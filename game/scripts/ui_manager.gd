extends Node

# UI管理
@onready var input_text_edit = %InputTextEdit
@onready var send_button = %SendButton
@onready var response_label = %ResponseLabel
@onready var dialogue_container = %DialogueContainer
@onready var dialogue_input = %DialogueTextEdit
@onready var dialogue_button = %DialogueButton
@onready var save_button = %SaveButton
@onready var load_button = %LoadButton
var output_length_button: Button

func init_ui():
    send_button.connect("pressed", _on_send_button_pressed)
    dialogue_button.connect("pressed", _on_dialogue_button_pressed)
    save_button.connect("pressed", save_game)
    load_button.connect("pressed", load_game)
    if input_text_edit != null:
        input_text_edit.placeholder_text = "输入行动，留空则继续"
    dialogue_container.visible = false
    _setup_output_mode_controls()

func _on_send_button_pressed():
    # Placeholder for button pressed logic
    pass

func _on_dialogue_button_pressed():
    # Placeholder for button pressed logic
    pass

func save_game():
    # Placeholder for save game logic
    pass

func load_game():
    # Placeholder for load game logic
    pass

func _setup_output_mode_controls() -> void:
    if response_label == null:
        return
    if output_length_button != null and is_instance_valid(output_length_button):
        return
    output_length_button = Button.new()
    output_length_button.name = "OutputLengthButton"
    output_length_button.text = "设置"
    output_length_button.custom_minimum_size = Vector2(52, 26)
    output_length_button.anchors_preset = 1
    output_length_button.anchor_left = 1.0
    output_length_button.anchor_right = 1.0
    output_length_button.offset_left = -60.0
    output_length_button.offset_top = 4.0
    output_length_button.offset_right = -4.0
    output_length_button.offset_bottom = 30.0
    output_length_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    output_length_button.pressed.connect(_on_output_length_button_pressed)
    response_label.add_child(output_length_button)

func _on_output_length_button_pressed():
    # Placeholder for button pressed logic
    pass

func update_ui():
    # 更新UI状态
    pass
