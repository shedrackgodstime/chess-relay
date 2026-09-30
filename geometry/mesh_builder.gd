class_name MeshBuilder
extends RefCounted

## Assembles several MeshData parts into one ArrayMesh with one surface per
## part, so a single node can carry more than one material.
##
## Parts are kept as independent MeshData and only merged at build time. That
## keeps each part independently testable and lets a part be reused at several
## transforms without duplicating vertex data.

class Part:
	extends RefCounted

	var data: MeshData
	var transform := Transform3D.IDENTITY
	var material: Material

	func _init(p_data: MeshData, p_transform: Transform3D, p_material: Material) -> void:
		data = p_data
		transform = p_transform
		material = p_material


var _parts: Array[Part] = []


func add_part(
	data: MeshData, material: Material = null, transform: Transform3D = Transform3D.IDENTITY
) -> MeshBuilder:
	if data == null or data.is_empty():
		return self
	var part := Part.new(data, transform, material)
	_parts.append(part)
	return self


func is_empty() -> bool:
	return _parts.is_empty()


## Merges every part into a single surface, ignoring materials.
func build() -> ArrayMesh:
	var merged := MeshData.new()
	for part in _parts:
		merged.append(part.data, part.transform)

	var mesh := ArrayMesh.new()
	if merged.is_empty():
		return mesh

	# One part means one surface: cheaper and simpler for the common case.
	if _parts.size() == 1:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged.to_arrays())
		if _parts[0].material != null:
			mesh.surface_set_material(0, _parts[0].material)
		return mesh

	for part in _parts:
		var surface := MeshData.new()
		surface.append(part.data, part.transform)
		var index := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.to_arrays())
		if part.material != null:
			mesh.surface_set_material(index, part.material)
	return mesh


## Collapses every part into a single surface with one material. Use this when
## the parts are details of one object, such as a rook's body and its merlons,
## rather than genuinely different materials.
func build_merged(material: Material = null) -> ArrayMesh:
	var merged := MeshData.new()
	for part in _parts:
		merged.append(part.data, part.transform)

	var mesh := ArrayMesh.new()
	if merged.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged.to_arrays())
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh
