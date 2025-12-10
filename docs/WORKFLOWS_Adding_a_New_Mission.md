# Workflow: Adding a New Mission (forward-looking)

Current state: mission runtime is mostly design-only. Use this as a scaffold until mission systems land.

## Near-term hooks available
- EventBus has placeholder mission signals (commented) — plan to emit/consume once mission controller exists.
- Factions: `FactionRelations.process_interaction` can adjust reputation for mission outcomes.
- Comms: use `CommSystem` templates to present mission offers and responses.
- Data: `data/factions/faction_mission_templates.json` exists but not yet consumed.

## Suggested process (until a mission system is built)
1. **Define mission template data**
   - Add to `data/factions/faction_mission_templates.json` or a new `data/missions/*.json` file with fields:
     - `id`, `faction_id`, `type` (delivery/scan/rescue/contract), `requirements` (rep tier, ship class), `objectives`, `rewards` (credits, rep, items), `failure` consequences.
   - Mark any inferred fields explicitly for future loader implementation.

2. **Expose offer via comms**
   - Add a comm template category (e.g., `mission_offer_scan`) with response options:
     - Accept → emits a custom EventBus signal (temporary) or directly calls a mission stub.
     - Decline → adjusts rep or closes conversation.

3. **Track state (temporary)**
   - Use `GameState.active_contracts` to store lightweight mission entries:
   ```gdscript
   var mission = {
     "id": "mission_scan_alpha",
     "state": "active",
     "faction_id": "aurora_fleet",
     "target_system": "sys:00123",
     "reward_credits": 5000
   }
   GameState.active_contracts.append(mission)
   ```
   - Persist via SaveSystem once provider keys are fixed.

4. **Resolve completion/failure**
   - On completion: add credits via `GameState.add_credits`, adjust reputation with `FactionRelations.adjust_reputation`.
   - On failure: adjust reputation negatively; clear mission state.

5. **Future integration plan**
   - Build `MissionController` autoload to own mission templates, generation, state, and EventBus hooks.
   - Add UI panel for mission log and objective tracking.
   - Extend SystemGenerator to spawn mission targets (anomalies, POIs, NPCs).

## Pitfalls / notes
- Do not hardcode mission logic into comm templates; route through a controller once it exists.
- Mark INFERRED fields in data to ease future schema validation.
- Avoid ternary operators in mission scripts when added.
