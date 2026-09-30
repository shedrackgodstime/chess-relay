class_name BoardMaterials
extends RefCounted

## Wood materials for the board. Generated once and cached, because texture
## generation costs a few hundred milliseconds and rebuilds happen often while
## tuning the board constants.

static var _cache := {}


static func light_square() -> StandardMaterial3D:
	if not _cache.has("light"):
		_cache["light"] = _wood(
			Color(0.855, 0.800, 0.690), Color(0.620, 0.485, 0.340), 0.55, 11, 0.55
		)
	return _cache["light"]


static func dark_square() -> StandardMaterial3D:
	if not _cache.has("dark"):
		_cache["dark"] = _wood(
			Color(0.400, 0.290, 0.205), Color(0.210, 0.140, 0.095), 0.60, 29, 0.50
		)
	return _cache["dark"]


static func frame() -> StandardMaterial3D:
	if not _cache.has("frame"):
		_cache["frame"] = _wood(
			Color(0.255, 0.170, 0.115), Color(0.130, 0.085, 0.055), 0.65, 47, 0.32
		)
	return _cache["frame"]


static func _wood(
	base: Color, vein: Color, strength: float, seed_value: int, roughness: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Albedo colour multiplies the texture, so it stays at the base tone; the
	# texture carries the grain detail.
	material.albedo_color = base
	material.albedo_texture = TextureKit.wood(base, vein, strength, seed_value, Quality.texture_size())
	material.roughness = roughness
	material.metallic = 0.0
	# Subtle clearcoat-free sheen; specular carries the polish on mobile.
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return material


## Drops the cache, for tests or after changing the palette constants.
static func clear_cache() -> void:
	_cache.clear()
