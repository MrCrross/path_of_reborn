# Опорная лесная сцена — 2026-11-20

Продолжение по пожеланию пользователя: [проверено использование полноразмерных оригиналов без разрушительного уменьшения](SOURCE_RESOLUTION_REVIEW_2026_11_20.md). Ниже сохранён предыдущий сравнительный тест строгой сетки; это не требование уменьшать все будущие ассеты до такого профиля.

Выполнен первый этап [промпта улучшения ассетов](CHATGPT_ASSET_UPGRADE_PROMPT.md): одна новая лесная композиция без UI, одна точечная правка пиксельной линии героя и технические preview. Исходники обеих версий — 941×1672; кандидат — 360×640, 95 цветов, строгие блоки 2×2. Генерация: встроенный image_gen; модель/seed не сообщены.

![Кандидат лесной сцены](../../art_working/visual_upgrade_2026_11_20/forest_visual_target/previews/candidate_native_360x640.png)

- [Цветное сравнение: новый слева, старый справа](../../art_working/visual_upgrade_2026_11_20/forest_visual_target/previews/comparison_sheet.png).
- [Grayscale-сравнение](../../art_working/visual_upgrade_2026_11_20/forest_visual_target/previews/grayscale_comparison_sheet.png).
- [Brief](../../art_working/visual_upgrade_2026_11_20/forest_visual_target/brief.md), [полный review](../../art_working/visual_upgrade_2026_11_20/forest_visual_target/review.md), [manifest](../../art_working/visual_upgrade_2026_11_20/forest_visual_target/manifest.json).
- [Промпт v01](../../art_working/visual_upgrade_2026_11_20/forest_visual_target/prompt_v01.txt), [правка v02](../../art_working/visual_upgrade_2026_11_20/forest_visual_target/prompt_v02.txt).

Кандидат улучшает читаемость лица/рубашки, сухого прута и слизи на тёплой земле. Просмотрены native/downsample/nearest ×2 и grayscale. Размеры, палитра и сетка проверены скриптами. Возраст/кисти/стороны деталей и Печать требуют крупного still-review и ручной доводки; HUD, анимация, FPS и Android не проверялись.

Статус: **reviewed visual target, не approved asset**. Профиль 360×640 остаётся предложением. Текущий runtime и production не менялись. Плоскую сцену нельзя импортировать как чистый фон: актёры и тени уже в ней. Отдельные PNG и анимации следуют после выбора направления, как требует исходный промпт.

Рабочие изображения и prompts находятся в art_working/, который исключён существующим .gitignore. Этот документ индексирует локальные материалы; для передачи пакета использовать сам рабочий каталог.
