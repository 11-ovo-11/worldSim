extends RefCounted
class_name GameAiUtils

static func safe_continuation_text() -> String:
	return "对方略过了那段细节，直接把注意力转回眼前的互动。场景继续向前推进，角色的态度和先前的关系保持连贯。"

static func limit_output_chars(text: String, maximum: int) -> String:
	var limit = max(0, maximum)
	var src = str(text).strip_edges()
	if limit <= 0 or src.length() <= limit:
		return src
	var cut = src.left(limit)
	var boundary = -1
	for marker in ["。", "！", "？", "!", "?", "；", ";", "\n"]:
		boundary = max(boundary, cut.rfind(marker))
	if boundary >= int(limit * 0.6):
		cut = cut.left(boundary + 1)
	return cut.strip_edges()

static func compact_prompt_content(text: String) -> String:
	var src = str(text).replace("\r\n", "\n").replace("\r", "\n")
	var rows = src.split("\n", false)
	var out: Array = []
	for row in rows:
		var cleaned = str(row).strip_edges()
		if cleaned == "":
			continue
		while cleaned.find("  ") != -1:
			cleaned = cleaned.replace("  ", " ")
		out.append(cleaned)
	if out.is_empty():
		return ""
	return "\n".join(out)

static func sanitize_frontend_text(text: String) -> String:
	var src = strip_angle_tags(str(text)).replace("\r\n", "\n").replace("\r", "\n")
	var meta_keywords = ["态度变化", "NPC态度", "好感度", "亲密度", "声望变化", "状态变化", "后台数据", "后端数据", "系统提示", "工具调用", "函数调用"]
	var kept: Array = []
	for raw_line in src.split("\n", false):
		var line = str(raw_line).strip_edges()
		if line == "":
			continue
		var structured_meta = line.begins_with("[") or line.begins_with("【") or line.begins_with("(") or line.begins_with("（") or line.begins_with("{")
		var remove_line = false
		for keyword in meta_keywords:
			if (structured_meta and line.find(keyword) != -1) or line.begins_with(keyword + "：") or line.begins_with(keyword + ":"):
					remove_line = true
					break
		if !remove_line:
			kept.append(line)
	var result = "\n".join(kept)
	var inline_meta = RegEx.new()
	if inline_meta.compile("[（(【\\[]\\s*(NPC)?(态度变化|好感度|亲密度|声望变化|状态变化|后台数据|后端数据|系统提示|工具调用|函数调用)[^）)】\\]]*[）)】\\]]") == OK:
		result = inline_meta.sub(result, "", true)
	return _sanitize_provider_refusal(result)

static func _sanitize_provider_refusal(text: String) -> String:
	var src = str(text).strip_edges()
	if src == "":
		return src
	var markers = ["作为AI", "作为一个AI", "我不能帮助", "无法协助", "不能协助", "无法生成", "不能生成", "不提供这类", "违反政策", "违反安全", "不适合生成", "抱歉，我不能", "抱歉，无法", "我无法继续", "无法继续生成", "我不能描写", "无法描写", "不能描写", "安全原因", "内容限制"]
	var has_refusal = false
	for marker in markers:
		if src.find(marker) != -1:
			has_refusal = true
			break
	if !has_refusal:
		return src
	var kept: Array = []
	for raw_part in src.split("\n", false):
		for part in str(raw_part).split("。", false):
			for clause in str(part).split("，", false):
				var piece = str(clause).strip_edges()
				if piece == "":
					continue
				var is_refusal = false
				for marker in markers:
					if piece.find(marker) != -1:
						is_refusal = true
						break
				if !is_refusal:
					kept.append(piece)
	if kept.is_empty():
		return "对方略过了那段细节，直接把注意力转回眼前的互动。场景继续向前推进。"
	return "。".join(kept) + "。"

static func compact_messages_for_request(messages: Array) -> Array:
	var copied = messages.duplicate(true)
	for i in range(copied.size()):
		var row = copied[i]
		if !(row is Dictionary):
			continue
		if !row.has("content"):
			continue
		row["content"] = compact_prompt_content(str(row.get("content", "")))
		copied[i] = row
	return copied

static func compact_action_narration(text: String) -> String:
	var src = str(text).strip_edges()
	if src == "":
		return src
	var removable = ["没有人阻拦", "没人阻拦", "没有人报警", "没人报警", "没有人追着问", "没人追问", "没有人问你来意", "没人问你来意", "没有人躲开", "没人躲开", "没有谁表现出抗拒或犹豫", "没有人表现出抗拒或犹豫", "没有意外也没有不满", "公司照常营业", "其他事务照旧运转", "无需提前跟他打招呼", "不用提前跟他打招呼", "不用顾及他的安排", "不必顾及他的安排", "一切照常"]
	var out: Array = []
	for raw_line in src.replace("\r", "").split("\n", false):
		for raw_piece in str(raw_line).split("。", false):
			var piece = str(raw_piece).strip_edges()
			if piece == "":
				continue
			for fragment in removable:
				piece = piece.replace(fragment, "")
			piece = piece.replace("，。，", "，").replace("，，", "，").strip_edges()
			if piece == "":
				continue
			var side_only = true
			for marker in removable:
				if piece.find(marker) == -1:
					side_only = false
					break
			if side_only:
				continue
			var duplicate = false
			for old in out:
				if str(old) == piece or (piece.length() >= 12 and str(old).find(piece) != -1):
					duplicate = true
					break
			if !duplicate:
				out.append(piece)
	if out.is_empty():
		return src
	return "。".join(out) + ("。" if src.ends_with("。") else "")

static func tail_preview(text: String, max_chars: int = 48) -> String:
	var src = str(text)
	if src.length() <= max_chars:
		return src
	return src.substr(src.length() - max_chars, max_chars)

static func strip_angle_tags(text: String) -> String:
	var src = str(text)
	var regex = RegEx.new()
	if regex.compile("<[^>]*>") != OK:
		return src
	return regex.sub(src, "", true)

static func extract_angle_tags(input_string: String) -> Array:
	var tags: Array = []
	var normalized_input = str(input_string)
	normalized_input = normalized_input.replace("\\<", "<").replace("\\>", ">")
	normalized_input = normalized_input.replace("＜", "<").replace("＞", ">")
	var regex = RegEx.new()
	if regex.compile("<([^>]+)>") != OK:
		return tags
	for m in regex.search_all(normalized_input):
		tags.append(str(m.get_string(1)).strip_edges())
	return tags

static func get_content_in_angle_brackets(input_string: String) -> String:
	var results = ""
	var normalized_input = str(input_string)
	normalized_input = normalized_input.replace("\\<", "<").replace("\\>", ">")
	normalized_input = normalized_input.replace("＜", "<").replace("＞", ">")
	var regex = RegEx.new()
	regex.compile("<[^>]+>")
	var matches = regex.search_all(normalized_input)
	for match_obj in matches:
		results += match_obj.get_string(0)
	return results

static func extract_json_from_text(input_string: String) -> Dictionary:
	var cleaned = input_string.replace("```json", "").replace("```", "").strip_edges()
	var json = JSON.new()
	var parse_result = json.parse(cleaned)
	if parse_result == OK:
		return json.get_data()
	var start_idx = cleaned.find("{")
	var end_idx = cleaned.rfind("}")
	if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
		var json_string = cleaned.substr(start_idx, end_idx - start_idx + 1)
		parse_result = json.parse(json_string)
		if parse_result == OK:
			return json.get_data()
		else:
			print("JSON解析错误: ", json.get_error_message())
	return {}
