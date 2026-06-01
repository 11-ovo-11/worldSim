extends Node
class_name GameManager

const GamePrompts = preload("res://scripts/game_prompts.gd")
const GameVisualUtils = preload("res://scripts/game_visual_utils.gd")
const GameTextUtils = preload("res://scripts/game_text_utils.gd")
const GameImageUtils = preload("res://scripts/game_image_utils.gd")
const GameStorageUtils = preload("res://scripts/game_storage_utils.gd")
const GameHttpUtils = preload("res://scripts/game_http_utils.gd")
const GameAiUtils = preload("res://scripts/game_ai_utils.gd")
const GameNpcInferUtils = preload("res://scripts/game_npc_infer_utils.gd")
const GameParseUtils = preload("res://scripts/game_parse_utils.gd")
const GameEventUtils = preload("res://scripts/game_event_utils.gd")
const GameNpcPoolUtils = preload("res://scripts/game_npc_pool_utils.gd")
const GameActionUtils = preload("res://scripts/game_action_utils.gd")
const GameActionTagUtils = preload("res://scripts/game_action_tag_utils.gd")
const GameMemoryUtils = preload("res://scripts/game_memory_utils.gd")
const GameDialogueExpandUtils = preload("res://scripts/game_dialogue_expand_utils.gd")
const GameAutoEffectUtils = preload("res://scripts/game_auto_effect_utils.gd")
const GameItemProfileUtils = preload("res://scripts/game_item_profile_utils.gd")
const GameUiSetupUtils = preload("res://scripts/game_ui_setup_utils.gd")
const GameImageRuntimeUtils = preload("res://scripts/game_image_runtime_utils.gd")
const GameProactiveNpcUtils = preload("res://scripts/game_proactive_npc_utils.gd")
const GameSaveLoadUtils = preload("res://scripts/game_save_load_utils.gd")
const GameFlowRuntimeUtils = preload("res://scripts/game_flow_runtime_utils.gd")

@onready var input_text_edit = %InputTextEdit
@onready var send_button = %SendButton
@onready var response_label = %ResponseLabel
@onready var http_request = $HTTPRequest
@onready var dialogue_container = %DialogueContainer
@onready var dialogue_input = %DialogueTextEdit
@onready var dialogue_button = %DialogueButton
@onready var save_button = %SaveButton
@onready var load_button = %LoadButton

enum worldState {explore, chat}
enum aiMode {init_background,init_env,explore, chat, sum, tools, action, validate_entity, refine_event}

var chat_url = "http://127.0.0.1:5000/chat"
var agent_url = "http://127.0.0.1:5000/agent"
var image_api_url = "http://localhost:5000/generate_image"

const PICTURE_DIR = "D:/毕设/worldSim/game/picture/"
const SESSION_RESOURCE_DIR = PICTURE_DIR + "session/"
const SCENE_IMG_DIR = SESSION_RESOURCE_DIR + "scenes/"
const ITEM_IMG_DIR = SESSION_RESOURCE_DIR + "items/"
const ITEM_PROFILE_DIR = SESSION_RESOURCE_DIR + "item_profiles/"
const SAVE_DIR = "D:/毕设/worldSim/game/saves/"
const SAVE_SLOT_DIR = SAVE_DIR + "slot_1/"
const SAVE_RESOURCE_DIR = SAVE_SLOT_DIR + "resources/"
const SAVE_SCENE_IMG_DIR = SAVE_RESOURCE_DIR + "scenes/"
const SAVE_ITEM_IMG_DIR = SAVE_RESOURCE_DIR + "items/"
const SAVE_ITEM_PROFILE_DIR = SAVE_RESOURCE_DIR + "item_profiles/"
const NPC_IMG_DIR = SESSION_RESOURCE_DIR + "npcs/"
const SAVE_NPC_IMG_DIR = SAVE_RESOURCE_DIR + "npcs/"
const SAVE_FILE = SAVE_SLOT_DIR + "save.json"

var pending_site_update: bool = false
var pending_img_queue: Array = []
var inflight_img_site: String = ""
var inflight_img_request: Dictionary = {}
var inflight_img_started_ms: int = 0
const IMG_RETRY_MAX_ATTEMPTS: int = 3
const IMG_RETRY_BASE_DELAY_SEC: float = 1.0
var explore_needs_retry: bool = false
var site_loading_lock: bool = false
var event_flow_lock: bool = false
var last_crime_event_context: String = ""
var last_action_input: String = ""
var last_dialogue_input: String = ""
var preferred_input_focus: String = "action"
var pending_action_confirm: Dictionary = {}
var important_event_memories: Array = []
var current_chat_session_npc: String = ""
var current_chat_session_records: Array = []
var pending_explore_target: String = ""
var explore_route_retry_count: int = 0
var bg_debug_enabled: bool = true
var has_saved_in_session: bool = false
var dead_npc_names: Array = []
var dialogue_min_chars: int = 90
var action_narration_min_chars: int = 90
var output_mode_debug_enabled: bool = false
var output_length_button: Button
var min_chars_dialog: AcceptDialog
var dialogue_min_chars_spin: SpinBox
var action_min_chars_spin: SpinBox
var timeout_seconds_spin: SpinBox
var img_watchdog_seq: int = 0
var pending_entity_records: Dictionary = {"npcs": {}, "locations": {}}
var last_entity_validation_response: String = ""
var last_event_refine_response: String = ""
var pending_event_refine_queue: Array = []
var event_refine_inflight: bool = false
var event_refine_cache: Dictionary = {}

var sites: Dictionary
var npcs: Dictionary
var items: Dictionary
var rumors:Dictionary
var siteImgs: Dictionary
var npcImgs: Dictionary = {}
var itemProfiles: Dictionary = {}
var instant_gen_mode: bool = false
var playerName: String = "武汉理工大学2022级学生戴子洋"
var world_seed_input: String = ""
var currentSiteName: String
var currentNpc: npc
var newNpc: npc
var currentState = worldState.explore
var currentMode = aiMode.explore
var nowtime = 500

var envDic:Dictionary
var timePrompt:String = ""
var weatherPrompt:String = ""

var money:int = 1000
var energy:float = 100
var hp:float = 100
var reputation:float = 100
const PASSIVE_ENERGY_RECOVERY_PER_HOUR: float = 4.0
const PASSIVE_HP_RECOVERY_PER_HOUR: float = 1.2
const ACTION_PROACTIVE_NPC_RATE: float = 0.2

var role_prompt = GamePrompts.ROLE_PROMPT
var agent_prompt:String = GamePrompts.AGENT_PROMPT
var item_profile_prompt:String = GamePrompts.ITEM_PROFILE_PROMPT
var validation_feedback_prompt:String = GamePrompts.VALIDATION_FEEDBACK_PROMPT
var action_prompt:String = GamePrompts.ACTION_PROMPT

var ai_busy: bool = false
var text_update_seq: int = 0
var _active_text_tweens: Dictionary = {}
var _ignore_next_request_completed: bool = false
var ai_request_timeout_seconds: float = 30.0
var force_release_button: Button
var continue_button: Button
var runtime_operation_lock: bool = false
var lock_debug_enabled: bool = false
const LOG_LABEL_SCENE := preload("res://fabs/log_rich_text_label.tscn")
var max_visible_logs: int = 180
var _process_strip_regex := RegEx.new()
var _process_newline_regex := RegEx.new()

func _log_lock_state(tag: String) -> void:
	if !lock_debug_enabled:
		return
	var has_event_panel = _has_active_event_panel()
	var text_busy = !_active_text_tweens.is_empty()
	print("[LOCK_DEBUG][" + tag + "] state=" + str(currentState) + ", ai_busy=" + str(ai_busy) + ", event_flow_lock=" + str(event_flow_lock) + ", site_loading_lock=" + str(site_loading_lock) + ", runtime_operation_lock=" + str(runtime_operation_lock) + ", has_event_panel=" + str(has_event_panel) + ", text_busy=" + str(text_busy))

