# Приёмка регистрации в Гильдии · 22 ноября 2026

После рекомендации Дайдзиро в Лиорене доступна Гильдия. Сцена использует прежнее диалоговое окно и 25 реплик с каноническими идентификаторами. Общие планы зала и крупный план Мидори собраны из утверждённых мастеров. После повторного просмотра Горо, Дайдзиро и Кэнта увеличены ещё примерно в полтора раза в базовом кадре. Головы посетителей заметно выше столешницы, а силуэты целиком видны над панелью. [План этапа](../../design/MVP_GUILD_REGISTRATION_PLAN.md)

В Лиорене скрыта полоса экипировки. Нижняя кнопка «Сумка» открывает инвентарь. На Тропе полоса снова видна.

## Кадры

| Лиорен | Зал Гильдии | Совет Горо | Проверка Печати | Первое задание |
| --- | --- | --- | --- | --- |
| [360×640](guild_city_360x640.png) | [360×800](guild_opening_360x800.png) | [360×640](guild_mentor_360x640.png) | [390×844](guild_register_dialogue_390x844.png) | [360×640](guild_order_360x640.png) |

## Проверки

- Оконный прогон Godot 4.7.2 на Windows прошёл 226 проверок и сохранил 24 кадра в окнах 360×640, 360×800, 390×844 и 412×915. К прежним проверкам маршрута добавлены измерения видимой высоты спрайтов и их границ над диалогом. Отдельно просмотрены общие планы Кэнты и Горо. Сохранения изолированы от игрового профиля.
- Headless-прогоны прошли 95 игровых тестов, 1675 проверок компоновки и 367 проверок анимации.
- Сверены 87 игровых копий арта с манифестом. ZIP ресурсов Android-пресета содержит сцену, JSON реплик и все шесть добавленных текстур с данными импорта. Установка на Android и playtest остаются открыты.

Команды выполняются из корня проекта. `godot` должен быть в `PATH`.

```powershell
python tools/copy_art.py
godot --headless --path game --editor --import
godot --path game --script res://tests/first_session_acceptance_runner.gd --fixed-fps 60 -- --acceptance-mode=guild
godot --headless --path game --script res://tests/test_runner.gd
godot --headless --path game --script res://tests/ui_layout_runner.gd
godot --headless --path game --script res://tests/animation_assets_runner.gd
$packPath = Join-Path (Get-Location) 'game/.godot/guild_android_data.zip'
godot --headless --path game --export-pack Android $packPath
```

Оконный тест создаёт отдельный профиль в `user://path_of_reborn_tests/` и сохраняет кадры и отчёт в `game/.godot/guild_acceptance/`.
