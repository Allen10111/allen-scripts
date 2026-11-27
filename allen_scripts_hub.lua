-- Allen Scripts Hub: automatically opens the script for this experience.
if not game:IsLoaded() then game.Loaded:Wait()end
local routes={
    [7008097940]="games/ink_game.lua",
    [6331902150]="games/forsaken.lua",
    [10769763567]="games/hajime_rising.lua",
    [2404080894]="games/funky_friday.lua",
    [3405992067]="games/rosu_mania.lua",
    [10766630653]="games/funky_duels.lua",
    [2802559498]="games/monday_morning_misery.lua",
    [1511883870]="games/shindo_life.lua",
    [2443177453]="games/basically_fnf.lua",
    [10258128048]="games/friday_night_partying.lua",
    [4777817887]="games/blade_ball.lua",
    [4730278139]="games/untitled_boxing_game.lua",
    [8366716517]="games/sky_fighters.lua",
    [245662005]="games/jailbreak.lua",
    [4557322431]="games/project_afternight.lua",
}
local env=type(getgenv)=="function"and getgenv()or _G
local old=env.__ALLEN_GENERAL_HUB
if old and type(old.Destroy)=="function"then old:Destroy()end
local path=routes[game.GameId]or"games/unsupported.lua"
local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/"..path.."?build=r59&t="..tostring(os.time()))
local run,err=loadstring(source,"AllenScripts/AutoDetect")
assert(run,err)
return run()
