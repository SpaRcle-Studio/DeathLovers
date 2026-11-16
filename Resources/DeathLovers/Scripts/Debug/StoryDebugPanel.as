//
// Created by Codex on 16.11.2026.
//

interface IStoryDebugRuntime
{
    JsonValue@ CaptureDebugState();
    bool RestoreDebugCheckpoint(JsonValue@ state);
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
            @checkpoints = checkpointManifest.Clone();
        }
        if (assetManifest !is null)
        {
            @resources = assetManifest.Clone();
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
        JsonValue@ state = runtime.CaptureDebugState();
        if (state is null || !state.IsValid())
        {
            diagnostic = "DEBUG_STATE: runtime did not supply a valid snapshot";
            display.SetText(diagnostic);
            return;
        }
        String text = "ID: " + state.Get("currentCommandId").GetString();
        text = text + "\nPhase: " + state.Get("phase").GetString();
        text = text + "\nStack: " + state.Get("callStack").ToJson();
        text = text + "\nVariables: " + state.Get("variables").ToJson();
        text = text + "\n" + diagnostic;
        display.SetText(text);
    }

    void ShowResources()
    {
        if (!developmentBuild || display is null || resources is null)
        {
            return;
        }
        display.SetText(resources.ToJson());
    }

    bool CompleteCheckpoint(JsonValue@ state)
    {
        if (state is null || !state.IsValid() || state.GetKind() != JsonValueKind::Object)
        {
            return false;
        }
        if (!state.Has("schemaVersion") || state.Get("schemaVersion").GetInt() != 1 ||
            !state.Has("contentVersion") || state.Get("contentVersion").GetString() != contentVersion ||
            !state.Has("currentCommandId") || !state.Has("phase") ||
            !state.Has("callStack") || !state.Has("variables") ||
            !state.Has("presentation") || !state.Has("audio") ||
            !state.Has("history") || !state.Has("rollbackBoundaryId") ||
            !state.Has("playTimeSeconds") || !state.Has("activeEndingId"))
        {
            return false;
        }
        JsonValue@ variables = state.Get("variables");
        if (variables.GetKind() != JsonValueKind::Object || variables.GetCount() != 7 ||
            !variables.Has("var_offices_visited") || !variables.Has("var_canteen_visited") ||
            !variables.Has("var_landfill_visited") || !variables.Has("var_roots") ||
            !variables.Has("var_hunger_score") || !variables.Has("var_war_score") ||
            !variables.Has("var_plague_score"))
        {
            return false;
        }
        JsonValue@ presentation = state.Get("presentation");
        if (presentation.GetKind() != JsonValueKind::Object ||
            !presentation.Has("background") || !presentation.Has("characters") ||
            !presentation.Has("mode") || !presentation.Has("speakerId") ||
            !presentation.Has("text") || !presentation.Has("visibleIndex") ||
            !presentation.Has("remainingPause") || !presentation.Has("choices") ||
            !presentation.Has("transition"))
        {
            return false;
        }
        return runtime.HasDebugCommand(state.Get("currentCommandId").GetString());
    }

    void RestoreCheckpoint()
    {
        if (!developmentBuild || runtime is null || checkpoints is null)
        {
            return;
        }
        if (!checkpoints.Has(selectedCheckpoint))
        {
            diagnostic = "CHECKPOINT_UNKNOWN: label jumps are forbidden; select a complete fixture";
            Refresh();
            return;
        }
        JsonValue@ state = checkpoints.Get(selectedCheckpoint);
        if (!CompleteCheckpoint(state))
        {
            diagnostic = "CHECKPOINT_INCOMPLETE: session unchanged; regenerate fixture for this contentVersion";
            Refresh();
            return;
        }
        // Runtime validates all typed fields/resources before atomic application.
        if (!runtime.RestoreDebugCheckpoint(state.Clone()))
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
        JsonValue@ state = runtime.CaptureDebugState();
        if (sink is null || state is null || !state.IsValid())
        {
            diagnostic = "SNAPSHOT_UNAVAILABLE: connect application-data storage sink";
        }
        else if (!sink.SaveDebugSnapshot("story-debug", state.ToJson()))
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
