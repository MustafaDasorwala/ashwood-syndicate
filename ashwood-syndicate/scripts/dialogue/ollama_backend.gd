class_name OllamaBackend
extends DialogueBackend

## Talks to a local Ollama server. Nothing leaves the machine and no paid API is
## ever involved.
##
## Measured on an M2 Max with qwen3:14b: ~1.3-2.0s warm for a two-sentence
## in-character reply. Cold start adds ~8s for the first request, which is why
## `warm_up` exists.
##
## Every failure path still emits `line_ready` with the template fallback. A
## conversation that awaits a signal must never be left hanging because a
## server was down.

const HOST := "http://localhost:11434"
const ENDPOINT := "/api/chat"

## Reasoning models otherwise burn seconds emitting <think> blocks nobody sees.
const DISABLE_THINKING := true

## Hard ceiling on reply length. Characters are told to speak 1-2 sentences;
## this stops a rambling model stalling the game if it ignores that.
const MAX_TOKENS := 90

const TIMEOUT_SECONDS := 20.0

var model: String
var _http: HTTPRequest
var _pending: Dictionary = {}
var _busy: bool = false

## Set while the warm-up request is in flight.
var _warming: bool = false

## A real request that arrived during warm-up, to be sent the moment it ends.
##
## Without this the first conversation of every game opened on a template,
## because warm-up holds the single-flight lock for its whole eight second cold
## start and a player who walks straight up to somebody collides with it. The
## greeting is the first impression of every character in the town, so it is the
## worst line in the game to lose.
var _deferred: Dictionary = {}


## `host_node` must be in the scene tree — HTTPRequest needs a parent to process.
func _init(host_node: Node, p_model: String = "qwen3:14b") -> void:
	model = p_model
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SECONDS
	host_node.add_child(_http)
	_http.request_completed.connect(_on_response)


func is_available() -> bool:
	return _http != null and not _busy


## Loads the model so the first real line is not an eight second pause.
func warm_up() -> void:
	if _busy:
		return
	_warming = true
	request_line({
		"speaker_name": "", "outcome": "greeting", "topic": "", "player_line": "",
		"system": "You are a villager.", "instruction": "Say hello.",
	})


func request_line(request: Dictionary) -> void:
	if _busy:
		# Warming up is not a conversation, so a real line arriving during it is
		# held rather than answered from templates.
		if _warming and _deferred.is_empty():
			_deferred = request
			return

		# Otherwise: one conversation at a time. A queued second request would
		# arrive out of order and put words in the wrong mouth.
		deliver(DialogueBackend.fallback_line(request))
		return

	_pending = request
	_busy = true

	var user: String = request.get("instruction", "")
	var player_line: String = request.get("player_line", "")
	if player_line != "":
		user = "They said to you: \"%s\"\n\n%s" % [player_line, user]

	var body := {
		"model": model,
		"stream": false,
		"think": not DISABLE_THINKING,
		"options": {"temperature": 0.85, "num_predict": MAX_TOKENS},
		"messages": [
			{"role": "system", "content": request.get("system", "")},
			{"role": "user", "content": user},
		],
	}

	var error: int = _http.request(
		HOST + ENDPOINT, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(body)
	)
	if error != OK:
		_finish(DialogueBackend.fallback_line(request))


func _on_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		_finish(DialogueBackend.fallback_line(_pending))
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("message"):
		_finish(DialogueBackend.fallback_line(_pending))
		return

	var line: String = _clean(str(parsed["message"].get("content", "")))
	if line.is_empty():
		line = DialogueBackend.fallback_line(_pending)
	_finish(line)


## Strips the artefacts models add despite being told not to: surrounding
## quotes, a leading "Name:" prefix, and any stray reasoning block.
static func _clean(raw: String) -> String:
	var text: String = raw.strip_edges()

	var think_end: int = text.find("</think>")
	if think_end != -1:
		text = text.substr(think_end + 8).strip_edges()

	if text.begins_with("\"") and text.ends_with("\"") and text.length() > 1:
		text = text.substr(1, text.length() - 2)

	var colon: int = text.find(":")
	if colon > 0 and colon < 24 and not text.substr(0, colon).contains(" "):
		text = text.substr(colon + 1).strip_edges()

	return text.strip_edges()


func _finish(line: String) -> void:
	_busy = false

	# A line held back during warm-up is sent now, and the warm-up's own reply is
	# dropped: nobody is awaiting it. Errors land here too, so a failed warm-up
	# releases the held request rather than stranding it.
	var was_warming: bool = _warming
	_warming = false
	if was_warming and not _deferred.is_empty():
		var held: Dictionary = _deferred
		_deferred = {}
		request_line(held)
		return

	deliver(line)
