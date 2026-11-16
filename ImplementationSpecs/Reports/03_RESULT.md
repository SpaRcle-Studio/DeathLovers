# Этап 03 — приёмка

Дата: 15.11.2026. Статус: **VERIFIED** в объёме проверенного пользователем Windows-стенда EngineApi.scene.

Пользователь подтвердил работу звука после установки pitch источника в 1 вместо 0 и сообщил, что остальные проверки также пройдены. Подтверждены исправления текста, декораций и визуальных элементов управления. Открытых замечаний по этому стенду нет; этап завершён. WrongSignature у кнопки Bad signature — ожидаемая диагностика отрицательного теста.

В сохранённой пользователем сцене pitch=1. Эта версия сохранена и в ImplementationArtifacts. Код движка после подтверждённого запуска не менялся. Агент не выполнял сборку и запуск. Android/iOS runtime-проверки не заявляются: заложенная поддержка pointer input не равна приёмке на этих устройствах.

Ниже сохранена история реализации и прежних статусов ожидания. Подробности исправлений: 03_FIXES.md. Переход к этапу 04 в этой задаче не выполнялся.

# Уточнение этапа 03: архитектура UI, mobile input и микшер

Дата: 15.11.2026. Статус: **AWAITING_USER_RUN**. Этот раздел описывает текущие API и заменяет соответствующие строки исходного отчета ниже; старый текст сохранен как история первоначальной реализации. Сборка, кодогенерация и runtime-проверки по-прежнему не выполнялись агентом.

## Исправления по замечаниям пользователя

- Добавлен Utils/UI/UIComponent — базовый Component для Canvas и UIControl. UIComponent владеет PrepareUIInput, AfterLayout и GetUIInputTarget. SceneUpdater регистрирует UI-компоненты в UIInputRouter, подготовка обходит этот реестр. В Component больше нет этих UI-хуков и InvokeEvent. Существующие layout-provider hooks для render/layout-компонентов оставлены общим контрактом этапа 02.
- Событие UIButtonEvent вызывает отраженный нативный метод либо Behaviour.InvokeEvent. Нет виртуальной UI-диспетчеризации в базовом Component. Интеграция с Behaviour находится в Engine/UI/UIControl.cpp, а не в Utils.
- UIInputRouter больше не опрашивает Input/MouseCode/KeyCode. Он принимает span PointerEvent и UINavigationState. Отдельный UIInputAdapter переводит клавиатурные команды в логические действия.
- PointerInput имеет переиспользуемые pending/frame буферы и thread-safe Submit. Идентичность указателя — device + pointerId; в событии есть device, phase, primary/secondary button, pressure, Screen/Client space, scroll и dragThreshold. У каждого указателя отдельный capture и drag candidate. Разные пальцы могут управлять разными контролами; второй палец не перехватывает уже занятый контрол.
- Android подает события напрямую из существующего ApplyAndroidInputEvent: отдельные ID, Down/Move/Up, давление, stylus hover/exit, mouse и wheel. Reset/ACTION_CANCEL отменяет захваты без click. Down/Up в одном кадре сохраняют порядок. Эмулированный touch-mouse не подается в UI второй раз. Client-координаты обрабатываются Canvas без desktop ScreenToClient. Порог touch drag учитывает DPI; аппаратный Back отображается на Escape/Cancel.
- PointerCancel не вызывает click; touch не оставляет hover после отпускания. Modal barrier остается до конца кадра, включая несколько pointer events в одном frame. Стабильная сортировка UI выполняется без временного heap-буфера stable_sort.
- AudioGroup enum и массив трех громкостей удалены. AudioMixerGroup — сериализуемая структура name/parent/volume/muted; в движке нет предопределенных имен групп. Группы добавляет проект. Пустая группа AudioSource подключается напрямую к master. Поддержаны настройка/перечисление групп, иерархия, mute, проверка parent и запрет циклов/удаления родителя с детьми. Неизвестная группа диагностируется; Play такого источника отклоняется.
- AS callback cache теперь полностью строится в CacheCallbacks при создании/замене instance: VM перечисляет void-методы без параметров, ключ — StringAtom имени. InvokeEvent не строит declaration, не конкатенирует строки и не вставляет методы в кеш на первом клике. Кеш очищается до освобождения старого instance при hot reload.

Подробный общий контракт находится в C:/Work/SREngine/Documentation/UIInput.md.

## Текущие API

