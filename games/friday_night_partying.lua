-- Allen Scripts / Friday Night Partying entry point.
assert(game.GameId==10258128048,"Open Friday Night Partying first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/friday_night_partying")
assert(run,err)
return run()
