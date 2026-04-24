extends Node

@export var mesh: MeshInstance3D
@export var shader_material: Material
@export var baseline_material: Material

@export var warmup_frames := 6000
@export var sample_frames := 60000

enum Phase {
	BASELINE,
	SHADER,
	DONE
}

var phase = Phase.BASELINE
var frame_count = 0
var samples: Array[float] = []

var baseline_avg := 0.0
var shader_avg := 0.0

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("Starting shader benchmark...")
	_apply_baseline()

func _process(_delta):
	var frame_time_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	
	frame_count += 1
	
	# Skip warmup frames
	if frame_count > warmup_frames:
		samples.append(frame_time_ms)
	
	if frame_count >= warmup_frames + sample_frames:
		var avg = _average(samples)
		
		match phase:
			Phase.BASELINE:
				baseline_avg = avg
				print("Baseline avg (ms): ", baseline_avg)
				_start_shader_phase()
			
			Phase.SHADER:
				shader_avg = avg
				print("Shader avg (ms): ", shader_avg)
				_finish()
	
func _apply_baseline():
	mesh.material_override = baseline_material
	_reset()

func _start_shader_phase():
	phase = Phase.SHADER
	mesh.material_override = shader_material
	_reset()

func _finish():
	var delta = shader_avg - baseline_avg
	
	print("\n=== RESULT ===")
	print("Baseline: ", baseline_avg, " ms")
	print("Shader:   ", shader_avg, " ms")
	print("Cost:     ", delta, " ms/frame")
	print("FPS impact: ", 1000.0 / baseline_avg, " → ", 1000.0 / shader_avg)
	
	phase = Phase.DONE
	set_process(false)

func _reset():
	frame_count = 0
	samples.clear()

func _average(arr: Array[float]) -> float:
	var sum := 0.0
	for v in arr:
		sum += v
	return sum / arr.size()
