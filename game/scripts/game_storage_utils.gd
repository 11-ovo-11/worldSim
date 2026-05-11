extends RefCounted
class_name GameStorageUtils

static func sanitize_filename(file_name: String) -> String:
	return file_name.replace("/", "_").replace("\\", "_").replace(":", "_").replace("*", "_").replace("?", "_").replace("\"", "_").replace("<", "_").replace(">", "_").replace("|", "_")

static func ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)

static func clear_dir_contents(dir_path: String) -> void:
	if !DirAccess.dir_exists_absolute(dir_path):
		return
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var target_path = dir_path.path_join(entry)
			if dir.current_is_dir():
				clear_dir_contents(target_path)
				DirAccess.remove_absolute(target_path)
			else:
				DirAccess.remove_absolute(target_path)
		entry = dir.get_next()
	dir.list_dir_end()

static func copy_file(src_path: String, dst_path: String) -> void:
	if !FileAccess.file_exists(src_path):
		return
	ensure_dir(dst_path.get_base_dir())
	var bytes = FileAccess.get_file_as_bytes(src_path)
	var file = FileAccess.open(dst_path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()

static func copy_dir_recursive(src_dir: String, dst_dir: String) -> void:
	if !DirAccess.dir_exists_absolute(src_dir):
		return
	ensure_dir(dst_dir)
	var dir = DirAccess.open(src_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var src_path = src_dir.path_join(entry)
			var dst_path = dst_dir.path_join(entry)
			if dir.current_is_dir():
				copy_dir_recursive(src_path, dst_path)
			else:
				copy_file(src_path, dst_path)
		entry = dir.get_next()
	dir.list_dir_end()

static func save_image_png(image: Image, dir_path: String, file_name: String) -> void:
	ensure_dir(dir_path)
	var path = dir_path + sanitize_filename(file_name) + ".png"
	image.save_png(path)

static func load_image_png(dir_path: String, file_name: String) -> Texture2D:
	var path = dir_path + sanitize_filename(file_name) + ".png"
	if FileAccess.file_exists(path):
		var img = Image.load_from_file(path)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null

static func save_json_dict(dir_path: String, file_name: String, data: Dictionary, indent: String = "") -> void:
	ensure_dir(dir_path)
	var path = dir_path + sanitize_filename(file_name) + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, indent))
		file.close()

static func load_json_dict(dir_path: String, file_name: String) -> Dictionary:
	var path = dir_path + sanitize_filename(file_name) + ".json"
	if !FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if !file:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	var d = json.get_data()
	return d if d is Dictionary else {}

static func prepare_session_resource_dir(session_dir: String, scene_dir: String, item_dir: String, item_profile_dir: String, npc_dir: String) -> void:
	ensure_dir(session_dir)
	clear_dir_contents(session_dir)
	ensure_dir(scene_dir)
	ensure_dir(item_dir)
	ensure_dir(item_profile_dir)
	ensure_dir(npc_dir)

static func sync_session_resources_to_save(
	save_slot_dir: String,
	save_resource_dir: String,
	scene_dir: String,
	item_dir: String,
	item_profile_dir: String,
	npc_dir: String,
	save_scene_dir: String,
	save_item_dir: String,
	save_item_profile_dir: String,
	save_npc_dir: String
) -> void:
	ensure_dir(save_slot_dir)
	clear_dir_contents(save_slot_dir)
	ensure_dir(save_resource_dir)
	copy_dir_recursive(scene_dir, save_scene_dir)
	copy_dir_recursive(item_dir, save_item_dir)
	copy_dir_recursive(item_profile_dir, save_item_profile_dir)
	copy_dir_recursive(npc_dir, save_npc_dir)

static func restore_session_resources_from_save(
	session_dir: String,
	scene_dir: String,
	item_dir: String,
	item_profile_dir: String,
	npc_dir: String,
	save_scene_dir: String,
	save_item_dir: String,
	save_item_profile_dir: String,
	save_npc_dir: String
) -> void:
	ensure_dir(session_dir)
	clear_dir_contents(session_dir)
	copy_dir_recursive(save_scene_dir, scene_dir)
	copy_dir_recursive(save_item_dir, item_dir)
	copy_dir_recursive(save_item_profile_dir, item_profile_dir)
	copy_dir_recursive(save_npc_dir, npc_dir)

static func handle_exit_cleanup(has_saved_in_session: bool, session_dir: String) -> void:
	if has_saved_in_session:
		return
	clear_dir_contents(session_dir)
