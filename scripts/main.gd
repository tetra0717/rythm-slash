extends Node2D

const Rules = preload("res://scripts/rules.gd")
const CYAN := Color("64f5d2")
const CORAL := Color("ff796d")
const INK := Color("0a1220")
const MUTED := Color("65778e")
var state: Dictionary = Rules.initial(5)
var groups: Array = [4]
var beats := 4
var bpm := 120.0
var dt := 0.5
var phase := "menu"
var start := 0.0
var beat := -1
var pulse := 0.0
var miss := 0.0
var hit_flash := [0.0, 0.0]
var plan: Array = []
var ghost: Array = [0, 4]
var held_key := 0
var charge_start := -1
var charge_dir: Array = [0, -1]
var guarding := false
var guard_start := -1
var penalty := 0
var spent := 0
var submitted := false
var frames: Array = []
var final_state: Dictionary = {}
var action_start := 0.0
var next_start := 0.0
var action_step := -1
var zones: Array = [[], []]
var current_actions: Array = [{"k":"wait"},{"k":"wait"}]
var me := 0
var online := false
var socket: WebSocketPeer
var joined := false
var offset := 0.0
var best_rtt := 99999.0
var last_ping := -999.0
var connect_time := 0.0
var rng := RandomNumberGenerator.new()
var menu: Control
var status: Label
var size_input: SpinBox
var bpm_input: SpinBox
var meter_input: LineEdit
var room_input: LineEdit
var server_input: LineEdit
var calibration: SpinBox
var volume: HSlider
var sound: AudioStreamPlayer
var kick: AudioStreamWAV
var tick: AudioStreamWAV
var fail_sound: AudioStreamWAV
var transition_sound: AudioStreamWAV
var hold_player: AudioStreamPlayer
var charge_sound: AudioStreamWAV
var guard_sound: AudioStreamWAV
var success_player: AudioStreamPlayer
var success_sound: AudioStreamWAV
var ready_start := 0.0
var plan_start := 0.0
var font: Font
var result := ""
var copy_button: Button
var checked_beat := -1

func _ready() -> void:
	rng.randomize()
	font = load("res://assets/NotoSansJP.ttf")
	sound = AudioStreamPlayer.new()
	add_child(sound)
	kick = make_tone(150.0, 0.12)
	tick = make_tone(700.0, 0.045)
	fail_sound = make_tone(65.0, 0.09)
	transition_sound = make_transition_sound()
	hold_player = AudioStreamPlayer.new()
	add_child(hold_player)
	charge_sound = make_hold_sound(220.0)
	guard_sound = make_hold_sound(165.0)
	success_player = AudioStreamPlayer.new()
	add_child(success_player)
	success_sound = make_success_sound()
	build_menu()
	if OS.has_feature("web"):
		var room_value = JavaScriptBridge.eval("new URL(location.href).searchParams.get('room') || ''")
		if room_value != null and not str(room_value).is_empty(): room_input.text = str(room_value)
		server_input.text = str(JavaScriptBridge.eval("(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'"))
	queue_redraw()

