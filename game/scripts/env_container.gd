extends HBoxContainer
class_name envManager
var nowTimeText:String
var scene:GameManager

func _ready() -> void:
	scene = owner

var timer = 0
func _process(delta: float) -> void:
	timer+=delta
	if timer>= 1:
		$site_buttons/timeDis/timeDot.visible = !$site_buttons/timeDis/timeDot.visible
		timer = 0
		_time_update(0.2)

func _time_update(timeToAdd:float):
	var rec = scene.advance_time_minutes(timeToAdd)
	$site_buttons/timeDis.text = minutes_to_time(scene.nowtime)
	if float(rec.get("hours", 0.0)) >= 1.0:
		scene.addLog("<时间流逝，体力与健康缓慢恢复。>")
	update_weather_system()

func minutes_to_time(minutes: int) -> String:
	# 处理负数情况
	if minutes < 0:
		minutes = 0

	# 计算小时和分钟
	var total_hours = int(floor(float(minutes) / 60.0))
	var hours = total_hours % 24
	var mins = minutes % 60
	scene.timePrompt = "当前时间：%02d:%02d" % [hours, mins]
	# 格式化为两位数字
	return "%02d %02d" % [hours, mins]

# 天气参数范围
var wind_range = Vector2(0, 50)  # km/h
var temperature_range = Vector2(-10, 35)  # 摄氏度
var humidity_range = Vector2(20, 100)  # 百分比

# 当前天气状态
var current_weather = "sunny"
var current_temperature = 20.0
var current_humidity = 50.0
var current_wind_speed = 5.0

# 天气持续时间
var weather_duration = 0
var next_change_time = 0

# 天气转换概率矩阵（基于当前天气）
var weather_transition_probability = {
	"sunny": {"sunny": 0.6, "cloudy": 0.3, "overcast": 0.1, "rain": 0.0, "snow": 0.0, "thunder": 0.0},
	"cloudy": {"sunny": 0.2, "cloudy": 0.4, "overcast": 0.3, "rain": 0.1, "snow": 0.0, "thunder": 0.0},
	"overcast": {"sunny": 0.1, "cloudy": 0.2, "overcast": 0.3, "rain": 0.3, "snow": 0.1, "thunder": 0.0},
	"rain": {"sunny": 0.1, "cloudy": 0.2, "overcast": 0.3, "rain": 0.3, "snow": 0.0, "thunder": 0.1},
	"snow": {"sunny": 0.1, "cloudy": 0.2, "overcast": 0.3, "rain": 0.0, "snow": 0.3, "thunder": 0.1},
	"thunder": {"sunny": 0.05, "cloudy": 0.1, "overcast": 0.2, "rain": 0.4, "snow": 0.0, "thunder": 0.25}
}

# 天气对参数的影响系数
var weather_effects = {
	"sunny": {"temp_factor": 1.2, "humidity_factor": 0.7, "wind_factor": 0.8},
	"cloudy": {"temp_factor": 1.0, "humidity_factor": 0.9, "wind_factor": 1.0},
	"overcast": {"temp_factor": 0.9, "humidity_factor": 1.1, "wind_factor": 1.1},
	"rain": {"temp_factor": 0.8, "humidity_factor": 1.3, "wind_factor": 1.3},
	"snow": {"temp_factor": 0.6, "humidity_factor": 1.1, "wind_factor": 1.2},
	"thunder": {"temp_factor": 0.9, "humidity_factor": 1.4, "wind_factor": 1.5}
}

# 天气持续时间的基准和随机范围
var weather_duration_base = {
	"sunny": 120,
	"cloudy": 90,
	"overcast": 60,
	"rain": 45,
	"snow": 60,
	"thunder": 30
}


func initialize_weather():
	update_weather_parameters()
	# 设置第一次天气变化时间
	next_change_time = scene.nowtime + calculate_weather_duration(current_weather)
	print("初始天气: ", current_weather)

func _on_weather_update_timeout():
	update_weather_system()
	get_tree().create_timer(10.0).timeout.connect(_on_weather_update_timeout)

