extends Node

# === PHASE 0: CORE SIGNALS ===

# System & Navigation
signal system_entered(system_id: String)
signal location_discovered(scope: String, id: String)

# Player & Ship
signal ship_position_changed(position: Vector2)

# Economy
signal credits_changed(new_amount: int)

# UI & Maps
signal map_toggled(map_type: String, should_open: bool)

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
signal comm_message_received(message_data: Dictionary)

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
