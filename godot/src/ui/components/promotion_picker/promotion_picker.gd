class_name PromotionPicker
extends Control
## Asks which piece a pawn becomes, showing the real pieces.
##
## Shown instead of applying the move: a promotion cannot be tapped as two
## squares, and applying first would animate the wrong piece. Cancelling is
## not a dead end: it falls back to a queen, so the player can always
## finish the move.
##
## The previews are baked snapshots of the actual catalog meshes
## (`tests/bake_previews.gd`), shown as plain textures. Runtime GPU capture
## was tried first and abandoned: tile-based mobile GPUs hand back blank
## frames with no error, which the content check could not distinguish from
## slow first renders. Baked art is identical on every device and costs
## nothing at runtime.
##
## Built in code: no subscene instances, no overrides, nothing for export
## conversion to drop. Presentation only: nothing here decides legality;
## the screen opens it solely for legal targets.
##
## Emitted with "queen", "rook", "bishop" or "knight".

signal chosen(piece: String)

const PIECES: Array[String] = ["Queen", "Rook", "Bishop", "Knight"]
const SUFFIXES := {"queen": "q", "rook": "r", "bishop": "b", "knight": "n"}
const PREVIEW_QUEEN_WHITE: Texture2D = preload("res://assets/chess/pieces/preview_queen_white.png")
const PREVIEW_ROOK_WHITE: Texture2D = preload("res://assets/chess/pieces/preview_rook_white.png")
const PREVIEW_BISHOP_WHITE: Texture2D = preload("res://assets/chess/pieces/preview_bishop_white.png")
const PREVIEW_KNIGHT_WHITE: Texture2D = preload("res://assets/chess/pieces/preview_knight_white.png")
const PREVIEW_QUEEN_BLACK: Texture2D = preload("res://assets/chess/pieces/preview_queen_black.png")
const PREVIEW_ROOK_BLACK: Texture2D = preload("res://assets/chess/pieces/preview_rook_black.png")
const PREVIEW_BISHOP_BLACK: Texture2D = preload("res://assets/chess/pieces/preview_bishop_black.png")
const PREVIEW_KNIGHT_BLACK: Texture2D = preload("res://assets/chess/pieces/preview_knight_black.png")
const OPTION_SIZE := Vector2(96.0, 112.0)
const PREVIEW_SIZE := Vector2(80.0, 84.0)


static func suffix_for(piece: String) -> String:
	return SUFFIXES.get(piece, "q")


var _options: HBoxContainer
var _title: Label
var _side := "white"


func _ready() -> void:
	_build()
	visible = false


## Shows the picker for a pawn of the given side ("white"/"black").
func open(side: String) -> void:
	_side = side
	_rebuild_options()
	_title.text = "%s pawn promotes to" % side.capitalize()
	visible = true


func close() -> void:
	visible = false


## How many choices are on offer, so tests assert population, not visibility.
func option_count() -> int:
	return _options.get_child_count() if _options != null else 0


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.018, 0.016, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"Card"
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	_title = Label.new()
	_title.theme_type_variation = &"SetupSectionTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.text = "Promote to"
	column.add_child(_title)

	_options = HBoxContainer.new()
	_options.name = "Options"
	_options.add_theme_constant_override("separation", 6)
	_options.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_options)

	var queen := Button.new()
	queen.name = "Cancel"
	queen.text = "Queen"
	queen.custom_minimum_size = Vector2(0, 42)
	queen.theme_type_variation = &"QuietButton"
	queen.focus_mode = Control.FOCUS_NONE
	queen.pressed.connect(_on_cancel_pressed)
	column.add_child(queen)


func _rebuild_options() -> void:
	if _options == null:
		return
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	for piece in PIECES:
		_options.add_child(_make_option(piece, _preview_for(piece.to_lower(), _side)))


## Baked preview art by piece and side. Match arms, not a Dictionary:
## untyped lookups return Variant, which the escalating gate refuses.
static func _preview_for(piece: String, side: String) -> Texture2D:
	if side == "black":
		match piece:
			"queen":
				return PREVIEW_QUEEN_BLACK
			"rook":
				return PREVIEW_ROOK_BLACK
			"bishop":
				return PREVIEW_BISHOP_BLACK
			_:
				return PREVIEW_KNIGHT_BLACK
	match piece:
		"queen":
			return PREVIEW_QUEEN_WHITE
		"rook":
			return PREVIEW_ROOK_WHITE
		"bishop":
			return PREVIEW_BISHOP_WHITE
		_:
			return PREVIEW_KNIGHT_WHITE


## A tappable button holding the baked piece preview.
func _make_option(piece: String, texture: Texture2D) -> Button:
	var button := Button.new()
	button.custom_minimum_size = OPTION_SIZE
	button.tooltip_text = piece
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.pressed.connect(_on_choice.bind(piece.to_lower()))
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.custom_minimum_size = PREVIEW_SIZE
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(preview)
	return button


func _on_choice(piece: String) -> void:
	close()
	chosen.emit(piece)


func _on_cancel_pressed() -> void:
	close()
	chosen.emit("queen")
