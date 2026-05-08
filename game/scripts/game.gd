extends Node
class_name GameManager

# UI引用
@onready var input_text_edit = %InputTextEdit
@onready var send_button = %SendButton
@onready var response_label = %ResponseLabel
@onready var http_request = $HTTPRequest
@onready var dialogue_container = %DialogueContainer
@onready var dialogue_input = %DialogueTextEdit
@onready var dialogue_button = %DialogueButton
@onready var save_button = %SaveButton
@onready var load_button = %LoadButton

# 常量与枚举
enum worldState {explore, chat}
enum aiMode {init_background,init_env,explore, chat, sum, tools, action}

# 配置变量
var chat_url = "http://127.0.0.1:5000/chat"
var agent_url = "http://127.0.0.1:5000/agent"
var image_api_url = "http://localhost:5000/generate_image"

const PICTURE_DIR = "D:/毕设/worldSim/game/picture/"
const SESSION_RESOURCE_DIR = PICTURE_DIR + "session/"
const SCENE_IMG_DIR = SESSION_RESOURCE_DIR + "scenes/"
const ITEM_IMG_DIR = SESSION_RESOURCE_DIR + "items/"
const ITEM_PROFILE_DIR = SESSION_RESOURCE_DIR + "item_profiles/"
const SAVE_DIR = "D:/毕设/worldSim/game/saves/"
const SAVE_SLOT_DIR = SAVE_DIR + "slot_1/"
const SAVE_RESOURCE_DIR = SAVE_SLOT_DIR + "resources/"
const SAVE_SCENE_IMG_DIR = SAVE_RESOURCE_DIR + "scenes/"
const SAVE_ITEM_IMG_DIR = SAVE_RESOURCE_DIR + "items/"
const SAVE_ITEM_PROFILE_DIR = SAVE_RESOURCE_DIR + "item_profiles/"
const SAVE_FILE = SAVE_SLOT_DIR + "save.json"

var pending_site_update: bool = false
var pending_img_prompt: String = ""
var pending_img_site: String = ""
var inflight_img_site: String = ""
var explore_needs_retry: bool = false
var site_loading_lock: bool = false
var event_flow_lock: bool = false
var last_crime_event_context: String = ""
var last_action_input: String = ""
var last_dialogue_input: String = ""
var preferred_input_focus: String = "action"
var chat_session_record_limit: int = 120
var pending_action_confirm: Dictionary = {}
var important_event_memories: Array = []
var current_chat_session_npc: String = ""
var current_chat_session_records: Array = []
var pending_explore_target: String = ""
var explore_route_retry_count: int = 0
var bg_debug_enabled: bool = true
var has_saved_in_session: bool = false
var dead_npc_names: Array = []
var dialogue_min_chars: int = 90
var action_narration_min_chars: int = 90
var prompt_session_memory_max_lines: int = 24
var prompt_session_memory_max_chars: int = 1800
var prompt_action_context_max_chars: int = 2200
var output_mode_debug_enabled: bool = false
var output_length_button: Button
var min_chars_dialog: AcceptDialog
var dialogue_min_chars_spin: SpinBox
var action_min_chars_spin: SpinBox
var img_watchdog_seq: int = 0

# 游戏数据
var sites: Dictionary
var npcs: Dictionary
var items: Dictionary
var rumors:Dictionary
var siteImgs: Dictionary
var itemProfiles: Dictionary = {}
#var playerName: String = "阿尔的秘宝"
var playerName: String = "武汉理工大学2022级学生戴子洋"
var world_seed_input: String = ""
var currentSiteName: String
var currentNpc: npc
var newNpc: npc
var currentState = worldState.explore
var currentMode = aiMode.explore
var nowtime = 500

#环境参数
var envDic:Dictionary
var timePrompt:String = ""
var weatherPrompt:String = ""

#玩家状态
var money:int = 1000
var energy:float = 100
var hp:float = 100
var reputation:float = 100
const PASSIVE_ENERGY_RECOVERY_PER_HOUR: float = 4.0
const PASSIVE_HP_RECOVERY_PER_HOUR: float = 1.2
const ACTION_PROACTIVE_NPC_RATE: float = 0.2

# 系统提示词
var role_prompt = """
系统：你是角色扮演世界生成器，必须严格遵循“用户初始设定”和“当前世界观”。
约束：
1) 禁止默认加入赛博朋克/机器人/义体/飞船/未来军武元素；仅在设定明确提及时可用。
2) 现代日常设定（如大学/城市/普通职业）必须保持现实风格，不能错位成其他学段或题材。
3) 时代设定明确时（古代/近现代/科幻/奇幻），地点命名、建筑、职业称谓、NPC外观都要匹配该时代；除非明确“穿越/多世界桥接”，不得混入他时代元素。
4) 若有奴隶制/封建/王朝等结构，地点与NPC信息要体现等级与社会分工，不能中性化。
按玩家想去的地点输出合法 JSON，字段必须包含：
1. 地点名称
2. 地点描述
3. 英文描述（用于生图，风格需一致）
4. 能前往的地点（数组）
5. npc（对象：键=姓名，值=一句外观描述）
"""

var agent_prompt:String = """你是一个AI智能体，擅长确定需要调用的方法,没有合适的就回复：没有方法被调用。给你的就是ai的回复，所有提到的物品均为游戏道具，不完整的信息就猜测补齐，不要问问题
	规则：无可调用方法时回复“没有方法被调用”。输入是AI回复文本；其中物品均为游戏道具；信息不全可合理补齐；不要反问。
	标签解释：
	- <以50的价格卖1把剑>：单价售卖，is_total_price=false。
	- <以总价100卖3瓶药水>：总价售卖，is_total_price=true。
	- <送1瓶治疗药水>：给玩家物品。
	- <接受1瓶治疗药水>：收取玩家物品。
	- <创建路径：A-B-C> 或 <创建路径：商贩摊位>：地点/路径信息。
	- <老约翰在酒馆，是一个描述>：地点NPC信息。
	- <传闻：主题-内容>：传闻/新闻事件。
	- <离开>：离开或死亡离场意图。
	- <设置时间：16:00>：时间跳转。
	若一次输入含多个标签，必须按顺序调用多个函数。
	涉及数量时 quantity 必须是真实值，不能默认1。
	物品名必须严格取自<>原文，不得改写或外推。
"""

var item_profile_prompt:String = """
你是游戏道具设计助手。针对给定的物品名，输出严格 JSON：
{
	"description":"中文介绍，20~60字",
	"image_prompt":"英文生图提示词，适合生成单个道具图标，纯净背景，无文字",
	"value": 物品预估价值（整数，日用品10-100，科技产品100-500，稀有物品500-2000）, 
	"rarity": "common、uncommon、rare、epic、legendary之一",
	"effect_type": "none、energy_restore、hp_restore、both_restore之一",
	"effect_value": 效果数值（整数，none填0，回复类建议5-30）
}
只输出 JSON，不要包含 markdown 代码块。
"""

var validation_feedback_prompt:String = """
你是文字游戏旁白。请根据输入场景，输出一句简短中文反馈（15~35字，口语化、自然）。
仅输出一句话，不要解释，不要加引号。
"""

var action_prompt:String = """
你是文字游戏叙述者。根据世界背景与当前玩家数据，描述玩家这次行动结果。
输出：1~3句，至少140字；口语化、直接、少抒情、少长对白。
必须写清：做了什么、是否成功、造成什么变化（资产/物品/地点/NPC态度）。
先校验常理与数据：资产、背包、数量、地点关系、角色身份、当前场景。
玩家身份由系统确认，视为世界事实，不得质疑/否认/重置。
涉及NPC态度时，必须结合玩家身份、声望、NPC身份、历史重要事件（敬畏/尊重/戒备/敌意等）。
若不成立（钱不够/缺物品/地点不合理/场景不可执行等），只输出失败，不得伪造成功，不得添加交易或物品变更指令。
若成功并创建了地点或NPC，叙述中要明确“找到了该地点或NPC”；失败时不得添加地点创建指令。
若成立且有可执行变化，在叙述末追加一个或多个<>指令：
1) 交易出售：<以50的价格卖1把剑> 或 <以总价100卖3瓶药水>
2) 获得物品：<送1瓶治疗药水>
3) 交出/消耗物品：<接受1瓶治疗药水>
4) 新地点路径：<创建路径：学校-小卖部>
5) 新NPC情报：<老张在小卖部，是一个戴帽子的中年店员>
6) 传闻：<传闻：主题-一句话内容>
7) 声望变化：<声望值-13> 或 <声望值+8>
8) 时间变化：<设置时间：16:00>
9) 离开：<离开>
10) 违规行为：<犯罪：偷窃>
11) 前往地点（行动为去某处且可成功到达时）：<前往:地点名>
工具指令仅用<>附在句末，不要解释。
"""

var ai_busy: bool = false
var _text_update_seq: int = 0
var _active_text_tweens: Dictionary = {}
var lock_debug_enabled: bool = false
const LOG_LABEL_SCENE := preload("res://fabs/log_rich_text_label.tscn")
var max_visible_logs: int = 180
var _process_strip_regex := RegEx.new()
var _process_newline_regex := RegEx.new()

func _log_lock_state(tag: String) -> void:
	if !lock_debug_enabled:
		return
	var has_event_panel = _has_active_event_panel()
	var text_busy = !_active_text_tweens.is_empty()
	print("[LOCK_DEBUG][" + tag + "] state=" + str(currentState) + ", ai_busy=" + str(ai_busy) + ", event_flow_lock=" + str(event_flow_lock) + ", site_loading_lock=" + str(site_loading_lock) + ", has_event_panel=" + str(has_event_panel) + ", text_busy=" + str(text_busy))

# ==================== 生命周期函数 ====================
func _ready():
	_ensure_process_regex_ready()
	send_button.connect("pressed", _on_send_button_pressed)
	dialogue_button.connect("pressed", _on_dialogue_button_pressed)
	save_button.connect("pressed", save_game)
	load_button.connect("pressed", load_game)
	if %npcIcon is Control:
		%npcIcon.custom_minimum_size.x = 0
		(%npcIcon as Control).mouse_filter = Control.MOUSE_FILTER_STOP
		(%npcIcon as Control).gui_input.connect(_on_npc_icon_gui_input)
	_prepare_session_resource_dir()
	dialogue_container.visible = false
	# %backgroundImg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 原先使用 Nearest 过滤会强化像素感，这里改回线性以更接近原图显示。
	%backgroundImg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# %backgroundImg.material = preload("res://assets/asciiShader.gdshader")
	# 关闭背景图的 ASCII/后处理材质，直接显示生成原图。
	%backgroundImg.material = null
	changeTextTo(%siteName, "未定位")
	player_update()
	_setup_output_mode_controls()
	_apply_interaction_locks()
	call_deferred("_focus_active_input")

func _setup_output_mode_controls() -> void:
	if response_label == null:
		return
	if output_length_button != null and is_instance_valid(output_length_button):
		return
	output_length_button = Button.new()
	output_length_button.name = "OutputLengthButton"
	output_length_button.text = "字数"
	output_length_button.custom_minimum_size = Vector2(52, 26)
	output_length_button.anchors_preset = 1
	output_length_button.anchor_left = 1.0
	output_length_button.anchor_right = 1.0
	output_length_button.offset_left = -60.0
	output_length_button.offset_top = 4.0
	output_length_button.offset_right = -4.0
	output_length_button.offset_bottom = 30.0
	output_length_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	output_length_button.pressed.connect(_on_output_length_button_pressed)
	response_label.add_child(output_length_button)
	min_chars_dialog = AcceptDialog.new()
	min_chars_dialog.title = "设置输出字数"
	var box = VBoxContainer.new()
	var dialogue_tip = Label.new()
	dialogue_tip.text = "对话最小字数"
	dialogue_min_chars_spin = SpinBox.new()
	dialogue_min_chars_spin.min_value = 40
	dialogue_min_chars_spin.max_value = 2000
	dialogue_min_chars_spin.step = 10
	dialogue_min_chars_spin.value = dialogue_min_chars
	var action_tip = Label.new()
	action_tip.text = "行动最小字数"
	action_min_chars_spin = SpinBox.new()
	action_min_chars_spin.min_value = 40
	action_min_chars_spin.max_value = 2000
	action_min_chars_spin.step = 10
	action_min_chars_spin.value = action_narration_min_chars
	box.add_child(dialogue_tip)
	box.add_child(dialogue_min_chars_spin)
	box.add_child(action_tip)
	box.add_child(action_min_chars_spin)
	min_chars_dialog.add_child(box)
	add_child(min_chars_dialog)
	min_chars_dialog.confirmed.connect(_on_min_chars_dialog_confirmed)

func _on_output_length_button_pressed() -> void:
	if min_chars_dialog == null:
		return
	if dialogue_min_chars_spin != null:
		dialogue_min_chars_spin.value = dialogue_min_chars
	if action_min_chars_spin != null:
		action_min_chars_spin.value = action_narration_min_chars
	min_chars_dialog.popup_centered(Vector2i(360, 180))

func _on_min_chars_dialog_confirmed() -> void:
	if dialogue_min_chars_spin == null or action_min_chars_spin == null:
		return
	dialogue_min_chars = clamp(int(dialogue_min_chars_spin.value), 40, 2000)
	action_narration_min_chars = clamp(int(action_min_chars_spin.value), 40, 2000)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_handle_exit_cleanup()

var background:String

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not ai_busy:
			if dialogue_container.visible and dialogue_input.has_focus():
				_on_dialogue_button_pressed()
			elif input_text_edit.has_focus():
				_on_send_button_pressed()

# ==================== 游戏状态管理 ====================
func changeStateInto(stateToChange: worldState):
	if currentState == worldState.chat:
		var switching_npc = stateToChange == worldState.chat and currentNpc != null and newNpc != null and str(currentNpc.npcName) != str(newNpc.npcName)
		changeTextTo(response_label, "你结束了与" + currentNpc.npcName + "的对话。", 100)
		await currentNpc.sum_chat()
		if stateToChange != worldState.chat or switching_npc:
			_end_chat_session()

	match stateToChange:
		worldState.chat:
			create_tween().tween_property(%npcIcon, "custom_minimum_size:x", 300, 0.2)
			if currentNpc != null:
				currentNpc.queue_free()
			currentNpc = newNpc
			_start_chat_session(str(currentNpc.npcName))
			currentNpc.start_chat()
			changeTextTo(response_label, "你走近了" + currentNpc.npcName, 100)
			changeTextTo(%speakerNameLabel, playerName, 100)
			addLog("你开始与" + currentNpc.npcName + "交谈")
			dialogue_container.visible = true
		worldState.explore:
			create_tween().tween_property(%npcIcon, "custom_minimum_size:x", 0, 0.2)
			changeTextTo(%speakerNameLabel, playerName, 100)
			dialogue_container.visible = false
			if currentState == worldState.chat and !currentSiteName.is_empty():
				site_update()
	
	currentState = stateToChange
	refresh_interaction_locks()
	call_deferred("_focus_active_input")

func _force_exit_chat_runtime() -> void:
	if currentNpc != null and is_instance_valid(currentNpc):
		currentNpc.queue_free()
	if newNpc != null and is_instance_valid(newNpc) and newNpc != currentNpc:
		newNpc.queue_free()
	currentNpc = null
	newNpc = null
	currentState = worldState.explore
	dialogue_container.visible = false
	dialogue_input.text = ""
	last_dialogue_input = ""
	last_action_input = ""
	last_crime_event_context = ""
	_end_chat_session()
	clear_children(%event)
	_set_event_flow_lock(false)
	refresh_interaction_locks()

func _start_chat_session(npc_name: String) -> void:
	var n = npc_name.strip_edges()
	if n == "":
		current_chat_session_npc = ""
		current_chat_session_records = []
		return
	if current_chat_session_npc != n:
		current_chat_session_npc = n
		current_chat_session_records = []

func _end_chat_session() -> void:
	current_chat_session_npc = ""
	current_chat_session_records = []

func _record_current_chat_session(kind: String, speaker: String, text: String) -> void:
	if currentState != worldState.chat or currentNpc == null:
		return
	var current_name = str(currentNpc.npcName).strip_edges()
	if current_name == "":
		return
	if current_chat_session_npc == "":
		_start_chat_session(current_name)
	if current_chat_session_npc != current_name:
		return
	var plain = process_string(str(text)).strip_edges()
	if plain == "":
		return
	var rec = "[" + kind + "]" + speaker + "：" + plain
	if !current_chat_session_records.is_empty() and str(current_chat_session_records[current_chat_session_records.size() - 1]) == rec:
		return
	current_chat_session_records.append(rec)
	if current_chat_session_records.size() > chat_session_record_limit:
		current_chat_session_records = current_chat_session_records.slice(current_chat_session_records.size() - chat_session_record_limit, current_chat_session_records.size())

func get_current_chat_session_memory(npc_name: String = "") -> String:
	var target_name = npc_name.strip_edges()
	if target_name != "" and target_name != current_chat_session_npc:
		return ""
	if current_chat_session_records.is_empty():
		return ""
	var lines: Array = []
	var start_idx = max(0, current_chat_session_records.size() - prompt_session_memory_max_lines)
	for i in range(start_idx, current_chat_session_records.size()):
		var row_text = str(current_chat_session_records[i]).strip_edges()
		if row_text == "":
			continue
		lines.append("- " + _clip_prompt_text(row_text, 150))
	if lines.is_empty():
		return ""
	var joined = "以下是当前会话中刚发生且必须延续影响的内容：\n" + "\n".join(lines)
	return _clip_prompt_text(joined, prompt_session_memory_max_chars)

func _clip_prompt_text(text: String, max_chars: int) -> String:
	var src = str(text).strip_edges()
	if max_chars <= 0:
		return ""
	if src.length() <= max_chars:
		return src
	var keep = max(8, max_chars - 3)
	return src.substr(0, keep).strip_edges() + "..."

func _clear_all_npc_dialogue_memory() -> void:
	for npc_name in npcs.keys():
		var npc_data = npcs[npc_name]
		if npc_data is Dictionary:
			npc_data["npc_log"] = []
			npcs[npc_name] = npc_data

# ==================== 地点导航 ====================
func _get_site_data(site_name: String) -> Dictionary:
	if !sites.has(site_name):
		return {}
	var data = sites[site_name]
	if data is Dictionary:
		return data
	var disk_site = _load_site_json(site_name)
	if !disk_site.is_empty():
		sites[site_name] = disk_site
		return disk_site
	return {}

func _build_scene_image_prompt(site_name: String, site_data: Dictionary) -> String:
	var english_prompt = str(site_data.get("英文描述", "")).strip_edges()
	var cn_desc = str(site_data.get("地点描述", "")).strip_edges()
	var world_hint = background.strip_edges()
	var style_sig = _detect_setting_style_signals()
	var style_guard = _build_setting_consistency_guard_text(style_sig)
	var location_hint = _build_location_visual_hint(site_name, cn_desc)
	var desc_anchor = _build_cn_desc_visual_anchor(cn_desc)
	var prompt_parts: Array = [
		"cinematic environment faithful to world setting",
		"daylight natural color",
		"no text, no watermark",
		"location:" + site_name
	]
	if style_guard != "":
		prompt_parts.append("style guard: " + style_guard)
	if world_hint != "":
		prompt_parts.append("world context: " + world_hint.left(120))
	if location_hint != "":
		prompt_parts.append(location_hint)
	if cn_desc != "":
		prompt_parts.append("narrative anchor: " + cn_desc.left(180))
	if desc_anchor != "":
		prompt_parts.append("must include visual elements: " + desc_anchor)
	if english_prompt != "":
		prompt_parts.append(english_prompt)
		if cn_desc != "":
			prompt_parts.append("if english prompt conflicts with narrative anchor, follow narrative anchor first")
	elif cn_desc != "":
		prompt_parts.append("scene detail: " + cn_desc.left(180))
	else:
		prompt_parts.append("scene detail: " + site_name)
	if site_data.has("npc") and site_data["npc"] is Dictionary:
		var npc_keys = (site_data["npc"] as Dictionary).keys()
		if !npc_keys.is_empty():
			if bool(style_sig.get("ancient", false)) and !bool(style_sig.get("bridge", false)):
				prompt_parts.append("people style: pre-modern attire and social hierarchy")
			elif bool(style_sig.get("scifi", false)) or bool(style_sig.get("cyber", false)):
				prompt_parts.append("people style: futuristic inhabitants consistent with lore")
			else:
				prompt_parts.append("people style: inhabitants fitting current world setting")
	if cn_desc != "":
		prompt_parts.append("keep architecture, facilities and props strictly aligned with narrative anchor")
	prompt_parts.append("strictly match this location and world era, avoid cross-era contamination")
	return ", ".join(prompt_parts)

func _build_location_visual_hint(site_name: String, cn_desc: String) -> String:
	var merged = (site_name + " " + cn_desc).strip_edges()
	if merged.find("食堂") != -1:
		return "communal dining hall, food counters, tables, era-consistent props"
	if merged.find("图书馆") != -1:
		return "library interior, bookshelves, reading area, quiet atmosphere"
	if merged.find("宿舍") != -1:
		return "residential quarters, corridor doors, daily-life details matching era"
	if merged.find("操场") != -1 or merged.find("体育") != -1:
		return "training ground or sports field, open area with active movement"
	if merged.find("教室") != -1 or merged.find("教学楼") != -1:
		return "learning hall interior, teaching space, era-appropriate furniture"
	if merged.find("超市") != -1 or merged.find("小卖部") != -1:
		return "general goods shop or market stall, goods display aligned with era"
	if merged.find("校门") != -1:
		return "main gate area, checkpoints and passers-by matching setting"
	return "architecture and props consistent with current world setting and era"

func _build_cn_desc_visual_anchor(cn_desc: String) -> String:
	var desc = cn_desc.strip_edges()
	if desc == "":
		return ""
	var keyword_map = {
		"跑道": "running track",
		"足球场": "football field",
		"篮球场": "basketball court",
		"看台": "stadium stands",
		"草坪": "open grass field",
		"健身": "sports training atmosphere",
		"图书馆": "library interior",
		"书架": "bookshelves",
		"自习": "study desks and lamps",
		"食堂": "cafeteria serving counters",
		"宿舍": "dormitory corridor",
		"教学楼": "teaching building corridor",
		"教室": "classroom interior",
		"超市": "convenience store shelves",
		"小卖部": "small general goods shop",
		"王宫": "royal palace complex",
		"宫殿": "palace interior and court symbols",
		"城墙": "city wall and gate defense",
		"铁匠": "blacksmith forge and anvils",
		"集市": "open market stalls",
		"奴隶": "servitude marks and social hierarchy",
		"庄园": "manor estate structure",
		"神殿": "temple architecture",
		"蒸汽": "steam machinery pipes and brass structure"
	}
	var anchors: Array = []
	for key in keyword_map.keys():
		if desc.find(str(key)) != -1:
			var anchor = str(keyword_map[key])
			if !anchors.has(anchor):
				anchors.append(anchor)
	return ", ".join(anchors)

func _build_location_fallback_description(location_name: String, from_site_name: String = "") -> String:
	var n = location_name.strip_edges()
	if n == "":
		return "你来到了一处新的地点。"
	if n.find("食堂") != -1:
		return "你来到" + n + "。热气和饭香交织，来往的人声让这里显得忙碌而真实。"
	if n.find("图书馆") != -1:
		return "你来到" + n + "。高书架与阅读区安静有序，空气里只有轻微翻页声。"
	if n.find("宿舍") != -1:
		return "你来到" + n + "。居住区的走廊延伸开来，生活痕迹随处可见。"
	if n.find("操场") != -1 or n.find("体育") != -1:
		return "你来到" + n + "。开阔场地上有人训练，风里带着土石与草木气息。"
	if n.find("教室") != -1 or n.find("教学楼") != -1:
		return "你来到" + n + "。讲学与讨论的痕迹还留在空气里，四周带着秩序感。"
	if n.find("超市") != -1 or n.find("小卖部") != -1:
		return "你来到" + n + "。铺面里货物陈列紧凑，交易声此起彼伏。"
	if from_site_name.strip_edges() != "":
		return "你来到" + n + "。这里与" + from_site_name + "相连，环境细节逐渐清晰起来。"
	return "你来到" + n + "。周围布局和气氛有了明显变化，这里看起来是可继续探索的区域。"

