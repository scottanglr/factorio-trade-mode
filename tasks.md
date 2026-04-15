# Factorio Trade Mode — Deterministic Build Tasks

Status key:
- [ ] Not started
- [\] Started, not completed, with a progress comment
- [:tick:] Completed

## A) Mandatory Factorio API Research Gate (before any Factorio-connected task)
- [ ] For every task touching Factorio APIs/events/entities/GUI, read relevant docs first and capture findings in task notes.
  - [ ] Primary API docs: https://lua-api.factorio.com/latest/
  - [ ] Modding concepts/tutorial reference: https://wiki.factorio.com/Tutorial:Modding_tutorial
  - [ ] Record exact API objects/events used (e.g., LuaEntity, LuaPlayer, on_gui_click, on_built_entity).
  - [ ] Confirm behavior assumptions with doc citations before coding adapters/UI handlers.

## 0) Project Guardrails
- [ ] Define module boundaries for pure economy logic vs Factorio adapters.
  - [ ] Write explicit rule: no `game`, `script`, `defines`, or entity API access inside pure modules.
  - [ ] Define persisted state schema and version tag.
- [ ] Create deterministic test harness entry points.
  - [ ] Pure Lua unit test runner command documented.
  - [ ] Integration scenario runner command documented.
- [ ] Add coding guideline note: avoid impossible-state defensive branches unless supported by reproducible scenario.

## 1) Economy Ledger (Pure Lua)
- [ ] Implement ledger primitives.
  - [ ] create_account(player_id)
  - [ ] get_balance(player_id)
  - [ ] credit(player_id, amount, reason)
  - [ ] debit(player_id, amount, reason)
  - [ ] transfer(from_player_id, to_player_id, amount, reason)
- [ ] Enforce invariants.
  - [ ] Integer-only balances.
  - [ ] No negative transfer amounts.
  - [ ] Debit fails when funds insufficient.
- [ ] Binary tests.
  - [ ] Transfer succeeds iff sender balance >= amount.
  - [ ] Failed debit leaves both balances unchanged.

## 2) Suggested Pricing Module (Pure Lua)
- [ ] Load suggested prices from configured source.
  - [ ] Lookup by item prototype name.
  - [ ] Return deterministic default/error for unknown items.
- [ ] Binary tests.
  - [ ] Known item returns configured price.
  - [ ] Unknown item behavior matches documented rule.

## 3) Buy Order Domain (Pure Lua)
- [ ] Implement buy order lifecycle.
  - [ ] Create order (box_id, buyer_id, item, unit_price).
  - [ ] Update order item/price.
  - [ ] Cancel order.
- [ ] Implement settlement rule.
  - [ ] settle_insert(order_id, recipient_id, quantity, buyer_balance).
  - [ ] Compute total = unit_price * quantity.
  - [ ] Reject settlement if buyer cannot afford total.
- [ ] Binary tests.
  - [ ] Settlement succeeds and transfers funds when affordable.
  - [ ] Settlement fails and records no transfer when unaffordable.
  - [ ] Zero/negative quantity rejected.

## 4) Factorio Adapter for Box Trading
- [ ] API research complete for this section (objects/events/GUI APIs documented with links).
- [ ] Choose initial box implementation path.
  - [ ] Existing chest + GUI extension **or** custom box entity (document choice + rationale).
- [ ] Implement adapter for insertion events.
  - [ ] Resolve buyer from box-configured order.
  - [ ] Resolve recipient from manual insert player.
  - [ ] Resolve recipient from inserter owner for automated insert.
- [ ] Wire adapter to pure settlement module.
  - [ ] Do not move item across when settlement fails.
- [ ] Binary scenarios.
  - [ ] Manual insert attributed to inserting player.
  - [ ] Inserter insert attributed to inserter owner.
  - [ ] Insufficient funds blocks transaction and inventory movement.

## 5) Buy Order GUI
- [ ] API research complete for this section (objects/events/GUI APIs documented with links).
- [ ] Add GUI for configuring order item + unit price.
  - [ ] Show suggested price during configuration.
  - [ ] Confirm action writes deterministic state.
- [ ] Add global view for active buy orders.
  - [ ] Supports filtering/sorting deterministically (stable ordering).
- [ ] Binary checks.
  - [ ] Saved order persists across reload.
  - [ ] Displayed active orders count equals domain store count.

## 6) Contracts Domain (Pure Lua)
- [ ] Implement contract lifecycle.
  - [ ] Create contract (creator_id, title, description, amount).
  - [ ] Assign self / unassign self.
  - [ ] Creator payout to currently assigned player.
- [ ] Authorization rules.
  - [ ] Only creator can payout.
  - [ ] Payout only if assignee exists.
  - [ ] Payout fails when creator lacks funds.
- [ ] Binary tests.
  - [ ] Unauthorized payout attempts fail.
  - [ ] Successful payout debits creator and credits assignee atomically.

## 7) Contracts GUI (Global)
- [ ] API research complete for this section (objects/events/GUI APIs documented with links).
- [ ] Implement global contracts panel.
  - [ ] Create contract form.
  - [ ] Assign/unassign toggle per player.
  - [ ] Creator payout action button.
