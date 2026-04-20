[Back to Guide Contents](README.md)

# Trade Boxes And Buy Orders

Trade boxes are the heart of the mod. Each trade box can host one live buy order at a time, and that order defines what the box will pay for.

## What A Trade Box Does

- Buys exactly one chosen item at a chosen unit price.
- Filters its inventory to match the current order item.
- Pays suppliers automatically when valid deliveries arrive.
- Exposes a map tag for active orders when chart tags are enabled.
- Sends a one-time notification to the order creator when the first valid supplier starts filling that order.

## Creating Or Updating An Order

The trade-box side panel lets you:

- Choose the item.
- Enter the price.
- Use the generated suggested price.
- Save the order.

Saving an existing order updates it in place. Saving a new order creates a new live order for that box.

Suggested prices include ingredient value and a recipe-energy surcharge derived from coal value.

## Order States

- `Active`: the box will accept delivery and attempt settlement.
- `Paused`: the order stays listed, but it does not settle deliveries.
- `Cancelled`: the order is removed from the box's live slot and from the current market listing.

## What Suppliers See In Practice

When a player or inserter delivers the requested item into an active trade box:

1. The mod attributes the delivery to a supplier.
2. It checks whether the buyer can afford the full delivery.
3. It transfers gold from the buyer to the supplier.
4. It records trade statistics and last-trade information.
5. If this is the first successful fill for that order, the order creator is notified and the supplier name is included.

Cross-force trading is supported. Orders can be supplied by players from other teams, and settlements move money between force wallets.

## Manual Deliveries

Manual deliveries include:

- Dropping items directly into the trade box.
- Fast-transferring items into the trade box.

If the delivery can be matched to the player who inserted the items, that player gets paid immediately.

## Automated Deliveries

Automated deliveries are built around nearby inserters feeding the box.

- The mod tracks inserters around the box.
- Each inserter must have a minimum acceptable unit price configured before it will auto-sell.
- It tries to identify which inserter supplied the incoming stack.
- The inserter owner receives the payout when the delivery settles.
- The inserter can also accumulate lifetime payout stats.

### Inserter Supplier Floor Price

Inserter minimum acceptable price is the supplier-side anti-tamper guard:

- If an order price is below the inserter minimum, the inserter is script-disabled for that order.
- The inserter can still finish an already in-flight stack if that stack was locked at a valid pickup price.
- Clearing the inserter minimum disables auto-selling for that inserter until a minimum is set again.

## Affordability Protection

The mod tries to stop automated over-delivery before it happens:

- Nearby inserters are budget-limited when an order is active.
- If the buyer's force wallet cannot afford the held stack, the inserter can be disabled by script.
- If the buyer cannot afford a delivery that still arrives, the items are refunded instead of being silently consumed.

## Price Locking During Delivery

To prevent buyer-side mid-delivery price tampering:

- Inserter deliveries lock unit price from the pickup/in-flight observation, not from the later order edit value.
- Settlement for that delivery uses the locked unit price.
- Order edits still apply to future deliveries.

## Refund Behavior

When settlement fails, the mod does not keep the items without paying:

- Manual deliveries are returned to the player when possible.
- Inserter deliveries are returned toward the source inventory when possible.
- If the source cannot be restored cleanly, the items are spilled into the world.

## Trade Box Panel Information

The side panel shows:

- Suggested price for the selected item.
- Current order status.
- Number of matching items stored in the box.
- Last trade time.
- Lifetime traded value for the order.

## Map Tags

Active orders can appear as chart tags on the map:

- The tag shows the requested item and the unit price.
- Only active orders get tags.
- Paused or cancelled orders do not stay tagged.
- Chart-tag visibility is controlled by a runtime-global setting.

[Back to Guide Contents](README.md)
