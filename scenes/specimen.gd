# todo: give this an icon
#@icon()
class_name Specimen
extends Node3D

enum ScaleMode {TABLE, WORLD}

@export var thumbnail: Texture2D
@export var scale_mode: ScaleMode = ScaleMode.TABLE
