extends Node2D

const World = preload("res://scripts/world_sim.gd")
const WorldView = preload("res://scripts/world_view.gd")
const INK := Color("e4e7d6")
const MUTED := Color("8eaaa0")
const GOLD := Color("d6b675")
const PANEL := Color("182c2c")
const EDGE := Color("344943")
const STEP := 0.1

var simulation: RefCounted
var world_view: Node2D
var camera: Camera2D
var font: SystemFont
var title_font: SystemFont
var hud: Control
var header: Panel
var sidebar: Panel
var toolbar: Panel
var location_card: Control
var toast_panel: Panel
var toast_label: Label
var help_overlay: Panel
var time_label: Label
var count_label: Label
var zoom_label: Label
var name_label: Label
var subtitle_label: Label
var state_label: Label
var root_label: Label
var age_label: Label
var origin_label: Label
var talent_label: Label
var health_label: Label
var health_bar: ProgressBar
var position_label: Label
var follow_button: Button
var pause_button: Button
var labels_button: Button
var minimap: TextureRect
var nearby_buttons: Array[Button] = []
var speed_buttons: Array[Button] = []
var selected_id: int = 0
var follow: bool = false
var paused: bool = false
var speed: int = 1
var accumulator: float = 0.0
var refresh_timer: float = 0.0
var minimap_timer: float = 0.0
var toast_time: float = 0.0
var drag_active: bool = false
var drag_distance: float = 0.0
var drag_button: int = 0
var press_position: Vector2
var camera_zoom: float = 1.65
var capture_frames: int = 0
var auto_capture: bool = false
var capture_path: String = "res://evidence/first-playable.png"
var smoke_test: bool = false
var smoke_failures: int = 0
var smoke_finished: bool = false
var capture_in_progress: bool = false
var placement_mode: bool = false
var spring_toolbar: Panel
var spring_button: Button
var aura_button: Button
var spring_status: Label
var cultivation_label: Label
var cultivation_bar: ProgressBar
var rate_label: Label
var reason_label: Label
var pointer_screen := Vector2(-100, -100)
var cultivation_smoke: bool = false

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["SimSun", "Noto Serif CJK SC", "Microsoft YaHei"])
	simulation = World.new()
	simulation.generate()
	world_view = WorldView.new()
	add_child(world_view)
	world_view.setup(simulation, font)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * camera_zoom
	add_child(camera)
	_build_hud()
	_layout_hud()
	_focus_village()
	_update_panel()
	get_viewport().size_changed.connect(_layout_hud)
	for argument in OS.get_cmdline_user_args():
		if argument == "--capture":
			auto_capture = true
		if argument == "--smoke-test":
			smoke_test = true
		if argument == "--cultivation-test":
			smoke_test = true
			cultivation_smoke = true
		if argument.begins_with("--capture-path="):
			capture_path = argument.trim_prefix("--capture-path=")
	if cultivation_smoke:
		_run_cultivation_smoke.call_deferred()
	elif smoke_test:
		_run_interaction_smoke.call_deferred()
	_show_toast("点击「布灵泉」，在草地上点化一处修炼之地。", 6.0)

