
-- Allen Scripts presentation adapter for MoroElite (GUI2222).
do
    local libraryFactory, libraryError=loadstring(SOURCES.AllenInterface,"AllenScripts/MoroElite")
    assert(libraryFactory,libraryError)
    local library=libraryFactory()
    library.Folder="AllenScriptsUI"
    if hub.Destroyed then library:Unload();return end
    local ui=library:CreateWindow({
        Title="Allen Scripts Hub",Subtitle="Allen10111 · "..gameName,
        Logo=false,Art=false,MenuArt=false,OpenControl="Button",
        ToggleKey=Enum.KeyCode.RightShift,TopButtons={},
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
    local settingsReady=false
    local function buildGame(name)
        if tabs[name] then ui:SelectTab(tabs[name]);return end
        local tab=ui:CreateTab({Name=name,Icon=name=="Universal" and "globe" or "gamepad-2"})
        tabs[name]=tab
        local groups={}
        for _,feature in ipairs(features)do if feature.Section==name then
            local key=group(feature)
            if not groups[key] then
                local page=tab:SubTab({Name=key,Icon=icons[key] or "layout-grid"})
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
        sections[name]=groups
        if not settingsReady then settingsReady=true;ui:AddSettingsTab()end
        ui:SelectTab(tab)
    end
    local profile=ui:GetProfileTab():Column("right"):CreateSection({Name="Allen Scripts",Icon="sparkles"})
    profile:AddLabel("Allen Scripts Hub · Allen10111")
    profile:AddLabel("github.com/Allen10111/allen-scripts")
    profile:AddLabel("Interface: MoroElite by Morozhka144 / GUI2222")
    profile:AddStat({Name="Hub status",Get=function()return note~="" and note or "Ready"end})
    profile:AddButton({Name="Unload Allen Scripts Hub",NoConfig=true,Callback=function()hub:Destroy()end})
    library.Folder="AllenScriptsUI"
    local loader=ui:CreateTab({Name="Loader",Icon="download"})
    loader.RightCol.Frame.Visible=false
    loader.LeftCol.Frame.Size=UDim2.new(1,0,0,0)
    local section=loader:Column("left"):CreateSection({Name="Allen Scripts",Icon="gamepad-2"})
    local selected=seen[gameName] and gameName or "Universal"
    local selector=section:AddDropdown({Name="Game",Options=names,Default=selected,NoConfig=true,
        Callback=function(value)selected=value end})
    local loading=false
    function hub:LoadSelectedScript()
        if self.Destroyed or loading then return false end
        local name=selected
        local action
        local compatible=name=="Universal"
        for _,feature in ipairs(features)do if feature.Section==name then
            if not feature.Game or feature.Game==game.GameId then compatible=true end
            if feature.Action then action=feature end
        end end
        if not compatible then
            ui:Notify({Title="Allen Scripts Hub",Text="Join "..name.." before loading its script.",Type="warning",Sound=false})
            return false
        end
        if action then
            loading=true
            activate(action)
            task.spawn(function()
                while not hub.Destroyed and hub.Busy[action.Id] do task.wait(.1)end
                loading=false
                if hub.Destroyed then return end
                if snapshot(action).Enabled then ui:Toggle(false)
                else ui:Notify({Title=action.Name,Text=note~="" and note or "Script did not finish loading. Try again.",Type="error",Sound=false})end
            end)
        else
            buildGame(name)
        end
        return true
    end
    section:AddButton({Name="Load Script",Icon="play",Primary=true,NoConfig=true,NoFastMenu=true,
        Callback=function()hub:LoadSelectedScript()end})
    hub.LoaderTab=loader;hub.GameSelector=selector
    ui.Watermark.Visible=true
    ui:SelectTab(loader)
    hub.InterfaceControls=controls
    hub.SelectGame=function(_,name)if seen[name]then selected=name;selector:Set(name);ui:SelectTab(loader)end end
    hub.SelectTab=function(_,name)
        local tab=tabs[selected]
        if tab and tab:GetSubTab(name) then tab:SelectSub(tab:GetSubTab(name))end
    end
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
