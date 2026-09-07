extends SceneTree
const Rules = preload("res://scripts/rules.gd")
func _initialize() -> void:
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tests/parity.json"))
	var failures := 0
	for c in cases:
		var actual := Rules.step(c.s,c.actions)
		# JSON normalizes integer/float values and dictionary key ordering.
		if JSON.stringify(actual,"",true) != JSON.stringify(c.expected,"",true):
			failures += 1
			push_error("Parity mismatch: " + JSON.stringify(c))
	print("GD / JS RULE PARITY: ",cases.size()," cases, ",failures," failures")
	quit(failures)