func _process(delta: float) -> void:
	if not paused:
		accumulator += minf(delta, 0.25) * speed
		var updates := 0
		while accumulator >= STEP and updates < 12:
			simulation.step(STEP)
			accumulator -= STEP
			updates += 1
		world_view.interpolation = clampf(accumulator / STEP, 0.0, 1.0)
	else:
		world_view.interpolation = 1.0
	if follow:
		var person := _selected()
		if not person.is_empty():
			camera.position = world_view.visual_position(person) + _camera_bias()
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction != Vector2.ZERO:
		follow = false
		camera.position += direction * delta * 350.0 / camera_zoom
		_clamp_camera()
	refresh_timer += delta
	if refresh_timer >= 0.2:
		refresh_timer = 0.0
		_update_panel()
	minimap_timer += delta
	if minimap_timer >= 1.0:
		minimap_timer = 0.0
		_make_minimap()
	if toast_time > 0.0:
		toast_time -= delta
		toast_panel.visible = toast_time > 0.0
	_update_placement_preview()
	if auto_capture:
		capture_frames += 1
		if capture_frames >= 90 and (not smoke_test or smoke_finished) and not capture_in_progress:
			capture_in_progress = true
			_capture_and_exit.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pointer_screen = event.position
		if not _in_world(event.position):
			world_view.hovered_id = -1
	# Finish a drag even if the cursor is released over an overlay panel.
	if event is InputEventMouseButton and not event.pressed and drag_active and event.button_index == drag_button:
		drag_active = false
		if drag_distance < 5.0 and drag_button == MOUSE_BUTTON_LEFT and _in_world(event.position):
			var point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
			if placement_mode:
				_place_spring_at(Vector2i(floori(point.x / 16), floori(point.y / 16)))
			else:
				_select_at(point)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and drag_active:
		drag_distance += event.relative.length()
		if drag_distance >= 5.0:
			follow = false
			camera.position -= event.relative / camera_zoom
			_clamp_camera()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and _in_world(event.position):
		if placement_mode and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_set_placement(false)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(1, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-1, event.position)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			drag_active = true
			drag_distance = 0.0
			drag_button = event.button_index
			press_position = event.position
	elif event is InputEventMouseMotion:
		world_view.hovered_id = world_view.find_person(get_viewport().get_canvas_transform().affine_inverse() * event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _toggle_pause()
			KEY_F: _toggle_follow()
			KEY_HOME: _focus_village()
			KEY_ESCAPE:
				help_overlay.hide()
				follow = false
				_set_placement(false)
			KEY_Q: _set_placement(not placement_mode)
			KEY_H: _toggle_aura()
			KEY_1: _set_speed(1)
			KEY_2: _set_speed(2)
			KEY_4: _set_speed(4)
			KEY_F12: _save_screenshot()

func _in_world(at: Vector2) -> bool:
	var size := get_viewport_rect().size
	return at.x < sidebar.position.x - 12.0 and at.y > 74.0 and at.y < size.y - 104.0

func _selected() -> Dictionary:
	for person in simulation.villagers:
		if person.id == selected_id:
			return person
	return {}

func _select_at(at: Vector2) -> void:
	var person_id: int = world_view.find_person(at, 14.0 / minf(camera_zoom, 1.0))
	if person_id >= 0:
		_select(person_id)

func _select(person_id: int) -> void:
	selected_id = person_id
	world_view.selected_id = person_id
	_update_panel()

func _camera_bias() -> Vector2:
	return Vector2((get_viewport_rect().size.x - sidebar.position.x + 12.0) / 2.0, 0.0) / camera_zoom

func _focus_village() -> void:
	follow = false
	camera_zoom = 1.65
	camera.zoom = Vector2.ONE * camera_zoom
	camera.position = Vector2(31.5 * 16.0, 31.0 * 16.0) + _camera_bias()
	_clamp_camera()

func _clamp_camera() -> void:
	camera.position.x = clampf(camera.position.x, 80.0, 1030.0)
	camera.position.y = clampf(camera.position.y, 80.0, 944.0)

func _change_zoom(direction: int, cursor: Vector2) -> void:
	var before: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * cursor
	camera_zoom = clampf(camera_zoom * (1.2 if direction > 0 else 1.0 / 1.2), 0.65, 4.0)
	camera.zoom = Vector2.ONE * camera_zoom
	camera.force_update_scroll()
	if not follow:
		var after: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * cursor
		camera.position += before - after
	_clamp_camera()
	_update_panel()

func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "▶  继续" if paused else "Ⅱ  暂停"
	_update_panel()

func _set_speed(value: int) -> void:
	speed = value
	for i in range(speed_buttons.size()):
		speed_buttons[i].button_pressed = [1, 2, 4][i] == speed
	_update_panel()

func _toggle_follow() -> void:
	follow = not follow
	if follow:
		camera.position = world_view.visual_position(_selected()) + _camera_bias()
	_update_panel()

func _show_toast(message: String, seconds: float = 3.0) -> void:
	toast_label.text = message
	toast_time = seconds
	toast_panel.show()

func _set_placement(enabled: bool) -> void:
	placement_mode = enabled
	drag_active = false
	spring_button.set_pressed_no_signal(enabled)
	spring_button.text = "✦  正在布泉" if enabled else "✦  布灵泉  Q"
	_update_panel()

func _toggle_aura() -> void:
	world_view.show_aura = not world_view.show_aura
	aura_button.set_pressed_no_signal(world_view.show_aura)
	world_view.refresh_aura()

func _update_placement_preview() -> void:
	world_view.placement_active = placement_mode
	world_view.placement_cell = Vector2i(-1, -1)
	if not placement_mode or not _in_world(pointer_screen) or help_overlay.visible:
		return
	var point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * pointer_screen
	var cell := Vector2i(floori(point.x / 16), floori(point.y / 16))
	world_view.placement_cell = cell
	var valid: bool = simulation.is_walkable(cell) and simulation.springs.size() < 6
	for spring in simulation.springs:
		if spring.cell == cell:
			valid = false
	world_view.placement_valid = valid

func _place_spring_at(cell: Vector2i) -> void:
	var result: Dictionary = simulation.place_spring(cell)
	_show_toast(result.reason, 4.0)
	if result.ok:
		world_view.refresh_aura()
		_make_minimap()
	_update_panel()

func _run_cultivation_smoke() -> void:
	var runner = load("res://tests/test_cultivation_ui.gd").new()
	await runner.run(self)
	smoke_finished = true
	if not auto_capture:
		get_tree().quit(0 if smoke_failures == 0 else 1)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	hud.theme = theme
	layer.add_child(hud)
	header = _panel(hud, Vector2.ZERO, Vector2(1440, 72), Color("142727"), 0)
	var brand := _label(header, "山 海 灵 境", Vector2(26, 13), 27, Color("ecdfbc"))
	brand.add_theme_font_override("font", title_font)
	_label(header, "SHANHAI  /  A LIVING WORLD", Vector2(29, 48), 9, MUTED)
	_label(header, "观世", Vector2(278, 24), 18, GOLD)
	_label(header, "山川流转 · 众生自在", Vector2(338, 29), 12, MUTED)
	count_label = _label(header, "●  生灵 30", Vector2(600, 28), 13, INK)
	time_label = _label(header, "初元 · 一日", Vector2(748, 28), 13, INK)
	var help_button := _button(header, "操作指南  ?", Vector2.ZERO, Vector2(112, 34))
	help_button.name = "HelpButton"
	help_button.pressed.connect(func() -> void: help_overlay.visible = not help_overlay.visible)
	location_card = Control.new()
	location_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(location_card)
	var realm := _label(location_card, "青 岚 山 境", Vector2(0, 0), 26, Color("f1e7c9"))
	realm.add_theme_font_override("font", title_font)
	realm.add_theme_color_override("font_shadow_color", Color("213b31"))
	realm.add_theme_constant_override("shadow_offset_x", 2)
	realm.add_theme_constant_override("shadow_offset_y", 2)
	_label(location_card, "一隅山河，三十段未完的人生。", Vector2(1, 38), 12, Color("dae4cd"))
	_label(location_card, "第二轮 · 点化灵泉，自主修行", Vector2(1, 61), 10, Color("b6ccb7"))
	spring_toolbar = _panel(hud, Vector2(30, 190), Vector2(324, 76), Color(0.08, 0.16, 0.16, 0.95), 6)
	spring_button = _button(spring_toolbar, "✦  布灵泉  Q", Vector2(12, 10), Vector2(139, 32), true)
	spring_button.toggle_mode = true
	spring_button.pressed.connect(func() -> void: _set_placement(not placement_mode))
	aura_button = _button(spring_toolbar, "灵气视图  H", Vector2(161, 10), Vector2(150, 32))
	aura_button.toggle_mode = true
	aura_button.pressed.connect(_toggle_aura)
	spring_status = _label(spring_toolbar, "布下第一处灵泉，观察行者的选择", Vector2(13, 51), 10, MUTED)
	sidebar = _panel(hud, Vector2.ZERO, Vector2(306, 790), PANEL, 8)
	_label(sidebar, "众 生 录", Vector2(22, 19), 19, Color("ebdfbd"))
	_label(sidebar, "所见皆有来处", Vector2(166, 24), 11, MUTED)
	_rule(sidebar, 22, 56, 262)
	var portrait_card := _panel(sidebar, Vector2(22, 76), Vector2(78, 86), Color("243d38"), 5)
	var portrait := TextureRect.new()
	portrait.texture = load("res://assets/art/portrait.png")
	portrait.position = Vector2(3, 3)
	portrait.size = Vector2(72, 80)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_card.add_child(portrait)
	portrait.set_deferred("size", Vector2(72, 80))
	name_label = _label(sidebar, "沈青禾", Vector2(116, 82), 25, Color("f0e6c8"))
	subtitle_label = _label(sidebar, "凡人 · 山野行者", Vector2(117, 123), 12, MUTED)
	_label(sidebar, "生命", Vector2(22, 184), 11, MUTED)
	health_label = _label(sidebar, "100 / 100", Vector2(214, 182), 11, INK)
	health_bar = ProgressBar.new()
	health_bar.position = Vector2(22, 208)
	health_bar.size = Vector2(262, 5)
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.add_theme_stylebox_override("background", _style(Color("30443b"), 0, false))
	health_bar.add_theme_stylebox_override("fill", _style(Color("a7bd83"), 0, false))
	health_bar.add_theme_font_size_override("font_size", 1)
	sidebar.add_child(health_bar)
	health_bar.set_deferred("size", Vector2(262, 5))
	_label(sidebar, "年龄", Vector2(22, 237), 11, MUTED)
	age_label = _label(sidebar, "19 岁", Vector2(22, 260), 17, INK)
	_label(sidebar, "灵根", Vector2(162, 237), 11, MUTED)
	root_label = _label(sidebar, "木灵根", Vector2(162, 260), 17, INK)
	_label(sidebar, "资质", Vector2(22, 300), 11, MUTED)
	talent_label = _label(sidebar, "上佳 · 78", Vector2(22, 323), 15, INK)
	_label(sidebar, "出身", Vector2(162, 300), 11, MUTED)
	origin_label = _label(sidebar, "青溪村", Vector2(162, 323), 15, INK)
	_rule(sidebar, 22, 363, 262)
	_label(sidebar, "修 为", Vector2(22, 382), 11, GOLD)
	cultivation_label = _label(sidebar, "0.0 / 100", Vector2(191, 382), 11, INK)
	cultivation_bar = ProgressBar.new()
	cultivation_bar.step = 0.0
	cultivation_bar.position = Vector2(22, 406)
	cultivation_bar.show_percentage = false
	cultivation_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cultivation_bar.add_theme_font_size_override("font_size", 1)
	cultivation_bar.add_theme_stylebox_override("background", _style(Color("30443b"), 0, false))
	cultivation_bar.add_theme_stylebox_override("fill", _style(Color("76c3a3"), 0, false))
	sidebar.add_child(cultivation_bar)
	cultivation_bar.set_deferred("size", Vector2(262, 5))
	state_label = _label(sidebar, "正在山间漫步", Vector2(22, 423), 15, INK)
	rate_label = _label(sidebar, "尚未开始修炼", Vector2(22, 450), 11, Color("a9ceae"))
	reason_label = _label(sidebar, "", Vector2(22, 474), 11, MUTED)
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.size = Vector2(262, 36)
	reason_label.max_lines_visible = 3
	position_label = _label(sidebar, "青禾村附近 · 32, 32", Vector2(22, 518), 10, MUTED)
	follow_button = _button(sidebar, "◎  跟随此人", Vector2(22, 543), Vector2(262, 34), true)
	follow_button.toggle_mode = true
	follow_button.pressed.connect(_toggle_follow)
	_label(sidebar, "同 行 之 人", Vector2(22, 593), 11, GOLD)
	for i in range(3):
		var row := _button(sidebar, "", Vector2(22, 617 + i * 29), Vector2(262, 26))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 12)
		nearby_buttons.append(row)
	_rule(sidebar, 22, 714, 262)
	_label(sidebar, "山 河 一 览", Vector2(22, 735), 10, MUTED)
	minimap = TextureRect.new()
	minimap.position = Vector2(207, 727)
	minimap.size = Vector2(70, 50)
	minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap.stretch_mode = TextureRect.STRETCH_SCALE
	minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sidebar.add_child(minimap)
	minimap.gui_input.connect(_minimap_input)
	_label(sidebar, "点击定位 · 64 × 64 山境", Vector2(22, 757), 9, MUTED)
	_make_minimap()
	toolbar = _panel(hud, Vector2.ZERO, Vector2(1060, 76), Color("162b2b"), 8)
	pause_button = _button(toolbar, "Ⅱ  暂停", Vector2(15, 17), Vector2(92, 40))
	pause_button.pressed.connect(_toggle_pause)
	for i in range(3):
		var value: int = [1, 2, 4][i]
		var button := _button(toolbar, "%d×" % value, Vector2(118 + i * 46, 17), Vector2(40, 40))
		button.toggle_mode = true
		button.button_pressed = value == 1
		button.pressed.connect(_set_speed.bind(value))
		speed_buttons.append(button)
	_rule(toolbar, 270, 19, 1, 36)
	var home := _button(toolbar, "⌂  村落", Vector2(285, 17), Vector2(95, 40))
	home.pressed.connect(_focus_village)
	labels_button = _button(toolbar, "地名  开", Vector2(390, 17), Vector2(90, 40))
	labels_button.pressed.connect(func() -> void:
		world_view.show_names = not world_view.show_names
		labels_button.text = "地名  开" if world_view.show_names else "地名  关")
	var grid := _button(toolbar, "网格", Vector2(490, 17), Vector2(70, 40))
	grid.toggle_mode = true
	grid.toggled.connect(func(value: bool) -> void: world_view.show_grid = value)
	zoom_label = _label(toolbar, "165%", Vector2(591, 28), 12, MUTED)
	var minus := _button(toolbar, "−", Vector2(647, 17), Vector2(37, 40))
	minus.pressed.connect(func() -> void: _change_zoom(-1, get_viewport_rect().size / 2.0))
	var plus := _button(toolbar, "+", Vector2(690, 17), Vector2(37, 40))
	plus.pressed.connect(func() -> void: _change_zoom(1, get_viewport_rect().size / 2.0))
	_label(toolbar, "拖动观世  ·  滚轮缩放", Vector2(752, 21), 11, MUTED)
	_label(toolbar, "点选人物  /  F 跟随", Vector2(752, 41), 10, Color("698a7d"))
	toast_panel = _panel(hud, Vector2.ZERO, Vector2(460, 40), Color(0.075, 0.15, 0.15, 0.94), 5)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = _label(toast_panel, "", Vector2(16, 10), 12, Color("d9ddbd"))
	help_overlay = _panel(hud, Vector2.ZERO, Vector2(410, 332), Color("192e2d"), 8)
	_label(help_overlay, "观世之法", Vector2(28, 24), 24, GOLD)
	_label(help_overlay, "左键点选          查看一位行者\n按住拖动          移动视野（左右中键均可）\n滚轮 / ＋ −       缩放地图\n空格                   暂停 / 继续\n1 / 2 / 4              时间流速\nF                         跟随选中的人物\nHome                  回到青溪村\nF12                      保存游戏截图", Vector2(28, 77), 14, INK)
	var close := _button(help_overlay, "开始观世", Vector2(28, 270), Vector2(354, 38), true)
	close.pressed.connect(func() -> void: help_overlay.hide())
	help_overlay.hide()
	_label(help_overlay, "Q 布灵泉 · H 灵气视图 · 右键取消放置", Vector2(28, 244), 11, GOLD)

