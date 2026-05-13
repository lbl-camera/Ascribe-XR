# Multi-Specimen Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow multiple specimens to remain loaded simultaneously, with one "active" at a time owning interaction and attached menus, removable via a new MenuManager-slotted "Open Specimens" panel summoned by a controller button.

**Architecture:** Convert `SceneManager` from a single `current_3d_scene` to a list-with-cursor (`_open_specimens` + `_active_specimen`). Split `Specimen._enter_tree` into a no-op-tree-entry plus explicit `activate()` / `deactivate()` lifecycle calls driven by `SceneManager`. Add a new `open_specimens_menu` panel (`MenuManager` slot) bound to the left controller's free `ax_button` and keyboard `KEY_O`.

**Tech Stack:** GDScript, Godot 4, Godot XR Tools, gdUnit4 (for pure-helper unit tests).

**Spec:** `docs/superpowers/specs/2026-05-08-multi-specimen-management-design.md`

---

## File Map

**Modify:**
- `scripts/Specimen/specimen.gd` — split `_enter_tree` into `activate()` / `deactivate()`; remove menu-spawning from tree entry.
- `scripts/singletons/main.gd` — list-based state, new RPCs, refactored `load_specimen` and `_fetch_and_load_result`, scale-mode guard.
- `scripts/AscribeMain/ascribemain.gd` — bind `ax_button` (left) and `KEY_O` to toggle the open-specimens menu.

**Create:**
- `scenes/UI/open_specimens_menu.tscn` — Panel UI with a VBoxContainer for rows.
- `scripts/UI/open_specimens_menu.gd` — populates rows from `SceneManager.specimens_changed`, dispatches `set_active_specimen` / `remove_specimen` RPCs.
- `tests/test_scene_manager_helpers.gd` — gdUnit4 tests for the two pure helpers (`_next_active_after_remove`, `_can_load_with_scale_mode`).

---

## Task 1: Specimen lifecycle split (activate / deactivate)

Behavior-preserving refactor. After this task, `Specimen` no longer spawns its menus on tree entry; `SceneManager.load_specimen` calls `activate()` explicitly. Removal of the previous specimen still works as today (still freed in `_reset_world`), so external behavior is identical.

**Files:**
- Modify: `scripts/Specimen/specimen.gd`
- Modify: `scripts/singletons/main.gd`

- [ ] **Step 1: Refactor `Specimen` to expose `activate()` / `deactivate()`**

Replace the current `_enter_tree` body in `scripts/Specimen/specimen.gd` so that menu-spawning lives in `activate()` and `_enter_tree` only handles the pipeline:

