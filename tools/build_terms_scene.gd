extends SceneTree

## Generates res://p2p_lobby.tscn: the scene the game opens on.
##
## Structure only. The screen and its shared frame build their own title and buttons
## same rule the board highlights follow, so the scene file never holds a copy of
## something that a change of wording would have to regenerate.
##
## Like the main scene builder this strips Godot's random per-node ids after saving,
## so regenerating an unchanged scene produces no diff at all. That matters most here:
## a regenerated scene that differs only by noise is the reason a real change goes
## unnoticed.

const OUTPUT := "res://terms.tscn"


func _init() -> void:
	var root := Control.new()
	root.name = "Terms"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_script(load("res://ui/terms_screen.gd"))

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


## Removes the random per-node IDs Godot writes on every save, so an unchanged scene
## regenerates byte for byte. See the same helper in build_main_scene.gd.
static func _strip_unique_ids() -> void:
	var source := FileAccess.get_file_as_string(OUTPUT)
	var pattern := RegEx.new()
	pattern.compile(" unique_id=\\d+")
	var normalized := pattern.sub(source, "", true)
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(normalized)
	file.close()