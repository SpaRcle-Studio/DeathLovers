# 08. История, откат, пропуск, авточтение и настройки

## Цель и зависимости

Зависимость: 07. Реализовать поведение чтения в AS, используя единое GameState. Общая маршрутизация UI остается в движке; сюжетная политика там запрещена.

## История

Максимум 250 записей, FIFO. Добавлять одну запись при первом предъявлении Say, keyed by commandId и порядковым номером исполнения, чтобы повторные посещения отличались. Перерисовка/открытие menu/загрузка не создают новых записей. Хранить speakerId/displayName/color, полный нормализованный текст без timing tags, mode, sequence. Из history отображать безопасные visual styles; wave/shake/cps/waits не исполнять. ScrollRect/clip/layout; при открытии сначала последний элемент, resize не теряет прокрутку произвольно.

## Откат

Граница отката — самостоятельный глубокий snapshot состояния перед пользовательской точкой взаимодействия (Say/Choice), до ее side effects. Хранить не более 100; самое старое удалять. Snapshots содержат variables/callStack/presentation/audio/history/cursor, но не рекурсивную копию rollback history. Использовать отдельный StateCore без поля rollbackCheckpoints внутри checkpoint, чтобы не получить экспоненциальный рост.

При rollback отменить skip/auto, остановить текущие transitions/short sounds, восстановить предыдущий StateCore, построить сцену; сохраненный текст показывать полностью. Read IDs профиля не уменьшать. Повторный forward из восстановленного checkpoint исполняет соответствующие команды в восстановленной ветке один раз, а не поверх старых counters.

RollbackBarrier устанавливает нижнюю границу на точном месте исходного `renpy.block_rollback`. Удалить старые checkpoints до барьера, включая choice, если вызов был уже после принятия выбора. Нельзя откатить результат такого выбора. Доступность Rollback в quick menu отражает реальную возможность. Загрузка сохраняет checkpoint ring и boundary, но не создает способ пройти барьер назад.

## Пропуск

Прочитанной считать реплику после первого полного показа; fast reveal тоже считается. Множество read IDs принадлежит профилю. По умолчанию skip только прочитанного, stop after choice=true, skipTransitions=false. Переключатель «всего текста» разрешает непрочитанное; after choices разрешает продолжить skip после принятого пользователем выбора, но никогда не выбирает вариант автоматически.

При skip timed/automatic waits пропускать, explicit `{w}` завершать без отдельного клика, Say мгновенно показывать и переходить дальше на следующем tick. Ограничить скорость до 30 Say/сек; сохранять порядок всех нетекстовых side effects. Не создавать очереди typewriter sounds. Music/SFX команды выполняются, но одномоментно начавшийся и остановленный SFX не должен бесконечно накапливаться. Если transitions не пропускаются, дождаться конца transition.

Toggle skip активируется кнопкой quick menu, hold skip — удержанием Ctrl; отпускание Ctrl выключает только hold mode. Ручной advance выключает toggle skip. При modal/меню оба режима приостановлены, загрузка/rollback/новая игра отменяют их. На Choice runner всегда ждет пользователя.

## Авточтение

Запускается отдельным переключателем Auto; взаимно исключается со skip. Отсчет начинается после полного показа текущей реплики и всех timed waits. DelaySeconds = afmTime*(visibleGraphemeCount+25)/250; afmTime по умолчанию 15, диапазон 0..30. Явный `{w}` без длительности требует пользователя и приостанавливает auto до advance. Choice никогда не выбирается автоматически. Ручное advance при включенном auto переключает текущую реплику, сохраняя auto; Escape/menu приостанавливает таймер, не сбрасывая его. Загрузка/rollback выключают auto.

## Настройки

ProfileState содержит: fullscreen(bool), textCps(float 0..120; 0=instant), afmTime(float 0..30), musicVolume/sfxVolume/voiceVolume(float 0..1), muteAll(bool), pixelVoiceEnabled(bool), skipUnread(bool), continueSkipAfterChoice(bool), skipTransitions(bool). Defaults громкостей взять из Reference/options, остальные — здесь/00_CONTRACTS. Cps modifiers применяются к базовому CPS; instant не порождает division by zero и audio ticks.

Текстовые слайдеры и volume работают с обратной связью без перезапуска сцены. Mute хранит прежние значения каналов и не заменяет их нулями. Fullscreen доступен из меню и по Alt+Enter; возврат в оконный режим восстанавливает последний валидный window size. Profile errors показываются Notify, не сбрасывают всю сессию.

## Управление v1

ЛКМ по игровой области, Space/Enter — advance; ПКМ/Escape — game menu/back верхнего экрана; колесо вверх/PageUp — rollback; H — hide/show игровой UI; Ctrl — hold skip; Tab — UI focus, не skip; Alt+Enter — fullscreen. Quick menu: rollback, history, skip, auto, save, quicksave, quickload, preferences. Исходные подписи сохранить; Help обновить под этот фактический набор.

Hide UI скрывает dialogue/quick menu, сохраняет состояние; H или advance только возвращает UI и потребляет событие без смены реплики. На экранах меню hotkeys gameplay отключены. При потере focus active timers заморожены; ввод при возврате не считается новым click.

## Приемка

Проверить одни и те же counters после ручного чтения, skip, auto, save/load и rollback. История не содержит tags waits и не дублируется после reload. 101 checkpoint корректно ограничивается 100. Барьер непроходим. Выбор остается ручным. Настройки сохраняются после restart, mute не теряет уровни. Создать `Reports/08_RESULT.md` с таблицей переходов режимов, hotkeys и воспроизводимыми тестами; отдельно результаты, ожидающие запуска.
