//
// Created by Codex on 16.11.2026.
//

interface IMenuSessionStarter
{
    bool StartSession();
}

#include "../Runtime/NovelSession.as"

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
    GameObject@ quickMenu;
    GameObject@ readingHistory;
    GameObject@ mainMenuButton;
    UIButton@ rollbackButton;
    bool pendingMainMenu = false;
    UIButton@ submenuOrigin;
    UIButton@ modalOrigin;
    AudioSource@ music;
    IMenuSessionStarter@ sessionStarter;
    NovelSession@ runtime;
    bool gameMenuOpen = false;
    bool developmentRuntime = true;
    String runtimeProbeReport = "AWAITING_USER_RUN";
    TextMesh@ runtimeProbeText;
    bool inGame = false;
    bool pendingQuit = false;
    bool syncing = false;
    float inputBarrier = 0;
    float notifyTime = 0;
    TextMesh@ fadingScreen;
    Sprite@ tabBackground;
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

    void ScreenOpacity(GameObject@ screen, float opacity)
    {
        cast<TextMesh@>(screen.GetComponent("TextMesh")).SetSubtreeOpacity(opacity);
    }

    void Start()
    {
        @novel = Child(gameObject, "Novel");
        @tabBackground = cast<Sprite@>(Child(novel, "TabBackground").GetComponent("Sprite"));
        TabBackgroundOpacity(0.0f);
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
        @quickMenu = Child(novel, "QuickMenu");
        @readingHistory = Child(novel, "ReadingHistory");
        @mainMenuButton = Child(Child(main, "Navigation"), "ReturnMainMenu");
        quickMenu.SetEnabled(false);
        readingHistory.SetEnabled(false);
        mainMenuButton.SetEnabled(false);
        @rollbackButton = Button(quickMenu, "Rollback");
        Button(quickMenu, "Save").SetInteractable(false);
        Button(quickMenu, "QuickSave").SetInteractable(false);
        Button(quickMenu, "QuickLoad").SetInteractable(false);
        cast<Sprite@>(Child(readingHistory, "Backdrop").GetComponent("Sprite")).SetMaterial("DeathLovers/Materials/RuntimeBlack.mat");
        GameObject@ historyViewport = Child(readingHistory, "Viewport");
        UIScrollRect@ historyScroll = cast<UIScrollRect@>(historyViewport.GetComponent("UIScrollRect"));
        historyScroll.SetViewport(historyViewport);
        historyScroll.SetContent(Child(historyViewport, "Content"));
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
        @runtime = NovelSession();
        runtime.Configure(this, gameObject.GetComponent("Behaviour"));
        @sessionStarter = runtime;
        if (developmentRuntime && runtime.configured)
        {
            BuildRuntimeProbe();
        }
        Button(Child(main, "Navigation"), "Start").Focus();
    }

    bool CanNavigate()
    {
        return inputBarrier <= 0 && fadingScreen is null;
    }

    void TabBackgroundOpacity(float opacity)
    {
        tabBackground.SetSubtreeOpacity(opacity);
        tabBackground.GetGameObject().SetEnabled(opacity > 0.0f);
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
        TabBackgroundOpacity(submenu is null ? 0.0f : 1.0f);
        @fadingScreen = cast<TextMesh@>(screen.GetComponent("TextMesh"));
        fadeTime = 0;
        fadeClosing = false;
        ScreenOpacity(fadingFrom, 1.0f);
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
        if (inGame && gameMenuOpen)
        {
            ToggleGameMenu();
            return;
        }
        if (sessionStarter !is null && sessionStarter.StartSession())
        {
            inGame = true;
            ScreenOpacity(main, 0.0f);
            main.SetEnabled(false);
            music.Stop();
            inputBarrier = 0.1f;
            return;
        }
        String error = runtime is null ? "Исполнитель новеллы не инициализирован. Подробности в журнале движка." : runtime.startupError;
        ShowNotify(error, Button(Child(main, "Navigation"), "Start"));
    }

    void Back()
    {
        if (inGame && gameMenuOpen && modal is null && submenu is null && CanNavigate())
        {
            ToggleGameMenu();
            return;
        }
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
            pendingMainMenu = false;
            if (modalOrigin !is null)
            {
                modalOrigin.Focus();
            }
            return;
        }
        if (submenu !is null)
        {
            @fadingFrom = submenu;
            @fadingScreen = cast<TextMesh@>(submenu.GetComponent("TextMesh"));
            fadeTime = 0;
            fadeClosing = true;
            transitionBlocker.SetEnabled(true);
            inputBarrier = 0.5f;
            @submenu = null;
            ScreenOpacity(main, 0.0f);
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
        pendingMainMenu = false;
        Text(Child(confirm, "Content"), "Message", "Выйти из игры?");
        @modal = confirm;
        pendingQuit = true;
        confirm.SetEnabled(true);
        Button(Child(Child(confirm, "Content"), "Qestion"), "No").Focus();
        inputBarrier = 0.1f;
    }

    void ReturnToMainMenu()
    {
        if (runtime !is null)
        {
            runtime.End();
        }
        gameMenuOpen = false;
        TabBackgroundOpacity(0.0f);
        Text(Child(main, "Navigation"), "Start", "Начать");
        Child(novel, "Background").SetEnabled(true);
        if (fadingScreen !is null)
        {
            fadingScreen.SetSubtreeOpacity(0.0f);
            @fadingScreen = null;
        }
        if (fadingFrom !is null && fadingFrom !is main)
        {
            ScreenOpacity(fadingFrom, 0.0f);
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
            ScreenOpacity(submenu, 0.0f);
            submenu.SetEnabled(false);
            @submenu = null;
        }
        pendingQuit = false;
        inGame = false;
        MenuSession::activeScreen = "MainMenu";
        ScreenOpacity(main, 1.0f);
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
        if (CanNavigate() && pendingMainMenu && modal is confirm)
        {
            pendingMainMenu = false;
            ReturnToMainMenu();
            return;
        }
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

    void RollbackStory()
    {
        runtime.Rollback();
    }

    void ToggleSkip()
    {
        runtime.skipEnabled = !runtime.skipEnabled;
        runtime.autoEnabled = false;
    }

    void ToggleAuto()
    {
        runtime.autoEnabled = !runtime.autoEnabled;
        runtime.skipEnabled = false;
        runtime.autoDelay = 0;
    }

    void UnavailableSave()
    {
        ShowNotify("Сохранения пока недоступны.", Button(quickMenu, "Save"));
    }

    void ReadingOptions()
    {
        ToggleGameMenu();
        inputBarrier = 0;
        OpenPreferences();
    }

    void OpenHistory()
    {
        if (!inGame || modal !is null || !CanNavigate())
        {
            return;
        }
        runtime.skipEnabled = false;
        runtime.autoEnabled = false;
        String content;
        for (uint i = 0; i < runtime.state.core.history.size(); ++i)
        {
            NovelHistoryEntry@ entry = runtime.state.core.history[i];
            DialogueProgram line;
            line.Compile(entry.text, false);
            String name = runtime.speakers.at(entry.speakerId).name;
            content = content + (name == "" ? "" : name + ":\n") + line.plain + "\n\n";
        }
        GameObject@ viewport = Child(readingHistory, "Viewport");
        GameObject@ body = Child(viewport, "Content");
        TextMesh@ text = cast<TextMesh@>(body.GetComponent("TextMesh"));
        text.horizontalAlignment = TextAlignmentHorizontal::Left;
        text.verticalAlignment = TextAlignmentVertical::Top;
        text.SetMaterial("DeathLovers/Materials/RuntimeText.mat");
        text.SetText(content);
        readingHistory.SetEnabled(true);
        float height = text.GetTextBounds().h + 60;
        cast<TransformRect@>(body.GetTransform()).SetSize(runtime.view.Vec(1200, height > 850 ? height : 850));
        cast<UIScrollRect@>(viewport.GetComponent("UIScrollRect")).SetNormalizedPosition(runtime.view.Vec(0, 1));
        @modal = readingHistory;
        Button(readingHistory, "Back").Focus();
        inputBarrier = 0.1f;
    }

    void CloseHistory()
    {
        readingHistory.SetEnabled(false);
        @modal = null;
        inputBarrier = 0.1f;
        runtime.inputBarrier = 0.1f;
        runtime.view.FocusNarrative(runtime.PhaseName() == "WaitingChoice");
    }

    void RequestMainMenu()
    {
        if (!inGame || modal !is null || !CanNavigate())
        {
            return;
        }
        pendingMainMenu = true;
        pendingQuit = false;
        @modalOrigin = gameMenuOpen ? cast<UIButton@>(mainMenuButton.GetComponent("UIButton")) : Button(quickMenu, "MainMenu");
        Text(Child(confirm, "Content"), "Message", "Вернуться в главное меню?\nНесохранённый прогресс будет потерян.");
        @modal = confirm;
        confirm.SetEnabled(true);
        Button(Child(Child(confirm, "Content"), "Qestion"), "No").Focus();
        inputBarrier = 0.1f;
    }

    void Update(float dt)
    {
        quickMenu.SetEnabled(inGame && !gameMenuOpen && modal is null);
        mainMenuButton.SetEnabled(inGame);
        if (runtime !is null && runtime.state !is null)
        {
            rollbackButton.SetInteractable(runtime.CanRollback());
        }
        MenuSession::skipActive = inGame && !gameMenuOpen && modal is null && runtime !is null &&
            (runtime.skipEnabled || Input::Instance().GetKey(KeyCode::LCtrl) || Input::Instance().GetKey(KeyCode::RCtrl));
        MenuSession::autoActive = inGame && runtime !is null && runtime.autoEnabled;
        if (modal is readingHistory && CanNavigate() && Input::Instance().GetKeyDown(KeyCode::Escape))
        {
            CloseHistory();
            return;
        }
        if (fadingScreen !is null)
        {
            fadeTime += dt;
            float progress = fadeTime < 0.5f ? fadeTime / 0.5f : 1.0f;
            fadingScreen.SetSubtreeOpacity(fadeClosing ? 1.0f - progress : progress);
            ScreenOpacity(fadeClosing ? main : fadingFrom, fadeClosing ? progress : 1.0f - progress);
            TabBackgroundOpacity(fadeClosing ? 1.0f - progress : fadingFrom is main ? progress : 1.0f);
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
            if (inGame && submenu is null)
            {
                ToggleGameMenu();
            }
            else
            {
                Back();
            }
        }
        if (runtime !is null)
        {
            runtime.Update(dt);
        }
    }

    void ToggleGameMenu()
    {
        if (!inGame || !CanNavigate() || modal !is null || submenu !is null)
        {
            return;
        }
        gameMenuOpen = !gameMenuOpen;
        ScreenOpacity(main, gameMenuOpen ? 1.0f : 0.0f);
        main.SetEnabled(gameMenuOpen);
        Text(Child(main, "Navigation"), "Start", "Продолжить");
        Child(novel, "Background").SetEnabled(gameMenuOpen);
        runtime.view.root.SetEnabled(!gameMenuOpen);
        MenuSession::activeScreen = gameMenuOpen ? "GameMenu" : "Story";
        inputBarrier = 0.1f;
        runtime.inputBarrier = 0.1f;
        if (gameMenuOpen)
        {
            Button(Child(main, "Navigation"), "Preferences").Focus();
        }
        else
        {
            runtime.view.FocusNarrative(runtime.PhaseName() == "WaitingChoice");
        }
    }

    void AdvanceStory()
    {
        runtime.skipEnabled = false;
        runtime.autoEnabled = false;
        runtime.Advance();
    }

    void Choose0()
    {
        runtime.Choose(0);
    }

    void Choose1()
    {
        runtime.Choose(1);
    }

    void Choose2()
    {
        runtime.Choose(2);
    }

    void Choose3()
    {
        runtime.Choose(3);
    }

    void Choose4()
    {
        runtime.Choose(4);
    }

    void Choose5()
    {
        runtime.Choose(5);
    }

    void Choose6()
    {
        runtime.Choose(6);
    }

    void Choose7()
    {
        runtime.Choose(7);
    }

    void BuildRuntimeProbe()
    {
        GameObject@ probe = runtime.view.Rect(novel, "RuntimeProbe", 360, 0, 1170, 100);
        for (uint i = 0; i < 3; ++i)
        {
            String name = i == 0 ? "Fixture" : i == 1 ? "RestoreTwice" : "Trace";
            GameObject@ button = runtime.view.Rect(probe, name, float(i) * 350, 0, 340, 40);
            runtime.view.Label(button, name);
            UIButton@ control = cast<UIButton@>(button.GetOrCreateComponent("UIButton"));
            control.SetClickReceiver(gameObject.GetComponent("Behaviour"), i == 0 ? "StartRuntimeFixture" : i == 1 ? "VerifyRuntimeSnapshot" : "ShowRuntimeTrace");
        }
        @runtimeProbeText = runtime.view.Label(runtime.view.Rect(probe, "Result", 0, 45, 1170, 50), "AWAITING_USER_RUN");
    }

    void StartRuntimeFixture()
    {
        if (developmentRuntime)
        {
            runtimeProbeText.SetText(runtime.StartFixture() ? "Fixture started" : "Fixture load failed");
        }
    }

    void VerifyRuntimeSnapshot()
    {
        if (developmentRuntime)
        {
            NovelRestoreReport@ result = runtime.VerifyRestoreTwice();
            runtimeProbeReport = SerializeScriptValue(result);
            runtimeProbeText.SetText(result.status);
        }
    }

    void ShowRuntimeTrace()
    {
        if (developmentRuntime)
        {
            runtimeProbeReport = SerializeScriptValue(runtime.trace);
            runtimeProbeText.SetText("Trace in runtimeProbeReport: " + RuntimeValues::Index(runtime.trace.size()) + " commands");
            if (inGame && !gameMenuOpen)
            {
                runtime.view.FocusNarrative(runtime.PhaseName() == "WaitingChoice");
            }
        }
    }

    void OnDestroy()
    {
        if (runtime !is null)
        {
            runtime.End();
        }
        if (music !is null)
        {
            music.Stop();
        }
    }
}
