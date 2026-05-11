extends RefCounted
class_name GameEntityRuntimeUtils

static func initiate_transaction(scene: Node, item_name: String, quantity: int, price: int, is_total: bool = false) -> void:
	await scene._ensure_item_profile_record_before_trade(item_name)
	var price_label = ("总价" + str(price)) if is_total else (str(price) + "每件")
	var seller_name = "附近商贩"
	if scene.currentNpc != null:
		seller_name = str(scene.currentNpc.npcName)
	scene.addLog("<" + seller_name + "想要以" + price_label + "出售" + str(item_name) + "X" + str(quantity) + ">")
	scene._remember_important_event("<交易提议>" + seller_name + "提出交易：" + str(item_name) + "x" + str(quantity) + "，报价" + price_label + "。", scene.currentSiteName, seller_name)
	scene.get_node("%event").got_deal_event(item_name, quantity, price, is_total)
	scene.refresh_interaction_locks()

static func got_items(scene: Node, item_name: String, quantity: int) -> void:
	await scene._ensure_item_profile_record_before_trade(item_name)
	var giver_name = "对方"
	if scene.currentNpc != null:
		giver_name = str(scene.currentNpc.npcName)
	scene.get_node("%event").got_gift_event(item_name, quantity)
	scene.addLog("<" + giver_name + "想送你" + str(item_name) + "X" + str(quantity) + ">")
	scene._remember_important_event("<赠送提议>" + giver_name + "提出赠送：" + str(item_name) + "x" + str(quantity) + "。", scene.currentSiteName, giver_name)
	scene.refresh_interaction_locks()

static func consume_items(scene: Node, item_name: String, quantity: int) -> void:
	if quantity <= 0:
		return
	var money_aliases = ["钱", "金币", "资产", "现金"]
	var is_money_action = false
	for alias in money_aliases:
		if item_name.find(alias) != -1:
			is_money_action = true
			break
	if !is_money_action:
		var _exists_in_bag = false
		for _child in scene.get_node("%itemContainer").get_children():
			if _child is item and str(_child.item_name) == item_name:
				_exists_in_bag = true
				break
		if !_exists_in_bag:
			scene.addLog("<物品使用被拦截：背包中没有「" + item_name + "」，操作已忽略>")
			return
	if is_money_action:
		if scene.money < quantity:
			var fail_msg = await scene._generate_validation_dialogue(
				"玩家想从背包里拿出" + str(quantity) + "块钱，但当前资产只有" + str(scene.money) + "块钱。请给一句失败反馈。",
				"你掏了掏背包，但是里面只有" + str(scene.money) + "块钱。"
			)
			scene.addLog("<" + fail_msg + ">")
			await scene.changeTextTo(scene.response_label, fail_msg)
			return
		scene.money -= quantity
		scene.player_update()
		scene.addLog("<你拿出了" + str(quantity) + "块钱，剩余" + str(scene.money) + "块钱>")
		return
	await scene._ensure_item_profile_record_before_trade(item_name)
	var consume_result: Dictionary = scene.get_node("%itemContainer").consume_item(item_name, quantity)
	if !consume_result.get("success", false):
		var available = int(consume_result.get("available", 0))
		var fail_fallback = "你翻找背包，" + str(item_name) + "只剩" + str(available) + "个，不够拿出" + str(quantity) + "个。"
		var scene_context = "玩家想从背包拿出" + str(quantity) + "个" + str(item_name) + "，但只剩" + str(available) + "个。请给一句失败反馈。"
		if consume_result.get("reason", "") == "missing":
			fail_fallback = "你翻找背包，没有找到" + str(item_name) + "。"
			scene_context = "玩家想从背包拿出" + str(item_name) + "，但背包里没有该物品。请给一句失败反馈。"
		var fail_msg2 = await scene._generate_validation_dialogue(scene_context, fail_fallback)
		scene.addLog("<" + fail_msg2 + ">")
		await scene.changeTextTo(scene.response_label, fail_msg2)
		return
	scene.addLog("<你失去了" + str(item_name) + "X" + str(quantity) + ">")

