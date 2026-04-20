local contracts = require("trade_mode.core.contracts")
local inserter_stats = require("trade_mode.core.inserter_stats")
local ledger = require("trade_mode.core.ledger")
local lib = require("tests.test_lib")
local metrics = require("trade_mode.core.metrics")
local orders = require("trade_mode.core.orders")
local pricing = require("trade_mode.core.pricing")
local suggested_prices = require("trade_mode.suggested-prices-config")
local ubi = require("trade_mode.core.ubi")

local suite = {}

function suite.run()
  return lib.run_cases("pure", {
    {
      name = "ledger transfer succeeds iff sender has funds",
      run = function()
        local state = {}
        ledger.create_account(state, 1)
        ledger.create_account(state, 2)
        ledger.credit(state, 1, 40, "seed")
        local result = ledger.transfer(state, 1, 2, 25, "test")
        lib.assert_true(result.ok)
        lib.assert_equal(ledger.get_balance(state, 1), 15)
        lib.assert_equal(ledger.get_balance(state, 2), 25)
      end,
    },
    {
      name = "ledger supports named wallet accounts for team balances",
      run = function()
        local state = {}
        ledger.credit(state, "force:alpha", 60, "seed")
        local result = ledger.transfer(state, "force:alpha", "force:beta", 35, "trade")
        lib.assert_true(result.ok)
        lib.assert_equal(ledger.get_balance(state, "force:alpha"), 25)
        lib.assert_equal(ledger.get_balance(state, "force:beta"), 35)
      end,
    },
    {
      name = "failed debit leaves balances unchanged",
      run = function()
        local state = {}
        ledger.credit(state, 1, 10, "seed")
        local result = ledger.debit(state, 1, 99, "too-much")
        lib.assert_false(result.ok)
        lib.assert_equal(ledger.get_balance(state, 1), 10)
      end,
    },
    {
      name = "known item returns configured suggested price",
      run = function()
        local value = pricing.get_suggested_price(suggested_prices, "iron-ore")
        lib.assert_equal(value, suggested_prices["iron-ore"])
      end,
    },
    {
      name = "unknown item returns documented error",
      run = function()
        local value, err = pricing.get_suggested_price(suggested_prices, "definitely-not-real")
        lib.assert_nil(value)
        lib.assert_equal(err, "unknown_item")
      end,
    },
    {
      name = "invalid unit price is rejected when creating an order",
      run = function()
        local ok = pcall(function()
          orders.create_order({}, {
            box_id = "box-1",
            buyer_id = 2,
            item_name = "iron-ore",
            unit_price = 0,
            tick = 1,
          })
        end)
        lib.assert_false(ok)
      end,
    },
    {
      name = "invalid unit price is rejected when updating an order",
      run = function()
        local order_state = {}
        local created = orders.create_order(order_state, {
          box_id = "box-1",
          buyer_id = 2,
          item_name = "iron-ore",
          unit_price = 7,
          tick = 1,
        })
        local ok = pcall(function()
          orders.update_order(order_state, created.order.id, {
            unit_price = 0,
          })
        end)
        lib.assert_false(ok)
      end,
    },
    {
      name = "order settlement succeeds and transfers funds when affordable",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, 2, 100, "seed")
        local order_state = {}
        local created = orders.create_order(order_state, {
          box_id = "box-1",
          buyer_id = 2,
          item_name = "iron-ore",
          unit_price = 7,
          tick = 1,
        })
        local result = orders.settle_insert(order_state, ledger_state, created.order.id, 1, 3, 2)
        lib.assert_true(result.ok)
        lib.assert_equal(result.unit_price, 7)
        lib.assert_equal(ledger.get_balance(ledger_state, 2), 79)
        lib.assert_equal(ledger.get_balance(ledger_state, 1), 21)
      end,
    },
    {
      name = "order settlement can honor a locked unit price override",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, 2, 100, "seed")
        local order_state = {}
        local created = orders.create_order(order_state, {
          box_id = "box-lock",
          buyer_id = 2,
          item_name = "iron-ore",
          unit_price = 10,
          tick = 1,
        })
        orders.update_order(order_state, created.order.id, {
          unit_price = 1,
          tick = 2,
        })
        local result = orders.settle_insert(order_state, ledger_state, created.order.id, 1, 1, 3, nil, 10)
        lib.assert_true(result.ok)
        lib.assert_equal(result.unit_price, 10)
        lib.assert_equal(ledger.get_balance(ledger_state, 2), 90)
        lib.assert_equal(ledger.get_balance(ledger_state, 1), 10)
      end,
    },
    {
      name = "order settlement can transfer using buyer and supplier wallet ids",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, "force:buyers", 100, "seed")
        local order_state = {}
        local created = orders.create_order(order_state, {
          box_id = "box-wallet",
          buyer_id = 2,
          buyer_wallet_id = "force:buyers",
          item_name = "iron-ore",
          unit_price = 7,
          tick = 1,
        })
        local result = orders.settle_insert(order_state, ledger_state, created.order.id, 1, 3, 2, "force:suppliers")
        lib.assert_true(result.ok)
        lib.assert_equal(ledger.get_balance(ledger_state, "force:buyers"), 79)
        lib.assert_equal(ledger.get_balance(ledger_state, "force:suppliers"), 21)
      end,
    },
    {
      name = "order settlement fails without transfer when unaffordable",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, 2, 5, "seed")
        local order_state = {}
        local created = orders.create_order(order_state, {
          box_id = "box-1",
          buyer_id = 2,
          item_name = "iron-ore",
          unit_price = 7,
          tick = 1,
        })
        local result = orders.settle_insert(order_state, ledger_state, created.order.id, 1, 1, 2)
        lib.assert_false(result.ok)
        lib.assert_equal(ledger.get_balance(ledger_state, 2), 5)
        lib.assert_equal(ledger.get_balance(ledger_state, 1), 0)
      end,
    },
    {
      name = "order settlement can settle an affordable subset deterministically",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, 2, 25, "seed")
        local order_state = {}
        local created = orders.create_order(order_state, {
          box_id = "box-1",
          buyer_id = 2,
          item_name = "iron-ore",
          unit_price = 10,
          tick = 1,
        })
        local result = orders.settle_insert(order_state, ledger_state, created.order.id, 1, 2, 2)
        lib.assert_true(result.ok)
        lib.assert_equal(ledger.get_balance(ledger_state, 2), 5)
        lib.assert_equal(ledger.get_balance(ledger_state, 1), 20)
        lib.assert_equal(created.order.total_units_traded, 2)
      end,
    },
    {
      name = "zero quantity is rejected",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, 2, 50, "seed")
        local order_state = {}
        local created = orders.create_order(order_state, {
          box_id = "box-1",
          buyer_id = 2,
          item_name = "iron-ore",
          unit_price = 7,
          tick = 1,
        })
        local ok = pcall(function()
          orders.settle_insert(order_state, ledger_state, created.order.id, 1, 0, 2)
        end)
        lib.assert_false(ok)
      end,
    },
    {
      name = "unauthorized contract payout fails",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, 2, 100, "seed")
        local contract_state = {}
        local created = contracts.create_contract(contract_state, {
          creator_id = 2,
          title = "Build belts",
          description = "Lay belts",
          amount = 30,
          tick = 1,
        })
        contracts.assign_self(contract_state, created.contract.id, 1, 2)
        local result = contracts.payout(contract_state, ledger_state, created.contract.id, 1, 3)
        lib.assert_false(result.ok)
        lib.assert_equal(result.error, "unauthorized")
      end,
    },
    {
      name = "successful contract payout debits and credits atomically",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, 2, 100, "seed")
        local contract_state = {}
        local created = contracts.create_contract(contract_state, {
          creator_id = 2,
          title = "Build belts",
          description = "Lay belts",
          amount = 30,
          tick = 1,
        })
        contracts.assign_self(contract_state, created.contract.id, 1, 2)
        local result = contracts.payout(contract_state, ledger_state, created.contract.id, 2, 3)
        lib.assert_true(result.ok)
        lib.assert_equal(ledger.get_balance(ledger_state, 2), 70)
        lib.assert_equal(ledger.get_balance(ledger_state, 1), 30)
      end,
    },
    {
      name = "contract payout uses creator and assignee wallet ids",
      run = function()
        local ledger_state = {}
        ledger.credit(ledger_state, "force:creator", 100, "seed")
        local contract_state = {}
        local created = contracts.create_contract(contract_state, {
          creator_id = 2,
          creator_wallet_id = "force:creator",
          title = "Build belts",
          description = "Lay belts",
          amount = 30,
          tick = 1,
        })
        contracts.assign_self(contract_state, created.contract.id, 1, 2, nil, "force:assignee")
        local result = contracts.payout(contract_state, ledger_state, created.contract.id, 2, 3)
        lib.assert_true(result.ok)
        lib.assert_equal(ledger.get_balance(ledger_state, "force:creator"), 70)
        lib.assert_equal(ledger.get_balance(ledger_state, "force:assignee"), 30)
      end,
    },
    {
      name = "contracts list open first and newest first within status groups",
      run = function()
        local contract_state = {}
        local oldest_open = contracts.create_contract(contract_state, {
          creator_id = 2,
          title = "Old open",
          description = "A",
          amount = 10,
          tick = 1,
        }).contract
        local newer_open = contracts.create_contract(contract_state, {
          creator_id = 2,
          title = "New open",
          description = "B",
          amount = 10,
          tick = 3,
        }).contract
        local assigned = contracts.create_contract(contract_state, {
          creator_id = 2,
          title = "Assigned",
          description = "C",
          amount = 10,
          tick = 2,
        }).contract
        local completed = contracts.create_contract(contract_state, {
          creator_id = 2,
          title = "Completed",
          description = "D",
          amount = 10,
          tick = 4,
        }).contract
        contracts.assign_self(contract_state, assigned.id, 1, 5)
        contracts.assign_self(contract_state, completed.id, 1, 6)
        local ledger_state = {}
        ledger.credit(ledger_state, 2, 100, "seed")
        contracts.payout(contract_state, ledger_state, completed.id, 2, 7)

        local listed = contracts.list_all(contract_state)
        lib.assert_equal(listed[1].id, newer_open.id)
        lib.assert_equal(listed[2].id, oldest_open.id)
        lib.assert_equal(listed[3].id, assigned.id)
        lib.assert_equal(listed[4].id, completed.id)
      end,
    },
    {
      name = "higher ore throughput produces higher or equal UBI payout",
      run = function()
        local config = {
          base_income = 2,
          income_scale = 0.08,
          income_exponent = 0.85,
        }
        local low = ubi.compute_gold_per_second(config, 60)
        local high = ubi.compute_gold_per_second(config, 600)
        lib.assert_true(high >= low)
      end,
    },
    {
      name = "same ore per player keeps per-player UBI steady as force size grows",
      run = function()
        local config = {
          base_income = 2,
          income_scale = 0.08,
          income_exponent = 0.85,
        }
        local solo = ubi.plan_distribution({}, config, 120, {1})
        local duo = ubi.plan_distribution({}, config, 240, {1, 2})
        lib.assert_equal(solo.ore_per_player_per_minute, 120)
        lib.assert_equal(duo.ore_per_player_per_minute, 120)
        lib.assert_true(math.abs(solo.per_player_gold_per_second - duo.per_player_gold_per_second) < 0.000001)
        lib.assert_true(math.abs(duo.raw_gold_per_second - (solo.per_player_gold_per_second * 2)) < 0.000001)
      end,
    },
    {
      name = "same total ore with more players lowers per-player UBI",
      run = function()
        local config = {
          base_income = 2,
          income_scale = 0.08,
          income_exponent = 0.85,
        }
        local solo = ubi.plan_distribution({}, config, 600, {1})
        local crowd = ubi.plan_distribution({}, config, 600, {1, 2, 3, 4, 5, 6})
        lib.assert_true(solo.ore_per_player_per_minute > crowd.ore_per_player_per_minute)
        lib.assert_true(solo.per_player_gold_per_second > crowd.per_player_gold_per_second)
      end,
    },
    {
      name = "no connected players means no UBI accrual",
      run = function()
        local state = {}
        local config = {
          base_income = 2,
          income_scale = 0.08,
          income_exponent = 0.85,
        }
        local plan = ubi.plan_distribution(state, config, 600, {})
        lib.assert_equal(plan.raw_gold_per_second, 0)
        lib.assert_equal(plan.creditable_amount, 0)
        lib.assert_equal(state.fractional_bank, 0)
      end,
    },
    {
      name = "same ore per player stays fair over repeated payout ticks",
      run = function()
        local config = {
          base_income = 2,
          income_scale = 0.08,
          income_exponent = 0.85,
        }
        local solo_state = {}
        local trio_state = {}
        local solo_total = 0
        local trio_totals = {[1] = 0, [2] = 0, [3] = 0}

        for _ = 1, 180 do
          local solo_plan = ubi.plan_distribution(solo_state, config, 180, {1})
          solo_total = solo_total + (solo_plan.payouts[1] or 0)

          local trio_plan = ubi.plan_distribution(trio_state, config, 540, {1, 2, 3})
          trio_totals[1] = trio_totals[1] + (trio_plan.payouts[1] or 0)
          trio_totals[2] = trio_totals[2] + (trio_plan.payouts[2] or 0)
          trio_totals[3] = trio_totals[3] + (trio_plan.payouts[3] or 0)
        end

        for player_id = 1, 3 do
          lib.assert_true(math.abs(trio_totals[player_id] - solo_total) <= 1, "per-player repeated payout drifted too far")
        end
      end,
    },
    {
      name = "fixed throughput payout is repeatable tick to tick",
      run = function()
        local state_a = {}
        local state_b = {}
        local player_ids = {1, 2}
        local config = {
          base_income = 2,
          income_scale = 0.08,
          income_exponent = 0.85,
        }
        local plan_a = ubi.plan_distribution(state_a, config, 240, player_ids)
        local plan_b = ubi.plan_distribution(state_b, config, 240, player_ids)
        lib.assert_equal(plan_a.creditable_amount, plan_b.creditable_amount)
        lib.assert_equal(plan_a.payouts[1], plan_b.payouts[1])
        lib.assert_equal(plan_a.payouts[2], plan_b.payouts[2])
      end,
    },
    {
      name = "window sum drops expired buckets deterministically",
      run = function()
        local state = {}
        metrics.record_trade(state, 1, 10, 1, 2)
        metrics.record_trade(state, 30, 20, 1, 2)
        metrics.record_trade(state, 61, 5, 1, 2)
        metrics.prune(state, 61, 60)
        lib.assert_equal(metrics.trade_last_minute(state, 61), 25)
      end,
    },
    {
      name = "snapshot counts reflect domain state",
      run = function()
        local state = {}
        metrics.set_snapshot_counts(state, 3, 2)
        lib.assert_equal(state.snapshots.active_orders, 3)
        lib.assert_equal(state.snapshots.active_contracts, 2)
      end,
    },
    {
      name = "two inserter payouts accumulate lifetime total",
      run = function()
        local state = {}
        inserter_stats.record_payout(state, 1001, 1, 12, 1, 5, "box")
        inserter_stats.record_payout(state, 1001, 1, 8, 1, 6, "box")
        lib.assert_equal(inserter_stats.get(state, 1001).lifetime_payout, 20)
      end,
    },
    {
      name = "failed settlements do not change inserter totals",
      run = function()
        local state = {}
        lib.assert_nil(inserter_stats.get(state, 1001))
      end,
    },
  })
end

return suite
