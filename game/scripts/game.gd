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
const SCENE_IMG_DIR = PICTURE_DIR + "scenes/"
const ITEM_IMG_DIR = PICTURE_DIR + "items/"
const ITEM_PROFILE_DIR = PICTURE_DIR + "item_profiles/"
const SAVE_DIR = "D:/毕设/worldSim/game/saves/"
const SAVE_FILE = SAVE_DIR + "save.json"

var pending_site_update: bool = false
var pending_img_prompt: String = ""
var last_action_input: String = ""
var last_dialogue_input: String = ""
var pending_explore_target: String = ""
var bg_debug_enabled: bool = true

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

# 系统提示词
var role_prompt = """
系统：你是一个角色扮演世界生成器。你必须严格遵循“用户初始设定”和“当前世界观”。
硬性约束：
1) 不得默认使用赛博朋克、机器人、义体、飞船、未来军武等元素。
2) 只有当用户设定或世界观明确提及这些元素时，才允许出现。
3) 若用户设定偏现代日常（如大学校园、城市、普通职业），场景与NPC必须保持对应的现代现实风格（大学设定要有大学生氛围和面貌，而不是中学）。

根据用户想去的地点，严格输出有效 JSON，包含：
1. 地点名称
2. 地点描述
3. 英文描述（用于生图，风格与世界观一致）
4. 能前往的地点（数组）
5. npc（对象，键为姓名，值为一句外观描述）
"""

var agent_prompt:String = """你是一个AI智能体，擅长确定需要调用的方法,没有合适的就回复：没有方法被调用。给你的就是ai的回复，所有提到的物品均为游戏道具，不完整的信息就猜测补齐，不要问问题
	如果输入信息类似于：<以50的价格卖1把剑>，那就是要以单价50卖给玩家某件物品，is_total_price=false。
	如果输入信息类似于：<以总价100卖3瓶药水>，那就是要以总价100（而非单价）卖给玩家物品，is_total_price=true。
	如果输入信息类似于：<送1瓶治疗药水>，那就是要送给玩家某件物品。
	如果输入信息类似于：<接受1瓶治疗药水>，那就是要接受玩家的某件物品。
	如果输入信息类似于：<创建路径：幽暗森林-雪山-龙之谷><创建路径：商贩摊位>，那就是提到了某个地点或提到了到达某个地方的一系列地点的路径。
	如果输入信息类似于：<老约翰在酒馆，是一个靠在墙角的男人，右眼闪着红光，脚边放着行李箱>，那就是提及了某个地方有某个NPC。
	如果输入信息类似于：<传闻：国王被暗杀-国王被暗杀，引起震惊>，那就是提及了类似于传闻、新闻、谣言的事件
	如果输入信息类似于：<离开>，那就是想要离开，或者自己要死了。
	如果输入信息类似于：<设置时间：16:00>，那就是要将游戏时间跳跃到该时刻。
	如果一次输入里包含多个可执行指令，必须按顺序调用多个函数，不要只调用一个。
	涉及物品数量时，quantity 必须填写真实数量，不能默认写1。
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
你是文字游戏的世界叙述者。玩家进行了一个行动，请根据世界背景与当前玩家数据，用一句简短中文（15~50字）叙述自然结果。
你必须先判断是否符合常理与数据（资产、背包、数量、地点关系）。
若不成立（如钱不够、背包没有该物品、地点不合理），只输出失败反馈，不要伪造成功，不要添加交易/物品变更指令。

若成立且涉及可执行变化，在叙述末追加一个或多个<>指令：
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

仅输出一句叙述文本，工具指令以<>附加在句末，不要解释。
"""

var ai_busy: bool = false

