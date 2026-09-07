class_name BattleRules
extends RefCounted

static func initial(n: int) -> Dictionary:
	return {"n": n, "pos": [[0, n-1], [n-1, 0]], "hp": [3, 3], "energy": [3, 3], "cool": [0, 0], "items": [], "round": 0}

static func cells(p: Array, d: Array, charge: int) -> Array:
	var forward := [p[0]+d[0], p[1]+d[1]]
	var side := [-int(d[1]), int(d[0])]
	match charge:
		0: return [forward]
		1: return [forward, [p[0]+2*d[0], p[1]+2*d[1]]]
		2: return [forward, [p[0]+side[0], p[1]+side[1]], [p[0]-side[0], p[1]-side[1]]]
	return [forward, [p[0]+2*d[0], p[1]+2*d[1]], [forward[0]+side[0], forward[1]+side[1]], [forward[0]-side[0], forward[1]-side[1]]]

static func inside(p: Array, n: int) -> bool:
	return p[0] >= 0 and p[1] >= 0 and p[0] < n and p[1] < n

static func step(state: Dictionary, actions: Array) -> Dictionary:
	var s: Dictionary = state.duplicate(true)
	var targets: Array = s.pos.duplicate(true)
	var hits := [false, false]
	var zones := [[], []]
	for i in 2:
		var a: Dictionary = actions[i]
		if a.get("k", "") == "move":
			var p := [s.pos[i][0]+a.d[0], s.pos[i][1]+a.d[1]]
			if inside(p, int(s.n)): targets[i] = p
	if targets[0] == targets[1] or (targets[0] == s.pos[1] and targets[1] == s.pos[0]): targets = s.pos.duplicate(true)
	s.pos = targets
	for i in 2:
		var a: Dictionary = actions[i]
		if a.get("k", "") == "attack":
			var c := int(a.get("c", 0))
			if c <= s.energy[i]:
				s.energy[i] -= c
				zones[i] = cells(s.pos[i], a.d, c)
				hits[1-i] = s.pos[1-i] in zones[i] and actions[1-i].get("k", "") != "guard"
	for i in 2:
		if hits[i]: s.hp[i] -= 1
		if s.pos[i] in s.items:
			s.items.erase(s.pos[i])
			s.energy[i] = mini(3, s.energy[i]+1)
	return {"state": s, "hits": hits, "zones": zones, "actions": actions}

static func finish(state: Dictionary, penalties: Array, rng: RandomNumberGenerator) -> Dictionary:
	var s: Dictionary = state.duplicate(true)
	for i in 2: s.cool[i] = maxi(int(s.cool[i])-1, int(penalties[i]))
	s.round += 1
	if rng.randf() < 0.3:
		var candidates: Array = []
		var best := 999
		for x in int(s.n):
			for y in int(s.n):
				var p := [x, y]
				if p in s.pos or p in s.items: continue
				var delta: int = absi(absi(x-s.pos[0][0])+absi(y-s.pos[0][1])-absi(x-s.pos[1][0])-absi(y-s.pos[1][1]))
				if delta < best:
					best = delta
					candidates.clear()
				if delta == best: candidates.append(p)
		if not candidates.is_empty(): s.items = [candidates[rng.randi_range(0, candidates.size()-1)]]
	return s
