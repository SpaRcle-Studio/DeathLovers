# Created by Codex on 16.11.2026.
default visited = False
default score = 0
label start:
    call nested
    if visited:
        if score >= 1:
            $ ch_death.say("{i}Текст {b}с пересечением{/i}{/b}")
        else:
            $ ch_death.say("Нулевая ветка")
    menu:
        "Повтор" if score < 1:
            $ score += 1
        "Далее":
            $ ch_death.say("$ renpy.full_restart(config.game_main_transition) — это строка")
    nvl clear
    scene black
    pause 0.25
    $ renpy.block_rollback()
    $ renpy.full_restart(config.game_main_transition)
label nested:
    $ visited = True
    $ score += 1
    return
