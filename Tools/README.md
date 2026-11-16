# Инструменты этапа 04

## Актуальное завершение — 16.11.2026

Пользователь разрешил агенту необходимые скрипты. Офлайн-импорт завершен и проверен; команды ниже актуальны. Старый раздел после «Архив первоначальной передачи» оставлен для истории и не определяет текущие статусы D004/D006/запуска.

Из корня DeathLovers:

```powershell
python Tools/test_tools.py
python Tools/story_tool.py convert --source C:/Work/Programs/RenPy/100flwrsjam/game --copy-assets
python Tools/story_tool.py validate --story Resources/DeathLovers/Story/story.json --config Resources/DeathLovers/Story/resolved-config.json --assets Resources/DeathLovers/Story/assets.json --project . --report ImplementationSpecs/Reports/04_validation.json
python Tools/qa_tool.py prepare --story Resources/DeathLovers/Story/story.json --output Resources/DeathLovers/Story/Debug
python Tools/verify_stage04.py --source C:/Work/Programs/RenPy/100flwrsjam/game
```

Без --copy-assets конвертация обновляет только JSON. SOURCE_FILES.tsv содержит принятый hash после исправлений D004/D006; обычная команда не требует --allow-source-changes. История source hash и сдвиг selectors — Reference/SOURCE_REVISIONS.md. D004 больше не ожидается как ошибка: полный reachable traversal проходит. D006 исправлен в источнике, text содержит Ren'Py escape [[x3], normalizedText содержит буквальное [x3].

verify_stage04.py требует предварительных convert и prepare. Проверяет повторную конвертацию побайтно, правку текста полного сюжета в памяти с сохранением ID, dangling target/returnTarget и D006; результат — Reports/04_acceptance.json. Оригинал не изменяется. Проверены 16 одинаковых JSON-файлов, все ID полного сюжета сохранены при правке текста.

test_tools.py теперь выполняет **10** cases. Добавлены inventory regression для всех 11 файлов источника (включая shaders.rpy), пробел перед двоеточием option, geometry IDs/пустые служебные массивы, case-sensitive путь и конфликт пользовательского ресурса. Остальные fixtures из первоначального раздела сохранены. Лимит состояний CLI по умолчанию **3000000**, проверено 1180031 состояние. В pipeline.json документированы 16 конкретных недостижимых ID, без wildcard; это returns после restart/ending и continuation цепочки location calls.

Ресурсы: 193 записи импортированы и проверены по SHA-256/точному регистру. asset_import_baseline.json продвигается только при --copy-assets; обычная конвертация baseline не меняет. Preflight всех файлов останавливает ASSET_CONFLICT до копирования. Source original и пользовательские правки не перезаписываются.

```powershell
python Tools/qa_tool.py geometry --expected ImplementationSpecs/Reference/LayoutCases/unity-results.json --actual ImplementationSpecs/Reference/LayoutCases/srengine-results.json --report ImplementationSpecs/Reports/04_geometry.json
python ImplementationSpecs/Reference/LayoutCases/compare.py ImplementationSpecs/Reference/LayoutCases/cases.json ImplementationSpecs/Reference/LayoutCases/unity-results.json ImplementationSpecs/Reference/LayoutCases/srengine-results.json --scalers ImplementationSpecs/Reference/LayoutCases/scaler-expected.json --engine-scalers ImplementationSpecs/Reference/LayoutCases/srengine-scalers.json --report ImplementationSpecs/Reports/04_layout_matrix.json
python Tools/qa_tool.py screenshots --directory Screenshots --report ImplementationSpecs/Reports/04_screenshots.json
```

Geometry helper сопоставляет cases/scalers по уникальным ID и допускает отсутствие пустого служебного массива; непустые данные пропускать нельзя. Полная матрица/drift100: PASS, 512 layout и 53 scaler cases, 0 differences. Использованы сохраненные экспорты, движок не запускался. Screenshots: отсутствует 31 требуемый снимок, поэтому availability-отчет FAILED; это не ошибка импортера и не заявление о визуальной точности.

Подготовлены восемь проверенных offline ending traces и полный new_game checkpoint в Story/Debug. Runtime/debug button integration остается этапу 06, сохранение snapshot через IStoryDebugSnapshotSink — этапу 07. В release prefab/menu debug-компонент не включать. Python остается офлайн-инструментом; игровое исполнение — AS.

## Архив первоначальной передачи

