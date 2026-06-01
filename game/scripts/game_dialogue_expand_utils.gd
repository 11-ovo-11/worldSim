extends RefCounted
class_name GameDialogueExpandUtils

static func looks_like_person_reference(npcs: Dictionary, target: String) -> bool:
	if target == "":
		return false
	if npcs.has(target):
		return true
	var person_words = ["同学", "老师", "阿姨", "大叔", "叔叔", "学长", "学姐", "室友", "店员", "保安", "路人", "女儿", "儿子", "父亲", "母亲", "爸爸", "妈妈", "兄弟", "姐妹", "同事", "上司", "下属"]
	if target.begins_with("你的") or target.begins_with("我的") or target.begins_with("他的") or target.begins_with("她的") or target.begins_with("自己的"):
		return true
	for w in person_words:
		if target.find(w) != -1:
			return true
	return false

static func apply_direct_npc_tool_tags(scene: Node, reply: String) -> Dictionary:
	var tags = scene._extract_angle_tags(reply)
	if tags.is_empty():
		return {"handled_any": false, "only_location_tags": false, "handled_tags": []}
	var handled_any = false
	var only_location_tags = true
	var handled_tags: Array = []
	for raw_tag in tags:
		var normalized = str(raw_tag).replace("：", ":").strip_edges()
		if normalized.begins_with("创建路径:"):
			var path = normalized.trim_prefix("创建路径:").strip_edges()
			if path != "":
				scene.create_location(path)
				handled_any = true
				handled_tags.append(normalized)
		elif normalized.begins_with("声望值"):
			var rep_text = normalized.trim_prefix("声望值").strip_edges()
			if rep_text != "":
				var rep_change = int(rep_text)
				scene.update_reputation(rep_change)
				handled_any = true
				handled_tags.append(normalized)
		else:
			only_location_tags = false
	return {"handled_any": handled_any, "only_location_tags": handled_any and only_location_tags, "handled_tags": handled_tags}

static func extract_location_target_from_dialogue(scene: Node, input_text: String) -> String:
	var t = GameTextUtils.normalize_single_line_input(input_text)
	if t == "":
		return ""
	var regex = RegEx.new()
	var patterns = [
		"(?:去|到)([^，。！？?]{1,24})(?:怎么走|怎么去|怎么到|在哪|在哪里|在哪儿)",
		"(?:怎么去|怎么到)([^，。！？?]{1,24})",
		"([^，。！？?]{1,24})(?:在哪|在哪里|在哪儿)",
		"([^，。！？?]{1,24})(?:路线|路怎么走|哪条路)"
	]
	for p in patterns:
		if regex.compile(p) != OK:
			continue
		var m = regex.search(t)
		if m == null:
			continue
		var candidate = GameEntityUtils.cleanup_location_candidate(str(m.get_string(1)))
		if candidate.length() < 2 or candidate.length() > 20:
			continue
		var reject_words = ["你", "我", "他", "她", "它", "这里", "那里", "哪儿", "哪里", "什么", "怎么", "时候"]
		var bad = false
		for rw in reject_words:
			if candidate == rw:
				bad = true
				break
		if bad:
			continue
		if looks_like_person_reference(scene.npcs, candidate):
			continue
		return candidate
	return ""

static func reply_has_location_clue(scene: Node, reply_text: String) -> bool:
	var plain = scene.process_string(reply_text).strip_edges()
	if plain == "":
		return false
	for site_key in scene.sites.keys():
		var site_name = str(site_key).strip_edges()
		if site_name != "" and plain.find(site_name) != -1:
			return true
	var clue_words = ["在", "位于", "往", "沿着", "直走", "左转", "右转", "经过", "到", "前面", "后面", "旁边", "路线", "路上"]
	for w in clue_words:
		if plain.find(w) != -1:
			return true
	return false

