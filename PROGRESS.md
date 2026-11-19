# PROGRESS

**Срез состояния:** 19 ноября 2026.

Утверждённый арт-пакет P0/P1 перенесён в `assets/`. Манифест фиксирует выбор пользователя и исходные версии, отчёт импорта хранит результаты Godot. Рабочие ревизии и превью хранятся в `art_working/`.

## Текущий этап

Gameplay vertical slice прошёл сквозную Windows-приёмку на blockout UI. Арт-пакет прошёл проверку в отдельном проекте Godot. Проверка FPS, touch и читаемости на целевом Android-устройстве ещё впереди.

Реализованы доменное ядро, бой со слизью и гоблином, добыча, инвентарь, экипировка, Checkpoint, локальный профиль и data-driven пролог. Подтверждён полный маршрут от нового профиля до возврата через Checkpoint и восстановления после настоящего перезапуска.

### Основной runtime

В [Godot-проекте](game/README.md) реализованы:

- persistent `GameRoot`, `SceneRouter`, `GameSession` и экраны `Title`, `Prologue`, `World`, `Combat`, `Reward`, `Inventory`, `Checkpoint`;
- общий deterministic tick-resolver с атакой, уклонением, телеграфом, vulnerability, двойным slash гоблина, победой и поражением;
- `CharacterState` с HP, однократной смертью, XP с остатком, несколькими level-up и выбором `strength`/`max_hp`;
- seeded loot, идемпотентная награда, инвентарь с фильтром, equip/unequip и модификаторы по `source_id`;
- глубокие Checkpoint-снимки, лимит три, 300-tick фиксация, выбор возврата, Первый след, fallback, Следы Пустоты, принудительный Лиорен и отдых;
- versioned JSON с `.tmp`/`.bak`, миграцией 0→1, defensive validation, `Continue` и подтверждением New game;
- 44 канонических cue пролога с tap, пагинацией, look/swipe, hold, `parts`, transitions, `Once` и выходом в World;
- логический viewport 180×320, фильтрация nearest и целочисленное масштабирование;
- headless runner: 50 наборов домена, боя, инвентаря, Checkpoint, сохранения и диалогов.

Сквозной сценарий пройден через экранные кнопки. Новый профиль прошёл пролог, поражение от слизи, Первый след за +1 След, победу в новой попытке, награду и экипировку, фиксацию Checkpoint, поражение от гоблина, полный выход, `Continue` и возврат к ручной точке за +1 След. Во втором процессе совпали SHA256 профиля, состояние героя, экипировка, инвентарь, победы, Отголоски, Следы и seen ID. Снятие оберега после отката записалось на диск. Финальный suite дал `passed=50 failed=0 unfinished=0`.

Ввод и вёрстка проверены на логическом 180×320 и в окнах 360×640 и 390×844; при 390×844 подтверждены integer scale ×2 и центрирование с offset `(15, 102)`. Использовались keyboard, mouse и synthetic touch. Бесплатного retry в основном маршруте нет. Черновые монтажи, бои и изображения в `art_working/` остаются изолированными превью.

## Готовность ассетов

Источники: [каталог карточек](docs/art/ASSET_PROMPT_TEMPLATES.md), [журнал генерации](docs/art/GENERATION_LOG.md), [сводная проверка](art_working/production_review/README.md), [покрытие именованных PNG](art_working/production_review/catalog_coverage.md) и манифесты рабочих партий.

| Область | Текущий результат | Статус готовности |
|---|---|---|
| Именованные P0 | 26/26 в утверждённом пакете | Импорт в проверочном Godot пройден |
| Именованные P1 | 112/112 в утверждённом пакете | Импорт в проверочном Godot пройден |
| Манифесты рабочих партий | 285 записей, включая ревизии, слои и спрайт-листы | Технические проверки пройдены |
| Арт-превью | 168 сцен, все 285 экспортов связаны с кадрами Godot | Сохранённый агрегированный отчёт без ошибок |
| Production `assets/` | 190 PNG, в том числе 52 спрайт-листа из 192 фаз | Все `approved`. Манифест и фактические файлы совпадают |
| P2 | Не созданы `vine_elder_idle.png` и `old_vine_heart_icon.png` | Отложены согласно плану; не блокируют MVP |

285 рабочих записей включают альтернативные версии, дополнительные варианты и спрайт-листы. Дополнительно проверены 59 компактных вариантов 32×32. Утверждённый комплект и результаты его импорта описаны в [папке ассетов](assets/README.md).

### Покрытие по типам

- **Персонажи и монстры:** все именованные P0/P1 статические спрайты и все движения из таблицы наборов собраны и проверены в рабочих превью. MON-09 относится к отложенному P2.
- **Окружения:** именованные фоны ENV-01–18 созданы как черновики. Для ENV-05, ENV-14, ENV-15 и ENV-17 дополнительно подготовлены дальний, средний и передний планы; правый запас пока использует временное зеркальное расширение.
- **Предметы и объекты:** выбранные P0/P1 иконки ITM и объекты OBJ созданы, включая отдельные игровые спрайты оружия ITM-01–03. Имеются точечные замечания к контрасту и мелким деталям в журнале.
- **Сюжет:** NAR-01–18 утверждены и собраны в интерактивный монтаж. Каноническая структура пролога работает в основном runtime с blockout. Монтаж с изображениями проверен отдельно.
- **Эффекты и UI:** именованные P0/P1 варианты FX и UI-01 созданы. FX-01/02 имеют анимационную пробу; часть остальных эффектов остаётся статической или покрывает только отдельную постановку.

### Анимационные наборы

