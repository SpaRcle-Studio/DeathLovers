# Этап 04 — инструменты и формат Story v1

## Актуальная приемка — 16.11.2026

**Этап 04 завершен.** После исправления String += пользователь повторно проверил проект и подтвердил отсутствие ошибок AS-модуля. Офлайн-приемка и сборка AS подтверждены; функциональное подключение debug-кнопок/runtime/snapshot sink остается этапам 06/07 по спецификации.

Уточнение AS-проверки: пользовательский запуск обнаружил четыре ошибки String += в StoryDebugPanel.Refresh. В текущем binding зарегистрирован opAdd, но нет opAddAssign; четыре выражения заменены на text = text + ... . Сигнатура сверена с AngelScriptBindings.cpp и Resources/as.predefined. После этой правки пользователь подтвердил отсутствие ошибок при повторной проверке; офлайн-результаты сценария и ресурсов не изменились.

Статус: **OFFLINE_VERIFIED**. Пользователь разрешил запуск необходимых скриптов; импорт, тесты и офлайн-проверки выполнены агентом. Нижний первоначальный отчет сохранен как история; его AWAITING_USER_RUN и ожидание решений D004/D006 больше не актуальны. Движок, Ren'Py runtime, сборка и кодогенерация не запускались.

### Фактический результат

- В Resources/DeathLovers/Story сформированы story.json, command_ids.json, assets.json, characters.json, coverage.json, aliases.json, text-audit.json, resource-usage.json и validation.json.
- 2158 команд: 1663 Say, 22 Choice, 56 вариантов, 15 labels; 2214 исполняемых узлов покрыты командами/вариантами.
- Проверены **1180031** точных reachable states с call stack/переменными. 2142 команды достижимы; 16 недостижимых команд имеют индивидуальные причины в pipeline.json. Это возвраты после full_restart/ending и continuation цепочки location calls.
- Импортированы все **193** ресурса, проверены точный регистр и SHA-256. User-modified asset блокируется preflight до первого копирования; baseline хранится отдельно от описания assets.
- Сформированы восемь bound playthroughs с постоянными commandId/choiceId и полный new_game checkpoint с contentVersion. Очки P,W,H и вход в нужную ending label проверены.

### Исправления при полном запуске

Причина SOURCE_COVERAGE — отсутствующая классификация shaders.rpy. Она добавлена и защищена inventory regression test. Parser допускает исходный пробел перед двоеточием option. CLI state limit увеличен до 3000000 без ослабления проверки choices/types. Geometry helper учитывает необязательный пустой scalers и сопоставляет export cases по ID.

