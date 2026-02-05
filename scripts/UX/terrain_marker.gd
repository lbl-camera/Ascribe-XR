@tool
extends Node3D

@export var label: String = "":
	set(text):
		label = text
		$Label3D.text = text
