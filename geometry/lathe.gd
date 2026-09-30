class_name Lathe
extends RefCounted

## Revolves a 2D profile around the Y axis to produce a solid of revolution.
##
## Profile points are Vector2(radius, height) ordered bottom to top. A point
## whose radius is zero becomes a pole and is fanned rather than revolved.
## Surface normals come from the profile tangent, so the result shades smoothly
## around the axis without needing smoothing groups or generated normals.
##
## WINDING: Godot's built-in meshes wind their triangles so the right-hand-rule
## normal points opposite to the stored vertex normals (verified: PlaneMesh,
## BoxMesh, SphereMesh and CylinderMesh all score -1.000 for
## dot(right-hand, stored)). Front faces are the ones that survive backface
## culling, so this file reproduces that convention. Getting it backwards makes
## every solid render inside-out and look transparent. tools/test_geometry.gd
## asserts conformance against that measured value.

const EPSILON := 0.00001
const DEFAULT_SEGMENTS := 48


static func build(
	profile: PackedVector2Array,
	segments: int = DEFAULT_SEGMENTS,
	cap_bottom: bool = true,
	cap_top: bool = true
) -> MeshData:
	var data := MeshData.new()
	var points := _dedupe(profile)
	if points.size() < 2 or segments < 3:
		return data

	# Outward 2D normal per profile point, from the central-difference tangent.
	# For a profile running bottom to top this points away from the axis.
	var profile_normals := PackedVector2Array()
	for i in points.size():
		var prev: Vector2 = points[maxi(i - 1, 0)]
		var next: Vector2 = points[mini(i + 1, points.size() - 1)]
		var tangent := next - prev
		if tangent.length_squared() < EPSILON * EPSILON:
			tangent = Vector2.UP
		profile_normals.append(Vector2(tangent.y, -tangent.x).normalized())

	# Ring offsets must be computed before emitting, because the stitch pass
	# needs to know where each ring's vertices land.
	var ring_starts := PackedInt32Array()
	var ring_counts := PackedInt32Array()
	var running := 0
	for i in points.size():
		ring_starts.append(running)
		var count := 1 if points[i].x <= EPSILON else segments
		ring_counts.append(count)
		running += count

	var v_coords := _arc_length_coords(points)
	for i in points.size():
		var p: Vector2 = points[i]
		var n2: Vector2 = profile_normals[i]
		if ring_counts[i] == 1:
			data.vertices.append(Vector3(0.0, p.y, 0.0))
			data.normals.append(Vector3(0.0, n2.y if absf(n2.y) > EPSILON else -1.0, 0.0))
			data.uvs.append(Vector2(0.5, v_coords[i]))
		else:
			for s in segments:
				var angle := TAU * s / segments
				var cos_a := cos(angle)
				var sin_a := sin(angle)
				data.vertices.append(Vector3(p.x * cos_a, p.y, p.x * sin_a))
				data.normals.append(Vector3(n2.x * cos_a, n2.y, n2.x * sin_a).normalized())
				data.uvs.append(Vector2(float(s) / float(segments), v_coords[i]))

	for i in points.size() - 1:
		_stitch(data, ring_starts[i], ring_counts[i], ring_starts[i + 1], ring_counts[i + 1])

	if cap_bottom and ring_counts[0] > 1:
		_cap(data, ring_starts[0], segments, points[0].y, -1.0)
	if cap_top and ring_counts[points.size() - 1] > 1:
		var last := points.size() - 1
		_cap(data, ring_starts[last], segments, points[last].y, 1.0)
	return data


static func _stitch(
	data: MeshData, a_start: int, a_count: int, b_start: int, b_count: int
) -> void:
	if a_count == 1 and b_count == 1:
		return

	if a_count == 1:
		# Pole below: fan up to the next full ring.
		for s in b_count:
			data.indices.append_array([a_start, b_start + (s + 1) % b_count, b_start + s])
		return
	if b_count == 1:
		# Pole above: fan down from this ring.
		for s in a_count:
			data.indices.append_array([a_start + s, a_start + (s + 1) % a_count, b_start])
		return

	for s in a_count:
		var s_next := (s + 1) % a_count
		data.indices.append_array([
			a_start + s,
			b_start + s_next,
			b_start + s,
			a_start + s,
			a_start + s_next,
			b_start + s_next,
		])


static func _cap(
	data: MeshData, ring_start: int, count: int, height: float, facing: float
) -> void:
	var centre := data.vertices.size()
	data.vertices.append(Vector3(0.0, height, 0.0))
	data.normals.append(Vector3(0.0, facing, 0.0))
	data.uvs.append(Vector2(0.5, 0.5))
	for s in count:
		var s_next := (s + 1) % count
		if facing > 0.0:
			data.indices.append_array([centre, ring_start + s, ring_start + s_next])
		else:
			data.indices.append_array([centre, ring_start + s_next, ring_start + s])


static func _dedupe(profile: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in profile:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > EPSILON * EPSILON:
			out.append(p)
	return out


## Normalises cumulative profile length into 0..1 for use as a V coordinate.
static func _arc_length_coords(points: PackedVector2Array) -> PackedFloat32Array:
	var lengths := PackedFloat32Array()
	var total := 0.0
	for i in points.size():
		if i > 0:
			total += points[i].distance_to(points[i - 1])
		lengths.append(total)
	if total <= EPSILON:
		total = 1.0
	for i in lengths.size():
		lengths[i] = lengths[i] / total
	return lengths
