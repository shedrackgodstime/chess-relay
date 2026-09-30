class_name ProfileCurve
extends RefCounted

## Samples smooth curves through control points.
##
## Profiles authored as dense hand-plotted points are tedious to tune and carry
## invisible kinks where the spacing changes. Describing the same silhouette
## with a few control points and sampling a Catmull-Rom spline through them
## gives a smooth result that stays editable: moving one control point reshapes
## the curve predictably instead of requiring a dozen points to be nudged.
##
## The sampler clamps the X coordinate at zero so a lathe profile can never dip
## to a negative radius, which would fold the surface inside out.


## Samples a Catmull-Rom spline through points, with subdivisions samples per
## segment. Endpoints are duplicated so the curve passes exactly through the
## first and last control points.
static func sample(points: PackedVector2Array, subdivisions: int = 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() < 2 or subdivisions < 1:
		return PackedVector2Array(points)
	for i in points.size() - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, points.size() - 1)]
		var steps := subdivisions if i < points.size() - 2 else subdivisions + 1
		for s in steps:
			var t := float(s) / float(subdivisions)
			out.append(_catmull_rom(p0, p1, p2, p3, t))
	return out


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	var result := 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
	result.x = maxf(result.x, 0.0)
	return result


## Resamples a dense polyline to even spacing, which keeps lathe rings from
## bunching where the control points were close together. The point count is
## derived from the total length so the spacing is honoured along the whole
## curve, and the endpoints are always kept exactly.
static func even_spaced(points: PackedVector2Array, spacing: float) -> PackedVector2Array:
	if points.size() < 2 or spacing <= 0.0:
		return PackedVector2Array(points)

	var cumulative := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		cumulative.append(cumulative[i - 1] + points[i].distance_to(points[i - 1]))
	var total: float = cumulative[cumulative.size() - 1]
	if total <= 1e-9:
		return PackedVector2Array([points[0], points[points.size() - 1]])

	var steps := maxi(1, roundi(total / spacing))
	var out := PackedVector2Array()
	var leg := 0
	for k in steps + 1:
		var target := total * float(k) / float(steps)
		while leg < cumulative.size() - 2 and cumulative[leg + 1] < target:
			leg += 1
		var leg_start: float = cumulative[leg]
		var leg_end: float = cumulative[leg + 1]
		var t := 0.0 if leg_end <= leg_start else (target - leg_start) / (leg_end - leg_start)
		out.append(points[leg].lerp(points[leg + 1], clampf(t, 0.0, 1.0)))
	return out