static func create_location(scene: Node, path: String) -> void:
	var raw_sites = path.split("-", false)
	var new_sites: Array = []
	for site_name in raw_sites:
		var cleaned = scene._resolve_site_alias(str(site_name).strip_edges())
		cleaned = scene._extract_compact_entity_candidate(cleaned, 16)
		if cleaned != "" and scene._is_valid_generated_location_name(cleaned) and !new_sites.has(cleaned):
			new_sites.append(cleaned)
	if new_sites.is_empty():
		return
	if !scene.sites.has(scene.currentSiteName):
		scene.sites[scene.currentSiteName] = {"能前往的地点": [], "npc": {}}
	elif !scene.sites[scene.currentSiteName].has("能前往的地点"):
		scene.sites[scene.currentSiteName]["能前往的地点"] = []
	var chain: Array = new_sites.duplicate()
	if chain[0] != scene.currentSiteName:
		chain.push_front(scene.currentSiteName)
	if chain.size() < 2:
		return
	for i in range(chain.size() - 1):
		var from_site = str(chain[i])
		var to_site = str(chain[i + 1])
		if !scene.sites.has(from_site):
			scene.sites[from_site] = {"能前往的地点": [], "npc": {}}
		elif !scene.sites[from_site].has("能前往的地点"):
			scene.sites[from_site]["能前往的地点"] = []
		if !scene.sites[from_site]["能前往的地点"].has(to_site):
			scene.sites[from_site]["能前往的地点"].append(to_site)
			scene._save_site_json(from_site, scene.sites[from_site])
	if chain.size() == 2:
		scene.addLog("<地图更新：发现了" + str(chain[1]) + ">")
	else:
		scene.addLog("<地图更新：发现了前往" + str(chain[-1]) + "的路：" + path + ">")
	var next_site = str(chain[1])
	var has_button = false
	for btn in scene.get_node("%site_buttons").get_children():
		if btn is siteButton and btn.siteName == next_site:
			has_button = true
			break
	if !has_button and next_site != scene.currentSiteName:
		var new_site_button = load("res://fabs/site_button.tscn").instantiate() as siteButton
		new_site_button.siteName = next_site
		scene.get_node("%site_buttons").add_child(new_site_button)

static func create_NPC(scene: Node, npc_name: String, location: String, npc_describe: String) -> void:
	npc_name = scene._sanitize_generated_npc_name(npc_name)
	npc_name = scene._extract_compact_entity_candidate(npc_name, 12)
	if !scene._is_valid_generated_npc_name(npc_name) and scene._is_relation_npc_query(scene.last_dialogue_input):
		npc_name = scene._fallback_relation_npc_name(scene.last_dialogue_input)
	npc_name = scene._extract_compact_entity_candidate(npc_name, 12)
	if !scene._is_valid_generated_npc_name(npc_name):
		return
	if npc_name == "" or scene.dead_npc_names.has(npc_name):
		return
	var location_text = "世界某处"
	if location != "":
		location = scene._extract_compact_entity_candidate(location, 16)
		if !scene._is_valid_generated_location_name(location):
			location = scene.currentSiteName
		location_text = location
	if !scene.npcs.has(npc_name) or !(scene.npcs[npc_name] is Dictionary):
		scene.npcs[npc_name] = {"npc_describe": npc_describe, "npc_log": [], "特征": "", "important_events": []}
	else:
		if !scene.npcs[npc_name].has("npc_describe") or str(scene.npcs[npc_name].get("npc_describe", "")).strip_edges() == "":
			scene.npcs[npc_name]["npc_describe"] = npc_describe
		if !scene.npcs[npc_name].has("npc_log") or !(scene.npcs[npc_name]["npc_log"] is Array):
			scene.npcs[npc_name]["npc_log"] = []
		if !scene.npcs[npc_name].has("important_events") or !(scene.npcs[npc_name]["important_events"] is Array):
			scene.npcs[npc_name]["important_events"] = []
	if location != "":
		if !scene.sites.has(location) or !(scene.sites[location] is Dictionary):
			scene.sites[location] = {"能前往的地点": [], "npc": {}, "地点名称": location, "地点描述": "", "英文描述": ""}
		if !scene.sites[location].has("npc") or !(scene.sites[location]["npc"] is Dictionary):
			scene.sites[location]["npc"] = {}
		scene.sites[location]["npc"][npc_name] = npc_describe
		if location == scene.currentSiteName:
			scene.site_update()
	var heard_text = "你听说" + location_text + "有位" + str(npc_describe) + "：" + str(npc_name)
	scene.addLog("<" + heard_text + ">")
	var source_npc = ""
	if scene.currentNpc != null:
		source_npc = str(scene.currentNpc.npcName)
	var memory_text = "<NPC情报>" + heard_text
	if source_npc != "":
		memory_text += "（消息来源：" + source_npc + "）"
	scene._remember_important_event(memory_text, location, source_npc)
	var target_log: Array = scene.npcs[npc_name]["npc_log"]
	var target_note = "系统记录：有人在" + location_text + "提及了你的信息【" + str(npc_describe) + "】。"
	if !target_log.has(target_note):
		target_log.append(target_note)
	scene.npcs[npc_name]["npc_log"] = target_log

