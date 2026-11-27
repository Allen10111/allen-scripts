-- Allen Scripts / Blade Ball entry point.
assert(game.GameId==4777817887,"Open Blade Ball first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/blade_ball")
assert(run,err)
return run()
