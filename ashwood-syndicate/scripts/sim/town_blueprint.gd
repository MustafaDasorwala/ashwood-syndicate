class_name TownBlueprint
extends RefCounted

## Everything needed to stand up a town: the people, the web that binds them,
## what they are hiding, and who is running for the leadership.
##
## Produced either by `Roster` (the hand-authored Ashwood) or by
## `TownGenerator`. `TownSim` cannot tell the difference, which is the point.

var agents: Array[Agent] = []
var relations: RelationGraph
var secrets: Array[Secret] = []
var candidate_ids: Array[StringName] = []

## Why generation rejected earlier attempts, kept for debugging a bad seed.
var rejections: Array[String] = []


func _init(
	p_agents: Array[Agent] = [],
	p_relations: RelationGraph = null,
	p_secrets: Array[Secret] = [],
	p_candidates: Array[StringName] = []
) -> void:
	agents = p_agents
	relations = p_relations if p_relations != null else RelationGraph.new()
	secrets = p_secrets
	candidate_ids = p_candidates


func agent_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for agent in agents:
		out.append(agent.id)
	return out


func find(id: StringName) -> Agent:
	for agent in agents:
		if agent.id == id:
			return agent
	return null
