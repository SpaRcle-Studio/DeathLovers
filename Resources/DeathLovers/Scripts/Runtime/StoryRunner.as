//
// Created by Claude on 27.11.2026.
//

#include "NovelState.as"

/// Presentation side of the story, implemented by NovelSession.
/// The runner calls it only for live operations: while restoring nothing reaches the screen,
/// so a runner without a host can validate a save by replaying it.
interface IStoryHost
{
    void StorySay(const String &in lineId, const String &in speakerId, const String &in mode, const String &in text, bool autoWait);
    void StoryMenu(const String &in menuId, const Vector<NovelChoice> &in choices);
    void StoryScene(const String &in resourceId, const String &in transition, float seconds);
    void StoryCharacter(const String &in characterId, const String &in state, const String &in transition, float seconds);
    void StoryAudio(const String &in bus, bool play, const String &in resourceId, bool loop, float fade);
    void StoryNvlClear();
    void StoryPause(float seconds, bool waitForInput);
    void StoryBarrier();
    void StoryRestartToMenu();
    /// true when the presentation has to wait for resources before the story may continue
    bool StoryNeedsFrame();
}

namespace Story
{
    /// runner executing story code right now; set for the duration of StoryRunner::Resume()
    StoryRunner@ active;
    /// variables of the active runner
    StoryVars@ v;
}

/// What an operation must do while the runner replays frames towards a saved position.
enum StoryStep
{
    /// before the saved position: no presentation, menus answered from the journal
    Skipped,
    /// normal execution
    Executed,
    /// the call that leads to the next saved frame
    Entered,
    /// the saved operation itself: from here on the story runs live
    Reached
}

/// Runs story functions in a coroutine and restores a position without serializing the coroutine:
/// only the frames on the stack are replayed (see StoryFrame), so restore cost does not depend on story length.
class StoryRunner
{
    IStoryHost@ host;
    NovelCore@ core;
    Coroutine@ coroutine;
    String rootLabel;
    String pendingJump;
    String error;
    bool restoring = false;
    bool abortRequested = false;
    Vector<StoryFrame> target;
    Story::StoryVars targetVars;
    String targetPosition;
    bool hasPick = false;
    uint pick = 0;
    uint operations = 0;

    void Bind(IStoryHost@ storyHost, NovelCore@ storyCore)
    {
        @host = storyHost;
        @core = storyCore;
    }

    bool IsRunning()
    {
        return coroutine !is null;
    }

    void Abort()
    {
        restoring = false;
        pendingJump = "";
        hasPick = false;
        if (coroutine is null)
        {
            return;
        }
        if (coroutine.IsRunning())
        {
            // Aborting from inside would stop the calling script right away; finish in Resume().
            abortRequested = true;
            return;
        }
        coroutine.Abort();
        @coroutine = null;
    }

    void Start(const String &in label)
    {
        Abort();
        core.frames.clear();
        core.position = "";
        error = "";
        Launch(label);
    }

    /// Rebuilds the coroutine at the position stored in core.frames (load, rollback, hot reload).
    bool Restore()
    {
        Abort();
        error = "";
        if (core.frames.size() == 0)
        {
            return true;
        }
        target = core.frames;
        targetVars = core.vars;
        targetPosition = core.position;
        core.frames.clear();
        restoring = true;
        Launch(target[0].label);
        Resume();
        if (error == "" && restoring)
        {
            error = "Story restore did not reach the saved position in " + target[target.size() - 1].label;
        }
        if (error != "")
        {
            String failure = error;
            Abort();
            error = failure;
            core.frames = target;
            core.vars = targetVars;
            core.position = targetPosition;
            return false;
        }
        return true;
    }

    bool Resume()
    {
        if (coroutine is null)
        {
            return false;
        }
        Coroutine@ running = coroutine;
        StoryRunner@ previousRunner = Story::active;
        Story::StoryVars@ previousVars = Story::v;
        @Story::active = this;
        @Story::v = core.vars;
        operations = 0;
        bool resumed = running.Resume();
        @Story::active = previousRunner;
        @Story::v = previousVars;
        if (!resumed && error == "" && !abortRequested)
        {
            error = running.GetError();
        }
        if (abortRequested || error != "")
        {
            abortRequested = false;
            running.Abort();
            if (coroutine is running)
            {
                @coroutine = null;
            }
            restoring = restoring && error == "";
            return error == "";
        }
        if (pendingJump != "")
        {
            String label = pendingJump;
            running.Abort();
            core.frames.clear();
            Launch(label);
            return true;
        }
        if (running.IsFinished())
        {
            @coroutine = null;
            core.frames.clear();
        }
        return true;
    }

    void Pick(uint index)
    {
        pick = index;
        hasPick = true;
    }

    // ---- coroutine side ------------------------------------------------------------------------

    void Launch(const String &in label)
    {
        rootLabel = label;
        pendingJump = "";
        abortRequested = false;
        @coroutine = Coroutine(CoroutineEntry(this.Body));
    }