```gdscript
## Base specimen class.
## Handles UI display via MenuManager, story text, and optional pipeline integration.
class_name Specimen
extends Node3D

enum ScaleMode {TABLE, WORLD}
@export var display_name: String
@export var thumbnail: Texture2D
@export var scale_mode: ScaleMode = ScaleMode.TABLE
@export var ui: PackedScene
@export var enabled: bool = true
@export_multiline var story_text: Array[String]

## Optional pipeline for data loading (can be configured in editor via SpecimenDef).
@export var pipeline: Pipeline

var ui_instance: Control
var _story_instance: Control
var _is_active: bool = false


func _enter_tree() -> void:
	# If a pipeline is configured, wire it up and run it.
	# Pipelines run regardless of active state so data is ready when we activate.
	if pipeline:
		pipeline.add_pickable.connect(_on_pipeline_pickable)
		pipeline.pipeline_error.connect(func(e): push_error("Specimen pipeline: " + e))
		pipeline.run_pipeline()


## Called by SceneManager when this specimen becomes active.
## Spawns the per-specimen UI and story panels into MenuManager slots.
## Sets process_mode back to INHERIT so physics/pickables resume.
func activate() -> void:
	if _is_active:
		return
	_is_active = true
	process_mode = Node.PROCESS_MODE_INHERIT

	if ui:
		ui_instance = ui.instantiate()
		MenuManager.show_menu(ui_instance, {
			"slot": "specimen",
			"screen_size": Vector2(3, 1.68),
			"viewport_size": Vector2(1152, 648),
			"distance": 2.5,
		})

	if story_text and story_text.size() > 0:
		var story_scene = preload("res://scenes/UI/story_ui.tscn")
		_story_instance = story_scene.instantiate()
		_story_instance.story = story_text
		MenuManager.show_menu(_story_instance, {
			"slot": "story",
			"screen_size": Vector2(3, 1.68),
			"viewport_size": Vector2(1152, 648),
			"distance": 1.5,
			"offset": Vector2(2.5, 0),
		})


## Called by SceneManager when this specimen is no longer active.
## Closes the menus owned by this specimen and freezes the subtree.
func deactivate() -> void:
	if not _is_active:
		return
	_is_active = false
	# MenuManager.show_menu reuses slots, so a new active will overwrite these
	# slots. The explicit close is for the case where this specimen is being
	# removed without another taking over.
	MenuManager.close_menu("specimen")
	MenuManager.close_menu("story")
	ui_instance = null
	_story_instance = null
	process_mode = Node.PROCESS_MODE_DISABLED


func _on_pipeline_pickable(pickable: Node3D) -> void:
	add_child(pickable)
```

- [ ] **Step 2: Update `SceneManager.load_specimen` to call `activate()` explicitly**

In `scripts/singletons/main.gd`, modify the body of `load_specimen` so that after `add_child` we call `activate()`. Replace the existing `load_specimen` function body:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func load_specimen(scene_path: String, config: Dictionary) -> void:
	_reset_world()

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("SceneManager: Failed to load scene: %s" % scene_path)
		return

	var specimen: Specimen = packed.instantiate()
	_apply_config(specimen, config)

	current_3d_scene = specimen
	specimens_root.add_child(specimen)
	_position_specimen(specimen)
	specimen.show()
	specimen.activate()
	hide_mainmenu()
```

Also update `_fetch_and_load_result` (around line 216-242) the same way — add `specimen.activate()` after `_position_specimen(specimen)`:

```gdscript
	current_3d_scene = specimen
	specimens_root.add_child(specimen)
	_position_specimen(specimen)
	specimen.show()
	specimen.activate()
	hide_mainmenu()
```

- [ ] **Step 3: Hand-test in XrSimulator**

Run the project (F5 in Godot editor with PC mode active). Open a static specimen from the main menu (e.g., "Heart" or "Brain Volume"). Verify:
- Specimen appears.
- Per-specimen UI panel appears (if the specimen defines `ui`).
- Story panel appears (if the specimen defines `story_text`).
- Open a different specimen: previous one disappears, new one's UI appears.

Behavior should be **identical** to before this task. If any menu fails to appear or any specimen fails to load, the lifecycle split is broken — debug before continuing.

- [ ] **Step 4: Commit**

```powershell
git add scripts/Specimen/specimen.gd scripts/singletons/main.gd
git commit -m "refactor: split Specimen lifecycle into activate/deactivate"
```

---

## Task 2: Pure helpers + gdUnit4 tests

The list-management logic (which index becomes active after a removal, whether a new scale_mode is compatible) is pure and worth unit-testing. Adding these helpers first lets later tasks use them with confidence.

**Files:**
- Create: `scripts/singletons/scene_manager_helpers.gd`
- Create: `tests/test_scene_manager_helpers.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_scene_manager_helpers.gd`:

```gdscript
extends GdUnitTestSuite


# next_active_after_remove rules (from spec):
# - If list becomes empty after the remove, return -1.
# - If the removed index is the active one, return the index of the
#   most-recently-added remaining specimen (i.e., new last index).
# - If the removed index is before the active one, active shifts down by 1.
# - If the removed index is after the active one, active stays put.


