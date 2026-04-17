local ledger = require("trade_mode.core.ledger")
local pricing = require("trade_mode.core.pricing")
local util = require("trade_mode.core.util")

local orders = {}

local VALID_STATUSES = {
  active = true,
  paused = true,
  cancelled = true,
}

local function ensure_state(state)
  state.next_id = state.next_id or 1
  state.by_id = state.by_id or {}
  state.by_box_id = state.by_box_id or {}
  return state
end

local function normalize_box_id(box_id)
  return util.id_key(box_id)
end

local function validate_status(status)
  if not VALID_STATUSES[status] then
    error("invalid order status")
  end
end

local function get_order(state, order_id)
  ensure_state(state)
  util.assert_positive_integer(order_id, "order_id")
  return state.by_id[order_id]
end

function orders.create_order(state, fields)
  ensure_state(state)
  util.assert_positive_integer(fields.buyer_id, "buyer_id")
  util.assert_non_empty_string(fields.item_name, "item_name")
  pricing.validate_unit_price(fields.unit_price)

  local box_id = normalize_box_id(fields.box_id)
  if state.by_box_id[box_id] ~= nil then
    return {
      ok = false,
      error = "box_already_has_order",
    }
  end

  local order = {
    id = state.next_id,
    box_id = box_id,
    buyer_id = fields.buyer_id,
    force_name = fields.force_name,
    item_name = fields.item_name,
    unit_price = fields.unit_price,
    status = "active",
    created_tick = fields.tick or 0,
    updated_tick = fields.tick or 0,
    last_trade_tick = nil,
    last_trade_total = 0,
    last_recipient_id = nil,
    total_traded = 0,
    total_units_traded = 0,
  }

  state.by_id[order.id] = order
  state.by_box_id[box_id] = order.id
  state.next_id = state.next_id + 1
  return {
    ok = true,
    order = order,
  }
end

function orders.get_by_id(state, order_id)
  return get_order(state, order_id)
end

function orders.get_by_box_id(state, box_id)
  ensure_state(state)
  local order_id = state.by_box_id[normalize_box_id(box_id)]
  if order_id == nil then
    return nil
  end

  return state.by_id[order_id]
end

function orders.update_order(state, order_id, fields)
  local order = get_order(state, order_id)
  if not order then
    return {
      ok = false,
      error = "order_not_found",
    }
  end

  if fields.item_name ~= nil then
    util.assert_non_empty_string(fields.item_name, "item_name")
    order.item_name = fields.item_name
  end

  if fields.unit_price ~= nil then
    pricing.validate_unit_price(fields.unit_price)
    order.unit_price = fields.unit_price
  end

  if fields.status ~= nil then
    validate_status(fields.status)
    order.status = fields.status
  end

  if fields.tick ~= nil then
    order.updated_tick = fields.tick
  end

  return {
    ok = true,
    order = order,
  }
end

function orders.cancel_order(state, order_id, tick)
  local order = get_order(state, order_id)
  if not order then
    return {
      ok = false,
      error = "order_not_found",
    }
  end

  order.status = "cancelled"
  order.updated_tick = tick or order.updated_tick
  order.cancelled_tick = tick or order.updated_tick
  state.by_box_id[order.box_id] = nil

  return {
    ok = true,
    order = order,
  }
end

function orders.set_status(state, order_id, status, tick)
  validate_status(status)
  if status == "cancelled" then
    return orders.cancel_order(state, order_id, tick)
  end

  return orders.update_order(state, order_id, {
    status = status,
    tick = tick,
  })
end

function orders.list_current(state)
  ensure_state(state)
  local list = {}
  for _, order in pairs(state.by_id) do
    if order.status ~= "cancelled" then
      list[#list + 1] = order
    end
  end

  table.sort(list, function(left, right)
    if left.item_name ~= right.item_name then
      return left.item_name < right.item_name
    end
    if left.unit_price ~= right.unit_price then
      return left.unit_price < right.unit_price
    end
    return left.box_id < right.box_id
  end)

  return list
end

function orders.count_active(state)
  ensure_state(state)
  local count = 0
  for _, order in pairs(state.by_id) do
    if order.status == "active" then
      count = count + 1
    end
  end
  return count
end

function orders.settle_insert(state, ledger_state, order_id, recipient_id, quantity, tick)
  local order = get_order(state, order_id)
  util.assert_positive_integer(recipient_id, "recipient_id")
  util.assert_positive_integer(quantity, "quantity")

  if not order then
    return {
      ok = false,
      error = "order_not_found",
    }
  end

  if order.status ~= "active" then
    return {
      ok = false,
      error = "order_not_active",
      status = order.status,
    }
  end

  local total = order.unit_price * quantity
  local transfer = ledger.transfer(
    ledger_state,
    order.buyer_id,
    recipient_id,
    total,
    "buy_order:" .. tostring(order.id)
  )

  if not transfer.ok then
    return {
      ok = false,
      error = transfer.error,
      total = total,
      order = order,
    }
  end

  order.updated_tick = tick or order.updated_tick
  order.last_trade_tick = tick or order.last_trade_tick
  order.last_trade_total = total
  order.last_recipient_id = recipient_id
  order.total_traded = order.total_traded + total
  order.total_units_traded = order.total_units_traded + quantity

  return {
    ok = true,
    total = total,
    order = order,
    from_balance = transfer.from_balance,
    to_balance = transfer.to_balance,
  }
end

function orders.normalize(state)
  ensure_state(state)
  return state
end

return orders
