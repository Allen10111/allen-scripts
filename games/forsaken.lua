-- Allen Scripts / Forsaken entry point.
assert(game.GameId==6331902150,"Open Forsaken first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allens_forsaken.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/forsaken")
assert(run,err)
return run()
