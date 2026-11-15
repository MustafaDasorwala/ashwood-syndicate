class_name IntentReader
extends RefCounted

## Reads what the player typed and decides what they were *attempting*.
##
## This is the half of free-text conversation the model is allowed to do. It
## reads intent; it never decides consequence. The split matters:
##
##   player types  ->  IntentReader interprets  ->  simulation resolves
##                                              ->  backend voices the result
##
## A model that decided outcomes could be talked into anything, and the whole
## game — rivals, ties, the persuasion ceiling — would collapse into finding the
## magic sentence. Interpreting is also a far smaller ask than judging, which is
## why a 4B model is enough here while it measurably was not for judging.
##
## Two things every caller depends on:
##
## 1. `read` **always** emits `intent_ready` exactly once, on every failure path.
##    A conversation awaits this signal and would otherwise hang for good. This
##    is the same deadlock `DialogueBackend.deliver` exists to prevent, so the
##    emit goes through `_deliver` for the same reason.
## 2. With Ollama absent or broken it falls back to keyword matching rather than
##    to nothing. Typing "I'll pay you well" still reads as a bribe.

signal intent_ready(intent: Dictionary)

const HOST := "http://localhost:11434"
const ENDPOINT := "/api/chat"

## Classifying is a much smaller job than acting a character, so it runs on the
## small fast model. Two sequential model calls per line would otherwise put
## four seconds between the player pressing enter and anyone speaking.
const DEFAULT_MODEL := "qwen3:4b"

const TIMEOUT_SECONDS := 12.0

## JSON only, so the reply cannot run long.
const MAX_TOKENS := 120

## Intent kinds. Plain StringNames rather than an enum shared with
## `Conversation`, which would make the two classes reference each other.
const APPROACH := &"approach"
const ASK_ABOUT := &"ask_about"
const SMALLTALK := &"smalltalk"
const LEAVE := &"leave"

## Neutral fit, used whenever nothing better is known. Sits at the midpoint so
## an unjudged line neither helps nor hurts.
const NEUTRAL_FIT := 0.5

## Words that betray an attempt, checked when no model is available. Ordered by
## specificity: "threaten to tell" is blackmail, not a threat, so the more
## particular kinds are tested first.
const KEYWORDS := [
	[PlayerActions.Kind.BLACKMAIL, ["blackmail", "keep quiet", "silence", "unless you", "or i tell", "or else i tell"]],
	[PlayerActions.Kind.EXPOSE, ["did you know", "you should know about", "tell you about", "expose", "spread"]],
	[PlayerActions.Kind.PROBE, ["hiding", "not telling", "what happened", "the truth", "confess", "secret"]],
	[PlayerActions.Kind.BRIBE, ["coin", "pay", "gold", "money", "purse", "silver", "worth your while", "reward"]],
	[PlayerActions.Kind.THREATEN, ["threat", "regret", "or else", "make you", "sorry", "ruin you", "hurt"]],
	[PlayerActions.Kind.FLATTER, ["admire", "respect", "finest", "best", "clever", "wise", "kind of you", "impressive"]],
	[PlayerActions.Kind.HELP, ["help", "hand", "assist", "carry", "favour", "favor", "let me"]],
]

var model: String
var _http: HTTPRequest
var _busy: bool = false
var _pending: Dictionary = {}


## `host_node` must be in the scene tree — HTTPRequest needs a parent to process.
func _init(host_node: Node, p_model: String = DEFAULT_MODEL) -> void:
	model = p_model
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SECONDS
	host_node.add_child(_http)
	_http.request_completed.connect(_on_response)


## Interprets `text`.
##
## `options` describes what is actually possible right now, so the model is only
## ever choosing among real moves: {
##   approaches: Array[PlayerActions.Kind],
##   people: Array[Dictionary] as { id, name },
##   speaker_name: String,
##   character: String   # the persona sheet, so fit is judged for this person
## }
func read(text: String, options: Dictionary) -> void:
	var context := {"text": text, "options": options}

	if _busy or _http == null:
		_deliver(fallback_intent(text, options))
		return

	_pending = context
	_busy = true

	var body := {
		"model": model,
		"stream": false,
		"think": false,
		# Ollama's JSON mode. Without it a small model wraps the object in prose
		# and the parse fails often enough to matter.
		"format": "json",
		"options": {"temperature": 0.1, "num_predict": MAX_TOKENS},
		"messages": [
			{"role": "system", "content": _system_prompt(options)},
			{"role": "user", "content": text},
		],
	}

	var error: int = _http.request(
		HOST + ENDPOINT, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(body)
	)
	if error != OK:
		_finish(fallback_intent(text, options))


