# Refactoring Item #9: Create Data Source Abstraction

## Overview

This document provides detailed guidance for implementing a clean data source abstraction layer that separates **data types**, **data sources**, and **loading strategies** into composable components.

---

## Current State Analysis

### Data Types
| Type | Current Implementation | Format Support |
|------|------------------------|----------------|
| **Mesh** | `mesh_specimen.gd` | STL, FBX, OBJ |
| **Volumetric** | `volumetric_specimen.gd` | Binary (.bin), ZIP archives |
| **Topographical** | Not implemented | (Future) |

### Data Sources
| Source | Current Implementation | Notes |
|--------|------------------------|-------|
| **Embedded** | Scenes with pre-loaded assets | No abstraction, hardcoded in scenes |
| **File** | FileAccess, ResourceLoader | Mixed sync/async approaches |
| **Network (MQTT)** | `dynamic_mesh_specimen.gd` | JSON messages via MQTT topics |
| **Network (RPC)** | `mesh_specimen.gd:send_mesh()` | Chunked 20KB packets |
| **Repository** | Not implemented | (Future) |

### Loading Strategies
| Strategy | Current Implementation | Location |
|----------|------------------------|----------|
| **Synchronous** | STL/FBX loading | `mesh_specimen.gd:123-126` |
| **Threaded** | OBJ via ResourceLoader | `mesh_specimen.gd:66-89` |
| **RPC-triggered** | Chunked mesh sync | `mesh_specimen.gd:254-298` |
| **Lazy/Deferred** | ZIP volume loading | `zipped_image_archive_rf_3d.gd:31-44` |

---

## Proposed Architecture

### Design Principles

1. **Separation of Concerns**: Data type, source, and loading strategy are independent axes
2. **Composition over Inheritance**: Use interfaces and composition rather than deep inheritance
3. **Single Responsibility**: Each class does one thing well
4. **Open/Closed**: Easy to add new formats, sources, or strategies without modifying existing code

### Directory Structure

```
scripts/
├── data/
│   ├── types/
│   │   ├── data_type.gd           # Base interface
│   │   ├── mesh_data.gd           # Mesh-specific data container
│   │   ├── volumetric_data.gd     # Volume-specific data container
│   │   └── topographical_data.gd  # Topo-specific data container
│   │
│   ├── sources/
│   │   ├── data_source.gd         # Base interface
│   │   ├── file_source.gd         # Local file loading
│   │   ├── embedded_source.gd     # Pre-loaded scene resources
│   │   ├── mqtt_source.gd         # MQTT network messages
│   │   ├── rpc_source.gd          # RPC chunk receiving
│   │   └── repository_source.gd   # Future: centralized repository
│   │
│   ├── loaders/
│   │   ├── loader_strategy.gd     # Base interface
│   │   ├── sync_loader.gd         # Blocking foreground load
│   │   ├── threaded_loader.gd     # Background thread loading
│   │   └── chunked_loader.gd      # Progressive chunk loading
│   │
│   └── data_pipeline.gd           # Orchestrates source → loader → type
│
├── specimens/
│   ├── specimen.gd                # Base specimen (existing)
│   ├── mesh_specimen.gd           # Simplified, uses data pipeline
│   ├── volumetric_specimen.gd     # Simplified, uses data pipeline
│   └── topographical_specimen.gd  # New
```

---

## Interface Definitions

### 1. DataType (Data Container)

```gdscript
# scripts/data/types/data_type.gd
class_name DataType
extends RefCounted

## Emitted when data is ready for use
signal data_ready

## Emitted on load progress (0.0 to 1.0)
signal progress_updated(progress: float)

## Emitted on error
signal load_failed(error: String)

## Returns true if data is loaded and valid
func is_valid() -> bool:
    return false

## Returns the data in a format suitable for the specimen
func get_data() -> Variant:
    return null

## Clears loaded data and frees resources
func clear() -> void:
    pass
```

### 2. MeshData Implementation

