# Agent Conversation (ascribe-xr milestones 0–2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A persistent, room-scoped conversational agent: users type to it in an in-world panel, it answers streamingly, generates/iterates specimens, manipulates the scene and display via client-executed tools, and can see the user's viewport.

**Architecture:** ascribe-link (Litestar, `C:\Users\rp\Documents\ascribe-link`) gains a `/ws/agent/{room_id}` websocket and a per-room persistent `claude_agent_sdk` session running on a dedicated worker thread with its own event loop (precedent: `routes/specimens.py:582-599` `_invoke_in_thread`), replacing the one-shot spawn-subprocess model *for conversations only* (the existing `ai_generate` job path is untouched). vr-start gains an `AgentSession` autoload (WebSocketPeer), an `AgentToolDispatcher` mapping server-forwarded tool calls onto SceneManager RPCs (two new RPCs added), and a conversation panel spawned through MenuManager. Voice, floor control, and local-launch are a follow-up plan; the protocol reserves their frame types now.

**Tech Stack:** Python ≥3.11 (dev venv 3.13), Litestar 2 websockets, claude-agent-sdk, pytest (asyncio_mode=auto, AsyncTestClient); Godot 4.6, WebSocketPeer, gdUnit4 (to be enabled).

**Spec:** `docs/superpowers/specs/2026-08-18-agent-centric-design.md` (vr-start). Deviations locked here: (1) this plan is milestones 0–2 only; (2) the spec's SpecimenLifecycle/JobRunner split of `main.gd` and the `/api/processing/invoke` deprecation are deferred to the follow-up plan — this plan adds to SceneManager only what agent tools force (two RPC wrappers); (3) in the text-only phase, turn-taking is a per-room serial queue, not the bind button (which arrives with voice).

## Global Constraints

- Two repos: server work in `C:\Users\rp\Documents\ascribe-link` (branch `agent-conversation` off main), client work in `C:\Users\rp\Documents\vr-start` (branch `agent-conversation` off master). Commit per task in whichever repo(s) the task touches.
- ascribe-link is **Litestar** — follow `ascribe_link/routes/federation.py` idioms for websockets (`@websocket("/{room_id:str}")`, `await socket.accept()`, `socket.iter_json()`), and DI via `Provide(..., sync_to_thread=False)` by parameter name (`app.py:331-337`).
- Python: ruff line-length 100 (`select E,F,W,I`); pytest `asyncio_mode="auto"`, tests in `tests/`; run via `.venv\Scripts\python -m pytest` from the ascribe-link checkout (create the venv with `py -3.13 -m venv .venv` + `pip install -e .[test,agent]` if absent). All new logging via `logging.getLogger(...)` only — never print/console handlers (the app routes logs through a QueueHandler, `cli.py:93-117`).
- Never touch `JobRegistry` internals from worker threads; the agent WS path must not depend on the job progress deque (maxlen=50).
- The claude_agent_sdk is imported lazily and every session component must accept an injected client factory so tests run with a fake (no API key in CI).
- WS wire protocol: TEXT frames are JSON objects with a required `"type"` key; BINARY frames are `<u32 LE header_len><UTF-8 JSON header><raw payload>` (mirrors `ascribe_link/envelope.py:3-7`). Reserved-but-unimplemented types (`bind`, `unbind`, `audio`, `speaker_bound`, `speaker_released`, `agent_audio`, `transcript`) must be REJECTED with an `error` frame naming the type, not silently ignored.
- Godot: new RPCs use `@rpc("any_peer", "call_local", "reliable")`; new autoloads appended after `MenuManager` in `project.godot`; pure logic goes in static helper classes (convention: `scripts/singletons/scene_manager_helpers.gd`) so gdUnit can test it without a scene tree; Godot exe for headless: `C:\Users\rp\Downloads\Godot_v4.6-stable_win64_console.exe` (gdUnit needs `--ignoreHeadlessMode`; run `--import` after adding files).
- Use `127.0.0.1`, never `localhost`, in default URLs (`config.gd:9` comment — Windows IPv6 issue).
- Commit messages end with a blank line then `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## File structure

```
ascribe-link/
├── ascribe_link/agent_ws/__init__.py
│   ├── protocol.py        frame schemas, validate/build (pure)
│   ├── session.py         AgentConversation: worker thread + persistent SDK client
│   ├── tools.py           conversational MCP tools (server-compute + client-forwarded)
│   ├── manager.py         AgentSessionManager: room → session, socket fan-out
│   └── controller.py      Litestar websocket controller /ws/agent/{room_id}
└── tests/test_agent_ws_*.py (protocol, session, forwarding, integration)