func test_remove_only_specimen_returns_minus_one():
	var result = SceneManagerHelpers.next_active_after_remove(1, 0, 0)
	assert_that(result).is_equal(-1)


func test_remove_active_with_others_picks_new_last_index():
	# 3 specimens, active=1, remove index 1 -> remaining size 2, new active = 1 (last)
	var result = SceneManagerHelpers.next_active_after_remove(3, 1, 1)
	assert_that(result).is_equal(1)


func test_remove_active_at_end_picks_new_last_index():
	# 3 specimens, active=2, remove index 2 -> remaining size 2, new active = 1 (last)
	var result = SceneManagerHelpers.next_active_after_remove(3, 2, 2)
	assert_that(result).is_equal(1)


func test_remove_below_active_shifts_active_down():
	# 3 specimens, active=2, remove index 0 -> active becomes 1
	var result = SceneManagerHelpers.next_active_after_remove(3, 0, 2)
	assert_that(result).is_equal(1)


func test_remove_above_active_leaves_active_alone():
	# 3 specimens, active=0, remove index 2 -> active stays 0
	var result = SceneManagerHelpers.next_active_after_remove(3, 2, 0)
	assert_that(result).is_equal(0)


# can_load_with_scale_mode rules:
# - Empty list: any scale mode allowed.
# - Non-empty list: only the existing list's scale mode is allowed.


func test_can_load_with_scale_mode_empty_list_allows_anything():
	assert_that(SceneManagerHelpers.can_load_with_scale_mode([], Specimen.ScaleMode.TABLE)).is_true()
	assert_that(SceneManagerHelpers.can_load_with_scale_mode([], Specimen.ScaleMode.WORLD)).is_true()


func test_can_load_with_scale_mode_matching_existing():
	var spec := _make_dummy_specimen(Specimen.ScaleMode.TABLE)
	assert_that(SceneManagerHelpers.can_load_with_scale_mode([spec], Specimen.ScaleMode.TABLE)).is_true()
	spec.queue_free()


func test_can_load_with_scale_mode_rejects_mismatch():
	var spec := _make_dummy_specimen(Specimen.ScaleMode.TABLE)
	assert_that(SceneManagerHelpers.can_load_with_scale_mode([spec], Specimen.ScaleMode.WORLD)).is_false()
	spec.queue_free()


func _make_dummy_specimen(mode: int) -> Specimen:
	var s := Specimen.new()
	s.scale_mode = mode
	return s
```

- [ ] **Step 2: Run tests and verify they fail**

Run from the project root:

```powershell
addons\gdUnit4\runtest.cmd -a tests/test_scene_manager_helpers.gd
```

Expected: FAIL with errors about `SceneManagerHelpers` being undefined.

- [ ] **Step 3: Implement the helpers**

Create `scripts/singletons/scene_manager_helpers.gd`:

```gdscript
## Pure helpers for SceneManager list-management. No side effects, no
## scene-tree access — easy to unit-test.
class_name SceneManagerHelpers


## Returns the new active index after removing `removed_idx` from a list of
## `list_size` specimens whose current active is `active_idx`.
## Returns -1 if the post-removal list is empty.
static func next_active_after_remove(list_size: int, removed_idx: int, active_idx: int) -> int:
	var new_size := list_size - 1
	if new_size <= 0:
		return -1
	if removed_idx == active_idx:
		# Most-recently-added remaining = new last index.
		return new_size - 1
	if removed_idx < active_idx:
		return active_idx - 1
	return active_idx


## Returns true iff a specimen with `new_scale_mode` may be added to a list
## of currently-open specimens. Empty list always allows; otherwise the new
## mode must match the existing list's mode.
static func can_load_with_scale_mode(open_specimens: Array, new_scale_mode: int) -> bool:
	for spec in open_specimens:
		if spec.scale_mode != new_scale_mode:
			return false
	return true
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
addons\gdUnit4\runtest.cmd -a tests/test_scene_manager_helpers.gd
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```powershell
git add scripts/singletons/scene_manager_helpers.gd tests/test_scene_manager_helpers.gd
git commit -m "feat: pure helpers for active-index and scale-mode checks"
```

