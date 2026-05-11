extends RefCounted
class_name GameImageUtils

static func resolve_image_slot_size(target_type: String, npc_size: Vector2, npc_min_size: Vector2, bg_size: Vector2, bg_min_size: Vector2) -> Vector2i:
	if target_type == "npc":
		var nw = int(max(npc_size.x, npc_min_size.x))
		var nh = int(max(npc_size.y, npc_min_size.y))
		if nh <= 0:
			nh = int(max(bg_size.y, bg_min_size.y))
		nw = max(nw, 220)
		nh = max(nh, 360)
		return Vector2i(nw, nh)
	if target_type == "item":
		return Vector2i(100, 100)
	var w = int(max(bg_size.x, bg_min_size.x))
	var h = int(max(bg_size.y, bg_min_size.y))
	if w > 0 and h > 0:
		return Vector2i(w, h)
	return Vector2i(1024, 576)

static func fit_image_to_target_slot(raw_image: Image, target_size: Vector2i) -> Image:
	if raw_image == null:
		return null
	if target_size.x <= 0 or target_size.y <= 0:
		return raw_image
	var sw = raw_image.get_width()
	var sh = raw_image.get_height()
	if sw <= 0 or sh <= 0:
		return raw_image
	var src_ratio = float(sw) / float(sh)
	var dst_ratio = float(target_size.x) / float(target_size.y)
	var crop_rect := Rect2i(0, 0, sw, sh)
	if absf(src_ratio - dst_ratio) > 0.001:
		if src_ratio > dst_ratio:
			var crop_w = int(round(float(sh) * dst_ratio))
			crop_w = clampi(crop_w, 1, sw)
			var x_offset = int(floor(float(sw - crop_w) / 2.0))
			crop_rect = Rect2i(x_offset, 0, crop_w, sh)
		else:
			var crop_h = int(round(float(sw) / dst_ratio))
			crop_h = clampi(crop_h, 1, sh)
			var y_offset = int(floor(float(sh - crop_h) / 2.0))
			crop_rect = Rect2i(0, y_offset, sw, crop_h)
	var fitted = raw_image.get_region(crop_rect)
	fitted.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	return fitted

static func resolve_image_callback_target(callback_site: String, response: Dictionary) -> String:
	var response_type = str(response.get("target_type", "")).strip_edges().to_lower()
	var response_name = str(response.get("target_name", "")).strip_edges()
	if response_type == "npc" and response_name != "":
		return "NPC:" + response_name
	if response_type == "item" and response_name != "":
		return "ITEM:" + response_name
	if response_type == "scene" and response_name != "":
		return response_name
	return callback_site

static func describe_image_target(target_site: String) -> String:
	if target_site.begins_with("NPC:"):
		return "NPC「" + target_site.trim_prefix("NPC:") + "」"
	if target_site.begins_with("ITEM:"):
		return "物品「" + target_site.trim_prefix("ITEM:") + "」"
	return "场景「" + target_site + "」"

static func base64_to_image(base64_string: String) -> Image:
	if base64_string == "":
		return null
	var image_buffer = Marshalls.base64_to_raw(base64_string)
	var image = Image.new()
	var error = image.load_png_from_buffer(image_buffer)
	if error != OK:
		error = image.load_jpg_from_buffer(image_buffer)
	if error != OK:
		return null
	return image

static func base64_to_texture(base64_string: String) -> Texture2D:
	var image = base64_to_image(base64_string)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)

static func build_image_request_payload(prompt: String, target_site: String, current_site_name: String, bg_size: Vector2, bg_min_size: Vector2) -> Dictionary:
	var target_key = target_site.strip_edges()
	var target_type = "scene"
	var target_name = target_key
	var width = 1344
	var height = 768
	if target_key.begins_with("NPC:"):
		target_type = "npc"
		target_name = target_key.trim_prefix("NPC:")
		width = 768
		height = 1152
	elif target_key.begins_with("ITEM:"):
		target_type = "item"
		target_name = target_key.trim_prefix("ITEM:")
		width = 256
		height = 256
	elif target_name == "":
		target_name = current_site_name
	if target_type == "scene":
		var bg_w = int(max(bg_size.x, bg_min_size.x))
		var bg_h = int(max(bg_size.y, bg_min_size.y))
		if bg_w > 0 and bg_h > 0:
			width = max(768, int(bg_w))
			height = max(432, int(bg_h))
	return {
		"prompt": prompt,
		"width": width,
		"height": height,
		"target_type": target_type,
		"target_name": target_name,
	}
