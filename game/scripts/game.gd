extends Node
class_name GameManager

# UI引用
@onready var input_text_edit = %InputTextEdit
@onready var send_button = %SendButton
@onready var response_label = %ResponseLabel
@onready var http_request = $HTTPRequest

# 常量与枚举
enum worldState {explore, chat}
enum aiMode {init_background,init_env,explore, chat, sum, tools}

# 配置变量
var chat_url = "http://127.0.0.1:5000/chat"
var agent_url = "http://127.0.0.1:5000/agent"
var image_api_url = "http://localhost:5000/generate_image"

# 游戏数据
var sites: Dictionary
var npcs: Dictionary
var items: Dictionary
var rumors:Dictionary
var siteImgs: Dictionary
var itemProfiles: Dictionary = {}
var playerName: String = "阿尔的秘宝"
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
系统：你是一个角色扮演机器人，和用户进行模拟游戏，内容是在用户设定的世界中探索。
根据用户想去的地点，你要设想并严格以有效的json格式回复下列内容：
1.这个区域的样子
2.用于生图的英文场景描述
3.这个区域能到达的区域
4.其中的npc，每个npc都用一句话描述一下样子。
回复举例：
{
	"地点名称":"霓虹边境站",
	"地点描述":"你面前是霓虹闪烁的"锈蚀边境"检查站，酸雨正冲刷着带刺的电网。右侧通道飘来合成拉面的香气，正前方全息广告牌闪烁着"欢迎来到新京港"，左侧阴影里有个穿褪色夹克的男人正在擦拭义肢。",
	"英文描述":"Cyberpunk style gateway, holographic billboard",
	"能前往的地点":["拉面摊","入境大厅","暗巷口"],
	"npc":{
		"拉面摊主":"围裙上沾着油渍的仿生人，机械臂正在切叉烧",
		"海关官员":"戴着数据目镜的银发女人，指尖敲击着全息屏幕",
		"义体贩子":"靠在墙角的男人，右眼闪着红光，脚边放着黑色医疗器械箱"
	}
}
"""

var agent_prompt:String = """你是一个AI智能体，擅长确定需要调用的方法,没有合适的就回复：没有方法被调用。给你的就是ai的回复，所有提到的物品均为游戏道具，不完整的信息就猜测补齐，不要问问题
	如果输入信息类似于：<以50的价格卖1把剑>，那就是要卖给玩家某件物品。
	如果输入信息类似于：<送1瓶治疗药水>，那就是要送给玩家某件物品。
	如果输入信息类似于：<接受1瓶治疗药水>，那就是要接受玩家的某件物品。
	如果输入信息类似于：<创建路径：幽暗森林-雪山-龙之谷><创建路径：商贩摊位>，那就是提到了某个地点或提到了到达某个地方的一系列地点的路径。
	如果输入信息类似于：<老约翰在酒馆，是一个靠在墙角的男人，右眼闪着红光，脚边放着行李箱>，那就是提及了某个地方有某个NPC。
	如果输入信息类似于：<传闻：国王被暗杀-国王被暗杀，引起震惊>，那就是提及了类似于传闻、新闻、谣言的事件
	如果输入信息类似于：<离开>，那就是想要离开，或者自己要死了。
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

# ==================== 生命周期函数 ====================
func _ready():
	send_button.connect("pressed", _on_send_button_pressed)
	%backgroundImg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player_update()
var background:String

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not send_button.disabled:
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
		worldState.explore:
			create_tween().tween_property(%npcIcon, "custom_minimum_size:x", 0, 0.2)
			changeTextTo(%speakerNameLabel, playerName, 100)

	currentState = stateToChange

# ==================== 地点导航 ====================
func goto(where: String):
	await changeStateInto(GameManager.worldState.explore)
	if sites.has(where)&&sites[where].has("地点描述"):
		print("地点已经存在")
		currentSiteName = where
		%backgroundImg.texture = siteImgs[currentSiteName]
		site_update()
	else:
		changeTextTo(response_label, "正在探索" + where + "...", 8)
		var prompts = [
			{"role":"system","content": role_prompt+background},
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
					"rumor_name": {"type": "integer", "quantity": "增加或减少的数量，增加为正值，减少为负值"}
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
	}
]

# ==================== AI 交互 ====================
func ask_ai(message: Array, askmode: aiMode):
	currentMode = askmode
	send_button.disabled = true
	var body = [message,null,"text"]
	match askmode:
		aiMode.tools:
			body = [message,tools,"text"]
		aiMode.explore:
			body = [message,null,"json_object"]
	var url = chat_url
	var json_string = JSON.stringify(body)
	var err = http_request.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		json_string
	)
	if err != OK:
		changeTextTo(response_label, "请求失败: " + str(err))
		send_button.disabled = false
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

func _display_base64_image(base64_string):
	var texture = _base64_to_texture(base64_string)
	if texture != null:
		%backgroundImg.texture = texture
		siteImgs[currentSiteName] = texture
		print(texture)
	else:
		print("错误：图片格式不支持")

