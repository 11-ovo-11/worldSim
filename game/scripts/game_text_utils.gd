extends RefCounted
class_name GameTextUtils

static func normalize_single_line_input(raw_text: String) -> String:
	var t = str(raw_text).replace("\r\n", "\n").replace("\r", "\n")
	if t.find("\n") != -1:
		t = t.substr(0, t.find("\n"))
	return t.strip_edges()

static func compact_history_rows_for_recovery(rows: Array, recent_keep: int = 6, summary_keep: int = 8, max_item_chars: int = 28) -> Array:
	var cleaned: Array = []
	for row in rows:
		var line = str(row).strip_edges()
		if line != "":
			cleaned.append(line)
	if cleaned.size() <= recent_keep:
		return cleaned
	var older_end = max(0, cleaned.size() - recent_keep)
	var summary_parts: Array = []
	var summary_start = max(0, older_end - summary_keep)
	for i in range(summary_start, older_end):
		var piece = str(cleaned[i]).strip_edges()
		if piece == "":
			continue
		if piece.length() > max_item_chars:
			piece = piece.substr(0, max_item_chars).strip_edges() + "..."
		summary_parts.append(piece)
	var out: Array = []
	if !summary_parts.is_empty():
		out.append("[系统摘要]此前上下文：" + "；".join(summary_parts))
	for i in range(older_end, cleaned.size()):
		out.append(cleaned[i])
	return out

static func compact_text_for_recovery(text: String, recent_keep: int = 8) -> String:
	var rows = str(text).replace("\r\n", "\n").replace("\r", "\n").split("\n", false)
	var compacted = compact_history_rows_for_recovery(rows, recent_keep, 10, 36)
	if compacted.is_empty():
		return ""
	return "\n".join(compacted)

static func extract_route_candidates_from_site_json(json_dic: Dictionary) -> Array:
	var route_keys = ["能前往的地点", "可前往地点", "可前往的地点", "前往地点", "可去地点", "可到达地点", "邻近地点", "连接地点"]
	var candidates: Array = []
	for key in route_keys:
		if !json_dic.has(key):
			continue
		var raw_val = json_dic.get(key)
		var raw_list: Array = []
		if raw_val is Array:
			raw_list = raw_val
		elif raw_val is String:
			var merged = str(raw_val)
			var splitters = ["\r\n", "\n", "，", ",", "、", "；", ";", "|", "/"]
			for sp in splitters:
				merged = merged.replace(sp, ",")
			raw_list = merged.split(",", false)
		for raw_name in raw_list:
			var route_name = str(raw_name).strip_edges()
			if route_name == "":
				continue
			if !candidates.has(route_name):
				candidates.append(route_name)
	return candidates

static func resolve_site_alias(site_name: String, sites: Dictionary) -> String:
	var cleaned = site_name.strip_edges()
	if cleaned == "":
		return ""
	if sites.has(cleaned):
		return cleaned
	for key in sites.keys():
		var existing = str(key).strip_edges()
		if existing == "":
			continue
		if cleaned == existing:
			return existing
		if min(cleaned.length(), existing.length()) >= 2 and (cleaned.ends_with(existing) or existing.ends_with(cleaned)):
			return existing
	return cleaned

static func is_location_query_dialogue(input_text: String) -> bool:
	var t = normalize_single_line_input(input_text)
	if t == "":
		return false
	if GameEntityUtils.is_relation_npc_query(t):
		return false
	var query_words = ["在哪", "在哪里", "在哪儿", "怎么去", "怎么走", "怎么到", "去哪", "去哪里", "路线", "路怎么走", "哪条路"]
	for w in query_words:
		if t.find(w) != -1:
			return true
	return false
