extends VBoxContainer

func add_item(itemToAdd:String, itemNum:int, itemTexture: Texture2D = null, itemDescription: String = ""):
	for child in get_children():
		if child is item and child.item_name == itemToAdd:
			child.add_quantity(itemNum)
			if itemTexture != null or itemDescription != "":
				child.set_item_visual(itemTexture, itemDescription)
			return

	var new_item_lable = load("res://fabs/item_lable.tscn").instantiate() as item
	new_item_lable.setup(itemToAdd, itemNum, itemTexture, itemDescription)
	add_child(new_item_lable)

func update_item_visual(itemName: String, itemTexture: Texture2D, itemDescription: String) -> void:
	for child in get_children():
		if child is item and child.item_name == itemName:
			child.set_item_visual(itemTexture, itemDescription)
			return

func consume_item(itemToConsume:String, itemNum:int):
	# 遍历所有子节点寻找匹配的物品标签
	for child in get_children():
		if child is item and child.item_name == itemToConsume:
			# 找到匹配物品，减少数量
			child.consume_quantity(itemNum)
			# 如果数量小于等于0，移除该物品标签
			if child.item_num <= 0:
				child.queue_free()
			# 找到并处理了一个匹配项，退出函数
			return
	# 如果没有找到匹配的物品，可以在这里添加错误处理或调试信息
	print("未找到物品: ", itemToConsume)
