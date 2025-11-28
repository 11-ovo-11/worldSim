extends Label


func _on_money_bar_value_changed(value: float) -> void:
	text = str(int(round(value)))
	pass # Replace with function body.
