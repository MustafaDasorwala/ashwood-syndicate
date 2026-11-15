class_name Conversation
extends RefCounted

## One conversation with one inhabitant.
##
## The player types whatever they like. The listed choices remain, as suggested
## phrasings rather than as the whole vocabulary — without them a new player has
## no way to discover that bribery or blackmail are in the game at all.
##
## Order of operations matters and is deliberate:
##   1. The player says something, typed or clicked.
##   2. `IntentReader` decides what they were *attempting*, and how well they
##      put it. This is the only judgement a model is trusted with.
##   3. The **simulation** resolves it and produces the outcome.
##   4. The backend phrases that outcome in character.
##
## The model is never asked what *should happen*, only what was meant and how it
## sounded. So it cannot contradict the sim, it cannot be argued into handing
## over a vote, and with no model running at all the game still plays on keyword
## matching and templates.

enum ChoiceKind { APPROACH, ASK_ABOUT, LEAVE }

signal line_spoken(speaker_name: String, line: String)
signal ended()

## Patience granted by how they already regard you, in exchanges that annoy
## them. Someone who despises you will not stand there long; someone who trusts
## you will talk all evening.
const MIN_PATIENCE := 2
const MAX_PATIENCE := 8

## Regard needed before someone will tell you their honest read on a third
## party. Lower than the bar for confessing their own secret.
const OPINION_THRESHOLD := 55.0

## Most a well-judged question can lower that bar. Small on purpose: putting it
## well should open a door that was already ajar, not pick the lock on someone
## who despises you.
const CANDOUR_RELIEF := 12.0

## Exchanges of history handed to the model, so a long conversation reads as one
## conversation rather than a series of unrelated first meetings. Bounded for
## the same reason `PromptBuilder.MEMORY_BUDGET` is — the whole prompt has to
## stay small enough for a 3B model later.
const HISTORY_BUDGET := 6

var target: Agent
var sim: TownSim
var backend: DialogueBackend
var reader: IntentReader
var day: int

## Falls as they tire of you. Only rebuffs and refusals spend it: pleasant
## conversation is free, which is the point of being able to type at all.
var patience: int = MAX_PATIENCE
var is_over: bool = false

## In-game hours this conversation has consumed. Talk is free; each attempt to
## actually move somebody costs an hour, and the caller advances the clock by
## whatever this reports.
var hours_spent: int = 0

## Everything said so far, as { speaker, line }.
var transcript: Array[Dictionary] = []


func _init(
	p_target: Agent,
	p_sim: TownSim,
	p_backend: DialogueBackend,
	p_day: int = 0,
	p_reader: IntentReader = null
) -> void:
	target = p_target
	sim = p_sim
	backend = p_backend
	day = p_day
	reader = p_reader
	patience = patience_for(p_target.opinion_of_player())


## How long they will put up with being annoyed, given how they see you.
static func patience_for(regard: float) -> int:
	var t: float = clampf(regard / RelationshipBook.MAX_SCORE, 0.0, 1.0)
	return int(round(lerpf(float(MIN_PATIENCE), float(MAX_PATIENCE), t)))


## Opens with their greeting. Await this before showing choices.
func open() -> String:
	var outcome: String = "greeting"
	if target.opinion_of_player() < 30.0:
		outcome = "hostile"
	return await _speak(PromptBuilder.build(target, sim, outcome, "", "", _history()))


## What the player could say right now.
##
## Contextual on purpose: blackmail only appears when you actually hold
## something, and you can only ask about people this character is tied to.
##
## These are now prompts rather than the menu — anything here can equally be
## typed, in the player's own words.
func choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_over:
		return out

	for kind: PlayerActions.Kind in available_approaches():
		out.append(_approach(kind, SUGGESTED_LINES[kind]))

	for other in _people_worth_asking_about():
		out.append({
			"kind": ChoiceKind.ASK_ABOUT,
			"text": "What do you make of %s?" % other.display_name,
			"subject": other.id,
		})

	out.append({"kind": ChoiceKind.LEAVE, "text": "(say nothing further)", "subject": &""})
	return out


## A suggested way to put each approach. Shown as clickable lines, and handed to
## nothing else — typing your own version of any of them works identically.
const SUGGESTED_LINES := {
	PlayerActions.Kind.HELP: "Let me take that off your hands.",
	PlayerActions.Kind.FLATTER: "This town would be poorer without you.",
	PlayerActions.Kind.BRIBE: "There is coin in this for you.",
	PlayerActions.Kind.THREATEN: "You do not want me for an enemy.",
	PlayerActions.Kind.PROBE: "What is it you are not telling me?",
	PlayerActions.Kind.BLACKMAIL: "I know what you did. You will back me.",
	PlayerActions.Kind.EXPOSE: "There is something you should know about someone.",
}