Python 3.11+ только для офлайн-подготовки, без зависимостей pip/Ren'Py. В игру Python не включается. Все команды ниже выполняет пользователь: агент их не запускал. Рабочий каталог — корень DeathLovers.

## Поддерживаемая грамматика

Разбор отступов и дерева блоков, затем отдельный разбор allowlisted expressions через Python ast (без eval/exec):

- literal default; label, включая вложенный main_choice; jump/call [from name]/return;
- if/elif/else; menu [name] с quoted option [if condition]; исходный порядок вариантов;
- `$ variable = literal`, `$ variable += int`;
- `$ known_controller.say(string[, auto_wait=bool])`, `$ known_controller.set_state(string[, transition=Dissolve(number)|dissolve])`;
- scene ID [with fade|dissolve|vpunch]; play/stop music|sound, loop, fadein/fadeout;
- nvl clear; pause [seconds]; renpy.block_rollback(); renpy.full_restart(config.game_main_transition).

Bool/int/string conditions: literals, registered variables, not/and/or, ==/!=/</<=/>/>=. Однострочные литералы Python; `#` внутри строки не комментарий. Вызовы внутри строки остаются текстом. Произвольные Python-блоки, неизвестные методы, ATL, show/hide, define/screens/init и другие формы не считаются сюжетными командами. Они либо явно классифицированы как инфраструктура в pipeline.json, либо дают fatal. Точное подмножество соответствует обращениям script.rpy из Reference; расширять его нужно явно вместе с fixtures.

## Пользовательский запуск

```powershell
python Tools/test_tools.py
python Tools/story_tool.py convert --source C:/Work/Programs/RenPy/100flwrsjam/game
```

По умолчанию output — Resources/DeathLovers/Story. Сначала создаются candidate.story.json, candidate.command_ids.json, candidate.assets.json, resolved-config.json, characters.json, coverage.json, aliases.json и text-audit.json. Валидатор затем создает validation.json. Только после успеха записываются story.json, command_ids.json, assets.json. Сюжетный D004 должен давать EMPTY_REACHABLE_CHOICE; точный первый error может быть другим до пользовательского прогона. FAILED не является приёмкой и не публикует новый story.json. Старый успешный story.json при ошибке остается прежним: всегда проверять validation.json/contentVersion.

resource-usage.json отдельно перечисляет использование из реестра Reference и unused/debug candidates. Динамические кандидаты не объявляются доказанно неиспользуемыми; файлы не удаляются.

Не создавать новый output для каждой обычной переконвертации: command_ids.json должен сохраняться и входить в Git. После первой неуспешной конвертации для продолжения с теми же ID можно явно принять **только** candidate.command_ids.json как command_ids.json; это не означает принятия сценария. Для исходников, осознанно измененных после baseline, есть `--allow-source-changes`. Пересмотреть Reference при изменениях controllers/images/UI: этот флаг не обновляет реестр автоматически.

Для неоднозначности сохранить JSON mapping `anchor -> старый ID`, затем:

```powershell
python Tools/story_tool.py convert --source C:/Work/Programs/RenPy/100flwrsjam/game --mapping Tools/id-mapping.json
```

При ошибке AMBIGUOUS_ID anchor указан в сообщении; предыдущие anchors/ID находятся в command_ids.json. Для split/merge определить сохраняемую идентичность вручную, остальные узлы получают новые ID, удаленные — tombstone. Перестановки одинаковых структур без изменения числа узлов требуют авторского mapping (см. ограничение STORY_SCHEMA.md).

Ресурсы копируются только при `--copy-assets`, после валидации и полного preflight конфликтов. Источник не изменяется; путь назначения только внутри проекта и только из ASSET_MANIFEST.tsv. Даже при первом копировании существующий отличающийся файл не затирается. После копирования записывается asset_import_baseline.json: сохранить его для проверки пользовательских изменений. Обычная конвертация без копирования не продвигает этот baseline. Копируется полный реестр, включая неиспользуемые ресурсы; они не удаляются. При прерывании файлового копирования нужно повторить запуск и проверить файлы: multi-file import не является файловой транзакцией.

Независимая проверка, в том числе установленных ресурсов с точным регистром и hash:

```powershell
python Tools/story_tool.py validate --story Resources/DeathLovers/Story/candidate.story.json --config Resources/DeathLovers/Story/resolved-config.json --assets Resources/DeathLovers/Story/candidate.assets.json --report Resources/DeathLovers/Story/validation.json
# Для проверки фактически скопированных файлов добавить --project .
```

