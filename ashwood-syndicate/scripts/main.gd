extends Node2D

## Entry point. Wires the simulation to its view layer and starts the clock.
##
## The composition order matters: the sim is built and seeded first, then views
## are attached to the agents that already exist. Nothing in the view layer can
## create or mutate simulation state.

## Seed for this playthrough. A fixed value makes a run reproducible; change it
## (or randomise it) for a fresh town.
@export var world_seed: int = 20260730

## When true, the town is generated from `world_seed` — new people, new ties,
## new secrets every seed. When false you get hand-authored Ashwood, which is
## the tutorial town and the one every balance number is tuned against.
@export var procedural: bool = false

## Speed presets cycled with the 1/2/3 keys, and 0 to pause.
const SPEED_STEPS := [0.0, 1.0, 4.0, 16.0]

var sim: TownSim
var renderer: TownRenderer
var hud: Hud
var audio: ProcAudio

var _views: Array[NpcView] = []

## Y-sorted parent for everything with a body, so depth reads correctly when
## people stand close.
var _actors: Node2D


## Carried across a scene reload so "play again" can choose the town.
## Static rather than saved, because a run is short and disposable.
static var next_seed: int = 0
static var next_procedural: bool = false

var _started: bool = false


func _ready() -> void:
	if next_seed != 0:
		world_seed = next_seed
		procedural = next_procedural
		next_seed = 0

	_build_simulation()
	_build_view()
	_seed_opening_situation()

	GameClock.reset()
	GameClock.time_scale = 0.0

	EventBus.deadline_reached.connect(_on_deadline_reached)

	if _start_capture_if_requested():
		# Screenshot mode drives the game itself. `--title` keeps the menu up so
		# it can be captured too.
		if OS.get_cmdline_user_args().has("--title"):
			_show_title()
		else:
			_begin(world_seed, procedural)
	else:
		_show_title()


func _show_title() -> void:
	var title := TitleScreen.new()
	title.name = "TitleScreen"
	add_child(title)
	title.begin_requested.connect(_on_begin_requested)


func _on_begin_requested(seed_value: int, use_procedural: bool) -> void:
	# Changing the town means rebuilding it, which is cleanest as a fresh scene.
	if seed_value != world_seed or use_procedural != procedural:
		next_seed = seed_value
		next_procedural = use_procedural
		get_tree().reload_current_scene()
		return
	_begin(seed_value, use_procedural)


## Shows the briefing, then starts the week when it is dismissed.
##
## Screenshot mode skips it, since it would sit over every capture; `--briefing`
## asks for it explicitly.
func _begin(_seed_value: int, _use_procedural: bool) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--shot") and not args.has("--briefing"):
		_start_week()
		return

	var briefing := BriefingScreen.new()
	briefing.name = "BriefingScreen"
	add_child(briefing)
	briefing.present(sim)
	briefing.dismissed.connect(_start_week)


## The clock stays at zero until the briefing closes, so the seven days never
## start while the player is still reading what the seven days are for.
func _start_week() -> void:
	_started = true
	GameClock.time_scale = 1.0


func _on_deadline_reached() -> void:
	if not _started:
		return
	_started = false
	GameClock.time_scale = 0.0
	_end_conversation()

	var results := ResultsScreen.new()
	results.name = "ResultsScreen"
	add_child(results)
	results.present(sim, sim.tally_votes())
	results.restart_requested.connect(_replay.bind(world_seed, procedural))
	results.new_town_requested.connect(_replay.bind(world_seed + 1, true))


func _replay(seed_value: int, use_procedural: bool) -> void:
	next_seed = seed_value
	next_procedural = use_procedural
	GameClock.reset()
	get_tree().reload_current_scene()


