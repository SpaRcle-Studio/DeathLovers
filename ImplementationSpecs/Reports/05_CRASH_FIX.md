# Исправление падения настроек и обводки

16.11.2026. Статус: FIXED / AWAITING_USER_RECHECK. Сборка, кодогенерация, тестовые бинарники и движок агентом не запускались.

## Падение

Пользовательский стек: Assign → AngelScriptBindings::CopyTo → ReflectedTypeInlineCopy<String> → String::operator= → resize/reserve → SRFree. Причина обнаружена в String::Deallocate(): он освобождал память, но не обнулял m_data, m_size и m_capacity. При копировании строки с другим аллокатором operator= вызывал Deallocate, менял аллокатор и передавал устаревший указатель в resize/reserve. Длинная строка приводила к повторному free; короткая — к записи в уже освобожденную память. Переход MainMenu → Preferences впервые присваивает более длинное имя, возвращенное GetName, строке MenuSession.activeScreen.

`Utils/src/Utils/Types/String.cpp`: Deallocate теперь обнуляет указатель, размер и емкость; аллокатор сохраняется до его штатной замены вызывающим operator=. Исправлена причина в строковом типе, привязка Assign не обойдена заменой меню на другую модель.

## Ассерты

В прочитанном srengine.log — 22 assert Texture::GetWidth и 22 Texture::GetHeight, все с сообщением о продолжающейся асинхронной загрузке. Стек ведет через Sprite::CalculateLayoutInput → LayoutRebuilder::Measure/Rebuild.

`Graphics/src/Graphics/Types/Geometry/Sprite.cpp`: измерение обращается к GetWidth/GetHeight только при pTexture->CanBeUsed(). Этот существующий метод проверяет незавершенную async-задачу. RELOAD_DONE уже вызывает SetLayoutDirty через подписку Sprite::OnTextureChanged, поэтому окончательные размеры измеряются после готовности без ожидания загрузчика в layout-проходе. Остальные проверки/ассерты загрузчика сохранены.

## Обводка

Прежняя формула вычитала из порога ширину обводки, превышающую доступный диапазон distance field. Для Pangolin sampling=86/fontSize=33/range=8.6/outline=3 даже нулевое значение вне контура получало outerAlpha=1. Это объясняет черные прямоугольники всего glyph quad.

- `Resources/Engine/Shaders/UI/text-mesh.srsl`: outerThreshold ограничен снизу шириной антиалиасинга; прозрачное нулевое поле остается прозрачным. outlineWidth=0 не добавляет контур. Толщина переводится из reference units через range и масштаб глифа, а не остается постоянной в физических пикселях после ресайза.
- `Graphics/src/Graphics/Font/TextMesh.cpp`: свободные Custom1.z/w передают признак MTSDF и fontSize/samplingPointSize. Формат вершин и существующие x/y не меняются. MTSDF-внешний контур использует истинное расстояние alpha; MSDF/SDF сохраняют соответствующее чтение.
- `Graphics/inc/Graphics/Font/FontAsset.h` и cpp: opt-in sdfRange, 0 означает прежний автоматический диапазон. Диапазон учитывается и в метриках с padding, и в генерации bitmap.
- `DeathLovers/Fonts/Pangolin.font`: sdfRange=24 при samplingPointSize=86 для запаса под контур шириной 3. Advance/kerning и текст не менялись; другие FontAsset с sdfRange=0 сохраняют прежние значения.

Статически сверены указатели/аллокаторы в обоих operator= String, async readiness/event dirty path, GlyphRenderType MTSDF и true SDF alpha в Font::GenerateMSDFOrMTSDF, существующие Codegen includes. diff --check пройден. Арифметика shader формулы при fit .5333/.6667/1/1.3333/1.5 дает background alpha=0 вместо прежнего 1; это не запуск GPU и не снимок исправленной игры.

## Повторная приемка

Пересобрать движок с изменениями Utils/Graphics и обычной кодогенерацией. Новых cpp нет, ручной reload CMake по этой причине не нужен. Полностью перезапустить приложение для нового font atlas и shader, открыть MainMenu, затем Preferences. Проверить переходы обратно/вперед и между подменю не менее 20 раз, hover и Tab; падения/повторного free быть не должно. На чистом старте проверить отсутствие 44 прежних async texture asserts. Контур должен следовать буквам, без черных прямоугольников и обрезанных краев; сравнить заголовки и кнопки на шести viewport/DPI с Reference. Передать свежий лог, если остается assert/исключение.

Эти ожидаемые runtime-результаты пока не подтверждены. Тест на смену аллокатора String и GPU-рендер не исполнялись согласно CLAUDE.md.