func _is_runtime_transition_locked() -> bool:
	return runtime_operation_lock or ai_busy or site_loading_lock or event_flow_lock or _has_active_event_panel() or !_active_text_tweens.is_empty()

func _set_runtime_operation_lock(v: bool, reason: String = "") -> void:
	runtime_operation_lock = v
	if lock_debug_enabled:
		_log_lock_state("set_runtime_operation_lock:" + str(v) + ":" + reason)
	_apply_interaction_locks()

func _ready():
	_ensure_process_regex_ready()
	send_button.connect("pressed", _on_send_button_pressed)
	dialogue_button.connect("pressed", _on_dialogue_button_pressed)
	save_button.connect("pressed", _on_save_button_pressed)
	load_button.connect("pressed", _on_load_button_pressed)
	if input_text_edit != null:
		input_text_edit.placeholder_text = "输入行动，留空则继续"
	if %npcIcon is Control:
		%npcIcon.custom_minimum_size.x = 0
		(%npcIcon as Control).mouse_filter = Control.MOUSE_FILTER_STOP
		(%npcIcon as Control).gui_input.connect(_on_npc_icon_gui_input)
	_prepare_session_resource_dir()
	dialogue_container.visible = false
	# %backgroundImg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 原先使用 Nearest 过滤会强化像素感，这里改回线性以更接近原图显示。
	%backgroundImg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# %backgroundImg.material = preload("res://assets/asciiShader.gdshader")
	# 关闭背景图的 ASCII/后处理材质，直接显示生成原图。
	%backgroundImg.material = null
	changeTextTo(%siteName, "未定位")
	player_update()
	_setup_output_mode_controls()
	_apply_interaction_locks()
	call_deferred("_focus_active_input")

func _setup_output_mode_controls() -> void:
	GameUiSetupUtils.setup_output_mode_controls(self)

func _on_output_length_button_pressed() -> void:
	if min_chars_dialog == null:
		return
	if dialogue_min_chars_spin != null:
		dialogue_min_chars_spin.value = dialogue_min_chars
	if action_min_chars_spin != null:
		action_min_chars_spin.value = action_narration_min_chars
	if timeout_seconds_spin != null:
		timeout_seconds_spin.value = ai_request_timeout_seconds
	min_chars_dialog.popup_centered(Vector2i(360, 240))

