extends HBoxContainer
class_name eventContainer
var settled:bool = true
enum eventType{deal}
var scene:GameManager
func _ready() -> void:
	scene = get_tree().current_scene
	$Label.text = ""
	$yes.visible = false
	$no.visible = false
	custom_minimum_size.y = 0
	set_deal_event()
var itemToAdd
var itemNum
var itemPrice
func set_deal_event():
	await create_tween().tween_property(self,"custom_minimum_size:y",50,0.2).finished
	await scene.changeTextTo($Label,"以" + str(itemPrice) + "每件（共" + str(itemNum) + "件，总价" + str(itemPrice * itemNum) + "）购买" + itemToAdd + "？")
	$yes.visible = true
	$no.visible = true
func _on_yes_button_down() -> void:
	var total_price = itemPrice * itemNum
	if scene.money < total_price:
		scene.addLog("<金币不足，无法购买" + itemToAdd + "X" + str(itemNum) + ">")
		close()
		return
	scene.money -= total_price
	scene.player_update()
	scene.add_item(itemToAdd,itemNum)
	scene.addLog("你购买了" + itemToAdd + "X" + str(itemNum) + "，花费" + str(total_price))
	close()
	pass # Replace with function body.
func close():
	await scene.changeTextTo($Label,"")
	$yes.visible = false
	$no.visible = false
	await create_tween().tween_property(self,"custom_minimum_size:y",0,0.2).finished
	queue_free()
func _on_no_button_down() -> void:
	close()
	pass # Replace with function body.
