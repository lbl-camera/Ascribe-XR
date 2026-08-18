# Agent-Centric ascribe-xr — Design

**Date:** 2026-08-18
**Status:** Approved design, pre-implementation
**Repos touched:** vr-start (Godot client) and Ascribe-Link (Python service)

## Purpose

Evolve ascribe-xr from one-shot form-driven AI generation into a conversational,
voice-first agent experience: users in a shared VR room summon an agent via an
in-world button, talk to it, and it generates specimens, manipulates the scene,
adjusts visualization, analyzes data, and sees the user's viewport.

## Decisions (with rationale)

| Decision | Choice | Why |
|---|---|---|
| Harness location | One harness in ascribe-link, two launch modes: remote deployment or client-spawned local subprocess | Shared rooms need a peer-symmetric, room-scoped agent that survives peer churn; generation compute already lives server-side. Subprocess-of-client rejected as architecture (asymmetric agent host, duplicate Python service) but retained as a *launcher* for convenience. |
| Platform | Desktop-class only (Windows now; Linux/Steam Frame later). Quest standalone not a target for agent mode. | "Capabilities over compatibility" (Ron). Quest native perf is poor and still needs ascribe-link anyway. |
| Transport | Persistent WebSocket per client, `/ws/agent/{room_id}`; JSON frames + binary frames (audio, images) | Bidirectional push; survives a future web export; replaces 0.5 s HTTP polling for agent traffic (legacy job polling stays for non-agent dynamic specimens). |
| Invocation | Explicit in-world bind button; binding is exclusive per room, server-arbitrated | Button = floor control. No VAD arbitration, no open mic. |
| Multiplayer | Shared room from day one; agent messages/audio fan out to all room sockets; agent scene actions execute on one client and replicate via existing SceneManager RPCs | Room replication machinery already exists and is the app's full action space. |
| STT | faster-whisper, server-side, streaming partials; CPU int8 default, GPU optional (config) | Shared-room floor control needs server-side STT. Client-side godot-whisper GDExtension evaluated and not used. |
| TTS | Kokoro default (CPU, faster-than-realtime, MOS ~4.5); Orpheus as optional GPU backend behind a common TTS interface | Local-launch mode shares the GPU with volume rendering — CPU TTS avoids VRAM contention. Orpheus (expressive, ~200 ms streaming, GPU) suits remote deployments. Piper rejected (quality). |
| Python env | Vanilla `.venv` in the ascribe-link checkout; no uv | Ron's convention; uv added only provisioning convenience. |
| Client deps | No new GDExtensions. WebSocketPeer + viewport capture are core; twovoip (already vendored) covers Opus encode/decode. | |

## Protocol

One agent session per room, held in ascribe-link (Claude Agent SDK session
persists across turns — that is the conversation). Created on first bind,
kept warm, ended by explicit "new conversation" or room teardown. Server holds
transcript history so late-joining peers render the backlog.

**Client → server frames:** `bind`, `audio` (Opus chunks while bound),
`unbind`, `text` (typed fallback), `tool_result`, `screenshot` (JPEG binary),
`interrupt`.

**Server → all room sockets:** `speaker_bound`/`speaker_released`,
`transcript` (live STT partials + final), `agent_text` (streamed tokens),
`agent_audio` (TTS Opus chunks), `tool_call`, `status` ("thinking",
"using tool X"), `error`.

## Client (Godot)

- **`AgentSession` autoload** — owns WebSocketPeer, reconnect with backoff,
  signals (`agent_speaking`, `transcript_updated`, `tool_call_received`, …).
- **Conversation panel** — new in-world panel via MenuManager: scrolling
  transcript, live captions while bound speaker talks, agent status line.
  Built new; the existing schema-form UI (`procedural_link_ui`) stays for
  non-agent dynamic specimens.
- **Bind button** — wrist-mounted and on the panel. Press to bind (server may
  reject if held); release on toggle or ~2 s server-side silence endpoint.
  While bound: raw PCM tapped from the twovoip mic pipeline pre-encode,
  Opus-encoded, streamed. Pressing while agent speaks sends `interrupt`
  (barge-in: TTS stops everywhere, generation cancelled).
