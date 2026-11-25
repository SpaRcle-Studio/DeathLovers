//
// Created by Codex on 25.11.2026.
//

class NovelSaves
{
    MenuNavigation@ menu;
    FrameCapture@ capture;
    bool busy = false;
    bool configured = false;
    String operation;
    String group = "manual";
    uint page = 1;
    bool saveMode = false;
    JsonValue@ listing;
    GameObject@ grid;
    String pendingAction;
    String pendingGroup;
    String pendingSlot;
    String queuedGroup;
    String queuedSlot;
    JsonValue payload;
    JsonValue@ metadata;
    NovelState@ candidate;
    JsonValue@ candidateStory;
    NovelView preparedView;
    NovelPresentation preparedPresentation;
    GameObject@ staging;
    float elapsed = 0;
    uint frames = 0;
    float profileDelay = -1;
    String lastProfile;
    bool profileWritable = true;
    bool autoPending = false;
    double lastAutoTime = 0;
    String lastAutoState;
    String diagnostic;
    String recoveryTrace;
    String candidateStoryResource;
    String autoStateKey;
    bool openAfterYield = false;

    String Two(uint number)
    {
        return (number < 10 ? "0" : "") + RuntimeValues::Index(number);
    }

    String SlotId(uint index)
    {
        return group == "manual" ? "p" + Two(page) + "_s" + Two(index + 1) :
            (group == "quick" ? "q" : "a") + Two(index + 1);
    }

    void Configure(MenuNavigation@ navigation)
    {
        @menu = navigation;
        SaveSystem::Instance().SetReadLimit(80 * 1024 * 1024);
        @capture = cast<FrameCapture@>(menu.gameObject.GetOrCreateComponent("FrameCapture"));
        LoadProfile();
        Component@ receiver = menu.gameObject.GetComponent("Behaviour");
        menu.Button(menu.quickMenu, "Save").SetClickReceiver(receiver, "OpenSave");
        menu.Button(menu.quickMenu, "QuickSave").SetClickReceiver(receiver, "QuickSave");
        menu.Button(menu.quickMenu, "QuickLoad").SetClickReceiver(receiver, "QuickLoad");
        menu.Child(menu.load, "Empty").SetEnabled(false);
        GameObject@ instance = cast<GameObject@>(menu.gameObject.GetScene().InstanceFromFile("DeathLovers/Prefabs/UI/SaveSlots.prefab"));
        @grid = instance;
        if (grid is null)
        {
            diagnostic = "Не удалось загрузить SaveSlots.prefab.";
            return;
        }
        if (!grid.MoveToTree(menu.load))
        {
            grid.Destroy();
            @grid = null;
            diagnostic = "Не удалось добавить сетку сохранений в иерархию меню.";
            return;
        }
        cast<TransformRect@>(grid.GetTransform()).SetAnchoredPosition(menu.runtime.view.Vec(500, -240));
        for (uint i = 0; i < 6; ++i)
        {
            GameObject@ slot = menu.runtime.view.Rect(grid, "Slot" + RuntimeValues::Index(i), 0, 0, 400, 310);
            NovelVisualSlot@ background = menu.runtime.view.Image(slot, "Background");
            cast<TransformRect@>(background.object.GetTransform()).SetSize(menu.runtime.view.Vec(400, 310));
            background.image.SetTexturePath("DeathLovers/UI/button/slot_idle_background.png");
            NovelVisualSlot@ image = menu.runtime.view.Image(slot, "Thumbnail");
            cast<TransformRect@>(image.object.GetTransform()).SetSize(menu.runtime.view.Vec(384, 216));
            cast<TransformRect@>(image.object.GetTransform()).SetAnchoredPosition(menu.runtime.view.Vec(8, -8));
            cast<TransformRect@>(image.object.GetTransform()).localPriority = 2;
            menu.runtime.view.Label(menu.runtime.view.Rect(slot, "Caption", 8, 230, 384, 70), "Пусто").fontSize = 23;
            UIButton@ button = cast<UIButton@>(slot.GetOrCreateComponent("UIButton"));
            button.SetClickReceiver(receiver, "SaveSlot" + RuntimeValues::Index(i));
            MakeButton(slot, "Delete", "Удалить", 270, 275, "DeleteSlot" + RuntimeValues::Index(i));
            cast<TransformRect@>(menu.Child(slot, "Delete").GetTransform()).SetSize(menu.runtime.view.Vec(120, 35));
            cast<TextMesh@>(menu.Child(slot, "Delete").GetComponent("TextMesh")).fontSize = 22;
        }
        MakeButton(menu.load, "ManualTab", "Ручные", 500, 150, "ManualSaves");
        MakeButton(menu.load, "AutoTab", "Авто", 790, 150, "AutoSaves");
        MakeButton(menu.load, "QuickTab", "Быстрые", 1080, 150, "QuickSaves");
        MakeButton(menu.load, "PreviousPage", "<", 500, 900, "PreviousSavePage");
        MakeButton(menu.load, "NextPage", ">", 1050, 900, "NextSavePage");
        menu.runtime.view.Label(menu.runtime.view.Rect(menu.load, "Page", 700, 900, 300, 50), "1 / 10");
        menu.runtime.view.Label(menu.runtime.view.Rect(menu.load, "StorageStatus", 500, 980, 1240, 70), "").fontSize = 22;
        configured = true;
        Refresh();
    }

