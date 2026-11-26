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

- **Scenes:** persistent `GameRoot` с `Title`, `Prologue`, `World`, `Combat`, `Inventory`, `Checkpoint`; маршрутизация через `SceneRouter`. (Reward-экран удалён в итерации 2026-11-20; результат боя — состояние сцены `Combat`.)
- **Domains:** `GameSession`, `CharacterState`, `CombatResolver`, `LootGenerator`, `InventoryService`, `CheckpointService`, `SaveService`, `DialogueRunner`.
- **Data:** `Resource` для authoring в Godot; сериализуемый save DTO для прогресса; item/enemy definitions отдельно от runtime state.
- **UI:** `Control` scenes с anchors/safe area; UI подписывается на состояние, а не меняет доменные правила напрямую.
- **Input:** abstract actions (`primary`, `secondary`, `inventory`, `checkpoint`) с touch mapping; keyboard mapping только для desktop smoke test.
- **Rendering:** nearest filter, integer scaling, portrait base viewport, performance budget на старом Android.
- **Save** хранит локальный профиль v7 в `user://` с миграциями v0–v6 и резервной копией. Награда остаётся в корневом `pending_battle_result` до успешной записи. Один результат относится ко всей встрече. Вехи Рощи, Синего Оврага и Края Ветров входят в снимок Печати. Эхо и память о репликах хранятся в `meta`. [Границы записи Рощи](../reviews/grove_stage_2026_11_22/README.md#маршрут-сохранение-и-баланс) · [Команды Оврага](../design/MVP_BLUE_HOLLOW.md#состояние-и-запись) · [Состояние поста](../design/MVP_WINDS_EDGE.md#состояние-и-запись)
- **Networking:** отсутствует в MVP; не добавлять multiplayer SDK или серверный backend.

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
