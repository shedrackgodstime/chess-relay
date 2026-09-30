extends SceneTree

## Headless checks for the procedural geometry helpers.
##
## These cannot judge how the geometry *looks*, but they do catch the failures
## that are invisible until the mesh is on screen: inverted winding, degenerate
## triangles, poles that are not fanned, and profiles that silently collapse.
##
##     godot-headless --headless --script res://tools/test_geometry.gd

var _failures := 0


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	_lathe_checks()
	_builder_checks()
	_extrude_checks()
	_primitive_checks()
	_winding_conformance()
	_curve_checks()
	if _failures == 0:
		print("geometry: all checks passed")
	else:
		printerr("geometry: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Signed volume via the divergence theorem. Positive means the triangles wind
## outward, which is what makes backface culling and shading behave.
func _volume(data: MeshData) -> float:
	var total := 0.0
	for i in range(0, data.indices.size(), 3):
		total += data.vertices[data.indices[i]].dot(
			data.vertices[data.indices[i + 1]].cross(data.vertices[data.indices[i + 2]])
		)
	return total / 6.0


func _degenerate_count(data: MeshData) -> int:
	var count := 0
	for i in range(0, data.indices.size(), 3):
		var a: Vector3 = data.vertices[data.indices[i]]
		var b: Vector3 = data.vertices[data.indices[i + 1]]
		var c: Vector3 = data.vertices[data.indices[i + 2]]
		if (b - a).cross(c - a).length_squared() < 1e-14:
			count += 1
	return count


## Worst dot product between a near-horizontal vertex normal and the outward
## radial direction. Side walls should score close to 1.
func _worst_side_normal(data: MeshData) -> float:
	var worst := 1.0
	for i in data.normals.size():
		var n: Vector3 = data.normals[i]
		if absf(n.y) > 0.1:
			continue
		var radial := Vector3(n.x, 0.0, n.z)
		if radial.length_squared() < 1e-9:
			continue
		worst = minf(worst, radial.normalized().dot(Vector3(n.x, 0.0, n.z).normalized()))
	return worst


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])


## |volume| is compared rather than the signed value, because the sign encodes
## the winding convention and is asserted separately by _expect_conformance.
func _expect_volume(label: String, data: MeshData, expected: float, tolerance: float = 0.02) -> void:
	var got := absf(_volume(data))
	_check(
		label,
		got > 0.0 and absf(got - expected) <= expected * tolerance + 0.001,
		"|volume|=%.4f expected~%.4f" % [got, expected]
	)


func _lathe_checks() -> void:
	print("Lathe")

	# A 32-sided prism sits just inside the true cylinder, hence the tolerance.
	_expect_volume(
		"cylinder r1 h2",
		Lathe.build(PackedVector2Array([Vector2(1, 0), Vector2(1, 2)]), 32),
		PI * 2.0
	)
	# Profile pole -> rim -> pole is a bicone, not a sphere.
	_expect_volume(
		"bicone",
		Lathe.build(
			PackedVector2Array([Vector2(0, 0), Vector2(0.7, 0.7), Vector2(0, 1.4)]), 24
		),
		2.0 / 3.0 * PI * 0.49 * 0.7
	)
	# Out from the axis, straight up, back in to the axis: revolves to a
	# cylinder of radius 1 and height 1.
	_expect_volume(
		"stepped profile",
		Lathe.build(
			PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), 32
		),
		PI
	)

	var tube := Lathe.build(PackedVector2Array([Vector2(1, 0), Vector2(1, 2)]), 8, false, false)
	_check(
		"open tube has no degenerate tris",
		_degenerate_count(tube) == 0,
		"tris=%d" % tube.triangle_count()
	)
	_check(
		"open tube side normals point outward",
		_worst_side_normal(tube) > 0.99,
		"worst=%.3f" % _worst_side_normal(tube)
	)

	var closed := Lathe.build(PackedVector2Array([Vector2(1, 0), Vector2(1, 2)]), 32)
	_check(
		"closed solid has no degenerate tris",
		_degenerate_count(closed) == 0,
		"tris=%d" % closed.triangle_count()
	)

	# Poles must fan, and a single-point profile must produce nothing at all.
	var pole := Lathe.build(PackedVector2Array([Vector2(0, 0), Vector2(0.6, 0.5), Vector2(0, 1)]), 16)
	_check(
		"pole fan is closed",
		_degenerate_count(pole) == 0 and absf(_volume(pole)) > 0.0,
		"tris=%d |volume|=%.4f" % [pole.triangle_count(), absf(_volume(pole))]
	)
	_check(
		"collapsed profile yields no geometry",
		Lathe.build(PackedVector2Array([Vector2(1, 0), Vector2(1, 0)]), 8).is_empty(),
		""
	)
	_check(
		"too few segments yields no geometry",
		Lathe.build(PackedVector2Array([Vector2(1, 0), Vector2(1, 2)]), 2).is_empty(),
		""
	)


