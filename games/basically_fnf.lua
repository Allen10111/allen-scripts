-- Allen Scripts / Basically FNF: Remix entry point.
assert(game.GameId==2443177453,"Open Basically FNF: Remix first")
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua".."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/basically_fnf")
assert(run,err)
return run()
