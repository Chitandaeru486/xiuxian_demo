extends RefCounted
## All integer values are tagged decimal strings; JSON numbers are never accepted.
const FORMAT_VERSION = "1"
const RULES_VERSION = "s1-rules.1"
const BUILD_ID = "s1-build.1"
const MAX_DEPTH = 96

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _decimal(value: Variant) -> bool:
	if not value is String or value.is_empty():
		return false
	var digits: String = value
	var negative := digits.begins_with("-")
	if negative:
		digits = digits.substr(1)
	if digits.is_empty() or (digits.length() > 1 and digits.begins_with("0")) or (negative and digits == "0"):
		return false
	for character in digits:
		if character < "0" or character > "9":
			return false
	var limit := "9223372036854775808" if negative else "9223372036854775807"
	return digits.length() < limit.length() or (digits.length() == limit.length() and digits <= limit)

static func _pack(value: Variant, depth: int = 0) -> Dictionary:
	if depth > MAX_DEPTH:
		return _error("payload nesting limit")
	match typeof(value):
		TYPE_INT:
			return {"ok": true, "value": {"$type": "int64", "value": str(value)}}
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return {"ok": true, "value": value}
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				var packed := _pack(item, depth + 1)
				if not packed.ok:
					return packed
				result.append(packed.value)
			return {"ok": true, "value": result}
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in value:
				if not key is String:
					return _error("payload map keys must be strings")
				var packed := _pack(value[key], depth + 1)
				if not packed.ok:
					return packed
				result[key] = packed.value
			return {"ok": true, "value": {"$type": "map", "value": result}}
	return _error("unsupported payload type (floats and runtime objects forbidden)")

static func _unpack(value: Variant, depth: int = 0) -> Dictionary:
	if depth > MAX_DEPTH:
		return _error("payload nesting limit")
	if value is Dictionary:
		if value.size() != 2 or not value.has("$type") or not value.has("value"):
			return _error("malformed typed payload")
		if value["$type"] == "int64":
			if not _decimal(value.value):
				return _error("noncanonical or out-of-range int64")
			return {"ok": true, "value": value.value.to_int()}
		if value["$type"] != "map" or not value.value is Dictionary:
			return _error("unknown payload type")
		var result: Dictionary = {}
		for key in value.value:
			var decoded := _unpack(value.value[key], depth + 1)
			if not decoded.ok:
				return decoded
			result[key] = decoded.value
		return {"ok": true, "value": result}
	if value is Array:
		var result: Array = []
		for item in value:
			var decoded := _unpack(item, depth + 1)
			if not decoded.ok:
				return decoded
			result.append(decoded.value)
		return {"ok": true, "value": result}
	if value == null or value is String or value is bool:
		return {"ok": true, "value": value}
	return _error("raw JSON number forbidden")

static func canonical(value: Variant) -> String:
	# JSON.stringify sort_keys is recursive, and packed payload contains no numbers.
	return JSON.stringify(value, "", true, true)

static func encode(snapshot: Dictionary) -> Dictionary:
	var packed := _pack(snapshot)
	if not packed.ok:
		return packed
	var rules: String = str(snapshot.get("rules_version", RULES_VERSION))
	if rules != RULES_VERSION:
		return _error("incompatible rules version: " + rules)
	var sequence: Variant = snapshot.get("last_commit_sequence", snapshot.get("commit_sequence", snapshot.get("counters", {}).get("commit", 0)))
	if not sequence is int or sequence < 0:
		return _error("invalid commit sequence")
	var payload_text := canonical(packed.value)
	var envelope := {
		"format_version": FORMAT_VERSION, "rules_version": rules,
		"build_id": str(snapshot.get("build_id", BUILD_ID)),
		"candidate_config_status": str(snapshot.get("candidate_config_status", "candidate")),
		"snapshot_id": "snapshot-" + payload_text.sha256_text(),
		"last_commit_sequence": str(sequence),
		"payload_digest": "sha256:" + payload_text.sha256_text(), "payload": packed.value}
	return {"ok": true, "error": "", "text": canonical(envelope), "envelope": envelope}

static func decode(source: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(source) != OK or not parser.data is Dictionary:
		return _error("invalid or truncated JSON")
	var envelope: Dictionary = parser.data
	for key in ["format_version", "rules_version", "build_id", "candidate_config_status", "snapshot_id", "last_commit_sequence", "payload_digest", "payload"]:
		if not envelope.has(key):
			return _error("missing envelope field: " + key)
	if envelope.format_version != FORMAT_VERSION or envelope.rules_version != RULES_VERSION:
		return _error("incompatible save format/rules version")
	for key in ["build_id", "candidate_config_status", "snapshot_id", "payload_digest"]:
		if not envelope[key] is String or envelope[key].is_empty():
			return _error("invalid envelope field: " + key)
	if not _decimal(envelope.last_commit_sequence) or envelope.last_commit_sequence.begins_with("-"):
		return _error("invalid envelope commit sequence")
	var digest := canonical(envelope.payload).sha256_text()
	if envelope.payload_digest != "sha256:" + digest or envelope.snapshot_id != "snapshot-" + digest:
		return _error("payload digest mismatch")
	var unpacked := _unpack(envelope.payload)
	if not unpacked.ok:
		return unpacked
	if not unpacked.value is Dictionary:
		return _error("snapshot must be a map")
	var snapshot: Dictionary = unpacked.value
	if str(snapshot.get("rules_version", RULES_VERSION)) != envelope.rules_version:
		return _error("rules version mismatch")
	if str(snapshot.get("build_id", BUILD_ID)) != envelope.build_id or str(snapshot.get("candidate_config_status", "candidate")) != envelope.candidate_config_status:
		return _error("build/candidate metadata mismatch")
	if str(snapshot.get("last_commit_sequence", snapshot.get("commit_sequence", snapshot.get("counters", {}).get("commit", 0)))) != envelope.last_commit_sequence:
		return _error("commit sequence mismatch")
	return {"ok": true, "error": "", "snapshot": snapshot, "envelope": envelope}
