# todo: give this an icon
#@icon()
class_name Specimen
extends Node3D

enum ScaleMode {TABLE, WORLD}

@export var thumbnail: Texture2D
@export var scale_mode: ScaleMode = ScaleMode.TABLE
@export var ui: PackedScene 
var ui_instance: Control

func _enter_tree() -> void:
    ui_instance = $/root/Main/SpecimenUIViewport.get_scene_instance()
