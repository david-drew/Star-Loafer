# System: Comms and Docking

## Responsibilities
- Manage hails, responses, and conversation flow using templates and AI profiles.
- Handle docking approvals/denials and autopilot docking sequences.
- Emit UI-friendly comm messages through EventBus.

## Main scripts
- `scripts/systems/CommSystem.gd`
- `scripts/systems/DockingManager.gd`
- Data: `data/dialogue/comm_message_templates.json`, `data/dialogue/comm_ai_profiles.json`
- Signals: EventBus (`hail_received`, `comm_message_received`, `comm_response_chosen`, `docking_approved/denied`, `ship_docked`, `ship_undocked`), CommSystem own signals (hail events, response_generated, broadcast_sent).

## Comms flow
1. `initiate_hail(initiator, recipient, hail_type)` checks cooldowns and acceptance; creates conversation; emits `hail_received`.
2. Builds context (entity ids/types, player stats, faction rep, distance) via `build_comm_context`.
3. Auto-generates initial greeting (station vs npc) using templates and AI profile personality.
4. Emits comm messages via EventBus `comm_message_received`; UI should display text and options.
5. Player (or AI) chooses a response → EventBus `comm_response_chosen` → CommSystem generates follow-up based on `leads_to_category`.
6. Conversations timeout based on entity type; timeouts can affect faction relations.
7. Broadcasts: `broadcast_message` sends one-to-many with range based on tech/priority.

## Docking flow
1. `request_docking(ship, station)` emits `docking_requested`. For NPCs, DockingManager may auto-approve/deny (rep check, lockdown).
2. Approval: compute docking point, register active docking, override player control if needed, emit `docking_approved` and `docking_started`.
3. Update loop phases: approaching (move toward dock point), aligning (rotate), completing (fires `complete_docking`).
4. Completion: sets docked flags, emits `docking_complete` and EventBus `player_docked_at_station` for player.
5. Undock: clears state, emits `undocking_started/complete`, EventBus `player_undocked`.

## Context and templates
- Templates organized by `response_type`/categories (e.g., station_greeting, docking_approved/denied).
- AI profiles define base personality traits and outgoing hail behavior (frequency).
- Personality modifiers and context requirements influence template weights.

## Extension points
- Add new template categories and response options in `comm_message_templates.json`.
- Add AI profiles for factions/roles in `comm_ai_profiles.json`.
- Extend context builders (e.g., cargo intel, mission states) without coupling UI; ensure defaults exist.
- Add consequences to comm choices by emitting EventBus signals or calling FactionRelations.
- Docking: add bay assignment, collision-safe paths, or station services on docking_complete.

## Pitfalls / notes
- CommSystem requires EventBus signals to be present; ensure autoload load order includes EventBus before CommSystem connects.
- DockingManager currently uses simple position/rotation checks; physics integration and obstruction checks are not implemented.
- Cooldown logic for hails depends on `comm_profile_id` `outgoing_hail_behavior`; ensure profiles specify reasonable limits.
