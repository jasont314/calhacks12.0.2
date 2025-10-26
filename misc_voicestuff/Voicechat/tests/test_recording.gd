extends MainLoop

#
# 🎙️ Godot 4.4 microphone recording test (pure MainLoop, CLI-friendly)
# Run with: godot -s res://tests/test_recording.gd
#

const SAMPLE_RATE := 44100
const CHUNK_DURATION_SEC := 2.0

var elapsed := 0.0
var start_time := 0.0
var effect: AudioEffectCapture
var bus_idx := -1

func _initialize() -> void:
    print("🎙️ [TEST] Starting microphone capture test (Godot 4.4)...")

    # Auto-create CaptureBus if missing
    var bus_idx := AudioServer.get_bus_index("CaptureBus")
    if bus_idx == -1:
        print("🔧 Creating 'CaptureBus' (runtime)...")
        AudioServer.add_bus(AudioServer.get_bus_count())
        var new_index := AudioServer.get_bus_count() - 1
        AudioServer.set_bus_name(new_index, "CaptureBus")
        var cap := AudioEffectCapture.new()
        AudioServer.add_bus_effect(new_index, cap)
        bus_idx = new_index
        print("✅ CaptureBus created in runtime session.")

    effect = AudioServer.get_bus_effect(bus_idx, 0)
    if not (effect is AudioEffectCapture):
        push_error("❌ Failed to attach AudioEffectCapture to CaptureBus.")
        return

    effect.set_recording_active(true)
    start_time = Time.get_ticks_msec() / 1000.0
    print("🎧 Recording for %.1f seconds..." % CHUNK_DURATION_SEC)


func _process(delta: float) -> bool:
    elapsed = (Time.get_ticks_msec() / 1000.0) - start_time
    if elapsed >= CHUNK_DURATION_SEC:
        _finish_recording()
        return true  # return true → end MainLoop
    return false     # continue loop until done

func _finish_recording() -> void:
    var frames := effect.get_frames_available()
    print("Frames available:", frames)
    if frames == 0:
        push_warning("⚠️ No frames captured. Speak or check mic permissions.")
        return

    var buffer := effect.get_buffer(frames)
    print("Buffer type:", typeof(buffer))
    print("Buffer size:", buffer.size())
    print("✅ Microphone capture test complete.")