---

## Task 3: SceneManager list-of-specimens state

Convert `SceneManager` from single-specimen state to list-with-cursor. After this task, opening a new specimen no longer frees the previous one, and the previous specimen freezes (because `set_active_specimen` calls `deactivate()` on it). UI to switch/remove doesn't exist yet — that comes in later tasks. Mixed scale_mode is also enforced.

**Files:**
- Modify: `scripts/singletons/main.gd`

- [ ] **Step 1: Replace state and add the new core methods**

In `scripts/singletons/main.gd`, replace the state declarations (lines 11-25) and the `load_specimen` / `_reset_world` / `_fetch_and_load_result` functions. Apply this diff:

Replace lines 11-15:
```gdscript
var world_3d: Node3D
var current_3d_scene: Node3D
var mainmenu: Node3D
var specimens_root: Node3D
```
with:
```gdscript
signal specimens_changed

var world_3d: Node3D
var mainmenu: Node3D
var specimens_root: Node3D

var _open_specimens: Array[Specimen] = []
var _active_specimen: Specimen = null
```

(Keep the procedural-UI / job-runner state declarations below — those are unrelated.)

- [ ] **Step 2: Replace `load_specimen` to append + activate, no longer frees**

Replace the existing `load_specimen` function body (around line 70-86) with:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func load_specimen(scene_path: String, config: Dictionary) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("SceneManager: Failed to load scene: %s" % scene_path)
		return

	# Refuse mixed scale modes.
	var probe: Specimen = packed.instantiate()
	if not SceneManagerHelpers.can_load_with_scale_mode(_open_specimens, probe.scale_mode):
		push_warning("SceneManager: refused to load %s (scale_mode mismatch with currently-open specimens)" % scene_path)
		probe.queue_free()
		return

	# Use the probe instance as the actual one (avoids a second instantiate).
	var specimen: Specimen = probe
	_apply_config(specimen, config)

	# First-load env transition: only if no specimens were open before.
	if _open_specimens.is_empty():
		_enter_specimen_mode_env(specimen)

	_open_specimens.append(specimen)
	specimens_root.add_child(specimen)
	_position_specimen(specimen)
	specimen.show()

	_set_active_local(_open_specimens.size() - 1)
	hide_mainmenu()
	specimens_changed.emit()
```

- [ ] **Step 3: Add the env-mode helpers and the local active setter**

Insert these helpers just below `load_specimen`:

```gdscript
## Apply the env transition that the old _reset_world used to perform on
## every load: show the world room, hide the empty-state floor, fire
## particles, set the room scene appropriate for this specimen's scale mode.
func _enter_specimen_mode_env(specimen: Specimen) -> void:
	world_3d.show()
	$/root/Main/Floor.hide()
	$/root/Main/GPUParticles3D.emitting = true
	# Note: set_room_scene is also called by _position_specimen via scale_mode,
	# so no explicit call needed here.


## Revert env to the empty-list / lobby state when the last specimen is
## removed.
func _exit_specimen_mode_env() -> void:
	world_3d.hide()
	$/root/Main/Floor.show()
	$/root/Main/GPUParticles3D.emitting = false


## Local (non-RPC) active setter. Caller is responsible for ensuring all
## peers eventually run this with the same index.
func _set_active_local(index: int) -> void:
	if index < 0 or index >= _open_specimens.size():
		_active_specimen = null
		return
	var target := _open_specimens[index]
	if _active_specimen == target:
		return
	if _active_specimen and is_instance_valid(_active_specimen):
		_active_specimen.deactivate()
	_active_specimen = target
	_active_specimen.activate()
