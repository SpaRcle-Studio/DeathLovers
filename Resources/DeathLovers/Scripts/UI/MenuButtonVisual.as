//
// Created by Codex on 16.11.2026.
//

class MenuButtonVisual : ScriptBehaviour
{
    UIControl@ control;
    TextMesh@ label;
    UIControlState previous = UIControlState::Disabled;
    bool wasSelected = false;

    void Start()
    {
        @control = cast<UIControl@>(gameObject.GetComponent("UIButton"));
        @label = cast<TextMesh@>(gameObject.GetComponent("TextMesh"));
        previous = UIControlState::Disabled;
    }

    void Update(float dt)
    {
        UIControlState state = control.GetState();
        bool selected = gameObject.GetName() == MenuSession::activeScreen;
        if (state == previous && selected == wasSelected)
        {
            return;
        }
        previous = state;
        wasSelected = selected;
        label.ClearStyles();
        TextStyle color;
        color.begin = 0;
        color.end = label.GetGraphemeCount();
        bool active = state == UIControlState::Hovered || state == UIControlState::Selected || state == UIControlState::Pressed;
        color.color.x = active ? 0.4f : selected ? 1.0f : 0.533333f;
        color.color.y = active ? 0.878431f : selected ? 1.0f : 0.533333f;
        color.color.z = active ? 0.756863f : selected ? 1.0f : 0.533333f;
        color.color.w = state == UIControlState::Disabled ? 0.5f : 1.0f;
        label.AddStyle(color);
    }
}

class MenuOptionVisual : ScriptBehaviour
{
    UIControl@ control;
    TextMesh@ label;
    GameObject@ mark;
    GameObject@ emptyMark;
    UIControlState previous = UIControlState::Disabled;
    bool wasSelected = false;
    bool initialized = false;

    void Start()
    {
        @control = cast<UIControl@>(gameObject.GetComponent("UIButton"));
        @label = cast<TextMesh@>(gameObject.GetOrCreateChild("Label").GetComponent("TextMesh"));
        @mark = gameObject.GetOrCreateChild("Selected");
        @emptyMark = gameObject.GetOrCreateChild("Unselected");
        initialized = false;
    }

    bool Selected()
    {
        String name = gameObject.GetName();
        if (name == "Windowed")
        {
            return !ApplicationManager::Instance().GetApplication().GetEngine().IsFullscreen();
        }
        if (name == "Fullscreen")
        {
            return ApplicationManager::Instance().GetApplication().GetEngine().IsFullscreen();
        }
        if (name == "PixelVoice")
        {
            return MenuSession::profile.settings.pixel_voice;
        }
        if (name == "Mute")
        {
            return MenuSession::profile.settings.mute;
        }
        if (name == "SkipUnseen")
        {
            return MenuSession::profile.settings.skip_unseen;
        }
        if (name == "SkipChoices")
        {
            return MenuSession::profile.settings.skip_after_choices;
        }
        return MenuSession::profile.settings.skip_transitions;
    }

    void Update(float dt)
    {
        bool selected = Selected();
        UIControlState state = control.GetState();
        if (initialized && state == previous && selected == wasSelected)
        {
            return;
        }
        initialized = true;
        previous = state;
        wasSelected = selected;
        mark.SetEnabled(selected);
        emptyMark.SetEnabled(!selected);
        label.ClearStyles();
        TextStyle style;
        style.begin = 0;
        style.end = label.GetGraphemeCount();
        bool active = state == UIControlState::Hovered || state == UIControlState::Pressed || state == UIControlState::Selected;
        style.color.x = active ? 0.4f : selected ? 1.0f : 0.533333f;
        style.color.y = active ? 0.878431f : selected ? 1.0f : 0.533333f;
        style.color.z = active ? 0.756863f : selected ? 1.0f : 0.533333f;
        label.AddStyle(style);
    }
}
