extends ScrollContainer


func _on_log_container_child_entered_tree(_node: Node) -> void:
	create_tween().tween_property(
		self,
		"scroll_vertical",
		get_v_scroll_bar().max_value,
		0.5
	)
	pass # Replace with function body.
