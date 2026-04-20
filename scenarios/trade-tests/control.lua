local constants = require("__factorio-trade-mode__.trade_mode.runtime.constants")
local pure_suite = require("__factorio-trade-mode__.tests.pure_suite")
local util = require("__factorio-trade-mode__.trade_mode.core.util")
local ubi = require("__factorio-trade-mode__.trade_mode.core.ubi")
local report_log_prefix = "TRADE_MODE_TEST_REPORT "
local synthetic_seller_id = 1
local synthetic_inserter_overflow_seller_id = 3

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

local function find_order_row(rows, box_id)
  for _, row in ipairs(rows) do
    if row.box_id == box_id then
      return row
    end
  end
  return nil
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

local function create_burner_inserter(position, direction, owner_player_index, min_unit_price)
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
  local min_result = nil
  if min_unit_price ~= nil then
    min_result = remote_call("test_set_inserter_min_price", entity.unit_number, min_unit_price)
  end
  return entity, bind_result, min_result
end

local function run_ui_open_case()
  local result = remote_call("test_toggle_main_ui", 1)
  add_result(
    "Scenario I: Main UI opens and closes without runtime errors",
    result.ok == true,
    "Opening the main trade UI creates the expected root widgets and closing it removes them again.",
    {
      "Invoke the same toggle logic used by the shortcut for player 1.",
      "Verify the main frame and tabbed pane are created.",
      "Toggle again and verify the window closes cleanly.",
    },
    result
  )
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

