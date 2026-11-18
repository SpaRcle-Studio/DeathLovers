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
    JsonValue@ endingTargets;
    JsonValue definitions;
    JsonValue speakers;
    JsonValue@ state;
    JsonValue@ trace;
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
        configured = false;
        startupError = "Не удалось загрузить assets.json, characters.json или speakers.json. Подробности в журнале движка.";
        if (!manifest.LoadResource("DeathLovers/Story/assets.json") ||
            !definitions.LoadResource("DeathLovers/Story/characters.json") ||
            !speakers.LoadResource("DeathLovers/Story/speakers.json"))
        {
            return;
        }
        startupError = "Не удалось создать интерфейс или аудио новеллы. Подробности в журнале движка.";
        @presentation.view = view;
        @presentation.audio = audio;
        view.Build(menu.novel, receiver);
        audio.Build(menu.gameObject.GetOrCreateChild("RuntimeAudio"), manifest);
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
        RuntimeValues::PutString(character, "animation", "single_bounce_animation");
        characters.Set("ch_p", character);
        definitions.Set("characters", characters);
        traceEnabled = true;
        return NewGame();
    }

    JsonValue@ InitialPresentation()
    {
        JsonValue result;
        result.Parse("{\"background\":\"builtin:black\",\"characters\":{},\"mode\":\"ADV\",\"speakerId\":\"ch_narrator\",\"text\":\"\",\"autoWait\":false,\"visibleIndex\":0,\"tokenIndex\":0,\"remainingPause\":0,\"inputWait\":false,\"fullyShown\":false,\"dialogueVisible\":false,\"choices\":[],\"nvl\":[],\"transition\":{\"kind\":\"none\",\"from\":\"builtin:black\",\"target\":\"builtin:black\",\"elapsed\":0,\"duration\":0},\"effectTime\":0}");
        return result.Clone();
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
        @endingTargets = RuntimeValues::Object();
        JsonValue@ labels = story.Get("labels");
        for (uint i = 0; i < labels.GetCount(); ++i)
        {
            String label = labels.GetKey(i);
            if (label.length() > 7 && label.substring(label.length() - 7, 7) == "_ending")
            {
                RuntimeValues::PutString(endingTargets, labels.Get(label).GetString(), label);
            }
        }
        audio.Stop();
        @state = RuntimeValues::Object();
        state.Set("schemaVersion", RuntimeValues::IntValue(1));
        state.Set("contentVersion", story.Get("contentVersion"));
        state.Set("currentCommandId", story.Get("entryCommandId"));
        Phase("Ready");
        state.Set("callStack", RuntimeValues::Array());
        JsonValue@ variables = RuntimeValues::Object();
        JsonValue@ registry = story.Get("variables");
        for (uint i = 0; i < registry.GetCount(); ++i)
        {
            String id = registry.GetKey(i);
            variables.Set(id, registry.Get(id).Get("initial"));
        }
        state.Set("variables", variables);
        state.Set("presentation", InitialPresentation());
        state.Set("audio", audio.EmptyState());
        state.Set("history", RuntimeValues::Array());
        state.Set("rollbackCheckpoints", RuntimeValues::Array());
        RuntimeValues::PutString(state, "rollbackBoundaryId", "");
        RuntimeValues::PutString(state, "activeEndingId", "");
        RuntimeValues::PutString(state, "diagnostic", "");
        RuntimeValues::PutNumber(state, "playTimeSeconds", 0);
        @trace = RuntimeValues::Array();
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
        return state is null ? "Finished" : state.Get("phase").GetString();
    }

    void Phase(const String &in phase)
    {
        RuntimeValues::PutString(state, "phase", phase);
    }

    bool Paused()
    {
        return !menu.inGame || menu.gameMenuOpen || menu.modal !is null || !Input::Instance().IsAppFocused();
    }

    JsonValue@ Command()
    {
        return commands.Get(state.Get("currentCommandId").GetString());
    }

    void Fail(const String &in message)
    {
        JsonValue@ command = Command();
        String location = state.Get("currentCommandId").GetString() + " " + RuntimeValues::Text(command, "sourceFile");
        if (command.Has("sourceLine"))
        {
            location = location + ":" + command.Get("sourceLine").ToJson();
        }
        RuntimeValues::PutString(state, "diagnostic", "NovelSession : " + location + " : " + message);
        Phase("Finished");
        view.adv.SetEnabled(true);
        view.dialogue.SetText(state.Get("diagnostic").GetString());
        view.dialogue.SetVisibleGraphemeCount(1000000);
        audio.StopTyping();
    }

    void Go(JsonValue@ target)
    {
        if (target.GetKind() == JsonValueKind::Null || target.GetString() == "")
        {
            Phase("Finished");
            return;
        }
        String id = target.GetString();
        if (!commands.Has(id))
        {
            Fail("Unknown command " + id);
            return;
        }
        RuntimeValues::PutString(state, "currentCommandId", id);
        if (endingTargets.Has(id))
        {
            state.Set("activeEndingId", endingTargets.Get(id));
        }
        Phase("Ready");
    }

    JsonValue@ Evaluate(JsonValue@ node, uint depth = 0)
    {
        if (depth > 64)
        {
            Fail("Condition nesting limit");
            return RuntimeValues::BoolValue(false);
        }
        String op = node.Get("op").GetString();
        if (op == "literal")
        {
            return node.Get("value");
        }
        if (op == "variable")
        {
            String id = node.Get("variableId").GetString();
            if (!state.Get("variables").Has(id))
            {
                Fail("Unknown variable " + id);
                return RuntimeValues::BoolValue(false);
            }
            return state.Get("variables").Get(id);
        }
        if (op == "not")
        {
            JsonValue@ operand = Evaluate(node.Get("operand"), depth + 1);
            if (operand.GetKind() != JsonValueKind::Boolean)
            {
                Fail("not requires bool");
                return RuntimeValues::BoolValue(false);
            }
            return RuntimeValues::BoolValue(!operand.GetBool());
        }
        if (op == "and" || op == "or")
        {
            JsonValue@ operands = node.Get("operands");
            for (uint i = 0; i < operands.GetCount(); ++i)
            {
                JsonValue@ value = Evaluate(operands.At(i), depth + 1);
                if (value.GetKind() != JsonValueKind::Boolean)
                {
                    Fail("Boolean operator requires bool");
                    return RuntimeValues::BoolValue(false);
                }
                if (value.GetBool() == (op == "or"))
                {
                    return value;
                }
            }
            return RuntimeValues::BoolValue(op == "and");
        }
        JsonValue@ left = Evaluate(node.Get("left"), depth + 1);
        JsonValue@ right = Evaluate(node.Get("right"), depth + 1);
        if (left.GetKind() != right.GetKind())
        {
            Fail("Comparison type mismatch");
            return RuntimeValues::BoolValue(false);
        }
        if (op == "eq" || op == "ne")
        {
            bool equal = left.ToJson() == right.ToJson();
            return RuntimeValues::BoolValue(op == "eq" ? equal : !equal);
        }
        if (left.GetKind() != JsonValueKind::Integer || (op != "lt" && op != "le" && op != "gt" && op != "ge"))
        {
            Fail("Invalid comparison operator/type " + op);
            return RuntimeValues::BoolValue(false);
        }
        int64 a = left.GetInt();
        int64 b = right.GetInt();
        return RuntimeValues::BoolValue(op == "lt" ? a < b : op == "le" ? a <= b : op == "gt" ? a > b : a >= b);
    }

    bool Condition(JsonValue@ node)
    {
        JsonValue@ result = Evaluate(node);
        if (result.GetKind() != JsonValueKind::Boolean)
        {
            Fail("Condition requires bool");
            return false;
        }
        return result.GetBool();
    }

    void Assign(JsonValue@ command)
    {
        JsonValue@ variables = state.Get("variables");
        String id = command.Get("variableId").GetString();
        JsonValue@ value = command.Get("value");
        if (!variables.Has(id) || variables.Get(id).GetKind() != value.GetKind())
        {
            Fail("Invalid variable assignment " + id);
            return;
        }
        String operation = command.Get("operation").GetString();
        if (operation == "add")
        {
            if (value.GetKind() != JsonValueKind::Integer)
            {
                Fail("add requires int");
                return;
            }
            int64 sum = variables.Get(id).GetInt() + value.GetInt();
            if (sum < -2147483648 || sum > 2147483647)
            {
                Fail("int32 assignment overflow " + id);
                return;
            }
            @value = RuntimeValues::IntValue(sum);
        }
        else if (operation != "set")
        {
            Fail("Unknown assignment operation");
            return;
        }
        if (value.GetKind() == JsonValueKind::Integer && (value.GetInt() < -2147483648 || value.GetInt() > 2147483647))
        {
            Fail("int32 assignment overflow " + id);
            return;
        }
        variables.Set(id, value);
        state.Set("variables", variables);
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
        if (!speakers.Has(speakerId))
        {
            Fail("Unknown speaker " + speakerId);
            return;
        }
        program.Compile(command.Get("normalizedText").GetString(), command.Get("autoWait").GetBool());
        if (program.diagnostic != "")
        {
            RuntimeValues::PutString(state, "diagnostic", command.Get("id").GetString() + " : " + program.diagnostic);
        }
        JsonValue@ p = state.Get("presentation");
        p.Set("mode", command.Get("mode"));
        p.Set("speakerId", command.Get("speakerId"));
        p.Set("text", command.Get("normalizedText"));
        p.Set("autoWait", command.Get("autoWait"));
        p.Set("visibleIndex", RuntimeValues::IntValue(0));
        p.Set("tokenIndex", RuntimeValues::IntValue(0));
        RuntimeValues::PutNumber(p, "remainingPause", 0);
        p.Set("inputWait", RuntimeValues::BoolValue(false));
        p.Set("fullyShown", RuntimeValues::BoolValue(false));
        p.Set("dialogueVisible", RuntimeValues::BoolValue(true));
        JsonValue@ history = state.Get("history");
        JsonValue@ entry = RuntimeValues::Object();
        entry.Set("commandId", command.Get("id"));
        entry.Set("speakerId", command.Get("speakerId"));
        RuntimeValues::PutString(entry, "text", program.AutoWaits(command.Get("normalizedText").GetString()));
        if (!command.Get("autoWait").GetBool())
        {
            entry.Set("text", command.Get("normalizedText"));
        }
        history.Append(entry);
        state.Set("history", history.GetCount() > 250 ? RuntimeValues::Tail(history, 1) : history);
        if (command.Get("mode").GetString() == "NVL")
        {
            JsonValue@ lines = p.Get("nvl");
            lines.Append(entry);
            p.Set("nvl", lines);
        }
        state.Set("presentation", p);
        Phase("WaitingText");
        view.Dialogue(p, program, speakers.Get(speakerId));
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
        JsonValue@ p = state.Get("presentation");
        JsonValue@ characters = p.Get("characters");
        JsonValue@ character = registry.Get(id);
        String previous = characters.Has(id) ? characters.Get(id).Get("resourceId").GetString() : "hidden";
        character.Set("state", command.Get("state"));
        character.Set("resourceId", character.Get("stateResources").Get(name));
        RuntimeValues::PutString(character, "previousResource", previous);
        RuntimeValues::PutNumber(character, "transitionDuration", Duration(command.Get("transition")));
        RuntimeValues::PutNumber(character, "transitionElapsed", 0);
        RuntimeValues::PutNumber(character, "bounceElapsed", 0);
        character.Set("bounceActive", RuntimeValues::BoolValue(RuntimeValues::Text(character, "animation") == "single_bounce_animation"));
        characters.Set(id, character);
        p.Set("characters", characters);
        state.Set("presentation", p);
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
            JsonValue@ stack = state.Get("callStack");
            if (stack.GetCount() >= 1000)
            {
                Fail("Call stack limit");
                return;
            }
            stack.Append(command.Get("returnTarget"));
            state.Set("callStack", stack);
            Go(command.Get("target"));
            return;
        }
        if (type == "Return")
        {
            JsonValue@ stack = state.Get("callStack");
            if (stack.GetCount() == 0)
            {
                Phase("Finished");
                return;
            }
            JsonValue@ target = stack.At(stack.GetCount() - 1);
            JsonValue@ remaining = RuntimeValues::Array();
            for (uint i = 0; i + 1 < stack.GetCount(); ++i)
            {
                remaining.Append(stack.At(i));
            }
            state.Set("callStack", remaining);
            Go(target);
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
        JsonValue@ p = state.Get("presentation");
        if (type == "Choice")
        {
            JsonValue@ options = RuntimeValues::Array();
            JsonValue@ source = command.Get("options");
            for (uint i = 0; i < source.GetCount(); ++i)
            {
                JsonValue@ option = source.At(i);
                if (!option.Has("condition") || Condition(option.Get("condition")))
                {
                    options.Append(option);
                }
            }
            if (PhaseName() == "Finished")
            {
                return;
            }
            if (options.GetCount() == 0 || options.GetCount() > 8)
            {
                Fail("Choice has zero or more than eight available options");
                return;
            }
            p.Set("choices", options);
            state.Set("presentation", p);
            Phase("WaitingChoice");
            RememberInteraction();
            if (!MenuSession::profile.settings.skip_after_choices)
            {
                skipEnabled = false;
            }
            view.Choices(options, true);
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
            JsonValue@ transition = command.Get("transition");
            transition.Set("from", p.Get("background"));
            transition.Set("target", command.Get("resourceId"));
            RuntimeValues::PutNumber(transition, "elapsed", 0);
            RuntimeValues::PutNumber(transition, "duration", Duration(transition));
            p.Set("transition", transition);
            p.Set("background", command.Get("resourceId"));
            state.Set("presentation", p);
            presentation.PaintBackground(p);
            if (transition.Get("duration").GetNumber() > 0)
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
            p.Set("nvl", RuntimeValues::Array());
            p.Set("dialogueVisible", RuntimeValues::BoolValue(false));
            state.Set("presentation", p);
            view.nvl.SetEnabled(false);
        }
        else if (type == "Audio")
        {
            JsonValue@ channels = state.Get("audio");
            if (!audio.Command(channels, command))
            {
                Fail(audio.diagnostic);
                return;
            }
            state.Set("audio", channels);
        }
        else if (type == "Wait")
        {
            RuntimeValues::PutNumber(p, "remainingPause", command.Has("seconds") ? command.Get("seconds").GetNumber() : 0);
            p.Set("inputWait", RuntimeValues::BoolValue(command.Has("waitForInput") && command.Get("waitForInput").GetBool()));
            state.Set("presentation", p);
            Phase("WaitingTimer");
            return;
        }
        else if (type == "RollbackBarrier")
        {
            rollbackCount = 0;
            rollbackLastCommand = "";
            state.Set("rollbackBoundaryId", command.Get("id"));
            state.Set("rollbackCheckpoints", RuntimeValues::Array());
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
            JsonValue@ before;
            if (traceEnabled)
            {
                @before = state.Clone();
            }
            JsonValue@ command = Command();
            Execute(command);
            if (traceEnabled)
            {
                JsonValue@ event = RuntimeValues::Object();
                event.Set("commandId", command.Get("id"));
                event.Set("before", before);
                event.Set("after", state);
                trace.Append(event);
            }
        }
        if (PhaseName() == "Ready")
        {
            Fail("1000 commands in one frame: probable cycle");
        }
    }

    void FinishSay()
    {
        String id = state.Get("currentCommandId").GetString();
        bool seen = false;
        for (uint i = 0; i < MenuSession::profile.readCommandIds.GetCount(); ++i)
        {
            if (MenuSession::profile.readCommandIds.At(i).GetString() == id)
            {
                seen = true;
                break;
            }
        }
        if (!seen)
        {
            MenuSession::profile.readCommandIds.Append(RuntimeValues::StringValue(id));
        }
        Go(Command().Get("next"));
    }

    void TextTick(float dt, bool fast)
    {
        JsonValue@ p = state.Get("presentation");
        if (p.Get("fullyShown").GetBool() && program.noWait && !fast)
        {
            FinishSay();
            return;
        }
        if (p.Get("inputWait").GetBool() || p.Get("fullyShown").GetBool())
        {
            return;
        }
        float remaining = float(p.Get("remainingPause").GetNumber());
        if (fast)
        {
            remaining = 0;
        }
        else
        {
            remaining -= dt;
        }
        uint index = uint(p.Get("tokenIndex").GetInt());
        JsonValue@ channels = state.Get("audio");
        for (; index < program.tokens.GetCount() && (fast || remaining <= 0); ++index)
        {
            JsonValue@ token = program.tokens.At(index);
            String kind = token.Get("kind").GetString();
            if (kind == "input")
            {
                p.Set("inputWait", RuntimeValues::BoolValue(true));
                ++index;
                remaining = 0;
                break;
            }
            if (kind == "pause")
            {
                if (!fast)
                {
                    remaining += float(token.Get("value").GetNumber());
                }
                continue;
            }
            p.Set("visibleIndex", token.Get("index"));
            float cps = MenuSession::profile.settings.text_cps * float(token.Get("cps").GetNumber());
            if (!fast && cps > 0)
            {
                remaining += 1.0f / cps;
                if (kind == "glyph")
                {
                    audio.Type(channels, speakers.Get(p.Get("speakerId").GetString()), cps);
                }
            }
        }
        p.Set("tokenIndex", RuntimeValues::IntValue(index));
        RuntimeValues::PutNumber(p, "remainingPause", remaining > 0 ? remaining : 0);
        bool finished = index >= program.tokens.GetCount() && remaining <= 0 && !p.Get("inputWait").GetBool();
        p.Set("fullyShown", RuntimeValues::BoolValue(finished));
        state.Set("presentation", p);
        state.Set("audio", channels);
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
        if (state is null || Paused() || inputBarrier > 0)
        {
            return;
        }
        skipEnabled = false;
        autoEnabled = false;
        inputBarrier = 0.1f;
        JsonValue@ p = state.Get("presentation");
        if (PhaseName() == "WaitingTimer" && p.Get("inputWait").GetBool())
        {
            p.Set("inputWait", RuntimeValues::BoolValue(false));
            state.Set("presentation", p);
            Go(Command().Get("next"));
        }
        else if (PhaseName() == "WaitingText")
        {
            if (p.Get("inputWait").GetBool())
            {
                p.Set("inputWait", RuntimeValues::BoolValue(false));
                state.Set("presentation", p);
            }
            else if (p.Get("fullyShown").GetBool())
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
        if (state is null || Paused() || inputBarrier > 0 || PhaseName() != "WaitingChoice")
        {
            return;
        }
        JsonValue@ p = state.Get("presentation");
        JsonValue@ options = p.Get("choices");
        if (index >= options.GetCount())
        {
            return;
        }
        JsonValue@ option = options.At(index);
        p.Set("choices", RuntimeValues::Array());
        state.Set("presentation", p);
        view.Choices(options, false);
        inputBarrier = 0.1f;
        Go(option.Get("target"));
    }

    void RememberInteraction()
    {
        JsonValue@ core = RuntimeValues::Object();
        for (uint i = 0; i < state.GetCount(); ++i)
        {
            String key = state.GetKey(i);
            if (key != "rollbackCheckpoints")
            {
                core.Set(key, state.Get(key));
            }
        }
        core.Set("rollbackCheckpoints", RuntimeValues::Array());
        if (PhaseName() == "WaitingText")
        {
            JsonValue@ p = core.Get("presentation");
            p.Set("visibleIndex", RuntimeValues::IntValue(program.plain.graphemeCount()));
            p.Set("tokenIndex", RuntimeValues::IntValue(program.tokens.GetCount()));
            p.Set("fullyShown", RuntimeValues::BoolValue(true));
            p.Set("inputWait", RuntimeValues::BoolValue(false));
            RuntimeValues::PutNumber(p, "remainingPause", 0);
            core.Set("presentation", p);
        }
        JsonValue@ checkpoints = state.Get("rollbackCheckpoints");
        checkpoints.Append(core);
        state.Set("rollbackCheckpoints", checkpoints.GetCount() > 100 ? RuntimeValues::Tail(checkpoints, 1) : checkpoints);
        rollbackCount = checkpoints.GetCount() > 100 ? 100 : checkpoints.GetCount();
        rollbackLastCommand = state.Get("currentCommandId").GetString();
    }

    bool CanRollback()
    {
        if (state is null)
        {
            return false;
        }
        uint count = rollbackCount;
        if (count > 0 && rollbackLastCommand == state.Get("currentCommandId").GetString())
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
        skipEnabled = false;
        autoEnabled = false;
        autoDelay = 0;
        JsonValue@ checkpoints = state.Get("rollbackCheckpoints");
        uint count = checkpoints.GetCount();
        if (checkpoints.At(count - 1).Get("currentCommandId").GetString() == state.Get("currentCommandId").GetString())
        {
            --count;
        }
        JsonValue@ target = checkpoints.At(count - 1);
        JsonValue@ remaining = RuntimeValues::Array();
        for (uint i = 0; i < count; ++i)
        {
            remaining.Append(checkpoints.At(i));
        }
        target.Set("rollbackCheckpoints", remaining);
        JsonValue@ presentationState = target.Get("presentation");
        JsonValue@ transition = presentationState.Get("transition");
        transition.Set("elapsed", transition.Get("duration"));
        presentationState.Set("transition", transition);
        JsonValue@ characters = presentationState.Get("characters");
        for (uint i = 0; i < characters.GetCount(); ++i)
        {
            String id = characters.GetKey(i);
            JsonValue@ character = characters.Get(id);
            character.Set("transitionElapsed", character.Get("transitionDuration"));
            character.Set("bounceActive", RuntimeValues::BoolValue(false));
            characters.Set(id, character);
        }
        presentationState.Set("characters", characters);
        target.Set("presentation", presentationState);
        JsonValue@ channels = target.Get("audio");
        JsonValue@ sfx = channels.Get("Sfx");
        sfx.Set("completed", RuntimeValues::BoolValue(true));
        channels.Set("Sfx", sfx);
        JsonValue@ voice = channels.Get("Voice");
        voice.Set("completed", RuntimeValues::BoolValue(true));
        channels.Set("Voice", voice);
        target.Set("audio", channels);
        audio.StopTyping();
        if (!RestoreDebugCheckpoint(target))
        {
            RuntimeValues::PutString(state, "diagnostic", "NovelSession::Rollback() : snapshot restore failed. " + audio.diagnostic);
            menu.ShowNotify("Не удалось восстановить точку отката.", menu.rollbackButton);
        }
    }

    bool IsRead(const String &in id)
    {
        for (uint i = 0; i < MenuSession::profile.readCommandIds.GetCount(); ++i)
        {
            if (MenuSession::profile.readCommandIds.At(i).GetString() == id)
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
        JsonValue@ p = state.Get("presentation");
        if (skip && PhaseName() == "WaitingText")
        {
            autoEnabled = false;
            if (!MenuSession::profile.settings.skip_unseen && !IsRead(state.Get("currentCommandId").GetString()))
            {
                skipEnabled = false;
                return;
            }
            audio.StopTyping();
            if (skipDelay <= 0)
            {
                skipDelay = 1.0f / 30;
                if (p.Get("fullyShown").GetBool())
                {
                    FinishSay();
                }
                else
                {
                    p.Set("inputWait", RuntimeValues::BoolValue(false));
                    state.Set("presentation", p);
                    TextTick(0, true);
                }
            }
        }
        else if (skip && PhaseName() == "WaitingTimer" && !p.Get("inputWait").GetBool())
        {
            Go(Command().Get("next"));
        }
        else if (skip && PhaseName() == "WaitingTransition" && MenuSession::profile.settings.skip_transitions)
        {
            JsonValue@ transition = p.Get("transition");
            transition.Set("elapsed", transition.Get("duration"));
            p.Set("transition", transition);
            state.Set("presentation", p);
        }
        else if (autoEnabled && PhaseName() == "WaitingText" && p.Get("fullyShown").GetBool() && !p.Get("inputWait").GetBool())
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
        JsonValue@ channels = state.Get("audio");
        audio.Update(channels, Paused() || wasPaused ? 0 : dt);
        state.Set("audio", channels);
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
        RuntimeValues::PutNumber(state, "playTimeSeconds", state.Get("playTimeSeconds").GetNumber() + dt);
        Animate(dt);
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
            JsonValue@ p = state.Get("presentation");
            if (!p.Get("inputWait").GetBool())
            {
                float remaining = float(p.Get("remainingPause").GetNumber()) - dt;
                RuntimeValues::PutNumber(p, "remainingPause", remaining > 0 ? remaining : 0);
                state.Set("presentation", p);
                if (remaining <= 0)
                {
                    Go(Command().Get("next"));
                }
            }
        }
        else if (phase == "WaitingTransition" && state.Get("presentation").Get("transition").Get("elapsed").GetNumber() >= state.Get("presentation").Get("transition").Get("duration").GetNumber())
        {
            Go(Command().Get("next"));
        }
        RunReady();
    }

    void Animate(float dt)
    {
        JsonValue@ p = state.Get("presentation");
        presentation.Animate(p, dt);
        state.Set("presentation", p);
    }

    void RestorePresentation()
    {
        JsonValue@ p = state.Get("presentation");
        program.Compile(p.Get("text").GetString(), p.Get("autoWait").GetBool());
        presentation.PaintBackground(p);
        presentation.PaintCharacters(p);
        view.Dialogue(p, program, speakers.Get(p.Get("speakerId").GetString()));
        view.Choices(p.Get("choices"), PhaseName() == "WaitingChoice");
        view.Effects(float(p.Get("effectTime").GetNumber()));
    }

    JsonValue@ CaptureDebugState()
    {
        if (state is null)
        {
            return null;
        }
        JsonValue@ channels = state.Get("audio");
        audio.Update(channels, 0);
        state.Set("audio", channels);
        return state.Clone();
    }

    bool HasDebugCommand(const String &in commandId)
    {
        return commands !is null && commands.Has(commandId);
    }

    bool RestoreDebugCheckpoint(JsonValue@ snapshot)
    {
        if (state is null || !ValidateSnapshot(snapshot))
        {
            return false;
        }
        JsonValue@ previous = state.Clone();
        if (!audio.Restore(snapshot.Get("audio")))
        {
            audio.Restore(previous.Get("audio"));
            return false;
        }
        @state = snapshot.Clone();
        JsonValue@ checkpoints = state.Get("rollbackCheckpoints");
        rollbackCount = checkpoints.GetCount();
        rollbackLastCommand = rollbackCount > 0 ? checkpoints.At(rollbackCount - 1).Get("currentCommandId").GetString() : "";
        skipEnabled = false;
        autoEnabled = false;
        autoDelay = 0;
        inputBarrier = 0.1f;
        RestorePresentation();
        view.FocusNarrative(PhaseName() == "WaitingChoice");
        return true;
    }

    bool ValidateSnapshot(JsonValue@ snapshot)
    {
        return NovelSnapshotValidation::Validate(snapshot, story, definitions, speakers, audio.paths);
    }

    JsonValue@ VerifyRestoreTwice()
    {
        JsonValue@ result = RuntimeValues::Object();
        JsonValue@ snapshot = CaptureDebugState();
        if (snapshot is null)
        {
            RuntimeValues::PutString(result, "status", "NO_SESSION");
            return result;
        }
        uint objects = menu.gameObject.GetHierarchyObjectCount();
        bool first = RestoreDebugCheckpoint(snapshot);
        bool second = first && RestoreDebugCheckpoint(snapshot);
        bool textRules = VerifyTextRules();
        bool equal = textRules && second && snapshot.Get("variables").ToJson() == state.Get("variables").ToJson() &&
            snapshot.Get("history").ToJson() == state.Get("history").ToJson() &&
            snapshot.Get("callStack").ToJson() == state.Get("callStack").ToJson() &&
            snapshot.Get("presentation").ToJson() == state.Get("presentation").ToJson() &&
            objects == menu.gameObject.GetHierarchyObjectCount();
        RuntimeValues::PutString(result, "status", equal ? "PASSED_IN_THIS_RUN" : "FAILED");
        result.Set("objectsBefore", RuntimeValues::IntValue(objects));
        result.Set("textRules", RuntimeValues::BoolValue(textRules));
        result.Set("objectsAfter", RuntimeValues::IntValue(menu.gameObject.GetHierarchyObjectCount()));
        result.Set("snapshot", snapshot);
        result.Set("after", state);
        RuntimeValues::PutString(result, "audioDiagnostic", audio.diagnostic);
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
        correct = correct && test.plain.graphemeCount() == 2 && test.tokens.GetCount() == 4 &&
            test.tokens.At(1).Get("kind").GetString() == "input" && test.noWait;
        test.Compile("{size=+10}А{size=-5}Б{/size}В{/size}", false);
        float nested = float(test.spans.At(0).Get("relativeSize").GetNumber()) * float(test.spans.At(1).Get("relativeSize").GetNumber());
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
