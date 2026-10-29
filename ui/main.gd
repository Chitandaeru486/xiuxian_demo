extends Control

const World = preload("res://core/world.gd")
const SaveStore = preload("res://core/save_store.gd")
var world: RefCounted
var saves: RefCounted
var last_us: int
var refresh_elapsed := 0.0
var world_text: RichTextLabel
var person_text: RichTextLabel
var events_text: RichTextLabel
var status: Label
var roster: ItemList
var pause_button: Button
var watch_button: Button
var speed_select: OptionButton
var slot_select: OptionButton
var fixture_toggle: CheckBox
var confirm: ConfirmationDialog
var pending_confirm: Callable
var person_ids: Array[String] = []
var selected_person := "P1"
var save_slot := 1
var ui_test := false
var ticks_before := 0
var sample_us := 0
var actual_speed := 0.0

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	var theme_resource := Theme.new()
	theme_resource.default_font = font
	theme_resource.default_font_size = 15
	theme = theme_resource
	world = World.new()
	world.initialize(20261029, 96)
	ui_test = OS.get_cmdline_user_args().has("--ui-test")
	saves = SaveStore.new()
	saves.initialize(ProjectSettings.globalize_path("res://evidence/ui_test_saves" if ui_test else "res://.local_saves"))
	_build_ui()
	_rebuild_roster()
	last_us = Time.get_ticks_usec()
	sample_us = last_us
	get_tree().auto_accept_quit = false
	for argument in OS.get_cmdline_user_args():
		if argument == "--ui-test": ui_test = true
	_refresh()
	if ui_test: _run_ui_test.call_deferred()

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var result: Dictionary = world.advance_real_us(now - last_us, 1000)
	last_us = now
	if not result.get("ok", true): status.text = "推进失败：" + str(result.get("error", result))
	if not world.autosave_snapshots.is_empty():
		var saved: Dictionary = saves.drain_autosaves(world)
		if not saved.get("ok", false): status.text = "自动保存失败：" + str(saved.get("error", saved))
	refresh_elapsed += delta
	if now - sample_us >= 1000000:
		actual_speed = float(int(world.state.world_minute) - ticks_before) * 1000000.0 / float(now - sample_us) / 60.0
		ticks_before = world.state.world_minute
		sample_us = now
	if refresh_elapsed >= 0.2:
		refresh_elapsed = 0.0
		_refresh()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "山海灵境  /  S1 世界运行台"
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color("d7c895")
	column.add_child(title)
	var caption := Label.new()
	caption.text = "权威状态 · 整数历法 · 命令与事件 · 可靠存读   |   S1调试入口，非完整玩法界面"
	caption.modulate = Color("97b5a7")
	column.add_child(caption)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	pause_button = _button(bar, "暂停", _toggle_pause)
	_button(bar, "确认提醒并继续", _resume)
	speed_select = OptionButton.new()
	for rate in [1, 2, 4, 24, 360]: speed_select.add_item("%d×" % rate, rate)
	speed_select.item_selected.connect(func(index: int) -> void: _change_speed(speed_select.get_item_id(index)))
	bar.add_child(speed_select)
	_button(bar, "单步 1 分钟", _single_step)
	_button(bar, "重建96人世界", func() -> void: _ask("重建世界将放弃当前未保存状态。", _new_world))
	var store_bar := HBoxContainer.new()
	column.add_child(store_bar)
	slot_select = OptionButton.new()
	for number in [1, 2, 3]: slot_select.add_item("手动槽 %d" % number, number)
	slot_select.item_selected.connect(func(index: int) -> void: save_slot = index + 1)
	store_bar.add_child(slot_select)
	_button(store_bar, "保存", _request_save)
	_button(store_bar, "读取", func() -> void: _ask("放弃当前未保存进度，并读取所选槽位？", _load_confirmed))
	fixture_toggle = CheckBox.new()
	fixture_toggle.text = "测试夹具模式（不代表正式突破玩法）"
	fixture_toggle.toggled.connect(func(value: bool) -> void: world.fixture_enabled = value)
	store_bar.add_child(fixture_toggle)
	_button(store_bar, "安排测试提醒", _schedule_fixture)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	column.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	body.add_child(left)
	world_text = _text_box(left, 250)
	roster = ItemList.new()
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster.custom_minimum_size.y = 160
	roster.item_selected.connect(func(index: int) -> void:
		selected_person = person_ids[index]
		_refresh())
	left.add_child(roster)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size.x = 360
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(middle)
	person_text = _text_box(middle, 300)
	watch_button = _button(middle, "关注此人", _toggle_watch)
	var info := Label.new()
	info.text = "世界事实与人物已知信息分别保存。\n测试夹具必须显式开启；关闭后普通天道无强升权限。\n24现实秒：1×为1天，360×为1年。\n后台继续；退出后无离线推进。"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.modulate = Color("97b5a7")
	middle.add_child(info)
	events_text = _text_box(body, 300)
	events_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status = Label.new()
	status.text = "已创建世界，尚未保存。存档位于本工程 .local_saves 目录。"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.modulate = Color("d7c895")
	column.add_child(status)
	confirm = ConfirmationDialog.new()
	confirm.title = "确认世界操作"
	confirm.confirmed.connect(func() -> void:
		if pending_confirm.is_valid(): pending_confirm.call())
	add_child(confirm)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _text_box(parent: Node, width: float) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.custom_minimum_size = Vector2(width, 240)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.bbcode_enabled = false
	label.selection_enabled = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172a2b")
	style.set_content_margin_all(14)
	style.set_corner_radius_all(6)
	label.add_theme_stylebox_override("normal", style)
	parent.add_child(label)
	return label

