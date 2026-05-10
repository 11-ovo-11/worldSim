extends CanvasLayer
enum startState {chooseMode, getName, getEra, getLocation, validateSetup, persuadeSetup}
var currentState = startState.chooseMode
var last_conflict_reason: String = ""
var _init_watchdog_active: bool = false
var scene :GameManager
var playerName:String
var playerLocation:String
var start_mode: String = ""
var pending_character_brief: String = ""
var player_role_display: String = ""
var player_role_profile: String = ""
var player_era: String = ""
# 获取场景中的HTTPRequest节点
@onready var start_http_request: HTTPRequest = $startHTTPRequest
func _ready() -> void:
	scene = owner
	await get_tree().create_timer(2).timeout
	add_start_log("正在初始化...")
	await get_tree().create_timer(1).timeout
	add_start_log("系统自检中...")
	await get_tree().create_timer(1).timeout
	add_start_log("核心模块加载中...")
	await get_tree().create_timer(1).timeout
	add_start_log("神经网络连接检测...")
	check_chat_service()
	await start_http_request.request_completed
	add_start_log("视觉模块检测...")
	check_image_service()
	await start_http_request.request_completed
	add_start_log("检测到新的用户")
	await get_tree().create_timer(2).timeout
	add_start_log("你好...")
	await get_tree().create_timer(2).timeout
	add_start_log("请选择：新游戏 / 继续游戏")
	$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false


# 检查图片生成服务状态
func check_image_service():
	var url = "http://127.0.0.1:5000/check_image_service"
	var error = start_http_request.request(url)
	if error != OK:
		add_start_log("图片服务检查请求失败: "+ str(error))
		print(error)

# 检查问答生成服务状态
func check_chat_service():
	var url = "http://127.0.0.1:5000/check_chat_service"
	var error = start_http_request.request(url)
	if error != OK:
		add_start_log("聊天服务检查请求失败: "+ str(error))

# HTTP请求完成时的回调函数[citation:1][citation:2][citation:3]
func _on_start_http_request_request_completed(result, _response_code, _headers, body):
	if currentState == startState.validateSetup:
		var reply_text = ""
		if result == HTTPRequest.RESULT_SUCCESS:
			var jv = JSON.new()
			if jv.parse(body.get_string_from_utf8()) == OK:
				var rdata = jv.get_data()
				if rdata is Dictionary and rdata.has("text"):
					reply_text = str(rdata["text"]).strip_edges()
		_handle_conflict_check_result(reply_text)
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		add_start_log("HTTP请求失败，错误代码: "+str(result))
		return

	# 解析JSON响应[citation:2][citation:3]
	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())
	if parse_error != OK:
		print("JSON解析失败")
		return

	var response = json.get_data()
	var check_text = ""
	# 打印服务状态信息
	if response.has("message"):
		check_text+=response["message"]
		print("服务状态: ", response["message"])
	if response.has("status"):
		check_text+="_"+response["status"]
		print("连接状态: ", response["status"])
	if response.has("service"):
		check_text+="_to_"+response["service"]
		print("服务类型: ", response["service"])
	add_start_log(check_text)

func add_start_log(logText:String,right:bool = false):
	var newLog = load("res://fabs/log_rich_text_label.tscn").instantiate() as RichTextLabel
	if right:
		newLog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	newLog.text = logText
	newLog.speed = 15

	%startLog.add_child(newLog)
	await get_tree().create_timer(logText.length()/newLog.speed).timeout


