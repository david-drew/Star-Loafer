# Star Loafer Comms System Design

Filename: `Comms_Design.md`  
Scope: Hails, broadcasts, news, rumors, and comm-driven interactions between player, NPCs, and locations.  
Dependencies: Narrative Integration Layer (Lore 07), Quick Start JSON Pack (Lore 08).  
Version: v1

---

## 1. Goals & Principles

The Comms System is the runtime backbone that delivers all in-world communication:

- **Diegetic-first:** Information reaches the player via believable channels: hails, radio, beacons, PAs, brokers, rumors, blackbox logs.
- **Entity-agnostic:** Any actor (player ship, NPC ship, station, planet, anomaly, faction node) can send and receive comms.
- **Data-driven:** Content lives in JSON templates (lore packs, tensions, faction voices). Code consumes packets, not hardcoded strings.
- **Decoupled:** Comms does not directly change reputation, markets, or missions. It emits events. Other systems subscribe and react.
- **Non-intrusive:** Incoming hails use a small HUD cue. Player opts in. Ignoring (explicit or by timeout) is valid and meaningful.
- **Symmetric:** Player can hail actors. Actors can accept, delay, or ignore based on AI profiles and situation.
- **Narrative-aligned:** Integrates with the Narrative Integration Layer so that simulation → narrative → comms → player is a clean pipeline.

This document describes the architecture and data contracts. Actual content lives in external JSON packs.

---

## 2. Core Runtime Concepts

### 2.1 CommEndpoint

A `CommEndpoint` marks an entity as comm-capable.

Attached to:
- Player ship
- NPC ships
- Stations and platforms (trade hubs, shipyards, labs, habitats, etc.)
- Inhabited planets/moons
- Beacons, anomalies, derelicts, black sites
- Virtual endpoints (faction HQs, galactic news wires)

Key properties (data-facing):

- `id` — Stable identifier (e.g. `ship_player`, `station_veridian_spindle`, `planet_khepri`).
- `type` — `ship`, `station`, `planet`, `beacon`, `faction_node`, `anomaly`, etc.
- `faction_id` — Owning / associated faction.
- `channels` — List of comm channels this endpoint can use.
- `capabilities`:
  - `can_initiate_hail`
  - `can_receive_hail`
  - `can_broadcast`
- `range_profile` — `short`, `system`, `sector`, `galaxy`, etc.
- `ai_profile_id` — Optional; links to Comm AI behavior.

Runtime:
- Endpoints register/unregister with `CommsManager` (e.g. via autoload or EventBus).
- Endpoints are dumb: they expose metadata; logic lives in `CommsManager` + AI + narrative systems.

---

### 2.2 CommChannel

A `CommChannel` defines how and where messages travel.

Examples:
- `direct` — Targeted hails (ship ↔ ship/station/planet).
- `distress` — SOS calls.
- `authority` — Lawful patrols, customs, military.
- `trade_news` — Price signals, shortages, surpluses.
- `system_broadcast` — Public system-wide info.
- `galactic_news` — Macro events.
- `rumor_net` — Low-confidence leads.
- `black_market` — Shady encrypted channels.
- `internal` — Player ship AI / crew chatter.

Channel properties:
- Who can publish / subscribe (`allows_initiator`, `allows_broadcast`).
- Visibility rules (`always`, `requires_unlock`, `jammed`, etc.).
- Default priority & UI treatment.
- Whether it can initiate a `CommSession` or is read-only.

Implementation:
- Defined in `comm_channels.json` (Quick Start compatible).
- `CommsManager` uses this to validate and route messages.

---

### 2.3 CommMessage & Templates

A `CommMessage` is a concrete, runtime instance of communication.

It is usually spawned from a JSON template:

- `id`
- `channel_id`
- `category` — `hail`, `broadcast`, `news`, `rumor`, `warning`, `threat`, `offer`, `mission_offer`, `tutorial`, etc.
- `from_endpoint` / `to_endpoint` or `audience` rules
- `priority` — `low`, `normal`, `urgent`, `blocking` (for UI routing)
- `ttl` — How long the message remains actionable/visible
- `interactive` — Whether it can open a `CommSession`
- `text` / `lines` / `dialogue_id` / `session_type`
- `conditions` — World-state filters (rep tiers, cargo, tensions, archetypes, etc.)
- `on_accept` / `on_ignore` / `on_timeout` — Event hooks (payload only; no direct side-effects)

