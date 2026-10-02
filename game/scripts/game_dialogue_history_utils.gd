extends RefCounted
class_name GameDialogueHistoryUtils

const HISTORY_LIMIT := 3

static func record_reply(scene: Node, speaker: String, text: String) -> void:
	var body = text.strip_edges()
	if body.is_empty():
		return
	scene.recent_ai_replies.append({"speaker": speaker, "text": body})
	while scene.recent_ai_replies.size() > HISTORY_LIMIT:
		scene.recent_ai_replies.pop_front()
	if scene.showing_dialogue_history:
		refresh_view(scene)

static func refresh_view(scene: Node) -> void:
	var rows: Array[String] = []
	for record in scene.recent_ai_replies:
		rows.append("【" + str(record["speaker"]) + "】\n" + str(record["text"]))
	var label = scene.get_node("%DialogueHistoryText") as RichTextLabel
	label.text = "暂无 AI 回复。" if rows.is_empty() else "\n\n".join(rows)
	# 不使用逐字动画，历史正文一次显示并允许跨回复选择、复制。
	label.visible_ratio = 1.0
	scene.get_node("%DialogueHistoryScroll").set_deferred("scroll_vertical", 0)

static func apply_view(scene: Node) -> void:
	scene.get_node("%logContainer").get_parent().visible = not scene.showing_dialogue_history
	scene.get_node("%DialogueHistoryScroll").visible = scene.showing_dialogue_history
	scene.get_node("%DialogueHistoryButton").text = "日志" if scene.showing_dialogue_history else "对话历史"
	scene.get_node("%LogPanelTitle").text = "对话历史（最近三条 AI 回复）" if scene.showing_dialogue_history else "日志"

static func toggle_view(scene: Node) -> void:
	scene.showing_dialogue_history = not scene.showing_dialogue_history
	if scene.showing_dialogue_history:
		refresh_view(scene)
	apply_view(scene)

static func clear_history(scene: Node) -> void:
	scene.recent_ai_replies.clear()
	scene.showing_dialogue_history = false
	scene.get_node("%DialogueHistoryText").text = ""
	apply_view(scene)
