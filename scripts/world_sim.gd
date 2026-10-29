extends RefCounted

const SIZE: int = 64
const TILE_SIZE: int = 16
enum Terrain { WATER, SAND, GRASS, FOREST, MOUNTAIN, PATH }
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

var terrain: PackedInt32Array = PackedInt32Array()
var villagers: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var springs: Array[Dictionary] = []
var tick_count: int = 0
var elapsed: float = 0.0
var seed_value: int = 20261027
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func generate(seed_number: int = 20261027) -> void:
	seed_value = seed_number
	_rng.seed = seed_value
	tick_count = 0
	elapsed = 0.0
	terrain.resize(SIZE * SIZE)
	villagers.clear()
	springs.clear()
	landmarks = [
		{"name": "青禾村", "cell": Vector2i(31, 32), "kind": "village"},
		{"name": "山间古祠", "cell": Vector2i(42, 23), "kind": "shrine"},
		{"name": "听风竹林", "cell": Vector2i(20, 24), "kind": "bamboo"}
	]
	var noise := FastNoiseLite.new()
	noise.seed = seed_number
	noise.frequency = 0.065
	noise.fractal_octaves = 3
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var cell := Vector2i(x, y)
			var nx: float = (float(x) - 31.0) / 30.0
			var ny: float = (float(y) - 31.0) / 29.0
			var shape: float = 1.0 - Vector2(nx, ny).length() + noise.get_noise_2d(x, y) * 0.18
			var kind: int = Terrain.GRASS
			if shape < 0.13:
				kind = Terrain.WATER
			elif shape < 0.21:
				kind = Terrain.SAND
			elif noise.get_noise_2d(x + 150, y + 100) > 0.04:
				kind = Terrain.FOREST
			var mountain: float = pow((float(x) - 46.0) / 12.0, 2) + pow((float(y) - 15.0) / 10.0, 2)
			if shape >= 0.21 and mountain < 0.85 + noise.get_noise_2d(x, y) * 0.5:
				kind = Terrain.MOUNTAIN
			var lake: float = pow((float(x) - 16.0) / 6.0, 2) + pow((float(y) - 42.0) / 8.0, 2)
			if lake < 1.0 + noise.get_noise_2d(x + 80, y) * 0.3:
				kind = Terrain.WATER
			if cell.distance_to(Vector2i(31, 32)) < 7.5:
				kind = Terrain.GRASS
			terrain[y * SIZE + x] = kind
	# The settlement ring and three footpaths remain passable for every seed.
	for y: int in range(28, 37):
		for x: int in range(26, 37):
			if y == 28 or y == 36 or x == 26 or x == 36:
				terrain[y * SIZE + x] = Terrain.PATH
	_carve_path(Vector2i(31, 32), Vector2i(42, 23))
	_carve_path(Vector2i(31, 32), Vector2i(20, 24))
	_carve_path(Vector2i(26, 32), Vector2i(36, 32))
	_remove_disconnected_tiles()
	var spawn_cells: Array[Vector2i] = []
	for y: int in range(28, 37):
		for x: int in range(26, 37):
			if is_walkable(Vector2i(x, y)):
				spawn_cells.append(Vector2i(x, y))
	var surnames: Array[String] = ["林", "沈", "苏", "陆", "顾", "柳", "叶", "江", "方", "孟"]
	var given_names: Array[String] = ["青禾", "云舟", "清竹", "知夏", "长安", "望舒", "怀瑾", "听雨", "明溪", "归尘", "星河", "若水", "山月", "云岚", "景行"]
	var roots: Array[String] = ["金", "木", "水", "火", "土", "杂灵根", "无灵根"]
	for index: int in range(30):
		var choice: int = _rng.randi_range(0, spawn_cells.size() - 1)
		var cell: Vector2i = spawn_cells[choice]
		spawn_cells.remove_at(choice)
		var position: Vector2 = _center(cell)
		var max_health: float = float(_rng.randi_range(80, 110))
		villagers.append({
			"id": index, "name": surnames[index % surnames.size()] + given_names[index % given_names.size()],
			"age": _rng.randi_range(16, 62), "root": roots[_rng.randi_range(0, roots.size() - 1)],
			"talent": _rng.randi_range(1, 100), "health": max_health, "max_health": max_health,
			"realm": "凡人", "origin": "青禾村", "position": position, "previous_position": position,
			"target": position, "state": "闲谈", "destination": "青禾村", "color": index % 6,
			"wander_timer": _rng.randf_range(0.1, 2.8), "_speed": _rng.randf_range(17.0, 24.0),
			"_direction": Vector2i.ZERO, "_steps_left": 0,
			"cultivation": 0.0, "cultivation_max": 100.0, "cultivation_rate": 0.0,
			"intent_reason": "尚未发现灵泉，随处走走", "spring_id": -1,
			"_decision_timer": 0.0, "_path": [], "_meditation_cell": Vector2i(-1, -1)
		})

