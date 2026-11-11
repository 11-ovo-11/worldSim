extends SceneTree

const Service = preload("res://scripts/instant_background_service.gd")
const Storage = preload("res://scripts/game_storage_utils.gd")
const ImageUtils = preload("res://scripts/game_image_utils.gd")

class Fixture extends Node:
	var currentSiteName := "测试图书馆"
	var instant_gen_mode := false
	var timePrompt := "下午"
	var weatherPrompt := "晴"
	var instant_background_url := "http://127.0.0.1:18769/generate_instant_background"
	var instant_background_status_label: Label
	var siteImgs: Dictionary = {}
	var npcImgs: Dictionary = {}
	var npcs: Dictionary = {}
	var currentNpc: Node = null
	var NPC_IMG_DIR := ""
	var logs: Array = []
	var debug_records: Array = []
	var showing_debug := false
	var usage_text := ""
	var SCENE_IMG_DIR := ""
	var save_file := ""
	var save_scenes := ""
	var active_fingerprint := ""
	func _get_site_data(_site: String) -> Dictionary:
		return {"地点描述": "书架与木桌"}
	func process_display_string(text: String) -> String:
		return text
	func _load_image_png(_dir: String, _name: String) -> Texture2D:
		return null
	func _save_image_png(image: Image, directory: String, site: String) -> void:
		Storage.save_image_png(image, directory, site)
	func persist_instant_background_to_active_save(image: Image, site: String) -> void:
		Storage.persist_generated_background(image, site, save_file, save_scenes, active_fingerprint)
	func addLog(text: String) -> void:
		logs.append(text)
	func add_debug(category: String, message: String) -> void:
		debug_records.append(category + ":" + message)
	func show_image_usage(text: String) -> void:
		usage_text = text

var fixture: Fixture
var service: Node
var folder: String

func _init() -> void:
	call_deferred("run_checks")

func wait_idle() -> void:
	var deadline = Time.get_ticks_msec() + 5000
	while not service._active.is_empty() or not service._pending.is_empty():
		assert(Time.get_ticks_msec() < deadline, "test image request did not finish")
		await process_frame

