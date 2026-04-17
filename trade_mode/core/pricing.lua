local util = require("trade_mode.core.util")

local pricing = {}

function pricing.normalize(config)
  return config or {}
end

function pricing.get_suggested_price(config, item_name)
  util.assert_non_empty_string(item_name, "item_name")
  config = pricing.normalize(config)

  local value = config[item_name]
  if value == nil then
    return nil, "unknown_item"
  end

  util.assert_positive_integer(value, "suggested_price")
  return value
end

function pricing.validate_unit_price(unit_price)
  util.assert_positive_integer(unit_price, "unit_price")
  return true
end

return pricing
