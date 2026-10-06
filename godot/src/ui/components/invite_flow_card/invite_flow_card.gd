class_name InviteFlowCard
extends PanelContainer

## The card the multiplayer hub shows instead of its Create and Join choices while
## one of those flows is running.
##
## Five flows use it: create a code, join with a code, invite a listed player, respond
## to an invitation, and recover from a declined one. All five want the same shape —
## what is happening, a line about it, room for whatever that flow is specifically
## about, and a row of things that can be done — and none of them want a different
## kind of card.
##
## It is a scene rather than something the hub builds because it is the same five
## times. See docs/architecture/foundation_tightening.md, item 2.

@onready var _heading: Label = %Heading
@onready var _detail: Label = %Detail
@onready var _body: VBoxContainer = %Body
@onready var _actions: HBoxContainer = %Actions


## Starts a flow: what is happening, and the line under it. Everything the previous
## flow put here goes, so a card never shows one flow's leftovers above another's.
func show_flow(heading_text: String, detail_text: String) -> void:
	_heading.text = heading_text
	_detail.text = detail_text
	_detail.visible = not detail_text.is_empty()
	_discard(_body)
	_discard(_actions)
	show()


## Empties a container and frees what was in it.
##
## Removed and freed in the same step rather than queued, because the caller fills the
## card again immediately afterwards and a queued child is still a child until the end
## of the frame, which would leave one flow's content sitting above the next one's.
func _discard(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## A line of status inside the card. Returns it so a flow can keep updating the text
## without holding on to a node it did not create.
func add_status(text: String, variation: StringName = &"SetupStatusText") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(label)
	return label


## The generated code, shown large because it is meant to be read off one screen and
## typed into another.
func add_code(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"CodeDisplay"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(label)
	return label


## Adds a control the flow needs: the code entry, a checkbox, anything else.
func add_content(control: Control) -> Control:
	_body.add_child(control)
	return control


## A button in the card's action row. Returned so the flow can connect to it or hold
## it; the card does not decide what any of them do.
func add_action(text: String, variation: StringName = &"SetupActionButton") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(144.0, 48.0)
	button.theme_type_variation = variation
	_actions.add_child(button)
	return button


## A centred row inside the body, for actions that belong with the content rather than
## in the card's own action row.
func add_centered_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	return row