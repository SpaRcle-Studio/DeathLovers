# Численная проверка этапа 02

Численный набор и Check Dirty Scheduling пройдены пользователем: VERIFIED. Пользователь также вручную проверил сцену C:/Work/SREngineProjects/3DNovel2/Resources/Scenes/Main.scene в редакторе и не заметил проблем; скриншот и область подтверждения описаны в Reports/02_RESULT.md. Полная матрица DPI/viewport отдельно не подтверждена. Агент не запускал Unity, SREngine, Python, сборку или кодогенерацию.

`cases.json`: 512 декларативных случаев. Каждый содержит упорядоченные nodes и changes. Индекс parent всегда меньше индекса ребенка; -1 обозначает корень. rect: anchorMin, anchorMax, pivot, position (anchoredPosition), size (sizeDelta), scale. Все координаты Unity: X вправо, Y вверх. Числа padding целые, как RectOffset Unity. Grid paddingMin=(Left,Top), paddingMax=(Right,Bottom), childAlignment=TextAnchor 0…8.

Текущая schemaVersion=2: у nodes/changes есть явные hasRect/hasActive/hasGroup/hasGrid/hasFitter/hasAspect/hasReflow/hasElements, а у changes также hasTargetParent/hasSiblingIndex. Они позволяют Unity отличать отсутствующий JSON-блок от созданного JsonUtility пустого inline-объекта и не полагаться на значения инициализаторов при десериализации. Численная геометрия cases не изменена; SREngine использует наличие исходных ключей. После обновления нужно заново скопировать UnityLayoutExport.cs в Assets/Editor и выбрать обновленный cases.json из этой папки. Старый JSON exporter отклоняет явно.

group/grid/elements/fitter/aspect/reflow — параметры соответствующих компонентов. group.direction выбирает HorizontalLayoutGroup или VerticalLayoutGroup в Unity. Все компоненты сразу используют текущие layout-значения; legacy-режимов и version markers нет. reflow — одинаковый синтетический monospace-поставщик метрик в обоих движках, не тест качества шрифта и не production-замена текста.

Три состояния результата: initial после одного rebuild; dynamic после changes и одного rebuild; stable после еще 100 rebuild. Выгружаются local rect, anchors/pivot, anchoredPosition, sizeDelta, offsets, local scale, world corners и шесть layout-метрик каждого узла, в том числе inactive/ignored. World corners требуют пустого host SREngine с единичным Transform3D без родителей.

`scalers.json`: 53 независимых входа scaler, все шесть viewport, match=0/0.5/1, Expand/Shrink, все физические единицы, DPI=0/96/144/192, ConstantPixelSize=0.5/1/2. `scaler-expected.json`: вычисленные по закрепленному CanvasScaler.cs ожидания, **не измеренные запуском Unity**. Для этой части exporter SREngine вызывает тот же CalculateScaleFactorForViewport, которым пользуется production Canvas. Реальное получение DPI и mapping окна проверяются отдельно.

## Запуск пользователем

1. В SREngine перезагрузить CMake и пересобрать движок. Добавлены новые cpp и пары h/cpp с generated include. Агент эти инструменты не вызывал.
2. Создать отдельную пустую проверочную сцену. У пустого host оставить Transform3D, position=(0,0,0), scale=(1,1,1), без родителей и игровых компонентов. Добавить компонент Tests/LayoutComparison. В Input указать полный путь к cases.json, в Output — новый путь srengine-results.json в этой папке. Нажать Export Cases. Проверить отсутствие ошибок в логе. Fixture-объекты создаются как дети host и удаляются после экспорта.
3. Тем же компонентом отдельно экспортировать scalers.json в srengine-scalers.json. Не выбирать входной JSON в качестве Output.
4. Создать отдельный Unity-проект в **6000.0.26f1** с **com.unity.ugui 2.0.0** из baseline. Скопировать UnityLayoutExport.cs в Assets/Editor. Дождаться компиляции. Меню Tools → Layout Conformance → Export uGUI 2.0.0: выбрать cases.json, сохранить unity-results.json. Скрипт отказывается экспортировать на другой версии. Созданные временные объекты удаляются в finally; исходники Unity не меняются.
5. Из этой папки выполнить:

```powershell
python compare.py cases.json unity-results.json srengine-results.json --scalers scaler-expected.json --engine-scalers srengine-scalers.json --report comparison.json
```

Ожидание: PASS, 512 layoutCases, 53 scalerCases, errors=[]. Сравниваются полные наборы ID, количество состояний/узлов, все поля, конечность чисел, drift dynamic→stable. Пустой/неполный экспорт не дает PASS. Допуски: геометрия и метрики 0.001; scale/scaleFactor 0.00001. Первые расхождения сохранять с ID и путем поля; не подгонять игровые AS под ошибку.

## Проверка dirty scheduling

В том же Tests/LayoutComparison на отдельном host с Transform3D нажать **Check Dirty Scheduling**. Метод проверяет фактический счетчик SceneUpdater::GetLayoutRebuildCount: idle и повторная установка того же значения дают 0; несколько изменений одного корня — 1; enable/disable, resize, sibling order — 1; reparent между двумя корнями — 2 без лишнего пересчета поддерева; два независимых dirty-корня — 2; уничтоженный pending root — 0. В логе ожидается LayoutComparison::CheckDirtyScheduling() : PASS. Агент метод не запускал.

В Tracy на стабильном UI без изменений LayoutRebuilder::Rebuild/Collect/Measure/Arrange не должны вызываться; один новый dirty root должен давать один общий четырехфазный проход. Явные вызовы Export Cases по-прежнему выполняют forced rebuild для проверки геометрии, а не имитируют кадры без изменений.

## Отдельные проверки интеграции

- В сцене с Canvas и CanvasScaler выставить referenceResolution=1920×1080, ScaleWithScreenSize, MatchWidthOrHeight=0.5. Последовательно выбрать шесть размеров через список режимов SceneViewer: View1920x1080, View1280x720, View1366x768, View2560x1440, View1024x768, View2560x1080. Проверить scaleFactor против scalers.json и отсутствие задержки на кадр при resize.
- В Inspector включить EditorDebugMode: TransformRect показывает Layout/Scaled Layout Rect с шестью знаками и min/preferred/flexible по осям. Проверить bounds, совпадение курсора и клика на краях кнопки при scale родителя 0.5/2, Canvas scale и letterbox viewport. Проверить колесо/drag ScrollView и scissor RectMask2D.
- Для физического Canvas зафиксировать фактический GetScreenDPI и сравнить с Unity Screen.dpi на той же машине/экране. Инъекции 96/144/192 и неизвестного DPI проверяют вычисления, но не заменяют проверку платформенного получения DPI. Проверить отключение scaler: scale возвращается к 1.
- Старые ресурсы по решению пользователя не мигрируются. Для текущих значений проверить save→reload и clone: sizeDelta/position/anchors/pivot/offsets должны сохраниться без преобразований.
- Реальные Text/Image renderer metrics и rasterizer относятся к этапу 03. Текущая проверка reflow подтверждает только общий контракт, когда результаты будут получены запуском. Допуск 1 physical pixel применим к растровому краю, не к численной геометрии.

Unity/SREngine результаты получены пользователем. comparison.json подтверждает PASS, 512 layoutCases, 53 scalerCases, errors=[]. Пользователь также подтвердил два PASS Check Dirty Scheduling. Это подтверждение относится к данному набору и исходным допускам; универсальная совместимость 1:1 и ручные платформенные проверки из него не следуют.
