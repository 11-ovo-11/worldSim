extends VBoxContainer
class_name item

const DEFAULT_ITEM_TEXTURE := preload("res://icon.svg")
const ITEM_DETAIL_POPUP_SCENE := preload("res://fabs/item_detail_popup.tscn")

var item_name: String = ""
var item_num: int = 0
var item_description: String = "正在生成物品介绍..."
var item_texture: Texture2D
var effect_type: String = "none"
var effect_value: int = 0

@onready var image_button: TextureButton = %ItemImageButton
@onready var quantity_label: Label = %QuantityLabel

const ITEM_ICON_SIZE_NORMAL := 100.0
const ITEM_ICON_SIZE_COMPACT := 84.0
const ITEM_ICON_SIZE_MIN := 40.0
const ITEM_LABEL_EXTRA_HEIGHT := 20.0

func _resolve_icon_size(preferred: float) -> float:
	var icon_size = preferred
	var parent_node = get_parent()
	if parent_node is Control:
		var parent_width = float((parent_node as Control).size.x)
		if parent_width > 1.0:
			icon_size = min(icon_size, parent_width - 8.0)
	return clamp(icon_size, ITEM_ICON_SIZE_MIN, ITEM_ICON_SIZE_NORMAL)

func _apply_compact_visual(is_compact: bool) -> void:
	if image_button == null or quantity_label == null:
		return
	var preferred = ITEM_ICON_SIZE_COMPACT if is_compact else ITEM_ICON_SIZE_NORMAL
	var icon_size = _resolve_icon_size(preferred)
	image_button.ignore_texture_size = true
	image_button.custom_minimum_size = Vector2(icon_size, icon_size)
	custom_minimum_size = Vector2(icon_size, icon_size + ITEM_LABEL_EXTRA_HEIGHT)
	if is_compact:
		quantity_label.add_theme_font_size_override("font_size", 10)
	else:
		quantity_label.add_theme_font_size_override("font_size", 12)

func _ready() -> void:
	if !resized.is_connected(_refresh_view):
		resized.connect(_refresh_view)
	var parent_node = get_parent()
	if parent_node is Control and !(parent_node as Control).resized.is_connected(_refresh_view):
		(parent_node as Control).resized.connect(_refresh_view)
	_refresh_view()

func setup(item_name_value: String, quantity: int, texture: Texture2D, description: String, effect_type_value: String = "none", effect_value_num: int = 0) -> void:
	item_name = item_name_value
	item_num = quantity
	if texture != null:
		item_texture = texture
	if description != "":
		item_description = description
	effect_type = effect_type_value
	effect_value = effect_value_num
	visible = true
	_refresh_view()

func add_quantity(quantity: int) -> void:
	item_num += quantity
	_refresh_view()

func consume_quantity(quantity: int) -> void:
	item_num -= quantity
	_refresh_view()

func set_item_visual(texture: Texture2D, description: String, effect_type_value: String = "none", effect_value_num: int = 0) -> void:
	if texture != null:
		item_texture = texture
		visible = true
	if description != "":
		item_description = description
	effect_type = effect_type_value
	effect_value = effect_value_num
	_refresh_view()

func _effect_display_text() -> String:
	match effect_type:
		"energy_restore":
			return "使用效果：体力+" + str(effect_value)
		"hp_restore":
			return "使用效果：健康+" + str(effect_value)
		"both_restore":
			return "使用效果：体力与健康恢复"
		"money_gain":
			return "使用效果：资产+" + str(effect_value)
		"money_loss":
			return "使用效果：资产-" + str(effect_value)
		"reputation_gain":
			return "使用效果：声望+" + str(effect_value)
		"reputation_loss":
			return "使用效果：声望-" + str(effect_value)
		"time_advance":
			return "使用效果：时间推进" + str(effect_value) + "分钟"
		"npc_affinity":
			return "使用效果：对话对象关系提升"
		"rumor_trigger":
			return "使用效果：触发新线索"
		_:
			return "使用效果：状态恢复"

func _refresh_view() -> void:
	if quantity_label == null or image_button == null:
		return
	var sibling_count = 0
	var parent_node = get_parent()
	if parent_node != null:
		sibling_count = parent_node.get_child_count()
	_apply_compact_visual(sibling_count >= 10)
	quantity_label.text = "x" + str(item_num)
	var display_texture: Texture2D = item_texture
	if display_texture == null:
		display_texture = DEFAULT_ITEM_TEXTURE
	image_button.texture_normal = display_texture
	image_button.texture_pressed = display_texture
	image_button.texture_hover = display_texture

func _on_item_image_button_pressed() -> void:
	var popup = ITEM_DETAIL_POPUP_SCENE.instantiate() as AcceptDialog
	if popup == null:
		return
	popup.title = item_name
	var preview = popup.get_node_or_null("%ItemPreview") as TextureRect
	if preview != null:
		preview.texture = item_texture if item_texture != null else DEFAULT_ITEM_TEXTURE
	var desc = popup.get_node_or_null("%ItemDesc") as RichTextLabel
	if desc != null:
		desc.text = item_description + "\n\n" + _effect_display_text()
	var use_button = popup.get_node_or_null("%UseButton") as Button
	if use_button != null:
		use_button.disabled = item_num <= 0
		use_button.pressed.connect(func():
			var scene = get_tree().current_scene
			if scene != null and scene.has_method("use_item"):
				scene.use_item(item_name)
			popup.hide()
			popup.queue_free()
		)
	var gift_button = popup.get_node_or_null("%GiftButton") as Button
	if gift_button != null:
		gift_button.disabled = item_num <= 0
		var scene_now = get_tree().current_scene
		if scene_now != null and scene_now.has_method("gift_item"):
			var in_chat = scene_now.currentState == scene_now.worldState.chat and scene_now.currentNpc != null
			gift_button.text = "赠送给当前对话对象" if in_chat else "赠送给路人"
		gift_button.pressed.connect(func():
			var scene = get_tree().current_scene
			if scene != null and scene.has_method("gift_item"):
				scene.gift_item(item_name)
			popup.hide()
			popup.queue_free()
		)
	get_tree().current_scene.add_child(popup)
	popup.popup_centered()
