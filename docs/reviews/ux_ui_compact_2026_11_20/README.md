# Compact UI — доказательства и проверки, 20 ноября 2026

Повторный аудит реализации Kimi, затем реальные изменения существующего UI. См. [аудит](../../design/UX_UI_COMPACT_AUDIT_2026_11_20.md) и [промпт с ролями](../../design/KIMI_COMPACT_UI_ROLES_PROMPT.md).

## Условия

- Godot 4.7.2 stable Steam, Compatibility, Windows. База 180×320, nearest, integer scale.
- PNG сохранены из viewport запущенного managed-процесса. Размер 360×640 physical pixels; они **не показывают внешние letterbox-поля окна**.
- Только отдельные `--save-path=user://ux_compact_…` и `user://ux_ui_final_20261120.json`; основной пользовательский профиль не перезаписывался.
- Файлы `before_*` сняты до нашей перекомпоновки, уже после правок Kimi. Съёмка началась 19 ноября и продолжилась после смены локальной даты. Старые каталоги предыдущего аудита не заменены.
- `ui_review_capture.gd` переключает экраны и подготавливает данные. Inventory, Reward с мечом, три Checkpoint и список возврата — **fixtures**, не свидетельство полного прохождения главы вручную.

## Кадры

| Экран | До | После |
|---|---|---|
| Combat, слизь | [до](before_combat.png) | [после](after_combat.png) |
| Dialogue, первая реплика | [до](before_dialogue.png) | [после](after_dialogue.png) |
| World, начальное состояние | [до](before_world.png) | [после](after_world.png) |
| Inventory | [пустая сумка до](before_inventory.png) | [fixture с предметами после](after_inventory.png) |

Дополнительные состояния:

- [Title](after_title.png), [look](after_look.png), [hold](after_hold.png), [светлый Порог](after_threshold.png).
- [Атака и cooldown](after_cooldown.png): один synthetic touch по мечу действительно уменьшил HP слизи с 6 до 3; число урона рядом с врагом.
- [Гоблин](after_goblin.png), [победа](after_victory.png), [поражение](after_defeat.png). Конечные состояния получены реальной симуляцией resolver через helper; это не запись всего боя одними UI-кнопками.
- [Реальная награда после победы](after_reward_actual.png), [fixture награды с мечом](after_reward.png).
- [Выбранный предмет](after_item_details.png), [после нажатия «Надеть»](after_item_equipped.png). Preview 5 → 5 у уже надетого меча, без второго сложения модификатора.
- [Три ручные точки](after_checkpoint.png), [список возврата](after_return.png), [выбор Первого следа и preview цены](after_return_preview.png).

## Фактические размеры окон

| Window | Root viewport | Scale | Offset | PNG |
|---|---|---|---|---|
| 360×640 | 180×320 | 2×2 | 0, 0 | Основные кадры |
| 360×800 | 180×320 | 2×2 | 0, 80 | [контент](after_world_window_360x800.png) |
| 390×844 | 180×320 | 2×2 | 15, 102 | [контент](after_world_window_390x844.png) |
| 412×915 | 180×320 | 2×2 | 26, 138 | [контент](after_world_window_412x915.png) |

Поля остаются: эти кадры подтверждают стабильность фиксированной компоновки, **не полноценный adaptive viewport**. Отдельный headless runner дополнительно открывает сцены в расширенных логических размерах 180×400, 195×422, 206×458; это проверки запаса контейнеров, а не утверждение, что production уже использует такую policy.

## Проверки

```text
tests/test_runner.gd
RESULT: passed=55 failed=0 unfinished=0

tests/ui_layout_runner.gd
UI_RESULT: checks=607 failed=0
```

Оба запуска завершились с кодом 0; `script_errors=[]`, stderr пустой, exit_leaks отсутствуют. GUI runner не использует SaveService и не пишет игровой профиль.

GUI checks охватывают границы видимых кнопок/текста вне scroll, initial focus, touch внутри DialoguePanel ровно на одну страницу, весь корпус реплик/parts на трёх ширинах, реальную высоту строк, preview надетого предмета, фокус после пересборки сетки и освобождения узлов, закрытие деталей через Back, modal focus, один telegraph tween, позицию damage Label, safe-area inverse transform и предупреждение о Лиорене при третьем Следе.

Отдельно в запущенной игре проверены synthetic touch с включённой mouse emulation: перелистывание панели, look по hotspot, раннее отпускание hold (progress сброшен), успешный hold (один переход), атака кнопкой-иконкой, переход с победы к награде, equip кнопкой, ui_cancel закрывает детали, выбор возврата. Финальный runtime-журнал перед остановкой — без ошибок и предупреждений. Управляемый stop инструмента может вернуть exit 1; это не результат тестов.

Физический Android, dp, системные вырезы/жесты, hardware Back, 30/60 FPS на телефоне, торговля и новая серия quit/relaunch в этой итерации **не проверялись**. Ранее выполненные проверки других исполнителей не выдаются за повторно выполненные.
