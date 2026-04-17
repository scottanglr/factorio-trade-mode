local util = require("trade_mode.core.util")

local inserter_stats = {}

local function ensure_state(state)
  state.by_id = state.by_id or {}
  return state
end

local function ensure_entry(state, inserter_id)
  ensure_state(state)
  local key = util.id_key(inserter_id)
  if state.by_id[key] == nil then
    state.by_id[key] = {
      inserter_id = key,
      owner_id = nil,
      lifetime_payout = 0,
      last_recipient_id = nil,
      last_trade_tick = nil,
      last_box_id = nil,
    }
  end
  return state.by_id[key]
end

function inserter_stats.record_payout(state, inserter_id, owner_id, amount, recipient_id, tick, box_id)
  util.assert_positive_integer(owner_id, "owner_id")
  util.assert_positive_integer(amount, "amount")
  util.assert_positive_integer(recipient_id, "recipient_id")

  local entry = ensure_entry(state, inserter_id)
  entry.owner_id = owner_id
  entry.lifetime_payout = entry.lifetime_payout + amount
  entry.last_recipient_id = recipient_id
  entry.last_trade_tick = tick
  entry.last_box_id = box_id and util.id_key(box_id) or nil
  return entry
end

function inserter_stats.get(state, inserter_id)
  ensure_state(state)
  return state.by_id[util.id_key(inserter_id)]
end

function inserter_stats.top(state, limit)
  ensure_state(state)
  local rows = {}
  for _, entry in pairs(state.by_id) do
    rows[#rows + 1] = entry
  end

  table.sort(rows, function(left, right)
    if left.lifetime_payout == right.lifetime_payout then
      return left.inserter_id < right.inserter_id
    end
    return left.lifetime_payout > right.lifetime_payout
  end)

  if limit and #rows > limit then
    while #rows > limit do
      table.remove(rows)
    end
  end

  return rows
end

function inserter_stats.normalize(state)
  ensure_state(state)
  return state
end

return inserter_stats

