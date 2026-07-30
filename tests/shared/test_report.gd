extends RefCounted

# Shared failure collector: every suite asserts relations, never authored numbers, so retuning a
# planet keeps the suite green while a broken behaviour still fails.

var failures: Array[String] = []


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func expect_close(value: float, expected: float, tolerance: float, message: String) -> void:
	expect(is_finite(value) and absf(value - expected) <= tolerance, "%s (got %f, expected %f +/- %f)" % [message, value, expected, tolerance])


func expect_between(value: float, minimum: float, maximum: float, message: String) -> void:
	expect(value > minimum and value < maximum, "%s (got %f, expected between %f and %f)" % [message, value, minimum, maximum])


func expect_decreasing(values: Array[float], message: String) -> void:
	for index in range(1, values.size()):
		if values[index] >= values[index - 1]:
			failures.append("%s (sample %d rose from %f to %f)" % [message, index, values[index - 1], values[index]])
			return


func finish(label: String, tree: SceneTree) -> void:
	if failures.is_empty():
		print("%s passed" % label)
		tree.quit(0)
		return
	for failure in failures:
		push_error("%s: %s" % [label, failure])
	tree.quit(1)
