# Volume Transmission — Client E2E Validation Checklist

Run date: 2026-04-24
Client branch: `volume-transmission` (HEAD `78b1b66`)
Server dependency: ascribe-link branch `volume-transmission` pushed to origin (`5053d37`)

## Autonomous verification (already done)

- [x] Server runs the full envelope-serving flow under pytest: 73/73 tests pass.
- [x] Server curl smoke test: `/api/specimens/generate_gaussian_volume/data` returns `application/x-ascribe-envelope-v1` with a well-formed 64³ float32 payload; `/api/specimens/generate_sphere/data` returns envelope with 962 verts + 1920 triangles + normals; `/api/specimens/brain/data` (static mesh) still streams raw STL unchanged.
- [x] Client commits on branch (6): BinaryEnvelope parser → MeshData.set_from_bytes → VolumetricData.set_from_bytes → MeshSpecimen content-type branch → VolumeSpecimen data_url → SceneManager type dispatch. See `git log volume-transmission ^master`.
- [x] gdUnit test files written (3): `tests/test_binary_envelope.gd`, `tests/test_mesh_data_bytes.gd`, `tests/test_volumetric_data_bytes.gd`. **Not executed** because gdUnit4 plugin is not enabled in `project.godot` — run them in the Godot editor after enabling the plugin if you want regression guards.

## Manual E2E steps (user-driven)

### Prerequisites

- Start ascribe-link from the server worktree:
  ```bash
  cd ~/PycharmProjects/ascribe-link/worktrees/volume-transmission
  source .venv/Scripts/activate  # or your preferred venv activation
  ascribe-link
  ```
  Confirm startup log shows `generate_gaussian_volume` registered alongside `generate_sphere`/`generate_torus`.

- Open the vr-start worktree in Godot 4.6 (File → Open Project → `project.godot` in `worktrees/volume-transmission`). Let re-import finish. Press F5 to run in flat mode (no headset needed).

### Golden path tests

- [ ] **Step 1 — Parametric Gaussian Volume.**
  - Main menu should list "Parametric Gaussian Volume ⚙️" (gear icon = dynamic).
  - Click it → procedural parameter form appears.
  - Leave defaults (resolution=64, sigma=0.3). Click Submit.
  - **Expected:** loading layer shows briefly, then the volume renders in the `VolumeLayeredShader`. A Gaussian blob: bright center, dim edges.
  - Pass/fail: _______________

- [ ] **Step 2 — Large parametric sphere regression.**
  - Main menu → "Parametric Sphere ⚙️".
  - Bump resolution to its max in the form (128 or similar).
  - Submit.
  - **Expected:** loads successfully and renders (this was hitting JSON size limits before).
  - Pass/fail: _______________

- [ ] **Step 3 — Static `.npy` volume.**
  - In the server specimen directory, add a static volume bundle:
    ```python
    from pathlib import Path
    import json, numpy as np
    dest = Path("~/PycharmProjects/ascribe-link/specimens/static_gaussian").expanduser()
    dest.mkdir(parents=True, exist_ok=True)
    x = np.linspace(-0.5, 0.5, 64, dtype=np.float32)
    zz, yy, xx = np.meshgrid(x, x, x, indexing="ij")
    np.save(dest / "data.npy", np.exp(-(xx**2 + yy**2 + zz**2) / 0.1).astype(np.float32))
    (dest / "specimen.json").write_text(json.dumps({
        "id": "static_gaussian",
        "display_name": "Static Gaussian",
        "type": "volume",
        "data_file": "data.npy",
        "tags": ["static", "volume"],
    }))
    ```
    Note: the specimen metadata file is `specimen.json` (not `metadata.json`) per the `SpecimenStore` convention discovered during server Task 8.
  - Restart ascribe-link; the new specimen appears without the ⚙️ (static).
  - Click "Static Gaussian" in the XR menu.
  - **Expected:** loads and renders identically to the parametric version.
  - Pass/fail: _______________

- [ ] **Step 4 — AI Generate volume (optional).**
  - AI Generate requires Claude Agent SDK installed and `enable_agent=True` when launching ascribe-link (e.g. `ascribe-link --enable-agent`).
  - Main menu → "AI Generate ⚙️".
  - Prompt: "generate a 3D Gaussian blob at 32 voxels per side".
  - Submit.
  - **Expected:** agent produces a volume (using the existing `submit_volume` MCP tool); renders.
  - If the agent produces a mesh instead, that is also valid — the prompt is not deterministic. Try variants like "return a 3D numpy array" or "submit a volume using submit_volume".
  - Pass/fail: _______________

### Regression checks

- [ ] **Step 5 — Bundled brain mesh.** Main menu → "Brain" (no gear). Loads and renders. This is the static server-backed STL path that must continue streaming as a raw file via the existing pipeline.
- [ ] **Step 6 — Locally-bundled specimen (if any).** Any `.tscn` under the vr-start `specimens/` directory should still load via the local path unchanged (menu path doesn't involve ascribe-link).

## Known caveats

- **AI Generate volumes** depend on the agent actually calling `submit_volume` (MCP tool). The system prompt may need adjusting if the agent defaults to mesh. This is a prompt-engineering concern, not a code bug — out of scope for this PR.
- **gdUnit4 tests** live in `tests/` but won't run until you enable the plugin (`project.godot` → editor_plugins). Once enabled, they provide regression coverage for envelope parsing and `set_from_bytes` on both data classes.
- **WebRTC multiplayer** was not exercised. The flow should work (per-peer server fetch) but hasn't been E2E-tested in multiplayer.

## Sign-off

Record pass/fail above. If all "Expected" outcomes render correctly, this PR is ready for review.
