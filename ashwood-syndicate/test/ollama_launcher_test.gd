## Choosing a model store, without a server or a network.
##
## The bug this covers is not a crash. A server pointed at an empty store
## answers every request happily with zero models, the dialogue layer falls
## back to templates exactly as designed, and nothing anywhere reports a
## problem. So the store choice is checked against the manifests on disk, and
## that check is what these tests exercise.
extends GdUnitTestSuite

## A store built by hand, so the tests do not depend on what this machine has
## actually pulled.
var _root: String


func before_test() -> void:
	_root = OS.get_user_data_dir().path_join("launcher_test")
	_wipe()
	DirAccess.make_dir_recursive_absolute(_root)


func after_test() -> void:
	_wipe()


func _wipe() -> void:
	if _root != "" and DirAccess.dir_exists_absolute(_root):
		OS.move_to_trash(_root)


## Writes a manifest for `model` into `store`, the way `ollama pull` would.
func _install(store: String, model: String) -> void:
	var path: String = store.path_join(OllamaLauncher.manifest_relative_path(model))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{}")
	file.close()


func test_manifest_path_matches_ollama_layout() -> void:
	assert_str(OllamaLauncher.manifest_relative_path("qwen3:14b")) \
		.is_equal("manifests/registry.ollama.ai/library/qwen3/14b")


## The CLI treats a bare name as :latest, and so must we — otherwise a store
## holding the model is rejected for not holding a tag nobody typed.
func test_an_untagged_model_is_latest() -> void:
	assert_str(OllamaLauncher.manifest_relative_path("qwen3")) \
		.is_equal("manifests/registry.ollama.ai/library/qwen3/latest")


## A name carrying its own namespace is not a library model and must not be
## given the library prefix on top of it.
func test_a_namespaced_model_keeps_its_namespace() -> void:
	assert_str(OllamaLauncher.manifest_relative_path("hf.co/bartowski/qwen:q4")) \
		.is_equal("manifests/registry.ollama.ai/hf.co/bartowski/qwen/q4")


func test_a_store_holding_every_model_is_accepted() -> void:
	_install(_root, "qwen3:14b")
	_install(_root, "qwen3:4b")
	assert_bool(OllamaLauncher.store_has_models(_root, ["qwen3:14b", "qwen3:4b"])).is_true()


## The half-stocked store is the interesting rejection: picking it would leave
## intent reading working and every spoken line canned, which reads as a bug in
## the dialogue writing rather than a missing model.
func test_a_store_missing_one_model_is_rejected() -> void:
	_install(_root, "qwen3:4b")
	assert_bool(OllamaLauncher.store_has_models(_root, ["qwen3:14b", "qwen3:4b"])).is_false()


## This is the failure that started it: the default store exists, is perfectly
## valid, and is empty, because the models were pulled under another account.
func test_an_empty_store_is_rejected() -> void:
	assert_bool(OllamaLauncher.store_has_models(_root, ["qwen3:14b"])).is_false()


func test_a_missing_store_is_rejected() -> void:
	var absent: String = _root.path_join("nothing-here")
	assert_bool(OllamaLauncher.store_has_models(absent, ["qwen3:14b"])).is_false()


## Order is the point: the stocked store wins even though the empty one is
## listed first, which is what makes the default path not being the right path
## a recoverable situation rather than a silent template fallback.
func test_the_first_stocked_store_wins_over_an_earlier_empty_one() -> void:
	var empty: String = _root.path_join("empty")
	var stocked: String = _root.path_join("stocked")
	DirAccess.make_dir_recursive_absolute(empty)
	_install(stocked, "qwen3:14b")

	var chosen: String = OllamaLauncher.pick_store(
		PackedStringArray([empty, stocked]), ["qwen3:14b"]
	)
	assert_str(chosen).is_equal(stocked)


func test_no_stocked_store_picks_nothing() -> void:
	var chosen: String = OllamaLauncher.pick_store(PackedStringArray([_root]), ["qwen3:14b"])
	assert_str(chosen).is_empty()


func test_a_binary_that_does_not_exist_is_not_picked() -> void:
	var chosen: String = OllamaLauncher.pick_binary(
		PackedStringArray([_root.path_join("no/such/ollama")])
	)
	assert_str(chosen).is_empty()


## Every candidate store is absolute. A relative one would resolve against
## Godot's working directory, which is the project folder and never where a
## model lives.
func test_candidate_stores_are_absolute_paths() -> void:
	for store in OllamaLauncher.store_candidates():
		assert_str(store).starts_with("/")
