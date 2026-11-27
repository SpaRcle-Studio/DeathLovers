//
// Created by Codex on 26.11.2026.
//

#include "NovelSnapshotValidation.as"
#include "../UI/MenuProfile.as"

// Disk data is independent of the in-memory rollback cache.
// Version 3: the story position is the stack of story frames (StoryFrame), variables are Story::StoryVars.
namespace NovelSaveFormat
{
    const uint Version = 3;

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

    JsonValue@ Variables(const Story::StoryVars &in vars)
    {
        JsonValue result;
        if (!result.Parse(SerializeScriptValue(vars)))
        {
            result.MakeObject();
        }
        return result;
    }

    bool ReadVariables(JsonValueView@ source, Story::StoryVars &out vars)
    {
        return source.GetKind() == JsonValueKind::Object && DeserializeScriptValue(source.ToJson(), vars);
    }

    JsonValue@ Frames(const Vector<StoryFrame> &in frames)
    {
        JsonValue result;
        result.MakeArray();
        for (uint i = 0; i < frames.size(); ++i)
        {
            const StoryFrame@ frame = frames[i];
            JsonValue saved;
            saved.MakeObject();
            Text(saved, "label", frame.label);
            saved.Set("entry", Variables(frame.entry));
            Integer(saved, "step", frame.step);
            JsonValue picks;
            picks.MakeArray();
            for (uint j = 0; j < frame.picks.size(); ++j)
            {
                JsonValue pick;
                pick.SetInt(frame.picks[j]);
                picks.Append(pick);
            }
            saved.Set("picks", picks);
            JsonValue calls;
            calls.MakeArray();
            for (uint j = 0; j < frame.afterCall.size(); ++j)
            {
                calls.Append(Variables(frame.afterCall[j]));
            }
            saved.Set("afterCall", calls);
            result.Append(saved);
        }
        return result;
    }

    bool ReadFrames(JsonValueView@ source, Vector<StoryFrame> &out frames)
    {
        if (source.GetKind() != JsonValueKind::Array || source.GetCount() > 1000) return false;
        frames.resize(source.GetCount());
        for (uint i = 0; i < source.GetCount(); ++i)
        {
            JsonValueView@ saved = source.At(i);
            StoryFrame@ frame = frames[i];
            JsonValueView@ picks = saved.Get("picks");
            JsonValueView@ calls = saved.Get("afterCall");
            if (saved.Get("label").GetKind() != JsonValueKind::String || saved.Get("step").GetKind() != JsonValueKind::Integer ||
                saved.Get("step").GetInt() < 0 || saved.Get("step").GetInt() > 100000000 ||
                picks.GetKind() != JsonValueKind::Array || calls.GetKind() != JsonValueKind::Array ||
                !ReadVariables(saved.Get("entry"), frame.entry)) return false;
            frame.label = saved.Get("label").GetString();
            frame.step = uint(saved.Get("step").GetInt());
            for (uint j = 0; j < picks.GetCount(); ++j)
            {
                if (picks.At(j).GetKind() != JsonValueKind::Integer || picks.At(j).GetInt() < 0 || picks.At(j).GetInt() >= 64) return false;
                frame.picks.pushBack(uint(picks.At(j).GetInt()));
            }
            frame.afterCall.resize(calls.GetCount());
            for (uint j = 0; j < calls.GetCount(); ++j)
            {
                if (!ReadVariables(calls.At(j), frame.afterCall[j])) return false;
            }
        }
        return true;
    }

    JsonValue@ Lines(const Vector<NovelHistoryEntry> &in entries)
    {
        JsonValue result;
        result.MakeArray();
        for (uint i = 0; i < entries.size(); ++i)
        {
            JsonValue item;
            item.MakeArray();
            JsonValue value;
            value.SetString(entries[i].lineId);
            item.Append(value);
            value.SetString(entries[i].speakerId);
            item.Append(value);
            value.SetString(entries[i].text);
            item.Append(value);
            result.Append(item);
        }
        return result;
    }

