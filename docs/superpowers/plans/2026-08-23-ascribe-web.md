# ascribe-web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A static-hostable browser viewer (desktop 3D + WebXR) for volumes/meshes with story panels, plus the `ascribe-bundle` Python CLI that bakes content bundles.

**Architecture:** New sibling repo `C:\Users\rp\Documents\ascribe-web` with two components: `viewer/` (Godot 4 project, Compatibility renderer, exported to Web) and `bundler/` (Python CLI). They meet at the bundle format: `manifest.json` + `application/x-ascribe-envelope-v1` binary blobs. Envelope decoders and the volume raymarch shader are vendored (copied + adapted) from vr-start.

**Tech Stack:** Godot 4.6 (Compatibility/WebGL2, WebXRInterface, gdUnit4), Python 3.11+ (numpy, tifffile, jsonschema, pytest, hatch + hatch-vcs, vanilla `.venv` — no uv).

**Spec:** `docs/superpowers/specs/2026-08-18-webvr-viewer-design.md` (in vr-start)

## Global Constraints

- New repo `C:\Users\rp\Documents\ascribe-web`; the plan and spec live in vr-start — copy the spec into the new repo's `docs/` in Task 1.
- Viewer: Godot **4.6**, `rendering_method="gl_compatibility"`, **single-threaded** web export (`variant/thread_support=false`) — no COOP/COEP dependence.
- Volumes: **float16 default, uint8 optional; float32 is rejected by both CLI and viewer.**
- All viewer HTTP fetches use **relative URLs** (same-origin static hosting; no CORS assumptions).
- Bundle manifest `"version": 1`; viewer rejects other versions with a readable error screen. Every load failure shows the error screen — never a black canvas.
- Python: vanilla `.venv`, `pyproject.toml` with hatch + hatch-vcs, pytest. Windows dev machine: activate via `.venv\Scripts\activate`; invoke as `.venv\Scripts\python -m pytest`.
- Vendored-from-vr-start files keep their doc comments and get a header line `## Vendored from vr-start <path> (<commit tag 1.1.0>); local changes noted below.`
- Envelope v1 layout (normative): `<u32 LE preamble_len><UTF-8 JSON preamble><contiguous data blocks>`. Volume preamble: `{"type":"volume","shape":[d,h,w],"dtype":"float16"|"uint8","spacing":[sz,sy,sx],"origin":[oz,oy,ox]}`, one block of `d*h*w*bytes_per_voxel` C-order bytes. Mesh preamble: `{"type":"mesh","vertex_count":N,"index_count":M,"normal_count":K}`, blocks in order vertices (float32 ×3), indices (uint32), normals (float32 ×3); zero counts omit the block.
- Commit after every task (both repos where touched). Commit messages `feat:`/`test:`/`fix:` style.

---

### Task 1: Scaffold the repository

**Files:**
- Create: `C:\Users\rp\Documents\ascribe-web\` — `README.md`, `.gitignore`, `docs/webvr-viewer-design.md` (copy of the spec), `bundler/pyproject.toml`, `bundler/src/ascribe_bundle/__init__.py`, `bundler/tests/test_smoke.py`, `viewer/project.godot`, `viewer/.gitignore`

**Interfaces:**
- Produces: repo layout all later tasks assume; importable package `ascribe_bundle`; a Godot project that opens in 4.6 with Compatibility renderer.

- [ ] **Step 1: Create repo and Python package**

```powershell
mkdir C:\Users\rp\Documents\ascribe-web; cd C:\Users\rp\Documents\ascribe-web
git init -b main
mkdir bundler\src\ascribe_bundle, bundler\tests, viewer, docs
copy C:\Users\rp\Documents\vr-start\docs\superpowers\specs\2026-08-18-webvr-viewer-design.md docs\webvr-viewer-design.md
```

`bundler/pyproject.toml`:

```toml
[build-system]
requires = ["hatchling", "hatch-vcs"]
build-backend = "hatchling.build"

[project]
name = "ascribe-bundle"
dynamic = ["version"]
description = "Bake static web bundles for the ascribe-web viewer"
requires-python = ">=3.11"
dependencies = ["numpy>=1.26", "tifffile>=2024.0", "jsonschema>=4.21"]

[project.optional-dependencies]
dev = ["pytest>=8"]

[project.scripts]
ascribe-bundle = "ascribe_bundle.cli:main"

[tool.hatch.version]
source = "vcs"
raw-options = { root = ".." }
```

`bundler/src/ascribe_bundle/__init__.py`: empty. `bundler/tests/test_smoke.py`:

```python
def test_import():
    import ascribe_bundle  # noqa: F401
```

- [ ] **Step 2: Create venv, install, run smoke test**

```powershell
cd bundler
python -m venv ..\.venv
..\.venv\Scripts\python -m pip install -e .[dev]
..\.venv\Scripts\python -m pytest tests -v
```

Expected: 1 passed.

- [ ] **Step 3: Create the Godot project**

`viewer/project.godot`:

```ini
config_version=5

[application]
config/name="ascribe-web"
run/main_scene="res://scenes/skeleton.tscn"
config/features=PackedStringArray("4.6", "GL Compatibility")

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

(`scenes/skeleton.tscn` is created in Task 2 — the project won't run until then; that's fine.)

`viewer/.gitignore`: `.godot/`. Root `.gitignore`: `.venv/`, `build/`, `__pycache__/`, `dist/`.

`README.md`: two paragraphs — what ascribe-web is (viewer + bundler, static hosting), and the author workflow (`ascribe-bundle build data.npy --story story.md -o out/` → copy to static host).

- [ ] **Step 4: Commit**

```powershell
git add -A; git commit -m "feat: scaffold ascribe-web (bundler package + Godot Compatibility project)"
```

---

### Task 2: Walking skeleton — web shader + WebXR on device (Milestone 0, risk-killer)

**Files:**
- Create: `viewer/shaders/volume_web.gdshader`, `viewer/scripts/procedural_volume.gd`, `viewer/scripts/skeleton.gd`, `viewer/scenes/skeleton.tscn`, `viewer/export_presets.cfg`

