extends RefCounted
class_name GameAutoEffectUtils

static func auto_apply_action_effects(scene: Node, action_input: String, action_reply: String, tool_tags: String) -> void:
	var source = (action_input + "\n" + action_reply).strip_edges()
	if source == "":
		return
	var action_context = scene._build_action_context_text(action_input, action_reply)

	var has_time_tool = tool_tags.find("设置时间") != -1 or tool_tags.find("set_time") != -1
	var has_money_tool = tool_tags.find("consume_items") != -1 or tool_tags.find("initiate_transaction") != -1
	if !has_money_tool:
		for ct in scene._extract_angle_tags(action_reply):
			var ctn = str(ct).replace("：", ":").strip_edges()
			if (ctn.begins_with("资产") or ctn.begins_with("金币") or ctn.begins_with("金钱")) and scene._extract_signed_number(ctn) != 0:
				has_money_tool = true
				break
	var passed_hours = 0.0

	var changed = false
	var money_changed = false

	var money_words = ["块钱", "元", "人民币", "现金", "钱"]
	var has_money_word = false
	for mw in money_words:
		if source.find(mw) != -1:
			has_money_word = true
			break
	if !has_money_tool and has_money_word and (source.find("扔") != -1 or source.find("丢") != -1 or source.find("放在地上") != -1):
		var amount = scene._extract_first_number(source)
		if amount > 0:
			var real_cost = min(amount, scene.money)
			scene.money -= real_cost
			money_changed = true
			scene.addLog("<你扔掉了" + str(real_cost) + "块钱，当前资产" + str(scene.money) + ">")
			if real_cost > 0 and randf() < scene.ACTION_PROACTIVE_NPC_RATE:
				await scene._spawn_context_npc("money", {}, action_context)
			changed = true

	if scene.currentState != scene.worldState.chat and !has_money_tool and !money_changed:
		var inferred_money_delta = scene._extract_money_delta_from_text(source)
		if inferred_money_delta != 0:
			var before_money = scene.money
			scene.money = max(0, scene.money + inferred_money_delta)
			var real_delta = scene.money - before_money
			if real_delta != 0:
				if real_delta < 0:
					scene.addLog("<行动花费" + str(abs(real_delta)) + "，当前资产" + str(scene.money) + ">")
				else:
					scene.addLog("<行动获得" + str(real_delta) + "，当前资产" + str(scene.money) + ">")
				changed = true

	if source.find("锻炼") != -1 or source.find("训练") != -1 or source.find("健身") != -1 or source.find("跑步") != -1:
		var hours = scene._extract_duration_hours(source)
		if hours <= 0.0:
			hours = 1.0
		if !has_time_tool:
			var rec_ex = scene.advance_time_minutes(hours * 60.0)
			passed_hours += float(rec_ex.get("hours", 0.0))
		var energy_cost = hours * 10.0
		scene.energy = max(0.0, scene.energy - energy_cost)
		scene.hp = min(100.0, scene.hp + hours * 1.5)
		scene.addLog("<锻炼" + str(hours) + "小时：体力-" + str(int(energy_cost)) + "，生命+" + str(int(hours * 1.5)) + ">")
		if randf() < scene.ACTION_PROACTIVE_NPC_RATE:
			await scene._spawn_context_npc("exercise", {}, action_context)
		changed = true

	if source.find("睡") != -1 and (source.find("睡觉") != -1 or source.find("睡一觉") != -1 or source.find("入睡") != -1):
		var sleep_hours = scene._extract_duration_hours(source)
		if !has_time_tool:
			if sleep_hours > 0.0:
				var rec_sleep = scene.advance_time_minutes(sleep_hours * 60.0)
				passed_hours += float(rec_sleep.get("hours", 0.0))
			else:
				var target_time = scene._extract_target_time(source)
				if target_time.get("valid", false):
					var current_in_day = fmod(scene.nowtime, 1440.0)
					var target_minutes = float(int(target_time.get("hour", 8)) * 60 + int(target_time.get("minute", 0)))
					var delta = target_minutes - current_in_day
					var has_next_day_hint = source.find("明天") != -1 or source.find("次日") != -1 or source.find("第二天") != -1
					if delta <= 0.0 and !has_next_day_hint:
						delta = 90.0
					elif delta <= 0.0:
						delta += 1440.0
					var rec_sleep_target = scene.advance_time_minutes(delta)
					passed_hours += float(rec_sleep_target.get("hours", 0.0))
				else:
					var current_hour = int(floor(fmod(scene.nowtime, 1440.0) / 60.0))
					if current_hour >= 22 or current_hour < 5:
						var wake_hour = randi_range(6, 8)
						var wake_min = 0 if randi_range(0, 1) == 0 else 30
						passed_hours += scene.set_time(wake_hour, wake_min)
					else:
						var default_sleep_hours = 1.5
						if source.find("午觉") != -1 or source.find("小睡") != -1 or source.find("打盹") != -1 or source.find("眯") != -1:
							default_sleep_hours = 0.5
						var rec_sleep_default = scene.advance_time_minutes(default_sleep_hours * 60.0)
						passed_hours += float(rec_sleep_default.get("hours", 0.0))
		scene.energy = min(100.0, scene.energy + 40.0)
		scene.hp = min(100.0, scene.hp + 8.0)
		scene.addLog("<你睡了一觉，醒来精神恢复了不少。>")
		changed = true

	if !has_time_tool and source.find("等到") != -1:
		var waiting_time = scene._extract_target_time(source)
		if waiting_time.get("valid", false):
			passed_hours += scene.set_time(int(waiting_time.get("hour", 0)), int(waiting_time.get("minute", 0)))
			changed = true

	var has_crime_tag = action_reply.find("<犯罪") != -1 or tool_tags.find("犯罪") != -1
	if !has_crime_tag:
		var crime_keywords = ["偷", "盗窃", "行窃", "防盗", "警报", "报警", "被抓", "保安"]
		for keyword in crime_keywords:
			if source.find(keyword) != -1:
				has_crime_tag = true
				break
	if has_crime_tag:
		scene.last_crime_event_context = scene._build_crime_context(action_input, action_reply, tool_tags)
		var penalty = randi_range(8, 20)
		scene.reputation = max(0.0, scene.reputation - penalty)
		scene.addLog("<违规行为被记录（" + scene.last_crime_event_context + "），声誉-" + str(penalty) + ">")
		if scene.currentState != scene.worldState.chat:
			var crime_npc = scene._pick_crime_npc_from_action(action_input)
			if !crime_npc.is_empty():
				await scene._spawn_context_npc("crime", crime_npc, scene.last_crime_event_context)
			else:
				await scene._spawn_context_npc("crime", {}, scene.last_crime_event_context)
		changed = true

	if !has_crime_tag and scene.currentState != scene.worldState.chat:
		await scene._trigger_time_pass_npc_event(passed_hours, action_context)

	if changed:
		scene.player_update()
