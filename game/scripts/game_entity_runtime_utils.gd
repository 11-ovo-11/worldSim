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
	var site_modifiers: Dictionary = {}
	for site_name in raw_sites:
		var raw_piece = str(site_name).strip_edges()
		if raw_piece == "":
			continue
		var cleaned = scene._resolve_site_alias(raw_piece)
		var split = scene._split_entity_with_modifier(cleaned, 16)
		var core_name = scene._extract_compact_entity_candidate(str(split.get("name", "")), 16)
		var modifier = str(split.get("modifier", "")).strip_edges()
		if core_name == "":
			continue
		var inferred_kind = scene._infer_entity_kind(core_name, path + " " + modifier)
		if inferred_kind == "npc" and scene._is_valid_generated_npc_name(core_name):
			var npc_desc = "在" + str(scene.currentSiteName) + "活动"
			if modifier != "":
				npc_desc += "（" + modifier + "）"
			scene._track_pending_entity("npc", core_name, {"location": str(scene.currentSiteName), "desc": npc_desc, "modifier": modifier, "source": "path_reclass"})
			scene.create_NPC(core_name, str(scene.currentSiteName), npc_desc)
			continue
		if !scene._is_valid_generated_location_name(core_name):
			continue
		if !new_sites.has(core_name):
			new_sites.append(core_name)
		if modifier != "":
			site_modifiers[core_name] = modifier
		scene._track_pending_entity("location", core_name, {"from": str(scene.currentSiteName), "modifier": modifier, "source": "path"})
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
			scene.sites[from_site] = {"能前往的地点": [], "npc": {}, "地点名称": from_site, "地点描述": "", "英文描述": ""}
		elif !scene.sites[from_site].has("能前往的地点"):
			scene.sites[from_site]["能前往的地点"] = []
		if !scene.sites[from_site]["能前往的地点"].has(to_site):
			scene.sites[from_site]["能前往的地点"].append(to_site)
			scene._save_site_json(from_site, scene.sites[from_site])
		if !scene.sites.has(to_site) or !(scene.sites[to_site] is Dictionary):
			scene.sites[to_site] = {"能前往的地点": [], "npc": {}, "地点名称": to_site, "地点描述": "", "英文描述": ""}
		if site_modifiers.has(to_site):
			var mod = str(site_modifiers[to_site]).strip_edges()
			if mod != "":
				var old_desc = str(scene.sites[to_site].get("地点描述", "")).strip_edges()
				if old_desc == "":
					scene.sites[to_site]["地点描述"] = "这里" + mod
				elif old_desc.find(mod) == -1:
					scene.sites[to_site]["地点描述"] = old_desc + "（" + mod + "）"
			scene._save_site_json(to_site, scene.sites[to_site])
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
	var npc_split = scene._split_entity_with_modifier(npc_name, 12)
	var npc_modifier = str(npc_split.get("modifier", "")).strip_edges()
	npc_name = scene._sanitize_generated_npc_name(str(npc_split.get("name", "")))
	npc_name = scene._extract_compact_entity_candidate(npc_name, 12)
	var name_kind = scene._infer_entity_kind(npc_name, npc_describe + " " + location + " " + npc_modifier)
	if name_kind == "location" and scene._is_valid_generated_location_name(npc_name):
		scene._track_pending_entity("location", npc_name, {"from": str(scene.currentSiteName), "modifier": npc_modifier, "source": "npc_reclass"})
		scene.create_location(str(scene.currentSiteName) + "-" + npc_name)
		return
	if !scene._is_valid_generated_npc_name(npc_name) and scene._is_relation_npc_query(scene.last_dialogue_input):
		npc_name = scene._fallback_relation_npc_name(scene.last_dialogue_input)
	npc_name = scene._extract_compact_entity_candidate(npc_name, 12)
	if !scene._is_valid_generated_npc_name(npc_name):
		if scene._is_valid_generated_location_name(npc_name):
			scene._track_pending_entity("location", npc_name, {"from": str(scene.currentSiteName), "modifier": npc_modifier, "source": "npc_invalid_reclass"})
			scene.create_location(str(scene.currentSiteName) + "-" + npc_name)
		return
	if npc_name == "" or scene.dead_npc_names.has(npc_name):
		return
	var location_text = "世界某处"
	var location_modifier = ""
	if location != "":
		var loc_split = scene._split_entity_with_modifier(location, 16)
		location_modifier = str(loc_split.get("modifier", "")).strip_edges()
		location = scene._extract_compact_entity_candidate(str(loc_split.get("name", "")), 16)
		if scene._infer_entity_kind(location, npc_describe + " " + location_modifier) == "npc":
			location = scene.currentSiteName
		if !scene._is_valid_generated_location_name(location):
			location = scene.currentSiteName
		location_text = location
	if location == "":
		location = scene.currentSiteName
		location_text = location
	var pending_row: Dictionary = {}
	if scene.pending_entity_records.has("npcs") and scene.pending_entity_records["npcs"] is Dictionary:
		var npc_pending: Dictionary = scene.pending_entity_records["npcs"]
		if npc_pending.has(npc_name) and npc_pending[npc_name] is Dictionary:
			pending_row = npc_pending[npc_name]
	if location == "" and !pending_row.is_empty():
		var pending_loc = str(pending_row.get("location", "")).strip_edges()
		if pending_loc != "":
			location = pending_loc
			location_text = pending_loc
	var final_desc = str(npc_describe).strip_edges()
	if final_desc == "" and !pending_row.is_empty():
		final_desc = str(pending_row.get("desc", "")).strip_edges()
	if final_desc == "":
		final_desc = "正在此地活动"
	var world_seed_hint = str(scene.world_seed_input).strip_edges()
	if world_seed_hint != "":
		var era_hint = world_seed_hint
		if era_hint.length() > 42:
			era_hint = era_hint.left(42)
		if final_desc.find(era_hint) == -1:
			final_desc += "（时代背景：" + era_hint + "）"
	if location != "" and scene.sites.has(location) and scene.sites[location] is Dictionary:
		var site_desc_hint = str(scene.sites[location].get("地点描述", "")).strip_edges()
		if site_desc_hint != "":
			if site_desc_hint.length() > 36:
				site_desc_hint = site_desc_hint.left(36)
			if final_desc.find(site_desc_hint) == -1:
				final_desc += "（活动地点特征：" + site_desc_hint + "）"
	if scene.has_method("_get_recent_related_event_memories"):
		var related_events = scene._get_recent_related_event_memories(location, npc_name, 2, {})
		if related_events is Array and !related_events.is_empty():
			var event_text = ""
			for row in related_events:
				if row is Dictionary:
					event_text = str(row.get("text", "")).strip_edges()
					if event_text != "":
						break
			if event_text != "":
				if event_text.length() > 44:
					event_text = event_text.left(44)
				if final_desc.find(event_text) == -1:
					final_desc += "（关联事件：" + event_text + "）"
	var pending_context = str(pending_row.get("context", "")).strip_edges()
	if pending_context != "":
		var ctx_snippet = pending_context.replace("\n", "；").strip_edges()
		if ctx_snippet.length() > 48:
			ctx_snippet = ctx_snippet.left(48)
		if ctx_snippet != "" and final_desc.find(ctx_snippet) == -1:
			final_desc += "（线索：" + ctx_snippet + "）"
	if npc_modifier != "" and final_desc.find(npc_modifier) == -1:
		final_desc += "（" + npc_modifier + "）"
	if location_modifier != "" and final_desc.find(location_modifier) == -1:
		final_desc += "（" + location_modifier + "）"
	scene._track_pending_entity("npc", npc_name, {"location": location, "desc": final_desc, "modifier": npc_modifier, "source": "create_npc"})
	if !scene.npcs.has(npc_name) or !(scene.npcs[npc_name] is Dictionary):
		scene.npcs[npc_name] = {"npc_describe": final_desc, "npc_log": [], "特征": "", "important_events": []}
	else:
		if !scene.npcs[npc_name].has("npc_describe") or str(scene.npcs[npc_name].get("npc_describe", "")).strip_edges() == "":
			scene.npcs[npc_name]["npc_describe"] = final_desc
		if !scene.npcs[npc_name].has("npc_log") or !(scene.npcs[npc_name]["npc_log"] is Array):
			scene.npcs[npc_name]["npc_log"] = []
		if !scene.npcs[npc_name].has("important_events") or !(scene.npcs[npc_name]["important_events"] is Array):
			scene.npcs[npc_name]["important_events"] = []
		if str(scene.npcs[npc_name].get("npc_describe", "")).find(final_desc) == -1:
			scene.npcs[npc_name]["npc_describe"] = final_desc
	if location != "":
		if !scene.sites.has(location) or !(scene.sites[location] is Dictionary):
			scene.sites[location] = {"能前往的地点": [], "npc": {}, "地点名称": location, "地点描述": "", "英文描述": ""}
		if !scene.sites[location].has("npc") or !(scene.sites[location]["npc"] is Dictionary):
			scene.sites[location]["npc"] = {}
		scene.sites[location]["npc"][npc_name] = final_desc
		if location_modifier != "":
			var site_desc = str(scene.sites[location].get("地点描述", "")).strip_edges()
			if site_desc == "":
				scene.sites[location]["地点描述"] = "这里" + location_modifier
			elif site_desc.find(location_modifier) == -1:
				scene.sites[location]["地点描述"] = site_desc + "（" + location_modifier + "）"
		scene._save_site_json(location, scene.sites[location])
		if location == scene.currentSiteName and !bool(scene.get_meta("hydrating_pending_entities", false)):
			if scene.currentState == scene.worldState.chat:
				var already_has_btn = false
				for btn in scene.get_node("%npc_buttons").get_children():
					if btn.has_method("get") and str(btn.get("npcName")).strip_edges() == npc_name:
						already_has_btn = true
						break
				if !already_has_btn and !scene.dead_npc_names.has(npc_name):
					var new_btn = load("res://fabs/npc_button.tscn").instantiate()
					new_btn.set("npcName", npc_name)
					scene.get_node("%npc_buttons").add_child(new_btn)
			else:
				scene.site_update()
	var heard_text = "你听说" + location_text + "有位" + str(final_desc) + "：" + str(npc_name)
	scene.addLog("<" + heard_text + ">")
	var source_npc = ""
	if scene.currentNpc != null:
		source_npc = str(scene.currentNpc.npcName)
	var memory_text = "<NPC情报>" + heard_text
	if source_npc != "":
		memory_text += "（消息来源：" + source_npc + "）"
	scene._remember_important_event(memory_text, location, source_npc)
	var target_log: Array = scene.npcs[npc_name]["npc_log"]
	var target_note = "系统记录：有人在" + location_text + "提及了你的信息【" + str(final_desc) + "】。"
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