func _layout_hud() -> void:
	if hud == null:
		return
	var size := get_viewport_rect().size
	hud.size = size
	header.size = Vector2(size.x, 72)
	header.get_node("HelpButton").position = Vector2(size.x - 148, 19)
	sidebar.position = Vector2(size.x - 330, 88)
	sidebar.size = Vector2(306, 788)
	# Keep all profile content accessible on smaller windows.
	sidebar.scale = Vector2.ONE * minf(1.0, (size.y - 112.0) / 788.0)
	sidebar.position.x = size.x - sidebar.size.x * sidebar.scale.x - 24.0
	toolbar.position = Vector2(24, size.y - 100)
	toolbar.size = Vector2(size.x - 378, 76)
	if toolbar.size.x < 960:
		toolbar.scale = Vector2.ONE * (toolbar.size.x / 960.0)
		toolbar.size.x = 960.0
	else:
		toolbar.scale = Vector2.ONE
	location_card.position = Vector2(30, 100)
	toast_panel.position = Vector2(maxf(24, (size.x - 340.0 - 460.0) / 2.0), size.y - 156)
	help_overlay.position = (size - help_overlay.size) / 2.0

func _update_panel() -> void:
	var person := _selected()
	if person.is_empty() or name_label == null:
		return
	name_label.text = person.name
	subtitle_label.text = "%s · 山野行者" % person.realm
	age_label.text = "%d 岁" % person.age
	root_label.text = person.root
	origin_label.text = person.origin
	var talent: int = person.talent
	talent_label.text = "%s · %d" % [("上佳" if talent >= 70 else "平和" if talent >= 40 else "朴拙"), talent]
	health_label.text = "%d / %d" % [person.health, person.max_health]
	health_bar.max_value = person.max_health
	health_bar.value = person.health
	cultivation_label.text = "%.1f / %.0f" % [person.cultivation, person.cultivation_max]
	cultivation_bar.max_value = person.cultivation_max
	cultivation_bar.value = person.cultivation
	rate_label.text = "+%.2f 修为 / 秒" % person.cultivation_rate if person.cultivation_rate > 0 else ("修为已满，静待机缘" if person.cultivation >= person.cultivation_max else "尚未开始吸纳灵气")
	reason_label.text = person.intent_reason
	reason_label.tooltip_text = person.intent_reason
	state_label.text = person.state
	var cell := Vector2i(person.position / 16.0)
	position_label.text = "%s · %d, %d" % [person.destination, cell.x, cell.y]
	follow_button.text = "◎  正在跟随 · F 取消" if follow else "◎  跟随此人"
	follow_button.set_pressed_no_signal(follow)
	count_label.text = "●  生灵 %d" % simulation.villagers.size()
	time_label.text = "初元 · 第 %d 日  %s" % [int(simulation.elapsed / 60.0) + 1, "已暂停" if paused else "%d×" % speed]
	zoom_label.text = "%d%%" % roundi(camera_zoom * 100)
	var sitting := 0
	for other in simulation.villagers:
		if other.state == "打坐修炼":
			sitting += 1
	if placement_mode:
		spring_status.text = "点击陆地放置 · 右键取消 · 灵泉 %d/6" % simulation.springs.size()
	elif not simulation.springs.is_empty():
		spring_status.text = "灵泉 %d/6 · %d 人正在打坐修炼" % [simulation.springs.size(), sitting]
	else:
		spring_status.text = "布下第一处灵泉，观察行者的选择"
	var options: Array[Dictionary] = []
	for other in simulation.villagers:
		if other.id != selected_id:
			options.append(other)
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.position.distance_squared_to(person.position) < b.position.distance_squared_to(person.position))
	for i in range(nearby_buttons.size()):
		var button := nearby_buttons[i]
		var other: Dictionary = options[i]
		button.text = "  %s     %s" % [other.name, other.state]
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection.callable)
		button.pressed.connect(_select.bind(other.id))

