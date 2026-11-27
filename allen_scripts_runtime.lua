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


-- Replace the former name-only injury filter before compiling the backend.
do
    local a,b=source:find("RemoveInjuries=[====[",1,true)
    assert(a,"Injury module start was not found")
    local finish,last=source:find("]====],",b+1,true)
    assert(finish,"Injury module end was not found")
    source=source:sub(1,a-1)..[========[RemoveInjuries=[====[
-- Red Light injury relief: native injury markers only; no health/death changes.
assert(game.GameId==7008097940,"Open Ink Game first")
local player=game:GetService("Players").LocalPlayer
local state={Version=2,HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Removed=0}
local connections={}
local childConnection
local generation=0
local function disconnect(c) if c then c:Disconnect() end end
local function active()
    local values=workspace:FindFirstChild("Values")
    local current=values and values:FindFirstChild("CurrentGame")
    return state.Enabled and not state.Destroyed and current and current.Value=="RedLightGreenLight"
end
local function remove(marker,character)
    if active() and player.Character==character and marker.Parent==character
        and (marker.Name=="InjuredWalking" or marker.Name=="Crawling"
            or marker.Name=="Stun" and (marker:GetAttribute("InjuredWalking") or marker:GetAttribute("Crawling"))) then
        marker:Destroy()
        state.Removed+=1
    end
end
local function refresh()
    state.Status=not state.Enabled and "Off" or active() and "Red Light injury relief (local)" or "Waiting for Red Light"
    if not active() then return end
    local character=player.Character
    if character then
        for _,marker in ipairs(character:GetChildren())do remove(marker,character)end
    end
end
local function bind(character)
    disconnect(childConnection);childConnection=nil
    if character then
        childConnection=character.ChildAdded:Connect(function(marker)
            task.defer(function()remove(marker,character)end)
        end)
    end
    refresh()
end
function state:SetEnabled(enabled)
    enabled=enabled==true
    if self.Destroyed or self.Enabled==enabled then return end
    self.Enabled=enabled
    generation+=1
    if enabled then
        connections[#connections+1]=player.CharacterAdded:Connect(bind)
        bind(player.Character)
        local token=generation
        task.spawn(function()
            while state.Enabled and not state.Destroyed and generation==token do
                task.wait(.15)
                if state.Enabled and not state.Destroyed and generation==token then refresh()end
            end
        end)
    else
        disconnect(childConnection);childConnection=nil
        for _,c in ipairs(connections)do c:Disconnect()end
        table.clear(connections);self.Status="Off"
    end
end
function state:GetSnapshot()return {Version=self.Version,Enabled=self.Enabled,Status=self.Status,Removed=self.Removed}end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
end
return state
]====],]========]..source:sub(last+1)
end


-- Verified Tug QTE callback layout and native timing gate.
do
    local a,b=source:find("Tug=[====[",1,true)
    assert(a,"Tug module start was not found")
    local first,last=source:find("]====],",b+1,true)
    assert(first,"Tug module end was not found")
    source=source:sub(1,a-1)..[========[Tug=[====[
-- Ink Game Tug of War auto-pull, Potassium, v2.1
-- Starts OFF. Controlled only by the Allen Scripts hub switch.
-- Uses the live game's QTE click callback; no direct remote spam.
-- Re-run safely: the preceding instance disconnects itself.
-- Diagnostic snapshot: getgenv().__INK_TUG_AUTO_PULL:GetSnapshot()

if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 7008097940 then
    warn("[Ink Tug] This script is for Ink Game.")
    return
end
if type(getconnections) ~= "function" or not debug
    or type(debug.getupvalues) ~= "function" then
    warn("[Ink Tug] Potassium connection/upvalue inspection is required.")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Environment = getgenv()
local previous = Environment.__INK_TUG_AUTO_PULL
if previous and type(previous.Destroy) == "function" then
    pcall(previous.Destroy, previous)
end

local MAX_WINDOW = 26
local MIN_PRESS_INTERVAL = 0.2
local BIND_RETRY_INTERVAL = 0.25

local State = {
    Version = "2.1",
    Enabled = false,
    Destroyed = false,
    Engine = nil,
    Context = nil,
    NextBindAt = 0,
    LastPressAt = -math.huge,
    Presses = 0,
    LocalAdvances = 0,
    UnconfirmedPulls = 0,
    LocalMisses = 0,
    LockoutSkips = 0,
    Errors = 0,
    LastError = nil,
    LastWindow = nil,
    LastAngleError = nil,
    LastReason = "Off",
    BindingCount = 0,
}

local function angleError(a, b)
    return math.abs((a - b + 180) % 360 - 180)
end

local function visible(instance)
    if not instance or not instance:IsDescendantOf(PlayerGui) then return false end
    local current = instance
    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current = current.Parent
    end
    return current == PlayerGui
end

-- Identify the live onPress closure by its UI instance references, not by
-- guessed function names or by changing any of its captured values.
local function findPressFunction(callback, context, depth, visited)
    if depth > 2 or visited[callback] then return nil end
    visited[callback] = true
    local ok, values = pcall(debug.getupvalues, callback)
    if not ok or type(values) ~= "table" then return nil end
    if values[3] == context.Halftone and values[4] == context.Medium
        and values[5] == context.Arrow and values[16] == context.Button
        and type(values[2]) == "boolean" and type(values[6]) == "number"
        and type(values[17]) == "boolean" then
        return callback
    end
    local checked = 0
    for _, value in pairs(values) do
        if type(value) == "function" then
            checked += 1
            if checked > 12 then break end
            local found = findPressFunction(value, context, depth + 1, visited)
            if found then return found end
        end
    end
end

-- Verified current native success handler: inspect identity and read timing only.
local function findSuccessFunction(callback, context, depth, visited)
    if depth > 2 or visited[callback] then return nil end
    visited[callback] = true
    local ok, values = pcall(debug.getupvalues, callback)
    if not ok or type(values) ~= "table" then return nil end
    if values[9] == context.Arrow and values[10] == context.Button
        and values[11] == context.Medium and values[3]
        and values[3]:IsA("NumberValue") and type(values[5]) == "number"
        and type(values[6]) == "number" and type(values[7]) == "number" then
        return callback
    end
    local checked = 0
    for _, value in pairs(values) do
        if type(value) == "function" then
            checked += 1
            if checked > 12 then break end
            local found = findSuccessFunction(value, context, depth + 1, visited)
            if found then return found end
        end
    end
end

function State:Bind(root)
    if not root or not root:IsDescendantOf(PlayerGui) then return false end
    local circle = root:FindFirstChild("CircleBase")
    if not circle then return false end
    local context = {
        Root = root,
        Circle = circle,
        Arrow = circle:FindFirstChild("Arrow"),
        Medium = circle:FindFirstChild("Medium"),
        Button = circle:FindFirstChild("TextButton"),
        Halftone = circle:FindFirstChild("HalftoneWhenPressed"),
        Armed = false,
        LastGoal = nil,
        LastReason = "Bound",
    }
    if not (context.Arrow and context.Medium and context.Halftone
        and context.Button and context.Button:IsA("TextButton")) then return false end
    local ok, connections = pcall(getconnections, context.Button.MouseButton1Click)
    if not ok then return false end
    for _, connection in ipairs(connections) do
        local callback = connection.Function
        if type(callback) == "function" and connection.Enabled ~= false then
            local press = findPressFunction(callback, context, 0, {})
            local success = press and findSuccessFunction(press, context, 0, {})
            if press and success then
                context.Press = callback
                context.Read = function()
                    local values = debug.getupvalues(press)
                    if values[4] ~= context.Medium or values[5] ~= context.Arrow
                        or values[16] ~= context.Button
                        or type(values[6]) ~= "number"
                        or type(values[11]) ~= "number"
                        or type(values[17]) ~= "boolean" then
                        error("The native Tug of War handler changed; stopped safely.")
                    end
                    local samples = debug.getupvalues(success)
                    if samples[9] ~= context.Arrow or samples[10] ~= context.Button
                        or samples[11] ~= context.Medium or not samples[3]
                        or not samples[3]:IsA("NumberValue")
                        or type(samples[5]) ~= "number" or type(samples[6]) ~= "number"
                        or samples[7] ~= values[6] then
                        error("Native Tug timing layout changed; input stopped.")
                    end
                    return values[6], values[1] ~= nil and values[1] ~= false,
                        values[17], samples[3].Value, samples[5], samples[6]
                end
                self.Context = context
                self.BindingCount += 1
                self.LastReason = "Native QTE bound"
                return true
            end
        end
    end
    self.LastReason = "Waiting for native QTE click handler"
    return false
end

-- Runs only after the round, phase, character and GUI checks in Step.
-- Context.Read returns the actual native window and its input lock state.
function State:TryPull(context, now)
    local goal = context.Medium.Rotation
    local errorDegrees = angleError(goal, context.Arrow.Rotation)
    local window, blocked, ended, progressBefore, nativeFrames, nativeStep = context.Read()
    self.LastAngleError = errorDegrees
    if ended then
        self.LastReason = "QTE ended"
        return
    end
    if blocked then
        context.Armed = false
        self.LockoutSkips += 1
        self.LastReason = "Native miss lockout"
        return
    end
    if not (window > 0 and window <= MAX_WINDOW) then
        error("Unexpected native hit window: " .. tostring(window))
    end
    self.LastWindow = window
    -- Wait for a new goal or a full exit before accepting another pass.
    -- This also handles Rhythmical, which can keep the same goal angle.
    if context.LastGoal ~= nil and angleError(goal, context.LastGoal) > 0.01
        or errorDegrees > window + 2 then
        context.Armed = true
    end
    context.LastGoal = goal
    -- QF/QW are generated by the native render loop. Never submit a pull
    -- before that loop has recorded an actual in-window sample and motion.
    if type(nativeFrames) ~= "number" or nativeFrames < 1
        or type(nativeStep) ~= "number" or nativeStep <= 0 then
        self.LastReason = "Waiting for native QTE timing"
        return
    end
    if not context.Armed or now - self.LastPressAt < MIN_PRESS_INTERVAL then
        self.LastReason = "Waiting for next alignment"
        return
    end
    if errorDegrees > window * 0.55 then
        self.LastReason = "Waiting for center of hit window"
        return
    end

    context.Armed = false
    self.LastPressAt = now
    self.Presses += 1
    context.Press()
    local _, missed, _, progressAfter = context.Read()
    if missed then
        self.LocalMisses += 1
        self:SetEnabled(false)
        self.LastReason = "Stopped after native miss"
    elseif progressAfter > progressBefore or angleError(goal, context.Medium.Rotation) > 0.01 then
        self.LocalAdvances += 1
        self.LastReason = "Native QTE advanced locally"
    else
        self.UnconfirmedPulls += 1
        self:SetEnabled(false)
        self.LastReason = "Stopped after unconfirmed pull; manual input required"
    end
end

function State:ActiveRound()
    local values = workspace:FindFirstChild("Values")
    local currentGame = values and values:FindFirstChild("CurrentGame")
    if not currentGame or currentGame.Value ~= "TugOfWar" then
        return false, "Waiting for Tug of War"
    end
    if LocalPlayer:GetAttribute("TugOfWarPhase") ~= "QTE" then
        return false, "Waiting for QTE phase"
    end
    if LocalPlayer:FindFirstChild("QTEOver") then return false, "QTE finished" end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 or character:FindFirstChild("Dead") then
        return false, "Character unavailable"
    end
    return true
end

function State:Step(now)
    if not self.Enabled or self.Destroyed then return end
    local active, reason = self:ActiveRound()
    if not active then
        self.Context = nil
        self.LastReason = reason
        return
    end
    local context = self.Context
    if context and not context.Root:IsDescendantOf(PlayerGui) then
        self.Context = nil
        context = nil
    end
    if not context then
        if now >= self.NextBindAt then
            self.NextBindAt = now + BIND_RETRY_INTERVAL
            local screen = PlayerGui:FindFirstChild("TugOfWarUIV2")
            self:Bind(screen and screen:FindFirstChild("TugofWarRemake"))
        end
        if not self.Context then self.LastReason = "Waiting for verified QTE handler" end
        return
    end
    if not visible(context.Circle) then self.LastReason = "QTE hidden"; return end
    self:TryPull(context, now)
end

function State:SetEnabled(enabled)
    if self.Destroyed then return end
    self.Enabled = enabled == true
    if self.Engine then self.Engine:Disconnect(); self.Engine = nil end
    self.LastPressAt = -math.huge
    self.Context = nil
    self.NextBindAt = 0
    if self.Enabled then
        self.Engine = RunService.RenderStepped:Connect(function()
            local ok, message = pcall(self.Step, self, os.clock())
            if not ok then
                self.Errors += 1
                self.LastError = tostring(message)
                self:SetEnabled(false)
                self.LastReason = "Stopped: " .. self.LastError
                warn("[Ink Tug] " .. self.LastError)
            end
        end)
    else
        self.LastReason = "Off"
    end
end

function State:GetSnapshot()
    return {
        Version = self.Version, Enabled = self.Enabled,
        BindingCount = self.BindingCount, Bound = self.Context ~= nil,
        Phase = LocalPlayer:GetAttribute("TugOfWarPhase"),
        Presses = self.Presses, LocalAdvances = self.LocalAdvances,
        UnconfirmedPulls = self.UnconfirmedPulls, LocalMisses = self.LocalMisses,
        LockoutSkips = self.LockoutSkips, Status = self.LastReason,
        LastWindow = self.LastWindow, LastAngleError = self.LastAngleError,
        LastReason = self.LastReason, Errors = self.Errors, LastError = self.LastError,
        Note = "QTE advances are measured on the client.",
    }
end

function State:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false)
    self.Destroyed = true
    self.Context = nil
    if Environment.__INK_TUG_AUTO_PULL == self then
        Environment.__INK_TUG_AUTO_PULL = nil
    end
end

Environment.__INK_TUG_AUTO_PULL = State
State:SetEnabled(false)

State.HubOnly=true
return State

]====],]========]..source:sub(last+1)
end

local run,err=loadstring(source,"AllenScripts/GameRuntime")
assert(run,err)
return run()