func run_checks() -> void:
	folder = "user://instant_background_check_" + str(Time.get_ticks_usec())
	fixture = Fixture.new()
	fixture.SCENE_IMG_DIR = folder.path_join("session/")
	fixture.save_file = folder.path_join("slot/save.json")
	fixture.save_scenes = folder.path_join("slot/resources/scenes/")
	if not OS.get_environment("WORLD_SIM_TEST_IMAGE_URL").is_empty():
		fixture.instant_background_url = OS.get_environment("WORLD_SIM_TEST_IMAGE_URL")
	root.add_child(fixture)
	var background = TextureRect.new()
	background.name = "backgroundImg"
	fixture.add_child(background)
	background.owner = fixture
	background.unique_name_in_owner = true
	fixture.instant_background_status_label = Label.new()
	fixture.add_child(fixture.instant_background_status_label)
	service = Service.new()
	fixture.add_child(service)
	service.configure(fixture)
	# Bind active and mentioned NPC portraits; missing portraits are skipped.
	var actor = preload("res://scripts/npc.gd").new()
	actor.npcName = "测试人物"
	fixture.currentNpc = actor
	fixture.npcs = {"测试人物": {}, "另一人物": {}, "缺少立绘": {}}
	var portrait = Image.create_empty(32, 64, false, Image.FORMAT_RGB8)
	portrait.fill(Color.BLUE)
	fixture.npcImgs["测试人物"] = ImageTexture.create_from_image(portrait)
	fixture.npcImgs["另一人物"] = ImageTexture.create_from_image(portrait)
	var references = service.collect_portrait_references("另一人物和缺少立绘在图书馆")
	assert(references.size() == 2)
	assert(references[0]["name"] == "测试人物")
	assert(references[1]["name"] == "另一人物")
	assert(ImageUtils.base64_to_image(references[0]["image"]).get_size() == Vector2i(32, 64))
	var turn = {"input": "另一人物在窗边双手递茶", "kind": "行动", "npc": "测试人物", "site": "测试图书馆"}
	var reply = "开场细节。".repeat(300) + "关键动作：双手递出蓝茶杯。" + "稍后去了花园。".repeat(100)
	var image_prompt: String = service.build_prompt(reply, "测试图书馆", turn)
	var visual_data = JSON.parse_string(image_prompt.get_slice("\n", 1))
	assert(visual_data["本轮输入"] == turn["input"])
	assert(visual_data["AI回复"] == reply, "middle action or later scene was discarded")
	assert(image_prompt.contains("冲突时优先本轮输入"))
	assert(image_prompt.contains("不合并不同时间"))
	var long_turn = {"input": "背景资料。".repeat(650) + "最终画面：窗边递蓝茶杯", "kind": "行动"}
	var long_data = JSON.parse_string(service.build_prompt("她伸出双手。", "测试图书馆", long_turn).get_slice("\n", 1))
	assert(long_data["本轮输入"] == long_turn["input"], "input's final scene instruction was truncated")
	references = service.collect_portrait_references("测试人物谈起缺少立绘", turn)
	assert(references[0]["name"] == "另一人物", "input subject lost to reply/focus character")
	assert(references[1]["name"] == "测试人物")
	export_scene_probe()
	fixture.currentNpc = null
	actor.free()
	Storage.ensure_dir(fixture.save_file.get_base_dir())
	var file = FileAccess.open(fixture.save_file, FileAccess.WRITE)
	file.store_string(JSON.stringify({"sites": {"测试图书馆": {}}, "current_site": "测试图书馆"}))
	file.close()
	fixture.active_fingerprint = FileAccess.get_sha256(fixture.save_file)
	var original_save_hash = fixture.active_fingerprint
	# Disabled means zero requests and no replacement.
	service.submit_reply("关闭状态")
	assert(service._active.is_empty())
	fixture.instant_gen_mode = true
	service.set_enabled(true)
	service.submit_reply("慢请求：走向书架")
	assert(not service._active.is_empty())
	service.submit_reply("中间请求：打开书本")
	service.submit_reply("最新请求：在桌上放书", turn)
	assert(service._pending["prompt"].contains("最新请求"))
	turn["input"] = "下一轮不相关输入"
	assert(service._pending["prompt"].contains("另一人物在窗边双手递茶"), "queued turn was mutated")
	var first_frame_deadline = Time.get_ticks_msec() + 3000
	while fixture.logs.is_empty():
		assert(Time.get_ticks_msec() < first_frame_deadline)
		await process_frame
	assert(background.texture != null, "continuous input discarded the completed same-site frame")
	await wait_idle()
	assert(background.texture != null)
	assert(background.texture.get_image().get_pixel(0, 0).g > 0.9, "stale result replaced latest image")
	assert(fixture.logs.size() == 2, "completed frame or newest pending frame was lost")
	await create_timer(0.15).timeout
	assert(fixture.usage_text.contains("新生成1张"))
	assert(fixture.usage_text.contains("输入=80"))
	assert(fixture.usage_text.contains("剩余63.0%"))
	assert("\n".join(fixture.debug_records).contains("模拟生成"))
	assert(FileAccess.file_exists(fixture.SCENE_IMG_DIR.path_join("测试图书馆.png")))
	assert(FileAccess.file_exists(fixture.save_scenes.path_join("测试图书馆.png")))
	assert(FileAccess.get_sha256(fixture.save_file) == original_save_hash, "background saving overwrote game progress")
	# Saved resource can be restored using the actual loader.
	var restored = Storage.load_image_png(fixture.save_scenes, "测试图书馆")
	assert(restored.get_image().get_pixel(0, 0).g > 0.9)
	var preserved = background.texture
	service.submit_reply("失败请求")
	await wait_idle()
	assert(background.texture == preserved)
	assert(fixture.instant_background_status_label.text.contains("fixture-failure"))
	# A scene change must still reject a completed picture from the old location.
	service.submit_reply("慢请求：旧地点画面")
	fixture.currentSiteName = "另一地点"
	await wait_idle()
	assert(background.texture == preserved, "old location overwrote the current background")
	fixture.currentSiteName = "测试图书馆"
	# Disable/reset cancels pending requests and keeps the last good background.
	service.submit_reply("慢请求：待取消")
	fixture.instant_gen_mode = false
	service.set_enabled(false)
	await create_timer(0.5).timeout
	assert(background.texture == preserved and service._active.is_empty())
	assert(service._pending.is_empty())
	# A different save cannot receive this session's generated background.
	file = FileAccess.open(fixture.save_file, FileAccess.WRITE)
	file.store_string(JSON.stringify({"sites": {"测试图书馆": {}}, "newer_save": true}))
	file.close()
	var red = Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	red.fill(Color.RED)
	assert(not Storage.persist_generated_background(red, "测试图书馆", fixture.save_file, fixture.save_scenes, original_save_hash))
	assert(Storage.load_image_png(fixture.save_scenes, "测试图书馆").get_image().get_pixel(0, 0).g > 0.9)
	# The production scene creates the binary control without enabling old queues.
	var main = load("res://main.tscn").instantiate()
	var debug_ui = preload("res://scripts/运行调试.gd")
	debug_ui.setup(main)
	assert(main.get_node("%日志按钮").button_pressed)
	assert(not main.get_node("%调试滚动").visible)
	main.add_debug("测试", "可复制的调试信息")
	main.get_node("%调试按钮").pressed.emit()
	assert(main.get_node("%调试滚动").visible)
	assert(not main.get_node("%logContainer").get_parent().visible)
	assert(main.get_node("%调试文本").text.contains("可复制的调试信息"))
	assert(main.get_node("%调试文本").selection_enabled)
	main._on_dialogue_history_button_pressed()
	assert(main.get_node("%DialogueHistoryScroll").visible and not main.showing_debug)
	main.get_node("%日志按钮").pressed.emit()
	assert(main.get_node("%logContainer").get_parent().visible)
	assert(not main.showing_dialogue_history)
	main.response_label = main.get_node("%ResponseLabel")
	main._setup_output_mode_controls()
	assert(main.instant_background_checkbox is CheckButton)
	assert(not main.instant_background_checkbox.button_pressed)
	main.instant_gen_mode = true
	main._configure_dialogue_only_mode()
	assert(main.instant_gen_mode, "text-only mode disabled the setting")
	main.instant_background_turn = {"input": "本轮行动", "kind": "行动"}
	main.last_dialogue_input = "旧对话，不能传给本轮图片"
	main.record_ai_reply("叙事", "把书放到桌上。")
	main.instant_background_turn["input"] = "下一轮对话"
	assert(main.recent_ai_replies[-1]["image_turn"]["input"] == "本轮行动")
	assert(not main.get_interaction_history_memory().contains("下一轮对话"))
	assert(not main.get_interaction_history_memory().contains("可复制的调试信息"))
	main.reset_instant_background()
	assert(main.instant_background_turn.is_empty())
	await export_debug_preview(main)
	main.free()
	# Test settings serialization in an isolated config, without changing preferences.
	var config = ConfigFile.new()
	config.set_value("images", "instant_background", true)
	assert(config.save(folder.path_join("settings.cfg")) == OK)
	var loaded_config = ConfigFile.new()
	assert(loaded_config.load(folder.path_join("settings.cfg")) == OK)
	assert(loaded_config.get_value("images", "instant_background", false))
	# Delete only the known files in the isolated fixture directory.
	for path in [fixture.SCENE_IMG_DIR.path_join("测试图书馆.png"), fixture.save_scenes.path_join("测试图书馆.png"), fixture.save_file, folder.path_join("settings.cfg")]:
		DirAccess.remove_absolute(path)
	for path in [fixture.SCENE_IMG_DIR, fixture.save_scenes, folder.path_join("slot/resources"), folder.path_join("slot"), folder]:
		DirAccess.remove_absolute(path)
	fixture.queue_free()
	await process_frame
	print("INSTANT_BACKGROUND_CHECK_OK: input/reply pairing, full middle action, input-priority portraits, immutable queue/history, single scene rules, replacement/save/load, failure/cancel, settings")
	quit()

