[Back to Guide Contents](README.md)

# Economy And UBI

The mod uses a shared gold economy. Money is not mined or crafted directly. Instead, it flows between players through trade and contracts, and new money enters the game through a UBI system driven by raw ore production.

## Gold Flow

Gold moves in three main ways:

- `Trade box settlements` move gold from the buyer to the supplier.
- `Contract payouts` move gold from the contract creator to the assignee.
- `UBI` injects new gold into connected players' balances.

## How UBI Works

UBI is based on recent raw ore throughput over a rolling 60-second window.

The tracked resources are:

- `Iron ore`
- `Copper ore`
- `Coal`
- `Stone`
- `Uranium ore`

Important behavior:

- There is always a base UBI trickle.
- More recent raw ore production increases the payout rate.
- Only currently connected players receive the split.
- Fractional gold is banked until it becomes spendable.
- Remainder distribution rotates so small leftovers are shared fairly over time.

## What The Economy Tab Shows

The `Economy` tab gives a player-facing snapshot of the current economy:

- `UBI rate`
- `Ore throughput`
- `Last-minute UBI`
- `Last-minute trade`
- Per-resource ore throughput
- `Top balances`
- `Top earners`
- `Top spenders`

The last-minute views use a rolling 60-second window.

## Reading The Balance And Leaderboards

- `Top balances` shows the richest players by current gold.
- `Top earners` shows who received the most gold recently.
- `Top spenders` shows who spent the most on buy orders recently.

These views are useful for seeing whether the market is active, who is consuming the most, and who is supplying the most.

## What Happens If A Player Runs Out Of Gold

- Trade box settlements fail if the buyer cannot afford the delivery.
- Contract payouts fail if the creator cannot cover the reward.
- Failed trade deliveries are refunded rather than silently accepted.

## Practical Multiplayer Impact

The UBI system means the economy does not depend only on a starting purse. Even if trading slows down, active mining keeps injecting fresh money into the game and helps new or poorer players re-enter the market.

[Back to Guide Contents](README.md)
