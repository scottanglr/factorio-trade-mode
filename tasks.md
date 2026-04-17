# Factorio Trade Mode — Deterministic Build Tasks

Status key:
- [ ] Not started
- [\] Started, not completed, with a progress comment
- [:tick:] Completed

## A) Mandatory Factorio API Research Gate (before any Factorio-connected task)
- [:tick:] For every task touching Factorio APIs/events/entities/GUI, read relevant docs first and capture findings in task notes.
  - [:tick:] Primary API docs: https://lua-api.factorio.com/latest/
  - [:tick:] Modding concepts/tutorial reference: https://wiki.factorio.com/Tutorial:Modding_tutorial
  - [:tick:] Record exact API objects/events used (e.g., LuaEntity, LuaPlayer, on_gui_click, on_built_entity).
  - [:tick:] Confirm behavior assumptions with doc citations before coding adapters/UI handlers.

## 0) Project Guardrails
- [:tick:] Define module boundaries for pure economy logic vs Factorio adapters.
  - [:tick:] Write explicit rule: no `game`, `script`, `defines`, or entity API access inside pure modules.
  - [:tick:] Define persisted state schema and version tag.
- [:tick:] Create deterministic test harness entry points.
  - [:tick:] Pure Lua unit test runner command documented.
  - [:tick:] Integration scenario runner command documented.
- [:tick:] Add coding guideline note: avoid impossible-state defensive branches unless supported by reproducible scenario.

## 1) Economy Ledger (Pure Lua)
- [:tick:] Implement ledger primitives.
  - [:tick:] create_account(player_id)
  - [:tick:] get_balance(player_id)
  - [:tick:] credit(player_id, amount, reason)
  - [:tick:] debit(player_id, amount, reason)
  - [:tick:] transfer(from_player_id, to_player_id, amount, reason)
- [:tick:] Enforce invariants.
  - [:tick:] Integer-only balances.
  - [:tick:] No negative transfer amounts.
  - [:tick:] Debit fails when funds insufficient.
- [:tick:] Binary tests.
  - [:tick:] Transfer succeeds iff sender balance >= amount.
  - [:tick:] Failed debit leaves both balances unchanged.

## 2) Suggested Pricing Module (Pure Lua)
- [:tick:] Load suggested prices from configured source.
  - [:tick:] Lookup by item prototype name.
  - [:tick:] Return deterministic default/error for unknown items.
- [:tick:] Binary tests.
  - [:tick:] Known item returns configured price.
  - [:tick:] Unknown item behavior matches documented rule.

## 3) Buy Order Domain (Pure Lua)
- [:tick:] Implement buy order lifecycle.
  - [:tick:] Create order (box_id, buyer_id, item, unit_price).
  - [:tick:] Update order item/price.
  - [:tick:] Cancel order.
- [:tick:] Implement settlement rule.
  - [:tick:] settle_insert(order_id, recipient_id, quantity, buyer_balance).
  - [:tick:] Compute total = unit_price * quantity.
  - [:tick:] Reject settlement if buyer cannot afford total.
- [:tick:] Binary tests.
  - [:tick:] Settlement succeeds and transfers funds when affordable.
  - [:tick:] Settlement fails and records no transfer when unaffordable.
  - [:tick:] Zero/negative quantity rejected.

## 4) Factorio Adapter for Box Trading
- [:tick:] API research complete for this section (objects/events/GUI APIs documented with links).
- [:tick:] Choose initial box implementation path.
  - [:tick:] Existing chest + GUI extension **or** custom box entity (document choice + rationale).
- [:tick:] Implement adapter for insertion events.
  - [:tick:] Resolve buyer from box-configured order.
  - [:tick:] Resolve recipient from manual insert player.
  - [:tick:] Resolve recipient from inserter owner for automated insert.
- [:tick:] Wire adapter to pure settlement module.
  - [:tick:] Do not move item across when settlement fails.
- [:tick:] Binary scenarios.
  - [:tick:] Manual insert attributed to inserting player.
  - [:tick:] Inserter insert attributed to inserter owner.
  - [:tick:] Insufficient funds blocks transaction and inventory movement.

## 5) Buy Order GUI
- [:tick:] API research complete for this section (objects/events/GUI APIs documented with links).
- [:tick:] Add GUI for configuring order item + unit price.
  - [:tick:] Show suggested price during configuration.
  - [:tick:] Confirm action writes deterministic state.
- [:tick:] Add global view for active buy orders.
  - [:tick:] Supports filtering/sorting deterministically (stable ordering).
- [:tick:] Binary checks.
  - [:tick:] Saved order persists across reload.
  - [:tick:] Displayed active orders count equals domain store count.

## 6) Contracts Domain (Pure Lua)
- [:tick:] Implement contract lifecycle.
  - [:tick:] Create contract (creator_id, title, description, amount).
  - [:tick:] Assign self / unassign self.
  - [:tick:] Creator payout to currently assigned player.
- [:tick:] Authorization rules.
  - [:tick:] Only creator can payout.
  - [:tick:] Payout only if assignee exists.
  - [:tick:] Payout fails when creator lacks funds.
- [:tick:] Binary tests.
  - [:tick:] Unauthorized payout attempts fail.
  - [:tick:] Successful payout debits creator and credits assignee atomically.

## 7) Contracts GUI (Global)
- [:tick:] API research complete for this section (objects/events/GUI APIs documented with links).
- [:tick:] Implement global contracts panel.
  - [:tick:] Create contract form.
  - [:tick:] Assign/unassign toggle per player.
  - [:tick:] Creator payout action button.
