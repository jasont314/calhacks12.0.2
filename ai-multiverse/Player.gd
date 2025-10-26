extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

@onready var pivot = $CamOrigin
@export var sens = 0.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
# var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var look_dir: Vector2
@onready var camera = $Camera3D
var camera_sens = 50


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	
	
func _ready(): 
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = is_multiplayer_authority()
	
	if not is_multiplayer_authority():
		set_physics_process(false)


func _rotate_camera(delta: float, sens_mod: float = 1.0):
	var input = Input.get_vector("look_left", "look_right", "look_down", "look_up")
	look_dir += input
	rotation.y -= look_dir.x * camera_sens * delta
	camera.rotation.x = clamp(camera.rotation.x - look_dir.y * camera_sens * sens_mod * delta, -1.5, 1.5)
	look_dir = Vector2.ZERO
	
func _input(event):
	if event is InputEventMouseMotion: look_dir = event.relative * 0.01
		
func _physics_process(delta):
	if not is_multiplayer_authority():
		return
	# if not is_on_floor():
		# velocity.y -= gravity * delta

	# Handle Jump.
	# if Input.is_action_just_pressed("jump") and is_on_floor():
		# velocity.y = JUMP_VELOCITY
	
	# hard-lock to ground plane
	var t := global_transform
	t.origin.y = 0.0
	global_transform = t
	velocity.y = 0.0
	
	if Input.is_action_just_pressed("quit"):
		$"../".exit_game(name.to_int()) 
		get_tree().quit()
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	
	_rotate_camera(delta)
	move_and_slide()
