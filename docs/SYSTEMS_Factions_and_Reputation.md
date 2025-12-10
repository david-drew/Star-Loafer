# System: Factions and Reputation

## Responsibilities
- Track player reputation with factions and determine reputation tiers.
- Record interaction history and decide if events are reported.
- Influence comms/docking/mission outcomes via reputation tiers (hooks available).
- Assign factions to systems during galaxy generation (via FactionManager).

## Main scripts
- `scripts/systems/FactionRelations.gd`
- Faction assignment: `scripts/world/galaxy_generator.gd` (uses FactionManager API).
- Data: `data/factions/*.json` (factions_core, faction_relations, subfactions, economy profiles, mission templates).

## Reputation model
- Numeric rep per faction: -100 to 100.
- Tiers: Hostile (< -60), Unfriendly (< -30), Neutral (< 0), Friendly (< 60), Allied (>= 60).
- Signals: `reputation_changed(faction_id, old_rep, new_rep, tier_changed)`, `reputation_tier_changed`.
- Interaction history: rolling window (max 100 entries).

## Interaction processing
- `process_interaction(npc, interaction_type, severity, is_positive, context)`:
  - `should_report_interaction` rolls based on base chance per interaction type, NPC personality traits (if available), severity, and random nudge.
  - If reported, applies a rep delta drawn from severity ranges (positive or negative) and records history.
- Base report chances include ignored hail, smuggling caught, attacked_npc, completed_trade, completed_mission, etc.

## Faction assignment (galaxy)
- GalaxyGenerator calls FactionManager to pick faction per system, compute influence, and mark contested borders if hostile neighbors.
- Influence scales with pop level and faction type; contested systems get reduced influence and a `contested` tag.

## Extension points
- Define faction metadata/relationships in `data/factions/*.json`; ensure FactionManager exposes helpers (`select_faction_for_system`, `are_hostile`, `get_faction_type/name`).
- Connect reputation changes to gameplay: docking approval, comm templates, market taxes, mission availability.
- Add interaction types/severities to `INTERACTION_REPORT_BASE_CHANCES` and severity ranges to reflect new features (combat, smuggling, missions).
- Persist reputation via SaveSystem: use `get_save_data` / `load_save_data`.

## Pitfalls / notes
- FactionRelations awaits one frame to find FactionManager under `/root/GameRoot/Systems`; ensure hierarchy matches.
- If FactionManager API changes, update GalaxyGenerator calls to avoid breaking faction assignment.
- Interaction processing uses randomness; design deterministic variants for tests if needed.
