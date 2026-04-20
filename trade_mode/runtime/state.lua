local contracts = require("trade_mode.core.contracts")
local constants = require("trade_mode.runtime.constants")
local inserter_stats = require("trade_mode.core.inserter_stats")
local ledger = require("trade_mode.core.ledger")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local ubi = require("trade_mode.core.ubi")

local state = {}

local FORCE_WALLET_PREFIX = "force:"

local function empty_economy_snapshot()
  return {
    gold_per_second = 0,
    recent_raw_ore_per_minute = 0,
    breakdown_per_minute = {},
  }
end

local function ensure_runtime(runtime_state)
  runtime_state.players = runtime_state.players or {}
  runtime_state.trade_boxes = runtime_state.trade_boxes or {}
  runtime_state.inserters = runtime_state.inserters or {}
  runtime_state.manual_insertions = runtime_state.manual_insertions or {}
  runtime_state.market_tags = runtime_state.market_tags or {}
  runtime_state.player_ui = runtime_state.player_ui or {}
  runtime_state.economy_snapshot = runtime_state.economy_snapshot or empty_economy_snapshot()
  runtime_state.economy_snapshots = runtime_state.economy_snapshots or {}
  return runtime_state
end

local function is_reserved_force(force_name)
  return force_name == "enemy" or force_name == "neutral"
end

local function force_wallet_id(force_name)
  if not force_name or force_name == "" or is_reserved_force(force_name) then
    return nil
  end
  return FORCE_WALLET_PREFIX .. force_name
end

function state.root()
  storage.trade_mode = storage.trade_mode or {}
  storage.trade_mode.version = constants.storage_version
  storage.trade_mode.ledger = ledger.normalize(storage.trade_mode.ledger or {})
  storage.trade_mode.orders = orders.normalize(storage.trade_mode.orders or {})
  storage.trade_mode.contracts = contracts.normalize(storage.trade_mode.contracts or {})
  storage.trade_mode.metrics = metrics.normalize(storage.trade_mode.metrics or {})
  storage.trade_mode.ubi = ubi.normalize(storage.trade_mode.ubi or {})
  storage.trade_mode.ubi_by_force = storage.trade_mode.ubi_by_force or {}
  for force_name, force_state in pairs(storage.trade_mode.ubi_by_force) do
    storage.trade_mode.ubi_by_force[force_name] = ubi.normalize(force_state or {})
  end
  storage.trade_mode.inserter_stats = inserter_stats.normalize(storage.trade_mode.inserter_stats or {})
  storage.trade_mode.runtime = ensure_runtime(storage.trade_mode.runtime or {})
  return storage.trade_mode
end

function state.runtime()
  return state.root().runtime
end

function state.current_second(tick)
  return math.floor((tick or game.tick) / constants.ticks.second)
end

function state.track_player(player)
  local runtime_state = state.runtime()
  local existing = runtime_state.players[player.index] or {}
  existing.player_index = player.index
  existing.name = player.name
  existing.force_name = player.force.name
  runtime_state.players[player.index] = existing
end

function state.set_tracked_player_force(player_index, force_name)
  local runtime_state = state.runtime()
  local existing = runtime_state.players[player_index] or {
    player_index = player_index,
    name = "Player " .. tostring(player_index),
  }
  existing.force_name = force_name
  runtime_state.players[player_index] = existing
end

function state.player_name(player_index)
  local record = state.runtime().players[player_index]
  if record then
    return record.name
  end
  return "Player " .. tostring(player_index)
end

