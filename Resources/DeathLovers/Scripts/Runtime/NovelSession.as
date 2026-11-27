//
// Created by Codex on 17.11.2026.
//

#include "NovelView.as"
#include "NovelAudio.as"
#include "NovelPresentation.as"
#include "NovelSnapshotValidation.as"
#include "NovelSaveFormat.as"
#include "StoryApi.as"
#include "../Debug/StoryDebugPanel.as"

class NovelSession : IMenuSessionStarter, IStoryDebugRuntime, IStoryHost
{
    MenuNavigation@ menu;
    NovelView view;
    NovelAudio audio;
    NovelPresentation presentation;
    DialogueProgram program;
    StoryRunner runner;
    JsonValue definitions;
    Map<String, NovelSpeaker> speakers;
    NovelState@ state;
    Vector<NovelTraceEvent> trace;
    bool traceEnabled = false;
    bool configured = false;
    String startupError = "Не удалось создать интерфейс новеллы. Подробности в журнале движка.";
    float inputBarrier = 0;
    bool wasPaused = false;
    bool skipEnabled = false;
    bool autoEnabled = false;
    float autoDelay = 0;
    float skipDelay = 0;
    uint rollbackCount = 0;
    uint rollbackLastInteraction = 0;
    NovelAudioState rollbackAudio;
    String storyEntry = "Story::start";
    bool restoreInputPending = false;
    Map<String, bool> readIndex;
    uint readIndexCount = 0;

    void Configure(MenuNavigation@ navigation, Component@ receiver)
    {
        @menu = navigation;
        JsonValue manifest;
        JsonValue speakerManifest;
        configured = false;
        startupError = "Не удалось загрузить assets.json, characters.json или speakers.json. Подробности в журнале движка.";
        if (!manifest.LoadResource("DeathLovers/Story/assets.json") ||
            !definitions.LoadResource("DeathLovers/Story/characters.json") ||
            !speakerManifest.LoadResource("DeathLovers/Story/speakers.json"))
        {
            return;
        }
        startupError = "Не удалось создать интерфейс или аудио новеллы. Подробности в журнале движка.";
        speakers.clear();
        for (uint i = 0; i < speakerManifest.View().GetCount(); ++i)
        {
            String id = speakerManifest.View().GetKey(i);
            JsonValueView@ source = speakerManifest.View().Get(id);
            NovelSpeaker speaker;
            speaker.name = source.Get("name").GetString();
            speaker.voice = source.Get("voice").GetString();
            speaker.multiplier = float(source.Get("multiplier").GetNumber());
            speaker.color.x = float(source.Get("color").At(0).GetNumber());
            speaker.color.y = float(source.Get("color").At(1).GetNumber());
            speaker.color.z = float(source.Get("color").At(2).GetNumber());
            speakers.set(id, speaker);
        }
        @presentation.view = view;
        @presentation.audio = audio;
        view.Build(menu.novel, receiver);
        audio.Build(menu.gameObject.GetOrCreateChild("RuntimeAudio"), manifest.View());
        for (uint i = 0; i < speakerManifest.View().GetCount(); ++i)
        {
            NovelSpeaker@ speaker = speakers.at(speakerManifest.View().GetKey(i));
            speaker.voicePath = audio.Path(speaker.voice);
        }
        configured = true;
        startupError = "";
    }

    bool StartSession()
    {
        traceEnabled = false;
        if (!configured)
        {
            return false;
        }
        startupError = "Не удалось загрузить characters.json. Подробности в журнале движка.";
        if (!definitions.LoadResource("DeathLovers/Story/characters.json"))
        {
            return false;
        }
        startupError = "Сценарий не найден или не запустился. Подробности в журнале движка.";
        if (!NewGame("Story::start"))
        {
            return false;
        }
        startupError = "";
        return true;
    }

    bool StartFixture()
    {
        if (!configured || !definitions.LoadResource("DeathLovers/Story/characters.json"))
        {
            return false;
        }
        JsonValue@ characters = definitions.View().Get("characters").Clone();
        JsonValue@ character = characters.View().Get("ch_p").Clone();
        JsonValue animation;
        animation.SetString("single_bounce_animation");
        character.Set("animation", animation);
        characters.Set("ch_p", character);
        definitions.Set("characters", characters);
        traceEnabled = true;
        return NewGame("Story::fixture_runtime_start");
    }

