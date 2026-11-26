class_name SceneStaging
extends RefCounted

## Общий владелец геометрии постановки World и Combat: линия земли, доли X
## и размер силуэта. Переход «путь → бой» переносит визуальную постановку,
## поэтому обе сцены опираются на одни константы.

const FLOOR_Y_FRACTION := 0.62
const HERO_X_FRACTION := 0.24
const ENEMY_X_FRACTION := 0.72
## Согласованный экранный размер непрозрачного силуэта (logical px, база 180×320):
## один владелец геометрии для World и Combat — переход «путь → бой» без скачка.
## Источник измерений: source_resolution_test/qa/source_audit.json.
const HERO_SOLID_HEIGHT := 82.0
const ENEMY_SOLID_HEIGHT := 32.0


static func floor_y(height: float) -> float:
	return height * FLOOR_Y_FRACTION


static func hero_anchor(size: Vector2) -> Vector2:
	return Vector2(size.x * HERO_X_FRACTION, floor_y(size.y))


static func enemy_anchor(size: Vector2) -> Vector2:
	return Vector2(size.x * ENEMY_X_FRACTION, floor_y(size.y))


## Экранный scale, при котором непрозрачный силуэт текстуры высотой
## solid_height_px занимает target_logical высоту в logical px.
static func still_scale(solid_height_px: float, target_logical: float) -> float:
	return target_logical / maxf(1.0, solid_height_px)


static func grove_hero_anchor(size: Vector2) -> Vector2:
	return Vector2(size.x * 0.20, floor_y(size.y))


static func grove_enemy_anchor(size: Vector2, index: int, airborne: bool) -> Vector2:
	var fraction: float = 0.53 if index == 0 else 0.77
	var depth: float = 0.0 if index == 0 else 19.0
	return Vector2(size.x * fraction, floor_y(size.y) - depth - (28.0 if airborne else 0.0))


static func hollow_enemy_anchor(size: Vector2, index: int, count: int) -> Vector2:
	var floor: float = floor_y(size.y)
	if count == 1:
		return Vector2(size.x * 0.67, floor)
	match index:
		0: return Vector2(size.x * 0.48, floor + 9.0)
		1: return Vector2(size.x * 0.79, floor + 9.0)
		_: return Vector2(size.x * 0.67, floor - 52.0)
