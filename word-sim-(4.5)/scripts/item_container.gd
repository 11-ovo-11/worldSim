extends VBoxContainer

func add_item(itemToAdd:String,itemNum:int):
	var new_item_lable = load("res://fabs/item_lable.tscn").instantiate()as item
	new_item_lable.item_name = itemToAdd
	new_item_lable.item_num = itemNum
	add_child(new_item_lable)

func consume_item(itemToConsume:String, itemNum:int):
	# 遍历所有子节点寻找匹配的物品标签
	for child in get_children():
		if child is item and child.item_name == itemToConsume:
			# 找到匹配物品，减少数量
			child.item_num -= itemNum
			# 如果数量小于等于0，移除该物品标签
			if child.item_num <= 0:
				child.queue_free()
			# 找到并处理了一个匹配项，退出函数
			return
	# 如果没有找到匹配的物品，可以在这里添加错误处理或调试信息
	print("未找到物品: ", itemToConsume)
