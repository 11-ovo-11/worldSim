extends Node
class_name DeepSeekServiceManager

signal startup_finished(ok: bool, message: String)

const WORLDSIM_URL := "http://127.0.0.1:5000/health"
const STARTUP_WAIT_SECONDS := 45.0
# 必须与 chat.py 里的 BRIDGE_PROTOCOL 保持一致。
# 应答的协议号低于该值，说明 5000 端口上跑的是旧版 chat.py（没有自我标识），
# 这类残留进程会让游戏请求打到错误的进程上并显示“服务器错误”。
const REQUIRED_BRIDGE_PROTOCOL := 3
const MAX_BRIDGE_PURGE_ROUNDS := 5
const PURGE_WAIT_SECONDS := 3.0
const PROBE_TIMEOUT_SECONDS := 3.0

var _startup_started := false
var _startup_finished := false
var _startup_ok := false
var _startup_message := ""
var _started_processes: Array[int] = []
var _probe_request: HTTPRequest = null

func ensure_ready() -> bool:
	if _startup_finished:
		return _startup_ok
	if _startup_started:
		while !_startup_finished:
			await get_tree().process_frame
		return _startup_ok
	_startup_started = true
	OS.set_environment("WORLD_SIM_CHAT_MODE", "openai")
	var api_base = OS.get_environment("WORLD_SIM_API_BASE_URL").strip_edges()
	if api_base == "":
		api_base = "https://api.deepseek.com"
	OS.set_environment("WORLD_SIM_API_BASE_URL", api_base)
	# 已经有一个“当前版本”的桥接在跑（例如玩家自己在终端里启动的 chat.py）就直接复用。
	var health = await _probe_health()
	if _bridge_is_usable(health):
		return _finish(true, _ready_message(health))
	# 端口上有旧版或模式不符的残留桥接：先结束它们，再启动自己的。
	var removed := await _purge_unusable_bridges()
	if removed > 0:
		print("[DEEPSEEK] 已结束 ", removed, " 个过期或重复的本地桥接进程")
	# 清理过程中如果冒出一个可用的桥接（例如玩家刚好手动启动了当前版本），就直接复用。
	var recheck = await _probe_health()
	if _bridge_is_usable(recheck):
		return _finish(true, _ready_message(recheck))
	_start_worldsim_api()
	if !await _wait_for_own_bridge(STARTUP_WAIT_SECONDS):
		var late = await _probe_health()
		if bool(late.get("ok", false)):
			var late_pid := _health_pid(late)
			var late_label := str(late_pid) if late_pid > 0 else "未知"
			return _finish(false, "端口 5000 被其它程序占用（pid=" + late_label + "），请关闭后重启游戏")
		return _finish(false, "chat.py 启动超时，请检查 Python 环境或 key.py")
	# 确认应答 /health 的只有我们刚启动的进程：Windows 允许两个 chat.py 同时监听
	# 同一端口，残留的那个会让一部分请求返回 5xx。
	var conflict := 0
	for _round in range(MAX_BRIDGE_PURGE_ROUNDS):
		conflict = await _find_conflicting_bridge()
		if conflict <= 0:
			break
		print("[DEEPSEEK] 端口 5000 上还有另一个桥接进程 pid=", conflict, "，正在结束它")
		OS.kill(conflict)
		await get_tree().create_timer(0.6).timeout
	if conflict > 0:
		return _finish(false, "端口 5000 上存在多个 chat.py 进程（pid=" + str(conflict) + "），请手动关闭后重启游戏")
	if !await _wait_for_own_bridge(5.0):
		return _finish(false, "端口 5000 上的桥接进程未能稳定应答，请手动关闭后重试")
	return _finish(true, _ready_message(await _probe_health()))

func get_startup_message() -> String:
	return _startup_message

func _start_worldsim_api() -> void:
	var worldsim_dir := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var python := worldsim_dir.path_join(".venv/Scripts/python.exe")
	var script := worldsim_dir.path_join("chat.py")
	if !FileAccess.file_exists(python):
		python = "python"
	if !FileAccess.file_exists(script):
		print("[DEEPSEEK] chat.py 不存在: ", script)
		return
	var pid := OS.create_process(python, PackedStringArray([script]), false)
	if pid > 0:
		_started_processes.append(pid)
	print("[DEEPSEEK] chat.py process=", pid)

