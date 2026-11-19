# Game runtime

Godot 4.7.2, GDScript и Compatibility renderer. Persistent `GameRoot` владеет `GameSession`, `SceneRouter` и вызовами `SaveService`; экраны внутри `ScreenHost` только вызывают команды и отображают состояние. Маршрут: `Title → Prologue → World`, далее общие экраны `Combat`, `Reward`, `Inventory` и `Checkpoint`.

Базовый viewport — 180×320, фильтрация nearest и целочисленный масштаб. Ввод: `Space`/касание — основное действие, `E` — уклонение, `I` — инвентарь, `C` — Печать Пути. В прологе поддержаны tap, пагинация, отдельная look-область/swipe и hold с отменой при раннем отпускании.

## Состояние и правила

- `domain/definitions/` и `data/` — typed `Resource`, определения актёров, предметов, модификаторов и таблиц добычи;
- `domain/state/` — независимое runtime-состояние героя, предметов, боя и профиля;
- `domain/services/` — seeded loot, инвентарь, Checkpoint, сохранение и линейный dialogue runner;
- `data/narrative/prologue.json` — 44 канонических cue со стабильными ID, presentation cues, `parts`, `Once` и whitelist команд;
- `tests/test_runner.gd` — единая точка входа для 50 headless-наборов правил без UI.

Runtime копирует значения из read-only определений и не изменяет `.tres`. Урон рассчитывается как `maxi(1, roundi((attack - defense) * window_multiplier))`. `CombatResolver` использует integer ticks и фазы `telegraph → startup → active → recovery → vulnerability`; гоблин выполняет два удара за цикл. Победа создаёт идемпотентную pending reward; снаряжение добавляет модификаторы по `source_id`, не перезаписывая base stats и не лечя героя.

Награда показывает итоговые значения после экипировки с учётом заменяемого предмета и Следов Пустоты. При загрузке профиль сначала восстанавливает модификаторы экипировки, затем текущее HP. После отката `GameRoot` подписывается на восстановленный инвентарь, чтобы новые изменения экипировки сохранялись.

Поражение требует возврата через Печать Пути, бесплатного retry в основном маршруте нет. Ручной Checkpoint фиксируется за 300 тиков вне боя; одновременно доступны три точки. Возврат откатывает профиль к глубокому снимку, расходует выбранную и более поздние точки и добавляет След Пустоты. Мета-прогрессия и seen-флаги сохраняются. Три Следа ведут в Лиорен; отдых снимает их без восстановления потраченных ресурсов.

`SaveService` хранит один versioned JSON-профиль в `user://`, использует primitive DTO, `.tmp`/`.bak`, defensive validation и миграцию схемы 0→1. Автосохранение выполняет только `GameRoot` и только вне боя и активной фиксации. Для изолированного запуска можно передать пользовательский аргумент `--save-path=user://...`.

Все числовые значения HP, XP, добычи, боевых окон, канала, hold и переходов — blockout-гипотезы, а не утверждённый баланс. Draft-изображения из `art_working/` в runtime не подключены.

## Проверки

При доступном в PATH Godot:

```bash
godot --headless --path game --import
godot --headless --path game --script res://tests/test_runner.gd
godot --headless --path game --quit-after 300
```

Runner выводит passed/failed/unfinished и возвращает `1`, если есть failed или unfinished case. Последний полный прогон дал `passed=50 failed=0 unfinished=0`. Сквозной Windows smoke охватил восемь сцен и 18 экранных состояний. Проверены поражение от слизи, Первый след, победа в следующей попытке, сравнение и экипировка награды, поражение от гоблина, настоящий quit/relaunch через `Continue`, откат к ручному Checkpoint и автосохранение снятого оберега.

Проверены логический viewport 180×320, окна 360×640 и 390×844; на последнем подтверждены scale ×2 и offset `(15, 102)`. Использовались keyboard, mouse и synthetic touch. Импорт [утверждённого арт-пакета](../assets/README.md) проверен в отдельном проекте. Проверки touch и 30/60 FPS на Android-устройстве предстоят.
