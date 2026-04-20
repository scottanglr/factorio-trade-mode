local ledger = require("trade_mode.core.ledger")
local util = require("trade_mode.core.util")

local contracts = {}

local STATUS_PRIORITY = {
  open = 1,
  assigned = 2,
  cancelled = 3,
  completed = 4,
}

local function assert_wallet_id(value, field_name)
  if util.is_positive_integer(value) then
    return
  end
  if type(value) == "string" and value ~= "" then
    return
  end
  error(field_name .. " must be a positive integer or non-empty string")
end

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
  if fields.creator_wallet_id ~= nil then
    assert_wallet_id(fields.creator_wallet_id, "creator_wallet_id")
  end

  local contract = {
    id = state.next_id,
    creator_id = fields.creator_id,
    creator_wallet_id = fields.creator_wallet_id or fields.creator_id,
    force_name = fields.force_name,
    title = fields.title,
    description = fields.description,
    amount = fields.amount,
    assignee_id = nil,
    assignee_wallet_id = nil,
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

function contracts.assign_self(state, contract_id, player_id, tick, force_name, assignee_wallet_id)
  local contract = get_contract(state, contract_id)
  util.assert_positive_integer(player_id, "player_id")
  if assignee_wallet_id ~= nil then
    assert_wallet_id(assignee_wallet_id, "assignee_wallet_id")
  end
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

  if contract.force_name and force_name and contract.force_name ~= force_name then
    return {
      ok = false,
      error = "wrong_force",
    }
  end

  contract.assignee_id = player_id
  contract.assignee_wallet_id = assignee_wallet_id or player_id
  contract.status = "assigned"
  contract.updated_tick = tick or contract.updated_tick
  return {
    ok = true,
    contract = contract,
  }
end

function contracts.unassign_self(state, contract_id, player_id, tick, force_name)
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

  if contract.force_name and force_name and contract.force_name ~= force_name then
    return {
      ok = false,
      error = "wrong_force",
    }
  end

  contract.assignee_id = nil
  contract.assignee_wallet_id = nil
  contract.status = "open"
  contract.updated_tick = tick or contract.updated_tick
  return {
    ok = true,
    contract = contract,
  }
end

function contracts.payout(state, ledger_state, contract_id, actor_id, tick, force_name)
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

  if contract.force_name and force_name and contract.force_name ~= force_name then
    return {
      ok = false,
      error = "wrong_force",
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
    contract.creator_wallet_id or contract.creator_id,
    contract.assignee_wallet_id or contract.assignee_id,
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

function contracts.list_all(state, force_name)
  ensure_state(state)
  local list = {}
  for _, contract in pairs(state.by_id) do
    if not force_name or contract.force_name == nil or contract.force_name == force_name then
      list[#list + 1] = contract
    end
  end

  table.sort(list, function(left, right)
    local left_priority = STATUS_PRIORITY[left.status] or 99
    local right_priority = STATUS_PRIORITY[right.status] or 99
    if left_priority ~= right_priority then
      return left_priority < right_priority
    end
    if left.created_tick ~= right.created_tick then
      return (left.created_tick or 0) > (right.created_tick or 0)
    end
    return left.id > right.id
  end)

  return list
end

function contracts.count_openish(state, force_name)
  ensure_state(state)
  local count = 0
  for _, contract in pairs(state.by_id) do
    if contract.status ~= "completed" and (not force_name or contract.force_name == nil or contract.force_name == force_name) then
      count = count + 1
    end
  end
  return count
end

function contracts.normalize(state)
  ensure_state(state)
  for _, contract in pairs(state.by_id) do
    if contract.creator_wallet_id == nil then
      contract.creator_wallet_id = contract.creator_id
    end
    if contract.assignee_id ~= nil and contract.assignee_wallet_id == nil then
      contract.assignee_wallet_id = contract.assignee_id
    end
  end
  return state
end

return contracts
