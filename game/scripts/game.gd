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
const SAVE_DIR = "D:/毕设/worldSim/game/saves/"
const SAVE_FILE = SAVE_DIR + "save.json"

var pending_site_update: bool = false

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
	如果输入信息类似于：<以50的价格卖1把剑>，那就是要卖给玩家某件物品。
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
	"image_prompt":"英文生图提示词，适合生成单个道具图标，纯净背景，无文字"
}
只输出 JSON，不要包含 markdown 代码块。
"""

var validation_feedback_prompt:String = """
你是文字游戏旁白。请根据输入场景，输出一句简短中文反馈（15~35字，口语化、自然）。
仅输出一句话，不要解释，不要加引号。
"""

var action_prompt:String = """
你是文字游戏的世界叙述者。玩家进行了一个行动，请根据世界背景用一句简短中文（15~50字）叙述该行动的自然结果。
若行动涉及等待到某时刻（如“等到下午4点”），在叙述末加：<设置时间：16:00>
若行动涉及离开当前地点，在叙述末加：<离开>
仅输出一句叙述文本，工具指令以<>括号附加在句末，不要解释。
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

	currentState = stateToChange

# ==================== 地点导航 ====================
func goto(where: String):
	await changeStateInto(GameManager.worldState.explore)
	if sites.has(where) && sites[where].has("地点描述"):
		print("地点已经存在")
		currentSiteName = where
		if siteImgs.has(where):
			%backgroundImg.texture = siteImgs[where]
		else:
			var cached = _load_image_png(SCENE_IMG_DIR, where)
			if cached != null:
				%backgroundImg.texture = cached
				siteImgs[where] = cached
		site_update()
	else:
		changeTextTo(response_label, "正在探索" + where + "...", 8)
		var prompts = [
			{"role":"system","content": _build_explore_system_prompt()},
			{"role":"user","content": "我想去"+where}]
		await ask_ai(prompts, aiMode.explore)
		gen_img(sites[currentSiteName]["英文描述"])

func site_update():
	changeTextTo(%siteName, currentSiteName)
	changeTextTo(response_label, sites[currentSiteName]["地点描述"],15)
	clear_children(%site_buttons)
	clear_children(%npc_buttons)
	for i in sites[currentSiteName]["能前往的地点"]:
		var new_site_button = load("res://fabs/site_button.tscn").instantiate() as siteButton
		new_site_button.siteName = i
		%site_buttons.add_child(new_site_button)

	for i in sites[currentSiteName]["npc"]:
		if i not in npcs:
			npcs[i] = {}
		npcs[i]["npc_name"] = i
		npcs[i]["npc_describe"] = sites[currentSiteName]["npc"][i]
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
					"price": {"type": "integer", "description": "物品单价，日用品10-100，技术产品100-200，稀有物品300-400"}
				},
				"required": ["item_name", "price"]
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
				"required": ["item_name"]
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
				"required": ["item_name"]
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

func npc_reply(reply: String):
	changeTextTo(%speakerNameLabel, currentNpc.npcName)
	changeTextTo(response_label, process_string(reply))
	currentNpc.currentChat +=  currentNpc.npcName +":"+ reply + "\n"
	var toolsTexts = get_content_in_angle_brackets(reply)
	print("提取出的工具信息：",toolsTexts)
	if toolsTexts!="":
		var prompts = [
			{"role":"system","content": agent_prompt},
			{"role":"user","content": toolsTexts}]
		await ask_ai(prompts, aiMode.tools)

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
	print("正在同时生成图片...")
	var headers = ["Content-Type: application/json"]
	var image_json_data = JSON.stringify({"prompt": prompt})
	var error_image = %ImgHTTPRequest.request(image_api_url, headers, HTTPClient.METHOD_POST, image_json_data)
	print("请求返回了...",error_image)
	if error_image != OK:
		print("错误：请求创建失败")
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
	else:
		print("错误：图片格式不支持")
	if pending_site_update:
		pending_site_update = false
		site_update()

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
			"image_prompt": "single game inventory item icon, clean background, detailed, centered"
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
		"image_prompt": "single game inventory item icon, clean background, detailed, centered"
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
		itemProfiles[item_name] = {
			"description": "正在生成物品介绍...",
			"texture": null,
			"is_generating": false,
			"is_ready": false
		}

	if itemProfiles[item_name].get("is_generating", false) or itemProfiles[item_name].get("is_ready", false):
		return

	itemProfiles[item_name]["is_generating"] = true

	# 磁盘缓存检查
	var cached_tex = _load_image_png(ITEM_IMG_DIR, item_name)
	if cached_tex != null:
		var cached_profile = await _generate_item_profile(item_name)
		var cached_desc = cached_profile.get("description", "这是一件实用的道具。")
		itemProfiles[item_name]["description"] = cached_desc
		itemProfiles[item_name]["texture"] = cached_tex
		itemProfiles[item_name]["is_generating"] = false
		itemProfiles[item_name]["is_ready"] = true
		%itemContainer.update_item_visual(item_name, cached_tex, cached_desc)
		return

	var profile = await _generate_item_profile(item_name)
	var item_description = profile.get("description", "这是一件实用的道具，可在冒险中派上用场。")
	var image_prompt = profile.get("image_prompt", "single game inventory item icon, clean background, detailed, centered")
	var item_texture = await _generate_item_texture(image_prompt)

	if item_texture != null:
		var item_image = (item_texture as ImageTexture).get_image()
		if item_image != null:
			_save_image_png(item_image, ITEM_IMG_DIR, item_name)

	itemProfiles[item_name]["description"] = item_description
	itemProfiles[item_name]["texture"] = item_texture
	itemProfiles[item_name]["is_generating"] = false
	itemProfiles[item_name]["is_ready"] = true
	%itemContainer.update_item_visual(item_name, item_texture, item_description)

