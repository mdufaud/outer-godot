extends CanvasLayer

var ship: RigidBody3D = null
var prompt_label: Label
var info_label: Label
var hint_label: Label

const HINT_FOOT := "ZQSD marcher · Espace saut/jetpack · Maj courir · E interagir · R respawn"
const HINT_SHIP := "ZQSD pousser · Espace/Maj haut/bas · souris orienter · W/C roulis · X frein · E sortir"


func _ready() -> void:
	add_to_group("hud")

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 22)
	add_child(crosshair)

	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position.y -= 120
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(prompt_label)

	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_label.position = Vector2(16, 16)
	info_label.add_theme_font_size_override("font_size", 18)
	add_child(info_label)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position.y -= 40
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.modulate = Color(1, 1, 1, 0.5)
	hint_label.text = HINT_FOOT
	add_child(hint_label)


func _process(_delta: float) -> void:
	if ship == null:
		info_label.text = ""
		return
	var speed := ship.linear_velocity.length()
	var altitude: float = Gravity.get_altitude(ship.global_position)
	var text := "Vitesse : %.1f m/s" % speed
	if altitude >= 0.0:
		text += "\nAltitude : %.0f m" % altitude
	info_label.text = text


func set_prompt(text: String) -> void:
	prompt_label.text = text


func set_ship(value: RigidBody3D) -> void:
	ship = value
	hint_label.text = HINT_SHIP if ship else HINT_FOOT
	if ship:
		prompt_label.text = ""
