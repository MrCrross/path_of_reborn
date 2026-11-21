extends Control

signal navigate_requested(destination: String)

## Компактная мобильная RPG: сцена и катсцена занимают центральный объём,
## текст живёт в одной защищённой нижней панели. Служебные данные (shot ID,
## cue N/44, ticks) показываются только при явном флаге --debug-ui.

const MAX_TEXT_LINES := 3
const SWIPE_DISTANCE := 24.0
const SKIP_FRAME_INSET := 3.0

var session: GameSession
var runner: DialogueRunner

@onready var background: ColorRect = %Background
@onready var shot_frame: TextureRect = %ShotFrame
@onready var signal_prop: TextureRect = %SignalProp
@onready var action_sprite: AnimatedSprite2D = %ActionSprite
@onready var full_clip: AnimatedSprite2D = %FullClip
@onready var hotspot_marker: Panel = %HotspotMarker
@onready var flash: TextureRect = %Flash
@onready var plan_caption: Label = %PlanCaption
@onready var dialogue_panel: PanelContainer = %DialoguePanel
@onready var speaker_name: Label = %SpeakerName
@onready var speaker_tag: Label = %SpeakerTag
@onready var speaker_accent: ColorRect = %Accent
@onready var story_text: Label = %StoryText
@onready var hint_text: Label = %HintText
@onready var page_cue: Label = %PageCue
@onready var hold_area: PanelContainer = %HoldArea
@onready var hold_label: Label = %HoldLabel
@onready var hold_progress_bar: ProgressBar = %HoldProgressBar
@onready var skip_button: Button = %SkipButton
@onready var debug_panel: VBoxContainer = %DebugPanel
@onready var debug_text: Label = %DebugText

var _yui_wait: SpriteFrames
var _yui_step: SpriteFrames
var _hero_push: SpriteFrames
var _mitsuki_clips: Dictionary = {}
var _flash_tween: Tween
var _swipe_accum: float = 0.0
var _art_signature: String = ""
var _measured_width: float = -1.0
var _skipping: bool = false
var _hold_pointer: Dictionary = {}
var _hold_style := AppTheme.flat(Color("1c2522"), AppTheme.COLOR_ACCENT, 1, 0)
var _hold_pulse: Tween
## Последний план, под который собран стиль панели (повторно не пересобираем).
var _style_shot: String = "__init__"

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	# История линейна: Back не пропускает и не прерывает пролог.
	return false

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	# SafeArea — MarginContainer: прямым детям он навязывает полный rect, из-за
	# чего панель перекрывала всю сцену. Сценические якоря держит отдельный
	# полноэкранный оверлей внутри safe area.
	var overlay := Control.new()
	overlay.name = "SafeOverlay"
	dialogue_panel.get_parent().add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node: Control in [plan_caption, skip_button, dialogue_panel]:
		node.reparent(overlay)
	skip_button.text = ""
	skip_button.icon = ArtMap.texture(ArtMap.UI["skip_cutscene"])
	hold_area.add_theme_stylebox_override("panel", _hold_style)
	var hotspot_box := AppTheme.flat(Color(0.85, 0.71, 0.36, 0.14), AppTheme.COLOR_ACCENT, 1, 3)
	hotspot_marker.add_theme_stylebox_override("panel", hotspot_box)
	_yui_wait = ArtMap.sprite_frames(ArtMap.YUI["wait"], 2.0)
	_yui_step = ArtMap.sprite_frames(ArtMap.YUI["step"], 5.0)
	_hero_push = ArtMap.sprite_frames(ArtMap.HERO_MODERN["push"], 8.0)
	for clip_name: String in ArtMap.MITSUKI_FULL:
		_mitsuki_clips[clip_name] = ArtMap.sprite_frames(ArtMap.MITSUKI_FULL[clip_name], 2.5)
	signal_prop.texture = ArtMap.texture(ArtMap.PROPS["pedestrian_signal"])
	debug_panel.visible = DebugFlags.ui_enabled
	plan_caption.visible = DebugFlags.ui_enabled
	dialogue_panel.gui_input.connect(_gui_input)
	story_text.resized.connect(_measure_page_policy)
	%HotspotLabel.text = ""
	%HotspotLabel.add_child(_look_icon())
	runner = DialogueRunner.new()
	runner.configure(session)
	runner.first_pass_only = true
	runner.changed.connect(_refresh)
	runner.transition_started.connect(_on_transition_started)
	runner.command_requested.connect(_on_command_requested)
	runner.cue_completed.connect(_on_cue_completed)
	runner.finished.connect(_on_finished)
	if not runner.load_file("res://data/narrative/prologue.json") or not runner.start():
		story_text.text = "Не удалось загрузить данные пролога."
		return
	_refresh()
	call_deferred("_measure_page_policy")
	if not get_viewport().size_changed.is_connected(_measure_page_policy):
		get_viewport().size_changed.connect(_measure_page_policy)

