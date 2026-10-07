class_name PromotionPicker
extends Control
## Asks which piece a pawn becomes. Shown instead of applying the move:
## a promotion cannot be tapped as two squares, and applying first would
## animate the wrong piece. Cancelling is not a dead end: it falls back
## to a queen, so the player can always finish the move.
##
## Options reuse ChoiceGroup (theme language, no second code path) and are
## configured here in code: array-typed scene overrides do not survive
## export conversion. The ChoiceGroup instance stays a leaf: nothing is
## ever parented inside another scene's interior.
##
## Emitted with "queen", "rook", "bishop" or "knight".

signal chosen(piece: String)

const PIECES := ["Queen", "Rook", "Bishop", "Knight"]
const SUFFIXES := {"queen": "q", "rook": "r", "bishop": "b", "knight": "n"}

@onready var _choice: ChoiceGroup = %PromotionChoices


static func suffix_for(piece: String) -> String:
	return SUFFIXES.get(piece, "q")


func _ready() -> void:
	_choice.configure("Promote to", PackedStringArray(PIECES), 2, 0)
	_choice.selection_changed.connect(_on_choice)
	var cancel := get_node("Centre/Panel/Column/Cancel") as Button
	cancel.pressed.connect(_on_cancel_pressed)
	visible = false


## Shows the picker for a pawn of the given side ("white"/"black").
func open(side: String) -> void:
	_choice.configure("%s pawn promotes to" % side.capitalize(), PackedStringArray(PIECES), 2, 0)
	visible = true


func close() -> void:
	visible = false


## How many choices are on offer, so tests assert population, not visibility.
func option_count() -> int:
	return _choice.get_node("Options").get_child_count()


func _on_choice(choice: String, _index: int) -> void:
	close()
	chosen.emit(choice.to_lower())


func _on_cancel_pressed() -> void:
	close()
	chosen.emit("queen")