## What the model is asked. Note it is asked to *classify and rate*, never to
## decide what happens as a result.
static func _system_prompt(options: Dictionary) -> String:
	var lines: Array[String] = []
	var speaker: String = options.get("speaker_name", "this person")

	lines.append("You classify what someone is attempting in conversation. You do not decide what happens as a result.")
	lines.append("")

	var character: String = options.get("character", "")
	if character != "":
		lines.append("They are speaking to %s." % speaker)
		lines.append(character)
		lines.append("")

	lines.append("Reply with JSON only, in this exact shape:")
	lines.append('{"intent": "...", "approach": "...", "about": "...", "fit": 0}')
	lines.append("")
	lines.append("intent is one of: approach, ask_about, smalltalk, leave")
	lines.append("  approach  - they are trying to move %s: a favour, flattery, a bribe, a threat, prying, leverage, or news about someone else" % speaker)
	lines.append("  ask_about - they are asking %s's opinion of another person" % speaker)
	lines.append("  smalltalk - conversation with no attempt behind it")
	lines.append("  leave     - they are ending the conversation")
	lines.append("")

	var approaches: Array = options.get("approaches", [])
	if not approaches.is_empty():
		lines.append("approach must be one of these, and only when intent is approach:")
		for kind: int in approaches:
			lines.append("  %s - %s" % [
				_approach_token(kind), PlayerActions.hint_for(kind as PlayerActions.Kind)
			])
		lines.append("")

	var people: Array = options.get("people", [])
	if not people.is_empty():
		lines.append("about is the person referred to, when there is one. One of:")
		for person: Dictionary in people:
			lines.append("  %s - %s" % [person["id"], person["name"]])
		lines.append("")

	lines.append("fit is 0 to 10: how well-judged this line is for %s specifically," % speaker)
	lines.append("given who they are and how they currently regard the speaker.")
	lines.append("10 means it lands exactly on what moves this person. 0 means it is")
	lines.append("the worst thing they could have said. Judge the wording, not the tactic.")

	return "\n".join(lines)


static func _approach_token(kind: int) -> String:
	return PlayerActions.label_for(kind as PlayerActions.Kind).to_lower()


func _on_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text: String = _pending.get("text", "")
	var options: Dictionary = _pending.get("options", {})

	if code != 200:
		_finish(fallback_intent(text, options))
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("message"):
		_finish(fallback_intent(text, options))
		return

	var content: String = str(parsed["message"].get("content", ""))
	var intent: Dictionary = parse_intent(content, text, options)
	_finish(intent)


## Turns the model's reply into an intent, falling back to keywords when it is
## unusable. Kept static and separate from the HTTP so it can be tested without
## a server.
static func parse_intent(content: String, text: String, options: Dictionary) -> Dictionary:
	var object: Variant = _extract_object(content)
	if typeof(object) != TYPE_DICTIONARY:
		return fallback_intent(text, options)

	var raw: Dictionary = object
	var kind: StringName = _read_kind(str(raw.get("intent", "")))
	var intent := fallback_intent(text, options)
	intent["kind"] = kind
	intent["fit"] = _read_fit(raw.get("fit"))

	if kind == APPROACH:
		var approach: int = _read_approach(str(raw.get("approach", "")), options)
		if approach < 0:
			# It called this an attempt but named no usable approach. Keywords
			# know more than nothing, and a smalltalk reply to an attempt reads
			# as the character ignoring the player.
			var guessed: Dictionary = fallback_intent(text, options)
			intent["kind"] = guessed["kind"]
			intent["approach"] = guessed["approach"]
		else:
			intent["approach"] = approach

	if kind == ASK_ABOUT or kind == APPROACH:
		var subject: StringName = _read_subject(str(raw.get("about", "")), options)
		if subject != &"":
			intent["subject"] = subject

	# Asking about nobody is not a question; treat it as talk rather than
	# resolving a question against an empty subject.
	if intent["kind"] == ASK_ABOUT and intent["subject"] == &"":
		intent["kind"] = SMALLTALK

	return intent


