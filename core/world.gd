extends RefCounted
## All future-affecting truth is in state. Fixture permissions and drained autosave
## outputs are runtime capabilities, never restored from an untrusted save.
const Rules = preload("res://core/rules.gd")
const MAX_INT = 9223372036854775807
var state: Dictionary = {}
var fixture_enabled: bool = false
var autosave_snapshots: Array[Dictionary] = []

func initialize(seed_value: int = 20261029, count: int = 96) -> void:
	fixture_enabled = false
	autosave_snapshots.clear()
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	state = {"format_version":1,"rules_version":Rules.VERSION,"build_id":"s1-build.1","candidate_config_status":"candidate","world_minute":0,"numerator":0,"pending_minutes":0,"multiplier":1,"paused":false,"seed":seed_value,"rng_state":rng.state,"map_size":[192,192],"persons":{},"actions":{},"queue":[],"events":[],"transactions":[],"command_results":{},"pending_commands":[],"notifications":[],"acknowledged":[],"followed":[],"rules":Rules.config(),"counters":{"person":0,"action":0,"queue":0,"event":0,"transaction":0,"command":0,"notification":0,"commit":0},"phase_cursor":{"minute":0,"phase":9,"last_sequence":0},"next_autosave_minute":43200,"pause_reason":{},"discarded_minutes":0}
	for i in range(clampi(count,0,10000)):
		var id = _id("person","P")
		var p = {"id":id,"name":"人物%d" % (i+1),"birth_minute":-rng.randi_range(18,40)*Rules.YEAR,"realm":"凡人","alive":true,"position":[rng.randi_range(0,191),rng.randi_range(0,191)],"origin":"fixed_seed_fixture","talent":rng.randi_range(1,100),"insight":rng.randi_range(1,100),"root_type":"fixture","lifespan_quantile":rng.randi_range(0,10000),"burn_days":0,"g_trained":50,"root_wound":0,"root_scar":0,"cultivation_progress":0,"daily_budget":0,"daily_used":0,"sleep_minutes":0,"meditation_minutes":0,"injury":0,"paid_energy":0,"current_action":"","target":"","family_id":"","organization_id":"","inventory":{},"wallet":{"balance":100,"reserved":0},"knowledge":[],"extensions":{"future_state_v1":{"polishing_history":[],"day_accumulator":0,"energy_remainder":0}}}
		state.persons[id] = p
	state.rng_state = rng.state

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(candidate: Dictionary) -> Dictionary:
	var validation = validate_snapshot(candidate)
	if not validation.ok:
		return validation
	state = candidate.duplicate(true)
	autosave_snapshots.clear()
	return {"ok":true,"error":""}

static func _bad(error: String) -> Dictionary:
	return {"ok":false,"error":error}