static func queue_action_confirm(scene: Node, action_data: Dictionary) -> void:
	if action_data.is_empty():
		return
	var action_text = str(action_data.get("action", "")).strip_edges()
	if action_text == "":
		return
	var actor = str(action_data.get("actor", "")).strip_edges()
	if actor == "":
		if scene.currentNpc != null:
			actor = str(scene.currentNpc.npcName)
		else:
			actor = "对方"
	scene.pending_action_confirm = {
		"action": action_text,
		"prompt": str(action_data.get("prompt", "是否执行行动：" + action_text + "？")),
		"actor": actor,
		"mode": str(action_data.get("mode", "player_execute"))
	}
	scene._set_event_flow_lock(true)
	scene.get_node("%event").got_action_confirm_event(str(scene.pending_action_confirm.get("action", "")), str(scene.pending_action_confirm.get("prompt", "")))

static func append_event_memories_to_npc_log(scene: Node, npc_name: String) -> void:
	if !scene.npcs.has(npc_name):
		return
	if !scene.npcs[npc_name].has("npc_log") or !(scene.npcs[npc_name]["npc_log"] is Array):
		scene.npcs[npc_name]["npc_log"] = []
	if !scene.npcs[npc_name].has("important_events") or !(scene.npcs[npc_name]["important_events"] is Array):
		scene.npcs[npc_name]["important_events"] = []
	var arr: Array = scene.npcs[npc_name]["npc_log"]
	var npc_events: Array = scene.npcs[npc_name]["important_events"]
	if !npc_events.is_empty():
		var start_idx = max(0, npc_events.size() - 4)
		for i in range(start_idx, npc_events.size()):
			var event_row = npc_events[i]
			if !(event_row is Dictionary):
				continue
			var view_text = str(event_row.get("npc_view", "")).strip_edges()
			if view_text == "":
				continue
			var note = "重要事件：" + view_text
			if !arr.has(note):
				arr.append(note)
		scene.npcs[npc_name]["npc_log"] = arr
		return
	var mems = scene._get_recent_related_event_memories(scene.currentSiteName, npc_name, 3)
	if mems.is_empty():
		return
	for m in mems:
		if !(m is Dictionary):
			continue
		var note2 = "重要事件：" + str(m.get("text", ""))
		if !arr.has(note2):
			arr.append(note2)
	scene.npcs[npc_name]["npc_log"] = arr

