# Аудит проектных скиллов — 2026-11-20

Активный набор сокращён **с 91 до 43 скиллов**: сохранены 40, архивирован 51,
добавлен один внешний и две проектные инструкции. Общий размер `SKILL.md` уменьшился
с 1 028 180 до 462 812 байт, на 55%. Это объём файлов инструкций, **не измерение
экономии токенов**: агент загружает тело скилла только при его выборе.

Область работы — `.agents/skills/` этого проекта. Глобальные скиллы и плагины Codex,
другие проекты, игровой код, ассеты, `models/` и `plans/` не изменялись. Существующий
мобильный UX/UI-раздел `AGENT_SKILLS.md` сохранён. Перед работой в checkout уже были
незакоммиченные изменения игры и документации; они не откатывались.

## Основания для отбора

Изучены локальные entrypoint-инструкции, состав references/scripts, документы стека,
MVP и арта, актуальные решения по интерфейсу и контракты текущей реализации.
Godot MCP сообщил **4.7.2-stable (steam)** из подключённого редактора.

Критерии: офлайн RPG на GDScript, 2D pixel art, portrait Android с последующей iOS,
сцены встреч и автобой, небольшое число осмысленных действий, существующие доменные
сервисы и тесты. Для API оставлен один основной маршрут на тему; отдельные скиллы
дизайна и реализации могут дополнять друг друга.

Истории вызовов скиллов нет. Поэтому «не нужен сейчас» означает отсутствие задачи
в текущем scope/реализации, а не доказанный ноль вызовов. Скиллы резерва можно вернуть
при появлении соответствующей задачи. Сохранённые `ability-system`, `inventory-system`
и `state-machine` — справочники для новых/перестраиваемых систем; их наличие не требует
переписывать работающую реализацию. `godot-tilemap` нужен только при работе с тайлами.

## Что действительно устарело

**Ни один из четырёх исходных паков целиком не признан устаревшим.** GitHub API
проверен 2026-11-20: HEAD основных веток совпадает с ревизиями локальных источников.
Ревизии приведены в [каталоге скиллов](AGENT_SKILLS.md). Дата проверки относится
к доступным на этот момент данным GitHub, а не к обещанию будущей совместимости.

- [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)
  содержит Godot 4.7 API и геймдизайн; выбранные части актуальны.
