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
