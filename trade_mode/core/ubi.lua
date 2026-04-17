local util = require("trade_mode.core.util")

local ubi = {}

local ORE_NAMES = {
  "iron-ore",
  "copper-ore",
  "coal",
  "stone",
  "uranium-ore",
}

local function ensure_state(state)
  state.fractional_bank = state.fractional_bank or 0
  state.rotation_index = state.rotation_index or 1
  state.samples = state.samples or {}
  return state
end

local function copy_breakdown(values)
  local copy = {}
  for _, name in ipairs(ORE_NAMES) do
    copy[name] = values[name] or 0
  end
  return copy
end

local function find_oldest_sample(samples)
  local oldest = samples[1]
  for index = 2, #samples do
    if samples[index].second < oldest.second then
      oldest = samples[index]
    end
  end
  return oldest
end

local function find_newest_sample(samples)
  local newest = samples[1]
  for index = 2, #samples do
    if samples[index].second > newest.second then
      newest = samples[index]
    end
  end
  return newest
end

function ubi.record_ore_sample(state, second, total_raw_ore_count, breakdown)
  ensure_state(state)
  util.assert_non_negative_integer(second, "second")
  util.assert_non_negative_integer(total_raw_ore_count, "total_raw_ore_count")

  local normalized_breakdown = copy_breakdown(breakdown or {})
  local replaced = false
  for index = 1, #state.samples do
    if state.samples[index].second == second then
      state.samples[index] = {
        second = second,
        total = total_raw_ore_count,
        breakdown = normalized_breakdown,
      }
      replaced = true
      break
    end
  end

  if not replaced then
    state.samples[#state.samples + 1] = {
      second = second,
      total = total_raw_ore_count,
      breakdown = normalized_breakdown,
    }
  end

  local keep_after = second - 60
  local filtered = {}
  for index = 1, #state.samples do
    if state.samples[index].second >= keep_after then
      filtered[#filtered + 1] = state.samples[index]
    end
  end
  state.samples = filtered
end

function ubi.get_recent_ore_per_minute(state)
  ensure_state(state)
  if #state.samples < 2 then
    return {
      recent_raw_ore_per_minute = 0,
      breakdown_per_minute = copy_breakdown({}),
    }
  end

  local oldest = find_oldest_sample(state.samples)
  local newest = find_newest_sample(state.samples)
  local delta_seconds = newest.second - oldest.second
  if delta_seconds <= 0 then
    return {
      recent_raw_ore_per_minute = 0,
      breakdown_per_minute = copy_breakdown({}),
    }
  end

  local breakdown = {}
  local total_delta = newest.total - oldest.total
  for _, ore_name in ipairs(ORE_NAMES) do
    local ore_delta = (newest.breakdown[ore_name] or 0) - (oldest.breakdown[ore_name] or 0)
    breakdown[ore_name] = util.round_half_up((ore_delta / delta_seconds) * 60)
  end

  return {
    recent_raw_ore_per_minute = (total_delta / delta_seconds) * 60,
    breakdown_per_minute = breakdown,
  }
end

function ubi.compute_gold_per_second(config, recent_raw_ore_per_minute)
  local base_income = config.base_income or 0
  local income_scale = config.income_scale or 0
  local income_exponent = config.income_exponent or 1
  return base_income + income_scale * (recent_raw_ore_per_minute ^ income_exponent)
end

function ubi.split_evenly(state, total_amount, player_ids)
  ensure_state(state)
  if total_amount <= 0 or #player_ids == 0 then
    return {}
  end

  local recipients = util.sorted_array(player_ids, function(left, right)
    return left < right
  end)

  local base_share = math.floor(total_amount / #recipients)
  local remainder = total_amount % #recipients
  local payouts = {}

  for index = 1, #recipients do
    payouts[recipients[index]] = base_share
  end

  if remainder > 0 then
    local start_index = ((state.rotation_index - 1) % #recipients) + 1
    for offset = 0, remainder - 1 do
      local index = ((start_index + offset - 1) % #recipients) + 1
      local player_id = recipients[index]
      payouts[player_id] = payouts[player_id] + 1
    end
    state.rotation_index = ((start_index + remainder - 1) % #recipients) + 1
  end

  return payouts
end

function ubi.plan_distribution(state, config, recent_raw_ore_per_minute, player_ids)
  ensure_state(state)
  local raw_gold_per_second = ubi.compute_gold_per_second(config, recent_raw_ore_per_minute)
  state.fractional_bank = state.fractional_bank + raw_gold_per_second
  local creditable_amount = math.floor(state.fractional_bank)
  state.fractional_bank = state.fractional_bank - creditable_amount

  return {
    raw_gold_per_second = raw_gold_per_second,
    creditable_amount = creditable_amount,
    payouts = ubi.split_evenly(state, creditable_amount, player_ids),
  }
end

function ubi.normalize(state)
  ensure_state(state)
  return state
end

return ubi
