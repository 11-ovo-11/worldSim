extends RefCounted
class_name GameUiSetupUtils

static func setup_output_mode_controls(scene: Node) -> void:
	if scene.response_label == null:
		return
	var controls_ready = scene.output_length_button != null and is_instance_valid(scene.output_length_button) and scene.force_release_button != null and is_instance_valid(scene.force_release_button) and scene.continue_button != null and is_instance_valid(scene.continue_button)
	if !controls_ready:
		scene.output_length_button = scene.get_node_or_null("%OutputLengthButton")
		scene.force_release_button = scene.get_node_or_null("%ForceReleaseButton")
		scene.continue_button = scene.get_node_or_null("%ContinueButton")
		if scene.output_length_button != null and !scene.output_length_button.pressed.is_connected(scene._on_output_length_button_pressed):
			scene.output_length_button.pressed.connect(scene._on_output_length_button_pressed)
		if scene.force_release_button != null and !scene.force_release_button.pressed.is_connected(scene._on_force_release_button_pressed):
			scene.force_release_button.pressed.connect(scene._on_force_release_button_pressed)
		if scene.continue_button != null and !scene.continue_button.pressed.is_connected(scene._on_continue_button_pressed):
			scene.continue_button.pressed.connect(scene._on_continue_button_pressed)
		scene.min_chars_dialog = AcceptDialog.new()
		scene.min_chars_dialog.title = "对话与图片设置"
		var box = VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dialogue_tip = Label.new()
		dialogue_tip.text = "对话最小字数"
		scene.dialogue_min_chars_spin = SpinBox.new()
		scene.dialogue_min_chars_spin.min_value = 160
		scene.dialogue_min_chars_spin.max_value = 2000
		scene.dialogue_min_chars_spin.step = 10
		scene.dialogue_min_chars_spin.value = scene.dialogue_min_chars
		var action_tip = Label.new()
		action_tip.text = "行动最小字数"
		scene.action_min_chars_spin = SpinBox.new()
		scene.action_min_chars_spin.min_value = 160
		scene.action_min_chars_spin.max_value = 2000
		scene.action_min_chars_spin.step = 10
		scene.action_min_chars_spin.value = scene.action_narration_min_chars
		var max_output_tip = Label.new()
		max_output_tip.text = "最大文本输出字数\n（单次对话/行动回复的可见字符硬上限，后端会先重写收束）"
		max_output_tip.add_theme_font_size_override("font_size", 13)
		scene.max_output_chars_spin = SpinBox.new()
		scene.max_output_chars_spin.min_value = 200
		scene.max_output_chars_spin.max_value = 6000
		scene.max_output_chars_spin.step = 100
		scene.max_output_chars_spin.value = scene.max_output_chars
		var timeout_tip = Label.new()
		timeout_tip.text = "最长响应时间（秒）"
		scene.timeout_seconds_spin = SpinBox.new()
		scene.timeout_seconds_spin.min_value = 5
		scene.timeout_seconds_spin.max_value = 120
		scene.timeout_seconds_spin.step = 5
		scene.timeout_seconds_spin.value = scene.ai_request_timeout_seconds
		var history_lines_tip = Label.new()
		history_lines_tip.text = "对话记忆轮数\n（保留最近多少条对话/行动记录）"
		history_lines_tip.add_theme_font_size_override("font_size", 13)
		scene.chat_history_lines_spin = SpinBox.new()
		scene.chat_history_lines_spin.min_value = 4
		scene.chat_history_lines_spin.max_value = 30
		scene.chat_history_lines_spin.step = 1
		scene.chat_history_lines_spin.value = scene.chat_history_max_lines
		var history_chars_tip = Label.new()
		history_chars_tip.text = "近期对话字符数\n（每次请求保留的近期记录总长度）"
		history_chars_tip.add_theme_font_size_override("font_size", 13)
		scene.chat_history_chars_spin = SpinBox.new()
		scene.chat_history_chars_spin.min_value = 600
		scene.chat_history_chars_spin.max_value = 6000
		scene.chat_history_chars_spin.step = 100
		scene.chat_history_chars_spin.value = scene.chat_history_max_chars
		var session_chars_tip = Label.new()
		session_chars_tip.text = "当前会话记忆字符数\n（NPC会话与非对话行动历史各自的保留上限，随存档保存；展示历史独立保留三条AI回复）"
		session_chars_tip.add_theme_font_size_override("font_size", 13)
		scene.session_memory_chars_spin = SpinBox.new()
		scene.session_memory_chars_spin.min_value = 800
		scene.session_memory_chars_spin.max_value = 8000
		scene.session_memory_chars_spin.step = 100
		scene.session_memory_chars_spin.value = scene.session_memory_max_chars
		var world_chars_tip = Label.new()
		world_chars_tip.text = "世界设定字符数\n（每次请求带入的世界设定上限，过大可能挤占对话记忆）"
		world_chars_tip.add_theme_font_size_override("font_size", 13)
		scene.world_context_chars_spin = SpinBox.new()
		scene.world_context_chars_spin.min_value = 300
		scene.world_context_chars_spin.max_value = 4000
		scene.world_context_chars_spin.step = 100
		scene.world_context_chars_spin.value = scene.world_context_max_chars
		box.add_child(dialogue_tip)
		box.add_child(scene.dialogue_min_chars_spin)
		box.add_child(action_tip)
		box.add_child(scene.action_min_chars_spin)
		box.add_child(max_output_tip)
		box.add_child(scene.max_output_chars_spin)
		box.add_child(timeout_tip)
		box.add_child(scene.timeout_seconds_spin)
		box.add_child(history_lines_tip)
		box.add_child(scene.chat_history_lines_spin)
		box.add_child(history_chars_tip)
		box.add_child(scene.chat_history_chars_spin)
		box.add_child(session_chars_tip)
		box.add_child(scene.session_memory_chars_spin)
		box.add_child(world_chars_tip)
		box.add_child(scene.world_context_chars_spin)
		scene.instant_background_checkbox = CheckButton.new()
		scene.instant_background_checkbox.text = "即时生成场景背景"
		scene.instant_background_checkbox.button_pressed = scene.instant_gen_mode
		box.add_child(scene.instant_background_checkbox)
		var image_hint = Label.new()
		image_hint.text = "AI回复后交给本机Codex命令行生图并替换背景，不阻塞输入。\n需Codex登录和生图权限，耗时可能数十秒；关闭后保留最后一张背景。"
		image_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		image_hint.add_theme_font_size_override("font_size", 13)
		box.add_child(image_hint)
		scene.instant_background_status_label = Label.new()
		scene.instant_background_status_label.text = "已开启：AI回复后生成背景" if scene.instant_gen_mode else "已关闭即时生图"
		scene.instant_background_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scene.instant_background_status_label.add_theme_font_size_override("font_size", 13)
		box.add_child(scene.instant_background_status_label)
		# Keep long help/status text scrollable instead of stretching the dialog
		# past the window (autowrap labels need a bounded initial width).
		var settings_scroll = ScrollContainer.new()
		settings_scroll.custom_minimum_size = Vector2(560, 560)
		settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		settings_scroll.add_child(box)
		scene.min_chars_dialog.add_child(settings_scroll)
		scene.add_child(scene.min_chars_dialog)
		scene.min_chars_dialog.confirmed.connect(scene._on_min_chars_dialog_confirmed)
	var _img_mode_panel = scene.get_node_or_null("%ImgModePanel")
	if _img_mode_panel == null:
		_img_mode_panel = scene.get_node_or_null("mainContainer/HBoxContainer/VBoxContainer/backgroundImg/ImgModePanel")
	if _img_mode_panel == null:
		return
	# The binary setting above is the only control; hide the old image button.
	_img_mode_panel.visible = false
