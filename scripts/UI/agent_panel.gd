class_name AgentPanel
extends PanelContainer

## AgentPanel -- in-world conversation panel for the persistent per-room
## conversational agent. Talks to the AgentSession autoload (WebSocket
## plumbing) and AgentToolDispatcher (tool execution). Kept alive across
## menu open/close (preserve_content) so transcript history survives.

@onready var _transcript: RichTextLabel = %Transcript
@onready var _status_label: Label = %StatusLabel
@onready var _line_edit: LineEdit = %LineEdit
@onready var _send_button: Button = %SendButton
@onready var _interrupt_button: Button = %InterruptButton
@onready var _new_conversation_button: Button = %NewConversationButton
@onready var _attach_view_checkbox: CheckBox = %AttachViewCheckBox
@onready var _talk_button: Button = %TalkButton

## True between the first agent_text chunk of a turn and agent_text_done.
var _agent_turn_active: bool = false
var _signals_connected: bool = false

## client_id of whoever currently holds the speaker floor, or -1 if free.
var _floor_holder_id: int = -1

const _FLOOR_COLOR: Color = Color(1.0, 0.35, 0.35)
const _DEFAULT_COLOR: Color = Color(1.0, 1.0, 1.0)


func _ready() -> void:
	_connect_signals()
	# Open the mic device now so the first Talk press hears the user
	# immediately (cold WASAPI capture streams zeros for a second or two).
	AgentMic.prewarm()

	_send_button.pressed.connect(_on_send_pressed)
	_line_edit.text_submitted.connect(_on_line_edit_submitted)
	_line_edit.focus_entered.connect(_on_line_edit_focus_entered)
	_interrupt_button.pressed.connect(_on_interrupt_pressed)
	_new_conversation_button.pressed.connect(_on_new_conversation_pressed)
	_talk_button.toggled.connect(_on_talk_toggled)

	_interrupt_button.hide()

	AgentSession.connect_to_room()
	_update_talk_button()


func _process(_delta: float) -> void:
	_update_talk_button()


func _connect_signals() -> void:
	if _signals_connected:
		return
	_signals_connected = true
	AgentSession.agent_text.connect(_on_agent_text)
	AgentSession.agent_text_done.connect(_on_agent_text_done)
	AgentSession.status_changed.connect(_on_status_changed)
	AgentSession.disconnected.connect(_on_disconnected)
	AgentSession.connected.connect(_on_connected)
	AgentSession.history_received.connect(_on_history_received)
	AgentSession.error_received.connect(_on_error_received)
	AgentSession.tool_call_received.connect(_on_tool_call_received)
	AgentSession.speaker_bound.connect(_on_speaker_bound)
	AgentSession.speaker_released.connect(_on_speaker_released)
	AgentSession.transcript_received.connect(_on_transcript_received)
	AgentToolDispatcher.tool_executed_remotely.connect(_on_tool_used)


# ---------------------------------------------------------------------------
# Static formatting helpers (testable without a scene tree)
# ---------------------------------------------------------------------------

static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


static func format_user_line(text: String) -> String:
	return "[b]You[/b] " + _escape_bbcode(text)


static func format_agent_line(text: String) -> String:
	return "[b]Agent[/b] " + _escape_bbcode(text)


static func format_tool_used_line(name: String) -> String:
	return "[color=gray]Agent used %s[/color]" % name


static func format_peer_line(text: String, client_id: int) -> String:
	return "[b]Peer %d[/b] " % client_id + _escape_bbcode(text)


# ---------------------------------------------------------------------------
# User input
# ---------------------------------------------------------------------------

func _on_send_pressed() -> void:
	_submit()


func _on_line_edit_submitted(_text: String) -> void:
	_submit()


func _submit() -> void:
	var text := _line_edit.text.strip_edges()
	if text.is_empty():
		return
	if _attach_view_checkbox.button_pressed:
		await _try_attach_view()
	_transcript.append_text(format_user_line(text) + "\n")
	AgentSession.send_text(text)
	_line_edit.text = ""
	DisplayServer.virtual_keyboard_hide()


## Best-effort viewport capture preceding a text send when "attach view" is
## checked. Capture failures must never block sending the text message.
func _try_attach_view() -> void:
	var viewport := get_viewport()
	if viewport == null:
		push_warning("AgentPanel: no viewport available for attach view")
		return
	var jpeg: PackedByteArray = await AgentCapture.capture(viewport)
	if jpeg.is_empty():
		push_warning("AgentPanel: viewport capture failed for attach view")
		return
	AgentSession.send_screenshot(jpeg)


