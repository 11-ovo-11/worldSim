extends Node
class_name npc
const GamePrompts = preload("res://scripts/game_prompts.gd")
var npcName:String = ""
var npcDescribe:String = ""
var npcLog:String = ""
var currentChat:String = ""
var scene:GameManager
var role_pormt
const CHAT_HISTORY_MAX_LINES := 12
const CHAT_HISTORY_MAX_CHARS := 1800
const SESSION_MEMORY_MAX_CHARS := 2400
const EVENT_MEMORY_MAX_CHARS := 240
const IDENTITY_GUIDANCE_MAX_CHARS := 280
const RUMORS_MAX_CHARS := 160
const NPC_LOG_MAX_CHARS := 420
const PLAYER_IDENTITY_MAX_CHARS := 120
const BASE_PROMPT_MAX_CHARS := 3600
# 在类顶部定义提示词模板
var chat_prompt_template = GamePrompts.NPC_CHAT_PROMPT_TEMPLATE

func _clip_text(text: String, max_chars: int) -> String:
	var src = str(text).strip_edges()
	if max_chars <= 0:
		return ""
	if src.length() <= max_chars:
		return src
	var keep = max(8, max_chars - 3)
	return src.substr(0, keep).strip_edges() + "..."

func _tail_lines(text: String, max_lines: int, max_chars: int) -> String:
	var src = str(text).strip_edges()
	if src == "":
		return ""
	var rows = src.split("\n", false)
	var start_idx = max(0, rows.size() - max_lines)
	var picked: Array = []
	for i in range(start_idx, rows.size()):
		var row = str(rows[i]).strip_edges()
		if row != "":
			picked.append(row)
	if picked.is_empty():
		return ""
	return GameMemoryUtils.build_recent_context(picked, max_lines, max_chars)

func _compact_rumors() -> String:
	if scene == null:
		return ""
	if !(scene.rumors is Dictionary):
		return _clip_text(JSON.stringify(scene.rumors), RUMORS_MAX_CHARS)
	var out: Array = []
	for k in scene.rumors.keys():
		out.append("- " + _clip_text(str(k), 20) + "：" + _clip_text(str(scene.rumors[k]), 42))
		if out.size() >= 2:
			break
	if out.is_empty():
		return ""
	return _clip_text("\n".join(out), RUMORS_MAX_CHARS)

func _is_rumor_query(text: String) -> bool:
	var query = str(text).strip_edges()
	for keyword in ["传闻", "流言", "谣言", "消息", "新闻", "风声", "情报", "听说", "议论"]:
		if query.find(keyword) != -1:
			return true
	return false

func _compact_npc_log() -> String:
	if scene == null:
		return ""
	if !scene.npcs.has(npcName) or !(scene.npcs[npcName] is Dictionary):
		return ""
	var logs = scene.npcs[npcName].get("npc_log", [])
	if !(logs is Array) or logs.is_empty():
		return ""
	var out: Array = []
	var start_idx = max(0, logs.size() - 6)
	for i in range(start_idx, logs.size()):
		out.append("- " + _clip_text(str(logs[i]), 80))
	return _clip_text("\n".join(out), NPC_LOG_MAX_CHARS)

# 提取构建提示词的公共方法
func build_base_prompt(include_rumors: bool = false) -> String:
	var rumor_context = ""
	if include_rumors:
		var rumors = _compact_rumors()
		if rumors != "":
			rumor_context = "\n传闻资料（仅用于回答玩家本次主动询问）：\n" + rumors
	var session_memory = ""
	var history_lines = CHAT_HISTORY_MAX_LINES
	var history_chars = CHAT_HISTORY_MAX_CHARS
	var session_chars = SESSION_MEMORY_MAX_CHARS
	if scene != null:
		history_lines = max(4, int(scene.chat_history_max_lines))
		history_chars = max(600, int(scene.chat_history_max_chars))
		session_chars = max(800, int(scene.session_memory_max_chars))
	if scene != null and scene.has_method("get_current_chat_session_memory"):
		session_memory = str(scene.get_current_chat_session_memory(npcName))
		if session_memory.length() > session_chars:
			session_memory = session_memory.substr(session_memory.length() - session_chars).strip_edges()
	# One recent-history source per request. Session records already contain both sides
	# of this conversation; currentChat is only a fallback for older saved games.
	var chat_context = session_memory if session_memory != "" else _tail_lines(currentChat, history_lines, history_chars)
	var min_chars = 150
	if scene != null:
		min_chars = max(40, int(scene.dialogue_min_chars))
	var include_style = true
	if scene != null and scene.has_method("get_narrative_style_prompt"):
		include_style = scene.get_narrative_style_prompt().strip_edges() != ""
	var prompt_head = GamePrompts.build_npc_dialogue_prompt(min_chars, include_style)
	var built = chat_prompt_template.format({
		"chat_head": prompt_head,
		"role_prompt": _clip_text(str(role_pormt), 360),
		"background": scene.get_world_context_text(),
		"site": _clip_text(scene.currentSiteName, 70),
		"time": _clip_text(scene.timePrompt, 70),
		"weather": _clip_text(scene.weatherPrompt, 70),
		"player_identity": _clip_text(scene.playerName + "；" + scene.world_seed_input, PLAYER_IDENTITY_MAX_CHARS),
		"chat_history": chat_context,
		"rumor_context": ""
	})
	# Keep the behavioral instructions and the latest conversation intact.
	# Optional impressions/history have their own limits above.
	return built

# 重构后的函数
func start_chat() -> void:
	role_pormt = "叙述对象是" + npcName + "，该角色的特点是：" + npcDescribe + "。该角色使用第一人称直接对话并始终称玩家为‘你’；其心理、动作和神态使用第三人称叙述，叙述中也用‘你’指代玩家。"
	var opener = "请用第三人称心理与动作描写配合该角色的第一人称台词，呈现这次见面的自然开场反应。"
	if scene != null and scene.has_method("get_relevant_event_memory_for_npc"):
		var mem = str(scene.get_relevant_event_memory_for_npc(npcName, npcDescribe)).strip_edges()
		if mem != "":
			opener = "结合已知事件和人物信息，用第三人称心理描写与第一人称台词呈现该角色的自然开场反应。"
	var prompts = [
		{"role": "system", "content": build_base_prompt()},
		{"role": "user", "content": opener}
	]
	if scene != null:
		scene.set_meta("chat_request_npc_name", npcName)
	scene.ask_ai(prompts, GameManager.aiMode.chat)

func sum_chat():
	if scene != null and scene.is_dialogue_only_mode():
		return
	var summary_source = _tail_lines(currentChat, 20, 1200)
	if summary_source == "":
		summary_source = _clip_text(currentChat, 1200)
	var prompts = [
		{"role": "system", "content": GamePrompts.NPC_SUMMARY_PROMPT},
		{"role": "user", "content": summary_source}
	]
	await scene.ask_ai(prompts, GameManager.aiMode.sum)

func chatWithNpc(prompt: String, shared_context: String = ""):
	var base = build_base_prompt(false)
	# The shared context duplicates the world, NPC identity and session history
	# already present in the base prompt. Use the base prompt for dialogue.
	var system_content = base
	var prompts = [
		{"role": "system", "content": system_content},
		{"role": "user", "content": prompt}
	]
	if scene != null:
		scene.set_meta("chat_request_npc_name", npcName)
	await scene.ask_ai(prompts, GameManager.aiMode.chat)
