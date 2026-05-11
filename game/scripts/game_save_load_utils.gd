extends RefCounted
class_name GameSaveLoadUtils

static func save_game(scene: Node) -> void:
	for profile_key in scene.itemProfiles.keys():
		var item_name = str(profile_key)
		var prof = scene.itemProfiles.get(item_name, {})
		if prof is Dictionary and item_name != "":
			var packed_profile = scene._sanitize_item_profile(item_name, {
				"description": prof.get("description", ""),
				"image_prompt": prof.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered"),
				"value": int(prof.get("value", 50)),
				"rarity": str(prof.get("rarity", "common")),
				"effect_type": str(prof.get("effect_type", "none")),
				"effect_value": int(prof.get("effect_value", 0))
			})
			scene._save_item_profile_json(item_name, packed_profile)
	scene._sync_session_resources_to_save()
	scene._ensure_dir(scene.SAVE_SLOT_DIR)
	var item_list: Array = []
	for child in scene.get_node("%itemContainer").get_children():
		if child is item:
			var prof = scene.itemProfiles.get(child.item_name, {})
			item_list.append({
				"name": child.item_name,
				"num": child.item_num,
				"description": child.item_description,
				"value": prof.get("value", 50),
				"rarity": prof.get("rarity", "common"),
				"effect_type": prof.get("effect_type", "none"),
				"effect_value": int(prof.get("effect_value", 0))
			})

	var log_list: Array = []
	for log_node in scene.get_node("%logContainer").get_children():
		var log_text = str(log_node.text)
		if scene._is_important_log(log_text):
			log_list.append(log_text)
	if log_list.size() > 200:
		log_list = log_list.slice(max(0, log_list.size() - 200), log_list.size())

	var save_data = {
		"version": 1,
		"world_seed_input": scene.world_seed_input,
		"background": scene.background,
		"current_site": scene.currentSiteName,
		"sites": scene.sites,
		"npcs": scene.npcs,
		"rumors": scene.rumors,
		"player": {
			"name": scene.playerName,
			"money": scene.money,
			"energy": scene.energy,
			"hp": scene.hp,
			"reputation": scene.reputation
		},
		"nowtime": scene.nowtime,
		"env_dic": scene.envDic,
		"items": item_list,
		"logs": log_list,
		"important_event_memories": scene.important_event_memories,
		"current_chat_session_npc": scene.current_chat_session_npc,
		"current_chat_session_records": scene.current_chat_session_records,
		"dead_npc_names": scene.dead_npc_names,
		"dialogue_min_chars": scene.dialogue_min_chars,
		"action_narration_min_chars": scene.action_narration_min_chars
	}

	var file = FileAccess.open(scene.SAVE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		scene.has_saved_in_session = true
		scene.addLog("<游戏已保存>")
	else:
		scene.addLog("<保存失败：" + str(FileAccess.get_open_error()) + ">")

static func load_game(scene: Node) -> bool:
	if !scene.has_save_file():
		scene.addLog("<没有存档文件>")
		return false
	scene._force_exit_chat_runtime()
	scene.siteImgs.clear()
	scene.npcImgs.clear()
	var npc_icon = scene.get_node("%npcIcon")
	if npc_icon is TextureRect:
		(npc_icon as TextureRect).texture = null
	var bg = scene.get_node("%backgroundImg")
	if bg is TextureRect:
		(bg as TextureRect).texture = null
	scene._restore_session_resources_from_save()
	var file = FileAccess.open(scene.SAVE_FILE, FileAccess.READ)
	if !file:
		scene.addLog("<读档失败>")
		return false
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		scene.addLog("<存档文件损坏>")
		return false
	file.close()
	var data = json.get_data()

	scene.world_seed_input = data.get("world_seed_input", "")
	scene.background = data.get("background", "")
	scene.sites = data.get("sites", {})
	scene.npcs = data.get("npcs", {})
	scene._restore_runtime_image_caches_from_disk()
	scene.rumors = data.get("rumors", {})
	scene.important_event_memories = data.get("important_event_memories", [])
	scene.current_chat_session_npc = str(data.get("current_chat_session_npc", "")).strip_edges()
	scene.current_chat_session_records = []
	var loaded_session_records = data.get("current_chat_session_records", [])
	if loaded_session_records is Array:
		for row in loaded_session_records:
			var rec = str(row).strip_edges()
			if rec != "":
				scene.current_chat_session_records.append(rec)
	if scene.current_chat_session_npc == "" or !scene.npcs.has(scene.current_chat_session_npc):
		scene.current_chat_session_npc = ""
		scene.current_chat_session_records = []
	scene.dead_npc_names = data.get("dead_npc_names", [])
	scene.dialogue_min_chars = clamp(int(data.get("dialogue_min_chars", data.get("efficient_mode_min_chars", 90))), 40, 2000)
	scene.action_narration_min_chars = clamp(int(data.get("action_narration_min_chars", 90)), 40, 2000)

	var p = data.get("player", {})
	scene.playerName = p.get("name", scene.playerName)
	scene.money = p.get("money", 1000)
	scene.energy = p.get("energy", 100.0)
	scene.hp = p.get("hp", 100.0)
	scene.reputation = p.get("reputation", 100.0)
	scene.player_update()

	scene.nowtime = data.get("nowtime", 500.0)

	scene.envDic = data.get("env_dic", {})
	if !scene.envDic.is_empty():
		scene.get_node("%envContainer").load_weather_config_from_json(scene.envDic)

	scene.clear_children(scene.get_node("%itemContainer"))
	scene.itemProfiles.clear()
	for item_data in data.get("items", []):
		var iname = item_data.get("name", "")
		var inum = item_data.get("num", 1)
		var idesc = item_data.get("description", "")
		var ivalue = int(item_data.get("value", 50))
		var irarity = str(item_data.get("rarity", "common"))
		var ieffect_type = str(item_data.get("effect_type", "none"))
		var ieffect_value = int(item_data.get("effect_value", 0))
		if iname == "":
			continue
		var disk_profile = scene._load_item_profile_json(iname)
		var iimage_prompt = str(disk_profile.get("image_prompt", "single game inventory item icon of " + iname + ", clean background, centered"))
		var tex = scene._load_image_png(scene.ITEM_IMG_DIR, iname)
		scene.itemProfiles[iname] = {
			"description": idesc,
			"image_prompt": iimage_prompt,
			"value": ivalue,
			"rarity": irarity,
			"effect_type": ieffect_type,
			"effect_value": ieffect_value,
			"texture": tex,
			"is_generating": false,
			"is_ready": tex != null
		}
		scene._save_item_profile_json(iname, scene._sanitize_item_profile(iname, {
			"description": idesc,
			"value": ivalue,
			"rarity": irarity,
			"effect_type": ieffect_type,
			"effect_value": ieffect_value,
			"image_prompt": iimage_prompt
		}))
		scene.get_node("%itemContainer").add_item(iname, inum, tex, idesc, ieffect_type, ieffect_value)
		if tex == null:
			scene.ensure_item_profile_async(iname)

	scene.clear_children(scene.get_node("%logContainer"))
	for log_text in data.get("logs", []):
		scene.addLog(str(log_text), true)

	var site_name = str(data.get("current_site", "")).strip_edges()
	if (site_name == "" or !scene.sites.has(site_name)) and !scene.sites.is_empty():
		site_name = str(scene.sites.keys()[0])
	if site_name != "" and scene.sites.has(site_name):
		scene.currentSiteName = site_name
		scene.changeTextTo(scene.get_node("%speakerNameLabel"), scene.playerName)
		scene._set_event_flow_lock(false)
		var has_bg := false
		var cached = scene._load_image_png(scene.SCENE_IMG_DIR, site_name)
		if cached != null:
			scene.get_node("%backgroundImg").texture = cached
			scene.siteImgs[site_name] = cached
			has_bg = true
			scene._bg_debug("load_game image cache hit for " + site_name)
		if !has_bg:
			var site_data = scene._get_site_data(site_name)
			var scene_prompt = scene._build_scene_image_prompt(site_name, site_data)
			scene._bg_debug("load_game image cache miss for " + site_name + ", prompt_len=" + str(scene_prompt.length()))
			if scene_prompt != "":
				scene.site_update(false, true, false)
				scene.pending_site_update = false
				scene._set_site_loading_lock(false)
				scene.gen_img(scene_prompt, site_name)
			else:
				scene.pending_site_update = false
				scene._set_site_loading_lock(false)
				scene.site_update(false, true, false)
		else:
			scene.pending_site_update = false
			scene.site_update(false, true, false)
	else:
		scene._set_site_loading_lock(false)
		scene.clear_children(scene.get_node("%site_buttons"))
		scene.clear_children(scene.get_node("%npc_buttons"))
		scene.changeTextTo(scene.get_node("%siteName"), "未定位")

	scene.has_saved_in_session = false
	scene.addLog("<读档完成>")
	return true
