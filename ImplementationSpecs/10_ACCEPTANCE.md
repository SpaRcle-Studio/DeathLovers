# 10. Сквозная приемка и подготовка выпуска

## Цель и зависимости

Зависимость: 09. Подтвердить полноту переноса, совместимость UI и изоляцию игры от движка. Подготовить самостоятельный пакет проекта DeathLovers. Сборку/запуск/упаковочные скрипты выполняет пользователь согласно CLAUDE.md; агент готовит необходимые assets, настройки и инструкции, исправляет дефекты по результатам.

## Матрица приемки

Создать `Reference/ACCEPTANCE_MATRIX.md`, строка: ID, предусловия, шаги, ожидаемый результат, источник требования, результат, доказательство, дефект. Статусы `PASS`, `FAIL`, `NOT_RUN`; только фактический результат пользователя переводит в PASS. Не считать statically inspected аналогом runtime pass.

### A. Layout

Повторить cases этапа 02 на закрепленном uGUI baseline. Сравнить numerical rect/scale, initial и dynamic результат, шесть viewport и DPI. Допуски — 02_LAYOUT. Дополнительно реальные MainMenu/Preferences/Slots/History/ADV/NVL/Choice не имеют clipping, неверного hit test, двойного scale, дрейфа после resize. Unity-параметры применяются без per-screen поправок.

### B. Сюжет

Все восемь концовок по trace fixtures. Все шесть порядков посещений. Проверка score=4/5 для каждого счетчика (через debug fixtures, отдельно от честных playthrough). Все доступные/недоступные варианты, call stack возвраты, visited guards и повторный NewGame. Сравнить последовательность command IDs и deltas при manual/skip/auto.

### C. Диалог/представление

Кириллица и комбинируемые символы, переносы на узком viewport, все tags/effects, auto waits/punctuation, явные waits, nw, NVL clear, смена говорящего/цвета, hidden sprites, mirror/scale, bounce и layer-only dissolve. Печать не меняет финальную геометрию текста. Одноразовые звуки не дублируются при восстановлении.

### D. Сохранения

Полный round-trip после закрытия процесса во всех waiting phases, stack depth>1, manual/quick/auto, overwrite/delete/cancel. Поврежденный state/hash/marker и неподдерживаемая версия не разрушают текущую сессию. Два поколения выдерживают прерывание записи. User-data каталог не зависит от working directory. Проверить запуск из каталога без прав записи.

### E. Чтение и ввод

Rollback через несколько реплик, fork ветки и запрет после barrier; 100 checkpoints; 250 history cap; read IDs глобальны; skip останавливается на choice; auto не выбирает ответ; hide UI потребляет первый input; modal/focus/drag/click release; потеря/возврат focus; Alt+Enter; settings persistence. Закрытие modal и загрузка не продвигают сценарий дополнительным input.

### F. Стабильность

20 циклов NewGame→Menu и Save→Load: число UI объектов, audio sources, subscriptions и cache entries возвращается к стабильному уровню, нет линейного роста. Один narrative runner и одна menu music instance. Длинная реплика не пересоздает font atlas на каждый glyph. Профилирование проводят на машине пользователя; записать модель CPU/GPU, resolution/backend и медиану/p95 frame time без выдуманного универсального FPS-обещания.

## Архитектурный аудит

По изменениям C++ проверить отсутствие DeathLovers/story IDs/героев/очков/концовок/Ren’Py interpreter и hardcoded путей. UI runtime не использует ImGui/Yoga вместо layout. AS не пишет произвольные файлы saves в installation directory. Новые C++ общие компоненты документированы и не зависят от наличия проекта игры. Удаление DeathLovers из project search paths не ломает загрузку редактора/других проектов.

Повторить требования CLAUDE.md: свои изменения без запрещенных STL-контейнеров, правильные codegen includes, native resource conventions, no generated-source edits, no unnecessary architecture rewrites. Найденные старые unrelated нарушения не исправлять массово.

## Пакет и документация

1. Проверить .srproject, project/application identity, стартовую сцену и зависимые ресурсы.
2. Подготовить список включаемых файлов: runtime resources/AS/story/native scenes и необходимые лицензии. Исключить Ren’Py cache/rpyc/saves, keystore, dev fixtures, converter Python и debug UI из релизной стартовой конфигурации.
3. Не включать исходные пользовательские saves в release. Первое открытие создает чистый профиль по defaults.
4. Создать `DeathLovers/README.md`: запуск проекта, entry scene, управление, saves location, ожидаемые зависимости движка, процедура обновления контента и несовместимость старых Ren’Py saves.
5. Создать `Reference/RELEASE_MANIFEST.md`: contentVersion, движок/revision или hash измененных файлов при недоступном Git, Unity baseline, список shipped assets/hash, лицензии.
6. Инструкции сборки/экспорта должны использовать реально существующий pipeline SREngine. Если packaging механизма нет, подготовить переносимый проект и описать отсутствующий общий exporter как отдельный дефект; не выдумывать команду и не заявлять готовый exe.

## Финальный критерий

Release accepted только если все обязательные matrix cases PASS, coverage 100%, отсутствуют блокирующие defects и заглушки, все девять предыдущих отчетов доступны, внешний проект содержит всю игровую логику в AS. Для неизбежных отличий rasterization записать конкретный допуск; не распространять его на layout.

`Reports/10_RESULT.md`: фактически достигнутый статус, артефакты, результаты по категориям, известные ограничения v1, список NOT_RUN, рекомендации пользователю для оставшейся проверки. Если сборка не запускалась пользователем, итог — IMPLEMENTED/AWAITING_USER_RUN, а не «игра полностью протестирована».
