[Back to Guide Contents](README.md)

# Inserters And Deliveries

The mod supports both hand-delivered trade and automated logistics. Inserters are treated as first-class trade helpers rather than passive item movers.

## Selecting An Inserter

When you select an inserter, the mod can show a `Trade stats` side panel with:

- Owner
- Pending trade box
- Lifetime payout
- Last recipient
- Last trade time

This is the fastest way to check whether an automated delivery line is actually earning money.

## How Inserter Ownership Works

The mod records an owner for tracked inserters when it can identify one from Factorio's normal entity history. In practical terms, this is the player most recently associated with placing or editing that inserter.

That owner is the player who gets credited when the inserter is identified as the delivery source for a settled trade.

## How Delivery Attribution Works

When items appear in a trade box, the mod tries to decide who should be paid.

It checks for:

- Recent manual insertion hints from player interactions.
- Recent inventory changes from a player who has that trade box open.
- Nearby inserters that were visibly carrying the ordered item into the box.

If attribution succeeds, the correct player gets paid. If attribution fails, the mod does not guess blindly.

## Automated Delivery Safeguards

For nearby inserters feeding an active trade box:

- The mod watches for held stacks that match the current order item.
- It tracks which box the inserter appears to be serving.
- It limits stack size based on what the buyer can currently afford.
- It can temporarily disable an inserter if the buyer has no budget for its held stack.

These safeguards help keep automated trading from burning items on unaffordable deliveries.

## Refund Behavior For Automation

If an automated delivery cannot be paid for:

- The mod first tries to put the items back into the inserter's pickup source.
- If that does not fully work, the remaining items are spilled near the source side of the inserter.

## Manual Delivery Behavior

For manual deliveries, the goal is simpler:

- Identify the player who inserted the items.
- Pay them if the order is valid and affordable.
- Return the items to them, or spill the overflow nearby, if settlement fails.

## Best Use Cases

- Seller-owned feeder lines into buyer-owned trade boxes.
- Shared mall setups where multiple players publish buy orders.
- Server economies where passive automation should still produce clear ownership and payouts.

[Back to Guide Contents](README.md)
