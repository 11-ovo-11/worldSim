extends CanvasLayer
enum startState {getName,getLocation}
var currentState = startState.getName
var scene :GameManager
var playerName:String
var playerLocation:String
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
	add_start_log("你是谁？")
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
		startState.getName:
			playerName = $HBoxContainer/VBoxContainer/TextEdit.text
			$HBoxContainer/VBoxContainer/TextEdit.text = ""
			currentState = startState.getLocation
			$HBoxContainer/VBoxContainer/TextEdit/Button.button_pressed = false
			$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = true
			await add_start_log(playerName,true)
			await get_tree().create_timer(1).timeout
			add_start_log("好...")
			await get_tree().create_timer(1).timeout
			add_start_log("...")
			await get_tree().create_timer(1).timeout
			add_start_log("那么，你要到哪里去呢？")
			$HBoxContainer/VBoxContainer/TextEdit/Button.disabled = false
		startState.getLocation:
			playerLocation = $HBoxContainer/VBoxContainer/TextEdit.text
			$HBoxContainer/VBoxContainer/TextEdit.text = ""
			_init_world(playerLocation)
			await add_start_log(playerLocation,true)
			await get_tree().create_timer(1).timeout
			add_start_log("好...")
			await get_tree().create_timer(1).timeout
			add_start_log("指令接收完成，开始世界初始化...")

	pass # Replace with function body.


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
var world_init_prompt = """
你是一个小说家，擅长世界观构建，现在需要你根据用户提供的信息生成一个精简、高效、可直接用于后续故事开发的世界观设定。请将世界观组织成以下三个明确的部分，确保语言凝练，富有启发性。
世界概览：
（用2-3句话精准描述这个世界的核心概念、基调与核心冲突。）
人群状态：
（描述社会中大多数普通人的生存状态、主流思想或共同特质。可回答：他们如何生活？信仰什么？恐惧什么？）
环境与天气：
（描述世界的物理环境和天气现象。回答：环境有何特点？天气是常态化的异常，还是循环往复的极端？它如何影响人们的生活？）
"""
func _init_world(location:String):
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
	add_start_log("环境创建完成...")
	await get_tree().create_timer(1).timeout
	add_start_log("欢迎,"+playerName)
	scene.playerName = playerName
	scene.goto(playerLocation)
	%speakerNameLabel.text = ""
	scene.changeTextTo(%speakerNameLabel, playerName)
	$"../mainContainer".showUP()
	await create_tween().tween_property($HBoxContainer,"modulate",Color(0.0, 0.0, 0.0, 0.0),0.5).finished
	visible = false
	pass

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
