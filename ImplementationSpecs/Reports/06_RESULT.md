# 06. AS runtime и вертикальный срез

Дата: 17.11.2026. Статус: IMPLEMENTED / AWAITING_USER_RUN. Сборка, компиляция AS, рендер, звук и интерактивная приемка не запускались: CLAUDE.md запрещает агенту сборочные инструменты, кодогенерацию и запуск бинарников. Ниже ожидаемые трассы, а не выданный за выполненный runtime-тест.

## Изменения игры

### Исправления по восьми замечаниям к игровому экрану

- Жирный MTSDF-текст: расширение контура использует true SDF из alpha вместо псевдорасстояния RGB; это устраняет источник швов на острых углах, но конкретный артефакт «М» требует визуальной проверки. Изменены общий text-mesh.srsl и шейдер игры.
- Явные localPriority: подложка −100; старый/новый фон 0/1; пары персонажей 10…15; advance 20; ADV/NVL 30; choices 50; панель быстрого меню 100; история 200. Приоритеты дочерних элементов относительные. Окно ADV ниже текста.
- RuntimeText.mat и шейдер игры задают чёрную обводку 3 px для текста, в том числе NVL на светлом фоне.
- Choice использует исходные choice_idle/hover_background.png, серый/белый текст и автоматическую высоту по измеренному тексту, spacing 33. Подсвечиваются hover, keyboard focus и pressed. Форматирование текста при смене состояния сохраняется.
- Rollback: до 100 независимых StateCore без вложенного кольца checkpoints, полное предъявление сохранённой реплики, восстановление переменных/ветки/стека/истории, остановка коротких звуков и завершение переходов. Профиль прочитанного не откатывается. RollbackBarrier очищает кольцо. Управление: кнопка «Назад», PageUp, колесо вверх. Доступность кнопки соответствует наличию предыдущей точки.
- Hold skip: левый/правый Ctrl; toggle skip и Auto подключены к панели. Пропуск учитывает настройки непрочитанного, explicit waits и переходов; выбор автоматически не принимается. Ручное продвижение/rollback/загрузка отменяют toggle skip и Auto. Музыка не превращается в очередь звуков печати. Зелёный цвет обозначает включённый режим.
- QuickMenu, ReadingHistory и ReturnMainMenu добавлены в MainMenu.scene как настоящая редактируемая разметка с нативными компонентами и событиями. AS управляет видимостью и содержимым. История использует UIScrollRect и маску. «Главное меню» доступно и на панели, и в игровом меню, с подтверждением потери прогресса.
- Проверены 148 текстур UI и Images: imageType UI, mipLevels 1, ClampToEdge. Для фоновых и персонажных изображений созданы отсутствовавшие .meta.

Ограничение: «Сохранить», «Б.Сохр», «Б.Загр» присутствуют в разметке, но отключены. Полноценное дисковое сохранение этапа 07 этой правкой не реализовано; временные копии в памяти не выдаются за сохранения.

Статически проверены баланс скобок AS, 24 обработчика событий сцены, отсутствие повторов среди 55 новых entity ID, метаданные всех 148 текстур и git diff --check. Это не компиляция AS и не runtime-приёмка. Проверить после перезапуска: жирные «М/И» на разных размерах; фон → персонаж → ADV; NVL на cgall; длинные выборы с мышью/клавиатурой; rollback через choice и до Barrier; Ctrl с разрешённым/запрещённым непрочитанным; Auto; история; отмена/подтверждение возврата в главное меню. Сборка и запуск не выполнялись по CLAUDE.md.

Исправление после проверки пользователем: NovelView больше не добавляет стиль имени с диапазоном [0,0) у рассказчика. DialogueProgram пропускает пустые диапазоны и теги cps, управляющие скоростью печати. Высота NVL Content теперь равна максимуму высоты viewport и фактических видимых записей (до шести, без отступа после последней); прокрутка к нижней границе больше не скрывает единственную короткую запись над маской. Изменены только AS-скрипты игры; повторная проверка в игре ещё требуется. В предоставленном логе также есть ошибки debug transport и загрузки Samples.dll — они не относятся к этим исправлениям.

