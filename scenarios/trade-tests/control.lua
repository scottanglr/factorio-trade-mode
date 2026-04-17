local constants = require("__factorio-trade-mode__.trade_mode.runtime.constants")
local pure_suite = require("__factorio-trade-mode__.tests.pure_suite")
local util = require("__factorio-trade-mode__.trade_mode.core.util")
local ubi = require("__factorio-trade-mode__.trade_mode.core.ubi")
local report_log_prefix = "TRADE_MODE_TEST_REPORT "
local synthetic_seller_id = 1

local function add_result(name, ok, pass_condition, setup_steps, details)
  storage.test_state.results[#storage.test_state.results + 1] = {
    name = name,
    ok = ok,
    pass_condition = pass_condition,
    setup_steps = setup_steps,
    details = details,
  }
end

local function ensure_state()
  storage.test_state = storage.test_state or {
    started = false,
    finished = false,
    results = {},
    checkpoints = {},
  }
  return storage.test_state
end

local function surface()
  return game.surfaces["nauvis"]
end

local function remote_call(name, ...)
  return remote.call(constants.mod_name, name, ...)
end

local function snapshot()
  return remote_call("state_snapshot")
end

local function clear_area(area)
  for _, entity in pairs(surface().find_entities_filtered({area = area})) do
    if entity.valid and entity.type ~= "character" and entity.force.name ~= "enemy" and entity.force.name ~= "neutral" then
      entity.destroy({raise_destroy = true})
    end
  end
end

local function raise_built(entity)
  script.raise_script_built({entity = entity})
end

local function player_force()
  return game.forces.player
end

local function create_trade_box(position)
  local entity = surface().create_entity({
    name = "trade-box",
    position = position,
    force = player_force(),
    create_build_effect_smoke = false,
  })
  raise_built(entity)
  return entity
end

local function create_container(name, position)
  local entity = surface().create_entity({
    name = name,
    position = position,
    force = player_force(),
    create_build_effect_smoke = false,
  })
  raise_built(entity)
  return entity
end

local function create_burner_inserter(position, direction, owner_player_index)
  local entity = surface().create_entity({
    name = "burner-inserter",
    position = position,
    direction = direction,
    force = player_force(),
    create_build_effect_smoke = false,
  })
  raise_built(entity)
  entity.get_fuel_inventory().insert({name = "coal", count = 10})
  local bind_result = remote_call("test_set_inserter_owner", entity.unit_number, owner_player_index)
  return entity, bind_result
end

local function run_manual_trade_case()
  clear_area({{-5, -5}, {5, 5}})

  local before = snapshot()
  local seller_before = before.balances[tostring(synthetic_seller_id)] or 0
  remote_call("credit_player", 2, 100)

  local box = create_trade_box({0, 0})
  local box_id = util.id_key(box.unit_number)
  local created = remote_call("create_order", box.unit_number, 2, "iron-ore", 10)

  box.get_inventory(defines.inventory.chest).insert({name = "iron-ore", count = 5})
  local manual_note = remote_call("test_note_manual_insertion", box.unit_number, synthetic_seller_id, "iron-ore", 5)
  remote_call("reconcile_now")

  local after = snapshot()
  local seller_after = after.balances[tostring(synthetic_seller_id)] or 0
  local buyer_after = after.balances["2"] or 0
  local box_count = box.get_inventory(defines.inventory.chest).get_item_count("iron-ore")
  local live_order = nil
  for _, row in ipairs(after.orders) do
    if row.box_id == box_id then
      live_order = row
      break
    end
  end
  add_result(
    "Scenario A: Two-player manual box trade happy path",
    seller_after - seller_before == 50 and buyer_after == 50 and box_count == 5,
    "Seller balance delta is 50, buyer 2 balance is 50, and the trade box holds 5 iron ore.",
    {
      "Credit buyer account 2 with 100 gold.",
      "Create a trade box and buy order for iron ore at 10 gold.",
      "Insert 5 iron ore via player fast transfer event path.",
    },
    {
      seller_before = seller_before,
      seller_after = seller_after,
      buyer_after = buyer_after,
      box_count = box_count,
      created_ok = created.ok,
      manual_note_ok = manual_note.ok,
      manual_note_error = manual_note.error,
      created_box_id = created.order and created.order.box_id or "missing",
      box_id = box_id,
      tracked_trade_boxes = after.tracked_trade_boxes,
      order_found = live_order ~= nil,
      order_status = live_order and live_order.status or "missing",
      order_total_traded = live_order and live_order.total_traded or 0,
    }
  )
