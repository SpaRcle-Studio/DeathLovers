//
// Created by Codex on 17.11.2026.
//

#include "NovelView.as"
#include "NovelAudio.as"

class NovelPresentation
{
    NovelView@ view;
    NovelAudio@ audio;

    void PaintBackground(JsonValue@ p)
    {
        JsonValue@ transition = p.Get("transition");
        String target = p.Get("background").GetString();
        String from = transition.Get("from").GetString();
        float duration = float(transition.Get("duration").GetNumber());
        float progress = duration > 0 ? float(transition.Get("elapsed").GetNumber()) / duration : 1;
        progress = progress > 1 ? 1 : progress;
        view.Texture(view.background, target, target == "builtin:black" ? "" : audio.Path(target));
        view.Texture(view.backgroundOld, from, from == "builtin:black" ? "" : audio.Path(from), progress < 1);
        String kind = transition.Get("kind").GetString();
        view.background.image.SetSubtreeOpacity(kind == "fade" ? (progress < 0.5f ? 0 : (progress - 0.5f) * 2) : progress);
        view.backgroundOld.image.SetSubtreeOpacity(kind == "fade" ? (progress < 0.5f ? 1 - progress * 2 : 0) : 1);
        FVector2 offset;
        if (kind == "vpunch" && progress < 1)
        {
            offset.y = MathUtils::Instance().Sin(progress * 31.4159265359f) * 15 * (1 - progress);
        }
        cast<TransformRect@>(view.background.object.GetTransform()).SetVisualOffset(offset);
    }

    String CharacterId(uint index)
    {
        return index == 0 ? "ch_p" : index == 1 ? "ch_w" : "ch_h";
    }

    void PlaceCharacter(NovelVisualSlot@ slot, JsonValue@ character)
    {
        TransformRect@ rect = cast<TransformRect@>(slot.object.GetTransform());
        FVector2 size = slot.image.GetTextureSize();
        JsonValue@ scale = character.Get("scale");
        size.x *= float(scale.At(0).GetNumber());
        size.y *= float(scale.At(1).GetNumber());
        rect.SetSize(size);
        FVector2 position;
        position.x = float(character.Get("position").At(0).GetNumber());
        position.y = -float(character.Get("position").At(1).GetNumber());
        rect.SetAnchoredPosition(position);
        FVector3 flip;
        flip.x = character.Get("flip").At(0).GetBool() ? -1 : 1;
        flip.y = character.Get("flip").At(1).GetBool() ? -1 : 1;
        flip.z = 1;
        rect.SetScale(flip);
        FVector2 bounce;
        if (character.Get("bounceActive").GetBool())
        {
            bounce.y = MathUtils::Instance().Sin(float(character.Get("bounceElapsed").GetNumber()) * 3.141592653589793f / 0.2f) * 20;
        }
        rect.SetVisualOffset(bounce);
    }

    void PaintCharacters(JsonValue@ p)
    {
        JsonValue@ characters = p.Get("characters");
        for (uint i = 0; i < 3; ++i)
        {
            String id = CharacterId(i);
            NovelVisualSlot@ slot = view.At(view.characters, i * 2);
            if (!characters.Has(id))
            {
                slot.object.SetEnabled(false);
                slot.next.object.SetEnabled(false);
                continue;
            }
            JsonValue@ character = characters.Get(id);
            String target = character.Get("resourceId").GetString();
            String previous = character.Get("previousResource").GetString();
            float duration = float(character.Get("transitionDuration").GetNumber());
            float progress = duration > 0 ? float(character.Get("transitionElapsed").GetNumber()) / duration : 1;
            progress = progress > 1 ? 1 : progress;
            view.Texture(slot, character.Get("state").GetString() == "hidden" ? "hidden" : target, audio.Path(target));
            view.Texture(slot.next, previous, previous == "hidden" ? "" : audio.Path(previous), progress < 1);
            PlaceCharacter(slot, character);
            if (progress < 1)
            {
                PlaceCharacter(slot.next, character);
            }
            slot.image.SetSubtreeOpacity(progress);
            slot.next.image.SetSubtreeOpacity(character.Get("state").GetString() == "hidden" ? 1 - progress : 1);
        }
    }

    void Animate(JsonValue@ p, float dt)
    {
        RuntimeValues::PutNumber(p, "effectTime", p.Get("effectTime").GetNumber() + dt);
        JsonValue@ transition = p.Get("transition");
        float duration = float(transition.Get("duration").GetNumber());
        float elapsed = float(transition.Get("elapsed").GetNumber()) + dt;
        RuntimeValues::PutNumber(transition, "elapsed", elapsed < duration ? elapsed : duration);
        p.Set("transition", transition);
        JsonValue@ characters = p.Get("characters");
        for (uint i = 0; i < characters.GetCount(); ++i)
        {
            String id = characters.GetKey(i);
            JsonValue@ character = characters.Get(id);
            float end = float(character.Get("transitionDuration").GetNumber());
            float time = float(character.Get("transitionElapsed").GetNumber()) + dt;
            RuntimeValues::PutNumber(character, "transitionElapsed", time < end ? time : end);
            if (character.Get("bounceActive").GetBool())
            {
                float bounce = float(character.Get("bounceElapsed").GetNumber()) + dt;
                RuntimeValues::PutNumber(character, "bounceElapsed", bounce < 0.2f ? bounce : 0.2f);
                if (bounce >= 0.2f)
                {
                    character.Set("bounceActive", RuntimeValues::BoolValue(false));
                    JsonValue empty;
                    character.Set("animation", empty);
                }
            }
            characters.Set(id, character);
        }
        p.Set("characters", characters);
        PaintBackground(p);
        PaintCharacters(p);
        view.Effects(float(p.Get("effectTime").GetNumber()));
    }

}
