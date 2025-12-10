extends Node

# Time Management
signal time_sim_tick(hours_elapsed: float, ticks: int)
signal time_big_jump(jump_hours: float, source: String)
signal time_mode_changed(old_mode: String, new_mode: String)
signal time_day_changed(year: int, day_of_year: int)

# System & Navigation
signal system_entered(system_id: String)
signal location_discovered(scope: String, id: String)

# Player & Ship
signal ship_position_changed(position: Vector2)

# Economy
signal credits_changed(new_amount: int)				# might be deprecated
signal trade_completed(trade_data: Dictionary)
signal market_prices_updated(station_id: String, price_changes: Dictionary)
signal commodity_shortage(station_id: String, commodity_id: String, severity: float)
signal commodity_surplus(station_id: String, commodity_id: String, amount: float)

# UI & Maps
signal map_toggled(map_type: String, should_open: bool)

signal player_ship_registered(ship: Node) 						## Emitted when the player ship instance is ready/registered.
signal ship_stats_updated(ship: Node, stats: Dictionary)		## Emitted when ship stats change in a way that UI should know about.

## loadout: Array of thin entries: { component_id, instance_id, enabled }
signal ship_loadout_updated(ship: Node, loadout: Array)			## Emitted when a ship's component loadout changes (install/remove/toggle).

## candidates: Array of { component_id: String, count: int }
signal ship_component_candidates_updated(ship: Node, candidates: Array)		## Emitted when install candidates (from cargo/inventory) change for a ship.

## ship: Ship whose systems should be shown.
signal ship_screen_toggled(ship: Node, should_open: bool)		## Emitted to open or close the Ship Systems UI for a specific ship.


# Travel
signal fast_travel_requested(target_system_id: String)

# === FUTURE PHASES (optional, add as needed) ===

# Combat (Phase 1+)
# signal enemy_spawned(enemy_id: String)
# signal ship_damaged(damage_amount: float)
# signal ship_destroyed(ship_id: String)

# Trading (Phase 1+)
# signal commodity_price_changed(commodity_id: String, new_price: int)
# signal trade_completed(commodity_id: String, quantity: int, price: int)

# Missions (Phase 2+)
# signal mission_accepted(mission_id: String)
# signal mission_completed(mission_id: String)
# signal mission_failed(mission_id: String)

# Reputation (Phase 2+)
# signal reputation_changed(faction_id: String, new_value: int)

# Mining (Phase 1+)
# signal ore_mined(ore_type: String, amount: int)
# signal mining_node_depleted(node_id: String)

## Emitted when a comm message should be displayed to the player
## message_data format:
## {
##   "from": String (sender name),
##   "from_node": Node (sender reference),
##   "to": String (recipient name),
##   "to_node": Node (recipient reference),
##   "text": String (message text),
##   "conversation_id": String (unique conversation ID),
##   "response_options": Array (optional player responses),
##   "message_type": String (optional: "docking_approved", "docking_denied", etc.)
## }
signal hail_received(sender:Node, recipient:Node, context:Dictionary)
signal comm_message_received(message_data: Dictionary)
signal comm_response_chosen(conversation_id, response_index: int, response: Dictionary)
signal comm_conversation_closed(conversation_id)

## Emitted when a station approves docking for a ship
## station: The station granting permission
## ship: The ship being granted permission
## bay_id: The assigned docking bay number
signal docking_approved(station: Node, ship: Node, bay_id: int)

## Emitted when a station denies docking for a ship
## station: The station denying permission
## ship: The ship being denied
## reason: String explaining denial ("hostile_reputation", "no_docking_service", etc.)
signal docking_denied(station: Node, ship: Node, reason: String)

## Emitted when a ship completes docking at a station
## ship: The ship that docked
## station: The station where docking occurred
signal ship_docked(ship: Node, station: Node)

## Emitted when a ship completes undocking from a station
## ship: The ship that undocked
## station: The station where undocking occurred
signal ship_undocked(ship: Node, station: Node)

# Components / Ship Systems

## UI is asking the game to toggle a component on/off.
## enabled: true = turn on, false = turn off
signal ship_component_toggle_requested(ship: Node, component_id: String, enabled: bool)

## UI is asking the game to install a component on the ship.
signal ship_component_install_requested(ship: Node, component_id: String)

## UI is asking the game to remove a component from the ship.
signal ship_component_remove_requested(ship: Node, component_id: String)

## Emitted when a requested action fails (rules, space, cargo, etc.).
## action: "install", "remove", "toggle"
## reason: snake_case reason code ("not_docked", "insufficient_component_space", etc.)
## data: optional context, e.g. { "component_id": "weapon__dual_pulse_mk2" }
signal ship_component_action_failed(ship: Node, action: String, reason: String, data: Dictionary)
