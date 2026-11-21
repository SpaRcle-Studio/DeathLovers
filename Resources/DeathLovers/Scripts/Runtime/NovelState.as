//
// Created by Codex on 21.11.2026.
//

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
    String commandId;
    String speakerId;
    String text;
}

class NovelChoice
{
    String choiceId;
    String normalizedText;
    String target;
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
    String currentCommandId;
    String phase = "Ready";
    Vector<String> callStack;
    Map<String, Value> variables;
    NovelPresentationState presentation;
    NovelAudioState audio;
    Vector<NovelHistoryEntry> history;
    String rollbackBoundaryId;
    String activeEndingId;
    String diagnostic;
    double playTimeSeconds = 0;
}

class NovelState
{
    NovelCore core;
    Vector<NovelCore> rollbackCheckpoints;
}

class NovelTraceEvent
{
    String commandId;
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