func update_weather_system():
	# 检查是否该改变天气
	if scene.nowtime >= next_change_time:
		change_weather()
		next_change_time = scene.nowtime + calculate_weather_duration(current_weather)
	# 更新天气参数（微小变化）
	update_weather_parameters_smooth()
	# 输出当前状态（调试用）

func change_weather():
	var new_weather = get_next_weather()
	print("天气从 ", current_weather, " 变为 ", new_weather)
	current_weather = new_weather
	weather_duration = 0
	update_dis()

func calculate_weather_duration(weather_type):
	var base_duration = weather_duration_base[weather_type]
	# 添加随机性，±50%的变化
	var random_variation = base_duration * 0.5
	return base_duration + randf_range(-random_variation, random_variation)

func get_next_weather():
	var probabilities = weather_transition_probability[current_weather]
	var rand_val = randf()
	var cumulative = 0.0

	for weather in probabilities:
		if weather_duration_base[weather] == 0:
			continue
		cumulative += probabilities[weather]
		if rand_val <= cumulative:
			return weather
	return "sunny"  # 默认回退

func update_weather_parameters():
	var effects = weather_effects[current_weather]

	# 基础值加随机变化
	var base_temp = (temperature_range.x + temperature_range.y) / 2.0
	current_temperature = base_temp * effects.temp_factor
	current_temperature += randf_range(-3.0, 3.0)  # 随机波动

	# 限制在合理范围内
	current_temperature = clamp(current_temperature, temperature_range.x, temperature_range.y)

	var base_humidity = (humidity_range.x + humidity_range.y) / 2.0
	current_humidity = base_humidity * effects.humidity_factor
	current_humidity += randf_range(-5.0, 5.0)
	current_humidity = clamp(current_humidity, humidity_range.x, humidity_range.y)

	var base_wind = (wind_range.x + wind_range.y) / 2.0
	current_wind_speed = base_wind * effects.wind_factor
	current_wind_speed += randf_range(-2.0, 2.0)
	current_wind_speed = clamp(current_wind_speed, wind_range.x, wind_range.y)

func update_weather_parameters_smooth():
	# 平滑过渡参数变化
	var effects = weather_effects[current_weather]

	# 目标值
	var target_temp = ((temperature_range.x + temperature_range.y) / 2.0) * effects.temp_factor
	var target_humidity = ((humidity_range.x + humidity_range.y) / 2.0) * effects.humidity_factor
	var target_wind = ((wind_range.x + wind_range.y) / 2.0) * effects.wind_factor

	# 平滑过渡（使用lerp）
	current_temperature = lerp(current_temperature, target_temp, 0.1)
	current_humidity = lerp(current_humidity, target_humidity, 0.1)
	current_wind_speed = lerp(current_wind_speed, target_wind, 0.1)

	# 添加微小随机波动
	current_temperature += randf_range(-0.5, 0.5)
	current_humidity += randf_range(-1.0, 1.0)
	current_wind_speed += randf_range(-0.5, 0.5)

	# 限制在合理范围内
	current_temperature = clamp(current_temperature, temperature_range.x, temperature_range.y)
	current_humidity = clamp(current_humidity, humidity_range.x, humidity_range.y)
	current_wind_speed = clamp(current_wind_speed, wind_range.x, wind_range.y)


var weatherDic = {
	"sunny": "晴天",
	"cloudy": "多云",
	"overcast": "阴天",
	"rain": "下雨",
	"snow": "下雪",
	"thunder": "雷雨"
}

# 获取当前天气信息的函数，供其他系统调用
func get_current_weather():
	return {
		"weather": current_weather,
		"temperature": current_temperature,
		"humidity": current_humidity,
		"wind_speed": current_wind_speed
	}

# 手动设置天气（用于测试或特殊事件）
func set_weather(weather_type: String, duration: int = -1):
	if weather_type in weather_effects:
		current_weather = weather_type
		if duration > 0:
			next_change_time = scene.nowtime + duration
		update_weather_parameters()
		print("手动设置天气为: ", weather_type)

# 在Godot中使用示例



