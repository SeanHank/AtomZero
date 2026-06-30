# AtomZero main scene
# The body is an empty framework; this scene only serves as a runtime entry point and a minimal UI container.
# The actual game UI (main menu, HUD, etc.) should be provided by Global Mods.
extends Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Main renders above Bootstrap's child nodes (DebugConsole/DebugOverlay)
	# Set to IGNORE so mouse events pass through to the console UI below
	mouse_filter = Control.MOUSE_FILTER_IGNORE