| Операция | API | Где реализовано |
|---|---|---|
| Жизненный цикл UI | UIComponent::PrepareUIInput / AfterLayout / GetUIInputTarget | Utils/UI/UIComponent.h/cpp |
| Pointer stream | PointerInput::Submit / CancelAll / BeginFrame / GetEvents | Utils/Input/PointerInput.h/cpp |
| Маршрутизация | UIInputRouter::Process(Scene&, span<const PointerEvent>, const UINavigationState&) | Utils/UI/UIInputRouter.h/cpp |
| Координаты | Canvas::PointerToCanvasSpace / ContainsPointer / ClientToCanvasSpace | Graphics/UI/Canvas.h/cpp |
| События AS | bool Behaviour.InvokeEvent(const String &in) | Behaviour.h; AngelScriptBehaviourInstance::CacheCallbacks/InvokeEvent |
| Описание группы AS | AudioMixerGroup: name, parent, volume, muted | Audio/AudioMixer.h |
| Создать/удалить | bool AudioMixer.AddGroup(const AudioMixerGroup &in), RemoveGroup(const String &in) | AudioMixer.h/cpp; RegisterMembers |
| Проверить/перечислить | HasGroup(const String &in), GetGroupCount(), GetGroupName(uint) | AudioMixer.h/cpp |
| Иерархия | SetGroupParent(const String &in,const String &in), GetGroupParent(const String &in) | AudioMixer.h/cpp |
| Настройки | SetGroupVolume(const String &in,float), GetGroupVolume(const String &in), GetGain(const String &in), SetGroupMuted(const String &in,bool), IsGroupMuted(const String &in) | AudioMixer.h/cpp |
| Назначить источник | bool AudioSource.SetGroup(const String &in), String@ GetGroup() | AudioSource.h/cpp |

StringAtom в этих AS-сигнатурах использует существующий String binding. Произвольные имена интернируются при конфигурации, GetGain не строит строки в runtime. Итоговая громкость: master * source * произведение громкостей всех родителей и группы; любой group mute обнуляет только ее поддерево. AS-сигнатуры здесь сверены с кодом RegisterMembers, успешная runtime-регистрация еще ожидает пользовательского запуска.

## Стенд и совместимость

EngineApiProbe.as теперь сам создает пользовательские Effects и Interface (parent=Effects) через AudioMixerGroup и назначает источник в Interface. Это пример конфигурации проекта, не константы движка. Mix устанавливает source=0.75, master=0.5, Effects=0.8, Interface=0.5: backend source gain=0.3, итог при listener gain=1 — 0.15. Имена не образуют фиксированный enum и могут быть заменены/дополнены.

Нативный EngineApi.scene хранит строковый group=Interface и содержит явный AudioListener на Camera для проверки master gain. Тип и имена UIButtonEvent.object/method сохранены. .srproject и исходные требования не изменялись. Прямой API Component.InvokeEvent удален, актуальный скриптовый вызов — Behaviour.InvokeEvent; вызовы UI через сериализуемые события остаются прежними.

Для новых отражаемых UIComponent и AudioMixerGroup используется штатная кодогенерация: UIComponent.generated.hpp и существующий AudioMixer.generated.hpp (оба типа mixer объявлены в одном заголовке). PointerInput/UIInputAdapter не являются отражаемыми классами и не требуют generated include.

## Статические проверки и пользовательский запуск

Статически проверены:
- отсутствие PrepareUIInput/GetUIInputTarget/InvokeEvent в Component;
- отсутствие опроса MouseCode/KeyCode/Input в UIInputRouter;
- соответствие новых PointerEvent сигнатур интерфейса всем контролам, Screen/Client преобразования;
- Android source, reset/cancel и аппаратный Back; названия GetMethodCount/GetMethodByIndex/GetReturnTypeId/GetParamCount сверены с локальным angelscript.h;
- отсутствие AudioGroup enum и AudioGroup:: ссылок в исходниках Audio и актуальном AS-стенде;
- отсутствие построения declaration в InvokeEvent и вставки кеша на вызове;
- наличие локальных include-файлов и generated include UIComponent; поиск std:: в измененных файлах. Новые самостоятельные файлы не используют запрещенные STL-контейнеры; затронутые Input cursor-lock/text-event vectors заменены на Vector SREngine. Старые unrelated optional-интерфейсы Input не менялись.

Git status остается недоступен из-за ownership; safe.directory и глобальные настройки не менялись. Сборка/тесты/скрипты проекта не запускались.

Пользователю нужно перезагрузить CMake и пересобрать движок: добавлены новые cpp, изменены базовый класс UI, pointer signatures и mixer API. В дополнение к основным проверкам ниже:
1. На desktop повторить click release, drag, Tab/Submit, modal закрытие и hot reload. Убедиться, что старый AS event target работает после reload и первый click не строит declaration.
2. На Android одновременно двигать Slider одним пальцем и ScrollRect другим; отпустить один палец, продолжить второй. Контролы должны сохранять независимый capture.
3. Быстрый tap Down/Up внутри одного кадра дает один click; Up снаружи — ноль. ACTION_CANCEL, уход приложения в фон и потеря окна отменяют capture без click. После возврата новое касание работает.
4. На Android проверить drag вне rect, CanvasScaler/viewport/resize, отсутствие второго клика от эмулированной мыши; Back закрывает верхний modal и не продвигает игровой ввод в том же кадре.
5. В микшере создать еще одну произвольную группу/подгруппу. Изменение volume/mute родителя влияет только на ее поддерево и не изменяет AudioSource.GetVolume. Попытка создать цикл или назначить отсутствующую группу возвращает false с диагностикой. Прямое подключение к master — SetGroup("").

