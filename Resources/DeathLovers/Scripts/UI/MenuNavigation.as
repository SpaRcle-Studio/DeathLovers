//
// Created by Codex on 16.11.2026.
//

interface IMenuSessionStarter
{
    bool StartSession();
}

class MenuNavigation : ScriptBehaviour
{
    GameObject@ novel;
    GameObject@ main;
    GameObject@ preferences;
    GameObject@ load;
    GameObject@ about;
    GameObject@ help;
    GameObject@ sessionStart;
    GameObject@ confirm;
    GameObject@ notify;
    GameObject@ submenu;
    GameObject@ modal;
    UIButton@ submenuOrigin;
    UIButton@ modalOrigin;
    AudioSource@ music;
    IMenuSessionStarter@ sessionStarter;
    bool inGame = false;
    bool pendingQuit = false;
    bool syncing = false;
    float inputBarrier = 0;
    float notifyTime = 0;

    GameObject@ Child(GameObject@ parent, const String &in name)
    {
        return parent.GetOrCreateChild(name);
    }

    UIButton@ Button(GameObject@ parent, const String &in name)
    {
        return cast<UIButton@>(Child(parent, name).GetComponent("UIButton"));
    }

    void Text(GameObject@ parent, const String &in name, const String &in value)
    {
        cast<TextMesh@>(Child(parent, name).GetComponent("TextMesh")).SetText(value);
    }

    void Start()
    {
        @novel = Child(gameObject, "Novel");
        @main = Child(novel, "MainMenu");
        @preferences = Child(novel, "Preferences");
        @load = Child(novel, "Load");
        @about = Child(novel, "About");
        @help = Child(novel, "Help");
        @sessionStart = Child(novel, "SessionStart");
        @confirm = Child(novel, "Confirm");
        @notify = Child(novel, "Notify");
        preferences.SetEnabled(false);
        load.SetEnabled(false);
        about.SetEnabled(false);
        help.SetEnabled(false);
        sessionStart.SetEnabled(false);
        confirm.SetEnabled(false);
        notify.SetEnabled(false);
        @music = cast<AudioSource@>(Child(gameObject, "MenuMusic").GetComponent("AudioSource"));
        music.SetSpatialize(SpatializeMode::Off);
        music.SetPath("DeathLovers/Audio/music/main_menu.ogg");
        music.SetLoop(true);
        EnsureGroup("Music");
        EnsureGroup("Effects");
        EnsureGroup("Voice");
        music.SetGroup("Music");
        ApplyAudio();
        music.Play();
        TextMesh@ title = cast<TextMesh@>(Child(Child(main, "Heading"), "Title").GetComponent("TextMesh"));
        TextStyle strike;
        strike.begin = 16;
        strike.end = 21;
        strike.strike = true;
        title.AddStyle(strike);
        Button(Child(main, "Navigation"), "Start").Focus();
    }

    bool CanNavigate()
    {
        return inputBarrier <= 0;
    }

    void Open(GameObject@ screen, const String &in origin)
    {
        if (!CanNavigate() || modal !is null || submenu !is null)
        {
            return;
        }
        @submenuOrigin = Button(Child(main, "Navigation"), origin);
        @submenu = screen;
        main.SetEnabled(false);
        screen.SetEnabled(true);
        Button(screen, "Back").Focus();
        inputBarrier = 0.1f;
    }

    void OpenLoad()
    {
        Open(load, "Load");
    }

    void OpenPreferences()
    {
        Open(preferences, "Preferences");
        if (submenu is preferences)
        {
            SyncPreferences();
        }
    }

    void OpenAbout()
    {
        Open(about, "About");
    }

    void OpenHelp()
    {
        Open(help, "Help");
    }

    void StartSession()
    {
        if (!CanNavigate() || modal !is null || submenu !is null)
        {
            return;
        }
        if (sessionStarter !is null && sessionStarter.StartSession())
        {
            inGame = true;
            main.SetEnabled(false);
            music.Stop();
            inputBarrier = 0.1f;
            return;
        }
        Open(sessionStart, "Start");
    }

