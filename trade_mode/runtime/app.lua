local commands_runtime = require("trade_mode.runtime.commands")
local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local economy = require("trade_mode.runtime.economy")
local entities = require("trade_mode.runtime.entities")
local gui = require("trade_mode.runtime.gui")
local ledger = require("trade_mode.core.ledger")
local notifications = require("trade_mode.runtime.notifications")
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

local function scan_existing_inserters()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({type = "inserter"})) do
      entities.register_inserter(entity)
    end
  end
end

local function initialize_players()
  for _, player in pairs(game.players) do
    runtime_state.track_player(player)
    runtime_state.ensure_player_wallet(player.index)
    runtime_state.migrate_legacy_player_wallet(player.index)
    gui.refresh_context_panels(player)
  end
end

local function initialize_force_wallets()
  for _, force in pairs(game.forces) do
    runtime_state.ensure_force_wallet(force.name)
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
  if not entity then
    return
  end

  local unit_number = nil
  local unit_number_ok = pcall(function()
    unit_number = entity.unit_number
  end)
  local entity_id = unit_number_ok and unit_number and util.id_key(unit_number) or nil
  local runtime = runtime_state.runtime()

  if entity_id and runtime.trade_boxes[entity_id] then
    entities.unregister_trade_box(entity_id)
    return
  end

  if entity_id and runtime.inserters[entity_id] then
    runtime.inserters[entity_id] = nil
    return
  end

  if entity.valid and entity.name == constants.entity_name then
    entities.unregister_trade_box(entity)
  elseif entity.valid and entity.type == "inserter" and entity_id then
    runtime.inserters[entity_id] = nil
  end
end

local function handle_player_created(event)
  local player = game.players[event.player_index]
  runtime_state.track_player(player)
  runtime_state.ensure_player_wallet(player.index)
  runtime_state.migrate_legacy_player_wallet(player.index)
  gui.refresh_context_panels(player)
end

local function handle_player_joined(event)
  local player = game.players[event.player_index]
  runtime_state.track_player(player)
  runtime_state.ensure_player_wallet(player.index)
  runtime_state.migrate_legacy_player_wallet(player.index)
  gui.refresh_context_panels(player)
end

local function handle_player_changed_force(event)
  local player = game.players[event.player_index]
  runtime_state.track_player(player)
  runtime_state.ensure_player_wallet(player.index)
  runtime_state.migrate_legacy_player_wallet(player.index)
  gui.refresh_context_panels(player)
end

local function handle_force_created(event)
  if event.force and event.force.valid then
    runtime_state.ensure_force_wallet(event.force.name)
  end
end

local function handle_forces_merged(event)
  if event and event.source_name and event.destination and event.destination.valid then
    runtime_state.merge_force_wallets(event.source_name, event.destination.name)
  end
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
  gui.refresh_context_panels(player)
end

local function handle_gui_closed(event)
  local player = game.players[event.player_index]
  gui.hide_trade_box_panel(player)
  trade.note_trade_box_context(player.index, nil)
  gui.refresh_context_panels(player)
end

local function handle_shortcut(event)
  if event.prototype_name ~= constants.shortcut_name then
    return
  end
  gui.toggle_main(game.players[event.player_index])
end

local function handle_custom_input(event)
  if event.input_name ~= constants.custom_input_name then
    return
  end
  gui.toggle_main(game.players[event.player_index])
end

local function find_descendant(root, name)
  if not root or not root.valid then
    return nil
  end

  if root.name == name then
    return root
  end

  for _, child in ipairs(root.children) do
    local match = find_descendant(child, name)
    if match then
      return match
    end
  end

  return nil
end

local function handle_chunk_charted(event)
  if not settings.global[constants.setting_enable_chart_tags].value then
    return
  end

  entities.refresh_tags_in_area(event.surface_index, event.force.name, event.area)
end

