class_name Hud
extends Control

## The on-screen controls: view rotation, board flip, and whose turn it is.
##
## The HUD knows nothing about the camera or the game. It emits intents and
## Main routes them, which keeps it reusable and lets the whole control layer
## be tested without a viewport. Signals are used rather than direct calls so
## that UI never reaches sideways into the scene it happens to sit in.

## Emitted with +1 to rotate right, -1 to rotate left, in degrees.
signal rotate_requested(direction: int)
## Emitted when the player asks for the default framing back.
signal reset_view_requested
## Emitted to swap the board to the other player's point of view.
signal flip_requested

@onready var turn_label: Label = %TurnLabel
@onready var rotate_left_button: Button = %RotateLeftButton
@onready var rotate_right_button: Button = %RotateRightButton
@onready var flip_button: Button = %FlipButton
@onready var reset_button: Button = %ResetButton

## Minimum touch target. Phones need roughly this much to hit reliably.
const TOUCH_SIZE := Vector2(72.0, 56.0)


func _ready() -> void:
	rotate_left_button.pressed.connect(_on_rotate_left)
	rotate_right_button.pressed.connect(_on_rotate_right)
	flip_button.pressed.connect(_on_flip)
	reset_button.pressed.connect(_on_reset)


## Shows whose turn it is. Call after any move.
func set_turn(side: int, moves: int) -> void:
	if turn_label == null:
		return
	var name := "White" if side == BoardState.LIGHT else "Black"
	turn_label.text = "%s to move    ·    %d %s" % [
		name, moves, "move" if moves == 1 else "moves"
	]


## Connects the button bar without waiting for _ready, so tests can drive the
## HUD straight after instantiation.
func bind() -> void:
	if rotate_left_button == null:
		return
	if not rotate_left_button.pressed.is_connected(_on_rotate_left):
		rotate_left_button.pressed.connect(_on_rotate_left)
	if not rotate_right_button.pressed.is_connected(_on_rotate_right):
		rotate_right_button.pressed.connect(_on_rotate_right)
	if not flip_button.pressed.is_connected(_on_flip):
		flip_button.pressed.connect(_on_flip)
	if not reset_button.pressed.is_connected(_on_reset):
		reset_button.pressed.connect(_on_reset)


func _on_rotate_left() -> void:
	rotate_requested.emit(-1)


func _on_rotate_right() -> void:
	rotate_requested.emit(1)


func _on_flip() -> void:
	flip_requested.emit()


func _on_reset() -> void:
	reset_view_requested.emit()