local function run_manual_overflow_case()
  clear_area({{-5, 6}, {5, 16}})

  local before = snapshot()
  local seller_before_balance = before.balances[tostring(synthetic_seller_id)] or 0
  remote_call("credit_player", 23, 30)

  local box = create_trade_box({0, 10})
  local box_id = util.id_key(box.unit_number)
  local created = remote_call("create_order", box.unit_number, 23, "iron-ore", 10)

  box.get_inventory(defines.inventory.chest).insert({name = "iron-ore", count = 5})
  local manual_note = remote_call("test_note_manual_insertion", box.unit_number, synthetic_seller_id, "iron-ore", 5)
  remote_call("reconcile_now")

  local after = snapshot()
  local seller_after_balance = after.balances[tostring(synthetic_seller_id)] or 0
  local buyer_after = after.balances["23"] or 0
  local box_count = box.get_inventory(defines.inventory.chest).get_item_count("iron-ore")
  local live_order = nil
  for _, row in ipairs(after.orders) do
    if row.box_id == box_id then
      live_order = row
      break
    end
  end

  add_result(
    "Scenario F: Manual overflow only sells the affordable subset",
    seller_after_balance - seller_before_balance == 30
      and buyer_after == 0
      and box_count == 3
      and (live_order and live_order.total_traded == 30 and live_order.total_units_traded == 3 or false),
    "Seller earns 30 gold, buyer 23 ends at 0, the trade box keeps 3 iron ore, and the order records only 3 sold units.",
    {
      "Credit buyer account 23 with 30 gold.",
      "Create a trade box and buy order for 5 iron ore at 10 gold each.",
      "Insert all 5 manually and reconcile once.",
    },
    {
      seller_before_balance = seller_before_balance,
      seller_after_balance = seller_after_balance,
      buyer_after = buyer_after,
      box_count = box_count,
      created_ok = created.ok,
      manual_note_ok = manual_note.ok,
      order_found = live_order ~= nil,
      order_total_traded = live_order and live_order.total_traded or 0,
      order_total_units_traded = live_order and live_order.total_units_traded or 0,
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
  local inserter, bind_result, min_result = create_burner_inserter({area_origin_x + 1, 0}, defines.direction.west, synthetic_seller_id, 1)
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
    min_price_set_ok = min_result and min_result.ok or false,
    min_price_set_error = min_result and min_result.error or "missing",
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
      min_price_set_ok = checkpoint.min_price_set_ok,
      min_price_set_error = checkpoint.min_price_set_error,
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
    string.find(status_report, "money_traded_last_minute: 180", 1, true) ~= nil and string.find(money_report, "value: 180", 1, true) ~= nil,
    "trade_status and trade_money_last_minute both report 180 after the manual, overflow, team-wallet, and automated trade scenarios.",
    {
      "Run the manual, overflow, team-wallet, and automated trade scenarios first.",
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
      min_price_set_ok = checkpoint.min_price_set_ok,
      min_price_set_error = checkpoint.min_price_set_error,
      tracked_trade_boxes = after.tracked_trade_boxes,
      tracked_inserters = after.tracked_inserters,
      order_found = live_order ~= nil,
      order_status = live_order and live_order.status or "missing",
      order_total_traded = live_order and live_order.total_traded or 0,
    }
  )

  ensure_state().checkpoints["scenario_c"] = nil
end

local function setup_automated_overflow_case()
  clear_area({{36, -4}, {44, 4}})

  local before = snapshot()
  local seller_before = before.balances[tostring(synthetic_inserter_overflow_seller_id)] or 0
  remote_call("credit_player", 24, 25)

  local source = create_container("steel-chest", {36, 0})
  local box = create_trade_box({38, 0})
  local inserter, bind_result, min_result = create_burner_inserter({37, 0}, defines.direction.west, synthetic_inserter_overflow_seller_id, 1)
  source.get_inventory(defines.inventory.chest).insert({name = "iron-ore", count = 3})
  local box_id = util.id_key(box.unit_number)
  local created = remote_call("create_order", box.unit_number, 24, "iron-ore", 10)

  ensure_state().checkpoints["scenario_g"] = {
    seller_before = seller_before,
    buyer_id = 24,
    box = box,
    box_id = box_id,
    source = source,
    inserter = inserter,
    due_tick = game.tick + 240,
    created_ok = created.ok,
    owner_bind_ok = bind_result.ok,
    owner_bind_error = bind_result.error,
    min_price_set_ok = min_result and min_result.ok or false,
    min_price_set_error = min_result and min_result.error or "missing",
  }
end

local function check_automated_overflow_case()
  local checkpoint = ensure_state().checkpoints["scenario_g"]
  if not checkpoint or game.tick < checkpoint.due_tick then
    return
  end

  local after = snapshot()
  local seller_after = after.balances[tostring(synthetic_inserter_overflow_seller_id)] or 0
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
    "Scenario G: Inserter overflow leaves the unaffordable remainder unsold",
    seller_after - checkpoint.seller_before == 20
      and buyer_after == 5
      and box_count == 2
      and (source_count + held_count) == 1
      and payout == 20
      and (live_order and live_order.total_traded == 20 and live_order.total_units_traded == 2 or false),
    "Seller earns 20 gold, buyer 24 ends at 5, the trade box keeps 2 iron ore, and 1 iron ore remains on the source side unsold.",
    {
      "Credit buyer account 24 with 25 gold.",
      "Feed 3 iron ore into a trade box through a burner inserter at 10 gold each.",
      "Let the automation settle only the affordable 2 ore.",
    },
    {
      seller_before = checkpoint.seller_before,
      seller_after = seller_after,
      buyer_after = buyer_after,
      box_count = box_count,
      source_count = source_count,
      held_count = held_count,
      inserter_payout = payout,
      created_ok = checkpoint.created_ok,
      owner_bind_ok = checkpoint.owner_bind_ok,
      owner_bind_error = checkpoint.owner_bind_error,
      min_price_set_ok = checkpoint.min_price_set_ok,
      min_price_set_error = checkpoint.min_price_set_error,
      order_found = live_order ~= nil,
      order_total_traded = live_order and live_order.total_traded or 0,
      order_total_units_traded = live_order and live_order.total_units_traded or 0,
    }
  )

  ensure_state().checkpoints["scenario_g"] = nil
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
  local low_gold, low_ore_per_player, low_per_player_gold = ubi.compute_team_gold_per_second(constants.ubi, low_rate, 1)
  local high_gold, high_ore_per_player, high_per_player_gold = ubi.compute_team_gold_per_second(constants.ubi, high_rate, 10)

  add_result(
    "Scenario E: UBI scales off throughput per player",
    high_rate > low_rate and high_ore_per_player == low_ore_per_player and math.abs(high_per_player_gold - low_per_player_gold) < 0.000001,
    "The pure UBI engine keeps per-player gold_per_second steady when throughput and player count scale together.",
    {
      "Feed the pure UBI module a low-throughput rolling sample window for one player.",
      "Feed the same module a ten-times-higher throughput window for ten players.",
      "Compare the resulting ore-per-player and per-player gold_per_second values.",
    },
    {
      low_rate = low_rate,
      high_rate = high_rate,
      low_ore_per_player = low_ore_per_player,
      high_ore_per_player = high_ore_per_player,
      low_gold = low_gold,
      high_gold = high_gold,
      low_per_player_gold = low_per_player_gold,
      high_per_player_gold = high_per_player_gold,
    }
  )
