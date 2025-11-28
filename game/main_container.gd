extends VBoxContainer
func _ready() -> void:
	visible = false
	for i in get_children():
		if i is Control:
			i.modulate = Color.TRANSPARENT
func showUP():
	visible = true
	for i in get_children():
		if i is Control:
			create_tween().tween_property(i,"modulate",Color.WHITE,0.3)
			await get_tree().create_timer(0.1).timeout
