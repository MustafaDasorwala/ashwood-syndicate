class_name BriefingScreen
extends CanvasLayer

## The situation, the objective and how to act on it, shown once before day one.
##
## The title screen already carries a two-line blurb, but it sits above a seed
## field and a Begin button, and it is read as flavour and clicked past. By the
## time the town is on screen the player has a HUD telling them to "win 6 of 10
## votes" and no idea votes for what, who they are, or that the two people
## campaigning against them exist.
##
## So this is deliberately a wall the player has to dismiss, and it names the
## rivals from the live simulation rather than from hardcoded text — a
## procedural town has neither Thorne nor Yolen in it.
##
## The clock does not start until it closes.

signal dismissed()

## Width of the panel: two columns of readable measure, side by side.
const PANEL_WIDTH := 860.0

var _root: PanelContainer


func present(sim: TownSim) -> void:
	layer = 28
	_build(sim)


func _build(sim: TownSim) -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.03, 0.045, 0.92)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	_root = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.075, 0.98)
	style.border_color = Color("f0d9a0")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(22)
	_root.add_theme_stylebox_override("panel", style)
	centre.add_child(_root)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_root.add_child(outer)

	_heading(outer, "ASHWOOD, AND WHAT YOU WANT FROM IT", 20, Color("f0d9a0"))

	# The prose scrolls and the button does not. On a short window an unscrolled
	# briefing pushes its own dismiss button off the bottom of the screen, which
	# leaves the player staring at text they cannot get past.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	# Two columns. In one column this briefing is taller than the window and the
	# last section — the one that explains why Expose exists — falls below the
	# fold, where it may as well not be written. The window is far wider than it
	# is short, so the space to spend is horizontal.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(columns)

	var left := _sub_column(columns)
	_body(left, _situation(sim))
	left.add_child(HSeparator.new())
	_heading(left, "HOW YOU WIN", 13, Color("d8c89a"))
	_body(left, _objective(sim))

	var right := _sub_column(columns)
	_heading(right, "WHAT TO DO", 13, Color("d8c89a"))
	_body(right, _how_to_play())
	right.add_child(HSeparator.new())
	_heading(right, "THREE THINGS THAT DECIDE GAMES", 13, Color("d8c89a"))
	_body(right, _warnings(), Color("b09a78"))

	var begin := Button.new()
	begin.text = "Begin — seven days"
	begin.add_theme_font_size_override("font_size", 15)
	begin.pressed.connect(_close)
	outer.add_child(begin)

	_scroll = scroll
	_columns = columns

	begin.grab_focus()
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


## Sizes the scrolling region to its content, capped by the window.
##
## Constraining the panel itself instead padded it out to the full window height
## and left a field of empty panel under the text. The text decides the height;
## the window only decides when to stop.
func _fit_to_viewport() -> void:
	if _scroll == null or _columns == null:
		return
	await get_tree().process_frame

	var available: float = get_viewport().get_visible_rect().size.y - VIEWPORT_MARGIN - CHROME_HEIGHT
	var content: float = _columns.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0, minf(content, maxf(available, MIN_SCROLL_HEIGHT)))


## Breathing room around the panel, roughly what the title and button occupy,
## and a floor so a very short window still shows something scrollable.
const VIEWPORT_MARGIN := 48.0
const CHROME_HEIGHT := 120.0
const MIN_SCROLL_HEIGHT := 180.0

var _scroll: ScrollContainer
var _columns: HBoxContainer


## One of the two side-by-side columns.
func _sub_column(row: HBoxContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	return column


func _heading(column: VBoxContainer, text: String, size: int, colour: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	column.add_child(label)


func _body(column: VBoxContainer, text: String, colour: Color = Color("cfc8ba")) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)


func _situation(sim: TownSim) -> String:
	return (
		"Ashwood is a frontier town of ten people, and its leader is dead. In "
		+ "seven days the town chooses a successor, and you are standing for it.\n\n"
		+ "You are not from here. Nobody owes you anything, these ten have known "
		+ "each other for years, and most of them are hiding something."
	)


func _objective(sim: TownSim) -> String:
	var rivals: Array[String] = []
	if sim != null:
		for candidate in sim.candidate_ids:
			if candidate == Agent.PLAYER_ID:
				continue
			var rival: Agent = sim.agent_by_id(candidate)
			if rival != null:
				rivals.append(rival.display_name)

	var text: String = "Win six of the ten votes by the end of day seven.\n\n"
	if rivals.is_empty():
		return text + "You are not the only one standing."

	return text + (
		"%s are standing too and campaign every hour you do. They vote for "
		% " and ".join(rivals)
		+ "themselves, so six of ten means winning six of the other eight.\n\n"
		+ "The vote is relative: people back whoever they favour most and "
		+ "abstain when torn. Being liked is not enough if a rival is liked more."
	)


func _how_to_play() -> String:
	return (
		"Walk with WASD, or click open ground. Click a person to go and talk.\n\n"
		+ "In conversation, type whatever you like and they answer in character. "
		+ "Talking is free, so ask about their neighbours, their work, whoever "
		+ "they resent — that is how you learn what will move them. Suggested "
		+ "lines sit under the box if you would rather pick than type.\n\n"
		+ "Trying to actually move someone — a favour, a bribe, a threat — costs "
		+ "an hour of the seven days."
	)


func _warnings() -> String:
	return (
		"Anyone in the room sees what you do. Bribing a man in front of the "
		+ "sheriff costs more than it gains.\n\n"
		+ "Charm has a ceiling. Favours and flattery will only carry one person "
		+ "so far, and a rival's oldest friend sits above it.\n\n"
		+ "So: secrets. Everyone has one. Earn enough trust and it may slip out "
		+ "— and a secret usually belongs to two people, one of whom is standing "
		+ "against you."
	)


func _close() -> void:
	dismissed.emit()
	queue_free()


## Enter or Escape dismisses it too. A modal that can only be closed by finding
## the right button is a modal people resent.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = (event as InputEventKey).keycode
	if key == KEY_ENTER or key == KEY_ESCAPE or key == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_close()