func _detect_setting_style_signals() -> Dictionary:
	var t = (world_seed_input + " " + background).strip_edges()
	return {
		"ancient": _contains_any_keyword(t, ["古代", "王朝", "朝廷", "封建", "奴隶制", "王国", "帝国", "城邦"]),
		"modern": _contains_any_keyword(t, ["现代", "当代", "校园", "大学", "城市", "公司", "地铁", "工业化"]),
		"scifi": _contains_any_keyword(t, ["科幻", "未来", "太空", "星际", "机甲", "机器人", "空间站"]),
		"cyber": _contains_any_keyword(t, ["赛博", "义体", "霓虹", "黑客", "芯片植入"]),
		"fantasy": _contains_any_keyword(t, ["魔法", "精灵", "神殿", "巫师", "异界", "巨龙"]),
		"slavery": _contains_any_keyword(t, ["奴隶制", "奴隶主", "奴隶", "庄园主"]),
		"bridge": _contains_any_keyword(t, ["穿越", "平行宇宙", "时空", "多元宇宙", "异世界桥接"])
	}

func _build_setting_consistency_guard_text(sig: Dictionary) -> String:
	var lines: Array = []
	if bool(sig.get("ancient", false)) and !bool(sig.get("bridge", false)):
		lines.append("ancient pre-industrial era only; forbid modern campus, cyberpunk neon, futuristic tech")
	if bool(sig.get("slavery", false)):
		lines.append("highlight hierarchical social structure and slave-based roles")
	if bool(sig.get("modern", false)) and !bool(sig.get("bridge", false)) and !bool(sig.get("scifi", false)):
		lines.append("modern realistic style; avoid ancient court language and sci-fi facilities")
	if bool(sig.get("scifi", false)) or bool(sig.get("cyber", false)):
		lines.append("futuristic sci-fi style allowed only when stated in world setting")
	if bool(sig.get("fantasy", false)) and !bool(sig.get("bridge", false)):
		lines.append("fantasy motif only; avoid modern institutional style")
	return "; ".join(lines)

func _extract_route_candidates_from_site_json(json_dic: Dictionary) -> Array:
	var route_keys = ["能前往的地点", "可前往地点", "可前往的地点", "前往地点", "可去地点", "可到达地点", "邻近地点", "连接地点"]
	var candidates: Array = []
	for key in route_keys:
		if !json_dic.has(key):
			continue
		var raw_val = json_dic.get(key)
		var raw_list: Array = []
		if raw_val is Array:
			raw_list = raw_val
		elif raw_val is String:
			var merged = str(raw_val)
			var splitters = ["\r\n", "\n", "，", ",", "、", "；", ";", "|", "/"]
			for sp in splitters:
				merged = merged.replace(sp, ",")
			raw_list = merged.split(",", false)
		for raw_name in raw_list:
			var route_name = str(raw_name).strip_edges()
			if route_name == "":
				continue
			if !candidates.has(route_name):
				candidates.append(route_name)
	return candidates

func _resolve_site_alias(site_name: String) -> String:
	var cleaned = site_name.strip_edges()
	if cleaned == "":
		return ""
	if sites.has(cleaned):
		return cleaned
	for key in sites.keys():
		var existing = str(key).strip_edges()
		if existing == "":
			continue
		if cleaned == existing:
			return existing
		if min(cleaned.length(), existing.length()) >= 2 and (cleaned.ends_with(existing) or existing.ends_with(cleaned)):
			return existing
	return cleaned

func _bg_debug(msg: String) -> void:
	if !bg_debug_enabled:
		return
	print("[BG_DEBUG] " + msg)
	addLog("<BG_DEBUG> " + msg)

func goto(where: String):
	where = _resolve_site_alias(str(where).strip_edges())
	if where == "":
		changeTextTo(%siteName, "未定位")
		return
	changeTextTo(%siteName, where)
	await changeStateInto(GameManager.worldState.explore)
	_bg_debug("goto start, where=" + where + ", current=" + currentSiteName)
	# 磁盘缓存恢复：内存中没有但磁盘JSON存在时补充
	if !sites.has(where) or !(sites[where] is Dictionary) or !sites[where].has("地点描述"):
		var disk_site = _load_site_json(where)
		if !disk_site.is_empty():
			sites[where] = disk_site
			_bg_debug("site json cache hit for " + where)
	var site_data = _get_site_data(where)
	var has_description = !site_data.is_empty() and str(site_data.get("地点描述", "")).strip_edges() != ""
	var has_routes = false
	if site_data.has("能前往的地点") and site_data["能前往的地点"] is Array:
		for raw_route in site_data["能前往的地点"]:
			var normalized_route = _resolve_site_alias(str(raw_route).strip_edges())
			if normalized_route != "" and normalized_route != where:
				has_routes = true
				break
	if has_description and has_routes:
		print("地点已经存在")
		currentSiteName = where
		var has_bg := false
		if siteImgs.has(where):
			%backgroundImg.texture = siteImgs[where]
			has_bg = true
		else:
			var cached = _load_image_png(SCENE_IMG_DIR, where)
			if cached != null:
				%backgroundImg.texture = cached
				siteImgs[where] = cached
				has_bg = true
				_bg_debug("scene image cache hit for " + where)
		if !has_bg:
			pending_site_update = true
			var scene_prompt = _build_scene_image_prompt(where, site_data)
			_bg_debug("scene image cache miss for " + where + ", prompt_len=" + str(scene_prompt.length()))
			if scene_prompt != "":
				site_update(false, false, false)
				_set_site_loading_lock(true)
				gen_img(scene_prompt, where)
				return
			else:
				pending_site_update = false
				_set_site_loading_lock(false)
		site_update()
	else:
		changeTextTo(response_label, "正在探索" + where + "...", 8)
		pending_explore_target = where
		explore_route_retry_count = 0
		var prompts = [
			{"role":"system","content": _build_explore_system_prompt()},
			{"role":"user","content": "我想去"+where}]
		explore_needs_retry = false
		await ask_ai(prompts, aiMode.explore)
		if explore_needs_retry and currentSiteName != "":
			explore_needs_retry = false
			var retry_target = currentSiteName
			_bg_debug("goto() retry explore for " + retry_target)
			var retry_prompts = [
				{"role":"system","content": _build_explore_system_prompt() + "\n再次强调：只能输出JSON，且\"能前往的地点\"不得为空。"},
				{"role":"user","content": "我想去" + retry_target}
			]
			await ask_ai(retry_prompts, aiMode.explore)
		explore_needs_retry = false
		var discovered_site = _resolve_site_alias(currentSiteName)
		if discovered_site == "":
			discovered_site = where
		currentSiteName = discovered_site
		var new_site = _get_site_data(discovered_site)
		if !new_site.is_empty():
			var has_bg_new := false
			if siteImgs.has(discovered_site):
				%backgroundImg.texture = siteImgs[discovered_site]
				has_bg_new = true
			else:
				var cached_new = _load_image_png(SCENE_IMG_DIR, discovered_site)
				if cached_new != null:
					%backgroundImg.texture = cached_new
					siteImgs[discovered_site] = cached_new
					has_bg_new = true
			if has_bg_new:
				pending_site_update = false
				_set_site_loading_lock(false)
				site_update()
				return
			var prompt = _build_scene_image_prompt(discovered_site, new_site)
			if prompt != "":
				site_update(false, false, false)
				pending_site_update = true
				_set_site_loading_lock(true)
				gen_img(prompt, discovered_site)
			else:
				pending_site_update = false
				_set_site_loading_lock(false)
				site_update()
		else:
			pending_site_update = false
			_set_site_loading_lock(false)
			changeTextTo(response_label, "无法探索「" + where + "」，请检查角色与场景设定后重试。")

func site_update(show_description: bool = true, unlock_after: bool = true, add_arrival_log: bool = true):
	var site_data = _get_site_data(currentSiteName)
	if site_data.is_empty():
		if unlock_after:
			_set_site_loading_lock(false)
		return
	var display_routes: Array = []
	if !site_data.has("能前往的地点") or !(site_data["能前往的地点"] is Array):
		site_data["能前往的地点"] = []
	if (site_data["能前往的地点"] as Array).is_empty() and sites.size() > 1:
		for key in sites.keys():
			var candidate = str(key)
			if candidate != "" and candidate != currentSiteName and !(site_data["能前往的地点"] as Array).has(candidate):
				(site_data["能前往的地点"] as Array).append(candidate)
				if (site_data["能前往的地点"] as Array).size() >= 6:
					break
	for route_name in site_data.get("能前往的地点", []):
		var normalized_route = _resolve_site_alias(str(route_name).strip_edges())
		if normalized_route != "" and normalized_route != currentSiteName and !display_routes.has(normalized_route):
			display_routes.append(normalized_route)
	if display_routes.is_empty() and currentSiteName != "":
		display_routes.append(currentSiteName)
	_save_site_json(currentSiteName, site_data)
	changeTextTo(%siteName, currentSiteName)
	if show_description and currentState != worldState.chat and !event_flow_lock:
		changeTextTo(response_label, str(site_data.get("地点描述", "")),15)
	clear_children(%site_buttons)
	clear_children(%npc_buttons)
	for i in display_routes:
		var new_site_button = load("res://fabs/site_button.tscn").instantiate() as siteButton
		new_site_button.siteName = i
		%site_buttons.add_child(new_site_button)

	for i in site_data.get("npc", {}):
		if dead_npc_names.has(i):
			continue
		if i not in npcs:
			npcs[i] = {"npc_log": [], "特征": "", "important_events": []}
		if !npcs[i].has("npc_log") or !(npcs[i]["npc_log"] is Array):
			npcs[i]["npc_log"] = []
		if !npcs[i].has("important_events") or !(npcs[i]["important_events"] is Array):
			npcs[i]["important_events"] = []
		npcs[i]["npc_describe"] = site_data.get("npc", {}).get(i, "")
		var new_npc_button = load("res://fabs/npc_button.tscn").instantiate() as npcButton
		new_npc_button.npcName = i
		%npc_buttons.add_child(new_npc_button)
	if add_arrival_log:
		addLog("你抵达了" + currentSiteName)
	if unlock_after:
		_set_site_loading_lock(false)

func player_update():
	%moneyBar.target_value = str(money)
	%energy.target_value = energy
	%hp.target_value = hp
	%reputation.target_value = reputation

# 定义可用的工具函数
var tools = [
	{
		"type": "function",
		"function": {
			"name": "initiate_transaction",
			"description": "想要卖给玩家某件物品",
			"parameters": {
				"type": "object",
				"properties": {
					"item_name": {"type": "string", "description": "物品名称"},
					"quantity": {"type": "integer", "description": "数量，默认为1"},
					"price": {"type": "integer", "description": "价格数值（单价或总价，由is_total_price决定）"},
					"is_total_price": {"type": "boolean", "description": "true表示price为总价，false（默认）表示price为单价"}
				},
				"required": ["item_name", "quantity", "price"]
			}
		}
	},
	{
		"type": "function",
		"function": {
			"name": "got_items",
			"description": "想要送给玩家某件物品",
			"parameters": {
				"type": "object",
				"properties": {
					"item_name": {"type": "string", "description": "物品名称"},
					"quantity": {"type": "integer", "description": "数量，默认为1"}
				},
				"required": ["item_name", "quantity"]
			}
		}
	},
	{
		"type": "function",
		"function": {
			"name": "consume_items",
			"description": "接受了玩家的某件物品或消耗了玩家的某件物品",
			"parameters": {
				"type": "object",
				"properties": {
					"item_name": {"type": "string", "description": "物品名称"},
					"quantity": {"type": "integer", "description": "数量，默认为1"}
				},
				"required": ["item_name", "quantity"]
			}
		}
	},
	{
		"type": "function",
		"function": {
			"name": "create_location",
			"description": "提到了某个地点或到达某个地方的一系列地点的路径",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "由一系列地点构成的、用-分隔的字符串，如：雪山-山脚下-村庄"}
				},
				"required": ["path"]
			}
		}
	},
	{
		"type": "function",
		"function": {
			"name": "create_NPC",
			"description": "提及了某个地方有某个NPC",
			"parameters": {
				"type": "object",
				"properties": {
					"npc_name": {"type": "string", "description": "NPC名称"},
					"location": {"type": "string", "description": "NPC所在的地点，没有提及就输入null"},
					"npc_describe": {"type": "string", "description": "对NPC的描述"}
				},
				"required": ["npc_name", "npc_describe"]
			}
		}
	},
	{
		"type": "function",
		"function": {
			"name": "create_rumors",
			"description": "提及了某个有意义的类似于传闻、新闻、谣言的事件",
			"parameters": {
				"type": "object",
				"properties": {
					"rumor_name": {"type": "string", "description": "传闻名称"},
					"content": {"type": "string", "description": "传闻简要的内容，用一句话总结"}
				},
				"required": ["rumor_name", "content"]
			}
		}
	},
	{
		"type": "function",
		"function": {
			"name": "update_reputation",
			"description": "根据玩家做出了好事或坏事，增加或扣除一定的声望值",
			"parameters": {
				"type": "object",
				"properties": {
					"quantity": {"type": "integer", "description": "增加或减少的数量，增加为正值，减少为负值"}
				},
				"required": ["quantity"]
			}
		}
	},
	{
		"type": "function",
		"function": {
			"name": "destroy_self",
			"description": "说想要永远离开，或者自己要死了",
			"parameters": {
				"type": "object",
				"properties": {},
				"required": []
			}
		}
	},
	{
		"type": "function",
		"function": {
			"name": "set_time",
			"description": "将游戏时间跳跃到指定时刻",
			"parameters": {
				"type": "object",
				"properties": {
					"hour": {"type": "integer", "description": "目标小时（0-23）"},
					"minute": {"type": "integer", "description": "目标分钟（0-59），默认0"}
				},
				"required": ["hour"]
			}
		}
	}
]

# ==================== AI 交互 ====================
func ask_ai(message: Array, askmode: aiMode):
	currentMode = askmode
	set_ai_busy(true)
	var outbound_messages = _compact_messages_for_request(_decorate_messages_for_output_mode(message, askmode))
	var body = [outbound_messages,null,"text"]
	match askmode:
		aiMode.tools:
			body = [outbound_messages,tools,"text"]
		aiMode.explore:
			body = [outbound_messages,null,"json_object"]
	var url = chat_url
	var json_string = JSON.stringify(body)
	if http_request.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
		await http_request.request_completed

	var err = http_request.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		json_string
	)
	if err == ERR_BUSY:
		await http_request.request_completed
		err = http_request.request(
			url,
			["Content-Type: application/json"],
			HTTPClient.METHOD_POST,
			json_string
		)
	if err != OK:
		changeTextTo(response_label, "请求失败: " + str(err))
		if askmode == aiMode.init_env and has_node("mainMenu") and $mainMenu.has_method("if_weather_failed"):
			$mainMenu.if_weather_failed("环境生成请求失败，已使用默认天气。")
		set_ai_busy(false)
		return
	await $HTTPRequest.request_completed

func _decorate_messages_for_output_mode(message: Array, askmode: aiMode) -> Array:
	if askmode != aiMode.chat and askmode != aiMode.action:
		return message
	var copied = message.duplicate(true)
	var min_chars = dialogue_min_chars if askmode == aiMode.chat else action_narration_min_chars
	min_chars = max(40, min_chars)
	var constraint = "输出要求：本次回复至少" + str(min_chars) + "字，信息完整、自然，不要省略关键细节，不要用固定收尾句硬凑字数。"
	copied.push_front({"role":"system", "content": constraint})
	return copied

func _compact_prompt_content(text: String) -> String:
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

func _compact_messages_for_request(messages: Array) -> Array:
	var copied = messages.duplicate(true)
	for i in range(copied.size()):
		var row = copied[i]
		if !(row is Dictionary):
			continue
		if !row.has("content"):
			continue
		row["content"] = _compact_prompt_content(str(row.get("content", "")))
		copied[i] = row
	return copied

func _output_mode_debug(msg: String) -> void:
	if !output_mode_debug_enabled:
		return
	print("[OUTPUT_MODE_DEBUG] " + msg)

func _tail_preview(text: String, max_chars: int = 48) -> String:
	var src = str(text)
	if src.length() <= max_chars:
		return src
	return src.substr(src.length() - max_chars, max_chars)

func _build_mode_consistent_extensions(_base_text: String, _askmode: aiMode) -> Array:
	return []

func _strip_angle_tags(text: String) -> String:
	var src = str(text)
	var regex = RegEx.new()
	if regex.compile("<[^>]*>") != OK:
		return src
	return regex.sub(src, "", true)

func _expand_text_to_min_chars(text: String, _min_chars: int, _askmode: aiMode) -> String:
	return text

func _enforce_output_min_length(text: String, _askmode: aiMode) -> String:
	return text

func _enforce_action_narration_richness(text: String) -> String:
	return text

func _looks_like_action_or_dialogue_phrase(text: String) -> bool:
	var t = _normalize_single_line_input(text)
	if t == "":
		return true
	if t.length() > 18:
		return true
	var invalid_tokens = ["请", "帮", "告诉", "一下", "怎么", "哪里", "为什么", "是否", "能不能", "可以吗", "然后", "如果", "因为", "所以", "行动", "对话", "回复", "输出"]
	for token in invalid_tokens:
		if t.find(token) != -1:
			return true
	return false

func _extract_compact_entity_candidate(raw_text: String, max_len: int = 14) -> String:
	var t = _normalize_single_line_input(raw_text)
	t = t.replace("：", " ").replace(":", " ").replace("。", " ").replace("，", " ").replace("？", " ").replace("!", " ")
	var regex = RegEx.new()
	if regex.compile("([\\u4e00-\\u9fa5A-Za-z·]{2,24})") != OK:
		return ""
	var m = regex.search(t)
	if m == null:
		return ""
	var candidate = str(m.get_string(1)).strip_edges()
	if candidate.length() > max_len:
		candidate = candidate.substr(0, max_len)
	return candidate

func _is_valid_generated_location_name(raw_name: String) -> bool:
	var n = _cleanup_location_candidate(raw_name)
	if n == "":
		return false
	if n.length() < 2 or n.length() > 16:
		return false
	if _looks_like_person_reference(n):
		return false
	if _looks_like_action_or_dialogue_phrase(n):
		return false
	var regex = RegEx.new()
	if regex.compile("^[\\u4e00-\\u9fa5A-Za-z0-9·]+$") != OK:
		return false
	return regex.search(n) != null

func _is_valid_generated_npc_name(raw_name: String) -> bool:
	var n = _sanitize_generated_npc_name(raw_name)
	if _is_bad_generated_npc_name(n):
		return false
	if n.length() > 12:
		return false
	if _looks_like_action_or_dialogue_phrase(n):
		return false
	var regex = RegEx.new()
	if regex.compile("^[\\u4e00-\\u9fa5A-Za-z·]+$") != OK:
		return false
	return regex.search(n) != null

func _extract_angle_tags(input_string: String) -> Array:
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

func _apply_direct_npc_tool_tags(reply: String) -> bool:
	var tags = _extract_angle_tags(reply)
	if tags.is_empty():
		return false
	var handled_any = false
	var only_location_tags = true
	for raw_tag in tags:
		var normalized = str(raw_tag).replace("：", ":").strip_edges()
		if normalized.begins_with("创建路径:"):
			var path = normalized.trim_prefix("创建路径:").strip_edges()
			if path != "":
				create_location(path)
				handled_any = true
		elif normalized.begins_with("声望值"):
			var rep_text = normalized.trim_prefix("声望值").strip_edges()
			if rep_text != "":
				var rep_change = int(rep_text)
				update_reputation(rep_change)
				handled_any = true
		else:
			only_location_tags = false
	return handled_any and only_location_tags

func _is_location_query_dialogue(input_text: String) -> bool:
	var t = _normalize_single_line_input(input_text)
	if t == "":
		return false
	if _is_relation_npc_query(t):
		return false
	var query_words = ["在哪", "在哪里", "在哪儿", "怎么去", "怎么走", "怎么到", "去哪", "去哪里", "路线", "路怎么走", "哪条路"]
	for w in query_words:
		if t.find(w) != -1:
			return true
	return false

func _cleanup_location_candidate(raw_text: String) -> String:
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

func _looks_like_person_reference(target: String) -> bool:
	if target == "":
		return false
	if npcs.has(target):
		return true
	var person_words = ["同学", "老师", "阿姨", "大叔", "叔叔", "学长", "学姐", "室友", "店员", "保安", "路人", "女儿", "儿子", "父亲", "母亲", "爸爸", "妈妈", "兄弟", "姐妹", "同事", "上司", "下属"]
	if target.begins_with("你的") or target.begins_with("我的") or target.begins_with("他的") or target.begins_with("她的") or target.begins_with("自己的"):
		return true
	for w in person_words:
		if target.find(w) != -1:
			return true
	return false

func _extract_location_target_from_dialogue(input_text: String) -> String:
	var t = _normalize_single_line_input(input_text)
	if t == "":
		return ""
	var regex = RegEx.new()
	var patterns = [
		"(?:去|到)([^，。！？?]{1,24})(?:怎么走|怎么去|怎么到|在哪|在哪里|在哪儿)",
		"(?:怎么去|怎么到)([^，。！？?]{1,24})",
		"([^，。！？?]{1,24})(?:在哪|在哪里|在哪儿)",
		"([^，。！？?]{1,24})(?:路线|路怎么走|哪条路)"
	]
	for p in patterns:
		if regex.compile(p) != OK:
			continue
		var m = regex.search(t)
		if m == null:
			continue
		var candidate = _cleanup_location_candidate(str(m.get_string(1)))
		if candidate.length() < 2 or candidate.length() > 20:
			continue
		var reject_words = ["你", "我", "他", "她", "它", "这里", "那里", "哪儿", "哪里", "什么", "怎么", "时候"]
		var bad = false
		for rw in reject_words:
			if candidate == rw:
				bad = true
				break
		if bad:
			continue
		if _looks_like_person_reference(candidate):
			continue
		return candidate
	return ""

func _reply_has_location_clue(reply_text: String) -> bool:
	var plain = process_string(reply_text).strip_edges()
	if plain == "":
		return false
	for site_key in sites.keys():
		var site_name = str(site_key).strip_edges()
		if site_name != "" and plain.find(site_name) != -1:
			return true
	var clue_words = ["在", "位于", "往", "沿着", "直走", "左转", "右转", "经过", "到", "前面", "后面", "旁边", "路线", "路上"]
	for w in clue_words:
		if plain.find(w) != -1:
			return true
	return false

func _try_create_location_from_dialogue(reply: String) -> bool:
	if last_dialogue_input == "":
		return false
	if !_is_location_query_dialogue(last_dialogue_input):
		return false
	var fail_words = ["不知道", "不清楚", "没听说", "找不到", "不在这", "不确定", "没去过", "不认识路", "不晓得"]
	var has_location_clue = _reply_has_location_clue(reply)
	for w in fail_words:
		if reply.find(w) != -1 and !has_location_clue:
			return false
	var target = _extract_location_target_from_dialogue(last_dialogue_input)
	if target == "":
		return false
	target = _extract_compact_entity_candidate(target, 16)
	if !_is_valid_generated_location_name(target):
		return false
	if _resolve_site_alias(target) == currentSiteName:
		return false
	if !has_location_clue:
		return false
	create_location(currentSiteName + "-" + target)
	return true

func _sanitize_generated_npc_name(raw_name: String) -> String:
	var n = _normalize_single_line_input(raw_name)
	n = n.replace("。", "").replace("，", "").replace("？", "").replace("?", "").replace("！", "").replace("!", "")
	var prefixes = ["你的", "我的", "他的", "她的", "自己的", "这个", "那个", "一位", "有个", "有位"]
	for p in prefixes:
		if n.begins_with(p):
			n = n.trim_prefix(p).strip_edges()
	return n

func _is_bad_generated_npc_name(npc_label: String) -> bool:
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