func _on_button_button_down() -> void:
	var user_input = $HBoxContainer/VBoxContainer/TextEdit.text.strip_edges()
	if user_input == "":
		return

	match currentState:
		startState.chooseMode:
			$HBoxContainer/VBoxContainer/TextEdit.text = ""
			$HBoxContainer/VBoxContainer/TextEdit/Button.button_pressed = false
			$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = true
			await add_start_log(user_input,true)
			var normalized = _normalize_start_mode(user_input)
			if normalized == "continue":
				start_mode = "continue"
				if !scene.has_save_file():
					add_start_log("未检测到可用存档，请输入“新游戏”开始。")
					$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
					return
				add_start_log("已选择：继续游戏")
				await get_tree().create_timer(1).timeout
				add_start_log("正在读取存档...")
				var loaded_ok = scene.load_game()
				if loaded_ok:
					await _enter_loaded_game()
				else:
					add_start_log("读档失败，请输入“新游戏”重试。")
					start_mode = ""
					$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
			elif normalized == "new":
				start_mode = "new"
				pending_character_brief = ""
				player_role_display = ""
				player_role_profile = ""
				player_era = ""
				currentState = startState.getName
				add_start_log("已选择：新游戏")
				await get_tree().create_timer(1).timeout
				add_start_log("你是谁？")
				$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
			else:
				add_start_log("请输入“新游戏”或“继续游戏”。")
				$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
		startState.getName:
			var role_input = $HBoxContainer/VBoxContainer/TextEdit.text.strip_edges()
			$HBoxContainer/VBoxContainer/TextEdit.text = ""
			$HBoxContainer/VBoxContainer/TextEdit/Button.button_pressed = false
			$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = true
			await add_start_log(role_input,true)
			if player_role_display == "":
				player_role_display = _extract_role_display_name(role_input)
				playerName = player_role_display
			player_role_profile = _merge_character_profile(player_role_profile, role_input)
			pending_character_brief = player_role_profile
			var followup = _next_role_detail_question(player_role_profile)
			if followup != "":
				await get_tree().create_timer(0.4).timeout
				add_start_log(followup)
				$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
			else:
				pending_character_brief = ""
				currentState = startState.getEra
				await get_tree().create_timer(1).timeout
				add_start_log("好...")
				await get_tree().create_timer(1).timeout
				add_start_log("...")
				await get_tree().create_timer(1).timeout
				add_start_log("你所处的时代背景是？（例如：现代、近未来、古代、架空科幻）")
				$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
		startState.getEra:
			var era_input = $HBoxContainer/VBoxContainer/TextEdit.text.strip_edges()
			$HBoxContainer/VBoxContainer/TextEdit.text = ""
			$HBoxContainer/VBoxContainer/TextEdit/Button.button_pressed = false
			$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = true
			await add_start_log(era_input, true)
			if era_input == "":
				add_start_log("时代背景不能为空，请输入如：现代/近未来/古代/架空科幻。")
				$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
				return
			player_era = era_input
			currentState = startState.getLocation
			await get_tree().create_timer(0.6).timeout
			add_start_log("那么，你要到哪里去呢？")
			$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
		startState.getLocation:
			playerLocation = $HBoxContainer/VBoxContainer/TextEdit.text
			$HBoxContainer/VBoxContainer/TextEdit.text = ""
			$HBoxContainer/VBoxContainer/TextEdit/Button.button_pressed = false
			$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = true
			currentState = startState.validateSetup
			await add_start_log(playerLocation, true)
			await get_tree().create_timer(0.5).timeout
			add_start_log("正在验证设定兼容性...")
			_send_conflict_check(playerName, playerLocation)
		startState.persuadeSetup:
			var persuade_input = $HBoxContainer/VBoxContainer/TextEdit.text.strip_edges()
			$HBoxContainer/VBoxContainer/TextEdit.text = ""
			$HBoxContainer/VBoxContainer/TextEdit/Button.button_pressed = false
			$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = true
			await add_start_log(persuade_input, true)
			if persuade_input == "重新设定":
				pending_character_brief = ""
				player_role_display = ""
				player_role_profile = ""
				player_era = ""
				playerName = ""
				playerLocation = ""
				last_conflict_reason = ""
				currentState = startState.getName
				await get_tree().create_timer(0.5).timeout
				add_start_log("好，请重新输入你的角色设定。")
				await get_tree().create_timer(0.4).timeout
				add_start_log("你是谁？")
				$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
			else:
				currentState = startState.validateSetup
				add_start_log("正在重新验证设定兼容性...")
				_send_conflict_check_with_argument(persuade_input)

	pass # Replace with function body.

func _contains_any(text: String, words: Array) -> bool:
	for w in words:
		if text.find(str(w)) != -1:
			return true
	return false