```gdscript
# scripts/data/types/mesh_data.gd
class_name MeshData
extends DataType

var vertices: PackedVector3Array
var indices: PackedInt32Array
var normals: PackedVector3Array
var _mesh: ArrayMesh

func is_valid() -> bool:
    return vertices.size() > 0

func get_data() -> ArrayMesh:
    if _mesh == null:
        _mesh = _build_mesh()
    return _mesh

func set_from_arrays(verts: PackedVector3Array, idx: PackedInt32Array, norms: PackedVector3Array) -> void:
    vertices = verts
    indices = idx
    normals = norms
    _mesh = null  # Invalidate cached mesh
    data_ready.emit()

## For network transmission - flat arrays are more efficient
func set_from_flat_arrays(verts: PackedFloat32Array, idx: PackedInt32Array, norms: PackedFloat32Array) -> void:
    vertices = _unflatten_vector3(verts)
    normals = _unflatten_vector3(norms)
    indices = idx
    _mesh = null
    data_ready.emit()

func get_flat_vertices() -> PackedFloat32Array:
    return _flatten_vector3(vertices)

func get_flat_normals() -> PackedFloat32Array:
    return _flatten_vector3(normals)

func _build_mesh() -> ArrayMesh:
    # Extracted from mesh_specimen.gd:build_mesh()
    pass

func _flatten_vector3(arr: PackedVector3Array) -> PackedFloat32Array:
    var flat := PackedFloat32Array()
    flat.resize(arr.size() * 3)
    for i in arr.size():
        flat[i * 3] = arr[i].x
        flat[i * 3 + 1] = arr[i].y
        flat[i * 3 + 2] = arr[i].z
    return flat

func _unflatten_vector3(flat: PackedFloat32Array) -> PackedVector3Array:
    var arr := PackedVector3Array()
    arr.resize(flat.size() / 3)
    for i in arr.size():
        arr[i] = Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])
    return arr
```

### 3. VolumetricData Implementation

```gdscript
# scripts/data/types/volumetric_data.gd
class_name VolumetricData
extends DataType

var _texture: Texture3D
var _dimensions: Vector3i

func is_valid() -> bool:
    return _texture != null

func get_data() -> Texture3D:
    return _texture

func get_dimensions() -> Vector3i:
    return _dimensions

func set_texture(tex: Texture3D, dims: Vector3i) -> void:
    _texture = tex
    _dimensions = dims
    data_ready.emit()

func set_from_images(images: Array[Image], dims: Vector3i) -> void:
    var tex := ImageTexture3D.new()
    tex.create(dims.x, dims.y, dims.z, images[0].get_format(), false, images)
    _texture = tex
    _dimensions = dims
    data_ready.emit()
```

---

### 4. DataSource (Where Data Comes From)

```gdscript
# scripts/data/sources/data_source.gd
class_name DataSource
extends RefCounted

## Emitted when raw data is available
signal data_available(raw_data: Variant)

## Emitted on progress (0.0 to 1.0)
signal progress_updated(progress: float)

## Emitted on error
signal source_error(error: String)

## Returns true if source is ready to provide data
func is_available() -> bool:
    return false

## Begins fetching data from source (may be async)
func fetch() -> void:
    pass

## Cancels an in-progress fetch
func cancel() -> void:
    pass
```

### 5. FileSource Implementation

```gdscript
# scripts/data/sources/file_source.gd
class_name FileSource
extends DataSource

var file_path: String
var _file_type: String  # "stl", "fbx", "obj", "bin", "zip"

func _init(path: String) -> void:
    file_path = path
    _file_type = path.get_extension().to_lower()

func is_available() -> bool:
    return FileAccess.file_exists(file_path)

func get_file_type() -> String:
    return _file_type

func fetch() -> void:
    if not is_available():
        source_error.emit("File not found: %s" % file_path)
        return

    # Return raw file reference - let loader handle format parsing
    data_available.emit(file_path)
```

### 6. MQTTSource Implementation

