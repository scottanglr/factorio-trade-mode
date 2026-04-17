local contracts = require("trade_mode.core.contracts")
local constants = require("trade_mode.runtime.constants")
local inserter_stats = require("trade_mode.core.inserter_stats")
local ledger = require("trade_mode.core.ledger")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local ubi = require("trade_mode.core.ubi")

local state = {}

local function ensure_runtime(runtime_state)
  runtime_state.players = runtime_state.players or {}
  runtime_state.trade_boxes = runtime_state.trade_boxes or {}
  runtime_state.inserters = runtime_state.inserters or {}
  runtime_state.manual_insertions = runtime_state.manual_insertions or {}
  runtime_state.market_tags = runtime_state.market_tags or {}
  runtime_state.player_ui = runtime_state.player_ui or {}
  runtime_state.economy_snapshot = runtime_state.economy_snapshot or {
    gold_per_second = 0,
    recent_raw_ore_per_minute = 0,
    breakdown_per_minute = {},
  }
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
  runtime_state.players[player.index] = {
    player_index = player.index,
    name = player.name,
    force_name = player.force.name,
  }
end

function state.player_name(player_index)
  local record = state.runtime().players[player_index]
  if record then
    return record.name
  end
  return "Player " .. tostring(player_index)
end

function state.online_player_ids()
  local ids = {}
  for _, player in pairs(game.connected_players) do
    ids[#ids + 1] = player.index
  end
  table.sort(ids)
  return ids
end

return state
