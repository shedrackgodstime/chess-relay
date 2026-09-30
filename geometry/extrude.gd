class_name Extrude
extends RefCounted

## Extrudes a closed 2D outline along Z, tapering towards both ends.
##
## The outline lives in XY (X forward, Y up) and is swept from -half_depth to
## +half_depth. Each slice is scaled about a pivot, so a shape can be pinched
## towards one end without moving the other. Caps are triangulated with
## Geometry2D, which handles concave outlines such as a horse's muzzle.
##
## Winding matches Lathe and Godot's built-in meshes: the right-hand-rule
## normal points opposite to the stored vertex normals. See the note in
## lathe.gd; the winding conformance test in tools/ guards this.

const EPSILON := 0.00001
const DEFAULT_SLICES := 7


## taper is how much the end slices shrink: 0 keeps a flat slab, 1 pinches them
## to a point. pivot is the point slices scale about, in outline space.
static func build(
	outline: PackedVector2Array,
	half_depth: float,
	taper: float = 0.35,
	slices: int = DEFAULT_SLICES,
	pivot: Vector2 = Vector2.ZERO,
	cap_start: bool = true,
	cap_end: bool = true
) -> MeshData:
	var data := MeshData.new()
	var ring := _normalise(outline)
	if ring.size() < 3 or slices < 2 or half_depth <= EPSILON:
		return data

	# Outward 2D normal per outline edge, averaged onto vertices for smooth
	# shading around the sweep.
	var edge_normals := PackedVector2Array()
	for i in ring.size():
		var prev: Vector2 = ring[(i - 1 + ring.size()) % ring.size()]
		var next: Vector2 = ring[(i + 1) % ring.size()]
		edge_normals.append(_outward(prev, ring[i]) + _outward(ring[i], next))

	var slice_starts := PackedInt32Array()
	var z_coords := PackedFloat32Array()
	for s in slices:
		slice_starts.append(data.vertices.size())
		var t := s / float(slices - 1)
		var centred := 2.0 * t - 1.0
		var scale := 1.0 - taper * centred * centred
		var z := lerpf(-half_depth, half_depth, t)
		z_coords.append(z)

		for i in ring.size():
			var scaled: Vector2 = pivot + (ring[i] - pivot) * scale
			data.vertices.append(Vector3(scaled.x, scaled.y, z))
			var n2 := edge_normals[i].normalized()
			data.normals.append(Vector3(n2.x, n2.y, 0.0))
			data.uvs.append(Vector2(i / float(ring.size()), t))

	for s in slices - 1:
		var a := slice_starts[s]
		var b := slice_starts[s + 1]
		for i in ring.size():
			var i_next := (i + 1) % ring.size()
			data.indices.append_array([a + i, b + i_next, a + i_next])
			data.indices.append_array([a + i, b + i, b + i_next])

	var tri_cap := Geometry2D.triangulate_polygon(ring)
	if tri_cap.is_empty():
		return data
	if cap_start:
		_cap(data, ring, tri_cap, z_coords[0], -1.0)
	if cap_end:
		_cap(data, ring, tri_cap, z_coords[slices - 1], 1.0)
	return data


static func _outward(from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	if d.length_squared() < EPSILON * EPSILON:
		return Vector2.ZERO
	return Vector2(d.y, -d.x).normalized()


## Returns the outline wound counter-clockwise, with the first point moved to
## (0, 0) so the result is positioned relative to its own start.
static func _normalise(outline: PackedVector2Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for p in outline:
		if ring.is_empty() or ring[ring.size() - 1].distance_squared_to(p) > EPSILON * EPSILON:
			ring.append(p)
	if ring.size() > 1 and ring[0].distance_squared_to(ring[ring.size() - 1]) < EPSILON * EPSILON:
		ring.remove_at(ring.size() - 1)
	if ring.size() < 3:
		return PackedVector2Array()
	if _signed_area(ring) < 0.0:
		ring.reverse()
	var out := PackedVector2Array()
	var origin := ring[0]
	for p in ring:
		out.append(p - origin)
	return out


static func _signed_area(ring: PackedVector2Array) -> float:
	var total := 0.0
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


static func _cap(
	data: MeshData, ring: PackedVector2Array, tris: PackedInt32Array, z: float, facing: float
) -> void:
	# Caps get their own vertices so they can carry a flat Z normal instead of
	# inheriting the side walls' averaged edge normals.
	var base := data.vertices.size()
	for i in ring.size():
		data.vertices.append(Vector3(ring[i].x, ring[i].y, z))
		data.normals.append(Vector3(0.0, 0.0, facing))
		data.uvs.append(Vector2(0.5, 0.5))

	for i in range(0, tris.size(), 3):
		var a := base + tris[i]
		var b := base + tris[i + 1]
		var c := base + tris[i + 2]
		if facing > 0.0:
			data.indices.append_array([c, b, a])
		else:
			data.indices.append_array([a, b, c])