```gdscript
# scripts/data/sources/mqtt_source.gd
class_name MQTTSource
extends DataSource

var _mqtt_client: Node
var _request_topic: String
var _response_topic: String
var _request_payload: Dictionary
var _is_waiting: bool = false

func _init(mqtt: Node, request_topic: String, response_topic: String) -> void:
    _mqtt_client = mqtt
    _request_topic = request_topic
    _response_topic = response_topic
    _mqtt_client.received_message.connect(_on_message)

func set_request(payload: Dictionary) -> void:
    _request_payload = payload

func is_available() -> bool:
    return _mqtt_client != null and _mqtt_client.is_connected_to_broker()

func fetch() -> void:
    if not is_available():
        source_error.emit("MQTT not connected")
        return

    _is_waiting = true
    var json := JSON.stringify(_request_payload)
    _mqtt_client.publish(_request_topic, json.to_utf8_buffer())

func cancel() -> void:
    _is_waiting = false

func _on_message(topic: String, payload: PackedByteArray) -> void:
    if not _is_waiting or topic != _response_topic:
        return

    _is_waiting = false
    var json := JSON.parse_string(payload.get_string_from_utf8())
    if json == null:
        source_error.emit("Invalid JSON response")
        return

    data_available.emit(json)
```

### 7. RPCChunkSource (for receiving networked data)

```gdscript
# scripts/data/sources/rpc_chunk_source.gd
class_name RPCChunkSource
extends DataSource

## Chunk size in elements (matches mesh_specimen.gd CHUNK_SIZE)
const CHUNK_SIZE := 20000

var _accumulated_data: Dictionary = {}
var _expected_chunks: Dictionary = {}

## Call this from RPC receiver
func receive_chunk(data_type: String, chunk: Variant, chunk_index: int, total_chunks: int) -> void:
    if not _accumulated_data.has(data_type):
        _accumulated_data[data_type] = []
        _expected_chunks[data_type] = total_chunks

    # Ensure array is large enough
    while _accumulated_data[data_type].size() <= chunk_index:
        _accumulated_data[data_type].append(null)

    _accumulated_data[data_type][chunk_index] = chunk

    var received := _count_received(data_type)
    progress_updated.emit(float(received) / total_chunks)

    if _is_complete():
        _finalize()

func _count_received(data_type: String) -> int:
    var count := 0
    for chunk in _accumulated_data[data_type]:
        if chunk != null:
            count += 1
    return count

func _is_complete() -> bool:
    for data_type in _expected_chunks:
        if _count_received(data_type) < _expected_chunks[data_type]:
            return false
    return true

func _finalize() -> void:
    var result := {}
    for data_type in _accumulated_data:
        result[data_type] = _merge_chunks(_accumulated_data[data_type])
    data_available.emit(result)

func _merge_chunks(chunks: Array) -> Variant:
    # Merge PackedFloat32Array or PackedInt32Array chunks
    if chunks.is_empty():
        return null

    var merged = chunks[0].duplicate()
    for i in range(1, chunks.size()):
        merged.append_array(chunks[i])
    return merged
```

---

### 8. LoaderStrategy (How Data is Loaded)

```gdscript
# scripts/data/loaders/loader_strategy.gd
class_name LoaderStrategy
extends RefCounted

signal load_complete(data: DataType)
signal load_progress(progress: float)
signal load_error(error: String)

## Parse raw data from source into typed data container
## Subclasses implement format-specific parsing
func load(source_data: Variant, target_type: DataType) -> void:
    push_error("LoaderStrategy.load() must be overridden")
```

### 9. SyncLoader (Blocking)

