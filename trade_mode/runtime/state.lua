local contracts = require("trade_mode.core.contracts")
local constants = require("trade_mode.runtime.constants")
local inserter_stats = require("trade_mode.core.inserter_stats")
local ledger = require("trade_mode.core.ledger")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local ubi = require("trade_mode.core.ubi")

local state = {}

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

function state.player_name(player_index)
  local record = state.runtime().players[player_index]
  if record then
    return record.name
  end
  return "Player " .. tostring(player_index)
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

function state.order_force_name(order)
  if not order then
    return nil
  end
  return order.force_name or state.box_force_name(order.box_id) or state.player_force_name(order.buyer_id)
end

function state.contract_force_name(contract)
  if not contract then
    return nil
  end
  return contract.force_name or state.player_force_name(contract.creator_id)
end

return state