    bool StartSavesFixture()
    {
        if (!configured || !definitions.LoadResource("DeathLovers/Story/characters.json"))
        {
            return false;
        }
        traceEnabled = true;
        return NewGame("Story::fixture_saves_start");
    }

    bool NewGame(const String &in entry)
    {
        if (FindCoroutineEntry(entry) is null)
        {
            Debug::Instance().Error("NovelSession::NewGame() : unknown story entry " + entry);
            return false;
        }
        storyEntry = entry;
        restoreInputPending = false;
        menu.saves.autoPending = false;
        menu.saves.lastAutoTime = 0;
        menu.saves.lastAutoState = "";
        menu.saves.queuedGroup = "";
        menu.saves.openAfterYield = false;
        skipEnabled = false;
        autoEnabled = false;
        autoDelay = 0;
        rollbackCount = 0;
        rollbackLastInteraction = 0;
        runner.Abort();
        audio.Stop();
        @state = NovelState();
        state.rollbackCheckpoints.reserve(100);
        state.core.history.reserve(250);
        state.core.frames.reserve(16);
        state.core.presentation.choices.reserve(8);
        state.core.schemaVersion = 1;
        state.core.contentVersion = Story::Version;
        Phase("Ready");
        state.rollbackCheckpoints.clear();
        state.core.activeEndingId = "";
        state.core.diagnostic = "";
        state.core.playTimeSeconds = 0;
        trace.clear();
        RefreshReadIndex(true);
        runner.Bind(this, state.core);
        runner.Start(storyEntry);
        inputBarrier = 0.1f;
        menu.gameMenuOpen = false;
        menu.inGame = true;
        MenuSession::activeScreen = "Story";
        menu.main.SetEnabled(false);
        menu.music.Stop();
        menu.novel.GetOrCreateChild("Background").SetEnabled(false);
        view.root.SetEnabled(true);
        RestorePresentation();
        view.FocusNarrative(false);
        return true;
    }

    String PhaseName()
    {
        return state is null ? "Finished" : state.core.phase;
    }

    void Phase(const String &in phase)
    {
        state.core.phase = phase;
    }

    bool Paused()
    {
        return !menu.inGame || menu.gameMenuOpen || menu.modal !is null || menu.saves.busy || !Input::Instance().IsAppFocused();
    }

    void Fail(const String &in message)
    {
        String location = state.core.Label();
        if (state.core.position != "")
        {
            location = location + " @" + state.core.position;
        }
        state.core.diagnostic = "NovelSession : " + location + " : " + message;
        Debug::Instance().Error(state.core.diagnostic);
        Phase("Finished");
        runner.Abort();
        view.adv.SetEnabled(true);
        view.dialogue.SetText(state.core.diagnostic);
        view.dialogue.SetVisibleGraphemeCount(1000000);
        audio.StopTyping();
    }

    float Duration(const String &in kind, float seconds)
    {
        if (seconds >= 0)
        {
            return seconds;
        }
        // Ren'Py common transitions: fade=.5 out + .0 hold + .5 in;
        // dissolve=.5; vpunch=.25. Explicit durations always take priority.
        return kind == "fade" ? 1.0f : kind == "dissolve" ? 0.5f : kind == "vpunch" ? 0.25f : 0;
    }

    // ---- IStoryHost ----------------------------------------------------------------------------

    void StorySay(const String &in lineId, const String &in speakerId, const String &in mode, const String &in text, bool autoWait)
    {
        if (!speakers.contains(speakerId))
        {
            Fail("Unknown speaker " + speakerId);
            return;
        }
        program.Compile(text, autoWait);
        if (program.diagnostic != "")
        {
            state.core.diagnostic = lineId + " : " + program.diagnostic;
        }
        NovelPresentationState@ p = state.core.presentation;
        p.mode = mode;
        p.speakerId = speakerId;
        p.text = text;
        p.autoWait = autoWait;
        p.visibleIndex = 0;
        p.tokenIndex = 0;
        p.remainingPause = 0;
        p.inputWait = false;
        p.fullyShown = false;
        p.dialogueVisible = true;
        NovelHistoryEntry entry;
        entry.lineId = lineId;
        entry.speakerId = speakerId;
        entry.text = autoWait ? program.AutoWaits(text) : text;
        if (state.core.history.size() >= 250)
        {
            state.core.history.erase(0);
        }
        state.core.history.pushBack(entry);
        if (mode == "NVL")
        {
            p.nvl.pushBack(entry);
        }

        Phase("WaitingText");
        view.Dialogue(p, program, speakers.at(speakerId));
        autoDelay = 0;
        RememberInteraction();
    }

