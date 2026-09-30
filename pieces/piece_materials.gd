class_name PieceMaterials
extends RefCounted

## Finished-wood materials for the pieces, generated once and cached.
## side is 0 for the light set, 1 for the dark set.

static var _cache := {}


static func for_side(side: int) -> StandardMaterial3D:
	var key := "light" if side == PieceMesh.LIGHT_SIDE else "dark"
	if not _cache.has(key):
		if side == PieceMesh.LIGHT_SIDE:
			_cache[key] = _finish(Color(0.910, 0.885, 0.830), 0.10, 101, 0.38, 0.0)
		else:
			_cache[key] = _finish(Color(0.205, 0.180, 0.168), 0.14, 202, 0.30, 0.15)
	return _cache[key]


static func _finish(
	base: Color, variation: float, seed_value: int, roughness: float, metallic: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = base
	material.albedo_texture = TextureKit.finish(base, variation, seed_value, Quality.texture_size())
	material.roughness = roughness
	material.metallic = metallic
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return material


## Drops the cache, for tests or after changing the palette constants.
static func clear_cache() -> void:
	_cache.clear()
