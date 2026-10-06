extends SceneTree

## Bakes every authored piece shape to a plain mesh.
##
## The shapes are authored as CSG because a silhouette is easier to shape as a
## revolved or lofted profile than as a mesh. CSG is not what should ship: the docs
## are explicit that "the CSG nodes in Godot are mainly intended for prototyping",
## and the same page gives the way out — since 4.4 a CSG node converts to a
## MeshInstance3D, which loads faster because nothing is recomputed at start-up.
##
## So the source of truth stays an editable `.tscn` and this turns it into a mesh
## resource beside it. Runtime loads only the mesh; the CSG never enters the game.
##
##     godot-headless --headless --path godot --script res://tools/bake_piece_shapes.gd
##
## Re-run after editing a shape. The baked file is committed, so the game builds and
## runs without this.

const SHAPE_DIR := "res://src/game/pieces/shapes"


func _init() -> void:
	# CSG computes its geometry once it is in a tree and has had a frame, so the
	# shapes are added to the scene before anything is baked.
	# The instances that go in the tree are the ones that get baked. Baking a separate
	# instance produces nothing, because CSG computes its geometry only while it is
	# inside a tree.
	var live := {}
	for path in _shape_scenes():
		var packed := load(path) as PackedScene
		if packed == null:
			printerr("could not load %s" % path)
			quit(1)
			return
		var instance := packed.instantiate()
		root.add_child(instance)
		live[path] = instance
	await process_frame
	await process_frame

	var baked := 0
	for path in _shape_scenes():
		if _bake(path, live[path]):
			baked += 1
	print("baked %d shape(s)" % baked)
	quit(0 if baked > 0 else 1)


func _shape_scenes() -> Array[String]:
	var found: Array[String] = []
	for path in DirAccess.get_files_at(SHAPE_DIR):
		if path.ends_with(".tscn"):
			found.append("%s/%s" % [SHAPE_DIR, path])
	found.sort()
	return found


func _bake(scene_path: String, instance: Node) -> bool:
	var shapes := _shapes_in(instance)
	if shapes.is_empty():
		printerr("%s has no CSGShape3D in it" % scene_path)
		return false

	var meshes: Array[Mesh] = []
	for shape in shapes:
		var baked: ArrayMesh = shape.bake_static_mesh()
		if baked == null:
			printerr("%s: %s produced no mesh" % [scene_path, shape.name])
			return false
		meshes.append(baked)

	# One surface per shape, merged into the single mesh the runtime wants. A piece is
	# one draw call, which matters at thirty-two pieces plus the trays.
	var merged := ArrayMesh.new()
	for mesh in meshes:
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var out_path := scene_path.replace(".tscn", ".tres")
	var err := ResourceSaver.save(merged, out_path)
	if err != OK:
		printerr("could not save %s: %d" % [out_path, err])
		return false
	print("  %s -> %s (%d surfaces)" % [scene_path.get_file(), out_path.get_file(),
		merged.get_surface_count()])
	return true


## Every CSGShape3D in the scene, outermost first, because a combiner's own operation
## applies to its children in tree order and the order is the shape.
func _shapes_in(from: Node) -> Array[CSGShape3D]:
	var found: Array[CSGShape3D] = []
	if from is CSGShape3D:
		found.append(from as CSGShape3D)
	for child in from.get_children():
		found.append_array(_shapes_in(child))
	return found