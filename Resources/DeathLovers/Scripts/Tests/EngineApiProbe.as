//
// Created by Codex on 15.11.2026.
//

#include "../Runtime/NovelState.as"
#include "../Runtime/RuntimeValues.as"

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
    bool monitorAudio = false;
    float audioStatusTimer = 0;

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
        Check(document.View().Get("schemaVersion").GetInt() == 1);
        JsonValueView@ fixture = document.View().Get("state");
        Check(fixture.Get("score").GetInt() == 7);
        Check(fixture.Get("enabled").GetBool());
        double fraction = fixture.Get("fraction").GetNumber();
        Check(fraction > 0.249999 && fraction < 0.250001);
        Check(fixture.Get("empty").GetKind() == JsonValueKind::Null);
        Check(fixture.Get("empty").IsValid());
        JsonValueView@ items = fixture.Get("items");
        Check(items.GetCount() == 3);
        Check(items.At(0).GetInt() == 1);
        Check(items.At(2).Get("nested").At(0).GetBool());
        Check(!items.At(2).Get("nested").At(1).GetBool());
        JsonValueView missing;
        Check(!missing.IsValid());
        JsonValue@ independent = fixture.Clone();
        JsonValue replacement;
        replacement.SetInt(99);
        Check(independent.Set("score", replacement));
        Check(independent.View().Get("score").GetInt() == 99);
        Check(fixture.Get("score").GetInt() == 7);

        NovelState source;
        source.core.schemaVersion = 2;
        String title = "Кириллица";
        source.core.position = title;
        source.core.frames.resize(1);
        source.core.frames[0].label = "return";
        source.core.frames[0].picks.pushBack(2);
        source.core.vars.roots = 7;
        source.core.vars.canteen_visited = true;
        source.core.frames[0].afterCall.pushBack(source.core.vars);
        NovelHistoryEntry entry;
        entry.lineId = "probe";
        entry.text = "Original";
        source.core.history.pushBack(entry);
        NovelCharacter character;
        character.resourceId = "original";
        source.core.presentation.characters.set("ch_p", character);
        source.rollbackCheckpoints.pushBack(source.core);

        NovelState copy;
        copy = source;
        copy.core.vars.roots = 99;
        copy.core.frames[0].afterCall[0].roots = 99;
        copy.core.history[0].text = "Changed";
        copy.core.presentation.characters.at("ch_p").resourceId = "changed";
        copy.core.frames[0].label = "changed";
        Check(source.core.vars.roots == 7 && source.core.frames[0].afterCall[0].roots == 7);
        Check(source.core.history[0].text == "Original");
        Check(source.core.presentation.characters.at("ch_p").resourceId == "original");
        Check(source.core.frames[0].label == "return");
        Check(copy.rollbackCheckpoints[0].history[0].text == "Original");

        String encoded = SerializeScriptValue(source);
        NovelState restored;
        Check(DeserializeScriptValue(encoded, restored));
        Check(restored.core.vars.roots == 7 && restored.core.vars.canteen_visited);
        Check(restored.core.position == title);
        Check(restored.core.frames.size() == 1 && restored.core.frames[0].picks.size() == 1 && restored.core.frames[0].picks[0] == 2);
        Check(restored.core.history.size() == 1 && restored.core.history[0].text == "Original");
        Check(restored.core.presentation.characters.at("ch_p").resourceId == "original");
        Check(restored.rollbackCheckpoints.size() == 1 && restored.rollbackCheckpoints[0].frames[0].label == "return");
        restored.core.history[0].text = "Changed";
        Check(DeserializeScriptValue(encoded, restored));
        Check(restored.core.history[0].text == "Original");
        Check(restored.rollbackCheckpoints[0].history[0].text == "Original");
        Check(!DeserializeScriptValue("{broken", restored));
        NovelState empty;
        Check(DeserializeScriptValue(SerializeScriptValue(empty), restored));
        Check(restored.core.frames.size() == 0 && restored.core.vars.roots == 0 && restored.core.history.size() == 0 &&
            restored.rollbackCheckpoints.size() == 0 && restored.core.presentation.characters.size() == 0);
        Check(RuntimeValues::Number("-1.25e2") < -124.999f && RuntimeValues::Number("-1.25e2") > -125.001f);
        Check(RuntimeValues::Number("invalid") > -0.000001f && RuntimeValues::Number("invalid") < 0.000001f);
        status.SetText(failures == 0 ? "Typed snapshots and external JSON: passed in this run" :
            "Typed snapshot/JSON FAIL: inspect failures and engine diagnostics");
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
        if (monitorAudio)
        {
            audioStatusTimer += dt;
            if (audioStatusTimer >= 1.0f)
            {
                audioStatusTimer = 0;
                //String state = audio.IsPaused() ? "paused" : audio.IsPlaying() ? "playing" : "stopped";
                //status.SetText("AUDIO: " + state + "; position=" + audio.GetPlaybackPosition()
                //    + "; source=" + audio.GetVolume() + "; master=" + AudioMixer::Instance().GetMasterVolume()
                //    + "; group=" + AudioMixer::Instance().GetGain("Interface")
                //    + (AudioMixer::Instance().IsMuted() ? "; MUTED" : "; unmuted"));
            }
        }
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
        TextMesh@ label = cast<TextMesh@>(gameObject.GetOrCreateChild("Mute").GetOrCreateChild("MuteLabel").GetComponent("TextMesh"));
        label.SetText(toggle.GetValue() ? "[X] Master mute: ON" : "[ ] Master mute: OFF");
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

    void PrepareAudioTest()
    {
        audio.Stop();
        toggle.SetValue(false);
        slider.SetValue(0.75f);
        AudioMixer::Instance().SetMuted(false);
        AudioMixer::Instance().SetMasterVolume(1.0f);
        AudioMixer::Instance().SetGroupVolume("Effects", 1.0f);
        AudioMixer::Instance().SetGroupVolume("Interface", 1.0f);
        AudioMixer::Instance().SetGroupMuted("Effects", false);
        AudioMixer::Instance().SetGroupMuted("Interface", false);
        audio.SetVolume(0.75f);
        monitorAudio = false;
        audioStatusTimer = 0;
    }

    void PlayWav()
    {
        PrepareAudioTest();
        audio.SetSpatialize(SpatializeMode::Off);
        audio.SetPath("DeathLovers/Audio/Tests/Door.wav");
        audio.SetLoop(true);
        monitorAudio = audio.Play();
        status.SetText(monitorAudio ? "WAV: mix reset; starting playback" : "WAV: Play failed; see log");
    }

    void PlayOgg()
    {
        PrepareAudioTest();
        audio.SetSpatialize(SpatializeMode::Off);
        audio.SetPath("DeathLovers/Audio/Tests/main_menu.ogg");
        audio.SetLoop(true);
        monitorAudio = audio.Play();
        status.SetText(monitorAudio ? "OGG: mix reset; starting playback" : "OGG: Play failed; see log");
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
        status.SetText(audio.Seek(1.0f) ? "SEEK: moved to one second" : "SEEK: failed; start playback first");
    }

    void StopAudio()
    {
        monitorAudio = false;
        audio.Stop();
        status.SetText("AUDIO: stopped");
    }

    void MixAudio()
    {
        audio.SetVolume(0.75f);
        AudioMixer::Instance().SetMasterVolume(0.5f);
        AudioMixer::Instance().SetGroupVolume("Effects", 0.8f);
        AudioMixer::Instance().SetGroupVolume("Interface", 0.5f);
        if (audio.GetVolume() < 0.749999f || audio.GetVolume() > 0.750001f)
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