    void StoryMenu(const String &in menuId, const Vector<NovelChoice> &in choices)
    {
        NovelPresentationState@ p = state.core.presentation;
        p.choices = choices;
        Phase("WaitingChoice");
        MarkRead(menuId);
        menu.saves.autoPending = true;
        menu.saves.FlushProfile();
        RememberInteraction();
        if (!MenuSession::profile.settings.skip_after_choices)
        {
            skipEnabled = false;
        }
        view.Choices(p.choices, true);
        inputBarrier = 0.1f;
    }

    void StoryScene(const String &in resourceId, const String &in kind, float seconds)
    {
        if (resourceId != "builtin:black" && audio.Path(resourceId) == "")
        {
            Fail("Unknown background " + resourceId);
            return;
        }
        if (kind != "none" && kind != "fade" && kind != "dissolve" && kind != "vpunch")
        {
            Fail("Unknown transition " + kind);
            return;
        }
        NovelPresentationState@ p = state.core.presentation;
        NovelTransition@ transition = p.transition;
        transition.kind = kind;
        transition.from = p.background;
        transition.target = resourceId;
        transition.elapsed = 0;
        transition.duration = Duration(kind, seconds);
        p.background = resourceId;

        presentation.PaintBackground(p);
        if (transition.duration > 0)
        {
            Phase("WaitingTransition");
        }
    }

    void StoryCharacter(const String &in id, const String &in name, const String &in kind, float seconds)
    {
        JsonValueView@ registry = definitions.View().Get("characters");
        if (!registry.Has(id) || !registry.Get(id).Get("stateResources").Has(name))
        {
            Fail("Unknown character/state " + id + " " + name);
            return;
        }
        NovelPresentationState@ p = state.core.presentation;
        JsonValueView@ definition = registry.Get(id);
        NovelCharacter character;
        character.position.x = float(definition.Get("position").At(0).GetNumber());
        character.position.y = float(definition.Get("position").At(1).GetNumber());
        character.scale.x = float(definition.Get("scale").At(0).GetNumber());
        character.scale.y = float(definition.Get("scale").At(1).GetNumber());
        character.flipX = definition.Get("flip").At(0).GetBool();
        character.flipY = definition.Get("flip").At(1).GetBool();
        character.animation = RuntimeValues::Text(definition, "animation");
        String previous = p.characters.contains(id) ? p.characters.at(id).resourceId : "hidden";
        character.state = name;
        character.resourceId = definition.Get("stateResources").Get(name).GetString();
        character.previousResource = previous;
        character.transitionDuration = Duration(kind, seconds);
        character.transitionElapsed = 0;
        character.bounceElapsed = 0;
        character.bounceActive = character.animation == "single_bounce_animation";
        p.characters.set(id, character);

        presentation.PaintCharacters(p);
    }

    void StoryAudio(const String &in bus, bool play, const String &in resourceId, bool loop, float fade)
    {
        if (!audio.Command(state.core.audio, bus, play, resourceId, loop, fade))
        {
            Fail(audio.diagnostic);
        }
    }

    void StoryNvlClear()
    {
        NovelPresentationState@ p = state.core.presentation;
        p.nvl.clear();
        p.dialogueVisible = false;

        view.nvl.SetEnabled(false);
    }

    void StoryPause(float seconds, bool waitForInput)
    {
        NovelPresentationState@ p = state.core.presentation;
        p.remainingPause = seconds > 0 ? seconds : 0;
        p.inputWait = waitForInput;

        Phase("WaitingTimer");
    }

