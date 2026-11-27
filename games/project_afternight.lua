-- Allen Scripts / Project: Afternight entry point.
assert(game.GameId==4557322431,"Open Project: Afternight first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/project_afternight")
assert(run,err)
return run()
