-- Allen Scripts / Funky Duels entry point.
assert(game.GameId==10766630653,"Open Funky Duels first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/funky_duels")
assert(run,err)
return run()
