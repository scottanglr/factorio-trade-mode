# Deterministic Scenarios

## Scenario I

- Name: Main UI opens and closes without runtime errors
- Setup:
  - Invoke the same toggle logic used by the shortcut for player 1.
  - Verify the main frame and tabbed pane are created.
  - Toggle again and verify the window closes cleanly.
- Binary pass condition:
  - Opening the main trade UI creates the expected root widgets and closing it removes them again.

## Scenario A

- Name: Two-player manual box trade happy path
- Setup:
  - Credit buyer account 2 with 100 gold.
  - Create a trade box and a buy order for `iron-ore` at 10 gold.
  - Insert 5 `iron-ore` through the player fast-transfer event path.
- Binary pass condition:
  - Seller balance increases by 50, buyer 2 balance becomes 50, and the trade box holds 5 `iron-ore`.

## Scenario F

- Name: Manual overflow only sells the affordable subset
- Setup:
  - Credit buyer account 23 with 30 gold.
  - Create a trade box and buy order for 5 `iron-ore` at 10 gold each.
  - Insert all 5 manually and reconcile once.
- Binary pass condition:
  - Seller earns 30 gold, buyer 23 ends at 0, the trade box keeps 3 `iron-ore`, and the order records only 3 sold units.

## Scenario E

- Name: UBI scales off throughput per player
- Setup:
  - Feed the pure UBI module one rolling sample window representing 60 ore/min for one player.
  - Feed it a second rolling sample window representing 600 ore/min for ten players.
- Binary pass condition:
  - The high-throughput case yields the same ore-per-player and the same per-player `gold_per_second` result.

## Scenario H

- Name: Script-raised destroy cleans up tracked trade boxes immediately
- Setup:
  - Create a tracked trade box and attach an active order.
  - Destroy the entity with `raise_destroy = true`.
  - Read the remote state snapshot immediately afterward.
- Binary pass condition:
  - The destroyed box is gone from `tracked_trade_boxes` and its order is gone from the active-order snapshot in the same scripted step.

## Scenario J

- Name: Team wallet sharing and cross-team trade settlement
- Setup:
  - Track synthetic buyers `30` and `31` as `team-a`, and synthetic supplier `32` as `team-b`.
  - Credit both team-a players, create a `5 x iron-ore @ 10` order for buyer `30`, and insert all 5 as supplier `32`.
  - Reconcile once and read snapshot balances/order flags.
- Binary pass condition:
  - Buyers `30` and `31` both reflect the same post-trade shared-wallet result, supplier `32` gains the payout, and the order's `first_fill_notified` flag is set.

## Scenario B

- Name: Inserter-owned automation trade attribution
- Setup:
  - Create a source chest, a burner inserter, and a trade box in a straight line.
  - Set inserter minimum acceptable price to `1`.
  - Credit buyer account 20 with 100 gold and create a `3 x iron-ore @ 10` order.
  - Let the inserter run for 240 ticks.
- Binary pass condition:
  - Seller balance increases by 30, buyer 20 balance becomes 70, the trade box holds 3 `iron-ore`, and the inserter lifetime payout equals 30.

## Scenario C

- Name: Insufficient-funds rejection with no item movement
- Setup:
  - Create the same burner-inserter automation path.
  - Set inserter minimum acceptable price to `1`.
  - Create an order for buyer account 21 with zero gold.
  - Let the automation run for 240 ticks.
- Binary pass condition:
  - The trade box holds 0 `iron-ore`, the original item remains on the source side, the order `total_traded` stays `0`, and the inserter payout stays `0`.

## Scenario G

- Name: Inserter overflow leaves the unaffordable remainder unsold
- Setup:
  - Credit buyer account 24 with 25 gold.
  - Set inserter minimum acceptable price to `1`.
  - Feed 3 `iron-ore` into a trade box through a burner inserter at 10 gold each.
  - Let the automation settle only the affordable 2 ore.
- Binary pass condition:
  - Seller earns 20 gold, buyer 24 ends at 5, the trade box keeps 2 `iron-ore`, and 1 `iron-ore` remains on the source side unsold.

## Scenario K

- Name: Inserter price lock and supplier floor-price enforcement
- Setup:
  - Create a burner inserter owned by seller `1`, and set inserter minimum acceptable price to `9`.
  - Create an order `1 x iron-ore @ 10`, wait until the inserter is holding the stack, then lower the order to `1`.
  - After first settlement, lower order price to `8`, feed one more ore, and wait for reconciliation.
- Binary pass condition:
  - The first in-flight inserter delivery settles at `10` (locked pickup price), then no second settlement happens below the inserter minimum.

## Scenario D

- Name: Contract assign, unassign, and payout flow
- Setup:
  - Credit creator account 22 with 60 gold.
  - Create a 25 gold contract, assign account 1, unassign it, assign it again, and pay it.
- Binary pass condition:
  - Assignee account 1 gains 25 gold, creator account 22 ends on 35 gold, and payout returns `ok`.
