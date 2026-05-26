extends VBoxContainer
var settled:bool = true
enum eventType{deal, gift}
var scene:GameManager
var pending_events: Array = []
func _ready() -> void:
	scene = get_tree().current_scene
	$"../水平分割线".visible = false
var itemToAdd
var itemNum
var itemPrice

func _enqueue_event(event_data: Dictionary) -> void:
	if event_data.is_empty():
		return
	pending_events.append(event_data)
	_show_next_event()

func _show_next_event() -> void:
	for child in get_children():
		if child is eventContainer:
			$"../水平分割线".visible = true
			return
	if pending_events.is_empty():
		$"../水平分割线".visible = false
		return
	var event_data: Dictionary = pending_events.pop_front()
	var newEvent = load("res://fabs/event_container.tscn").instantiate() as eventContainer
	newEvent.event_mode = int(event_data.get("event_mode", 0))
	newEvent.itemToAdd = event_data.get("item_name", "")
	newEvent.itemNum = int(event_data.get("quantity", 0))
	newEvent.itemPrice = int(event_data.get("price", 0))
	newEvent.is_total_price = bool(event_data.get("is_total_price", false))
	newEvent.action_text = str(event_data.get("action_text", ""))
	newEvent.action_prompt = str(event_data.get("action_prompt", ""))
	$"../水平分割线".visible = true
	add_child(newEvent)

func got_deal_event(item_name: String, quantity: int, price: int, is_total: bool = false):
	_enqueue_event({
		"event_mode": eventContainer.EventMode.DEAL,
		"item_name": item_name,
		"quantity": quantity,
		"price": price,
		"is_total_price": is_total
	})

func got_action_confirm_event(action_text: String, prompt_text: String = ""):
	_enqueue_event({
		"event_mode": eventContainer.EventMode.ACTION_CONFIRM,
		"action_text": action_text,
		"action_prompt": prompt_text
	})

func got_gift_event(item_name: String, quantity: int):
	_enqueue_event({
		"event_mode": eventContainer.EventMode.GIFT,
		"item_name": item_name,
		"quantity": quantity,
		"price": 0,
		"is_total_price": true
	})

func _on_child_entered_tree(_node: Node) -> void:
	$"../水平分割线".visible = true
	pass # Replace with function body.

func _on_child_exiting_tree(_node: Node) -> void:
	call_deferred("_show_next_event")
	pass # Replace with function body.
