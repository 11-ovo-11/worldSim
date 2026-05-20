extends RefCounted
class_name GameInteractionRuntimeUtils

static func change_state_into(scene: Node, stateToChange) -> void:
	if scene.currentState == scene.worldState.chat:
		var switching_npc = stateToChange == scene.worldState.chat and scene.currentNpc != null and scene.newNpc != null and str(scene.currentNpc.npcName) != str(scene.newNpc.npcName)
		scene.changeTextTo(scene.response_label, "你结束了与" + scene.currentNpc.npcName + "的对话。", 100)
		await scene.currentNpc.sum_chat()
		if stateToChange != scene.worldState.chat or switching_npc:
			scene._end_chat_session()
	match stateToChange:
		scene.worldState.chat:
			scene.create_tween().tween_property(scene.get_node("%npcIcon"), "custom_minimum_size:x", 240, 0.2)
			if scene.currentNpc != null:
				scene.currentNpc.queue_free()
			scene.currentNpc = scene.newNpc
			scene.set_meta("npc_profile_open", false)
			scene.set_meta("npc_profile_prev_npc", "")
			scene.set_meta("npc_profile_prev_speaker", "")
			scene.set_meta("npc_profile_prev_text", "")
			if scene.get_node("%npcIcon") is TextureRect:
				(scene.get_node("%npcIcon") as TextureRect).texture = null
			scene._start_chat_session(str(scene.currentNpc.npcName))
			scene.currentNpc.start_chat()
			scene.changeTextTo(scene.response_label, "你走近了" + scene.currentNpc.npcName, 100)
			scene.changeTextTo(scene.get_node("%speakerNameLabel"), scene.playerName, 100)
			scene.addLog("你开始与" + scene.currentNpc.npcName + "交谈")
			scene.dialogue_container.visible = true
			var _cn = str(scene.currentNpc.npcName)
			var _cd = str(scene.currentNpc.npcDescribe)
			if scene.npcImgs.has(_cn) and scene.npcImgs[_cn] is Texture2D:
				if scene.get_node("%npcIcon") is TextureRect:
					(scene.get_node("%npcIcon") as TextureRect).texture = scene.npcImgs[_cn]
			else:
				var _cached_npc = scene._load_image_png(scene.NPC_IMG_DIR, _cn)
				if _cached_npc != null:
					scene.npcImgs[_cn] = _cached_npc
					if scene.get_node("%npcIcon") is TextureRect:
						(scene.get_node("%npcIcon") as TextureRect).texture = _cached_npc
				else:
					var _loc_hint = scene._infer_npc_location_for_prompt(_cn)
					var _np = scene._build_npc_image_prompt(_cn, _cd, _loc_hint)
					if _np != "":
						scene.gen_img(_np, "NPC:" + _cn)
		scene.worldState.explore:
			scene.create_tween().tween_property(scene.get_node("%npcIcon"), "custom_minimum_size:x", 0, 0.2)
			if scene.get_node("%npcIcon") is TextureRect:
				(scene.get_node("%npcIcon") as TextureRect).texture = null
			scene.changeTextTo(scene.get_node("%speakerNameLabel"), scene.playerName, 100)
			scene.dialogue_container.visible = false
			if scene.currentState == scene.worldState.chat and !scene.currentSiteName.is_empty():
				scene.site_update()
	scene.currentState = stateToChange
	scene.refresh_interaction_locks()
	scene.call_deferred("_focus_active_input")

static func force_exit_chat_runtime(scene: Node) -> void:
	if scene.currentNpc != null and is_instance_valid(scene.currentNpc):
		scene.currentNpc.queue_free()
	if scene.newNpc != null and is_instance_valid(scene.newNpc) and scene.newNpc != scene.currentNpc:
		scene.newNpc.queue_free()
	scene.currentNpc = null
	scene.newNpc = null
	scene.currentState = scene.worldState.explore
	scene.dialogue_container.visible = false
	scene.dialogue_input.text = ""
	scene.last_dialogue_input = ""
	scene.last_action_input = ""
	scene.last_crime_event_context = ""
	scene._end_chat_session()
	scene.clear_children(scene.get_node("%event"))
	scene._set_event_flow_lock(false)
	scene.refresh_interaction_locks()

