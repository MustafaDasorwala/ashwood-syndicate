class_name OllamaLauncher
extends RefCounted

## Starts the local Ollama server if it is not already up, and points it at a
## model store that actually holds the models the game asks for.
##
## This exists because of a failure that looks exactly like a bug in the game
## and is not one. `OllamaBackend` and `IntentReader` both fall back silently —
## templates and keyword matching — whenever the server does not answer. That
## is the right behaviour: the game must be playable with no model installed.
## The cost is that a server which is merely *not running*, or is running
## against the wrong model directory, is indistinguishable from a machine that
## never had a model on it. The player sees canned lines and no error.
##
## Two distinct things go wrong in practice:
##
## 1. Nobody started the daemon. Ollama is installed, the models are on disk,
##    and there is no process listening on 11434.
## 2. The daemon is up but reading an empty store. `OLLAMA_MODELS` defaults to
##    `$HOME/.ollama/models`, so logging in as a different macOS user than the
##    one that ran `ollama pull` yields a server with zero models and a
##    perfectly healthy `/api/tags` returning `{"models":[]}`.
##
## Both are fixed here by looking for a store that contains the required
## manifests before spawning, rather than trusting the environment default.
##
## What this deliberately does *not* do: download anything. A missing model is
## reported and the game carries on with templates. Pulling ~11GB is not a
## thing a game should decide to do while the player waits at the title screen.

const HOST := "http://127.0.0.1:11434"
const TAGS_ENDPOINT := "/api/tags"

## How long to wait for a freshly spawned server to answer. Cold start on an
## M2 Max is around eight seconds, most of it GPU discovery, and the port binds
## several seconds before `/api/tags` stops returning 500 — so this waits on a
## successful response, never on the socket.
const READY_TIMEOUT_SECONDS := 30.0
const POLL_INTERVAL_SECONDS := 0.5

## A probe against a server that is already up should cost almost nothing.
const PROBE_TIMEOUT_SECONDS := 3.0

## Set this in the environment to keep the game from spawning anything.
const OPT_OUT_ENV := "ASHWOOD_NO_OLLAMA_LAUNCH"

## Where home directories live, so the other-accounts sweep works on both
## platforms this is developed and played on. Windows has no equivalent worth
## guessing at — there the installer runs Ollama as a service under the logged
## in user, and the default store is the right one.
const HOME_ROOTS: PackedStringArray = ["/Users", "/home"]

## Where Ollama installs on macOS, in the order worth trying. The bundled binary
## inside the .app is last because it is the one least likely to match whatever
## the user drives from a terminal.
const BINARY_CANDIDATES: PackedStringArray = [
	"/usr/local/bin/ollama",
	"/opt/homebrew/bin/ollama",
	"/usr/bin/ollama",
	"/Applications/Ollama.app/Contents/Resources/ollama",
]

var _host: Node
var _http: HTTPRequest


## `host_node` must be in the scene tree — HTTPRequest needs a parent to process.
func _init(host_node: Node) -> void:
	_host = host_node
	_http = HTTPRequest.new()
	host_node.add_child(_http)