    void MakeButton(GameObject@ parent, const String &in name, const String &in text, float x, float y, const String &in method)
    {
        GameObject@ object = menu.runtime.view.Rect(parent, name, x, y, 260, 45);
        menu.runtime.view.Label(object, text).fontSize = 26;
        cast<UIButton@>(object.GetOrCreateComponent("UIButton")).SetClickReceiver(menu.gameObject.GetComponent("Behaviour"), method);
    }

    JsonValueView@ Find(const String &in id)
    {
        for (uint i = 0; i < listing.View().GetCount(); ++i)
        {
            if (listing.View().At(i).Get("slotId").GetString() == id)
            {
                return listing.View().At(i);
            }
        }
        JsonValueView empty;
        return empty;
    }

    bool CanSave()
    {
        return configured && menu.inGame && menu.runtime.state !is null && menu.runtime.PhaseName() != "Ready" &&
            !(menu.runtime.PhaseName() == "Finished" && RuntimeValues::Starts(menu.runtime.state.core.diagnostic, "NovelSession : ")) &&
            !menu.runtime.presentation.waitingTextures;
    }

    void Refresh()
    {
        if (!configured)
        {
            return;
        }
        @listing = SaveSystem::Instance().EnumerateSlots(group);
        String listingError = SaveSystem::Instance().GetError();
        menu.Text(menu.load, "StorageStatus", listingError == "" ? "" : "Некоторые сохранения недоступны: " + listingError);
        menu.Text(menu.load, "Title", saveMode ? "Сохранить" : "Загрузить");
        menu.Text(menu.load, "Page", group == "manual" ? RuntimeValues::Index(page) + " / 10" : "");
        menu.Button(menu.load, "PreviousPage").SetInteractable(!busy && group == "manual" && page > 1);
        menu.Button(menu.load, "NextPage").SetInteractable(!busy && group == "manual" && page < 10);
        menu.Button(menu.load, "ManualTab").SetInteractable(!busy);
        menu.Button(menu.load, "AutoTab").SetInteractable(!busy);
        menu.Button(menu.load, "QuickTab").SetInteractable(!busy);
        for (uint i = 0; i < 6; ++i)
        {
            String id = SlotId(i);
            JsonValueView@ record = Find(id);
            bool exists = record.IsValid() && record.Has("slotId");
            GameObject@ slot = menu.Child(grid, "Slot" + RuntimeValues::Index(i));
            menu.Text(slot, "Caption", exists ? record.Get("displayTime").GetString() + "\n" + record.Get("sceneTitle").GetString() : "Пусто");
            cast<UIButton@>(slot.GetComponent("UIButton")).SetInteractable(!busy && (saveMode ? group == "manual" && CanSave() : exists));
            menu.Button(slot, "Delete").SetInteractable(!busy && exists);
            GameObject@ thumbnail = menu.Child(slot, "Thumbnail");
            thumbnail.SetEnabled(exists);
            if (exists)
            {
                SaveSystem::Instance().CloseSlot(group, id);
                SaveSlot@ preview = SaveSystem::Instance().OpenSlot(group, id);
                if (preview !is null)
                {
                    cast<Sprite@>(thumbnail.GetComponent("Sprite")).SetTextureData(preview.GetFile("thumbnail.png"));
                }
                SaveSystem::Instance().CloseSlot(group, id);
            }
        }
        menu.Button(menu.quickMenu, "QuickLoad").SetInteractable(!busy && Latest("quick") != "");
    }