# 函数用于接收并验证天气配置JSON，然后赋值给系统
func load_weather_config_from_json(json_data: Dictionary) -> bool:
	"""
	从JSON数据加载天气配置

	参数:
		json_data: 包含天气配置的字典

	返回:
		bool: 配置是否成功加载
	"""

	# 必需字段列表
	var required_fields = [
		"wind_range", "temperature_range", "humidity_range",
		"current_weather", "current_temperature", "current_humidity", "current_wind_speed",
		"weather_duration_base", "weather_transition_probability"
	]

	# 检查必需字段是否存在
	for field in required_fields:
		if not json_data.has(field):
			push_error("天气配置缺少必需字段: " + field)
			return false

	# 验证并转换wind_range
	if not _validate_and_assign_range(json_data["wind_range"], "wind_range", wind_range):
		return false

	# 验证并转换temperature_range
	if not _validate_and_assign_range(json_data["temperature_range"], "temperature_range", temperature_range):
		return false

	# 验证并转换humidity_range
	if not _validate_and_assign_range(json_data["humidity_range"], "humidity_range", humidity_range):
		return false

	# 验证当前天气参数
	if not _validate_current_weather_params(json_data):
		return false

	# 验证天气持续时间
	if not _validate_weather_durations(json_data["weather_duration_base"]):
		return false

	# 验证天气转换概率
	if not _validate_transition_probabilities(json_data["weather_transition_probability"]):
		return false

	# 所有验证通过，开始赋值
	_assign_weather_config(json_data)
	update_dis()
	print("天气配置成功加载!")
	return true

# 辅助函数：验证和分配范围数据
func _validate_and_assign_range(range_data, field_name: String, _target_range) -> bool:
	if not (range_data is Array and range_data.size() == 2):
		push_error(field_name + " 格式错误，应为包含2个数值的数组")
		return false

	if range_data[0] >= range_data[1]:
		push_error(field_name + " 范围无效，最小值应小于最大值")
		return false

	# 创建Vector2范围（由调用方自行赋值）
	var _range = Vector2(range_data[0], range_data[1])
	return true

# 辅助函数：验证当前天气参数
func _validate_current_weather_params(json_data: Dictionary) -> bool:
	var current_weathercc = json_data["current_weather"]
	var valid_weather_types = ["sunny", "cloudy", "overcast", "rain", "snow", "thunder"]

	if not valid_weather_types.has(current_weathercc):
		push_error("无效的天气类型: " + current_weathercc)
		return false

	# 检查当前参数是否在合理范围内
	var temp = json_data["current_temperature"]
	var humidity = json_data["current_humidity"]
	var wind = json_data["current_wind_speed"]

	if not (temp is float or temp is int):
		push_error("当前温度应为数值类型")
		return false

	if not (humidity is float or humidity is int):
		push_error("当前湿度应为数值类型")
		return false

	if not (wind is float or wind is int):
		push_error("当前风速应为数值类型")
		return false

	return true

# 辅助函数：验证天气持续时间
func _validate_weather_durations(durations: Dictionary) -> bool:
	var required_weather_types = ["sunny", "cloudy", "overcast", "rain", "snow", "thunder"]

	for weather_type in required_weather_types:
		if not durations.has(weather_type):
			push_error("天气持续时间缺少类型: " + weather_type)
			return false

		#var duration = int(durations[weather_type])
		#if not (duration is int and duration > 0):
			#push_error("天气持续时间应为正整数: " + weather_type,duration)
			#return false

	return true

# 辅助函数：验证天气转换概率
func _validate_transition_probabilities(probabilities: Dictionary) -> bool:
	var required_weather_types = ["sunny", "cloudy", "overcast", "rain", "snow", "thunder"]

	# 检查所有源天气类型
	for source_weather in required_weather_types:
		if not probabilities.has(source_weather):
			push_error("转换概率缺少源天气类型: " + source_weather)
			return false

		var source_probs = probabilities[source_weather]

		# 检查所有目标天气类型
		for target_weather in required_weather_types:
			if not source_probs.has(target_weather):
				push_error("转换概率缺少目标天气类型: " + target_weather + " 对于源天气: " + source_weather)
				return false

			var prob = source_probs[target_weather]
			if not (prob is float or prob is int):
				push_error("概率值应为数值类型: " + source_weather + " -> " + target_weather)
				return false

			if prob < 0 or prob > 1:
				push_error("概率值应在0-1之间: " + source_weather + " -> " + target_weather)
				return false

		# 检查概率总和是否为1（允许小的浮点误差）
		var total_prob = 0.0
		for target_weather in required_weather_types:
			total_prob += source_probs[target_weather]

		if abs(total_prob - 1.0) > 0.001:
			if abs(total_prob)> 0.001:

				push_error("转换概率总和不为1,也不是0: " + source_weather + " (总和: " + str(total_prob) + ")")
				return false

	return true