**Interfaces:**
- Produces: `volume_web.gdshader` with uniforms `texture_volume, gradient, zoom, opacity, gamma, color_scalar, max_steps, step_size, num_exclusion_planes, exclusion_planes` (used by Task 8); `ProceduralVolume.make_texture(size: int) -> ImageTexture3D` (used by tests and the demo bundle); the pattern for entering WebXR (reused in Task 10).

- [ ] **Step 1: Port the shader**

Copy `vr-start/addons/volume_layered_shader/shaders/volume_shader.gdshader` to `viewer/shaders/volume_web.gdshader`, then apply exactly these changes:

1. Replace the consts with uniforms (quality tiers need runtime control):
   ```glsl
   uniform int max_steps = 128;
   uniform float step_size = 0.01;
   ```
   and use `max_steps` / `step_size` in `raymarch()` in place of `MAX_STEPS` / `STEP_SIZE`.
2. Texture hints: `filter_linear_mipmap` → `filter_linear` on both `texture_volume` and `gradient` (textures are created without mipmaps; WebGL2 mipmap filtering of a mipless texture is undefined-ish).
3. Delete the stereo debug tint at the end of `fragment()`:
   ```glsl
   if (VIEW_INDEX == VIEW_RIGHT)
       ALBEDO.g = 1.0;
   ```
4. Delete the unused `uniform int layers = 2;`.
5. Keep `EYE_OFFSET`, exclusion planes, and the ray-box entry clamp unchanged.

- [ ] **Step 2: Procedural test volume**

`viewer/scripts/procedural_volume.gd`:

```gdscript
## Generates a small float16 test volume (soft sphere + gyroid shell) for
## the walking skeleton, tests, and the demo bundle.
class_name ProceduralVolume
extends RefCounted


static func make_slices(size: int) -> Array[Image]:
	var images: Array[Image] = []
	for z in range(size):
		var buf := PackedFloat32Array()
		buf.resize(size * size)
		for y in range(size):
			for x in range(size):
				var p := (Vector3(x, y, z) / float(size - 1)) * 2.0 - Vector3.ONE
				var sphere := clampf(1.0 - p.length(), 0.0, 1.0)
				var g := absf(sin(p.x * 6.0) * cos(p.y * 6.0) + sin(p.y * 6.0) * cos(p.z * 6.0))
				buf[y * size + x] = sphere * clampf(g, 0.0, 1.0)
		var img32 := Image.create_from_data(size, size, false, Image.FORMAT_RF, buf.to_byte_array())
		img32.convert(Image.FORMAT_RH)
		images.append(img32)
	return images


static func make_texture(size: int) -> ImageTexture3D:
	var slices := make_slices(size)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RH, size, size, size, false, slices)
	return tex
```

- [ ] **Step 3: Skeleton scene**

`viewer/scenes/skeleton.tscn` (build in editor or as text): root `Node3D` with script `skeleton.gd`; children: `WorldEnvironment` (plain dark `Environment`), `Camera3D` at `(0, 0, 1.5)`, `XROrigin3D` with `XRCamera3D` and two `XRController3D` nodes, `MeshInstance3D` named `Volume` with a `BoxMesh` (size 1×1×1) and a `ShaderMaterial` using `volume_web.gdshader`, and a `CanvasLayer` with a `Button` named `EnterVR` (text "Enter VR", anchored bottom-center).

`viewer/scripts/skeleton.gd`:

```gdscript
extends Node3D

var xr_interface: WebXRInterface


func _ready() -> void:
	var mat: ShaderMaterial = $Volume.get_surface_override_material(0)
	if mat == null:
		mat = $Volume.mesh.surface_get_material(0)
	mat.set_shader_parameter("texture_volume", ProceduralVolume.make_texture(64))
	mat.set_shader_parameter("gradient", _default_gradient())
	xr_interface = XRServer.find_interface("WebXR")
	if xr_interface:
		xr_interface.session_supported.connect(_on_session_supported)
		xr_interface.session_started.connect(_on_session_started)
		xr_interface.session_failed.connect(func(msg): push_error("WebXR failed: " + msg))
		xr_interface.is_session_supported("immersive-vr")
	$CanvasLayer/EnterVR.pressed.connect(_enter_vr)
	$CanvasLayer/EnterVR.visible = false


func _default_gradient() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(1, 0.9, 0.7, 1))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


func _on_session_supported(mode: String, supported: bool) -> void:
	if mode == "immersive-vr":
		$CanvasLayer/EnterVR.visible = supported


func _enter_vr() -> void:
	xr_interface.session_mode = "immersive-vr"
	xr_interface.requested_reference_space_types = "local-floor, local"
	xr_interface.required_features = "local-floor"
	if not xr_interface.initialize():
		push_error("WebXR initialize() failed")


func _on_session_started() -> void:
	get_viewport().use_xr = true
	$CanvasLayer/EnterVR.visible = false
```

- [ ] **Step 4: Web export preset**

In the Godot editor: Project → Export → Add → Web. Then in the generated `viewer/export_presets.cfg` ensure: `variant/thread_support=false`, `vram_texture_compression/for_desktop=false` (3D textures are uploaded raw), export path `../build/web/index.html`. Export Release.

- [ ] **Step 5: Verify on desktop browser**

