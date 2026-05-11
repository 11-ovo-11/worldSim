extends RefCounted
class_name GameFlowRuntimeUtils

static func goto(scene: Node, where: String) -> void:
	where = scene._resolve_site_alias(str(where).strip_edges())
	if where == "":
		scene.changeTextTo(scene.get_node("%siteName"), "未定位")
		return
	scene.changeTextTo(scene.get_node("%siteName"), where)
	await scene.changeStateInto(scene.worldState.explore)
	scene._set_site_loading_lock(false)
	scene._bg_debug("goto start, where=" + where + ", current=" + scene.currentSiteName)
	if !scene.sites.has(where) or !(scene.sites[where] is Dictionary) or !scene.sites[where].has("地点描述"):
		var disk_site = scene._load_site_json(where)
		if !disk_site.is_empty():
			scene.sites[where] = disk_site
			scene._bg_debug("site json cache hit for " + where)
	var site_data = scene._get_site_data(where)
	var has_description = !site_data.is_empty() and str(site_data.get("地点描述", "")).strip_edges() != ""
	var has_routes = false
	if site_data.has("能前往的地点") and site_data["能前往的地点"] is Array:
		for raw_route in site_data["能前往的地点"]:
			var normalized_route = scene._resolve_site_alias(str(raw_route).strip_edges())
			if normalized_route != "" and normalized_route != where:
				has_routes = true
				break
	if has_description and has_routes:
		print("地点已经存在")
		scene.currentSiteName = where
		var has_bg := false
		if scene.siteImgs.has(where):
			scene.get_node("%backgroundImg").texture = scene.siteImgs[where]
			has_bg = true
		else:
			var cached = scene._load_image_png(scene.SCENE_IMG_DIR, where)
			if cached != null:
				scene.get_node("%backgroundImg").texture = cached
				scene.siteImgs[where] = cached
				has_bg = true
				scene._bg_debug("scene image cache hit for " + where)
		if !has_bg:
			var scene_prompt = scene._build_scene_image_prompt(where, site_data)
			scene._bg_debug("scene image cache miss for " + where + ", prompt_len=" + str(scene_prompt.length()))
			if scene_prompt != "":
				scene.gen_img(scene_prompt, where)
		scene.site_update()
	else:
		scene.changeTextTo(scene.response_label, "正在探索" + where + "...", 8)
		scene.pending_explore_target = where
		scene.explore_route_retry_count = 0
		var prompts = [
			{"role":"system","content": scene._build_explore_system_prompt()},
			{"role":"user","content": "我想去"+where}]
		scene.explore_needs_retry = false
		await scene.ask_ai(prompts, scene.aiMode.explore)
		if scene.explore_needs_retry and scene.currentSiteName != "":
			scene.explore_needs_retry = false
			var retry_target = scene.currentSiteName
			scene._bg_debug("goto() retry explore for " + retry_target)
			var retry_prompts = [
				{"role":"system","content": scene._build_explore_system_prompt() + "\n再次强调：只能输出JSON，且\"能前往的地点\"不得为空。"},
				{"role":"user","content": "我想去" + retry_target}
			]
			await scene.ask_ai(retry_prompts, scene.aiMode.explore)
		scene.explore_needs_retry = false
		var discovered_site = scene._resolve_site_alias(scene.currentSiteName)
		if discovered_site == "":
			discovered_site = where
		scene.currentSiteName = discovered_site
		var new_site = scene._get_site_data(discovered_site)
		if !new_site.is_empty():
			var has_bg_new := false
			if scene.siteImgs.has(discovered_site):
				scene.get_node("%backgroundImg").texture = scene.siteImgs[discovered_site]
				has_bg_new = true
			else:
				var cached_new = scene._load_image_png(scene.SCENE_IMG_DIR, discovered_site)
				if cached_new != null:
					scene.get_node("%backgroundImg").texture = cached_new
					scene.siteImgs[discovered_site] = cached_new
					has_bg_new = true
			if has_bg_new:
				scene.site_update()
				return
			var prompt = scene._build_scene_image_prompt(discovered_site, new_site)
			if prompt != "":
				scene.gen_img(prompt, discovered_site)
			scene.site_update()
		else:
			scene.pending_site_update = false
			scene._set_site_loading_lock(false)
			scene.changeTextTo(scene.response_label, "无法探索「" + where + "」，请检查角色与场景设定后重试。")

