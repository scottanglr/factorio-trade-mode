local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local commands_runtime = require("trade_mode.runtime.commands")
local economy = require("trade_mode.runtime.economy")
local entities = require("trade_mode.runtime.entities")
local format = require("trade_mode.runtime.format")
local inserter_stats = require("trade_mode.core.inserter_stats")
local metrics = require("trade_mode.core.metrics")
local notifications = require("trade_mode.runtime.notifications")
local orders = require("trade_mode.core.orders")
local pricing = require("trade_mode.core.pricing")
local runtime_state = require("trade_mode.runtime.state")
local util = require("trade_mode.core.util")
local trade = require("trade_mode.runtime.trade")
local mod_gui = require("__core__.lualib.mod-gui")

local suggested_prices = require("trade_mode.suggested-prices-config")

local gui = {}

local MARKET_SCROLL = "trade_mode_market_scroll"
local MARKET_SUMMARY = "trade_mode_market_summary"
local TRADE_BOX_SUGGESTED = "trade_mode_suggested_price_label"
local TRADE_BOX_STATUS = "trade_mode_status_label"
local TRADE_BOX_STORED = "trade_mode_stored_count_label"
local TRADE_BOX_LAST_TRADE = "trade_mode_last_trade_label"
local TRADE_BOX_TOTAL = "trade_mode_total_traded_label"
local INSERTER_CONTENT = "trade_mode_inserter_content"
local FEEDBACK_COLORS = {
  error = {r = 1, g = 0.34, b = 0.34},
  success = {r = 0.62, g = 0.95, b = 0.62},
  info = {r = 0.82, g = 0.82, b = 0.82},
}

local function root()
  return runtime_state.root()
end

