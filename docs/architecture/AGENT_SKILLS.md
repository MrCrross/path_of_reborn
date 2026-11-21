# AGENT SKILLS

Проектные скиллы Kimi Code и Codex лежат в `.agents/skills/`. После чистки **2026-11-20**
активны **43 скилла**: 40 сохранены из прежних 91, один внешний добавлен, два написаны
для проекта. 51 убран из активного каталога с проверенным ZIP-бэкапом. Глобальные скиллы
Codex, служебные скиллы и плагины других проектов не менялись.

Полный разбор: [SKILL_AUDIT_2026_11_20.md](SKILL_AUDIT_2026_11_20.md).
Поимённый реестр решений, исходных SHA-256 и источников: [JSON](SKILL_AUDIT_2026_11_20.json).
Наличие скилла не означает, что он загружается целиком на каждую задачу: выбирать нужные
инструкции и затем только нужные references. Истории вызовов нет; «резерв» означает
отсутствие текущей задачи в scope/коде, а не доказательство, что скилл никогда не вызывался.

## Выбор по задаче

| Задача | Основные скиллы | Дополнение по необходимости |
|---|---|---|
| Компактный мир/бой, автобой, победа, Checkpoint | `por-mobile-combat-ux`, `game-ui-ux` | `game-feel`, `mobile-design` |
| Реализация UI в Godot | `godot-ui-control`, `responsive-ui` | `input-handling`, `localization`, `tween-animation` |
| Мобильные UX, touch, состояния | `mobile-design` | `ui-ux-pro-max` — только точечный поиск |
| Геймдизайн, статы, предметы, прогрессия | `rpg`, `game-docs` | `game-ai`, `ability-system` для новой системы |
| Проверка баланса боя и наград | `headless-game-balance`, `rpg` | существующий `CombatResolver`, seeded loot, headless runner |
| Первая глава, встречи, обучение, темп | `level-design` | `godot-tilemap` только при работе с тайлами |
| Архитектура и проверка API | `por-godot-architecture-api` | `scene-organization`, `godot-nodes-scenes`, `godot-resources`, `godot-signals-groups`, `state-machine` |
| GDScript, ошибки, ревью | `godot-gdscript`, `gdscript-patterns` | `godot-debugging`, `godot-code-review` |
| Проверки без GUI | `godot-gdscript-headless-testing` | существующие `tests/test_runner.gd`, `tests/ui_layout_runner.gd` |
| Инвентарь, диалог, сохранения | `inventory-system`, `dialogue-systems`, `save-systems` | сначала читать текущие сервисы; не строить их заново |
| Pixel art, анимация, эффекты | `create-game-assets`, `assets-pipeline`, `godot-animation` | `2d-essentials`, `godot-shaders`, `particles-vfx` |
| Звук | `godot-audio` | `audio-design` |
| Производительность, Android/iOS | `performance-optimization`, `mobile-development`, `godot-export` | `rendering-pipeline` |

Скиллы не заменяют `AGENTS.md`, решения в `docs/` и существующий код. Работа внутри
готовой системы начинается с её реализации. Примеры новых систем не являются поручением
заменить `GameSession`, `CombatResolver`, `InventoryService`, `DialogueRunner` или `SaveService`.

## Источники и актуальность

Исходная установка: 2026-11-17; два мобильных UX/UI-скилла: 2026-11-19.
На 2026-11-20 удалённые HEAD совпадают с установленными исходниками:

