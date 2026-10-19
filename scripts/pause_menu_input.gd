extends Node
## Keyboard shortcuts hosted by the always-processing pause menu.

var game: Node = null

func _input(event: InputEvent) -> void:
	if game == null or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			if not bool(game.get("_pause_menu_open")):
				return
			_mark_input_handled()
			if game.get("_settings_layer") != null and is_instance_valid(game.get("_settings_layer")):
				game.call("_close_settings_menu")
			else:
				game.call("_set_pause_menu_open", false)
		KEY_F5:
			if not bool(game.get("_pause_menu_open")):
				return
			_mark_input_handled()
			game.call("_pause_save")
		KEY_F9:
			if not bool(game.get("_pause_menu_open")):
				return
			_mark_input_handled()
			game.call("_continue_saved_match")

func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
