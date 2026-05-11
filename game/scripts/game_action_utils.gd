extends RefCounted
class_name GameActionUtils

# plain_reply: already processed (angle tags stripped), tags: pre-extracted from tool_tags + action_reply
static func build_crime_context(action_input: String, plain_reply: String, tags: Array) -> String:
	for tag in tags:
		var normalized = str(tag).replace("：", ":").strip_edges()
		if normalized.begins_with("犯罪:"):
			return normalized.trim_prefix("犯罪:").strip_edges()
	var input_text = action_input.strip_edges()
	if input_text != "":
		return input_text.left(36)
	if plain_reply.strip_edges() != "":
		return plain_reply.strip_edges().left(36)
	return "可疑行为"

# plain_action_reply: already processed via process_string
static func build_action_context_text(action_input: String, plain_action_reply: String) -> String:
	var context_text = action_input.strip_edges()
	if context_text == "":
		context_text = plain_action_reply.strip_edges()
	if context_text == "":
		context_text = (action_input + " " + plain_action_reply).strip_edges()
	return context_text.left(64)

static func build_identity_attitude_guidance(player_name: String, world_seed: String, reputation: float, focus_npc_name: String = "", focus_npc_desc: String = "") -> String:
	var lines: Array = []
	var player_role_text = (player_name + " " + world_seed).strip_edges()
	var npc_text = (focus_npc_name + " " + focus_npc_desc).strip_edges()
	lines.append("- 玩家身份（系统确认）:" + player_name)
	if GameEntityUtils.contains_keyword(player_role_text, ["国王", "皇帝", "君主", "王", "摄政", "王储"]):
		lines.append("- 统治身份导向：普通NPC默认更谨慎/敬畏，除非有强事件依据才会顶撞。")
	if GameEntityUtils.contains_keyword(player_role_text, ["奴隶主", "领主", "将军", "军阀", "老板", "主任", "警长"]):
		lines.append("- 权力导向：NPC态度需体现权力差（迎合/畏惧/压抑反感），不可按陌生平民处理。")
	if GameEntityUtils.contains_keyword(player_role_text, ["囚犯", "逃犯", "通缉", "流浪汉", "乞丐"]):
		lines.append("- 风险身份导向：NPC更可能戒备、排斥或利用。")
	if reputation >= 130.0:
		lines.append("- 声望高导向：NPC更易尊重、配合。")
	elif reputation <= 60.0:
		lines.append("- 声望低导向：NPC更易警惕、厌恶或拒绝。")
	if focus_npc_name != "":
		lines.append("- 当前NPC：" + focus_npc_name + "（" + focus_npc_desc + "）")
		if GameEntityUtils.contains_keyword(npc_text, ["护卫", "保安", "警察", "士兵", "侍卫"]):
			lines.append("- 秩序角色导向：更重规则/风险/立场，不会无条件顺从。")
		if GameEntityUtils.contains_keyword(npc_text, ["平民", "学生", "路人", "店员", "仆人"]):
			lines.append("- 普通角色导向：在高权势面前通常更保守或顺从。")
	return "\n".join(lines)

static func extract_nav_target_from_text(text: String, current_site_name: String, site_names: Array) -> String:
	var fail_words = ["无法", "不能", "不行", "失败", "被阻", "没能", "不让", "不允许", "随即返回", "无法前往"]
	for w in fail_words:
		if text.find(w) != -1:
			return ""
	var travel_words = ["前往", "去了", "来到", "到达了", "抵达", "走向", "回到了", "走进", "进入了", "出发前往", "动身前往", "前去", "赶往"]
	var has_travel = false
	for w in travel_words:
		if text.find(w) != -1:
			has_travel = true
			break
	if !has_travel:
		return ""
	for site in site_names:
		var site_str = str(site).strip_edges()
		if site_str != "" and site_str != current_site_name and text.find(site_str) != -1:
			return site_str
	return ""
