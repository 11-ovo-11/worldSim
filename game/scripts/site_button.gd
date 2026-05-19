extends Button
class_name siteButton
var siteName = ""
var scene:GameManager
func _ready() -> void:
	text = siteName
	scene = get_tree().current_scene
	if !scene.sites.has(siteName) or str(scene.sites[siteName].get("地点描述", "")).strip_edges() == "":
		text = text+"\n(未探索)"
func _on_button_down() -> void:
	if scene == null:
		return
	if scene.has_method("_is_runtime_transition_locked") and scene._is_runtime_transition_locked():
		return
	if scene.has_method("request_site_switch"):
		scene.request_site_switch(siteName)
	else:
		scene.goto(siteName)
	pass # Replace with function body.
