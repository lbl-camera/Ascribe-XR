# Refactoring Goals for Ascribe XR

## Overview

This document outlines refactoring opportunities identified in the Ascribe XR Godot VR project. The project has grown organically and would benefit from architectural improvements to increase maintainability, reduce code duplication, and improve testability.

---

## High Priority Issues

### 1. Break Up God Classes

**Problem:** `scripts/mesh_specimen.gd` is 546 lines handling too many responsibilities:
- File loading (STL/FBX/OBJ)
- Mesh building and vertex/normal manipulation
- RPC network synchronization
- UI updates
- Material/shader management
- Collision shape generation

**Refactoring Goal:** Split into focused classes:
- `MeshLoader` - File format handling
- `MeshNetworkSync` - RPC chunk transmission
- `MeshMaterialManager` - Shader/material application
- Keep `MeshSpecimen` as coordinator

**Files to modify:**
- `scripts/mesh_specimen.gd`

---

### 2. Eliminate Hardcoded Node Paths

**Problem:** Throughout the codebase, absolute node paths are hardcoded:
```gdscript
# scripts/main.gd lines 15-21
world_3d = $/root/Main/Sketchfab_Scene
mainmenu = $/root/Main/mainmenu
specimen_ui_viewport = $/root/Main/SpecimenUIViewport
```

This makes refactoring the scene tree risky and creates tight coupling.

**Refactoring Goal:** Create a `SceneRegistry` or `ServiceLocator` pattern:
- Register key nodes at startup
- Other scripts request nodes by name/type rather than path
- Alternatively, use Godot's group system or signals for node discovery

**Files to modify:**
- `scripts/main.gd`
- `scripts/ascribemain.gd`
- `scripts/dynamic_mesh_specimen.gd`

---

### 3. Fix Logic Bug in Scene Loading

**Problem:** `scripts/main.gd` lines 88-95 has a busy-wait loop with a logic error:
```gdscript
var i = 0
while specimens_root.get_child_count() == 0 and i<1000:
    i+=1
    await get_tree().process_frame
if i==100:  # BUG: Loop goes to 1000, but checks ==100
    push_error(...)
```

**Refactoring Goal:** Replace with signal-based approach or fix the boundary condition.

**Files to modify:**
- `scripts/main.gd` (lines 88-95)

---

### 4. Incomplete State Handling

**Problem:** `scripts/main.gd` lines 156-160, the `'world_scale'` case in the room match statement doesn't update `room_name`:
```gdscript
'world_scale':
	$/root/Main/Sketchfab_Scene.hide()
	$/root/Main/XROrigin3D/OpenXRFbPassthroughGeometry.hide()
	$/root/Main/Black.hide()
	# Missing: room_name = 'world_scale'
```

**Refactoring Goal:** Ensure all cases properly set state.

**Files to modify:**
- `scripts/main.gd` (line 156-160)

---

## Medium Priority Issues

### 5. Extract Duplicate VR Scroll Logic

**Problem:** Identical drag-to-scroll code appears in two files:
- `scripts/xrscroll.gd` (lines 21-67)
- `scripts/filedialog.gd` (lines 274-320)

Both have same variables: `is_dragging`, `drag_start_pos`, `scroll_start_pos`, `click_timer`, `drag_threshold`

**Refactoring Goal:** Create a shared `VRScrollHelper` utility class that both can use.

**Files to modify:**
- `scripts/xrscroll.gd`
- `scripts/filedialog.gd`
- Create: `scripts/utils/vr_scroll_helper.gd`

---

### 6. Consolidate Directory Refresh Logic

**Problem:** `scripts/filedialog.gd` has two near-identical functions:
- `_refresh_directory()` (lines 83-133) - 51 lines
- `_refresh_directory_no_history()` (lines 203-240) - 38 lines

Only difference is history tracking.

**Refactoring Goal:** Combine into single function with a `track_history: bool` parameter.

**Files to modify:**
- `scripts/filedialog.gd`

---

### 7. Centralize Configuration

**Problem:** Configuration values are scattered as `@export` variables and magic numbers:
- `ascribemain.gd` line 14: `"vision.lbl.gov"` (MQTT broker)
- `mesh_specimen.gd` line 228: `CHUNK_SIZE = 20000`
- `xrscroll.gd` line 11: `drag_threshold = 100`
- `filedialog.gd` line 34: `drag_threshold = 10` (different value!)
- `volumetric_specimen.gd` line 66: `Vector3i(256, 256, 10)` (hardcoded dimensions)

**Refactoring Goal:** Create a `Config` autoload or resource file:
- Network settings (broker URL, room names, protocols)
- UI settings (drag thresholds, scroll sensitivity)
- Data settings (chunk sizes, texture dimensions)