## Pointer-ввод идёт через _gui_input корня: STOP-контролы в Godot 4 потребляют
## pointer-события, не давая им дойти до _unhandled_input. Корень покрывает сцену;
## панель и hotspot пикуются раньше и обрабатывают своё сами. Touch обрабатывается
## как touch, эмулированная мышь от touch игнорируется (одно касание = одно действие).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointer_pressed()
		else:
			_pointer_released()
		accept_event()
	elif event is InputEventScreenDrag:
		_pointer_dragged(event.relative)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed:
			_pointer_pressed()
		else:
			_pointer_released()
		accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_pointer_dragged(event.relative)
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	# Space (primary) — desktop-канал для продолжения/удержания.
	if event.is_action_pressed("primary"):
		get_viewport().set_input_as_handled()
		_primary_pressed()
	elif event.is_action_released("primary"):
		get_viewport().set_input_as_handled()
		if runner != null:
			runner.release_hold()

func _physics_process(_delta: float) -> void:
	if runner != null:
		runner.advance_ticks(1)

func _pointer_pressed() -> void:
	if runner == null or runner.is_finished:
		return
	_swipe_accum = 0.0
	match runner.current_kind():
		"line", "title":
			runner.tap()
		_:
			# Для жестов используются hotspot и область удержания.
			pass

func _pointer_released() -> void:
	if runner == null or runner.is_finished:
		return
	if runner.current_kind() == "hold":
		# Раннее отпускание отменяет удержание; после завершения шага отпускание
		# ничего не продвигает (holding уже сброшен в runner).
		runner.release_hold()

func _pointer_dragged(relative: Vector2) -> void:
	if runner == null or runner.is_finished or runner.current_kind() != "look":
		return
	_swipe_accum += relative.length()
	if _swipe_accum >= SWIPE_DISTANCE:
		runner.look()

func _primary_pressed() -> void:
	if runner == null or runner.is_finished:
		return
	match runner.current_kind():
		"line", "title":
			runner.tap()
		"hold":
			runner.begin_hold()

func _on_hotspot_gui_input(event: InputEvent) -> void:
	if runner == null or runner.is_finished or runner.current_kind() != "look":
		return
	var pressed: bool = event is InputEventScreenTouch and event.pressed
	pressed = pressed or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION)
	if pressed:
		hotspot_marker.accept_event()
		runner.look()

func _on_hold_area_gui_input(event: InputEvent) -> void:
	if runner == null or runner.is_finished or runner.current_kind() != "hold":
		return
	if event is InputEventScreenTouch:
		hold_area.accept_event()
		if event.pressed:
			if not _hold_pointer.is_empty():
				return
			_hold_pointer = {"kind": "touch", "index": event.index, "device": event.device}
			runner.begin_hold()
		elif not _hold_pointer.is_empty() and _hold_pointer.get("kind") == "touch" and _hold_pointer.get("index") == event.index and _hold_pointer.get("device") == event.device:
			_hold_pointer = {}
			runner.release_hold()
		if event.canceled:
			_hold_pointer = {}
			runner.release_hold()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		hold_area.accept_event()
		if event.pressed:
			if not _hold_pointer.is_empty():
				return
			_hold_pointer = {"kind": "mouse", "device": event.device}
			runner.begin_hold()
		elif _hold_pointer.get("kind", "") == "mouse" and _hold_pointer.get("device", -1) == event.device:
			_hold_pointer = {}
			runner.release_hold()
	elif event is InputEventScreenDrag and _hold_pointer.get("kind", "") == "touch" and _hold_pointer.get("index", -1) == event.index:
		hold_area.accept_event()
		if not Rect2(Vector2.ZERO, hold_area.size).has_point(event.position):
			_hold_pointer = {}
			runner.release_hold()
	elif event is InputEventMouseMotion and _hold_pointer.get("kind", "") == "mouse" and not Rect2(Vector2.ZERO, hold_area.size).has_point(event.position):
		_hold_pointer = {}
		runner.release_hold()

