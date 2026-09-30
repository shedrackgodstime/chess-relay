extends SceneTree

## Regenerates .godot/global_script_class_cache.cfg from the class_name
## declarations found in the project.
##
## The editor normally writes this file, but it only does so as part of a full
## filesystem scan. Scripts run with --script cannot trigger that scan, so
## global class names would not resolve and every cross-file type reference
## would fail to parse. Run this after adding or renaming a class_name:
##
##     godot-headless --headless --script res://tools/build_class_cache.gd
##
## It is a development tool and has no role in the shipped game.

const CACHE_PATH := "res://.godot/global_script_class_cache.cfg"


func _init() -> void:
	var entries := _collect("res://")
	if entries.is_empty():
		push_error("No class_name declarations found; refusing to blank the cache.")
		quit(1)
		return

	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s: %s" % [CACHE_PATH, error_string(FileAccess.get_open_error())])
		quit(1)
		return

	var chunks: PackedStringArray = []
	for entry in entries:
		var template := (
			'{\n"base": &"%s",\n"class": &"%s",\n"icon": "",\n"is_abstract": false,\n'
			+ '"is_tool": %s,\n"language": &"GDScript",\n"path": "%s"\n}'
		)
		chunks.append(
			template % [entry["base"], entry["class"], str(entry["tool"]).to_lower(), entry["path"]]
		)
	file.store_string("list=[%s]\n" % ", ".join(chunks))
	file.close()

	print("Wrote %d global classes to the cache:" % entries.size())
	for entry in entries:
		print("  %s (%s) <- %s" % [entry["class"], entry["base"], entry["path"]])
	quit(0)


func _collect(dir_path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := dir_path.path_join(name)
		if dir.current_is_dir():
			# The .godot folder holds generated files, not sources.
			if not name.begins_with("."):
				found.append_array(_collect(path))
		elif name.ends_with(".gd") and path != get_script().resource_path:
			var entry := _describe(path)
			if not entry.is_empty():
				found.append(entry)
		name = dir.get_next()
	dir.list_dir_end()
	return found


func _describe(path: String) -> Dictionary:
	var source := FileAccess.get_file_as_string(path)
	var class_name_match := RegEx.new()
	class_name_match.compile("(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var found := class_name_match.search(source)
	if found == null:
		return {}

	var script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
	var base := "RefCounted"
	var is_tool := false
	if script != null:
		base = script.get_instance_base_type()
		is_tool = script.is_tool()
	return {
		"class": found.get_string(1),
		"base": base if base != "" else "RefCounted",
		"tool": is_tool,
		"path": path,
	}
