# Workflow: Adding or Modifying Ship Components

Goal: Create or adjust components in `components.json` and ensure runtime behavior and UI stay coherent.

## Steps
1. **Decide component type and role**
   - Choose a `type` defined in `schema_components.json` (reactor, drive, shield, weapon, sensor, armor, ecm, computer, cloaking, radiator, cargo_module, habitat, fabricator, lab, hangar, industrial, utility).
   - Identify required fields from the schema (e.g., reactors need `power_output`, drives need `thrust` and `turning_torque`, weapons need `hardpoint_size` and `weapon_class`).

2. **Edit `data/components/components.json`**
   - Add to the `components` array:
   ```json
   {
     "id": "reactor__fusion_mk1",
     "type": "reactor",
     "tier": 2,
     "tech_level": 3,
     "space_cost": 4,
     "power_output": 24.0,
     "heat": 8.0,
     "throttleable": true,
     "tags": ["civilian", "starter"]
   }
   ```
   - Use canonical IDs (`type__local_name`); ComponentDB will alias common variants, but canonical is preferred.
   - If adding visuals, include `sprite` block or rely on `sprite_defaults` (path template `{type}_{variant}.png` in `assets/images/ui/components/`).

3. **Weapons specifics**
   - Ensure `hardpoint_size` (`light|medium|heavy|turret`) and `slot_cost` are set.
   - Include `damage`, `fire_rate`, `range`, and optional `projectile_speed`, `energy_cost`, `weapon_class`.

4. **Defense/utility specifics**
   - Armor: `hull_points_bonus`, optional `damage_reduction`; stacking uses diminishing returns.
   - ECM: `signature_mult` or `signature_flat`, `scan_defense_bonus`, `missile_defense`.
   - Utility: `component_space_bonus_pct`, `add_hardpoints` map.

5. **Validate and load**
   - Run the game to let ComponentDB load; check logs for parse errors.
   - Use GDScript snippet to verify:
   ```gdscript
   var def = ComponentDB.get_def("reactor__fusion_mk1")
   print(def)
   var scs = ShipComponentSystem.new()
   scs.init_from_ship_type("starter_frigate", ComponentDB, ShipTypeDB)
   scs.install("reactor__fusion_mk1")
   print(scs.get_current_stats().power_margin)
   ```

6. **Balance and testing**
   - Check `get_component_space_free` and `get_hardpoints_free` when installing to avoid impossible defaults.
   - Verify power margins; ShipComponentSystem will shed lowest-priority components if power is negative.
   - Adjust `diminishing_returns` defaults in ComponentDB if you add many stackable components.

7. **Document**
   - Update any design tables and changelog.
   - Keep notes on legality/rarity if economy or factions will reference them later.

## Common pitfalls
- Non-canonical IDs causing duplicates.
- Missing required fields per schema (e.g., weapon without `hardpoint_size`).
- Sprite path mismatches; ensure variant numbering uses two digits (`_01`).
- Installing components that exceed ship space/hardpoints; check values before setting as stock components.