## Screenshot mode, driven by `-- --shot <frames> <path>` on the command line.
##
## This exists so a change can be verified visually from a script rather than by
## a human watching the window — the game runs itself forward, captures the
## viewport, and exits.
func _start_capture_if_requested() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find("--shot")
	if index == -1 or index + 2 >= args.size():
		return false

	var frames: int = maxi(int(args[index + 1]), 1)
	var out_path: String = args[index + 2]

	# Capturing is slow in real time, so wind the simulation forward quickly to
	# reach a state worth looking at. `--skip <hours>` jumps further still, for
	# capturing late-game states without waiting out seven real days.
	GameClock.time_scale = 8.0
	var skip: int = args.find("--skip")
	if skip != -1 and skip + 1 < args.size():
		_started = true
		GameClock.skip_hours(int(args[skip + 1]))

	_capture_after(frames, out_path)
	return true


func _capture_after(frames: int, out_path: String) -> void:
	for _i in frames:
		await get_tree().process_frame

	await _open_conversation_if_requested()

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: int = image.save_png(out_path)
	print("capture: %s (err %d) at day %d %02d:00" % [out_path, error, GameClock.day + 1, GameClock.hour])
	get_tree().quit()


## `--talk [what to say]` opens a conversation before the screenshot, optionally
## having already said something.
##
## The dialogue panel is the one part of the game a plain screenshot can never
## reach, because it needs somebody standing next to somebody else and a
## keypress. That made it the one part nobody ever looked at.
func _open_conversation_if_requested() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find("--talk")
	if index == -1 or sim == null or avatar == null:
		return

	# Deliberately the *last* inhabitant, not the first. Reach and walk-to were
	# both keyed on the room's first standing spot, so any harness that picked
	# agent zero passed while the real interaction was broken for everybody else.
	var partner: Agent = sim.agents[sim.agents.size() - 1]

	# Drive the real click path rather than teleporting into reach, so this
	# captures what a player actually does.
	avatar.tile_position = Vector2(TownGrid.zone_center(partner.current_zone))
	avatar.position = ProcArt.tile_to_px(avatar.tile_position)
	avatar._sync_zone()

	var view: NpcView = null
	for candidate in _views:
		if candidate.agent == partner:
			view = candidate
	if view != null:
		_click_at(ProcArt.tile_to_px(view.tile_position))

	# Let the avatar walk over and `_process` open the conversation on arrival.
	for _i in 400:
		if _conversation != null:
			break
		await get_tree().process_frame

	if _conversation == null:
		push_error("--talk never reached %s" % partner.display_name)
		return

	while dialogue != null and not dialogue.is_accepting():
		await get_tree().process_frame

	var said: String = args[index + 1] if index + 1 < args.size() else ""
	if said != "" and not said.begins_with("--"):
		await _on_line_typed(said)

	for _i in 30:
		await get_tree().process_frame


func _build_simulation() -> void:
	sim = TownSim.new()
	sim.name = "TownSim"
	if procedural:
		sim.setup_generated(world_seed)
	else:
		sim.setup(world_seed)
	add_child(sim)


func _build_view() -> void:
	renderer = TownRenderer.new()
	renderer.name = "TownRenderer"
	add_child(renderer)
	renderer.setup(sim.grid)

	var lighting := DayNight.new()
	lighting.name = "DayNight"
	add_child(lighting)

	# Everybody with a body shares one y-sorted parent, so whoever is further
	# down the screen draws in front. Without it the draw order is the order the
	# cast was built in, and a villager standing behind you paints over your
	# head. The avatar sits in here too, and must: the player is not exempt from
	# standing behind people.
	_actors = Node2D.new()
	_actors.name = "Actors"
	_actors.y_sort_enabled = true
	add_child(_actors)

	for i in sim.agents.size():
		var agent: Agent = sim.agents[i]
		var view := NpcView.new()
		view.name = "Npc_%s" % agent.id
		_actors.add_child(view)
		view.setup(agent, sim.grid, i)
		_views.append(view)

	avatar = PlayerAvatar.new()
	avatar.name = "PlayerAvatar"
	_actors.add_child(avatar)
	avatar.setup(sim)

	audio = ProcAudio.new()
	audio.name = "ProcAudio"
	add_child(audio)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(sim)

	_build_dialogue()

	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.seeking_started.connect(_on_seeking_started)
	EventBus.gossip_exchanged.connect(_on_gossip_exchanged)

	_center_camera()


## Pixels of padding kept between the town and the window edge, so the HUD
## panels never sit directly on top of an inhabitant.
const VIEW_PADDING := 40.0

