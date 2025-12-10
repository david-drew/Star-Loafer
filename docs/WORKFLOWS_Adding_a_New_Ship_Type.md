# Workflow: Adding a New Ship Type

Goal: Define a new ship hull with visuals, stock components, and ensure it appears correctly in-game.

## Steps
1. **Plan the hull**
   - Decide `category`, `size_category` (small/medium/large/capital), `manufacturer`, `tech_level`, `base_value`, tags.
   - Define capacities: `component_space`, `hardpoints` by size, hull/shield/sensor/cargo, maneuverability, range, crew support, mass.

2. **Add hull visuals**
   - Update `data/components/hull_visuals.json`:
     - Add entry `{ "id": "hull_myship", "sprite_type": "myship", "num_variants": 2 }`.
     - Ensure sprites exist at `assets/images/actors/ships/myship_01.png` (and variants).
   - If reusing defaults, set `hull_class_id` to an existing hull entry.

3. **Add the ship entry**
   - Edit `data/components/ship_types_v2.json`, append under `ships`:
   ```json
   {
     "id": "myship_scout",
     "name": "Scout Mk I",
     "category": "Scout",
     "size_category": "small",
     "manufacturer": "Aurora Yards",
     "tech_level": 3,
     "base_value": 120000,
     "tags": ["explorer", "civilian"],
     "mass_base": 30.0,
     "component_space": 14,
     "hardpoints": { "light": 2, "medium": 0, "heavy": 0, "turret": 0 },
     "hull_points": 250,
     "shield_strength": 100,
     "sensor_strength": 2.5,
     "cargo_capacity": 60,
     "maneuverability": 6.5,
     "range_au": 4.0,
     "crew_support": 6,
     "stock_components": [
       "reactor__fission_mk1",
       "drive__chem_impulse_mk1",
       "shield__basic_mk1",
       "sensor__nav_mk1"
     ],
     "hull_class_id": "hull_myship"
   }
   ```
   - Keep IDs canonical; avoid ternary operators in any code snippets when referencing this ship.

4. **Load and validate**
   - Run the game; `ShipTypeDB` loads on start. Check the console for warnings about missing assets or JSON errors.
   - Use a test harness or spawn command to instantiate the ship:
   ```gdscript
   var scs = ShipComponentSystem.new()
   scs.init_from_ship_type("myship_scout", ComponentDB, ShipTypeDB)
   print(scs.get_current_stats())
   ```

5. **Hook into gameplay**
   - NPCSpawner: add logic to pick the new ship for certain factions/roles if desired.
   - Economy/shop (future): ensure stock components are obtainable; add ship availability list when implemented.

6. **Document**
   - Update any design docs that list ship categories or progression.
   - Add a note in changelog if player-facing.

## Common pitfalls
- Missing sprite assets or wrong filenames (`{type}_{variant}.png`).
- Stock component IDs not canonical (use `type__name`).
- Hardpoints/component_space too small to fit stock components.
- Forgetting to update hull visuals when adding a new hull_class_id.
