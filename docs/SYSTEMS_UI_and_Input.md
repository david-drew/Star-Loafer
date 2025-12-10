# System: UI and Input

## Responsibilities
- Present HUD, maps, comms, ship systems, notifications, menus.
- Respond to EventBus signals for map toggles, comm messages, ship stats/loadout updates.
- Provide input mappings for flight and UI toggles.

## Main scripts/scenes
- HUD: `scripts/ui/hud.gd`, scene `scenes/ui/hud.tscn`.
- Maps: `scripts/ui/galaxy_map.gd`, `scripts/ui/system_map.gd`, scenes under `scenes/ui/`.
- Ship systems panel: `scripts/ui/ShipSystemsPanel.gd`.
- Comms panel: `scripts/ui/comm_panel.gd`.
- Notifier panel: `scripts/ui/notifier_panel.gd`.
- Camera: `scripts/ui/camera2d.gd`.
- Menus: main_menu, pause_menu scenes.
- Input map: defined in `project.godot` (`move_*`, `zoom_in/out`, `reset_camera`, `ui_map`, `ui_map_system`, `ui_ship_systems`, `print_screen`).

## Event hooks (primary)
- `EventBus.map_toggled(map_type, should_open)` — emitted by SystemExploration; maps should open/close accordingly.
- `EventBus.ship_screen_toggled(ship, should_open)` — toggle ShipSystemsPanel for specific ship.
- `EventBus.ship_stats_updated(ship, stats)` — update ship HUD/system panel.
- `EventBus.ship_loadout_updated(ship, loadout)` — refresh install/remove state.
- `EventBus.ship_component_candidates_updated(ship, candidates)` — show install options from cargo/inventory.
- `EventBus.comm_message_received(message_data)` — display comm messages and response options; emit `comm_response_chosen` on selection.
- `EventBus.credits_changed(new_amount)` — HUD credits.

## Flow (maps)
1. Player presses `ui_map` or `ui_map_system`.
2. SystemExploration emits `map_toggled`.
3. Map scenes handle open/close; they read `GameState` for galaxy/system data.

## Flow (ship systems panel)
1. Some UI or hotkey triggers `ship_screen_toggled`.
2. Panel fetches stats/loadout from ShipComponentSystem and listens for update signals.
3. Player actions (install/remove/toggle) should emit `ship_component_*_requested` signals to EventBus; ShipComponentSystem responds and emits updates/failures.

## UI styling / assets
- Ships/components sprites under `assets/images/actors/ships` and `assets/images/ui/components`.
- Icons referenced in data schemas (components, etc.).

## Extension points
- Add new UI panels: prefer wiring via EventBus signals and minimal direct node references.
- For input changes: update `project.godot` InputMap; document in UI.
- Map overlays: pull from GameState (fog/discovery) and system data (stations, bodies, NPCs).

## Pitfalls / notes
- Keep UI responsive to missing signals (when systems not initialized).
- Avoid ternary operators in GDScript UI code; keep conditions explicit.
