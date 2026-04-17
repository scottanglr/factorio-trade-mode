local constants = require("trade_mode.runtime.constants")
local contracts = require("trade_mode.core.contracts")
local economy = require("trade_mode.runtime.economy")
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

  log(type(text) == "string" and text or serpent.line(text))
end

local function localised(key, ...)
  local message = {"trade-mode." .. key}
  local args = {...}
  for index = 1, #args do
    message[#message + 1] = args[index]
  end
  return message
end

local function require_admin(command)
  if not command.player_index then
    return true
  end

  local player = game.players[command.player_index]
  if player and player.valid and player.admin then
    return true
  end

  emit(command, localised("admin-required"))
  return false
end

local function root()
  return runtime_state.root()
end

local function current_second()
  return runtime_state.current_second(game.tick)
end

local function command_force_name(command)
  if not command.player_index then
    return nil
  end

  local player = game.players[command.player_index]
  if player and player.valid then
    return player.force.name
  end

  return nil
end

local function force_orders(force_name)
  local visible = {}
  for _, order in ipairs(orders.list_current(root().orders)) do
    if not force_name or runtime_state.order_force_name(order) == force_name then
      visible[#visible + 1] = order
    end
  end
  return visible
end

local function force_contracts(force_name)
  local visible = {}
  for _, contract in ipairs(contracts.list_all(root().contracts)) do
    if not force_name or runtime_state.contract_force_name(contract) == force_name then
      visible[#visible + 1] = contract
    end
  end
  return visible
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
  commands.add_command("trade_status", localised("command-help-trade-status"), commands_runtime.trade_status)
  commands.add_command("trade_money_last_minute", localised("command-help-trade-money-last-minute"), commands_runtime.trade_money_last_minute)
  commands.add_command("trade_ubi_last_minute", localised("command-help-trade-ubi-last-minute"), commands_runtime.trade_ubi_last_minute)
  commands.add_command("trade_orders", localised("command-help-trade-orders"), commands_runtime.trade_orders)
  commands.add_command("trade_contracts", localised("command-help-trade-contracts"), commands_runtime.trade_contracts)
end

function commands_runtime.render_trade_status(force_name)
  local state = root()
  local snapshot = economy.snapshot(force_name)
  local second = current_second()
  local lines = {
    "Trade status",
  }

  if force_name then
    lines[#lines + 1] = string.format("force: %s", force_name)
  end

  lines[#lines + 1] = "window: last 60 seconds (bucketed by second)"
  lines[#lines + 1] = string.format("gold_per_second: %.2f", snapshot.gold_per_second)
  lines[#lines + 1] = string.format("recent_raw_ore_per_minute: %.2f", snapshot.recent_raw_ore_per_minute)
  lines[#lines + 1] = string.format("money_traded_last_minute: %d", metrics.trade_last_minute(state.metrics, second, force_name))
  lines[#lines + 1] = string.format("ubi_last_minute: %d", metrics.ubi_last_minute(state.metrics, second, force_name))
  lines[#lines + 1] = string.format("active_orders: %d", #force_orders(force_name))
  lines[#lines + 1] = string.format("active_contracts: %d", contracts.count_openish(state.contracts, force_name))

  local top_payers = metrics.top_payers(state.metrics, second, 3, function(row)
    return runtime_state.player_in_force(row.player_id, force_name)
  end)
  local top_recipients = metrics.top_recipients(state.metrics, second, 3, function(row)
    return runtime_state.player_in_force(row.player_id, force_name)
  end)
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
    local added_any = false
    local rank = 1
    for _, entry in ipairs(top_inserters) do
      if not force_name or runtime_state.player_in_force(entry.owner_id or 0, force_name) then
        added_any = true
        lines[#lines + 1] = string.format(
          "%d. inserter %s owner=%s payout=%d",
          rank,
          entry.inserter_id,
          entry.owner_id and runtime_state.player_name(entry.owner_id) or "Unknown",
          entry.lifetime_payout
        )
        rank = rank + 1
      end
    end
    if not added_any then
      lines[#lines + 1] = "none"
    end
  end

  return format.multiline(lines)
end

function commands_runtime.trade_status(command)
  if not require_admin(command) then
    return
  end

  emit(command, commands_runtime.render_trade_status(command_force_name(command)))
end

function commands_runtime.render_trade_money_last_minute(force_name)
  local second = current_second()
  local lines = {
    "Trade money last minute",
  }
  if force_name then
    lines[#lines + 1] = string.format("force: %s", force_name)
  end
  lines[#lines + 1] = "window: last 60 seconds (bucketed by second)"
  lines[#lines + 1] = string.format("value: %d", metrics.trade_last_minute(root().metrics, second, force_name))
  return format.multiline(lines)
end

function commands_runtime.trade_money_last_minute(command)
  if not require_admin(command) then
    return
  end

  emit(command, commands_runtime.render_trade_money_last_minute(command_force_name(command)))
end

function commands_runtime.render_trade_ubi_last_minute(force_name)
  local second = current_second()
  local lines = {
    "Trade UBI last minute",
  }
  if force_name then
    lines[#lines + 1] = string.format("force: %s", force_name)
  end
  lines[#lines + 1] = "window: last 60 seconds (bucketed by second)"
  lines[#lines + 1] = string.format("value: %d", metrics.ubi_last_minute(root().metrics, second, force_name))
  return format.multiline(lines)
end

function commands_runtime.trade_ubi_last_minute(command)
  if not require_admin(command) then
    return
  end

  emit(command, commands_runtime.render_trade_ubi_last_minute(command_force_name(command)))
end

function commands_runtime.render_trade_orders(force_name)
  local lines = {
    "Trade orders",
  }
  if force_name then
    lines[#lines + 1] = string.format("force: %s", force_name)
  end
  lines[#lines + 1] = "window: current snapshot"

  local current_orders = force_orders(force_name)
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

  emit(command, commands_runtime.render_trade_orders(command_force_name(command)))
end

function commands_runtime.render_trade_contracts(force_name)
  local lines = {
    "Trade contracts",
  }
  if force_name then
    lines[#lines + 1] = string.format("force: %s", force_name)
  end
  lines[#lines + 1] = "window: current snapshot"

  local current_contracts = force_contracts(force_name)
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

  emit(command, commands_runtime.render_trade_contracts(command_force_name(command)))
end

return commands_runtime
