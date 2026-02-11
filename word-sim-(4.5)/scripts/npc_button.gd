extends Button
class_name npcButton
var npcName = ""
var scene:GameManager
func _ready() -> void:
	text = npcName
	scene = get_tree().current_scene

func _on_button_down() -> void:
	var currentNpc = npc.new()
	currentNpc.npcName = npcName
	currentNpc.scene = scene
	currentNpc.npcDescribe = scene.npcs[npcName]["npc_describe"]
	if "npc_log" not in scene.npcs[npcName]:
		scene.npcs[npcName]["npc_log"] = []
	var logs = ""
	if scene.npcs[npcName]["npc_log"] != []:
		for i in scene.npcs[npcName]["npc_log"]:
			logs+=i
	currentNpc.npcLog = logs
	scene.newNpc = currentNpc
	scene.changeStateInto(GameManager.worldState.chat)
	pass # Replace with function body.
