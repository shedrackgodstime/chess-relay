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

## Where each baked shape is.
##
## A mesh resource, not the CSG scene beside it. The CSG is how a silhouette is
## authored — a revolved or lofted profile is far easier to shape than a mesh — but
## the docs are explicit that CSG "is mainly intended for prototyping", and the same
## page's way out is to convert it, because "the CSG mesh no longer needs to be
## rebuilt when the scene loads". `tools/bake_piece_shapes.gd` does that conversion
## and the result is committed, so nothing in the game evaluates CSG at all.
const SHAPE_MESHES := {
	&"pawn": "res://src/game/pieces/shapes/pawn.tres",
	&"knight": "res://src/game/pieces/shapes/knight.tres",
	&"rook": "res://src/game/pieces/shapes/rook.tres",
	&"bishop": "res://src/game/pieces/shapes/bishop.tres",
	&"queen": "res://src/game/pieces/shapes/queen.tres",
	&"king": "res://src/game/pieces/shapes/king.tres",
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