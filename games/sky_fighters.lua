-- Allen Scripts / Sky Fighters entry point.
assert(game.GameId==8366716517,"Open Sky Fighters first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/sky_fighters")
assert(run,err)
return run()
