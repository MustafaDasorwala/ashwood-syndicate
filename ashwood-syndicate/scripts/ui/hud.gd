class_name Hud
extends CanvasLayer

## The player-facing readout: date, deadline, vote count, and a running log of
## the clues the background simulation leaves behind.
##
## The log matters mechanically, not just cosmetically. The design docs warn
## that invisible background maths reads as the game cheating, so every gossip
## exchange and every NPC breaking from their routine surfaces here — without
## revealing the underlying numbers.

const MAX_LOG_LINES := 8

## Screen corner a panel is pinned to. Not named `Corner` — that collides with
## Godot's own global enum, and the parameter annotation silently resolves to
## the built-in instead of this one.
enum PanelCorner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT }

const MARGIN := 10.0

var sim: TownSim

var _clock_label: Label
var _vote_label: Label
var _log_label: Label
var _inspector: Label
var _log_lines: Array[String] = []


func setup(p_sim: TownSim) -> void:
	sim = p_sim
	_refresh()
	# The briefing was already drawn once, during `_build`, with no simulation to
	# read — so without this the player never sees who they are running against.
	inspect(null)


func _ready() -> void:
	layer = 10
	_build()

	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.deadline_reached.connect(_on_deadline_reached)
	EventBus.gossip_exchanged.connect(_on_gossip_exchanged)
	EventBus.seeking_started.connect(_on_seeking_started)


func _build() -> void:
	# Status panel, top left: the date and the vote count.
	var status := _make_panel(PanelCorner.TOP_LEFT, 300)
	var status_column := _make_column(status)
	_clock_label = _make_label(status_column, 15, Color("f0e6d0"))
	_vote_label = _make_label(status_column, 11, Color("b9b0a0"))

	# Clue log, bottom left. Kept apart from the status panel so a burst of
	# gossip cannot push the deadline out of view.
	var log_panel := _make_panel(PanelCorner.BOTTOM_LEFT, 300)
	_log_label = _make_label(_make_column(log_panel), 10, Color("cfc6b4"))
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Inspector, top right: who is selected and what can be done to them.
	var inspect_panel := _make_panel(PanelCorner.TOP_RIGHT, 250)
	var inspect_column := _make_column(inspect_panel)
	_inspector = _make_label(inspect_column, 11, Color("e0d8c4"))
	_inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	inspect_column.add_child(HSeparator.new())

	var controls := _make_label(inspect_column, 10, Color("9a9284"))
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.text = _controls_text()

	inspect(null)


## The rules of the game, on screen, because nothing here is discoverable.
static func _controls_text() -> String:
	var lines: Array[String] = [
		"WASD or arrows to walk. CLICK open ground to walk there.",
		"CLICK A PERSON to go and talk to them. SPACE talks to",
		"whoever is already beside you.",
		"",
		"In conversation, TYPE whatever you want to say.",
		"They answer in character. Talking is free — only",
		"an actual attempt on them costs an hour.",
		"",
		"The listed lines are suggestions, clickable with",
		"1-9. Outside a conversation these shortcuts do",
		"the same thing directly:",
		"",
	]
	for kind in PlayerActions.DEFINITIONS:
		lines.append("[%s] %s — %s" % [
			PlayerActions.key_for(kind), PlayerActions.label_for(kind), PlayerActions.hint_for(kind)
		])
	lines.append("")
	lines.append("One approach per hour. Anyone in the room sees it.")
	lines.append("[0] pause  [1] [2] [3] speed")
	return "\n".join(lines)


## A dark, readable container pinned to a corner.
##
## Anchors are set before offsets deliberately: `set_anchors_preset` clears the
## existing offsets, so assigning position first put the log and inspector
## panels off-screen entirely.
func _make_panel(corner: PanelCorner, width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	match corner:
		PanelCorner.TOP_RIGHT:
			panel.anchor_left = 1.0
			panel.anchor_right = 1.0
			panel.offset_left = -(width + MARGIN)
			panel.offset_right = -MARGIN
			panel.offset_top = MARGIN
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		PanelCorner.BOTTOM_LEFT:
			panel.anchor_top = 1.0
			panel.anchor_bottom = 1.0
			panel.offset_left = MARGIN
			panel.offset_right = MARGIN + width
			panel.offset_bottom = -MARGIN
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_:
			panel.offset_left = MARGIN
			panel.offset_right = MARGIN + width
			panel.offset_top = MARGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.055, 0.07, 0.88)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	add_child(panel)
	return panel


