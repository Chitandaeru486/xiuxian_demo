extends SceneTree

const World = preload("res://core/world.gd")
const SEED = 20261029

func _initialize() -> void:
	var samples: Array = []
	for workload in ["empty", "one_move_per_person"]:
		for count in [30, 96, 300]:
			for multiplier in [1, 360]:
				for repeat in range(3):
					samples.append(_sample(workload, count, multiplier, repeat + 1))
	var evidence = {"scenario_id": "S1-AC24", "build": "s1-build.1", "rules": "s1-rules.1", "executed_at": Time.get_datetime_string_from_system(true),
		"godot": Engine.get_version_info(), "os": OS.get_name(), "cpu": OS.get_processor_name(),
		"logical_cpu_count": OS.get_processor_count(), "memory": OS.get_memory_info(),
		"display": "headless; no rendered viewport; FPS not measured", "configured_window_size": [1440, 900], "samples": samples,
		"limitations": ["S1 state/hourly lifespan checks: empty queue control and one move fixture per person due at minutes 1..population. No repeated AI, pathfinding or economy.",
			"Elapsed measurements are synchronous simulation processing, not a graphical frame-rate claim.",
			"OS process CPU utilization is not sampled; processor identity and elapsed processing time are recorded.",
			"engine_static_memory_bytes is Godot tracked static allocation, not total process RSS/working set."]}
	var passed = true
	for sample in samples:
		passed = passed and sample.passed
	evidence["status"] = "PASS" if passed else "FAIL"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	var file = FileAccess.open("res://evidence/benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	print("S1-AC24 ", evidence.status, ": ", samples.size(), " measured logical-load samples; FPS not measured")
	quit(0 if passed else 1)

func _sample(workload: String, count: int, multiplier: int, repeat: int) -> Dictionary:
	var world = World.new()
	world.initialize(SEED, count)
	world.set_multiplier(multiplier)
	world.fixture_enabled = true
	var setup_errors: Array = []
	if workload == "one_move_per_person":
		for i in range(1, count + 1):
			var scheduled = world.fixture_schedule("move_complete", "P%d" % i, i, {"position":[i % 192, (i * 3) % 192]})
			if not scheduled.ok: setup_errors.append(scheduled)
	var initial_queue: int = world.state.queue.size()
	var initial_validation: Dictionary = World.validate_snapshot(world.snapshot())
	var before: int = Time.get_ticks_usec()
	var result = world.advance_real_us(24000000, 1000000)
	var elapsed: int = maxi(1, Time.get_ticks_usec() - before)
	var minute: int = world.state.world_minute
	var target: int = 1440 * multiplier
	var completed := 0
	for action in world.state.actions.values():
		if action.status == "completed": completed += 1
	var completion_events := 0
	for event in world.state.events:
		if event.type == "completed": completion_events += 1
	var expected_completed: int = count if workload == "one_move_per_person" else 0
	var positions_correct := true
	if expected_completed > 0:
		for i in range(1, count + 1):
			positions_correct = positions_correct and world.state.persons["P%d" % i].position == [i % 192, (i * 3) % 192]
	var validation: Dictionary = World.validate_snapshot(world.snapshot())
	var passed: bool = setup_errors.is_empty() and initial_validation.ok and result.ok and minute == target and world.state.pending_minutes == 0 and world.state.queue.is_empty() and completed == expected_completed and completion_events == expected_completed and positions_correct and validation.ok
	print("BENCH_SAMPLE ",workload," persons=",count," multiplier=",multiplier," repeat=",repeat," elapsed_us=",elapsed," passed=",passed)
	return {"workload":workload,"persons":count,"multiplier":multiplier,"repeat":repeat,"seed":SEED,
		"input_real_us":24000000,"elapsed_us":elapsed,"target_world_minutes":target,"actual_world_minutes":minute,
		"input_target_reached":minute==target,"processing_world_minutes_per_real_second":float(minute)*1000000.0/elapsed,
		"required_world_minutes_per_real_second":60*multiplier,"initial_due_queue":initial_queue,"final_due_queue":world.state.queue.size(),
		"initial_queue_items_per_person":float(initial_queue)/count,"pending_budget_minutes":world.state.pending_minutes,
		"setup_errors":setup_errors,"initial_validation":initial_validation,"final_validation":validation,
		"expected_completions":expected_completed,"completed_actions":completed,"completion_events":completion_events,"positions_correct":positions_correct,
		"engine_static_memory_bytes":OS.get_static_memory_usage(),"performance_static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"advance_result":result,"passed":passed}
