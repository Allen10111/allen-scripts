-- Applies presentation-only instrumentation to the dedicated backends before execution.
return function(source,gameName)
    source=source:gsub("\r\n","\n")
    if source:find("ui/dedicated_game_interface.lua",1,true)then return source end
    local function replace(old,new)
        local a,b=source:find(old,1,true)
        assert(a,"Allen Scripts UI source anchor changed: "..old:sub(1,70))
        assert(not source:find(old,b+1,true),"Allen Scripts UI source anchor is ambiguous")
        source=source:sub(1,a-1)..new..source:sub(b+1)
    end
    if gameName=="Forsaken"then
        local edits={
        {"connect(save.Activated,function()\n","c.SavePreferences=function()\n"},
        {"end)\nlocal unload=button(pages.Settings,\"Unload and restore\"","end\nconnect(save.Activated,c.SavePreferences)\nlocal unload=button(pages.Settings,\"Unload and restore\""},
        }
        for _,edit in ipairs(edits)do replace(edit[1],edit[2])end
        return source.."\ngui.Enabled=false\nlocal bridgeSource=game:HttpGet(\"https://raw.githubusercontent.com/Allen10111/allen-scripts/main/ui/dedicated_game_interface.lua?build=r60&t=\"..tostring(os.time()))\nlocal bridgeFactory,bridgeError=loadstring(bridgeSource,\"AllenScripts/DedicatedUI\")\nassert(bridgeFactory,bridgeError)\nbridgeFactory()(c,\"Forsaken\")\nreturn c\n"
    elseif gameName=="Hajime Rising"then
        local edits={
        {"local App = { Alive = true,","local App = { UIControls={}, UICards={}, UIPageRoots={}, Alive = true,"},
        {"        local function action(parent, caption, callback, accent)\n","        local function action(parent, caption, callback, accent)\n            if callback then App.UIControls[#App.UIControls+1]={Kind=\"action\",Label=caption,Parent=parent,Callback=callback}end\n"},
        {"        local function toggle(parent, caption, key, detail)\n","        local function toggle(parent, caption, key, detail)\n            App.UIControls[#App.UIControls+1]={Kind=\"toggle\",Label=caption,Key=key,Parent=parent,Description=detail}\n"},
        {"        local function slider(parent, caption, key, minimum, maximum, step, suffix)\n","        local function slider(parent, caption, key, minimum, maximum, step, suffix)\n            App.UIControls[#App.UIControls+1]={Kind=\"number\",Label=caption,Key=key,Parent=parent,Min=minimum,Max=maximum,Step=step,Suffix=suffix}\n"},
        {"        local function dropdown(parent, caption, key, options)\n","        local function dropdown(parent, caption, key, options)\n            App.UIControls[#App.UIControls+1]={Kind=\"choice\",Label=caption,Key=key,Parent=parent,Options=options}\n"},
        {"            pages[name] = {Root = page, Scroll = scroll}","            pages[name] = {Root = page, Scroll = scroll}\n            App.UIPageRoots[scroll]=name"},
        {"            local nameBox = input(profiles, \"Profile name\", C.ProfileName)","            local nameBox = input(profiles, \"Profile name\", C.ProfileName)\n            App.UIControls[#App.UIControls+1]={Kind=\"text\",Label=\"Profile name\",Key=\"ProfileName\",Parent=profiles}"},
        {"            local accent = input(appearance, \"#6366F1\", C.Accent)","            local accent = input(appearance, \"#6366F1\", C.Accent)\n            App.UIControls[#App.UIControls+1]={Kind=\"text\",Label=\"Accent color\",Key=\"Accent\",Parent=appearance}"},
        {"            return frame\n        end\n        local function input","            App.UICards[frame]={Title=title,Tab=App.UIPageRoots[parent] or \"Training\"}\n            return frame\n        end\n        local function input"},
        }
        for _,edit in ipairs(edits)do replace(edit[1],edit[2])end
        replace("\nreturn App","\nApp.Gui.Enabled=false\nlocal bridgeSource=game:HttpGet(\"https://raw.githubusercontent.com/Allen10111/allen-scripts/main/ui/dedicated_game_interface.lua?build=r60&t=\"..tostring(os.time()))\nlocal bridgeFactory,bridgeError=loadstring(bridgeSource,\"AllenScripts/DedicatedUI\")\nassert(bridgeFactory,bridgeError)\nbridgeFactory()(App,\"Hajime Rising\")\nreturn App\n")
        return source
    end
    error("Unknown dedicated game interface: "..tostring(gameName))
end
