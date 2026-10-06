extends RefCounted

## Shared 3D board palette. Materials are cached so every board instance uses
## the same resources and no per-square material copies are created.

static var _cache: Dictionary = {}

static func light_square() -> StandardMaterial3D:
	return _material_for("light", Color(0.76, 0.67, 0.52, 1.0), 0.62)

static func dark_square() -> StandardMaterial3D:
	return _material_for("dark", Color(0.28, 0.20, 0.14, 1.0), 0.68)

static func frame() -> StandardMaterial3D:
	return _material_for("frame", Color(0.12, 0.08, 0.05, 1.0), 0.58)

static func _material_for(key: String, colour: Color, roughness: float) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cache[key] = material
	return material

static func clear_cache() -> void:
	_cache.clear()
