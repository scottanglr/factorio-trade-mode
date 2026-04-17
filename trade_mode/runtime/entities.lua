local constants = require("trade_mode.runtime.constants")
local format = require("trade_mode.runtime.format")
local ledger = require("trade_mode.core.ledger")
local orders = require("trade_mode.core.orders")
local runtime_state = require("trade_mode.runtime.state")
local util = require("trade_mode.core.util")

local entities = {}

local function is_trade_box(entity)
  return entity and entity.valid and entity.name == constants.entity_name
end

local function is_inserter(entity)
  return entity and entity.valid and entity.type == "inserter"
end

local function box_key(entity_or_id)
  if type(entity_or_id) == "table" then
    return util.id_key(entity_or_id.unit_number)
  end
  return util.id_key(entity_or_id)
end

local function ensure_box_record(entity)
  local runtime = runtime_state.runtime()
  local key = box_key(entity)
  local record = runtime.trade_boxes[key]
  if record == nil then
    record = {
      box_id = key,
      entity = entity,
      tracked_item_count = 0,
      last_known_item_name = nil,
    }
    runtime.trade_boxes[key] = record
  end

  record.entity = entity
  return record
end

local function ensure_inserter_record(entity)
  local runtime = runtime_state.runtime()
  local key = util.id_key(entity.unit_number)
  local record = runtime.inserters[key]
  if record == nil then
    record = {
      inserter_id = key,
      entity = entity,
      owner_player_index = nil,
      pending_box_id = nil,
      pending_item_name = nil,
      pending_count = 0,
      last_seen_tick = 0,
    }
    runtime.inserters[key] = record
  end

  record.entity = entity
  if entity.last_user and entity.last_user.valid then
    record.owner_player_index = entity.last_user.index
  end
  return record
end

local function box_inventory(entity)
  return entity.get_inventory(defines.inventory.chest)
end

local function destroy_tags_for_box(box_id)
  local runtime = runtime_state.runtime()
  local tags = runtime.market_tags[box_id]
  if tags == nil then
    return
  end

  for _, tag in pairs(tags) do
    if tag.valid then
      tag.destroy()
    end
  end
  runtime.market_tags[box_id] = nil
end

local function should_show_tags()
  return settings.global[constants.setting_enable_chart_tags].value
end

function entities.refresh_tags_for_box(box_id)
  local root = runtime_state.root()
  local record = root.runtime.trade_boxes[box_id]
  local order = orders.get_by_box_id(root.orders, box_id)
  if not record or not record.entity.valid or not order or order.status ~= "active" or not should_show_tags() then
    destroy_tags_for_box(box_id)
    return
  end

  destroy_tags_for_box(box_id)
  local tags = {}
  local buyer_player = game.get_player(order.buyer_id)
  local force = record.entity.force
  local tag_spec = {
    position = record.entity.position,
    icon = {type = "item", name = order.item_name},
    text = tostring(order.unit_price),
  }
  if buyer_player and buyer_player.valid then
    tag_spec.last_user = buyer_player
  end
  tags[force.name] = force.add_chart_tag(record.entity.surface, tag_spec)
  root.runtime.market_tags[box_id] = tags
end

function entities.refresh_all_tags()
  for box_id in pairs(runtime_state.runtime().trade_boxes) do
    entities.refresh_tags_for_box(box_id)
  end
end

function entities.register_trade_box(entity)
  if not is_trade_box(entity) or not entity.unit_number then
    return nil
  end

  local record = ensure_box_record(entity)
  entities.sync_box_filters(record.box_id)
  local order = orders.get_by_box_id(runtime_state.root().orders, record.box_id)
  if order then
    record.last_known_item_name = order.item_name
    record.tracked_item_count = box_inventory(entity).get_item_count(order.item_name)
  else
    record.last_known_item_name = nil
    record.tracked_item_count = 0
  end
  entities.refresh_tags_for_box(record.box_id)
  return record
end

function entities.unregister_trade_box(entity_or_id)
  local key = box_key(entity_or_id)
  local order = orders.get_by_box_id(runtime_state.root().orders, key)
  if order and order.status ~= "cancelled" then
    orders.cancel_order(runtime_state.root().orders, order.id, game.tick)
  end
  destroy_tags_for_box(key)
  runtime_state.runtime().trade_boxes[key] = nil
