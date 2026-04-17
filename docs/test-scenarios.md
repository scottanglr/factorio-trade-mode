# Deterministic Scenarios

## Scenario A

- Name: Two-player manual box trade happy path
- Setup:
  - Credit buyer account 2 with 100 gold.
  - Create a trade box and a buy order for `iron-ore` at 10 gold.
  - Insert 5 `iron-ore` through the player fast-transfer event path.
- Binary pass condition:
  - Seller balance increases by 50, buyer 2 balance becomes 50, and the trade box holds 5 `iron-ore`.

## Scenario B

- Name: Inserter-owned automation trade attribution
- Setup:
  - Create a source chest, a burner inserter, and a trade box in a straight line.
  - Credit buyer account 20 with 100 gold and create a `3 x iron-ore @ 10` order.
  - Let the inserter run for 240 ticks.
- Binary pass condition:
  - Seller balance increases by 30, buyer 20 balance becomes 70, the trade box holds 3 `iron-ore`, and the inserter lifetime payout equals 30.

## Scenario C

- Name: Insufficient-funds rejection with no item movement
- Setup:
  - Create the same burner-inserter automation path.
  - Create an order for buyer account 21 with zero gold.
  - Let the automation run for 240 ticks.
- Binary pass condition:
  - The trade box holds 0 `iron-ore`, the original item remains on the source side, the order `total_traded` stays `0`, and the inserter payout stays `0`.

## Scenario D

- Name: Contract assign, unassign, and payout flow
- Setup:
  - Credit creator account 22 with 60 gold.
  - Create a 25 gold contract, assign account 1, unassign it, assign it again, and pay it.
- Binary pass condition:
  - Assignee account 1 gains 25 gold, creator account 22 ends on 35 gold, and payout returns `ok`.

## Scenario E

- Name: UBI scaling under low vs high ore throughput
- Setup:
  - Feed the pure UBI module one rolling sample window representing 60 ore/min.
  - Feed it a second rolling sample window representing 600 ore/min.
- Binary pass condition:
  - The high-throughput case yields both a higher ore/minute reading and a higher `gold_per_second` result.

## Scenario H

- Name: Script-raised destroy cleans up tracked trade boxes immediately
- Setup:
  - Create a tracked trade box and attach an active order.
  - Destroy the entity with `raise_destroy = true`.
  - Read the remote state snapshot immediately afterward.
- Binary pass condition:
  - The destroyed box is gone from `tracked_trade_boxes` and its order is gone from the active-order snapshot in the same scripted step.