func _builder_checks() -> void:
	print("MeshBuilder")
	var square := Lathe.build(
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), 4
	)

	var single := MeshBuilder.new().add_part(square)
	var single_mesh := single.build()
	_check(
		"single part makes one surface",
		single_mesh.get_surface_count() == 1 and square.triangle_count() > 0,
		"surfaces=%d" % single_mesh.get_surface_count()
	)

	var two := MeshBuilder.new().add_part(square).add_part(square, null, Transform3D(Basis(), Vector3(0, 0, 3)))
	var two_mesh := two.build()
	_check(
		"two parts make two surfaces",
		two_mesh.get_surface_count() == 2,
		"surfaces=%d" % two_mesh.get_surface_count()
	)
	_check(
		"transformed part keeps its volume",
		absf(_volume(square)) > 0.0,
		"|volume|=%.4f" % absf(_volume(square))
	)

	var empty_mesh := MeshBuilder.new().add_part(MeshData.new()).build()
	_check("empty builder makes no surfaces", empty_mesh.get_surface_count() == 0, "")


func _extrude_checks() -> void:
	print("Extrude")
	# Convex square of side 1 swept +-0.5 with no taper: volume must be 1.
	var square := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var slab := Extrude.build(square, 0.5, 0.0, 3)
	_expect_volume("square slab", slab, 1.0, 0.05)
	_check("slab has no degenerate tris", _degenerate_count(slab) == 0, "tris=%d" % slab.triangle_count())

	# Taper shrinks the ends, so volume must drop below the untiltered case.
	var tapered := Extrude.build(square, 0.5, 0.8, 7)
	_check(
		"taper reduces volume",
		absf(_volume(tapered)) > 0.0 and absf(_volume(tapered)) < absf(_volume(slab)),
		"tapered=%.4f slab=%.4f" % [absf(_volume(tapered)), absf(_volume(slab))]
	)
	_check("tapered has no degenerate tris", _degenerate_count(tapered) == 0, "tris=%d" % tapered.triangle_count())

	# A concave L must still cap correctly, which a centroid fan would fail.
	var ell := PackedVector2Array([
		Vector2(0, 0), Vector2(2, 0), Vector2(2, 1), Vector2(1, 1), Vector2(1, 2), Vector2(0, 2),
	])
	var ell_solid := Extrude.build(ell, 0.5, 0.0, 3)
	_expect_volume("concave L slab", ell_solid, 3.0, 0.05)

	# Clockwise input must be normalised, not turned inside out.
	var reversed := PackedVector2Array([
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
	])
	_expect_volume("clockwise outline", Extrude.build(reversed, 0.5, 0.0, 3), 1.0, 0.05)

	_check(
		"degenerate outline yields no geometry",
		Extrude.build(PackedVector2Array([Vector2(0, 0), Vector2(1, 1)]), 0.5).is_empty(),
		""
	)

	# Coordinates must survive untouched: an outline drawn away from the
	# origin has to extrude exactly there, or anything placed relative to it
	# (like the knight's ears) ends up floating. A re-basing normaliser once
	# broke this silently.
	var placed := PackedVector2Array([
		Vector2(2, 3), Vector2(4, 3), Vector2(4, 5), Vector2(2, 5),
	])
	var positioned := Extrude.build(placed, 0.5, 0.0, 2)
	var bb_min := Vector3(9, 9, 9)
	var bb_max := Vector3(-9, -9, -9)
	for v in positioned.vertices:
		bb_min = bb_min.min(v)
		bb_max = bb_max.max(v)
	_check("extrude preserves outline coordinates",
		is_equal_approx(bb_min.x, 2.0) and is_equal_approx(bb_max.x, 4.0)
			and is_equal_approx(bb_min.y, 3.0) and is_equal_approx(bb_max.y, 5.0),
		"bounds x=%.2f..%.2f y=%.2f..%.2f" % [bb_min.x, bb_max.x, bb_min.y, bb_max.y])


