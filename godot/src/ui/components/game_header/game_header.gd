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

const EDGE_INSET := 24.0
const CONTROL_SIZE := 48.0
const TITLE_MAX_WIDTH := 320.0
const TITLE_LEFT_RESERVED := 88.0
const TITLE_RIGHT_RESERVED := 140.0
## Voice transport is outside v1, so the mic notes its own unavailability here
## instead of each screen repeating it (previously via center text, or not at
## all when no handler was connected). Flip when the transport lands.
const VOICE_UNAVAILABLE_TOOLTIP := "Voice chat unavailable"

@export_group("Content")
@export var center_text := ""

@export_group("Visible elements")
@export var show_network_indicator := true
@export var show_voice_control := false
@export var show_center_text := true
@export var show_menu_button := true

@export_group("Voice")
## True once a voice transport exists. False keeps the mic honest: presses are
## noted on the control itself and never read as a live channel.
@export var voice_transport_available := false

@onready var _network_indicator: Control = %NetworkIndicator
@onready var _voice_cluster: Control = %VoiceCluster
@onready var _mic_button: Button = %MicButton
@onready var _mic_glyph: TextureRect = %MicGlyph
@onready var _mic_live_ring: Panel = %MicLiveRing
@onready var _remote_speaking_dot: Panel = %RemoteSpeakingDot
@onready var _center_label: Label = %CenterLabel
@onready var _menu_button: Button = %MenuButton

var _voice_state := VoiceState.OFF
## The live bridge this header mirrors. Screens lend it; the header subscribes
## for meter presentation only and releases on exit or rebind.
var _net_bridge: ChessCoreBridge = null


func _ready() -> void:
	_mic_button.pressed.connect(_on_mic_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_apply_visibility()
	_center_label.text = center_text
	_center_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_update_layout()
	set_voice_state(VoiceState.OFF)
	if not voice_transport_available:
		_mic_button.tooltip_text = VOICE_UNAVAILABLE_TOOLTIP
	set_network_state(NetworkState.IDLE)
	if _net_bridge != null:
		_apply_network_snapshot()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_layout()


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
		if not voice_transport_available:
			_mic_button.tooltip_text = VOICE_UNAVAILABLE_TOOLTIP


## Pass screen-owned content; the header has no chess-state dependency.
func set_center_text(text: String) -> void:
	center_text = text
	_center_label.text = text


func set_network_state(state: NetworkState) -> void:
	_network_indicator.call("set_state", state)


func set_network_quality(level: int, rtt_ms: int, loss_percent: int, direct: bool) -> void:
	_network_indicator.call("set_quality", level, rtt_ms, loss_percent, direct)


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


## Single visibility policy for peer contexts. Solo play hides network and
## voice; peer play shows them. Center text and menu stay always on.
func set_peer_context(is_peer: bool) -> void:
	set_visibility(is_peer, is_peer, true, true)


## Mirrors the meter off a live bridge. One subscription covers every screen,
## so the signal-to-state map lives here and not once per screen. Screens keep
## their own subscriptions only for screen-owned text.
func bind_net_bridge(bridge: ChessCoreBridge) -> void:
	unbind_net_bridge()
	_net_bridge = bridge
	if not _net_bridge.network_snapshot_changed.is_connected(_on_network_snapshot_changed):
		_net_bridge.network_snapshot_changed.connect(_on_network_snapshot_changed)
	if is_node_ready():
		_apply_network_snapshot()


func unbind_net_bridge() -> void:
	if not is_instance_valid(_net_bridge):
		_net_bridge = null
		return
	if _net_bridge.network_snapshot_changed.is_connected(_on_network_snapshot_changed):
		_net_bridge.network_snapshot_changed.disconnect(_on_network_snapshot_changed)
	_net_bridge = null


func _apply_network_snapshot() -> void:
	if _net_bridge == null or not is_node_ready():
		return
	var snapshot := _net_bridge.network_snapshot()
	if snapshot.size() != 5:
		return
	var lifecycle := snapshot[0]
	var level := int(snapshot[1])
	var rtt_ms := int(snapshot[2])
	var loss_percent := int(snapshot[3])
	var direct := snapshot[4] == "true"
	match lifecycle:
		"connecting": set_network_state(NetworkState.CONNECTING)
		"degraded": set_network_state(NetworkState.DEGRADED)
		"lost": set_network_state(NetworkState.LOST)
		"connected":
			if level > 0:
				set_network_quality(level, rtt_ms, loss_percent, direct)
			else:
				set_network_state(NetworkState.GOOD)
		_: set_network_state(NetworkState.IDLE)


## Declares whether voice transport exists. With none, the mic stays OFF and
## carries its own unavailable note.
func set_voice_transport_available(available: bool) -> void:
	voice_transport_available = available
	if not available and is_node_ready():
		set_voice_state(VoiceState.OFF)
		_mic_button.tooltip_text = VOICE_UNAVAILABLE_TOOLTIP


func _apply_visibility() -> void:
	_network_indicator.visible = show_network_indicator
	_voice_cluster.visible = show_voice_control
	_center_label.visible = show_center_text
	_menu_button.visible = show_menu_button


func _update_layout() -> void:
	_voice_cluster.position = Vector2(EDGE_INSET, 16.0)
	_voice_cluster.size = Vector2(CONTROL_SIZE, CONTROL_SIZE)
	_mic_button.custom_minimum_size = Vector2(CONTROL_SIZE, CONTROL_SIZE)
	_mic_glyph.offset_left = 8.0
	_mic_glyph.offset_top = 8.0
	_mic_glyph.offset_right = -8.0
	_mic_glyph.offset_bottom = -8.0
	_remote_speaking_dot.position = Vector2(36.0, 36.0)
	_remote_speaking_dot.size = Vector2(11.0, 11.0)
	_menu_button.custom_minimum_size = Vector2(CONTROL_SIZE, CONTROL_SIZE)
	_menu_button.offset_left = -72.0
	_menu_button.offset_top = 16.0
	_menu_button.offset_right = -EDGE_INSET
	_menu_button.offset_bottom = 64.0
	_network_indicator.offset_left = -124.0
	_network_indicator.offset_top = -18.0
	_network_indicator.offset_right = -88.0
	_network_indicator.offset_bottom = 18.0
	var title_width := minf(
		TITLE_MAX_WIDTH,
		maxf(0.0, size.x - TITLE_LEFT_RESERVED - TITLE_RIGHT_RESERVED)
	)
	var available_width := maxf(0.0, size.x - TITLE_LEFT_RESERVED - TITLE_RIGHT_RESERVED)
	var title_center := size.x * 0.5
	if available_width < TITLE_MAX_WIDTH:
		title_center = (TITLE_LEFT_RESERVED + size.x - TITLE_RIGHT_RESERVED) * 0.5
	var center_offset := title_center - size.x * 0.5
	_center_label.offset_left = center_offset - title_width * 0.5
	_center_label.offset_top = 20.0
	_center_label.offset_right = center_offset + title_width * 0.5
	_center_label.offset_bottom = 60.0


func _on_mic_pressed() -> void:
	if not voice_transport_available:
		set_voice_state(VoiceState.OFF)
		_mic_button.tooltip_text = VOICE_UNAVAILABLE_TOOLTIP
		return
	voice_toggle_requested.emit()


func _on_menu_pressed() -> void:
	menu_requested.emit()


func _exit_tree() -> void:
	unbind_net_bridge()


func _on_network_snapshot_changed(
	_lifecycle: String, _level: int, _rtt_ms: int, _loss_percent: int, _direct: bool) -> void:
	_apply_network_snapshot()