# ==================== UI 操作 ====================
func _on_send_button_pressed():
	var user_input = input_text_edit.text.strip_edges()
	if user_input == "" or ai_busy:
		return
	%InputTextEdit.text = ""
	addLog("【行动】" + user_input)
	changeTextTo(%speakerNameLabel, playerName)
	changeTextTo(response_label, user_input)
	var action_context = "用户初始设定：" + world_seed_input + "\n当前世界观：" + background + "\n当前地点：" + currentSiteName
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
				print("能前往的地点", jsonDic["能前往的地点"])
				if currentSiteName != "" && !jsonDic["能前往的地点"].has(currentSiteName):
					jsonDic["能前往的地点"].append(currentSiteName)
				# 已经存在，执行合并操作
				var location_name = str(jsonDic.get("地点名称", ""))
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
				currentSiteName = jsonDic["地点名称"]
				pending_site_update = true
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



var weather:String = """
	"""

func _on_img_http_request_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("图片生成失败：网络错误")
		if pending_site_update:
			pending_site_update = false
			site_update()
		return

	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())

	if parse_error != OK:
		print("图片生成失败：响应解析错误", body.get_string_from_utf8())
		if pending_site_update:
			pending_site_update = false
			site_update()
		return

	var response = json.get_data()

	if response_code == 200 and response.get("success", false):
		var image_data = response.get("image", "")
		if image_data:
			_display_base64_image(image_data)
		else:
			print("图片生成失败：未收到图片数据")
			if pending_site_update:
				pending_site_update = false
				site_update()
	else:
		var error_msg = response.get("error", "未知错误")
		print("图片生成失败：" + error_msg)
		if pending_site_update:
			pending_site_update = false
			site_update()

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


# 初始化交易：NPC想要卖给玩家物品
func initiate_transaction(item_name: String, quantity: int, price: int) -> void:
	addLog("<" + str(currentNpc.npcName) + "想要以" + str(price) + "的价格出售" + str(item_name) + "X" + str(quantity) + ">")
	%event.got_deal_event(item_name, quantity, price)
	pass

# 给予物品：NPC想要送给玩家物品
func got_items(item_name: String, quantity: int) -> void:
	add_item(item_name, quantity)
	addLog("<你获得了" + str(item_name) + "X" + str(quantity) + ">")
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
	addLog("<你听说" + location_text + "有位" + str(npc_describe) + "：" + str(npc_name) + ">")
	pass

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

func set_time(hour: int, minute: int) -> void:
	var target = float(hour * 60 + minute)
	if target <= nowtime:
		target += 1440.0
	nowtime = target
	addLog("<时间跳跃至 %02d:%02d>" % [hour, minute])

# 自我销毁：NPC说想要永远离开或自己要死了
func destroy_yourself() -> void:
	addLog("<" + str(currentNpc.npcName) + "离开了，也许再也见不到了...>")
	for i:npcButton in %npc_buttons.get_children():
		if i.npcName == currentNpc.npcName:
			i.queue_free()
			return
	pass

# 处理从AI接收的JSON指令
func handle_npc_instruction(tool_calls: Array) -> void:
	for tool_call in tool_calls:
		print("接受到一个函数调用: ", tool_call)
		# 提取函数调用信息
		var function_data = tool_call.get("function", {})
		var method = function_data.get("name", "")
		var arguments_data = function_data.get("arguments", "{}")

		# 解析JSON参数
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

		# 根据方法名调用对应函数
		match method:
			"initiate_transaction":
				initiate_transaction(
					parameters.get("item_name", ""),
					parameters.get("quantity", 1),
					parameters.get("price", 0)
				)
			"got_items":
				got_items(
					parameters.get("item_name", ""),
					parameters.get("quantity", 1)
				)
			"consume_items":
				await consume_items(
					parameters.get("item_name", ""),
					parameters.get("quantity", 1)
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
		itemProfiles[itemToAdd] = {
			"description": "正在生成物品介绍...",
			"texture": null,
			"is_generating": false,
			"is_ready": false
		}
	%itemContainer.add_item(
		itemToAdd,
		itemNum,
		itemProfiles[itemToAdd].get("texture", null),
		itemProfiles[itemToAdd].get("description", "正在生成物品介绍...")
	)
	ensure_item_profile_async(itemToAdd)

# ==================== 存读档 ====================
func save_game() -> void:
	_ensure_dir(SAVE_DIR)
	var item_list: Array = []
	for child in %itemContainer.get_children():
		if child is item:
			item_list.append({
				"name": child.item_name,
				"num": child.item_num,
				"description": child.item_description
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
		if iname == "":
			continue
		var tex = _load_image_png(ITEM_IMG_DIR, iname)
		itemProfiles[iname] = {
			"description": idesc,
			"texture": tex,
			"is_generating": false,
			"is_ready": tex != null
		}
		%itemContainer.add_item(iname, inum, tex, idesc)
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
		var cached = _load_image_png(SCENE_IMG_DIR, site_name)
		if cached != null:
			%backgroundImg.texture = cached
			siteImgs[site_name] = cached
		site_update()

	addLog("<读档完成>")