func _ask(message: String, action: Callable) -> void:
	confirm.ok_button_text = "确认"
	if confirm.has_meta("exit_button"):
		confirm.get_meta("exit_button").hide()
	pending_confirm = action
	confirm.dialog_text = message
	confirm.popup_centered(Vector2i(480, 160))

func _toggle_pause() -> void:
	world.set_paused(not bool(world.state.paused))
	_refresh()

func _resume() -> void:
	_report(world.resume(), "提醒已确认，继续推进")
	_refresh()

func _change_speed(rate: int) -> void:
	_report(world.set_multiplier(rate), "目标倍率 %d×" % rate)
	_refresh()

func _single_step() -> void:
	# Core provides explicit single-step permission while preserving paused state.
	if world.has_method("single_step"):
		_report(world.single_step(1), "单步完成")
	else:
		status.text = "请继续后推进；暂停期间不直接修改世界时间。"
	_refresh()

func _new_world() -> void:
	world.initialize(20261029, 96)
	world.fixture_enabled = fixture_toggle.button_pressed
	selected_person = "P1"
	last_us = Time.get_ticks_usec()
	ticks_before = 0
	sample_us = last_us
	_rebuild_roster()
	status.text = "已重建世界，尚未保存。"
	_refresh()

func _toggle_watch() -> void:
	_watch_command(not world.state.followed.has(selected_person))
	_refresh()

func _watch_command(value: bool) -> void:
	var sequence: int = int(world.state.counters.command) + 1
	var identifier := "ui_watch_%d" % sequence
	while world.state.command_results.has(identifier):
		sequence += 1
		identifier = "ui_watch_%d" % sequence
	var result: Dictionary = world.submit({"command_id": identifier, "issuer": "天道", "issued_at": world.state.world_minute, "execute_at": world.state.world_minute, "sequence": sequence, "type": "watch" if value else "unwatch", "payload": {"person_id": selected_person}})
	status.text = "关注设置已更新" if result.status == "applied" else "关注设置失败：" + str(result.error_code)

func _schedule_fixture() -> void:
	if not world.fixture_enabled:
		status.text = "请显式开启测试夹具模式。普通天道不创建突破或危机测试。"
		return
	_watch_command(true)
	_report(world.fixture_schedule("reminder", selected_person, int(world.state.world_minute) + 100, {"reason": "S1准备期测试提醒"}), "已安排100世界分钟后的测试提醒")
	_refresh()

func _request_save() -> void:
	var result: Dictionary = saves.save_slot(world, save_slot, false)
	if not result.get("ok", false) and str(result.get("error", "")).contains("confirm"):
		_ask("覆盖手动槽 %d？" % save_slot, func() -> void: _report(saves.save_slot(world, save_slot, true), "保存成功"))
	else:
		_report(result, "保存成功")

func _load_confirmed() -> void:
	var result: Dictionary = saves.load_slot(world, save_slot, true)
	_report(result, "读取成功；按保存的暂停状态恢复")
	if result.get("ok", false):
		last_us = Time.get_ticks_usec()
		ticks_before = world.state.world_minute
		sample_us = last_us
		_rebuild_roster()
	_refresh()

func _report(result: Dictionary, message: String) -> void:
	status.text = message if result.get("ok", false) else "操作未完成：" + str(result.get("error", result))

func _rebuild_roster() -> void:
	roster.clear()
	person_ids.clear()
	for identifier in world.state.persons:
		person_ids.append(str(identifier))
		roster.add_item("%s · %s" % [identifier, world.state.persons[identifier].get("name", "")])
	if not person_ids.is_empty():
		if not person_ids.has(selected_person): selected_person = person_ids[0]
		roster.select(person_ids.find(selected_person))

