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

static func apply_direct_npc_tool_tags(scene: Node, reply: String) -> bool:
	var tags = scene._extract_angle_tags(reply)
	if tags.is_empty():
		return false
	var handled_any = false
	var only_location_tags = true
	for raw_tag in tags:
		var normalized = str(raw_tag).replace("：", ":").strip_edges()
		if normalized.begins_with("创建路径:"):
			var path = normalized.trim_prefix("创建路径:").strip_edges()
			if path != "":
				scene.create_location(path)
				handled_any = true
		elif normalized.begins_with("声望值"):
			var rep_text = normalized.trim_prefix("声望值").strip_edges()
			if rep_text != "":
				var rep_change = int(rep_text)
				scene.update_reputation(rep_change)
				handled_any = true
		else:
			only_location_tags = false
	return handled_any and only_location_tags

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

static func try_create_location_from_dialogue(scene: Node, reply: String) -> bool:
	if scene.last_dialogue_input == "":
		return false
	if _is_nonhuman_actor(scene):
		return false
	if !scene._is_location_query_dialogue(scene.last_dialogue_input):
		return false
	var fail_words = ["不知道", "不清楚", "没听说", "找不到", "不在这", "不确定", "没去过", "不认识路", "不晓得"]
	var has_location_clue = reply_has_location_clue(scene, reply)
	for w in fail_words:
		if reply.find(w) != -1 and !has_location_clue:
			return false
	var target = extract_location_target_from_dialogue(scene, scene.last_dialogue_input)
	if target == "":
		return false
	target = GameEntityUtils.extract_compact_entity(target, 16)
	if scene._looks_like_person_reference(GameEntityUtils.cleanup_location_candidate(target)):
		return false
	if !GameEntityUtils.is_valid_location_name_basic(target):
		return false
	if scene._resolve_site_alias(target) == scene.currentSiteName:
		return false
	if !has_location_clue:
		return false
	scene.create_location(scene.currentSiteName + "-" + target)
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

static func maybe_create_related_npc_from_dialogue(scene: Node, reply: String) -> void:
	if scene.currentNpc == null:
		return
	if _is_nonhuman_actor(scene):
		return
	if scene.last_dialogue_input == "" or !scene._is_relation_npc_query(scene.last_dialogue_input):
		return
	var fail_words = ["没有", "不知道", "不清楚", "记不清", "不认识", "没听说", "不方便说"]
	for w in fail_words:
		if reply.find(w) != -1:
			return
	var names = extract_named_people_from_dialogue(scene, reply)
	if names.is_empty():
		var fallback_name = GameEntityUtils.fallback_relation_npc_name(scene.last_dialogue_input)
		if !GameEntityUtils.is_bad_npc_name(fallback_name):
			names.append(fallback_name)
	if names.is_empty():
		return
	var guessed_desc = GameNpcInferUtils.guess_related_npc_desc(GameTextUtils.normalize_single_line_input(scene.last_dialogue_input), str(scene.currentNpc.npcName))
	var reply_hint = scene.process_string(reply).strip_edges()
	if reply_hint.length() > 30:
		reply_hint = reply_hint.left(30)
	if reply_hint != "":
		guessed_desc += "（线索：" + reply_hint + "）"
	var loc = extract_location_name_from_reply(scene, reply)
	if loc == "":
		loc = scene.currentSiteName
	var created = 0
	for raw_name in names:
		var npc_name = GameEntityUtils.sanitize_npc_name(str(raw_name))
		npc_name = GameEntityUtils.extract_compact_entity(npc_name, 12)
		if !GameEntityUtils.is_valid_npc_name(npc_name) and scene._is_relation_npc_query(scene.last_dialogue_input):
			npc_name = GameEntityUtils.fallback_relation_npc_name(scene.last_dialogue_input)
		if !GameEntityUtils.is_valid_npc_name(npc_name):
			continue
		if npc_name == "" or scene.npcs.has(npc_name) or scene.dead_npc_names.has(npc_name):
			continue
		if loc != "" and !scene._looks_like_person_reference(GameEntityUtils.cleanup_location_candidate(loc)) and GameEntityUtils.is_valid_location_name_basic(loc) and !scene.sites.has(loc):
			scene.create_location(scene.currentSiteName + "-" + loc)
		scene.create_NPC(npc_name, loc, guessed_desc)
		created += 1
		if created >= 2:
			break

static func maybe_create_unknown_npc_from_dialogue(scene: Node, reply: String) -> void:
	if scene.last_dialogue_input == "":
		return
	if _is_nonhuman_actor(scene):
		return
	var target_name = GameEntityUtils.extract_unknown_npc_target_from_query(scene.last_dialogue_input)
	if target_name == "":
		return
	if scene.npcs.has(target_name) or scene.dead_npc_names.has(target_name):
		return
	var fail_words = ["不知道", "不清楚", "没听说", "没有这个人", "不认识", "没见过"]
	for w in fail_words:
		if reply.find(w) != -1:
			return
	var loc = extract_location_name_from_reply(scene, reply)
	if loc == "":
		loc = scene.currentSiteName
	if loc == "":
		return
	if loc != "" and !scene._looks_like_person_reference(GameEntityUtils.cleanup_location_candidate(loc)) and GameEntityUtils.is_valid_location_name_basic(loc) and !scene.sites.has(loc):
		scene.create_location(scene.currentSiteName + "-" + loc)
	var source_hint = str(scene.last_dialogue_input).strip_edges()
	if source_hint.length() > 36:
		source_hint = source_hint.left(36)
	var desc = "在" + loc + "活动，与你打听的人物相关"
	if source_hint != "":
		desc += "（线索：" + source_hint + "）"
	scene.create_NPC(target_name, loc, desc)

static func npc_reply(scene: Node, reply: String) -> void:
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
	var direct_location_only = apply_direct_npc_tool_tags(scene, reply)
	if !direct_location_only:
		try_create_location_from_dialogue(scene, reply)
	maybe_create_related_npc_from_dialogue(scene, reply)
	maybe_create_unknown_npc_from_dialogue(scene, reply)
	var tools_texts = scene.get_content_in_angle_brackets(reply)
	print("提取出的工具信息：", tools_texts)
	if tools_texts != "" and !direct_location_only:
		var prompts = [
			{"role": "system", "content": scene.agent_prompt},
			{"role": "user", "content": tools_texts}
		]
		await scene.ask_ai(prompts, scene.aiMode.tools)
	elif tools_texts == "" and scene._needs_tool_inference_from_context(scene.last_dialogue_input, reply):
		var infer_prompts = [
			{"role": "system", "content": scene.agent_prompt + "\n若输入没有<>标签，也要从语义中尽力提取买卖、赠送、交付、协助执行等可执行方法；如果确实没有再回复没有方法被调用。"},
			{"role": "user", "content": "玩家输入：" + scene.last_dialogue_input + "\nNPC回复：" + reply}
		]
		await scene.ask_ai(infer_prompts, scene.aiMode.tools)
	await scene._auto_apply_action_effects("", reply, tools_texts)
	if !scene._has_active_event_panel():
		var action_req = scene._extract_npc_action_request(reply)
		if !action_req.is_empty():
			scene._queue_action_confirm(action_req)
		else:
			scene._maybe_offer_intent_confirm_from_dialogue(reply)