Serve and open (any static server; Python's is fine):

```powershell
cd C:\Users\rp\Documents\ascribe-web
.venv\Scripts\python -m http.server 8080 -d build\web
```

Open `http://localhost:8080`. Expected: the gyroid-sphere volume renders and the page holds ~60fps at 128 steps (check with browser devtools). If the volume is invisible or black, debug before proceeding — this task exists to catch exactly that.

- [ ] **Step 6: HUMAN CHECKPOINT — verify on Quest browser**

Needs a human with the headset: serve on the LAN (`--bind 0.0.0.0`, note WebXR requires HTTPS off-localhost — use `adb reverse tcp:8080 tcp:8080` and browse to `http://localhost:8080` on-device, which counts as a secure context). Press Enter VR. Expected: stereo volume rendering, no green-tinted right eye, tolerable frame rate (drop `max_steps` to 64 via a temporary keybind if needed to compare). Record findings in the task commit message.

- [ ] **Step 7: Commit**

```powershell
git add -A; git commit -m "feat: walking skeleton - web volume raymarch + WebXR entry (M0)"
```

---

### Task 3: Bundler — envelope writer

**Files:**
- Create: `bundler/src/ascribe_bundle/envelope.py`
- Test: `bundler/tests/test_envelope.py`

**Interfaces:**
- Produces: `write_envelope(preamble: dict, blocks: list[bytes]) -> bytes`; `read_envelope(data: bytes) -> tuple[dict, bytes]` (returns preamble and payload; used by tests and by `inspect` in Task 5); `volume_envelope(arr: np.ndarray, spacing=(1,1,1), origin=(0,0,0)) -> bytes` (arr is 3D, dtype float16 or uint8, axis order z,y,x).

- [ ] **Step 1: Write failing tests**

`bundler/tests/test_envelope.py`:

```python
import json
import struct

import numpy as np
import pytest

from ascribe_bundle.envelope import read_envelope, volume_envelope, write_envelope


def test_roundtrip():
    pre = {"type": "volume", "shape": [2, 3, 4], "dtype": "uint8"}
    payload = bytes(range(24))
    data = write_envelope(pre, [payload])
    got_pre, got_payload = read_envelope(data)
    assert got_pre == pre
    assert got_payload == payload


def test_layout_is_u32le_prefixed_json():
    data = write_envelope({"a": 1}, [b"XY"])
    n = struct.unpack("<I", data[:4])[0]
    assert json.loads(data[4 : 4 + n]) == {"a": 1}
    assert data[4 + n :] == b"XY"


def test_volume_envelope_float16():
    arr = np.arange(24, dtype=np.float16).reshape(2, 3, 4)
    pre, payload = read_envelope(volume_envelope(arr, spacing=(2, 1, 1)))
    assert pre["type"] == "volume"
    assert pre["shape"] == [2, 3, 4]
    assert pre["dtype"] == "float16"
    assert pre["spacing"] == [2, 1, 1]
    assert np.frombuffer(payload, dtype="<f2").reshape(2, 3, 4).tolist() == arr.tolist()


def test_volume_envelope_rejects_float32():
    with pytest.raises(ValueError, match="float16 or uint8"):
        volume_envelope(np.zeros((2, 2, 2), dtype=np.float32))
```

- [ ] **Step 2: Run to verify failure**

Run: `..\.venv\Scripts\python -m pytest tests\test_envelope.py -v` (from `bundler/`). Expected: FAIL — `ModuleNotFoundError: ascribe_bundle.envelope`.

- [ ] **Step 3: Implement**

`bundler/src/ascribe_bundle/envelope.py`:

```python
"""Writer/reader for the ascribe-link binary envelope (v1).

Layout: <u32 LE preamble_len><UTF-8 JSON preamble><contiguous data blocks>.
Mirrors vr-start's scripts/DataSources/binary_envelope.gd.
"""
from __future__ import annotations

import json
import struct

import numpy as np

MEDIA_TYPE = "application/x-ascribe-envelope-v1"
_ALLOWED_VOLUME_DTYPES = {"float16", "uint8"}


def write_envelope(preamble: dict, blocks: list[bytes]) -> bytes:
    p = json.dumps(preamble, separators=(",", ":")).encode("utf-8")
    return struct.pack("<I", len(p)) + p + b"".join(blocks)


def read_envelope(data: bytes) -> tuple[dict, bytes]:
    if len(data) < 4:
        raise ValueError("envelope truncated: missing length prefix")
    n = struct.unpack("<I", data[:4])[0]
    if len(data) < 4 + n:
        raise ValueError("envelope truncated: preamble incomplete")
    return json.loads(data[4 : 4 + n].decode("utf-8")), data[4 + n :]


def volume_envelope(arr: np.ndarray, spacing=(1, 1, 1), origin=(0, 0, 0)) -> bytes:
    if arr.ndim != 3:
        raise ValueError(f"volume must be 3D (z,y,x), got {arr.ndim}D")
    dtype = str(arr.dtype)
    if dtype not in _ALLOWED_VOLUME_DTYPES:
        raise ValueError(f"volume dtype must be float16 or uint8, got {dtype}")
    preamble = {
        "type": "volume",
        "shape": list(arr.shape),
        "dtype": dtype,
        "spacing": list(spacing),
        "origin": list(origin),
    }
    payload = np.ascontiguousarray(arr).astype(arr.dtype.newbyteorder("<")).tobytes()
    return write_envelope(preamble, [payload])
```

- [ ] **Step 4: Run tests — expect PASS**, then commit:

```powershell
git add -A; git commit -m "feat(bundler): envelope v1 writer/reader with dtype guard"
```

---

### Task 4: Bundler — volume ingestion and conversion

**Files:**
- Create: `bundler/src/ascribe_bundle/volume.py`
- Test: `bundler/tests/test_volume.py`

**Interfaces:**
- Consumes: `volume_envelope` from Task 3.
- Produces: `load_volume(path: Path) -> np.ndarray` (reads `.npy` or `.tif/.tiff` stacks, returns 3D array unchanged dtype); `convert_volume(arr, dtype: str = "float16", max_dim: int | None = None) -> np.ndarray` (dtype "float16" or "uint8"; uint8 min–max windows to 0–255; `max_dim` downsamples by integer striding so no axis exceeds it).

- [ ] **Step 1: Write failing tests**

`bundler/tests/test_volume.py`:

```python
from pathlib import Path

import numpy as np
import pytest

from ascribe_bundle.volume import convert_volume, load_volume


def test_load_npy(tmp_path: Path):
    arr = np.random.rand(4, 5, 6).astype(np.float32)
    p = tmp_path / "v.npy"
    np.save(p, arr)
    assert load_volume(p).shape == (4, 5, 6)


def test_load_tiff(tmp_path: Path):
    import tifffile
    arr = (np.random.rand(3, 4, 4) * 255).astype(np.uint8)
    p = tmp_path / "v.tif"
    tifffile.imwrite(p, arr)
    assert np.array_equal(load_volume(p), arr)


def test_convert_to_float16_preserves_values():
    arr = np.linspace(0, 1000, 27, dtype=np.float32).reshape(3, 3, 3)
    out = convert_volume(arr, "float16")
    assert out.dtype == np.float16
    assert np.allclose(out.astype(np.float32), arr, rtol=1e-3)


def test_convert_to_uint8_windows_minmax():
    arr = np.array([[[-5.0, 5.0]]], dtype=np.float32)
    out = convert_volume(arr, "uint8")
    assert out.dtype == np.uint8
    assert out.min() == 0 and out.max() == 255


def test_max_dim_downsamples():
    arr = np.zeros((100, 40, 100), dtype=np.float16)
    out = convert_volume(arr, "float16", max_dim=50)
    assert max(out.shape) <= 50


def test_rejects_bad_dtype():
    with pytest.raises(ValueError, match="float16 or uint8"):
        convert_volume(np.zeros((2, 2, 2)), "float32")
```

- [ ] **Step 2: Run — expect FAIL** (`ModuleNotFoundError`).

- [ ] **Step 3: Implement**

`bundler/src/ascribe_bundle/volume.py`:

```python
"""Load volumes from disk and convert them to web-safe dtypes."""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np


def load_volume(path: Path) -> np.ndarray:
    path = Path(path)
    if path.suffix == ".npy":
        arr = np.load(path)
    elif path.suffix in (".tif", ".tiff"):
        import tifffile

        arr = tifffile.imread(path)
    else:
        raise ValueError(f"unsupported volume file type: {path.suffix}")
    if arr.ndim != 3:
        raise ValueError(f"expected a 3D volume, got shape {arr.shape}")
    return arr


def convert_volume(arr: np.ndarray, dtype: str = "float16", max_dim: int | None = None) -> np.ndarray:
    if dtype not in ("float16", "uint8"):
        raise ValueError(f"dtype must be float16 or uint8, got {dtype}")
    if max_dim is not None and max(arr.shape) > max_dim:
        stride = math.ceil(max(arr.shape) / max_dim)
        arr = arr[::stride, ::stride, ::stride]
    if dtype == "uint8":
        a = arr.astype(np.float64)
        lo, hi = a.min(), a.max()
        scale = 255.0 / (hi - lo) if hi > lo else 0.0
        return ((a - lo) * scale).astype(np.uint8)
    return arr.astype(np.float16)
```

- [ ] **Step 4: Run tests — expect PASS**, commit `feat(bundler): volume loading and f16/u8 conversion`.

---

### Task 5: Bundler — manifest, story parsing, `build` CLI

**Files:**
- Create: `bundler/src/ascribe_bundle/manifest.py`, `bundler/src/ascribe_bundle/story.py`, `bundler/src/ascribe_bundle/cli.py`
- Test: `bundler/tests/test_manifest.py`, `bundler/tests/test_story.py`, `bundler/tests/test_cli.py`

**Interfaces:**
- Consumes: Tasks 3–4.
- Produces: the on-disk bundle format (normative for the viewer, Tasks 6–7): `manifest.json` `{"version":1,"title":str,"specimens":[{"id":str,"type":"volume"|"mesh","data":str,"display":{"gamma":float,"opacity":float,"gradient":[[pos,"#rrggbbaa"],...]}}],"story":[{"text":str,"specimen":str|null}]}`; story images stay inline in markdown text (`![alt](fig1.png)`), the CLI copies referenced image files into the bundle. CLI: `ascribe-bundle build <volume.npy|.tif|.bin-envelope> [--story story.md] [--title T] [--dtype float16|u8] [--max-dim N] [--size-warn-mb 100] -o out/`; `ascribe-bundle inspect <bundle-dir>`.

- [ ] **Step 1: Write failing tests**

`bundler/tests/test_manifest.py`:

```python
import pytest

from ascribe_bundle.manifest import make_manifest, validate_manifest


def _specimen():
    return {"id": "vol0", "type": "volume", "data": "specimen_0.bin",
            "display": {"gamma": 1.0, "opacity": 1.0,
                        "gradient": [[0.0, "#00000000"], [1.0, "#ffe6b3ff"]]}}


def test_make_and_validate_roundtrip():
    m = make_manifest("My Data", [_specimen()], [{"text": "hello", "specimen": "vol0"}])
    validate_manifest(m)  # should not raise
    assert m["version"] == 1


def test_validate_rejects_wrong_version():
    m = make_manifest("t", [_specimen()], [])
    m["version"] = 2
    with pytest.raises(ValueError, match="version"):
        validate_manifest(m)


def test_validate_rejects_story_referencing_unknown_specimen():
    m = make_manifest("t", [_specimen()], [{"text": "x", "specimen": "nope"}])
    with pytest.raises(ValueError, match="unknown specimen"):
        validate_manifest(m)
```

`bundler/tests/test_story.py`:

```python
from ascribe_bundle.story import parse_story

MD = """@specimen vol0
# Intro

Some text with ![a figure](fig1.png).

---

Second page, no pin.
"""


def test_parse_pages_and_pins():
    pages, images = parse_story(MD)
    assert len(pages) == 2
    assert pages[0]["specimen"] == "vol0"
    assert "# Intro" in pages[0]["text"]
    assert "@specimen" not in pages[0]["text"]
    assert pages[1]["specimen"] is None
    assert images == ["fig1.png"]
```

`bundler/tests/test_cli.py`:

```python
import json
from pathlib import Path

import numpy as np

from ascribe_bundle.cli import main


def test_build_creates_bundle(tmp_path: Path):
    vol = tmp_path / "v.npy"
    np.save(vol, np.random.rand(8, 8, 8).astype(np.float32))
    story = tmp_path / "story.md"
    story.write_text("Hello volume.")
    out = tmp_path / "out"
    rc = main(["build", str(vol), "--story", str(story), "--title", "T", "-o", str(out)])
    assert rc == 0
    manifest = json.loads((out / "manifest.json").read_text())
    assert manifest["version"] == 1
    assert (out / manifest["specimens"][0]["data"]).exists()


def test_build_warns_on_size(tmp_path: Path, capsys):
    vol = tmp_path / "v.npy"
    np.save(vol, np.zeros((64, 64, 64), dtype=np.float32))
    out = tmp_path / "out"
    main(["build", str(vol), "-o", str(out), "--size-warn-mb", "0"])
    assert "exceeds" in capsys.readouterr().err
```

- [ ] **Step 2: Run — expect FAIL** (missing modules).

- [ ] **Step 3: Implement the three modules**

`bundler/src/ascribe_bundle/manifest.py`:

```python
"""Bundle manifest construction and validation (schema version 1)."""
from __future__ import annotations

import jsonschema

SCHEMA = {
    "type": "object",
    "required": ["version", "title", "specimens", "story"],
    "properties": {
        "version": {"const": 1},
        "title": {"type": "string"},
        "specimens": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["id", "type", "data", "display"],
                "properties": {
                    "id": {"type": "string"},
                    "type": {"enum": ["volume", "mesh"]},
                    "data": {"type": "string"},
                    "display": {
                        "type": "object",
                        "properties": {
                            "gamma": {"type": "number"},
                            "opacity": {"type": "number"},
                            "gradient": {"type": "array", "items": {
                                "type": "array", "prefixItems": [
                                    {"type": "number"}, {"type": "string"}]}},
                        },
                    },
                },
            },
        },
        "story": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["text"],
                "properties": {"text": {"type": "string"},
                               "specimen": {"type": ["string", "null"]}},
            },
        },
    },
}

DEFAULT_GRADIENT = [[0.0, "#00000000"], [1.0, "#ffe6b3ff"]]


def make_manifest(title: str, specimens: list[dict], story: list[dict]) -> dict:
    return {"version": 1, "title": title, "specimens": specimens, "story": story}


def validate_manifest(m: dict) -> None:
    try:
        jsonschema.validate(m, SCHEMA)
    except jsonschema.ValidationError as e:
        raise ValueError(f"manifest invalid ({'/'.join(map(str, e.path)) or 'version'}): {e.message}") from e
    ids = {s["id"] for s in m["specimens"]}
    for page in m["story"]:
        pin = page.get("specimen")
        if pin is not None and pin not in ids:
            raise ValueError(f"story page pins unknown specimen '{pin}'")
```

`bundler/src/ascribe_bundle/story.py`:

```python
"""Parse a markdown story file into pages.

Pages are split on lines containing only '---'. A page may start with
'@specimen <id>' to pin a specimen. Inline images '![alt](path)' are
collected so the CLI can copy them into the bundle.
"""
from __future__ import annotations

import re

_IMG_RE = re.compile(r"!\[[^\]]*\]\(([^)]+)\)")


def parse_story(md: str) -> tuple[list[dict], list[str]]:
    pages: list[dict] = []
    images: list[str] = []
    for chunk in re.split(r"^---\s*$", md, flags=re.MULTILINE):
        text = chunk.strip()
        if not text:
            continue
        specimen = None
        lines = text.splitlines()
        if lines and lines[0].startswith("@specimen "):
            specimen = lines[0].removeprefix("@specimen ").strip()
            text = "\n".join(lines[1:]).strip()
        images.extend(m for m in _IMG_RE.findall(text) if m not in images)
        pages.append({"text": text, "specimen": specimen})
    return pages, images
```

`bundler/src/ascribe_bundle/cli.py`:

```python
"""ascribe-bundle command-line interface."""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np

from .envelope import read_envelope, volume_envelope
from .manifest import DEFAULT_GRADIENT, make_manifest, validate_manifest
from .story import parse_story
from .volume import convert_volume, load_volume


def build(args) -> int:
    src = Path(args.input)
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)

    if src.suffix == ".bin":  # pre-baked envelope, pass through after dtype check
        data = src.read_bytes()
        pre, _ = read_envelope(data)
        if pre.get("type") == "volume" and pre.get("dtype") not in ("float16", "uint8"):
            print(f"error: envelope dtype {pre.get('dtype')} not web-safe", file=sys.stderr)
            return 1
        env = data
        spec_type = pre.get("type", "volume")
    else:
        arr = convert_volume(load_volume(src),
                             "uint8" if args.dtype == "u8" else "float16",
                             max_dim=args.max_dim)
        env = volume_envelope(arr)
        spec_type = "volume"

    data_name = "specimen_0.bin"
    (out / data_name).write_bytes(env)

    pages: list[dict] = []
    if args.story:
        md = Path(args.story).read_text(encoding="utf-8")
        pages, images = parse_story(md)
        for img in images:
            src_img = Path(args.story).parent / img
            if not src_img.exists():
                print(f"error: story references missing image {img}", file=sys.stderr)
                return 1
            shutil.copy(src_img, out / Path(img).name)

    specimen = {"id": "specimen_0", "type": spec_type, "data": data_name,
                "display": {"gamma": 1.0, "opacity": 1.0, "gradient": DEFAULT_GRADIENT}}
    for page in pages:
        if page["specimen"] is None:
            page["specimen"] = "specimen_0"
    manifest = make_manifest(args.title or src.stem, [specimen], pages)
    validate_manifest(manifest)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    total_mb = sum(f.stat().st_size for f in out.iterdir()) / 1e6
    if total_mb > args.size_warn_mb:
        print(f"warning: bundle is {total_mb:.0f} MB, exceeds {args.size_warn_mb} MB "
              f"(consider --max-dim or --dtype u8)", file=sys.stderr)
    print(f"bundle written to {out} ({total_mb:.1f} MB)")
    return 0


def inspect(args) -> int:
    out = Path(args.bundle)
    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
    validate_manifest(manifest)
    print(json.dumps(manifest, indent=2))
    for s in manifest["specimens"]:
        pre, payload = read_envelope((out / s["data"]).read_bytes())
        print(f"{s['id']}: {pre} payload={len(payload)} bytes")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="ascribe-bundle")
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="bake a bundle from a volume + story")
    b.add_argument("input", help=".npy / .tif volume, or a pre-baked .bin envelope")
    b.add_argument("--story", help="markdown story file")
    b.add_argument("--title", default=None)
    b.add_argument("--dtype", choices=["float16", "u8"], default="float16")
    b.add_argument("--max-dim", type=int, default=None)
    b.add_argument("--size-warn-mb", type=float, default=100)
    b.add_argument("-o", "--output", required=True)
    b.set_defaults(func=build)
    i = sub.add_parser("inspect", help="validate and describe a bundle")
    i.add_argument("bundle")
    i.set_defaults(func=inspect)
    args = p.parse_args(argv)
    return args.func(args)
```

- [ ] **Step 4: Run all bundler tests — expect PASS**, commit `feat(bundler): manifest, story parsing, build/inspect CLI`.

---

### Task 6: Viewer — vendored decoders + gdUnit tests + fixture bundle

**Files:**
- Create: `viewer/scripts/data/binary_envelope.gd`, `viewer/scripts/data/volumetric_data.gd`, `viewer/scripts/data/mesh_data.gd`, `viewer/tests/test_decoders.gd`, `viewer/tests/fixtures/` (tiny bundle), `viewer/addons/gdUnit4/`

**Interfaces:**
- Consumes: bundle fixture produced by the Task 5 CLI.
- Produces: `BinaryEnvelope.parse(body) -> Dictionary` (`{"preamble":Dictionary,"offset":int}` or `{"error":String}`); `WebVolumetricData` with `set_from_bytes(preamble, body, offset) -> bool`, `get_texture() -> Texture3D`, `get_dimensions() -> Vector3i`, `get_spacing() -> Vector3`; `WebMeshData.set_from_bytes(...) -> bool`, `get_mesh() -> ArrayMesh`. Used by Task 7.

- [ ] **Step 1: Install gdUnit4** — clone `https://github.com/MikeSchulze/gdUnit4` (latest 4.x release tag) and copy its `addons/gdUnit4` into `viewer/addons/`; enable the plugin in `project.godot` (`[editor_plugins] enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")`).

- [ ] **Step 2: Generate the fixture bundle** with the CLI (checked in; also the demo bundle):

```powershell
cd C:\Users\rp\Documents\ascribe-web
@'
import numpy as np
z, y, x = np.mgrid[0:16, 0:16, 0:16] / 15.0 * 2 - 1
np.save("tiny.npy", (np.clip(1 - np.sqrt(x**2+y**2+z**2), 0, 1)).astype(np.float32))
'@ | .venv\Scripts\python -
echo "@specimen specimen_0`nA tiny test sphere.`n---`nSecond page." > tiny_story.md
.venv\Scripts\ascribe-bundle build tiny.npy --story tiny_story.md --title Tiny -o viewer\tests\fixtures\tiny_bundle
del tiny.npy, tiny_story.md
```

- [ ] **Step 3: Vendor the three GDScript files.** Copy from vr-start (tag 1.1.0): `scripts/DataSources/binary_envelope.gd` (unchanged apart from the vendored-from header), `scripts/DataClasses/volumetric_data.gd`, `scripts/DataClasses/mesh_data.gd`. Apply these changes to the copies:
  - Rename classes `VolumetricData`→`WebVolumetricData`, `MeshData`→`WebMeshData`; both `extends RefCounted` instead of `Data` (the `Data` base class is not vendored); replace the `data_ready.emit()` calls with a locally declared `signal data_ready`.
  - Delete `set_from_dict`, `set_from_images`, and `set_texture` from the volumetric class (the web viewer only uses `set_from_bytes`); delete the `uint16`/`float64` branches from `_create_image_from_bytes`.
  - In `_create_image_from_bytes`, the supported set becomes exactly:
    ```gdscript
    match dtype:
        "uint8":
            return Image.create_from_data(width, height, false, Image.FORMAT_L8, raw)
        "float16":
            return Image.create_from_data(width, height, false, Image.FORMAT_RH, raw)
        _:
            push_error("WebVolumetricData: dtype '%s' is not web-safe (float16/uint8 only)" % dtype)
            return null
    ```
    and `set_from_bytes` must return `false` when a slice comes back null (it already does).
  - `WebMeshData` gains `get_mesh() -> ArrayMesh` if the vr-start copy exposes arrays differently — mirror whatever accessor the vr-start file has, but ensure an `ArrayMesh` accessor exists.

- [ ] **Step 4: Write the gdUnit tests**

`viewer/tests/test_decoders.gd`:

```gdscript
extends GdUnitTestSuite

const FIXTURE := "res://tests/fixtures/tiny_bundle/"


func _load_fixture_envelope() -> PackedByteArray:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE + "manifest.json"))
	return FileAccess.get_file_as_bytes(FIXTURE + manifest["specimens"][0]["data"])


