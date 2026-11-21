# Стабилизация Path of Reborn — приёмка A01–A12

Дата: 2026-11-20. Godot 4.7.2, Compatibility, Windows. Рабочее дерево уже содержало изменения предыдущих итераций; оно не откатывалось и не коммитилось. Все runtime-проверки использовали изолированные `user://path_of_reborn_tests/...`.

Исходные красные результаты сохранены в [baseline.md](baseline.md). Прежние доказательства в `docs/reviews/plan_acceptance_2026_11_20/` не перезаписывались. Итоговый статус ниже относится к текущему рабочему дереву, а не к коммиту.

## 1. Сохранение, жизненный цикл и ввод

| ID | Статус | Исправление и доказательство | Оставшееся ограничение |
|---|---|---|---|
| A01 | Исправлено | `GameRoot.claim_battle_result()` применяет награды к отдельной проекции, проверяет фактический `SaveService.save() == true` и только затем заменяет живое состояние, публикует settlement и переходит в World (`game_root.gd:72`). `SaveService` сохраняет атомарные `.tmp`/`.bak` (`save_service.gd:38`). UI-тесты блокируют `.tmp` на prepare и claim: результат остаётся видимым, проекция/инвентарь не публикуются, повтор не делает reroll. После failed claim загрузка восстанавливает идентичный pending. | После failed prepare на диске намеренно остаётся прежнее согласованное состояние без нового pending; живой результат можно повторно записать. Отдельный claim-journal не вводился. |
| A02 | Исправлено | Schema v4: один canonical root `pending_battle_result`, `trial_echo_claimed` в `meta`; pure migration v0–v3, вложенные Checkpoint DTO и одинаковая валидация после миграции (`save_service.gd:4`, `save_service.gd:129`). При конфликте v3 побеждает profile-копия, которую применял старый runtime; невалидная копия отклоняет DTO. Выданная v2-добыча не становится pending. | Старые сейвы проверены как фикстуры соответствующих форм; дополнительных устройств с пользовательскими файлами не было. |
| A03 | Исправлено | Один `active_resolver`, процессно уникальный `run_token`, закрытие resolver при retry/surrender/new/load/Checkpoint и guards несовместимых команд (`game_session.gd:168`, `game_session.gd:178`). `_claim_in_progress` устанавливается до внутренних сигналов (`game_session.gd:350`). Регрессии покрывают reentrant claim из `inventory.changed` и stale damage/finish на всех пяти границах. | Сетевой или многопроцессный доступ к одному файлу не поддерживается и не входил в задачу. |
| A04 | Исправлено | Результат принимает пару press/release одного pointer с kind/device/index/start; drag, canceled, второй палец, details и focus loss отменяют кандидат. Событие consume до навигации, обращения к viewport после выхода нет (`combat_screen.gd:124`). Touch, emulated mouse, обычная мышь и `ui_accept` используют один claim. | Системные жесты и реальный multitouch Android не проверялись; синтетические события Godot и живой Windows-ввод пройдены. |
| A05 | Исправлено | HUD, dodge и cooldown читают зафиксированный контекст текущего resolver; пауза меняет только предпочтение следующего боя и явно пишет «Со следующего боя» (`combat_screen.gd:273`, `combat_screen.gd:303`). `save_combat_format()` записывает настройку сразу (`save_service.gd:49`). Живой сценарий подтвердил auto→active и active→auto: текущая автоматика не менялась; настройка пережила Checkpoint и перезапуск. | Реальное закрытие мобильного приложения сразу после настройки проверено только аналогом процесса Windows, не Android lifecycle. |

## 2. UX, декомпозиция и экипировка