Ограничения: Android-путь подготовлен по существующему native input, но устройство агентом не запускалось. Нативный iOS-драйвер, отдельный Web multi-touch и gamepad adapter здесь не реализованы. Для них есть generic pointer stream и отдельное состояние навигации; контролы и маршрутизатор не требуют desktop API. Pinch/rotate recognizer не добавлялся.

## Измененные файлы этой доработки

- Engine/libs/Utils/inc/Utils/ECS/Component.h
- Engine/libs/Utils/src/Utils/ECS/Component.cpp
- Engine/libs/Utils/inc/Utils/UI/UIComponent.h
- Engine/libs/Utils/src/Utils/UI/UIComponent.cpp
- Engine/libs/Utils/inc/Utils/UI/IUIInputTarget.h
- Engine/libs/Utils/inc/Utils/UI/UIInputRouter.h
- Engine/libs/Utils/src/Utils/UI/UIInputRouter.cpp
- Engine/libs/Utils/inc/Utils/UI/UIInputAdapter.h
- Engine/libs/Utils/src/Utils/UI/UIInputAdapter.cpp
- Engine/libs/Utils/inc/Utils/Input/PointerInput.h
- Engine/libs/Utils/src/Utils/Input/PointerInput.cpp
- Engine/libs/Utils/inc/Utils/Input/InputSystem.h
- Engine/libs/Utils/src/Utils/Input/InputSystem.cpp
- Engine/libs/Utils/src/Utils/Platform/AndroidInput.cpp
- Engine/libs/Utils/src/Utils/Platform/AndroidInputEvents.cpp
- Engine/libs/Utils/src/Utils/World/SceneUpdater.cpp
- Engine/libs/Graphics/inc/Graphics/UI/Canvas.h
- Engine/libs/Graphics/src/Graphics/UI/Canvas.cpp
- Engine/inc/Engine/UI/UIControl.h
- Engine/src/Engine/UI/UIControl.cpp
- Engine/inc/Engine/UI/UIButton.h
- Engine/src/Engine/UI/UIButton.cpp
- Engine/inc/Engine/UI/UISlider.h
- Engine/src/Engine/UI/UISlider.cpp
- Engine/inc/Engine/UI/UIScrollRect.h
- Engine/src/Engine/UI/UIScrollRect.cpp
- Engine/inc/Engine/UI/UIScrollBar.h
- Engine/src/Engine/UI/UIScrollBar.cpp
- Engine/libs/Scripting/inc/Scripting/Base/Behaviour.h
- Engine/libs/Scripting/src/Scripting/AngelScript/AngelScriptBehaviourInstance.cpp
- Engine/libs/Audio/inc/Audio/AudioMixer.h
- Engine/libs/Audio/src/Audio/AudioMixer.cpp
- Engine/libs/Audio/inc/Audio/Types/AudioSource.h
- Engine/libs/Audio/src/Audio/Types/AudioSource.cpp
- Documentation/UIInput.md

Файлы проекта: Resources/DeathLovers/Scripts/Tests/EngineApiProbe.as, Resources/DeathLovers/Scenes/EngineApi.scene и этот отчет. Копия комплекта сохранена в ImplementationArtifacts/03/DeathLovers.

---

## Исходный отчет до замечаний пользователя (история; API выше имеет приоритет)

# Этап 03 — универсальные API движка

Дата: 15.11.2026. Статус: **AWAITING_USER_RUN**.

Подготовлены исходники движка и отдельный нативный стенд. Сборка, кодогенерация, компиляция AS, загрузка сцены, визуальные и звуковые проверки агентом не выполнялись. VERIFIED не заявляется. Отчет 02 прочитан; подтвержденные пользователем результаты этапа 02 сохранены. К этапу 04 агент не переходил.

## Реализация

UI использует общий UIInputRouter сцены перед Update игровых компонентов. Canvas подготавливает актуальный viewport/scale через PrepareUIInput; перед маршрутизацией выполняется очередь dirty layout. Контролы получают события централизованно, без собственного опроса мыши. Учитываются inverse-transform Canvas, маска TransformRect, priority и стабильный порядок иерархии при одинаковом priority. UIControl с raycastTarget=true служит также блокирующей поверхностью; focusable=false исключает ее из навигации. Interactable=false блокирует активацию и не пропускает raycast нижнему контролу.

Сохранен тип UIButtonEvent и его сериализуемые поля object/method; визуальные idle/hovered/pressed перенесены в базовый UIControl с прежними именами. Добавлены selected/disabled. Click вызывается только при отпускании захваченной кнопки мыши над исходной целью. Capture сохраняется вне rect; отключение/удаление цели и потеря фокуса приложения отменяют захват. Slider и Scrollbar имеют самостоятельную семантику. Drag с дочерней кнопки после порога 4 screen pixels передается ближайшему drag-контролу, например ScrollRect. Колесо всплывает к родительскому ScrollRect. Tab/Shift+Tab и стрелки меняют фокус, стрелки на slider/scrollbar меняют значение; Enter/Space отправляет один Submit по KeyDown. Верхний modal ограничивает допустимые цели своим поддеревом; Escape вызывает его сериализуемое событие cancel.