func _make_minimap() -> void:
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var palette: Array[Color] = [Color("2b6262"), Color("a59d70"), Color("789568"), Color("4e7255"), Color("728276"), Color("b1a578")]
	for y in range(64):
		for x in range(64):
			image.set_pixel(x, y, palette[simulation.tile_at(Vector2i(x, y))])
	for person in simulation.villagers:
		var cell := Vector2i(person.position / 16.0)
		image.set_pixel(clampi(cell.x, 0, 63), clampi(cell.y, 0, 63), Color("f0d99a"))
	for spring in simulation.springs:
		image.set_pixel(spring.cell.x, spring.cell.y, Color("93ffcb"))
	minimap.texture = ImageTexture.create_from_image(image)

func _minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		follow = false
		camera.position = event.position / minimap.size * 1024.0 + _camera_bias()
		_clamp_camera()

func _panel(parent: Node, at: Vector2, dimensions: Vector2, color: Color, radius: int = 6) -> Panel:
	var panel := Panel.new()
	panel.position = at
	panel.size = dimensions
	panel.add_theme_stylebox_override("panel", _style(color, radius))
	parent.add_child(panel)
	return panel

func _style(color: Color, radius: int, border: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	if border:
		style.set_border_width_all(1)
		style.border_color = EDGE
	return style

func _label(parent: Node, text: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, at: Vector2, dimensions: Vector2, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", GOLD if accent else INK)
	button.add_theme_color_override("font_hover_color", Color("f5e8be"))
	button.add_theme_color_override("font_pressed_color", Color("f5e8be"))
	button.add_theme_stylebox_override("normal", _style(Color("2d4037") if accent else Color("213732"), 4))
	button.add_theme_stylebox_override("hover", _style(Color("3a5143"), 4))
	button.add_theme_stylebox_override("pressed", _style(Color("485b43"), 4))
	parent.add_child(button)
	return button

func _rule(parent: Node, x: float, y: float, width: float, height: float = 1.0) -> void:
	var line := ColorRect.new()
	line.position = Vector2(x, y)
	line.size = Vector2(width, height)
	line.color = EDGE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _save_screenshot() -> void:
	var directory := ProjectSettings.globalize_path("res://evidence")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("screenshot-%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	var result := get_viewport().get_texture().get_image().save_png(path)
	_show_toast("截图已保存到 evidence 文件夹" if result == OK else "截图保存失败，请检查目录权限")

func _capture_and_exit() -> void:
	paused = true
	toast_panel.hide()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_path.get_base_dir()))
	var result := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(capture_path))
	print("CAPTURE_RESULT=", result, " PATH=", capture_path)
	get_tree().quit(0 if result == OK and smoke_failures == 0 else 1)

