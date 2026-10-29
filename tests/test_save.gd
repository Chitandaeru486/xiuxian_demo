extends SceneTree
const Codec = preload("res://core/save_codec.gd")
const Store = preload("res://core/save_store.gd")
const World = preload("res://core/world.gd")
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _initialize() -> void:
	var fixture := {"rules_version": Codec.RULES_VERSION, "seed": 9007199254740993,
		"minimum": -9223372036854775807 - 1, "maximum": 9223372036854775807,
		"birth_minute": -123456789, "numerator": 999999,
		"candidate_config_status": "candidate", "rules": {"version": "breakthrough-candidate.2", "quantile_scale": 1000000},
		"registered_future_fixture": {"type": "fixture", "history": [1, 2, 3], "paid_energy": 35},
		"counters": {"commit": 9007199254740995}, "$type": "user-map-key"}
	var encoded := Codec.encode(fixture)
	check(encoded.ok, "AC16 encode exact integer fixture")
	var decoded := Codec.decode(encoded.text)
	check(decoded.ok and decoded.snapshot == fixture, "AC16 exact >2^53/int64 limits/negative birth/fraction remainder")
	check(encoded.text.contains('"9007199254740993"'), "AC16 disk integer is decimal string")
	check(Codec.encode({"float": 1.5}).ok == false, "AC16 floating payload rejected")
	var reversed: Dictionary = {}
	var keys := fixture.keys()
	keys.reverse()
	for key in keys:
		reversed[key] = fixture[key]
	check(Codec.encode(reversed).text == encoded.text, "AC22 canonical dictionary ordering")
	check(decoded.snapshot.rules == fixture.rules and decoded.snapshot.registered_future_fixture == fixture.registered_future_fixture, "AC22 full candidate and future fixture survive")
	for bad in ["01", "+1", "-0", " 1", "1.0", "9223372036854775808", "-9223372036854775809", "", "--1"]:
		var envelope: Dictionary = encoded.envelope.duplicate(true)
		envelope.payload.value.seed.value = bad
		redigest(envelope)
		check(not Codec.decode(Codec.canonical(envelope)).ok, "AC16 rejects malformed integer " + bad)
	var altered: Dictionary = encoded.envelope.duplicate(true)
	altered.payload.value.seed.value = "5"
	check(not Codec.decode(Codec.canonical(altered)).ok, "AC17 digest corruption rejected")
	for version_key in ["format_version", "rules_version"]:
		altered = encoded.envelope.duplicate(true)
		altered[version_key] = "future.999"
		check(not Codec.decode(Codec.canonical(altered)).ok, "AC18 unknown " + version_key)
	altered = encoded.envelope.duplicate(true)
	altered.payload.value.seed["$type"] = "future-type"
	redigest(altered)
	check(not Codec.decode(Codec.canonical(altered)).ok, "AC18 unknown typed payload")
	check(not Codec.decode(encoded.text.substr(0, encoded.text.length() / 2)).ok, "AC15 truncated file rejected")
	disk_tests()
	print("SAVE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func redigest(envelope: Dictionary) -> void:
	var digest := Codec.canonical(envelope.payload).sha256_text()
	envelope.payload_digest = "sha256:" + digest
	envelope.snapshot_id = "snapshot-" + digest

func disk_tests() -> void:
	var store := Store.new()
	store.initialize("res://evidence/test_saves/save_suite")
	DirAccess.make_dir_recursive_absolute(store.directory)
	# Remove only these test-owned fixed filenames; no user saves are touched.
	for kind in ["manual", "auto"]:
		for slot in range(1, 4):
			for suffix in ["", ".backup", ".tmp", ".backup.tmp"]:
				var path := store.directory.path_join("%s_%d.json%s" % [kind, slot, suffix])
				if FileAccess.file_exists(path):
					DirAccess.remove_absolute(path)
	var world := World.new()
	world.initialize(9007199254740993, 2)
	world.state.numerator = 999999
	world.state.persons.P1.extensions.future_state_v1 = {"polishing_history": [7, 11], "day_accumulator": 132, "energy_remainder": 51}
	world.state.persons.P1.wallet = {"balance": 9007199254740993, "reserved": 25}
	world.state.persons.P1.paid_energy = 35
	world.state.persons.P1.burn_days = 3600
	var baseline := world.snapshot()
	var manual := store.directory.path_join("manual_1.json")
	check(store.save_slot(world, 1).ok, "AC19 manual slot first save")
	var original := FileAccess.get_file_as_string(manual)
	world.advance_minutes(7)
	var live := world.snapshot()
	check(not store.save_slot(world, 1).ok and FileAccess.get_file_as_string(manual) == original, "AC19 overwrite cancellation keeps file")
	check(not store.load_slot(world, 1).ok and world.snapshot() == live, "AC19 discard confirmation required")
	check(not store.save_slot(world, 0, true).ok and not store.load_slot(world, 4, true).ok, "AC19 fixed slot range")
	for mode in ["write_denied", "disk_full", "truncated", "replacerenamefail"]:
		store.failure_mode = mode
		var outcome := store.save_slot(world, 1, true)
		check(not outcome.ok and FileAccess.get_file_as_string(manual) == original and world.snapshot() == live, "AC15 " + mode + " preserves old slot and current world")
	store.failure_mode = ""
	check(store.load_slot(world, 1, true).ok and world.snapshot() == baseline, "AC16/22 disk roundtrip complete state and full candidate config")
	for slot in [2, 3]:
		check(store.save_slot(world, slot).ok, "AC19 manual slot " + str(slot))
	for mutation in ["digest", "balance", "reserved", "entity", "queue", "extension", "action", "format", "rules"]:
		var bad := baseline.duplicate(true)
		match mutation:
			"balance": bad.persons.P1.wallet.balance = -1
			"reserved": bad.persons.P1.wallet.reserved = 9223372036854775807
			"entity": bad.persons.P1.current_action = "A999"
			"queue": bad.queue.append({"due_minute":10,"phase":5,"stable_sequence":1,"action_id":"A999","kind":"action_complete","person_id":"P1","payload":{}})
			"extension": bad.persons.P1.extensions["unknown_future_v999"] = {}
			"action":
				bad.counters.action = 1
				bad.actions["A1"] = {"id":"A1","person_id":"P1","kind":"unknown_v999","status":"executing","started_at":0,"due_minute":10,"payload":{},"fixture":true}
				bad.persons.P1.current_action = "A1"
		var encoded := Codec.encode(bad)
		if not encoded.ok:
			check(false, "bad fixture encode " + mutation + ": " + str(encoded.error))
			continue
		var envelope: Dictionary = encoded.envelope.duplicate(true)
		if mutation == "digest": envelope.payload.value.seed.value = "123"
		if mutation == "format": envelope.format_version = "999"
		if mutation == "rules": envelope.rules_version = "unknown-rules.999"
		write_file(manual, Codec.canonical(envelope))
		var before := world.snapshot()
		var bad_text := FileAccess.get_file_as_string(manual)
		check(not store.load_slot(world, 1, true).ok and world.snapshot() == before and FileAccess.get_file_as_string(manual) == bad_text, "AC17/18 rejected " + mutation + " leaves world/RNG/file untouched")
	write_file(manual, original)
	world.advance_minutes(4 * 43200 + 7)
	check(world.autosave_snapshots.size() == 4, "AC19 actual four boundary snapshots queued")
	var queued: Array = world.autosave_snapshots.duplicate(true)
	check(store.drain_autosaves(world).ok and world.autosave_snapshots.is_empty(), "AC19 boundary queue drained")
	for slot in range(1, 4):
		var decoded := Codec.decode(FileAccess.get_file_as_string(store.directory.path_join("auto_%d.json" % slot)))
		var expected: int = 4 * 43200 if slot == 1 else slot * 43200
		check(decoded.ok and decoded.snapshot.world_minute == expected and decoded.snapshot == queued[(expected / 43200) - 1], "AC19 autoslot %d true boundary %d" % [slot, expected])
	check(FileAccess.get_file_as_string(manual) == original, "AC19 autosaves leave manual slots intact")
	check(Codec.decode(FileAccess.get_file_as_string(store.directory.path_join("auto_1.json.backup"))).snapshot == queued[0], "AC15 rotated autosave retains validated prior backup")
	# Reinitializing the store chooses rotation from world time, independent of volatile counters.
	var restarted := Store.new()
	restarted.initialize(store.directory)
	world.advance_minutes(43200)
	check(restarted.drain_autosaves(world).ok, "AC19 restart rotation metadata derives from boundary time")
	check(Codec.decode(FileAccess.get_file_as_string(store.directory.path_join("auto_2.json"))).snapshot.world_minute == 5 * 43200, "AC19 fifth boundary uses second autoslot")
	continuation_tests(store)

func write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func continuation_tests(store) -> void:
	for kind in ["move_complete", "action_complete", "random_complete"]:
		var continuous := World.new()
		continuous.initialize(20261029, 1)
		continuous.fixture_enabled = true
		continuous.state.persons.P1.wallet.reserved = 20
		continuous.state.persons.P1.paid_energy = 17
		continuous.state.persons.P1.daily_budget = 60
		continuous.state.persons.P1.daily_used = 9
		continuous.state.persons.P1.burn_days = 360
		continuous.state.persons.P1.extensions.future_state_v1.polishing_history = [12, 18]
		check(continuous.fixture_schedule(kind, "P1", 100, {"position":[4, 7]} if kind == "move_complete" else {}).ok, "AC20 fixture " + kind)
		continuous.advance_minutes(25)
		var save_result: Dictionary = store.save_slot(continuous, 3, true)
		check(save_result.ok, "AC20 save in-progress " + kind + ": " + str(save_result.get("error", "")))
		var resumed := World.new()
		resumed.initialize(123, 0)
		check(store.load_slot(resumed, 3, true).ok, "AC20 restore in-progress " + kind)
		continuous.advance_minutes(175)
		resumed.advance_minutes(175)
		check(continuous.snapshot() == resumed.snapshot(), "AC20/21 continued full business and RNG equivalence " + kind)
		continuous.fixture_schedule("random_complete", "P1", 250)
		resumed.fixture_enabled = true
		resumed.fixture_schedule("random_complete", "P1", 250)
		continuous.advance_minutes(50)
		resumed.advance_minutes(50)
		check(continuous.snapshot() == resumed.snapshot(), "AC21 future random sequence " + kind)