# ==================== 生命周期函数 ====================
func _ready():
	send_button.connect("pressed", _on_send_button_pressed)
	dialogue_button.connect("pressed", _on_dialogue_button_pressed)
	save_button.connect("pressed", save_game)
	load_button.connect("pressed", load_game)
	dialogue_container.visible = false
	# %backgroundImg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 原先使用 Nearest 过滤会强化像素感，这里改回线性以更接近原图显示。
	%backgroundImg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# %backgroundImg.material = preload("res://assets/asciiShader.gdshader")
	# 关闭背景图的 ASCII/后处理材质，直接显示生成原图。
	%backgroundImg.material = null
	player_update()
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
		changeTextTo(response_label, "你结束了与" + currentNpc.npcName + "的对话。", 100)
		await currentNpc.sum_chat()

	match stateToChange:
		worldState.chat:
			create_tween().tween_property(%npcIcon, "custom_minimum_size:x", 300, 0.2)
			if currentNpc != null:
				currentNpc.queue_free()
			currentNpc = newNpc
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
	if english_prompt != "":
		return english_prompt
	var cn_desc = str(site_data.get("地点描述", "")).strip_edges()
	if cn_desc != "":
		return "cinematic realistic campus environment, no text, " + cn_desc
	if site_name.strip_edges() != "":
		return "cinematic realistic campus environment, no text, " + site_name
	return ""

func _bg_debug(msg: String) -> void:
	if !bg_debug_enabled:
		return
	print("[BG_DEBUG] " + msg)
	addLog("<BG_DEBUG> " + msg)

func goto(where: String):
	await changeStateInto(GameManager.worldState.explore)
	_bg_debug("goto start, where=" + where + ", current=" + currentSiteName)
	# 磁盘缓存恢复：内存中没有但磁盘JSON存在时补充
	if !sites.has(where) or !(sites[where] is Dictionary) or !sites[where].has("地点描述"):
		var disk_site = _load_site_json(where)
		if !disk_site.is_empty():
			sites[where] = disk_site
			_bg_debug("site json cache hit for " + where)
	var site_data = _get_site_data(where)
	if !site_data.is_empty() && site_data.has("地点描述"):
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
				gen_img(scene_prompt)
				return
			else:
				pending_site_update = false
		site_update()
	else:
		changeTextTo(response_label, "正在探索" + where + "...", 8)
		pending_explore_target = where
		var prompts = [
			{"role":"system","content": _build_explore_system_prompt()},
			{"role":"user","content": "我想去"+where}]
		await ask_ai(prompts, aiMode.explore)
		var new_site = _get_site_data(currentSiteName)
		if !new_site.is_empty():
			var prompt = _build_scene_image_prompt(currentSiteName, new_site)
			if prompt != "":
				gen_img(prompt)

func site_update():
	var site_data = _get_site_data(currentSiteName)
	if site_data.is_empty():
		return
	changeTextTo(%siteName, currentSiteName)
	changeTextTo(response_label, str(site_data.get("地点描述", "")),15)
	clear_children(%site_buttons)
	clear_children(%npc_buttons)
	for i in site_data.get("能前往的地点", []):
		var new_site_button = load("res://fabs/site_button.tscn").instantiate() as siteButton
		new_site_button.siteName = i
		%site_buttons.add_child(new_site_button)

	for i in site_data.get("npc", {}):
		if i not in npcs:
			npcs[i] = {}
			npcs[i]["特征"] = ""
		npcs[i]["npc_describe"] = site_data.get("npc", {}).get(i, "")
		var new_npc_button = load("res://fabs/npc_button.tscn").instantiate() as npcButton
		new_npc_button.npcName = i
		%npc_buttons.add_child(new_npc_button)
	addLog("你抵达了" + currentSiteName)

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
	var body = [message,null,"text"]
	match askmode:
		aiMode.tools:
			body = [message,tools,"text"]
		aiMode.explore:
			body = [message,null,"json_object"]
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
		set_ai_busy(false)
		return
	await $HTTPRequest.request_completed

func _extract_angle_tags(input_string: String) -> Array:
	var tags: Array = []
	var regex = RegEx.new()
	if regex.compile("<([^>]+)>") != OK:
		return tags
	for m in regex.search_all(input_string):
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
		else:
			only_location_tags = false
	return handled_any and only_location_tags