```

- [ ] **Step 4: Remove or shrink `_reset_world`**

The old `_reset_world` did three things: (1) env transition, (2) close specimen/story menus, (3) free the current specimen. After this refactor:
- (1) is now `_enter_specimen_mode_env`, called only on first load.
- (2) is now `Specimen.deactivate()`, called by `_set_active_local`.
- (3) was the single-active-mode behavior we're removing.

Delete the `_reset_world` function (lines 95-105). Search for any remaining callers — there's one in `_fetch_and_load_result`. We update that next.

- [ ] **Step 5: Update `_fetch_and_load_result` to use the new flow**

Replace the body of `_fetch_and_load_result` (around line 216-242):

```gdscript
func _fetch_and_load_result(specimen_id: String, function_name: String, room_id: String) -> void:
	var metadata := await _fetch_metadata_for_active(specimen_id)

	var params_json := JSON.stringify(_active_params)
	var query := "params=%s&room_id=%s" % [params_json.uri_encode(), room_id.uri_encode()]
	var data_url := "%s/api/specimens/%s/data?%s" % [Config.ascribe_link_url, specimen_id, query]

	var scene_path := _scene_path_for_type(metadata.get("type", "mesh"))
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("SceneManager: Failed to load %s" % scene_path)
		return
	var specimen: Specimen = packed.instantiate()

	# Refuse mixed scale modes.
	if not SceneManagerHelpers.can_load_with_scale_mode(_open_specimens, specimen.scale_mode):
		push_warning("SceneManager: refused to load dynamic %s (scale_mode mismatch)" % specimen_id)
		specimen.queue_free()
		return

	specimen.data_url = data_url
	if "display_name" in specimen:
		specimen.display_name = metadata.get("display_name", specimen.display_name)

	if _open_specimens.is_empty():
		_enter_specimen_mode_env(specimen)

	_open_specimens.append(specimen)
	specimens_root.add_child(specimen)
	_position_specimen(specimen)
	specimen.show()

	_set_active_local(_open_specimens.size() - 1)
	# Procedural UI was already shown via show_procedural_ui; close it now that
	# the result is loaded.
	_close_procedural_ui()
	hide_mainmenu()
	specimens_changed.emit()
```

- [ ] **Step 6: Hand-test multi-specimen behavior**

Run the project. Test:
1. Open specimen A from the main menu. Verify it appears with menu.
2. Open specimen B (same scale_mode). Verify:
   - Specimen A is still visible in the scene.
   - Specimen A's menu is gone.
   - Specimen B's menu is showing.
   - Specimen A is "frozen" — try to interact with one of its pickables (a story button or a pipeline-added pickable). It should not respond.
3. Try to open a different-scale specimen (e.g., `sanfrancisco_topography` if currently open are TABLE-scale). Verify a warning is logged and the new one does not load.
4. Close all specimens (currently no UI for this — quit and restart, or skip until Task 4).

If any of these fail, debug. The order-of-operations between `add_child`, `_position_specimen`, and `activate()` matters.

- [ ] **Step 7: Commit**

```powershell
git add scripts/singletons/main.gd
git commit -m "feat: SceneManager keeps multiple specimens; previous freezes on new load"
```

---

## Task 4: set_active_specimen and remove_specimen RPCs

Now that the state model supports multiple, expose the operations needed by the new menu. After this task, you can switch active and remove specimens via the RPCs (testable from the editor's remote-debug console), but the menu UI is still in the next task.

**Files:**
- Modify: `scripts/singletons/main.gd`

- [ ] **Step 1: Add `set_active_specimen` RPC**

Insert below `_set_active_local`:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func set_active_specimen(index: int) -> void:
	if index < 0 or index >= _open_specimens.size():
		push_warning("SceneManager.set_active_specimen: invalid index %d (size=%d)" % [index, _open_specimens.size()])
		return
	_set_active_local(index)
	specimens_changed.emit()
```

- [ ] **Step 2: Add `remove_specimen` RPC**