static func _is_nonhuman_actor(scene: Node) -> bool:
	if scene.currentNpc == null:
		return false
	var desc = (str(scene.currentNpc.npcName) + " " + str(scene.currentNpc.npcDescribe)).strip_edges()
	if desc == "":
		return false
	var animal_words = ["猫", "狗", "乌龟", "鹦鹉", "马", "牛", "羊", "猪", "鸟", "兔", "狐狸"]
	var humanized_words = ["会说话", "拟人", "人形", "精怪", "妖", "变成人", "高智"]
	var has_animal = false
	for w in animal_words:
		if desc.find(w) != -1:
			has_animal = true
			break
	if !has_animal:
		return false
	for hw in humanized_words:
		if desc.find(hw) != -1:
			return false
	return true

static func _collect_location_candidate(scene: Node, reply: String) -> Dictionary:
	if scene.last_dialogue_input == "":
		return {}
	if _is_nonhuman_actor(scene):
		return {}
	if !scene._is_location_query_dialogue(scene.last_dialogue_input):
		return {}
	var fail_words = ["不知道", "不清楚", "没听说", "找不到", "不在这", "不确定", "没去过", "不认识路", "不晓得"]
	var has_location_clue = reply_has_location_clue(scene, reply)
	for w in fail_words:
		if reply.find(w) != -1 and !has_location_clue:
			return {}
	var target = extract_location_target_from_dialogue(scene, scene.last_dialogue_input)
	if target == "":
		return {}
	target = GameEntityUtils.extract_compact_entity(target, 16)
	if scene._looks_like_person_reference(GameEntityUtils.cleanup_location_candidate(target)):
		return {}
	if !GameEntityUtils.is_valid_location_name_basic(target):
		return {}
	if scene._resolve_site_alias(target) == scene.currentSiteName:
		return {}
	if !has_location_clue:
		return {}
	return {
		"kind": "location",
		"name": target,
		"path": scene.currentSiteName + "-" + target,
		"context": scene.last_dialogue_input + "\n" + scene.process_string(reply).left(80)
	}

static func try_create_location_from_dialogue(scene: Node, reply: String) -> bool:
	var cand = _collect_location_candidate(scene, reply)
	if cand.is_empty():
		return false
	scene.create_location(str(cand.get("path", "")))
	return true

static func extract_location_name_from_reply(scene: Node, reply_text: String) -> String:
	var plain = scene.process_string(reply_text).strip_edges()
	if plain == "":
		return ""
	if plain.find("？") != -1 or plain.find("?") != -1:
		return ""
	for site_key in scene.sites.keys():
		var site_name = str(site_key).strip_edges()
		if site_name != "" and plain.find(site_name) != -1:
			return site_name
	var regex = RegEx.new()
	if regex.compile("(?:在|位于|住在)([\\p{Han}A-Za-z·]{2,16})") != OK:
		return ""
	var m = regex.search(plain)
	if m == null:
		return ""
	var loc = GameEntityUtils.extract_compact_entity(GameEntityUtils.cleanup_location_candidate(str(m.get_string(1))), 16)
	var reject_words = ["这里", "那里", "你家", "我家", "他们", "我们", "这个地方", "那边"]
	if reject_words.has(loc):
		return ""
	if scene._looks_like_person_reference(GameEntityUtils.cleanup_location_candidate(loc)):
		return ""
	if !GameEntityUtils.is_valid_location_name_basic(loc):
		return ""
	return loc

static func extract_named_people_from_dialogue(scene: Node, reply_text: String) -> Array:
	var plain = scene.process_string(reply_text).strip_edges()
	if plain == "":
		return []
	var names: Array = []
	var regex = RegEx.new()
	var patterns = [
		"(?:叫|名叫|名字是|是)([\\p{Han}A-Za-z·]{2,12})",
		"(?:有个|有位)([\\p{Han}A-Za-z·]{2,12})",
		"([\\p{Han}A-Za-z·]{2,12})(?:是我的|跟我|在)",
		"(?:他叫|她叫|我哥叫|我姐叫|我爸叫|我妈叫)([\\p{Han}A-Za-z·]{2,12})"
	]
	var reject_words = ["这里", "那里", "这个", "那个", "我们", "他们", "她们", "没有", "不知道", "不清楚", "路人", "前面", "后面", "左边", "右边", "附近", "那边", "这边"]
	for p in patterns:
		if regex.compile(p) != OK:
			continue
		for m in regex.search_all(plain):
			var n = GameEntityUtils.sanitize_npc_name(str(m.get_string(1)))
			if n == "":
				continue
			if scene.currentNpc != null and n == str(scene.currentNpc.npcName):
				continue
			if reject_words.has(n):
				continue
			if GameEntityUtils.is_bad_npc_name(n):
				continue
			if !names.has(n):
				names.append(n)
	return names