func _probe_health() -> Dictionary:
	# 复用同一个 HTTPRequest 节点：探测很频繁，反复创建/释放节点既浪费，
	# 也会在信号回调里释放对象而触发引擎报错。
	if _probe_request == null:
		_probe_request = HTTPRequest.new()
		_probe_request.timeout = PROBE_TIMEOUT_SECONDS
		add_child(_probe_request)
	var request := _probe_request
	if request.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
		await request.request_completed
	var err := request.request(WORLDSIM_URL)
	if err != OK:
		return {"ok": false, "code": 0, "data": {}, "raw": ""}
	var result = await request.request_completed
	var code := int(result[1])
	var raw := ""
	if result[3] is PackedByteArray:
		raw = (result[3] as PackedByteArray).get_string_from_utf8()
	var data = {}
	var trimmed := raw.strip_edges()
	if trimmed != "":
		var parser := JSON.new()
		if parser.parse(trimmed) == OK and parser.get_data() is Dictionary:
			data = parser.get_data()
	var ok := int(result[0]) == HTTPRequest.RESULT_SUCCESS and code == 200
	return {"ok": ok, "code": code, "data": data, "raw": raw}

func _bridge_is_usable(health: Dictionary) -> bool:
	if !bool(health.get("ok", false)):
		return false
	var data = health.get("data", {})
	if !(data is Dictionary):
		return false
	var dict := data as Dictionary
	if dict.is_empty():
		return false
	if int(dict.get("protocol", 0)) < REQUIRED_BRIDGE_PROTOCOL:
		return false
	return str(dict.get("chat_mode", "")).strip_edges().to_lower() == "openai"

func _health_pid(health: Dictionary) -> int:
	var data = health.get("data", {})
	if data is Dictionary:
		return int((data as Dictionary).get("pid", 0))
	return 0

func _health_ppid(health: Dictionary) -> int:
	var data = health.get("data", {})
	if data is Dictionary:
		return int((data as Dictionary).get("ppid", 0))
	return 0

# Windows 上 .venv/Scripts/python.exe 只是个启动器，真正跑 chat.py 的是它派生出来的
# 子进程，所以 /health 报的 pid 和我们 create_process 拿到的启动器 pid 不一致：
# 只要 pid 或 ppid 落在我们自己启动的进程里，就算“这是我们的桥接”。
func _is_own_bridge(health: Dictionary) -> bool:
	if _started_processes.has(_health_pid(health)):
		return true
	var ppid := _health_ppid(health)
	return ppid > 0 and _started_processes.has(ppid)

func _purge_unusable_bridges() -> int:
	var removed := 0
	for _round in range(MAX_BRIDGE_PURGE_ROUNDS):
		var health = await _probe_health()
		if !bool(health.get("ok", false)):
			return removed
		if _bridge_is_usable(health):
			# 第一次探测可能只是瞬时失败；这里发现可用桥接就停手，交给上层复用。
			return removed
		var pid := _health_pid(health)
		if pid <= 0:
			print("[DEEPSEEK] 5000 端口被非本项目的服务占用，无法自动清理")
			return removed
		var data = health.get("data", {})
		var protocol := 0
		var mode := ""
		if data is Dictionary:
			protocol = int((data as Dictionary).get("protocol", 0))
			mode = str((data as Dictionary).get("chat_mode", ""))
		print("[DEEPSEEK] 结束过期或重复的本地桥接 pid=", pid, " protocol=", protocol, " chat_mode=", mode)
		OS.kill(pid)
		removed += 1
		if !await _wait_for_port_free(PURGE_WAIT_SECONDS):
			print("[DEEPSEEK] 桥接 pid=", pid, " 未能在限定时间内释放端口")
			return removed
	return removed

func _wait_for_port_free(timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var health = await _probe_health()
		if !bool(health.get("ok", false)):
			return true
		await get_tree().create_timer(0.25).timeout
	return false

func _wait_for_own_bridge(timeout_seconds: float) -> bool:
	if _started_processes.is_empty():
		return false
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var health = await _probe_health()
		if _bridge_is_usable(health) and _is_own_bridge(health):
			return true
		if !_has_live_started_process():
			return false
		await get_tree().create_timer(0.5).timeout
	return false

func _find_conflicting_bridge(attempts: int = 3) -> int:
	for i in range(attempts):
		var health = await _probe_health()
		var pid := _health_pid(health)
		if pid > 0 and !_is_own_bridge(health):
			return pid
		if i < attempts - 1:
			await get_tree().create_timer(0.3).timeout
	return 0

func _has_live_started_process() -> bool:
	for pid in _started_processes:
		if pid > 0 and OS.is_process_running(pid):
			return true
	return false

func _ready_message(health: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("pid=" + str(_health_pid(health)))
	var data = health.get("data", {})
	if data is Dictionary:
		var dict := data as Dictionary
		var model := str(dict.get("model", "")).strip_edges()
		if model != "":
			parts.append("model=" + model)
		var endpoint := str(dict.get("api_base_url", "")).strip_edges()
		if endpoint != "":
			parts.append("端点=" + endpoint)
	return "DeepSeek API 桥接已就绪（" + "，".join(parts) + "）"

func _finish(ok: bool, message: String) -> bool:
	_startup_finished = true
	_startup_ok = ok
	_startup_message = message
	startup_finished.emit(ok, message)
	print("[DEEPSEEK] ", message)
	return ok

func _exit_tree() -> void:
	for pid in _started_processes:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_started_processes.clear()
