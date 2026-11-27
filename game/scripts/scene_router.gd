class_name SceneRouter
extends RefCounted

signal screen_added(screen: Control)

const SCENES: Dictionary = {
	"title": "res://scenes/title.tscn",
	"prologue": "res://scenes/prologue.tscn",
	"world": "res://scenes/world.tscn",
	"world_map": "res://scenes/world_map.tscn",
	"trail_dialogue": "res://scenes/trail_dialogue.tscn",
	"combat": "res://scenes/combat.tscn",
	"inventory": "res://scenes/inventory.tscn",
	"checkpoint": "res://scenes/checkpoint.tscn",
	"merchant": "res://scenes/merchant.tscn",
	"shop": "res://scenes/shop.tscn",
	"guild": "res://scenes/guild.tscn",
	"guild_orders": "res://scenes/guild_orders.tscn",
	"characters": "res://scenes/characters.tscn",
	"settings": "res://scenes/settings.tscn",
}

var current_screen: Control
var _host: Control
var _session: GameSession

func configure(host: Control, session: GameSession) -> void:
	_host = host
	_session = session

func go_to(scene_id: String) -> bool:
	var open_hero: bool = scene_id == "hero_profile"
	var screen_id: String = "characters" if open_hero else scene_id
	if scene_id == "combat" and _session.checkpoints.has_pending_completion():
		screen_id = "checkpoint"
	elif scene_id == "guild_from_orders":
		screen_id = "guild"
	elif scene_id == "guild_order_detail":
		screen_id = "guild_orders"
	elif scene_id == "shop_from_order":
		screen_id = "shop"
	elif scene_id == "world_from_map":
		screen_id = "world"
	elif scene_id in ["lioren_map", "map_from_shop", "map_from_guild", "map_from_lioren"]:
		screen_id = "world_map"
	if not SCENES.has(screen_id):
		return false
	var packed: PackedScene = load(SCENES[screen_id])
	var screen: Control = packed.instantiate()
	if open_hero:
		screen.call("configure", _session, true)
	elif screen.has_method("configure"):
		screen.call("configure", _session)
	match scene_id:
		"guild_from_orders":
			screen.set("focus_orders_on_entry", true)
		"guild_order_detail":
			screen.set("initial_order_id", _session.guild_order.get("id", ""))
		"shop_from_order":
			screen.set("return_to_order", true)
		"world_from_map":
			screen.set("focus_map_on_entry", true)
		"lioren_map":
			screen.set("city_map", true)
		"map_from_lioren":
			screen.set("initial_destination", GameSession.LOCATION_LIOREN)
		"map_from_shop":
			screen.set("city_map", true)
			screen.set("initial_destination", GameSession.MAP_SHOP)
		"map_from_guild":
			screen.set("city_map", true)
			screen.set("initial_destination", GameSession.MAP_GUILD)
	if screen.has_signal("navigate_requested"):
		screen.connect("navigate_requested", go_to)
	if is_instance_valid(current_screen):
		_host.remove_child(current_screen)
		current_screen.queue_free()
	current_screen = screen
	_host.add_child(screen)
	screen_added.emit(screen)
	return true
