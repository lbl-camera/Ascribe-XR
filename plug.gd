extends "res://addons/gd-plug/plug.gd"

func _plugging():
	# plug("imjp94/gd-YAFSM") # By default, gd-plug will only install anything from "addons/" directory
	# plug("imjp94/gd-YAFSM", {"include": ["addons/"]})

	# dependencies
	plug("GodotVR/godot-xr-tools")
	plug("Cafezinhu/godot-vr-simulator")
	plug("goatchurchprime/godot-mqtt")
	plug("goatchurchprime/godot_multiplayer_networking_workbench", {"include": ["addons/player-networking"]})
	plug("Godot-Dojo/Godot-XR-AH", {"include": ["addons/xr-autohandtracker"]})
	# plug("blackears/godot_volume_layers") # this one has some edits that need to be extracted
	# plug("TokisanGames/Terrain3D", {"install_root": "addons/terrain_3d", "include": ["project/addons/terrain_3d/"]}) # needs .zip support in plug
	# plug("GodotVR/godot_openxr_vendors")  # needs .zip support
	#plug("goatchurchprime/two-voip-godot-4")
	#plug("godotengine/webrtc-native")

	# dev tools
	#plug("Maran23/script-ide")

	# large binary addons unpacked and put into a spare repo for the moment
	var stashedaddons = ["addons/twovoip", "addons/webrtc"]
	plug("goatchurchprime/paraviewgodot", {"branch": "stashedaddons", "include": stashedaddons})
