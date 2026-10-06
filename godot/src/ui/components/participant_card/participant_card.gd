class_name ParticipantCard
extends PanelContainer

@export var display_name := "Player"
@export var player_type := "PLAYER"
@export var detail := ""
@export var side := "White"
@export var is_opponent := false

@onready var _name_label: Label = %Name
@onready var _type_label: Label = %Type
@onready var _detail_label: Label = %Detail
@onready var _side_value: Label = %SideValue
@onready var _piece_icon: TextureRect = %PieceIcon


func _ready() -> void:
	_name_label.text = display_name
	_type_label.text = player_type
	_detail_label.text = detail
	_apply_side_style()
	# The opponent's piece is dimmed so it does not read as another white piece. It is a
	# theme variation rather than a modulate assignment, so the dimming travels with the
	# theme and is inspectable rather than only visible here.
	if is_opponent:
		_piece_icon.theme_type_variation = &"MutedPieceIcon"


func set_side(value: String) -> void:
	side = value
	_apply_side_style()


func configure(name_text: String, type_text: String, detail_text: String) -> void:
	display_name = name_text
	player_type = type_text
	detail = detail_text
	if is_node_ready():
		_name_label.text = display_name
		_type_label.text = player_type
		_detail_label.text = detail


func _apply_side_style() -> void:
	_side_value.text = side
	match side:
		"White":
			_side_value.theme_type_variation = &"SetupSideBadge"
		"Black":
			_side_value.theme_type_variation = &"SetupDarkSideBadge"
		_:
			_side_value.theme_type_variation = &"SetupNeutralSideBadge"
