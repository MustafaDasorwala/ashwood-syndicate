class_name TitleScreen
extends CanvasLayer

## Where a run is chosen: which town, and whether it is a fresh one.
##
## The simulation is frozen behind this. Nothing ticks until Begin is pressed,
## so the seven days always start when the player is actually looking.

signal begin_requested(seed_value: int, procedural: bool)

var _seed_field: LineEdit
var _procedural_box: CheckBox
var _blurb: Label


func _ready() -> void:
	layer = 30
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.03, 0.045, 0.97)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(430, 0)
	centre.add_child(column)

	var title := Label.new()
	title.text = "THE ASHWOOD SYNDICATE"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("f0d9a0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_blurb = Label.new()
	_blurb.text = (
		"The town leader is dead. In seven days Ashwood chooses a successor.\n\n"
		+ "Win six of ten votes. Two others want the same thing, and everyone "
		+ "here has something they would rather you did not know."
	)
	_blurb.add_theme_font_size_override("font_size", 12)
	_blurb.add_theme_color_override("font_color", Color("b8b0a0"))
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_blurb)

	column.add_child(HSeparator.new())

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	column.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.add_theme_font_size_override("font_size", 12)
	seed_row.add_child(seed_label)

	_seed_field = LineEdit.new()
	_seed_field.text = "20260730"
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_field)

	var reroll := Button.new()
	reroll.text = "Reroll"
	reroll.pressed.connect(_on_reroll)
	seed_row.add_child(reroll)

	_procedural_box = CheckBox.new()
	_procedural_box.text = "New town (procedural cast, ties and secrets)"
	_procedural_box.add_theme_font_size_override("font_size", 12)
	_procedural_box.toggled.connect(_on_procedural_toggled)
	column.add_child(_procedural_box)

	var start := Button.new()
	start.text = "Begin"
	start.add_theme_font_size_override("font_size", 16)
	start.custom_minimum_size = Vector2(0, 40)
	start.pressed.connect(_on_begin)
	column.add_child(start)

	var controls := Label.new()
	controls.text = "WASD or click to walk  ·  SPACE to talk  ·  0-3 speed"
	controls.add_theme_font_size_override("font_size", 10)
	controls.add_theme_color_override("font_color", Color("7d7768"))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(controls)


func _on_procedural_toggled(pressed: bool) -> void:
	_blurb.text = (
		"A town you have never seen: new people, new ties, new secrets.\n\n"
		+ "Nobody here is written. The web is woven first, then their secrets "
		+ "are derived from it, so the scandals implicate people who already "
		+ "had reason to care about each other."
	) if pressed else (
		"The town leader is dead. In seven days Ashwood chooses a successor.\n\n"
		+ "Win six of ten votes. Two others want the same thing, and everyone "
		+ "here has something they would rather you did not know."
	)


func _on_reroll() -> void:
	# Seeds are only meaningful as text the player can write down and replay,
	# so this fills the field rather than starting immediately.
	_seed_field.text = str(randi() % 9_000_000 + 1000)
	if not _procedural_box.button_pressed:
		_procedural_box.button_pressed = true


func _on_begin() -> void:
	var seed_value: int = int(_seed_field.text) if _seed_field.text.is_valid_int() else 20260730
	begin_requested.emit(seed_value, _procedural_box.button_pressed)
	queue_free()
