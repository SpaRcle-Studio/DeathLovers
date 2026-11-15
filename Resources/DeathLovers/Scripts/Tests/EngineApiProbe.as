//
// Created by Codex on 15.11.2026.
//

class EngineApiProbe : ScriptBehaviour
{
    TextMesh@ display;
    TextMesh@ status;
    AudioSource@ audio;
    UISlider@ slider;
    UIToggle@ toggle;
    GameObject@ modal;
    uint clicks = 0;
    uint valueChanges = 0;
    uint toggleChanges = 0;
    uint rawAdvanceCount = 0;
    uint jsonChecks = 0;
    uint failures = 0;
    bool narrow = false;
    bool printing = true;
    float elapsed = 0;

    void Start()
    {
        @display = cast<TextMesh@>(gameObject.GetOrCreateChild("Text").GetComponent("TextMesh"));
        @status = cast<TextMesh@>(gameObject.GetOrCreateChild("Status").GetComponent("TextMesh"));
        @audio = cast<AudioSource@>(gameObject.GetOrCreateChild("Audio").GetComponent("AudioSource"));
        @slider = cast<UISlider@>(gameObject.GetOrCreateChild("Volume").GetComponent("UISlider"));
        @toggle = cast<UIToggle@>(gameObject.GetOrCreateChild("Mute").GetComponent("UIToggle"));
        @modal = gameObject.GetOrCreateChild("Modal");
        modal.SetEnabled(false);
        if (!AudioMixer::Instance().HasGroup("Effects"))
        {
            AudioMixerGroup effects;
            effects.name = "Effects";
            effects.volume = 0.8f;
            AudioMixer::Instance().AddGroup(effects);
        }
        if (!AudioMixer::Instance().HasGroup("Interface"))
        {
            AudioMixerGroup interfaceAudio;
            interfaceAudio.name = "Interface";
            interfaceAudio.parent = "Effects";
            interfaceAudio.volume = 0.5f;
            AudioMixer::Instance().AddGroup(interfaceAudio);
        }
        audio.SetGroup("Interface");
        TestJson();
        SetFormattedText();
    }

    void Check(bool passed)
    {
        ++jsonChecks;
        if (!passed)
        {
            ++failures;
        }
    }

    void TestJson()
    {
        JsonValue document;
        Check(document.LoadResource("DeathLovers/Tests/engine-api.json"));
        Check(document.Get("schemaVersion").GetInt() == 1);
        JsonValue@ state = document.Get("state");
        Check(state.Get("score").GetInt() == 7);
        Check(state.Get("enabled").GetBool());
        Check(state.Get("fraction").GetNumber() == 0.25);
        Check(state.Get("empty").GetKind() == JsonValueKind::Null);
        JsonValue@ copy = state.Clone();
        JsonValue replacement;
        replacement.SetInt(99);
        JsonValue@ items = copy.Get("items");
        Check(items.SetAt(0, replacement));
        Check(copy.Set("items", items));
        Check(state.Get("items").At(0).GetInt() == 1);
        Check(copy.Get("items").At(0).GetInt() == 99);
        JsonValue restored;
        Check(restored.Parse(copy.ToJson()));
        Check(restored.Get("items").At(2).Get("nested").At(0).GetBool());
        Check(restored.Get("empty").GetKind() == JsonValueKind::Null);
        if (failures == 0)
        {
            status.SetText("JSON: 13 checks prepared and passed in this run");
        }
        else
        {
            status.SetText("JSON FAIL: inspect failures and parser diagnostics");
        }
    }