    void StoryBarrier()
    {
        rollbackCount = 0;
        rollbackLastInteraction = 0;
        state.rollbackCheckpoints.clear();
    }

    void StoryRestartToMenu()
    {
        Phase("Finished");
        menu.ReturnToMainMenu();
    }

    bool StoryNeedsFrame()
    {
        presentation.Prepare(state.core.presentation);
        return presentation.waitingTextures;
    }

    // ---- execution -----------------------------------------------------------------------------

    void RunReady()
    {
        if (state is null)
        {
            return;
        }
        for (uint count = 0; count < 1000 && PhaseName() == "Ready"; ++count)
        {
            if (!runner.IsRunning())
            {
                // The root label returned: the story ended without restart_to_menu().
                Phase("Finished");
                return;
            }
            String before;
            if (traceEnabled)
            {
                before = SerializeScriptValue(state.core);
            }
            if (!runner.Resume())
            {
                Fail(runner.error);
                return;
            }
            if (traceEnabled)
            {
                NovelTraceEvent event;
                event.label = state.core.Label();
                event.position = state.core.position;
                event.before = before;
                event.after = SerializeScriptValue(state.core);
                trace.pushBack(event);
            }
            if (state is null)
            {
                return;
            }
            presentation.Prepare(state.core.presentation);
            if (presentation.waitingTextures)
            {
                return;
            }
        }
        if (PhaseName() == "Ready")
        {
            Fail("1000 story resumes in one frame: probable cycle");
        }
    }

    void FinishSay()
    {
        MarkRead(state.core.position);
        Phase("Ready");
    }

    void TextTick(float dt, bool fast)
    {
        NovelPresentationState@ p = state.core.presentation;
        if (p.fullyShown && program.noWait && !fast)
        {
            FinishSay();
            return;
        }
        if (p.inputWait || p.fullyShown)
        {
            return;
        }
        float remaining = float(p.remainingPause);
        if (fast)
        {
            remaining = 0;
        }
        else
        {
            remaining -= dt;
        }
        uint index = uint(p.tokenIndex);
        NovelAudioState@ channels = state.core.audio;
        for (; index < program.tokenCount && (fast || remaining <= 0); ++index)
        {
            DialogueToken@ token = program.tokens[index];
            String kind = token.kind;
            if (kind == "input")
            {
                p.inputWait = true;
                ++index;
                remaining = 0;
                break;
            }
            if (kind == "pause")
            {
                if (!fast)
                {
                    remaining += float(token.value);
                }
                continue;
            }
            p.visibleIndex = token.index;
            float cps = MenuSession::profile.settings.text_cps * float(token.cps);
            if (!fast && cps > 0)
            {
                remaining += 1.0f / cps;
                if (kind == "glyph")
                {
                    audio.Type(channels, speakers.at(p.speakerId), cps);
                }
            }
        }
        p.tokenIndex = index;
        p.remainingPause = remaining > 0 ? remaining : 0;
        bool finished = index >= program.tokenCount && remaining <= 0 && !p.inputWait;
        p.fullyShown = finished;

        view.Progress(p);
        if (finished)
        {
            if (program.noWait && !fast)
            {
                FinishSay();
            }
        }
    }

    void Advance()
    {
        if (state is null || Paused() || inputBarrier > 0 || presentation.waitingTextures)
        {
            return;
        }
        skipEnabled = false;
        // Manual advance keeps auto reading active, including after an explicit {w}.
        autoDelay = 0;
        inputBarrier = 0.1f;
        NovelPresentationState@ p = state.core.presentation;
        if (PhaseName() == "WaitingTimer" && p.inputWait)
        {
            p.inputWait = false;

            Phase("Ready");
        }
        else if (PhaseName() == "WaitingText")
        {
            if (p.inputWait)
            {
                p.inputWait = false;
            }
            else if (p.fullyShown)
            {
                FinishSay();
            }
            else
            {
                audio.StopTyping();
                TextTick(0, true);
            }
        }
    }