end

function entities.register_inserter(entity)
  if not is_inserter(entity) or not entity.unit_number then
    return nil
  end
  return ensure_inserter_record(entity)
end

function entities.find_nearby_inserter_records(box_record)
  local entity = box_record.entity
  if not entity.valid then
    return {}
  end

  local results = {}
  local area = {
    {entity.position.x - 2, entity.position.y - 2},
    {entity.position.x + 2, entity.position.y + 2},
  }
  local found = entity.surface.find_entities_filtered({area = area, type = "inserter"})
  for _, inserter in ipairs(found) do
    local targets_box = inserter.drop_target == entity
    local drop_position = inserter.drop_position
    if not targets_box then
      targets_box =
        math.abs(drop_position.x - entity.position.x) <= 0.6 and
        math.abs(drop_position.y - entity.position.y) <= 0.6
    end

    if targets_box then
      results[#results + 1] = ensure_inserter_record(inserter)
    end
  end

  table.sort(results, function(left, right)
    return left.inserter_id < right.inserter_id
  end)
  return results
end

function entities.capture_inserter_candidates(box_record, order, tick)
  local candidates = entities.find_nearby_inserter_records(box_record)
  for _, inserter_record in ipairs(candidates) do
    local inserter = inserter_record.entity
    if inserter.valid and inserter.held_stack.valid_for_read and inserter.held_stack.name == order.item_name then
      inserter_record.pending_box_id = box_record.box_id
      inserter_record.pending_item_name = order.item_name
      inserter_record.pending_count = inserter.held_stack.count
      inserter_record.last_seen_tick = tick
    end
  end
  return candidates
end

function entities.find_pending_inserter_owner(box_record, order, tick)
  local candidates = entities.find_nearby_inserter_records(box_record)
  local chosen = nil
  for _, record in ipairs(candidates) do
    if
      record.pending_box_id == box_record.box_id and
      record.pending_item_name == order.item_name and
      record.last_seen_tick >= (tick - 2)
    then
      if chosen == nil or record.last_seen_tick > chosen.last_seen_tick then
        chosen = record
      end
    end
  end
  return chosen
end

function entities.set_inserter_budget(box_record, order)
  local buyer_balance = ledger.get_balance(runtime_state.root().ledger, order.buyer_id)
  local nearby = entities.find_nearby_inserter_records(box_record)
  local max_units = math.floor(buyer_balance / order.unit_price)

  for _, inserter_record in ipairs(nearby) do
    local inserter = inserter_record.entity
    if inserter.valid then
      local held_count = 0
      if inserter.held_stack.valid_for_read and inserter.held_stack.name == order.item_name then
        held_count = inserter.held_stack.count
      end

      if max_units <= 0 or (held_count > 0 and held_count > max_units) then
        inserter.disabled_by_script = true
      else
        inserter.disabled_by_script = false
        inserter.inserter_stack_size_override = math.max(1, max_units)
      end
    end
  end
end

function entities.release_inserter_budget(box_record)
  for _, inserter_record in ipairs(entities.find_nearby_inserter_records(box_record)) do
    local inserter = inserter_record.entity
    if inserter.valid then
      inserter.disabled_by_script = false
      inserter.inserter_stack_size_override = 0
    end
  end
end

function entities.sync_box_filters(box_id)
  local root = runtime_state.root()
  local box_record = root.runtime.trade_boxes[box_id]
  if not box_record or not box_record.entity.valid then
    return
  end

  local inventory = box_inventory(box_record.entity)
  if not inventory.supports_filters() then
    return
  end

  local order = orders.get_by_box_id(root.orders, box_id)
  local item_name = order and order.item_name or nil
  for slot = 1, #inventory do
    if item_name == nil or inventory.can_set_filter(slot, item_name) then
      inventory.set_filter(slot, item_name)
    end
  end
end

function entities.describe_box(box_id)
  local record = runtime_state.runtime().trade_boxes[box_id]
  if not record or not record.entity.valid then
    return "Missing box"
  end
  return format.position(record.entity)
end

function entities.box_inventory(entity)
  return box_inventory(entity)
end

return entities
