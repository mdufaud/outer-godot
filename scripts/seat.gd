extends Area3D

var ship: RigidBody3D
var prompt_text := "E : s'asseoir au poste de pilotage"


func interact(player: Node3D) -> void:
	ship.enter_pilot(player)
