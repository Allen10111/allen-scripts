-- Allen Scripts / Funky Friday entry point.
assert(game.GameId==2404080894,"Open Funky Friday first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/funky_friday")
assert(run,err)
return run()
