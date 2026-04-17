# Factorio API Research Notes

This document captures the official API/runtime references used for every Factorio-connected part of the mod before adapter code was written.

## Source References

- Runtime events: [Events](https://lua-api.factorio.com/latest/events.html)
- Runtime bootstrap and nth-tick handlers: [LuaBootstrap](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html)
- Entity APIs for inventories, inserters, ownership, and identity: [LuaEntity](https://lua-api.factorio.com/latest/classes/LuaEntity.html)
- Player GUI state: [LuaPlayer](https://lua-api.factorio.com/latest/classes/LuaPlayer.html)
- GUI construction: [LuaGuiElement](https://lua-api.factorio.com/latest/classes/LuaGuiElement.html)
- Commands: [LuaCommandProcessor](https://lua-api.factorio.com/latest/classes/LuaCommandProcessor.html)
- Production statistics: [LuaForce](https://lua-api.factorio.com/latest/classes/LuaForce.html) and [LuaFlowStatistics](https://lua-api.factorio.com/latest/classes/LuaFlowStatistics.html)
- Inventory mutation/filtering: [LuaInventory](https://lua-api.factorio.com/latest/classes/LuaInventory.html)
- Shortcut prototypes: [ShortcutPrototype](https://lua-api.factorio.com/latest/prototypes/ShortcutPrototype.html)
- Persistent storage guidance: [Storage](https://lua-api.factorio.com/latest/auxiliary/storage.html)
- Mod file layout guidance: [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- Modding concepts/tutorial baseline: [Factorio Wiki Modding Tutorial](https://wiki.factorio.com/Tutorial:Modding_tutorial)

## Runtime Hooks Used

### Core lifecycle and polling

- `script.on_init`, `script.on_load`, `script.on_configuration_changed`, `script.on_event`, and `script.on_nth_tick` come from `LuaBootstrap`.
- `on_nth_tick` is the documented way to run deterministic periodic reconciliation and metric sampling.

### Box/inserter/entity integration

- `on_built_entity` / `on_robot_built_entity` are used to register trade boxes and nearby inserters.
- `on_space_platform_built_entity` and `script_raised_revive` are also relevant in 2.0 because entities can be built by platforms or revived by other mods, not only by players and robots.
- `on_pre_player_mined_item`, `on_robot_pre_mined`, `on_space_platform_pre_mined`, and `script_raised_destroy` are used to tear down tracked entities cleanly across player, robot, platform, and scripted destruction paths.
- `LuaBootstrap::on_event(..., filters)` and `LuaBootstrap::set_event_filter()` support `name`/`type` event filters for built/mined/died entity events, so the runtime can subscribe only to `trade-box` and `inserter` entity changes instead of every entity event.
- `LuaEntity::get_inventory()` is used to access chest inventories.
- `LuaEntity::unit_number` is used as the stable save-lifetime identifier for tracked trade boxes and inserters.
- `LuaEntity::last_user` is used as the documented ownership hint for entity-with-owner objects, including buyer/inserter attribution fallbacks.
- `LuaEntity::drop_target`, `LuaEntity::pickup_target`, `LuaEntity::held_stack`, and `LuaEntity::active` are used for automated inserter attribution and affordability throttling.
- `LuaEntity::disabled_by_script` is the documented write path for enabling/disabling updatable entities in 2.0; the docs say writes to `LuaEntity::active` are deprecated and only proxy that script-disabled state.

### Manual insertion attribution

- `on_player_dropped_item_into_entity` is documented as firing when a player drops a single item into an entity.
- `on_player_fast_transferred` is documented as firing when a player fast-transfers something to or from an entity.
- `on_player_main_inventory_changed` is used as a reconciliation signal for player-driven transfers that do not expose precise quantity in their event payload.

Inference:
Factorio does not expose a single pre-insert chest event that gives both exact quantity and actor for every inventory movement path. The adapter therefore uses the documented player insertion events for explicit attribution first, then deterministic inventory reconciliation as fallback.

### GUI and UX

- `on_gui_click`, `on_gui_closed`, `on_gui_elem_changed`, `on_gui_text_changed`, `on_gui_opened`, and `on_lua_shortcut` come from the runtime events list.
- `LuaGuiElement::add()` supports the controls used in this mod, including frames, flows, tables, textfields, scroll-panes, tabbed panes, buttons, and choose-element buttons.
- `ShortcutPrototype` with `action = "lua"` raises `on_lua_shortcut`, which is used to open the global market/contracts/economy window.
- `LuaPlayer::opened` and `on_gui_opened` are used to show the trade-box configuration panel when a player interacts with a trade box.
- `on_runtime_mod_setting_changed` is the documented hook for reacting immediately when the runtime-global chart-tag setting is toggled.

### Map tags

- `LuaForce::add_chart_tag()` only creates a valid tag if the chunk is already charted for that force.
- `on_chunk_charted` is therefore needed to retry trade-box tag creation when a force charts the box location after the order already exists.

### Economy sampling and admin reporting

- `LuaForce::get_item_production_statistics(surface)` returns `LuaFlowStatistics` for a force/surface pair.
- `LuaFlowStatistics::get_output_count(name)` and `get_input_count(name)` are used to derive recent ore throughput for `iron-ore`, `copper-ore`, `coal`, `stone`, and `uranium-ore`.
- `commands.add_command` from `LuaCommandProcessor` is used for admin slash commands.

### Persistence and schema

- The Factorio 2.0 storage guidance explicitly uses the `storage` table for mod-persisted state.
- The schema in this mod is versioned and normalized during `on_init` and `on_configuration_changed`.

## Implementation Decisions Driven By Research

### Trade box path

- Chosen path: custom trade box entity instead of patching all vanilla chests.
- Rationale: it gives us a dedicated surface for GUI behavior, deterministic box registration, filterable inventory setup, and cleaner order ownership rules without invasive vanilla-chest heuristics.

### Automated trade blocking

- The documented `LuaEntity::disabled_by_script` inserter control plus `held_stack` / `pickup_target` / `drop_target` support lets the adapter prevent unaffordable automated deliveries before the item settles into the trade box in the normal case.

### Manual trade failure handling

- Because manual insert events fire after the interaction, insufficient-funds handling removes the inserted item immediately and returns it to the player inventory when possible, with spill fallback only if the return insert cannot fit.
