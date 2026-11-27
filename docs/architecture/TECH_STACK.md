# TECH STACK

## Рекомендация

Рекомендуется **Godot 4.x + GDScript + Git + Aseprite (или LibreSprite)**. Для первого 2D-портретного прототипа использовать Compatibility renderer; после device smoke test можно переключить мобильный проект на Mobile renderer. Это решение минимизирует стоимость и объём инфраструктуры, сохраняя Android/iOS экспорт и расширяемость сцены/данных.

Официальная документация Godot указывает MIT-лицензию, 2D-поддержку, Compatibility/Mobile renderers и native Android/iOS exports: [FAQ](https://docs.godotengine.org/en/stable/about/faq.html), [renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html), [system requirements](https://docs.godotengine.org/en/stable/about/system_requirements.html), [license compliance](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).

## Сравнение движков

| Критерий | Godot 4.x | Unity 6 |
|---|---|---|
| Pixel art и 2D | TileMap, Canvas/UI, import settings и простая сцена хорошо подходят | Очень зрелый 2D toolset, больше интеграционных возможностей |
| Перспектива | Удобна 2D/2.5D; 3D доступна при необходимости | Сильна для 2D и 3D, но сложнее минимальный 2D-проект |
| Анимация | AnimatedSprite2D, AnimationPlayer, particles | Animator, Timeline, 2D Animation, большой ecosystem |
| UI | Control nodes, anchors, themes, scene composition | Canvas UI и большой набор готовых решений |
| Сохранения | Небольшой собственный save layer без обязательного сервиса | Аналогично, но больше вариантов cloud/service |
| Mobile | Android/iOS export; Compatibility шире для старых устройств | Сильный mobile pipeline, больше build tooling |
| MVP speed | Меньше editor overhead, GDScript и открытый runtime | Много готовых пакетов, но package/project overhead выше |
| Расширение | Достаточно для offline RPG; сетевой слой добавлять позже | Сильнее marketplace и enterprise ecosystem |
| Стоимость/лицензия | MIT, без роялти движка; учитывать лицензии сторонних плагинов | Personal до $200k revenue/funding, Pro выше порога; проверять актуальные условия |

Официальные условия Unity: [licensing](https://unity.com/pages/license-compliance) и [plans](https://unity.com/products). Порог и цены могут меняться, поэтому проверять перед коммерческим релизом.

## Технические решения MVP

- **Scenes:** persistent `GameRoot` с `Title`, `Prologue`, `World`, `WorldMap`, `Combat`, `Inventory` и `Checkpoint`. Маршрутизация через `SceneRouter`. Результат боя отображается в `Combat`.
- **Карта мира.** `GameSession` определяет посещённые места и допустимый первый визит. Посещения хранятся в существующих `memory_flags`, общих для временных линий Печати. Для старых профилей учитывается состояние локации и пройденные сюжетные вехи. `GameRoot` сохраняет кандидата профиля перед сменой локации и первым входом в лавку. При отказе записи направление остаётся доступным для повтора. Вход в Гильдию также записывает флаг активного визита для Continue. Общая сцена карты загружает иллюстрацию долины или Лиорена через `ArtMap` и размещает кнопки поверх неё по нормализованным координатам фона.
- **Domains:** `GameSession`, `CharacterState`, `CombatResolver`, `LootGenerator`, `InventoryService`, `CheckpointService`, `SaveService`, `DialogueRunner`.
- **Data:** `Resource` для authoring в Godot; сериализуемый save DTO для прогресса; item/enemy definitions отдельно от runtime state.
- **UI:** `Control` scenes с anchors/safe area; UI подписывается на состояние, а не меняет доменные правила напрямую.
- **Input:** abstract actions (`primary`, `secondary`, `inventory`, `checkpoint`) с touch mapping; keyboard mapping только для desktop smoke test.
- **Rendering:** рисованные текстуры с линейной фильтрацией, дробный масштаб портретной базы 180×320 и проверка бюджета памяти на Android.
- **Save** хранит локальный профиль v7 в `user://` с миграциями v0–v6 и резервной копией. Награда остаётся в корневом `pending_battle_result` до успешной записи. Один результат относится ко всей встрече. Вехи Рощи, Синего Оврага и Края Ветров входят в снимок Печати. Эхо и память о репликах хранятся в `meta`. [Границы записи Рощи](../reviews/grove_stage_2026_11_22/README.md#маршрут-сохранение-и-баланс) · [Команды Оврага](../design/MVP_BLUE_HOLLOW.md#состояние-и-запись) · [Состояние поста](../design/MVP_WINDS_EDGE.md#состояние-и-запись)
- **Networking:** отсутствует в MVP; не добавлять multiplayer SDK или серверный backend.

## Запись команд и восстановление профиля

Экраны передают запрос в `GameRoot`. Получение награды, сделки, переходы по карте, задания и операции Печати применяются к копии `GameSession`. После успешной записи корневой узел публикует новое состояние в существующей сессии. Подписчики сразу видят и результат действия. При ошибке остаются прежние предметы, деньги и право повтора. Замена профиля на титульном экране использует тот же порядок. [Граница записи](../../game/scripts/game_root.gd)

`SaveService` отвечает за чтение основного файла и восстановление резервной копии. `ProfileSchema` мигрирует копию данных и проверяет текущий профиль и вложенные снимки. Профиль остаётся в формате v7. Настройки имеют собственную схему. Обе службы записывают JSON через временный файл и обновляют резервную копию после проверки основного файла по своей схеме. [Схема профиля](../../game/domain/services/profile_schema.gd) · [Запись файлов](../../game/domain/services/atomic_json_file.gd)

Боевые и сюжетные награды используют общие правила карточек. Перед выдачей проверяется весь набор предметов и решений игрока. Незавершённый выбор сохраняется для «Продолжить». Лавка повторно сверяет предложение, количество, цену и баланс при выполнении команды. [Карточки наград](../../game/domain/services/reward_items.gd) · [Правила торговли](../../game/domain/services/shop_trade.gd)

Если игрок покинул Печать после отказа записи готовой точки, следующий вход в бой возвращает к фиксации. «Продолжить» сначала завершает запись точки. Если в старом профиле одновременно ожидает добыча, успешная фиксация открывает именно этот результат боя. [Восстановление и проверки](../../game/tests/ui_layout_runner.gd)

## Инструменты графики

- ChatGPT Image Generation — быстрые оригинальные концепты и source candidates по pipeline;
- Aseprite — основной ручной pixel-art, palette, animation и export;
- LibreSprite — бесплатная альтернатива для pixel-art и кадров;
- Krita — крупные фоновые иллюстрации, paint-over и подготовка слоёв;
- ImageMagick/скрипт — пакетная проверка размеров, alpha и nearest resize;
- Godot import — финальная проверка в движке, не замена art review.

## Минимальный набор окружения

Git; Godot 4.x; Aseprite или LibreSprite; Krita по необходимости; ImageMagick или небольшой Python/Pillow script для batch checks; Android SDK/подходящий export template; markdown-документация в репозитории. Атласы собирать средствами Godot до появления доказанной потребности в отдельном packer.

## Риски и проверки

Проверить Android export на реальном устройстве, iOS export на macOS/Xcode до обещания даты, размер текстур и FPS при частицах, сохранение после принудительного закрытия, лицензии шрифтов/плагинов и совместимость generated assets с alpha/grid. Пересмотреть выбор renderer после первого device test.

## Решения, требующие согласования

Финальная перспектива боя, минимальные версии ОС, разрешение и aspect policy, необходимость Aseprite purchase, формат localization и коммерческая лицензия Unity как fallback. Правила Checkpoint согласованы с narrative Bible/Story и реализованы в текущем slice; их числовые тайминги и боевой баланс остаются blockout-гипотезами до playtest.