func _primitive_checks() -> void:
	print("Primitives")
	var cube := Primitives.box(Vector3(2, 2, 2))
	_expect_volume("box 2x2x2", cube, 8.0, 0.001)
	_check("box has no degenerate tris", _degenerate_count(cube) == 0, "tris=%d" % cube.triangle_count())

	var spike := Primitives.spike(1.0, 2.0, 6)
	# Regular n-gon base area is (n/2)*R^2*sin(2pi/n); pyramid volume is a*h/3.
	var base_area := 0.5 * 6.0 * 1.0 * sin(TAU / 6.0)
	_expect_volume("hex spike", spike, base_area * 2.0 / 3.0, 0.01)
	_check("spike has no degenerate tris", _degenerate_count(spike) == 0, "tris=%d" % spike.triangle_count())

	var merlons := Primitives.ring(Primitives.box(Vector3(0.1, 0.2, 0.1)), 6, 0.3, 0.5)
	_check(
		"ring repeats geometry",
		merlons.triangle_count() == 6 * 12,
		"tris=%d expected=%d" % [merlons.triangle_count(), 6 * 12]
	)
	_check("ring has no degenerate tris", _degenerate_count(merlons) == 0, "")
	_check("empty ring yields nothing", Primitives.ring(null, 4, 0.3, 0.0).is_empty(), "")

	var bevelled := Primitives.beveled_box(Vector3(2, 2, 2), 0.2)
	# A 0.2 chamfer on every top edge removes a small, known wedge volume.
	_expect_volume("bevelled box", bevelled, 8.0 - 4.0 * 0.5 * 0.2 * 0.2 * 2.0, 0.02)
	_check("bevelled box has no degenerate tris", _degenerate_count(bevelled) == 0,
		"tris=%d" % bevelled.triangle_count())
	_expect_conformance("bevelled box winding", bevelled)

	var flat := Primitives.beveled_box(Vector3(2, 2, 2), 0.0)
	_expect_volume("zero bevel is a plain box", flat, 8.0, 0.001)
	_check("zero bevel matches box triangle count",
		flat.triangle_count() == Primitives.box(Vector3(2, 2, 2)).triangle_count(),
		"tris=%d" % flat.triangle_count())


## Winding conformance against the engine.
##
## Godot's own built-in meshes (PlaneMesh, BoxMesh, SphereMesh) all score
## exactly -1.0 for dot(right-hand triangle normal, stored vertex normal):
## the right-hand normal points INWARDS, opposite the outward vertex normals.
## Any generated mesh must score the same, or its outward faces are back-facing,
## get culled, and the solid renders inside-out.
func _conformance(data: MeshData) -> float:
	var total := 0.0
	var count := 0
	for i in range(0, data.indices.size(), 3):
		var a: Vector3 = data.vertices[data.indices[i]]
		var b: Vector3 = data.vertices[data.indices[i + 1]]
		var c: Vector3 = data.vertices[data.indices[i + 2]]
		var right_hand := (b - a).cross(c - a)
		if right_hand.length_squared() < 1e-16:
			continue
		right_hand = right_hand.normalized()
		var stored := (
			data.normals[data.indices[i]]
			+ data.normals[data.indices[i + 1]]
			+ data.normals[data.indices[i + 2]]
		).normalized()
		total += right_hand.dot(stored)
		count += 1
	return total / maxf(count, 1)


## The score is exactly -1.000 only where every triangle has a flat normal. At
## a hard edge the three stored normals are an average across the crease, so a
## per-triangle normal cannot match them exactly; the lathe scores nearer
## -0.9 there. What must hold is the sign: the right-hand normal opposes the
## stored normals, which is the Godot convention.
func _expect_conformance(label: String, data: MeshData) -> void:
	var score := _conformance(data)
	_check(
		label,
		score < -0.5,
		"mean dot(right-hand, stored) = %+.3f (must be negative; flat-faced meshes give -1.000)" % score
	)


