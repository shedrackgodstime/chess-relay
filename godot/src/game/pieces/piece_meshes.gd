class_name PieceMeshes
extends RefCounted

## One mesh per piece shape, and a material per side. Colour is the second axis, not
## a second set of shapes, so a full set is six shapes and two materials rather than
## twelve things.
##
## This is a lookup, not a declaration. The identities it is keyed by are the ones
## that arrive over the application boundary, not a list this project invented:
## `application_core.md` puts board and piece state in Rust's `chess_core` and says of
## Godot only that it "renders the board". Declaring an enum of piece types here would
## be a second source of truth for piece identity — correct-looking, passing every
## check, and disagreeing with `chess_core` the first time either side changed.
##
## It is keyed by StringName rather than by an integer because that is the form that
## crosses a language boundary without agreeing on a number first, and because a
## misspelled identity is a missing mesh at run time rather than a wrong mesh.

const LIGHT := &"light"
const DARK := &"dark"

## Where each shape comes from.
##
## Imported models, one per identity, from models/README.md. CSG was tried first and
## dropped: a solid of revolution cannot express a rook's merlons, a queen's crown or
## a king's cross, and those details are what make a piece read as itself.
##
## The identities here are the point. They are names that arrive over the application
## boundary, not an enum declared in this project, so there is one list of piece types
## and it is not this one.
const SHAPE_MESHES := {
	&"pawn": "res://src/game/pieces/models/pawn.glb",
	&"knight": "res://src/game/pieces/models/knight.glb",
	&"rook": "res://src/game/pieces/models/rook.glb",
	&"bishop": "res://src/game/pieces/models/bishop.glb",
	&"queen": "res://src/game/pieces/models/queen.glb",
	&"king": "res://src/game/pieces/models/king.glb",
}

## Every model arrives at whatever size its author worked in, and these six are not
## even the same size as each other.
##
## Measured from the glTF position accessors rather than assumed. The prototype scales
## every piece by the same `Vector3(10, 10, 10)`, which hides the inconsistency by
## making it uniformly wrong rather than by removing it.
##
## Measured heights as imported, and what each is scaled to:
##
## ```text
##           as imported   scaled to   by
##   knight      0.58        0.85      1.466
##   pawn        0.79        0.65      0.823
##   bishop      1.16        0.92      0.791
##   rook        0.93        0.84      0.903
##   queen       1.43        1.00      0.699
##   king        1.67        1.12      0.671
## ```
##
## The targets are a starting point, not a measurement of how these particular models
## ought to look. Proportion cannot be judged headlessly: whether a knight reads as a
## knight is a thing to look at, which is the same lesson as the camera pitch and the
## square occlusion. So the numbers are here, the reasoning is here, and the last word
## belongs on the board.
const MODEL_SCALE := {
	&"knight": 1.466,
	&"pawn": 0.823,
	&"bishop": 0.791,
	&"rook": 0.903,
	&"queen": 0.699,
	&"king": 0.671,
}

## Loaded once. A dictionary of paths read per instance would be a disk read per piece.
static var _loaded: Dictionary = {}


## The mesh for an identity and a side, or null if the identity has no shape yet.
##
## Null rather than a placeholder on purpose. A pawn standing in for a missing king
## would look like a bug somewhere else entirely.
static func mesh_for(identity: StringName, side: StringName) -> Mesh:
	var path: String = SHAPE_MESHES.get(identity, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var mesh := _mesh(path)
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	# Duplicated rather than loaded and mutated in place: two sides ask for the same
	# shape and a shared mesh with one surface's material overwritten would make the
	# light pieces turn dark the first time a dark one was drawn.
	var copy: Mesh = mesh.duplicate()
	copy.surface_set_material(0, material_for(side))
	var scale: float = MODEL_SCALE.get(identity, 1.0)
	if not is_equal_approx(scale, 1.0):
		copy.scale = Vector3.ONE * scale
	return copy


## A piece material, kept as a resource rather than applied as an override at each
## use, so one change re-skins every piece.
static func material_for(side: StringName) -> StandardMaterial3D:
	if side == DARK:
		return _dark()
	return _light()


static func _light() -> StandardMaterial3D:
	var cached := _loaded.get(LIGHT, null) as StandardMaterial3D
	if cached != null:
		return cached
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.86, 0.74)
	material.roughness = 0.42
	material.metallic_specular = 0.5
	_loaded[LIGHT] = material
	return material


static func _dark() -> StandardMaterial3D:
	var cached := _loaded.get(DARK, null) as StandardMaterial3D
	if cached != null:
		return cached
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.10, 0.07, 0.05)
	material.roughness = 0.42
	material.metallic_specular = 0.5
	_loaded[DARK] = material
	return material


static func _mesh(path: String) -> Mesh:
	if _loaded.has(path):
		return _loaded[path] as Mesh
	var mesh := load(path) as Mesh
	_loaded[path] = mesh
	return mesh


## Drops the cache. For tests, and for the editor after a shape is rebuilt.
static func clear_cache() -> void:
	_loaded.clear()