local function handle_runtime_mod_setting_changed(event)
  if event.setting ~= constants.setting_enable_chart_tags or event.setting_type ~= "runtime-global" then
    return
  end

  entities.refresh_all_tags()
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
      for account_id, balance in pairs(state.ledger.balances) do
        if type(account_id) == "number" then
          balances[tostring(account_id)] = balance
        end
      end
      for player_id in pairs(state.runtime.players) do
        balances[tostring(player_id)] = runtime_state.player_balance(player_id)
      end

      local wallet_balances = {}
      for account_id, balance in pairs(state.ledger.balances) do
        wallet_balances[tostring(account_id)] = balance
      end

      local order_rows = {}
      for _, order in ipairs(orders.list_current(state.orders)) do
        order_rows[#order_rows + 1] = {
          id = order.id,
          box_id = order.box_id,
          buyer_id = order.buyer_id,
          buyer_wallet_id = order.buyer_wallet_id,
          item_name = order.item_name,
          unit_price = order.unit_price,
          status = order.status,
          last_trade_unit_price = order.last_trade_unit_price,
          total_traded = order.total_traded,
          total_units_traded = order.total_units_traded,
          first_fill_notified = order.first_fill_notified,
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
          pending_unit_price = record.pending_unit_price,
          min_unit_price = record.min_unit_price,
        }
      end
      table.sort(tracked_inserters, function(left, right)
        return left.inserter_id < right.inserter_id
      end)

      return {
        balances = balances,
        wallet_balances = wallet_balances,
        orders = order_rows,
        tracked_trade_boxes = tracked_trade_boxes,
        tracked_inserters = tracked_inserters,
        economy = state.runtime.economy_snapshot,
        economy_by_force = state.runtime.economy_snapshots,
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
      ledger.credit(runtime_state.root().ledger, runtime_state.wallet_id_for_player(player_index), amount, "remote_test_credit")
    end,
    create_order = function(box_unit_number, buyer_id, item_name, unit_price)
      local box_id = util.id_key(box_unit_number)
      local buyer = game.get_player(buyer_id)
      local force_name = buyer and buyer.valid and buyer.force.name or runtime_state.player_force_name(buyer_id)
      local created = orders.create_order(runtime_state.root().orders, {
        box_id = box_id,
        buyer_id = buyer_id,
        buyer_wallet_id = runtime_state.wallet_id_for_player(buyer_id),
        force_name = force_name,
        item_name = item_name,
        unit_price = unit_price,
        tick = game.tick,
      })
      if created.ok then
        local record = runtime_state.runtime().trade_boxes[box_id]
        local entity = record and record.entity
        if entity and entity.valid then
          entities.register_trade_box(entity)
        else
          entities.sync_box_filters(box_id)
          entities.refresh_tags_for_box(box_id)
        end
      end
      return created
    end,
    update_order_price = function(box_unit_number, unit_price)
      local box_id = util.id_key(box_unit_number)
      local order = orders.get_by_box_id(runtime_state.root().orders, box_id)
      if not order then
        return {
          ok = false,
          error = "order_not_found",
        }
      end
      local updated = orders.update_order(runtime_state.root().orders, order.id, {
        unit_price = unit_price,
        tick = game.tick,
      })
      if updated.ok then
        entities.refresh_tags_for_box(box_id)
      end
      return updated
    end,
    create_contract = function(creator_id, title, description, amount)
      local creator = game.get_player(creator_id)
      local force_name = creator and creator.valid and creator.force.name or runtime_state.player_force_name(creator_id)
      return contracts.create_contract(runtime_state.root().contracts, {
        creator_id = creator_id,
        creator_wallet_id = runtime_state.wallet_id_for_player(creator_id),
        force_name = force_name,
        title = title,
        description = description,
        amount = amount,
        tick = game.tick,
      })
    end,
    assign_contract = function(contract_id, player_id)
      local player = game.get_player(player_id)
      local result = contracts.assign_self(
        runtime_state.root().contracts,
        contract_id,
        player_id,
        game.tick,
        player and player.valid and player.force.name or runtime_state.player_force_name(player_id),
        runtime_state.wallet_id_for_player(player_id)
      )
      if result.ok then
        notifications.notify_contract_assigned(result.contract, player_id)
      end
      return result
    end,
    unassign_contract = function(contract_id, player_id)
      local player = game.get_player(player_id)
      return contracts.unassign_self(
        runtime_state.root().contracts,
        contract_id,
        player_id,
        game.tick,
        player and player.valid and player.force.name or nil
      )
    end,
    pay_contract = function(contract_id, actor_id)
      local player = game.get_player(actor_id)
      return contracts.payout(
        runtime_state.root().contracts,
        runtime_state.root().ledger,
        contract_id,
        actor_id,
        game.tick,
        player and player.valid and player.force.name or nil
      )
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
    test_set_inserter_min_price = function(inserter_unit_number, min_unit_price)
      local record = runtime_state.runtime().inserters[util.id_key(inserter_unit_number)]
      local entity = record and record.entity
      if not entity or not entity.valid then
        return {
          ok = false,
          error = "entity_not_found",
        }
      end

      return entities.set_inserter_min_price(entity, min_unit_price)
    end,
    test_set_player_force = function(player_index, force_name)
      runtime_state.set_tracked_player_force(player_index, force_name)
      runtime_state.ensure_force_wallet(force_name)
      return {
        ok = true,
        wallet_id = runtime_state.wallet_id_for_player(player_index),
      }
    end,
    test_toggle_main_ui = function(player_index)
      local player = game.get_player(player_index)
      if not player or not player.valid then
        local item_name = "iron-ore"
        local item_sprite = "item/" .. item_name
        return {
          ok = prototypes.item[item_name] ~= nil
            and helpers.is_valid_sprite_path("utility/close")
            and helpers.is_valid_sprite_path("utility/close_black")
            and helpers.is_valid_sprite_path(item_sprite),
          skipped = true,
          reason = "player_not_found",
          fallback = {
            item_name = item_name,
            item_prototype_present = prototypes.item[item_name] ~= nil,
            item_sprite_valid = helpers.is_valid_sprite_path(item_sprite),
            close_sprite_valid = helpers.is_valid_sprite_path("utility/close"),
            close_black_sprite_valid = helpers.is_valid_sprite_path("utility/close_black"),
          },
        }
      end

      local opened, open_error = pcall(gui.toggle_main, player)
      if not opened then
        return {
          ok = false,
          error = open_error,
        }
      end

      local frame = player.gui.screen[constants.gui.screen_root]
      local present = {
        frame = frame ~= nil,
        main_tabs = find_descendant(frame, constants.gui.main_tabs) ~= nil,
      }

      local closed, close_error = pcall(gui.toggle_main, player)
      if not closed then
        return {
          ok = false,
          error = close_error,
          present = present,
        }
      end

      return {
        ok = present.frame and present.main_tabs and player.gui.screen[constants.gui.screen_root] == nil,
        present = present,
      }
    end,
  })
