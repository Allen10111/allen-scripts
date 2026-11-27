-- Allen Scripts shared runtime. Game entry points choose this automatically.
local root="https://raw.githubusercontent.com/Allen10111/allen-scripts/main/"
local source=game:HttpGet(root.."allen_scripts_backend.lua?build=r59&t="..tostring(os.time()))
local marker="\n-- Allen Scripts presentation adapter for MoroElite (GUI2222)."
local start=source:find(marker,1,true)
assert(start,"Allen Scripts backend interface boundary was not found")
local adapter=[========[

-- Allen Scripts presentation adapter for MoroElite (GUI2222).
do
    -- Games with their own interface launch directly without a hub menu.
    local dedicated
    for _,feature in ipairs(features)do
        if feature.Action and feature.Game==game.GameId then dedicated=feature;break end
    end
    if dedicated then
        gui.Enabled=false;window.Visible=false
        change(dedicated)
        hub.AutoDetectedGame=dedicated.Section
        task.spawn(function()
            while not hub.Destroyed and hub.Busy[dedicated.Id]do task.wait(.1)end
            if not hub.Destroyed and not snapshot(dedicated).Enabled then
                warn("[Allen Scripts] "..tostring(note))
            end
        end)
        return hub
    end
    local libraryFactory, libraryError=loadstring(SOURCES.AllenInterface,"AllenScripts/MoroElite")
    assert(libraryFactory,libraryError)
    local library=libraryFactory()
    library.Folder="AllenScriptsUI"
    if hub.Destroyed then library:Unload();return end
    local ui=library:CreateWindow({
        Title="Allen Scripts Hub",Subtitle="Allen10111 · "..gameName,
        Logo=false,Art=false,MenuArt=false,OpenControl="Button",
        ToggleKey=Enum.KeyCode.RightShift,TopButtons={"bell","settings"},
        LoaderSound=false,NotifySound=false,Blur=false,
        TeleportUrl="https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_hub.lua",
        ExecuteOnTeleport=false,
    })
    hub.Interface=ui;hub.InterfaceLibrary=library
    ui.Gui.Name="AllenScriptsHub"
    ui.Gui.DisplayOrder=gui.DisplayOrder
    hub.Gui=ui.Gui
    gui.Enabled=false
    window.Visible=false
    local originalDestroy=hub.Destroy
    function hub:Destroy()
        if self.Destroyed then return end
        originalDestroy(self)
        if not self.UnloadingInterface then
            self.UnloadingInterface=true
            library:Unload()
        end
    end
    library:OnUnload(function()
        hub.UnloadingInterface=true
        if not hub.Destroyed then originalDestroy(hub) end
    end)
    local sections,tabs,controls={},{},{}
    local names,seen={},{}
    local function addName(name)
        if name and not seen[name] then seen[name]=true;names[#names+1]=name end
    end
    addName(gameName~="Other experience" and gameName or nil)
    addName("Universal")
    for _,feature in ipairs(features)do addName(feature.Section)end
    local icons={Movement="footprints",Combat="swords",Alerts="eye",Minigames="gamepad-2",
        Utility="wrench",Rhythm="music",Aim="crosshair",Forsaken="library",
        ["Hajime Rising"]="flame"}
    local function group(feature)
        if feature.Id:find("^hns_")then return "Hide & Seek" end
        if feature.Id=="inkrope" or feature.Id:find("^rope_")then return "Jump Rope" end
        if feature.Id=="inktug"then return "Tug of War" end
        if feature.Id=="inkqte"then return "Auto QTE" end
        if feature.Id=="inkrlgl" or feature.Id=="inkinjuries" then return "Red Light" end
        if feature.Id:find("^dalgona")then return "Dalgona" end
        if feature.Id:find("^glass")then return "Glass Bridge" end
        return feature.Category or "Features"
    end
    local function unavailable(feature)
        return feature.Unavailable or feature.Game and feature.Game~=game.GameId
            or feature.PCOnly and not UIS.KeyboardEnabled
            or feature.MobileUnsupported and UIS.TouchEnabled
    end
    local function activate(feature)
        if hub.Destroyed then return end
        if unavailable(feature) then
            ui:Notify({Title=feature.Name,Text=snapshot(feature).Status or "Unavailable in this experience",Type="warning",Sound=false})
            return
        end
        change(feature)
    end
    local supported=false
    for _,feature in ipairs(features)do
        if feature.Section==gameName and not feature.Action then supported=true;break end
    end
    hub.AutoDetectedGame=supported and gameName or nil
    if supported then
        local groups={}
        for _,feature in ipairs(features)do if feature.Section==gameName or feature.Section=="Universal" then
            local key=feature.Section=="Universal" and "Utility" or group(feature)
            if not groups[key] then
                local page=ui:CreateTab({Name=key,Icon=icons[key] or "layout-grid"})
                tabs[key]=page
                page.RightCol.Frame.Visible=false
                page.LeftCol.Frame.Size=UDim2.new(1,0,0,0)
                groups[key]=page:Column("left"):CreateSection({Name=key,Icon=icons[key] or "sliders-horizontal"})
            end
            local section=groups[key]
            if feature.Action then
                section:AddButton({Name=feature.Name,Description=feature.Subtitle,
                    Tooltip="Launch or re-execute "..feature.Name,NoConfig=true,
                    Callback=function()activate(feature)end})
            else
                local control=section:AddToggle({Name=feature.Name,Description=feature.Subtitle,
                    Tooltip=feature.Section.." · "..(feature.Subtitle or ""),Default=false,NoConfig=true,NoFastMenu=true,
                    Callback=function()activate(feature)end})
                controls[#controls+1]={Feature=feature,Control=control}
            end
            if feature.Id=="silentaim" then
                section:AddSlider({Name="Silent Aim FOV",Min=50,Max=350,Default=150,Suffix=" px",NoConfig=true,
                    Callback=function(v)env.__ALLEN_SILENT_AIM_RADIUS=v end})
            end
        end end

        sections[gameName]=groups
        ui:AddSettingsTab()
    else
        local tab=ui:CreateTab({Name="Unsupported Game",Icon="info"})
        tabs.Unsupported=tab
        tab.RightCol.Frame.Visible=false;tab.LeftCol.Frame.Size=UDim2.new(1,0,0,0)
        local message=tab:Column("left"):CreateSection({Name="Allen Scripts Hub"})
        message:AddLabel("This game is not supported yet.")
    end
    local profile=ui:GetProfileTab():Column("right"):CreateSection({Name="Allen Scripts",Icon="sparkles"})
    profile:AddLabel("Allen Scripts Hub · Allen10111")
    profile:AddLabel("github.com/Allen10111/allen-scripts")
    profile:AddLabel("Interface: MoroElite by Morozhka144 / GUI2222")
    profile:AddStat({Name="Hub status",Get=function()return note~="" and note or "Ready"end})
    profile:AddButton({Name="Unload Allen Scripts Hub",NoConfig=true,Callback=function()hub:Destroy()end})
    library.Folder="AllenScriptsUI"
    ui.Watermark.Visible=true
    hub.InterfaceControls=controls
    hub.GameTabs=tabs
    hub.SelectGame=function()return false end
    hub.SelectTab=function(_,name)if tabs[name]then ui:SelectTab(tabs[name])end end
    local first=tabs.Combat or tabs.Movement or tabs["Red Light"]
    if not first then for _,tab in pairs(tabs)do first=tab;break end end
    if first then ui:SelectTab(first)end
    task.spawn(function()
        while not hub.Destroyed do
            for _,entry in ipairs(controls)do
                local q=snapshot(entry.Feature)
                entry.Control:Set(q.Enabled==true,true)
            end
            task.wait(.35)
        end
    end)
end

]========]
source=source:sub(1,start-1).."\n"..adapter.."\nreturn hub\n"
source=source:gsub('Version="2026%-11%-27%-r58"','Version="2026-11-27-r59"')
source=source:gsub('or "Other experience"','or game.GameId==245662005 and "Jailbreak" or game.GameId==4557322431 and "Project: Afternight" or "Other experience"')
local run,err=loadstring(source,"AllenScripts/GameRuntime")
assert(run,err)
return run()
