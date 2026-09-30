class_name Quality
extends RefCounted

## Parametric quality tiers: the cross-platform lever for procedural art.
##
## An imported mesh has a fixed triangle count; scaling it per device means
## maintaining several LOD assets or per-preset import settings. Generated
## geometry instead takes its resolution as a parameter, so one setting
## retunes the whole game: dense smooth pieces on desktop, light ones on a
## weak phone or web.
##
## The tier lives in ProjectSettings rather than in static variables so there
## is no initialisation order to get wrong: builders read it lazily whenever
## they generate, whether that happens in the editor, at startup, or after the
## player changes it in a settings screen. Anything that changes the tier at
## runtime must also drop the generated-material caches (BoardMaterials and
## PieceMaterials both have clear_cache) and rebuild the views, or the old
## resolution survives.
##
## Tests pin the MEDIUM tier explicitly so they stay deterministic.

enum Preset { LOW, MEDIUM, HIGH }

const SETTING := "chess_relay/quality_preset"


static func preset() -> int:
	return clampi(int(ProjectSettings.get_setting(SETTING, Preset.MEDIUM)), 0, 2)


static func set_preset(preset: int) -> void:
	ProjectSettings.set_setting(SETTING, clampi(preset, 0, 2))


## Radial segments for lathed pieces. LOW stays smooth enough because the
## profiles themselves are curve-sampled; the segments only facet around
## the axis.
static func mesh_segments() -> int:
	match preset():
		Preset.LOW:
			return 28
		Preset.HIGH:
			return 96
		_:
			return 48


## Edge length of generated textures in pixels. Halving it quarters the
## generation cost and VRAM.
static func texture_size() -> int:
	match preset():
		Preset.LOW:
			return 128
		Preset.HIGH:
			return 512
		_:
			return 256


static func preset_name(value: int = -1) -> String:
	match value if value >= 0 else preset():
		Preset.LOW:
			return "Low"
		Preset.HIGH:
			return "High"
		_:
			return "Medium"
