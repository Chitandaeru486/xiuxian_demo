extends SceneTree

const World = preload("res://scripts/world_sim.gd")
var failures: int = 0

func _init() -> void:
	var world = World.new()
	world.generate()
	check(world.springs.is_empty(), "starts without springs")
	check(not world.place_spring(Vector2i(-1, 1)).ok, "reject out of bounds")
	check(not world.place_spring(Vector2i(0, 0)).ok, "reject water")
	world.terrain[64 + 1] = World.Terrain.MOUNTAIN
	check(not world.place_spring(Vector2i(1, 1)).ok, "reject mountain")
	for person: Dictionary in world.villagers:
		check(person.cultivation == 0.0, "starts uncultivated")
	for index: int in range(100):
		world.step(0.1)
	for person: Dictionary in world.villagers:
		check(person.cultivation == 0.0, "no passive cultivation")
	var placement: Dictionary = world.place_spring(Vector2i(31, 32))
	check(placement.ok, "place spring")
	check(not world.place_spring(Vector2i(31, 32)).ok, "reject duplicate")
	check(world.aura_at(Vector2i(31, 32)) == 1.0, "aura at source")
	check(world.aura_at(Vector2i(0, 0)) == 0.0, "no remote aura")
	var paused: Dictionary = world.snapshot()
	world.step(0.0)
	world.step(-2.0)
	check(paused == world.snapshot(), "pause preserves complete state")
	var headed: bool = false
	var meditated: bool = false
	var grew: bool = false
	var early_response: bool = false
	for index: int in range(600):
		world.step(0.1)
		var claimed: Dictionary = {}
		for person: Dictionary in world.villagers:
			headed = headed or person.state == "前往灵泉"
			if index < 20 and person.spring_id >= 0:
				early_response = true
			if person.spring_id >= 0:
				check(not claimed.has(person._meditation_cell), "distinct meditation destinations")
				claimed[person._meditation_cell] = true
			meditated = meditated or person.state == "打坐修炼"
			grew = grew or person.cultivation > 0.0
			check(world.is_walkable(to_cell(person.position)), "walkable cultivation movement")
			var movement: Vector2 = person.position - person.previous_position
			check(absf(movement.x) < 0.001 or absf(movement.y) < 0.001, "cardinal cultivation movement")
			check(movement.length() <= 2.401, "cultivation speed bounded")
			if person.root == "无灵根":
				check(person.spring_id == -1 and person.cultivation == 0.0, "no root never cultivates")
			if person.state == "前往灵泉":
				check(person.cultivation_rate == 0.0, "no growth in transit")
	check(headed and meditated and grew, "spring causes travel, meditation and growth")
	check(early_response, "nearby villagers respond within two seconds")
	for index: int in range(5):
		check(world.place_spring(Vector2i(27 + index, 30)).ok, "six spring allowance")
	check(not world.place_spring(Vector2i(34, 30)).ok, "spring cap")
	test_controlled()
	test_determinism()
	world.generate()
	check(world.springs.is_empty(), "regenerate removes springs")
	check(world.villagers[0].cultivation == 0.0, "regenerate resets cultivation")
	if failures == 0:
		print("PASS: placement, aura, travel, cultivation, roots, talent, cap, retarget, reachability, determinism and pause")
	else:
		printerr("FAIL: %d cultivation checks" % failures)
	quit(0 if failures == 0 else 1)

func test_controlled() -> void:
	var world = World.new()
	world.generate()
	world.terrain.fill(World.Terrain.GRASS)
	world.villagers.resize(2)
	for index: int in range(2):
		var person: Dictionary = world.villagers[index]
		person.root = "木"
		person.talent = 1 if index == 0 else 100
		person.position = Vector2(20 * 16 + 8, (20 + index) * 16 + 8)
		person.previous_position = person.position
		person.target = person.position
		person.wander_timer = 0.0
	world.place_spring(Vector2i(20, 20))
	for index: int in range(100):
		world.step(0.1)
	check(world.villagers[0].state == "打坐修炼" and world.villagers[1].state == "打坐修炼", "controlled villagers meditate")
	# Equal aura isolates talent from the destination each villager selected.
	world.springs[0].radius = 10000
	var low_before: float = world.villagers[0].cultivation
	var high_before: float = world.villagers[1].cultivation
	world.step(1.0)
	check(world.villagers[1].cultivation - high_before > (world.villagers[0].cultivation - low_before) * 1.5, "talent increases rate under equal aura")
	world.villagers[0].cultivation = 99.99
	world.step(1.0)
	check(world.villagers[0].cultivation == 100.0 and world.villagers[0].cultivation_rate == 0.0, "cultivation capped with zero rate")
	var stronger: Dictionary = world.place_spring(Vector2i(24, 20))
	stronger.spring.power = 3.0
	for index: int in range(20):
		world.step(0.1)
	check(world.villagers[1].spring_id == stronger.spring.id, "better spring triggers retarget")
	var isolated = World.new()
	isolated.generate()
	isolated.terrain.fill(World.Terrain.WATER)
	isolated.terrain[10 * 64 + 10] = World.Terrain.GRASS
	isolated.terrain[10 * 64 + 12] = World.Terrain.GRASS
	isolated.villagers.resize(1)
	var person: Dictionary = isolated.villagers[0]
	person.root = "木"
	person.position = Vector2(168, 168)
	person.target = person.position
	isolated.place_spring(Vector2i(12, 10))
	for index: int in range(100):
		isolated.step(0.1)
	check(person.spring_id == -1 and person.cultivation == 0.0, "unreachable spring gives no cultivation")

func test_determinism() -> void:
	var first = World.new()
	var second = World.new()
	first.generate(71)
	second.generate(71)
	for world in [first, second]:
		world.place_spring(Vector2i(31, 32))
	for index: int in range(180):
		first.step(0.1)
		second.step(0.1)
	check(first.snapshot() == second.snapshot(), "same seed and actions deterministic")
	var detached: Dictionary = first.snapshot()
	detached.springs[0].name = "changed"
	check(first.springs[0].name != "changed", "spring snapshot detached")

func to_cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / 16.0), floori(position.y / 16.0))

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		if failures <= 12:
			printerr("FAILED: " + message)