## Pulls the first JSON object out of a reply. Models in JSON mode occasionally
## still prepend a sentence.
static func _extract_object(content: String) -> Variant:
	var direct: Variant = JSON.parse_string(content.strip_edges())
	if typeof(direct) == TYPE_DICTIONARY:
		return direct

	var start: int = content.find("{")
	var end: int = content.rfind("}")
	if start == -1 or end <= start:
		return null
	return JSON.parse_string(content.substr(start, end - start + 1))


static func _read_kind(raw: String) -> StringName:
	match raw.strip_edges().to_lower():
		"approach": return APPROACH
		"ask_about", "ask about", "ask": return ASK_ABOUT
		"leave", "goodbye", "end": return LEAVE
		_: return SMALLTALK


## Maps the model's label back to an approach, accepting only ones actually
## available. A model naming Blackmail when the player holds nothing must not
## be able to conjure the leverage.
static func _read_approach(raw: String, options: Dictionary) -> int:
	var wanted: String = raw.strip_edges().to_lower()
	if wanted.is_empty():
		return -1
	for kind: int in options.get("approaches", []):
		if _approach_token(kind) == wanted:
			return kind
	return -1


static func _read_subject(raw: String, options: Dictionary) -> StringName:
	var wanted: String = raw.strip_edges().to_lower()
	if wanted.is_empty():
		return &""
	for person: Dictionary in options.get("people", []):
		if str(person["id"]).to_lower() == wanted:
			return person["id"]
		if str(person["name"]).to_lower().contains(wanted) and wanted.length() > 2:
			return person["id"]
	return &""


## Reads the model's rating, which is asked for as 0-10 and does not always
## arrive that way.
##
## Measured: qwen3:4b answers 0, 7, 8, 10 — and occasionally 0.8, meaning
## eight tenths rather than eight. Taken at face value and divided by ten that
## became 0.08, so a mild pleasantry read as the most offensive thing the player
## could have said. A fractional value is therefore treated as already scaled.
static func _read_fit(raw: Variant) -> float:
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return NEUTRAL_FIT

	var value: float = float(raw)
	if value > 0.0 and value < 1.0 and not is_equal_approx(value, roundf(value)):
		return clampf(value, 0.0, 1.0)
	return clampf(value / 10.0, 0.0, 1.0)


## Interpretation with no model involved.
##
## Deliberately crude, and deliberately present: the project's rule is that the
## game stays playable with Ollama absent. Typing "there is coin in this for
## you" reads as a bribe here just as it would through the model, only without
## the judgement of how well it was put.
static func fallback_intent(text: String, options: Dictionary) -> Dictionary:
	var intent := {
		"kind": SMALLTALK,
		"approach": -1,
		"subject": &"",
		"fit": NEUTRAL_FIT,
		"text": text,
	}

	var lowered: String = text.to_lower()
	if lowered.strip_edges().is_empty():
		return intent

	for person: Dictionary in options.get("people", []):
		if lowered.contains(str(person["name"]).to_lower()):
			intent["subject"] = person["id"]
			intent["kind"] = ASK_ABOUT
			break

	var available: Array = options.get("approaches", [])
	for entry: Array in KEYWORDS:
		var kind: int = entry[0]
		if not available.has(kind):
			continue
		for word: String in entry[1]:
			if lowered.contains(word):
				intent["kind"] = APPROACH
				intent["approach"] = kind
				return intent

	return intent


func _finish(intent: Dictionary) -> void:
	_busy = false
	_deliver(intent)


## Deferred for the same reason `DialogueBackend.deliver` is: an instant answer
## must still arrive after the caller has begun awaiting, or the await never
## returns.
func _deliver(intent: Dictionary) -> void:
	intent_ready.emit.call_deferred(intent)