func _on_transition_started(cue: Dictionary) -> void:
	var colors: Dictionary = {
		"routine": Color("172131"),
		"crosswalk": Color("1c2931"),
		"alarm": Color("351d24"),
		"rescue": Color("3b3030"),
		"dark": Color("08090e"),
		"threshold": Color("211b35"),
		"seal": Color("153333"),
		"title": Color("10182a"),
	}
	background.color = colors.get(String(cue.get("shot", "")), Color("151522"))
	if String(cue.get("enter", "")) == "flash":
		_play_flash()

func _on_skip_pressed() -> void:
	if runner == null or runner.is_finished or _skipping:
		return
	_skipping = true
	_hold_pointer = {}
	# hold/transition/swipe сбрасывает runner; flash и hold-анимации — события
	# презентации, пропуск их останавливает.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if action_sprite.is_playing():
		action_sprite.stop()
	runner.skip_sequence()
	_skipping = false

func _on_command_requested(command: Dictionary) -> void:
	match String(command["type"]):
		"set_world_flag":
			session.world_flags[command["key"]] = command["value"]
		"set_npc_flag":
			session.npc_flags[command["key"]] = command["value"]
		_:
			return
	# Во время пропуска команды идут батчем: один profile_changed на границе
	# завершения sequence, а не десятки частичных записей по пути.
	if not _skipping:
		session.profile_changed.emit()

## Безопасная граница автосохранения: завершённая cue (seen, команды) —
## точка, где GameRoot может сохранить профиль. Каждый animation tick не сохраняем.
func _on_cue_completed(_cue_id: String) -> void:
	session.profile_changed.emit()

func _on_finished(destination: String) -> void:
	if _skipping:
		# Исход sequence фиксируем отдельным флагом; один profile_changed —
		# безопасная граница autosave до навигации (целый профиль на диске
		# до ухода, даже если приложение закроют на переходе).
		session.world_flags["prologue_skipped"] = true
		session.profile_changed.emit()
	session.mark_path_started()
	navigate_requested.emit(destination)

## Presentation measures actual glyphs at the available width. The runner
## receives a text-to-pages Callable and stays independent of UI classes.
func _look_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = UiIcons.texture("next")
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon.position = Vector2(-12, -12)
	icon.size = Vector2(24, 24)
	return icon

func _measure_page_policy() -> void:
	if runner == null or runner.is_finished:
		return
	var font: Font = story_text.get_theme_font("font")
	if font == null:
		return
	_fit_dialogue_panel()
	var text_width: float = story_text.size.x
	if text_width < 32.0 or is_equal_approx(text_width, _measured_width):
		return
	_measured_width = text_width
	var font_size: int = story_text.get_theme_font_size("font_size")
	runner.page_policy = func(text: String) -> Array[String]:
		return DialoguePaginator.paginate(text, font, font_size, text_width, MAX_TEXT_LINES)
	runner.repaginate_current()

