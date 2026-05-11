extends RefCounted
class_name GameAiUtils

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
