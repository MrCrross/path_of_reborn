class_name DebugFlags
extends RefCounted

## Явное включение отладочного UI. Включается только флагом `--debug-ui`
## в user args (см. game_root.gd); OS.is_debug_build() сам по себе недостаточен.

static var ui_enabled: bool = false
