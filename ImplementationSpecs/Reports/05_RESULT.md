# Этап 05 — главное меню и навигация

## Исправления после пользовательского запуска — 16.11.2026

Статус: **FIXED / AWAITING_USER_RECHECK**. Нижний первоначальный отчет описывает первую поставку; актуальные уточнения здесь. Пользователь подтвердил запуск AS и прислал кадры с ошибками представления. Исправленная версия агентом не собиралась и не запускалась.

- Музыка: srengine.log содержит `OpenALSoundContext::Play(): source=1, playing=true, gain=0.2, listenerGain=1, pitch=0`. В сцену добавлены явные нативные audio-параметры, включая pitch=1; MenuNavigation.Start также вызывает SetPitch(1). Существующие SetPitch/GetPitch открыты AS через @method в AudioSource.h. Это исправляет нулевую скорость воспроизведения, а не создает второй источник.
- Материалы: первая поставка ошибочно помещала uniforms/samplers рядом с defaultShader вместо внутрь MaterialShaderData. Они не загружались и были удалены штатным сохранением сцены. Исправлены MainMenu.scene и все три префаба; color/outlineWidth/outlineColor теперь лежат в defaultShader.uniforms. Sprite samplers дополнительно содержат явный путь diffuse. Восстановлены зеленые заголовки, черная обводка и черный цвет BlackBars. Видимая шахматная текстура по краям была текстурой BlackBars, умноженной на дефолтный белый цвет; это не доказательство отдельной неисправности GPU-дескрипторов при ресайзе.
- Все 89 PNG в DeathLovers/UI получили imageType=UI, mipLevels=1, ClampToEdge. Семь parallax PNG сохраняют NEAREST. Проверено по Texture.cpp: UI выбирает RGBA8_UNORM, Albedo при включенном sRGB выбирал RGBA8_SRGB. Цветовые изображения новеллы из Images этим не изменялись.
- Масштаб: AspectRatioFitter получил opt-in referenceSize для режима FitInParent. В Novel задано 1920×1080: внутренний layout остается в reference units, а fit задает единый равномерный масштаб относительно Canvas. CanvasScaler match=.5 сохранен; AS не пересчитывает раскладку. При referenceSize=(0,0) прежняя семантика существующих компонентов не меняется.
- Preferences: исходные названия без текстовых [X]/[ ]; radio/check foreground PNG, отдельные Label с левым отступом 27, MenuOptionVisual для выбранного/hover состояния. Заголовки не переносятся по словам. Уточнены native layout-группы: General cells 338×235, Sliders 675×475, межрядовый отступ 60, slider 525×38, handle 15×38. Контент имеет отступы L480/R30/T195/B90. Названия/порядок не изменены.
- В Preferences, Load, About, Help и SessionStart добавлена боковая навигация по исходному desktop navigation. Открытие другого submenu заменяет текущий без перезапуска сцены/музыки. MenuSession.activeScreen задает выделение текущего пункта. Общее состояние профиля сохранено.
- Предупреждения EntityRef в логе соответствуют пяти handle объектов ползунков. UISlider раньше разрешал ссылки из range/setter/OnPostLoad до загрузки дочерних объектов. RefreshVisual теперь ожидает активности компонента; отложенное обновление выполняется в AfterLayout после загрузки дерева. Отсутствующая runtime-ссылка по-прежнему диагностируется.

Статическая проверка исправлений: `05_FIXES_STATIC.json` — 581 определение entityId, 74 ссылки, дубликатов и висячих ссылок нет; 133 материала имеют корректную вложенность, 16 event method names сохранены. У всех 89 UI metadata проверен imageType=UI. Пройдены diff --check и чтение новых сигнатур/Codegen includes; std:: контейнеры не добавлялись. Исходная версия сцены была сохранена пользователем штатным редактором: правки сделаны поверх актуального файла, возврата к старому сериализованному снимку не было.

Для повторной проверки пересобрать движок (AudioSource AS bindings, UISlider, AspectRatioFitter), затем заново загрузить сцену/ресурсы, чтобы применились метаданные текстур и исправленные материалы. Старую открытую сцену перед перезагрузкой не сохранять поверх новых файлов. Ожидается: музыка с pitch=1; черные поля после ресайза; зеленые заголовки с черной обводкой; боковая навигация; целые надписи и видимые ползунки/отметки; отсутствие пяти преждевременных EntityRef warnings. Сравнить Settings с Reference/settings.png и MainMenu с Reference/main menu.png; повторить шесть viewport, fullscreen и 20 циклов настроек. Эти runtime-результаты пока не получены.

