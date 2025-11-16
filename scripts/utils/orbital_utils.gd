extends RefCounted
class_name OrbitalUtils

## Utility class for orbital mechanics calculations and coordinate conversions
## Used by system generation and display logic

# Physical constants
const AU_TO_PIXELS: float = 4000.0
const GRAVITATIONAL_CONSTANT: float = 1.0  # Simplified for game purposes

## ============================================================
## COORDINATE CONVERSION
## ============================================================

static func au_to_pixels(au: float) -> float:
	"""Convert AU to pixels"""
	return au * AU_TO_PIXELS

static func pixels_to_au(pixels: float) -> float:
	"""Convert pixels to AU"""
	return pixels / AU_TO_PIXELS

static func polar_to_cartesian(radius: float, angle: float) -> Vector2:
	"""Convert polar coordinates (radius, angle) to cartesian (x, y)"""
	return Vector2(cos(angle), sin(angle)) * radius

static func cartesian_to_polar(position: Vector2) -> Dictionary:
	"""Convert cartesian position to polar coordinates"""
	return {
		"radius": position.length(),
		"angle": position.angle()
	}

## ============================================================
## ORBITAL CALCULATIONS
## ============================================================

static func calculate_orbital_period(semi_major_axis_au: float, star_mass_solar: float = 1.0) -> float:
	"""
	Calculate orbital period in days using simplified Kepler's third law
	period^2 = semi_major_axis^3 / star_mass
	"""
	var period_squared := pow(semi_major_axis_au, 3.0) / star_mass_solar
	var period_years := sqrt(period_squared)
	return period_years * 365.25  # Convert to days

static func calculate_moon_orbital_period(orbital_radius_px: float, planet_mass_factor: float = 1.0) -> float:
	"""
	Calculate moon orbital period in days
	Simplified calculation based on pixel distance
	"""
	# Closer moons orbit faster, scale based on distance
	var base_period := orbital_radius_px / 400.0  # 400px = ~1 day orbit
	return max(0.5, base_period / planet_mass_factor)

static func calculate_orbital_velocity(semi_major_axis_au: float, star_mass_solar: float = 1.0) -> float:
	"""Calculate average orbital velocity in AU/day"""
	var period_days := calculate_orbital_period(semi_major_axis_au, star_mass_solar)
	var orbit_circumference := TAU * semi_major_axis_au
	return orbit_circumference / period_days

static func get_position_at_time(semi_major_axis_au: float, angle_offset: float, time_days: float, period_days: float) -> Vector2:
	"""Get orbital position at a specific time"""
	var angle := angle_offset + (TAU * time_days / period_days)
	var radius_px := au_to_pixels(semi_major_axis_au)
	return polar_to_cartesian(radius_px, angle)

## ============================================================
## ORBITAL ZONE CALCULATIONS
## ============================================================

static func get_temperature_zone(orbit_au: float, star_luminosity: float = 1.0) -> String:
	"""
	Determine temperature zone based on orbital distance and star luminosity
	Returns: "hot", "warm", "temperate", "cold", "frozen"
	"""
	# Adjust orbit based on star luminosity (brighter stars have wider habitable zones)
	var effective_orbit := orbit_au / sqrt(star_luminosity)
	
	if effective_orbit < 0.5:
		return "hot"
	elif effective_orbit < 0.9:
		return "warm"
	elif effective_orbit < 1.5:
		return "temperate"
	elif effective_orbit < 5.0:
		return "cold"
	else:
		return "frozen"

static func is_in_habitable_zone(orbit_au: float, star_luminosity: float = 1.0) -> bool:
	"""Check if orbit is in the habitable zone (liquid water possible)"""
	var effective_orbit := orbit_au / sqrt(star_luminosity)
	return effective_orbit >= 0.8 and effective_orbit <= 2.0

## ============================================================
## DISTANCE AND COLLISION HELPERS
## ============================================================

static func calculate_separation(pos1: Vector2, pos2: Vector2) -> float:
	"""Calculate distance between two positions"""
	return pos1.distance_to(pos2)

static func check_collision(pos1: Vector2, radius1: float, pos2: Vector2, radius2: float, min_separation: float = 0.0) -> bool:
	"""Check if two circular regions collide"""
	var distance := calculate_separation(pos1, pos2)
	var min_distance := radius1 + radius2 + min_separation
	return distance < min_distance