static func _resolve_item_effect_fallback(item_name: String, profile: Dictionary) -> Dictionary:
	var desc_based = _infer_item_effect_from_description(
		item_name,
		str(profile.get("description", "")).strip_edges(),
		int(profile.get("value", 50))
	)
	if !desc_based.is_empty():
		return desc_based
	var effect_type = str(profile.get("effect_type", "")).strip_edges().to_lower()
	var effect_value = int(profile.get("effect_value", 0))
	if effect_type == "none":
		effect_type = ""
	if effect_type != "" and (effect_value > 0 or effect_type == "rumor_trigger"):
		return {"effect_type": effect_type, "effect_value": effect_value}
	var n = str(item_name).strip_edges()
	var val = max(6, int(round(max(1, int(profile.get("value", 50))) / 12.0)))
	if n.find("药") != -1 or n.find("绷带") != -1:
		return {"effect_type": "hp_restore", "effect_value": clamp(val, 8, 28)}
	if n.find("奶") != -1 or n.find("茶") != -1 or n.find("咖啡") != -1 or n.find("水") != -1 or n.find("饮") != -1:
		return {"effect_type": "energy_restore", "effect_value": clamp(val, 8, 24)}
	if n.find("券") != -1 or n.find("卡") != -1 or n.find("金币") != -1:
		return {"effect_type": "money_gain", "effect_value": clamp(val * 2, 10, 120)}
	if n.find("情报") != -1 or n.find("信") != -1 or n.find("地图") != -1:
		return {"effect_type": "rumor_trigger", "effect_value": 1}
	return {"effect_type": "both_restore", "effect_value": clamp(val, 6, 20)}