func step(delta: float) -> void:
	if delta <= 0.0:
		return
	tick_count += 1
	elapsed += delta
	for person: Dictionary in villagers:
		person.previous_position = person.position
		if not springs.is_empty() and _step_cultivation(person, delta):
			continue
		var time_left: float = delta
		while time_left > 0.00001:
			if float(person.wander_timer) > 0.0:
				var pause: float = minf(time_left, person.wander_timer)
				person.wander_timer -= pause
				time_left -= pause
				if time_left <= 0.00001:
					break
			var distance: float = person.position.distance_to(person.target)
			if distance < 0.001:
				if int(person._steps_left) <= 0:
					person._steps_left = _rng.randi_range(3, 10)
					person.wander_timer = _rng.randf_range(0.3, 2.0)
					person.state = "歇脚"
					continue
				_choose_next_tile(person)
				distance = person.position.distance_to(person.target)
				if distance < 0.001:
					person.wander_timer = 1.0
					continue
			var travel_time: float = distance / float(person._speed)
			var used: float = minf(time_left, travel_time)
			person.position = person.position.move_toward(person.target, float(person._speed) * used)
			time_left -= used
			if used >= travel_time:
				person._steps_left -= 1
				time_left = 0.0

func tile_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE:
		return Terrain.WATER
	return terrain[cell.y * SIZE + cell.x]

func is_walkable(cell: Vector2i) -> bool:
	var tile: int = tile_at(cell)
	return tile != Terrain.WATER and tile != Terrain.MOUNTAIN

func snapshot() -> Dictionary:
	return {"seed": seed_value, "tick_count": tick_count, "elapsed": elapsed,
		"terrain": terrain.duplicate(), "villagers": villagers.duplicate(true),
		"landmarks": landmarks.duplicate(true), "springs": springs.duplicate(true), "rng_state": _rng.state}

func _choose_next_tile(person: Dictionary) -> void:
	var current := Vector2i(floori(person.position.x / TILE_SIZE), floori(person.position.y / TILE_SIZE))
	var choices: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		if is_walkable(current + direction):
			choices.append(direction)
			if direction == person._direction:
				choices.append(direction)
	if choices.is_empty():
		return
	var direction: Vector2i = choices[_rng.randi_range(0, choices.size() - 1)]
	person._direction = direction
	person.target = _center(current + direction)
	person.state = "闲逛"
	var nearest_name: String = "山野"
	var nearest_distance: float = 8.0
	for landmark: Dictionary in landmarks:
		var distance: float = current.distance_to(landmark.cell)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_name = landmark.name
	person.destination = nearest_name

func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE_SIZE) + Vector2.ONE * (TILE_SIZE / 2.0)

func _carve_path(start: Vector2i, end: Vector2i) -> void:
	var cell: Vector2i = start
	while cell != end:
		terrain[cell.y * SIZE + cell.x] = Terrain.PATH
		if cell.x != end.x:
			cell.x += 1 if end.x > cell.x else -1
		elif cell.y != end.y:
			cell.y += 1 if end.y > cell.y else -1
	terrain[end.y * SIZE + end.x] = Terrain.PATH

