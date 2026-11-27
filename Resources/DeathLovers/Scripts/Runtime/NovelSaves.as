//
// Created by Codex on 25.11.2026.
//

#include "NovelSaveFormat.as"

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
    String candidateEntry;
    String autoStateKey;
    bool openAfterYield = false;
    String listedGroup;
    bool listingDirty = true;
    bool quickListingDirty = true;
    bool hasQuickSave = false;
    String listingError;
    Map<String, String> previewKeys;
    JsonValue@ manualEntries;
    JsonValue@ autoEntries;
    JsonValue@ quickEntries;
    Map<String, String> listingErrors;

    JsonValue@ CachedListing(const String &in storageGroup)
    {
        if (storageGroup == "manual") return manualEntries;
        if (storageGroup == "auto") return autoEntries;
        return quickEntries;
    }

    void CacheListing(const String &in storageGroup, JsonValue@ entries)
    {
        if (storageGroup == "manual") @manualEntries = entries;
        else if (storageGroup == "auto") @autoEntries = entries;
        else @quickEntries = entries;
    }

    JsonValue@ ReadListing(const String &in storageGroup)
    {
        JsonValue@ entries = CachedListing(storageGroup);
        if (entries is null)
        {
            JsonValue@ all = SaveSystem::Instance().EnumerateSlotPreviews(storageGroup);
            listingErrors.set(storageGroup, SaveSystem::Instance().GetError());
            @entries = JsonValue();
            entries.MakeArray();
            for (uint i = 0; i < all.View().GetCount(); ++i)
            {
                JsonValueView@ record = all.View().At(i);
                if (record.Has("schemaVersion") && record.Get("schemaVersion").GetInt() == NovelSaveFormat::Version)
                    entries.Append(record.Clone());
            }
            CacheListing(storageGroup, entries);
        }
        return entries;
    }

    void CacheSavedSlot(const String &in storageGroup, const String &in id, SaveSlot@ slot, const String &in png)
    {
        JsonValue@ entries = CachedListing(storageGroup);
        if (entries !is null)
        {
            JsonValue updated;
            updated.MakeArray();
            for (uint i = 0; i < entries.View().GetCount(); ++i)
            {
                if (entries.View().At(i).Get("slotId").GetString() != id)
                {
                    updated.Append(entries.View().At(i).Clone());
                }
            }
            JsonValue@ record = slot.GetMetadata().Clone();
            JsonValue recovered;
            recovered.SetBool(false);
            record.Set("recovered", recovered);
            updated.Append(record);
            CacheListing(storageGroup, updated);
            if (listedGroup == storageGroup)
            {
                @listing = CachedListing(storageGroup);
                for (uint i = 0; i < 6; ++i)
                {
                    if (SlotId(i) == id)
                    {
                        GameObject@ thumbnail = menu.Child(menu.Child(grid, "Slot" + RuntimeValues::Index(i)), "Thumbnail");
                        cast<Sprite@>(thumbnail.GetComponent("Sprite")).SetTextureData(png);
                        previewKeys.set(RuntimeValues::Index(i), storageGroup + "/" + id + "/" + record.View().ToJson());
                    }
                }
            }
        }
        if (storageGroup == "quick")
        {
            hasQuickSave = true;
            quickListingDirty = false;
        }
    }

    void InvalidateListings(bool clearPreviews = true)
    {
        listingDirty = true;
        quickListingDirty = true;
        if (clearPreviews) previewKeys.clear();
        @manualEntries = null;
        @autoEntries = null;
        @quickEntries = null;
        listingErrors.clear();
    }

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
        if (listingDirty || listedGroup != group)
        {
            @listing = ReadListing(group);
            listingError = listingErrors.contains(group) ? listingErrors.at(group) : "";
            listedGroup = group;
            listingDirty = false;
        }
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
            String previewIndex = RuntimeValues::Index(i);
            String previewKey;
            if (exists)
            {
                previewKey = group + "/" + id + "/" + record.ToJson();
            }
            if (!exists)
            {
                previewKeys.set(previewIndex, "");
            }
            else if (!previewKeys.contains(previewIndex) || previewKeys.at(previewIndex) != previewKey)
            {
                String png = SaveSystem::Instance().ReadSlotPreviewFile(group, id, "thumbnail.png");
                if (ThumbnailValid(png))
                {
                    cast<Sprite@>(thumbnail.GetComponent("Sprite")).SetTextureData(png);
                    previewKeys.set(previewIndex, previewKey);
                }
                else
                {
                    thumbnail.SetEnabled(false);
                }
            }
        }
        if (quickListingDirty)
        {
            JsonValue@ quickEntries;
            if (group == "quick")
            {
                @quickEntries = listing;
            }
            else
            {
                @quickEntries = ReadListing("quick");
            }
            hasQuickSave = quickEntries.View().GetCount() > 0;
            quickListingDirty = false;
        }
        menu.Button(menu.quickMenu, "QuickLoad").SetInteractable(!busy && hasQuickSave);
    }

    String Latest(const String &in storageGroup)
    {
        JsonValue@ entries = ReadListing(storageGroup);
        int64 sequence = -1;
        String id;
        for (uint i = 0; i < entries.View().GetCount(); ++i)
        {
            JsonValueView@ record = entries.View().At(i);
            if (record.Get("sequence").GetInt() > sequence)
            {
                sequence = record.Get("sequence").GetInt();
                id = record.Get("slotId").GetString();
            }
        }
        return id;
    }

    void BeginQuickLoad(const String &in newestId)
    {
        if (ReadLoadCandidate("quick", newestId))
        {
            BeginPreparedLoad();
            return;
        }
        String newestError = diagnostic;
        JsonValue@ entries = ReadListing("quick");
        Map<String, bool> checked;
        checked.set(newestId, true);
        for (uint attempt = 0; attempt < entries.View().GetCount(); ++attempt)
        {
            int64 sequence = -1;
            int selected = -1;
            for (uint i = 0; i < entries.View().GetCount(); ++i)
            {
                JsonValueView@ record = entries.View().At(i);
                if (!checked.contains(record.Get("slotId").GetString()) && record.Get("sequence").GetInt() > sequence)
                {
                    sequence = record.Get("sequence").GetInt();
                    selected = int(i);
                }
            }
            if (selected < 0) break;
            String id = entries.View().At(uint(selected)).Get("slotId").GetString();
            if (ReadLoadCandidate("quick", id))
            {
                BeginPreparedLoad();
                return;
            }
            checked.set(id, true);
        }
        @candidate = null;
        Error(newestError);
    }

    bool AllowedEntry(const String &in entry)
    {
        return entry == "Story::start" || (menu.developmentRuntime &&
            (entry == "Story::fixture_runtime_start" || entry == "Story::fixture_saves_start"));
    }

    int64 NextSequence(const String &in storageGroup)
    {
        JsonValue@ entries = ReadListing(storageGroup);
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
        InvalidateListings(false);
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
        if (action == "quickload")
        {
            BeginQuickLoad(id);
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
            InvalidateListings();
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
            Confirm("quickload", "quick", id);
        }
        else
        {
            BeginQuickLoad(id);
        }
    }

    void TextField(JsonValue@ object, const String &in key, const String &in text)
    {
        JsonValue value;
        value.SetString(text);
        object.Set(key, value);
    }

    void IntegerField(JsonValue@ object, const String &in key, int64 number)
    {
        JsonValue value;
        value.SetInt(number);
        object.Set(key, value);
    }

    JsonValue@ Metadata(bool thumbnail, const String &in content, const String &in position, double time)
    {
        JsonValue result;
        result.MakeObject();
        IntegerField(result, "schemaVersion", NovelSaveFormat::Version);
        TextField(result, "contentVersion", content);
        TextField(result, "position", position);
        TextField(result, "sceneTitle", position);
        JsonValue value;
        value.SetNumber(time);
        result.Set("playTimeSeconds", value);
        value.SetBool(thumbnail);
        result.Set("hasThumbnail", value);
        return result;
    }

    /// "Story::label_canteen" -> "label_canteen"
    String SceneTitle(const String &in label)
    {
        uint scope = 0;
        for (uint i = 0; i + 1 < label.length(); ++i)
        {
            if (label.byteAt(i) == 58 && label.byteAt(i + 1) == 58)
            {
                scope = i + 2;
            }
        }
        return label.substring(scope, label.length() - scope);
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
        NovelCore saved;
        saved = menu.runtime.state.core;
        menu.runtime.audio.Update(saved.audio, 0);
        JsonValue@ document = NovelSaveFormat::State(saved);
        payload = document;
        @metadata = Metadata(true, saved.contentVersion, saved.position, saved.playTimeSeconds);
        TextField(metadata, "storyEntry", menu.runtime.storyEntry);
        autoStateKey = AutoKey();
        IntegerField(metadata, "sequence", NextSequence(queuedGroup));
        TextField(metadata, "sceneTitle", SceneTitle(saved.Label()));
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
        if (slot !is null && ThumbnailValid(png) && slot.SetState(payload) && slot.SetFile("thumbnail.png", png))
        {
            slot.SetMetadata(metadata);
            saved = SaveSystem::Instance().FlushSlot(storageGroup, id);
        }
        String error = SaveSystem::Instance().GetError();
        if (saved)
        {
            CacheSavedSlot(storageGroup, id, slot, png);
        }
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
        if (!ReadLoadCandidate(storageGroup, id))
        {
            @candidate = null;
            Error(diagnostic);
            return;
        }
        BeginPreparedLoad();
    }

    bool ReadLoadCandidate(const String &in storageGroup, const String &in id)
    {
        SaveSystem::Instance().CloseSlot(storageGroup, id);
        SaveSlot@ slot = SaveSystem::Instance().OpenSlot(storageGroup, id);
        if (slot is null || !slot.GetMetadata().Has("slotId"))
        {
            diagnostic = "Не удалось прочитать сохранение: " + SaveSystem::Instance().GetError();
            SaveSystem::Instance().CloseSlot(storageGroup, id);
            return false;
        }
        if (!slot.GetMetadata().Has("schemaVersion") || slot.GetMetadata().Get("schemaVersion").GetInt() != NovelSaveFormat::Version ||
            !slot.HasState() || !ThumbnailValid(slot.GetFile("thumbnail.png")) ||
            slot.GetMetadata().Get("payloadLength").GetInt() > 64 * 1024 * 1024)
        {
            diagnostic = "Сохранение не содержит допустимого игрового состояния или миниатюры 384×216 RGB PNG.";
            SaveSystem::Instance().CloseSlot(storageGroup, id);
            return false;
        }
        candidateEntry = slot.GetMetadata().Get("storyEntry").GetString();
        if (!AllowedEntry(candidateEntry) || FindCoroutineEntry(candidateEntry) is null)
        {
            diagnostic = "Неизвестный источник сценария в сохранении.";
            SaveSystem::Instance().CloseSlot(storageGroup, id);
            return false;
        }
        if (slot.GetMetadata().Get("contentVersion").GetString() != Story::Version)
        {
            diagnostic = "Сохранение несовместимо с этой версией сценария.";
            SaveSystem::Instance().CloseSlot(storageGroup, id);
            return false;
        }
        @candidate = NovelState();
        if (!NovelSaveFormat::ReadState(slot.GetState(), menu.runtime.definitions.View(), candidate))
        {
            diagnostic = "Сохранение содержит недопустимое состояние или неподдерживаемую версию.";
            SaveSystem::Instance().CloseSlot(storageGroup, id);
            return false;
        }
        // Includes a replay of the saved frames: a save whose position no longer exists in the script is rejected here.
        if (!menu.runtime.ValidateSnapshot(candidate))
        {
            diagnostic = "Сохранение не совпадает с текущей версией сценария.";
            SaveSystem::Instance().CloseSlot(storageGroup, id);
            return false;
        }
        recoveryTrace = slot.WasRecovered() ? "RECOVERED " + storageGroup + "/" + id : "CURRENT " + storageGroup + "/" + id;
        SaveSystem::Instance().CloseSlot(storageGroup, id);
        return true;
    }

    void BeginPreparedLoad()
    {
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
        menu.runtime.storyEntry = candidateEntry;
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
        JsonValue@ document = NovelSaveFormat::State(core);
        return SaveSystem::Instance().ComputeSha256(document.View().ToJson());
    }

    bool ValidProfile(MenuProfile@ profile)
    {
        MenuSettings@ s = profile.settings;
        if (!(profile.readLines.size() <= 1000000 &&
            s.music_volume >= 0 && s.music_volume <= 1 && s.sfx_volume >= 0 && s.sfx_volume <= 1 &&
            s.voice_volume >= 0 && s.voice_volume <= 1 && s.text_cps >= 0 && s.text_cps <= 200 &&
            s.afm_time >= 0 && s.afm_time <= 60))
        {
            return false;
        }
        Map<String, bool> seen;
        for (uint i = 0; i < profile.readLines.size(); ++i)
        {
            String id = profile.readLines[i];
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
        bool loaded = false;
        if (entries.View().GetCount() > 0 && slot.GetMetadata().Has("schemaVersion") &&
            slot.GetMetadata().Get("schemaVersion").GetInt() == NovelSaveFormat::Version)
        {
            MenuProfile candidateProfile;
            if (!NovelSaveFormat::ReadProfile(slot.GetState(), candidateProfile) || !ValidProfile(candidateProfile))
            {
                profileWritable = false;
                diagnostic = "Профиль содержит недопустимые настройки; исходный файл сохранён.";
                return;
            }
            MenuSession::profile = candidateProfile;
            loaded = true;
        }
        JsonValue@ document = NovelSaveFormat::Profile(MenuSession::profile);
        lastProfile = loaded ? document.View().ToJson() : "";
        if (!loaded) MarkProfile();
    }

    bool FlushProfile(bool showError = true)
    {
        if (!profileWritable)
        {
            return false;
        }
        JsonValue@ document = NovelSaveFormat::Profile(MenuSession::profile);
        String encoded = document.View().ToJson();
        if (encoded == lastProfile && profileDelay < 0)
        {
            return true;
        }
        SaveSlot@ slot = SaveSystem::Instance().OpenSlot("profile", "main");
        if (slot is null || !slot.SetState(document))
        {
            diagnostic = "Не удалось подготовить профиль: " + SaveSystem::Instance().GetError();
            profileDelay = -1;
            if (showError && menu.modal is null)
            {
                Error(diagnostic);
            }
            return false;
        }
        slot.SetMetadata(Metadata(false, "profile-v3", "", 0));
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
