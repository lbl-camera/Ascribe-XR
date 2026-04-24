# Volume Transmission — Client (ascribe-xr / vr-start) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the XR client consume the binary envelope wire format emitted by ascribe-link for both mesh and volume results: parse the envelope, feed it into `MeshData` / `VolumetricData`, give `VolumeSpecimen` an HTTP data-URL path, and make the post-job specimen instantiation type-aware.

**Architecture:** Add one shared parser (`BinaryEnvelope`) that reads the length-prefixed JSON preamble. `MeshData` and `VolumetricData` each get a `set_from_bytes(preamble, body, offset)` method. `MeshSpecimen` gains a content-type branch for the envelope media type. `VolumeSpecimen` mirrors `MeshSpecimen`'s `data_url` flow. `SceneManager._fetch_and_load_result` branches on the specimen type (mesh vs. volume) to pick the right scene.

**Tech Stack:** Godot 4.4 GDScript, gdUnit4 for unit tests (addon already vendored at `addons/gdUnit4`). Spec reference: `docs/superpowers/specs/2026-04-24-volumetric-transmission-design.md`.

**Worktree:** Work inside `~/Documents/vr-start/worktrees/volume-transmission` on branch `volume-transmission` (branched from `master`). The server-side work (see `2026-04-24-volume-transmission-server.md`) must be running locally during the final E2E task.

---

## File Structure

**New files:**
- `scripts/DataSources/binary_envelope.gd` — envelope parser (static methods)
- `tests/test_binary_envelope.gd` — gdUnit tests for parser
- `tests/test_mesh_data_bytes.gd` — gdUnit tests for `MeshData.set_from_bytes`
- `tests/test_volumetric_data_bytes.gd` — gdUnit tests for `VolumetricData.set_from_bytes`

**Modified files:**
- `scripts/DataClasses/mesh_data.gd` — add `set_from_bytes`
- `scripts/DataClasses/volumetric_data.gd` — add `set_from_bytes`
- `scripts/Specimen/mesh_specimen.gd` — content-type dispatch for envelope
- `scripts/Specimen/volumetric_specimen.gd` — add `data_url` export and HTTP fetch
- `scripts/singletons/main.gd` — `SceneManager._fetch_and_load_result` type branch

---

## Task 0: Prepare worktree

**Files:** n/a (git operations only)

- [ ] **Step 1:** Create the worktree from the vr-start repo root.

```bash
cd ~/Documents/vr-start
git worktree add -b volume-transmission worktrees/volume-transmission
cd worktrees/volume-transmission
```

- [ ] **Step 2:** Open the worktree in the Godot editor (File → Open Project → select `project.godot` in the worktree). Let Godot re-import assets.