static func _plain(value: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	if value is Dictionary:
		for key in value:
			if not key is String or not _plain(value[key],depth+1): return false
		return true
	if value is Array:
		for element in value:
			if not _plain(element,depth+1): return false
		return true
	return value == null or value is String or value is int or value is bool

static func _position(v: Variant) -> bool:
	return v is Array and v.size()==2 and v[0] is int and v[1] is int and v[0]>=0 and v[0]<192 and v[1]>=0 and v[1]<192

static func _payload_valid(kind: String, payload: Dictionary) -> bool:
	if kind=="breakthrough_complete": return payload.get("realm") in Rules.REALMS
	if kind=="move_complete": return _position(payload.get("position"))
	if kind=="reminder":
		if payload.has("reason") and not payload.reason is String: return false
		if payload.has("notification_id") and (not payload.notification_id is String or payload.notification_id==""): return false
		if payload.has("cause_event_ids"):
			if not payload.cause_event_ids is Array: return false
			for cause in payload.cause_event_ids:
				if not cause is String: return false
	if kind=="command":
		var c=payload.get("command")
		if not c is Dictionary or not c.has_all(["command_id","issuer","issued_at","execute_at","type","payload"]): return false
		if not c.command_id is String or c.command_id=="" or not c.issuer in ["天道","NPC","系统"] or not c.issued_at is int or not c.execute_at is int or not c.payload is Dictionary: return false
		if not c.type in ["watch","unwatch","set_target","move"]: return false
		if not c.payload.get("person_id") is String: return false
		if c.type in ["move","set_target"] and c.issuer!="NPC": return false
		if c.type=="move" and (not _position(c.payload.get("position")) or not c.payload.get("duration_minutes") is int or c.payload.duration_minutes<=0): return false
		if c.type=="set_target" and not c.payload.get("target") is String: return false
	return true

static func validate_snapshot(data: Dictionary) -> Dictionary:
	if not _plain(data): return _bad("incompatible_save: nonprimitive or excessive nesting")
	var needed = ["format_version","rules_version","build_id","candidate_config_status","world_minute","numerator","pending_minutes","multiplier","paused","seed","rng_state","map_size","persons","actions","queue","events","transactions","command_results","pending_commands","notifications","acknowledged","followed","rules","counters","phase_cursor","next_autosave_minute","pause_reason","discarded_minutes"]
	for key in needed:
		if not data.has(key): return _bad("incompatible_save: missing " + key)
	if not data.format_version is int or data.format_version != 1 or data.rules_version != Rules.VERSION or data.candidate_config_status != "candidate" or not data.build_id is String: return _bad("incompatible_save: version")
	for key in ["world_minute","numerator","pending_minutes","multiplier","seed","rng_state","next_autosave_minute","discarded_minutes"]:
		if not data[key] is int: return _bad("invalid_time: integer " + key)
	if data.world_minute<0 or data.pending_minutes<0 or data.numerator<0 or data.numerator>=1000000 or data.next_autosave_minute<=data.world_minute or not data.multiplier in Rules.MULTIPLIERS: return _bad("invalid_time")
	if not data.paused is bool or data.map_size != [192,192]: return _bad("incompatible_save: world shape")
	for key in ["persons","actions","rules","command_results","counters","phase_cursor","pause_reason"]:
		if not data[key] is Dictionary: return _bad("incompatible_save: dictionary " + key)
	for key in ["queue","events","transactions","pending_commands","notifications","acknowledged","followed"]:
		if not data[key] is Array: return _bad("incompatible_save: array " + key)
	if not data.rules.has_all(["version","lifespan_years","root_cap","candidate","calendar"]) or data.rules.version != Rules.VERSION or not data.rules.candidate is Dictionary or data.rules.candidate.get("status")!="candidate" or not data.rules.lifespan_years is Dictionary: return _bad("incompatible_save: rules")
	if data.rules.calendar!={"days_per_month":30,"months_per_year":12,"minutes_per_day":1440}: return _bad("incompatible_save: calendar")
	for realm in Rules.REALMS:
		if not data.rules.lifespan_years.has(realm): return _bad("incompatible_save: lifespan table")
		var span = data.rules.lifespan_years[realm]
		if not span is Array or span.size()!=2 or not span[0] is int or not span[1] is int or span[0]<1 or span[1]<span[0] or span[1]>100000: return _bad("incompatible_save: lifespan range")
	if not data.rules.root_cap is int or data.rules.root_cap<0 or data.rules.root_cap>10000: return _bad("incompatible_save: root cap")
	for key in ["person","action","queue","event","transaction","command","notification","commit"]:
		if not data.counters.has(key) or not data.counters[key] is int or data.counters[key]<0: return _bad("incompatible_save: counter " + key)
	for id in data.persons:
		var p = data.persons[id]
		if not p is Dictionary or not p.has_all(["id","name","birth_minute","realm","alive","position","origin","talent","insight","root_type","lifespan_quantile","burn_days","g_trained","root_wound","root_scar","cultivation_progress","daily_budget","daily_used","sleep_minutes","meditation_minutes","injury","paid_energy","current_action","target","family_id","organization_id","inventory","wallet","knowledge","extensions"]): return _bad("invalid_entity: missing person fields")
		if p.id!=id or not id.begins_with("P") or not id.substr(1).is_valid_int() or int(id.substr(1))<=0 or int(id.substr(1))>data.counters.person: return _bad("invalid_entity: person id")
		if not p.realm in Rules.REALMS: return _bad("invalid_realm")
		for field in ["id","name","realm","origin","root_type","current_action","target","family_id","organization_id"]:
			if not p[field] is String: return _bad("invalid_entity: string " + field)
		for field in ["talent","insight"]:
			if not p[field] is int or p[field]<0 or p[field]>100: return _bad("invalid_entity: trait " + field)
		if not _position(p.position): return _bad("out_of_bounds")
		if not p.alive is bool or not p.birth_minute is int or p.birth_minute>data.world_minute or p.birth_minute < -MAX_INT + data.world_minute: return _bad("invalid_time: birth")
		for field in ["lifespan_quantile","burn_days","g_trained","root_wound","root_scar","cultivation_progress","daily_budget","daily_used","sleep_minutes","meditation_minutes","injury","paid_energy"]:
			if not p[field] is int or p[field]<0: return _bad("invalid_entity: " + field)
		if p.lifespan_quantile>10000 or p.burn_days>int(MAX_INT/1440) or p.g_trained>100 or p.root_scar>99 or p.root_wound>100 or p.daily_used>p.daily_budget: return _bad("invalid_entity: lifespan/root/budget")
		var life_minutes: int=(Rules.natural_days(p,data.rules)-p.burn_days)*Rules.DAY
		if life_minutes<0 and data.world_minute-p.birth_minute>MAX_INT+life_minutes: return _bad("invalid_time: lifespan underflow")
		if not p.wallet is Dictionary or not p.wallet.has_all(["balance","reserved"]) or not p.wallet.balance is int or not p.wallet.reserved is int or p.wallet.balance<0 or p.wallet.reserved<0 or p.wallet.reserved>p.wallet.balance: return _bad("invalid_entity: wallet")
		if not p.extensions is Dictionary or not p.inventory is Dictionary or not p.knowledge is Array: return _bad("incompatible_save: person containers")
		for quantity in p.inventory.values():
			if not quantity is int or quantity<0: return _bad("invalid_entity: inventory")
		for extension in p.extensions:
			if extension!="future_state_v1" or not p.extensions[extension] is Dictionary: return _bad("incompatible_save: unknown extension " + extension)
			var ex:Dictionary=p.extensions[extension]
			if not ex.has_all(["polishing_history","day_accumulator","energy_remainder"]) or not ex.polishing_history is Array or not ex.day_accumulator is int or not ex.energy_remainder is int or ex.day_accumulator<0 or ex.energy_remainder<0: return _bad("incompatible_save: future extension fields")
		for known in p.knowledge:
			if not known is String: return _bad("invalid_entity: knowledge")
		if p.family_id!="" or p.organization_id!="": return _bad("invalid_entity: unregistered family or organization")
		if p.current_action!="" and not data.actions.has(p.current_action): return _bad("invalid_entity: action reference")
		if p.current_action!="" and (not data.actions[p.current_action] is Dictionary or data.actions[p.current_action].get("person_id")!=id or data.actions[p.current_action].get("status") in ["completed","cancelled","failed"]): return _bad("invalid_entity: current action owner/state")
		if not p.alive and p.current_action!="": return _bad("invalid_state_transition: dead active actor")
	for id in data.actions:
		var a = data.actions[id]
		if not a is Dictionary or not a.has_all(["id","person_id","kind","status","started_at","due_minute","payload","fixture"]): return _bad("incompatible_save: action fields")
		if a.id!=id or not id.begins_with("A") or not id.substr(1).is_valid_int() or int(id.substr(1))<=0 or int(id.substr(1))>data.counters.action or not data.persons.has(a.person_id): return _bad("invalid_entity: action id/reference")
		if not Rules.PHASES.has(a.kind): return _bad("incompatible_save: unknown action type")
		if not a.status in Rules.ACTION_STATES or not a.started_at is int or not a.due_minute is int or a.started_at<0 or a.started_at>data.world_minute or a.due_minute<=a.started_at: return _bad("invalid_state_transition: action time/state")
		if not a.payload is Dictionary or not a.fixture is bool: return _bad("incompatible_save: action payload")
		if not a.kind in ["breakthrough_complete","move_complete","action_complete","random_complete"] or not _payload_valid(a.kind,a.payload): return _bad("incompatible_save: invalid action payload")
		if not a.status in ["completed","cancelled","failed"] and data.persons[a.person_id].current_action!=id: return _bad("invalid_entity: active action owner")
	var seqs = {}
	var queue_actions = {}
	var queue_commands = {}
	for q in data.queue:
		if not q is Dictionary or not q.has_all(["due_minute","phase","stable_sequence","action_id","kind","person_id","payload"]): return _bad("incompatible_save: queue fields")
		if not Rules.PHASES.has(q.kind) or q.phase!=Rules.PHASES[q.kind]: return _bad("incompatible_save: unknown queue type")
		if not q.due_minute is int or q.due_minute<data.world_minute or not q.stable_sequence is int or q.stable_sequence<=0 or q.stable_sequence>data.counters.queue or seqs.has(q.stable_sequence): return _bad("invalid_time: queue")
		seqs[q.stable_sequence]=true
		if q.person_id!="" and not data.persons.has(q.person_id): return _bad("invalid_entity: queue person")
		if q.action_id!="" and not data.actions.has(q.action_id): return _bad("invalid_entity: queue action")
		if not q.payload is Dictionary: return _bad("incompatible_save: queue payload")
		if not _payload_valid(q.kind,q.payload): return _bad("incompatible_save: invalid queue payload")
		if q.action_id!="" and (data.actions[q.action_id].person_id!=q.person_id or data.actions[q.action_id].due_minute!=q.due_minute or data.actions[q.action_id].kind!=q.kind): return _bad("invalid_entity: queue/action mismatch")
		if q.kind in ["breakthrough_complete","move_complete","action_complete","random_complete"] and q.action_id=="": return _bad("invalid_entity: action required")
		if q.action_id!="" and q.payload!=data.actions[q.action_id].payload: return _bad("invalid_entity: action payload mismatch")
		if q.action_id!="":
			if queue_actions.has(q.action_id): return _bad("invalid_entity: duplicate action queue")
			queue_actions[q.action_id]=true
		if q.kind=="command" and not q.payload.has("command"): return _bad("incompatible_save: queued command")
		if q.kind=="command":
			var c:Dictionary=q.payload.command
			if c.execute_at!=q.due_minute or c.issued_at<0 or c.issued_at>data.world_minute or c.payload.person_id!=q.person_id or not data.command_results.has(c.command_id) or queue_commands.has(c.command_id): return _bad("invalid_entity: queued command reference")
			queue_commands[c.command_id]=c
	for id in data.actions:
		var a = data.actions[id]
		if a.status in ["completed","cancelled","failed"]: continue
		var found = false
		for q in data.queue:
			if q.action_id==id: found=true
		if not found: return _bad("invalid_entity: missing action queue")
	for id in data.followed:
		if not data.persons.has(id): return _bad("invalid_entity: followed")
	var pending_ids={}
	for c in data.pending_commands:
		if not c is Dictionary or not _payload_valid("command",{"command":c}): return _bad("incompatible_save: pending command")
		if pending_ids.has(c.command_id) or not queue_commands.has(c.command_id) or queue_commands[c.command_id]!=c: return _bad("invalid_entity: pending command reference")
		pending_ids[c.command_id]=true
	if pending_ids.size()!=queue_commands.size(): return _bad("invalid_entity: missing pending command")
	var event_ids = {}
	var commits = {}
	var last_commit = 0
	for tx in data.transactions:
		if not tx is Dictionary or not tx.has_all(["transaction_id","commit_sequence","world_minute","event_ids"]): return _bad("incompatible_save: transaction")
		if not tx.transaction_id is String or not tx.event_ids is Array or not tx.world_minute is int or tx.world_minute<0 or commits.has(tx.transaction_id) or not tx.commit_sequence is int or tx.commit_sequence<=last_commit or tx.commit_sequence>data.counters.commit or tx.world_minute>data.world_minute: return _bad("invalid_entity: transaction sequence")
		if not tx.transaction_id.begins_with("T") or not tx.transaction_id.substr(1).is_valid_int() or int(tx.transaction_id.substr(1))<=0 or int(tx.transaction_id.substr(1))>data.counters.transaction: return _bad("invalid_entity: transaction id")
		commits[tx.transaction_id]=true
		last_commit=tx.commit_sequence
	for e in data.events:
		if not e is Dictionary or not e.has_all(["event_id","commit_sequence","world_minute","type","actor_ids","location","source_action_id","cause_event_ids","result","visibility","source"]): return _bad("incompatible_save: event")
		if not e.event_id is String or not e.type is String or not e.actor_ids is Array or not e.cause_event_ids is Array or not e.result is Dictionary or not e.visibility is String or not e.source is String or not e.source_action_id is String or not e.world_minute is int or e.world_minute<0 or not _position(e.location): return _bad("incompatible_save: event fields")
		if not e.event_id.begins_with("E") or not e.event_id.substr(1).is_valid_int() or int(e.event_id.substr(1))<=0 or int(e.event_id.substr(1))>data.counters.event: return _bad("invalid_entity: event id")
		if event_ids.has(e.event_id) or not e.commit_sequence is int or e.commit_sequence<=0 or e.commit_sequence>data.counters.commit or e.world_minute>data.world_minute: return _bad("invalid_entity: event sequence")
		for actor in e.actor_ids:
			if not data.persons.has(actor): return _bad("invalid_entity: event actor")
		for cause in e.cause_event_ids:
			if not event_ids.has(cause): return _bad("invalid_entity: cause")
		if e.source_action_id!="" and not data.actions.has(e.source_action_id): return _bad("invalid_entity: event action")
		event_ids[e.event_id]=true
	for tx in data.transactions:
		for eid in tx.event_ids:
			if not event_ids.has(eid): return _bad("invalid_entity: transaction event")
	for q in data.queue:
		for cause in q.payload.get("cause_event_ids",[]):
			if not event_ids.has(cause): return _bad("invalid_entity: queue cause")
	var notification_ids = {}
	for n in data.notifications:
		if not n is Dictionary or not n.has_all(["notification_id","person_id","event_id","reason","world_minute"]): return _bad("incompatible_save: notification")
		if not n.notification_id is String or n.notification_id=="" or not n.reason is String or not n.world_minute is int or n.world_minute<0 or n.world_minute>data.world_minute: return _bad("incompatible_save: notification fields")
		if notification_ids.has(n.notification_id) or not data.persons.has(n.person_id) or not event_ids.has(n.event_id): return _bad("invalid_entity: notification")
		notification_ids[n.notification_id]=true
	var ack = {}
	for id in data.acknowledged:
		if ack.has(id) or not notification_ids.has(id): return _bad("invalid_entity: acknowledgement")
		ack[id]=true
	for id in data.command_results:
		var record=data.command_results[id]
		if not record is Dictionary or not record.has_all(["fingerprint","result"]) or not record.fingerprint is String or not record.result is Dictionary or record.result.get("command_id")!=id: return _bad("incompatible_save: command record")
		var r:Dictionary=record.result
		if not r.has_all(["status","error_code","transaction_id","event_ids","applied_at"]) or not r.status in ["queued","applied","rejected"] or not r.error_code is String or not r.transaction_id is String or not r.event_ids is Array or not r.applied_at is int or r.applied_at<0 or r.applied_at>data.world_minute: return _bad("incompatible_save: command result")
		if (r.status=="queued")!=pending_ids.has(id): return _bad("invalid_entity: queued command result")
		if r.transaction_id!="" and not commits.has(r.transaction_id): return _bad("invalid_entity: command transaction")
		for eid in r.event_ids:
			if not event_ids.has(eid): return _bad("invalid_entity: command event")
	if not data.phase_cursor.has_all(["minute","phase","last_sequence"]) or not data.phase_cursor.minute is int or data.phase_cursor.minute!=data.world_minute or not data.phase_cursor.phase is int or data.phase_cursor.phase<0 or data.phase_cursor.phase>9 or not data.phase_cursor.last_sequence is int or data.phase_cursor.last_sequence<0 or data.phase_cursor.last_sequence>data.counters.queue: return _bad("invalid_time: phase cursor")
	for q in data.queue:
		if q.due_minute==data.world_minute and q.phase<data.phase_cursor.phase: return _bad("invalid_time: phase cursor skips queued work")
	return {"ok":true,"error":""}

func _id(counter: String, prefix: String) -> String:
	state.counters[counter] += 1
	return prefix + str(state.counters[counter])

static func canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys = value.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for key in keys: parts.append(JSON.stringify(str(key))+":"+canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: PackedStringArray = []
		for item in value: parts.append(canonical(item))
		return "["+",".join(parts)+"]"
	return str(value) if value is int else JSON.stringify(value)

func date_parts() -> Dictionary:
	var t: int = state.world_minute
	return {"year":int(t/Rules.YEAR)+1,"month":int((t%Rules.YEAR)/43200)+1,"day":int((t%43200)/1440)+1,"hour":int((t%1440)/60),"minute":t%60}

func person_summary(id: String) -> Dictionary:
	if not state.persons.has(id): return {}
	var p: Dictionary = state.persons[id].duplicate(true)
	p.merge(Rules.derived(p,state.world_minute,state.rules))
	return p

func set_paused(value: bool) -> void:
	state.paused=value
	if value: state.pause_reason={"type":"manual"}

func set_multiplier(value: int) -> Dictionary:
	if not value in Rules.MULTIPLIERS: return _bad("invalid_multiplier")
	state.multiplier=value
	return {"ok":true,"error":""}

func resume() -> Dictionary:
	for n in state.notifications:
		if not n.notification_id in state.acknowledged: state.acknowledged.append(n.notification_id)
	state.paused=false
	state.pause_reason={}
	return {"ok":true,"error":""}

func single_step(minutes: int = 1) -> Dictionary:
	if minutes<0: return _bad("invalid_time")
	if _unacknowledged_followed(): return _bad("notification_requires_resume")
	state.paused=false
	var result=advance_minutes(minutes)
	if not state.paused: set_paused(true)
	result.paused=state.paused
	return result

func follow_person(id: String, value: bool = true) -> Dictionary:
	if not state.persons.has(id): return _bad("invalid_entity")
	if value and not id in state.followed: state.followed.append(id)
	if not value: state.followed.erase(id)
	return {"ok":true,"error":""}

func _enqueue(kind: String, person_id: String, due: int, payload: Dictionary, action_id: String = "") -> void:
	state.counters.queue+=1
	state.queue.append({"due_minute":due,"phase":Rules.PHASES[kind],"stable_sequence":state.counters.queue,"action_id":action_id,"kind":kind,"person_id":person_id,"payload":payload.duplicate(true)})
	if due==state.world_minute: state.phase_cursor.phase=mini(state.phase_cursor.phase,Rules.PHASES[kind])
	_sort_queue()

func _sort_queue() -> void:
	state.queue.sort_custom(func(a,b):
		if a.due_minute!=b.due_minute: return a.due_minute<b.due_minute
		if a.phase!=b.phase: return a.phase<b.phase
		return a.stable_sequence<b.stable_sequence)

func _event(kind: String, actors: Array, result: Dictionary, action_id: String = "", causes: Array = [], source: String = "system") -> Dictionary:
	state.counters.commit+=1
	var tid = _id("transaction","T")
	var eid = _id("event","E")
	var location: Array = state.persons[actors[0]].position.duplicate() if not actors.is_empty() else [0,0]
	var e = {"event_id":eid,"commit_sequence":state.counters.commit,"world_minute":state.world_minute,"type":kind,"actor_ids":actors.duplicate(),"location":location,"source_action_id":action_id,"cause_event_ids":causes.duplicate(),"result":result.duplicate(true),"visibility":"天道","source":source}
	state.events.append(e)
	state.transactions.append({"transaction_id":tid,"commit_sequence":state.counters.commit,"world_minute":state.world_minute,"event_ids":[eid]})
	return {"transaction_id":tid,"event_ids":[eid],"event_id":eid}

func fixture_schedule(kind: String, person_id: String, due: int, payload: Dictionary = {}) -> Dictionary:
	if not fixture_enabled: return _bad("permission_denied: test fixture disabled")
	if not Rules.PHASES.has(kind) or kind in ["command","death_check"]: return _bad("invalid_command")
	if not state.persons.has(person_id): return _bad("invalid_entity")
	if not state.persons[person_id].alive: return _bad("dead_actor")
	if due<=state.world_minute: return _bad("invalid_time")
	if not _plain(payload): return _bad("invalid_command")
	if not _payload_valid(kind,payload): return _bad("invalid_command: fixture payload")
	for cause in payload.get("cause_event_ids",[]):
		var found=false
		for event in state.events:
			if event.event_id==cause: found=true
		if not found: return _bad("invalid_entity: cause event")
	if kind=="breakthrough_complete" and not payload.get("realm","") in Rules.REALMS: return _bad("invalid_realm")
	if kind=="move_complete" and not _position(payload.get("position")): return _bad("out_of_bounds")
	var aid=""
	if kind in ["breakthrough_complete","move_complete","action_complete","random_complete"]:
		if state.persons[person_id].current_action!="": return _bad("invalid_state_transition")
		aid=_id("action","A")
		state.actions[aid]={"id":aid,"person_id":person_id,"kind":kind,"status":"travelling" if kind=="move_complete" else "executing","started_at":state.world_minute,"due_minute":due,"payload":payload.duplicate(true),"fixture":true}
		state.persons[person_id].current_action=aid
		_event("action_started",[person_id],{"fixture":true,"kind":kind},aid,[],"fixture")
	_enqueue(kind,person_id,due,payload,aid)
	return {"ok":true,"error":"","action_id":aid}

func fixture_change_person(id: String, changes: Dictionary, inject_failure: bool = false) -> Dictionary:
	if not fixture_enabled: return _bad("permission_denied")
	if not state.persons.has(id): return _bad("invalid_entity")
	if not state.persons[id].alive: return _bad("dead_actor")
	var candidate=snapshot()
	for field in changes:
		if not field in ["birth_minute","realm","burn_days","g_trained","root_wound","root_scar","position","wallet","paid_energy","daily_budget","daily_used","cultivation_progress","extensions","sleep_minutes","meditation_minutes","injury"]: return _bad("permission_denied: fixture field")
		candidate.persons[id][field]=changes[field]
	var check=validate_snapshot(candidate)
	if not check.ok: return check
	if inject_failure: return _bad("fixture_injected_failure")
	state=candidate
	_event("lifespan_burned" if changes.has("burn_days") else "state_changed",[id],{"fixture":true,"changes":changes},"",[],"fixture")
	_check_deaths()
	return {"ok":true,"error":""}

func fixture_transfer(from_id: String, to_id: String, amount: int, inject_failure: bool = false) -> Dictionary:
	if not fixture_enabled: return _bad("permission_denied")
	if not state.persons.has(from_id) or not state.persons.has(to_id): return _bad("invalid_entity")
	if not state.persons[from_id].alive or not state.persons[to_id].alive: return _bad("dead_actor")
	if from_id==to_id or amount<=0 or state.persons[from_id].wallet.balance-state.persons[from_id].wallet.reserved<amount or state.persons[to_id].wallet.balance>MAX_INT-amount: return _bad("insufficient_resources")
	var before=snapshot()
	state.persons[from_id].wallet.balance-=amount
	if inject_failure:
		state=before
		return _bad("fixture_injected_failure")
	state.persons[to_id].wallet.balance+=amount
	_event("fixture_transfer",[from_id,to_id],{"amount":amount,"fixture":true},"",[],"fixture")
	return {"ok":true,"error":""}

func _command_result(id: String, status: String, code: String = "", tx: Dictionary = {}) -> Dictionary:
	return {"command_id":id,"status":status,"error_code":code,"transaction_id":tx.get("transaction_id",""),"event_ids":tx.get("event_ids",[]),"applied_at":state.world_minute}

func submit(command: Dictionary) -> Dictionary:
	var id = str(command.get("command_id",""))
	var content=command.duplicate(true)
	content.erase("payload_fingerprint")
	var fingerprint=canonical(content).sha256_text()
	if state.command_results.has(id):
		var record: Dictionary=state.command_results[id]
		return record.result.duplicate(true) if record.fingerprint==fingerprint else _command_result(id,"rejected","command_id_conflict")
	var error=""
	if id=="" or not command.get("command_id") is String or not _plain(command) or not command.has_all(["issuer","issued_at","execute_at","type","payload"]) or not command.get("payload") is Dictionary: error="invalid_command"
	elif not command.issuer in ["天道","NPC","系统"]: error="permission_denied"
	elif not command.issued_at is int or not command.execute_at is int or command.issued_at>state.world_minute or command.issued_at<0 or command.execute_at<state.world_minute: error="invalid_time"
	elif command.has("payload_fingerprint") and command.payload_fingerprint!=fingerprint: error="invalid_command"
	else: error=_validate_command(command)
	if error!="":
		var result=_command_result(id,"rejected",error)
		if id!="": state.command_results[id]={"fingerprint":fingerprint,"result":result}
		return result
	state.counters.command+=1
	if command.type in ["watch","unwatch"] or (not state.paused and command.execute_at==state.world_minute):
		var result=_apply_command(command)
		state.command_results[id]={"fingerprint":fingerprint,"result":result}
		return result
	var queued=_command_result(id,"queued")
	state.command_results[id]={"fingerprint":fingerprint,"result":queued}
	state.pending_commands.append(command.duplicate(true))
	_enqueue("command",str(command.payload.get("person_id","")),command.execute_at,{"command":command})
	return queued

func _validate_command(c: Dictionary) -> String:
	if not c.type in ["watch","unwatch","set_target","move"]: return "invalid_command"
	var p: Dictionary=c.payload
	if not p.has("person_id") or not state.persons.has(p.person_id): return "invalid_entity"
	if c.type in ["watch","unwatch"]: return ""
	if c.issuer!="NPC": return "permission_denied"
	if not state.persons[p.person_id].alive: return "dead_actor"
	if c.type=="set_target" and (not p.has("target") or not p.target is String): return "invalid_command"
	if c.type=="move":
		if not _position(p.get("position")): return "out_of_bounds"
		if not p.get("duration_minutes") is int or p.duration_minutes<=0 or p.duration_minutes>MAX_INT-state.world_minute: return "invalid_time"
		if state.persons[p.person_id].current_action!="": return "invalid_state_transition"
	return ""

func _apply_command(c: Dictionary) -> Dictionary:
	var error=_validate_command(c)
	if error!="": return _command_result(c.command_id,"rejected",error)
	var p: Dictionary=c.payload
	if c.type in ["watch","unwatch"]:
		follow_person(p.person_id,c.type=="watch")
		return _command_result(c.command_id,"applied")
	if c.type=="set_target":
		state.persons[p.person_id].target=p.target
		return _command_result(c.command_id,"applied","",_event("state_changed",[p.person_id],{"target":p.target}))
	var aid=_id("action","A")
	var due: int=state.world_minute+p.duration_minutes
	state.actions[aid]={"id":aid,"person_id":p.person_id,"kind":"move_complete","status":"travelling","started_at":state.world_minute,"due_minute":due,"payload":{"position":p.position.duplicate()},"fixture":false}
	state.persons[p.person_id].current_action=aid
	_enqueue("move_complete",p.person_id,due,{"position":p.position},aid)
	return _command_result(c.command_id,"applied","",_event("action_started",[p.person_id],{"kind":"move_complete"},aid))

func advance_real_us(delta: int, max_operations: int = 100000) -> Dictionary:
	if delta<0: return _bad("invalid_time")
	if state.paused: return {"ok":true,"advanced_minutes":0,"pending_minutes":state.pending_minutes,"paused":true}
	var factor: int=60*state.multiplier
	if delta>int((MAX_INT-state.numerator)/factor): return _bad("time_overflow")
	var numerator: int=state.numerator+delta*factor
	var minutes: int=int(numerator/1000000)
	if not _time_target_valid(minutes): return _bad("time_overflow")
	state.numerator=numerator%1000000
	return advance_minutes(minutes,max_operations)

func _time_target_valid(minutes: int) -> bool:
	if minutes>MAX_INT-state.pending_minutes or minutes+state.pending_minutes>MAX_INT-state.world_minute: return false
	var target: int=state.world_minute+state.pending_minutes+minutes
	# A boundary snapshot must retain a representable next monthly save date.
	if target>=state.next_autosave_minute and target>MAX_INT-43200: return false
	if state.pending_minutes+minutes>MAX_INT-state.discarded_minutes: return false
	for p in state.persons.values():
		if p.birth_minute<0 and target>MAX_INT+p.birth_minute: return false
		var life: int=(Rules.natural_days(p,state.rules)-p.burn_days)*Rules.DAY
		if life<0 and target-p.birth_minute>MAX_INT+life: return false
	return true

func advance_minutes(minutes: int, max_operations: int = 100000) -> Dictionary:
	if minutes<0: return _bad("invalid_time")
	if state.paused: return {"ok":true,"advanced_minutes":0,"pending_minutes":state.pending_minutes,"paused":true}
	if not _time_target_valid(minutes): return _bad("time_overflow")
	state.pending_minutes+=minutes
	var start: int=state.world_minute
	var operations=0
	while operations<maxi(0,max_operations):
		_sort_queue()
		var target: int=state.world_minute+state.pending_minutes
		var next: int=target
		if not state.queue.is_empty(): next=mini(next,state.queue[0].due_minute)
		next=mini(next,state.next_autosave_minute)
		# Every hour is a scheduling checkpoint, even with no active gameplay.
		var hour_boundary: int=state.world_minute+mini(60-state.world_minute%60,MAX_INT-state.world_minute)
		next=mini(next,hour_boundary)
		for p in state.persons.values():
			if p.alive:
				var remaining: int=Rules.derived(p,state.world_minute,state.rules).remaining_lifespan_minutes
				if remaining>0 and remaining<=next-state.world_minute: next=state.world_minute+remaining
		if state.phase_cursor.phase<9: next=state.world_minute
		if next>state.world_minute:
			state.pending_minutes-=next-state.world_minute
			state.world_minute=next
			state.phase_cursor={"minute":next,"phase":0,"last_sequence":0}
		var did_work=false
		for phase in range(maxi(1,state.phase_cursor.phase),9):
			state.phase_cursor.phase=phase
			if phase==2: _check_deaths()
			while not state.queue.is_empty() and state.queue[0].due_minute==state.world_minute and state.queue[0].phase==phase:
				var q: Dictionary=state.queue.pop_front()
				_execute_due(q)
				state.phase_cursor.last_sequence=q.stable_sequence
				did_work=true
				operations+=1
				# Finish the reminder batch at this phase before event pause.
				if operations>=max_operations and phase!=7: break
			if phase==7 and _unacknowledged_followed():
				state.paused=true
				state.pause_reason={"type":"notification","minute":state.world_minute}
				state.discarded_minutes+=state.pending_minutes
				state.pending_minutes=0
				break
			if operations>=max_operations: break
		if not state.paused and state.phase_cursor.phase==8 and not (not state.queue.is_empty() and state.queue[0].due_minute==state.world_minute and state.queue[0].phase==8):
			state.phase_cursor.phase=9
		if state.world_minute==state.next_autosave_minute:
			state.next_autosave_minute+=43200
			autosave_snapshots.append(snapshot())
		if state.paused: break
		operations+=1
		if state.pending_minutes==0 and state.phase_cursor.phase==9 and (state.queue.is_empty() or state.queue[0].due_minute>state.world_minute): break
		if not did_work and state.world_minute==target and state.phase_cursor.phase==9: break
	return {"ok":true,"advanced_minutes":state.world_minute-start,"pending_minutes":state.pending_minutes,"paused":state.paused,"operations":operations,"discarded_minutes":state.discarded_minutes}

func _unacknowledged_followed() -> bool:
	for n in state.notifications:
		if n.person_id in state.followed and not n.notification_id in state.acknowledged: return true
	return false

func _check_deaths() -> void:
	var ids=state.persons.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary=state.persons[id]
		if p.alive and Rules.derived(p,state.world_minute,state.rules).remaining_lifespan_minutes<=0:
			p.alive=false
			p.wallet.reserved=0
			if p.current_action!="":
				var aid: String=p.current_action
				state.actions[aid].status="cancelled"
				p.current_action=""
				_event("cancelled",[id],{"reason":"dead_actor"},aid)
			_event("died",[id],{"reason":"lifespan"})

func _execute_due(q: Dictionary) -> void:
	if q.kind=="command":
		var c: Dictionary=q.payload.command
		var result=_apply_command(c)
		state.command_results[c.command_id].result=result
		state.pending_commands.erase(c)
		return
	if q.person_id=="" or not state.persons.has(q.person_id): return
	var p: Dictionary=state.persons[q.person_id]
	if not p.alive: return
	if q.action_id!="":
		var a: Dictionary=state.actions[q.action_id]
		if a.status in ["completed","cancelled","failed"]: return
		if a.started_at>=state.world_minute: return
		if q.kind=="breakthrough_complete": p.realm=q.payload.realm
		if q.kind=="move_complete": p.position=q.payload.position.duplicate()
		var result={"kind":q.kind,"fixture":a.fixture}
		if q.kind=="random_complete":
			var rng=RandomNumberGenerator.new()
			rng.state=state.rng_state
			# Dot insertion creates a StringName key, outside the save primitive contract.
			result["roll"]=rng.randi_range(0,10000)
			state.rng_state=rng.state
		a.status="completed"
		p.current_action=""
		_event("completed",[q.person_id],result,q.action_id,[],"fixture" if a.fixture else "system")
	elif q.kind=="reminder":
		var nid: String=str(q.payload.get("notification_id",""))
		for n in state.notifications:
			if n.notification_id==nid: return
		if nid=="":
			nid=_id("notification","N")
			var existing=true
			while existing:
				existing=false
				for n in state.notifications:
					if n.notification_id==nid: existing=true
				if existing: nid=_id("notification","N")
		var ev=_event("fixture_preparation_ready",[q.person_id],{"reason":q.payload.get("reason","准备突破（测试夹具）"),"fixture":true},"",q.payload.get("cause_event_ids",[]),"fixture")
		state.notifications.append({"notification_id":nid,"person_id":q.person_id,"event_id":ev.event_id,"reason":q.payload.get("reason","准备突破（测试夹具）"),"world_minute":state.world_minute})
	else:
		_event("fixture_"+q.kind,[q.person_id],{"fixture":true,"payload":q.payload},"",[],"fixture")
