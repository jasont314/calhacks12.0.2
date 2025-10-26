extends Node2D

@onready var trump = preload("res://characters/Trump.tscn").instantiate()
@onready var obama = preload("res://characters/Obama.tscn").instantiate()

func _ready():
	add_child(trump)
	add_child(obama)
	trump.global_position = Vector2(200, 300)
	obama.global_position = Vector2(400, 350)
