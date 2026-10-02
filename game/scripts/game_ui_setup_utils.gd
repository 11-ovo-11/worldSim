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
		scene.min_chars_dialog.title = "输出设置"
		var box = VBoxContainer.new()
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
		max_output_tip.text = "最大文本输出字数\n（单次对话/行动回复上限，按字符计算）"
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
		session_chars_tip.text = "当前会话记忆字符数\n（当前NPC会话在内存中保留的上限，存档时保存；对话历史按钮独立保留最近三条完整AI回复）"
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
		scene.min_chars_dialog.add_child(box)
		scene.add_child(scene.min_chars_dialog)
		scene.min_chars_dialog.confirmed.connect(scene._on_min_chars_dialog_confirmed)
	var _img_mode_panel = scene.get_node_or_null("%ImgModePanel")
	if _img_mode_panel == null:
		_img_mode_panel = scene.get_node_or_null("mainContainer/HBoxContainer/VBoxContainer/backgroundImg/ImgModePanel")
	if _img_mode_panel == null:
		return
	var _btn_instant = scene._get_instant_gen_button()
	if _btn_instant == null:
		return
	_btn_instant.toggle_mode = true
	var _apply_img_mode := func(is_instant: bool) -> void:
		var last_mode = bool(scene.get_meta("last_img_mode", bool(scene.instant_gen_mode)))
		var mode_changed = is_instant != last_mode
		scene.instant_gen_mode = is_instant
		_btn_instant.set_pressed_no_signal(is_instant)
		scene._bg_debug("img mode toggled instant=" + str(is_instant))
		if mode_changed:
			scene.addLog("<图片模式切换：" + ("即时生成" if is_instant else "只生成场景") + ">")
			if is_instant:
				scene.addLog("<即时生成已开启：将在每次对话/行动输出后尝试更新背景>")
		scene.set_meta("last_img_mode", is_instant)
		if !is_instant:
			GameImageRuntimeUtils.apply_scene_background_for_current_site(scene)
	var _wired = bool(scene.get_meta("img_mode_signal_wired", false))
	if !_wired or !_btn_instant.toggled.is_connected(_apply_img_mode):
		_btn_instant.toggled.connect(_apply_img_mode)
		scene.set_meta("img_mode_signal_wired", true)
	if !scene.has_meta("last_img_mode"):
		scene.set_meta("last_img_mode", bool(scene.instant_gen_mode))
	_apply_img_mode.call(bool(_btn_instant.button_pressed or scene.instant_gen_mode))
