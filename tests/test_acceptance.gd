extends SceneTree

const World = preload("res://core/world.gd")
const Codec = preload("res://core/save_codec.gd")
const Store = preload("res://core/save_store.gd")
const YEAR = 518400
const SEED = 20261029
var rows: Array = []
var current: Dictionary = {}
var saves: RefCounted
var save_dir: String

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--continuation-child":
		_child(args[1])
		return
	# Recorded equivalent local directory: sandbox cannot write Godot's AppData user://.
	save_dir = ProjectSettings.globalize_path("res://.acceptance_saves/run_" + str(Time.get_ticks_usec()))
	saves = Store.new()
	saves.initialize(save_dir)
	for number in range(1, 25):
		current = {"scenario_id": "S1-AC%02d" % number, "status": "NOT_RUN", "assertions": [], "limitations": []}
		call("_ac%02d" % number)
		if not current.assertions.is_empty():
			current.status = "PASS"
			for assertion in current.assertions:
				if not assertion.passed: current.status = "FAIL"
		rows.append(current)
		print(current.scenario_id, " ", current.status, " (", current.assertions.size(), " assertions)")
	_e01()
	_e02()
	_e03()
	var failed = 0
	for row in rows:
		if row.status == "FAIL": failed += 1
	var evidence = {"build": "s1-build.1", "rules": "s1-rules.1", "config": "breakthrough-candidate.2 (candidate, disabled)",
		"seed": SEED, "executed_at": Time.get_datetime_string_from_system(true), "engine": Engine.get_version_info(),
		"comparison_exclusions": [], "scenarios": rows, "failed_scenarios": failed,
		"limitations": ["AC23 requires separate graphical evidence from the main agent.", "AC24 is measured by tests/benchmark.gd.",
			"Direct state edits in malformed-save tests construct adversarial input; fixture APIs create valid directed scenarios."]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	_write("res://evidence/acceptance.json", JSON.stringify(evidence, "\t"))
	quit(0 if failed == 0 else 1)

func _w(count: int = 3):
	var world = World.new()
	world.initialize(SEED, count)
	world.fixture_enabled = true
	return world

func _check(condition: bool, expected: String, actual: Variant = null) -> void:
	current.assertions.append({"expected": expected, "passed": condition, "actual": actual})
	if not condition: print("  FAIL: ", expected, " actual=", actual)

func _same(a: Variant, b: Variant, message: String) -> void:
	_check(World.canonical(a) == World.canonical(b), message, "equal" if World.canonical(a) == World.canonical(b) else "different")

func _command(world, id: String, kind: String = "set_target", payload: Dictionary = {"person_id":"P1","target":"observe"}, issuer: String = "NPC") -> Dictionary:
	return {"command_id": id, "issuer": issuer, "issued_at": world.state.world_minute, "execute_at": world.state.world_minute,
		"sequence": world.state.counters.command + 1, "type": kind, "payload": payload.duplicate(true)}

func _write(path: String, content: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _roundtrip(world, slot: int = 1):
	var saved = saves.save_slot(world, slot, true)
	if not saved.ok: _bad_types(world.snapshot())
	_check(saved.ok, "Save writes a verified authoritative snapshot", saved)
	var restored = _w()
	var loaded = saves.load_slot(restored, slot, true)
	_check(loaded.ok, "Load validates and replaces a fresh candidate world", loaded)
	_same(world.snapshot(), restored.snapshot(), "Full snapshot equality at save/load boundary; no fields excluded")
	return restored

func _bad_types(value: Variant, path: String = "state") -> void:
	if value is Dictionary:
		for key in value:
			if not key is String: print("NONSTRING KEY ",path," ",key)
			_bad_types(value[key], path+"."+str(key))
	elif value is Array:
		for i in value.size(): _bad_types(value[i],path+"["+str(i)+"]")
	elif not (value == null or value is String or value is int or value is bool):
		print("NONPRIMITIVE ", path, " type=", typeof(value), " value=",value)

func _bad_load(world, candidate: Dictionary, label: String) -> void:
	var before = world.snapshot()
	var encoded = Codec.encode(candidate)
	if encoded.ok:
		_write(save_dir.path_join("manual_3.json"), encoded.text)
		var result = saves.load_slot(world, 3, true)
		_check(not result.ok, label + " is rejected during isolated load", result)
	else:
		_check(not encoded.ok, label + " is rejected during encoding", encoded)
	_same(before, world.snapshot(), label + " leaves active state and RNG unchanged")

func _ac01() -> void:
	var w = _w()
	w.advance_minutes(43200 - 1)
	_same(w.date_parts(), {"year":1,"month":1,"day":30,"hour":23,"minute":59}, "30th day ends at month boundary")
	w.advance_minutes(1)
	_same(w.date_parts(), {"year":1,"month":2,"day":1,"hour":0,"minute":0}, "Next minute begins month two")
	w.advance_minutes(YEAR - 43200 - 1)
	_same(w.date_parts(), {"year":1,"month":12,"day":30,"hour":23,"minute":59}, "360th day ends year one")
	w.advance_minutes(1)
	_same(w.date_parts(), {"year":2,"month":1,"day":1,"hour":0,"minute":0}, "No leap day; year boundary advances once")
	_check(w.person_summary("P1").age_minutes == YEAR - w.state.persons.P1.birth_minute, "Age uses the same minute calendar")

func _ac02() -> void:
	for rate in [1, 360]:
		var w = _w()
		w.set_multiplier(rate)
		w.advance_real_us(24000000)
		_check(w.state.world_minute == 1440 * rate, "24 real seconds at %dx yields %d minutes" % [rate,1440*rate], w.state.world_minute)
	var a = _w()
	var b = _w()
	var cmd = _command(a, "speed_equal")
	a.submit(cmd)
	b.submit(cmd)
	a.advance_real_us(360000000)
	b.set_multiplier(360)
	b.advance_real_us(1000000)
	_check(b.state.world_minute == a.state.world_minute and a.state.numerator == 0 and b.state.numerator == 0, "Exact equal-duration input yields equal clock and remainder across rates")
	b.state.multiplier = a.state.multiplier
	_same(a.snapshot(), b.snapshot(), "Equal world time and commands have equal full business state (only selected clock-rate control normalized)")

func _ac03() -> void:
	var a = _w()
	a.advance_real_us(1000000)
	a.set_multiplier(360)
	a.advance_real_us(1000000)
	_check(a.state.world_minute == 21660, "One second at 1x then one second at 360x yields 21660 minutes")
	var b = _w()
	for delta in [1,333333,666666]: b.advance_real_us(delta)
	b.set_multiplier(360)
	for delta in [17,555555,444428]: b.advance_real_us(delta)
	_same(a.snapshot(), b.snapshot(), "Integer input slicing preserves complete world state and numerator")
	var c = _w()
	c.advance_real_us(1)
	c.set_multiplier(360)
	c.advance_real_us(1)
	_check(c.state.numerator == 21660, "Changing multiplier preserves prior subminute remainder", c.state.numerator)
	var delayed = _w()
	delayed.advance_real_us(1000000, 0)
	_check(delayed.state.world_minute == 0 and delayed.state.pending_minutes == 60, "Zero operation budget retains all pending time without skipping")
	delayed.advance_minutes(0)
	_check(delayed.state.world_minute == 60 and delayed.state.pending_minutes == 0, "Later processing consumes retained budget")
	var before = delayed.snapshot()
	_check(not delayed.advance_real_us(-1).ok, "Negative delta rejected")
	_check(not delayed.advance_real_us(9223372036854775807).ok, "Overflow delta rejected")
	_same(before, delayed.snapshot(), "Invalid input does not mutate clock or random state")

func _ac04() -> void:
	var w = _w()
	w.set_paused(true)
	w.set_multiplier(360)
	var before = w.snapshot()
	w.advance_real_us(24000000)
	_same(before, w.snapshot(), "Paused input including new multiplier does not accumulate or progress")
	var r = _roundtrip(w)
	_check(r.state.paused and r.state.world_minute == 0, "Reload restores saved pause and time without offline input")
	current.limitations.append("Background/focus callbacks and UI return behavior verified separately in graphical runtime, not simulated by this headless API test.")

func _ac05() -> void:
	var w = _w()
	# Place people one minute before natural death using authoritative fixture values.
	for id in ["P1","P2"]:
		var natural = w.person_summary(id).natural_lifespan_days * 1440
		_check(w.fixture_change_person(id, {"birth_minute":1-natural}).ok, "Set directed natural-death boundary")
	w.fixture_schedule("breakthrough_complete", "P1", 1, {"realm":"炼气"})
	w.fixture_schedule("breakthrough_complete", "P2", 1, {"realm":"凡人"})
	var n3 = w.person_summary("P3").natural_lifespan_days * 1440
	w.fixture_change_person("P3", {"birth_minute":-n3})
	_check(not w.state.persons.P3.alive, "Earlier expired person is already dead")
	_check(not w.fixture_schedule("breakthrough_complete", "P3", 1, {"realm":"金丹"}).ok, "Dead history cannot start a breakthrough")
	w.advance_minutes(1)
	_check(w.state.persons.P1.alive and w.state.persons.P1.realm == "炼气", "Phase-one completion extends life before phase-two death")
	_check(not w.state.persons.P2.alive, "Completion with insufficient final lifespan still dies")
	_check(not w.state.persons.P3.alive, "Earlier dead actor is never revived")
	var types: Array = []
	for e in w.state.events:
		if e.world_minute == 1: types.append(e.type)
	_check(types.find("completed") >= 0 and types.find("completed") < types.find("died"), "Completion event precedes same-minute death event", types)

func _ac06() -> void:
	var w = _w()
	var birth = w.state.persons.P1.birth_minute
	w.fixture_change_person("P1", {"burn_days":3600,"realm":"炼气","root_scar":5,"g_trained":50})
	_check(w.person_summary("P1").root_effective == 45, "50 original root minus scar 5 is 45")
	w.fixture_change_person("P1", {"realm":"筑基","g_trained":100})
	_check(w.person_summary("P1").root_effective == 95 and w.person_summary("P1").root_cap == 95, "100 root and cap lose scar once, both 95")
	_check(w.state.persons.P1.burn_days == 3600 and w.state.persons.P1.birth_minute == birth, "Promotion retains permanent burn and birth time")
	w.fixture_change_person("P1", {"birth_minute":-90*YEAR})
	w.fixture_change_person("P1", {"realm":"凡人"})
	_check(not w.state.persons.P1.alive and w.state.persons.P1.burn_days == 3600 and w.person_summary("P1").age_years == 90, "Demotion immediately kills exhausted person without resetting age or burn")

func _ac07() -> void:
	var w = _w()
	for kind in ["duplicate_id","reference","realm","position"]:
		var data = w.snapshot()
		match kind:
			"duplicate_id": data.persons.P2.id = "P1"
			"reference": data.persons.P1.current_action = "A999"
			"realm": data.persons.P1.realm = "元婴"
			"position": data.persons.P1.position = [192,0]
		var before = w.snapshot()
		_check(not w.restore(data).ok, "Reject malformed " + kind)
		_same(before, w.snapshot(), "Malformed " + kind + " preserves active world")
	var id_counter = w.state.counters.person
	w.fixture_change_person("P1", {"birth_minute":-100*YEAR})
	_check(w.state.persons.has("P1") and w.state.counters.person == id_counter, "Death retains history ID without reusing it")
	_check(World.validate_snapshot(w.snapshot()).ok, "Death events may reference retained dead history")

func _ac08() -> void:
	var w = _w()
	var cmd = _command(w, "idempotent")
	var first = w.submit(cmd)
	var before = w.snapshot()
	_same(first, w.submit(cmd), "Exact resend returns exact recorded result")
	_same(before, w.snapshot(), "Exact resend creates no extra transaction/event or state mutation")
	cmd.payload.target = "different"
	var conflict = w.submit(cmd)
	_check(conflict.error_code == "command_id_conflict", "Same ID with changed payload conflicts", conflict)
	_same(before, w.snapshot(), "Conflict retains original record and all state")
	_check(w.state.events.size() == 1 and w.state.transactions.size() == 1, "One command produces exactly one atomic transaction/event")

func _ac09() -> void:
	var w = _w()
	var cases = [
		["denied", "set_target", {"person_id":"P1","target":"x"}, "天道", "permission_denied"],
		["bounds", "move", {"person_id":"P1","position":[192,0],"duration_minutes":1}, "NPC", "out_of_bounds"],
		["missing", "set_target", {"person_id":"P999","target":"x"}, "NPC", "invalid_entity"],
		["unknown", "force_breakthrough", {"person_id":"P1"}, "天道", "invalid_command"]]
	for item in cases:
		var before = w.snapshot()
		var result = w.submit(_command(w,item[0],item[1],item[2],item[3]))
		_check(result.error_code == item[4], "Readable specific rejection " + item[4], result)
		var after = w.snapshot()
		after.command_results = before.command_results
		_same(before, after, "Rejection alters only documented command audit, no business or RNG")
	var before = w.snapshot()
	_check(not w.fixture_transfer("P1","P2",101).ok, "Insufficient unreserved resources rejected")
	_same(before,w.snapshot(), "Resource rejection preserves both entities, events and RNG")

func _ac10() -> void:
	var w = _w()
	var before = w.snapshot()
	_check(not w.fixture_change_person("P1", {"burn_days":10}, true).ok, "Injected preparation failure reported")
	_same(before,w.snapshot(), "Preparation failure rolls back all truth and sequence counters")
	_check(not w.fixture_transfer("P1","P2",25,true).ok, "Injected exception after debit reported")
	_same(before,w.snapshot(), "Mid-transfer rollback restores two balances/events/transactions/counters exactly")
	_check(w.fixture_transfer("P1","P2",25).ok, "Successful fixture transfer commits")
	_check(w.state.persons.P1.wallet.balance == 75 and w.state.persons.P2.wallet.balance == 125, "Successful transfer conserves both balances")
	_check(w.state.events.size() == 1 and w.state.transactions.size() == 1 and w.state.counters.commit == 1, "Transfer and event commit once with one sequence")
	_check(World.validate_snapshot(w.snapshot()).ok, "Posttransaction snapshot is fully valid")

func _ac11() -> void:
	var w = _w()
	w.fixture_change_person("P1", {"burn_days":1})
	var cause = w.state.events[0].event_id
	w.fixture_schedule("reminder","P1",10,{"cause_event_ids":[cause]})
	w.fixture_schedule("reminder","P2",10,{})
	w.advance_minutes(10)
	var last = 0
	var ordered = true
	for e in w.state.events:
		ordered = ordered and e.commit_sequence > last
		last = e.commit_sequence
	_check(ordered,"Same-minute facts have strict stable commit order")
	_same(w.state.events[1].cause_event_ids,[cause],"Notification references its real prior cause")
	_same(w.state.events[2].cause_event_ids,[],"Independent fact has no invented cause")
	var before = w.snapshot()
	w.person_summary("P1")
	w.snapshot()
	_same(before,w.snapshot(),"Read-only queries do not teach NPCs or change world truth")
	_check(w.state.persons.P1.knowledge.is_empty() and w.state.persons.P2.knowledge.is_empty(),"World facts remain separate from NPC knowledge")

func _reminder_world():
	var w = _w()
	w.follow_person("P1")
	w.fixture_schedule("reminder","P1",100,{"notification_id":"notice100"})
	w.fixture_schedule("plan","P1",100,{"marker":"after_pause"})
	return w

func _ac12() -> void:
	var w = _reminder_world()
	w.set_multiplier(360)
	w.advance_real_us(24000000)
	_check(w.state.world_minute == 100 and w.state.paused, "Large fast-forward stops exactly at followed reminder minute", w.state.world_minute)
	_check(w.state.pending_minutes == 0 and w.state.discarded_minutes == YEAR-100, "Event pause explicitly discards remaining request budget", w.state.discarded_minutes)
	_check(w.state.persons.P1.paid_energy == 0, "Preparation reminder does not consume fixture energy")
	w.resume()
	w.advance_real_us(0)
	_check(w.state.world_minute == 100 and not w.state.paused, "Continue consumes only pending same-minute work without old fast-forward")
	_check(w.state.queue.is_empty(), "Remaining phase-eight work completes at original minute")

func _ac13() -> void:
	var w = _reminder_world()
	w.follow_person("P2")
	w.fixture_schedule("reminder","P2",100,{"notification_id":"notice_other"})
	w.advance_minutes(1000)
	_check(w.state.notifications.size() == 2 and w.state.paused,"Same-minute followed reminders aggregate as two facts before pausing")
	var before = w.snapshot()
	w.person_summary("P1")
	_same(before,w.snapshot(),"Viewing notification details cannot resume simulation")
	w.resume()
	_check(w.state.acknowledged.size() == 2,"Manual continue acknowledges entire presented batch")
	w.advance_minutes(0)
	w.fixture_schedule("reminder","P1",101,{"notification_id":"notice100"})
	w.advance_minutes(1)
	_check(not w.state.paused and w.state.notifications.size() == 2,"Redelivery of acknowledged notification does not repeat fact/pause")
	w.fixture_schedule("reminder","P1",102,{"notification_id":"new_attempt"})
	w.advance_minutes(1)
	_check(w.state.paused and w.state.notifications.size() == 3,"A new attempt creates a new notification and pauses")
	current.limitations.append("Closing the actual detail control is covered by AC23 GUI evidence; this test checks read-only detail query behavior.")

func _ac14() -> void:
	var a = _reminder_world()
	a.advance_minutes(1000)
	_check(a.state.phase_cursor.phase == 7 and a.state.queue.size() == 1,"Paused cursor retains unexecuted same-minute phase-eight item")
	var b = _roundtrip(a)
	var count = a.state.events.size()
	a.resume()
	b.resume()
	a.advance_minutes(0)
	b.advance_minutes(0)
	_same(a.snapshot(),b.snapshot(),"Restored cursor resumes exactly the same remaining work")
	_check(b.state.world_minute == 100 and b.state.events.size() == count+1,"Resume stays at original minute, emits only remaining event once")
	b.advance_minutes(0)
	_check(b.state.events.size() == count+1,"Second continuation does not replay committed facts")

func _ac15() -> void:
	var w = _w()
	_check(saves.save_slot(w,1,true).ok,"Create known valid baseline slot")
	var old = _read(save_dir.path_join("manual_1.json"))
	w.advance_minutes(20)
	var before = w.snapshot()
	for mode in ["write_denied","disk_full","truncated","replacerenamefail"]:
		saves.failure_mode = mode
		var result = saves.save_slot(w,1,true)
		_check(not result.ok,"Save reports explicit injected " + mode + " failure",result)
		_check(_read(save_dir.path_join("manual_1.json")) == old,"Old valid slot survives " + mode)
		_same(before,w.snapshot(),"Failed save preserves active world for " + mode)
		saves.failure_mode = ""
		var restored = _w()
		_check(saves.load_slot(restored,1,true).ok and restored.state.world_minute == 0,"Load selects valid old slot, never residual temp for " + mode)
	current.limitations.append("Permission and full-disk failures use deterministic I/O injection; no OS ACL or physical disk exhaustion is performed.")

func _ac16() -> void:
	var w = _w()
	w.state.seed = 9007199254740993
	w.state.rng_state = 9007199254740995
	w.state.counters.event = 9007199254740997
	w.state.numerator = 999999
	w.state.persons.P1.birth_minute = -9007199254740993
	w.state.persons.P1.wallet.balance = 9007199254740999
	var encoded = Codec.encode(w.snapshot())
	_check(encoded.ok,"Encode legal int64 fields beyond floating precision")
	_check(encoded.text.contains("9007199254740993") and encoded.text.contains('"9007199254740993"'),"Disk represents int64 as decimal strings")
	var decoded = Codec.decode(encoded.text)
	_check(decoded.ok,"Decode exact large and negative integers")
	if decoded.ok: _same(w.snapshot(),decoded.snapshot,"Large seed/state/count/birth/balance and fractional remainder roundtrip exactly")
	var overflow_text = encoded.text.replace('"9007199254740993"','"9223372036854775808"')
	_check(not Codec.decode(overflow_text).ok,"Out-of-range decimal integer is rejected rather than rounded")
	var a = _w()
	a.state.rng_state = 9007199254740995
	a.fixture_schedule("random_complete","P1",10,{})
	var b = _roundtrip(a)
	a.advance_minutes(10)
	b.advance_minutes(10)
	_same(a.snapshot(),b.snapshot(),"High random state yields identical actual next random outcome after disk restore")

func _ac17() -> void:
	var w = _w()
	var encoded = Codec.encode(w.snapshot())
	var parsed = JSON.parse_string(encoded.text)
	parsed.payload_digest = "bad"
	_write(save_dir.path_join("manual_3.json"),JSON.stringify(parsed))
	var before = w.snapshot()
	_check(not saves.load_slot(w,3,true).ok,"Digest mismatch rejects isolated load")
	_same(before,w.snapshot(),"Digest failure leaves active state and RNG unchanged")
	for kind in ["negative_balance","over_reserved","missing_entity","queue_reference"]:
		var data = w.snapshot()
		match kind:
			"negative_balance": data.persons.P1.wallet.balance = -1
			"over_reserved": data.persons.P1.wallet.reserved = 101
			"missing_entity": data.followed.append("P999")
			"queue_reference": data.queue.append({"due_minute":1,"phase":4,"stable_sequence":1,"action_id":"A999","kind":"move_complete","person_id":"P1","payload":{"position":[0,0]}}); data.counters.queue = 1
		_bad_load(w,data,kind)

func _ac18() -> void:
	var w = _w()
	for kind in ["format","rules","extension","action"]:
		var data = w.snapshot()
		match kind:
			"format": data.format_version = 999
			"rules": data.rules_version = "unknown"
			"extension": data.persons.P1.extensions["unregistered_v999"] = {"value":1}
			"action":
				w.fixture_schedule("action_complete","P1",10,{})
				data = w.snapshot()
				data.actions.A1.kind = "unregistered_action"
		_bad_load(w,data,"Unknown " + kind)
	_roundtrip(w)

func _ac19() -> void:
	var w = _w()
	for slot in [1,2,3]: _check(saves.save_slot(w,slot,true).ok,"Manual slot %d accepts save" % slot)
	var originals: Array = []
	for slot in [1,2,3]: originals.append(_read(save_dir.path_join("manual_%d.json" % slot)))
	w.advance_minutes(4*43200)
	_check(w.autosave_snapshots.size() == 4,"Crossing four 30-day boundaries creates four genuine snapshots")
	var times: Array = []
	for snapshot in w.autosave_snapshots: times.append(snapshot.world_minute)
	_same(times,[43200,86400,129600,172800],"Each autosave captures its actual boundary, not duplicate endpoint")
	var result = saves.drain_autosaves(w)
	_check(result.ok and result.saved == 4,"All four boundary snapshots written with rotation",result)
	var auto_times: Array = []
	for slot in [1,2,3]:
		var decoded = Codec.decode(_read(save_dir.path_join("auto_%d.json" % slot)))
		if decoded.ok: auto_times.append(decoded.snapshot.world_minute)
		_check(_read(save_dir.path_join("manual_%d.json" % slot)) == originals[slot-1],"Autosave never changes manual slot %d" % slot)
	auto_times.sort()
	_same(auto_times,[86400,129600,172800],"Automatic slots retain exactly the latest three distinct boundary dates")
	_check(not saves.save_slot(w,1,false).ok,"Cancelled/unconfirmed overwrite requires confirmation")
	_check(_read(save_dir.path_join("manual_1.json")) == originals[0],"Cancelled overwrite leaves file unchanged")
	var fresh = _w()
	_check(not saves.load_slot(fresh,1,false).ok,"Discard-unsaved confirmation required")
	_check(saves.load_slot(fresh,1,true).ok and fresh.state.world_minute == 0,"Unsaved simulated progress is absent when reopening old manual slot")

func _rich_world():
	var w = _w()
	w.fixture_change_person("P1", {"burn_days":100,"paid_energy":17,"daily_budget":40,"daily_used":13,"cultivation_progress":12345,
		"root_scar":5,"root_wound":2,"wallet":{"balance":100,"reserved":30},
		"extensions":{"future_state_v1":{"polishing_history":[3,5,8],"day_accumulator":19,"energy_remainder":7}}})
	w.fixture_schedule("move_complete","P1",30,{"position":[11,12]})
	w.fixture_schedule("action_complete","P2",40,{})
	w.fixture_schedule("random_complete","P3",50,{})
	return w

func _ac20() -> void:
	var a = _rich_world()
	var b = _roundtrip(a)
	for minute in [10,29,30,39,40,49,50,60]:
		a.advance_minutes(minute-a.state.world_minute)
		b.advance_minutes(minute-b.state.world_minute)
		b = _roundtrip(b)
		_same(a.snapshot(),b.snapshot(),"Continuous and reloaded complete state agree at minute %d" % minute)
	_check(b.state.persons.P1.wallet.reserved == 30 and b.state.persons.P1.paid_energy == 17 and b.state.persons.P1.burn_days == 100,"Reservation, paid energy and permanent burn do not clear or double")
	_check(b.state.persons.P1.daily_used == 13 and b.state.persons.P1.extensions.future_state_v1.polishing_history == [3,5,8],"Daily partial state and polishing history survive every phase checkpoint")

func _ac21() -> void:
	var a = _w()
	var cmd = _command(a,"random_idempotence")
	a.submit(cmd)
	a.fixture_schedule("random_complete","P1",10,{})
	var b = _roundtrip(a)
	var before_rng = b.state.rng_state
	var rejected = b.submit(_command(b,"random_reject","move",{"person_id":"P1","position":[192,0],"duration_minutes":1}))
	_check(rejected.status == "rejected" and b.state.rng_state == before_rng,"Rejected command consumes no random draw")
	# The rejection audit is an explicitly documented difference and is applied to both branches.
	a.submit(_command(a,"random_reject","move",{"person_id":"P1","position":[192,0],"duration_minutes":1}))
	a.advance_minutes(10)
	b.advance_minutes(10)
	var snap = b.snapshot()
	b.submit(cmd)
	_same(snap,b.snapshot(),"Replayed applied command does not draw or emit another outcome")
	_same(a.snapshot(),b.snapshot(),"First actual random completion agrees after reload/rejection/resend")
	for person in ["P1","P2","P3"]:
		a.fixture_schedule("random_complete",person,a.state.world_minute+1,{})
		b.fixture_schedule("random_complete",person,b.state.world_minute+1,{})
		a.advance_minutes(1)
		b.advance_minutes(1)
	_same(a.snapshot(),b.snapshot(),"Three future random outcomes and final RNG state match exactly")

func _ac22() -> void:
	var w = _rich_world()
	w.state.rules.candidate["future_formula_inputs"] = {"coefficient_numerator":123,"denominator":10000,"candidate_only":true}
	var r = _roundtrip(w)
	_check(r.state.rules.candidate.status == "candidate" and r.state.rules.candidate.version == "breakthrough-candidate.2" and not r.state.rules.candidate.enabled,"Candidate version/status remain explicit and disabled")
	_same(w.person_summary("P1"),r.person_summary("P1"),"Derived summary and registered future fields roundtrip without exclusions")
	_check(r.state.persons.P1.extensions.future_state_v1.energy_remainder == 7,"Registered future remainder preserved")

func _ac23() -> void:
	current.limitations.append("EXTERNAL: real graphical startup, control actions, screen capture and process evidence are owned by the main agent; no headless pass is claimed.")

func _ac24() -> void:
	current.limitations.append("EXTERNAL: execute tests/benchmark.gd and inspect evidence/benchmark.json; this acceptance runner does not invent measurements.")

func _end_e() -> void:
	current.status = "PASS"
	for assertion in current.assertions:
		if not assertion.passed: current.status = "FAIL"
	rows.append(current)
	print(current.scenario_id," ",current.status)

func _e01() -> void:
	current = {"scenario_id":"E01","status":"NOT_RUN","assertions":[],"limitations":[]}
	var w = _w()
	var cmd = _command(w,"M1")
	var first = w.submit(cmd)
	w.advance_minutes(10*1440)
	w.set_paused(true)
	w.set_multiplier(360)
	w.advance_real_us(24000000)
	_check(w.state.world_minute == 14400,"Pause and switch rate preserve day-ten time")
	w.resume()
	var before = w.snapshot()
	_same(first,w.submit(cmd),"Resending M1 returns its recorded result")
	w.person_summary("P1")
	_same(before,w.snapshot(),"M1 resend and query leave complete authority unchanged")
	_check(w.state.events.size() == 1 and w.state.persons.P1.target == "observe","M1 applies exactly once after day-ten continuation")
	_end_e()

func _child(directory: String) -> void:
	var store = Store.new()
	store.initialize(directory)
	var w = _w()
	OS.delay_msec(100)
	var result = store.load_slot(w,2,true)
	_write(directory.path_join("child_loaded.json"),JSON.stringify(Codec.encode(w.snapshot())))
	if result.ok:
		w.resume()
		w.advance_minutes(0)
		_write(directory.path_join("child_continued.json"),Codec.encode(w.snapshot()).text)
	quit(0 if result.ok else 1)

func _e02() -> void:
	current = {"scenario_id":"E02","status":"NOT_RUN","assertions":[],"limitations":[]}
	var w = _reminder_world()
	w.set_multiplier(360)
	w.advance_real_us(24000000)
	_check(saves.save_slot(w,2,true).ok,"Save event-paused world before process restart")
	var output: Array = []
	var code = OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",save_dir.path_join("child.log"),"--script","res://tests/test_acceptance.gd","--","--continuation-child",save_dir]),output,true)
	_check(code == 0,"Fresh Godot child process loads after a real closed-world delay",{"exit_code":code,"output":output})
	var loaded_outer = JSON.parse_string(_read(save_dir.path_join("child_loaded.json")))
	if loaded_outer is Dictionary and loaded_outer.get("ok",false):
		var decoded = Codec.decode(loaded_outer.text)
		_check(decoded.ok,"Child snapshot is valid")
		if decoded.ok: _same(w.snapshot(),decoded.snapshot,"Reopened process keeps exact saved time, pause, queue, RNG and notification")
	else: _check(false,"Child writes loaded-state evidence",loaded_outer)
	w.resume()
	w.advance_minutes(0)
	var continued = Codec.decode(_read(save_dir.path_join("child_continued.json")))
	_check(continued.ok,"Child writes postresume state")
	if continued.ok: _same(w.snapshot(),continued.snapshot,"Fresh-process manual continuation executes only uncommitted same-minute work")
	_end_e()

func _e03() -> void:
	current = {"scenario_id":"E03","status":"NOT_RUN","assertions":[],"limitations":[]}
	var a = _rich_world()
	var b = _rich_world()
	for w in [a,b]:
		w.follow_person("P2")
		w.fixture_schedule("reminder","P2",35,{"notification_id":"e03_pending"})
	for target in [15,30,35,40,50,65]:
		a.advance_minutes(target-a.state.world_minute)
		b.advance_minutes(target-b.state.world_minute)
		b = _roundtrip(b)
		_same(a.snapshot(),b.snapshot(),"Continuous and restored authority agree at checkpoint %d including pause/queue/random/events/dedupe" % target)
		if a.state.paused:
			a.resume()
			b.resume()
		var cmd = _command(a,"E03_%d" % target)
		a.submit(cmd)
		b.submit(cmd)
	for w in [a,b]:
		w.fixture_schedule("random_complete","P1",66,{})
		w.advance_minutes(1)
	_same(a.snapshot(),b.snapshot(),"Final full canonical state and future random result agree; exclusion whitelist is empty")
	_end_e()
