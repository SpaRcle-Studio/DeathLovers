# Story v1 — контракт данных этапа 04

Дата: 16.11.2026. Реализация: Tools/story_parser.py, story_compile.py, story_validate.py, story_tool.py. Статус: OFFLINE_VERIFIED. JSON UTF-8, LF, indent=2, без NaN/Infinity и timestamps. Повторяющиеся ключи JSON запрещены.

## Корень

`schemaVersion: 1`, `contentVersion: string` (64 lowercase hex SHA-256), `entryCommandId: string`, `labels: object<label, commandId>`, `commands: object<commandId, command>`, `variables: object<variableId, {type, initial}>`. Тип переменной: `bool`, `int` (signed 32 bit), `string`; implicit casts запрещены. Реальные семь defaults извлекаются из script.rpy, не из исполняемого Python.

contentVersion вычисляется из канонического JSON: нормализованные UTF-8 тексты всех файлов SOURCE_FILES.tsv (CRLF/CR→LF, BOM удаляется), тексты referenceFiles из pipeline.json, resolved config, ID registry, assets manifest с SHA-256 содержимого файлов. Порядок файлов фиксирован TSV/config; сортировка таблицы команд и ID registry явная. Версия зависит также от исключенных исходников: изменение UI/контроллеров не остается незамеченным.

## Команды

Общие обязательные поля: `id: cmd_########`, `type`, `sourceFile`, `sourceLine` (positive integer), `next: commandId|null`. sourceFile/sourceLine служат диагностикой, не ключом идентичности. Неизвестные поля команды запрещены. Ни Python, ни AS source в данных не исполняются.

| type | Поля сверх общих | Семантика |
|---|---|---|
| Say | speakerId, mode: ADV/NVL, text: string, normalizedText: string, autoWait: bool | text сохраняет оригинал; runtime использует normalizedText и применяет autoWait по TEXT_AND_AUDIO.md; next после ожидания |
| NvlClear | — | Очистить NVL без удаления истории |
| Scene | resourceId, transition, clearLayers: ["master"] | Не очищать отдельные character_* layers |
| Character | characterId, action: set_state, state, transition | Применить stateResources и параметры characters.json; hidden использует исходный empty sprite |
| Audio | bus: Music/Sfx/Voice, action: play/stop, resourceId при play, loop: bool, fadeSeconds >= 0 | Группы задаются проектом; stop не требует resourceId |
| Assign | variableId, operation: set/add, value: primitive | add только int, overflow — ошибка; точка воздействия не переносится |
| Branch | condition: AST, trueTarget, falseTarget | Перейти по условию; targets могут быть null на конце блока |
| Choice | options: array | Порядок исходный; выбранный target после подтверждения |
| Jump | target | next=null |
| Call | target, returnTarget | Положить returnTarget в стек; next=null |
| Return | — | next=null; пустой стек завершает сценарий |
| Wait | seconds >= 0 **либо** waitForInput: true | Без блокировки UI |
| RollbackBarrier | — | Граница в точке исходного вызова |
| RestartToMenu | — | next=null; завершить сессию, сохранить профиль, сбросить transient state |

Option: `{choiceId: "choice_########", text, normalizedText, condition?: AST, target: commandId}`. ID варианта уникален во всем документе. Текст варианта не является ID. `normalizedText` добавляется CLI; модульные fixtures допускают его отсутствие и вычисляют его при проверке.

Transition: `{kind: "none"|"fade"|"dissolve"|"vpunch", seconds?: number}`. Для `Dissolve(x)` seconds=x; именованные переходы используют исходные стандартные значения, не произвольно назначенную длительность. Параметры position/scale/flip/animation не обнаружены как отдельные сюжетные вызовы: исходные постоянные параметры сохранены в characters.json. Координаты там остаются RenPy1920x1080; преобразование в UI выполняется один раз слоем представления этапа 05.

## AST