func test_envelope_parse_ok() -> void:
	var parsed := BinaryEnvelope.parse(_load_fixture_envelope())
	assert_that(parsed.has("error")).is_false()
	assert_that(parsed["preamble"]["type"]).is_equal("volume")
	assert_that(parsed["preamble"]["dtype"]).is_equal("float16")


func test_envelope_truncated() -> void:
	var parsed := BinaryEnvelope.parse(PackedByteArray([1, 2]))
	assert_that(parsed.has("error")).is_true()


func test_volume_set_from_bytes() -> void:
	var body := _load_fixture_envelope()
	var parsed := BinaryEnvelope.parse(body)
	var vol := WebVolumetricData.new()
	assert_that(vol.set_from_bytes(parsed["preamble"], body, parsed["offset"])).is_true()
	assert_that(vol.get_dimensions()).is_equal(Vector3i(16, 16, 16))
	assert_that(vol.get_texture()).is_not_null()


func test_volume_rejects_float32() -> void:
	var pre := {"type": "volume", "shape": [1, 1, 1], "dtype": "float32"}
	var body := PackedByteArray([0, 0, 0, 0])
	var vol := WebVolumetricData.new()
	assert_that(vol.set_from_bytes(pre, body, 0)).is_false()
```

- [ ] **Step 5: Run headless — expect PASS**

```powershell
& "<godot4.6 exe>" --headless --path viewer -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

