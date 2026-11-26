"""Copy the approved asset subset from assets/ into game/art/ with SHA-256 verification.

Usage: python tools/copy_art.py
Reads assets/manifest.json, copies each listed file byte-for-byte into game/art/,
and fails if a file is missing or its hash differs from the manifest entry.
Idempotent: re-running replaces copies with identical bytes.
"""

import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "assets"
TARGET_DIR = ROOT / "game" / "art"
MANIFEST = SOURCE_DIR / "manifest.json"

ASSET_PATHS: list[str] = [
    # CHR-01 Харуто современный (пролог)
    "characters/haruto_modern_idle.png",
    "characters/animations/haruto_modern_alarm_sheet.png",
    "characters/animations/haruto_modern_push_sheet.png",
    "characters/animations/haruto_modern_run_sheet.png",
    # CHR-03 Харуто после изгнания (мир и бой)
    "characters/haruto_exiled_idle.png",
    "characters/haruto_exiled_sword_idle.png",
    "characters/haruto_exiled_unarmed_idle.png",
    "characters/animations/haruto_exiled_idle_sheet.png",
    "characters/animations/haruto_exiled_branch_attack_sheet.png",
    "characters/animations/haruto_exiled_dodge_sheet.png",
    "characters/animations/haruto_exiled_hit_sheet.png",
    "characters/animations/haruto_exiled_sword_idle_sheet.png",
    "characters/animations/haruto_exiled_sword_attack_sheet.png",
    "characters/animations/haruto_exiled_sword_dodge_sheet.png",
    "characters/animations/haruto_exiled_sword_hit_sheet.png",
    # CHR-04 Мицуки (пролог)
    "characters/mitsuki_threshold_portrait.png",
    "characters/animations/mitsuki_offer_sheet.png",
    "characters/animations/mitsuki_wing_glitch_sheet.png",
    # CHR-15 Юи (пролог)
    "characters/yui_crosswalk_idle.png",
    "characters/animations/yui_crosswalk_wait_sheet.png",
    "characters/animations/yui_crosswalk_step_sheet.png",
    "characters/animations/yui_crosswalk_displaced_sheet.png",
    # MON-01 слизь
    "enemies/moss_slime_idle.png",
    "enemies/animations/moss_slime_idle_sheet.png",
    "enemies/animations/moss_slime_jump_sheet.png",
    "enemies/animations/moss_slime_hit_sheet.png",
    # MON-02 гоблин
    "enemies/goblin_scout_idle.png",
    "enemies/animations/goblin_scout_idle_sheet.png",
    "enemies/animations/goblin_scout_double_slash_sheet.png",
    "enemies/animations/goblin_scout_retreat_sheet.png",
    # CHR-07 Дайдзиро-торговец (лавка и разговоры)
    "characters/daijiro_merchant_idle.png",
    "characters/midori_registrar_idle.png",
    "characters/goro_guildmaster_idle.png",
    "characters/kenta_novice_idle.png",
    # Роща Шелестящих Трав
    "enemies/needle_hound_idle.png",
    "enemies/dust_moth_idle.png",
    "enemies/root_weaver_idle.png",
    "environments/whispering_grass_grove_background.png",
    "equipment/moon_flax_bandage_icon.png",
    "equipment/needle_hound_quills_icon.png",
    "equipment/moth_pollen_jar_icon.png",
    "equipment/grove_route_map_icon.png",
    "environments/props/grove_route_marker_broken_prop.png",
    "environments/props/moon_flax_gatherable_prop.png",
    "environments/story/kenta_root_bridge_story.png",
    "effects/moth_pollen_cloud_01.png",
    "enemies/animations/needle_hound_idle_sheet.png",
    "enemies/animations/needle_hound_quill_shot_sheet.png",
    "enemies/animations/needle_hound_leap_sheet.png",
    "enemies/animations/dust_moth_hover_sheet.png",
    "enemies/animations/dust_moth_pollen_sheet.png",
    "enemies/animations/root_weaver_idle_sheet.png",
    "enemies/animations/root_weaver_grab_sheet.png",
    # Фоны локаций
    "environments/tokyo_crosswalk_background.png",
    "environments/white_threshold_background.png",
    "environments/first_breath_trail_background.png",
    "environments/lioren_south_gate_background.png",
    "environments/props/daijiro_cart_overturned_prop.png",
    "environments/cricket_twilight_interior_background.png",
    "environments/dawn_trail_guild_hall_background.png",
    # NAR-01..06 сюжетные кадры пролога
    "environments/story/haruto_tokyo_evening_story.png",
    "environments/story/haruto_crosswalk_alarm_story.png",
    "environments/story/haruto_pushes_yui_story.png",
    "environments/story/briefcase_after_flash_story.png",
    "environments/story/mitsuki_first_meeting_story.png",
    "environments/story/haruto_receives_path_seal_story.png",
    "environments/story/daijiro_cart_rescue_story.png",
    "environments/story/daijiro_crystal_appraisal_story.png",
    "environments/story/midori_registers_haruto_story.png",
    # OBJ-07/08 реквизит пролога
    "environments/props/haruto_phone_prop.png",
    "environments/props/pedestrian_signal_prop.png",
    "environments/props/tokyo_truck_prop.png",
    "environments/props/yui_whale_backpack_prop.png",
    "environments/props/path_seal_icon.png",
    # Эффекты
    "effects/checkpoint_set_01.png",
    "effects/void_return_overlay_01.png",
    "effects/void_trace_icon.png",
    "effects/inventory_receive_01.png",
    "effects/attack_zone_telegraph_01.png",
    "effects/headlight_flash_overlay.png",
    # UI
    "ui/checkpoint_active_icon.png",
    "ui/checkpoint_inactive_icon.png",
    "ui/checkpoint_spent_icon.png",
    "ui/dialogue_panel_normal.png",
    "ui/icons/settings_gear_steel_icon.png",
    "ui/icons/characters_icon.png",
    "ui/icons/merchant_icon.png",
    "ui/icons/skip_cutscene_icon.png",
    "ui/icons/slot_helmet_icon.png",
    "ui/icons/slot_armor_icon.png",
    "ui/icons/slot_weapon_icon.png",
    "ui/icons/slot_boots_icon.png",
    "ui/icons/slot_shoulders_icon.png",
    "ui/icons/slot_familiar_icon.png",
    "ui/icons/slot_amulet_icon.png",
    "ui/icons/slot_ring_icon.png",
    # Иконки предметов
    "equipment/broken_wanderer_branch_icon.png",
    "equipment/novice_short_sword_icon.png",
    "equipment/moss_core_icon.png",
    "equipment/echo_growth_cloudy_icon.png",
    "equipment/echo_dusk_clear_icon.png",
    "equipment/wanderer_jacket_icon.png",
    "equipment/dawn_trail_guild_badge_icon.png",
    "equipment/astra_copper_icon.png",
    "equipment/astra_silver_icon.png",
    "equipment/astra_gold_icon.png",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    by_path: dict[str, dict] = {}
    for entry in manifest["assets"]:
        if entry.get("status") != "approved":
            continue
        by_path.setdefault(entry["path"], entry)

    failures: list[str] = []
    copied = 0
    for rel_path in ASSET_PATHS:
        entry = by_path.get(rel_path)
        source = SOURCE_DIR / rel_path
        if entry is None:
            failures.append(f"{rel_path}: нет approved-записи в манифесте")
            continue
        if not source.is_file():
            failures.append(f"{rel_path}: исходный файл отсутствует")
            continue
        actual = sha256(source)
        if actual != entry["sha256"]:
            failures.append(f"{rel_path}: sha256 {actual} != манифест {entry['sha256']}")
            continue
        target = TARGET_DIR / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_file() and sha256(target) == actual:
            continue
        shutil.copyfile(source, target)
        copied += 1

    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print(f"OK: {len(ASSET_PATHS)} файлов проверены, {copied} скопировано, "
          f"{len(ASSET_PATHS) - copied} уже совпадали побайтово.")
    catalog = {path: by_path[path]["runtime"] for path in ASSET_PATHS
               if "runtime" in by_path[path]}
    catalog_path = TARGET_DIR / "animation_catalog.json"
    catalog_text = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
    if not catalog_path.exists() or catalog_path.read_text(encoding="utf-8") != catalog_text:
        catalog_path.write_text(catalog_text, encoding="utf-8")
    print(f"OK: {len(catalog)} source-resolution animation contracts generated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
