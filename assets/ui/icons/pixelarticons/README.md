# UI icons — Pixelarticons

Integrated 2026-11-20 at the user's request to replace oversized text buttons with icons.

- Source: [Iconify icon data](https://github.com/iconify/icon-sets/blob/master/json/pixelarticons.json), collection `pixelarticons`, version **2.4.2** at download.
- Author: [Gerrit Halfmann](https://github.com/halfmage/pixelarticons).
- License: MIT; full notice in [LICENSE.txt](LICENSE.txt), also copied into the runtime directory.
- Selected icons: sword, human-run, backpack, chevron-left, close, info-box, map, bed, trash, chevron-right, heart, shield, coin, reload.
- Changes: wrap original body in a 24×24 SVG; replace `currentColor` with white for Godot modulation; filenames use `lower_snake_case` and `_icon`.
- Source metadata: [source.json](source.json). Runtime copies: `game/art/ui/icons/`. Sources and copies are byte-identical.
- These are sourced vector UI assets, separate from the approved PNG package in `assets/manifest.json`. No new AI-generated art, JavaScript dependency, web view or HTTP request in the game.
- Render at native 24 logical px with nearest filtering. Button touch area is independent of the visible glyph. Optional future symbols are packaged but do not imply a working shop or currency system.