(First run may fail on import cache — run `--headless --path viewer --import` once first.)

- [ ] **Step 6: Commit** `feat(viewer): vendored envelope/volume/mesh decoders (f16-safe) + fixture bundle`.

---

### Task 7: Viewer — BundleLoader

**Files:**
- Create: `viewer/scripts/bundle_loader.gd`, `viewer/scripts/error_screen.gd`, `viewer/scenes/error_screen.tscn`
- Test: `viewer/tests/test_bundle_loader.gd`

**Interfaces:**
- Consumes: Task 6 decoders.
- Produces: `BundleLoader` (Node) with `func load_bundle(base_url: String) -> void`, signals `progress(stage: String, ratio: float)`, `loaded(manifest: Dictionary, specimens: Dictionary)` (`specimens` maps id → `WebVolumetricData`/`WebMeshData`), `failed(message: String)`. Manifest validation: requires `version == 1`, arrays present, story pins resolve — mirrors the CLI's `validate_manifest`. `ErrorScreen.show_error(message: String)` full-screen readable error. Used by Tasks 8/11.

- [ ] **Step 1: Write failing gdUnit test** — validation logic is pure, test it directly:

```gdscript
extends GdUnitTestSuite


func test_validate_ok() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/tiny_bundle/manifest.json"))
	assert_that(BundleLoader.validate_manifest(manifest)).is_equal("")


func test_validate_wrong_version() -> void:
	assert_that(BundleLoader.validate_manifest({"version": 2, "title": "t", "specimens": [], "story": []}))\
		.contains("version")


func test_validate_unknown_pin() -> void:
	var m := {"version": 1, "title": "t",
		"specimens": [{"id": "a", "type": "volume", "data": "d.bin", "display": {}}],
		"story": [{"text": "x", "specimen": "nope"}]}
	assert_that(BundleLoader.validate_manifest(m)).contains("unknown specimen")
```

