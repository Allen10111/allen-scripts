# Allen Scripts unified interface

allen_scripts_hub.lua detects the game and opens its game entry script directly. Generic games use top-level tabs from the shared runtime. Forsaken and Hajime Rising entries now prepare their original backend source with explicit UI control metadata, then display the same MoroElite-based Allen Scripts interface via ui/dedicated_game_interface.lua. Their gameplay adapters remain unchanged.

The preparation is idempotent and validates its source anchors before executing anything. Original standalone backend files remain preserved. Their game entry files provide the unified interface when launched through the universal loadstring.

Cobalt Remote Spy's bundled code and feature entry are removed from allen_scripts_backend.lua. The Allen10111 title, watermark, silent cat/startup sounds, right-click camera movement, top-level tabs, profile/configuration actions and cleanup are retained.

UI source: https://github.com/Morozhka144/GUI2222, upstream c4173cd6c63bd836d626583289d0785808a24287. Source attribution and Lucide MIT notice remain.

Checks: both prepared game scripts compile with Luau; repeated preparation does not duplicate the interface; mocked Forsaken/Hajime controls update settings, actions execute, dropdown changes propagate, and unload clears the interface and backend. Generic Ink Game UI and dispatcher routes were previously tested. Live Forsaken/Hajime game behavior and physical Android/iOS testing remain pending.
