extends Node

# Called when the node enters the scene tree for the first time.
func _ready():
	# Make sure the node name matches your scene tree.
	# If your WSListener node is named "WSListener", this works:
	$WSListener._startTranscribing()
	print("🎬 Transcribing started automatically from main.gd.")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