- Scripts/Runtime/RuntimeValues.as: значения JSON и операции над строками.
- Scripts/Runtime/NovelSession.as: единственный GameState, Story v1 runner, AST, call/return, assign с int32 overflow, choice с кэшированным порядком, лимит 1000 команд/кадр, ожидания, история, граница отката, фиксация ID концовки при входе в соответствующую label.
- Scripts/Runtime/DialogueProgram.as: автоматические паузы по character_data.py, графемы, ADV/NVL, вложенные стили, cps, input/timed waits, nw, параметры wave/shake.
- Scripts/Runtime/NovelView.as: переиспользуемое представление через штатные GameObject/TransformRect, TextMesh, Sprite, UIButton, RectMask2D, UIScrollRect. Это прямое создание нативных компонентов, не альтернативный layout/рендерер или самодельный загрузчик сцены. Геометрию внешнего 1920×1080 пространства и resize обслуживает уже существующий Novel/AspectRatioFitter FitInParent с referenceSize.
- Scripts/Runtime/NovelAudio.as: Music/Sfx/Voice, независимые группы Music/Effects/Voice, линейные fade по narrative time, реальные позиции источников, пул Typewriter0…9. Все пути разрешаются исключительно через assets.json.
- Scripts/Runtime/NovelPresentation.as: применение фона, отдельных слоев персонажей, переходов, bounce и времени текстовых эффектов. Не исполняет сценарий и не владеет GameState.
- Scripts/Runtime/NovelSnapshotValidation.as: валидация до замены состояния, восстановление представления без исполнения команд.
- Scripts/UI/MenuNavigation.as: Start → исходный story.entryCommandId → Call пролога; Escape открывает/закрывает игровое меню и не продвигает текст. «Продолжить» возвращает из игрового меню. Профиль MenuSession сохраняется. Неактивность приложения и game menu замораживают narrative time; музыка продолжает играть. Первый кадр после возобновления не добавляет прошедшее реальное время.
- Story/speakers.json: имена, цвета, manifest voice ID и множители из characters.rpy/CharacterController/NarratorNvl. Story/runtime-fixture.json: отдельный Story v1 с семью defaults и собственным contentVersion/ID. Исходный story.json и его ID не менялись.
- Materials/RuntimeText.mat, RuntimeBlack.mat: нативные SRA-материалы текста и черной подложки. Shaders/RuntimeText.srsl реализует диапазонные wave/shake в игре. В MainMenu.scene удалён устаревший текст про этап 06. Исходная Ren'Py-игра не изменена.
- Reference/DEFECTS.md: явное решение D003, ограничение сравнения NVL по D002.

## Изменения движка

Только универсальные API; сюжетных типов и путей DeathLovers в C++ нет.

| Файлы | Добавление |
|---|---|
| Scripting/src/Scripting/AngelScript/AngelScriptBindings.cpp, AngelScriptBindingHelpers.cpp | String.byteAt(uint), substring(uint begin,uint count), graphemeCount(); length/индексы substring задаются в UTF-8 байтах, graphemeCount использует существующий DecodeGraphemes. Границы проверяются, ошибки дают AS exception |
| Engine/UI/UIButton.h/.cpp | SetClickReceiver(const SharedPtr<Component>&, StringAtom): заменить список события клика одним штатным receiver/method, без параллельной системы ввода |
| Engine/UI/UIScrollRect.h | существующие SetContent/SetViewport открыты рефлексии/AS |
| Graphics/Font/TextMesh.h/.cpp | SetFontPath(StringAtom); передача произвольных customData0/1 в Custom2/Custom3 без интерпретации эффектов |
| Graphics/Font/TextStyle.h | два универсальных FVector4 customData0/1; включены в сравнение стиля. Нулевой канал наследуется от предыдущего покрывающего диапазона, ненулевой заменяет его целиком |
| Graphics/Types/Geometry/Sprite.h/.cpp | GetTextureSize(): исходные размеры текстуры, без scale/PPU |
| Utils/ECS/SceneObject.h/.cpp | GetHierarchyObjectCount(): число SceneObject в поддереве, включая корень |
| AngelScriptBindingHelpers.cpp | неудачный AS cast возвращает null вместо исключения об unsupported value |