    String Latest(const String &in storageGroup)
    {
        JsonValue@ entries = SaveSystem::Instance().EnumerateSlots(storageGroup);
        int64 sequence = -1;
        String id;
        for (uint i = 0; i < entries.View().GetCount(); ++i)
        {
            if (entries.View().At(i).Get("sequence").GetInt() > sequence && Compatible(entries.View().At(i), storageGroup))
            {
                sequence = entries.View().At(i).Get("sequence").GetInt();
                id = entries.View().At(i).Get("slotId").GetString();
            }
        }
        return id;
    }

    bool Compatible(JsonValueView@ record, const String &in storageGroup)
    {
        if (!record.Has("schemaVersion") || record.Get("schemaVersion").GetInt() != 1)
        {
            return false;
        }
        String resource = record.Get("storyResource").GetString();
        if (!AllowedStory(resource))
        {
            return false;
        }
        JsonValue source;
        if (!source.LoadResource(resource) || record.Get("contentVersion").GetString() != source.View().Get("contentVersion").GetString())
        {
            return false;
        }
        String id = record.Get("slotId").GetString();
        SaveSystem::Instance().CloseSlot(storageGroup, id);
        SaveSlot@ slot = SaveSystem::Instance().OpenSlot(storageGroup, id);
        NovelState test;
        bool valid = slot !is null && slot.HasState() && ThumbnailValid(slot.GetFile("thumbnail.png")) && DecodeState(slot.GetState(), test) &&
            NovelSnapshotValidation::Validate(test, source.View(), menu.runtime.definitions.View(), menu.runtime.speakers, menu.runtime.audio.paths);
        SaveSystem::Instance().CloseSlot(storageGroup, id);
        return valid;
    }

    bool AllowedStory(const String &in resource)
    {
        return resource == "DeathLovers/Story/story.json" || (menu.developmentRuntime &&
            (resource == "DeathLovers/Story/runtime-fixture.json" || resource == "DeathLovers/Story/saves-fixture.json"));
    }

    int64 NextSequence(const String &in storageGroup)
    {
        JsonValue@ entries = SaveSystem::Instance().EnumerateSlots(storageGroup);
        int64 sequence = 0;
        for (uint i = 0; i < entries.View().GetCount(); ++i)
        {
            int64 value = entries.View().At(i).Get("sequence").GetInt();
            sequence = value > sequence ? value : sequence;
        }
        return sequence + 1;
    }

    void Open(bool saving)
    {
        if (!configured)
        {
            Error(diagnostic);
            return;
        }
        if (busy || !menu.CanNavigate() || menu.modal !is null || (saving && !menu.inGame))
        {
            return;
        }
        if (saving && !CanSave())
        {
            openAfterYield = true;
            return;
        }
        if (menu.inGame && !menu.gameMenuOpen)
        {
            menu.ToggleGameMenu();
            menu.inputBarrier = 0;
        }
        saveMode = saving;
        menu.Open(menu.load, "Load");
        Refresh();
    }

    void SelectGroup(const String &in value)
    {
        if (!busy && menu.CanNavigate() && menu.modal is null)
        {
            group = value;
            Refresh();
        }
    }

    void Select(uint index, bool deleting)
    {
        if (busy || !menu.CanNavigate() || menu.modal !is null || index >= 6)
        {
            return;
        }
        String id = SlotId(index);
        bool exists = Find(id).Has("slotId");
        if (deleting && !exists || !saveMode && !exists)
        {
            return;
        }
        String action = deleting ? "delete" : saveMode ? "save" : "load";
        if (action == "save" && (group != "manual" || !CanSave()))
        {
            return;
        }
        if (deleting || action == "save" && exists || action == "load" && menu.inGame)
        {
            Confirm(action, group, id);
        }
        else
        {
            Execute(action, group, id);
        }
    }