    void SetFormattedText()
    {
        display.SetText("Кириллица: ё, й; ё = один символ.\nПеренос по ширине; жирный, курсив, подчёркивание и зачёркивание. Диапазоны перекрываются.");
        TextStyle first;
        first.begin = 0;
        first.end = 30;
        first.bold = true;
        first.relativeSize = 1.2f;
        display.AddStyle(first);
        TextStyle second;
        second.begin = 15;
        second.end = 55;
        second.italic = true;
        second.underline = true;
        second.color.x = 0.5f;
        display.AddStyle(second);
        TextStyle third;
        third.begin = 40;
        third.end = 75;
        third.strike = true;
        third.color.w = 0.6f;
        display.AddStyle(third);
        elapsed = 0;
        printing = true;
        display.SetVisibleGraphemeCount(0);
    }

    void Update(float dt)
    {
        elapsed += dt;
        if (printing)
        {
            uint count = uint(elapsed * 20.0f);
            display.SetVisibleGraphemeCount(count);
            if (count >= display.GetGraphemeCount())
            {
                printing = false;
            }
        }
        display.SetCharacterEffect(elapsed, 1.0f, 0.4f, 8.0f);
        if (!gameObject.GetScene().IsUIInputConsumed() && Input::Instance().GetKeyDown(KeyCode::Space))
        {
            ++rawAdvanceCount;
        }
    }

    void OnClick()
    {
        ++clicks;
        status.SetText("CLICK: check clicks in Inspector; one release = one click");
    }

    void OpenModal()
    {
        modal.SetEnabled(true);
    }

    void CloseModal()
    {
        modal.SetEnabled(false);
    }

    void OnSlider()
    {
        ++valueChanges;
        audio.SetVolume(slider.GetValue());
        status.SetText("SLIDER: pointer capture and arrows; source volume changed");
    }

    void OnToggle()
    {
        ++toggleChanges;
        AudioMixer::Instance().SetMuted(toggle.GetValue());
        status.SetText("TOGGLE: master mute changed");
    }

    void ResizeText()
    {
        narrow = !narrow;
        TransformRect@ rect = cast<TransformRect@>(gameObject.GetOrCreateChild("Text").GetTransform());
        FVector2 size;
        size.x = narrow ? 420.0f : 850.0f;
        size.y = rect.GetSizeDelta().y;
        rect.SetSize(size);
        SetFormattedText();
    }

    void PlainText()
    {
        display.SetText("Новая реплика: прежние стили не должны сохраняться.\n\nПосле пустой строки.");
        printing = false;
    }

    void PlayWav()
    {
        audio.Stop();
        audio.SetSpatialize(SpatializeMode::Off);
        audio.SetPath("DeathLovers/Audio/Tests/Door.wav");
        audio.SetLoop(true);
        audio.Play();
    }

    void PlayOgg()
    {
        audio.Stop();
        audio.SetSpatialize(SpatializeMode::Off);
        audio.SetPath("DeathLovers/Audio/Tests/main_menu.ogg");
        audio.SetLoop(true);
        audio.Play();
    }

    void PauseAudio()
    {
        audio.Pause();
    }

    void ResumeAudio()
    {
        audio.Resume();
    }

    void SeekAudio()
    {
        audio.Seek(1.0f);
        status.SetText("SEEK: playback position must be near one second");
    }

    void StopAudio()
    {
        audio.Stop();
    }

    void MixAudio()
    {
        audio.SetVolume(0.75f);
        AudioMixer::Instance().SetMasterVolume(0.5f);
        AudioMixer::Instance().SetGroupVolume("Effects", 0.8f);
        AudioMixer::Instance().SetGroupVolume("Interface", 0.5f);
        if (audio.GetVolume() != 0.75f)
        {
            ++failures;
        }
        status.SetText("MIX: source=0.75; master=0.5; Effects=0.8; Interface=0.5; effective=0.15");
    }

    void DestroyReceiver()
    {
        gameObject.GetOrCreateChild("Receiver").Destroy();
        status.SetText("Target destroyed: Test Target must report unavailable target");
    }

    int WrongSignature()
    {
        return 1;
    }
}

class EngineApiReceiver : ScriptBehaviour
{
    uint received = 0;

    void Receive()
    {
        ++received;
    }
}
