# Этап 02 — layout

Дата: 15.11.2026. **Численная проверка, dirty scheduling и ручная проверка тестовой сцены: VERIFIED в проверенном объеме.** Полная матрица платформенных DPI/viewport отдельно не подтверждена. Этап 03 не выполнялся.

## Подтвержденные результаты пользователя

Пользователь повторно выполнил compare.py: **PASS, 0 differences**. Прочитан сохраненный Reference/LayoutCases/comparison.json: status=PASS, layoutCases=512, scalerCases=53, errors=[]. Подтверждено совпадение всех экспортированных состояний initial/dynamic/stable, включая отсутствие дрейфа после 100 rebuild, в пределах исходных допусков. Ожидания 53 scaler cases по-прежнему source-derived, не отдельные измерения физического DPI в Unity.

Пользователь также передал два сообщения **LayoutComparison::CheckDirtyScheduling() : PASS.** Подтверждены проверки idle, равных значений, объединения изменений, активности, resize, reparent/sibling order, независимых roots и удаления pending root. Успешный запуск подтверждает сборку и выполнение соответствующих инструментов пользователем; агент ничего не запускал. Дополнительного повторения этих же численных проверок сейчас не требуется.

Пользователь вручную проверил редактор и сообщил: «вроде все работает, проблем с ходу не увидел». Проверочная сцена: C:/Work/SREngineProjects/3DNovel2/Resources/Scenes/Main.scene, 56 676 байт, SHA-256 EE15CDF7D2D09165A46B564626EFD569085227E433D85F94F463F08D89F71D46 на момент чтения. На приложенном скриншоте видны Canvas, Scroll View/Viewport/Content с Item, LayoutGroup и ContentSizeFitter, выделение Savefiles. Это принято как ручная проверка данной сцены без замеченных проблем; отдельные результаты для каждого DPI/viewport, сценария ввода и профилировочные замеры пользователь не перечислял. Агент сцену не запускал и не изменял. Скриншот предоставлен в сообщении, отдельный файл изображения в Reference не создавался.

Ранее описанные ниже ошибки и запросы пересборки — история исправлений; текущий PASS заменяет их прежний статус ожидания. Полное визуальное и платформенное соответствие не выводится из этих результатов.

## Исправление после пользовательского запуска экспорта

Пользователь выполнил compare.py на 512 layout и 53 scaler cases: comparison.json содержит FAIL, 60 расхождений. 54 относятся к dynamic/stable состояниям inactive: первоначально выключенный объект пропускался Awake, а экспортер после включения вызывал только CheckActivity, которая пропускает еще не пробужденные компоненты. В LayoutComparison.cpp перед dynamic CheckActivity добавлен Awake(false,true), в соответствии с порядком SceneUpdater::Build. Остальные 6 расхождений (2 aspect_EnvelopeParent и 4 физических scaler в сантиметрах) вызваны SerializeFloat с %.6g: JSON терял значащие цифры. В Utils/Common/ToString.h формат изменен на %.9g для сохранения float при сериализации. Допуски comparator и эталонные результаты не менялись. На предоставленном запуске остальные 510 layout cases и 49 scaler cases не имели зарегистрированных расхождений; исправленные файлы агентом не собирались и не запускались. Требуется пересобрать, заново экспортировать оба SREngine JSON и повторить прежнюю команду compare.py. unity-results.json и scaler-expected.json можно сохранить.

Unity exporter остановился на Invalid alignment. Статическая проверка показала, что все явно заданные alignment в JSON допустимы; проблема связана с обработкой отсутствующих inline-блоков JsonUtility. В cases.json добавлены явные presence flags для optional-блоков и dynamic parent/sibling; schemaVersion поднята до 2. UnityLayoutExport.cs использует эти flags вместо проверок вложенных ссылок на null, проверяет версию входа и выводит конкретные значения при ошибке alignment. Параметры всех 512 случаев сохранены. Пользователю требуется обновить копию UnityLayoutExport.cs в Assets/Editor и выбрать новый cases.json. Unity агентом не запускалась, устранение исключения ожидает подтверждения.

Повторный запуск пользователем дошел до удаления fixtures и вызвал EntityController::Unregister() с invalid ID. Причина в экспортере: AddComponent регистрирует сущность, затем Load настроек из JSON без entityId восстанавливает default ID, оставляя прежнюю регистрацию в контроллере. В LayoutComparison.cpp десериализатор fixtures теперь получает AddDontLoadTag("Inspector"): существующий @dontSaveTags(Inspector) у Entity::m_entityId исключает ID также из загрузки через CanLoadByTags в кодогенерации. Это сохраняет идентичность компонентов при initial и dynamic загрузке настроек. Общий Unregister и его assert не менялись. Статически сверены поле Entity, механизм тегов и все три пути Load(input) экспорта; сборка и повторный запуск агентом не выполнялись. После пересборки нужно перезапустить редактор, чтобы не повторять экспорт в сцене с уже нарушенными регистрациями. Успешная очистка fixtures и экспорт пока ожидают подтверждения.