- literal: `{op:"literal", value: bool|int|string}`;
- variable: `{op:"variable", variableId}`;
- not: `{op:"not", operand: AST}`;
- and/or: `{op:"and"|"or", operands:[AST, AST, ...]}`;
- сравнение: `{op:"eq"|"ne"|"lt"|"le"|"gt"|"ge", left:AST, right:AST}`.

and/or short-circuit. not/and/or требуют bool. eq/ne требуют одинаковых типов; упорядоченные сравнения — int. Calls, attributes, arithmetic expressions, interpolation expressions и arbitrary host execution в AST запрещены.

## Идентичность и ресурсы

command_ids.json: `{schemaVersion:1, nextCommand, nextChoice, nodes:[{id,anchor,scope,shape,textFingerprint,previousShape,nextShape,sourceFile,sourceLine,tombstone}]}`. Первый обход — порядок sourceFiles и исходный preorder. scope учитывает файл/label и блок; shape не содержит текст Say/Choice. При неизменной структурной последовательности сохраняются ID соседних узлов; при структурных правках используются уникальные shapes в scope. Повторяющиеся кандидаты и обнаруженные перемещения блоков требуют `--mapping` JSON `{ "anchor из candidate registry": "старый ID" }`. Удаленные записи остаются tombstone; counters всегда выше всех ранее выделенных значений.

textFingerprint используется только для отказа при перестановке неизмененного набора текстов, не для автоматического назначения ID. Ограничение консервативного matching: одновременная перестановка и переписывание одинаковых структур может быть неотличима от обычного редактирования текста. Для таких правок, а также split/merge, автор обязан передать явный mapping; автоматического переноса прочитанности по тексту нет. Исходная строка не используется для сопоставления. Mapping не должен назначать один ID двум узлам.

assets.json: `{schemaVersion:1, assets:[{id,source,target,sha256,names}]}`. Канонический resource ID — точный физический относительный путь из реестра этапа 01, а не объединенная через `;` ячейка id TSV. `names` хранит эти исходные имена раздельно. `builtin:black` не файл. aliases.json содержит отдельные записи FILE_ALIASES.tsv с причиной. Исходные файлы всегда читаются без изменения. Existing target при копировании сравнивается с asset_import_baseline.json последнего импорта; изменение пользователем вызывает ASSET_CONFLICT. Этот baseline не обновляется при конвертации без копирования.

characters.json содержит states и для трех видимых героинь: stateResources, layer, position, scale, flip, animation, order, coordinateSpace. Неиспользуемая Алиса исключена вместе с debug.rpy. Остальные метаданные говорящих, автоожидание и звук печати — Reference/TEXT_AND_AUDIO.md для реализации этапа 05.

## Диагностика и покрытия

Ошибка: `{code,sourceFile,sourceLine,message}`. Покрытие `coverage.json`: executableNodes с commandId и при необходимости choiceId; classifiedSources содержит причины исключения файлов инфраструктуры/UI. labels представлены таблицей labels, defaults — variables, поэтому не создают фиктивные исполняемые команды. Неизвестный statement/block — fatal.

`text-audit.json` хранит оригиналы, нормализованные тексты и диагностику. Открытые стили закрываются в конце текста, лишние закрытия игнорируются, пересекающиеся диапазоны сохраняются. Слова не исправляются. После разрешенного исправления D006 исходник содержит корректный `{/i}` и Ren'Py escape `[[x3]`; нормализация превращает `[[` в буквальную `[` без исполнения интерполяции.

Валидатор исследует точные состояния `(current ID, call stack, values)`; empty reachable choice и int overflow fatal. Лимит состояний/стека дает STATE_LIMIT, не успешный неполный результат. CLI по умолчанию допускает 3000000 состояний; текущий полный граф проверен за 1180031 состояние. Недостижимая команда требует причины в resolved config `unreachable: {commandId: reason}`; у текущего сюжета документированы 16 таких команд. D004 исправлен в источнике, конвертер не добавляет скрытых переходов. Эквивалентность Ren'Py runtime этим не заявляется.
