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

-- Ink Game movement recovery module and its normal game-specific toggle.
do
    local function replaceOnce(old,new)
        local a,b=source:find(old,1,true)
        assert(a,"Allen Scripts feature anchor is missing")
        source=source:sub(1,a-1)..new..source:sub(b+1)
    end
    if not source:find('Id="anti_stun"',1,true)then
        replaceOnce("local SOURCES={",[========[local SOURCES={
AntiStun=[======[
-- Allen Scripts / Ink Game local movement recovery.
assert(game.GameId==7008097940,"Open Ink Game first")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local state={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Corrections=0}
local connections={}
local character,humanoid,speedConnection,addedConnection,removedConnection
local baseline,nativeSpeed,forcedSpeed
local writing=false
local function disconnect(c)if c then c:Disconnect()end end
local function restore()
 if humanoid and humanoid.Parent and forcedSpeed and nativeSpeed~=nil and humanoid.WalkSpeed==forcedSpeed then
  writing=true;humanoid.WalkSpeed=nativeSpeed;writing=false
 end
 nativeSpeed=nil;forcedSpeed=nil
end
local function blocked()
 return not humanoid or humanoid.Health<=0 or not character or not character.Parent
  or character:FindFirstChild("Dead") or character:FindFirstChild("Ragdoll")
  or character:FindFirstChild("InCutscene") or character:FindFirstChild("Anchor")
end
local function refresh()
 if not state.Enabled or state.Destroyed or writing then return end
 if blocked()then restore();state.Status="Waiting for movable character";return end
 local speed=humanoid.WalkSpeed
 if not character:FindFirstChild("Stun")then
  -- The native controller resumes its own speed when the stun ends.
  -- Do not restore a stale zero-speed request over that recovery.
  forcedSpeed=nil;nativeSpeed=nil
  if speed>0 then baseline=speed end
  state.Status="Ready";return
 end
 if speed~=forcedSpeed then nativeSpeed=speed end
 local target=baseline and baseline>0 and baseline or 14
 if speed<target then
  forcedSpeed=target;writing=true;humanoid.WalkSpeed=target;writing=false
  state.Corrections+=1
 end
 state.Status="Preserving local movement during stun"
end
local function bind(nextCharacter)
 disconnect(speedConnection);disconnect(addedConnection);disconnect(removedConnection)
 restore()
 character=nextCharacter
 humanoid=character and character:FindFirstChildOfClass("Humanoid")
 baseline=humanoid and humanoid.WalkSpeed>0 and humanoid.WalkSpeed or 14
 if not character then return end
 addedConnection=character.ChildAdded:Connect(function(child)
  if child:IsA("Humanoid")and not humanoid then bind(character)else refresh()end
 end)
 removedConnection=character.ChildRemoved:Connect(refresh)
 if humanoid then speedConnection=humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(refresh)end
 refresh()
end
function state:SetEnabled(enabled)
 enabled=enabled==true
 if self.Destroyed or self.Enabled==enabled then return end
 self.Enabled=enabled
 if enabled then
  bind(player.Character)
  connections[#connections+1]=player.CharacterAdded:Connect(bind)
  connections[#connections+1]=player.CharacterRemoving:Connect(function()bind(nil)end)
  local elapsed=0
  connections[#connections+1]=RunService.Heartbeat:Connect(function(dt)
   elapsed+=dt
   if elapsed>=.1 then elapsed=0;refresh()end
  end)
 else
  disconnect(speedConnection);disconnect(addedConnection);disconnect(removedConnection)
  speedConnection=nil;addedConnection=nil;removedConnection=nil
  for _,c in ipairs(connections)do c:Disconnect()end
  table.clear(connections);restore();character=nil;humanoid=nil;self.Status="Off"
 end
end
function state:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Corrections=self.Corrections}end
function state:Destroy()
 if self.Destroyed then return end
 self:SetEnabled(false);self.Destroyed=true
end
return state

]======],]========])
        replaceOnce('    {Id="unlock_dash"',[========[    {Id="anti_stun",Section="Ink Game",Category="Combat",Name="Anti Stun",Subtitle="Preserves local movement during attack recovery and stuns",Game=INK,Source="AntiStun"},
    {Id="unlock_dash"]========])
    end
end

local run,err=loadstring(source,"AllenScripts/GameRuntime")
assert(run,err)
return run()