Пользователь запустил Export Cases и получил assert Transform::GetGlobalScale() is not implemented. Цепочка TransformRect → родительский Transform3D доходила до базовой заглушки: Transform3D не переопределял GetGlobalScale. В Engine/libs/Utils/inc/Utils/ECS/Transform3D.h и src/Utils/ECS/Transform3D.cpp добавлены override и кеш глобального масштаба, согласованные с существующим TransformRect: масштаб родителя умножается на локальный; без родителя возвращается локальный. Кеш сбрасывается существующим m_dirtyScale через UpdateTree при смене масштаба/иерархии. Экспортер и инструкция с host Transform3D сохранены. Проверены объявление, реализация и invalidation; новых STL-контейнеров нет. Исправление агентом не собиралось и не запускалось. Требуется пересборка и повторный Export Cases; успешный экспорт пока не подтвержден.

## Уточнения пользователя

Старых ресурсов, требующих миграции, нет. По явному указанию пользователя удалены миграции, layout version markers, legacy-флаги и соответствующие ветки fitter/group/scaler/aspect/rect. Это указание заменяет прежнее требование миграции в ТЗ для данной реализации. Исходные ТЗ сохранены, текущие значения читаются непосредственно.

Полный покадровый обход сцены заменен очередью dirty UI-корней в SceneUpdater. На неизменном кадре layout не обходит деревья и не вычисляет метрики. HashSet объединяет повторные уведомления; корень, покрываемый другим queued ancestor после reparent, не перестраивается повторно. Контекст и очереди сохраняют capacity.

Для dirty-корня список активных layout-участников собирается один раз; четыре фазы работают с плоскими буферами: X measure → X assign → Y measure → Y assign. Self controllers выполняются перед группами. Transform-записи самого прохода не порождают повторную очередь; новые явные изменения параметров во время прохода откладываются в следующий batch. Неизмененные setters группы не вызывают invalidation.

Повторные dynamic_cast удалены из layout. GameObject проверяется по метаклассу, TransformRect — через IsSameOrInherited, затем используется static_cast. Layout-интерфейсы не имеют отражаемых метаклассов: Component предоставляет виртуальные GetLayoutElement/GetLayoutController/GetLayoutIgnorer с override в шести существующих layout-классах. Это не требует RTTI или списка всех concrete-классов в resolver. Единственный прежний dynamic_cast в Canvas::OnAttached для неотражаемого RenderScene оставлен: он выполняется при подключении компонента, а не в layout-проходах.

CanvasScaler кеширует результат по viewport, DPI и изменениям параметров; log/pow при неизменном вводе не повторяются каждый кадр.

## Измененные файлы движка

Пути относительно C:/Work/SREngine. Для пар перечислены общая часть имени и каталоги inc/src.

- Engine/libs/Utils: ECS/TransformRect.h/cpp — offsets, anchoredPosition/sizeDelta, sizing по осям, presets, согласованное чтение полей без миграций.
- Engine/libs/Utils: UI/ILayoutElement.h, LayoutUtility.h/cpp, LayoutRebuilder.h/cpp — интерфейсы, общий выбор метрик, фазы и буферы.
- Engine/libs/Utils: UI/LayoutGroup.h/cpp, GridLayoutGroup.h/cpp, LayoutElement.h/cpp, ContentSizeFitter.h/cpp, AspectRatioFitter.h/cpp, LayoutTestMetrics.h/cpp — H/V/Grid, metrics, fitter и уведомления о свойствах; без legacy.
- Engine/libs/Utils: World/SceneUpdater.h/cpp — очередь корней, deduplication, подавление повторного пересчета, счетчик выполненных rebuild. Прежние std::vector в этом классе заменены на Vector SREngine.
- Engine/libs/Utils: ECS/Component.h/cpp — прямые layout accessors, SetLayoutDirty, invalidation после загрузки.
- Engine/libs/Utils: ECS/Transform.h/cpp — одно уведомление layout на UpdateTree, отдельная рекурсия матриц без повторных уведомлений.
- Engine/libs/Utils: ECS/SceneObject.cpp — invalidation обеих сторон reparent, dirty/activity и удаления детей.
- Engine/libs/Utils: ECS/GameObject.h — TryGetTransform без ленивого создания transform при проверке dirty-очереди.
- Engine/libs/Utils: Serialization/BaseSerialization.h — чтение целочисленных JSON numbers как float/double.
- Engine/libs/Graphics: UI/Canvas.h/cpp — scale/physical units, same-frame resize, inverse coordinates/hit test, кеш scaler.
- Engine: UI/LayoutComparison.h/cpp — экспорт geometry/scaler и CheckDirtyScheduling.
- Engine: GUI/SceneTools.h, GUI/SceneViewer.cpp, GUI/PropertyDrawers/TransformRectPropertyDrawer.cpp — шесть viewport, Inspector offsets и debug-метрики.
- Engine/src/Engine/UI: UIButton.cpp, UIScrollRect.cpp, UIScrollBar.cpp — hit test/scroll через общий scale/inverse transform.

