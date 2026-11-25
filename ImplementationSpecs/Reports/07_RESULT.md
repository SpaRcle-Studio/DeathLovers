# 07 — Сохранения, загрузка и постоянный профиль

Дата: 25.11.2026.

## Статус

Реализация внесена в игру и `C:/Work/SREngine`. Статически сверены используемые API, схема записи/восстановления и маршруты UI. **Сборка, кодогенерация, приложение и диагностические стенды не запускались**: действует запрет `C:/Work/SREngine/CLAUDE.md`. Приёмка после сборки и полного перезапуска приложения остаётся за пользователем. Значения `PASS` ниже — ожидаемые результаты, а не полученные логи.

Корневого `DeathLovers/CLAUDE.md` в рабочем каталоге нет. Git status отклонён Git из-за dubious ownership; safe.directory и глобальная конфигурация не изменялись. Коммитов нет. Проверка изменений выполнена чтением файлов и поиском по исходникам.

## Универсальность хранения и платформенный слой

Движок не требует GameState, contentVersion, playtime, command IDs, картинок или JSON-объекта в состоянии. SetState принимает любую корректную JSON-величину, включая число, строку, bool, null, массив и дерево. Без SetState слот хранит только пользовательские файлы или служебные метаданные. SetMetadata необязателен; минимальный индекс движок создаёт сам. schemaVersion и sequence относятся к приложению и не проверяются/не назначаются движком. Версия физического индекса — отдельный storageVersion=1.

SetFile/GetFile/HasFile/RemoveFile/EnumerateFiles работают с именованными бинарными данными. ImportFile/ExportFile копируют целый файл через VFS без преобразования его формата. Относительные пути могут включать подкаталоги, расширения и UTF-8; traversal, абсолютные пути и конфликтующие пути отвергаются. Файлы и необязательное JSON-состояние публикуются одним поколением с проверкой длины и SHA-256 каждого файла. Данные файлов подготавливаются в памяти: это не streaming API для файлов больше доступной памяти.

OpenFileStream, FlushFileToDisk, ReplaceFileAtomic и FormatLocalDateTime объявлены в Platform.h и реализованы в платформенном слое. File.cpp, SaveStorage.cpp и операция replace DirectoryVFSBackend не содержат WinAPI или платформенных ветвлений. SR_GMTIME/SR_LOCALTIME/SR_TIMEGM определены в Platform.h; Windows.h в публичные заголовки не добавляется. Инклюды модулей разделены пустыми строками; FrameCapture.h начинает зависимости с Graphics/stdInclude.h. Остальные затронутые Graphics-заголовки получают его через собственные Graphics-зависимости.

## Изменения движка

Пути относительно `C:/Work/SREngine/Engine`:

- `libs/Utils/inc/Utils/Game/SaveSystem.h`, `libs/Utils/src/Utils/Game/SaveSystem.cpp`: реальные Save/Load, подтверждённые Flush/Delete, каталог из ApplicationInfo, дисковое перечисление, метаданные, ошибки, защита ID, поколения и fallback.
- Новые `libs/Utils/inc/Utils/Game/SaveStorage.h`, `libs/Utils/src/Utils/Game/SaveStorage.cpp`: настраиваемый бюджет чтения, атомарная запись через VFS, независимый от OpenSSL SHA-256, проверка относительных путей, UTC, локализованное отображение времени, точки инъекции сбоев.
- `libs/Utils/inc/Utils/FileSystem/File.h`, `libs/Utils/src/Utils/FileSystem/File.cpp`: `bool Flush()`; проверка stream errors и `FlushFileBuffers` на Windows / `fsync` на остальных платформах. Windows/MSVC открывает UTF-8 пути через UTF-16.
- `libs/Utils/inc/Utils/Platform/Platform.h`, `libs/Utils/src/Utils/Platform/PlatformWindows.cpp`, `PlatformCommon.cpp`: платформенные операции файлов и локального времени, макросы времени.
- `libs/Utils/src/Utils/FileSystem/DirectoryVFSBackend.cpp`: replace делегируется Platform::ReplaceFileAtomic.
- `libs/Utils/src/Utils/FileSystem/VFS.cpp`: `WriteFileAtomic` учитывает результат flush перед replace.
- Новые `libs/Graphics/inc/Graphics/Types/FrameCapture.h`, `libs/Graphics/src/Graphics/Types/FrameCapture.cpp`: захват показанного кадра без специальной рендертехники. В редакторе используется изображение сцены активной editor-камеры из настроек RenderContext, при обычном запуске — swapchain. Размер PNG задаёт вызывающий код.
- `Pipeline`, `VulkanPipeline/VulkanKernel`, `WebGPUPipeline`: очередь захвата после отрисовки; Vulkan завершает чтение acquired swapchain-изображения до QueuePresent. Нормализация каналов для изображения отделена параметром от численных значений picking; учитывается BGRA. Цветовые framebuffer Vulkan допускают transfer-source независимо от настроек рендертехники.
- `libs/Graphics/inc/Graphics/Loaders/TextureLoader.h`, `libs/Graphics/src/Graphics/Loaders/TextureLoader.cpp`: кодирование RGB PNG через существующий stb_image_write.
- `libs/Graphics/inc/Graphics/Types/Geometry/Sprite.h`, `libs/Graphics/src/Graphics/Types/Geometry/Sprite.cpp`: загрузка изображения из байтов, без превращения AppData в каталог ресурсов.
- `libs/Graphics/src/Graphics/Types/Texture.cpp`: уникальные ID текстур из памяти и установка состояния Loaded для таких текстур.
- Новые `libs/Utils/inc/Utils/Tests/SaveStorageProbe.h`, `libs/Utils/src/Utils/Tests/SaveStorageProbe.cpp`: дисковый стенд атомарности, fallback, схемы, перечисления, удаления и отдельного чтения после перезапуска.