func _refresh() -> void:
	if runner == null or runner.is_finished:
		return
	var kind: String = runner.current_kind()
	var cue: Dictionary = runner.current_cue()
	var shot: String = runner.current_shot()
	_apply_dialogue_style(shot)
	plan_caption.text = PrologueStaging.heading(shot)
	_update_speaker(runner.current_speaker())
	story_text.text = runner.current_text()
	# Interaction cues describe a gesture, rather than a spoken story line.
	# Keep canonical data intact; present the gesture once, next to its target.
	story_text.visible = kind not in ["look", "hold"]
	_update_page_cue()
	hint_text.text = _hint_for(kind)
	hint_text.visible = not hint_text.text.is_empty()
	hint_text.get_parent().visible = hint_text.visible or page_cue.visible
	hold_area.visible = kind == "hold"
	_refresh_hold_pulse()
	if kind != "hold":
		_hold_pointer = {}
	hold_progress_bar.value = runner.hold_progress() * 100.0
	var hotspot: Rect2 = PrologueStaging.hotspot(shot)
	hotspot_marker.visible = kind == "look" and hotspot.has_area()
	hotspot_marker.position = hotspot.position
	hotspot_marker.size = hotspot.size
	if DebugFlags.ui_enabled:
		debug_text.text = "%s · cue %d/%d · стр. %d/%d\nфаза: %s · переход: %d тик." % [
			shot,
			runner.index + 1,
			runner.entries.size(),
			runner.page_index + 1,
			runner.page_count(),
			kind,
			runner.transition_ticks,
		]
	var signature: String = "%s:%s:%s" % [kind, shot, cue.get("enter", "")]
	if signature != _art_signature:
		_art_signature = signature
		_refresh_art(kind, cue, shot)
	if kind == "hold" and action_sprite.visible:
		action_sprite.frame = clampi(int(runner.hold_progress() * 4.0), 0, 3)
	_fit_dialogue_panel()

## Единый визуальный язык панели: одна подложка и один контур для всех планов.
## Акцент спикера, «Пропустить» и зона удержания сохраняют контраст при смене фона.
func _apply_dialogue_style(shot: String) -> void:
	if shot == _style_shot:
		return
	_style_shot = shot
	var bg := Color("111a24e8")
	var border := Color("8fa3c0")
	dialogue_panel.add_theme_stylebox_override("panel", AppTheme.flat(bg, border, 1, 0))
	page_cue.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT)
	story_text.add_theme_color_override("font_color", Color("e9e4d8"))
	speaker_tag.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
	hint_text.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
	hold_label.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT)
	var skip_styles: Dictionary = flat_states(bg, border)
	for state: String in skip_styles:
		var box: StyleBoxFlat = skip_styles[state]
		box.set_expand_margin_all(-SKIP_FRAME_INSET)
		skip_button.add_theme_stylebox_override(state, box)
	skip_button.add_theme_color_override("font_color", AppTheme.COLOR_TEXT)


func _refresh_hold_pulse() -> void:
	var idle := Color("1c2522")
	var highlighted := Color("574329")
	if hold_area.visible and not runner.holding and runner.transition_ticks == 0:
		if _hold_pulse == null:
			_hold_style.bg_color = idle
			_hold_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_hold_pulse.tween_property(_hold_style, "bg_color", highlighted, 0.55)
			_hold_pulse.tween_property(_hold_style, "bg_color", idle, 0.65)
		return
	if _hold_pulse != null:
		_hold_pulse.kill()
		_hold_pulse = null
	_hold_style.bg_color = highlighted if runner.holding else idle


## Состояния кнопки: normal/hover/pressed/focus/disabled.
func flat_states(bg: Color, border: Color) -> Dictionary:
	return {
		"normal": AppTheme.flat(bg, border, 1, 0),
		"hover": AppTheme.flat(bg.lightened(0.08), border.lightened(0.1), 1, 0),
		"pressed": AppTheme.flat(bg.darkened(0.12), border.darkened(0.1), 1, 0),
		"focus": AppTheme.focus_box(),
		"disabled": AppTheme.flat(bg.darkened(0.25), border.darkened(0.25), 1, 0),
	}

func _fit_dialogue_panel() -> void:
	var font: Font = story_text.get_theme_font("font")
	if font == null:
		return
	var font_size: int = story_text.get_theme_font_size("font_size")
	var text_height: float = ceilf(font.get_height(font_size) * MAX_TEXT_LINES)
	story_text.custom_minimum_size.y = text_height
	hold_area.custom_minimum_size.y = maxf(text_height, 42.0)
	var height: float = 3.0 + 18.0 + maxf(text_height, 42.0) + 16.0 + 6.0
	if hold_area.visible:
		height = hold_area.custom_minimum_size.y + 5.0
	dialogue_panel.offset_top = -7.0 - height
	dialogue_panel.offset_bottom = -7.0

