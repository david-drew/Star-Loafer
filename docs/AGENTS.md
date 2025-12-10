# AGENTS.md (project root)

Use this as the quick orientation map for **Star Loafer** docs.

## Read this first
- Core: `docs/PROJECT_OVERVIEW.md`, `docs/ARCHITECTURE.md`
- Systems: `docs/SYSTEMS_Time_and_Ticks.md`, `docs/SYSTEMS_Procgen_and_Streaming.md`, `docs/SYSTEMS_Economy_and_Trade.md`, `docs/SYSTEMS_Ship_Components_and_Ship_Types.md`, `docs/SYSTEMS_Comms_and_Docking.md`, `docs/SYSTEMS_Factions_and_Reputation.md`, `docs/SYSTEMS_AI_and_Agents.md`, `docs/SYSTEMS_UI_and_Input.md`, `docs/SYSTEMS_Save_and_Scene_Flow.md`
- Data: `docs/DATA_SCHEMAS.md`
- Workflows: `docs/WORKFLOWS_Adding_a_New_Ship_Type.md`, `docs/WORKFLOWS_Adding_or_Modifying_Ship_Components.md`, `docs/WORKFLOWS_Adding_a_New_Mission.md`
- Legacy/reference design notes: `docs/Previous/` (see `docs/Previous/README.md` for a map of comms, economy, flight FSM, and away-team design docs).

## How to use this folder
- Before changing **worldgen or map code**, read `SYSTEMS_Procgen_and_Streaming.md`.
- Before changing **UI**, read `SYSTEMS_UI_and_Input.md` and relevant comms/ship panels.
- Before changing **economy**, read `SYSTEMS_Economy_and_Trade.md` and `DATA_SCHEMAS.md` economy section.
- Before touching **time/ticks**, read `SYSTEMS_Time_and_Ticks.md`.
- Before modifying **components/ships**, read the components/ship systems docs and workflows.
- If code and docs disagree, prefer the docs and open a follow-up to reconcile.

## Coding preferences (project-specific)
- Godot 4.5, GDScript-first. Do not introduce ternary operators.
- Favor EventBus signals and manager APIs over direct cross-node calls.
- Keep helpers small and explicit; avoid monoliths and hidden side effects.
- Data-first: extend JSON schemas first, then code; keep canonical IDs (`type__name`) consistent.
- Ask when unsure; propose options rather than guessing.
