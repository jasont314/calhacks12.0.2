# res://scripts/player/player_controller.gd
extends CharacterBody3D

# Multiplayer sync
@onready var sync = $MultiplayerSynchronizer
@onready var camera_rig = $CameraRig
@onready var camera = $CameraRig/Camera3D
@onready var name_label = $NameLabel3D

# Movement
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_local_player = false


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready():
	camera.current = is_multiplayer_authority()

func _input(event):
	if not is_local_player:
		return
	
	# Mouse look (first-person)
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_rig.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_rig.rotation.x = clamp(camera_rig.rotation.x, -PI/2, PI/2)

func _physics_process(delta):
	if is_multiplayer_authority():
		if not is_local_player:
			return
		
		# Gravity
		if not is_on_floor():
			velocity.y -= gravity * delta
		
		# Jump
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
		
		# Quit
		if Input.is_action_just_pressed("jump"):
			$"../".exit_game(name.to_int())
			get_tree().quit()
		
		# Movement
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
		
		move_and_slide()

func set_player_name(new_name: String):
	name_label.text = new_name
