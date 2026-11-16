# 03. Универсальные API движка для AngelScript

## Цель и вход

Зависимость: 02. Прочитать общие контракты. Закрыть конкретные пробелы UI, текста, аудио и работы с данными, не внедряя логику новеллы в C++. Поддерживать существующую GameObject/Component-модель.

## Проверяемые исходники

- `Engine/libs/Scripting/src/Scripting/AngelScript/AngelScriptBindings.cpp`, `AngelScriptBehaviourInstance.cpp`, `AngelScriptValueSerialization.cpp` и соответствующие заголовки.
- `Engine/inc/Engine/UI/UIButton.h`, UIScrollRect/UIScrollBar и cpp.
- `Engine/libs/Graphics/inc/Graphics/Font/TextMesh.h`, TextMeshDetails, FontAsset и cpp. Старый Text не выбирать автоматически: основной renderer нового UI — TextMesh.
- `Engine/libs/Graphics/inc/Graphics/Types/Geometry/Sprite.h` и cpp.
- `Engine/libs/Audio/inc/Audio/Types/AudioSource.h`, backend и публичные audio interfaces.
- `Engine/libs/Utils/inc/Utils/Game/SaveSystem.h` и cpp, существующие сериализаторы/VFS/Input.

Рефлексия не гарантирует, что каждый C++ метод уже доступен AS. Нужны реальные зарегистрированные сигнатуры, корректные типы и lifetime. Не редактировать сгенерированные файлы вместо первоисточника.

## UI-события

1. Обеспечить надежный вызов метода AS-компонента из UI: target reference, имя/идентичность метода, диагностируемые неверная сигнатура и уничтоженный target. Через тот же путь должны работать повторное создание сцены и hot reload без dangling handles.
2. Button: hover/pressed/selected/disabled; interactable; click при отпускании той же кнопки над исходной активной целью после ее нажатия. Нажал внутри/отпустил снаружи — без click; нажал снаружи/отпустил внутри — без click. Keyboard submit формирует один click.
3. Один центральный маршрутизатор ввода UI: hit testing с учетом transform, canvas, mask, z/sibling order и raycast blocking. Верхний modal перехватывает события; нижние кнопки и новелла их не получают.
4. Pointer capture при drag; focus navigation Tab/Shift+Tab/стрелки; Enter/Space submit; Escape cancel верхнего окна. Input event, закрывший окно, не должен в том же кадре продвинуть реплику.
5. Универсальные Slider и Toggle: значение, изменение, interactable, клавиатура, сериализуемые ссылки. Radio-поведение настроек строится AS-группой. Не маскировать scrollbar под slider, если его semantics отличаются.
6. ScrollRect/Scrollbar: колесо, drag, bounds, clip, нормализованная позиция, изменение размера content после layout. UI не зависит от случайного Update-порядка.

## Текст

Основной контракт TextMesh: UTF-8, перенос по ширине, явные переводы строк, размеры min/preferred для layout, range styles и visible grapheme count. Grapheme — пользовательский символ; комбинируемые знаки и кириллица не должны разрываться по байтам UTF-8.

Форматированные диапазоны: bold, italic, underline, strike, relative font size, color/alpha. Диапазоны могут перекрываться; стиль после конца реплики не протекает. Нужны одинаковые glyph positions при печати и показе полного текста: скрытые символы участвуют в окончательной раскладке, чтобы строка не прыгала.

В renderer передавать готовые диапазоны/метаданные; Ren’Py-теги и временные `{w}/{nw}/{cps}` обрабатываются AS. Общий эффект символов принимает индекс, время, амплитуду и параметры; wave/shake реализуются GPU/SRSL либо существующим универсальным механизмом. Индекс эффекта относится к видимым glyph, не к байтам и не к символам тегов. Не пересоздавать font atlas/VBO на каждый напечатанный символ, если достаточно изменить предел видимости.

Добавить доступ к метрикам, границам и событию изменения layout-input. Подготовить Pangolin font asset без подмены на default при отсутствии исходного файла; недостающий шрифт должен диагностироваться.

## Аудио

Предоставить AS универсальные Play/Stop/Pause/Resume, resource assignment, loop, volume, playback position get/seek и признаки завершения. Непозиционное воспроизведение обязательно. Управление fade — AS через эти операции; C++ tween можно использовать только как общий примитив, без знания команд новеллы.

Поддержать группы Music/Sfx/Voice и master mute через общую микшерную абстракцию либо существующий backend. Итоговая громкость — произведение master, группы, источника; настройка группы не стирает собственный fade volume источника. WAV и OGG обязательны. AIFF конвертировать офлайн только если реально используется, не добавлять новый runtime decoder ради неиспользуемого файла.

## Данные и ресурсы

Из AS должны быть доступны: чтение UTF-8 JSON-ресурса, типизированные primitive/array/object значения, диагностика parse errors, сериализация дерева значений и полное глубокое копирование. Использовать имеющуюся инфраструктуру; не вводить отдельный JSON parser для игры, если подходящий уже есть. Конкретный контейнер API и его сигнатуры записать в отчете для этапа 04.

Доступны создание/уничтожение объектов, применение prefab, изменение активности, sprite/material/resource, transform/layout properties, безопасные ссылки, получение времени/input. Их отсутствие закрыть здесь. Незагруженный resource ID вызывает ошибку с путем, не silent fallback. Файловые операции saves заканчиваются в этапе 07.

## Проверочный стенд

Создать тестовую сцену вне релизной стартовой сцены. AS показывает форматированный текст с переносом, динамически меняет его в fitter, нажимает button/slider/toggle, открывает modal, прокручивает clip, проигрывает и seek-ает OGG/WAV, читает и сериализует JSON-значения. Все назначения событий проходят тот же путь, что в игре, а не C++ shortcuts.

Подготовить meaningful проверки: click release semantics; modal input consumption; уничтожение target; повторное восстановление ссылок; text reflow; UTF-8; overlapping styles; seek/volume; глубокая копия state. Пользователь выполняет запуск согласно CLAUDE.md.

## Выход и приемка

`Reports/03_RESULT.md` включает таблицу «операция → реальный AS API → исходник регистрации → ограничение». Стенд должен обходиться без project-specific C++. Не оставлять stub-return success. Передать этапу 04 окончательные интерфейсы и пример ресурсов в нативном формате, не выдуманную API-псевдореализацию.
