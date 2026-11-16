# Текст, эффекты и аудио

## Текст и паузы

В script.rpy **1663 исходных вызова say** (все однострочные; ch_*.say и nvl_narrator.say). Это количество исходных реплик, а не реплик в одном прохождении. debug исключен из этого счетчика; служебная строка `[nvl_text]` в characters.rpy:17 не считается второй сюжетной репликой. Полный текст/строки — SOURCE_LINES.tsv, параметры каждого текстового тега — TEXT_TAG_USES.tsv. Варианты выбора считаются отдельно: 56 в CHOICES.tsv.

Используемые в сюжетных репликах теги: b,i,u,s; alpha=*0.5; cps=*0.5,*1.5,*2,*3; size=-15,-10,+5,+10,+12,+15,+20,+30,+40,+50; w без значения; nw; shader wave и shake. Закрывающие версии присутствуют не для всех открытий. В вариантах выборов есть i,u,s, в названии игры s. Debug содержит дополнительные color, cps=20 и явные w=0.15/0.2/0.25; не расширять объем runtime из-за недостижимого debug. Для служебного UI встречаются переводческие `{#...}`, history allow_tags и hyperlink в help — не принимать их за сюжетные команды.

`add_auto_waits` (character_data.py:11–82) вызывается по умолчанию **перед** каждым CharacterController.say и NarratorNvl.say. В достижимом сценарии auto_wait=False не найден. Алгоритм:

1. Заменить U+2026 на три ASCII-точки по всей строке.
2. Перебирать символы; множество пунктуации `.,;:!?…`. Не вставлять паузу внутри `{...}` и для десятичной точки между цифрами.
3. После знака просмотреть пробелы и последующие теги; если найден `{w}` или тег с началом `w=`, новую паузу не вставлять.
4. Если знак соседствует с пунктуацией, вставить `{w=0.25}` даже для последнего знака группы. Иначе вставить паузу лишь при наличии следующего значимого символа. Последняя одиночная точка в конце строки паузы не добавляет.

Примеры ожидаемого преобразования по коду: `А, Б.` → `А,{w=0.25} Б.`; `...` → `.{w=0.25}.{w=0.25}.{w=0.25}`; `1.25` без вставки; `А!{w} Б` без дополнительной паузы после !. Это не доказательство измеренного времени в оригинале. Голый `{w}` требует продвижения, nw завершает реплику без ожидания; фактическую совместимость skip/auto подтвердить запуском, не заменять их одинаковым таймером.

## NVL и персонажи

NarratorNvl.say:244–251 преобразует текст, ставит active_voice_path="voice/deathnarrator.wav", multiplier и nvl_text, затем `call_in_new_context("nvl_text_label")`. Это вложенный контекст Ren’Py, не call обычного сюжета. Метка characters.rpy:16 произносит `[nvl_text]`, return:18. default nvl_narrator multiplier1.25. Но narrator задан объектом NarratorNvl без __call__, и kind=nvl нигде не задан — **заявленное NVL не подтверждено**, D002. Сохранять полученный NVL-кадр как эталон можно только после выяснения запускаемой версии. В новом runtime NVL будет состоянием AS по контрактам, не сериализацией контекста Ren’Py.

Контроллеры: narrator без имени, voice с пустым именем #f60; news «Новости» #4f2de6; revecca «Ревекка» #fff; death «Смерть» #fff; god «Бог» #fff000; plague «Чума» #b3bf4a; war «Война» #802121; hunger «Голод» #88a6b9. Say screen фактически задает цвет имени custom_text_color. God multiplier1.25, остальные ADV1.0.

Позиции и масштабы исходного представления: plague (250,0), sprite .3×.3; war (250,−50), sprite .32×.32; hunger (360,−50), sprite .32×.32. War берет именно ch_h_sprite_scale, не отдельный коэффициент. По одному custom layer character_<tag>, вставляемому перед screens в порядке создания; поэтому слои создаются даже для невидимых контроллеров. CharacterStore хранит zoom, position, flipped, state, animation/reset. set_state перемножает родительский и дочерний signed zoom; позиция берет только родительские coordinates (дочернее смещение помечено TODO и не применяется); transition только к слою персонажа. hidden использует Sprite("empty"), а не вызов hide.