vr-start/
├── scripts/singletons/agent_session.gd         AgentSession autoload (WS client)
├── scripts/singletons/agent_session_helpers.gd static frame helpers (testable)
├── scripts/singletons/agent_tool_dispatcher.gd AgentToolDispatcher autoload
├── scripts/singletons/agent_tool_helpers.gd    static tool validation/mapping (testable)
├── scripts/UI/agent_panel.gd + scenes/UI/agent_panel.tscn
├── scripts/singletons/main.gd                  MODIFY: +2 RPCs
└── tests/test_agent_*.gd                       gdUnit suites
```

---

### Task 1: Server — protocol module (pure)

**Files:**
- Create: `ascribe_link/agent_ws/__init__.py` (empty), `ascribe_link/agent_ws/protocol.py`
- Test: `tests/test_agent_ws_protocol.py`

**Interfaces:**
- Produces (consumed by Tasks 2–5 and mirrored by the Godot client):
  - `CLIENT_TYPES = {"text", "tool_result", "screenshot_meta", "interrupt", "end_conversation"}`; `RESERVED_TYPES = {"bind", "unbind", "audio"}`
  - `SERVER_TYPES = {"agent_text", "agent_text_done", "tool_call", "status", "error", "history", "turn_queued"}`; reserved server types `{"speaker_bound", "speaker_released", "agent_audio", "transcript"}`
  - `validate_client_frame(frame: dict) -> str` — returns "" if valid, else a human-readable error. Rules: dict with str `type`; `text` requires non-empty str `text`; `tool_result` requires str `request_id` and `result` (any JSON); `interrupt`/`end_conversation` need no extras; a RESERVED type returns `"type '<t>' is reserved for the voice phase"`; unknown type returns `"unknown frame type '<t>'"`.
  - Builders returning dicts: `agent_text(text)`, `agent_text_done()`, `tool_call(request_id, name, args)`, `status(text)`, `error(message)`, `history(entries: list[dict])`, `turn_queued(position: int)`.
  - Binary framing: `encode_binary(header: dict, payload: bytes) -> bytes` and `decode_binary(data: bytes) -> tuple[dict, bytes]` (u32 LE + JSON header + payload; ValueError on truncation/bad JSON).

- [ ] **Step 1: Write failing tests**

```python
# tests/test_agent_ws_protocol.py
import struct

import pytest

from ascribe_link.agent_ws import protocol as p


def test_valid_text_frame():
    assert p.validate_client_frame({"type": "text", "text": "hi"}) == ""


def test_text_requires_nonempty_text():
    assert "text" in p.validate_client_frame({"type": "text", "text": ""})
    assert "text" in p.validate_client_frame({"type": "text"})


def test_tool_result_requires_request_id_and_result():
    ok = {"type": "tool_result", "request_id": "r1", "result": {"ok": True}}
    assert p.validate_client_frame(ok) == ""
    assert "request_id" in p.validate_client_frame({"type": "tool_result", "result": {}})


def test_reserved_type_rejected_with_reason():
    msg = p.validate_client_frame({"type": "audio"})
    assert "reserved" in msg and "audio" in msg


def test_unknown_type_rejected():
    assert "unknown" in p.validate_client_frame({"type": "bogus"})


def test_builders_have_type_key():
    assert p.tool_call("r1", "load_specimen", {"a": 1}) == {
        "type": "tool_call", "request_id": "r1", "name": "load_specimen", "args": {"a": 1}}
    assert p.status("thinking")["type"] == "status"
    assert p.turn_queued(2) == {"type": "turn_queued", "position": 2}


def test_binary_roundtrip():
    data = p.encode_binary({"kind": "screenshot", "mime": "image/jpeg"}, b"JPEGDATA")
    header, payload = p.decode_binary(data)
    assert header["kind"] == "screenshot"
    assert payload == b"JPEGDATA"
    n = struct.unpack("<I", data[:4])[0]
    assert data[4 + n:] == b"JPEGDATA"


def test_binary_truncated_raises():
    with pytest.raises(ValueError):
        p.decode_binary(b"\x00")
