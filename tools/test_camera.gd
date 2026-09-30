extends SceneTree

## Headless checks for the orbit camera maths.
##
## The orbit state is tree-independent on purpose, so the framing, clamps and
## look-at behaviour are all assertable without a viewport or input events.
##
##     godot-headless --headless --script res://tools/test_camera.gd

var _failures := 0


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	var camera := OrbitCamera.new()

	camera.reset_view(Vector3.ZERO, 0.0, 34.0, 11.7)
	_check("camera sits at the orbit distance",
		is_equal_approx(camera.transform.origin.distance_to(Vector3.ZERO), 11.7),
		"dist=%.3f" % camera.transform.origin.distance_to(Vector3.ZERO))
	_check("camera looks at the target", _looks_at(camera, Vector3.ZERO),
		"forward=%s" % -camera.transform.basis.z)

	# Yaw zero sits behind +Z; yaw 90 swings the camera around to +X.
	camera.reset_view(Vector3.ZERO, 90.0, 34.0, 10.0)
	var expected_x := 10.0 * cos(deg_to_rad(34.0))
	_check("yaw 90 puts the camera on +X",
		is_equal_approx(camera.transform.origin.x, expected_x)
			and is_equal_approx(camera.transform.origin.z, 0.0),
		"pos=%s" % camera.transform.origin)
	_check("camera still looks at the target after yaw", _looks_at(camera, Vector3.ZERO), "")

	# Near top-down pitch puts the camera almost straight above.
	camera.reset_view(Vector3.ZERO, 0.0, 85.0, 10.0)
	_check("pitch 85 is nearly overhead",
		camera.transform.origin.y > 9.9 and absf(camera.transform.origin.z) < 1.0,
		"pos=%s" % camera.transform.origin)

	camera.pitch_degrees = 100.0
	_check("pitch clamps at the top",
		is_equal_approx(camera.pitch_degrees, camera.max_pitch_degrees),
		"pitch=%.1f" % camera.pitch_degrees)
	camera.pitch_degrees = -20.0
	_check("pitch clamps at the bottom",
		is_equal_approx(camera.pitch_degrees, camera.min_pitch_degrees),
		"pitch=%.1f" % camera.pitch_degrees)

	camera.distance = 500.0
	_check("distance clamps at the far end",
		is_equal_approx(camera.distance, camera.max_distance),
		"dist=%.1f" % camera.distance)
	camera.distance = 0.01
	_check("distance clamps at the near end",
		is_equal_approx(camera.distance, camera.min_distance),
		"dist=%.1f" % camera.distance)

	camera.reset_view(Vector3.ZERO, 0.0, 34.0, 10.0)
	camera.zoom_by(0.5)
	_check("zoom in halves the distance", is_equal_approx(camera.distance, 5.5),
		"dist=%.2f" % camera.distance)
	camera.zoom_by(0.1)
	_check("zoom in respects the near clamp", is_equal_approx(camera.distance, 5.5),
		"dist=%.2f" % camera.distance)

	camera.reset_view(Vector3.ZERO, 350.0, 34.0, 10.0)
	camera.orbit_by(20.0, 0.0)
	_check("yaw wraps past 360", camera.yaw_degrees < 20.0,
		"yaw=%.1f" % camera.yaw_degrees)

	# A non-origin target orbits around that point, not the world origin.
	camera.reset_view(Vector3(1.0, 0.0, 2.0), 0.0, 45.0, 8.0)
	_check("orbit centres on a moved target",
		is_equal_approx(camera.transform.origin.distance_to(Vector3(1.0, 0.0, 2.0)), 8.0),
		"pos=%s" % camera.transform.origin)
	_check("camera looks at a moved target", _looks_at(camera, Vector3(1.0, 0.0, 2.0)), "")

	camera.free()
	if _failures == 0:
		print("camera: all checks passed")
	else:
		printerr("camera: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## True when the camera's -Z axis points at the target.
func _looks_at(camera: OrbitCamera, target: Vector3) -> bool:
	var forward := -camera.transform.basis.z.normalized()
	var want := (target - camera.transform.origin).normalized()
	return forward.distance_squared_to(want) < 1e-6


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])