Дата: 16.11.2026. Статус: **IMPLEMENTED / AWAITING_USER_RUN**. Сборка, кодогенерация, AS-компиляция и движок не запускались согласно CLAUDE.md. Структурные проверки выполнены чтением файлов; они не заменяют runtime-приемку.

## Игра и точка входа

`.srproject` теперь указывает `DeathLovers/Scenes/MainMenu.scene`. Тестовая EngineApi.scene сохранена.

- `Resources/DeathLovers/Scenes/MainMenu.scene`: нативный SRA SceneAssetLogic; камера/AudioListener, один Canvas/CanvasScaler 1920×1080, ScaleWithScreenSize/MatchWidthOrHeight/0.5; Novel с AspectRatioFitter FitInParent 16:9 и RectMask2D, отдельный черный фон вокруг него.
- `Prefabs/UI/MenuButton.prefab`, `ModalFrame.prefab`, `ParallaxBackdrop.prefab`: нативный ScenePrefabLogic. Это независимые шаблоны без внешних event references. В стартовой сцене находятся настроенные сериализованные экземпляры UI, события адресованы компоненту MenuNavigation. Самодельного загрузчика сцен и runtime-раскладки нет.
- `Scripts/UI/MenuNavigation.as`: MenuNavigation, интерфейс IMenuSessionStarter. Единственный владелец main/submenu/modal, музыки и переходов; без загрузки новой сцены при открытии меню.
- `Scripts/UI/MenuParallax.as`: MenuParallax. Все вычисления мыши, clamp и движения — AS; ссылки на семь TransformRect кешируются в Start.
- `Scripts/UI/MenuProfile.as`: MenuSettings, MenuProfile, глобальный MenuSession::profile на время жизни AS-модуля.
- `Scripts/UI/MenuButtonVisual.as`: MenuButtonVisual, цвета idle #888888 и hover/focus #66e0c1 через TextStyle. Ввод и события кнопок обрабатывает штатный UIInputRouter.
- Семь `UI/parallax/prlx_*.png.meta`: NEAREST, mipLevels=1, ClampToEdge. PNG/аудио/шрифт оригинала не переписывались.

Расположение задают TransformRect anchors/pivot, LayoutGroup, ContentSizeFitter, LayoutElement, GridLayoutGroup, AspectRatioFitter, RectMask2D. AS не расставляет кнопки вручную и не назначает ширину отдельных слов. Navigation использует общую измеренную ширину, spacing=6, нижний центральный alignment .95 в координатах Ren’Py. Настройки имеют группы Display/Skip и Text/Audio с переносом колонок нативным Flexible GridLayoutGroup; ползунки шириной 525, колонки 675, отступ между рядами 60. Длинные About/Help и настройки прокручиваются UIScrollRect.

## Переходы и жизненный цикл

Главное меню: «Начать», «Загрузить», «Настройки», «Об игре», «Помощь», «Выход». Save и debug-кнопок нет.

| Действие | Результат |
|---|---|
| Начать | IMenuSessionStarter.StartSession(), если подключен; иначе явно технический SessionStart с возвратом |
| Загрузить | Load: «Сохранений пока нет.», без фиктивных слотов |
| Настройки | Preferences; значения синхронизируются из профиля без сброса |
| Об игре | About: исходные 10 атрибуций звуков/URL, указание переноса на SREngine, лицензия Pangolin |
| Помощь | Только текущие команды меню: мышь, Tab/Shift+Tab, стрелки, Enter/Space, Escape, прокрутка, режим экрана |
| Вернуться / Escape | Закрыть верхний modal, затем submenu; Escape в MainMenu ничего не меняет |
| Выход в MainMenu | Engine.RequestQuit(), без Confirm |
| QuitFromGame(origin) | Confirm: Да / Нет; Escape соответствует Нет, focus возвращается origin |
| ShowNotify(message, origin) | Общий modal Notify; закрытие кнопкой/Escape или через 3.25 секунды |
| ReturnToMainMenu() | Закрыть modal/submenu, показать главное меню, восстановить единственный музыкальный источник |

