-- Allen Scripts / Forsaken: common Allen interface with the original gameplay backend.
assert(game.GameId==6331902150,"Open Forsaken first")
local root="https://raw.githubusercontent.com/Allen10111/allen-scripts/main/"
local stamp="?build=r60&t="..tostring(os.time())
local prepare=assert(loadstring(game:HttpGet(root.."ui/prepare_dedicated_source.lua"..stamp)))()
local source=prepare(game:HttpGet(root.."allens_forsaken.lua"..stamp),"Forsaken")
local run,err=loadstring(source,"AllenScripts/forsaken")
assert(run,err)
return run()