Authoring uses **templates**:
- Stored in `comm_message_templates.json`.
- Use the same macro style as Quick Start packs:
  - `$SYSTEM`, `$FACTION`, `$TENSION`, `$GOOD`, `$DELTA`, etc.
- Evaluated by the Narrative Integration Layer or a comm content builder before enqueue.

---

### 2.4 CommSession

A `CommSession` represents an active, focused interaction created when a hail is accepted.

Examples:
- Dialogue with branching choices.
- Cargo scan / surrender / bribe prompt.
- Mission/contract offer screen.
- Trade or service offer UI.
- News / dossier viewer.
- One-shot flavor exchange.

Core rules:
- Created only after an explicit accept (player or AI).
- Owned by `CommsManager` but **delegates** to specialized systems:
  - Dialogue system
  - Mission/contract system
  - Market/trade system
  - Faction/reputation view
- On completion or cancellation, emits `COMM_SESSION_ENDED`.

Comms never assumes what “accepting” means; it only hands off via events and metadata.

---

### 2.5 Comm AI Profiles

`CommAIProfile` controls how non-player endpoints behave:

- When to initiate hails (patrol scans, pirate ultimatums, trader offers).
- How to respond to incoming hails.
- When to ignore, delay, or terminate comms.

Defined in `comm_ai_profiles.json` as:
- Baseline accept/ignore chances.
- State-based modifiers (in combat, fleeing, docking, etc.).
- Personality traits (formal, taunting, skittish, bureaucratic).
- Faction voice hooks (prefaces, lexicon hints; see Lore 07).

This makes:
- Patrols usually answer, except when busy.
- Pirates sometimes ignore pleading.
- Stations almost always answer, unless in lockdown.
- Rare “disrespectful” behavior systemic and tunable.

---

## 3. Event Model & Flows

The Comms System is **event-driven** on top of your central EventBus.

### 3.1 Key Events

Produced & consumed as needed (names indicative):

- `COMM_OUTGOING_HAIL_REQUESTED`
- `COMM_HAIL_CREATED`            # pending hail is available
- `COMM_HAIL_PRESENTED_TO_PLAYER`
- `COMM_HAIL_ACCEPTED`
- `COMM_HAIL_IGNORED`            # player explicitly ignores/dismisses
- `COMM_HAIL_TIMED_OUT`          # hail expired unanswered
- `COMM_HAIL_IGNORED_BY_TARGET`  # NPC/endpoint chooses not to respond
- `COMM_SESSION_STARTED`
- `COMM_SESSION_ENDED`
- `COMM_BROADCAST_PUBLISHED`
- `COMM_NEWS_ITEM_ADDED`
- `COMM_RUMOR_ADDED`

Downstream systems (factions, AI combat, missions, economy, codex) subscribe and react.

---

### 3.2 Flow: NPC hails Player

1. NPC or narrative logic emits `COMM_OUTGOING_HAIL_REQUESTED` with:
   - `from_endpoint`
   - `to_endpoint = player`
   - `template_id` or criteria
2. `CommsManager`:
   - Validates channel, range, conditions.
   - Spawns a pending `CommMessage`.
   - Emits `COMM_HAIL_CREATED`.
3. UI:
   - Displays small, non-blocking hail popup with source + icon.
4. Player choices:
   - Accept → `COMM_HAIL_ACCEPTED` → `COMM_SESSION_STARTED` → delegated handling.
   - Explicit ignore/dismiss → `COMM_HAIL_IGNORED`.
   - No response until `ttl` → `COMM_HAIL_TIMED_OUT`.

Other systems:
- Faction/AI listen to ignored/timeouts (e.g. patrol offended, pirate escalates, ally mildly disappointed).

---

### 3.3 Flow: Player hails NPC (with NPC ignore logic)

1. Player chooses target and “Hail”.
2. `CommsManager` emits `COMM_OUTGOING_HAIL_REQUESTED` with:
   - `from = player`, `to = target`.
3. Target’s `CommAIProfile` evaluates:
   - Current state (idle, docking, in_combat, fleeing).
   - Relationship (rep, faction stance, tension).
   - Personality flags.