static func _collect_related_npc_candidates(scene: Node, reply: String) -> Array:
	if scene.currentNpc == null:
		return []
	if _is_nonhuman_actor(scene):
		return []
	if scene.last_dialogue_input == "":
		return []
	var relation_query = scene._is_relation_npc_query(scene.last_dialogue_input)
	var fail_words = ["没有", "不知道", "不清楚", "记不清", "不认识", "没听说", "不方便说"]
	for w in fail_words:
		if reply.find(w) != -1:
			return []
	var names = extract_named_people_from_dialogue(scene, reply)
	var loc = extract_location_name_from_reply(scene, reply)
	if !relation_query:
		if names.is_empty() or loc == "":
			return []
	if names.is_empty() and relation_query:
		var fallback_name = GameEntityUtils.fallback_relation_npc_name(scene.last_dialogue_input)
		if !GameEntityUtils.is_bad_npc_name(fallback_name):
			names.append(fallback_name)
	if names.is_empty():
		return []
	var guessed_desc = GameNpcInferUtils.guess_related_npc_desc(GameTextUtils.normalize_single_line_input(scene.last_dialogue_input), str(scene.currentNpc.npcName))
	var reply_hint = scene.process_string(reply).strip_edges()
	if reply_hint.length() > 30:
		reply_hint = reply_hint.left(30)
	if reply_hint != "":
		guessed_desc += "（线索：" + reply_hint + "）"
	if loc == "":
		loc = scene.currentSiteName
	var result: Array = []
	var added = 0
	for raw_name in names:
		var npc_name = GameEntityUtils.sanitize_npc_name(str(raw_name))
		npc_name = GameEntityUtils.extract_compact_entity(npc_name, 12)
		if !GameEntityUtils.is_valid_npc_name(npc_name) and scene._is_relation_npc_query(scene.last_dialogue_input):
			npc_name = GameEntityUtils.fallback_relation_npc_name(scene.last_dialogue_input)
		if !GameEntityUtils.is_valid_npc_name(npc_name):
			continue
		if npc_name == "" or scene.dead_npc_names.has(npc_name):
			continue
		var desc_to_use = guessed_desc
		if scene.npcs.has(npc_name) and scene.npcs[npc_name] is Dictionary:
			var existed_desc = str((scene.npcs[npc_name] as Dictionary).get("npc_describe", "")).strip_edges()
			if existed_desc != "":
				desc_to_use = existed_desc
		var loc_to_create = ""
		if loc != "" and !scene._looks_like_person_reference(GameEntityUtils.cleanup_location_candidate(loc)) and GameEntityUtils.is_valid_location_name_basic(loc) and !scene.sites.has(loc):
			loc_to_create = loc
		result.append({
			"kind": "npc",
			"name": npc_name,
			"location": loc,
			"desc": desc_to_use,
			"loc_to_create": loc_to_create,
			"context": scene.last_dialogue_input + "\n" + reply.left(80)
		})
		added += 1
		if added >= 2:
			break
	return result

static func maybe_create_related_npc_from_dialogue(scene: Node, reply: String) -> void:
	for cand in _collect_related_npc_candidates(scene, reply):
		_create_entity_from_candidate(scene, cand)

