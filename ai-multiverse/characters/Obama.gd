extends "res://characters/random_walker.gd"

func _ready():
	super()
	move_speed = 50.0             # moves calmly
	idle_chance = 0.4             # pauses more often
	min_decide_time = 0.8
	max_decide_time = 2.5