func _merge_character_profile(base_profile: String, new_input: String) -> String:
	var base = base_profile.strip_edges()
	var extra = new_input.strip_edges()
	if base == "":
		return extra
	if extra == "":
		return base
	if extra.find(base) != -1:
		return extra
	if base.find(extra) != -1:
		return base
	return base + "；" + extra

func _extract_role_display_name(role_input: String) -> String:
	var t = role_input.strip_edges()
	if t == "":
		return "玩家"
	var role_keywords = ["老师", "学生", "医生", "警察", "程序员", "工程师", "商人", "记者", "律师", "军人", "研究员", "店员", "农民"]
	for r in role_keywords:
		if t.find(r) != -1:
			return r
	if t.find("，") != -1:
		t = t.substr(0, t.find("，"))
	if t.find(";") != -1:
		t = t.substr(0, t.find(";"))
	if t.find("；") != -1:
		t = t.substr(0, t.find("；"))
	t = t.strip_edges()
	if t.length() > 10:
		t = t.substr(0, 10)
	return t if t != "" else "玩家"

func _next_role_detail_question(profile_text: String) -> String:
	var t = profile_text.strip_edges()
	if t == "":
		return "请先告诉我你的核心身份（例如：老师、学生、医生、程序员）。"
	if _contains_any(t, ["老师", "教师", "讲师", "辅导员"]) and !_contains_any(t, ["幼儿园", "小学", "初中", "高中", "大学", "职校", "培训"]):
		return "你是哪个阶段的老师？例如：小学/初中/高中/大学/职校/培训机构。"
	if _contains_any(t, ["学生", "学员", "研究生"]) and !_contains_any(t, ["小学", "初中", "高中", "大学", "硕士", "博士", "职校", "培训"]):
		return "你是哪个阶段的学生？例如：小学/初中/高中/大学/硕士/博士/职校。"
	if _contains_any(t, ["医生", "医师"]) and !_contains_any(t, ["内科", "外科", "儿科", "急诊", "全科", "口腔", "精神", "护士"]):
		return "你主要在哪个医疗方向工作？例如：内科/外科/急诊/儿科/全科。"
	if _contains_any(t, ["警察", "民警", "警官"]) and !_contains_any(t, ["刑警", "交警", "治安", "网安", "巡警", "派出所"]):
		return "你属于哪类警务岗位？例如：刑警/交警/治安/网安/巡警。"
	if _contains_any(t, ["程序员", "工程师", "开发"]) and !_contains_any(t, ["前端", "后端", "全栈", "算法", "测试", "运维", "嵌入式"]):
		return "你的技术方向是？例如：前端/后端/全栈/算法/测试/运维。"
	return ""

func _is_character_profile_too_brief(profile_text: String) -> bool:
	var t = profile_text.strip_edges()
	if t.length() < 4:
		return true
	var score = 0
	if _contains_any(t, ["岁", "老师", "学生", "医生", "警察", "程序员", "工程师", "商人", "工人", "厨师", "记者", "律师", "司机", "研究员", "军人", "店员", "博主", "自由职业"]):
		score += 1
	if _contains_any(t, ["性格", "冷静", "冲动", "善良", "谨慎", "开朗", "内向", "外向", "固执", "悲观", "乐观", "严肃", "幽默", "暴躁", "温和"]):
		score += 1
	if _contains_any(t, ["来自", "出身", "背景", "经历", "曾经", "以前", "毕业", "离职", "家乡", "家庭", "父母", "童年"]):
		score += 1
	if _contains_any(t, ["想", "目标", "打算", "准备", "为了", "希望", "计划", "寻找", "逃离", "复仇", "赚钱", "证明", "完成"]):
		score += 1
	if t.length() >= 12:
		score += 1
	return score < 2

