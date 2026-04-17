local ledger = require("trade_mode.core.ledger")
local util = require("trade_mode.core.util")

local contracts = {}

local function ensure_state(state)
  state.next_id = state.next_id or 1
  state.by_id = state.by_id or {}
  return state
end

local function get_contract(state, contract_id)
  ensure_state(state)
  util.assert_positive_integer(contract_id, "contract_id")
  return state.by_id[contract_id]
end

function contracts.create_contract(state, fields)
  ensure_state(state)
  util.assert_positive_integer(fields.creator_id, "creator_id")
  util.assert_non_empty_string(fields.title, "title")
  util.assert_non_empty_string(fields.description, "description")
  util.assert_positive_integer(fields.amount, "amount")

  local contract = {
    id = state.next_id,
    creator_id = fields.creator_id,
    title = fields.title,
    description = fields.description,
    amount = fields.amount,
    assignee_id = nil,
    status = "open",
    created_tick = fields.tick or 0,
    updated_tick = fields.tick or 0,
    paid_tick = nil,
  }

  state.by_id[contract.id] = contract
  state.next_id = state.next_id + 1
  return {
    ok = true,
    contract = contract,
  }
end

function contracts.get_by_id(state, contract_id)
  return get_contract(state, contract_id)
end

function contracts.assign_self(state, contract_id, player_id, tick)
  local contract = get_contract(state, contract_id)
  util.assert_positive_integer(player_id, "player_id")
  if not contract then
    return {
      ok = false,
      error = "contract_not_found",
    }
  end

  if contract.status == "completed" then
    return {
      ok = false,
      error = "contract_completed",
    }
  end

  if contract.creator_id == player_id then
    return {
      ok = false,
      error = "creator_cannot_assign",
    }
  end

  contract.assignee_id = player_id
  contract.status = "assigned"
  contract.updated_tick = tick or contract.updated_tick
  return {
    ok = true,
    contract = contract,
  }
end

function contracts.unassign_self(state, contract_id, player_id, tick)
  local contract = get_contract(state, contract_id)
  util.assert_positive_integer(player_id, "player_id")
  if not contract then
    return {
      ok = false,
      error = "contract_not_found",
    }
  end

  if contract.status == "completed" then
    return {
      ok = false,
      error = "contract_completed",
    }
  end

  if contract.assignee_id ~= player_id then
    return {
      ok = false,
      error = "not_assignee",
    }
  end

  contract.assignee_id = nil
  contract.status = "open"
  contract.updated_tick = tick or contract.updated_tick
  return {
    ok = true,
    contract = contract,
  }
end

function contracts.payout(state, ledger_state, contract_id, actor_id, tick)
  local contract = get_contract(state, contract_id)
  util.assert_positive_integer(actor_id, "actor_id")
  if not contract then
    return {
      ok = false,
      error = "contract_not_found",
    }
  end

  if contract.creator_id ~= actor_id then
    return {
      ok = false,
      error = "unauthorized",
    }
  end

  if contract.status ~= "assigned" or contract.assignee_id == nil then
    return {
      ok = false,
      error = "no_assignee",
    }
  end

  local transfer = ledger.transfer(
    ledger_state,
    contract.creator_id,
    contract.assignee_id,
    contract.amount,
    "contract:" .. tostring(contract.id)
  )

  if not transfer.ok then
    return {
      ok = false,
      error = transfer.error,
    }
  end

  contract.status = "completed"
  contract.updated_tick = tick or contract.updated_tick
  contract.paid_tick = tick or contract.updated_tick
  return {
    ok = true,
    contract = contract,
    from_balance = transfer.from_balance,
    to_balance = transfer.to_balance,
  }
end

function contracts.list_all(state)
  ensure_state(state)
  local list = {}
  for _, contract in pairs(state.by_id) do
    list[#list + 1] = contract
  end

  table.sort(list, function(left, right)
    if left.status ~= right.status then
      return left.status < right.status
    end
    if left.title ~= right.title then
      return left.title < right.title
    end
    return left.id < right.id
  end)

  return list
end

function contracts.count_openish(state)
  ensure_state(state)
  local count = 0
  for _, contract in pairs(state.by_id) do
    if contract.status ~= "completed" then
      count = count + 1
    end
  end
  return count
end

function contracts.normalize(state)
  ensure_state(state)
  return state
end

return contracts