func _on_min_chars_dialog_confirmed() -> void:
	if dialogue_min_chars_spin == null or action_min_chars_spin == null:
		return
	dialogue_min_chars = clamp(int(dialogue_min_chars_spin.value), 40, 2000)
	action_narration_min_chars = clamp(int(action_min_chars_spin.value), 40, 2000)
	if timeout_seconds_spin != null:
		ai_request_timeout_seconds = clamp(float(timeout_seconds_spin.value), 5.0, 120.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_handle_exit_cleanup()

var background:String

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not ai_busy:
			if dialogue_container.visible and dialogue_input.has_focus():
				_on_dialogue_button_pressed()
			elif input_text_edit.has_focus():
				_on_send_button_pressed()

func changeStateInto(stateToChange: worldState):
	await GameInteractionRuntimeUtils.change_state_into(self, stateToChange)

func _force_exit_chat_runtime() -> void:
	GameInteractionRuntimeUtils.force_exit_chat_runtime(self)

func _start_chat_session(npc_name: String) -> void:
	GameInteractionRuntimeUtils.start_chat_session(self, npc_name)

func _end_chat_session() -> void:
	GameInteractionRuntimeUtils.end_chat_session(self)

func _compact_history_rows_for_recovery(rows: Array, recent_keep: int = 6, summary_keep: int = 8, max_item_chars: int = 28) -> Array:
	return GameTextUtils.compact_history_rows_for_recovery(rows, recent_keep, summary_keep, max_item_chars)

func _compact_text_for_recovery(text: String, recent_keep: int = 8) -> String:
	return GameTextUtils.compact_text_for_recovery(text, recent_keep)

func _compact_current_context_for_recovery() -> void:
	GameInteractionRuntimeUtils.compact_current_context_for_recovery(self)

func _record_current_chat_session(kind: String, speaker: String, text: String) -> void:
	GameInteractionRuntimeUtils.record_current_chat_session(self, kind, speaker, text)

func get_current_chat_session_memory(npc_name: String = "") -> String:
	var target_name = npc_name.strip_edges()
	if target_name != "" and target_name != current_chat_session_npc:
		return ""
	if current_chat_session_records.is_empty():
		return ""
	var lines: Array = []
	for i in range(current_chat_session_records.size()):
		var row_text = str(current_chat_session_records[i]).strip_edges()
		if row_text == "":
			continue
		lines.append("- " + row_text)
	if lines.is_empty():
		return ""
	var joined = "以下是当前会话中刚发生且必须延续影响的内容：\n" + "\n".join(lines)
	return joined

func _clip_prompt_text(text: String, _max_chars: int) -> String:
	var src = str(text).strip_edges()
	return src

func _clear_all_npc_dialogue_memory() -> void:
	for npc_name in npcs.keys():
		var npc_data = npcs[npc_name]
		if npc_data is Dictionary:
			npc_data["npc_log"] = []
			npcs[npc_name] = npc_data

func _get_site_data(site_name: String) -> Dictionary:
	if !sites.has(site_name):
		return {}
	var data = sites[site_name]
	if data is Dictionary:
		return data
	var disk_site = _load_site_json(site_name)
	if !disk_site.is_empty():
		sites[site_name] = disk_site
		return disk_site
	return {}

func _build_scene_image_prompt(site_name: String, site_data: Dictionary) -> String:
	return GameVisualUtils.build_scene_image_prompt(site_name, site_data, world_seed_input, background)

func _infer_npc_location_for_prompt(npc_name: String) -> String:
	var target_name = str(npc_name).strip_edges()
	if target_name == "":
		return str(currentSiteName).strip_edges()
	for site_name in sites.keys():
		if !(sites[site_name] is Dictionary):
			continue
		var site_dic: Dictionary = sites[site_name]
		if site_dic.has("npc") and site_dic["npc"] is Dictionary and (site_dic["npc"] as Dictionary).has(target_name):
			return str(site_name).strip_edges()
	return str(currentSiteName).strip_edges()

func _build_npc_image_prompt(npc_name: String, npc_describe: String, npc_location: String = "") -> String:
	var resolved_location = str(npc_location).strip_edges()
	if resolved_location == "":
		resolved_location = _infer_npc_location_for_prompt(npc_name)
	var location_desc = ""
	if resolved_location != "" and sites.has(resolved_location) and sites[resolved_location] is Dictionary:
		location_desc = str((sites[resolved_location] as Dictionary).get("地点描述", "")).strip_edges()
	return GameVisualUtils.build_npc_image_prompt(npc_name, npc_describe, world_seed_input, background, resolved_location, location_desc)

func _get_instant_gen_button() -> BaseButton:
	var btn = get_node_or_null("%InstantGenButton")
	if btn is BaseButton:
		return btn
	btn = get_node_or_null("mainContainer/HBoxContainer/VBoxContainer/backgroundImg/ImgModePanel/InstantGenButton")
	if btn is BaseButton:
		return btn
	return null

func _is_instant_gen_active() -> bool:
	var btn = _get_instant_gen_button()
	if btn != null:
		var pressed = bool(btn.button_pressed)
		if instant_gen_mode != pressed:
			instant_gen_mode = pressed
		return pressed
	return bool(instant_gen_mode)

func _build_image_request_payload(prompt: String, target_site: String) -> Dictionary:
	var bg_size := Vector2.ZERO
	var bg_min_size := Vector2.ZERO
	if %backgroundImg is Control:
		var bg_ctrl := %backgroundImg as Control
		bg_size = bg_ctrl.size
		bg_min_size = bg_ctrl.custom_minimum_size
	return GameImageUtils.build_image_request_payload(prompt, target_site, currentSiteName, bg_size, bg_min_size)

func _resolve_image_slot_size(target_type: String) -> Vector2i:
	var npc_size := Vector2.ZERO
	var npc_min_size := Vector2.ZERO
	if %npcIcon is Control:
		var npc_ctrl := %npcIcon as Control
		npc_size = npc_ctrl.size
		npc_min_size = npc_ctrl.custom_minimum_size
	var bg_size := Vector2.ZERO
	var bg_min_size := Vector2.ZERO
	if %backgroundImg is Control:
		var bg_ctrl := %backgroundImg as Control
		bg_size = bg_ctrl.size
		bg_min_size = bg_ctrl.custom_minimum_size
	return GameImageUtils.resolve_image_slot_size(target_type, npc_size, npc_min_size, bg_size, bg_min_size)

func _fit_image_to_target_slot(raw_image: Image, target_type: String) -> Image:
	var target_size = _resolve_image_slot_size(target_type)
	return GameImageUtils.fit_image_to_target_slot(raw_image, target_size)

func _resolve_image_callback_target(callback_site: String, response: Dictionary) -> String:
	return GameImageUtils.resolve_image_callback_target(callback_site, response)

func _build_location_visual_hint(site_name: String, cn_desc: String) -> String:
	return GameVisualUtils.build_location_visual_hint(site_name, cn_desc)

func _build_cn_desc_visual_anchor(cn_desc: String) -> String:
	return GameVisualUtils.build_cn_desc_visual_anchor(cn_desc)

func _build_location_fallback_description(location_name: String, from_site_name: String = "") -> String:
	return GameVisualUtils.build_location_fallback_description(location_name, from_site_name)

func _detect_setting_style_signals() -> Dictionary:
	return GameVisualUtils.detect_setting_style_signals(world_seed_input, background)

func _build_setting_consistency_guard_text(sig: Dictionary) -> String:
	return GameVisualUtils.build_setting_consistency_guard_text(sig)

func _extract_route_candidates_from_site_json(json_dic: Dictionary) -> Array:
	return GameTextUtils.extract_route_candidates_from_site_json(json_dic)

func _resolve_site_alias(site_name: String) -> String:
	return GameTextUtils.resolve_site_alias(site_name, sites)

func _bg_debug(msg: String) -> void:
	if !bg_debug_enabled:
		return
	print("[BG_DEBUG] " + msg)
	addLog("<BG_DEBUG> " + msg)

func goto(where: String):
	await GameFlowRuntimeUtils.goto(self, where)

func _describe_image_target(target_site: String) -> String:
	return GameImageUtils.describe_image_target(target_site)

func _try_use_cached_image_for_target(target_site: String) -> bool:
	return GameImageRuntimeUtils.try_use_cached_image_for_target(self, target_site)

func _build_bootstrap_scene_image_prompt(site_name: String) -> String:
	return GameVisualUtils.build_bootstrap_scene_image_prompt(site_name, background)

func prefetch_scene_image_for_setup(site_name: String) -> void:
	var target = _resolve_site_alias(str(site_name).strip_edges())
	if target == "":
		target = str(site_name).strip_edges()
	if target == "":
		return
	if _try_use_cached_image_for_target(target):
		_bg_debug("setup prefetch skipped (cache hit), target=" + target)
		return
	var prompt = _build_bootstrap_scene_image_prompt(target)
	if prompt == "":
		return
	_bg_debug("setup prefetch start, target=" + target)
	gen_img(prompt, target)

func site_update(show_description: bool = true, unlock_after: bool = true, add_arrival_log: bool = true):
	var site_data = _get_site_data(currentSiteName)
	if site_data.is_empty():
		if unlock_after:
			_set_site_loading_lock(false)
		return
	set_meta("hydrating_pending_entities", true)
	_consume_pending_entities_for_site(currentSiteName)
	set_meta("hydrating_pending_entities", false)
	site_data = _get_site_data(currentSiteName)
	if site_data.is_empty():
		if unlock_after:
			_set_site_loading_lock(false)
		return
	var display_routes: Array = []
	if !site_data.has("能前往的地点") or !(site_data["能前往的地点"] is Array):
		site_data["能前往的地点"] = []
	if (site_data["能前往的地点"] as Array).is_empty() and sites.size() > 1:
		for key in sites.keys():
			var candidate = str(key)
			if candidate != "" and candidate != currentSiteName and !(site_data["能前往的地点"] as Array).has(candidate):
				(site_data["能前往的地点"] as Array).append(candidate)
				if (site_data["能前往的地点"] as Array).size() >= 6:
					break
	for route_name in site_data.get("能前往的地点", []):
		var normalized_route = _resolve_site_alias(str(route_name).strip_edges())
		if normalized_route != "" and normalized_route != currentSiteName and !display_routes.has(normalized_route):
			display_routes.append(normalized_route)
	if display_routes.is_empty() and currentSiteName != "":
		display_routes.append(currentSiteName)
	_save_site_json(currentSiteName, site_data)
	changeTextTo(%siteName, currentSiteName)
	if show_description and currentState != worldState.chat and !event_flow_lock:
		changeTextTo(response_label, str(site_data.get("地点描述", "")),15)
	clear_children(%site_buttons)
	clear_children(%npc_buttons)
	for i in display_routes:
		var new_site_button = load("res://fabs/site_button.tscn").instantiate() as siteButton
		new_site_button.siteName = i
		%site_buttons.add_child(new_site_button)

	for i in site_data.get("npc", {}):
		if dead_npc_names.has(i):
			continue
		if i not in npcs:
			npcs[i] = {"npc_log": [], "特征": "", "important_events": []}
		if !npcs[i].has("npc_log") or !(npcs[i]["npc_log"] is Array):
			npcs[i]["npc_log"] = []
		if !npcs[i].has("important_events") or !(npcs[i]["important_events"] is Array):
			npcs[i]["important_events"] = []
		npcs[i]["npc_describe"] = site_data.get("npc", {}).get(i, "")
		var new_npc_button = load("res://fabs/npc_button.tscn").instantiate() as npcButton
		new_npc_button.npcName = i
		%npc_buttons.add_child(new_npc_button)
	if add_arrival_log:
		addLog("你抵达了" + currentSiteName)
	if unlock_after:
		_set_site_loading_lock(false)

func player_update():
	%moneyBar.target_value = str(money)
	%energy.target_value = energy
	%hp.target_value = hp
	%reputation.target_value = reputation
var tools: Array = GamePrompts.get_npc_tools()

func ask_ai(message: Array, askmode: aiMode):
	currentMode = askmode
	set_ai_busy(true)
	_ignore_next_request_completed = false
	if askmode == aiMode.init_background or askmode == aiMode.init_env:
		http_request.timeout = 0.0
	else:
		http_request.timeout = ai_request_timeout_seconds
	var outbound_messages = _compact_messages_for_request(_decorate_messages_for_output_mode(message, askmode))
	var body = [outbound_messages,null,"text"]
	match askmode:
		aiMode.tools:
			body = [outbound_messages,tools,"text"]
		aiMode.chat, aiMode.action:
			body = [outbound_messages,tools,"text"]
		aiMode.explore:
			body = [outbound_messages,null,"json_object"]
	var url = chat_url
	var json_string = JSON.stringify(body)
	if http_request.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
		await http_request.request_completed

	var err = ERR_CANT_CONNECT
	for attempt in range(3):
		if http_request.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
			await http_request.request_completed
		err = http_request.request(
			url,
			["Content-Type: application/json"],
			HTTPClient.METHOD_POST,
			json_string
		)
		if err == OK:
			break
		if err != ERR_BUSY and err != 44:
			break
		var tree = get_tree()
		if tree == null:
			break
		await tree.create_timer(0.08 + float(attempt) * 0.12).timeout
	if err != OK:
		if err == 44:
			changeTextTo(response_label, "请求失败：网络请求通道暂不可用(44)，请重试")
		else:
			changeTextTo(response_label, "请求失败: " + str(err))
		if askmode == aiMode.init_env and has_node("mainMenu") and $mainMenu.has_method("if_weather_failed"):
			$mainMenu.if_weather_failed("环境生成请求失败，已使用默认天气。")
		set_ai_busy(false)
		return
	await $HTTPRequest.request_completed

func _decorate_messages_for_output_mode(message: Array, askmode: aiMode) -> Array:
	if askmode != aiMode.chat and askmode != aiMode.action:
		return message
	var copied = message.duplicate(true)
	var min_chars = dialogue_min_chars if askmode == aiMode.chat else action_narration_min_chars
	min_chars = max(40, min_chars)
	var constraint = "输出要求：本次回复至少" + str(min_chars) + "字，信息完整、自然，不要省略关键细节，不要用固定收尾句硬凑字数。"
	copied.push_front({"role":"system", "content": constraint})
	return copied

func _compact_prompt_content(text: String) -> String:
	return GameAiUtils.compact_prompt_content(text)

func _compact_messages_for_request(messages: Array) -> Array:
	return GameAiUtils.compact_messages_for_request(messages)

func _output_mode_debug(msg: String) -> void:
	if !output_mode_debug_enabled:
		return
	print("[OUTPUT_MODE_DEBUG] " + msg)

func _tail_preview(text: String, max_chars: int = 48) -> String:
	return GameAiUtils.tail_preview(text, max_chars)

func _build_mode_consistent_extensions(_base_text: String, _askmode: aiMode) -> Array:
	return []

func _strip_angle_tags(text: String) -> String:
	return GameAiUtils.strip_angle_tags(text)

func _expand_text_to_min_chars(text: String, _min_chars: int, _askmode: aiMode) -> String:
	return text

func _enforce_output_min_length(text: String, _askmode: aiMode) -> String:
	return text

func _enforce_action_narration_richness(text: String) -> String:
	return text

func _looks_like_action_or_dialogue_phrase(text: String) -> bool:
	return GameEntityUtils.looks_like_action_phrase(text)

func _extract_compact_entity_candidate(raw_text: String, max_len: int = 14) -> String:
	return GameEntityUtils.extract_compact_entity(raw_text, max_len)

func _split_entity_with_modifier(raw_text: String, max_len: int = 14) -> Dictionary:
	return GameEntityUtils.split_entity_with_modifier(raw_text, max_len)

func _infer_entity_kind(name_text: String, context_text: String = "") -> String:
	return GameEntityUtils.infer_entity_kind(name_text, context_text)

func _is_valid_generated_location_name(raw_name: String) -> bool:
	if _looks_like_person_reference(GameEntityUtils.cleanup_location_candidate(raw_name)):
		return false
	return GameEntityUtils.is_valid_location_name_basic(raw_name)

func _is_valid_generated_npc_name(raw_name: String) -> bool:
	return GameEntityUtils.is_valid_npc_name(raw_name)

func _extract_angle_tags(input_string: String) -> Array:
	return GameAiUtils.extract_angle_tags(input_string)

func _apply_direct_npc_tool_tags(reply: String) -> Dictionary:
	return GameDialogueExpandUtils.apply_direct_npc_tool_tags(self, reply)

func _build_tool_inference_user_prompt(interaction_kind: String, source_input: String, reply_text: String, angle_tags_text: String = "", handled_direct_tags: Array = []) -> String:
	return GamePrompts.build_tool_inference_user_prompt(interaction_kind, source_input, reply_text, angle_tags_text, handled_direct_tags)

func _request_tool_inference(interaction_kind: String, source_input: String, reply_text: String, angle_tags_text: String = "", handled_direct_tags: Array = []) -> void:
	await GameFlowRuntimeUtils.request_tool_inference(self, interaction_kind, source_input, reply_text, angle_tags_text, handled_direct_tags)

func _is_location_query_dialogue(input_text: String) -> bool:
	return GameTextUtils.is_location_query_dialogue(input_text)

func _cleanup_location_candidate(raw_text: String) -> String:
	return GameEntityUtils.cleanup_location_candidate(raw_text)

func _looks_like_person_reference(target: String) -> bool:
	return GameDialogueExpandUtils.looks_like_person_reference(npcs, target)

func _extract_location_target_from_dialogue(input_text: String) -> String:
	return GameDialogueExpandUtils.extract_location_target_from_dialogue(self, input_text)

func _reply_has_location_clue(reply_text: String) -> bool:
	return GameDialogueExpandUtils.reply_has_location_clue(self, reply_text)

func _try_create_location_from_dialogue(reply: String) -> bool:
	return GameDialogueExpandUtils.try_create_location_from_dialogue(self, reply)

func _sanitize_generated_npc_name(raw_name: String) -> String:
	return GameEntityUtils.sanitize_npc_name(raw_name)

func _is_bad_generated_npc_name(npc_label: String) -> bool:
	return GameEntityUtils.is_bad_npc_name(npc_label)

func _fallback_relation_npc_name(query_text: String) -> String:
	return GameEntityUtils.fallback_relation_npc_name(query_text)

func _extract_location_name_from_reply(reply_text: String) -> String:
	return GameDialogueExpandUtils.extract_location_name_from_reply(self, reply_text)

func _extract_unknown_npc_target_from_query(query_text: String) -> String:
	return GameEntityUtils.extract_unknown_npc_target_from_query(query_text)

func _is_relation_npc_query(input_text: String) -> bool:
	return GameEntityUtils.is_relation_npc_query(input_text)

func _guess_related_npc_desc(query_text: String, source_npc_name: String) -> String:
	return GameNpcInferUtils.guess_related_npc_desc(GameTextUtils.normalize_single_line_input(query_text), source_npc_name)

func _track_pending_entity(kind: String, entity_name: String, info: Dictionary = {}) -> void:
	var k = str(kind).strip_edges()
	var n = str(entity_name).strip_edges()
	if k == "" or n == "":
		return
	if !pending_entity_records.has("npcs") or !(pending_entity_records["npcs"] is Dictionary):
		pending_entity_records["npcs"] = {}
	if !pending_entity_records.has("locations") or !(pending_entity_records["locations"] is Dictionary):
		pending_entity_records["locations"] = {}
	var bucket = pending_entity_records.get(k + "s", {})
	if !(bucket is Dictionary):
		bucket = {}
	var row: Dictionary = {}
	if bucket.has(n) and bucket[n] is Dictionary:
		row = bucket[n]
	for key in info.keys():
		var info_key = str(key)
		if info_key == "context":
			var old_ctx = str(row.get("context", "")).strip_edges()
			var new_ctx = str(info[key]).strip_edges()
			if new_ctx == "":
				continue
			if old_ctx == "":
				row["context"] = new_ctx
			elif old_ctx.find(new_ctx) == -1:
				row["context"] = (old_ctx + "；" + new_ctx).left(240)
		else:
			row[info_key] = info[key]
	row["name"] = n
	bucket[n] = row
	pending_entity_records[k + "s"] = bucket

func _consume_pending_entities_for_site(site_name: String) -> void:
	var site = str(site_name).strip_edges()
	if site == "":
		return
	if pending_entity_records.has("locations") and pending_entity_records["locations"] is Dictionary:
		var loc_map: Dictionary = pending_entity_records["locations"]
		var consumed_loc: Array = []
		for loc_name in loc_map.keys():
			var lrow = loc_map[loc_name]
			if !(lrow is Dictionary):
				continue
			var from_site = str(lrow.get("from", "")).strip_edges()
			if from_site == "" or from_site != site:
				continue
			consumed_loc.append(loc_name)
			var already_connected = sites.has(site) and (sites[site].get("能前往的地点", []) as Array).has(str(loc_name))
			if already_connected:
				continue
			create_location(site + "-" + str(loc_name))
		for lk in consumed_loc:
			loc_map.erase(lk)
		pending_entity_records["locations"] = loc_map
	if !pending_entity_records.has("npcs") or !(pending_entity_records["npcs"] is Dictionary):
		return
	var npc_map: Dictionary = pending_entity_records["npcs"]
	if npc_map.is_empty():
		return
	var consumed: Array = []
	for npc_name in npc_map.keys():
		var row = npc_map[npc_name]
		if !(row is Dictionary):
			continue
		var home = str(row.get("location", "")).strip_edges()
		if home == "" or home != site:
			continue
		var already_at_site = npcs.has(str(npc_name)) and sites.has(site) and (sites[site].get("npc", {}) as Dictionary).has(str(npc_name))
		consumed.append(npc_name)
		if already_at_site:
			continue
		var desc = str(row.get("desc", "")).strip_edges()
		var modifier = str(row.get("modifier", "")).strip_edges()
		if modifier != "" and desc.find(modifier) == -1:
			desc = (desc + "（" + modifier + "）").strip_edges()
		if desc == "":
			desc = "在此地活动"
		create_NPC(str(npc_name), site, desc)
	for key in consumed:
		npc_map.erase(key)
	pending_entity_records["npcs"] = npc_map

func _extract_named_people_from_dialogue(reply_text: String) -> Array:
	return GameDialogueExpandUtils.extract_named_people_from_dialogue(self, reply_text)

func _maybe_create_related_npc_from_dialogue(reply: String) -> void:
	GameDialogueExpandUtils.maybe_create_related_npc_from_dialogue(self, reply)

func _maybe_create_unknown_npc_from_dialogue(reply: String) -> void:
	GameDialogueExpandUtils.maybe_create_unknown_npc_from_dialogue(self, reply)

func npc_reply(reply: String, model_tool_calls: Array = []):
	await GameDialogueExpandUtils.npc_reply(self, reply, model_tool_calls)

func process_string(input: String) -> String:
	_ensure_process_regex_ready()
	var src = str(input)
	var result = src
	if _process_strip_regex != null and _process_strip_regex.is_valid():
		result = _process_strip_regex.sub(result, "", true)
	if _process_newline_regex != null and _process_newline_regex.is_valid():
		result = _process_newline_regex.sub(result, "\n", true)
	return result.strip_edges()

func _ensure_process_regex_ready() -> void:
	if _process_strip_regex == null:
		_process_strip_regex = RegEx.new()
	if !_process_strip_regex.is_valid():
		if _process_strip_regex.compile("<[^>]*>") != OK:
			push_warning("process_string strip regex compile failed")
	if _process_newline_regex == null:
		_process_newline_regex = RegEx.new()
	if !_process_newline_regex.is_valid():
		if _process_newline_regex.compile("\n\n+") != OK:
			push_warning("process_string newline regex compile failed")

func get_content_in_angle_brackets(input_string: String) -> String:
	return GameAiUtils.get_content_in_angle_brackets(input_string)

func _has_pending_image_target(target_site: String) -> bool:
	return GameImageRuntimeUtils.has_pending_image_target(self, target_site)
func _enqueue_image_request(prompt: String, target_site: String, retry_count: int = 0, front: bool = false) -> void:
	GameImageRuntimeUtils.enqueue_image_request(self, prompt, target_site, retry_count, front)
func _dispatch_image_request(req: Dictionary) -> int:
	return GameImageRuntimeUtils.dispatch_image_request(self, req)
func _is_retryable_image_error(response_code: int, error_msg: String) -> bool:
	return GameImageRuntimeUtils.is_retryable_image_error(self, response_code, error_msg)
func _queue_image_retry(req: Dictionary, reason: String = "") -> bool:
	return GameImageRuntimeUtils.queue_image_retry(self, req, reason)
func _schedule_image_retry(prompt: String, target_site: String, retry_count: int, delay_sec: float) -> void:
	await GameImageRuntimeUtils.schedule_image_retry(self, prompt, target_site, retry_count, delay_sec)

func gen_img(prompt: String, site_name: String = ""):
	var target_site = site_name.strip_edges()
	if target_site == "":
		target_site = currentSiteName
	if target_site == "":
		return
	if prompt == "":
		if pending_site_update:
			pending_site_update = false
			site_update()
		return
	if _try_use_cached_image_for_target(target_site):
		_bg_debug("gen_img skipped (cache hit), target=" + target_site)
		if pending_site_update and !target_site.begins_with("NPC:") and !target_site.begins_with("ITEM:"):
			pending_site_update = false
			site_update()
		return
	_enqueue_image_request(prompt, target_site, 0, false)
	_drain_pending_img()

func _start_img_watchdog(target_site: String) -> void:
	img_watchdog_seq += 1
	var seq = img_watchdog_seq
	await get_tree().create_timer(200.0).timeout
	if seq != img_watchdog_seq:
		return
	if pending_site_update and inflight_img_site == target_site:
		_bg_debug("img watchdog timeout fallback, site=" + target_site)
		pending_site_update = false
		site_update(true, true, false)

func _sanitize_filename(file_name: String) -> String:
	return GameStorageUtils.sanitize_filename(file_name)

func _ensure_dir(path: String) -> void:
	GameStorageUtils.ensure_dir(path)

func _clear_dir_contents(dir_path: String) -> void:
	GameStorageUtils.clear_dir_contents(dir_path)

func _copy_file(src_path: String, dst_path: String) -> void:
	GameStorageUtils.copy_file(src_path, dst_path)

func _copy_dir_recursive(src_dir: String, dst_dir: String) -> void:
	GameStorageUtils.copy_dir_recursive(src_dir, dst_dir)

func _prepare_session_resource_dir() -> void:
	GameStorageUtils.prepare_session_resource_dir(
		SESSION_RESOURCE_DIR,
		SCENE_IMG_DIR,
		ITEM_IMG_DIR,
		ITEM_PROFILE_DIR,
		NPC_IMG_DIR
	)
	has_saved_in_session = false

func _sync_session_resources_to_save() -> void:
	GameStorageUtils.sync_session_resources_to_save(
		SAVE_SLOT_DIR,
		SAVE_RESOURCE_DIR,
		SCENE_IMG_DIR,
		ITEM_IMG_DIR,
		ITEM_PROFILE_DIR,
		NPC_IMG_DIR,
		SAVE_SCENE_IMG_DIR,
		SAVE_ITEM_IMG_DIR,
		SAVE_ITEM_PROFILE_DIR,
		SAVE_NPC_IMG_DIR
	)

func _restore_session_resources_from_save() -> void:
	GameStorageUtils.restore_session_resources_from_save(
		SESSION_RESOURCE_DIR,
		SCENE_IMG_DIR,
		ITEM_IMG_DIR,
		ITEM_PROFILE_DIR,
		NPC_IMG_DIR,
		SAVE_SCENE_IMG_DIR,
		SAVE_ITEM_IMG_DIR,
		SAVE_ITEM_PROFILE_DIR,
		SAVE_NPC_IMG_DIR
	)

func _handle_exit_cleanup() -> void:
	GameStorageUtils.handle_exit_cleanup(has_saved_in_session, SESSION_RESOURCE_DIR)

func _save_image_png(image: Image, dir: String, file_name: String) -> void:
	GameStorageUtils.save_image_png(image, dir, file_name)

func _load_image_png(dir: String, file_name: String) -> Texture2D:
	return GameStorageUtils.load_image_png(dir, file_name)

func _restore_runtime_image_caches_from_disk() -> void:
	siteImgs.clear()
	npcImgs.clear()
	for site_key in sites.keys():
		var site_name = str(site_key).strip_edges()
		if site_name == "":
			continue
		var s_tex = _load_image_png(SCENE_IMG_DIR, site_name)
		if s_tex != null:
			siteImgs[site_name] = s_tex
	for npc_key in npcs.keys():
		var npc_name = str(npc_key).strip_edges()
		if npc_name == "":
			continue
		var n_tex = _load_image_png(NPC_IMG_DIR, npc_name)
		if n_tex != null:
			npcImgs[npc_name] = n_tex

func _save_site_json(site_name: String, site_data: Dictionary) -> void:
	GameStorageUtils.save_json_dict(SCENE_IMG_DIR, site_name, site_data)

func _load_site_json(site_name: String) -> Dictionary:
	return GameStorageUtils.load_json_dict(SCENE_IMG_DIR, site_name)

func _save_item_profile_json(item_name: String, profile: Dictionary) -> void:
	GameStorageUtils.save_json_dict(ITEM_PROFILE_DIR, item_name, profile, "\t")

func _load_item_profile_json(item_name: String) -> Dictionary:
	return GameStorageUtils.load_json_dict(ITEM_PROFILE_DIR, item_name)

func _base64_to_image(base64_string: String) -> Image:
	return GameImageUtils.base64_to_image(base64_string)

func _display_base64_image(base64_string: String, site_name: String = ""):
	GameImageRuntimeUtils.display_base64_image(self, base64_string, site_name)

func _base64_to_texture(base64_string: String) -> Texture2D:
	return GameImageUtils.base64_to_texture(base64_string)

func _request_json(url: String, body_json: String) -> Dictionary:
	return await GameHttpUtils.request_json(self, url, body_json)

func _generate_item_profile(item_name: String) -> Dictionary:
	return await GameItemProfileUtils.generate_item_profile(self, item_name)

func _generate_item_texture(image_prompt: String) -> Texture2D:
	return await GameItemProfileUtils.generate_item_texture(self, image_prompt)

func _generate_validation_dialogue(scene_context: String, fallback: String) -> String:
	return await GameItemProfileUtils.generate_validation_dialogue(self, scene_context, fallback)

func _request_item_use_ai_feedback(scene_context: String, fallback: String) -> void:
	await GameEntityRuntimeUtils.request_item_use_ai_feedback(self, scene_context, fallback)

func _build_ultra_fast_item_prompt(base_prompt: String) -> String:
	return GameItemProfileUtils.build_ultra_fast_item_prompt(base_prompt)

func _sanitize_item_profile(item_name: String, raw_profile: Dictionary) -> Dictionary:
	return GameItemProfileUtils.sanitize_item_profile(item_name, raw_profile)

func _ensure_item_profile_record_before_trade(item_name: String) -> void:
	await GameItemProfileUtils.ensure_item_profile_record_before_trade(self, item_name)

func _build_explore_system_prompt() -> String:
	return GameVisualUtils.build_explore_system_prompt(role_prompt, world_seed_input, background)

func ensure_item_profile_async(item_name: String) -> void:
	await GameItemProfileUtils.ensure_item_profile_async(self, item_name)

func update_item_trade_price(item_name: String, per_unit_price: int) -> void:
	GameInteractionRuntimeUtils.update_item_trade_price(self, item_name, per_unit_price)

func _on_send_button_pressed():
	await GameInteractionRuntimeUtils.on_send_button_pressed(self)

func _normalize_single_line_input(raw_text: String) -> String:
	return GameTextUtils.normalize_single_line_input(raw_text)

func _build_shared_interaction_context(interaction_text: String, focus_npc_name: String = "", focus_npc_desc: String = "") -> String:
	return GameInteractionRuntimeUtils.build_shared_interaction_context(self, interaction_text, focus_npc_name, focus_npc_desc)

func _build_continue_action_text() -> String:
	return GameInteractionRuntimeUtils.build_continue_action_text()

func _build_continue_dialogue_text() -> String:
	return GameInteractionRuntimeUtils.build_continue_dialogue_text()

func _trigger_continue_flow() -> void:
	await GameInteractionRuntimeUtils.trigger_continue_flow(self)

func _submit_action_input(raw_input: String, bypass_lock_check: bool = false) -> void:
	await GameInteractionRuntimeUtils.submit_action_input(self, raw_input, bypass_lock_check)

func _on_dialogue_button_pressed():
	await GameInteractionRuntimeUtils.on_dialogue_button_pressed(self)

func _submit_dialogue_input(raw_input: String, allow_continue_text: bool = false) -> void:
	await GameInteractionRuntimeUtils.submit_dialogue_input(self, raw_input, allow_continue_text)

func _on_continue_button_pressed() -> void:
	await GameInteractionRuntimeUtils.on_continue_button_pressed(self)

func _on_npc_icon_gui_input(event: InputEvent) -> void:
	GameInteractionRuntimeUtils.on_npc_icon_gui_input(self, event)

func _show_current_npc_profile() -> void:
	GameInteractionRuntimeUtils.show_current_npc_profile(self)

func _request_leave_chat_confirm() -> void:
	GameInteractionRuntimeUtils.request_leave_chat_confirm(self)

func request_site_switch(site_name: String) -> void:
	await GameInteractionRuntimeUtils.request_site_switch(self, site_name)

func _start_chat_with_existing_npc(npc_name: String) -> void:
	await GameInteractionRuntimeUtils.start_chat_with_existing_npc(self, npc_name)

func request_npc_switch(npc_name: String) -> void:
	await GameInteractionRuntimeUtils.request_npc_switch(self, npc_name)

func _request_npc_leave_confirm(npc_name: String) -> void:
	GameInteractionRuntimeUtils.request_npc_leave_confirm(self, npc_name)

func _has_active_event_panel() -> bool:
	return GameInteractionRuntimeUtils.has_active_event_panel(self)

func refresh_interaction_locks() -> void:
	GameInteractionRuntimeUtils.refresh_interaction_locks(self)

func _set_event_flow_lock(v: bool) -> void:
	GameInteractionRuntimeUtils.set_event_flow_lock(self, v)

func _focus_active_input() -> void:
	GameInteractionRuntimeUtils.focus_active_input(self)

func _recover_focus_after_submit(target_focus: String) -> void:
	await GameInteractionRuntimeUtils.recover_focus_after_submit(self, target_focus)
		

func _apply_interaction_locks() -> void:
	GameInteractionRuntimeUtils.apply_interaction_locks(self)

func _set_site_loading_lock(v: bool) -> void:
	GameInteractionRuntimeUtils.set_site_loading_lock(self, v)

func set_ai_busy(v: bool) -> void:
	GameInteractionRuntimeUtils.set_ai_busy(self, v)

func _sanitize_response_text(raw_text: String) -> String:
	return GameInteractionRuntimeUtils.sanitize_response_text(raw_text)

func changeTextTo(nodeToChange: Control, text: String, speed = 30, max_tween_duration: float = 1.6):
	await GameInteractionRuntimeUtils.changeTextTo(self, nodeToChange, text, speed, max_tween_duration)

func clear_children(node: Node):
	GameInteractionRuntimeUtils.clear_children(self, node)

func addLog(logText: String, instant: bool = false):
	GameInteractionRuntimeUtils.addLog(self, logText, instant)

func _is_important_log(log_text: String) -> bool:
	return GameEventUtils.is_important_log(log_text)

func _extract_npc_mentions(text: String) -> Array:
	return GameMemoryUtils.extract_npc_mentions(npcs, text)

func _remember_important_event(raw_text: String, site_name: String = "", focus_npc: String = "") -> void:
	var site = str(site_name).strip_edges()
	if site == "":
		site = currentSiteName
	var plain = GameMemoryUtils.refine_important_event_text(str(raw_text).strip_edges())
	if plain == "":
		return
	var sig = _extract_interaction_signals(plain)
	if !_should_store_npc_personal_event(plain, sig):
		return
	if plain.length() < 70:
		GameMemoryUtils.remember_important_event(important_event_memories, npcs, plain, site, focus_npc)
		return
	_enqueue_important_event_refine({"raw_text": plain, "site": site, "focus_npc": str(focus_npc).strip_edges()})

func _enqueue_important_event_refine(job: Dictionary) -> void:
	if job.is_empty():
		return
	if pending_event_refine_queue.size() > 60:
		pending_event_refine_queue.pop_front()
	pending_event_refine_queue.append(job)
	if !event_refine_inflight:
		call_deferred("_drain_event_refine_queue")

func _build_event_refine_prompt(raw_event_text: String) -> Array:
	var user_text = "请将下面事件精练为1句话，保留关键人物、地点、结果，不要虚构，不要套话，不超过60字：\n" + raw_event_text.left(360)
	return [
		{"role": "system", "content": "你是事件记录助手。只输出精练后的事件一句话，不要解释。"},
		{"role": "user", "content": user_text}
	]

func _drain_event_refine_queue() -> void:
	if event_refine_inflight:
		return
	event_refine_inflight = true
	while !pending_event_refine_queue.is_empty():
		var job = pending_event_refine_queue.pop_front()
		if !(job is Dictionary):
			continue
		var raw_text = str(job.get("raw_text", "")).strip_edges()
		if raw_text == "":
			continue
		var site = str(job.get("site", currentSiteName)).strip_edges()
		if site == "":
			site = currentSiteName
		var focus = str(job.get("focus_npc", "")).strip_edges()
		var cache_key = raw_text.left(180)
		var final_text = str(event_refine_cache.get(cache_key, "")).strip_edges()
		if final_text == "":
			last_event_refine_response = ""
			await ask_ai(_build_event_refine_prompt(raw_text), aiMode.refine_event)
			var ai_text = GameMemoryUtils.refine_important_event_text(last_event_refine_response)
			if ai_text != "":
				final_text = ai_text
				event_refine_cache[cache_key] = final_text
		if final_text == "":
			final_text = raw_text
		GameMemoryUtils.remember_important_event(important_event_memories, npcs, final_text, site, focus)
	event_refine_inflight = false

func _ensure_npc_event_bucket(npc_name: String) -> void:
	GameMemoryUtils.ensure_npc_event_bucket(npcs, npc_name)

func _build_npc_perspective_event_text(event_text: String, npc_name: String, focus_npc: String) -> String:
	return GameEventUtils.build_npc_perspective_event_text(process_string(event_text), npc_name, focus_npc)

func _should_store_npc_personal_event(plain_text: String, sig: Dictionary) -> bool:
	return GameEventUtils.should_store_npc_personal_event(plain_text, sig)

func _extract_npc_result_outcome_flags(plain_text: String, sig: Dictionary) -> Dictionary:
	return GameEventUtils.extract_npc_result_outcome_flags(plain_text, sig)

func _build_npc_personal_event_summary(plain_text: String, npc_name: String, focus_npc: String, sig: Dictionary) -> String:
	return GameEventUtils.build_npc_personal_event_summary(plain_text, npc_name, focus_npc, sig)


func _append_event_to_npc_memory(npc_name: String, record: Dictionary, focus_npc: String) -> void:
	GameMemoryUtils.append_event_to_npc_memory(npcs, npc_name, record, focus_npc)

func _get_recent_npc_personal_events(npc_name: String, limit_count: int = 3) -> Array:
	return GameMemoryUtils.get_recent_npc_personal_events(npcs, npc_name, limit_count)

func _score_event_relevance(mem: Dictionary, site_name: String, npc_name: String, intent_hint: Dictionary = {}) -> int:
	return GameEventUtils.score_event_relevance(mem, site_name, npc_name, intent_hint)

func _get_recent_related_event_memories(site_name: String, npc_name: String = "", limit_count: int = 4, intent_hint: Dictionary = {}) -> Array:
	return GameMemoryUtils.get_recent_related_event_memories(important_event_memories, site_name, npc_name, limit_count, intent_hint)

func get_relevant_event_memory_for_npc(npc_name: String, _npc_desc: String = "") -> String:
	var personal_rows = _get_recent_npc_personal_events(npc_name, 4)
	var rows = _get_recent_related_event_memories(currentSiteName, npc_name, 2)
	var memory_text = GameMemoryUtils.build_relevant_event_memory_text(personal_rows, rows)
	if memory_text == "":
		return ""
	if !personal_rows.is_empty():
		return _clip_prompt_text(memory_text, 320)
	return _clip_prompt_text(memory_text, 260)

func _build_identity_attitude_guidance(focus_npc_name: String = "", focus_npc_desc: String = "") -> String:
	return GameActionUtils.build_identity_attitude_guidance(playerName, world_seed_input, reputation, focus_npc_name, focus_npc_desc)

func get_identity_attitude_guidance_for_npc(npc_name: String, npc_desc: String = "") -> String:
	return _build_identity_attitude_guidance(npc_name, npc_desc)

func _build_related_event_memory_for_action(action_text: String, focus_npc_name: String = "") -> String:
	var hint = _extract_interaction_signals(action_text)
	var focus_npc = GameMemoryUtils.resolve_focus_npc_for_action(action_text, focus_npc_name, npcs)
	if focus_npc != "":
		var personal_rows = _get_recent_npc_personal_events(focus_npc, 4)
		var personal_text = GameMemoryUtils.build_relevant_event_memory_text(personal_rows, [])
		if personal_text != "":
			return _clip_prompt_text(personal_text, 320)
	var rows = _get_recent_related_event_memories(currentSiteName, focus_npc, 2, hint)
	var related_text = GameMemoryUtils.build_relevant_event_memory_text([], rows)
	if related_text == "":
		return ""
	return _clip_prompt_text(related_text, 260)

func _build_inventory_snapshot(max_items: int = 6) -> String:
	var parts: Array = []
	for child in %itemContainer.get_children():
		if child is item:
			parts.append(str(child.item_name) + "x" + str(child.item_num))
			if parts.size() >= max_items:
				break
	if parts.is_empty():
		return "空"
	return "，".join(parts)

func _on_force_release_button_pressed() -> void:
	GameInteractionRuntimeUtils.on_force_release_button_pressed(self)

func _on_save_button_pressed() -> void:
	GameInteractionRuntimeUtils.on_save_button_pressed(self)

func _on_load_button_pressed() -> void:
	GameInteractionRuntimeUtils.on_load_button_pressed(self)

func _clear_active_text_tweens(force_complete_visible: bool = true) -> void:
	GameInteractionRuntimeUtils.clear_active_text_tweens(self, force_complete_visible)

func _force_release_runtime(show_notice: bool = true, compact_context: bool = false) -> void:
	GameInteractionRuntimeUtils.force_release_runtime(self, show_notice, compact_context)

func _recover_from_ai_stall(reason: String) -> void:
	GameInteractionRuntimeUtils.recover_from_ai_stall(self, reason)

func _on_request_completed(result, response_code, _header, body):
	await GameInteractionRuntimeUtils.on_request_completed(self, result, response_code, _header, body)

func apply_passive_recovery(minutes: float) -> Dictionary:
	return GameInteractionRuntimeUtils.apply_passive_recovery(self, minutes)

func advance_time_minutes(minutes: float, with_log: bool = false) -> Dictionary:
	return GameInteractionRuntimeUtils.advance_time_minutes(self, minutes, with_log)

func on_event_decision(event_kind: String, accepted: bool, item_name: String, quantity: int, total_price: int = 0) -> void:
	await GameInteractionRuntimeUtils.on_event_decision(self, event_kind, accepted, item_name, quantity, total_price)

var weather:String = ""

func _drain_pending_img() -> void:
	if inflight_img_site != "":
		return
	if pending_img_queue.is_empty():
		return
	var req: Dictionary = pending_img_queue.pop_front()
	var error_image = _dispatch_image_request(req)
	if error_image == OK:
		return
	if error_image == ERR_BUSY:
		pending_img_queue.push_front(req)
		call_deferred("_drain_pending_img")
		return
	_bg_debug("gen_img request create failed, err=" + str(error_image))
	if !_queue_image_retry(req, "request_error:" + str(error_image)):
		if pending_site_update:
			pending_site_update = false
			site_update()
		if site_loading_lock:
			_set_site_loading_lock(false)
	call_deferred("_drain_pending_img")

func _on_img_http_request_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	GameImageRuntimeUtils.on_img_http_request_request_completed(self, result, response_code, _headers, body)

func _extract_first_number(text: String) -> int:
	return GameNpcInferUtils.extract_first_number(text)

func _extract_duration_hours(text: String) -> float:
	return GameParseUtils.extract_duration_hours(text)

func _extract_target_time(text: String) -> Dictionary:
	return GameParseUtils.extract_target_time(text)

func _auto_initiate_npc_chat(npc_name: String, npc_describe: String) -> void:
	await GameProactiveNpcUtils.auto_initiate_npc_chat(self, npc_name, npc_describe)

func _pick_crime_npc_from_action(action_input: String) -> Dictionary:
	var cleaned = action_input.strip_edges()
	if cleaned != "":
		for npc_name in npcs.keys():
			var n = str(npc_name)
			if cleaned.find(n) != -1:
				var data = npcs[n]
				if data is Dictionary:
					return {"name": n, "describe": str(data.get("npc_describe", "神情紧张地盯着你"))}
	return GameNpcPoolUtils.pick_crime_npc_fallback(currentSiteName, _detect_setting_style_signals())

func _build_proactive_npc_pool(reason: String) -> Array:
	return GameNpcPoolUtils.build_proactive_npc_pool(reason, _detect_setting_style_signals())

func _spawn_context_npc(reason: String, forced_npc: Dictionary = {}, context_text: String = "") -> void:
	await GameProactiveNpcUtils.spawn_context_npc(self, reason, forced_npc, context_text)

func _trigger_time_pass_npc_event(hours: float, action_context: String = "") -> bool:
	if hours < 0.5:
		return false
	if randf() < ACTION_PROACTIVE_NPC_RATE:
		await _spawn_context_npc("time_pass", {}, action_context)
		return true
	return false

func _build_action_context_text(action_input: String, action_reply: String) -> String:
	return GameActionUtils.build_action_context_text(action_input, process_string(action_reply))

func _extract_signed_number(text: String) -> int:
	return GameParseUtils.extract_signed_number(text)

func _extract_money_delta_from_text(text: String) -> int:
	return GameParseUtils.extract_money_delta_from_text(process_string(text))

func _build_crime_context(action_input: String, action_reply: String, tool_tags: String) -> String:
	return GameActionUtils.build_crime_context(action_input, process_string(action_reply), _extract_angle_tags(tool_tags + action_reply))

func _apply_direct_action_tool_tags(action_reply: String) -> Dictionary:
	var tags = _extract_angle_tags(action_reply)
	if tags.is_empty():
		return {"handled_any": false, "unresolved_tags": "", "nav_target": "", "handled_tags": []}
	var parsed = GameActionTagUtils.parse_direct_action_tags(tags)
	var unresolved = str(parsed.get("unresolved_tags", ""))
	var handled_any = bool(parsed.get("handled_any", false))
	var handled_tags: Array = parsed.get("handled_tags", [])
	var nav_target = ""
	var state_changed = false
	for op in parsed.get("operations", []):
		if !(op is Dictionary):
			continue
		var op_type = str(op.get("type", "")).strip_edges()
		if op_type == "reputation_delta":
			update_reputation(int(op.get("delta", 0)))
			state_changed = true
		elif op_type == "set_time":
			set_time(int(op.get("hour", 0)), int(op.get("minute", 0)))
			state_changed = true
		elif op_type == "nav_target":
			nav_target = str(op.get("target", "")).strip_edges()
	if state_changed:
		player_update()
	return {"handled_any": handled_any, "unresolved_tags": unresolved, "nav_target": nav_target, "handled_tags": handled_tags}

func _extract_nav_target_from_text(text: String) -> String:
	return GameActionUtils.extract_nav_target_from_text(text, currentSiteName, sites.keys())

func _auto_apply_action_effects(action_input: String, action_reply: String, tool_tags: String) -> void:
	await GameAutoEffectUtils.auto_apply_action_effects(self, action_input, action_reply, tool_tags)

func extract_json_from_text(input_string: String) -> Dictionary:
	return GameAiUtils.extract_json_from_text(input_string)
func initiate_transaction(item_name: String, quantity: int, price: int, is_total: bool = false) -> void:
	await GameEntityRuntimeUtils.initiate_transaction(self, item_name, quantity, price, is_total)

func got_items(item_name: String, quantity: int) -> void:
	await GameEntityRuntimeUtils.got_items(self, item_name, quantity)

func consume_items(item_name: String, quantity: int) -> void:
	await GameEntityRuntimeUtils.consume_items(self, item_name, quantity)

func create_location(path: String) -> void:
	GameEntityRuntimeUtils.create_location(self, path)

func create_NPC(npc_name: String, location: String, npc_describe: String) -> void:
	GameEntityRuntimeUtils.create_NPC(self, npc_name, location, npc_describe)

func prepare_npc_memory_for_chat(npc_name: String) -> void:
	_append_event_memories_to_npc_log(npc_name)

func _has_trade_keywords(text: String) -> bool:
	return GameNpcInferUtils.has_trade_keywords(text)

func _queue_action_confirm(action_data: Dictionary) -> void:
	GameEntityRuntimeUtils.queue_action_confirm(self, action_data)

func _npc_refused_request(reply_text: String) -> bool:
	return GameNpcInferUtils.npc_refused_request(process_string(reply_text))

func _extract_player_directed_request(user_text: String) -> String:
	return GameNpcInferUtils.extract_player_directed_request(GameTextUtils.normalize_single_line_input(user_text))

func _can_force_request_on_npc(npc_name: String, npc_describe: String, request_text: String) -> bool:
	return GameNpcInferUtils.can_force_request_on_npc(world_seed_input + " " + playerName, npc_name, npc_describe, request_text)

func _append_event_memories_to_npc_log(npc_name: String) -> void:
	GameEntityRuntimeUtils.append_event_memories_to_npc_log(self, npc_name)

func _contains_any_keyword(text: String, words: Array) -> bool:
	return GameEntityUtils.contains_keyword(text, words)

func _extract_interaction_signals(text: String) -> Dictionary:
	return GameNpcInferUtils.extract_interaction_signals(text)

func _needs_tool_inference_from_context(player_text: String, npc_text: String) -> bool:
	return GameNpcInferUtils.needs_tool_inference_from_context(player_text, process_string(npc_text))

func _npc_reply_accepts_request(reply_text: String) -> bool:
	return GameNpcInferUtils.npc_reply_accepts_request(process_string(reply_text))

func _maybe_offer_intent_confirm_from_dialogue(reply_text: String) -> void:
	GameEntityRuntimeUtils.maybe_offer_intent_confirm_from_dialogue(self, reply_text)

func _extract_npc_action_request(reply_text: String) -> Dictionary:
	var actor_name = ""
	if currentNpc != null:
		actor_name = str(currentNpc.npcName)
	return GameNpcInferUtils.extract_npc_action_request(process_string(reply_text), _extract_angle_tags(reply_text), actor_name)

func _auto_handle_action_search(action_input: String, action_reply: String) -> void:
	GameEntityRuntimeUtils.auto_handle_action_search(self, action_input, action_reply)

func create_rumors(rumor_name: String, content: String) -> void:
	GameEntityRuntimeUtils.create_rumors(self, rumor_name, content)

func update_reputation(quantity:int)->void:
	GameEntityRuntimeUtils.update_reputation(self, quantity)

func set_time(hour: int, minute: int) -> float:
	return GameEntityRuntimeUtils.set_time(self, hour, minute)

func destroy_yourself(npc_name_hint: String = "") -> void:
	await GameEntityRuntimeUtils.destroy_yourself(self, npc_name_hint)

func _safe_tool_param_string(parameters: Dictionary, key: String, fallback: String = "") -> String:
	if !parameters.has(key):
		return fallback
	var value = parameters.get(key, fallback)
	if value == null:
		return fallback
	return str(value)

func handle_npc_instruction(tool_calls: Array) -> void:
	await GameFlowRuntimeUtils.handle_npc_instruction(self, tool_calls)

func add_item(itemToAdd, itemNum):
	GameEntityRuntimeUtils.add_item(self, itemToAdd, itemNum)

func use_item(item_name: String) -> Dictionary:
	return GameEntityRuntimeUtils.use_item(self, item_name)

func gift_item(item_name: String) -> Dictionary:
	return GameEntityRuntimeUtils.gift_item(self, item_name)

func save_game() -> void:
	if _is_runtime_transition_locked():
		return
	_set_runtime_operation_lock(true, "save_game")
	GameSaveLoadUtils.save_game(self)
	_set_runtime_operation_lock(false, "save_game_done")

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_FILE)

func load_game() -> bool:
	if _is_runtime_transition_locked():
		return false
	_set_runtime_operation_lock(true, "load_game")
	var ok = GameSaveLoadUtils.load_game(self)
	_set_runtime_operation_lock(false, "load_game_done")
	return ok