Путь события: UIButtonEvent::Invoke -> Component::InvokeEvent -> Behaviour::InvokeEvent -> BehaviourInstance::InvokeEvent. AngelScriptBehaviourInstance разрешает только void Name(), кеширует функцию по имени в текущем instance и исполняет ее через переиспользуемые контексты VM. При SetInstance кеш очищается до освобождения старого объекта; EntityRef хранит идентичность компонента, а не AS handle. Неверная сигнатура, отсутствующая/уничтоженная цель и ошибки исполнения диагностируются. C++-компоненты используют отраженные void-методы с проверкой параметров, возврата и condition.

Игровые AS-обработчики общего ввода обязаны проверять Scene.IsUIInputConsumed() перед продвижением. Флаг сохраняется до следующего прохода маршрутизатора, включая кадр закрытия modal. Сырые методы Input не изменены: флаг проверяется игровым потребителем. Пример есть в EngineApiProbe.Update.

TextMesh предоставляет layout-provider, перенос по словам и границам grapheme при слишком длинном слове, явные/пустые строки, min/preferred, bounds и revision входных метрик. SetLayoutDirty вызывается при изменении текста, диапазонов и шрифта; изменение матрицы инвалидирует геометрию без зацикливания layout. SetText очищает диапазоны предыдущей реплики, включая повторную строку с тем же содержимым. Скрытые символы участвуют в окончательной раскладке. SetVisibleGraphemeCount и SetCharacterEffect меняют uniforms, не геометрию и не атлас. Шейдер отсекает скрытые glyph, выполняет wave/shake; индекс эффекта исключает переносы строк и дополнительные декоративные quad.

TextStyle использует полуоткрытый диапазон [begin,end) в grapheme. Перекрытия: boolean-стили объединяются OR, relativeSize и RGBA перемножаются. Bold/italic синтезируются SDF-порогом/наклоном, underline/strike — дополнительными quad. Это не подбор отдельных файлов bold/italic. Геометрия разбивается по font/renderType/page, текстурные batch используют соответствующие FontAtlas-текстуры; декоративные линии на пробелах не требуют glyph в атласе. GetVBO сохраняет первый выделенный идентификатор как ключ очереди при смене набора активных страниц. FontAsset.BuildText/GlyphKey принимают StringView без промежуточной std::string.

Sprite получил явное назначение текстуры, layout-provider для назначенной текстуры с учетом PPU и invalidation при reload. Нативные свойства материала остаются доступны; добавлен отраженный SetMaterial(Path).

Аудио управляется через AudioSource; pause/resume/seek/позиция выполняются в SoundManager на звуковом потоке и в OpenAL backend. Seek проверяет конечность, неотрицательность и продолжительность PCM. Команды pause/seek допускаются также до создания backend source. Непозиционный режим задает spatialize=Off, relative=1, нулевую позицию и rolloff=0 для итоговых playback params. Неизменяемые числовые opaque handles не переиспользуют адрес освобожденного PlayData. После естественного завершения старый handle не может управлять новым источником.

AudioMixer: master/mute применяются через существующий глобальный gain listener, группы — в gain источника. Итог: master * group * source (при стандартном listener gain=1). GetVolume возвращает собственную громкость/fade источника. Изменения групп рассылаются подписчикам AudioSource, включая продолжающие играть отключенные компоненты; исходная громкость не перезаписывается. Поддержка WAV/OGG использует существующие декодеры. AIFF runtime decoder и преобразование неиспользуемых AIFF не добавлялись.

JsonValue построен на SerializationNode/JsonDeserializer/JsonSerializer. Добавлены raw JSON value parse/serialization в существующую инфраструктуру; формат нативных документов с именованным корнем сохранен. null теперь имеет отдельный тип, а не превращается в пустую строку. Допускаются корневые object/array/primitive/null, проверяются trailing data, возвращается bool и выводятся исходные line/column; LoadResource добавляет путь. Чтение идет через FileSystem/VFS. Get/At/Clone возвращают независимые глубокие копии; вложенное изменение нужно записывать обратно через Set/SetAt. Save/Load JsonValue сохраняет дерево как JSON-строку через штатный сериализатор. Ключи ограничены штатным SerializationId: максимум 127 байт; превышение диагностируется вместо усечения.

## Операция → AS API → регистрация → ограничение

Сигнатуры ниже выведены из первоисточников регистрации. Фактическое успешное создание этих bindings ожидает пользовательской сборки/запуска. AngelScriptBindings::RegisterFactory собирает метаданные фабрики; RegisterMembers регистрирует @method и accessors @property через asCALL_GENERIC. Имена типов формирует AngelScriptBindingHelpers::Identifier. Нативные объекты, включая String и математику, представлены reference wrappers. Поэтому возврат JSON/String/Math — handle, а вход нативного значения — const Type &in; SharedPtr-параметр использует Type@+.

