extends HBoxContainer
class_name eventContainer
var settled:bool = true
enum eventType{deal}
enum EventMode{DEAL, GIFT}
var scene:GameManager
var event_mode: EventMode = EventMode.DEAL
func _ready() -> void:
	scene = get_tree().current_scene
	$Label.text = ""
	$yes.visible = false
	$no.visible = false
	custom_minimum_size.y = 0
	if scene != null and scene.has_method("refresh_interaction_locks"):
		scene.refresh_interaction_locks()
	set_event_view()
var itemToAdd
var itemNum
var itemPrice
var is_total_price: bool = false
func set_event_view():
	await create_tween().tween_property(self,"custom_minimum_size:y",50,0.2).finished
	var display_text: String
	if event_mode == EventMode.GIFT:
		display_text = "是否接受" + str(itemNum) + "个" + str(itemToAdd) + "？"
	else:
		if is_total_price:
			var unit = itemPrice / max(1, itemNum)
			display_text = "以总价" + str(itemPrice) + "（单价约" + str(unit) + "，共" + str(itemNum) + "件）购买" + itemToAdd + "？"
		else:
			display_text = "以" + str(itemPrice) + "每件（共" + str(itemNum) + "件，总价" + str(itemPrice * itemNum) + "）购买" + itemToAdd + "？"
	await scene.changeTextTo($Label, display_text)
	$yes.visible = true
	$no.visible = true
func _on_yes_button_down() -> void:
	if event_mode == EventMode.GIFT:
		scene.add_item(itemToAdd,itemNum)
		scene.addLog("你接受了" + itemToAdd + "X" + str(itemNum))
		await scene.on_event_decision("gift", true, str(itemToAdd), int(itemNum), 0)
		close()
		return
	var total_price = itemPrice if is_total_price else itemPrice * itemNum
	if scene.money < total_price:
		scene.addLog("<金币不足，无法购买" + itemToAdd + "X" + str(itemNum) + ">")
		await scene.on_event_decision("deal", false, str(itemToAdd), int(itemNum), total_price)
		close()
		return
	scene.money -= total_price
	scene.player_update()
	scene.add_item(itemToAdd,itemNum)
	scene.addLog("你购买了" + itemToAdd + "X" + str(itemNum) + "，花费" + str(total_price))
	await scene.on_event_decision("deal", true, str(itemToAdd), int(itemNum), total_price)
	close()
	pass # Replace with function body.
func close():
	await scene.changeTextTo($Label,"")
	$yes.visible = false
	$no.visible = false
	await create_tween().tween_property(self,"custom_minimum_size:y",0,0.2).finished
	queue_free()
	if scene != null and scene.has_method("refresh_interaction_locks"):
		scene.call_deferred("refresh_interaction_locks")

func close_immediate() -> void:
	$Label.text = ""
	$yes.visible = false
	$no.visible = false
	custom_minimum_size.y = 0
	queue_free()
	if scene != null and scene.has_method("refresh_interaction_locks"):
		scene.call_deferred("refresh_interaction_locks")

func _on_no_button_down() -> void:
	var total_price = itemPrice if is_total_price else itemPrice * itemNum
	if event_mode == EventMode.GIFT:
		await scene.on_event_decision("gift", false, str(itemToAdd), int(itemNum), 0)
	else:
		await scene.on_event_decision("deal", false, str(itemToAdd), int(itemNum), total_price)
	close()
	pass # Replace with function body.
