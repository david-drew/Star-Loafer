# Star Loafer – Away Mission Template Sets

*(Design + Data Format Reference)*

## 1. Overview

**Away Missions** are self-contained, procedurally assembled “space dungeons” for the **Away Team mode**:

* Turn-based, AP-based squad tactics
* 10–30 rooms, 1–3 levels
* Hybrid focus: **exploration, story discovery, hazards, tactical encounters**
* Loot + narrative + risk (injury, death, attrition)

Each mission type is defined as a **Template Set**: a small bundle of JSON files describing how to generate that mission.

Examples:
`derelict_freighter`, `wrecked_passenger_liner`, `mining_station`, `pirate_hideout`, `black_market_hub`, `military_bunker`, `luxury_habitat`, `corporate_retreat`, `medical_facility`, `biocontainment_center`, `research_lab`, etc.

---

## 2. Folder Layout

Each mission template gets its own directory:

```text
res://data/procgen/away_missions/<mission_id>/
  location_templates.json
  room_archetypes.json
  hazard_profiles.json
  enemy_profiles.json
  loot_profiles.json
  story_nodes.json
```

Where `<mission_id>` matches the primary location template’s `id` (or is closely aligned).

---

## 3. High-Level Responsibilities

Each file answers a different question:

1. **location_templates.json**
   → What is this mission? How big, how dangerous, what biomes/tags, which profiles to use?

2. **room_archetypes.json**
   → What kinds of rooms exist here? How many hazards/enemies/loot can they host, and where in the layout do they tend to appear?

3. **hazard_profiles.json**
   → What hazards are allowed here, and how densely do they appear?

4. **enemy_profiles.json**
   → What enemy groups can spawn here, and how often?

5. **loot_profiles.json**
   → What loot categories and tables can drop here, and at what density?

6. **story_nodes.json**
   → Narrative content for this mission: mission-level hook/detail + per-node logs and story fragments.

---

## 4. `location_templates.json`

Schema (umbrella with `items[]`):

```json
{
  "schema": "star_loafer.away.location_templates.v1",
  "items": [
    {
      "id": "research_lab_standard",
      "display_name": "Research Lab",
      "description": "Short in-world description of this location.",

      "biome": "facility",
      "tags": [
        "scientific",
        "story_dense",
        "hazard_medium"
      ],

      "hazard_groups": ["environmental", "security", "biological"],
      "enemy_profiles": ["research_lab_enemies_id"],
      "loot_profiles": ["research_lab_loot_id"],
      "room_archetypes": [
        "lab_alpha",
        "analysis_room",
        "control_chamber",
        "storage_bay",
        "core_lab"
      ],

      "min_rooms": 12,
      "max_rooms": 24,
      "levels": [1, 3],
      "base_danger": 2,

      "time_pressure_weights": {
        "none": 0.6,
        "mild": 0.3,
        "heavy": 0.1
      },

      "story_nodes": [
        "research_lab_chain"
      ],

      "signature_features": [
        "unique_feature_1",
        "unique_feature_2"
      ],

      "meta": {
        "tags_internal": ["core_template"],
        "notes": "Design notes only; not used by the game."
      }
    }
  ]
}
```

**Key ideas:**

* `biome` + `tags` give high-level flavor: `station`, `facility`, `wreck`, `civilian`, `militarized`, `criminal`, `luxurious`, `quarantine`, etc.
* `min_rooms` / `max_rooms` / `levels` define scale.
* `hazard_groups`, `enemy_profiles`, `loot_profiles`, `room_archetypes` **reference IDs** defined in the sibling files.
* `base_danger` and `time_pressure_weights` help the generator bias hazard/enemy intensity and whether timers show up.

---

## 5. `room_archetypes.json`

Defines what rooms *feel like* and how they behave in generation.

```json
{
  "schema": "star_loafer.away.room_archetypes.v1",
  "items": [
    {
      "id": "core_lab",
      "display_name": "Core Laboratory",
      "description": "Central experiment chamber with high-risk equipment and data.",
      "tags": [
        "scientific",
        "high_value_target_area",
        "story_dense"
      ],
      "allowed_biomes": ["facility"],

      "min_hazards": 2,
      "max_hazards": 4,

      "min_enemies": 1,
      "max_enemies": 4,

      "max_loot_containers": 3,

      "supports_objective": true,
      "supports_story": true,
      "supports_boss": true,

      "preferred_hazard_tags": ["bio_contamination", "high_voltage"],
      "forbidden_hazard_tags": [],

      "preferred_enemy_tags": ["scientists", "mutations"],
      "forbidden_enemy_tags": [],

      "preferred_loot_tags": ["artifact", "data_log"],
      "forbidden_loot_tags": [],

      "layout_hint": "vault_room",
      "depth_bias": 2
    }
  ]
}
```

**Key ideas:**

* `min/max_hazards`, `min/max_enemies`, `max_loot_containers` are per-room caps for the generator.
* `supports_*` flags guide placement of objectives, story nodes, and bosses.
* `layout_hint` & `depth_bias` let the generator weight early vs deep placement (e.g. entry area vs final room).

---

## 6. `hazard_profiles.json`

Hazards allowed + density rules.

