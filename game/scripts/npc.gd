extends Node
class_name npc
var npcName:String = ""
var npcDescribe:String = ""
var npcLog:String = ""
var currentChat:String = ""
var scene:GameManager
var chat_prompt_head:String = """
你以第三人称上帝视角叙述NPC与玩家的互动，同时让NPC用第一人称直接对话。
 NPC说出口的话必须放在中文引号“”内，并以NPC自身口吻使用“我/我们”，可在对话中用“你”称呼玩家；引号外的动作、神态、心理和叙述必须使用第三人称，用NPC姓名或“他/她”指代NPC，用玩家姓名或“玩家”指代玩家。
 第一人称只允许出现在NPC的引号内对话中，心理描写不得写成NPC第一人称独白。应自然混合精炼的第三人称心理描写与第一人称台词，例如：她有些戒备：“我不清楚这件事。”
 即使历史对话的视角不同，当前回复也必须遵循“第一人称对话、第三人称心理与叙述”的格式。
 回复要自然、符合角色，当次回复尽量不少于90字；避免文艺腔；不要主动提问或提议。
 以NPC的第一人称台词、明确回应和互动结果为主体。心理描写可以有，但每次只保留一至两个与回应直接相关的短句，不展开多层情绪分析或反复解释动机。
 环境、外貌、姿势、衣着、神态、感官和动作细节仅在推动互动时简要提及；不堆叠形容词或副词，不使用比喻、同义反复和渲染性修饰。涉及暴力、侵害或其他敏感事件时，只作非露骨概述，不描写实施过程、身体细节或感官细节。
 除非玩家明确询问传闻/消息/舆论，或他人的行为直接介入并改变当前事件，否则不要扩写人们议论、围观评价、消息传播、社会反响或事后传闻；不得用无名群众反应凑字数。
 玩家请求买卖/赠送/接收物品、打听地点或传闻、更新时间等，你可同意或拒绝。
 若本轮包含可执行变化，需在同一轮里保持自然回复文本并调用对应工具函数，不要只返回函数调用。
 只有明确同意才加工具标签；拒绝不加标签。
可用标签：
- <以X的价格卖N件物品> 或 <以总价X卖N件物品>
- <送N件物品名>
- <接受N件物品名>
- <创建路径:地点1-地点2>
- <名字在地点，是一个描述>
- <传闻:主题-内容>
- <声望值+N> / <声望值-N>
 - <设置时间:HH:MM>
 - <离开>
 尖括号工具标签保持原格式，不受第三人称规则影响。
 态度必须结合：玩家身份、声望、NPC身份、近期重要事件、当前会话里刚发生的对话与行动结果；前面刚发生的内容不能降权失效，必须持续影响NPC后续回应与决定；不要用固定套话收尾来凑字数。
"""

var sum_prompt:String = """
系统：以玩家视角总结与npc对话，输出一句话；不得添加虚假信息；不要有“npc：”“他说：”等开头。
输出举例：
他在这里很久了，熟悉这个地方，也有一些东西可以卖。
"""
var role_pormt
const CHAT_HISTORY_MAX_LINES := 12
const CHAT_HISTORY_MAX_CHARS := 700
const SESSION_MEMORY_MAX_CHARS := 760
const EVENT_MEMORY_MAX_CHARS := 240
const IDENTITY_GUIDANCE_MAX_CHARS := 280
const RUMORS_MAX_CHARS := 160
const NPC_LOG_MAX_CHARS := 420
const PLAYER_IDENTITY_MAX_CHARS := 120
const BASE_PROMPT_MAX_CHARS := 2600
# 在类顶部定义提示词模板
var chat_prompt_template = "{chat_head}\n角色:{role_prompt}\n背景:{background}\n时天气:{time}{weather}\n玩家:{player_identity}\n态度:{identity_guidance}{rumor_context}\n印象:{player_impression}\n对话:{chat_history}"

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
			picked.append(_clip_text(row, 110))
	if picked.is_empty():
		return ""
	return _clip_text("\n".join(picked), max_chars)

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
	var event_memory = ""
	var identity_guidance = ""
	var session_memory = ""
	if scene != null and scene.has_method("get_relevant_event_memory_for_npc"):
		event_memory = _clip_text(str(scene.get_relevant_event_memory_for_npc(npcName, npcDescribe)), EVENT_MEMORY_MAX_CHARS)
	if scene != null and scene.has_method("get_identity_attitude_guidance_for_npc"):
		identity_guidance = _clip_text(str(scene.get_identity_attitude_guidance_for_npc(npcName, npcDescribe)), IDENTITY_GUIDANCE_MAX_CHARS)
	if scene != null and scene.has_method("get_current_chat_session_memory"):
		session_memory = _clip_text(str(scene.get_current_chat_session_memory(npcName)), SESSION_MEMORY_MAX_CHARS)
	var history = _tail_lines(currentChat, CHAT_HISTORY_MAX_LINES, CHAT_HISTORY_MAX_CHARS)
	var chat_context = history
	var min_chars = 150
	if scene != null:
		min_chars = max(40, int(scene.dialogue_min_chars))
	if session_memory != "":
		chat_context += "\n会话:\n" + session_memory
	if event_memory != "":
		chat_context += "\n事件:\n" + event_memory
	var built = chat_prompt_template.format({
		"chat_head": chat_prompt_head.replace("90字", str(min_chars) + "字"),
		"role_prompt": role_pormt,
		"background": _clip_text(scene.background, 420),
		"time": _clip_text(scene.timePrompt, 70),
		"weather": _clip_text(scene.weatherPrompt, 70),
		"player_identity": _clip_text(scene.playerName + "；" + scene.world_seed_input, PLAYER_IDENTITY_MAX_CHARS),
		"identity_guidance": identity_guidance,
		"player_impression": _compact_npc_log(),
		"chat_history": chat_context,
		"rumor_context": rumor_context
	})
	return _clip_text(built, BASE_PROMPT_MAX_CHARS)

# 重构后的函数
func start_chat() -> void:
	role_pormt = "叙述对象是" + npcName + "，该角色的特点是：" + npcDescribe + "。该角色使用第一人称直接对话，其心理、动作和神态使用第三人称叙述。"
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
	var summary_source = _tail_lines(currentChat, 20, 1200)
	if summary_source == "":
		summary_source = _clip_text(currentChat, 1200)
	var prompts = [
		{"role": "system", "content": sum_prompt},
		{"role": "user", "content": summary_source}
	]
	await scene.ask_ai(prompts, GameManager.aiMode.sum)

func chatWithNpc(prompt: String, shared_context: String = ""):
	var base = build_base_prompt(_is_rumor_query(prompt))
	var system_content = base if shared_context == "" else base + "\n" + shared_context
	var prompts = [
		{"role": "system", "content": system_content},
		{"role": "user", "content": prompt}
	]
	if scene != null:
		scene.set_meta("chat_request_npc_name", npcName)
	await scene.ask_ai(prompts, GameManager.aiMode.chat)