static func on_event_decision(scene: Node, event_kind: String, accepted: bool, item_name: String, quantity: int, total_price: int = 0) -> void:
	var speaker = "路人"
	if scene.currentNpc != null:
		speaker = str(scene.currentNpc.npcName)
	if event_kind == "action_confirm":
		var confirm_data: Dictionary = scene.pending_action_confirm
		var action_actor = str(confirm_data.get("actor", speaker))
		var action_text = str(confirm_data.get("action", item_name))
		var action_mode = str(confirm_data.get("mode", "player_execute"))
		if action_mode == "npc_leave":
			var target_npc = str(confirm_data.get("target_npc", action_actor)).strip_edges()
			if accepted:
				scene.addLog("<你拦下了" + target_npc + "，对方暂时没有离开>")
			else:
				await scene.destroy_yourself(target_npc)
			scene.pending_action_confirm = {}
			scene.call_deferred("_focus_active_input")
			return
		if action_mode == "leave_chat":
			if accepted:
				await scene.changeStateInto(scene.worldState.explore)
			else:
				scene.addLog("<你选择继续与" + action_actor + "对话>")
			scene.pending_action_confirm = {}
			scene.call_deferred("_focus_active_input")
			return
		if action_mode == "switch_site":
			var target_site = scene._resolve_site_alias(str(confirm_data.get("target_site", "")).strip_edges())
			if accepted and target_site != "":
				await scene.goto(target_site)
			else:
				scene.addLog("<你取消了前往" + target_site + ">")
			scene.pending_action_confirm = {}
			scene.call_deferred("_focus_active_input")
			return
		if action_mode == "switch_npc":
			var target_npc = str(confirm_data.get("target_npc", "")).strip_edges()
			if accepted and target_npc != "":
				await scene._start_chat_with_existing_npc(target_npc)
			else:
				if target_npc != "":
					scene.addLog("<你取消了切换到" + target_npc + "的对话>")
			scene.pending_action_confirm = {}
			scene.call_deferred("_focus_active_input")
			return
		if accepted:
			if action_mode == "force_execute":
				scene.addLog("<你选择强硬执行：" + action_text + ">")
			else:
				scene.addLog("<你接受了" + action_actor + "的行动建议：" + action_text + ">")
			await scene._submit_action_input(action_text, true)
		else:
			scene.addLog("<你拒绝了" + action_actor + "的行动建议：" + action_text + ">")
		scene.pending_action_confirm = {}
		scene.call_deferred("_focus_active_input")
		return
	if accepted:
		if event_kind == "deal":
			scene.addLog("<" + speaker + "：成交。>")
			scene._remember_important_event("<交易结果>你与" + speaker + "就「" + str(item_name) + "x" + str(quantity) + "」成交，价格" + str(total_price) + "。", scene.currentSiteName, speaker)
		elif event_kind == "gift":
			scene.addLog("<" + speaker + "：收下吧。>")
			scene._remember_important_event("<赠送结果>" + speaker + "向你赠送「" + str(item_name) + "x" + str(quantity) + "」，你已接受。", scene.currentSiteName, speaker)
	else:
		if event_kind == "deal":
			scene._remember_important_event("<交易结果>你拒绝了" + speaker + "关于「" + str(item_name) + "x" + str(quantity) + "」的交易报价。", scene.currentSiteName, speaker)
		else:
			scene._remember_important_event("<赠送结果>你拒绝了" + speaker + "赠送的「" + str(item_name) + "x" + str(quantity) + "」。", scene.currentSiteName, speaker)