Сверка ведётся с [таблицей наборов движений](docs/art/ASSET_PROMPT_TEMPLATES.md#наборы-движений).

| Актёр | Проверенные движения | Отчёт |
|---|---|---|
| CHR-01, Харуто современный | walk 4, alarm 2, run 4, push 4 | [Переход](art_working/tokyo_crosswalk_motion_p0_p1_2026_11_19/README.md) · [Спасение](art_working/tokyo_rescue_motion_p1_2026_11_19/README.md) |
| CHR-02, Харуто странник | idle 2, sword_attack 6, hit 2, pulse_check 4 | [Ожидание](art_working/trail_idle_animation_p0_p1_2026_11_18/README.md) · [Удар мечом](art_working/winds_edge_joint_action_p0_p1_2026_11_19/README.md) · [Реакции](art_working/haruto_and_raven_motion_p0_p1_2026_11_19/README.md) |
| CHR-03, Харуто после изгнания | idle 2, branch_attack 4, dodge 4, hit 2 | [Бой на Тропе](art_working/first_slime_combat_p0_p1_2026_11_19/README.md) · [Реакции](art_working/haruto_and_raven_motion_p0_p1_2026_11_19/README.md) |
| CHR-04, Мицуки | offer 3, wing_glitch 3 | [Белый Порог](art_working/white_threshold_motion_p0_2026_11_19/README.md) |
| CHR-07, Дайдзиро | idle 2, defend_cart 4 | [Защита телеги](art_working/daijiro_cart_motion_p1_2026_11_19/README.md) |
| CHR-08, CHR-11, CHR-14 | По три кадра работы с картой, склянкой и миской | [Лиорен](art_working/lioren_social_motion_p1_2026_11_19/README.md) |
| CHR-09, Акари | idle 2, seal 4, thrust 6 | [Ожидание](art_working/winds_edge_summon_motion_p0_p1_2026_11_19/README.md) · [Печать](art_working/winds_edge_joint_action_p0_p1_2026_11_19/README.md) · [Выпад](art_working/winds_edge_attack_motion_p0_p1_2026_11_19/README.md) |
| CHR-15, Юи | wait 2, step 4, displaced 3 | [Переход](art_working/tokyo_crosswalk_motion_p0_p1_2026_11_19/README.md) · [Спасение](art_working/tokyo_rescue_motion_p1_2026_11_19/README.md) |
| MON-01, слизь | idle 2, jump 6, hit 2 | [Ожидание](art_working/trail_idle_animation_p0_p1_2026_11_18/README.md) · [Прыжок и реакция](art_working/first_slime_combat_p0_p1_2026_11_19/README.md) |
| MON-02, гоблин | idle 2, double_slash 6, retreat 3 | [Защита телеги](art_working/daijiro_cart_motion_p1_2026_11_19/README.md) |
| MON-03, иглопёс | idle 2, quill_shot 4, leap 6 | [Роща](art_working/grove_monster_motion_p1_2026_11_19/README.md) |
| MON-04, пыльный мотылёк | hover 4, pollen 4 | [Роща](art_working/grove_monster_motion_p1_2026_11_19/README.md) |
| MON-05, корневой плетун | idle 2, grab 6 | [Захват](art_working/weaver_and_shieldback_motion_p1_2026_11_19/README.md) |
| MON-06, речной щитень | guard 2, claw_attack 6 | [Удар клешнёй](art_working/weaver_and_shieldback_motion_p1_2026_11_19/README.md) |
| MON-07, каменный грызун | idle 2, stone_throw 4, stunned 3 | [Бросок и оглушение](art_working/rodent_and_toad_motion_p1_2026_11_19/README.md) |
| MON-08, пепельный ворон | flap 4, dive 6 | [Взмах](art_working/winds_edge_summon_motion_p0_p1_2026_11_19/README.md) · [Пикирование](art_working/haruto_and_raven_motion_p0_p1_2026_11_19/README.md) |
| MON-10, кристальная жаба | idle 2, tongue 6, jump 6 | [Язык и прыжок](art_working/rodent_and_toad_motion_p1_2026_11_19/README.md) |
| MON-11, костяной дозорный | idle 2, stagger 4, sweep 8, summon 6 | [Ожидание и призыв](art_working/winds_edge_summon_motion_p0_p1_2026_11_19/README.md) · [Реакция](art_working/winds_edge_joint_action_p0_p1_2026_11_19/README.md) · [Размах](art_working/winds_edge_attack_motion_p0_p1_2026_11_19/README.md) |

Последние шесть монстров проверены в [превью Рощи](art_working/grove_monster_motion_p1_2026_11_19/README.md), [сценах плетуна и щитня](art_working/weaver_and_shieldback_motion_p1_2026_11_19/README.md) и [сценах грызуна и жабы](art_working/rodent_and_toad_motion_p1_2026_11_19/README.md). Для этих сцен сняты 68 контрольных фаз в каждом из трёх портретных окон.

### Ограничения текущей готовности

- В журнале сохранены замечания к мелким знакам, оттенкам и читаемости отдельных фаз. На 180×320 слабее видны светлые части игл на дорожке, суставы щитня и отдельные участки корпуса жабы.
- Проверки выполнялись на Windows в Godot 4.7.2 Compatibility. ADB не показал подключённых устройств. Реальный Android-экран и производительность устройства ещё предстоит проверить.
- Тайлы не являются текущим блокером: их размер и необходимость определяются после появления фактической TileMap-сцены.

## Основной runtime после проверки пакета

Игровые сцены остаются в состоянии vertical slice с blockout UI. Импорт утверждённой графики проверен в изолированном Godot-проекте. Постановки после пролога, боевой баланс и проверка на Android относятся к следующему этапу runtime.

