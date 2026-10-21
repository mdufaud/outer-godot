class_name Seat
extends Area3D

var ship: Ship
var prompt_text := "Board pilot seat"


func interact(player: Player) -> void:
	ship.enter_pilot(player)