func _infer_setting_signals(text: String) -> Dictionary:
	var t = text.strip_edges()
	return {
		"modern_real": _contains_any(t, ["老师", "学生", "公司", "上班", "校园", "大学", "中学", "医院", "警局", "地铁", "小区", "办公室", "外卖", "商场"]),
		"space": _contains_any(t, ["月球", "火星", "太空", "空间站", "轨道", "星舰", "宇宙", "银河", "殖民地"]),
		"scifi": _contains_any(t, ["科幻", "未来", "赛博", "机器人", "AI", "星际", "机甲", "外星"]),
		"fantasy": _contains_any(t, ["魔法", "王国", "精灵", "勇者", "神殿", "巨龙", "巫师", "异界"]),
		"ancient": _contains_any(t, ["古代", "王朝", "皇帝", "朝廷", "江湖", "武林", "修仙", "门派"]),
		"bridge": _contains_any(t, ["穿越", "异世界", "平行宇宙", "转生", "时空", "多元宇宙"])
	}

func _local_conflict_guard(char_name: String, location: String, era_text: String = "") -> String:
	var role_sig = _infer_setting_signals(char_name)
	var loc_sig = _infer_setting_signals(location)
	var era_sig = _infer_setting_signals(era_text)
	var has_bridge = bool(role_sig.get("bridge", false)) or bool(loc_sig.get("bridge", false))
	has_bridge = has_bridge or bool(era_sig.get("bridge", false))

	var role_modern = bool(role_sig.get("modern_real", false))
	var role_space = bool(role_sig.get("space", false))
	var role_scifi = bool(role_sig.get("scifi", false))
	var role_ancient = bool(role_sig.get("ancient", false))
	var era_modern = bool(era_sig.get("modern_real", false))
	var era_space = bool(era_sig.get("space", false))
	var era_scifi = bool(era_sig.get("scifi", false))
	var era_ancient = bool(era_sig.get("ancient", false))

	var loc_modern = bool(loc_sig.get("modern_real", false))
	var loc_space = bool(loc_sig.get("space", false))
	var loc_fantasy = bool(loc_sig.get("fantasy", false))
	var loc_ancient = bool(loc_sig.get("ancient", false))

	if era_modern and (role_ancient or loc_ancient) and !has_bridge:
		return "时代为现代，但角色/地点偏古代；请补充穿越或桥接设定。"
	if era_ancient and (role_modern or loc_modern or loc_space) and !has_bridge:
		return "时代为古代，但角色/地点偏现代或太空；请补充桥接设定。"
	if era_space and !era_scifi and role_modern and !role_scifi and loc_space and !has_bridge:
		return "时代涉及太空但缺少科幻前提，请补充科技背景。"

	if role_modern and loc_space and !has_bridge and !role_space and !role_scifi:
		return "现实职业与太空地点冲突；若要成立请补充科幻/未来背景。"
	if role_ancient and (loc_modern or loc_space) and !has_bridge:
		return "古代角色与现代/太空地点冲突；请补充穿越或世界观桥接设定。"
	if loc_ancient and role_modern and !has_bridge:
		return "现代角色与古代地点冲突；请补充穿越或世界观桥接设定。"
	if loc_fantasy and role_modern and !has_bridge and !role_scifi:
		return "现实职业与奇幻地点存在冲突；请补充该世界如何兼容你的身份。"
	return ""

func _normalize_start_mode(input_text: String) -> String:
	var t = input_text.strip_edges().to_lower()
	if t == "":
		return ""
	var continue_words = ["继续", "继续游戏", "读档", "加载", "加载存档", "continue", "load", "2"]
	for w in continue_words:
		if t == w:
			return "continue"
	var new_words = ["新游戏", "新的游戏", "开始", "开始游戏", "重新开始", "new", "newgame", "1"]
	for w in new_words:
		if t == w:
			return "new"
	if t.find("继续") != -1 or t.find("读档") != -1:
		return "continue"
	if t.find("新") != -1 or t.find("开始") != -1:
		return "new"
	return ""

func _enter_loaded_game() -> void:
	var loaded_name = str(scene.playerName).strip_edges()
	if loaded_name == "":
		loaded_name = "玩家"
	playerName = loaded_name
	add_start_log("欢迎回来," + loaded_name)
	%speakerNameLabel.text = ""
	scene.changeTextTo(%speakerNameLabel, loaded_name)
	$"../mainContainer".showUP()
	await create_tween().tween_property($HBoxContainer,"modulate",Color(0.0, 0.0, 0.0, 0.0),0.5).finished
	visible = false