static func maybe_offer_intent_confirm_from_dialogue(scene: Node, reply_text: String) -> void:
	if scene._has_active_event_panel():
		return
	if scene._npc_reply_accepts_request(reply_text):
		var inferred_req = scene._extract_npc_action_request(reply_text)
		if !inferred_req.is_empty():
			scene._queue_action_confirm(inferred_req)
			return
	if !scene._npc_refused_request(reply_text):
		return
	var user_req = scene._extract_player_directed_request(scene.last_dialogue_input)
	if user_req == "":
		return
	var npc_name = "对方"
	var npc_desc = ""
	if scene.currentNpc != null:
		npc_name = str(scene.currentNpc.npcName)
		npc_desc = str(scene.currentNpc.npcDescribe)
	if !scene._can_force_request_on_npc(npc_name, npc_desc, user_req):
		return
	scene._queue_action_confirm({
		"action": "强行要求" + npc_name + user_req,
		"prompt": npc_name + "拒绝了你的要求。是否强硬执行：让TA" + user_req + "？",
		"actor": npc_name,
		"mode": "force_execute"
	})

static func auto_handle_action_search(scene: Node, action_input: String, action_reply: String) -> void:
	var input_text = action_input.strip_edges()
	if input_text == "":
		return
	if !(input_text.find("寻找") != -1 or input_text.find("找") != -1):
		return
	var fail_tokens = ["没找到", "没有找到", "未找到", "找不到", "这里没有", "不存在", "并没有", "没有这样", "没有对应", "无法找到"]
	for t in fail_tokens:
		if action_reply.find(t) != -1:
			return
	var target = input_text
	if target.find("寻找") != -1:
		target = target.substr(target.find("寻找") + 2)
	elif target.find("找") != -1:
		target = target.substr(target.find("找") + 1)
	target = target.replace("。", "").replace("，", "").replace("!", "").replace("？", "").strip_edges()
	target = scene._sanitize_generated_npc_name(target)
	target = scene._extract_compact_entity_candidate(target, 16)
	if target != "" and action_reply.find("没有" + target) != -1:
		return
	if target == "":
		return
	if !scene._is_valid_generated_npc_name(target):
		var maybe_loc = scene._is_valid_generated_location_name(target)
		if !maybe_loc and scene._is_relation_npc_query(action_input):
			target = scene._fallback_relation_npc_name(action_input)
			target = scene._extract_compact_entity_candidate(target, 12)
	if !scene._is_valid_generated_npc_name(target) and !scene._is_valid_generated_location_name(target):
		return
	if !scene._is_valid_generated_npc_name(target) and scene._is_relation_npc_query(action_input):
		target = scene._fallback_relation_npc_name(action_input)
	if target == "" or scene.dead_npc_names.has(target):
		return
	var location_hints = ["楼", "馆", "店", "部", "室", "场", "食堂", "宿舍", "图书馆", "超市", "办公室", "校门"]
	var is_location = false
	for hint in location_hints:
		if target.find(hint) != -1:
			is_location = true
			break
	if is_location:
		if !scene._is_valid_generated_location_name(target):
			return
		scene.create_location(scene.currentSiteName + "-" + target)
	else:
		if !scene._is_valid_generated_npc_name(target):
			return
		var npc_desc = "正在此地活动"
		if scene._is_relation_npc_query(action_input):
			npc_desc = scene._guess_related_npc_desc(action_input, str(scene.currentNpc.npcName) if scene.currentNpc != null else "")
		scene.create_NPC(target, scene.currentSiteName, npc_desc)

static func create_rumors(scene: Node, rumor_name: String, content: String) -> void:
	scene.rumors[rumor_name] = content
	scene.addLog("<传闻：" + str(rumor_name) + " - " + str(content) + ">")

static func update_reputation(scene: Node, quantity: int) -> void:
	var delta = clamp(quantity, -100, 100)
	if delta == 0:
		return
	scene.reputation = clamp(scene.reputation + float(delta), 0.0, 100.0)
	scene.player_update()
	if delta > 0:
		scene.addLog("<声望增加了：" + str(delta) + ">")
	else:
		scene.addLog("<声望减少了：" + str(abs(delta)) + ">")

static func set_time(scene: Node, hour: int, minute: int) -> float:
	var target = float(hour * 60 + minute)
	var current_in_day = fmod(scene.nowtime, 1440.0)
	var delta = target - current_in_day
	if delta <= 0.0:
		delta += 1440.0
	var rec = scene.advance_time_minutes(delta)
	scene.addLog("<时间跳跃至 %02d:%02d>" % [hour, minute])
	return float(rec.get("hours", 0.0))

