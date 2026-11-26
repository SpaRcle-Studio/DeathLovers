//
// Created by Codex on 26.11.2026.
//

#include "NovelSnapshotValidation.as"
#include "../UI/MenuProfile.as"

// Disk data is independent of script reflection and the in-memory rollback cache.
namespace NovelSaveFormat
{
    const uint Version = 2;

    void Text(JsonValue@ object, const String &in key, const String &in text)
    {
        JsonValue value;
        value.SetString(text);
        object.Set(key, value);
    }

    void Number(JsonValue@ object, const String &in key, double number)
    {
        JsonValue value;
        value.SetNumber(number);
        object.Set(key, value);
    }

    void Integer(JsonValue@ object, const String &in key, int64 number)
    {
        JsonValue value;
        value.SetInt(number);
        object.Set(key, value);
    }

    void Boolean(JsonValue@ object, const String &in key, bool boolean)
    {
        JsonValue value;
        value.SetBool(boolean);
        object.Set(key, value);
    }

    JsonValue@ Strings(const Vector<String> &in items)
    {
        JsonValue result;
        result.MakeArray();
        for (uint i = 0; i < items.size(); ++i)
        {
            JsonValue item;
            item.SetString(items[i]);
            result.Append(item);
        }
        return result;
    }

    bool ReadStrings(JsonValueView@ source, Vector<String> &out items, uint limit)
    {
        if (source.GetKind() != JsonValueKind::Array || source.GetCount() > limit) return false;
        for (uint i = 0; i < source.GetCount(); ++i)
        {
            if (source.At(i).GetKind() != JsonValueKind::String) return false;
            items.pushBack(source.At(i).GetString());
        }
        return true;
    }

    JsonValue@ History(const Vector<NovelHistoryEntry> &in entries)
    {
        Vector<String> ids;
        for (uint i = 0; i < entries.size(); ++i) ids.pushBack(entries[i].commandId);
        return Strings(ids);
    }

    bool ReadHistory(JsonValueView@ source, JsonValueView@ commands, Vector<NovelHistoryEntry> &out entries)
    {
        Vector<String> ids;
        if (!ReadStrings(source, ids, 250)) return false;
        DialogueProgram program;
        for (uint i = 0; i < ids.size(); ++i)
        {
            JsonValueView@ command = commands.Get(ids[i]);
            if (command.Get("type").GetString() != "Say") return false;
            NovelHistoryEntry entry;
            entry.commandId = ids[i];
            entry.speakerId = command.Get("speakerId").GetString();
            entry.text = command.Get("normalizedText").GetString();
            if (command.Get("autoWait").GetBool()) entry.text = program.AutoWaits(entry.text);
            entries.pushBack(entry);
        }
        return true;
    }

    JsonValue@ Primitive(Value@ source)
    {
        JsonValue value;
        bool boolean;
        int64 integer;
        String text;
        if (source.get(boolean)) value.SetBool(boolean);
        else if (source.get(integer)) value.SetInt(integer);
        else if (source.get(text)) value.SetString(text);
        return value;
    }

    JsonValue@ Audio(NovelAudioChannel@ channel)
    {
        JsonValue result;
        result.MakeObject();
        Text(result, "resource", channel.resourceId);
        Boolean(result, "loop", channel.loop);
        Number(result, "position", channel.position);
        Number(result, "gain", channel.gain);
        if (channel.fadeRemaining > 0)
        {
            JsonValue fade;
            fade.MakeObject();
            Number(fade, "from", channel.fadeFrom);
            Number(fade, "to", channel.targetGain);
            Number(fade, "remaining", channel.fadeRemaining);
            Number(fade, "duration", channel.fadeDuration);
            Boolean(fade, "stop", channel.stopAfterFade);
            result.Set("fade", fade);
        }
        return result;
    }

    void ReadAudio(JsonValueView@ source, NovelAudioChannel@ channel)
    {
        channel.resourceId = source.Get("resource").GetString();
        channel.completed = false;
        channel.loop = source.Get("loop").GetBool();
        channel.position = float(source.Get("position").GetNumber());
        channel.gain = float(source.Get("gain").GetNumber());
        channel.targetGain = channel.gain;
        if (source.Has("fade"))
        {
            JsonValueView@ fade = source.Get("fade");
            channel.fadeFrom = float(fade.Get("from").GetNumber());
            channel.targetGain = float(fade.Get("to").GetNumber());
            channel.fadeRemaining = float(fade.Get("remaining").GetNumber());
            channel.fadeDuration = float(fade.Get("duration").GetNumber());
            channel.stopAfterFade = fade.Get("stop").GetBool();
        }
    }

