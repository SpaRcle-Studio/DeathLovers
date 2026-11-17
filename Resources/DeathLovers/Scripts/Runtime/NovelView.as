//
// Created by Codex on 17.11.2026.
//

#include "DialogueProgram.as"

class NovelVisualSlot
{
    GameObject@ object;
    Sprite@ image;
    TextMesh@ text;
    UIButton@ button;
    String resource;
    String caption;
    NovelVisualSlot@ next;
}

class NovelView
{
    GameObject@ root;
    GameObject@ adv;
    GameObject@ nvl;
    GameObject@ choiceRoot;
    TextMesh@ dialogue;
    TextMesh@ speaker;
    TextMesh@ indicator;
    NovelVisualSlot@ background;
    NovelVisualSlot@ backgroundOld;
    NovelVisualSlot@ characters;
    NovelVisualSlot@ choices;
    NovelVisualSlot@ nvlEntries;
    UIScrollRect@ nvlScroll;
    UIButton@ advanceButton;
    bool choicesActive = false;
    GameObject@ nvlContent;

    FVector2 Vec(float x, float y)
    {
        FVector2 result;
        result.x = x;
        result.y = y;
        return result;
    }

    void Priority(GameObject@ object, int order)
    {
        cast<TransformRect@>(object.GetTransform()).localPriority = order;
    }

    GameObject@ Rect(GameObject@ parent, const String &in name, float x, float y, float w, float h)
    {
        GameObject@ object = parent.GetOrCreateChild(name);
        @object.transform = TransformRect();
        TransformRect@ rect = cast<TransformRect@>(object.GetTransform());
        RectAnchors anchors;
        anchors.min = Vec(0, 1);
        anchors.max = Vec(0, 1);
        rect.SetAnchors(anchors);
        rect.SetPivot(Vec(0, 1));
        rect.SetSize(Vec(w, h));
        rect.SetAnchoredPosition(Vec(x, -y));
        return object;
    }

    TextMesh@ Label(GameObject@ object, const String &in value)
    {
        TextMesh@ text = cast<TextMesh@>(object.GetOrCreateComponent("TextMesh"));
        text.SetMaterial("DeathLovers/Materials/RuntimeText.mat");
        text.SetFontPath("DeathLovers/Fonts/Pangolin.font");
        text.fontSize = 33.0f;
        text.SetText(value);
        return text;
    }

    NovelVisualSlot@ Image(GameObject@ parent, const String &in name)
    {
        NovelVisualSlot slot;
        @slot.object = Rect(parent, name, 0, 0, 1920, 1080);
        @slot.image = cast<Sprite@>(slot.object.GetOrCreateComponent("Sprite"));
        slot.image.SetMaterial("Engine/Materials/UI/ui.mat");
        slot.image.spriteMode = SpriteMode::Simple;
        return slot;
    }

    NovelVisualSlot@ At(NovelVisualSlot@ first, uint index)
    {
        NovelVisualSlot@ slot = first;
        for (uint i = 0; i < index && slot !is null; ++i)
        {
            @slot = slot.next;
        }
        return slot;
    }

