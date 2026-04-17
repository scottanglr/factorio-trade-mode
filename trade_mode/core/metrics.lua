local util = require("trade_mode.core.util")

local metrics = {}

local DEFAULT_WINDOW = 60

local function ensure_state(state)
  state.windows = state.windows or {}
  state.windows.traded = state.windows.traded or {}
  state.windows.ubi = state.windows.ubi or {}
  state.snapshots = state.snapshots or {}
  state.snapshots.active_orders = state.snapshots.active_orders or 0
  state.snapshots.active_contracts = state.snapshots.active_contracts or 0
  return state
end

local function ensure_bucket(bucket_map, second)
  local bucket = bucket_map[second]
  if bucket == nil then
    bucket = {
      total = 0,
      by_force = {},
      by_payer = {},
      by_recipient = {},
      by_player = {},
    }
    bucket_map[second] = bucket
  end
  return bucket
end

local function prune_window(bucket_map, current_second, window_seconds)
  for second in pairs(bucket_map) do
    if second <= (current_second - window_seconds) then
      bucket_map[second] = nil
    end
  end
end

local function aggregate_actor_map(bucket_map, current_second, window_seconds, field_name, row_filter)
  local aggregate = {}
  for second, bucket in pairs(bucket_map) do
    if second > (current_second - window_seconds) then
      for actor_id, amount in pairs(bucket[field_name]) do
        aggregate[actor_id] = (aggregate[actor_id] or 0) + amount
      end
    end
  end

  local rows = {}
  for actor_id, amount in pairs(aggregate) do
    local row = {
      player_id = actor_id,
      amount = amount,
    }
    if row_filter == nil or row_filter(row) then
      rows[#rows + 1] = row
    end
  end

  table.sort(rows, function(left, right)
    if left.amount == right.amount then
      return left.player_id < right.player_id
    end
    return left.amount > right.amount
  end)

  return rows
end

function metrics.record_trade(state, second, amount, payer_id, recipient_id, force_name)
  ensure_state(state)
  util.assert_non_negative_integer(second, "second")
  util.assert_positive_integer(amount, "amount")
  util.assert_positive_integer(payer_id, "payer_id")
  util.assert_positive_integer(recipient_id, "recipient_id")

  local bucket = ensure_bucket(state.windows.traded, second)
  bucket.total = bucket.total + amount
  if force_name then
    bucket.by_force[force_name] = (bucket.by_force[force_name] or 0) + amount
  end
  bucket.by_payer[payer_id] = (bucket.by_payer[payer_id] or 0) + amount
  bucket.by_recipient[recipient_id] = (bucket.by_recipient[recipient_id] or 0) + amount
end

function metrics.record_ubi(state, second, amount, player_id, force_name)
  ensure_state(state)
  util.assert_non_negative_integer(second, "second")
  util.assert_positive_integer(amount, "amount")
  util.assert_positive_integer(player_id, "player_id")

  local bucket = ensure_bucket(state.windows.ubi, second)
  bucket.total = bucket.total + amount
  if force_name then
    bucket.by_force[force_name] = (bucket.by_force[force_name] or 0) + amount
  end
  bucket.by_player[player_id] = (bucket.by_player[player_id] or 0) + amount
end

function metrics.sum_window(state, window_name, current_second, window_seconds, force_name)
  ensure_state(state)
  local bucket_map = state.windows[window_name]
  local total = 0
  for second, bucket in pairs(bucket_map) do
    if second > (current_second - window_seconds) then
      if force_name then
        total = total + (bucket.by_force[force_name] or 0)
      else
        total = total + bucket.total
      end
    end
  end
  return total
end

function metrics.trade_last_minute(state, current_second, force_name)
  return metrics.sum_window(state, "traded", current_second, DEFAULT_WINDOW, force_name)
end

function metrics.ubi_last_minute(state, current_second, force_name)
  return metrics.sum_window(state, "ubi", current_second, DEFAULT_WINDOW, force_name)
end

function metrics.top_payers(state, current_second, limit, row_filter)
  local rows = aggregate_actor_map(ensure_state(state).windows.traded, current_second, DEFAULT_WINDOW, "by_payer", row_filter)
  if limit and #rows > limit then
    while #rows > limit do
      table.remove(rows)
    end
  end
  return rows
end

function metrics.top_recipients(state, current_second, limit, row_filter)
  local rows = aggregate_actor_map(ensure_state(state).windows.traded, current_second, DEFAULT_WINDOW, "by_recipient", row_filter)
  if limit and #rows > limit then
    while #rows > limit do
      table.remove(rows)
    end
  end
  return rows
end

function metrics.set_snapshot_counts(state, active_orders, active_contracts)
  ensure_state(state)
  util.assert_non_negative_integer(active_orders, "active_orders")
  util.assert_non_negative_integer(active_contracts, "active_contracts")
  state.snapshots.active_orders = active_orders
  state.snapshots.active_contracts = active_contracts
end

function metrics.prune(state, current_second, window_seconds)
  ensure_state(state)
  prune_window(state.windows.traded, current_second, window_seconds or DEFAULT_WINDOW)
  prune_window(state.windows.ubi, current_second, window_seconds or DEFAULT_WINDOW)
end

function metrics.normalize(state)
  ensure_state(state)
  return state
end

return metrics
