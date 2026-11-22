//
// Created by Monika on 22.11.2026.
//

class GameGlobalData {
    Vector<ResourceRef<Texture>> textures;
    ResourceRef<FontAsset> mainFont;
}
GameGlobalData gGameGlobalData;

class LoadingScreen : ScriptBehaviour
{
    EntityRef<TextMesh> statusText;
    EntityRef<TextMesh> preloadText;
    EntityRef<TextMesh> preloadTextSystem;

    private Vector<Path> gameResources;
    private uint totalResources = 0;
    private uint totalGraphemes = 0;
    private String tempText;
    private String preloadChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя0123456789!@#$%^&*()-_=+[]{}|;:'\",.<>/?`~\\ ";
    private bool isSystemTextLoaded = false;
    private bool isTextLoaded = false;
    private bool isTextQueued = false;
    private bool isTexturesQueued = false;

    void Update(float dt)
    {
        if (!statusText.hasValue()) {
            return;
        }

        if (!isSystemTextLoaded && preloadTextSystem.hasValue()) {
            auto text = preloadTextSystem.get();
            if (text.GetLoadedGlyphCount() != text.text.graphemeCount()) {
                return;
            }
            isSystemTextLoaded = true;
        }

        if (!isTextLoaded && preloadText.hasValue()) {
            if (!gGameGlobalData.mainFont.hasValue()) {
                gGameGlobalData.mainFont.setId("DeathLovers/Fonts/Pangolin.font");
                gGameGlobalData.mainFont.ForceLoad();
            }
            TextMesh@ text = preloadText.get();
            uint loaded = 0;
            if (!isTextQueued) {
                text.SetFontPath("DeathLovers/Fonts/Pangolin.font");
                text.SetText(preloadChars);
                totalGraphemes = preloadChars.graphemeCount();
                isTextQueued = true;
            }
            loaded = text.GetLoadedGlyphCount();
            tempText = "Loading font: ";
            tempText = tempText + StringUtils::Instance().IntToString(loaded);
            tempText = tempText + " / ";
            tempText = tempText + StringUtils::Instance().IntToString(totalGraphemes);
            statusText.get().SetText(tempText);
            isTextLoaded = loaded == totalGraphemes;
            return;
        }

        if (!isTexturesQueued) {
            gGameGlobalData.textures.clear();
            gGameGlobalData.textures.reserve(128);
            auto gamePath = StringUtils::Instance().ConcatPath(ResourceManager::Instance().GetResPathRef(), "DeathLovers");
            VFS::Instance().GetFilesInDirectory(gameResources, gamePath, true, true);
            for (uint i = 0; i < gameResources.size(); i++) {
                gameResources[i] = StringUtils::Instance().RemoveSubPath(gameResources[i], ResourceManager::Instance().GetResPathRef());
                StringView path = gameResources[i];
                if (path.ends_with(".png") || path.ends_with(".jpg")) {
                    ResourceRef<Texture> ref;
                    ref.setId(path);
                    ref.ForceLoad();
                    gGameGlobalData.textures.pushBack(ref);
                    totalResources++;
                }
            }
            isTexturesQueued = true;
        }

        uint loaded = 0;
        for (uint i = 0; i < gGameGlobalData.textures.size(); i++) {
            if (!gGameGlobalData.textures[i].hasValue()) {
                loaded++; /// skip broken resource
                continue;
            }
            Texture@ pTexture = gGameGlobalData.textures[i].get();
            if (pTexture.CanBeUsed()) {
                loaded++;
            }
        }

        TextMesh@ textMesh = statusText.get();
        tempText = "Loading textures: ";
        tempText = tempText + StringUtils::Instance().IntToString(loaded);
        tempText = tempText + " / ";
        tempText = tempText + StringUtils::Instance().IntToString(totalResources);
        textMesh.SetText(tempText);

        if (loaded == totalResources) {
            textMesh.SetText("Loading scene...");
            ApplicationManager::Instance().GetApplication().GetEngine().RunSceneGameMode("Resources/DeathLovers/Scenes/MainMenu.scene", false);
        }
    }
}
