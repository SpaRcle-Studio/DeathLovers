//
// Created by Codex on 16.11.2026.
//

#include "../Runtime/NovelState.as"

interface IStoryDebugRuntime
{
    NovelState@ CaptureDebugState();
    bool RestoreDebugCheckpoint(NovelState@ state);
    bool HasDebugCommand(const String &in commandId);
}

interface IStoryDebugSnapshotSink
{
    bool SaveDebugSnapshot(const String &in name, const String &in json);
}

class StoryDebugPanel : ScriptBehaviour
{
    private bool developmentBuild = false;
    private IStoryDebugRuntime@ runtime;
    private IStoryDebugSnapshotSink@ sink;
    private TextMesh@ display;
    private JsonValue@ checkpoints;
    private JsonValue@ resources;
    private String contentVersion;
    private String selectedCheckpoint;
    private String diagnostic;

    void Configure(bool development, IStoryDebugRuntime@ target,
        IStoryDebugSnapshotSink@ storage, TextMesh@ text,
        JsonValue@ checkpointManifest, JsonValue@ assetManifest,
        const String &in version)
    {
        developmentBuild = development;
        @runtime = target;
        @sink = storage;
        @display = text;
        contentVersion = version;
        if (checkpointManifest !is null)
        {
            @checkpoints = checkpointManifest;
        }
        if (assetManifest !is null)
        {
            @resources = assetManifest;
        }
        gameObject.SetEnabled(developmentBuild);
    }

    void SelectCheckpoint(const String &in name)
    {
        selectedCheckpoint = name;
    }

    void Refresh()
    {
        if (!developmentBuild || runtime is null || display is null)
        {
            return;
        }
        NovelState@ state = runtime.CaptureDebugState();
        if (state is null)
        {
            diagnostic = "DEBUG_STATE: runtime did not supply a valid snapshot";
            display.SetText(diagnostic);
            return;
        }
        String text = "ID: " + state.core.currentCommandId;
        text = text + "\nPhase: " + state.core.phase;
        text = text + "\nStack: " + SerializeScriptValue(state.core.callStack);
        text = text + "\nVariables: " + SerializeScriptValue(state.core.variables);
        text = text + "\n" + diagnostic;
        display.SetText(text);
    }

    void ShowResources()
    {
        if (!developmentBuild || display is null || resources is null)
        {
            return;
        }
        display.SetText(resources.View().ToJson());
    }

    bool CompleteCheckpoint(NovelState@ state)
    {
        return state !is null && state.core.schemaVersion == 2 && state.core.contentVersion == contentVersion &&
            runtime.HasDebugCommand(state.core.currentCommandId);
    }

    void RestoreCheckpoint()
    {
        if (!developmentBuild || runtime is null || checkpoints is null)
        {
            return;
        }
        if (!checkpoints.View().Has(selectedCheckpoint))
        {
            diagnostic = "CHECKPOINT_UNKNOWN: label jumps are forbidden; select a complete fixture";
            Refresh();
            return;
        }
        NovelState state;
        String encoded = checkpoints.View().Get(selectedCheckpoint).GetString();
        if (encoded == "" || !DeserializeScriptValue(encoded, state))
        {
            diagnostic = "CHECKPOINT_INCOMPLETE: regenerate typed fixture for this contentVersion";
            Refresh();
            return;
        }
        if (!CompleteCheckpoint(state))
        {
            diagnostic = "CHECKPOINT_INCOMPLETE: session unchanged; regenerate fixture for this contentVersion";
            Refresh();
            return;
        }
        // Runtime validates all typed fields/resources before atomic application.
        if (!runtime.RestoreDebugCheckpoint(state))
        {
            diagnostic = "CHECKPOINT_REJECTED: runtime validation failed; session unchanged";
        }
        else
        {
            diagnostic = "CHECKPOINT_RESTORED";
        }
        Refresh();
    }

    void SaveSnapshot()
    {
        if (!developmentBuild || runtime is null)
        {
            return;
        }
        NovelState@ state = runtime.CaptureDebugState();
        if (sink is null || state is null)
        {
            diagnostic = "SNAPSHOT_UNAVAILABLE: connect application-data storage sink";
        }
        else if (!sink.SaveDebugSnapshot("story-debug", SerializeScriptValue(state)))
        {
            diagnostic = "SNAPSHOT_WRITE_FAILED: inspect storage diagnostics";
        }
        else
        {
            diagnostic = "SNAPSHOT_SAVED";
        }
        Refresh();
    }
}
