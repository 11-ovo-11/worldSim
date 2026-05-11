extends RefCounted
class_name GameProactiveNpcUtils

static func auto_initiate_npc_chat(scene: Node, npc_name: String, npc_describe: String) -> void:
	var retry = 0
	while (scene.ai_busy or scene.currentState == scene.worldState.chat) and retry < 200:
		await scene.get_tree().create_timer(0.15).timeout
		retry += 1
	if scene.ai_busy or scene.currentState == scene.worldState.chat:
		scene._set_event_flow_lock(false)
		return
	if !scene.npcs.has(npc_name):
		scene.npcs[npc_name] = {"npc_describe": npc_describe, "npc_log": [], "特征": ""}
	if !scene.npcs[npc_name].has("npc_describe"):
		scene.npcs[npc_name]["npc_describe"] = npc_describe
	if !scene.npcs[npc_name].has("npc_log"):
		scene.npcs[npc_name]["npc_log"] = []
	var new_npc = npc.new()
	new_npc.npcName = npc_name
	new_npc.scene = scene
	new_npc.npcDescribe = npc_describe
	var logs = ""
	scene._append_event_memories_to_npc_log(npc_name)
	for log_entry in scene.npcs[npc_name]["npc_log"]:
		logs += log_entry
	new_npc.npcLog = logs
	scene.newNpc = new_npc
	await scene.changeStateInto(scene.worldState.chat)
	scene._set_event_flow_lock(false)

static func spawn_context_npc(scene: Node, reason: String, forced_npc: Dictionary = {}, context_text: String = "") -> void:
	if scene.currentSiteName == "":
		return
	scene._set_event_flow_lock(true)
	var npc_name = ""
	var npc_describe = ""
	if !forced_npc.is_empty():
		npc_name = str(forced_npc.get("name", "")).strip_edges()
		npc_describe = str(forced_npc.get("describe", "正在此地活动"))
	else:
		var pool: Array = scene._build_proactive_npc_pool(reason)
		if pool.is_empty():
			scene._set_event_flow_lock(false)
			return
		var pick = pool[randi_range(0, pool.size() - 1)]
		npc_name = str(pick.get("name", "路人"))
		npc_describe = str(pick.get("describe", "正在此地活动"))
	if scene.dead_npc_names.has(npc_name):
		scene._set_event_flow_lock(false)
		return

	if npc_name == "":
		scene._set_event_flow_lock(false)
		return
	var npc_existed = scene.npcs.has(npc_name)
	if !scene.npcs.has(npc_name):
		scene.npcs[npc_name] = {"npc_describe": npc_describe, "npc_log": [], "特征": ""}
	if !scene.npcs[npc_name].has("npc_describe"):
		scene.npcs[npc_name]["npc_describe"] = npc_describe
	if !scene.npcs[npc_name].has("npc_log") or !(scene.npcs[npc_name]["npc_log"] is Array):
		scene.npcs[npc_name]["npc_log"] = []
	var scoped_context = context_text.strip_edges()
	if scoped_context == "" and reason == "crime":
		scoped_context = scene.last_crime_event_context.strip_edges()
	if scoped_context != "":
		var context_note = ""
		match reason:
			"money":
				context_note = "系统记录：玩家刚进行与金钱有关的行动【" + scoped_context + "】。你要围绕这件事开场。"
			"exercise":
				context_note = "系统记录：玩家刚进行体能相关行动【" + scoped_context + "】。你要围绕这件事开场。"
			"time_pass":
				context_note = "系统记录：玩家刚完成一段行动【" + scoped_context + "】。你要围绕这件事开场。"
			"crime":
				context_note = "系统记录：玩家刚刚因【" + scoped_context + "】触发警报，你需要围绕这件事追问。"
			_:
				context_note = ""
		if context_note != "":
			var context_log_arr: Array = scene.npcs[npc_name]["npc_log"]
			for i in range(context_log_arr.size() - 1, -1, -1):
				var old_note = str(context_log_arr[i])
				if old_note.begins_with("系统记录：玩家刚"):
					context_log_arr.remove_at(i)
			if context_log_arr.is_empty() or str(context_log_arr[context_log_arr.size() - 1]) != context_note:
				context_log_arr.append(context_note)
			scene.npcs[npc_name]["npc_log"] = context_log_arr
	if reason == "crime":
		scene.addLog("<" + npc_name + "拦住了你，开始质问刚才的异常动静。>")

	if npc_existed:
		await scene.get_tree().create_timer(0.4).timeout
		await auto_initiate_npc_chat(scene, npc_name, str(scene.npcs[npc_name].get("npc_describe", npc_describe)))
		return

	scene.create_NPC(npc_name, scene.currentSiteName, npc_describe)
	scene.addLog("<" + npc_name + "注意到了你，主动走了过来。>")
	await scene.get_tree().create_timer(0.8).timeout
	await auto_initiate_npc_chat(scene, npc_name, npc_describe)