    JsonValue@ State(NovelCore@ core, JsonValueView@ story)
    {
        JsonValue result;
        result.MakeObject();
        Integer(result, "schemaVersion", Version);
        Text(result, "contentVersion", core.contentVersion);
        Text(result, "command", core.currentCommandId);
        Text(result, "phase", core.phase);
        Number(result, "playTimeSeconds", core.playTimeSeconds);
        result.Set("callStack", Strings(core.callStack));
        Text(result, "ending", core.activeEndingId);
        JsonValue variables;
        variables.MakeObject();
        JsonValueView@ registry = story.Get("variables");
        for (uint i = 0; i < registry.GetCount(); ++i)
        {
            String id = registry.GetKey(i);
            Value@ initial = RuntimeValues::FromJson(registry.Get(id).Get("initial"));
            if (!RuntimeValues::Equal(core.variables.at(id), initial)) variables.Set(id, Primitive(core.variables.at(id)));
        }
        result.Set("variables", variables);
        result.Set("history", History(core.history));

        NovelPresentationState@ p = core.presentation;
        JsonValue screen;
        screen.MakeObject();
        Text(screen, "background", p.background);
        Boolean(screen, "dialogueVisible", p.dialogueVisible);
        // The last Say remains the displayed dialogue through choices, waits and transitions.
        Text(screen, "dialogue", core.history.size() > 0 ? core.history[core.history.size() - 1].commandId : "");
        Integer(screen, "token", p.tokenIndex);
        Number(screen, "pause", p.remainingPause);
        Boolean(screen, "inputWait", p.inputWait);
        Boolean(screen, "fullyShown", p.fullyShown);
        Number(screen, "effectTime", p.effectTime);
        screen.Set("nvl", History(p.nvl));
        if (p.transition.elapsed < p.transition.duration)
        {
            JsonValue transition;
            transition.MakeObject();
            Text(transition, "kind", p.transition.kind);
            Text(transition, "from", p.transition.from);
            Number(transition, "elapsed", p.transition.elapsed);
            Number(transition, "duration", p.transition.duration);
            screen.Set("transition", transition);
        }
        JsonValue characters;
        characters.MakeObject();
        for (uint i = 0; i < 3; ++i)
        {
            String id = i == 0 ? "ch_p" : i == 1 ? "ch_w" : "ch_h";
            if (!p.characters.contains(id)) continue;
            const NovelCharacter@ character = p.characters.at(id);
            JsonValue saved;
            saved.MakeObject();
            Text(saved, "state", character.state);
            if (character.transitionElapsed < character.transitionDuration)
            {
                Text(saved, "from", character.previousResource);
                Number(saved, "elapsed", character.transitionElapsed);
                Number(saved, "duration", character.transitionDuration);
            }
            if (character.bounceActive) Number(saved, "bounce", character.bounceElapsed);
            characters.Set(id, saved);
        }
        screen.Set("characters", characters);
        result.Set("screen", screen);
        JsonValue audio;
        audio.MakeObject();
        for (uint i = 0; i < 3; ++i)
        {
            String bus = i == 0 ? "Music" : i == 1 ? "Sfx" : "Voice";
            NovelAudioChannel@ channel = core.audio.Channel(bus);
            if (!channel.completed && channel.resourceId != "") audio.Set(bus, Audio(channel));
        }
        result.Set("audio", audio);
        return result;
    }