var _camera: Camera2D


func _center_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.position = Vector2(TownGrid.WIDTH, TownGrid.HEIGHT) * ProcArt.TILE_SIZE * 0.5
	add_child(_camera)
	_camera.make_current()

	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()


## Scales the view so the whole town fills whatever window it is given.
##
## Without this the map draws at a fixed 640x480 regardless of window size —
## unreadable on a large display and clipped on a small one.
func _fit_camera() -> void:
	if _camera == null:
		return

	var viewport_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var town_size: Vector2 = Vector2(TownGrid.WIDTH, TownGrid.HEIGHT) * ProcArt.TILE_SIZE
	var usable: Vector2 = viewport_size - Vector2(VIEW_PADDING, VIEW_PADDING) * 2.0
	if usable.x <= 0.0 or usable.y <= 0.0 or town_size.x <= 0.0 or town_size.y <= 0.0:
		return

	# Camera2D.zoom is a scale factor: larger means closer. Fitting means taking
	# the tighter of the two axes so nothing is cropped.
	var scale: float = minf(usable.x / town_size.x, usable.y / town_size.y)
	_camera.zoom = Vector2(scale, scale)


## Gives the town something to talk about on Day 1.
##
## Without an inciting rumour the simulation is stable and nothing propagates —
## correct behaviour, but it makes the opening minutes look inert.
func _seed_opening_situation() -> void:
	sim.witness(Roster.DRUNKARD, MemoryToken.new(
		Agent.PLAYER_ID, ActionCatalog.BRIBED, Roster.BLACKSMITH, true, 7, &"", 0
	))
	hud.log_clue("Old Pell saw something at the forge last night.")


## Keyboard shortcut for each approach.
const ACTION_KEYS := {
	KEY_B: PlayerActions.Kind.BRIBE,
	KEY_T: PlayerActions.Kind.THREATEN,
	KEY_H: PlayerActions.Kind.HELP,
	KEY_F: PlayerActions.Kind.FLATTER,
	KEY_P: PlayerActions.Kind.PROBE,
	KEY_K: PlayerActions.Kind.BLACKMAIL,
	KEY_E: PlayerActions.Kind.EXPOSE,
}

## The player may approach someone once per in-game hour. Without a limit there
## is no reason not to work through all ten inhabitants immediately, and the
## seven-day deadline stops meaning anything.
var _selected: Agent
var _last_action_hour: int = -1

var avatar: PlayerAvatar
var dialogue: DialoguePanel
var backend: DialogueBackend
var reader: IntentReader
var _conversation: Conversation
var _speed_before_talk: float = 1.0


## Builds the dialogue stack. Falls back to templates when Ollama is not
## running, so the game is fully playable with no model installed.
func _build_dialogue() -> void:
	dialogue = DialoguePanel.new()
	dialogue.name = "DialoguePanel"
	add_child(dialogue)
	dialogue.choice_picked.connect(_on_choice_picked)
	dialogue.line_typed.connect(_on_line_typed)
	dialogue.dismissed.connect(_end_conversation)

	backend = OllamaBackend.new(self, DIALOGUE_MODEL)
	reader = IntentReader.new(self, INTENT_MODEL)

	# Assigned above and warmed below: bringing a server up takes seconds, and
	# nothing else may wait on it. A conversation opened before the server
	# answers is served from templates, which is the same thing that happens
	# with no model installed at all.
	_boot_dialogue_server()


## Starts Ollama if it is not already up, then warms the model.
##
## The warm-up has to happen on the far side of the launch. Firing it first
## against a server still doing GPU discovery burns the single-flight lock on a
## request that will fail, and the first line of the game — every character's
## first impression — comes back canned.
func _boot_dialogue_server() -> void:
	var launcher := OllamaLauncher.new(self)
	var report: Dictionary = await launcher.ensure_running([DIALOGUE_MODEL, INTENT_MODEL])

	if report["spawned"]:
		print("Ollama: started from %s (models: %s)" % [report["binary"], report["store"]])
	elif not report["running"]:
		# Not an error. The game plays without a model; this line is here so a
		# player wondering why everyone sounds canned has something to read.
		print("Ollama: not running (%s) — dialogue will use templates." % report["reason"])

	if report["running"]:
		(backend as OllamaBackend).warm_up()