```gdscript
# scripts/data/loaders/sync_loader.gd
class_name SyncLoader
extends LoaderStrategy

var _format_handlers: Dictionary = {}

func _init() -> void:
    # Register format handlers
    _format_handlers["stl"] = _load_stl
    _format_handlers["fbx"] = _load_fbx
    _format_handlers["bin"] = _load_bin

func register_handler(extension: String, handler: Callable) -> void:
    _format_handlers[extension] = handler

func load(source_data: Variant, target_type: DataType) -> void:
    if source_data is String:
        # File path
        var ext := source_data.get_extension().to_lower()
        if _format_handlers.has(ext):
            _format_handlers[ext].call(source_data, target_type)
        else:
            load_error.emit("Unsupported format: %s" % ext)
    elif source_data is Dictionary:
        # Already parsed data (from network)
        _load_from_dict(source_data, target_type)
    else:
        load_error.emit("Unknown source data type")

func _load_stl(path: String, target: MeshData) -> void:
    var importer := preload("res://tools/stl_importer.gd").new()
    var result := importer.import(path, false)
    if result.is_empty():
        load_error.emit("STL import failed")
        return
    target.set_from_arrays(result.verts, result.indices, result.normals)
    load_complete.emit(target)

func _load_fbx(path: String, target: MeshData) -> void:
    # Extract FBX loading from mesh_specimen.gd:98-127
    pass

func _load_bin(path: String, target: VolumetricData) -> void:
    # Extract from volumetric_specimen.gd:65-85
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        load_error.emit("Cannot open file: %s" % path)
        return

    var data := file.get_buffer(file.get_length())
    var dims := Vector3i(256, 256, 10)  # TODO: Make configurable
    var images: Array[Image] = []
    var frame_size := dims.x * dims.y

    for z in dims.z:
        var offset := z * frame_size
        var slice := data.slice(offset, offset + frame_size)
        var img := Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_L8, slice)
        images.append(img)

    target.set_from_images(images, dims)
    load_complete.emit(target)

func _load_from_dict(data: Dictionary, target: DataType) -> void:
    if target is MeshData:
        target.set_from_flat_arrays(
            data.get("vertices", PackedFloat32Array()),
            data.get("indices", PackedInt32Array()),
            data.get("normals", PackedFloat32Array())
        )
        load_complete.emit(target)
```

### 10. ThreadedLoader (Background)

```gdscript
# scripts/data/loaders/threaded_loader.gd
class_name ThreadedLoader
extends LoaderStrategy

var _thread: Thread
var _target_type: DataType
var _sync_loader: SyncLoader

func _init() -> void:
    _sync_loader = SyncLoader.new()
    _sync_loader.load_complete.connect(_on_sync_complete)
    _sync_loader.load_error.connect(_on_sync_error)

func load(source_data: Variant, target_type: DataType) -> void:
    _target_type = target_type

    # For OBJ files, use Godot's built-in threaded loader
    if source_data is String and source_data.get_extension().to_lower() == "obj":
        ResourceLoader.load_threaded_request(source_data)
        # Need to poll in _process - see DataPipeline
        return

    # For other formats, use our own thread
    _thread = Thread.new()
    _thread.start(_threaded_load.bind(source_data, target_type))

func _threaded_load(source_data: Variant, target_type: DataType) -> void:
    _sync_loader.load(source_data, target_type)

func _on_sync_complete(data: DataType) -> void:
    if _thread and _thread.is_started():
        _thread.wait_to_finish()
    load_complete.emit(data)

func _on_sync_error(error: String) -> void:
    if _thread and _thread.is_started():
        _thread.wait_to_finish()
    load_error.emit(error)

## Call this each frame to check ResourceLoader status
func poll_resource_loader(path: String, target: MeshData) -> bool:
    var status := ResourceLoader.load_threaded_get_status(path)
    match status:
        ResourceLoader.THREAD_LOAD_IN_PROGRESS:
            return false
        ResourceLoader.THREAD_LOAD_LOADED:
            var mesh: Mesh = ResourceLoader.load_threaded_get(path)
            # Convert Mesh to MeshData
            # Extract from mesh_specimen.gd extract_mesh_data()
            load_complete.emit(target)
            return true
        _:
            load_error.emit("Resource load failed")
            return true
```

---

### 11. DataPipeline (Orchestrator)