local function localised(key, ...)
  local message = {"trade-mode." .. key}
  local args = {...}
  for index = 1, #args do
    message[#message + 1] = args[index]
  end
  return message
end

local function player_force_name(player)
  return player and player.valid and player.force.name or nil
end

local function localised_status(status)
  return localised("status-" .. (status or "unknown"))
end

local function localised_error(error_code)
  return localised("error-" .. (error_code or "unknown"))
end

local function ui_state(player_index)
  local runtime = runtime_state.runtime()
  runtime.player_ui[player_index] = runtime.player_ui[player_index] or {
    market_filter = "",
    selected_contract_id = nil,
    contract_list_ids = {},
    contract_title = "",
    contract_description = "",
    contract_amount = "",
    trade_box_feedback = nil,
    contract_feedback = nil,
    selected_main_tab = 1,
    selected_inserter_id = nil,
    inserter_min_price = "",
    inserter_feedback = nil,
  }
  return runtime.player_ui[player_index]
end

local function destroy_if_present(container, name)
  if container[name] then
    container[name].destroy()
  end
end

local function destroy_named_panel(player, name)
  destroy_if_present(player.gui.left, name)
  destroy_if_present(player.gui.relative, name)
  destroy_if_present(player.gui.screen, name)
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

local function split_lines(text)
  local lines = {}
  if not text or text == "" then
    return lines
  end

  for line in string.gmatch(text .. "\n", "(.-)\n") do
    lines[#lines + 1] = line
  end

  return lines
end

local function parse_numeric_text(text)
  local number = tonumber(text)
  if not number or number <= 0 or number ~= math.floor(number) then
    return nil
  end
  return number
end

local function humanize_status(status)
  if not status or status == "" then
    return "Unknown"
  end
  local words = {}
  for chunk in string.gmatch(status, "[^_]+") do
    words[#words + 1] = chunk:gsub("^%l", string.upper)
  end
  return table.concat(words, " ")
end

local function item_caption(item_name)
  local prototype = prototypes and prototypes.item and prototypes.item[item_name]
  local name = prototype and prototype.localised_name or item_name
  local sprite_path = "item/" .. item_name
  local icon = helpers.is_valid_sprite_path(sprite_path) and ("[img=" .. sprite_path .. "] ") or ""
  return {"", icon, name}
end

local function current_box_record(player)
  local record = runtime_state.runtime().players[player.index]
  if not record or not record.opened_trade_box_id then
    return nil
  end
  return runtime_state.runtime().trade_boxes[record.opened_trade_box_id]
end

local function buy_order_panel(player)
  return player.gui.relative[constants.gui.trade_box_root] or player.gui.left[constants.gui.trade_box_root]
end

local function inserter_panel(player)
  return player.gui.relative[constants.gui.inserter_panel] or player.gui.left[constants.gui.inserter_panel]
end

local function main_frame(player)
  return player.gui.screen[constants.gui.screen_root]
end

local function main_element(player, name)
  return find_descendant(main_frame(player), name)
end

local function destroy_legacy_mod_button(player)
  local flow = mod_gui.get_button_flow(player)
  if flow and flow.valid and flow[constants.gui.mod_button] then
    flow[constants.gui.mod_button].destroy()
  end
  destroy_if_present(player.gui.relative, "trade_mode_controller_root")
end

local function main_tab_count(player)
  if player.admin then
    return 4
  end
  return 3
end

local function set_main_shortcut_toggled(player, toggled)
  if player and player.valid then
    player.set_shortcut_toggled(constants.shortcut_name, toggled)
  end
end

local function set_feedback(player, key, level, text)
  local ui = ui_state(player.index)
  if text == nil then
    ui[key] = nil
    return
  end

  ui[key] = {
    level = level or "info",
    text = text,
  }
end

local function apply_feedback(element, feedback)
  if not element or not element.valid then
    return
  end

  if feedback and feedback.text ~= "" then
    element.caption = feedback.text
    element.visible = true
    element.style.font_color = FEEDBACK_COLORS[feedback.level] or FEEDBACK_COLORS.info
  else
    element.caption = ""
    element.visible = false
  end
end

local function set_text_if_changed(element, text)
  if element and element.valid and element.text ~= text then
    element.text = text
  end
end

local function add_horizontal_pusher(parent, style_name)
  local widget = parent.add({type = "empty-widget"})
  if style_name then
    widget.style = style_name
  end
  widget.style.horizontally_stretchable = true
  return widget
end

local function player_balance(player)
  return runtime_state.player_balance(player.index)
end

local function balance_caption(player)
  return localised("balance-label", format.localised_money(player_balance(player)))
end

local function add_window_titlebar(frame, title)
  local titlebar = frame.add({type = "flow", direction = "horizontal"})
  titlebar.drag_target = frame
  titlebar.style.horizontal_spacing = 8
  local title_label = titlebar.add({type = "label", style = "frame_title", caption = title})
  title_label.ignored_by_interaction = true
  local drag_handle = add_horizontal_pusher(titlebar, "draggable_space_header")
  drag_handle.style.height = 24
  drag_handle.style.right_margin = 4
  drag_handle.ignored_by_interaction = true
  titlebar.add({
    type = "sprite-button",
    name = "trade_mode_close_main",
    style = "frame_action_button",
    sprite = "utility/close",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    tooltip = {"gui.close-instruction"},
  })
end

local function add_panel_titlebar(frame, title, close_name)
  local titlebar = frame.add({type = "flow", direction = "horizontal"})
  titlebar.style.horizontal_spacing = 8
  local title_label = titlebar.add({type = "label", style = "frame_title", caption = title})
  title_label.ignored_by_interaction = true
  local drag_handle = add_horizontal_pusher(titlebar, "draggable_space_header")
  drag_handle.style.height = 24
  drag_handle.ignored_by_interaction = true
  titlebar.add({
    type = "sprite-button",
    name = close_name,
    style = "frame_action_button",
    sprite = "utility/close",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    tooltip = {"gui.close-instruction"},
  })
end

local function add_section(parent, title, content_name)
  local wrapper = parent.add({type = "flow", direction = "vertical"})
  wrapper.style.horizontally_stretchable = true
  local header = wrapper.add({type = "frame", style = "subheader_frame"})
  header.style.horizontally_stretchable = true
  header.add({type = "label", style = "subheader_caption_label", caption = title})
  local body = wrapper.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
  body.style.horizontally_stretchable = true
  local content = body.add({type = "flow", direction = "vertical", name = content_name})
  content.style.horizontally_stretchable = true
  content.style.vertical_spacing = 8
  return wrapper, content, header
end

local function add_detail_row(parent, label, value)
  local row = parent.add({type = "flow", direction = "horizontal"})
  row.style.horizontal_spacing = 8
  row.style.vertical_align = "center"
  row.add({type = "label", style = "caption_label", caption = label})
  row.add({type = "label", caption = value})
end

local function add_wrapped_label(parent, style_name, caption)
  local spec = {type = "label", caption = caption}
  if style_name then
    spec.style = style_name
  end
  local label = parent.add(spec)
  label.style.single_line = false
  label.style.horizontally_stretchable = true
  return label
end

local function add_report_lines(parent, text, min_height)
  local scroll = parent.add({
    type = "scroll-pane",
    direction = "vertical",
    vertical_scroll_policy = "auto-and-reserve-space",
  })
  scroll.style.horizontally_stretchable = true
  scroll.style.vertically_stretchable = true
  scroll.style.minimal_height = min_height or 150

  local content = scroll.add({type = "flow", direction = "vertical"})
  content.style.horizontally_stretchable = true
  content.style.vertical_spacing = 4

  local lines = split_lines(text)
  for index, line in ipairs(lines) do
    add_wrapped_label(content, index == 1 and "bold_label" or "caption_label", line ~= "" and line or " ")
  end

  if #lines == 0 then
    content.add({type = "label", style = "caption_label", caption = localised("none")})
  end

  return scroll
end

local function add_metric_card(parent, title, value, note)
  local card = parent.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
  card.style.minimal_width = 170
  card.style.horizontally_stretchable = true
  local body = card.add({type = "flow", direction = "vertical"})
  body.style.horizontally_stretchable = true
  body.style.vertical_spacing = 4
  body.add({type = "label", style = "caption_label", caption = title})
  body.add({type = "label", style = "bold_label", caption = value})
  if note then
    body.add({type = "label", style = "caption_label", caption = note})
  end
end

local function ensure_mod_button(player)
  local button = player.gui.relative[constants.gui.mod_button]
  if button and button.valid then
    return button
  end

  return player.gui.relative.add({
    type = "sprite-button",
    name = constants.gui.mod_button,
    style = mod_gui.button_style,
    sprite = "item/trade-box",
    tooltip = localised("trade-market"),
    anchor = {
      gui = defines.relative_gui_type.controller_gui,
      position = defines.relative_gui_position.right,
    },
  })
end

local function refresh_mod_button(player)
  destroy_legacy_mod_button(player)
  local button = ensure_mod_button(player)
  if button then
    button.tooltip = {"", localised("trade-market"), "\n", balance_caption(player)}
  end
end

local function refresh_window_balance(player)
  local label = main_element(player, constants.gui.window_balance)
  if label then
    label.caption = balance_caption(player)
  end
end

local function add_two_column_header(table_element, left, right)
  table_element.add({type = "label", style = "bold_label", caption = left})
  table_element.add({type = "label", style = "bold_label", caption = right})
end

local function sync_contract_form(player)
  local ui = ui_state(player.index)
  set_text_if_changed(main_element(player, constants.gui.contract_title), ui.contract_title or "")
  set_text_if_changed(main_element(player, constants.gui.contract_description), ui.contract_description or "")
  set_text_if_changed(main_element(player, constants.gui.contract_amount), ui.contract_amount or "")
  set_text_if_changed(main_element(player, constants.gui.market_filter), ui.market_filter or "")
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
  local item_picker = find_descendant(frame, constants.gui.buy_order_item)
  local selected_item = item_picker and item_picker.elem_value or nil
  local suggested_label = find_descendant(frame, TRADE_BOX_SUGGESTED)
  local status_label = find_descendant(frame, TRADE_BOX_STATUS)
  local stored_label = find_descendant(frame, TRADE_BOX_STORED)
  local last_trade_label = find_descendant(frame, TRADE_BOX_LAST_TRADE)
  local total_label = find_descendant(frame, TRADE_BOX_TOTAL)
  local toggle_button = find_descendant(frame, constants.gui.buy_order_toggle)
  local delete_button = find_descendant(frame, constants.gui.buy_order_delete)
  local feedback_label = find_descendant(frame, constants.gui.buy_order_feedback)

  apply_feedback(feedback_label, ui_state(player.index).trade_box_feedback)

  if selected_item then
    local suggested = pricing.get_suggested_price(suggested_prices, selected_item)
    if suggested then
      suggested_label.caption = localised("suggested-price", format.localised_money(suggested))
    else
      suggested_label.caption = localised("suggested-price-na")
    end
  else
    suggested_label.caption = localised("suggested-price-na")
  end

  if order then
    status_label.caption = localised("status-label", localised_status(order.status))
    stored_label.caption = localised("stored-count", box_record.tracked_item_count or 0)
    last_trade_label.caption = localised("last-trade-label", format.localised_tick_age(game.tick, order.last_trade_tick))
    total_label.caption = localised("lifetime-traded", format.localised_money(order.total_traded or 0))
    toggle_button.caption = order.status == "active" and localised("pause-order") or localised("resume-order")
    toggle_button.enabled = true
    delete_button.enabled = true
  else
    status_label.caption = localised("status-label", localised("no-active-order"))
    stored_label.caption = localised("stored-count", box_record.tracked_item_count or 0)
    last_trade_label.caption = localised("last-trade-label", localised("never"))
    total_label.caption = localised("lifetime-traded", format.localised_money(0))
    toggle_button.caption = localised("pause-order")
    toggle_button.enabled = false
    delete_button.enabled = false
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
  local record = entities.register_inserter(selected)
  local ui = ui_state(player.index)
  local selected_inserter_id = util.id_key(selected.unit_number)
  if ui.selected_inserter_id ~= selected_inserter_id then
    ui.selected_inserter_id = selected_inserter_id
    ui.inserter_min_price = record and record.min_unit_price and tostring(record.min_unit_price) or ""
    ui.inserter_feedback = nil
  end

  local content = find_descendant(frame, INSERTER_CONTENT)
  clear_children(content)
  add_detail_row(content, localised("owner"), record and record.owner_player_index and runtime_state.player_name(record.owner_player_index) or localised("unknown"))
  add_detail_row(content, localised("pending-box"), record and record.pending_box_id and entities.describe_box(record.pending_box_id) or localised("idle"))
  add_detail_row(content, localised("lifetime-payout"), format.localised_money(stats and stats.lifetime_payout or 0))
  add_detail_row(content, localised("last-recipient"), stats and stats.last_recipient_id and runtime_state.player_name(stats.last_recipient_id) or localised("none"))
  add_detail_row(content, localised("last-trade"), format.localised_tick_age(game.tick, stats and stats.last_trade_tick or nil))
  add_detail_row(
    content,
    localised("minimum-acceptable-price"),
    record and record.min_unit_price and format.localised_money(record.min_unit_price) or localised("not-set")
  )

  local edit_row = content.add({type = "flow", direction = "horizontal", style = "player_input_horizontal_flow"})
  edit_row.style.horizontally_stretchable = true
  edit_row.add({type = "label", style = "caption_label", caption = localised("minimum-acceptable-price")})
  local price_input = edit_row.add({
    type = "textfield",
    name = constants.gui.inserter_min_price,
    text = ui.inserter_min_price or "",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    clear_and_focus_on_right_click = true,
  })
  price_input.style.width = 110
  edit_row.add({
    type = "button",
    name = constants.gui.inserter_min_price_save,
    caption = localised("save"),
  })

  add_wrapped_label(content, "caption_label", localised("inserter-min-price-note"))
  local feedback = content.add({
    type = "label",
    name = constants.gui.inserter_feedback,
    style = "caption_label",
    caption = "",
  })
  apply_feedback(feedback, ui.inserter_feedback)
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

local function refresh_market_tab(player)
  local summary = main_element(player, constants.gui.market_results)
  local scroll = main_element(player, MARKET_SCROLL)
  local summary_content = main_element(player, MARKET_SUMMARY)
  if not summary or not scroll or not summary_content then
    return
  end

  local market_orders = filtered_orders(player)
  summary.caption = localised("listings-count", #market_orders)
  clear_children(summary_content)

  local active_count = 0
  local paused_count = 0
  local buyers = {}
  for _, order in ipairs(market_orders) do
    if order.status == "active" then
      active_count = active_count + 1
    elseif order.status == "paused" then
      paused_count = paused_count + 1
    end
    buyers[order.buyer_id] = true
  end

  local buyer_count = 0
  for _ in pairs(buyers) do
    buyer_count = buyer_count + 1
  end

  add_detail_row(summary_content, localised("matching-orders"), tostring(#market_orders))
  add_detail_row(summary_content, localised("active-orders"), tostring(active_count))
  add_detail_row(summary_content, localised("paused-orders"), tostring(paused_count))
  add_detail_row(summary_content, localised("buyers"), tostring(buyer_count))
  add_wrapped_label(summary_content, "caption_label", localised("market-filter-note"))
  add_wrapped_label(summary_content, "caption_label", localised("market-trade-box-note"))

  clear_children(scroll)
  if #market_orders == 0 then
    scroll.add({type = "label", style = "caption_label", caption = localised("no-buy-orders-match")})
    return
  end

  local table_element = scroll.add({type = "table", name = constants.gui.market_orders_table, style = "table_with_selection", column_count = 6})
  table_element.style.horizontally_stretchable = true
  table_element.draw_horizontal_line_after_headers = true
  table_element.add({type = "label", style = "bold_label", caption = localised("item")})
  table_element.add({type = "label", style = "bold_label", caption = localised("price")})
  table_element.add({type = "label", style = "bold_label", caption = localised("buyer")})
  table_element.add({type = "label", style = "bold_label", caption = localised("box")})
  table_element.add({type = "label", style = "bold_label", caption = localised("status")})
  table_element.add({type = "label", style = "bold_label", caption = localised("last-trade")})
  for _, order in ipairs(market_orders) do
    table_element.add({type = "label", caption = item_caption(order.item_name)})
    table_element.add({type = "label", caption = format.localised_money(order.unit_price)})
    table_element.add({type = "label", caption = runtime_state.player_name(order.buyer_id)})
    table_element.add({type = "label", caption = entities.describe_box(order.box_id)})
    table_element.add({type = "label", caption = localised_status(order.status)})
    table_element.add({type = "label", caption = format.localised_tick_age(game.tick, order.last_trade_tick)})
  end
end

local function refresh_contract_detail(player)
  local container = main_element(player, constants.gui.selected_contract)
  if not container then
    return
  end
  clear_children(container)

  local state = root()
  local ui = ui_state(player.index)
  local selected = ui.selected_contract_id and contracts.get_by_id(state.contracts, ui.selected_contract_id) or nil
  if not selected or runtime_state.contract_force_name(selected) ~= player_force_name(player) then
    container.add({type = "label", style = "caption_label", caption = localised("select-contract")})
    return
  end

  add_detail_row(container, localised("title"), selected.title)
  add_detail_row(container, localised("creator"), runtime_state.player_name(selected.creator_id))
  add_detail_row(container, localised("reward"), format.localised_money(selected.amount))
  add_detail_row(container, localised("assignee"), selected.assignee_id and runtime_state.player_name(selected.assignee_id) or localised("unassigned"))
  add_detail_row(container, localised("status"), localised_status(selected.status))
  add_detail_row(container, localised("created"), format.localised_tick_age(game.tick, selected.created_tick))
  if selected.paid_tick then
    add_detail_row(container, localised("paid"), format.localised_tick_age(game.tick, selected.paid_tick))
  end

  container.add({type = "label", style = "caption_label", caption = localised("briefing")})
  local description_frame = container.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
  description_frame.style.horizontally_stretchable = true
  add_wrapped_label(description_frame, nil, selected.description ~= "" and selected.description or localised("none"))

  local current_player_id = player.index
  if selected.creator_id ~= current_player_id and selected.status ~= "completed" then
    local button_flow = container.add({type = "flow", direction = "horizontal"})
    button_flow.style.horizontally_stretchable = true
    if selected.assignee_id == current_player_id then
      local button = button_flow.add({type = "button", name = constants.gui.contract_unassign, caption = localised("unassign")})
      button.style.horizontally_stretchable = true
    else
      local button = button_flow.add({type = "button", name = constants.gui.contract_assign, caption = localised("assign-to-me")})
      button.style.horizontally_stretchable = true
    end
  end

  if selected.creator_id == current_player_id and selected.assignee_id ~= nil and selected.status == "assigned" then
    local payout_flow = container.add({type = "flow", direction = "horizontal"})
    payout_flow.style.horizontally_stretchable = true
    local button = payout_flow.add({type = "button", name = constants.gui.contract_pay, caption = localised("pay-assignee")})
    button.style.horizontally_stretchable = true
  end
end

local function refresh_contracts_tab(player)
  local ui = ui_state(player.index)
  local state = root()
  local count_label = main_element(player, constants.gui.contract_count)
  local list_box = main_element(player, constants.gui.contract_list)
  local feedback_label = main_element(player, constants.gui.contract_feedback)
  if not count_label or not list_box then
    return
  end

  apply_feedback(feedback_label, ui.contract_feedback)

  local contract_rows = contracts.list_all(state.contracts, player_force_name(player))
  ui.contract_list_ids = {}
  local items = {}
  for _, contract in ipairs(contract_rows) do
    ui.contract_list_ids[#ui.contract_list_ids + 1] = contract.id
    items[#items + 1] = {"", "#", tostring(contract.id), "  ", contract.title, "  [", localised_status(contract.status), "]"}
  end

  list_box.items = items
  local selected_index = 0
  for index, contract_id in ipairs(ui.contract_list_ids) do
    if contract_id == ui.selected_contract_id then
      selected_index = index
      break
    end
  end
  if selected_index == 0 then
    ui.selected_contract_id = nil
  end
  if list_box.selected_index ~= selected_index then
    list_box.selected_index = selected_index
  end

  count_label.caption = localised("contracts-open-count", contracts.count_openish(state.contracts, player_force_name(player)))
  refresh_contract_detail(player)
end

local function refresh_economy_tab(player)
  local container = main_element(player, constants.gui.economy_tab)
  if not container then
    return
  end
  clear_children(container)

  local force_name = player_force_name(player)
  local snapshot = economy.snapshot(force_name)
  local second = runtime_state.current_second(game.tick)
  local state = root()
  local openish_contracts = contracts.count_openish(state.contracts, force_name)

  local cards = container.add({type = "flow", direction = "horizontal"})
  cards.style.horizontally_stretchable = true
  cards.style.horizontal_spacing = 12
  add_metric_card(cards, localised("ubi-rate"), localised("gold-per-second", string.format("%.2f", snapshot.gold_per_second)), localised("current-force-payout"))
  add_metric_card(cards, localised("ore-throughput"), localised("units-per-minute-compact", string.format("%.1f", snapshot.recent_raw_ore_per_minute)), localised("tracked-raw-ore-force"))
  add_metric_card(cards, localised("last-minute-ubi"), format.localised_money(metrics.ubi_last_minute(state.metrics, second, force_name)), localised("rolling-window"))
  add_metric_card(cards, localised("last-minute-trade"), format.localised_money(metrics.trade_last_minute(state.metrics, second, force_name)), localised("rolling-window"))

  local upper_row = container.add({type = "flow", direction = "horizontal"})
  upper_row.style.horizontally_stretchable = true
  upper_row.style.horizontal_spacing = 12

  local _, ore_content = add_section(upper_row, localised("ore-throughput"))
  local ore_table = ore_content.add({type = "table", column_count = 2})
  ore_table.style.horizontally_stretchable = true
  add_two_column_header(ore_table, localised("resource"), localised("units-per-minute"))
  for _, ore_name in ipairs(constants.ore_names) do
    ore_table.add({type = "label", caption = item_caption(ore_name)})
    ore_table.add({type = "label", caption = string.format("%.1f", snapshot.breakdown_per_minute[ore_name] or 0)})
  end

  local _, balance_content = add_section(upper_row, localised("top-balances"))
  local balance_rows = runtime_state.force_wallet_rows(force_name, 5)
  if #balance_rows == 0 then
    balance_content.add({type = "label", style = "caption_label", caption = localised("no-balances")})
  else
    local balance_table = balance_content.add({type = "table", column_count = 2})
    balance_table.style.horizontally_stretchable = true
    add_two_column_header(balance_table, localised("wallet"), localised("balance"))
    for _, row in ipairs(balance_rows) do
      balance_table.add({type = "label", caption = runtime_state.actor_name(row.account_id)})
      balance_table.add({type = "label", caption = format.localised_money(row.balance)})
    end
  end

  local lower_row = container.add({type = "flow", direction = "horizontal"})
  lower_row.style.horizontally_stretchable = true
  lower_row.style.horizontal_spacing = 12

  local _, earners_content = add_section(lower_row, localised("top-earners"))
  local earners = metrics.top_recipients(state.metrics, second, 5, function(row)
    return runtime_state.player_in_force(row.player_id, force_name)
  end)
  if #earners == 0 then
    earners_content.add({type = "label", style = "caption_label", caption = localised("no-trade-payouts")})
  else
    local earners_table = earners_content.add({type = "table", column_count = 2})
    earners_table.style.horizontally_stretchable = true
    add_two_column_header(earners_table, localised("player"), localised("income"))
    for _, row in ipairs(earners) do
      earners_table.add({type = "label", caption = runtime_state.player_name(row.player_id)})
      earners_table.add({type = "label", caption = format.localised_money(row.amount)})
    end
  end

  local _, payers_content = add_section(lower_row, localised("top-spenders"))
  local payers = metrics.top_payers(state.metrics, second, 5, function(row)
    return runtime_state.player_in_force(row.player_id, force_name)
  end)
  if #payers == 0 then
    payers_content.add({type = "label", style = "caption_label", caption = localised("no-buy-side-spend")})
  else
    local payers_table = payers_content.add({type = "table", column_count = 2})
    payers_table.style.horizontally_stretchable = true
    add_two_column_header(payers_table, localised("player"), localised("spent"))
    for _, row in ipairs(payers) do
      payers_table.add({type = "label", caption = runtime_state.player_name(row.player_id)})
      payers_table.add({type = "label", caption = format.localised_money(row.amount)})
    end
  end
end

local function refresh_admin_tab(player)
  if not player.admin then
    return
  end

  local container = main_element(player, constants.gui.admin_tab)
  if not container then
    return
  end

  clear_children(container)
  local force_name = player_force_name(player)
  local snapshot = economy.snapshot(force_name)
  local second = runtime_state.current_second(game.tick)
  local state = root()

  local active_orders = 0
  for _, order in ipairs(orders.list_current(state.orders)) do
    if runtime_state.order_force_name(order) == force_name then
      active_orders = active_orders + 1
    end
  end

  local cards = container.add({type = "flow", direction = "horizontal"})
  cards.style.horizontally_stretchable = true
  cards.style.horizontal_spacing = 12
  add_metric_card(cards, localised("active-orders"), tostring(active_orders), localised("buy-orders"))
  add_metric_card(cards, localised("contracts"), tostring(openish_contracts), localised("contracts-open-count", openish_contracts))
  add_metric_card(cards, localised("last-minute-trade"), format.localised_money(metrics.trade_last_minute(state.metrics, second, force_name)), localised("rolling-window"))
  add_metric_card(cards, localised("last-minute-ubi"), format.localised_money(metrics.ubi_last_minute(state.metrics, second, force_name)), localised("rolling-window"))

  local notes_row = container.add({type = "flow", direction = "horizontal"})
  notes_row.style.horizontally_stretchable = true
  notes_row.style.horizontal_spacing = 12

  local _, notes_content = add_section(notes_row, localised("admin-diagnostics"))
  add_wrapped_label(notes_content, "caption_label", localised("chart-tag-scope-note"))
  add_wrapped_label(notes_content, "caption_label", localised("admin-commands-note"))

  local _, command_content = add_section(notes_row, localised("quick-commands"))
  add_wrapped_label(command_content, "caption_label", {"", "/trade_status  ", localised("command-help-trade-status")})
  add_wrapped_label(command_content, "caption_label", {"", "/trade_orders  ", localised("command-help-trade-orders")})
  add_wrapped_label(command_content, "caption_label", {"", "/trade_contracts  ", localised("command-help-trade-contracts")})
  add_wrapped_label(command_content, "caption_label", {"", "/trade_money_last_minute  ", localised("command-help-trade-money-last-minute")})
  add_wrapped_label(command_content, "caption_label", {"", "/trade_ubi_last_minute  ", localised("command-help-trade-ubi-last-minute")})

  local status_row = container.add({type = "flow", direction = "horizontal"})
  status_row.style.horizontally_stretchable = true
  status_row.style.horizontal_spacing = 12

  local _, economy_content = add_section(status_row, localised("economy-status"))
  add_detail_row(economy_content, localised("ubi-rate"), localised("gold-per-second", string.format("%.2f", snapshot.gold_per_second)))
  add_detail_row(economy_content, localised("ore-throughput"), localised("units-per-minute-compact", string.format("%.1f", snapshot.recent_raw_ore_per_minute)))
  add_report_lines(economy_content, commands_runtime.render_trade_status(force_name), 120)

  local lower_row = container.add({type = "flow", direction = "horizontal"})
  lower_row.style.horizontally_stretchable = true
  lower_row.style.horizontal_spacing = 12

  local _, orders_content = add_section(lower_row, localised("order-snapshot"))
  add_report_lines(orders_content, commands_runtime.render_trade_orders(force_name), 120)

  local _, contracts_content = add_section(lower_row, localised("contract-snapshot"))
  add_report_lines(contracts_content, commands_runtime.render_trade_contracts(force_name), 120)
end

local function build_market_tab(player, container)
  local columns = container.add({type = "flow", direction = "horizontal"})
  columns.style.horizontally_stretchable = true
  columns.style.horizontal_spacing = 12

  local left = columns.add({type = "flow", direction = "vertical"})
  left.style.horizontally_stretchable = true
  left.style.vertical_spacing = 12

  local toolbar = left.add({type = "frame", style = "subheader_frame"})
  toolbar.style.horizontally_stretchable = true
  toolbar.add({type = "label", style = "subheader_caption_label", caption = localised("buy-orders")})
  add_horizontal_pusher(toolbar)
  toolbar.add({type = "label", style = "caption_label", caption = localised("filter")})
  local filter_field = toolbar.add({type = "textfield", name = constants.gui.market_filter, text = ui_state(player.index).market_filter or ""})
  filter_field.style.minimal_width = 220
  toolbar.add({type = "label", name = constants.gui.market_results, style = "caption_label", caption = localised("listings-count", 0)})

  local list_frame = left.add({type = "frame", style = "inside_shallow_frame", direction = "vertical"})
  list_frame.style.horizontally_stretchable = true
  list_frame.style.vertically_stretchable = true
  local scroll = list_frame.add({
    type = "scroll-pane",
    name = MARKET_SCROLL,
    style = "scroll_pane_in_shallow_frame",
    direction = "vertical",
    vertical_scroll_policy = "auto-and-reserve-space",
  })
  scroll.style.horizontally_stretchable = true
  scroll.style.vertically_stretchable = true
  scroll.style.minimal_height = 320

  local sidebar = columns.add({type = "flow", direction = "vertical"})
  sidebar.style.minimal_width = 250
  sidebar.style.maximal_width = 250
  sidebar.style.vertical_spacing = 12
  add_section(sidebar, localised("market-overview"), MARKET_SUMMARY)
end

local function build_contracts_tab(player, container)
  local contract_feedback = container.add({type = "label", name = constants.gui.contract_feedback, style = "caption_label", caption = ""})
  contract_feedback.visible = false

  local _, create_content = add_section(container, localised("create-contract"))
  add_wrapped_label(create_content, "caption_label", localised("contract-create-note"))

  local form = create_content.add({type = "flow", direction = "horizontal"})
  form.style.horizontally_stretchable = true
  form.style.horizontal_spacing = 16

  local left_form = form.add({type = "flow", direction = "vertical"})
  left_form.style.minimal_width = 320
  left_form.style.maximal_width = 340
  left_form.style.vertical_spacing = 8

  local title_row = left_form.add({type = "flow", direction = "horizontal", style = "player_input_horizontal_flow"})
  title_row.style.horizontally_stretchable = true
  title_row.add({type = "label", style = "caption_label", caption = localised("title")})
  local title_field = title_row.add({type = "textfield", name = constants.gui.contract_title, text = ui_state(player.index).contract_title or ""})
  title_field.style.horizontally_stretchable = true

  local amount_row = left_form.add({type = "flow", direction = "horizontal", style = "player_input_horizontal_flow"})
  amount_row.style.horizontally_stretchable = true
  amount_row.add({type = "label", style = "caption_label", caption = localised("reward")})
  amount_row.add({
    type = "textfield",
    name = constants.gui.contract_amount,
    text = ui_state(player.index).contract_amount or "",
    style = "long_number_textfield",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
  })

  local right_form = form.add({type = "flow", direction = "vertical"})
  right_form.style.horizontally_stretchable = true
  right_form.style.vertical_spacing = 8
  right_form.add({type = "label", style = "caption_label", caption = localised("briefing")})
  local description = right_form.add({type = "text-box", name = constants.gui.contract_description, text = ui_state(player.index).contract_description or ""})
  description.style.minimal_height = 90
  description.style.horizontally_stretchable = true

  local create_buttons = right_form.add({type = "flow", direction = "horizontal"})
  create_buttons.style.horizontally_stretchable = true
  local create_button = create_buttons.add({type = "button", name = constants.gui.contract_create, caption = localised("create-contract")})
  create_button.style.horizontally_stretchable = true

  local columns = container.add({type = "flow", direction = "horizontal"})
  columns.style.horizontally_stretchable = true
  columns.style.horizontal_spacing = 12

  local list_frame = columns.add({type = "frame", style = "inside_shallow_frame", direction = "vertical"})
  list_frame.style.minimal_width = 280
  list_frame.style.maximal_width = 300
  list_frame.style.vertically_stretchable = true
  local list_header = list_frame.add({type = "frame", style = "subheader_frame"})
  list_header.style.horizontally_stretchable = true
  list_header.add({type = "label", style = "subheader_caption_label", caption = localised("contracts")})
  add_horizontal_pusher(list_header)
  list_header.add({type = "label", name = constants.gui.contract_count, style = "caption_label", caption = localised("contracts-open-count", 0)})

  local contract_list = list_frame.add({type = "list-box", name = constants.gui.contract_list, style = "wide_list_box_under_subheader"})
  contract_list.style.minimal_height = 320
  contract_list.style.horizontally_stretchable = true
  contract_list.style.vertically_stretchable = true

  local right = columns.add({type = "flow", direction = "vertical"})
  right.style.horizontally_stretchable = true
  right.style.vertical_spacing = 12
  add_section(right, localised("selected-contract"), constants.gui.selected_contract)
end

function gui.refresh_main(player)
  local frame = main_frame(player)
  if frame then
    local tabs = find_descendant(frame, constants.gui.main_tabs)
    if tabs and tabs.selected_tab_index then
      ui_state(player.index).selected_main_tab = tabs.selected_tab_index
    end
    sync_contract_form(player)
    refresh_market_tab(player)
    refresh_contracts_tab(player)
    refresh_economy_tab(player)
    refresh_admin_tab(player)
    refresh_window_balance(player)
  end
  refresh_mod_button(player)
end

function gui.open_main(player)
  if main_frame(player) then
    gui.refresh_main(player)
    main_frame(player).bring_to_front()
    set_main_shortcut_toggled(player, true)
    return
  end

  local frame = player.gui.screen.add({type = "frame", name = constants.gui.screen_root, direction = "vertical"})
  frame.auto_center = true
  frame.style.minimal_width = 900
  frame.style.maximal_height = math.floor((player.display_resolution.height / player.display_scale) * 0.84)
  add_window_titlebar(frame, localised("trade-market"))

  local body = frame.add({type = "frame", style = "inside_deep_frame", direction = "vertical"})
  body.style.horizontally_stretchable = true
  body.style.vertically_stretchable = true
  local tabs = body.add({type = "tabbed-pane", name = constants.gui.main_tabs, style = "tabbed_pane_with_no_side_padding"})
  tabs.style.vertically_stretchable = true

  local market_tab = tabs.add({type = "tab", caption = localised("market")})
  local market_content = tabs.add({type = "flow", name = constants.gui.market_tab, direction = "vertical"})
  market_content.style.horizontally_stretchable = true
  market_content.style.vertically_stretchable = true
  market_content.style.vertical_spacing = 12
  market_content.style.top_padding = 12
  market_content.style.right_padding = 12
  market_content.style.bottom_padding = 12
  market_content.style.left_padding = 12
  tabs.add_tab(market_tab, market_content)
  build_market_tab(player, market_content)

  local contracts_tab = tabs.add({type = "tab", caption = localised("contracts")})
  local contracts_content = tabs.add({type = "flow", name = constants.gui.contracts_tab, direction = "vertical"})
  contracts_content.style.horizontally_stretchable = true
  contracts_content.style.vertically_stretchable = true
  contracts_content.style.vertical_spacing = 12
  contracts_content.style.top_padding = 12
  contracts_content.style.right_padding = 12
  contracts_content.style.bottom_padding = 12
  contracts_content.style.left_padding = 12
  tabs.add_tab(contracts_tab, contracts_content)
  build_contracts_tab(player, contracts_content)

  local economy_tab = tabs.add({type = "tab", caption = localised("economy")})
  local economy_content = tabs.add({type = "flow", name = constants.gui.economy_tab, direction = "vertical"})
  economy_content.style.horizontally_stretchable = true
  economy_content.style.vertically_stretchable = true
  economy_content.style.vertical_spacing = 12
  economy_content.style.top_padding = 12
  economy_content.style.right_padding = 12
  economy_content.style.bottom_padding = 12
  economy_content.style.left_padding = 12
  tabs.add_tab(economy_tab, economy_content)

  if player.admin then
    local admin_tab = tabs.add({type = "tab", caption = localised("admin")})
    local admin_outer = tabs.add({type = "flow", direction = "vertical"})
    admin_outer.style.horizontally_stretchable = true
    admin_outer.style.vertically_stretchable = true
    admin_outer.style.top_padding = 12
    admin_outer.style.right_padding = 12
    admin_outer.style.bottom_padding = 12
    admin_outer.style.left_padding = 12
    local admin_scroll = admin_outer.add({
      type = "scroll-pane",
      name = constants.gui.admin_scroll,
      direction = "vertical",
      vertical_scroll_policy = "auto-and-reserve-space",
    })
    admin_scroll.style.horizontally_stretchable = true
    admin_scroll.style.vertically_stretchable = true
    local admin_content = admin_scroll.add({type = "flow", name = constants.gui.admin_tab, direction = "vertical"})
    admin_content.style.horizontally_stretchable = true
    admin_content.style.vertical_spacing = 12
    tabs.add_tab(admin_tab, admin_outer)
  end

  local footer = frame.add({type = "frame", style = "subheader_frame"})
  footer.style.horizontally_stretchable = true
  footer.add({type = "label", name = constants.gui.window_balance, style = "subheader_caption_label", caption = ""})

  tabs.selected_tab_index = math.max(1, math.min(ui_state(player.index).selected_main_tab or 1, main_tab_count(player)))
  set_main_shortcut_toggled(player, true)
  gui.refresh_main(player)
end

function gui.toggle_main(player)
  if main_frame(player) then
    main_frame(player).destroy()
    set_main_shortcut_toggled(player, false)
  else
    gui.open_main(player)
  end
end

function gui.show_trade_box_panel(player, entity)
  destroy_named_panel(player, constants.gui.trade_box_root)
  if not entity or not entity.valid or entity.name ~= constants.entity_name then
    return
  end

  set_feedback(player, "trade_box_feedback", nil, nil)
  local order = orders.get_by_box_id(root().orders, util.id_key(entity.unit_number))
  local frame = player.gui.relative.add({
    type = "frame",
    name = constants.gui.trade_box_root,
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      name = constants.entity_name,
    },
  })
  frame.style.minimal_width = 320
  add_panel_titlebar(frame, localised("trade-order"), constants.gui.buy_order_close)

  local body = frame.add({type = "frame", style = "inside_deep_frame", direction = "vertical"})
  body.style.horizontally_stretchable = true
  local header = body.add({type = "frame", style = "subheader_frame"})
  header.style.horizontally_stretchable = true
  header.add({type = "label", style = "subheader_caption_label", caption = localised("buy-request")})
  add_horizontal_pusher(header)
  header.add({type = "label", style = "caption_label", caption = format.position(entity)})

  local content_frame = body.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
  content_frame.style.horizontally_stretchable = true
  local content = content_frame.add({type = "flow", direction = "vertical"})
  content.style.horizontally_stretchable = true
  content.style.vertical_spacing = 8
  local feedback = content.add({type = "label", name = constants.gui.buy_order_feedback, style = "caption_label", caption = ""})
  feedback.visible = false

  local selector_row = content.add({type = "flow", direction = "horizontal"})
  selector_row.style.horizontal_spacing = 12
  selector_row.style.vertical_align = "center"
  local item_picker = selector_row.add({type = "choose-elem-button", name = constants.gui.buy_order_item, elem_type = "item"})
  item_picker.elem_value = order and order.item_name or nil

  local price_row = selector_row.add({type = "flow", direction = "horizontal", style = "player_input_horizontal_flow"})
  price_row.add({type = "label", style = "caption_label", caption = localised("price")})
  price_row.add({
    type = "textfield",
    name = constants.gui.buy_order_price,
    text = order and tostring(order.unit_price) or "",
    style = "short_number_textfield",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
  })

  selector_row.add({type = "button", name = constants.gui.buy_order_fill_suggested, caption = localised("use-suggested")})
  content.add({type = "label", name = TRADE_BOX_SUGGESTED, style = "caption_label", caption = localised("suggested-price-na")})
  content.add({type = "label", name = TRADE_BOX_STATUS, caption = localised("status-label", localised("no-active-order"))})
  content.add({type = "label", name = TRADE_BOX_STORED, style = "caption_label", caption = localised("stored-count", 0)})
  content.add({type = "label", name = TRADE_BOX_LAST_TRADE, style = "caption_label", caption = localised("last-trade-label", localised("never"))})
  content.add({type = "label", name = TRADE_BOX_TOTAL, style = "caption_label", caption = localised("lifetime-traded", format.localised_money(0))})

  local primary_buttons = content.add({type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow"})
  primary_buttons.style.horizontally_stretchable = true
  local save_button = primary_buttons.add({type = "button", name = constants.gui.buy_order_save, caption = localised("save-order")})
  save_button.style.horizontally_stretchable = true

  local secondary_buttons = content.add({type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow"})
  secondary_buttons.style.horizontally_stretchable = true
  secondary_buttons.style.horizontal_spacing = 12
  local delete_button = secondary_buttons.add({type = "button", name = constants.gui.buy_order_delete, caption = localised("delete-order")})
  delete_button.style.horizontally_stretchable = true
  local toggle_button = secondary_buttons.add({type = "button", name = constants.gui.buy_order_toggle, caption = localised("pause-order")})
  toggle_button.style.horizontally_stretchable = true

  trade.note_trade_box_context(player.index, entity)
  refresh_trade_box_panel(player)
end

function gui.hide_trade_box_panel(player)
  destroy_named_panel(player, constants.gui.trade_box_root)
  set_feedback(player, "trade_box_feedback", nil, nil)
end

function gui.show_selected_inserter(player)
  destroy_named_panel(player, constants.gui.inserter_panel)
  local selected = player.selected
  if not selected or not selected.valid or selected.type ~= "inserter" then
    return
  end

  local frame = player.gui.relative.add({
    type = "frame",
    name = constants.gui.inserter_panel,
    direction = "vertical",
    caption = localised("trade-stats"),
    anchor = {
      gui = defines.relative_gui_type.additional_entity_info_gui,
      position = defines.relative_gui_position.right,
      type = "inserter",
    },
  })
  frame.style.minimal_width = 280

  local body = frame.add({type = "frame", style = "inside_deep_frame", direction = "vertical"})
  body.style.horizontally_stretchable = true
  local header = body.add({type = "frame", style = "subheader_frame"})
  header.style.horizontally_stretchable = true
  header.add({type = "label", style = "subheader_caption_label", caption = localised("inserter")})
  add_horizontal_pusher(header)
  header.add({type = "label", style = "caption_label", caption = format.position(selected)})

  local content_frame = body.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
  content_frame.style.horizontally_stretchable = true
  local content = content_frame.add({type = "flow", name = INSERTER_CONTENT, direction = "vertical"})
  content.style.horizontally_stretchable = true
  content.style.vertical_spacing = 8
  local ui = ui_state(player.index)
  local selected_inserter_id = util.id_key(selected.unit_number)
  local record = entities.register_inserter(selected)
  ui.selected_inserter_id = selected_inserter_id
  ui.inserter_min_price = record and record.min_unit_price and tostring(record.min_unit_price) or ""
  ui.inserter_feedback = nil
  refresh_inserter_panel(player)
end

function gui.handle_click(event)
  local player = game.players[event.player_index]
  local name = event.element.name

  if name == constants.gui.mod_button then
    gui.toggle_main(player)
    return
  end

  if name == "trade_mode_close_main" then
    if main_frame(player) then
      main_frame(player).destroy()
    end
    set_main_shortcut_toggled(player, false)
    return
  end

  if name == constants.gui.buy_order_cancel or name == constants.gui.buy_order_close then
    gui.hide_trade_box_panel(player)
    trade.note_trade_box_context(player.index, nil)
    return
  end

  if name == constants.gui.buy_order_fill_suggested then
    local frame = buy_order_panel(player)
    local item_name = find_descendant(frame, constants.gui.buy_order_item).elem_value
    if item_name then
      local suggested = pricing.get_suggested_price(suggested_prices, item_name)
      if suggested then
        find_descendant(frame, constants.gui.buy_order_price).text = tostring(suggested)
      end
    end
    refresh_trade_box_panel(player)
    return
  end

  if name == constants.gui.buy_order_save then
    local box_record = current_box_record(player)
    if not box_record then
      set_feedback(player, "trade_box_feedback", "error", localised("trade-box-feedback-no-selection"))
      return
    end

    local frame = buy_order_panel(player)
    local item_name = find_descendant(frame, constants.gui.buy_order_item).elem_value
    local unit_price = parse_numeric_text(find_descendant(frame, constants.gui.buy_order_price).text)
    if not item_name or not unit_price then
      set_feedback(player, "trade_box_feedback", "error", localised("trade-box-feedback-invalid"))
      refresh_trade_box_panel(player)
      return
    end

    local state = root()
    local existing = orders.get_by_box_id(state.orders, box_record.box_id)
    if existing then
      orders.update_order(state.orders, existing.id, {
        item_name = item_name,
        unit_price = unit_price,
        status = existing.status,
        tick = game.tick,
      })
    else
      local created = orders.create_order(state.orders, {
        box_id = box_record.box_id,
        buyer_id = player.index,
        buyer_wallet_id = runtime_state.wallet_id_for_player(player.index),
        force_name = player_force_name(player),
        item_name = item_name,
        unit_price = unit_price,
        tick = game.tick,
      })
      if not created.ok then
        set_feedback(player, "trade_box_feedback", "error", localised("trade-box-feedback-existing"))
        refresh_trade_box_panel(player)
        return
      end
    end

    entities.sync_box_filters(box_record.box_id)
    box_record.tracked_item_count = entities.box_inventory(box_record.entity).get_item_count(item_name)
    entities.refresh_tags_for_box(box_record.box_id)
    set_feedback(player, "trade_box_feedback", "success", localised("trade-box-feedback-saved"))
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
      set_feedback(player, "trade_box_feedback", "success", localised("trade-box-feedback-status", localised_status(new_status)))
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
      set_feedback(player, "trade_box_feedback", "success", localised("trade-box-feedback-deleted"))
      refresh_trade_box_panel(player)
      gui.refresh_main(player)
    end
    return
  end

  if name == constants.gui.inserter_min_price_save then
    local selected = player.selected
    if not selected or not selected.valid or selected.type ~= "inserter" then
      set_feedback(player, "inserter_feedback", "error", localised("inserter-feedback-no-selection"))
      refresh_inserter_panel(player)
      return
    end

    local ui = ui_state(player.index)
    local text = ui.inserter_min_price or ""
    local min_unit_price = nil
    if text ~= "" then
      min_unit_price = parse_numeric_text(text)
      if not min_unit_price then
        set_feedback(player, "inserter_feedback", "error", localised("inserter-feedback-invalid"))
        refresh_inserter_panel(player)
        return
      end
    end

    local updated = entities.set_inserter_min_price(selected, min_unit_price)
    if not updated.ok then
      set_feedback(player, "inserter_feedback", "error", localised("inserter-feedback-save-failed"))
    elseif min_unit_price then
      set_feedback(player, "inserter_feedback", "success", localised("inserter-feedback-saved", format.localised_money(min_unit_price)))
    else
      set_feedback(player, "inserter_feedback", "success", localised("inserter-feedback-cleared"))
    end
    ui.inserter_min_price = min_unit_price and tostring(min_unit_price) or ""
    refresh_inserter_panel(player)
    return
  end

  if name == constants.gui.contract_create then
    local ui = ui_state(player.index)
    local amount = parse_numeric_text(ui.contract_amount)
    if ui.contract_title == "" or ui.contract_description == "" or not amount then
      set_feedback(player, "contract_feedback", "error", localised("contract-feedback-invalid"))
      gui.refresh_main(player)
      return
    end

    contracts.create_contract(root().contracts, {
      creator_id = player.index,
      creator_wallet_id = runtime_state.wallet_id_for_player(player.index),
      force_name = player_force_name(player),
      title = ui.contract_title,
      description = ui.contract_description,
      amount = amount,
      tick = game.tick,
    })

    ui.contract_title = ""
    ui.contract_description = ""
    ui.contract_amount = ""
    ui.selected_contract_id = nil
    set_feedback(player, "contract_feedback", "success", localised("contract-feedback-created"))
    gui.refresh_main(player)
    return
  end

  local selected_contract_id = ui_state(player.index).selected_contract_id
  if not selected_contract_id then
    return
  end

  if name == constants.gui.contract_assign then
    local result = contracts.assign_self(
      root().contracts,
      selected_contract_id,
      player.index,
      game.tick,
      player_force_name(player),
      runtime_state.wallet_id_for_player(player.index)
    )
    if not result.ok then
      set_feedback(player, "contract_feedback", "error", localised("contract-feedback-assign-failed", localised_error(result.error)))
    else
      set_feedback(player, "contract_feedback", "success", localised("contract-feedback-assigned"))
      notifications.notify_contract_assigned(result.contract, player.index)
    end
    gui.refresh_main(player)
    return
  end

  if name == constants.gui.contract_unassign then
    local result = contracts.unassign_self(root().contracts, selected_contract_id, player.index, game.tick, player_force_name(player))
    if not result.ok then
      set_feedback(player, "contract_feedback", "error", localised("contract-feedback-unassign-failed", localised_error(result.error)))
    else
      set_feedback(player, "contract_feedback", "success", localised("contract-feedback-unassigned"))
    end
    gui.refresh_main(player)
    return
  end

  if name == constants.gui.contract_pay then
    local result = contracts.payout(root().contracts, root().ledger, selected_contract_id, player.index, game.tick, player_force_name(player))
    if not result.ok then
      set_feedback(player, "contract_feedback", "error", localised("contract-feedback-payout-failed", localised_error(result.error)))
    else
      set_feedback(player, "contract_feedback", "success", localised("contract-feedback-paid"))
    end
    gui.refresh_main(player)
  end
end

function gui.handle_text_changed(event)
  local player = game.players[event.player_index]
  local ui = ui_state(player.index)

  if event.element.name == constants.gui.market_filter then
    ui.market_filter = event.element.text
    refresh_market_tab(player)
    return
  end
  if event.element.name == constants.gui.contract_title then
    ui.contract_title = event.element.text
    return
  end
  if event.element.name == constants.gui.contract_description then
    ui.contract_description = event.element.text
    return
  end
  if event.element.name == constants.gui.contract_amount then
    ui.contract_amount = event.element.text
    return
  end
  if event.element.name == constants.gui.buy_order_price then
    refresh_trade_box_panel(player)
    return
  end
  if event.element.name == constants.gui.inserter_min_price then
    ui.inserter_min_price = event.element.text
    return
  end
end

function gui.handle_elem_changed(event)
  local player = game.players[event.player_index]
  if event.element.name == constants.gui.buy_order_item then
    refresh_trade_box_panel(player)
  end
end

function gui.handle_selection_state_changed(event)
  local player = game.players[event.player_index]
  if event.element.name ~= constants.gui.contract_list then
    return
  end

  local ui = ui_state(player.index)
  local index = event.element.selected_index or 0
  ui.selected_contract_id = ui.contract_list_ids[index]
  ui.contract_feedback = nil
  refresh_contract_detail(player)
end

function gui.handle_selected_tab_changed(event)
  if event.element.name ~= constants.gui.main_tabs then
    return
  end
  ui_state(event.player_index).selected_main_tab = event.element.selected_tab_index or 1
end

function gui.refresh_context_panels(player)
  refresh_mod_button(player)
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
