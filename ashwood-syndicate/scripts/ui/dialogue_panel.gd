class_name DialoguePanel
extends CanvasLayer

## The conversation view: who is speaking, what they said, and what you say back.
##
## You type. The listed lines are suggestions, not the vocabulary — they exist
## so a new player can see that bribery and blackmail are options at all, and
## clicking one is identical to typing your own version of it.
##
## Suggestions are numbered and selectable by keyboard as well as mouse, but
## only while the text box is empty, since otherwise typing "2 sheep" would fire
## a suggestion mid-sentence.

signal choice_picked(choice: Dictionary)
signal line_typed(text: String)
signal dismissed()

const MAX_VISIBLE_CHOICES := 8

## Kept short. A conversation is speech, and a paragraph is not speech.
const MAX_INPUT_LENGTH := 200

var _root: PanelContainer
var _speaker_label: Label
var _line_label: Label
var _choice_box: VBoxContainer
var _status_label: Label
var _input: LineEdit
var _transcript_label: RichTextLabel

var _choices: Array[Dictionary] = []
var _accepting: bool = false


func _ready() -> void:
	layer = 20
	_build()
	hide_panel()


func _build() -> void:
	_root = PanelContainer.new()
	_root.anchor_top = 1.0
	_root.anchor_bottom = 1.0
	_root.anchor_right = 1.0
	_root.offset_left = 40.0
	_root.offset_right = -40.0
	_root.offset_bottom = -30.0
	_root.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.055, 0.96)
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_root.add_child(column)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 15)
	_speaker_label.add_theme_color_override("font_color", Color("f0d9a0"))
	column.add_child(_speaker_label)

	# What has been said so far, so a long conversation can be read back rather
	# than existing only in the player's memory of the last line.
	_transcript_label = RichTextLabel.new()
	_transcript_label.bbcode_enabled = true
	_transcript_label.fit_content = false
	_transcript_label.scroll_following = true
	_transcript_label.custom_minimum_size = Vector2(0, 140)
	_transcript_label.add_theme_font_size_override("normal_font_size", 12)
	column.add_child(_transcript_label)

	# Only ever holds the waiting indicator. The reply itself goes in the
	# transcript, and printing it in both places said everything twice.
	_line_label = Label.new()
	_line_label.add_theme_font_size_override("font_size", 13)
	_line_label.add_theme_color_override("font_color", Color("8d8677"))
	column.add_child(_line_label)

	_input = LineEdit.new()
	_input.placeholder_text = "Say something…  (Enter to speak, Esc to walk away)"
	_input.max_length = MAX_INPUT_LENGTH
	_input.add_theme_font_size_override("font_size", 13)
	_input.text_submitted.connect(_on_submitted)
	column.add_child(_input)

	column.add_child(HSeparator.new())

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 2)
	column.add_child(_choice_box)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", Color("8d8677"))
	column.add_child(_status_label)


func show_panel(speaker_name: String) -> void:
	_speaker_label.text = speaker_name
	_line_label.text = ""
	_transcript_label.text = ""
	_input.text = ""
	_root.visible = true


func hide_panel() -> void:
	_root.visible = false
	_accepting = false
	_input.text = ""
	_input.release_focus()
	_clear_choices()


## Redraws the conversation so far. Called with `Conversation.transcript`.
func show_transcript(entries: Array[Dictionary], speaker_name: String) -> void:
	var parts: PackedStringArray = []
	for entry in entries:
		var who: String = str(entry.get("speaker", ""))
		var colour: String = "9fb8d0" if who == "You" else "d8c89a"
		parts.append("[color=#%s]%s:[/color] %s" % [colour, who, entry.get("line", "")])
	_transcript_label.text = "\n".join(parts)
	_speaker_label.text = speaker_name


func is_open() -> bool:
	return _root != null and _root.visible


## Whether the panel is waiting on the player rather than on a reply. Used by
## screenshot mode to capture a settled conversation rather than a "thinking".
func is_accepting() -> bool:
	return _accepting


## Shown while a reply is being written, so a slow model reads as the character
## thinking rather than as the game hanging.
func show_thinking() -> void:
	_accepting = false
	_input.editable = false
	_clear_choices()
	_line_label.text = "…"
	_status_label.text = "thinking"


## The reply is already in the transcript by the time this runs, so all that is
## left is to take the waiting indicator down.
func show_line(_line: String) -> void:
	_line_label.text = ""


func show_choices(choices: Array[Dictionary], patience: int) -> void:
	_clear_choices()
	_choices = choices.slice(0, MAX_VISIBLE_CHOICES)
	_accepting = true

	_input.editable = true
	_input.text = ""
	_input.grab_focus()

	for i in _choices.size():
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, _choices[i]["text"]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_pressed.bind(i))
		_choice_box.add_child(button)

	# Patience, not a turn budget: talking costs nothing, and only rebuffs spend
	# this. Saying so matters, because the old message told the player they had
	# three lines and they behaved accordingly.
	_status_label.text = "Talk as long as you like. %s  ·  Suggestions above are only suggestions." % [
		"They are losing patience with you." if patience <= 2 else "They are listening."
	]


func _clear_choices() -> void:
	for child in _choice_box.get_children():
		child.queue_free()
	_choices.clear()


func _on_submitted(text: String) -> void:
	if not _accepting:
		return
	if text.strip_edges().is_empty():
		return
	_accepting = false
	_input.text = ""
	line_typed.emit(text)


func _input_event_is_for_typing() -> bool:
	# Number shortcuts must not fire while the player is composing a sentence,
	# or typing "3 coins" picks suggestion three mid-word.
	return _input != null and _input.has_focus() and not _input.text.is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if not _accepting or not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var key: int = (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		dismissed.emit()
		get_viewport().set_input_as_handled()
		return

	if _input_event_is_for_typing():
		return

	var index: int = key - KEY_1
	if index >= 0 and index < _choices.size():
		_on_pressed(index)
		get_viewport().set_input_as_handled()


func _on_pressed(index: int) -> void:
	if not _accepting or index >= _choices.size():
		return
	_accepting = false
	_input.text = ""
	choice_picked.emit(_choices[index])