```

- [ ] **Step 2: Run — expect FAIL** (`ModuleNotFoundError`): `.venv\Scripts\python -m pytest tests\test_agent_ws_protocol.py -v`
- [ ] **Step 3: Implement `protocol.py`** — module docstring naming the wire contract; sets/validators/builders exactly per Interfaces; `encode_binary`/`decode_binary` with `struct.pack("<I", ...)` mirroring `envelope.py`.
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Commit** `feat(agent-ws): wire protocol frames and binary framing`

---

### Task 2: Server — conversational session worker with injectable SDK

**Files:**
- Create: `ascribe_link/agent_ws/session.py`
- Test: `tests/test_agent_ws_session.py`

**Interfaces:**
- Consumes: `protocol` builders (Task 1).
- Produces: `class AgentConversation` —
  - `__init__(self, room_id: str, *, client_factory: Callable[[], Any], emit: Callable[[dict], None], request_client_tool: Callable[[str, dict], Awaitable[Any]], model: str, system_prompt: str | None = None)` — `emit` is thread-safe (manager wraps `loop.call_soon_threadsafe`); `request_client_tool(name, args)` awaits the client's `tool_result` (Task 4 provides the real one).
  - `start() -> None` — spawns the worker thread running its own event loop; enters `client_factory()` as async context manager ONCE and keeps it open.
  - `submit_text(text: str) -> int` — queues a user turn, returns queue position (0 = running now).
  - `attach_image(jpeg: bytes) -> None` — stashes an image to attach to the next turn.
  - `interrupt() -> None`, `stop() -> None` (graceful: cancel turn, exit client context, join thread), `history() -> list[dict]` (role/text entries, capped 200).
- The worker loop per turn: `await client.query(prompt_blocks)` then `async for msg in client.receive_response():` translating messages via a local `_emit_events(msg)` (AssistantMessage text blocks → `agent_text`; blocks with `.name` → `status(f"Using the {name} tool...")` — same translation contract as `agent_generator._emit_agent_events` at `agent_generator.py:43-115`, reimplemented here without the reporter), ending with `agent_text_done`. Turns are strictly serial; `submit_text` while busy returns position and the manager sends `turn_queued`.
- **Ruling (recorded):** worker THREAD + persistent event loop, not the spawn-subprocess used by `_run_agent_in_subprocess` (`agent_generator.py:1271-1322`). Rationale: the subprocess model is one-shot by construction; the GIL-stall concern that motivated it (giant `json.loads` from mesh dumps) is mitigated because conversations stream small messages and heavy artifacts still flow through the existing job path. If stalls reappear, the seam is `client_factory`.

- [ ] **Step 1: Write failing tests** — a `FakeSDKClient` (async context manager; `query()` records prompts; `receive_response()` yields scripted message objects with `content` blocks shaped like the SDK's: `types.SimpleNamespace(content=[SimpleNamespace(text="Hello!")])` for text and `SimpleNamespace(content=[SimpleNamespace(name="mcp__scene__load_specimen", text=None)])` for a tool block). Tests: (a) `start()` enters the client exactly once across two `submit_text` turns (fake counts `__aenter__`); (b) emitted frame sequence for a scripted turn is `status("thinking")`, `agent_text("Hello!")`, `agent_text_done()`; (c) tool block emits `status("Using the mcp__scene__load_specimen tool...")`; (d) second `submit_text` while turn 1 is blocked (fake gated on an `asyncio.Event`) returns position 1; (e) `interrupt()` while blocked ends the turn and emits `status("interrupted")`; (f) `stop()` joins the thread within 5 s and exits the client context; (g) `history()` returns both user and agent entries in order. Use `queue.Queue` collection of emitted frames with timeouts — no sleeps.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** — thread target: `asyncio.new_event_loop()` + `run_until_complete(self._main())`; `_main` holds the client context and drains an `asyncio.Queue` of turns; `submit_text`/`interrupt`/`stop`/`attach_image` marshal in via `loop.call_soon_threadsafe`. Every exception inside a turn emits `error(str(e))` and continues to the next turn — a failed turn never kills the session.
- [ ] **Step 4: Run — expect PASS.** **Step 5: Commit** `feat(agent-ws): persistent per-room conversation worker with injectable SDK client`

---

### Task 3: Server — conversational tool surface

**Files:**
- Create: `ascribe_link/agent_ws/tools.py`
- Test: `tests/test_agent_ws_tools.py`

**Interfaces:**
- Consumes: `AgentConversation.request_client_tool` callable shape (Task 2); `claude_agent_sdk.tool` / `create_sdk_mcp_server` (lazy import, same pattern as `agent_generator.py:583-593`); `ascribe_link.models` MeshResult/VolumeResult + `wrap_agent_output` (`agent_generator.py:1414-1444`).
- Produces: `build_conversation_tools(sink: ConversationSink) -> tuple[server, allowed_tools: list[str]]` where `ConversationSink` is a small class in tools.py holding `request_client_tool` (awaitable), `stage_result(result) -> str` (returns a specimen id the client can fetch via the existing data endpoint), and `room_id`. Tools registered on MCP server name `"scene"`:
  - Server-compute: `submit_mesh(vertices, faces)` and `submit_volume(volume_b64, shape, dtype)` — hoisted, de-closured ports of `agent_generator.py:629-707` and `:822-885`: same JSON schemas, but instead of setting a one-shot `AgentResult` they call `sink.stage_result(...)` and RETURN (the conversation continues); the tool result text tells the agent the specimen id and that it is now visible to the user.
  - Server-compute analysis: `analyze_specimen(specimen_id: str)` — looks up the staged result in the room cache via `sink.get_staged(specimen_id)` (sink protocol method; manager backs it with `RoomResultCache`), and returns text content with basic statistics: for a VolumeResult, shape/dtype/min/max/mean/std and a 16-bin histogram (numpy, computed via `asyncio.to_thread`); for a MeshResult, vertex/face counts and bounding box. Unknown id → error text content. This is the v1 "analyze & explain data" capability; richer analysis tools come later.
  - Client-forwarded (each body is one line: `await sink.request_client_tool(name, args)` with a 30 s timeout wrapper): `load_specimen(specimen_id)`, `set_active_specimen(index)`, `remove_specimen(index)`, `set_room_scene(name: Literal['lab','black','passthrough','world_scale'])`, `set_display_param(index, name: Literal['gamma','opacity','color_scalar','max_steps','step_size','zoom'], value: number)`, `capture_viewport()` (returns the image to the agent as an image content block: `{"content":[{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":...}}]}`).
  - `allowed_tools` = `["mcp__scene__" + name for each]` (NO Bash/Read/Write — the conversational agent gets no filesystem, unlike the generation job's `agent_generator.py:1066-1076`).
- **Staging contract with the existing app:** `stage_result` inserts into the `RoomResultCache` under `(function_name="agent_chat", params_hash=<uuid>)` the same way `_run_job` does, so the client fetches bytes from the existing `GET /api/specimens/{id}/data?...&room_id=` endpoint. The manager (Task 5) provides the real implementation; tools.py only defines the sink protocol.

- [ ] **Step 1: Failing tests** — with a `FakeSink` recording calls: (a) `build_conversation_tools` returns a server whose tool list matches the 9 names; (b) invoking the `set_display_param` tool handler with `{"index":0,"name":"gamma","value":2.0}` awaits `request_client_tool("set_display_param", ...)` and returns its result as text content; (c) `capture_viewport` wraps the sink's `bytes` return into an image content block with base64 data; (d) client-tool timeout (fake sink sleeps past the patched 0.05 s timeout) returns an error text content, not an exception; (e) `submit_volume` with a small b64 array calls `sink.stage_result` with a `VolumeResult` and returns text naming the id; (f) `analyze_specimen` on a staged 4×4×4 volume returns text containing shape, min, max, mean; unknown id returns an error text. `allowed_tools` count is 9 (`submit_mesh`, `submit_volume`, `analyze_specimen` + 6 client-forwarded). Import guard: the whole test module `pytest.importorskip("claude_agent_sdk")`.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS. Step 5: Commit** `feat(agent-ws): conversational MCP tool surface (server-compute + client-forwarded)`

---

### Task 4: Server — session manager with socket fan-out and tool correlation

**Files:**
- Create: `ascribe_link/agent_ws/manager.py`
- Test: `tests/test_agent_ws_manager.py`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `class AgentSessionManager` —
  - `__init__(self, *, model: str, client_factory=None, result_cache=None)` (None factory → real SDK factory built lazily on first session).
  - `async connect(room_id, socket) -> None` / `async disconnect(room_id, socket) -> None` — tracks sockets per room; on first-ever connect for a room, creates the `AgentConversation` (wiring `emit` → `broadcast`, `request_client_tool` → correlation below, sink.stage_result → result_cache); on connect sends `history(...)` to the new socket only.
  - `async handle_frame(room_id, socket, frame: dict) -> None` — validates via `protocol.validate_client_frame` (invalid → `error` to that socket only); `text` → `submit_text` (+ `turn_queued` if position > 0); `interrupt` → interrupt; `tool_result` → resolves the matching future; `end_conversation` → `stop()` and drop the session (next text starts fresh).
  - `async handle_binary(room_id, socket, data: bytes) -> None` — decode; header `kind=="screenshot"` → `conversation.attach_image(payload)`; anything else → `error`.
  - `async broadcast(room_id, frame) -> None` — send JSON to every room socket, pruning dead ones.
  - Tool correlation (mirrors `FederationHub.proxy_request`, `federation.py:147-161`): `request_client_tool(room_id, name, args)` creates `request_id=uuid4().hex`, stores an `asyncio.Future` on the MAIN loop, broadcasts `tool_call(...)`, awaits the future with `asyncio.wait_for(..., 30)`. The conversation worker thread calls this via `asyncio.run_coroutine_threadsafe(mgr.request_client_tool(...), main_loop).result()` — manager exposes a sync bridge `request_client_tool_sync` for the worker; capture `main_loop` at manager construction (`asyncio.get_running_loop()` in an async factory, see Task 5).
  - `async shutdown() -> None` — stop all sessions (app shutdown hook).
- Executor rule (text phase): `tool_call` broadcasts to ALL sockets, and the frame includes `"executor": <socket_index_0>`; the client whose `client_id` (assigned in the `history` frame as `{"type":"history", "client_id": n, ...}`) matches executes and replies; others render the action in the transcript. Oldest connection = index 0; reassign on disconnect.

- [ ] **Step 1: Failing tests** — `FakeSocket` with `send_json` recording + closed flag; fake conversation injected by monkeypatching `manager.AgentConversation`. Tests: (a) two sockets, `broadcast` reaches both, dead socket pruned; (b) `text` frame reaches `submit_text`, queue position 1 triggers `turn_queued` to sender; (c) invalid frame → `error` only to sender; (d) `request_client_tool` broadcasts a `tool_call` with executor 0 and resolves when `handle_frame` gets the matching `tool_result`; (e) timeout path raises `TimeoutError` inside, returned as failed result; (f) binary screenshot reaches `attach_image`; (g) `end_conversation` stops and a following `text` creates a fresh conversation (factory called twice).
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS. Step 5: Commit** `feat(agent-ws): room session manager, fan-out, and client-tool correlation`

---

### Task 5: Server — Litestar wiring + integration test

**Files:**
- Create: `ascribe_link/agent_ws/controller.py`
- Modify: `ascribe_link/app.py` (~:217-242 agent block, :274-276 route_handlers, :331-337 dependencies, :302-317 startup/shutdown hooks), `ascribe_link/cli.py` (no new flags needed — reuse `--enable-agent`/`--agent-model`)
- Test: `tests/test_agent_ws_integration.py`

**Interfaces:**
- Consumes: Tasks 1–4; `routes/federation.py:23-50` as the controller template.
- Produces: websocket route `/ws/agent/{room_id:str}` (mounted ONLY when `enable_agent=True`, independent of `relay_mode`); DI `agent_session_manager`; `create_app(..., agent_client_factory=None)` test seam threading a fake factory to the manager.

Controller shape (verbatim intent):

```python
class AgentWSController(Controller):
    path = "/ws/agent"

    @websocket("/{room_id:str}")
    async def agent_socket(self, socket: WebSocket, room_id: str,
                           agent_session_manager: AgentSessionManager) -> None:
        await socket.accept()
        await agent_session_manager.connect(room_id, socket)
        try:
            async for message in socket.iter_data(mode="binary"):  # see note
                ...
        finally:
            await agent_session_manager.disconnect(room_id, socket)
```

Note: Litestar's `iter_json()` (used in federation.py) handles text only; this socket carries text AND binary. Use `socket.receive()` in a loop and branch on the message: text → `json.loads` → `handle_frame`; bytes → `handle_binary`. Malformed JSON → `error` frame, keep the connection.

- [ ] **Step 1: Failing integration test** — `AsyncTestClient(app=create_app(enable_agent=True, agent_client_factory=FakeSDKFactory))` (reuse the Task 2 fake via a `tests/fake_sdk.py` helper module — create it in this task, importing nothing from claude_agent_sdk). With `async with client.websocket_connect("/ws/agent/testroom") as ws:` — (a) first message received is `history` with a `client_id`; (b) send `{"type":"text","text":"hello"}`, collect frames until `agent_text_done`, assert an `agent_text` with the fake's scripted reply arrived; (c) scripted fake triggers a `tool_call`; reply with `tool_result`; assert the turn completes; (d) second client on the same room receives the broadcasts; (e) `create_app(enable_agent=False)` → connecting to `/ws/agent/x` fails (404/close). Also assert GET `/api/specimens/` still works (no regression).
- [ ] **Step 2: FAIL. Step 3: Implement** — app.py: build the manager inside the existing `if enable_agent:` block; add `route_handlers.append(AgentWSController)`; provide DI; register `manager.shutdown` in `on_shutdown`. **Step 4: PASS, plus full suite** (`pytest tests -q`) for regressions. **Step 5: Commit** `feat(agent-ws): mount /ws/agent with DI, lifecycle, and integration tests`

---

### Task 6: Client — Config + AgentSession autoload

**Files (vr-start):**
- Create: `scripts/singletons/agent_session.gd`, `scripts/singletons/agent_session_helpers.gd`
- Modify: `scripts/singletons/config.gd` (append after :10: `@export var agent_ws_url = "ws://127.0.0.1:8000/ws/agent"`), `project.godot` [autoload] (append `AgentSession="*res://scripts/singletons/agent_session.gd"`) and [editor_plugins] (add `"res://addons/gdUnit4/plugin.cfg"` — the plugin is vendored at addons/gdUnit4 v6.0.0 but not enabled)
- Test: `tests/test_agent_session_helpers.gd`

**Interfaces:**
- Consumes: server protocol (Task 1) — mirrored constants.
- Produces:
  - `AgentSessionHelpers` (static): `build_text_frame(text: String) -> String` (JSON), `build_tool_result_frame(request_id: String, result: Variant) -> String`, `build_interrupt_frame() -> String`, `parse_server_frame(json_text: String) -> Dictionary` (returns `{"error": String}` on bad JSON/missing type), `encode_binary(header: Dictionary, payload: PackedByteArray) -> PackedByteArray` (u32 LE + JSON + payload — same as server).
  - `AgentSession` (Node autoload): `connect_to_room(room_id: String = Config.webrtcroomname)`; `send_text(text)`, `send_tool_result(request_id, result)`, `send_interrupt()`, `send_screenshot(jpeg: PackedByteArray)`; `_process` polls `WebSocketPeer`, reconnects with backoff 1→2→4→8 s (capped, resets on success); signals `connected`, `disconnected`, `agent_text(text: String)`, `agent_text_done()`, `status_changed(text: String)`, `tool_call_received(request_id: String, name: String, args: Dictionary, executor: int)`, `history_received(client_id: int, entries: Array)`, `error_received(message: String)`, `turn_queued(position: int)`. Property `client_id: int = -1` (set from history frame).

- [ ] **Step 1: Failing gdUnit tests for the helpers** — frame build/parse round-trips, bad JSON → error dict, binary encode layout (check first 4 bytes little-endian length), reserved server types pass through parse (typed dispatch happens in AgentSession).
- [ ] **Step 2: FAIL** (`--headless --ignoreHeadlessMode --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests` — note the four pre-existing suites in tests/ must also run; fix nothing unrelated, but report their status).
- [ ] **Step 3: Implement helpers + autoload.** AgentSession's frame dispatch is a `match frame.type:` emitting the signals; unknown types emit `error_received` locally (client-side leniency, server-side strictness).
- [ ] **Step 4: PASS. Step 5: Commit** `feat(agent): AgentSession autoload + frame helpers; enable gdUnit4 plugin`

---

### Task 7: Client — SceneManager RPC additions + AgentToolDispatcher

**Files (vr-start):**
- Create: `scripts/singletons/agent_tool_dispatcher.gd`, `scripts/singletons/agent_tool_helpers.gd`
- Modify: `scripts/singletons/main.gd` (add two RPCs; do NOT restructure anything else), `scripts/Specimen/volumetric_specimen.gd` (make `_update_shader` reachable for the RPC — see below), `project.godot` [autoload] (append `AgentToolDispatcher="*res://scripts/singletons/agent_tool_dispatcher.gd"` AFTER AgentSession)
- Test: `tests/test_agent_tool_helpers.gd`

**Interfaces:**
- Consumes: `AgentSession.tool_call_received` (Task 6); SceneManager's existing RPCs (`main.gd:74` `load_specimen(scene_path, config)`, `:146` `set_active_specimen(index)`, `:155` `remove_specimen(index)`) and `request_submit` (`:222`).
- Produces:
  - Two new RPCs on SceneManager, exactly:
    ```gdscript
    @rpc("any_peer", "call_local", "reliable")
    func set_room_scene_rpc(room: String) -> void:
        set_room_scene(room)

    @rpc("any_peer", "call_local", "reliable")
    func set_display_param(index: int, param: String, value: float) -> void:
        if index < 0 or index >= _open_specimens.size():
            push_error("set_display_param: bad index %d" % index)
            return
        var spec := _open_specimens[index]
        if spec.has_method("apply_display_param"):
            spec.apply_display_param(param, value)
    ```
    plus `apply_display_param(param: String, value: float)` on `volumetric_specimen.gd`: whitelist `['gamma','opacity','color_scalar','max_steps','step_size','zoom']` (the list at `volumetric_specimen.gd:41`), call the existing `_update_shader(value, param)` (`:117`), and update the bound slider (`ui_instance.get_node("%" + param + "Slider").set_value_no_signal(value)` guarded by null checks) so the UI doesn't drift.
  - `AgentToolHelpers` (static, pure): `validate_tool(name: String, args: Dictionary) -> String` ("" ok, else error) — schema per tool: `load_specimen{specimen_id:String}`, `set_active_specimen{index:int}`, `remove_specimen{index:int}`, `set_room_scene{name in ['lab','black','passthrough','world_scale']}`, `set_display_param{index:int, name in whitelist, value:float}`, `capture_viewport{}`.
  - `AgentToolDispatcher` (Node autoload): on `tool_call_received(request_id, name, args, executor)` — if `AgentSession.client_id != executor`: append a transcript notice only (via signal `tool_executed_remotely(name)`); else validate (invalid → `send_tool_result(request_id, {"error": msg})`), execute, reply `{"ok": true, ...}`. Execution mapping: `set_room_scene` → `SceneManager.set_room_scene_rpc.rpc(args.name)`; `set_display_param` → `SceneManager.set_display_param.rpc(args.index, args.name, args.value)`; `set_active_specimen`/`remove_specimen` → existing RPCs; `load_specimen` → fetch by id through the existing dynamic-specimen result flow: call `SceneManager.specimen_job_done.rpc(args.specimen_id, "agent_chat", Config.webrtcroomname, "")` (the staged-result contract from server Task 3 — every peer then GETs the cached data exactly as after a job); `capture_viewport` → handled in Task 9, return `{"error": "not implemented"}` until then.

- [ ] **Step 1: Failing gdUnit tests for AgentToolHelpers** — valid/invalid for each tool (bad enum, missing key, wrong type), unknown tool name.
- [ ] **Step 2: FAIL. Step 3: Implement** helpers, dispatcher, the two RPCs, `apply_display_param`. **Step 4: PASS (full gdUnit run). Step 5:** Also verify the project still parses headless: `--headless --path . --import` exits clean. **Step 6: Commit** `feat(agent): tool dispatcher + set_display_param/set_room_scene RPCs`

---

### Task 8: Client — conversation panel

**Files (vr-start):**
- Create: `scenes/UI/agent_panel.tscn`, `scripts/UI/agent_panel.gd`
- Modify: `scripts/AscribeMain/ascribemain.gd` (spawn hook), `scripts/UI/mainmenuflat.gd` (an "Agent" button that opens the panel)

**Interfaces:**
- Consumes: all AgentSession signals (Task 6), `AgentToolDispatcher.tool_executed_remotely`, MenuManager (`menu_manager.gd:36` `show_menu(control, options)`; options slot/screen_size/viewport_size/preserve_content — follow the NetworkGateway preserve_content pattern at `ascribemain.gd:39-44`).
- Produces: `AgentPanel` (Control): scrolling transcript (`RichTextLabel`, bbcode: user turns prefixed `[b]You[/b] `, agent turns `[b]Agent[/b] ` with streaming append on `agent_text`, finalized on `agent_text_done`), status line (Label, driven by `status_changed`; shows "reconnecting..." on `disconnected`), `LineEdit` + Send button (Enter submits; on focus `DisplayServer.virtual_keyboard_show("")`, on submit `virtual_keyboard_hide()`), an Interrupt button visible while a turn streams, and a "New conversation" button sending `end_conversation`. History replay: on `history_received`, rebuild the transcript. Tool calls render as gray status lines ("Agent used set_display_param"). Spawn: MenuManager slot `"agent"`, screen_size `Vector2(2.2, 1.4)`, viewport_size `Vector2i(1100, 700)`, `preserve_content: true` (panel node owned by AscribeMain, re-shown on demand).

- [ ] **Step 1: Build the scene + script** (UI assembly; no unit tests — logic already tested in helpers). Keep ALL formatting logic in static funcs on the panel script (`format_user_line(text)`, `format_agent_line(text)`) and add `tests/test_agent_panel_format.gd` covering bbcode escaping of `[` in user text (use `[lb]`).
- [ ] **Step 2: gdUnit run PASS (format tests). Step 3:** Desktop smoke: run the app with XRSimulator (no headset needed) against a locally running `ascribe-link --enable-agent` if available, else against the fake server (Task 10); typing "hello" must round-trip. Record what you ran in the report.
- [ ] **Step 4: Commit** `feat(agent): in-world conversation panel`

---

### Task 9: Client — viewport capture

**Files (vr-start):**
- Create: `scripts/singletons/agent_capture.gd` (static helper)
- Modify: `scripts/singletons/agent_tool_dispatcher.gd` (implement `capture_viewport`), `scripts/UI/agent_panel.gd` (an "attach view" toggle: when on, every `send_text` is preceded by a capture + `send_screenshot`)
- Test: `tests/test_agent_capture.gd`

**Interfaces:**
- Produces: `AgentCapture.process_image(img: Image, max_dim: int = 1024, quality: float = 0.75) -> PackedByteArray` (pure: downscale keeping aspect if larger than max_dim, `save_jpg_to_buffer(quality)`); `AgentCapture.capture(viewport: Viewport, max_dim := 1024) -> PackedByteArray` (awaits `RenderingServer.frame_post_draw`, `viewport.get_texture().get_image()`, then `process_image`). The XR eye view is the root viewport (no SubViewport in this app — `menu_manager.gd:147` resolves the camera at `Main/XROrigin3D/XRCamera3D`).
- Dispatcher `capture_viewport` tool: `var jpeg := await AgentCapture.capture(get_viewport())`, reply `send_tool_result(request_id, {"ok": true})` AND `send_screenshot(jpeg)` (binary frame; server pairs it with the pending capture via the conversation's `attach_image` — server Task 3's capture tool awaits the next screenshot binary after the tool_result, manager handles ordering).

- [ ] **Step 1: Failing test for `process_image`** — a generated 2048×1024 gradient Image → result decodes (`Image.load_jpg_from_buffer`) to max dim 1024 with aspect preserved; an 800×600 image is not upscaled; buffer is non-empty and smaller than raw.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS. Step 5: Commit** `feat(agent): viewport capture for agent vision`

---

### Task 10: Fake agent server + end-to-end smoke + docs

**Files:**
- Create (ascribe-link): `tools/fake_agent_server.py` — runs the REAL app (`create_app(enable_agent=True, agent_client_factory=ScriptedFactory)`) on port 8000 with a scripted fake SDK: reply to any text with a canned streamed answer; if the text contains "darker", issue `tool_call set_display_param {index:0, name:"gamma", value:2.0}`; if it contains "look", issue `capture_viewport`. Run: `.venv\Scripts\python tools\fake_agent_server.py`.
- Modify (vr-start): `docs/developer-guide/index.md` — new "Agent conversation" section: architecture sketch, frame table, how to run the fake server, how to run gdUnit headless (with `--ignoreHeadlessMode`), what's deferred to the voice plan.

**Interfaces:** consumes everything.

- [ ] **Step 1: Implement the fake server** reusing `tests/fake_sdk.py`; verify with `python tools/fake_agent_server.py` + the Task 5 integration test client pointed at it (a 20-line `tools/smoke_ws_client.py` using `websockets` — connect, send text, print frames, assert agent_text arrives; run it, paste output).
- [ ] **Step 2: HUMAN CHECKPOINT — desktop end-to-end:** run fake server + vr-start with XRSimulator; type "hello" (reply streams), "make it darker" with a volume specimen open (gamma visibly changes on ALL peers if two instances are running), "look at this" (screenshot flows; fake server logs receipt + size). This checkpoint also stands in for multi-peer executor behavior (run two desktop instances in the same room if feasible).
- [ ] **Step 3: Docs. Step 4: Commit both repos** `feat(agent): fake agent server, smoke client, developer docs`

---

## Follow-up plan (not here): voice (bind button, mic Opus streaming via the `transmitaudiopacket` signal tap — never a second `AudioEffectOpusChunked` reader, faster-whisper STT, Kokoro TTS at 48 kHz/960-sample frames into a dedicated `AudioStreamOpusChunked`, barge-in), floor-control UX, local-launch subprocess mode, SceneManager god-object split, `/api/processing/invoke` deprecation.
