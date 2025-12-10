# Star Loafer – Faction Outpost Mission Design (Quick Reference)

You can paste this doc into a new chat and say:

“Use this as the reference for building Faction Outpost missions for Star Loafer. Let’s start by designing a faction_border_checkpoint mission, with mode: "dynamic" faction_binding, and then an independent_waystation mission.”

---

# Star Loafer – Faction Outpost Mission Design (Quick Reference)

## 1. Goal

Design **Away Mission templates** for “Faction Outposts” that:

* Can be **independent** (no major faction) or **bound to any existing faction**.
* Reuse the same mission template with different factions via **tags + skinning**, instead of hard-coding specific faction IDs everywhere.
* Plug into the existing Away Mission format:

  * `location_templates.json`
  * `room_archetypes.json`
  * `hazard_profiles.json`
  * `enemy_profiles.json`
  * `loot_profiles.json`
  * `story_nodes.json` (with `mission_hook` / `mission_detail`)

This doc is about **how outposts connect to factions**, not about all Away Mission details.

---

## 2. Concept: Faction Binding Modes

Each outpost-style mission can declare a **faction binding** in `location_templates.json`.

Proposed field (inside each `items[]` entry):

```json
"faction_binding": {
  "mode": "dynamic",         // "dynamic" | "independent" | "fixed"
  "role": "owner",           // e.g. "owner", "tenant", "occupier"

  "required_faction_tags": [
    "militarized",
    "border_presence"
  ],
  "forbidden_faction_tags": [
    "criminal"
  ],

  "hostility_default": "neutral", // "friendly" | "neutral" | "hostile"
  "law_level_hint": "high",       // optional: influences law/patrol flavor

  "allow_any_if_no_match": true,
  "fallback_mode": "independent", // what to do if no suitable faction is found

  "fixed_faction_id": null        // used only if mode == "fixed"
}
```

### Modes

* `"dynamic"`

  * At generation time, pick a faction in this area that matches `required_faction_tags` and doesn’t violate `forbidden_faction_tags`.
  * Skin signage, NPCs, dialogue, and `{FACTION_NAME}` substitutions accordingly.

* `"independent"`

  * No major faction owner. Possibly a local/minor group or just “neutral port”.
  * Behavior controlled by `hostility_default`, `law_level_hint`, and optional `independent_tags`.

* `"fixed"`

  * Explicitly bound to one specific faction (for key story beats).
  * Uses `fixed_faction_id` to point to a known faction.

---

## 3. Variants to Support

We probably want multiple “outpost families,” not just one:

* **Independent / Generic Outposts**

  * `independent_trade_post`
  * `frontier_mining_outpost`
  * `waystation_repair_hub`
  * Typically `mode: "independent"`.

* **Faction-Flexible Outposts** (dynamic owner)

  * `faction_border_checkpoint` (militarized, patrol-heavy)
  * `faction_supply_depot` (logistics, cargo-heavy)
  * `faction_listening_post` (intel, stealth)
  * `faction_research_spur` (mini research station)
  * `faction_recruitment_enclave` (social/story-heavy)
  * Typically `mode: "dynamic"`, with `required_faction_tags` filters.

* **Rare Fixed Outposts** (story-specific)

  * Only for major plot arcs.
  * `mode: "fixed"`, `fixed_faction_id: "some_major_faction"`.

---

## 4. Story Text Integration

For **story_nodes.json**, keep text mostly faction-agnostic and use placeholders:

```json
"detail": "Operations log: \"By directive of {FACTION_NAME}, this outpost is now under restricted access.\""
```

At runtime, replace `{FACTION_NAME}` (and potentially `{FACTION_ADJECTIVE}`, `{FACTION_SYMBOL}`, etc.) with the actual bound faction’s values.

`story_nodes.json` still follows the newer pattern:

```json
{
  "schema": "star_loafer.away.story_nodes.v1",
  "mission_id": "faction_border_checkpoint",
  "mission_hook": "...",
  "mission_detail": "...",
  "items": [
    {
      "id": "outpost_story_01",
      "hook": "...",
      "detail": "...",
      "display_name": "...",
      "description": "...",
      "chain_group": "outpost_chain",
      "chain_next": "outpost_story_02",
      ...
    }
  ]
}
```

---

## 5. Open Questions to Revisit (for Future Chat)

When resuming this design, the assistant should ask:

1. **Faction Tags**

   * What tags do factions currently use (if any)?
   * Do we need a small shared tag vocabulary specifically for mission binding, e.g.:

     * `militarized`, `corporate`, `criminal`, `religious`, `scientific`,
     * `border_power`, `local`, `fringe`, `pirate_friendly`, etc.?

2. **Independent Outposts**

   * Should independent outposts:

     * Avoid creating full faction entries (just “neutral station” behavior)?
     * Or create small, trackable micro-factions (e.g. local miner unions)?

3. **Hostility / Law-Level**

   * Should `hostility_default` and `law_level_hint` be:

     * Taken directly from the mission template?
     * Or combined with faction properties (e.g. criminal faction + checkpoint template → corrupt checkpoint)?

4. **Integration Level**

   * Are early Faction Outposts meant to be:

     * Mostly sandbox content (optional, systemic), or
     * Tight story content tied to named factions and arcs?

5. **Next Concrete Step**

   * Usually: design **one dynamic outpost** (`faction_border_checkpoint`) and **one independent outpost** (`independent_waystation`) using this faction_binding structure and the known Away Mission file layout.

---

You can paste this doc into a new chat and say:

> “Use this as the reference for building Faction Outpost missions for Star Loafer. Let’s start by designing a `faction_border_checkpoint` mission, with `mode: "dynamic"` faction_binding, and then an `independent_waystation` mission.”

…and it should pick up right where we left off.