## Which approaches are actually possible against this person right now.
##
## Shared by the choice list and by `IntentReader`, so the model can only ever
## pick from moves the player genuinely holds. Without that, typing "I know what
## you did" would let a model conjure leverage nobody has.
func available_approaches() -> Array[PlayerActions.Kind]:
	var out: Array[PlayerActions.Kind] = [
		PlayerActions.Kind.HELP,
		PlayerActions.Kind.FLATTER,
		PlayerActions.Kind.BRIBE,
		PlayerActions.Kind.THREATEN,
	]

	if not sim.secrets_about(target.id).is_empty() and not sim.knows_secret_of(Agent.PLAYER_ID, target.id):
		out.append(PlayerActions.Kind.PROBE)
	if sim.knows_secret_of(Agent.PLAYER_ID, target.id):
		out.append(PlayerActions.Kind.BLACKMAIL)
	if PlayerActions.can_expose(target, sim):
		out.append(PlayerActions.Kind.EXPOSE)

	return out


func _approach(kind: PlayerActions.Kind, text: String) -> Dictionary:
	return {"kind": ChoiceKind.APPROACH, "text": text, "approach": kind, "subject": &""}


## Who this character has an opinion worth hearing about: the people they are
## actually tied to, minus anyone in the room to hear it.
func _people_worth_asking_about() -> Array[Agent]:
	var out: Array[Agent] = []
	if sim.relations == null:
		return out

	for relation in sim.relations.relations_of(target.id):
		var other: Agent = sim.agent_by_id(relation["other"])
		if other == null or other.current_zone == target.current_zone:
			continue
		out.append(other)
		if out.size() >= 2:
			break
	return out


# --- saying things ---------------------------------------------------------

## The free-text path. Say anything; the reader works out what you meant.
func say(text: String) -> String:
	if is_over:
		return ""

	var spoken: String = text.strip_edges()
	if spoken.is_empty():
		return ""

	transcript.append({"speaker": "You", "line": spoken})

	var intent: Dictionary = await _interpret(spoken)
	return await _act_on(intent, spoken)


## Clicking one of the suggested lines. Goes through exactly the same resolution
## as typing it would, only with the interpretation already known — so the two
## input methods can never drift into behaving differently.
func choose(choice: Dictionary) -> String:
	if is_over:
		return ""

	if choice["kind"] == ChoiceKind.LEAVE:
		_end()
		return ""

	var spoken: String = choice["text"]
	transcript.append({"speaker": "You", "line": spoken})

	var intent := {
		"kind": IntentReader.SMALLTALK,
		"approach": -1,
		"subject": choice.get("subject", &""),
		# A canned line is neither well nor badly judged. Neutral maps to a
		# delivery of exactly 1.0, so clicking behaves as it always has.
		"fit": IntentReader.NEUTRAL_FIT,
		"text": spoken,
	}
	match choice["kind"]:
		ChoiceKind.APPROACH:
			intent["kind"] = IntentReader.APPROACH
			intent["approach"] = choice["approach"]
		ChoiceKind.ASK_ABOUT:
			intent["kind"] = IntentReader.ASK_ABOUT

	return await _act_on(intent, spoken)


func _interpret(spoken: String) -> Dictionary:
	var options := {
		"speaker_name": target.display_name,
		"approaches": available_approaches(),
		"people": _people_referable(),
		"character": PromptBuilder.persona_summary(target),
	}

	if reader == null:
		return IntentReader.fallback_intent(spoken, options)

	reader.read(spoken, options)
	return await reader.intent_ready


## Everyone the player could plausibly name at this person. Wider than
## `_people_worth_asking_about`, because you can mention somebody who is
## standing right there even if asking their opinion of them is awkward.
func _people_referable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for agent in sim.agents:
		if agent.id == target.id:
			continue
		out.append({"id": agent.id, "name": agent.display_name})
	return out


## Resolves an interpreted intent and voices the result.
func _act_on(intent: Dictionary, spoken: String) -> String:
	match intent["kind"]:
		IntentReader.LEAVE:
			_end()
			return ""
		IntentReader.APPROACH:
			return await _resolve_approach(intent, spoken)
		IntentReader.ASK_ABOUT:
			return await _resolve_question(intent, spoken)
		_:
			return await _resolve_smalltalk(intent, spoken)