    bool ReadState(JsonValueView@ source, JsonValueView@ story, JsonValueView@ definitions, NovelState@ result)
    {
        if (source.Get("schemaVersion").GetKind() != JsonValueKind::Integer ||
            source.Get("schemaVersion").GetInt() != int64(Version)) return false;
        NovelState decoded;
        NovelCore@ core = decoded.core;
        core.schemaVersion = 1; // Runtime invariant, independent of the disk format version.
        core.contentVersion = source.Get("contentVersion").GetString();
        core.currentCommandId = source.Get("command").GetString();
        core.phase = source.Get("phase").GetString();
        core.playTimeSeconds = source.Get("playTimeSeconds").GetNumber();
        core.activeEndingId = source.Get("ending").GetString();
        if (!ReadStrings(source.Get("callStack"), core.callStack, 1000)) return false;
        JsonValueView@ registry = story.Get("variables");
        JsonValueView@ variables = source.Get("variables");
        if (variables.GetKind() != JsonValueKind::Object) return false;
        for (uint i = 0; i < variables.GetCount(); ++i)
            if (!registry.Has(variables.GetKey(i))) return false;
        for (uint i = 0; i < registry.GetCount(); ++i)
        {
            String id = registry.GetKey(i);
            Value@ initial = RuntimeValues::FromJson(registry.Get(id).Get("initial"));
            Value@ value = variables.Has(id) ? RuntimeValues::FromJson(variables.Get(id)) : initial;
            if (!RuntimeValues::SameType(initial, value)) return false;
            core.variables.set(id, value);
        }
        JsonValueView@ commands = story.Get("commands");
        if (!ReadHistory(source.Get("history"), commands, core.history)) return false;
        JsonValueView@ screen = source.Get("screen");
        NovelPresentationState@ p = core.presentation;
        p.background = screen.Get("background").GetString();
        p.dialogueVisible = screen.Get("dialogueVisible").GetBool();
        String dialogue = screen.Get("dialogue").GetString();
        DialogueProgram program;
        if (dialogue != "")
        {
            JsonValueView@ command = commands.Get(dialogue);
            if (command.Get("type").GetString() != "Say") return false;
            p.text = command.Get("normalizedText").GetString();
            p.speakerId = command.Get("speakerId").GetString();
            p.mode = command.Get("mode").GetString();
            p.autoWait = command.Get("autoWait").GetBool();
        }
        program.Compile(p.text, p.autoWait);
        int64 token = screen.Get("token").GetInt();
        if (token < 0 || token > int64(program.tokenCount)) return false;
        p.tokenIndex = uint(token);
        p.visibleIndex = token == 0 ? 0 : program.tokens[uint(token) - 1].index;
        p.remainingPause = float(screen.Get("pause").GetNumber());
        p.inputWait = screen.Get("inputWait").GetBool();
        p.fullyShown = screen.Get("fullyShown").GetBool();
        p.effectTime = float(screen.Get("effectTime").GetNumber());
        if (!ReadHistory(screen.Get("nvl"), commands, p.nvl)) return false;
        if (core.phase == "WaitingChoice")
        {
            JsonValueView@ options = commands.Get(core.currentCommandId).Get("options");
            for (uint i = 0; i < options.GetCount(); ++i)
            {
                JsonValueView@ option = options.At(i);
                bool available = true;
                if (option.Has("condition"))
                {
                    Value@ condition = NovelSnapshotValidation::ConditionValue(option.Get("condition"), core.variables);
                    if (!condition.get(available)) return false;
                }
                if (!available) continue;
                NovelChoice choice;
                choice.choiceId = option.Get("choiceId").GetString();
                choice.normalizedText = option.Get("normalizedText").GetString();
                choice.target = option.Get("target").GetString();
                p.choices.pushBack(choice);
            }
        }
        p.transition.from = p.background;
        p.transition.target = p.background;
        if (screen.Has("transition"))
        {
            JsonValueView@ transition = screen.Get("transition");
            p.transition.kind = transition.Get("kind").GetString();
            p.transition.from = transition.Get("from").GetString();
            p.transition.elapsed = float(transition.Get("elapsed").GetNumber());
            p.transition.duration = float(transition.Get("duration").GetNumber());
        }
        JsonValueView@ characters = screen.Get("characters");
        if (characters.GetKind() != JsonValueKind::Object || characters.GetCount() > 3) return false;
        for (uint i = 0; i < characters.GetCount(); ++i)
        {
            String id = characters.GetKey(i);
            JsonValueView@ definition = definitions.Get("characters").Get(id);
            JsonValueView@ saved = characters.Get(id);
            NovelCharacter character;
            character.state = saved.Get("state").GetString();
            if (!definition.Get("stateResources").Has(character.state)) return false;
            character.resourceId = definition.Get("stateResources").Get(character.state).GetString();
            character.previousResource = character.resourceId;
            character.position.x = float(definition.Get("position").At(0).GetNumber());
            character.position.y = float(definition.Get("position").At(1).GetNumber());
            character.scale.x = float(definition.Get("scale").At(0).GetNumber());
            character.scale.y = float(definition.Get("scale").At(1).GetNumber());
            character.flipX = definition.Get("flip").At(0).GetBool();
            character.flipY = definition.Get("flip").At(1).GetBool();
            if (saved.Has("from"))
            {
                character.previousResource = saved.Get("from").GetString();
                character.transitionElapsed = float(saved.Get("elapsed").GetNumber());
                character.transitionDuration = float(saved.Get("duration").GetNumber());
            }
            if (saved.Has("bounce"))
            {
                character.animation = RuntimeValues::Text(definition, "animation");
                character.bounceActive = character.animation == "single_bounce_animation";
                character.bounceElapsed = float(saved.Get("bounce").GetNumber());
                if (!character.bounceActive) return false;
            }
            p.characters.set(id, character);
        }
        JsonValueView@ audio = source.Get("audio");
        if (audio.GetKind() != JsonValueKind::Object || audio.GetCount() > 3) return false;
        for (uint i = 0; i < audio.GetCount(); ++i)
        {
            NovelAudioChannel@ channel = core.audio.Channel(audio.GetKey(i));
            if (channel is null) return false;
            ReadAudio(audio.Get(audio.GetKey(i)), channel);
        }
        // Strict shape/types: missing, unknown or lossy fields cannot silently become defaults.
        JsonValue@ canonical = State(core, story);
        if (!source.Equals(canonical.View())) return false;
        result = decoded;
        return true;
    }