    void Build(GameObject@ novel, Component@ receiver)
    {
        @root = Rect(novel, "Runtime", 0, 0, 1920, 1080);
        root.SetEnabled(false);
        NovelVisualSlot@ black = Image(root, "Black");
        cast<TransformRect>(black.object.GetTransform()).set_localPriority(-100);
        black.image.SetMaterial("DeathLovers/Materials/RuntimeBlack.mat");
        @backgroundOld = Image(root, "BackgroundOld");
        @background = Image(root, "Background");
        Priority(backgroundOld.object, 0);
        Priority(background.object, 1);
        NovelVisualSlot@ previous;
        for (uint i = 0; i < 3; ++i)
        {
            NovelVisualSlot@ old = Image(root, "CharacterOld" + RuntimeValues::Index(i));
            NovelVisualSlot@ layer = Image(root, "Character" + RuntimeValues::Index(i));
            Priority(old.object, 10 + int(i) * 2);
            Priority(layer.object, 11 + int(i) * 2);
            @layer.next = old;
            if (previous is null)
            {
                @characters = layer;
            }
            else
            {
                @previous.next = layer;
            }
            @previous = layer.next;
        }
        // Native UI routing owns pointer/keyboard activation and consumption.
        GameObject@ advance = Rect(root, "Advance", 0, 0, 1920, 1080);
        Priority(advance, 20);
        @advanceButton = cast<UIButton@>(advance.GetOrCreateComponent("UIButton"));
        advanceButton.SetClickReceiver(receiver, "AdvanceStory");
        @adv = Rect(root, "ADV", 0, 800, 1920, 280);
        Priority(adv, 30);
        NovelVisualSlot@ window = Image(adv, "Window");
        Priority(window.object, 0);
        cast<TransformRect@>(window.object.GetTransform()).SetSize(Vec(1920, 280));
        window.image.SetTexturePath("DeathLovers/UI/textbox.png");
        @speaker = Label(Rect(adv, "Speaker", 360, 12, 1200, 50), "");
        @dialogue = Label(Rect(adv, "Text", 360, 62, 1200, 190), "");
        @indicator = Label(Rect(adv, "Complete", 1580, 220, 100, 50), "▼");
        @nvl = Rect(root, "NVL", 360, 15, 1170, 1010);
        Priority(nvl, 30);
        nvl.GetOrCreateComponent("RectMask2D");
        @nvlScroll = cast<UIScrollRect@>(nvl.GetOrCreateComponent("UIScrollRect"));
        nvlScroll.horizontal = false;
        nvlScroll.focusable = false;
        @nvlContent = Rect(nvl, "Content", 0, 0, 1170, 1010);
        nvlScroll.SetContent(nvlContent);
        nvlScroll.SetViewport(nvl);
        @previous = null;
        for (uint i = 0; i < 6; ++i)
        {
            NovelVisualSlot slot;
            @slot.object = Rect(nvlContent, "Entry" + RuntimeValues::Index(i), 0, float(i) * 188, 1170, 173);
            @slot.text = Label(slot.object, "");
            if (previous is null)
            {
                @nvlEntries = slot;
            }
            else
            {
                @previous.next = slot;
            }
            @previous = slot;
        }
        GameObject@ nvlAdvance = Rect(nvl, "Advance", 0, 0, 1170, 1010);
        UIButton@ nvlButton = cast<UIButton@>(nvlAdvance.GetOrCreateComponent("UIButton"));
        nvlButton.focusable = false;
        nvlButton.SetClickReceiver(receiver, "AdvanceStory");
        @choiceRoot = Rect(root, "Choices", 360, 260, 1200, 600);
        Priority(choiceRoot, 50);
        @previous = null;
        for (uint i = 0; i < 8; ++i)
        {
            NovelVisualSlot slot;
            @slot.object = Rect(choiceRoot, "Choice" + RuntimeValues::Index(i), 0, float(i) * 150, 1200, 117);
            @slot.image = cast<Sprite@>(slot.object.GetOrCreateComponent("Sprite"));
            slot.image.SetMaterial("Engine/Materials/UI/ui.mat");
            slot.image.SetTexturePath("DeathLovers/UI/button/choice_idle_background.png");
            @slot.text = Label(Rect(slot.object, "Label", 90, 8, 1020, 101), "");
            slot.text.horizontalAlignment = TextAlignmentHorizontal::Center;
            slot.text.verticalAlignment = TextAlignmentVertical::Middle;
            @slot.button = cast<UIButton@>(slot.object.GetOrCreateComponent("UIButton"));
            slot.button.SetClickReceiver(receiver, "Choose" + RuntimeValues::Index(i));
            if (previous is null)
            {
                @choices = slot;
            }
            else
            {
                @previous.next = slot;
            }
            @previous = slot;
        }
        root.SetEnabled(false);
    }

    void Texture(NovelVisualSlot@ slot, const String &in id, const String &in path, bool visible = true)
    {
        bool enabled = visible && id != "" && id != "hidden" && id != "builtin:black";
        slot.object.SetEnabled(enabled);
        if (enabled && slot.resource != id)
        {
            slot.image.SetTexturePath(path);
            slot.resource = id;
        }
    }

