extends ProgressBar
var target_value:float
func _process(delta: float) -> void:
	value = lerp(value,target_value,0.2)
