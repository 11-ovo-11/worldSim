extends VBoxContainer
class_name item

const DEFAULT_ITEM_TEXTURE := preload("res://icon.svg")

var item_name: String = ""
var item_num: int = 0
var item_description: String = "正在生成物品介绍..."
var item_texture: Texture2D

@onready var image_button: TextureButton = %ItemImageButton
@onready var quantity_label: Label = %QuantityLabel

func _ready() -> void:
	_refresh_view()

func setup(item_name_value: String, quantity: int, texture: Texture2D, description: String) -> void:
	item_name = item_name_value
	item_num = quantity
	if texture != null:
		item_texture = texture
	if description != "":
		item_description = description
	visible = (item_texture != null)
	_refresh_view()

func add_quantity(quantity: int) -> void:
	item_num += quantity
	_refresh_view()

func consume_quantity(quantity: int) -> void:
	item_num -= quantity
	_refresh_view()

func set_item_visual(texture: Texture2D, description: String) -> void:
	if texture != null:
		item_texture = texture
		visible = true
	if description != "":
		item_description = description
	_refresh_view()

func _refresh_view() -> void:
	if quantity_label == null or image_button == null:
		return
	quantity_label.text = "x" + str(item_num)
	if item_texture != null:
		image_button.texture_normal = item_texture
		image_button.texture_pressed = item_texture
		image_button.texture_hover = item_texture

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
	desc.text = item_description
	content.add_child(desc)

	popup.add_child(content)
	get_tree().current_scene.add_child(popup)
	popup.popup_centered()