**Files to modify:**
- Create: `scripts/config.gd` (new autoload)
- Update all files with hardcoded values

---

### 8. Add class_name Declarations

**Problem:** Most scripts don't have `class_name` declarations. Only `Specimen` class has one.

**Refactoring Goal:** Add `class_name` to all script classes for:
- Better IDE support
- Type hinting
- Clearer code structure

**Files to modify:**
- All `.gd` files in `scripts/`

---

### 9. Create Data Source Abstraction

**Problem:** Multiple loading mechanisms with duplicated patterns:
- `mesh_specimen.gd`: File-based loading (STL/FBX/OBJ)
- `dynamic_mesh_specimen.gd`: MQTT-based loading
- `volumetric_specimen.gd`: Binary/ZIP loading

Each has different code paths that end up doing similar things.

**Refactoring Goal:** Create a `DataSource` interface/base class:
```gdscript
class_name DataSource
func load_data() -> Variant:
    pass
```
Then implement `FileDataSource`, `MQTTDataSource`, etc.

**Files to modify:**
- `scripts/mesh_specimen.gd`
- `scripts/dynamic_mesh_specimen.gd`
- `scripts/volumetric_specimen.gd`
- Create: `scripts/data_sources/` directory

---

### 10. Standardize Error Handling

**Problem:** Inconsistent error handling across the codebase:
- Some use `push_error()`
- Some use `push_warning()`
- Some silently return null
- Mix of `print()` and `print_debug()` for debugging

**Refactoring Goal:** Establish error handling conventions:
- Use `push_error()` for actual errors
- Use `push_warning()` for recoverable issues
- Remove debug `print()` statements or use a logging system

**Files to review:**
- All `.gd` files

---

## Lower Priority Issues

### 11. Clean Up Project Organization

**Problem:**
- `scenes/` has 26+ `.tscn` files with no categorization
- `.tscn.tmp` files exist in the repo
- `deprecated_specimens/` folder exists (should be removed or gitignored)
- Duplicate files in root and `scenes/` (mavic.glb)

**Refactoring Goal:**
- Organize scenes into subdirectories (ui/, environments/, specimens/)
- Clean up temp files
- Remove or archive deprecated content

---

### 12. Rename Confusing Autoload

**Problem:** The autoload is named `Ascribemain` but loads `main.gd`. This is confusing.

```
# project.godot
Ascribemain="*res://scripts/main.gd"
```

**Refactoring Goal:** Rename to something descriptive like `SceneManager` or `AppManager`.

**Files to modify:**
- `project.godot`
- All references to `Ascribemain` throughout codebase

---

### 13. Separate VR-Specific Code

**Problem:** Specimen classes assume VR context:
- `mesh_specimen.gd` line 349 references `$ScalableMultiplayerPickableObject`
- No abstraction for "viewing context"

**Refactoring Goal:** Create interfaces that abstract VR-specific behavior so specimens could theoretically work in non-VR mode.

---

### 14. Add Documentation

**Problem:** Minimal inline documentation and no architecture documentation.

**Refactoring Goal:**
- Add docstrings to public functions
- Create ARCHITECTURE.md explaining the system
- Document the data flow for specimen loading

---

## Summary Table

| Priority | Issue | Key Files |
|----------|-------|-----------|
| High | Break up mesh_specimen.gd god class | mesh_specimen.gd |
| High | Eliminate hardcoded node paths | main.gd, ascribemain.gd |
| High | Fix busy-wait loop bug | main.gd:88-95 |
| High | Fix incomplete room state | main.gd:156-160 |
| Medium | Extract VR scroll utility | xrscroll.gd, filedialog.gd |
| Medium | Consolidate refresh functions | filedialog.gd |
| Medium | Centralize configuration | Multiple files |
| Medium | Add class_name declarations | All scripts |
| Medium | Create data source abstraction | specimen classes |
| Medium | Standardize error handling | All scripts |
| Low | Clean up project organization | Project structure |
| Low | Rename Ascribemain autoload | project.godot |
| Low | Separate VR-specific code | Specimen classes |
| Low | Add documentation | All |

---

## Suggested Starting Point

For a student new to the project, I recommend starting with:

1. **Item #6 (Consolidate directory refresh)** - Small, self-contained, teaches refactoring basics
2. **Item #5 (Extract VR scroll logic)** - Creates reusable component, moderate complexity
3. **Item #8 (Add class_name)** - Quick wins throughout codebase, improves tooling

Then progress to harder items like #1 (breaking up god classes) and #2 (eliminating hardcoded paths).