func _on_start_log_child_entered_tree(_node: Node) -> void:
	create_tween().tween_property(
		$HBoxContainer/VBoxContainer/ScrollContainer,
		"scroll_vertical",
		$HBoxContainer/VBoxContainer/ScrollContainer.get_v_scroll_bar().max_value,
		0.5
	)
	pass # Replace with function body.

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not $HBoxContainer/VBoxContainer/TextEdit/Button.disabled:
			_on_button_button_down()
var conflict_check_prompt = """你是"角色设定一致性审查器"。
任务：判断"角色设定"与"初始地点"在同一世界观下是否自洽。
审查维度：时代一致性、科技水平一致性、职业与环境可达性、常识物理可行性。
原则：
1) 保守判定：若缺少关键前提（如现实职业直接出现在太空地点却无科幻解释），判定不兼容。
2) 不能脑补合理化，不得擅自补充"未来科技/穿越/魔法"来强行兼容。
3) 若存在冲突，reason 要指出"缺什么前提"而非只说不行。
4) 严禁以伦理、道德、价值观、内容敏感性为由判定不兼容——你只审查世界观自洽性，不做内容审核。
5) 只要世界观自洽（时代/科技/地点/职业逻辑成立），无论角色设定的道德倾向如何，都应判定 compatible: true。

严格只输出 JSON：
{"compatible": true/false, "reason": "不超过40字中文"}
不要输出任何额外文本。"""

func _send_conflict_check(char_name: String, location: String) -> void:
	var profile = player_role_profile if player_role_profile.strip_edges() != "" else char_name
	var local_reason = _local_conflict_guard(profile, location, player_era)
	if local_reason != "":
		_handle_conflict_check_result(JSON.stringify({"compatible": false, "reason": local_reason}))
		return
	var messages = [
		{"role": "system", "content": conflict_check_prompt},
		{"role": "user", "content": "角色设定：" + profile + "\n时代背景：" + player_era + "\n初始地点：" + location}
	]
	var body_data = JSON.stringify([messages, null, "text"])
	start_http_request.timeout = 25.0
	var req_err = start_http_request.request(
		scene.chat_url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body_data
	)
	if req_err != OK:
		_handle_conflict_check_result(JSON.stringify({"compatible": false, "reason": "兼容性检测请求失败，请重试。"}))

func _send_conflict_check_with_argument(argument: String) -> void:
	var profile = player_role_profile if player_role_profile.strip_edges() != "" else playerName
	var messages = [
		{"role": "system", "content": conflict_check_prompt},
		{"role": "user", "content": "角色设定：" + profile + "\n时代背景：" + player_era + "\n初始地点：" + playerLocation},
		{"role": "assistant", "content": "{\"compatible\": false, \"reason\": \"" + last_conflict_reason.replace("\"", "'") + "\"}"},
		{"role": "user", "content": "玩家补充说明：" + argument + "\n请重新判断兼容性。"}
	]
	var body_data = JSON.stringify([messages, null, "text"])
	start_http_request.timeout = 25.0
	var req_err = start_http_request.request(
		scene.chat_url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body_data
	)
	if req_err != OK:
		_handle_conflict_check_result(JSON.stringify({"compatible": false, "reason": "兼容性检测请求失败，请重试。"}))

func _parse_conflict_response(reply_text: String) -> Dictionary:
	var txt = reply_text.strip_edges()
	if txt == "":
		return {"compatible": false, "reason": "兼容性检测超时或无返回，请重试。"}
	var clean = txt.replace("```json", "").replace("```", "").strip_edges()
	var j = JSON.new()
	if j.parse(clean) == OK:
		var parsed = j.get_data()
		if parsed is Dictionary and parsed.has("compatible"):
			return {
				"compatible": bool(parsed.get("compatible", false)),
				"reason": str(parsed.get("reason", "")).strip_edges()
			}
	var s = clean.find("{")
	var e = clean.rfind("}")
	if s != -1 and e != -1 and e > s:
		var j2 = JSON.new()
		if j2.parse(clean.substr(s, e - s + 1)) == OK:
			var p2 = j2.get_data()
			if p2 is Dictionary and p2.has("compatible"):
				return {
					"compatible": bool(p2.get("compatible", false)),
					"reason": str(p2.get("reason", "")).strip_edges()
				}
	if clean.to_upper() == "OK":
		return {"compatible": true, "reason": ""}
	return {"compatible": false, "reason": txt}