    void Confirm(const String &in action, const String &in storageGroup, const String &in id)
    {
        pendingAction = action;
        pendingGroup = storageGroup;
        pendingSlot = id;
        menu.pendingQuit = false;
        menu.pendingMainMenu = false;
        @menu.modalOrigin = menu.submenu is menu.load ? menu.Button(menu.load, "Back") : menu.Button(menu.quickMenu, "QuickLoad");
        menu.Text(menu.Child(menu.confirm, "Content"), "Message", action == "delete" ? "Удалить сохранение?" : action == "save" ? "Перезаписать сохранение?" : "Загрузить сохранение?\nНесохранённый прогресс будет потерян.");
        @menu.modal = menu.confirm;
        menu.confirm.SetEnabled(true);
        menu.Button(menu.Child(menu.Child(menu.confirm, "Content"), "Qestion"), "No").Focus();
        menu.inputBarrier = 0.1f;
    }

    void ConfirmYes()
    {
        String action = pendingAction;
        pendingAction = "";
        menu.confirm.SetEnabled(false);
        @menu.modal = null;
        Execute(action, pendingGroup, pendingSlot);
    }

    void Error(const String &in message)
    {
        diagnostic = message;
        Debug::Instance().Error("NovelSaves : " + message);
        menu.ShowNotify(message, menu.Button(menu.load, "Back"));
    }

    void Execute(const String &in action, const String &in storageGroup, const String &in id)
    {
        if (busy)
        {
            return;
        }
        if (action == "save")
        {
            queuedGroup = storageGroup;
            queuedSlot = id;
            return;
        }
        if (action == "delete")
        {
            busy = true;
            Refresh();
            bool removed = SaveSystem::Instance().DeleteSlot(storageGroup, id);
            String error = SaveSystem::Instance().GetError();
            busy = false;
            menu.inputBarrier = 0.1f;
            Refresh();
            if (!removed)
            {
                Error("Не удалось удалить сохранение: " + error);
            }
            return;
        }
        BeginLoad(storageGroup, id);
    }

    void QuickSave()
    {
        if (configured && !busy && menu.inGame && menu.CanNavigate() && menu.modal is null && queuedGroup == "")
        {
            int64 sequence = NextSequence("quick");
            Execute("save", "quick", "q" + Two(uint((sequence - 1) % 6 + 1)));
        }
    }

    void QuickLoad()
    {
        if (busy || !menu.CanNavigate() || menu.modal !is null)
        {
            return;
        }
        String id = Latest("quick");
        if (id == "")
        {
            return;
        }
        if (menu.inGame)
        {
            Confirm("load", "quick", id);
        }
        else
        {
            BeginLoad("quick", id);
        }
    }

    void TextField(JsonValue@ object, const String &in key, const String &in text)
    {
        JsonValue value;
        value.SetString(text);
        object.Set(key, value);
    }

    bool EqualTree(JsonValueView@ left, JsonValueView@ right, uint depth = 0)
    {
        if (depth > 128 || left.GetKind() != right.GetKind() || left.GetCount() != right.GetCount())
        {
            return false;
        }
        JsonValueKind kind = left.GetKind();
        if (kind == JsonValueKind::Object)
        {
            for (uint i = 0; i < left.GetCount(); ++i)
            {
                String key = left.GetKey(i);
                if (!right.Has(key) || !EqualTree(left.Get(key), right.Get(key), depth + 1))
                {
                    return false;
                }
            }
            return true;
        }
        if (kind == JsonValueKind::Array)
        {
            for (uint i = 0; i < left.GetCount(); ++i)
            {
                if (!EqualTree(left.At(i), right.At(i), depth + 1))
                {
                    return false;
                }
            }
            return true;
        }
        return left.ToJson() == right.ToJson();
    }

    bool DecodeState(JsonValueView@ document, NovelState@ result)
    {
        NovelState decoded;
        if (!DeserializeScriptValue(document.ToJson(), decoded))
        {
            return false;
        }
        JsonValue canonical;
        if (!canonical.Parse(SerializeScriptValue(decoded)) || !EqualTree(document, canonical.View()))
        {
            return false;
        }
        result = decoded;
        return true;
    }

    bool DecodeProfile(JsonValueView@ document, MenuProfile@ result)
    {
        MenuProfile decoded;
        if (!DeserializeScriptValue(document.ToJson(), decoded))
        {
            return false;
        }
        JsonValue canonical;
        if (!canonical.Parse(SerializeScriptValue(decoded)) || !EqualTree(document, canonical.View()))
        {
            return false;
        }
        result = decoded;
        return true;
    }

    void IntegerField(JsonValue@ object, const String &in key, int64 number)
    {
        JsonValue value;
        value.SetInt(number);
        object.Set(key, value);
    }

