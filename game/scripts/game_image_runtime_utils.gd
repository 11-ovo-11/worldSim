extends RefCounted
class_name GameImageRuntimeUtils

static func has_pending_image_target(scene: Node, target_site: String) -> bool:
	if target_site == "":
		return false
	for req in scene.pending_img_queue:
		if req is Dictionary and str(req.get("target_site", "")) == target_site:
			return true
	return false

static func enqueue_image_request(scene: Node, prompt: String, target_site: String, retry_count: int = 0, front: bool = false) -> void:
	var p = str(prompt).strip_edges()
	var t = str(target_site).strip_edges()
	if p == "" or t == "":
		return
	if retry_count <= 0:
		var dedupe_key = t + "|" + p
		var now_ms = Time.get_ticks_msec()
		var recent_raw = scene.get_meta("img_recent_req_map", {})
		var recent: Dictionary = {}
		if recent_raw is Dictionary:
			recent = recent_raw
		var last_ms = int(recent.get(dedupe_key, 0))
		if last_ms > 0 and now_ms - last_ms < 45000:
			scene._bg_debug("gen_img suppressed duplicate, target=" + t)
			return
		recent[dedupe_key] = now_ms
		for key in recent.keys():
			if now_ms - int(recent.get(key, 0)) > 180000:
				recent.erase(key)
		scene.set_meta("img_recent_req_map", recent)
	if scene.inflight_img_site == t or scene._has_pending_image_target(t):
		return
	var req = {
		"prompt": p,
		"target_site": t,
		"retry_count": max(0, int(retry_count))
	}
	if front:
		scene.pending_img_queue.push_front(req)
	else:
		scene.pending_img_queue.append(req)

static func dispatch_image_request(scene: Node, req: Dictionary) -> int:
	var prompt = str(req.get("prompt", "")).strip_edges()
	var target_site = str(req.get("target_site", "")).strip_edges()
	var is_instant_scene = bool(req.get("instant_scene", false))
	if prompt == "" or target_site == "":
		return ERR_INVALID_PARAMETER
	var retry_count = int(req.get("retry_count", 0))
	var start_log = "<" + ("即时场景图请求：" if is_instant_scene else "图片生成请求：") + scene._describe_image_target(target_site)
	if retry_count > 0:
		start_log += "（重试" + str(retry_count) + "）"
	start_log += ">"
	scene.addLog(start_log)
	scene._bg_debug("gen_img start, site=" + target_site + ", prompt=" + prompt.left(80))
	var headers = ["Content-Type: application/json"]
	var image_json_data = JSON.stringify(scene._build_image_request_payload(prompt, target_site))
	scene.get_node("%ImgHTTPRequest").timeout = 200.0
	var error_image = scene.get_node("%ImgHTTPRequest").request(scene.image_api_url, headers, HTTPClient.METHOD_POST, image_json_data)
	if error_image == OK:
		scene.inflight_img_site = target_site
		scene.inflight_img_request = req.duplicate(true)
		scene.inflight_img_started_ms = Time.get_ticks_msec()
		if scene.pending_site_update:
			scene._start_img_watchdog(target_site)
	return error_image

static func is_retryable_image_error(_scene: Node, response_code: int, error_msg: String) -> bool:
	if response_code in [429, 500, 502, 503, 504]:
		return true
	var msg = str(error_msg)
	return msg.find("上游负载已饱和") >= 0 \
		or msg.find("稍后再试") >= 0 \
		or msg.to_lower().find("rate limit") >= 0 \
		or msg.to_lower().find("overload") >= 0 \
		or msg.to_lower().find("timeout") >= 0

