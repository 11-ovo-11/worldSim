extends RefCounted
class_name GameItemProfileUtils

static func generate_item_profile(scene: Node, item_name: String) -> Dictionary:
	var prompts = [
		{"role": "system", "content": scene.item_profile_prompt},
		{"role": "user", "content": "物品名：" + item_name}
	]
	var req = await scene._request_json(scene.chat_url, JSON.stringify([prompts, null, "json_object"]))
	if !req.get("ok", false):
		return {
			"description": "这是一件实用的道具，可在冒险中派上用场。",
			"image_prompt": "single game inventory item icon, clean background, detailed, centered",
			"effect_type": "none",
			"effect_value": 0
		}

	var text = req["data"].get("text", "")
	if text is Dictionary:
		return text
	if text is String:
		var json_dic = scene.extract_json_from_text(text)
		if json_dic != {}:
			return json_dic
	return {
		"description": "这是一件实用的道具，可在冒险中派上用场。",
		"image_prompt": "single game inventory item icon, clean background, detailed, centered",
		"effect_type": "none",
		"effect_value": 0
	}

static func generate_item_texture(scene: Node, image_prompt: String) -> Texture2D:
	var ultra_fast_prompt = build_ultra_fast_item_prompt(image_prompt)
	var req = await scene._request_json(
		scene.image_api_url,
		JSON.stringify({
			"prompt": ultra_fast_prompt,
			"width": 1024,
			"height": 1024,
			"target_type": "item",
			"target_name": "inventory_item",
			"steps": 6,
			"cfg_scale": 2.2,
			"mode": "ultra_fast_item"
		})
	)
	if !req.get("ok", false):
		return null
	var image_data = req["data"].get("image", "")
	return scene._base64_to_texture(image_data)

static func generate_validation_dialogue(scene: Node, scene_context: String, fallback: String) -> String:
	var prompts = [
		{"role": "system", "content": scene.validation_feedback_prompt},
		{"role": "user", "content": scene_context}
	]
	var req = await scene._request_json(scene.chat_url, JSON.stringify([prompts, null, "text"]))
	if !req.get("ok", false):
		return fallback
	var text = req["data"].get("text", "")
	if text is String and text.strip_edges() != "":
		return text.strip_edges()
	return fallback

static func build_ultra_fast_item_prompt(base_prompt: String) -> String:
	var cleaned = base_prompt.strip_edges()
	if cleaned == "":
		cleaned = "generic item"
	return "minimalist inventory icon, single object, centered, plain clean background, no text, simple lighting, " + cleaned