- [GodotPrompter](https://github.com/jame581/GodotPrompter) поддерживается и включает
  заметки о 4.8. Надпись «4.3+» у отдельных тем не означает, что API удалён.
- [mobile-design](https://github.com/RubenGlez/mobile-design) актуален для touch UX;
  его нативные паттерны применяются с учётом игровой композиции.
- [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) актуален как
  поисковый справочник; поддержки Godot `--stack` нет. Web-рецепты не переносятся в игру.

Исправлены конкретные неподходящие рекомендации и маршруты:

| Проблема | Изменение |
|---|---|
| `responsive-ui/references/mobile.md` переносил экранные safe-area insets прямо в логические поля контейнера | Рецепт заменён указанием использовать существующий `SafeArea.margins_for` с обратным screen transform |
| DPI-рецепт `dpi / 96` и дробные шаги 0.25 предлагались как общая настройка | Исключён из checklist проекта; пример помечен неприменимым к текущей integer-сетке |
| Общие рекомендации 1920×1080, `viewport`/`expand` могли заменить текущий layout | Сохранены фактические 180×320, `canvas_items`, integer и текущая aspect policy; portrait-проверки перечислены явно |
| 44 px могли восприниматься как 44 логических пикселя Godot | Требуется проверка физических touch targets, без смешивания dp/pt и logical pixels |
| `level-design` начинал с измерения прыжка и геометрии | Добавлен маршрут для главы: встречи, обучение, награды, отдых, Checkpoint и проверка достижимости |
| `rpg` мог навязать другую damage formula и типовые pacing numbers | Текущая формула сохраняется; численные примеры обозначены гипотезами, симуляция вызывает домен игры |
| Checklist scene organization навязывал EventBus, лимит ~15 узлов и имена из двух слов | Границы сцен выбираются по ответственности; используются существующие сигналы и владелец состояния |
| Ссылки вели на архивированные дубли и общий multi-engine router | Эквивалентные маршруты перенаправлены на выбранные скиллы; router заменён каталогом проекта |
| Мобильный checklist мог расширить MVP PiP/IAP/permissions или 4.8 migration | Разделы явно условные; текущий офлайн GDScript MVP и установленная версия имеют приоритет |

Основание для исправления координат: [Viewport.get_screen_transform, Godot 4.7](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-method-get-screen-transform).
Integer scaling применим с разными stretch modes; менять `canvas_items` только из-за
слова pixel art не требуется: [Multiple resolutions, Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html).
Платформенные touch-рекомендации имеют собственные единицы:
[Android accessibility](https://developer.android.com/guide/topics/ui/accessibility/apps#touch-targets),
[Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
Соблюдение этих требований на устройстве этим аудитом не подтверждалось.

## Найденные дополнения

| Кандидат | Решение и причина |
|---|---|
| [headless-game-balance](https://github.com/nitzangames/headless-game-balance) | Установлен commit `0b0a759c5ad446d5d677da52721d2ce6203b503d`, MIT. Закрывает пробел воспроизводимого баланса: те же игровые правила, политики и seeds, сравнение результатов. Прочитаны инструкция, simulation contract, Python summarizer и лицензия |
| [GameForge game-balance-check](https://github.com/AlterLab-IEU/AlterLab_GameForge/blob/main/skills/workflows/game-balance-check/SKILL.md) | Найден как альтернативный кандидат, не установлен. Для текущей задачи предпочли меньший самостоятельный balance skill; весь studio framework не нужен. Полный пакет не проходил проверку |
| [GD-Agentic-Skills godot-platform-mobile](https://github.com/thedivergentai/GD-Agentic-Skills/blob/main/skills/godot-platform-mobile/SKILL.md) | Найден для будущих платформенных задач, не установлен. Текущие export/lifecycle/touch покрыты выбранными скиллами; дополнительный набор API-шаблонов сейчас дублировал бы их. Не утверждается, что кандидат полностью проверен |

Два коротких собственных скилла закрывают проектные ограничения, которых нет в общем паке:

- `por-mobile-combat-ux` — сценическая композиция, HP у актёров, автобой, телеграфы,
  лёгкая победная надпись, осмысленные действия с предметами и Checkpoint; проверка
  portrait-состояний без добавления постоянных панелей и лишних подтверждений.
- `por-godot-architecture-api` — владельцы GameRoot/GameSession и доменные контракты,
  точечное расширение готовых сервисов, документация нужной версии, MCP и проверки API.

Проектная поправка к `headless-game-balance` требует использовать настоящий
`CombatResolver.advance_ticks`, session/loot/Checkpoint, фиксировать версии политик
и сравнивать одинаковые seeds. Python summarizer проверен, но сам симулятор игры
в этой задаче не создавался. Его агрегатор не разделяет политики и версии автоматически:
подавать отдельные JSONL cohorts; интервалы и paired differences считать отдельно.

## Практический набор по направлениям

| Направление | Выбранный маршрут |
|---|---|
| UX/UI и компактный бой | `por-mobile-combat-ux` → `game-ui-ux` → `godot-ui-control`; `responsive-ui`, `mobile-design` по задаче |
| Красивое и читаемое представление | `create-game-assets`, `godot-animation`, `game-feel`; `particles-vfx` и shaders после проверки Compatibility и нагрузки |
| Геймдизайн | `rpg`, `game-docs`, `game-ai`; решения и гипотезы остаются в документах проекта |
| Уровни первой главы | `level-design`: порядок встреч, обучение, риск/награда, отдых/Checkpoint; `godot-tilemap` для реальных tile-задач |
| Баланс | `rpg` + `headless-game-balance`: время боя в ticks, HP, окна уклонения, награды и цена возврата; затем playtest |
| Архитектура | `por-godot-architecture-api`, `scene-organization`, `godot-resources`, `godot-signals-groups` |
| Godot API | `godot-gdscript`, `godot-nodes-scenes`, тематический API-скилл; проверка через MCP и документацию 4.7 |
| Android/iOS | `mobile-development`, `godot-export`, `performance-optimization`; реальные Android/iOS проверки отдельно |

Для API не установлен дополнительный сервер: доступны Godot MCP и Context7.
Проверены чтение версии редактора и запрос документации Context7 для ветки 4.7.
Для последующих задач полезны `godot_code_complete`, `godot_code_definition`,
`godot_code_diagnostics`, `godot_validate_script`, `godot_run_script`, runtime snapshot
и screenshot. Выбирать фактически доступный инструмент, а не выдуманное имя API.

## Проверки и ограничения

- Все **43/43** активных скилла прошли штатный `quick_validate.py`: frontmatter,
  обязательные поля, имена. Встроенному Python не хватало PyYAML; использована уже
  установленная библиотека из окружения Blender MCP, новых зависимостей нет.
- Относительные навигационные Markdown-ссылки проверены; битых не найдено.
  Кодовые примеры и ссылки-шаблоны будущих документов исключены из этой проверки.
- `ui-ux-pro-max`: поиск `touch target spacing --domain ux -n 3` возвращает результаты.
- `headless-game-balance`: `--help`, валидная выборка из трёх прогонов с двумя победами,
  отклонение неправильного типа `won` с кодом 2 — успешно.
- ZIP прошёл CRC-проверку; **400 исходных файлов** проверены по SHA-256.
- Проверены границы трёх проектных сценариев чтением инструкций: UI не меняет stretch,
  архитектура не добавляет дублирующий state owner, баланс не реализует вторую формулу.
  Это проверка инструкций, не независимый behavioral benchmark агентов.
- Игра не менялась, игровые тесты и мобильные сборки не запускались. Примеры всех
  upstream references не компилировались и не объявляются полностью проверенными.

## Восстановление и сопровождение

Архив всех исходных 91 скиллов:
`.agents/skill-archives/2026-11-20/before_cleanup.zip`.
Рядом `file_hashes.json`; SHA-256 самого архива указан в
[поимённом JSON-реестре](SKILL_AUDIT_2026_11_20.json).

Для возврата распаковать архив в отдельный рабочий каталог, выбрать нужный скилл,
сверить хэши и перенести только его в `.agents/skills/`. Полное восстановление поверх
активного набора отменит локальные исправления. Исходные MIT-лицензии сохранены.
Архив и рабочие исходники исключены из Git; для другого компьютера их нужно перенести
отдельно. Это локальная обратимость, а не удалённый backup.

При обновлении паков смотреть diff и сохранять `UPSTREAM.json`/проектные поправки.
Резерв возвращается под конкретную новую задачу: свободное движение, физика, процедурные
карты, editor plugins или новая платформа. Не устанавливать целиком несколько перекрывающихся
паков. Переход на Godot 4.8 и окончательные численные цели баланса не входят в эту чистку.

## Поимённые решения

Списки ниже сформированы из JSON-реестра. «Дубль» означает пересечение основного
маршрута текущего проекта, а не полную эквивалентность всего содержимого.

### Сохранены: 40

`2d-essentials`, `ability-system`, `assets-pipeline`, `audio-design`, `create-game-assets`, `dialogue-systems`, `game-ai`, `game-docs`, `game-feel`, `game-ui-ux`, `gdscript-patterns`, `godot-animation`, `godot-audio`, `godot-code-review`, `godot-debugging`, `godot-export`, `godot-gdscript`, `godot-gdscript-headless-testing`, `godot-nodes-scenes`, `godot-resources`, `godot-shaders`, `godot-signals-groups`, `godot-tilemap`, `godot-ui-control`, `input-handling`, `inventory-system`, `level-design`, `localization`, `mobile-design`, `mobile-development`, `particles-vfx`, `performance-optimization`, `rendering-pipeline`, `responsive-ui`, `rpg`, `save-systems`, `scene-organization`, `state-machine`, `tween-animation`, `ui-ux-pro-max`.

### Архивированы как дубли: 16

| Скилл | Причина / выбранный маршрут |
|---|---|
| `animation-system` | Основной маршрут: godot-animation |
| `audio-system` | Основной маршрут: godot-audio |
| `component-system` | Основной маршрут: scene-organization |
| `dialogue-system` | Основной маршрут: dialogue-systems |
| `event-bus` | Основной маршрут: godot-signals-groups |
| `godot-brainstorming` | Основной маршрут: por-godot-architecture-api |
| `godot-optimization` | Основной маршрут: performance-optimization |
| `godot-ui` | Основной маршрут: godot-ui-control |
| `hud-system` | Основной маршрут: game-ui-ux + godot-ui-control |
| `input-systems` | Основной маршрут: input-handling |
| `resource-pattern` | Основной маршрут: godot-resources |
| `router` | Основной маршрут: docs/architecture/AGENT_SKILLS.md |
| `save-load` | Основной маршрут: save-systems |
| `shader-basics` | Основной маршрут: godot-shaders |
| `shader-programming` | Основной маршрут: godot-shaders |
| `using-godot-prompter` | Основной маршрут: docs/architecture/AGENT_SKILLS.md |

### Архивированы вне MVP: 14

| Скилл | Причина / выбранный маршрут |
|---|---|
| `card-game` | Другой жанр/стек/платформа или задача вне MVP. |
| `fps-shooter` | Другой жанр/стек/платформа или задача вне MVP. |
| `game-jam` | Другой жанр/стек/платформа или задача вне MVP. |
| `godot-3d-essentials` | Другой жанр/стек/платформа или задача вне MVP. |
| `godot-csharp` | Другой жанр/стек/платформа или задача вне MVP. |
| `godot-multiplayer` | Другой жанр/стек/платформа или задача вне MVP. |
| `itch-publish` | Другой жанр/стек/платформа или задача вне MVP. |
| `platformer` | Другой жанр/стек/платформа или задача вне MVP. |
| `procedural-generation` | Другой жанр/стек/платформа или задача вне MVP. |
| `puzzle` | Другой жанр/стек/платформа или задача вне MVP. |
| `roguelike` | Другой жанр/стек/платформа или задача вне MVP. |
| `steam-publish` | Другой жанр/стек/платформа или задача вне MVP. |
| `survival-crafting` | Другой жанр/стек/платформа или задача вне MVP. |
| `tower-defense` | Другой жанр/стек/платформа или задача вне MVP. |

### Архивированы в резерв: 21

| Скилл | Причина / выбранный маршрут |
|---|---|
| `addon-development` | Нет задачи editor plugin; MCP уже установлен. |
| `ai-behavior-trees-utility-ai` | Текущий бой использует фазы CombatResolver, BT/utility не требуется. |
| `ai-navigation` | В текущем slice нет свободного перемещения и NavigationAgent. |
| `camera-system` | В текущем slice постановка сцены, свободная камера не нужна. |
| `camera-systems` | В текущем slice постановка сцены, свободная камера не нужна. |
| `dialogue-manager` | Аддон Dialogue Manager не установлен; есть собственный DialogueRunner. |
| `gdscript-advanced` | Нет задачи metaprogramming/@tool; базовые API покрыты активными скиллами. |
| `godot-2d-movement` | В текущем slice нет физического контроллера перемещения. |
| `godot-grill` | Отдельный режим интервью сейчас не нужен; уточнения остаются по необходимости. |
| `godot-mentor` | Обучающий режим не запрошен. |
| `godot-physics` | Текущий бой на integer ticks, без физической симуляции столкновений. |
| `godot-project-setup` | Проект уже создан; повторный scaffold не нужен. |
| `godot-testing` | Уже есть SceneTree test runner; GUT/gdUnit4 не установлены. |
| `math-essentials` | Общий математический справочник не закрывает отдельную текущую задачу. |
| `multithreading` | Нет измеренной потребности выносить работу в потоки. |
| `physics-system` | Текущий бой на integer ticks, без физической симуляции столкновений. |
| `physics-tuning` | Нет физического контроллера, CCD/solver tuning не нужны. |
| `player-controller` | В текущем slice нет физического контроллера перемещения. |
| `procedural-gen` | Seeded loot уже реализован; генерация уровней вне MVP. |
| `prototype-fast` | Есть рабочий vertical slice; throwaway-прототип не запрошен. |
| `visual-novel` | Есть линейный пролог и DialogueRunner; отдельный VN framework не нужен. |
