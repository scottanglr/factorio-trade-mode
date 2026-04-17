local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local format = require("trade_mode.runtime.format")
local inserter_stats = require("trade_mode.core.inserter_stats")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local runtime_state = require("trade_mode.runtime.state")

local commands_runtime = {}

local function emit(command, text)
  if command.player_index then
    local player = game.players[command.player_index]
    if player and player.valid then
      player.print(text)
      return
    end
  end

  log(text)
end

local function require_admin(command)
  if not command.player_index then
    return true
  end

  local player = game.players[command.player_index]
  if player and player.valid and player.admin then
    return true
  end

  emit(command, "Trade Mode: admin privileges required.")
  return false
end

local function root()
  return runtime_state.root()
end

local function current_second()
  return runtime_state.current_second(game.tick)
end

local function lines_for_top_rows(label, rows)
  local lines = {label}
  if #rows == 0 then
    lines[#lines + 1] = "none"
    return lines
  end

  for index = 1, math.min(#rows, 3) do
    lines[#lines + 1] = string.format(
      "%d. %s = %d",
      index,
      runtime_state.player_name(rows[index].player_id),
      rows[index].amount
    )
  end
  return lines
end

function commands_runtime.register()
  commands.add_command("trade_status", "Show current trade economy status.", commands_runtime.trade_status)
  commands.add_command("trade_money_last_minute", "Show money traded in the last minute.", commands_runtime.trade_money_last_minute)
  commands.add_command("trade_ubi_last_minute", "Show UBI credited in the last minute.", commands_runtime.trade_ubi_last_minute)
  commands.add_command("trade_orders", "Show active trade orders.", commands_runtime.trade_orders)
  commands.add_command("trade_contracts", "Show current trade contracts.", commands_runtime.trade_contracts)
end

function commands_runtime.render_trade_status()
  local state = root()
  local snapshot = state.runtime.economy_snapshot
  local second = current_second()
  local lines = {
    string.format("Trade status"),
    string.format("window: last 60 seconds (bucketed by second)"),
    string.format("gold_per_second: %.2f", snapshot.gold_per_second),
    string.format("recent_raw_ore_per_minute: %.2f", snapshot.recent_raw_ore_per_minute),
    string.format("money_traded_last_minute: %d", metrics.trade_last_minute(state.metrics, second)),
    string.format("ubi_last_minute: %d", metrics.ubi_last_minute(state.metrics, second)),
    string.format("active_orders: %d", orders.count_active(state.orders)),
    string.format("active_contracts: %d", contracts.count_openish(state.contracts)),
  }

  local top_payers = metrics.top_payers(state.metrics, second, 3)
  local top_recipients = metrics.top_recipients(state.metrics, second, 3)
  local top_inserters = inserter_stats.top(state.inserter_stats, 3)

  for _, line in ipairs(lines_for_top_rows("top_payers:", top_payers)) do
    lines[#lines + 1] = line
  end
  for _, line in ipairs(lines_for_top_rows("top_recipients:", top_recipients)) do
    lines[#lines + 1] = line
  end

  lines[#lines + 1] = "top_inserter_payouts:"
  if #top_inserters == 0 then
    lines[#lines + 1] = "none"
  else
    for index = 1, #top_inserters do
      lines[#lines + 1] = string.format(
        "%d. inserter %s owner=%s payout=%d",
        index,
        top_inserters[index].inserter_id,
        top_inserters[index].owner_id and runtime_state.player_name(top_inserters[index].owner_id) or "Unknown",
        top_inserters[index].lifetime_payout
      )
    end
  end

  return format.multiline(lines)
end

function commands_runtime.trade_status(command)
  if not require_admin(command) then
    return
  end

  emit(command, commands_runtime.render_trade_status())
end

function commands_runtime.render_trade_money_last_minute()
  local second = current_second()
  return format.multiline({
    "Trade money last minute",
    "window: last 60 seconds (bucketed by second)",
    string.format("value: %d", metrics.trade_last_minute(root().metrics, second)),
  })
end

function commands_runtime.trade_money_last_minute(command)
  if not require_admin(command) then
    return
  end

  emit(command, commands_runtime.render_trade_money_last_minute())
end

function commands_runtime.render_trade_ubi_last_minute()
  local second = current_second()
  return format.multiline({
    "Trade UBI last minute",
    "window: last 60 seconds (bucketed by second)",
    string.format("value: %d", metrics.ubi_last_minute(root().metrics, second)),
  })
end

function commands_runtime.trade_ubi_last_minute(command)
  if not require_admin(command) then
    return
  end

  emit(command, commands_runtime.render_trade_ubi_last_minute())
end

function commands_runtime.render_trade_orders()
  local state = root()
  local lines = {
    "Trade orders",
    "window: current snapshot",
  }
  local current_orders = orders.list_current(state.orders)
  if #current_orders == 0 then
    lines[#lines + 1] = "none"
  else
    for _, order in ipairs(current_orders) do
      lines[#lines + 1] = string.format(
        "#%d %s price=%d buyer=%s box=%s status=%s",
        order.id,
        order.item_name,
        order.unit_price,
        runtime_state.player_name(order.buyer_id),
        order.box_id,
        order.status
      )
    end
  end

  return format.multiline(lines)
end

function commands_runtime.trade_orders(command)
  if not require_admin(command) then
    return
  end

  emit(command, commands_runtime.render_trade_orders())
end

function commands_runtime.render_trade_contracts()
  local state = root()
  local lines = {
    "Trade contracts",
    "window: current snapshot",
  }
  local current_contracts = contracts.list_all(state.contracts)
  if #current_contracts == 0 then
    lines[#lines + 1] = "none"
  else
    for _, contract in ipairs(current_contracts) do
      lines[#lines + 1] = string.format(
        "#%d %s payout=%d creator=%s assignee=%s status=%s",
        contract.id,
        contract.title,
        contract.amount,
        runtime_state.player_name(contract.creator_id),
        contract.assignee_id and runtime_state.player_name(contract.assignee_id) or "Unassigned",
        contract.status
      )
    end
  end

  return format.multiline(lines)
end

function commands_runtime.trade_contracts(command)
  if not require_admin(command) then
    return
  end

  emit(command, commands_runtime.render_trade_contracts())
end

return commands_runtime
