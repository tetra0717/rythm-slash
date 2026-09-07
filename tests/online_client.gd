extends SceneTree
var game: Node
var elapsed := 0.0
var checked := false
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.bpm_input.value = 400
	game.meter_input.text = "3+2"
	game.room_input.text = "GODOT-INTEGRATION"
	game.connect_room()
func _process(delta: float) -> bool:
	elapsed += delta
	if game == null: return false
	if game.phase == "action" and game.state.round >= 1 and not checked:
		checked = true
		print("ONLINE CLIENT ",game.me," ROUND ",game.state.round," FINAL ",JSON.stringify(game.final_state,"",true))
	if checked and elapsed > 7.5:
		game.disconnect_room()
		game.queue_free()
		quit(0)
	if elapsed > 12:
		print("TIMEOUT: ",game.phase," / ",game.status.text," / round ",game.state.round," / offset ",game.offset)
		push_error("Online client failed to complete two rounds")
		quit(1)
	return false
