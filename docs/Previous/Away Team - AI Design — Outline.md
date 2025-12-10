
# Away Team AI Design — Outline

This is more of a design skeleton you can grow into a full doc later. Think something like `docs/ai_away_team_outline.md`.

### 2.1 Goals

* Tactical combat with:

  * Cover, flanking, area denial, abilities.
* Coexistence of:

  * Hostile enemies.
  * Civilians.
  * Neutral guards.
  * Friendly followers / party members.
* Pacing-agnostic:

  * Works for RTwP **or** turn-based.

---

### 2.2 Core Architecture

* **AgentBrain** (same conceptual entity as flight):

  * Roles: soldier, guard, civilian, medic, elite, boss, follower, etc.
  * Personality: aggression, bravery, caution, discipline, mercy.
  * Morale: as in space, but with stronger effect on panic/flee.

* **ActorAgentController**:

  * Uses a `MovementProvider` abstraction:

    * Phase 1: grid + A* (cover tiles)
    * Future: navmesh-based implementation
  * Commands:

    * `move_to(tile)`
    * `move_to_cover(tile)`
    * `face(target_or_dir)`
    * `use_ability(ability_id, target)`

* **Perception**:

  * 2D LOS checks.
  * Awareness states: unaware → suspicious → alerted.
  * Sound / noise events (gunfire, explosions, running).

---

### 2.3 Movement & Pathfinding

**MovementProvider (Phase 1):**

* Grid:

  * Tiles flagged with:

    * walkable / blocked
    * cover rating (none, half, full)
* APIs:

  * `find_path(start_tile, end_tile)`
  * `find_cover_positions(around_tile, threat_position)`
  * `is_visible(from_tile, to_tile)`
* A* for pathfinding, cached or time-sliced by AIManager.

---

### 2.4 Combat States (FSM)

Core states (for hostiles and guards):

* `Idle`
* `GuardPost`
* `PatrolRoute`
* `InvestigateNoise`
* `Alerted`
* `EngageRanged`
* `EngageMelee` (if applicable)
* `TakeCover`
* `Flank`
* `Retreat`
* `Flee`
* `CallForBackup`

Civilians:

* `Idle`
* `Wander`
* `PanicFlee`
* `Cower` (optional)

Friendly followers:

* `FollowLeader`
* `EngageSupport` (attack nearest, assist)
* `HoldPosition`
* `RetreatWithLeader`

---

### 2.5 Utility Decisions (Tactics)

Inside `Alerted` / `Engage` states, utility scoring decides:

* Whether to:

  * Stay in current cover and shoot.
  * Move to better cover.
  * Advance / flank.
  * Fall back.
* Target selection:

  * Lowest HP.
  * Highest threat (DPS, special abilities, player).
  * Closest.
* Ability usage:

  * Heal when ally HP < threshold.
  * Grenade when multiple enemies are clustered.
  * Shield when under focus fire.

Inputs pulled from:

* Personality (aggression, caution, discipline).
* Morale.
* Local map (cover rating, distance).
* Squad context (# allies, # enemies).

---

### 2.6 Civilians & Neutral AI

**Civilians:**

* Triggered panic when:

  * Weapon fired in radius.
  * Enemy seen.
* Decide:

  * Flee to safe zones (exits, secure rooms).
  * Hide behind cover if cornered.

**Neutral Guards:**

* `GuardPost`:

  * Watch for criminal actions or hostile factions.
* On provocation:

  * `Warn` → `Engage` if ignored.
* May call reinforcements (spawning additional guards).

---

### 2.7 Party AI & Player Control

* Party members:

  * Obey:

    * Direct commands (move here, attack this, hold position).
    * Stance settings (aggressive / defensive / passive / healer).
  * Use abilities auto based on simple rules (overridable later).
* AI decisions paused/slowed in:

  * Turn-based mode: 1 “AI tick” per turn.
  * RTwP: periodic ticks (e.g. every 0.25–0.5 seconds).

---

### 2.8 Phase Plan (Away Team)

**Phase A (MVP):**

* Grid + A* with cover flags.
* Basic states:

  * GuardPost, PatrolRoute, Alerted, EngageRanged, Flee.
* Civilians with simple panic flee.
* Followers that just “follow & shoot”.

**Phase B:**

* Flanking, better cover selection, retreat logic.
* Backup calls, simple squad coordination.

**Phase C:**

* Personality and morale fully integrated.
* Named NPCs with special behaviors.
* Complex multi-stage encounters.

That’s enough structure to later turn into a full doc without decisions changing.