## Local models only. Never a hosted API.
##
## Two models, because the two jobs are not the same size. Voicing a character
## convincingly wants the larger one; working out that "there's coin in this for
## you" is a bribe does not, and putting both through the 14B would add seconds
## to every line the player types.
const DIALOGUE_MODEL := "qwen3:14b"
const INTENT_MODEL := "qwen3:4b"


## Opens a conversation with the selected inhabitant.
##
## The town stops while you talk. Talking is free — the clock only moves when you
## actually try to move somebody, and `Conversation.hours_spent` reports how much
## of the week that cost. Charging for conversation itself would punish the one
## thing the player most needs to do, which is find out who these people are.
func _talk_to(agent: Agent) -> void:
	if agent == null or _conversation != null:
		return
	if not _in_reach(agent):
		hud.log_clue("Walking over to %s. Press SPACE again when you arrive." % agent.short_name())
		avatar.walk_to(avatar.approach_tile(agent))
		return

	_speed_before_talk = GameClock.time_scale
	GameClock.time_scale = 0.0

	_conversation = Conversation.new(agent, sim, backend, GameClock.day, reader)
	dialogue.show_panel(agent.display_name)
	dialogue.show_thinking()

	var line: String = await _conversation.open()
	if _conversation == null:
		return
	_show_reply(line)


func _on_choice_picked(choice: Dictionary) -> void:
	if _conversation == null:
		return

	if choice["kind"] == Conversation.ChoiceKind.LEAVE:
		_end_conversation()
		return

	_begin_exchange()
	var line: String = await _conversation.choose(choice)
	_finish_exchange(line)


## The free-text path. Identical from here on: the conversation decides what was
## meant, the simulation decides what it did, the backend says it aloud.
func _on_line_typed(text: String) -> void:
	if _conversation == null:
		return

	_begin_exchange()
	var line: String = await _conversation.say(text)
	_finish_exchange(line)


func _begin_exchange() -> void:
	dialogue.show_transcript(_conversation.transcript, _conversation.target.display_name)
	dialogue.show_thinking()
	audio.play_speech_blip(_conversation.target.id)


func _finish_exchange(line: String) -> void:
	if _conversation == null:
		return

	# Attempts cost time; talk does not. Spending it here rather than inside the
	# conversation keeps the simulation clock out of the dialogue layer.
	_charge_hours()
	if _conversation == null:
		return

	hud.inspect(_conversation.target)
	_show_reply(line)


## Advances the clock by whatever the conversation has newly cost.
##
## The town keeps running through it: rivals campaign, people walk off to their
## next appointment. Standing in the tavern making five attempts in a row really
## does burn five hours of the seven days, which is the pressure that makes
## choosing who to spend them on a decision.
func _charge_hours() -> void:
	var owed: int = _conversation.hours_spent - _hours_charged
	if owed <= 0:
		return
	_hours_charged = _conversation.hours_spent
	GameClock.skip_hours(owed)
	if GameClock.is_over:
		_end_conversation()


var _hours_charged: int = 0


func _show_reply(line: String) -> void:
	if _conversation == null:
		return

	dialogue.show_line(line)
	dialogue.show_transcript(_conversation.transcript, _conversation.target.display_name)

	if _conversation.is_over:
		# A beat to read their parting line before the panel goes.
		await get_tree().create_timer(1.6).timeout
		_end_conversation()
		return

	dialogue.show_choices(_conversation.choices(), _conversation.patience)


func _end_conversation() -> void:
	if _conversation == null:
		return
	var closing: Agent = _conversation.target
	_conversation = null
	_hours_charged = 0
	dialogue.hide_panel()
	GameClock.time_scale = _speed_before_talk
	hud.log_clue("You finish speaking with %s." % closing.short_name())