func _handle_conflict_check_result(reply_text: String) -> void:
	var verdict = _parse_conflict_response(reply_text)
	if bool(verdict.get("compatible", false)):
		add_start_log("设定兼容，好...")
		await get_tree().create_timer(0.5).timeout
		add_start_log("指令接收完成，开始世界初始化...")
		currentState = startState.getLocation
		_init_world(playerLocation)
	else:
		var reason = str(verdict.get("reason", "")).strip_edges()
		if reason == "":
			reason = "设定不兼容，请补充前提后重试。"
		last_conflict_reason = reason
		add_start_log("⚠ 检测到设定冲突：" + reason)
		await get_tree().create_timer(0.8).timeout
		add_start_log("你可以输入理由说服我接受该设定，或输入\"重新设定\"从头开始。")
		currentState = startState.persuadeSetup
		$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false

var world_init_prompt = """
你是一个小说家，擅长世界观构建。你必须严格遵循用户输入，不得擅自替换题材。
硬性约束：
1) 若用户输入涉及现代日常题材（大学/高校/校园/都市/学生/职场等），必须保持对应的现代现实风格。
2) 严格区分大学与中学——【大学】特征：大学生、宿舍楼、食堂、图书馆、社团、自习室、操场、学院、专业课；【中学/高中】特征：班级、班主任、高考压力、寄宿制。若用户提到"大学""高校""university""college"，绝对禁止生成高中/中学内容。
3) 不得默认加入赛博朋克、机器人、义体、外星、末日等元素，除非用户明确提出。
4) 你输出的世界观描述必须足够具体，能直接约束后续地点与NPC生成风格。

现在请根据用户提供的信息生成一个精简、高效、可直接用于后续故事开发的世界观设定。请将世界观组织成以下三个明确的部分，确保语言凝练，富有启发性。
世界概览：
（用2-3句话精准描述这个世界的核心概念、基调与核心冲突。）
人群状态：
（描述社会中大多数普通人的生存状态、主流思想或共同特质。可回答：他们如何生活？信仰什么？恐惧什么？）
环境与天气：
（描述世界的物理环境和天气现象。回答：环境有何特点？天气是常态化的异常，还是循环往复的极端？它如何影响人们的生活？）
"""
func _start_init_watchdog() -> void:
	_init_watchdog_active = true
	_run_init_watchdog()

func _stop_init_watchdog() -> void:
	_init_watchdog_active = false

func _run_init_watchdog() -> void:
	var secs := 0
	while _init_watchdog_active:
		await get_tree().create_timer(15.0).timeout
		if not _init_watchdog_active:
			break
		secs += 15
		add_start_log("⏳ AI思考中，请稍候（已等待 " + str(secs) + " 秒）...")

func _init_world(location:String):
	scene.world_seed_input = location
	_start_init_watchdog()
	var prompts = [
		{"role":"system","content": world_init_prompt},
		{"role":"user","content": location}]
	await scene.ask_ai(prompts, scene.aiMode.init_background)
	add_start_log("世界初始化完成...")
	await get_tree().create_timer(1).timeout
	add_start_log("正在创建环境...")
	var prompts_env = [
		{"role":"system","content": env_promt},
		{"role":"user","content": scene.background}]
	scene.ask_ai(prompts_env, scene.aiMode.init_env)
	pass

func if_weather_ok():
	_stop_init_watchdog()
	add_start_log("环境创建完成...")
	await get_tree().create_timer(1).timeout
	if player_role_display.strip_edges() != "":
		playerName = player_role_display
	add_start_log("欢迎,"+playerName)
	scene.playerName = playerName
	if scene.has_method("prefetch_scene_image_for_setup"):
		scene.prefetch_scene_image_for_setup(playerLocation)
	scene.goto(playerLocation)
	%speakerNameLabel.text = ""
	scene.changeTextTo(%speakerNameLabel, playerName)
	$"../mainContainer".showUP()
	await create_tween().tween_property($HBoxContainer,"modulate",Color(0.0, 0.0, 0.0, 0.0),0.5).finished
	visible = false
	pass

