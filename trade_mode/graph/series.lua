local metrics = require("trade_mode.core.metrics")
local stats = require("trade_mode.graph.stats")
local util = require("trade_mode.core.util")

local series = {}

local DEFAULT_WINDOW = 60
local DEFAULT_BUCKET_COUNT = 12

local function bucketed_series(state, window_name, current_second, window_seconds, bucket_count, force_name)
  metrics.normalize(state)
  util.assert_non_negative_integer(current_second, "current_second")
  util.assert_positive_integer(window_seconds, "window_seconds")
  util.assert_positive_integer(bucket_count, "bucket_count")

  local bucket_map = state.windows[window_name]
  local output = {}
  for index = 1, bucket_count do
    output[index] = 0
  end

  local window_start_second = current_second - window_seconds + 1
  for second, bucket in pairs(bucket_map) do
    if second >= window_start_second and second <= current_second then
      local span = second - window_start_second
      local bucket_index = math.floor((span * bucket_count) / window_seconds) + 1
      if bucket_index > bucket_count then
        bucket_index = bucket_count
      end
      if bucket_index >= 1 and bucket_index <= bucket_count then
        if force_name then
          output[bucket_index] = output[bucket_index] + (bucket.by_force[force_name] or 0)
        else
          output[bucket_index] = output[bucket_index] + bucket.total
        end
      end
    end
  end

  return output
end

function series.trade(state, current_second, window_seconds, bucket_count, force_name)
  return bucketed_series(state, "traded", current_second, window_seconds or DEFAULT_WINDOW, bucket_count or DEFAULT_BUCKET_COUNT, force_name)
end

function series.ubi(state, current_second, window_seconds, bucket_count, force_name)
  return bucketed_series(state, "ubi", current_second, window_seconds or DEFAULT_WINDOW, bucket_count or DEFAULT_BUCKET_COUNT, force_name)
end

function series.combine(left, right)
  if type(left) ~= "table" then
    error("left must be a table", 2)
  end
  if type(right) ~= "table" then
    error("right must be a table", 2)
  end
  local count = math.max(#left, #right)
  local combined = {}
  for index = 1, count do
    combined[index] = (left[index] or 0) + (right[index] or 0)
  end
  return combined
end

function series.summary(values)
  if type(values) ~= "table" then
    error("values must be a table", 2)
  end
  if #values == 0 then
    return {
      total = 0,
      average = 0,
      peak = 0,
      minimum = 0,
      median = 0,
      stddev = 0,
      latest = 0,
    }
  end

  local total = stats.sum(values)
  local peak, minimum = stats.maxmin(values)
  return {
    total = total,
    average = stats.mean(values),
    peak = peak,
    minimum = minimum,
    median = stats.median(values),
    stddev = stats.stddev(values),
    latest = values[#values] or 0,
  }
end

return series
