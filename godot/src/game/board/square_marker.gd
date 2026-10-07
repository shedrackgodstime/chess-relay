extends RefCounted

const DOT_RADIUS := 0.13
const DOT_HEIGHT := 0.018
const RING_OUTER_RADIUS := 0.42
const RING_INNER_RADIUS := 0.30
const RING_HEIGHT := 0.018


static func create_dot(color: Color, marker_name: String, position: Vector3) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = DOT_RADIUS
	mesh.bottom_radius = DOT_RADIUS
	mesh.height = DOT_HEIGHT
	mesh.radial_segments = 24
	marker.mesh = mesh
	marker.material_override = _material(color)
	marker.position = position
	return marker


## Flat ring marker: captures and any future "loud" square state. Same
## footprint language as the dot, open centre so the victim piece shows
## through until it is taken.
static func create_ring(color: Color, marker_name: String, position: Vector3) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = RING_INNER_RADIUS
	mesh.outer_radius = RING_OUTER_RADIUS
	mesh.rings = 24
	mesh.ring_segments = 8
	marker.mesh = mesh
	marker.material_override = _material(color)
	marker.position = position
	return marker


static func create_square(color: Color, marker_name: String, position: Vector3) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.84, 0.026, 0.84)
	marker.mesh = mesh
	marker.material_override = _material(color)
	marker.position = position
	return marker


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	return material
