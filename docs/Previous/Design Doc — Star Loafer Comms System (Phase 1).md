
# Design Doc — Star Loafer Comms System (Phase 1)

**Version:** v1
**Scope:** Hailing, automated NPC/station messages, template-driven dialogue, EventBus communication

---

## **1. Overview**

The **Comms System** provides all player-facing communications between ships, stations, and other actors.
It handles:

* Hails (player ↔ NPC, NPC ↔ player)
* Docking messages
* Automated greetings
* Threats/extortion
* Template-driven dialogue lines
* Dialogue branching via response options
* Message emission to UI via EventBus

All messages and responses are data-driven through JSON files.

---

## **2. Architecture**

### 2.1 Core Script: `CommSystem.gd`

Responsibilities:

* Manage hails and conversation lifecycles
* Build communication context for both parties
* Select message templates from JSON
* Generate responses using AI profiles & context rules
* Emit events via EventBus
* Handle player-selected responses

### 2.2 EventBus Signals

Used for full decoupling:

```gdscript
signal hail_received(sender: Node, recipient: Node, context: Dictionary)
signal comm_message_received(message_data: Dictionary)
signal comm_response_chosen(conversation_id, response_index: int, response: Dictionary)
signal docking_approved(station: Node, ship: Node, bay_id: int)
signal docking_denied(station: Node, ship: Node, reason: String)
```

These signals allow CommPanel, NotifierPanel, DockingManager, NPC AI, and other systems to respond without direct references.

### 2.3 Conversations

Each hail spawns a **conversation dictionary** stored in `active_conversations`.
Fields include:

* `id`
* `initiator` / `recipient`
* `context`
* timestamps
* timeout tracking

Conversations support multi-turn branching.

---

## **3. Data Files**

### 3.1 `comm_message_templates.json`

Defines message categories (e.g., `npc_greeting`, `docking_approved`).
Each template contains:

* `id`, `text`
* `context_requirements`
* `base_weight`
* `response_options`
* optional timing and ignore behavior

### 3.2 `comm_ai_profiles.json`

Defines per-entity communication style:

* tone
* polite/aggressive tendencies
* frequency of warnings, threats, delays

Selected based on ship type, faction, or entity tags.

---

## **4. Message Payload Format**

CommSystem builds a structured `message_data` dictionary:

```
{
  "from_label": String,
  "from_type": String,
  "from_id": String,
  "to_label": String,
  "to_id": String,
  "channel": String,
  "message_type": String,
  "conversation_id": int,
  "turn_index": int,
  "template_id": String,
  "template_category": String,
  "text": String,
  "response_options": Array,
  "timeout_seconds": float,
  "can_be_ignored": bool,
  "context": Dictionary
}
```

EventBus emits this directly to CommPanel.

---

## **5. Flow Summary**

### 5.1 Player hails NPC/station

1. PlayerShip calls `CommSystem.initiate_hail()`.
2. CommSystem:

   * builds context
   * creates a conversation
   * emits `hail_received`
   * selects a template (`npc_greeting`, `station_greeting`)
   * emits `comm_message_received` with full payload

### 5.2 NPC replies (branching)

Player selects a response in CommPanel:

1. UI emits:
   `EventBus.comm_response_chosen(conversation_id, index, response_dict)`
2. CommSystem retrieves conversation context.
3. Follows `leads_to_category`.
4. Generates follow-up template.
5. Emits new `comm_message_received`.

### 5.3 Docking messages

DockingManager emits approval/denial.
CommSystem handles and emits comm messages using `docking_approved` / `docking_denied` templates.

---

## **6. Advantages**

* Fully data-driven
* Highly extensible
* Works for ships, stations, planets, factions
* No direct UI or gameplay dependencies
* Built on EventBus for clean decoupling
* Ready for expansions (broadcasts, NPC chatter, story beats)

---

