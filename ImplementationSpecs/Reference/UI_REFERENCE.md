# Эталон интерфейса

Статические значения подтверждены исходниками; фактический кадр/фокус/поведение — AWAITING_USER_RUN. Полный индекс экранов: SCREEN_DEFINITIONS.tsv. Все текстовые строки, стили, условия, размеры и colors с точными строками: SOURCE_LINES.tsv (screens.rpy, gui.rpy, options.rpy). Это нормативное приложение к таблицам ниже; не восстанавливать значения из памяти.

## Достижимость

Desktop: main_menu:403 → navigation:292 → Start, load:655, preferences:793, about:610, help:1046, Quit. В игре добавляются history:956 и save:648, MainMenu; overlay quick_menu:240. Общие: game_menu:479, file_slots:662, confirm:1214, skip_indicator:1277, notify:1332. ADV say:96 и choice:209 используются сценарием. NVL nvl:1371/nvl_dialogue:1403 заявлен интерфейсом, но фактическое подключение NarratorNvl дефектно (D002); скриншот NVL обязателен после решения блокера.

Desktop quick_menu использует **определение :240**: :1589 — отдельный вариант `variant "touch"`, не безусловная замена поздним определением. На desktop последняя версия touch не активна. Варианты small/medium в конце screens.rpy и gui.rpy не применять к фиксированному desktop-эталону. Истинные системные pc/touch variants пользователь должен записать в журнал запуска.

Недостижимые из штатного сюжетного потока: input:176 (нет renpy.input), bubble:1493 (нет bubble characters), replay-ветвь navigation (:325; нет запуска replay), debug/Alice (кнопка закомментирована). gamepad_help:1149 условно доступен при обнаружении контроллера; вне v1 мышь/клавиатура. Системные accessibility/self-voicing и sync из стандартного SDK не становятся обязательным объемом порта; условные кнопки sync в file_slots учитывать отдельно от подтвержденного desktop потока.

## Базовые значения

GUI 1920×1080 (gui.rpy:9). Pangolin для всех игровых текстов; outline по умолчанию (3,#000000ff,0,0), options.rpy:19. Цвета gui: accent #00cc99, idle #888888, idle_small #aaaaaa, hover #66e0c1, selected #ffffff, insensitive #8888887f, muted #00513d, hover_muted #007a5b, text/interface #ffffff. Базовые размеры: text 33, name 45, interface 33, label 36, notify 24, title 75. Явный say what size **35**:107 перекрывает gui.text_size. Say who color custom_text_color (#ffffff), bold False, size45:104; не подменять фактический цвет имени только цветом CharacterController.

| Область | Значения |
|---|---|
| ADV window | xalign .5, xfill True, yalign1, height278; textbox background закомментирован (:147) |
| Имя | xpos360, ypos0, xanchor0; namebox xalign.5, auto width/height, borders(5,5,5,5), gui/namebox.png |
| Реплика | xpos402, ypos75 относительно window, width1116, xalign0, adjust_spacing False |
| Choice | vbox xalign.5, ypos405, yanchor.5, spacing33; width1185, borders(150,8,150,8), text xalign.5, idle #888888/hover #fff |
| Quick menu | xalign.5, yalign1, zorder100; text size21, borders(15,6,15,0) |
| Navigation | main_menu xalign.5,yalign.95; иначе .1,.5; spacing6, общий size_group navigation |
| Заголовок меню | vbox xalign.5,xoffset30,xmaximum1200,yalign0,yoffset80; title75 |
| Game menu | main_menu background gui/main_menu.png, иначе gui/game_menu.png; outer top_padding180,bottom_padding45; navigation width420; content margins L60/R30/T15; viewport width1380, side spacing15 |
| Game menu title/return | title xpos75,height180,color accent; return xpos60,yalign1,yoffset−45 |
| Слоты | grid3×2, center, spacing15; slot414×309,borders15; thumbnail384×216; text21; страницы А/Б/1…9, < и > |
| Настройки | pref_spacing15,pref_button_spacing0; между рядами null60; slider width525, vbox675; radio/check borders27,6,6,6 |
| История | limit250,height210,spacing0; имя xpos233,ypos0,width233,xalign1; текст xpos255,ypos3,width1110 |
| NVL | borders(0,15,0,30), list_length6,height173,spacing15; name(645,0),width225,align1; text(675,12),width885; thought(360,0),width1170; button xpos675 |
| Confirm | modal True,zorder200; overlay закомментирован; frame выбирает gui/confirm_frame.png, затем fallback gui/frame.png; borders/padding60; center; vbox spacing45, buttons spacing150; game_menu key = no |
| Notify / skip | zorder100; notify ypos68, borders(24,8,60,8), duration3.25; skip ypos15,borders(24,8,75,8), triangle DejaVuSans |

Рамки/полосы: обычные borders(6,6,6,6), frame_tile/bar_tile/scrollbar_tile/slider_tile False; bar/slider38, scrollbar18, unscrollable="hide". Все отличающиеся состояния и шаблоны путей содержатся в SOURCE_LINES.tsv.

## Семь слоев меню

Формула screens.rpy:367–400: px=mx/1920, py=my/1080; ox=px−.5, oy=py−.5; smx=ox(1−abs(ox))*.002; smy аналогично. Timer .025. Layer xpos=.5+smx*f*.4, ypos=.5+smy*f*.1, anchors .5. size=(1920*s,1080*s), s=base при f≠0, иначе1. **Нет сглаживания по времени**. Пары factor/base в порядке отрисовки: 0/1.1, −20/1.0,40/1.1,−60/1.1,80/1.1,−100/1.1,120/1.1. Первый base фактически игнорируется. Это растяжение в size, не сохранение aspect исходных PNG2594×1080. Слои nearest True, затем пустой frame (background закомментирован), navigation, title/version. D001 блокирует подтверждение движения в оригинале.

## Строки, действия, ввод

Главное меню: «Начать», «Загрузить», «Настройки», «Об игре», «Помощь», «Выход». Внутри игры: «История», «Сохранить», «Загрузить», «Настройки», «Главное меню», «Об игре», «Помощь», «Выход». Quick: «Назад», «История», «Пропуск», «Авто», «Сохранить», «Б.Сохр», «Б.Загр», «Опции». Слоты: «Пустой слот», «{} страница», «Автосохранения», «Быстрые сохранения»; FileTime "%A, %d %B %Y, %H:%M".

Preferences: «Режим экрана»: «Оконный»/«Полный»; «Пропуск»: «Всего текста»/«После выборов»/«Переходов»; «Скорость текста», «Скорость авточтения», «Громкость музыки», «Громкость звуков», «Громкость голоса», «Без звука», «Пиксель-войс». Test-кнопки условны на config.sample_sound/voice; в проекте они закомментированы. Help вкладки «Клавиатура»/«Мышь», условно «Геймпад». Полные тексты пояснений и about, включая атрибуцию звуков, — исходные строки, не переписывать.

Из desktop help (:1075–1147): Enter/ЛКМ продвижение и активация; Space продвижение без выбора; arrows навигация; Esc/ПКМ game_menu; Ctrl удержание skip; Tab toggle skip; PageUp/колесо вверх rollback; PageDown/колесо вниз rollforward; H/средняя кнопка скрытие UI; S снимок; V self-voicing и Shift+A accessibility (последние вне v1). File slots привязывает save_delete/save_page_prev/save_page_next; точные физические клавиши SDK не переопределены проектом. Системный cursor gui/cursor.png hotspot(0,0). Проверить фокус/модальность и границы rollback отдельно.