Исправление по пользовательскому runtime-логу: в NovelView.Rect установка TransformRect использует `@object.transform = TransformRect()`, то есть заменяет ссылку на трансформ объекта. Прежнее присваивание без `@` оставляло Transform3D и приводило к ошибке при cast на следующей строке. Configure теперь устанавливает configured только после создания всего UI/аудио; ошибка Start показывает диагностику через Notify, а не экран-заглушку. Требуются пересборка движка и повторный запуск пользователем; устранение ошибки в работающей игре ещё не подтверждено.

Новых cpp/h нет. Существующие cpp включают соответствующие Codegen/*.generated.hpp; TextStyle.generated.hpp включен существующим TextStyle.cpp. Нужна пересборка движка с обычной кодогенерацией; добавление новых cpp не требует reload CMake. Старые TextStyle имеют нулевые амплитуды и сохраняют прежний вид. Вершинный layout TextMesh расширен двумя vec4; шейдер и движок нужно обновлять вместе.

## Состояние и интерфейсы для этапа 07

`NovelSession.state` — единственный JSON GameState schemaVersion=1. `Get/At` у JsonValue возвращают копии: все изменения явно записываются обратно через Set/SetAt. Нативные компоненты — только производное представление и аудиоустройства.

- contentVersion из загруженного Story; currentCommandId; phase: Ready/WaitingText/WaitingChoice/WaitingTimer/WaitingTransition/Finished; callStack в порядке вызовов, включая null continuation на конце блока.
- variables: defaults из Story.variables, семь исходных типизированных значений; bool/int/string без неявного приведения.
- presentation: background (manifest ID либо builtin:black), characters; mode/speakerId/text/autoWait; visibleIndex в графемах; tokenIndex следующего текстового события; remainingPause; inputWait/fullyShown/dialogueVisible; choices (кэш доступных option objects в исходном порядке); nvl (полные накопленные записи); effectTime.
- presentation.transition: kind/from/target/elapsed/duration. Именованные fade=1.0 (.5 out+.0 hold+.5 in), dissolve=.5, vpunch=.25; seconds имеют приоритет. Окончательные значения/кадры сравнить с установленным SDK оригинала.
- character: исходные layer/order/position/scale/flip/stateResources, state/resourceId/previousResource, transitionElapsed/transitionDuration, animation/bounceElapsed/bounceActive. Порядок слоев — register order ch_p, ch_w, ch_h. Позиция = position контроллера; закомментированное sprite.position-смещение не добавляется. В реестре исходные parent zoom=1 и flip=false, child scale уже записан в scale. Ren'Py Y инвертируется один раз. Bounce .2 секунды, 20 пикселей: UI offset=+sin(elapsed*pi/.2)*20, то есть исходный -abs(sin(...))*20 в Y вниз; затем offset=0, active=false, animation=null.
- audio.Music/Sfx/Voice: resourceId, loop, position, gain, targetGain, fadeFrom, fadeDuration/fadeRemaining, stopAfterFade, completed. voiceIndex/voiceCooldown — положение пула печати и минимальная пауза. Snapshot не содержит объектов аудио. Завершенные одноразовые SFX не запускаются при restore; незавершенные/loop восстанавливаются с seek. Ошибка Play/Seek возвращает false с diagnostic, а не молча играет сначала.
- history: максимум 250 записей commandId/speakerId/text. rollbackBoundaryId; rollbackCheckpoints (пустой резерв для этапа 08, лимит валидации 100). playTimeSeconds; activeEndingId (имя исходной ending label); diagnostic.

Публичные AS-интерфейсы: `bool StartSession()`, `JsonValue@ CaptureDebugState()`, `bool RestoreDebugCheckpoint(JsonValue@)`, `bool HasDebugCommand(const String &in)`, `void End()`. Runtime реализует существующий IStoryDebugRuntime. До restore должен быть сконфигурирован runtime и загружен соответствующий Story (например, StartSession до первого Update); перенос снимка между contentVersion отвергается. В этом этапе нет диска и переноса snapshot между перезапусками приложения. Профиль MenuSession::profile не входит в снимок и не откатывается.

Restore валидирует типы/default registry, ID и фазу, текстовые индексы, варианты текущего Choice, ресурсы, таймеры/аудио до изменения GameState. Затем восстанавливает аудио и проецирует представление; runner не вызывается. При аудиоошибке возвращает false и пытается восстановить предыдущее аудио; состояние игры остается прежним. Runtime-зависимость seek этапа 03 остается обязательной для приемки.

## Fixture: ожидаемая трасса до/после каждой команды

Идентификаторы ниже имеют общий префикс `cmd_900000`; `01` означает `cmd_90000001`. Поля: R=var_roots, P=var_plague_score, H=history count, S=callStack. Остальные переменные остаются defaults. «После» для временной команды — состояние сразу после входа/yield; следующий переход происходит после таймера/ввода. Это статическое ожидание, не измеренный trace.

| ID/type | До | После |
|---|---|---|
| 01 Audio | Ready, R0/P0/H0/S[] | Music god loop, gain0→1 за1.5; Ready02 |
| 02 Scene | black, Ready02 | cgall, WaitingTransition02 elapsed0/duration1; затем Ready03 |
| 03 Say NVL | H0, NVL[] | H1, NVL[03], WaitingText03; auto waits, 1.25 не разбивается; после advance Ready04 |
| 04 Say NVL | H1, NVL[03] | H2, NVL[03,04], WaitingText04; отдельная граница {w}, .2 timed wait; затем Ready05 |
| 05 NvlClear | NVL[03,04], H2 | NVL[], H2, dialogueVisible=false, Ready06 |
| 06 Character | персонажей нет | ch_p normal, dissolve.15, bounce.2; Ready07 (анимация не блокирует диалог) |
| 07 Say ADV | H2 | H3, WaitingText07; стили/cps/effects; nw автоматически → Ready08 |
| 08 Audio | Sfx завершен | Door one-shot, Music продолжает независимо; Ready22 |
| 22 Character | ch_p normal | ch_p happy, слой dissolve.5, новый одноразовый bounce.2; Ready09 |
| 09 Assign | R0/P0 | R1/P0, Ready10 |
| 10 Branch | R1 | trueTarget11; false99 не посещается |
| 11 Call | S[] | S[12], Ready20 |
| 20 Say ADV | H3/S[12] | H4/S[12], WaitingText20; затем Ready21 |
| 21 Return | S[12] | S[], Ready12 |
| 12 Choice | R1, canteen=false | WaitingChoice12, только choice_90000001; исходный второй вариант исключен; один submit → Ready13 |
| 13 Assign | P0 | P2, Ready14 |
| 14 RollbackBarrier | boundary пустой | boundary14, rollbackCheckpoints[], Ready15 |
| 15 Wait | Ready15 | WaitingTimer15/inputWait=true; отдельный advance → Ready16 |
| 16 Audio | Music gain1 | Music fadeout.5/stopAfterFade=true, Ready17 |
| 17 Scene | cgall и ch_p | black, WaitingTransition17; персонаж сохраняется на отдельном слое; затем Ready18 |
| 18 Return | S[] | Finished18; R1/P2/H4, boundary14 |
| 99 Say (ошибка) | недостижим при штатных значениях | при посещении виден FIXTURE FAILED; это отрицательный контроль |

В fixture StartFixture устанавливает animation=single_bounce_animation в отдельной копии Character registry; исходный сюжет bounce не вызывает, его реестр не меняется. Штатный Start всегда загружает исходный реестр заново. Команды не расширены игровым C++ API.

Для отдельного fixture contentVersion — SHA-256 его UTF-8/LF текста с исключенной строкой contentVersion; это локальная версия теста, отдельно от версии исходного сюжета, вычисленной конвертером этапа04.

`runtime.trace` при fixture хранит реальные before/after GameState для каждого входа в команду. В обычной игре trace выключен. Кнопка Trace помещает JSON в MenuNavigation.runtimeProbeReport для просмотра/копирования из Inspector. Действительного runtime trace пока нет: AWAITING_USER_RUN.

## Статическая проверка и запуск пользователем

Выполнено: чтение фактических API, сверка Story v1/AST/defaults и источников character_data.py/characters.rpy; разбор новых JSON через ConvertFrom-Json; сверка fixture и voice ID с assets.json; чтение изменений и проверка литералов, std:: и generated include; git diff --check для измененных отслеживаемых файлов. Сборка/кодоген/тестовые бинарники/конвертер не запускались. Чужие изменения движка и его подмодулей не изменены; коммиты и глобальный safe.directory не создавались.

Результат чтения JSON: 22 команды fixture, 7 переменных, 10 говорящих; 0 неизвестных ссылок команд/ресурсов fixture и voice ID; 0 отсутствующих физических файлов во всем существующем assets.json; contentVersion fixture — 64 символа. У семи новых AS-файлов сбалансированы скобки после исключения строк/комментариев. Это не компиляция AngelScript.

1. Пересобрать SREngine обычным способом. Открыть MainMenu.scene и игровой режим. Проверить AS compiler log, отсутствие неизвестных типов, полей, событий и ошибок ресурсов. Start должен сразу исполнять исходный Call и пролог, без технического SessionStart. Пройти до первого сюжетного выбора после return пролога.
2. Проверить ADV/NVL, имена/цвета/кириллицу/комбинируемые графемы, стили, auto waits и десятичные точки. В NVL проверить накопление, прокрутку и NvlClear. Из-за D002 требуются Reference-кадр/решение для точной политики переполнения оригинала; выбранная реализация последних шести записей не объявлена подтвержденной оригиналом.
3. Для fixture остановить игровой режим, включить developmentRuntime на MenuNavigation в Inspector, снова запустить. Вверху появится только техническая панель Fixture / RestoreTwice / Trace. В релизной конфигурации developmentRuntime=false, панель не создается. Fixture → пройти строки и единственный выбор; проверить итог R1/P2/H4/Finished в snapshot/trace.
4. На строке04 ускорить печать: первый advance должен остановиться на {w}; следующий только снять input wait; дальнейший advance раскрывает хвост, пропуская timed waits; еще один заканчивает Say. Escape не меняет visibleIndex. На строке07 проверить nw как при обычной печати, так и после ускорения.
5. Нажать RestoreTwice в середине строки04/07/20, в начале перехода02/17, на Choice12 и Wait15. Ожидается PASSED_IN_THIS_RUN, textRules=true, одинаковые objectsBefore/After; variables/history/callStack/presentation равны. Тест текстовых правил покрывает многоточия, десятичную точку, поиск существующего wait через теги/пробелы, теговые параметры, combining mark и вложенные size. Результат проверяется в текущем запуске, не является заранее пройденным.
6. Во время печати и перехода открыть Escape/Preferences, подождать, изменить размер, закрыть. visibleIndex/elapsed/offset не должны продвинуться за время паузы; трек продолжает играть, CaptureDebugState берет фактическую позицию. Потерять/вернуть focus. Проверить viewport 1920×1080, 1280×720, 1366×768, 2560×1440, 1024×768, 2560×1080.
7. Проверить .15 dissolve персонажа отдельно от окна текста, bounce возвращается точно в исходную позицию и сбрасывает флаг. На17 фон становится черным, персонаж сохраняется. Пул печати не создает Typewriter10, нет звука пробелов/тегов/ускорения/догоняющего воспроизведения. cps=0/pixel_voice=false дают тишину. Проверить раздельные настройки Music/Effects/Voice и мастер mute.
8. После завершения Door и во время музыки восстановить снимок дважды: завершенный Door не повторяется, музыка находится на сохраненной позиции; ошибка seek должна быть видна как FAILED с audioDiagnostic. Повторить Start/возврат через сюжетный RestartToMenu несколько раз: object count стабилен, источники не множатся.

Открытая приемка: компиляция AS/C++, actual trace, двойное восстановление, pause/menu/resize/focus, звук/seek, визуальные эффекты и сравнение NVL с оригиналом. До результатов пользователя этап не имеет статуса runtime-verified. Этапы07/08 должны подключить диск/слоты, историю отката, пользовательские load/history/skip/auto UI к этим явным значениям; реализация этих этапов здесь не подменяется.