## Brings a server holding `models` up if one is not already answering.
##
## Returns a report rather than a bool because every outcome here is a thing
## somebody debugging a canned-sounding NPC wants to read: which store was
## chosen, whether we spawned anything, and why we gave up if we did.
##
## Awaits, so callers must not depend on the server being up when it returns
## control — build the backend first, then warm it up on the far side of this.
func ensure_running(models: Array) -> Dictionary:
	var report := {
		"running": false, "spawned": false, "store": "", "binary": "", "reason": "",
	}

	# Headless is the test harness and tools/run.sh. A smoke run must not leave
	# an inference server behind it, and the suite must not depend on one.
	if DisplayServer.get_name() == "headless":
		report["reason"] = "headless"
		return report

	if OS.get_environment(OPT_OUT_ENV) != "":
		report["reason"] = "opted out via %s" % OPT_OUT_ENV
		return report

	if await _server_answers(PROBE_TIMEOUT_SECONDS):
		report["running"] = true
		report["reason"] = "already running"
		return report

	var store: String = pick_store(store_candidates(), models)
	if store == "":
		report["reason"] = "no model store holds %s" % ", ".join(models)
		return report
	report["store"] = store

	var binary: String = pick_binary(BINARY_CANDIDATES)
	if binary == "":
		report["reason"] = "ollama binary not found"
		return report
	report["binary"] = binary

	# Godot has no per-process environment argument, so the child inherits ours.
	# Setting it here rather than passing a flag is also what makes the spawned
	# server agree with an `ollama` run by hand from the same environment.
	OS.set_environment("OLLAMA_MODELS", store)

	if OS.create_process(binary, ["serve"]) == -1:
		report["reason"] = "could not spawn %s serve" % binary
		return report
	report["spawned"] = true

	# The server is left running on quit on purpose. It is shared with anything
	# else on the machine using Ollama, and killing a daemon we may not have
	# been the first to want is worse than leaving a warm one behind.
	report["running"] = await _server_answers(READY_TIMEOUT_SECONDS)
	if not report["running"]:
		report["reason"] = "spawned but no response within %ds" % int(READY_TIMEOUT_SECONDS)
	return report


## True once `/api/tags` returns 200. Polls, because a server that has bound the
## port is not yet a server that can list models.
func _server_answers(timeout_seconds: float) -> bool:
	var deadline: float = timeout_seconds
	while deadline > 0.0:
		if await _tags_ok():
			return true
		await _host.get_tree().create_timer(POLL_INTERVAL_SECONDS).timeout
		deadline -= POLL_INTERVAL_SECONDS
	return false


func _tags_ok() -> bool:
	_http.timeout = PROBE_TIMEOUT_SECONDS
	if _http.request(HOST + TAGS_ENDPOINT) != OK:
		return false
	var result: Array = await _http.request_completed
	return int(result[1]) == 200


## Model stores worth looking in, best first.
##
## The other-users sweep is the one that matters and the one that looks odd. A
## Mac with two accounts, where the models were pulled under the other one, is
## how this bug arrived: the store is on the disk, readable, and eleven
## gigabytes, and the default path points at an empty directory beside it.
static func store_candidates() -> PackedStringArray:
	var out: PackedStringArray = []

	var configured: String = OS.get_environment("OLLAMA_MODELS")
	if configured != "":
		out.append(configured)

	var home: String = OS.get_environment("HOME")
	if home != "":
		out.append(home.path_join(".ollama/models"))

	for root in HOME_ROOTS:
		if not DirAccess.dir_exists_absolute(root):
			continue
		for name in DirAccess.get_directories_at(root):
			var store: String = root.path_join(name).path_join(".ollama/models")
			if not out.has(store):
				out.append(store)

	return out


## The first candidate that holds every one of `models`.
##
## "Holds" is checked against the manifests rather than by asking a server,
## because at this point there is no server to ask — that is the whole reason
## we are choosing a store.
static func pick_store(candidates: PackedStringArray, models: Array) -> String:
	for store in candidates:
		if store_has_models(store, models):
			return store
	return ""


static func store_has_models(store: String, models: Array) -> bool:
	if store == "" or not DirAccess.dir_exists_absolute(store):
		return false
	for model in models:
		if not FileAccess.file_exists(store.path_join(manifest_relative_path(str(model)))):
			return false
	return true


## Where Ollama files the manifest for a model name.
##
## `qwen3:14b` -> `manifests/registry.ollama.ai/library/qwen3/14b`. An unadorned
## name is a library model; one containing a slash already carries its namespace
## and is used as given. A name with no tag means `latest`, same as the CLI.
static func manifest_relative_path(model: String) -> String:
	var name: String = model
	var tag: String = "latest"

	var colon: int = name.rfind(":")
	if colon > 0:
		tag = name.substr(colon + 1)
		name = name.substr(0, colon)

	if not name.contains("/"):
		name = "library/" + name

	return "manifests/registry.ollama.ai".path_join(name).path_join(tag)


static func pick_binary(candidates: PackedStringArray) -> String:
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""
