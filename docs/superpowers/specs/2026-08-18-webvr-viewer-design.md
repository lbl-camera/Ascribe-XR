# WebVR Viewer ("ascribe-web") — Design

**Date:** 2026-08-18
**Status:** Approved design, pre-implementation
**Repo:** new sibling repository `ascribe-web` (this doc lives in vr-start because the design was brainstormed here; copy or move it into the new repo when scaffolded)

## Purpose

A simplified browser-based viewer so group members can show their scientific
visualization work (volumes, meshes, and explanatory story panels) to external
people via a plain web link. No server, no agent access, no multiplayer —
static files only.

## Decisions (with rationale)

| Decision | Choice | Why |
|---|---|---|
| Engine | New minimal Godot 4 project, Compatibility renderer | Reuses the volume raymarch shader and `x-ascribe-envelope-v1` decoders from ascribe-xr; one engine for the group. Rejected: stripping ascribe-xr (wasm-less GDExtensions, dual-renderer maintenance) and three.js (full shader rewrite, second stack). |
| Content delivery | Baked static bundles | No public server, no CORS, no auth. Hostable on GitHub Pages or any static host. |
| Viewing modes | Desktop 3D (orbit/pan/zoom, mouse+touch) first-class + WebXR "Enter VR" for headset browsers | External audiences mostly lack headsets. |
| Authoring | Separate Python CLI (`ascribe-bundle`), hatch + hatch-vcs | File-based authoring; can import ascribe-link's serialization code. |
| Volume precision | float16 (`Image.FORMAT_RH` → R16F) default; 8-bit L8 optional for size | R16F linear filtering is core WebGL2; R32F and normalized R16 both require non-universal extensions. f16 ≈ 11-bit significand, adequate dynamic range for CT-style data, 2 bytes/voxel. R32F is not supported in the web viewer. |
| Threading | Single-threaded web export | No COOP/COEP headers needed → works on dumb static hosts. Chunked awaited decoding avoids main-thread stalls. |

## Repo layout

```
ascribe-web/
├── viewer/             Godot 4 project, Compatibility renderer
│   ├── shaders/        volume raymarcher (ported copy of
│   │                   addons/volume_layered_shader/shaders/volume_shader.gdshader, web-tuned)
│   ├── scripts/        vendored VolumetricData/MeshData decoders + viewer logic
│   └── export_presets.cfg   Web preset only
└── bundler/            Python CLI "ascribe-bundle" (pyproject.toml, hatch + hatch-vcs)
```

Deployed artifact: `index.html` + wasm/pck (built once, shared) + one `bundle/`
directory per publication. Viewer reads `?bundle=<url>` so one hosted viewer
serves many bundles.

Author workflow: `ascribe-bundle build my_volume.npy --story story.md -o out/`
→ copy `out/` to a static host → send the link.

## Bundle format

`manifest.json` is the contract between the CLI and the viewer:

```json
{
  "version": 1,
  "title": "...",
  "specimens": [
    { "id": "...", "type": "volume|mesh",
      "data": "specimen_0.bin",
      "display": { "gamma": 1.0, "opacity": 1.0, "gradient": "..." } }
  ],
  "story": [
    { "text": "markdown...", "image": "fig1.png", "specimen": "id" }
  ]
}
```

- Data blobs are `application/x-ascribe-envelope-v1` verbatim (existing format:
  `[u32 LE preamble_len][JSON preamble][raw blocks]`). CLI imports ascribe-link's
  serialization; viewer vendors the existing GDScript decoders
  (`scripts/DataClasses/volumetric_data.gd`, `mesh_data.gd`). No new wire formats.
- Volumes: float16 by default (`--dtype u8` for smallest size). Manifest/envelope
  preamble declares dtype.
- CLI inputs: numpy arrays / TIFF stacks (volumes), an ascribe-link specimen ID
  (fetched from a running server), or a saved envelope file.
- Story: markdown file, pages split on `---`, images referenced relatively.
  A page may pin a specimen id; v1 shows one specimen at a time.

## Viewer components

- **BundleLoader** — fetches manifest + blobs via `HTTPRequest` with relative
  URLs (same-origin, no CORS needed); decodes envelopes asynchronously with a
  progress bar; chunked to avoid main-thread stalls.
- **SpecimenStage** — one specimen scene at a time (volume or mesh), ported from
  ascribe-xr specimen scenes minus multiplayer/pickable code. Display settings
  from manifest; small on-screen panel for gamma/opacity/step-quality.
- **ViewController** — desktop: orbit/pan/zoom camera (mouse + touch). XR:
  `WebXRInterface` with a ~100-line grab-to-rotate/scale handler for the single
  specimen. No godot-xr-tools dependency.
- **StoryPanel** — markdown → BBCode in `RichTextLabel`, inline images,
  Previous/Next, switches staged specimen when a page pins one. Sidebar on
  desktop; floating panel anchored near the specimen in XR.

## Web constraints & quality

- Raymarcher `max_steps` / `step_size` get three tiers (desktop / mobile / XR),
  auto-selected by platform, user-overridable.
- Size budget: engine ~10 MB compressed + bundle data. CLI warns above a
  configurable bundle-size threshold (default 100 MB); `--max-dim` downsampling.
- Known risk, addressed first: the raymarch shader under WebGL2 + WebXR
  multiview on Quest browser is unproven. **Milestone 0 is a walking skeleton:
  shader + one f16 volume rendering in WebXR on Quest browser, before any UI.**

## Error handling

- Viewer: every load failure (missing file, bad manifest version, envelope
  mismatch, unsupported dtype) shows a human-readable error screen — never a
  black canvas. Manifest `version` checked.
- CLI: validates inputs and manifest schema at build time; refuses to emit
  bundles the viewer can't load (e.g. R32F volumes).

## Testing

- CLI: pytest — envelope round-trips against golden files, manifest schema
  validation, f16/u8 conversion correctness.
- Viewer: gdUnit4 for decoder + manifest parsing; a checked-in tiny procedural
  test bundle (few KB) doubles as CI smoke test and demo.

## Out of scope (v1)

Multiplayer, voice, agent access, live ascribe-link catalog browsing, R32F
volumes, multiple simultaneous specimens, terrain/room environments.

## Build order

1. Walking skeleton: Compatibility project + ported shader + hardcoded f16
   volume rendering on desktop web and Quest browser WebXR (kills the top risk).
2. Bundle format + CLI (envelope reuse, manifest, tests).
3. BundleLoader + SpecimenStage (manifest-driven loading, error screens).
4. ViewController (desktop orbit; XR grab).
5. StoryPanel + polish (quality tiers, progress UI, demo bundle).