| ID | Статус | Исправление и доказательство | Оставшееся ограничение |
|---|---|---|---|
| A06 | Исправлено в текущем арт-наборе | `CombatArenaPresenter` — единственный владелец клипов, layout, HP, телеграфа, чисел, intro, pause и transient tweens (`combat_arena_presenter.gd:35`). Контакты героя: тики 19/79, frame 3; гоблина: 48/66, contact frames 1/4, preparation 0/3. Hit/dodge героя имеют приоритет, контакт обозначается локальным эффектом. Урон создаёт только resolver. | У гоблина нет отдельного hit clip; используется явный fallback. Новые кадры не генерировались. |
| A07 | Исправлено | `CombatResultView` содержит scroll, XP/рост/Эхо, фокусируемые item Buttons и одну компактную кнопку claim (`combat_result_view.gd:43`). Крупная золотая «Победа» без фоновой карточки сохранена; режим, dodge, equipment и лишние подсказки скрыты. Детали не собирают предмет, Back возвращает к результату. См. [победу](live/02_victory_charm_360x640.png) и [детали](live/03_victory_details_360x640.png). | Визуальная оценка сделана на Windows viewport; доступность screen reader на Android не проверялась. |
| A08 | Исправлено | После маршрута остаётся один главный CTA в тот же encounter sheet; отдельный repeats CTA скрыт. Статусы и режим получили локальные подложки, equipment/CTA/Печать/dodge проверены на пересечения. Геометрия проверена для 360×640, 360×800, 390×844 и 412×915. | Tall-screen полосы остаются letterbox; новое адаптивное использование высоты не вводилось. |
| A09 | Исправлено | Общие `ItemDetailsView` и `EquipmentModel` обслуживают Inventory, World и результат (`item_details_view.gd:25`, `equipment_model.gd:29`). `gain_xp()` и preview вызывают `CharacterState.calculate_level_gain()` (`character_state.gd:66`, `character_state.gd:85`). Route продолжает использовать существующий JSON и один валидатор. | `GameSession` остаётся интеграционным владельцем нескольких subsystem; преждевременный второй роутер или новый слой не создавались. |
| A12 | Исправлено функционально; visual fallback | Источник — `InventoryService.equipment` по `slot_id → instance_id`. Закреплённое «Надето», occupied/empty слоты, фильтр пустого слота, доступные имена, точные instance ID, replace/unequip и полные отрицательные дельты покрыты UI-тестами. Тропа и бой показывают занятые миниатюры; preview находки read-only. См. [Сумку](visual/412x915_inventory.png), [Тропу](visual/412x915_world.png) и [бой](visual/412x915_combat.png). | Нет approved still/idle/attack/hit/dodge-комплекта с мечом. Используется icon-fallback поверх текущего героя, поэтому исходная ветка в базовом кадре и отдельная иконка могут читаться как два оружия. Это не финальный composite art. Физической отрисовки оберега на костюме нет. |

## 3. Испытание, баланс и графический профиль

### A10 — исправлено

Принято фактическое правило: первая победа над trial даёт суммарно **+2 Эхо** — +1 за первый enemy ID и +1 разовый trial bonus. Оба UI-входа и результата называют фактический бонус и риск Печати. Флаг и валюта принадлежат `meta`, поэтому сценарий «снимок → +2 → сдача/rollback → повторная победа» даёт **+0 дополнительного trial bonus**, а не +1. Миграция использует OR старого profile flag и meta flag, не меняя заработанный баланс.

XP после cap накапливается в сейве; claim и preview используют один расчёт. Таблицы добычи не расширялись: разнообразие оставлено отдельной гипотезой.

`balance_simulation_runner.gd` теперь использует `sword_only` без скрытых HP-улучшений и называет политику `first_available_window_v1` по фактическому правилу, без объявления верхней границы. Сохранены 180 isolated и 90 route записей с одинаковыми seeds 11/22/33: [isolated JSONL](balance_isolated.jsonl), [route JSONL](balance_route.jsonl).

| Сборка / полный auto | Изолированный trial | Полный маршрут слизь → гоблин → trial |
|---|---|---|
| base | поражение, 462 тика / 0 HP | без прогресса: поражение на trial, 1100 суммарных тиков |
| strength_2 | победа, 259 / 6 HP | победа, 777 / 6 HP |
| health_2 | победа, 499 / 8 HP | победа, 1137 / 8 HP |
| sword_only | 259 / 6 HP, max HP 12 | см. отдельные drop-equipment записи |
| drop_equipment | — | seeds 11/22 победа, seed 33 поражение |
| upgrades + drops | — | все проверенные seeds прошли |

Это детерминированные сравнения resolver, не нормы реакции человека. Добавлены manual policies с разной задержкой; `first_available_window_v1` не считается oracle.

### A11 — измерено; арт-пробелы остаются открытыми

Один и тот же бой снят в [360×640](graphics/combat_360x640.png) и нативном [1080×1920](graphics/combat_1080x1920.png). Схема остаётся 180×320, `canvas_items`, integer, nearest, Compatibility. Мастера и raster density не менялись.

[profile.json](graphics/profile.json), Windows/NVIDIA, `Performance.MEMORY_STATIC` (не полный RSS/VRAM телефона):

| Операция | Синхронный вход | До первого draw | Static memory после |
|---|---:|---:|---:|
| Первый пролог | 272,357 мс | 283,528 мс | 59,13 MiB |
| Повторный пролог | 219,757 мс | 233,548 мс | 59,78 MiB |
| Первый бой | 172,940 мс | 180,494 мс | 62,02 MiB |
| Повторный бой | 8,327 мс | 25,240 мс | 61,12 MiB |

Skip→World занял 100,075 мс; native 1080×1920 показал 81,95 MiB static memory. Для desktop slice признаков блокирующей загрузки нет, поэтому eager prologue сохранён и cue-prefetch не добавлен. Это не Android-бюджет.

Визуально подтверждены читаемые силуэты и HP, но разная плотность фона/персонажа, слабые контактные тени, зазор HP слизи и дистанция ударов остаются художественными ограничениями. Для окон 360×800/390×844/412×915 integer scale ×2 даёт содержимое 360×640 и физические полосы; capture сохраняет содержимое viewport, а не полосы. Геометрия и offsets проверены отдельно UI-runner.

