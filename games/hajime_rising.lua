-- Allen Scripts / Hajime Rising entry point.
assert(game.GameId==10769763567,"Open Hajime Rising first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/hajime_rising.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/hajime_rising")
assert(run,err)
return run()