static func queue_image_retry(scene: Node, req: Dictionary, reason: String = "") -> bool:
	if req.is_empty():
		return false
	var retry_count = int(req.get("retry_count", 0))
	if retry_count >= int(scene.IMG_RETRY_MAX_ATTEMPTS):
		return false
	var next_retry = retry_count + 1
	var delay_sec = float(scene.IMG_RETRY_BASE_DELAY_SEC) * pow(2.0, float(retry_count))
	var target_site = str(req.get("target_site", "")).strip_edges()
	var reason_text = str(reason).strip_edges()
	if target_site != "":
		var msg = "<图片服务繁忙，" + scene._describe_image_target(target_site) + "将在" + str(snapped(delay_sec, 0.1)) + "秒后重试(" + str(next_retry) + "/" + str(scene.IMG_RETRY_MAX_ATTEMPTS) + ")"
		if reason_text != "":
			msg += "，原因:" + reason_text
		msg += ">"
		scene.addLog(msg)
	scene.call_deferred("_schedule_image_retry", str(req.get("prompt", "")), target_site, next_retry, delay_sec)
	return true

static func schedule_image_retry(scene: Node, prompt: String, target_site: String, retry_count: int, delay_sec: float) -> void:
	await scene.get_tree().create_timer(max(0.2, delay_sec)).timeout
	scene._enqueue_image_request(prompt, target_site, retry_count, true)
	scene._drain_pending_img()

static func apply_scene_background_for_current_site(scene: Node) -> void:
	var site_name = str(scene.currentSiteName).strip_edges()
	if site_name == "":
		return
	var bg = scene.get_node_or_null("%backgroundImg")
	if !(bg is TextureRect):
		return
	if scene.siteImgs.has(site_name) and scene.siteImgs[site_name] is Texture2D:
		(bg as TextureRect).texture = scene.siteImgs[site_name]
		return
	var cached = scene._load_image_png(scene.SCENE_IMG_DIR, site_name)
	if cached != null:
		scene.siteImgs[site_name] = cached
		(bg as TextureRect).texture = cached

static func _build_dialogue_npc_style_anchor(scene: Node) -> String:
	if scene == null or scene.currentNpc == null:
		return ""
	var npc_name = str(scene.currentNpc.npcName).strip_edges()
	if npc_name == "":
		return ""
	var npc_desc = str(scene.currentNpc.npcDescribe).strip_edges()
	if npc_desc == "" and scene.npcs.has(npc_name) and scene.npcs[npc_name] is Dictionary:
		npc_desc = str((scene.npcs[npc_name] as Dictionary).get("npc_describe", "")).strip_edges()
	var style_anchor = ""
	if scene.has_method("_build_npc_image_prompt"):
		var loc_hint = str(scene.currentSiteName).strip_edges()
		style_anchor = str(scene._build_npc_image_prompt(npc_name, npc_desc, loc_hint)).strip_edges()
	var parts: Array = [
		"character consistency reference",
		"dialogue focus npc: " + npc_name,
		"keep the same face traits, hairstyle, outfit silhouette and anime rendering style as this npc"
	]
	if npc_desc != "":
		parts.append("npc appearance: " + npc_desc.left(140))
	if style_anchor != "":
		parts.append("npc style anchor: " + style_anchor.left(220))
	return ", ".join(parts)

