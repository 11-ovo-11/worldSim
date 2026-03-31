extends VBoxContainer
class_name item

const DEFAULT_ITEM_TEXTURE := preload("res://icon.svg")

var item_name: String = ""
var item_num: int = 0
var item_description: String = "正在生成物品介绍..."
var item_texture: Texture2D
var effect_type: String = "none"
var effect_value: int = 0

@onready var image_button: TextureButton = %ItemImageButton
@onready var quantity_label: Label = %QuantityLabel

func _ready() -> void:
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
		_:
			return "使用效果：无"

func _refresh_view() -> void:
	if quantity_label == null or image_button == null:
		return
	quantity_label.text = "x" + str(item_num)
	var display_texture: Texture2D = item_texture
	if display_texture == null:
		display_texture = DEFAULT_ITEM_TEXTURE
	image_button.texture_normal = display_texture
	image_button.texture_pressed = display_texture
	image_button.texture_hover = display_texture

func _on_item_image_button_pressed() -> void:
	var popup := AcceptDialog.new()
	popup.title = item_name
	popup.dialog_autowrap = true
	popup.size = Vector2i(520, 620)
	popup.ok_button_text = "关闭"

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(480, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)

	if item_texture != null:
		var img := TextureRect.new()
		img.texture = item_texture
		img.custom_minimum_size = Vector2(240, 240)
		img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		img.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(img)

	var desc := RichTextLabel.new()
	desc.fit_content = true
	desc.scroll_active = true
	desc.custom_minimum_size = Vector2(0, 240)
	desc.bbcode_enabled = true
	desc.text = item_description + "\n\n" + _effect_display_text()
	content.add_child(desc)

	var use_button := Button.new()
	use_button.text = "使用"
	use_button.disabled = item_num <= 0
	use_button.pressed.connect(func():
		var scene = get_tree().current_scene
		if scene != null and scene.has_method("use_item"):
			scene.use_item(item_name)
		popup.hide()
		popup.queue_free()
	)
	content.add_child(use_button)

	popup.add_child(content)
	get_tree().current_scene.add_child(popup)
	popup.popup_centered()