Новых сюжетных команд или интерпретатора в C++ нет. Значения DeathLovers, история, политика слотов и восстановление остаются в AS.

## Изменения игры

- Новый `Resources/DeathLovers/Scripts/Runtime/NovelSaves.as`: слоты, Confirm, очередь сохранения до yield, получение снимка, capture/publish, строгая проверка документа, подготовка загрузки, кольца quick/auto, профиль и ошибки.
- `Scripts/UI/MenuNavigation.as`: подключение сервиса, кнопки Save/QuickSave/QuickLoad, вкладки и страницы, сохранение настроек, завершение профиля, диагностические кнопки.
- `Scripts/Runtime/NovelSession.as`: точки Choice/после выбора, прочитанность Choice, блокировка исполнения при операции, копирование аудио в снимок, сброс ввода при восстановлении, учёт источника сценария.
- `Scripts/Runtime/NovelSnapshotValidation.as`: schemaVersion=1, дополнительные проверки текста/концовок/типов ресурсов и точного списка доступных Choice по сохранённым переменным.
- `Scripts/Runtime/NovelAudio.as`: параметр восстановления одноразовых звуков; дисковая загрузка не запускает одноразовые SFX заново. Loop-источники восстанавливаются с позицией/fade.
- Новый `Resources/DeathLovers/Prefabs/UI/SaveSlots.prefab`: общий нативный GridLayoutGroup, 3 столбца, 2 строки, 6 ячеек. Содержимое ячеек и receiver назначаются AS через обычные компоненты движка.
- Новый `Resources/DeathLovers/Story/saves-fixture.json`: отдельный сценарий для дискового round-trip; существующий runtime-fixture этапа 06 не изменён.
- `Scenes/MainMenu.scene`: камера использует штатную рендертехнику из настроек движка. Дополнительные ресурсы рендеринга для миниатюр не требуются.

## Реальные API