static func start_chat_session(scene: Node, npc_name: String) -> void:
	var n = npc_name.strip_edges()
	if n == "":
		scene.current_chat_session_npc = ""
		scene.current_chat_session_records = []
		return
	if scene.current_chat_session_npc != n:
		scene.current_chat_session_npc = n
		scene.current_chat_session_records = []

static func end_chat_session(scene: Node) -> void:
	scene.current_chat_session_npc = ""
	scene.current_chat_session_records = []

static func compact_current_context_for_recovery(scene: Node) -> void:
	scene.current_chat_session_records = scene._compact_history_rows_for_recovery(scene.current_chat_session_records, 6, 10, 32)
	if scene.currentNpc != null and is_instance_valid(scene.currentNpc):
		scene.currentNpc.currentChat = scene._compact_text_for_recovery(scene.currentNpc.currentChat, 10)

static func record_current_chat_session(scene: Node, kind: String, speaker: String, text: String) -> void:
	if scene.currentState != scene.worldState.chat or scene.currentNpc == null:
		return
	var current_name = str(scene.currentNpc.npcName).strip_edges()
	if current_name == "":
		return
	if scene.current_chat_session_npc == "":
		scene._start_chat_session(current_name)
	if scene.current_chat_session_npc != current_name:
		return
	var plain = scene.process_string(str(text)).strip_edges()
	if plain == "":
		return
	var rec = "[" + kind + "]" + speaker + "：" + plain
	if !scene.current_chat_session_records.is_empty() and str(scene.current_chat_session_records[scene.current_chat_session_records.size() - 1]) == rec:
		return
	scene.current_chat_session_records.append(rec)

static func update_item_trade_price(scene: Node, item_name: String, per_unit_price: int) -> void:
	if item_name == "" or per_unit_price <= 0:
		return
	var key = str(item_name).strip_edges()
	if !scene.itemProfiles.has(key):
		return
	scene.itemProfiles[key]["value"] = per_unit_price
	scene.itemProfiles[key]["value_trade_confirmed"] = true
	var disk_profile = scene._load_item_profile_json(key)
	disk_profile["value"] = per_unit_price
	scene._save_item_profile_json(key, disk_profile)

static func _normalize_single_line_input(raw_text: String) -> String:
	return GameTextUtils.normalize_single_line_input(raw_text)

static func _is_action_explicitly_targeting_current_npc(scene: Node, action_text: String) -> bool:
	if scene == null or scene.currentNpc == null:
		return false
	var t = _normalize_single_line_input(action_text)
	if t == "":
		return false
	var npc_name = str(scene.currentNpc.npcName).strip_edges()
	if npc_name != "" and t.find(npc_name) != -1:
		return true
	var actor_markers = ["让他", "让她", "让对方", "叫他", "叫她", "请他", "请她", "跟他说", "跟她说", "问他", "问她"]
	for marker in actor_markers:
		if t.find(marker) != -1:
			return true
	return false

static func on_send_button_pressed(scene: Node) -> void:
	if scene._is_runtime_transition_locked():
		return
	if _normalize_single_line_input(scene.input_text_edit.text) == "":
		await scene._trigger_continue_flow()
		return
	await scene._submit_action_input(scene.input_text_edit.text, false)

static func build_shared_interaction_context(scene: Node, interaction_text: String, focus_npc_name: String = "", focus_npc_desc: String = "") -> String:
	var identity_guidance = scene._clip_prompt_text(scene._build_identity_attitude_guidance(focus_npc_name, focus_npc_desc), 520)
	var chat_session_mem = scene._clip_prompt_text(scene.get_current_chat_session_memory(focus_npc_name), 900)
	var related_events = scene._clip_prompt_text(scene._build_related_event_memory_for_action(interaction_text, focus_npc_name), 480)
	return scene._clip_prompt_text(GameInteractionContext.build_shared_context({
		"world_seed_input": scene.world_seed_input,
		"background": scene.background,
		"current_site_name": scene.currentSiteName,
		"money": str(scene.money),
		"player_name": scene.playerName,
		"inventory_snapshot": scene._build_inventory_snapshot(),
		"focus_npc_name": focus_npc_name,
		"focus_npc_desc": focus_npc_desc,
		"identity_guidance": identity_guidance,
		"chat_session_mem": chat_session_mem,
		"related_events": related_events,
	}), 0)

