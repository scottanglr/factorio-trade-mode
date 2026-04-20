local constants = require("trade_mode.runtime.constants")
local format = require("trade_mode.runtime.format")
local ledger = require("trade_mode.core.ledger")
local orders = require("trade_mode.core.orders")
local pricing = require("trade_mode.core.pricing")
local runtime_state = require("trade_mode.runtime.state")
local util = require("trade_mode.core.util")

local entities = {}

local function is_trade_box(entity)
  return entity and entity.valid and entity.name == constants.entity_name
end

local function is_inserter(entity)
  return entity and entity.valid and entity.type == "inserter"
end

local function box_key(entity_or_id)
  if type(entity_or_id) == "table" then
    return util.id_key(entity_or_id.unit_number)
  end
  return util.id_key(entity_or_id)
end

local function inserter_key(entity_or_id)
  if type(entity_or_id) == "table" then
    return util.id_key(entity_or_id.unit_number)
  end
  return util.id_key(entity_or_id)
end

local function ensure_box_record(entity)
  local runtime = runtime_state.runtime()
  local key = box_key(entity)
  local record = runtime.trade_boxes[key]
  if record == nil then
    record = {
      box_id = key,
      entity = entity,
      tracked_item_count = 0,
      last_known_item_name = nil,
    }
    runtime.trade_boxes[key] = record
  end

  record.entity = entity
  return record
end

local function ensure_inserter_record(entity)
  local runtime = runtime_state.runtime()
  local key = inserter_key(entity)
  local record = runtime.inserters[key]
  if record == nil then
    record = {
      inserter_id = key,
      entity = entity,
      owner_player_index = nil,
      pending_box_id = nil,
      pending_item_name = nil,
      pending_count = 0,
      pending_unit_price = nil,
      last_seen_tick = 0,
      min_unit_price = nil,
    }
    runtime.inserters[key] = record
  end

  record.pending_count = record.pending_count or 0
  record.last_seen_tick = record.last_seen_tick or 0
  if record.min_unit_price ~= nil and not util.is_positive_integer(record.min_unit_price) then
    record.min_unit_price = nil
  end
  if record.pending_unit_price ~= nil and not util.is_positive_integer(record.pending_unit_price) then
    record.pending_unit_price = nil
  end

  record.entity = entity
  if entity.last_user and entity.last_user.valid then
    record.owner_player_index = entity.last_user.index
  end
  return record
end

local function lookup_inserter_record(entity_or_id)
  local runtime = runtime_state.runtime()
  if type(entity_or_id) == "table" then
    if entity_or_id.inserter_id ~= nil then
      local key = util.id_key(entity_or_id.inserter_id)
      return runtime.inserters[key] or entity_or_id
    end
    if not entity_or_id.valid or not entity_or_id.unit_number then
      return nil
    end
    return ensure_inserter_record(entity_or_id)
  end

  return runtime.inserters[inserter_key(entity_or_id)]
end

local function box_inventory(entity)
  return entity.get_inventory(defines.inventory.chest)
end

local function position_in_area(position, area)
  if not area then
    return true
  end

  local left_top = area.left_top or area[1]
  local right_bottom = area.right_bottom or area[2]
  if not left_top or not right_bottom then
    return true
  end

  local left_x = left_top.x or left_top[1]
  local left_y = left_top.y or left_top[2]
  local right_x = right_bottom.x or right_bottom[1]
  local right_y = right_bottom.y or right_bottom[2]
  if left_x == nil or left_y == nil or right_x == nil or right_y == nil then
    return true
  end

  local min_x = math.min(left_x, right_x)
  local max_x = math.max(left_x, right_x)
  local min_y = math.min(left_y, right_y)
  local max_y = math.max(left_y, right_y)
  return position.x >= min_x and position.x <= max_x and position.y >= min_y and position.y <= max_y
end

local function destroy_tags_for_box(box_id)
  local runtime = runtime_state.runtime()
  local tags = runtime.market_tags[box_id]
  if tags == nil then
    return
  end

  for _, tag in pairs(tags) do
    if tag.valid then
      tag.destroy()
    end
  end
  runtime.market_tags[box_id] = nil
end

local function should_show_tags()
  return settings.global[constants.setting_enable_chart_tags].value
end

