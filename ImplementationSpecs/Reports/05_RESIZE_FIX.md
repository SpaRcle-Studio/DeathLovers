# Ресайз, слои UI, курсор и переходы

16.11.2026. Статус: **FIXED / AWAITING_USER_RECHECK**. Основание — пользовательские снимки с периодически неверной маской, полосой фона и пропадающими ручками/отметками. Сборка, кодогенерация, тестовые бинарники и движок агентом не запускались.

## Маска и граница фона

RectMask2D вычислял GetTransformedLayoutRect прямо в OnMatrixDirty. Transform::UpdateTreeRecursive в этот момент еще не закончил помечать потомков грязными; GetMatrix мог прочитать промежуточные значения parent/Canvas/fit. Результат попадал в maskInfo и render cache. Дополнительно UpdateMaskInfoTree прекращал обход, если собственный mask cache уже был грязным, хотя у потомков мог оставаться чистый устаревший cache.

- `Graphics/UI/RectMask2D.h/.cpp`: базовый класс UIComponent; маска пересчитывается в AfterLayout, после Canvas/layout, без запросов матрицы из OnMatrixDirty. При выключении локальная маска очищается без чтения геометрии. Обновление referenceSize Canvas остается частью сравнения maskInfo.
- `Utils/ECS/TransformRect.cpp`: dirty маски передается всему поддереву независимо от прежнего состояния собственного cache.
- Scissor включает пиксели, центры которых лежат в исходном rect: ceil(min−.5), ceil(max−.5). Прежнее floor(min)/ceil(max) добавляло внешнюю полосу при дробном fit. Нативный PNG main_menu.png проверен чтением: нижний пиксель непрозрачен, alpha=255; изображение не редактировалось.

## Порядок отрисовки

Фон screen, текст, slider bar, handle и radio/check marker имели одинаковые суммарные приоритеты. Это оставляло их взаимный порядок зависимым от очередей материала/регистрации, в том числе после ресайза и enable/disable.

`MainMenu.scene`: фон submenu остается на уровне 100, непосредственные content/title/navigation/Back получают +10; Handle/Selected/Unselected/Label — +1 относительно соответствующего контрола. Для Confirm/Notify отдельно упорядочены Shade, Content и кнопки/текст. Input-контролы одной визуальной группы остаются на одном уровне для стабильного обхода Tab. MainMenu подняты только контейнеры над parallax. Обновлен также ModalFrame.prefab. Раскладка и значения ползунков этим не менялись.

## Курсор

- `Engine/UI/UICursor.h/.cpp`: UIComponent с AfterLayout и ExecuteInEditMode. Курсор обновляется и на паузе редактора. В игре проверяется client viewport Canvas и focus окна; в редакторе — IsOpen/IsHovered и точный GetImagePosition/GetTextureSize SceneViewer. Координаты редактора пересчитываются от прямоугольника изображения, а не от всего окна; это учитывает вынесенный SceneView.
- `Utils/Input/InputSystem.h/.cpp`: SetCustomCursorActive(owner, active), список владельцев и совместимость с существующим cursor lock. Input больше не включает системный курсор каждый кадр поверх игрового. Вне viewport/SceneView, при потере focus, отключении или удалении UICursor запрос снимается. При camera cursor lock скрываются оба курсора.
- Sprite игрового курсора виден только в своей области. Положение задается SetVisualOffset; постоянное перемещение мыши не ставит все дерево Canvas на layout rebuild. Сохраненная anchored position сбрасывается один раз.

## Прозрачность и AS

`UIRenderComponent::SetSubtreeOpacity(float)` — общий механизм для текущих UI-renderers под объектом, без изменения layout и материалов проекта. Он обновляет opacity и uniforms; `sliced.srsl`/`text-mesh.srsl` умножают итоговую alpha на uiOpacity. По умолчанию opacity=1; параметр не сериализуется. Другие шейдеры не получают новую визуальную семантику без поддержки uiOpacity.

`MenuNavigation.as` управляет временем и переходами. Открытие submenu: новый экран 0→1 поверх старого; старый отключается после завершения. Вернуться: submenu 1→0 поверх MainMenu. Длительность .5 секунды взята из options.rpy enter/intra/exit_transition=dissolve и SDK renpy/common/00definitions.rpy:328, dissolve=Dissolve(0.5). Alpha обновляется игровым dt. Это прозрачность отдельных UI-renderers, без захвата сцены в промежуточную текстуру.

Невидимый UIControl TransitionBlocker (modal, focusable=false, priority=450) перекрывает весь ввод на время перехода; это служебная нода, не техническая кнопка. По завершении focus восстанавливается. ReturnToMainMenu корректно отменяет незавершенный переход. AS не задает размеры/позиции UI и не занимается native cursor visibility.

## Проверки и передача

`05_RESIZE_STATIC.json`: 583 определения entityId, 74 ссылки, дубликатов/висячих ссылок нет; 16 event methods найдены. Проверены 26 отношений child/control priority и 20 отношений content/screen background; изменено 55 native priority значений. Арифметическая проверка 40 дробных rect подтверждает соответствие scissor покрытию центров пикселей. Это не экспорт геометрии движка и не проверка GPU.

Сверены реальные UIComponent.AfterLayout, WidgetManager.GetWidget, SceneViewer screen rect, Canvas scale/viewport, Input cursor lock и Shader uniform API. Проверены Codegen includes, новые исходники на std:: и diff --check. Новых cpp нет. Прежние пользовательские изменения MainMenu.scene прочитаны и сохранены; исправления наложены на актуальную сериализацию. PNG и сюжет не изменялись.

Нужна пересборка движка с Utils/Graphics/Engine и штатной кодогенерацией для новых базовых классов и SetSubtreeOpacity. Затем полностью перезагрузить MainMenu.scene и шейдеры; не сохранять старую открытую сцену поверх измененного файла. Ручной reload CMake из-за новых cpp не требуется.

Повторная runtime-проверка:

1. Быстро и медленно менять размеры в обе стороны при открытых Preferences и MainMenu; проверить все шесть viewport. Область Novel/маски не должна прыгать к content rect; под Preferences не должно оставаться полосы parallax.
2. После ресайза менять все пять slider, включая 0/1 и промежуточные значения; открыть/закрыть Preferences 20 раз. Ручки и выбранные radio/check должны оставаться поверх фона.
3. Проверить курсор в игровом client area, letterbox, вне окна и при Alt+Tab. В редакторе отдельно проверить изображение SceneView, заголовок/панели/Inspector, скрытый tab, паузу, camera RMB-lock и вынесенное окно SceneView. Системный и игровой курсор не должны быть одновременно видимы над изображением.
4. Открыть Preferences, перейти в другие submenu и вернуться: плавная alpha за .5 с, музыка не перезапускается, нажатия во время перехода не активируют контролы. После завершения проверить Tab/Enter/Escape и исходный focus.

Результаты этих запусков еще не получены; исправления не объявлены подтвержденными runtime-приемкой.
