//
// Created by Codex on 17.11.2026.
//

#include "RuntimeValues.as"
#include "NovelState.as"

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
    Map<String, String> paths;
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

    void Build(GameObject@ parent, JsonValueView@ manifest)
    {
        paths.clear();
        JsonValueView@ assets = manifest.Get("assets");
        for (uint i = 0; i < assets.GetCount(); ++i)
        {
            JsonValueView@ asset = assets.At(i);
            String path = asset.Get("target").GetString();
            paths.set(asset.Get("id").GetString(), path.substring(10, path.length() - 10));
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
        if (!paths.contains(id))
        {
            diagnostic = "NovelAudio::Path() : unknown manifest resource " + id;
            return "";
        }
        return paths.at(id);
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

    bool Command(NovelAudioState@ audio, const String &in bus, bool play, const String &in id, bool loop, float duration)
    {
        NovelAudioSlot@ slot = Bus(bus);
        if (slot is null)
        {
            diagnostic = "NovelAudio::Command() : unknown bus " + bus;
            return false;
        }
        NovelAudioChannel@ channel = audio.Channel(bus);
        bool stop = !play;
        if (!stop)
        {
            String path = Path(id);
            if (path == "")
            {
                return false;
            }
            slot.source.Stop();
            slot.source.SetPath(path);
            slot.source.SetLoop(loop);
            slot.source.SetVolume(duration > 0 ? 0 : 1);
            if (!slot.source.Play())
            {
                diagnostic = "NovelAudio::Command() : Play failed " + id;
                return false;
            }
            channel.resourceId = id;
            channel.loop = loop;
            channel.position = 0;
            channel.gain = duration > 0 ? 0 : 1;
            channel.completed = false;
        }
        channel.fadeFrom = channel.gain;
        channel.targetGain = stop ? 0 : 1;
        channel.fadeDuration = duration;
        channel.fadeRemaining = duration;
        channel.stopAfterFade = stop;
        if (stop && duration <= 0)
        {
            slot.source.Stop();
            channel.completed = true;
            channel.gain = 0;
        }

        return true;
    }

    void Update(NovelAudioState@ audio, float dt)
    {
        soundedThisFrame = false;
        float cooldown = float(audio.voiceCooldown) - dt;
        audio.voiceCooldown = cooldown > 0 ? cooldown : 0;
        for (NovelAudioSlot@ slot = buses; slot !is null; @slot = slot.next)
        {
            NovelAudioChannel@ channel = audio.Channel(slot.id);
            float remaining = float(channel.fadeRemaining);
            if (remaining > 0 && dt > 0)
            {
                remaining = remaining > dt ? remaining - dt : 0;
                float progress = 1.0f - remaining / float(channel.fadeDuration);
                float gain = float(channel.fadeFrom) * (1 - progress) + float(channel.targetGain) * progress;
                slot.source.SetVolume(gain);
                channel.gain = gain;
                channel.fadeRemaining = remaining;
                if (remaining <= 0 && channel.stopAfterFade)
                {
                    slot.source.Stop();
                }
            }
            channel.position = slot.source.GetPlaybackPosition();
            channel.completed = !slot.source.IsPlaying();
        }
    }

    void Type(NovelAudioState@ audio, NovelSpeaker@ speaker, float cps)
    {
        if (soundedThisFrame || cps <= 0 || !MenuSession::profile.settings.pixel_voice || audio.voiceCooldown > 0)
        {
            return;
        }
        if (speaker.voicePath == "")
        {
            return;
        }
        uint index = uint(audio.voiceIndex);
        NovelAudioSlot@ slot = voices;
        for (uint i = 0; i < index; ++i)
        {
            @slot = slot.next;
        }
        slot.source.Stop();
        if (slot.id != speaker.voice)
        {
            slot.source.SetPath(speaker.voicePath);
            slot.id = speaker.voice;
        }
        slot.source.SetLoop(false);
        slot.source.SetVolume(1);
        slot.source.Play();
        float interval = 0.075f * float(speaker.multiplier);
        if (1.0f / cps > interval)
        {
            interval = 1.0f / cps;
        }
        audio.voiceIndex = (index + 1) % 10;
        audio.voiceCooldown = interval;
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

    bool Restore(NovelAudioState@ audio, bool resumeOneShots = true)
    {
        StopTyping();
        for (NovelAudioSlot@ slot = buses; slot !is null; @slot = slot.next)
        {
            NovelAudioChannel@ channel = audio.Channel(slot.id);
            slot.source.Stop();
            if (channel.completed || channel.resourceId == "" || (!resumeOneShots && slot.id == "Sfx" && !channel.loop))
            {
                continue;
            }
            String path = Path(channel.resourceId);
            if (path == "")
            {
                return false;
            }
            slot.source.SetPath(path);
            slot.source.SetLoop(channel.loop);
            slot.source.SetVolume(float(channel.gain));
            if (!slot.source.Play() || (channel.position > 0 && !slot.source.Seek(float(channel.position))))
            {
                diagnostic = "NovelAudio::Restore() : playback/seek failed; stage 03 dependency";
                slot.source.Stop();
                return false;
            }
        }
        return true;
    }
}