func _base64_to_texture(base64_string: String) -> Texture2D:
	if base64_string == "":
		return null
	var image_buffer = Marshalls.base64_to_raw(base64_string)
	var image = Image.new()
	var error = image.load_png_from_buffer(image_buffer)
	if error != OK:
		error = image.load_jpg_from_buffer(image_buffer)
	if error != OK:
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
	var req = await _request_json(
		image_api_url,
		JSON.stringify({"prompt": image_prompt, "width": 1024, "height": 1024})
	)
	if !req.get("ok", false):
		return null
	var image_data = req["data"].get("image", "")
	return _base64_to_texture(image_data)

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
	%itemContainer.update_item_visual(item_name, itemProfiles[item_name].get("texture", null), itemProfiles[item_name].get("description", "正在生成物品介绍..."))

	var profile = await _generate_item_profile(item_name)
	var item_description = profile.get("description", "这是一件实用的道具，可在冒险中派上用场。")
	var image_prompt = profile.get("image_prompt", "single game inventory item icon, clean background, detailed, centered")
	var item_texture = await _generate_item_texture(image_prompt)

	itemProfiles[item_name]["description"] = item_description
	itemProfiles[item_name]["texture"] = item_texture
	itemProfiles[item_name]["is_generating"] = false
	itemProfiles[item_name]["is_ready"] = true
	%itemContainer.update_item_visual(item_name, item_texture, item_description)

# ==================== UI 操作 ====================
func _on_send_button_pressed():
	var user_input = input_text_edit.text.strip_edges()
	if user_input == "":
		return

	changeTextTo(%speakerNameLabel, playerName)
	changeTextTo(response_label, user_input)
	%InputTextEdit.text = ""

	match currentState:
		worldState.explore:
			pass
		worldState.chat:
			currentNpc.chatWithNpc(user_input)
			currentNpc.currentChat += "玩家：" + user_input + "\n"

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
	send_button.disabled = false
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
				print("能前往的地点", jsonDic["能前往的地点"])
				if currentSiteName != "" && !jsonDic["能前往的地点"].has(currentSiteName):
					jsonDic["能前往的地点"].append(currentSiteName)
				#已经存在，执行合并操作
				var prenpcs = []
				var presites = []
				if sites.has(jsonDic["地点名称"]):
					if sites.has(jsonDic["地点名称"]["能前往的地点"]):
						presites = sites[jsonDic["地点名称"]]["能前往的地点"]
						print("发现了预先存在的地点")
					if sites.has(jsonDic["地点名称"]["npc"]):
						prenpcs = sites[jsonDic["地点名称"]]["npc"]
						print("发现了预先存在的npc")
				sites[jsonDic["地点名称"]] = jsonDic
				if prenpcs.size()!=0:
					sites[jsonDic["地点名称"]["能前往的地点"]].append_array(prenpcs)
				if presites.size()!=0:
					sites[jsonDic["地点名称"]["npc"]].append_array(presites)
				currentSiteName = jsonDic["地点名称"]
				site_update()
			aiMode.chat:
				#print("开始聊天")
				npc_reply(data["text"])
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
		return

	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())

	if parse_error != OK:
		print("图片生成失败：响应解析错误", body.get_string_from_utf8())
		return

	var response = json.get_data()

	if response_code == 200 and response.get("success", false):
		var image_data = response.get("image", "")
		if image_data:
			_display_base64_image(image_data)
		else:
			print("图片生成失败：未收到图片数据")
	else:
		var error_msg = response.get("error", "未知错误")
		print("图片生成失败：" + error_msg)

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
	%itemContainer.consume_item(item_name,quantity)
	addLog("<你失去了" + str(item_name) + "X" + str(quantity) + ">")
	pass

# 创建地点：NPC提到了到达某个地方的路径
func create_location(path: String) -> void:
	var newSites = path.split("-")
	if newSites.size() == 1:
		addLog("<地图更新：发现了" + str(newSites[0]) + ">")
		if newSites[0]!=currentSiteName:
			sites[currentSiteName]["能前往的地点"].append(newSites[0])
			var new_site_button = load("res://fabs/site_button.tscn").instantiate() as siteButton
			new_site_button.siteName = newSites[0]
			%site_buttons.add_child(new_site_button)
	else:
		var nowsite = currentSiteName
		for i in newSites:
			if newSites[0]==currentSiteName:
				continue
			if !sites.has(nowsite):
				sites[nowsite] = {}
				sites[nowsite]["能前往的地点"] = []
			sites[nowsite]["能前往的地点"].append(i)
			print("为",nowsite,"添加了地点：",i)
			nowsite = i

		addLog("<地图更新：发现了前往" + str(newSites[-1]) + "的路："+path+">")
		var new_site_button = load("res://fabs/site_button.tscn").instantiate() as siteButton
		new_site_button.siteName = newSites[0]
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
				consume_items(
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
			"destroy_self":
				destroy_yourself()
			_:
				response_label.text += "未知方法: " + method + "\n"
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
