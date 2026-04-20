local active_mods = script and script.active_mods or {}
local has_space_age = active_mods["space-age"] ~= nil

if has_space_age then
  return require("trade_mode.suggested-prices-space-age")
end

return require("trade_mode.suggested-prices-vanilla")
