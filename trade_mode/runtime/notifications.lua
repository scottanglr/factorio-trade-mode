local format = require("trade_mode.runtime.format")
local runtime_state = require("trade_mode.runtime.state")

local notifications = {}

local function localised(key, ...)
  local message = {"trade-mode." .. key}
  local args = {...}
  for index = 1, #args do
    message[#message + 1] = args[index]
  end
  return message
end

local function connected_player(player_index)
  if not game then
    return nil
  end
  local player = game.get_player(player_index)
  if player and player.valid and player.connected then
    return player
  end
  return nil
end

function notifications.notify_player(player_index, localised_message)
  local player = connected_player(player_index)
  if not player then
    return false
  end
  player.print(localised_message)
  return true
end

function notifications.notify_trade_box_first_fill(order, supplier_player_index, quantity, box_record)
  if not order or not order.buyer_id or quantity <= 0 then
    return false
  end

  local supplier_name = runtime_state.player_name(supplier_player_index)
  local location = box_record and box_record.entity and box_record.entity.valid and format.position(box_record.entity) or ("[" .. tostring(order.box_id) .. "]")
  return notifications.notify_player(
    order.buyer_id,
    localised(
      "notification-trade-box-first-fill",
      supplier_name,
      quantity,
      order.item_name,
      location
    )
  )
end

function notifications.notify_contract_assigned(contract, assignee_player_index)
  if not contract or not contract.creator_id then
    return false
  end

  return notifications.notify_player(
    contract.creator_id,
    localised(
      "notification-contract-assigned",
      runtime_state.player_name(assignee_player_index),
      contract.title
    )
  )
end

return notifications