| Операция | Реальный AS API | Источник метаданных / регистрации | Ограничение |
|---|---|---|---|
| Событие компонента | bool Component.InvokeEvent(const String &in) | Utils/ECS/Component.h; AngelScriptBindings::RegisterMembers | void Name(), без аргументов |
| Событие AS | тот же Component.InvokeEvent; сериализуемый UIButtonEvent.object/method | Behaviour.cpp; AngelScriptBehaviourInstance.cpp | кеш сбрасывается при замене instance |
| Кнопка | UIControl.SetInteractable(bool), UIControlState GetState(); свойства onClickEvents, idle/hovered/pressed/selected/disabled | UIControl.h, UIButton.h; RegisterMembers | событие назначается компоненту Behaviour, не ScriptBehaviour handle |
| Modal | UIControl.modal, focusable, raycastTarget, onCancelEvents | UIControl.h | верхний по priority/иерархии modal |
| Потребление ввода | bool Scene.IsUIInputConsumed() | Utils/World/Scene.h; RegisterMembers | raw Input требует этого guard в игровой логике |
| Slider | void UISlider.SetValue(float), float GetValue(); minValue/maxValue/keyboardStep/wholeNumbers/vertical/reverse; onValueChanged | UISlider.h | callback читает значение через GetValue |
| Toggle | void UIToggle.SetValue(bool), bool GetValue(); onValueChanged | UIToggle.h | radio-группа остается в AS |
| Scrollbar | void UIScrollBar.SetValue(float), float GetValue(), void SetSize(float) | UIScrollBar.h | размер thumb и направление независимы от Slider |
| ScrollRect | void SetNormalizedPosition(const FVector2 &in), FVector2@ GetNormalizedPosition() | UIScrollRect.h | x: слева направо; y: сверху вниз; viewport снабжается RectMask2D |
| Текст | void TextMesh.SetText(const String &in); font/fontSize/wordWrap | TextMesh.h | текст без Ren'Py-тегов |
| Диапазоны | void AddStyle(const TextStyle &in), void ClearStyles() | TextStyle.h, TextMesh.h | [begin,end), compositing описан выше |
| Печать | void SetVisibleGraphemeCount(uint), uint GetGraphemeCount() | TextMesh.h | счетчик grapheme, без rebuild VBO |
| Метрики | float GetMinWidth/GetPreferredWidth/GetPreferredHeight(); FRect@ GetTextBounds(); uint64 GetLayoutInputRevision() | TextMesh.h; ILayoutElement/OnTextDirty | preferred обновляется layout-проходом; bounds вычисляется без GPU |
| Эффекты | void SetCharacterEffect(float time,float waveAmplitude,float shakeAmplitude,float frequency) | TextMesh.h; text-mesh.srsl | GPU; параметры и часы задает AS |
| Звук | bool Play/Pause/Resume(), void Stop(), bool Seek(float), float GetPlaybackPosition(), bool IsPlaying/IsPaused/HasFinished() | AudioSource.h; RegisterMembers | Play принимает запрос; backend-ошибки диагностируются отдельно |
| Назначение звука | void SetPath(const String &in), void SetLoop(bool), void SetSpatialize(SpatializeMode), void SetVolume(float), float GetVolume() | AudioSource.h | path относителен Resources; PlayOnEnable=false для ручного старта |
| Микшер | AudioMixer::Instance(); SetMasterVolume(float), SetMuted(bool), SetGroupVolume(AudioGroup,float), GetGroupVolume(AudioGroup) | AudioMixer.h; RegisterFactory singleton binding | Music/Sfx/Voice; master не стирает fade |
| JSON | bool JsonValue.Parse(const String &in), bool LoadResource(const String &in), String@ ToJson(), JsonValue@ Clone() | JsonValue.h; RegisterMembers | существующий парсер; максимум глубины 512, ключ 127 байт |
| JSON-чтение | JsonValueKind GetKind(), bool IsValid(), uint GetCount(), bool Has(const String &in), JsonValue@ Get(const String &in), JsonValue@ At(uint), String@ GetKey(uint) | JsonValue.h | отсутствующий ключ/тип диагностируется, возвращается invalid value |
| JSON-значения | MakeObject/MakeArray/SetNull(), SetBool(bool), SetInt(int64), SetNumber(double), SetString(const String &in); GetBool/GetInt/GetNumber/GetString | JsonValue.h | Number принимает только finite; int64 сохранен отдельно |
| JSON-изменение | bool Set(const String &in,const JsonValue &in), SetAt(uint,const JsonValue &in), Append(const JsonValue &in) | JsonValue.h | передача по значению, без алиасов и циклов |
| Объекты | Scene.InstanceGameObject(const String &in), InstanceFromFile(const String &in), GameObject.CreateChild(const String &in), SceneObject.Destroy/SetEnabled/SetParent | Scene.h, GameObject.h, SceneObject.h; RegisterMembers | штатный prefab loader |
| Ссылки | EntityRef<T>.get/set, ResourceRef<T>.get/set | AngelScriptBindings::RegisterMembers wrapper path | штатные ID и проверки жизненного цикла |
| Transform/layout | TransformRect.SetAnchoredPosition/SetSize(const FVector2 &in), SetPivot(const FVector2 &in), SetAnchors(const RectAnchors &in), GetLayoutSize() | TransformRect.h; RegisterMembers | семантика этапа 02 |
| Sprite/material | bool Sprite.SetTexturePath(const String &in), IRenderComponent.SetMaterial(const String &in) | Sprite.h, IRenderComponent.h; RegisterMembers | ошибки загрузки с путем |
| Input/время | Input::Instance().GetKeyDown/GetMouseDown/...; Update(float dt) | InputSystem.h; AngelScriptRuntime/BehaviourInstance | игровые часы накапливает AS из dt |