static func sanitize_item_profile(item_name: String, raw_profile: Dictionary) -> Dictionary:
	var safe: Dictionary = {
		"description": str(raw_profile.get("description", "这是一件实用的道具，可在冒险中派上用场。")).strip_edges(),
		"image_prompt": str(raw_profile.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered")).strip_edges(),
		"value": int(raw_profile.get("value", 50)),
		"rarity": str(raw_profile.get("rarity", "common")).strip_edges(),
		"effect_type": str(raw_profile.get("effect_type", "none")).strip_edges(),
		"effect_value": int(raw_profile.get("effect_value", 0))
	}
	if safe["description"] == "":
		safe["description"] = "这是一件实用的道具，可在冒险中派上用场。"
	if safe["image_prompt"] == "":
		safe["image_prompt"] = "single game inventory item icon of " + item_name + ", clean background, centered"
	if safe["rarity"] == "":
		safe["rarity"] = "common"
	if safe["value"] < 1:
		safe["value"] = 1
	return safe

static func ensure_item_profile_record_before_trade(scene: Node, item_name: String) -> void:
	var key = str(item_name).strip_edges()
	if key == "":
		return
	var disk_profile = scene._load_item_profile_json(key)
	var profile: Dictionary = {}
	if !disk_profile.is_empty():
		profile = sanitize_item_profile(key, disk_profile)
	else:
		var generated = await generate_item_profile(scene, key)
		profile = sanitize_item_profile(key, generated)
		scene._save_item_profile_json(key, profile)
	var cached_tex = scene._load_image_png(scene.ITEM_IMG_DIR, key)
	scene.itemProfiles[key] = {
		"description": profile.get("description", "这是一件实用的道具，可在冒险中派上用场。"),
		"image_prompt": profile.get("image_prompt", "single game inventory item icon of " + key + ", clean background, centered"),
		"value": int(profile.get("value", 50)),
		"rarity": str(profile.get("rarity", "common")),
		"effect_type": str(profile.get("effect_type", "none")),
		"effect_value": int(profile.get("effect_value", 0)),
		"texture": cached_tex,
		"is_generating": false,
		"is_ready": cached_tex != null
	}
	scene.ensure_item_profile_async(key)

static func ensure_item_profile_async(scene: Node, item_name: String) -> void:
	var disk_profile_full = scene._load_item_profile_json(item_name)
	if !scene.itemProfiles.has(item_name):
		var disk_profile = disk_profile_full
		scene.itemProfiles[item_name] = {
			"description": disk_profile.get("description", "正在生成物品介绍..."),
			"image_prompt": disk_profile.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered"),
			"value": int(disk_profile.get("value", 50)),
			"rarity": str(disk_profile.get("rarity", "common")),
			"effect_type": str(disk_profile.get("effect_type", "none")),
			"effect_value": int(disk_profile.get("effect_value", 0)),
			"texture": null,
			"is_generating": false,
			"is_ready": false
		}

	if scene.itemProfiles[item_name].get("is_generating", false) or scene.itemProfiles[item_name].get("is_ready", false):
		return

	scene.itemProfiles[item_name]["is_generating"] = true

	var cached_tex = scene._load_image_png(scene.ITEM_IMG_DIR, item_name)
	if cached_tex != null:
		var disk_profile = scene._load_item_profile_json(item_name)
		var cached_desc: String
		var cached_image_prompt: String
		var cached_value: int
		var cached_rarity: String
		var cached_effect_type: String
		var cached_effect_value: int
		if !disk_profile.is_empty():
			cached_desc = str(disk_profile.get("description", "这是一件实用的道具。"))
			cached_image_prompt = str(disk_profile.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered"))
			cached_value = int(disk_profile.get("value", 50))
			cached_rarity = str(disk_profile.get("rarity", "common"))
			cached_effect_type = str(disk_profile.get("effect_type", "none"))
			cached_effect_value = int(disk_profile.get("effect_value", 0))
		else:
			var fresh = await generate_item_profile(scene, item_name)
			cached_desc = str(fresh.get("description", "这是一件实用的道具。"))
			cached_image_prompt = str(fresh.get("image_prompt", "single game inventory item icon of " + item_name + ", clean background, centered"))
			cached_value = int(fresh.get("value", 50))
			cached_rarity = str(fresh.get("rarity", "common"))
			cached_effect_type = str(fresh.get("effect_type", "none"))
			cached_effect_value = int(fresh.get("effect_value", 0))
			scene._save_item_profile_json(item_name, fresh)
		scene.itemProfiles[item_name]["description"] = cached_desc
		scene.itemProfiles[item_name]["image_prompt"] = cached_image_prompt
		if !scene.itemProfiles[item_name].get("value_trade_confirmed", false):
			scene.itemProfiles[item_name]["value"] = cached_value
		scene.itemProfiles[item_name]["rarity"] = cached_rarity
		scene.itemProfiles[item_name]["effect_type"] = cached_effect_type
		scene.itemProfiles[item_name]["effect_value"] = cached_effect_value
		scene.itemProfiles[item_name]["texture"] = cached_tex
		scene.itemProfiles[item_name]["is_generating"] = false
		scene.itemProfiles[item_name]["is_ready"] = true
		scene.get_node("%itemContainer").update_item_visual(item_name, cached_tex, cached_desc, cached_effect_type, cached_effect_value)
		return

	var profile: Dictionary = {}
	if !disk_profile_full.is_empty():
		profile = sanitize_item_profile(item_name, disk_profile_full)
	else:
		profile = sanitize_item_profile(item_name, await generate_item_profile(scene, item_name))
		scene._save_item_profile_json(item_name, profile)
	var item_description = str(profile.get("description", "这是一件实用的道具，可在冒险中派上用场。"))
	var item_value = int(profile.get("value", 50))
	var item_rarity = str(profile.get("rarity", "common"))
	var item_effect_type = str(profile.get("effect_type", "none"))
	var item_effect_value = int(profile.get("effect_value", 0))
	var image_prompt = str(profile.get("image_prompt", "single game inventory item icon, clean background, detailed, centered"))
	var item_texture = await generate_item_texture(scene, image_prompt)

	if item_texture != null:
		var item_image = (item_texture as ImageTexture).get_image()
		if item_image != null:
			scene._save_image_png(item_image, scene.ITEM_IMG_DIR, item_name)

	scene.itemProfiles[item_name]["description"] = item_description
	scene.itemProfiles[item_name]["image_prompt"] = image_prompt
	if !scene.itemProfiles[item_name].get("value_trade_confirmed", false):
		scene.itemProfiles[item_name]["value"] = item_value
	scene.itemProfiles[item_name]["rarity"] = item_rarity
	scene.itemProfiles[item_name]["effect_type"] = item_effect_type
	scene.itemProfiles[item_name]["effect_value"] = item_effect_value
	scene.itemProfiles[item_name]["texture"] = item_texture
	scene.itemProfiles[item_name]["is_generating"] = false
	scene.itemProfiles[item_name]["is_ready"] = true
	scene.get_node("%itemContainer").update_item_visual(item_name, item_texture, item_description, item_effect_type, item_effect_value)