    void Dialogue(JsonValue@ p, DialogueProgram@ program, JsonValue@ definition)
    {
        bool isNvl = p.Get("mode").GetString() == "NVL";
        adv.SetEnabled(!isNvl && p.Get("dialogueVisible").GetBool());
        nvl.SetEnabled(isNvl && p.Get("dialogueVisible").GetBool());
        if (!isNvl)
        {
            program.Paint(dialogue);
            speaker.SetText(definition.Get("name").GetString());
            TextStyle color;
            color.end = speaker.GetGraphemeCount();
            color.color.x = float(definition.Get("color").At(0).GetNumber());
            color.color.y = float(definition.Get("color").At(1).GetNumber());
            color.color.z = float(definition.Get("color").At(2).GetNumber());
            if (color.end > 0)
            {
                speaker.AddStyle(color);
            }
        }
        else
        {
            JsonValue@ lines = p.Get("nvl");
            uint first = lines.GetCount() > 6 ? lines.GetCount() - 6 : 0;
            uint visibleLines = lines.GetCount() - first;
            float contentHeight = visibleLines > 0 ? float(visibleLines) * 188 - 15 : 0;
            TransformRect@ contentRect = cast<TransformRect@>(nvlContent.GetTransform());
            contentRect.SetSize(Vec(1170, contentHeight > 1010 ? contentHeight : 1010));
            for (uint i = 0; i < 6; ++i)
            {
                NovelVisualSlot@ slot = At(nvlEntries, i);
                slot.object.SetEnabled(first + i < lines.GetCount());
                if (first + i < lines.GetCount())
                {
                    DialogueProgram line;
                    line.Compile(lines.At(first + i).Get("text").GetString(), false);
                    line.Paint(slot.text);
                }
            }
            nvlScroll.SetNormalizedPosition(Vec(0, 1));
        }
        Progress(p);
    }

    void Progress(JsonValue@ p)
    {
        uint count = uint(p.Get("visibleIndex").GetInt());
        if (p.Get("mode").GetString() == "NVL")
        {
            uint total = p.Get("nvl").GetCount();
            if (total > 0)
            {
                At(nvlEntries, total > 6 ? 5 : total - 1).text.SetVisibleGraphemeCount(count);
            }
        }
        else
        {
            dialogue.SetVisibleGraphemeCount(count);
        }
        indicator.SetText(p.Get("inputWait").GetBool() ? "…" : p.Get("fullyShown").GetBool() ? "▼" : "");
    }

    void Effects(float time)
    {
        if (choicesActive)
        {
            for (NovelVisualSlot@ slot = choices; slot !is null; @slot = slot.next)
            {
                UIControlState state = slot.button.GetState();
                bool hovered = state == UIControlState::Hovered || state == UIControlState::Selected || state == UIControlState::Pressed;
                String texture = hovered ? "DeathLovers/UI/button/choice_hover_background.png" : "DeathLovers/UI/button/choice_idle_background.png";
                if (slot.resource != texture)
                {
                    slot.image.SetTexturePath(texture);
                    slot.resource = texture;
                    DialogueProgram label;
                    label.Compile(slot.caption, false);
                    label.Paint(slot.text);
                    TextStyle color;
                    color.end = slot.text.GetGraphemeCount();
                    float value = hovered ? 1 : 0.533333f;
                    color.color.x = value;
                    color.color.y = value;
                    color.color.z = value;
                    if (color.end > 0)
                    {
                        slot.text.AddStyle(color);
                    }
                }
            }
        }
        dialogue.SetCharacterEffect(time, 0, 0, 0);
        for (NovelVisualSlot@ slot = nvlEntries; slot !is null; @slot = slot.next)
        {
            slot.text.SetCharacterEffect(time, 0, 0, 0);
        }
    }

    void Choices(JsonValue@ options, bool active)
    {
        choicesActive = active;
        advanceButton.SetInteractable(!active);
        choiceRoot.SetEnabled(active);
        float totalHeight = 0;
        for (uint i = 0; i < 8; ++i)
        {
            NovelVisualSlot@ slot = At(choices, i);
            slot.object.SetEnabled(active && i < options.GetCount());
            if (active && i < options.GetCount())
            {
                TransformRect@ rect = cast<TransformRect@>(slot.object.GetTransform());
                TransformRect@ labelRect = cast<TransformRect@>(slot.text.GetGameObject().GetTransform());
                slot.resource = "";
                DialogueProgram label;
                label.Compile(options.At(i).Get("normalizedText").GetString(), false);
                slot.caption = options.At(i).Get("normalizedText").GetString();
                label.Paint(slot.text);
                float textHeight = slot.text.GetTextBounds().h;
                float height = textHeight + 24;
                if (height < 70)
                {
                    height = 70;
                }
                rect.SetAnchoredPosition(Vec(0, -totalHeight));
                rect.SetSize(Vec(1200, height));
                labelRect.SetSize(Vec(1020, height - 16));
                totalHeight += height + 33;
            }
        }
        totalHeight = totalHeight > 0 ? totalHeight - 33 : 0;
        cast<TransformRect@>(choiceRoot.GetTransform()).SetAnchoredPosition(Vec(360, -(540 - totalHeight * 0.5f)));
        if (active && options.GetCount() > 0)
        {
            choices.button.Focus();
        }
    }

    void FocusNarrative(bool choice)
    {
        if (choice)
        {
            choices.button.Focus();
        }
        else
        {
            advanceButton.Focus();
        }
    }
}