    JsonValue@ Metadata(bool thumbnail, const String &in content, const String &in command, double time)
    {
        JsonValue result;
        result.MakeObject();
        IntegerField(result, "schemaVersion", 1);
        TextField(result, "contentVersion", content);
        TextField(result, "currentCommandId", command);
        TextField(result, "sceneTitle", command);
        JsonValue value;
        value.SetNumber(time);
        result.Set("playTimeSeconds", value);
        value.SetBool(thumbnail);
        result.Set("hasThumbnail", value);
        return result;
    }

    bool ThumbnailValid(const String &in png)
    {
        return png.length() >= 45 && png.length() <= 4 * 1024 * 1024 &&
            png.byteAt(0) == 137 && png.byteAt(1) == 80 && png.byteAt(2) == 78 && png.byteAt(3) == 71 &&
            png.byteAt(4) == 13 && png.byteAt(5) == 10 && png.byteAt(6) == 26 && png.byteAt(7) == 10 &&
            png.byteAt(12) == 73 && png.byteAt(13) == 72 && png.byteAt(14) == 68 && png.byteAt(15) == 82 &&
            png.byteAt(16) == 0 && png.byteAt(17) == 0 && png.byteAt(18) == 1 && png.byteAt(19) == 128 &&
            png.byteAt(20) == 0 && png.byteAt(21) == 0 && png.byteAt(22) == 0 && png.byteAt(23) == 216 &&
            png.byteAt(24) == 8 && png.byteAt(25) == 2;
    }

    void BeginSave()
    {
        NovelState snapshot;
        snapshot = menu.runtime.state;
        menu.runtime.audio.Update(snapshot.core.audio, 0);
        String encoded = SerializeScriptValue(snapshot);
        if (!payload.Parse(encoded))
        {
            queuedGroup = "";
            Error("Не удалось сериализовать состояние игры.");
            return;
        }
        @metadata = Metadata(true, snapshot.core.contentVersion, snapshot.core.currentCommandId, snapshot.core.playTimeSeconds);
        TextField(metadata, "storyResource", menu.runtime.storyResource);
        autoStateKey = AutoKey();
        IntegerField(metadata, "sequence", NextSequence(queuedGroup));
        if (menu.runtime.Command().Has("sourceFile"))
        {
            TextField(metadata, "sceneTitle", menu.runtime.Command().Get("sourceFile").GetString());
        }
        busy = true;
        operation = "capture_frame";
        elapsed = 0;
        frames = 0;
        menu.main.SetEnabled(false);
        menu.load.SetEnabled(false);
        menu.quickMenu.SetEnabled(false);
        menu.TabBackgroundOpacity(0);
        menu.Child(menu.novel, "Background").SetEnabled(false);
        menu.runtime.view.root.SetEnabled(true);
        menu.runtime.audio.StopTyping();
        if (menu.developmentRuntime)
        {
            menu.Child(menu.novel, "RuntimeProbe").SetEnabled(false);
        }
    }

    void EndCapture()
    {
        capture.Cancel();
        busy = false;
        operation = "";
        menu.runtime.view.root.SetEnabled(!menu.gameMenuOpen);
        menu.main.SetEnabled(menu.gameMenuOpen && menu.submenu is null);
        menu.load.SetEnabled(menu.submenu is menu.load);
        menu.Child(menu.novel, "Background").SetEnabled(menu.gameMenuOpen);
        menu.TabBackgroundOpacity(menu.submenu is null ? 0 : 1);
        menu.inputBarrier = 0.1f;
        menu.runtime.inputBarrier = 0.1f;
        if (menu.developmentRuntime)
        {
            menu.Child(menu.novel, "RuntimeProbe").SetEnabled(true);
        }
        Refresh();
    }