function entities.refresh_tags_for_box(box_id)
  local root = runtime_state.root()
  local record = root.runtime.trade_boxes[box_id]
  local order = orders.get_by_box_id(root.orders, box_id)
  if not record or not record.entity.valid or not order or order.status ~= "active" or not should_show_tags() then
    destroy_tags_for_box(box_id)
    return
  end

  destroy_tags_for_box(box_id)
  local tags = {}
  local buyer_player = game.get_player(order.buyer_id)
  local force = record.entity.force
  local tag_spec = {
    position = record.entity.position,
    icon = {type = "item", name = order.item_name},
    text = tostring(order.unit_price),
  }
  if buyer_player and buyer_player.valid then
    tag_spec.last_user = buyer_player
  end
  tags[force.name] = force.add_chart_tag(record.entity.surface, tag_spec)
  root.runtime.market_tags[box_id] = tags
end

function entities.refresh_all_tags()
  for box_id in pairs(runtime_state.runtime().trade_boxes) do
    entities.refresh_tags_for_box(box_id)
  end
end

function entities.refresh_tags_in_area(surface_index, force_name, area)
  for box_id, record in pairs(runtime_state.runtime().trade_boxes) do
    local entity = record.entity
    if
      entity and
      entity.valid and
      entity.surface.index == surface_index and
      entity.force.name == force_name and
      position_in_area(entity.position, area)
    then
      entities.refresh_tags_for_box(box_id)
    end
  end
end

function entities.register_trade_box(entity)
  if not is_trade_box(entity) or not entity.unit_number then
    return nil
  end

  local record = ensure_box_record(entity)
  entities.sync_box_filters(record.box_id)
  local order = orders.get_by_box_id(runtime_state.root().orders, record.box_id)
  if order then
    record.last_known_item_name = order.item_name
    record.tracked_item_count = box_inventory(entity).get_item_count(order.item_name)
  else
    record.last_known_item_name = nil
    record.tracked_item_count = 0
  end
  entities.refresh_tags_for_box(record.box_id)
  return record
end

function entities.unregister_trade_box(entity_or_id)
  local key = box_key(entity_or_id)
  local order = orders.get_by_box_id(runtime_state.root().orders, key)
  if order and order.status ~= "cancelled" then
    orders.cancel_order(runtime_state.root().orders, order.id, game.tick)
  end
  destroy_tags_for_box(key)
  runtime_state.runtime().trade_boxes[key] = nil
end

function entities.register_inserter(entity)
  if not is_inserter(entity) or not entity.unit_number then
    return nil
  end
  return ensure_inserter_record(entity)
end

function entities.clear_inserter_pending(record_or_entity)
  local record = lookup_inserter_record(record_or_entity)
  if not record then
    return
  end
  record.pending_box_id = nil
  record.pending_item_name = nil
  record.pending_count = 0
  record.pending_unit_price = nil
  record.last_seen_tick = 0
end

function entities.inserter_min_unit_price(record_or_entity)
  local record = lookup_inserter_record(record_or_entity)
  if not record then
    return nil
  end
  return record.min_unit_price
end

function entities.set_inserter_min_price(record_or_entity, min_unit_price)
  local record = lookup_inserter_record(record_or_entity)
  if not record then
    return {
      ok = false,
      error = "inserter_not_found",
    }
  end

  if min_unit_price ~= nil then
    pricing.validate_unit_price(min_unit_price)
  end
  record.min_unit_price = min_unit_price
  return {
    ok = true,
    record = record,
  }
end