| API | Назначение |
|---|---|
| `SaveSystem::GetSaveDirectory() -> const Path&` | Корень сохранений по organization/name/project из Platform::ApplicationInfo |
| `OpenSlot(group, slot) -> SaveSlot::Ptr` | Чтение опубликованного слота либо создание пустого объекта; ошибка возвращает null |
| `CloseSlot(group, slot)` | Удаление из кеша открытых объектов; файлы остаются |
| `FlushSlot(group, slot) -> bool` | Синхронный подтверждённый publish |
| `DeleteSlot(group, slot) -> bool` | Проверка фактического удаления каталога |
| `EnumerateSlots(group) -> JsonValue` | JSON-массив валидных опубликованных метаданных с диска |
| `SaveSlot::SetState(const JsonValue&) -> bool`, `GetState() -> JsonValue` | Копия JSON-значения любого вида |
| `SetMetadata(const JsonValue&)`, `GetMetadata() -> JsonValue` | Метаданные операции |
| `HasState() -> bool`, `RemoveState()` | Необязательное JSON-состояние; отсутствие отличается от сохранённого null |
| `SetFile(relativePath, bytes) -> bool`, `GetFile(relativePath) -> String` | Произвольные бинарные данные без требований к формату |
| `HasFile/RemoveFile/EnumerateFiles` | Наличие, удаление и список path/length |
| `ImportFile(relativePath, source) -> bool`, `ExportFile(relativePath, destination) -> bool` | Целые файлы из/в смонтированный VFS |
| `SaveSlot/SaveSystem::SetReadLimit(uint64)` | Бюджет JSON-состояния и пользовательских файлов, 0 — без заданного лимита |
| `SaveSlot::WasRecovered() -> bool` | Сработал fallback |
| `GetError() -> String`, `ClearError()` | Есть у SaveSystem и SaveSlot |
| `ComputeSha256(StringView) -> String` | SHA-256; используется также для устранения дублей auto |
| `SetFaultPoint(StringView) -> bool` | Однократная диагностическая инъекция |
| `FrameCapture::Request() -> bool`, `IsReady() -> bool` | Запрос/опрос показанного кадра независимо от рендертехники |
| `FrameCapture::FetchPng(uint32, uint32) -> String`, `Cancel()` | Получение/освобождение readback |
| `Sprite::SetTextureData(const String&) -> bool` | Декодирование миниатюры из памяти |
| `SaveStorageProbe::Run/PrepareRestart/VerifyRestart() -> String` | Результат стенда/инструкция оператору |

Группы и ID принимают только ASCII буквы, цифры, `_`, `-`, длину 1..64. Разделители, абсолютные пути и `..` отвергаются до доступа к слотам. Контроллер игры обращается к хранилищу только через group/slot IDs. Перечисление не зависит от `m_slots`; перед явным чтением/перезаписью игра закрывает кешированный объект.

## Каталог и физический формат

Windows: `%LOCALAPPDATA%/<Organization>/<ApplicationName>/Save/`. При заданном ApplicationInfo.project внутри Save добавляется каталог с именем проекта: `%LOCALAPPDATA%/<Organization>/<ApplicationName>/Save/<Project>/`. Для остальных платформ базовый каталог предоставляет Platform::GetUserDataDirectory(). Каталог отдельно монтируется в VFS. При изменении пути кеш открытых слотов очищается; отдельного identity и API его установки нет.

```text
Save/[Project/]
  manual/p01_s01/
    current                    # UTF-8: gen_12, без перевода строки
    published_gen_11           # UTF-8: 1, квитанция публикации
    published_gen_12
    gen_11/
      state.json
      metadata.json
      files/thumbnail.png
    gen_12/
      state.json
      metadata.json
      thumbnail.png
  quick/q01/ ... q06/
  auto/a01/ ... a06/
  profile/main/                # тот же протокол, без thumbnail.png
```

`gen_N` монотонен внутри существующего физического слота, с учётом брошенных поколений. `metadata.generation` содержит N. Отдельный `metadata.sequence` задаётся AS как следующий номер группы, определяет latest/ring и не зависит от локализованной даты.

Минимальный индекс metadata.json: storageVersion=1, slotId, group, generation, createdUtc, hasState, payloadSha256/payloadLength и files[]. Каждая запись files содержит path, length, sha256; физический путь — gen_N/files/<path>. state.json создаётся только при hasState=true. Миниатюра — один из файлов, выбранный AS, и может вообще отсутствовать. У пользовательских файлов произвольные имена и содержимое; JSON, PNG или определённый размер не требуются.

SetMetadata добавляет поля приложения в индекс. Зарезервированы служебные поля, перечисленные выше. Игра задаёт schemaVersion=1, contentVersion, playTimeSeconds, currentCommandId, sceneTitle, storyResource, hasThumbnail и sequence. Enumeration добавляет displayTime и recovered. Вызов GetFile("thumbnail.png") получает файл для игрового UI; специального thumbnail API у SaveSlot нет.

`state.json` — UTF-8 JSON, результат `SerializeScriptValue` согласованной копии AS-значения, разобранный как JsonValue. Логический GameState — `NovelState { core: NovelCore, rollbackCheckpoints }`; `core.schemaVersion=1`. В core находятся все поля контракта: command/phase/stack, variables, presentation, audio, history, boundary, ending, playtime. Профиль — отдельный MenuProfile schemaVersion=1 со settings/firstRun/readCommandIds.

