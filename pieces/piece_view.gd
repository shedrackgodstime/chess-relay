@tool
class_name PieceView
extends MeshInstance3D

## A single procedurally generated chess piece.
##
## Exposes the piece's identity as exported properties so pieces can be
## configured in the inspector and duplicated freely. The mesh is generated on
## change rather than stored in the scene, so changing a property re-lathes the
## piece immediately in the editor viewport.
##
## side is an index into PieceProfiles' palette: 0 is the light set, 1 the dark.

@export_enum("Light", "Dark") var side: int = 0:
	set(value):
		side = clampi(value, 0, 1)
		rebuild()

@export var piece_type: PieceProfiles.Type = PieceProfiles.Type.PAWN:
	set(value):
		piece_type = value
		rebuild()

## Knight heads are modelled facing +X. Rotating them to face the opposing
## side is what makes a full set read correctly, so this is exposed rather than
## hard-coded.
@export var face_opponent: bool = false:
	set(value):
		face_opponent = value
		rotation.y = PI if value else 0.0


## Emitted when a glide or capture animation finishes.
signal move_finished

## Board square this piece stands on, as (file, rank). Main assigns it from
## the scene layout at startup and updates it on every move.
var home_square := Vector2i(-1, -1)

## Seconds per square glided. Slow enough to read, fast enough to not bore.
const GLIDE_SECONDS_PER_SQUARE := 0.12
const CAPTURE_SECONDS := 0.25

var _move_tween: Tween


func _ready() -> void:
	rebuild()


## Regenerates the piece geometry for the current type and side.
func rebuild() -> void:
	mesh = PieceMesh.build(piece_type, side)
	rotation.y = PI if face_opponent else 0.0


## True while a glide or capture animation is running.
func is_moving() -> bool:
	return _move_tween != null and _move_tween.is_valid() and _move_tween.is_running()


## Glides to a board position. Knights hop (a sine arc) while everything else
## slides, which is the one motion detail that sells each piece's character.
## A new order kills the old tween and starts from the current position, so
## rapid taps never strand a piece between squares.
func glide_to(target: Vector3, hop: bool = false) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	var from := position
	var squares := Vector2(from.x, from.z).distance_to(Vector2(target.x, target.z))
	var duration := maxf(0.08, squares * GLIDE_SECONDS_PER_SQUARE)
	_move_tween = create_tween().set_parallel()
	_move_tween.tween_property(self, "position:x", target.x, duration)
	_move_tween.tween_property(self, "position:z", target.z, duration)
	if hop:
		_move_tween.tween_method(_hop_height.bind(from.y), 0.0, 1.0, duration)
	else:
		_move_tween.tween_property(self, "position:y", target.y, duration * 0.5)
	_move_tween.chain().tween_callback(_on_glide_done)


func _hop_height(t: float, from_y: float) -> void:
	position.y = from_y + sin(t * PI) * 0.55


func _on_glide_done() -> void:
	move_finished.emit()


## Capture effect: shrinks, sinks and fades, then frees the node. Main removes
## it from the registry first, so the animation never affects game state.
func capture() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween().set_parallel()
	_move_tween.tween_property(self, "scale", Vector3.ONE * 0.01, CAPTURE_SECONDS)
	_move_tween.tween_property(self, "position:y", position.y - 0.4, CAPTURE_SECONDS)
	_move_tween.tween_property(self, "transparency", 1.0, CAPTURE_SECONDS)
	_move_tween.chain().tween_callback(_on_glide_done)
	_move_tween.tween_callback(queue_free)
