# Allen Scripts

A Roblox script hub with game-specific sections and in-hub ON/OFF switches.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_hub.lua"))()
```

## Included

- Universal: soft camera lock with a red target highlight.
- Ink Game: auto-dodge using the available native dash.
- Funky Friday: autoplay with taps, holds, and chords.
- rosu!mania: autoplay with native lane presses and hold releases.

All scripts start OFF. Individual script buttons and hotkeys are removed in the hub build. Use the hub switches to control features, Right Shift to hide/show the hub, or AS to reopen it. Drag the title bar to move the window.

Game-specific controls are disabled in other games. Auto Parry is marked unavailable because no standalone implementation is included. Tug of War, Mingle, and the scrapped auto-combat project are excluded.

The hub and bundled engines are readable, not obfuscated. Executor support is required; Funky Friday additionally requires Actor execution. Compatibility can change with game updates.