end

local function setup_automated_trade_case(case_name, area_origin_x, buyer_id, buyer_credit, expected_box_count)
  clear_area({{area_origin_x - 4, -4}, {area_origin_x + 4, 4}})

  local before = snapshot()
  local seller_before = before.balances[tostring(synthetic_seller_id)] or 0
  if buyer_credit > 0 then
    remote_call("credit_player", buyer_id, buyer_credit)
  end

  local source = create_container("steel-chest", {area_origin_x, 0})
  local box = create_trade_box({area_origin_x + 2, 0})
  local inserter, bind_result = create_burner_inserter({area_origin_x + 1, 0}, defines.direction.west, synthetic_seller_id)
  source.get_inventory(defines.inventory.chest).insert({name = "iron-ore", count = expected_box_count})
  local box_id = util.id_key(box.unit_number)
  local created = remote_call("create_order", box.unit_number, buyer_id, "iron-ore", 10)

  ensure_state().checkpoints[case_name] = {
    seller_before = seller_before,
    buyer_id = buyer_id,
    box = box,
    box_id = box_id,
    source = source,
    inserter = inserter,
    due_tick = game.tick + 240,
    expected_box_count = expected_box_count,
    created_ok = created.ok,
    created_box_id = created.order and created.order.box_id or "missing",
    owner_bind_ok = bind_result.ok,
    owner_bind_error = bind_result.error,
  }
end

local function check_automated_trade_case()
  local checkpoint = ensure_state().checkpoints["scenario_b"]
  if not checkpoint or game.tick < checkpoint.due_tick then
    return
  end

  local after = snapshot()
  local seller_after = after.balances[tostring(synthetic_seller_id)] or 0
  local buyer_after = after.balances[tostring(checkpoint.buyer_id)] or 0
  local box_count = checkpoint.box.get_inventory(defines.inventory.chest).get_item_count("iron-ore")
  local source_count = checkpoint.source.get_inventory(defines.inventory.chest).get_item_count("iron-ore")
  local held_count = checkpoint.inserter.held_stack.valid_for_read and checkpoint.inserter.held_stack.count or 0
  local inserter_stat = after.inserter_stats[util.id_key(checkpoint.inserter.unit_number)]
  local payout = inserter_stat and inserter_stat.lifetime_payout or 0
  local live_order = nil
  for _, row in ipairs(after.orders) do
    if row.box_id == checkpoint.box_id then
      live_order = row
      break
    end
  end

  add_result(
    "Scenario B: Inserter-owned automation trade attribution",
    seller_after - checkpoint.seller_before == 30 and buyer_after == 70 and box_count == 3 and payout == 30,
    "Seller balance delta is 30, buyer balance is 70, trade box has 3 iron ore, and inserter lifetime payout is 30.",
    {
      "Create a source chest, burner inserter, and trade box in a straight line.",
      "Credit buyer account 20 with 100 gold and create an order for 3 iron ore.",
      "Let the inserter move items for 240 ticks.",
    },
    {
      seller_before = checkpoint.seller_before,
      seller_after = seller_after,
      buyer_after = buyer_after,
      box_count = box_count,
      source_count = source_count,
      held_count = held_count,
      inserter_payout = payout,
      inserter_active = checkpoint.inserter.active,
      drop_target_name = checkpoint.inserter.drop_target and checkpoint.inserter.drop_target.valid and checkpoint.inserter.drop_target.name or "nil",
      pickup_target_name = checkpoint.inserter.pickup_target and checkpoint.inserter.pickup_target.valid and checkpoint.inserter.pickup_target.name or "nil",
      created_ok = checkpoint.created_ok,
      created_box_id = checkpoint.created_box_id,
      owner_bind_ok = checkpoint.owner_bind_ok,
      owner_bind_error = checkpoint.owner_bind_error,
      tracked_trade_boxes = after.tracked_trade_boxes,
      tracked_inserters = after.tracked_inserters,
      order_found = live_order ~= nil,
      order_status = live_order and live_order.status or "missing",
      order_total_traded = live_order and live_order.total_traded or 0,
    }
  )

  local status_report = after.reports.trade_status
  local money_report = after.reports.trade_money_last_minute
  add_result(
    "Admin command reports reflect last-minute trade metrics",
    string.find(status_report, "money_traded_last_minute: 80", 1, true) ~= nil and string.find(money_report, "value: 80", 1, true) ~= nil,
    "trade_status and trade_money_last_minute both report 80 after the manual and automated trade scenarios.",
    {
      "Run the manual and automated trade scenarios first.",
      "Read the same formatted report strings used by the slash commands.",
    },
    {
      trade_status = status_report,
      trade_money_last_minute = money_report,
    }
  )

  ensure_state().checkpoints["scenario_b"] = nil
