# 04. Формат сценария, конвертер, валидатор и инструменты

## Цель и зависимости

Зависимость: 03 и Reference этапа 01. Создать воспроизводимый pipeline переноса без Python/Ren’Py runtime в готовой игре. Инструменты живут в `DeathLovers/Tools`; все исполнение новеллы — AS. Подготовить запуск инструментов пользователем, самостоятельно скрипты не выполнять.

## Формат Story v1

UTF-8 JSON, без зависимых от локали чисел. Корень: schemaVersion=1, contentVersion (SHA-256 нормализованного набора исходников и manifests), entryCommandId, labels (label→commandId), commands (ID→record). У каждой команды: id, type, sourceFile, sourceLine, next (ID либо null). Source fields нужны для диагностики, но не идентичности.

| Команда | Обязательные данные и семантика |
|---|---|
| Say | speakerId, mode ADV/NVL, text с исходной разметкой, autoWait; next выполняется после завершения ожидания |
| NvlClear | Очистка NVL-страницы без очистки истории |
| Scene | resourceId, transition descriptor; смена фона и только тех слоев, которые очищает оригинал |
| Character | characterId, action, параметры state/position/scale/flip/animation/transition |
| Audio | bus, action play/stop, resourceId при play, loop, fadeSeconds |
| Assign | variableId, operation set/add, типизированное значение |
| Branch | condition AST, trueTarget, falseTarget |
| Choice | варианты: неизменяемый choiceId, text, optional condition AST, target; порядок исходный |
| Jump | target; next не используется |
| Call | target, returnTarget; кладет returnTarget в стек |
| Return | Снять верхний returnTarget; пустой стек завершает сценарий |
| Wait | seconds либо waitForInput; не блокирует UI-кадр |
| RollbackBarrier | Создать границу отката в точном месте исходного вызова |
| RestartToMenu | Завершить сессию, сохранить профиль, сбросить transient game state |

AST условий: literal, variable, not, and, or, eq, ne, lt, le, gt, ge. Логические операции short-circuit; типы фиксированы Variables registry; неявное сравнение boolean/string/int запрещено. Числовые исходные счетчики — signed 32 bit. Никакого eval/exec и свободного AS source в JSON.

## Стабильные ID

`Story/command_ids.json` хранит идентичность и соответствие исходным узлам; ID вида `cmd_00000001`, choice ID вида `choice_00000001`, значения монотонно выделяются и никогда не переиспользуются. Первая конвертация присваивает ID в порядке файлов из manifest и исходного обхода. Повторная конвертация сопоставляет structural anchors, label, соседей и сохраненную привязку; совпадение текста само по себе недостаточно. При нескольких кандидатах завершить с отчетом, требующим явной mapping-записи. Удаленные ID сохраняются tombstone. Смена текста не меняет ID и прочитанность; split/merge требуют явного mapping и contentVersion change.

## Конвертер

Поддержать только обнаруженное в Reference подмножество Ren’Py: labels/call/return/jump/menu/default/if/elif/else; изменения переменных; обращения к существующему CharacterController/NarratorNvl; scene/audio/nvl clear/rollback/full_restart; достижимые transforms. Построить синтаксический разбор структуры и отступов; один большой regex-переписыватель недопустим. Положительные и отрицательные fixtures обязательны.

Сохранить регистр ID, текст, порядок вариантов, условия и point-of-effect переменных. Вызовы внутри Python-строк не интерпретировать как команды. Комментарии и недостижимый debug не превращать в сюжет. Формальный список поддерживаемых конструкций разместить в `Tools/README.md`.

Ресурсы копируются только через реестр этапа 01. Оригинал остается неизменным. Целевые имена и hash привязать в `Story/assets.json`; alias хранить отдельно с причиной. Измененные ранее пользователем ресурсы не перезаписывать молча: сравнивать baseline и выдавать конфликт.

## Валидатор

Проверяет schema/types, уникальность ID, все targets/returnTarget, стартовую метку, reachable graph, отсутствие choice без доступного варианта при достижимом состоянии, состояния персонажей, ресурсы/регистр пути, парность/параметры тегов, вызовы запрещенных конструкций, корректность AST, версию manifests.

Отдельно отчет coverage: исходные исполняемые узлы → команды; неизвестные узлы — fatal, не warning. Недостижимый код допускается только с записью причины. Несбалансированные visual-теги нормализуются по общему контракту, исходный текст сохраняется для аудита. Ошибка имеет код, sourceFile/line и actionable сообщение.

## Инструменты отладки

Подготовить AS debug panel, включаемую настройкой development build, недоступную в релизном меню: просмотр current ID/phase/call stack/variables, переход к заранее подготовленному checkpoint, просмотр resource IDs, сохранение диагностического snapshot. Прыжок к метке с неизвестным состоянием запрещен: использовать fixture со всеми variables/presentation либо выдавать предупреждение и не менять сессию. Конкретные кнопки подключаются к runtime на этапе 06.

Подготовить проверку geometry fixture из этапа 02, screenshot names и воспроизводимые playthrough manifests. Не создавать отдельный полноценный редактор графа сюжета: текстовые данные и валидатор достаточны для v1.

## Приемка и передача

Повторная конвертация одинакового входа дает побайтно одинаковый результат. Изменение текста fixture сохраняет ID; неоднозначное перемещение вызывает контролируемую ошибку. Нет потерянных исполняемых конструкций. Fixtures содержат call stack, nested conditions, выбор с условием, ошибочный resource и неизвестный statement. Создать `Reference/STORY_SCHEMA.md`, `Tools/README.md`, `Reports/04_RESULT.md`. Содержимое JSON, API и CLI в отчетах — фактические, не предполагаемые.