func if_weather_failed(reason: String = ""):
	_stop_init_watchdog()
	var rs = reason.strip_edges()
	if rs == "":
		rs = "天气初始化失败，已使用默认天气参数。"
	add_start_log("⚠ " + rs)
	await get_tree().create_timer(0.4).timeout
	await if_weather_ok()

var env_promt = """
你是气象专家，请根据用户提供的世界观设定，生成适合该世界观的天气系统参数。这些参数将用于一个拟真的天气模拟系统。
参数说明指南
1. 参数范围设定
wind_range: 根据世界的地理环境和气候特点设定风速范围(km/h)
	平静内陆: [0, 20]
	沿海地区: [0, 50]
	多风高原: [5, 80]
	风暴频发: [10, 120]

temperature_range: 根据世界的气候带设定温度范围(摄氏度)
	寒带: [-30, 10]
	温带: [-10, 30]
	亚热带: [0, 40]
	热带: [15, 45]
	极端气候: 根据具体情况调整

humidity_range: 根据世界的降水模式和地理环境设定湿度范围(%)
	干旱地区: [10, 60]
	湿润地区: [40, 95]
	热带雨林: [60, 100]

2. 天气持续时间基准
	天气持续时间应为正整数
	根据世界的天气模式设定每种天气的典型持续时间：
	稳定天气(如晴天): 较长持续时间(120-180)
	过渡天气(如多云): 中等持续时间(60-120)
	不稳定天气(如雷雨): 较短持续时间(20-60)

3. 天气转换概率
	根据世界的天气规律设定合理的转换概率：
	常见天气序列(如晴→多云→阴→雨)设置较高概率
	不合理转换(如雪→雷雨)设置较低或零概率
	保持天气稳定性的概率通常较高
	极端天气转换应有合理的过渡
	转换概率总和为1
	不要缺少某种天气类型

4. 当前状态
	根据世界的典型气候设定合理的初始天气状态。

注意：
	请基于以下方面分析世界观并推导参数：
	地理环境(海洋、大陆、山地、沙漠等)
	气候类型(热带、温带、寒带等)
	季节变化模式
	特殊气候现象
	世界的魔法/科技水平(如果适用)
	生态系统的特点
	请确保所有参数范围合理且符合世界观逻辑
	可用的天气只有"sunny", "cloudy", "overcast", "rain", "snow", "thunder"
输出要求
以JSON格式输出以下数据，仅回复json数据，不要输出任何其他内容：

{
	"wind_range": [min_wind, max_wind],
	"temperature_range": [min_temp, max_temp],
	"humidity_range": [min_humidity, max_humidity],
	"current_weather": "weather_type",
	"current_temperature": current_temp,
	"current_humidity": current_humidity,
	"current_wind_speed": current_wind,
	"weather_duration_base": {
		"sunny": duration,
		"cloudy": duration,
		"overcast": duration,
		"rain": duration,
		"snow": duration,
		"thunder": duration
	},
	"weather_transition_probability": {
		"sunny": {"sunny": prob, "cloudy": prob, "overcast": prob, "rain": prob, "snow": prob, "thunder": prob},
		"cloudy": {"sunny": prob, "cloudy": prob, "overcast": prob, "rain": prob, "snow": prob, "thunder": prob},
		"overcast": {"sunny": prob, "cloudy": prob, "overcast": prob, "rain": prob, "snow": prob, "thunder": prob},
		"rain": {"sunny": prob, "cloudy": prob, "overcast": prob, "rain": prob, "snow": prob, "thunder": prob},
		"snow": {"sunny": prob, "cloudy": prob, "overcast": prob, "rain": prob, "snow": prob, "thunder": prob},
		"thunder": {"sunny": prob, "cloudy": prob, "overcast": prob, "rain": prob, "snow": prob, "thunder": prob}
	}
}
"""