Физическая JSON-обёртка — существующий формат сериализатора AS: объектная таблица с `objectId`, `definition`, `objectType`, `properties[] { name, scriptType, value }`; контейнеры используют `items` и `key/mapped`, Value сохраняет `payloadType`. ObjectId — порядковый номер определения в документе, не адрес VM/объекта сцены. Нативные компоненты и стек исполнения в снимок не входят.

При чтении сначала проверяются length/SHA-256 и только затем разбирается необязательное state.json. Для каждого пользовательского файла проверяются manifest path, length и SHA-256 без декодирования его формата. По умолчанию у движка нет заданного бюджета чтения; SetReadLimit(0) отключает ограничение. DeathLovers отдельно задаёт бюджет 80 MiB и проверяет в AS payload ≤64 MiB и PNG ≤4 MiB, signature/IHDR, 384×216/RGB8. PNG создаётся штатным кодировщиком; его декодирование для отображения выполняет Sprite. Требования к картинке принадлежат игре.


Запись создаёт новое поколение; flush каждого файла подтверждается; новое поколение перечитывается; current заменяется штатным VFS::WriteFileAtomic. На Windows replace использует существующий `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`. Файлы опубликованного поколения не изменяются на месте. После успеха остаются новое и предыдущее валидное поколение. Квитанции находятся рядом с поколениями: fallback исключает полностью записанное, но ещё не опубликованное поколение.

Current имеет приоритет. Если он повреждён или указывает на испорченные данные, выбирается самое новое валидное поколение с квитанцией, выставляется recovered и пишется `SaveSlot::Load() : recovered ...`. Будущая storage schema отвергается без fallback/перезаписи. Если сбой произошёл после replace, current уже доказывает публикацию даже без новой квитанции; перед последующей перезаписью она сохраняется для previous.

## Поведение AS и совместимость

Manual: p01_s01..p10_s06, 10 страниц × 6. Сохранение в пустую ячейку доступно при наличии игрового состояния; загрузка пустой ячейки отключена. Перезапись, удаление и загрузка поверх активной сессии проходят Confirm; отмена очищает pendingAction. QuickLoad также подтверждается поверх сессии.

Quick: q01..q06. Выбирается последний совместимый валидный GameState по sequence. Несовместимые документы не используются как latest. Auto: a01..a06, Choice, первый yield после выбора и 300 секунд narrative playtime от предыдущего auto. Auto не работает в главном меню, игровом меню, modal или без фокуса приложения. Для сравнения дублей берётся SHA-256 core с обнулённым playTimeSeconds; остальные поля сохраняются. После ошибки auto не повторяется каждый кадр: следующая попытка — новый Choice или новый интервал.

Снимок копируется целиком в одном вызове; позиции аудио считываются в копию. Сериализация не проходит по изменяемой сессии между кадрами. Ready-запрос ждёт yield. На время захвата исполнение блокируется, меню/Confirm/Notify/quick/debug UI отсутствуют в миниатюре, диалог и персонажи остаются. Отсутствие readback/PNG или timeout не публикуют слот. Масштабирование миниатюры выполняется после центрированного вписывания в 16:9.

Перед загрузкой создаётся отдельный candidate. Проверяется точное соответствие типизированного документа его повторной сериализации, затем schema/contentVersion, IDs, диапазоны, история ≤250, checkpoints ≤100, stack ≤1000, текстовые индексы/паузы, Choice и ресурсы. Повторная сериализация исключает молчаливую загрузку пропущенных/неизвестных полей через defaults. Ресурсы готовятся в невидимом поддереве; до готовности previous session/view остаются доступны для восстановления. После подготовки аудио заменяются состояние и представление; команды runner не переисполняются. При ошибке аудио восстанавливается прежнее аудио. Controls блокируются, повторный click не запускает вторую операцию. На успехе меню закрывается, skip/auto отключаются, ввод блокируется до отпускания клавиш/мыши.

Profile читается при старте, настройки применяются к mixer/fullscreen. Изменения настроек и прочитанности откладывают запись на 0.5 с; профиль flush при выходе/возврате в главное меню и Choice. Прочитанность глобальна и не загружается из GameState. Неизвестная версия/повреждённый профиль не перезаписывается defaults; пользователю показывается ошибка. Ошибки записи не выдают уведомление «сохранено».

Текущий формат: storageVersion=1 и GameState/ProfileState schemaVersion=1. Reader поддерживает только этот формат хранения. Смена contentVersion явно отвергается. schemaVersion метаданных контролируется AS, а неизвестный storageVersion — движком. Debug-fixture разрешён только при developmentRuntime=true, с явно разрешённым storyResource; произвольный путь из metadata не загружается.