static func _infer_item_effect_from_description(item_name: String, description: String, value: int) -> Dictionary:
	var desc = str(description).strip_edges()
	if desc == "":
		return {}
	var base = max(5, int(round(max(1, value) / 12.0)))
	var severe = max(base, 10)
	var negative_health_tokens = ["有毒", "剧毒", "腐坏", "变质", "诅咒", "副作用", "灼烧", "刺痛", "恶臭", "污染", "不适", "头晕", "发烧", "呕吐"]
	for token in negative_health_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "hp_restore", "effect_value": -clamp(severe, 8, 28)}
	var negative_energy_tokens = ["嗜睡", "昏沉", "疲惫", "乏力", "困倦", "麻木", "眩晕"]
	for token in negative_energy_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "energy_restore", "effect_value": -clamp(severe, 8, 24)}
	var money_loss_tokens = ["押金", "手续费", "维护费", "保养费", "破财", "损耗资金", "需支付", "代价"]
	for token in money_loss_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "money_loss", "effect_value": clamp(severe * 2, 10, 120)}
	var rep_loss_tokens = ["违禁", "赃物", "偷来", "可疑", "通缉", "黑市", "失礼", "冒犯", "败坏名声"]
	for token in rep_loss_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "reputation_loss", "effect_value": clamp(severe, 6, 25)}
	var hp_tokens = ["治愈", "疗伤", "止血", "恢复健康", "修复", "愈合", "缓解疼痛", "消炎"]
	for token in hp_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "hp_restore", "effect_value": clamp(base, 8, 30)}
	var energy_tokens = ["提神", "补充体力", "恢复体力", "充能", "振奋", "醒脑", "驱困"]
	for token in energy_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "energy_restore", "effect_value": clamp(base, 8, 24)}
	var both_tokens = ["恢复状态", "全面恢复", "补给", "应急恢复", "恢复精力与健康"]
	for token in both_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "both_restore", "effect_value": clamp(base, 6, 20)}
	var money_gain_tokens = ["兑奖", "变现", "赏金", "可售", "现金奖励", "增值", "抵扣"]
	for token in money_gain_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "money_gain", "effect_value": clamp(base * 2, 10, 140)}
	var rep_gain_tokens = ["荣誉", "嘉奖", "表彰", "推荐信", "信誉", "体面", "正当身份"]
	for token in rep_gain_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "reputation_gain", "effect_value": clamp(base, 6, 25)}
	var affinity_tokens = ["礼物", "纪念", "安抚", "表达心意", "联络", "示好", "缓和关系"]
	for token in affinity_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "npc_affinity", "effect_value": max(1, int(round(base / 2.0)))}
	var rumor_tokens = ["线索", "情报", "地图", "密信", "传闻", "密码", "笔记"]
	for token in rumor_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "rumor_trigger", "effect_value": 1}
	var time_tokens = ["需要等待", "耗时", "发酵", "冷却", "长时间", "延时"]
	for token in time_tokens:
		if desc.find(token) != -1:
			return {"effect_type": "time_advance", "effect_value": clamp(base * 3, 10, 90)}
	if str(item_name).find("毒") != -1:
		return {"effect_type": "hp_restore", "effect_value": -clamp(severe, 8, 30)}
	return {}

