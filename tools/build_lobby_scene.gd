extends SceneTree

## Generates res://lobby.tscn: where a match is set up.
##
## Structure only, like the home scene. The screen builds its own rows and buttons in
## _ready so the scene file never holds a copy of something a change of wording would
## have to regenerate.
##
## The random per-node ids are stripped after saving, so regenerating an unchanged
## scene produces no diff at all.

const OUTPUT := "res://lobby.tscn"


func _init() -> void:
	var root := Control.new()
	root.name = "Lobby"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_script(load("res://ui/lobby_screen.gd"))

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		printerr("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUTPUT)
	if err != OK:
		printerr("save failed: %d" % err)
		quit(1)
		return
	_strip_unique_ids()

	print("Wrote %s" % OUTPUT)
	quit(0)


## Removes the random per-node IDs Godot writes on every save. See build_home_scene.gd.
static func _strip_unique_ids() -> void:
	var source := FileAccess.get_file_as_string(OUTPUT)
	var pattern := RegEx.new()
	pattern.compile(" unique_id=\\d+")
	var normalized := pattern.sub(source, "", true)
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(normalized)
	file.close()