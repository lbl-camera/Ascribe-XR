extends Control

var story: PackedStringArray:
	set(value):
		story = value
		page = 0

		self.visible = len(story)

var page: int = 0:
	set(value):
		if value >= len(story) or value < 0 or not len(story):
			return

		page = value

		$NinePatchRect/VBoxContainer/RichTextLabel.text = story[page]


func _on_button_2_pressed() -> void:
	page += 1


func _on_button_pressed() -> void:
	page -= 1
