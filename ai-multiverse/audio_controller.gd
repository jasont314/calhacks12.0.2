extends Node

@onready var input : AudioStreamPlayer = $input

var index : int

var effect : AudioEffectCapture
var playback : AudioStreamGeneratorPlayback

@export var outputPath : NodePath

var inputThreshold = 0.005

func _ready():
	pass

func setupAudio(id):
	set_multiplayer_authority(id)
	if is_multiplayer_authority():
		input.stream = AudioStreamMicrophone.new()
		input.play()
		index = AudioServer.get_bus_index("Record")
		effect = AudioServer.get_bus_effect(index, 0)
		
	playback = get_node(outputPath).get_stream_playback()
	
func _process(delta: float) -> void:
	if is_multiplayer_authority():
		processMic()
	pass
	
func processMic():
	var stereoData : PackedVector2Array = effect.get_buffer(effect.get_frames_available())
	
	if stereoData.size() > 0:
		var data = PackedFloat32Array()
		data.resize(stereoData.size())
		var maxAmplitude := 0.0
		
		for i in range(stereoData.size()):
			var value = (stereoData[i].x +   stereoData[i].y) / 2
			maxAmplitude = max(value, maxAmplitude)
			data[i] = value
			
		if maxAmplitude < 0.005: 
			return
		
		print(data)
