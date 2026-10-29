extends RefCounted

func run(game: Node2D) -> void:
	await game.get_tree().process_frame
	game.paused = true
	game._place_spring_at(Vector2i(0, 0))
	game._smoke_check(game.simulation.springs.is_empty(), "Invalid water placement must be rejected")
	await game._test_key(KEY_Q)
	game._smoke_check(game.placement_mode, "Q enables placement")
	var cell := Vector2i(37, 32)
	var point: Vector2 = game.get_viewport().get_canvas_transform() * (Vector2(cell * 16) + Vector2(8, 8))
	await game._test_click(point)
	game._smoke_check(game.simulation.springs.size() == 1, "Map click places one spring")
	game._smoke_check(game.simulation.springs[0].cell == cell, "Placement screen coordinates map to correct tile")
	await game._test_key(KEY_ESCAPE)
	game._smoke_check(not game.placement_mode and not game.spring_button.button_pressed, "Esc cancels placement")
	game._smoke_check(not game.world_view.placement_active, "Cancel removes placement preview")
	await game._test_key(KEY_H)
	game._smoke_check(game.world_view.show_aura and game.aura_button.button_pressed, "H enables aura overlay")
	game._smoke_check(not game.world_view.aura_cells.is_empty(), "Overlay contains actual aura cells")
	var saw_walking := false
	var saw_sitting := false
	for i in range(400):
		game.simulation.step(0.1)
		for person in game.simulation.villagers:
			if person.state == "前往灵泉": saw_walking = true
			if person.state == "打坐修炼": saw_sitting = true
	game._smoke_check(saw_walking and saw_sitting, "Placement leads to walking then sitting")
	var observer: Dictionary = {}
	for person in game.simulation.villagers:
		if person.cultivation > 0 and person.cultivation_rate > 0:
			observer = person
			break
	game._smoke_check(not observer.is_empty(), "At least one villager gains cultivation")
	if not observer.is_empty():
		game._select(observer.id)
		game._smoke_check(is_equal_approx(game.cultivation_bar.value, observer.cultivation), "Progress bar matches selected person")
		game._smoke_check(game.reason_label.text == observer.intent_reason, "Panel explains actual decision")
		var before: float = observer.cultivation
		await game.get_tree().create_timer(0.3).timeout
		game._smoke_check(is_equal_approx(observer.cultivation, before), "Pause freezes cultivation")
	game.world_view.interpolation = 1.0
	game._make_minimap()
	game._set_placement(false)
	game._update_panel()
	await game.get_tree().process_frame
	await game.get_tree().process_frame
	game._smoke_check(game.sidebar.position.y + game.sidebar.size.y * game.sidebar.scale.y <= game.get_viewport_rect().size.y, "Sidebar fits viewport")
	print("CULTIVATION_UI_PASS: placement, cancel, overlay, travel, meditation, growth, profile and pause" if game.smoke_failures == 0 else "CULTIVATION_UI_FAIL: %d" % game.smoke_failures)