- [ ] **Step 2: Run — expect FAIL** (BundleLoader missing).

- [ ] **Step 3: Implement `bundle_loader.gd`** — `class_name BundleLoader extends Node`. Static `validate_manifest(m) -> String` (empty string = valid, else the error message). `load_bundle(base_url)` chains `HTTPRequest` children: fetch `manifest.json` (JSON), validate, then fetch each specimen's `data` blob sequentially, emitting `progress("manifest"|specimen_id, bytes_ratio)` (use `body_size_limit`-free requests and `request_completed` bytes; ratio 0→1 per file). Decode each blob with `BinaryEnvelope.parse` + the matching data class **in chunks across frames**: after parsing the preamble, build slice Images in batches of 8 per frame (`await get_tree().process_frame` between batches) so a 512-slice volume doesn't stall the main thread — this requires moving the slice loop out of `set_from_bytes` into the loader for volumes: call `_create_image_from_bytes` per batch via a new public `WebVolumetricData.build_async(preamble, body, offset, tree: SceneTree) -> bool` that awaits between batches (add it to the vendored class; keep `set_from_bytes` for tests). Any failure at any stage → `failed(message)` with a human-readable string including the file name; never partial `loaded`.
  - `error_screen.tscn`: full-rect `ColorRect` (dark) + centered `Label` (autowrap, theme font size 20) + smaller hint label "Check the bundle URL or contact the author."; `show_error(msg)` sets text and makes it visible.

