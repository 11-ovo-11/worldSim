extends Node
class_name DeepSeekServiceManager

signal startup_finished(ok: bool, message: String)

const WORLDSIM_URL := "http://127.0.0.1:5000/health"
const STARTUP_WAIT_SECONDS := 45.0

var _startup_started := false
var _startup_finished := false
var _startup_ok := false
var _startup_message := ""
var _started_processes: Array[int] = []

func ensure_ready() -> bool:
	if _startup_finished:
		return _startup_ok
	if _startup_started:
		while !_startup_finished:
			await get_tree().process_frame
		return _startup_ok
	_startup_started = true
	OS.set_environment("WORLD_SIM_CHAT_MODE", "openai")
	OS.set_environment("WORLD_SIM_API_BASE_URL", "https://api.deepseek.com")
	if await _endpoint_ok(WORLDSIM_URL):
		return _finish(true, "DeepSeek API 桥接已就绪")
	_start_worldsim_api()
	if await _wait_for_endpoint(WORLDSIM_URL, STARTUP_WAIT_SECONDS):
		return _finish(true, "DeepSeek API 桥接已就绪")
	return _finish(false, "chat.py 启动超时，请检查 Python 环境或 key.py")

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

func _endpoint_ok(url: String) -> bool:
	var request := HTTPRequest.new()
	request.timeout = 3.0
	add_child(request)
	var err := request.request(url)
	if err != OK:
		request.queue_free()
		return false
	var result = await request.request_completed
	request.queue_free()
	return int(result[0]) == HTTPRequest.RESULT_SUCCESS and int(result[1]) == 200

func _wait_for_endpoint(url: String, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if await _endpoint_ok(url):
			return true
		await get_tree().create_timer(0.5).timeout
	return false

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
