class_name HeaderMenu
extends Control
## Single-source chrome for every game-header menu.
##
## Setup and game screens used to build their own: a centered modal with
## backdrop and ESC handling on one side, a bare top-right dropdown with
## neither (and no toggle, so repeats stacked) on the other. Both now pass
## item content here; this file owns layer, backdrop, card, buttons,
## outside-click and ESC dismissal, and the shared leave-confirm shape.
## Screens keep item labels, order, and what each action does.

const CARD_MIN_WIDTH := 300.0
const ITEM_HEIGHT := 48.0
const ITEM_SEPARATION := 8
const CONFIRM_SIZE := Vector2i(460, 220)

var _actions_box: VBoxContainer = null


## Opens the menu over `host`, or closes it when one is already open there.
## Labels and actions run in parallel; the menu closes itself before the
## action runs. Returns the open menu, or null when toggled shut.
static func toggle_in(
	host: Control,
	labels: PackedStringArray,
	actions: Array[Callable]
) -> HeaderMenu:
	var open := find_in(host)
	if open != null:
		open.close()
		return null
	return open_in(host, labels, actions)


## Opens the menu over `host`. Returns the existing one when already open.
static func open_in(
	host: Control,
	labels: PackedStringArray,
	actions: Array[Callable]
) -> HeaderMenu:
	var open := find_in(host)
	if open != null:
		return open
	var menu := HeaderMenu.new()
	menu.name = &"HeaderMenu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(menu)
	menu._build(labels, actions)
	return menu


## Closes the menu over `host`, if any.
static func close_in(host: Control) -> void:
	var open := find_in(host)
	if open != null:
		open.close()


static func is_open_in(host: Control) -> bool:
	return find_in(host) != null


static func find_in(host: Control) -> HeaderMenu:
	for child in host.get_children():
		if child is HeaderMenu:
			return child as HeaderMenu
	return null


## Shared confirm shape for destructive header-menu actions (leaving).
## The menu is already gone by the time an action runs, so this only ever
## stacks over the screen itself.
static func confirm_in(
	host: Control,
	title: String,
	text: String,
	ok_text: String,
	cancel_text: String,
	on_ok: Callable
) -> ConfirmationDialog:
	var confirmation := ConfirmationDialog.new()
	confirmation.theme_type_variation = &"ModalDialog"
	confirmation.title = title
	confirmation.dialog_text = text
	confirmation.dialog_autowrap = true
	confirmation.ok_button_text = ok_text
	confirmation.cancel_button_text = cancel_text
	confirmation.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirmation.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ok_button := confirmation.get_ok_button()
	ok_button.accessibility_name = ok_text
	ok_button.theme_type_variation = &"ModalDangerButton"
	var cancel_button := confirmation.get_cancel_button()
	cancel_button.accessibility_name = cancel_text
	cancel_button.theme_type_variation = &"ModalSecondaryButton"
	confirmation.confirmed.connect(func() -> void:
		on_ok.call()
		confirmation.queue_free()
	)
	confirmation.canceled.connect(confirmation.queue_free)
	host.add_child(confirmation)
	confirmation.popup_centered(CONFIRM_SIZE)
	return confirmation


## Button for an item label, for tests and owners that need direct access.
func find_item(label: String) -> Button:
	for button in _item_buttons():
		if button.text == label:
			return button
	return null


func close() -> void:
	# Detach now so is_open_in flips in the same frame; the free itself
	# stays deferred. Tests and toggles read presence, not queue state.
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


func _build(labels: PackedStringArray, actions: Array[Callable]) -> void:
	# A Panel rather than a ColorRect so the wash is a theme item. A ColorRect
	# takes its colour from the node and nowhere else, which would put one more
	# value in this script that a re-theme could not reach.
	var backdrop := Panel.new()
	backdrop.theme_type_variation = &"ModalBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var menu_card := PanelContainer.new()
	menu_card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0.0)
	menu_card.theme_type_variation = &"Card"
	menu_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(menu_card)
	_actions_box = VBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", ITEM_SEPARATION)
	menu_card.add_child(_actions_box)
	for index in range(labels.size()):
		if index < actions.size():
			_actions_box.add_child(_make_item(labels[index], actions[index]))


func _make_item(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.accessibility_name = label
	button.custom_minimum_size.y = ITEM_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = &"QuietButton"
	button.pressed.connect(func() -> void:
		close()
		action.call()
	)
	return button


func _on_backdrop_input(event: InputEvent) -> void:
	if _is_dismiss_press(event):
		close()
		get_viewport().set_input_as_handled()


func _item_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	if _actions_box == null:
		return buttons
	for child in _actions_box.get_children():
		if child is Button:
			buttons.append(child as Button)
	return buttons


## Left-click or touch press. Mirrors ChessBoardView.is_selecting_press without
## taking a board-layer dependency from a header component.
static func _is_dismiss_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return button.pressed and button.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false