    void Body()
    {
        CoroutineEntry@ entry = FindCoroutineEntry(rootLabel);
        if (entry is null)
        {
            Fail("Unknown story label " + rootLabel);
            return;
        }
        Enter(rootLabel);
        entry();
        Leave();
    }

    void Fail(const String &in message)
    {
        if (error == "")
        {
            error = message;
        }
        if (IsInCoroutine())
        {
            // Never resumed: Resume() sees the error and aborts the coroutine.
            Yield();
        }
    }

    void Operation()
    {
        if (++operations > 200000)
        {
            Fail("Story ran 200000 operations without waiting for the player: probable infinite loop in " + core.Label());
        }
    }

    void Enter(const String &in label)
    {
        uint depth = core.frames.size();
        if (depth >= 1000)
        {
            Fail("Story call stack limit in " + label);
        }
        if (restoring)
        {
            if (depth >= target.size() || target[depth].label != label)
            {
                Fail("Saved call stack does not match the script: expected " +
                    (depth < target.size() ? target[depth].label : "<none>") + ", got " + label);
            }
            core.vars = target[depth].entry;
        }
        core.frames.resize(depth + 1);
        core.frames[depth].label = label;
        core.frames[depth].entry = core.vars;
        uint scope = 0;
        for (uint i = 0; i + 1 < label.length(); ++i)
        {
            if (label.byteAt(i) == 58 && label.byteAt(i + 1) == 58)
            {
                scope = i + 2;
            }
        }
        String name = label.substring(scope, label.length() - scope);
        if (name.length() > 7 && name.substring(name.length() - 7, 7) == "_ending")
        {
            core.activeEndingId = name;
        }
    }

    void Leave()
    {
        core.frames.resize(core.frames.size() - 1);
    }

    StoryStep Step(bool call)
    {
        uint depth = core.frames.size() - 1;
        uint step = core.frames[depth].step + 1;
        core.frames[depth].step = step;
        if (!restoring)
        {
            return StoryStep::Executed;
        }
        uint expected = target[depth].step;
        if (step < expected)
        {
            return StoryStep::Skipped;
        }
        if (step > expected)
        {
            Fail("Saved position is not reachable in " + core.frames[depth].label);
        }
        if (depth + 1 < target.size())
        {
            if (!call)
            {
                Fail("Saved call is not found in " + core.frames[depth].label);
            }
            return StoryStep::Entered;
        }
        if (call)
        {
            Fail("Saved position points to a call in " + core.frames[depth].label);
        }
        for (uint i = 0; i < target.size(); ++i)
        {
            if (core.frames[i].picks.size() != target[i].picks.size() ||
                core.frames[i].afterCall.size() != target[i].afterCall.size())
            {
                Fail("Saved choices do not match the script in " + core.frames[i].label);
            }
        }
        if (SerializeScriptValue(core.vars) != SerializeScriptValue(targetVars))
        {
            Fail("Saved variables do not match the script in " + core.frames[depth].label);
        }
        restoring = false;
        return StoryStep::Reached;
    }

    /// Yields until the host finishes the current interaction (phase becomes Ready).
    void Wait()
    {
        while (core.phase != "Ready")
        {
            Yield();
        }
        if (abortRequested)
        {
            Yield();
        }
    }

    void SoftYield()
    {
        if (abortRequested || host.StoryNeedsFrame())
        {
            Yield();
        }
    }

    /// Live presentation is impossible without a host (save validation): stop here.
    bool Live()
    {
        if (host is null)
        {
            Yield();
            return false;
        }
        return true;
    }

    String Hash(const String &in text)
    {
        uint64 hash = 0xcbf29ce484222325;
        for (uint i = 0; i < text.length(); ++i)
        {
            hash ^= uint64(text.byteAt(i));
            hash *= 0x100000001b3;
        }
        String digits = "0123456789abcdef";
        String result;
        for (int shift = 60; shift >= 0; shift -= 4)
        {
            result = result + digits.substring(uint((hash >> uint(shift)) & 15), 1);
        }
        return result;
    }

    void CheckPosition(const String &in id)
    {
        if (id != targetPosition)
        {
            Fail("Saved position is not in the script any more (" + core.Label() + ")");
        }
    }

    void Say(const String &in speakerId, const String &in mode, const String &in text, bool autoWait)
    {
        Operation();
        StoryStep step = Step(false);
        if (step == StoryStep::Skipped)
        {
            return;
        }
        String id = Hash(core.Label() + "|" + speakerId + "|" + text);
        if (step == StoryStep::Reached)
        {
            CheckPosition(id);
            if (core.phase == "WaitingText")
            {
                Wait();
                return;
            }
        }
        if (!Live())
        {
            return;
        }
        core.position = id;
        host.StorySay(id, speakerId, mode, text, autoWait);
        Wait();
    }