Изменение C++ API: FlushSlot/DeleteSlot и File::Flush теперь возвращают bool. Нужна полная пересборка потребителей. Кодогенерация должна обновить binding новых методов/классов. Новые cpp автоматически подхватываются после reload CMake. `SaveSystem.generated.hpp`, `FrameCapture.generated.hpp`, `SaveStorageProbe.generated.hpp` включены в соответствующие cpp; SaveStorage не содержит SR_CLASS и не требует generated header.

## Статическая проверка

- Сверены VFS WriteFileAtomic/ReplaceFile, File, Platform, JsonValue, Scene::InstanceFromFile, GridLayoutGroup, Sprite/Texture, framebuffer и Pipeline pixel-range API с реализациями.
- Форматы prefab/srtech сверены с существующими нативными ресурсами и generated serialization FrameBufferPass (`data.frameBufferName`).
- saves-fixture.json разобран как JSON: 17 команд, 7 переменных, отсутствующих command targets — 0. Это проверка данных, не запуск сценария.
- Проверены сохранение previous до publish, чтение с диска вместо кеша, отсутствие изменения текущего поколения и отсутствие публикации при сбое миниатюры.
- В новом C++ коде нет STL-контейнеров/анонимных namespace и прямых сравнений float через ==. Использование std ограничено алгоритмами, временем, атомиками и существующими потоками файлов.
- Тесты/сборка не выполнялись. Подтверждения визуального результата, компиляции AS и корректного GPU readback пока нет.

## Пользовательская проверка

1. Перезагрузить CMake, пересобрать движок обычным способом с кодогенерацией. Запустить DeathLovers пользователем. Проверить, что нет ошибок компиляции AS и основное меню выглядит как раньше.
2. Открыть главное меню без сохранений: пустые ячейки загрузки disabled; QuickLoad в сессии disabled до первого quick save. Начать игру, открыть Save, проверить шесть ячеек и страницы 1..10.
3. Сохранить ADV в середине печати и на explicit wait. Полностью завершить процесс, запустить снова, Load из главного меню. Ожидание: тот же visibleIndex/phase/pause, без повторного history/начисления очков. Повторить с NVL, Choice, WaitingTransition, callStack глубиной >1 и loop music/fade.
4. Сохранить в ту же manual ячейку: Confirm/No не меняет файлы; Confirm/Yes создаёт следующее поколение. Load поверх сессии и Delete также подтверждаются. Double click не запускает две операции. После успешной загрузки не переносится click/Enter/Ctrl.
5. Выполнить 7 QuickSave, проверить q01..q06, перезапустить процесс и QuickLoad: выбирается последний по sequence. Аналогично пройти несколько Choice и проверить кольцо auto, а также интервал 5 минут активной истории. В menu/modal время для auto не накапливается.
6. Проверить thumbnail.png: 384×216 RGB, тот же игровой диалог/персонажи, без меню и modal. Повторить в широком, узком и полноэкранном окне. Отдельно проверить ориентацию изображения и соответствие цвета на используемом GPU backend.
7. Изменить громкости, fullscreen и скорость текста, подождать >0.5 с и полностью перезапустить приложение. Настройки и прочитанность должны сохраниться. Загрузка старого GameState не откатывает профиль.

### Дисковый стенд

В Inspector MenuNavigation включить developmentRuntime и перезапустить сцену пользователем. В верхней панели доступны StorageProbe / PrepareRestart / VerifyRestart. Полный результат — поле runtimeProbeReport. Стенд пишет только в группу probe текущего каталога Save/[Project/], не меняя ApplicationInfo. Временные файлы также находятся внутри probe.

Кнопка SavesFixture запускает saves-fixture-v1. Точки проверки: cmd_90000102 — переход 3 с с loop music; cmd_90000103 — NVL с `{w}` и `{w=0.5}`; cmd_90000104 — накопленный NVL; cmd_90000112 — ADV, midprint/explicit wait и callStack `[cmd_90000108, cmd_90000111]` глубины 2; cmd_90000108 — один доступный choice_90000101; cmd_90000114 — WaitingTimer с inputWait; cmd_90000115 — второй переход. На cmd_90000112 roots=1/plague=0, на cmd_90000114 roots=1/plague=2. Сохранить каждую точку в отдельную manual ячейку, полностью перезапустить процесс и загрузить её из главного меню. DevelopmentRuntime должен оставаться включённым для разрешённого доступа к fixture. При повторной загрузке history, stack и счётчики не растут.

