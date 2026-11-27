# Allen Scripts automatic game interface

The existing allen_scripts_hub.lua loadstring is now a small dispatcher. It selects one of 15 game entry scripts under games/ by game.GameId. There is no game picker or Load Script menu. Unknown games show an unsupported-game message.

Forsaken and Hajime Rising execute their existing dedicated scripts directly. Other game entries use allen_scripts_runtime.lua, which loads the preserved backend source from allen_scripts_backend.lua and replaces its presentation adapter before executing it. This retains the established feature code while allowing each detected game to expose only its applicable controls in top-level tabs.

UI source: MoroElite by Morozhka144, https://github.com/Morozhka144/GUI2222 (upstream c4173cd6c63bd836d626583289d0785808a24287). Allen Scripts / Allen10111 title and watermark remain. Original attribution and the bundled Lucide MIT notice are retained. Cat/startup audio stays blocked; right-click camera look is permitted.

Validation: current Ink Game shared runtime compiled and initialized with 38 applicable controls. No loader or nested feature tabs remain; Hide & Seek, Jump Rope and Tug of War have explicit tabs. Mocked dispatcher tests passed for all 15 supported IDs and one unknown ID. Other games and physical Android/iOS devices were not live-tested in this change.
