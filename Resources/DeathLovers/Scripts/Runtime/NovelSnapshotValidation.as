//
// Created by Codex on 17.11.2026.
//

#include "DialogueProgram.as"

// Structural checks of a restored state. Whether the position still exists in the story code
// is checked separately by replaying the frames (NovelSession::ValidateSnapshot).
namespace NovelSnapshotValidation
{
    bool Nonnegative(double value)
    {
        return value >= 0 && value <= 1.7976931348623157e308;
    }

    bool Resource(const String &in id, const Map<String, String> &in paths)
    {
        return id == "builtin:black" || id == "hidden" || (paths.contains(id) && !RuntimeValues::Starts(id, "audio/"));
    }

    bool History(const Vector<NovelHistoryEntry> &in entries, const Map<String, NovelSpeaker> &in speakers)
    {
        for (uint i = 0; i < entries.size(); ++i)
        {
            if (entries[i].lineId == "" || !speakers.contains(entries[i].speakerId))
            {
                return false;
            }
        }
        return true;
    }

    bool Frames(const Vector<StoryFrame> &in frames)
    {
        if (frames.size() > 1000)
        {
            return false;
        }
        for (uint i = 0; i < frames.size(); ++i)
        {
            const StoryFrame@ frame = frames[i];
            // Outer frames wait inside a call, the top one on an interaction: each made at least one step.
            if (frame.label == "" || frame.step == 0 || frame.picks.size() > frame.step || frame.afterCall.size() > frame.step)
            {
                return false;
            }
        }
        return true;
    }

    bool Core(NovelCore@ s, JsonValueView@ definitions,
        const Map<String, NovelSpeaker> &in speakers, const Map<String, String> &in paths, DialogueProgram@ program)
    {
        if (s is null || s.schemaVersion != 1 || s.contentVersion != Story::Version || !Nonnegative(s.playTimeSeconds) ||
            !Frames(s.frames) || s.history.size() > 250)
        {
            return false;
        }
        String phase = s.phase;
        if (s.activeEndingId != "" && (s.activeEndingId.length() <= 7 ||
            s.activeEndingId.substring(s.activeEndingId.length() - 7, 7) != "_ending"))
        {
            return false;
        }
        if (phase != "Ready" && phase != "WaitingText" && phase != "WaitingChoice" &&
            phase != "WaitingTimer" && phase != "WaitingTransition" && phase != "Finished")
        {
            return false;
        }
        // A waiting story always has a position; a finished one has nothing left to resume.
        if (phase != "Finished" && (s.frames.size() == 0 || s.position == ""))
        {
            return false;
        }
        NovelPresentationState@ p = s.presentation;
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
        if (p.characters.size() != characterCount || !History(s.history, speakers) || !History(p.nvl, speakers) ||
            p.choices.size() > 8 || (phase == "WaitingChoice") != (p.choices.size() > 0))
        {
            return false;
        }
        for (uint i = 0; i < p.choices.size(); ++i)
        {
            if (p.choices[i].index >= 64 || (i > 0 && p.choices[i].index <= p.choices[i - 1].index))
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

    bool Validate(NovelState@ snapshot, JsonValueView@ definitions,
        const Map<String, NovelSpeaker> &in speakers, const Map<String, String> &in paths)
    {
        DialogueProgram program;
        if (snapshot is null || snapshot.rollbackCheckpoints.size() > 100 ||
            !Core(snapshot.core, definitions, speakers, paths, program))
        {
            return false;
        }
        for (uint i = 0; i < snapshot.rollbackCheckpoints.size(); ++i)
        {
            NovelCore@ checkpoint = snapshot.rollbackCheckpoints[i];
            if ((checkpoint.phase != "WaitingText" && checkpoint.phase != "WaitingChoice") ||
                !Core(checkpoint, definitions, speakers, paths, program))
            {
                return false;
            }
        }
        return true;
    }
}