- [ ] **Step 3:** Confirm gdUnit4 is enabled. Project Settings → Plugins → `GdUnit4` should be enabled (it's vendored at `addons/gdUnit4`).

- [ ] **Step 4:** Run the existing test scenes under `testscenes/` if any are relevant (no pass/fail needed — just verify the project opens). Commit nothing.

---

## Task 1: Add `BinaryEnvelope` parser

**Files:**
- Create: `scripts/DataSources/binary_envelope.gd`
- Create: `tests/test_binary_envelope.gd`

- [ ] **Step 1: Write failing gdUnit tests for the parser.**

Create `tests/test_binary_envelope.gd`:

```gdscript
extends GdUnitTestSuite


func _build_envelope(preamble_json: String, body: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var preamble_bytes := preamble_json.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, preamble_bytes.size())
	out.append_array(preamble_bytes)
	out.append_array(body)
	return out


func test_media_type_constant():
	assert_that(BinaryEnvelope.MEDIA_TYPE).is_equal("application/x-ascribe-envelope-v1")


func test_parse_valid_envelope():
	var env := _build_envelope('{"type":"mesh","vertex_count":0,"vertex_dtype":"float32","index_count":0,"index_dtype":"uint32","normal_count":0,"normal_dtype":"float32"}')
	var parsed = BinaryEnvelope.parse(env)
	assert_that(parsed.has("preamble")).is_true()
	assert_that(parsed["preamble"]["type"]).is_equal("mesh")
	assert_that(parsed["offset"]).is_equal(env.size())  # no body blocks


func test_parse_with_trailing_body():
	var body := PackedByteArray([1, 2, 3, 4, 5])
	var env := _build_envelope('{"type":"volume","shape":[1,1,1],"dtype":"uint8","spacing":[1,1,1],"origin":[0,0,0]}', body)
	var parsed = BinaryEnvelope.parse(env)
	assert_that(parsed["preamble"]["type"]).is_equal("volume")
	assert_that(parsed["offset"]).is_equal(env.size() - body.size())


func test_parse_truncated_length_prefix():
	var parsed = BinaryEnvelope.parse(PackedByteArray([0x01, 0x00]))
	assert_that(parsed.has("error")).is_true()
	assert_that(parsed["error"]).contains("length prefix")


func test_parse_truncated_preamble():
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, 100)  # claims 100 bytes of preamble
	out.append(0x7B)  # but only gives one byte
	var parsed = BinaryEnvelope.parse(out)
	assert_that(parsed.has("error")).is_true()
	assert_that(parsed["error"]).contains("preamble")


func test_parse_invalid_json():
	var env := _build_envelope("not json")
	var parsed = BinaryEnvelope.parse(env)
	assert_that(parsed.has("error")).is_true()
	assert_that(parsed["error"]).contains("JSON")
```

- [ ] **Step 2: Run the tests to verify they fail.**

Open the gdUnit panel in the Godot editor (bottom dock → GdUnit) and run `tests/test_binary_envelope.gd`. Expected: all fail with "class `BinaryEnvelope` not found."

Alternatively from the command line (if `GdUnitCmdTool` is configured):

```bash
# from worktree root
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/test_binary_envelope.gd
```

- [ ] **Step 3: Implement `scripts/DataSources/binary_envelope.gd`.**

```gdscript
## Binary envelope parser for the ascribe-link wire format.
##
## Layout:
##     <4-byte little-endian uint32: preamble_length>
##     <preamble_length bytes: UTF-8 JSON preamble>
##     <raw bytes: one or more contiguous data blocks>
class_name BinaryEnvelope
extends RefCounted

const MEDIA_TYPE := "application/x-ascribe-envelope-v1"


## Parse the envelope header.
##
## Returns a Dictionary:
##   - On success: {"preamble": Dictionary, "offset": int}
##   - On failure: {"error": String}
static func parse(body: PackedByteArray) -> Dictionary:
	if body.size() < 4:
		return {"error": "envelope truncated: missing length prefix"}
	var preamble_len := body.decode_u32(0)
	if body.size() < 4 + preamble_len:
		return {"error": "envelope truncated: preamble incomplete (claimed %d bytes, got %d)" % [preamble_len, body.size() - 4]}
	var preamble_bytes := body.slice(4, 4 + preamble_len)
	var preamble_str := preamble_bytes.get_string_from_utf8()
	var preamble = JSON.parse_string(preamble_str)
	if preamble == null or not (preamble is Dictionary):
		return {"error": "envelope: invalid JSON preamble"}
	return {"preamble": preamble, "offset": 4 + preamble_len}
```

- [ ] **Step 4: Re-run the tests; all six pass.**

Expected: all pass in the gdUnit panel.

- [ ] **Step 5: Commit.**

```bash
git add scripts/DataSources/binary_envelope.gd tests/test_binary_envelope.gd
git commit -m "Add BinaryEnvelope parser for ascribe-link wire format"
```

---

## Task 2: `MeshData.set_from_bytes`

**Files:**
- Modify: `scripts/DataClasses/mesh_data.gd`
- Create: `tests/test_mesh_data_bytes.gd`

- [ ] **Step 1: Write failing tests.**

Create `tests/test_mesh_data_bytes.gd`:

```gdscript
extends GdUnitTestSuite


func _build_mesh_envelope(vertices: PackedFloat32Array, indices: PackedInt32Array, normals: PackedFloat32Array) -> Dictionary:
	var preamble := {
		"type": "mesh",
		"vertex_count": vertices.size() / 3,
		"vertex_dtype": "float32",
		"index_count": indices.size(),
		"index_dtype": "uint32",
		"normal_count": normals.size() / 3,
		"normal_dtype": "float32",
	}
	var body := PackedByteArray()
	body.append_array(vertices.to_byte_array())
	body.append_array(indices.to_byte_array())
	body.append_array(normals.to_byte_array())
	return {"preamble": preamble, "body": body}


func test_set_from_bytes_with_normals():
	var verts := PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	var inds := PackedInt32Array([0, 1, 2])
	var norms := PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0])
	var pkg := _build_mesh_envelope(verts, inds, norms)

	var data := MeshData.new()
	var ok: bool = data.set_from_bytes(pkg["preamble"], pkg["body"], 0)
	assert_that(ok).is_true()
	assert_that(data.vertices).is_equal(verts)
	assert_that(data.indices).is_equal(inds)
	assert_that(data.normals).is_equal(norms)


func test_set_from_bytes_without_normals():
	var verts := PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	var inds := PackedInt32Array([0, 1, 2])
	var preamble := {
		"type": "mesh",
		"vertex_count": 3,
		"vertex_dtype": "float32",
		"index_count": 3,
		"index_dtype": "uint32",
		"normal_count": 0,
		"normal_dtype": "float32",
	}
	var body := PackedByteArray()
	body.append_array(verts.to_byte_array())
	body.append_array(inds.to_byte_array())

	var data := MeshData.new()
	var ok: bool = data.set_from_bytes(preamble, body, 0)
	assert_that(ok).is_true()
	assert_that(data.vertices).is_equal(verts)
	assert_that(data.indices).is_equal(inds)
	assert_that(data.normals.size()).is_equal(0)


func test_set_from_bytes_with_nonzero_offset():
	var verts := PackedFloat32Array([0.0, 0.0, 0.0])
	var inds := PackedInt32Array([0, 0, 0])
	var preamble := {
		"type": "mesh",
		"vertex_count": 1,
		"vertex_dtype": "float32",
		"index_count": 3,
		"index_dtype": "uint32",
		"normal_count": 0,
		"normal_dtype": "float32",
	}
	var prefix := PackedByteArray([0xDE, 0xAD, 0xBE, 0xEF])  # simulated preamble offset
	var body := prefix.duplicate()
	body.append_array(verts.to_byte_array())
	body.append_array(inds.to_byte_array())

	var data := MeshData.new()
	var ok: bool = data.set_from_bytes(preamble, body, prefix.size())
	assert_that(ok).is_true()
	assert_that(data.vertices).is_equal(verts)
```

- [ ] **Step 2: Run to verify failure.**

Expected: `set_from_bytes` not found on `MeshData`.

- [ ] **Step 3: Add `set_from_bytes` to `scripts/DataClasses/mesh_data.gd`.**

Append to the class:

```gdscript
## Set data from the binary envelope body.
##
## `preamble` is the dict returned by `BinaryEnvelope.parse`.
## `body` is the full response body (including the preamble).
## `offset` is the byte position where the data blocks start (preamble["offset"]).
##
## Returns true on success, false on error (malformed preamble or body-too-short).
func set_from_bytes(preamble: Dictionary, body: PackedByteArray, offset: int) -> bool:
	if preamble.get("type", "") != "mesh":
		push_error("MeshData.set_from_bytes: preamble.type is not 'mesh'")
		return false

	var vc: int = int(preamble.get("vertex_count", 0))
	var ic: int = int(preamble.get("index_count", 0))
	var nc: int = int(preamble.get("normal_count", 0))

	var vertex_bytes := vc * 3 * 4
	var index_bytes := ic * 4
	var normal_bytes := nc * 3 * 4
	var required := offset + vertex_bytes + index_bytes + normal_bytes
	if body.size() < required:
		push_error("MeshData.set_from_bytes: body too short (need %d, got %d)" % [required, body.size()])
		return false

	var cursor := offset
	if vc > 0:
		vertices = body.slice(cursor, cursor + vertex_bytes).to_float32_array()
	else:
		vertices = PackedFloat32Array()
	cursor += vertex_bytes

	if ic > 0:
		indices = body.slice(cursor, cursor + index_bytes).to_int32_array()
	else:
		indices = PackedInt32Array()
	cursor += index_bytes

	if nc > 0:
		normals = body.slice(cursor, cursor + normal_bytes).to_float32_array()
	else:
		normals = PackedFloat32Array()

	_cached_mesh = null
	data_ready.emit()
	return true
```

- [ ] **Step 4: Re-run tests; all three pass.**

- [ ] **Step 5: Commit.**

```bash
git add scripts/DataClasses/mesh_data.gd tests/test_mesh_data_bytes.gd
git commit -m "MeshData: add set_from_bytes for binary envelope path"
```

---

## Task 3: `VolumetricData.set_from_bytes`

**Files:**
- Modify: `scripts/DataClasses/volumetric_data.gd`
- Create: `tests/test_volumetric_data_bytes.gd`

- [ ] **Step 1: Write failing tests.**

Create `tests/test_volumetric_data_bytes.gd`:

```gdscript
extends GdUnitTestSuite


func test_set_from_bytes_uint8():
	# 2x2x2 volume of uint8 values: 0,1,2,3,4,5,6,7 (C-order: [z,y,x])
	var voxels := PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7])
	var preamble := {
		"type": "volume",
		"shape": [2, 2, 2],
		"dtype": "uint8",
		"spacing": [1.0, 1.0, 1.0],
		"origin": [0.0, 0.0, 0.0],
	}

	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes(preamble, voxels, 0)
	assert_that(ok).is_true()
	assert_that(data.get_dimensions()).is_equal(Vector3i(2, 2, 2))
	var tex := data.get_data()
	assert_that(tex).is_not_null()
	assert_that(tex is Texture3D).is_true()


func test_set_from_bytes_float32():
	# 1 voxel of float32 value 1.5
	var body := PackedFloat32Array([1.5]).to_byte_array()
	var preamble := {
		"type": "volume",
		"shape": [1, 1, 1],
		"dtype": "float32",
		"spacing": [2.0, 2.0, 2.0],
		"origin": [10.0, 20.0, 30.0],
	}
	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes(preamble, body, 0)
	assert_that(ok).is_true()
	assert_that(data.get_spacing()).is_equal(Vector3(2.0, 2.0, 2.0))


func test_set_from_bytes_wrong_type_rejected():
	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes({"type": "mesh"}, PackedByteArray(), 0)
	assert_that(ok).is_false()


func test_set_from_bytes_body_too_short():
	var preamble := {
		"type": "volume",
		"shape": [4, 4, 4],
		"dtype": "float32",
		"spacing": [1, 1, 1],
		"origin": [0, 0, 0],
	}
	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes(preamble, PackedByteArray([0, 0, 0, 0]), 0)
	assert_that(ok).is_false()
```

- [ ] **Step 2: Run to verify failure.**

Expected: `set_from_bytes` not found on `VolumetricData`.

- [ ] **Step 3: Add `set_from_bytes` to `scripts/DataClasses/volumetric_data.gd`.**

Append to the class:

```gdscript
## Set data from the binary envelope body.
##
## `preamble` is the dict returned by `BinaryEnvelope.parse`.
## `body` is the full response body (including the preamble).
## `offset` is the byte position where the volume bytes start.
##
## Returns true on success, false on error.
func set_from_bytes(preamble: Dictionary, body: PackedByteArray, offset: int) -> bool:
	if preamble.get("type", "") != "volume":
		push_error("VolumetricData.set_from_bytes: preamble.type is not 'volume'")
		return false

	var shape = preamble.get("shape", [])
	if shape.size() != 3:
		push_error("VolumetricData.set_from_bytes: shape must have 3 elements")
		return false
	var depth: int = int(shape[0])
	var height: int = int(shape[1])
	var width: int = int(shape[2])
	_dimensions = Vector3i(width, height, depth)

	var dtype: String = preamble.get("dtype", "float32")
	var bytes_per_voxel := _get_bytes_per_voxel(dtype)
	var slice_bytes := width * height * bytes_per_voxel
	var total_bytes := depth * slice_bytes

	if body.size() < offset + total_bytes:
		push_error("VolumetricData.set_from_bytes: body too short (need %d, got %d)" % [offset + total_bytes, body.size()])
		return false

	var spacing_arr = preamble.get("spacing", [1.0, 1.0, 1.0])
	var origin_arr = preamble.get("origin", [0.0, 0.0, 0.0])
	if spacing_arr.size() >= 3:
		# Preamble order is [sz, sy, sx]; Godot Vector3 is [x, y, z].
		_spacing = Vector3(spacing_arr[2], spacing_arr[1], spacing_arr[0])
	if origin_arr.size() >= 3:
		_origin = Vector3(origin_arr[2], origin_arr[1], origin_arr[0])

	var images: Array[Image] = []
	for z in range(depth):
		var start := offset + z * slice_bytes
		var end := start + slice_bytes
		var slice_buf := body.slice(start, end)
		var img := _create_image_from_bytes(slice_buf, width, height, dtype)
		if img == null:
			push_error("VolumetricData.set_from_bytes: failed to create image for slice %d" % z)
			return false
		images.append(img)

	var tex := ImageTexture3D.new()
	tex.create(width, height, depth, images[0].get_format(), false, images)
	_texture = tex
	data_ready.emit()
	return true
```

- [ ] **Step 4: Re-run tests; all four pass.**

- [ ] **Step 5: Commit.**

```bash
git add scripts/DataClasses/volumetric_data.gd tests/test_volumetric_data_bytes.gd
git commit -m "VolumetricData: add set_from_bytes for binary envelope path"
```

---

## Task 4: `MeshSpecimen` envelope content-type branch

**Files:**
- Modify: `scripts/Specimen/mesh_specimen.gd:81-133` (method `_on_data_url_completed`)

**Why:** Today the handler branches on `application/json` vs. "anything else treated as a binary file." The envelope format uses `application/x-ascribe-envelope-v1` — needs its own branch that parses via `BinaryEnvelope` and feeds `MeshData.set_from_bytes`.

- [ ] **Step 1: Open `scripts/Specimen/mesh_specimen.gd` and find the `_on_data_url_completed` function.** Confirm its current structure: content-type check → JSON dict path → else: temp-file + pipeline.

- [ ] **Step 2: Modify the function.**

Replace the body of `_on_data_url_completed` (starting after the progress bar / cleanup at the top):

```gdscript
func _on_data_url_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if ui_instance:
		var progress_bar = ui_instance.get_node_or_null("%ProgressBar")
		if progress_bar:
			progress_bar.value = 1.0

	if _data_http_request:
		_data_http_request.queue_free()
		_data_http_request = null

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("MeshSpecimen: Data request failed: result=%d, code=%d" % [result, response_code])
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()
		return

	var content_type := _get_content_type(headers)

	# New hot path: ascribe-link binary envelope.
	if content_type == BinaryEnvelope.MEDIA_TYPE:
		_load_from_envelope(body)
		return

	# Legacy path: JSON dict from /api/processing/invoke or older servers.
	if content_type.begins_with("application/json") or content_type.begins_with("text/json"):
		var result_data = JSON.parse_string(body.get_string_from_utf8())
		if result_data is Dictionary:
			_load_from_result_dict(result_data)
		else:
			push_error("MeshSpecimen: Failed to parse JSON from %s" % data_url)
			if ui_instance:
				ui_instance.get_node("LoadingLayer").hide()
		return

	# Fallback: raw file (STL/OBJ/FBX). Write to temp and feed into the pipeline.
	var file_ext = _get_file_extension(headers, data_url)
	var temp_path = "user://temp_specimen." + file_ext
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("MeshSpecimen: Failed to create temp file")
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()
		return
	file.store_buffer(body)
	file.close()
	_send_after_load = false
	_load_file(temp_path)
```

- [ ] **Step 3: Add the `_load_from_envelope` helper.**

Append to the class:

```gdscript
func _load_from_envelope(body: PackedByteArray) -> void:
	var parsed := BinaryEnvelope.parse(body)
	if parsed.has("error"):
		push_error("MeshSpecimen: envelope parse failed: %s" % parsed["error"])
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()
		return

	var preamble: Dictionary = parsed["preamble"]
	if preamble.get("type", "") != "mesh":
		push_error("MeshSpecimen: expected envelope type 'mesh', got %s" % preamble.get("type", "<none>"))
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()
		return

	var mesh_data := MeshData.new()
	mesh_data.flip_normals = flip_normals
	if not mesh_data.set_from_bytes(preamble, body, parsed["offset"]):
		push_error("MeshSpecimen: MeshData.set_from_bytes failed")
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()
		return

	_mesh_data = mesh_data
	_set_mesh_from_data(mesh_data)
```

- [ ] **Step 4: Verify no regressions in the manual flow.**

Open the project in Godot. Smoke test: run the project, pick a locally bundled mesh specimen (any `.tscn` in `specimens/`). It should still load as before — this code path doesn't touch local bundles.

- [ ] **Step 5: Commit.**

```bash
git add scripts/Specimen/mesh_specimen.gd
git commit -m "MeshSpecimen: accept binary envelope content-type from /data"
```

---

## Task 5: `VolumeSpecimen` gains `data_url` HTTP path

**Files:**
- Modify: `scripts/Specimen/volumetric_specimen.gd`

**Why:** `VolumeSpecimen` today only loads from local files. Add a `data_url` export + `HTTPRequest` flow that parallels `MeshSpecimen`'s implementation.

- [ ] **Step 1: Read the current `volumetric_specimen.gd` to confirm field names and `_ready` / `_enter_tree` structure.** In particular: `volume_layered` is `get_node("%VolumeLayeredShader")`; the texture is installed via `_update_texture` RPC; UI layers `%FileDialogLayer`, `%LoadingLayer`, `%SettingsLayer` exist.

- [ ] **Step 2: Modify `scripts/Specimen/volumetric_specimen.gd`.**

Add these fields near the top of the class (below existing vars):

```gdscript
## URL to fetch volume data over HTTP (e.g. ascribe-link /api/specimens/{id}/data).
## Set before adding to tree. Every peer downloads independently.
@export var data_url: String = ""

var _data_http_request: HTTPRequest = null
```

Modify `_ready()` to fire the HTTP load when `data_url` is set. Replace the current `_ready` function with:

```gdscript
func _ready():
	volume_layered = get_node("%VolumeLayeredShader")
	var mesh_inst = volume_layered.get_child(0, true)
	mat = mesh_inst.get_surface_override_material(0)

	if ui_instance:
		for slider_name in ['gamma', 'opacity', 'color_scalar', 'max_steps', 'step_size', 'zoom']:
			var slider = ui_instance.get_node("%" + slider_name + "Slider")
			slider.value_changed.connect(_update_shader.bind(slider_name))
			slider.value = volume_layered[slider_name]
		ui_instance.get_node("%GradientItemList").colormap_selected.connect(_update_shader_colormap)
		ui_instance.get_node("%FileDialog").file_selected.connect(_on_file_dialog_file_selected)

		if volume_layered.texture:
			ui_instance.get_node("%FileDialogLayer").hide()
			ui_instance.get_node("%SettingsLayer").show()
			_enable_pickables()

	if not data_url.is_empty():
		_load_from_data_url()
```

Add the `_load_from_data_url` and `_on_data_url_completed` methods:

```gdscript
func _load_from_data_url() -> void:
	if ui_instance:
		ui_instance.get_node("%FileDialogLayer").hide()
		ui_instance.get_node("%LoadingLayer").show()
		var progress_bar = ui_instance.get_node_or_null("%ProgressBar")
		if progress_bar:
			progress_bar.value = 0.0

	_data_http_request = HTTPRequest.new()
	_data_http_request.request_completed.connect(_on_data_url_completed)
	add_child(_data_http_request)

	var err = _data_http_request.request(data_url)
	if err != OK:
		push_error("VolumeSpecimen: Failed to start data request: %s" % error_string(err))
		if ui_instance:
			ui_instance.get_node("%LoadingLayer").hide()


func _on_data_url_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _data_http_request:
		_data_http_request.queue_free()
		_data_http_request = null

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("VolumeSpecimen: Data request failed: result=%d, code=%d" % [result, response_code])
		if ui_instance:
			ui_instance.get_node("%LoadingLayer").hide()
		return

	var content_type := _get_content_type(headers)
	if content_type != BinaryEnvelope.MEDIA_TYPE:
		push_error("VolumeSpecimen: unexpected content-type %s (expected %s)" % [content_type, BinaryEnvelope.MEDIA_TYPE])
		if ui_instance:
			ui_instance.get_node("%LoadingLayer").hide()
		return

	var parsed := BinaryEnvelope.parse(body)
	if parsed.has("error"):
		push_error("VolumeSpecimen: envelope parse failed: %s" % parsed["error"])
		if ui_instance:
			ui_instance.get_node("%LoadingLayer").hide()
		return

	var preamble: Dictionary = parsed["preamble"]
	if preamble.get("type", "") != "volume":
		push_error("VolumeSpecimen: expected envelope type 'volume', got %s" % preamble.get("type", "<none>"))
		if ui_instance:
			ui_instance.get_node("%LoadingLayer").hide()
		return

	var data := VolumetricData.new()
	if not data.set_from_bytes(preamble, body, parsed["offset"]):
		push_error("VolumeSpecimen: VolumetricData.set_from_bytes failed")
		if ui_instance:
			ui_instance.get_node("%LoadingLayer").hide()
		return

	var texture := data.get_data()
	if texture:
		_update_texture.rpc(texture)


func _get_content_type(headers: PackedStringArray) -> String:
	for header in headers:
		var lower = header.to_lower()
		if lower.begins_with("content-type:"):
			var value = header.substr(13).strip_edges()
			var semicolon = value.find(";")
			if semicolon != -1:
				value = value.substr(0, semicolon).strip_edges()
			return value.to_lower()
	return ""
```

- [ ] **Step 3: Quick editor check.**

Back in Godot, re-open the project. Confirm `volumetric_specimen.gd` parses (no errors in the Debug → Errors panel).

- [ ] **Step 4: Commit.**

```bash
git add scripts/Specimen/volumetric_specimen.gd
git commit -m "VolumeSpecimen: add data_url HTTP fetch with envelope parsing"
```

---

## Task 6: `SceneManager._fetch_and_load_result` type dispatch

**Files:**
- Modify: `scripts/singletons/main.gd:216-242`

**Why:** Currently `_fetch_and_load_result` hardcodes `res://specimens/mesh_specimen.tscn`. Dynamic volumes need to instantiate `res://specimens/volume_specimen.tscn` instead.

- [ ] **Step 1: Open `scripts/singletons/main.gd` and locate `_fetch_and_load_result`.**

- [ ] **Step 2: Modify the function.**

Replace its body with:

```gdscript
func _fetch_and_load_result(specimen_id: String, function_name: String, room_id: String) -> void:
	# Hand the GET /data URL (with params + room_id) to the right specimen so its
	# own LoadingLayer + ProgressBar show during the download. Every peer hits
	# the same RoomResultCache key independently, so no recomputation.
	var metadata := await _fetch_metadata_for_active(specimen_id)

	var params_json := JSON.stringify(_active_params)
	var query := "params=%s&room_id=%s" % [params_json.uri_encode(), room_id.uri_encode()]
	var data_url := "%s/api/specimens/%s/data?%s" % [Config.ascribe_link_url, specimen_id, query]

	_reset_world()

	var scene_path := _scene_path_for_type(metadata.get("type", "mesh"))
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("SceneManager: Failed to load %s" % scene_path)
		return
	var specimen: Specimen = packed.instantiate()
	specimen.data_url = data_url
	if "display_name" in specimen:
		specimen.display_name = metadata.get("display_name", specimen.display_name)

	current_3d_scene = specimen
	specimens_root.add_child(specimen)
	_position_specimen(specimen)
	specimen.show()
	hide_mainmenu()


static func _scene_path_for_type(specimen_type: String) -> String:
	match specimen_type:
		"volume":
			return "res://specimens/volume_specimen.tscn"
		_:
			return "res://specimens/mesh_specimen.tscn"
```

- [ ] **Step 3: Editor check.**

Re-open the project in Godot. No parse errors.

- [ ] **Step 4: Commit.**

```bash
git add scripts/singletons/main.gd
git commit -m "SceneManager: dispatch dynamic specimen scene by type"
```

---

## Task 7: End-to-end manual validation

**Prerequisite:** Server-side PR (from `2026-04-24-volume-transmission-server.md`) is merged into the server's default branch, OR a local build of that branch is running.

**Files:** n/a (manual runs).

- [ ] **Step 1: Start ascribe-link from its volume-transmission worktree.**

```bash
cd ~/PycharmProjects/ascribe-link/worktrees/volume-transmission
python -m ascribe_link
```

Verify startup logs show `generate_gaussian_volume` registered.

- [ ] **Step 2: Launch vr-start in Godot (flat mode, no headset).**

From the `volume-transmission` worktree, press F5. Confirm the main menu loads and lists at least:
- Locally-bundled specimens from `specimens/` (brain mesh, etc.)
- Remote specimens from the server — verify `Parametric Gaussian Volume ⚙️` appears

- [ ] **Step 3: Golden path — parametric volume.**

- Click "Parametric Gaussian Volume ⚙️" in the menu.
- Leave parameters at defaults, click Submit.
- Expected: loading layer shows, then the volume renders in the `VolumeLayeredShader`. The blob should look like a Gaussian (bright center, dark edges).
- If it renders: pass.

- [ ] **Step 4: Regression — large mesh no longer size-limited.**

- Click "Parametric Sphere ⚙️".
- Increase resolution to max (128).
- Submit.
- Expected: loads faster than before and does not fail with JSON-size errors. The sphere renders.

- [ ] **Step 5: Static `.npy` volume.**

- On the server side, drop a test specimen into the specimens directory used by `python -m ascribe_link`. From a Python shell:

```python
from pathlib import Path
import json
import numpy as np

dest = Path("~/PycharmProjects/ascribe-link/specimens/static_gaussian").expanduser()
dest.mkdir(parents=True, exist_ok=True)
x = np.linspace(-0.5, 0.5, 64, dtype=np.float32)
xx, yy, zz = np.meshgrid(x, x, x, indexing="ij")
np.save(dest / "data.npy", np.exp(-(xx**2 + yy**2 + zz**2) / 0.1).astype(np.float32))
(dest / "metadata.json").write_text(json.dumps({
    "id": "static_gaussian",
    "display_name": "Static Gaussian",
    "type": "volume",
    "data_file": "data.npy",
    "tags": ["static", "volume"],
}))
```

- Restart ascribe-link. Verify `Static Gaussian` appears in the XR menu (no ⚙️ since it's not dynamic).
- Click it. Expected: renders as a Gaussian blob identical to the parametric version.

- [ ] **Step 6: AI Generate with a volume prompt.**

- Click "AI Generate ⚙️".
- Prompt: `generate a 3D Gaussian blob at 32 voxels per side`.
- Submit.
- Expected: loads and renders as a volume (agent produces a numpy 3D array → volume envelope → XR client volume specimen).
- If the agent produces a mesh instead, that's also correct — verify it renders as a mesh. Log the prompt that reliably produces a volume in the worktree notes.

- [ ] **Step 7: Record results.**

In the worktree, add a file `docs/superpowers/VOLUME_TRANSMISSION_E2E.md` with one line per step confirming pass/fail and any observations (e.g., load time for the large sphere).

```bash
git add docs/superpowers/VOLUME_TRANSMISSION_E2E.md
git commit -m "Record volume transmission E2E validation results"
```

---

## Task 8: Open a PR for client-side work

**Files:** n/a

- [ ] **Step 1: Push the branch.**

```bash
git push -u origin volume-transmission
```

- [ ] **Step 2: Open the PR.**

```bash
gh pr create --title "Volumetric data transmission (client side)" --body "$(cat <<'EOF'
## Summary
- Adds `BinaryEnvelope` parser for ascribe-link's new wire format
- `MeshData` and `VolumetricData` each gain `set_from_bytes`
- `MeshSpecimen` dispatches on `application/x-ascribe-envelope-v1`
- `VolumeSpecimen` gains a `data_url` HTTP-fetch path parallel to `MeshSpecimen`
- `SceneManager._fetch_and_load_result` now branches on specimen type

Depends on: ascribe-link `volume-transmission` PR (must be merged first).

Spec: `docs/superpowers/specs/2026-04-24-volumetric-transmission-design.md`.

## Test plan
- [ ] gdUnit suite (`tests/`) passes — envelope, mesh bytes, volumetric bytes
- [ ] Parametric Gaussian Volume renders end-to-end
- [ ] Large parametric sphere no longer hits JSON size limit
- [ ] Static `.npy` volume renders
- [ ] AI Generate can produce a volume
EOF
)"
```

- [ ] **Step 3: Link the PRs.**

Add a comment on each PR referencing the other so reviewers can see the pair.

---

## Self-Review Checklist (run before handoff)

- [ ] gdUnit tests under `tests/` all pass.
- [ ] `BinaryEnvelope.MEDIA_TYPE == "application/x-ascribe-envelope-v1"`.
- [ ] `MeshData.set_from_bytes` returns `bool`, emits `data_ready` on success.
- [ ] `VolumetricData.set_from_bytes` returns `bool`, emits `data_ready` on success.
- [ ] `MeshSpecimen._on_data_url_completed` has three branches (envelope → JSON → raw file) and the envelope branch is taken first.
- [ ] `VolumeSpecimen` has `@export var data_url: String = ""` and its own `_on_data_url_completed`.
- [ ] `SceneManager._fetch_and_load_result` branches on `metadata.type`, defaulting to mesh for unknowns.
- [ ] Static server-backed path (`mainmenuflat._load_remote_specimen`) works for static volumes without any change — confirm by running Task 7 Step 5.
