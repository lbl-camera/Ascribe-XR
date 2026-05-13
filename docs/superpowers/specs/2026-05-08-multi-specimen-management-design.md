# Multi-Specimen Management Design

**Status:** Approved (brainstorm 2026-05-08)

## Goal

Today, opening a specimen frees the previous one. This design lets the user keep
multiple specimens loaded simultaneously and switch between them, with one
"active" specimen at a time owning user interaction and attached UI. Removal
happens through a new dedicated menu.

## User-Facing Behavior

- Opening a specimen from the existing main menu **adds** it to the open list
  and makes it the new active specimen. Previously-open specimens remain in the
  scene, visible, but **frozen** — no menus, no pickable interaction.
- A new "Open Specimens" menu, summoned via a controller button or keyboard
  key, lists all currently-open specimens. Each row has:
  - A radio indicator showing which is active
  - The specimen's display name
  - A `×` button to remove that specimen
- Tapping a row makes that specimen active (closing the previous active's
  attached menus and bringing up the new one's).
- Removing the active specimen activates the most-recently-added remaining
  specimen. If the list becomes empty, the main menu re-appears.

## Architecture

The change is concentrated in two places: the `SceneManager` autoload (which
gains list-with-cursor state) and the `Specimen` class (which gains a split
lifecycle). One new menu scene+script is added. No other systems are touched.

### `SceneManager` (`scripts/singletons/main.gd`)

State changes:
- Replace `current_3d_scene: Node3D` with `_open_specimens: Array[Specimen]`.
- Add `_active_specimen: Specimen` (or null).
- Add `signal specimens_changed` for the menu UI to subscribe to.

New RPCs (all `@rpc("any_peer", "call_local", "reliable")`):
- `set_active_specimen(index: int)` — deactivates the current active,
  activates the specimen at `index`.
- `remove_specimen(index: int)` — frees that specimen, removes it from the
  list, applies the active-fallback rules.

`load_specimen` modifications:
- No longer calls `_reset_world()`. The existing `_reset_world` body is split:
  - "Enter specimen mode" env setup (`world_3d.show()`, `Floor.hide()`,
    `GPUParticles3D.emitting = true`, `set_room_scene(...)`) runs only when
    the list was empty before this load.
  - UI/menu closes are now part of `Specimen.deactivate()`; specimen freeing
    is part of `remove_specimen`.
- After instantiating, append to `_open_specimens` and call
  `set_active_specimen(_open_specimens.size() - 1)`.
- The dynamic-specimen result path (`_fetch_and_load_result`) uses the same
  append-and-activate logic.

When the list returns to empty (via `remove_specimen` of the last entry),
revert env: `world_3d.hide()`, `Floor.show()`, `GPUParticles3D.emitting =
false`. Then `show_mainmenu()`.

Mixed `ScaleMode` guard: when `load_specimen` is invoked with a scale_mode
different from the currently-open specimens, push a warning and abort the
load. (Toast UI is out of scope for this design — `push_warning` only.)

### `Specimen` (`scripts/Specimen/specimen.gd`)

Split lifecycle:
- `_enter_tree`: keeps the pipeline wiring/run only. No menu spawning.
- `activate()`: instantiates and shows the `ui` panel into the
  `MenuManager` "specimen" slot, and the `story_text` panel into the "story"
  slot, exactly as `_enter_tree` does today. Sets
  `process_mode = PROCESS_MODE_INHERIT`.
- `deactivate()`: closes the "specimen" and "story" slots if this specimen
  owned them, frees `ui_instance`, sets `process_mode = PROCESS_MODE_DISABLED`.
  Disabling process mode freezes physics on the entire subtree, so XRTools
  pickables in that specimen become inert. The specimen remains visible.

Note that slot reuse in `MenuManager` already auto-closes the previous slot
occupant. `deactivate()`'s explicit `close_menu` call is defense-in-depth in
case activation order is interrupted.

### New: `scenes/UI/open_specimens_menu.tscn` + `scripts/UI/open_specimens_menu.gd`

A `Panel` with a `VBoxContainer` that builds one row per open specimen on
`SceneManager.specimens_changed`:

```
┌──────────────────────────────────┐
│  ●  Brain Volume          [×]    │
│  ○  San Francisco Topo    [×]    │
│  ○  Heart                 [×]    │
└──────────────────────────────────┘
```

- Row tap: calls `SceneManager.set_active_specimen.rpc(index)`.
- `×` tap: calls `SceneManager.remove_specimen.rpc(index)`.
- Empty list shows a "No specimens open" label.

Summoned via `MenuManager.show_menu(panel, {"slot": "open_specimens", ...})`,
toggled by:
- Left controller `ax_button` (currently unbound — `ascribemain.gd:55-56`).
- A desktop keyboard key (proposing `KEY_O`) added to the `_input` handler in
  `ascribemain.gd`.

## Data Flow

**Loading a new specimen** (existing flow plus list-append):
1. User taps an item in the static main menu (`mainmenuflat.gd`).
2. `SceneManager.load_specimen.rpc(scene_path, config)` fires on every peer.
3. Each peer: env setup if list was empty → instantiate → append to list →
   `set_active_specimen(index)` → `hide_mainmenu()` → emit
   `specimens_changed`.

**Switching active**:
1. User taps a row in the open-specimens menu.
2. `SceneManager.set_active_specimen.rpc(index)` on every peer.
3. Each peer: deactivate current active → activate the target → emit
   `specimens_changed`.

**Removing**:
1. User taps `×` on a row.
2. `SceneManager.remove_specimen.rpc(index)` on every peer.
3. Each peer: if removing active, deactivate → `queue_free` → remove from
   list → if list empty, `show_mainmenu()` and tear down env setup; else
   activate most-recently-added remaining → emit `specimens_changed`.

## Defaults & Edge Cases

| Case | Behavior |
|---|---|
| Open new specimen | Appended; auto-activates. |
| Same specimen opened twice | Allowed; each instance has independent state. |
| Specimen count cap | None. |
| Mixed `ScaleMode` | Refuse the mismatched load; `push_warning`. |
| Remove the active one | Most-recently-added remaining becomes active. |
| Remove the last one | Main menu re-appears; env setup is reset (floor, particles, etc). |
| Cross-peer simultaneous loads | Per-sender ordering preserved; cross-sender interleaving may produce divergent list orders. Accepted limitation for phase 1. |

## Out of Scope

- Per-specimen positioning (each specimen at its own marker rather than
  relocating `specimens_root`). Without it, multiple TABLE specimens overlap.
  User explicitly accepted this.
- VRAM/perf budgeting for many concurrent specimens.
- Toast UI for the mixed-scale-mode warning. `push_warning` only.
- Persistence of the open list across rejoin.
- A "previous active" history stack.

## Testing

- PC mode (XrSimulator), single peer:
  - Open A, open B, confirm A frozen and visible, B active with menu.
  - Switch active to A via the open-specimens menu — B freezes, A unfreezes.
  - Remove A while B is active — A disappears, B unaffected.
  - Remove last specimen — main menu reappears, floor/particles reset.
  - Open a TABLE specimen, then attempt a WORLD specimen — load is refused,
    warning logged.
- Multiplayer (two peers, ENet):
  - Peer A loads specimen X — both peers see X active.
  - Peer B switches active via their open-specimens menu — both peers update.
  - Peer A removes a specimen — both peers' lists shrink consistently.

Hand-test only; existing project has no automated test harness for this layer.
