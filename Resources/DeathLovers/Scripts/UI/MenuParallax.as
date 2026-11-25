//
// Created by Codex on 16.11.2026.
//

class MenuParallax : ScriptBehaviour
{
    Canvas@ canvas;
    TransformRect@ novel;
    TransformRect@ bg;
    TransformRect@ bg1;
    TransformRect@ bg2;
    TransformRect@ mid;
    TransformRect@ mid1;
    TransformRect@ mid2;
    TransformRect@ fg;
    float elapsed = 0;
    float nx = 0.5f;
    float ny = 0.5f;
    FVector2 neutralGravity;
    bool tiltInitialized = false;

    TransformRect@ Layer(GameObject@ background, const String &in name)
    {
        return cast<TransformRect@>(background.GetOrCreateChild(name).GetTransform());
    }

    void Start()
    {
        @canvas = cast<Canvas@>(gameObject.GetComponent("Canvas"));
        GameObject@ area = gameObject.GetOrCreateChild("Novel");
        @novel = cast<TransformRect@>(area.GetTransform());
        GameObject@ background = area.GetOrCreateChild("Background");
        @bg = Layer(background, "Bg");
        @bg1 = Layer(background, "Bg1");
        @bg2 = Layer(background, "Bg2");
        @mid = Layer(background, "Mid");
        @mid1 = Layer(background, "Mid1");
        @mid2 = Layer(background, "Mid2");
        @fg = Layer(background, "Fg");
    }

    float Clamp01(float value)
    {
        return value < 0 ? 0 : value > 1 ? 1 : value;
    }

    float Curve(float value)
    {
        float offset = value - 0.5f;
        float magnitude = offset < 0 ? -offset : offset;
        return offset * (1.0f - magnitude) * 0.002f;
    }

    void Move(TransformRect@ layer, float factor, float width, float height)
    {
        FVector2 offset;
        offset.x = Curve(nx) * factor * 0.4f * width;
        offset.y = -Curve(ny) * factor * 0.1f * height;
        layer.SetVisualOffset(offset);
    }

    void Update(float dt)
    {
        elapsed += dt;
        if (elapsed < 0.025f)
        {
            return;
        }
        while (elapsed >= 0.025f)
        {
            elapsed -= 0.025f;
        }
        FVector2 size = novel.GetLayoutSize();
        if (size.x <= 0 || size.y <= 0)
        {
            return;
        }
        if (!Input::Instance().IsAppFocused())
        {
            tiltInitialized = false;
            return;
        }
        if (ApplicationManager::Instance().GetApplication().GetPlatformType() == PlatformType::Android)
        {
            nx = 0.5f;
            ny = 0.5f;
            if (Input::Instance().HasDeviceGravity())
            {
                FVector2 gravity = Input::Instance().GetDeviceGravity();
                if (!tiltInitialized)
                {
                    neutralGravity = gravity;
                    tiltInitialized = true;
                }
                nx = Clamp01(0.5f + (gravity.x - neutralGravity.x));
                ny = Clamp01(0.5f - (gravity.y - neutralGravity.y));
            }
            else
            {
                tiltInitialized = false;
            }
        }
        else
        {
            FVector2 point = canvas.CanvasToLayoutPoint(novel, canvas.ScreenToCanvasSpace(Input::Instance().GetMousePos()));
            FRect rect = novel.layoutRect;
            nx = Clamp01((point.x - rect.x) / size.x);
            ny = Clamp01(1.0f - (point.y - rect.y) / size.y);
        }
        Move(bg, 0, size.x, size.y);
        Move(bg1, -20, size.x, size.y);
        Move(bg2, 40, size.x, size.y);
        Move(mid, -60, size.x, size.y);
        Move(mid1, 80, size.x, size.y);
        Move(mid2, -100, size.x, size.y);
        Move(fg, 120, size.x, size.y);
    }
}
