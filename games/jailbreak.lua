-- Allen Scripts / Jailbreak entry point.
assert(game.GameId==245662005,"Open Jailbreak first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/jailbreak")
assert(run,err)
return run()
