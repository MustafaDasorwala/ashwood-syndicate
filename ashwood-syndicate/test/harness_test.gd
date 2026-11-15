## Smoke test proving the gdUnit4 harness itself works headless.
extends GdUnitTestSuite


func test_harness_runs() -> void:
	assert_int(2 + 2).is_equal(4)


func test_assertions_can_fail_meaningfully() -> void:
	assert_str("ashwood").contains("wood")
