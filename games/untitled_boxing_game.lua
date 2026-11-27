-- Allen Scripts / Untitled Boxing Game entry point.
assert(game.GameId==4730278139,"Open Untitled Boxing Game first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/untitled_boxing_game")
assert(run,err)
return run()
