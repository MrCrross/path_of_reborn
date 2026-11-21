# Исходная регрессия A01–A05 — 2026-11-20

Рабочее дерево уже содержало изменения предыдущих итераций; они сохранены. Новые доказательства записываются отдельно от `docs/reviews/plan_acceptance_2026_11_20/`.

Команды выполнялись через Godot MCP с проектом `game/`, Godot 4.7.2 и `--fixed-fps 60`:

- `res://tests/test_runner.gd` до новых регрессий: 65 passed, 0 failed, 0 unfinished, stderr пуст.
- `res://tests/ui_layout_runner.gd` до новых регрессий: 837 checks, 0 failed, stderr пуст.
- `res://tests/iteration_acceptance_probe.gd`: диагностические наблюдения подтверждены; три `SCRIPT ERROR` в `SaveService._valid_profile`.

Наблюдения probe до исправления:

- A01: после блокировки `.tmp` экран `World`; память — 1 предмет, pending пуст; диск — 0 предметов, pending сохранён.
- A02: настоящая форма v2 со старыми вложенными Checkpoint-снимками мигрирует в v3, но не валидируется; обращение к отсутствующему `pending_battle_result` вызывает `SCRIPT ERROR`.
- A03: reentrant claim из `inventory.changed` принят внутри и снаружи, выдано 2 единицы вместо 1. Старый `run_000001` после retry создаёт pending и сбрасывает `in_combat`, пока `run_000002` ещё активен.
- A06: контакты героя на тиках 19/79; на 79 атакующий клип уже не показан. Удары гоблина — 48/66.
- A10: первый claim даёт +2; после rollback повторный claim даёт ещё +1.

После добавления регрессий, ещё до исправления production-кода:

- `test_runner.gd`: 65 passed, 8 failed, 0 unfinished. Красные наборы: stale resolver, reentrant claim, incompatible commands, route context, trial rollback, real v0/v1/v2 nested snapshots, v3 source policy, pending contradictions.
- `ui_layout_runner.gd`: 857 checks, 11 failed. Красные проверки: failed claim commit/rollback/publication, swipe, canceled, второй палец, focus loss, текущий active/auto mode и скрытие режима на победе.

Эти красные результаты являются исходной точкой; итоговые прогоны записываются отдельно и не заменяют этот файл.