Submenu и modal имеют штатный UIControl.modal. Фоновый экран не получает UI-ввод. Focus задается через UIButton.Focus() и очередь UIInputRouter на следующем кадре. Барьер 0.1 секунды защищает переходы от повторной активации открывшим нажатием; подтверждение выхода нельзя активировать исходным нажатием. Порядок обхода контролов соответствует порядку дерева/визуальному порядку групп.

Музыка: один AudioSource `Canvas/MenuMusic`, playOnEnable=false; AS задает путь `DeathLovers/Audio/music/main_menu.ogg`, loop, группу Music и вызывает Play один раз. Подменю не уничтожают и не перезапускают источник. При успешном запуске runtime музыка останавливается; OnDestroy освобождает воспроизведение. Настройки используют группы Music/Effects/Voice и master mute.

## Профиль и передача следующим этапам

MenuProfile: schemaVersion=1, firstRun=false после применения начальных настроек, settings:MenuSettings, readCommandIds:JsonValue (массив строк ID). Диск отсутствует до этапа 07. Профиль создается один раз в AS-модуле; повторное открытие меню не пересоздает его. Горячая перезагрузка всего модуля и перезапуск приложения пока не сохраняют профиль.

settings: music_volume=.2, sfx_volume=.2, voice_volume=1, text_cps=30, afm_time=15, pixel_voice=true; mute/fullscreen/skip_unseen/skip_after_choices/skip_transitions=false. Имена полей сохраняются при подключении диска. Умножения громкости при каждом открытии нет. Текущая сцена не исполняет skip/auto/pixel voice: она сохраняет настройки для runtime.

Этап 06 должен установить MenuNavigation.sessionStarter в реализацию IMenuSessionStarter, подключить успешный StartSession к Story entry и представлению, использовать профиль и аудиогруппы, вызывать QuitFromGame с исходной кнопкой и ReturnToMainMenu при возврате. SessionStart — временный экран, не законченное релизное поведение.

Этап 07 должен загрузить/сохранить schemaVersion/settings/firstRun/readCommandIds в application data, заменить пустое содержимое Load настоящими слотами и связать выбранный слот с восстановлением сессии. Сохранение в Resources не добавлялось.

## Движок и фактические API

- `Engine.h/.cpp`: RequestQuit(), SetFullscreen(bool), IsFullscreen(); RequestQuit вызывает штатный StopEngine, teardown остается главному циклу. Контейнер окон заменен на SR_UTILS_NS::Vector.
- `Engine/UI/UIControl.h/.cpp`: Focus(); передает UIControl через SceneUpdater.RequestUIFocus в UIInputRouter.RequestFocus. Очередь применяется после сбора активных modal/targets и проверяет доступность/focusable.
- `Utils/UI/UIInputRouter.h/.cpp`, `Utils/World/SceneUpdater.h`: очередь запроса focus без второго обработчика input.
- `Utils/ECS/TransformRect.h/.cpp`: SetVisualOffset(FVector2), только изменение render matrix и дочерних matrix dirty. Anchors/size/layoutRect не изменяются, LayoutRebuilder::MarkDirty не вызывается. Используется только декоративными слоями, отдельно от кнопок.
- `Graphics/UI/Canvas.h`: существующие ScreenToCanvasSpace и CanvasToLayoutPoint открыты рефлексии/AS через @method; преобразование учитывает viewport/window/CanvasScale.
- `Graphics/Window/BasicWindowImpl.h`, `Window.cpp`, `Win32Window.h/.cpp`: ранее пустые Window.SetFullScreen/IsFullScreen делегируют платформе. Windows реализует borderless fullscreen на текущем мониторе и восстановление WINDOWPLACEMENT/style/header. Запрос передается оконному потоку через PostMessage. Остальные платформы сохраняют дефолтное поведение; они вне v1. DPI-cache использует SR_UTILS_NS::Optional.
- `Resources/Engine/Shaders/UI/text-mesh.srsl`: общие outlineWidth/outlineColor для SDF, default width=0 сохраняет прежний вид остальных материалов. Меню задает черную обводку шириной 3 через нативные материалы; stroke заголовка задает AS TextStyle.begin=16/end=21/strike=true.

