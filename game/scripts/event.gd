extends VBoxContainer
var settled:bool = true
enum eventType{deal, gift}
var scene:GameManager
func _ready() -> void:
	scene = get_tree().current_scene
	$"../水平分割线".visible = false
var itemToAdd
var itemNum
var itemPrice
func got_deal_event(item_name: String, quantity: int, price: int, is_total: bool = false):
	# 关闭当前所有未完成的交易，避免堆叠
	for child in get_children():
		if child is eventContainer:
			child.close()
	var newEvent = load("res://fabs/event_container.tscn").instantiate() as eventContainer
	newEvent.event_mode = 0 # DEAL
	newEvent.itemToAdd = item_name
	newEvent.itemNum = quantity
	newEvent.itemPrice = price
	newEvent.is_total_price = is_total
	$"../水平分割线".visible = true
	add_child(newEvent)

func got_gift_event(item_name: String, quantity: int):
	for child in get_children():
		if child is eventContainer:
			child.close()
	var newEvent = load("res://fabs/event_container.tscn").instantiate() as eventContainer
	newEvent.event_mode = 1 # GIFT
	newEvent.itemToAdd = item_name
	newEvent.itemNum = quantity
	newEvent.itemPrice = 0
	newEvent.is_total_price = true
	$"../水平分割线".visible = true
	add_child(newEvent)

func _on_child_entered_tree(_node: Node) -> void:
	$"../水平分割线".visible = true
	pass # Replace with function body.

func _on_child_exiting_tree(_node: Node) -> void:
	if get_child_count()==1:
		$"../水平分割线".visible = false
	pass # Replace with function body.