4. Possible outcomes:
   - **Accept:** Creates pending hail back → `COMM_HAIL_CREATED` → usual accept → session.
   - **Delay:** Queue response until safe/idle.
   - **Ignore (snub):** No hail created; emit `COMM_HAIL_IGNORED_BY_TARGET`.
   - **Jam/Block:** Optional variant of ignore with different flavor.

Guidelines:
- Hostile ships may ignore peaceful hails if already committed to attack.
- Arrogant elites or pirates may occasionally ignore for tone.
- Stations and lawful patrols rarely ignore unless in lockdown or under fire.
- Rates controlled purely by `comm_ai_profiles.json`.

---

### 3.4 Flow: Broadcasts & News

1. Simulation / narrative layer generates narrative packets:
   - Beacon bulletins
   - Dock PA announcements
   - Radio news (Galactic Pulse)
   - Rumors
2. For each, it calls into `CommsManager` to publish on the appropriate channel:
   - `system_broadcast`
   - `trade_news`
   - `galactic_news`
   - `rumor_net`
3. `CommsManager`:
   - Emits `COMM_BROADCAST_PUBLISHED` / `COMM_NEWS_ITEM_ADDED` / `COMM_RUMOR_ADDED`.
   - Stores items in per-channel queues with `ttl`.
4. UI:
   - Renders a radio/comms tape, system messages, station flavor, etc.
   - Player can review recent items.

Broadcasts are usually auto-accepted, non-interactive, but can:
- Attach hooks (e.g. add missions, adjust prices, update codex) via subscribed systems.

---

## 4. Integration with Narrative Integration Layer

The uploaded docs define the **Narrative Integration Layer** as the authoring and generation brain.  
The Comms System is its delivery mechanism.

### 4.1 Roles

- **Simulation Layer**
  - Maintains world state: factions, tensions, markets, POIs, encounters.
- **Narrative Integration Layer**
  - Reads world state.
  - Chooses which narrative packets to emit:
    - Beacon bulletins
    - Dock PA
    - Mission posts
    - News bulletins
    - Rumors
    - Faction hails
    - Blackbox logs
  - Uses JSON templates (Lore 08) with macros and tone packs.
- **CommsManager**
  - Turns those packets into `CommMessage`s on channels.
  - Manages pending hails & sessions.
  - Emits events for other systems.
- **Downstream Systems**
  - Missions, markets, factions, codex, encounter spawners.

### 4.2 Voice & Tone

Faction “voice skins” (from Lore 07) are applied in one of:

- Pre-authored lines in templates (recommended for consistency).
- Or by a lightweight transformation step that:
  - Adds faction-specific prefaces.
  - Adjusts a few lexical choices per faction.

Comms System itself does not enforce style; it only delivers.

---

## 5. Behavior Design: Ignoring & Consequences

### 5.1 Player Ignores

When the player ignores a hail (explicitly or by timeout):

- `COMM_HAIL_IGNORED` or `COMM_HAIL_TIMED_OUT` fires with full context.
- Example systemic reactions (implemented externally):
  - Lawful patrol: small rep penalty; flag for closer scrutiny.
  - Pirates: treat as defiance → escalate to attack or pursuit.
  - Traders: remember rudeness → slightly worse offers.
  - Allies/quests: downgrade priority, nudge alternate hooks later.

No direct side-effects in Comms; only events.

### 5.2 NPC / Actor Ignores Player

Driven entirely by `CommAIProfile`:

- Reasons:
  - In combat or executing critical maneuver.
  - Hostile and not interested in talk.
  - Disrespectful / arrogant profile.
  - Jamming / degraded comms / lockdown.
- On ignore:
  - `COMM_HAIL_IGNORED_BY_TARGET` emitted.
  - May feed UI feedback:
    - “No response.”
    - “Channel busy.” (flavor decided per AI profile/template.)
  - Other systems can listen (e.g. codex noting cultural habits).

This preserves symmetry and gives tools for personality without hardcoding.

---

## 6. UI & UX Guidelines

Not prescriptive; meant to keep everything consistent.

### 6.1 Hail Popup

- Small, non-blocking HUD element:
  - Source icon (ship/station/faction).
  - Short label: “Hail from Free Hab Patrol”.
  - Buttons: `[Open] [Dismiss]`.
- Auto-dismiss on `ttl` expiry → counts as timeout.

### 6.2 Comms Panel

Unified panel for:
- Active hail/session.
- Recent broadcasts (news, PA, beacon).
- Rumors & saved logs.
- Filters per channel: `All | Direct | News | Rumors | Blackbox`.