    void Publish(const String &in png)
    {
        String storageGroup = queuedGroup;
        String id = queuedSlot;
        queuedGroup = "";
        SaveSystem::Instance().CloseSlot(storageGroup, id);
        SaveSlot@ slot = SaveSystem::Instance().OpenSlot(storageGroup, id);
        bool saved = false;
        if (slot !is null && slot.GetMetadata().Has("slotId"))
        {
            NovelState previous;
            if (!slot.GetMetadata().Has("schemaVersion") || slot.GetMetadata().Get("schemaVersion").GetInt() != 1 ||
                !DecodeState(slot.GetState(), previous) || previous.core.schemaVersion != 1)
            {
                CancelAutoAttempt(storageGroup);
                EndCapture();
                Error("Нельзя перезаписать сохранение с неподдерживаемой версией состояния.");
                return;
            }
        }
        if (slot !is null && ThumbnailValid(png) && slot.SetState(payload) && slot.SetFile("thumbnail.png", png))
        {
            slot.SetMetadata(metadata);
            saved = SaveSystem::Instance().FlushSlot(storageGroup, id);
        }
        String error = SaveSystem::Instance().GetError();
        EndCapture();
        if (saved)
        {
            if (storageGroup == "auto")
            {
                lastAutoState = autoStateKey;
                lastAutoTime = menu.runtime.state.core.playTimeSeconds;
                autoPending = false;
            }
            else
            {
                menu.ShowNotify("Игра сохранена.", menu.Button(menu.load, "Back"));
            }
        }
        else
        {
            CancelAutoAttempt(storageGroup);
            Error("Не удалось сохранить игру: " + (png == "" ? "не получена миниатюра" : error));
        }
    }

    void CancelAutoAttempt(const String &in storageGroup)
    {
        if (storageGroup == "auto")
        {
            autoPending = false;
            lastAutoTime = menu.runtime.state.core.playTimeSeconds;
        }
    }

    void BeginLoad(const String &in storageGroup, const String &in id)
    {
        SaveSystem::Instance().CloseSlot(storageGroup, id);
        SaveSlot@ slot = SaveSystem::Instance().OpenSlot(storageGroup, id);
        if (slot is null || !slot.GetMetadata().Has("slotId"))
        {
            Error("Не удалось прочитать сохранение: " + SaveSystem::Instance().GetError());
            return;
        }
        if (!slot.GetMetadata().Has("schemaVersion") || slot.GetMetadata().Get("schemaVersion").GetInt() != 1 ||
            !slot.HasState() || !ThumbnailValid(slot.GetFile("thumbnail.png")) ||
            slot.GetMetadata().Get("payloadLength").GetInt() > 64 * 1024 * 1024)
        {
            Error("Сохранение не содержит допустимого игрового состояния или миниатюры 384×216 RGB PNG.");
            return;
        }
        candidateStoryResource = slot.GetMetadata().Get("storyResource").GetString();
        if (!AllowedStory(candidateStoryResource))
        {
            Error("Неизвестный источник сценария в сохранении.");
            return;
        }
        @candidateStory = JsonValue();
        if (!candidateStory.LoadResource(candidateStoryResource))
        {
            Error("Не удалось загрузить реестр сценария.");
            return;
        }
        if (slot.GetMetadata().Get("contentVersion").GetString() != candidateStory.View().Get("contentVersion").GetString())
        {
            Error("Сохранение несовместимо с этой версией сценария.");
            return;
        }
        @candidate = NovelState();
        if (!DecodeState(slot.GetState(), candidate) ||
            !NovelSnapshotValidation::Validate(candidate, candidateStory.View(), menu.runtime.definitions.View(), menu.runtime.speakers, menu.runtime.audio.paths))
        {
            Error("Сохранение содержит недопустимое состояние или неподдерживаемую версию.");
            return;
        }
        recoveryTrace = slot.WasRecovered() ? "RECOVERED " + storageGroup + "/" + id : "CURRENT " + storageGroup + "/" + id;
        @staging = menu.novel.GetOrCreateChild("LoadCandidate");
        preparedView.Build(staging, menu.gameObject.GetComponent("Behaviour"));
        @preparedPresentation.view = preparedView;
        @preparedPresentation.audio = menu.runtime.audio;
        preparedPresentation.Prepare(candidate.core.presentation);
        DialogueProgram program;
        program.Compile(candidate.core.presentation.text, candidate.core.presentation.autoWait);
        preparedView.Dialogue(candidate.core.presentation, program, menu.runtime.speakers.at(candidate.core.presentation.speakerId));
        preparedView.Choices(candidate.core.presentation.choices, candidate.core.phase == "WaitingChoice");
        busy = true;
        operation = "load_prepare";
        elapsed = 0;
        Refresh();
    }

