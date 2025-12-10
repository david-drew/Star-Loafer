# System: AI and Agents

## Responsibilities
- Track active AI agents for coordination/debugging.
- Provide ship/NPC behaviors via AgentBrain, ShipAgentController, ShipSensors.
- Spawn NPC ships appropriate to system context.

## Main scripts
- Autoload: `scripts/autoloads/ai_manager.gd` (register/unregister agents).
- AI components: `scripts/ai/agent_brain.gd`, `scripts/ai/ship_agent_controller.gd`, `scripts/ai/ship_sensors.gd`.
- NPC spawning: `scripts/actors/npc_spawner.gd`.
- Data: roles (`data/ai/roles.json` via RoleDb), personalities (`data/ai/personalities.json` via PersonalityDb).

## Current behavior (scaffold)
- AIManager only keeps a list of AgentBrain instances.
- AgentBrain/ShipAgentController handle per-ship state/behaviors (patrol, trade, flee, attack enums referenced in CommSystem for context strings).
- ShipSensors provides perception (targets, detection) for controllers.
- NPCSpawner:
  - Receives system data (stations, faction, seed) from SystemExploration.
  - Instantiates NPC ships (`scenes/actors/npc_ship.tscn`) and assigns faction/roles.
  - Exposes `get_npcs_in_range`, `get_hostile_npcs_in_range`, `clear_all_npcs`.

## Extension points
- Add AI states/behaviors in AgentBrain and ShipAgentController (e.g., escort, mine, smuggle).
- Use RoleDb/PersonalityDb to drive decision weights and comms personalities.
- Add faction-aware hostility/ally logic in NPCSpawner; integrate with FactionRelations.
- Register agents with AIManager for global toggles, debugging, or time-slicing heavy logic.
- Emit EventBus signals for AI events (combat, distress calls) when implementing combat.

## Pitfalls / notes
- Many behaviors are placeholders; ensure sensors/controllers handle missing targets gracefully.
- Keep AI decoupled: prefer EventBus or high-level service calls over direct node dependencies.
