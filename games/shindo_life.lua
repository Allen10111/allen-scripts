-- Allen Scripts / Shindo Life entry point.
assert(game.GameId==1511883870,"Open Shindo Life first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/shindo_life")
assert(run,err)
return run()