```gdscript
# scripts/data/data_pipeline.gd
class_name DataPipeline
extends RefCounted

signal pipeline_complete(data: DataType)
signal pipeline_progress(progress: float)
signal pipeline_error(error: String)

var _source: DataSource
var _loader: LoaderStrategy
var _target: DataType

func configure(source: DataSource, loader: LoaderStrategy, target: DataType) -> DataPipeline:
    _source = source
    _loader = loader
    _target = target

    # Wire up signals
    _source.data_available.connect(_on_source_data)
    _source.progress_updated.connect(func(p): pipeline_progress.emit(p * 0.5))
    _source.source_error.connect(func(e): pipeline_error.emit("Source: " + e))

    _loader.load_complete.connect(func(d): pipeline_complete.emit(d))
    _loader.load_progress.connect(func(p): pipeline_progress.emit(0.5 + p * 0.5))
    _loader.load_error.connect(func(e): pipeline_error.emit("Loader: " + e))

    return self

func start() -> void:
    _source.fetch()

func _on_source_data(raw_data: Variant) -> void:
    _loader.load(raw_data, _target)


## Factory methods for common pipelines

static func file_to_mesh(path: String) -> DataPipeline:
    var pipeline := DataPipeline.new()
    var ext := path.get_extension().to_lower()

    var source := FileSource.new(path)
    var loader: LoaderStrategy

    if ext == "obj":
        loader = ThreadedLoader.new()
    else:
        loader = SyncLoader.new()

    var target := MeshData.new()

    return pipeline.configure(source, loader, target)

static func file_to_volume(path: String) -> DataPipeline:
    var pipeline := DataPipeline.new()
    var source := FileSource.new(path)
    var loader := SyncLoader.new()
    var target := VolumetricData.new()
    return pipeline.configure(source, loader, target)

static func mqtt_to_mesh(mqtt: Node, specimen_name: String) -> DataPipeline:
    var pipeline := DataPipeline.new()
    var source := MQTTSource.new(mqtt, "godot/processing_requests", "python/processing_responses")
    source.set_request({"function_name": "get_specimen", "args": [specimen_name]})
    var loader := SyncLoader.new()
    var target := MeshData.new()
    return pipeline.configure(source, loader, target)
```

---

## Specimen Simplification

After implementing the data abstraction, specimens become much simpler:

```gdscript
# scripts/specimens/mesh_specimen.gd (simplified)
class_name MeshSpecimen
extends Specimen

var _data: MeshData
var _pipeline: DataPipeline

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func load_from_file(path: String) -> void:
    _pipeline = DataPipeline.file_to_mesh(path)
    _pipeline.pipeline_complete.connect(_on_data_loaded)
    _pipeline.pipeline_progress.connect(_update_progress_ui)
    _pipeline.pipeline_error.connect(_on_load_error)
    _pipeline.start()

func load_from_mqtt(mqtt: Node, specimen_name: String) -> void:
    _pipeline = DataPipeline.mqtt_to_mesh(mqtt, specimen_name)
    _pipeline.pipeline_complete.connect(_on_data_loaded)
    _pipeline.pipeline_progress.connect(_update_progress_ui)
    _pipeline.pipeline_error.connect(_on_load_error)
    _pipeline.start()

func set_data(data: MeshData) -> void:
    _data = data
    mesh_instance.mesh = data.get_data()
    _apply_material()
    _generate_collision()

func _on_data_loaded(data: DataType) -> void:
    set_data(data as MeshData)

func _update_progress_ui(progress: float) -> void:
    # Update loading bar
    pass

func _on_load_error(error: String) -> void:
    push_error("MeshSpecimen load failed: %s" % error)
```

---

## Migration Strategy

### Phase 1: Create Infrastructure (Non-Breaking)
1. Create `scripts/data/` directory structure
2. Implement base classes: `DataType`, `DataSource`, `LoaderStrategy`
3. Implement `MeshData` and `VolumetricData`
4. Write unit tests for data containers

### Phase 2: Implement Sources
1. `FileSource` - extract file loading logic
2. `MQTTSource` - extract from `dynamic_mesh_specimen.gd`
3. `RPCChunkSource` - extract from `mesh_specimen.gd`
4. `EmbeddedSource` - for pre-loaded scene resources