| Пак | Ветка / зафиксированная ревизия | Состояние |
|---|---|---|
| [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | main / `c6ca6c41c839b68319ffc08430b99ab768debc32` | актуален, сохранена нужная часть; MIT |
| [GodotPrompter](https://github.com/jame581/GodotPrompter) | master / `426e8ab597473d1c71a11a04f6f0f2e1182a8e39` | актуален, локальные поправки к проекту; MIT |
| [mobile-design](https://github.com/RubenGlez/mobile-design) | main / `9d220f76b21e83ae9a48f0adaf64842d08fac56e` | актуален; MIT |
| [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | main / `2de1134dc4d1cfe112934611ae5803ae17a1bd7e` | актуален; справочник без Godot stack; MIT |
| [headless-game-balance](https://github.com/nitzangames/headless-game-balance) | main / `0b0a759c5ad446d5d677da52721d2ce6203b503d` | добавлен 2026-11-20; MIT |

Исходники сохраняются в `references/agent-skills-src/`. Два первых пака — Git-клоны;
mobile-design, ui-ux-pro-max и headless-game-balance загружены `skill-installer` по commit.
Для каждого активного внешнего скилла есть `UPSTREAM.json`; сохранять локальные поправки
при обновлении. Не копировать автоматически весь пакет поверх курированного набора.

## Обновление, инструменты и восстановление

- Проверять новую ревизию, релевантный diff и лицензию; затем обновлять выбранные скиллы,
  повторно накладывать локальные изменения и проверять frontmatter, ссылки и нужные скрипты.
  Надпись «Godot 4.3+» сама по себе не означает устаревание; 4.8 migration notes не требуют
  обновлять установленный Godot 4.7.2.
- Для Godot API уже доступны MCP Godot и Context7. Список подходящих инструментов и порядок
  проверки находятся в `por-godot-architecture-api` и [MCP_SETUP.md](MCP_SETUP.md).
  Предпочитать документацию установленной minor-версии, не плавающую `/latest/`.
- До чистки сохранены все 91 каталога и проверены SHA-256 каждого файла:
  `.agents/skill-archives/2026-11-20/before_cleanup.zip`, рядом `file_hashes.json`.
  ZIP не обнаруживается как активный скилл. Для возврата распаковать в отдельный рабочий
  каталог, сверить SHA-256 выбранного скилла и скопировать только его в `.agents/skills/`.
  Не разворачивать весь архив поверх текущего набора — это вернёт дубли и старые рецепты.
- `.agents/`, `references/agent-skills-src/` и `art_working/` исключены из Git; реестр и
  объяснения в `docs/architecture/` отслеживаются. Локальный архив не является удалённой
  резервной копией. Изменения набора будут доступны для выбора со следующего хода Codex.

## Мобильный UX/UI: набор и ограничения

Основная связка для портретного интерфейса: `game-ui-ux` (игровой UX и переходы), `godot-ui-control` (реализация в Godot), `responsive-ui` (пропорции и масштабирование). По задаче подключать `input-handling`, `localization`, `hud-system` и `game-feel`.

- `mobile-design`: применять для зон досягаемости, навигации, жестов, понятных состояний и аудита экранов. Общие рекомендации для нативных приложений не заменяют утверждённую игровую композицию и art direction.
- `ui-ux-pro-max`: применять как дополнительный справочник по конкретным вопросам контраста, текста, обратной связи и взаимодействия. В списке `--stack` нет Godot: использовать `--domain`, а реализацию сверять с Godot-скиллами. Автоматическая генерация новой дизайн-системы не требуется для исправления существующего UI.
- Сохранять pixel art, `nearest`, integer scaling и решения из `AGENTS.md`/`docs/`. Размеры в pt/dp/CSS px нельзя напрямую переносить в logical pixels Godot: проверять физические зоны касания и читаемость на целевом portrait viewport и устройстве.
- Подключать только нужные разделы; установка скиллов не расширяет MVP сетевыми функциями, монетизацией или системными интеграциями.

### Источники и локальная адаптация

Установлены фиксированные ревизии:

| Скилл | Commit | Исходный путь |
|---|---|---|
| mobile-design | `9d220f76b21e83ae9a48f0adaf64842d08fac56e` | `SKILL.md` + `references/` + `LICENSE` |
| ui-ux-pro-max | `2de1134dc4d1cfe112934611ae5803ae17a1bd7e` | `.claude/skills/ui-ux-pro-max/` + корневой `LICENSE` |

Исходные материалы сохранены в `references/agent-skills-src/mobile-design/` и `references/agent-skills-src/ui-ux-pro-max/`. Они загружены через `skill-installer`, а не клонированы; для обновления нужно повторно загрузить выбранную ревизию. В установленные каталоги скопированы инструкции, references, лицензии и необходимые данные/скрипты; репозиторная автоматизация, чужие release-инструкции и Python-тесты не устанавливались.

В оба `SKILL.md` добавлен блок ограничений проекта. В `ui-ux-pro-max` пути `${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max` заменены на `<skill-dir>`: подставлять абсолютный путь к установленному каталогу `.agents/skills/ui-ux-pro-max`. Поисковый скрипт и данные оставлены без изменений. В каждом каталоге есть `UPSTREAM.json` с источником, commit и перечнем локальных изменений; сохранять эти изменения при обновлении.

Пример из корня проекта в PowerShell (только поиск, без записи дизайн-системы):

```powershell
python -B './.agents/skills/ui-ux-pro-max/scripts/search.py' 'touch target spacing' --domain ux -n 3
```

Нужен Python 3 без внешних пакетов. Если `python` указывает на WindowsApps alias, подставить путь к рабочему интерпретатору. В Codex его можно найти через `load_workspace_dependencies`. Каталоги `.agents/` и `references/agent-skills-src/` исключены из Git.