Add below `set_active_specimen`:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func remove_specimen(index: int) -> void:
	if index < 0 or index >= _open_specimens.size():
		push_warning("SceneManager.remove_specimen: invalid index %d (size=%d)" % [index, _open_specimens.size()])
		return

	var active_idx := _open_specimens.find(_active_specimen)
	var new_active_idx := SceneManagerHelpers.next_active_after_remove(_open_specimens.size(), index, active_idx)

	var victim := _open_specimens[index]
	if victim == _active_specimen:
		victim.deactivate()
		_active_specimen = null
	_open_specimens.remove_at(index)
	victim.queue_free()

	if new_active_idx == -1:
		# List is empty — revert env and bring the main menu back.
		_exit_specimen_mode_env()
		show_mainmenu()
	else:
		_set_active_local(new_active_idx)

	specimens_changed.emit()
```

- [ ] **Step 3: Hand-test the RPCs**

In the running game, open the Godot editor's debugger console (or use `_unhandled_input` to wire a temporary key). Run:

1. Open three specimens A, B, C of the same scale_mode (C is active).
2. From the debug console, call `SceneManager.set_active_specimen.rpc(0)`. Verify A's menu now appears, C freezes.
3. Call `SceneManager.remove_specimen.rpc(2)` (removing C, which is not active). Verify C disappears, A still active.
4. Call `SceneManager.remove_specimen.rpc(0)` (removing A, which IS active). Verify A disappears, B becomes active (most-recently-added remaining).
5. Call `SceneManager.remove_specimen.rpc(0)` (removing the last one, B). Verify B disappears, env reverts (floor visible, world hidden, particles off), main menu re-appears.

If you can't easily reach the debug console, add a temporary keyboard binding in `ascribemain.gd` _input — e.g., KEY_1/2/3 for set_active and KEY_DELETE for remove of active. Remove these temporary bindings before committing.

- [ ] **Step 4: Commit**

```powershell
git add scripts/singletons/main.gd
git commit -m "feat: set_active_specimen and remove_specimen RPCs"
```

---

## Task 5: Open-specimens menu (UI)

Build the panel that lists open specimens with active-radio + remove-× per row. Subscribes to `specimens_changed`. After this task, the menu exists as a Control but isn't yet summoned by any input; that's Task 6.

**Files:**
- Create: `scenes/UI/open_specimens_menu.tscn`
- Create: `scripts/UI/open_specimens_menu.gd`

- [ ] **Step 1: Create the script**

Create `scripts/UI/open_specimens_menu.gd`:

```gdscript
## Lists currently-open specimens. Each row has:
##   - A radio indicator (active or not)
##   - The specimen's display_name
##   - A remove button (×)
##
## Tapping a row calls SceneManager.set_active_specimen.rpc(index).
## Tapping × calls SceneManager.remove_specimen.rpc(index).
##
## Subscribes to SceneManager.specimens_changed and rebuilds rows on the signal.
extends Panel

@onready var _vbox: VBoxContainer = $MarginContainer/VBoxContainer/RowsContainer
@onready var _empty_label: Label = $MarginContainer/VBoxContainer/EmptyLabel


func _ready() -> void:
	SceneManager.specimens_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	# Clear existing rows.
	for child in _vbox.get_children():
		child.queue_free()

	var specimens: Array = SceneManager._open_specimens
	var active: Specimen = SceneManager._active_specimen

	if specimens.is_empty():
		_empty_label.show()
		return
	_empty_label.hide()

	for i in range(specimens.size()):
		var spec: Specimen = specimens[i]
		var row := _build_row(i, spec, spec == active)
		_vbox.add_child(row)


