extends Node
class_name AIManager

var agents: Array[AgentBrain] = []

func register_agent(agent: AgentBrain) -> void:
	if agent == null:
		return
	if agents.has(agent):
		return
	agents.append(agent)

func unregister_agent(agent: AgentBrain) -> void:
	if agent == null:
		return
	agents.erase(agent)

func get_agents() -> Array[AgentBrain]:
	return agents.duplicate()

# You can expand this later for:
# - time-sliced heavy logic
# - debug HUD integration
# - global AI toggles
