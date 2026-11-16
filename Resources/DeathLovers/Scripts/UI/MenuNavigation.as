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
    GameObject@ transitionBlocker;
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
    Sprite@ fadingScreen;
    GameObject@ fadingFrom;
    float fadeTime = 0;
    bool fadeClosing = false;

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
        @transitionBlocker = Child(novel, "TransitionBlocker");
        transitionBlocker.SetEnabled(false);
        preferences.SetEnabled(false);
        load.SetEnabled(false);
        about.SetEnabled(false);
        help.SetEnabled(false);
        sessionStart.SetEnabled(false);
        confirm.SetEnabled(false);
        notify.SetEnabled(false);
        @music = cast<AudioSource@>(Child(gameObject, "MenuMusic").GetComponent("AudioSource"));
        music.SetSpatialize(SpatializeMode::Off);
        music.SetPitch(1.0f);
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
        return inputBarrier <= 0 && fadingScreen is null;
    }

    void Open(GameObject@ screen, const String &in origin)
    {
        if (!CanNavigate() || modal !is null)
        {
            return;
        }
        if (submenu is screen)
        {
            return;
        }
        @fadingFrom = submenu is null ? main : submenu;
        @fadingScreen = cast<Sprite@>(screen.GetComponent("Sprite"));
        fadeTime = 0;
        fadeClosing = false;
        fadingScreen.SetSubtreeOpacity(0.0f);
        transitionBlocker.SetEnabled(true);
        @submenuOrigin = Button(Child(main, "Navigation"), origin);
        @submenu = screen;
        screen.SetEnabled(true);
        MenuSession::activeScreen = screen.GetName();
        Button(screen, "Back").Focus();
        inputBarrier = 0.5f;
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
        if (!CanNavigate() || modal !is null)
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
            @fadingFrom = submenu;
            @fadingScreen = cast<Sprite@>(submenu.GetComponent("Sprite"));
            fadeTime = 0;
            fadeClosing = true;
            transitionBlocker.SetEnabled(true);
            inputBarrier = 0.5f;
            @submenu = null;
            main.SetEnabled(true);
            MenuSession::activeScreen = "MainMenu";
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
        if (fadingScreen !is null)
        {
            fadingScreen.SetSubtreeOpacity(1.0f);
            @fadingScreen = null;
        }
        if (fadingFrom !is null && fadingFrom !is main)
        {
            fadingFrom.SetEnabled(false);
        }
        @fadingFrom = null;
        transitionBlocker.SetEnabled(false);
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
        MenuSession::activeScreen = "MainMenu";
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

    void ChangeSliders()
    {
        if (syncing || modal !is null || !CanNavigate())
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
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.pixel_voice = !MenuSession::profile.settings.pixel_voice;
    }

    void ToggleMute()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.mute = !MenuSession::profile.settings.mute;
        ApplyAudio();
    }

    void ToggleSkipUnseen()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.skip_unseen = !MenuSession::profile.settings.skip_unseen;
    }

    void ToggleSkipChoices()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.skip_after_choices = !MenuSession::profile.settings.skip_after_choices;
    }

    void ToggleSkipTransitions()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.skip_transitions = !MenuSession::profile.settings.skip_transitions;
    }

    void Windowed()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.fullscreen = false;
        ApplicationManager::Instance().GetApplication().GetEngine().SetFullscreen(false);
    }

    void Fullscreen()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.fullscreen = true;
        ApplicationManager::Instance().GetApplication().GetEngine().SetFullscreen(true);
    }

    void Update(float dt)
    {
        if (fadingScreen !is null)
        {
            fadeTime += dt;
            float progress = fadeTime < 0.5f ? fadeTime / 0.5f : 1.0f;
            fadingScreen.SetSubtreeOpacity(fadeClosing ? 1.0f - progress : progress);
            if (progress >= 1.0f)
            {
                fadingFrom.SetEnabled(false);
                @fadingFrom = null;
                @fadingScreen = null;
                transitionBlocker.SetEnabled(false);
                if (fadeClosing)
                {
                    if (submenuOrigin !is null)
                    {
                        submenuOrigin.Focus();
                    }
                }
                else
                {
                    Button(submenu, "Back").Focus();
                }
            }
        }
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