func _build_row(index: int, specimen: Specimen, is_active: bool) -> Control:
	var row := HBoxContainer.new()

	# Radio dot — filled if active, empty otherwise. Plain text keeps things
	# robust without needing icon assets.
	var radio := Label.new()
	radio.text = "●  " if is_active else "○  "
	radio.add_theme_font_size_override("font_size", 32)
	row.add_child(radio)

	# Name button — tapping makes this specimen active.
	var name_btn := Button.new()
	name_btn.text = specimen.display_name if specimen.display_name else "(unnamed)"
	name_btn.flat = true
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.pressed.connect(func(): SceneManager.set_active_specimen.rpc(index))
	row.add_child(name_btn)

	# Remove button.
	var remove_btn := Button.new()
	remove_btn.text = "×"
	remove_btn.custom_minimum_size = Vector2(60, 60)
	remove_btn.pressed.connect(func(): SceneManager.remove_specimen.rpc(index))
	row.add_child(remove_btn)

	return row
```

- [ ] **Step 2: Create the scene**

Create `scenes/UI/open_specimens_menu.tscn` with this content. The `uid` field can be omitted entirely on first write — Godot will assign one on first import. The example below shows the structure with a placeholder; delete the `uid="..."` attribute if you want Godot to generate it:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/UI/open_specimens_menu.gd" id="1_script"]

[node name="OpenSpecimensMenu" type="Panel"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
custom_minimum_size = Vector2(500, 700)
script = ExtResource("1_script")

[node name="MarginContainer" type="MarginContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_constants/margin_left = 20
theme_override_constants/margin_top = 20
theme_override_constants/margin_right = 20
theme_override_constants/margin_bottom = 20

[node name="VBoxContainer" type="VBoxContainer" parent="MarginContainer"]
layout_mode = 2

[node name="Title" type="Label" parent="MarginContainer/VBoxContainer"]
layout_mode = 2
text = "Open Specimens"
theme_override_font_sizes/font_size = 36

[node name="HSeparator" type="HSeparator" parent="MarginContainer/VBoxContainer"]
layout_mode = 2

[node name="EmptyLabel" type="Label" parent="MarginContainer/VBoxContainer"]
layout_mode = 2
text = "No specimens open"
theme_override_font_sizes/font_size = 24

[node name="RowsContainer" type="VBoxContainer" parent="MarginContainer/VBoxContainer"]
layout_mode = 2
```

(The UID at the top will be regenerated by Godot on first import — accept whatever it picks. If `RowsContainer` and `EmptyLabel` resolve correctly via the `@onready` paths, the script will work.)

- [ ] **Step 3: Hand-test by manually summoning**

In the Godot editor, add a temporary one-shot to `ascribemain.gd`'s `_input` to summon the menu via `MenuManager`, just to verify the UI works end-to-end:

```gdscript
if event.keycode == KEY_O and event.pressed:
	var panel = preload("res://scenes/UI/open_specimens_menu.tscn").instantiate()
	MenuManager.show_menu(panel, {
		"slot": "open_specimens",
		"screen_size": Vector2(2, 2.5),
		"viewport_size": Vector2(500, 700),
	})
```

Run the project. Open two specimens. Press O. Verify:
- The panel appears in front of the user.
- Both specimens are listed; the active one shows a filled radio.
- Tapping the inactive row swaps active (radio fills move).
- Tapping × on a specimen removes it.
- Removing the last one closes the panel slot and re-shows the main menu.

This temporary KEY_O wiring will be replaced properly in Task 6 — but leave it for now if it works.

- [ ] **Step 4: Commit**

```powershell
git add scenes/UI/open_specimens_menu.tscn scripts/UI/open_specimens_menu.gd
git commit -m "feat: open-specimens menu panel"
```

---

## Task 6: Bind the toggle trigger

Wire the proper toggle bindings: left controller `ax_button` and `KEY_O` on keyboard. Replace any temporary KEY_O wiring from Task 5.

**Files:**
- Modify: `scripts/AscribeMain/ascribemain.gd`

- [ ] **Step 1: Add the toggle helper**

In `scripts/AscribeMain/ascribemain.gd`, add a new function modeled on `_toggle_network_gateway_menu`:

