extends Node

## Mesh whose material will be swapped during benchmarking.
@export var mesh: MeshInstance3D

## Material containing the shader being evaluated.
@export var shader_material: Material

## Reference material used as the performance baseline.
@export var baseline_material: Material

## Number of frames ignored before sampling begins.
## This allows rendering and engine state to stabilize.
@export var warmup_frames := 6000

## Number of frames sampled during each benchmark phase.
@export var sample_frames := 60000

## Benchmark state machine.
##
## BASELINE:
##     Measures performance using the baseline material.
##
## SHADER:
##     Measures performance using the shader material.
##
## DONE:
##     Benchmark completed.
enum Phase {
	BASELINE,
	SHADER,
	DONE
}

## Current benchmark phase.
var phase = Phase.BASELINE

## Counts frames elapsed within the current phase.
var frame_count = 0

## Stores collected TIME_PROCESS samples (milliseconds).
var samples: Array[float] = []

## Average TIME_PROCESS measured during the baseline phase.
var baseline_avg := 0.0

## Average TIME_PROCESS measured during the shader phase.
var shader_avg := 0.0

## Initializes the benchmark and applies the baseline material.
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("Starting shader benchmark...")
	_apply_baseline()

## Collects TIME_PROCESS samples each frame.
##
## The benchmark proceeds as follows:
## 1. Ignore warmup frames.
## 2. Record sample_frames samples.
## 3. Compute average process time.
## 4. Switch from BASELINE to SHADER phase.
## 5. Repeat sampling.
## 6. Output results.
func _process(_delta):
	var frame_time_ms = Performance.get_monitor(
		Performance.TIME_PROCESS
	) * 1000.0

	frame_count += 1

	# Ignore warmup period.
	if frame_count > warmup_frames:
		samples.append(frame_time_ms)

	# End phase after collecting all samples.
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

## Applies the baseline material and resets benchmark counters.
func _apply_baseline():
	mesh.material_override = baseline_material
	_reset()

## Switches to the shader test phase.
##
## Applies the shader material and clears previously
## collected samples so a new measurement can begin.
func _start_shader_phase():
	phase = Phase.SHADER
	mesh.material_override = shader_material
	_reset()

## Computes and prints final benchmark results.
##
## Reported metrics:
## - Baseline average process time
## - Shader average process time
## - Difference between the two
## - Approximate FPS equivalent
func _finish():
	var delta = shader_avg - baseline_avg

	print("\n=== RESULT ===")
	print("Baseline: ", baseline_avg, " ms")
	print("Shader:   ", shader_avg, " ms")
	print("Cost:     ", delta, " ms/frame")
	print(
		"FPS impact: ",
		1000.0 / baseline_avg,
		" → ",
		1000.0 / shader_avg
	)

	phase = Phase.DONE
	set_process(false)

## Resets frame counters and clears collected samples.
##
## Called whenever a new benchmark phase begins.
func _reset():
	frame_count = 0
	samples.clear()


func _average(arr: Array[float]) -> float:
	var sum := 0.0
	for v in arr:
		sum += v

	return sum / arr.size()
