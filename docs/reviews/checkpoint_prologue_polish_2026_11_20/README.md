# Печать, HP и оформление пролога · 20 ноября 2026

Итоги итерации по [повторному аудиту](../scene_visual_reaudit_2026_11_20/README.md) ([prompt](../../design/KIMI_CHECKPOINT_AND_PROLOGUE_POLISH_PROMPT.md)). Реализованы все пять пунктов: commit-граница записи Печати, единая шкала HP, локационный фон и подписи Печати, общий визуальный язык диалогов и выбор разрешения пролога. Финальные прогоны: `test_runner` **77/77**, `ui_layout_runner` **979 checks / 0 failed**, `animation_assets_runner` **256/256** (обычный и fixed 60), exit 0 и пустой `script_errors` во всех трёх. Платформа проверок — Windows, Godot 4.7.2, Compatibility renderer, headless + графические окна.

## Печать: отказ записи и состояния

| Кадр | Состояние |
| --- | --- |
| [checkpoint_error_360x640.png](checkpoint_error_360x640.png) | Ошибка фиксации: inline-панель рядом с действием, retry доступен, список/Следы/расход точек совпадают с последним подтверждённым состоянием, справка видима |
| [checkpoint_trail_empty.png](checkpoint_trail_empty.png) | Пустой список на Тропе: фон локации виден, «Печать · Следы 0/3», «Точек пока нет», первый след доступен |
| [checkpoint_trail_three.png](checkpoint_trail_three.png) | Три ручные точки: «Точек: 3/3», NBSP в «ур. 2», карточки с местом/уровнем/ценой |
| [checkpoint_traces_full.png](checkpoint_traces_full.png) | «Следы 3/3» — обязательный переход в Лиорен; причина показана первой, выбор точки ничего не расходует |
| [checkpoint_lioren.png](checkpoint_lioren.png) | Печать в Лиорене: фон Лиорена, отдых сбрасывает Следы, заголовок «Печать · Следы 3/3» |
| [checkpoint_return_preview.png](checkpoint_return_preview.png) | Выбор возврата: превью снимка по `snapshot.location_id`, цена и последствия в подтверждении |

Регрессии отказа: `game/tests/ui_layout_runner.gd` → `_test_checkpoint_commit_failure` (фиксация и возврат при заблокированном `.tmp`: память == диск == последнее подтверждённое состояние, `.bak` = предыдущее, повтор применяет действие ровно один раз, экран остаётся на месте) и `_test_checkpoint_presentation` (+8 проверок фона, превью, заголовков Следов и NBSP).

## HP и HUD

| Кадр | Состояние |
| --- | --- |
| [combat_hp_full.png](combat_hp_full.png) | Полное HP обеих сторон: трек и fill в одном 36×4 от (0,0), тонкая приглушённая подложка, без тяжёлой кромки |
| [combat_hp_partial.png](combat_hp_partial.png) | Частичное HP (герой 8/12, враг 10/20), в том числе у краёв арены |
| [combat_hp_one.png](combat_hp_one.png) | 1 HP — заполнение минимально читаемо |
| [combat_hp_zero.png](combat_hp_zero.png) | 0 HP — пустой трек, на Тропе полное HP по-прежнему скрыто |
| [alarm_signal_360x640.png](alarm_signal_360x640.png) | Индикатор «Автобой» с тёмной подложкой на светлой листве; уклонение и режим очевидны |

До: [combat_hp_360.png](../scene_visual_reaudit_2026_11_20/combat_hp_360.png) из повторного аудита (смещённая светлая полоска, толстая кромка).

## Диалоги пролога

| Кадр | Состояние |
| --- | --- |
| [dialogue_tokyo_short.png](dialogue_tokyo_short.png) | Токио, короткая реплика: сланцево-синяя палитра, PNG-рамка `dialogue_panel_normal.png` (nine-slice), янтарный акцент спикера, «Пропустить» в той же системе |
| [dialogue_tokyo_long.png](dialogue_tokyo_long.png) | Токио, длинная русская реплика: подложка текста, пагинация по реальным внутренним отступам, углы рамки вне зоны реплик |
| [dialogue_threshold_short.png](dialogue_threshold_short.png) | Порог, короткая реплика: светлая перламутровая панель, тёмный текст |
| [dialogue_threshold_long.png](dialogue_threshold_long.png) | Порог (Мицуки), длинная реплика: читаемость на ярком кадре, акцент рядом с именем |

Все cue пройдены: длинный русский текст, внешний тап, hotspot, отмена удержания, skip, восстановление после Continue — покрыто раннерами и сценариями пролога.

## Разрешение пролога: сравнение и выбор

Сетка по окнам: строки — план (`crosswalk` = ENV-01, `routine` = NAR-01, `seal` = NAR-05, `threshold` = NAR-06), столбцы — источник (`production` = текущий 180×320, `360x640`, `540x960`, `720x1280`).

- Окно 360×640: [sheet](_sheet_360_window.png), планы [crosswalk](res_360x640_crosswalk_production.png) / [routine](res_360x640_routine_production.png) / [seal](res_360x640_seal_production.png) / [threshold](res_360x640_threshold_production.png) (production; кандидаты — `_*_<N>x<M>.png` рядом)
- Окно 720×1280: [sheet](_sheet_720_window.png), планы [crosswalk](res_720x1280_crosswalk_production.png) / [routine](res_720x1280_routine_production.png) / [seal](res_720x1280_seal_production.png) / [threshold](res_720x1280_threshold_production.png)

Кроп лица NAR-01: [production](_crop_face_production.png) / [540×960](_crop_face_540x960.png) / [720×1280](_crop_face_720x1280.png).

Решение: **540×960 для всех семи still** (NAR-01..06 + ENV-01). Прирост 720×1280 заметен только в окне 720×1280 при почти двойном VRAM (≈26 против ≈14,5 МБ на семь кадров); 180×320 теряет мелкие детали лица/телефона/костюма. Экспорт LANCZOS из мастеров 941×1672 скриптом `tools/export_prologue_stills_540.py`; манифест и `tools/copy_art.py` обновлены; hotspot и позиции анимированного реквизита совпадают на контрольных кадрах.

## Окна и компоновка

По пять окон для каждого экрана (`360×640`, `360×800`, `390×844`, `412×915`, `720×1280`): [combat](size_combat_360x640.png) (`size_combat_*.png`), [checkpoint](size_checkpoint_360x640.png), [dialogue](size_dialogue_360x640.png). При aspect keep + integer окна 360×800/390×844/412×915 дают viewport 360×640 с letterbox; tall-логика дополнительно покрыта раннером на 180×400/195×422/206×458; 720×1280 рендерится ×4. Дефектов компоновки не найдено.

## Ограничения и следующие шаги

- Физический Android, системные жесты, вырезы, FPS/нагрев и полный прогон пролога на устройстве не проверены.
- Рамки Порога и леса пока StyleBoxFlat по палитрам планов; запрос PNG-рамок остаётся открытым в [арт-брифе](../../art/CHATGPT_PROLOGUE_DIALOGUE_ART_PROMPT.md).
- Апгрейд still до 720×1280 записан как путь на случай playtest-замечаний; мастеры 941×1672 сохранены.
