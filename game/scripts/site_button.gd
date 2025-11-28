extends Button
class_name siteButton
var siteName = ""
var scene:GameManager
func _ready() -> void:
	text = siteName
	scene = get_tree().current_scene
	if !scene.sites.has(siteName)||!scene.sites[siteName].has("地点描述"):
		text = text+"\n(未探索)"
func _on_button_down() -> void:
	scene.goto(siteName)
	pass # Replace with function body.