    void Back()
    {
        if (!CanNavigate() || (modal is null && submenu is null))
        {
            return;
        }
        inputBarrier = 0.1f;
        if (modal !is null)
        {
            modal.SetEnabled(false);
            @modal = null;
            pendingQuit = false;
            if (modalOrigin !is null)
            {
                modalOrigin.Focus();
            }
            return;
        }
        if (submenu !is null)
        {
            submenu.SetEnabled(false);
            @submenu = null;
            main.SetEnabled(true);
            if (submenuOrigin !is null)
            {
                submenuOrigin.Focus();
            }
        }
    }

    void Quit()
    {
        if (!CanNavigate() || modal !is null)
        {
            return;
        }
        if (!inGame)
        {
            ApplicationManager::Instance().GetApplication().GetEngine().RequestQuit();
            return;
        }
        QuitFromGame(submenu is null ? Button(Child(main, "Navigation"), "Quit") : Button(submenu, "Back"));
    }

    void QuitFromGame(UIButton@ origin)
    {
        if (!CanNavigate() || modal !is null)
        {
            return;
        }
        @modalOrigin = origin;
        @modal = confirm;
        pendingQuit = true;
        confirm.SetEnabled(true);
        Button(Child(confirm, "Content"), "No").Focus();
        inputBarrier = 0.1f;
    }

    void ReturnToMainMenu()
    {
        if (modal !is null)
        {
            modal.SetEnabled(false);
            @modal = null;
        }
        if (submenu !is null)
        {
            submenu.SetEnabled(false);
            @submenu = null;
        }
        pendingQuit = false;
        inGame = false;
        main.SetEnabled(true);
        if (!music.IsPlaying())
        {
            music.Play();
        }
        Button(Child(main, "Navigation"), "Start").Focus();
        inputBarrier = 0.1f;
    }

    void ConfirmYes()
    {
        if (CanNavigate() && pendingQuit && modal is confirm)
        {
            ApplicationManager::Instance().GetApplication().GetEngine().RequestQuit();
        }
    }

    void ShowNotify(const String &in message, UIButton@ origin)
    {
        if (modal !is null)
        {
            return;
        }
        @modalOrigin = origin;
        Text(Child(notify, "Content"), "Message", message);
        @modal = notify;
        notifyTime = 3.25f;
        notify.SetEnabled(true);
        Button(Child(notify, "Content"), "Close").Focus();
        inputBarrier = 0.1f;
    }

    void ApplyAudio()
    {
        music.SetVolume(1.0f);
        AudioMixer::Instance().SetGroupVolume("Music", MenuSession::profile.settings.music_volume);
        AudioMixer::Instance().SetGroupVolume("Effects", MenuSession::profile.settings.sfx_volume);
        AudioMixer::Instance().SetGroupVolume("Voice", MenuSession::profile.settings.voice_volume);
        AudioMixer::Instance().SetMasterVolume(MenuSession::profile.settings.mute ? 0.0f : 1.0f);
    }

    void EnsureGroup(const String &in name)
    {
        if (!AudioMixer::Instance().HasGroup(name))
        {
            AudioMixerGroup group;
            group.name = name;
            AudioMixer::Instance().AddGroup(group);
        }
    }

    GameObject@ Settings()
    {
        return Child(Child(Child(preferences, "SettingsScroll"), "Viewport"), "Settings");
    }

    void SyncPreferences()
    {
        syncing = true;
        cast<UISlider@>(Child(PreferenceGroup("Music"), "Music").GetComponent("UISlider")).SetValue(MenuSession::profile.settings.music_volume);
        cast<UISlider@>(Child(PreferenceGroup("Sfx"), "Sfx").GetComponent("UISlider")).SetValue(MenuSession::profile.settings.sfx_volume);
        cast<UISlider@>(Child(PreferenceGroup("Voice"), "Voice").GetComponent("UISlider")).SetValue(MenuSession::profile.settings.voice_volume);
        cast<UISlider@>(Child(PreferenceGroup("TextSpeed"), "TextSpeed").GetComponent("UISlider")).SetValue(MenuSession::profile.settings.text_cps);
        cast<UISlider@>(Child(PreferenceGroup("AutoSpeed"), "AutoSpeed").GetComponent("UISlider")).SetValue(MenuSession::profile.settings.afm_time);
        RefreshChecks();
        syncing = false;
    }

