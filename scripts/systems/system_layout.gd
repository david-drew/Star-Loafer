extends RefCounted
class_name SystemLayout

## Centralized spatial management for star system generation
## Handles position validation, collision detection, and placement of all stellar objects
## All positions stored in pixels internally

# Conversion constant
const AU_TO_PIXELS: float = 4000.0

# Minimum separation distances (in pixels)
const MIN_PLANET_SEPARATION_PX: float = 3000.0  # ~0.75 AU between planets
const MIN_STATION_SEPARATION_PX: float = 2000.0  # ~0.5 AU between stations
const MIN_MOON_SEPARATION_PX: float = 200.0     # Moons can be closer to each other
const MIN_STATION_FROM_CENTER_PX: float = 8000.0  # 2 AU minimum from system center

# Object tracking
var occupied_regions: Array[Dictionary] = []  # {position: Vector2, radius: float, id: String, kind: String}
var stars: Array[Dictionary] = []  # Store star positions for reference
var planets: Array[Dictionary] = []  # Store planet data with final positions
var moons: Array[Dictionary] = []  # Store moon data with parent references
var stations: Array[Dictionary] = []  # Store station data with final positions

# System bounds
var system_radius_px: float = 200000.0  # ~50 AU - reasonable system size

func _init() -> void:
	clear()

func clear() -> void:
	"""Reset all spatial data"""
	occupied_regions.clear()
	stars.clear()
	planets.clear()
	moons.clear()
	stations.clear()

## ============================================================
## PLACEMENT FUNCTIONS
## ============================================================

func place_star(star_data: Dictionary, position: Vector2) -> bool:
	"""Place a star at a specific position (stars are placed first, no collision check)"""
	var radius: float = 1000.0  # Stars have large exclusion zones
	var star_entry := {
		"id": star_data.get("id", "star:0"),
		"position": position,
		"radius": radius,
		"data": star_data
	}
	
	stars.append(star_entry)
	_register_occupied_region(position, radius, star_entry["id"], "star")
	return true

func place_planet(planet_data: Dictionary, desired_orbit_au: float, desired_angle: float, rng: RandomNumberGenerator, max_attempts: int = 20) -> Dictionary:
	"""
	Place a planet at desired orbital radius (in AU) and angle
	Returns updated planet_data with final position, or empty dict if failed
	"""
	var orbit_radius_px := desired_orbit_au * AU_TO_PIXELS
	var planet_size_px := _estimate_planet_size(planet_data)
	var exclusion_radius := planet_size_px * 2.0  # Give planets breathing room
	
	# Try to place at desired position first
	var desired_pos := Vector2(cos(desired_angle), sin(desired_angle)) * orbit_radius_px
	
	for attempt in range(max_attempts):
		var test_pos: Vector2
		
		if attempt == 0:
			test_pos = desired_pos
		else:
			# Vary angle and slightly vary radius
			var angle_offset := rng.randf_range(-0.3, 0.3) * attempt
			var radius_offset := rng.randf_range(-1000.0, 1000.0) * attempt
			var adjusted_angle := desired_angle + angle_offset
			var adjusted_radius := orbit_radius_px + radius_offset
			test_pos = Vector2(cos(adjusted_angle), sin(adjusted_angle)) * adjusted_radius
		
		# Check if position is valid
		if _is_position_valid_for_planet(test_pos, exclusion_radius):
			# Valid position found!
			var final_angle := test_pos.angle()
			var final_radius_px := test_pos.length()
			var final_radius_au := final_radius_px / AU_TO_PIXELS
			
			# Update planet data with final position
			var updated_planet := planet_data.duplicate(true)
			updated_planet["orbit"]["a_AU"] = final_radius_au
			updated_planet["orbit"]["angle_rad"] = final_angle
			updated_planet["_position_px"] = test_pos  # Store pixel position for reference
			
			# Register this planet
			var planet_entry := {
				"id": planet_data.get("id", "unknown"),
				"position": test_pos,
				"radius": exclusion_radius,
				"data": updated_planet
			}
			planets.append(planet_entry)
			_register_occupied_region(test_pos, exclusion_radius, planet_entry["id"], "planet")
			
			return updated_planet
	
	# Failed to place planet
	push_warning("SystemLayout: Failed to place planet %s after %d attempts" % [planet_data.get("id", "unknown"), max_attempts])
	return {}

