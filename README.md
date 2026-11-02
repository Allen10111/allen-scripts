# Allen Scripts

A searchable Roblox script library with in-hub ON/OFF switches.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_hub.lua"))()
```

## Library

Black tabbed interface inspired by Ringta's visible GUI layout, with Allen Scripts branding. Choose a game from the selector, use the left sidebar to open feature pages, and search across the complete library by game or script name. Ink Game has Home, Red Light, Dalgona and Movement pages. Each feature retains its own ON/OFF switch. The title bar supports dragging, minimizing, expanding and closing. No external UI library or Ringta script is executed.

## Included

- Universal Remote Spy: disabled following a confirmed BAC anti-cheat kick while logging. Its hub switch is unavailable and standalone file stops before installing a hook. Logging previously observed outgoing calls without intentionally replaying or generating requests. Exact BAC trigger is unconfirmed.
- Blade Ball Auto Parry: disabled after a BAC anti-cheat kick during testing (Error Code 267). Not verified for use. The hub switch is unavailable; the standalone file stops before running.
- Blade Ball: Red Ball Beep sound notice. A short local beep plays once when the visible ball enters the native red/highlighted state, rearming after it stops being red. No automatic parry, keypress, movement, or remote requests. Includes main and training ball folders. Controlled by the hub under Alerts.
- Friday Night Partying: native note-hit scheduler for local taps, chords, and sustain segments. Skips notes marked shouldPress=false or with positive HealthLoss. Uses the native song clock; starts OFF and is controlled by the hub. Requires module access, getfenv, getconnections, debug.info, and debug.getupvalues. Mobile executor testing is pending.
- Basically FNF: Remix: native local-lane autoplay for taps, holds, and chords, with upscroll/downscroll and current keybinding support. Requires module access, getfenv, and debug.getupvalues. Mobile executor gameplay is unverified.
- Universal: PC-only soft camera lock with shift-lock compensation and a red target highlight.
- Ink Game: auto-dodge using the available native dash. Red Light, Green Light Auto Stop preserves manual movement on green and unknown signals, and stops horizontal movement and jumping on confirmed red. It listens to the native TrafficLight event and traffic-light UI, and runs after the default PC/touch control update. It does not disable native controls, move toward a target, teleport, create standalone buttons or send remotes. Auto Stop releases when the native ReachedEnd character marker appears; that exemption lasts until the round or character changes. Switch OFF to remove red-light stopping. The previous autorun build was replaced at the user's request. Offline behavior/cleanup tests pass. Live testing confirmed manual green-light movement and two red-light stops at zero horizontal speed with health at 100. A complete round outcome for this revision has not been verified.
- Ink Game Dalgona (Minigames): three independent hub switches for Auto-complete, Lighter and Anti-crack. Auto-complete validates the native cookie frame and advances its progress once per cookie; the native controller then handles its completion request and cleanup. Lighter temporarily enables the client-side native lighter and removes the temporary effect on OFF. This does not purchase or permanently grant an item. Anti-crack suppresses native wrong-click cracking and holds the client fear value at zero; it does not remove the round deadline, undo cracks already reported, or guarantee protection from server-side failure. Requires getconnections, debug.info, debug.getupvalues and debug.setupvalue. The frame layout was matched against live Dalgona, but the round ended before functional testing; all three behaviors remain unverified in live gameplay. Starts OFF with no standalone buttons.
- Shindo Life: automatic power guard using the native block request, short holds, caster-facing, manual input ownership, and dodge fallback if guarding fails, breaks, or damage gets through. Detected projectiles, jutsu casts, and modeled power hazards are guard candidates; melee dash combos keep using evasions. Guard-break/unguardable attacks are not guaranteed blocked. Native local movement dash triggered by nearby replicated combat/cast signals, incoming physical carriers, and supported area-power events. Long beams/waves are covered along their full axis. Actual touch carriers in ClientEffects are included; cosmetic effects alone are ignored. Supplementary visual-envelope profiles cover Grand Fireball, Almighty Push variants, Earth AoE, Water Pillar Dragon, and Senko teleport/flash cues. These are defensive approximations, not verified server damage volumes. Checks full dash paths against tracked attacks, projectiles, and occupied landing zones using continuous collision tests and two dash-speed estimates. Wall walking is unsupported. Cast ranges are heuristics, not verified server hitboxes. No guarantee of avoiding every attack; cooldown, stun, latency, and unobserved attacks still apply. Requires getconnections, debug.info, and thread identity APIs. Does not grant invulnerability. Mobile gameplay unverified.
- Funky Friday: autoplay with taps, holds, and chords.
- Funky Duels: native autoplay with taps, holds, chords, and hurt-note filtering. Requires debug.getupvalues, debug.info, and module access; mobile gameplay verification is pending.
- rosu!mania: autoplay with native lane presses and hold releases.
- Monday Morning Misery: native local-lane autoplay with tap and hold handling. Requires getgc, debug.getupvalues, and debug.info; mobile compatibility is unverified.

All scripts start OFF. Individual script buttons are removed in the hub build. Press C to toggle the PC soft camera lock; its hub switch stays synchronized. Use the hub switches to control features, Right Shift to hide/show the hub, or AS to reopen it. Drag the title bar to move the window.

Game-specific controls are disabled in other games. Tug of War, Mingle, and the scrapped auto-combat project are excluded.

The hub and bundled engines are readable, not obfuscated. Executor support is required; Funky Friday additionally requires Actor execution. Compatibility can change with game updates.

## Mobile

The mobile window is capped at 430 by 430 pixels and adapts to portrait and landscape screens. A game selector and Tabs drawer replace the desktop sidebar. Feature lists scroll vertically and switches have 44-pixel touch height. Safe-area and on-screen-keyboard changes are handled. Tap AS to reopen the window and drag the title bar to move it. Desktop and simulated portrait/landscape layouts, cross-game search and Dalgona page filtering were checked in-game; physical mobile touch testing of this UI revision is pending. The executor must still support each feature's required APIs.

## Auto Dodge engine

`ink_auto_dodge.lua` is the button-free native dodge engine for PC and mobile. It starts OFF and is controlled by the hub switch. It creates no standalone GUI or hotkeys. Requires a supported executor and an available native dash.

