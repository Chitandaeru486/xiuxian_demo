extends Node2D

const TILE := 16
var simulation: RefCounted
var selected_id: int = 0
var hovered_id: int = -1
var show_names: bool = true
var show_grid: bool = false
var show_aura: bool = false
var placement_active: bool = false
var placement_cell: Vector2i = Vector2i(-1, -1)
var placement_valid: bool = false
var aura_cells: Array[Dictionary] = []
var interpolation: float = 1.0
var clock: float = 0.0
var tiles: Texture2D
var decor: Texture2D
var people: Texture2D
var font: Font
var labels: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var ground: TileMapLayer

func setup(world: RefCounted, label_font: Font) -> void:
	simulation = world
	font = label_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tiles = load("res://assets/art/tiles.png")
	decor = load("res://assets/art/decor.png")
	people = load("res://assets/art/villagers.png")
	_make_ground()
	_make_objects()
	refresh_aura()
	queue_redraw()

func refresh_aura() -> void:
	aura_cells.clear()
	if simulation == null:
		return
	for y in range(simulation.SIZE):
		for x in range(simulation.SIZE):
			var cell := Vector2i(x, y)
			if not simulation.is_walkable(cell):
				continue
			var strength: float = simulation.aura_at(cell)
			if strength > 0.0:
				aura_cells.append({"cell": cell, "strength": strength})
	queue_redraw()

func _make_ground() -> void:
	if is_instance_valid(ground):
		ground.queue_free()
	ground = TileMapLayer.new()
	ground.z_index = -10
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tiles
	atlas.texture_region_size = Vector2i(TILE, TILE)
	for i in range(24):
		atlas.create_tile(Vector2i(i, 0))
	tile_set.add_source(atlas, 0)
	ground.tile_set = tile_set
	add_child(ground)
	for y in range(simulation.SIZE):
		for x in range(simulation.SIZE):
			var kind: int = simulation.tile_at(Vector2i(x, y))
			var variant: int = posmod(x * 7 + y * 13 + x * y, 4)
			ground.set_cell(Vector2i(x, y), 0, Vector2i(kind * 4 + variant, 0))

func _make_objects() -> void:
	objects.clear()
	labels.clear()
	var random := RandomNumberGenerator.new()
	random.seed = simulation.seed_value + 130
	for y in range(3, simulation.SIZE - 3):
		for x in range(3, simulation.SIZE - 3):
			var cell := Vector2i(x, y)
			var kind: int = simulation.tile_at(cell)
			var location := Vector2(x * TILE + 8, y * TILE + 13)
			var in_village: bool = Vector2(x - 31, y - 32).length() < 6.0
			if in_village:
				continue
			var frame := -1
			if kind == 3 and random.randf() < 0.25:
				frame = 0 if random.randf() < 0.6 else 1
			elif kind == 2 and random.randf() < 0.025:
				frame = 7
			elif kind == 4 and random.randf() < 0.33:
				frame = 3
			if frame >= 0:
				objects.append({"position": location, "frame": frame})
	# A small inhabited hamlet, rather than a decorative UI on an empty map.
	for cell in [Vector2i(28, 29), Vector2i(34, 29), Vector2i(27, 34), Vector2i(34, 35), Vector2i(30, 37)]:
		if simulation.is_walkable(cell):
			objects.append({"position": Vector2(cell * TILE) + Vector2(8, 12), "frame": 4})
	for landmark in simulation.landmarks:
		var cell: Vector2i = landmark.cell
		var position_at := Vector2(cell * TILE) + Vector2(8, 12)
		var kind: String = landmark.get("kind", "")
		if kind == "shrine":
			objects.append({"position": position_at, "frame": 5})
		elif kind == "grove" or kind == "bamboo":
			for offset in [Vector2(-20, -5), Vector2(16, 5), Vector2(-4, -20)]:
				objects.append({"position": position_at + offset, "frame": 2})
		labels.append({"position": position_at + Vector2(0, -40), "name": landmark.name})
	for cell in [Vector2i(30, 31), Vector2i(33, 33)]:
		objects.append({"position": Vector2(cell * TILE) + Vector2(8, 12), "frame": 6})
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.position.y < b.position.y)

