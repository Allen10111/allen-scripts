-- Allen Scripts / Ink Game entry point.
assert(game.GameId==7008097940,"Open Ink Game first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/ink_game")
assert(run,err)
return run()
