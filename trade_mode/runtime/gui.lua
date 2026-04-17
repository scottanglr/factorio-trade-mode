local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local economy = require("trade_mode.runtime.economy")
local entities = require("trade_mode.runtime.entities")
local format = require("trade_mode.runtime.format")
local inserter_stats = require("trade_mode.core.inserter_stats")
local ledger = require("trade_mode.core.ledger")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local pricing = require("trade_mode.core.pricing")
local runtime_state = require("trade_mode.runtime.state")
local util = require("trade_mode.core.util")
local trade = require("trade_mode.runtime.trade")

local gui = {}

local function root()
  return runtime_state.root()
end

local function ui_state(player_index)
  local runtime = runtime_state.runtime()
  runtime.player_ui[player_index] = runtime.player_ui[player_index] or {
    market_filter = "",
    selected_contract_id = nil,
  }
  return runtime.player_ui[player_index]
end

local function destroy_if_present(container, name)
  if container[name] then
    container[name].destroy()
  end
end

local function find_descendant(root_element, target_name)
  if not root_element or not root_element.valid then
    return nil
  end

  if root_element.name == target_name then
    return root_element
  end

  for _, child in pairs(root_element.children) do
    local found = find_descendant(child, target_name)
    if found then
      return found
    end
  end

  return nil
end

local function clear_children(element)
  for _, child in pairs(element.children) do
    child.destroy()
  end
end

local function parse_numeric_text(text)
  local number = tonumber(text)
  if not number or number <= 0 or number ~= math.floor(number) then
    return nil
  end
  return number
end

local function current_box_record(player)
  local record = runtime_state.runtime().players[player.index]
  if not record or not record.opened_trade_box_id then
    return nil
  end
  return runtime_state.runtime().trade_boxes[record.opened_trade_box_id]
end

local function buy_order_panel(player)
  return player.gui.left[constants.gui.trade_box_root]
end

local function inserter_panel(player)
  return player.gui.left[constants.gui.inserter_panel]
end

local function main_frame(player)
  return player.gui.screen[constants.gui.screen_root]
end

local function refresh_trade_box_panel(player)
  local frame = buy_order_panel(player)
  if not frame then
    return
  end

  local box_record = current_box_record(player)
  if not box_record or not box_record.entity.valid then
    frame.destroy()
    return
  end

  local order = orders.get_by_box_id(root().orders, box_record.box_id)
  local item_picker = frame[constants.gui.buy_order_item]
  local price_field = frame[constants.gui.buy_order_price]
  local suggested_label = frame["trade_mode_suggested_price_label"]
  local status_label = frame["trade_mode_status_label"]

  if order then
    item_picker.elem_value = order.item_name
    price_field.text = tostring(order.unit_price)
    status_label.caption = "Status: " .. order.status:gsub("^%l", string.upper)
  else
    status_label.caption = "Status: Invalid"
  end

  local selected_item = item_picker.elem_value
  if selected_item then
    local suggested = pricing.get_suggested_price(require("src.suggested-prices-config"), selected_item)
    if suggested then
      suggested_label.caption = "Suggested price: " .. suggested
    else
      suggested_label.caption = "Suggested price: n/a"
    end
  else
    suggested_label.caption = "Suggested price: n/a"
  end
end

local function refresh_inserter_panel(player)
  local frame = inserter_panel(player)
  if not frame then
    return
  end

  local selected = player.selected
  if not selected or not selected.valid or selected.type ~= "inserter" then
    frame.destroy()
    return
  end

  local stats = inserter_stats.get(root().inserter_stats, selected.unit_number)
  local content = frame["trade_mode_inserter_content"]
  clear_children(content)
  content.add({type = "label", caption = "Lifetime Trade Payout: " .. (stats and stats.lifetime_payout or 0)})
  content.add({
    type = "label",
    caption = "Last Recipient: " .. (stats and stats.last_recipient_id and runtime_state.player_name(stats.last_recipient_id) or "None"),
  })
  content.add({
    type = "label",
    caption = "Last Trade: " .. (stats and format.tick_age(game.tick, stats.last_trade_tick) or "Never"),
  })
end

