extends Label
class_name item
var item_name
var item_num
func _ready() -> void:
	text = item_name+"*"+str(item_num)
