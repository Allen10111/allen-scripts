-- Allen Scripts / Hajime Rising: common Allen interface with the original gameplay backend.
assert(game.GameId==10769763567,"Open Hajime Rising first")
local root="https://raw.githubusercontent.com/Allen10111/allen-scripts/main/"
local stamp="?build=r60&t="..tostring(os.time())
local prepare=assert(loadstring(game:HttpGet(root.."ui/prepare_dedicated_source.lua"..stamp)))()
local source=prepare(game:HttpGet(root.."hajime_rising.lua"..stamp),"Hajime Rising")
local run,err=loadstring(source,"AllenScripts/hajime_rising")
assert(run,err)
return run()