```json
{
  "schema": "star_loafer.away.hazard_profiles.v1",
  "items": [
    {
      "id": "research_lab_hazards",
      "display_name": "Research Lab Hazards",
      "description": "Environmental failures and experiment side effects.",

      "tags": ["scientific", "environmental"],

      "hazards": [
        { "id": "sparking_cables",          "weight": 3, "max_per_room": 2 },
        { "id": "power_outage_zone",        "weight": 2, "max_per_room": 2 },
        { "id": "energy_field_glitch",      "weight": 2, "max_per_room": 1 },
        { "id": "mild_radiation_pocket",    "weight": 1, "max_per_room": 1 }
      ],

      "global_rules": {
        "max_total_hazards": 16,
        "max_hazard_types_per_room": 2,
        "allow_overlap": false
      }
    }
  ]
}
```

**Key ideas:**

* `weight` drives random selection frequency.
* `max_total_hazards` and `max_hazard_types_per_room` are mission-level clamps.

---

## 7. `enemy_profiles.json`

Enemy groups for this mission.

```json
{
  "schema": "star_loafer.away.enemy_profiles.v1",
  "items": [
    {
      "id": "research_lab_enemies",
      "display_name": "Research Lab Adversaries",
      "description": "Panicked staff, corrupted bots, and accident side-effects.",

      "tags": ["scientific", "human_enemies", "robots"],

      "enemy_groups": [
        {
          "id": "panicked_technicians",
          "weight": 3,
          "min_depth": 0,
          "max_depth": 2,
          "min_danger": 1,
          "max_danger": 4
        },
        {
          "id": "security_drone_squad",
          "weight": 2,
          "min_depth": 1,
          "max_depth": 3,
          "min_danger": 2,
          "max_danger": 5
        }
      ],

      "global_rules": {
        "max_total_encounters": 9,
        "combat_frequency": "common",
        "allow_elites": true,
        "elite_chance": 0.12
      }
    }
  ]
}
```

**Key ideas:**

* `enemy_groups` are abstract — actual composition is defined elsewhere (enemy DB).
* Depth/danger min/max let you bias which groups appear where in the run.

---

## 8. `loot_profiles.json`

Loot density and categories.

```json
{
  "schema": "star_loafer.away.loot_profiles.v1",
  "items": [
    {
      "id": "research_lab_loot",
      "display_name": "Research Lab Inventory",
      "description": "Scientific gear, data, and occasional experimental tech.",

      "tags": ["scientific", "loot_rich"],

      "loot_tables": [
        { "id": "lab_equipment",        "category": "valuables",     "weight": 3 },
        { "id": "research_data_cache",  "category": "data_log",      "weight": 3 },
        { "id": "experimental_gadgets", "category": "artifact",      "weight": 2 },
        { "id": "protective_gear",      "category": "crew_gear",     "weight": 2 }
      ],

      "global_rules": {
        "average_loot_per_room": 0.35,
        "min_high_tier_items": 1,
        "max_high_tier_items": 3
      }
    }
  ]
}
```

---

## 9. `story_nodes.json`

### (New format with mission-level hook/detail)

This file now holds **two levels** of story:

1. Mission-level hook + detail
2. Per-node logs with optional node-level hook + detail

```json
{
  "schema": "star_loafer.away.story_nodes.v1",

  "mission_id": "research_lab_standard",
  "mission_hook": "A remote research lab claimed a breakthrough. Then it went dark.",
  "mission_detail": "Longer paragraph or two describing why the player might come here, what’s rumored to have happened, and what they might find. This is suitable for mission selection UI or codex entries.",

  "items": [
    {
      "id": "research_lab_story_01",
      "hook": "A rushed lab message hints at an impossible reading.",
      "detail": "Full in-world log text to show in a terminal UI when the player opens this log. Can be multi-sentence or multi-paragraph.",

      "display_name": "Preliminary Excitation Report",
      "description": "The first log that records something strange happening.",
      "type": "log",
      "biome": "facility",
      "tags": ["scientific", "story_dense", "mysterious"],

      "required": true,
      "weight": 3,
      "chain_group": "research_lab_chain",
      "chain_next": "research_lab_story_02",

      "preferred_room_tags": ["analysis_room", "lab_alpha"],
      "forbidden_room_tags": [],

      "min_depth": 0,
      "max_depth": 1,
      "min_danger": 0,
      "max_danger": 5,

      "effects": {
        "grants_log_entry": "research_lab_log_01",
        "triggers_event": "",
        "adds_trait_to_crew": [],
        "modifies_morale": 0
      }
    }

    // more nodes in the chain...
  ]
}
```

**Conventions:**

* `mission_id` links this narrative set to the primary mission template in `location_templates.json`.
* `mission_hook` → 1–2 sentence teaser for UI.
* `mission_detail` → 1–3 paragraph backstory.
* Node-level:

  * `display_name` → short title in UI list
  * `description` → short summary (internal or tooltip)
  * `hook` (optional) → one-liner “why this log is interesting”
  * `detail` (optional) → full text shown to the player (log window, terminal, etc.)
* `chain_group` + `chain_next` let you build ordered narrative chains within the mission.

---

## 10. How to Ask for a New Mission in Future Chats

When you want a new mission template set, you can say something like:

> “Using the Star Loafer Away Mission Template Set format, please create a new mission called `ancient_ruin` with a spooky, non-horror alien ruin theme. Produce all six JSON files, including `story_nodes.json` with mission_id/mission_hook/mission_detail and a 3-node story chain.”

And this doc is enough context for ChatGPT to:

* Use the right folder structure
* Follow the JSON umbrella schemas
* Use the new story_nodes format with mission-level + node-level story

---

If you’d like, next step I can do is:
**Generate the full `research_lab` mission (all 6 files) using this spec, with the updated `story_nodes.json` format.**
