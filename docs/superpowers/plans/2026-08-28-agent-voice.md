# Agent Voice (spec milestone 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Voice conversation with the room agent: a Talk button binds the speaker, mic audio streams to the server, faster-whisper transcribes (live captions for everyone), the agent's reply comes back as Kokoro TTS audio played on every client, and pressing Talk mid-reply barges in.

**Architecture:** Builds directly on the shipped agent-conversation stack (both repos, branch `agent-conversation`). Server: the reserved protocol frames (`bind`/`unbind`/`audio`/`speaker_bound`/`speaker_released`/`transcript`/`agent_audio`) come alive; `AgentSessionManager` gains floor control and an utterance pipeline (accumulate PCM → VAD endpoint → transcript → `submit_text`); `AgentConversation`'s streamed text is sentence-chunked into a TTS worker whose PCM fans out to all room sockets. STT/TTS are injectable engines (fakes in tests, faster-whisper/kokoro-onnx real). Client: a dedicated `AgentMicBus` + `AudioEffectCapture` (never touching twovoip's `AudioEffectOpusChunked` — a second instance is a documented crash, `two_voip_mic.gd:107-110`), a Talk button + live captions on the agent panel, and an `AgentVoice` playback node using `AudioStreamGenerator`.

**Tech Stack:** Python: faster-whisper (int8 CPU default, built-in silero VAD), kokoro-onnx (+ onnxruntime CPU, espeakng-loader; model files `kokoro-v1.0.onnx` + `voices-v1.0.bin` auto-downloaded), numpy resampling. Godot 4.6: AudioEffectCapture, AudioStreamGenerator, existing WS binary framing.

**Spec:** `docs/superpowers/specs/2026-08-18-agent-centric-design.md` (milestone 3). **Deviation (ruled):** voice frames carry raw little-endian PCM16 mono over the WS, not Opus — avoids native codec deps in Python on Windows; 32–48 KB/s is negligible on LAN. Opus is a later optimization for WAN. **Deferred within milestone 3:** wrist-mounted button (panel button only, works in desktop + XR); streaming *partial* captions (v1 sends one `transcript` per utterance — a periodic-partial pass is a noted follow-up).

## Global Constraints