StorageProbe вызывает реальный SaveSystem/VFS. Дополнительно проверяются null/bool/int/number/string/array/object с метаданными по умолчанию, files-only слот без state.json, пользовательская schemaVersion=999, бинарный файл 5 MiB с нулевыми байтами, ASCII имя и каталог с точкой, импорт/экспорт без изменения байтов, бюджет чтения, обрыв после файлов, fallback повреждённого файла и удаление файла. Ожидаемые строки:

```text
generic values + optional metadata + binary import/export + file atomicity/fallback + read budget: PASS
SHA256 + IDs + disk round-trip: PASS
interruption after_state -> current revision 1: PASS
interruption after_metadata -> current revision 1: PASS
interruption before_marker -> current revision 1: PASS
after_marker -> current revision 3: PASS
invalid marker -> latest published revision 4, recovered=true: PASS
damaged current payload -> previous revision 3, recovered=true: PASS
future schema -> rejected, bytes preserved: PASS
enumeration + two-generation retention + delete: PASS
PASSED_IN_THIS_RUN
```

Для проверки именно другого процесса нажать PrepareRestart, полностью закрыть приложение, запустить снова и нажать VerifyRestart. Ожидается RESTART_PAYLOAD_VALID с revision 42; факт перезапуска подтверждает оператор. Смена сцены или повторное нажатие без завершения процесса не считается такой проверкой.

`SetFaultPoint` принимает after_state / after_files / after_metadata / before_marker / after_marker либо пустую строку для сброса. Первые четыре имитируют прекращение записи до публикации, возвращая ошибку. after_marker прекращает post-publish обслуживание и возвращает успех, поскольку replace уже совершён. Это детерминированные точки инъекции, а не реальное убийство процесса/отключение питания.

### Ручная инъекция

- Сделать два сохранения одного слота, закрыть процесс. Заменить current на некорректный ID, запустить и загрузить: ожидается recovered из последнего опубликованного поколения и уведомление. Изменить байт state.json актуального поколения: ожидается fallback на previous. Повредить оба поколения: ожидается ошибка и доступная прежняя сессия.
- Скопировать валидное поколение в новый gen_N без published_gen_N и не менять current: новая папка не должна считаться опубликованным сохранением.
- В metadata актуального поколения выставить storageVersion=999: движок отвергает загрузку и перезапись, файлы остаются. В игровом слоте schemaVersion=999 отвергает AS; в универсальном слоте приложения это допустимое пользовательское поле. Для contentVersion заменить только metadata.contentVersion: AS сообщает несовместимость без изменения активной сессии.
- Запретить текущему пользователю запись в каталог тестового слота и попробовать сохранить: ожидается ошибка, старый current остаётся прежним, уведомления «сохранено» нет. Вернуть разрешения и повторить запись.
- Через debugger остановиться непосредственно перед/после WriteFileAtomic(current), завершить процесс и перезапустить. До replace читается old; после — new. Сохранить реальные логи, runtimeProbeReport и скриншоты результата для приёмки.

### Примеры универсального использования

Скаляр: создать JsonValue, вызвать SetInt(42), передать его в slot.SetState и FlushSlot. Других пользовательских полей не требуется. Для строк, bool и массивов используются соответствующие операции JsonValue.

Только файлы: OpenSlot("worlds", "one"), ImportFile("region/world.bin", sourcePath), FlushSlot. После нового открытия HasState=false, HasFile("region/world.bin")=true, ExportFile восстанавливает исходные байты. Можно совместить эти файлы с SetState или очистить состояние через RemoveState. Изображения ничем не отличаются от остальных пользовательских файлов.

## Оставшаяся приёмка и следующий этап

Не подтверждены запуском все пункты пользовательской проверки, реальный аварийный stop процесса, ошибки ОС, GPU capture/ориентация/цвет, native/AS компиляция и отсутствие повторного SFX/очков при дисковой загрузке. Имитирующий стенд написан, но не запускался.

Для следующего этапа доступны сохраняемые history/rollbackCheckpoints и транзакционная загрузка без исполнения команд. Любое изменение состава AS-состояния должно явно учитывать schemaVersion и строгую проверку дерева; скрытые миграции не добавлять.
