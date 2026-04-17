# Factorio Trade Mode

Trade-focused multiplayer economy for Factorio 2.0 with:

- Trade boxes that settle buy orders automatically
- Global contracts with assign/unassign and creator-authorized payout
- UBI-style money injection tied to recent raw ore throughput
- Admin observability commands for money flow, UBI, orders, and contracts
- Inserter lifetime payout tracking with player-facing stats

## Commands

- `/trade_status`
- `/trade_money_last_minute`
- `/trade_ubi_last_minute`
- `/trade_orders`
- `/trade_contracts`

## Test and Build

- Install the Node-side tooling:
  - `npm install`
- Build the mod into the local Factorio portable install:
  - `npm run build:mod`
- Run the Lua validator plus the deterministic Factorio scenario suite:
  - `npm test`
- Run only the headless Factorio scenario suite:
  - `npm run test:factorio`

`npm test` expects a portable Factorio install under `factorio-game/`, builds the mod into `factorio-game/mods`, converts the deterministic scenario into a save with `--scenario2map`, then runs that save with `--load-game --until-tick`. The structured scenario report is emitted to stdout, which makes it safe to run headlessly without GUI prompts.
