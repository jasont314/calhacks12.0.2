# res://scripts/player/player_controller.gd
extends CharacterBody3D

@onready var camera = $Camera3D

func _ready():
	print("========================================")
	print("PLAYER READY - FULL DEBUG")
	print("========================================")
	print("Player node name: ", name)
	print("Player global position: ", global_position)
	print("")
	
	# Check camera exists
	print("Camera node exists: ", camera != null)
	if camera:
		print("Camera path: ", camera.get_path())
		print("Camera global position: ", camera.global_position)
		print("Camera rotation: ", camera.rotation_degrees)
		print("Camera is current BEFORE make_current: ", camera.is_current())
		
		# Force camera to be current
		camera.make_current()
		
		await get_tree().process_frame
		
		print("Camera is current AFTER make_current: ", camera.is_current())
		print("")
		
		# Check if ANY camera is current
		var viewport = get_viewport()
		print("Viewport exists: ", viewport != null)
		if viewport:
			var active_camera = viewport.get_camera_3d()
			print("Active camera in viewport: ", active_camera)
			if active_camera:
				print("Active camera path: ", active_camera.get_path())
			else:
				print("⚠️ NO ACTIVE CAMERA IN VIEWPORT!")
	else:
		print("❌ CAMERA NODE NOT FOUND!")
	
	print("========================================")
