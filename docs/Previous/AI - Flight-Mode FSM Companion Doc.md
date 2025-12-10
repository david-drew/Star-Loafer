
# Flight-Mode FSM Companion Doc

You can treat this as `docs/ai_flight_fsm.md`.

### 1.1 Purpose

Define the **finite state machine** used by `AgentBrain` in **flight / space mode**:

* Shared state set for all ship roles.
* Role-specific **allowed states**, **transitions**, and **utility preferences**.
* Clean separation of:

  * *State* = “what I’m currently doing at a high level”
  * *Utility decisions* = “how exactly I do it” inside that state.

---

### 1.2 Global Concepts

**Inputs** (from ShipSensors + world):

* `visible_ships`: [ShipInfo...]
* `player_ship`: optional ShipInfo
* `nearest_station`: StationInfo
* `system_law_level`
* `faction_relations`: (self_faction, others)
* `threat_level`: estimate of enemy strength vs self
* `cargo_value_estimate`: approximate value of target cargo
* `player_reputation`: per-faction

**Blackboard fields** (examples):

* `current_target_ship`
* `escort_leader`
* `threat_ship` (ship that attacked us)
* `destination_waypoint`
* `safe_docking_target`
* `morale`
* `last_state_change_time`

**Outputs** (to ShipAgentController / systems):

* `move_to(point)`
* `orbit_target(target, radius)`
* `maintain_distance(target, min, max)`
* `flee_from(target_or_point)`
* `dock_at(station)`
* `open_hail(target, type)`
* `attack_target(target)`
* `cease_fire()`

---

### 1.3 State List

**Core shared states:**

1. `Idle`
2. `TravelRoute`
3. `Docking`
4. `Undocking`
5. `Patrol`
6. `Guard`
7. `Hunt`
8. `Escort`
9. `Engage`
10. `Flee`
11. `CallForHelp`
12. `Surrender`
13. `Wander`
14. `StudyAnomaly` (researcher-focused)
15. `InvestigateSignal` (optional, later)

Not all roles use all states.

---

### 1.4 State Definitions (Concise)

#### `Idle`

* **Used by:** any role.
* **Entry conditions:** no route, no orders, or just spawned and waiting.
* **Behavior:** slow drift or minimal movement near spawn point / station.
* **Transitions:**

  * → `TravelRoute` when assigned route.
  * → `Patrol` for police/military.
  * → `Wander` for tourists.
  * → `Engage` if attacked at close range.

---

#### `TravelRoute`

* **Used by:** trader, courier, diplomat, tourist, researcher (transit), some patrols.
* **Behavior:**

  * Move along waypoints defined by world sim route.
  * Avoid large threats if system law low and caution high.
* **Transitions:**

  * → `Docking` when close to destination station.
  * → `Engage` if forced into combat (pirate ambush, etc.) and bravery high.
  * → `Flee` if outgunned or morale low.
  * → `CallForHelp` if under attack and law > threshold.

---

#### `Docking`

* **Used by:** any.
* **Behavior:**

  * Approach station using docking corridor / autopilot.
* **Transitions:**

  * → `Idle` when docked (simulated).
  * → `Flee` if attacked while docking (rare; maybe ignore in Phase 1).

---

#### `Undocking`

* **Used by:** any.
* **Behavior:**

  * Move away from station to a safe distance.
* **Transitions:**

  * → `TravelRoute`, `Patrol`, `Hunt`, or `Wander` depending on role.

---

#### `Patrol`

* **Used by:** police/military, some researchers or convoys.
* **Behavior:**

  * Follow a local route inside system.
  * Run periodic scans on nearby ships.
* **Transitions:**

  * → `Engage` if hostile or criminal target found.
  * → `CallForHelp` if enemy strength high.
  * → `TravelRoute` when patrol done or reassigned.

---

#### `Guard`

* **Used by:** escorts, station guards, some military.
* **Behavior:**

  * Maintain position near a protected asset (station, convoy leader, anomaly).
* **Transitions:**

  * → `Engage` when enemy enters guard radius.
  * → `Flee` only if asset lost and morale very low.
  * → `Escort` when guard target starts moving as convoy.

