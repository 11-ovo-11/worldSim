extends RefCounted
class_name GameParseUtils

static func sanitize_response_text(raw_text: String) -> String:
	var t = str(raw_text)
	t = t.replace("\ufeff", "").replace("\u200b", "")
	t = t.replace("\r\n", "\n").replace("\r", "\n")
	var lines: Array = t.split("\n", true)
	while !lines.is_empty() and str(lines[0]).strip_edges() == "":
		lines.remove_at(0)
	t = "\n".join(lines)
	return t.strip_edges(false, true)

static func extract_duration_hours(text: String) -> float:
	var regex = RegEx.new()
	if regex.compile("(\\d+(?:\\.\\d+)?)\\s*小时") == OK:
		var h = regex.search(text)
		if h != null:
			return float(h.get_string(1))
	if text.find("半小时") != -1:
		return 0.5
	if regex.compile("(\\d+)\\s*分钟") == OK:
		var m = regex.search(text)
		if m != null:
			return float(int(m.get_string(1))) / 60.0
	return 0.0

static func extract_target_time(text: String) -> Dictionary:
	var regex = RegEx.new()
	if regex.compile("(\\d{1,2})\\s*[:：]\\s*(\\d{1,2})") == OK:
		var m = regex.search(text)
		if m != null:
			var h = clamp(int(m.get_string(1)), 0, 23)
			var mm = clamp(int(m.get_string(2)), 0, 59)
			return {"valid": true, "hour": h, "minute": mm}
	if regex.compile("(\\d{1,2})\\s*点\\s*(半|\\d{1,2}分?)?") == OK:
		var p = regex.search(text)
		if p != null:
			var h2 = clamp(int(p.get_string(1)), 0, 23)
			var minute_text = str(p.get_string(2)).strip_edges()
			var m2 = 0
			if minute_text == "半":
				m2 = 30
			elif minute_text != "":
				minute_text = minute_text.replace("分", "")
				m2 = clamp(int(minute_text), 0, 59)
			return {"valid": true, "hour": h2, "minute": m2}
	return {"valid": false, "hour": 0, "minute": 0}

static func extract_signed_number(text: String) -> int:
	var regex = RegEx.new()
	if regex.compile("([+-]?\\d+)") != OK:
		return 0
	var m = regex.search(text)
	if m == null:
		return 0
	return int(m.get_string(1))

# plain_text: already processed (angle tags stripped)
static func extract_money_delta_from_text(plain_text: String) -> int:
	var t = plain_text.strip_edges()
	if t == "":
		return 0
	var spend_patterns = ["花费", "花了", "花去", "支付", "付了", "付款", "消费", "支出", "扣除", "减少", "损失", "收你"]
	for p in spend_patterns:
		var spend_regex = RegEx.new()
		if spend_regex.compile(p + "\\s*(\\d+)") == OK:
			var spend_match = spend_regex.search(t)
			if spend_match != null:
				return -int(spend_match.get_string(1))
	var income_patterns = ["获得", "赚了", "收入", "得到", "返还", "退款", "增加了"]
	for p in income_patterns:
		var income_regex = RegEx.new()
		if income_regex.compile(p + "\\s*(\\d+)") == OK:
			var income_match = income_regex.search(t)
			if income_match != null:
				return int(income_match.get_string(1))
	return 0
