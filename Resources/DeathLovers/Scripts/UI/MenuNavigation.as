//
// Created by Codex on 16.11.2026.
//

interface IMenuSessionStarter
{
    bool StartSession();
}

#include "../Runtime/NovelSession.as"
#include "../Runtime/NovelSaves.as"

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
    NovelSaves saves;
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
    bool altEnterLatched = false;
    /// The in-game menu fades in/out over the paused story frame.
    bool gameMenuFading = false;
    bool gameMenuFadeOpening = false;
    float gameMenuFade = 0;
    /// The submenu was opened from the quick menu: the game menu stays invisible and Back returns to the story.
    bool quickSubmenu = false;
    GameObject@ plagueSilhouette;
    GameObject@ hungerSilhouette;
    GameObject@ warSilhouette;
    GameObject@ plagueCharacter;
    GameObject@ hungerCharacter;
    GameObject@ warCharacter;
    Map<String, bool> menuTextures;

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
        // Above TabBackground (90), below the submenus (100): in game the menu is drawn over the dark backdrop.
        cast<TransformRect@>(main.GetTransform()).localPriority = 95;
        PlatformType platform = ApplicationManager::Instance().GetApplication().GetPlatformType();
        bool showQuit = platform != PlatformType::Android && platform != PlatformType::Emscripten;
        Child(Child(main, "Navigation"), "Quit").SetEnabled(showQuit);
        @preferences = Child(novel, "Preferences");
        @load = Child(novel, "Load");
        @about = Child(novel, "About");
        @help = Child(novel, "Help");
        @sessionStart = Child(novel, "SessionStart");
        Child(Child(preferences, "Navigation"), "Quit").SetEnabled(showQuit);
        Child(Child(load, "Navigation"), "Quit").SetEnabled(showQuit);
        Child(Child(about, "Navigation"), "Quit").SetEnabled(showQuit);
        Child(Child(help, "Navigation"), "Quit").SetEnabled(showQuit);
        Child(Child(sessionStart, "Navigation"), "Quit").SetEnabled(showQuit);
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
        saves.Configure(this);
        BuildMenuCharacters();
        RefreshMenuCharacters();
        ApplyAudio();
        ApplicationManager::Instance().GetApplication().GetEngine().SetFullscreen(MenuSession::profile.settings.fullscreen);
        @sessionStarter = runtime;
        if (developmentRuntime && runtime.configured)
        {
            BuildRuntimeProbe();
        }
        Button(Child(main, "Navigation"), "Start").Focus();
        if (saves.diagnostic != "")
        {
            ShowNotify(saves.diagnostic, Button(Child(main, "Navigation"), "Start"));
        }
    }

    bool CanNavigate()
    {
        // Alt+Enter toggles fullscreen: Enter must not also activate the focused button.
        bool alt = Input::Instance().GetKey(KeyCode::LAlt) || Input::Instance().GetKey(KeyCode::RAlt);
        return inputBarrier <= 0 && fadingScreen is null && !gameMenuFading && !saves.busy && !alt;
    }

    /// In the game menu (not opened from the quick menu) the dark backdrop stays under the navigation and the submenus.
    bool GameMenuBackdrop()
    {
        return gameMenuOpen && !quickSubmenu;
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
        TabBackgroundOpacity(submenu is null && !GameMenuBackdrop() ? 0.0f : 1.0f);
        @fadingScreen = cast<TextMesh@>(screen.GetComponent("TextMesh"));
        fadeTime = 0;
        fadeClosing = false;
        ScreenOpacity(fadingFrom, quickSubmenu && fadingFrom is main ? 0.0f : 1.0f);
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
        saves.Open(false);
    }

    void OpenSave() { saves.Open(true); }
    void QuickSave() { saves.QuickSave(); }
    void QuickLoad() { saves.QuickLoad(); }
    void ManualSaves() { saves.SelectGroup("manual"); }
    void AutoSaves() { saves.SelectGroup("auto"); }
    void QuickSaves() { saves.SelectGroup("quick"); }
    void PreviousSavePage()
    {
        if (CanNavigate() && modal is null && saves.page > 1)
        {
            --saves.page;
            saves.Refresh();
        }
    }
    void NextSavePage()
    {
        if (CanNavigate() && modal is null && saves.page < 10)
        {
            ++saves.page;
            saves.Refresh();
        }
    }
    void SaveSlot0() { saves.Select(0, false); }
    void SaveSlot1() { saves.Select(1, false); }
    void SaveSlot2() { saves.Select(2, false); }
    void SaveSlot3() { saves.Select(3, false); }
    void SaveSlot4() { saves.Select(4, false); }
    void SaveSlot5() { saves.Select(5, false); }
    void DeleteSlot0() { saves.Select(0, true); }
    void DeleteSlot1() { saves.Select(1, true); }
    void DeleteSlot2() { saves.Select(2, true); }
    void DeleteSlot3() { saves.Select(3, true); }
    void DeleteSlot4() { saves.Select(4, true); }
    void DeleteSlot5() { saves.Select(5, true); }

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
            saves.pendingAction = "";
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
            main.SetEnabled(!quickSubmenu);
            MenuSession::activeScreen = gameMenuOpen ? "GameMenu" : "MainMenu";
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
            saves.FlushProfile();
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
        saves.FlushProfile();
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
        quickSubmenu = false;
        gameMenuFading = false;
        RefreshMenuCharacters();
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
        if (CanNavigate() && modal is confirm && saves.pendingAction != "")
        {
            saves.ConfirmYes();
            return;
        }
        if (CanNavigate() && pendingMainMenu && modal is confirm)
        {
            pendingMainMenu = false;
            ReturnToMainMenu();
            return;
        }
        if (CanNavigate() && pendingQuit && modal is confirm)
        {
            saves.FlushProfile();
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
        saves.MarkProfile();
        ApplyAudio();
    }

    void TogglePixelVoice()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.pixel_voice = !MenuSession::profile.settings.pixel_voice;
        saves.MarkProfile();
    }

    void ToggleMute()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.mute = !MenuSession::profile.settings.mute;
        saves.MarkProfile();
        ApplyAudio();
    }

    void ToggleSkipUnseen()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.skip_unseen = !MenuSession::profile.settings.skip_unseen;
        saves.MarkProfile();
    }

    void ToggleSkipChoices()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.skip_after_choices = !MenuSession::profile.settings.skip_after_choices;
        saves.MarkProfile();
    }

    void ToggleSkipTransitions()
    {
        if (!CanNavigate())
        {
            return;
        }
        MenuSession::profile.settings.skip_transitions = !MenuSession::profile.settings.skip_transitions;
        saves.MarkProfile();
    }

    void Windowed()
    {
        if (!CanNavigate())
        {
            return;
        }
        SetFullscreenMode(false);
    }

    void Fullscreen()
    {
        if (!CanNavigate())
        {
            return;
        }
        SetFullscreenMode(true);
    }

    void SetFullscreenMode(bool fullscreen)
    {
        MenuSession::profile.settings.fullscreen = fullscreen;
        saves.MarkProfile();
        ApplicationManager::Instance().GetApplication().GetEngine().SetFullscreen(fullscreen);
    }

    // ---- main menu characters -----------------------------------------------------------------

    /// prlx_fg holds all three silhouettes; each one is cut out by its own RectMask2D column inside the Fg layer,
    /// so the parallax offset of the layer still moves them together.
    GameObject@ MenuSilhouette(GameObject@ layer, const String &in name, float left, float right)
    {
        GameObject@ column = layer.GetOrCreateChild(name + "Silhouette");
        @column.transform = TransformRect();
        TransformRect@ rect = cast<TransformRect@>(column.GetTransform());
        // The vertical margin keeps the part of the image enlarged by the 1.1 scale.
        float bottom = -0.1f;
        float top = 1.1f;
        RectAnchors anchors;
        anchors.min = runtime.view.Vec(left, bottom);
        anchors.max = runtime.view.Vec(right, top);
        rect.SetAnchors(anchors);
        rect.SetPivot(runtime.view.Vec(0.5f, 0.5f));
        rect.SetSize(runtime.view.Vec(0, 0));
        rect.SetAnchoredPosition(runtime.view.Vec(0, 0));
        rect.localPriority = 1;
        column.GetOrCreateComponent("RectMask2D");
        // Stretch the image back over the whole layer: anchors are relative to the column.
        RectAnchors full;
        full.min = runtime.view.Vec(-left / (right - left), -bottom / (top - bottom));
        full.max = runtime.view.Vec((1 - left) / (right - left), (1 - bottom) / (top - bottom));
        MenuImage(column, "Image", full, "DeathLovers/UI/parallax/prlx_fg.png", 0);
        return column;
    }

    GameObject@ MenuImage(GameObject@ parent, const String &in name, const RectAnchors &in anchors, const String &in texture, int priority)
    {
        GameObject@ image = parent.GetOrCreateChild(name);
        @image.transform = TransformRect();
        TransformRect@ rect = cast<TransformRect@>(image.GetTransform());
        rect.SetAnchors(anchors);
        rect.SetPivot(runtime.view.Vec(0.5f, 0.5f));
        rect.SetSize(runtime.view.Vec(0, 0));
        rect.SetAnchoredPosition(runtime.view.Vec(0, 0));
        rect.localPriority = priority;
        FVector3 scale;
        scale.x = 1.1f;
        scale.y = 1.1f;
        scale.z = 1;
        rect.SetScale(scale);
        Sprite@ sprite = cast<Sprite@>(image.GetOrCreateComponent("Sprite"));
        sprite.SetMaterial("Engine/Materials/UI/ui.mat");
        sprite.spriteMode = SpriteMode::Simple;
        if (texture != "")
        {
            sprite.SetTexturePath(texture);
        }
        return image;
    }

    /// The unlocked character sprite covers its silhouette. Placement is given in prlx_fg pixels (2594x1080):
    /// left/top of the sprite and its scale, fitted so the head matches the silhouette and the bottom reaches the frame edge.
    /// The texture is assigned only when the character is unlocked: these sprites are 4000-4800 px wide.
    GameObject@ MenuCharacterSprite(GameObject@ layer, const String &in name, float left, float top, float width, float height,
        float scale, int priority)
    {
        RectAnchors anchors;
        anchors.min = runtime.view.Vec(left / 2594.0f, 1.0f - (top + height * scale) / 1080.0f);
        anchors.max = runtime.view.Vec((left + width * scale) / 2594.0f, 1.0f - top / 1080.0f);
        GameObject@ image = MenuImage(layer, name + "Character", anchors, "", priority);
        image.SetEnabled(false);
        return image;
    }

    void BuildMenuCharacters()
    {
        GameObject@ layer = Child(Child(novel, "Background"), "Fg");
        // The full original layer is replaced by three silhouette columns, each replaced by its character after an ending.
        Child(layer, "Image").SetEnabled(false);
        @plagueSilhouette = MenuSilhouette(layer, "Plague", -0.1f, 0.36f);
        @hungerSilhouette = MenuSilhouette(layer, "Hunger", 0.36f, 0.59f);
        @warSilhouette = MenuSilhouette(layer, "War", 0.59f, 1.1f);
        // Hunger stands behind the side characters where the sprites overlap.
        @hungerCharacter = MenuCharacterSprite(layer, "Hunger", 676, 61, 4000, 4000, 0.255f, 2);
        @plagueCharacter = MenuCharacterSprite(layer, "Plague", -10, 129, 4800, 4000, 0.238f, 3);
        @warCharacter = MenuCharacterSprite(layer, "War", 1321, 125, 4800, 4000, 0.239f, 4);
    }

    bool EndingReached(const String &in id)
    {
        for (uint i = 0; i < MenuSession::profile.endings.size(); ++i)
        {
            if (MenuSession::profile.endings[i] == id)
            {
                return true;
            }
        }
        return false;
    }

    void ShowMenuCharacter(GameObject@ silhouette, GameObject@ character, const String &in texture, bool unlocked)
    {
        silhouette.SetEnabled(!unlocked);
        character.SetEnabled(unlocked);
        Sprite@ sprite = cast<Sprite@>(character.GetComponent("Sprite"));
        if (unlocked && !menuTextures.contains(texture))
        {
            sprite.SetTexturePath(texture);
            menuTextures.set(texture, true);
        }
    }

    void RefreshMenuCharacters()
    {
        if (plagueSilhouette is null)
        {
            return;
        }
        bool harem = EndingReached("harem_ending");
        ShowMenuCharacter(plagueSilhouette, plagueCharacter, "DeathLovers/Images/plague/conq_normal.png",
            harem || EndingReached("plague_ending") || EndingReached("plaguewar_ending") || EndingReached("plaguehunger_ending"));
        ShowMenuCharacter(warSilhouette, warCharacter, "DeathLovers/Images/war/war_headsup.png",
            harem || EndingReached("war_ending") || EndingReached("plaguewar_ending") || EndingReached("warhunger_ending"));
        ShowMenuCharacter(hungerSilhouette, hungerCharacter, "DeathLovers/Images/hunger/normal.png",
            harem || EndingReached("hunger_ending") || EndingReached("plaguehunger_ending") || EndingReached("warhunger_ending"));
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
        OpenSave();
    }

    void ReadingOptions()
    {
        if (!OpenGameMenuFromQuick())
        {
            return;
        }
        OpenPreferences();
        if (submenu !is preferences && quickSubmenu)
        {
            SetGameMenu(false, false);
        }
    }

    /// Quick menu -> submenu: opens the game menu without showing its navigation, so it does not flash.
    bool OpenGameMenuFromQuick()
    {
        if (!inGame || gameMenuOpen)
        {
            return inGame;
        }
        if (!CanNavigate() || modal !is null || submenu !is null)
        {
            return false;
        }
        SetGameMenu(true, false);
        quickSubmenu = true;
        // Only the submenu fades in over the paused story frame: no game menu navigation, no backdrop yet.
        ApplyGameMenuFade(0);
        main.SetEnabled(false);
        inputBarrier = 0;
        return true;
    }

    void OpenHistory()
    {
        if (!inGame || modal !is null || !CanNavigate())
        {
            return;
        }
        // Skip/auto are paused by the modal (NovelSession::Paused), not cancelled.
        String content;
        Vector<TextStyle> names;
        for (uint i = 0; i < runtime.state.core.history.size(); ++i)
        {
            NovelHistoryEntry@ entry = runtime.state.core.history[i];
            DialogueProgram line;
            line.Compile(entry.text, false);
            NovelSpeaker@ speaker = runtime.speakers.at(entry.speakerId);
            if (speaker.name != "")
            {
                TextStyle style;
                style.begin = content.graphemeCount();
                content = content + speaker.name + ":";
                style.end = content.graphemeCount();
                style.color.x = float(speaker.color.x);
                style.color.y = float(speaker.color.y);
                style.color.z = float(speaker.color.z);
                names.pushBack(style);
                content = content + "\n";
            }
            content = content + line.plain + "\n\n";
        }
        GameObject@ viewport = Child(readingHistory, "Viewport");
        GameObject@ body = Child(viewport, "Content");
        TextMesh@ text = cast<TextMesh@>(body.GetComponent("TextMesh"));
        text.horizontalAlignment = TextAlignmentHorizontal::Left;
        text.verticalAlignment = TextAlignmentVertical::Top;
        text.SetMaterial("DeathLovers/Materials/RuntimeText.mat");
        text.SetText(content);
        for (uint i = 0; i < names.size(); ++i)
        {
            text.AddStyle(names[i]);
        }
        readingHistory.SetEnabled(true);
        float height = text.GetTextBounds().h + 60;
        cast<TransformRect@>(body.GetTransform()).SetSize(runtime.view.Vec(1200, height > 850 ? height : 850));
        // Unity convention: 0 is the bottom, so the history opens on the latest line.
        cast<UIScrollRect@>(viewport.GetComponent("UIScrollRect")).SetNormalizedPosition(runtime.view.Vec(0, 0));
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
        // Latched on the held state, not GetKeyDown: after the window switch the next frames can run several updates
        // with the same input state, and a second "down" would switch the window straight back.
        bool altEnter = (Input::Instance().GetKey(KeyCode::LAlt) || Input::Instance().GetKey(KeyCode::RAlt)) &&
            Input::Instance().GetKey(KeyCode::Enter);
        if (altEnter && !altEnterLatched)
        {
            SetFullscreenMode(!MenuSession::profile.settings.fullscreen);
        }
        altEnterLatched = altEnter;
        UpdateGameMenuFade(dt);
        bool uiHidden = runtime !is null && runtime.uiHidden;
        quickMenu.SetEnabled(inGame && !gameMenuOpen && modal is null && !saves.busy && !uiHidden);
        Button(quickMenu, "Save").SetInteractable(!saves.busy && saves.CanSave());
        Button(quickMenu, "QuickSave").SetInteractable(saves.configured && !saves.busy && inGame);
        mainMenuButton.SetEnabled(inGame);
        if (runtime !is null && runtime.state !is null)
        {
            rollbackButton.SetInteractable(runtime.CanRollback());
        }
        MenuSession::skipActive = inGame && !gameMenuOpen && modal is null && runtime !is null &&
            (runtime.skipEnabled || Input::Instance().GetKey(KeyCode::LCtrl) || Input::Instance().GetKey(KeyCode::RCtrl));
        MenuSession::autoActive = inGame && runtime !is null && runtime.autoEnabled;
        if (runtime !is null)
        {
            runtime.view.Skipping(MenuSession::skipActive && !uiHidden && !runtime.Paused() && !runtime.restoreInputPending &&
                runtime.PhaseName() != "WaitingChoice", dt);
        }
        if (modal is readingHistory && CanNavigate() &&
            (Input::Instance().GetKeyDown(KeyCode::Escape) || Input::Instance().GetMouseDown(MouseCode::MouseRight)))
        {
            CloseHistory();
            return;
        }
        if (fadingScreen !is null)
        {
            fadeTime += dt;
            float progress = fadeTime < 0.5f ? fadeTime / 0.5f : 1.0f;
            fadingScreen.SetSubtreeOpacity(fadeClosing ? 1.0f - progress : progress);
            ScreenOpacity(fadeClosing ? main : fadingFrom, quickSubmenu && (fadeClosing || fadingFrom is main) ? 0.0f :
                fadeClosing ? progress : 1.0f - progress);
            TabBackgroundOpacity(GameMenuBackdrop() ? 1.0f : fadeClosing ? 1.0f - progress : fadingFrom is main ? progress : 1.0f);
            if (progress >= 1.0f)
            {
                fadingFrom.SetEnabled(false);
                @fadingFrom = null;
                @fadingScreen = null;
                transitionBlocker.SetEnabled(false);
                if (fadeClosing && quickSubmenu)
                {
                    SetGameMenu(false, false);
                }
                else if (fadeClosing)
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
        if (modal is null && CanNavigate() &&
            (Input::Instance().GetKeyDown(KeyCode::Escape) || Input::Instance().GetMouseDown(MouseCode::MouseRight)))
        {
            if (inGame && submenu is null && gameMenuOpen)
            {
                ToggleGameMenu();
            }
            else if (inGame && submenu is null)
            {
                // Escape / right mouse button in the story open the preferences over the paused frame.
                ReadingOptions();
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
        saves.Update(dt);
    }

    void ToggleGameMenu()
    {
        if (!inGame || !CanNavigate() || modal !is null || submenu !is null)
        {
            return;
        }
        SetGameMenu(!gameMenuOpen);
    }

    /// The game menu is drawn over the paused story frame (the main menu parallax is not shown in game).
    /// animate=false switches instantly: used when the quick-menu submenu has already faded the backdrop itself.
    void SetGameMenu(bool open, bool animate = true)
    {
        quickSubmenu = false;
        if (open && runtime.uiHidden)
        {
            runtime.SetUiHidden(false);
        }
        Text(Child(main, "Navigation"), "Start", "Продолжить");
        Child(novel, "Background").SetEnabled(false);
        runtime.view.root.SetEnabled(true);
        MenuSession::activeScreen = open ? "GameMenu" : "Story";
        inputBarrier = 0.1f;
        runtime.inputBarrier = 0.1f;
        if (open)
        {
            // Paused from the first frame of the fade.
            gameMenuOpen = true;
            main.SetEnabled(true);
            Button(Child(main, "Navigation"), "Preferences").Focus();
        }
        if (animate)
        {
            gameMenuFading = true;
            gameMenuFadeOpening = open;
            gameMenuFade = 0;
            ApplyGameMenuFade(0);
            return;
        }
        gameMenuFading = false;
        ApplyGameMenuFade(open ? 1.0f : 0.0f);
        if (!open)
        {
            FinishGameMenuClose();
        }
    }

    void ApplyGameMenuFade(float opacity)
    {
        ScreenOpacity(main, opacity);
        TabBackgroundOpacity(opacity);
    }

    void FinishGameMenuClose()
    {
        main.SetEnabled(false);
        gameMenuOpen = false;
        runtime.inputBarrier = 0.1f;
        runtime.view.FocusNarrative(runtime.PhaseName() == "WaitingChoice");
    }

    void UpdateGameMenuFade(float dt)
    {
        if (!gameMenuFading)
        {
            return;
        }
        gameMenuFade += dt / 0.25f;
        float progress = gameMenuFade < 1.0f ? gameMenuFade : 1.0f;
        ApplyGameMenuFade(gameMenuFadeOpening ? progress : 1.0f - progress);
        if (progress < 1.0f)
        {
            return;
        }
        gameMenuFading = false;
        if (!gameMenuFadeOpening)
        {
            FinishGameMenuClose();
        }
    }

    void AdvanceStory()
    {
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
        GameObject@ probe = runtime.view.Rect(novel, "RuntimeProbe", 360, 0, 1170, 205);
        for (uint i = 0; i < 7; ++i)
        {
            String name = i == 0 ? "Fixture" : i == 1 ? "RestoreTwice" : i == 2 ? "Trace" :
                i == 3 ? "StorageProbe" : i == 4 ? "PrepareRestart" : i == 5 ? "VerifyRestart" : "SavesFixture";
            GameObject@ button = runtime.view.Rect(probe, name, float(i % 3) * 350, float(i / 3) * 45, 340, 40);
            runtime.view.Label(button, name);
            UIButton@ control = cast<UIButton@>(button.GetOrCreateComponent("UIButton"));
            control.SetClickReceiver(gameObject.GetComponent("Behaviour"), i == 0 ? "StartRuntimeFixture" :
                i == 1 ? "VerifyRuntimeSnapshot" : i == 2 ? "ShowRuntimeTrace" :
                i == 3 ? "RunStorageProbe" : i == 4 ? "PrepareStorageRestart" : i == 5 ? "VerifyStorageRestart" : "StartSavesFixture");
        }
        @runtimeProbeText = runtime.view.Label(runtime.view.Rect(probe, "Result", 0, 140, 1170, 60), "AWAITING_USER_RUN");
    }

    void StartSavesFixture()
    {
        if (developmentRuntime && CanNavigate() && modal is null)
        {
            runtimeProbeText.SetText(runtime.StartSavesFixture() ? "Saves fixture started" : "Saves fixture load failed");
        }
    }

    void RunStorageProbe()
    {
        if (developmentRuntime && CanNavigate() && modal is null)
        {
            SaveStorageProbe probe;
            runtimeProbeReport = probe.Run();
            runtimeProbeText.SetText(runtimeProbeReport);
            saves.Refresh();
        }
    }

    void PrepareStorageRestart()
    {
        if (developmentRuntime && CanNavigate() && modal is null)
        {
            SaveStorageProbe probe;
            runtimeProbeReport = probe.PrepareRestart();
            runtimeProbeText.SetText(runtimeProbeReport);
        }
    }

    void VerifyStorageRestart()
    {
        if (developmentRuntime && CanNavigate() && modal is null)
        {
            SaveStorageProbe probe;
            runtimeProbeReport = probe.VerifyRestart();
            runtimeProbeText.SetText(runtimeProbeReport);
        }
    }

    void StartRuntimeFixture()
    {
        if (developmentRuntime && CanNavigate() && modal is null)
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
        if (saves.menu !is null)
        {
            saves.FlushProfile(false);
            if (saves.capture !is null)
            {
                saves.capture.Cancel();
            }
        }
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