static func _collect_unknown_npc_candidate(scene: Node, reply: String) -> Dictionary:
	if scene.last_dialogue_input == "":
		return {}
	if _is_nonhuman_actor(scene):
		return {}
	var target_name = GameEntityUtils.extract_unknown_npc_target_from_query(scene.last_dialogue_input)
	if target_name == "":
		return {}
	if scene.npcs.has(target_name) or scene.dead_npc_names.has(target_name):
		return {}
	var fail_words = ["不知道", "不清楚", "没听说", "没有这个人", "不认识", "没见过"]
	for w in fail_words:
		if reply.find(w) != -1:
			return {}
	var loc = extract_location_name_from_reply(scene, reply)
	if loc == "":
		loc = scene.currentSiteName
	if loc == "":
		return {}
	var source_hint = str(scene.last_dialogue_input).strip_edges()
	if source_hint.length() > 36:
		source_hint = source_hint.left(36)
	var desc = "在" + loc + "活动，与你打听的人物相关"
	if source_hint != "":
		desc += "（线索：" + source_hint + "）"
	var loc_to_create = ""
	if !scene._looks_like_person_reference(GameEntityUtils.cleanup_location_candidate(loc)) and GameEntityUtils.is_valid_location_name_basic(loc) and !scene.sites.has(loc):
		loc_to_create = loc
	return {
		"kind": "npc",
		"name": target_name,
		"location": loc,
		"desc": desc,
		"loc_to_create": loc_to_create,
		"context": scene.last_dialogue_input + "\n" + reply.left(80)
	}

static func maybe_create_unknown_npc_from_dialogue(scene: Node, reply: String) -> void:
	var cand = _collect_unknown_npc_candidate(scene, reply)
	if !cand.is_empty():
		_create_entity_from_candidate(scene, cand)

static func _create_entity_from_candidate(scene: Node, cand: Dictionary) -> void:
	var kind = str(cand.get("kind", ""))
	var ctx = str(cand.get("context", "")).strip_edges()
	if kind == "location":
		var path = str(cand.get("path", ""))
		if path != "":
			scene.create_location(path)
	elif kind == "npc":
		var npc_name = str(cand.get("name", ""))
		var loc = str(cand.get("location", ""))
		if loc in ["这里", "这儿", "当前地点", "当前"]:
			loc = str(scene.currentSiteName)
		if loc == "":
			loc = str(scene.currentSiteName)
		var desc = str(cand.get("desc", ""))
		var loc_to_create = str(cand.get("loc_to_create", ""))
		if ctx != "":
			scene._track_pending_entity("npc", npc_name, {"context": ctx})
		if loc_to_create != "":
			scene.create_location(scene.currentSiteName + "-" + loc_to_create)
		scene.create_NPC(npc_name, loc, desc)

static func validate_and_create_entity_candidates(scene: Node, candidates: Array, full_context: String) -> void:
	if candidates.is_empty():
		return
	var confident: Array = []
	var need_ai: Array = []
	for cand in candidates:
		var kind = str(cand.get("kind", ""))
		var name = str(cand.get("name", ""))
		var ctx = str(cand.get("context", full_context))
		var inferred = GameEntityUtils.infer_entity_kind(name, ctx)
		if inferred == kind:
			confident.append(cand)
		elif inferred == "unknown":
			need_ai.append(cand)
	for cand in confident:
		_create_entity_from_candidate(scene, cand)
	if need_ai.is_empty():
		return
	var lines: Array = []
	lines.append("对话上下文：" + full_context.left(150))
	lines.append("")
	lines.append("请逐行判断（每行只回复是或否）：")
	for i in range(need_ai.size()):
		var cand = need_ai[i]
		var type_label = "人物" if str(cand.get("kind", "")) == "npc" else "地点"
		lines.append(str(i + 1) + ". 「" + str(cand.get("name", "")) + "」在上述对话中是否为" + type_label + "？")
	var prompts = [
		{"role": "system", "content": GamePrompts.ENTITY_VALIDATE_PROMPT},
		{"role": "user", "content": "\n".join(lines)}
	]
	scene.last_entity_validation_response = ""
	await scene.ask_ai(prompts, scene.aiMode.validate_entity)
	var val_text = str(scene.last_entity_validation_response).strip_edges()
	if val_text == "":
		for cand in need_ai:
			_create_entity_from_candidate(scene, cand)
		return
	var answers = val_text.replace("\r\n", "\n").replace("\r", "\n").split("\n", false)
	for i in range(need_ai.size()):
		if i >= answers.size():
			_create_entity_from_candidate(scene, need_ai[i])
			continue
		var ans = str(answers[i]).strip_edges()
		if ans.find("是") != -1 and ans.find("否") == -1:
			_create_entity_from_candidate(scene, need_ai[i])
		else:
			print("[实体验证] 跳过「", str(need_ai[i].get("name", "")), "」（AI判定非", str(need_ai[i].get("kind", "")), "）")

