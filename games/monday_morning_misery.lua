-- Allen Scripts / Monday Morning Misery entry point.
assert(game.GameId==2802559498,"Open Monday Morning Misery first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/monday_morning_misery")
assert(run,err)
return run()