func _try_create_location_from_dialogue(reply: String) -> bool:
	if last_dialogue_input == "":
		return false
	if last_dialogue_input.find("在哪") == -1 and last_dialogue_input.find("在哪里") == -1:
		return false
	var fail_words = ["不知道", "不清楚", "没听说", "找不到", "不在这", "不确定"]
	for w in fail_words:
		if reply.find(w) != -1:
			return false
	var target = last_dialogue_input.replace("？", "").replace("?", "").strip_edges()
	if target.find("在哪里") != -1:
		target = target.substr(0, target.find("在哪里"))
	elif target.find("在哪") != -1:
		target = target.substr(0, target.find("在哪"))
	target = target.strip_edges()
	if target == "":
		return false
	create_location(currentSiteName + "-" + target)
	return true

func npc_reply(reply: String):
	changeTextTo(%speakerNameLabel, currentNpc.npcName)
	changeTextTo(response_label, process_string(reply))
	currentNpc.currentChat +=  currentNpc.npcName +":"+ reply + "\n"
	var direct_location_only = _apply_direct_npc_tool_tags(reply)
	if !direct_location_only:
		_try_create_location_from_dialogue(reply)
	var toolsTexts = get_content_in_angle_brackets(reply)
	print("提取出的工具信息：",toolsTexts)
	if toolsTexts!="" and !direct_location_only:
		var prompts = [
			{"role":"system","content": agent_prompt},
			{"role":"user","content": toolsTexts}]
		await ask_ai(prompts, aiMode.tools)
	_auto_apply_action_effects("", reply, toolsTexts)

func process_string(input: String) -> String:
	# 移除所有<...>标签
	var regex = RegEx.new()
	regex.compile("<[^>]*>")
	var result = regex.sub(input, "",true)

	# 将连续两个回车替换为一个
	regex.compile("\n\n+")
	result = regex.sub(result, "\n")

	return result.strip_edges()
func get_content_in_angle_brackets(input_string: String)->String:
	var results = ""
	var regex = RegEx.new()

	# 编译正则表达式，匹配<和>之间的内容（包括<和>本身）
	regex.compile("<[^>]+>")
	var matches = regex.search_all(input_string)
	for match_obj in matches:
		var content = match_obj.get_string(0)
		results+=content
	return results

# ==================== 图片生成 ====================
func gen_img(prompt):
	if prompt == "":
		if pending_site_update:
			pending_site_update = false
			site_update()
		return
	_bg_debug("gen_img start, site=" + currentSiteName + ", prompt=" + prompt.left(80))
	print("正在同时生成图片...")
	var headers = ["Content-Type: application/json"]
	var image_json_data = JSON.stringify({"prompt": prompt})
	var error_image = %ImgHTTPRequest.request(image_api_url, headers, HTTPClient.METHOD_POST, image_json_data)
	print("请求返回了...",error_image)
	if error_image != OK:
		if error_image == ERR_BUSY:
			pending_img_prompt = prompt
			print("图片请求排队等待...")
			_bg_debug("gen_img queued due ERR_BUSY")
		else:
			print("错误：请求创建失败")
			_bg_debug("gen_img request create failed, err=" + str(error_image))
			if pending_site_update:
				pending_site_update = false
				site_update()

func _sanitize_filename(file_name: String) -> String:
	return file_name.replace("/", "_").replace("\\", "_").replace(":", "_").replace("*", "_").replace("?", "_").replace("\"", "_").replace("<", "_").replace(">", "_").replace("|", "_")

func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)

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

func _display_base64_image(base64_string):
	var image = _base64_to_image(base64_string)
	if image != null:
		var texture = ImageTexture.create_from_image(image)
		%backgroundImg.texture = texture
		siteImgs[currentSiteName] = texture
		_save_image_png(image, SCENE_IMG_DIR, currentSiteName)
		_bg_debug("display image ok, site=" + currentSiteName + ", b64_len=" + str(base64_string.length()))
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

func _build_explore_system_prompt() -> String:
	var guards = "用户初始设定：" + world_seed_input + "\n"
	guards += "当前世界观：" + background + "\n"
	guards += "请确保地点、NPC、英文生图提示词与上述设定完全一致。"
	return role_prompt + "\n" + guards