    void FinishLoad()
    {
        preparedPresentation.Prepare(candidate.core.presentation);
        if (preparedPresentation.waitingTextures)
        {
            return;
        }
        NovelAudioState previousAudio;
        if (menu.runtime.state !is null)
        {
            previousAudio = menu.runtime.state.core.audio;
            menu.runtime.audio.Update(previousAudio, 0);
        }
        if (!menu.runtime.audio.Restore(candidate.core.audio, false))
        {
            menu.runtime.audio.Restore(previousAudio);
            staging.Destroy();
            @staging = null;
            busy = false;
            operation = "";
            Refresh();
            Error("Не удалось подготовить аудио: " + menu.runtime.audio.diagnostic);
            return;
        }
        if (!preparedView.root.MoveToTree(menu.novel))
        {
            menu.runtime.audio.Restore(previousAudio);
            preparedView.root.Destroy();
            staging.Destroy();
            @staging = null;
            busy = false;
            operation = "";
            Refresh();
            Error("Не удалось перенести восстановленное представление в иерархию сцены.");
            return;
        }
        menu.runtime.view.root.Destroy();
        staging.Destroy();
        @staging = null;
        menu.runtime.view = preparedView;
        @menu.runtime.story = candidateStory;
        menu.runtime.storyResource = candidateStoryResource;
        @menu.runtime.commands = menu.runtime.story.View().Get("commands");
        menu.runtime.endingTargets.clear();
        JsonValueView@ labels = menu.runtime.story.View().Get("labels");
        for (uint i = 0; i < labels.GetCount(); ++i)
        {
            String label = labels.GetKey(i);
            if (label.length() > 7 && label.substring(label.length() - 7, 7) == "_ending")
            {
                menu.runtime.endingTargets.set(labels.Get(label).GetString(), label);
            }
        }
        @menu.runtime.state = candidate;
        menu.inGame = true;
        menu.gameMenuOpen = false;
        menu.main.SetEnabled(false);
        menu.load.SetEnabled(false);
        @menu.submenu = null;
        menu.TabBackgroundOpacity(0);
        menu.Child(menu.novel, "Background").SetEnabled(false);
        menu.music.Stop();
        menu.runtime.view.root.SetEnabled(true);
        menu.runtime.FinishRestore();
        menu.inputBarrier = 0.1f;
        menu.runtime.wasPaused = true;
        MenuSession::activeScreen = "Story";
        busy = false;
        operation = "";
        autoPending = false;
        lastAutoTime = candidate.core.playTimeSeconds;
        Refresh();
        if (recoveryTrace.substring(0, 9) == "RECOVERED")
        {
            menu.ShowNotify("Восстановлена предыдущая исправная версия сохранения.", menu.Button(menu.quickMenu, "Save"));
        }
    }

    void MarkProfile()
    {
        profileDelay = 0.5f;
    }

    String AutoKey()
    {
        NovelCore core;
        core = menu.runtime.state.core;
        core.playTimeSeconds = 0;
        return SaveSystem::Instance().ComputeSha256(SerializeScriptValue(core));
    }

    bool ValidProfile(MenuProfile@ profile)
    {
        MenuSettings@ s = profile.settings;
        if (!(profile.schemaVersion == 1 && profile.readCommandIds.size() <= 100000 &&
            s.music_volume >= 0 && s.music_volume <= 1 && s.sfx_volume >= 0 && s.sfx_volume <= 1 &&
            s.voice_volume >= 0 && s.voice_volume <= 1 && s.text_cps >= 0 && s.text_cps <= 200 &&
            s.afm_time >= 0 && s.afm_time <= 60))
        {
            return false;
        }
        Map<String, bool> seen;
        for (uint i = 0; i < profile.readCommandIds.size(); ++i)
        {
            String id = profile.readCommandIds[i];
            if (id == "" || id.length() > 128 || seen.contains(id))
            {
                return false;
            }
            seen.set(id, true);
        }
        return true;
    }