```gdscript
func _toggle_open_specimens_menu():
	if MenuManager.has_active_menu("open_specimens"):
		MenuManager.close_menu("open_specimens")
	else:
		var panel = preload("res://scenes/UI/open_specimens_menu.tscn").instantiate()
		MenuManager.show_menu(panel, {
			"slot": "open_specimens",
			"screen_size": Vector2(2, 2.5),
			"viewport_size": Vector2(500, 700),
		})
```

- [ ] **Step 2: Wire `ax_button` on the left controller**

In `vr_left_button_pressed` (around line 53), update the `ax_button` branch:

```gdscript
func vr_left_button_pressed(button: String):
	print("vr left button pressd ", button)
	if button == "ax_button":
		_toggle_open_specimens_menu()
	if button == "by_button":
		print("Publishing Right hand XR transforms to mqtt hand/pos")
```

- [ ] **Step 3: Wire `KEY_O` for desktop**

In `_input` (around line 61), add a KEY_O branch alongside the existing key handlers. Replace any temporary KEY_O wiring from Task 5 with:

```gdscript
		if event.keycode == KEY_O and event.pressed:
			_toggle_open_specimens_menu()
```

- [ ] **Step 4: Hand-test the full flow**

Run the project in PC mode. Test:
1. With no specimens open, press O. Menu shows "No specimens open".
2. Close it (press O again). Verify it animates closed.
3. Open two specimens via the main menu.
4. Press O. Menu lists both.
5. Tap the inactive specimen's row. Verify active swaps (radio moves, attached menu replaces).
6. Tap × on the inactive one. Verify it disappears.
7. Tap × on the now-only specimen. Verify env reverts and main menu re-appears.

If you have a Quest headset available, also verify left-controller A button toggles the menu the same way.

- [ ] **Step 5: Commit**

```powershell
git add scripts/AscribeMain/ascribemain.gd
git commit -m "feat: bind ax_button and KEY_O to open-specimens menu"
```

---

## Task 7: Multiplayer verification

No code changes expected unless issues are found. This is a verification task — run a two-peer session and validate cross-peer sync.

**Setup:** Two Godot instances, ENet, one as server one as client. (See `Config.PCstartupprotocol` / startup logic in `ascribemain.gd:_ready` for the existing protocol setup; ENet is the simplest to test on a single machine — set both to ENet, one as server, one as client.)

- [ ] **Step 1: Verify load syncing**

Server opens specimen A. Verify A appears on both peers, both show A's menu.

- [ ] **Step 2: Verify active-switch syncing**

Both peers have A and B open. Client opens its open-specimens menu and switches active to A. Verify both peers now show A as active.

- [ ] **Step 3: Verify remove syncing**

Client opens its open-specimens menu and removes A. Verify A disappears on both peers, both show B active.

- [ ] **Step 4: Verify last-removal env reset on both peers**

Client removes the last specimen. Verify both peers' env reverts and main menu re-appears.

- [ ] **Step 5: Document any divergences**

If you observe any cross-peer divergence (out-of-order indices, differing active state), capture a description in `docs/superpowers/MULTI_SPECIMEN_NOTES.md`. Known limitation: simultaneous loads from two peers may produce different list orders on different peers (per the spec). If you observe other issues, that's a bug — file and fix before proceeding.

- [ ] **Step 6: Commit (if any notes added)**

```powershell
# Only if MULTI_SPECIMEN_NOTES.md was created:
git add docs/superpowers/MULTI_SPECIMEN_NOTES.md
git commit -m "docs: multi-specimen multiplayer caveats observed during testing"
```

---

## Cleanup checklist

- [ ] Search for any leftover references to `current_3d_scene` in `scripts/singletons/main.gd` — should be zero.
- [ ] Search for any leftover references to `_reset_world` — should be zero.
- [ ] Confirm no `TODO` / `FIXME` comments were added.
- [ ] All gdUnit4 tests passing: `addons\gdUnit4\runtest.cmd -a tests/`.