## Файлы движка

Относительно C:/Work/SREngine:

- `Engine/libs/Utils/inc/Utils/ECS/Component.h`
- `Engine/libs/Utils/src/Utils/ECS/Component.cpp`
- `Engine/libs/Utils/inc/Utils/ECS/SceneObject.h`
- `Engine/libs/Utils/inc/Utils/ECS/TransformRect.h`
- `Engine/libs/Utils/inc/Utils/World/Scene.h`
- `Engine/libs/Utils/src/Utils/World/Scene.cpp`
- `Engine/libs/Utils/inc/Utils/World/SceneUpdater.h`
- `Engine/libs/Utils/src/Utils/World/SceneUpdater.cpp`
- `Engine/libs/Utils/inc/Utils/UI/IUIInputTarget.h`
- `Engine/libs/Utils/inc/Utils/UI/UIInputRouter.h`
- `Engine/libs/Utils/src/Utils/UI/UIInputRouter.cpp`
- `Engine/libs/Utils/inc/Utils/Localization/Grapheme.h`
- `Engine/libs/Utils/src/Utils/Localization/Grapheme.cpp`
- `Engine/libs/Utils/inc/Utils/Serialization/BaseSerialization.h`
- `Engine/libs/Utils/inc/Utils/Serialization/JsonSerialization.h`
- `Engine/libs/Utils/src/Utils/Serialization/JsonSerialization.cpp`
- `Engine/libs/Utils/inc/Utils/Serialization/JsonValue.h`
- `Engine/libs/Utils/src/Utils/Serialization/JsonValue.cpp`
- `Engine/libs/Scripting/inc/Scripting/Base/BehaviourInstance.h`
- `Engine/libs/Scripting/inc/Scripting/Base/Behaviour.h`
- `Engine/libs/Scripting/src/Scripting/Base/Behaviour.cpp`
- `Engine/libs/Scripting/inc/Scripting/AngelScript/AngelScriptBehaviourInstance.h`
- `Engine/libs/Scripting/src/Scripting/AngelScript/AngelScriptBehaviourInstance.cpp`
- `Engine/inc/Engine/UI/UIControl.h`
- `Engine/src/Engine/UI/UIControl.cpp`
- `Engine/inc/Engine/UI/UIButton.h`
- `Engine/src/Engine/UI/UIButton.cpp`
- `Engine/inc/Engine/UI/UISlider.h`
- `Engine/src/Engine/UI/UISlider.cpp`
- `Engine/inc/Engine/UI/UIToggle.h`
- `Engine/src/Engine/UI/UIToggle.cpp`
- `Engine/inc/Engine/UI/UIScrollRect.h`
- `Engine/src/Engine/UI/UIScrollRect.cpp`
- `Engine/inc/Engine/UI/UIScrollBar.h`
- `Engine/src/Engine/UI/UIScrollBar.cpp`
- `Engine/libs/Graphics/inc/Graphics/Font/TextMesh.h`
- `Engine/libs/Graphics/src/Graphics/Font/TextMesh.cpp`
- `Engine/libs/Graphics/inc/Graphics/Font/TextMeshDetails.h`
- `Engine/libs/Graphics/src/Graphics/Font/TextMeshDetails.cpp`
- `Engine/libs/Graphics/inc/Graphics/Font/TextStyle.h`
- `Engine/libs/Graphics/src/Graphics/Font/TextStyle.cpp`
- `Engine/libs/Graphics/inc/Graphics/Font/FontAsset.h`
- `Engine/libs/Graphics/src/Graphics/Font/FontAsset.cpp`
- `Engine/libs/Graphics/inc/Graphics/Font/Glyph.h`
- `Engine/libs/Graphics/src/Graphics/Font/Glyph.cpp`
- `Engine/libs/Graphics/inc/Graphics/UI/Canvas.h`
- `Engine/libs/Graphics/src/Graphics/UI/Canvas.cpp`
- `Engine/libs/Graphics/inc/Graphics/Types/IRenderComponent.h`
- `Engine/libs/Graphics/src/Graphics/Types/IRenderComponent.cpp`
- `Engine/libs/Graphics/inc/Graphics/Types/Geometry/Sprite.h`
- `Engine/libs/Graphics/src/Graphics/Types/Geometry/Sprite.cpp`
- `Engine/libs/Graphics/inc/Graphics/Types/Geometry/IndexedMesh.h`
- `Engine/libs/Graphics/src/Graphics/Types/Geometry/IndexedMesh.cpp`
- `Engine/libs/Graphics/inc/Graphics/Particles/ParticleEmitter.h`
- `Engine/libs/Graphics/src/Graphics/Particles/ParticleEmitter.cpp`
- `Engine/libs/Graphics/src/Graphics/Types/Mesh.cpp`
- `Resources/Engine/Shaders/UI/text-mesh.srsl`
- `Engine/libs/Audio/inc/Audio/AudioMixer.h`
- `Engine/libs/Audio/src/Audio/AudioMixer.cpp`
- `Engine/libs/Audio/inc/Audio/Types/AudioSource.h`
- `Engine/libs/Audio/src/Audio/Types/AudioSource.cpp`
- `Engine/libs/Audio/inc/Audio/SoundManager.h`
- `Engine/libs/Audio/src/Audio/SoundManager.cpp`
- `Engine/libs/Audio/inc/Audio/Impl/OpenALSoundContext.h`
- `Engine/libs/Audio/src/Audio/Impl/OpenALSoundContext.cpp`
- `Engine/libs/Audio/inc/Audio/SoundContext.h`
- `Engine/libs/Utils/inc/Utils/TypeTraits/TypeTraits.h`