end

local function contains_value(values, target)
  for _, value in ipairs(values) do
    if value == target then
      return true
    end
  end
  return false
end

local function run_script_destroy_cleanup_case()
  clear_area({{46, -4}, {54, 4}})

  local box = create_trade_box({50, 0})
  local box_id = util.id_key(box.unit_number)
  local created = remote_call("create_order", box.unit_number, 2, "iron-ore", 10)
  local before = snapshot()

  box.destroy({raise_destroy = true})

  local after = snapshot()
  local remaining_order = nil
  for _, row in ipairs(after.orders) do
    if row.box_id == box_id then
      remaining_order = row
      break
    end
  end

  add_result(
    "Scenario H: Script-raised destroy cleans up tracked trade boxes immediately",
    contains_value(before.tracked_trade_boxes, box_id)
      and not contains_value(after.tracked_trade_boxes, box_id)
      and remaining_order == nil,
    "Destroying a tracked trade box with raise_destroy removes it from runtime tracking and cancels its active order immediately.",
    {
      "Create a tracked trade box and attach an active order.",
      "Destroy the entity with raise_destroy enabled so script_raised_destroy fires.",
      "Verify the trade box disappears from runtime tracking and the order no longer appears in the active snapshot immediately.",
    },
    {
      created_ok = created.ok,
      before_tracked_trade_boxes = before.tracked_trade_boxes,
      after_tracked_trade_boxes = after.tracked_trade_boxes,
      remaining_order_status = remaining_order and remaining_order.status or "none",
    }
  )
end

local function run_team_wallet_cross_force_trade_case()
  clear_area({{56, -4}, {66, 4}})

  remote_call("test_set_player_force", 30, "team-a")
  remote_call("test_set_player_force", 31, "team-a")
  remote_call("test_set_player_force", 32, "team-b")

  local before = snapshot()
  local buyer_before = before.balances["30"] or 0
  local teammate_before = before.balances["31"] or 0
  local seller_before = before.balances["32"] or 0

  remote_call("credit_player", 30, 50)
  remote_call("credit_player", 31, 50)

  local box = create_trade_box({60, 0})
  local box_id = util.id_key(box.unit_number)
  local created = remote_call("create_order", box.unit_number, 30, "iron-ore", 10)
  box.get_inventory(defines.inventory.chest).insert({name = "iron-ore", count = 5})
  remote_call("test_note_manual_insertion", box.unit_number, 32, "iron-ore", 5)
  remote_call("reconcile_now")

  local after = snapshot()
  local buyer_after = after.balances["30"] or 0
  local teammate_after = after.balances["31"] or 0
  local seller_after = after.balances["32"] or 0

  local live_order = nil
  for _, row in ipairs(after.orders) do
    if row.box_id == box_id then
      live_order = row
      break
    end
  end

  local buyer_delta = buyer_after - buyer_before
  local teammate_delta = teammate_after - teammate_before
  local seller_delta = seller_after - seller_before

  add_result(
    "Scenario J: Team wallet sharing and cross-team trade settlement",
    buyer_delta == 50
      and teammate_delta == 50
      and seller_delta == 50
      and (live_order and live_order.first_fill_notified == true or false),
    "Team A's two players both reflect the same post-trade wallet (delta +50), Team B seller gains 50, and first-fill notification flag is set on the order.",
    {
      "Track synthetic buyer players 30 and 31 as team-a, and synthetic supplier 32 as team-b.",
      "Credit both team-a players (which should hit one shared wallet) then create a 5 x iron-ore @ 10 order for player 30.",
      "Insert 5 iron ore as team-b supplier and reconcile immediately.",
    },
    {
      created_ok = created.ok,
      buyer_before = buyer_before,
      buyer_after = buyer_after,
      teammate_before = teammate_before,
      teammate_after = teammate_after,
      seller_before = seller_before,
      seller_after = seller_after,
      buyer_delta = buyer_delta,
      teammate_delta = teammate_delta,
      seller_delta = seller_delta,
      wallet_balances = after.wallet_balances,
      order_found = live_order ~= nil,
      first_fill_notified = live_order and live_order.first_fill_notified or false,
      order_total_traded = live_order and live_order.total_traded or 0,
    }
  )