func _update_speaker(raw: String) -> void:
	# «Харуто / мысли» -> имя + тег; имя визуально связано с репликой.
	speaker_name.get_parent().visible = not raw.is_empty()
	var parts: PackedStringArray = raw.split(" / ", false, 1)
	if parts.is_empty():
		speaker_name.text = ""
		speaker_tag.text = ""
		return
	speaker_name.text = parts[0]
	var accent: Color = AppTheme.COLOR_ACCENT if parts[0] == "Харуто" else AppTheme.COLOR_MAGIC
	speaker_name.add_theme_color_override("font_color", accent)
	speaker_accent.color = accent
	speaker_tag.text = parts[1] if parts.size() > 1 else ""
	speaker_tag.visible = false

func _update_page_cue() -> void:
	page_cue.visible = runner.current_kind() in ["line", "title"]
	var more_pages: bool = runner.page_index + 1 < runner.page_count()
	var parts: Array = runner.current_cue().get("parts", [])
	var more_parts: bool = runner.part_index + 1 < parts.size()
	page_cue.text = "▼" if more_pages or more_parts else "◆"

func _hint_for(kind: String) -> String:
	# Постоянные клавиатурные инструкции не показываем: Space остаётся рабочим
	# вводом на десктопе, но copy говорит только о касаниях.
	match kind:
		"look":
			return "Осмотрите переход"
		_:
			return ""

func _refresh_art(kind: String, cue: Dictionary, shot: String) -> void:
	var relative: String = ArtMap.PROLOGUE_SHOTS.get(shot, "")
	shot_frame.visible = not relative.is_empty()
	if not relative.is_empty():
		shot_frame.texture = ArtMap.texture(relative)
	var enter: String = String(cue.get("enter", ""))
	# Полноэкранные клипы Мицуки (свой фон внутри кадра).
	var full_name: String = PrologueStaging.full_clip(enter) if shot == "threshold" else ""
	if full_name.is_empty():
		if full_clip.visible:
			full_clip.stop()
			full_clip.hide()
	elif full_clip.sprite_frames != _mitsuki_clips[full_name] or not full_clip.is_playing():
		full_clip.sprite_frames = _mitsuki_clips[full_name]
		ArtMap.apply_animation_transform(full_clip, ArtMap.MITSUKI_FULL[full_name])
		full_clip.show()
		full_clip.play(&"default")
	# Светофор появляется в тревожном плане (cue signal).
	signal_prop.visible = shot == "alarm" and enter == "signal"
	# Актёрский оверлей: Юи на переходе; толчок — только если план не содержит
	# героя в кадре (иначе дубль).
	if kind == "hold" and not PrologueStaging.is_actor_overlay_suppressed(shot):
		if action_sprite.sprite_frames != _hero_push:
			action_sprite.sprite_frames = _hero_push
			ArtMap.apply_animation_transform(action_sprite, ArtMap.HERO_MODERN["push"], true)
		action_sprite.show()
		action_sprite.stop()
		action_sprite.frame = clampi(int(runner.hold_progress() * 4.0), 0, 3)
	elif shot == "crosswalk":
		var frames: SpriteFrames = _yui_step if kind == "look" else _yui_wait
		if action_sprite.sprite_frames != frames:
			action_sprite.sprite_frames = frames
			ArtMap.apply_animation_transform(action_sprite, ArtMap.YUI["step" if kind == "look" else "wait"], true)
		action_sprite.show()
		if not action_sprite.is_playing():
			action_sprite.play(&"default")
	else:
		if action_sprite.visible:
			action_sprite.stop()
			action_sprite.hide()

func _play_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	flash.modulate.a = 0.0
	_flash_tween = create_tween()
	# Длительность вспышки согласована с lock перехода (12 тиков):
	# следующая реплика не появляется под ещё яркой вспышкой.
	var duration: float = float(DialogueRunner.TRANSITION_TICKS) / Engine.physics_ticks_per_second
	_flash_tween.tween_property(flash, "modulate:a", 1.0, duration * 0.25)
	_flash_tween.tween_property(flash, "modulate:a", 0.0, duration * 0.75)
