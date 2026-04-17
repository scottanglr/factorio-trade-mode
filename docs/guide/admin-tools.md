[Back to Guide Contents](README.md)

# Admin Tools

The mod includes an admin-facing diagnostics layer for checking market health, economy activity, and live gameplay state.

## Admin Tab

Admins get an extra `Admin` tab inside the main `Trade Market` window.

It contains:

- A reminder that chart tags are force-wide, not per-player.
- A live `Economy status` report.
- An `Order snapshot`.
- A `Contract snapshot`.

This is meant to be the at-a-glance control room for the mod.

## Slash Commands

These commands require admin privileges:

- `/trade_status`
- `/trade_money_last_minute`
- `/trade_ubi_last_minute`
- `/trade_orders`
- `/trade_contracts`

## What Each Command Is For

- `/trade_status` shows the broadest summary, including UBI, throughput, trade volume, active counts, top payers, top recipients, and top inserter payouts.
- `/trade_money_last_minute` shows recent trade volume only.
- `/trade_ubi_last_minute` shows recent UBI payout only.
- `/trade_orders` shows the current live order snapshot.
- `/trade_contracts` shows the current contract snapshot.

## When To Use The Tab Versus Commands

- Use the `Admin` tab when you want a live GUI view while playing.
- Use the slash commands when you want a quick text report in chat, logs, or remote administration workflows.

## What Admins Can Learn Quickly

- Whether the economy is active or stalled.
- Whether players are actually using trade boxes.
- Who is spending the most.
- Who is earning the most.
- Which inserters are producing the highest lifetime payouts.
- Whether contracts are piling up or completing normally.

[Back to Guide Contents](README.md)