static func trigger_instant_scene_image(scene: Node, narrative_text: String) -> void:
	var site_name = str(scene.currentSiteName).strip_edges()
	if site_name == "":
		scene.addLog("<即时生成取消：当前地点为空>")
		return
	var site_data = scene._get_site_data(site_name)
	if site_data.is_empty():
		scene.addLog("<即时生成取消：地点数据为空（" + site_name + "）>")
		return
	var moment = str(narrative_text).strip_edges()
	var dedupe_text = moment.left(220)
	var dialogue_npc = ""
	if scene.currentNpc != null:
		dialogue_npc = str(scene.currentNpc.npcName).strip_edges()
	var dedupe_key = site_name + "|" + dialogue_npc + "|" + dedupe_text
	var now_ms = Time.get_ticks_msec()
	var last_key = str(scene.get_meta("instant_img_last_key", ""))
	var last_ms = int(scene.get_meta("instant_img_last_ms", 0))
	if dedupe_key == last_key and now_ms - last_ms < 2500:
		scene._bg_debug("instant scene image deduped, site=" + site_name)
		scene.addLog("<即时生成去重：同一内容短时间重复触发>")
		return
	scene.set_meta("instant_img_last_key", dedupe_key)
	scene.set_meta("instant_img_last_ms", now_ms)
	var prompt = scene._build_scene_image_prompt(site_name, site_data)
	var npc_style_anchor = _build_dialogue_npc_style_anchor(scene)
	if npc_style_anchor != "":
		prompt += ", " + npc_style_anchor
	if moment != "":
		prompt += ", narrative moment: " + moment.left(180)
	if prompt == "":
		scene.addLog("<即时生成取消：生成提示词为空>")
		return
	if str(scene.inflight_img_site).strip_edges() != "":
		scene.addLog("<即时生成已取消：上一张图片仍在生成中>")
		scene._bg_debug("instant scene image canceled (inflight=" + str(scene.inflight_img_site) + ")")
		return
	var req = {
		"prompt": prompt,
		"target_site": site_name,
		"retry_count": 0,
		"instant_scene": true
	}
	var kept_queue: Array = []
	var replaced_count = 0
	for pending in scene.pending_img_queue:
		if pending is Dictionary and str((pending as Dictionary).get("target_site", "")) == site_name:
			replaced_count += 1
			continue
		kept_queue.append(pending)
	scene.pending_img_queue = kept_queue
	scene.pending_img_queue.append(req)
	if replaced_count > 0:
		scene.addLog("<即时生成更新：已替换" + str(replaced_count) + "个旧背景请求>")
	scene.addLog("<即时生成排队：" + site_name + "，文本片段=" + moment.left(28) + "...>")
	scene._bg_debug("instant scene image queued, site=" + site_name + ", prompt_len=" + str(prompt.length()) + ", queue_size=" + str(scene.pending_img_queue.size()))
	scene._drain_pending_img()

static func try_use_cached_image_for_target(scene: Node, target_site: String) -> bool:
	if target_site == "":
		return false
	if target_site.begins_with("NPC:"):
		var npc_name = target_site.trim_prefix("NPC:")
		var npc_tex: Texture2D = null
		if scene.npcImgs.has(npc_name) and scene.npcImgs[npc_name] is Texture2D:
			npc_tex = scene.npcImgs[npc_name]
		else:
			npc_tex = scene._load_image_png(scene.NPC_IMG_DIR, npc_name)
			if npc_tex != null:
				scene.npcImgs[npc_name] = npc_tex
		if npc_tex == null:
			return false
		var npc_icon = scene.get_node("%npcIcon")
		if scene.currentNpc != null and str(scene.currentNpc.npcName) == npc_name and npc_icon is TextureRect:
			(npc_icon as TextureRect).texture = npc_tex
		return true
	if target_site.begins_with("ITEM:"):
		var item_name = target_site.trim_prefix("ITEM:")
		var item_tex: Texture2D = null
		if scene.itemProfiles.has(item_name):
			var t = scene.itemProfiles[item_name].get("texture", null)
			if t is Texture2D:
				item_tex = t
		if item_tex == null:
			item_tex = scene._load_image_png(scene.ITEM_IMG_DIR, item_name)
			if item_tex != null and scene.itemProfiles.has(item_name):
				scene.itemProfiles[item_name]["texture"] = item_tex
				scene.itemProfiles[item_name]["is_ready"] = true
				scene.itemProfiles[item_name]["is_generating"] = false
		if item_tex == null:
			return false
		if scene.itemProfiles.has(item_name):
			scene.get_node("%itemContainer").update_item_visual(
				item_name,
				item_tex,
				str(scene.itemProfiles[item_name].get("description", "这是一件实用的道具。")),
				str(scene.itemProfiles[item_name].get("effect_type", "none")),
				int(scene.itemProfiles[item_name].get("effect_value", 0))
			)
		return true
	var scene_tex: Texture2D = null
	if scene.siteImgs.has(target_site) and scene.siteImgs[target_site] is Texture2D:
		scene_tex = scene.siteImgs[target_site]
	else:
		scene_tex = scene._load_image_png(scene.SCENE_IMG_DIR, target_site)
		if scene_tex != null:
			scene.siteImgs[target_site] = scene_tex
	if scene_tex == null:
		return false
	var bg = scene.get_node("%backgroundImg")
	if target_site == scene.currentSiteName and bg is TextureRect:
		(bg as TextureRect).texture = scene_tex
	return true

