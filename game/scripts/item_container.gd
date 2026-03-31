extends VBoxContainer

func add_item(itemToAdd:String, itemNum:int, itemTexture: Texture2D = null, itemDescription: String = "", effect_type: String = "none", effect_value: int = 0):
	for child in get_children():
		if child is item and child.item_name == itemToAdd:
			child.add_quantity(itemNum)
			if itemTexture != null or itemDescription != "" or effect_type != "none" or effect_value > 0:
				child.set_item_visual(itemTexture, itemDescription, effect_type, effect_value)
			return

	var new_item_lable = load("res://fabs/item_lable.tscn").instantiate() as item
	new_item_lable.setup(itemToAdd, itemNum, itemTexture, itemDescription)
	new_item_lable.set_item_visual(itemTexture, itemDescription, effect_type, effect_value)
	add_child(new_item_lable)

func update_item_visual(itemName: String, itemTexture: Texture2D, itemDescription: String, effect_type: String = "none", effect_value: int = 0) -> void:
	for child in get_children():
		if child is item and child.item_name == itemName:
			child.set_item_visual(itemTexture, itemDescription, effect_type, effect_value)
			return

func consume_item(itemToConsume:String, itemNum:int) -> Dictionary:
	# 遍历所有子节点寻找匹配的物品标签
	for child in get_children():
		if child is item and child.item_name == itemToConsume:
			if child.item_num < itemNum:
				return {
					"success": false,
					"available": child.item_num,
					"reason": "insufficient"
				}
			# 找到匹配物品，减少数量
			child.consume_quantity(itemNum)
			# 如果数量小于等于0，移除该物品标签
			if child.item_num <= 0:
				child.queue_free()
			# 找到并处理了一个匹配项，退出函数
			return {
				"success": true,
				"available": max(child.item_num, 0),
				"reason": "ok"
			}
	# 如果没有找到匹配的物品，可以在这里添加错误处理或调试信息
	print("未找到物品: ", itemToConsume)
	return {
		"success": false,
		"available": 0,
		"reason": "missing"
	}
