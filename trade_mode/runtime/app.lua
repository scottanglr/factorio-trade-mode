local commands_runtime = require("trade_mode.runtime.commands")
local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local economy = require("trade_mode.runtime.economy")
local entities = require("trade_mode.runtime.entities")
local gui = require("trade_mode.runtime.gui")
local ledger = require("trade_mode.core.ledger")
local orders = require("trade_mode.core.orders")
local runtime_state = require("trade_mode.runtime.state")
local trade = require("trade_mode.runtime.trade")
local util = require("trade_mode.core.util")

local app = {}

local function built_entity_from_event(event)
  return event.entity or event.created_entity or event.destination
end

local function scan_existing_trade_boxes()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({name = constants.entity_name})) do
      entities.register_trade_box(entity)
    end
  end
end

local function initialize_players()
  for _, player in pairs(game.players) do
    runtime_state.track_player(player)
    ledger.create_account(runtime_state.root().ledger, player.index)
  end
end

local function handle_built_entity(event)
  local entity = built_entity_from_event(event)
  if not entity or not entity.valid then
    return
  end

  if entity.name == constants.entity_name then
    entities.register_trade_box(entity)
  elseif entity.type == "inserter" then
    entities.register_inserter(entity)
  end
end

local function handle_removed_entity(event)
  local entity = event.entity
  if not entity or not entity.valid then
    return
  end

  if entity.name == constants.entity_name then
    entities.unregister_trade_box(entity)
  elseif entity.type == "inserter" and entity.unit_number then
    runtime_state.runtime().inserters[util.id_key(entity.unit_number)] = nil
  end
end

local function handle_player_created(event)
  local player = game.players[event.player_index]
  runtime_state.track_player(player)
  ledger.create_account(runtime_state.root().ledger, player.index)
end

local function handle_player_joined(event)
  local player = game.players[event.player_index]
  runtime_state.track_player(player)
  ledger.create_account(runtime_state.root().ledger, player.index)
  gui.refresh_context_panels(player)
end

local function handle_selected_entity_changed(event)
  local player = game.players[event.player_index]
  gui.show_selected_inserter(player)
end

local function handle_gui_opened(event)
  local player = game.players[event.player_index]
  local entity = event.entity
  if entity and entity.valid and entity.name == constants.entity_name then
    entities.register_trade_box(entity)
    gui.show_trade_box_panel(player, entity)
  else
    gui.hide_trade_box_panel(player)
    trade.note_trade_box_context(player.index, nil)
  end
end

local function handle_gui_closed(event)
  local player = game.players[event.player_index]
  gui.hide_trade_box_panel(player)
  trade.note_trade_box_context(player.index, nil)
end

local function handle_shortcut(event)
  if event.prototype_name ~= constants.shortcut_name then
    return
  end
  gui.toggle_main(game.players[event.player_index])
end

local tracked_entity_filters = {
  {filter = "name", name = constants.entity_name},
  {filter = "type", type = "inserter"},
}