static func display_base64_image(scene: Node, base64_string: String, site_name: String = "") -> void:
	var target_site = site_name.strip_edges()
	if target_site == "":
		target_site = scene.currentSiteName
	if target_site.begins_with("ITEM:"):
		var item_n = target_site.trim_prefix("ITEM:")
		var item_img = scene._base64_to_image(base64_string)
		if item_img != null:
			var fitted_item_img = scene._fit_image_to_target_slot(item_img, "item")
			if fitted_item_img == null:
				return
			if fitted_item_img != null and fitted_item_img.get_format() != Image.FORMAT_RGBA8:
				fitted_item_img.convert(Image.FORMAT_RGBA8)
			var item_tex = ImageTexture.create_from_image(fitted_item_img)
			if scene.itemProfiles.has(item_n):
				scene.itemProfiles[item_n]["texture"] = item_tex
				scene.itemProfiles[item_n]["is_generating"] = false
				scene.itemProfiles[item_n]["is_ready"] = true
				scene.get_node("%itemContainer").update_item_visual(
					item_n,
					item_tex,
					str(scene.itemProfiles[item_n].get("description", "这是一件实用的道具。")),
					str(scene.itemProfiles[item_n].get("effect_type", "none")),
					int(scene.itemProfiles[item_n].get("effect_value", 0))
				)
			scene._save_image_png(fitted_item_img, scene.ITEM_IMG_DIR, item_n)
		scene._drain_pending_img()
		return
	if target_site.begins_with("NPC:"):
		var npc_n = target_site.trim_prefix("NPC:")
		var npc_img = scene._base64_to_image(base64_string)
		if npc_img != null:
			var fitted_npc_img = scene._fit_image_to_target_slot(npc_img, "npc")
			var npc_tex = ImageTexture.create_from_image(fitted_npc_img)
			scene.npcImgs[npc_n] = npc_tex
			scene._save_image_png(fitted_npc_img, scene.NPC_IMG_DIR, npc_n)
			var npc_icon = scene.get_node("%npcIcon")
			if scene.currentNpc != null and str(scene.currentNpc.npcName) == npc_n and npc_icon is TextureRect:
				(npc_icon as TextureRect).texture = npc_tex
		if scene.npcs.has(npc_n) and scene.npcs[npc_n] is Dictionary:
			scene.npcs[npc_n]["portrait_generating"] = false
		scene._drain_pending_img()
		return
	var image = scene._base64_to_image(base64_string)
	if image != null:
		var fitted_scene = scene._fit_image_to_target_slot(image, "scene")
		var texture = ImageTexture.create_from_image(fitted_scene)
		scene.siteImgs[target_site] = texture
		scene._save_image_png(fitted_scene, scene.SCENE_IMG_DIR, target_site)
		if target_site == scene.currentSiteName:
			scene.get_node("%backgroundImg").texture = texture
		scene._bg_debug("display image ok, site=" + target_site + ", b64_len=" + str(base64_string.length()))
	else:
		print("错误：图片格式不支持")
		scene._bg_debug("display image failed, invalid image buffer")
	if scene.pending_site_update:
		scene.pending_site_update = false
		scene.site_update()
	scene._drain_pending_img()