- [ ] **Step 4: Run gdUnit — expect PASS.** Manual check: temporarily set skeleton scene to load the fixture bundle via `load_bundle("res://tests/fixtures/tiny_bundle")` — `HTTPRequest` won't fetch `res://`, so for tests/manual runs `load_bundle` must detect a `res://` prefix and read via `FileAccess` instead (implement this branch; it's also how the demo bundle ships inside the pck later if desired).

- [ ] **Step 5: Commit** `feat(viewer): async BundleLoader with validation, progress, error screen`.

---

### Task 8: Viewer — SpecimenStage

**Files:**
- Create: `viewer/scripts/specimen_stage.gd`, `viewer/scenes/specimen_stage.tscn`, `viewer/scripts/display_settings_panel.gd`, `viewer/scenes/display_settings_panel.tscn`
- Test: `viewer/tests/test_specimen_stage.gd`

**Interfaces:**
- Consumes: `WebVolumetricData`/`WebMeshData` (Task 6); `volume_web.gdshader` uniforms (Task 2).
- Produces: `SpecimenStage` (Node3D) with `func stage(id: String, data: RefCounted, display: Dictionary) -> void` (swaps out the previous specimen; volume → unit `BoxMesh` with the raymarch material, mesh → `MeshInstance3D` normalized to fit a 1m cube), `func apply_display(display: Dictionary) -> void` (gamma/opacity/gradient/max_steps/step_size; gradient list-of-stops → `GradientTexture1D`), `func clear() -> void`, `var current_id: String`. `DisplaySettingsPanel` (Control): sliders for gamma (0.1–4), opacity (0–2), quality (steps 32–512), emits `display_changed(display: Dictionary)`. Used by Tasks 10/11.

- [ ] **Step 1: Failing gdUnit test** — `stage()` a `WebVolumetricData` built from the fixture; assert `current_id`, assert the stage has exactly one `MeshInstance3D` child whose material shader parameter `gamma` matches; `stage()` a second specimen and assert the first child is gone. Test `_gradient_from_stops([[0.0,"#00000000"],[1.0,"#ffffffff"]])` returns a `GradientTexture1D` with 2 points.

- [ ] **Step 2: Run — FAIL.** **Step 3: Implement** (`_gradient_from_stops` uses `Color.from_string(hex, Color.MAGENTA)`; volume box scaled by `dimensions * spacing` normalized so the largest axis = 1m). **Step 4: Run — PASS.** **Step 5:** Replace the skeleton scene's hardcoded volume path: `skeleton.gd` becomes `main.gd`/`main.tscn` — parse `?bundle=` from `JavaScriptBridge.eval("window.location.search")` (fallback: `res://tests/fixtures/tiny_bundle` when not web or param missing), wire BundleLoader → SpecimenStage + error screen + a `ProgressBar`. Run in browser: fixture sphere renders via the full pipeline. **Step 6: Commit** `feat(viewer): SpecimenStage + display settings; main scene loads bundles end-to-end`.