- Repos/branches: work continues on `agent-conversation` in BOTH `C:\Users\rp\Documents\ascribe-link` (canonical; Ron's PycharmProjects clone fast-forwards from it via remote `local-docs`) and `C:\Users\rp\Documents\vr-start`.
- Python: venv `.venv` (3.13) at ascribe-link root; run `.venv/Scripts/python -m pytest tests -q`. New deps go in a `voice` extra: `voice = ["faster-whisper>=1.1", "kokoro-onnx>=0.4", "onnxruntime>=1.20"]`. The server must start and pass tests WITHOUT the voice extra installed (lazy imports; `--voice` off ⇒ never imported); STT/TTS engines are injectable so no test loads a real model.
- Voice binary frames reuse the existing `<u32 LE header_len><JSON header><payload>` framing. Header contracts (normative): client→server audio `{"kind":"audio","rate":<int>,"format":"s16le","channels":1}`; server→client TTS `{"kind":"tts","rate":24000,"format":"s16le","channels":1,"seq":<int>}`. Existing `{"kind":"screenshot"}` binary handling must keep working.
- Frame types `bind`, `unbind` move from RESERVED to accepted client frames; `audio` remains binary-only (a TEXT frame `{"type":"audio"}` stays rejected). Server frames `speaker_bound{client_id}`, `speaker_released{}`, `transcript{text, client_id, final: true}`, `agent_audio_end{}` join SERVER_TYPES. The Godot helper mirrors all of this.
- Floor control: exclusive per room, server-arbitrated. `bind` while held by another → `error` frame "speaker slot is held". Bind while the agent is speaking = barge-in: cancel TTS + interrupt the turn, then grant the floor.
- Server-side endpointing: an utterance finalizes on `unbind`, OR after 2.0 s of trailing silence (VAD), OR at a 60 s hard cap.
- Never create a second `AudioEffectOpusChunked` and never call `drop_chunk()` on twovoip's effect (documented crash/contention, `addons/player-networking/twovoipr/two_voip_mic.gd:107-110, 212`). The agent path uses its own bus + `AudioEffectCapture`.
- Godot exe: `C:\Users\rp\Downloads\Godot_v4.6-stable_win64_console.exe`; gdUnit: `--headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode` (flag AFTER `-a`); `--import` after adding files; everything FOREGROUND. Current suites: ascribe-link 147, vr-start 73.
- Commits end with a blank line then `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## File structure

```
ascribe-link/ascribe_link/agent_ws/
├── protocol.py     MODIFY: unreserve bind/unbind, new server frame builders
├── audio.py        NEW: PCM16↔float32, resample-to-16k, RMS/silence helpers (pure numpy)
├── stt.py          NEW: STTEngine protocol + FasterWhisperSTT (lazy) + endpointing helper
├── tts.py          NEW: TTSEngine protocol + KokoroTTS (lazy, model auto-download) + sentence chunker
├── manager.py      MODIFY: floor control, utterance pipeline, TTS fan-out, barge-in
└── session.py      MODIFY: expose a per-turn text-stream hook for the TTS chunker
ascribe-link: cli.py (--voice, --stt-model, --tts-voice), app.py (thread flags), tools/fake_agent_server.py (fake voice engines)

vr-start/
├── scripts/singletons/agent_mic.gd        NEW: AgentMicBus capture → binary audio frames
├── scripts/singletons/agent_voice.gd      NEW: TTS playback via AudioStreamGenerator
├── scripts/singletons/agent_session.gd    MODIFY: bind/unbind sends, new frame signals, binary rx
├── scripts/singletons/agent_session_helpers.gd  MODIFY: decode_binary + new frame parsing
├── scripts/UI/agent_panel.gd              MODIFY: Talk button, captions, barge-in
└── tests/test_agent_audio_helpers.gd      NEW
```

---

### Task 1: Server — protocol: voice frames go live

**Files:**
- Modify: `ascribe_link/agent_ws/protocol.py`
- Test: `tests/test_agent_ws_protocol.py` (append)

**Interfaces:**
- Produces: `RESERVED_TYPES` becomes `set()` for `bind`/`unbind` (they move into `CLIENT_TYPES`; a TEXT `{"type":"audio"}` still rejected with the reserved message). New builders: `speaker_bound(client_id: int)`, `speaker_released()`, `transcript(text: str, client_id: int)` → `{"type":"transcript","text":...,"client_id":...,"final":True}`, `agent_audio_end()`. New binary header helpers: `audio_header(rate: int) -> dict` (`{"kind":"audio","rate":rate,"format":"s16le","channels":1}`) and `tts_header(seq: int) -> dict` (`{"kind":"tts","rate":24000,"format":"s16le","channels":1,"seq":seq}`).
- `validate_client_frame`: `bind`/`unbind` need no extras and are valid.

- [ ] **Step 1: Append failing tests**

```python
def test_bind_unbind_are_now_valid():
    assert p.validate_client_frame({"type": "bind"}) == ""
    assert p.validate_client_frame({"type": "unbind"}) == ""


def test_text_audio_frame_still_rejected():
    assert "reserved" in p.validate_client_frame({"type": "audio"})


def test_voice_builders():
    assert p.speaker_bound(3) == {"type": "speaker_bound", "client_id": 3}
    assert p.speaker_released() == {"type": "speaker_released"}
    assert p.transcript("hello", 2) == {
        "type": "transcript", "text": "hello", "client_id": 2, "final": True}
    assert p.agent_audio_end() == {"type": "agent_audio_end"}
    assert p.audio_header(44100) == {
        "kind": "audio", "rate": 44100, "format": "s16le", "channels": 1}
    assert p.tts_header(7)["seq"] == 7 and p.tts_header(7)["rate"] == 24000
```

- [ ] **Step 2: Run — FAIL.** `.venv/Scripts/python -m pytest tests/test_agent_ws_protocol.py -q`
- [ ] **Step 3: Implement** (move types between sets; keep the audio-as-text rejection special-cased). **Step 4: PASS + full suite. Step 5: Commit** `feat(agent-ws): activate bind/unbind and voice frame builders`

---

### Task 2: Server — audio utilities (pure)

**Files:**
- Create: `ascribe_link/agent_ws/audio.py`
- Test: `tests/test_agent_ws_audio.py`

**Interfaces:**
- Produces: `pcm16_to_float32(data: bytes) -> np.ndarray` (float32 in [-1,1]); `float32_to_pcm16(arr) -> bytes`; `resample(arr: np.ndarray, src_rate: int, dst_rate: int) -> np.ndarray` (np.interp linear; identity when rates equal); `trailing_silence_s(arr: np.ndarray, rate: int, threshold: float = 0.01) -> float` (seconds of samples below RMS threshold at the tail, computed on 50 ms windows).

- [ ] **Step 1: Failing tests** — round-trip pcm16→float→pcm16 within ±1 LSB; float 1.0/-1.0 clamps to 32767/-32768; resample 48000→16000 of a 1 kHz sine keeps length ratio 1/3 (±1) and stays a sine (zero crossings ≈ expected ±2); identity resample returns same array; `trailing_silence_s` on [0.5 s tone + 1.0 s zeros] @16 kHz returns ≈1.0 (±0.06); all-silence returns full duration.
- [ ] **Step 2: FAIL. Step 3: Implement (numpy only). Step 4: PASS. Step 5: Commit** `feat(agent-ws): PCM conversion, resampling, silence measurement`

---

### Task 3: Server — STT engine (injectable) + utterance accumulator

**Files:**
- Create: `ascribe_link/agent_ws/stt.py`
- Test: `tests/test_agent_ws_stt.py`
- Modify: `pyproject.toml` (add the `voice` extra)

**Interfaces:**
- Produces:
  - `class STTEngine(Protocol): def transcribe(self, audio_16k: np.ndarray) -> str` (float32 mono 16 kHz in, text out; blocking, called via `asyncio.to_thread` by the manager).
  - `class FasterWhisperSTT(STTEngine)` — `__init__(model_size: str = "small", device: str = "cpu", compute_type: str = "int8")`; lazy `from faster_whisper import WhisperModel` inside `_ensure_model()`; `transcribe` runs with `vad_filter=True` and joins segment texts.
  - `class UtteranceBuffer` — `__init__(rate_hint: int = 48000)`; `add(payload: bytes, rate: int) -> None` (converts+resamples to 16 k float32 and appends); `duration_s: float`; `should_finalize(silence_s: float = 2.0, max_s: float = 60.0) -> bool` (uses `audio.trailing_silence_s`, only after ≥0.5 s of audio); `take() -> np.ndarray` (returns 16 k audio and resets).

- [ ] **Step 1: Failing tests** — UtteranceBuffer: feeding 0.5 s of 48 kHz tone yields `duration_s`≈0.5; tone+2.1 s silence → `should_finalize()` True; tone only → False; `take()` resets (duration 0 after). FasterWhisperSTT: constructing does NOT import faster_whisper (assert `"faster_whisper" not in sys.modules` after `FasterWhisperSTT()` — laziness is the testable part; actual transcription is exercised at the human checkpoint). A `FakeSTT` used by later tasks lives in `tests/fake_voice.py`: `transcribe` returns `"FAKE(<n> samples)"` — create it here with a trivial test.
- [ ] **Step 2: FAIL. Step 3: Implement + pyproject `voice` extra. Step 4: PASS + full suite. Step 5: Commit** `feat(agent-ws): injectable STT engine and utterance buffer`

---

### Task 4: Server — TTS engine (injectable) + sentence chunker

**Files:**
- Create: `ascribe_link/agent_ws/tts.py`
- Test: `tests/test_agent_ws_tts.py`
- Modify: `tests/fake_voice.py` (add FakeTTS)

**Interfaces:**
- Produces:
  - `class TTSEngine(Protocol): def synthesize(self, text: str) -> np.ndarray` (float32 mono 24 kHz out; blocking, manager calls via `asyncio.to_thread`).
  - `class KokoroTTS(TTSEngine)` — `__init__(voice: str = "af_heart", model_dir: str | None = None)`; lazy `from kokoro_onnx import Kokoro`; `_ensure_model()` downloads `kokoro-v1.0.onnx` and `voices-v1.0.bin` (URLs from the kokoro-onnx release assets, `urllib.request.urlretrieve`) into `model_dir or platformdirs-style ~/.cache/ascribe-link/kokoro/` with an INFO log line per file; synthesize returns the float32 array resampled to 24 kHz if Kokoro's native rate differs.
  - `class SentenceChunker` — `feed(text_delta: str) -> list[str]` (accumulates streamed deltas, emits complete sentences on `.`, `!`, `?`, `\n` followed by space/end, minimum 3 chars); `flush() -> str` (remainder).
  - `FakeTTS.synthesize` returns a 0.1 s 440 Hz sine at 24 kHz.

- [ ] **Step 1: Failing tests** — SentenceChunker: `feed("Hello the")+feed("re. How")` → `["Hello there."]`, then `feed(" are you? I")` → `["How are you?"]`, `flush()` → `"I"`; abbreviation-ish "3.14 is pi." emits once, not at "3."  (rule: sentence break needs terminator + space/end AND ≥3 chars since last break — encode exactly that, no smarter). KokoroTTS: constructing does not import kokoro_onnx; `synthesize` raises a clear RuntimeError naming `pip install -e .[voice]` when the import fails. FakeTTS: returns 2400 samples, non-silent.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS. Step 5: Commit** `feat(agent-ws): injectable TTS engine and sentence chunker`

---

### Task 5: Server — floor control, utterance pipeline, TTS fan-out, barge-in

**Files:**
- Modify: `ascribe_link/agent_ws/manager.py`, `ascribe_link/agent_ws/session.py`, `ascribe_link/app.py`, `ascribe_link/cli.py`
- Test: `tests/test_agent_ws_voice_integration.py`

**Interfaces:**
- Consumes: Tasks 1–4; existing manager internals (`_RoomState`, `client_ids`, `handle_frame`, `handle_binary`, capture FIFO — screenshot handling must be untouched).
- Produces:
  - `AgentSessionManager.__init__` gains `stt: STTEngine | None = None, tts: TTSEngine | None = None` (None ⇒ voice frames answered with `error("voice is not enabled on this server")`).
  - Floor control in `handle_frame`: `bind` → if free (or held by the SAME socket) grant: `room.speaker = socket`, fresh `UtteranceBuffer`, broadcast `speaker_bound(client_id)`; if held by another → `error` to sender only. If the agent is currently speaking (TTS task running), `bind` FIRST cancels TTS + `conversation.interrupt()` + broadcast `agent_audio_end()`, then grants (barge-in). `unbind` (or the speaker's disconnect) → finalize the utterance if non-trivial, broadcast `speaker_released()`.
  - `handle_binary` with header `kind=="audio"`: reject unless sender holds the floor (`error` to sender); else `buffer.add(payload, header["rate"])`; then `if buffer.should_finalize(): await self._finalize_utterance(room)`. `_finalize_utterance`: `text = await asyncio.to_thread(stt.transcribe, buffer.take())`; empty text → `status("(silence)")` to speaker only + release floor; else broadcast `transcript(text, client_id)`, release floor (broadcast `speaker_released`), and `submit_text(text)` exactly like a typed turn.
  - TTS fan-out: `session.AgentConversation.__init__` gains `on_text_delta: Callable[[str], None] | None = None`, called (via `_safe_emit` guard pattern) with each streamed text delta before the `agent_text` emit. The manager wires it into a `SentenceChunker`; each complete sentence is queued to a per-room `_tts_task` (single asyncio task draining an `asyncio.Queue`): `pcm = await asyncio.to_thread(tts.synthesize, sentence)`, then broadcast BINARY `encode_binary(protocol.tts_header(seq), audio.float32_to_pcm16(pcm))` to all room sockets. On `agent_text_done` (manager observes it in its emit path) → `chunker.flush()` final fragment → queue → after the queue drains, broadcast `agent_audio_end()`. Barge-in/`interrupt` cancels the task, clears the queue, broadcasts `agent_audio_end()`.
  - `cli.py`: `--voice` (store_true), `--stt-model` (default "small"), `--tts-voice` (default "af_heart"); `create_app(..., stt_engine=None, tts_engine=None)` test seam; when `--voice` and no injected engines, construct the real ones (ImportError → clear log naming `pip install -e .[voice]`, voice stays disabled, server still starts).
- **Ordering rule (normative):** TTS binary frames for a turn are sequenced (`seq` from 0 per turn) and sent from the single drain task, so clients receive them in order; `agent_audio_end` is sent only after the last sentence of the turn.

- [ ] **Step 1: Failing integration tests** (AsyncTestClient + FakeSDK factory + `tests/fake_voice.py` engines): (a) bind → `speaker_bound` broadcast with the binder's client_id; second client's bind → error "held"; (b) audio binary from a non-speaker → error; (c) bind, send 0.6 s tone + 2.1 s silence (build PCM16 bytes with numpy) → receives `transcript` containing "FAKE", then `speaker_released`, then the fake agent's `agent_text` (the transcript reached submit_text); (d) a scripted turn's reply produces ≥1 binary frame with header kind "tts", rate 24000, in-order `seq`, followed by `agent_audio_end` after `agent_text_done`; (e) bind while TTS is mid-stream (gate FakeTTS on an event) → `agent_audio_end` arrives and the floor is granted (`speaker_bound`); (f) server without engines: bind → error "voice is not enabled"; (g) screenshot binary still routes to attach_image (no regression).
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS + full suite. Step 5: Commit** `feat(agent-ws): voice floor control, STT pipeline, TTS fan-out, barge-in`

---

### Task 6: Client — mic capture on a dedicated bus

**Files:**
- Create: `scripts/singletons/agent_mic.gd` (`class_name AgentMic extends Node`, autoload after AgentSession)
- Modify: `scripts/singletons/agent_session.gd` (add `send_bind()`, `send_unbind()`, `send_audio(pcm16: PackedByteArray, rate: int)` using `AgentSessionHelpers.encode_binary(AgentSessionHelpers.audio_header(rate), pcm16)`), `scripts/singletons/agent_session_helpers.gd` (add `audio_header(rate: int) -> Dictionary` and static `frames_to_pcm16_mono(frames: PackedVector2Array) -> PackedByteArray` — average L/R, clamp, 16-bit LE), `project.godot` (autoload)
- Test: `tests/test_agent_audio_helpers.gd`

**Interfaces:**
- Produces: `AgentMic.start_capture()` — creates (once) an audio bus "AgentMicBus" (`AudioServer.add_bus`, muted send to Master? NO — set bus mute ON so the mic isn't audible; `AudioServer.set_bus_mute(idx, true)`), adds an `AudioEffectCapture` (buffer 0.5 s), and an `AudioStreamPlayer` playing `AudioStreamMicrophone` routed to that bus; `stop_capture()` stops the player. While capturing, `_process` drains `capture.get_buffer(capture.get_frames_available())` every frame, converts via `frames_to_pcm16_mono`, and calls `AgentSession.send_audio(pcm, int(AudioServer.get_mix_rate()))` in ≤4096-frame chunks. NEVER touches the MicrophoneBus or twovoip's effect.
- Risk note (verify at the human checkpoint, step also in Task 9): a second `AudioStreamMicrophone` alongside twovoip's is expected to work (shared input feed) — if the capture buffer stays empty on-device while voice chat is active, the fallback is routing the player only while unbound from voice chat; surface loudly in the report if observed locally.

- [ ] **Step 1: Failing gdUnit tests for `frames_to_pcm16_mono`** — stereo frames [(1.0,0.0)] → 16383±1; [(-1.0,-1.0)] → -32768; empty → empty; length = 2 bytes/frame. And `audio_header(44100)` dict equality.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS (full gdUnit). Step 5: Commit** `feat(agent): dedicated mic capture bus streaming PCM16 to the agent WS`

---

### Task 7: Client — TTS playback

**Files:**
- Create: `scripts/singletons/agent_voice.gd` (`class_name AgentVoice extends Node`, autoload after AgentMic)
- Modify: `scripts/singletons/agent_session.gd` (route incoming BINARY frames: parse with `AgentSessionHelpers.decode_binary`; header kind "tts" → new signal `tts_audio(header: Dictionary, pcm: PackedByteArray)`; add signals `speaker_bound(client_id: int)`, `speaker_released()`, `transcript_received(text: String, client_id: int)`, `agent_audio_ended()` parsed from the new text frames), `scripts/singletons/agent_session_helpers.gd` (add `decode_binary(data: PackedByteArray) -> Dictionary` returning `{"header": Dictionary, "payload": PackedByteArray}` or `{"error": String}` — mirror of encode)
- Test: `tests/test_agent_audio_helpers.gd` (append decode tests)

**Interfaces:**
- Produces: `AgentVoice` — owns an `AudioStreamPlayer` with `AudioStreamGenerator` (`mix_rate` set from the first tts header's rate, `buffer_length` 0.5); on `tts_audio`, converts PCM16 LE → frames (`Vector2(v, v)`) and `push_buffer`s into the `AudioStreamGeneratorPlayback` (drop with a push_warning if `get_frames_available()` is insufficient — do not block); on `agent_audio_ended` or `AgentSession.error_received`, `stop()` + restart the stream (clears the ring buffer). Property `is_playing_agent_audio: bool` (playing and frames pushed since last end) — the panel uses it for barge-in affordance.

- [ ] **Step 1: Failing gdUnit tests** — `decode_binary(encode_binary(h, p))` round-trips; truncated data → error dict; a static `pcm16_to_frames(pcm: PackedByteArray) -> PackedVector2Array` on AgentVoice: 2 bytes → 1 frame, 32767 → ≈1.0, -32768 → -1.0.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS. Step 5: Commit** `feat(agent): TTS audio playback via AudioStreamGenerator`

---

### Task 8: Client — Talk button, captions, barge-in on the panel

**Files:**
- Modify: `scripts/UI/agent_panel.gd`, `scenes/UI/agent_panel.tscn`

**Interfaces:**
- Consumes: AgentSession signals from Task 7, `AgentMic.start_capture/stop_capture`, `AgentVoice.is_playing_agent_audio`.
- Produces: a `Talk` toggle button in the input row: pressed → `AgentSession.send_bind()` (mic starts only on `speaker_bound` for OUR client_id — the server is the authority); released → `send_unbind()` + `stop_capture()`. Button states: normal "Talk"; while we hold the floor: "Listening…" (red modulate) + captions area shows a live "…" placeholder; while ANOTHER client holds it: disabled with "(<id> speaking)"; while `AgentVoice.is_playing_agent_audio`: label "Interrupt & talk" (pressing = barge-in — just send_bind, the server handles cancel). `transcript_received` renders into the transcript exactly like a typed user line (prefixed with `You` when client_id matches ours, else `Peer <id>`); `speaker_released` clears listening state and stops capture if we held it.

- [ ] **Step 1: Implement** (UI wiring; keep any new pure formatting in the panel's static funcs and extend `tests/test_agent_panel_format.gd` with the `Peer <id>` prefix case, TDD for that one function).
- [ ] **Step 2: gdUnit PASS (full). Step 3:** Headless parse check (`--import` clean). **Step 4: Commit** `feat(agent): Talk button with floor states, live captions, barge-in`

---

### Task 9: Fake voice server, smoke, docs, human checkpoint

**Files:**
- Modify: `tools/fake_agent_server.py` (wire `tests/fake_voice.py` engines via the `create_app` seams: FakeSTT returns "make it darker" so the voice path drives the scripted tool flow; FakeTTS beep), `tools/smoke_ws_client.py` (add a `--voice` mode: bind → send 1 s of synthetic tone PCM + 2.2 s silence → expect speaker_bound, transcript, tts binary frames, agent_audio_end), vr-start `docs/developer-guide/index.md` (voice section: frame additions, dependency install `pip install -e .[voice]`, model downloads, `--voice` flag, PCM-not-Opus deviation and rationale, known risk: dual mic streams alongside twovoip)
- Test: run the smoke yourself (foreground; paste output)

**Interfaces:** consumes everything.

- [ ] **Step 1: Fake server + smoke client; run the smoke, paste output.** Also run the FULL ascribe-link suite and full gdUnit suite; paste summaries.
- [ ] **Step 2: Commit** both repos: `feat(agent-ws): fake voice engines + voice smoke mode` / `docs: agent voice developer guide`.
- [ ] **Step 3: HUMAN CHECKPOINT (Ron):** real server `--enable-agent --voice` (after `pip install -e .[voice]`; first run downloads whisper-small + kokoro models). In ascribe-xr: hold Talk, say "hello", release (or wait 2 s) → caption appears, agent replies in Kokoro's voice; say "make it darker" with a volume loaded → gamma changes; press Talk mid-reply → audio stops immediately and it listens. Verify voice chat (twovoip) still works simultaneously — the dual-mic-stream risk.

## Out of scope (follow-ups, not this plan)

Opus voice transport (WAN), streaming partial captions, wrist-mounted bind button, Orpheus TTS backend, local-launch subprocess mode, VOX/wake-word, per-speaker voice identity to the agent.
