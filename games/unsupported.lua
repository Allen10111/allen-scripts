-- Allen Scripts unsupported-game message.
local run,err=loadstring(game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_runtime.lua?build=r59&t="..tostring(os.time())))
assert(run,err)
return run()