end

local function setup_price_lock_and_floor_case()
  clear_area({{68, -4}, {78, 4}})

  remote_call("credit_player", 33, 100)
  local before = snapshot()
  local seller_before = before.balances[tostring(synthetic_seller_id)] or 0

  local source = create_container("steel-chest", {68, 0})
  local box = create_trade_box({70, 0})
  local inserter, bind_result, min_result = create_burner_inserter({69, 0}, defines.direction.west, synthetic_seller_id, 9)
  source.get_inventory(defines.inventory.chest).insert({name = "iron-ore", count = 1})
  local created = remote_call("create_order", box.unit_number, 33, "iron-ore", 10)

  ensure_state().checkpoints["scenario_k"] = {
    stage = "wait_hold",
    started_tick = game.tick,
    seller_before = seller_before,
    source = source,
    box = box,
    box_id = util.id_key(box.unit_number),
    inserter = inserter,
    created_ok = created.ok,
    owner_bind_ok = bind_result.ok,
    owner_bind_error = bind_result.error,
    min_price_set_ok = min_result and min_result.ok or false,
    min_price_set_error = min_result and min_result.error or "missing",
    first_price_update_ok = false,
    second_price_update_ok = false,
  }
end

local function finish_price_lock_and_floor_case(ok, details)
  add_result(
    "Scenario K: Inserter price lock and supplier floor-price enforcement",
    ok,
    "An in-flight inserter delivery settles at its locked pickup price, then a lowered order below the inserter minimum is blocked with no extra payout.",
    {
      "Create a burner inserter owned by seller 1 with minimum acceptable price 9.",
      "Create a 1 x iron-ore @ 10 order, wait for the inserter to hold the stack, then lower order price to 1 before drop.",
      "After the first settlement, lower order price to 8, feed one more ore, and verify no additional trade settles.",
    },
    details
  )
  ensure_state().checkpoints["scenario_k"] = nil
  ensure_state().price_lock_case_done = true
end

