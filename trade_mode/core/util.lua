local util = {}

local function shallow_copy(input)
  local copy = {}
  for key, value in pairs(input) do
    copy[key] = value
  end
  return copy
end

function util.shallow_copy(input)
  return shallow_copy(input or {})
end

function util.is_integer(value)
  return type(value) == "number" and value == math.floor(value)
end

function util.is_non_negative_integer(value)
  return util.is_integer(value) and value >= 0
end

function util.is_positive_integer(value)
  return util.is_integer(value) and value > 0
end

function util.assert_positive_integer(value, field_name)
  if not util.is_positive_integer(value) then
    error(field_name .. " must be a positive integer")
  end
end

function util.assert_non_negative_integer(value, field_name)
  if not util.is_non_negative_integer(value) then
    error(field_name .. " must be a non-negative integer")
  end
end

function util.assert_non_empty_string(value, field_name)
  if type(value) ~= "string" or value == "" then
    error(field_name .. " must be a non-empty string")
  end
end

function util.push_limited(list, value, limit)
  list[#list + 1] = value
  while #list > limit do
    table.remove(list, 1)
  end
end

function util.round_half_up(value)
  if value >= 0 then
    return math.floor(value + 0.5)
  end

  return math.ceil(value - 0.5)
end

function util.sorted_array(values, comparator)
  local copy = {}
  for index = 1, #values do
    copy[index] = values[index]
  end
  table.sort(copy, comparator)
  return copy
end

function util.id_key(value)
  if type(value) == "string" then
    return value
  end

  if type(value) == "number" then
    return string.format("%.0f", value)
  end

  if type(value) == "userdata" then
    local ok, unit_number = pcall(function()
      return value.unit_number
    end)
    if ok and unit_number ~= nil then
      return util.id_key(unit_number)
    end
    return tostring(value)
  end

  error("unsupported identifier type")
end

return util
