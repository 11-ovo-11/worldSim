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
	service.submit_reply("最新请求：在桌上放书")
	assert(service._pending["prompt"].contains("最新请求"))
	await wait_idle()
	assert(background.texture != null)
	assert(background.texture.get_image().get_pixel(0, 0).g > 0.9, "stale result replaced latest image")
	assert(fixture.logs.size() == 1, "intermediate result was applied")
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
	main.response_label = main.get_node("%ResponseLabel")
	main._setup_output_mode_controls()
	assert(main.instant_background_checkbox is CheckButton)
	assert(not main.instant_background_checkbox.button_pressed)
	main.instant_gen_mode = true
	main._configure_dialogue_only_mode()
	assert(main.instant_gen_mode, "text-only mode disabled the setting")
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
	print("INSTANT_BACKGROUND_CHECK_OK: disabled, latest-only queue, replacement, save image, load resource, failure retention, cancel, save isolation, settings control")
	quit()
