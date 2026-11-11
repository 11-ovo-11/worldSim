extends RefCounted
class_name GameRuntimeDebug

static func setup(scene: Node) -> void:
	scene.get_node("%日志按钮").pressed.connect(show_tab.bind(scene, false))
	scene.get_node("%调试按钮").pressed.connect(show_tab.bind(scene, true))
	apply_view(scene)

static func show_tab(scene: Node, debug: bool) -> void:
	scene.showing_debug = debug
	scene.showing_dialogue_history = false
	apply_view(scene)
	if debug and is_instance_valid(scene.instant_background_service):
		scene.instant_background_service.poll_debug()

static func apply_view(scene: Node) -> void:
	var debug = scene.showing_debug
	var history = scene.showing_dialogue_history and not debug
	scene.get_node("%logContainer").get_parent().visible = not debug and not history
	scene.get_node("%DialogueHistoryScroll").visible = history
	scene.get_node("%调试滚动").visible = debug
	scene.get_node("%日志按钮").set_pressed_no_signal(not debug)
	scene.get_node("%调试按钮").set_pressed_no_signal(debug)
	scene.get_node("%DialogueHistoryButton").text = "日志" if history else "对话历史"
	scene.get_node("%LogPanelTitle").text = "对话历史（最近三条 AI 回复）" if history else "日志"
	scene.get_node("%LogPanelTitle").visible = history
	if debug:
		refresh(scene)

static func append(scene: Node, category: String, message: String) -> void:
	var row = "[" + Time.get_time_string_from_system() + "][" + category + "] " + message.strip_edges().left(16000)
	scene.debug_records.append(row)
	while scene.debug_records.size() > 200:
		scene.debug_records.pop_front()
	if scene.showing_debug:
		refresh(scene)

static func refresh(scene: Node) -> void:
	var label = scene.get_node("%调试文本") as RichTextLabel
	var scroll = scene.get_node("%调试滚动") as ScrollContainer
	var bar = scroll.get_v_scroll_bar()
	var follow = bar.value >= bar.max_value - bar.page - 12
	label.text = "暂无调试信息。开启即时生图后可查看请求阶段与等待原因。" if scene.debug_records.is_empty() else "\n\n".join(scene.debug_records)
	if follow:
		scroll.set_deferred("scroll_vertical", int(bar.max_value))
