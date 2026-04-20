local util = require("trade_mode.core.util")

local ledger = {}

local JOURNAL_LIMIT = 256

local function normalize_account_id(account_id, field_name)
  if util.is_positive_integer(account_id) then
    return account_id
  end
  if type(account_id) == "string" and account_id ~= "" then
    return account_id
  end
  error((field_name or "account_id") .. " must be a positive integer or non-empty string")
end

local function ensure_state(state)
  state.balances = state.balances or {}
  state.journal = state.journal or {}
  state.next_entry_id = state.next_entry_id or 1
  return state
end

local function ensure_account(state, account_id, field_name)
  account_id = normalize_account_id(account_id, field_name or "account_id")
  ensure_state(state)
  if state.balances[account_id] == nil then
    state.balances[account_id] = 0
  end
  return state.balances[account_id], account_id
end

local function append_entry(state, entry)
  util.push_limited(state.journal, entry, JOURNAL_LIMIT)
  state.next_entry_id = state.next_entry_id + 1
end

function ledger.create_account(state, account_id)
  local _, normalized_account_id = ensure_account(state, account_id, "account_id")
  return {
    ok = true,
    balance = state.balances[normalized_account_id],
  }
end

function ledger.get_balance(state, account_id)
  local _, normalized_account_id = ensure_account(state, account_id, "account_id")
  return state.balances[normalized_account_id]
end

function ledger.credit(state, account_id, amount, reason)
  local normalized_account_id = normalize_account_id(account_id, "account_id")
  util.assert_positive_integer(amount, "amount")
  util.assert_non_empty_string(reason, "reason")

  ensure_state(state)
  ensure_account(state, normalized_account_id, "account_id")
  state.balances[normalized_account_id] = state.balances[normalized_account_id] + amount
  append_entry(state, {
    id = state.next_entry_id,
    kind = "credit",
    account_id = normalized_account_id,
    amount = amount,
    reason = reason,
  })

  return {
    ok = true,
    balance = state.balances[normalized_account_id],
  }
end

function ledger.debit(state, account_id, amount, reason)
  local normalized_account_id = normalize_account_id(account_id, "account_id")
  util.assert_positive_integer(amount, "amount")
  util.assert_non_empty_string(reason, "reason")

  ensure_state(state)
  ensure_account(state, normalized_account_id, "account_id")
  if state.balances[normalized_account_id] < amount then
    return {
      ok = false,
      error = "insufficient_funds",
      balance = state.balances[normalized_account_id],
    }
  end

  state.balances[normalized_account_id] = state.balances[normalized_account_id] - amount
  append_entry(state, {
    id = state.next_entry_id,
    kind = "debit",
    account_id = normalized_account_id,
    amount = amount,
    reason = reason,
  })

  return {
    ok = true,
    balance = state.balances[normalized_account_id],
  }
end

function ledger.transfer(state, from_account_id, to_account_id, amount, reason)
  local normalized_from = normalize_account_id(from_account_id, "from_account_id")
  local normalized_to = normalize_account_id(to_account_id, "to_account_id")
  util.assert_positive_integer(amount, "amount")
  util.assert_non_empty_string(reason, "reason")

  ensure_state(state)
  ensure_account(state, normalized_from, "from_account_id")
  ensure_account(state, normalized_to, "to_account_id")

  if state.balances[normalized_from] < amount then
    return {
      ok = false,
      error = "insufficient_funds",
      from_balance = state.balances[normalized_from],
      to_balance = state.balances[normalized_to],
    }
  end

  state.balances[normalized_from] = state.balances[normalized_from] - amount
  state.balances[normalized_to] = state.balances[normalized_to] + amount
  append_entry(state, {
    id = state.next_entry_id,
    kind = "transfer",
    from_account_id = normalized_from,
    to_account_id = normalized_to,
    amount = amount,
    reason = reason,
  })

  return {
    ok = true,
    from_balance = state.balances[normalized_from],
    to_balance = state.balances[normalized_to],
  }
end

function ledger.top_balances(state, limit)
  ensure_state(state)
  local entries = {}
  for account_id, balance in pairs(state.balances) do
    entries[#entries + 1] = {
      account_id = account_id,
      player_id = account_id,
      balance = balance,
    }
  end

  table.sort(entries, function(left, right)
    if left.balance == right.balance then
      return tostring(left.account_id) < tostring(right.account_id)
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