func _fallback_relation_npc_name(query_text: String) -> String:
	var t = _normalize_single_line_input(query_text)
	if _contains_any_keyword(t, ["女儿"]):
		return ["阿莲", "小霜", "露娜", "清禾"][randi_range(0, 3)]
	if _contains_any_keyword(t, ["儿子"]):
		return ["阿成", "小川", "远山", "泽安"][randi_range(0, 3)]
	if _contains_any_keyword(t, ["父亲", "爸爸"]):
		return ["老周", "韩叔", "陈伯", "沈叔"][randi_range(0, 3)]
	if _contains_any_keyword(t, ["母亲", "妈妈"]):
		return ["周婶", "林姨", "方姨", "柳婶"][randi_range(0, 3)]
	if _contains_any_keyword(t, ["兄弟", "姐妹"]):
		return ["阿岳", "小宁", "云青", "子岚"][randi_range(0, 3)]
	return ["阿远", "小禾", "程木", "林渡"][randi_range(0, 3)]

func _extract_location_name_from_reply(reply_text: String) -> String:
	var plain = process_string(reply_text).strip_edges()
	if plain == "":
		return ""
	for site_key in sites.keys():
		var site_name = str(site_key).strip_edges()
		if site_name != "" and plain.find(site_name) != -1:
			return site_name
	var regex = RegEx.new()
	if regex.compile("(?:在|位于|住在)([\\u4e00-\\u9fa5A-Za-z·]{2,16})") != OK:
		return ""
	var m = regex.search(plain)
	if m == null:
		return ""
	var loc = _extract_compact_entity_candidate(_cleanup_location_candidate(str(m.get_string(1))), 16)
	if !_is_valid_generated_location_name(loc):
		return ""
	return loc

func _extract_unknown_npc_target_from_query(query_text: String) -> String:
	var t = _normalize_single_line_input(query_text)
	if t == "":
		return ""
	var regex = RegEx.new()
	var patterns = [
		"([\\u4e00-\\u9fa5A-Za-z·]{2,12})(?:在哪|在哪里|在哪儿|是谁|什么人|在吗|的信息|的消息)",
		"(?:找|寻找|打听|问|关于)([\\u4e00-\\u9fa5A-Za-z·]{2,12})"
	]
	for p in patterns:
		if regex.compile(p) != OK:
			continue
		var m = regex.search(t)
		if m == null:
			continue
		var candidate = _sanitize_generated_npc_name(str(m.get_string(1)))
		candidate = _extract_compact_entity_candidate(candidate, 12)
		if !_is_valid_generated_npc_name(candidate) and _is_relation_npc_query(t):
			candidate = _fallback_relation_npc_name(t)
		if _is_valid_generated_npc_name(candidate):
			return candidate
	return ""

func _is_relation_npc_query(input_text: String) -> bool:
	var t = _normalize_single_line_input(input_text)
	if t == "":
		return false
	var relation_words = ["兄弟", "姐妹", "父母", "爸爸", "妈妈", "儿子", "女儿", "同事", "上司", "下属", "学徒", "师父", "朋友", "家人", "亲戚"]
	for w in relation_words:
		if t.find(w) != -1:
			return true
	return false

func _guess_related_npc_desc(query_text: String, source_npc_name: String) -> String:
	var t = _normalize_single_line_input(query_text)
	var relation = "熟人"
	if _contains_any_keyword(t, ["兄弟", "姐妹"]):
		relation = "兄弟姐妹"
	elif _contains_any_keyword(t, ["父母", "爸爸", "妈妈"]):
		relation = "亲属长辈"
	elif _contains_any_keyword(t, ["同事", "上司", "下属"]):
		relation = "工作关系人"
	elif _contains_any_keyword(t, ["学徒", "师父"]):
		relation = "师门关系人"
	elif _contains_any_keyword(t, ["朋友", "熟人", "家人", "亲戚"]):
		relation = "生活关系人"
	var source_name = source_npc_name.strip_edges()
	if source_name == "":
		source_name = "当前人物"
	return "与" + source_name + "相关的" + relation

func _extract_named_people_from_dialogue(reply_text: String) -> Array:
	var plain = process_string(reply_text).strip_edges()
	if plain == "":
		return []
	var names: Array = []
	var regex = RegEx.new()
	var patterns = [
		"(?:叫|名叫|名字是|是)([\\u4e00-\\u9fa5A-Za-z·]{2,12})",
		"(?:有个|有位)([\\u4e00-\\u9fa5A-Za-z·]{2,12})",
		"([\\u4e00-\\u9fa5A-Za-z·]{2,12})(?:是我的|跟我|在)",
		"(?:他叫|她叫|我哥叫|我姐叫|我爸叫|我妈叫)([\\u4e00-\\u9fa5A-Za-z·]{2,12})"
	]
	var reject_words = ["这里", "那里", "这个", "那个", "我们", "他们", "她们", "没有", "不知道", "不清楚", "路人"]
	for p in patterns:
		if regex.compile(p) != OK:
			continue
		for m in regex.search_all(plain):
			var n = _sanitize_generated_npc_name(str(m.get_string(1)))
			if n == "":
				continue
			if n == str(currentNpc.npcName):
				continue
			if reject_words.has(n):
				continue
			if _is_bad_generated_npc_name(n):
				continue
			if !names.has(n):
				names.append(n)
	return names

func _maybe_create_related_npc_from_dialogue(reply: String) -> void:
	if currentNpc == null:
		return
	if last_dialogue_input == "" or !_is_relation_npc_query(last_dialogue_input):
		return
	var fail_words = ["没有", "不知道", "不清楚", "记不清", "不认识", "没听说", "不方便说"]
	for w in fail_words:
		if reply.find(w) != -1:
			return
	var names = _extract_named_people_from_dialogue(reply)
	if names.is_empty():
		var fallback_name = _fallback_relation_npc_name(last_dialogue_input)
		if !_is_bad_generated_npc_name(fallback_name):
			names.append(fallback_name)
	if names.is_empty():
		return
	var guessed_desc = _guess_related_npc_desc(last_dialogue_input, str(currentNpc.npcName))
	var loc = _extract_location_name_from_reply(reply)
	if loc == "":
		loc = currentSiteName
	var created = 0
	for raw_name in names:
		var npc_name = _sanitize_generated_npc_name(str(raw_name))
		npc_name = _extract_compact_entity_candidate(npc_name, 12)
		if !_is_valid_generated_npc_name(npc_name) and _is_relation_npc_query(last_dialogue_input):
			npc_name = _fallback_relation_npc_name(last_dialogue_input)
		if !_is_valid_generated_npc_name(npc_name):
			continue
		if npc_name == "" or npcs.has(npc_name) or dead_npc_names.has(npc_name):
			continue
		if loc != "" and _is_valid_generated_location_name(loc) and !sites.has(loc):
			create_location(currentSiteName + "-" + loc)
		create_NPC(npc_name, loc, guessed_desc)
		created += 1
		if created >= 2:
			break

func _maybe_create_unknown_npc_from_dialogue(reply: String) -> void:
	if last_dialogue_input == "":
		return
	var target_name = _extract_unknown_npc_target_from_query(last_dialogue_input)
	if target_name == "":
		return
	if npcs.has(target_name) or dead_npc_names.has(target_name):
		return
	var fail_words = ["不知道", "不清楚", "没听说", "没有这个人", "不认识", "没见过"]
	for w in fail_words:
		if reply.find(w) != -1:
			return
	var loc = _extract_location_name_from_reply(reply)
	if loc == "":
		loc = currentSiteName
	if loc != "" and _is_valid_generated_location_name(loc) and !sites.has(loc):
		create_location(currentSiteName + "-" + loc)
	var desc = "在" + loc + "活动，与你打听的人物相关"
	create_NPC(target_name, loc, desc)

func npc_reply(reply: String):
	changeTextTo(%speakerNameLabel, currentNpc.npcName)
	changeTextTo(response_label, process_string(reply))
	_record_current_chat_session("对话回复", str(currentNpc.npcName), reply)
	currentNpc.currentChat +=  currentNpc.npcName +":"+ reply + "\n"
	_remember_important_event("<对话>" + currentNpc.npcName + "：" + process_string(reply), currentSiteName, currentNpc.npcName)
	var direct_location_only = _apply_direct_npc_tool_tags(reply)
	if !direct_location_only:
		_try_create_location_from_dialogue(reply)
	_maybe_create_related_npc_from_dialogue(reply)
	_maybe_create_unknown_npc_from_dialogue(reply)
	var toolsTexts = get_content_in_angle_brackets(reply)
	print("提取出的工具信息：",toolsTexts)
	if toolsTexts!="" and !direct_location_only:
		var prompts = [
			{"role":"system","content": agent_prompt},
			{"role":"user","content": toolsTexts}]
		await ask_ai(prompts, aiMode.tools)
	elif toolsTexts == "" and _needs_tool_inference_from_context(last_dialogue_input, reply):
		var infer_prompts = [
			{"role":"system","content": agent_prompt + "\n若输入没有<>标签，也要从语义中尽力提取买卖、赠送、交付、协助执行等可执行方法；如果确实没有再回复没有方法被调用。"},
			{"role":"user","content": "玩家输入：" + last_dialogue_input + "\nNPC回复：" + reply}]
		await ask_ai(infer_prompts, aiMode.tools)
	await _auto_apply_action_effects("", reply, toolsTexts)
	if !_has_active_event_panel():
		var action_req = _extract_npc_action_request(reply)
		if !action_req.is_empty():
			_queue_action_confirm(action_req)
		else:
			_maybe_offer_intent_confirm_from_dialogue(reply)

func process_string(input: String) -> String:
	_ensure_process_regex_ready()
	var src = str(input)
	var result = src
	if _process_strip_regex != null and _process_strip_regex.is_valid():
		result = _process_strip_regex.sub(result, "", true)
	if _process_newline_regex != null and _process_newline_regex.is_valid():
		result = _process_newline_regex.sub(result, "\n", true)
	return result.strip_edges()

func _ensure_process_regex_ready() -> void:
	if _process_strip_regex == null:
		_process_strip_regex = RegEx.new()
	if !_process_strip_regex.is_valid():
		if _process_strip_regex.compile("<[^>]*>") != OK:
			push_warning("process_string strip regex compile failed")
	if _process_newline_regex == null:
		_process_newline_regex = RegEx.new()
	if !_process_newline_regex.is_valid():
		if _process_newline_regex.compile("\n\n+") != OK:
			push_warning("process_string newline regex compile failed")
func get_content_in_angle_brackets(input_string: String)->String:
	var results = ""
	var normalized_input = str(input_string)
	normalized_input = normalized_input.replace("\\<", "<").replace("\\>", ">")
	normalized_input = normalized_input.replace("＜", "<").replace("＞", ">")
	var regex = RegEx.new()

	# 编译正则表达式，匹配<和>之间的内容（包括<和>本身）
	regex.compile("<[^>]+>")
	var matches = regex.search_all(normalized_input)
	for match_obj in matches:
		var content = match_obj.get_string(0)
		results+=content
	return results

# ==================== 图片生成 ====================
func gen_img(prompt: String, site_name: String = ""):
	var target_site = site_name.strip_edges()
	if target_site == "":
		target_site = currentSiteName
	if prompt == "":
		if pending_site_update:
			pending_site_update = false
			site_update()
		return
	_bg_debug("gen_img start, site=" + target_site + ", prompt=" + prompt.left(80))
	print("正在同时生成图片...")
	var headers = ["Content-Type: application/json"]
	var image_json_data = JSON.stringify({"prompt": prompt})
	var error_image = %ImgHTTPRequest.request(image_api_url, headers, HTTPClient.METHOD_POST, image_json_data)
	print("请求返回了...",error_image)
	if error_image != OK:
		if error_image == ERR_BUSY:
			pending_img_prompt = prompt
			pending_img_site = target_site
			print("图片请求排队等待...")
			_bg_debug("gen_img queued due ERR_BUSY")
		else:
			print("错误：请求创建失败")
			_bg_debug("gen_img request create failed, err=" + str(error_image))
			if pending_site_update:
				pending_site_update = false
				site_update()
		inflight_img_site = ""
		return
	inflight_img_site = target_site
	if pending_site_update:
		_start_img_watchdog(target_site)

func _start_img_watchdog(target_site: String) -> void:
	img_watchdog_seq += 1
	var seq = img_watchdog_seq
	await get_tree().create_timer(10.0).timeout
	if seq != img_watchdog_seq:
		return
	if pending_site_update and inflight_img_site == target_site:
		_bg_debug("img watchdog timeout fallback, site=" + target_site)
		pending_site_update = false
		site_update(true, true, false)

func _sanitize_filename(file_name: String) -> String:
	return file_name.replace("/", "_").replace("\\", "_").replace(":", "_").replace("*", "_").replace("?", "_").replace("\"", "_").replace("<", "_").replace(">", "_").replace("|", "_")

func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)

func _clear_dir_contents(dir_path: String) -> void:
	if !DirAccess.dir_exists_absolute(dir_path):
		return
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var target_path = dir_path.path_join(entry)
			if dir.current_is_dir():
				_clear_dir_contents(target_path)
				DirAccess.remove_absolute(target_path)
			else:
				DirAccess.remove_absolute(target_path)
		entry = dir.get_next()
	dir.list_dir_end()

func _copy_file(src_path: String, dst_path: String) -> void:
	if !FileAccess.file_exists(src_path):
		return
	_ensure_dir(dst_path.get_base_dir())
	var bytes = FileAccess.get_file_as_bytes(src_path)
	var file = FileAccess.open(dst_path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()

func _copy_dir_recursive(src_dir: String, dst_dir: String) -> void:
	if !DirAccess.dir_exists_absolute(src_dir):
		return
	_ensure_dir(dst_dir)
	var dir = DirAccess.open(src_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var src_path = src_dir.path_join(entry)
			var dst_path = dst_dir.path_join(entry)
			if dir.current_is_dir():
				_copy_dir_recursive(src_path, dst_path)
			else:
				_copy_file(src_path, dst_path)
		entry = dir.get_next()
	dir.list_dir_end()

func _prepare_session_resource_dir() -> void:
	_ensure_dir(SESSION_RESOURCE_DIR)
	_clear_dir_contents(SESSION_RESOURCE_DIR)
	_ensure_dir(SCENE_IMG_DIR)
	_ensure_dir(ITEM_IMG_DIR)
	_ensure_dir(ITEM_PROFILE_DIR)
	has_saved_in_session = false

func _sync_session_resources_to_save() -> void:
	_ensure_dir(SAVE_SLOT_DIR)
	_clear_dir_contents(SAVE_SLOT_DIR)
	_ensure_dir(SAVE_RESOURCE_DIR)
	_copy_dir_recursive(SCENE_IMG_DIR, SAVE_SCENE_IMG_DIR)
	_copy_dir_recursive(ITEM_IMG_DIR, SAVE_ITEM_IMG_DIR)
	_copy_dir_recursive(ITEM_PROFILE_DIR, SAVE_ITEM_PROFILE_DIR)

func _restore_session_resources_from_save() -> void:
	_ensure_dir(SESSION_RESOURCE_DIR)
	_clear_dir_contents(SESSION_RESOURCE_DIR)
	_copy_dir_recursive(SAVE_SCENE_IMG_DIR, SCENE_IMG_DIR)
	_copy_dir_recursive(SAVE_ITEM_IMG_DIR, ITEM_IMG_DIR)
	_copy_dir_recursive(SAVE_ITEM_PROFILE_DIR, ITEM_PROFILE_DIR)

func _handle_exit_cleanup() -> void:
	if has_saved_in_session:
		return
	_clear_dir_contents(SESSION_RESOURCE_DIR)

func _save_image_png(image: Image, dir: String, file_name: String) -> void:
	_ensure_dir(dir)
	var path = dir + _sanitize_filename(file_name) + ".png"
	image.save_png(path)

func _load_image_png(dir: String, file_name: String) -> Texture2D:
	var path = dir + _sanitize_filename(file_name) + ".png"
	if FileAccess.file_exists(path):
		var img = Image.load_from_file(path)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null

func _save_site_json(site_name: String, site_data: Dictionary) -> void:
	_ensure_dir(SCENE_IMG_DIR)
	var path = SCENE_IMG_DIR + _sanitize_filename(site_name) + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(site_data))
		file.close()

func _load_site_json(site_name: String) -> Dictionary:
	var path = SCENE_IMG_DIR + _sanitize_filename(site_name) + ".json"
	if !FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if !file:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	var d = json.get_data()
	return d if d is Dictionary else {}

func _save_item_profile_json(item_name: String, profile: Dictionary) -> void:
	_ensure_dir(ITEM_PROFILE_DIR)
	var path = ITEM_PROFILE_DIR + _sanitize_filename(item_name) + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(profile, "\t"))
		file.close()

func _load_item_profile_json(item_name: String) -> Dictionary:
	var path = ITEM_PROFILE_DIR + _sanitize_filename(item_name) + ".json"
	if !FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if !file:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	var d = json.get_data()
	return d if d is Dictionary else {}

func _base64_to_image(base64_string: String) -> Image:
	if base64_string == "":
		return null
	var image_buffer = Marshalls.base64_to_raw(base64_string)
	var image = Image.new()
	var error = image.load_png_from_buffer(image_buffer)
	if error != OK:
		error = image.load_jpg_from_buffer(image_buffer)
	if error != OK:
		return null
	return image

func _display_base64_image(base64_string: String, site_name: String = ""):
	var target_site = site_name.strip_edges()
	if target_site == "":
		target_site = currentSiteName
	var image = _base64_to_image(base64_string)
	if image != null:
		var texture = ImageTexture.create_from_image(image)
		siteImgs[target_site] = texture
		_save_image_png(image, SCENE_IMG_DIR, target_site)
		if target_site == currentSiteName:
			%backgroundImg.texture = texture
		_bg_debug("display image ok, site=" + target_site + ", b64_len=" + str(base64_string.length()))
	else:
		print("错误：图片格式不支持")
		_bg_debug("display image failed, invalid image buffer")
	if pending_site_update:
		pending_site_update = false
		site_update()
	_drain_pending_img()

func _base64_to_texture(base64_string: String) -> Texture2D:
	var image = _base64_to_image(base64_string)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)

func _request_json(url: String, body_json: String) -> Dictionary:
	var request_node := HTTPRequest.new()
	add_child(request_node)
	var err = request_node.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body_json
	)
	if err != OK:
		request_node.queue_free()
		return {"ok": false, "error": "请求创建失败: " + str(err)}

	var response = await request_node.request_completed
	request_node.queue_free()

	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "网络错误: " + str(result)}

	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		return {"ok": false, "error": "响应解析失败"}

	var data = parser.get_data()
	if response_code != 200:
		return {"ok": false, "error": str(data.get("error", "HTTP " + str(response_code)))}
	return {"ok": true, "data": data}

func _generate_item_profile(item_name: String) -> Dictionary:
	var prompts = [
		{"role":"system", "content": item_profile_prompt},
		{"role":"user", "content": "物品名：" + item_name}
	]
	var req = await _request_json(chat_url, JSON.stringify([prompts, null, "json_object"]))
	if !req.get("ok", false):
		return {
			"description": "这是一件实用的道具，可在冒险中派上用场。",
			"image_prompt": "single game inventory item icon, clean background, detailed, centered",
			"effect_type": "none",
			"effect_value": 0
		}

	var text = req["data"].get("text", "")
	if text is Dictionary:
		return text
	if text is String:
		var json_dic = extract_json_from_text(text)
		if json_dic != {}:
			return json_dic
	return {
		"description": "这是一件实用的道具，可在冒险中派上用场。",
		"image_prompt": "single game inventory item icon, clean background, detailed, centered",
		"effect_type": "none",
		"effect_value": 0
	}

func _generate_item_texture(image_prompt: String) -> Texture2D:
	var ultra_fast_prompt = _build_ultra_fast_item_prompt(image_prompt)
	var req = await _request_json(
		image_api_url,
		JSON.stringify({
			"prompt": ultra_fast_prompt,
			"width": 1024,
			"height": 1024,
			"steps": 6,
			"cfg_scale": 2.2,
			"mode": "ultra_fast_item"
		})
	)
	if !req.get("ok", false):
		return null
	var image_data = req["data"].get("image", "")
	return _base64_to_texture(image_data)

func _generate_validation_dialogue(scene_context: String, fallback: String) -> String:
	var prompts = [
		{"role":"system", "content": validation_feedback_prompt},
		{"role":"user", "content": scene_context}
	]
	var req = await _request_json(chat_url, JSON.stringify([prompts, null, "text"]))
	if !req.get("ok", false):
		return fallback
	var text = req["data"].get("text", "")
	if text is String and text.strip_edges() != "":
		return text.strip_edges()
	return fallback

func _build_ultra_fast_item_prompt(base_prompt: String) -> String:
	var cleaned = base_prompt.strip_edges()
	if cleaned == "":
		cleaned = "generic item"
	return "minimalist inventory icon, single object, centered, plain clean background, no text, simple lighting, " + cleaned