    void Choose(uint index)
    {
        if (state is null || Paused() || inputBarrier > 0 || presentation.waitingTextures || PhaseName() != "WaitingChoice")
        {
            return;
        }
        NovelPresentationState@ p = state.core.presentation;
        if (index >= p.choices.size())
        {
            return;
        }
        uint declared = p.choices[index].index;
        menu.saves.autoPending = true;
        menu.saves.FlushProfile();
        p.choices.clear();

        view.Choices(p.choices, false);
        inputBarrier = 0.1f;
        runner.Pick(declared);
        Phase("Ready");
    }

    void RememberInteraction()
    {
        state.core.interaction = state.core.interaction + 1;
        if (state.rollbackCheckpoints.size() >= 100)
        {
            state.rollbackCheckpoints.erase(0);
        }
        // Write directly into the destination: pushBack makes an additional deep copy in the binding.
        state.rollbackCheckpoints.resize(state.rollbackCheckpoints.size() + 1);
        NovelCore@ core = state.rollbackCheckpoints[state.rollbackCheckpoints.size() - 1];
        core = state.core;
        if (PhaseName() == "WaitingText")
        {
            core.presentation.visibleIndex = program.plain.graphemeCount();
            core.presentation.tokenIndex = program.tokenCount;
            core.presentation.fullyShown = true;
            core.presentation.inputWait = false;
            core.presentation.remainingPause = 0;
        }
        rollbackCount = state.rollbackCheckpoints.size();
        rollbackLastInteraction = state.core.interaction;
    }

    bool CanRollback()
    {
        if (state is null)
        {
            return false;
        }
        uint count = rollbackCount;
        if (count > 0 && rollbackLastInteraction == state.core.interaction)
        {
            --count;
        }
        return count > 0;
    }

    void Rollback()
    {
        if (Paused() || inputBarrier > 0 || !CanRollback())
        {
            return;
        }
        uint count = state.rollbackCheckpoints.size();
        if (state.rollbackCheckpoints[count - 1].interaction == state.core.interaction)
        {
            --count;
        }
        // These checkpoints are internal, or were validated when the save was loaded.
        // Restore just the selected core, without copying/validating the entire rollback history.
        NovelCore@ checkpoint = state.rollbackCheckpoints[count - 1];
        rollbackAudio = checkpoint.audio;
        rollbackAudio.Sfx.completed = true;
        rollbackAudio.Voice.completed = true;
        audio.Update(state.core.audio, 0);
        if (!audio.Restore(rollbackAudio))
        {
            audio.Restore(state.core.audio);
            state.core.diagnostic = "NovelSession::Rollback() : snapshot restore failed. " + audio.diagnostic;
            menu.ShowNotify("Не удалось восстановить точку отката.", menu.rollbackButton);
            return;
        }
        state.core = checkpoint;
        state.core.audio = rollbackAudio;
        @checkpoint = null;
        state.rollbackCheckpoints.resize(count);
        NovelPresentationState@ p = state.core.presentation;
        p.transition.elapsed = p.transition.duration;
        for (uint i = 0; i < 3; ++i)
        {
            String id = presentation.CharacterId(i);
            if (p.characters.contains(id))
            {
                p.characters.at(id).transitionElapsed = p.characters.at(id).transitionDuration;
                p.characters.at(id).bounceActive = false;
            }
        }
        FinishRestore();
    }

    void RefreshReadIndex(bool force = false)
    {
        uint count = MenuSession::profile.readLines.size();
        if (!force && readIndexCount == count)
        {
            return;
        }
        readIndex.clear();
        for (uint i = 0; i < count; ++i)
        {
            readIndex.set(MenuSession::profile.readLines[i], true);
        }
        readIndexCount = count;
    }

    bool IsRead(const String &in id)
    {
        RefreshReadIndex();
        return readIndex.contains(id);
    }

    void MarkRead(const String &in id)
    {
        if (id == "" || IsRead(id))
        {
            return;
        }
        MenuSession::profile.readLines.pushBack(id);
        readIndex.set(id, true);
        readIndexCount = MenuSession::profile.readLines.size();
        menu.saves.MarkProfile();
    }

