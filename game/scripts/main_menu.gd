extends CanvasLayer
const GamePrompts = preload("res://scripts/game_prompts.gd")
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
	add_start_log("正在启动 DeepSeek API 桥接...")
	var services_ok = await scene.ensure_deepseek_service_ready()
	if !services_ok:
		add_start_log("⚠ DeepSeek API 桥接启动失败：" + str(scene.get_node("DeepSeekService").get_startup_message()))
		$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
		return
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
	if response.has("error"):
		# 例如 “Connection error.”：让玩家和日志都能看到真正的失败原因，
		# 而不是只有一个“神经网络检查失败”。
		var service_error = str(response["error"]).strip_edges()
		if service_error != "":
			check_text += "（" + service_error.left(120) + "）"
			print("服务错误: ", service_error)
	add_start_log(check_text)
	if response.has("debug_report"):
		var debug_log = load("res://fabs/log_rich_text_label.tscn").instantiate() as RichTextLabel
		debug_log.text = "【连接调试】\n文件：" + str(response.get("debug_file", "")) + "\n" + str(response["debug_report"])
		%startLog.add_child(debug_log)
		debug_log.visible_ratio = 1.0
		debug_log.set("expanded", true)
		debug_log.set_process(false)
		print(debug_log.text)

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
				scene.clear_dialogue_history()
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

func _send_conflict_check(char_name: String, location: String) -> void:
	var profile = player_role_profile if player_role_profile.strip_edges() != "" else char_name
	var local_reason = _local_conflict_guard(profile, location, player_era)
	if local_reason != "":
		_handle_conflict_check_result(JSON.stringify({"compatible": false, "reason": local_reason}))
		return
	var messages = [
		{"role": "system", "content": GamePrompts.CONFLICT_CHECK_PROMPT},
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
		{"role": "system", "content": GamePrompts.CONFLICT_CHECK_PROMPT},
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
	scene.clear_dialogue_history()
	scene.world_seed_input = location
	_start_init_watchdog()
	var prompts = [
		{"role":"system","content": GamePrompts.WORLD_INIT_PROMPT},
		{"role":"user","content": location}]
	await scene.ask_ai(prompts, scene.aiMode.init_background)
	add_start_log("世界初始化完成...")
	await get_tree().create_timer(1).timeout
	add_start_log("正在创建环境...")
	var prompts_env = [
		{"role":"system","content": GamePrompts.ENVIRONMENT_INIT_PROMPT},
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
