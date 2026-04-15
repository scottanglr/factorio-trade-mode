# Factorio Trade Mode — Build Prompt

Use this prompt as the implementation contract for the mod.

## Mission
Build a trade-focused multiplayer mode where players specialize in different roles but remain economically interdependent through buy orders, contracts, and an activity-scaled money supply.

## Non-Negotiable Engineering Constraints
- Economy and rules logic must live in **pure Lua modules** (no Factorio API calls in those modules).
- `control.lua` must remain thin and orchestration-only (event wiring, state persistence bridge, GUI plumbing).
- Build in **small deterministic slices** with explicit binary pass/fail checks.
- Every feature must define a **reproducible test scenario** and a **binary pass condition**.
- Avoid “looks right” checks.
- Minimize mocking; only mock what cannot be reasonably integrated.
- Avoid over-defensive handling of impossible states.
- For any task that integrates with Factorio runtime/events/entities/GUI, first gather the relevant API knowledge from the official docs before coding. Primary reference: https://lua-api.factorio.com/latest/ (and concept docs: https://wiki.factorio.com/Tutorial:Modding_tutorial).

## Core Feature Scope

### 1) Buy Orders on Boxes
Players can create buy orders tied to a box (new custom box entity or existing boxes with added GUI, whichever is easiest to ship first).

Rules:
- A buy order targets exactly one item prototype.
- Buyer sets desired item and unit price.
- Suggested price is available from preconfigured suggested price table.
- When an item is inserted, trade resolves automatically at configured price.
- **No escrow**.
- If buyer cannot afford total transaction, item must not be moved across.
- Recipient attribution:
  - Manual insertion: inserter player is recipient.
  - Inserter machine insertion: owner of that inserter is recipient.
  - Do not track item journey, only insertion actor/owner.

### 2) Contracts
Global GUI supports contracts with these actions:
- Creator creates a contract.
- Other players assign/unassign themselves.
- Creator can payout assigned player when satisfied.

### 3) UBI-Style Money Injection
Money enters economy from industrial activity:

`gold_per_second = base_income + income_scale * (recent_raw_ore_per_minute ^ income_exponent)`

`recent_raw_ore_per_minute` should be derived from production stats for:
- iron ore
- copper ore
- coal
- stone
- uranium ore

Goal: money supply scales with resource throughput so stable box pricing requires less manual reconfiguration.

### 4) Admin Observability
Add slash commands for admin visibility into mod economics, e.g.:
- money traded in last minute
- UBI distributed in last minute
- active buy orders
- contract counts/status
- top recipients/payers (optional enhancement)

### 5) Market Visibility UX
Provide discoverability for buy orders:
- GUI list of current buy orders (minimum)
- Optional map icon markers for boxes


## UI/UX Specification by Feature

### Buy Orders on Boxes UI
- **Box configuration panel** (opened from box interaction):
  - Header: `Buy Order` + box identifier/location hint.
  - Item picker control for requested item.
  - Unit price input with integer validation.
  - Suggested price row showing configured value and quick-fill button.
  - Status badge: `Active` / `Paused` / `Invalid`.
  - Save + Cancel buttons.
- **Global market panel**:
  - Table columns: Item, Unit Price, Buyer, Box Location, Last Trade Time.
  - Deterministic sort (default: Item asc, Price asc, Box id asc).
  - Filters: item text filter, online-only buyers toggle (optional).

### Contracts UI
- **Global contracts window** with two panes:
  - Left pane: contract list (title, creator, payout amount, assignee, status).
  - Right pane: selected contract details and action buttons.
- Actions:
  - `Create Contract` form (title, description, amount).
  - `Assign to Me` / `Unassign` single-click toggle for non-creators.
  - `Pay Assignee` button only visible/enabled for creator when assignee exists.

### UBI / Economy Visibility UI
- **Economy stats panel** (admin + optional player read-only):
  - Current `gold_per_second` value.
  - Recent raw ore per minute value and ore-component breakdown.
  - Last-minute UBI total and last-minute traded total.

### Inserter Lifetime Payout UI
- Inserter tooltip or small side panel should display:
  - `Lifetime Trade Payout` (total money credited through this inserter’s deliveries).
  - `Last Recipient` and `Last Trade Timestamp` (optional but useful).
- Optional map overlay label/icon for top-earning inserters.

### Admin Commands Output UX
- Slash command responses should use structured, compact text blocks:
  - headline metric value
  - measurement window
  - deterministic source notes (e.g., bucketed 60s sum)


### 6) Inserter Lifetime Payout Tracking
Track cumulative payout volume attributed to each inserter owner/source inserter identity.
- Update cumulative totals when automated inserter-driven trades settle successfully.
- Expose these totals in UI and admin reporting.
- Keep attribution deterministic and ownership-resolution based on current Factorio ownership metadata available at event time.

## Architecture Guidance

### Pure Lua Core Modules (No Factorio API)
Suggested module boundaries:
- `economy/ledger.lua` — balances, debits, credits, transfers, invariants.
- `economy/pricing.lua` — suggested price lookup and validation.
- `economy/orders.lua` — buy order lifecycle and trade settlement rules.
- `economy/contracts.lua` — contract lifecycle and payout authorization.
- `economy/ubi.lua` — income formula and rolling ore-rate calculations.
- `economy/metrics.lua` — counters/windows for observability.
- `economy/inserter_stats.lua` — lifetime payout aggregation and query helpers.

### Adapters / Integration Layer
- `control.lua` only for event handlers and calling core modules.
- Factorio-specific identity resolution (player/inserter owner) should happen in adapters before invoking core rules.
- Persisted state shape should be explicit and versioned.

## Deterministic Testing Strategy

Use layered tests:
1. **Pure Lua unit tests** for all economy modules.
2. **Integration tests** for adapter behavior (ownership attribution, event-to-core mapping).
3. **Scenario scripts** for end-to-end deterministic replay.

If Factorio test suites are available in this repo/environment, wire and run them.

### Required Binary Pass Conditions (examples)
- Trade succeeds iff buyer balance >= price * quantity.
- Trade fails without inventory transfer iff insufficient funds.
- Inserter ownership maps payout recipient correctly.
- Contract payout only succeeds for creator → assigned player.
- UBI payout increases with higher ore throughput, given fixed config.
- Admin command “money traded last minute” equals sum of settled trades in window.
- Inserter lifetime payout strictly increases by settled automated trade payout amount.

## Data & State Expectations
- Keep event log style counters for minute-window metrics.
- Prefer append-only trade records with bounded rolling windows for performance.
- All monetary values use integer units (no floats in balances).
- Formula intermediate precision may use float, but credited payouts must round deterministically.

## Delivery Requirements
- Ship in deterministic vertical slices (one shippable capability at a time).
- Each slice must include:
  - implementation
  - tests
  - explicit pass condition
  - short scenario script
- Document decisions when choosing “new box” vs “existing box GUI extension.”

## Definition of Done
- Multiplayer flows for buy orders, contracts, and UBI function deterministically.
- Admin observability commands report accurate minute-window metrics.
- Core economy modules are pure and independently testable.
- `control.lua` remains thin and integration-focused.
