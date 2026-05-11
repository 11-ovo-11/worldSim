extends RefCounted
class_name GameEntityUtils

static func _norm(text: String) -> String:
	var t = str(text).replace("\r\n", "\n").replace("\r", "\n")
	if t.find("\n") != -1:
		t = t.substr(0, t.find("\n"))
	return t.strip_edges()

static func contains_keyword(text: String, words: Array) -> bool:
	for w in words:
		if text.find(str(w)) != -1:
			return true
	return false

static func looks_like_action_phrase(text: String) -> bool:
	var t = _norm(text)
	if t == "":
		return true
	if t.length() > 18:
		return true
	var invalid_tokens = ["请", "帮", "告诉", "一下", "怎么", "哪里", "为什么", "是否", "能不能", "可以吗", "然后", "如果", "因为", "所以", "行动", "对话", "回复", "输出"]
	for token in invalid_tokens:
		if t.find(token) != -1:
			return true
	return false

static func extract_compact_entity(raw_text: String, max_len: int = 14) -> String:
	var t = _norm(raw_text)
	t = t.replace("：", " ").replace(":", " ").replace("。", " ").replace("，", " ").replace("？", " ").replace("!", " ")
	var regex = RegEx.new()
	if regex.compile("([\\p{Han}A-Za-z·]{2,24})") != OK:
		return ""
	var m = regex.search(t)
	if m == null:
		return ""
	var candidate = str(m.get_string(1)).strip_edges()
	if candidate.length() > max_len:
		candidate = candidate.substr(0, max_len)
	return candidate

static func cleanup_location_candidate(raw_text: String) -> String:
	var t = str(raw_text).strip_edges()
	t = t.replace("？", "").replace("?", "").replace("。", "").replace("，", "")
	var trims = ["请问", "问下", "一下", "告诉我", "你知道", "我想问", "这个", "那个", "一下子", "去", "到"]
	for p in trims:
		if t.begins_with(p):
			t = t.trim_prefix(p).strip_edges()
	if t.begins_with("的"):
		t = t.trim_prefix("的").strip_edges()
	if t.ends_with("在哪"):
		t = t.left(t.length() - 2).strip_edges()
	if t.ends_with("在哪里"):
		t = t.left(t.length() - 3).strip_edges()
	if t.ends_with("在哪儿"):
		t = t.left(t.length() - 3).strip_edges()
	if t.ends_with("怎么去"):
		t = t.left(t.length() - 3).strip_edges()
	if t.ends_with("怎么走"):
		t = t.left(t.length() - 3).strip_edges()
	if t.ends_with("怎么到"):
		t = t.left(t.length() - 3).strip_edges()
	return t

static func sanitize_npc_name(raw_name: String) -> String:
	var n = _norm(raw_name)
	n = n.replace("。", "").replace("，", "").replace("？", "").replace("?", "").replace("！", "").replace("!", "")
	var prefixes = ["你的", "我的", "他的", "她的", "自己的", "这个", "那个", "一位", "有个", "有位"]
	for p in prefixes:
		if n.begins_with(p):
			n = n.trim_prefix(p).strip_edges()
	return n

static func is_bad_npc_name(npc_label: String) -> bool:
	var n = npc_label.strip_edges()
	if n == "":
		return true
	if n.length() < 2:
		return true
	var bad_words = ["女儿", "儿子", "父母", "父亲", "母亲", "爸爸", "妈妈", "兄弟", "姐妹", "同事", "上司", "下属", "家人", "亲戚", "熟人", "自己", "你的", "我的", "他的", "她的", "某人", "路人"]
	if bad_words.has(n):
		return true
	if n.begins_with("你的") or n.begins_with("我的") or n.begins_with("他的") or n.begins_with("她的"):
		return true
	return false

static func fallback_relation_npc_name(query_text: String) -> String:
	var t = _norm(query_text)
	if contains_keyword(t, ["女儿"]):
		return ["阿莲", "小霜", "露娜", "清禾"][randi_range(0, 3)]
	if contains_keyword(t, ["儿子"]):
		return ["阿成", "小川", "远山", "泽安"][randi_range(0, 3)]
	if contains_keyword(t, ["父亲", "爸爸"]):
		return ["老周", "韩叔", "陈伯", "沈叔"][randi_range(0, 3)]
	if contains_keyword(t, ["母亲", "妈妈"]):
		return ["周婶", "林姨", "方姨", "柳婶"][randi_range(0, 3)]
	if contains_keyword(t, ["兄弟", "姐妹"]):
		return ["阿岳", "小宁", "云青", "子岚"][randi_range(0, 3)]
	return ["阿远", "小禾", "程木", "林渡"][randi_range(0, 3)]

static func is_relation_npc_query(input_text: String) -> bool:
	var t = _norm(input_text)
	if t == "":
		return false
	var relation_words = ["兄弟", "姐妹", "父母", "爸爸", "妈妈", "儿子", "女儿", "同事", "上司", "下属", "学徒", "师父", "朋友", "家人", "亲戚"]
	for w in relation_words:
		if t.find(w) != -1:
			return true
	return false

static func is_valid_npc_name(raw_name: String) -> bool:
	var n = sanitize_npc_name(raw_name)
	if is_bad_npc_name(n):
		return false
	if n.length() > 12:
		return false
	if looks_like_action_phrase(n):
		return false
	var regex = RegEx.new()
	if regex.compile("^[\\p{Han}A-Za-z·]+$") != OK:
		return false
	return regex.search(n) != null

static func is_valid_location_name_basic(raw_name: String) -> bool:
	var n = cleanup_location_candidate(raw_name)
	if n == "":
		return false
	if n.length() < 2 or n.length() > 16:
		return false
	if looks_like_action_phrase(n):
		return false
	var regex = RegEx.new()
	if regex.compile("^[\\p{Han}A-Za-z0-9·]+$") != OK:
		return false
	return regex.search(n) != null

static func extract_unknown_npc_target_from_query(query_text: String) -> String:
	var t = _norm(query_text)
	if t == "":
		return ""
	var regex = RegEx.new()
	var patterns = [
		"([\\p{Han}A-Za-z\u00b7]{2,12})(?:\u5728\u54ea|\u5728\u54ea\u91cc|\u5728\u54ea\u513f|\u662f\u8c01|\u4ec0\u4e48\u4eba|\u5728\u5417|\u7684\u4fe1\u606f|\u7684\u6d88\u606f)",
		"(?:\u627e|\u5bfb\u627e|\u6253\u542c|\u95ee|\u5173\u4e8e)([\\p{Han}A-Za-z\u00b7]{2,12})"
	]
	for p in patterns:
		if regex.compile(p) != OK:
			continue
		var m = regex.search(t)
		if m == null:
			continue
		var candidate = sanitize_npc_name(str(m.get_string(1)))
		candidate = extract_compact_entity(candidate, 12)
		if !is_valid_npc_name(candidate) and is_relation_npc_query(t):
			candidate = fallback_relation_npc_name(t)
		if is_valid_npc_name(candidate):
			return candidate
	return ""