local function add_remote_interface()
  remote.add_interface(constants.mod_name, {
    state_snapshot = function()
      local state = runtime_state.root()
      local balances = {}
      for player_id, balance in pairs(state.ledger.balances) do
        balances[tostring(player_id)] = balance
      end

      local order_rows = {}
      for _, order in ipairs(orders.list_current(state.orders)) do
        order_rows[#order_rows + 1] = {
          id = order.id,
          box_id = order.box_id,
          buyer_id = order.buyer_id,
          item_name = order.item_name,
          unit_price = order.unit_price,
          status = order.status,
          total_traded = order.total_traded,
        }
      end

      local tracked_trade_boxes = {}
      for box_id in pairs(state.runtime.trade_boxes) do
        tracked_trade_boxes[#tracked_trade_boxes + 1] = box_id
      end
      table.sort(tracked_trade_boxes)

      local tracked_inserters = {}
      for inserter_id, record in pairs(state.runtime.inserters) do
        tracked_inserters[#tracked_inserters + 1] = {
          inserter_id = inserter_id,
          owner_player_index = record.owner_player_index,
          pending_box_id = record.pending_box_id,
          pending_item_name = record.pending_item_name,
          pending_count = record.pending_count,
        }
      end
      table.sort(tracked_inserters, function(left, right)
        return left.inserter_id < right.inserter_id
      end)

      return {
        balances = balances,
        orders = order_rows,
        tracked_trade_boxes = tracked_trade_boxes,
        tracked_inserters = tracked_inserters,
        economy = state.runtime.economy_snapshot,
        inserter_stats = state.inserter_stats.by_id,
        reports = {
          trade_status = commands_runtime.render_trade_status(),
          trade_money_last_minute = commands_runtime.render_trade_money_last_minute(),
          trade_ubi_last_minute = commands_runtime.render_trade_ubi_last_minute(),
          trade_orders = commands_runtime.render_trade_orders(),
          trade_contracts = commands_runtime.render_trade_contracts(),
        },
      }
    end,
    credit_player = function(player_index, amount)
      ledger.credit(runtime_state.root().ledger, player_index, amount, "remote_test_credit")
    end,
    create_order = function(box_unit_number, buyer_id, item_name, unit_price)
      local box_id = util.id_key(box_unit_number)
      local created = orders.create_order(runtime_state.root().orders, {
        box_id = box_id,
        buyer_id = buyer_id,
        item_name = item_name,
        unit_price = unit_price,
        tick = game.tick,
      })
      if created.ok then
        entities.sync_box_filters(box_id)
        entities.refresh_tags_for_box(box_id)
      end
      return created
    end,
    create_contract = function(creator_id, title, description, amount)
      return contracts.create_contract(runtime_state.root().contracts, {
        creator_id = creator_id,
        title = title,
        description = description,
        amount = amount,
        tick = game.tick,
      })
    end,
    assign_contract = function(contract_id, player_id)
      return contracts.assign_self(runtime_state.root().contracts, contract_id, player_id, game.tick)
    end,
    unassign_contract = function(contract_id, player_id)
      return contracts.unassign_self(runtime_state.root().contracts, contract_id, player_id, game.tick)
    end,
    pay_contract = function(contract_id, actor_id)
      return contracts.payout(runtime_state.root().contracts, runtime_state.root().ledger, contract_id, actor_id, game.tick)
    end,
    reconcile_now = function()
      trade.reconcile_all_boxes(game.tick)
    end,
    tick_second_now = function()
      economy.tick_second(runtime_state.current_second(game.tick))
    end,
    test_note_manual_insertion = function(box_unit_number, player_index, item_name, quantity)
      local record = runtime_state.runtime().trade_boxes[util.id_key(box_unit_number)]
      local entity = record and record.entity
      if not entity or not entity.valid then
        return {
          ok = false,
          error = "entity_not_found",
        }
      end

      trade.note_manual_insertion(player_index, entity, item_name, quantity, game.tick)
      trade.note_inventory_change(player_index, game.tick)
      return {
        ok = true,
      }
    end,
    test_set_inserter_owner = function(inserter_unit_number, owner_player_index)
      local record = runtime_state.runtime().inserters[util.id_key(inserter_unit_number)]
      local entity = record and record.entity
      if not entity or not entity.valid then
        return {
          ok = false,
          error = "entity_not_found",
        }
      end

      entities.register_inserter(entity).owner_player_index = owner_player_index
      return {
        ok = true,
      }
    end,
  })
end

function app.register()
  commands_runtime.register()
  add_remote_interface()

  script.on_init(function()
    runtime_state.root()
    initialize_players()
    scan_existing_trade_boxes()
    entities.refresh_all_tags()
  end)

  script.on_configuration_changed(function()
    runtime_state.root()
    initialize_players()
    scan_existing_trade_boxes()
    entities.refresh_all_tags()
  end)

  script.on_event(defines.events.on_player_created, handle_player_created)
  script.on_event(defines.events.on_player_joined_game, handle_player_joined)
  script.on_event(defines.events.on_built_entity, handle_built_entity, tracked_entity_filters)
  script.on_event(defines.events.on_robot_built_entity, handle_built_entity, tracked_entity_filters)
  script.on_event(defines.events.script_raised_built, handle_built_entity, tracked_entity_filters)
  script.on_event(defines.events.on_pre_player_mined_item, handle_removed_entity, tracked_entity_filters)
  script.on_event(defines.events.on_robot_pre_mined, handle_removed_entity, tracked_entity_filters)
  script.on_event(defines.events.on_entity_died, handle_removed_entity, tracked_entity_filters)
  script.on_event(defines.events.on_selected_entity_changed, handle_selected_entity_changed)
  script.on_event(defines.events.on_gui_opened, handle_gui_opened)
  script.on_event(defines.events.on_gui_closed, handle_gui_closed)
  script.on_event(defines.events.on_gui_click, gui.handle_click)
  script.on_event(defines.events.on_gui_selected_tab_changed, gui.handle_selected_tab_changed)
  script.on_event(defines.events.on_gui_selection_state_changed, gui.handle_selection_state_changed)
  script.on_event(defines.events.on_gui_text_changed, gui.handle_text_changed)
  script.on_event(defines.events.on_gui_elem_changed, gui.handle_elem_changed)
  script.on_event(defines.events.on_lua_shortcut, handle_shortcut)
  script.on_event(defines.events.on_player_dropped_item_into_entity, trade.handle_player_drop_into_entity)
  script.on_event(defines.events.on_player_fast_transferred, trade.handle_player_fast_transfer)
  script.on_event(defines.events.on_player_main_inventory_changed, function(event)
    trade.note_inventory_change(event.player_index, event.tick)
  end)

  script.on_nth_tick(1, function(event)
    trade.reconcile_all_boxes(event.tick)
  end)
  script.on_nth_tick(constants.ticks.second, function(event)
    economy.tick_second(runtime_state.current_second(event.tick))
  end)
  script.on_nth_tick(constants.ticks.ui_refresh, function()
    for _, player in pairs(game.connected_players) do
      gui.refresh_context_panels(player)
    end
  end)
end

return app