end

function app.register()
  commands_runtime.register()
  add_remote_interface()

  script.on_init(function()
    runtime_state.root()
    initialize_force_wallets()
    initialize_players()
    scan_existing_trade_boxes()
    scan_existing_inserters()
    entities.refresh_all_tags()
  end)

  script.on_configuration_changed(function()
    runtime_state.root()
    initialize_force_wallets()
    initialize_players()
    scan_existing_trade_boxes()
    scan_existing_inserters()
    entities.refresh_all_tags()
  end)

  script.on_event(defines.events.on_player_created, handle_player_created)
  script.on_event(defines.events.on_player_joined_game, handle_player_joined)
  script.on_event(defines.events.on_player_changed_force, handle_player_changed_force)
  script.on_event(defines.events.on_force_created, handle_force_created)
  script.on_event(defines.events.on_forces_merged, handle_forces_merged)
  script.on_event(defines.events.on_built_entity, handle_built_entity, tracked_entity_filters)
  script.on_event(defines.events.on_robot_built_entity, handle_built_entity, tracked_entity_filters)
  script.on_event(defines.events.on_space_platform_built_entity, handle_built_entity, tracked_entity_filters)
  script.on_event(defines.events.script_raised_built, handle_built_entity, tracked_entity_filters)
  script.on_event(defines.events.script_raised_revive, handle_built_entity, tracked_entity_filters)
  script.on_event(defines.events.on_pre_player_mined_item, handle_removed_entity, tracked_entity_filters)
  script.on_event(defines.events.on_robot_pre_mined, handle_removed_entity, tracked_entity_filters)
  script.on_event(defines.events.on_space_platform_pre_mined, handle_removed_entity, tracked_entity_filters)
  script.on_event(defines.events.on_entity_died, handle_removed_entity, tracked_entity_filters)
  script.on_event(defines.events.script_raised_destroy, handle_removed_entity, tracked_entity_filters)
  script.on_event(defines.events.on_selected_entity_changed, handle_selected_entity_changed)
  script.on_event(defines.events.on_gui_opened, handle_gui_opened)
  script.on_event(defines.events.on_gui_closed, handle_gui_closed)
  script.on_event(defines.events.on_gui_click, gui.handle_click)
  script.on_event(defines.events.on_gui_selected_tab_changed, gui.handle_selected_tab_changed)
  script.on_event(defines.events.on_gui_selection_state_changed, gui.handle_selection_state_changed)
  script.on_event(defines.events.on_gui_text_changed, gui.handle_text_changed)
  script.on_event(defines.events.on_gui_elem_changed, gui.handle_elem_changed)
  script.on_event(defines.events.on_lua_shortcut, handle_shortcut)
  script.on_event(constants.custom_input_name, handle_custom_input)
  script.on_event(defines.events.on_chunk_charted, handle_chunk_charted)
  script.on_event(defines.events.on_runtime_mod_setting_changed, handle_runtime_mod_setting_changed)
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