func make_tone(freq: float, duration: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var data := PackedByteArray()
	data.resize(int(duration*44100)*2)
	for i in int(duration*44100):
		var t := float(i)/44100.0
		var v := sin(TAU*freq*t + 3.0*(1.0-exp(-t*35.0)))*exp(-t*45.0)*0.6
		data.encode_s16(i*2, int(v*32767))
	stream.data = data
	return stream

func make_transition_sound() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var data := PackedByteArray()
	data.resize(15435*2)
	for i in 15435:
		var t := float(i)/44100.0
		var chord := sin(TAU*330*t)+0.6*sin(TAU*495*t)+0.35*sin(TAU*660*t)
		var envelope := minf(1.0,t*180.0)*exp(-t*11.0)
		data.encode_s16(i*2,int(chord*envelope*0.35*32767))
	stream.data = data
	return stream

func make_hold_sound(frequency: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = 8820
	var data := PackedByteArray()
	data.resize(8820*2)
	for i in 8820:
		var t := float(i)/44100.0
		var v := (sin(TAU*frequency*t)+0.25*sin(TAU*frequency*2*t))*(0.8+0.2*cos(TAU*5*t))*0.2
		data.encode_s16(i*2,int(v*32767))
	stream.data = data
	return stream

func make_success_sound() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var sample_count := 13230
	var data := PackedByteArray()
	data.resize(sample_count*2)
	for i in sample_count:
		var t := float(i)/44100.0
		var chord := sin(TAU*523.25*t)+0.72*sin(TAU*659.25*t)+0.55*sin(TAU*783.99*t)
		var shimmer := 0.18*sin(TAU*1567.98*t)
		var envelope := minf(1.0,t*140.0)*exp(-t*10.0)
		data.encode_s16(i*2,int((chord*0.25+shimmer)*envelope*32767))
	stream.data = data
	return stream

func play_success() -> void:
	success_player.stream = success_sound
	success_player.volume_db = linear_to_db(maxf(0.0001,volume.value*0.9))
	success_player.pitch_scale = 1.0
	success_player.play()

func update_hold_audio() -> void:
	if phase != "plan" or submitted or not (guarding or charge_start >= 0):
		hold_player.stop()
		return
	var desired := guard_sound if guarding else charge_sound
	if hold_player.stream != desired or not hold_player.playing:
		hold_player.stream = desired
		hold_player.play()
	var level := clampi(floori((now()-start)/dt)-charge_start,0,3)
	hold_player.pitch_scale = 1.0 if guarding else 1.0+0.12*level
	hold_player.volume_db = linear_to_db(maxf(0.0001,volume.value*0.65))

func label_at(parent: Node, text: String, p: Vector2, width: float, font_size := 18) -> Label:
	var l := Label.new()
	l.text = text
	l.position = p
	l.size.x = width
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l

func button_at(text: String, p: Vector2, width: float, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = p
	b.size = Vector2(width, 48)
	b.pressed.connect(callback)
	menu.add_child(b)
	return b

func build_menu() -> void:
	menu = Control.new()
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 17
	for kind in ["Label","Button","LineEdit","SpinBox"]:
		ui_theme.set_color("font_color",kind,Color("e8eef6"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("17283b")
	normal.border_color = Color("30455b")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	ui_theme.set_stylebox("normal","Button",normal)
	var hover := normal.duplicate()
	hover.border_color = CYAN
	hover.bg_color = Color("213d4b")
	ui_theme.set_stylebox("hover","Button",hover)
	ui_theme.set_stylebox("pressed","Button",hover)
	menu.theme = ui_theme
	add_child(menu)
	label_at(menu, "PULSE / SLASH", Vector2(96,74), 800, 58)
	label_at(menu, "READ THE NEXT BAR.", Vector2(100,145), 800, 18).modulate = CYAN
	label_at(menu, "リズムで読み、次の小節で斬る。", Vector2(100,189), 800, 23)
	label_at(menu, "FIELD", Vector2(100,261), 160).modulate = MUTED
	size_input = SpinBox.new()
	size_input.min_value = 3
	size_input.max_value = 10
	size_input.value = 5
	size_input.position = Vector2(100,295)
	size_input.size = Vector2(150,44)
	menu.add_child(size_input)
	label_at(menu, "BPM", Vector2(275,261), 150).modulate = MUTED
	bpm_input = SpinBox.new()
	bpm_input.min_value = 20
	bpm_input.max_value = 400
	bpm_input.value = 120
	bpm_input.position = Vector2(275,295)
	bpm_input.size = Vector2(150,44)
	menu.add_child(bpm_input)
	label_at(menu, "METER / 拍子", Vector2(450,261), 190).modulate = MUTED
	meter_input = LineEdit.new()
	meter_input.text = "4"
	meter_input.placeholder_text = "3 / 3+2 / 2+2+3"
	meter_input.position = Vector2(450,295)
	meter_input.size = Vector2(200,44)
	menu.add_child(meter_input)
	label_at(menu, "1〜32拍。+ でアクセントを区切れます。", Vector2(100,351), 600, 16).modulate = MUTED
	button_at("CPU と練習  →", Vector2(100,399), 550, start_practice)
	room_input = LineEdit.new()
	room_input.placeholder_text = "ROOM CODE"
	room_input.text = "SLASH-" + str(rng.randi_range(1000,9999))
	room_input.position = Vector2(100,477)
	room_input.size = Vector2(255,44)
	menu.add_child(room_input)
	button_at("ルーム作成 / 参加", Vector2(375,477), 275, connect_room)
	server_input = LineEdit.new()
	server_input.text = "ws://127.0.0.1:8080/ws"
	server_input.position = Vector2(100,539)
	server_input.size = Vector2(550,40)
	menu.add_child(server_input)
	copy_button = button_at("招待URLをコピー", Vector2(100,596), 260, copy_invite)
	button_at("接続を解除", Vector2(380,596), 270, disconnect_room)
	status = label_at(menu, "", Vector2(100,663), 1080, 17)
	status.modulate = CYAN
	label_at(menu, "HOW TO DUEL", Vector2(758,267), 390, 20).modulate = CYAN
	label_at(menu, "W A S D     移動\n↑ ← ↓ →     攻撃 / 長押しでタメ\nSHIFT         ガード / 放して解除\n\n光る拍に合わせて入力。\n半透明の自分で計画し、次の小節で実行。\nタメは最大3拍、放すタイミングも拍に。\nガード解除：成功1 / 失敗3ターン休み。\n\nESC  メニューへ", Vector2(758,312), 425, 18)
	label_at(menu, "入力補正 ms", Vector2(758,611), 180, 16).modulate = MUTED
	calibration = SpinBox.new()
	calibration.min_value = -250
	calibration.max_value = 250
	calibration.step = 5
	calibration.position = Vector2(918,604)
	calibration.size = Vector2(160,38)
	menu.add_child(calibration)
	label_at(menu, "音量", Vector2(758,665), 100, 16).modulate = MUTED
	volume = HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.01
	volume.value = 0.65
	volume.position = Vector2(850,667)
	volume.size = Vector2(230,24)
	menu.add_child(volume)

func settings() -> bool:
	var parsed: Array = []
	var total := 0
	for part in meter_input.text.split("+"):
		if not part.strip_edges().is_valid_int():
			status.text = "拍子は 3、5、3+2 などで入力してください。"
			return false
		var v := int(part)
		if v < 1 or v > 32:
			status.text = "拍子の各グループは1〜32にしてください。"
			return false
		parsed.append(v)
		total += v
	if total > 32:
		status.text = "1小節は1〜32拍にしてください。"
		return false
	groups = parsed
	beats = total
	bpm = bpm_input.value
	dt = 60.0/bpm
	return true

func now() -> float:
	return Time.get_ticks_msec()/1000.0 + (offset if online else 0.0)

func start_practice() -> void:
	if not settings(): return
	disconnect_room()
	me = 0
	state = Rules.initial(int(size_input.value))
	menu.hide()
	result = ""
	begin_ready(now()+0.25,now()+0.25+dt*4)

func begin_ready(at: float, first_plan_at: float) -> void:
	phase = "ready"
	ready_start = at
	plan_start = first_plan_at
	start = at
	beat = -1
	plan.clear()
	for i in beats: plan.append({"k":"wait"})
	ghost = state.pos[me].duplicate()
	submitted = true
	frames = []
	zones = [[], []]
	action_step = -1
	current_actions = [{"k":"wait"},{"k":"wait"}]

func begin_plan(at: float) -> void:
	phase = "plan"
	start = at
	beat = -1
	plan.clear()
	for i in beats: plan.append({"k":"wait"})
	ghost = state.pos[me].duplicate()
	held_key = 0
	charge_start = -1
	guarding = false
	penalty = 0
	spent = 0
	submitted = false
	checked_beat = -1
	frames = []
	zones = [[], []]
	action_step = -1
	current_actions = [{"k":"wait"},{"k":"wait"}]

func connect_room() -> void:
	if not settings(): return
	disconnect_room()
	online = true
	joined = false
	best_rtt = 99999
	offset = 0
	socket = WebSocketPeer.new()
	var error := socket.connect_to_url(server_input.text.strip_edges())
	connect_time = Time.get_ticks_msec()/1000.0
	if error != OK:
		status.text = "接続できません。サーバーURLを確認してください。"
		online = false
	else: status.text = "接続中…"

func disconnect_room() -> void:
	if socket != null: socket.close()
	socket = null
	online = false
	joined = false
	status.text = ""

func copy_invite() -> void:
	var base := server_input.text.replace("wss://","https://").replace("ws://","http://").trim_suffix("/ws") + "/"
	if OS.has_feature("web"): base = str(JavaScriptBridge.eval("location.origin + location.pathname"))
	var url := base + "?room=" + room_input.text.to_upper().uri_encode()
	DisplayServer.clipboard_set(url)
	status.text = "招待URL: " + url

func send_packet(data: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN: socket.send_text(JSON.stringify(data))

func poll_network() -> void:
	if socket == null: return
	socket.poll()
	var local_time := Time.get_ticks_msec()/1000.0
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if not joined:
			joined = true
			send_packet({"type":"join","room":room_input.text.to_upper(),"n":int(size_input.value),"bpm":bpm,"groups":groups})
		if local_time-last_ping > 0.4:
			last_ping = local_time
			send_packet({"type":"ping","time":local_time})
		while socket.get_available_packet_count() > 0:
			var data = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if data is Dictionary: receive(data)
	elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED or local_time-connect_time > 10 and not joined:
		disconnect_room()
		menu.show()
		phase = "menu"
		status.text = "接続が終了しました。サーバーを起動して再接続してください。"

func receive(m: Dictionary) -> void:
	match m.type:
		"pong":
			var local_time := Time.get_ticks_msec()/1000.0
			var rtt: float = local_time-float(m.echo)
			if rtt < best_rtt:
				best_rtt = rtt
				offset = float(m.time)/1000.0-(float(m.echo)+local_time)/2.0
		"joined":
			me = int(m.player)
			status.text = "ROOM " + str(m.room) + "  •  相手を待っています。招待URLを共有してください。"
		"start":
			state = m.state
			bpm = float(m.bpm)
			dt = 60.0/bpm
			groups = m.groups
			beats = 0
			for g in groups: beats += int(g)
			menu.hide()
			result = ""
			var first_plan_at := float(m.start)/1000.0
			var countdown_at := float(m.get("ready",m.start))/1000.0
			begin_ready(countdown_at,first_plan_at)
		"action":
			if int(m.round) != int(state.round): return
			frames = m.frames
			final_state = m.final
			action_start = float(m.start)/1000.0
			next_start = float(m.next)/1000.0
		"error": status.text = str(m.message)
		"left":
			phase = "menu"
			menu.show()
			status.text = "相手が退出しました。"

func _process(delta: float) -> void:
	poll_network()
	pulse = maxf(0, pulse-delta*5)
	miss = maxf(0, miss-delta*3)
	for i in 2: hit_flash[i] = maxf(0,hit_flash[i]-delta*3)
	if phase == "ready":
		var ready_time := now()-ready_start
		var ready_beat := floori(ready_time/dt)
		if ready_beat != beat and ready_beat >= 0 and ready_beat < 4:
			beat = ready_beat
			pulse = 1.0
			sound.stream = kick if ready_beat == 3 else tick
			sound.pitch_scale = 1.35 if ready_beat == 3 else 0.85+ready_beat*0.08
			sound.volume_db = linear_to_db(maxf(0.0001,volume.value))
			sound.play()
		if now() >= plan_start: begin_plan(plan_start)
	elif phase == "plan":
		var t := now()-start
		var b := floori(t/dt)
		if b != beat and b < beats:
			beat = b
			play_beat(posmod(b, beats))
			if b >= 0: extend_hold(b)
		if not submitted and t >= beats*dt:
			seal_plan()
		var finished_beat := mini(floori((t-window()-0.01)/dt),beats-1)
		if finished_beat > checked_beat and finished_beat >= 0:
			checked_beat = finished_beat
			if plan[finished_beat].k == "wait": fail()
		if t >= beats*dt:
			phase = "transition"
			miss = 0.0
			pulse = 1.0
			sound.stream = transition_sound
			sound.pitch_scale = maxf(1.0,0.35/dt)
			sound.volume_db = linear_to_db(maxf(0.0001,volume.value))
			sound.play()
	elif phase == "transition":
		if not frames.is_empty() and now() >= action_start:
			phase = "action"
			beat = -1
		elif online and now() > start+(beats+1)*dt+5:
			return_menu("通信が遅延しました。再接続してください。")
	elif phase == "action":
		var b := mini(floori((now()-action_start)/dt), beats-1)
		if b != beat:
			beat = b
			play_beat(b)
		while action_step < mini(b,frames.size()-1):
			action_step += 1
			var f: Dictionary = frames[action_step]
			state = f.state
			zones = f.zones
			current_actions = f.actions
			for i in 2:
				if f.hits[i]: hit_flash[i] = 1.0
		var defeated: bool = state.hp[0] <= 0 or state.hp[1] <= 0
		if defeated and now() >= action_start+action_step*dt+minf(0.5,dt*0.8):
			phase = "result"
			result = "DRAW" if state.hp[0] <= 0 and state.hp[1] <= 0 else ("VICTORY" if state.hp[1-me] <= 0 else "DEFEAT")
		elif now() >= action_start+beats*dt:
			state = final_state
			if state.hp[0] <= 0 or state.hp[1] <= 0:
				phase = "result"
				result = "DRAW" if state.hp[0] <= 0 and state.hp[1] <= 0 else ("VICTORY" if state.hp[1-me] <= 0 else "DEFEAT")
			else:
				phase = "transition_plan"
				zones = [[], []]
				current_actions = [{"k":"wait"},{"k":"wait"}]
				miss = 0.0
				pulse = 1.0
				sound.stream = transition_sound
				sound.pitch_scale = maxf(0.75,0.35/dt)
				sound.volume_db = linear_to_db(maxf(0.0001,volume.value))
				sound.play()
	elif phase == "transition_plan":
		if now() >= next_start: begin_plan(next_start)
	update_hold_audio()
	queue_redraw()

func window() -> float:
	return minf(0.13, dt*0.286)

func play_beat(b: int) -> void:
	pulse = 1.0
	var accent := false
	var total := 0
	for g in groups:
		if b == total: accent = true
		total += int(g)
	sound.stream = kick if accent else tick
	sound.pitch_scale = 1.0
	sound.volume_db = linear_to_db(maxf(0.0001,volume.value))
	sound.play()

func fail() -> void:
	miss = 1.0
	sound.stream = fail_sound
	sound.play()

func input_beat() -> int:
	var t := now()-start-calibration.value/1000.0
	var b := roundi(t/dt)
	if b < 0 or b >= beats or absf(t-b*dt) > window(): return -1
	return b

func extend_hold(b: int) -> void:
	if submitted: return
	if guarding and b >= guard_start:
		plan[b] = {"k":"guard"}
	elif charge_start >= 0 and b > charge_start:
		plan[b] = {"k":"charge","d":charge_dir.duplicate()}

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo: return
	var key: int = event.physical_keycode
	if event.pressed and key == KEY_ESCAPE:
		return_menu("")
		return
	if phase == "result" and event.pressed:
		return_menu("")
		return
	if phase != "plan" or submitted: return
	var b := input_beat()
	if not event.pressed:
		if key == KEY_SHIFT and guarding:
			var release_at := b if b >= 0 else clampi(ceili((now()-start)/dt),0,beats-1)
			penalty = 1 if b >= 0 else 3
			guarding = false
			if release_at > guard_start:
				plan[release_at] = {"k":"wait","bad":b < 0}
			elif b < 0: plan[release_at]["bad"] = true
			for j in range(beats-1,-1,-1):
				if plan[j].k == "guard":
					plan[j]["release"] = penalty
					break
			if b < 0: fail()
			else: play_success()
		if key == held_key and charge_start >= 0:
			var c := b-charge_start
			var release_time := now()-start-calibration.value/1000.0
			if b == charge_start or (b < 0 and release_time < (charge_start+1)*dt):
				plan[charge_start] = {"k":"attack","d":charge_dir.duplicate(),"c":0}
			elif b >= 0 and c >= 1 and c <= 3 and c <= state.energy[me]-spent:
				plan[b] = {"k":"attack","d":charge_dir.duplicate(),"c":c}
				spent += c
				play_success()
			else:
				for j in range(charge_start,beats):
					if plan[j].get("k") == "charge": plan[j] = {"k":"wait"}
				fail()
			charge_start = -1
			held_key = 0
		return
	if b < 0:
		fail()
		return
	if guarding or charge_start >= 0: return
	if plan[b].k != "wait":
		fail()
		return
	var moves := {KEY_W:[0,-1],KEY_S:[0,1],KEY_A:[-1,0],KEY_D:[1,0]}
	var attacks := {KEY_UP:[0,-1],KEY_DOWN:[0,1],KEY_LEFT:[-1,0],KEY_RIGHT:[1,0]}
	if me == 1:
		for k in moves: moves[k] = [-moves[k][0],-moves[k][1]]
		for k in attacks: attacks[k] = [-attacks[k][0],-attacks[k][1]]
	if moves.has(key):
		plan[b] = {"k":"move","d":moves[key]}
		var p := [ghost[0]+moves[key][0],ghost[1]+moves[key][1]]
		if Rules.inside(p,int(state.n)): ghost = p
		else: fail()
	elif attacks.has(key):
		charge_start = b
		charge_dir = attacks[key]
		held_key = key
		plan[b] = {"k":"charge","d":charge_dir.duplicate()}
	elif key == KEY_SHIFT:
		if state.cool[me] > 0 or penalty > 0:
			fail()
			return
		guard_start = b
		guarding = true
		plan[b] = {"k":"guard"}

func seal_plan() -> void:
	if charge_start >= 0:
		if charge_start == beats-1:
			plan[charge_start] = {"k":"attack","d":charge_dir.duplicate(),"c":0}
		else:
			for j in range(charge_start,beats):
				if plan[j].get("k") == "charge": plan[j] = {"k":"wait"}
			fail()
		charge_start = -1
	if guarding: penalty = 1
	guarding = false
	submitted = true
	if online:
		send_packet({"type":"plan","round":state.round,"plan":plan})
	else:
		var cpu := cpu_plan()
		var s: Dictionary = state.duplicate(true)
		frames = []
		for b in beats:
			var f: Dictionary = Rules.step(s,[plan[b],cpu[b]])
			frames.append(f)
			s = f.state
			if s.hp[0] <= 0 or s.hp[1] <= 0: break
		final_state = Rules.finish(s,[penalty,1 if cpu.any(func(a): return a.k == "guard") else 0],rng)
		action_start = start+(beats+1)*dt
		next_start = action_start+(beats+1)*dt

func cpu_plan() -> Array:
	var output: Array = []
	var p: Array = state.pos[1].duplicate()
	var target: Array = state.pos[0]
	var used_guard := false
	for b in beats:
		var dx := int(target[0]-p[0])
		var dy := int(target[1]-p[1])
		var d := [signi(dx),0] if absi(dx) > absi(dy) else [0,signi(dy)]
		if d == [0,0]: d = [0,1]
		if absi(dx)+absi(dy) == 1 and rng.randf() < 0.8:
			output.append({"k":"attack","d":d,"c":0})
		elif state.cool[1] == 0 and not used_guard and rng.randf() < 0.12:
			output.append({"k":"guard"})
			used_guard = true
		else:
			output.append({"k":"move","d":d})
			var q := [p[0]+d[0],p[1]+d[1]]
			if Rules.inside(q,int(state.n)): p = q
	return output

func return_menu(message: String) -> void:
	hold_player.stop()
	success_player.stop()
	disconnect_room()
	phase = "menu"
	menu.show()
	status.text = message

func point(p: Array) -> Vector2:
	var cell := 480.0/float(state.n)
	var view := Vector2(float(p[0]),float(p[1]))
	if me == 1: view = Vector2.ONE*(float(state.n)-1)-view
	return Vector2(400,160)+(view+Vector2(0.5,0.5))*cell

func text_at(text: String, p: Vector2, color: Color, font_size := 16) -> void:
	draw_string(font,p,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func shield(p: Vector2, color: Color, radius := 22.0) -> void:
	draw_polyline(PackedVector2Array([p+Vector2(-radius,-radius*.7),p+Vector2(radius,-radius*.7),p+Vector2(radius*.8,radius*.35),p+Vector2(0,radius),p+Vector2(-radius*.8,radius*.35),p+Vector2(-radius,-radius*.7)]),color,2.5,true)

func arrow(p: Vector2, d: Array, color: Color, length := 14.0) -> void:
	var v := Vector2(float(d[0]),float(d[1]))
	if me == 1: v = -v
	var s := Vector2(-v.y,v.x)
	draw_line(p-v*length,p+v*length,color,2.5,true)
	draw_polyline(PackedVector2Array([p+v*length-v*7+s*6,p+v*length,p+v*length-v*7-s*6]),color,2.5,true)

func player_color_for(base: Color, hp: int, damage_flash: float, at: float) -> Color:
	if damage_flash > 0.0: return base.lerp(Color.WHITE,damage_flash)
	if hp == 1: return Color.WHITE if fmod(at,0.34) < 0.17 else Color(base,0.18)
	return base

func _draw() -> void:
	# Fixed logical canvas; canvas_items scales to the window.
	var backdrop := INK
	if phase == "plan": backdrop = Color("08333c")
	elif phase == "action": backdrop = Color("401925")
	elif phase == "transition": backdrop = Color("493818")
	elif phase == "transition_plan": backdrop = Color("193c50")
	elif phase == "ready": backdrop = Color("101c35")
	draw_rect(Rect2(0,0,1280,800),backdrop)
	for x in range(0,1280,40): draw_line(Vector2(x,0),Vector2(x,800),Color(0.15,0.22,0.3,0.10))
	for y in range(0,800,40): draw_line(Vector2(0,y),Vector2(1280,y),Color(0.15,0.22,0.3,0.10))
	if phase == "menu":
		draw_line(Vector2(710,260),Vector2(710,710),Color("26354a"),1)
		return
	var cell := 480.0/float(state.n)
	var phase_color := CYAN if phase == "plan" else CORAL
	if phase == "transition": phase_color = Color("ffe39a")
	elif phase == "transition_plan": phase_color = CYAN
	elif phase == "ready": phase_color = Color("f4f8ff")
	draw_rect(Rect2(0,0,1280,7),phase_color)
	draw_rect(Rect2(0,793,1280,7),phase_color)
	text_at("PULSE / SLASH",Vector2(62,60),Color("dfe9f6"),22)
	text_at("%03d" % int(bpm),Vector2(1100,60),MUTED,22)
	text_at("BPM",Vector2(1162,60),MUTED,12)
	# A hollow diamond means planning; a play triangle means execution.
	if phase == "plan":
		draw_polyline(PackedVector2Array([Vector2(626,51),Vector2(640,37),Vector2(654,51),Vector2(640,65),Vector2(626,51)]),CYAN,3,true)
	elif phase != "ready": draw_colored_polygon(PackedVector2Array([Vector2(630,36),Vector2(630,64),Vector2(653,50)]),CORAL)
	text_at("READY" if phase == "ready" else ("計画" if phase == "plan" else ("計画へ" if phase == "transition_plan" else ("行動へ" if phase == "transition" else "行動"))),Vector2(679,61),phase_color,26)
	var displayed_beats := 4 if phase == "ready" else beats
	var spacing := minf(52,650.0/displayed_beats)
	var origin := 640.0-(displayed_beats-1)*spacing/2
	var accents: Array = [0]
	if phase == "ready":
		accents.append(3)
	else:
		var total := 0
		for g in groups:
			total += int(g)
			accents.append(total)
	for b in displayed_beats:
		var p := Vector2(origin+b*spacing,108)
		var active := b == beat if phase == "ready" else b == posmod(beat,beats)
		draw_circle(p,(8 if b in accents else 5)+(4*pulse if active else 0),phase_color if active else Color("2d4055"))
		if active: draw_arc(p,19+(1-pulse)*10,0,TAU,40,Color(phase_color,0.4*pulse),2,true)
	for x in int(state.n):
		for y in int(state.n):
			var rect := Rect2(Vector2(400+x*cell,160+y*cell)+Vector2(2,2),Vector2.ONE*(cell-4))
			draw_rect(rect,Color("142234") if (x+y)%2 == 0 else Color("111e2f"))
	draw_rect(Rect2(398,158,484,484),Color(phase_color,0.22+0.2*pulse),false,2)
	for p in state.items:
		var c := point(p)
		draw_colored_polygon(PackedVector2Array([c+Vector2(0,-12),c+Vector2(9,0),c+Vector2(0,12),c+Vector2(-9,0)]),Color("ffe39a"))
	for i in 2:
		var color := CYAN if i == me else CORAL
		for p in zones[i]:
			if Rules.inside(p,int(state.n)):
				draw_rect(Rect2(point(p)-Vector2.ONE*(cell*.46),Vector2.ONE*cell*.92),Color(color,0.15+0.3*pulse))
		var c := point(state.pos[i])
		var radius := cell*0.25*(1.0+0.18*pulse)
		if hit_flash[i] > 0: c += Vector2(sin(Time.get_ticks_msec()*0.09)*7*hit_flash[i],0)
		var player_color := player_color_for(color,int(state.hp[i]),hit_flash[i],now())
		draw_rect(Rect2(c-Vector2.ONE*radius,Vector2.ONE*radius*2),player_color)
		draw_rect(Rect2(c-Vector2.ONE*(radius+5),Vector2.ONE*(radius+5)*2),Color(color,0.15*pulse),false,3)
		if current_actions[i].get("k") == "guard": shield(c,color,cell*0.43)
		if hit_flash[i] > 0: draw_arc(c,cell*.46,0,TAU,40,Color(CORAL,hit_flash[i]),4,true)
	if phase == "plan":
		var c := point(ghost)
		draw_rect(Rect2(c-Vector2.ONE*cell*.3,Vector2.ONE*cell*.6),Color(CYAN,0.22))
		draw_rect(Rect2(c-Vector2.ONE*cell*.3,Vector2.ONE*cell*.6),CYAN,false,2)
		if guarding: shield(c,CYAN,cell*.45)
		if charge_start >= 0:
			var charge := clampi(maxi(beat,input_beat())-charge_start,0,3)
			for p in Rules.cells(ghost,charge_dir,charge):
				if Rules.inside(p,int(state.n)): draw_rect(Rect2(point(p)-Vector2.ONE*cell*.42,Vector2.ONE*cell*.84),Color(CYAN,0.18))
	for i in 2:
		var own := i == me
		var color := CYAN if own else CORAL
		var p := Vector2(140,480) if own else Vector2(972,220)
		draw_rect(Rect2(p-Vector2(22,60),Vector2(182,170)),Color("101d2d"))
		draw_rect(Rect2(p-Vector2(22,60),Vector2(3,170)),color)
		for j in 3:
			var c := p+Vector2(j*42,0)
			draw_circle(c,11,color if j < state.hp[i] else Color("29394c"))
			var e := c+Vector2(0,40)
			draw_colored_polygon(PackedVector2Array([e+Vector2(0,-10),e+Vector2(8,0),e+Vector2(0,10),e+Vector2(-8,0)]),Color("ffe39a") if j < state.energy[i] else Color("29394c"))
		var cooldown := int(state.cool[i])
		if own and phase == "plan" and penalty > 0: cooldown = penalty
		shield(p+Vector2(6,83),color if cooldown == 0 else MUTED,13)
		for j in cooldown: draw_circle(p+Vector2(42+j*22,83),5,MUTED)
	if phase == "plan" or phase == "action" or phase == "transition":
		var gap := minf(58,1050.0/beats)
		var tile := minf(44,gap-4)
		for b in beats:
			var p := Vector2(640-(beats-1)*gap/2+b*gap,708)
			draw_rect(Rect2(p-Vector2(tile/2,22),Vector2(tile,44)),Color("17283c"))
			var a: Dictionary = plan[b]
			match a.k:
				"move": arrow(p,a.d,CYAN,minf(14,tile*.3))
				"attack":
					arrow(p,a.d,CORAL,minf(14,tile*.3))
					for j in int(a.c): draw_circle(p+Vector2(-8+j*8,16),2,Color("ffe39a"))
				"guard": shield(p,CYAN,13)
				"charge": draw_circle(p,8,Color("ffe39a"),false,2)
				_: draw_circle(p,2,MUTED)
			if b == beat: draw_rect(Rect2(p-Vector2(tile/2+1,23),Vector2(tile+2,46)),phase_color,false,2)
	if miss > 0:
		draw_rect(Rect2(3,3,1274,794),Color(CORAL,miss),false,5)
		draw_line(Vector2(632,758),Vector2(648,774),Color(CORAL,miss),4,true)
		draw_line(Vector2(648,758),Vector2(632,774),Color(CORAL,miss),4,true)
	if phase == "transition" or phase == "transition_plan":
		var returning := phase == "transition_plan"
		var transition_start := next_start-dt if returning else start+beats*dt
		var progress := clampf((now()-transition_start)/dt,0.0,1.0)
		var center := Vector2(640,400)
		draw_rect(Rect2(398,158,484,484),Color("17121b")*Color(1,1,1,0.72))
		draw_arc(center,48+(1.0-progress if returning else progress)*175,0,TAU,80,Color(phase_color,1.0-progress*0.8),5,true)
		if returning:
			var radius := 35.0+12.0*progress
			draw_polyline(PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius,0),center+Vector2(0,radius),center+Vector2(-radius,0),center+Vector2(0,-radius)]),phase_color,6,true)
		else:
			for j in 3:
				var p := center+Vector2((j-1)*55+progress*16,0)
				draw_polyline(PackedVector2Array([p+Vector2(-12,-23),p+Vector2(12,0),p+Vector2(-12,23)]),phase_color,6,true)
		draw_rect(Rect2(400,633,480*progress,7),phase_color)
	if phase == "ready":
		var countdown := clampi(floori((now()-ready_start)/dt),0,3)
		var center := Vector2(640,400)
		var ready_progress := clampf(fmod(maxf(0.0,now()-ready_start),dt)/dt,0.0,1.0)
		draw_rect(Rect2(398,158,484,484),Color("07101f"))
		draw_arc(center,76+ready_progress*44,0,TAU,80,Color(phase_color,1.0-ready_progress),5,true)
		if countdown < 3:
			text_at("READY",center+Vector2(-105,12),Color("dce8ff"),54)
			for j in 3:
				draw_circle(center+Vector2(-30+j*30,58),7,Color("8ba7d9") if j <= countdown else Color("30405b"))
		else:
			text_at("GO!",center+Vector2(-62,20),CYAN,74)
			draw_arc(center,122-ready_progress*48,0,TAU,80,Color(CYAN,1.0-ready_progress),8,true)
	if phase == "result":
		draw_rect(Rect2(0,280,1280,210),Color(INK,0.95))
		text_at(result,Vector2(470,375),CYAN if result == "VICTORY" else CORAL,54)
		text_at("キーを押してメニューへ",Vector2(505,432),MUTED,20)