    GameObject@ PreferenceGroup(const String &in name)
    {
        if (name == "TextSpeed" || name == "AutoSpeed")
        {
            return Child(Child(Settings(), "Sliders"), "Text");
        }
        if (name == "SkipUnseen" || name == "SkipChoices" || name == "SkipTransitions")
        {
            return Child(Child(Settings(), "General"), "Skip");
        }
        return Child(Child(Settings(), "Sliders"), "Audio");
    }

    void RefreshChecks()
    {
        Text(PreferenceGroup("PixelVoice"), "PixelVoice", MenuSession::profile.settings.pixel_voice ? "[X] Пиксель-войс" : "[ ] Пиксель-войс");
        Text(PreferenceGroup("Mute"), "Mute", MenuSession::profile.settings.mute ? "[X] Без звука" : "[ ] Без звука");
        Text(PreferenceGroup("SkipUnseen"), "SkipUnseen", MenuSession::profile.settings.skip_unseen ? "[X] Всего текста" : "[ ] Всего текста");
        Text(PreferenceGroup("SkipChoices"), "SkipChoices", MenuSession::profile.settings.skip_after_choices ? "[X] После выборов" : "[ ] После выборов");
        Text(PreferenceGroup("SkipTransitions"), "SkipTransitions", MenuSession::profile.settings.skip_transitions ? "[X] Переходов" : "[ ] Переходов");
    }

    void ChangeSliders()
    {
        if (syncing || modal !is null)
        {
            return;
        }
        MenuSession::profile.settings.music_volume = cast<UISlider@>(Child(PreferenceGroup("Music"), "Music").GetComponent("UISlider")).GetValue();
        MenuSession::profile.settings.sfx_volume = cast<UISlider@>(Child(PreferenceGroup("Sfx"), "Sfx").GetComponent("UISlider")).GetValue();
        MenuSession::profile.settings.voice_volume = cast<UISlider@>(Child(PreferenceGroup("Voice"), "Voice").GetComponent("UISlider")).GetValue();
        MenuSession::profile.settings.text_cps = cast<UISlider@>(Child(PreferenceGroup("TextSpeed"), "TextSpeed").GetComponent("UISlider")).GetValue();
        MenuSession::profile.settings.afm_time = cast<UISlider@>(Child(PreferenceGroup("AutoSpeed"), "AutoSpeed").GetComponent("UISlider")).GetValue();
        ApplyAudio();
    }

    void TogglePixelVoice()
    {
        MenuSession::profile.settings.pixel_voice = !MenuSession::profile.settings.pixel_voice;
        RefreshChecks();
    }

    void ToggleMute()
    {
        MenuSession::profile.settings.mute = !MenuSession::profile.settings.mute;
        ApplyAudio();
        RefreshChecks();
    }

    void ToggleSkipUnseen()
    {
        MenuSession::profile.settings.skip_unseen = !MenuSession::profile.settings.skip_unseen;
        RefreshChecks();
    }

    void ToggleSkipChoices()
    {
        MenuSession::profile.settings.skip_after_choices = !MenuSession::profile.settings.skip_after_choices;
        RefreshChecks();
    }

    void ToggleSkipTransitions()
    {
        MenuSession::profile.settings.skip_transitions = !MenuSession::profile.settings.skip_transitions;
        RefreshChecks();
    }

    void Windowed()
    {
        MenuSession::profile.settings.fullscreen = false;
        ApplicationManager::Instance().GetApplication().GetEngine().SetFullscreen(false);
    }

    void Fullscreen()
    {
        MenuSession::profile.settings.fullscreen = true;
        ApplicationManager::Instance().GetApplication().GetEngine().SetFullscreen(true);
    }

    void Update(float dt)
    {
        if (inputBarrier > 0)
        {
            inputBarrier -= dt;
        }
        if (modal is notify)
        {
            notifyTime -= dt;
            if (notifyTime <= 0)
            {
                Back();
            }
        }
        if (modal is null && CanNavigate() && Input::Instance().GetKeyDown(KeyCode::Escape))
        {
            Back();
        }
    }

    void OnDestroy()
    {
        if (music !is null)
        {
            music.Stop();
        }
    }
}