func _make_column(parent: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	parent.add_child(column)
	return column


func _make_label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _refresh() -> void:
	if sim == null:
		return

	var meridiem: String = "night" if GameClock.is_night() else "day"
	_clock_label.text = "Day %d of %d — %02d:00 (%s)" % [
		GameClock.day + 1, GameClock.TOTAL_DAYS, GameClock.hour, meridiem
	]

	# The standings must show the rivals too, or the player cannot tell whether
	# a vote was never won or has just been taken from them.
	var tally: Dictionary = sim.tally_votes()
	var counts: Dictionary = tally["counts"]
	var standings: Array[String] = []
	for candidate_id in sim.candidate_ids:
		var who: String = "You"
		if candidate_id != Agent.PLAYER_ID:
			var rival: Agent = sim.agent_by_id(candidate_id)
			who = rival.short_name() if rival != null else str(candidate_id)
		standings.append("%s %d" % [who, counts.get(candidate_id, 0)])

	var abstaining: int = tally["total"]
	for candidate_id in counts:
		abstaining -= counts[candidate_id]

	_vote_label.text = "%s   ·   undecided %d   ·   need %d   ·   %dh left" % [
		"   ".join(standings), abstaining, tally["required"], GameClock.hours_remaining()
	]


## Adds a line to the visible clue log.
func log_clue(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.pop_front()
	_log_label.text = "\n".join(_log_lines)


## What the game is, shown whenever nobody is selected.
##
## The premise used to be stated once, in small type on the title screen, and
## never again — so a player who clicked past it spent seven days being told to
## "win 6 of 10 votes" without ever learning votes *for what*. Naming the office,
## the rivals and the arithmetic here costs nothing and is the difference between
## a systemic game and an inscrutable one.
func _briefing() -> String:
	# No hand-wrapping: the label autowraps, and manual breaks fought it into
	# ragged half-lines.
	var lines: Array[String] = [
		"YOU ARE STANDING FOR LEADER OF ASHWOOD.",
		"",
		"The old leader is dead. In seven days the ten people of this town choose a successor. You need six of them.",
		"",
	]

	# The panel is built and drawn once before `setup` hands it the simulation,
	# so the briefing has to stand on its own without one.
	if sim == null:
		lines.append("Click someone to read them.")
		return "\n".join(lines)

	var rivals: Array[String] = []
	for candidate in sim.candidate_ids:
		if candidate == Agent.PLAYER_ID:
			continue
		var rival: Agent = sim.agent_by_id(candidate)
		if rival != null:
			rivals.append(rival.display_name)

	if not rivals.is_empty():
		lines.append("Standing against you: %s. They campaign every hour too, and they vote for themselves — so six of ten means winning six of the other eight." % " and ".join(rivals))
		lines.append("")

	lines.append("Click someone to read them.")
	return "\n".join(lines)


## Shows one inhabitant's readable state. Deliberately qualitative — the player
## sees a mood and a rumour count, never the raw relationship score.
func inspect(agent: Agent) -> void:
	if agent == null:
		_inspector.text = _briefing()
		return

	var opinion: float = agent.opinion_of_player()
	var mood: String = "hostile"
	if opinion > RelationshipBook.VOTE_THRESHOLD:
		mood = "committed"
	elif opinion > 60.0:
		mood = "warm"
	elif opinion > 40.0:
		mood = "guarded"
	elif opinion > 20.0:
		mood = "suspicious"

	# Who they currently back matters more than their raw regard for you, since
	# the vote is relative.
	var backing: String = "undecided"
	var ballots: Dictionary = sim.tally_votes()["ballots"]
	var choice: StringName = ballots.get(agent.id, &"")
	if choice == Agent.PLAYER_ID:
		backing = "backing YOU"
	elif choice != &"":
		var rival: Agent = sim.agent_by_id(choice)
		backing = "backing %s" % (rival.short_name() if rival != null else str(choice))

	var leverage: String = ""
	var hidden: Array[Secret] = sim.secrets_about(agent.id)
	if sim.knows_secret_of(Agent.PLAYER_ID, agent.id):
		leverage = "\nYou know what they did. [K] to use it."
	elif not hidden.is_empty():
		leverage = "\nThey are hiding something. [P] to probe."

	# Their ties are what make them predictable — and what can be used.
	var ties: Array[String] = []
	for relation in sim.relations.relations_of(agent.id):
		if RelationGraph.is_hidden(relation["kind"]):
			continue  # The player has to find these out for themselves.
		var other: Agent = sim.agent_by_id(relation["other"])
		if other == null:
			continue
		ties.append("%s %s" % [
			RelationGraph.Kind.keys()[relation["kind"]].to_lower(), other.short_name()
		])
	var tie_text: String = "\n" + ", ".join(ties) if not ties.is_empty() else ""

	_inspector.text = "%s\n%s · %s\n%s%s\nholds %d rumour(s) about you%s" % [
		agent.display_name,
		TownGrid.zone_name(agent.current_zone),
		mood,
		backing,
		tie_text,
		agent.ledger.about(Agent.PLAYER_ID).size(),
		leverage,
	]


## Narrates the outcome of an approach in the clue log.
##
## Deliberately qualitative — the player is told the direction and rough size of
## what happened and who saw it, never the underlying numbers.
func report_action(target: Agent, report: Dictionary) -> void:
	var delta: float = report["target_delta"]
	log_clue("%s %s: %s" % [report["label"], target.short_name(), _describe_delta(delta)])

	var witnesses: Array = report["witnesses"]
	if witnesses.is_empty():
		return

	var names: Array[String] = []
	for witness_id in witnesses:
		var witness: Agent = sim.agent_by_id(witness_id)
		if witness != null:
			names.append(witness.short_name())

	if not names.is_empty():
		log_clue("  ...seen by %s. %s" % [
			", ".join(names), _describe_delta(report["witness_delta"])
		])


static func _describe_delta(delta: float) -> String:
	if delta > 8.0:
		return "they are won over"
	if delta > 2.0:
		return "they warm to you"
	if delta > 0.5:
		return "a small gain"
	if delta < -8.0:
		return "they are furious"
	if delta < -2.0:
		return "they turn against you"
	if delta < -0.5:
		return "a small loss"
	return "no visible effect"


func _on_hour_changed(_day: int, _hour: int) -> void:
	_refresh()


func _on_day_changed(day: int) -> void:
	log_clue("— Day %d breaks over Ashwood —" % (day + 1))


func _on_deadline_reached() -> void:
	var tally: Dictionary = sim.tally_votes()
	var verdict: String = "You are the leader of Ashwood." if tally["won"] else "The town chose otherwise."
	log_clue("VOTE: %d of %d. %s" % [tally["votes_for"], tally["total"], verdict])


func _on_gossip_exchanged(speaker_id: StringName, listener_id: StringName, _token: MemoryToken) -> void:
	var speaker: Agent = sim.agent_by_id(speaker_id)
	var listener: Agent = sim.agent_by_id(listener_id)
	if speaker == null or listener == null:
		return
	# No content is revealed — only that words were exchanged, which is the
	# player's cue to go find out what was said.
	log_clue("%s speaks with %s." % [speaker.display_name, listener.display_name])


func _on_seeking_started(npc_id: StringName, target_id: StringName) -> void:
	var seeker: Agent = sim.agent_by_id(npc_id)
	var target: Agent = sim.agent_by_id(target_id)
	if seeker == null or target == null:
		return
	log_clue("%s abandons their work, looking for %s." % [seeker.display_name, target.display_name])