D004 и D006 исправлены в оригинале по прямому запросу пользователя. SOURCE_FILES.tsv обновлен; старый hash, принятый hash и изменения сохранены в Reference/SOURCE_REVISIONS.md. Нумерация столовых menu selectors актуализирована. После D004 достижимых пустых choices нет. После D006 text сохраняет [[x3], normalizedText содержит буквальное [x3]; тег курсива исправлен. Другие исходные дефекты этим не считаются закрытыми.

### Выполненные проверки

| Проверка | Результат | Артефакт |
|---|---|---|
| 10 unit/regression cases | OK | Tools/test_tools.py |
| Schema/AST/types, полный reachable graph, resource case/hash | PASSED | 04_validation.json и Story/validation.json |
| Повторная конвертация | 16 JSON файлов побайтно одинаковы | 04_acceptance.json |
| Правка текста полного сюжета в памяти | Все ID сохранены | 04_acceptance.json |
| Dangling target/returnTarget | Ожидаемый диагностический отказ | 04_acceptance.json |
| Ambiguous move/insert, unknown statement/resource, empty choice, tombstones, AST/short-circuit, source inventory | Ожидаемые positive/negative результаты | test_tools.py |
| User-modified asset / неверный регистр | ASSET_CONFLICT / PATH_CASE | test_tools.py |
| 8 ending traces | Очки и ending labels проверены | Story/Debug/bound-playthroughs.json |
| Geometry exports | PASSED, 0 differences | 04_geometry.json |
| Layout/scalers + drift100 | PASS, 512/53 cases, 0 differences | 04_layout_matrix.json |
| Screenshot names/PNG availability | Отсутствует 31 снимок | 04_screenshots.json |

Точные contentVersion и output hashes — в 04_acceptance.json. Geometry использует ранее сохраненные экспорты. Отсутствующие screenshots не заменялись искусственными кадрами; визуальное/звуковое воспроизведение и AS debug execution еще не проверены.

### Изменения и передача

Движок: изменений нет. Игра: Tools/*.py, pipeline.json, playthroughs.json, fixtures, Tools/.gitignore; подготовленный AS StoryDebugPanel; generated Story и импортированные ресурсы по реестру. Reference: SOURCE_FILES.tsv, SOURCE_REVISIONS.md, STORY_SCHEMA.md, уточнения DEFECTS/SOURCE_BASELINE. Reports: текущий отчет и машинные результаты. Существующие пользовательские изменения сохранены, commits и глобальные Git settings не менялись; reload CMake не требуется.

Офлайн-часть этапа 04 завершена. Этапу 05 передаются schema/resources/characters и TEXT_AND_AUDIO; этапу 06 — граф, IDs, checkpoints/replays и IStoryDebugRuntime; этапу 07 — IStoryDebugSnapshotSink. Используются реальные JsonValue.Get/Has/Clone/ToJson, TextMesh.SetText, GameObject.SetEnabled. Интерфейсы runtime/sink объявлены в игровом AS, их интеграция соответствует этапам 06/07. Нативные сцены выдуманного формата и C++ VN runtime не добавлялись.

Остаток: screenshots/визуальная и звуковая приемка, runtime-кнопки отладки требуют последующих этапов. Multi-file import не транзакционен при I/O failure; одновременная перестановка и переписывание одинаковых shapes требует авторского mapping. D001/D002/D003/D008 и прочие исходные замечания не объявляются исправленными.

## Архив первоначальной передачи

Дата: 16.11.2026. Статус: **IMPLEMENTED / AWAITING_USER_RUN**. Скрипты, тесты, движок и сборка агентом не запускались. Готовые story.json/command_ids.json/assets.json не сфабрикованы: их создает пользовательский запуск конвертера.

## Изменения игры

- Tools/story_common.py — JSON с проверкой дубликатов, канонические байты, SHA-256, ограничение путей, case-sensitive проверка файлов.
- Tools/story_parser.py — дерево отступов, allowlisted синтаксис и типизированное condition AST без исполнения исходника.
- Tools/story_compile.py — граф, continuation/returnTarget, nested labels/branches/menus, стабильные ID, явные mapping и tombstones.
- Tools/story_validate.py — schema/types, targets/entry, AST, states/resources, теги, точный обход reachable states с call stack и empty-choice проверкой.
- Tools/story_tool.py, pipeline.json — CLI, baseline/reference manifests, contentVersion, coverage/text audit, защита копирования ресурсов от конфликтов.
- Tools/qa_tool.py, playthroughs.json — привязка восьми маршрутов к ID, полный new_game checkpoint, проверки geometry/screenshot artifacts.
- Tools/test_tools.py, fixtures/*.rpy — положительные/отрицательные приемочные исходники и проверки.
- Resources/DeathLovers/Scripts/Debug/StoryDebugPanel.as — просмотр state/resource IDs, checkpoint guard, интерфейсы runtime/snapshot sink для этапов 06/07.
- Reference/STORY_SCHEMA.md, Tools/README.md — фактический формат и CLI, ограничения и команды пользовательского запуска.

## Движок и совместимость

Исходники движка и оригинальная Ren'Py-игра не изменены. Новых C++ файлов нет, reload CMake для этой задачи не требуется. Выполнение новеллы остается задачей AS этапов 05/06. Python нужен только офлайн.

Использован подтвержденный JsonValue API: LoadResource/Parse/Get/GetKind/GetCount/Has/Clone/ToJson и тип JsonValueKind. Debug UI использует TextMesh.SetText и GameObject.SetEnabled. Интерфейсы IStoryDebugRuntime/IStoryDebugSnapshotSink объявлены в новом AS-файле; они не выдаются за готовый API движка. Нативных сцен выдуманного формата не добавлено.

## Статическая проверка

Перечитаны исходники инструментов и AS, сверены SOURCE_FILES/ASSET_MANIFEST/SCENE_REFERENCES/FILE_ALIASES/IMAGE_DEFINITIONS, методы контроллеров оригинала, данные маршрутов ENDINGS.md и API JsonValue/TextMesh/SceneObject. Проверены пути назначения, отсутствие eval/exec, отсутствие runtime Python, поиск std:: и конфликтных маркеров. JSON-конфигурации проверены штатным чтением PowerShell; новые Python/AS не исполнялись. Подробные результаты пользовательского запуска еще отсутствуют.

Git status прочитан с одноразовым `git -c safe.directory=... status`; глобальная конфигурация не менялась. До работы существовали untracked Builds, ImplementationArtifacts, ImplementationSpecs, Resources/Engine; эти материалы не перезаписывались. Commit не создавался.

## Пользовательская приемка

1. Из корня DeathLovers выполнить `python Tools/test_tools.py`: ожидаются восемь успешных unittest cases. При ошибках передать полный вывод.
2. Выполнить convert по Tools/README.md. Проверить candidate outputs и coverage. Повтор одинакового входа с сохраненным command_ids.json должен дать те же байты; текстовая правка — те же ID и другой contentVersion. Проверка baseline для измененного источника требует явного --allow-source-changes.
3. Ожидается обнаружение D004 (script.rpy:1779): достигнуто меню без доступных вариантов. Это ошибка исходного сюжета, не основание добавлять переход молча. Не помечать весь сценарий PASSED и не публиковать новый story.json при FAILED.
4. Запустить qa_tool prepare для candidate.story.json: восемь offline traces должны привести в указанные ending labels с точными очками. Это не проверяет воспроизведение финальных реплик. D006 остается отдельным вопросом текста/интерполяции.
5. Проверить конфликт измененного ресурса, dangling target, неверный resource/case и неоднозначную вставку. Ошибки должны быть fatal и actionable. Прочитать text-audit, исключения и tombstones.
6. Запустить geometry и screenshots по README. Не считать наличие PNG доказательством визуального совпадения. Полная geometry матрица/drift100 остается штатным compare.py этапа 02.
7. В этапе 06 подключить debug runtime/кнопки только development build. Проверить ID/phase/stack/variables/resource IDs, отказ неизвестному checkpoint без изменения session, восстановление полного new_game. В этапе 07 подключить сохранение snapshot в application data; до подключения ожидается диагностический отказ.

## Остаток и передача

Приемка исполнения и побайтовой повторяемости ожидает пользователя согласно запрету запуска скриптов. Известные D004 и D006 не исправлены без сюжетного решения. Консервативный matching не может автоматически отличить перестановку одинаковых shapes от правки текста: для этого обязателен авторский mapping. Импорт нескольких файлов не является атомарной транзакцией при I/O failure. Инфраструктурные исходники классифицированы по файлам, а не конвертируются в сюжет.

Этапу 05 передаются Story/AST/resource contracts и Reference/TEXT_AND_AUDIO. Этапу 06 — граф/continuations, bound replay/checkpoint формат и IStoryDebugRuntime. Этапу 07 — IStoryDebugSnapshotSink. Финальные счетчики команд, contentVersion и результаты запуска записать сюда после фактического пользовательского прогона; значения не предполагались.