static func request_item_use_ai_feedback(scene: Node, scene_context: String, fallback: String) -> void:
	var line = await scene._generate_validation_dialogue(scene_context, fallback)
	if str(line).strip_edges() == "":
		line = fallback
	if str(line).strip_edges() == "":
		return
	scene.changeTextTo(scene.get_node("%speakerNameLabel"), "【旁白】")
	scene.changeTextTo(scene.response_label, str(line))
	scene.addLog("<道具反馈：" + str(line) + ">")

static func use_item(scene: Node, item_name: String) -> Dictionary:
	if !scene.itemProfiles.has(item_name):
		return {"ok": false, "message": "你不知道这个物品的用途。"}
	var consume_result: Dictionary = scene.get_node("%itemContainer").consume_item(item_name, 1)
	if !consume_result.get("success", false):
		return {"ok": false, "message": "背包里没有可用的" + str(item_name) + "。"}
	var profile: Dictionary = scene.itemProfiles.get(item_name, {})
	var resolved_effect = _resolve_item_effect_fallback(item_name, profile)
	var effect_type = str(resolved_effect.get("effect_type", "both_restore"))
	var effect_value = int(resolved_effect.get("effect_value", 8))
	scene.itemProfiles[item_name]["effect_type"] = effect_type
	scene.itemProfiles[item_name]["effect_value"] = effect_value
	var disk_profile = scene._load_item_profile_json(item_name)
	if !disk_profile.is_empty():
		disk_profile["effect_type"] = effect_type
		disk_profile["effect_value"] = effect_value
		scene._save_item_profile_json(item_name, disk_profile)
	var msg = "你使用了" + str(item_name) + "。"
	var effect_summary = ""
	var target_name = str(scene.playerName).strip_edges()
	if target_name == "":
		target_name = "你自己"
	if scene.currentState == scene.worldState.chat and scene.currentNpc != null:
		target_name = str(scene.currentNpc.npcName).strip_edges()
		if target_name == "":
			target_name = "对话对象"
	match effect_type:
		"energy_restore":
			scene.energy = clamp(scene.energy + float(effect_value), 0.0, 100.0)
			effect_summary = "体力" + ("+" if effect_value >= 0 else "") + str(effect_value)
			msg = "你对" + target_name + "使用了" + str(item_name) + "，" + effect_summary
		"hp_restore":
			scene.hp = clamp(scene.hp + float(effect_value), 0.0, 100.0)
			effect_summary = "健康" + ("+" if effect_value >= 0 else "") + str(effect_value)
			msg = "你对" + target_name + "使用了" + str(item_name) + "，" + effect_summary
		"both_restore":
			scene.energy = clamp(scene.energy + float(effect_value), 0.0, 100.0)
			scene.hp = clamp(scene.hp + float(int(round(effect_value * 0.6))), 0.0, 100.0)
			if effect_value >= 0:
				effect_summary = "体力与健康恢复"
				msg = "你对" + target_name + "使用了" + str(item_name) + "，体力与健康都恢复了一些"
			else:
				effect_summary = "体力与健康受损"
				msg = "你对" + target_name + "使用了" + str(item_name) + "，状态明显变差"
		"money_gain":
			scene.money += max(1, effect_value)
			effect_summary = "资产+" + str(max(1, effect_value))
			msg = "你使用了" + str(item_name) + "，" + effect_summary
		"money_loss":
			var cost = min(scene.money, max(1, effect_value))
			scene.money -= cost
			effect_summary = "资产-" + str(cost)
			msg = "你使用了" + str(item_name) + "，" + effect_summary
		"reputation_gain":
			scene.reputation = clamp(scene.reputation + max(1, effect_value), 0.0, 100.0)
			effect_summary = "声望+" + str(max(1, effect_value))
			msg = "你使用了" + str(item_name) + "，" + effect_summary
		"reputation_loss":
			scene.reputation = clamp(scene.reputation - max(1, effect_value), 0.0, 100.0)
			effect_summary = "声望-" + str(max(1, effect_value))
			msg = "你使用了" + str(item_name) + "，" + effect_summary
		"time_advance":
			var mins = max(5, effect_value)
			scene.advance_time_minutes(float(mins), true)
			effect_summary = "时间推进" + str(mins) + "分钟"
			msg = "你使用了" + str(item_name) + "，" + effect_summary
		"npc_affinity":
			effect_summary = "关系升温"
			if scene.currentState == scene.worldState.chat and scene.currentNpc != null:
				scene._remember_important_event("<道具影响>你对" + target_name + "使用了「" + str(item_name) + "」，对方态度有所软化。", scene.currentSiteName, target_name)
				msg = "你对" + target_name + "使用了" + str(item_name) + "，对方态度明显缓和"
			else:
				msg = "你使用了" + str(item_name) + "，心态更加稳定"
		"rumor_trigger":
			var rumor_title = "关于" + str(item_name) + "的新线索"
			var rumor_content = "有人提到「" + str(item_name) + "」与" + str(scene.currentSiteName) + "有关。"
			scene.rumors[rumor_title] = rumor_content
			effect_summary = "触发新线索"
			msg = "你使用了" + str(item_name) + "，获得了一条新的传闻"
		_:
			scene.energy = clamp(scene.energy + max(6, effect_value), 0.0, 100.0)
			effect_summary = "体力恢复"
			msg = "你使用了" + str(item_name) + "，状态有所恢复"
	scene.player_update()
	scene.addLog("<" + msg + ">")
	var feedback_context = "玩家在地点「" + str(scene.currentSiteName) + "」使用道具「" + str(item_name) + "」，作用对象是「" + target_name + "」，效果为：" + effect_summary + "。请用15~35字给一句自然的结果反馈。"
	scene.call_deferred("_request_item_use_ai_feedback", feedback_context, msg)
	return {"ok": true, "message": msg}