function entities.find_nearby_inserter_records(box_record)
  local entity = box_record.entity
  if not entity.valid then
    return {}
  end

  local results = {}
  local area = {
    {entity.position.x - 2, entity.position.y - 2},
    {entity.position.x + 2, entity.position.y + 2},
  }
  local found = entity.surface.find_entities_filtered({area = area, type = "inserter"})
  for _, inserter in ipairs(found) do
    local targets_box = inserter.drop_target == entity
    local drop_position = inserter.drop_position
    if not targets_box then
      targets_box =
        math.abs(drop_position.x - entity.position.x) <= 0.6 and
        math.abs(drop_position.y - entity.position.y) <= 0.6
    end

    if targets_box then
      results[#results + 1] = ensure_inserter_record(inserter)
    end
  end

  table.sort(results, function(left, right)
    return left.inserter_id < right.inserter_id
  end)
  return results
end

function entities.capture_inserter_candidates(box_record, order, tick)
  local candidates = entities.find_nearby_inserter_records(box_record)
  for _, inserter_record in ipairs(candidates) do
    local inserter = inserter_record.entity
    if inserter.valid and inserter.held_stack.valid_for_read and inserter.held_stack.name == order.item_name then
      local held_count = inserter.held_stack.count
      local should_lock_price =
        inserter_record.pending_box_id ~= box_record.box_id or
        inserter_record.pending_item_name ~= order.item_name or
        inserter_record.pending_count ~= held_count or
        inserter_record.pending_unit_price == nil

      inserter_record.pending_box_id = box_record.box_id
      inserter_record.pending_item_name = order.item_name
      inserter_record.pending_count = held_count
      if should_lock_price then
        inserter_record.pending_unit_price = order.unit_price
      end
      inserter_record.last_seen_tick = tick
    end
  end
  return candidates
end

function entities.find_pending_inserter_owner(box_record, order, tick)
  local candidates = entities.find_nearby_inserter_records(box_record)
  local chosen = nil
  for _, record in ipairs(candidates) do
    if
      record.pending_box_id == box_record.box_id and
      record.pending_item_name == order.item_name and
      record.last_seen_tick >= (tick - 2)
    then
      if chosen == nil or record.last_seen_tick > chosen.last_seen_tick then
        chosen = record
      end
    end
  end
  return chosen
end

function entities.set_inserter_budget(box_record, order)
  local buyer_wallet_id = runtime_state.order_wallet_id(order) or order.buyer_id
  local buyer_balance = ledger.get_balance(runtime_state.root().ledger, buyer_wallet_id)
  local nearby = entities.find_nearby_inserter_records(box_record)
  local affordable_units = math.floor(buyer_balance / order.unit_price)

  for _, inserter_record in ipairs(nearby) do
    local inserter = inserter_record.entity
    if inserter.valid then
      local held_matching_order_item =
        inserter.held_stack.valid_for_read and
        inserter.held_stack.name == order.item_name
      local min_unit_price = inserter_record.min_unit_price
      local has_locked_in_flight_price =
        min_unit_price ~= nil and
        held_matching_order_item and
        inserter_record.pending_box_id == box_record.box_id and
        inserter_record.pending_item_name == order.item_name and
        util.is_positive_integer(inserter_record.pending_unit_price) and
        inserter_record.pending_unit_price >= min_unit_price
      local has_valid_floor =
        min_unit_price ~= nil and
        (order.unit_price >= min_unit_price or has_locked_in_flight_price)
      if not has_valid_floor then
        inserter.disabled_by_script = true
        inserter.inserter_stack_size_override = 0
      elseif affordable_units <= 0 then
        inserter.disabled_by_script = true
        inserter.inserter_stack_size_override = 0
      else
        inserter.disabled_by_script = false
        -- Keep automated deliveries single-unit to avoid in-flight stack overshoot.
        inserter.inserter_stack_size_override = 1
      end
    end
  end
end

function entities.release_inserter_budget(box_record)
  for _, inserter_record in ipairs(entities.find_nearby_inserter_records(box_record)) do
    local inserter = inserter_record.entity
    if inserter.valid then
      inserter.disabled_by_script = false
      inserter.inserter_stack_size_override = 0
    end
  end
end

function entities.sync_box_filters(box_id)
  local root = runtime_state.root()
  local box_record = root.runtime.trade_boxes[box_id]
  if not box_record or not box_record.entity.valid then
    return
  end

  local inventory = box_inventory(box_record.entity)
  if not inventory.supports_filters() then
    return
  end

  local order = orders.get_by_box_id(root.orders, box_id)
  local item_name = order and order.item_name or nil
  for slot = 1, #inventory do
    if item_name == nil or inventory.can_set_filter(slot, item_name) then
      inventory.set_filter(slot, item_name)
    end
  end
end

function entities.describe_box(box_id)
  local record = runtime_state.runtime().trade_boxes[box_id]
  if not record or not record.entity.valid then
    return "Missing box"
  end
  return format.position(record.entity)
end

function entities.box_inventory(entity)
  return box_inventory(entity)
end

return entities
