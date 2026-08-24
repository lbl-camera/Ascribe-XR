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

## True between the first agent_text chunk of a turn and agent_text_done.
var _agent_turn_active: bool = false
var _signals_connected: bool = false


func _ready() -> void:
	_connect_signals()

	_send_button.pressed.connect(_on_send_pressed)
	_line_edit.text_submitted.connect(_on_line_edit_submitted)
	_line_edit.focus_entered.connect(_on_line_edit_focus_entered)
	_interrupt_button.pressed.connect(_on_interrupt_pressed)
	_new_conversation_button.pressed.connect(_on_new_conversation_pressed)

	_interrupt_button.hide()

	AgentSession.connect_to_room()


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


func _on_tool_call_received(_request_id: String, name: String, _args: Dictionary, executor: int) -> void:
	# Locally-executed tool calls: render the notice here. Remote calls are
	# rendered via AgentToolDispatcher.tool_executed_remotely instead, since
	# that signal only fires for the non-executing peers.
	if executor == AgentSession.client_id:
		_on_tool_used(name)


func _on_tool_used(name: String) -> void:
	_transcript.append_text(format_tool_used_line(name) + "\n")
