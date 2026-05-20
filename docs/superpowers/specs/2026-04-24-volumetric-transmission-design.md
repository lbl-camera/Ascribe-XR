# Volumetric Data Transmission — ascribe-link → ascribe-xr

**Date:** 2026-04-24
**Status:** Design (pre-implementation)
**Scope:** Two repos — server (`ascribe-link`) and client (`ascribe-xr` / this repo `vr-start`). Work proceeds in paired worktrees.

## Goal

Enable volumetric data (`numpy.ndarray`, typically float32, 64³–256³) to travel end-to-end from ascribe-link to the in-VR specimen, matching the existing dynamic-specimen flow used for meshes. Support:

- **Parametric volume specimens** (built-in, no client-code changes to add new ones).
- **Static volume specimens** (drop `.npy` + optional `.json` sidecar into a specimen bundle).
- **AI Generate** output as either mesh or volume (auto-detected from the agent's return value).

Also fix the current **JSON-encoded large-mesh size limit** by moving meshes to the same binary envelope format — volumes and meshes share one wire format for the in-VR `/data` flow.

## Non-goals

- Multi-channel/RGB/vector volumes (single scalar field only).
- Multiplayer RPC sync of local file-pick volumes (peers that pick a local `.npy` in VR see it locally; peers that want shared volumes go through ascribe-link like dynamic meshes do).
- Streaming/chunked partial volumes. One volume, one HTTP response.
- Changing `/api/processing/invoke` (stays JSON-dict for tooling / REPL / language parity).

## Wire format — unified binary envelope

The `/api/specimens/{id}/data` endpoint returns **`Content-Type: application/x-ascribe-envelope-v1`** for **both** mesh and volume specimens that come from a `Result` object (dynamic or static-via-numpy), using a single envelope body:

```
<4-byte little-endian uint32: preamble_length>
<preamble_length bytes: UTF-8 JSON preamble>
<raw bytes: one or more contiguous data blocks>
```

### Mesh preamble

```json
{
  "type": "mesh",
  "vertex_count": N, "vertex_dtype": "float32",
  "index_count":  M, "index_dtype":  "uint32",
  "normal_count": K, "normal_dtype": "float32"
}
```

Data blocks follow in order: vertices (`N*3*4` bytes), indices (`M*4` bytes), normals (`K*3*4` bytes). Any `_count` of `0` means the block is omitted.

### Volume preamble

```json
{
  "type": "volume",
  "shape":   [D, H, W],
  "dtype":   "float32",
  "spacing": [sz, sy, sx],
  "origin":  [oz, oy, ox]
}
```

Single data block of `D*H*W * bytes_per_voxel` bytes, row-major (C-contiguous), shape order `[D, H, W]`.

### Rationale

- **No base64** — 33 % payload savings and zero server-side encode / client-side decode cost for the hot path.
- **No list-of-floats JSON** — GDScript parsing of a 500 k-element float list is the current mesh-size bottleneck.
- **Self-describing body** — the bytes can be `.save()`'d to disk and re-read without HTTP context. HTTP headers would need out-of-band association for that.
- **One format for both kinds** — one envelope parser, one dispatch point on `preamble.type`.
- **Custom media type** — `application/x-ascribe-envelope-v1` distinguishes envelope responses from raw static mesh files (STL/OBJ/FBX), which the server still serves as-is with `application/octet-stream` + `Content-Disposition: attachment`. The client branches on content-type.
- **Existing JSON path kept** — `/api/processing/invoke` stays JSON-dict (REPL / non-Godot tooling). `VolumetricData.set_from_dict` and `MeshData.set_from_dict` remain as-is for that endpoint.

### Content-type matrix

| Source | Response content-type | Client handling |
|---|---|---|
| Dynamic mesh / volume (`/data`) | `application/x-ascribe-envelope-v1` | `BinaryEnvelope.parse` → `set_from_bytes` |
| Static volume (`.npy` via `/data`) | `application/x-ascribe-envelope-v1` | same |
| Static mesh file (`.stl`/`.obj`/`.fbx` via `/data`) | `application/octet-stream` + `Content-Disposition: attachment` | write to temp file, run through existing file pipeline |
| Any result via `/api/processing/invoke` | `application/json` | `set_from_dict` (legacy path) |

## On-disk format for static volume specimens

`.npy` + optional `.json` sidecar:

```
specimens/<id>/
├── data.npy          # numpy array, any 3D dtype the client can render (uint8, float32, uint16→normalized, float64→float32)
├── data.json         # optional: {"spacing": [sz, sy, sx], "origin": [oz, oy, ox]}
├── metadata.json     # existing: display_name, description, type="volume", data_file="data.npy", tags, story_text
└── thumbnail.png     # existing (optional)
```

If `data.json` is absent, `spacing=[1,1,1]` and `origin=[0,0,0]`. `SpecimenStore` recognizes `.npy` as a volume data file regardless of `metadata.type` (though the two should agree).

Server loads the `.npy` via `np.load(path, mmap_mode='r')` on each request, wraps in `VolumeResult`, serializes via the envelope. Caching at the `RoomResultCache` layer is by-specimen for static files (no parameter key).

## Architecture

### Data flow (dynamic volume specimen, e.g. Parametric Gaussian)

```
User picks "Parametric Gaussian Volume" in VR
  → ProceduralLinkUI form (schema from server)
  → submit → SceneManager.request_submit (submitter) / specimen_job_submitted.rpc (all peers)
  → submitter: AscribeLinkClient.run_job → POST /start → poll /progress → GET /result
  → submitter: specimen_job_done.rpc (all peers)
  → each peer: SceneManager._fetch_and_load_result
      → read meta.type → instantiate volume_specimen.tscn
      → set data_url = "<base>/api/specimens/parametric_gaussian/data?params=...&room_id=..."
      → specimen enters tree, HTTPRequest fires
      → server: RoomResultCache hit → encode_binary_envelope(volume_result) → octet-stream
      → specimen: parse_envelope → VolumetricData.set_from_bytes → ImageTexture3D → shader
```

### Data flow (static volume specimen)

Same as above minus the procedural UI and job run. `SceneManager.load_specimen` (static path) sets `data_url` on the instantiated scene instead of loading a bundled file.

### Data flow (AI Generate → volume)

Same as dynamic, but the registered function is `agent_generate` and its tool surface now accepts volume-producing code. On completion the agent's Python output is inspected: `VolumeResult` / `numpy.ndarray` (3D) → wrapped as volume; `MeshResult` / `pyvista.*` → wrapped as mesh. The specimen-type dispatch happens server-side at result time.

## Component changes

### Server — `ascribe-link`

**`ascribe_link/models.py`**
- Add `MeshResult.to_bytes() -> bytes` (concatenation of vertex/index/normal bytes) and keep `MeshResult.vertices/indices/normals` as-is; the existing `list[float]`/`list[int]` typing stays for `to_dict()` compatibility, but the binary path uses `np.asarray(self.vertices, dtype=np.float32).tobytes()` directly — no data-model change.
- Add `VolumeResult.to_bytes() -> bytes` (single raw buffer). Keep the dataclass field `data: str` for base64 — **add a parallel `_array: np.ndarray | None` attribute** populated by `from_numpy` that holds the raw array. `to_bytes()` prefers `_array` if present, else base64-decodes `data`. `to_dict()` continues to emit base64. Backward compatible: callers that construct `VolumeResult(data=<base64>)` still work; `to_dict()` output unchanged.
- New module `ascribe_link/envelope.py`: `encode_envelope(result: MeshResult | VolumeResult) -> bytes` and `decode_envelope(data: bytes) -> MeshResult | VolumeResult` (decoder primarily for tests and Python consumers).
- Tests: `tests/test_envelope.py` round-trips synthetic arrays.

**`ascribe_link/parametric.py`**
- New `generate_gaussian_volume(resolution: int = 64, sigma: float = 0.3) -> VolumeResult`. Pure numpy. Resolution clamped to `[32, 256]`, sigma to `[0.05, 1.0]`. Returns float32.

**`ascribe_link/app.py`**
- Register `generate_gaussian_volume` with `return_type="volume"`, `display_name="Parametric Gaussian Volume"`, `tags=["parametric", "volume", "dynamic"]`.
- AI Generate registration: drop the `"mesh"` tag, change `return_type` to `None` (registry accepts either).

**`ascribe_link/specimen_store.py`**
- Recognize `.npy` as a valid `data_file` for `SpecimenType.VOLUME`. Add helper `load_volume(path: Path) -> VolumeResult` that handles `.npy` + sidecar, returns a `VolumeResult`.

**`ascribe_link/routes/specimens.py`**
- `_get_data_impl`: when the result is a `MeshResult` or `VolumeResult` (in-memory, from dynamic invocation or static-`.npy` load), return `Response(content=encode_envelope(result), media_type="application/x-ascribe-envelope-v1")`. Static mesh files (STL/OBJ/FBX) keep returning `File()` with `application/octet-stream` — the existing pipeline handles those directly without going through `MeshResult`.

**Cache shape change** — `RoomResultCache` today stores `dict` (the base64-JSON-ready result). Change it to store the raw `MeshResult | VolumeResult` object, plus a cached envelope bytes blob alongside (built lazily on first envelope fetch). `/api/processing/invoke` pulls the cached object and calls `result_to_dict()` for its JSON response; `/api/specimens/{id}/data` pulls the cached envelope bytes (or builds and caches them on miss). This avoids re-serializing on each request while keeping both wire formats cheap.

**`ascribe_link/job_registry.py`**
- `Job.result` field type widens from `dict | None` to `MeshResult | VolumeResult | None`. `_run_job` in `specimens.py` stores the raw result, not `result_dict`.

**`ascribe_link/agent_generator.py`**
- After the agent produces output, inspect the return value: `VolumeResult` → use as-is; `MeshResult` → use as-is; `numpy.ndarray` with `ndim == 3` → wrap via `VolumeResult.from_numpy`; `pyvista.*` mesh → wrap via `MeshResult.from_pyvista`; anything else → error.

### Client — `vr-start` (ascribe-xr)

**New: `scripts/DataSources/binary_envelope.gd`**
```gdscript
class_name BinaryEnvelope
static func parse(body: PackedByteArray) -> Dictionary:
    # Returns {"preamble": Dictionary, "offset": int} or {"error": String}
```
Decodes 4-byte LE uint32 length, then UTF-8 JSON preamble, returns the post-preamble offset.

**`scripts/DataClasses/mesh_data.gd`**
- Add `set_from_bytes(preamble: Dictionary, body: PackedByteArray, offset: int) -> bool` — slices `body` into `vertices`, `indices`, `normals` `Packed*Array`s using `slice().to_float32_array()` / `to_int32_array()` (Godot 4.3+ supports these on `PackedByteArray`). No `Array[float]` allocation.

**`scripts/DataClasses/volumetric_data.gd`**
- Add `set_from_bytes(preamble: Dictionary, body: PackedByteArray, offset: int) -> bool` — extracts `shape`/`dtype`/`spacing`/`origin`, iterates depth slices, each slice → `Image.create_from_data` with the right `Image.FORMAT_*`, builds `ImageTexture3D`. Emits `data_ready`.
- Keep `set_from_dict` for `/api/processing/invoke` path (unchanged).

**`scripts/Specimen/mesh_specimen.gd` — `_on_data_url_completed`**
- Content-type dispatch:
  - `application/x-ascribe-envelope-v1` → `BinaryEnvelope.parse(body)` → verify `preamble.type == "mesh"` → `MeshData.new().set_from_bytes(preamble, body, offset)` → `_set_mesh_from_data(mesh_data)`.
  - `application/json` → keep existing `_load_from_result_dict` (legacy).
  - `application/octet-stream` (with `Content-Disposition: attachment`) → keep existing temp-file + pipeline path for static STL/OBJ/FBX.
- The envelope branch is the new dynamic-mesh hot path; the JSON branch becomes cold (kept for back-compat with older servers).

**`scripts/Specimen/volumetric_specimen.gd`**
- Add `@export var data_url: String = ""` and `_load_from_data_url` + `_on_data_url_completed` parallel to `MeshSpecimen`'s (HTTPRequest with progress UI).
- On completion: `BinaryEnvelope.parse` → verify `preamble.type == "volume"` → `VolumetricData.new().set_from_bytes(preamble, body, offset)` → install `ImageTexture3D` on the `VolumeLayeredShader` mesh instance → enable pickables, swap UI layers.
- `_enter_tree` logic: if `data_url` set, skip file dialog and start HTTP load.

**`scripts/singletons/main.gd` — `SceneManager._fetch_and_load_result`** (dynamic-post-job flow only)
- Currently hardcodes `res://specimens/mesh_specimen.tscn`. Change to branch on `meta.type`:
  - `"mesh"` → `res://specimens/mesh_specimen.tscn`
  - `"volume"` → `res://specimens/volume_specimen.tscn`
- Set `data_url` on the instantiated scene the same way (existing logic).
- Everything else (`_reset_world`, `_position_specimen`, `hide_mainmenu`) identical.

**Static server-backed specimens require no SceneManager or main-menu changes.** `scripts/UI/mainmenuflat.gd:_load_remote_specimen` already dispatches on `specimen_list_item.type`, already references `res://specimens/volume_specimen.tscn` for the volume branch, and already sets `data_url` in the config passed to `SceneManager.load_specimen.rpc`. The existing path becomes functional for static volumes once `VolumeSpecimen` honors the `data_url` config (change above).

### No changes

- `Pipeline.gd` — stays file-source-focused for local file picks.
- `SyncronousLoader.gd`, `ThreadedLoader.gd` — unchanged.
- `HTTPSource.gd`, `AscribeLinkClient` — the new envelope format goes through `HTTPRequest` directly in the specimen scripts, same pattern `MeshSpecimen._load_from_data_url` uses today.
- `VolumetricData.set_from_dict` — kept for the `/api/processing/invoke` legacy path.
- Chunked mesh RPC sync — unchanged, only used for local-file-pick sync which is orthogonal.

## Multiplayer

**Per-peer server fetch, same as dynamic mesh specimens today.** The submitter runs the job; every peer (including the submitter) hits `/api/specimens/{id}/data?params=...&room_id=...`. The server's `RoomResultCache` serves the same volume bytes to each peer. No RPC chunking for volumes.

Local-file-pick volumes (user picks an `.npy` via the VR file dialog) stay local to that peer. If the user wants volumes shared, they publish through ascribe-link.

## Error handling

- **Preamble length mismatch** (body shorter than `4 + preamble_length`): XR client aborts with loading-layer hidden and `push_error`; server tests cover this with a truncation fixture.
- **`preamble.type` mismatch** (mesh specimen gets a volume envelope or vice versa): each specimen verifies and errors explicitly rather than trying to interpret mixed bytes.
- **Unsupported dtype** on the client: `VolumetricData.set_from_bytes` falls back to the same dtype handling `set_from_dict` does today (uint8→L8, float32→RF, uint16→normalized L8, float64→float32, other→float32 with warning).
- **HTTP failure** (timeout, 5xx): existing `MeshSpecimen`/`VolumeSpecimen` error flows re-used — hide loading layer, `push_error`, leave specimen in the not-loaded state.
- **Dimension clamp**: server rejects volumes with any axis > 512 or total > 256³ voxels in the Gaussian function and the static-load path. Larger volumes need explicit opt-in (out of scope for this PR; leave a TODO).

## Testing

### Server

- `tests/test_envelope.py` — round-trip mesh and volume `encode_envelope` / `decode_envelope` for synthetic arrays (float32 volumes, uint8 volumes, meshes with and without normals).
- `tests/test_parametric_volume.py` — `generate_gaussian_volume` at default / min / max params returns correct shape and dtype.
- `tests/test_static_volume.py` — fixture specimen dir with `data.npy` + `data.json`; HTTP `GET /api/specimens/<id>/data`; parse envelope; verify bytes match source array.
- `tests/test_agent_dispatch.py` — mock agent returns a `numpy.ndarray` (3D) and a `pyvista.Sphere`; registry wraps each correctly.

### Client

- `tests/gdunit/test_binary_envelope.gd` — parse synthetic bytes (valid, truncated, invalid JSON preamble).
- `tests/gdunit/test_mesh_data_bytes.gd` — `MeshData.set_from_bytes` round-trip (synthesize bytes matching a known preamble, verify `PackedFloat32Array` and `PackedInt32Array` contents).
- `tests/gdunit/test_volumetric_data_bytes.gd` — `VolumetricData.set_from_bytes` produces the right-sized `ImageTexture3D` with the right format.

### Manual E2E (golden path)

1. Start ascribe-link from its worktree: `python -m ascribe_link`.
2. Open Godot on the vr-start worktree, run the project (no headset needed — flat mode).
3. Main menu → "Parametric Gaussian Volume" → submit with default params → volume loads and renders in the `VolumeLayeredShader`.
4. Main menu → static volume specimen (drop a sample `brain.npy` into `specimens/brain_volume/`) → loads and renders.
5. Main menu → AI Generate → prompt "a 3D Gaussian blob at 64 cubed" → agent emits a volume, loads and renders.
6. Main menu → Parametric Sphere (mesh) at max resolution — verify it loads via the new envelope, faster than current, no size-limit failure.

## Worktree structure

Two paired worktrees sharing the branch name `volume-transmission`:

```
~/Documents/vr-start/worktrees/volume-transmission   # XR client, branched from master
~/PycharmProjects/ascribe-link/worktrees/volume-transmission   # server, branched from its default branch
```

The XR worktree's `Config.ascribe_link_url` points at the local server run from the server worktree during dev. Commits land on the shared branch name in each repo, and the two sides are tested together.

## Build order

1. Server — `envelope.py` + `MeshResult.to_bytes` + `VolumeResult.to_bytes` + unit tests.
2. Server — `generate_gaussian_volume` + registration.
3. Server — `/api/specimens/{id}/data` emits envelope for volume + dynamic-mesh results; legacy static STL path unchanged.
4. Server — static `.npy` specimen support in `SpecimenStore` + `_get_data_impl`.
5. Server — AI Generate auto-detect.
6. Client — `BinaryEnvelope.parse` + unit tests.
7. Client — `MeshData.set_from_bytes`, `VolumetricData.set_from_bytes` + unit tests.
8. Client — `MeshSpecimen._on_data_url_completed` envelope branch (regression-test large parametric sphere).
9. Client — `VolumeSpecimen.data_url` + `_load_from_data_url`.
10. Client — `SceneManager._fetch_and_load_result` type dispatch.
11. E2E — Gaussian volume golden path, then AI Generate volume, then static volume.

Each step is independently testable. Server-side 1–5 can be merged before any client work lands — the client falls back to the existing JSON path via content-type branching (unchanged servers return `application/json`, new servers return `application/x-ascribe-envelope-v1`).