func ensure_item_profile_async(item_name: String) -> void:
	if !itemProfiles.has(item_name):
		var disk_profile = _load_item_profile_json(item_name)
		itemProfiles[item_name] = {
			"description": disk_profile.get("description", "正在生成物品介绍..."),
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
		var cached_value: int
		var cached_rarity: String
		var cached_effect_type: String
		var cached_effect_value: int
		if !disk_profile.is_empty():
			cached_desc = str(disk_profile.get("description", "这是一件实用的道具。"))
			cached_value = int(disk_profile.get("value", 50))
			cached_rarity = str(disk_profile.get("rarity", "common"))
			cached_effect_type = str(disk_profile.get("effect_type", "none"))
			cached_effect_value = int(disk_profile.get("effect_value", 0))
		else:
			var fresh = await _generate_item_profile(item_name)
			cached_desc = str(fresh.get("description", "这是一件实用的道具。"))
			cached_value = int(fresh.get("value", 50))
			cached_rarity = str(fresh.get("rarity", "common"))
			cached_effect_type = str(fresh.get("effect_type", "none"))
			cached_effect_value = int(fresh.get("effect_value", 0))
			_save_item_profile_json(item_name, fresh)
		itemProfiles[item_name]["description"] = cached_desc
		itemProfiles[item_name]["value"] = cached_value
		itemProfiles[item_name]["rarity"] = cached_rarity
		itemProfiles[item_name]["effect_type"] = cached_effect_type
		itemProfiles[item_name]["effect_value"] = cached_effect_value
		itemProfiles[item_name]["texture"] = cached_tex
		itemProfiles[item_name]["is_generating"] = false
		itemProfiles[item_name]["is_ready"] = true
		%itemContainer.update_item_visual(item_name, cached_tex, cached_desc, cached_effect_type, cached_effect_value)
		return

	var profile = await _generate_item_profile(item_name)
	var item_description = str(profile.get("description", "这是一件实用的道具，可在冒险中派上用场。"))
	var item_value = int(profile.get("value", 50))
	var item_rarity = str(profile.get("rarity", "common"))
	var item_effect_type = str(profile.get("effect_type", "none"))
	var item_effect_value = int(profile.get("effect_value", 0))
	var image_prompt = str(profile.get("image_prompt", "single game inventory item icon, clean background, detailed, centered"))
	_save_item_profile_json(item_name, profile)
	var item_texture = await _generate_item_texture(image_prompt)

	if item_texture != null:
		var item_image = (item_texture as ImageTexture).get_image()
		if item_image != null:
			_save_image_png(item_image, ITEM_IMG_DIR, item_name)

	itemProfiles[item_name]["description"] = item_description
	itemProfiles[item_name]["value"] = item_value
	itemProfiles[item_name]["rarity"] = item_rarity
	itemProfiles[item_name]["effect_type"] = item_effect_type
	itemProfiles[item_name]["effect_value"] = item_effect_value
	itemProfiles[item_name]["texture"] = item_texture
	itemProfiles[item_name]["is_generating"] = false
	itemProfiles[item_name]["is_ready"] = true
	%itemContainer.update_item_visual(item_name, item_texture, item_description, item_effect_type, item_effect_value)

# ==================== UI 操作 ====================
func _on_send_button_pressed():
	var user_input = input_text_edit.text.strip_edges()
	if user_input == "" or ai_busy:
		return
	%InputTextEdit.text = ""
	last_action_input = user_input
	addLog("【行动】" + user_input)
	changeTextTo(%speakerNameLabel, playerName)
	changeTextTo(response_label, user_input)
	var action_context = "用户初始设定：" + world_seed_input
	action_context += "\n当前世界观：" + background
	action_context += "\n当前地点：" + currentSiteName
	action_context += "\n玩家资产：" + str(money)
	action_context += "\n玩家背包：" + _build_inventory_snapshot()
	var aprompts = [
		{"role":"system","content": action_prompt + "\n" + action_context},
		{"role":"user","content": user_input}]
	await ask_ai(aprompts, aiMode.action)

func _on_dialogue_button_pressed():
	if currentState != worldState.chat or currentNpc == null or ai_busy:
		return
	var user_input = dialogue_input.text.strip_edges()
	if user_input == "":
		return
	last_dialogue_input = user_input
	dialogue_input.text = ""
	changeTextTo(%speakerNameLabel, playerName)
	changeTextTo(response_label, user_input)
	currentNpc.chatWithNpc(user_input)
	currentNpc.currentChat += "玩家：" + user_input + "\n"

func set_ai_busy(v: bool) -> void:
	ai_busy = v
	send_button.disabled = v
	dialogue_button.disabled = v
	for btn in %site_buttons.get_children():
		if btn is BaseButton:
			btn.disabled = v
	for btn in %npc_buttons.get_children():
		if btn is BaseButton:
			btn.disabled = v

func changeTextTo(nodeToChange: Control, text: String, speed = 30):
	if nodeToChange.text == text:
		return
	await create_tween().tween_property(nodeToChange, "visible_ratio", 0, 0.4).finished
	nodeToChange.text = text
	await create_tween().tween_property(nodeToChange, "visible_ratio", 1, float(text.length()) / speed).finished

func clear_children(node: Node):
	for i in node.get_children():
		i.queue_free()

func addLog(logText: String):
	var newLog = load("res://fabs/log_rich_text_label.tscn").instantiate()
	newLog.text = logText
	%logContainer.add_child(newLog)

func _build_inventory_snapshot(max_items: int = 10) -> String:
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
					return
				envDic =jsonDic
				if %envContainer.load_weather_config_from_json(envDic):
					$mainMenu.if_weather_ok()
					pass
			aiMode.explore:
				var jsonDic = extract_json_from_text(data["text"])
				if jsonDic == {}:
					changeTextTo(response_label, "你并没有找到" + currentSiteName + "，休息了一会，你再次进行了尝试")
					goto(currentSiteName)
					return
				# 先确保必要字段存在
				if !jsonDic.has("能前往的地点") or !(jsonDic["能前往的地点"] is Array):
					jsonDic["能前往的地点"] = []
				if !jsonDic.has("npc") or !(jsonDic["npc"] is Dictionary):
					jsonDic["npc"] = {}
				if !jsonDic.has("英文描述") or str(jsonDic.get("英文描述", "")).strip_edges() == "":
					jsonDic["英文描述"] = str(jsonDic.get("地点描述", ""))
				var location_name = str(jsonDic.get("地点名称", ""))
				if location_name == "" and pending_explore_target != "":
					location_name = pending_explore_target
					jsonDic["地点名称"] = location_name
				if !jsonDic.has("地点描述") or str(jsonDic.get("地点描述", "")).strip_edges() == "":
					jsonDic["地点描述"] = "你来到了" + location_name
				if location_name == "":
					changeTextTo(response_label, "地点信息解析失败，请重试")
					set_ai_busy(false)
					return
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

				sites[location_name] = jsonDic
				currentSiteName = location_name
				pending_explore_target = ""
				_save_site_json(location_name, jsonDic)
				pending_site_update = true
				site_update()
			aiMode.chat:
				#print("开始聊天")
				npc_reply(data["text"])
			aiMode.action:
				var action_reply = data.get("text", "")
				if action_reply is String and action_reply.strip_edges() != "":
					changeTextTo(%speakerNameLabel, "【旁白】")
					changeTextTo(response_label, process_string(action_reply))
					var tool_tags = get_content_in_angle_brackets(action_reply)
					if tool_tags != "":
						var aprompts = [
							{"role":"system","content": agent_prompt},
							{"role":"user","content": tool_tags}]
						await ask_ai(aprompts, aiMode.tools)
					else:
						var infer_prompts = [
							{"role":"system","content": agent_prompt + "\n若输入没有<>标签，也要从语义中尽力提取可执行方法；如果确实没有再回复没有方法被调用。"},
							{"role":"user","content": action_reply}
						]
						await ask_ai(infer_prompts, aiMode.tools)
						_auto_handle_action_search(last_action_input, action_reply)
					_auto_apply_action_effects(last_action_input, action_reply, tool_tags)
			aiMode.sum:
				npcs[currentNpc.npcName]["npc_log"].append(data["text"])
				addLog("你结束了与" + currentNpc.npcName + "的对话。" + data["text"])
			aiMode.tools:
				if data["text"] is Array:
					handle_npc_instruction(data["text"])
				elif data["text"] is Dictionary:
					handle_npc_instruction([data["text"]])
				elif data["text"] is String:
					var parser = JSON.new()
					if parser.parse(data["text"]) == OK:
						var parsed = parser.get_data()
						if parsed is Array:
							handle_npc_instruction(parsed)
						elif parsed is Dictionary and parsed.has("function"):
							handle_npc_instruction([parsed])
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
		pending_img_prompt = ""
		gen_img(queued)

func _on_img_http_request_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_bg_debug("img callback, result=" + str(result) + ", code=" + str(response_code) + ", body_len=" + str(body.size()))
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
			_display_base64_image(image_data)
		else:
			print("图片生成失败：未收到图片数据")
			_bg_debug("img callback success=true but image empty")
			if pending_site_update:
				pending_site_update = false
				site_update()
		_drain_pending_img()
	else:
		var error_msg = response.get("error", "未知错误")
		print("图片生成失败：" + error_msg)
		_bg_debug("img callback failed, error=" + error_msg)
		if pending_site_update:
			pending_site_update = false
			site_update()
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
	while ai_busy and retry < 20:
		await get_tree().create_timer(0.15).timeout
		retry += 1
	if ai_busy or currentState == worldState.chat:
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
	for log_entry in npcs[npc_name]["npc_log"]:
		logs += log_entry
	new_npc.npcLog = logs
	newNpc = new_npc
	changeStateInto(GameManager.worldState.chat)

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
	return {}

func _spawn_context_npc(reason: String, forced_npc: Dictionary = {}) -> void:
	if currentSiteName == "":
		return
	var npcs_by_reason = {
		"money": [
			{"name": "路过的清洁阿姨", "describe": "一位戴着手套、动作麻利的阿姨"},
			{"name": "值班保安", "describe": "穿着制服、目光警觉的保安"},
			{"name": "路人同学", "describe": "背着双肩包、神情好奇的学生"}
		],
		"exercise": [
			{"name": "运动社学长", "describe": "穿着运动外套、状态很好的学长"},
			{"name": "晨跑女生", "describe": "戴着耳机、步伐轻快的女生"},
			{"name": "体育老师", "describe": "吹着口哨、语气爽朗的老师"}
		],
		"time_pass": [
			{"name": "热心同学", "describe": "抱着教材、主动搭话的同学"},
			{"name": "陌生访客", "describe": "拿着地图、看起来有些迷路的人"},
			{"name": "校园志愿者", "describe": "佩戴袖章、语气友好的志愿者"}
		],
		"crime": [
			{"name": "保安大叔", "describe": "腰挂对讲机、神情严肃走来的保安"},
			{"name": "目击室友", "describe": "突然出现在旁边、一脸惊讶的室友"},
			{"name": "店员", "describe": "眼神警惕、快步走来的工作人员"}
		]
	}
	var npc_name = ""
	var npc_describe = ""
	if !forced_npc.is_empty():
		npc_name = str(forced_npc.get("name", "")).strip_edges()
		npc_describe = str(forced_npc.get("describe", "正在此地活动"))
	else:
		if !npcs_by_reason.has(reason):
			return
		var pool: Array = npcs_by_reason[reason]
		if pool.is_empty():
			return
		var pick = pool[randi_range(0, pool.size() - 1)]
		npc_name = str(pick.get("name", "路人"))
		npc_describe = str(pick.get("describe", "正在此地活动"))

	if npc_name == "":
		return

	if npcs.has(npc_name):
		await get_tree().create_timer(0.4).timeout
		_auto_initiate_npc_chat(npc_name, str(npcs[npc_name].get("npc_describe", npc_describe)))
		return

	# 旧逻辑（保留）: create_NPC + addLog，仅记录不主动对话
	# create_NPC(npc_name, currentSiteName, npc_describe)
	# addLog("<" + npc_name + "主动与你有了互动。>")

	# 新逻辑：创建NPC并延迟自动开启对话
	create_NPC(npc_name, currentSiteName, npc_describe)
	addLog("<" + npc_name + "注意到了你，主动走了过来。>")
	await get_tree().create_timer(0.8).timeout
	_auto_initiate_npc_chat(npc_name, npc_describe)

func _trigger_time_pass_npc_event(hours: float) -> void:
	if hours < 1.0:
		return
	if randf() < 0.35:
		_spawn_context_npc("time_pass")

func _auto_apply_action_effects(action_input: String, action_reply: String, tool_tags: String) -> void:
	var source = (action_input + "\n" + action_reply).strip_edges()
	if source == "":
		return

	var has_time_tool = tool_tags.find("设置时间") != -1 or tool_tags.find("set_time") != -1
	var has_money_tool = tool_tags.find("consume_items") != -1 or tool_tags.find("initiate_transaction") != -1
	var passed_hours = 0.0

	var changed = false

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
			addLog("<你扔掉了" + str(real_cost) + "块钱，当前资产" + str(money) + ">")
			if real_cost > 0 and randf() < 0.6:
				_spawn_context_npc("money")
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
		if randf() < 0.5:
			_spawn_context_npc("exercise")
		changed = true

	if source.find("睡") != -1 and (source.find("睡觉") != -1 or source.find("睡一觉") != -1 or source.find("入睡") != -1):
		if !has_time_tool:
			var target_time = _extract_target_time(source)
			if target_time.get("valid", false):
				passed_hours += set_time(int(target_time.get("hour", 8)), int(target_time.get("minute", 0)))
			else:
				var wake_hour = randi_range(6, 10)
				var wake_min = randi_range(0, 59)
				passed_hours += set_time(wake_hour, wake_min)
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
	if has_crime_tag:
		var penalty = randi_range(8, 20)
		reputation = max(0.0, reputation - penalty)
		addLog("<违规行为被记录，声誉-" + str(penalty) + ">")
		var crime_npc = _pick_crime_npc_from_action(action_input)
		if !crime_npc.is_empty():
			_spawn_context_npc("crime", crime_npc)
		else:
			_spawn_context_npc("crime")
		changed = true

	_trigger_time_pass_npc_event(passed_hours)

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
	var price_label = ("总价" + str(price)) if is_total else (str(price) + "每件")
	var seller_name = "附近商贩"
	if currentNpc != null:
		seller_name = str(currentNpc.npcName)
	addLog("<" + seller_name + "想要以" + price_label + "出售" + str(item_name) + "X" + str(quantity) + ">")
	%event.got_deal_event(item_name, quantity, price, is_total)

# 给予物品：NPC想要送给玩家物品
func got_items(item_name: String, quantity: int) -> void:
	%event.got_gift_event(item_name, quantity)
	addLog("<有人想送你" + str(item_name) + "X" + str(quantity) + ">")
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
		var cleaned = str(site_name).strip_edges()
		if cleaned != "":
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
	var location_text = "世界某处"
	if location != "":
		location_text = location
	if location != "":
		if !sites.has(location) or !(sites[location] is Dictionary):
			sites[location] = {"能前往的地点": [], "npc": {}, "地点名称": location, "地点描述": "", "英文描述": ""}
		if !sites[location].has("npc") or !(sites[location]["npc"] is Dictionary):
			sites[location]["npc"] = {}
		sites[location]["npc"][npc_name] = npc_describe
		if location == currentSiteName:
			site_update()
	addLog("<你听说" + location_text + "有位" + str(npc_describe) + "：" + str(npc_name) + ">")
	pass

func _auto_handle_action_search(action_input: String, action_reply: String) -> void:
	var input_text = action_input.strip_edges()
	if input_text == "":
		return
	if !(input_text.find("寻找") != -1 or input_text.find("找") != -1):
		return
	var fail_tokens = ["没找到", "没有找到", "未找到", "找不到", "这里没有"]
	for t in fail_tokens:
		if action_reply.find(t) != -1:
			return

	var target = input_text
	if target.find("寻找") != -1:
		target = target.substr(target.find("寻找") + 2)
	elif target.find("找") != -1:
		target = target.substr(target.find("找") + 1)
	target = target.replace("。", "").replace("，", "").replace("!", "").replace("？", "").strip_edges()
	if target == "":
		return

	var location_hints = ["楼", "馆", "店", "部", "室", "场", "食堂", "宿舍", "图书馆", "超市", "办公室", "校门"]
	var is_location = false
	for hint in location_hints:
		if target.find(hint) != -1:
			is_location = true
			break

	if is_location:
		create_location(currentSiteName + "-" + target)
	else:
		create_NPC(target, currentSiteName, "正在此地活动")

# 创建传闻：NPC提及了某个传闻、新闻或谣言
func create_rumors(rumor_name: String, content: String) -> void:
	rumors[rumor_name] = content
	addLog("<传闻：" + str(rumor_name) + " - " + str(content) + ">")
	pass

func update_reputation(quantity:int)->void:
	reputation-=quantity
	quantity = clamp(quantity,0,100)
	player_update()
	addLog("<声望减少了：" + str(quantity)+">")

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
func destroy_yourself() -> void:
	if currentNpc == null:
		return
	var npc_name = currentNpc.npcName
	addLog("<" + npc_name + "离开了，也许再也见不到了...>")
	for i:npcButton in %npc_buttons.get_children():
		if i.npcName == npc_name:
			i.queue_free()
			return

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

		if parameters is Dictionary and parameters.has("quantity"):
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
					can_merge = int(parameters.get("price", 0)) == int(prev_params.get("price", 0))
				if can_merge:
					prev_params["quantity"] = int(prev_params.get("quantity", 1)) + int(parameters.get("quantity", 1))
					normalized_calls[normalized_calls.size() - 1]["parameters"] = prev_params
					continue

		normalized_calls.append({"method": method, "parameters": parameters})

	for tool_call_item in normalized_calls:
		var method = str(tool_call_item.get("method", ""))
		var parameters: Dictionary = tool_call_item.get("parameters", {})
		match method:
			"initiate_transaction":
				initiate_transaction(
					parameters.get("item_name", ""),
					max(1, int(parameters.get("quantity", 1))),
					int(parameters.get("price", 0)),
					bool(parameters.get("is_total_price", false))
				)
			"got_items":
				got_items(
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
				destroy_yourself()
			_:
				print("未知方法: ", method)
				addLog("<调试：未知工具调用 " + method + ">")
		await get_tree().create_timer(0.4).timeout
func add_item(itemToAdd, itemNum):
	if !itemProfiles.has(itemToAdd):
		var disk_profile = _load_item_profile_json(itemToAdd)
		itemProfiles[itemToAdd] = {
			"description": disk_profile.get("description", "正在生成物品介绍..."),
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
	_ensure_dir(SAVE_DIR)
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
		log_list.append(log_node.text)

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
		"logs": log_list
	}

	var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		addLog("<游戏已保存>")
	else:
		addLog("<保存失败：" + str(FileAccess.get_open_error()) + ">")

func load_game() -> void:
	if !FileAccess.file_exists(SAVE_FILE):
		addLog("<没有存档文件>")
		return
	var file = FileAccess.open(SAVE_FILE, FileAccess.READ)
	if !file:
		addLog("<读档失败>")
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		addLog("<存档文件损坏>")
		return
	file.close()
	var data = json.get_data()

	world_seed_input = data.get("world_seed_input", "")
	background      = data.get("background", "")
	sites           = data.get("sites", {})
	npcs            = data.get("npcs", {})
	rumors          = data.get("rumors", {})

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
		var tex = _load_image_png(ITEM_IMG_DIR, iname)
		itemProfiles[iname] = {
			"description": idesc,
			"value": ivalue,
			"rarity": irarity,
			"effect_type": ieffect_type,
			"effect_value": ieffect_value,
			"texture": tex,
			"is_generating": false,
			"is_ready": tex != null
		}
		%itemContainer.add_item(iname, inum, tex, idesc, ieffect_type, ieffect_value)
		if tex == null:
			ensure_item_profile_async(iname)

	# 恢复日志
	clear_children(%logContainer)
	for log_text in data.get("logs", []):
		addLog(log_text)

	# 恢复当前场景
	var site_name = data.get("current_site", "")
	if site_name != "" and sites.has(site_name):
		currentSiteName = site_name
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
				pending_site_update = true
				gen_img(scene_prompt)
		site_update()

	addLog("<读档完成>")