func _on_line_edit_focus_entered() -> void:
	DisplayServer.virtual_keyboard_show("")


func _on_interrupt_pressed() -> void:
	AgentSession.send_interrupt()


func _on_talk_toggled(pressed: bool) -> void:
	if pressed:
		AgentSession.send_bind()
	else:
		AgentSession.send_unbind()


func _on_new_conversation_pressed() -> void:
	AgentSession.send_end_conversation()
	_transcript.clear()
	_agent_turn_active = false
	_interrupt_button.hide()


# ---------------------------------------------------------------------------
# AgentSession signal handlers
# ---------------------------------------------------------------------------

func _on_agent_text(text: String) -> void:
	if not _agent_turn_active:
		_agent_turn_active = true
		_interrupt_button.show()
		_transcript.append_text("[b]Agent[/b] ")
	_transcript.append_text(_escape_bbcode(text))


func _on_agent_text_done() -> void:
	_agent_turn_active = false
	_interrupt_button.hide()
	_transcript.append_text("\n")


func _on_status_changed(text: String) -> void:
	_status_label.text = text


func _on_disconnected() -> void:
	_status_label.text = "reconnecting..."


func _on_connected() -> void:
	_status_label.text = ""


func _on_history_received(_client_id: int, entries: Array) -> void:
	_transcript.clear()
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var role: String = str(entry.get("role", ""))
		var text: String = str(entry.get("text", ""))
		if role == "user":
			_transcript.append_text(format_user_line(text) + "\n")
		elif role == "agent":
			_transcript.append_text(format_agent_line(text) + "\n")


func _on_error_received(message: String) -> void:
	_status_label.text = message
	# A rejected bind ("speaker slot is held", "voice is not enabled", ...)
	# leaves the Talk toggle stuck pressed with no floor to release; un-press it
	# so the button reflects reality.
	if _talk_button.button_pressed and _floor_holder_id != AgentSession.client_id:
		_talk_button.set_pressed_no_signal(false)
		_update_talk_button()


func _on_tool_call_received(_request_id: String, name: String, _args: Dictionary, executor: int) -> void:
	# Locally-executed tool calls: render the notice here. Remote calls are
	# rendered via AgentToolDispatcher.tool_executed_remotely instead, since
	# that signal only fires for the non-executing peers.
	if executor == AgentSession.client_id:
		_on_tool_used(name)


func _on_tool_used(name: String) -> void:
	_transcript.append_text(format_tool_used_line(name) + "\n")


func _on_speaker_bound(client_id: int) -> void:
	_floor_holder_id = client_id
	print("[AgentPanel] speaker_bound: floor=%d, our client_id=%d" % [client_id, AgentSession.client_id])
	if client_id == AgentSession.client_id:
		AgentMic.start_capture()
	_update_talk_button()


func _on_speaker_released() -> void:
	var we_held_floor: bool = _floor_holder_id == AgentSession.client_id
	_floor_holder_id = -1
	if we_held_floor:
		AgentMic.stop_capture()
		_talk_button.set_pressed_no_signal(false)
	_update_talk_button()


func _on_transcript_received(text: String, client_id: int) -> void:
	if client_id == AgentSession.client_id:
		_transcript.append_text(format_user_line(text) + "\n")
	else:
		_transcript.append_text(format_peer_line(text, client_id) + "\n")


## Refreshes the Talk button's label/enabled/modulate state from current
## floor ownership and agent-playback state. Priority: our floor > another's
## floor > agent speaking (barge-in available) > default idle.
func _update_talk_button() -> void:
	if _floor_holder_id == AgentSession.client_id:
		_talk_button.disabled = false
		_talk_button.text = "Listening…"
		_talk_button.modulate = _FLOOR_COLOR
	elif _floor_holder_id != -1:
		_talk_button.disabled = true
		_talk_button.text = "(%d speaking)" % _floor_holder_id
		_talk_button.modulate = _DEFAULT_COLOR
	elif AgentVoice.is_playing_agent_audio:
		_talk_button.disabled = false
		_talk_button.text = "Interrupt & talk"
		_talk_button.modulate = _DEFAULT_COLOR
	else:
		_talk_button.disabled = false
		_talk_button.text = "Talk"
		_talk_button.modulate = _DEFAULT_COLOR