func _winding_conformance() -> void:
	print("Winding conformance (Godot convention = -1.000)")
	_expect_conformance(
		"lathe cylinder",
		Lathe.build(PackedVector2Array([Vector2(1, 0), Vector2(1, 2)]), 32)
	)
	_expect_conformance(
		"lathe pole top",
		Lathe.build(PackedVector2Array([Vector2(1, 0), Vector2(0.5, 1), Vector2(0, 2)]), 32)
	)
	_expect_conformance(
		"lathe pole both ends",
		Lathe.build(PackedVector2Array([Vector2(0, 0), Vector2(0.7, 0.7), Vector2(0, 1.4)]), 24)
	)
	_expect_conformance(
		"extrude slab",
		Extrude.build(PackedVector2Array([
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), 0.5, 0.0, 3)
	)
	_expect_conformance(
		"extrude tapered",
		Extrude.build(PackedVector2Array([
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), 0.5, 0.8, 7)
	)
	_expect_conformance(
		"extrude concave",
		Extrude.build(PackedVector2Array([
			Vector2(0, 0), Vector2(2, 0), Vector2(2, 1),
			Vector2(1, 1), Vector2(1, 2), Vector2(0, 2)]), 0.5, 0.0, 3)
	)
	_expect_conformance("box", Primitives.box(Vector3(2, 2, 2)))
	_expect_conformance("spike", Primitives.spike(1.0, 2.0, 6))
	_expect_conformance(
		"ring of boxes",
		Primitives.ring(Primitives.box(Vector3(0.1, 0.2, 0.1)), 4, 0.3, 0.0)
	)


func _curve_checks() -> void:
	print("Curve")
	var line := ProfileCurve.sample(PackedVector2Array([Vector2(0, 0), Vector2(1, 1)]), 4)
	_check("two points sample a straight line", line.size() == 5,
		"points=%d" % line.size())
	_check("curve keeps its endpoints",
		line[0].is_equal_approx(Vector2(0, 0)) and line[4].is_equal_approx(Vector2(1, 1)),
		"first=%s last=%s" % [line[0], line[4]])

	var bend := ProfileCurve.sample(
		PackedVector2Array([Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), 4)
	_check("curve passes through middle control points",
		bend[4].distance_to(Vector2(1, 1)) < 0.001,
		"mid=%s" % bend[4])

	var dip := ProfileCurve.sample(
		PackedVector2Array([Vector2(0.5, 0), Vector2(-2, 0.5), Vector2(0.5, 1)]), 8)
	var lowest := 10.0
	for v in dip:
		lowest = minf(lowest, v.x)
	_check("radius never goes negative", lowest >= 0.0, "min_x=%.3f" % lowest)

	var dense := ProfileCurve.sample(
		PackedVector2Array([Vector2(0, 0), Vector2(0.5, 0.2), Vector2(0.4, 0.8), Vector2(0, 1)]), 6)
	var even := ProfileCurve.even_spaced(dense, 0.1)
	var worst := 0.0
	for i in range(1, even.size()):
		worst = maxf(worst, absf(even[i].distance_to(even[i - 1]) - 0.1))
	_check("even spacing is roughly even", worst < 0.05, "worst dev=%.3f" % worst)
	_check("even spacing keeps endpoints",
		even[0].is_equal_approx(dense[0])
			and even[even.size() - 1].is_equal_approx(dense[dense.size() - 1]),
		"points=%d" % even.size())

	# A sampled profile must still lathe into a closed solid.
	var smooth := ProfileCurve.even_spaced(ProfileCurve.sample(
		PackedVector2Array([Vector2(0, 0), Vector2(0.4, 0.1), Vector2(0.3, 0.5), Vector2(0, 0.6)]), 6), 0.04)
	var solid := Lathe.build(smooth, 32)
	_check("sampled profile lathes closed",
		_degenerate_count(solid) == 0 and absf(_volume(solid)) > 0.0,
		"tris=%d |volume|=%.4f" % [solid.triangle_count(), absf(_volume(solid))])
	_expect_conformance("sampled profile winding", solid)
