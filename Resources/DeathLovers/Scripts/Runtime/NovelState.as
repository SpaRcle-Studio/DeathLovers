//
// Created by Codex on 21.11.2026.
//

#include "../../Story/Script/Vars.as"

class DialogueToken
{
    String kind;
    uint index = 0;
    float value = 0;
    float cps = 1;
}

class DialogueSpan
{
    String name;
    String tag;
    uint begin = 0;
    uint end = 0;
    bool closed = false;
    float relativeSize = 1;
}

class NovelSpeaker
{
    String name;
    String voice;
    String voicePath;
    FVector3 color;
    float multiplier = 1;
}

class NovelHistoryEntry
{
    String lineId;
    String speakerId;
    String text;
}

class NovelChoice
{
    /// index of the option as declared in the story code (stable regardless of conditions)
    uint index = 0;
    String text;
}

/// One active story function on the coroutine stack. The stack itself is not serialized:
/// a frame is re-entered by replaying its function from the start with `entry` variables,
/// skipping `step` operations, answering menus from `picks` and skipping completed calls
/// by restoring the variables they returned with (`afterCall`).
class StoryFrame
{
    String label;
    Story::StoryVars entry;
    uint step = 0;
    Vector<uint> picks;
    Vector<Story::StoryVars> afterCall;
}

class NovelTransition
{
    String kind = "none";
    String from = "builtin:black";
    String target = "builtin:black";
    float elapsed = 0;
    float duration = 0;
}

class NovelCharacter
{
    String state;
    String resourceId;
    String previousResource = "hidden";
    String animation;
    FVector2 position;
    FVector2 scale;
    bool flipX = false;
    bool flipY = false;
    float transitionDuration = 0;
    float transitionElapsed = 0;
    float bounceElapsed = 0;
    bool bounceActive = false;
}

class NovelPresentationState
{
    String background = "builtin:black";
    Map<String, NovelCharacter> characters;
    String mode = "ADV";
    String speakerId = "ch_narrator";
    String text;
    bool autoWait = false;
    uint visibleIndex = 0;
    uint tokenIndex = 0;
    float remainingPause = 0;
    bool inputWait = false;
    bool fullyShown = false;
    bool dialogueVisible = false;
    Vector<NovelChoice> choices;
    Vector<NovelHistoryEntry> nvl;
    NovelTransition transition;
    float effectTime = 0;
}

class NovelAudioChannel
{
    String resourceId;
    bool loop = false;
    float position = 0;
    float gain = 1;
    float targetGain = 1;
    float fadeFrom = 1;
    float fadeRemaining = 0;
    float fadeDuration = 0;
    bool stopAfterFade = false;
    bool completed = true;
}

class NovelAudioState
{
    NovelAudioChannel Music;
    NovelAudioChannel Sfx;
    NovelAudioChannel Voice;
    uint voiceIndex = 0;
    float voiceCooldown = 0;

    NovelAudioChannel@ Channel(const String &in bus)
    {
        if (bus == "Music")
        {
            return Music;
        }
        if (bus == "Sfx")
        {
            return Sfx;
        }
        if (bus == "Voice")
        {
            return Voice;
        }
        return null;
    }
}

class NovelCore
{
    uint schemaVersion = 0;
    String contentVersion;
    String phase = "Ready";
    /// id of the operation the story waits on: line id, menu id, "scene:<resource>" or "pause"
    String position;
    Vector<StoryFrame> frames;
    Story::StoryVars vars;
    NovelPresentationState presentation;
    NovelAudioState audio;
    Vector<NovelHistoryEntry> history;
    /// increments on every rollback checkpoint; identifies the interaction a checkpoint belongs to
    uint interaction = 0;
    String activeEndingId;
    String diagnostic;
    double playTimeSeconds = 0;

    String Label() const
    {
        return frames.size() == 0 ? "" : frames[frames.size() - 1].label;
    }
}

class NovelState
{
    NovelCore core;
    Vector<NovelCore> rollbackCheckpoints;
}

class NovelTraceEvent
{
    String label;
    String position;
    String before;
    String after;
}

class NovelRestoreReport
{
    String status;
    uint objectsBefore = 0;
    uint objectsAfter = 0;
    bool textRules = false;
    String audioDiagnostic;
    String snapshot;
    String after;
}

