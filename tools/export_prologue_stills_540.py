"""Одноразовый экспорт still пролога 540x960 из мастеров + обновление манифеста."""

from PIL import Image
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "art_working/prologue_resolution_p2_2026_11_20/exports/540"
SIZE = (540, 960)

MASTERS = {
    "environments/story/haruto_tokyo_evening_story.png":
        "art_working/nar_tokyo_prologue_p1_2026_11_18/nar_01_v02/source/haruto_tokyo_evening_story_v02.png",
    "environments/tokyo_crosswalk_background.png":
        "art_working/tokyo_crosswalk_p0_p1_2026_11_18/env_01/source/tokyo_crosswalk_background_v01.png",
    "environments/story/haruto_crosswalk_alarm_story.png":
        "art_working/nar_tokyo_prologue_p1_2026_11_18/nar_02/source/haruto_crosswalk_alarm_story_v01.png",
    "environments/story/haruto_pushes_yui_story.png":
        "art_working/nar_tokyo_prologue_p1_2026_11_18/nar_03/source/haruto_pushes_yui_story_v01.png",
    "environments/story/briefcase_after_flash_story.png":
        "art_working/nar_tokyo_prologue_p1_2026_11_18/nar_04/source/briefcase_after_flash_story_v01.png",
    "environments/story/mitsuki_first_meeting_story.png":
        "art_working/nar_threshold_to_shop_p1_2026_11_18/nar_05/source/mitsuki_first_meeting_story_v01.png",
    "environments/story/haruto_receives_path_seal_story.png":
        "art_working/nar_threshold_to_shop_p1_2026_11_18/nar_06_v02/source/haruto_receives_path_seal_story_v02.png",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    manifest_path = ROOT / "assets/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    by_path = {e["path"]: e for e in manifest["assets"] if e.get("path") in MASTERS}
    for rel, master in MASTERS.items():
        image = Image.open(ROOT / master).convert("RGB").resize(SIZE, Image.LANCZOS)
        name = Path(rel).stem
        work_png = WORK / f"{name}_540x960.png"
        image.save(work_png)
        data = work_png.read_bytes()
        entry = by_path[rel]
        entry["size"] = list(SIZE)
        entry["sha256"] = sha256(data)
        entry["rgba_sha256"] = sha256(image.convert("RGBA").tobytes())
        entry.setdefault("source", {})["export"] = work_png.relative_to(ROOT).as_posix()
        shutil.copyfile(work_png, ROOT / "assets" / rel)
        print(rel, "->", entry["sha256"][:12])
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("manifest updated")


if __name__ == "__main__":
    main()