func place_moon_relative_to_planet(moon_data: Dictionary, parent_planet_id: String, desired_radius_px: float, desired_angle: float, rng: RandomNumberGenerator, max_attempts: int = 15) -> Dictionary:
	"""
	Place a moon in orbit around its parent planet
	Returns updated moon_data with final position info, or empty dict if failed
	"""
	# Find parent planet
	var parent_planet: Dictionary = _find_planet_by_id(parent_planet_id)
	if parent_planet.is_empty():
		push_error("SystemLayout: Cannot place moon - parent planet '%s' not found" % parent_planet_id)
		return {}
	
	var parent_pos: Vector2 = parent_planet.get("position", Vector2.ZERO)
	var moon_size_px := _estimate_moon_size(moon_data)
	var exclusion_radius := moon_size_px * 1.5
	
	for attempt in range(max_attempts):
		var test_angle: float
		var test_radius: float
		
		if attempt == 0:
			test_angle = desired_angle
			test_radius = desired_radius_px
		else:
			# Vary angle and radius
			test_angle = desired_angle + rng.randf_range(-0.5, 0.5) * attempt
			test_radius = desired_radius_px + rng.randf_range(-100.0, 100.0) * attempt
		
		# Calculate absolute position
		var offset := Vector2(cos(test_angle), sin(test_angle)) * test_radius
		var test_pos := parent_pos + offset
		
		# Check if valid (moons can be close to each other, but not overlapping)
		if _is_position_valid_for_moon(test_pos, exclusion_radius, parent_pos):
			# Valid position!
			var updated_moon := moon_data.duplicate(true)
			updated_moon["orbit"]["radius_px"] = test_radius
			updated_moon["orbit"]["angle_rad"] = test_angle
			updated_moon["_position_px"] = test_pos  # Absolute position
			updated_moon["_parent_position_px"] = parent_pos  # For reference
			
			# Register moon
			var moon_entry := {
				"id": moon_data.get("id", "unknown"),
				"position": test_pos,
				"radius": exclusion_radius,
				"data": updated_moon,
				"parent_id": parent_planet_id
			}
			moons.append(moon_entry)
			_register_occupied_region(test_pos, exclusion_radius, moon_entry["id"], "moon")
			
			return updated_moon
	
	push_warning("SystemLayout: Failed to place moon %s around planet %s after %d attempts" % [
		moon_data.get("id", "unknown"),
		parent_planet_id,
		max_attempts
	])
	return {}

func place_station(station_data: Dictionary, placement_prefs: Dictionary, bodies_data: Array, rng: RandomNumberGenerator, max_attempts: int = 30) -> Dictionary:
	"""
	Place a station according to its placement preferences
	Returns updated station_data with final position, or empty dict if failed
	"""
	var station_size_px:float = station_data.get("size_px", 300.0)
	var exclusion_radius:float = station_size_px * 1.5
	
	# Get preferred radius range from placement_prefs
	var radius_range: Array = placement_prefs.get("orbit_radius_px_range", [10000.0, 30000.0])
	var min_radius: float = float(radius_range[0]) if radius_range.size() >= 1 else 10000.0
	var max_radius: float = float(radius_range[1]) if radius_range.size() >= 2 else 30000.0
	
	# Enforce minimum distance from center (2 AU = 8000 px)
	min_radius = max(min_radius, MIN_STATION_FROM_CENTER_PX)
	
	# Check if station should orbit near a specific body
	var prefer_orbit_kinds: Array = placement_prefs.get("prefer_orbit_host_kinds", [])
	var should_orbit_body := "planet" in prefer_orbit_kinds or "belt" in prefer_orbit_kinds or "moon" in prefer_orbit_kinds
	
	if should_orbit_body:
		# Try to place near a suitable body
		var suitable_bodies := _find_suitable_bodies_for_station(placement_prefs, bodies_data)
		if not suitable_bodies.is_empty():
			var target_body = suitable_bodies[rng.randi_range(0, suitable_bodies.size() - 1)]
			var result := _try_place_station_near_body(station_data, target_body, exclusion_radius, min_radius, max_radius, rng, max_attempts)
			if not result.is_empty():
				return result
			# If failed near body, fall through to deep space placement
	
	# Place in deep space (or if body placement failed)
	return _try_place_station_deep_space(station_data, exclusion_radius, min_radius, max_radius, rng, max_attempts)

