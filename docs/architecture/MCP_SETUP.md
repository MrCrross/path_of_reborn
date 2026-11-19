# MCP SETUP

## Цель

Локальные MCP-серверы нужны для ускорения работы с установленными Godot, Blender и Krita. Они не являются частью runtime игры и не должны попадать в production build.

## Установленные компоненты

| Инструмент | Компонент | Версия/источник | Состояние |
|---|---|---|---|
| Godot | `godot-mcp` Windows server + Godot add-on | `zeegzoog/godot-mcp`, release `v0.14.0`, Godot `4.7` | работает: сервер `%LOCALAPPDATA%\PathOfRebornMcp\godot\godot-mcp.exe`, add-on включён в `game/project.godot` |
| Blender | Blender Lab MCP | `blender.org/lab/mcp-server`, исходник в `.mcp-servers/blender_mcp/` | работает: launcher `%LOCALAPPDATA%\PathOfRebornMcp\blender\Scripts\blender-mcp.exe`, add-on установлен в Blender 5.3 (`scripts/addons/mcp/`), включён с Auto Start, в системных настройках Blender включён Network Access (`use_online_access`) — без него аддон молча не стартует |
| Krita | Krita Codex MCP | PyPI `krita-codex-mcp==0.2.2` | работает: launcher `%LOCALAPPDATA%\PathOfRebornMcp\krita\Scripts\krita-codex-mcp.exe`, bridge `kritacodexbridge` установлен в профиле Krita, конфиг `.mcp-local/krita-config.json` |

Дата проверки: 2026-11-17.

## Конфигурация агентов

Оба агента используют одни и те же серверы; конфиги глобальные (не коммитятся):

- **Codex**: `%USERPROFILE%\.codex\config.toml`, секции `[mcp_servers.godot|blender|krita]`.
- **Kimi Code**: `%USERPROFILE%\.kimi-code\mcp.json`, ключи `mcpServers.godot/blender/krita` (зеркально Codex).

Добавленные серверы подхватываются только в **новых** сессиях; в Kimi Code статус смотрится через `/mcp`.

## Локальные пути

- Godot MCP server: `%LOCALAPPDATA%\PathOfRebornMcp\godot\godot-mcp.exe`, обёртка `run-godot-mcp.cmd` (cwd = `game/`).
- Blender MCP environment: `%LOCALAPPDATA%\PathOfRebornMcp\blender\` (venv, launcher в `Scripts\`).
- Krita MCP environment: `%LOCALAPPDATA%\PathOfRebornMcp\krita\` (venv, launcher в `Scripts\`).
- Blender MCP source: `.mcp-servers/blender_mcp/` в рабочей копии; не включать в production assets.

## Ограничения и порядок проверки

1. MCP-серверы выполняют локальные команды или код в редакторах. Использовать их только для этого проекта и открытых сцен/ассетов.
2. Godot add-on должен соответствовать minor-версии Godot; установлен Godot `4.7.2`, поэтому используется addon `godot4.7`.
3. Blender MCP предупреждает, что вызовы могут исполнять Python в Blender. Не открывать через него чувствительные файлы. Работает только при запущенном Blender с включённым аддоном «MCP» (порт 9876, loopback). Аддон стартует автоматически (Auto Start в настройках аддона); если соединения нет — проверить, что в Edit → Preferences → System → Network Access включён доступ (аддон без него молча отказывается стартовать).
4. Krita bridge работает только после включения **Krita Codex Bridge** в Python Plugin Manager и перезапуска Krita; проверка — `krita-codex-install check`.
5. Godot MCP требует открытый редактор Godot с проектом `game/`; bridge поднимается аддоном автоматически.

## Следующая проверка

Открыть `game/` в Godot, убедиться, что аддон загружен (без ошибок в консоли), и проверить переходы `title → prologue → world`. Затем запустить Krita, включить bridge и выполнить `krita-codex-install check`. Blender проверять на пустой сцене через add-on и loopback-only соединение. В новой сессии Kimi Code выполнить `/mcp` — все три сервера должны быть подключены.
