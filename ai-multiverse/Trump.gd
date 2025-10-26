# Character.gd
extends CharacterBody2D

#
# === TUNABLE PARAMETERS ===
#

@export var move_speed: float = 60.0        # how fast the NPC moves
@export var min_decide_time: float = 0.5    # min seconds before picking a new direction
@export var max_decide_time: float = 2.0    # max seconds before picking a new direction
@export var idle_chance: float = 0.25       # 0.0 -> never idle, 1.0 -> always idle

# Optional: define a rectangle that the NPC is allowed to wander in.
# If you don't care, just leave it really big or ignore.
@export var roam_area: Rect2 = Rect2(Vector2(-1000, -1000), Vector2(2000, 2000))

var _target_direction: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()


@onready var _timer: Timer = $DecisionTimer


func _ready() -> void:
	# seed randomness
	_rng.randomize()

	# pick first direction
	_pick_new_direction()

	# connect timer
	_timer.timeout.connect(_on_decision_timer_timeout)


func _physics_process(delta: float) -> void:
	# Basic "wander and bounce" behavior:
	#   1. Try to move in the chosen direction.
	#   2. If we hit a wall or we're trying to leave roam_area, pick a new direction.

	if _should_idle():
		velocity = Vector2.ZERO
	else:
		velocity = _target_direction * move_speed

	# Attempt to move
	move_and_slide()

	# If we're basically not moving because we bonked a wall, choose something else
	if velocity.length() < 1.0:
		_pick_new_direction()
		return

	# Keep the character inside the roam_area (optional)
	if not roam_area.has_point(global_position):
		# steer back toward the center if we wander out of bounds
		var center := roam_area.get_center()
		_target_direction = (center - global_position).normalized()


func _on_decision_timer_timeout() -> void:
	# every time the timer fires, pick a brand new plan
	_pick_new_direction()


func _pick_new_direction() -> void:
	# Decide if we idle or walk
	if _rng.randf() < idle_chance:
		_target_direction = Vector2.ZERO
	else:
		# Pick a random angle and go that way
		var angle := _rng.randf_range(0.0, TAU)  # TAU = 2*pi
		_target_direction = Vector2(cos(angle), sin(angle)).normalized()

	# Restart the timer with a random wait time so movement feels organic
	var wait_time := _rng.randf_range(min_decide_time, max_decide_time)
	_timer.wait_time = wait_time
	_timer.start()


func _should_idle() -> bool:
	# If the chosen direction is zero, we "idle"
	return _target_direction == Vector2.ZERO