func _try_place_station_near_body(station_data: Dictionary, target_body: Dictionary, exclusion_radius: float, min_offset: float, max_offset: float, rng: RandomNumberGenerator, max_attempts: int) -> Dictionary:
	"""Try to place a station near a specific body (planet, moon, or belt)"""
	var body_id: String = target_body.get("id", "")
	var body_kind: String = target_body.get("kind", "")
	var body_pos: Vector2
	
	# Get body position
	if body_kind == "planet":
		var planet_entry := _find_planet_by_id(body_id)
		if planet_entry.is_empty():
			return {}
		body_pos = planet_entry.get("position", Vector2.ZERO)
	elif body_kind == "moon":
		var moon_entry := _find_moon_by_id(body_id)
		if moon_entry.is_empty():
			return {}
		body_pos = moon_entry.get("position", Vector2.ZERO)
	elif body_kind == "asteroid_belt":
		# For belts, use the orbital radius
		var belt_orbit: Dictionary = target_body.get("orbit", {})
		var belt_radius_au: float = belt_orbit.get("a_AU", 20.0)
		var belt_radius_px := belt_radius_au * AU_TO_PIXELS
		var belt_angle := rng.randf() * TAU
		body_pos = Vector2(cos(belt_angle), sin(belt_angle)) * belt_radius_px
	else:
		return {}
	
	# Try to place near this body
	for attempt in range(max_attempts):
		var offset_distance := rng.randf_range(min_offset, max_offset)
		var offset_angle := rng.randf() * TAU
		var test_pos := body_pos + Vector2(cos(offset_angle), sin(offset_angle)) * offset_distance
		
		# Enforce minimum distance from center
		if test_pos.length() < MIN_STATION_FROM_CENTER_PX:
			continue
		
		if _is_position_valid_for_station(test_pos, exclusion_radius):
			return _finalize_station_placement(station_data, test_pos, exclusion_radius)
	
	return {}

func _try_place_station_deep_space(station_data: Dictionary, exclusion_radius: float, min_radius: float, max_radius: float, rng: RandomNumberGenerator, max_attempts: int) -> Dictionary:
	"""Try to place a station in deep space (not near any body)"""
	for attempt in range(max_attempts):
		var radius := rng.randf_range(min_radius, max_radius)
		var angle := rng.randf() * TAU
		var test_pos := Vector2(cos(angle), sin(angle)) * radius
		
		if _is_position_valid_for_station(test_pos, exclusion_radius):
			return _finalize_station_placement(station_data, test_pos, exclusion_radius)
	
	push_warning("SystemLayout: Failed to place station %s in deep space after %d attempts" % [
		station_data.get("id", "unknown"),
		max_attempts
	])
	return {}

func _finalize_station_placement(station_data: Dictionary, position: Vector2, exclusion_radius: float) -> Dictionary:
	"""Finalize station placement and register it"""
	var updated_station := station_data.duplicate(true)
	updated_station["position"] = [position.x, position.y]
	updated_station["_position_px"] = position
	
	var station_entry := {
		"id": station_data.get("id", "unknown"),
		"position": position,
		"radius": exclusion_radius,
		"data": updated_station
	}
	stations.append(station_entry)
	_register_occupied_region(position, exclusion_radius, station_entry["id"], "station")
	
	return updated_station

## ============================================================
## VALIDATION FUNCTIONS
## ============================================================

func _is_position_valid_for_planet(position: Vector2, exclusion_radius: float) -> bool:
	"""Check if position is valid for a planet"""
	# Check against all occupied regions (stars, other planets)
	for region in occupied_regions:
		var region_kind: String = region.get("kind", "")
		if region_kind == "moon":
			continue  # Planets don't collide with moons (moons orbit planets)
		
		var distance := position.distance_to(region["position"])
		var min_distance:float = exclusion_radius + region["radius"]
		
		# Planets need extra separation
		if region_kind == "planet":
			min_distance = max(min_distance, MIN_PLANET_SEPARATION_PX)
		
		if distance < min_distance:
			return false
	
	# Check system bounds
	if position.length() > system_radius_px:
		return false
	
	return true

