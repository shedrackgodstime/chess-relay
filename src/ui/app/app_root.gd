extends Control

const HOME_SCREEN: PackedScene = preload("res://src/ui/screens/home/home_screen.tscn")
const GAME_SETUP_SCREEN: PackedScene = preload(
	"res://src/ui/screens/game_setup/game_setup_screen.tscn")

@onready var _screen_host: Control = %ScreenHost

var _current_screen: Control


func _ready() -> void:
	_show_home_screen()


func _show_home_screen() -> void:
	var home_screen: Control = HOME_SCREEN.instantiate() as Control
	home_screen.connect(&"play_computer_requested", _on_play_computer_requested)
	_show_screen(home_screen)


func _on_play_computer_requested() -> void:
	_show_screen(GAME_SETUP_SCREEN.instantiate() as Control)


func _show_screen(screen: Control) -> void:
	if _current_screen != null:
		_screen_host.remove_child(_current_screen)
		_current_screen.queue_free()

	_current_screen = screen
	_screen_host.add_child(_current_screen)
	_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
