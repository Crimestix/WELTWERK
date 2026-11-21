extends Node3D
## Hauptszene: verbindet Gelände, Kamera und Oberfläche.
##
## Aufruf mit `-- --screenshot=<Pfad>` speichert nach dem Laden ein Bild und beendet das
## Programm (zum Prüfen des Aussehens ohne Klicken).

@onready var terrain: Terrain = $Terrain
@onready var help = $Interface/ControlsHelp


func _ready() -> void:
	help.show_terrain_origin(terrain.field)
	terrain.generated.connect(help.show_terrain_origin)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			# --view=x,z,abstand – Blick für Prüfbilder setzen.
			var v := arg.trim_prefix("--view=").split_floats(",")
			if v.size() == 3:
				$CameraRig.jump_to(Vector3(v[0], 0.0, v[1]), v[2])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_save_screenshot(arg.trim_prefix("--screenshot="))


func _save_screenshot(path: String) -> void:
	for i in 45:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("Bild gespeichert: ", path) if error == OK else printerr("Bild nicht gespeichert: ", error)
	get_tree().quit()
