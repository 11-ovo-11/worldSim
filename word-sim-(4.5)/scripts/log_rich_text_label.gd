extends RichTextLabel

var expanded: bool = false
var can_expand: bool = false
var speed = 30.0
func _ready() -> void:
	visible_ratio = 0
	# 检查是否是第一个节点
	var my_index = get_index()
	if my_index == 0:
		# 第一个节点可以直接开始展开
		can_expand = true
	else:
		# 其他节点需要等待上一个节点完成
		can_expand = false

func _process(_delta: float) -> void:
	if expanded:
		return

	if can_expand:
		expand()
		expanded = true
	else:
		# 检查上一个节点是否完全展开
		var prev_node = get_previous_node()
		if prev_node and prev_node.visible_ratio == 1:
			can_expand = true

# 获取上一个节点（兄弟节点中的前一个）
func get_previous_node() -> Node:
	var parent = get_parent()
	var my_index = get_index()

	if my_index > 0:
		return parent.get_child(my_index - 1)
	return null

func expand() -> void:
	var tween = create_tween()
	tween.tween_property(self, "visible_ratio", 1.0, float(text.length()) / speed)

# 可选：提供一个外部调用的方法来手动触发展开
func start_expand() -> void:
	can_expand = true
