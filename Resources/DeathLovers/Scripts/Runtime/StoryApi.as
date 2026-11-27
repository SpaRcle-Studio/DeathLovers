//
// Created by Claude on 27.11.2026.
//

#include "StoryRunner.as"

// Story scripting API (Story/Script/*.as). A story label is a `void name()` function in namespace Story.
//
//   narrator("text");                 say; p("text"), p.say("text", false) without automatic pauses
//   p.show("happy"); p.show("sad", dissolve(0.5)); p.hide();
//   scene("images/background/office.png", fade());
//   play_music(id[, fade, loop]); stop_music([fade]); play_sound(id[, loop, fade]); stop_sound([fade]);
//   Menu menu; menu.option("text"[, condition]); switch (menu.show()) { case 0: ... }
//   call(label);   run another label and come back        jump(label);  replace the whole stack (never returns)
//   pause(seconds); wait_click(); nvl_clear(); barrier(); restart_to_menu();
//   v.<name>       story variables (Story/Script/Vars.as)
//
// Rules that keep save/load, rollback and hot reload exact:
//   * state that must survive goes to `v`; locals are recomputed on restore;
//   * behaviour must depend only on `v`, choices and constants (no time, no unseeded random);
//   * labels are entered only through call()/jump(), never by a plain function call.
namespace Story
{
    class Transition
    {
        String kind = "none";
        /// negative: default duration of the kind
        float seconds = -1;

        Transition()
        {
        }

        Transition(const String &in transitionKind, float transitionSeconds)
        {
            kind = transitionKind;
            seconds = transitionSeconds;
        }
    }

    Transition none()
    {
        return Transition("none", 0);
    }

    Transition fade(float seconds = -1)
    {
        return Transition("fade", seconds);
    }

    Transition dissolve(float seconds = -1)
    {
        return Transition("dissolve", seconds);
    }

    Transition vpunch(float seconds = -1)
    {
        return Transition("vpunch", seconds);
    }

    class Character
    {
        String id;
        String mode;

        Character(const String &in speakerId, const String &in speakerMode = "ADV")
        {
            id = speakerId;
            mode = speakerMode;
        }

        void opCall(const String &in text)
        {
            say(text, true);
        }

        void say(const String &in text, bool autoWait = true)
        {
            active.Say(id, mode, text, autoWait);
        }

        void show(const String &in state)
        {
            show(state, dissolve(0.15f));
        }

        void show(const String &in state, const Transition &in transition)
        {
            active.Show(id, state, transition.kind, transition.seconds);
        }

        void hide()
        {
            show("hidden");
        }
    }

    class Menu
    {
        Vector<String> texts;
        Vector<bool> available;

        void option(const String &in text, bool condition = true)
        {
            texts.pushBack(text);
            available.pushBack(condition);
        }

        /// index of the chosen option in declaration order
        int show()
        {
            return int(active.Choose(texts, available));
        }
    }

    void scene(const String &in resourceId)
    {
        active.Scene(resourceId, "none", 0);
    }

    void scene(const String &in resourceId, const Transition &in transition)
    {
        active.Scene(resourceId, transition.kind, transition.seconds);
    }

    void play_music(const String &in resourceId, float fade = 1.5f, bool loop = true)
    {
        active.Audio("Music", true, resourceId, loop, fade);
    }

    void stop_music(float fade = 0.5f)
    {
        active.Audio("Music", false, "", false, fade);
    }

    void play_sound(const String &in resourceId, bool loop = false, float fade = 0)
    {
        active.Audio("Sfx", true, resourceId, loop, fade);
    }

    void stop_sound(float fade = 0.5f)
    {
        active.Audio("Sfx", false, "", false, fade);
    }

    void nvl_clear()
    {
        active.NvlClear();
    }

    void pause(float seconds)
    {
        active.Pause(seconds, false);
    }

    void wait_click()
    {
        active.Pause(0, true);
    }

    /// forbids rolling back past this point (Ren'Py fix_rollback-like barrier after important choices)
    void barrier()
    {
        active.Barrier();
    }

    void call(CoroutineEntry@ label)
    {
        active.Call(label);
    }

    void jump(CoroutineEntry@ label)
    {
        active.Jump(label);
    }

    void restart_to_menu()
    {
        active.RestartToMenu();
    }
}
