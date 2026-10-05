class_name GameHeader
extends Control

signal menu_requested
signal voice_toggle_requested

enum NetworkState { IDLE, CONNECTING, DEGRADED, GOOD, LOST }
enum VoiceState { OFF, REQUESTING, LIVE }

const MIC_OFF_ICON: Texture2D = preload(
	"res://src/ui/components/game_header/icons/mic_off.svg")
const MIC_REQUESTING_ICON: Texture2D = preload(
	"res://src/ui/components/game_header/icons/mic_signal.svg")
const MIC_LIVE_ICON: Texture2D = preload(
	"res://src/ui/components/game_header/icons/mic.svg")

@export_group("Content")
@export var center_text := ""

@export_group("Visible elements")
@export var show_network_indicator := true
@export var show_voice_control := false
@export var show_center_text := true
@export var show_menu_button := true

@onready var _network_indicator: Control = %NetworkIndicator
@onready var _voice_cluster: Control = %VoiceCluster
@onready var _mic_button: Button = %MicButton
@onready var _mic_glyph: TextureRect = %MicGlyph
@onready var _mic_live_ring: Panel = %MicLiveRing
@onready var _remote_speaking_dot: Panel = %RemoteSpeakingDot
@onready var _center_label: Label = %CenterLabel
@onready var _menu_button: Button = %MenuButton

var _voice_state := VoiceState.OFF


func _ready() -> void:
	_mic_button.pressed.connect(_on_mic_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_apply_visibility()
	_center_label.text = center_text
	set_voice_state(VoiceState.OFF)
	set_network_state(NetworkState.IDLE)


## Sets which parts of this header are present in the current screen context.
func set_visibility(
	show_network: bool,
	show_voice: bool,
	show_center: bool,
	show_menu: bool
) -> void:
	show_network_indicator = show_network
	show_voice_control = show_voice
	show_center_text = show_center
	show_menu_button = show_menu
	_apply_visibility()
	if not show_voice_control:
		set_voice_state(VoiceState.OFF)
		set_remote_speaking(false)


## Pass screen-owned content; the header has no chess-state dependency.
func set_center_text(text: String) -> void:
	center_text = text
	_center_label.text = text


func set_network_state(state: NetworkState) -> void:
	_network_indicator.call("set_state", state)


func set_voice_state(state: VoiceState) -> void:
	_voice_state = state
	match state:
		VoiceState.REQUESTING:
			_mic_glyph.texture = MIC_REQUESTING_ICON
			_mic_button.tooltip_text = "Request voice chat"
		VoiceState.LIVE:
			_mic_glyph.texture = MIC_LIVE_ICON
			_mic_button.tooltip_text = "Voice chat active"
		_:
			_mic_glyph.texture = MIC_OFF_ICON
			_mic_button.tooltip_text = "Voice chat off"
	_mic_live_ring.visible = state == VoiceState.LIVE


func set_remote_speaking(speaking: bool) -> void:
	_remote_speaking_dot.visible = speaking and show_voice_control


func _apply_visibility() -> void:
	_network_indicator.visible = show_network_indicator
	_voice_cluster.visible = show_voice_control
	_center_label.visible = show_center_text
	_menu_button.visible = show_menu_button


func _on_mic_pressed() -> void:
	voice_toggle_requested.emit()


func _on_menu_pressed() -> void:
	menu_requested.emit()
