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

## Candidate sets, so two can be on the board at once and compared.
##
## Both are here because proportion cannot be judged from numbers: a knight that
## measures the right height can still read as a lump, and that is a thing to look at.
## Changing `ACTIVE_SET` is the whole comparison.
const SETS := {
	&"oga": {
		&"pawn": "res://src/game/pieces/models/oga/pawn.glb",
		&"knight": "res://src/game/pieces/models/oga/knight.glb",
		&"bishop": "res://src/game/pieces/models/oga/bishop.glb",
		&"rook": "res://src/game/pieces/models/oga/rook.glb",
		&"queen": "res://src/game/pieces/models/oga/queen.glb",
		&"king": "res://src/game/pieces/models/oga/king.glb",
	},
	&"saber": {
		&"pawn": "res://src/game/pieces/models/saber/pawn.glb",
		&"knight": "res://src/game/pieces/models/saber/knight.glb",
		&"bishop": "res://src/game/pieces/models/saber/bishop.glb",
		&"rook": "res://src/game/pieces/models/saber/rook.glb",
		&"queen": "res://src/game/pieces/models/saber/queen.glb",
		&"king": "res://src/game/pieces/models/saber/king.glb",
	},
}

## Which set the game draws with.
const ACTIVE_SET := &"oga"

## How big each piece ends up.
##
## The difference between the two entries is the whole reason they are here.
##
## **OGA** is one number for all six. Its models share a base footprint and their
## heights are already in tournament proportion — pawn 0.53, rook 0.58, knight 0.63,
## bishop 0.74, queen 0.89 of the king — so scaling the set as one thing is correct
## and a single factor is all it takes.
##
## **Saber** needs a different factor per piece. Its six models are not a set: their
## base footprints run from 0.536 to 0.948, and a knight is 0.35 of the king's
## height, which makes it the smallest piece on the board. Scaling it as one thing is
## what its original project does, by ten, and that makes the inconsistency uniformly
## wrong rather than removing it.
##
## The targets are a starting point. Proportion is judged by looking.
const SET_SCALE := {
	&"oga": 11.8,
	&"saber": {
		&"knight": 1.466,
		&"pawn": 0.823,
		&"bishop": 0.791,
		&"rook": 0.903,
		&"queen": 0.699,
		&"king": 0.671,
	},
}

## Loaded once. A dictionary of paths read per instance would be a disk read per piece.
static var _loaded: Dictionary = {}


## The mesh for an identity in the active set, or null if that identity has no model.
##
## Null rather than a placeholder on purpose. A pawn standing in for a missing king
## would look like a bug somewhere else entirely.
##
## **The mesh is a shared resource and carries nothing but geometry.** No material and
## no scale, because both are properties of the node that draws it and not of the
## geometry: a colour and a size belong to how a piece is presented here, and thirty-two
## nodes sharing one mesh is thirty-two times less memory than thirty-two copies.
static func mesh_for(identity: StringName) -> Mesh:
	var set_paths: Dictionary = SETS.get(ACTIVE_SET, {})
	var path: String = set_paths.get(identity, "")
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var mesh := _mesh(path)
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	return mesh


## How large this identity's model is drawn.
##
## A `Vector3` rather than a float because it is applied to a node, and a node's scale
## is a vector. Uniform, because every scale here is uniform.
static func model_scale_for(identity: StringName) -> Vector3:
	var entry = SET_SCALE.get(ACTIVE_SET, 1.0)
	if entry is Dictionary:
		return Vector3.ONE * float((entry as Dictionary).get(identity, 1.0))
	return Vector3.ONE * float(entry)


## A piece material, kept as a resource rather than applied as an override at each
## use, so one change re-skins every piece.
static func material_for(side: StringName) -> StandardMaterial3D:
	if side == DARK:
		return _dark()
	return _light()


static func _scale_for(identity: StringName) -> float:
	var entry = SET_SCALE.get(ACTIVE_SET, 1.0)
	if entry is Dictionary:
		return float((entry as Dictionary).get(identity, 1.0))
	return float(entry)


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


## The mesh for a model path.
##
## Two routes, in order. The first is the imported resource, which is what the game
## should normally use: it is faster to load and it is what the import pipeline is for.
##
## The second reads the glTF at run time through `GLTFDocument`. That exists because
## a `.glb` is only loadable once it has been imported, and the import step is the one
## part of this project that cannot always run headlessly — `--import` and `--editor`
## both abort on some builds. Without this the board was simply empty, with a warning
## per piece and nothing to see.
static func _mesh(path: String) -> Mesh:
	if _loaded.has(path):
		return _loaded[path] as Mesh
	var mesh := _imported_mesh(path)
	if mesh == null:
		mesh = _gltf_mesh(path)
	_loaded[path] = mesh
	return mesh


## Through the import pipeline, which is the normal route.
static func _imported_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return load(path) as Mesh
	var root := packed.instantiate()
	var found := _first_mesh(root)
	var mesh := found.mesh if found != null else null
	if root != null:
		root.free()
	return mesh


## Straight out of the glTF, with no import step.
static func _gltf_mesh(path: String) -> Mesh:
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_file(ProjectSettings.globalize_path(path), state)
	if err != OK:
		push_warning("could not read %s: %d" % [path, err])
		return null
	var root := document.generate_scene(state)
	if root == null:
		return null
	var found := _first_mesh(root)
	var mesh := found.mesh if found != null else null
	if mesh == null:
		root.free()
		return null
	# The node's own transform is part of the model. These files are authored at large
	# raw sizes and scaled down by their root node — a pawn's vertices span 2.5 units
	# behind a node scaled by 0.02 — and taking only the mesh resource throws that away,
	# so a piece would come out fifty times too large.
	mesh = _bake_transform(mesh, found.transform)
	root.free()
	return mesh


## Normals pushed through a basis.
static func _reorient_normals(normals: PackedVector3Array, basis: Basis) -> PackedVector3Array:
	var moved := PackedVector3Array()
	moved.resize(normals.size())
	for index in normals.size():
		moved[index] = basis * normals[index]
	return moved


## A copy of the mesh with a transform folded into its vertices.
##
## Baking rather than keeping the node transform, because the piece node is the only
## thing that will ever draw this and it should carry one transform of its own.
static func _bake_transform(mesh: Mesh, transform: Transform3D) -> Mesh:
	var baked := ArrayMesh.new()
	var basis := transform.basis
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		if arrays[Mesh.ARRAY_VERTEX] != null:
			arrays[Mesh.ARRAY_VERTEX] = transform * arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_NORMAL] != null:
			# Normals follow the inverse transpose, so a non-uniform scale would
			# otherwise tilt them.
			# Normals follow the inverse transpose, so a non-uniform scale would
			# otherwise tilt them. One at a time: `Basis * PackedVector3Array` is
			# not a valid operation even though `Transform3D * PackedVector3Array`
			# is, which is an easy thing to assume.
			arrays[Mesh.ARRAY_NORMAL] = _reorient_normals(
				arrays[Mesh.ARRAY_NORMAL], basis.inverse().transposed())
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return baked


## The first MeshInstance3D anywhere below a node. A glTF scene carries its own root
## and naming, so the mesh is looked for rather than assumed at a fixed path.
static func _first_mesh(from: Node) -> MeshInstance3D:
	if from is MeshInstance3D:
		return from as MeshInstance3D
	for child in from.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


## Drops the cache. For tests, and for the editor after a shape is rebuilt.
static func clear_cache() -> void:
	_loaded.clear()