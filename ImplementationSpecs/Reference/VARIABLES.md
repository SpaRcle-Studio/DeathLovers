# Переменные

Статические данные; точные чтения и записи с файлами и строками — VARIABLE_USES.tsv. Начальные определения: script.rpy:1–8.

| Имя | Тип | Начало | Запись/чтение |
|---|---|---|---|
| var_offices_visited | bool | False | True перед переходом к офису; условия каждого меню навигации, общий цикл:286 |
| var_canteen_visited | bool | False | True перед переходом в столовую; те же условия |
| var_landfill_visited | bool | False | True перед переходом на свалку; те же условия |
| var_roots | int | 0 | +1 при входе :299/:1154/:1909; условия порядка и окончания |
| var_hunger_score | int | 0 | +0/+1/+2 в трех меню столовой; сравнения ending:2580–2602 |
| var_war_score | int | 0 | +0/+1/+2 в меню Войны; промежуточные >=5/<5 и ending |
| var_plague_score | int | 0 | +0/+1/+2/+3 в меню Чумы; промежуточные >=5/<5 и ending |

Флаги монотонны в одной новой игре. Условия `if not ..._visited` убирают повторное посещение, а не обнуляют его счет. Загрузка/rollback восстанавливают снимок; глобальный сброс через full_restart начинает новую игру. `var_roots` считает входы, а не число положительных отношений. Порядок влияет на текст (:642,902,1011,1051,1118,1469,1705,1799,1856,1868,2234,2241,2546) и поток. Явных начислений очков в зависимости от порядка не найдено. :642 проверяет >=1 и при штатном входе в свалку всегда истинно.

Дополнительные реально используемые данные вне семи сюжетных переменных:

- characters.rpy: custom_text_color="#ffffff", character_store={}, nvl_narrator, nvl_text="empty text", контроллеры и масштабы; это состояние представления, а не новые сюжетные флаги.
- audio.rpy: persistent.pixel_voice_enabled=True; last_typewriter_sound_time=0.0, active_voice_path="voice/voice.wav", active_voice_interval_multiplier=1.0, count_channels=10, current_channel=0. Реальное состояние десяти каналов и Python-объекты не сериализовать как объекты.
- options.rpy: persistent.set_volumes=False; preferences.text_cps=30:164, preferences.afm_time=15:170.
- screens.rpy: quick_menu=True; main_menu_parallax_smx/smy=0.0; screen-local device, page_name_value и др. Полные определения/использование — SOURCE_LINES.tsv.

Неизвестное `[x3]` в реплике :2866 не считать восьмой сюжетной переменной: определения нет, см. DEFECTS D006.
