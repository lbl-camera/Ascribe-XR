# Volume Transmission — Server (ascribe-link) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable ascribe-link to emit volumetric data (and large meshes) via a compact binary envelope over `/api/specimens/{id}/data`, register a built-in parametric Gaussian volume specimen, support static `.npy` volume specimens on disk, and make AI Generate auto-detect volume vs. mesh output.

**Architecture:** Add a new `envelope.py` module that serializes `MeshResult` / `VolumeResult` to a length-prefixed JSON-preamble + raw-bytes format. Switch the `/data` endpoint to emit this format (content-type `application/x-ascribe-envelope-v1`) for any in-memory `Result` object; static raw mesh files (`.stl`/`.obj`/`.fbx`) continue to stream as-is. Widen `RoomResultCache` to store raw result objects and serialize-on-read for each endpoint. Add a Gaussian parametric specimen and a `.npy` loader.

**Tech Stack:** Python 3.11+, NumPy, Litestar, pytest + httpx.AsyncTestClient. Spec reference: `docs/superpowers/specs/2026-04-24-volumetric-transmission-design.md` (in the vr-start repo).

**Worktree:** Work inside `~/PycharmProjects/ascribe-link/worktrees/volume-transmission` on branch `volume-transmission` (branched from the repo's default branch).

---

## File Structure

**New files:**
- `ascribe_link/envelope.py` — encode/decode binary envelope
- `tests/test_envelope.py` — round-trip unit tests
- `tests/test_parametric_volume.py` — parametric Gaussian tests
- `tests/test_static_volume.py` — static `.npy` specimen tests
- `tests/test_envelope_endpoint.py` — `/data` endpoint integration tests
- `tests/test_agent_dispatch.py` — AI Generate auto-detect unit tests
- `tests/fixtures/static_volume/metadata.json`, `data.npy`, `data.json` — fixtures for static tests

**Modified files:**
- `ascribe_link/models.py` — add `to_bytes()` methods, widen `VolumeResult` with optional `_array`
- `ascribe_link/parametric.py` — add `generate_gaussian_volume`
- `ascribe_link/app.py` — register `generate_gaussian_volume`, adjust AI Generate registration
- `ascribe_link/cache.py` — widen `CachedResult.result` type to `Any`
- `ascribe_link/specimen_store.py` — recognize `.npy` volume files + sidecar loader
- `ascribe_link/routes/specimens.py` — emit envelope for in-memory results; store raw results in cache
- `ascribe_link/job_registry.py` — widen `Job.result` type to `Any`
- `ascribe_link/agent_generator.py` — auto-detect volume vs. mesh return

---

## Task 0: Prepare worktree

**Files:** n/a (git operations only)

- [ ] **Step 1:** Create the worktree from the ascribe-link repo root.

```bash
cd ~/PycharmProjects/ascribe-link
git worktree add -b volume-transmission worktrees/volume-transmission
cd worktrees/volume-transmission
```

- [ ] **Step 2:** Verify the venv is usable (or create one). Use the existing `.venv` if present in the main checkout; otherwise:

```bash
python -m venv .venv
source .venv/bin/activate  # or .venv/Scripts/activate on Windows bash
pip install -e .[dev,agent]
```

- [ ] **Step 3:** Run the existing test suite to confirm a clean baseline.

```bash
pytest -q
```
Expected: all tests pass (or same failures as on the default branch — note and ignore). Commit nothing.

---

## Task 1: Add `envelope.py` with encode/decode for volumes

**Files:**
- Create: `ascribe_link/envelope.py`
- Create: `tests/test_envelope.py`

- [ ] **Step 1: Write the failing round-trip test for a VolumeResult.**

Create `tests/test_envelope.py` with:

```python
"""Tests for the binary envelope format."""
from __future__ import annotations

import numpy as np
import pytest

from ascribe_link.envelope import decode_envelope, encode_envelope, ENVELOPE_MEDIA_TYPE
from ascribe_link.models import VolumeResult


def test_envelope_media_type():
    assert ENVELOPE_MEDIA_TYPE == "application/x-ascribe-envelope-v1"


def test_volume_round_trip_float32():
    arr = np.random.RandomState(0).rand(4, 5, 6).astype(np.float32)
    original = VolumeResult.from_numpy(arr, spacing=[1.5, 2.0, 2.5], origin=[0.1, 0.2, 0.3])
    blob = encode_envelope(original)
    decoded = decode_envelope(blob)
    assert isinstance(decoded, VolumeResult)
    assert decoded.dtype == "float32"
    assert decoded.shape == [4, 5, 6]
    np.testing.assert_array_equal(decoded.to_numpy(), arr)
    assert decoded.spacing == [1.5, 2.0, 2.5]
    assert decoded.origin == [0.1, 0.2, 0.3]


def test_volume_round_trip_uint8():
    arr = np.arange(2 * 3 * 4, dtype=np.uint8).reshape(2, 3, 4)
    original = VolumeResult.from_numpy(arr)
    blob = encode_envelope(original)
    decoded = decode_envelope(blob)
    assert decoded.dtype == "uint8"
    np.testing.assert_array_equal(decoded.to_numpy(), arr)
```

- [ ] **Step 2: Run the test to verify it fails with an import error.**

```bash
pytest tests/test_envelope.py -x -q
```
Expected: `ImportError: cannot import name 'decode_envelope' from 'ascribe_link.envelope'` (or `No module named 'ascribe_link.envelope'`).

- [ ] **Step 3: Implement `ascribe_link/envelope.py` with the volume path only.**

```python
"""Binary envelope wire format for MeshResult / VolumeResult.

Layout:
    <4-byte little-endian uint32: preamble_length>
    <preamble_length bytes: UTF-8 JSON preamble>
    <raw bytes: one or more contiguous data blocks>
"""
from __future__ import annotations

import json
import struct
from typing import Union

import numpy as np

from ascribe_link.models import MeshResult, VolumeResult

ENVELOPE_MEDIA_TYPE = "application/x-ascribe-envelope-v1"

Envelopeable = Union[MeshResult, VolumeResult]


def encode_envelope(result: Envelopeable) -> bytes:
    """Serialize a result to the binary envelope format."""
    if isinstance(result, VolumeResult):
        return _encode_volume(result)
    if isinstance(result, MeshResult):
        return _encode_mesh(result)
    raise TypeError(f"Cannot envelope-encode {type(result).__name__}")


def decode_envelope(data: bytes) -> Envelopeable:
    """Parse the binary envelope format back into a typed result."""
    if len(data) < 4:
        raise ValueError("envelope truncated: missing length prefix")
    (preamble_len,) = struct.unpack("<I", data[:4])
    if len(data) < 4 + preamble_len:
        raise ValueError("envelope truncated: preamble incomplete")
    preamble = json.loads(data[4 : 4 + preamble_len].decode("utf-8"))
    offset = 4 + preamble_len
    result_type = preamble.get("type", "")
    if result_type == "volume":
        return _decode_volume(preamble, data, offset)
    if result_type == "mesh":
        return _decode_mesh(preamble, data, offset)
    raise ValueError(f"unknown envelope type: {result_type!r}")


# ---------- volume ----------

def _encode_volume(result: VolumeResult) -> bytes:
    arr = _volume_array(result)
    preamble = {
        "type": "volume",
        "shape": list(arr.shape),
        "dtype": str(arr.dtype),
        "spacing": list(result.spacing) if result.spacing else [1.0, 1.0, 1.0],
        "origin": list(result.origin) if result.origin else [0.0, 0.0, 0.0],
    }
    preamble_bytes = json.dumps(preamble, separators=(",", ":")).encode("utf-8")
    header = struct.pack("<I", len(preamble_bytes)) + preamble_bytes
    return header + np.ascontiguousarray(arr).tobytes()


def _decode_volume(preamble: dict, data: bytes, offset: int) -> VolumeResult:
    shape = preamble["shape"]
    dtype = preamble["dtype"]
    count = int(np.prod(shape))
    arr = np.frombuffer(data, dtype=dtype, count=count, offset=offset).reshape(shape).copy()
    return VolumeResult.from_numpy(
        arr,
        spacing=preamble.get("spacing"),
        origin=preamble.get("origin"),
    )


def _volume_array(result: VolumeResult) -> np.ndarray:
    """Get the underlying ndarray, preferring the zero-copy _array if set."""
    arr = getattr(result, "_array", None)
    if arr is not None:
        return arr
    return result.to_numpy()


# ---------- mesh ----------

def _encode_mesh(result: MeshResult) -> bytes:
    vertices = np.asarray(result.vertices, dtype=np.float32)
    indices = np.asarray(result.indices, dtype=np.uint32)
    normals = (
        np.asarray(result.normals, dtype=np.float32)
        if result.normals
        else np.empty(0, dtype=np.float32)
    )
    vertex_count = vertices.size // 3
    index_count = indices.size
    normal_count = normals.size // 3
    preamble = {
        "type": "mesh",
        "vertex_count": vertex_count,
        "vertex_dtype": "float32",
        "index_count": index_count,
        "index_dtype": "uint32",
        "normal_count": normal_count,
        "normal_dtype": "float32",
    }
    preamble_bytes = json.dumps(preamble, separators=(",", ":")).encode("utf-8")
    header = struct.pack("<I", len(preamble_bytes)) + preamble_bytes
    body = vertices.tobytes() + indices.tobytes()
    if normal_count:
        body += normals.tobytes()
    return header + body


def _decode_mesh(preamble: dict, data: bytes, offset: int) -> MeshResult:
    vc = preamble["vertex_count"]
    ic = preamble["index_count"]
    nc = preamble["normal_count"]
    vertices = np.frombuffer(data, dtype=np.float32, count=vc * 3, offset=offset).tolist()
    offset += vc * 3 * 4
    indices = np.frombuffer(data, dtype=np.uint32, count=ic, offset=offset).tolist()
    offset += ic * 4
    normals = None
    if nc:
        normals = np.frombuffer(
            data, dtype=np.float32, count=nc * 3, offset=offset
        ).tolist()
    return MeshResult(vertices=vertices, indices=indices, normals=normals)
```

- [ ] **Step 4: Re-run the volume round-trip tests.**

```bash
pytest tests/test_envelope.py -x -q
```
Expected: both tests pass.

- [ ] **Step 5: Add failing mesh round-trip tests.**

Append to `tests/test_envelope.py`:

```python
from ascribe_link.models import MeshResult


def test_mesh_round_trip_with_normals():
    original = MeshResult(
        vertices=[0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
        indices=[0, 1, 2],
        normals=[0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0],
    )
    blob = encode_envelope(original)
    decoded = decode_envelope(blob)
    assert isinstance(decoded, MeshResult)
    assert decoded.vertices == original.vertices
    assert decoded.indices == original.indices
    assert decoded.normals == original.normals


def test_mesh_round_trip_without_normals():
    original = MeshResult(
        vertices=[0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
        indices=[0, 1, 2],
        normals=None,
    )
    blob = encode_envelope(original)
    decoded = decode_envelope(blob)
    assert isinstance(decoded, MeshResult)
    assert decoded.vertices == original.vertices
    assert decoded.indices == original.indices
    assert decoded.normals is None
```

- [ ] **Step 6: Run mesh tests; they should pass since the encoder is already implemented.**

```bash
pytest tests/test_envelope.py -x -q
```
Expected: all four tests pass.

- [ ] **Step 7: Add failing tests for error handling.**

Append to `tests/test_envelope.py`:

```python
def test_truncated_length_prefix():
    with pytest.raises(ValueError, match="missing length prefix"):
        decode_envelope(b"\x00\x00")


def test_truncated_preamble():
    header = struct.pack("<I", 100) + b"{"  # claims 100 bytes, gives 1
    with pytest.raises(ValueError, match="preamble incomplete"):
        decode_envelope(header)


def test_unknown_envelope_type():
    preamble = b'{"type":"nope"}'
    blob = struct.pack("<I", len(preamble)) + preamble
    with pytest.raises(ValueError, match="unknown envelope type"):
        decode_envelope(blob)


def test_encode_rejects_other_types():
    with pytest.raises(TypeError):
        encode_envelope({"type": "volume"})  # dict is not a Result
```

Add `import struct` to the imports at the top of the test file.

- [ ] **Step 8: Run all envelope tests.**

```bash
pytest tests/test_envelope.py -v
```
Expected: all seven pass.

- [ ] **Step 9: Commit.**

```bash
git add ascribe_link/envelope.py tests/test_envelope.py
git commit -m "Add binary envelope wire format for mesh and volume results"
```

---

## Task 2: Make `VolumeResult.from_numpy` cache the raw ndarray

**Files:**
- Modify: `ascribe_link/models.py:105-170`
- Test: re-runs existing `tests/test_envelope.py`

**Why:** `_encode_volume` reads `result._array` if available, otherwise falls back to `to_numpy()` (which base64-decodes). Populating `_array` from `from_numpy` avoids redundant encode/decode cycles on the hot path. The change is backward-compatible — existing callers that construct `VolumeResult(data=<base64>)` still get a working object; `_array` is just absent.

- [ ] **Step 1: Write a test that asserts `_array` is populated by `from_numpy`.**

Append to `tests/test_envelope.py`:

```python
def test_from_numpy_caches_array():
    arr = np.ones((2, 3, 4), dtype=np.float32)
    result = VolumeResult.from_numpy(arr)
    assert getattr(result, "_array", None) is not None
    # Envelope encode should not need to re-decode base64
    blob = encode_envelope(result)
    decoded = decode_envelope(blob)
    np.testing.assert_array_equal(decoded.to_numpy(), arr)
```

- [ ] **Step 2: Run the test to verify it fails.**

```bash
pytest tests/test_envelope.py::test_from_numpy_caches_array -x -q
```
Expected: FAIL — `_array` attribute is `None`.

- [ ] **Step 3: Modify `VolumeResult` in `ascribe_link/models.py`.**

In `ascribe_link/models.py`, find the `@dataclass class VolumeResult:` block (~line 105) and update the `from_numpy` classmethod. The full replacement for the `from_numpy` method and a small `__post_init__` to initialize `_array`:

```python
# Inside @dataclass class VolumeResult:
    # ... existing fields unchanged ...

    def __post_init__(self) -> None:
        # Transient zero-copy handle; set by from_numpy, not serialized to dict.
        self._array: np.ndarray | None = None

    # ... to_dict unchanged ...
    # ... to_numpy unchanged ...

    @classmethod
    def from_numpy(
        cls,
        arr: np.ndarray,
        spacing: list[float] | None = None,
        origin: list[float] | None = None,
    ) -> "VolumeResult":
        """Create from a NumPy array."""
        arr = np.ascontiguousarray(arr)
        data = base64.b64encode(arr.tobytes()).decode("ascii")
        result = cls(
            shape=list(arr.shape),
            dtype=str(arr.dtype),
            data=data,
            spacing=spacing,
            origin=origin,
        )
        result._array = arr
        return result
```

- [ ] **Step 4: Run the new test plus all previous envelope tests.**

```bash
pytest tests/test_envelope.py -v
```
Expected: all pass including `test_from_numpy_caches_array`.

- [ ] **Step 5: Commit.**

```bash
git add ascribe_link/models.py tests/test_envelope.py
git commit -m "Cache raw ndarray on VolumeResult.from_numpy for zero-copy envelope"
```

---

## Task 3: Add parametric Gaussian volume function

**Files:**
- Modify: `ascribe_link/parametric.py` (append)
- Create: `tests/test_parametric_volume.py`

- [ ] **Step 1: Write a failing test for `generate_gaussian_volume`.**

Create `tests/test_parametric_volume.py`:

```python
"""Tests for parametric volume specimens."""
from __future__ import annotations

import numpy as np
import pytest

from ascribe_link.models import VolumeResult
from ascribe_link.parametric import generate_gaussian_volume


def test_default_gaussian_volume():
    result = generate_gaussian_volume()
    assert isinstance(result, VolumeResult)
    assert result.shape == [64, 64, 64]
    assert result.dtype == "float32"
    arr = result.to_numpy()
    # Peak at the center, decays outward.
    center = (32, 32, 32)
    assert arr[center] == pytest.approx(1.0, abs=1e-3)
    # A corner should be much smaller than the center.
    assert arr[0, 0, 0] < arr[center] * 0.5


def test_gaussian_volume_resolution():
    result = generate_gaussian_volume(resolution=32)
    assert result.shape == [32, 32, 32]


def test_gaussian_volume_sigma_affects_spread():
    narrow = generate_gaussian_volume(resolution=32, sigma=0.1).to_numpy()
    wide = generate_gaussian_volume(resolution=32, sigma=0.5).to_numpy()
    # Wider sigma → more mass away from center.
    off_center_narrow = narrow[0, 0, 0]
    off_center_wide = wide[0, 0, 0]
    assert off_center_wide > off_center_narrow


def test_gaussian_volume_clamps_resolution():
    # Below minimum
    r = generate_gaussian_volume(resolution=8)
    assert r.shape == [32, 32, 32]
    # Above maximum
    r = generate_gaussian_volume(resolution=999)
    assert r.shape == [256, 256, 256]
```

- [ ] **Step 2: Run the test to verify it fails.**

```bash
pytest tests/test_parametric_volume.py -x -q
```
Expected: `ImportError: cannot import name 'generate_gaussian_volume'`.

- [ ] **Step 3: Append to `ascribe_link/parametric.py`.**

Add at the end of the file:

```python
import numpy as np  # may already be imported; ensure it is

from ascribe_link.models import VolumeResult


def generate_gaussian_volume(resolution: int = 64, sigma: float = 0.3) -> VolumeResult:
    """Generate a 3D Gaussian blob centered in a unit cube.

    Parameters
    ----------
    resolution : int
        Number of voxels per axis (clamped to [32, 256]).
    sigma : float
        Standard deviation of the Gaussian relative to the cube edge
        (clamped to [0.05, 1.0]).

    Returns
    -------
    VolumeResult
        float32 volume, shape [resolution]*3, normalized so peak == 1.0.
    """
    resolution = max(32, min(256, int(resolution)))
    sigma = max(0.05, min(1.0, float(sigma)))

    axis = np.linspace(-0.5, 0.5, resolution, dtype=np.float32)
    z, y, x = np.meshgrid(axis, axis, axis, indexing="ij")
    r2 = x * x + y * y + z * z
    volume = np.exp(-r2 / (2.0 * sigma * sigma)).astype(np.float32)
    return VolumeResult.from_numpy(
        volume,
        spacing=[1.0 / resolution, 1.0 / resolution, 1.0 / resolution],
        origin=[0.0, 0.0, 0.0],
    )
```

If `parametric.py` already imports numpy or `VolumeResult`, don't duplicate the imports.

- [ ] **Step 4: Run tests to verify they pass.**

```bash
pytest tests/test_parametric_volume.py -v
```
Expected: all four pass.

- [ ] **Step 5: Commit.**

```bash
git add ascribe_link/parametric.py tests/test_parametric_volume.py
git commit -m "Add generate_gaussian_volume parametric specimen"
```

---

## Task 4: Register `generate_gaussian_volume` and adjust AI Generate

**Files:**
- Modify: `ascribe_link/app.py:77-131`

- [ ] **Step 1: Write the failing test that the specimen list includes the new specimen.**

Create `tests/test_app_registration.py`:

```python
"""Tests that specimens are correctly registered at app startup."""
from __future__ import annotations

import pytest
from litestar.testing import AsyncTestClient

from ascribe_link.app import create_app


@pytest.fixture
async def client():
    app = create_app()
    async with AsyncTestClient(app=app) as c:
        yield c


async def test_gaussian_volume_is_registered(client: AsyncTestClient):
    r = await client.get("/api/specimens/")
    r.raise_for_status()
    items = r.json()
    names = {item["id"] for item in items}
    assert "generate_gaussian_volume" in names
    entry = next(x for x in items if x["id"] == "generate_gaussian_volume")
    assert entry["type"] == "volume"
    assert entry["is_dynamic"] is True
    assert "volume" in entry["tags"]
```

- [ ] **Step 2: Run the test; it should fail.**

```bash
pytest tests/test_app_registration.py -x -q
```
Expected: `assert "generate_gaussian_volume" in names` fails.

- [ ] **Step 3: Modify `ascribe_link/app.py`.**

Find the existing `registry.register_specimen(generate_torus, ...)` block. Just after it, add:

```python
from ascribe_link.parametric import generate_sphere, generate_torus, generate_gaussian_volume
# ^ update the existing import line to include generate_gaussian_volume

registry.register_specimen(
    generate_gaussian_volume,
    display_name="Parametric Gaussian Volume",
    name="generate_gaussian_volume",
    description="3D Gaussian blob with adjustable resolution and spread",
    return_type="volume",
    tags=["parametric", "volume", "dynamic"],
)
```

Then find the AI Generate registration (around `registry.register_specimen(agent_func, ...)` inside the `if enable_agent:` block). Change the `return_type` from `"mesh"` to `None` so the registry accepts either output, and update tags:

```python
registry.register_specimen(
    agent_func,
    display_name="AI Generate",
    name="ai_generate",
    description="Generate 3D data from natural language prompts using an AI agent",
    return_type=None,  # Agent may return either MeshResult or VolumeResult
    tags=["ai", "generative", "dynamic"],
)
```

- [ ] **Step 4: Re-run the registration test.**

```bash
pytest tests/test_app_registration.py -x -q
```
Expected: pass.

- [ ] **Step 5: Run the full suite to make sure nothing regressed.**

```bash
pytest -q
```
Expected: all tests pass.

- [ ] **Step 6: Commit.**

```bash
git add ascribe_link/app.py tests/test_app_registration.py
git commit -m "Register Parametric Gaussian Volume; relax AI Generate return type"
```

---

## Task 5: Emit envelope from `/api/specimens/{id}/data` for `Result` objects

**Files:**
- Modify: `ascribe_link/routes/specimens.py:229-336` (method `_get_data_impl`)
- Create: `tests/test_envelope_endpoint.py`

**Why:** Today `_get_data_impl` returns `result_dict` (JSON). Change it so that when the result is a `MeshResult` or `VolumeResult`, the response body is the envelope bytes with media type `application/x-ascribe-envelope-v1`. Static file specimens (STL/OBJ/FBX) remain unchanged.

- [ ] **Step 1: Write a failing integration test that hits the Gaussian volume via `/data`.**

Create `tests/test_envelope_endpoint.py`:

```python
"""Integration tests for envelope-encoded /data responses."""
from __future__ import annotations

import pytest
from litestar.testing import AsyncTestClient

from ascribe_link.app import create_app
from ascribe_link.envelope import ENVELOPE_MEDIA_TYPE, decode_envelope
from ascribe_link.models import MeshResult, VolumeResult


@pytest.fixture
async def client():
    app = create_app()
    async with AsyncTestClient(app=app) as c:
        yield c


async def test_gaussian_volume_data_is_envelope(client: AsyncTestClient):
    r = await client.get("/api/specimens/generate_gaussian_volume/data")
    r.raise_for_status()
    content_type = r.headers["content-type"].split(";")[0].strip()
    assert content_type == ENVELOPE_MEDIA_TYPE
    decoded = decode_envelope(r.content)
    assert isinstance(decoded, VolumeResult)
    assert decoded.shape == [64, 64, 64]
    assert decoded.dtype == "float32"


async def test_sphere_mesh_data_is_envelope(client: AsyncTestClient):
    r = await client.get("/api/specimens/generate_sphere/data")
    r.raise_for_status()
    content_type = r.headers["content-type"].split(";")[0].strip()
    assert content_type == ENVELOPE_MEDIA_TYPE
    decoded = decode_envelope(r.content)
    assert isinstance(decoded, MeshResult)
    assert len(decoded.vertices) > 0
    assert len(decoded.indices) > 0
```

- [ ] **Step 2: Run the test; it should fail because the endpoint currently returns JSON.**

```bash
pytest tests/test_envelope_endpoint.py -x -q
```
Expected: assertion on `content_type` fails (currently `application/json`).

- [ ] **Step 3: Modify `ascribe_link/routes/specimens.py`.**

Add this import near the top, alongside the other `ascribe_link.*` imports:

```python
from ascribe_link.envelope import ENVELOPE_MEDIA_TYPE, encode_envelope
```

Replace the dynamic-specimen return path inside `_get_data_impl`. Locate this block:

```python
            # Invoke the function
            try:
                result = await function_registry.invoke_async(
                    meta.function_name,
                    [],
                    params,
                )
                result_dict = result_to_dict(result)
            except KeyError:
                raise NotFoundException(detail=f"Function not found: {meta.function_name}")
            except TypeError as e:
                # Sync function - fall back to sync invoke
                if "async" in str(e).lower() or "await" in str(e).lower():
                    result = function_registry.invoke(
                        meta.function_name,
                        [],
                        params,
                    )
                    result_dict = result_to_dict(result)
                else:
                    raise

            # Cache and return
            result_cache.put(room_id, meta.function_name, params, result_dict)
            return result_dict
```

Replace it with:

```python
            # Invoke the function
            try:
                result = await function_registry.invoke_async(
                    meta.function_name,
                    [],
                    params,
                )
            except KeyError:
                raise NotFoundException(detail=f"Function not found: {meta.function_name}")
            except TypeError as e:
                if "async" in str(e).lower() or "await" in str(e).lower():
                    result = function_registry.invoke(
                        meta.function_name,
                        [],
                        params,
                    )
                else:
                    raise

            # Cache the raw result object (widened in Task 6); then envelope-serve.
            result_cache.put(room_id, meta.function_name, params, result)
            return Response(
                content=encode_envelope(result),
                media_type=ENVELOPE_MEDIA_TYPE,
            )
```

Also update the cache-hit branch slightly above:

```python
            # Check cache first
            cached_result = result_cache.get(room_id, meta.function_name, params)
            if cached_result is not None:
                logger.info("Cache hit for %s/%s", room_id, meta.function_name)
                return cached_result
```

becomes:

```python
            # Check cache first
            cached_result = result_cache.get(room_id, meta.function_name, params)
            if cached_result is not None:
                logger.info("Cache hit for %s/%s", room_id, meta.function_name)
                return Response(
                    content=encode_envelope(cached_result),
                    media_type=ENVELOPE_MEDIA_TYPE,
                )
```

The static-file branch (at the very bottom of `_get_data_impl`, starting `# Static specimen: return the file`) is unchanged.

- [ ] **Step 4: Update `Response` import if needed.**

Check that `from litestar import Controller, Response, get, post` at the top of `specimens.py` already includes `Response`. It does (line 14). No change needed.

- [ ] **Step 5: Re-run the envelope endpoint test.**

```bash
pytest tests/test_envelope_endpoint.py -v
```
Expected: both pass.

- [ ] **Step 6: Run the full suite — some existing tests that expect JSON from `/data` for dynamic specimens will now fail.**

```bash
pytest -q
```
Expected: failures in any test that asserts `r.json()` on a dynamic specimen's `/data` response (e.g. possibly `test_jobs_api.py` or other integration tests). **Read each failure and adapt** — the expected fix is to call `decode_envelope(r.content)` instead of `r.json()`. If no existing tests hit `/data` for a dynamic specimen, no changes are needed.

- [ ] **Step 7: Fix any broken tests by switching to `decode_envelope`.**

For each failing test, replace:

```python
data = r.json()
```

with:

```python
from ascribe_link.envelope import decode_envelope
result = decode_envelope(r.content)
# use result.vertices / result.to_numpy() / etc. instead of data["..."]
```

- [ ] **Step 8: Commit.**

```bash
git add ascribe_link/routes/specimens.py tests/test_envelope_endpoint.py
git add -u tests/  # any test files you adapted in Step 7
git commit -m "Serve /api/specimens/{id}/data as binary envelope for in-memory results"
```

---

## Task 6: Widen `RoomResultCache` to store raw results

**Files:**
- Modify: `ascribe_link/cache.py:17-130`
- Modify: `ascribe_link/routes/specimens.py` (the `_run_job` function already stores the raw result after Task 5; confirm no further changes needed)

**Why:** Task 5 already calls `result_cache.put(..., result)` with a raw `MeshResult`/`VolumeResult`. The cache type hints are still `dict[str, Any]`, which is misleading. Fix the types and make sure no consumer assumes `dict`.

- [ ] **Step 1: Write a failing test.**

Create `tests/test_cache.py`:

```python
"""Tests that RoomResultCache stores arbitrary result objects."""
from __future__ import annotations

import numpy as np

from ascribe_link.cache import RoomResultCache
from ascribe_link.models import VolumeResult


def test_cache_stores_volume_result():
    cache = RoomResultCache()
    arr = np.ones((2, 2, 2), dtype=np.float32)
    result = VolumeResult.from_numpy(arr)
    cache.put("room1", "fn", {"a": 1}, result)
    got = cache.get("room1", "fn", {"a": 1})
    assert got is result  # same object, no serialization round-trip
```

- [ ] **Step 2: Run the test.**

```bash
pytest tests/test_cache.py -x -q
```
Expected: passes (the cache already stores whatever is given — this is a regression test against future changes).

- [ ] **Step 3: Update type hints in `ascribe_link/cache.py`.**

In `CachedResult`, change `result: dict[str, Any]` to `result: Any`.
In `get()` signature, change return type to `Any | None`.
In `put()` signature, change `result: dict[str, Any]` to `result: Any`.

- [ ] **Step 4: Run the full suite to confirm no regression.**

```bash
pytest -q
```
Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add ascribe_link/cache.py tests/test_cache.py
git commit -m "Widen RoomResultCache to hold raw result objects"
```

---

## Task 7: Widen `Job.result` type and job result fetch

**Files:**
- Modify: `ascribe_link/job_registry.py` — widen `Job.result` type
- Modify: `ascribe_link/routes/specimens.py` — `_run_job` stores raw result
- Modify: `ascribe_link/routes/jobs.py` — `GET /api/jobs/{id}/result` returns a dict for the JSON-invoke callers

- [ ] **Step 1: Inspect `job_registry.py` to find the `Job` dataclass.**

```bash
grep -n "class Job" ascribe_link/job_registry.py
```

- [ ] **Step 2: Change `Job.result` type.**

In the `@dataclass class Job:` block, change:

```python
    result: dict[str, Any] | None = None
```

to:

```python
    result: Any = None
```

(If there is no default, make it `Any | None = None`.) Adjust the imports at the top: `from typing import Any` (already present in most modules).

- [ ] **Step 3: Update `_run_job` in `routes/specimens.py`.**

Find this block near the end of `specimens.py`:

```python
        result_dict = result_to_dict(result)
        result_cache.put(job.room_id, func_name, job.params, result_dict)
        job.result = result_dict
        job.status = "done"
```

Replace with:

```python
        result_cache.put(job.room_id, func_name, job.params, result)
        job.result = result
        job.status = "done"
```

- [ ] **Step 4: Update the `/api/jobs/{id}/result` handler in `routes/jobs.py`.**

```bash
grep -n "result" ascribe_link/routes/jobs.py | head -20
```

Find the handler that returns `job.result`. It should wrap the value via `result_to_dict` or the envelope depending on how the client calls it. Because the existing client (`AscribeLinkClient.run_job`) uses this result to know the job succeeded then fetches `/data` separately, **we can keep this endpoint emitting the JSON-dict form** (back-compat; the client already tolerates it). Wrap the raw result:

```python
# Wherever the handler returns job.result:
from ascribe_link.models import result_to_dict, MeshResult, VolumeResult, PointCloudResult, ImageResult

# ...
if isinstance(job.result, (MeshResult, VolumeResult, PointCloudResult, ImageResult)):
    return result_to_dict(job.result)
return job.result  # already a dict or None
```

(Apply the same pattern inside each handler that exposes `job.result`.)

- [ ] **Step 5: Run the full test suite.**

```bash
pytest -q
```
Expected: all pass. If any tests regressed, they probably expect the JSON-dict shape from `/jobs/.../result` — the wrap above restores that.

- [ ] **Step 6: Commit.**

```bash
git add ascribe_link/job_registry.py ascribe_link/routes/jobs.py ascribe_link/routes/specimens.py
git commit -m "Store raw result objects in Job; keep /jobs/result JSON for back-compat"
```

---

## Task 8: Static `.npy` volume specimens

**Files:**
- Create: `tests/fixtures/static_volume/metadata.json`
- Create: `tests/fixtures/static_volume/data.npy`
- Create: `tests/fixtures/static_volume/data.json`
- Modify: `ascribe_link/specimen_store.py`
- Modify: `ascribe_link/routes/specimens.py` — `_get_data_impl` static branch
- Create: `tests/test_static_volume.py`

- [ ] **Step 1: Write the fixture generator and the failing test.**

Create `tests/test_static_volume.py`:

```python
"""Tests for static .npy volume specimens."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import numpy as np
import pytest
from litestar.testing import AsyncTestClient

from ascribe_link.app import create_app
from ascribe_link.envelope import ENVELOPE_MEDIA_TYPE, decode_envelope
from ascribe_link.models import VolumeResult

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "static_volume"


@pytest.fixture(scope="module")
def fixture_specimens(tmp_path_factory) -> Path:
    """Write a real static volume specimen fixture once per test module."""
    root = tmp_path_factory.mktemp("specimens")
    spec_dir = root / "gaussian_static"
    spec_dir.mkdir()

    arr = np.random.RandomState(0).rand(16, 16, 16).astype(np.float32)
    np.save(spec_dir / "data.npy", arr)
    (spec_dir / "data.json").write_text(
        json.dumps({"spacing": [0.1, 0.2, 0.3], "origin": [1.0, 2.0, 3.0]})
    )
    (spec_dir / "metadata.json").write_text(
        json.dumps({
            "id": "gaussian_static",
            "display_name": "Static Gaussian",
            "description": "A static .npy volume specimen",
            "type": "volume",
            "data_file": "data.npy",
            "tags": ["static", "volume"],
        })
    )
    return root


@pytest.fixture
async def client(fixture_specimens: Path):
    app = create_app(specimens_dir=fixture_specimens)
    async with AsyncTestClient(app=app) as c:
        yield c


async def test_static_volume_listed(client):
    r = await client.get("/api/specimens/")
    r.raise_for_status()
    items = r.json()
    names = {item["id"] for item in items}
    assert "gaussian_static" in names
    entry = next(x for x in items if x["id"] == "gaussian_static")
    assert entry["type"] == "volume"


async def test_static_volume_data_is_envelope(client, fixture_specimens: Path):
    r = await client.get("/api/specimens/gaussian_static/data")
    r.raise_for_status()
    content_type = r.headers["content-type"].split(";")[0].strip()
    assert content_type == ENVELOPE_MEDIA_TYPE
    decoded = decode_envelope(r.content)
    assert isinstance(decoded, VolumeResult)
    assert decoded.shape == [16, 16, 16]
    assert decoded.spacing == [0.1, 0.2, 0.3]
    assert decoded.origin == [1.0, 2.0, 3.0]

    # Verify the bytes match the source.
    source = np.load(fixture_specimens / "gaussian_static" / "data.npy")
    np.testing.assert_array_equal(decoded.to_numpy(), source)


async def test_static_volume_without_sidecar(tmp_path):
    spec_root = tmp_path / "specimens"
    spec_dir = spec_root / "nosidecar"
    spec_dir.mkdir(parents=True)
    np.save(spec_dir / "data.npy", np.zeros((4, 4, 4), dtype=np.uint8))
    (spec_dir / "metadata.json").write_text(json.dumps({
        "id": "nosidecar",
        "display_name": "No Sidecar",
        "type": "volume",
        "data_file": "data.npy",
    }))
    app = create_app(specimens_dir=spec_root)
    async with AsyncTestClient(app=app) as c:
        r = await c.get("/api/specimens/nosidecar/data")
        r.raise_for_status()
        decoded = decode_envelope(r.content)
        assert decoded.spacing == [1.0, 1.0, 1.0]
        assert decoded.origin == [0.0, 0.0, 0.0]
```

- [ ] **Step 2: Run the test to verify it fails.**

```bash
pytest tests/test_static_volume.py -x -q
```
Expected: failure — either the specimen doesn't appear in the listing, or the `/data` endpoint returns a raw file rather than an envelope.

- [ ] **Step 3: Add a `.npy`-aware volume loader to `specimen_store.py`.**

Append to `ascribe_link/specimen_store.py`:

```python
def load_static_volume(spec_dir: Path, data_file: str) -> "VolumeResult":
    """Load a static volume specimen from disk (currently .npy + optional .json sidecar).

    Parameters
    ----------
    spec_dir : Path
        Directory containing the specimen bundle.
    data_file : str
        Filename (within spec_dir) of the volume data, e.g. "data.npy".

    Returns
    -------
    VolumeResult
    """
    from ascribe_link.models import VolumeResult  # avoid import cycle

    data_path = spec_dir / data_file
    if not data_path.exists():
        raise FileNotFoundError(f"volume data missing: {data_path}")
    if data_path.suffix.lower() != ".npy":
        raise ValueError(f"unsupported static volume format: {data_path.suffix}")

    arr = np.load(data_path, mmap_mode="r")
    if arr.ndim != 3:
        raise ValueError(f"static volume must be 3D, got ndim={arr.ndim}")

    sidecar = data_path.with_suffix(".json")
    spacing: list[float] | None = None
    origin: list[float] | None = None
    if sidecar.exists():
        meta = json.loads(sidecar.read_text())
        spacing = meta.get("spacing")
        origin = meta.get("origin")

    return VolumeResult.from_numpy(np.ascontiguousarray(arr), spacing=spacing, origin=origin)
```

Add `import json` and `import numpy as np` at the top of `specimen_store.py` if not already present.

- [ ] **Step 4: Modify the static branch of `_get_data_impl` in `routes/specimens.py`.**

Find this block at the end of `_get_data_impl`:

```python
        # Static specimen: return the file
        path = specimen_store.data_path(specimen_id)
        if path is None:
            raise NotFoundException(detail=f"Data file not found for: {specimen_id}")
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        return File(
            path=path,
            filename=meta.data_file,
            content_disposition_type="attachment",
            media_type=content_type,
        )
```

Replace with:

```python
        # Static specimen
        path = specimen_store.data_path(specimen_id)
        if path is None:
            raise NotFoundException(detail=f"Data file not found for: {specimen_id}")

        # Volumes → envelope; raw mesh files → stream as-is.
        if meta.type == SpecimenType.VOLUME and path.suffix.lower() == ".npy":
            from ascribe_link.specimen_store import load_static_volume
            result = load_static_volume(path.parent, path.name)
            return Response(
                content=encode_envelope(result),
                media_type=ENVELOPE_MEDIA_TYPE,
            )

        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        return File(
            path=path,
            filename=meta.data_file,
            content_disposition_type="attachment",
            media_type=content_type,
        )
```

- [ ] **Step 5: Verify `SpecimenStore.list()` picks up `.npy` specimens.**

Check `specimen_store.py` for any extension filters. The current implementation reads `metadata.json` and trusts the `data_file` value, so `.npy` should already work — verify by running the test.

- [ ] **Step 6: Re-run the static volume tests.**

```bash
pytest tests/test_static_volume.py -v
```
Expected: all four pass.

- [ ] **Step 7: Run the full suite.**

```bash
pytest -q
```
Expected: all pass.

- [ ] **Step 8: Commit.**

```bash
git add ascribe_link/specimen_store.py ascribe_link/routes/specimens.py tests/test_static_volume.py
git commit -m "Support static .npy volume specimens via envelope"
```

---

## Task 9: AI Generate auto-detect mesh vs. volume

**Files:**
- Modify: `ascribe_link/agent_generator.py`
- Create: `tests/test_agent_dispatch.py`

**Why:** Today `agent_generator.create_agent_function` returns a function whose return value is shaped as a mesh tuple/MeshResult. Make it produce a `VolumeResult` when the agent-produced value is a 3D `numpy.ndarray` (or already a `VolumeResult`).

- [ ] **Step 1: Inspect the current agent function's return handling.**

```bash
grep -n "return\|result\|MeshResult\|VolumeResult" ascribe_link/agent_generator.py | head -30
```

Identify where the agent's Python output is converted into a `MeshResult` (it should be near the bottom of the file, inside the inner function returned by `create_agent_function`).

- [ ] **Step 2: Write a failing test.**

Create `tests/test_agent_dispatch.py`:

```python
"""Tests for AI-agent output dispatch (mesh vs. volume)."""
from __future__ import annotations

import numpy as np

import ascribe_link.agent_generator as agent_gen
from ascribe_link.models import MeshResult, VolumeResult


def test_dispatch_3d_ndarray_to_volume():
    arr = np.ones((8, 8, 8), dtype=np.float32)
    result = agent_gen.wrap_agent_output(arr)
    assert isinstance(result, VolumeResult)
    assert result.shape == [8, 8, 8]


def test_dispatch_volume_result_passthrough():
    original = VolumeResult.from_numpy(np.zeros((2, 3, 4), dtype=np.float32))
    result = agent_gen.wrap_agent_output(original)
    assert result is original


def test_dispatch_mesh_result_passthrough():
    original = MeshResult(vertices=[0.0, 0.0, 0.0], indices=[0], normals=None)
    result = agent_gen.wrap_agent_output(original)
    assert result is original


def test_dispatch_pyvista_mesh_to_mesh_result():
    import pyvista as pv
    mesh = pv.Sphere(radius=1.0, theta_resolution=8, phi_resolution=8)
    result = agent_gen.wrap_agent_output(mesh)
    assert isinstance(result, MeshResult)
    assert len(result.vertices) > 0
    assert len(result.indices) > 0


def test_dispatch_unknown_raises():
    import pytest
    with pytest.raises(TypeError, match="cannot wrap agent output"):
        agent_gen.wrap_agent_output("not a mesh or volume")
```

- [ ] **Step 3: Run the test to verify it fails.**

```bash
pytest tests/test_agent_dispatch.py -x -q
```
Expected: `AttributeError: module 'ascribe_link.agent_generator' has no attribute 'wrap_agent_output'`.

- [ ] **Step 4: Add the dispatcher and wire it into `create_agent_function`.**

Append to `ascribe_link/agent_generator.py`:

```python
def wrap_agent_output(value: Any):
    """Coerce an arbitrary agent Python return value into a typed Result.

    Dispatch:
    - VolumeResult / MeshResult → passthrough
    - numpy.ndarray (ndim == 3) → VolumeResult.from_numpy
    - pyvista.PolyData / pyvista.UnstructuredGrid → MeshResult.from_pyvista
    - anything else → TypeError
    """
    import numpy as np
    from ascribe_link.models import MeshResult, VolumeResult

    if isinstance(value, (MeshResult, VolumeResult)):
        return value
    if isinstance(value, np.ndarray) and value.ndim == 3:
        return VolumeResult.from_numpy(np.ascontiguousarray(value.astype(np.float32)))
    try:
        import pyvista as pv
        if isinstance(value, pv.PolyData) or hasattr(value, "points") and hasattr(value, "faces"):
            return MeshResult.from_pyvista(value)
    except ImportError:
        pass
    raise TypeError(f"cannot wrap agent output of type {type(value).__name__}")
```

Then, inside the existing agent function (the one returned by `create_agent_function`), find the line where the agent's final value is converted into a `MeshResult`. Replace that conversion with a call to `wrap_agent_output`. The exact edit depends on the current structure — look for a pattern like:

```python
return MeshResult.from_pyvista(mesh)
```

or

```python
return MeshResult(vertices=..., indices=..., normals=...)
```

Replace with:

```python
return wrap_agent_output(<agent_value>)
```

where `<agent_value>` is whatever variable held the agent's raw Python return.

Add `from typing import Any` at the top of `agent_generator.py` if not already present.

- [ ] **Step 5: Re-run the dispatch tests.**

```bash
pytest tests/test_agent_dispatch.py -v
```
Expected: all five pass.

- [ ] **Step 6: Run the full suite.**

```bash
pytest -q
```
Expected: all pass. Agent-related integration tests (if any) should continue to work since mesh output still goes through `MeshResult`.

- [ ] **Step 7: Commit.**

```bash
git add ascribe_link/agent_generator.py tests/test_agent_dispatch.py
git commit -m "AI Generate: auto-detect volume vs. mesh from agent return value"
```

---

## Task 10: Server-side verification smoke test

**Files:** n/a (manual run)

- [ ] **Step 1: Start the server in the worktree.**

```bash
python -m ascribe_link --port 8001
```

(Use port 8001 to avoid colliding with any running dev server on 8000.)

- [ ] **Step 2: Verify the Gaussian volume is listed.**

In another terminal:

```bash
curl -sS http://localhost:8001/api/specimens/ | python -c "import sys,json; items=json.load(sys.stdin); print([x for x in items if x['id']=='generate_gaussian_volume'])"
```

Expected: a single-element list with `type == "volume"`, `is_dynamic == True`.

- [ ] **Step 3: Fetch the volume envelope and verify its shape.**

```bash
curl -sS http://localhost:8001/api/specimens/generate_gaussian_volume/data -o /tmp/gauss.bin
python -c "
import struct, json, numpy as np
data = open('/tmp/gauss.bin', 'rb').read()
plen, = struct.unpack('<I', data[:4])
preamble = json.loads(data[4:4+plen].decode())
print('preamble:', preamble)
arr = np.frombuffer(data, dtype=preamble['dtype'], count=np.prod(preamble['shape']), offset=4+plen).reshape(preamble['shape'])
print('shape:', arr.shape, 'peak:', arr.max(), 'min:', arr.min())
"
```

Expected output:
- `preamble: {'type': 'volume', 'shape': [64, 64, 64], 'dtype': 'float32', 'spacing': [...], 'origin': [0.0, 0.0, 0.0]}`
- `shape: (64, 64, 64) peak: 0.999... min: ~0.0`

- [ ] **Step 4: Fetch the sphere mesh envelope.**

```bash
curl -sS http://localhost:8001/api/specimens/generate_sphere/data -o /tmp/sphere.bin
python -c "
from ascribe_link.envelope import decode_envelope
r = decode_envelope(open('/tmp/sphere.bin','rb').read())
print('vertices:', len(r.vertices), 'indices:', len(r.indices), 'normals:', len(r.normals) if r.normals else 0)
"
```

Expected: `vertices: <some positive multiple of 3>, indices: <positive multiple of 3>, normals: <same as vertices>`.

- [ ] **Step 5: Stop the server and record results.**

Kill the server (`Ctrl+C`). Paste the smoke-test output into a new file `docs/VOLUME_TRANSMISSION_SMOKE.md` in the worktree — one-line confirmation that each check passed. This is a record for the client-side work.

```bash
git add docs/VOLUME_TRANSMISSION_SMOKE.md
git commit -m "Record volume transmission smoke-test results"
```

(If `docs/` doesn't exist in the server repo, create it.)

---

## Task 11: Open a PR for server-side work

**Files:** n/a

- [ ] **Step 1: Push the branch.**

```bash
git push -u origin volume-transmission
```

- [ ] **Step 2: Open a PR.**

```bash
gh pr create --title "Volumetric data transmission (server side)" --body "$(cat <<'EOF'
## Summary
- Adds a binary envelope wire format for mesh + volume results (`application/x-ascribe-envelope-v1`)
- Adds a built-in Parametric Gaussian Volume specimen
- Supports static `.npy` volume specimens with optional `.json` sidecar for spacing/origin
- AI Generate now auto-detects mesh vs. volume output
- Fixes the large-mesh JSON size limit by moving the hot `/data` path to raw bytes

Spec: `ascribe-xr/docs/superpowers/specs/2026-04-24-volumetric-transmission-design.md`

## Test plan
- [ ] `pytest` — all tests pass including new envelope / endpoint / static-volume / agent-dispatch suites
- [ ] Manual smoke test: `curl /api/specimens/generate_gaussian_volume/data` returns the envelope format
- [ ] Manual smoke test: `curl /api/specimens/generate_sphere/data` returns the envelope format (large meshes no longer JSON-size-limited)
- [ ] Client-side PR in ascribe-xr verifies end-to-end rendering
EOF
)"
```

- [ ] **Step 3: Share the PR URL in the client-side work (either as a comment on the client PR or a note in the worktree).**

---

## Self-Review Checklist (run before handoff)

- [ ] All tests in `tests/test_envelope.py`, `tests/test_parametric_volume.py`, `tests/test_envelope_endpoint.py`, `tests/test_static_volume.py`, `tests/test_agent_dispatch.py`, `tests/test_app_registration.py` pass.
- [ ] `pytest -q` on the full suite: all green.
- [ ] `ENVELOPE_MEDIA_TYPE == "application/x-ascribe-envelope-v1"` is referenced consistently.
- [ ] `VolumeResult.from_numpy` populates `_array` (Task 2).
- [ ] `_get_data_impl` dynamic path returns `Response(..., media_type=ENVELOPE_MEDIA_TYPE)` (Task 5).
- [ ] `_get_data_impl` static `.npy` branch returns envelope; static STL branch still returns `File()` (Task 8).
- [ ] `RoomResultCache` stores raw results (Task 6).
- [ ] `Job.result` is typed `Any`; `/jobs/{id}/result` still emits JSON dict for back-compat (Task 7).
- [ ] `wrap_agent_output` dispatches ndarray → volume, pyvista → mesh, passthrough for typed results (Task 9).