`single_bounce_animation` (:85–98) duration.2, amplitude20, yoffset=−abs(sin(st*pi/.2))*20; при st>.2 сброс0, обновление1/60. Но достижимых set_animation/set_flipped/set_zoom в script.rpy нет — это debug-функции. Не включать их как обязательные сюжетные эффекты. hide() не передает custom layer (D009); в release-сценарии hide не вызывается, применяется hidden.

## Звуки печати и музыка

audio.rpy:10–17 регистрирует typewriter0…typewriter9, mixer voice, loop=False,tight=True. play_voice_sound:19–37 отключается при pixel_voice_enabled=False или text_cps<=0. Порог = max(1/text_cps, .075*active_voice_interval_multiplier); обычный .075s, God/NVL .09375s при text_cps30. Исходник использует time.time; новый runtime должен использовать игровое монотонное время. Channel выбирается `typewriter{current_channel+1}`, затем current_channel=(current_channel+1)%10: **typewriter10 не зарегистрирован**, D003. Начальное last_typewriter_sound_time=0.

Таймер say/nvl установлен .01 repeat=True только при truthiness `.slow_done` (screens.rpy:110/1421). В локальном SDK text/text.py:2204 это **callback или None**, не boolean «печать закончена»; :2613–2621 вызывает callback и очищает его после печати. Поэтому нельзя делать вывод об инверсии поведения из одного имени свойства. Нужна запись воспроизведения, влияния screen prediction и перепоказа экрана. `what` в функции звука не используется.

Реальные пути/каждая операция play/stop/loop/fade и канал — SOURCE_LINES.tsv; разрешенные ресурсы — AUDIO_REFERENCES.tsv. Группы:

- Меню audio/music/main_menu.ogg; музыка сюжета music/god.ogg, main.ogg, plague.ogg, war.ogg, Hunger.ogg. **music/office.ogg часто играет на канале sound**, а не music: это длительный ambience, его нельзя выключать как одноразовый SFX автоматически.
- Sound loop: sfx/steps.ogg, Dumpster.ogg, Clock.ogg, Canteen.ogg; короткие Door.ogg, Lighter.ogg, Knock.ogg, Table.ogg, Lock.ogg, MetalHit.ogg, news.ogg, tun.ogg. Новое play sound заменяет предыдущий звук этого канала; например Lighter прерывает Dumpster, затем ambience запускается снова.
- fadein обычно1.5, stop fadeout .5 или1.5; есть stop sound без fade. Точные значения и порядок — исходные строки. Не выводить loop из расширения файла. Музыка endings запускается на ending:2578 до выбора ветви, news:2579; harem дополнительно tun:2820.
- Начальная скорость текста30, afm_time15; настройки громкости music/sfx однократно ×.20 в splash, voice не уменьшается.

## Временные эффекты

Достижимы fade, dissolve, Dissolve(.15)/(.5), vpunch, текстовые wave и shake. Shake (:223) amplitude1.5,speed50; формула shaders.rpy: sin(time*speed+index*13)*amplitude по x и cos(time*speed+index*17)*amplitude по y, затем u_text_to_drawable. Значения wave: (amplitude,frequency,wavelength)=(5,2,20),(2,6,2),(2,9,2),(2,8,4),(2,10,2),(8,2,20); wave — механизм SDK, не определение shaders.rpy. Локальный SDK common/00textshader_ren.py:235–250 задает смещение gl_Position.y += cos(2*pi*(a_text_index/wavelength+u_time*frequency))*amplitude*u_text_to_drawable. Defaults amplitude5,frequency2,wavelength20; frequency в волнах/сек, wavelength в символах между пиками. Этап 03 должен закрепить численные проверки и сверить кадр/отсчет времени; формула не подтверждает фактический кадр оригинала.

blur/chromatic/glitch определены shaders.rpy, но обращения только в debug.rpy, поэтому в v1 не переносятся. Пролог содержит закомментированную альтернативу wave рядом с активным shake; комментарий не является вторым событием.