## 4. Приёмочные прогоны

Все команды выполнялись для `game/` через Godot MCP; fixed-варианты используют `--fixed-fps 60`.

| Проверка | Обычное время | Fixed 60 |
|---|---:|---:|
| `res://tests/test_runner.gd` | 74 passed / 0 failed / 0 unfinished | 74 / 0 / 0 |
| `res://tests/ui_layout_runner.gd` | 934 checks / 0 failed | 934 / 0 |
| `res://tests/animation_assets_runner.gd` | 256 checks / 0 failed | 256 / 0 |
| `res://tests/balance_simulation_runner.gd` | 270 записей, 0 script errors | не требовался повтор: вход deterministic ticks |

У всех финальных headless-прогонов exit 0, stderr пуст, `script_errors=[]`. В animation runner сначала обнаружен timing-flake: 50 реальных кадров не гарантировали tween 0,6 с; тест теперь ограниченно ждёт фактическое завершение, проверка очистки не ослаблена. `iteration_acceptance_probe.gd` остаётся диагностическим и не считается штатным зелёным тестом.

Живой Windows input-playthrough на изолированном профиле:

`Начать → Пропустить → Идти дальше → победа → чтение → детали → Back → touch claim → Сумка → сила +1 → надеть оберег → гоблин → ui_accept claim → испытание → повтор → пауза/режимы → Сдаться → Печать → Первый след`.

- До первого claim: 0 предметов, level 1, 0 XP, 0 Эхо; после: 1 предмет, level 2, 1 Эхо, route index 1.
- После гоблина: level 3, 2 предмета, 2 Эхо, route completed; один `ui_accept` дал один переход.
- Первый trial довёл баланс до 4 Эхо за весь маршрут; повторная защита подтверждена тестами.
- Сдача без лишнего подтверждения открыла существующий выбор Печати. Возврат откатил level/items/equipment, сохранил 4 Эхо и активное предпочтение.
- Перезапуск до claim восстановил тот же `result_id`, `loot_state` и 2 Кристалла Эха; после claim перезапуск сохранил ровно один inventory stack, level 2 и отсутствие pending.
- Журналы живых процессов: 0 errors/warnings. Долгое чтение, press до победы, drag, canceled, два пальца, emulated mouse, focus loss и details gesture покрыты реальными сценами в UI-runner; живой ввод дополнительно покрыл mouse, touch и accept.

Дополнительные кадры: [пустая Тропа](live/01_world_empty_360x640.png), [экипированная Сумка](live/04_inventory_equipped_360x640.png), [выбор испытания](live/06_trial_entry_360x640.png), [auto pause](live/08_repeat_pause_before_switch_360x640.png), [Печать после сдачи](live/10_seal_after_surrender_360x640.png), [active pause](live/12_active_pause_360x640.png). Полный комплект на разных окнах находится в [visual/](visual/).

## 5. Применённые проверки скиллов

- `por-godot-architecture-api`, `godot-code-review`, `gdscript-patterns`: владельцы состояния, публичные команды, resolver identity, отсутствие UI→SaveService/RNG, типизированные GDScript-контракты.
- `save-systems`, `godot-gdscript-headless-testing`: pure migration, fixtures v0–v3, atomic replace/backup, blocked `.tmp`, изолированные `user://`, exit status, stderr, unfinished count, fixed/real time.
- `por-mobile-combat-ux`, `game-ui-ux`, `godot-ui-control`, `mobile-design`, `input-handling`: portrait composition, один CTA, scroll/focus, modal Back, pointer identity/cancel, safe-area mapping, hit targets.
- `godot-animation`, `game-feel`, `assets-pipeline`: contact mapping, clip priority, pause/resume, tween cleanup, AtlasTexture regions/margins, approved ArtMap assets только.
- `headless-game-balance`, `rpg`: парные seeds/builds, настоящий route/claim/RNG/upgrades/drops, политики без ложного oracle, общий XP cap contract.
- `godot-debugging`, `game-docs`: живой журнал, воспроизводимые fixtures, отдельные новые evidence, обновление текущих документов.

## 6. Принятые решения/гипотезы и непроверенное

- Сохранена текущая auto-dodge гипотеза: первая STARTUP-фаза цикла при готовности, cooldown 150 тиков; это не доказанная верхняя граница.
- Первый trial bonus утверждён в этой итерации как суммарные +2; числа боя и cooldown остаются blockout-гипотезами.
- До появления approved weapon composite допускается только честный icon-fallback; неутверждённые кандидаты из `art_working/` не подключались.
- Новых production PNG не добавлено. Проверены существующие approved 15 клипов / 49 кадров, AtlasTexture и иконки ArtMap; отсутствуют полный sword composite, goblin hit и отдельные death/walk клипы.
- Не проверены физический Android, системные жесты/вырезы, реальный background/return, OS text scale, FPS/нагрев, экспорт и мобильная память. Desktop synthetic touch не заменяет эти проверки.