static func npc_reply(scene: Node, reply: String, model_tool_calls: Array = []) -> void:
	if scene.currentNpc == null or !is_instance_valid(scene.currentNpc):
		return
	var active_npc_name = str(scene.currentNpc.npcName).strip_edges()
	if active_npc_name == "":
		return
	scene.changeTextTo(scene.get_node("%speakerNameLabel"), active_npc_name)
	scene.changeTextTo(scene.response_label, scene.process_string(reply))
	if scene.currentNpc == null or !is_instance_valid(scene.currentNpc) or str(scene.currentNpc.npcName).strip_edges() != active_npc_name:
		return
	scene._record_current_chat_session("对话回复", active_npc_name, reply)
	scene.currentNpc.currentChat += active_npc_name + ":" + reply + "\n"
	scene._remember_important_event("<对话>" + active_npc_name + "：" + scene.process_string(reply), scene.currentSiteName, active_npc_name)
	var direct_tag_result = apply_direct_npc_tool_tags(scene, reply)
	var direct_location_only = bool(direct_tag_result.get("only_location_tags", false))
	var handled_direct_tags: Array = direct_tag_result.get("handled_tags", [])
	var entity_candidates: Array = []
	if !direct_location_only:
		var location_cand = _collect_location_candidate(scene, reply)
		if !location_cand.is_empty():
			entity_candidates.append(location_cand)
	for npc_cand in _collect_related_npc_candidates(scene, reply):
		entity_candidates.append(npc_cand)
	var unknown_cand = _collect_unknown_npc_candidate(scene, reply)
	if !unknown_cand.is_empty():
		entity_candidates.append(unknown_cand)
	var full_context = (str(scene.last_dialogue_input) + "\n" + scene.process_string(reply)).strip_edges()
	await validate_and_create_entity_candidates(scene, entity_candidates, full_context)
	var tools_texts = scene.get_content_in_angle_brackets(reply)
	var tool_hint = GameFlowRuntimeUtils.build_tool_call_hint_text(model_tool_calls)
	if tool_hint != "":
		tools_texts = (tools_texts + "\n" + tool_hint).strip_edges()
	print("提取出的工具信息：", tools_texts)
	await GameFlowRuntimeUtils.handle_model_tool_calls(scene, model_tool_calls, handled_direct_tags)
	if model_tool_calls.is_empty():
		var plain_reply = scene.process_string(reply)
		var should_fallback_infer = false
		if tools_texts.strip_edges() != "":
			should_fallback_infer = true
		elif GameNpcInferUtils.needs_tool_inference_from_context(str(scene.last_dialogue_input), plain_reply):
			should_fallback_infer = true
		if should_fallback_infer:
			await scene._request_tool_inference("dialogue", scene.last_dialogue_input, reply, tools_texts, handled_direct_tags)
	await scene._auto_apply_action_effects("", reply, tools_texts)
	if !scene._has_active_event_panel():
		var action_req = scene._extract_npc_action_request(reply)
		if !action_req.is_empty():
			scene._queue_action_confirm(action_req)
		else:
			scene._maybe_offer_intent_confirm_from_dialogue(reply)