static func destroy_yourself(scene: Node, npc_name_hint: String = "") -> void:
	var npc_name = str(npc_name_hint).strip_edges()
	if npc_name == "":
		if scene.currentNpc == null:
			return
		npc_name = str(scene.currentNpc.npcName)
	if !scene.dead_npc_names.has(npc_name):
		scene.dead_npc_names.append(npc_name)
	if scene.npcs.has(npc_name):
		scene.npcs.erase(npc_name)
	for site_key in scene.sites.keys():
		if !(scene.sites[site_key] is Dictionary):
			continue
		if !scene.sites[site_key].has("npc") or !(scene.sites[site_key]["npc"] is Dictionary):
			continue
		scene.sites[site_key]["npc"].erase(npc_name)
		scene._save_site_json(str(site_key), scene.sites[site_key])
	scene.addLog("<" + npc_name + "离开了，也许再也见不到了...>")
	for i in scene.get_node("%npc_buttons").get_children():
		if i is npcButton and i.npcName == npc_name:
			i.queue_free()
	if scene.currentNpc != null and str(scene.currentNpc.npcName) == npc_name:
		await scene.changeStateInto(scene.worldState.explore)

static func add_item(scene: Node, itemToAdd, itemNum) -> void:
	if !scene.itemProfiles.has(itemToAdd):
		var disk_profile = scene._load_item_profile_json(itemToAdd)
		scene.itemProfiles[itemToAdd] = {
			"description": disk_profile.get("description", "正在生成物品介绍..."),
			"image_prompt": disk_profile.get("image_prompt", "single game inventory item icon of " + str(itemToAdd) + ", clean background, centered"),
			"value": int(disk_profile.get("value", 50)),
			"rarity": str(disk_profile.get("rarity", "common")),
			"effect_type": str(disk_profile.get("effect_type", "none")),
			"effect_value": int(disk_profile.get("effect_value", 0)),
			"texture": null,
			"is_generating": false,
			"is_ready": false
		}
	scene.get_node("%itemContainer").add_item(
		itemToAdd,
		itemNum,
		scene.itemProfiles[itemToAdd].get("texture", null),
		scene.itemProfiles[itemToAdd].get("description", "正在生成物品介绍..."),
		scene.itemProfiles[itemToAdd].get("effect_type", "none"),
		int(scene.itemProfiles[itemToAdd].get("effect_value", 0))
	)
	scene.ensure_item_profile_async(itemToAdd)

static func use_item(scene: Node, item_name: String) -> Dictionary:
	if !scene.itemProfiles.has(item_name):
		return {"ok": false, "message": "你不知道这个物品的用途。"}
	var consume_result: Dictionary = scene.get_node("%itemContainer").consume_item(item_name, 1)
	if !consume_result.get("success", false):
		return {"ok": false, "message": "背包里没有可用的" + str(item_name) + "。"}
	var profile: Dictionary = scene.itemProfiles.get(item_name, {})
	var effect_type = str(profile.get("effect_type", "none"))
	var effect_value = int(profile.get("effect_value", 0))
	var msg = "你使用了" + str(item_name) + "。"
	match effect_type:
		"energy_restore":
			scene.energy = clamp(scene.energy + effect_value, 0.0, 100.0)
			msg = "你使用了" + str(item_name) + "，体力+" + str(effect_value)
		"hp_restore":
			scene.hp = clamp(scene.hp + effect_value, 0.0, 100.0)
			msg = "你使用了" + str(item_name) + "，健康+" + str(effect_value)
		"both_restore":
			scene.energy = clamp(scene.energy + effect_value, 0.0, 100.0)
			scene.hp = clamp(scene.hp + int(round(effect_value * 0.6)), 0.0, 100.0)
			msg = "你使用了" + str(item_name) + "，体力与健康都恢复了一些"
		_:
			msg = "你使用了" + str(item_name) + "，似乎没有明显效果。"
	scene.player_update()
	scene.addLog("<" + msg + ">")
	return {"ok": true, "message": msg}
