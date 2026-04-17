local util = require("trade_mode.core.util")

local ledger = {}

local JOURNAL_LIMIT = 256

local function ensure_state(state)
  state.balances = state.balances or {}
  state.journal = state.journal or {}
  state.next_entry_id = state.next_entry_id or 1
  return state
end

local function ensure_account(state, player_id)
  util.assert_positive_integer(player_id, "player_id")
  ensure_state(state)
  if state.balances[player_id] == nil then
    state.balances[player_id] = 0
  end
  return state.balances[player_id]
end

local function append_entry(state, entry)
  util.push_limited(state.journal, entry, JOURNAL_LIMIT)
  state.next_entry_id = state.next_entry_id + 1
end

function ledger.create_account(state, player_id)
  ensure_account(state, player_id)
  return {
    ok = true,
    balance = state.balances[player_id],
  }
end

function ledger.get_balance(state, player_id)
  ensure_account(state, player_id)
  return state.balances[player_id]
end

function ledger.credit(state, player_id, amount, reason)
  util.assert_positive_integer(player_id, "player_id")
  util.assert_positive_integer(amount, "amount")
  util.assert_non_empty_string(reason, "reason")

  ensure_state(state)
  ensure_account(state, player_id)
  state.balances[player_id] = state.balances[player_id] + amount
  append_entry(state, {
    id = state.next_entry_id,
    kind = "credit",
    player_id = player_id,
    amount = amount,
    reason = reason,
  })

  return {
    ok = true,
    balance = state.balances[player_id],
  }
end

function ledger.debit(state, player_id, amount, reason)
  util.assert_positive_integer(player_id, "player_id")
  util.assert_positive_integer(amount, "amount")
  util.assert_non_empty_string(reason, "reason")

  ensure_state(state)
  ensure_account(state, player_id)
  if state.balances[player_id] < amount then
    return {
      ok = false,
      error = "insufficient_funds",
      balance = state.balances[player_id],
    }
  end

  state.balances[player_id] = state.balances[player_id] - amount
  append_entry(state, {
    id = state.next_entry_id,
    kind = "debit",
    player_id = player_id,
    amount = amount,
    reason = reason,
  })

  return {
    ok = true,
    balance = state.balances[player_id],
  }
end

function ledger.transfer(state, from_player_id, to_player_id, amount, reason)
  util.assert_positive_integer(from_player_id, "from_player_id")
  util.assert_positive_integer(to_player_id, "to_player_id")
  util.assert_positive_integer(amount, "amount")
  util.assert_non_empty_string(reason, "reason")

  ensure_state(state)
  ensure_account(state, from_player_id)
  ensure_account(state, to_player_id)

  if state.balances[from_player_id] < amount then
    return {
      ok = false,
      error = "insufficient_funds",
      from_balance = state.balances[from_player_id],
      to_balance = state.balances[to_player_id],
    }
  end

  state.balances[from_player_id] = state.balances[from_player_id] - amount
  state.balances[to_player_id] = state.balances[to_player_id] + amount
  append_entry(state, {
    id = state.next_entry_id,
    kind = "transfer",
    from_player_id = from_player_id,
    to_player_id = to_player_id,
    amount = amount,
    reason = reason,
  })

  return {
    ok = true,
    from_balance = state.balances[from_player_id],
    to_balance = state.balances[to_player_id],
  }
end

function ledger.top_balances(state, limit)
  ensure_state(state)
  local entries = {}
  for player_id, balance in pairs(state.balances) do
    entries[#entries + 1] = {
      player_id = player_id,
      balance = balance,
    }
  end

  table.sort(entries, function(left, right)
    if left.balance == right.balance then
      return left.player_id < right.player_id
    end
    return left.balance > right.balance
  end)

  if limit and #entries > limit then
    while #entries > limit do
      table.remove(entries)
    end
  end

  return entries
end

function ledger.normalize(state)
  ensure_state(state)
  return state
end

return ledger

