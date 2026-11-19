class_name SceneRouter
extends RefCounted

signal screen_added(screen: Control)

const SCENES: Dictionary = {
	"title": "res://scenes/title.tscn",
	"prologue": "res://scenes/prologue.tscn",
	"world": "res://scenes/world.tscn",
	"combat": "res://scenes/combat.tscn",
	"reward": "res://scenes/reward.tscn",
	"inventory": "res://scenes/inventory.tscn",
	"checkpoint": "res://scenes/checkpoint.tscn",
}

var current_screen: Control
var _host: Control
var _session: GameSession

func configure(host: Control, session: GameSession) -> void:
	_host = host
	_session = session

func go_to(scene_id: String) -> bool:
	if not SCENES.has(scene_id):
		return false
	var packed: PackedScene = load(SCENES[scene_id])
	var screen: Control = packed.instantiate()
	if screen.has_method("configure"):
		screen.call("configure", _session)
	if screen.has_signal("navigate_requested"):
		screen.connect("navigate_requested", go_to)
	if is_instance_valid(current_screen):
		_host.remove_child(current_screen)
		current_screen.queue_free()
	current_screen = screen
	_host.add_child(screen)
	screen_added.emit(screen)
	return true