func visual_position(person: Dictionary) -> Vector2:
	return person.previous_position.lerp(person.position, interpolation)

func find_person(world_position: Vector2, radius: float = 12.0) -> int:
	var nearest := -1
	var distance := radius
	for person in simulation.villagers:
		var current: float = visual_position(person).distance_to(world_position + Vector2(0, 5))
		if current < distance:
			distance = current
			nearest = person.id
	return nearest

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	if simulation == null or people == null:
		return
	if show_aura:
		for tile in aura_cells:
			var alpha := 0.035 + clampf(float(tile.strength), 0.0, 1.0) * 0.18
			draw_rect(Rect2(Vector2(tile.cell * TILE), Vector2(TILE, TILE)), Color(0.49, 0.85, 0.53, alpha))
	# Transparent shallow-water glints are sparse, deliberately not a moving noise field.
	for i in range(32):
		var cell := Vector2i(posmod(i * 17 + 9, 64), posmod(i * 23 + 3, 64))
		if simulation.tile_at(cell) == 0:
			var alpha := (sin(clock * 1.1 + i * 2.0) + 1.0) * 0.12
			draw_rect(Rect2(Vector2(cell * TILE) + Vector2(3, 9), Vector2(6, 1)), Color(0.64, 0.88, 0.78, alpha))
	if show_grid:
		for i in range(65):
			draw_line(Vector2(i * TILE, 0), Vector2(i * TILE, 1024), Color(0.88, 0.94, 0.81, 0.13))
			draw_line(Vector2(0, i * TILE), Vector2(1024, i * TILE), Color(0.88, 0.94, 0.81, 0.13))
	var drawables: Array[Dictionary] = []
	for item in objects:
		drawables.append({"y": item.position.y, "object": item})
	for person in simulation.villagers:
		drawables.append({"y": visual_position(person).y, "person": person})
	for spring in simulation.springs:
		drawables.append({"y": spring.cell.y * TILE + 12, "spring": spring})
	drawables.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
	for entry in drawables:
		if entry.has("object"):
			var item: Dictionary = entry.object
			draw_texture_rect_region(decor, Rect2(item.position - Vector2(16, 44), Vector2(32, 48)), Rect2(item.frame * 32, 0, 32, 48))
		elif entry.has("spring"):
			_draw_spring(entry.spring)
		else:
			_draw_person(entry.person)
	if show_names:
		for item in labels:
			_draw_label(item.position, item.name, Color("e4d5af"), 10)
		for spring in simulation.springs:
			_draw_label(Vector2(spring.cell * TILE) + Vector2(8, -18), spring.name, Color("c1e4b4"), 9)
	if placement_active and placement_cell.x >= 0:
		_draw_placement()

func _draw_person(person: Dictionary) -> void:
	var p := visual_position(person).round()
	var moving: bool = person.position.distance_to(person.previous_position) > 0.01
	var frame: int = 1 + (int(simulation.elapsed * 6.0 + person.id) % 2) if moving else 0
	if person.get("state", "") == "打坐修炼":
		frame = 3
	if person.id == selected_id:
		_selection_ellipse(p + Vector2(0, 1), Vector2(9, 4), Color(0.88, 0.78, 0.44, 0.25))
		draw_polyline(PackedVector2Array([p + Vector2(-9, -2), p + Vector2(-9, 3), p + Vector2(-4, 5)]), Color("ebce83"), 1.0)
		draw_polyline(PackedVector2Array([p + Vector2(9, -2), p + Vector2(9, 3), p + Vector2(4, 5)]), Color("ebce83"), 1.0)
	var dest := Rect2(p - Vector2(8, 21), Vector2(16, 24))
	draw_texture_rect_region(people, dest, Rect2(frame * 16, person.color * 24, 16, 24))
	if float(person.get("cultivation_rate", 0.0)) > 0.0:
		for i in range(3):
			var phase := fposmod(clock * 0.32 + float(i) / 3.0 + float(person.id) * 0.17, 1.0)
			var sparkle := p + Vector2(round(sin(phase * TAU + i) * 7.0), round(-5.0 - phase * 17.0))
			draw_rect(Rect2(sparkle, Vector2(1, 1)), Color(0.69, 0.9, 0.63, sin(phase * PI) * 0.65))
	if person.id == selected_id:
		var arrow_y: float = p.y - 27 + floor(sin(clock * 3.0))
		draw_colored_polygon(PackedVector2Array([Vector2(p.x - 3, arrow_y), Vector2(p.x + 3, arrow_y), Vector2(p.x, arrow_y + 3)]), Color("ebce83"))
		_draw_label(p + Vector2(0, -33), person.name, Color("f0dfa9"), 9)
	elif person.id == hovered_id:
		_draw_label(p + Vector2(0, -27), person.name, Color("e6eddc"), 9)