    JsonValue@ Profile(MenuProfile@ profile)
    {
        JsonValue result;
        result.MakeObject();
        Integer(result, "schemaVersion", Version);
        Boolean(result, "firstRun", profile.firstRun);
        result.Set("readCommandIds", Strings(profile.readCommandIds));
        JsonValue settings;
        settings.MakeObject();
        MenuSettings@ s = profile.settings;
        Number(settings, "music_volume", s.music_volume);
        Number(settings, "sfx_volume", s.sfx_volume);
        Number(settings, "voice_volume", s.voice_volume);
        Number(settings, "text_cps", s.text_cps);
        Number(settings, "afm_time", s.afm_time);
        Boolean(settings, "pixel_voice", s.pixel_voice);
        Boolean(settings, "mute", s.mute);
        Boolean(settings, "fullscreen", s.fullscreen);
        Boolean(settings, "skip_unseen", s.skip_unseen);
        Boolean(settings, "skip_after_choices", s.skip_after_choices);
        Boolean(settings, "skip_transitions", s.skip_transitions);
        result.Set("settings", settings);
        return result;
    }

    bool ReadProfile(JsonValueView@ source, MenuProfile@ result)
    {
        if (source.Get("schemaVersion").GetInt() != int64(Version)) return false;
        MenuProfile decoded;
        decoded.firstRun = source.Get("firstRun").GetBool();
        if (!ReadStrings(source.Get("readCommandIds"), decoded.readCommandIds, 100000)) return false;
        JsonValueView@ settings = source.Get("settings");
        MenuSettings@ s = decoded.settings;
        s.music_volume = float(settings.Get("music_volume").GetNumber());
        s.sfx_volume = float(settings.Get("sfx_volume").GetNumber());
        s.voice_volume = float(settings.Get("voice_volume").GetNumber());
        s.text_cps = float(settings.Get("text_cps").GetNumber());
        s.afm_time = float(settings.Get("afm_time").GetNumber());
        s.pixel_voice = settings.Get("pixel_voice").GetBool();
        s.mute = settings.Get("mute").GetBool();
        s.fullscreen = settings.Get("fullscreen").GetBool();
        s.skip_unseen = settings.Get("skip_unseen").GetBool();
        s.skip_after_choices = settings.Get("skip_after_choices").GetBool();
        s.skip_transitions = settings.Get("skip_transitions").GetBool();
        JsonValue@ canonical = Profile(decoded);
        if (!source.Equals(canonical.View())) return false;
        result = decoded;
        return true;
    }
}