Уведомления подключены к transform, свойствам groups/grid/fitter/aspect/reflow, metrics, OnPostLoad, регистрации/снятию компонентов, активности, hierarchy/sibling changes и viewport. Новые Text/Image providers этапа 03 должны переопределять Component::GetLayoutElement() и вызывать SetLayoutDirty при изменении входных метрик или сбросе кеша текста/шрифта.

## Файлы игры и baseline

Reference/UNITY_BASELINE.md фиксирует com.unity.ugui 2.0.0 из Unity 6000.0.26f1. Архив C:/Work/SREngine/ImplementationArtifacts/02/com.unity.ugui-2.0.0-6000.0.26f1.zip, 15 809 588 байт, SHA-256 62355FB7E45784383CE70F8428AAE40CD56E564446CBBDF19616D969A2C8BD00. Лицензия сохранена в архиве, Unity-код не включается в C++ сборку. Commit/tag локальной поставкой не указан; main не использовался.

Reference/LAYOUT_CONTRACT.md описывает формулы и фактические API. Reference/LayoutCases содержит cases.json (512 layout cases), scalers.json и scaler-expected.json (53 scaler cases), UnityLayoutExport.cs, compare.py и README.md. Version markers из fixtures также удалены. Результаты scaler-expected — source-derived, не измерения запущенной Unity. LayoutTestMetrics — синтетический тестовый provider, не production-замена текста.

Resources, .srproject, оригинал Ren’Py и исходные ТЗ не менялись. Коммитов и изменений safe.directory нет. Git status недоступен из-за dubious ownership; проверялось фактическое содержимое файлов.

## API для диагностики и оптимизации

- Component::GetLayoutElement/GetLayoutController/GetLayoutIgnorer — прямое получение интерфейсов без RTTI.
- Component::SetLayoutDirty() и LayoutRebuilder::MarkDirty(SceneObject&,bool fromTransform=false) — invalidation.
- SceneUpdater::MarkLayoutDirty/ RebuildDirtyLayouts — очередь dirty UI-корней после LateUpdate.
- LayoutRebuilder::Rebuild(SceneObject&,Context&) — forced rebuild с переиспользуемыми буферами; overload без Context оставлен для самостоятельных вызовов.
- SceneUpdater::GetLayoutRebuildCount() — накопительный счетчик реально обработанных roots.
- LayoutComparison::CheckDirtyScheduling() — редакторская проверка расписания.
- CanvasScaler::CalculateScaleFactorForViewport/CalculateReferencePixelsPerUnit — общие production/fixture вычисления.

Остальные контракты rect/metrics/fitter/grid и координат приведены в Reference/LAYOUT_CONTRACT.md.

## Статические проверки и пределы

Прочитаны актуальные реализации и реальные сигнатуры; проверены все существующие реализации layout-интерфейсов и их accessors. Поиск по layout/rect подтвердил отсутствие dynamic_cast и migration/legacy markers в измененном пути. Проверены уведомления и метапроверки перед down-casts; новые STL-контейнеры не добавлены. JSON fixtures разбираются статически: 512 уникальных layout cases и 53 scaler cases. Новые отражаемые классы сохраняют пары h/cpp и generated includes.

Агент не запускал CMake, сборку, кодогенерацию, бинарники, Unity, exporter, comparator и CheckDirtyScheduling. Пользователь подтвердил численный PASS и PASS расписания, зафиксированные в начале отчета. Профилировочные замеры времени и универсальная совместимость 1:1 за пределами набора cases не заявляются.

## Действия пользователя

Численный экспорт, compare.py и Check Dirty Scheduling уже пройдены пользователем. Инструкция Reference/LayoutCases/README.md сохранена для воспроизводимости и будущих изменений.

Ручная проверка указанной сцены уже подтверждена пользователем; повторять ее сейчас не требуется. Полная матрица реальных viewport/платформенных DPI и профилировочные замеры остаются отдельными непредоставленными доказательствами. Старые ресурсы не мигрировать.

Отдельно обсужден общий SerializeFloat: %.9g может создавать текстовые диффы при пересохранении ресурсов. Предложено сохранить прежний формат по умолчанию и локализовать высокую точность в экспорте численных проверок; это предложение пока не реализовано, текущий успешный PASS получен с %.9g.

