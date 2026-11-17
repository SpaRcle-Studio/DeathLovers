//
// Created by Codex on 17.11.2026.
//

#include "RuntimeValues.as"

class NovelAudioSlot
{
    AudioSource@ source;
    String id;
    NovelAudioSlot@ next;
}

class NovelAudio
{
    NovelAudioSlot@ buses;
    NovelAudioSlot@ voices;
    JsonValue@ paths;
    String diagnostic;
    bool soundedThisFrame = false;

    AudioSource@ Source(GameObject@ parent, const String &in name, const String &in group)
    {
        AudioSource@ source = cast<AudioSource@>(parent.GetOrCreateChild(name).GetOrCreateComponent("AudioSource"));
        source.playOnEnable = false;
        source.SetSpatialize(SpatializeMode::Off);
        source.SetGroup(group);
        source.SetPitch(1);
        return source;
    }

    void Build(GameObject@ parent, JsonValue@ manifest)
    {
        @paths = RuntimeValues::Object();
        JsonValue@ assets = manifest.Get("assets");
        for (uint i = 0; i < assets.GetCount(); ++i)
        {
            JsonValue@ asset = assets.At(i);
            String path = asset.Get("target").GetString();
            RuntimeValues::PutString(paths, asset.Get("id").GetString(), path.substring(10, path.length() - 10));
        }
        NovelAudioSlot music;
        music.id = "Music";
        @music.source = Source(parent, "StoryMusic", "Music");
        @buses = music;
        NovelAudioSlot sfx;
        sfx.id = "Sfx";
        @sfx.source = Source(parent, "StorySfx", "Effects");
        @music.next = sfx;
        NovelAudioSlot voice;
        voice.id = "Voice";
        @voice.source = Source(parent, "StoryVoice", "Voice");
        voice.source.set_continueOnDisable(true);
        @sfx.next = voice;
        NovelAudioSlot@ previous;
        for (uint i = 0; i < 10; ++i)
        {
            NovelAudioSlot slot;
            @slot.source = Source(parent, "Typewriter" + RuntimeValues::Index(i), "Voice");
            slot.source.set_continueOnDisable(true);
            if (previous is null)
            {
                @voices = slot;
            }
            else
            {
                @previous.next = slot;
            }
            @previous = slot;
        }
    }

    String Path(const String &in id)
    {
        if (!paths.Has(id))
        {
            diagnostic = "NovelAudio::Path() : unknown manifest resource " + id;
            return "";
        }
        return paths.Get(id).GetString();
    }

    NovelAudioSlot@ Bus(const String &in id)
    {
        for (NovelAudioSlot@ slot = buses; slot !is null; @slot = slot.next)
        {
            if (slot.id == id)
            {
                return slot;
            }
        }
        return null;
    }

    JsonValue@ EmptyState()
    {
        JsonValue@ result = RuntimeValues::Object();
        for (NovelAudioSlot@ slot = buses; slot !is null; @slot = slot.next)
        {
            JsonValue channel;
            channel.Parse("{\"resourceId\":\"\",\"loop\":false,\"position\":0,\"gain\":1,\"targetGain\":1,\"fadeFrom\":1,\"fadeRemaining\":0,\"fadeDuration\":0,\"stopAfterFade\":false,\"completed\":true}");
            result.Set(slot.id, channel);
        }
        result.Set("voiceIndex", RuntimeValues::IntValue(0));
        RuntimeValues::PutNumber(result, "voiceCooldown", 0);
        return result;
    }

    bool Command(JsonValue@ audio, JsonValue@ command)
    {
        String bus = command.Get("bus").GetString();
        NovelAudioSlot@ slot = Bus(bus);
        if (slot is null)
        {
            diagnostic = "NovelAudio::Command() : unknown bus " + bus;
            return false;
        }
        JsonValue@ channel = audio.Get(bus);
        float duration = float(command.Get("fadeSeconds").GetNumber());
        bool stop = command.Get("action").GetString() == "stop";
        if (!stop)
        {
            String id = command.Get("resourceId").GetString();
            String path = Path(id);
            if (path == "")
            {
                return false;
            }
            slot.source.Stop();
            slot.source.SetPath(path);
            slot.source.SetLoop(command.Get("loop").GetBool());
            slot.source.SetVolume(duration > 0 ? 0 : 1);
            if (!slot.source.Play())
            {
                diagnostic = "NovelAudio::Command() : Play failed " + id;
                return false;
            }
            RuntimeValues::PutString(channel, "resourceId", id);
            channel.Set("loop", command.Get("loop"));
            RuntimeValues::PutNumber(channel, "position", 0);
            RuntimeValues::PutNumber(channel, "gain", duration > 0 ? 0 : 1);
            channel.Set("completed", RuntimeValues::BoolValue(false));
        }
        RuntimeValues::PutNumber(channel, "fadeFrom", channel.Get("gain").GetNumber());
        RuntimeValues::PutNumber(channel, "targetGain", stop ? 0 : 1);
        RuntimeValues::PutNumber(channel, "fadeDuration", duration);
        RuntimeValues::PutNumber(channel, "fadeRemaining", duration);
        channel.Set("stopAfterFade", RuntimeValues::BoolValue(stop));
        if (stop && duration <= 0)
        {
            slot.source.Stop();
            channel.Set("completed", RuntimeValues::BoolValue(true));
            RuntimeValues::PutNumber(channel, "gain", 0);
        }
        audio.Set(bus, channel);
        return true;
    }

