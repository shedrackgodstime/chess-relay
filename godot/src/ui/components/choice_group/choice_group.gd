class_name ChoiceGroup
extends VBoxContainer

signal selection_changed(choice: String, index: int)

@export var title := ""
@export var choices: PackedStringArray = []
@export_range(1, 6, 1) var columns := 3
@export var selected_index := 0

@onready var _title_label: Label = %Title
@onready var _options_grid: GridContainer = %Options

var _button_group := ButtonGroup.new()
var _buttons: Array[Button] = []
var _observer_label := ""


func _ready() -> void:
	_title_label.text = title
	_observer_label = ""
	_options_grid.columns = columns
	_build_options()


## Bulk configuration owned by code, not scene overrides: array-typed
## instance overrides do not survive export conversion (titles and other
## scalars do; PackedStringArrays vanish), so callers set choices here.
func configure(p_title: String, p_choices: PackedStringArray, p_columns: int, p_selected: int) -> void:
	title = p_title
	choices = p_choices
	columns = p_columns
	selected_index = p_selected
	for child in _options_grid.get_children():
		_options_grid.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_title_label.text = title
	_options_grid.columns = columns
	_build_options()


func set_selection(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	selected_index = index
	_buttons[index].button_pressed = true
	_refresh_button_labels()


func get_selected_choice() -> String:
	if selected_index < 0 or selected_index >= choices.size():
		return ""
	return choices[selected_index]


func set_enabled(enabled: bool) -> void:
	for button in _buttons:
		button.disabled = not enabled


## Makes a disabled network choice explicit instead of making it look broken.
## The selected value remains the normal choice; the check prefix is only
## presentation for the guest's host-owned snapshot.
func set_observer_label(label: String) -> void:
	_observer_label = label
	_title_label.text = title if label.is_empty() else "%s · %s" % [title, label]
	_refresh_button_labels()


func _refresh_button_labels() -> void:
	for index in range(_buttons.size()):
		_buttons[index].text = choices[index]
	if selected_index >= 0 and selected_index < _buttons.size() and not _observer_label.is_empty():
		_buttons[selected_index].text = "✓ %s" % choices[selected_index]


func _build_options() -> void:
	for index in range(choices.size()):
		var option_button := Button.new()
		option_button.text = choices[index]
		option_button.accessibility_name = choices[index]
		option_button.custom_minimum_size = Vector2(0, 46)
		option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_button.toggle_mode = true
		option_button.button_group = _button_group
		option_button.theme_type_variation = &"SetupOptionButton"
		option_button.pressed.connect(_on_option_pressed.bind(index))
		_options_grid.add_child(option_button)
		_buttons.append(option_button)
	if not _buttons.is_empty():
		set_selection(clampi(selected_index, 0, _buttons.size() - 1))


func _on_option_pressed(index: int) -> void:
	selected_index = index
	selection_changed.emit(choices[index], index)