- **`AgentToolDispatcher`** — maps tool names to SceneManager RPCs, validates
  args, returns structured errors on bad calls. No arbitrary code execution.
- **`AgentVoice`** — decodes fanned-out TTS Opus, plays on a dedicated bus.

## Tool surface (server-side MCP toolset)

- **Server-executed (compute):** generate/iterate specimens (conversational
  refinement of prior results), analyze specimen data the server already holds
  (stats, histograms, thresholding, segmentation summaries) returning
  text/images/new specimens into the conversation.
- **Client-executed (scene), forwarded as `tool_call` to one designated
  executor client** (bound speaker's client; fallback oldest connection):
  `load_specimen`, `remove_specimen`, `set_active_specimen`, `set_room_scene`,
  `set_display_params` (gamma/opacity/gradient/exclusion planes/material),
  `transform_specimen`, `capture_viewport`. Executor invokes the SceneManager
  RPC so the action replicates to all peers, then returns `tool_result`.

## Vision

Agent-requested `capture_viewport` tool, plus optional auto-attach of a capture
with each user turn. Bound speaker's client grabs
`get_viewport().get_texture().get_image()`, downscales to ~1024 px, JPEG,
binary WS frame; server injects as an image block in the SDK session. In VR
this is the rendered eye view — literally what the user sees.

## Local-launch mode

If `Config.ascribe_link_url` is unreachable on desktop, offer "Start local
session": `OS.create_process` on
`<ascribe-link checkout>/.venv/Scripts/python -m ascribe_link --enable-agent`
(checkout path from a settings file), health-poll until up, connect, kill on
app exit. First run downloads STT/TTS models with progress in the panel.
Identical protocol to a lab deployment — no forked code paths.

GPU note: contention between TTS/STT and volume-texture memory exists only in
this mode. Kokoro-on-CPU default avoids it; Orpheus/GPU-whisper are per-server
config for deployments with GPU headroom.

## Targeted refactors (in scope — pain points, not a rewrite)

- Split `main.gd` (SceneManager, 419-line god object this work touches):
  extract **SpecimenLifecycle** (load/instantiate/remove; substrate for the
  tool dispatcher) and **JobRunner** (legacy polling path); SceneManager
  remains the thin RPC/replication surface.
- Deprecate the legacy one-shot `/api/processing/invoke` path (duplicates the
  job API).
- Resolve boot discrepancy: project boots `ascribemain.tscn` directly while
  docs describe XR-tools staging — standardize on staging, or fix the docs.

**Out-of-scope housekeeping (separate small PRs):** remove ~75 MB committed
data artifacts at repo root; enable gdUnit4 plugin in project.godot; fix Quest
preset `internet=false` / `record_audio=false`.

## Error handling

- WS drop → panel shows state, auto-reconnect with backoff, conversation
  resumes from server-held history.
- Agent/tool errors stream into the transcript as visible turns — never silent.
- Malformed `tool_call` → structured dispatcher error the agent can react to.
- Unreachable server → local-launch offer (desktop) or clear error.

## Testing

- Python (pytest): protocol framing, floor-control state machine, STT/TTS
  behind mocked model interfaces, SDK session lifecycle.
- Godot (gdUnit4): AgentToolDispatcher mapping + validation, WS frame parsing.
- End-to-end smoke test against a scripted fake-agent server.

## Build order

1. **Milestone 0 (risk-killer): text-only loop** — WS session, conversation
   panel with typed input, agent responds, one client-executed tool call
   changes the scene. No audio.
2. Full tool surface + vision (screenshots) + SceneManager refactor.
3. Voice: bind button, mic streaming, server STT, Kokoro TTS fan-out, barge-in.
4. Shared-room polish: floor control UX, late-join backlog, multi-peer testing.
5. Local-launch mode + Orpheus backend option.

## Out of scope (v1)

Quest standalone agent mode, client-side STT, VAD/open-mic invocation, agent
as WebRTC voice peer, web-export agent access (the WebVR viewer is explicitly
agent-free per its own spec).