func _draw_spring(spring: Dictionary) -> void:
	var p := Vector2(spring.cell * TILE) + Vector2(8, 10)
	# Stepped stone rim and still jade water share the map's muted palette.
	draw_rect(Rect2(p + Vector2(-9, -3), Vector2(18, 9)), Color("344b42"))
	draw_rect(Rect2(p + Vector2(-11, -1), Vector2(22, 5)), Color("344b42"))
	draw_rect(Rect2(p + Vector2(-9, -4), Vector2(18, 7)), Color("8a9676"))
	draw_rect(Rect2(p + Vector2(-11, -2), Vector2(22, 3)), Color("8a9676"))
	draw_rect(Rect2(p + Vector2(-7, -3), Vector2(14, 6)), Color("476e61"))
	draw_rect(Rect2(p + Vector2(-9, -1), Vector2(18, 3)), Color("476e61"))
	draw_rect(Rect2(p + Vector2(-6, 0), Vector2(12, 2)), Color("679e83"))
	draw_rect(Rect2(p + Vector2(-8, -4), Vector2(4, 1)), Color("c1bb91"))
	draw_rect(Rect2(p + Vector2(5, 2), Vector2(4, 1)), Color("c1bb91"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-3, -6), p + Vector2(0, -16), p + Vector2(4, -8), p + Vector2(2, -1), p + Vector2(-2, -1)]), Color("75b895"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -16), p + Vector2(1, -6), p + Vector2(-2, -1), p + Vector2(-3, -6)]), Color("b8d8ac"))
	draw_line(p + Vector2(1, -11), p + Vector2(2, -6), Color("e1e6bc"), 1.0)
	draw_rect(Rect2(p + Vector2(-5, 1), Vector2(3, 1)), Color(0.75, 0.87, 0.69, 0.55 + sin(clock * 1.5) * 0.12))

func _draw_placement() -> void:
	var tint := Color("b9d393") if placement_valid else Color("d88b78")
	var center := Vector2(placement_cell * TILE) + Vector2(8, 8)
	# Tile steps keep the coverage boundary legible without smoothing the pixel map.
	for y in range(-8, 9):
		for x in range(-8, 9):
			var offset := Vector2i(x, y)
			if offset.length() > 8.0:
				continue
			var cell := placement_cell + offset
			if cell.x < 0 or cell.y < 0 or cell.x >= simulation.SIZE or cell.y >= simulation.SIZE:
				continue
			var origin := center + Vector2(offset * TILE) - Vector2(8, 8)
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if (offset + direction).length() <= 8.0:
					continue
				var edge := Rect2(origin, Vector2(TILE, 1))
				if direction == Vector2i.DOWN:
					edge.position.y += TILE - 1
				elif direction == Vector2i.LEFT:
					edge.size = Vector2(1, TILE)
				elif direction == Vector2i.RIGHT:
					edge.position.x += TILE - 1
					edge.size = Vector2(1, TILE)
				draw_rect(edge, Color(tint, 0.5))
	draw_rect(Rect2(center - Vector2(8, 8), Vector2(TILE, TILE)), Color(tint, 0.15))
	draw_rect(Rect2(center - Vector2(8, 8), Vector2(TILE, TILE)), tint, false, 1.0)

func _selection_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(20):
		var angle: float = float(i) * TAU / 20.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)

func _draw_label(at: Vector2, text: String, color: Color, size: int) -> void:
	var length: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var start := at - Vector2(length / 2.0, 0)
	draw_string_outline(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color("21342c"))
	draw_string(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