    void LoadProfile()
    {
        JsonValue@ entries = SaveSystem::Instance().EnumerateSlots("profile");
        SaveSlot@ slot = SaveSystem::Instance().OpenSlot("profile", "main");
        if (slot is null)
        {
            profileWritable = false;
            diagnostic = "Профиль не загружен: " + SaveSystem::Instance().GetError();
            return;
        }
        if (entries.View().GetCount() > 0)
        {
            MenuProfile candidateProfile;
            candidateProfile.schemaVersion = 0;
            if (!slot.GetMetadata().Has("schemaVersion") || slot.GetMetadata().Get("schemaVersion").GetInt() != 1 ||
                !DecodeProfile(slot.GetState(), candidateProfile) || !ValidProfile(candidateProfile))
            {
                profileWritable = false;
                diagnostic = "Профиль содержит недопустимые настройки; исходный файл сохранён.";
                return;
            }
            MenuSession::profile = candidateProfile;
        }
        lastProfile = entries.View().GetCount() > 0 ? SerializeScriptValue(MenuSession::profile) : "";
        if (entries.View().GetCount() == 0)
        {
            MarkProfile();
        }
    }

    bool FlushProfile(bool showError = true)
    {
        if (!profileWritable)
        {
            return false;
        }
        String encoded = SerializeScriptValue(MenuSession::profile);
        if (encoded == lastProfile && profileDelay < 0)
        {
            return true;
        }
        JsonValue document;
        SaveSlot@ slot = SaveSystem::Instance().OpenSlot("profile", "main");
        if (slot is null || !document.Parse(encoded) || !slot.SetState(document))
        {
            diagnostic = "Не удалось подготовить профиль: " + SaveSystem::Instance().GetError();
            profileDelay = -1;
            if (showError && menu.modal is null)
            {
                Error(diagnostic);
            }
            return false;
        }
        slot.SetMetadata(Metadata(false, "profile-v1", "", 0));
        if (!SaveSystem::Instance().FlushSlot("profile", "main"))
        {
            diagnostic = "Не удалось сохранить профиль: " + SaveSystem::Instance().GetError();
            profileDelay = -1;
            if (showError && menu.modal is null)
            {
                Error(diagnostic);
            }
            return false;
        }
        lastProfile = encoded;
        profileDelay = -1;
        return true;
    }

    void Update(float dt)
    {
        if (!configured)
        {
            return;
        }
        if (profileDelay >= 0 && !busy)
        {
            profileDelay -= dt;
            if (profileDelay <= 0)
            {
                FlushProfile();
            }
        }
        if (busy)
        {
            elapsed += dt;
            if (elapsed > 15)
            {
                if (operation == "load_prepare")
                {
                    staging.Destroy();
                    @staging = null;
                    busy = false;
                    operation = "";
                    Refresh();
                    Error("Ресурсы сохранения не удалось подготовить за 15 секунд.");
                }
                else
                {
                    CancelAutoAttempt(queuedGroup);
                    queuedGroup = "";
                    EndCapture();
                    Error("Не удалось получить игровой кадр для миниатюры.");
                }
                return;
            }
            if (operation == "load_prepare")
            {
                FinishLoad();
            }
            else if (operation == "capture_frame")
            {
                ++frames;
                if (frames >= 3)
                {
                    if (capture.Request())
                    {
                        operation = "capture_readback";
                    }
                    else
                    {
                        Publish("");
                    }
                }
            }
            else if (operation == "capture_readback" && capture.IsReady())
            {
                Publish(capture.FetchPng(384, 216));
            }
            return;
        }
        if ((openAfterYield || queuedGroup != "") && menu.inGame && menu.runtime.state !is null &&
            menu.runtime.PhaseName() == "Ready" && menu.modal is null)
        {
            menu.runtime.presentation.Prepare(menu.runtime.state.core.presentation);
            if (!menu.runtime.presentation.waitingTextures)
            {
                menu.runtime.RunReady();
            }
        }
        if (openAfterYield && CanSave() && menu.modal is null)
        {
            openAfterYield = false;
            Open(true);
            return;
        }
        if (queuedGroup != "" && CanSave() && menu.modal is null)
        {
            BeginSave();
            return;
        }
        if (menu.inGame && !menu.gameMenuOpen && menu.modal is null && Input::Instance().IsAppFocused() && CanSave())
        {
            bool timed = menu.runtime.state.core.playTimeSeconds - lastAutoTime >= 300;
            if (!autoPending && !timed)
            {
                return;
            }
            String stateKey = AutoKey();
            if ((autoPending || timed) && stateKey != lastAutoState)
            {
                int64 sequence = NextSequence("auto");
                queuedGroup = "auto";
                queuedSlot = "a" + Two(uint((sequence - 1) % 6 + 1));
                BeginSave();
            }
            else if (autoPending)
            {
                autoPending = false;
            }
        }
    }
}