func _sanitize_item_profile(item_name: String, raw_profile: Dictionary) -> Dictionary:
	var safe: Dictionary = {
		"description": str(raw_profile.get("description", "这是一件实用的道具，可在冒险中派上用场。")).strip_edges(),
		"image_prompt": str(raw_profile.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered")).strip_edges(),
		"value": int(raw_profile.get("value", 50)),
		"rarity": str(raw_profile.get("rarity", "common")).strip_edges(),
		"effect_type": str(raw_profile.get("effect_type", "none")).strip_edges(),
		"effect_value": int(raw_profile.get("effect_value", 0))
	}
	if safe["description"] == "":
		safe["description"] = "这是一件实用的道具，可在冒险中派上用场。"
	if safe["image_prompt"] == "":
		safe["image_prompt"] = "single game inventory item icon of " + item_name + ", clean background, centered"
	if safe["rarity"] == "":
		safe["rarity"] = "common"
	if safe["value"] < 1:
		safe["value"] = 1
	return safe

func _ensure_item_profile_record_before_trade(item_name: String) -> void:
	var key = str(item_name).strip_edges()
	if key == "":
		return
	var disk_profile = _load_item_profile_json(key)
	var profile: Dictionary = {}
	if !disk_profile.is_empty():
		profile = _sanitize_item_profile(key, disk_profile)
	else:
		var generated = await _generate_item_profile(key)
		profile = _sanitize_item_profile(key, generated)
		_save_item_profile_json(key, profile)
	var cached_tex = _load_image_png(ITEM_IMG_DIR, key)
	itemProfiles[key] = {
		"description": profile.get("description", "这是一件实用的道具，可在冒险中派上用场。"),
		"image_prompt": profile.get("image_prompt", "single game inventory item icon of " + key + ", clean background, centered"),
		"value": int(profile.get("value", 50)),
		"rarity": str(profile.get("rarity", "common")),
		"effect_type": str(profile.get("effect_type", "none")),
		"effect_value": int(profile.get("effect_value", 0)),
		"texture": cached_tex,
		"is_generating": false,
		"is_ready": cached_tex != null
	}
	ensure_item_profile_async(key)

func _build_explore_system_prompt() -> String:
	var guards = "用户初始设定：" + world_seed_input + "\n"
	guards += "当前世界观：" + background + "\n"
	guards += "请确保地点、NPC、英文生图提示词与上述设定完全一致。"
	var style_guard = _build_setting_consistency_guard_text(_detect_setting_style_signals())
	if style_guard != "":
		guards += "\n设定一致性约束：" + style_guard
	guards += "\n硬性要求：输出JSON中的“能前往的地点”必须是3~6个可直达、互不重复、且不包含当前地点本身的地点名，不能为空。"
	return role_prompt + "\n" + guards

func ensure_item_profile_async(item_name: String) -> void:
	var disk_profile_full = _load_item_profile_json(item_name)
	if !itemProfiles.has(item_name):
		var disk_profile = disk_profile_full
		itemProfiles[item_name] = {
			"description": disk_profile.get("description", "正在生成物品介绍..."),
			"image_prompt": disk_profile.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered"),
			"value": int(disk_profile.get("value", 50)),
			"rarity": str(disk_profile.get("rarity", "common")),
			"effect_type": str(disk_profile.get("effect_type", "none")),
			"effect_value": int(disk_profile.get("effect_value", 0)),
			"texture": null,
			"is_generating": false,
			"is_ready": false
		}

	if itemProfiles[item_name].get("is_generating", false) or itemProfiles[item_name].get("is_ready", false):
		return

	itemProfiles[item_name]["is_generating"] = true

	# 磁盘图片缓存检查
	var cached_tex = _load_image_png(ITEM_IMG_DIR, item_name)
	if cached_tex != null:
		var disk_profile = _load_item_profile_json(item_name)
		var cached_desc: String
		var cached_image_prompt: String
		var cached_value: int
		var cached_rarity: String
		var cached_effect_type: String
		var cached_effect_value: int
		if !disk_profile.is_empty():
			cached_desc = str(disk_profile.get("description", "这是一件实用的道具。"))
			cached_image_prompt = str(disk_profile.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered"))
			cached_value = int(disk_profile.get("value", 50))
			cached_rarity = str(disk_profile.get("rarity", "common"))
			cached_effect_type = str(disk_profile.get("effect_type", "none"))
			cached_effect_value = int(disk_profile.get("effect_value", 0))
		else:
			var fresh = await _generate_item_profile(item_name)
			cached_desc = str(fresh.get("description", "这是一件实用的道具。"))
			cached_image_prompt = str(fresh.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered"))
			cached_value = int(fresh.get("value", 50))
			cached_rarity = str(fresh.get("rarity", "common"))
			cached_effect_type = str(fresh.get("effect_type", "none"))
			cached_effect_value = int(fresh.get("effect_value", 0))
			_save_item_profile_json(item_name, fresh)
		itemProfiles[item_name]["description"] = cached_desc
		itemProfiles[item_name]["image_prompt"] = cached_image_prompt
		if !itemProfiles[item_name].get("value_trade_confirmed", false):
			itemProfiles[item_name]["value"] = cached_value
		itemProfiles[item_name]["rarity"] = cached_rarity
		itemProfiles[item_name]["effect_type"] = cached_effect_type
		itemProfiles[item_name]["effect_value"] = cached_effect_value
		itemProfiles[item_name]["texture"] = cached_tex
		itemProfiles[item_name]["is_generating"] = false
		itemProfiles[item_name]["is_ready"] = true
		%itemContainer.update_item_visual(item_name, cached_tex, cached_desc, cached_effect_type, cached_effect_value)
		return

	var profile: Dictionary = {}
	if !disk_profile_full.is_empty():
		profile = _sanitize_item_profile(item_name, disk_profile_full)
	else:
		profile = _sanitize_item_profile(item_name, await _generate_item_profile(item_name))
		_save_item_profile_json(item_name, profile)
	var item_description = str(profile.get("description", "这是一件实用的道具，可在冒险中派上用场。"))
	var item_value = int(profile.get("value", 50))
	var item_rarity = str(profile.get("rarity", "common"))
	var item_effect_type = str(profile.get("effect_type", "none"))
	var item_effect_value = int(profile.get("effect_value", 0))
	var image_prompt = str(profile.get("image_prompt", "single game inventory item icon, clean background, detailed, centered"))
	var item_texture = await _generate_item_texture(image_prompt)

	if item_texture != null:
		var item_image = (item_texture as ImageTexture).get_image()
		if item_image != null:
			_save_image_png(item_image, ITEM_IMG_DIR, item_name)

	itemProfiles[item_name]["description"] = item_description
	itemProfiles[item_name]["image_prompt"] = image_prompt
	if !itemProfiles[item_name].get("value_trade_confirmed", false):
		itemProfiles[item_name]["value"] = item_value
	itemProfiles[item_name]["rarity"] = item_rarity
	itemProfiles[item_name]["effect_type"] = item_effect_type
	itemProfiles[item_name]["effect_value"] = item_effect_value
	itemProfiles[item_name]["texture"] = item_texture
	itemProfiles[item_name]["is_generating"] = false
	itemProfiles[item_name]["is_ready"] = true
	%itemContainer.update_item_visual(item_name, item_texture, item_description, item_effect_type, item_effect_value)

func update_item_trade_price(item_name: String, per_unit_price: int) -> void:
	if item_name == "" or per_unit_price <= 0:
		return
	var key = str(item_name).strip_edges()
	if !itemProfiles.has(key):
		return
	itemProfiles[key]["value"] = per_unit_price
	itemProfiles[key]["value_trade_confirmed"] = true
	var disk_profile = _load_item_profile_json(key)
	disk_profile["value"] = per_unit_price
	_save_item_profile_json(key, disk_profile)

# ==================== UI 操作 ====================
func _on_send_button_pressed():
	await _submit_action_input(input_text_edit.text, false)

func _normalize_single_line_input(raw_text: String) -> String:
	var t = str(raw_text).replace("\r\n", "\n").replace("\r", "\n")
	if t.find("\n") != -1:
		t = t.substr(0, t.find("\n"))
	return t.strip_edges()

func _submit_action_input(raw_input: String, bypass_lock_check: bool = false) -> void:
	var user_input = _normalize_single_line_input(raw_input)
	if user_input == "" or ai_busy:
		return
	if !bypass_lock_check and (event_flow_lock or _has_active_event_panel()):
		return
	preferred_input_focus = "action"
	call_deferred("_recover_focus_after_submit", "action")
	input_text_edit.text = ""
	last_action_input = user_input
	addLog("【行动】" + user_input)
	changeTextTo(%speakerNameLabel, playerName)
	changeTextTo(response_label, user_input)
	var action_context = "设定：" + world_seed_input
	action_context += "\n世界：" + background
	action_context += "\n地点：" + currentSiteName
	action_context += "\n资产：" + str(money)
	action_context += "\n身份：" + playerName
	action_context += "\n背包：" + _build_inventory_snapshot()
	var focus_npc_name = ""
	var focus_npc_desc = ""
	if currentState == worldState.chat and currentNpc != null:
		focus_npc_name = str(currentNpc.npcName)
		focus_npc_desc = str(currentNpc.npcDescribe)
		action_context += "\n对象：" + focus_npc_name
		action_context += "\n对象身份：" + focus_npc_desc
		action_context += "\n规则：行动无明确对象时默认对当前对象发起。"
	var identity_guidance = _clip_prompt_text(_build_identity_attitude_guidance(focus_npc_name, focus_npc_desc), 520)
	if identity_guidance != "":
		action_context += "\n态度导向：\n" + identity_guidance
	var chat_session_mem = _clip_prompt_text(get_current_chat_session_memory(focus_npc_name), 900)
	if chat_session_mem != "":
		action_context += "\n当前会话强约束：\n" + chat_session_mem
	var related_events = _clip_prompt_text(_build_related_event_memory_for_action(user_input, focus_npc_name), 480)
	if related_events != "":
		action_context += "\n事件记忆：\n" + related_events
	if focus_npc_name != "":
		_record_current_chat_session("行动输入", playerName, user_input)
	action_context = _clip_prompt_text(action_context, prompt_action_context_max_chars)
	var aprompts = [
		{"role":"system","content": action_prompt + "\n" + action_context},
		{"role":"user","content": user_input}]
	await ask_ai(aprompts, aiMode.action)

func _on_dialogue_button_pressed():
	if currentState != worldState.chat or currentNpc == null or ai_busy:
		return
	var user_input = _normalize_single_line_input(dialogue_input.text)
	if user_input == "":
		return
	preferred_input_focus = "dialogue"
	call_deferred("_recover_focus_after_submit", "dialogue")
	var leave_words = ["离开", "结束对话", "退出对话", "不聊了", "再见"]
	if leave_words.has(user_input):
		dialogue_input.text = ""
		if _has_active_event_panel():
			changeTextTo(%speakerNameLabel, "【旁白】")
			changeTextTo(response_label, "当前情况无法脱离，" + currentNpc.npcName + "不会让你就这么走。")
			await currentNpc.chatWithNpc("[玩家试图离开]")
			return
		_request_leave_chat_confirm()
		return
	last_dialogue_input = user_input
	dialogue_input.text = ""
	changeTextTo(%speakerNameLabel, playerName)
	changeTextTo(response_label, user_input)
	_record_current_chat_session("对话输入", playerName, user_input)
	await currentNpc.chatWithNpc(user_input)
	currentNpc.currentChat += "玩家：" + user_input + "\n"

func _on_npc_icon_gui_input(event: InputEvent) -> void:
	if !(event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if !mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if currentState != worldState.chat or currentNpc == null:
		return
	_show_current_npc_profile()

func _show_current_npc_profile() -> void:
	if currentNpc == null:
		return
	var npc_name = str(currentNpc.npcName)
	var desc = str(currentNpc.npcDescribe).strip_edges()
	if desc == "":
		desc = "暂无详细介绍"
	var mem = get_relevant_event_memory_for_npc(npc_name, desc).strip_edges()
	if mem == "":
		mem = "- 暂无与该角色直接相关的重要事件"
	var panel_text = "人物：" + npc_name + "\n介绍：" + desc + "\n相关重要事件：\n" + mem
	changeTextTo(%speakerNameLabel, "【人物档案】")
	changeTextTo(response_label, panel_text, 80)
	addLog("<查看了" + npc_name + "的人物档案>")

func _request_leave_chat_confirm() -> void:
	if currentState != worldState.chat or currentNpc == null:
		return
	var npc_name = str(currentNpc.npcName).strip_edges()
	pending_action_confirm = {
		"action": "离开与" + npc_name + "的对话",
		"prompt": "是否结束与" + npc_name + "的对话并回到探索？",
		"actor": npc_name,
		"mode": "leave_chat"
	}
	_set_event_flow_lock(true)
	%event.got_action_confirm_event(str(pending_action_confirm.get("action", "")), str(pending_action_confirm.get("prompt", "")))

func request_site_switch(site_name: String) -> void:
	var target = _resolve_site_alias(str(site_name).strip_edges())
	if target == "":
		return
	if currentState == worldState.chat and currentNpc != null:
		var npc_name = str(currentNpc.npcName).strip_edges()
		pending_action_confirm = {
			"action": "前往" + target,
			"prompt": "是否结束与" + npc_name + "的对话并前往" + target + "？",
			"actor": npc_name,
			"mode": "switch_site",
			"target_site": target
		}
		_set_event_flow_lock(true)
		%event.got_action_confirm_event(str(pending_action_confirm.get("action", "")), str(pending_action_confirm.get("prompt", "")))
		return
	await goto(target)

func _start_chat_with_existing_npc(npc_name: String) -> void:
	if !npcs.has(npc_name) or !(npcs[npc_name] is Dictionary):
		return
	prepare_npc_memory_for_chat(npc_name)
	var new_npc = npc.new()
	new_npc.npcName = npc_name
	new_npc.scene = self
	new_npc.npcDescribe = str(npcs[npc_name].get("npc_describe", ""))
	if !npcs[npc_name].has("npc_log") or !(npcs[npc_name]["npc_log"] is Array):
		npcs[npc_name]["npc_log"] = []
	var logs = ""
	for log_entry in npcs[npc_name]["npc_log"]:
		logs += str(log_entry)
	new_npc.npcLog = logs
	newNpc = new_npc
	await changeStateInto(GameManager.worldState.chat)

func request_npc_switch(npc_name: String) -> void:
	var target_npc = str(npc_name).strip_edges()
	if target_npc == "":
		return
	if !npcs.has(target_npc):
		return
	if currentState == worldState.chat and currentNpc != null and str(currentNpc.npcName) != target_npc:
		var from_npc = str(currentNpc.npcName).strip_edges()
		pending_action_confirm = {
			"action": "切换对话对象到" + target_npc,
			"prompt": "是否结束与" + from_npc + "的对话并切换到" + target_npc + "？",
			"actor": from_npc,
			"mode": "switch_npc",
			"target_npc": target_npc
		}
		_set_event_flow_lock(true)
		%event.got_action_confirm_event(str(pending_action_confirm.get("action", "")), str(pending_action_confirm.get("prompt", "")))
		return
	await _start_chat_with_existing_npc(target_npc)

func _request_npc_leave_confirm(npc_name: String) -> void:
	var target_npc = str(npc_name).strip_edges()
	if target_npc == "":
		return
	pending_action_confirm = {
		"action": "允许" + target_npc + "离开",
		"prompt": target_npc + "想要离开，你要挽留吗？",
		"actor": target_npc,
		"mode": "npc_leave",
		"target_npc": target_npc
	}
	_set_event_flow_lock(true)
	%event.got_action_confirm_event(str(pending_action_confirm.get("action", "")), str(pending_action_confirm.get("prompt", "")))

func _has_active_event_panel() -> bool:
	for child in %event.get_children():
		if child is eventContainer:
			return true
	return false

func refresh_interaction_locks() -> void:
	if event_flow_lock and !_has_active_event_panel():
		event_flow_lock = false
		_log_lock_state("refresh:auto_unlock_event_flow")
	_apply_interaction_locks()

func _set_event_flow_lock(v: bool) -> void:
	event_flow_lock = v
	_log_lock_state("set_event_flow_lock:" + str(v))
	_apply_interaction_locks()
	if !event_flow_lock:
		call_deferred("_focus_active_input")

func _focus_active_input() -> void:
	if ai_busy or event_flow_lock or _has_active_event_panel():
		return
	if preferred_input_focus == "dialogue" and currentState == worldState.chat and dialogue_container.visible and currentNpc != null and dialogue_input != null:
		dialogue_input.grab_focus()
		return
	if preferred_input_focus == "action" and input_text_edit != null:
		input_text_edit.grab_focus()
		return
	if currentState == worldState.chat and dialogue_container.visible and currentNpc != null and dialogue_input != null:
		dialogue_input.grab_focus()
		return
	if input_text_edit != null:
		input_text_edit.grab_focus()

func _recover_focus_after_submit(target_focus: String) -> void:
	var target = str(target_focus).strip_edges()
	if target != "dialogue":
		target = "action"
	var retry = 0
	while retry < 180:
		await get_tree().process_frame
		if ai_busy or event_flow_lock or _has_active_event_panel():
			retry += 1
			continue
		preferred_input_focus = target
		_focus_active_input()
		return
		

func _apply_interaction_locks() -> void:
	var has_event_panel = _has_active_event_panel()
	var text_busy = !_active_text_tweens.is_empty()
	send_button.disabled = ai_busy or event_flow_lock or has_event_panel or text_busy
	dialogue_button.disabled = ai_busy or currentState != worldState.chat or has_event_panel or text_busy
	var map_lock = ai_busy or site_loading_lock or event_flow_lock or has_event_panel or text_busy
	for btn in %site_buttons.get_children():
		if btn is BaseButton:
			btn.disabled = map_lock
	for btn in %npc_buttons.get_children():
		if btn is BaseButton:
			btn.disabled = map_lock
	_log_lock_state("apply")

func _set_site_loading_lock(v: bool) -> void:
	site_loading_lock = v
	_apply_interaction_locks()

func set_ai_busy(v: bool) -> void:
	ai_busy = v
	_log_lock_state("set_ai_busy:" + str(v))
	if ai_busy:
		_apply_interaction_locks()
	else:
		refresh_interaction_locks()
		call_deferred("_focus_active_input")

func _sanitize_response_text(raw_text: String) -> String:
	var t = str(raw_text)
	t = t.replace("\ufeff", "").replace("\u200b", "")
	t = t.replace("\r\n", "\n").replace("\r", "\n")
	var lines: Array = t.split("\n", true)
	while !lines.is_empty() and str(lines[0]).strip_edges() == "":
		lines.remove_at(0)
	t = "\n".join(lines)
	return t.strip_edges(false, true)

func changeTextTo(nodeToChange: Control, text: String, speed = 30, max_tween_duration: float = 1.6):
	if nodeToChange == null:
		return
	var safe_text = text
	if nodeToChange == response_label:
		safe_text = _sanitize_response_text(text)
	else:
		safe_text = str(text).strip_edges()
	var key = str(nodeToChange.get_instance_id())
	if _active_text_tweens.has(key):
		var old_tween = _active_text_tweens[key]
		if old_tween is Tween and old_tween.is_valid():
			old_tween.kill()
		_active_text_tweens.erase(key)
		_log_lock_state("changeTextTo:kill_old_tween")

	if nodeToChange.text == safe_text:
		nodeToChange.visible_ratio = 1.0
		_log_lock_state("changeTextTo:same_text_no_tween")
		return

	_text_update_seq += 1
	var request_id = _text_update_seq
	nodeToChange.set_meta("text_request_id", request_id)
	nodeToChange.text = safe_text
	nodeToChange.visible_ratio = 0.0

	var char_count = max(1, safe_text.length())
	var safe_speed = max(1.0, float(speed))
	var max_duration = max(0.1, max_tween_duration)
	if nodeToChange == response_label:
		max_duration = max(max_duration, 4.5)
	var duration = clamp(float(char_count) / safe_speed, 0.08, max_duration)
	var tween = create_tween()
	_active_text_tweens[key] = tween
	_apply_interaction_locks()
	tween.tween_property(nodeToChange, "visible_ratio", 1.0, duration)
	await tween.finished

	if !is_instance_valid(nodeToChange):
		return
	if int(nodeToChange.get_meta("text_request_id", -1)) != request_id:
		refresh_interaction_locks()
		return
	if _active_text_tweens.get(key, null) == tween:
		_active_text_tweens.erase(key)
		_log_lock_state("changeTextTo:tween_finished")
	refresh_interaction_locks()

func clear_children(node: Node):
	var children = node.get_children()
	for i in children:
		node.remove_child(i)
		i.queue_free()

func addLog(logText: String, instant: bool = false):
	var newLog = LOG_LABEL_SCENE.instantiate()
	newLog.text = logText
	if instant and newLog is RichTextLabel:
		newLog.visible_ratio = 1.0
	%logContainer.add_child(newLog)
	if %logContainer.get_child_count() > max_visible_logs:
		var overflow = %logContainer.get_child_count() - max_visible_logs
		for i in range(overflow):
			var old_log = %logContainer.get_child(i)
			%logContainer.remove_child(old_log)
			old_log.queue_free()
	if _is_important_log(logText):
		var focus_npc = ""
		if currentNpc != null:
			focus_npc = str(currentNpc.npcName)
		_remember_important_event(logText, currentSiteName, focus_npc)

func _is_important_log(log_text: String) -> bool:
	var t = str(log_text).strip_edges()
	if t == "":
		return false
	if t.find("<BG_DEBUG>") != -1:
		return false
	var keywords = [
		"【行动】", "你抵达了", "地图更新", "传闻", "声望", "时间", "购买", "失去", "获得",
		"违规", "防盗", "警报", "主动", "交谈", "读档", "保存", "交易", "送你"
	]
	for k in keywords:
		if t.find(k) != -1:
			return true
	return false

func _extract_npc_mentions(text: String) -> Array:
	var found: Array = []
	var t = str(text)
	if t.strip_edges() == "":
		return found
	for k in npcs.keys():
		var npc_name_text = str(k)
		if npc_name_text != "" and t.find(npc_name_text) != -1 and !found.has(npc_name_text):
			found.append(npc_name_text)
	return found

func _remember_important_event(raw_text: String, site_name: String = "", focus_npc: String = "") -> void:
	var text = str(raw_text).strip_edges()
	if text == "":
		return
	var site = str(site_name).strip_edges()
	if site == "":
		site = currentSiteName
	var npc_names: Array = _extract_npc_mentions(text)
	if focus_npc.strip_edges() != "" and !npc_names.has(focus_npc):
		npc_names.append(focus_npc)
	var sig = _extract_interaction_signals(text)
	var record = {
		"text": text,
		"site": site,
		"npcs": npc_names,
		"trade": int(sig.get("trade", 0)),
		"gift": int(sig.get("gift", 0)),
		"assist": int(sig.get("assist", 0)),
		"positive": int(sig.get("positive", 0)),
		"negative": int(sig.get("negative", 0)),
		"coercion": int(sig.get("coercion", 0)),
		"respect": int(sig.get("respect", 0)),
		"t": Time.get_unix_time_from_system()
	}
	for i in range(important_event_memories.size() - 1, -1, -1):
		var old = important_event_memories[i]
		if old is Dictionary and str(old.get("text", "")) == text:
			important_event_memories.remove_at(i)
	important_event_memories.append(record)
	if important_event_memories.size() > 200:
		important_event_memories = important_event_memories.slice(max(0, important_event_memories.size() - 200), important_event_memories.size())
	var focus_name = focus_npc.strip_edges()
	for n in npc_names:
		_append_event_to_npc_memory(str(n), record, focus_name)

func _ensure_npc_event_bucket(npc_name: String) -> void:
	if npc_name == "":
		return
	if !npcs.has(npc_name) or !(npcs[npc_name] is Dictionary):
		npcs[npc_name] = {"npc_describe": "", "npc_log": [], "特征": "", "important_events": []}
	if !npcs[npc_name].has("npc_log") or !(npcs[npc_name]["npc_log"] is Array):
		npcs[npc_name]["npc_log"] = []
	if !npcs[npc_name].has("important_events") or !(npcs[npc_name]["important_events"] is Array):
		npcs[npc_name]["important_events"] = []

func _build_npc_perspective_event_text(event_text: String, npc_name: String, focus_npc: String) -> String:
	var plain = process_string(event_text).strip_edges()
	if plain == "":
		return ""
	if npc_name == focus_npc:
		if plain.begins_with("传闻："):
			return "我听到一条传闻：" + plain.trim_prefix("传闻：").strip_edges()
		return "我亲历了：" + plain
	if plain.begins_with("传闻："):
		return "和我有关的一条传闻：" + plain.trim_prefix("传闻：").strip_edges()
	return "和我相关的重要事件：" + plain

func _should_store_npc_personal_event(plain_text: String, sig: Dictionary) -> bool:
	var t = str(plain_text).strip_edges()
	if t == "":
		return false
	if t.begins_with("【行动】"):
		return false
	var outcome_flags = _extract_npc_result_outcome_flags(t, sig)
	if bool(outcome_flags.get("accepted", false)) or bool(outcome_flags.get("rejected", false)) or bool(outcome_flags.get("cooperated", false)):
		return true
	if bool(outcome_flags.get("warned", false)) or bool(outcome_flags.get("harmed", false)) or bool(outcome_flags.get("breached", false)):
		return true
	if bool(outcome_flags.get("gifted", false)) or bool(outcome_flags.get("traded", false)) or bool(outcome_flags.get("protected", false)):
		return true
	if bool(outcome_flags.get("softened", false)):
		return true
	if int(sig.get("trade", 0)) > 0 or int(sig.get("gift", 0)) > 0 or int(sig.get("assist", 0)) > 0:
		return true
	if int(sig.get("positive", 0)) > 0 or int(sig.get("negative", 0)) > 0 or int(sig.get("coercion", 0)) > 0 or int(sig.get("respect", 0)) > 0:
		return true
	var keep_keywords = [
		"传闻", "声望", "违规", "警报", "离开", "拒绝", "同意", "成交", "感谢", "敌意", "戒备", "尊重", "敬畏", "帮", "救", "冲突", "道歉", "威胁", "命令", "羞辱", "冒犯", "安慰", "保护", "信任", "怀疑", "欺骗", "冷淡", "亲近"
	]
	for kw in keep_keywords:
		if t.find(kw) != -1:
			return true
	return false

func _extract_npc_result_outcome_flags(plain_text: String, sig: Dictionary) -> Dictionary:
	var source = str(plain_text).strip_edges()
	var accepted = _contains_any_keyword(source, ["接受", "收下", "接过", "答应", "同意", "愿意", "允许", "放行", "成交", "买下", "卖给", "告诉你", "带你", "让你", "配合", "照办", "原谅", "饶过"])
	var rejected = _contains_any_keyword(source, ["拒绝", "回绝", "谢绝", "不肯", "不愿", "不同意", "无视", "不理", "赶走", "驱逐", "轰走", "拦住", "阻止", "阻拦"])
	var cooperated = int(sig.get("assist", 0)) > 0 or _contains_any_keyword(source, ["帮你", "协助", "接应", "带路", "照应", "掩护", "治疗", "救下", "保护", "替你", "配合"])
	var traded = int(sig.get("trade", 0)) > 0 or _contains_any_keyword(source, ["交易", "成交", "买下", "卖给", "付款", "付钱", "报价", "按价", "钱货两清"])
	var gifted = int(sig.get("gift", 0)) > 0 or _contains_any_keyword(source, ["送", "赠", "递给", "交给", "给你", "给我", "补给", "分享"])
	var warned = _contains_any_keyword(source, ["警报", "报警", "通缉", "围住", "盘问", "搜身", "扣留", "盯上", "怀疑", "戒备", "防盗", "违规"])
	var harmed = _contains_any_keyword(source, ["威胁", "命令", "逼", "强迫", "羞辱", "冒犯", "欺骗", "骗", "偷", "抢", "打伤", "伤害", "砍", "捅", "勒索", "辱骂"])
	var breached = _contains_any_keyword(source, ["食言", "失约", "赖账", "反悔", "违约", "不守信用", "说话不算"])
	var protected = _contains_any_keyword(source, ["救", "保护", "掩护", "照顾", "安慰", "治疗", "扶住", "拉开", "挡下"])
	var softened = _contains_any_keyword(source, ["感谢", "谢谢", "道歉", "赔偿", "归还", "谅解", "缓和", "客气"])
	if warned:
		rejected = true
	if int(sig.get("coercion", 0)) > 0:
		harmed = true
	if traded and _contains_any_keyword(source, ["成交", "买下", "卖给", "付款", "钱货两清"]):
		accepted = true
	if gifted and _contains_any_keyword(source, ["接受", "收下", "接过"]):
		accepted = true
	if protected:
		cooperated = true
	return {
		"accepted": accepted,
		"rejected": rejected,
		"cooperated": cooperated,
		"traded": traded,
		"gifted": gifted,
		"warned": warned,
		"harmed": harmed,
		"breached": breached,
		"protected": protected,
		"softened": softened
	}

func _build_npc_personal_event_summary(plain_text: String, npc_name: String, focus_npc: String, sig: Dictionary) -> String:
	var t = str(plain_text).strip_edges()
	if !_should_store_npc_personal_event(t, sig):
		return ""
	var source = _clip_prompt_text(t, 90)
	var outcome_flags = _extract_npc_result_outcome_flags(source, sig)
	if source.begins_with("传闻："):
		var rumor_text = source.trim_prefix("传闻：").strip_edges()
		if npc_name == focus_npc:
			return "我获知传闻：" + _clip_prompt_text(rumor_text, 62)
		return "相关传闻：" + _clip_prompt_text(rumor_text, 62)
	if source.find("声望值+") != -1:
		return "玩家声望上升，我对其态度更积极。"
	if source.find("声望值-") != -1:
		return "玩家声望下降，我对其更警惕。"
	if bool(outcome_flags.get("warned", false)):
		return "这次结果直接触发了警报、盘查或违规处置，我会把玩家当作高风险对象。"
	if bool(outcome_flags.get("harmed", false)):
		return "这次结果里我遭到威逼、欺骗、羞辱或实际伤害，我会记仇并明显提高戒备。"
	if bool(outcome_flags.get("breached", false)):
		return "这次结果显示玩家失约、赖账或反悔，我会把他视为不可靠的人。"
	if bool(outcome_flags.get("rejected", false)):
		return "这次结果以拒绝、阻拦或驱离收场，我会继续与玩家保持距离。"
	if bool(outcome_flags.get("protected", false)):
		return "这次结果里玩家实际保护、救助或照应了我，我会把这件事记得很深。"
	if bool(outcome_flags.get("cooperated", false)):
		return "这次结果显示玩家确实与我合作、帮忙或配合，我会更愿意继续往来。"
	if int(sig.get("trade", 0)) > 0:
		if bool(outcome_flags.get("accepted", false)):
			return "这次结果里交易真的谈成了，我会按对方是否守信、是否讲价有度来记住他。"
		if npc_name == focus_npc:
			return "我与玩家出现交易往来，我会根据最终成没成交、是否守规矩来重新判断。"
		return "我相关的交易结果已经发生，我会按照实际得失与风险重新判断玩家。"
	if int(sig.get("gift", 0)) > 0:
		if bool(outcome_flags.get("accepted", false)):
			return "这次结果里我收下了玩家给出的物品，这会明显拉近我对他的看法。"
		return "我向玩家提供了物品，若对方识趣守分，我会更愿意缓和相处。"
	if int(sig.get("assist", 0)) > 0:
		return "我与玩家有实际协作结果，这会明显影响我之后是否继续信任和配合。"
	if bool(outcome_flags.get("softened", false)):
		return "这次结果里出现感谢、道歉、赔偿或归还等明确表示，我对玩家的态度会有所松动。"
	if npc_name == focus_npc:
		return "我记住了一件会直接影响我对玩家态度的事：" + _clip_prompt_text(source, 56)
	return "有一件与我相关的事会影响我之后对玩家的判断：" + _clip_prompt_text(source, 56)

func _classify_npc_attitude_change(plain_text: String, npc_name: String, focus_npc: String, sig: Dictionary) -> Dictionary:
	var source = str(plain_text).strip_edges()
	var out = {
		"attitude": "我还会继续观察玩家，再决定该怎么对他。",
		"bond_delta": 0,
		"trust_delta": 0,
		"fear_delta": 0,
		"summary": ""
	}
	if source == "":
		return out
	var outcome_flags = _extract_npc_result_outcome_flags(source, sig)
	if source.begins_with("传闻："):
		out["summary"] = ("我得知一条与玩家有关的传闻，会据此调整看法。" if npc_name == focus_npc else "我听到与玩家有关的传闻，会影响后续判断。")
		return out
	if source.find("声望值+") != -1:
		out["attitude"] = "玩家最近名声在变好，我会更愿意高看他一眼。"
		out["bond_delta"] = 2
		out["trust_delta"] = 2
		out["summary"] = "玩家名声变好，我对其更尊重，也更愿意相信。"
		return out
	if source.find("声望值-") != -1:
		out["attitude"] = "玩家最近名声不太好，我会先留个心眼再接触。"
		out["bond_delta"] = -1
		out["trust_delta"] = -2
		out["fear_delta"] = 2
		out["summary"] = "玩家名声变差，我会更警惕，也更难轻信。"
		return out
	if bool(outcome_flags.get("warned", false)):
		out["attitude"] = "这次已经闹到警报和盘查，我会把玩家当成麻烦源主动提防。"
		out["bond_delta"] = -3
		out["trust_delta"] = -3
		out["fear_delta"] = 2
		out["summary"] = "这次结果直接发展成警报、盘查或违规处置，我会把玩家视为高风险对象。"
		return out
	if int(sig.get("coercion", 0)) > 0:
		out["attitude"] = "玩家这次是在逼我做事，我表面会应付，心里会一直防着他。"
		out["bond_delta"] = -3
		out["trust_delta"] = -2
		out["fear_delta"] = 3
		out["summary"] = "这次结果里玩家对我施压、命令或威逼，我会明显紧张、防备，表面顺从也未必真心。"
		return out
	if bool(outcome_flags.get("harmed", false)):
		out["attitude"] = "玩家这次实打实地伤到我了，我会排斥他，也不想再给他好脸色。"
		out["bond_delta"] = -3
		out["trust_delta"] = -2
		out["fear_delta"] = 1
		out["summary"] = "这次结果里玩家对我造成了伤害、羞辱、欺骗或强夺，我会更容易拒绝、顶撞或疏远。"
		return out
	if bool(outcome_flags.get("breached", false)):
		out["attitude"] = "玩家这次没有守约，我会觉得他靠不住，之后很难再轻信。"
		out["bond_delta"] = -2
		out["trust_delta"] = -3
		out["summary"] = "这次结果显示玩家失约、赖账或反悔，我会把他视为不可靠的人。"
		return out
	if bool(outcome_flags.get("rejected", false)):
		out["attitude"] = "这次我和玩家没谈拢，我会先和他拉开距离。"
		out["bond_delta"] = -2
		out["trust_delta"] = -1
		out["summary"] = "这次结果以拒绝、阻拦或驱离收场，我之后会继续与玩家保持距离。"
		return out
	if bool(outcome_flags.get("protected", false)):
		out["attitude"] = "玩家这次确实护住了我，我会把这份人情记住，也更愿意信他。"
		out["bond_delta"] = 3
		out["trust_delta"] = 3
		out["summary"] = "这次结果里玩家实际保护、救助或照应了我，我会明显更信任也更愿意回报。"
		return out
	if bool(outcome_flags.get("cooperated", false)):
		out["attitude"] = "这次合作是成了的，我会把玩家当成还能继续打交道的人。"
		out["bond_delta"] = 2
		out["trust_delta"] = 2
		out["summary"] = "这次结果显示玩家确实与我合作、帮忙或配合，我会更愿意继续往来。"
		return out
	if int(sig.get("gift", 0)) > 0:
		if bool(outcome_flags.get("accepted", false)):
			out["attitude"] = "我收下了玩家给的东西，心里自然会对他软一些。"
			out["bond_delta"] = 3
			out["trust_delta"] = 2
			out["summary"] = "这次结果里我收下了玩家给出的物品，我对其更亲近，也更容易给出善意回应。"
		else:
			out["attitude"] = "这次有了实在的物品往来，我对玩家的态度会先缓下来一点。"
			out["bond_delta"] = 2
			out["trust_delta"] = 1
			out["summary"] = "这次结果里双方有明确物品往来，彼此关系有所缓和。"
		return out
	if int(sig.get("trade", 0)) > 0:
		out["attitude"] = "交易已经发生了，我会按玩家这次办事是否靠谱来继续看他。"
		out["bond_delta"] = 1
		out["trust_delta"] = 2
		out["summary"] = "这次结果里交易已实际发生，我会更快根据对方是否守规矩、讲信用来调整后续态度。"
		return out
	if int(sig.get("assist", 0)) > 0:
		out["attitude"] = "玩家这次帮上了忙，我会觉得他至少在这件事上是能靠一下的。"
		out["bond_delta"] = 2
		out["trust_delta"] = 3
		out["summary"] = "这次结果里我与玩家有协作或帮助往来，因此更愿意信任和配合。"
		return out
	if bool(outcome_flags.get("accepted", false)):
		out["attitude"] = "这次我接受了玩家的要求，短时间内不会再对他那么绷着。"
		out["bond_delta"] = 1
		out["trust_delta"] = 1
		out["summary"] = "这次结果是接受、同意或放行，我对玩家会暂时放下些戒心。"
		return out
	if bool(outcome_flags.get("softened", false)):
		out["attitude"] = "这次结果里有赔礼、道歉或感谢，我对玩家的火气会先消一点。"
		out["bond_delta"] = 1
		out["trust_delta"] = 1
		out["summary"] = "这次结果里出现感谢、道歉、赔偿或归还等明确表示，我对玩家的态度会有所松动。"
		return out
	if _contains_any_keyword(source, ["拒绝", "敌意", "警报", "违规", "冲突", "威胁", "偷", "抢", "犯罪"]):
		out["attitude"] = "这次结果不太对劲，我会把玩家当成需要提防的人。"
		out["bond_delta"] = -3
		out["trust_delta"] = -3
		out["fear_delta"] = 2
		out["summary"] = "这次结果里出现了明显风险或冲突后果，我会更戒备，也更不愿配合。"
		return out
	if _contains_any_keyword(source, ["感谢", "帮助", "道歉", "救", "照顾", "安慰", "保护", "体谅", "信任"]):
	if npc_name == "" or !npcs.has(npc_name) or !(npcs[npc_name] is Dictionary):
		return ""
	if !npcs[npc_name].has("important_events") or !(npcs[npc_name]["important_events"] is Array):
		return ""
	var bucket: Array = npcs[npc_name]["important_events"]
	if bucket.is_empty():
		return ""
	var latest_attitude = ""
	var recent_causes: Array = []
	for i in range(bucket.size() - 1, -1, -1):
		var row = bucket[i]
		if !(row is Dictionary):
			continue
		var row_attitude = str(row.get("attitude", "")).strip_edges()
		if latest_attitude == "" and row_attitude != "":
			latest_attitude = _clip_prompt_text(row_attitude, 90)
		var row_view = str(row.get("npc_view", "")).strip_edges()
		if row_view != "":
			recent_causes.append(_clip_prompt_text(row_view, 48))
		if latest_attitude != "" and recent_causes.size() >= 2:
			break
	recent_causes.reverse()
	if latest_attitude == "" and recent_causes.is_empty():
		return ""
	if latest_attitude == "":
		latest_attitude = "我会继续根据最近和玩家之间发生的结果来判断他。"
	var lines: Array = ["- 当前态度：" + latest_attitude]
	if !recent_causes.is_empty():
		lines.append("- 态度来源：" + "；".join(recent_causes))
	return "\n".join(lines)

func _append_event_to_npc_memory(npc_name: String, record: Dictionary, focus_npc: String) -> void:
	if npc_name == "":
		return
	_ensure_npc_event_bucket(npc_name)
	var plain = process_string(str(record.get("text", ""))).strip_edges()
	if plain == "":
		return
	var sig = {
		"trade": int(record.get("trade", 0)),
		"gift": int(record.get("gift", 0)),
		"assist": int(record.get("assist", 0)),
		"positive": int(record.get("positive", 0)),
		"negative": int(record.get("negative", 0)),
		"coercion": int(record.get("coercion", 0)),
		"respect": int(record.get("respect", 0))
	}
	var npc_view = _build_npc_personal_event_summary(plain, npc_name, focus_npc, sig)
	if npc_view == "":
		return
	var attitude_row = _classify_npc_attitude_change(plain, npc_name, focus_npc, sig)
	var attitude = str(attitude_row.get("attitude", "我还会继续观察玩家，再决定该怎么对他。")).strip_edges()
	var attitude_summary = str(attitude_row.get("summary", "")).strip_edges()
	if attitude_summary != "":
		npc_view = attitude_summary
	var npc_bucket: Array = npcs[npc_name].get("important_events", [])
	for old in npc_bucket:
		if old is Dictionary and str(old.get("npc_view", "")) == npc_view and str(old.get("attitude", "")) == attitude:
			return
	npc_bucket.append({
		"text": _clip_prompt_text(plain, 90),
		"npc_view": _clip_prompt_text(npc_view, 90),
		"attitude": attitude,
		"bond_delta": int(attitude_row.get("bond_delta", 0)),
		"trust_delta": int(attitude_row.get("trust_delta", 0)),
		"fear_delta": int(attitude_row.get("fear_delta", 0)),
		"t": int(record.get("t", Time.get_unix_time_from_system()))
	})
	if npc_bucket.size() > 40:
		npc_bucket = npc_bucket.slice(npc_bucket.size() - 40, npc_bucket.size())
	npcs[npc_name]["important_events"] = npc_bucket

func _get_recent_npc_personal_events(npc_name: String, limit_count: int = 3) -> Array:
	var out: Array = []
	if npc_name == "" or !npcs.has(npc_name) or !(npcs[npc_name] is Dictionary):
		return out
	if !npcs[npc_name].has("important_events") or !(npcs[npc_name]["important_events"] is Array):
		return out
	var bucket: Array = npcs[npc_name]["important_events"]
	var start_idx = max(0, bucket.size() - limit_count)
	for i in range(start_idx, bucket.size()):
		var row = bucket[i]
		if !(row is Dictionary):
			continue
		var view_text = str(row.get("npc_view", "")).strip_edges()
		if view_text == "":
			continue
		out.append(_clip_prompt_text(view_text, 80))
	return out

func _score_event_relevance(mem: Dictionary, site_name: String, npc_name: String, intent_hint: Dictionary = {}) -> int:
	var score = 0
	if str(mem.get("site", "")) == site_name and site_name != "":
		score += 2
	if npc_name != "":
		var arr = mem.get("npcs", [])
		if arr is Array and arr.has(npc_name):
			score += 4
	if !intent_hint.is_empty():
		score += min(int(mem.get("trade", 0)), int(intent_hint.get("trade", 0)))
		score += min(int(mem.get("gift", 0)), int(intent_hint.get("gift", 0)))
		score += min(int(mem.get("assist", 0)), int(intent_hint.get("assist", 0)))
	return score

func _get_recent_related_event_memories(site_name: String, npc_name: String = "", limit_count: int = 4, intent_hint: Dictionary = {}) -> Array:
	var scored: Array = []
	for mem_item in important_event_memories:
		if !(mem_item is Dictionary):
			continue
		var mem: Dictionary = mem_item
		var score = _score_event_relevance(mem, site_name, npc_name, intent_hint)
		if score <= 0:
			continue
		scored.append({"score": score, "mem": mem})
	scored.sort_custom(func(a, b):
		var sa = int(a.get("score", 0))
		var sb = int(b.get("score", 0))
		if sa == sb:
			return int(a.get("mem", {}).get("t", 0)) > int(b.get("mem", {}).get("t", 0))
		return sa > sb
	)
	var out: Array = []
	for row in scored:
		out.append(row.get("mem", {}))
		if out.size() >= limit_count:
			break
	return out

func get_relevant_event_memory_for_npc(npc_name: String, _npc_desc: String = "") -> String:
	var attitude_state = _build_npc_attitude_state_text(npc_name)
	var personal_rows = _get_recent_npc_personal_events(npc_name, 4)
	if !personal_rows.is_empty() or attitude_state != "":
		var personal_lines: Array = []
		if attitude_state != "":
			personal_lines.append(attitude_state)
		for line in personal_rows:
			personal_lines.append("- " + str(line))
		return _clip_prompt_text("\n".join(personal_lines), 320)
	var rows = _get_recent_related_event_memories(currentSiteName, npc_name, 2)
	if rows.is_empty():
		return ""
	var lines: Array = []
	for m in rows:
		if m is Dictionary:
			lines.append("- " + _clip_prompt_text(str(m.get("text", "")), 90))
	return _clip_prompt_text("\n".join(lines), 260)

func _build_identity_attitude_guidance(focus_npc_name: String = "", focus_npc_desc: String = "") -> String:
	var lines: Array = []
	var player_role_text = (playerName + " " + world_seed_input).strip_edges()
	var npc_text = (focus_npc_name + " " + focus_npc_desc).strip_edges()
	lines.append("- 玩家身份（系统确认）:" + playerName)
	if _contains_any_keyword(player_role_text, ["国王", "皇帝", "君主", "王", "摄政", "王储"]):
		lines.append("- 统治身份导向：普通NPC默认更谨慎/敬畏，除非有强事件依据才会顶撞。")
	if _contains_any_keyword(player_role_text, ["奴隶主", "领主", "将军", "军阀", "老板", "主任", "警长"]):
		lines.append("- 权力导向：NPC态度需体现权力差（迎合/畏惧/压抑反感），不可按陌生平民处理。")
	if _contains_any_keyword(player_role_text, ["囚犯", "逃犯", "通缉", "流浪汉", "乞丐"]):
		lines.append("- 风险身份导向：NPC更可能戒备、排斥或利用。")
	if reputation >= 130.0:
		lines.append("- 声望高导向：NPC更易尊重、配合。")
	elif reputation <= 60.0:
		lines.append("- 声望低导向：NPC更易警惕、厌恶或拒绝。")
	if focus_npc_name != "":
		lines.append("- 当前NPC：" + focus_npc_name + "（" + focus_npc_desc + "）")
		if _contains_any_keyword(npc_text, ["护卫", "保安", "警察", "士兵", "侍卫"]):
			lines.append("- 秩序角色导向：更重规则/风险/立场，不会无条件顺从。")
		if _contains_any_keyword(npc_text, ["平民", "学生", "路人", "店员", "仆人"]):
			lines.append("- 普通角色导向：在高权势面前通常更保守或顺从。")
	return "\n".join(lines)

func get_identity_attitude_guidance_for_npc(npc_name: String, npc_desc: String = "") -> String:
	return _build_identity_attitude_guidance(npc_name, npc_desc)

func _build_related_event_memory_for_action(action_text: String, focus_npc_name: String = "") -> String:
	var hint = _extract_interaction_signals(action_text)
	var focus_npc = focus_npc_name.strip_edges()
	var mentions = _extract_npc_mentions(action_text)
	if !mentions.is_empty():
		focus_npc = str(mentions[0])
	if focus_npc != "":
		var attitude_state = _build_npc_attitude_state_text(focus_npc)
		var personal_rows = _get_recent_npc_personal_events(focus_npc, 4)
		if !personal_rows.is_empty() or attitude_state != "":
			var personal_lines: Array = []
			if attitude_state != "":
				personal_lines.append(attitude_state)
			for line in personal_rows:
				personal_lines.append("- " + str(line))
			return _clip_prompt_text("\n".join(personal_lines), 320)
	var rows = _get_recent_related_event_memories(currentSiteName, focus_npc, 2, hint)
	if rows.is_empty():
		return ""
	var lines: Array = []
	for m in rows:
		if m is Dictionary:
			lines.append("- " + _clip_prompt_text(str(m.get("text", "")), 90))
	return _clip_prompt_text("\n".join(lines), 260)

func _build_inventory_snapshot(max_items: int = 6) -> String:
	var parts: Array = []
	for child in %itemContainer.get_children():
		if child is item:
			parts.append(str(child.item_name) + "x" + str(child.item_num))
			if parts.size() >= max_items:
				break
	if parts.is_empty():
		return "空"
	return "，".join(parts)

# ==================== HTTP 响应处理 ====================
func _on_request_completed(result, response_code, _header, body):
	set_ai_busy(false)
	if result != HTTPRequest.RESULT_SUCCESS:
		changeTextTo(response_label, "网络错误: " + str(result))
		return
	if response_code != 200:
		changeTextTo(response_label, "服务器错误: " + str(response_code))
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		changeTextTo(response_label, "解析响应失败")
		return
	var data = json.get_data()
	if data.has("text"):
		match currentMode:
			aiMode.init_background:
				background = data["text"]
				print(background)
			aiMode.init_env:
				print(data["text"])
				var jsonDic = extract_json_from_text(data["text"])
				if jsonDic == {}:
					print("天气初始化失败")
					if has_node("mainMenu") and $mainMenu.has_method("if_weather_failed"):
						$mainMenu.if_weather_failed("天气配置解析失败，已使用默认天气。")
					return
				envDic =jsonDic
				if %envContainer.load_weather_config_from_json(envDic):
					$mainMenu.if_weather_ok()
				else:
					if has_node("mainMenu") and $mainMenu.has_method("if_weather_failed"):
						$mainMenu.if_weather_failed("天气配置校验失败，已回退默认天气。")
			aiMode.explore:
				var jsonDic = extract_json_from_text(data["text"])
				if jsonDic == {}:
					_bg_debug("explore JSON parse failed for " + pending_explore_target)
					pending_site_update = false
					_set_site_loading_lock(false)
					return
				# 先确保必要字段存在
				jsonDic["能前往的地点"] = _extract_route_candidates_from_site_json(jsonDic)
				if !jsonDic.has("npc") or !(jsonDic["npc"] is Dictionary):
					jsonDic["npc"] = {}
				if !jsonDic.has("英文描述") or str(jsonDic.get("英文描述", "")).strip_edges() == "":
					jsonDic["英文描述"] = str(jsonDic.get("地点描述", ""))
				var location_name = str(jsonDic.get("地点名称", ""))
				var model_location_name = location_name
				if location_name == "" and pending_explore_target != "":
					location_name = pending_explore_target
					jsonDic["地点名称"] = location_name
				if pending_explore_target != "":
					var target_name = _resolve_site_alias(pending_explore_target)
					if target_name != "":
						location_name = target_name
						jsonDic["地点名称"] = location_name
				if model_location_name != "" and model_location_name != location_name:
					var aliases: Array = []
					if jsonDic.has("别名") and jsonDic["别名"] is Array:
						aliases = jsonDic["别名"]
					if !aliases.has(model_location_name):
						aliases.append(model_location_name)
					jsonDic["别名"] = aliases
				if !jsonDic.has("地点描述") or str(jsonDic.get("地点描述", "")).strip_edges() == "":
					jsonDic["地点描述"] = _build_location_fallback_description(location_name, currentSiteName)
				if location_name == "":
					changeTextTo(response_label, "地点信息解析失败，请重试")
					set_ai_busy(false)
					return
				var cleaned_routes: Array = []
				for raw_route in jsonDic.get("能前往的地点", []):
					var normalized_route = _resolve_site_alias(str(raw_route).strip_edges())
					if normalized_route == "" or normalized_route == location_name or cleaned_routes.has(normalized_route):
						continue
					cleaned_routes.append(normalized_route)
				jsonDic["能前往的地点"] = cleaned_routes
				if cleaned_routes.is_empty() and explore_route_retry_count < 1:
					explore_route_retry_count += 1
					_bg_debug("explore empty routes, signaling goto() to retry")
					explore_needs_retry = true
				else:
					explore_route_retry_count = 0
				print("能前往的地点", jsonDic["能前往的地点"])
				if currentSiteName != "" && !jsonDic["能前往的地点"].has(currentSiteName):
					jsonDic["能前往的地点"].append(currentSiteName)
				# 已经存在，执行合并操作
				var old_site: Dictionary = {}
				if sites.has(location_name) and sites[location_name] is Dictionary:
					old_site = sites[location_name]

				if !old_site.is_empty():
					if old_site.has("能前往的地点") and old_site["能前往的地点"] is Array:
						for old_route in old_site["能前往的地点"]:
							if !jsonDic["能前往的地点"].has(old_route):
								jsonDic["能前往的地点"].append(old_route)
						print("发现了预先存在的地点")
					if old_site.has("npc") and old_site["npc"] is Dictionary:
						for npc_name in old_site["npc"].keys():
							if !jsonDic["npc"].has(npc_name):
								jsonDic["npc"][npc_name] = old_site["npc"][npc_name]
						print("发现了预先存在的npc")

				if model_location_name != "" and model_location_name != location_name and sites.has(model_location_name):
					var alias_site = sites[model_location_name]
					if alias_site is Dictionary:
						if alias_site.has("能前往的地点") and alias_site["能前往的地点"] is Array:
							for old_route in alias_site["能前往的地点"]:
								if !jsonDic["能前往的地点"].has(old_route):
									jsonDic["能前往的地点"].append(old_route)
						if alias_site.has("npc") and alias_site["npc"] is Dictionary:
							for npc_name in alias_site["npc"].keys():
								if !jsonDic["npc"].has(npc_name):
									jsonDic["npc"][npc_name] = alias_site["npc"][npc_name]
					sites.erase(model_location_name)

				sites[location_name] = jsonDic
				if currentSiteName != "" and currentSiteName != location_name:
					create_location(currentSiteName + "-" + location_name)
				currentSiteName = location_name
				pending_explore_target = ""
				_save_site_json(location_name, jsonDic)
				pending_site_update = false
			aiMode.chat:
				#print("开始聊天")
				var chat_text = _enforce_output_min_length(str(data.get("text", "")), aiMode.chat)
				npc_reply(chat_text)
			aiMode.action:
				var action_reply = _enforce_output_min_length(str(data.get("text", "")), aiMode.action)
				action_reply = _enforce_action_narration_richness(action_reply)
				if action_reply is String and action_reply.strip_edges() != "":
					_set_event_flow_lock(true)
					changeTextTo(%speakerNameLabel, "【旁白】")
					changeTextTo(response_label, process_string(action_reply))
					var tool_tags = get_content_in_angle_brackets(action_reply)
					var direct_tag_result = _apply_direct_action_tool_tags(action_reply)
					var handled_direct = bool(direct_tag_result.get("handled_any", false))
					var unresolved_tags = str(direct_tag_result.get("unresolved_tags", ""))
					var nav_target = str(direct_tag_result.get("nav_target", ""))
					if nav_target == "":
						nav_target = _extract_nav_target_from_text(action_reply)
					if unresolved_tags != "":
						var aprompts = [
							{"role":"system","content": agent_prompt},
							{"role":"user","content": unresolved_tags}]
						await ask_ai(aprompts, aiMode.tools)
					elif !handled_direct:
						var infer_prompts = [
							{"role":"system","content": agent_prompt + "\n若输入没有<>标签，也要从语义中尽力提取可执行方法；如果确实没有再回复没有方法被调用。"},
							{"role":"user","content": "玩家行动：" + last_action_input + "\n旁白结果：" + action_reply}
						]
						await ask_ai(infer_prompts, aiMode.tools)
						_auto_handle_action_search(last_action_input, action_reply)
					if currentState == worldState.chat and currentNpc != null:
						_record_current_chat_session("行动结果", "旁白", action_reply)
						_remember_important_event("<行动结果>" + str(currentNpc.npcName) + "：" + process_string(action_reply), currentSiteName, str(currentNpc.npcName))
					await _auto_apply_action_effects(last_action_input, action_reply, tool_tags)
					if nav_target != "" and currentState != worldState.chat:
						advance_time_minutes(float(randi_range(15, 60)), true)
						await goto(nav_target)
					if currentState != worldState.chat and !_has_active_event_panel():
						_set_event_flow_lock(false)
				else:
					_set_event_flow_lock(false)
			aiMode.sum:
				if currentNpc != null:
					var sum_npc_name = str(currentNpc.npcName).strip_edges()
					if sum_npc_name != "":
						if !npcs.has(sum_npc_name) or !(npcs[sum_npc_name] is Dictionary):
							npcs[sum_npc_name] = {"npc_describe": "", "npc_log": [], "特征": "", "important_events": []}
						if !npcs[sum_npc_name].has("npc_log") or !(npcs[sum_npc_name]["npc_log"] is Array):
							npcs[sum_npc_name]["npc_log"] = []
						npcs[sum_npc_name]["npc_log"].append(str(data.get("text", "")))
						addLog("你结束了与" + sum_npc_name + "的对话。" + str(data.get("text", "")))
			aiMode.tools:
				if data["text"] is Array:
					await handle_npc_instruction(data["text"])
				elif data["text"] is Dictionary:
					await handle_npc_instruction([data["text"]])
				elif data["text"] is String:
					var parser = JSON.new()
					if parser.parse(data["text"]) == OK:
						var parsed = parser.get_data()
						if parsed is Array:
							await handle_npc_instruction(parsed)
						elif parsed is Dictionary and parsed.has("function"):
							await handle_npc_instruction([parsed])
	else:
		changeTextTo(response_label, "响应格式错误")

func apply_passive_recovery(minutes: float) -> Dictionary:
	var m = max(0.0, minutes)
	if m <= 0.0:
		return {"hours": 0.0, "energy": 0.0, "hp": 0.0}
	var hours = m / 60.0
	var energy_gain = hours * PASSIVE_ENERGY_RECOVERY_PER_HOUR
	var hp_gain = hours * PASSIVE_HP_RECOVERY_PER_HOUR
	var before_energy = energy
	var before_hp = hp
	energy = clamp(energy + energy_gain, 0.0, 100.0)
	hp = clamp(hp + hp_gain, 0.0, 100.0)
	return {
		"hours": hours,
		"energy": max(0.0, energy - before_energy),
		"hp": max(0.0, hp - before_hp)
	}

func advance_time_minutes(minutes: float, with_log: bool = false) -> Dictionary:
	var safe_minutes = max(0.0, minutes)
	nowtime += safe_minutes
	var rec = apply_passive_recovery(safe_minutes)
	if with_log and safe_minutes > 0.0:
		addLog("<时间流逝" + str(snappedf(rec.get("hours", 0.0), 0.1)) + "小时：体力+" + str(int(round(rec.get("energy", 0.0)))) + "，健康+" + str(int(round(rec.get("hp", 0.0)))) + ">")
	player_update()
	return rec

func on_event_decision(event_kind: String, accepted: bool, item_name: String, quantity: int, total_price: int = 0) -> void:
	var speaker = "路人"
	if currentNpc != null:
		speaker = str(currentNpc.npcName)
	if event_kind == "action_confirm":
		var confirm_data: Dictionary = pending_action_confirm
		var action_actor = str(confirm_data.get("actor", speaker))
		var action_text = str(confirm_data.get("action", item_name))
		var action_mode = str(confirm_data.get("mode", "player_execute"))
		if action_mode == "npc_leave":
			var target_npc = str(confirm_data.get("target_npc", action_actor)).strip_edges()
			if accepted:
				await changeTextTo(%speakerNameLabel, target_npc)
				await changeTextTo(response_label, "……那我先不走。")
				addLog("<你拦下了" + target_npc + "，对方暂时没有离开>")
			else:
				await changeTextTo(%speakerNameLabel, target_npc)
				await changeTextTo(response_label, "好，那我就先离开了。")
				await destroy_yourself(target_npc)
			pending_action_confirm = {}
			call_deferred("_focus_active_input")
			return
		if action_mode == "leave_chat":
			if accepted:
				await changeTextTo(%speakerNameLabel, action_actor)
				await changeTextTo(response_label, "好，先到这里。")
				await changeStateInto(GameManager.worldState.explore)
			else:
				await changeTextTo(%speakerNameLabel, action_actor)
				await changeTextTo(response_label, "那就继续聊。")
				addLog("<你选择继续与" + action_actor + "对话>")
			pending_action_confirm = {}
			call_deferred("_focus_active_input")
			return
		if action_mode == "switch_site":
			var target_site = _resolve_site_alias(str(confirm_data.get("target_site", "")).strip_edges())
			if accepted and target_site != "":
				await changeTextTo(%speakerNameLabel, action_actor)
				await changeTextTo(response_label, "行，你先去吧。")
				await goto(target_site)
			else:
				await changeTextTo(%speakerNameLabel, action_actor)
				await changeTextTo(response_label, "那就先别走。")
				addLog("<你取消了前往" + target_site + ">")
			pending_action_confirm = {}
			call_deferred("_focus_active_input")
			return
		if action_mode == "switch_npc":
			var target_npc = str(confirm_data.get("target_npc", "")).strip_edges()
			if accepted and target_npc != "":
				await _start_chat_with_existing_npc(target_npc)
			else:
				await changeTextTo(%speakerNameLabel, action_actor)
				await changeTextTo(response_label, "那就先不换人。")
				if target_npc != "":
					addLog("<你取消了切换到" + target_npc + "的对话>")
			pending_action_confirm = {}
			call_deferred("_focus_active_input")
			return
		if accepted:
			await changeTextTo(%speakerNameLabel, action_actor)
			if action_mode == "force_execute":
				await changeTextTo(response_label, "你要硬来？行，你试试看。")
				addLog("<你选择强硬执行：" + action_text + ">")
			else:
				await changeTextTo(response_label, "好，那就按你说的做。")
				addLog("<你接受了" + action_actor + "的行动建议：" + action_text + ">")
			await _submit_action_input(action_text, true)
		else:
			await changeTextTo(%speakerNameLabel, action_actor)
			await changeTextTo(response_label, "行，那先按你的意思来。")
			addLog("<你拒绝了" + action_actor + "的行动建议：" + action_text + ">")
		pending_action_confirm = {}
		call_deferred("_focus_active_input")
		return
	if accepted:
		if event_kind == "deal":
			await changeTextTo(%speakerNameLabel, speaker)
			await changeTextTo(response_label, "行，" + str(item_name) + "给你，收你" + str(total_price) + "。")
			addLog("<" + speaker + "：成交。>")
		elif event_kind == "gift":
			await changeTextTo(%speakerNameLabel, speaker)
			await changeTextTo(response_label, "拿着吧，这" + str(quantity) + "个" + str(item_name) + "你用得上。")
			addLog("<" + speaker + "：收下吧。>")
	else:
		await changeTextTo(%speakerNameLabel, speaker)
		if event_kind == "deal":
			await changeTextTo(response_label, "那就算了，下次想买再来。")
		else:
			await changeTextTo(response_label, "你要是不要，我就先收着。")



var weather:String = """
	"""

func _drain_pending_img() -> void:
	if pending_img_prompt != "":
		var queued = pending_img_prompt
		var queued_site = pending_img_site
		pending_img_prompt = ""
		pending_img_site = ""
		gen_img(queued, queued_site)

func _on_img_http_request_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	img_watchdog_seq += 1
	var callback_site = inflight_img_site
	inflight_img_site = ""
	if callback_site == "":
		callback_site = currentSiteName
	_bg_debug("img callback, site=" + callback_site + ", result=" + str(result) + ", code=" + str(response_code) + ", body_len=" + str(body.size()))
	if result != HTTPRequest.RESULT_SUCCESS:
		print("图片生成失败：网络错误")
		_bg_debug("img callback network failed")
		if pending_site_update:
			pending_site_update = false
			site_update()
		_drain_pending_img()
		return

	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())

	if parse_error != OK:
		print("图片生成失败：响应解析错误", body.get_string_from_utf8())
		_bg_debug("img callback parse failed")
		if pending_site_update:
			pending_site_update = false
			site_update()
		_drain_pending_img()
		return

	var response = json.get_data()

	if response_code == 200 and response.get("success", false):
		var image_data = response.get("image", "")
		if image_data:
			_display_base64_image(image_data, callback_site)
		else:
			print("图片生成失败：未收到图片数据")
			_bg_debug("img callback success=true but image empty")
			if pending_site_update:
				pending_site_update = false
				site_update()
		if pending_site_update:
			pending_site_update = false
			site_update()
		_drain_pending_img()
	else:
		var error_msg = response.get("error", "未知错误")
		print("图片生成失败：" + error_msg)
		var debug_data = response.get("debug", {})
		if debug_data is Dictionary and !debug_data.is_empty():
			print("[IMG_CLIENT_DEBUG] provider=", str(debug_data.get("provider", "")),
				" status=", str(debug_data.get("status_code", "")),
				" content_type=", str(debug_data.get("content_type", "")),
				" cf_ray=", str(debug_data.get("cf_ray", "")))
			if debug_data.has("response_preview"):
				print("[IMG_CLIENT_DEBUG] response_preview=", str(debug_data.get("response_preview", "")))
			if debug_data.has("exception"):
				print("[IMG_CLIENT_DEBUG] exception=", str(debug_data.get("exception", "")))
			if debug_data.has("request"):
				print("[IMG_CLIENT_DEBUG] request=", JSON.stringify(debug_data.get("request", {})))
		_bg_debug("img callback failed, error=" + error_msg + ", has_debug=" + str(debug_data is Dictionary and !debug_data.is_empty()))
		if pending_site_update:
			pending_site_update = false
			site_update()
		elif site_loading_lock:
			site_update(true, true, false)
		_drain_pending_img()

func _extract_first_number(text: String) -> int:
	var regex = RegEx.new()
	if regex.compile("(\\d+)") != OK:
		return 0
	var m = regex.search(text)
	if m == null:
		return 0
	return int(m.get_string(1))

func _extract_duration_hours(text: String) -> float:
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

func _extract_target_time(text: String) -> Dictionary:
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

func _auto_initiate_npc_chat(npc_name: String, npc_describe: String) -> void:
	var retry = 0
	while (ai_busy or currentState == worldState.chat) and retry < 200:
		await get_tree().create_timer(0.15).timeout
		retry += 1
	if ai_busy or currentState == worldState.chat:
		_set_event_flow_lock(false)
		return
	if !npcs.has(npc_name):
		npcs[npc_name] = {"npc_describe": npc_describe, "npc_log": [], "特征": ""}
	if !npcs[npc_name].has("npc_describe"):
		npcs[npc_name]["npc_describe"] = npc_describe
	if !npcs[npc_name].has("npc_log"):
		npcs[npc_name]["npc_log"] = []
	var new_npc = npc.new()
	new_npc.npcName = npc_name
	new_npc.scene = self
	new_npc.npcDescribe = npc_describe
	var logs = ""
	_append_event_memories_to_npc_log(npc_name)
	for log_entry in npcs[npc_name]["npc_log"]:
		logs += log_entry
	new_npc.npcLog = logs
	newNpc = new_npc
	await changeStateInto(GameManager.worldState.chat)
	_set_event_flow_lock(false)

func _pick_crime_npc_from_action(action_input: String) -> Dictionary:
	var cleaned = action_input.strip_edges()
	if cleaned != "":
		for npc_name in npcs.keys():
			var n = str(npc_name)
			if cleaned.find(n) != -1:
				var data = npcs[n]
				if data is Dictionary:
					return {
						"name": n,
						"describe": str(data.get("npc_describe", "神情紧张地盯着你"))
					}
	if currentSiteName.find("宿舍") != -1:
		return {"name": "宿管阿姨", "describe": "拿着登记本、神情警惕地走了过来"}
	if currentSiteName.find("学校") != -1 or currentSiteName.find("教学") != -1:
		return {"name": "值班老师", "describe": "皱着眉、快步走来的值班老师"}
	var sig = _detect_setting_style_signals()
	if bool(sig.get("ancient", false)) and !bool(sig.get("bridge", false)):
		return {"name": "巡城卫兵", "describe": "披甲执戟、神情严厉地拦下了你"}
	if bool(sig.get("scifi", false)) or bool(sig.get("cyber", false)):
		return {"name": "安保巡查员", "describe": "佩戴识别终端、语气冷硬地要求你停下"}
	return {}

func _build_proactive_npc_pool(reason: String) -> Array:
	var sig = _detect_setting_style_signals()
	var pool_map: Dictionary = {}
	if bool(sig.get("ancient", false)) and !bool(sig.get("bridge", false)):
		pool_map = {
			"money": [
				{"name": "集市掌柜", "describe": "拨着算盘、目光精明的掌柜"},
				{"name": "巡街差役", "describe": "腰挎短刀、神情警觉的差役"},
				{"name": "庄园管事", "describe": "衣着整肃、语气克制的管事"}
			],
			"exercise": [
				{"name": "武馆教头", "describe": "身形稳健、目光锐利的教头"},
				{"name": "营中老兵", "describe": "披着旧甲、说话干练的老兵"},
				{"name": "猎场向导", "describe": "背弓挎囊、步伐利落的向导"}
			],
			"time_pass": [
				{"name": "过路行商", "describe": "牵着驮兽、一路吆喝的行商"},
				{"name": "驿站信使", "describe": "披尘快步、神色匆匆的信使"},
				{"name": "城门小吏", "describe": "手持簿册、谨慎打量来人的小吏"}
			],
			"crime": [
				{"name": "巡城卫兵", "describe": "披甲执戟、面色不善的卫兵"},
				{"name": "庄园监工", "describe": "手持皮鞭、语气严厉的监工"},
				{"name": "目击商贩", "describe": "抱紧货箱、神色惊惧的商贩"}
			]
		}
	elif bool(sig.get("scifi", false)) or bool(sig.get("cyber", false)):
		pool_map = {
			"money": [
				{"name": "交易站文员", "describe": "佩戴终端、谨慎核验账目的文员"},
				{"name": "站区安保", "describe": "穿着防护装、目光冷静的安保"},
				{"name": "通道巡检员", "describe": "提着检测仪、步伐稳健的巡检员"}
			],
			"exercise": [
				{"name": "训练官", "describe": "佩戴护甲、下令简洁的训练官"},
				{"name": "机修技师", "describe": "手上沾着油污、动作麻利的技师"},
				{"name": "外勤队员", "describe": "背着装备包、目光冷静的队员"}
			],
			"time_pass": [
				{"name": "引导员", "describe": "手持投影地图、态度专业的引导员"},
				{"name": "远行乘客", "describe": "拖着箱包、神情疲惫的乘客"},
				{"name": "后勤调度员", "describe": "不断核对清单、语速很快的调度员"}
			],
			"crime": [
				{"name": "安保巡查员", "describe": "佩戴识别终端、语气冷硬的巡查员"},
				{"name": "目击维修工", "describe": "握着扳手、神情紧张的维修工"},
				{"name": "封控执行员", "describe": "启动警戒程序、要求你停下的执行员"}
			]
		}
	else:
		pool_map = {
			"money": [
				{"name": "路过行人", "describe": "步伐匆匆、却忍不住多看你一眼的行人"},
				{"name": "值守人员", "describe": "神情警觉、习惯观察周围的值守人员"},
				{"name": "小摊商贩", "describe": "守着摊位、眼神精明的商贩"}
			],
			"exercise": [
				{"name": "训练者", "describe": "动作利落、状态很好的训练者"},
				{"name": "晨练路人", "describe": "呼吸平稳、步伐轻快的路人"},
				{"name": "教习", "describe": "目光专注、语气沉稳的教习"}
			],
			"time_pass": [
				{"name": "热心路人", "describe": "愿意搭话、对周围很熟悉的路人"},
				{"name": "陌生访客", "describe": "拿着地图、看起来有些迷路的人"},
				{"name": "本地向导", "describe": "语气友好、对地形很熟的向导"}
			],
			"crime": [
				{"name": "巡逻人员", "describe": "脚步急促、神情严肃地靠近你的人"},
				{"name": "目击者", "describe": "突然出现在旁边、一脸惊讶的目击者"},
				{"name": "工作人员", "describe": "眼神警惕、快步走来的工作人员"}
			]
		}
	if pool_map.has(reason):
		return pool_map[reason]
	return []

func _spawn_context_npc(reason: String, forced_npc: Dictionary = {}, context_text: String = "") -> void:
	if currentSiteName == "":
		return
	_set_event_flow_lock(true)
	var npc_name = ""
	var npc_describe = ""
	if !forced_npc.is_empty():
		npc_name = str(forced_npc.get("name", "")).strip_edges()
		npc_describe = str(forced_npc.get("describe", "正在此地活动"))
	else:
		var pool: Array = _build_proactive_npc_pool(reason)
		if pool.is_empty():
			_set_event_flow_lock(false)
			return
		var pick = pool[randi_range(0, pool.size() - 1)]
		npc_name = str(pick.get("name", "路人"))
		npc_describe = str(pick.get("describe", "正在此地活动"))
	if dead_npc_names.has(npc_name):
		_set_event_flow_lock(false)
		return

	if npc_name == "":
		_set_event_flow_lock(false)
		return
	var npc_existed = npcs.has(npc_name)
	if !npcs.has(npc_name):
		npcs[npc_name] = {"npc_describe": npc_describe, "npc_log": [], "特征": ""}
	if !npcs[npc_name].has("npc_describe"):
		npcs[npc_name]["npc_describe"] = npc_describe
	if !npcs[npc_name].has("npc_log") or !(npcs[npc_name]["npc_log"] is Array):
		npcs[npc_name]["npc_log"] = []
	var scoped_context = context_text.strip_edges()
	if scoped_context == "" and reason == "crime":
		scoped_context = last_crime_event_context.strip_edges()
	if scoped_context != "":
		var context_note = ""
		match reason:
			"money":
				context_note = "系统记录：玩家刚进行与金钱有关的行动【" + scoped_context + "】。你要围绕这件事开场。"
			"exercise":
				context_note = "系统记录：玩家刚进行体能相关行动【" + scoped_context + "】。你要围绕这件事开场。"
			"time_pass":
				context_note = "系统记录：玩家刚完成一段行动【" + scoped_context + "】。你要围绕这件事开场。"
			"crime":
				context_note = "系统记录：玩家刚刚因【" + scoped_context + "】触发警报，你需要围绕这件事追问。"
			_:
				context_note = ""
		if context_note != "":
			var context_log_arr: Array = npcs[npc_name]["npc_log"]
			for i in range(context_log_arr.size() - 1, -1, -1):
				var old_note = str(context_log_arr[i])
				if old_note.begins_with("系统记录：玩家刚"):
					context_log_arr.remove_at(i)
			if context_log_arr.is_empty() or str(context_log_arr[context_log_arr.size() - 1]) != context_note:
				context_log_arr.append(context_note)
			npcs[npc_name]["npc_log"] = context_log_arr
	if reason == "crime":
		addLog("<" + npc_name + "拦住了你，开始质问刚才的异常动静。>")

	if npc_existed:
		await get_tree().create_timer(0.4).timeout
		await _auto_initiate_npc_chat(npc_name, str(npcs[npc_name].get("npc_describe", npc_describe)))
		return

	# 旧逻辑（保留）: create_NPC + addLog，仅记录不主动对话
	# create_NPC(npc_name, currentSiteName, npc_describe)
	# addLog("<" + npc_name + "主动与你有了互动。>")

	# 新逻辑：创建NPC并延迟自动开启对话
	create_NPC(npc_name, currentSiteName, npc_describe)
	addLog("<" + npc_name + "注意到了你，主动走了过来。>")
	await get_tree().create_timer(0.8).timeout
	await _auto_initiate_npc_chat(npc_name, npc_describe)

func _trigger_time_pass_npc_event(hours: float, action_context: String = "") -> bool:
	if hours < 0.5:
		return false
	if randf() < ACTION_PROACTIVE_NPC_RATE:
		await _spawn_context_npc("time_pass", {}, action_context)
		return true
	return false

func _build_action_context_text(action_input: String, action_reply: String) -> String:
	var context_text = action_input.strip_edges()
	if context_text == "":
		context_text = process_string(action_reply).strip_edges()
	if context_text == "":
		context_text = (action_input + " " + process_string(action_reply)).strip_edges()
	return context_text.left(64)

func _extract_signed_number(text: String) -> int:
	var regex = RegEx.new()
	if regex.compile("([+-]?\\d+)") != OK:
		return 0
	var m = regex.search(text)
	if m == null:
		return 0
	return int(m.get_string(1))

func _extract_money_delta_from_text(text: String) -> int:
	var plain = process_string(text).strip_edges()
	if plain == "":
		return 0
	var spend_patterns = ["花费", "花了", "花去", "支付", "付了", "付款", "消费", "支出", "扣除", "减少", "损失", "收你"]
	for p in spend_patterns:
		var spend_regex = RegEx.new()
		if spend_regex.compile(p + "\\s*(\\d+)") == OK:
			var spend_match = spend_regex.search(plain)
			if spend_match != null:
				return -int(spend_match.get_string(1))
	var income_patterns = ["获得", "赚了", "收入", "得到", "返还", "退款", "增加了"]
	for p in income_patterns:
		var income_regex = RegEx.new()
		if income_regex.compile(p + "\\s*(\\d+)") == OK:
			var income_match = income_regex.search(plain)
			if income_match != null:
				return int(income_match.get_string(1))
	return 0

func _build_crime_context(action_input: String, action_reply: String, tool_tags: String) -> String:
	var tags = _extract_angle_tags(tool_tags + action_reply)
	for tag in tags:
		var normalized = str(tag).replace("：", ":").strip_edges()
		if normalized.begins_with("犯罪:"):
			return normalized.trim_prefix("犯罪:").strip_edges()
	var input_text = action_input.strip_edges()
	if input_text != "":
		return input_text.left(36)
	var plain = process_string(action_reply).strip_edges()
	if plain != "":
		return plain.left(36)
	return "可疑行为"

func _apply_direct_action_tool_tags(action_reply: String) -> Dictionary:
	var tags = _extract_angle_tags(action_reply)
	if tags.is_empty():
		return {"handled_any": false, "unresolved_tags": "", "nav_target": ""}
	var unresolved = ""
	var handled_any = false
	var nav_target = ""
	for raw_tag in tags:
		var normalized = str(raw_tag).replace("：", ":").strip_edges()
		if normalized == "":
			continue
		if normalized.begins_with("资产") or normalized.begins_with("金币") or normalized.begins_with("金钱"):
			var money_delta = _extract_signed_number(normalized)
			if money_delta != 0:
				var before_money = money
				money = max(0, money + money_delta)
				var real_delta = money - before_money
				if real_delta != 0:
					var sign = "+" if real_delta > 0 else ""
					addLog("<资产变化" + sign + str(real_delta) + "，当前资产" + str(money) + ">")
				handled_any = true
			else:
				unresolved += "<" + raw_tag + ">"
		elif normalized.begins_with("声望值"):
			var rep_delta = _extract_signed_number(normalized.trim_prefix("声望值").strip_edges())
			if rep_delta != 0:
				update_reputation(rep_delta)
				handled_any = true
			else:
				unresolved += "<" + raw_tag + ">"
		elif normalized.begins_with("犯罪"):
			handled_any = true
		elif normalized.begins_with("前往"):
			var target = normalized.trim_prefix("前往").replace(":", "").strip_edges()
			if target != "":
				nav_target = target
				handled_any = true
			else:
				unresolved += "<" + raw_tag + ">"
		else:
			unresolved += "<" + raw_tag + ">"
	if handled_any:
		player_update()
	return {"handled_any": handled_any, "unresolved_tags": unresolved, "nav_target": nav_target}

func _extract_nav_target_from_text(text: String) -> String:
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
	for site in sites.keys():
		var site_str = str(site).strip_edges()
		if site_str != "" and site_str != currentSiteName and text.find(site_str) != -1:
			return site_str
	return ""

func _auto_apply_action_effects(action_input: String, action_reply: String, tool_tags: String) -> void:
	var source = (action_input + "\n" + action_reply).strip_edges()
	if source == "":
		return
	var action_context = _build_action_context_text(action_input, action_reply)

	var has_time_tool = tool_tags.find("设置时间") != -1 or tool_tags.find("set_time") != -1
	var has_money_tool = tool_tags.find("consume_items") != -1 or tool_tags.find("initiate_transaction") != -1
	if !has_money_tool:
		for ct in _extract_angle_tags(action_reply):
			var ctn = str(ct).replace("：", ":").strip_edges()
			if (ctn.begins_with("资产") or ctn.begins_with("金币") or ctn.begins_with("金钱")) and _extract_signed_number(ctn) != 0:
				has_money_tool = true
				break
	var passed_hours = 0.0

	var changed = false
	var money_changed = false

	var money_words = ["块钱", "元", "人民币", "现金", "钱"]
	var has_money_word = false
	for mw in money_words:
		if source.find(mw) != -1:
			has_money_word = true
			break
	if !has_money_tool and has_money_word and (source.find("扔") != -1 or source.find("丢") != -1 or source.find("放在地上") != -1):
		var amount = _extract_first_number(source)
		if amount > 0:
			var real_cost = min(amount, money)
			money -= real_cost
			money_changed = true
			addLog("<你扔掉了" + str(real_cost) + "块钱，当前资产" + str(money) + ">")
			if real_cost > 0 and randf() < ACTION_PROACTIVE_NPC_RATE:
				await _spawn_context_npc("money", {}, action_context)
			changed = true

	if currentState != worldState.chat and !has_money_tool and !money_changed:
		var inferred_money_delta = _extract_money_delta_from_text(source)
		if inferred_money_delta != 0:
			var before_money = money
			money = max(0, money + inferred_money_delta)
			var real_delta = money - before_money
			if real_delta != 0:
				if real_delta < 0:
					addLog("<行动花费" + str(abs(real_delta)) + "，当前资产" + str(money) + ">")
				else:
					addLog("<行动获得" + str(real_delta) + "，当前资产" + str(money) + ">")
				changed = true

	if source.find("锻炼") != -1 or source.find("训练") != -1 or source.find("健身") != -1 or source.find("跑步") != -1:
		var hours = _extract_duration_hours(source)
		if hours <= 0.0:
			hours = 1.0
		if !has_time_tool:
			var rec_ex = advance_time_minutes(hours * 60.0)
			passed_hours += float(rec_ex.get("hours", 0.0))
		var energy_cost = hours * 10.0
		energy = max(0.0, energy - energy_cost)
		hp = min(100.0, hp + hours * 1.5)
		addLog("<锻炼" + str(hours) + "小时：体力-" + str(int(energy_cost)) + "，生命+" + str(int(hours * 1.5)) + ">")
		if randf() < ACTION_PROACTIVE_NPC_RATE:
			await _spawn_context_npc("exercise", {}, action_context)
		changed = true

	if source.find("睡") != -1 and (source.find("睡觉") != -1 or source.find("睡一觉") != -1 or source.find("入睡") != -1):
		var sleep_hours = _extract_duration_hours(source)
		if !has_time_tool:
			if sleep_hours > 0.0:
				var rec_sleep = advance_time_minutes(sleep_hours * 60.0)
				passed_hours += float(rec_sleep.get("hours", 0.0))
			else:
				var target_time = _extract_target_time(source)
				if target_time.get("valid", false):
					var current_in_day = fmod(nowtime, 1440.0)
					var target_minutes = float(int(target_time.get("hour", 8)) * 60 + int(target_time.get("minute", 0)))
					var delta = target_minutes - current_in_day
					var has_next_day_hint = source.find("明天") != -1 or source.find("次日") != -1 or source.find("第二天") != -1
					if delta <= 0.0 and !has_next_day_hint:
						delta = 90.0
					elif delta <= 0.0:
						delta += 1440.0
					var rec_sleep_target = advance_time_minutes(delta)
					passed_hours += float(rec_sleep_target.get("hours", 0.0))
				else:
					var current_hour = int(floor(fmod(nowtime, 1440.0) / 60.0))
					if current_hour >= 22 or current_hour < 5:
						var wake_hour = randi_range(6, 8)
						var wake_min = 0 if randi_range(0, 1) == 0 else 30
						passed_hours += set_time(wake_hour, wake_min)
					else:
						var default_sleep_hours = 1.5
						if source.find("午觉") != -1 or source.find("小睡") != -1 or source.find("打盹") != -1 or source.find("眯") != -1:
							default_sleep_hours = 0.5
						var rec_sleep_default = advance_time_minutes(default_sleep_hours * 60.0)
						passed_hours += float(rec_sleep_default.get("hours", 0.0))
		energy = min(100.0, energy + 40.0)
		hp = min(100.0, hp + 8.0)
		addLog("<你睡了一觉，醒来精神恢复了不少。>")
		changed = true

	if !has_time_tool and source.find("等到") != -1:
		var waiting_time = _extract_target_time(source)
		if waiting_time.get("valid", false):
			passed_hours += set_time(int(waiting_time.get("hour", 0)), int(waiting_time.get("minute", 0)))
			changed = true

	# 犯罪行为检测：响应 action_prompt 追加的 <犯罪：...> 标签
	var has_crime_tag = action_reply.find("<犯罪") != -1 or tool_tags.find("犯罪") != -1
	if !has_crime_tag:
		var crime_keywords = ["偷", "盗窃", "行窃", "防盗", "警报", "报警", "被抓", "保安"]
		for keyword in crime_keywords:
			if source.find(keyword) != -1:
				has_crime_tag = true
				break
	if has_crime_tag:
		last_crime_event_context = _build_crime_context(action_input, action_reply, tool_tags)
		var penalty = randi_range(8, 20)
		reputation = max(0.0, reputation - penalty)
		addLog("<违规行为被记录（" + last_crime_event_context + "），声誉-" + str(penalty) + ">")
		if currentState != worldState.chat:
			var crime_npc = _pick_crime_npc_from_action(action_input)
			if !crime_npc.is_empty():
				await _spawn_context_npc("crime", crime_npc, last_crime_event_context)
			else:
				await _spawn_context_npc("crime", {}, last_crime_event_context)
		changed = true

	if !has_crime_tag and currentState != worldState.chat:
		await _trigger_time_pass_npc_event(passed_hours, action_context)

	if changed:
		player_update()

# ==================== 工具函数 ====================
func extract_json_from_text(input_string: String) -> Dictionary:
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


# 初始化交易：NPC想要卖给玩家物品，is_total=true 表示price为总价而非单价
func initiate_transaction(item_name: String, quantity: int, price: int, is_total: bool = false) -> void:
	await _ensure_item_profile_record_before_trade(item_name)
	var price_label = ("总价" + str(price)) if is_total else (str(price) + "每件")
	var seller_name = "附近商贩"
	if currentNpc != null:
		seller_name = str(currentNpc.npcName)
	addLog("<" + seller_name + "想要以" + price_label + "出售" + str(item_name) + "X" + str(quantity) + ">")
	%event.got_deal_event(item_name, quantity, price, is_total)
	refresh_interaction_locks()

# 给予物品：NPC想要送给玩家物品
func got_items(item_name: String, quantity: int) -> void:
	await _ensure_item_profile_record_before_trade(item_name)
	%event.got_gift_event(item_name, quantity)
	addLog("<有人想送你" + str(item_name) + "X" + str(quantity) + ">")
	refresh_interaction_locks()
	pass

# 消耗物品：NPC接受了玩家的物品
func consume_items(item_name: String, quantity: int) -> void:
	if quantity <= 0:
		return
	var money_aliases = ["钱", "金币", "资产", "现金"]
	var is_money_action = false
	for alias in money_aliases:
		if item_name.find(alias) != -1:
			is_money_action = true
			break

	if is_money_action:
		if money < quantity:
			var fail_msg = await _generate_validation_dialogue(
				"玩家想从背包里拿出" + str(quantity) + "块钱，但当前资产只有" + str(money) + "块钱。请给一句失败反馈。",
				"你掏了掏背包，但是里面只有" + str(money) + "块钱。"
			)
			addLog("<" + fail_msg + ">")
			await changeTextTo(response_label, fail_msg)
			return
		money -= quantity
		player_update()
		addLog("<你拿出了" + str(quantity) + "块钱，剩余" + str(money) + "块钱>")
		return

	await _ensure_item_profile_record_before_trade(item_name)

	var consume_result: Dictionary = %itemContainer.consume_item(item_name, quantity)
	if !consume_result.get("success", false):
		var available = int(consume_result.get("available", 0))
		var fail_fallback = "你翻找背包，" + str(item_name) + "只剩" + str(available) + "个，不够拿出" + str(quantity) + "个。"
		var scene_context = "玩家想从背包拿出" + str(quantity) + "个" + str(item_name) + "，但只剩" + str(available) + "个。请给一句失败反馈。"
		if consume_result.get("reason", "") == "missing":
			fail_fallback = "你翻找背包，没有找到" + str(item_name) + "。"
			scene_context = "玩家想从背包拿出" + str(item_name) + "，但背包里没有该物品。请给一句失败反馈。"
		var fail_msg = await _generate_validation_dialogue(scene_context, fail_fallback)
		addLog("<" + fail_msg + ">")
		await changeTextTo(response_label, fail_msg)
		return

	addLog("<你失去了" + str(item_name) + "X" + str(quantity) + ">")
	pass

# 创建地点：NPC提到了到达某个地方的路径
func create_location(path: String) -> void:
	var raw_sites = path.split("-", false)
	var new_sites: Array = []
	for site_name in raw_sites:
		var cleaned = _resolve_site_alias(str(site_name).strip_edges())
		cleaned = _extract_compact_entity_candidate(cleaned, 16)
		if cleaned != "" and _is_valid_generated_location_name(cleaned) and !new_sites.has(cleaned):
			new_sites.append(cleaned)

	if new_sites.is_empty():
		return

	if !sites.has(currentSiteName):
		sites[currentSiteName] = {"能前往的地点": [], "npc": {}}
	elif !sites[currentSiteName].has("能前往的地点"):
		sites[currentSiteName]["能前往的地点"] = []

	var chain: Array = new_sites.duplicate()
	if chain[0] != currentSiteName:
		chain.push_front(currentSiteName)
	if chain.size() < 2:
		return

	for i in range(chain.size() - 1):
		var from_site = str(chain[i])
		var to_site = str(chain[i + 1])
		if !sites.has(from_site):
			sites[from_site] = {"能前往的地点": [], "npc": {}}
		elif !sites[from_site].has("能前往的地点"):
			sites[from_site]["能前往的地点"] = []
		if !sites[from_site]["能前往的地点"].has(to_site):
			sites[from_site]["能前往的地点"].append(to_site)
			_save_site_json(from_site, sites[from_site])

	if chain.size() == 2:
		addLog("<地图更新：发现了" + str(chain[1]) + ">")
	else:
		addLog("<地图更新：发现了前往" + str(chain[-1]) + "的路：" + path + ">")

	var next_site = str(chain[1])
	var has_button = false
	for btn in %site_buttons.get_children():
		if btn is siteButton and btn.siteName == next_site:
			has_button = true
			break
	if !has_button and next_site != currentSiteName:
		var new_site_button = load("res://fabs/site_button.tscn").instantiate() as siteButton
		new_site_button.siteName = next_site
		%site_buttons.add_child(new_site_button)
	pass

# 创建NPC：NPC说某个地方有某个NPC
func create_NPC(npc_name: String, location: String, npc_describe: String) -> void:
	npc_name = _sanitize_generated_npc_name(npc_name)
	npc_name = _extract_compact_entity_candidate(npc_name, 12)
	if !_is_valid_generated_npc_name(npc_name) and _is_relation_npc_query(last_dialogue_input):
		npc_name = _fallback_relation_npc_name(last_dialogue_input)
	npc_name = _extract_compact_entity_candidate(npc_name, 12)
	if !_is_valid_generated_npc_name(npc_name):
		return
	if npc_name == "" or dead_npc_names.has(npc_name):
		return
	var location_text = "世界某处"
	if location != "":
		location = _extract_compact_entity_candidate(location, 16)
		if !_is_valid_generated_location_name(location):
			location = currentSiteName
		location_text = location
	if !npcs.has(npc_name) or !(npcs[npc_name] is Dictionary):
		npcs[npc_name] = {"npc_describe": npc_describe, "npc_log": [], "特征": "", "important_events": []}
	else:
		if !npcs[npc_name].has("npc_describe") or str(npcs[npc_name].get("npc_describe", "")).strip_edges() == "":
			npcs[npc_name]["npc_describe"] = npc_describe
		if !npcs[npc_name].has("npc_log") or !(npcs[npc_name]["npc_log"] is Array):
			npcs[npc_name]["npc_log"] = []
		if !npcs[npc_name].has("important_events") or !(npcs[npc_name]["important_events"] is Array):
			npcs[npc_name]["important_events"] = []
	if location != "":
		if !sites.has(location) or !(sites[location] is Dictionary):
			sites[location] = {"能前往的地点": [], "npc": {}, "地点名称": location, "地点描述": "", "英文描述": ""}
		if !sites[location].has("npc") or !(sites[location]["npc"] is Dictionary):
			sites[location]["npc"] = {}
		sites[location]["npc"][npc_name] = npc_describe
		if location == currentSiteName:
			site_update()
	var heard_text = "你听说" + location_text + "有位" + str(npc_describe) + "：" + str(npc_name)
	addLog("<" + heard_text + ">")
	var source_npc = ""
	if currentNpc != null:
		source_npc = str(currentNpc.npcName)
	var memory_text = "<NPC情报>" + heard_text
	if source_npc != "":
		memory_text += "（消息来源：" + source_npc + "）"
	_remember_important_event(memory_text, location, source_npc)
	var target_log: Array = npcs[npc_name]["npc_log"]
	var target_note = "系统记录：有人在" + location_text + "提及了你的信息【" + str(npc_describe) + "】。"
	if !target_log.has(target_note):
		target_log.append(target_note)
	npcs[npc_name]["npc_log"] = target_log
	pass

func prepare_npc_memory_for_chat(npc_name: String) -> void:
	_append_event_memories_to_npc_log(npc_name)

func _has_trade_keywords(text: String) -> bool:
	var sig = _extract_interaction_signals(text)
	return int(sig.get("trade", 0)) > 0 or int(sig.get("gift", 0)) > 0

func _queue_action_confirm(action_data: Dictionary) -> void:
	if action_data.is_empty():
		return
	var action_text = str(action_data.get("action", "")).strip_edges()
	if action_text == "":
		return
	var actor = str(action_data.get("actor", "")).strip_edges()
	if actor == "":
		if currentNpc != null:
			actor = str(currentNpc.npcName)
		else:
			actor = "对方"
	pending_action_confirm = {
		"action": action_text,
		"prompt": str(action_data.get("prompt", "是否执行行动：" + action_text + "？")),
		"actor": actor,
		"mode": str(action_data.get("mode", "player_execute"))
	}
	_set_event_flow_lock(true)
	%event.got_action_confirm_event(str(pending_action_confirm.get("action", "")), str(pending_action_confirm.get("prompt", "")))

func _npc_refused_request(reply_text: String) -> bool:
	var t = process_string(reply_text).strip_edges()
	if t == "":
		return false
	var deny_words = ["不行", "不能", "不可以", "不帮", "拒绝", "没空", "做不到", "不愿", "别想", "不可能"]
	for w in deny_words:
		if t.find(w) != -1:
			return true
	return false

func _extract_player_directed_request(user_text: String) -> String:
	var plain = _normalize_single_line_input(user_text)
	if plain == "":
		return ""
	var regex = RegEx.new()
	if regex.compile("(?:你|请你|麻烦你|帮我|替我|你去)([^。！？?]{1,28})") != OK:
		return ""
	var m = regex.search(plain)
	if m == null:
		return ""
	var req = str(m.get_string(1)).strip_edges()
	if req.length() < 2:
		return ""
	return req

func _can_force_request_on_npc(npc_name: String, npc_describe: String, request_text: String) -> bool:
	var score = 0
	var player_context = world_seed_input + " " + playerName
	if _contains_any_keyword(player_context, ["老师", "保安", "警察", "军", "领导", "主任", "老板", "队长"]):
		score += 2
	if _contains_any_keyword(npc_describe + " " + npc_name, ["学生", "同学", "路人", "游客"]):
		score += 1
	if _contains_any_keyword(npc_describe + " " + npc_name, ["老师", "保安", "警察", "店长", "主任", "领导"]):
		score -= 3
	if _contains_any_keyword(request_text, ["打", "抢", "偷", "绑", "闯"]):
		score -= 2
	return score >= 1

func _append_event_memories_to_npc_log(npc_name: String) -> void:
	if !npcs.has(npc_name):
		return
	if !npcs[npc_name].has("npc_log") or !(npcs[npc_name]["npc_log"] is Array):
		npcs[npc_name]["npc_log"] = []
	if !npcs[npc_name].has("important_events") or !(npcs[npc_name]["important_events"] is Array):
		npcs[npc_name]["important_events"] = []
	var arr: Array = npcs[npc_name]["npc_log"]
	var npc_events: Array = npcs[npc_name]["important_events"]
	if !npc_events.is_empty():
		var start_idx = max(0, npc_events.size() - 4)
		for i in range(start_idx, npc_events.size()):
			var event_row = npc_events[i]
			if !(event_row is Dictionary):
				continue
			var view_text = str(event_row.get("npc_view", "")).strip_edges()
			if view_text == "":
				continue
			var note = "重要事件：" + view_text
			if !arr.has(note):
				arr.append(note)
		npcs[npc_name]["npc_log"] = arr
		return
	var mems = _get_recent_related_event_memories(currentSiteName, npc_name, 3)
	if mems.is_empty():
		return
	for m in mems:
		if !(m is Dictionary):
			continue
		var note = "重要事件：" + str(m.get("text", ""))
		if !arr.has(note):
			arr.append(note)
	npcs[npc_name]["npc_log"] = arr

func _contains_any_keyword(text: String, words: Array) -> bool:
	for w in words:
		if text.find(str(w)) != -1:
			return true
	return false

func _extract_interaction_signals(text: String) -> Dictionary:
	var t = str(text).strip_edges()
	if t == "":
		return {"trade": 0, "gift": 0, "assist": 0, "positive": 0, "negative": 0, "coercion": 0, "respect": 0, "interaction_score": 0}
	var trade_keywords = [
		"买", "购买", "卖", "出售", "交易", "成交", "收购", "收你", "报价", "价格", "多少钱", "单价", "总价", "换"
	]
	var gift_keywords = [
		"送", "赠", "给你", "给我", "递给", "交给", "拿给", "分你", "分享", "补给"
	]
	var assist_keywords = [
		"帮", "帮我", "帮你", "替", "替我", "替你", "代", "代我", "代你", "陪", "带我", "去帮"
	]
	var positive_keywords = [
		"感谢", "谢谢", "帮忙", "照顾", "安慰", "道歉", "体谅", "关心", "保护", "救", "信任", "友好", "客气"
	]
	var negative_keywords = [
		"拒绝", "敌意", "冲突", "冒犯", "羞辱", "欺骗", "冷淡", "厌恶", "怀疑", "不耐烦", "辱骂", "看不起"
	]
	var coercion_keywords = [
		"威胁", "命令", "逼", "强迫", "施压", "滚", "跪下", "闭嘴", "老实点", "给我", "立刻", "马上"
	]
	var respect_keywords = [
		"尊重", "敬畏", "请", "拜托", "劳烦", "失礼", "抱歉", "请教", "愿意听你", "照你规矩"
	]
	var trade_score = 0
	var gift_score = 0
	var assist_score = 0
	var positive_score = 0
	var negative_score = 0
	var coercion_score = 0
	var respect_score = 0
	for kw in trade_keywords:
		if t.find(kw) != -1:
			trade_score += 1
	for kw in gift_keywords:
		if t.find(kw) != -1:
			gift_score += 1
	for kw in assist_keywords:
		if t.find(kw) != -1:
			assist_score += 1
	for kw in positive_keywords:
		if t.find(kw) != -1:
			positive_score += 1
	for kw in negative_keywords:
		if t.find(kw) != -1:
			negative_score += 1
	for kw in coercion_keywords:
		if t.find(kw) != -1:
			coercion_score += 1
	for kw in respect_keywords:
		if t.find(kw) != -1:
			respect_score += 1
	if _contains_any_keyword(t, ["个", "件", "瓶", "把", "份", "张", "点", "块", "元"]):
		trade_score += 1
		gift_score += 1
	if _extract_first_number(t) > 0:
		trade_score += 1
		gift_score += 1
	if t.find("请") != -1 and t.find("帮") != -1:
		respect_score += 1
		positive_score += 1
	if _contains_any_keyword(t, ["不许", "否则", "后果", "弄死", "收拾你"]):
		coercion_score += 2
		negative_score += 1
	return {
		"trade": trade_score,
		"gift": gift_score,
		"assist": assist_score,
		"positive": positive_score,
		"negative": negative_score,
		"coercion": coercion_score,
		"respect": respect_score,
		"interaction_score": trade_score + gift_score + assist_score + positive_score + negative_score + coercion_score + respect_score
	}

func _needs_tool_inference_from_context(player_text: String, npc_text: String) -> bool:
	var player_sig = _extract_interaction_signals(player_text)
	var npc_sig = _extract_interaction_signals(npc_text)
	var total_score = int(player_sig.get("interaction_score", 0)) + int(npc_sig.get("interaction_score", 0))
	if total_score >= 2:
		return true
	if _has_trade_keywords(npc_text):
		return true
	if _contains_any_keyword(player_text, ["买", "卖", "给", "送", "帮", "替"]) and _npc_reply_accepts_request(npc_text):
		return true
	return false

func _npc_reply_accepts_request(reply_text: String) -> bool:
	var t = process_string(reply_text).strip_edges()
	if t == "":
		return false
	var yes_words = ["可以", "行", "好", "没问题", "当然", "马上", "这就", "给你", "帮你", "替你", "成交", "安排"]
	for w in yes_words:
		if t.find(w) != -1:
			return true
	return false

func _maybe_offer_intent_confirm_from_dialogue(reply_text: String) -> void:
	if _has_active_event_panel():
		return
	if _npc_reply_accepts_request(reply_text):
		var inferred_req = _extract_npc_action_request(reply_text)
		if !inferred_req.is_empty():
			_queue_action_confirm(inferred_req)
			return
	if !_npc_refused_request(reply_text):
		return
	var user_req = _extract_player_directed_request(last_dialogue_input)
	if user_req == "":
		return
	var npc_name = "对方"
	var npc_desc = ""
	if currentNpc != null:
		npc_name = str(currentNpc.npcName)
		npc_desc = str(currentNpc.npcDescribe)
	if !_can_force_request_on_npc(npc_name, npc_desc, user_req):
		return
	_queue_action_confirm({
		"action": "强行要求" + npc_name + user_req,
		"prompt": npc_name + "拒绝了你的要求。是否强硬执行：让TA" + user_req + "？",
		"actor": npc_name,
		"mode": "force_execute"
	})

func _extract_npc_action_request(reply_text: String) -> Dictionary:
	var actor_name = ""
	if currentNpc != null:
		actor_name = str(currentNpc.npcName)
	var tags = _extract_angle_tags(reply_text)
	for raw_tag in tags:
		var normalized = str(raw_tag).replace("：", ":").strip_edges()
		if normalized.begins_with("要求行动:"):
			var action_from_tag = normalized.trim_prefix("要求行动:").strip_edges()
			if action_from_tag != "":
				return {"action": action_from_tag, "prompt": "是否执行行动：" + action_from_tag + "？", "actor": actor_name, "mode": "player_execute"}
		if normalized.begins_with("行动指示:"):
			var action_from_hint = normalized.trim_prefix("行动指示:").strip_edges()
			if action_from_hint != "":
				return {"action": action_from_hint, "prompt": "是否执行行动：" + action_from_hint + "？", "actor": actor_name, "mode": "player_execute"}

	if _has_trade_keywords(reply_text):
		return {}
	var plain = process_string(reply_text).strip_edges()
	if plain == "":
		return {}
	var regex = RegEx.new()
	if regex.compile("(?:你要不要|你要|要不要|是否|请你|麻烦你)([^。！？?]{1,24})(?:吗|么|吧|呢|？|\\?)") != OK:
		return {}
	var m = regex.search(plain)
	if m == null:
		return {}
	var action_text = str(m.get_string(1)).strip_edges()
	if action_text.length() < 2:
		return {}
	var prompt_text = "是否" + action_text + "？"
	var q_idx = plain.find("？")
	if q_idx == -1:
		q_idx = plain.find("?")
	if q_idx != -1:
		var question = plain.substr(0, q_idx + 1).strip_edges()
		if question.length() <= 36:
			prompt_text = question
	return {"action": action_text, "prompt": prompt_text, "actor": actor_name, "mode": "player_execute"}

func _auto_handle_action_search(action_input: String, action_reply: String) -> void:
	var input_text = action_input.strip_edges()
	if input_text == "":
		return
	if !(input_text.find("寻找") != -1 or input_text.find("找") != -1):
		return
	var fail_tokens = ["没找到", "没有找到", "未找到", "找不到", "这里没有", "不存在", "并没有", "没有这样", "没有对应", "无法找到"]
	for t in fail_tokens:
		if action_reply.find(t) != -1:
			return
	var target = input_text
	if target.find("寻找") != -1:
		target = target.substr(target.find("寻找") + 2)
	elif target.find("找") != -1:
		target = target.substr(target.find("找") + 1)
	target = target.replace("。", "").replace("，", "").replace("!", "").replace("？", "").strip_edges()
	target = _sanitize_generated_npc_name(target)
	target = _extract_compact_entity_candidate(target, 16)
	if target != "" and action_reply.find("没有" + target) != -1:
		return

	if target == "":
		return
	if !_is_valid_generated_npc_name(target):
		var maybe_loc = _is_valid_generated_location_name(target)
		if !maybe_loc and _is_relation_npc_query(action_input):
			target = _fallback_relation_npc_name(action_input)
			target = _extract_compact_entity_candidate(target, 12)
	if !_is_valid_generated_npc_name(target) and !_is_valid_generated_location_name(target):
		return
	if !_is_valid_generated_npc_name(target) and _is_relation_npc_query(action_input):
		target = _fallback_relation_npc_name(action_input)
	if target == "" or dead_npc_names.has(target):
		return

	var location_hints = ["楼", "馆", "店", "部", "室", "场", "食堂", "宿舍", "图书馆", "超市", "办公室", "校门"]
	var is_location = false
	for hint in location_hints:
		if target.find(hint) != -1:
			is_location = true
			break

	if is_location:
		if !_is_valid_generated_location_name(target):
			return
		create_location(currentSiteName + "-" + target)
	else:
		if !_is_valid_generated_npc_name(target):
			return
		var npc_desc = "正在此地活动"
		if _is_relation_npc_query(action_input):
			npc_desc = _guess_related_npc_desc(action_input, str(currentNpc.npcName) if currentNpc != null else "")
		create_NPC(target, currentSiteName, npc_desc)

# 创建传闻：NPC提及了某个传闻、新闻或谣言
func create_rumors(rumor_name: String, content: String) -> void:
	rumors[rumor_name] = content
	addLog("<传闻：" + str(rumor_name) + " - " + str(content) + ">")
	pass

func update_reputation(quantity:int)->void:
	var delta = clamp(quantity, -100, 100)
	if delta == 0:
		return
	reputation = clamp(reputation + float(delta), 0.0, 100.0)
	player_update()
	if delta > 0:
		addLog("<声望增加了：" + str(delta) + ">")
	else:
		addLog("<声望减少了：" + str(abs(delta)) + ">")

func set_time(hour: int, minute: int) -> float:
	var target = float(hour * 60 + minute)
	var current_in_day = fmod(nowtime, 1440.0)
	var delta = target - current_in_day
	if delta <= 0.0:
		delta += 1440.0
	var rec = advance_time_minutes(delta)
	addLog("<时间跳跃至 %02d:%02d>" % [hour, minute])
	return float(rec.get("hours", 0.0))

# 自我销毁：NPC说想要永远离开或自己要死了
func destroy_yourself(npc_name_hint: String = "") -> void:
	var npc_name = str(npc_name_hint).strip_edges()
	if npc_name == "":
		if currentNpc == null:
			return
		npc_name = str(currentNpc.npcName)
	if !dead_npc_names.has(npc_name):
		dead_npc_names.append(npc_name)
	if npcs.has(npc_name):
		npcs.erase(npc_name)
	for site_key in sites.keys():
		if !(sites[site_key] is Dictionary):
			continue
		if !sites[site_key].has("npc") or !(sites[site_key]["npc"] is Dictionary):
			continue
		sites[site_key]["npc"].erase(npc_name)
		_save_site_json(str(site_key), sites[site_key])
	addLog("<" + npc_name + "离开了，也许再也见不到了...>")
	for i:npcButton in %npc_buttons.get_children():
		if i.npcName == npc_name:
			i.queue_free()
	if currentNpc != null and str(currentNpc.npcName) == npc_name:
		await changeStateInto(GameManager.worldState.explore)

# 处理从AI接收的JSON指令
func handle_npc_instruction(tool_calls: Array) -> void:
	var normalized_calls: Array = []
	for tool_call in tool_calls:
		print("接受到一个函数调用: ", tool_call)
		var function_data = tool_call.get("function", {})
		if function_data == {} and tool_call.has("name"):
			function_data = tool_call
		var method = str(function_data.get("name", "")).strip_edges()
		if method == "":
			continue
		var arguments_data = function_data.get("arguments", "{}")

		var parameters = {}
		if arguments_data is Dictionary:
			parameters = arguments_data
		elif arguments_data is String:
			var json = JSON.new()
			var error = json.parse(arguments_data)
			if error == OK:
				parameters = json.data
			else:
				print("解析参数失败: ", arguments_data)
				continue
		else:
			print("解析参数失败: ", arguments_data)
			continue

		if parameters is Dictionary and parameters.has("quantity") and method in ["initiate_transaction", "got_items", "consume_items"]:
			parameters["quantity"] = max(1, int(parameters.get("quantity", 1)))

		if !normalized_calls.is_empty():
			var prev = normalized_calls[normalized_calls.size() - 1]
			var prev_method = str(prev.get("method", ""))
			var prev_params: Dictionary = prev.get("parameters", {})
			if method in ["initiate_transaction", "got_items", "consume_items"] and prev_method == method:
				var item_name = str(parameters.get("item_name", ""))
				var prev_item_name = str(prev_params.get("item_name", ""))
				var can_merge = item_name != "" and item_name == prev_item_name
				if can_merge and method == "initiate_transaction":
					can_merge = int(parameters.get("price", 0)) == int(prev_params.get("price", 0)) \
						and bool(parameters.get("is_total_price", false)) == bool(prev_params.get("is_total_price", false))
				if can_merge:
					prev_params["quantity"] = int(prev_params.get("quantity", 1)) + int(parameters.get("quantity", 1))
					normalized_calls[normalized_calls.size() - 1]["parameters"] = prev_params
					continue

		normalized_calls.append({"method": method, "parameters": parameters})

	# 归还错误物品并换取正确物品的场景检测：consume_items(A) + initiate_transaction(B, A≠B) → got_items(B)
	for i in range(normalized_calls.size() - 1):
		if normalized_calls[i].get("method", "") == "consume_items" and normalized_calls[i+1].get("method", "") == "initiate_transaction":
			var a_item = str(normalized_calls[i].get("parameters", {}).get("item_name", ""))
			var b_params: Dictionary = normalized_calls[i+1].get("parameters", {})
			var b_item = str(b_params.get("item_name", ""))
			if a_item != "" and b_item != "" and a_item != b_item:
				normalized_calls[i+1]["method"] = "got_items"
				normalized_calls[i+1]["parameters"] = {"item_name": b_item, "quantity": int(b_params.get("quantity", 1))}

	for tool_call_item in normalized_calls:
		var method = str(tool_call_item.get("method", ""))
		var parameters: Dictionary = tool_call_item.get("parameters", {})
		match method:
			"initiate_transaction":
				await initiate_transaction(
					parameters.get("item_name", ""),
					max(1, int(parameters.get("quantity", 1))),
					int(parameters.get("price", 0)),
					bool(parameters.get("is_total_price", false))
				)
			"got_items":
				await got_items(
					parameters.get("item_name", ""),
					max(1, int(parameters.get("quantity", 1)))
				)
			"consume_items":
				await consume_items(
					parameters.get("item_name", ""),
					max(1, int(parameters.get("quantity", 1)))
				)
			"create_location":
				create_location(parameters.get("path", ""))
			"create_NPC":
				create_NPC(
					parameters.get("npc_name", ""),
					parameters.get("location", ""),
					parameters.get("npc_describe", "")
				)
			"create_rumors":
				create_rumors(
					parameters.get("rumor_name", ""),
					parameters.get("content", "")
				)
			"update_reputation":
				update_reputation(parameters.get("quantity", 0))
			"set_time":
				set_time(int(parameters.get("hour", 0)), int(parameters.get("minute", 0)))
			"destroy_self":
				var leave_target = ""
				if currentNpc != null:
					leave_target = str(currentNpc.npcName)
				_request_npc_leave_confirm(leave_target)
			_:
				print("未知方法: ", method)
				addLog("<调试：未知工具调用 " + method + ">")
		await get_tree().create_timer(0.4).timeout
func add_item(itemToAdd, itemNum):
	if !itemProfiles.has(itemToAdd):
		var disk_profile = _load_item_profile_json(itemToAdd)
		itemProfiles[itemToAdd] = {
			"description": disk_profile.get("description", "正在生成物品介绍..."),
			"image_prompt": disk_profile.get("image_prompt", "single game inventory item icon of " + str(itemToAdd) + ", clean background, centered"),
			"value": int(disk_profile.get("value", 50)),
			"rarity": str(disk_profile.get("rarity", "common")),
			"effect_type": str(disk_profile.get("effect_type", "none")),
			"effect_value": int(disk_profile.get("effect_value", 0)),
			"texture": null,
			"is_generating": false,
			"is_ready": false
		}
	%itemContainer.add_item(
		itemToAdd,
		itemNum,
		itemProfiles[itemToAdd].get("texture", null),
		itemProfiles[itemToAdd].get("description", "正在生成物品介绍..."),
		itemProfiles[itemToAdd].get("effect_type", "none"),
		int(itemProfiles[itemToAdd].get("effect_value", 0))
	)
	ensure_item_profile_async(itemToAdd)

func use_item(item_name: String) -> Dictionary:
	if !itemProfiles.has(item_name):
		return {"ok": false, "message": "你不知道这个物品的用途。"}
	var consume_result: Dictionary = %itemContainer.consume_item(item_name, 1)
	if !consume_result.get("success", false):
		return {"ok": false, "message": "背包里没有可用的" + str(item_name) + "。"}
	var profile: Dictionary = itemProfiles.get(item_name, {})
	var effect_type = str(profile.get("effect_type", "none"))
	var effect_value = int(profile.get("effect_value", 0))
	var msg = "你使用了" + str(item_name) + "。"
	match effect_type:
		"energy_restore":
			energy = clamp(energy + effect_value, 0.0, 100.0)
			msg = "你使用了" + str(item_name) + "，体力+" + str(effect_value)
		"hp_restore":
			hp = clamp(hp + effect_value, 0.0, 100.0)
			msg = "你使用了" + str(item_name) + "，健康+" + str(effect_value)
		"both_restore":
			energy = clamp(energy + effect_value, 0.0, 100.0)
			hp = clamp(hp + int(round(effect_value * 0.6)), 0.0, 100.0)
			msg = "你使用了" + str(item_name) + "，体力与健康都恢复了一些"
		_:
			msg = "你使用了" + str(item_name) + "，似乎没有明显效果。"
	player_update()
	addLog("<" + msg + ">")
	return {"ok": true, "message": msg}

# ==================== 存读档 ====================
func save_game() -> void:
	for profile_key in itemProfiles.keys():
		var item_name = str(profile_key)
		var prof = itemProfiles.get(item_name, {})
		if prof is Dictionary and item_name != "":
			var packed_profile = _sanitize_item_profile(item_name, {
				"description": prof.get("description", ""),
				"image_prompt": prof.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered"),
				"value": int(prof.get("value", 50)),
				"rarity": str(prof.get("rarity", "common")),
				"effect_type": str(prof.get("effect_type", "none")),
				"effect_value": int(prof.get("effect_value", 0))
			})
			_save_item_profile_json(item_name, packed_profile)
	_sync_session_resources_to_save()
	_ensure_dir(SAVE_SLOT_DIR)
	var item_list: Array = []
	for child in %itemContainer.get_children():
		if child is item:
			var prof = itemProfiles.get(child.item_name, {})
			item_list.append({
				"name": child.item_name,
				"num": child.item_num,
				"description": child.item_description,
				"value": prof.get("value", 50),
				"rarity": prof.get("rarity", "common"),
				"effect_type": prof.get("effect_type", "none"),
				"effect_value": int(prof.get("effect_value", 0))
			})

	var log_list: Array = []
	for log_node in %logContainer.get_children():
		var log_text = str(log_node.text)
		if _is_important_log(log_text):
			log_list.append(log_text)
	if log_list.size() > 200:
		log_list = log_list.slice(max(0, log_list.size() - 200), log_list.size())

	var save_data = {
		"version": 1,
		"world_seed_input": world_seed_input,
		"background": background,
		"current_site": currentSiteName,
		"sites": sites,
		"npcs": npcs,
		"rumors": rumors,
		"player": {
			"name": playerName,
			"money": money,
			"energy": energy,
			"hp": hp,
			"reputation": reputation
		},
		"nowtime": nowtime,
		"env_dic": envDic,
		"items": item_list,
		"logs": log_list,
		"important_event_memories": important_event_memories,
		"current_chat_session_npc": current_chat_session_npc,
		"current_chat_session_records": current_chat_session_records,
		"dead_npc_names": dead_npc_names,
		"dialogue_min_chars": dialogue_min_chars,
		"action_narration_min_chars": action_narration_min_chars
	}

	var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		has_saved_in_session = true
		addLog("<游戏已保存>")
	else:
		addLog("<保存失败：" + str(FileAccess.get_open_error()) + ">")

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_FILE)

func load_game() -> bool:
	if !has_save_file():
		addLog("<没有存档文件>")
		return false
	_force_exit_chat_runtime()
	_restore_session_resources_from_save()
	var file = FileAccess.open(SAVE_FILE, FileAccess.READ)
	if !file:
		addLog("<读档失败>")
		return false
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		addLog("<存档文件损坏>")
		return false
	file.close()
	var data = json.get_data()

	world_seed_input = data.get("world_seed_input", "")
	background      = data.get("background", "")
	sites           = data.get("sites", {})
	npcs            = data.get("npcs", {})
	rumors          = data.get("rumors", {})
	important_event_memories = data.get("important_event_memories", [])
	current_chat_session_npc = str(data.get("current_chat_session_npc", "")).strip_edges()
	current_chat_session_records = []
	var loaded_session_records = data.get("current_chat_session_records", [])
	if loaded_session_records is Array:
		for row in loaded_session_records:
			var rec = str(row).strip_edges()
			if rec != "":
				current_chat_session_records.append(rec)
	if current_chat_session_records.size() > chat_session_record_limit:
		current_chat_session_records = current_chat_session_records.slice(current_chat_session_records.size() - chat_session_record_limit, current_chat_session_records.size())
	if current_chat_session_npc == "" or !npcs.has(current_chat_session_npc):
		current_chat_session_npc = ""
		current_chat_session_records = []
	dead_npc_names = data.get("dead_npc_names", [])
	dialogue_min_chars = clamp(int(data.get("dialogue_min_chars", data.get("efficient_mode_min_chars", 90))), 40, 2000)
	action_narration_min_chars = clamp(int(data.get("action_narration_min_chars", 90)), 40, 2000)

	var p = data.get("player", {})
	playerName  = p.get("name", playerName)
	money       = p.get("money", 1000)
	energy      = p.get("energy", 100.0)
	hp          = p.get("hp", 100.0)
	reputation  = p.get("reputation", 100.0)
	player_update()

	nowtime = data.get("nowtime", 500.0)

	envDic = data.get("env_dic", {})
	if !envDic.is_empty():
		%envContainer.load_weather_config_from_json(envDic)

	# 恢复物品
	clear_children(%itemContainer)
	itemProfiles.clear()
	for item_data in data.get("items", []):
		var iname = item_data.get("name", "")
		var inum  = item_data.get("num", 1)
		var idesc = item_data.get("description", "")
		var ivalue = int(item_data.get("value", 50))
		var irarity = str(item_data.get("rarity", "common"))
		var ieffect_type = str(item_data.get("effect_type", "none"))
		var ieffect_value = int(item_data.get("effect_value", 0))
		if iname == "":
			continue
		var disk_profile = _load_item_profile_json(iname)
		var iimage_prompt = str(disk_profile.get("image_prompt", "single game inventory item icon of " + iname + ", clean background, centered"))
		var tex = _load_image_png(ITEM_IMG_DIR, iname)
		itemProfiles[iname] = {
			"description": idesc,
			"image_prompt": iimage_prompt,
			"value": ivalue,
			"rarity": irarity,
			"effect_type": ieffect_type,
			"effect_value": ieffect_value,
			"texture": tex,
			"is_generating": false,
			"is_ready": tex != null
		}
		_save_item_profile_json(iname, _sanitize_item_profile(iname, {
			"description": idesc,
			"value": ivalue,
			"rarity": irarity,
			"effect_type": ieffect_type,
			"effect_value": ieffect_value,
			"image_prompt": iimage_prompt
		}))
		%itemContainer.add_item(iname, inum, tex, idesc, ieffect_type, ieffect_value)
		if tex == null:
			ensure_item_profile_async(iname)

	# 恢复日志
	clear_children(%logContainer)
	for log_text in data.get("logs", []):
		addLog(str(log_text), true)

	# 恢复当前场景
	var site_name = str(data.get("current_site", "")).strip_edges()
	if (site_name == "" or !sites.has(site_name)) and !sites.is_empty():
		site_name = str(sites.keys()[0])
	if site_name != "" and sites.has(site_name):
		currentSiteName = site_name
		changeTextTo(%speakerNameLabel, playerName)
		_set_event_flow_lock(false)
		var has_bg := false
		var cached = _load_image_png(SCENE_IMG_DIR, site_name)
		if cached != null:
			%backgroundImg.texture = cached
			siteImgs[site_name] = cached
			has_bg = true
			_bg_debug("load_game image cache hit for " + site_name)
		if !has_bg:
			var site_data = _get_site_data(site_name)
			var scene_prompt = _build_scene_image_prompt(site_name, site_data)
			_bg_debug("load_game image cache miss for " + site_name + ", prompt_len=" + str(scene_prompt.length()))
			if scene_prompt != "":
				site_update(false, true, false)
				pending_site_update = false
				_set_site_loading_lock(false)
				gen_img(scene_prompt, site_name)
			else:
				pending_site_update = false
				_set_site_loading_lock(false)
				site_update(false, true, false)
		else:
			pending_site_update = false
			site_update(false, true, false)
	else:
		_set_site_loading_lock(false)
		clear_children(%site_buttons)
		clear_children(%npc_buttons)
		changeTextTo(%siteName, "未定位")

	has_saved_in_session = false
	addLog("<读档完成>")
	return true
