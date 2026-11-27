-- Allen Scripts / rosu!mania entry point.
assert(game.GameId==3405992067,"Open rosu!mania first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/rosu_mania")
assert(run,err)
return run()
