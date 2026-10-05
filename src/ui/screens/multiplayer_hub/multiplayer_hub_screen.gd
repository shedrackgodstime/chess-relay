class_name MultiplayerHubScreen
extends Control

signal back_requested

const HEADER_SCENE: PackedScene = preload("res://src/ui/components/game_header/game_header.tscn")

const BG := Color(0.05, 0.04, 0.03, 1.0)
const TEXT := Color(1.0, 0.9, 0.72, 1.0)
const MUTED := Color(0.72, 0.66, 0.58, 1.0)

var _content: VBoxContainer
var _invite_grid: GridContainer
var _join_code: LineEdit
var _join_feedback: Label
var _player_list: ScrollContainer


func _ready() -> void:
	_build_screen()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()


func _build_screen() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var header := HEADER_SCENE.instantiate() as GameHeader
	header.center_text = "Play with People"
	header.show_network_indicator = false
	header.show_voice_control = false
	header.show_menu_button = false
	add_child(header)

	var back := Button.new()
	back.text = "‹   Back"
	back.position = Vector2(24, 22)
	back.custom_minimum_size = Vector2(112, 44)
	back.theme_type_variation = &"QuietButton"
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)

	var workspace := PanelContainer.new()
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.offset_left = 18
	workspace.offset_top = 98
	workspace.offset_right = -18
	workspace.offset_bottom = -22
	workspace.theme_type_variation = &"SetupWorkspace"
	add_child(workspace)

	var margins := MarginContainer.new()
	for side in [&"left", &"right"]:
		margins.add_theme_constant_override("margin_%s" % side, 24)
	margins.add_theme_constant_override("margin_top", 22)
	margins.add_theme_constant_override("margin_bottom", 22)
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(margins)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 18)
	margins.add_child(_content)

	_content.add_child(_build_profile_card())
	_content.add_child(_label("Invite", "SetupSectionTitle"))
	_invite_grid = GridContainer.new()
	_invite_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_grid.add_theme_constant_override("h_separation", 18)
	_invite_grid.add_theme_constant_override("v_separation", 18)
	_content.add_child(_invite_grid)
	_invite_grid.add_child(_build_create_card())
	_invite_grid.add_child(_build_join_card())

	_content.add_child(_build_players_section())


func _build_profile_card() -> PanelContainer:
	var card := _card()
	card.custom_minimum_size.y = 84
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(_label("Guest player", "SetupParticipantName"))
	identity.add_child(_label("Player profile saved on this device", "QuietLabel"))
	row.add_child(identity)
	var settings := Button.new()
	settings.text = "Discovery settings"
	settings.theme_type_variation = &"QuietButton"
	settings.pressed.connect(_show_discovery_settings)
	row.add_child(settings)
	return card


func _build_create_card() -> PanelContainer:
	var card := _card()
	card.custom_minimum_size.y = 184
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	column.add_child(_label("Create an invite", "SetupParticipantName"))
	column.add_child(_label("Make a code to share with someone.", "QuietLabel"))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(_action_button("Create invite", _on_create_invite))
	return card


func _build_join_card() -> PanelContainer:
	var card := _card()
	card.custom_minimum_size.y = 184
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	column.add_child(_label("Join with a code", "SetupParticipantName"))
	column.add_child(_label("Enter a code someone shared with you.", "QuietLabel"))
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "Invite code"
	_join_code.custom_minimum_size.y = 46
	_join_code.max_length = 20
	column.add_child(_join_code)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	_join_feedback = _label("", "QuietLabel")
	_join_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_join_feedback)
	action_row.add_child(_action_button("Join", _on_join_preview))
	column.add_child(action_row)
	return card


func _build_players_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 10)
	var heading := HBoxContainer.new()
	heading.add_child(_label("Players", "SetupParticipantName"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	heading.add_child(_label("Nearby  ·  Online", "QuietLabel"))
	section.add_child(heading)
	section.add_child(_label(
		"Nearby and online players appear here automatically. Recent players appear in this list when they’re online.",
		"QuietLabel"
	))
	_player_list = ScrollContainer.new()
	_player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_player_list.custom_minimum_size.y = 110
	_player_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(_player_list)
	var list_inset := MarginContainer.new()
	list_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_inset.add_theme_constant_override("margin_bottom", 10)
	_player_list.add_child(list_inset)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	list_inset.add_child(list)
	list.add_child(_build_mock_player_row("Ayo", "Nearby", false))
	list.add_child(_build_mock_player_row("KnightOwl", "Online", false))
	list.add_child(_build_mock_player_row("Kemi", "Nearby", true))
	list.add_child(_build_mock_player_row("RookRunner", "Online", true))
	return section


func _build_mock_player_row(player_name: String, presence: String, is_recent: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.theme_type_variation = &"PlayerListRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 52
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	row.add_child(layout)
	var avatar := Label.new()
	avatar.text = player_name.substr(0, 1).to_upper()
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.custom_minimum_size = Vector2(34, 34)
	avatar.add_theme_font_size_override("font_size", 18)
	avatar.add_theme_color_override("font_color", TEXT)
	layout.add_child(avatar)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_child(_label(player_name, "SetupParticipantName"))
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	details.add_child(_label("●  " + presence, "QuietLabel"))
	if is_recent:
		var recent := _label("Recent", "Caption")
		details.add_child(recent)
	identity.add_child(details)
	layout.add_child(identity)
	var invite := Button.new()
	invite.text = "Invite"
	invite.custom_minimum_size = Vector2(82, 34)
	invite.theme_type_variation = &"SetupOptionButton"
	invite.pressed.connect(_show_mock_invite.bind(player_name))
	layout.add_child(invite)
	return row


func _show_mock_invite(player_name: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Invite preview"
	dialog.dialog_text = "Invite %s to play.\n\nUI preview only." % player_name
	add_child(dialog)
	dialog.popup_centered(Vector2i(380, 180))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _show_discovery_settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Discovery settings"
	dialog.dialog_text = "Choose whether other players can discover you nearby or online."
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	var nearby := CheckButton.new()
	nearby.text = "Discoverable on this local network"
	nearby.button_pressed = true
	content.add_child(nearby)
	var online := CheckButton.new()
	online.text = "Discoverable by online players"
	content.add_child(online)
	dialog.add_child(content)
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 240))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_create_invite() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Invite preview"
	dialog.dialog_text = "RELAY-482\n\nUI preview only — no invite is active."
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 190))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_join_preview() -> void:
	if _join_code.text.strip_edges().is_empty():
		_join_feedback.text = "Enter an invite code."
		return
	_join_feedback.text = "UI preview only — joining isn’t active."


func _update_responsive_layout() -> void:
	if _invite_grid != null and is_instance_valid(_invite_grid):
		_invite_grid.columns = 1 if get_viewport_rect().size.x < 900.0 else 2


func _action_button(title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(100, 46)
	button.theme_type_variation = &"SetupPrimaryButton"
	button.pressed.connect(action)
	return button


func _card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return panel


func _label(value: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	if variation != &"":
		label.theme_type_variation = variation
	else:
		label.add_theme_color_override("font_color", TEXT)
	return label