static func build_continue_action_text() -> String:
	return "继续当前事情的发展"

static func build_continue_dialogue_text() -> String:
	return "继续当前对话和眼前发生的事情"

static func trigger_continue_flow(scene: Node) -> void:
	if scene._is_runtime_transition_locked():
		return
	if scene.input_text_edit != null:
		scene.input_text_edit.text = ""
	if scene.currentState == scene.worldState.chat and scene.currentNpc != null:
		await scene._submit_dialogue_input(build_continue_dialogue_text(), true)
		return
	await scene._submit_action_input(build_continue_action_text(), true)

static func submit_action_input(scene: Node, raw_input: String, bypass_lock_check: bool = false) -> void:
	var user_input = _normalize_single_line_input(raw_input)
	if user_input == "" or scene.ai_busy:
		return
	if !bypass_lock_check and scene._is_runtime_transition_locked():
		return
	scene.preferred_input_focus = "action"
	scene.call_deferred("_recover_focus_after_submit", "action")
	scene.input_text_edit.text = ""
	scene.last_action_input = user_input
	scene.addLog("【行动】" + user_input)
	scene.changeTextTo(scene.get_node("%speakerNameLabel"), scene.playerName)
	scene.changeTextTo(scene.response_label, user_input)
	var focus_npc_name = ""
	var focus_npc_desc = ""
	var explicitly_target_npc = _is_action_explicitly_targeting_current_npc(scene, user_input)
	if explicitly_target_npc and scene.currentState == scene.worldState.chat and scene.currentNpc != null:
		focus_npc_name = str(scene.currentNpc.npcName)
		focus_npc_desc = str(scene.currentNpc.npcDescribe)
	if focus_npc_name != "":
		scene._record_current_chat_session("行动输入", scene.playerName, user_input)
	var action_context = scene._build_shared_interaction_context(user_input, focus_npc_name, focus_npc_desc)
	var aprompts = [
		{"role":"system","content": scene.action_prompt + "\n" + action_context},
		{"role":"user","content": user_input}]
	await scene.ask_ai(aprompts, scene.aiMode.action)

static func on_dialogue_button_pressed(scene: Node) -> void:
	await scene._submit_dialogue_input(scene.dialogue_input.text, false)

static func submit_dialogue_input(scene: Node, raw_input: String, allow_continue_text: bool = false) -> void:
	if scene.currentState != scene.worldState.chat or scene.currentNpc == null or scene.ai_busy or scene._is_runtime_transition_locked():
		return
	var user_input = _normalize_single_line_input(raw_input)
	if user_input == "" and allow_continue_text:
		user_input = build_continue_dialogue_text()
	if user_input == "":
		return
	scene.preferred_input_focus = "dialogue"
	scene.call_deferred("_recover_focus_after_submit", "dialogue")
	var leave_words = ["离开", "结束对话", "退出对话", "不聊了", "再见"]
	if leave_words.has(user_input):
		scene.dialogue_input.text = ""
		if scene._has_active_event_panel():
			scene.changeTextTo(scene.get_node("%speakerNameLabel"), "【旁白】")
			scene.changeTextTo(scene.response_label, "当前情况无法脱离，" + scene.currentNpc.npcName + "不会让你就这么走。")
			await scene.currentNpc.chatWithNpc("[玩家试图离开]", scene._build_shared_interaction_context("离开", str(scene.currentNpc.npcName), str(scene.currentNpc.npcDescribe)))
			return
		scene._request_leave_chat_confirm()
		return
	scene.last_dialogue_input = user_input
	scene.dialogue_input.text = ""
	scene.changeTextTo(scene.get_node("%speakerNameLabel"), scene.playerName)
	scene.changeTextTo(scene.response_label, user_input)
	scene._record_current_chat_session("对话输入", scene.playerName, user_input)
	var dialogue_context = scene._build_shared_interaction_context(user_input, str(scene.currentNpc.npcName), str(scene.currentNpc.npcDescribe))
	await scene.currentNpc.chatWithNpc(user_input, dialogue_context)
	scene.currentNpc.currentChat += "玩家：" + user_input + "\n"