---

#### `Hunt`

* **Used by:** pirates, some aggressive factions.
* **Behavior:**

  * Move in patterns through low law regions / belts / trade routes.
  * Evaluate passing ships as potential prey.
* **Transitions:**

  * → `Engage` after selecting target (attack/extort).
  * → `TravelRoute` if switching hunting grounds.
  * → `Flee` if strong patrol appears.

---

#### `Escort`

* **Used by:** escorts, bodyguards, convoy defenders.
* **Behavior:**

  * Maintain formation around leader.
  * Utility chooses when to break formation to intercept threats.
* **Transitions:**

  * → `Engage` when intercepting attacker.
  * → `Flee` if convoy collapses and morale low.
  * → `Idle` or `Patrol` if leader is gone/mission complete.

---

#### `Engage`

* **Used by:** pirates, police, escorts, angry traders, etc.
* **Behavior:**

  * Select target via utility:

    * Threat level, distance, faction hatred, player rep.
  * Decide range behavior:

    * Close in, kite, circle, etc.
* **Transitions:**

  * → `Flee` if morale breaks / hull low / outnumbered.
  * → `Surrender` in rare cases (morale low + mercy from enemy).
  * → `TravelRoute` / `Patrol` / `Guard` after combat ends.

---

#### `Flee`

* **Used by:** any role.
* **Behavior:**

  * Move away from threat towards:

    * Nearest safe station.
    * System exit (hyperspace).
  * Avoid direct collision with enemies if possible.
* **Transitions:**

  * → `TravelRoute` or `Docking` on successful escape.
  * → `Engage` again if forced into corner and morale recovers a bit (optional).
  * → Destroyed if caught.

---

#### `CallForHelp`

* **Used by:** traders, couriers, diplomats, tourists, researchers, some police.
* **Behavior:**

  * Broadcast distress/summon to faction/police.
  * Continue current behavior: usually `Flee` or defensive `Engage`.
* **Transitions:**

  * → `Flee` (common pairing).
  * → `Engage` (escorts or courageous captains).
  * → back to previous state after some delay or if help arrives.

---

#### `Surrender`

* **Used by:** traders, couriers, tourists, some researchers.
* **Behavior:**

  * Cease fire, stop engines / drift.
  * Possibly drop cargo or pay extortion (game design choice).
* **Transitions:**

  * → `Flee` after delay if enemy ignores surrender.
  * → `TravelRoute` if allowed to go.
  * → Destroyed if the attacker is brutal.

---

#### `Wander`

* **Used by:** tourists/wanderers, some civilians.
* **Behavior:**

  * Move from point to point in scenic / interesting areas.
* **Transitions:**

  * → `Flee` if threatened.
  * → `Idle` or `TravelRoute` when leaving system / done sightseeing.

---

#### `StudyAnomaly`

* **Used by:** researchers.
* **Behavior:**

  * Orbit anomaly at safe radius.
* **Transitions:**

  * → `Flee` if anomaly spawns threats.
  * → `TravelRoute` when study completes.
  * → `Engage` if forced to fight.

---

### 1.5 Role → State Matrix (Phase 1)

| Role       | Typical States Used                                                 |
| ---------- | ------------------------------------------------------------------- |
| Trader     | Idle, TravelRoute, Docking, Undocking, Flee, CallForHelp, Surrender |
| Pirate     | Idle, Hunt, Engage, Flee, TravelRoute                               |
| Police     | Idle, Patrol, Guard, Engage, Flee, TravelRoute                      |
| Miner      | Idle, TravelRoute, Docking, Flee                                    |
| Escort     | Escort, Guard, Engage, Flee, TravelRoute                            |
| Tourist    | Wander, TravelRoute, Idle, Flee                                     |
| Diplomat   | TravelRoute, Docking, Escort (as leader), Flee, CallForHelp         |
| Courier    | TravelRoute, Docking, Flee, CallForHelp                             |
| Researcher | TravelRoute, StudyAnomaly, Docking, Flee, CallForHelp               |

That’s enough to implement Phase 1 behavior without the doc ballooning.



