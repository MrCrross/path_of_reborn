# REFERENCE CATALOG

Дата сбора: **2026-11-17**. Статусы отражают доступ из текущей среды. Оригинальные материалы Path of Kings не являются production assets.

## Источники

| ID | Название | Тип | Оригинальный источник | Локальный путь | Содержимое и что изучаем | Планируемые изменения | Дата | Статус |
|---|---|---|---|---|---|---|---|---|
| POK-001 | Path of Kings — Google Play listing | официальный store page | [Google Play](https://play.google.com/store/apps/details?id=com.TornadoBear.WayofKings) | — | Официальное описание подтверждает first-person fantasy action RPG, vertical play, real-time combat, dodge/strike/abilities, waves, locations, loot и equipment combinations. Изучаем заявленный loop и portrait constraint. | Переносим только общие UX-принципы; создаём 2D pixel-art identity и собственную Checkpoint-систему. | 2026-11-17 | Проверен текст и наличие screenshot links |
| POK-002 | Official screenshot 01 | официальный скриншот | [Google Play CDN](https://play-lh.googleusercontent.com/f577ndbpbUBn1n66rLkwUOPlKZMQoedO8-2PANaqyYh4UHbo9Y0Xh00vOAMHRdKPcvA8gu8PODazGGPL_9qONVc=w526-h296) | `references/path-of-kings/screenshots/path_of_kings_01.png` | Официальный визуальный материал для ручного сравнения portrait-композиции и боевого фокуса. | Перерисовать только wireframe и поведение, не использовать пиксели/ассеты. | 2026-11-17 | Скачан, reference-only |
| POK-003 | Official screenshot 02 | официальный скриншот | [Google Play CDN](https://play-lh.googleusercontent.com/ob5oCTjlDWPcVTjQuYnuE2mmS4HkupH99k07febif6zM3fUh-dCIlMQ_H3sMVFSb996Sjr2cyy5OvuSF0pTK=w526-h296) | `references/path-of-kings/screenshots/path_of_kings_02.png` | Официальный визуальный материал для ручного осмотра экранных зон и визуального приоритета. | Создать оригинальную композицию для Path of Reborn после подтверждения наблюдений. | 2026-11-17 | Скачан, reference-only |
| POK-004 | Official screenshot 03 | официальный скриншот | [Google Play CDN](https://play-lh.googleusercontent.com/w0XAO8SFhP3eXiGF65CxMamo0YGSCo2MDivelAGblfL6cuWMZebX1yxYv1ONhqTqpHlZWOdCZ5dS4DdQkbrO=w526-h296) | `references/path-of-kings/screenshots/path_of_kings_03.png` | Боевой кадр с вертикальной композицией и крупным сообщением о битве; используем только как UX-наблюдение. | Не копировать персонажей, палитру, шрифт или текст; проверить собственную читаемость на portrait viewport. | 2026-11-17 | Скачан, reference-only |
| POK-005 | Official screenshot 04 | официальный скриншот | [Google Play CDN](https://play-lh.googleusercontent.com/UpuWMh_T83XYnBMpPttT11vlcR64YdlYi_t5sdnLG0S3JZg96vEZ_RB461MxNV3gieEIQ0sm79Lm-N_YDYqy=w526-h296) | `references/path-of-kings/screenshots/path_of_kings_04.png` | Официальный визуальный материал; pixel-level layout ещё не является требованием Path of Reborn. | Использовать как наблюдаемый референс только для анализа приоритета и масштаба. | 2026-11-17 | Скачан, reference-only |
| POK-006 | Official screenshot 05 | официальный скриншот | [Google Play CDN](https://play-lh.googleusercontent.com/kf1cRLBzqwVD3tW35TbxO_73sL4Cedl3V0_UAWaRieUM2A-mpgrhJMdU5RmBfWuZN7Bi0RiNa21JppDhq03mjsg=w526-h296) | `references/path-of-kings/screenshots/path_of_kings_05.png` | Официальный визуальный материал для осмотра прогрессии/награды, если эти элементы присутствуют. | Создать собственные карточки и рамки на основе требований Path of Reborn. | 2026-11-17 | Скачан, reference-only |
| POK-007 | Official trailer thumbnail | официальный promo/trailer asset | [YouTube thumbnail](https://i.ytimg.com/vi/LAIGCQWOJ6s/hqdefault.jpg) | — | Страница Google Play указывает trailer; thumbnail URL доступен, но видео и кадры не извлечены в среде. | Найти полный trailer вручную и пометить таймкоды экранов. | 2026-11-17 | URL обнаружен, просмотр требует ручного шага |
| POK-008 | Path of Kings — GameFAQs screenshot | пользовательский скриншот, вторичный источник | [GameFAQs](https://gamefaqs.gamespot.com/android/668789-path-of-kings/images?img=8&pid=668789) | — | Страница подтверждает игру, разработчика Tornado Bear, Android и дату релиза; права и актуальность изображения не подтверждены. | Не использовать для art production; только как lead для поиска первичного материала. | 2026-11-17 | Метаданные проверены, изображение не сохранено |

## Подтверждённый анализ

- Ориентация: portrait/vertical заявлена официальной страницей.
- Камера: first-person заявлена официальной страницей; это не означает, что Path of Reborn должен копировать её перспективу.
- Бой: real-time, dodge, strike, abilities и waves заявлены официально.
- Прогрессия: weapons/equipment combinations, locations, enemies и loot заявлены официально.
- Параметры отдельных HUD-зон, точные touch targets, grid inventory, карты, rarity frames и reward flow **не подтверждены в этой среде**.

## Рабочие UX-гипотезы до ручного просмотра

Использовать нижнюю зону для часто нажимаемых действий, держать один главный фокус в игровом поле, не скрывать состояние HP и результата боя, показывать последствия поражения до повторной попытки. Эти пункты — проектные гипотезы Path of Reborn, а не утверждения о Path of Kings.

## Ограничение

Скриншоты сохранены только в reference-каталоге после явного разрешения пользователя. Они не копируются в `assets/`, не импортируются в Godot и не используются как production art. Полный trailer по-прежнему не скачан; в каталоге сохранена только ссылка на thumbnail.
