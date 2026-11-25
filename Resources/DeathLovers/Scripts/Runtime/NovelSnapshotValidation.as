//
// Created by Codex on 17.11.2026.
//

#include "DialogueProgram.as"

namespace NovelSnapshotValidation
{
    bool Nonnegative(double value)
    {
        return value >= 0 && value <= 1.7976931348623157e308;
    }

    bool Target(const String &in id, JsonValueView@ commands)
    {
        return id == "" || commands.Has(id);
    }

    bool Resource(const String &in id, const Map<String, String> &in paths)
    {
        return id == "builtin:black" || id == "hidden" || (paths.contains(id) && !RuntimeValues::Starts(id, "audio/"));
    }

    Value@ ConditionValue(JsonValueView@ node, const Map<String, Value> &in variables, uint depth = 0)
    {
        Value invalid;
        if (depth > 64)
        {
            return invalid;
        }
        String op = node.Get("op").GetString();
        if (op == "literal")
        {
            return RuntimeValues::FromJson(node.Get("value"));
        }
        if (op == "variable")
        {
            String id = node.Get("variableId").GetString();
            if (!variables.contains(id))
            {
                return invalid;
            }
            Value copy;
            copy = variables.at(id);
            return copy;
        }
        bool result = false;
        if (op == "not")
        {
            Value@ value = ConditionValue(node.Get("operand"), variables, depth + 1);
            if (!value.get(result))
            {
                return invalid;
            }
            result = !result;
        }
        else if (op == "and" || op == "or")
        {
            result = op == "and";
            JsonValueView@ operands = node.Get("operands");
            for (uint i = 0; i < operands.GetCount(); ++i)
            {
                Value@ value = ConditionValue(operands.At(i), variables, depth + 1);
                if (!value.get(result))
                {
                    return invalid;
                }
                if (result == (op == "or"))
                {
                    break;
                }
            }
        }
        else
        {
            Value@ left = ConditionValue(node.Get("left"), variables, depth + 1);
            Value@ right = ConditionValue(node.Get("right"), variables, depth + 1);
            if (!RuntimeValues::SameType(left, right))
            {
                return invalid;
            }
            if (op == "eq" || op == "ne")
            {
                bool equal = RuntimeValues::Equal(left, right);
                result = op == "eq" ? equal : !equal;
            }
            else
            {
                int64 a, b;
                if (!left.get(a) || !right.get(b) || (op != "lt" && op != "le" && op != "gt" && op != "ge"))
                {
                    return invalid;
                }
                result = op == "lt" ? a < b : op == "le" ? a <= b : op == "gt" ? a > b : a >= b;
            }
        }
        Value value;
        value.set(result);
        return value;
    }

    bool History(const Vector<NovelHistoryEntry> &in entries, JsonValueView@ commands, const Map<String, NovelSpeaker> &in speakers)
    {
        for (uint i = 0; i < entries.size(); ++i)
        {
            if (!commands.Has(entries[i].commandId) || !speakers.contains(entries[i].speakerId) ||
                commands.Get(entries[i].commandId).Get("type").GetString() != "Say" ||
                commands.Get(entries[i].commandId).Get("speakerId").GetString() != entries[i].speakerId)
            {
                return false;
            }
        }
        return true;
    }