- [:tick:] Binary scenarios.
  - [:tick:] Player can assign and unassign with one click each.
  - [:tick:] Payout button visible/enabled only for creator when valid.

## 7.5) UI/UX Definition Tasks (Feature-by-Feature)
- [:tick:] Buy-order box panel mock/spec.
  - [:tick:] Header, item picker, unit price field, suggested price quick-fill, status badge, save/cancel.
  - [:tick:] Deterministic validation/error messages for invalid item/price.
- [:tick:] Global buy-order list mock/spec.
  - [:tick:] Columns: item, unit price, buyer, location, last trade time.
  - [:tick:] Stable default sort and explicit filter behavior.
- [:tick:] Contracts panel mock/spec.
  - [:tick:] List/detail split with assign/unassign and creator payout controls.
  - [:tick:] Visibility/enablement rules documented as binary conditions.
- [:tick:] Economy stats panel mock/spec.
  - [:tick:] gold_per_second, ore/minute, last-minute UBI, last-minute traded value.
- [:tick:] Admin command response format spec.
  - [:tick:] Structured text block with metric, window, and deterministic aggregation note.

## 8) UBI Engine (Pure Lua + Adapter)
- [:tick:] Implement formula engine in pure module.
  - [:tick:] gold_per_second = base_income + income_scale * (recent_raw_ore_per_minute ^ income_exponent)
  - [:tick:] Deterministic rounding from formula output to credited integer amount.
- [:tick:] Implement ore-rate adapter.
  - [:tick:] Source production deltas for iron/copper/coal/stone/uranium.
  - [:tick:] Compute recent_raw_ore_per_minute in deterministic window.
- [:tick:] Binary tests.
  - [:tick:] Higher ore throughput produces greater or equal UBI payout.
  - [:tick:] With fixed throughput and config, payouts are repeatable tick-to-tick.

## 9) Admin Slash Commands
- [:tick:] API research complete for this section (objects/events/GUI APIs documented with links).
- [:tick:] Implement admin-only command set.
  - [:tick:] /trade_status
  - [:tick:] /trade_money_last_minute
  - [:tick:] /trade_ubi_last_minute
  - [:tick:] /trade_orders
  - [:tick:] /trade_contracts
- [:tick:] Binary checks.
  - [:tick:] Non-admin invocation rejected with explicit message.
  - [:tick:] Reported “money traded last minute” equals metrics window sum.
  - [:tick:] Reported “UBI last minute” equals credited UBI window sum.

## 10) Metrics & Observability (Pure Lua)
- [:tick:] Add rolling-window metrics store.
  - [:tick:] Traded value per second buckets (last 60s).
  - [:tick:] UBI credited per second buckets (last 60s).
  - [:tick:] Active orders/contracts snapshot counters.
- [:tick:] Binary tests.
  - [:tick:] Window sum drops expired buckets deterministically.
  - [:tick:] Snapshot counts reflect current domain state.

## 10.5) Inserter Lifetime Payout Tracking
- [:tick:] Implement inserter payout accumulator.
  - [:tick:] Key by stable inserter identity and owner attribution.
  - [:tick:] Increment only on successful automated trade settlement.
- [:tick:] Add query/report support.
  - [:tick:] Inserter tooltip/panel shows lifetime payout.
  - [:tick:] Admin report includes top inserter payout totals.
- [:tick:] Binary tests.
  - [:tick:] Two successful payouts of X and Y produce total X+Y.
  - [:tick:] Failed settlements do not change inserter lifetime payout.

## 11) Optional: Map Discoverability
- [:tick:] Add optional map markers/icons for active buy-order boxes.
  - [:tick:] Config toggle enable/disable.
- [:tick:] Binary checks.
  - [:tick:] Marker appears for configured buy-order box.
  - [:tick:] Marker removed on order cancel or box removal.

## 12) End-to-End Deterministic Scenarios
- [:tick:] Scenario A: Two-player manual box trade happy path.
- [:tick:] Scenario B: Inserter-owned automation trade attribution.
- [:tick:] Scenario C: Insufficient-funds rejection with no item movement.
- [:tick:] Scenario D: Contract assign/unassign/payout flow.
- [:tick:] Scenario E: UBI scaling under low vs high ore throughput.
- [:tick:] For each scenario:
  - [:tick:] Scripted setup steps.
  - [:tick:] Expected state deltas.
  - [:tick:] Single binary pass condition.

## 13) Factorio Test Suite Integration (If Available)
- [:tick:] Detect and document available Factorio headless test command(s).
- [:tick:] Add CI-friendly command wrapper for deterministic scenarios.
- [:tick:] Record known environment limitations if Factorio runtime is unavailable.

## 14) Release Readiness
- [:tick:] Keep `control.lua` thin: event wiring + adapter calls only.
- [:tick:] Verify no Factorio API usage leaked into pure modules.
- [:tick:] Produce concise README section for admins and players.
- [:tick:] Changelog entry for first playable trade economy slice.

## Progress Tracker (Update During Implementation)
- [:tick:] Slice 1 target: Ledger + pricing + tests.
- [:tick:] Slice 2 target: Buy order domain + basic box adapter + tests.
- [:tick:] Slice 3 target: Contracts domain + GUI + tests.
- [:tick:] Slice 4 target: UBI + metrics + admin commands + tests.
- [:tick:] Slice 4.5 target: inserter lifetime payout tracking + UI/admin surfacing + tests.
- [:tick:] Slice 5 target: E2E scenarios + polish + release.

## Completion Note
- [:tick:] Deterministic buy-order adapter wiring, inserter ownership attribution, and end-to-end fixture coverage are all finished and verified by the green scenario suite.
