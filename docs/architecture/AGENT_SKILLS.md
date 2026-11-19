# AGENT SKILLS

Agent Skills (формат `SKILL.md`) расширяют возможности AI-агентов проекта — Kimi Code и Codex. Установленные скиллы лежат в `.agents/skills/` в корне репозитория: эта директория является общей кросс-агентной конвенцией и подхватывается обоими инструментами на уровне проекта. Kimi Code дополнительно требует, чтобы корень проекта содержал `.git` (требование выполнено).

Дата установки: 2026-11-17.

## Установленные паки

| Пак | Источник | Лицензия | Скиллов установлено | Комментарий |
|---|---|---|---|---|
| awesome-gamedev-agent-skills | `github.com/gamedev-skills/awesome-gamedev-agent-skills` | MIT | 46 | disciplines (17), genres (9), godot (15), workflows (5) + master-router |
| GodotPrompter | `github.com/jame581/GodotPrompter` | MIT | 43 | курированное подмножество под GDScript-проект |

Итого: **89 скиллов**. Валидация frontmatter (`name`, `description`), коллизии имён и соответствие имён каталогам — без ошибок.

Скопированы не все скиллы исходных паков, а только релевантные проекту:

- Из awesome-gamedev пропущены категории `unity/`, `unreal/`, `web-engines/`, `other-engines/` (bevy, defold, love2d, pygame, roblox) — проект на Godot, эти скиллы давали бы шум при автовыборе.
- Из GodotPrompter пропущены `3d-essentials`, `xr-development`, `dedicated-server`, `web-export`, `web-services`, `csharp-godot`, `csharp-signals`, `multiplayer-*`, `gdextension`, аддон-специфичные (`beehave`, `limboai`, `popochiu`, `phantom-camera`) — за пределами MVP (GDScript, 2D, офлайн, мобильный).

Исходники паков (для обновлений и справки) склонированы в `references/agent-skills-src/`. Это внешний материал исследования: не импортировать в игру, не включать в production assets.

## Ключевые скиллы по задачам проекта

- **Геймдизайн и прогрессия**: `rpg` (статы, XP-кривые, предметы, квесты), `game-docs` (GDD), `godot-brainstorming`, `godot-grill` (уточнение требований перед реализацией), `prototype-fast`.
- **Дизайн уровней 2D**: `level-design` (метрики игрока, гейтинг, паcing), `platformer`, `godot-tilemap`, `2d-essentials`, `procedural-gen` / `procedural-generation`.
- **Бой и AI**: `game-ai`, `ai-behavior-trees-utility-ai`, `ai-navigation`, `state-machine`, `ability-system`, `game-feel` (джус/отзывчивость ударов).
- **Инфраструктура Godot**: `godot-gdscript`, `gdscript-patterns`, `gdscript-advanced`, `godot-nodes-scenes`, `godot-resources` / `resource-pattern`, `godot-signals-groups` / `event-bus`, `godot-physics` / `physics-system`, `godot-animation` / `tween-animation`, `godot-ui` / `godot-ui-control` / `responsive-ui` (портретный mobile UI), `mobile-development`, `godot-export`, `save-systems` / `save-load`, `inventory-system`, `dialogue-system` / `dialogue-systems`.
- **Арт-пайплайн**: `create-game-assets` (генерация и валидация арта, pixel art, тайлсеты), `shader-basics` / `godot-shaders`, `particles-vfx`.
- **Входная точка**: `router` — определяет движок и задачу и направляет к нужному скиллу; полезен, когда неясно, какой скилл применить.

Скиллы ссылаются друг на друга по имени (`godot-tilemap`, `resource-pattern` и т.п.) — плоская раскладка в `.agents/skills/` это поддерживает.

## Правила использования и обновления

1. Скиллы — внешний материал: перед принятием их рекомендаций сверять с `AGENTS.md` и документами `docs/` (art direction, MVP scope). При конфликте приоритет у документов проекта.
2. Обновление паков: `git -C references/agent-skills-src/<пак> pull`, затем повторить копирование изменённых скиллов в `.agents/skills/` и валидацию.
3. Новые собственные скиллы проекта добавлять в `.agents/skills/` по тому же формату (`name`, `description` обязательны).
4. Описания скиллов на английском — это нормально: frontmatter используется моделью для выбора, а не показывается игроку.