static func gift_item(scene: Node, item_name: String) -> Dictionary:
	var key = str(item_name).strip_edges()
	if key == "":
		return {"ok": false, "message": "你还没有选定要赠送的物品。"}
	var consume_result: Dictionary = scene.get_node("%itemContainer").consume_item(key, 1)
	if !consume_result.get("success", false):
		return {"ok": false, "message": "背包里没有可赠送的" + key + "。"}
	var target_name = "路人"
	var in_chat = scene.currentState == scene.worldState.chat and scene.currentNpc != null
	if in_chat:
		target_name = str(scene.currentNpc.npcName).strip_edges()
		if target_name == "":
			target_name = "对方"
	var msg = "你把" + key + "赠送给了" + target_name
	if in_chat:
		scene._remember_important_event("<道具赠送>你向" + target_name + "赠送了「" + key + "x1」。", scene.currentSiteName, target_name)
	else:
		scene._remember_important_event("<道具赠送>你在" + str(scene.currentSiteName) + "将「" + key + "x1」赠送给路人。", scene.currentSiteName, "")
	scene.addLog("<" + msg + ">")
	var feedback_context = "玩家在地点「" + str(scene.currentSiteName) + "」将道具「" + key + "」赠送给「" + target_name + "」。请用15~35字给一句自然的结果反馈。"
	scene.call_deferred("_request_item_use_ai_feedback", feedback_context, msg)
	return {"ok": true, "message": msg}