end

local function check_insufficient_funds_case()
  local checkpoint = ensure_state().checkpoints["scenario_c"]
  if not checkpoint or game.tick < checkpoint.due_tick then
    return
  end

  local after = snapshot()
  local seller_after = after.balances[tostring(synthetic_seller_id)] or 0
  local box_count = checkpoint.box.get_inventory(defines.inventory.chest).get_item_count("iron-ore")
  local source_count = checkpoint.source.get_inventory(defines.inventory.chest).get_item_count("iron-ore")
  local held_count = checkpoint.inserter.held_stack.valid_for_read and checkpoint.inserter.held_stack.count or 0
  local inserter_stat = after.inserter_stats[util.id_key(checkpoint.inserter.unit_number)]
  local payout = inserter_stat and inserter_stat.lifetime_payout or 0
  local live_order = nil
  for _, row in ipairs(after.orders) do
    if row.box_id == checkpoint.box_id then
      live_order = row
      break
    end
  end

  add_result(
    "Scenario C: Insufficient-funds rejection with no item movement",
    box_count == 0 and (source_count + held_count) == 1 and payout == 0 and (live_order and live_order.total_traded == 0 or false),
    "Trade box count is 0, the original item remains on the source side, order total_traded stays 0, and inserter payout stays 0.",
    {
      "Create a burner-inserter feed into a trade box.",
      "Create an order for buyer account 21 with zero gold.",
      "Wait 240 ticks and verify the inserter cannot settle the delivery.",
    },
    {
      seller_before = checkpoint.seller_before,
      seller_after = seller_after,
      box_count = box_count,
      source_count = source_count,
      held_count = held_count,
      inserter_payout = payout,
      created_ok = checkpoint.created_ok,
      created_box_id = checkpoint.created_box_id,
      owner_bind_ok = checkpoint.owner_bind_ok,
      owner_bind_error = checkpoint.owner_bind_error,
      tracked_trade_boxes = after.tracked_trade_boxes,
      tracked_inserters = after.tracked_inserters,
      order_found = live_order ~= nil,
      order_status = live_order and live_order.status or "missing",
      order_total_traded = live_order and live_order.total_traded or 0,
    }
  )

  ensure_state().checkpoints["scenario_c"] = nil
end

