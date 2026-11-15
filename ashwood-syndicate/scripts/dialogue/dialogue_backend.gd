class_name DialogueBackend
extends RefCounted

## How a line of NPC dialogue gets written.
##
## The simulation has already decided what happened before this is called. A
## backend's only job is to phrase an outcome in a character's voice — it never
## decides trust, never reveals a secret, never changes state. That split is
## deliberate: it keeps the model unable to contradict the simulation, and it
## means a weak local model (or none at all) degrades to flat prose rather than
## to a broken game.
##
## Implementations: `TemplateBackend` (always available), `OllamaBackend`
## (local model), and `ScriptedBackend` for tests.

## Emitted when a requested line is ready. `line` is always non-empty.
signal line_ready(line: String)


## Requests a line. Implementations must eventually emit `line_ready` exactly
## once per call, even on failure — callers await the signal and would otherwise
## hang the conversation forever.
##
## Always emit through `deliver`, never `line_ready.emit` directly. A backend
## that answers instantly would otherwise fire the signal before the caller's
## `await` has subscribed, and the conversation would hang for good. That is a
## real deadlock, not a slow reply: it took a fast test double to expose it.
##
## `request` is the dictionary built by `PromptBuilder.build`.
func request_line(request: Dictionary) -> void:
	deliver(fallback_line(request))


## Emits `line_ready` on the next idle frame, so an instant answer is still
## delivered after the caller begins awaiting.
func deliver(line: String) -> void:
	line_ready.emit.call_deferred(line)


## Whether this backend can currently produce anything better than templates.
func is_available() -> bool:
	return true


## A usable line with no model involved. Every backend falls back to this, so
## the game is fully playable with Ollama absent.
static func fallback_line(request: Dictionary) -> String:
	var name: String = request.get("speaker_name", "They")
	var outcome: String = request.get("outcome", "neutral")
	var topic: String = request.get("topic", "")

	match outcome:
		"hostile":
			return "%s looks at you coldly and says nothing worth repeating." % name
		"warm":
			return "%s softens a little at that." % name
		"guarded":
			return "%s gives you a careful, measured answer." % name
		"reveal":
			return "%s hesitates, then tells you what they know about %s." % [name, topic]
		"refuse":
			return "%s changes the subject." % name
		_:
			return "%s acknowledges you." % name