static func on_img_http_request_request_completed(scene: Node, result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	scene.img_watchdog_seq += 1
	var inflight_req: Dictionary = {}
	if scene.inflight_img_request is Dictionary:
		inflight_req = scene.inflight_img_request.duplicate(true)
	var callback_site = scene.inflight_img_site
	var started_ms = scene.inflight_img_started_ms
	scene.inflight_img_site = ""
	scene.inflight_img_request = {}
	scene.inflight_img_started_ms = 0
	if callback_site == "":
		callback_site = scene.currentSiteName
	scene._bg_debug("img callback, site=" + callback_site + ", result=" + str(result) + ", code=" + str(response_code) + ", body_len=" + str(body.size()))
	if result != HTTPRequest.RESULT_SUCCESS:
		print("图片生成失败：网络错误")
		scene._bg_debug("img callback network failed")
		if callback_site.begins_with("NPC:"):
			var fail_npc = callback_site.trim_prefix("NPC:")
			if scene.npcs.has(fail_npc) and scene.npcs[fail_npc] is Dictionary:
				scene.npcs[fail_npc]["portrait_generating"] = false
		if scene._queue_image_retry(inflight_req, "network_error"):
			scene._drain_pending_img()
			return
		if scene.pending_site_update:
			scene.pending_site_update = false
			scene.site_update()
		scene._drain_pending_img()
		return

	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())

	if parse_error != OK:
		print("图片生成失败：响应解析错误", body.get_string_from_utf8())
		scene._bg_debug("img callback parse failed")
		if callback_site.begins_with("NPC:"):
			var parse_fail_npc = callback_site.trim_prefix("NPC:")
			if scene.npcs.has(parse_fail_npc) and scene.npcs[parse_fail_npc] is Dictionary:
				scene.npcs[parse_fail_npc]["portrait_generating"] = false
		if scene._queue_image_retry(inflight_req, "parse_error"):
			scene._drain_pending_img()
			return
		if scene.pending_site_update:
			scene.pending_site_update = false
			scene.site_update()
		scene._drain_pending_img()
		return

	var response = json.get_data()

	if response_code == 200 and response.get("success", false):
		var image_data = response.get("image", "")
		if image_data:
			var resolved_target = scene._resolve_image_callback_target(callback_site, response)
			scene._display_base64_image(image_data, resolved_target)
			if started_ms > 0:
				var elapsed_s = snapped(float(Time.get_ticks_msec() - started_ms) / 1000.0, 0.01)
				scene.addLog("<图片生成完成：" + scene._describe_image_target(resolved_target) + "，耗时" + str(elapsed_s) + "秒>")
		else:
			print("图片生成失败：未收到图片数据")
			scene._bg_debug("img callback success=true but image empty")
			if scene.pending_site_update:
				scene.pending_site_update = false
				scene.site_update()
		if scene.pending_site_update:
			scene.pending_site_update = false
			scene.site_update()
		scene._drain_pending_img()
	else:
		var error_msg = response.get("error", "未知错误")
		var debug_data = response.get("debug", {})
		var has_debug = debug_data is Dictionary and !debug_data.is_empty()
		var debug_summary := ""
		if has_debug:
			var status = str(debug_data.get("status_code", ""))
			var preview = str(debug_data.get("response_preview", str(debug_data.get("exception", ""))))
			if debug_data.has("attempts"):
				print("[IMG_CLIENT_DEBUG] attempts=", JSON.stringify(debug_data.get("attempts", [])))
			if preview.length() > 200:
				preview = preview.left(200) + "..."
			if status != "":
				debug_summary = " [HTTP " + status + "] " + preview
			else:
				debug_summary = " " + preview
			print("[IMG_CLIENT_DEBUG] status=", status,
				"  content_type=", str(debug_data.get("content_type", "")),
				"  exception=", str(debug_data.get("exception", "")))
			if debug_data.has("response_preview"):
				print("[IMG_CLIENT_DEBUG] response_preview=", str(debug_data.get("response_preview", "")).left(400))
			if debug_data.has("request"):
				print("[IMG_CLIENT_DEBUG] request=", JSON.stringify(debug_data.get("request", {})))
		print("图片生成失败：" + error_msg + debug_summary)
		scene._bg_debug("img callback failed, error=" + error_msg + debug_summary)
		if callback_site.begins_with("NPC:"):
			var svc_fail_npc = callback_site.trim_prefix("NPC:")
			if scene.npcs.has(svc_fail_npc) and scene.npcs[svc_fail_npc] is Dictionary:
				scene.npcs[svc_fail_npc]["portrait_generating"] = false
		if scene._is_retryable_image_error(response_code, error_msg) and scene._queue_image_retry(inflight_req, error_msg):
			scene._drain_pending_img()
			return
		if scene.pending_site_update:
			scene.pending_site_update = false
			scene.site_update()
		elif scene.site_loading_lock:
			scene.site_update(true, true, false)
		scene._drain_pending_img()