    uint Choose(const Vector<String> &in texts, const Vector<bool> &in available)
    {
        Operation();
        StoryStep step = Step(false);
        uint depth = core.frames.size() - 1;
        if (step == StoryStep::Skipped)
        {
            uint index = core.frames[depth].picks.size();
            if (index >= target[depth].picks.size())
            {
                Fail("Saved choices do not match the script in " + core.frames[depth].label);
            }
            uint picked = target[depth].picks[index];
            core.frames[depth].picks.pushBack(picked);
            return picked;
        }
        String joined = core.Label() + "|menu";
        for (uint i = 0; i < texts.size(); ++i)
        {
            joined = joined + "|" + texts[i];
        }
        String id = Hash(joined);
        bool waiting = false;
        if (step == StoryStep::Reached)
        {
            CheckPosition(id);
            waiting = core.phase == "WaitingChoice";
        }
        if (!waiting)
        {
            if (!Live())
            {
                return 0;
            }
            Vector<NovelChoice> choices;
            for (uint i = 0; i < texts.size(); ++i)
            {
                if (available[i])
                {
                    NovelChoice choice;
                    choice.index = i;
                    choice.text = texts[i];
                    choices.pushBack(choice);
                }
            }
            if (choices.size() == 0 || choices.size() > 8)
            {
                Fail("Menu has zero or more than eight available options in " + core.Label());
            }
            core.position = id;
            hasPick = false;
            host.StoryMenu(id, choices);
        }
        Wait();
        if (!hasPick || pick >= texts.size())
        {
            Fail("Menu resumed without a valid choice in " + core.Label());
        }
        hasPick = false;
        core.frames[depth].picks.pushBack(pick);
        return pick;
    }

    void Scene(const String &in resourceId, const String &in transition, float seconds)
    {
        Operation();
        StoryStep step = Step(false);
        if (step == StoryStep::Skipped)
        {
            return;
        }
        String id = "scene:" + resourceId;
        if (step == StoryStep::Reached)
        {
            CheckPosition(id);
            if (core.phase == "WaitingTransition")
            {
                Wait();
                return;
            }
        }
        if (!Live())
        {
            return;
        }
        core.position = id;
        host.StoryScene(resourceId, transition, seconds);
        SoftYield();
        Wait();
    }

    void Pause(float seconds, bool waitForInput)
    {
        Operation();
        StoryStep step = Step(false);
        if (step == StoryStep::Skipped)
        {
            return;
        }
        if (step == StoryStep::Reached)
        {
            CheckPosition("pause");
            if (core.phase == "WaitingTimer")
            {
                Wait();
                return;
            }
        }
        if (!Live())
        {
            return;
        }
        core.position = "pause";
        host.StoryPause(seconds, waitForInput);
        Wait();
    }

    void Show(const String &in characterId, const String &in state, const String &in transition, float seconds)
    {
        Operation();
        if (restoring || !Live())
        {
            return;
        }
        host.StoryCharacter(characterId, state, transition, seconds);
        SoftYield();
    }

    void Audio(const String &in bus, bool play, const String &in resourceId, bool loop, float fade)
    {
        Operation();
        if (restoring || !Live())
        {
            return;
        }
        host.StoryAudio(bus, play, resourceId, loop, fade);
        SoftYield();
    }

    void NvlClear()
    {
        Operation();
        if (restoring || !Live())
        {
            return;
        }
        host.StoryNvlClear();
        SoftYield();
    }

    void Barrier()
    {
        Operation();
        if (restoring || !Live())
        {
            return;
        }
        host.StoryBarrier();
    }

    void RestartToMenu()
    {
        Operation();
        if (restoring)
        {
            Fail("Saved position is past the end of the story in " + core.Label());
        }
        if (!Live())
        {
            return;
        }
        host.StoryRestartToMenu();
        Yield();
        Fail("Story resumed after restart_to_menu() in " + core.Label());
    }

    void Call(CoroutineEntry@ entry)
    {
        Operation();
        if (entry is null)
        {
            Fail("call() with a null label in " + core.Label());
        }
        StoryStep step = Step(true);
        uint depth = core.frames.size() - 1;
        if (step == StoryStep::Skipped)
        {
            uint index = core.frames[depth].afterCall.size();
            if (index >= target[depth].afterCall.size())
            {
                Fail("Saved calls do not match the script in " + core.frames[depth].label);
            }
            core.vars = target[depth].afterCall[index];
            core.frames[depth].afterCall.pushBack(core.vars);
            return;
        }
        Enter(GetCoroutineEntryName(entry));
        entry();
        Leave();
        core.frames[depth].afterCall.pushBack(core.vars);
    }

    void Jump(CoroutineEntry@ entry)
    {
        Operation();
        if (entry is null)
        {
            Fail("jump() with a null label in " + core.Label());
        }
        if (restoring)
        {
            Fail("Saved position is past a jump in " + core.Label());
        }
        // Resume() drops the whole stack and starts the target as the new root.
        pendingJump = GetCoroutineEntryName(entry);
        Yield();
    }
}
