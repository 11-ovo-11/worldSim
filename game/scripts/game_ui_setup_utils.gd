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
		scene.dialogue_min_chars_spin.min_value = 40
		scene.dialogue_min_chars_spin.max_value = 2000
		scene.dialogue_min_chars_spin.step = 10
		scene.dialogue_min_chars_spin.value = scene.dialogue_min_chars
		var action_tip = Label.new()
		action_tip.text = "行动最小字数"
		scene.action_min_chars_spin = SpinBox.new()
		scene.action_min_chars_spin.min_value = 40
		scene.action_min_chars_spin.max_value = 2000
		scene.action_min_chars_spin.step = 10
		scene.action_min_chars_spin.value = scene.action_narration_min_chars
		var timeout_tip = Label.new()
		timeout_tip.text = "最长响应时间（秒）"
		scene.timeout_seconds_spin = SpinBox.new()
		scene.timeout_seconds_spin.min_value = 5
		scene.timeout_seconds_spin.max_value = 120
		scene.timeout_seconds_spin.step = 5
		scene.timeout_seconds_spin.value = scene.ai_request_timeout_seconds
		box.add_child(dialogue_tip)
		box.add_child(scene.dialogue_min_chars_spin)
		box.add_child(action_tip)
		box.add_child(scene.action_min_chars_spin)
		box.add_child(timeout_tip)
		box.add_child(scene.timeout_seconds_spin)
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
