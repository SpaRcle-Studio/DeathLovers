//
// Created by Codex on 17.11.2026.
//

#include "NovelView.as"
#include "NovelAudio.as"

class NovelPresentation
{
    NovelView@ view;
    NovelAudio@ audio;
    bool waitingTextures = false;

    void Prepare(NovelPresentationState@ p)
    {
        PaintBackground(p);
        PaintCharacters(p);
        waitingTextures = view.background.waitingTexture || view.backgroundOld.waitingTexture;
        for (uint i = 0; i < 6; ++i)
        {
            waitingTextures = waitingTextures || view.At(view.characters, i).waitingTexture;
        }
    }

    void PaintBackground(NovelPresentationState@ p)
    {
        NovelTransition@ transition = p.transition;
        float duration = float(transition.duration);
        float progress = duration > 0 ? float(transition.elapsed) / duration : 1;
        progress = progress > 1 ? 1 : progress;
        view.Texture(view.background, p.background, p.background == "builtin:black" || view.background.resource == p.background ? "" : audio.Path(p.background));
        view.Texture(view.backgroundOld, transition.from, progress >= 1 || transition.from == "builtin:black" || view.backgroundOld.resource == transition.from ? "" : audio.Path(transition.from), progress < 1);
        view.background.image.SetSubtreeOpacity(transition.kind == "fade" ? (progress < 0.5f ? 0 : (progress - 0.5f) * 2) : progress);
        view.backgroundOld.image.SetSubtreeOpacity(transition.kind == "fade" ? (progress < 0.5f ? 1 - progress * 2 : 0) : 1);
        FVector2 offset;
        if (transition.kind == "vpunch" && progress < 1)
        {
            offset.y = MathUtils::Instance().Sin(progress * 31.4159265359f) * 15 * (1 - progress);
        }
        cast<TransformRect@>(view.background.object.GetTransform()).SetVisualOffset(offset);
    }

    String CharacterId(uint index)
    {
        return index == 0 ? "ch_p" : index == 1 ? "ch_w" : "ch_h";
    }

    void PlaceCharacter(NovelVisualSlot@ slot, NovelCharacter@ character)
    {
        if (!slot.image.IsTextureReady())
        {
            return;
        }
        TransformRect@ rect = cast<TransformRect@>(slot.object.GetTransform());
        FVector2 size = slot.image.GetTextureSize();
        size.x *= float(character.scale.x);
        size.y *= float(character.scale.y);
        rect.SetSize(size);
        FVector2 position;
        position.x = float(character.position.x);
        position.y = -float(character.position.y);
        rect.SetAnchoredPosition(position);
        FVector3 flip;
        flip.x = character.flipX ? -1 : 1;
        flip.y = character.flipY ? -1 : 1;
        flip.z = 1;
        rect.SetScale(flip);
        FVector2 bounce;
        if (character.bounceActive)
        {
            bounce.y = MathUtils::Instance().Sin(float(character.bounceElapsed) * 3.141592653589793f / 0.2f) * 20;
        }
        rect.SetVisualOffset(bounce);
    }

    void PaintCharacters(NovelPresentationState@ p)
    {
        for (uint i = 0; i < 3; ++i)
        {
            String id = CharacterId(i);
            NovelVisualSlot@ slot = view.At(view.characters, i * 2);
            if (!p.characters.contains(id))
            {
                slot.waitingTexture = false;
                slot.next.waitingTexture = false;
                slot.object.SetEnabled(false);
                slot.next.object.SetEnabled(false);
                continue;
            }
            NovelCharacter@ character = p.characters.at(id);
            float duration = float(character.transitionDuration);
            float progress = duration > 0 ? float(character.transitionElapsed) / duration : 1;
            progress = progress > 1 ? 1 : progress;
            view.Texture(slot, character.state == "hidden" ? "hidden" : character.resourceId,
                character.state == "hidden" || slot.resource == character.resourceId ? "" : audio.Path(character.resourceId));
            view.Texture(slot.next, character.previousResource,
                progress >= 1 || character.previousResource == "hidden" || slot.next.resource == character.previousResource ? "" : audio.Path(character.previousResource), progress < 1);
            PlaceCharacter(slot, character);
            if (progress < 1)
            {
                PlaceCharacter(slot.next, character);
            }
            slot.image.SetSubtreeOpacity(progress);
            slot.next.image.SetSubtreeOpacity(character.state == "hidden" ? 1 - progress : 1);
        }
    }

    void Animate(NovelPresentationState@ p, float dt)
    {
        Prepare(p);
        if (waitingTextures)
        {
            return;
        }
        p.effectTime = p.effectTime + dt;
        NovelTransition@ transition = p.transition;
        float duration = float(transition.duration);
        float elapsed = float(transition.elapsed) + dt;
        transition.elapsed = elapsed < duration ? elapsed : duration;

        for (uint i = 0; i < 3; ++i)
        {
            String id = CharacterId(i);
            if (!p.characters.contains(id))
            {
                continue;
            }
            NovelCharacter@ character = p.characters.at(id);
            float end = float(character.transitionDuration);
            float time = float(character.transitionElapsed) + dt;
            character.transitionElapsed = time < end ? time : end;
            if (character.bounceActive)
            {
                float bounce = float(character.bounceElapsed) + dt;
                character.bounceElapsed = bounce < 0.2f ? bounce : 0.2f;
                if (bounce >= 0.2f)
                {
                    character.bounceActive = false;
                    character.animation = "";
                }
            }
        }

        PaintBackground(p);
        PaintCharacters(p);
        view.Effects(float(p.effectTime));
    }
}
