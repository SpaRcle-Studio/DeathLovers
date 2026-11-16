//
// Created by Codex on 16.11.2026.
//

class MenuButtonVisual : ScriptBehaviour
{
    UIControl@ control;
    TextMesh@ label;
    UIControlState previous = UIControlState::Disabled;

    void Start()
    {
        @control = cast<UIControl@>(gameObject.GetComponent("UIButton"));
        @label = cast<TextMesh@>(gameObject.GetComponent("TextMesh"));
    }

    void Update(float dt)
    {
        UIControlState state = control.GetState();
        if (state == previous)
        {
            return;
        }
        previous = state;
        label.ClearStyles();
        TextStyle color;
        color.begin = 0;
        color.end = label.GetGraphemeCount();
        bool active = state == UIControlState::Hovered || state == UIControlState::Selected || state == UIControlState::Pressed;
        color.color.x = active ? 0.4f : 0.533333f;
        color.color.y = active ? 0.878431f : 0.533333f;
        color.color.z = active ? 0.756863f : 0.533333f;
        color.color.w = state == UIControlState::Disabled ? 0.5f : 1.0f;
        label.AddStyle(color);
    }
}