---

### Task 9: Viewer — desktop orbit controls

**Files:**
- Create: `viewer/scripts/orbit_camera.gd`
- Modify: `viewer/scenes/main.tscn` (attach to Camera3D)
- Test: `viewer/tests/test_orbit_camera.gd`

**Interfaces:**
- Produces: `OrbitCamera` (Camera3D script): left-drag orbit, right-drag/two-finger pan, wheel/pinch zoom; state `yaw, pitch (clamped ±89°), distance (clamped 0.2–10), target: Vector3`; `func frame(aabb_size: float) -> void` sets distance to fit. Pure math in `static func orbit_transform(yaw, pitch, distance, target) -> Transform3D` for testability.

- [ ] **Step 1: Failing test** — `orbit_transform(0, 0, 2, Vector3.ZERO)` places camera at `(0, 0, 2)` looking at origin; pitch clamp: feeding pitch 2.0 rad through the input handler clamps to <1.56; zoom clamps at bounds.
- [ ] **Step 2: FAIL. Step 3: Implement** (`_unhandled_input` for `InputEventMouseButton`/`Motion`/`InputEventPanGesture`/`InputEventMagnifyGesture`; sensitivity 0.01 rad/px orbit, distance-scaled pan). **Step 4: PASS. Step 5:** Browser check: orbit/pan/zoom the fixture sphere with mouse and touchpad. **Step 6: Commit** `feat(viewer): desktop orbit/pan/zoom camera`.

---

### Task 10: Viewer — WebXR mode with grab interaction

**Files:**
- Create: `viewer/scripts/xr_grab.gd`
- Modify: `viewer/scripts/main.gd` (XR session wiring moved here from the Task 2 skeleton), `viewer/scenes/main.tscn`

**Interfaces:**
- Consumes: WebXR entry pattern (Task 2), `SpecimenStage` (Task 8).
- Produces: `XRGrab` (Node, exported refs to two `XRController3D` and the `SpecimenStage`): hold one grip → specimen follows that controller's rotation/translation delta; hold both grips → distance ratio scales the stage (clamped 0.1×–10×); release → specimen stays. Uses the `grip` float input (`controller.get_float("grip") > 0.7`).

- [ ] **Step 1: Implement** — no gdUnit for pose input; isolate the math as `static func two_hand_scale(d0: float, d1: float, s: float) -> float` and `static func one_hand_delta(prev: Transform3D, curr: Transform3D) -> Transform3D` and unit-test those two in `viewer/tests/test_xr_grab.gd` (scale ratio, clamps, delta composition) with the TDD cycle.
- [ ] **Step 2: Wire into main scene**: `use_xr` on session start; desktop `OrbitCamera` disabled while XR active; `EnterVR` button as in Task 2.
- [ ] **Step 3: HUMAN CHECKPOINT — on-device**: enter VR from a served build, grab-rotate and two-hand-scale the fixture volume, confirm the display panel is reachable (panel renders on a `SubViewport` quad 0.5m in front at eye height — reuse `display_settings_panel.tscn` on a `Sprite3D`/viewport quad with pointer via controller ray: keep v1 minimal — laser dot + trigger click mapped through `SubViewport.push_input`).
- [ ] **Step 4: Commit** `feat(viewer): WebXR grab/scale interaction + in-VR settings panel`.

---

### Task 11: StoryPanel, quality tiers, demo polish

**Files:**
- Create: `viewer/scripts/story_panel.gd`, `viewer/scenes/story_panel.tscn`, `viewer/scripts/md_to_bbcode.gd`, `viewer/scripts/quality.gd`
- Modify: `viewer/scripts/main.gd`
- Test: `viewer/tests/test_md_to_bbcode.gd`, `viewer/tests/test_quality.gd`

**Interfaces:**
- Consumes: manifest `story` array (Task 5 format), `SpecimenStage.stage/apply_display`, `BundleLoader.loaded`.
- Produces: `MdToBBCode.convert(md: String, base_url: String) -> String` (supports `#`/`##` headers → `[font_size]`, `**bold**`, `*italic*`, `![alt](img)` → `[img]{base_url}/img[/img]`, blank-line paragraphs); `Quality.pick_tier(features: PackedStringArray, xr_active: bool) -> Dictionary` returning `{"max_steps": int, "step_size": float}` — desktop 256/0.005, mobile browser 96/0.012, XR session 128/0.008 (detect mobile via `OS.has_feature("web_android") or OS.has_feature("web_ios")`); `StoryPanel` (Control): RichTextLabel + Prev/Next, emits `page_pinned(specimen_id)`; sidebar (right, 320px) on desktop, viewport-quad next to the specimen in XR (same mechanism as Task 10's panel).

- [ ] **Step 1: TDD `md_to_bbcode`** — tests: header, bold, italic, image URL joining, plain paragraphs pass through, BBCode-hostile input is escaped first (`[` → `[lb]`). FAIL → implement → PASS.
- [ ] **Step 2: TDD `quality.gd`** — feature-flag detection is injected (`pick_tier(features: PackedStringArray, xr_active: bool)`) so tests cover all three tiers. FAIL → implement → PASS.
- [ ] **Step 3: StoryPanel + wiring** — main.gd: on `loaded`, show page 0; page change → if page pins a different specimen, `stage()` it; quality tier applied at startup and on XR enter/exit (user override via the settings panel wins — track a `user_touched_quality` flag).
- [ ] **Step 4: Demo bundle + README** — regenerate the fixture as a slightly larger (64³) demo with a 3-page story; document the full author workflow in `README.md` (venv setup, build command, `python -m http.server` preview, static-host deploy). Export the web build; verify in browser: story sidebar, page flip, specimen pin, quality override.
- [ ] **Step 5: Final human checkpoint** — full pass on Quest browser: load demo bundle over LAN, VR mode, story panel legible, grab + panels work.
- [ ] **Step 6: Commit** `feat(viewer): story panel, quality tiers, demo bundle + author docs`; tag the repo `0.1.0`.
