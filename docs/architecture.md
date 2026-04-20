# Trade Mode Architecture

## Guardrails

- Pure modules live under `trade_mode/core/`.
- Pure modules must not reference `game`, `script`, `defines`, `storage`, `rendering`, `remote`, or any `Lua*` runtime object.
- Factorio-facing code lives under `trade_mode/runtime/`, `prototypes/`, `data.lua`, `settings.lua`, and `control.lua`.
- `control.lua` stays orchestration-only and delegates all behavior to runtime modules.
- Monetary values are integer units only.

## Persisted State Schema

All persisted state lives under `storage.trade_mode`.

```lua
storage.trade_mode = {
  version = 1,
  ledger = {
    balances = {},
    journal = {},
    next_entry_id = 1,
  },
  orders = {
    next_id = 1,
    by_id = {},
    by_box_id = {},
  },
  contracts = {
    next_id = 1,
    by_id = {},
  },
  metrics = {
    windows = {
      traded = {},
      ubi = {},
    },
    snapshots = {
      active_orders = 0,
      active_contracts = 0,
    },
  },
  ubi = {
    fractional_bank = 0,
    rotation_index = 1,
    samples = {},
  },
  inserter_stats = {
    by_id = {},
  },
  runtime = {
    players = {},
    trade_boxes = {},
    inserters = {},
    manual_insertions = {},
    market_tags = {},
  },
}
```

Order and contract records persist explicit wallet routing fields:

- `order.buyer_wallet_id` (defaults to buyer player id for legacy data).
- `order.last_trade_unit_price` for the unit price actually used on the most recent settlement (supports locked inserter settlement price).
- `contract.creator_wallet_id`.
- `contract.assignee_wallet_id` once assigned.

Tracked inserter runtime records also persist:

- `inserter.min_unit_price` (supplier floor price, required for automated selling).
- `inserter.pending_unit_price` (locked pickup price for in-flight settlement).

Wallet ids are either:

- `force:<force-name>` for team-shared force wallets.
- Numeric player ids as a compatibility fallback for synthetic/legacy contexts.

## Test Harness Entry Points

- Pure/unit runner: `npm run test:lua` statically validates the pure/runtime Lua modules, and `scenarios/trade-tests/control.lua` runs the pure Lua assertions inside Factorio on init.
- Integration runner: `npm run test:factorio` invokes `scripts/run-tests.mjs`, which builds the mod, converts `factorio-trade-mode/trade-tests` via `--scenario2map`, and replays it with `--load-game --until-tick`.
- End-to-end runner: scripted scenario cases in `scenarios/trade-tests/control.lua` create real entities, drive runtime APIs/events, and assert binary pass conditions from the structured stdout report.

## Coding Note

- Avoid impossible-state branches unless the state can be produced by a documented runtime path or a reproducible scenario.
