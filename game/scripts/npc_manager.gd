extends Node

# NPC管理
var npcs: Dictionary
var currentNpc: npc
var currentSiteName: String
var speakerNameLabel
var response_label

func handle_npc_interaction():
    # 处理NPC交互逻辑
    pass

func update_npc_dialogue():
    # 更新NPC对话逻辑
    pass

func npc_reply(reply: String):
    if currentNpc == null:
        print("Error: currentNpc is null in npc_reply")
        return
    changeTextTo(speakerNameLabel, currentNpc.npcName)
    changeTextTo(response_label, process_string(reply))
    _record_current_chat_session("对话回复", str(currentNpc.npcName), reply)
    currentNpc.currentChat +=  currentNpc.npcName +":"+ reply + "\n"
    _remember_important_event("<对话>" + currentNpc.npcName + "：" + process_string(reply), currentSiteName, currentNpc.npcName)
    var direct_location_only = _apply_direct_npc_tool_tags(reply)
    if !direct_location_only:
        _try_create_location_from_dialogue(reply)
    _maybe_create_related_npc_from_dialogue(reply)

func changeTextTo(_label, _text):
    # Placeholder for changing text logic
    pass

func process_string(input: String) -> String:
    # Placeholder for processing string logic
    return input

func _record_current_chat_session(_kind: String, _speaker: String, _text: String):
    # Placeholder for recording chat session logic
    pass

func _remember_important_event(_event: String, _site: String, _npc: String):
    # Placeholder for remembering important event logic
    pass

func _apply_direct_npc_tool_tags(_reply: String) -> bool:
    # Placeholder for applying direct NPC tool tags logic
    return false

func _try_create_location_from_dialogue(_reply: String):
    # Placeholder for creating location from dialogue logic
    pass

func _maybe_create_related_npc_from_dialogue(_reply: String):
    # Placeholder for creating related NPC from dialogue logic
    pass