    void ReadingTick(float dt)
    {
        bool skip = skipEnabled || Input::Instance().GetKey(KeyCode::LCtrl) || Input::Instance().GetKey(KeyCode::RCtrl);
        if (skip)
        {
            autoEnabled = false;
            autoDelay = 0;
        }
        skipDelay -= dt;
        NovelPresentationState@ p = state.core.presentation;
        if (skip && PhaseName() == "WaitingText")
        {
            if (!MenuSession::profile.settings.skip_unseen && !IsRead(state.core.position))
            {
                skipEnabled = false;
                return;
            }
            audio.StopTyping();
            if (skipDelay <= 0)
            {
                skipDelay = 1.0f / 30;
                if (p.fullyShown)
                {
                    FinishSay();
                }
                else
                {
                    p.inputWait = false;

                    TextTick(0, true);
                }
            }
        }
        else if (skip && PhaseName() == "WaitingTimer" && !p.inputWait)
        {
            Phase("Ready");
        }
        else if (skip && PhaseName() == "WaitingTransition" && MenuSession::profile.settings.skip_transitions)
        {
            NovelTransition@ transition = p.transition;
            transition.elapsed = transition.duration;
        }
        else if (autoEnabled && PhaseName() == "WaitingText" && p.fullyShown && !p.inputWait && p.remainingPause <= 0)
        {
            autoDelay += dt;
            float delay = MenuSession::profile.settings.afm_time * (float(program.plain.graphemeCount()) + 25) / 250;
            if (autoDelay >= delay)
            {
                autoDelay = 0;
                FinishSay();
            }
        }
    }

    void Update(float dt)
    {
        if (state is null || !menu.inGame)
        {
            return;
        }
        if (PhaseName() != "Finished" && !runner.IsRunning() && state.core.frames.size() > 0)
        {
            // The coroutine is not part of the script object graph: after a hot reload it is rebuilt from the frames.
            runner.Bind(this, state.core);
            if (!runner.Restore())
            {
                Fail("Не удалось продолжить сценарий после перезагрузки скриптов: " + runner.error);
                return;
            }
        }
        if (inputBarrier > 0)
        {
            inputBarrier -= dt;
        }
        NovelAudioState@ channels = state.core.audio;
        audio.Update(channels, Paused() || wasPaused ? 0 : dt);

        if (Paused())
        {
            wasPaused = true;
            audio.StopTyping();
            return;
        }
        if (wasPaused)
        {
            dt = 0;
            wasPaused = false;
        }
        if (restoreInputPending)
        {
            if (Input::Instance().GetKey(KeyCode::Space) || Input::Instance().GetKey(KeyCode::Enter) ||
                Input::Instance().GetKey(KeyCode::LCtrl) || Input::Instance().GetKey(KeyCode::RCtrl) ||
                Input::Instance().GetKey(KeyCode::MouseLeft))
            {
                return;
            }
            restoreInputPending = false;
            inputBarrier = 0.1f;
            return;
        }
        state.core.playTimeSeconds = state.core.playTimeSeconds + dt;
        Animate(dt);
        if (presentation.waitingTextures)
        {
            audio.StopTyping();
            return;
        }
        if (Input::Instance().GetKeyDown(KeyCode::PageUp) || Input::Instance().GetMouseWheel() > 0)
        {
            Rollback();
            return;
        }
        ReadingTick(dt);
        if (!menu.gameObject.GetScene().IsUIInputConsumed() && (Input::Instance().GetKeyDown(KeyCode::Space) || Input::Instance().GetKeyDown(KeyCode::Enter)))
        {
            Advance();
        }
        String phase = PhaseName();
        if (phase == "WaitingText")
        {
            TextTick(dt, false);
        }
        else if (phase == "WaitingTimer")
        {
            NovelPresentationState@ p = state.core.presentation;
            if (!p.inputWait)
            {
                float remaining = float(p.remainingPause) - dt;
                p.remainingPause = remaining > 0 ? remaining : 0;

                if (remaining <= 0)
                {
                    Phase("Ready");
                }
            }
        }
        else if (phase == "WaitingTransition" && state.core.presentation.transition.elapsed >= state.core.presentation.transition.duration)
        {
            Phase("Ready");
        }
        RunReady();
    }

    void Animate(float dt)
    {
        NovelPresentationState@ p = state.core.presentation;
        presentation.Animate(p, dt);
    }

