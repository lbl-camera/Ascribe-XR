# Developer Guide

This guide is for engineers working on the Ascribe-XR Godot project. It
covers the repository layout, the runtime architecture, the data pipeline,
multiplayer, and how to build and ship the app for desktop and Quest.

For an end-user perspective see the [User Guide](../user-guide/index.md).
For the backend service see the
[Ascribe-Link](https://github.com/ronpandolfi/Ascribe-Link) repo.

## Prerequisites

- **Godot 4.6+** (OpenXR build). `project.godot` declares
  `config/features=PackedStringArray("4.6", "Forward Plus")`.
- **Python 3.10+** — only needed for the data-prep scripts at the repo root
  and for running a local Ascribe-Link server.
- **Git LFS** — large mesh/volume samples in `specimen_data/` are stored
  via LFS (`.gitattributes`, `lfs.ps1`).
- **VR runtime** for headset testing: SteamVR or another OpenXR runtime
  (PCVR), or Meta Quest Link / Air Link. The
  [xr-simulator](../../addons/xr-simulator) addon lets you drive the app
  from keyboard/mouse without a headset.

## Repository layout

```
Ascribe-XR/
├── project.godot             # engine config; autoloads, input map, XR settings
├── scenes/                   # .tscn scenes
│   ├── Main/                 # ascribemain.tscn — top-level scene
│   ├── Staging/              # asribe_staging.tscn — startup/staging
│   ├── Player/               # VR rig (XROrigin + body)
│   ├── Rooms/                # environment scenes (lab, passthrough, black, ...)
│   ├── Specimen/             # base mesh/volume specimen templates
│   ├── UI/                   # menus (mainmenu, file dialog, procedural UI, ...)
│   └── pickable/             # multiplayer-pickable wrappers
├── specimens/                # bundled specimen scenes (one .tscn per dataset)
├── specimen_data/            # raw meshes/volumes (.stl, .fbx, .obj, .zip, .res, ...)
├── scripts/                  # GDScript sources, grouped by responsibility
│   ├── AscribeMain/          # top-level scene controller
│   ├── singletons/           # autoloaded scripts (see below)
│   ├── Specimen/             # Specimen base + MeshSpecimen + VolumeSpecimen
│   ├── DataSources/          # WHERE data comes from (file, HTTP, MQTT, …)
│   ├── DataLoaders/          # HOW data is loaded (sync, threaded, chunked)
│   ├── DataClasses/          # typed data containers (MeshData, VolumetricData, …)
│   ├── UI/                   # menu/panel controllers
│   ├── pickable/             # multiplayer pickable behaviour
│   ├── pipeline.gd           # Source → Loader → Data orchestrator
│   └── debug/                # dev overlays
├── shaders/                  # custom shaders (glass, hologram, raymarching, …)
├── addons/                   # third-party Godot plugins (see Addons section)
├── tests/                    # gdUnit4 unit tests
├── testscenes/               # ad-hoc dev scenes
├── tools/                    # one-off importers/converters (.gd, .py)
├── docs/                     # Sphinx documentation (this file lives here)
└── *.py, *.pkl, *.json       # Python data-prep scripts and intermediates
```

The `addons/` directory has both vendored and git-ignored plugins — see
`.gitignore`; missing addons need to be re-installed via the Asset Library
or by checkout from upstream.

## Runtime architecture

### Boot sequence

1. The application opens `scenes/Staging/asribe_staging.tscn` (set as the
   main scene by `project.godot:application/run/main_scene`).
2. Staging hands off to `scenes/Main/ascribemain.tscn`, whose root script
   is `scripts/AscribeMain/ascribemain.gd`.
3. `ascribemain.gd._ready()` reads `Config.QUESTstartupprotocol` /
   `Config.PCstartupprotocol` and brings up the network gateway (WebRTC
   over MQTT signalling, or raw ENet).
4. The main scene exposes hooks the rest of the app uses to find world
   nodes: `/root/Main/Sketchfab_Scene`, `/root/Main/mainmenu`,
   `/root/Main/Specimens`, the `XROrigin3D` rig, etc.

### Autoload singletons

Declared in `project.godot:[autoload]`:

| Name | File | Role |
| --- | --- | --- |
| `XRToolsUserSettings`, `XRToolsRumbleManager` | `addons/godot-xr-tools` | XR-tools state |
| `XrSimulator` | `addons/xr-simulator/XRSimulator.tscn` | Desktop XR sim |
| `SceneManager` | `scripts/singletons/main.gd` | Orchestrates specimen loading + multiplayer sync |
| `Config` | `scripts/singletons/config.gd` | Server URLs, network mode, chunk size |
| `MenuManager` | `scripts/singletons/menu_manager.gd` | Spawns VR menus into named slots |

`SceneManagerHelpers` (`scripts/singletons/scene_manager_helpers.gd`) is a
pure-function helper, not an autoload — it backs the unit tests in
`tests/test_scene_manager_helpers.gd`.

### SceneManager

`scripts/singletons/main.gd` is the heart of the runtime. It maintains
`_open_specimens: Array[Specimen]`, the active specimen, and the
environment state (lab / passthrough / black / world_scale rooms).

Two specimen flows live side-by-side:

**Static / bundled specimens** — one RPC, every peer instantiates the
same scene locally:

```
load_specimen.rpc(scene_path, config)
  → instantiate, _apply_config, scale_mode check
  → first specimen triggers _enter_specimen_mode_env (hides lobby floor)
  → _position_specimen + set_room_scene
  → _set_active_local + specimens_changed signal
```

**Dynamic specimens** — parametric jobs run on the Ascribe-Link server.
Every peer shows the same procedural form; only the submitter actually
runs the job; all peers then fetch the result from the server's per-room
cache:

```
show_procedural_ui.rpc(id, metadata)           # form on every peer
  ↓
request_submit (local)                          # submitter only
  ↓ specimen_job_submitted.rpc(...)
all peers enter loading state
  ↓ submitter: _run_job → AscribeLinkClient
job_progress → specimen_progress.rpc(text)
job_complete → specimen_job_done.rpc(id, fn, room_id)
  ↓
each peer independently fetches /api/specimens/{id}/data and renders
```

`_active_job_client` is held as a member because `AscribeLinkClient` is
`RefCounted` — a local-scoped reference would be freed before the HTTP
polling loop finishes.

The `ScaleMode` enum (`TABLE`, `WORLD`) gates room selection in
`_position_specimen` and prevents mixing world-scale and table-scale
specimens in the same session.

### Specimen base class

`scripts/Specimen/specimen.gd` defines the `Specimen` class. Key
properties:

- `display_name`, `thumbnail`, `enabled` — menu metadata.
- `scale_mode: ScaleMode` — `TABLE` or `WORLD`; controls environment.
- `ui: PackedScene` — per-specimen UI panel, opened in MenuManager's
  `"specimen"` slot when the specimen activates.
- `story_text: Array[String]` — narrative text shown in the `"story"`
  slot.
- `pipeline: Pipeline` — `Pipeline` resource (see below). If
  set, it runs as soon as the specimen enters the tree, regardless of
  active state, so data is ready by the time the user activates it.

Lifecycle: `_enter_tree()` starts the specimen with
`process_mode = DISABLED`; `SceneManager` calls `activate()` /
`deactivate()` to swap the UI in/out of MenuManager and gate
physics/pickables.

Two concrete subclasses:

- `MeshSpecimen` (`scripts/Specimen/mesh_specimen.gd`) — handles STL /
  FBX / OBJ loading (always threaded), runtime file-picker, mesh-RPC
  chunking, and the ascribe-link binary envelope path.
- `VolumeSpecimen` (`scripts/Specimen/volumetric_specimen.gd`) — wraps
  the `VolumeLayers` shader from `addons/volume_layered_shader`.

### Pipeline: source → loader → data

The data layer follows a Source / Loader / Target split:

```
DataSource           Loader                   Data
(where it is)        (how it loads)           (typed container)
─────────────        ──────────────           ────────────────
FileSource           SyncronousLoader         MeshData
HTTPSource           ThreadedLoader           VolumetricData
MQTTSource           ChunkedLoader            TopographicalData
RepoSource                                    (Data base class)
EmbeddedSource
RPCSource
AscribeLinkClient
```

`Pipeline` (`scripts/pipeline.gd`) wires the three together. It exposes
factory helpers for the common cases:

```gdscript
Pipeline.file_to_mesh(path)        # ThreadedLoader → MeshData
Pipeline.file_to_volume(path)      # SyncronousLoader → VolumetricData
Pipeline.http_to_mesh(parent, fn, args, kwargs, base_url)  # ascribe-link mesh
Pipeline.mqtt_to_mesh(...)         # deprecated; prefer http_to_mesh
```

A `Pipeline` can also be configured via a `SpecimenDef` resource
(`scripts/Specimen/SpecimenDef.gd`) — a `{source, loader}` pair you can
attach in the editor. `Pipeline.run_pipeline()` will infer the `Data`
target from the source's file extension or type.

Signals flow as: `source.data_available → loader.load_data →
loader.load_complete → pipeline_complete`. Progress is forwarded with
the source covering 0–0.5 and the loader 0.5–1.0.

When the resulting `Data` is `MeshData`, `Pipeline` auto-wraps the mesh
in `scenes/pickable/scalable_multiplayer_pickable.tscn`, builds a convex
collision shape, normalises scale to `TABLE_SIZE`, and emits
`add_pickable(node)` for the Specimen to parent.

### Ascribe-Link integration

`scripts/DataSources/ascribe_link_client.gd` is the HTTP client used for
both the static catalogue and dynamic jobs. The server URL comes from
`Config.ascribe_link_url`.

Key endpoints (see Ascribe-Link docs for full schema):

- `GET /api/specimens/` — catalogue
- `GET /api/specimens/{id}/data` — bytes for a specimen
- `GET /api/specimens/{id}/thumbnail` — preview image
- `GET /api/processing/functions` — registered dynamic-spec functions
- POST/run flow for dynamic jobs (driven via `AscribeLinkClient.run_job`)

**Binary envelope wire format** (`scripts/DataSources/binary_envelope.gd`,
media type `application/x-ascribe-envelope-v1`):

```
[4-byte LE uint32: preamble_length][JSON preamble][raw data blocks ...]
```

The JSON preamble carries `type` (`"mesh"` / `"volume"`) plus shape
info; the raw blocks are the contiguous numeric arrays. `MeshSpecimen`
detects the envelope by Content-Type and routes to
`MeshData.set_from_bytes(...)`. Older servers may return a JSON
dictionary instead; both code paths are kept.

### MenuManager and VR UI

`MenuManager` (`scripts/singletons/menu_manager.gd`) spawns UI panels
into named **slots**. Showing a new menu in an occupied slot closes the
previous one immediately, so callers don't need to track lifetimes.

```gdscript
MenuManager.show_menu(panel, {
    "slot": "specimen",
    "screen_size": Vector2(3, 1.68),
    "viewport_size": Vector2(1152, 648),
    "distance": 2.5,
    "offset": Vector2(2.5, 0),
    "on_close": Callable(...),
})
MenuManager.close_menu("specimen")
```

Slots in use: `"default"`, `"specimen"`, `"story"`, `"open_specimens"`,
`"network"`. The Specimen base owns `"specimen"` and `"story"`;
`AscribeMain` owns `"network"` and `"open_specimens"`. The procedural
form for dynamic specimens reuses the `"specimen"` slot — see the note
in `SceneManager._fetch_and_load_result` about closing it *before*
activating the result specimen to avoid the new menu being torn down.

Panels are rendered to a Viewport and positioned in front of the
`XRCamera3D`. `_position_in_front_of_user` falls back to a
`Main/MenuSpawnMarker` node if no camera is present (e.g. headless
testing).

### Multiplayer

Network bring-up lives in `addons/player-networking` and is hosted by
`AscribeMain` as `$NetworkGateway`. Two protocols are supported:

- **WebRTC over MQTT signalling** (default) — connects to the broker
  set by `Config.webrtcbroker` (default `vision.lbl.gov`) and joins the
  room named by `Config.webrtcroomname` (default `ascribe`). Both
  Quest and PC default to this path.
- **ENet** — direct UDP, PC-as-server / Quest-as-client. Selected by
  setting `Config.PCstartupprotocol` / `QUESTstartupprotocol` to `enet`.

All specimen state changes go through `SceneManager` RPCs annotated
`@rpc("any_peer", "call_local", "reliable")`, so every peer applies the
same change locally. This keeps the peers in sync with the host and the 
host in sync with the peers.

For mesh sync between peers, `MeshSpecimen._send_mesh` chunks vertices /
indices / normals into `Config.CHUNK_SIZE` (20 000) elements per RPC,
prefixed by a metadata chunk with expected sizes. Receivers reassemble
in `_receive_mesh_data` and rebuild the `MeshData`.

### Pickables

`scripts/pickable/` provides the multiplayer-aware variants of
godot-xr-tools' pickable:

- `multiplayer_pickable.gd` — base
- `multiplayer_pickable_audio.gd` — adds grab/release sfx
- `scalable_multiplayer_pickable.gd` — two-handed scale + the wrapper
  the `Pipeline` factory uses for mesh specimens

### Shaders

`shaders/` contains the per-material shaders selectable from the mesh
specimen UI (glass, hologram, crystal, pearl, jello, water, brick,
edges, holographic, raymarching). `MeshSpecimen._set_shader` resolves a
material by name: first tries `shaders/<name>.tres`, then falls back to
building a `ShaderMaterial` from `shaders/<name>.gdshader`.

The volume specimen relies on `5d_volume_shader.gdshader` and
`volume_shader_improved.gdshader` via the layered-volume addon.

## Addons

`project.godot:[editor_plugins]` enables `godot-xr-tools`,
`import_cleaner`, and `volume_layered_shader`. Other directories under
`addons/` are runtime libraries pulled in as needed:

- `godot-xr-tools`, `godotopenxrvendors`, `xr-autohandtracker`,
  `xr-simulator` — XR rig, vendor extensions, sim
- `webrtc`, `mqtt`, `twovoip`, `player-networking` — networking + voice
- `volume_layered_shader` — volume rendering
- `terrain_3d`, `stl_importer` — terrain + import helpers
- `gdUnit4` — test framework

Most of these are git-ignored (`.gitignore` lists them under `# plug`)
and must be installed from the Asset Library or vendored manually.

## Python data prep

The scripts at the repo root convert third-party datasets into shapes the
runtime can ingest:

| Script | Purpose |
| --- | --- |
| `importer.py` | Generic importer entry point |
| `load_ct_head.py`, `load_cthead_volume.py` | CT-head dataset → volume |
| `get_mesh_data.py` | Pull mesh arrays out of a source file |
| `submit_ct_head.py`, `submit_final.py`, `extract_for_submission.py` | Helpers used when packaging meshes for an ascribe-link server |
| `tools/tiff-converter.py` | TIFF stack → volume |

Generated intermediates live alongside as `.pkl` and `.json`
(`ct_mesh_data.pkl`, `cthead_mesh.json`, `vertices.pkl`, `indices.pkl`,
`mesh_submission.json`). These are not consumed by the runtime
directly — they feed the ascribe-link server or are converted into the
binary blobs under `specimen_data/`.

A typical loop is:

```bash
python load_ct_head.py        # produce ct_mesh_data.pkl
python submit_ct_head.py      # upload to a running ascribe-link instance
```

## Adding a new specimen

**Static / bundled:**

1. Drop the data file into `specimen_data/` (STL/FBX/OBJ for meshes,
   `.zip` / `.res` for volumes).
2. Create a new **inherited scene** in `specimens/` from `scenes/Specimen/specimen.tscn`
   or `scenes/Specimen/volumetric_specimen.tscn`.
3. Set the `Specimen` exports: `display_name`, `thumbnail`, `enabled`,
   `scale_mode`, and either `loading_file` (for `MeshSpecimen`) or wire
   a `SpecimenDef` / `Pipeline`.
4. The main menu scans `res://specimens/` on launch
   (`scripts/UI/mainmenuflat.gd:scenes_directory`) and lists every
   `.tscn` whose root `Specimen.enabled` is `true`.

**Dynamic (server-side):**

1. Register the function on the ascribe-link server (see backend docs).
2. The function's `specimen.json` schema drives the auto-generated
   parameter form (`scripts/UI/procedural_link_ui.gd`).
3. No client changes required — the catalogue endpoint advertises
   dynamic specimens with a marker the menu uses to show the gear icon.

<!-- ## Testing

Unit tests live in `tests/` and use **gdUnit4** (`addons/gdUnit4`).
Files are pure GDScript (`extends GdUnitTestSuite`) and exercise the
side-effect-free helpers — see `tests/test_scene_manager_helpers.gd`,
`test_binary_envelope.gd`, `test_mesh_data_bytes.gd`,
`test_volumetric_data_bytes.gd`.

Run from the editor: open the gdUnit4 panel and hit "Run all" (or run a
single suite). There is currently no headless CI hook for tests; the
only GitHub Action (`.github/workflows/docs.yml`) builds the Sphinx
documentation.

When adding a new bit of logic, prefer pulling pure functions into a
helper class (as `SceneManagerHelpers` does) so it can be tested
without standing up the scene tree. -->

## Building and exporting

Export presets are committed in `export_presets.cfg`. Open
**Project → Export…** in Godot to use them.

### Desktop (Windows / Linux)

1. Install the matching Godot **export templates** (Editor → Manage
   Export Templates).
2. Pick the desktop preset, set an output path (e.g. `build/ascribe-xr.exe`),
   click **Export Project**.
3. Ship the produced binary plus the generated `.pck` alongside.

### Android / Quest

1. Install the Android SDK + JDK and configure their paths in
   Godot Editor Settings under **Export → Android**.
2. Generate a debug keystore once (`lfs.ps1` is unrelated; use the
   standard `keytool` flow) and point Godot at it.
3. Use the Quest export preset — it relies on the
   `godotopenxrvendors` addon for Meta-specific extensions and the
   `meta/passthrough` OpenXR extension enabled in `project.godot`.
4. Export as APK (or AAB for Play Store / MQDH releases).
5. Deploy with `adb install -r build/ascribe-xr.apk` or SideQuest.

`*.apk`, `*.aab`, `*.exe`, `*.pck`, and `*.keystore` are git-ignored —
treat the build output as throwaway.

### Documentation

Docs are built with Sphinx + MyST (`docs/conf.py`, `docs/requirements.txt`).

Local build:

```bash
pip install -r docs/requirements.txt
sphinx-build -W -b html docs docs/_build
```

`.github/workflows/docs.yml` runs the same `sphinx-build -W -b html docs
public --keep-going` on every push to `master` and publishes to GitHub
Pages.

## Configuration cheatsheet

Edit `scripts/singletons/config.gd` to change runtime defaults:

```gdscript
@export var ascribe_link_url     = "http://vision.lbl.gov:8000"
@export var webrtcbroker         = "vision.lbl.gov"
@export var webrtcroomname       = "ascribe"
@export var PCstartupprotocol    = "webrtc"   # or "enet"
@export var QUESTstartupprotocol = "webrtc"   # or "enet"
const CHUNK_SIZE                 = 20000      # mesh RPC chunk size
```

For a local ascribe-link server, set
`ascribe_link_url = "http://127.0.0.1:8000"` (avoid `localhost` on
Windows because of IPv6 resolution issues — see the comment in
`config.gd`).

## Conventions

- `.editorconfig` enforces UTF-8, trimmed trailing whitespace, and a
  final newline on `*.gd` files.
- Class names use `class_name` so types can be referenced across files;
  prefer typed signals and `@export` over untyped script-side wiring.
- Singletons orchestrate; specimens own their UI; pure logic goes into
  side-effect-free helpers (testable in isolation).
- New top-level scenes belong in `scenes/`; ad-hoc experiments belong
  in `testscenes/`.

## Where to look next

- `REFACTORING.md` and `REFACTORING-9.md` — recent architectural notes
  (specimen list, multi-specimen UI, dynamic specimen flow).
- `docs/superpowers/` — design specs and plans for in-flight work
  (excluded from the published docs build by `docs/conf.py`).