func _run_interaction_smoke() -> void:
	await get_tree().process_frame
	await _test_key(KEY_SPACE)
	_smoke_check(paused, "Space key should pause the world")
	var count_before: int = simulation.tick_count
	await get_tree().create_timer(0.3).timeout
	_smoke_check(simulation.tick_count == count_before, "Pause must stop simulation")
	await _test_key(KEY_SPACE)
	await get_tree().create_timer(0.3).timeout
	_smoke_check(simulation.tick_count > count_before, "Resume must advance simulation")
	var person: Dictionary = simulation.villagers[7]
	var point: Vector2 = get_viewport().get_canvas_transform() * (world_view.visual_position(person) - Vector2(0, 5))
	await _test_click(point)
	_smoke_check(name_label.text == person.name, "Map click should select the matching person")
	await _test_key(KEY_F)
	_smoke_check(follow and follow_button.button_pressed, "Follow key should update visible state")
	await _test_key(KEY_F)
	var camera_before := camera.position
	var drag_start := Vector2(700, 650)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = drag_start
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = drag_start + Vector2(40, 20)
	motion.relative = Vector2(40, 20)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	_smoke_check(camera.position.distance_to(camera_before) > 1.0, "Mouse drag should pan camera")
	_smoke_check(selected_id == 7, "Dragging should not change character selection")
	var zoom_before := camera_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(550, 400)
	get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	_smoke_check(camera_zoom > zoom_before, "Mouse wheel should zoom")
	await _test_click(speed_buttons[2].global_position + speed_buttons[2].size / 2.0)
	_smoke_check(speed == 4 and speed_buttons[2].button_pressed, "Speed button should update state")
	_set_speed(1)
	_focus_village()
	_select(0)
	print("INTERACTION_SMOKE_PASS: keyboard pause/resume, map click, drag, follow, wheel, speed button" if smoke_failures == 0 else "INTERACTION_SMOKE_FAIL: %d" % smoke_failures)
	smoke_finished = true
	if not auto_capture:
		get_tree().quit(0 if smoke_failures == 0 else 1)

func _smoke_check(condition: bool, message: String) -> void:
	if not condition:
		smoke_failures += 1
		printerr("INTERACTION_CHECK_FAILED: ", message)

func _test_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = code
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _test_click(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move, true)
	await get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.position = at
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = at
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.position = at
	release.global_position = at
	release.button_index = MOUSE_BUTTON_LEFT
	get_viewport().push_input(release, true)
	await get_tree().process_frame
