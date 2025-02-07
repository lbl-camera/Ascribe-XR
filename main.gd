extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    var heart_button: CheckButton = get_node("XRToolsPickable4/Menu/Viewport/DataMenu/VBoxContainer/GridContainer/Panel/HBoxContainer/HeartTransparencyButton")
    heart_button.toggled.connect(set_heart_transparent)
    #heart_button.toggled.emit(true)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
    pass

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action('ui_cancel'):
        #get_tree().quit()
        return
    elif event.is_action('ui_up'):
        var shader := get_node("XRToolsPickable2/VolumeLayeredShader")
        shader.gradient.gradient.set_offset(0, shader.gradient.gradient.get_offset(0)+.01)
    elif event.is_action('ui_down'):
        var shader := get_node("XRToolsPickable2/VolumeLayeredShader")
        shader.gradient.gradient.set_offset(0, shader.gradient.gradient.get_offset(0)-.01)

func set_heart_transparent(transparent: bool) -> void:
    var material: StandardMaterial3D = get_node("%heart").get_node("Coração_001").get_active_material(2)
    if transparent:
        material.set_transparency(BaseMaterial3D.Transparency.TRANSPARENCY_ALPHA)
    else:
        material.set_transparency(BaseMaterial3D.Transparency.TRANSPARENCY_DISABLED)