    void RestorePresentation()
    {
        NovelPresentationState@ p = state.core.presentation;
        program.Compile(p.text, p.autoWait);
        presentation.Prepare(p);
        view.Dialogue(p, program, speakers.at(p.speakerId));
        view.Choices(p.choices, PhaseName() == "WaitingChoice");
        view.Effects(float(p.effectTime));
    }

    NovelState@ CaptureDebugState()
    {
        if (state is null)
        {
            return null;
        }
        NovelState snapshot;
        snapshot = state;
        audio.Update(snapshot.core.audio, 0);
        return snapshot;
    }

    bool HasDebugLabel(const String &in label)
    {
        return FindCoroutineEntry(label) !is null;
    }

    String SaveSnapshot()
    {
        if (state is null)
        {
            return "";
        }
        NovelState snapshot;
        snapshot = state;
        audio.Update(snapshot.core.audio, 0);
        return SerializeScriptValue(snapshot);
    }

    bool LoadSnapshot(const String &in encoded)
    {
        NovelState candidate;
        return DeserializeScriptValue(encoded, candidate) && RestoreDebugCheckpoint(candidate);
    }

    bool RestoreDebugCheckpoint(NovelState@ snapshot)
    {
        if (state is null || !ValidateSnapshot(snapshot))
        {
            return false;
        }
        NovelState candidate;
        candidate = snapshot;
        audio.Update(state.core.audio, 0);
        if (!audio.Restore(candidate.core.audio))
        {
            audio.Restore(state.core.audio);
            return false;
        }
        @state = candidate;
        return FinishRestore();
    }

    bool FinishRestore()
    {
        rollbackCount = state.rollbackCheckpoints.size();
        rollbackLastInteraction = rollbackCount > 0 ? state.rollbackCheckpoints[rollbackCount - 1].interaction : 0;
        skipEnabled = false;
        autoEnabled = false;
        autoDelay = 0;
        inputBarrier = 0.1f;
        runner.Bind(this, state.core);
        bool restored = runner.Restore();
        RestorePresentation();
        restoreInputPending = true;
        view.FocusNarrative(PhaseName() == "WaitingChoice");
        if (!restored)
        {
            Fail("Не удалось восстановить позицию сценария: " + runner.error);
        }
        return restored;
    }

    /// Checks fields and replays the story frames without touching the screen.
    bool ValidateSnapshot(NovelState@ snapshot)
    {
        if (!NovelSnapshotValidation::Validate(snapshot, definitions.View(), speakers, audio.paths))
        {
            return false;
        }
        NovelCore probeCore;
        probeCore = snapshot.core;
        StoryRunner probe;
        probe.Bind(null, probeCore);
        bool replayed = probe.Restore();
        probe.Abort();
        if (!replayed)
        {
            Debug::Instance().Error("NovelSession::ValidateSnapshot() : " + probe.error);
        }
        return replayed;
    }

    bool VerifySaveFormat()
    {
        JsonValue@ encoded = NovelSaveFormat::State(state.core);
        // Include the JSON text boundary used by disk storage in the round trip.
        JsonValue disk;
        if (!disk.Parse(encoded.View().ToJson())) return false;
        NovelState decoded;
        if (!NovelSaveFormat::ReadState(disk.View(), definitions.View(), decoded) ||
            !ValidateSnapshot(decoded) || decoded.rollbackCheckpoints.size() != 0 ||
            SerializeScriptValue(decoded.core.vars) != SerializeScriptValue(state.core.vars) ||
            SerializeScriptValue(decoded.core.frames) != SerializeScriptValue(state.core.frames) ||
            SerializeScriptValue(decoded.core.history) != SerializeScriptValue(state.core.history) ||
            decoded.core.position != state.core.position ||
            decoded.core.presentation.text != state.core.presentation.text ||
            decoded.core.presentation.visibleIndex != state.core.presentation.visibleIndex ||
            SerializeScriptValue(decoded.core.presentation.choices) != SerializeScriptValue(state.core.presentation.choices) ||
            SerializeScriptValue(decoded.core.presentation.nvl) != SerializeScriptValue(state.core.presentation.nvl)) return false;
        JsonValue@ roundTrip = NovelSaveFormat::State(decoded.core);
        if (!disk.View().Equals(roundTrip.View())) return false;
        NovelSaveFormat::Integer(disk, "schemaVersion", 2);
        if (NovelSaveFormat::ReadState(disk.View(), definitions.View(), decoded)) return false;
        NovelSaveFormat::Integer(disk, "schemaVersion", NovelSaveFormat::Version + 1);
        if (NovelSaveFormat::ReadState(disk.View(), definitions.View(), decoded)) return false;
        NovelSaveFormat::Integer(disk, "schemaVersion", NovelSaveFormat::Version);
        NovelSaveFormat::Text(disk, "unexpected", "reject unknown fields");
        if (NovelSaveFormat::ReadState(disk.View(), definitions.View(), decoded)) return false;

        JsonValue@ profile = NovelSaveFormat::Profile(MenuSession::profile);
        MenuProfile decodedProfile;
        if (!disk.Parse(profile.View().ToJson()) ||
            !NovelSaveFormat::ReadProfile(disk.View(), decodedProfile) ||
            !menu.saves.ValidProfile(decodedProfile) ||
            SerializeScriptValue(decodedProfile) != SerializeScriptValue(MenuSession::profile)) return false;
        NovelSaveFormat::Integer(disk, "schemaVersion", 2);
        return !NovelSaveFormat::ReadProfile(disk.View(), decodedProfile);
    }