function state.actor_name(actor_id)
  if type(actor_id) == "string" and string.sub(actor_id, 1, #FORCE_WALLET_PREFIX) == FORCE_WALLET_PREFIX then
    return "Force " .. string.sub(actor_id, #FORCE_WALLET_PREFIX + 1)
  end
  return state.player_name(actor_id)
end

function state.player_force_name(player_index)
  local record = state.runtime().players[player_index]
  if record and record.force_name then
    return record.force_name
  end

  local player = game and game.get_player(player_index)
  if player and player.valid then
    return player.force.name
  end

  return nil
end

function state.player_in_force(player_index, force_name)
  if not force_name then
    return true
  end
  local player_force = state.player_force_name(player_index)
  if player_force == nil then
    return true
  end
  return player_force == force_name
end

function state.account_force_name(account_id)
  if type(account_id) == "string" and string.sub(account_id, 1, #FORCE_WALLET_PREFIX) == FORCE_WALLET_PREFIX then
    return string.sub(account_id, #FORCE_WALLET_PREFIX + 1)
  end
  if type(account_id) == "number" then
    return state.player_force_name(account_id)
  end
  return nil
end

function state.wallet_id_for_force(force_name)
  return force_wallet_id(force_name)
end

function state.wallet_id_for_player(player_index)
  local force_name = state.player_force_name(player_index)
  local wallet_id = force_wallet_id(force_name)
  if wallet_id ~= nil then
    return wallet_id
  end
  return player_index
end

function state.ensure_force_wallet(force_name)
  local wallet_id = force_wallet_id(force_name)
  if wallet_id ~= nil then
    ledger.create_account(state.root().ledger, wallet_id)
  end
  return wallet_id
end

function state.ensure_player_wallet(player_index)
  local wallet_id = state.wallet_id_for_player(player_index)
  ledger.create_account(state.root().ledger, wallet_id)
  return wallet_id
end

function state.migrate_legacy_player_wallet(player_index)
  local wallet_id = state.wallet_id_for_player(player_index)
  if wallet_id == player_index then
    return
  end

  local root = state.root()
  local legacy_balance = ledger.get_balance(root.ledger, player_index)
  if legacy_balance <= 0 then
    return
  end

  ledger.create_account(root.ledger, wallet_id)
  ledger.transfer(root.ledger, player_index, wallet_id, legacy_balance, "wallet_migration")
end

function state.merge_force_wallets(source_force_name, destination_force_name)
  if not source_force_name or not destination_force_name or source_force_name == destination_force_name then
    return
  end

  local source_wallet_id = force_wallet_id(source_force_name)
  local destination_wallet_id = force_wallet_id(destination_force_name)
  if not source_wallet_id or not destination_wallet_id then
    return
  end

  local root = state.root()
  ledger.create_account(root.ledger, source_wallet_id)
  ledger.create_account(root.ledger, destination_wallet_id)
  local transferable = ledger.get_balance(root.ledger, source_wallet_id)
  if transferable <= 0 then
    return
  end

  ledger.transfer(
    root.ledger,
    source_wallet_id,
    destination_wallet_id,
    transferable,
    "force_merge:" .. source_force_name .. "->" .. destination_force_name
  )
end

function state.player_balance(player_index)
  return ledger.get_balance(state.root().ledger, state.wallet_id_for_player(player_index))
end

function state.account_in_force(account_id, force_name)
  if not force_name then
    return true
  end
  local account_force = state.account_force_name(account_id)
  if not account_force then
    return true
  end
  return account_force == force_name
end

function state.force_wallet_rows(force_name, limit)
  local rows = {}
  if not game then
    return rows
  end

  for _, force in pairs(game.forces) do
    if not is_reserved_force(force.name) and (not force_name or force.name == force_name) then
      local wallet_id = state.ensure_force_wallet(force.name)
      rows[#rows + 1] = {
        account_id = wallet_id,
        balance = ledger.get_balance(state.root().ledger, wallet_id),
      }
    end
  end

  table.sort(rows, function(left, right)
    if left.balance == right.balance then
      return tostring(left.account_id) < tostring(right.account_id)
    end
    return left.balance > right.balance
  end)

  if limit and #rows > limit then
    while #rows > limit do
      table.remove(rows)
    end
  end
  return rows
end

function state.online_player_ids(force_name)
  local ids = {}
  for _, player in pairs(game.connected_players) do
    if not force_name or player.force.name == force_name then
      ids[#ids + 1] = player.index
    end
  end
  table.sort(ids)
  return ids
end

function state.ubi_state(force_name)
  local root = state.root()
  local key = force_name or "_global"
  root.ubi_by_force[key] = ubi.normalize(root.ubi_by_force[key] or {})
  return root.ubi_by_force[key]
end

function state.economy_snapshot(force_name)
  local runtime_state = state.runtime()
  if not force_name then
    runtime_state.economy_snapshot = runtime_state.economy_snapshot or empty_economy_snapshot()
    return runtime_state.economy_snapshot
  end

  runtime_state.economy_snapshots[force_name] = runtime_state.economy_snapshots[force_name] or empty_economy_snapshot()
  return runtime_state.economy_snapshots[force_name]
end

function state.box_force_name(box_id)
  local record = state.runtime().trade_boxes[box_id]
  if record and record.entity and record.entity.valid then
    return record.entity.force.name
  end
  return nil
end

function state.order_wallet_id(order)
  if not order then
    return nil
  end
  return order.buyer_wallet_id or force_wallet_id(order.force_name) or state.wallet_id_for_player(order.buyer_id)
end

function state.contract_creator_wallet_id(contract)
  if not contract then
    return nil
  end
  return contract.creator_wallet_id or force_wallet_id(contract.force_name) or state.wallet_id_for_player(contract.creator_id)
end

function state.contract_assignee_wallet_id(contract)
  if not contract then
    return nil
  end
  if contract.assignee_wallet_id ~= nil then
    return contract.assignee_wallet_id
  end
  if contract.assignee_id ~= nil then
    return state.wallet_id_for_player(contract.assignee_id)
  end
  return nil
end

function state.order_force_name(order)
  if not order then
    return nil
  end
  return order.force_name or state.account_force_name(order.buyer_wallet_id) or state.box_force_name(order.box_id) or state.player_force_name(order.buyer_id)
end

function state.contract_force_name(contract)
  if not contract then
    return nil
  end
  return contract.force_name or state.account_force_name(contract.creator_wallet_id) or state.player_force_name(contract.creator_id)
end

return state
