class_name ResultsScreen
extends CanvasLayer

## The vote, and why it went the way it did.
##
## Showing only a win or loss would make a week of social manoeuvring feel
## arbitrary. Every inhabitant's ballot is listed with the reason behind it, so
## a defeat is legible: you can see which two people you lost and to whom.

signal restart_requested()
signal new_town_requested()


func _ready() -> void:
	layer = 30


func present(sim: TownSim, tally: Dictionary) -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.03, 0.045, 0.96)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.custom_minimum_size = Vector2(520, 0)
	centre.add_child(column)

	_add_verdict(column, sim, tally)
	_add_standings(column, sim, tally)
	column.add_child(HSeparator.new())
	_add_ballots(column, sim, tally)
	_add_buttons(column)


func _add_verdict(column: VBoxContainer, sim: TownSim, tally: Dictionary) -> void:
	var won: bool = tally["won"]
	var verdict := Label.new()
	verdict.text = "YOU LEAD ASHWOOD" if won else "ASHWOOD CHOSE OTHERWISE"
	verdict.add_theme_font_size_override("font_size", 26)
	verdict.add_theme_color_override("font_color", Color("9fd18a") if won else Color("d18a8a"))
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(verdict)

	var detail := Label.new()
	if won:
		detail.text = "%d of %d votes. You needed %d." % [
			tally["votes_for"], tally["total"], tally["required"]
		]
	else:
		var leader_name: String = "nobody"
		var leader: Agent = sim.agent_by_id(tally["leader"])
		if tally["leader"] == Agent.PLAYER_ID:
			leader_name = "you"
		elif leader != null:
			leader_name = leader.display_name
		detail.text = "%d of %d votes — %d were needed. The town turned to %s." % [
			tally["votes_for"], tally["total"], tally["required"], leader_name
		]
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color("b8b0a0"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)


func _add_standings(column: VBoxContainer, sim: TownSim, tally: Dictionary) -> void:
	var counts: Dictionary = tally["counts"]
	var parts: Array[String] = []
	for candidate_id in sim.candidate_ids:
		var who: String = "You"
		if candidate_id != Agent.PLAYER_ID:
			var rival: Agent = sim.agent_by_id(candidate_id)
			who = rival.display_name if rival != null else str(candidate_id)
		parts.append("%s %d" % [who, counts.get(candidate_id, 0)])

	var standings := Label.new()
	standings.text = "   ·   ".join(parts)
	standings.add_theme_font_size_override("font_size", 14)
	standings.add_theme_color_override("font_color", Color("e8e0cc"))
	standings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(standings)


## Every ballot, with the reason. This is the part that makes a loss teachable.
func _add_ballots(column: VBoxContainer, sim: TownSim, tally: Dictionary) -> void:
	var ballots: Dictionary = tally["ballots"]

	for agent in sim.agents:
		if sim.candidate_ids.has(agent.id):
			continue

		var choice: StringName = ballots.get(agent.id, &"")
		var backed: String = "abstained"
		var tint := Color("8d8677")
		if choice == Agent.PLAYER_ID:
			backed = "backed you"
			tint = Color("9fd18a")
		elif choice != &"":
			var rival: Agent = sim.agent_by_id(choice)
			backed = "backed %s" % (rival.short_name() if rival != null else str(choice))
			tint = Color("d1a88a")

		var row := Label.new()
		row.text = "%-22s %-16s   %s" % [agent.display_name, backed, _reason(sim, agent, choice)]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", tint)
		column.add_child(row)


## Why this inhabitant voted as they did, in their own terms.
func _reason(sim: TownSim, agent: Agent, choice: StringName) -> String:
	var regard: float = agent.opinion_of_player()
	var rumours: int = agent.ledger.about(Agent.PLAYER_ID).size()

	if choice == &"":
		if regard <= Election.MIN_SUPPORT:
			return "never warmed to anyone"
		return "torn between you and another"

	if choice != Agent.PLAYER_ID:
		var rival_regard: float = agent.relationships.score_for(choice)
		if rival_regard - regard > 25.0:
			return "you were never really in it"
		return "you were close — %d rumour(s) about you" % rumours

	return "held through %d rumour(s)" % rumours if rumours > 0 else "steady all week"


func _add_buttons(column: VBoxContainer) -> void:
	column.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	var again := Button.new()
	again.text = "Same town again"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func() -> void: restart_requested.emit())
	row.add_child(again)

	var fresh := Button.new()
	fresh.text = "A different town"
	fresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fresh.pressed.connect(func() -> void: new_town_requested.emit())
	row.add_child(fresh)