local function filtered_orders(player)
  local filter_text = string.lower(ui_state(player.index).market_filter or "")
  local list = {}
  for _, order in ipairs(orders.list_current(root().orders)) do
    if filter_text == "" or string.find(string.lower(order.item_name), filter_text, 1, true) then
      list[#list + 1] = order
    end
  end
  return list
end

local function refresh_market_tab(player, container)
  clear_children(container)

  local filter_flow = container.add({type = "flow", direction = "horizontal"})
  filter_flow.add({type = "label", caption = "Item Filter"})
  filter_flow.add({
    type = "textfield",
    name = constants.gui.market_filter,
    text = ui_state(player.index).market_filter or "",
  })

  local table_element = container.add({type = "table", column_count = 5})
  table_element.add({type = "label", caption = "Item"})
  table_element.add({type = "label", caption = "Unit Price"})
  table_element.add({type = "label", caption = "Buyer"})
  table_element.add({type = "label", caption = "Box Location"})
  table_element.add({type = "label", caption = "Last Trade"})

  for _, order in ipairs(filtered_orders(player)) do
    table_element.add({type = "label", caption = order.item_name})
    table_element.add({type = "label", caption = tostring(order.unit_price)})
    table_element.add({type = "label", caption = runtime_state.player_name(order.buyer_id)})
    table_element.add({type = "label", caption = entities.describe_box(order.box_id)})
    table_element.add({type = "label", caption = format.tick_age(game.tick, order.last_trade_tick)})
  end
end

local function refresh_contracts_tab(player, container)
  clear_children(container)
  local state = root()
  local ui = ui_state(player.index)
  local horizontal = container.add({type = "flow", direction = "horizontal"})

  local left = horizontal.add({type = "scroll-pane", direction = "vertical"})
  left.style.minimal_width = 280
  left.style.maximal_height = 420
  for _, contract in ipairs(contracts.list_all(state.contracts)) do
    local label = string.format(
      "#%d %s (%s)",
      contract.id,
      contract.title,
      contract.status
    )
    left.add({
      type = "button",
      name = constants.gui.contract_list_prefix .. contract.id,
      caption = label,
    })
  end

  local right = horizontal.add({type = "flow", direction = "vertical"})
  right.style.minimal_width = 360

  right.add({type = "label", caption = "Create Contract"})
  right.add({
    type = "textfield",
    name = constants.gui.contract_title,
    text = "",
  })
  right.add({
    type = "text-box",
    name = constants.gui.contract_description,
    text = "",
  })
  right.add({
    type = "textfield",
    name = constants.gui.contract_amount,
    text = "",
  })
  right.add({
    type = "button",
    name = constants.gui.contract_create,
    caption = "Create Contract",
  })

  local selected = ui.selected_contract_id and contracts.get_by_id(state.contracts, ui.selected_contract_id) or nil
  right.add({type = "line"})
  right.add({type = "label", caption = "Selected Contract"})
  if selected then
    right.add({type = "label", caption = "Title: " .. selected.title})
    right.add({type = "label", caption = "Creator: " .. runtime_state.player_name(selected.creator_id)})
    right.add({type = "label", caption = "Amount: " .. selected.amount})
    right.add({type = "label", caption = "Assignee: " .. (selected.assignee_id and runtime_state.player_name(selected.assignee_id) or "Unassigned")})
    right.add({type = "label", caption = "Status: " .. selected.status})
    right.add({type = "label", caption = selected.description})

    local current_player_id = player.index
    if selected.creator_id ~= current_player_id and selected.status ~= "completed" then
      if selected.assignee_id == current_player_id then
        right.add({type = "button", name = constants.gui.contract_unassign, caption = "Unassign"})
      else
        right.add({type = "button", name = constants.gui.contract_assign, caption = "Assign to Me"})
      end
    end

    if selected.creator_id == current_player_id and selected.assignee_id ~= nil and selected.status == "assigned" then
      right.add({type = "button", name = constants.gui.contract_pay, caption = "Pay Assignee"})
    end
  else
    right.add({type = "label", caption = "No contract selected."})
  end
end

local function refresh_economy_tab(container)
  clear_children(container)
  local snapshot = economy.snapshot()
  local second = runtime_state.current_second(game.tick)
  local state = root()

  container.add({type = "label", caption = string.format("gold_per_second: %.2f", snapshot.gold_per_second)})
  container.add({type = "label", caption = string.format("recent_raw_ore_per_minute: %.2f", snapshot.recent_raw_ore_per_minute)})
  container.add({type = "label", caption = "last-minute UBI: " .. metrics.ubi_last_minute(state.metrics, second)})
  container.add({type = "label", caption = "last-minute traded: " .. metrics.trade_last_minute(state.metrics, second)})
  container.add({type = "label", caption = "Ore Breakdown / Minute"})
  for _, ore_name in ipairs(constants.ore_names) do
    container.add({
      type = "label",
      caption = string.format("%s: %d", ore_name, snapshot.breakdown_per_minute[ore_name] or 0),
    })
  end
end

function gui.refresh_main(player)
  local frame = main_frame(player)
  if not frame then
    return
  end

  refresh_market_tab(player, frame["trade_mode_market_content"])
  refresh_contracts_tab(player, frame["trade_mode_contracts_content"])
  refresh_economy_tab(frame["trade_mode_economy_content"])
end

function gui.open_main(player)
  if main_frame(player) then
    gui.refresh_main(player)
    return
  end

  local frame = player.gui.screen.add({
    type = "frame",
    name = constants.gui.screen_root,
    direction = "vertical",
    caption = "Trade Market",
  })
  frame.auto_center = true

  local close_flow = frame.add({type = "flow", direction = "horizontal"})
  close_flow.add({type = "empty-widget"})
  close_flow.add({type = "button", name = "trade_mode_close_main", caption = "Close"})

  local tabs = frame.add({type = "tabbed-pane"})
  local market_tab = tabs.add({type = "tab", caption = "Market"})
  local market_content = tabs.add({type = "flow", name = "trade_mode_market_content", direction = "vertical"})
  tabs.add_tab(market_tab, market_content)

  local contracts_tab = tabs.add({type = "tab", caption = "Contracts"})
  local contracts_content = tabs.add({type = "flow", name = "trade_mode_contracts_content", direction = "vertical"})
  tabs.add_tab(contracts_tab, contracts_content)

  local economy_tab = tabs.add({type = "tab", caption = "Economy"})
  local economy_content = tabs.add({type = "flow", name = "trade_mode_economy_content", direction = "vertical"})
  tabs.add_tab(economy_tab, economy_content)

  gui.refresh_main(player)
end

function gui.toggle_main(player)
  if main_frame(player) then
    main_frame(player).destroy()
  else
    gui.open_main(player)
  end
end

function gui.show_trade_box_panel(player, entity)
  destroy_if_present(player.gui.left, constants.gui.trade_box_root)
  if not entity or not entity.valid or entity.name ~= constants.entity_name then
    return
  end

  local frame = player.gui.left.add({
    type = "frame",
    name = constants.gui.trade_box_root,
    direction = "vertical",
    caption = "Buy Order - " .. format.position(entity),
  })

  local order = orders.get_by_box_id(root().orders, util.id_key(entity.unit_number))
  frame.add({
    type = "choose-elem-button",
    name = constants.gui.buy_order_item,
    elem_type = "item",
  })
  frame[constants.gui.buy_order_item].elem_value = order and order.item_name or nil
  frame.add({
    type = "textfield",
    name = constants.gui.buy_order_price,
    text = order and tostring(order.unit_price) or "",
  })
  frame.add({type = "label", name = "trade_mode_suggested_price_label", caption = "Suggested price: n/a"})
  frame.add({type = "label", name = "trade_mode_status_label", caption = "Status: Invalid"})

  local button_flow = frame.add({type = "flow", direction = "horizontal"})
  button_flow.add({type = "button", name = constants.gui.buy_order_fill_suggested, caption = "Use Suggested"})
  button_flow.add({type = "button", name = constants.gui.buy_order_save, caption = "Save"})
  button_flow.add({type = "button", name = constants.gui.buy_order_cancel, caption = "Cancel"})

  local secondary_flow = frame.add({type = "flow", direction = "horizontal"})
  secondary_flow.add({type = "button", name = constants.gui.buy_order_toggle, caption = "Pause / Resume"})
  secondary_flow.add({type = "button", name = constants.gui.buy_order_delete, caption = "Delete"})

  trade.note_trade_box_context(player.index, entity)
  refresh_trade_box_panel(player)
end

function gui.hide_trade_box_panel(player)
  destroy_if_present(player.gui.left, constants.gui.trade_box_root)
end

function gui.show_selected_inserter(player)
  destroy_if_present(player.gui.left, constants.gui.inserter_panel)
  local selected = player.selected
  if not selected or not selected.valid or selected.type ~= "inserter" then
    return
  end

  local frame = player.gui.left.add({
    type = "frame",
    name = constants.gui.inserter_panel,
    direction = "vertical",
    caption = "Inserter Trade Stats",
  })
  frame.add({type = "flow", name = "trade_mode_inserter_content", direction = "vertical"})
  refresh_inserter_panel(player)
end

function gui.handle_click(event)
  local player = game.players[event.player_index]
  local name = event.element.name

  if name == "trade_mode_close_main" then
    main_frame(player).destroy()
    return
  end

  if name == constants.gui.buy_order_cancel then
    gui.hide_trade_box_panel(player)
    trade.note_trade_box_context(player.index, nil)
    return
  end

  if name == constants.gui.buy_order_fill_suggested then
    local frame = buy_order_panel(player)
    local item_name = frame[constants.gui.buy_order_item].elem_value
    if item_name then
      local suggested = pricing.get_suggested_price(require("src.suggested-prices-config"), item_name)
      if suggested then
        frame[constants.gui.buy_order_price].text = tostring(suggested)
      end
    end
    refresh_trade_box_panel(player)
    return
  end

  if name == constants.gui.buy_order_save then
    local box_record = current_box_record(player)
    if not box_record then
      player.print("Trade Mode: no active trade box selected.")
      return
    end

    local frame = buy_order_panel(player)
    local item_name = frame[constants.gui.buy_order_item].elem_value
    local unit_price = parse_numeric_text(frame[constants.gui.buy_order_price].text)
    if not item_name or not unit_price then
      player.print("Trade Mode: select an item and enter a positive integer price.")
      return
    end

    local state = root()
    local existing = orders.get_by_box_id(state.orders, box_record.box_id)
    if existing then
      orders.update_order(state.orders, existing.id, {
        item_name = item_name,
        unit_price = unit_price,
        status = existing.status == "cancelled" and "active" or existing.status,
        tick = game.tick,
      })
      existing = orders.get_by_id(state.orders, existing.id)
      if existing.status == "cancelled" then
        existing.status = "active"
      end
    else
      local created = orders.create_order(state.orders, {
        box_id = box_record.box_id,
        buyer_id = player.index,
        item_name = item_name,
        unit_price = unit_price,
        tick = game.tick,
      })
      if not created.ok then
        player.print("Trade Mode: box already has an order.")
        return
      end
    end

    entities.sync_box_filters(box_record.box_id)
    box_record.tracked_item_count = entities.box_inventory(box_record.entity).get_item_count(item_name)
    entities.refresh_tags_for_box(box_record.box_id)
    refresh_trade_box_panel(player)
    gui.refresh_main(player)
    return
  end

  if name == constants.gui.buy_order_toggle then
    local box_record = current_box_record(player)
    if not box_record then
      return
    end

    local order = orders.get_by_box_id(root().orders, box_record.box_id)
    if order then
      local new_status = order.status == "active" and "paused" or "active"
      orders.set_status(root().orders, order.id, new_status, game.tick)
      entities.refresh_tags_for_box(box_record.box_id)
      refresh_trade_box_panel(player)
      gui.refresh_main(player)
    end
    return
  end

  if name == constants.gui.buy_order_delete then
    local box_record = current_box_record(player)
    if not box_record then
      return
    end

    local order = orders.get_by_box_id(root().orders, box_record.box_id)
    if order then
      orders.cancel_order(root().orders, order.id, game.tick)
      entities.sync_box_filters(box_record.box_id)
      entities.refresh_tags_for_box(box_record.box_id)
      box_record.tracked_item_count = 0
      refresh_trade_box_panel(player)
      gui.refresh_main(player)
    end
    return
  end

  if name == constants.gui.contract_create then
    local frame = main_frame(player)
    local title = find_descendant(frame, constants.gui.contract_title).text
    local description = find_descendant(frame, constants.gui.contract_description).text
    local amount = parse_numeric_text(find_descendant(frame, constants.gui.contract_amount).text)
    if title == "" or description == "" or not amount then
      player.print("Trade Mode: title, description, and a positive integer amount are required.")
      return
    end
    contracts.create_contract(root().contracts, {
      creator_id = player.index,
      title = title,
      description = description,
      amount = amount,
      tick = game.tick,
    })
    ui_state(player.index).selected_contract_id = nil
    gui.refresh_main(player)
    return
  end

  if string.find(name, "^" .. constants.gui.contract_list_prefix) then
    ui_state(player.index).selected_contract_id = tonumber(string.gsub(name, constants.gui.contract_list_prefix, ""))
    gui.refresh_main(player)
    return
  end

  local selected_contract_id = ui_state(player.index).selected_contract_id
  if not selected_contract_id then
    return
  end

  if name == constants.gui.contract_assign then
    contracts.assign_self(root().contracts, selected_contract_id, player.index, game.tick)
    gui.refresh_main(player)
    return
  end

  if name == constants.gui.contract_unassign then
    contracts.unassign_self(root().contracts, selected_contract_id, player.index, game.tick)
    gui.refresh_main(player)
    return
  end

  if name == constants.gui.contract_pay then
    local result = contracts.payout(root().contracts, root().ledger, selected_contract_id, player.index, game.tick)
    if not result.ok then
      player.print("Trade Mode: payout failed (" .. result.error .. ").")
    end
    gui.refresh_main(player)
  end
end

function gui.handle_text_changed(event)
  local player = game.players[event.player_index]
  if event.element.name == constants.gui.market_filter then
    ui_state(player.index).market_filter = event.element.text
    gui.refresh_main(player)
    return
  end

  if event.element.name == constants.gui.buy_order_price then
    refresh_trade_box_panel(player)
  end
end

function gui.handle_elem_changed(event)
  local player = game.players[event.player_index]
  if event.element.name == constants.gui.buy_order_item then
    refresh_trade_box_panel(player)
  end
end

function gui.refresh_context_panels(player)
  if buy_order_panel(player) then
    refresh_trade_box_panel(player)
  end
  if inserter_panel(player) then
    refresh_inserter_panel(player)
  end
  if main_frame(player) then
    gui.refresh_main(player)
  end
end

return gui
