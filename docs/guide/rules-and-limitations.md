[Back to Guide Contents](README.md)

# Rules And Limitations

This page collects the practical limits and expectations that matter during real play.

## Trade Box Rules

- A trade box can only host one current buy order at a time.
- Only `active` orders settle deliveries.
- `Paused` orders remain visible but do not process payouts.
- `Cancelled` orders are removed from the live box slot.
- The box inventory is filtered to the ordered item while an order exists.

## Delivery Rules

- Players only get paid when the mod can attribute the delivery to a real supplier.
- Manual delivery and automated delivery are both supported.
- Inserters must have a minimum acceptable unit price configured before they can auto-sell.
- If an order is below the inserter's minimum, that inserter will not settle new deliveries for that order.
- In-flight inserter deliveries use a locked pickup price, so buyer price edits apply to future deliveries, not the one already on the arm.
- If a delivery cannot be attributed safely, the mod refuses to pay blindly.
- Failed settlements refund or spill the items instead of letting them disappear unpaid.

## Contract Rules

- The creator cannot assign their own contract to themselves.
- Only the current assignee can unassign themselves.
- Only the creator can pay the contract.
- A contract must be assigned before it can be paid.
- A completed contract is final.

## Economy Rules

- Trade orders and contracts draw from the same gold balance system.
- In team play, each force shares one wallet across all members.
- Cross-force trade is allowed; settlement moves value between those force wallets.
- Only connected players receive UBI.
- Economy and recent-activity views use rolling 60-second windows.

## Map Tag Limitation

- Trade-box chart tags are force-wide because Factorio chart tags are force-wide.
- The mod cannot make chart-tag visibility personal to each player without leaving Factorio's normal chart-tag model.

## Current Scope Of The Mod

The mod is centered on:

- Buy orders
- Contract rewards
- UBI-driven currency injection
- Inserter-aware delivery tracking

It is not trying to be a full stock exchange, auction house, or train-scheduler replacement. The focus is readable multiplayer trade with strong automation support.

[Back to Guide Contents](README.md)