    NovelRestoreReport@ VerifyRestoreTwice()
    {
        NovelRestoreReport result;
        NovelState@ snapshot = CaptureDebugState();
        if (snapshot is null)
        {
            result.status = "NO_SESSION";
            return result;
        }
        result.objectsBefore = menu.gameObject.GetHierarchyObjectCount();
        String encoded = SaveSnapshot();
        bool first = LoadSnapshot(encoded);
        bool second = first && LoadSnapshot(encoded);
        result.textRules = VerifyTextRules();
        bool equal = result.textRules && second && VerifySaveFormat() &&
            SerializeScriptValue(snapshot.core.vars) == SerializeScriptValue(state.core.vars) &&
            SerializeScriptValue(snapshot.core.frames) == SerializeScriptValue(state.core.frames) &&
            SerializeScriptValue(snapshot.core.history) == SerializeScriptValue(state.core.history) &&
            SerializeScriptValue(snapshot.core.presentation) == SerializeScriptValue(state.core.presentation);
        result.objectsAfter = menu.gameObject.GetHierarchyObjectCount();
        equal = equal && result.objectsBefore == result.objectsAfter;
        result.status = equal ? "PASSED_IN_THIS_RUN" : "FAILED";
        result.snapshot = SerializeScriptValue(snapshot);
        result.after = SerializeScriptValue(state);
        result.audioDiagnostic = audio.diagnostic;
        return result;
    }

    bool VerifyTextRules()
    {
        DialogueProgram test;
        bool correct = test.AutoWaits("А, Б.") == "А,{w=0.25} Б." &&
            test.AutoWaits("...") == ".{w=0.25}.{w=0.25}.{w=0.25}" &&
            test.AutoWaits("…") == ".{w=0.25}.{w=0.25}.{w=0.25}" &&
            test.AutoWaits("1.25") == "1.25" &&
            test.AutoWaits("А!{i} {/i}{w} Б") == "А!{i} {/i}{w} Б" &&
            test.AutoWaits("{shader=shake:u__speed=50.0}А{/shader}.") == "{shader=shake:u__speed=50.0}А{/shader}.";
        test.Compile("ё{w}Б{w=0.2}{nw}", false);
        correct = correct && test.plain.graphemeCount() == 2 && test.tokenCount == 4 &&
            test.tokens[1].kind == "input" && test.noWait;
        test.Compile("{size=+10}А{size=-5}Б{/size}В{/size}", false);
        float nested = float(test.spans[0].relativeSize) * float(test.spans[1].relativeSize);
        correct = correct && nested > 1.1514f && nested < 1.1516f;
        return correct;
    }

    void End()
    {
        menu.saves.queuedGroup = "";
        menu.saves.openAfterYield = false;
        menu.saves.autoPending = false;
        runner.Abort();
        audio.Stop();
        if (configured)
        {
            view.root.SetEnabled(false);
        }
        if (state !is null)
        {
            Phase("Finished");
        }
    }
}