# 辅助函数：执行实际的配置赋值
func _assign_weather_config(json_data: Dictionary):
	# 赋值范围参数
	wind_range = Vector2(json_data["wind_range"][0], json_data["wind_range"][1])
	temperature_range = Vector2(json_data["temperature_range"][0], json_data["temperature_range"][1])
	humidity_range = Vector2(json_data["humidity_range"][0], json_data["humidity_range"][1])

	# 赋值当前天气状态
	current_weather = json_data["current_weather"]
	current_temperature = float(json_data["current_temperature"])
	current_humidity = float(json_data["current_humidity"])
	current_wind_speed = float(json_data["current_wind_speed"])

	# 赋值天气持续时间
	weather_duration_base = json_data["weather_duration_base"].duplicate()

	# 赋值天气转换概率
	weather_transition_probability = json_data["weather_transition_probability"].duplicate()

	# 重置天气计时器
	weather_duration = 0
	next_change_time = scene.nowtime + calculate_weather_duration(current_weather)

func update_dis():
	scene.weatherPrompt = "当前天气："+("%s，温度%.0f°C ， 湿度%.0f%% ， 室外风力%.0fkm/h" % [weatherDic[current_weather], current_temperature, current_humidity, current_wind_speed])
	scene.changeTextTo($site_buttons/weatherLable,("%s\n%.0f°C | %.0f%% | %.0fkm/h" % [weatherDic[current_weather], current_temperature, current_humidity, current_wind_speed]))
	scene.changeTextTo($Control/weatherLable,$Control/weatherLable.weathers[current_weather])
# 使用示例函数
func load_weather_from_json_string(json_string: String) -> bool:
	"""
	从JSON字符串加载天气配置
	参数:
		json_string: JSON格式的字符串
	返回:
		bool: 配置是否成功加载
	"""
	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_error("JSON解析错误: " + json.get_error_message())
		return false

	var json_data = json.get_data()

	if json_data is Dictionary:
		return load_weather_config_from_json(json_data)
	else:
		push_error("JSON数据不是有效的字典格式")
		return false

# 测试函数
func test_weather_config_loading():
	# 示例JSON数据（用于测试）
	var test_json = {
		"wind_range": [0, 60],
		"temperature_range": [-5, 30],
		"humidity_range": [25, 95],
		"current_weather": "cloudy",
		"current_temperature": 18.5,
		"current_humidity": 65.0,
		"current_wind_speed": 12.0,
		"weather_duration_base": {
			"sunny": 150,
			"cloudy": 100,
			"overcast": 70,
			"rain": 50,
			"snow": 80,
			"thunder": 25
		},
		"weather_transition_probability": {
			"sunny": {"sunny": 0.5, "cloudy": 0.3, "overcast": 0.15, "rain": 0.05, "snow": 0.0, "thunder": 0.0},
			"cloudy": {"sunny": 0.2, "cloudy": 0.4, "overcast": 0.25, "rain": 0.15, "snow": 0.0, "thunder": 0.0},
			"overcast": {"sunny": 0.1, "cloudy": 0.2, "overcast": 0.3, "rain": 0.35, "snow": 0.05, "thunder": 0.0},
			"rain": {"sunny": 0.05, "cloudy": 0.15, "overcast": 0.25, "rain": 0.4, "snow": 0.0, "thunder": 0.15},
			"snow": {"sunny": 0.05, "cloudy": 0.15, "overcast": 0.25, "rain": 0.0, "snow": 0.5, "thunder": 0.05},
			"thunder": {"sunny": 0.0, "cloudy": 0.1, "overcast": 0.2, "rain": 0.5, "snow": 0.0, "thunder": 0.2}
		}
	}

	if load_weather_config_from_json(test_json):
		print("测试配置加载成功!")
	else:
		print("测试配置加载失败!")
