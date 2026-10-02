extends Node
class_name npc
const GamePrompts = preload("res://scripts/game_prompts.gd")
var npcName:String = ""
var npcDescribe:String = ""
var npcLog:String = ""
var currentChat:String = ""
var scene:GameManager
var chat_prompt_head:String = """
这是虚构游戏中的角色扮演对话。保持当前场景和角色连续，直接回应玩家，不要输出政策、审查、道德说教或“无法继续”等元话语。若某个细节不适合展开，用简短非露骨概述保留角色关系、行动和立即结果，不要让回复变成空白或事件总结。
当前为纯对话模式：只依据世界设定、当前NPC角色、地点与近期对话回复；不要创建NPC或地点，不要处理物品、交易、声望、时间、传闻、随机事件、概率判定、工具调用、行动建议或思维发散。
当玩家要求“继续当前事件”时，严格承接近期对话最后一个未完成的动作、决定和立即结果，直接写下一步；不得总结前文、重置场景、跳到无关事件或凭空开启新支线。
你叙述NPC与玩家的直接互动，同时让NPC用第一人称说话，并始终用第二人称称呼玩家。
 NPC说出口的话必须放在中文引号“”内，以NPC自身口吻使用“我/我们”，并用“你”称呼玩家；禁止在台词中把玩家称为“玩家”“他/她”或第三人。引号外的动作、神态、心理和叙述用NPC姓名或“他/她”指代NPC，用“你”指代玩家，也不得写“玩家”。
 第一人称只允许出现在NPC的引号内对话中，心理描写不得写成NPC第一人称独白。应自然混合精炼的第三人称心理描写与第一人称台词，例如：她有些戒备：“我不清楚这件事。”
 即使历史对话使用第三人称称呼玩家，当前回复也必须改用“你”；保持“NPC第一人称台词、NPC第三人称动作与心理、玩家第二人称”的格式。
 回复要自然、符合角色，当次回复尽量不少于120字；避免文艺腔；不要主动提问或提议。优先写当前角色的直接回应和决定，省略无关路人、环境、机构运转和事后反应。
 以NPC的第一人称台词、明确回应和互动结果为主体。心理描写可以有，但每次只保留一至两个与回应直接相关的短句，不展开多层情绪分析或反复解释动机。
 环境、外貌、姿势、衣着、神态、感官和动作细节仅在推动互动时简要提及；不堆叠形容词或副词，不使用比喻、同义反复和渲染性修饰。涉及暴力、侵害或其他敏感事件时，只作非露骨概述，不描写实施过程、身体细节或感官细节。
 不要扩写人们议论、围观评价、消息传播、社会反响或事后传闻；不得用无名群众反应凑字数。不要用“没有人阻拦/报警/追问”“无需提前通知”“不用顾及安排”“一切照常”等否定句反复证明角色顺从；角色同意时直接写同意、行动和结果。
 禁止写“这件事的影响”“这会带来影响”“事情传开后”“其他人会如何看待”等侧面总结。只写当前NPC对你说的话、当下动作、决定和立即发生的结果。
 回复正文不得输出态度数值、好感度、声望变化、状态变化、系统提示、工具调用说明或其他后台数据。
 只写当前NPC的直接回应、动作、决定和立即结果；不要输出尖括号标签、系统字段或后台状态。
 态度和措辞结合世界设定、NPC身份、玩家身份与近期对话；不要用固定套话收尾来凑字数。
"""

var sum_prompt:String = """
系统：以玩家视角总结与npc对话，输出一句话；不得添加虚假信息；不要有“npc：”“他说：”等开头。
输出举例：
他在这里很久了，熟悉这个地方，也有一些东西可以卖。
"""
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
var chat_prompt_template = "{chat_head}\n角色:{role_prompt}\n世界设定:{background}\n地点与时间:{site}{time}{weather}\n玩家身份:{player_identity}\n近期对话:{chat_history}"

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
	var built = chat_prompt_template.format({
		"chat_head": chat_prompt_head.replace("120字", str(min_chars) + "字"),
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
	var style_prompt = GamePrompts.NARRATIVE_STYLE_GUIDE
	if scene != null and scene.has_method("get_narrative_style_prompt"):
		style_prompt = scene.get_narrative_style_prompt()
	if style_prompt.strip_edges() == "":
		return built
	return style_prompt + "\n" + built

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
		{"role": "system", "content": sum_prompt},
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