func _remove_disconnected_tiles() -> void:
	var visited: Dictionary = {Vector2i(31, 32): true}
	var queue: Array[Vector2i] = [Vector2i(31, 32)]
	var cursor: int = 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = current + direction
			if is_walkable(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var cell := Vector2i(x, y)
			if is_walkable(cell) and not visited.has(cell):
				terrain[y * SIZE + x] = Terrain.WATER



func place_spring(cell: Vector2i) -> Dictionary:
	if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE:
		return {"ok": false, "reason": "请在地图范围内放置灵泉"}
	if not is_walkable(cell):
		return {"ok": false, "reason": "水域和山地无法放置灵泉"}
	for spring: Dictionary in springs:
		if spring.cell == cell:
			return {"ok": false, "reason": "此处已有灵泉"}
	if springs.size() >= 6:
		return {"ok": false, "reason": "最多可放置六处灵泉"}
	var spring: Dictionary = {"id": springs.size(), "cell": cell,
		"name": "灵泉·%d" % (springs.size() + 1), "radius": 8, "power": 1.0}
	springs.append(spring)
	for person: Dictionary in villagers:
		person._decision_timer = 0.0
	return {"ok": true, "reason": "灵泉涌现，有灵根的村民会寻找可达的修炼位置", "spring": spring}

func aura_at(cell: Vector2i) -> float:
	var strength: float = 0.0
	for spring: Dictionary in springs:
		strength = maxf(strength, _spring_aura(spring, cell))
	return clampf(strength, 0.0, 1.0)

func _spring_aura(spring: Dictionary, cell: Vector2i) -> float:
	var distance: float = cell.distance_to(spring.cell)
	return clampf(float(spring.power) * (1.0 - distance / maxf(1.0, float(spring.radius))), 0.0, 1.0)

func _step_cultivation(person: Dictionary, delta: float) -> bool:
	person.cultivation_rate = 0.0
	if person.root == "无灵根":
		person.spring_id = -1
		person.intent_reason = "无灵根，无法感应灵气，继续日常闲逛"
		return false
	if float(person.cultivation) >= float(person.cultivation_max):
		person.cultivation = person.cultivation_max
		person.spring_id = -1
		person.state = "歇脚"
		person.intent_reason = "修为已满，暂且歇息"
		return true
	person._decision_timer = float(person._decision_timer) - delta
	# Decisions happen at tile centers: finishing the current cardinal segment
	# avoids a diagonal cut when a spring appears while somebody is walking.
	if person.position.distance_to(person.target) < 0.001:
		if float(person._decision_timer) <= 0.0:
			person._decision_timer = 1.0
			_choose_spring(person)
	if int(person.spring_id) < 0:
		return false
	var spring: Dictionary = _spring_by_id(int(person.spring_id))
	if spring.is_empty():
		person.spring_id = -1
		return false
	person.destination = spring.name
	if person.position.distance_to(person.target) >= 0.001:
		person.state = "前往灵泉"
		person.position = person.position.move_toward(person.target, float(person._speed) * delta)
		return true
	var route: Array = person._path
	if not route.is_empty():
		var next: Vector2i = route.pop_front()
		if not is_walkable(next):
			person.spring_id = -1
			person._decision_timer = 0.0
			return false
		person.target = _center(next)
		person.state = "前往灵泉"
		person.position = person.position.move_toward(person.target, float(person._speed) * delta)
		return true
	var cell: Vector2i = _person_cell(person)
	var aura: float = aura_at(cell)
	if cell != person._meditation_cell or aura <= 0.0:
		person.spring_id = -1
		person._decision_timer = 0.0
		person.intent_reason = "灵气不足，重新寻找修炼处"
		return false
	person.state = "打坐修炼"
	person.cultivation_rate = aura * (0.7 + float(person.talent) * 0.013)
	person.cultivation = minf(person.cultivation_max, float(person.cultivation) + float(person.cultivation_rate) * delta)
	person.intent_reason = "在%s感应灵气 %.0f%%，资质 %d，修为 +%.2f/秒" % [spring.name, aura * 100.0, person.talent, person.cultivation_rate]
	if float(person.cultivation) >= float(person.cultivation_max):
		person.cultivation_rate = 0.0
		person.intent_reason = "修为已满，暂且歇息"
	return true

func _spring_by_id(id: int) -> Dictionary:
	for spring: Dictionary in springs:
		if int(spring.id) == id:
			return spring
	return {}

func _person_cell(person: Dictionary) -> Vector2i:
	return Vector2i(floori(person.position.x / TILE_SIZE), floori(person.position.y / TILE_SIZE))

func _choose_spring(person: Dictionary) -> void:
	var start: Vector2i = _person_cell(person)
	var parents: Dictionary = {start: start}
	var distances: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = cell + direction
			if is_walkable(next) and not parents.has(next):
				parents[next] = cell
				distances[next] = int(distances[cell]) + 1
				queue.append(next)
	var claimed: Dictionary = {}
	for other: Dictionary in villagers:
		if int(other.id) != int(person.id) and int(other.spring_id) >= 0:
			claimed[other._meditation_cell] = true
	var best_spring: Dictionary = {}
	var best_cell := Vector2i(-1, -1)
	var best_score: float = -INF
	var current_score: float = -INF
	for spring: Dictionary in springs:
		# Aura across water is visible, but a villager must be able to reach
		# the spring itself before choosing a meditation place around it.
		if not parents.has(spring.cell):
			continue
		if int(spring.id) == int(person.spring_id) and distances.has(person._meditation_cell):
			current_score = _spring_score(spring, person, int(distances[person._meditation_cell]), person._meditation_cell)
		for offset_y: int in range(-3, 4):
			for offset_x: int in range(-3, 4):
				var candidate: Vector2i = spring.cell + Vector2i(offset_x, offset_y)
				if candidate.distance_to(spring.cell) > 3.0 or not distances.has(candidate) or claimed.has(candidate):
					continue
				var score: float = _spring_score(spring, person, int(distances[candidate]), candidate)
				if score > best_score:
					best_score = score
					best_cell = candidate
					best_spring = spring
	if current_score > -INF and (best_spring.is_empty() or best_score <= current_score + 0.25):
		return
	if best_spring.is_empty():
		person.spring_id = -1
		person._path = []
		person.intent_reason = "未找到可达的灵泉修炼处，继续闲逛"
		return
	var route: Array[Vector2i] = []
	var route_cell: Vector2i = best_cell
	while route_cell != start:
		route.push_front(route_cell)
		route_cell = parents[route_cell]
	person.spring_id = best_spring.id
	person._meditation_cell = best_cell
	person._path = route
	person.wander_timer = 0.0
	person.intent_reason = "感应到%s：灵气 %.0f%%，路程 %d 格；前往可达的修炼处" % [best_spring.name, _spring_aura(best_spring, best_cell) * 100.0, distances[best_cell]]

func _spring_score(spring: Dictionary, person: Dictionary, distance: int, cell: Vector2i) -> float:
	return float(spring.power) * (0.7 + float(person.talent) * 0.013) + _spring_aura(spring, cell) * 0.2 - float(distance) * 0.035