local function check_price_lock_and_floor_case()
  local checkpoint = ensure_state().checkpoints["scenario_k"]
  if not checkpoint then
    return
  end

  if checkpoint.stage == "wait_hold" then
    if checkpoint.inserter.held_stack.valid_for_read and checkpoint.inserter.held_stack.name == "iron-ore" then
      checkpoint.hold_detected_tick = checkpoint.hold_detected_tick or game.tick
      if game.tick > checkpoint.hold_detected_tick then
        local updated = remote_call("update_order_price", checkpoint.box.unit_number, 1)
        checkpoint.first_price_update_ok = updated and updated.ok == true
        checkpoint.stage = "wait_first_settlement"
        checkpoint.first_due_tick = game.tick + 240
      end
      return
    end

    if game.tick > checkpoint.started_tick + 240 then
      finish_price_lock_and_floor_case(false, {
        reason = "inserter_never_held_stack",
        created_ok = checkpoint.created_ok,
        owner_bind_ok = checkpoint.owner_bind_ok,
        owner_bind_error = checkpoint.owner_bind_error,
        min_price_set_ok = checkpoint.min_price_set_ok,
        min_price_set_error = checkpoint.min_price_set_error,
      })
    end
    return
  end

  if checkpoint.stage == "wait_first_settlement" then
    local after = snapshot()
    local seller_after = after.balances[tostring(synthetic_seller_id)] or 0
    local live_order = find_order_row(after.orders, checkpoint.box_id)
    if live_order and live_order.total_units_traded >= 1 then
      checkpoint.seller_after_first = seller_after
      checkpoint.first_order_total_traded = live_order.total_traded or 0
      checkpoint.first_order_units = live_order.total_units_traded or 0
      local updated = remote_call("update_order_price", checkpoint.box.unit_number, 8)
      checkpoint.second_price_update_ok = updated and updated.ok == true
      checkpoint.source.get_inventory(defines.inventory.chest).insert({name = "iron-ore", count = 1})
      checkpoint.stage = "wait_floor_block"
      checkpoint.second_due_tick = game.tick + 240
      return
    end

    if checkpoint.first_due_tick and game.tick > checkpoint.first_due_tick then
      finish_price_lock_and_floor_case(false, {
        reason = "first_delivery_did_not_settle",
        created_ok = checkpoint.created_ok,
        first_price_update_ok = checkpoint.first_price_update_ok,
        first_due_tick = checkpoint.first_due_tick,
      })
    end
    return
  end

  if checkpoint.stage == "wait_floor_block" and checkpoint.second_due_tick and game.tick >= checkpoint.second_due_tick then
    local after = snapshot()
    local seller_after = after.balances[tostring(synthetic_seller_id)] or 0
    local buyer_after = after.balances["33"] or 0
    local box_count = checkpoint.box.get_inventory(defines.inventory.chest).get_item_count("iron-ore")
    local source_count = checkpoint.source.get_inventory(defines.inventory.chest).get_item_count("iron-ore")
    local held_count = checkpoint.inserter.held_stack.valid_for_read and checkpoint.inserter.held_stack.count or 0
    local live_order = find_order_row(after.orders, checkpoint.box_id)

    local first_delta = (checkpoint.seller_after_first or checkpoint.seller_before) - checkpoint.seller_before
    local final_delta = seller_after - checkpoint.seller_before
    local ok =
      checkpoint.created_ok
      and checkpoint.owner_bind_ok
      and checkpoint.min_price_set_ok
      and checkpoint.first_price_update_ok
      and checkpoint.second_price_update_ok
      and first_delta == 10
      and final_delta == 10
      and buyer_after == 90
      and box_count == 1
      and (source_count + held_count) == 1
      and (live_order and live_order.total_traded == 10 and live_order.total_units_traded == 1 or false)

    finish_price_lock_and_floor_case(ok, {
      created_ok = checkpoint.created_ok,
      owner_bind_ok = checkpoint.owner_bind_ok,
      owner_bind_error = checkpoint.owner_bind_error,
      min_price_set_ok = checkpoint.min_price_set_ok,
      min_price_set_error = checkpoint.min_price_set_error,
      first_price_update_ok = checkpoint.first_price_update_ok,
      second_price_update_ok = checkpoint.second_price_update_ok,
      seller_before = checkpoint.seller_before,
      seller_after_first = checkpoint.seller_after_first,
      seller_after = seller_after,
      buyer_after = buyer_after,
      box_count = box_count,
      source_count = source_count,
      held_count = held_count,
      order_found = live_order ~= nil,
      order_total_traded = live_order and live_order.total_traded or 0,
      order_total_units_traded = live_order and live_order.total_units_traded or 0,
      tracked_inserters = after.tracked_inserters,
    })
  end
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
    run_ui_open_case()
    run_manual_trade_case()
    run_manual_overflow_case()
    setup_automated_trade_case("scenario_b", 10, 20, 100, 3)
    setup_automated_trade_case("scenario_c", 24, 21, 0, 1)
    setup_automated_overflow_case()
    run_ubi_scaling_case()
    run_script_destroy_cleanup_case()
    run_team_wallet_cross_force_trade_case()
  end

  check_automated_trade_case()
  check_insufficient_funds_case()
  check_automated_overflow_case()
  check_price_lock_and_floor_case()

  if
    test_state.started and
    not test_state.price_lock_case_started and
    not test_state.checkpoints["scenario_b"] and
    not test_state.checkpoints["scenario_c"] and
    not test_state.checkpoints["scenario_g"]
  then
    setup_price_lock_and_floor_case()
    test_state.price_lock_case_started = true
  end

  if
    test_state.started and
    not test_state.contract_case_done and
    test_state.price_lock_case_done and
    not test_state.checkpoints["scenario_k"]
  then
    run_contract_case()
    test_state.contract_case_done = true
  end

  if test_state.started and test_state.contract_case_done and not test_state.finished and event.tick >= 620 then
    write_report()
  end
end)
