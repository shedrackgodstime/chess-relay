class_name Primitives
extends RefCounted

## Small hand-built solids for details that a solid of revolution cannot
## express: the king's cross, the rook's merlons, the queen's crown points.
##
## These exist so the pieces keep their recognisable silhouette without any
## imported art. Each returns MeshData so it can be merged into a piece and
## pick up the piece's material.
##
## Winding follows the same convention as lathe.gd: the right-hand-rule normal
## points opposite to the stored vertex normals.


## An axis-aligned box centred on the origin. Every face carries its own four
## vertices with 0..1 UVs, so a texture maps cleanly onto each face.
static func box(size: Vector3) -> MeshData:
	return _box_faces(size, 0.0)


## A box whose top edges are chamfered, so tiles catch a highlight instead of
## meeting at a hard knife edge. Bevel is clamped to half the smallest
## dimension. The bottom stays flat so tiles sit flush.
static func beveled_box(size: Vector3, bevel: float) -> MeshData:
	return _box_faces(size, bevel)


static func _box_faces(size: Vector3, bevel: float) -> MeshData:
	var data := MeshData.new()
	var h := size * 0.5
	var b := clampf(bevel, 0.0, minf(h.x, minf(h.y, h.z)) * 0.5)
	var top_y := h.y - b

	# Each face lists its outward normal, four corners in the same mathematical
	# order as the original box, and four UVs. Sharp edges get duplicated
	# vertices so the chamfer shades as its own crisp band.
	var faces := [
		[Vector3(0, 0, 1), [
			Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
			Vector3(h.x, top_y, h.z), Vector3(-h.x, top_y, h.z)]],
		[Vector3(0, 0, -1), [
			Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z),
			Vector3(-h.x, top_y, -h.z), Vector3(h.x, top_y, -h.z)]],
		[Vector3(1, 0, 0), [
			Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z),
			Vector3(h.x, top_y, -h.z), Vector3(h.x, top_y, h.z)]],
		[Vector3(-1, 0, 0), [
			Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z),
			Vector3(-h.x, top_y, h.z), Vector3(-h.x, top_y, -h.z)]],
	]

	for face in faces:
		_add_quad(data, face[0], face[1])

	if b <= 0.0:
		_add_quad(data, Vector3(0, 1, 0), [
			Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z),
			Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)])
	else:
		var slopes := [
			[Vector3(0, 1, 1).normalized(), [
				Vector3(-h.x, top_y, h.z), Vector3(h.x, top_y, h.z),
				Vector3(h.x - b, h.y, h.z - b), Vector3(-h.x + b, h.y, h.z - b)]],
			[Vector3(0, 1, -1).normalized(), [
				Vector3(h.x, top_y, -h.z), Vector3(-h.x, top_y, -h.z),
				Vector3(-h.x + b, h.y, -h.z + b), Vector3(h.x - b, h.y, -h.z + b)]],
			[Vector3(1, 1, 0).normalized(), [
				Vector3(h.x, top_y, h.z), Vector3(h.x, top_y, -h.z),
				Vector3(h.x - b, h.y, -h.z + b), Vector3(h.x - b, h.y, h.z - b)]],
			[Vector3(-1, 1, 0).normalized(), [
				Vector3(-h.x, top_y, -h.z), Vector3(-h.x, top_y, h.z),
				Vector3(-h.x + b, h.y, h.z - b), Vector3(-h.x + b, h.y, -h.z + b)]],
		]
		for slope in slopes:
			_add_quad(data, slope[0], slope[1])
		_add_quad(data, Vector3(0, 1, 0), [
			Vector3(-h.x + b, h.y, h.z - b), Vector3(h.x - b, h.y, h.z - b),
			Vector3(h.x - b, h.y, -h.z + b), Vector3(-h.x + b, h.y, -h.z + b)])

	_add_quad(data, Vector3(0, -1, 0), [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)])
	return data


static func _add_quad(data: MeshData, normal: Vector3, corners: Array) -> void:
	var base := data.vertices.size()
	var quad_uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in corners.size():
		data.vertices.append(corners[i])
		data.normals.append(normal)
		data.uvs.append(quad_uvs[i])
	for i in range(1, corners.size() - 1):
		data.indices.append_array([base, base + i + 1, base + i])


## Copies count copies of geometry around the Y axis at the given radius, which
## is how the rook gets its merlons and the queen her crown points.
static func ring(geometry: MeshData, count: int, radius: float, height: float) -> MeshData:
	var merged := MeshData.new()
	if geometry == null or geometry.is_empty() or count < 1:
		return merged
	for i in count:
		var angle := TAU * i / count
		var offset := Vector3(cos(angle) * radius, height, sin(angle) * radius)
		merged.append(geometry, Transform3D(Basis(Vector3.UP, angle), offset))
	return merged


## A four-sided pyramid, used for the pointed elements on the queen's crown.
static func spike(base_radius: float, height: float, sides: int = 4) -> MeshData:
	var data := MeshData.new()
	if sides < 3 or base_radius <= 0.0 or height <= 0.0:
		return data

	var base := data.vertices.size()
	for i in sides:
		var angle := TAU * i / sides
		var p := Vector3(cos(angle) * base_radius, 0.0, sin(angle) * base_radius)
		data.vertices.append(p)
		data.normals.append(p.normalized())
		data.uvs.append(Vector2(float(i) / float(sides), 0.0))
	var apex := data.vertices.size()
	data.vertices.append(Vector3(0.0, height, 0.0))
	data.normals.append(Vector3.UP)
	data.uvs.append(Vector2(0.5, 1.0))
	for i in sides:
		data.indices.append_array([base + i, base + (i + 1) % sides, apex])

	var centre := data.vertices.size()
	data.vertices.append(Vector3.ZERO)
	data.normals.append(Vector3.DOWN)
	data.uvs.append(Vector2(0.5, 0.0))
	for i in sides:
		data.indices.append_array([centre, base + (i + 1) % sides, base + i])
	return data