- [ ] Binary scenarios.
  - [ ] Player can assign and unassign with one click each.
  - [ ] Payout button visible/enabled only for creator when valid.

## 7.5) UI/UX Definition Tasks (Feature-by-Feature)
- [ ] Buy-order box panel mock/spec.
  - [ ] Header, item picker, unit price field, suggested price quick-fill, status badge, save/cancel.
  - [ ] Deterministic validation/error messages for invalid item/price.
- [ ] Global buy-order list mock/spec.
  - [ ] Columns: item, unit price, buyer, location, last trade time.
  - [ ] Stable default sort and explicit filter behavior.
- [ ] Contracts panel mock/spec.
  - [ ] List/detail split with assign/unassign and creator payout controls.
  - [ ] Visibility/enablement rules documented as binary conditions.
- [ ] Economy stats panel mock/spec.
  - [ ] gold_per_second, ore/minute, last-minute UBI, last-minute traded value.
- [ ] Admin command response format spec.
  - [ ] Structured text block with metric, window, and deterministic aggregation note.

## 8) UBI Engine (Pure Lua + Adapter)
- [ ] Implement formula engine in pure module.
  - [ ] gold_per_second = base_income + income_scale * (recent_raw_ore_per_minute ^ income_exponent)
  - [ ] Deterministic rounding from formula output to credited integer amount.
- [ ] Implement ore-rate adapter.
  - [ ] Source production deltas for iron/copper/coal/stone/uranium.
  - [ ] Compute recent_raw_ore_per_minute in deterministic window.
- [ ] Binary tests.
  - [ ] Higher ore throughput produces greater or equal UBI payout.
  - [ ] With fixed throughput and config, payouts are repeatable tick-to-tick.

## 9) Admin Slash Commands
- [ ] API research complete for this section (objects/events/GUI APIs documented with links).
- [ ] Implement admin-only command set.
  - [ ] /trade_status
  - [ ] /trade_money_last_minute
  - [ ] /trade_ubi_last_minute
  - [ ] /trade_orders
  - [ ] /trade_contracts
- [ ] Binary checks.
  - [ ] Non-admin invocation rejected with explicit message.
  - [ ] Reported “money traded last minute” equals metrics window sum.
  - [ ] Reported “UBI last minute” equals credited UBI window sum.

## 10) Metrics & Observability (Pure Lua)
- [ ] Add rolling-window metrics store.
  - [ ] Traded value per second buckets (last 60s).
  - [ ] UBI credited per second buckets (last 60s).
  - [ ] Active orders/contracts snapshot counters.
- [ ] Binary tests.
  - [ ] Window sum drops expired buckets deterministically.
  - [ ] Snapshot counts reflect current domain state.

## 10.5) Inserter Lifetime Payout Tracking
- [ ] Implement inserter payout accumulator.
  - [ ] Key by stable inserter identity and owner attribution.
  - [ ] Increment only on successful automated trade settlement.
- [ ] Add query/report support.
  - [ ] Inserter tooltip/panel shows lifetime payout.
  - [ ] Admin report includes top inserter payout totals.
- [ ] Binary tests.
  - [ ] Two successful payouts of X and Y produce total X+Y.
  - [ ] Failed settlements do not change inserter lifetime payout.

## 11) Optional: Map Discoverability
- [ ] Add optional map markers/icons for active buy-order boxes.
  - [ ] Config toggle enable/disable.
- [ ] Binary checks.
  - [ ] Marker appears for configured buy-order box.
  - [ ] Marker removed on order cancel or box removal.

## 12) End-to-End Deterministic Scenarios
- [ ] Scenario A: Two-player manual box trade happy path.
- [ ] Scenario B: Inserter-owned automation trade attribution.
- [ ] Scenario C: Insufficient-funds rejection with no item movement.
- [ ] Scenario D: Contract assign/unassign/payout flow.
- [ ] Scenario E: UBI scaling under low vs high ore throughput.
- [ ] For each scenario:
  - [ ] Scripted setup steps.
  - [ ] Expected state deltas.
  - [ ] Single binary pass condition.

## 13) Factorio Test Suite Integration (If Available)
- [ ] Detect and document available Factorio headless test command(s).
- [ ] Add CI-friendly command wrapper for deterministic scenarios.
- [ ] Record known environment limitations if Factorio runtime is unavailable.

## 14) Release Readiness
- [ ] Keep `control.lua` thin: event wiring + adapter calls only.
- [ ] Verify no Factorio API usage leaked into pure modules.
- [ ] Produce concise README section for admins and players.
- [ ] Changelog entry for first playable trade economy slice.

## Progress Tracker (Update During Implementation)
- [ ] Slice 1 target: Ledger + pricing + tests.
- [ ] Slice 2 target: Buy order domain + basic box adapter + tests.
- [ ] Slice 3 target: Contracts domain + GUI + tests.
- [ ] Slice 4 target: UBI + metrics + admin commands + tests.
- [ ] Slice 4.5 target: inserter lifetime payout tracking + UI/admin surfacing + tests.
- [ ] Slice 5 target: E2E scenarios + polish + release.

## Example In-Progress Entry Format
- [\] Buy order adapter wiring in `control.lua`.
  - Progress: insertion event identified; recipient attribution implemented for manual insert; inserter ownership attribution pending deterministic test fixture.
