# Layout: фактический контракт этапа 02

## TransformRect

Для каждой оси: P — размер parent rect, O — его минимум, a/b — anchorMin/Max, p — pivot, t — anchoredPosition, d — sizeDelta.

```text
Amin = O + P*a
Amax = O + P*b
S = P*(b-a) + d
pivotPosition = Amin + (Amax-Amin)*p + t
rectMin = pivotPosition - S*p
rectMax = rectMin + S
offsetMin = t - d*p
offsetMax = t + d*(1-p)
```

Совпадающие anchors дают S=d и pivotPosition=Amin+t. Раздельные anchors используют те же формулы; offsets эквивалентно задают rectMin=Amin+offsetMin, rectMax=Amax+offsetMax. Inspector Right/Top отображает **минус offsetMax**. Anchor presets Top имеют y=1, Bottom y=0. Anchors программно не ограничиваются [0,1], как в Unity.

SetSize()/GetSize()/GetSizeDelta() обозначают sizeDelta. Фактический размер — GetLayoutRect().Size(). SetSizeWithCurrentAnchors(bool horizontal,float_t size) задает фактический размер одной оси, оставляя anchoredPosition/pivot. GetLayoutRect — принятой ранее в движке формы, в общем пространстве раскладки; относительно собственного pivot local rect имеет min=-S*p. Матрица применяет scale/rotation отдельно, размеры layout-input не включают parent scale. Для сравнения экспортируются local rect и transformed world corners.

## Метрики и проходы

`LayoutUtility::GetMetrics(const GameObject&,bool horizontal)` возвращает minimum/preferred/flexible. Для каждого свойства отдельно выбирается максимальный priority среди активных ILayoutElement с неотрицательным значением; одинаковый priority разрешается максимумом. Отсутствующее свойство дает 0; preferred=max(minimum,preferred). ignoreLayout — отдельный ILayoutIgnorer; ребенок исключен, только когда все его ignorers требуют исключения, как в закрепленном LayoutGroup.cs. Отсутствие ignorers не исключает ребенка. Inactive дети исключаются независимо.

`Component::GetLayoutElement/GetLayoutController/GetLayoutIgnorer` предоставляют интерфейсы напрямую без RTTI; компонент-поставщик переопределяет соответствующий accessor и возвращает this. `Component::SetLayoutDirty()` вызывается при изменении входных метрик (в том числе текста/шрифта). `ILayoutElement::CalculateLayoutInput(bool)` измеряет метрики, `ILayoutController::SetLayout(bool)` назначает размеры/позиции. `IsSelfController()` выбирает первую фазу controllers, затем выполняются группы. Несколько controllers одного типа разрешаются порядком компонентов с однократной диагностикой.

`LayoutRebuilder::Rebuild(SceneObject&)`: X measure снизу вверх → X control сверху вниз → Y measure снизу вверх → Y control сверху вниз. SceneUpdater после LateUpdate обрабатывает только очередь dirty UI-корней. Повторные уведомления объединяются hash set; после reparent вложенный корень пропускается, если уже поставлен в очередь его предок. Для dirty-корня один раз собирается плоский список активных layout-участников, используемый всеми четырьмя фазами. Vector/HashSet и Context переиспользуют capacity. На неизменном кадре обход и вычисления layout не выполняются.

LayoutGroup — H/V controller и ILayoutElement(priority=0). Метрики учитывают padding, spacing, control size, force expand, scale, reverse; shortage интерполирует min→preferred, extra распределяется по flexible. Без control size сохраняется sizeDelta ребенка, но force expand по-прежнему дает flexible cell и влияет на позицию внутри нее. Новые компоненты: UpperLeft, control width/height=false (Unity Editor Reset), force expand=true, scale=false, reverse=false.

GridLayoutGroup — ILayoutElement и controller. Inspector имеет Start Corner, Start Axis, Cell Size, Spacing, Constraint/Count, Padding Min=(Left,Top), Padding Max=(Right,Bottom), Child Alignment=0…8 (Unity TextAnchor). Sibling order сохраняется. Метрики/ячейки различают flexible, fixed columns и fixed rows, включая неполную последнюю строку/колонку.

ContentSizeFitter в новом режиме читает метрики **собственного** объекта: MinSize и PreferredSize различаются, Unconstrained не пишет ось. LayoutTestMetrics — исключительно тестовый поставщик переноса строк. В production постоянные фиктивные размеры не подставляются; Text/Image должны реализовать ILayoutElement в этапе 03.

## Canvas

ScaleWithScreenSize: scaleX=width/referenceWidth, scaleY=height/referenceHeight; Match — exp2(lerp(log2(scaleX),log2(scaleY),match)); Expand=min; Shrink=max. ConstantPhysicalSize использует DPI/unitsPerInch (1,2.54,25.4,72,6), fallback при неизвестном DPI; referencePixelsPerUnit умножается на unitsPerInch/defaultSpriteDPI. ConstantPixelSize использует заданный scaleFactor.

`CanvasScaler::CalculateScaleFactorForViewport(const FVector2&,float_t dpi)` — общий вычислительный API, используемый production и численными fixtures. `Canvas::ScreenToCanvasSpace` использует тот же viewport/scale. ContainsScreenPoint и CanvasToLayoutPoint учитывают inverse transform; UIButton и scroll-wheel/scrollbar используют этот путь. Маски уже используют GetTransformedLayoutRect. Вписывание игрового изображения 16:9 остается отдельной задачей игры.

## Сериализация и уведомления

По явному указанию пользователя старых ресурсов для миграции нет. Удалены все layout version markers, специальные Save/Load для defaults, legacy-флаги и bounds/fallback ветки. Сериализованные значения сразу имеют текущую семантику. TransformRect::Load сохраняет только пакетное чтение взаимосвязанных полей без промежуточного применения setters; никаких преобразований старых значений нет.

Изменения RectTransform уведомляют layout до раннего выхода по matrix dirty; рекурсивное обновление дочерних матриц не дублирует уведомление для каждого ребенка. SceneObject помечает обе стороны reparent, sibling changes, добавление/удаление и enable/disable. Регистрация/снятие layout-компонентов, OnPostLoad и свойства metrics/group/grid/fitter/aspect/reflow также ставят корень в очередь. Внутренние transform-записи layout не порождают бесконечное перестроение; явные новые изменения параметров во время прохода остаются в следующем batch. Неизмененные setters группы не инвалидируют layout.

Метаклассы GameObject (final) сравниваются напрямую; TransformRect проверяется через IsSameOrInherited перед static_cast. Plain layout-интерфейсы не отражаются в метаданных, поэтому их получение выполняется виртуальными accessors без cross-cast. Контекст не кеширует интерфейсы между dirty-проходами: удаление/замена компонентов учитывается при следующем сборе.

CanvasScaler кеширует scale по viewport, DPI и изменению настроек: log/pow не вычисляются каждый кадр при неизменном вводе. SceneUpdater::GetLayoutRebuildCount() доступен для проверки расписания. Tests/LayoutComparison → Check Dirty Scheduling проверяет idle, равные значения, объединение изменений, activity, resize, reparent, sibling order, независимые roots и удаление pending root. Проверка агентом не запускалась.

