extends RefCounted
class_name GameInteractionContext

static func build_shared_context(data: Dictionary) -> String:
	var lines: Array = []
	var world_seed_input = str(data.get("world_seed_input", "")).strip_edges()
	var background = str(data.get("background", "")).strip_edges()
	var current_site_name = str(data.get("current_site_name", "")).strip_edges()
	var money = str(data.get("money", "")).strip_edges()
	var player_name = str(data.get("player_name", "")).strip_edges()
	var inventory_snapshot = str(data.get("inventory_snapshot", "")).strip_edges()
	var focus_npc_name = str(data.get("focus_npc_name", "")).strip_edges()
	var focus_npc_desc = str(data.get("focus_npc_desc", "")).strip_edges()
	var identity_guidance = str(data.get("identity_guidance", "")).strip_edges()
	var chat_session_mem = str(data.get("chat_session_mem", "")).strip_edges()
	var related_events = str(data.get("related_events", "")).strip_edges()
	if world_seed_input != "":
		lines.append("设定：" + world_seed_input)
	if background != "":
		lines.append("世界：" + background)
	if current_site_name != "":
		lines.append("地点：" + current_site_name)
	if money != "":
		lines.append("资产：" + money)
	if player_name != "":
		lines.append("身份：" + player_name)
	if inventory_snapshot != "":
		lines.append("背包：" + inventory_snapshot)
	if focus_npc_name != "":
		lines.append("对象：" + focus_npc_name)
	if focus_npc_desc != "":
		lines.append("对象身份：" + focus_npc_desc)
	if focus_npc_name != "":
		lines.append("规则：行动或对话无明确对象时默认围绕当前对象展开。")
	if identity_guidance != "":
		lines.append("态度导向：\n" + identity_guidance)
	if chat_session_mem != "":
		var session_lines = chat_session_mem.split("\n")
		var session_set = {}
		for s in session_lines:
			if s.strip_edges() != "":
				session_set[s] = true
		var session_keys = session_set.keys()
		if session_keys.size() > 6:
			session_keys = session_keys.slice(session_keys.size() - 6, session_keys.size())
		lines.append("当前会话强约束：\n" + "\n".join(session_keys))
	if related_events != "":
		var event_lines = related_events.split("\n")
		var event_set = {}
		for e in event_lines:
			if e.strip_edges() != "":
				event_set[e] = true
		var event_keys = event_set.keys()
		if event_keys.size() > 6:
			event_keys = event_keys.slice(event_keys.size() - 6, event_keys.size())
		lines.append("事件记忆：\n" + "\n".join(event_keys))
	return "\n".join(lines)

static func build_dialogue_runtime_context(data: Dictionary) -> String:
	var lines: Array = []
	var current_site_name = str(data.get("current_site_name", "")).strip_edges()
	var money = str(data.get("money", "")).strip_edges()
	var inventory_snapshot = str(data.get("inventory_snapshot", "")).strip_edges()
	if current_site_name != "":
		lines.append("地点：" + current_site_name)
	if money != "":
		lines.append("资产：" + money)
	if inventory_snapshot != "":
		lines.append("背包：" + inventory_snapshot)
	return "\n".join(lines)

static func build_dialogue_user_content(prompt: String, shared_context: String = "") -> String:
	var clean_prompt = str(prompt).strip_edges()
	var clean_context = str(shared_context).strip_edges()
	if clean_context == "":
		return clean_prompt
	return "必须严格延续以下当前上下文，不得与其冲突：\n" + clean_context + "\n玩家当前输入：" + clean_prompt
