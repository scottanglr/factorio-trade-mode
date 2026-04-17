local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local ledger = require("trade_mode.core.ledger")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local runtime_state = require("trade_mode.runtime.state")
local ubi = require("trade_mode.core.ubi")

local economy = {}

local function sample_total_raw_ore()
  local total = 0
  local breakdown = {}
  for _, ore_name in ipairs(constants.ore_names) do
    breakdown[ore_name] = 0
  end

  for force_name, force in pairs(game.forces) do
    if force_name ~= "enemy" and force_name ~= "neutral" then
      for _, surface in pairs(game.surfaces) do
        local stats = force.get_item_production_statistics(surface)
        for _, ore_name in ipairs(constants.ore_names) do
          local amount = stats.get_output_count(ore_name)
          breakdown[ore_name] = breakdown[ore_name] + amount
          total = total + amount
        end
      end
    end
  end

  return total, breakdown
end

function economy.tick_second(second)
  local root = runtime_state.root()
  local total, breakdown = sample_total_raw_ore()
  ubi.record_ore_sample(root.ubi, second, total, breakdown)
  local ore_snapshot = ubi.get_recent_ore_per_minute(root.ubi)
  local payout_plan = ubi.plan_distribution(
    root.ubi,
    constants.ubi,
    ore_snapshot.recent_raw_ore_per_minute,
    runtime_state.online_player_ids()
  )

  root.runtime.economy_snapshot.gold_per_second = payout_plan.raw_gold_per_second
  root.runtime.economy_snapshot.recent_raw_ore_per_minute = ore_snapshot.recent_raw_ore_per_minute
  root.runtime.economy_snapshot.breakdown_per_minute = ore_snapshot.breakdown_per_minute

  for player_id, amount in pairs(payout_plan.payouts) do
    if amount > 0 then
      ledger.credit(root.ledger, player_id, amount, "ubi")
      metrics.record_ubi(root.metrics, second, amount, player_id)
    end
  end

  metrics.prune(root.metrics, second, 60)
  metrics.set_snapshot_counts(
    root.metrics,
    orders.count_active(root.orders),
    contracts.count_openish(root.contracts)
  )
end

function economy.snapshot()
  return runtime_state.root().runtime.economy_snapshot
end

return economy