static func handle_npc_instruction(scene: Node, tool_calls: Array) -> void:
	var normalized_calls: Array = []
	for tool_call in tool_calls:
		print("接受到一个函数调用: ", tool_call)
		var function_data = tool_call.get("function", {})
		if function_data == {} and tool_call.has("name"):
			function_data = tool_call
		var method = str(function_data.get("name", "")).strip_edges()
		if method == "":
			continue
		var arguments_data = function_data.get("arguments", "{}")

		var parameters = {}
		if arguments_data is Dictionary:
			parameters = arguments_data
		elif arguments_data is String:
			var json = JSON.new()
			var error = json.parse(arguments_data)
			if error == OK:
				parameters = json.data
			else:
				print("解析参数失败: ", arguments_data)
				continue
		else:
			print("解析参数失败: ", arguments_data)
			continue

		if parameters is Dictionary and parameters.has("quantity") and method in ["initiate_transaction", "got_items", "consume_items"]:
			parameters["quantity"] = max(1, int(parameters.get("quantity", 1)))

		if !normalized_calls.is_empty():
			var prev = normalized_calls[normalized_calls.size() - 1]
			var prev_method = str(prev.get("method", ""))
			var prev_params: Dictionary = prev.get("parameters", {})
			if method in ["initiate_transaction", "got_items", "consume_items"] and prev_method == method:
				var item_name = str(parameters.get("item_name", ""))
				var prev_item_name = str(prev_params.get("item_name", ""))
				var can_merge = item_name != "" and item_name == prev_item_name
				if can_merge and method == "initiate_transaction":
					can_merge = int(parameters.get("price", 0)) == int(prev_params.get("price", 0)) \
						and bool(parameters.get("is_total_price", false)) == bool(prev_params.get("is_total_price", false))
				if can_merge:
					prev_params["quantity"] = int(prev_params.get("quantity", 1)) + int(parameters.get("quantity", 1))
					normalized_calls[normalized_calls.size() - 1]["parameters"] = prev_params
					continue

		normalized_calls.append({"method": method, "parameters": parameters})

	for i in range(normalized_calls.size() - 1):
		if normalized_calls[i].get("method", "") == "consume_items" and normalized_calls[i+1].get("method", "") == "initiate_transaction":
			var a_item = str(normalized_calls[i].get("parameters", {}).get("item_name", ""))
			var b_params: Dictionary = normalized_calls[i+1].get("parameters", {})
			var b_item = str(b_params.get("item_name", ""))
			var tx_price = int(b_params.get("price", 0))
			var is_total_price = bool(b_params.get("is_total_price", false))
			var maybe_gift = tx_price <= 0 and !is_total_price
			if maybe_gift and a_item != "" and b_item != "" and a_item != b_item:
				normalized_calls[i+1]["method"] = "got_items"
				normalized_calls[i+1]["parameters"] = {"item_name": b_item, "quantity": int(b_params.get("quantity", 1))}

	for tool_call_item in normalized_calls:
		var method = str(tool_call_item.get("method", ""))
		var parameters: Dictionary = tool_call_item.get("parameters", {})
		match method:
			"initiate_transaction":
				await scene.initiate_transaction(
					scene._safe_tool_param_string(parameters, "item_name", ""),
					max(1, int(parameters.get("quantity", 1))),
					int(parameters.get("price", 0)),
					bool(parameters.get("is_total_price", false))
				)
			"got_items":
				await scene.got_items(
					scene._safe_tool_param_string(parameters, "item_name", ""),
					max(1, int(parameters.get("quantity", 1)))
				)
			"consume_items":
				await scene.consume_items(
					scene._safe_tool_param_string(parameters, "item_name", ""),
					max(1, int(parameters.get("quantity", 1)))
				)
			"create_location":
				scene.create_location(scene._safe_tool_param_string(parameters, "path", ""))
			"create_NPC":
				scene.create_NPC(
					scene._safe_tool_param_string(parameters, "npc_name", ""),
					scene._safe_tool_param_string(parameters, "location", ""),
					scene._safe_tool_param_string(parameters, "npc_describe", "")
				)
			"create_rumors":
				scene.create_rumors(
					scene._safe_tool_param_string(parameters, "rumor_name", ""),
					scene._safe_tool_param_string(parameters, "content", "")
				)
			"update_reputation":
				scene.update_reputation(parameters.get("quantity", 0))
			"set_time":
				scene.set_time(int(parameters.get("hour", 0)), int(parameters.get("minute", 0)))
			"destroy_self":
				var leave_target = ""
				if scene.currentNpc != null:
					leave_target = str(scene.currentNpc.npcName)
				scene._request_npc_leave_confirm(leave_target)
			_:
				print("未知方法: ", method)
				scene.addLog("<调试：未知工具调用 " + method + ">")
		await scene.get_tree().create_timer(0.4).timeout

