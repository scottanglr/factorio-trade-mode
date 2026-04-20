[Back to Guide Contents](README.md)

# Overview

Factorio Trade Mode adds a lightweight multiplayer economy on top of normal Factorio production. Instead of only moving items between your own belts, chests, and trains, players can publish buy orders, fulfill each other's requests, create contracts, and earn gold from both trade and system-wide UBI.

## Core Loop

1. Craft and place a `Trade Box`.
2. Set a buy order for an item and a unit price.
3. Other players, or their inserter-fed delivery setups, deliver into the box.
4. The mod transfers gold from the buyer wallet to the supplier wallet automatically.
5. Mining activity across the game keeps new gold entering the economy through UBI.

## Main Feature Areas

| Feature | Where It Lives | What It Does |
| --- | --- | --- |
| Trade boxes | Relative panel when you open a trade box | Lets you create, pause, resume, or delete one buy order per box |
| Market browser | Global `Trade Market` window, `Market` tab | Shows all current non-cancelled buy orders with filtering |
| Contracts | Global `Trade Market` window, `Contracts` tab | Lets players post jobs with a reward, assign themselves, and get paid |
| Economy view | Global `Trade Market` window, `Economy` tab | Shows UBI, throughput, balances, earners, and spenders |
| Admin diagnostics | Global `Trade Market` window, `Admin` tab | Gives admins live reports and reminders about shared settings |
| Inserter stats | Relative panel when you select an inserter | Shows payout stats and lets suppliers set inserter minimum acceptable price |
| Chart tags | Map view | Shows active trade boxes as map tags when enabled |

## What "Gold" Means In This Mod

- Gold is a virtual balance tracked by the mod.
- It is not a physical item in your inventory.
- Team play uses force-shared wallets (everyone on one force shares one wallet).
- Trade settlements and contract payouts both use these wallet balances.
- UBI credits the same balance pool.

## Who Uses What

- Buyers mostly work with `Trade Boxes`, the `Market` tab, and the `Economy` tab.
- Suppliers mostly interact with active trade boxes and inserter-fed delivery setups.
- Contract creators and freelancers use the `Contracts` tab.
- Server hosts and moderators use the `Admin` tab and slash commands.

[Back to Guide Contents](README.md)
