extends RefCounted
class_name GameMemoryUtils

static func extract_npc_mentions(npcs: Dictionary, text: String) -> Array:
	var found: Array = []
	var t = str(text)
	if t.strip_edges() == "":
		return found
	for k in npcs.keys():
		var npc_name_text = str(k)
		if npc_name_text != "" and t.find(npc_name_text) != -1 and !found.has(npc_name_text):
			found.append(npc_name_text)
	return found

static func build_relevant_event_memory_text(personal_rows: Array, related_rows: Array) -> String:
	if !personal_rows.is_empty():
		var personal_lines: Array = []
		for line in personal_rows:
			personal_lines.append("- " + str(line))
		return "\n".join(personal_lines).strip_edges()
	if related_rows.is_empty():
		return ""
	var lines: Array = []
	for m in related_rows:
		if m is Dictionary:
			lines.append("- " + str(m.get("text", "")).strip_edges())
	return "\n".join(lines).strip_edges()

static func resolve_focus_npc_for_action(action_text: String, focus_npc_name: String, npcs: Dictionary) -> String:
	var focus_npc = focus_npc_name.strip_edges()
	var mentions = extract_npc_mentions(npcs, action_text)
	if !mentions.is_empty():
		focus_npc = str(mentions[0])
	return focus_npc

static func ensure_npc_event_bucket(npcs: Dictionary, npc_name: String) -> void:
	if npc_name == "":
		return
	if !npcs.has(npc_name) or !(npcs[npc_name] is Dictionary):
		npcs[npc_name] = {"npc_describe": "", "npc_log": [], "特征": "", "important_events": []}
	if !npcs[npc_name].has("npc_log") or !(npcs[npc_name]["npc_log"] is Array):
		npcs[npc_name]["npc_log"] = []
	if !npcs[npc_name].has("important_events") or !(npcs[npc_name]["important_events"] is Array):
		npcs[npc_name]["important_events"] = []

# record must have "text","trade","gift","assist","positive","negative","coercion","respect","t" keys
static func append_event_to_npc_memory(npcs: Dictionary, npc_name: String, record: Dictionary, focus_npc: String) -> void:
	if npc_name == "":
		return
	ensure_npc_event_bucket(npcs, npc_name)
	var plain = str(record.get("text", "")).strip_edges()
	if plain == "":
		return
	var sig = {
		"trade": int(record.get("trade", 0)),
		"gift": int(record.get("gift", 0)),
		"assist": int(record.get("assist", 0)),
		"positive": int(record.get("positive", 0)),
		"negative": int(record.get("negative", 0)),
		"coercion": int(record.get("coercion", 0)),
		"respect": int(record.get("respect", 0))
	}
	var npc_view = GameEventUtils.build_npc_personal_event_summary(plain, npc_name, focus_npc, sig)
	if npc_view == "":
		return
	var npc_bucket: Array = npcs[npc_name].get("important_events", [])
	for old in npc_bucket:
		if old is Dictionary and str(old.get("npc_view", "")) == npc_view:
			return
	npc_bucket.append({
		"text": plain.left(220),
		"npc_view": npc_view.left(180),
		"t": int(record.get("t", Time.get_unix_time_from_system()))
	})
	if npc_bucket.size() > 40:
		npc_bucket = npc_bucket.slice(npc_bucket.size() - 40, npc_bucket.size())
	npcs[npc_name]["important_events"] = npc_bucket

static func refine_important_event_text(raw_text: String) -> String:
	var t = str(raw_text).strip_edges()
	if t == "":
		return ""
	t = t.replace("\r\n", "\n").replace("\r", "\n")
	var compact_lines: Array = []
	for line in t.split("\n", false):
		var one = str(line).strip_edges()
		if one == "":
			continue
		compact_lines.append(one)
	t = "；".join(compact_lines)
	t = t.replace("<对话>", "").replace("<行动结果>", "").replace("<NPC情报>", "").replace("<", "").replace(">", "")
	if t.length() > 260:
		t = t.left(260)
	return t.strip_edges()

# plain_text: already processed via process_string before calling this
static func remember_important_event(important_event_memories: Array, npcs: Dictionary, plain_text: String, site_name: String, focus_npc: String) -> void:
	var refined_text = refine_important_event_text(plain_text)
	if refined_text == "":
		return
	var npc_names: Array = []
	for k in npcs.keys():
		var npc_name_text = str(k)
		if npc_name_text != "" and refined_text.find(npc_name_text) != -1 and !npc_names.has(npc_name_text):
			npc_names.append(npc_name_text)
	var focus_clean = focus_npc.strip_edges()
	if focus_clean != "" and !npc_names.has(focus_clean):
		npc_names.append(focus_clean)
	var sig = GameNpcInferUtils.extract_interaction_signals(refined_text)
	if !GameEventUtils.should_store_npc_personal_event(refined_text, sig):
		return
	var record = {
		"text": refined_text,
		"site": site_name,
		"npcs": npc_names,
		"trade": int(sig.get("trade", 0)),
		"gift": int(sig.get("gift", 0)),
		"assist": int(sig.get("assist", 0)),
		"positive": int(sig.get("positive", 0)),
		"negative": int(sig.get("negative", 0)),
		"coercion": int(sig.get("coercion", 0)),
		"respect": int(sig.get("respect", 0)),
		"t": Time.get_unix_time_from_system()
	}
	for i in range(important_event_memories.size() - 1, -1, -1):
		var old = important_event_memories[i]
		if old is Dictionary and str(old.get("text", "")) == plain_text:
			important_event_memories.remove_at(i)
	important_event_memories.append(record)
	while important_event_memories.size() > 200:
		important_event_memories.remove_at(0)
	for n in npc_names:
		append_event_to_npc_memory(npcs, str(n), record, focus_clean)

static func get_recent_npc_personal_events(npcs: Dictionary, npc_name: String, limit_count: int = 3) -> Array:
	var out: Array = []
	if npc_name == "" or !npcs.has(npc_name) or !(npcs[npc_name] is Dictionary):
		return out
	if !npcs[npc_name].has("important_events") or !(npcs[npc_name]["important_events"] is Array):
		return out
	var bucket: Array = npcs[npc_name]["important_events"]
	var start_idx = max(0, bucket.size() - limit_count)
	for i in range(start_idx, bucket.size()):
		var row = bucket[i]
		if !(row is Dictionary):
			continue
		var view_text = str(row.get("npc_view", "")).strip_edges()
		if view_text == "":
			continue
		out.append(view_text.left(80))
	return out

static func get_recent_related_event_memories(important_event_memories: Array, site_name: String, npc_name: String = "", limit_count: int = 4, intent_hint: Dictionary = {}) -> Array:
	var scored: Array = []
	for mem_item in important_event_memories:
		if !(mem_item is Dictionary):
			continue
		var mem: Dictionary = mem_item
		var score = GameEventUtils.score_event_relevance(mem, site_name, npc_name, intent_hint)
		if score <= 0:
			continue
		scored.append({"score": score, "mem": mem})
	scored.sort_custom(func(a, b):
		var sa = int(a.get("score", 0))
		var sb = int(b.get("score", 0))
		if sa == sb:
			return int(a.get("mem", {}).get("t", 0)) > int(b.get("mem", {}).get("t", 0))
		return sa > sb
	)
	var out: Array = []
	for row in scored:
		out.append(row.get("mem", {}))
		if out.size() >= limit_count:
			break
	return out
