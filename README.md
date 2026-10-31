# Allen Scripts

A searchable Roblox script library with in-hub ON/OFF switches.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_hub.lua"))()
```

## Library

Black interface with a game-category sidebar, instant game/script search, and Aim, Movement, and Rhythm sections. Use This game only to narrow results.

## Included

- Universal: PC-only soft camera lock with shift-lock compensation and a red target highlight.
- Ink Game: auto-dodge using the available native dash.
- Shindo Life: native local movement dash triggered by nearby replicated combat/cast signals, incoming physical carriers, and supported area-power events. Long beams/waves are covered along their full axis. Actual touch carriers in ClientEffects are included; cosmetic effects alone are ignored. Supplementary visual-envelope profiles cover Grand Fireball, Almighty Push variants, Earth AoE, Water Pillar Dragon, and Senko teleport/flash cues. These are defensive approximations, not verified server damage volumes. Checks full dash paths against tracked attacks, projectiles, and occupied landing zones using continuous collision tests and two dash-speed estimates. Wall walking is unsupported. Cast ranges are heuristics, not verified server hitboxes. No guarantee of avoiding every attack; cooldown, stun, latency, and unobserved attacks still apply. Requires getconnections, debug.info, and thread identity APIs. Does not grant invulnerability. Mobile gameplay unverified.
- Funky Friday: autoplay with taps, holds, and chords.
- Funky Duels: native autoplay with taps, holds, chords, and hurt-note filtering. Requires debug.getupvalues, debug.info, and module access; mobile gameplay verification is pending.
- rosu!mania: autoplay with native lane presses and hold releases.
- Monday Morning Misery: native local-lane autoplay with tap and hold handling. Requires getgc, debug.getupvalues, and debug.info; mobile compatibility is unverified.

All scripts start OFF. Individual script buttons are removed in the hub build. Press C to toggle the PC soft camera lock; its hub switch stays synchronized. Use the hub switches to control features, Right Shift to hide/show the hub, or AS to reopen it. Drag the title bar to move the window.

Game-specific controls are disabled in other games. Tug of War, Mingle, and the scrapped auto-combat project are excluded.

The hub and bundled engines are readable, not obfuscated. Executor support is required; Funky Friday additionally requires Actor execution. Compatibility can change with game updates.

## Mobile

The compact mobile window is capped at 430 by 430 pixels and adapts to touch screens with portrait and landscape layouts, a scrollable Games menu, swipeable section tabs, 44-pixel switches, and a touch drag handle. Safe-area and on-screen-keyboard changes are handled automatically. Tap AS to reopen the window. The executor must still support the APIs required by each game, including Actor execution for Funky Friday.

## Auto Dodge engine

`ink_auto_dodge.lua` is the button-free native dodge engine for PC and mobile. It starts OFF and is controlled by the hub switch. It creates no standalone GUI or hotkeys. Requires a supported executor and an available native dash.
