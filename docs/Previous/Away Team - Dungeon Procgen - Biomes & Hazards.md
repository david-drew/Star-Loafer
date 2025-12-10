
# Away Team - Dungeon Procgen - Biomes & Hazards

Absolutely — let’s group all 15 template sets into **biomes** and **hazard categories**, then discuss the **tag system** (yes, it’s very useful), and how it would work in Star Loafer.

---

# ⭐ **Biome Classification + Hazard Grouping**

Below is a clean, game-design-friendly way to cluster the 15 template sets into:

* **Biomes** → large families of environment types
* **Hazard Groups** → general danger types that biome templates typically use

Each template set belongs to one biome, and often intersects 1–2 hazard groups.

---

# 🪐 **BIOMES (with member template sets)**

## **1. Ship / Spacecraft Biomes**

Interior of constructed ships.

**Members:**

* Derelict Freighter
* Wrecked Passenger Liner
* Crash Site (ship fragment)
* Prototype Vault (mobile or container-class ships)

**Typical Traits:**

* Modular room structure
* Airlocks, corridors, machinery
* Critical path engineering

---

## **2. Station / Outpost Biomes**

Constructed orbital or remote facilities.

**Members:**

* Remote Outpost (Faction or Deserted)
* Military Bunker / Listening Station
* Medical Facility / Biocontainment Center
* Luxury Habitat / Corporate Retreat
* Pirate Hideout / Black-Market Hub
* Mining Station / Asteroid Base

**Typical Traits:**

* Power grids
* Sectors/zones
* Defense systems
* Living quarters

---

## **3. Alien Architecture Biomes**

Non-human built environments.

**Members:**

* Ancient Alien Ruin
* Alien Outpost (Functional)
* Monastery / Spiritual Temple Station

**Typical Traits:**

* Non-standard shapes, layouts
* Glyphs, puzzles
* Strange materials
* Unknown technology

---

## **4. Anomaly / Rift Biomes**

Reality-distorted or physics-unstable areas.

**Members:**

* Dimensional Rift Site
* Crash Site (if anomaly-infused)

**Typical Traits:**

* Unreal geometry
* Distortion hazards
* Rare artifacts
* Uncommon/psychic enemies

---

# 🔥 **HAZARD GROUPS (what dangers appear in each biome)**

Each biome tends to use 2–4 hazard groups below.

---

## **1. Mechanical / Industrial Hazards**

* Fire
* Steam vents
* Coolant leaks
* Unstable machinery
* Falling debris
* Power arcs

**Used in:**

* Freighters
* Passenger Liners
* Mining Stations
* Military Bunkers
* Prototype Vaults
* Remote Outposts

---

## **2. Environmental / Atmospheric Hazards**

* Oxygen depletion
* Toxic gas
* Mold/fungal spore clouds
* Contaminated water
* Pressure loss
* Radiation pockets

**Used in:**

* Medical Facilities
* Mining Stations
* Passenger Liners
* Alien Outposts
* Ancient Ruins

---

## **3. Security / Defensive Hazards**

* Auto-turrets
* Laser grids
* Tripwires
* Countermeasure gas
* Electrified floors
* Lockdown security systems

**Used in:**

* Military Bunkers
* Prototype Vaults
* Pirate Hideouts
* Corporate Retreats
* Remote Outposts

---

## **4. Biological Hazards**

* Infection
* Parasitic organisms
* Mutated fauna
* Bio-engineered threats
* Pathogen containment failures

**Used in:**

* Medical Facilities
* Science Labs
* Passenger Liners (panic spread)
* Ancient Ruins (fauna)

---

## **5. Structural Hazards**

* Collapsing rooms
* Cracking floors
* Microgravity zones
* Shifting corridors
* Unstable ceilings/vents

**Used in:**

* Crash Sites
* Mining Stations
* Derelict Freighters

---

## **6. Energy / Anomaly Hazards**

* Time dilation bubbles
* Spatial distortion
* Gravity anomalies
* Psychic pulses
* Reality tears
* “Echo” phantoms

**Used in:**

* Dimensional Rift Site
* Ancient Ruins
* Prototype Vaults (rare)

---

# ⭐ **YES — we should absolutely use a tag system**

A **tag system** is basically mandatory in a flexible, data-driven procgen architecture like this.

Tags make:

* filtering
* weighting
* cross-referencing
* difficulty scaling
* compatibility checks
  much easier.

And critically, tags make the system **future-proof**. You can add new missions, hazards, events, and components without modifying code.

---

# 🏷️ **Tag Type Categories**

Here are the categories I recommend:

---

## **1. Biome Tags**

Used for broad grouping.

Examples:

* `ship`
* `station`
* `alien`
* `anomaly`

---

## **2. Environment Tags**

Describes the physical conditions.

Examples:

* `low_gravity`
* `vacuum`
* `pressurized`
* `humid`
* `radiation`
* `organic_growth`
* `flooded`

---

## **3. Hazard Tags**

Used for slotting hazard profiles into appropriate rooms.

Examples:

* `mechanical`
* `electrical`
* `biological`
* `psychic`
* `structural`

---

## **4. Threat Tags**

Used to define encounter logic and challenge type.

Examples:

* `human_enemies`
* `robot_enemies`
* `fauna_enemies`
* `anomaly_enemies`
* `stealth_preferred`
* `combat_frequent`
* `combat_rare`

---

## **5. Theme / Flavor Tags**

For story, audio, and visual styling.

Examples:

* `mysterious`
* `industrial`
* `holy`
* `luxury`
* `desolate`
* `quarantine`
* `haunted`

---

## **6. Gameplay Tags**

Used by the generator for branching logic or special handling.

Examples:

* `multi_level`
* `puzzle_heavy`
* `hazard_dense`
* `loot_rich`
* `fast_navigation`
* `rare_artifacts`
* `captain_dialogue_heavy`

---

# 🎯 Why tags are extremely useful in Star Loafer

### **A. Easy matching**

Rooms, hazards, and story nodes check tags:

* “Place ‘power_failure_chain’ only in templates tagged `industrial`.”
* “Hazard 'fungal_bloom' only in `biological` or `alien` templates.”

### **B. Weighted flavor generation**

Tags influence random generation:

* `mysterious + alien` → higher chance of psychic anomalies
* `industrial + station` → higher chance of fire and electrical hazards

### **C. Tooling**

You can write a simple Godot EditorPlugIn that:

* autocompletes tags
* warns about invalid tag combinations
* filters templates by tag

### **D. Easy future expansion**

Add new template:

* "Orbital Prison"
  and tag it:
  `["station", "security_heavy", "combat_common", "biological"]`

Boom — it integrates seamlessly with:

* hazards
* enemies
* loot
* room archetypes
* story chains

### **E. Reuse**

Hazards, rooms, logs, and events each list tags they require or avoid.
So the system mixes and matches components without brute force.

---

# ⭐ TAG SYSTEM: FINAL RECOMMENDATION

Yes — include a robust tag system.
Not for factions.
But for **environment**, **hazards**, **theme**, **enemy type**, and **procedural rules**.

It will dramatically improve:

* diversity
* maintainability
* perceived depth
* ease of adding content later

---

If you want, I can now:

1. **Generate a full tag taxonomy** with 80–120 recommended tags.
2. **Design the JSON schema for templates including tag fields.**
3. **Assign tags to each of the 15 template sets.**
4. **Show how tags influence procedural generation logic.**

Which next?