func _is_position_valid_for_moon(position: Vector2, exclusion_radius: float, parent_pos: Vector2) -> bool:
	"""Check if position is valid for a moon"""
	# Moons can be close to each other but not overlapping
	# They should not overlap with stations or planets (except their parent)
	for region in occupied_regions:
		var region_kind: String = region.get("kind", "")
		
		# Skip the parent planet
		if region["position"] == parent_pos and region_kind == "planet":
			continue
		
		var distance := position.distance_to(region["position"])
		var min_distance:float = exclusion_radius + region["radius"]
		
		# Moons can be closer to each other
		if region_kind == "moon":
			min_distance = max(min_distance, MIN_MOON_SEPARATION_PX)
		
		if distance < min_distance:
			return false
	
	# Check system bounds
	if position.length() > system_radius_px:
		return false
	
	return true

func _is_position_valid_for_station(position: Vector2, exclusion_radius: float) -> bool:
	"""Check if position is valid for a station"""
	# Minimum distance from center (2 AU)
	if position.length() < MIN_STATION_FROM_CENTER_PX:
		return false
	
	# Check against all occupied regions
	for region in occupied_regions:
		var distance := position.distance_to(region["position"])
		var min_distance:float = exclusion_radius + region["radius"]
		
		# Stations need separation from everything
		min_distance = max(min_distance, MIN_STATION_SEPARATION_PX)
		
		if distance < min_distance:
			return false
	
	# Check system bounds
	if position.length() > system_radius_px:
		return false
	
	return true

## ============================================================
## HELPER FUNCTIONS
## ============================================================

func _register_occupied_region(position: Vector2, radius: float, id: String, kind: String) -> void:
	"""Register a position as occupied"""
	occupied_regions.append({
		"position": position,
		"radius": radius,
		"id": id,
		"kind": kind
	})

func _find_planet_by_id(planet_id: String) -> Dictionary:
	"""Find a planet entry by ID"""
	for planet in planets:
		if planet.get("id", "") == planet_id:
			return planet
	return {}

func _find_moon_by_id(moon_id: String) -> Dictionary:
	"""Find a moon entry by ID"""
	for moon in moons:
		if moon.get("id", "") == moon_id:
			return moon
	return {}

func _find_suitable_bodies_for_station(placement_prefs: Dictionary, bodies_data: Array) -> Array:
	"""Find bodies suitable for station placement based on preferences"""
	var prefer_orbit_kinds: Array = placement_prefs.get("prefer_orbit_host_kinds", [])
	var planet_type_bias: Array = placement_prefs.get("planet_type_bias", [])
	
	var suitable := []
	
	for body in bodies_data:
		var body_kind: String = body.get("kind", "")
		
		# Check if body kind is preferred
		if body_kind in prefer_orbit_kinds:
			# For planets, also check type bias
			if body_kind == "planet":
				var planet_type: String = body.get("type", "")
				if planet_type_bias.is_empty() or planet_type in planet_type_bias:
					suitable.append(body)
			else:
				suitable.append(body)
	
	return suitable

func _estimate_planet_size(planet_data: Dictionary) -> float:
	"""Estimate planet visual size in pixels"""
	# Could read from planet_types.json if needed, for now use reasonable estimate
	var planet_type: String = planet_data.get("type", "rocky")
	match planet_type:
		"gas":
			return 150.0  # Gas giants are large
		"primordial":
			return 120.0
		"terran", "ocean", "thick_atmo":
			return 80.0
		_:
			return 60.0  # Default for rocky, ice, barren, etc.

func _estimate_moon_size(moon_data: Dictionary) -> float:
	"""Estimate moon visual size in pixels"""
	var size_range: Array = moon_data.get("size_px_range", [20, 40])
	if size_range.size() >= 2:
		return (float(size_range[0]) + float(size_range[1])) / 2.0
	return 30.0

## ============================================================
## DEBUG / UTILITY
## ============================================================

func get_stats() -> Dictionary:
	"""Get statistics about the current layout"""
	return {
		"stars": stars.size(),
		"planets": planets.size(),
		"moons": moons.size(),
		"stations": stations.size(),
		"occupied_regions": occupied_regions.size()
	}

func print_layout_summary() -> void:
	"""Print a summary of the current layout"""
	print("SystemLayout Summary:")
	print("  Stars: %d" % stars.size())
	print("  Planets: %d" % planets.size())
	print("  Moons: %d" % moons.size())
	print("  Stations: %d" % stations.size())
	print("  Total occupied regions: %d" % occupied_regions.size())
