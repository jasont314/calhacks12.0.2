extends CharacterBody3D

@export var move_speed := 1.5        # how fast it drifts around
@export var gravity := 9.8           # basic gravity
@export var wander_radius := 5.0     # how far from its spawn it's allowed to roam
@export var turn_speed_deg := 90.0   # deg/sec it can rotate to face new heading
@export var state_change_interval := Vector2(1.5, 4.0) 
# every N seconds it'll pick a new goal dir/heading

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

	# Occasionally pick a new wander direction / new look direction
	if _timer >= _next_state_time:
		_pick_new_state()

	# Smoothly rotate toward the desired heading
	_rotate_towards_heading(delta)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0

	# Horizontal drift
	var desired_vel = _walk_dir * move_speed

	# Keep within wander_radius of home
	var offset_from_home = global_transform.origin - _home_position
	offset_from_home.y = 0.0
	if offset_from_home.length() > wander_radius:
		# if we wandered too far, force direction back home
		var back_dir = (-offset_from_home).normalized()
		desired_vel = back_dir * move_speed
		_target_heading_rad = atan2(back_dir.x, back_dir.z)

	# apply horizontal velocity
	velocity.x = desired_vel.x
	velocity.z = desired_vel.z

	move_and_slide()

func _pick_new_state() -> void:
	_timer = 0.0
	_next_state_time = randf_range(state_change_interval.x, state_change_interval.y)

	# 50% chance: stand still, 50%: walk
	var should_walk := randf() < 0.5

	if should_walk:
		# pick random flat direction (XZ plane)
		var ang = randf() * TAU
		_walk_dir = Vector3(sin(ang), 0.0, cos(ang)).normalized()

		# face that way
		_target_heading_rad = atan2(_walk_dir.x, _walk_dir.z)
	else:
		# idle in place but maybe look somewhere new
		_walk_dir = Vector3.ZERO
		_target_heading_rad = randf() * TAU

func _rotate_towards_heading(delta: float) -> void:
	# turn head/body gradually so it "looks around"
	var max_turn_rad = deg_to_rad(turn_speed_deg) * delta

	# shortest angular diff
	var diff := wrapf(_target_heading_rad - _current_heading_rad, -PI, PI)

	# clamp by turn speed
	var step = clamp(diff, -max_turn_rad, max_turn_rad)
	_current_heading_rad += step

	# apply rotation to the whole body
	rotation.y = _current_heading_rad
