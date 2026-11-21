//
// Created by Codex on 17.11.2026.
//

#include "NovelView.as"
#include "NovelAudio.as"
#include "NovelPresentation.as"
#include "NovelSnapshotValidation.as"
#include "../Debug/StoryDebugPanel.as"

class NovelSession : IMenuSessionStarter, IStoryDebugRuntime
{
    MenuNavigation@ menu;
    NovelView view;
    NovelAudio audio;
    NovelPresentation presentation;
    DialogueProgram program;
    JsonValue story;
    JsonValue@ commands;
    Map<String, String> endingTargets;
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
    String rollbackLastCommand;

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
        for (uint i = 0; i < speakerManifest.GetCount(); ++i)
        {
            String id = speakerManifest.GetKey(i);
            JsonValue@ source = speakerManifest.Get(id);
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
        audio.Build(menu.gameObject.GetOrCreateChild("RuntimeAudio"), manifest);
        for (uint i = 0; i < speakerManifest.GetCount(); ++i)
        {
            NovelSpeaker@ speaker = speakers.at(speakerManifest.GetKey(i));
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
        startupError = "Не удалось загрузить story.json или characters.json. Подробности в журнале движка.";
        if (!story.LoadResource("DeathLovers/Story/story.json") ||
            !definitions.LoadResource("DeathLovers/Story/characters.json"))
        {
            return false;
        }
        startupError = "Неверная версия Story или отсутствует начальная команда.";
        if (!NewGame())
        {
            return false;
        }
        startupError = "";
        return true;
    }

    bool StartFixture()
    {
        if (!configured || !story.LoadResource("DeathLovers/Story/runtime-fixture.json"))
        {
            return false;
        }
        definitions.LoadResource("DeathLovers/Story/characters.json");
        JsonValue@ characters = definitions.Get("characters");
        JsonValue@ character = characters.Get("ch_p");
        JsonValue animation;
        animation.SetString("single_bounce_animation");
        character.Set("animation", animation);
        characters.Set("ch_p", character);
        definitions.Set("characters", characters);
        traceEnabled = true;
        return NewGame();
    }

    bool NewGame()
    {
        skipEnabled = false;
        autoEnabled = false;
        autoDelay = 0;
        rollbackCount = 0;
        rollbackLastCommand = "";
        @commands = story.Get("commands");
        if (story.Get("schemaVersion").GetInt() != 1 || !commands.Has(story.Get("entryCommandId").GetString()))
        {
            return false;
        }
        endingTargets.clear();
        JsonValue@ labels = story.Get("labels");
        for (uint i = 0; i < labels.GetCount(); ++i)
        {
            String label = labels.GetKey(i);
            if (label.length() > 7 && label.substring(label.length() - 7, 7) == "_ending")
            {
                endingTargets.set(labels.Get(label).GetString(), label);
            }
        }
        audio.Stop();
        @state = NovelState();
        state.rollbackCheckpoints.reserve(100);
        state.core.history.reserve(250);
        state.core.callStack.reserve(16);
        state.core.presentation.choices.reserve(8);
        state.core.schemaVersion = 2;
        state.core.contentVersion = story.Get("contentVersion").GetString();
        state.core.currentCommandId = story.Get("entryCommandId").GetString();
        Phase("Ready");
        JsonValue@ registry = story.Get("variables");
        for (uint i = 0; i < registry.GetCount(); ++i)
        {
            String id = registry.GetKey(i);
            Value@ initial = RuntimeValues::FromJson(registry.Get(id).Get("initial"));
            if (!initial.hasValue())
            {
                return false;
            }
            state.core.variables.set(id, initial);
        }
        state.rollbackCheckpoints.clear();
        state.core.rollbackBoundaryId = "";
        state.core.activeEndingId = "";
        state.core.diagnostic = "";
        state.core.playTimeSeconds = 0;
        trace.clear();
        inputBarrier = 0.1f;
        menu.gameMenuOpen = false;
        menu.inGame = true;
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
        return !menu.inGame || menu.gameMenuOpen || menu.modal !is null || !Input::Instance().IsAppFocused();
    }

    JsonValue@ Command()
    {
        return commands.Get(state.core.currentCommandId);
    }

    void Fail(const String &in message)
    {
        JsonValue@ command = Command();
        String location = state.core.currentCommandId + " " + RuntimeValues::Text(command, "sourceFile");
        if (command.Has("sourceLine"))
        {
            location = location + ":" + RuntimeValues::Index(uint(command.Get("sourceLine").GetInt()));
        }
        state.core.diagnostic = "NovelSession : " + location + " : " + message;
        Phase("Finished");
        view.adv.SetEnabled(true);
        view.dialogue.SetText(state.core.diagnostic);
        view.dialogue.SetVisibleGraphemeCount(1000000);
        audio.StopTyping();
    }

    void Go(JsonValue@ target)
    {
        GoId(target.GetString());
    }

    void GoId(const String &in id)
    {
        if (id == "")
        {
            Phase("Finished");
            return;
        }
        if (!commands.Has(id))
        {
            Fail("Unknown command " + id);
            return;
        }
        state.core.currentCommandId = id;
        if (endingTargets.contains(id))
        {
            state.core.activeEndingId = endingTargets.at(id);
        }
        Phase("Ready");
    }

    Value@ Evaluate(JsonValue@ node, uint depth = 0)
    {
        Value result;
        bool boolean = false;
        if (depth > 64)
        {
            Fail("Condition nesting limit");
            result.set(boolean);
            return result;
        }
        String op = node.Get("op").GetString();
        if (op == "literal")
        {
            return RuntimeValues::FromJson(node.Get("value"));
        }
        if (op == "variable")
        {
            String id = node.Get("variableId").GetString();
            if (!state.core.variables.contains(id))
            {
                Fail("Unknown variable " + id);
                result.set(boolean);
                return result;
            }
            return state.core.variables.at(id);
        }
        if (op == "not")
        {
            Value@ operand = Evaluate(node.Get("operand"), depth + 1);
            if (!operand.get(boolean))
            {
                Fail("not requires bool");
            }
            boolean = !boolean;
        }
        else if (op == "and" || op == "or")
        {
            JsonValue@ operands = node.Get("operands");
            boolean = op == "and";
            for (uint i = 0; i < operands.GetCount(); ++i)
            {
                Value@ value = Evaluate(operands.At(i), depth + 1);
                if (!value.get(boolean))
                {
                    Fail("Boolean operator requires bool");
                    boolean = false;
                    break;
                }
                if (PhaseName() == "Finished" || boolean == (op == "or"))
                {
                    break;
                }
            }
        }
        else
        {
            Value@ left = Evaluate(node.Get("left"), depth + 1);
            Value@ right = Evaluate(node.Get("right"), depth + 1);
            if (!RuntimeValues::SameType(left, right))
            {
                Fail("Comparison type mismatch");
            }
            else if (op == "eq" || op == "ne")
            {
                bool equal = RuntimeValues::Equal(left, right);
                boolean = op == "eq" ? equal : !equal;
            }
            else
            {
                int64 a, b;
                if (!left.get(a) || !right.get(b) || (op != "lt" && op != "le" && op != "gt" && op != "ge"))
                {
                    Fail("Invalid comparison operator/type " + op);
                }
                else
                {
                    boolean = op == "lt" ? a < b : op == "le" ? a <= b : op == "gt" ? a > b : a >= b;
                }
            }
        }
        result.set(boolean);
        return result;
    }

    bool Condition(JsonValue@ node)
    {
        Value@ result = Evaluate(node);
        bool boolean = false;
        if (!result.get(boolean))
        {
            Fail("Condition requires bool");
        }
        return boolean;
    }

    void Assign(JsonValue@ command)
    {
        String id = command.Get("variableId").GetString();
        Value@ value = RuntimeValues::FromJson(command.Get("value"));
        if (!state.core.variables.contains(id) || !RuntimeValues::SameType(state.core.variables.at(id), value))
        {
            Fail("Invalid variable assignment " + id);
            return;
        }
        String operation = command.Get("operation").GetString();
        int64 integer = 0;
        bool isInteger = value.get(integer);
        if (isInteger && (integer < -2147483648 || integer > 2147483647))
        {
            Fail("int32 assignment overflow " + id);
            return;
        }
        if (operation == "add")
        {
            int64 current = 0;
            if (!isInteger || !state.core.variables.at(id).get(current))
            {
                Fail("add requires int");
                return;
            }
            integer += current;
            if (integer < -2147483648 || integer > 2147483647)
            {
                Fail("int32 assignment overflow " + id);
                return;
            }
            value.set(integer);
        }
        else if (operation != "set")
        {
            Fail("Unknown assignment operation");
            return;
        }
        state.core.variables.set(id, value);
        Go(command.Get("next"));
    }

    float Duration(JsonValue@ transition)
    {
        if (transition.Has("seconds"))
        {
            return float(transition.Get("seconds").GetNumber());
        }
        String kind = transition.Get("kind").GetString();
        // Ren'Py common transitions: fade=.5 out + .0 hold + .5 in;
        // dissolve=.5; vpunch=.25. Explicit durations always take priority.
        return kind == "fade" ? 1.0f : kind == "dissolve" ? 0.5f : kind == "vpunch" ? 0.25f : 0;
    }

    void Say(JsonValue@ command)
    {
        String speakerId = command.Get("speakerId").GetString();
        if (!speakers.contains(speakerId))
        {
            Fail("Unknown speaker " + speakerId);
            return;
        }
        program.Compile(command.Get("normalizedText").GetString(), command.Get("autoWait").GetBool());
        if (program.diagnostic != "")
        {
            state.core.diagnostic = command.Get("id").GetString() + " : " + program.diagnostic;
        }
        NovelPresentationState@ p = state.core.presentation;
        p.mode = command.Get("mode").GetString();
        p.speakerId = command.Get("speakerId").GetString();
        p.text = command.Get("normalizedText").GetString();
        p.autoWait = command.Get("autoWait").GetBool();
        p.visibleIndex = 0;
        p.tokenIndex = 0;
        p.remainingPause = 0;
        p.inputWait = false;
        p.fullyShown = false;
        p.dialogueVisible = true;
        NovelHistoryEntry entry;
        entry.commandId = command.Get("id").GetString();
        entry.speakerId = command.Get("speakerId").GetString();
        entry.text = p.autoWait ? program.AutoWaits(p.text) : p.text;
        if (state.core.history.size() >= 250)
        {
            state.core.history.erase(0);
        }
        state.core.history.pushBack(entry);
        if (command.Get("mode").GetString() == "NVL")
        {
            p.nvl.pushBack(entry);
        }

        Phase("WaitingText");
        view.Dialogue(p, program, speakers.at(speakerId));
        autoDelay = 0;
        RememberInteraction();
    }

    void Character(JsonValue@ command)
    {
        String id = command.Get("characterId").GetString();
        String name = command.Get("state").GetString();
        JsonValue@ registry = definitions.Get("characters");
        if (!registry.Has(id) || !registry.Get(id).Get("stateResources").Has(name))
        {
            Fail("Unknown character/state " + id + " " + name);
            return;
        }
        NovelPresentationState@ p = state.core.presentation;
        JsonValue@ definition = registry.Get(id);
        NovelCharacter character;
        character.position.x = float(definition.Get("position").At(0).GetNumber());
        character.position.y = float(definition.Get("position").At(1).GetNumber());
        character.scale.x = float(definition.Get("scale").At(0).GetNumber());
        character.scale.y = float(definition.Get("scale").At(1).GetNumber());
        character.flipX = definition.Get("flip").At(0).GetBool();
        character.flipY = definition.Get("flip").At(1).GetBool();
        character.animation = RuntimeValues::Text(definition, "animation");
        String previous = p.characters.contains(id) ? p.characters.at(id).resourceId : "hidden";
        character.state = command.Get("state").GetString();
        character.resourceId = definition.Get("stateResources").Get(name).GetString();
        character.previousResource = previous;
        character.transitionDuration = Duration(command.Get("transition"));
        character.transitionElapsed = 0;
        character.bounceElapsed = 0;
        character.bounceActive = character.animation == "single_bounce_animation";
        p.characters.set(id, character);

        presentation.PaintCharacters(p);
        Go(command.Get("next"));
    }

    void Execute(JsonValue@ command)
    {
        String type = command.Get("type").GetString();
        if (type == "Say")
        {
            Say(command);
            return;
        }
        if (type == "Assign")
        {
            Assign(command);
            return;
        }
        if (type == "Character")
        {
            Character(command);
            return;
        }
        if (type == "Jump")
        {
            Go(command.Get("target"));
            return;
        }
        if (type == "Call")
        {
            if (state.core.callStack.size() >= 1000)
            {
                Fail("Call stack limit");
                return;
            }
            state.core.callStack.pushBack(command.Get("returnTarget").GetString());
            Go(command.Get("target"));
            return;
        }
        if (type == "Return")
        {
            if (state.core.callStack.size() == 0)
            {
                Phase("Finished");
                return;
            }
            String target = state.core.callStack[state.core.callStack.size() - 1];
            state.core.callStack.resize(state.core.callStack.size() - 1);
            GoId(target);
            return;
        }
        if (type == "Branch")
        {
            bool result = Condition(command.Get("condition"));
            if (PhaseName() != "Finished")
            {
                Go(command.Get(result ? "trueTarget" : "falseTarget"));
            }
            return;
        }
        NovelPresentationState@ p = state.core.presentation;
        if (type == "Choice")
        {
            p.choices.clear();
            JsonValue@ source = command.Get("options");
            for (uint i = 0; i < source.GetCount(); ++i)
            {
                JsonValue@ option = source.At(i);
                if (!option.Has("condition") || Condition(option.Get("condition")))
                {
                    NovelChoice choice;
                    choice.choiceId = option.Get("choiceId").GetString();
                    choice.normalizedText = option.Get("normalizedText").GetString();
                    choice.target = option.Get("target").GetString();
                    p.choices.pushBack(choice);
                }
            }
            if (PhaseName() == "Finished")
            {
                return;
            }
            if (p.choices.size() == 0 || p.choices.size() > 8)
            {
                Fail("Choice has zero or more than eight available options");
                return;
            }

            Phase("WaitingChoice");
            RememberInteraction();
            if (!MenuSession::profile.settings.skip_after_choices)
            {
                skipEnabled = false;
            }
            view.Choices(p.choices, true);
            inputBarrier = 0.1f;
            return;
        }
        if (type == "Scene")
        {
            String id = command.Get("resourceId").GetString();
            if (id != "builtin:black" && audio.Path(id) == "")
            {
                Fail("Unknown background " + id);
                return;
            }
            NovelTransition@ transition = p.transition;
            transition.kind = command.Get("transition").Get("kind").GetString();
            transition.from = p.background;
            transition.target = command.Get("resourceId").GetString();
            transition.elapsed = 0;
            transition.duration = Duration(command.Get("transition"));
            p.background = command.Get("resourceId").GetString();

            presentation.PaintBackground(p);
            if (transition.duration > 0)
            {
                Phase("WaitingTransition");
            }
            else
            {
                Go(command.Get("next"));
            }
            return;
        }
        if (type == "NvlClear")
        {
            p.nvl.clear();
            p.dialogueVisible = false;

            view.nvl.SetEnabled(false);
        }
        else if (type == "Audio")
        {
            NovelAudioState@ channels = state.core.audio;
            if (!audio.Command(channels, command))
            {
                Fail(audio.diagnostic);
                return;
            }
        }
        else if (type == "Wait")
        {
            p.remainingPause = command.Has("seconds") ? command.Get("seconds").GetNumber() : 0;
            p.inputWait = command.Has("waitForInput") && command.Get("waitForInput").GetBool();

            Phase("WaitingTimer");
            return;
        }
        else if (type == "RollbackBarrier")
        {
            rollbackCount = 0;
            rollbackLastCommand = "";
            state.core.rollbackBoundaryId = command.Get("id").GetString();
            state.rollbackCheckpoints.clear();
        }
        else if (type == "RestartToMenu")
        {
            Phase("Finished");
            menu.ReturnToMainMenu();
            return;
        }
        else
        {
            Fail("Unknown command type " + type);
            return;
        }
        Go(command.Get("next"));
    }

    void RunReady()
    {
        for (uint count = 0; count < 1000 && PhaseName() == "Ready"; ++count)
        {
            String before;
            if (traceEnabled)
            {
                before = SerializeScriptValue(state.core);
            }
            JsonValue@ command = Command();
            Execute(command);
            if (traceEnabled)
            {
                NovelTraceEvent event;
                event.commandId = command.Get("id").GetString();
                event.before = before;
                event.after = SerializeScriptValue(state.core);
                trace.pushBack(event);
            }
            presentation.Prepare(state.core.presentation);
            if (presentation.waitingTextures)
            {
                return;
            }
        }
        if (PhaseName() == "Ready")
        {
            Fail("1000 commands in one frame: probable cycle");
        }
    }

    void FinishSay()
    {
        String id = state.core.currentCommandId;
        bool seen = false;
        for (uint i = 0; i < MenuSession::profile.readCommandIds.size(); ++i)
        {
            if (MenuSession::profile.readCommandIds[i] == id)
            {
                seen = true;
                break;
            }
        }
        if (!seen)
        {
            MenuSession::profile.readCommandIds.pushBack(id);
        }
        Go(Command().Get("next"));
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
        autoEnabled = false;
        inputBarrier = 0.1f;
        NovelPresentationState@ p = state.core.presentation;
        if (PhaseName() == "WaitingTimer" && p.inputWait)
        {
            p.inputWait = false;

            Go(Command().Get("next"));
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
        String target = p.choices[index].target;
        p.choices.clear();

        view.Choices(p.choices, false);
        inputBarrier = 0.1f;
        GoId(target);
    }

    void RememberInteraction()
    {
        if (state.rollbackCheckpoints.size() >= 100)
        {
            state.rollbackCheckpoints.erase(0);
        }
        state.rollbackCheckpoints.pushBack(state.core);
        NovelCore@ core = state.rollbackCheckpoints[state.rollbackCheckpoints.size() - 1];
        if (PhaseName() == "WaitingText")
        {
            core.presentation.visibleIndex = program.plain.graphemeCount();
            core.presentation.tokenIndex = program.tokenCount;
            core.presentation.fullyShown = true;
            core.presentation.inputWait = false;
            core.presentation.remainingPause = 0;
        }
        rollbackCount = state.rollbackCheckpoints.size();
        rollbackLastCommand = state.core.currentCommandId;
    }

    bool CanRollback()
    {
        if (state is null)
        {
            return false;
        }
        uint count = rollbackCount;
        if (count > 0 && rollbackLastCommand == state.core.currentCommandId)
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
        if (state.rollbackCheckpoints[count - 1].currentCommandId == state.core.currentCommandId)
        {
            --count;
        }
        NovelState target;
        target.core = state.rollbackCheckpoints[count - 1];
        for (uint i = 0; i < count; ++i)
        {
            target.rollbackCheckpoints.pushBack(state.rollbackCheckpoints[i]);
        }
        NovelPresentationState@ p = target.core.presentation;
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
        target.core.audio.Sfx.completed = true;
        target.core.audio.Voice.completed = true;
        if (!RestoreDebugCheckpoint(target))
        {
            state.core.diagnostic = "NovelSession::Rollback() : snapshot restore failed. " + audio.diagnostic;
            menu.ShowNotify("Не удалось восстановить точку отката.", menu.rollbackButton);
        }
    }

    bool IsRead(const String &in id)
    {
        for (uint i = 0; i < MenuSession::profile.readCommandIds.size(); ++i)
        {
            if (MenuSession::profile.readCommandIds[i] == id)
            {
                return true;
            }
        }
        return false;
    }

    void ReadingTick(float dt)
    {
        bool skip = skipEnabled || Input::Instance().GetKey(KeyCode::LCtrl) || Input::Instance().GetKey(KeyCode::RCtrl);
        skipDelay -= dt;
        NovelPresentationState@ p = state.core.presentation;
        if (skip && PhaseName() == "WaitingText")
        {
            autoEnabled = false;
            if (!MenuSession::profile.settings.skip_unseen && !IsRead(state.core.currentCommandId))
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
            Go(Command().Get("next"));
        }
        else if (skip && PhaseName() == "WaitingTransition" && MenuSession::profile.settings.skip_transitions)
        {
            NovelTransition@ transition = p.transition;
            transition.elapsed = transition.duration;
        }
        else if (autoEnabled && PhaseName() == "WaitingText" && p.fullyShown && !p.inputWait)
        {
            autoDelay += dt;
            float delay = MenuSession::profile.settings.afm_time * (float(program.plain.graphemeCount()) / 250 + 1);
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
                    Go(Command().Get("next"));
                }
            }
        }
        else if (phase == "WaitingTransition" && state.core.presentation.transition.elapsed >= state.core.presentation.transition.duration)
        {
            Go(Command().Get("next"));
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
        audio.Update(state.core.audio, 0);
        NovelState snapshot;
        snapshot = state;
        return snapshot;
    }

    bool HasDebugCommand(const String &in commandId)
    {
        return commands !is null && commands.Has(commandId);
    }

    String SaveSnapshot()
    {
        if (state is null)
        {
            return "";
        }
        audio.Update(state.core.audio, 0);
        return SerializeScriptValue(state);
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
        rollbackCount = state.rollbackCheckpoints.size();
        rollbackLastCommand = rollbackCount > 0 ? state.rollbackCheckpoints[rollbackCount - 1].currentCommandId : "";
        skipEnabled = false;
        autoEnabled = false;
        autoDelay = 0;
        inputBarrier = 0.1f;
        RestorePresentation();
        view.FocusNarrative(PhaseName() == "WaitingChoice");
        return true;
    }

    bool ValidateSnapshot(NovelState@ snapshot)
    {
        return NovelSnapshotValidation::Validate(snapshot, story, definitions, speakers, audio.paths);
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
        bool equal = result.textRules && second &&
            SerializeScriptValue(snapshot.core.variables) == SerializeScriptValue(state.core.variables) &&
            SerializeScriptValue(snapshot.core.history) == SerializeScriptValue(state.core.history) &&
            SerializeScriptValue(snapshot.core.callStack) == SerializeScriptValue(state.core.callStack) &&
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
        test.Compile("ё{w}Б{w=0.2}{nw}", false);
        correct = correct && test.plain.graphemeCount() == 2 && test.tokenCount == 4 &&
            test.tokens[1].kind == "input" && test.noWait;
        test.Compile("{size=+10}А{size=-5}Б{/size}В{/size}", false);
        float nested = float(test.spans[0].relativeSize) * float(test.spans[1].relativeSize);
        correct = correct && nested > 1.1514f && nested < 1.1516f;
        return correct;
    }

    void End()
    {
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
