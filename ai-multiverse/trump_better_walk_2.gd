extends CharacterBody3D

@export var move_speed := 1.5
@export var wander_radius := 5.0
@export var turn_speed_deg := 90.0
@export var state_change_interval := Vector2(1.5, 4.0)

var _home_position: Vector3
var _target_heading_rad := 0.0
var _current_heading_rad := 0.0
var _walk_dir: Vector3 = Vector3.ZERO
var _timer := 0.0
var _next_state_time := 0.0

func _ready() -> void:
	_home_position = global_transform.origin
	_current_heading_rad = rotation.y
	_pick_new_state()

func _physics_process(delta: float) -> void:
	_timer += delta

	if _timer >= _next_state_time:
		_pick_new_state()

	_rotate_towards_heading(delta)

	# no gravity for now
	# no y velocity changes
	velocity.y = 0.0

	# horizontal drift
	var desired_vel = _walk_dir * move_speed

	# leash
	var offset = global_transform.origin - _home_position
	offset.y = 0.0
	if offset.length() > wander_radius:
		var back_dir = (-offset).normalized()
		desired_vel = back_dir * move_speed
		_target_heading_rad = atan2(back_dir.x, back_dir.z)

	velocity.x = desired_vel.x
	velocity.z = desired_vel.z

	move_and_slide()

func _pick_new_state() -> void:
	_timer = 0.0
	_next_state_time = randf_range(state_change_interval.x, state_change_interval.y)

	var should_walk := randf() < 0.5

	if should_walk:
		var ang = randf() * TAU
		_walk_dir = Vector3(sin(ang), 0.0, cos(ang)).normalized()
		_target_heading_rad = atan2(_walk_dir.x, _walk_dir.z)
	else:
		_walk_dir = Vector3.ZERO
		_target_heading_rad = randf() * TAU

func _rotate_towards_heading(delta: float) -> void:
	var max_turn_rad = deg_to_rad(turn_speed_deg) * delta
	var diff := wrapf(_target_heading_rad - _current_heading_rad, -PI, PI)
	var step = clamp(diff, -max_turn_rad, max_turn_rad)
	_current_heading_rad += step
	rotation.y = _current_heading_rad
