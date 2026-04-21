-- Adapted from SimpleStats (lua-users wiki, mirrored by ZeroStride gist):
-- http://lua-users.org/wiki/SimpleStats
-- https://gist.github.com/ZeroStride/3485c35e2583e5aca3978d54f2004399
local stats = {}

local function assert_table(values)
  if type(values) ~= "table" then
    error("values must be a table", 3)
  end
end

local function copy_numeric(values)
  local numeric = {}
  for _, value in ipairs(values) do
    if type(value) == "number" then
      numeric[#numeric + 1] = value
    end
  end
  return numeric
end

function stats.sum(values)
  assert_table(values)
  local total = 0
  for _, value in ipairs(values) do
    if type(value) == "number" then
      total = total + value
    end
  end
  return total
end

function stats.mean(values)
  assert_table(values)
  local numeric = copy_numeric(values)
  if #numeric == 0 then
    return 0
  end
  return stats.sum(numeric) / #numeric
end

function stats.maxmin(values)
  assert_table(values)
  local max_value = -math.huge
  local min_value = math.huge
  local count = 0
  for _, value in ipairs(values) do
    if type(value) == "number" then
      count = count + 1
      max_value = math.max(max_value, value)
      min_value = math.min(min_value, value)
    end
  end
  if count == 0 then
    return 0, 0
  end
  return max_value, min_value
end

function stats.median(values)
  assert_table(values)
  local numeric = copy_numeric(values)
  if #numeric == 0 then
    return 0
  end
  table.sort(numeric)
  if #numeric % 2 == 0 then
    return (numeric[#numeric / 2] + numeric[(#numeric / 2) + 1]) / 2
  end
  return numeric[math.ceil(#numeric / 2)]
end

function stats.stddev(values)
  assert_table(values)
  local numeric = copy_numeric(values)
  if #numeric <= 1 then
    return 0
  end
  local mean = stats.mean(numeric)
  local squared_error_sum = 0
  for _, value in ipairs(numeric) do
    local delta = value - mean
    squared_error_sum = squared_error_sum + (delta * delta)
  end
  return math.sqrt(squared_error_sum / (#numeric - 1))
end

return stats
