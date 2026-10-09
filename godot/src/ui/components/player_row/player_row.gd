class_name PlayerRow
extends PanelContainer

## One person in the multiplayer hub's list.
##
## Extracted from the hub script because it is a concept of this game rather than
## part of that screen's behaviour, and the scene organization guidance is that
## such a thing should be a scene: visible in the editor, editable there, and
## reusable without knowing what called it. See
## docs/architecture/foundation_tightening.md, item 2.

## Raised when this row's own Invite control is pressed. The row does not know
## what inviting means; the hub does.
signal invite_pressed

@export var display_name := "Player"
@export var presence := ""
@export var is_recent := false
@export var ticket := ""

@onready var _avatar: Label = %Avatar
@onready var _name_label: Label = %Name
@onready var _presence_label: Label = %Presence
@onready var _recent_label: Label = %Recent
@onready var _invite_button: Button = %InviteButton


func _ready() -> void:
	_invite_button.pressed.connect(func() -> void: invite_pressed.emit())
	_apply()


## Shows a person. Called once when the row is made and again if it is reused, so
## both paths go through the same place rather than one setting text and the other
## setting fields.
func configure(name_text: String, presence_text: String, recent: bool, ticket_text: String = "") -> void:
	display_name = name_text
	presence = presence_text
	is_recent = recent
	ticket = ticket_text
	if is_node_ready():
		_apply()


## Turns the invite control off without hiding the row.
##
## Used while another flow is active: the row stays legible so the list does not
## jump, but an invite cannot be started halfway through something else.
func set_invite_enabled(enabled: bool) -> void:
	_invite_button.disabled = not enabled or ticket.is_empty()


## The initial, rather than the whole name, because the avatar is a circle and a
## circle holds one letter.
func _apply() -> void:
	_avatar.text = display_name.substr(0, 1).to_upper()
	_name_label.text = display_name
	_presence_label.text = "●  " + presence
	_recent_label.visible = is_recent
