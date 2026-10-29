extends SceneTree

const World = preload("res://scripts/world_sim.gd")
var failures: int = 0

func _init() -> void:
	var first = World.new()
	var repeat = World.new()
	first.generate(20261027)
	repeat.generate(20261027)
	check(first.terrain.size() == 4096, "64 by 64 map")
	check(first.villagers.size() == 30, "30 villagers")
	check(first.snapshot() == repeat.snapshot(), "same seed produces the same state")
	var ids: Dictionary = {}
	var cells: Dictionary = {}
	var starts: Dictionary = {}
	for person: Dictionary in first.villagers:
		check(not ids.has(person.id), "unique character ids")
		ids[person.id] = true
		var cell: Vector2i = to_cell(person.position)
		check(not cells.has(cell), "separate spawn cells")
		cells[cell] = true
		starts[person.id] = person.position
		check(first.is_walkable(cell), "walkable spawn")
		check(person.talent >= 1 and person.talent <= 100, "talent bounds")
		check(person.health > 0.0 and person.health <= person.max_health, "health bounds")
	check(not first.is_walkable(Vector2i(-1, 0)), "negative boundary blocked")
	check(not first.is_walkable(Vector2i(64, 0)), "outer boundary blocked")
	for landmark: Dictionary in first.landmarks:
		check(first.is_walkable(landmark.cell), "landmarks are walkable")
	check_connected(first)
	var initial: Dictionary = first.snapshot()
	first.step(0.0)
	check(first.snapshot() == initial, "zero delta preserves full state")
	first.step(-1.0)
	check(first.snapshot() == initial, "negative delta preserves full state")
	for tick: int in range(300):
		first.step(0.1)
		repeat.step(0.1)
		for person: Dictionary in first.villagers:
			check(first.is_walkable(to_cell(person.position)), "walkable movement")
			check(first.is_walkable(to_cell(person.target)), "walkable targets")
			var displacement: Vector2 = person.position - person.previous_position
			check(absf(displacement.x) < 0.001 or absf(displacement.y) < 0.001, "cardinal movement without corner cutting")
			check(displacement.length() <= 2.401, "bounded continuous movement")
	check(first.snapshot() == repeat.snapshot(), "deterministic updates")
	check(first.tick_count == 300 and is_equal_approx(first.elapsed, 30.0), "tick and time advance")
	var moved: int = 0
	for person: Dictionary in first.villagers:
		if person.position.distance_to(starts[person.id]) > 1.0:
			moved += 1
	check(moved >= 25, "at least 25 villagers move over 30 seconds")
	var detached: Dictionary = first.snapshot()
	detached.villagers[0].name = "changed"
	check(first.villagers[0].name != "changed", "snapshot is independent of live state")
	first.generate(20261027)
	check(first.snapshot() == initial, "regeneration resets world")
	repeat.generate(20261028)
	check(first.terrain != repeat.terrain, "different seeds create varied terrain")
	if failures == 0:
		print("PASS: simulation invariants, 30 villagers, map connectivity, deterministic 300 ticks, pause and snapshots")
	else:
		printerr("FAIL: %d checks" % failures)
	quit(0 if failures == 0 else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		if failures <= 12:
			printerr("FAILED: " + message)

func to_cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / 16.0), floori(position.y / 16.0))

func check_connected(world: RefCounted) -> void:
	var queue: Array[Vector2i] = [Vector2i(31, 32)]
	var seen: Dictionary = {Vector2i(31, 32): true}
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if world.is_walkable(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	var total: int = 0
	for y: int in range(64):
		for x: int in range(64):
			if world.is_walkable(Vector2i(x, y)):
				total += 1
	check(seen.size() == total, "all walkable terrain is connected")
