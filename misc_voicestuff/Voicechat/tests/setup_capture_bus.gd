extends MainLoop

#
# ⚙️ One-time setup: create a CaptureBus and AudioEffectCapture if missing.
# Run with: godot -s res://tests/setup_capture_bus.gd
#

func _initialize() -> void:
    print("⚙️ Checking for 'CaptureBus'...")

    var bus_idx := AudioServer.get_bus_index("CaptureBus")
    if bus_idx == -1:
        print("🔧 Creating 'CaptureBus'...")
        AudioServer.add_bus(AudioServer.get_bus_count())
        var new_index := AudioServer.get_bus_count() - 1
        AudioServer.set_bus_name(new_index, "CaptureBus")
        var capture := AudioEffectCapture.new()
        AudioServer.add_bus_effect(new_index, capture)
        print("✅ CaptureBus created and AudioEffectCapture added.")
    else:
        print("✅ CaptureBus already exists.")

    # clean exit (MainLoop scripts end when _process returns true)
    should_quit = true

var should_quit := false
func _process(_delta: float) -> bool:
    return should_quit
