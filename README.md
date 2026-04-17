# Factorio Trade Mode

Trade-focused multiplayer economy for Factorio 2.0 with:

- Trade boxes that settle buy orders automatically
- Global contracts with assign/unassign and creator-authorized payout
- UBI-style money injection tied to recent raw ore throughput
- Admin observability commands for money flow, UBI, orders, and contracts
- Inserter lifetime payout tracking with player-facing stats

## Install

### Easiest option: GitHub release

1. Download the latest release zip from the repository's [Releases](../../releases) page.
2. Put that zip into your Factorio `mods` folder.
3. Start Factorio and enable `Factorio Trade Mode` in the in-game Mods list if needed.

Common `mods` folder locations:

- Windows: `%AppData%\Factorio\mods`
- Factorio portable install: `<Factorio folder>\mods`

The release zip is built as a normal Factorio mod package, so you can leave it zipped.

### Optional: extracted install with one-click updating

If you want to use the included updater:

1. Extract the release zip into your Factorio `mods` folder.
2. Open the extracted mod folder.
3. Run [auto-update.bat](<C:\Users\scott\OneDrive\Documents\Factorio Mod\auto-update.bat:1>) whenever you want to pull the newest GitHub release into that folder.

This is meant for Windows players who prefer an unpacked mod folder instead of replacing zip files by hand.

## For Players

### What this mod adds

- `Trade Box`: a dedicated chest for buy orders and tracked deliveries.
- Global market panel for active buy orders.
- Global contracts panel for assign/unassign/payout flows.
- Economy panel showing trade and UBI activity.
- Optional chart tags for active trade boxes.

### Basic use

1. Craft and place a `Trade Box`.
2. Open it and set the requested item plus the price per unit.
3. Other players can deliver into that box manually or by inserter.
4. The configured buyer pays automatically when the delivery settles.

### Opening the main panel

- Keyboard shortcut: `Ctrl + T`
- Alternate shortcut: `Shift + T`
- Toolbar shortcut: `Trade Market`

### Admin commands

- `/trade_status`
- `/trade_money_last_minute`
- `/trade_ubi_last_minute`
- `/trade_orders`
- `/trade_contracts`

## Documentation

- [Feature Guide](docs/guide/README.md)
- [Architecture Notes](docs/architecture.md)
- [Factorio API Notes](docs/factorio-api-notes.md)
- [Test Scenarios](docs/test-scenarios.md)

## For Modders

- Install the Node-side tooling:
  - `npm install`
- Build the mod into the local Factorio portable install:
  - `npm run build:mod`
- Run the Lua validator plus the deterministic Factorio scenario suite:
  - `npm test`
- Run only the headless Factorio scenario suite:
  - `npm run test:factorio`

`npm test` expects a portable Factorio install under `factorio-game/`, builds the mod into `factorio-game/mods`, converts the deterministic scenario into a save with `--scenario2map`, then runs that save with `--load-game --until-tick`. The structured scenario report is emitted to stdout, which makes it safe to run headlessly without GUI prompts.