    bool Core(NovelCore@ s, JsonValueView@ story, JsonValueView@ definitions,
        const Map<String, NovelSpeaker> &in speakers, const Map<String, String> &in paths, DialogueProgram@ program)
    {
        JsonValueView@ commands = story.Get("commands");
        if (s is null || s.schemaVersion != 1 || s.contentVersion != story.Get("contentVersion").GetString() ||
            !commands.Has(s.currentCommandId) || !Nonnegative(s.playTimeSeconds) ||
            !Target(s.rollbackBoundaryId, commands))
        {
            return false;
        }
        String phase = s.phase;
        if (s.activeEndingId != "" && (!story.Get("labels").Has(s.activeEndingId) ||
            s.activeEndingId.length() <= 7 || s.activeEndingId.substring(s.activeEndingId.length() - 7, 7) != "_ending"))
        {
            return false;
        }
        if (phase != "Ready" && phase != "WaitingText" && phase != "WaitingChoice" &&
            phase != "WaitingTimer" && phase != "WaitingTransition" && phase != "Finished")
        {
            return false;
        }
        String type = commands.Get(s.currentCommandId).Get("type").GetString();
        if ((phase == "WaitingText" && type != "Say") || (phase == "WaitingChoice" && type != "Choice") ||
            (phase == "WaitingTimer" && type != "Wait") || (phase == "WaitingTransition" && type != "Scene"))
        {
            return false;
        }
        JsonValueView@ registry = story.Get("variables");
        if (s.variables.size() != registry.GetCount() || s.history.size() > 250 || s.callStack.size() > 1000)
        {
            return false;
        }
        for (uint i = 0; i < registry.GetCount(); ++i)
        {
            String key = registry.GetKey(i);
            Value@ initial = RuntimeValues::FromJson(registry.Get(key).Get("initial"));
            if (!s.variables.contains(key) || !initial.hasValue() || !RuntimeValues::SameType(s.variables.at(key), initial))
            {
                return false;
            }
            int64 integer;
            if (s.variables.at(key).get(integer) && (integer < -2147483648 || integer > 2147483647))
            {
                return false;
            }
        }
        for (uint i = 0; i < s.callStack.size(); ++i)
        {
            if (!Target(s.callStack[i], commands))
            {
                return false;
            }
        }
        NovelPresentationState@ p = s.presentation;
        JsonValueView@ current = commands.Get(s.currentCommandId);
        if (phase == "WaitingText" && (p.text != current.Get("normalizedText").GetString() ||
            p.speakerId != current.Get("speakerId").GetString() || p.mode != current.Get("mode").GetString() ||
            p.autoWait != current.Get("autoWait").GetBool()))
        {
            return false;
        }
        if (!Resource(p.background, paths) || (p.mode != "ADV" && p.mode != "NVL") ||
            !speakers.contains(p.speakerId) || !Nonnegative(p.remainingPause) || !Nonnegative(p.effectTime))
        {
            return false;
        }
        program.Compile(p.text, p.autoWait);
        if (p.visibleIndex > program.plain.graphemeCount() || p.tokenIndex > program.tokenCount)
        {
            return false;
        }
        uint expectedVisible = p.tokenIndex == 0 ? 0 : program.tokens[p.tokenIndex - 1].index;
        if (p.visibleIndex != expectedVisible ||
            (p.inputWait && phase == "WaitingText" && (p.tokenIndex == 0 || program.tokens[p.tokenIndex - 1].kind != "input")) ||
            (phase == "WaitingText" && p.fullyShown && (p.tokenIndex != program.tokenCount || p.remainingPause > 0 || p.inputWait)))
        {
            return false;
        }
        NovelTransition@ transition = p.transition;
        if (!Resource(transition.from, paths) || !Resource(transition.target, paths) ||
            !Nonnegative(transition.elapsed) || !Nonnegative(transition.duration) || transition.elapsed > transition.duration ||
            (transition.kind != "none" && transition.kind != "fade" && transition.kind != "dissolve" && transition.kind != "vpunch"))
        {
            return false;
        }
        uint characterCount = 0;
        for (uint i = 0; i < 3; ++i)
        {
            String id = i == 0 ? "ch_p" : i == 1 ? "ch_w" : "ch_h";
            if (!p.characters.contains(id))
            {
                continue;
            }
            ++characterCount;
            const NovelCharacter@ character = p.characters.at(id);
            JsonValueView@ characters = definitions.Get("characters");
            if (!characters.Has(id) || !characters.Get(id).Get("stateResources").Has(character.state) ||
                character.resourceId != characters.Get(id).Get("stateResources").Get(character.state).GetString() ||
                !Resource(character.resourceId, paths) || !Resource(character.previousResource, paths) ||
                !Nonnegative(character.transitionElapsed) || !Nonnegative(character.transitionDuration) ||
                character.transitionElapsed > character.transitionDuration || !Nonnegative(character.bounceElapsed) ||
                character.bounceElapsed > 0.200001 ||
                !(character.position.x >= -3.402823466e38f && character.position.x <= 3.402823466e38f) ||
                !(character.position.y >= -3.402823466e38f && character.position.y <= 3.402823466e38f) ||
                !(character.scale.x >= -3.402823466e38f && character.scale.x <= 3.402823466e38f) ||
                !(character.scale.y >= -3.402823466e38f && character.scale.y <= 3.402823466e38f))
            {
                return false;
            }
        }
        if (p.characters.size() != characterCount || !History(s.history, commands, speakers) ||
            !History(p.nvl, commands, speakers) || p.choices.size() > 8 || (phase == "WaitingChoice" && p.choices.size() == 0))
        {
            return false;
        }
        for (uint i = 0; i < p.choices.size(); ++i)
        {
            const NovelChoice@ option = p.choices[i];
            if (!Target(option.target, commands))
            {
                return false;
            }
        }
        if (phase == "WaitingChoice")
        {
            JsonValueView@ original = current.Get("options");
            uint availableCount = 0;
            for (uint i = 0; i < original.GetCount(); ++i)
            {
                JsonValueView@ source = original.At(i);
                bool available = true;
                if (source.Has("condition"))
                {
                    Value@ condition = ConditionValue(source.Get("condition"), s.variables);
                    if (!condition.get(available))
                    {
                        return false;
                    }
                }
                if (!available)
                {
                    continue;
                }
                if (availableCount >= p.choices.size())
                {
                    return false;
                }
                NovelChoice@ option = p.choices[availableCount++];
                if (option.choiceId != source.Get("choiceId").GetString() ||
                    option.normalizedText != source.Get("normalizedText").GetString() ||
                    option.target != source.Get("target").GetString())
                {
                    return false;
                }
            }
            if (availableCount != p.choices.size())
            {
                return false;
            }
        }
        NovelAudioState@ a = s.audio;
        if (a.voiceIndex > 9 || !Nonnegative(a.voiceCooldown))
        {
            return false;
        }
        for (uint i = 0; i < 3; ++i)
        {
            NovelAudioChannel@ channel = a.Channel(i == 0 ? "Music" : i == 1 ? "Sfx" : "Voice");
            if ((channel.resourceId != "" && (!paths.contains(channel.resourceId) || !RuntimeValues::Starts(channel.resourceId, "audio/"))) ||
                !Nonnegative(channel.position) || !Nonnegative(channel.gain) || !Nonnegative(channel.targetGain) ||
                !Nonnegative(channel.fadeFrom) || !Nonnegative(channel.fadeRemaining) || !Nonnegative(channel.fadeDuration) ||
                channel.fadeRemaining > channel.fadeDuration)
            {
                return false;
            }
        }
        return true;
    }

    bool Validate(NovelState@ snapshot, JsonValueView@ story, JsonValueView@ definitions,
        const Map<String, NovelSpeaker> &in speakers, const Map<String, String> &in paths)
    {
        DialogueProgram program;
        if (snapshot is null || snapshot.rollbackCheckpoints.size() > 100 ||
            !Core(snapshot.core, story, definitions, speakers, paths, program))
        {
            return false;
        }
        for (uint i = 0; i < snapshot.rollbackCheckpoints.size(); ++i)
        {
            NovelCore@ checkpoint = snapshot.rollbackCheckpoints[i];
            if ((checkpoint.phase != "WaitingText" && checkpoint.phase != "WaitingChoice") ||
                checkpoint.rollbackBoundaryId != snapshot.core.rollbackBoundaryId ||
                !Core(checkpoint, story, definitions, speakers, paths, program))
            {
                return false;
            }
        }
        return true;
    }
}
