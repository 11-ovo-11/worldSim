extends VBoxContainer
var settled:bool = true
enum eventType{deal}
var scene:GameManager
func _ready() -> void:
	scene = get_tree().current_scene
	$"../水平分割线".visible = false
var itemToAdd
var itemNum
var itemPrice
func got_deal_event(item_name: String, quantity: int, price: int):
	var newEvent = load("res://fabs/event_container.tscn").instantiate() as eventContainer
	newEvent.itemToAdd = item_name
	newEvent.itemNum = quantity
	newEvent.itemPrice = price
	$"../水平分割线".visible = true
	add_child(newEvent)

func _on_child_entered_tree(_node: Node) -> void:
	$"../水平分割线".visible = true
	pass # Replace with function body.

func _on_child_exiting_tree(_node: Node) -> void:
	if get_child_count()==1:
		$"../水平分割线".visible = false
	pass # Replace with function body.