### 6.3 Radio / Tape

- Horizontal ticker or feed:
  - `[NEWS] Free Hab ballots close in Veridian Reach.`
  - `[RUMOR] Nomads trading charts for songs at Dock 6.`
  - `[HAIL] Patrol requests cargo scan.`
- Clicking an item opens its full card or linked UI.

### 6.4 Station & Map Hooks

- Docked:
  - Station PA and mission boards are just comms on local channels rendered in that UI.
- Map:
  - Some comms (beacons, news, rumors) can attach marker references to POIs.

---

## 7. Data Files & Contracts

The following JSON files define content and behavior.  
This design doc **references** them; they are maintained separately.

1. `comm_channels.json`
   - Channel definitions (ids, visibility, roles).

2. `comm_message_templates.json`
   - Templates for:
     - Faction hails (patrol, trader, pirate, smugglers, pilgrims, mercs, etc.).
     - System broadcasts (beacon, PA, alerts).
     - News bulletins (regional, factional, economic).
     - Rumors & hooks (POIs, derelicts, anomalies).
   - Includes macro placeholders for the Narrative Integration Layer.

3. `comm_ai_profiles.json`
   - AI profiles defining:
     - Incoming hail response probabilities.
     - Ignoring behavior based on state (in_combat, fleeing, lockdown).
     - Outgoing hail rules (who they contact, when).
   - Mapped by `ai_profile_id` from endpoints.

4. Existing packs from Lore 08 (for reference)
   - `beacons.json`, `dock_pa.json`, `missions.json`, `news.json`,
     `rumors.json`, `hails.json`, `codex_templates.json`.
   - These are producers of narrative packets; `CommsManager` is the consumer.

---

## 8. Implementation Checklist (Godot 4.5, High-Level)

**Phase 1 — Skeleton**

- [ ] Add `CommsManager.gd` as an autoload.
- [ ] Implement endpoint registration (`register_endpoint`, `unregister_endpoint`).
- [ ] Load `comm_channels.json` on startup.
- [ ] Provide `enqueue_message(packet)` and `request_hail(from, to, template_id)` APIs.
- [ ] Wire to central EventBus.

**Phase 2 — Hails & Sessions**

- [ ] Implement pending hail tracking with `ttl`.
- [ ] Emit `COMM_HAIL_CREATED`, `COMM_HAIL_ACCEPTED`, `COMM_HAIL_IGNORED`, `COMM_HAIL_TIMED_OUT`.
- [ ] Add a simple CommSession wrapper that:
  - Identifies `session_type`.
  - Emits `COMM_SESSION_STARTED`/`COMM_SESSION_ENDED`.
  - Hands off to dialogue/mission/trade UIs.

**Phase 3 — AI Profiles & Ignoring**

- [ ] Load `comm_ai_profiles.json`.
- [ ] On player hail, evaluate target AI profile to decide accept/ignore/delay.
- [ ] Emit `COMM_HAIL_IGNORED_BY_TARGET` when applicable.
- [ ] Add basic cooldowns to prevent spammy behavior.

**Phase 4 — Narrative Integration**

- [ ] Expose `CommsManager` API for Narrative Integration Layer:
  - `publish_broadcast(packet)`
  - `publish_news(packet)`
  - `publish_rumor(packet)`
- [ ] Adapt Quick Start JSON packs so their generated outputs map cleanly to comm channels.
- [ ] Ensure all such publishes are event-only; mission/economy/faction respond via subscriptions.

**Phase 5 — Polish**

- [ ] Add diegetic UI: radio tape, comm history, filters.
- [ ] Add logging for debugging (who hailed whom, which template fired).
- [ ] Tune AI profiles for how often actors ignore hails.
- [ ] Add content: more templates for factions, tensions, and rare events.

---

## 9. Design Notes

- The Comms System should never “own” story outcomes. It is a router.
- Hails, news, rumors, and PA lines are all `CommMessage`s on different channels.
- NPCs ignoring hails is a **feature**, not a bug:
  - Gives behavioral texture.
  - Exposes stakes (pirates that don’t negotiate, panicked ships that won’t answer).
  - All controlled via data.
- The Narrative Integration Layer is free to get clever:
  - Conflicting reports, propaganda, escalating rumors.
  - Comms just has to deliver them reliably and consistently.

End of document.