static func on_continue_button_pressed(scene: Node) -> void:
	await scene._trigger_continue_flow()

static func on_npc_icon_gui_input(scene: Node, event: InputEvent) -> void:
	if !(event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if !mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if scene.currentState != scene.worldState.chat or scene.currentNpc == null:
		return
	if bool(scene.get_meta("npc_profile_open", false)):
		var active_npc = str(scene.currentNpc.npcName).strip_edges()
		var prev_npc = str(scene.get_meta("npc_profile_prev_npc", "")).strip_edges()
		var prev_speaker = str(scene.get_meta("npc_profile_prev_speaker", active_npc))
		var prev_text = str(scene.get_meta("npc_profile_prev_text", "")).strip_edges()
		if prev_npc != "" and prev_npc != active_npc:
			prev_speaker = active_npc
			prev_text = ""
		if prev_text == "":
			prev_text = str(scene.currentNpc.currentChat).strip_edges()
			if prev_text.find("\n") != -1:
				var rows = prev_text.split("\n", false)
				prev_text = str(rows[rows.size() - 1]).strip_edges()
			if prev_text == "":
				prev_text = "你正在与" + active_npc + "交谈。"
		scene.changeTextTo(scene.get_node("%speakerNameLabel"), prev_speaker)
		scene.changeTextTo(scene.response_label, prev_text)
		scene.set_meta("npc_profile_open", false)
		scene.set_meta("npc_profile_prev_npc", "")
		scene.set_meta("npc_profile_prev_speaker", "")
		scene.set_meta("npc_profile_prev_text", "")
		scene.addLog("<关闭人物档案，已返回对话输出>")
		return
	scene._show_current_npc_profile()

static func show_current_npc_profile(scene: Node) -> void:
	if scene.currentNpc == null:
		return
	var speaker_node = scene.get_node_or_null("%speakerNameLabel")
	if speaker_node != null and speaker_node is Label:
		scene.set_meta("npc_profile_prev_speaker", str((speaker_node as Label).text))
	else:
		scene.set_meta("npc_profile_prev_speaker", str(scene.currentNpc.npcName))
	scene.set_meta("npc_profile_prev_npc", str(scene.currentNpc.npcName))
	scene.set_meta("npc_profile_prev_text", str(scene.response_label.text))
	scene.set_meta("npc_profile_open", true)
	var npc_name = str(scene.currentNpc.npcName)
	var desc = str(scene.currentNpc.npcDescribe).strip_edges()
	if desc == "":
		desc = "暂无详细介绍"
	var mem = scene.get_relevant_event_memory_for_npc(npc_name, desc).strip_edges()
	if mem == "":
		mem = "- 暂无与该角色直接相关的重要事件"
	var panel_text = "人物：" + npc_name + "\n介绍：" + desc + "\n相关重要事件：\n" + mem
	scene.changeTextTo(scene.get_node("%speakerNameLabel"), "【人物档案】")
	scene.changeTextTo(scene.response_label, panel_text, 80)
	scene.addLog("<查看了" + npc_name + "的人物档案>")

static func request_leave_chat_confirm(scene: Node) -> void:
	if scene.currentState != scene.worldState.chat or scene.currentNpc == null:
		return
	var npc_name = str(scene.currentNpc.npcName).strip_edges()
	scene.pending_action_confirm = {
		"action": "离开与" + npc_name + "的对话",
		"prompt": "是否结束与" + npc_name + "的对话并回到探索？",
		"actor": npc_name,
		"mode": "leave_chat"
	}
	scene._set_event_flow_lock(true)
	scene.get_node("%event").got_action_confirm_event(str(scene.pending_action_confirm.get("action", "")), str(scene.pending_action_confirm.get("prompt", "")))

static func request_site_switch(scene: Node, site_name: String) -> void:
	if scene._is_runtime_transition_locked():
		return
	var target = scene._resolve_site_alias(str(site_name).strip_edges())
	if target == "":
		return
	if scene.currentState == scene.worldState.chat and scene.currentNpc != null:
		var npc_name = str(scene.currentNpc.npcName).strip_edges()
		scene.pending_action_confirm = {
			"action": "前往" + target,
			"prompt": "是否结束与" + npc_name + "的对话并前往" + target + "？",
			"actor": npc_name,
			"mode": "switch_site",
			"target_site": target
		}
		scene._set_event_flow_lock(true)
		scene.get_node("%event").got_action_confirm_event(str(scene.pending_action_confirm.get("action", "")), str(scene.pending_action_confirm.get("prompt", "")))
		return
	await scene.goto(target)

static func start_chat_with_existing_npc(scene: Node, npc_name: String) -> void:
	if !scene.npcs.has(npc_name) or !(scene.npcs[npc_name] is Dictionary):
		return
	scene.set_meta("npc_profile_open", false)
	scene.set_meta("npc_profile_prev_npc", "")
	scene.set_meta("npc_profile_prev_speaker", "")
	scene.set_meta("npc_profile_prev_text", "")
	scene._end_chat_session()
	if scene.get_node("%npcIcon") is TextureRect:
		(scene.get_node("%npcIcon") as TextureRect).texture = null
	if !scene.npcs[npc_name].has("portrait_generating"):
		scene.npcs[npc_name]["portrait_generating"] = false
	var has_portrait = scene.npcImgs.has(npc_name) and scene.npcImgs[npc_name] is Texture2D
	if !has_portrait:
		var disk_portrait = scene._load_image_png(scene.NPC_IMG_DIR, npc_name)
		if disk_portrait != null:
			scene.npcImgs[npc_name] = disk_portrait
			has_portrait = true
	if !has_portrait and !bool(scene.npcs[npc_name].get("portrait_generating", false)):
		scene.npcs[npc_name]["portrait_generating"] = true
		var desc_for_img = str(scene.npcs[npc_name].get("npc_describe", ""))
		var loc_hint = scene._infer_npc_location_for_prompt(npc_name)
		var nprompt = scene._build_npc_image_prompt(npc_name, desc_for_img, loc_hint)
		if nprompt != "":
			scene.gen_img(nprompt, "NPC:" + npc_name)
	scene.prepare_npc_memory_for_chat(npc_name)
	var new_npc = npc.new()
	new_npc.npcName = npc_name
	new_npc.scene = scene
	new_npc.npcDescribe = str(scene.npcs[npc_name].get("npc_describe", ""))
	if !scene.npcs[npc_name].has("npc_log") or !(scene.npcs[npc_name]["npc_log"] is Array):
		scene.npcs[npc_name]["npc_log"] = []
	var logs = ""
	for log_entry in scene.npcs[npc_name]["npc_log"]:
		logs += str(log_entry) + "\n"
	new_npc.npcLog = logs
	new_npc.currentChat = ""
	scene.newNpc = new_npc
	await scene.changeStateInto(scene.worldState.chat)

static func request_npc_switch(scene: Node, npc_name: String) -> void:
	if scene._is_runtime_transition_locked():
		return
	var target_npc = str(npc_name).strip_edges()
	if target_npc == "":
		return
	if !scene.npcs.has(target_npc):
		return
	if scene.currentState == scene.worldState.chat and scene.currentNpc != null and str(scene.currentNpc.npcName) != target_npc:
		var from_npc = str(scene.currentNpc.npcName).strip_edges()
		scene.pending_action_confirm = {
			"action": "切换对话对象到" + target_npc,
			"prompt": "是否结束与" + from_npc + "的对话并切换到" + target_npc + "？",
			"actor": from_npc,
			"mode": "switch_npc",
			"target_npc": target_npc
		}
		scene._set_event_flow_lock(true)
		scene.get_node("%event").got_action_confirm_event(str(scene.pending_action_confirm.get("action", "")), str(scene.pending_action_confirm.get("prompt", "")))
		return
	await scene._start_chat_with_existing_npc(target_npc)

static func request_npc_leave_confirm(scene: Node, npc_name: String) -> void:
	var target_npc = str(npc_name).strip_edges()
	if target_npc == "":
		return
	scene.pending_action_confirm = {
		"action": "允许" + target_npc + "离开",
		"prompt": target_npc + "想要离开，你要挽留吗？",
		"actor": target_npc,
		"mode": "npc_leave",
		"target_npc": target_npc
	}
	scene._set_event_flow_lock(true)
	scene.get_node("%event").got_action_confirm_event(str(scene.pending_action_confirm.get("action", "")), str(scene.pending_action_confirm.get("prompt", "")))

static func has_active_event_panel(scene: Node) -> bool:
	for child in scene.get_node("%event").get_children():
		if child is eventContainer:
			return true
	return false

static func refresh_interaction_locks(scene: Node) -> void:
	if scene.event_flow_lock and !scene._has_active_event_panel():
		scene.event_flow_lock = false
		scene._log_lock_state("refresh:auto_unlock_event_flow")
	scene._apply_interaction_locks()

static func set_event_flow_lock(scene: Node, v: bool) -> void:
	scene.event_flow_lock = v
	scene._log_lock_state("set_event_flow_lock:" + str(v))
	scene._apply_interaction_locks()
	if !scene.event_flow_lock:
		scene.call_deferred("_focus_active_input")

static func focus_active_input(scene: Node) -> void:
	if scene.ai_busy or scene.event_flow_lock or scene._has_active_event_panel():
		return
	if scene.preferred_input_focus == "dialogue" and scene.currentState == scene.worldState.chat and scene.dialogue_container.visible and scene.currentNpc != null and scene.dialogue_input != null:
		scene.dialogue_input.grab_focus()
		return
	if scene.preferred_input_focus == "action" and scene.input_text_edit != null:
		scene.input_text_edit.grab_focus()
		return
	if scene.currentState == scene.worldState.chat and scene.dialogue_container.visible and scene.currentNpc != null and scene.dialogue_input != null:
		scene.dialogue_input.grab_focus()
		return
	if scene.input_text_edit != null:
		scene.input_text_edit.grab_focus()

static func recover_focus_after_submit(scene: Node, target_focus: String) -> void:
	var target = str(target_focus).strip_edges()
	if target != "dialogue":
		target = "action"
	var retry = 0
	while retry < 180:
		await scene.get_tree().process_frame
		if scene.ai_busy or scene.event_flow_lock or scene._has_active_event_panel():
			retry += 1
			continue
		scene.preferred_input_focus = target
		scene._focus_active_input()
		return

static func apply_interaction_locks(scene: Node) -> void:
	var has_event_panel = scene._has_active_event_panel()
	var text_busy = !scene._active_text_tweens.is_empty()
	var base_lock = scene.runtime_operation_lock or scene.ai_busy or scene.event_flow_lock or has_event_panel or text_busy
	scene.send_button.disabled = base_lock
	scene.dialogue_button.disabled = base_lock or scene.currentState != scene.worldState.chat
	if scene.save_button != null and is_instance_valid(scene.save_button):
		scene.save_button.disabled = base_lock or scene.site_loading_lock
	if scene.load_button != null and is_instance_valid(scene.load_button):
		scene.load_button.disabled = base_lock or scene.site_loading_lock
	if scene.input_text_edit != null:
		scene.input_text_edit.editable = !base_lock
	if scene.dialogue_input != null:
		scene.dialogue_input.editable = !(base_lock or scene.currentState != scene.worldState.chat)
	if scene.continue_button != null and is_instance_valid(scene.continue_button):
		scene.continue_button.disabled = base_lock
	var map_lock = base_lock or scene.site_loading_lock
	for btn in scene.get_node("%site_buttons").get_children():
		if btn is BaseButton:
			btn.disabled = map_lock
	for btn in scene.get_node("%npc_buttons").get_children():
		if btn is BaseButton:
			btn.disabled = map_lock
	scene._log_lock_state("apply")

static func set_site_loading_lock(scene: Node, v: bool) -> void:
	scene.site_loading_lock = v
	scene._apply_interaction_locks()

static func set_ai_busy(scene: Node, v: bool) -> void:
	scene.ai_busy = v
	scene._log_lock_state("set_ai_busy:" + str(v))
	if scene.ai_busy:
		scene._apply_interaction_locks()
	else:
		scene.refresh_interaction_locks()
		scene.call_deferred("_focus_active_input")

static func sanitize_response_text(raw_text: String) -> String:
	return GameParseUtils.sanitize_response_text(raw_text)

static func changeTextTo(scene: Node, nodeToChange: Control, text: String, speed = 30, max_tween_duration: float = 1.6) -> void:
	if !scene.has_method("get"):
		return
	if typeof(scene.get("text_update_seq")) != TYPE_INT:
		scene.set("text_update_seq", 0)
	if nodeToChange == null:
		return
	var safe_text = text
	if nodeToChange == scene.response_label:
		safe_text = scene._sanitize_response_text(text)
	else:
		safe_text = str(text).strip_edges()
	var key = str(nodeToChange.get_instance_id())
	if scene._active_text_tweens.has(key):
		var old_tween = scene._active_text_tweens[key]
		if old_tween is Tween and old_tween.is_valid():
			old_tween.kill()
		scene._active_text_tweens.erase(key)
		scene._log_lock_state("changeTextTo:kill_old_tween")
	if nodeToChange.text == safe_text:
		nodeToChange.visible_ratio = 1.0
		scene._log_lock_state("changeTextTo:same_text_no_tween")
		return
	scene.text_update_seq += 1
	var request_id = scene.text_update_seq
	nodeToChange.set_meta("text_request_id", request_id)
	nodeToChange.text = safe_text
	nodeToChange.visible_ratio = 0.0
	var char_count = max(1, safe_text.length())
	var safe_speed = max(1.0, float(speed))
	var max_duration = max(0.1, max_tween_duration)
	if nodeToChange == scene.response_label:
		max_duration = max(max_duration, 4.5)
	var duration = clamp(float(char_count) / safe_speed, 0.08, max_duration)
	var tween = scene.create_tween()
	scene._active_text_tweens[key] = tween
	scene._apply_interaction_locks()
	tween.tween_property(nodeToChange, "visible_ratio", 1.0, duration)
	await tween.finished
	if !is_instance_valid(nodeToChange):
		return
	if int(nodeToChange.get_meta("text_request_id", -1)) != request_id:
		scene.refresh_interaction_locks()
		return
	if scene._active_text_tweens.get(key, null) == tween:
		scene._active_text_tweens.erase(key)
		scene._log_lock_state("changeTextTo:tween_finished")
	scene.refresh_interaction_locks()

static func clear_children(_scene: Node, node: Node) -> void:
	var children = node.get_children()
	for i in children:
		node.remove_child(i)
		i.queue_free()

static func addLog(scene: Node, logText: String, instant: bool = false) -> void:
	var newLog = scene.LOG_LABEL_SCENE.instantiate()
	newLog.text = logText
	if instant and newLog is RichTextLabel:
		newLog.visible_ratio = 1.0
	scene.get_node("%logContainer").add_child(newLog)
	if scene.get_node("%logContainer").get_child_count() > scene.max_visible_logs:
		var overflow = scene.get_node("%logContainer").get_child_count() - scene.max_visible_logs
		for i in range(overflow):
			var old_log = scene.get_node("%logContainer").get_child(i)
			scene.get_node("%logContainer").remove_child(old_log)
			old_log.queue_free()
	if scene._is_important_log(logText):
		var focus_npc = ""
		if scene.currentNpc != null:
			focus_npc = str(scene.currentNpc.npcName)
		scene._remember_important_event(logText, scene.currentSiteName, focus_npc)

static func on_force_release_button_pressed(scene: Node) -> void:
	scene._force_release_runtime(true, false)

static func on_save_button_pressed(scene: Node) -> void:
	if scene._is_runtime_transition_locked():
		scene.addLog("<当前流程未完成，暂不可保存>")
		return
	scene.save_game()

static func on_load_button_pressed(scene: Node) -> void:
	if scene._is_runtime_transition_locked():
		scene.addLog("<当前流程未完成，暂不可读档>")
		return
	scene.load_game()

static func clear_active_text_tweens(scene: Node, force_complete_visible: bool = true) -> void:
	for key in scene._active_text_tweens.keys():
		var tw = scene._active_text_tweens[key]
		if tw is Tween and tw.is_valid():
			tw.kill()
	scene._active_text_tweens.clear()
	if force_complete_visible:
		if scene.response_label != null and is_instance_valid(scene.response_label):
			scene.response_label.visible_ratio = 1.0
		if scene.has_node("%speakerNameLabel"):
			scene.get_node("%speakerNameLabel").visible_ratio = 1.0
	scene.refresh_interaction_locks()

static func force_release_runtime(scene: Node, show_notice: bool = true, compact_context: bool = false) -> void:
	if compact_context:
		scene._compact_current_context_for_recovery()
	scene._ignore_next_request_completed = true
	if scene.http_request.get_http_client_status() == HTTPClient.STATUS_REQUESTING and scene.http_request.has_method("cancel_request"):
		scene.http_request.cancel_request()
	scene._clear_active_text_tweens(true)
	scene.clear_children(scene.get_node("%event"))
	scene.pending_action_confirm = {}
	scene.site_loading_lock = false
	scene.event_flow_lock = false
	scene.ai_busy = false
	scene.refresh_interaction_locks()
	scene.call_deferred("_focus_active_input")
	if show_notice:
		scene.addLog("<已强制释放：你现在可以继续输入、切换场景或切换对话对象>")
		scene.changeTextTo(scene.get_node("%speakerNameLabel"), "【系统】", 240, 0.12)
		scene.changeTextTo(scene.response_label, "已强制解除当前输出与交互锁定，你可以继续进行对话、行动输入，以及切换场景或对话对象。", 240, 0.2)

static func recover_from_ai_stall(scene: Node, reason: String) -> void:
	if scene.currentMode == scene.aiMode.init_env:
		scene._force_release_runtime(false, false)
		if scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("if_weather_failed"):
			scene.get_node("mainMenu").if_weather_failed("环境创建中断（" + reason + "），已使用默认天气。")
		return
	if scene.currentMode == scene.aiMode.init_background:
		scene._force_release_runtime(false, false)
		if scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("add_start_log"):
			scene.get_node("mainMenu").add_start_log("⚠ 世界初始化中断（" + reason + "），正在继续...")
		return
	scene._compact_current_context_for_recovery()
	scene._force_release_runtime(false, false)
	scene.addLog("<AI响应超时，已精简保留上下文并解除锁定：" + reason + ">")
	scene.changeTextTo(scene.get_node("%speakerNameLabel"), "【系统】", 240, 0.12)
	scene.changeTextTo(scene.response_label, "AI超过" + str(int(ceil(scene.ai_request_timeout_seconds))) + "秒未响应，已精简并保留先前上下文后清理卡住状态。你可以继续输入、切换场景或切换对话对象。", 240, 0.24)

static func on_request_completed(scene: Node, result, response_code, _header, body) -> void:
	await GameFlowRuntimeUtils.on_request_completed(scene, result, response_code, _header, body)

static func apply_passive_recovery(scene: Node, minutes: float) -> Dictionary:
	var m = max(0.0, minutes)
	if m <= 0.0:
		return {"hours": 0.0, "energy": 0.0, "hp": 0.0}
	var hours = m / 60.0
	var energy_gain = hours * scene.PASSIVE_ENERGY_RECOVERY_PER_HOUR
	var hp_gain = hours * scene.PASSIVE_HP_RECOVERY_PER_HOUR
	var before_energy = scene.energy
	var before_hp = scene.hp
	scene.energy = clamp(scene.energy + energy_gain, 0.0, 100.0)
	scene.hp = clamp(scene.hp + hp_gain, 0.0, 100.0)
	return {
		"hours": hours,
		"energy": max(0.0, scene.energy - before_energy),
		"hp": max(0.0, scene.hp - before_hp)
	}

static func advance_time_minutes(scene: Node, minutes: float, with_log: bool = false) -> Dictionary:
	var safe_minutes = max(0.0, minutes)
	scene.nowtime += safe_minutes
	var rec = scene.apply_passive_recovery(safe_minutes)
	if with_log and safe_minutes > 0.0:
		scene.addLog("<时间流逝" + str(snappedf(rec.get("hours", 0.0), 0.1)) + "小时：体力+" + str(int(round(rec.get("energy", 0.0)))) + "，健康+" + str(int(round(rec.get("hp", 0.0)))) + ">")
	scene.player_update()
	return rec

static func on_event_decision(scene: Node, event_kind: String, accepted: bool, item_name: String, quantity: int, total_price: int = 0) -> void:
	await GameFlowRuntimeUtils.on_event_decision(scene, event_kind, accepted, item_name, quantity, total_price)