    bool ReadLines(JsonValueView@ source, Vector<NovelHistoryEntry> &out entries)
    {
        if (source.GetKind() != JsonValueKind::Array || source.GetCount() > 250) return false;
        for (uint i = 0; i < source.GetCount(); ++i)
        {
            JsonValueView@ item = source.At(i);
            if (item.GetKind() != JsonValueKind::Array || item.GetCount() != 3) return false;
            for (uint j = 0; j < 3; ++j)
            {
                if (item.At(j).GetKind() != JsonValueKind::String) return false;
            }
            NovelHistoryEntry entry;
            entry.lineId = item.At(0).GetString();
            entry.speakerId = item.At(1).GetString();
            entry.text = item.At(2).GetString();
            entries.pushBack(entry);
        }
        return true;
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

    JsonValue@ State(NovelCore@ core)
    {
        JsonValue result;
        result.MakeObject();
        Integer(result, "schemaVersion", Version);
        Text(result, "contentVersion", core.contentVersion);
        Text(result, "phase", core.phase);
        Text(result, "position", core.position);
        Number(result, "playTimeSeconds", core.playTimeSeconds);
        Text(result, "ending", core.activeEndingId);
        result.Set("variables", Variables(core.vars));
        result.Set("frames", Frames(core.frames));
        result.Set("history", Lines(core.history));

        NovelPresentationState@ p = core.presentation;
        JsonValue screen;
        screen.MakeObject();
        Text(screen, "background", p.background);
        Boolean(screen, "dialogueVisible", p.dialogueVisible);
        // The last line remains the displayed dialogue through choices, waits and transitions.
        JsonValue dialogue;
        dialogue.MakeObject();
        Text(dialogue, "speaker", p.speakerId);
        Text(dialogue, "mode", p.mode);
        Text(dialogue, "text", p.text);
        Boolean(dialogue, "autoWait", p.autoWait);
        screen.Set("dialogue", dialogue);
        Integer(screen, "token", p.tokenIndex);
        Number(screen, "pause", p.remainingPause);
        Boolean(screen, "inputWait", p.inputWait);
        Boolean(screen, "fullyShown", p.fullyShown);
        Number(screen, "effectTime", p.effectTime);
        screen.Set("nvl", Lines(p.nvl));
        JsonValue choices;
        choices.MakeArray();
        for (uint i = 0; i < p.choices.size(); ++i)
        {
            JsonValue choice;
            choice.MakeObject();
            Integer(choice, "index", p.choices[i].index);
            Text(choice, "text", p.choices[i].text);
            choices.Append(choice);
        }
        screen.Set("choices", choices);
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

    bool ReadState(JsonValueView@ source, JsonValueView@ definitions, NovelState@ result)
    {
        if (source.Get("schemaVersion").GetKind() != JsonValueKind::Integer ||
            source.Get("schemaVersion").GetInt() != int64(Version)) return false;
        NovelState decoded;
        NovelCore@ core = decoded.core;
        core.schemaVersion = 1; // Runtime invariant, independent of the disk format version.
        core.contentVersion = source.Get("contentVersion").GetString();
        core.phase = source.Get("phase").GetString();
        core.position = source.Get("position").GetString();
        core.playTimeSeconds = source.Get("playTimeSeconds").GetNumber();
        core.activeEndingId = source.Get("ending").GetString();
        if (!ReadVariables(source.Get("variables"), core.vars) ||
            !ReadFrames(source.Get("frames"), core.frames) ||
            !ReadLines(source.Get("history"), core.history)) return false;
        JsonValueView@ screen = source.Get("screen");
        NovelPresentationState@ p = core.presentation;
        p.background = screen.Get("background").GetString();
        p.dialogueVisible = screen.Get("dialogueVisible").GetBool();
        JsonValueView@ dialogue = screen.Get("dialogue");
        p.speakerId = dialogue.Get("speaker").GetString();
        p.mode = dialogue.Get("mode").GetString();
        p.text = dialogue.Get("text").GetString();
        p.autoWait = dialogue.Get("autoWait").GetBool();
        DialogueProgram program;
        program.Compile(p.text, p.autoWait);
        int64 token = screen.Get("token").GetInt();
        if (token < 0 || token > int64(program.tokenCount)) return false;
        p.tokenIndex = uint(token);
        p.visibleIndex = token == 0 ? 0 : program.tokens[uint(token) - 1].index;
        p.remainingPause = float(screen.Get("pause").GetNumber());
        p.inputWait = screen.Get("inputWait").GetBool();
        p.fullyShown = screen.Get("fullyShown").GetBool();
        p.effectTime = float(screen.Get("effectTime").GetNumber());
        if (!ReadLines(screen.Get("nvl"), p.nvl)) return false;
        JsonValueView@ choices = screen.Get("choices");
        if (choices.GetKind() != JsonValueKind::Array || choices.GetCount() > 8) return false;
        for (uint i = 0; i < choices.GetCount(); ++i)
        {
            JsonValueView@ option = choices.At(i);
            if (option.Get("index").GetKind() != JsonValueKind::Integer || option.Get("index").GetInt() < 0 ||
                option.Get("text").GetKind() != JsonValueKind::String) return false;
            NovelChoice choice;
            choice.index = uint(option.Get("index").GetInt());
            choice.text = option.Get("text").GetString();
            p.choices.pushBack(choice);
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
        JsonValue@ canonical = State(core);
        if (!source.Equals(canonical.View())) return false;
        result = decoded;
        return true;
    }

    /// withEndings=false reproduces profiles written before endings were tracked (for strict comparison only).
    JsonValue@ Profile(MenuProfile@ profile, bool withEndings = true)
    {
        JsonValue result;
        result.MakeObject();
        Integer(result, "schemaVersion", Version);
        Boolean(result, "firstRun", profile.firstRun);
        result.Set("readLines", Strings(profile.readLines));
        if (withEndings)
        {
            result.Set("endings", Strings(profile.endings));
        }
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
        if (!ReadStrings(source.Get("readLines"), decoded.readLines, 1000000)) return false;
        bool withEndings = source.Has("endings");
        if (withEndings && !ReadStrings(source.Get("endings"), decoded.endings, 16)) return false;
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
        JsonValue@ canonical = Profile(decoded, withEndings);
        if (!source.Equals(canonical.View())) return false;
        result = decoded;
        return true;
    }
}