static func on_request_completed(scene: Node, result, response_code, _header, body) -> void:
	if scene._ignore_next_request_completed:
		scene._ignore_next_request_completed = false
		scene.set_ai_busy(false)
		return
	scene.set_ai_busy(false)
	if scene.runtime_operation_lock:
		return
	if result == HTTPRequest.RESULT_TIMEOUT:
		if scene.currentMode == scene.aiMode.init_env:
			if scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("if_weather_failed"):
				scene.get_node("mainMenu").if_weather_failed("环境创建超时，已使用默认天气。")
			return
		if scene.currentMode == scene.aiMode.init_background:
			if scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("add_start_log"):
				scene.get_node("mainMenu").add_start_log("⚠ 世界初始化超时，请检查网络后重试。")
			return
		scene._recover_from_ai_stall("请求超时")
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		scene.changeTextTo(scene.response_label, "网络错误: " + str(result))
		if scene.currentMode == scene.aiMode.init_env and scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("if_weather_failed"):
			scene.get_node("mainMenu").if_weather_failed("环境创建网络错误，已使用默认天气。")
		elif scene.currentMode == scene.aiMode.init_background and scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("add_start_log"):
			scene.get_node("mainMenu").add_start_log("⚠ 世界初始化网络错误（" + str(result) + "），请检查后端服务。")
		return
	if response_code != 200:
		scene.changeTextTo(scene.response_label, "服务器错误: " + str(response_code))
		if scene.currentMode == scene.aiMode.init_env and scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("if_weather_failed"):
			scene.get_node("mainMenu").if_weather_failed("环境创建服务器错误(" + str(response_code) + ")，已使用默认天气。")
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		scene.changeTextTo(scene.response_label, "解析响应失败")
		if scene.currentMode == scene.aiMode.init_env and scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("if_weather_failed"):
			scene.get_node("mainMenu").if_weather_failed("环境创建响应解析失败，已使用默认天气。")
		return
	var data = json.get_data()
	if data.has("text"):
		match scene.currentMode:
			scene.aiMode.init_background:
				scene.background = data["text"]
				print(scene.background)
			scene.aiMode.init_env:
				print(data["text"])
				var jsonDic = scene.extract_json_from_text(data["text"])
				if jsonDic == {}:
					print("天气初始化失败")
					if scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("if_weather_failed"):
						scene.get_node("mainMenu").if_weather_failed("天气配置解析失败，已使用默认天气。")
					return
				scene.envDic = jsonDic
				if scene.get_node("%envContainer").load_weather_config_from_json(scene.envDic):
					if scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("if_weather_ok"):
						scene.get_node("mainMenu").if_weather_ok()
				else:
					if scene.has_node("mainMenu") and scene.get_node("mainMenu").has_method("if_weather_failed"):
						scene.get_node("mainMenu").if_weather_failed("天气配置校验失败，已回退默认天气。")
			scene.aiMode.explore:
				var jsonDic = scene.extract_json_from_text(data["text"])
				if jsonDic == {}:
					scene._bg_debug("explore JSON parse failed for " + scene.pending_explore_target)
					scene.pending_site_update = false
					scene._set_site_loading_lock(false)
					return
				jsonDic["能前往的地点"] = scene._extract_route_candidates_from_site_json(jsonDic)
				if !jsonDic.has("npc") or !(jsonDic["npc"] is Dictionary):
					jsonDic["npc"] = {}
				if !jsonDic.has("英文描述") or str(jsonDic.get("英文描述", "")).strip_edges() == "":
					jsonDic["英文描述"] = str(jsonDic.get("地点描述", ""))
				var location_name = str(jsonDic.get("地点名称", ""))
				var model_location_name = location_name
				if location_name == "" and scene.pending_explore_target != "":
					location_name = scene.pending_explore_target
					jsonDic["地点名称"] = location_name
				if scene.pending_explore_target != "":
					var target_name = scene._resolve_site_alias(scene.pending_explore_target)
					if target_name != "":
						location_name = target_name
						jsonDic["地点名称"] = location_name
				if model_location_name != "" and model_location_name != location_name:
					var aliases: Array = []
					if jsonDic.has("别名") and jsonDic["别名"] is Array:
						aliases = jsonDic["别名"]
					if !aliases.has(model_location_name):
						aliases.append(model_location_name)
					jsonDic["别名"] = aliases
				if !jsonDic.has("地点描述") or str(jsonDic.get("地点描述", "")).strip_edges() == "":
					jsonDic["地点描述"] = scene._build_location_fallback_description(location_name, scene.currentSiteName)
				if location_name == "":
					scene.changeTextTo(scene.response_label, "地点信息解析失败，请重试")
					scene.set_ai_busy(false)
					return
				var cleaned_routes: Array = []
				for raw_route in jsonDic.get("能前往的地点", []):
					var normalized_route = scene._resolve_site_alias(str(raw_route).strip_edges())
					if normalized_route == "" or normalized_route == location_name or cleaned_routes.has(normalized_route):
						continue
					cleaned_routes.append(normalized_route)
				jsonDic["能前往的地点"] = cleaned_routes
				if cleaned_routes.is_empty() and scene.explore_route_retry_count < 1:
					scene.explore_route_retry_count += 1
					scene._bg_debug("explore empty routes, signaling goto() to retry")
					scene.explore_needs_retry = true
				else:
					scene.explore_route_retry_count = 0
				print("能前往的地点", jsonDic["能前往的地点"])
				if scene.currentSiteName != "" and !jsonDic["能前往的地点"].has(scene.currentSiteName):
					jsonDic["能前往的地点"].append(scene.currentSiteName)
				var old_site: Dictionary = {}
				if scene.sites.has(location_name) and scene.sites[location_name] is Dictionary:
					old_site = scene.sites[location_name]
				if !old_site.is_empty():
					if old_site.has("能前往的地点") and old_site["能前往的地点"] is Array:
						for old_route in old_site["能前往的地点"]:
							if !jsonDic["能前往的地点"].has(old_route):
								jsonDic["能前往的地点"].append(old_route)
						print("发现了预先存在的地点")
					if old_site.has("npc") and old_site["npc"] is Dictionary:
						for npc_name in old_site["npc"].keys():
							if !jsonDic["npc"].has(npc_name):
								jsonDic["npc"][npc_name] = old_site["npc"][npc_name]
						print("发现了预先存在的npc")
				if model_location_name != "" and model_location_name != location_name and scene.sites.has(model_location_name):
					var alias_site = scene.sites[model_location_name]
					if alias_site is Dictionary:
						if alias_site.has("能前往的地点") and alias_site["能前往的地点"] is Array:
							for old_route in alias_site["能前往的地点"]:
								if !jsonDic["能前往的地点"].has(old_route):
									jsonDic["能前往的地点"].append(old_route)
						if alias_site.has("npc") and alias_site["npc"] is Dictionary:
							for npc_name in alias_site["npc"].keys():
								if !jsonDic["npc"].has(npc_name):
									jsonDic["npc"][npc_name] = alias_site["npc"][npc_name]
					scene.sites.erase(model_location_name)
				scene.sites[location_name] = jsonDic
				if scene.currentSiteName != "" and scene.currentSiteName != location_name:
					scene.create_location(scene.currentSiteName + "-" + location_name)
				scene.currentSiteName = location_name
				scene.pending_explore_target = ""
				scene._save_site_json(location_name, jsonDic)
				scene.pending_site_update = false
			scene.aiMode.chat:
				var chat_text = scene._enforce_output_min_length(str(data.get("text", "")), scene.aiMode.chat)
				if scene.runtime_operation_lock or scene.currentState != scene.worldState.chat or scene.currentNpc == null:
					return
				await scene.npc_reply(chat_text)
				if scene.instant_gen_mode and scene.currentNpc != null:
					var _in = str(scene.currentNpc.npcName)
					var _id = str(scene.currentNpc.npcDescribe)
					scene.gen_img(scene._build_npc_image_prompt(_in, _id), "NPC:" + _in)
			scene.aiMode.action:
				var action_reply = scene._enforce_output_min_length(str(data.get("text", "")), scene.aiMode.action)
				action_reply = scene._enforce_action_narration_richness(action_reply)
				if action_reply is String and action_reply.strip_edges() != "":
					scene._set_event_flow_lock(true)
					scene.changeTextTo(scene.get_node("%speakerNameLabel"), "【旁白】")
					scene.changeTextTo(scene.response_label, scene.process_string(action_reply))
					if scene.instant_gen_mode and scene.currentSiteName != "":
						var _isd = scene._get_site_data(scene.currentSiteName)
						if !_isd.is_empty():
							scene.gen_img(scene._build_scene_image_prompt(scene.currentSiteName, _isd), scene.currentSiteName)
					var tool_tags = scene.get_content_in_angle_brackets(action_reply)
					var direct_tag_result = scene._apply_direct_action_tool_tags(action_reply)
					var handled_direct = bool(direct_tag_result.get("handled_any", false))
					var unresolved_tags = str(direct_tag_result.get("unresolved_tags", ""))
					var nav_target = str(direct_tag_result.get("nav_target", ""))
					if nav_target == "":
						nav_target = scene._extract_nav_target_from_text(action_reply)
					if unresolved_tags != "":
						var aprompts = [
							{"role":"system","content": scene.agent_prompt},
							{"role":"user","content": unresolved_tags}]
						await scene.ask_ai(aprompts, scene.aiMode.tools)
					elif !handled_direct:
						var infer_prompts = [
							{"role":"system","content": scene.agent_prompt + "\n若输入没有<>标签，也要从语义中尽力提取可执行方法；如果确实没有再回复没有方法被调用。\n重要限制：consume_items（玩家交出或消耗背包物品）禁止从语义推断，只能由明确的<接受...>标签触发。"},
							{"role":"user","content": "玩家行动：" + scene.last_action_input + "\n旁白结果：" + action_reply}
						]
						var _action_infer_src = (scene.last_action_input + " " + action_reply).strip_edges()
						if scene._contains_any_keyword(_action_infer_src, ["送", "给", "卖", "买", "赠", "以", "价", "路径", "地点", "创建", "传闻", "赶往", "前往"]):
							await scene.ask_ai(infer_prompts, scene.aiMode.tools)
						scene._auto_handle_action_search(scene.last_action_input, action_reply)
					if scene.currentState == scene.worldState.chat and scene.currentNpc != null:
						scene._record_current_chat_session("行动结果", "旁白", action_reply)
						scene._remember_important_event("<行动结果>" + str(scene.currentNpc.npcName) + "：" + scene.process_string(action_reply), scene.currentSiteName, str(scene.currentNpc.npcName))
					await scene._auto_apply_action_effects(scene.last_action_input, action_reply, tool_tags)
					if nav_target != "" and scene.currentState != scene.worldState.chat:
						scene.advance_time_minutes(float(randi_range(15, 60)), true)
						await scene.goto(nav_target)
					if scene.currentState != scene.worldState.chat and !scene._has_active_event_panel():
						scene._set_event_flow_lock(false)
				else:
					scene._set_event_flow_lock(false)
			scene.aiMode.sum:
				if scene.currentNpc != null:
					var sum_npc_name = str(scene.currentNpc.npcName).strip_edges()
					if sum_npc_name != "":
						if !scene.npcs.has(sum_npc_name) or !(scene.npcs[sum_npc_name] is Dictionary):
							scene.npcs[sum_npc_name] = {"npc_describe": "", "npc_log": [], "特征": "", "important_events": []}
						if !scene.npcs[sum_npc_name].has("npc_log") or !(scene.npcs[sum_npc_name]["npc_log"] is Array):
							scene.npcs[sum_npc_name]["npc_log"] = []
						scene.npcs[sum_npc_name]["npc_log"].append(str(data.get("text", "")))
						scene.addLog("你结束了与" + sum_npc_name + "的对话。" + str(data.get("text", "")))
			scene.aiMode.tools:
				if data["text"] is Array:
					await scene.handle_npc_instruction(data["text"])
				elif data["text"] is Dictionary:
					await scene.handle_npc_instruction([data["text"]])
				elif data["text"] is String:
					var parser = JSON.new()
					if parser.parse(data["text"]) == OK:
						var parsed = parser.get_data()
						if parsed is Array:
							await scene.handle_npc_instruction(parsed)
						elif parsed is Dictionary and parsed.has("function"):
							await scene.handle_npc_instruction([parsed])
	else:
		scene.changeTextTo(scene.response_label, "响应格式错误")
