extends RefCounted
class_name GameActionTagUtils

static func parse_direct_action_tags(tags: Array) -> Dictionary:
	var unresolved = ""
	var handled_any = false
	var operations: Array = []
	for raw_tag in tags:
		var normalized = str(raw_tag).replace("：", ":").strip_edges()
		if normalized == "":
			continue
		if normalized.begins_with("资产") or normalized.begins_with("金币") or normalized.begins_with("金钱"):
			var money_delta = GameParseUtils.extract_signed_number(normalized)
			if money_delta != 0:
				operations.append({"type": "money_delta", "delta": money_delta})
				handled_any = true
			else:
				unresolved += "<" + str(raw_tag) + ">"
		elif normalized.begins_with("声望值"):
			var rep_delta = GameParseUtils.extract_signed_number(normalized.trim_prefix("声望值").strip_edges())
			if rep_delta != 0:
				operations.append({"type": "reputation_delta", "delta": rep_delta})
				handled_any = true
			else:
				unresolved += "<" + str(raw_tag) + ">"
		elif normalized.begins_with("犯罪"):
			operations.append({"type": "crime_flag"})
			handled_any = true
		elif normalized.begins_with("前往"):
			var target = normalized.trim_prefix("前往").replace(":", "").strip_edges()
			if target != "":
				operations.append({"type": "nav_target", "target": target})
				handled_any = true
			else:
				unresolved += "<" + str(raw_tag) + ">"
		elif normalized.begins_with("设置时间"):
			var time_info = GameParseUtils.extract_target_time(normalized)
			if bool(time_info.get("valid", false)):
				operations.append({
					"type": "set_time",
					"hour": int(time_info.get("hour", 0)),
					"minute": int(time_info.get("minute", 0))
				})
				handled_any = true
			else:
				unresolved += "<" + str(raw_tag) + ">"
		else:
			unresolved += "<" + str(raw_tag) + ">"
	return {"handled_any": handled_any, "unresolved_tags": unresolved, "operations": operations}
