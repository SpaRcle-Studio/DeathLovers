//
// Created by Codex on 17.11.2026.
//

namespace NovelSnapshotValidation
{
    bool Kind(JsonValue@ value, const String &in key, JsonValueKind kind)
    {
        return value.Has(key) && value.Get(key).GetKind() == kind;
    }

    bool Number(JsonValue@ value, const String &in key)
    {
        return value.Has(key) && (value.Get(key).GetKind() == JsonValueKind::Number || value.Get(key).GetKind() == JsonValueKind::Integer) && value.Get(key).GetNumber() >= 0;
    }

    bool Target(JsonValue@ target, JsonValue@ commands)
    {
        return target.GetKind() == JsonValueKind::Null || (target.GetKind() == JsonValueKind::String && commands.Has(target.GetString()));
    }

    bool Resource(const String &in id, JsonValue@ paths)
    {
        return id == "builtin:black" || id == "hidden" || paths.Has(id);
    }

    bool Validate(JsonValue@ s, JsonValue@ story, JsonValue@ definitions, JsonValue@ speakers, JsonValue@ paths)
    {
        JsonValue@ commands = story.Get("commands");
        if (s is null || !s.IsValid() || s.GetKind() != JsonValueKind::Object || !Kind(s, "schemaVersion", JsonValueKind::Integer) || s.Get("schemaVersion").GetInt() != 1 ||
            !Kind(s, "contentVersion", JsonValueKind::String) || s.Get("contentVersion").GetString() != story.Get("contentVersion").GetString() ||
            !Kind(s, "currentCommandId", JsonValueKind::String) || !commands.Has(s.Get("currentCommandId").GetString()) ||
            !Kind(s, "phase", JsonValueKind::String) || !Kind(s, "variables", JsonValueKind::Object) || !Kind(s, "callStack", JsonValueKind::Array) ||
            !Kind(s, "presentation", JsonValueKind::Object) || !Kind(s, "audio", JsonValueKind::Object) || !Kind(s, "history", JsonValueKind::Array) ||
            !Kind(s, "rollbackCheckpoints", JsonValueKind::Array) || !Kind(s, "rollbackBoundaryId", JsonValueKind::String) ||
            !Kind(s, "activeEndingId", JsonValueKind::String) || !Kind(s, "diagnostic", JsonValueKind::String) || !Number(s, "playTimeSeconds"))
        {
            return false;
        }
        String phase = s.Get("phase").GetString();
        if (phase != "Ready" && phase != "WaitingText" && phase != "WaitingChoice" && phase != "WaitingTimer" && phase != "WaitingTransition" && phase != "Finished")
        {
            return false;
        }
        String type = commands.Get(s.Get("currentCommandId").GetString()).Get("type").GetString();
        if ((phase == "WaitingText" && type != "Say") || (phase == "WaitingChoice" && type != "Choice") ||
            (phase == "WaitingTimer" && type != "Wait") || (phase == "WaitingTransition" && type != "Scene"))
        {
            return false;
        }
        JsonValue@ registry = story.Get("variables");
        JsonValue@ variables = s.Get("variables");
        if (variables.GetCount() != registry.GetCount() || s.Get("history").GetCount() > 250 ||
            s.Get("rollbackCheckpoints").GetCount() > 100 || s.Get("callStack").GetCount() > 1000)
        {
            return false;
        }
        for (uint i = 0; i < registry.GetCount(); ++i)
        {
            String key = registry.GetKey(i);
            if (!variables.Has(key) || variables.Get(key).GetKind() != registry.Get(key).Get("initial").GetKind())
            {
                return false;
            }
            if (variables.Get(key).GetKind() == JsonValueKind::Integer && (variables.Get(key).GetInt() < -2147483648 || variables.Get(key).GetInt() > 2147483647))
            {
                return false;
            }
        }
        for (uint i = 0; i < s.Get("callStack").GetCount(); ++i)
        {
            if (!Target(s.Get("callStack").At(i), commands))
            {
                return false;
            }
        }
        JsonValue@ p = s.Get("presentation");
        if (!Kind(p, "background", JsonValueKind::String) || !Resource(p.Get("background").GetString(), paths) ||
            !Kind(p, "mode", JsonValueKind::String) || (p.Get("mode").GetString() != "ADV" && p.Get("mode").GetString() != "NVL") ||
            !Kind(p, "speakerId", JsonValueKind::String) || !speakers.Has(p.Get("speakerId").GetString()) ||
            !Kind(p, "text", JsonValueKind::String) || !Kind(p, "autoWait", JsonValueKind::Boolean) ||
            !Kind(p, "visibleIndex", JsonValueKind::Integer) || !Kind(p, "tokenIndex", JsonValueKind::Integer) ||
            !Number(p, "remainingPause") || !Number(p, "effectTime") || !Kind(p, "inputWait", JsonValueKind::Boolean) ||
            !Kind(p, "fullyShown", JsonValueKind::Boolean) || !Kind(p, "dialogueVisible", JsonValueKind::Boolean) ||
            !Kind(p, "choices", JsonValueKind::Array) || !Kind(p, "nvl", JsonValueKind::Array) || !Kind(p, "characters", JsonValueKind::Object) ||
            !Kind(p, "transition", JsonValueKind::Object))
        {
            return false;
        }
        DialogueProgram program;
        program.Compile(p.Get("text").GetString(), p.Get("autoWait").GetBool());
        if (p.Get("visibleIndex").GetInt() < 0 || uint64(p.Get("visibleIndex").GetInt()) > program.plain.graphemeCount() ||
            p.Get("tokenIndex").GetInt() < 0 || uint64(p.Get("tokenIndex").GetInt()) > program.tokens.GetCount())
        {
            return false;
        }
        uint tokenIndex = uint(p.Get("tokenIndex").GetInt());
        int64 expectedVisible = tokenIndex == 0 ? 0 : program.tokens.At(tokenIndex - 1).Get("index").GetInt();
        if (p.Get("visibleIndex").GetInt() != expectedVisible ||
            (p.Get("inputWait").GetBool() && phase == "WaitingText" && (tokenIndex == 0 || program.tokens.At(tokenIndex - 1).Get("kind").GetString() != "input")) ||
            (phase == "WaitingText" && p.Get("fullyShown").GetBool() && (tokenIndex != program.tokens.GetCount() || p.Get("remainingPause").GetNumber() > 0 || p.Get("inputWait").GetBool())))
        {
            return false;
        }
        JsonValue@ transition = p.Get("transition");
        if (!Kind(transition, "kind", JsonValueKind::String) || !Kind(transition, "from", JsonValueKind::String) ||
            !Kind(transition, "target", JsonValueKind::String) || !Resource(transition.Get("from").GetString(), paths) ||
            !Resource(transition.Get("target").GetString(), paths) || !Number(transition, "elapsed") || !Number(transition, "duration") ||
            transition.Get("elapsed").GetNumber() > transition.Get("duration").GetNumber())
        {
            return false;
        }
        String transitionKind = transition.Get("kind").GetString();
        if (transitionKind != "none" && transitionKind != "fade" && transitionKind != "dissolve" && transitionKind != "vpunch")
        {
            return false;
        }
        for (uint i = 0; i < p.Get("characters").GetCount(); ++i)
        {
            String id = p.Get("characters").GetKey(i);
            JsonValue@ character = p.Get("characters").Get(id);
            if ((id != "ch_p" && id != "ch_w" && id != "ch_h") || !definitions.Get("characters").Has(id) || !Kind(character, "state", JsonValueKind::String) ||
                !definitions.Get("characters").Get(id).Get("stateResources").Has(character.Get("state").GetString()) ||
                !Kind(character, "resourceId", JsonValueKind::String) || !Resource(character.Get("resourceId").GetString(), paths) ||
                !Kind(character, "previousResource", JsonValueKind::String) || !Resource(character.Get("previousResource").GetString(), paths) ||
                !Number(character, "transitionElapsed") || !Number(character, "transitionDuration") || !Number(character, "bounceElapsed") ||
                !Kind(character, "bounceActive", JsonValueKind::Boolean) || !Kind(character, "position", JsonValueKind::Array) ||
                !Kind(character, "scale", JsonValueKind::Array) || !Kind(character, "flip", JsonValueKind::Array) ||
                character.Get("position").GetCount() != 2 || character.Get("scale").GetCount() != 2 || character.Get("flip").GetCount() != 2)
            {
                return false;
            }
            if (character.Get("resourceId").GetString() != definitions.Get("characters").Get(id).Get("stateResources").Get(character.Get("state").GetString()).GetString() ||
                character.Get("transitionElapsed").GetNumber() > character.Get("transitionDuration").GetNumber() || character.Get("bounceElapsed").GetNumber() > 0.200001)
            {
                return false;
            }
            for (uint axis = 0; axis < 2; ++axis)
            {
                JsonValueKind positionKind = character.Get("position").At(axis).GetKind();
                JsonValueKind scaleKind = character.Get("scale").At(axis).GetKind();
                if ((positionKind != JsonValueKind::Integer && positionKind != JsonValueKind::Number) ||
                    (scaleKind != JsonValueKind::Integer && scaleKind != JsonValueKind::Number) || character.Get("flip").At(axis).GetKind() != JsonValueKind::Boolean)
                {
                    return false;
                }
            }
        }
        for (uint i = 0; i < s.Get("history").GetCount(); ++i)
        {
            JsonValue@ entry = s.Get("history").At(i);
            if (!Kind(entry, "commandId", JsonValueKind::String) || !commands.Has(entry.Get("commandId").GetString()) ||
                !Kind(entry, "text", JsonValueKind::String) || !Kind(entry, "speakerId", JsonValueKind::String) || !speakers.Has(entry.Get("speakerId").GetString()))
            {
                return false;
            }
        }
        for (uint i = 0; i < p.Get("nvl").GetCount(); ++i)
        {
            if (!Kind(p.Get("nvl").At(i), "text", JsonValueKind::String))
            {
                return false;
            }
        }
        if (p.Get("choices").GetCount() > 8 || (phase == "WaitingChoice" && p.Get("choices").GetCount() == 0))
        {
            return false;
        }
        for (uint i = 0; i < p.Get("choices").GetCount(); ++i)
        {
            JsonValue@ option = p.Get("choices").At(i);
            if (!Kind(option, "choiceId", JsonValueKind::String) || !Kind(option, "normalizedText", JsonValueKind::String) ||
                !option.Has("target") || !Target(option.Get("target"), commands))
            {
                return false;
            }
            if (phase == "WaitingChoice")
            {
                JsonValue@ original = commands.Get(s.Get("currentCommandId").GetString()).Get("options");
                bool found = false;
                for (uint j = 0; j < original.GetCount(); ++j)
                {
                    if (original.At(j).ToJson() == option.ToJson())
                    {
                        found = true;
                        break;
                    }
                }
                if (!found)
                {
                    return false;
                }
            }
        }
        JsonValue@ a = s.Get("audio");
        if (!Kind(a, "voiceIndex", JsonValueKind::Integer) || a.Get("voiceIndex").GetInt() < 0 || a.Get("voiceIndex").GetInt() > 9 || !Number(a, "voiceCooldown"))
        {
            return false;
        }
        for (uint i = 0; i < 3; ++i)
        {
            String bus = i == 0 ? "Music" : i == 1 ? "Sfx" : "Voice";
            if (!Kind(a, bus, JsonValueKind::Object))
            {
                return false;
            }
            JsonValue@ channel = a.Get(bus);
            if (!Kind(channel, "resourceId", JsonValueKind::String) ||
                (channel.Get("resourceId").GetString() != "" && !paths.Has(channel.Get("resourceId").GetString())) ||
                !Kind(channel, "loop", JsonValueKind::Boolean) || !Kind(channel, "completed", JsonValueKind::Boolean) ||
                !Kind(channel, "stopAfterFade", JsonValueKind::Boolean) || !Number(channel, "position") || !Number(channel, "gain") ||
                !Number(channel, "targetGain") || !Number(channel, "fadeFrom") || !Number(channel, "fadeRemaining") || !Number(channel, "fadeDuration") ||
                channel.Get("fadeRemaining").GetNumber() > channel.Get("fadeDuration").GetNumber())
            {
                return false;
            }
        }
        return true;
    }
}