func _unhandled_input(event: InputEvent) -> void:
	# The dialogue panel owns input while a conversation is open.
	if _conversation != null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).keycode
		if key == KEY_SPACE or key == KEY_ENTER:
			_talk_to(_selected)
		elif key >= KEY_0 and key <= KEY_3:
			_set_speed(key - KEY_0)
		elif ACTION_KEYS.has(key):
			_attempt_action(ACTION_KEYS[key])
		return

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_click_at(get_global_mouse_position())


## Somebody the player clicked and is still walking towards. Cleared as soon as
## the conversation opens, or the moment they steer somewhere else.
var _pending_talk: Agent = null


func _process(_delta: float) -> void:
	if _pending_talk == null or _conversation != null or avatar == null:
		return

	# Taking the keys cancels the errand — grabbing WASD always means "no, this
	# way", and it would be maddening for a conversation to spring open because
	# you happened to walk past somebody you clicked a minute ago.
	if not avatar.is_walking():
		var arrived: Agent = _pending_talk
		_pending_talk = null
		if _in_reach(arrived):
			_talk_to(arrived)


## A click either points at somebody, or sets the player walking.
func _click_at(world_position: Vector2) -> void:
	var nearest: Agent = _nearest_agent(world_position)
	if nearest != null:
		_select(nearest)

		# Clicking somebody means wanting to speak to them. If they are already
		# within reach, that is the whole interaction; otherwise walk over and
		# open the conversation on arrival. Requiring a separate keypress after
		# a click that already committed to the person reads, correctly, as
		# nothing having happened.
		if _in_reach(nearest):
			_talk_to(nearest)
			return

		_pending_talk = nearest
		if avatar.walk_to(avatar.approach_tile(nearest)):
			hud.log_clue("Walking over to %s." % nearest.short_name())
		else:
			_pending_talk = null
			hud.log_clue("There is no way through to %s." % nearest.short_name())
		return

	# Clicking open ground is a change of mind about where to be, so it cancels
	# any errand towards a person.
	_pending_talk = null

	var tile := Vector2i(
		floori(world_position.x / ProcArt.TILE_SIZE),
		floori(world_position.y / ProcArt.TILE_SIZE)
	)
	if not avatar.walk_to(tile):
		hud.log_clue("There is no way through there.")


func _in_reach(agent: Agent) -> bool:
	return avatar.can_reach(agent)


func _select(agent: Agent) -> void:
	_selected = agent
	for view in _views:
		view.is_selected = view.agent == agent
	hud.inspect(agent)
	if agent != null:
		audio.play_speech_blip(agent.id)


func _attempt_action(kind: PlayerActions.Kind) -> void:
	if _selected == null:
		hud.log_clue("Choose someone first — click an inhabitant.")
		return

	var now: int = GameClock.total_hours()
	if now == _last_action_hour:
		hud.log_clue("You have already made your approach this hour.")
		return
	if GameClock.is_over:
		hud.log_clue("The vote has been called. It is too late.")
		return

	var report: Dictionary = PlayerActions.perform(kind, _selected, sim, GameClock.day)
	if not report["ok"]:
		# A refused approach costs nothing — the player learns why and can try
		# something else this same hour.
		hud.log_clue(report["note"])
		return

	_last_action_hour = now
	audio.play_speech_blip(_selected.id)
	hud.report_action(_selected, report)
	hud.inspect(_selected)


func _set_speed(step: int) -> void:
	GameClock.time_scale = SPEED_STEPS[clampi(step, 0, SPEED_STEPS.size() - 1)]
	audio.play_click()


## Whichever inhabitant is nearest the click, within a small radius.
func _nearest_agent(world_position: Vector2) -> Agent:
	var nearest: Agent = null
	var nearest_distance: float = 24.0

	for view in _views:
		var distance: float = view.position.distance_to(world_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = view.agent

	return nearest


func _on_hour_changed(_day: int, _hour: int) -> void:
	audio.play_hour_chime()


func _on_day_changed(_day: int) -> void:
	audio.play_day_chime()


func _on_seeking_started(_npc_id: StringName, _target_id: StringName) -> void:
	audio.play_alarm()


func _on_gossip_exchanged(speaker_id: StringName, _listener_id: StringName, _token: MemoryToken) -> void:
	audio.play_speech_blip(speaker_id)