### Phase 3: Implement Loaders
1. `SyncLoader` with format handlers for STL, FBX, BIN
2. `ThreadedLoader` for OBJ and large files
3. `ChunkedLoader` for progressive network loading

### Phase 4: Create Pipeline
1. Implement `DataPipeline` orchestrator
2. Add factory methods for common patterns
3. Integration tests

### Phase 5: Migrate Specimens (One at a Time)
1. Update `mesh_specimen.gd` to use pipeline
2. Update `volumetric_specimen.gd` to use pipeline
3. Simplify `dynamic_mesh_specimen.gd`
4. Keep old code paths during transition (feature flag)

### Phase 6: Future Sources
1. `RepositorySource` - centralized data repository
2. `TopographicalData` - when terrain features are needed

---

## Testing Strategy

### Unit Tests
```gdscript
# tests/test_mesh_data.gd
func test_mesh_data_from_arrays():
    var data := MeshData.new()
    var verts := PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0)])
    var indices := PackedInt32Array([0, 1, 2])
    var normals := PackedVector3Array([Vector3(0,0,1), Vector3(0,0,1), Vector3(0,0,1)])

    data.set_from_arrays(verts, indices, normals)

    assert(data.is_valid())
    assert(data.vertices.size() == 3)

func test_mesh_data_flat_conversion():
    var data := MeshData.new()
    var flat_verts := PackedFloat32Array([0,0,0, 1,0,0, 0,1,0])
    var indices := PackedInt32Array([0, 1, 2])
    var flat_normals := PackedFloat32Array([0,0,1, 0,0,1, 0,0,1])

    data.set_from_flat_arrays(flat_verts, indices, flat_normals)

    assert(data.vertices[1] == Vector3(1, 0, 0))
```

### Integration Tests
```gdscript
# tests/test_pipeline.gd
func test_file_to_mesh_pipeline():
    var pipeline := DataPipeline.file_to_mesh("res://test_assets/cube.stl")
    var loaded := false
    pipeline.pipeline_complete.connect(func(d): loaded = true)
    pipeline.start()

    await get_tree().create_timer(1.0).timeout
    assert(loaded)
```

---

## Benefits of This Architecture

1. **Testability**: Each component can be tested in isolation
2. **Extensibility**: Add new formats/sources without modifying existing code
3. **Reusability**: Same `MeshData` works with any source
4. **Clarity**: Clear separation of "what", "where", and "how"
5. **Maintainability**: Smaller, focused classes instead of 546-line god classes
6. **Future-proof**: Repository source slots in naturally

---

## Pre-prepared Scenes and Embedded Data

### Problem with Embedded Data

Currently, some scenes contain data directly embedded within them (e.g., mesh resources saved inline in `.tscn` files). This approach has several drawbacks:

1. **Large scene files** - Binary data bloats `.tscn` files, making them slow to parse
2. **Version control noise** - Binary changes create unreadable diffs
3. **No data reuse** - Same data embedded in multiple scenes is duplicated
4. **Memory inefficiency** - Scene loading pulls all data into memory immediately
5. **No lazy loading** - Cannot defer data loading until actually needed

### Recommended Pattern: External Data References

Pre-prepared scenes should **reference** external data files rather than embedding data:

```
scenes/
├── specimens/
│   └── brain_scan.tscn      # Scene with EmbeddedSource pointing to data file
│
res://data/
├── specimens/
│   └── brain_scan.bin       # Actual volumetric data (external file)
```

### EmbeddedSource Implementation