func _refresh() -> void:
	if world_text == null: return
	var s: Dictionary = world.state
	pause_button.text = "已暂停" if s.paused else "暂停"
	for i in range(speed_select.item_count):
		if speed_select.get_item_id(i) == int(s.multiplier): speed_select.select(i)
	var date: Dictionary = world.date_parts()
	var date_text := "第%d年 %02d月 %02d日\n%02d:%02d" % [date.year, date.month, date.day, date.hour, date.minute]
	world_text.text = "世界时钟\n\n%s\n\n世界分钟：%d\n目标：%d×\n实测：%.2f×\n状态：%s\n\n地图：192 × 192\n人物：%d\n待办：%d\n待推进：%s 分钟\n\n种子：%s\n候选配置：candidate" % [date_text, s.world_minute, s.multiplier, actual_speed, "暂停" if s.paused else "推进中", s.persons.size(), s.queue.size(), str(s.get("pending_minutes", 0)), str(s.seed)]
	watch_button.text = "取消关注 · 此人已关注" if s.followed.has(selected_person) else "关注此人"
	person_text.text = "人物权威状态 / 派生值\n\n" + JSON.stringify(world.person_summary(selected_person), "  ")
	var notices: Array = s.get("notifications", []).filter(func(n: Dictionary) -> bool: return not s.acknowledged.has(n.notification_id))
	var facts: Array = s.get("events", [])
	events_text.text = "通知与真实事件账本\n\n待处理提醒：\n" + JSON.stringify(notices, "  ") + "\n\n最近事件（最多12条）：\n"
	for i in range(maxi(0, facts.size() - 12), facts.size()): events_text.text += JSON.stringify(facts[i], "  ") + "\n\n"

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_ask("退出后世界停止。保存退出将覆盖当前槽；也可不保存退出，或取消返回。", _save_exit)
		confirm.ok_button_text = "保存并退出"
		if not confirm.has_meta("exit_button"):
			var button := confirm.add_button("不保存退出", false, "discard_exit")
			button.pressed.connect(func() -> void: get_tree().quit())
			confirm.set_meta("exit_button", button)
		confirm.get_meta("exit_button").show()

func _save_exit() -> void:
	var result: Dictionary = saves.save_slot(world, save_slot, true)
	if result.get("ok", false): get_tree().quit()
	else: _report(result, "")

func _run_ui_test() -> void:
	await get_tree().process_frame
	var checks: Array = []
	pause_button.pressed.emit()
	_change_speed(360)
	checks.append({"expected": "Pause control and multiplier preserve paused authority", "passed": world.state.paused and world.state.multiplier == 360})
	var before_fixture: Dictionary = world.snapshot()
	_schedule_fixture()
	checks.append({"expected": "Fixture control refuses use before explicit opt-in", "passed": before_fixture == world.snapshot()})
	fixture_toggle.button_pressed = true
	_schedule_fixture()
	world.resume()
	world.advance_minutes(200)
	checks.append({"expected": "Watched reminder stops authority at exactly minute 100", "passed": world.state.paused and world.state.world_minute == 100 and not world.state.notifications.is_empty()})
	var saved: Dictionary = saves.save_slot(world, 1, true)
	_report(saved, "图形验收保存")
	checks.append({"expected": "Graphical session saves a valid manual slot", "passed": saved.get("ok", false)})
	var before: Dictionary = world.snapshot()
	_request_save()
	checks.append({"expected": "Existing slot opens overwrite confirmation", "passed": confirm.visible})
	confirm.hide()
	world.initialize(20261028, 30)
	_load_confirmed()
	checks.append({"expected": "Load control restores exact saved state after world replacement", "passed": before == world.snapshot()})
	_ask("关闭详情不应恢复时间", func() -> void: pass)
	confirm.hide()
	checks.append({"expected": "Closing detail leaves reminder pause unchanged", "passed": world.state.paused})
	if OS.get_cmdline_user_args().has("--small-ui"):
		get_window().size = Vector2i(1152, 720)
		await get_tree().process_frame
	_refresh()
	await RenderingServer.frame_post_draw
	var suffix := "-small" if OS.get_cmdline_user_args().has("--small-ui") else ""
	var screenshot := "res://evidence/s1-console%s.png" % suffix
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(screenshot))
	checks.append({"expected": "Real viewport capture succeeds", "passed": error == OK})
	var okay := true
	for check in checks: okay = okay and check.passed
	var evidence := {"scenario_id": "S1-AC23", "status": "PASS" if okay else "FAIL", "build": "s1-build.1", "rules": "s1-rules.1", "executed_at_utc": Time.get_datetime_string_from_system(true), "engine": Engine.get_version_info(), "window_size": [get_window().size.x, get_window().size.y], "viewport_size": [get_viewport_rect().size.x, get_viewport_rect().size.y], "checks": checks, "screenshot": screenshot, "limitations": ["Script emits actual connected control signals and invokes UI handlers in a rendered Godot session; no physical mouse automation.", "S1 debug console only; pixel world and full gameplay are outside this stage."]}
	var file := FileAccess.open("res://evidence/ui%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	print("S1_UI_PASS" if okay and error == OK else "S1_UI_FAIL")
	get_tree().quit(0 if okay and error == OK else 1)