static func find_nearest_clear_position(
	desired_pos: Vector2,
	occupied_positions: Array,
	radius: float,
	min_separation: float,
	max_attempts: int = 20,
	rng: RandomNumberGenerator = null
) -> Vector2:
	"""
	Find nearest valid position that doesn't collide with occupied positions
	Returns Vector2.ZERO if no valid position found
	"""
	if rng == null:
		rng = RandomNumberGenerator.new()
	
	for attempt in range(max_attempts):
		var test_pos := desired_pos
		
		if attempt > 0:
			# Add random offset increasing with attempts
			var offset_distance := float(attempt) * 100.0
			var offset_angle := rng.randf() * TAU
			test_pos += Vector2(cos(offset_angle), sin(offset_angle)) * offset_distance
		
		# Check against all occupied positions
		var is_valid := true
		for occupied in occupied_positions:
			if check_collision(test_pos, radius, occupied["position"], occupied["radius"], min_separation):
				is_valid = false
				break
		
		if is_valid:
			return test_pos
	
	return Vector2.ZERO  # Failed to find valid position

## ============================================================
## ANGLE UTILITIES
## ============================================================

static func normalize_angle(angle: float) -> float:
	"""Normalize angle to range [0, TAU)"""
	var normalized := fmod(angle, TAU)
	if normalized < 0:
		normalized += TAU
	return normalized

static func angle_difference(angle1: float, angle2: float) -> float:
	"""Calculate smallest difference between two angles"""
	var diff := normalize_angle(angle2 - angle1)
	if diff > PI:
		diff -= TAU
	return abs(diff)

static func is_angle_between(angle: float, start: float, end: float) -> bool:
	"""Check if angle is between start and end (wrapping around)"""
	angle = normalize_angle(angle)
	start = normalize_angle(start)
	end = normalize_angle(end)
	
	if start < end:
		return angle >= start and angle <= end
	else:
		return angle >= start or angle <= end

## ============================================================
## SPRITE SIZE ESTIMATION
## ============================================================

static func estimate_planet_visual_radius(planet_type: String) -> float:
	"""Estimate planet visual radius in pixels (for collision detection)"""
	match planet_type:
		"gas":
			return 150.0
		"primordial":
			return 120.0
		"terran", "ocean", "thick_atmo":
			return 80.0
		_:
			return 60.0

static func estimate_moon_visual_radius(size_px_range: Array) -> float:
	"""Estimate moon visual radius from size range"""
	if size_px_range.size() >= 2:
		return (float(size_px_range[0]) + float(size_px_range[1])) / 2.0
	return 30.0

static func estimate_station_visual_radius(size_px: float) -> float:
	"""Estimate station visual radius (stations are roughly square)"""
	return size_px * 0.5  # Half of width/height

## ============================================================
## RANDOM UTILITIES
## ============================================================

static func random_position_in_ring(
	inner_radius: float,
	outer_radius: float,
	rng: RandomNumberGenerator
) -> Vector2:
	"""Generate random position in a ring (donut shape)"""
	var angle := rng.randf() * TAU
	var radius := rng.randf_range(inner_radius, outer_radius)
	return polar_to_cartesian(radius, angle)

static func random_position_in_circle(
	max_radius: float,
	rng: RandomNumberGenerator
) -> Vector2:
	"""Generate random position in a circle (uniform distribution)"""
	var angle := rng.randf() * TAU
	var radius := sqrt(rng.randf()) * max_radius  # sqrt for uniform distribution
	return polar_to_cartesian(radius, angle)

## ============================================================
## DEBUG UTILITIES
## ============================================================

static func format_position(pos: Vector2, in_au: bool = false) -> String:
	"""Format position for debug output"""
	if in_au:
		return "(%0.2f, %0.2f) AU" % [pixels_to_au(pos.x), pixels_to_au(pos.y)]
	else:
		return "(%0.0f, %0.0f) px" % [pos.x, pos.y]

static func format_orbit(orbit_au: float, angle: float) -> String:
	"""Format orbital parameters for debug output"""
	return "%0.2f AU @ %0.1f°" % [orbit_au, rad_to_deg(angle)]