    void Update(JsonValue@ audio, float dt)
    {
        soundedThisFrame = false;
        float cooldown = float(audio.Get("voiceCooldown").GetNumber()) - dt;
        RuntimeValues::PutNumber(audio, "voiceCooldown", cooldown > 0 ? cooldown : 0);
        for (NovelAudioSlot@ slot = buses; slot !is null; @slot = slot.next)
        {
            JsonValue@ channel = audio.Get(slot.id);
            float remaining = float(channel.Get("fadeRemaining").GetNumber());
            if (remaining > 0 && dt > 0)
            {
                remaining = remaining > dt ? remaining - dt : 0;
                float progress = 1.0f - remaining / float(channel.Get("fadeDuration").GetNumber());
                float gain = float(channel.Get("fadeFrom").GetNumber()) * (1 - progress) + float(channel.Get("targetGain").GetNumber()) * progress;
                slot.source.SetVolume(gain);
                RuntimeValues::PutNumber(channel, "gain", gain);
                RuntimeValues::PutNumber(channel, "fadeRemaining", remaining);
                if (remaining <= 0 && channel.Get("stopAfterFade").GetBool())
                {
                    slot.source.Stop();
                }
            }
            RuntimeValues::PutNumber(channel, "position", slot.source.GetPlaybackPosition());
            channel.Set("completed", RuntimeValues::BoolValue(!slot.source.IsPlaying()));
            audio.Set(slot.id, channel);
        }
    }

    void Type(JsonValue@ audio, JsonValue@ speaker, float cps)
    {
        if (soundedThisFrame || cps <= 0 || !MenuSession::profile.settings.pixel_voice || audio.Get("voiceCooldown").GetNumber() > 0)
        {
            return;
        }
        String path = Path(speaker.Get("voice").GetString());
        if (path == "")
        {
            return;
        }
        uint index = uint(audio.Get("voiceIndex").GetInt());
        NovelAudioSlot@ slot = voices;
        for (uint i = 0; i < index; ++i)
        {
            @slot = slot.next;
        }
        slot.source.Stop();
        slot.source.SetPath(path);
        slot.source.SetLoop(false);
        slot.source.SetVolume(1);
        slot.source.Play();
        float interval = 0.075f * float(speaker.Get("multiplier").GetNumber());
        if (1.0f / cps > interval)
        {
            interval = 1.0f / cps;
        }
        audio.Set("voiceIndex", RuntimeValues::IntValue((index + 1) % 10));
        RuntimeValues::PutNumber(audio, "voiceCooldown", interval);
        soundedThisFrame = true;
    }

    void StopTyping()
    {
        for (NovelAudioSlot@ slot = voices; slot !is null; @slot = slot.next)
        {
            slot.source.Stop();
        }
    }

    void Stop()
    {
        StopTyping();
        for (NovelAudioSlot@ slot = buses; slot !is null; @slot = slot.next)
        {
            slot.source.Stop();
        }
    }

    bool Restore(JsonValue@ audio)
    {
        StopTyping();
        for (NovelAudioSlot@ slot = buses; slot !is null; @slot = slot.next)
        {
            JsonValue@ channel = audio.Get(slot.id);
            slot.source.Stop();
            if (channel.Get("completed").GetBool() || channel.Get("resourceId").GetString() == "")
            {
                continue;
            }
            String path = Path(channel.Get("resourceId").GetString());
            if (path == "")
            {
                return false;
            }
            slot.source.SetPath(path);
            slot.source.SetLoop(channel.Get("loop").GetBool());
            slot.source.SetVolume(float(channel.Get("gain").GetNumber()));
            if (!slot.source.Play() || (channel.Get("position").GetNumber() > 0 && !slot.source.Seek(float(channel.Get("position").GetNumber()))))
            {
                diagnostic = "NovelAudio::Restore() : playback/seek failed; stage 03 dependency";
                slot.source.Stop();
                return false;
            }
        }
        return true;
    }
}