func export_scene_probe() -> void:
	# Optional live probe: export the actual production-built request, never a hand-built prompt.
	var destination = OS.get_environment("WORLD_SIM_TEST_EXPORT_REQUEST")
	if destination.is_empty():
		return
	var image = Image.load_from_file(OS.get_environment("WORLD_SIM_TEST_PORTRAIT"))
	assert(image != null and not image.is_empty())
	fixture.npcs["多萝西"] = {}
	fixture.npcImgs["多萝西"] = ImageTexture.create_from_image(image)
	var turn = {"input": "画面停留在图书馆窗边：多萝西坐在木桌旁，双手把一只蓝色茶杯递向你，桌上放着一本打开的书。", "kind": "行动", "npc": "多萝西", "site": "测试图书馆"}
	var reply = "多萝西坐在图书馆窗边的木桌旁，双手端起蓝色茶杯递向你；打开的书留在桌面。傍晚的橙色光照过书页，窗外下着细雨。她看着你，轻轻微笑。稍后她经过石砌走廊，走进有喷泉的花园，抬头望向月亮。"
	var payload = {"target_name": "测试图书馆", "prompt": service.build_prompt(reply, "测试图书馆", turn), "references": service.collect_portrait_references(reply, turn)}
	var file = FileAccess.open(destination, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(payload))
	file.close()
	fixture.npcs.erase("多萝西")
	fixture.npcImgs.erase("多萝西")

func export_debug_preview(main: Node) -> void:
	var destination = OS.get_environment("WORLD_SIM_TEST_DEBUG_PREVIEW")
	if destination.is_empty():
		return
	fixture.instant_background_status_label.hide()
	main.add_debug("即时生图", "示例：场景提炼完成，内置工具生成中；已等待15秒")
	main.show_image_usage("本次生图：新生成1张；文字token：工具未返回；单图扣费：工具未返回\n额度示例：5小时已用37%/剩余63%（账户共享）")
	main.RuntimeDebug.show_tab(main, true)
	var panel = main.get_node("mainContainer/HBoxContainer/VBoxContainer2").duplicate()
	panel.theme = main.theme
	root.size = Vector2i(480, 820)
	root.content_scale_size = Vector2i(480, 820)
	root.content_scale_factor = 1.0
	panel.position = Vector2(16, 16)
	panel.size = Vector2(448, 788)
	root.add_child(panel)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(destination) == OK)
	panel.queue_free()
	await process_frame