`--state-limit N` доступен обеим командам. Исчерпание лимита дает ошибку; не снижать требования к reachable choice для обхода D004. Config `unreachable` принимает только конкретные commandId и непустую причину, не wildcard.

## Fixtures и приемка

test_tools.py подготавливает восемь unittest-проверок: повторные байты/текстовые правки ID; неоднозначная вставка; неизвестный блок; отсутствующий ресурс; недоступный выбор; типы AST/short-circuit; нормализация; tombstones/no reuse. positive.rpy содержит call stack, nested conditions, conditional choice, NVL clear, scene, wait, barrier/restart и вызов внутри строки. Отрицательные исходники вынесены в fixtures. Fixtures не подтверждают полный сюжет до пользовательского запуска.

Вручную дополнительно проверить: изменить целевой ресурс после импорта — следующий `--copy-assets` дает ASSET_CONFLICT; убрать target/returnTarget — validate дает TARGET/RETURN_TARGET; поменять регистр физического пути — PATH_CASE. Удалить/переместить неоднозначный повтор — AMBIGUOUS_ID с явным mapping. Никакой неизвестный statement не должен исчезать из coverage без ошибки.

## Debug, replay, geometry и screenshots

```powershell
python Tools/qa_tool.py prepare --story Resources/DeathLovers/Story/candidate.story.json --output Resources/DeathLovers/Story/Debug
python Tools/qa_tool.py geometry --expected ImplementationSpecs/Reference/LayoutCases/unity-results.json --actual ImplementationSpecs/Reference/LayoutCases/srengine-results.json --report ImplementationSpecs/Reports/04_geometry.json
python Tools/qa_tool.py screenshots --directory Screenshots --report ImplementationSpecs/Reports/04_screenshots.json
```

prepare проверяет восемь маршрутов из ENDINGS.md офлайн, привязывает варианты к commandId/choiceId и проверяет P,W,H и вход в нужную ending label. Создает bound-playthroughs.json (OFFLINE_TRACE_ONLY) и checkpoints.json с полным new_game, привязанным к contentVersion. Это не подтверждает текст, звук, screenshots и завершение ending. Навигация выбирается по исходному `not visited`, пакеты — по исходным меню/ordinal, готовая трасса содержит неизменяемые ID. playthroughs.json также хранит отрицательный D004.

geometry сравнивает JSON геометрии с исходными допусками compare.py этапа 02: 0.00001 для `.scale`, 0.001 иначе. Для полной приемки матрицы и drift100 использовать также существующий ImplementationSpecs/Reference/LayoutCases/compare.py по его README; новый инструмент его не заменяет. screenshots проверяет наличие имен из BASELINE_CHECKLIST, включая восемь ending PNG, PNG header и 1920×1080, без заявления о визуальном совпадении. Conditional gamepad screenshot может быть отсутствующим обоснованно в v1; отсутствие фиксируется в отчете.

StoryDebugPanel.as — подготовленный AS-компонент, developmentBuild=false по умолчанию. Configure включает его только при development=true. В release prefab/menu не добавлять этот компонент и его кнопки. Состояние показывается через штатный TextMesh.SetText, данные — JsonValue.Clone/Get/ToJson. Реальные объявления: Engine/libs/Utils/inc/Utils/Serialization/JsonValue.h; TextMesh API проверен стендом EngineApiProbe.as.

Новые интерфейсы **игрового AS**, не существующие C++ API:

- IStoryDebugRuntime: CaptureDebugState(), RestoreDebugCheckpoint(JsonValue@), HasDebugCommand(String). Реализовать этапу 06; восстановление валидирует типы/ресурсы и атомарно применяет состояние без исполнения команд.
- IStoryDebugSnapshotSink: SaveDebugSnapshot(name,json). Реализовать этапу 07 в application data directory. Текущий SaveSystem не дает проверенного AS setter для произвольного JSON, поэтому выдуманного вызова записи файла здесь нет.

Refresh/ShowResources/RestoreCheckpoint/SaveSnapshot подготовлены как void callbacks для UIButtonEvent. Этап 06 назначает runtime, TextMesh, manifests и SelectCheckpoint(name); этап 07 подключает sink. До этого SaveSnapshot выдает SNAPSHOT_UNAVAILABLE, а неизвестный/неполный checkpoint не меняет сессию. Нельзя подменять checkpoint произвольной меткой.
