class_name LoadingScreen
extends CanvasLayer

var _root: Control
var _label: Label
var _progress: ProgressBar


func setup() -> void:
	layer = 10
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.size = get_viewport().get_visible_rect().size
	add_child(_root)
	get_viewport().size_changed.connect(_resize)
	var background := ColorRect.new()
	background.color = Color(0.008, 0.012, 0.035)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(440.0, 0.0)
	content.add_theme_constant_override("separation", 18)
	center.add_child(content)
	var title := Label.new()
	title.text = "OUTER GODOT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	content.add_child(title)
	_label = Label.new()
	_label.text = "Initializing…"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(0.65, 0.75, 1.0))
	content.add_child(_label)
	_progress = ProgressBar.new()
	_progress.show_percentage = true
	_progress.value = 0.0
	content.add_child(_progress)


func set_status(value: String) -> void:
	if _label != null:
		_label.text = value


func set_progress(value: float) -> void:
	if _progress != null:
		_progress.value = value


func finish() -> void:
	queue_free()


func _resize() -> void:
	if _root != null:
		_root.size = get_viewport().get_visible_rect().size