Для новых отражаемых UIControl/UISlider/UIToggle/TextStyle/JsonValue/AudioMixer созданы пары h/cpp и включены соответствующие Codegen/*.generated.hpp. Сгенерированные файлы не редактировались.

## Файлы игры

- Resources/DeathLovers/Scenes/EngineApi.scene — отдельная нативная SRA-сцена, не стартовая сцена.
- Resources/DeathLovers/Scripts/Tests/EngineApiProbe.as — только AS: 13 JSON-проверок, форматированный текст, печать, reflow, события UI, modal, звук и guard ввода; дополнительный EngineApiReceiver.
- Resources/DeathLovers/Tests/engine-api.json — UTF-8 fixture с object/array/bool/int/double/string/null.
- Resources/DeathLovers/Fonts/Pangolin.font, Pangolin.ttf, Pangolin-OFL.txt — нативный asset и исходный шрифт с лицензией.
- Resources/DeathLovers/Audio/Tests/Door.wav, main_menu.ogg, README.md — неизмененные исходные аудиоресурсы для стенда.
- ImplementationSpecs/Reports/03_RESULT.md — этот отчет.

Воспроизводимая подготовленная копия комплекта: C:/Work/SREngine/ImplementationArtifacts/03/DeathLovers. .srproject, исходные ТЗ и ресурсы оригинала Ren'Py не изменялись.

SHA-256 ресурсов:
- Pangolin.ttf: A48DB64EADC589C2E9F14A4BA79EED82A438C7F620F929DD19E352C20B2A922E.
- Door.wav: 8A3E55BB2482A1C885BAE0F4788E23F88D55317F38437FFD5E13A5E1B46E98A6.
- main_menu.ogg: A30D4B6E6600738749EC755D93341C7235B7CAF44DF6796260BE832A8D7860FA.

## Совместимость и ограничения

- Сериализуемые имена событий/визуальных ссылок UIButton сохранены; сами клики намеренно перенесены с mouse-down на mouse-up.
- GetVBO теперь возвращает Optional SREngine; все три override (TextMesh, IndexedMesh, ParticleEmitter) и потребители регистрации/Bind согласованы. Это C++ API-изменение требует пересборки зависимых модулей. GetIBO и прочие старые unrelated STL-интерфейсы не мигрировались.
- SoundManager использует StringView/Optional/Vector вместо затронутых STL-типов; opaque handle больше не адрес PlayData.
- null существующего JSON parser больше не является пустой строкой. Новый LoadValueFromStringView не меняет контракт старого LoadFromStringView с именованным корнем.
- Grapheme-путь строго валидирует UTF-8 и объединяет распространенные combining blocks, кириллические combining marks, variation selectors, emoji modifiers/ZWJ и пары regional indicators, CRLF. Это не полная таблица свойств UAX #29 для всех письменностей: сложные Indic/Hangul-кластеры за пределами русскоязычного v1 не заявляются.
- Синтетические стили и shader/atlas batches требуют визуальной проверки на реальном backend. Размер/положение GPU wave/shake и декоративных линий не входят в GetTextBounds.
- Router обходит иерархию для hit-test; отдельные профилировочные замеры не проводились. Dirty-layout остается отдельной очередью.
- Успешная загрузка нативной сцены и фактический финальный AS API dump еще не подтверждены. Интерфейсы для этапа 04 переданы как реализация в исходниках, без фиктивного утверждения об успешном runtime.

## Выполненные статические проверки

Прочитаны README, 00_CONTRACTS, 03_ENGINE_API и Reports/02_RESULT; применимые CLAUDE/AGENTS. Проверены реальные сигнатуры регистрации, контексты и lifetime AS, метаданные layout, audio thread/backend и JSON parser. Пары новых отражаемых h/cpp и generated includes проверены. Локальные includes Utils/Graphics/Audio/Engine/Scripting в измененных файлах существуют. Новые самостоятельные файлы проверены поиском std:: на запрещенные контейнеры; старые unrelated контейнеры в больших файлах не переписывались.

JSON fixture статически разобран ConvertFrom-Json. SRA fixture проверен по структуре/отступам и entity IDs: 108 определений, 25 ссылок, нет повторных определений и неразрешенных ссылок. Это не загрузка сцены движком. Хеши скопированных бинарных ресурсов получены штатным SHA-256.

Git status недоступен из-за dubious ownership; safe.directory не менялся. Коммитов нет. Сборка, CMake, CI/codegen.py, тестовые бинарники и скрипты проекта не запускались. Сообщение PASS в AS-файле — ожидаемый результат будущего запуска, а не доказательство выполненной агентом проверки.

## Пользовательская проверка

1. Перезагрузить CMake штатным способом, затем полностью пересобрать движок и зависимые модули с AngelScript и Audio. Это нужно из-за новых cpp и измененного C++ GetVBO API. В логах регистрации AS не должно быть failed registration/unsupported signature для API этой таблицы. Сохранить сформированный Cache/Scripts/AngelScriptAPI.txt.
2. Открыть существующий проект DeathLovers. Открыть DeathLovers/Scenes/EngineApi.scene, запустить Play. Стенд не назначать release/start scene. Ожидание: форматированный Pangolin, печать без прыжков строк, в Status сообщение JSON о 13 проверках; failures=0, jsonChecks=13 в Inspector Behaviour.
3. Click release: записать clicks. Нажать внутри Click release и отпустить снаружи; нажать снаружи и отпустить внутри — счетчик не меняется. Нажать/отпустить внутри той же кнопкой — +1. Нажать вторую кнопку мыши и отпустить ее во время захвата первой — нет ложного click.
4. Tab/Shift+Tab и стрелки: видимый state изменяется в Inspector; focused Slider/Scrollbar меняются стрелками. Enter/Space на Button/Toggle дают ровно одно событие на KeyDown. Interactable=false: disabled state, нет событий. Для проверки визуальных children назначить idle/hovered/pressed/selected/disabled штатными EntityRef в Inspector.
5. Открыть modal, нажимать расположенные под ним Click/Slider/Toggle, колесо и Space. Нижние счетчики и rawAdvanceCount не растут. Escape и Close закрывают modal; rawAdvanceCount не меняется также в кадре закрытия. Следующий отдельный Space вне UI может увеличить rawAdvanceCount. Проверить вкладку приложения/Alt+Tab во время drag: захват отменяется.
6. Drag Slider/Scrollbar за пределы их rect с удержанием, отпустить за пределами: значение меняется с capture, после release дальнейшее движение не меняет значение. Прокрутить Scroll до границ колесом и drag, уменьшить/увеличить ScrollContent через layout/fitter — bounds и thumb пересчитываются, содержимое за RectMask2D не видно. Для nested drag добавить кнопку в ScrollContent: drag более 4 screen pixels прокручивает, без ложного click.
7. Text reflow несколько раз: ширина 850/420, vertical fitter меняет высоту после layout. Plain text убирает все предыдущие стили; Repeat text вновь показывает пересечения bold/italic/underline/strike/size/color/alpha. Ё должен раскрываться целиком, UTF-8/кириллица не повреждаются; пустая строка сохраняется. На печати меняется visible limit, glyph positions полной реплики стабильны. Измерить GetTextBounds/Preferred и layout revision при смене текста/шрифта; убедиться, что только visible count не вызывает AllocateVBO/BuildText.
8. WAV, OGG, Pause/Resume, Seek 1 sec, Stop: оба формата звучат непозиционно; во время Pause позиция не растет; после Seek позиция около 1 секунды; Stop прекращает звук. Mix устанавливает source=0.75, Sfx=0.4, master=0.5: source сохраняет 0.75, backend source gain=0.3 и listener master=0.5 при listener gain=1, итог 0.15. Toggle mute заглушает master и снимает mute без потери source volume. Проверить естественное завершение при loop=false и HasFinished.
9. Test target увеличивает received у Receiver. Bad signature выводит expected void WrongSignature(), без выполнения метода. Destroy target затем Test target выводит unavailable target без падения. Выгрузить/загрузить сцену заново: ссылка снова разрешается и Test target работает. Изменить AS и выполнить штатный hot reload: события работают через новый instance; старые function handles не используются.
10. Для отрицательных JSON-проверок вызвать Parse с незакрытым объектом, trailing data и ключом более 127 байт: false/диагностика, IsValid=false, без принятия частичного документа. Проверить roundtrip корневых array/primitive/null. Изменить вложенную копию и записать обратно: оригинал не меняется. Несуществующий JSON/audio/font/texture path должен давать диагностику с путем; отсутствующий Pangolin не заменяется default.
11. Проверить 1280x720, 1920x1080 и resize во время drag/modal. Зафиксировать результаты и ошибки в этом отчете. Численный эталон этапа 02 не изменялся; при затронутом поведении повторить соответствующие cases, без изменения допусков.

Непройденные критерии: все перечисленные сборочные/runtime/визуальные/звуковые проверки ожидают пользователя. После их подтверждения можно уточнить статус VERIFIED в проверенном объеме и закрепить AS API dump для этапа 04.
