local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local ledger = require("trade_mode.core.ledger")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local runtime_state = require("trade_mode.runtime.state")
local ubi = require("trade_mode.core.ubi")

local economy = {}

local function empty_breakdown()
  local breakdown = {}
  for _, ore_name in ipairs(constants.ore_names) do
    breakdown[ore_name] = 0
  end
  return breakdown
end

local function sample_total_raw_ore()
  local per_force = {}
  local total = 0
  local total_breakdown = empty_breakdown()

  for force_name, force in pairs(game.forces) do
    if force_name ~= "enemy" and force_name ~= "neutral" then
      local force_total = 0
      local force_breakdown = empty_breakdown()
      for _, surface in pairs(game.surfaces) do
        local stats = force.get_item_production_statistics(surface)
        for _, ore_name in ipairs(constants.ore_names) do
          local amount = stats.get_output_count(ore_name)
          force_breakdown[ore_name] = force_breakdown[ore_name] + amount
          total_breakdown[ore_name] = total_breakdown[ore_name] + amount
          force_total = force_total + amount
          total = total + amount
        end
      end
      per_force[force_name] = {
        total = force_total,
        breakdown = force_breakdown,
      }
    end
  end

  return per_force, {
    total = total,
    breakdown = total_breakdown,
  }
end

function economy.tick_second(second)
  local root = runtime_state.root()
  local runtime = runtime_state.runtime()
  local per_force = sample_total_raw_ore()
  local total_gold_per_second = 0
  local total_recent_raw_ore_per_minute = 0
  local total_breakdown_per_minute = empty_breakdown()

  runtime.economy_snapshots = {}

  for force_name, sample in pairs(per_force) do
    local force_ubi = runtime_state.ubi_state(force_name)
    ubi.record_ore_sample(force_ubi, second, sample.total, sample.breakdown)
    local ore_snapshot = ubi.get_recent_ore_per_minute(force_ubi)
    local payout_plan = ubi.plan_distribution(
      force_ubi,
      constants.ubi,
      ore_snapshot.recent_raw_ore_per_minute,
      runtime_state.online_player_ids(force_name)
    )

    runtime.economy_snapshots[force_name] = {
      gold_per_second = payout_plan.raw_gold_per_second,
      recent_raw_ore_per_minute = ore_snapshot.recent_raw_ore_per_minute,
      breakdown_per_minute = ore_snapshot.breakdown_per_minute,
    }

    total_gold_per_second = total_gold_per_second + payout_plan.raw_gold_per_second
    total_recent_raw_ore_per_minute = total_recent_raw_ore_per_minute + ore_snapshot.recent_raw_ore_per_minute
    for _, ore_name in ipairs(constants.ore_names) do
      total_breakdown_per_minute[ore_name] = total_breakdown_per_minute[ore_name] + (ore_snapshot.breakdown_per_minute[ore_name] or 0)
    end

    for player_id, amount in pairs(payout_plan.payouts) do
      if amount > 0 then
        ledger.credit(root.ledger, player_id, amount, "ubi")
        metrics.record_ubi(root.metrics, second, amount, player_id, force_name)
      end
    end
  end

  runtime.economy_snapshot.gold_per_second = total_gold_per_second
  runtime.economy_snapshot.recent_raw_ore_per_minute = total_recent_raw_ore_per_minute
  runtime.economy_snapshot.breakdown_per_minute = total_breakdown_per_minute

  metrics.prune(root.metrics, second, 60)
  metrics.set_snapshot_counts(
    root.metrics,
    orders.count_active(root.orders),
    contracts.count_openish(root.contracts)
  )
end

function economy.snapshot(force_name)
  if force_name then
    return runtime_state.economy_snapshot(force_name)
  end
  return runtime_state.economy_snapshot()
end

return economy