## Talk with no attempt behind it. Costs no time and moves no numbers — it is
## how the player learns who somebody is before deciding what will work on them,
## which is the entire reason for typing rather than picking.
func _resolve_smalltalk(intent: Dictionary, spoken: String) -> String:
	var fit: float = float(intent["fit"])
	var outcome: String = "guarded"
	if fit > 0.65:
		outcome = "warm"
	elif fit < RUDENESS_FIT:
		outcome = "hostile"
		# Only genuine rudeness costs patience. The bar is well below neutral
		# because a bland remark scores low without being an insult, and
		# charging patience for those made small talk quietly dangerous — which
		# defeats the point of being able to make it.
		_lose_patience()

	return await _speak(PromptBuilder.build(target, sim, outcome, spoken, "", _history()))


## Below this, an idle remark counts as an insult rather than merely a dull one.
const RUDENESS_FIT := 0.15


## The simulation resolves the approach; the backend only voices the result.
func _resolve_approach(intent: Dictionary, spoken: String) -> String:
	var kind: PlayerActions.Kind = intent["approach"] as PlayerActions.Kind
	var report: Dictionary = PlayerActions.perform(
		kind, target, sim, day, Agent.PLAYER_ID, intent.get("subject", &""), float(intent["fit"])
	)

	if not report["ok"]:
		# Refused approaches cost patience but not the whole conversation.
		_lose_patience()
		var request := PromptBuilder.build(target, sim, "refuse", spoken, "", _history())
		return await _speak(request)

	# Trying to move somebody is the thing that costs time. Talking does not.
	hours_spent += 1

	var outcome: String = "guarded"
	var delta: float = report["target_delta"]
	if kind == PlayerActions.Kind.PROBE:
		outcome = "reveal"
	elif kind == PlayerActions.Kind.EXPOSE:
		# They react to the news, not to you — even when hearing it costs you
		# something in their estimation.
		outcome = "reveal"
	elif delta > 2.0:
		outcome = "warm"
	elif delta < -2.0:
		outcome = "hostile"

	# Patience goes on *any* unwelcome move, not only a loud one. Keying it to
	# the hostile threshold meant repetition decay eventually shrank a threat
	# below it, and someone could then be threatened forever without ever
	# walking away — they simply stopped minding.
	if delta < 0.0:
		_lose_patience()

	var topic: String = ""
	if report.get("discovered") != null:
		topic = "what they have been hiding"

	return await _speak(PromptBuilder.build(target, sim, outcome, spoken, topic, _history()))


## Asking about a third party. Trust decides whether they are honest, and a
## genuine answer hands the player a belief they did not have.
func _resolve_question(intent: Dictionary, spoken: String) -> String:
	var subject_id: StringName = intent["subject"]
	var subject: Agent = sim.agent_by_id(subject_id)
	var subject_name: String = subject.display_name if subject != null else str(subject_id)

	if target.opinion_of_player() < candour_threshold(float(intent["fit"])):
		_lose_patience()
		return await _speak(
			PromptBuilder.build(target, sim, "refuse", spoken, subject_name, _history())
		)

	# They share the most significant thing they believe about that person.
	var known: Array[MemoryToken] = target.ledger.about(subject_id)
	if not known.is_empty():
		sim.player_learns(known[0].retold_by(target.id, day))

	return await _speak(
		PromptBuilder.build(target, sim, "reveal", spoken, subject_name, _history())
	)


## How much regard it takes to get an honest answer, given how well the question
## was put.
##
## This is one of the two rewards for a well-judged line — see
## `PlayerActions.delivery_of` for why the reward cannot be regard itself.
static func candour_threshold(fit: float) -> float:
	var above_neutral: float = maxf(clampf(fit, 0.0, 1.0) - IntentReader.NEUTRAL_FIT, 0.0)
	return OPINION_THRESHOLD - CANDOUR_RELIEF * (above_neutral / IntentReader.NEUTRAL_FIT)


# --- plumbing --------------------------------------------------------------

## The tail of what has been said, for the prompt. Without it every reply in a
## long conversation is answered as though it were the first thing said.
func _history() -> Array[Dictionary]:
	if transcript.size() <= HISTORY_BUDGET:
		return transcript
	return transcript.slice(transcript.size() - HISTORY_BUDGET)


func _lose_patience() -> void:
	patience -= 1
	if patience <= 0:
		_end()


func _speak(request: Dictionary) -> String:
	backend.request_line(request)
	var line: String = await backend.line_ready
	transcript.append({"speaker": target.display_name, "line": line})
	line_spoken.emit(target.display_name, line)
	return line


func _end() -> void:
	if is_over:
		return
	is_over = true
	ended.emit()
