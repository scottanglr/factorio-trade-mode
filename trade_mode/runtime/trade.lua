local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local entities = require("trade_mode.runtime.entities")
local inserter_stats = require("trade_mode.core.inserter_stats")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local runtime_state = require("trade_mode.runtime.state")
local util = require("trade_mode.core.util")

local trade = {}

local function player_record(player_index)
  local runtime = runtime_state.runtime()
  runtime.players[player_index] = runtime.players[player_index] or {
    player_index = player_index,
    name = "Player " .. tostring(player_index),
  }
  return runtime.players[player_index]
end

local function box_inventory(box_record)
  return entities.box_inventory(box_record.entity)
end

local function clear_manual_hint(box_id)
  runtime_state.runtime().manual_insertions[box_id] = nil
end

local function set_manual_hint(box_id, hint)
  runtime_state.runtime().manual_insertions[box_id] = hint
end

local function find_manual_source(box_id, order, tick)
  local hint = runtime_state.runtime().manual_insertions[box_id]
  if hint and hint.tick >= (tick - 2) and hint.item_name == order.item_name then
    clear_manual_hint(box_id)
    return {
      kind = "manual",
      player_index = hint.player_index,
    }
  end

  local matching = {}
  for player_index, record in pairs(runtime_state.runtime().players) do
    if record.opened_trade_box_id == box_id and record.last_inventory_change_tick and record.last_inventory_change_tick >= (tick - 2) then
      matching[#matching + 1] = player_index
    end
  end

  table.sort(matching)
  if #matching == 1 then
    return {
      kind = "manual",
      player_index = matching[1],
    }
  end

  return nil
end

local function find_automated_source(box_record, order, tick)
  local pending = entities.find_pending_inserter_owner(box_record, order, tick)
  if pending and pending.owner_player_index then
    return {
      kind = "inserter",
      player_index = pending.owner_player_index,
      inserter_record = pending,
    }
  end

  local nearby = entities.find_nearby_inserter_records(box_record)
  for _, inserter_record in ipairs(nearby) do
    if inserter_record.owner_player_index then
      return {
        kind = "inserter",
        player_index = inserter_record.owner_player_index,
        inserter_record = inserter_record,
      }
    end
  end

  return nil
end

local function refund_to_player(box_record, item_name, quantity, player_index)
  local inventory = box_inventory(box_record)
  inventory.remove({name = item_name, count = quantity})
  local player = game.players[player_index]
  if player and player.valid then
    local inserted = player.insert({name = item_name, count = quantity})
    if inserted < quantity then
      box_record.entity.surface.spill_item_stack({
        position = player.position,
        stack = {name = item_name, count = quantity - inserted},
        enable_looted = false,
      })
    end
  else
    box_record.entity.surface.spill_item_stack({
      position = box_record.entity.position,
      stack = {name = item_name, count = quantity},
      enable_looted = false,
    })
  end
end

local function refund_unknown_source(box_record, item_name, quantity)
  local inventory = box_inventory(box_record)
  inventory.remove({name = item_name, count = quantity})
  box_record.entity.surface.spill_item_stack({
    position = box_record.entity.position,
    stack = {name = item_name, count = quantity},
    enable_looted = false,
  })
end

local function refund_to_inserter_source(box_record, item_name, quantity, inserter_record)
  local inventory = box_inventory(box_record)
  inventory.remove({name = item_name, count = quantity})

  local inserter = inserter_record and inserter_record.entity
  if inserter and inserter.valid and inserter.pickup_target and inserter.pickup_target.valid then
    local target = inserter.pickup_target
    local target_inventory =
      target.get_inventory(defines.inventory.chest) or
      target.get_output_inventory() or
      target.get_inventory(defines.inventory.furnace_source) or
      target.get_inventory(defines.inventory.assembling_machine_input)

    if target_inventory and target_inventory.valid then
      local inserted = target_inventory.insert({name = item_name, count = quantity})
      if inserted == quantity then
        return
      end
      quantity = quantity - inserted
    end
  end

  local spill_position = inserter and inserter.valid and inserter.pickup_position or box_record.entity.position
  box_record.entity.surface.spill_item_stack({
    position = spill_position,
    stack = {name = item_name, count = quantity},
    enable_looted = false,
  })
end

local function reconcile_order_box(box_record, tick)
  if not box_record.entity.valid then
    entities.unregister_trade_box(box_record.box_id)
    return
  end

  local root = runtime_state.root()
  local order = orders.get_by_box_id(root.orders, box_record.box_id)
  if not order then
    box_record.tracked_item_count = 0
    box_record.last_known_item_name = nil
    entities.release_inserter_budget(box_record)
    return
  end

  box_record.last_known_item_name = order.item_name
  entities.sync_box_filters(box_record.box_id)
  entities.capture_inserter_candidates(box_record, order, tick)
  if order.status == "active" then
    entities.set_inserter_budget(box_record, order)
  else
    entities.release_inserter_budget(box_record)
  end

  local inventory = box_inventory(box_record)
  local current_count = inventory.get_item_count(order.item_name)
  local delta = current_count - (box_record.tracked_item_count or 0)
  if delta <= 0 then
    box_record.tracked_item_count = current_count
    return
  end

  local source = find_manual_source(box_record.box_id, order, tick)
  if not source then
    source = find_automated_source(box_record, order, tick)
  end

  if not source then
    refund_unknown_source(box_record, order.item_name, delta)
    box_record.tracked_item_count = inventory.get_item_count(order.item_name)
    return
  end

  local result = orders.settle_insert(root.orders, root.ledger, order.id, source.player_index, delta, tick)
  if result.ok then
    local current_second = runtime_state.current_second(tick)
    metrics.record_trade(root.metrics, current_second, result.total, order.buyer_id, source.player_index)
    metrics.set_snapshot_counts(
      root.metrics,
      orders.count_active(root.orders),
      contracts.count_openish(root.contracts)
    )
    if source.kind == "inserter" and source.inserter_record then
      inserter_stats.record_payout(
        root.inserter_stats,
        source.inserter_record.inserter_id,
        source.player_index,
        result.total,
        source.player_index,
        tick,
        box_record.box_id
      )
    end
  else
    if source.kind == "manual" then
      refund_to_player(box_record, order.item_name, delta, source.player_index)
    else
      refund_to_inserter_source(box_record, order.item_name, delta, source.inserter_record)
    end
  end

  box_record.tracked_item_count = inventory.get_item_count(order.item_name)
end

function trade.note_inventory_change(player_index, tick)
  player_record(player_index).last_inventory_change_tick = tick
end

function trade.note_trade_box_context(player_index, box_entity)
  local record = player_record(player_index)
  if box_entity and box_entity.valid and box_entity.name == constants.entity_name then
    record.opened_trade_box_id = util.id_key(box_entity.unit_number)
  else
    record.opened_trade_box_id = nil
  end
end

function trade.note_manual_insertion(player_index, box_entity, item_name, quantity, tick)
  if not box_entity or not box_entity.valid or box_entity.name ~= constants.entity_name then
    return
  end

  set_manual_hint(
    util.id_key(box_entity.unit_number),
    {
      player_index = player_index,
      item_name = item_name,
      quantity = quantity,
      tick = tick,
    }
  )
end

function trade.handle_player_drop_into_entity(event)
  if not event.entity or not event.entity.valid or event.entity.name ~= constants.entity_name then
    return
  end

  local root = runtime_state.root()
  local order = orders.get_by_box_id(root.orders, util.id_key(event.entity.unit_number))
  if not order then
    return
  end

  trade.note_manual_insertion(event.player_index, event.entity, order.item_name, 1, event.tick)
  trade.note_inventory_change(event.player_index, event.tick)
  reconcile_order_box(entities.register_trade_box(event.entity), event.tick)
end

function trade.handle_player_fast_transfer(event)
  if not event.entity or not event.entity.valid or event.entity.name ~= constants.entity_name or not event.from_player then
    return
  end

  local record = entities.register_trade_box(event.entity)
  local order = orders.get_by_box_id(runtime_state.root().orders, record.box_id)
  if not order then
    return
  end

  local inventory = box_inventory(record)
  local current_count = inventory.get_item_count(order.item_name)
  local delta = current_count - (record.tracked_item_count or 0)
  if delta > 0 then
    trade.note_manual_insertion(event.player_index, event.entity, order.item_name, delta, event.tick)
  end
  trade.note_inventory_change(event.player_index, event.tick)
  reconcile_order_box(record, event.tick)
end

function trade.reconcile_all_boxes(tick)
  local runtime = runtime_state.runtime()
  for _, box_record in pairs(runtime.trade_boxes) do
    reconcile_order_box(box_record, tick)
  end
end

return trade
