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
