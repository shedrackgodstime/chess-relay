class_name MeshData
extends RefCounted

## A single block of triangle geometry: positions, normals, UVs and indices.
##
## Geometry helpers return MeshData rather than ArrayMesh so that callers can
## merge parts, transform them independently, and assign one material per part
## afterwards via MeshBuilder. Use MeshBuilder rather than this class directly
## when you need more than a single surface.

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()


func is_empty() -> bool:
	return indices.is_empty()


func triangle_count() -> int:
	return int(indices.size() / 3.0)


## Appends other, baking transform into the positions and its inverse-transpose
## into the normals so lighting stays correct under non-uniform scale.
func append(other: MeshData, transform: Transform3D = Transform3D.IDENTITY) -> void:
	if other == null or other.is_empty():
		return

	var basis := transform.basis
	var normal_basis := basis.inverse().transposed()
	var vertex_offset := vertices.size()

	for v in other.vertices:
		vertices.append(transform * v)
	for n in other.normals:
		normals.append((normal_basis * n).normalized())
	uvs.append_array(other.uvs)
	for i in other.indices:
		indices.append(i + vertex_offset)


## Surface arrays in the layout ArrayMesh expects. ArrayMesh requires the array
## to be exactly Mesh.ARRAY_MAX long, and the slots are not contiguous, so they
## are filled by constant rather than by position.
func to_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