Новых C++ файлов нет; ручных generated.hpp и изменений as.predefined нет. Соответствующие существующие cpp уже включают свои Codegen/*.generated.hpp. Нужна пересборка движка с обычной кодогенерацией, ручной reload CMake из-за новых cpp не требуется. Префабы и сцена используют существующий SRA-формат. В C++ не добавлено специфики DeathLovers.

## Сравнение с Reference и дефекты

Сверены UI_REFERENCE, исходные screens.rpy/options.rpy/gui.rpy, фактический main menu.png, размеры/пути ресурсов. Семь слоев/порядок/factor 0,-20,40,-60,80,-100,120; prescale arguments 1.1,1,1.1,1.1,1.1,1.1,1.1, effective factor=0 scale=1. Инициализация normalized mouse в центре; offset*(1-abs(offset))*.002; Y-down преобразуется в месте вычисления визуального смещения один раз. Период .025, без временного сглаживания; вне viewport clamp, при потере focus состояние не обновляется.

D001 исправлен только в AS-представлении: Python/global не переносится. Изменение внесено в Reference/DEFECTS.md. Важное расхождение источников: оригинал растягивает PNG 2594×1080 в 1920×1080, тогда как 05_MAIN_MENU запрещает искажение пропорций. Выбран native EnvelopeParent с центральной обрезкой лишней ширины, prescale сохранен. Это не обещание пиксельного совпадения с растянутым кадром.

Название сохранено с зачеркнутым «юбовн». Версия оригинала не задана: главная строка версии пустая, в About явно указано отсутствие значения; 1.0 из закомментированной строки не используется (D008). Исходные атрибуции звуков сохранены, утверждение «сделано с Ren’Py» заменено сведениями о переносе. Полная лицензия Ren’Py не включалась, его код не поставляется. Pangolin-OFL.txt сохранен.

## Проверки и пользовательский запуск

`05_static.json`: 4 нативных SRA-ресурса; в сцене 377 определений entityId и 44 ссылки, дубликатов/висячих ссылок нет. Проверены 16 имен void event methods, 18 путей ресурсов, один Canvas/CanvasScaler/AudioSource. Геометрия шести viewport в JSON — только арифметика ожидаемого fit, не экспорт движка. Проверены новые сигнатуры по исходникам, std:: в изменениях, конфликтные маркеры и git diff --check. Результатов AS/рендера/звука нет.

1. Пересобрать SREngine обычным способом. Открыть DeathLovers/.srproject и MainMenu.scene, включить игровой режим. В опубликованной сборке mainScene уже установлен. Проверить отсутствие ошибок AS и неизвестных типов/событий в логах.
2. Проверить порядок/названия шести кнопок, отсутствие Save/debug, заголовок со strike и обводкой; сравнить с Reference/main menu.png с учетом описанного отличия aspect. Проверить края/буквы и пропорции.
3. Проверить 1920×1080, 1280×720, 1366×768, 2560×1440, 1024×768, 2560×1080. DPI 96/144/192. Новелла 16:9, поля черные; прокрутка настроек/About/Help и перенос колонок работают.
4. В центре/четырех углах и вне viewport проверить направление/амплитуду слоев и отсутствие черных разрывов; hit rect кнопок не двигается. Потерять focus: последнее положение сохраняется. Меню не должно каждый тик параллакса пересчитывать layout.
5. Проверить Tab/Shift+Tab/стрелки/Enter/Space, hover, Escape и Вернуться. После закрытия экрана focus возвращается к исходной кнопке. Первое нажатие не активирует новый экран.
6. Открыть/закрыть Preferences 20 раз; менять громкость/mute/pixel voice/text_cps/afm_time/skip. Значения сохраняются в памяти, играют одна музыка и один AudioSource; scene object count возвращается к исходному. Повторного input handler нет.
7. Переключить «Полный»/«Оконный», включая окно на втором мониторе; проверить восстановление размеров/позиции, viewport и hover. Проверить общий master mute и громкость музыки.
8. Load должен быть пустым, Start — явно техническим. Проверить About/Help и прямой Выход из MainMenu. После подключения этапа 06 дополнительно проверить QuitFromGame/Confirm, ShowNotify и восстановление focus активной игровой кнопки; до подключения они не имеют технических кнопок в релизном меню.

Остаток приемки: сборка/AS, реальные шесть viewport, screenshots, звук, fullscreen/мониторы/DPI, modal/input/focus и 20 циклов проверяются пользователем. Они не объявлены пройденными. Коммиты и глобальные настройки Git не менялись, исходная Ren’Py-игра и ранее существовавший ImplementationArtifacts не изменялись.
