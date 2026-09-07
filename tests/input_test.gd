extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func key(game: Node, code: int, pressed: bool, at: float) -> void:
	game.start = game.now()-at
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	game._unhandled_key_input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.meter_input.text = "3+2"
	check(game.settings() and game.beats == 5, "additive meter")
	game.dt = 0.5
	check(is_equal_approx(game.window(),0.13),"timing window expanded by 30 percent")
	game.dt = 0.15
	check(is_equal_approx(game.window(),0.0429),"fast BPM timing window expanded by 30 percent")
	game.meter_input.text = "4"
	game.start_practice()
	check(game.phase == "ready" and is_equal_approx(game.plan_start-game.ready_start,game.dt*4),"game opens with a four-beat Ready/Go count")
	var ready_plan: Array = game.plan.duplicate(true)
	key(game,KEY_D,true,0)
	check(game.plan == ready_plan,"Ready/Go count ignores combat input")
	game.ready_start = game.now()
	game.start = game.ready_start
	game.plan_start = game.now()+game.dt*4
	game._process(0.0)
	check(game.phase == "ready" and game.beat == 0 and game.sound.playing,"countdown starts with an audible beat")
	game.plan_start = game.now()-0.01
	game._process(0.0)
	check(game.phase == "plan" and not game.submitted,"planning begins only after Go")
	key(game,KEY_D,true,0)
	check(game.plan[0].k == "move" and game.ghost == [1,4],"on-beat movement")
	key(game,KEY_W,true,0.25)
	check(game.plan[1].k == "wait", "off-beat movement rejected")
	game.begin_plan(game.now())
	key(game,KEY_UP,true,0)
	game.update_hold_audio()
	check(game.hold_player.playing and game.hold_player.stream == game.charge_sound,"charge hold has its own looping sound")
	key(game,KEY_UP,false,0.25)
	game.update_hold_audio()
	check(game.plan[0].k == "attack" and game.plan[0].c == 0 and game.spent == 0,"off-beat short release produces a normal attack")
	check(not game.hold_player.playing,"hold sound stops on release")
	game.begin_plan(game.now())
	key(game,KEY_UP,true,1.5)
	key(game,KEY_UP,false,1.8)
	check(game.plan[3].k == "attack" and game.plan[3].c == 0,"last beat permits an unhurried normal release")
	game.begin_plan(game.now())
	key(game,KEY_UP,true,1.5)
	game.seal_plan()
	check(game.plan[3].k == "attack" and game.plan[3].c == 0,"last beat hold resolves to a normal attack")
	game.begin_plan(game.now())
	key(game,KEY_UP,true,0.25)
	key(game,KEY_UP,false,0.3)
	check(game.plan[0].k == "wait","normal attacks still require an on-beat press")
	game.begin_plan(game.now())
	key(game,KEY_UP,true,0)
	game.extend_hold(1)
	game.extend_hold(2)
	game.extend_hold(3)
	key(game,KEY_UP,false,1.5)
	check(game.plan[3].k == "attack" and game.plan[3].c == 3 and game.spent == 3,"three-beat charge")
	check(game.success_player.playing,"on-beat charge release plays a success chord")
	check(game.ghost == [0,4], "charge occupies movement slots")
	game.begin_plan(game.now())
	key(game,KEY_UP,true,0)
	game.extend_hold(1)
	key(game,KEY_UP,false,0.7)
	check(game.spent == 0 and game.plan.all(func(a):return a.k == "wait"),"bad release refunds entire charge")
	game.begin_plan(game.now())
	key(game,KEY_SHIFT,true,0)
	game.update_hold_audio()
	check(game.hold_player.playing and game.hold_player.stream == game.guard_sound,"guard hold has a distinct looping sound")
	game.extend_hold(1)
	key(game,KEY_SHIFT,false,0.7)
	check(game.penalty == 3 and game.plan[1].release == 3,"off-beat guard release")
	game.begin_plan(game.now())
	key(game,KEY_SHIFT,true,0)
	key(game,KEY_SHIFT,false,0.5)
	check(game.penalty == 1,"on-beat guard release")
	check(game.success_player.playing,"on-beat guard release plays a success chord")
	var danger_on: Color = game.player_color_for(game.CYAN,1,0.0,0.0)
	var danger_off: Color = game.player_color_for(game.CYAN,1,0.0,0.2)
	check(danger_on != danger_off and danger_off.a < danger_on.a,"one HP players blink regardless of player index")
	check(game.player_color_for(game.CORAL,1,0.0,0.0) != game.player_color_for(game.CORAL,1,0.0,0.2),"opponent one HP uses the same blink")
	game.me = 1
	game.begin_plan(game.now())
	key(game,KEY_W,true,0)
	check(game.plan[0].d == [0,1],"second player's controls rotate with the board")
	game.me = 0
	game.begin_plan(game.now())
	key(game,KEY_D,true,0.12)
	check(game.plan[0].k == "move","previously late input is now accepted")
	game.begin_plan(game.now())
	key(game,KEY_D,true,0.145)
	check(game.plan[0].k == "wait","input outside expanded window still rejected")
	game.state = game.Rules.initial(5)
	game.begin_plan(game.now()-game.beats*game.dt)
	game.seal_plan()
	check(is_equal_approx(game.action_start-game.start,(game.beats+1)*game.dt),"one transition beat scheduled")
	game._process(0.0)
	check(game.phase == "transition" and game.action_step == -1,"transition does not execute actions")
	var frozen_plan: Array = game.plan.duplicate(true)
	key(game,KEY_D,true,0)
	check(game.plan == frozen_plan,"transition ignores combat inputs")
	game.action_start = game.now()-0.01
	game._process(0.0)
	check(game.phase == "action","transition enters action at scheduled time")
	game.action_start = game.now()-game.beats*game.dt-0.01
	game.next_start = game.action_start+(game.beats+1)*game.dt
	game._process(0.0)
	check(game.phase == "transition_plan","action ends in a separate return beat")
	var completed_round := int(game.state.round)
	key(game,KEY_D,true,0)
	check(game.phase == "transition_plan" and int(game.state.round) == completed_round,"return beat ignores input and does not advance turns")
	game.next_start = game.now()-0.01
	game._process(0.0)
	check(game.phase == "plan" and not game.submitted,"planning resumes after the return beat")
	var item_state: Dictionary = game.Rules.initial(5)
	item_state.items = [[2,2]]
	for i in 100:
		item_state = game.Rules.finish(item_state,[0,0],game.rng)
		check(item_state.items.size() == 1,"CPU item spawns replace the previous item")
	for n in [3,5,10]:
		game.size_input.value = n
		game.start_practice()
		for round_index in 20:
			game.seal_plan()
			check(not game.frames.is_empty(),"CPU replay generated")
			game.state = game.final_state
			if game.state.hp[0] <= 0: break
			game.begin_plan(game.now())
	print("INPUT / CPU TESTS: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	game.queue_free()
	await process_frame
	quit(failures)
