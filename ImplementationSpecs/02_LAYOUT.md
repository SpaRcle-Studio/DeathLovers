# 02. Совместимость layout SREngine с Unity uGUI

## Цель и зависимости

Зависимость: 01. Прочитать общие контракты. Получить одинаковое поведение при одинаковых значениях Inspector, включая динамические изменения. Визуальная подгонка меню вместо исправления алгоритмов не принимается.

## Реальная отправная точка

В движке проверить `Engine/libs/Utils/inc/Utils/ECS/TransformRect.h`, `Utils/UI/ILayoutElement.h`, `LayoutElement.h`, `LayoutGroup.h`, `ContentSizeFitter.h`, `AspectRatioFitter.h` и соответствующие cpp; `Engine/libs/Graphics/inc/Graphics/UI/Canvas.h` и cpp; drawer TransformRect; существующие маски и скролл.

На 15.11.2026 обнаружено: ContentSizeFitter считает bounds детей; LayoutGroup не наследует ILayoutElement; layout обновляется через Update. Эти наблюдения — основание проверки, не разрешение переписать всю UI-подсистему. Сначала проверить актуальный код.

## Закрепленный эталон

Использовать исходники пакета `com.unity.ugui` версии 2.0.0. В `Reference/UNITY_BASELINE.md` записать origin, version, commit/tag при наличии и SHA-256 архива. Документация: https://docs.unity3d.com/Packages/com.unity.ugui@2.0/manual/index.html . Репозиторий: https://github.com/Unity-Technologies/uGUI . Не сравнивать с текущим main и не смешивать версии.

Эталонные алгоритмы: RectTransform, CanvasScaler, LayoutUtility, LayoutRebuilder, HorizontalOrVerticalLayoutGroup, GridLayoutGroup, ContentSizeFitter, AspectRatioFitter. Не копировать сторонние исходники без сохранения обязательных license notices.

## Требования

1. RectTransform-контракт: anchorMin/Max, pivot, anchoredPosition, sizeDelta, offsetMin/Max, parent rect, local scale. Зафиксировать формулы для раздельных и совпадающих anchors. OffsetMax обязан иметь семантику Unity, а не положительного отступа от верхнего края.
2. Проверить миграцию существующих сцен SREngine: если меняется трактовка поля, добавить версионированную миграцию старых assets. Не считать все ранее сохраненные данные уже Unity-compatible.
3. Единый расчет layout-input: минимальный, preferred и flexible размеры по каждой оси; отрицательное значение означает «не задано» по эталону; приоритет выбирается отдельно для каждого свойства; одинаковый приоритет разрешается эталонным правилом максимума.
4. Группы сами предоставляют layout-input. Horizontal/Vertical включают padding, spacing, детей и min/preferred/flexible. Учесть ignoreLayout, inactive, scale-control и reverse arrangement, если они входят в закрепленный пакет. Публичные значения/defaults должны совпадать с эталоном.
5. Ввести согласованное перестроение: измерить X снизу вверх, назначить X сверху вниз, затем измерить и назначить Y. Не допускать зависимости результата от порядка компонентов в списке Update. Изменение ширины текста влияет на его preferredHeight в том же layout-проходе.
6. ContentSizeFitter читает метрики компонентов собственного GameObject; MinSize и PreferredSize различны; Unconstrained не управляет осью. Сохранить pivot-поведение. При конфликте нескольких контроллеров использовать порядок эталона и диагностику, не бесконечные циклы.
7. GridLayoutGroup: start corner, start axis, cell size, spacing, padding, child alignment; fixed rows, fixed columns и flexible constraint. Порядок ячеек соответствует sibling order.
8. CanvasScaler: ConstantPixelSize; ScaleWithScreenSize с логарифмической интерполяцией MatchWidthOrHeight, Expand/Shrink; ConstantPhysicalSize с корректным fallback DPI. ScreenToCanvas и hit test используют тот же scale/viewport.
9. Измерение текста/изображений подключить через общий ILayoutElement. Если сам renderer доделывается в этапе 03, сейчас создать общий контракт и тестовый поставщик метрик, не фиктивные постоянные размеры в production.
10. Dirty propagation: текст, шрифт, размер, свойства группы, включение/выключение, reparent, sibling order, scale и размер viewport. Повторное перестроение без изменений не должно дрейфовать.

## Инструменты сравнения

Создать `Reference/LayoutCases` с декларативными входами и ожидаемыми результатами Unity. Для каждого случая записывать local rect/anchors/pivot/offsets/layout metrics/scale, а не только screenshot. Подготовить export/compare-инструмент; запуск делает пользователь. В редакторе SREngine добавить просмотр вычисленных layout rect/метрик и переключение тестового размера viewport, если аналог уже есть — расширить его.

Обязательные случаи: anchors 0/0.5/1 и stretch; pivot 0/0.5/1; все девять align; отрицательный/нулевой/положительный spacing; min shortage; preferred/excess; flexible 0/1/2; force expand с выключенным control size; два поставщика метрик с разными/равными приоритетами; ignoreLayout; inactive; вложенные H/V группы; Grid все constraints; fitter с текстом и группой; изменение ширины и reflow; повторные 100 rebuild; parent scale 0.5/2; resize.

Viewport: 1920×1080, 1280×720, 1366×768, 2560×1440, 1024×768, 2560×1080; DPI 96/144/192, fallback при неизвестном DPI. Геометрия: абсолютная ошибка <=0.001 reference unit, scale <=0.00001. Для видимого растрового края допустим 1 physical pixel из-за округления; это не разрешение менять геометрию. Текстовое растрирование сравнивается отдельно, совместимость layout не обещает одинаковый rasterizer Unity и SREngine.

## Приемка и передача

Нет ручных поправок в игровых AS. Все cases имеют ожидаемые значения эталона и результаты SREngine либо явно ожидают запуска. Совпадают initial и dynamic layout. Существующие сцены не испорчены без миграции. Создать `Reports/02_RESULT.md` с закрепленным Unity baseline, фактическими API и результатами численного сравнения. Если эталон еще не запущен, статус AWAITING_USER_RUN, не «совместимо 1 в 1».
