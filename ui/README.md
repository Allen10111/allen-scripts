# Allen Scripts Hub interface

Adapted from MoroElite by Morozhka144: https://github.com/Morozhka144/GUI2222
Upstream revision: c4173cd6c63bd836d626583289d0785808a24287

Allen Scripts Hub / Allen10111 branding uses supported title, subtitle, logo, and watermark configuration. Upstream source attribution is retained. Lucide's MIT notice remains in the bundled icon source.

The library and Lucide icons are bundled into allen_scripts_hub.lua. Features reuse the existing backend and start disabled. Interface settings use AllenScriptsUI, isolated from other MoroElite menus. Unload disconnects both the interface and feature controllers. Camera right-drag is allowed while the menu is open.

Verified in the connected client: full hub compilation and initialization, 63 features / 61 toggles, Perm Guard toggle changes backend state and restores its attribute, status synchronization, and desktop screenshot inspection. Physical Android/iOS checks and manual camera-right-drag verification remain pending.
