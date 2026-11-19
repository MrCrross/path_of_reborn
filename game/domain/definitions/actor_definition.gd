class_name ActorDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var max_hp: int = 1
@export var strength: int = 1
@export var defense: int = 0
@export var mana: int = 0
@export var xp_reward: int = 0
@export var xp_thresholds: Array[int] = []
@export var strength_upgrade_amount: int = 1
@export var max_hp_upgrade_amount: int = 1
@export var behavior_id: String = ""
@export var telegraph_ticks: int = 30
@export var startup_ticks: int = 18
@export var active_ticks: int = 6
@export var recovery_ticks: int = 12
@export var vulnerability_ticks: int = 36
@export var attacks_per_cycle: int = 1
@export var attack_multiplier: float = 1.0
@export var vulnerability_multiplier: float = 2.0
@export var attack_cooldown_ticks: int = 24
@export var dodge_duration_ticks: int = 24
@export var dodge_cooldown_ticks: int = 42
