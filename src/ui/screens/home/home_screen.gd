class_name HomeScreen
extends Control

signal play_computer_requested
signal p2p_requested
signal settings_requested


func _on_play_computer_pressed() -> void:
	play_computer_requested.emit()


func _on_p2p_pressed() -> void:
	p2p_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()
