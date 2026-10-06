class_name DiscoverySettingsDialog
extends AcceptDialog

## Where this player can be found.
##
## Extracted from the hub script for the reason the player row and the flow card were
## extracted: a dialog with its own layout, its own controls and its own wording is a
## thing, and a thing belongs in a scene where it can be seen and edited. See
## docs/architecture/foundation_tightening.md, item 2.

## Raised when either answer changes. The dialog reports what the player chose and
## does not decide what it means for the profile line, which is the hub's business.
signal discovery_changed(nearby: bool, online: bool)

@export var discoverable_nearby := true
@export var discoverable_online := false

@onready var _nearby: CheckButton = %Nearby
@onready var _online: CheckButton = %Online


func _ready() -> void:
	# The message label belongs to AcceptDialog itself, so it is reached through the
	# supported accessor rather than by path into the engine's own node tree.
	get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_nearby.toggled.connect(_on_toggled)
	_online.toggled.connect(_on_toggled)
	_apply()


## Shows the dialog with the answers as they are now.
##
## Not named `open`, because that is already a name on Object, and a method that
## shadows an inherited one is a method that means two things.
func show_dialog() -> void:
	_apply()
	show()


## Puts the stored answers back onto the two controls. Used before showing, so a
## dialog reopened after a cancel shows the answers that are in force rather than
## whatever was left on screen.
func _apply() -> void:
	_nearby.set_pressed_no_signal(discoverable_nearby)
	_online.set_pressed_no_signal(discoverable_online)


func _on_toggled(_enabled: bool) -> void:
	discoverable_nearby = _nearby.button_pressed
	discoverable_online = _online.button_pressed
	discovery_changed.emit(discoverable_nearby, discoverable_online)