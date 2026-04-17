local format = {}

function format.position(entity)
  local x = math.floor(entity.position.x)
  local y = math.floor(entity.position.y)
  return string.format("%s (%d, %d)", entity.surface.name, x, y)
end

function format.tick_age(current_tick, source_tick)
  if not source_tick then
    return "Never"
  end

  local delta_seconds = math.floor((current_tick - source_tick) / 60)
  return delta_seconds .. "s ago"
end

function format.localised_tick_age(current_tick, source_tick)
  if not source_tick then
    return {"trade-mode.never"}
  end

  local delta_seconds = math.floor((current_tick - source_tick) / 60)
  return {"trade-mode.seconds-ago", delta_seconds}
end

function format.money(amount)
  return tostring(amount) .. " gold"
end

function format.localised_money(amount)
  return {"trade-mode.money", amount}
end

function format.multiline(lines)
  return table.concat(lines, "\n")
end

return format
