extends CharacterBody3D

@export var move_speed: float = 4.0
@export var min_decide_time: float = 0.5
@export var max_decide_time: float = 2.0
@export var idle_chance: float = 0.25
@export var roam_box: AABB = AABB(Vector3(-10, 0, -10), Vector3(20, 10, 20)) # (origin, size)

var _target_direction: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
@onready var _timer: Timer = $DecisionTimer

func _ready() -> void:
	_rng.randomize()
	_pick_new_direction()
	_timer.timeout.connect(_on_decision_timer_timeout)
	_timer.start()  # ensures movement starts right away

func _physics_process(delta: float) -> void:
	if _target_direction == Vector3.ZERO:
		velocity = Vector3.ZERO
	else:
		velocity = _target_direction * move_speed

	move_and_slide()

	# if we hit a wall or slowed down too much, pick a new direction
	if velocity.length() < 0.1:
		_pick_new_direction()

	# keep within roam_box bounds
	if not _is_inside_roam_box(global_position):
		var center := roam_box.position + roam_box.size / 2.0
		_target_direction = (center - global_position).normalized()

func _on_decision_timer_timeout() -> void:
	_pick_new_direction()

func _pick_new_direction() -> void:
	if _rng.randf() < idle_chance:
		_target_direction = Vector3.ZERO
	else:
		# pick random direction in the XZ plane
		var angle := _rng.randf_range(0.0, TAU)
		_target_direction = Vector3(cos(angle), 0, sin(angle)).normalized()

	var wait_time := _rng.randf_range(min_decide_time, max_decide_time)
	_timer.wait_time = wait_time
	_timer.start()

func _is_inside_roam_box(pos: Vector3) -> bool:
	return (
		pos.x >= roam_box.position.x and pos.x <= roam_box.position.x + roam_box.size.x and
		pos.y >= roam_box.position.y and pos.y <= roam_box.position.y + roam_box.size.y and
		pos.z >= roam_box.position.z and pos.z <= roam_box.position.z + roam_box.size.z
	)