local function run_contract_case()
  local before = snapshot()
  local seller_before = before.balances[tostring(synthetic_seller_id)] or 0
  remote_call("credit_player", 22, 60)
  local created = remote_call("create_contract", 22, "Deliver coal", "Supply one burner inserter worth of coal.", 25)
  remote_call("assign_contract", created.contract.id, synthetic_seller_id)
  remote_call("unassign_contract", created.contract.id, synthetic_seller_id)
  remote_call("assign_contract", created.contract.id, synthetic_seller_id)
  local paid = remote_call("pay_contract", created.contract.id, 22)
  local after = snapshot()
  local seller_after = after.balances[tostring(synthetic_seller_id)] or 0
  local creator_after = after.balances["22"] or 0

  add_result(
    "Scenario D: Contract assign, unassign, and payout flow",
    paid.ok and seller_after - seller_before == 25 and creator_after == 35,
    "Assignee receives 25 gold, creator account 22 drops to 35, and payout returns ok.",
    {
      "Create a contract owned by account 22 for 25 gold.",
      "Assign account 1, unassign it, assign again, and then pay it from account 22.",
    },
    {
      seller_before = seller_before,
      seller_after = seller_after,
      creator_after = creator_after,
    }
  )
end

local function run_ubi_scaling_case()
  local low_state = {}
  local high_state = {}
  ubi.record_ore_sample(low_state, 0, 0, {["iron-ore"] = 0})
  ubi.record_ore_sample(low_state, 60, 60, {["iron-ore"] = 60})
  ubi.record_ore_sample(high_state, 0, 0, {["iron-ore"] = 0})
  ubi.record_ore_sample(high_state, 60, 600, {["iron-ore"] = 600})

  local low_rate = ubi.get_recent_ore_per_minute(low_state).recent_raw_ore_per_minute
  local high_rate = ubi.get_recent_ore_per_minute(high_state).recent_raw_ore_per_minute
  local low_gold = ubi.compute_gold_per_second(constants.ubi, low_rate)
  local high_gold = ubi.compute_gold_per_second(constants.ubi, high_rate)

  add_result(
    "Scenario E: UBI scaling under low vs high ore throughput",
    high_rate > low_rate and high_gold > low_gold,
    "The pure UBI engine reports a higher gold_per_second at 600 ore/min than at 60 ore/min.",
    {
      "Feed the pure UBI module a low-throughput rolling sample window.",
      "Feed the same module a high-throughput rolling sample window.",
      "Compare the resulting ore/minute and gold_per_second values.",
    },
    {
      low_rate = low_rate,
      high_rate = high_rate,
      low_gold = low_gold,
      high_gold = high_gold,
    }
  )
end

local function write_report()
  local test_state = ensure_state()
  local pure = test_state.pure_result
  local passed = pure.passed
  local failed = pure.failed
  for _, result in ipairs(test_state.results) do
    if result.ok then
      passed = passed + 1
    else
      failed = failed + 1
    end
  end

  local report = {
    pure = pure,
    scenarios = test_state.results,
    summary = {
      passed = passed,
      failed = failed,
    },
  }

  log(report_log_prefix .. helpers.table_to_json(report))
  test_state.finished = true
end

script.on_init(function()
  ensure_state()
end)

script.on_event(defines.events.on_tick, function(event)
  local test_state = ensure_state()
  if test_state.finished then
    return
  end

  if not test_state.started and event.tick >= 10 then
    test_state.started = true
    test_state.pure_result = pure_suite.run()
    run_manual_trade_case()
    setup_automated_trade_case("scenario_b", 10, 20, 100, 3)
    setup_automated_trade_case("scenario_c", 24, 21, 0, 1)
    run_ubi_scaling_case()
  end

  check_automated_trade_case()
  check_insufficient_funds_case()

   if test_state.started and not test_state.contract_case_done and not test_state.checkpoints["scenario_b"] and not test_state.checkpoints["scenario_c"] then
    run_contract_case()
    test_state.contract_case_done = true
  end

  if test_state.started and test_state.contract_case_done and not test_state.finished and event.tick >= 520 then
    write_report()
  end
end)
