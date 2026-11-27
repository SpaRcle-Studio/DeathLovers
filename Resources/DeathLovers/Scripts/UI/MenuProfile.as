//
// Created by Codex on 16.11.2026.
//

class MenuSettings
{
    float music_volume = 0.2f;
    float sfx_volume = 0.2f;
    float voice_volume = 1.0f;
    float text_cps = 30.0f;
    float afm_time = 15.0f;
    bool pixel_voice = true;
    bool mute = false;
    bool fullscreen = false;
    bool skip_unseen = false;
    bool skip_after_choices = false;
    bool skip_transitions = false;
}

class MenuProfile
{
    bool firstRun = false;
    MenuSettings settings;
    /// ids of read lines and seen menus (StoryRunner line ids)
    Vector<String> readLines;
    /// reached ending labels (e.g. "war_ending"): unlock character silhouettes in the main menu
    Vector<String> endings;
}

namespace MenuSession
{
    MenuProfile profile;
    bool skipActive = false;
    bool autoActive = false;
    String activeScreen = "MainMenu";
}