```gdscript
# scripts/data/sources/embedded_source.gd
class_name EmbeddedSource
extends DataSource

## Path to the bundled data file (relative to res://)
@export var data_path: String

## Whether to load immediately or defer until fetch() is called
@export var preload_data: bool = false

var _cached_path: String

func _init(path: String = "") -> void:
    data_path = path
    _cached_path = _resolve_path(path)

func is_available() -> bool:
    return ResourceLoader.exists(_cached_path) or FileAccess.file_exists(_cached_path)

func fetch() -> void:
    if not is_available():
        source_error.emit("Embedded data not found: %s" % data_path)
        return

    # Return the resolved path - loader handles the actual parsing
    data_available.emit(_cached_path)

func _resolve_path(path: String) -> String:
    # Support both res:// and user:// paths
    if path.begins_with("res://") or path.begins_with("user://"):
        return path
    # Default to res://data/ for relative paths
    return "res://data/" + path
```

### Scene Setup Pattern

```gdscript
# In a pre-prepared specimen scene (brain_scan.tscn)
class_name BrainScanSpecimen
extends VolumetricSpecimen

## Configure in the editor - points to external file, NOT embedded data
@export var embedded_source: EmbeddedSource

func _ready() -> void:
    if embedded_source and embedded_source.data_path:
        _load_from_embedded()

func _load_from_embedded() -> void:
    var pipeline := DataPipeline.new()
    var loader := SyncLoader.new()
    var target := VolumetricData.new()

    pipeline.configure(embedded_source, loader, target)
    pipeline.pipeline_complete.connect(_on_data_loaded)
    pipeline.start()
```

### Migration: Extracting Embedded Data

For existing scenes with embedded data, use this extraction workflow:

```gdscript
# tools/extract_embedded_data.gd
## Run from editor: Tools > Extract Embedded Data
@tool
extends EditorScript

func _run() -> void:
    var scene_path := "res://scenes/specimens/old_brain_scan.tscn"
    var output_dir := "res://data/specimens/"

    var scene: PackedScene = load(scene_path)
    var instance := scene.instantiate()

    # Find MeshInstance3D nodes with inline meshes
    for child in instance.get_children():
        if child is MeshInstance3D and child.mesh:
            var mesh_name := child.name.to_snake_case()
            var output_path := output_dir + mesh_name + ".res"

            # Save mesh as separate resource
            ResourceSaver.save(child.mesh, output_path)
            print("Extracted: %s -> %s" % [child.name, output_path])

            # Update scene to use external reference
            child.mesh = load(output_path)

    # Save updated scene
    var packed := PackedScene.new()
    packed.pack(instance)
    ResourceSaver.save(packed, scene_path.replace(".tscn", "_updated.tscn"))

    instance.queue_free()
```

### Benefits of External Data References

| Aspect | Embedded Data | External Reference |
|--------|---------------|-------------------|
| Scene file size | Large (MB+) | Small (KB) |
| Load time | All at once | On-demand |
| Git diffs | Unreadable | Clean |
| Data sharing | Duplicated | Single source |
| Memory control | None | Lazy loading |
| Export flexibility | Fixed | Configurable |

### Directory Convention

```
res://
├── data/                    # All external data files
│   ├── meshes/             # .stl, .obj, .res mesh files
│   ├── volumes/            # .bin, .zip volumetric data
│   └── specimens/          # Pre-bundled specimen data
│
├── scenes/
│   └── specimens/          # Scenes reference data via EmbeddedSource
│       ├── brain_scan.tscn # @export data_path = "specimens/brain.bin"
│       └── skull.tscn      # @export data_path = "meshes/skull.stl"
```

This pattern ensures that "embedded" means "bundled with the application" rather than "inlined in the scene file", providing the convenience of pre-configured specimens with the flexibility and efficiency of external data loading.

---

## Considerations

### Performance
- Threaded loading should be used for large files
- Chunk-based network transfer preserves the current 20KB strategy
- Lazy loading pattern (from volumetric) can be applied elsewhere

### Backward Compatibility
- Existing `@export` properties on specimens should continue to work
- File dialog integration remains unchanged
- RPC methods need thin wrappers to bridge to new architecture

### Configuration
- Chunk size (20000) should move to centralized config (Item #7)
- Volume dimensions (256x256x10) should be configurable
- Format-specific settings should live with their handlers
