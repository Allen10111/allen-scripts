-- Allen Scripts general hub. All features start OFF.
local SOURCES={
Tug=[====[
-- Ink Game Tug of War auto-pull, Potassium, v1.0
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
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Environment = getgenv()
local previous = Environment.__INK_TUG_AUTO_PULL
if previous and type(previous.Destroy) == "function" then
    pcall(previous.Destroy, previous)
end

local MAX_WINDOW = 26
local EDGE_MARGIN = 2
local MIN_PRESS_INTERVAL = 1 / 30
local BIND_RETRY_INTERVAL = 0.25

local State = {
    Version = "1.1",
    Enabled = false,
    Destroyed = false,
    Connections = {},
    Engine = nil,
    Context = nil,
    PendingRoot = nil,
    NextBindAt = 0,
    LastPressAt = -math.huge,
    Presses = 0,
    AcceptedCallbacks = 0,
    NoopCallbacks = 0,
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
        and type(values[18]) == "boolean" then
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
        Armed = true,
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
            if press then
                context.Press = callback
                context.Read = function()
                    local values = debug.getupvalues(press)
                    if values[4] ~= context.Medium or values[5] ~= context.Arrow
                        or values[16] ~= context.Button
                        or type(values[6]) ~= "number"
                        or type(values[18]) ~= "boolean" then
                        error("The native Tug of War handler changed; stopped safely.")
                    end
                    return values[6], values[1] ~= nil and values[1] ~= false,
                        values[18], values[2]
                end
                self.Context = context
                self.PendingRoot = root
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
    self.LastAngleError = errorDegrees
    if context.LastGoal == nil or angleError(goal, context.LastGoal) > 0.01 then
        context.Armed = true
    end
    if errorDegrees > MAX_WINDOW then
        context.Armed = true
        self.LastReason = "Waiting for alignment"
        return false
    end
    local window, blocked, ended, directionBefore = context.Read()
    if ended then
        self.LastReason = "QTE ended"
        return false
    end
    if blocked then
        self.LockoutSkips += 1
        self.LastReason = "Native miss lockout"
        return false
    end
    if window <= 0 or window > MAX_WINDOW then
        error("Unexpected native hit window: " .. tostring(window))
    end
    self.LastWindow = window
    local triggerWindow = math.max(1, window - EDGE_MARGIN)
    if errorDegrees > triggerWindow then
        self.LastReason = "Waiting for hit window"
        return false
    end
    if not context.Armed or now - self.LastPressAt < MIN_PRESS_INTERVAL then
        self.LastReason = "Duplicate press suppressed"
        return false
    end
    context.Armed = false
    context.LastGoal = goal
    self.LastPressAt = now
    self.Presses += 1
    context.Press()
    local _, _, _, directionAfter = context.Read()
    if directionAfter ~= directionBefore then
        self.AcceptedCallbacks += 1
    else
        self.NoopCallbacks += 1
    end
    self.LastReason = "Native QTE press"
    return true
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
    if not active then self.LastReason = reason; return end
    local context = self.Context
    if context and not context.Root:IsDescendantOf(PlayerGui) then
        self.Context = nil
        context = nil
    end
    if not context then
        if now >= self.NextBindAt then
            self.NextBindAt = now + BIND_RETRY_INTERVAL
            self:Bind(self.PendingRoot)
        end
        self.LastReason = "Waiting for live QTE UI"
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
    if self.Context then self.Context.Armed = true end
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
        Presses = self.Presses, AcceptedCallbacks = self.AcceptedCallbacks,
        NoopCallbacks = self.NoopCallbacks, LockoutSkips = self.LockoutSkips,
        LastWindow = self.LastWindow, LastAngleError = self.LastAngleError,
        LastReason = self.LastReason, Errors = self.Errors, LastError = self.LastError,
        Note = "AcceptedCallbacks counts native handler responses, not server-confirmed wins.",
    }
end

function State:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false)
    self.Destroyed = true
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    self.Context = nil
    self.PendingRoot = nil
    if Environment.__INK_TUG_AUTO_PULL == self then
        Environment.__INK_TUG_AUTO_PULL = nil
    end
end

local function discovered(instance)
    if instance.Name == "TugofWarRemake" and instance:IsA("GuiObject") then
        State.PendingRoot = instance
        State.Context = nil
        State.NextBindAt = 0
    elseif instance.Name == "CircleBase" then
        local parent = instance.Parent
        if parent and parent.Name == "TugofWarRemake" then
            State.PendingRoot = parent
            State.Context = nil
            State.NextBindAt = 0
        end
    end
end

table.insert(State.Connections, PlayerGui.DescendantAdded:Connect(discovered))
table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(function()
    State.Context = nil
    State.NextBindAt = 0
    State.LastPressAt = -math.huge
end))
for _, instance in ipairs(PlayerGui:GetDescendants()) do discovered(instance) end
Environment.__INK_TUG_AUTO_PULL = State
State:SetEnabled(false)

State.HubOnly=true
return State

]====],
RLGL=[====[
-- Ink Game Red Light, Green Light: automatic stopping on red only.
-- Read-only light events; no outgoing remotes, raw keypresses or map indexing.
local Policy=(function()
local Policy={}
function Policy.InFinishZone(progress,lateral,height,halfDepth,halfWidth)
    return progress>=halfDepth+.15 and math.abs(lateral)<=halfWidth+3 and math.abs(height)<=20
end
function Policy.Light(packet)
    if type(packet)~="table" or packet.EffectName~="TrafficLight" then return nil end
    if packet.Over then return "over" end
    if packet.Setup then return "unknown" end
    if packet.RedLight then return "red" end
    if packet.GreenLight then return "green" end
    return nil
end
function Policy.Action(active,light,hasCharacter)
    if not active or not hasCharacter then return "idle" end
    if light=="red" then return "stop" end
    return "manual"
end
return Policy

end)()
assert(game.GameId==7008097940,"Open Ink Game to use Red Light, Green Light")
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local LP=Players.LocalPlayer
local env=getgenv()
if env.__ALLEN_INK_RLGL then env.__ALLEN_INK_RLGL:Destroy() end
local State={HubOnly=true,Enabled=false,Destroyed=false,Connections={},Light="unknown",Status="Off",Stops=0,Source="None"}
local renderName="AllenRLGL_"..HttpService:GenerateGUID(false)
local managing=false
local image,imageConnection
local characterConnection
local checkElapsed=0
local function connect(signal,callback)
    local c=signal:Connect(callback);table.insert(State.Connections,c);return c
end
local function character()
    local c=LP.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    local r=c and c:FindFirstChild("HumanoidRootPart")
    if c and h and r and h.Health>0 and not c:FindFirstChild("Dead") then return c,h,r end
end
local function finished()
    local values=workspace:FindFirstChild("Values")
    local current=values and values:FindFirstChild("CurrentGame")
    if not current or current.Value~="RedLightGreenLight" then return false end
    local c=LP.Character
    if not c then return false end
    if c:FindFirstChild("ReachedEnd") then State.FinishedCharacter=c;State.FinishSource="ReachedEnd" end
    if State.FinishedCharacter~=c then
        local r=c:FindFirstChild("HumanoidRootPart")
        local map=workspace:FindFirstChild("RedLightGreenLight")
        local sand=map and map:FindFirstChild("sand")
        local line=sand and sand:FindFirstChild("crossedover")
        local start=sand and sand:FindFirstChild("startingcrossedover")
        if r and line and start and line:IsA("BasePart") and start:IsA("BasePart") then
            local delta=line.Position-start.Position
            local forward=Vector3.new(delta.X,0,delta.Z)
            if forward.Magnitude>10 then
                forward=forward.Unit
                local right=forward:Cross(Vector3.yAxis)
                local relative=r.Position-line.Position
                local halfDepth=(math.abs(line.CFrame.RightVector:Dot(forward))*line.Size.X
                    +math.abs(line.CFrame.LookVector:Dot(forward))*line.Size.Z)*.5
                local halfWidth=(math.abs(line.CFrame.RightVector:Dot(right))*line.Size.X
                    +math.abs(line.CFrame.LookVector:Dot(right))*line.Size.Z)*.5
                if Policy.InFinishZone(relative:Dot(forward),relative:Dot(right),relative.Y,halfDepth,halfWidth) then
                    State.FinishedCharacter=c;State.FinishSource="sand.crossedover"
                end
            end
        end
    end
    return State.FinishedCharacter==c
end
local function active()
    if not State.Enabled or State.Light=="over" or LP:GetAttribute("IsGuard") then return false end
    if workspace:GetAttribute("RLGLOVER") then return false end
    if finished() then return false end
    local values=workspace:FindFirstChild("Values")
    local current=values and values:FindFirstChild("CurrentGame")
    local started=values and values:FindFirstChild("GameStarted")
    return current~=nil and current.Value=="RedLightGreenLight" and not (started and not started.Value)
end
local function stop(h,r)
    if h then h:Move(Vector3.zero,false);h.Jump=false end
    if r and not r.Anchored then
        local v=r.AssemblyLinearVelocity
        r.AssemblyLinearVelocity=Vector3.new(0,v.Y,0)
        r.AssemblyAngularVelocity=Vector3.zero
    end
end
local function release()
    if managing then
        local _,h=character()
        if h then h:Move(Vector3.zero,false) end
    end
    managing=false
end
local function setLight(value,source)
    if not value then return end
    local changed=State.Light~=value
    State.Light=value;State.Source=source
    if value=="red" and active() then
        local _,h,r=character()
        managing=true;stop(h,r)
        if value=="red" and changed then State.Stops+=1 end
    else release() end
end
local function assetId(value) return tostring(value):match("%d+") end
local function bindImage()
    local pg=LP:FindFirstChildOfClass("PlayerGui")
    local frames=pg and pg:FindFirstChild("ImpactFrames")
    local current=frames and frames:FindFirstChild("TrafficLightEmpty")
    if current==image then return end
    if imageConnection then imageConnection:Disconnect();imageConnection=nil end
    image=current
    if not image or not (image:IsA("ImageLabel") or image:IsA("ImageButton")) then image=nil;return end
    local effects=RS:FindFirstChild("Effects")
    local images=effects and effects:FindFirstChild("Images")
    local traffic=images and images:FindFirstChild("TrafficLights")
    local green=traffic and traffic:FindFirstChild("GreenLight")
    local red=traffic and traffic:FindFirstChild("RedLight")
    if not green or not red then return end
    local greenId,redId=assetId(green.Image),assetId(red.Image)
    local function read()
        if not State.Enabled or State.Light=="over" or not image then return end
        local id=assetId(image.Image)
        if redId and id==redId then setLight("red","Native traffic-light UI")
        elseif greenId and id==greenId then setLight("green","Native traffic-light UI")
        else setLight("unknown","Native traffic-light UI") end
    end
    imageConnection=image:GetPropertyChangedSignal("Image"):Connect(read)
    read()
end
local function step()
    if not active() then
        release()
        State.Status=State.Enabled and (finished() and "Finish reached · free movement" or State.Light=="over" and "Round ended" or "Waiting for Red Light, Green Light") or "Off"
        return
    end
    local c,h,r=character()
    if not c then release();State.Status="Waiting for character";return end
    local action=Policy.Action(true,State.Light,true)
    if action=="stop" then
        -- Default PC/touch controls remain enabled. Override movement after their update,
        -- so held keys and the thumbstick keep their normal state when green returns.
        managing=true;stop(h,r)
        State.Status="Red light · stopped"
    else
        release()
        State.Status=State.Light=="green" and "Green light · manual movement" or "Waiting for light signal · manual movement"
    end
end
function State:SetEnabled(value)
    if self.Destroyed then return end
    value=value==true
    if self.Enabled==value then return end
    if value then
        self.Enabled=true;self.Light="unknown";self.Source="None";self.Status="Waiting for light signal"
        image=nil;bindImage()
    else
        self.Enabled=false;release()
        if imageConnection then imageConnection:Disconnect();imageConnection=nil end
        image=nil;self.Light="unknown";self.Status="Off"
    end
end
function State:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Light=self.Light,Stops=self.Stops,Signal=self.Source,Finished=finished(),FinishSource=self.FinishSource}
end
function State:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    RunService:UnbindFromRenderStep(renderName)
    if characterConnection then characterConnection:Disconnect();characterConnection=nil end
    for _,c in ipairs(self.Connections) do c:Disconnect() end
    table.clear(self.Connections)
    if env.__ALLEN_INK_RLGL==self then env.__ALLEN_INK_RLGL=nil end
end
local remotes=RS:FindFirstChild("Remotes")
local effect=remotes and remotes:FindFirstChild("Effects")
assert(effect and effect:IsA("RemoteEvent"),"Native traffic-light event is unavailable")
connect(effect.OnClientEvent,function(packet)
    if State.Enabled then setLight(Policy.Light(packet),"Native TrafficLight event") end
end)
local function watchCharacter(c)
    if characterConnection then characterConnection:Disconnect();characterConnection=nil end
    if not c then return end
    characterConnection=c.ChildAdded:Connect(function(child)
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        if child.Name=="ReachedEnd" and current and current.Value=="RedLightGreenLight" then
            State.FinishedCharacter=c;State.FinishSource="ReachedEnd";release()
            if State.Enabled then State.Status="Finish reached · free movement" end
        end
    end)
end
watchCharacter(LP.Character)
connect(LP.CharacterAdded,function(c)
    release();State.Light="unknown";image=nil
    State.FinishedCharacter=nil;State.FinishSource=nil;watchCharacter(c)
    if imageConnection then imageConnection:Disconnect();imageConnection=nil end
end)
local values=workspace:FindFirstChild("Values")
local current=values and values:FindFirstChild("CurrentGame")
if current then connect(current.Changed,function()
    release();State.Light="unknown";image=nil
    State.FinishedCharacter=nil
    State.FinishSource=nil
end) end
RunService:BindToRenderStep(renderName,Enum.RenderPriority.Input.Value+1,function(dt)
    if State.Destroyed or not State.Enabled then return end
    local ok,err=pcall(function()
        checkElapsed+=dt
        if checkElapsed>=.5 then checkElapsed=0;bindImage() end
        step()
    end)
    if not ok then State:SetEnabled(false);State.Status="Stopped: "..tostring(err):sub(1,120);warn("[Ink RLGL] "..tostring(err)) end
end)
env.__ALLEN_INK_RLGL=State
return State

]====],
RemoteSpy=[====[
-- Allen Scripts adapter for the Cobalt loader used by Infinite Yield's remotespy command.
-- Upstream Cobalt: https://gitlab.com/upio/cobalt/ (deivid / upio).
-- No interception hooks are installed by this adapter itself. Starts OFF.
local URL="https://gitlab.com/upio/cobalt/-/releases/permalink/latest/downloads/Cobalt.luau"
local env=getgenv()
if env.__ALLEN_REMOTE_SPY then env.__ALLEN_REMOTE_SPY:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Loading=false,Status="Off",Generation=0}
local owned
local function sharedOf(value)
    return type(value)=="table"and type(value.shared)=="table"and value.shared or nil
end
local function unload()
    local current=owned;owned=nil
    local shared=sharedOf(current)
    if shared and not shared.Unloaded then
        assert(type(shared.Unload)=="function","Cobalt unload API changed; use Cobalt's own unload control")
        shared.Unload()
    end
end
function S:SetEnabled(value)
    if self.Destroyed then return end
    if value~=true then
        self.Generation+=1;self.Enabled=false
        local ok,err=pcall(unload)
        self.Status=ok and (self.Loading and "Cancelling Cobalt load"or"Off")or("Unload failed: "..tostring(err):sub(1,110))
        return
    end
    if self.Enabled then return end
    assert(not self.Loading,"Wait for the previous Cobalt load to finish")
    assert(not env.Cobalt and not env.CobaltInitialized,"Cobalt is already running or initializing; unload it first")
    self.Generation+=1;local generation=self.Generation
    self.Enabled=true;self.Loading=true;self.Status="Loading Cobalt · same loader as Infinite Yield"
    task.spawn(function()
        local startedHere=false
        local ok,err=pcall(function()
            local source=game:HttpGet(URL)
            assert(type(source)=="string"and #source>0,"Cobalt download was empty")
            if generation~=self.Generation or self.Destroyed then return end
            assert(not env.Cobalt and not env.CobaltInitialized,"Another Cobalt instance started during download")
            local fn,compileError=loadstring(source,"AllenCobaltUpstream")
            assert(fn,compileError)
            startedHere=true;fn()
            -- Official bundle starts its entrypoint asynchronously.
            local deadline=os.clock()+60
            while not env.Cobalt and os.clock()<deadline do task.wait(.1)end
            local current=env.Cobalt;local shared=sharedOf(current)
            assert(shared and type(shared.Unload)=="function","Cobalt did not expose its unload API; restart before retrying")
            owned=current
            if generation~=self.Generation or self.Destroyed or not self.Enabled then unload();return end
            self.Status="Cobalt open · incoming / outgoing inspector"
        end)
        self.Loading=false
        if not ok then
            self.Enabled=false;self.Status="Cobalt failed: "..tostring(err):sub(1,150)
            if startedHere then pcall(unload)end
            warn("[Allen Remote Spy] "..tostring(err))
        elseif not self.Enabled then self.Status="Off"end
    end)
end
function S:GetSnapshot()
    local shared=sharedOf(owned)
    if owned and (env.Cobalt~=owned or shared and shared.Unloaded)then
        owned=nil;self.Enabled=false;self.Status="Cobalt closed"
    end
    return {Enabled=self.Enabled,Status=self.Status,Loading=self.Loading}
end
function S:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if env.__ALLEN_REMOTE_SPY==self then env.__ALLEN_REMOTE_SPY=nil end
end
env.__ALLEN_REMOTE_SPY=S
return S

]====],
BladeParry=[====[
-- Allen Scripts: Experimental Blade Ball auto parry, disabled.
error("Auto Parry disabled after a BAC anti-cheat kick during testing")
assert(game.GameId==4777817887,"Open Blade Ball")
local VirtualInput=game:GetService("VirtualInputManager")
local LP=game:GetService("Players").LocalPlayer
local env=getgenv()
if env.__BLADE_AUTO_PARRY then env.__BLADE_AUTO_PARRY:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Connections={},Balls={},Requests=0,Successes=0,Errors=0,NextRequest=0,Status="Off"}
local function native()
    return function()
        local gui=LP:FindFirstChild("PlayerGui")
        if not gui or not gui:FindFirstChild("Hotbar") then return false end
        VirtualInput:SendKeyEvent(true,Enum.KeyCode.F,false,game)
        S.KeyDown=true
        task.delay(.035,function()
            pcall(function()VirtualInput:SendKeyEvent(false,Enum.KeyCode.F,false,game)end)
            S.KeyDown=false
        end)
        return true
    end
end
local function invoke(fn)return fn()end
function S:ShouldParry(relative,velocity,radius,lead)
    local distance=relative.Magnitude
    if distance<=radius then return true,0 end
    if velocity.Magnitude<1 then return false end
    local closing=-relative.Unit:Dot(velocity)
    if closing<=1 then return false end
    local eta=(distance-radius)/closing
    local t=math.clamp(-relative:Dot(velocity)/math.max(velocity:Dot(velocity),1),0,lead+.15)
    local clearance=(relative+velocity*t).Magnitude
    return eta<=lead and clearance<=radius+3,eta
end
function S:SetEnabled(on)
    if self.KeyDown then pcall(function()VirtualInput:SendKeyEvent(false,Enum.KeyCode.F,false,game)end);self.KeyDown=false end
    self.Enabled=on==true and not self.Destroyed;self.NextRequest=0;table.clear(self.Balls)
    self.Status=self.Enabled and "Watching incoming ball"or"Off"
end
function S:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Requests=self.Requests,Successes=self.Successes,Errors=self.Errors,LastError=self.LastError,ETA=self.ETA}
end
function S:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    for _,c in ipairs(self.Connections)do c:Disconnect()end
    if env.__BLADE_AUTO_PARRY==self then env.__BLADE_AUTO_PARRY=nil end
end
function S:Step(dt)
    local character=LP.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local training=LP:GetAttribute("LobbyTraining")==true
    if not root or not humanoid or humanoid.Health<=0 or (character.Parent~=workspace:FindFirstChild("Alive")and not training)then self.Status="Waiting for round";table.clear(self.Balls);return end
    if character:GetAttribute("Stunned")or character:GetAttribute("DoNotParry")then self.Status="Native parry unavailable";return end
    local now=os.clock()
    if not self.Native or now>=(self.RefreshAt or 0)then self.Native=native();self.RefreshAt=now+2 end
    if not self.Native then self.Status="Waiting for parry controls";return end
    local seen={};local best,bestETA,bestRecord
    local ping=LP:GetNetworkPing()
    local lead=math.clamp(.14+ping+math.min(dt,.05),.15,.32)
    for _,name in ipairs(training and {"Balls","TrainingBalls"}or{"Balls"})do
        local folder=workspace:FindFirstChild(name)
        if folder then
            for index,ball in ipairs(folder:GetChildren())do
                if index>64 then break end
                if ball:IsA("BasePart")and ball:GetAttribute("realBall")==true then
                    seen[ball]=true
                    local target=ball:GetAttribute("target")
                    local record=self.Balls[ball]
                    if not record then record={};self.Balls[ball]=record end
                    if record.Target~=target then record.Fired=false;record.Target=target end
                    local velocity=ball.AssemblyLinearVelocity
                    if record.Position and record.At and now-record.At>.004 and now-record.At<.2 then
                        local measured=(ball.Position-record.Position)/(now-record.At)
                        if measured.Magnitude>velocity.Magnitude*1.5 and measured.Magnitude<1600 then velocity=measured end
                    end
                    record.Position=ball.Position;record.At=now
                    if target==LP.Name and not record.Fired then
                        local radius=6+math.min(ball.Size.Magnitude*.5,4)
                        local due,eta=self:ShouldParry(ball.Position-root.Position,velocity-root.AssemblyLinearVelocity,radius,lead)
                        if due and(not bestETA or eta<bestETA)then best=ball;bestETA=eta;bestRecord=record end
                    end
                end
            end
        end
    end
    for ball in pairs(self.Balls)do if not seen[ball]then self.Balls[ball]=nil end end
    self.ETA=bestETA
    if best and now>=self.NextRequest then
        self.NextRequest=now+.20
        if invoke(self.Native)==true then
            bestRecord.Fired=true;self.Requests+=1;self.Status="Parry requested · "..self.Requests
        else self.Status="Native cooldown"end
    elseif not best then self.Status="Watching incoming ball"end
end
S.Connections[#S.Connections+1]=game:GetService("RunService").Heartbeat:Connect(function(dt)
    if not S.Enabled or S.Destroyed then return end
    local ok,err=pcall(S.Step,S,dt)
    if not ok then S.Errors+=1;S.LastError=tostring(err);S:SetEnabled(false);S.Status="Stopped: "..tostring(err):sub(1,100);warn("[Blade Auto Parry] "..tostring(err))end
end)
local remotes=game.ReplicatedStorage:FindFirstChild("Remotes")
local success=remotes and remotes:FindFirstChild("ParrySuccess")
if success then S.Connections[#S.Connections+1]=success.OnClientEvent:Connect(function()
    if S.Enabled then S.Successes+=1 end
end)end
env.__BLADE_AUTO_PARRY=S
return S

]====],
BladeBeep=[====[
-- Allen Scripts: Blade Ball red-ball sound notice. No automatic input.
assert(game.GameId==4777817887,"Open Blade Ball")
local env=getgenv()
if env.__BLADE_BALL_BEEP then env.__BLADE_BALL_BEEP:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Connections={},Roots={},Balls={},Beeps=0,Errors=0,Status="Off"}
local sound=Instance.new("Sound")
sound.Name="AllenRedBallBeep"
sound.SoundId="rbxasset://sounds/electronicpingshort.wav"
sound.Volume=3;sound.PlaybackSpeed=1.4
sound.Parent=game:GetService("SoundService")
local function disconnect(list)for _,c in ipairs(list)do c:Disconnect()end;table.clear(list)end
function S:IsRed(ball)
    if ball:GetAttribute("realBall")==true then return false end -- the visible clone carries the red flag
    local highlighted=ball:GetAttribute("highlighted")
    if type(highlighted)=="boolean"then return highlighted end
    local color=ball.Color
    return color.R>.6 and color.R>color.G*1.8 and color.R>color.B*1.8
end
function S:Evaluate(ball)
    local record=self.Balls[ball];if not record or not self.Enabled then return end
    local red=ball.Parent~=nil and self:IsRed(ball)
    if red and not record.Red then
        sound:Stop();sound.TimePosition=0;sound:Play()
        self.Beeps+=1
        self.Status="Red ball · beep"
        self.SoundGeneration=(self.SoundGeneration or 0)+1
        local generation=self.SoundGeneration
        task.delay(.16,function()if not self.Destroyed and self.SoundGeneration==generation then sound:Stop()end end)
    end
    record.Red=red
end
function S:Forget(ball)
    local record=self.Balls[ball]
    if record then disconnect(record.Connections);self.Balls[ball]=nil end
end
function S:Watch(ball)
    if not ball:IsA("BasePart")or self.Balls[ball]then return end
    local count=0;for _ in pairs(self.Balls)do count+=1 end
    if count>=64 then return end
    local record={Red=false,Connections={}}
    self.Balls[ball]=record
    local function check()
        local ok,err=pcall(self.Evaluate,self,ball)
        if not ok then self.Errors+=1;self.LastError=tostring(err);self.Status="Alert error"end
    end
    for _,name in ipairs({"highlighted","realBall"})do record.Connections[#record.Connections+1]=ball:GetAttributeChangedSignal(name):Connect(check)end
    record.Connections[#record.Connections+1]=ball:GetPropertyChangedSignal("Color"):Connect(check)
    record.Connections[#record.Connections+1]=ball.AncestryChanged:Connect(function()if not ball.Parent then self:Forget(ball)end end)
    check()
end
function S:Bind(root)
    if self.Roots[root]then return end
    local list={}
    self.Roots[root]=list
    list[#list+1]=root.ChildAdded:Connect(function(ball)self:Watch(ball)end)
    list[#list+1]=root.ChildRemoved:Connect(function(ball)self:Forget(ball)end)
    for _,ball in ipairs(root:GetChildren())do self:Watch(ball)end
end
function S:SetEnabled(on)
    if self.Destroyed then return end
    disconnect(self.Connections)
    for root,list in pairs(self.Roots)do disconnect(list);self.Roots[root]=nil end
    local all={};for ball in pairs(self.Balls)do all[#all+1]=ball end
    for _,ball in ipairs(all)do self:Forget(ball)end
    sound:Stop();self.SoundGeneration=(self.SoundGeneration or 0)+1
    self.Enabled=on==true;self.Status=self.Enabled and "Watching red-ball changes"or"Off"
    if not self.Enabled then return end
    local function add(root)if root.Name=="Balls"or root.Name=="TrainingBalls"then self:Bind(root)end end
    self.Connections[#self.Connections+1]=workspace.ChildAdded:Connect(add)
    self.Connections[#self.Connections+1]=workspace.ChildRemoved:Connect(function(root)
        local list=self.Roots[root];if list then disconnect(list);self.Roots[root]=nil end
        for _,ball in ipairs(root:GetChildren())do self:Forget(ball)end
    end)
    for _,root in ipairs(workspace:GetChildren())do add(root)end
end
function S:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Beeps=self.Beeps,Errors=self.Errors,SoundLoaded=sound.IsLoaded,LastError=self.LastError}
end
function S:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true;sound:Destroy()
    if env.__BLADE_BALL_BEEP==self then env.__BLADE_BALL_BEEP=nil end
end
env.__BLADE_BALL_BEEP=S
return S

]====],
FNP=[====[
-- Allen Scripts: Friday Night Partying native note scheduler. Hub only.
assert(game.GameId==10258128048,"Open Friday Night Partying")
assert(debug and type(debug.getupvalues)=="function" and type(getconnections)=="function","Executor needs getconnections and debug.getupvalues")
local env=getgenv()
if env.__FNP_AUTOPLAY then env.__FNP_AUTOPLAY:Destroy()end
local LP=game:GetService("Players").LocalPlayer
local ui=LP:WaitForChild("PlayerGui"):WaitForChild("GameUI",10)
assert(ui and ui:FindFirstChild("GameHandler"),"Game engine not ready")
local handler=require(ui.GameHandler)
local native=getfenv(handler.genSong)
local good=native.Goodhit
local modules=game.ReplicatedStorage.Modules
local conductor=require(modules.Conductor)
local inputs=require(modules.UserInputBindables)
local began,check
for _,c in ipairs(getconnections(inputs.InputEvents.Began))do
    local f=c.Function
    if f and debug.info(f,"s")==ui.GameHandler:GetFullName() then
        local candidate=debug.getupvalues(f)[2]
        if type(candidate)=="function" and debug.info(candidate,"n")=="CheckInput"then began=f;check=candidate;break end
    end
end
assert(type(good)=="function" and check,"Native note handlers unavailable")
local layout=debug.getupvalues(check)
assert(type(layout[4])=="table" and type(layout[5])=="table" and type(layout[7])=="table","Unsupported lane engine layout")
local state={HubOnly=true,Enabled=false,Destroyed=false,Hits=0,Holds=0,Errors=0,Skipped=0,Held={},Status="Off",Seen=setmetatable({},{__mode="k"})}
local function call(fn,...)
    local gi=getthreadidentity or getidentity;local si=setthreadidentity or setidentity
    local identity=gi and gi();if si and identity then si(2)end
    local ok,err=pcall(fn,...)
    if si and identity then si(identity)end
    if not ok then error(err,0)end
end
function state:Release()
    for receptor in pairs(self.Held)do
        pcall(function()receptor.Holding=false;call(receptor.PlayAnimation,receptor,"static")end)
    end
    table.clear(self.Held)
end
function state:SetEnabled(value)
    self:Release();self.Enabled=value==true and not self.Destroyed
    self.Status=self.Enabled and "Waiting for song"or"Off"
end
function state:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Hits=self.Hits,Holds=self.Holds,Skipped=self.Skipped,Errors=self.Errors,LastError=self.LastError}
end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if self.Connection then self.Connection:Disconnect()end
    if env.__FNP_AUTOPLAY==self then env.__FNP_AUTOPLAY=nil end
end
function state:Step(dt)
    if not debug.getupvalues(began)[1] or not ui.Enabled then self:Release();self.Status="Waiting for song";return end
    local up=debug.getupvalues(check)
    local heads,receptors,tails=up[4],up[5],up[7]
    local now=conductor.SongPos
    if type(now)~="number"or now~=now then return end
    local due={};local scanned=0
    local lead=math.min(dt*500,8)
    for _,group in ipairs({heads,tails})do
        for lane,notes in pairs(group)do
            local receptor=receptors[lane]
            for _,note in ipairs(notes)do
                scanned+=1;if scanned>2048 then error("Active note limit exceeded")end
                if not note.Destroyed and not note.GoodHit and note.MustPress and not self.Seen[note] then
                    if note.shouldPress==false or (tonumber(note.HealthLoss)or 0)>0 then
                        self.Seen[note]=true;self.Skipped+=1
                    elseif note.CanBeHit and not note.TooLate and receptor and receptor.CanBePressed
                        and type(note.StrumTime)=="number" and note.StrumTime-now<=lead and note.StrumTime-now>=-100 then
                        due[#due+1]={Note=note,Receptor=receptor}
                    end
                end
            end
        end
    end
    table.sort(due,function(a,b)return a.Note.StrumTime<b.Note.StrumTime end)
    for _,entry in ipairs(due)do
        local note=entry.Note
        if not note.GoodHit and not note.Destroyed then
            call(good,note)
            self.Seen[note]=true
            if note.GoodHit then
                if note.IsSustain then self.Holds+=1 else self.Hits+=1 end
                self.Held[entry.Receptor]=os.clock()+.10
            end
        end
    end
    for receptor,untilTime in pairs(self.Held)do
        if os.clock()>=untilTime then
            receptor.Holding=false;call(receptor.PlayAnimation,receptor,"static");self.Held[receptor]=nil
        end
    end
    self.Status="Playing · native note timing"
end
state.Connection=game:GetService("RunService").RenderStepped:Connect(function(dt)
    if not state.Enabled or state.Destroyed then return end
    local ok,err=pcall(state.Step,state,dt)
    if not ok then state.Errors+=1;state.LastError=tostring(err);state:SetEnabled(false);state.Status="Stopped: "..tostring(err):sub(1,100);warn("[FNP Autoplay] "..tostring(err))end
end)
env.__FNP_AUTOPLAY=state
return state

]====],
BFNF=[====[
-- Allen Scripts: Basically FNF: Remix. Native lane input, hub controls only.
assert(game.GameId==2443177453,"Open Basically FNF: Remix")
assert(type(getfenv)=="function" and debug and type(debug.getupvalues)=="function","Executor requires getfenv and debug.getupvalues")
local env=getgenv()
if env.__BFNF_AUTOPLAY then env.__BFNF_AUTOPLAY:Destroy() end
local LP=game:GetService("Players").LocalPlayer
local main=LP:WaitForChild("PlayerGui"):WaitForChild("Main",10)
assert(main and main:FindFirstChild("FNFMain"),"Note engine not ready")
local module=require(main.FNFMain.Modules.songPlay)
local native=getfenv(module.PlaySong)
assert(type(native.KeyPress)=="function" and type(native.KeyLift)=="function" and type(native.NoteInput)=="function","Native input handlers unavailable")
local function up(fn) return debug.getupvalues(fn) end
-- Validate the inspected native layout before accessing mutable lane data.
local p,n=up(native.KeyPress),up(native.NoteInput)
assert(type(p[3])=="function" and type(p[5])=="table" and typeof(n[3])=="Instance" and type(n[5])=="table" and type(n[6])=="table","Unsupported note engine layout")
local state={HubOnly=true,Enabled=false,Destroyed=false,Held={},Seen=setmetatable({},{__mode="k"}),Hits=0,Holds=0,Errors=0,Status="Off"}
local activity,lastActivity
local function findActivity()
    assert(type(getgc)=="function","Anti AFK needs getgc support")
    local afk=LP.PlayerScripts:FindFirstChild("AfkSys")
    local remote=game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    remote=remote and remote:FindFirstChild("AFKEvent")
    assert(afk and remote,"Native AFK interface unavailable")
    local found
    for _,fn in ipairs(getgc())do
        if type(fn)=="function"then
            local ok,e=pcall(getfenv,fn)
            if ok and e.script==afk and debug.info(fn,"n")=="updateActivity"then
                local values=up(fn);local hasRemote,hasClock,hasFlag=false,false,false
                for _,v in pairs(values)do
                    if v==remote then hasRemote=true elseif type(v)=="number"then hasClock=true elseif type(v)=="boolean"then hasFlag=true end
                end
                if hasRemote and hasClock and hasFlag then assert(not found or found==fn,"Ambiguous AFK handler");found=fn end
            end
        end
    end
    assert(found,"Native AFK activity handler unavailable")
    return found
end
local function call(fn,...)
    local getid=getthreadidentity or getidentity
    local setid=setthreadidentity or setidentity
    local id=getid and getid()
    if setid and id then setid(2) end
    local ok,err=pcall(fn,...)
    if setid and id then setid(id) end
    if not ok then error(err,0) end
end
function state:ReleaseLane(lane)
    local h=self.Held[lane]
    if h then
        self.Held[lane]=nil
        local lift=up(native.KeyLift)
        if lift[1] and lift[6]==h.Side then
            call(native.KeyLift,h.Input,false)
        else
            -- KeyLift ignores input after a song ends; clear only our owned key.
            lift[3][h.Input.KeyCode]=nil
            lift[4][lane]=false
            local skin=lift[5][h.Side] and lift[5][h.Side][lane]
            if skin then call(skin.Release,skin) end
        end
    end
end
function state:Release()
    for lane=1,4 do local ok,err=pcall(self.ReleaseLane,self,lane);if not ok then self.LastError=tostring(err) end end
end
function state:SetEnabled(value)
    if value==true and not self.Destroyed then activity=findActivity();activity();lastActivity=os.clock()end
    self:Release();self.Enabled=value==true and not self.Destroyed
    self.Status=self.Enabled and "Waiting for song" or "Off"
end
function state:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Hits=self.Hits,Holds=self.Holds,Errors=self.Errors,LastError=self.LastError}
end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if self.Connection then self.Connection:Disconnect() end
    if env.__BFNF_AUTOPLAY==self then env.__BFNF_AUTOPLAY=nil end
end
function state:Step(dt)
    if activity and os.clock()-(lastActivity or 0)>=20 then activity();lastActivity=os.clock()end
    local press=up(native.KeyPress)
    local noteUp=up(native.NoteInput)
    local active,side=press[1],press[8]
    if not active or not main.MatchFrame.Visible or not LP:FindFirstChild("CurrentMatch") then
        self:Release();self.Status="Waiting for song";return
    end
    local lanes=noteUp[5][side]
    local settings=getfenv(native.NoteInput)._G.Settings
    local direction=settings.Direction
    local speed=tonumber(noteUp[4])
    if not lanes or not speed or speed<=0 or (direction~=1 and direction~=-1) then self:Release();self.Status="Waiting for lanes";return end
    local keys=up(press[3])[1]
    local now=os.clock()
    self.Status="Playing · native lanes"
    for lane=1,4 do
        local data=lanes[lane]
        local h=self.Held[lane]
        if h then
            local hold=data and data.holding
            if h.Side~=side or not hold or not hold.Parent then
                if h.Side~=side or now>=h.ReleaseAt then self:ReleaseLane(lane) end
            elseif math.abs(hold.Size.Y.Scale)+hold.Position.Y.Scale*direction<=0.5 then
                self:ReleaseLane(lane)
            end
        end
        if data then
            local idx=data.index
            local note=data.notes[idx]
            -- Mirror the native closest-note choice without modifying its index.
            local nextNote=data.notes[idx+1]
            if nextNote and nextNote.Parent and (not note or not note.Parent or math.abs(nextNote.Position.Y.Scale)<math.abs(note.Position.Y.Scale)) then note=nextNote end
            if note and note.Parent and not self.Seen[note] then
                local timeLeft=note.Position.Y.Scale*direction/(5.5*speed)
                -- Render-step midpoint targeting; late notes outside the native window are skipped.
                if timeLeft<=math.min(dt*0.5,0.012) and timeLeft>=-0.11 then
                    if self.Held[lane] and not data.holding then self:ReleaseLane(lane) end
                    if not self.Held[lane] then
                        local key=keys and Enum.KeyCode[keys[lane]]
                        assert(key,"Lane keybinding unavailable")
                        local input={UserInputType=Enum.UserInputType.Keyboard,KeyCode=key}
                        call(native.KeyPress,input,false)
                        self.Held[lane]={Input=input,Side=side,ReleaseAt=now+0.025}
                        self.Seen[note]=true
                        if not note.Parent then self.Hits+=1;if data.holding then self.Holds+=1 end end
                    end
                end
            end
        end
    end
end
state.Connection=game:GetService("RunService").RenderStepped:Connect(function(dt)
    if not state.Enabled or state.Destroyed then return end
    local ok,err=pcall(state.Step,state,dt)
    if not ok then
        state.Errors+=1;state.LastError=tostring(err);state:Release()
        state.Enabled=false;state.Status="Stopped: "..tostring(err):sub(1,100)
        warn("[BFNF Autoplay] "..tostring(err))
    end
end)
env.__BFNF_AUTOPLAY=state
return state

]====],
Shindo=[====[
-- Allen Scripts: Shindo Life native local movement evasions. Hub controlled, starts OFF.
-- Combat values and projectile motion are replicated evidence; range envelopes
-- are defensive heuristics, not a copy of server hitboxes or invulnerability.
if game.GameId ~= 1511883870 then return end
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local LP=Players.LocalPlayer
local UIS=game:GetService("UserInputService")
local env=getgenv()
if env.__SHINDO_AUTO_DODGE then env.__SHINDO_AUTO_DODGE:Destroy() end
local S={Enabled=false,HubOnly=true,Destroyed=false,Connections={},Watchers={},Projectiles={},Powers={},
    Threats={},Replay={},Requests=0,Acknowledged=0,Errors=0,Detected=0,NextRequest=0,
    Status="Off",Generation=0,NextScan=0,NextTick=0,LastHit="None",Version=7}
env.__SHINDO_AUTO_DODGE=S
local ZERO=Vector3.zero
local identityGet=getthreadidentity or getidentity
local identitySet=setthreadidentity or setidentity
assert(type(getconnections)=="function" and debug and type(debug.info)=="function"
    and type(identityGet)=="function" and type(identitySet)=="function",
    "Shindo Auto Dodge needs getconnections, debug.info, and thread identity APIs")
local function value(folder,name,fallback)
    local v=folder and folder:FindFirstChild(name)
    return v and v:IsA("ValueBase") and v.Value or fallback
end
local function flat(v)
    local h=Vector3.new(v.X,0,v.Z)
    return h.Magnitude>0.001 and h.Unit or Vector3.new(0,0,-1)
end
local function log(kind,data)
    local e=data or {};e.Kind=kind;e.At=os.clock()
    S.Replay[#S.Replay+1]=e
    if #S.Replay>64 then table.remove(S.Replay,1)end
end
local function disconnect(list)
    for _,c in ipairs(list)do c:Disconnect()end
    table.clear(list)
end
local function localParts()
    local c=LP.Character
    return c,c and c:FindFirstChildOfClass("Humanoid"),c and c:FindFirstChild("HumanoidRootPart"),c and c:FindFirstChild("combat")
end
local function ownerOf(part,folder)
    local current=part
    for _=1,5 do
        if not current or current==folder then break end
        local o=current:FindFirstChild("owner") or current:FindFirstChild("Owner")
        if o and o:IsA("ObjectValue")then return o.Value end
        current=current.Parent
    end
end
local function ownProjectile(part,folder)
    local owner=ownerOf(part,folder)
    return owner==LP or owner==LP.Character
end
-- Constant relative-velocity closest approach, shared by detection and route scoring.
function S:ClosestApproach(relative,velocity,horizon,radius)
    local speed2=velocity:Dot(velocity)
    local t=speed2>0.001 and math.clamp(-relative:Dot(velocity)/speed2,0,horizon) or 0
    return (relative+velocity*t).Magnitude-radius,t
end
function S:RememberProjectile(part)
    if not part:IsA("BasePart") then
        if (part.Name=="owner" or part.Name=="Owner" or part:IsA("TouchTransmitter")) and part.Parent then
            self:RememberProjectile(part.Parent)
        end
        return
    end
    local folder
    for _,candidate in ipairs(self.HazardRoots or {})do
        if part:IsDescendantOf(candidate)then folder=candidate;break end
    end
    if not folder or part.Name:lower():find("mouse",1,true)
        or ownProjectile(part,folder) or self.Projectiles[part] then return end
    local touch=part:FindFirstChildOfClass("TouchTransmitter")
    if folder.Name=="ClientEffects" and not touch then return end -- cosmetic FX alone are not hitboxes
    if not ownerOf(part,folder) and not touch then return end
    local count=0;for _ in pairs(self.Projectiles)do count+=1 end
    if count>=160 then return end
    self.Projectiles[part]={Position=part.Position,At=os.clock(),Folder=folder,ZoneKeys={}}
end
-- Long physical carriers (beams/waves) cannot be approximated by a capped
-- sphere at their center. Cover their full major axis with overlapping spheres.
function S:ProjectileZones(part,sample)
    local size=part.Size
    local length,axis,other1,other2=size.X,part.CFrame.RightVector,size.Y,size.Z
    if size.Y>length then length,axis,other1,other2=size.Y,part.CFrame.UpVector,size.X,size.Z end
    if size.Z>length then length,axis,other1,other2=size.Z,part.CFrame.LookVector,size.X,size.Y end
    local radius=math.max(1,math.sqrt(other1*other1+other2*other2)*.5)+2.5
    local count=length>12 and length>math.max(other1,other2)*3
        and math.clamp(math.ceil(length/math.max(radius,3))+1,2,17) or 1
    if count==1 then radius=math.max(1,size.Magnitude*.5)+2.5
    else radius=math.max(radius,length/(count-1)*.5+2.5)end
    local zones={}
    for i=1,count do
        sample.ZoneKeys[i]=sample.ZoneKeys[i] or {}
        zones[i]={Key=sample.ZoneKeys[i],Position=part.Position+axis*(count==1 and 0 or -length*.5+length*(i-1)/(count-1)),
            Velocity=sample.Velocity or part.AssemblyLinearVelocity,Radius=radius,EndRadius=radius,Source="Projectile",
            Static=part.Anchored and (sample.Velocity or ZERO).Magnitude<1}
    end
    return zones
end
-- These decoders match inspected EFFECTS.make(caster,payload) schemas. Their
-- envelopes are conservative visual approximations, NOT server damage bounds.
function S:DecodePower(name,payload,localY,casterPosition)
    local zones={}
    local lifetime=.9
    local function sphere(position,radius)
        if position.X~=position.X or position.Y~=position.Y or position.Z~=position.Z
            or position.Magnitude>1e7 then return end
        zones[#zones+1]={Key={},Position=position,Velocity=ZERO,Radius=radius,EndRadius=radius,
            Static=true,Source="Power: "..name}
    end
    local function point(v)
        if typeof(v)=="CFrame"then return v.Position end
        if typeof(v)=="Vector3"then return v end
        if typeof(v)=="Instance"then
            if v:IsA("BasePart")then return v.Position end
            if v:IsA("Attachment")then return v.WorldPosition end
        end
    end
    local senko=name=="namikazeteleport" or name=="namikazegodteleport"
        or name=="namikazeteleportazure" or name=="namikazeteleportrose" or name=="namikazeteleportruby"
    if senko and type(payload)=="table" and typeof(payload[1])=="CFrame"then
        -- The ring's reported location can be departure or arrival. Cover
        -- that point and the caster, without inventing a teleport trajectory.
        sphere(payload[1].Position,14)
        if casterPosition and (casterPosition-payload[1].Position).Magnitude>4 then sphere(casterPosition,14)end
        lifetime=.55
    elseif name=="namikazeflash" and type(payload)=="table" then
        local first,second=point(payload[1]),point(payload[2])
        if first and second then sphere(first,14);sphere(second,14)end
        lifetime=.6
    elseif name=="grandfireball" and typeof(payload)=="CFrame" then
        for i=0,6 do sphere(payload.Position+payload.LookVector*(i*30),30)end
        lifetime=1.1
    elseif name=="earth5aoe" and typeof(payload)=="CFrame" then
        sphere(payload.Position,32)
    elseif (name=="allmightypush" or name=="allmightypush2") and type(payload)=="table"
        and typeof(payload[1])=="CFrame" and type(payload[2])=="number"
        and payload[2]==payload[2] then
        local radius=name=="allmightypush" and 35*math.clamp(payload[2],.25,4)
            or 28+math.clamp(payload[2],0,80)*.5
        sphere(payload[1].Position,radius)
        lifetime=name=="allmightypush" and 1.2 or .8
    elseif name=="waterpillardragon" and typeof(payload)=="Vector3" then
        local y=math.clamp(localY or payload.Y,payload.Y-15,payload.Y+150)
        sphere(Vector3.new(payload.X,y,payload.Z),12)
        lifetime=1.2
    end
    return zones,lifetime
end
function S:ObservePower(caster,payload,name)
    if not self.Enabled or type(name)~="string" or typeof(caster)~="Instance"
        or not caster:IsA("Model") or caster==LP.Character then return false end
    local owner=ownerOf(caster,nil)
    if owner==LP or owner==LP.Character then return false end
    if name=="widedash" then
        -- Inspected module is a movement afterimage, not a damage volume.
        local watcher=self.Watchers[caster]
        if watcher then self:ObserveEnemyDash(watcher)end
        return false
    end
    local _,_,root=localParts();if not root then return false end
    local casterRoot=caster:FindFirstChild("HumanoidRootPart")
    local zones,lifetime=self:DecodePower(name,payload,root.Position.Y,casterRoot and casterRoot.Position)
    if #zones==0 then return false end
    local relevant=false
    for _,zone in ipairs(zones)do
        if (zone.Position-root.Position).Magnitude<=180+zone.Radius then relevant=true end
    end
    if not relevant then return false end
    local count=0;for _ in pairs(self.Powers)do count+=1 end
    if count>=16 then self.PowerOverflowUntil=os.clock()+1;return false end
    local key={}
    for _,zone in ipairs(zones)do zone.CasterRoot=casterRoot end
    self.Powers[key]={Until=os.clock()+lifetime,Zones=zones}
    self.PowerEvents=(self.PowerEvents or 0)+1
    log("power",{Name=name,Caster=caster.Name,Zones=#zones,Evidence="Client effect envelope"})
    self.NextTick=0
    return true
end
function S:GetPowerZones(now)
    local zones={}
    for key,record in pairs(self.Powers)do
        if now>record.Until then self.Powers[key]=nil
        else for _,zone in ipairs(record.Zones)do zones[#zones+1]=zone end end
    end
    return zones
end
local function addThreat(w,kind)
    if not S.Enabled or w.Character==LP.Character then return end
    local _,_,root=localParts();local r=w.Root
    if not root or not r or not r.Parent then return end
    local distance=(root.Position-r.Position).Magnitude
    -- Retain distant melee windups: the dash can replicate after the punch.
    -- Admission does not trigger a dodge; Gather still requires collision.
    if distance>96 then return end
    -- A cast signals possible danger, not a verified target or server hitbox.
    -- Only nearby forward-facing casts are considered without a projectile.
    if kind~="Jutsu" and distance>5 and flat(r.CFrame.LookVector):Dot(flat(root.Position-r.Position))<0.25 then return end
    S.Threats[w.Character]={Root=r,Kind=kind,Until=os.clock()+(kind=="Jutsu" and .65 or .55),
        Range=kind=="Jutsu" and 24 or 12,Created=os.clock()}
    S.Detected+=1;log("attack",{Name=w.Character.Name,Source=kind,Distance=distance})
    S.NextTick=0
end
local DASH_ANIMATIONS={
    ["4830732942"]="right",["4830735289"]="left",
    ["9102219647"]="back",["9102202719"]="front",
    ["13188341428"]="right",["13188333575"]="left",
    ["13188336212"]="back",["13188338883"]="front",
}
function S:ObserveEnemyDash(w,direction)
    local now=os.clock();w.DashUntil=now+.55
    if direction then
        local cf=w.Root.CFrame
        local v=direction=="right" and cf.RightVector or direction=="left" and -cf.RightVector
            or direction=="back" and -cf.LookVector or cf.LookVector
        w.DashVelocity=flat(v)*60;w.DashBridgeUntil=now+.12
    end
    local threat=self.Threats[w.Character]
    log("enemy_dash",{Name=w.Character.Name,Direction=direction or "Replicated slide",AttackPending=threat~=nil})
    self.NextTick=0
end
function S:EnemyVelocity(w,now)
    local position=w.Root.Position
    local velocity=w.Root.AssemblyLinearVelocity
    local dt=w.MotionAt and now-w.MotionAt or 0
    if dt>=.008 and dt<=.25 and w.MotionPosition then
        local displacement=position-w.MotionPosition
        local measured=displacement/dt
        if displacement.Magnitude<=45 and measured.Magnitude<=240
            and measured.Magnitude>math.max(24,velocity.Magnitude*1.5)then velocity=measured end
    end
    w.MotionAt=now;w.MotionPosition=position
    if velocity.Magnitude<12 and now<(w.DashBridgeUntil or 0) and w.DashVelocity then
        velocity=w.DashVelocity
    end
    return velocity
end
function S:AttackContact(relative,velocity,forward,range,dashActive)
    local gap,eta=self:ClosestApproach(relative,velocity,dashActive and .35 or .25,range+2)
    local closing=relative.Magnitude>.01 and -relative.Unit:Dot(velocity) or 0
    local dashIncoming=dashActive and closing>=24
    return gap<=0 and (relative.Magnitude<5 or forward>.15),eta,dashIncoming
end
function S:Watch(character)
    if character==LP.Character or self.Watchers[character]then return end
    local h=character:FindFirstChildOfClass("Humanoid")
    local r=character:FindFirstChild("HumanoidRootPart")
    local combat=character:FindFirstChild("combat")
    if not h or not r or not combat then return end
    local w={Character=character,Root=r,Humanoid=h,Combat=combat,Connections={}}
    self.Watchers[character]=w
    for _,spec in ipairs({{"combat","Melee"},{"heavyhit","Melee"},{"jutsuactiv","Jutsu"}})do
        local v=combat:FindFirstChild(spec[1])
        if v and v:IsA("ValueBase")then
            w.Connections[#w.Connections+1]=v.Changed:Connect(function(new)
                if new==true or type(new)=="number" and new>0 then addThreat(w,spec[2])end
                if spec[2]=="Jutsu" and new==false then
                    local threat=self.Threats[character]
                    if threat and threat.Kind=="Jutsu"then threat.Until=math.max(threat.Until,os.clock()+.55)end
                end
            end)
        end
    end
    for _,name in ipairs({"slide","slide2"})do
        local v=combat:FindFirstChild(name)
        if v and v:IsA("BoolValue")then
            w.Connections[#w.Connections+1]=v.Changed:Connect(function(on)
                if on then self:ObserveEnemyDash(w)end
            end)
        end
    end
    local animator=h:FindFirstChildOfClass("Animator")
    if animator then
        w.Connections[#w.Connections+1]=animator.AnimationPlayed:Connect(function(track)
            local animation=track.Animation
            local id=animation and animation.AnimationId:match("%d+")
            local direction=id and DASH_ANIMATIONS[id]
            if direction then self:ObserveEnemyDash(w,direction)end
        end)
    end
end
function S:Scan(now,root)
    self.NextScan=now+.5
    local candidates={}
    for _,p in ipairs(Players:GetPlayers())do if p.Character then candidates[#candidates+1]=p.Character end end
    local npcs=workspace:FindFirstChild("npc")
    if npcs then for i,c in ipairs(npcs:GetChildren())do if i>64 then break end;candidates[#candidates+1]=c end end
    for c,w in pairs(self.Watchers)do
        if not c.Parent or not w.Root.Parent or w.Humanoid.Health<=0
            or (w.Root.Position-root.Position).Magnitude>160 then
            disconnect(w.Connections);self.Watchers[c]=nil;self.Threats[c]=nil
        end
    end
    local count=0;for _ in pairs(self.Watchers)do count+=1 end
    for _,c in ipairs(candidates)do
        local r=c:FindFirstChild("HumanoidRootPart")
        if count>=48 then break end
        if r and not self.Watchers[c] and (r.Position-root.Position).Magnitude<140 then
            self:Watch(c);if self.Watchers[c]then count+=1 end
        end
    end
    local primary=workspace:FindFirstChild("projectileparent")
    local effects=workspace:FindFirstChild("ClientEffects")
    if primary~=self.ProjectileFolder or effects~=self.EffectsFolder then
        disconnect(self.HazardConnections or {})
        self.HazardConnections={};self.HazardRoots={}
        self.ProjectileFolder=primary;self.EffectsFolder=effects
        table.clear(self.Projectiles)
        if primary then self.HazardRoots[#self.HazardRoots+1]=primary end
        if effects then self.HazardRoots[#self.HazardRoots+1]=effects end
        for _,folder in ipairs(self.HazardRoots)do
            self.HazardConnections[#self.HazardConnections+1]=folder.DescendantAdded:Connect(function(x)self:RememberProjectile(x)end)
            local queue=folder:GetChildren();local index=1
            while index<=#queue and index<=512 do
                local x=queue[index];self:RememberProjectile(x)
                for _,child in ipairs(x:GetChildren())do if #queue<512 then queue[#queue+1]=child end end
                index+=1
            end
        end
    end
end
function S:Gather(now,root)
    local dangers={}
    for _,w in pairs(self.Watchers)do
        if w.Root.Parent then w.Velocity=self:EnemyVelocity(w,now)end
    end
    for c,t in pairs(self.Threats)do
        local caster=self.Watchers[c]
        if t.Kind=="Jutsu" and caster and value(caster.Combat,"jutsuactiv",false)
            and now<(t.Created or now)+3 then t.Until=math.max(t.Until,now+.15)end
        if now>t.Until or not t.Root.Parent then self.Threats[c]=nil
        else
            local relative=t.Root.Position-root.Position
            local w=self.Watchers[c]
            local attackerVelocity=w and w.Velocity or t.Root.AssemblyLinearVelocity
            local velocity=attackerVelocity-root.AssemblyLinearVelocity
            local dashActive=(w and now<(w.DashUntil or 0)) or attackerVelocity.Magnitude>=35
            local forward=t.Kind=="Jutsu" and 1 or flat(t.Root.CFrame.LookVector):Dot(flat(-relative))
            local hit,eta,incoming=self:AttackContact(relative,velocity,forward,t.Range,dashActive)
            if hit then
                local source=t.Kind=="Melee" and incoming and "Dash + melee" or t.Kind
                if source=="Dash + melee" and not t.DashLogged then
                    t.DashLogged=true
                    log("dash_attack",{Name=c.Name,Distance=relative.Magnitude,ETA=eta,Speed=attackerVelocity.Magnitude})
                end
                dangers[#dangers+1]={Key=t.Root,Position=t.Root.Position,Velocity=attackerVelocity,
                    Radius=t.Range,Source=source,ETA=eta}
            end
        end
    end
    for part,sample in pairs(self.Projectiles)do
        if not part.Parent or not sample.Folder or not part:IsDescendantOf(sample.Folder)then self.Projectiles[part]=nil
        else
            local position=part.Position;local dt=now-sample.At
            local measured=dt>.008 and (position-sample.Position)/dt or sample.Velocity or ZERO
            local velocity=part.AssemblyLinearVelocity
            if part.Anchored or velocity.Magnitude<2 then velocity=measured end
            sample.Position=position;sample.At=now;sample.Velocity=velocity
            if not ownProjectile(part,sample.Folder)then
                sample.Zones=self:ProjectileZones(part,sample)
                for _,zone in ipairs(sample.Zones)do
                    local relative=zone.Position-root.Position
                    local relativeVelocity=velocity-root.AssemblyLinearVelocity
                    local gap,eta=self:ClosestApproach(relative,relativeVelocity,.3,zone.Radius)
                    if gap<=0 and (relative.Magnitude<=zone.Radius or relative:Dot(relativeVelocity)<-1)then
                        local copy=table.clone(zone);copy.ETA=eta;dangers[#dangers+1]=copy
                    end
                end
            end
        end
    end
    for _,zone in ipairs(self:GetPowerZones(now))do
        local relative=zone.Position-root.Position
        local gap,eta=self:ClosestApproach(relative,-root.AssemblyLinearVelocity,.3,zone.Radius+2)
        if gap<=0 then local copy=table.clone(zone);copy.ETA=eta;dangers[#dangers+1]=copy end
    end
    table.sort(dangers,function(a,b)return a.ETA<b.ETA end)
    return dangers
end
function S:BuildRoutePool(root,dangers,now)
    if now<(self.PowerOverflowUntil or 0)then return nil end
    local pool,seen={},{}
    local function add(t)
        if t.Key and seen[t.Key]then return end
        -- Analytic upper bound for any intersection with the 60-stud route.
        if (t.Position-root.Position).Magnitude>60+math.max(t.Radius,t.EndRadius or 0)
            +t.Velocity.Magnitude*.7+5 then return end
        if t.Key then seen[t.Key]=true end
        pool[#pool+1]=t
    end
    for _,t in ipairs(dangers)do
        local copy=table.clone(t)
        copy.EndRadius=(t.Source=="Projectile" or t.Static) and t.Radius or math.max(14,t.Radius)
        add(copy)
    end
    -- Include active attacks that miss the CURRENT position but could hit a
    -- proposed route. Previously only current-position collisions were scored.
    for c,t in pairs(self.Threats)do
        if t.Until>now and t.Root.Parent then
            local w=self.Watchers[c]
            add({Key=t.Root,Position=t.Root.Position,Velocity=w and w.Velocity or t.Root.AssemblyLinearVelocity,
                Radius=t.Range,EndRadius=math.max(14,t.Range),Source=t.Kind})
        end
    end
    -- Even an idle character occupies space. Keep the landing outside a
    -- conservative melee envelope; this does not predict a future attack.
    for c,w in pairs(self.Watchers)do
        if c~=LP.Character and w.Root.Parent and w.Humanoid.Health>0 then
            add({Key=w.Root,Position=w.Root.Position,Velocity=w.Velocity or w.Root.AssemblyLinearVelocity,
                Radius=4,EndRadius=14,Source="Character"})
        end
    end
    for part,sample in pairs(self.Projectiles)do
        if part.Parent and not ownProjectile(part,sample.Folder)then
            for _,zone in ipairs(sample.Zones or self:ProjectileZones(part,sample))do add(zone)end
        end
    end
    for _,zone in ipairs(self:GetPowerZones(now))do add(zone)end
    if #pool>256 then return nil end -- never silently skip the excess threats
    return pool
end
function S:RouteClearance(origin,direction,pool)
    local minimum=math.huge
    local escape=math.huge
    local powerOverlap=false
    local knots={0,.1,.22,.35,.5,.7}
    -- Cover both the observed slower dash and the previous fast travel model.
    for _,speed in ipairs({60,150})do
        for _,t in ipairs(pool)do
            local initialGap=(origin-t.Position).Magnitude-t.Radius
            local overlap=initialGap<0
            local partial=overlap and t.Static==true
            powerOverlap=powerOverlap or partial
            local hypotheses=(t.Source=="Projectile" or t.Static) and 1 or 2
            for hypothesis=1,hypotheses do
                local function enemy(time)
                    return t.Position+t.Velocity*(hypothesis==2 and math.min(time,.12) or time)
                end
                for i=1,#knots-1 do
                    local a,b=knots[i],knots[i+1]
                    local pa=origin+direction*math.min(50,speed*math.min(a,.35))
                    local pb=origin+direction*math.min(50,speed*math.min(b,.35))
                    local relative=pa-enemy(a)
                    local relativeVelocity=((pb-pa)-(enemy(b)-enemy(a)))/(b-a)
                    local padding=(t.Source=="Projectile" or t.Static) and 0 or math.min(4,15*b*b)
                    local gap=self:ClosestApproach(relative,relativeVelocity,b-a,t.Radius+padding)
                    -- Existing overlap cannot be undone at t=0. Allow that
                    -- initial source an escape phase, but reject NEW crossings.
                    if not overlap or a>=.35 then
                        minimum=math.min(minimum,gap)
                        escape=math.min(escape,partial and gap-initialGap-3 or gap)
                    end
                end
                local endpoint=origin+direction*math.min(50,speed*.35)
                local endGap=(endpoint-enemy(.7)).Magnitude-(t.EndRadius or t.Radius)-2
                minimum=math.min(minimum,endGap)
                escape=math.min(escape,partial and endGap-initialGap-3 or endGap)
            end
        end
    end
    return minimum,powerOverlap and escape or nil
end
function S:Plan(root,humanoid,dangers,character)
    local pool=self:BuildRoutePool(root,dangers,os.clock())
    self.RouteThreatCount=pool and #pool or 0;self.RouteChecked=0
    if not pool then self.RouteReason="Too many route threats";return nil end
    local away=flat(root.Position-dangers[1].Position)
    local side=Vector3.new(-away.Z,0,away.X)
    local dirs={away,side,-side,flat(away+side),flat(away-side),-away,
        flat(-away+side),flat(-away-side),flat(humanoid.MoveDirection)}
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    local exclude={character}
    if self.ProjectileFolder then exclude[#exclude+1]=self.ProjectileFolder end
    for c in pairs(self.Watchers)do exclude[#exclude+1]=c end
    params.FilterDescendantsInstances=exclude;params.RespectCanCollide=true
    local best,bestScore,escapeDirection,escapeScore,escapeClearance
    local deadline=os.clock()+.008
    for _,dir in ipairs(dirs)do
        if self.RouteChecked>0 and os.clock()>deadline then break end
        local right=Vector3.new(-dir.Z,0,dir.X)
        local clear=true
        -- Sweep width as well as the center ray; keep the body off walls.
        for _,offset in ipairs({ZERO,right*2,-right*2})do
            if workspace:Raycast(root.Position+offset,dir*60,params)then clear=false;break end
        end
        for _,step in ipairs({10,20,30,40,50,60})do
            local ground=workspace:Raycast(root.Position+dir*step+Vector3.new(0,3,0),Vector3.new(0,-13,0),params)
            if not ground or ground.Normal.Y<.45 then clear=false;break end
        end
        if clear then
            local score,progress=self:RouteClearance(root.Position,dir,pool)
            self.RouteChecked+=1
            if score>0 and (not bestScore or score>bestScore)then best,bestScore=dir,score end
            if progress and progress>0 and (not escapeScore or progress>escapeScore)then
                escapeDirection,escapeScore,escapeClearance=dir,progress,score
            end
        end
    end
    self.RouteReason=best and "Complete route checked" or "No clear route through nearby threats"
    if not best and escapeDirection then
        best,bestScore=escapeDirection,escapeClearance
        self.RouteReason="Partial escape from existing power overlap"
    end
    self.LastRouteClearance=bestScore
    return best,bestScore
end
function S:Request(direction,source)
    local c,h,r,combat=localParts();local now=os.clock()
    if not self.Enabled or self.Destroyed or not h or h.Health<=0 or not r or not combat then return false end
    if now<self.NextRequest then self.Status="Dash request cooldown";return false end
    for _,name in ipairs({"ragdoll","disable","disablekeys","bind","grip","plrgrip","slide","slide2"})do
        if value(combat,name,false)==true then self.Status="Blocked: "..name;return false end
    end
    if c:FindFirstChild("beserk") or c:FindFirstChild("itachi") or c:FindFirstChild("cantjump")then
        self.Status="Native movement restricted";return false
    end
    if value(combat,"wallwalk",false)then self.Status="Wall walking: route unverified";return false end
    if self.NativeCharacter~=c then self.NativeCharacter=c;self.NativeCallback=nil end
    if not self.NativeCallback then
        local slide=combat:FindFirstChild("slide")
        if slide then
            for i,connection in ipairs(getconnections(slide.Changed))do
                if i>24 then break end
                local fn=connection.Function
                if type(fn)=="function" then
                    local ok,source=pcall(debug.info,fn,"s")
                    if ok and type(source)=="string" and source:match("ReplicatedStorage%.Char$")then
                        self.NativeCallback=fn;break
                    end
                end
            end
        end
    end
    if not self.NativeCallback then self.Status="Waiting for native movement callback";return false end
    if self.NativeBusy then self.Status="Native dash active";return false end
    self:ReleasePowerGuard("Dodge takes priority")
    self.NextRequest=now+1;self.Requests+=1;self.Status="Dash requested: "..source
    self.PendingAck={Root=r,Combat=combat,Started=now,Position=r.Position,Direction=direction,Source=source}
    local callback=self.NativeCallback
    local generation=self.Generation
    self.NativeBusy=true
    task.spawn(function()
        if not self.Enabled or self.Generation~=generation then self.NativeBusy=false;return end
        local prior=identityGet()
        local previousMover=r:FindFirstChild("dashvelocity")
        local ok,err=pcall(function()
            h:Move(direction,false)
            identitySet(2)
            callback(true)
        end)
        pcall(identitySet,prior)
        self.NativeBusy=false
        if not ok then
            self.NativeCallback=nil
            local mover=r.Parent and r:FindFirstChild("dashvelocity")
            if mover and mover~=previousMover then mover:Destroy()end
            self.Status="Native movement failed"
            log("native_error",{Message=tostring(err)})
            self.Errors+=1
            warn("[Shindo Auto Dodge] "..tostring(err))
            if self.Errors>=3 then self:SetEnabled(false)end
        end
    end)
    log("request",{Source=source,Direction=tostring(direction)})
    return true
end
function S:IsGuardCandidate(threat)
    return type(threat.Source)=="string" and (threat.Source:match("^Power: ")~=nil
        or threat.Source=="Jutsu" or threat.Source=="Projectile")
end
function S:ReleasePowerGuard(reason)
    local guard=self.PowerGuard
    if not guard then return end
    self.PowerGuard=nil
    if guard.Humanoid and guard.Humanoid.Parent and guard.Humanoid.AutoRotate==false then
        guard.Humanoid.AutoRotate=guard.AutoRotate
    end
    -- A real input begun during our hold transfers ownership to the player.
    if not guard.ManualTakeover and not self.ManualGuardHeld and guard.Remote.Parent then
        pcall(guard.Remote.FireServer,guard.Remote,"mouse2",false)
        self.GuardReleasePendingUntil=os.clock()+.25
    end
    log("guard_release",{Reason=reason})
end
function S:UpdatePowerGuard(dangers,now,character,humanoid,root,combat)
    local senko
    for _,threat in ipairs(dangers)do if self:IsGuardCandidate(threat)then senko=threat;break end end
    local guard=self.PowerGuard
    if guard and (guard.Character~=character or guard.ManualTakeover)then
        self:ReleasePowerGuard(guard.ManualTakeover and "Manual takeover" or "Character changed")
        guard=nil
    end
    local restricted=value(combat,"ragdoll",false) or value(combat,"disable",false)
        or value(combat,"disablekeys",false) or value(combat,"bind",false)
        or value(combat,"grip",false) or value(combat,"plrgrip",false) or value(combat,"wallwalk",false)
    if guard and (restricted or now>=guard.Started+.85)then
        self:ReleasePowerGuard(restricted and "Native movement restriction" or "Hold limit")
        self.NextPowerGuard=now+.5
        return false
    end
    if not senko then
        if guard and now>=guard.HoldUntil then self:ReleasePowerGuard("Power threat cleared")end
        return false
    end
    if restricted then return false end
    -- Preserve ordinary blocking without claiming it or changing facing.
    if not guard and value(combat,"deflect",false) and now>=(self.GuardReleasePendingUntil or 0)then
        self.Status="Manual block active: power"
        return true
    end
    if self.ManualGuardHeld then return false end
    if not guard then
        if now<(self.NextPowerGuard or 0) or self.NativeBusy then return false end
        local remote=combat and combat:FindFirstChild("update")
        if not remote or not remote:IsA("RemoteEvent")then return false end
        guard={Character=character,Humanoid=humanoid,AutoRotate=humanoid.AutoRotate,
            Remote=remote,Started=now,HoldUntil=now+.22,AckWait=.18}
        local ok,ping=pcall(LP.GetNetworkPing,LP)
        if ok and type(ping)=="number" then guard.AckWait=math.clamp(ping*2+.06,.12,.35)end
        self.PowerGuard=guard
        self.GuardRequests=(self.GuardRequests or 0)+1
        humanoid.AutoRotate=false
        remote:FireServer("mouse2",true)
        log("guard_request",{Source=senko.Source})
    end
    guard.HoldUntil=math.min(guard.Started+.85,math.max(guard.HoldUntil,now+.12))
    local caster=senko.CasterRoot
    local target=caster and caster.Parent and caster.Position or senko.Position
    local horizontal=Vector3.new(target.X-root.Position.X,0,target.Z-root.Position.Z)
    if horizontal.Magnitude>.25 then root.CFrame=CFrame.lookAt(root.Position,root.Position+horizontal)end
    local acknowledged=value(combat,"deflect",false)
    if acknowledged and not guard.Acknowledged then
        guard.Acknowledged=true
        self.GuardAcknowledged=(self.GuardAcknowledged or 0)+1
        log("guard_ack",{Source=senko.Source,DelayMs=(now-guard.Started)*1000})
    elseif not acknowledged and (guard.Acknowledged or now-guard.Started>guard.AckWait)then
        self:ReleasePowerGuard(guard.Acknowledged and "Guard broken or released" or "Guard not acknowledged")
        self.NextPowerGuard=now+.6
        self.Status="Power guard unavailable: trying dodge"
        return false
    end
    self.Status=acknowledged and "Blocking power" or "Requesting power block"
    return true
end
function S:ObserveGuardDamage(now)
    if not self.PowerGuard then return false end
    log("guard_damage",{Acknowledged=self.PowerGuard.Acknowledged==true})
    self:ReleasePowerGuard("Damage passed through guard")
    self.NextPowerGuard=now+.7
    return true
end
function S:Tick()
    local now=os.clock();if now<self.NextTick then return end;self.NextTick=now+1/30
    local c,h,r,combat=localParts()
    if not c or not h or not r or h.Health<=0 then
        self:ReleasePowerGuard("Character unavailable")
        self.Status="Waiting for character";return
    end
    local health=value(c,"fakehealth",h.Health)
    if self.LastCharacter~=c then
        self.LastCharacter=c;self.LastHealth=health;self.NextScan=0;self.PendingAck=nil
    elseif health<self.LastHealth then
        self.LastHit=self.Status;log("health_loss",{Amount=self.LastHealth-health,Decision=self.Status})
        self:ObserveGuardDamage(now)
    end
    self.LastHealth=health
    if now>=self.NextScan then self:Scan(now,r)end
    local ack=self.PendingAck
    if ack then
        if ack.Root~=r then self.PendingAck=nil
        else
            local distance=(r.Position-ack.Position):Dot(ack.Direction)
            local mover=r:FindFirstChild("dashvelocity")
            ack.MoverSeen=ack.MoverSeen or mover~=nil
            local v=r.AssemblyLinearVelocity
            ack.PeakSpeed=math.max(ack.PeakSpeed or 0,Vector3.new(v.X,0,v.Z).Magnitude)
            if ack.MoverSeen and distance>3 and (ack.PeakSpeed>35 or distance>10) then
                self.Acknowledged+=1;log("native_ack",{Distance=distance,PeakSpeed=ack.PeakSpeed,
                    NativeMover=true,Source=ack.Source})
                self.PendingAck=nil
            elseif now-ack.Started>.45 then
                log("unacknowledged",{Source=ack.Source});self.PendingAck=nil;self.Status="Native dash not acknowledged"
            end
        end
    end
    local dangers=self:Gather(now,r)
    self.ActiveThreats=#dangers
    if self:UpdatePowerGuard(dangers,now,c,h,r,combat)then return end
    if #dangers==0 then if now>=self.NextRequest then self.Status="Watching attacks"end;return end
    local direction=self:Plan(r,h,dangers,c)
    if not direction then self.Status=self.RouteReason or "No verified ground route";return end
    self:Request(direction,dangers[1].Source)
end
function S:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Requests=self.Requests,Acknowledged=self.Acknowledged,
        Errors=self.Errors,Threats=self.ActiveThreats or 0,RouteThreats=self.RouteThreatCount or 0,
        RoutesChecked=self.RouteChecked or 0,RouteClearance=self.LastRouteClearance,
        RouteReason=self.RouteReason,PowerEvents=self.PowerEvents or 0,
        GuardRequests=self.GuardRequests or 0,GuardAcknowledged=self.GuardAcknowledged or 0}
end
function S:SetEnabled(on)
    if self.Destroyed then return end
    on=on==true;if self.Enabled==on then return end
    self.Enabled=on;self.Generation+=1
    if not on then
        self:ReleasePowerGuard("Feature OFF")
        disconnect(self.Connections)
        for _,w in pairs(self.Watchers)do disconnect(w.Connections)end
        disconnect(self.HazardConnections or {});self.HazardConnections={};self.HazardRoots={};self.EffectsFolder=nil
        if self.ReleaseRemote and self.ReleaseRemote.Parent then self.ReleaseRemote:FireServer("key","xend")end
        self.ReleaseRemote=nil;self.ProjectileFolder=nil;self.PendingAck=nil;self.NativeCallback=nil;self.NativeCharacter=nil
        table.clear(self.Watchers);table.clear(self.Projectiles);table.clear(self.Threats);table.clear(self.Powers)
        self.PowerOverflowUntil=nil
        self.GuardReleasePendingUntil=0
        self.ManualGuardHeld=false
        self.ManualGuardInputs={}
        self.Status="Off";return
    end
    self.Status="Watching attacks";self.NextScan=0;self.NextTick=0
    local function guardInput(input)
        return input.UserInputType==Enum.UserInputType.MouseButton2 or input.KeyCode==Enum.KeyCode.ButtonL2
    end
    self.ManualGuardHeld=UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    self.ManualGuardInputs={}
    local function manualStart(input)
        self.ManualGuardInputs[input]=true
        self.ManualGuardHeld=true
        if self.PowerGuard then self.PowerGuard.ManualTakeover=true end
    end
    local function manualEnd(input)
        self.ManualGuardInputs[input]=nil
        self.ManualGuardHeld=next(self.ManualGuardInputs)~=nil
            or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    end
    self.Connections[#self.Connections+1]=UIS.InputBegan:Connect(function(input)
        if guardInput(input)then manualStart(input)end
    end)
    self.Connections[#self.Connections+1]=UIS.InputEnded:Connect(function(input)
        if guardInput(input) or self.ManualGuardInputs[input]then manualEnd(input)end
    end)
    local main=LP.PlayerGui:FindFirstChild("Main")
    local ingame=main and main:FindFirstChild("ingame")
    local keys=ingame and ingame:FindFirstChild("mobilekeys")
    local block=keys and keys:FindFirstChild("BLOCK")
    if block and block:IsA("GuiButton")then
        self.Connections[#self.Connections+1]=block.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.Touch then manualStart(input)end
        end)
        self.Connections[#self.Connections+1]=block.InputEnded:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.Touch then manualEnd(input)end
        end)
    end
    self.Connections[#self.Connections+1]=UIS.WindowFocusReleased:Connect(function()
        self.ManualGuardHeld=false
        table.clear(self.ManualGuardInputs)
        self:ReleasePowerGuard("Window focus lost")
    end)
    self.Connections[#self.Connections+1]=Run.Heartbeat:Connect(function()
        local ok,err=pcall(self.Tick,self)
        if not ok then
            self.Errors+=1;warn("[Shindo Auto Dodge] "..tostring(err))
            if self.Errors>=3 then self:SetEnabled(false);self.Status="Stopped after errors"end
        end
    end)
    local fire=game:GetService("ReplicatedStorage"):FindFirstChild("fire")
    if fire and fire:IsA("RemoteEvent")then
        self.Connections[#self.Connections+1]=fire.OnClientEvent:Connect(function(caster,payload,name)
            local ok,err=pcall(self.ObservePower,self,caster,payload,name)
            if not ok then log("power_decode_error",{Message=tostring(err)})end
        end)
    end
end
function S:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if env.__SHINDO_AUTO_DODGE==self then env.__SHINDO_AUTO_DODGE=nil end
end
return S

]====],
Camera=[====[
-- Soft Camera Lock (Shift Lock compensated)
-- Press C to lock / unlock

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LP:GetMouse()

local LockedPlayer = nil
local Highlight = nil
local FollowConnection = nil

local LOCK_STRENGTH = 0.78
local MAX_LOCK_DISTANCE = 90
local MAX_LOCK_ANGLE = 40

-- How much to pull the aim point to correct Shift Lock offset
-- Higher value = moves crosshair more toward center of torso
local SHIFTLOCK_COMPENSATION = 0.55

local function clearLock()
	if Highlight then
		Highlight:Destroy()
		Highlight = nil
	end
	if FollowConnection then
		FollowConnection:Disconnect()
		FollowConnection = nil
	end
	LockedPlayer = nil
	print("Camera unlocked")
end

local function createHighlight(character)
	if Highlight then Highlight:Destroy() end
	local hl = Instance.new("Highlight")
	hl.Name = "TargetLock"
	hl.FillColor = Color3.fromRGB(255, 0, 0)
	hl.OutlineColor = Color3.fromRGB(255, 40, 40)
	hl.FillTransparency = 0.6
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = character
	return hl
end

local function getAimPosition(character)
	local upperTorso = character:FindFirstChild("UpperTorso")
	local root = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso") -- R6

	local basePos
	if upperTorso then
		basePos = upperTorso.Position
	elseif torso then
		basePos = torso.Position
	elseif root then
		basePos = root.Position + Vector3.new(0, 1.15, 0)
	else
		local head = character:FindFirstChild("Head")
		if head then
			basePos = head.Position - Vector3.new(0, 0.7, 0)
		else
			return nil
		end
	end

	-- Compensate for Shift Lock camera being on the right side
	-- This pulls the aim point so the crosshair lands closer to the middle of the torso
	local compensated = basePos - Camera.CFrame.RightVector * SHIFTLOCK_COMPENSATION
	return compensated
end

local function getClosestPlayer()
	-- Exact raycast first
	local unitRay = Camera:ScreenPointToRay(Mouse.X, Mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {LP.Character, Camera}

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1200, params)
	if result then
		local character = result.Instance:FindFirstAncestorOfClass("Model")
		if character then
			local player = Players:GetPlayerFromCharacter(character)
			if player and player ~= LP and player.Character and getAimPosition(player.Character) then
				return player
			end
		end
	end

	-- Nearby fallback
	local closestPlayer = nil
	local closestScore = math.huge
	local camPos = Camera.CFrame.Position
	local camLook = Camera.CFrame.LookVector

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LP and player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			local aimPos = getAimPosition(player.Character)

			if humanoid and humanoid.Health > 0 and aimPos then
				local distance = (aimPos - camPos).Magnitude
				if distance <= MAX_LOCK_DISTANCE then
					local direction = (aimPos - camPos).Unit
					local angle = math.deg(math.acos(math.clamp(camLook:Dot(direction), -1, 1)))

					if angle <= MAX_LOCK_ANGLE then
						local score = distance + (angle * 1.6)
						if score < closestScore then
							closestScore = score
							closestPlayer = player
						end
					end
				end
			end
		end
	end

	return closestPlayer
end

local function startLock(player)
	if not player or not player.Character then return end
	if not getAimPosition(player.Character) then return end

	LockedPlayer = player
	Highlight = createHighlight(player.Character)

	FollowConnection = RunService.RenderStepped:Connect(function()
		if not LockedPlayer or not LockedPlayer.Character then
			clearLock()
			return
		end

		local targetPos = getAimPosition(LockedPlayer.Character)
		if not targetPos then return end

		if not Highlight or Highlight.Parent ~= LockedPlayer.Character then
			if Highlight then Highlight:Destroy() end
			Highlight = createHighlight(LockedPlayer.Character)
		end

		local camPos = Camera.CFrame.Position
		local desired = CFrame.lookAt(camPos, targetPos)
		Camera.CFrame = Camera.CFrame:Lerp(desired, LOCK_STRENGTH)
	end)

	print("Locked onto:", player.Name)
end

local removingConnection=Players.PlayerRemoving:Connect(function(player)
	if player == LockedPlayer then
		clearLock()
	end
end)

local Controller={HubOnly=true,Destroyed=false}
function Controller:SetEnabled(value)
    if self.Destroyed then return end
    if value then
        assert(UIS.KeyboardEnabled,"This aimlock is PC only")
        if not LockedPlayer then
            local target=getClosestPlayer()
            if target then startLock(target) end
        end
    else clearLock() end
end
function Controller:GetSnapshot()
    return {Enabled=LockedPlayer~=nil,Status=LockedPlayer and ("Locked: "..LockedPlayer.DisplayName) or "Off"}
end
function Controller:Destroy()
    if self.Destroyed then return end
    self.Destroyed=true
    clearLock()
    removingConnection:Disconnect()
    if getgenv().__INK_SOFT_CAMERA_MOBILE==self then getgenv().__INK_SOFT_CAMERA_MOBILE=nil end
end
getgenv().__INK_SOFT_CAMERA_MOBILE=Controller
return Controller
]====],
Dodge=[====[
error("General Auto Dodge disabled during timeout/crash investigation")
]====],
Rosu=[====[
-- Allen Scripts / rosu!mania autoplay. Blank button or F6; starts OFF.
if game.GameId~=3405992067 then warn("[Rosu Autoplay] Open rosu!mania first");return end
if type(getsenv)~="function" or not debug or type(debug.getupvalues)~="function" then
    warn("[Rosu Autoplay] Script-environment inspection is required");return
end
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local LP=Players.LocalPlayer
local env=getgenv()
if env.__ROSU_AUTOPLAY then env.__ROSU_AUTOPLAY:Destroy() end
local state={Enabled=false,Destroyed=false,Connections={},Held={},Processed=setmetatable({},{__mode="k"}),
    Presses=0,Releases=0,Errors=0,Status="Off",NextBind=0}
local function dueHit(note,gameState,rate)
    local ok,result,delta=note:test_hit(gameState)
    if not ok or result==0 or type(delta)~="number" or delta~=delta then return false end
    local late=note.Type=="Note" and -delta or delta
    return late>=0 and late<=70*rate
end
local function dueRelease(note,gameState,rate)
    local ok,_,delta=note:test_release(gameState)
    if not ok or type(delta)~="number" or delta~=delta then return false end
    return delta>=0
end
local function stepNotes(state,gameState,tracks,clock)
    local rate=gameState._audio_manager:get_song_rate()
    if type(rate)~="number" or rate<=0 or rate~=rate then return end
    for lane,held in pairs(state.Held) do
        local release=held.Note and (dueRelease(held.Note,gameState,rate)
            or not table.find(tracks._active_notes or {},held.Note))
            or not held.Note and clock>=held.ReleaseClock
        if release then
            tracks:release_track_index(gameState,lane)
            state.Held[lane]=nil;state.Releases+=1
        end
    end
    local candidates={}
    local notes=tracks._active_notes or {}
    local count=math.min(#notes,2048)
    for i=1,count do
        local note=notes[i]
        if not state.Processed[note] and (note.Type=="Note" or note.Type=="HeldNote") then
            local lane=note:get_track_index()
            if type(lane)=="number" and lane>=1 and lane<=4 and not candidates[lane]
                and (not state.Held[lane] or not state.Held[lane].Note)
                and dueHit(note,gameState,rate) then candidates[lane]=note end
        end
    end
    for lane=1,4 do
        local note=candidates[lane]
        if note then
            if state.Held[lane] then tracks:release_track_index(gameState,lane);state.Held[lane]=nil;state.Releases+=1 end
            tracks:press_track_index(gameState,lane)
            state.Processed[note]=true;state.Presses+=1
            state.Held[lane]=note.Type=="HeldNote" and {Note=note} or {ReleaseClock=clock+.025}
        end
    end
end

function state:FindContext()
    if not self.Main or not self.Main.Parent then
        self.Main=nil
        for _,object in ipairs(LP:WaitForChild("PlayerGui"):GetDescendants()) do
            if object:IsA("LocalScript") and object.Name=="MAIN SYSTEM" then self.Main=object;break end
        end
    end
    if not self.Main then return nil end
    local scriptEnv=getsenv(self.Main)
    if type(scriptEnv.StartGame)~="function" then return nil end
    for _,value in pairs(debug.getupvalues(scriptEnv.StartGame)) do
        if type(value)=="table" and rawget(value,"_game_join") then
            local join=value._game_join
            if type(join)=="table" and type(join.get_game)=="function" then return join:get_game() end
        end
    end
end
function state:Release()
    if self.Game and self.Tracks then
        for lane in pairs(self.Held) do pcall(self.Tracks.release_track_index,self.Tracks,self.Game,lane) end
    end
    table.clear(self.Held)
end
function state:Step()
    local clock=os.clock()
    if clock>=self.NextBind then
        self.NextBind=clock+.25
        local context=self:FindContext()
        if context~=self.Game then
            self:Release();self.Game=context;self.Tracks=nil
            self.Processed=setmetatable({},{__mode="k"})
        end
    end
    local gameState=self.Game
    local audio=gameState and gameState._audio_manager
    if not audio or not audio:is_playing() or gameState._is_replay_mode then
        self:Release();self.Status="Waiting for a local chart";return
    end
    local tracks=gameState:get_local_tracksystem()
    if tracks~=self.Tracks then self:Release();self.Tracks=tracks end
    if not tracks or not tracks._active_notes then self.Status="Waiting for lanes";return end
    if UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then self:Release();self.Status="Paused for menu / typing";return end
    stepNotes(self,gameState,tracks,clock)
    self.Status="Playing"
end
local gui={Enabled=false,Destroy=function()end}
local button={Parent=true}
state.Gui=gui
function state:SetEnabled(value)
    RunService:UnbindFromRenderStep("AllenRosuAutoplay")
    self.Enabled=false;self:Release();self.Game=nil;self.Tracks=nil
    self.Enabled=value==true and not self.Destroyed
    self.Processed=setmetatable({},{__mode="k"});self.NextBind=0
    button.BackgroundColor3=self.Enabled and Color3.fromRGB(36,165,91) or Color3.fromRGB(164,55,62)
    self.Status=self.Enabled and "Waiting for a local chart" or "Off"
    if self.Enabled then
        -- The game updates notes at Camera.Value-1; judge after that native update.
        RunService:BindToRenderStep("AllenRosuAutoplay",Enum.RenderPriority.Camera.Value+1,function()
            local ok,message=pcall(self.Step,self)
            if not ok then self.Errors+=1;self.LastError=tostring(message);self:SetEnabled(false);warn("[Rosu Autoplay] "..self.LastError)end
        end)
    end
end
function state:GetSnapshot()
    local out={Enabled=self.Enabled,Status=self.Status,Presses=self.Presses,Releases=self.Releases,
        Errors=self.Errors,LastError=self.LastError}
    local score=self.Game and self.Game._score_manager
    if score then
        out.Score=score:get_score();out.Accuracy=score:get_accuracy()*100
        out.Misses=score:get_miss();out.PerfectX=score:get_perfectx();out.Perfect=score:get_perfect()
    end
    return out
end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    for _,connection in ipairs(self.Connections)do connection:Disconnect()end
    gui:Destroy()
    if env.__ROSU_AUTOPLAY==self then env.__ROSU_AUTOPLAY=nil end
end
state.HubOnly=true
env.__ROSU_AUTOPLAY=state
state:SetEnabled(false)
print("[Rosu Autoplay] Loaded OFF; blank button / F6 toggles.")


return state

]====],
FFBridge=[=====[
local env=getgenv()
local LP=game:GetService("Players").LocalPlayer
local folder=LP:WaitForChild("PlayerGui"):WaitForChild("AllenHubFFStatus",10)
if not folder then return end
if env.__ALLEN_FF_BRIDGE then env.__ALLEN_FF_BRIDGE:Destroy() end
local controller=env.__FF_AUTOPLAY
if controller and not controller.HubOnly then controller:Destroy();controller=nil end
local function initialize()
    if not controller or controller.Destroyed then
        local fn,err=loadstring([====[
-- Funky Friday native autoplay. Blank button / F6. Starts OFF.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local env=getgenv()
local previous=env.__FF_AUTOPLAY
if previous and type(previous.Destroy)=="function" then previous:Destroy() end
local framework=env.__FF_SCAN and env.__FF_SCAN.Framework
if not framework then
    for _,value in ipairs(getgc(true)) do
        if type(value)=="table" and rawget(value,"VSRG") and rawget(value,"SettingsHandler")
            and rawget(value,"Configs") and type(value.VSRG.GameHandler)=="table" then framework=value;break end
    end
end
if not framework then warn("[FF Autoplay] Rhythm framework not found");return end
local handler=framework.VSRG.GameHandler
local ignored={}
for _,kind in ipairs(framework.Configs.VSRG.IgnoredNoteTypes or {}) do ignored[kind]=true end
for _,kind in ipairs(framework.Configs.VSRG.DeathNoteTypes or {}) do ignored[kind]=true end
local state={Version="1.0",Enabled=false,Destroyed=false,Held={},Hits=0,Rejected=0,Errors=0,Status="Off"}
-- Native lane scheduler; no input spoofing, remote hooks, or score edits.
local function songTime(gameState,clock)
    local rate=gameState.AdjustedPlayback or 1
    local sample=gameState.TimePositionSample
    local time=gameState.TimePosition
    if type(sample)=="table" and type(sample.Position)=="number" and type(sample.Clock)=="number" then
        time=sample.Position+math.clamp(clock-sample.Clock,-.25,.25)*rate
    end
    if type(time)~="number" or time~=time or type(rate)~="number" or rate<=0 then return nil end
    return time,rate
end
local function candidateFor(lane,time,rate,ignored)
    local best
    local count=0
    for _,note in pairs(lane.Notes or {}) do
        count+=1
        if count>2048 then break end
        local kind=note.NoteData and note.NoteData.Type or note.Type
        if not note.Hit and not note.Cleaned and note.CanMove~=false
            and type(note.Time)=="number" and not ignored[kind or ""]
            and kind~="Auto Note" then
            local late=(time-note.Time)/rate
            if late>=0 and late<=.08 and (not best or note.Time<best.Time) then best=note end
        end
    end
    return best
end
local function tickLanes(state,field,time,rate,clock,ignored,hit)
    for index,lane in ipairs(field.Lanes or {}) do
        local held=state.Held[lane]
        if held then
            local release=held.EndTime and time>=held.EndTime or not held.EndTime and clock>=held.ReleaseClock
            if release then hit(index,false,clock);state.Held[lane]=nil;held=nil end
        end
        local note=candidateFor(lane,time,rate,ignored)
        if note then
            -- Retrigger a lane for repeated notes; preserve native hold state until that point.
            if held then hit(index,false,clock);state.Held[lane]=nil end
            hit(index,true,clock)
            if lane.LastHitIndex==note.Index then
                state.Hits+=1
                state.Held[lane]={Index=index,EndTime=(note.Length or 0)>0 and note.Time+note.Length or nil,ReleaseClock=clock+.04}
            else
                -- Native hit path rejected the note: do not leave a lane pressed.
                hit(index,false,clock);state.Rejected+=1
            end
        end
    end
end

local gui={Enabled=false,Destroy=function()end}
local button={Parent=true}
state.Gui=gui;state.Connections={}
function state:Release()
    local field=self.Field
    for lane,held in pairs(self.Held) do
        if field and field.Game and not field.Game.Ending and field.Lanes and field.Lanes[held.Index]==lane then
            pcall(field.HitLane,field,held.Index,false,os.clock())
        end
    end
    table.clear(self.Held);self.Field=nil
end
function state:SetEnabled(value)
    if self.Engine then self.Engine:Disconnect();self.Engine=nil end
    self:Release();self.Enabled=value==true and not self.Destroyed
    button.BackgroundColor3=self.Enabled and Color3.fromRGB(36,165,91) or Color3.fromRGB(164,55,62)
    self.Status=self.Enabled and "Waiting for local song" or "Off"
    if self.Enabled then
        self.Engine=RunService.RenderStepped:Connect(function()
            local ok,message=pcall(function()
                local field=handler.Field
                if field~=self.Field then self:Release();self.Field=field end
                if not field or not field.Game or field.Game.Ending
                    or handler.Playing~=field.Game.GUID then self:Release();self.Status="Waiting for local song";return end
                if field.AutoPlay then self:Release();self.Status="Native bot mode active";return end
                if UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then self:Release();self.Status="Paused for input / menu";return end
                local clock=os.clock()
                local time,rate=songTime(field.Game,clock)
                if not time or time<0 then self.Status="Countdown";return end
                local offset=framework.SettingsHandler:Get("HitboxOffset") or 0
                time+=offset/1000
                tickLanes(self,field,time,rate,clock,ignored,function(index,pressed,stamp)
                    field:HitLane(index,pressed,stamp)
                end)
                self.Status="Playing local lanes"
            end)
            if not ok then self.Errors+=1;self.LastError=tostring(message);self:SetEnabled(false);warn("[FF Autoplay] "..self.LastError) end
        end)
    end
end
function state:GetSnapshot()
    return {Version=self.Version,Enabled=self.Enabled,Hits=self.Hits,Rejected=self.Rejected,
        Errors=self.Errors,LastError=self.LastError,Status=self.Status,
        Side=self.Field and self.Field.Side,Keys=self.Field and self.Field.Keys}
end
function state:Destroy()
    self:SetEnabled(false);self.Destroyed=true
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    gui:Destroy()
    if env.__FF_AUTOPLAY==self then env.__FF_AUTOPLAY=nil end
end
state.HubOnly=true
env.__FF_AUTOPLAY=state
state:SetEnabled(false)
print("[FF Autoplay] Loaded OFF. Controlled by the Allen Scripts hub switch.")


]====]);assert(fn,err);fn()
        controller=env.__FF_AUTOPLAY
    end
    assert(controller and not controller.Destroyed,"Autoplay engine unavailable")
    controller:SetEnabled(false)
    if controller.Gui then controller.Gui.Enabled=false end
end
local ok,err=pcall(initialize)
if not ok then folder:SetAttribute("Error",tostring(err));folder:SetAttribute("Status","Engine failed to load");return end
local bridge={Destroyed=false,Controller=controller,Folder=folder}
local function sync()
    if not folder.Parent then return end
    local q=controller:GetSnapshot()
    folder:SetAttribute("Enabled",q.Enabled==true)
    folder:SetAttribute("Hits",q.Hits or 0)
    folder:SetAttribute("Status",q.Status or "Off")
    folder:SetAttribute("Errors",q.Errors or 0)
end
-- Read the hub's desired state across Actor contexts without script ancestry requirements.
local lastRequested=false
local function applyRequested()
    local desired=folder:GetAttribute("DesiredEnabled")==true
    if desired~=lastRequested then
        lastRequested=desired
        local success,message=pcall(controller.SetEnabled,controller,desired)
        if not success then
            folder:SetAttribute("DesiredEnabled",false)
            folder:SetAttribute("Error",tostring(message))
        end
    end
end
function bridge:Destroy()
    if self.Destroyed then return end
    self.Destroyed=true
    if controller and not controller.Destroyed then controller:Destroy() end
    if env.__ALLEN_FF_BRIDGE==self then env.__ALLEN_FF_BRIDGE=nil end
end
env.__ALLEN_FF_BRIDGE=bridge
sync();folder:SetAttribute("Ready",true)
task.spawn(function()
    while not bridge.Destroyed and folder.Parent and not controller.Destroyed do
        applyRequested();sync();task.wait(.05)
    end
    bridge:Destroy()
end)

]=====],
Duels=[====[
-- Allen Scripts: Funky Duels native autoplay. Starts OFF.
assert(game.GameId==10766630653,"Open Funky Duels to use this script")
assert(debug and type(debug.getupvalues)=="function","Executor requires debug.getupvalues")
local env=getgenv()
if env.__FUNKY_DUELS_AUTOPLAY then env.__FUNKY_DUELS_AUTOPLAY:Destroy() end
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local client=Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client",10)
assert(client,"Funky Duels client not ready")
local Note=require(client.Gameplay.Note)
local Input=require(client.Gameplay.Input)
local Conductor=require(client.Gameplay.Conductor)
local GameState=require(client.Core.State)
local hurtType=require(game:GetService("ReplicatedStorage").Shared.Constants).Match.HurtNoteType
local bindKeyboard=debug.getupvalues(Input.Init)[8]
assert(type(bindKeyboard)=="function" and debug.info(bindKeyboard,"n")=="bindKeyboard","Input layout changed")
local bindings=debug.getupvalues(bindKeyboard)
local press,release=bindings[5],bindings[6]
assert(type(press)=="function" and type(release)=="function" and debug.info(press,"n")=="handlePress" and debug.info(release,"n")=="handleRelease","Input callbacks unavailable")
local state={Enabled=false,Destroyed=false,Held={},Hits=0,Errors=0,Status="Off",Connections={}}
local directions={"Left","Down","Up","Right"}
function state:Release()
    for dir in pairs(self.Held)do pcall(release,dir)end
    table.clear(self.Held)
end
function state:SetEnabled(value)
    self:Release()
    self.Enabled=value==true and not self.Destroyed
    self.Status=self.Enabled and "Waiting for song" or "Off"
    if self.Switch then
        self.Switch.BackgroundColor3=self.Enabled and Color3.fromRGB(45,157,87) or Color3.fromRGB(60,60,65)
        self.Thumb.Position=UDim2.new(self.Enabled and 1 or 0,self.Enabled and -29 or 3,.5,-13)
    end
end
function state:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Hits=self.Hits,Errors=self.Errors,LastError=self.LastError}
end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    for _,c in ipairs(self.Connections)do c:Disconnect()end
    if self.Gui then self.Gui:Destroy()end
    if env.__FUNKY_DUELS_AUTOPLAY==self then env.__FUNKY_DUELS_AUTOPLAY=nil end
end
state.Connections[1]=RunService.RenderStepped:Connect(function()
    if not state.Enabled or state.Destroyed then return end
    local ok,message=pcall(function()
        local values=debug.getupvalues(Note.TryHitNote)
        local notes,context,offset=values[3],values[4],values[2]
        if type(notes)~="table" or type(context)~="table" then error("Note layout changed")end
        if GameState.GetState()~="InGame" or context.RoundOver or context.RoundInputLocked or Note.IsPaused() or context.IsPaused() then
            state:Release();state.Status="Waiting / paused";return
        end
        if UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then state:Release();state.Status="Paused for menu / typing";return end
        local now=Conductor.GetLiveSongTimeMs()+offset
        local clock=os.clock()
        local left=context.SessionLocalSide=="Left"
        local keys=left and context.OpponentKeys or context.ArrowKeys
        if state.Keys and state.Keys~=keys then state:Release()end
        state.Keys=keys
        for dir,held in pairs(state.Held)do
            if held.EndTime and now>=held.EndTime or not held.EndTime and clock>=held.ReleaseClock then
                release(dir);state.Held[dir]=nil
            end
        end
        local due={}
        for _,note in ipairs(notes)do
            if not note.Hit and not note.Missed and note.IsPlayer==not left and note.Type~=hurtType and type(note.TimeMs)=="number" then
                local delta=now-note.TimeMs
                if delta>=0 and delta<=100 then
                    local best=due[note.Dir]
                    if not best or note.TimeMs<best.TimeMs then due[note.Dir]=note end
                end
            end
        end
        for _,dir in ipairs(directions)do
            local note=due[dir]
            if note then
                -- Release only between taps. Keep a live hold pressed through same-lane notes.
                local held=state.Held[dir]
                if held and not held.EndTime then release(dir);state.Held[dir]=nil end
                press(dir)
                if note.Hit then
                    state.Hits+=1
                    local endTime=(note.HoldMs or 0)>0 and note.TimeMs+note.HoldMs or nil
                    if held and held.EndTime then endTime=math.max(endTime or held.EndTime,held.EndTime)end
                    state.Held[dir]={EndTime=endTime,ReleaseClock=clock+.035}
                end
            end
        end
        state.Status="Playing "..(left and "left" or "right").." lanes"
    end)
    if not ok then
        state.Errors+=1;state.LastError=tostring(message);state:SetEnabled(false)
        state.Status="Error: "..state.LastError;warn("[Funky Duels Autoplay] "..state.LastError)
    end
end)
state.HubOnly=true
env.__FUNKY_DUELS_AUTOPLAY=state
state:SetEnabled(false)
print("[Funky Duels Autoplay] Loaded OFF. Controlled by the hub switch.")
return state

]====],
MMM=[====[
-- Allen Scripts: Monday Morning Misery. Hub-controlled native lane autoplay.
assert(game.GameId==2802559498,"Open Monday Morning Misery")
assert(type(getgc)=="function" and debug and type(debug.getupvalues)=="function" and type(debug.info)=="function","Executor requires getgc, debug.getupvalues and debug.info")
local env=getgenv()
if env.__MMM_AUTOPLAY then env.__MMM_AUTOPLAY:Destroy()end
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local methods
for _,value in ipairs(getgc(true))do
    if type(value)=="table" and type(rawget(value,"_GetClosestNote"))=="function" and type(rawget(value,"_ArrowPressed"))=="function" then methods=value;break end
end
assert(methods,"Monday Morning Misery note engine not ready")
local state={HubOnly=true,Enabled=false,Destroyed=false,Held={},Bindings={},Hits=0,Holds=0,Errors=0,Status="Off",NextScan=0}
local function dangerous(note)
    if not note or not note[1] then return true end
    local config=note[3]
    return config and type(config.IsDangerous)=="table" and config.IsDangerous[note[1]:GetAttribute("NoteType")]==true
end
function state:Release()
    for _,held in pairs(self.Held)do pcall(held.Binding.Activate,3)end
    table.clear(self.Held)
end
function state:SetEnabled(value)
    self:Release();self.Enabled=value==true and not self.Destroyed
    self.Status=self.Enabled and "Waiting for song" or "Off"
end
function state:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Hits=self.Hits,Holds=self.Holds,Errors=self.Errors,LastError=self.LastError}
end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if self.Connection then self.Connection:Disconnect()end
    table.clear(self.Bindings)
    if env.__MMM_AUTOPLAY==self then env.__MMM_AUTOPLAY=nil end
end
function state:FindBindings(context)
    self.NextScan=os.clock()+1
    table.clear(self.Bindings)
    local side=({"Left","Right"})[context.PlayerType]
    local gui=context.ArrowGui
    local sideGui=gui and side and gui:FindFirstChild(side)
    local container=sideGui and sideGui:FindFirstChild("MainArrowContainer")
    if not container then return end
    for _,fn in ipairs(getgc())do
        if type(fn)=="function" then
            local ok,name=pcall(debug.info,fn,"n")
            if ok and name=="ActivateArrow" then
                local up=debug.getupvalues(fn)
                local owner,arrow=up[1],up[8]
                if type(owner)=="table" and typeof(arrow)=="Instance" and arrow.Parent==container and type(owner._CantHitNotes)=="function" then
                    self.Bindings[arrow.Name]={Activate=fn,Owner=owner,Arrow=arrow}
                end
            end
        end
    end
    local count=0;for _ in pairs(self.Bindings)do count+=1 end
    if count>=(context.MaxArrows or 4) then self.NextScan=math.huge end
end
state.Connection=RunService.RenderStepped:Connect(function(dt)
    if not state.Enabled or state.Destroyed then return end
    local ok,message=pcall(function()
        local up=debug.getupvalues(methods._GetClosestNote)
        local lanes,options,context=up[1],up[2],up[5]
        local gui=context.ArrowGui
        if not gui or not gui.Parent or not options then state:Release();state.Status="Waiting for song";return end
        if state.RoundGui~=gui or state.PlayerType~=context.PlayerType then
            state:Release();table.clear(state.Bindings);state.RoundGui=gui;state.PlayerType=context.PlayerType;state.NextScan=0
        end
        if os.clock()>=state.NextScan then state:FindBindings(context)end
        if not next(state.Bindings) then state.Status="Waiting for lane controls";return end
        if UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then state:Release();state.Status="Paused for menu / typing";return end
        local down=options.DownScroll==true
        local speed=methods:_GetNoteSpeed()
        local target=down and 1 or 0
        for name,binding in pairs(state.Bindings)do
            if binding.Owner:_CantHitNotes() then state:Release();state.Status="Input locked";return end
            local held=state.Held[name]
            if held then
                local tail=held.Tail
                local finished=not tail or not tail.Parent or not tail.Visible
                if not finished then
                    local tip=tail.Position.Y.Scale+(down and -1 or 1)*tail.Size.Y.Scale
                    finished=down and tip>=target or not down and tip<=target
                end
                if finished then binding.Activate(3);state.Held[name]=nil end
            end
            local list=lanes[name]
            local candidate
            for _,note in ipairs(list or {})do
                local head=note[1]
                if head and head.Parent and not dangerous(note) then
                    local remaining=(down and (target-head.Position.Y.Scale) or (head.Position.Y.Scale-target))/speed
                    if remaining<=math.min(dt*.5,.012) and remaining>=-.09 then candidate=note;break end
                end
            end
            if candidate then
                -- Confirm the game would select the same safe note before using its input callback.
                local selected=binding.Owner:_GetClosestNote(binding.Arrow)
                if selected and selected[1]==candidate and not dangerous(selected[1])then
                    binding.Activate(1)
                    local result=debug.getupvalues(binding.Activate)[2]
                    if result and result[1]==candidate then
                        state.Hits+=1
                        local tail=candidate[2]
                        if tail and tail.Parent and tail.Visible then state.Held[name]={Binding=binding,Tail=tail};state.Holds+=1
                        else binding.Activate(3);state.Held[name]=nil end
                    end
                end
            end
        end
        state.Status="Playing local lanes"
    end)
    if not ok then state.Errors+=1;state.LastError=tostring(message);state:SetEnabled(false);state.Status="Engine error";warn("[MMM Autoplay] "..state.LastError)end
end)
env.__MMM_AUTOPLAY=state
state:SetEnabled(false)
print("[MMM Autoplay] Loaded OFF; controlled by the hub switch.")
return state

]====],
IsolatedDodge=[====[
-- Isolated DODGE! controller: invokes one validated native hotbar callback per swing.
-- No synthesized keyboard/touch input, direct remotes, map index or movement.
assert(game.GameId==7008097940,"Open Ink Game")
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local Run=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
assert(type(getconnections)=="function"and debug and type(debug.getupvalues)=="function",
    "Native hotbar callback inspection is unavailable on this executor")
local env=getgenv()
if env.__ALLEN_HNS_dodge then env.__ALLEN_HNS_dodge:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Actions=0,Attempts=0,Status="Off",MaxStepMs=0,Generation=0}
local animationIds={}
local abilities=RS:FindFirstChild("Animations");abilities=abilities and abilities:FindFirstChild("Abilities")
local knife=abilities and abilities:FindFirstChild("Knife")
if knife then for _,v in ipairs(knife:GetChildren())do
    local name=v.Name:lower()
    if v:IsA("Animation")and name:find("swing",1,true)and not name:find("victim",1,true)then
        local id=v.AnimationId:match("%d+")
        if id then animationIds[id]={Kind="Knife",Range=name:find("lunge",1,true)and 14 or 8}end
    end
end end
-- SharedFunctions maps Weak Fists to FightBack, which also contains non-punch assets.
-- Explicit whitelist avoids victim, clash, QTE and pole animations in the same folder.
local weakNames={Punch1=true,Punch2=true,Punch3=true,AttemptToPunchBack=true}
local fightBack=abilities and abilities:FindFirstChild("FightBack")
if fightBack then for _,v in ipairs(fightBack:GetChildren())do
    if v:IsA("Animation")and weakNames[v.Name]then
        local id=v.AnimationId:match("%d+")
        if id then animationIds[id]={Kind="Weak Fists",Range=6}end
    end
end end
local function weaponMatches(c,kind)
    -- The exact FightBack punch IDs identify Weak Fists even when it auto-uses from inventory.
    return kind=="Weak Fists" or c:FindFirstChild("Knife")~=nil
end
local watches,threats={},{}
local heartbeat,lastScan,lastAttempt,statusUntil,elapsed=nil,0,-math.huge,0,0
local function log(...)print("[DODGE ISOLATED]",...)end
local function live(p)
    local c=p.Character;local h=c and c:FindFirstChildOfClass("Humanoid");local r=c and c:FindFirstChild("HumanoidRootPart")
    if h and h.Health>0 and r then return c,h,r end
end
local function cooldown(c)
    for _,v in ipairs(c:GetChildren())do if not v:IsA("Tool") and (v:GetAttribute("CD")=="DODGE!"or v:GetAttribute("CD")=="Dodge")then return true end end
    return false
end
local function slotHandler()
    local pg=LP:FindFirstChildOfClass("PlayerGui");local bar=pg and pg:FindFirstChild("Hotbar")
    bar=bar and bar:FindFirstChild("Backpack");bar=bar and bar:FindFirstChild("Hotbar")
    if not bar then return end
    for _,button in ipairs(bar:GetChildren())do
        local label=button:FindFirstChild("ToolName")
        if button:IsA("GuiButton")and button.Visible and label and label.Text=="DODGE!"then
            local handler
            for _,connection in ipairs(getconnections(button.MouseButton1Down))do
                local fn=connection.Function
                if type(fn)=="function"then
                    local ok,u=pcall(debug.getupvalues,fn)
                    -- Native backpack handler: inventory-open flag, drag fn, slot, char, bag, use fn.
                    if ok and type(u)=="table"and type(u[1])=="boolean"and type(u[2])=="function"
                        and u[3]==button and typeof(u[4])=="Instance"and typeof(u[5])=="Instance"and type(u[6])=="function"then
                        if u[1]then return nil,"Close the inventory editor"end
                        if handler then return nil,"Multiple native hotbar handlers; stopped"end
                        handler=fn
                    end
                end
            end
            return handler,handler and nil or "Native hotbar callback schema changed"
        end
    end
    return nil,"DODGE! must be visible in the hotbar"
end
local function scan()
    local present={};local n=0
    for _,p in ipairs(Players:GetPlayers())do
        if p~=LP then
            n+=1;if n>32 then break end
            local c,h=live(p);local a=h and h:FindFirstChildOfClass("Animator")
            if a then
                present[p]=a
                if not watches[p]or watches[p].Animator~=a then
                    if watches[p]then watches[p].Connection:Disconnect()end
                    watches[p]={Animator=a,Connection=a.AnimationPlayed:Connect(function(track)
                        if not S.Enabled then return end
                        local id=track.Animation and track.Animation.AnimationId:match("%d+")
                        local profile=id and animationIds[id]
                        if profile and weaponMatches(c,profile.Kind)then
                            threats[p]={Character=c,Track=track,Range=profile.Range,Kind=profile.Kind,Expires=os.clock()+1.2,Attempted=false}
                            log("swing",p.Name,profile.Kind,id)
                        end
                    end)}
                end
            end
        end
    end
    for p,w in pairs(watches)do if present[p]~=w.Animator then w.Connection:Disconnect();watches[p]=nil;threats[p]=nil end end
end
local DashPolicy=(function()
local P={}
local function finite(v)return v==v and math.abs(v)<math.huge end
function P.Entry(x,y,z,vx,vy,vz,range)
    if not(finite(x)and finite(y)and finite(z)and finite(vx)and finite(vy)and finite(vz))then return end
    local near,far=0,.14
    local speed=math.sqrt(vx*vx+vz*vz)
    local inside=math.abs(x)<=4.25 and math.abs(y)<=5.75 and z>=-range-.75 and z<=.75
    if inside then return 0 end
    -- Only predict a fast approach, not ordinary distant swings or movement away.
    if speed<15 or speed>250 or x*vx+z*vz>=0 then return end
    far=math.min(far,10/speed)
    local function slab(position,velocity,low,high)
        if math.abs(velocity)<.001 then return position>=low and position<=high end
        local a,b=(low-position)/velocity,(high-position)/velocity
        if a>b then a,b=b,a end
        near=math.max(near,a);far=math.min(far,b)
        return near<=far
    end
    if slab(x,vx,-4.25,4.25)and slab(y,vy,-5.75,5.75)and slab(z,vz,-range-.75,.75)then return near end
end
return P

end)()
local function hitboxEntry(root,target,range)
    local point=root.CFrame:PointToObjectSpace(target.Position)
    local relative=root.CFrame:VectorToObjectSpace(target.AssemblyLinearVelocity-root.AssemblyLinearVelocity)
    return DashPolicy.Entry(point.X,point.Y,point.Z,relative.X,relative.Y,relative.Z,range)
end
local function directedThreat(root,target,range)
    local offset=target.Position-root.Position
    local flat=Vector3.new(offset.X,0,offset.Z)
    local facing=Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z)
    if flat.Magnitude<.1 or facing.Magnitude<.1 or facing.Unit:Dot(flat.Unit)<.65 then return end
    local entry=hitboxEntry(root,target,range)
    if type(entry)=="number" and entry<=.07 then return entry end
end
local function step()
    local now=os.clock()
    if now-lastScan>=.5 then lastScan=now;scan()end
    local c,h,r=live(LP);if not c then return end
    local bag=LP:FindFirstChildOfClass("Backpack")
    if not(c:FindFirstChild("DODGE!")or bag and bag:FindFirstChild("DODGE!"))then S.Status="DODGE! item required";return end
    if cooldown(c)then if S.PendingInput then S.PendingInput.Observed=true end;S.Status="Native DODGE! cooldown · waiting";return end
    if c:FindFirstChild("Ragdoll")or c:FindFirstChild("Stun")or c:FindFirstChild("DisableTools")then S.Status="Waiting for recovery";return end
    if now>statusUntil then S.Status="Watching knife / weak fists + dash approach · one activation per swing"end
    for p,t in pairs(threats)do
        if now>t.Expires or not t.Track.IsPlaying or p.Character~=t.Character then threats[p]=nil
        elseif not t.Attempted and now-lastAttempt>=.55 then
            local attacker,_,root=live(p)
            local entry=attacker and weaponMatches(attacker,t.Kind)and directedThreat(root,r,t.Range)
            local turning=false
            if root then
                local look=root.CFrame.LookVector
                if t.LastLook and now>t.LastLookAt then
                    turning=math.acos(math.clamp(look:Dot(t.LastLook),-1,1))/(now-t.LastLookAt)>4.5
                end
                t.LastLook=look;t.LastLookAt=now
            end
            if type(entry)~="number" or turning then t.DirectedSince=nil
            elseif not t.DirectedSince then t.DirectedSince=now end
            if type(entry)=="number" and not turning and t.DirectedSince and now-t.DirectedSince>=.05 then
                if UIS:GetFocusedTextBox()then S.Status="Close text input to dodge";return end
                local handler,reason=slotHandler()
                if not handler then S.Status=reason or "Native hotbar handler unavailable";return end
                -- Recheck current geometry in the callback task before consuming this swing.
                local generation=S.Generation
                local attempt={Observed=false};S.PendingInput=attempt
                task.spawn(function()
                    if not S.Enabled or generation~=S.Generation or LP.Character~=c then return end
                    if threats[p]~=t or t.Attempted or not t.Track.IsPlaying or p.Character~=attacker
                        or not root.Parent or not r.Parent or cooldown(c)
                        or type(directedThreat(root,r,t.Range))~="number"then
                        t.DirectedSince=nil
                        if S.PendingInput==attempt then S.PendingInput=nil end
                        return
                    end
                    t.Attempted=true;lastAttempt=os.clock();S.Attempts+=1;statusUntil=lastAttempt+2
                    log("confirmed directed swing; native button attempt",S.Attempts,"ETA",entry)
                    local ok,err=pcall(handler)
                    if not ok then
                        log("native button error",tostring(err));S:SetEnabled(false);S.Status="Native hotbar handler failed";return
                    end
                    task.wait(.4)
                    if generation~=S.Generation then return end
                    if S.PendingInput==attempt then S.PendingInput=nil end
                    if attempt.Observed or cooldown(c)then S.Actions+=1;S.Status="DODGE! cooldown observed";log("activation cooldown confirmed")
                    else S.Status="Native button called; no cooldown confirmed";log("no activation cooldown")end
                end)
                return
            end
        end
    end
end
function S:SetEnabled(value)
    if self.Destroyed then return end
    self.Enabled=value==true;self.Generation+=1
    if heartbeat then heartbeat:Disconnect();heartbeat=nil end
    for _,w in pairs(watches)do w.Connection:Disconnect()end;table.clear(watches);table.clear(threats)
    if not self.Enabled then self.Status="Off";log("OFF");return end
    lastScan=0;elapsed=0
    heartbeat=Run.Heartbeat:Connect(function(dt)
        elapsed+=dt;if elapsed<1/30 then return end;elapsed=0
        local started=os.clock();local ok,err=pcall(step)
        local duration=(os.clock()-started)*1000;self.MaxStepMs=math.max(self.MaxStepMs,duration)
        if not ok or duration>50 then self:SetEnabled(false);self.Status="Stopped by error / timing guard";log("GUARD STOP",tostring(err),duration)end
    end)
    self.Status="Watching knife / weak-fist threats";log("ON")
end
function S:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Actions=self.Actions,Attempts=self.Attempts,MaxStepMs=self.MaxStepMs}end
function S:Destroy()if self.Destroyed then return end;self:SetEnabled(false);self.Destroyed=true;if env.__ALLEN_HNS_dodge==self then env.__ALLEN_HNS_dodge=nil end end
env.__ALLEN_HNS_dodge=S
return S

]====],
HalloweenShoot=[====[
assert(game.PlaceId == 105920136178200, "Open the Ink Game Halloween event")
local env = getgenv()
local key = "__ALLEN_HALLOWEEN_SHOOT"
if env[key] then env[key]:Destroy() end

local player = game:GetService("Players").LocalPlayer
local rs = game:GetService("ReplicatedStorage")
local tags = game:GetService("CollectionService")
local gun = require(rs.Modules.GunFunctions)
local gunClient = require(rs.Modules.GunSystemClient)
local combat = require(rs.Modules.Halloween2026Combat)
local attr = combat.Attr
local state = {HubOnly = true, Enabled = false, Status = "Off"}
local connection
local nextStep, nextReload, nextPickup = 0, 0, 0

local ammoTrip
local attemptedPrompts = setmetatable({}, {__mode = "k"})

local function tripActive(trip)
    local humanoid = trip.Character:FindFirstChildOfClass("Humanoid")
    return ammoTrip == trip and state.Enabled and player.Character == trip.Character
        and trip.Root.Parent == trip.Character and humanoid and humanoid.Health > 0
        and trip.Character:GetAttribute(attr.Team) ~= combat.Team.Infected
end

local function stopAmmoTrip(trip)
    if ammoTrip ~= trip then return end
    ammoTrip = nil
    if trip.SprintInfo and trip.SprintInfo.Parent then
        local input = game:GetService("UserInputService")
        local shiftHeld = input:IsKeyDown(Enum.KeyCode.LeftShift) or input:IsKeyDown(Enum.KeyCode.RightShift)
        trip.SprintInfo:Fire({RunningEnabled = true, State = shiftHeld})
    end
    local humanoid = trip.Character:FindFirstChildOfClass("Humanoid")
    if player.Character == trip.Character and humanoid and trip.Root.Parent then
        humanoid:MoveTo(trip.Root.Position)
    end
end

local function walkTo(trip, destination, radius)
    if not tripActive(trip) then return false end
    local humanoid = trip.Character:FindFirstChildOfClass("Humanoid")
    local path = game:GetService("PathfindingService"):CreatePath()
    path:ComputeAsync(trip.Root.Position, destination)
    if not tripActive(trip) or path.Status ~= Enum.PathStatus.Success then return false end
    local deadline = os.clock() + 35
    for _, waypoint in ipairs(path:GetWaypoints()) do
        if not tripActive(trip) or os.clock() > deadline then return false end
        if (trip.Root.Position - destination).Magnitude <= radius then return true end
        if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
        humanoid:MoveTo(waypoint.Position)
        local expires = os.clock() + 4
        repeat
            task.wait(0.1)
            if not tripActive(trip) then return false end
        until (trip.Root.Position - waypoint.Position).Magnitude < 3 or os.clock() >= expires
        if (trip.Root.Position - waypoint.Position).Magnitude >= 3 then return false end
    end
    return (trip.Root.Position - destination).Magnitude <= radius
end

local function collectAmmo(root, now)
    if ammoTrip or now < nextPickup or type(fireproximityprompt) ~= "function" then return end
    nextPickup = now + 2
    local nearest, nearestPoint, distance = nil, nil, math.huge
    for _, prompt in ipairs(tags:GetTagged(attr.AmmoPromptTag)) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled and prompt:IsDescendantOf(workspace)
            and now - (attemptedPrompts[prompt] or -math.huge) >= 5 then
            local parent = prompt.Parent
            local point = parent:IsA("Attachment") and parent.WorldPosition
                or parent:IsA("BasePart") and parent.Position
                or parent:IsA("Model") and parent:GetPivot().Position
            if point then
                local d = (point - root.Position).Magnitude
                if d < distance then nearest, nearestPoint, distance = prompt, point, d end
            end
        end
    end
    if not nearest then return end
    attemptedPrompts[nearest] = now
    local trip = {Root = root, Character = player.Character, Origin = root.Position}
    local main = trip.Character:FindFirstChild("Main")
    local info = main and main:FindFirstChild("Info")
    if info and info:IsA("BindableEvent") then
        trip.SprintInfo = info
        info:Fire({RunningEnabled = true, State = true})
    end
    ammoTrip = trip
    task.spawn(function()
        local ok, err = pcall(function()
            local range = math.min(nearest.MaxActivationDistance, 10)
            local arrived = walkTo(trip, nearestPoint, math.max(2, range - 1))
            if arrived and tripActive(trip) and nearest.Parent and nearest.Enabled
                and (root.Position - nearestPoint).Magnitude <= range then
                fireproximityprompt(nearest)
                task.wait(0.3)
            end
        end)
        if tripActive(trip) then
            local returned, returnError = pcall(walkTo, trip, trip.Origin, 3)
            if not returned then warn("[Halloween ammo return] " .. tostring(returnError)) end
        end
        stopAmmoTrip(trip)
        if not ok then warn("[Halloween ammo] " .. tostring(err)) end
    end)
end

local function step(now)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return end
    if character:GetAttribute(attr.Team) == combat.Team.Infected then
        state.Status = "Waiting for survivor team"
        return
    end
    collectAmmo(root, now)
    if ammoTrip then state.Status = "Collecting ammo / returning"; return end
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool or not combat.IsActiveEventTool(tool) or not character:GetAttribute("HoldingWeapon") then
        state.Status = "Equip an event gun"
        return
    end
    local info = tool:FindFirstChild("InfoClient")
    local bullets = info and info:FindFirstChild("Bullets")
    if bullets and bullets.Value <= 0 then
        if now >= nextReload then
            nextReload = now + 1
            gunClient.Reload(character)
        end
        state.Status = "Reloading / waiting for ammo"
        return
    end
    if character:FindFirstChild("CurrentlyReloading") or character:FindFirstChild("CD " .. tool.Name) then return end
    local live = workspace:FindFirstChild("Live")
    if not live then return end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    local aim, best = nil, math.huge
    for _, model in ipairs(live:GetChildren()) do
        if model:IsA("Model") and model ~= character and (model.Name:match("^_InfectedZombie%d+$") or model:GetAttribute(attr.Team) == combat.Team.Infected) then
            local hp = model:FindFirstChildOfClass("Humanoid")
            local target = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
            if hp and hp.Health > 0 and target and target:IsA("BasePart") then
                local offset = target.Position - root.Position
                if offset.Magnitude < best then
                    local hit = workspace:Raycast(root.Position, offset, params)
                    if not hit or hit.Instance:IsDescendantOf(model) then
                        aim, best = target.Position, offset.Magnitude
                    end
                end
            end
        end
    end
    state.Status = aim and "Firing at zombies" or "Waiting for a clear shot"
    if aim then gun.FiredGun(character, aim, {CustomFireFrom = true}) end
end

function state:SetEnabled(enabled)
    if connection then connection:Disconnect(); connection = nil end
    self.Enabled = enabled == true and not self.Destroyed
    self.Status = self.Enabled and "Searching for zombies" or "Off"
    if not self.Enabled then
        if ammoTrip then stopAmmoTrip(ammoTrip) end
        return
    end
    connection = game:GetService("RunService").Heartbeat:Connect(function()
        local now = os.clock()
        if now < nextStep then return end
        nextStep = now + 0.08
        local ok, err = pcall(step, now)
        if not ok then
            self:SetEnabled(false)
            self.Status = "Stopped: " .. tostring(err)
            warn(self.Status)
        end
    end)
end

function state:Destroy()
    self:SetEnabled(false)
    self.Destroyed = true
    if env[key] == self then env[key] = nil end
end

env[key] = state
return state

]====],
CandyESP=[====[
assert(game.GameId == 7008097940, "Open Ink Game")
local env = getgenv()
local key = "__ALLEN_CANDY_ESP"
if env[key] then env[key]:Destroy() end
local state = {HubOnly = true, Enabled = false, Status = "Off"}
local markers = {}
local connection, addedConnection
local folder
local function pickup(object)
    if not (object:IsA("Model") or object:IsA("BasePart")) then return false end
    if object:FindFirstAncestor("Live") then return false end
    local name = object.Name:lower()
    return name == "candy" or name == "candypile" or name == "candypickup"
        or name == "candydrop" or object:GetAttribute("CandyPickup") == true
end
local function clear()
    if connection then connection:Disconnect(); connection = nil end
    if addedConnection then addedConnection:Disconnect(); addedConnection = nil end
    if folder then folder:Destroy(); folder = nil end
    table.clear(markers)
end
local function refresh()
    local count = 0
    local root = game:GetService("Players").LocalPlayer.Character
    root = root and root:FindFirstChild("HumanoidRootPart")
    for object, marker in pairs(markers) do
        if not object:IsDescendantOf(workspace) or not marker.Part:IsDescendantOf(object) and marker.Part ~= object then
            marker.Highlight:Destroy()
            marker.Gui:Destroy()
            markers[object] = nil
        else
            count += 1
            local position = marker.Part.Position
            local distance = root and math.floor((position - root.Position).Magnitude)
            marker.Text.Text = distance and ("Candy · " .. distance .. " studs") or "Candy"
        end
    end
    state.Status = count .. " candy pickups marked"
end
local function add(object)
    if not state.Enabled or markers[object] or not pickup(object) then return end
    local ancestor = object.Parent
    while ancestor and ancestor ~= workspace do
        if pickup(ancestor) then return end
        ancestor = ancestor.Parent
    end
    local part = object:IsA("BasePart") and object or object:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end
    local highlight = Instance.new("Highlight")
    highlight.Adornee = object
    highlight.FillColor = Color3.fromRGB(255, 145, 30)
    highlight.OutlineColor = Color3.fromRGB(255, 240, 140)
    highlight.FillTransparency = 0.35
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = folder
    local gui = Instance.new("BillboardGui")
    gui.Adornee = part
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(160, 30)
    gui.StudsOffset = Vector3.new(0, 2, 0)
    gui.Parent = folder
    local text = Instance.new("TextLabel")
    text.Size = UDim2.fromScale(1, 1)
    text.BackgroundTransparency = 1
    text.TextColor3 = Color3.fromRGB(255, 200, 90)
    text.TextStrokeTransparency = 0.2
    text.Font = Enum.Font.GothamBold
    text.TextSize = 14
    text.Text = "Candy"
    text.Parent = gui
    markers[object] = {Highlight = highlight, Gui = gui, Text = text, Part = part}
end
function state:SetEnabled(enabled)
    clear()
    self.Enabled = enabled == true and not self.Destroyed
    self.Status = self.Enabled and "Looking for candy pickups" or "Off"
    if not self.Enabled then return end
    folder = Instance.new("Folder")
    folder.Name = "AllenCandyESP"
    folder.Parent = game:GetService("Players").LocalPlayer.PlayerGui
    for _, object in ipairs(workspace:GetDescendants()) do add(object) end
    addedConnection = workspace.DescendantAdded:Connect(function(object)
        task.defer(function()
            if self.Enabled and object:IsDescendantOf(workspace) then
                add(object)
                if object.Parent then add(object.Parent) end
            end
        end)
    end)
    local elapsed = 0
    connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed < 1 then return end
        elapsed = 0
        refresh()
    end)
    refresh()
end
function state:GetSnapshot()
    return {Enabled = self.Enabled, Status = self.Status}
end
function state:Destroy()
    self:SetEnabled(false)
    self.Destroyed = true
    if env[key] == self then env[key] = nil end
end
env[key] = state
return state

]====],
PA=[====[
assert(game.GameId==4557322431,"Open Project: Afternight")
local env=getgenv()
if env.__ALLEN_PA_AUTOPLAY then env.__ALLEN_PA_AUTOPLAY:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Status="Off"}
local engine
local function findEngine()
 assert(type(getgc)=="function","Executor needs getgc support")
 local found
 for _,v in ipairs(getgc(true))do
  if type(v)=="table"and type(rawget(v,"GetAutoplay"))=="function"and type(rawget(v,"SetAutoplay"))=="function"then
   assert(not found,"Multiple gameplay engines found; reload the game")
   found=v
  end
 end
 assert(found,"Gameplay engine not ready")
 return found
end
function S:SetEnabled(on)
 if self.Destroyed then return end
 if on then engine=findEngine();engine.SetAutoplay(true);self.Enabled=engine.GetAutoplay()==true;assert(self.Enabled,"Native botplay did not enable")
 else if engine then engine.SetAutoplay(false)end;self.Enabled=false end
 self.Status=self.Enabled and "Native botplay ON · game scoring rules apply"or"Off"
end
function S:GetSnapshot()
 if engine then self.Enabled=engine.GetAutoplay()==true end
 return {Enabled=self.Enabled,Status=self.Enabled and "Native botplay ON · game scoring rules apply"or"Off"}
end
function S:Destroy()
 if self.Destroyed then return end
 self:SetEnabled(false);self.Destroyed=true
 if env.__ALLEN_PA_AUTOPLAY==self then env.__ALLEN_PA_AUTOPLAY=nil end
end
env.__ALLEN_PA_AUTOPLAY=S
return S

]====],
UBGCombat=[====[
-- Untitled Boxing Game native-action auto combat. Starts OFF; one hub switch.
-- No simulated keyboard/mouse input, raw remote replay, stat edits or teleports.
assert(game.GameId==4730278139,"Open Untitled Boxing Game")
local Policy=(function()
local P={}
function P.Decide(s)
    if not s.Match then return "wait"end
    if s.Disabled then return "recover"end
    if s.Threat then
        -- Ordinary lights are cheaper to guard; reserve a fresh dodge for heavier danger.
        if s.ThreatKind=="Light"and s.CanBlock and s.Block>.35 then return "block"end
        if s.CanDash and s.CanAffordDash~=false and s.Stamina>.25 and s.FreshThreat then return "dodge"end
        if s.CanBlock and s.Block>.12 then return "block"end
        return "retreat"
    end
    local restingDistance=s.RestDistance or s.Reach+3
    if s.RecoveringStamina or s.Stamina<.22 or s.Health<.3 and s.Stamina<.55 then
        return s.Distance>=restingDistance and "rest"or"retreat"
    end
    -- A recognized approaching contact should not be met with a fresh attack startup.
    if s.Windup then
        if s.CanBlock and s.Block>.12 then return "block"end
        return s.Distance<s.Reach+2 and "retreat"or"circle"
    end
    if s.Distance>s.Reach then return "approach"end
    if s.Distance<2.1 then return "space"end
    if not s.CanPunch or s.OpponentDashing then return "circle"end
    local opening=s.Opening or 0
    local heavyStartup=s.HeavyStartup or .45
    local ultimateStartup=s.UltimateStartup or .65
    if s.Ultimate>=100 and s.CanAffordUltimate~=false and s.Stamina>.5
        and opening>=ultimateStartup+.1 and s.Distance<s.Reach-.3 then return "ultimate"end
    if s.CanAffordHeavy~=false and s.Stamina>.58 and(opening>=heavyStartup+.1
        or s.OpponentBlocking and s.OpponentBlock<.25)then return "heavy"end
    if s.CanAffordLight~=false and s.Stamina>.3 then return "light"end
    return "circle"
end
return P

end)()
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer
local env=getgenv()
if env.__ALLEN_UBG_COMBAT then env.__ALLEN_UBG_COMBAT:Destroy()end
local S={Version="1.1",HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Attacks=0,Dodges=0,Blocks=0,
    ConfirmedAttacks=0,ConfirmedDodges=0,ConfirmedGuards=0,BlockedRoutes=0,RejectedGuards=0,
    MaxStepMs=0,Generation=0,Desired=Vector3.zero,Threats={},LastAttack=-math.huge,LastDash=-math.huge,
    LastUltimate=-math.huge,LastEquip=-math.huge,Decision="wait"}
local connection,enemyConnection,ownConnection,native,styles,phases,broadcast,controls,originalMove,rawMove,moveShim
local currentTarget,currentCharacter,currentStyle,profileMap,blockCommand
local lockLease,ownProfileMap,ownBoundCharacter,ownStyle=nil,nil,nil,nil
local nextGuardAt,guardRequestedAt=0,nil
local function value(folder,name,default)
    local v=folder and folder:FindFirstChild(name)
    return v and v.Value or default
end
local function flag(folder,name)
    local v=folder and folder:FindFirstChild(name);return v and v.Value==true or false
end
local function stateFor(name)
    local states=workspace:FindFirstChild("States");local s=states and states:FindFirstChild(name)
    return s,s and s:FindFirstChild("CharacterData"),s and s:FindFirstChild("Occupied"),s and s:FindFirstChild("PlayerData")
end
local function live(c)
    local h=c and c:FindFirstChildOfClass("Humanoid");local r=c and c:FindFirstChild("HumanoidRootPart")
    if c and c.Parent and h and h.Health>0 and r then return h,r end
end
local function resolveOpponent(v)
    if typeof(v)=="Instance"then if v:IsA("Player")then return v.Character elseif v:IsA("Model")then return v end end
    local liveFolder=workspace:FindFirstChild("Live")
    return type(v)=="string"and liveFolder and liveFolder:FindFirstChild(v)or nil
end
local function setBlock(on)
    if blockCommand==on then return end
    blockCommand=on
    if native then native.SetBlock:Fire(on)end
    if on then S.Blocks+=1;guardRequestedAt=os.clock();S.GuardObserved=false
    else
        if guardRequestedAt then nextGuardAt=os.clock()+(S.BlockDebounce or .3)end
        guardRequestedAt=nil;S.GuardObserved=false
    end
end
local function releasePunch()
    if native then
        native.TryPunch:Fire({StopHoldingDownHeavy=true,InputType="Heavy"})
        native.TryPunch:Fire({StopHoldingDownHeavy=true,InputType="Light"})
    end
end
local function releaseTarget()
    if enemyConnection then enemyConnection:Disconnect();enemyConnection=nil end
    table.clear(S.Threats);currentTarget=nil;profileMap=nil;currentStyle=nil
    if lockLease then
        local slot=lockLease.Slot
        if slot.Parent and slot.Value==lockLease.Target then slot.Value=lockLease.Original end
        lockLease=nil
    end
    S.Desired=Vector3.zero;S.RecoveringStamina=false;S.PendingAttack=nil;S.PendingDash=nil;S.WasRecovering=false;S.WakeupGuardUntil=nil
end
local function profileStyle(style)
    local info=styles[style];local map={};if type(info)~="table"then return map end
    local defaultReach=math.clamp(((info.HitboxInfo and info.HitboxInfo.Size and info.HitboxInfo.Size.Z)or 2.9)+2.5,4,9)
    local visited=0
    local function walk(t,defaults,kind,depth,seen)
        if type(t)~="table"or depth>4 or seen[t]or visited>=500 then return end;seen[t]=true;visited+=1
        if t.AnimId then
            local id=tostring(t.AnimId):match("%d+")
            if id then map[id]={Kind=kind,Contact=tonumber(t.LandedFrame)or tonumber(t.Startup)or tonumber(defaults.Startup)or .25,
                Reach=defaultReach,Recovery=tonumber(t.MaxTime)or tonumber(defaults.MaxTime)or .75}end
        end
        local n=0;for _,v in pairs(t)do n+=1;if n>100 then break end;if type(v)=="table"then walk(v,defaults,kind,depth+1,seen)end end
    end
    walk(info.Combos,info.DefaultPunchInfo or {},"Light",0,{})
    walk(info.HeavyAttacks,info.HeavyAttacks and info.HeavyAttacks.DefaultPunchInfo or {},"Heavy",0,{})
    walk(info.UltimateInfo,info.UltimateInfo and info.UltimateInfo.DefaultPunchInfo or {},"Ultimate",0,{})
    return map
end
local function trackAttack(track)
    local id=track.Animation and track.Animation.AnimationId:match("%d+")
    local profile=id and profileMap and profileMap[id]
    if profile then
        if #S.Threats>=12 then table.remove(S.Threats,1)end
        S.Threats[#S.Threats+1]={Track=track,Profile=profile,Expires=os.clock()+4,Defended=false}
    end
end
local function bindTarget(target,style)
    local changed=currentTarget~=target
    if changed then
        releaseTarget();currentTarget=target
        local h=target:FindFirstChildOfClass("Humanoid");local a=h and h:FindFirstChildOfClass("Animator")
        if a then enemyConnection=a.AnimationPlayed:Connect(trackAttack)end
    end
    if currentStyle~=style then currentStyle=style;profileMap=profileStyle(style)end
    if changed then local h=target:FindFirstChildOfClass("Humanoid");local a=h and h:FindFirstChildOfClass("Animator");if a then
        for i,tr in ipairs(a:GetPlayingAnimationTracks())do if i>16 then break end;trackAttack(tr)end
    end end
end
local function safeMove(worldDirection,root,target)
    local flat=Vector3.new(worldDirection.X,0,worldDirection.Z)
    local amount=math.min(1,flat.Magnitude)
    if amount<.05 then return Vector3.zero end
    flat=flat.Unit
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={workspace:FindFirstChild("Live")or LP.Character,target};params.RespectCanCollide=true
    local point=root.Position+flat*3
    if workspace:Raycast(root.Position,flat*3,params)then return Vector3.zero end
    local floor=workspace:Raycast(point+Vector3.new(0,2,0),Vector3.new(0,-9,0),params)
    if not floor or floor.Normal.Y<.6 then return Vector3.zero end
    local localDirection=CFrame.lookAt(root.Position,Vector3.new(target.PrimaryPart.Position.X,root.Position.Y,target.PrimaryPart.Position.Z)):VectorToObjectSpace(flat)
    return Vector3.new(localDirection.X,0,localDirection.Z)*amount
end
local function chooseMove(candidates,root,target)
    for i,candidate in ipairs(candidates)do
        local direction=safeMove(candidate,root,target)
        if direction.Magnitude>.05 then return direction,i end
    end
    S.BlockedRoutes+=1;return Vector3.zero,0
end
local function bindOwn(c,style)
    if ownBoundCharacter==c and ownStyle==style then return end
    if ownConnection then ownConnection:Disconnect();ownConnection=nil end
    ownBoundCharacter=c;ownStyle=style;ownProfileMap=profileStyle(style)
    local h=c:FindFirstChildOfClass("Humanoid");local a=h and h:FindFirstChildOfClass("Animator")
    if a then ownConnection=a.AnimationPlayed:Connect(function(track)
        local id=track.Animation and track.Animation.AnimationId:match("%d+")
        local pending=S.PendingAttack
        if id and ownProfileMap[id]and pending and not pending.Observed and os.clock()-pending.Time<.65 then
            pending.Observed=true;S.ConfirmedAttacks+=1
        end
    end)end
end
local function requestPunch(kind,now)
    if now-S.LastAttack<.36 then return end
    if kind=="ultimate"and now-S.LastUltimate<2 then return end
    setBlock(false);S.LastAttack=now
    S.PendingAttack={Time=now,Kind=kind,Observed=false}
    if kind=="ultimate"then native.TryPunch:Fire({IsUltimate=true});S.LastUltimate=now
    elseif kind=="heavy"then native.TryPunch:Fire({IsHeavy=true})
    else native.TryPunch:Fire()end
    S.Attacks+=1
    local generation=S.Generation
    task.delay(.1,function()if generation==S.Generation then releasePunch()end end)
end
local function step()
    local now=os.clock();S.Desired=Vector3.zero
    local c=LP.Character;local h,r=live(c)
    local _,cd,occupied,pd=stateFor(LP.Name)
    if not h or not cd or not occupied then setBlock(false);releaseTarget();S.Status="Waiting for character combat state";return end
    if currentCharacter~=c then releaseTarget();currentCharacter=c;releasePunch();blockCommand=nil end
    local actualGuard=flag(cd,"Blocking")or flag(occupied,"Blocking")
    if blockCommand and actualGuard and not S.GuardObserved then S.GuardObserved=true;S.ConfirmedGuards+=1 end
    if blockCommand and not actualGuard and guardRequestedAt and now-guardRequestedAt>.3 then
        S.RejectedGuards+=1;setBlock(false)
    end
    if S.PendingDash then
        local pending=S.PendingDash
        if pending.Character~=c or now-pending.Time>.5 then S.PendingDash=nil
        elseif flag(cd,"Dashing")or flag(occupied,"Dashing")or c:GetAttribute("LocalDashTime")~=pending.Before then
            S.ConfirmedDodges+=1;S.PendingDash=nil
        end
    end
    if UIS:GetFocusedTextBox()then setBlock(false);S.Status="Paused while typing";return end
    local menu=workspace:FindFirstChild("CurrentMenu")
    if menu and menu.Value~=""then setBlock(false);releaseTarget();S.Status="Paused while menu is open";return end
    local target=resolveOpponent(value(cd,"Opponent"))
    local oh,other=live(target)
    if not target or target==c or not oh or not other or not target.PrimaryPart then
        setBlock(false);releaseTarget();S.Status="Waiting for active match opponent";return
    end
    local _,ocd,ooccupied,opd=stateFor(target.Name)
    if not ocd then setBlock(false);S.Status="Opponent state unavailable";return end
    local styleName=value(pd,"Style","Basic");local opponentStyle=value(opd,"Style","Basic")
    bindTarget(target,opponentStyle);bindOwn(c,styleName)
    local forced=flag(occupied,"ForceMove")or c:GetAttribute("Rooted")or c:GetAttribute("SpecialHoldRooted")
    local blocked=forced or flag(cd,"Cutscene")or flag(cd,"Stunned")or flag(occupied,"Stunned")or flag(occupied,"Spectating")
        or flag(pd,"Disable")or flag(cd,"Toxic")or value(cd,"Health",100)<=0 or c:GetAttribute("StaminaBroken")
    if blocked then S.WasRecovering=true;setBlock(false);S.Decision="recover";S.Status="Waiting for stun / knockdown / cutscene recovery";return end
    if S.WasRecovering then S.WakeupGuardUntil=now+.18;S.WasRecovering=false end
    if flag(ocd,"Cutscene")or value(ocd,"Health",100)<=0 then setBlock(false);S.Status="Waiting for opponent recovery";return end
    if not flag(cd,"Equipped")then
        if now-S.LastEquip>1 then native.TrySwitchEquip:Fire();S.LastEquip=now end
        S.Status="Waiting for native combat equip";return
    end
    local locked=occupied:FindFirstChild("LockedOn")
    if locked and locked.Value~=target then
        if not lockLease then lockLease={Slot=locked,Original=locked.Value,Target=target}end
        locked.Value=target
    end
    local delta=other.Position-r.Position;local flat=Vector3.new(delta.X,0,delta.Z)
    local distance=flat.Magnitude
    if distance<.01 or distance>80 then setBlock(false);S.Status="Opponent outside controlled range";return end
    local toward=flat.Unit;local side=toward:Cross(Vector3.yAxis)
    local facing=other.CFrame.LookVector:Dot(-toward)>.35 and math.abs(delta.Y)<5
    local threatening,fresh,selected=false,false,nil
    local opponentRecovering,opening,windup=false,0,false
    local ownInfo=styles[styleName]or styles.Basic
    local lightInfo=ownInfo.DefaultPunchInfo or {}
    local heavyInfo=ownInfo.HeavyAttacks and ownInfo.HeavyAttacks.DefaultPunchInfo or {}
    local ultimateInfo=ownInfo.UltimateInfo and ownInfo.UltimateInfo.DefaultPunchInfo or {}
    local dashInfo=ownInfo.DashInfo and ownInfo.DashInfo.DefaultInfo or {}
    local coreInfo=ownInfo.CoreInfo or {}
    local lightStartup=tonumber(lightInfo.Startup)or .2
    local heavyStartup=tonumber(heavyInfo.Startup)or .5
    local ultimateStartup=tonumber(ultimateInfo.Startup)or .65
    S.BlockDebounce=tonumber(coreInfo.BlockDebounce)or .3
    local dashInterval=math.clamp((tonumber(dashInfo.DashDelay)or .65)+(tonumber(dashInfo.DashStartup)or .05),.35,1.5)
    for i=#S.Threats,1,-1 do
        local t=S.Threats[i];local tr=t.Track
        if not tr.IsPlaying or now>t.Expires then table.remove(S.Threats,i)
        else
            local eta=(t.Profile.Contact-tr.TimePosition)/math.max(.1,tr.Speed)
            local recovering=phases.IsInRecovery(tr)==true
            if recovering then
                opponentRecovering=true
                opening=math.max(opening,math.max(0,((tonumber(tr.Length)or t.Profile.Recovery)-tr.TimePosition)/math.max(.1,tr.Speed)))
            end
            if not recovering and facing and distance<=t.Profile.Reach+1.5 and eta>0 and eta<=lightStartup+.15 then windup=true end
            if not recovering and facing and distance<=t.Profile.Reach+1.5 and eta<=.24 and eta>=-.15 then
                threatening=true
                if not selected or eta<selected.Eta then selected={Threat=t,Eta=eta};fresh=not t.Defended end
            end
        end
    end
    if not threatening and target:GetAttribute("Punching")and facing and distance<5.5 and #S.Threats==0 then threatening=true end
    local stamina=value(cd,"Stamina",0)/math.max(1,value(cd,"MaxStamina",100))
    local healthRatio=value(cd,"Health",100)/math.max(1,value(cd,"MaxHealth",100))
    local reserve=healthRatio<.3 and .8 or .65
    if stamina<.3 or healthRatio<.3 and stamina<.55 then S.RecoveringStamina=true
    elseif stamina>=reserve then S.RecoveringStamina=false end
    local ownBlock=value(cd,"BlockEnergy",0)/math.max(1,value(cd,"MaxBlockEnergy",50))
    local reach=math.clamp(((ownInfo.HitboxInfo and ownInfo.HitboxInfo.Size and ownInfo.HitboxInfo.Size.Z)or 2.9)+2.2,3.8,8)
    local ownPunch=flag(occupied,"Punching")
    local movementLocked=phases.IsMovementLocked(c)
    local staminaPoints=value(cd,"Stamina",0)
    local dashCost=tonumber(dashInfo.Stamina)or 10
    local reserveCost=dashCost+3
    local threatKind=selected and selected.Threat.Profile.Kind or "Unknown"
    local snapshot={Match=true,Disabled=false,Threat=threatening,FreshThreat=fresh,
        CanDash=not flag(occupied,"Dashing")and not ownPunch and not movementLocked and now-S.LastDash>dashInterval
            and not c:HasTag("DashDisabled")and not c:GetAttribute("NoDash"),
        CanBlock=flag(occupied,"CanBlock")and not ownPunch and not movementLocked and now>=nextGuardAt
            and not c:HasTag("BlockDisabled")and not coreInfo.NoBlock and not c:GetAttribute("NoBlock")
            and not c:GetAttribute("BlockBroken")and not c:GetAttribute("DempseyRolling")and not c:GetAttribute("SlowMo"),
        ThreatKind=threatKind,Windup=windup or(now<(S.WakeupGuardUntil or 0)and facing and distance<=reach+2),Opening=opening,HeavyStartup=heavyStartup,UltimateStartup=ultimateStartup,
        CanAffordDash=staminaPoints>=dashCost+5,
        CanAffordLight=staminaPoints>=(tonumber(lightInfo.Stamina)or 10)+reserveCost,
        CanAffordHeavy=staminaPoints>=(tonumber(heavyInfo.Stamina)or 20)+reserveCost,
        CanAffordUltimate=staminaPoints>=(tonumber(ultimateInfo.Stamina)or 20)+reserveCost,
        RestDistance=reach+3,
        Stamina=stamina,RecoveringStamina=S.RecoveringStamina,Block=ownBlock,Health=value(cd,"Health",100)/math.max(1,value(cd,"MaxHealth",100)),
        Distance=distance,Reach=reach,CanPunch=flag(occupied,"CanPunch")and not flag(occupied,"Dashing")and not ownPunch,
        OpponentVulnerable=flag(ocd,"Stunned")or opponentRecovering,
        OpponentBlocking=flag(ocd,"Blocking")or flag(ooccupied,"Blocking"),
        OpponentBlock=value(ocd,"BlockEnergy",50)/math.max(1,value(ocd,"MaxBlockEnergy",50)),
        OpponentDashing=flag(ocd,"Dashing")or flag(ooccupied,"Dashing"),Ultimate=value(cd,"UltimateEnergy",0)}
    local decision=Policy.Decide(snapshot);S.Decision=decision
    local direction=Vector3.zero
    local sign=math.floor(now/1.2)%2==0 and 1 or -1
    if decision=="approach"then direction=toward
    elseif decision=="retreat"or decision=="space"then direction=-toward+side*.25*sign
    elseif decision=="circle"then direction=side*sign*.35
    elseif decision=="dodge"then direction=side*sign end
    local candidates={direction}
    if decision=="dodge"then candidates={direction,-direction,-toward}
    elseif decision=="approach"or decision=="retreat"or decision=="space"then
        candidates={direction,direction+side*.7,direction-side*.7}
    elseif decision=="circle"then candidates={direction,-direction}end
    S.Desired=direction.Magnitude>.05 and chooseMove(candidates,r,target)or Vector3.zero
    if decision=="block"then setBlock(true)
    elseif decision=="dodge"then
        setBlock(false)
        if S.Desired.Magnitude>.1 then
            if selected then selected.Threat.Defended=true end
            S.LastDash=now;S.Dodges+=1;S.PendingDash={Character=c,Time=now,Before=c:GetAttribute("LocalDashTime")};native.TryDash:Fire()
        elseif snapshot.CanBlock then setBlock(true)end
    else
        setBlock(false)
        if decision=="light"or decision=="heavy"or decision=="ultimate"then
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={workspace:FindFirstChild("Live")or c};params.RespectCanCollide=true
            if not workspace:Raycast(r.Position,delta,params)then requestPunch(decision,now)end
        end
    end
    S.Status=decision.." · "..target.Name..string.format(" · %.1f studs · %d%% stamina",distance,stamina*100)
end
local function setupNative()
    local folder=RS:FindFirstChild("MobileEvents");assert(folder,"Native action interfaces unavailable")
    local actions={}
    for _,name in ipairs({"TryPunch","TryDash","SetBlock","TrySwitchEquip"})do
        local event=folder:FindFirstChild(name);assert(event and event:IsA("BindableEvent"),"Native action changed: "..name);actions[name]=event
    end
    native=actions
    local modules=RS:FindFirstChild("Modules");assert(modules,"Combat modules unavailable")
    styles=require(modules:FindFirstChild("Styles"));phases=require(modules.Combat:FindFirstChild("AttackAnimationPhases"))
    broadcast=require(modules:FindFirstChild("BroadcastCamera"))
    local playerModule=LP.PlayerScripts:FindFirstChild("PlayerModule");assert(playerModule,"Native movement module unavailable")
    controls=require(playerModule):GetControls();originalMove=controls.GetMoveVector;rawMove=rawget(controls,"GetMoveVector")
    assert(type(originalMove)=="function","Native movement interface changed")
    moveShim=function(self,...)
        if not S.Enabled or not currentTarget or UIS:GetFocusedTextBox()then return originalMove(self,...)end
        local _,_,forcedOccupied=stateFor(LP.Name)
        local c=LP.Character
        if flag(forcedOccupied,"ForceMove")or c and(c:GetAttribute("Rooted")or c:GetAttribute("SpecialHoldRooted"))then return originalMove(self,...)end
        local desired=S.Desired
        local _,_,occupied=stateFor(LP.Name)
        local locked=value(occupied,"LockedOn")
        local x=broadcast.GetCombatMoveVector(Vector3.xAxis,locked)
        local z=broadcast.GetCombatMoveVector(Vector3.zAxis,locked)
        local det=x.X*z.Z-z.X*x.Z
        if math.abs(det)<.01 then return Vector3.zero end
        local vector=Vector3.new((desired.X*z.Z-desired.Z*z.X)/det,0,(x.X*desired.Z-x.Z*desired.X)/det)
        if flag(occupied,"ReverseInputs")then vector=-vector end
        return vector.Magnitude>1 and vector.Unit or vector
    end
    controls.GetMoveVector=moveShim
end
function S:SetEnabled(valueOn)
    if self.Destroyed then return end
    if valueOn~=true then
        self.Enabled=false;self.Generation+=1
        if connection then connection:Disconnect();connection=nil end
        pcall(setBlock,false);pcall(releasePunch);releaseTarget()
        if ownConnection then ownConnection:Disconnect();ownConnection=nil end
        ownBoundCharacter=nil;ownStyle=nil
        if controls and controls.GetMoveVector==moveShim then controls.GetMoveVector=rawMove end
        controls=nil;originalMove=nil;moveShim=nil;self.Status="Off";self.Desired=Vector3.zero
        return
    end
    if self.Enabled then return end
    local ok,err=pcall(setupNative)
    if not ok then self:SetEnabled(false);error(err,0)end
    self.Enabled=true;self.Generation+=1;blockCommand=nil;self.Status="Waiting for active match"
    local elapsed=0
    connection=Run.Heartbeat:Connect(function(dt)
        elapsed+=dt;if elapsed<.05 then return end;elapsed=0
        local started=os.clock();local ok,message=pcall(step)
        local ms=(os.clock()-started)*1000;self.MaxStepMs=math.max(self.MaxStepMs,ms)
        if not ok or ms>50 then
            self:SetEnabled(false);self.Status=not ok and("Stopped: "..tostring(message):sub(1,120))or"Stopped: timing guard"
            warn("[UBG Auto Combat] "..self.Status)
        end
    end)
end
function S:GetSnapshot()return {Version=self.Version,Enabled=self.Enabled,Status=self.Status,Attacks=self.Attacks,Dodges=self.Dodges,Blocks=self.Blocks,Decision=self.Decision,MaxStepMs=self.MaxStepMs,ConfirmedAttacks=self.ConfirmedAttacks,ConfirmedDodges=self.ConfirmedDodges,ConfirmedGuards=self.ConfirmedGuards,RejectedGuards=self.RejectedGuards,BlockedRoutes=self.BlockedRoutes}end
function S:Destroy()
    if self.Destroyed then return end;self:SetEnabled(false);self.Destroyed=true
    if env.__ALLEN_UBG_COMBAT==self then env.__ALLEN_UBG_COMBAT=nil end
end
env.__ALLEN_UBG_COMBAT=S
return S

]====],
AutoQTE=[====[
-- Native combat/struggle shrinking-ring QTEs. Starts OFF, hub switch only.
-- Does not synthesize keys, hook functions, change timing data or replay remotes.
local Policy=(function()
local Policy={}
function Policy.Phase(elapsed,duration)
    if type(elapsed)~="number" or type(duration)~="number" or elapsed~=elapsed or duration~=duration
        or duration<=0 or duration==math.huge then return "invalid" end
    local opens,closes=duration/2.15,duration/1.75
    if elapsed>=closes then return "expired" end
    if elapsed<(opens+closes)*.5 then return "wait" end
    return "hit"
end
return Policy

end)()
assert(game.GameId==7008097940,"Open Ink Game to use Auto QTE")
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local env=getgenv()
if env.__ALLEN_INK_AUTO_QTE then env.__ALLEN_INK_AUTO_QTE:Destroy()end
local State={HubOnly=true,Enabled=false,Destroyed=false,Hits=0,Skipped=0,Errors=0,Status="Off",Generation=0,
    Seen=setmetatable({},{__mode="k"})}
local native,connection
local function loadModule()
    local modules=RS:FindFirstChild("Modules")
    local script=modules and modules:FindFirstChild("HBGQTE")
    assert(script and script:IsA("ModuleScript"),"Native ring QTE module is unavailable")
    local module=require(script)
    assert(type(module)=="table" and type(module.ActiveButtons)=="table" and type(module.Pressed)=="function",
        "The native QTE interface changed")
    return module
end
local function visible(object)
    local pg=LP:FindFirstChildOfClass("PlayerGui")
    if typeof(object)~="Instance" or not object:IsA("GuiObject") or not pg or not object:IsDescendantOf(pg)then return false end
    local current=object
    while current and current~=pg do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current=current.Parent
    end
    return current==pg
end
local function valid(data)
    if type(data)~="table" or not visible(data.Inner) or not visible(data.Outer)then return false end
    if data.Outer:GetAttribute("PressedOnce") or data.Inner:GetAttribute("Failed") or data.Inner:GetAttribute("Tweening")then return false end
    local c=LP.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health<=0 or c:FindFirstChild("Dead")then return false end
    if data.Tag and (typeof(data.Tag)~="Instance" or data.Tag.Parent~=c)then return false end
    return true
end
function State:Step()
    if not self.Enabled or self.Destroyed then return end
    local active=0
    for key,data in pairs(native.ActiveButtons)do
        if type(data)=="table" and not self.Seen[data] and valid(data)then
            active+=1
            local phase=Policy.Phase(type(data.StartedAt)=="number" and tick()-data.StartedAt or nil,data.Duration)
            if phase=="hit"then
                self.Seen[data]=true
                local generation=self.Generation
                local character=LP.Character
                task.spawn(function()
                    if not self.Enabled or generation~=self.Generation or character~=LP.Character
                        or native.ActiveButtons[key]~=data or not valid(data)
                        or Policy.Phase(tick()-data.StartedAt,data.Duration)~="hit"then return end
                    local ok,err=pcall(native.Pressed,false,data)
                    if ok then
                        if data.Outer:GetAttribute("PressedOnce") and not data.Inner:GetAttribute("Failed")then self.Hits+=1 end
                    else
                        self.Errors+=1;self:SetEnabled(false)
                        self.Status="Stopped: "..tostring(err):sub(1,120)
                        warn("[Allen Auto QTE] "..tostring(err))
                    end
                end)
            elseif phase=="expired" or phase=="invalid"then
                self.Seen[data]=true;self.Skipped+=1
            end
        end
    end
    if self.Enabled then self.Status=active>0 and "Timing native ring prompt" or "Waiting for combat / struggle QTE"end
end
function State:SetEnabled(value)
    if self.Destroyed then return end
    value=value==true
    if self.Enabled==value then return end
    if value then native=loadModule()end
    self.Enabled=value;self.Generation+=1
    if connection then connection:Disconnect();connection=nil end
    self.Seen=setmetatable({},{__mode="k"})
    if value then
        self.Status="Waiting for combat / struggle QTE"
        connection=RunService.RenderStepped:Connect(function()
            local ok,err=pcall(self.Step,self)
            if not ok then self.Errors+=1;self:SetEnabled(false);self.Status="Stopped: "..tostring(err):sub(1,120);warn("[Allen Auto QTE] "..tostring(err))end
        end)
    else self.Status="Off"end
end
function State:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Hits=self.Hits,Skipped=self.Skipped,Errors=self.Errors}
end
function State:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true;native=nil
    if env.__ALLEN_INK_AUTO_QTE==self then env.__ALLEN_INK_AUTO_QTE=nil end
end
env.__ALLEN_INK_AUTO_QTE=State
return State

]====],
JumpRope=[====[
-- Jump Rope: learn the native pass phase, then request normal Humanoid jumps.
assert(game.GameId==7008097940,"Open Ink Game")
local LP=game:GetService("Players").LocalPlayer
local Run=game:GetService("RunService")
local env=getgenv()
if env.__ALLEN_JUMP_ROPE then env.__ALLEN_JUMP_ROPE:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Actions=0,Status="Off"}
local connection,passConnection,rope,lastAngle,lastAt,speed,targetAngle,lastJump
local function angle(cf)return math.atan2(cf.UpVector.Z,cf.UpVector.Y)end
local function wrap(x)return (x+math.pi)%(2*math.pi)-math.pi end
local function reset()
    if passConnection then passConnection:Disconnect();passConnection=nil end
    rope=nil;lastAngle=nil;lastAt=nil;speed=nil;targetAngle=nil;lastJump=nil
end
local function bind(candidate)
    reset();rope=candidate
    passConnection=rope.ChildAdded:Connect(function(child)
        if child.Name=="HitOff" then
            local cf=rope:GetAttribute("CurrentCF")
            if typeof(cf)=="CFrame"then targetAngle=angle(cf)end
        end
    end)
    if rope:FindFirstChild("HitOff")then local cf=rope:GetAttribute("CurrentCF");if typeof(cf)=="CFrame"then targetAngle=angle(cf)end end
end
local function step()
    local values=workspace:FindFirstChild("Values");local gameValue=values and values:FindFirstChild("CurrentGame")
    if not gameValue or gameValue.Value~="JumpRope"then reset();S.Status="Waiting for Jump Rope";return end
    if not rope or not rope:IsDescendantOf(workspace)then
        local effects=workspace:FindFirstChild("Effects")
        local candidate=effects and effects:FindFirstChild("rope")
        if not candidate or typeof(candidate:GetAttribute("CurrentCF"))~="CFrame"then S.Status="Waiting for native rope";return end
        bind(candidate)
    end
    local cf=rope:GetAttribute("CurrentCF");if typeof(cf)~="CFrame"then return end
    local now=os.clock();local a=angle(cf)
    if lastAt then
        local dt=now-lastAt
        if dt>0 and dt<.2 then
            local measured=wrap(a-lastAngle)/dt
            if math.abs(measured)>.03 and math.abs(measured)<30 then speed=speed and speed*.7+measured*.3 or measured end
        elseif dt>=.2 then speed=nil end
    end
    lastAngle=a;lastAt=now
    if not targetAngle then S.Status="Learning first pass · jump manually";return end
    if not speed or math.abs(speed)<.1 then S.Status="Waiting for rope rotation";return end
    local c=LP.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health<=0 or not c:GetAttribute("JumpRopeZone") or not c:FindFirstChild("PlayingJumpRope")then S.Status="Enter the rope zone · manual movement";return end
    if c:FindFirstChild("Ragdoll") or c:FindFirstChild("Stun") or c:FindFirstChild("NoCheckJumpRope")then S.Status="Waiting for recovery";return end
    local phase=(targetAngle-a)*(speed>0 and 1 or -1)%(2*math.pi)
    local untilPass=phase/math.abs(speed)
    if untilPass<=.22 and untilPass>=.025 and now-(lastJump or -math.huge)>.65
        and h.FloorMaterial~=Enum.Material.Air and h:GetStateEnabled(Enum.HumanoidStateType.Jumping)then
        h.Jump=true;lastJump=now;S.Actions+=1;S.Status="Normal jump requested"
    else S.Status="Tracking rope · "..S.Actions.." jumps"end
end
function S:SetEnabled(value)
    if self.Destroyed then return end
    self.Enabled=value==true
    if connection then connection:Disconnect();connection=nil end
    reset()
    if self.Enabled then connection=Run.Heartbeat:Connect(function()
        local ok,err=pcall(step)
        if not ok then self:SetEnabled(false);self.Status="Stopped: "..tostring(err):sub(1,100)end
    end)else self.Status="Off"end
end
function S:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Actions=self.Actions}end
function S:Destroy()if self.Destroyed then return end;self:SetEnabled(false);self.Destroyed=true;if env.__ALLEN_JUMP_ROPE==self then env.__ALLEN_JUMP_ROPE=nil end end
env.__ALLEN_JUMP_ROPE=S
return S

]====],
RopeUtils=[====[
return function(MODE)
-- Shared Jump Rope utilities. Local geometry does not override server decisions.
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local Run=game:GetService("RunService")
local env=getgenv()
local allowed={balance=true,bridge=true,antifall=true,fake=true,cutscene=true,disable=true,finish=true}
assert(game.GameId==7008097940 and allowed[MODE],"Unsupported Jump Rope feature")
local M=env.__ALLEN_ROPE_UTILS
if not M or M.Destroyed then
    M={Controllers={},Originals={},Seen=setmetatable({},{__mode="k"}),LastInput=0}
    env.__ALLEN_ROPE_UTILS=M
    local function on(mode)local s=M.Controllers[mode];return s and s.Enabled end
    local function restore(mode)
        local records=M.Originals[mode] or {}
        for object,props in pairs(records)do for name,value in pairs(props)do pcall(function()object[name]=value end)end end
        M.Originals[mode]=nil
    end
    local function set(mode,object,name,value)
        local records=M.Originals[mode] or {};M.Originals[mode]=records
        local props=records[object] or {};records[object]=props
        if props[name]==nil then props[name]=object[name]end
        object[name]=value
    end
    local function clear()
        if M.Pad then M.Pad:Destroy();M.Pad=nil end
        restore("disable");restore("fake")
        M.Map=nil;M.Safe=nil;M.Finished=nil;M.Seen=setmetatable({},{__mode="k"})
    end
    M.Clear=clear
    local function landing(map,name)
        local object=map:FindFirstChild(name,true)
        local part=object and (object:IsA("BasePart")and object or object:FindFirstChildWhichIsA("BasePart",true))
        if not part then return end
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={object}
        local result=workspace:Raycast(part.Position+Vector3.new(0,15,0),Vector3.new(0,-40,0),params)
        if result and result.Normal.Y>.85 and result.Instance.CanCollide then return result.Position end
    end
    function M:Step()
        local values=workspace:FindFirstChild("Values");local current=values and values:FindFirstChild("CurrentGame")
        local map=workspace:FindFirstChild("JumpRope")
        if not map or not current or current.Value~="JumpRope"then
            if self.Map then clear()end
            for _,s in pairs(self.Controllers)do if s.Enabled then s.Status="Waiting for Jump Rope"end end
            return
        end
        if self.Map~=map then clear();self.Map=map end
        local c=LP.Character;local h=c and c:FindFirstChildOfClass("Humanoid");local r=c and c:FindFirstChild("HumanoidRootPart")
        if not h or h.Health<=0 or not r then return end
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map}
        local floor=workspace:Raycast(r.Position,Vector3.new(0,-8,0),params)
        if floor and floor.Normal.Y>.8 and floor.Instance.CanCollide and not c:FindFirstChild("Ragdoll")then self.Safe={Character=c,Pivot=c:GetPivot(),FloorY=floor.Position.Y}end
        local protect=on("antifall") or on("cutscene") and workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable
        local safe=self.Safe
        if protect and safe and safe.Character==c and r.Position.Y<safe.FloorY-5 and not c:FindFirstChild("Ragdoll")then
            c:PivotTo(safe.Pivot);r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
        end
        if on("antifall")then self.Controllers.antifall.Status=safe and "Local last-ground recovery ready"or"Step onto solid ground to arm"end
        if on("cutscene")then self.Controllers.cutscene.Status="Local cutscene fall recovery · cannot prevent server death"end
        if on("bridge") or on("finish")then
            local start=landing(map,"Start") or landing(map,"StartingPlatform")
            local finish=landing(map,"End") or landing(map,"Finish") or landing(map,"FinishPlatform")
            if on("bridge")then
                if start and finish and (finish-start).Magnitude<600 and math.abs(start.Y-finish.Y)<15 then
                    if not self.Pad then local pad=Instance.new("Part");pad.Name="AllenRopeBridge";pad.Anchored=true;pad.CanTouch=false;pad.Transparency=.45;pad.Color=Color3.fromRGB(35,35,35);pad.Parent=workspace;self.Pad=pad end
                    local delta=finish-start;self.Pad.Size=Vector3.new(12,.6,delta.Magnitude)
                    self.Pad.CFrame=CFrame.lookAt((start+finish)/2-Vector3.new(0,.35,0),finish-Vector3.new(0,.35,0))
                    self.Controllers.bridge.Status="Local bridge · server hazards still apply"
                else self.Controllers.bridge.Status="Waiting for verified Start / End platforms"end
            end
            if on("finish")then
                if self.Finished==c then self.Controllers.finish.Status="Finish teleport attempted · server decides completion"
                elseif finish then c:PivotTo(CFrame.new(finish+Vector3.new(0,h.HipHeight+r.Size.Y/2+.2,0))*r.CFrame.Rotation);r.AssemblyLinearVelocity=Vector3.zero;self.Finished=c;self.Controllers.finish.Actions+=1
                else self.Controllers.finish.Status="Waiting for verified finish landing"end
            end
        end
        if not on("bridge")and self.Pad then self.Pad:Destroy();self.Pad=nil end
        if on("disable")then
            local effects=workspace:FindFirstChild("Effects");local rope=effects and effects:FindFirstChild("rope")
            if rope then for _,v in ipairs(rope:GetDescendants())do
                if v:IsA("BasePart")then set("disable",v,"LocalTransparencyModifier",1);set("disable",v,"CanTouch",false);set("disable",v,"CanCollide",false)end
            end end
            self.Controllers.disable.Status="Rope hidden / collision off locally · timing hazard remains"
        end
        if on("balance") or on("fake")then
            local pg=LP:FindFirstChildOfClass("PlayerGui");local frames=pg and pg:FindFirstChild("ImpactFrames")
            if frames then for _,ui in ipairs(frames:GetChildren())do
                local indicator=ui:FindFirstChild("Indicator");local warning=ui:FindFirstChild("WarningLabel")
                if indicator and warning and ui:IsA("GuiObject")and ui.Visible then
                    if on("balance") and not self.Seen[ui] and os.clock()-self.LastInput>.3 then
                        local sign=indicator.Rotation
                        if math.abs(sign)>.1 then
                            local code=sign>0 and Enum.KeyCode.A or Enum.KeyCode.D
                            if not game:GetService("UserInputService"):GetFocusedTextBox()then
                                local vim=game:GetService("VirtualInputManager")
                                vim:SendKeyEvent(true,code,false,game)
                                task.delay(.03,function()pcall(function()vim:SendKeyEvent(false,code,false,game)end)end)
                                self.Seen[ui]=true;self.LastInput=os.clock();self.Controllers.balance.Actions+=1
                            end
                        end
                    end
                    if on("fake")then set("fake",indicator,"Rotation",0);set("fake",indicator,"Position",UDim2.fromScale(.5,.5))end
                end
            end end
            if on("balance")then self.Controllers.balance.Status="Watching balance prompt · normal A/D input"end
            if on("fake")then self.Controllers.fake.Status="Cosmetic centered indicator · does not bypass balance"end
        end
    end
    M.Connection=Run.Heartbeat:Connect(function(dt)
        M.Elapsed=(M.Elapsed or 0)+dt;if M.Elapsed<.05 then return end;M.Elapsed=0
        local any=false;for _,s in pairs(M.Controllers)do if s.Enabled then any=true end end
        if not any then return end
        local ok,err=pcall(M.Step,M)
        if not ok then for _,s in pairs(M.Controllers)do s.Enabled=false;s.Status="Stopped: "..tostring(err):sub(1,100)end;clear()end
    end)
    function M:Create(mode)
        local key="__ALLEN_ROPE_"..mode
        if self.Controllers[mode]then self.Controllers[mode]:Destroy()end
        local s={HubOnly=true,Enabled=false,Destroyed=false,Actions=0,Status="Off"}
        function s:SetEnabled(value)
            if self.Destroyed then return end;self.Enabled=value==true
            if mode=="finish"then M.Finished=nil end
            if not self.Enabled then restore(mode);if mode=="bridge"and M.Pad then M.Pad:Destroy();M.Pad=nil end end
            self.Status=self.Enabled and "Waiting for Jump Rope"or"Off"
        end
        function s:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Actions=self.Actions}end
        function s:Destroy()
            if self.Destroyed then return end;self:SetEnabled(false);self.Destroyed=true;M.Controllers[mode]=nil
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers)then clear();M.Connection:Disconnect();M.Destroyed=true;if env.__ALLEN_ROPE_UTILS==M then env.__ALLEN_ROPE_UTILS=nil end end
        end
        self.Controllers[mode]=s;env[key]=s;return s
    end
end
return M:Create(MODE)

end
]====],
DalgonaAuto=[====[
local MODE="auto"
-- Headless Dalgona controls. MODE is supplied by the hub build.
-- Uses the validated native Dalgona frame; no remote hooks or input injection.
assert(game.GameId==7008097940,"Open Ink Game to use Dalgona")
assert(type(getconnections)=="function" and debug and type(debug.getupvalues)=="function"
    and type(debug.setupvalue)=="function" and type(debug.info)=="function",
    "Dalgona requires connection and upvalue APIs supported by this executor")
local env=getgenv()
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local RunService=game:GetService("RunService")
local M=env.__ALLEN_DALGONA_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Context=nil,NextScan=0,Destroyed=false}
    env.__ALLEN_DALGONA_MANAGER=M
    local I={Cookie=3,Outline=6,Player=9,LighterReady=11,LighterModel=12,LighterViewport=13,
        LighterCamera=14,OpenTrack=20,CloseTrack=22,Flame=23,LighterGeneration=24,
        LighterOpen=25,Character=27,Progress=35,Total=36,Allowance=37,Finishing=39,
        Cracks=40,CrackFunction=41,Completed=42,Remote=45,CloseLighter=65,Guard=79}
    local function is(value,class)
        return typeof(value)=="Instance" and value:IsA(class)
    end
    local function enabled(mode)
        local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed
    end
    local function active()
        local c=LP.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="Dalgona" and h and h.Health>0 and not c:FindFirstChild("Dead")
    end
    local function write(context,index,value)
        debug.setupvalue(context.Function,index,value)
    end
    local function valid(context)
        return context and context.Connection.Connected~=false and context.Cookie.Parent and context.Outline.Parent
            and context.Character==LP.Character
    end
    local function releaseGuard(context)
        if context and context.GuardOwned then
            local ok,u=pcall(debug.getupvalues,context.Function)
            if ok and u[I.Guard]==true then pcall(write,context,I.Guard,context.OriginalGuard) end
            context.GuardOwned=false
        end
    end
    local function releaseLighter(context)
        if M.LighterSet then
            if LP:GetAttribute("HasLighter")==true then LP:SetAttribute("HasLighter",M.OriginalLighter) end
            M.LighterSet=false;M.OriginalLighter=nil
        end
        if not context or not context.LighterOwned then return end
        context.LighterOwned=false
        -- Invalidate native animation timers before clearing our temporary lighter.
        local u=debug.getupvalues(context.Function)
        write(context,I.LighterGeneration,(u[I.LighterGeneration] or 0)+2)
        write(context,I.LighterOpen,nil)
        local close=u[I.CloseLighter]
        if type(close)=="function" then
            local values=debug.getupvalues(close)
            local sound=values[8] -- u62, validated against the native close-lighter closure.
            if is(sound,"Sound") then sound:Stop();sound:Destroy();debug.setupvalue(close,8,nil) end
        end
        for _,index in ipairs({I.OpenTrack,I.CloseTrack}) do
            local track=u[index]
            if is(track,"AnimationTrack") then track:Stop(0);track:Destroy() end
            write(context,index,nil)
        end
        for _,index in ipairs({I.LighterModel,I.LighterViewport,I.LighterCamera,I.Flame}) do
            local object=u[index]
            if typeof(object)=="Instance" then object:Destroy() end
            write(context,index,nil)
        end
        write(context,I.LighterReady,nil)
    end
    function M:DropContext()
        local context=self.Context
        pcall(releaseGuard,context);pcall(releaseLighter,context)
        self.Context=nil
    end
    local function scan()
        for _,connection in ipairs(getconnections(RunService.RenderStepped)) do
            local f=connection.Function
            if type(f)=="function" and connection.Connected~=false then
                local ok,source=pcall(debug.info,f,"s")
                if ok and tostring(source):find("DalgonaClient",1,true) then
                    local success,u=pcall(debug.getupvalues,f)
                    if success and is(u[I.Cookie],"Model") and is(u[I.Outline],"Model")
                        and u[I.Outline].Name==u[I.Cookie].Name.."Outline" and u[I.Player]==LP
                        and u[I.Character]==LP.Character and is(u[I.Remote],"RemoteEvent")
                        and type(u[I.Progress])=="number" and type(u[I.Total])=="number"
                        and u[I.Total]>0 and u[I.Progress]>=0 and u[I.Progress]<=u[I.Total]
                        and type(u[I.Allowance])=="number" and type(u[I.CrackFunction])=="function"
                        and type(u[I.CloseLighter])=="function" and type(u[I.LighterGeneration])=="number" then
                        local crack=debug.getupvalues(u[I.CrackFunction])
                        -- A second closure validates the same outline, cookie, crack counter and remote.
                        if crack[15]==u[I.Cookie] and crack[18]==u[I.Outline] and crack[10]==u[I.Remote]
                            and crack[4]==u[I.Cracks] then
                            return {Function=f,Connection=connection,Cookie=u[I.Cookie],Outline=u[I.Outline],
                                Character=u[I.Character],Shape=u[I.Cookie].Name,BoundAt=os.clock(),
                                Fear=is(crack[5],"NumberValue") and crack[5] or nil,AutoSubmitted=false}
                        end
                    end
                end
            end
        end
    end
    function M:Step()
        if not (enabled("auto") or enabled("lighter") or enabled("anticrack")) or not active() then
            if self.Context or self.LighterSet then self:DropContext() end
            for _,c in pairs(self.Controllers) do if c.Enabled then c.Status="Waiting for Dalgona" end end
            return
        end
        if not valid(self.Context) then
            self:DropContext()
            if os.clock()<self.NextScan then return end
            self.NextScan=os.clock()+.5;self.Context=scan()
        end
        local context=self.Context
        if not context then
            for _,c in pairs(self.Controllers) do if c.Enabled then c.Status="Waiting for native cookie controller" end end
            return
        end
        local u=debug.getupvalues(context.Function)
        if enabled("anticrack") then
            if not context.GuardOwned then context.OriginalGuard=u[I.Guard];context.GuardOwned=true end
            write(context,I.Guard,true)
            if context.Fear and context.Fear.Value~=0 then context.Fear.Value=0 end
            self.Controllers.anticrack.Status="Wrong-click protection · "..context.Shape
        else releaseGuard(context) end
        if enabled("lighter") then
            if not self.LighterSet then
                self.OriginalLighter=LP:GetAttribute("HasLighter");self.LighterSet=true
                context.LighterOwned=not u[I.LighterReady] and self.OriginalLighter~=true
                LP:SetAttribute("HasLighter",true)
            end
            self.Controllers.lighter.Status=u[I.LighterReady] and "Native lighter ready · hold to use" or "Enabling native lighter"
        elseif self.LighterSet then releaseLighter(context) end
        if enabled("auto") then
            local c=self.Controllers.auto
            local remaining=workspace:GetAttribute("CurrentGameTime")
            if u[I.Finishing] or u[I.Completed] then
                c.Status=context.AutoSubmitted and "Native completion triggered · awaiting server result" or "Cookie already finished"
            elseif type(remaining)=="number" and remaining<=0 then
                c.Status="Dalgona timer ended"
            elseif not context.AutoSubmitted and os.clock()-context.BoundAt>=.35 then
                -- The game's next frame performs its own Completed request, visuals and cleanup.
                write(context,I.Progress,u[I.Total])
                context.AutoSubmitted=true;c.Requests+=1
                c.Status="Completing "..context.Shape
            end
        end
    end
    local elapsed=0
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        elapsed+=dt;if elapsed<.05 then return end;elapsed=0
        local ok,err=pcall(M.Step,M)
        if not ok then
            for _,c in pairs(M.Controllers) do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,120) end
            M:DropContext();warn("[Allen Dalgona] "..tostring(err))
        end
    end)
    function M:Create(mode)
        local key="__ALLEN_DALGONA_"..mode
        if self.Controllers[mode] then
            self.Controllers[mode]:SetEnabled(false)
            self.Controllers[mode].Destroyed=true
        end
        local c={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Requests=0}
        function c:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if not self.Enabled then
                if mode=="anticrack" then releaseGuard(M.Context) end
                if mode=="lighter" then releaseLighter(M.Context) end
                self.Status="Off"
            else self.Status="Waiting for Dalgona";M.NextScan=0;M:Step() end
        end
        function c:GetSnapshot() return {Enabled=self.Enabled,Status=self.Status,Requests=self.Requests} end
        function c:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers) then
                M:DropContext();M.Destroyed=true;M.Connection:Disconnect()
                if env.__ALLEN_DALGONA_MANAGER==M then env.__ALLEN_DALGONA_MANAGER=nil end
            end
        end
        self.Controllers[mode]=c;env[key]=c
        return c
    end
end
return M:Create(MODE)

]====],
DalgonaLighter=[====[
local MODE="lighter"
-- Headless Dalgona controls. MODE is supplied by the hub build.
-- Uses the validated native Dalgona frame; no remote hooks or input injection.
assert(game.GameId==7008097940,"Open Ink Game to use Dalgona")
assert(type(getconnections)=="function" and debug and type(debug.getupvalues)=="function"
    and type(debug.setupvalue)=="function" and type(debug.info)=="function",
    "Dalgona requires connection and upvalue APIs supported by this executor")
local env=getgenv()
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local RunService=game:GetService("RunService")
local M=env.__ALLEN_DALGONA_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Context=nil,NextScan=0,Destroyed=false}
    env.__ALLEN_DALGONA_MANAGER=M
    local I={Cookie=3,Outline=6,Player=9,LighterReady=11,LighterModel=12,LighterViewport=13,
        LighterCamera=14,OpenTrack=20,CloseTrack=22,Flame=23,LighterGeneration=24,
        LighterOpen=25,Character=27,Progress=35,Total=36,Allowance=37,Finishing=39,
        Cracks=40,CrackFunction=41,Completed=42,Remote=45,CloseLighter=65,Guard=79}
    local function is(value,class)
        return typeof(value)=="Instance" and value:IsA(class)
    end
    local function enabled(mode)
        local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed
    end
    local function active()
        local c=LP.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="Dalgona" and h and h.Health>0 and not c:FindFirstChild("Dead")
    end
    local function write(context,index,value)
        debug.setupvalue(context.Function,index,value)
    end
    local function valid(context)
        return context and context.Connection.Connected~=false and context.Cookie.Parent and context.Outline.Parent
            and context.Character==LP.Character
    end
    local function releaseGuard(context)
        if context and context.GuardOwned then
            local ok,u=pcall(debug.getupvalues,context.Function)
            if ok and u[I.Guard]==true then pcall(write,context,I.Guard,context.OriginalGuard) end
            context.GuardOwned=false
        end
    end
    local function releaseLighter(context)
        if M.LighterSet then
            if LP:GetAttribute("HasLighter")==true then LP:SetAttribute("HasLighter",M.OriginalLighter) end
            M.LighterSet=false;M.OriginalLighter=nil
        end
        if not context or not context.LighterOwned then return end
        context.LighterOwned=false
        -- Invalidate native animation timers before clearing our temporary lighter.
        local u=debug.getupvalues(context.Function)
        write(context,I.LighterGeneration,(u[I.LighterGeneration] or 0)+2)
        write(context,I.LighterOpen,nil)
        local close=u[I.CloseLighter]
        if type(close)=="function" then
            local values=debug.getupvalues(close)
            local sound=values[8] -- u62, validated against the native close-lighter closure.
            if is(sound,"Sound") then sound:Stop();sound:Destroy();debug.setupvalue(close,8,nil) end
        end
        for _,index in ipairs({I.OpenTrack,I.CloseTrack}) do
            local track=u[index]
            if is(track,"AnimationTrack") then track:Stop(0);track:Destroy() end
            write(context,index,nil)
        end
        for _,index in ipairs({I.LighterModel,I.LighterViewport,I.LighterCamera,I.Flame}) do
            local object=u[index]
            if typeof(object)=="Instance" then object:Destroy() end
            write(context,index,nil)
        end
        write(context,I.LighterReady,nil)
    end
    function M:DropContext()
        local context=self.Context
        pcall(releaseGuard,context);pcall(releaseLighter,context)
        self.Context=nil
    end
    local function scan()
        for _,connection in ipairs(getconnections(RunService.RenderStepped)) do
            local f=connection.Function
            if type(f)=="function" and connection.Connected~=false then
                local ok,source=pcall(debug.info,f,"s")
                if ok and tostring(source):find("DalgonaClient",1,true) then
                    local success,u=pcall(debug.getupvalues,f)
                    if success and is(u[I.Cookie],"Model") and is(u[I.Outline],"Model")
                        and u[I.Outline].Name==u[I.Cookie].Name.."Outline" and u[I.Player]==LP
                        and u[I.Character]==LP.Character and is(u[I.Remote],"RemoteEvent")
                        and type(u[I.Progress])=="number" and type(u[I.Total])=="number"
                        and u[I.Total]>0 and u[I.Progress]>=0 and u[I.Progress]<=u[I.Total]
                        and type(u[I.Allowance])=="number" and type(u[I.CrackFunction])=="function"
                        and type(u[I.CloseLighter])=="function" and type(u[I.LighterGeneration])=="number" then
                        local crack=debug.getupvalues(u[I.CrackFunction])
                        -- A second closure validates the same outline, cookie, crack counter and remote.
                        if crack[15]==u[I.Cookie] and crack[18]==u[I.Outline] and crack[10]==u[I.Remote]
                            and crack[4]==u[I.Cracks] then
                            return {Function=f,Connection=connection,Cookie=u[I.Cookie],Outline=u[I.Outline],
                                Character=u[I.Character],Shape=u[I.Cookie].Name,BoundAt=os.clock(),
                                Fear=is(crack[5],"NumberValue") and crack[5] or nil,AutoSubmitted=false}
                        end
                    end
                end
            end
        end
    end
    function M:Step()
        if not (enabled("auto") or enabled("lighter") or enabled("anticrack")) or not active() then
            if self.Context or self.LighterSet then self:DropContext() end
            for _,c in pairs(self.Controllers) do if c.Enabled then c.Status="Waiting for Dalgona" end end
            return
        end
        if not valid(self.Context) then
            self:DropContext()
            if os.clock()<self.NextScan then return end
            self.NextScan=os.clock()+.5;self.Context=scan()
        end
        local context=self.Context
        if not context then
            for _,c in pairs(self.Controllers) do if c.Enabled then c.Status="Waiting for native cookie controller" end end
            return
        end
        local u=debug.getupvalues(context.Function)
        if enabled("anticrack") then
            if not context.GuardOwned then context.OriginalGuard=u[I.Guard];context.GuardOwned=true end
            write(context,I.Guard,true)
            if context.Fear and context.Fear.Value~=0 then context.Fear.Value=0 end
            self.Controllers.anticrack.Status="Wrong-click protection · "..context.Shape
        else releaseGuard(context) end
        if enabled("lighter") then
            if not self.LighterSet then
                self.OriginalLighter=LP:GetAttribute("HasLighter");self.LighterSet=true
                context.LighterOwned=not u[I.LighterReady] and self.OriginalLighter~=true
                LP:SetAttribute("HasLighter",true)
            end
            self.Controllers.lighter.Status=u[I.LighterReady] and "Native lighter ready · hold to use" or "Enabling native lighter"
        elseif self.LighterSet then releaseLighter(context) end
        if enabled("auto") then
            local c=self.Controllers.auto
            local remaining=workspace:GetAttribute("CurrentGameTime")
            if u[I.Finishing] or u[I.Completed] then
                c.Status=context.AutoSubmitted and "Native completion triggered · awaiting server result" or "Cookie already finished"
            elseif type(remaining)=="number" and remaining<=0 then
                c.Status="Dalgona timer ended"
            elseif not context.AutoSubmitted and os.clock()-context.BoundAt>=.35 then
                -- The game's next frame performs its own Completed request, visuals and cleanup.
                write(context,I.Progress,u[I.Total])
                context.AutoSubmitted=true;c.Requests+=1
                c.Status="Completing "..context.Shape
            end
        end
    end
    local elapsed=0
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        elapsed+=dt;if elapsed<.05 then return end;elapsed=0
        local ok,err=pcall(M.Step,M)
        if not ok then
            for _,c in pairs(M.Controllers) do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,120) end
            M:DropContext();warn("[Allen Dalgona] "..tostring(err))
        end
    end)
    function M:Create(mode)
        local key="__ALLEN_DALGONA_"..mode
        if self.Controllers[mode] then
            self.Controllers[mode]:SetEnabled(false)
            self.Controllers[mode].Destroyed=true
        end
        local c={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Requests=0}
        function c:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if not self.Enabled then
                if mode=="anticrack" then releaseGuard(M.Context) end
                if mode=="lighter" then releaseLighter(M.Context) end
                self.Status="Off"
            else self.Status="Waiting for Dalgona";M.NextScan=0;M:Step() end
        end
        function c:GetSnapshot() return {Enabled=self.Enabled,Status=self.Status,Requests=self.Requests} end
        function c:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers) then
                M:DropContext();M.Destroyed=true;M.Connection:Disconnect()
                if env.__ALLEN_DALGONA_MANAGER==M then env.__ALLEN_DALGONA_MANAGER=nil end
            end
        end
        self.Controllers[mode]=c;env[key]=c
        return c
    end
end
return M:Create(MODE)

]====],
DalgonaAntiCrack=[====[
local MODE="anticrack"
-- Headless Dalgona controls. MODE is supplied by the hub build.
-- Uses the validated native Dalgona frame; no remote hooks or input injection.
assert(game.GameId==7008097940,"Open Ink Game to use Dalgona")
assert(type(getconnections)=="function" and debug and type(debug.getupvalues)=="function"
    and type(debug.setupvalue)=="function" and type(debug.info)=="function",
    "Dalgona requires connection and upvalue APIs supported by this executor")
local env=getgenv()
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local RunService=game:GetService("RunService")
local M=env.__ALLEN_DALGONA_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Context=nil,NextScan=0,Destroyed=false}
    env.__ALLEN_DALGONA_MANAGER=M
    local I={Cookie=3,Outline=6,Player=9,LighterReady=11,LighterModel=12,LighterViewport=13,
        LighterCamera=14,OpenTrack=20,CloseTrack=22,Flame=23,LighterGeneration=24,
        LighterOpen=25,Character=27,Progress=35,Total=36,Allowance=37,Finishing=39,
        Cracks=40,CrackFunction=41,Completed=42,Remote=45,CloseLighter=65,Guard=79}
    local function is(value,class)
        return typeof(value)=="Instance" and value:IsA(class)
    end
    local function enabled(mode)
        local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed
    end
    local function active()
        local c=LP.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="Dalgona" and h and h.Health>0 and not c:FindFirstChild("Dead")
    end
    local function write(context,index,value)
        debug.setupvalue(context.Function,index,value)
    end
    local function valid(context)
        return context and context.Connection.Connected~=false and context.Cookie.Parent and context.Outline.Parent
            and context.Character==LP.Character
    end
    local function releaseGuard(context)
        if context and context.GuardOwned then
            local ok,u=pcall(debug.getupvalues,context.Function)
            if ok and u[I.Guard]==true then pcall(write,context,I.Guard,context.OriginalGuard) end
            context.GuardOwned=false
        end
    end
    local function releaseLighter(context)
        if M.LighterSet then
            if LP:GetAttribute("HasLighter")==true then LP:SetAttribute("HasLighter",M.OriginalLighter) end
            M.LighterSet=false;M.OriginalLighter=nil
        end
        if not context or not context.LighterOwned then return end
        context.LighterOwned=false
        -- Invalidate native animation timers before clearing our temporary lighter.
        local u=debug.getupvalues(context.Function)
        write(context,I.LighterGeneration,(u[I.LighterGeneration] or 0)+2)
        write(context,I.LighterOpen,nil)
        local close=u[I.CloseLighter]
        if type(close)=="function" then
            local values=debug.getupvalues(close)
            local sound=values[8] -- u62, validated against the native close-lighter closure.
            if is(sound,"Sound") then sound:Stop();sound:Destroy();debug.setupvalue(close,8,nil) end
        end
        for _,index in ipairs({I.OpenTrack,I.CloseTrack}) do
            local track=u[index]
            if is(track,"AnimationTrack") then track:Stop(0);track:Destroy() end
            write(context,index,nil)
        end
        for _,index in ipairs({I.LighterModel,I.LighterViewport,I.LighterCamera,I.Flame}) do
            local object=u[index]
            if typeof(object)=="Instance" then object:Destroy() end
            write(context,index,nil)
        end
        write(context,I.LighterReady,nil)
    end
    function M:DropContext()
        local context=self.Context
        pcall(releaseGuard,context);pcall(releaseLighter,context)
        self.Context=nil
    end
    local function scan()
        for _,connection in ipairs(getconnections(RunService.RenderStepped)) do
            local f=connection.Function
            if type(f)=="function" and connection.Connected~=false then
                local ok,source=pcall(debug.info,f,"s")
                if ok and tostring(source):find("DalgonaClient",1,true) then
                    local success,u=pcall(debug.getupvalues,f)
                    if success and is(u[I.Cookie],"Model") and is(u[I.Outline],"Model")
                        and u[I.Outline].Name==u[I.Cookie].Name.."Outline" and u[I.Player]==LP
                        and u[I.Character]==LP.Character and is(u[I.Remote],"RemoteEvent")
                        and type(u[I.Progress])=="number" and type(u[I.Total])=="number"
                        and u[I.Total]>0 and u[I.Progress]>=0 and u[I.Progress]<=u[I.Total]
                        and type(u[I.Allowance])=="number" and type(u[I.CrackFunction])=="function"
                        and type(u[I.CloseLighter])=="function" and type(u[I.LighterGeneration])=="number" then
                        local crack=debug.getupvalues(u[I.CrackFunction])
                        -- A second closure validates the same outline, cookie, crack counter and remote.
                        if crack[15]==u[I.Cookie] and crack[18]==u[I.Outline] and crack[10]==u[I.Remote]
                            and crack[4]==u[I.Cracks] then
                            return {Function=f,Connection=connection,Cookie=u[I.Cookie],Outline=u[I.Outline],
                                Character=u[I.Character],Shape=u[I.Cookie].Name,BoundAt=os.clock(),
                                Fear=is(crack[5],"NumberValue") and crack[5] or nil,AutoSubmitted=false}
                        end
                    end
                end
            end
        end
    end
    function M:Step()
        if not (enabled("auto") or enabled("lighter") or enabled("anticrack")) or not active() then
            if self.Context or self.LighterSet then self:DropContext() end
            for _,c in pairs(self.Controllers) do if c.Enabled then c.Status="Waiting for Dalgona" end end
            return
        end
        if not valid(self.Context) then
            self:DropContext()
            if os.clock()<self.NextScan then return end
            self.NextScan=os.clock()+.5;self.Context=scan()
        end
        local context=self.Context
        if not context then
            for _,c in pairs(self.Controllers) do if c.Enabled then c.Status="Waiting for native cookie controller" end end
            return
        end
        local u=debug.getupvalues(context.Function)
        if enabled("anticrack") then
            if not context.GuardOwned then context.OriginalGuard=u[I.Guard];context.GuardOwned=true end
            write(context,I.Guard,true)
            if context.Fear and context.Fear.Value~=0 then context.Fear.Value=0 end
            self.Controllers.anticrack.Status="Wrong-click protection · "..context.Shape
        else releaseGuard(context) end
        if enabled("lighter") then
            if not self.LighterSet then
                self.OriginalLighter=LP:GetAttribute("HasLighter");self.LighterSet=true
                context.LighterOwned=not u[I.LighterReady] and self.OriginalLighter~=true
                LP:SetAttribute("HasLighter",true)
            end
            self.Controllers.lighter.Status=u[I.LighterReady] and "Native lighter ready · hold to use" or "Enabling native lighter"
        elseif self.LighterSet then releaseLighter(context) end
        if enabled("auto") then
            local c=self.Controllers.auto
            local remaining=workspace:GetAttribute("CurrentGameTime")
            if u[I.Finishing] or u[I.Completed] then
                c.Status=context.AutoSubmitted and "Native completion triggered · awaiting server result" or "Cookie already finished"
            elseif type(remaining)=="number" and remaining<=0 then
                c.Status="Dalgona timer ended"
            elseif not context.AutoSubmitted and os.clock()-context.BoundAt>=.35 then
                -- The game's next frame performs its own Completed request, visuals and cleanup.
                write(context,I.Progress,u[I.Total])
                context.AutoSubmitted=true;c.Requests+=1
                c.Status="Completing "..context.Shape
            end
        end
    end
    local elapsed=0
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        elapsed+=dt;if elapsed<.05 then return end;elapsed=0
        local ok,err=pcall(M.Step,M)
        if not ok then
            for _,c in pairs(M.Controllers) do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,120) end
            M:DropContext();warn("[Allen Dalgona] "..tostring(err))
        end
    end)
    function M:Create(mode)
        local key="__ALLEN_DALGONA_"..mode
        if self.Controllers[mode] then
            self.Controllers[mode]:SetEnabled(false)
            self.Controllers[mode].Destroyed=true
        end
        local c={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Requests=0}
        function c:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if not self.Enabled then
                if mode=="anticrack" then releaseGuard(M.Context) end
                if mode=="lighter" then releaseLighter(M.Context) end
                self.Status="Off"
            else self.Status="Waiting for Dalgona";M.NextScan=0;M:Step() end
        end
        function c:GetSnapshot() return {Enabled=self.Enabled,Status=self.Status,Requests=self.Requests} end
        function c:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers) then
                M:DropContext();M.Destroyed=true;M.Connection:Disconnect()
                if env.__ALLEN_DALGONA_MANAGER==M then env.__ALLEN_DALGONA_MANAGER=nil end
            end
        end
        self.Controllers[mode]=c;env[key]=c
        return c
    end
end
return M:Create(MODE)

]====],
GlassFinish=[====[
local MODE="finish"
-- Independent headless Glass Bridge switches. MODE is supplied by the hub build.
-- Geometry is local; original glass attributes and native connections are untouched.
assert(game.GameId==7008097940,"Open Ink Game to use Glass Bridge")
local LP=game:GetService("Players").LocalPlayer
local RunService=game:GetService("RunService")
local env=getgenv()
local M=env.__ALLEN_GLASS_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Records={},Rows={},Map=nil,Holder=nil,Folder=nil,Destroyed=false,Elapsed=0}
    env.__ALLEN_GLASS_MANAGER=M
    local function enabled(mode)local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed end
    local function character()
        local c=LP.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and h.Health>0 and not c:FindFirstChild("Dead") then return c,h,r end
    end
    local function active()
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="GlassBridge" and not workspace:GetAttribute("GLASSBRIDGEOVER")
    end
    local function remove(record,key)
        if record[key] then record[key]:Destroy();record[key]=nil end
    end
    function M:Reset()
        if self.Folder then self.Folder:Destroy() end
        self.Folder=nil;self.Map=nil;self.Holder=nil;self.Floor=nil;self.Geometry=nil
        self.LastSafe=nil;self.LastCharacter=nil;self.Teleported=nil
        table.clear(self.Records);table.clear(self.Rows)
    end
    local function collisionPart(name,size,cf,parent)
        local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf
        p.Anchored=true;p.CanCollide=true;p.CanTouch=false;p.CanQuery=false
        p.Transparency=1;p.CastShadow=false;p.Locked=true;p.Parent=parent
        return p
    end
    function M:Scan()
        local rows={}
        for _,row in ipairs(self.Holder:GetChildren()) do
            local index=tonumber(row.Name:match("^ClonedPanel(%d+)$"))
            if index then
                local sum=Vector3.zero;local count=0
                for _,model in ipairs(row:GetChildren())do
                    local part=model:IsA("Model") and model.PrimaryPart
                    if part and part:IsA("BasePart") and part.Name=="glasspart" then
                        local record=self.Records[part]
                        if not record then
                            record={Part=part,Model=model,CFrame=part.CFrame,Size=part.Size,Row=index}
                            self.Records[part]=record
                        end
                        record.Fake=part:GetAttribute("exploitingisevil")==true
                        sum+=record.CFrame.Position;count+=1
                    end
                end
                if count>0 then rows[#rows+1]={Index=index,Center=sum/count} end
            end
        end
        table.sort(rows,function(a,b)return a.Index<b.Index end)
        self.Rows=rows
        if #rows<2 then return end
        local first,last=rows[1].Center,rows[#rows].Center
        local delta=Vector3.new(last.X-first.X,0,last.Z-first.Z)
        if delta.Magnitude<5 then return end
        local direction=delta.Unit
        local right=direction:Cross(Vector3.yAxis)
        local center=(first+last)*.5
        local width,minY,maxY=0,math.huge,-math.huge
        for _,record in pairs(self.Records)do
            local p=record.CFrame.Position
            local half=math.abs(record.CFrame.RightVector:Dot(right))*record.Size.X*.5
                +math.abs(record.CFrame.LookVector:Dot(right))*record.Size.Z*.5
            width=math.max(width,math.abs((p-center):Dot(right))+half)
            local top=p.Y+record.Size.Y*.5
            minY=math.min(minY,top);maxY=math.max(maxY,top)
        end
        local spacing=delta.Magnitude/math.max(1,rows[#rows].Index-rows[1].Index)
        self.Geometry={Direction=direction,Right=right,Center=center,SurfaceY=minY,MaxY=maxY,
            Width=width*2+8,Length=delta.Magnitude+spacing*2,Spacing=spacing,Last=last}
    end
    function M:FindFinish()
        local g=self.Geometry;local finish=self.Map and self.Map:FindFirstChild("End")
        if not g or not finish or not finish:IsA("Model") then return nil,"Waiting for native End platform" end
        local cf=finish:GetBoundingBox()
        local center=cf.Position
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={finish};params.IgnoreWater=true
        local _,h,r=character();if not r then return nil,"Waiting for character" end
        for _,forward in ipairs({0,-g.Spacing*.5,g.Spacing*.5,g.Spacing})do
            for _,side in ipairs({0,g.Width*.2,-g.Width*.2})do
                local p=center+g.Direction*forward+g.Right*side
                local hit=workspace:Raycast(Vector3.new(p.X,g.SurfaceY+12,p.Z),Vector3.new(0,-30,0),params)
                if hit and hit.Normal.Y>=.85 and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
                    and math.min(hit.Instance.Size.X,hit.Instance.Size.Z)>=4
                    and math.abs(hit.Position.Y-g.SurfaceY)<3 then
                    local height=math.max(3,h.HipHeight+r.Size.Y*.5)+.3
                    local point=hit.Position+Vector3.new(0,height,0)
                    return CFrame.lookAt(point,point+g.Direction),"Native End platform"
                end
            end
        end
        return nil,"No solid landing found on End platform"
    end
    function M:VisualsAndPads()
        local fake,safe,pads=0,0,0
        for _,record in pairs(self.Records)do
            if record.Fake then fake+=1 else safe+=1 end
            if enabled("reveal") and record.Model:IsDescendantOf(self.Holder) then
                if not record.Highlight then
                    local h=Instance.new("Highlight");h.Name="GlassMarker";h.Adornee=record.Model
                    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.FillTransparency=.55;h.OutlineTransparency=0
                    h.Parent=self.Folder;record.Highlight=h
                end
                local color=record.Fake and Color3.fromRGB(255,65,75) or Color3.fromRGB(65,235,125)
                record.Highlight.FillColor=color;record.Highlight.OutlineColor=color
            else remove(record,"Highlight")end
            if enabled("walkfake") and record.Fake then
                if not record.Pad then
                    record.Pad=collisionPart("FakeGlassSupport",Vector3.new(record.Size.X+.2,.25,record.Size.Z+.2),
                        record.CFrame*CFrame.new(0,record.Size.Y*.5+.4,0),self.Folder)
                end
                pads+=1
            else remove(record,"Pad")end
        end
        if enabled("reveal") then self.Controllers.reveal.Status="Green: safe "..safe.." · red: fake "..fake end
        if enabled("walkfake") then self.Controllers.walkfake.Status="Local fake-glass supports: "..pads end
    end
    function M:CatchFloor()
        local g=self.Geometry
        if enabled("antifall") and g and g.MaxY-g.SurfaceY<2 then
            if not self.Floor then
                local center=Vector3.new(g.Center.X,g.SurfaceY-.6,g.Center.Z)
                self.Floor=collisionPart("BridgeCatchFloor",Vector3.new(g.Width,.4,g.Length),
                    CFrame.lookAt(center,center+g.Direction),self.Folder)
            end
            self.Controllers.antifall.Status="Local catch floor active"
        else
            if self.Floor then self.Floor:Destroy();self.Floor=nil end
            if enabled("antifall") then self.Controllers.antifall.Status="Waiting for flat bridge geometry" end
        end
    end
    function M:Recover()
        if not enabled("antifall") or not self.Geometry then return end
        local c,h,r=character();if not r then return end
        if self.LastCharacter~=c then self.LastCharacter=c;self.LastSafe=nil end
        if c:FindFirstChild("Ragdoll") then return end
        local g=self.Geometry
        local relative=CFrame.lookAt(g.Center,g.Center+g.Direction):PointToObjectSpace(r.Position)
        if math.abs(relative.X)>g.Width*.5+8 or math.abs(relative.Z)>g.Length*.5+8 then return end
        if r.Position.Y<g.SurfaceY-2 and self.LastSafe and os.clock()-(self.LastRecovery or 0)>.5 then
            self.LastRecovery=os.clock();c:PivotTo(self.LastSafe)
            r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
            self.Controllers.antifall.Recoveries+=1
        elseif r.Position.Y>=g.SurfaceY+2 and r.Position.Y<=g.SurfaceY+7 and h.FloorMaterial~=Enum.Material.Air then
            self.LastSafe=c:GetPivot()
        end
    end
    function M:Step()
        local any=false;for _,c in pairs(self.Controllers)do if c.Enabled then any=true;break end end
        local map=workspace:FindFirstChild("GlassBridge")
        local holder=map and map:FindFirstChild("GlassHolder")
        if not any or not active() or not holder then
            if self.Map then self:Reset()end
            for _,c in pairs(self.Controllers)do if c.Enabled then c.Status="Waiting for Glass Bridge" end end
            return
        end
        if map~=self.Map or holder~=self.Holder then
            self:Reset();self.Map=map;self.Holder=holder
            self.Folder=Instance.new("Folder");self.Folder.Name="AllenGlassBridge";self.Folder.Parent=workspace
        end
        self:Scan();self:VisualsAndPads();self:CatchFloor()
        if enabled("finish") then
            local c,h,r=character();local s=self.Controllers.finish
            if c and self.Teleported==c then s.Status="Teleported to End platform"
            elseif c and not LP:GetAttribute("IsGuard") then
                local target,reason=self:FindFinish()
                if target and self.Geometry and math.abs(r.Position.Y-self.Geometry.SurfaceY)<100 then
                    c:PivotTo(target);r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
                    self.Teleported=c;s.Status="Teleported to End platform";s.Teleports+=1
                else s.Status=reason or "Waiting for bridge participation" end
            else s.Status="Waiting for living character" end
        end
    end
    function M:Refresh()
        local ok,err=pcall(self.Step,self)
        if not ok then
            for _,c in pairs(self.Controllers)do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,100)end
            self:Reset();warn("[Allen Glass Bridge] "..tostring(err))
        end
    end
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        M.Elapsed+=dt
        if M.Elapsed>=.25 then M.Elapsed=0;M:Refresh() end
        if M.Map then
            local ok,err=pcall(M.Recover,M)
            if not ok then local c=M.Controllers.antifall;if c then c.Enabled=false;c.Status="Recovery stopped: "..tostring(err):sub(1,90)end end
        end
    end)
    function M:Create(mode)
        local key="__ALLEN_GLASS_"..mode
        local previous=self.Controllers[mode]
        if previous then previous:SetEnabled(false);previous.Destroyed=true end
        local c={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Recoveries=0,Teleports=0}
        function c:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if mode=="finish" then M.Teleported=nil end
            M:Refresh()
            if not self.Enabled then self.Status="Off" end
        end
        function c:GetSnapshot()
            return {Enabled=self.Enabled,Status=self.Status,Recoveries=self.Recoveries,Teleports=self.Teleports}
        end
        function c:InspectFinish() return M:FindFinish() end
        function c:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers)then
                M:Reset();M.Destroyed=true;M.Connection:Disconnect()
                if env.__ALLEN_GLASS_MANAGER==M then env.__ALLEN_GLASS_MANAGER=nil end
            end
        end
        self.Controllers[mode]=c;env[key]=c;return c
    end
end
return M:Create(MODE)

]====],
GlassReveal=[====[
local MODE="reveal"
-- Independent headless Glass Bridge switches. MODE is supplied by the hub build.
-- Geometry is local; original glass attributes and native connections are untouched.
assert(game.GameId==7008097940,"Open Ink Game to use Glass Bridge")
local LP=game:GetService("Players").LocalPlayer
local RunService=game:GetService("RunService")
local env=getgenv()
local M=env.__ALLEN_GLASS_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Records={},Rows={},Map=nil,Holder=nil,Folder=nil,Destroyed=false,Elapsed=0}
    env.__ALLEN_GLASS_MANAGER=M
    local function enabled(mode)local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed end
    local function character()
        local c=LP.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and h.Health>0 and not c:FindFirstChild("Dead") then return c,h,r end
    end
    local function active()
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="GlassBridge" and not workspace:GetAttribute("GLASSBRIDGEOVER")
    end
    local function remove(record,key)
        if record[key] then record[key]:Destroy();record[key]=nil end
    end
    function M:Reset()
        if self.Folder then self.Folder:Destroy() end
        self.Folder=nil;self.Map=nil;self.Holder=nil;self.Floor=nil;self.Geometry=nil
        self.LastSafe=nil;self.LastCharacter=nil;self.Teleported=nil
        table.clear(self.Records);table.clear(self.Rows)
    end
    local function collisionPart(name,size,cf,parent)
        local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf
        p.Anchored=true;p.CanCollide=true;p.CanTouch=false;p.CanQuery=false
        p.Transparency=1;p.CastShadow=false;p.Locked=true;p.Parent=parent
        return p
    end
    function M:Scan()
        local rows={}
        for _,row in ipairs(self.Holder:GetChildren()) do
            local index=tonumber(row.Name:match("^ClonedPanel(%d+)$"))
            if index then
                local sum=Vector3.zero;local count=0
                for _,model in ipairs(row:GetChildren())do
                    local part=model:IsA("Model") and model.PrimaryPart
                    if part and part:IsA("BasePart") and part.Name=="glasspart" then
                        local record=self.Records[part]
                        if not record then
                            record={Part=part,Model=model,CFrame=part.CFrame,Size=part.Size,Row=index}
                            self.Records[part]=record
                        end
                        record.Fake=part:GetAttribute("exploitingisevil")==true
                        sum+=record.CFrame.Position;count+=1
                    end
                end
                if count>0 then rows[#rows+1]={Index=index,Center=sum/count} end
            end
        end
        table.sort(rows,function(a,b)return a.Index<b.Index end)
        self.Rows=rows
        if #rows<2 then return end
        local first,last=rows[1].Center,rows[#rows].Center
        local delta=Vector3.new(last.X-first.X,0,last.Z-first.Z)
        if delta.Magnitude<5 then return end
        local direction=delta.Unit
        local right=direction:Cross(Vector3.yAxis)
        local center=(first+last)*.5
        local width,minY,maxY=0,math.huge,-math.huge
        for _,record in pairs(self.Records)do
            local p=record.CFrame.Position
            local half=math.abs(record.CFrame.RightVector:Dot(right))*record.Size.X*.5
                +math.abs(record.CFrame.LookVector:Dot(right))*record.Size.Z*.5
            width=math.max(width,math.abs((p-center):Dot(right))+half)
            local top=p.Y+record.Size.Y*.5
            minY=math.min(minY,top);maxY=math.max(maxY,top)
        end
        local spacing=delta.Magnitude/math.max(1,rows[#rows].Index-rows[1].Index)
        self.Geometry={Direction=direction,Right=right,Center=center,SurfaceY=minY,MaxY=maxY,
            Width=width*2+8,Length=delta.Magnitude+spacing*2,Spacing=spacing,Last=last}
    end
    function M:FindFinish()
        local g=self.Geometry;local finish=self.Map and self.Map:FindFirstChild("End")
        if not g or not finish or not finish:IsA("Model") then return nil,"Waiting for native End platform" end
        local cf=finish:GetBoundingBox()
        local center=cf.Position
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={finish};params.IgnoreWater=true
        local _,h,r=character();if not r then return nil,"Waiting for character" end
        for _,forward in ipairs({0,-g.Spacing*.5,g.Spacing*.5,g.Spacing})do
            for _,side in ipairs({0,g.Width*.2,-g.Width*.2})do
                local p=center+g.Direction*forward+g.Right*side
                local hit=workspace:Raycast(Vector3.new(p.X,g.SurfaceY+12,p.Z),Vector3.new(0,-30,0),params)
                if hit and hit.Normal.Y>=.85 and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
                    and math.min(hit.Instance.Size.X,hit.Instance.Size.Z)>=4
                    and math.abs(hit.Position.Y-g.SurfaceY)<3 then
                    local height=math.max(3,h.HipHeight+r.Size.Y*.5)+.3
                    local point=hit.Position+Vector3.new(0,height,0)
                    return CFrame.lookAt(point,point+g.Direction),"Native End platform"
                end
            end
        end
        return nil,"No solid landing found on End platform"
    end
    function M:VisualsAndPads()
        local fake,safe,pads=0,0,0
        for _,record in pairs(self.Records)do
            if record.Fake then fake+=1 else safe+=1 end
            if enabled("reveal") and record.Model:IsDescendantOf(self.Holder) then
                if not record.Highlight then
                    local h=Instance.new("Highlight");h.Name="GlassMarker";h.Adornee=record.Model
                    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.FillTransparency=.55;h.OutlineTransparency=0
                    h.Parent=self.Folder;record.Highlight=h
                end
                local color=record.Fake and Color3.fromRGB(255,65,75) or Color3.fromRGB(65,235,125)
                record.Highlight.FillColor=color;record.Highlight.OutlineColor=color
            else remove(record,"Highlight")end
            if enabled("walkfake") and record.Fake then
                if not record.Pad then
                    record.Pad=collisionPart("FakeGlassSupport",Vector3.new(record.Size.X+.2,.25,record.Size.Z+.2),
                        record.CFrame*CFrame.new(0,record.Size.Y*.5+.4,0),self.Folder)
                end
                pads+=1
            else remove(record,"Pad")end
        end
        if enabled("reveal") then self.Controllers.reveal.Status="Green: safe "..safe.." · red: fake "..fake end
        if enabled("walkfake") then self.Controllers.walkfake.Status="Local fake-glass supports: "..pads end
    end
    function M:CatchFloor()
        local g=self.Geometry
        if enabled("antifall") and g and g.MaxY-g.SurfaceY<2 then
            if not self.Floor then
                local center=Vector3.new(g.Center.X,g.SurfaceY-.6,g.Center.Z)
                self.Floor=collisionPart("BridgeCatchFloor",Vector3.new(g.Width,.4,g.Length),
                    CFrame.lookAt(center,center+g.Direction),self.Folder)
            end
            self.Controllers.antifall.Status="Local catch floor active"
        else
            if self.Floor then self.Floor:Destroy();self.Floor=nil end
            if enabled("antifall") then self.Controllers.antifall.Status="Waiting for flat bridge geometry" end
        end
    end
    function M:Recover()
        if not enabled("antifall") or not self.Geometry then return end
        local c,h,r=character();if not r then return end
        if self.LastCharacter~=c then self.LastCharacter=c;self.LastSafe=nil end
        if c:FindFirstChild("Ragdoll") then return end
        local g=self.Geometry
        local relative=CFrame.lookAt(g.Center,g.Center+g.Direction):PointToObjectSpace(r.Position)
        if math.abs(relative.X)>g.Width*.5+8 or math.abs(relative.Z)>g.Length*.5+8 then return end
        if r.Position.Y<g.SurfaceY-2 and self.LastSafe and os.clock()-(self.LastRecovery or 0)>.5 then
            self.LastRecovery=os.clock();c:PivotTo(self.LastSafe)
            r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
            self.Controllers.antifall.Recoveries+=1
        elseif r.Position.Y>=g.SurfaceY+2 and r.Position.Y<=g.SurfaceY+7 and h.FloorMaterial~=Enum.Material.Air then
            self.LastSafe=c:GetPivot()
        end
    end
    function M:Step()
        local any=false;for _,c in pairs(self.Controllers)do if c.Enabled then any=true;break end end
        local map=workspace:FindFirstChild("GlassBridge")
        local holder=map and map:FindFirstChild("GlassHolder")
        if not any or not active() or not holder then
            if self.Map then self:Reset()end
            for _,c in pairs(self.Controllers)do if c.Enabled then c.Status="Waiting for Glass Bridge" end end
            return
        end
        if map~=self.Map or holder~=self.Holder then
            self:Reset();self.Map=map;self.Holder=holder
            self.Folder=Instance.new("Folder");self.Folder.Name="AllenGlassBridge";self.Folder.Parent=workspace
        end
        self:Scan();self:VisualsAndPads();self:CatchFloor()
        if enabled("finish") then
            local c,h,r=character();local s=self.Controllers.finish
            if c and self.Teleported==c then s.Status="Teleported to End platform"
            elseif c and not LP:GetAttribute("IsGuard") then
                local target,reason=self:FindFinish()
                if target and self.Geometry and math.abs(r.Position.Y-self.Geometry.SurfaceY)<100 then
                    c:PivotTo(target);r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
                    self.Teleported=c;s.Status="Teleported to End platform";s.Teleports+=1
                else s.Status=reason or "Waiting for bridge participation" end
            else s.Status="Waiting for living character" end
        end
    end
    function M:Refresh()
        local ok,err=pcall(self.Step,self)
        if not ok then
            for _,c in pairs(self.Controllers)do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,100)end
            self:Reset();warn("[Allen Glass Bridge] "..tostring(err))
        end
    end
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        M.Elapsed+=dt
        if M.Elapsed>=.25 then M.Elapsed=0;M:Refresh() end
        if M.Map then
            local ok,err=pcall(M.Recover,M)
            if not ok then local c=M.Controllers.antifall;if c then c.Enabled=false;c.Status="Recovery stopped: "..tostring(err):sub(1,90)end end
        end
    end)
    function M:Create(mode)
        local key="__ALLEN_GLASS_"..mode
        local previous=self.Controllers[mode]
        if previous then previous:SetEnabled(false);previous.Destroyed=true end
        local c={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Recoveries=0,Teleports=0}
        function c:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if mode=="finish" then M.Teleported=nil end
            M:Refresh()
            if not self.Enabled then self.Status="Off" end
        end
        function c:GetSnapshot()
            return {Enabled=self.Enabled,Status=self.Status,Recoveries=self.Recoveries,Teleports=self.Teleports}
        end
        function c:InspectFinish() return M:FindFinish() end
        function c:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers)then
                M:Reset();M.Destroyed=true;M.Connection:Disconnect()
                if env.__ALLEN_GLASS_MANAGER==M then env.__ALLEN_GLASS_MANAGER=nil end
            end
        end
        self.Controllers[mode]=c;env[key]=c;return c
    end
end
return M:Create(MODE)

]====],
GlassAntiFall=[====[
local MODE="antifall"
-- Independent headless Glass Bridge switches. MODE is supplied by the hub build.
-- Geometry is local; original glass attributes and native connections are untouched.
assert(game.GameId==7008097940,"Open Ink Game to use Glass Bridge")
local LP=game:GetService("Players").LocalPlayer
local RunService=game:GetService("RunService")
local env=getgenv()
local M=env.__ALLEN_GLASS_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Records={},Rows={},Map=nil,Holder=nil,Folder=nil,Destroyed=false,Elapsed=0}
    env.__ALLEN_GLASS_MANAGER=M
    local function enabled(mode)local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed end
    local function character()
        local c=LP.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and h.Health>0 and not c:FindFirstChild("Dead") then return c,h,r end
    end
    local function active()
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="GlassBridge" and not workspace:GetAttribute("GLASSBRIDGEOVER")
    end
    local function remove(record,key)
        if record[key] then record[key]:Destroy();record[key]=nil end
    end
    function M:Reset()
        if self.Folder then self.Folder:Destroy() end
        self.Folder=nil;self.Map=nil;self.Holder=nil;self.Floor=nil;self.Geometry=nil
        self.LastSafe=nil;self.LastCharacter=nil;self.Teleported=nil
        table.clear(self.Records);table.clear(self.Rows)
    end
    local function collisionPart(name,size,cf,parent)
        local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf
        p.Anchored=true;p.CanCollide=true;p.CanTouch=false;p.CanQuery=false
        p.Transparency=1;p.CastShadow=false;p.Locked=true;p.Parent=parent
        return p
    end
    function M:Scan()
        local rows={}
        for _,row in ipairs(self.Holder:GetChildren()) do
            local index=tonumber(row.Name:match("^ClonedPanel(%d+)$"))
            if index then
                local sum=Vector3.zero;local count=0
                for _,model in ipairs(row:GetChildren())do
                    local part=model:IsA("Model") and model.PrimaryPart
                    if part and part:IsA("BasePart") and part.Name=="glasspart" then
                        local record=self.Records[part]
                        if not record then
                            record={Part=part,Model=model,CFrame=part.CFrame,Size=part.Size,Row=index}
                            self.Records[part]=record
                        end
                        record.Fake=part:GetAttribute("exploitingisevil")==true
                        sum+=record.CFrame.Position;count+=1
                    end
                end
                if count>0 then rows[#rows+1]={Index=index,Center=sum/count} end
            end
        end
        table.sort(rows,function(a,b)return a.Index<b.Index end)
        self.Rows=rows
        if #rows<2 then return end
        local first,last=rows[1].Center,rows[#rows].Center
        local delta=Vector3.new(last.X-first.X,0,last.Z-first.Z)
        if delta.Magnitude<5 then return end
        local direction=delta.Unit
        local right=direction:Cross(Vector3.yAxis)
        local center=(first+last)*.5
        local width,minY,maxY=0,math.huge,-math.huge
        for _,record in pairs(self.Records)do
            local p=record.CFrame.Position
            local half=math.abs(record.CFrame.RightVector:Dot(right))*record.Size.X*.5
                +math.abs(record.CFrame.LookVector:Dot(right))*record.Size.Z*.5
            width=math.max(width,math.abs((p-center):Dot(right))+half)
            local top=p.Y+record.Size.Y*.5
            minY=math.min(minY,top);maxY=math.max(maxY,top)
        end
        local spacing=delta.Magnitude/math.max(1,rows[#rows].Index-rows[1].Index)
        self.Geometry={Direction=direction,Right=right,Center=center,SurfaceY=minY,MaxY=maxY,
            Width=width*2+8,Length=delta.Magnitude+spacing*2,Spacing=spacing,Last=last}
    end
    function M:FindFinish()
        local g=self.Geometry;local finish=self.Map and self.Map:FindFirstChild("End")
        if not g or not finish or not finish:IsA("Model") then return nil,"Waiting for native End platform" end
        local cf=finish:GetBoundingBox()
        local center=cf.Position
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={finish};params.IgnoreWater=true
        local _,h,r=character();if not r then return nil,"Waiting for character" end
        for _,forward in ipairs({0,-g.Spacing*.5,g.Spacing*.5,g.Spacing})do
            for _,side in ipairs({0,g.Width*.2,-g.Width*.2})do
                local p=center+g.Direction*forward+g.Right*side
                local hit=workspace:Raycast(Vector3.new(p.X,g.SurfaceY+12,p.Z),Vector3.new(0,-30,0),params)
                if hit and hit.Normal.Y>=.85 and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
                    and math.min(hit.Instance.Size.X,hit.Instance.Size.Z)>=4
                    and math.abs(hit.Position.Y-g.SurfaceY)<3 then
                    local height=math.max(3,h.HipHeight+r.Size.Y*.5)+.3
                    local point=hit.Position+Vector3.new(0,height,0)
                    return CFrame.lookAt(point,point+g.Direction),"Native End platform"
                end
            end
        end
        return nil,"No solid landing found on End platform"
    end
    function M:VisualsAndPads()
        local fake,safe,pads=0,0,0
        for _,record in pairs(self.Records)do
            if record.Fake then fake+=1 else safe+=1 end
            if enabled("reveal") and record.Model:IsDescendantOf(self.Holder) then
                if not record.Highlight then
                    local h=Instance.new("Highlight");h.Name="GlassMarker";h.Adornee=record.Model
                    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.FillTransparency=.55;h.OutlineTransparency=0
                    h.Parent=self.Folder;record.Highlight=h
                end
                local color=record.Fake and Color3.fromRGB(255,65,75) or Color3.fromRGB(65,235,125)
                record.Highlight.FillColor=color;record.Highlight.OutlineColor=color
            else remove(record,"Highlight")end
            if enabled("walkfake") and record.Fake then
                if not record.Pad then
                    record.Pad=collisionPart("FakeGlassSupport",Vector3.new(record.Size.X+.2,.25,record.Size.Z+.2),
                        record.CFrame*CFrame.new(0,record.Size.Y*.5+.4,0),self.Folder)
                end
                pads+=1
            else remove(record,"Pad")end
        end
        if enabled("reveal") then self.Controllers.reveal.Status="Green: safe "..safe.." · red: fake "..fake end
        if enabled("walkfake") then self.Controllers.walkfake.Status="Local fake-glass supports: "..pads end
    end
    function M:CatchFloor()
        local g=self.Geometry
        if enabled("antifall") and g and g.MaxY-g.SurfaceY<2 then
            if not self.Floor then
                local center=Vector3.new(g.Center.X,g.SurfaceY-.6,g.Center.Z)
                self.Floor=collisionPart("BridgeCatchFloor",Vector3.new(g.Width,.4,g.Length),
                    CFrame.lookAt(center,center+g.Direction),self.Folder)
            end
            self.Controllers.antifall.Status="Local catch floor active"
        else
            if self.Floor then self.Floor:Destroy();self.Floor=nil end
            if enabled("antifall") then self.Controllers.antifall.Status="Waiting for flat bridge geometry" end
        end
    end
    function M:Recover()
        if not enabled("antifall") or not self.Geometry then return end
        local c,h,r=character();if not r then return end
        if self.LastCharacter~=c then self.LastCharacter=c;self.LastSafe=nil end
        if c:FindFirstChild("Ragdoll") then return end
        local g=self.Geometry
        local relative=CFrame.lookAt(g.Center,g.Center+g.Direction):PointToObjectSpace(r.Position)
        if math.abs(relative.X)>g.Width*.5+8 or math.abs(relative.Z)>g.Length*.5+8 then return end
        if r.Position.Y<g.SurfaceY-2 and self.LastSafe and os.clock()-(self.LastRecovery or 0)>.5 then
            self.LastRecovery=os.clock();c:PivotTo(self.LastSafe)
            r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
            self.Controllers.antifall.Recoveries+=1
        elseif r.Position.Y>=g.SurfaceY+2 and r.Position.Y<=g.SurfaceY+7 and h.FloorMaterial~=Enum.Material.Air then
            self.LastSafe=c:GetPivot()
        end
    end
    function M:Step()
        local any=false;for _,c in pairs(self.Controllers)do if c.Enabled then any=true;break end end
        local map=workspace:FindFirstChild("GlassBridge")
        local holder=map and map:FindFirstChild("GlassHolder")
        if not any or not active() or not holder then
            if self.Map then self:Reset()end
            for _,c in pairs(self.Controllers)do if c.Enabled then c.Status="Waiting for Glass Bridge" end end
            return
        end
        if map~=self.Map or holder~=self.Holder then
            self:Reset();self.Map=map;self.Holder=holder
            self.Folder=Instance.new("Folder");self.Folder.Name="AllenGlassBridge";self.Folder.Parent=workspace
        end
        self:Scan();self:VisualsAndPads();self:CatchFloor()
        if enabled("finish") then
            local c,h,r=character();local s=self.Controllers.finish
            if c and self.Teleported==c then s.Status="Teleported to End platform"
            elseif c and not LP:GetAttribute("IsGuard") then
                local target,reason=self:FindFinish()
                if target and self.Geometry and math.abs(r.Position.Y-self.Geometry.SurfaceY)<100 then
                    c:PivotTo(target);r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
                    self.Teleported=c;s.Status="Teleported to End platform";s.Teleports+=1
                else s.Status=reason or "Waiting for bridge participation" end
            else s.Status="Waiting for living character" end
        end
    end
    function M:Refresh()
        local ok,err=pcall(self.Step,self)
        if not ok then
            for _,c in pairs(self.Controllers)do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,100)end
            self:Reset();warn("[Allen Glass Bridge] "..tostring(err))
        end
    end
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        M.Elapsed+=dt
        if M.Elapsed>=.25 then M.Elapsed=0;M:Refresh() end
        if M.Map then
            local ok,err=pcall(M.Recover,M)
            if not ok then local c=M.Controllers.antifall;if c then c.Enabled=false;c.Status="Recovery stopped: "..tostring(err):sub(1,90)end end
        end
    end)
    function M:Create(mode)
        local key="__ALLEN_GLASS_"..mode
        local previous=self.Controllers[mode]
        if previous then previous:SetEnabled(false);previous.Destroyed=true end
        local c={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Recoveries=0,Teleports=0}
        function c:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if mode=="finish" then M.Teleported=nil end
            M:Refresh()
            if not self.Enabled then self.Status="Off" end
        end
        function c:GetSnapshot()
            return {Enabled=self.Enabled,Status=self.Status,Recoveries=self.Recoveries,Teleports=self.Teleports}
        end
        function c:InspectFinish() return M:FindFinish() end
        function c:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers)then
                M:Reset();M.Destroyed=true;M.Connection:Disconnect()
                if env.__ALLEN_GLASS_MANAGER==M then env.__ALLEN_GLASS_MANAGER=nil end
            end
        end
        self.Controllers[mode]=c;env[key]=c;return c
    end
end
return M:Create(MODE)

]====],
GlassWalkFake=[====[
local MODE="walkfake"
-- Independent headless Glass Bridge switches. MODE is supplied by the hub build.
-- Geometry is local; original glass attributes and native connections are untouched.
assert(game.GameId==7008097940,"Open Ink Game to use Glass Bridge")
local LP=game:GetService("Players").LocalPlayer
local RunService=game:GetService("RunService")
local env=getgenv()
local M=env.__ALLEN_GLASS_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Records={},Rows={},Map=nil,Holder=nil,Folder=nil,Destroyed=false,Elapsed=0}
    env.__ALLEN_GLASS_MANAGER=M
    local function enabled(mode)local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed end
    local function character()
        local c=LP.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and h.Health>0 and not c:FindFirstChild("Dead") then return c,h,r end
    end
    local function active()
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="GlassBridge" and not workspace:GetAttribute("GLASSBRIDGEOVER")
    end
    local function remove(record,key)
        if record[key] then record[key]:Destroy();record[key]=nil end
    end
    function M:Reset()
        if self.Folder then self.Folder:Destroy() end
        self.Folder=nil;self.Map=nil;self.Holder=nil;self.Floor=nil;self.Geometry=nil
        self.LastSafe=nil;self.LastCharacter=nil;self.Teleported=nil
        table.clear(self.Records);table.clear(self.Rows)
    end
    local function collisionPart(name,size,cf,parent)
        local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf
        p.Anchored=true;p.CanCollide=true;p.CanTouch=false;p.CanQuery=false
        p.Transparency=1;p.CastShadow=false;p.Locked=true;p.Parent=parent
        return p
    end
    function M:Scan()
        local rows={}
        for _,row in ipairs(self.Holder:GetChildren()) do
            local index=tonumber(row.Name:match("^ClonedPanel(%d+)$"))
            if index then
                local sum=Vector3.zero;local count=0
                for _,model in ipairs(row:GetChildren())do
                    local part=model:IsA("Model") and model.PrimaryPart
                    if part and part:IsA("BasePart") and part.Name=="glasspart" then
                        local record=self.Records[part]
                        if not record then
                            record={Part=part,Model=model,CFrame=part.CFrame,Size=part.Size,Row=index}
                            self.Records[part]=record
                        end
                        record.Fake=part:GetAttribute("exploitingisevil")==true
                        sum+=record.CFrame.Position;count+=1
                    end
                end
                if count>0 then rows[#rows+1]={Index=index,Center=sum/count} end
            end
        end
        table.sort(rows,function(a,b)return a.Index<b.Index end)
        self.Rows=rows
        if #rows<2 then return end
        local first,last=rows[1].Center,rows[#rows].Center
        local delta=Vector3.new(last.X-first.X,0,last.Z-first.Z)
        if delta.Magnitude<5 then return end
        local direction=delta.Unit
        local right=direction:Cross(Vector3.yAxis)
        local center=(first+last)*.5
        local width,minY,maxY=0,math.huge,-math.huge
        for _,record in pairs(self.Records)do
            local p=record.CFrame.Position
            local half=math.abs(record.CFrame.RightVector:Dot(right))*record.Size.X*.5
                +math.abs(record.CFrame.LookVector:Dot(right))*record.Size.Z*.5
            width=math.max(width,math.abs((p-center):Dot(right))+half)
            local top=p.Y+record.Size.Y*.5
            minY=math.min(minY,top);maxY=math.max(maxY,top)
        end
        local spacing=delta.Magnitude/math.max(1,rows[#rows].Index-rows[1].Index)
        self.Geometry={Direction=direction,Right=right,Center=center,SurfaceY=minY,MaxY=maxY,
            Width=width*2+8,Length=delta.Magnitude+spacing*2,Spacing=spacing,Last=last}
    end
    function M:FindFinish()
        local g=self.Geometry;local finish=self.Map and self.Map:FindFirstChild("End")
        if not g or not finish or not finish:IsA("Model") then return nil,"Waiting for native End platform" end
        local cf=finish:GetBoundingBox()
        local center=cf.Position
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={finish};params.IgnoreWater=true
        local _,h,r=character();if not r then return nil,"Waiting for character" end
        for _,forward in ipairs({0,-g.Spacing*.5,g.Spacing*.5,g.Spacing})do
            for _,side in ipairs({0,g.Width*.2,-g.Width*.2})do
                local p=center+g.Direction*forward+g.Right*side
                local hit=workspace:Raycast(Vector3.new(p.X,g.SurfaceY+12,p.Z),Vector3.new(0,-30,0),params)
                if hit and hit.Normal.Y>=.85 and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
                    and math.min(hit.Instance.Size.X,hit.Instance.Size.Z)>=4
                    and math.abs(hit.Position.Y-g.SurfaceY)<3 then
                    local height=math.max(3,h.HipHeight+r.Size.Y*.5)+.3
                    local point=hit.Position+Vector3.new(0,height,0)
                    return CFrame.lookAt(point,point+g.Direction),"Native End platform"
                end
            end
        end
        return nil,"No solid landing found on End platform"
    end
    function M:VisualsAndPads()
        local fake,safe,pads=0,0,0
        for _,record in pairs(self.Records)do
            if record.Fake then fake+=1 else safe+=1 end
            if enabled("reveal") and record.Model:IsDescendantOf(self.Holder) then
                if not record.Highlight then
                    local h=Instance.new("Highlight");h.Name="GlassMarker";h.Adornee=record.Model
                    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.FillTransparency=.55;h.OutlineTransparency=0
                    h.Parent=self.Folder;record.Highlight=h
                end
                local color=record.Fake and Color3.fromRGB(255,65,75) or Color3.fromRGB(65,235,125)
                record.Highlight.FillColor=color;record.Highlight.OutlineColor=color
            else remove(record,"Highlight")end
            if enabled("walkfake") and record.Fake then
                if not record.Pad then
                    record.Pad=collisionPart("FakeGlassSupport",Vector3.new(record.Size.X+.2,.25,record.Size.Z+.2),
                        record.CFrame*CFrame.new(0,record.Size.Y*.5+.4,0),self.Folder)
                end
                pads+=1
            else remove(record,"Pad")end
        end
        if enabled("reveal") then self.Controllers.reveal.Status="Green: safe "..safe.." · red: fake "..fake end
        if enabled("walkfake") then self.Controllers.walkfake.Status="Local fake-glass supports: "..pads end
    end
    function M:CatchFloor()
        local g=self.Geometry
        if enabled("antifall") and g and g.MaxY-g.SurfaceY<2 then
            if not self.Floor then
                local center=Vector3.new(g.Center.X,g.SurfaceY-.6,g.Center.Z)
                self.Floor=collisionPart("BridgeCatchFloor",Vector3.new(g.Width,.4,g.Length),
                    CFrame.lookAt(center,center+g.Direction),self.Folder)
            end
            self.Controllers.antifall.Status="Local catch floor active"
        else
            if self.Floor then self.Floor:Destroy();self.Floor=nil end
            if enabled("antifall") then self.Controllers.antifall.Status="Waiting for flat bridge geometry" end
        end
    end
    function M:Recover()
        if not enabled("antifall") or not self.Geometry then return end
        local c,h,r=character();if not r then return end
        if self.LastCharacter~=c then self.LastCharacter=c;self.LastSafe=nil end
        if c:FindFirstChild("Ragdoll") then return end
        local g=self.Geometry
        local relative=CFrame.lookAt(g.Center,g.Center+g.Direction):PointToObjectSpace(r.Position)
        if math.abs(relative.X)>g.Width*.5+8 or math.abs(relative.Z)>g.Length*.5+8 then return end
        if r.Position.Y<g.SurfaceY-2 and self.LastSafe and os.clock()-(self.LastRecovery or 0)>.5 then
            self.LastRecovery=os.clock();c:PivotTo(self.LastSafe)
            r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
            self.Controllers.antifall.Recoveries+=1
        elseif r.Position.Y>=g.SurfaceY+2 and r.Position.Y<=g.SurfaceY+7 and h.FloorMaterial~=Enum.Material.Air then
            self.LastSafe=c:GetPivot()
        end
    end
    function M:Step()
        local any=false;for _,c in pairs(self.Controllers)do if c.Enabled then any=true;break end end
        local map=workspace:FindFirstChild("GlassBridge")
        local holder=map and map:FindFirstChild("GlassHolder")
        if not any or not active() or not holder then
            if self.Map then self:Reset()end
            for _,c in pairs(self.Controllers)do if c.Enabled then c.Status="Waiting for Glass Bridge" end end
            return
        end
        if map~=self.Map or holder~=self.Holder then
            self:Reset();self.Map=map;self.Holder=holder
            self.Folder=Instance.new("Folder");self.Folder.Name="AllenGlassBridge";self.Folder.Parent=workspace
        end
        self:Scan();self:VisualsAndPads();self:CatchFloor()
        if enabled("finish") then
            local c,h,r=character();local s=self.Controllers.finish
            if c and self.Teleported==c then s.Status="Teleported to End platform"
            elseif c and not LP:GetAttribute("IsGuard") then
                local target,reason=self:FindFinish()
                if target and self.Geometry and math.abs(r.Position.Y-self.Geometry.SurfaceY)<100 then
                    c:PivotTo(target);r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
                    self.Teleported=c;s.Status="Teleported to End platform";s.Teleports+=1
                else s.Status=reason or "Waiting for bridge participation" end
            else s.Status="Waiting for living character" end
        end
    end
    function M:Refresh()
        local ok,err=pcall(self.Step,self)
        if not ok then
            for _,c in pairs(self.Controllers)do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,100)end
            self:Reset();warn("[Allen Glass Bridge] "..tostring(err))
        end
    end
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        M.Elapsed+=dt
        if M.Elapsed>=.25 then M.Elapsed=0;M:Refresh() end
        if M.Map then
            local ok,err=pcall(M.Recover,M)
            if not ok then local c=M.Controllers.antifall;if c then c.Enabled=false;c.Status="Recovery stopped: "..tostring(err):sub(1,90)end end
        end
    end)
    function M:Create(mode)
        local key="__ALLEN_GLASS_"..mode
        local previous=self.Controllers[mode]
        if previous then previous:SetEnabled(false);previous.Destroyed=true end
        local c={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Recoveries=0,Teleports=0}
        function c:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if mode=="finish" then M.Teleported=nil end
            M:Refresh()
            if not self.Enabled then self.Status="Off" end
        end
        function c:GetSnapshot()
            return {Enabled=self.Enabled,Status=self.Status,Recoveries=self.Recoveries,Teleports=self.Teleports}
        end
        function c:InspectFinish() return M:FindFinish() end
        function c:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers)then
                M:Reset();M.Destroyed=true;M.Connection:Disconnect()
                if env.__ALLEN_GLASS_MANAGER==M then env.__ALLEN_GLASS_MANAGER=nil end
            end
        end
        self.Controllers[mode]=c;env[key]=c;return c
    end
end
return M:Create(MODE)

]====],
HNS=[====[
return function(MODE)
-- Allen Scripts Hide & Seek suite. MODE is supplied by the hub build.
-- Scoped map index, native movement/actions, reversible local modifications.
assert(game.GameId==7008097940,"Open Ink Game to use Hide & Seek")
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Pathfinding=game:GetService("PathfindingService")
local validModes={exits=true,doors=true,players=true,keys=true,stairs=true,spikes=true,collect=true,dodge=true,stamina=true,follow=true,hitboxes=true,teleport=true,disablespikes=true}
assert(validModes[MODE],"Unsupported Hide & Seek feature")
assert(MODE~="dodge","DODGE! is disabled while investigating crash and timeout reports")
local env=getgenv()
local KnifePolicy=(function()
local Policy={}
-- Estimated knife volume: exact caller-supplied HitboxSize/CFrameOffset is unavailable.
function Policy.InAttackBox(forward,lateral,height,range)
    return forward>0 and forward<=range and math.abs(lateral)<=3.5 and math.abs(height)<=5
end
function Policy.Prediction(x,z)
    if x~=x or z~=z or math.abs(x)==math.huge or math.abs(z)==math.huge then return 0,0 end
    x*=.1;z*=.1
    local length=math.sqrt(x*x+z*z)
    if length>10 then x=x/length*10;z=z/length*10 end
    return x,z
end
return Policy

end)()
local M=env.__ALLEN_HNS_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Generation=0,Connections={},Animators={},Targets={},Doors={},Exits={},Keys={},Stairs={},Spikes={},
        Originals={},Covers={},Elapsed=0,RouteClock=0,Threats={},LastDodge=0,NextPeers=0}
    env.__ALLEN_HNS_MANAGER=M
    local colors={Blue=Color3.fromRGB(65,155,255),Red=Color3.fromRGB(255,65,75),Green=Color3.fromRGB(70,235,135),
        Yellow=Color3.fromRGB(255,205,65),White=Color3.fromRGB(220,220,230)}
    local function enabled(mode)local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed end
    local function live(p)
        if not p then return end
        local c=p.Character;local h=c and c:FindFirstChildOfClass("Humanoid");local r=c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and h.Health>0 and not c:FindFirstChild("Dead") then return c,h,r end
    end
    local function active()
        local values=workspace:FindFirstChild("Values");local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="HideAndSeek" and not workspace:GetAttribute("HIDEANDSEEKOVER")
    end
    local function hunter(p)return p:GetAttribute("IsHunter")==true end
    local function hider(p)return p:GetAttribute("IsHider")==true and p:GetAttribute("HNSDidEscape")~=true end
    local function nearest(predicate,maxRange)
        local _,_,r=live(LP);if not r then return end
        local target,distance=nil,maxRange or math.huge
        for _,p in ipairs(Players:GetPlayers())do
            local _,_,other=live(p)
            if p~=LP and other and predicate(p) then
                local d=(other.Position-r.Position).Magnitude
                if d<distance then target=p;distance=d end
            end
        end
        return target,distance
    end
    local function objectPart(object)
        if object:IsA("BasePart") then return object end
        if object:IsA("Model") then return object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart",true)end
    end
    local function restore(mode)
        local records=M.Originals[mode]
        if not records then return end
        for object,properties in pairs(records)do for property,record in pairs(properties)do
            pcall(function()if object[property]==record.Value then object[property]=record.Original end end)
        end end
        M.Originals[mode]=nil
    end
    local function set(mode,object,property,value)
        local records=M.Originals[mode] or {};M.Originals[mode]=records
        local values=records[object] or {};records[object]=values
        if not values[property] then values[property]={Original=object[property],Value=value}end
        values[property].Value=value;object[property]=value
    end
    local function clearMarks(c)
        if not c then return end
        for _,mark in pairs(c.Marks)do mark:Destroy()end;table.clear(c.Marks)
    end
    local function restoreEquipment()
        local lease=M.DodgeEquipment;M.DodgeEquipment=nil
        if not lease then return end
        local c,h=live(LP)
        if c==lease.Character and lease.Tool.Parent==c then
            if lease.Previous and lease.Previous.Parent==lease.Backpack then h:EquipTool(lease.Previous)
            elseif not lease.Previous then h:UnequipTools()end
        end
    end
    function M:Reset()
        if self.FinishCollection then self.FinishCollection()end
        self.KeyVisited=nil;self.NextKeyAt=nil
        self.Generation+=1
        restoreEquipment()
        if self.Moving then local _,h=live(LP);if h then h:Move(Vector3.zero,false)end end
        self.Moving=false
        for _,connection in ipairs(self.Connections)do connection:Disconnect()end;table.clear(self.Connections)
        for _,connection in pairs(self.Animators)do connection:Disconnect()end;table.clear(self.Animators)
        for _,c in pairs(self.Controllers)do clearMarks(c)end
        restore("hitboxes");restore("disablespikes")
        if self.Folder then self.Folder:Destroy()end
        self.Folder=nil;self.Map=nil;self.Motion=nil;self.RoutePending=false;self.Teleported=nil
        self.EvadeUntil=nil;self.DodgeItemUntil=nil
        for _,name in ipairs({"Targets","Doors","Exits","Keys","Stairs","Spikes","Threats","Covers"})do table.clear(self[name])end
    end
    local function inDoor(v)
        while v and v~=M.Map do
            if v.Name=="FullDoorAnimated" or v.Name=="EXITDOOR" or v:GetAttribute("KeyNeeded")~=nil then return true end
            v=v.Parent
        end
        return false
    end
    local function index(v)
        if not v.Parent then return end
        if v:IsA("Model") then
            if v.Name=="EXITDOOR" then M.Exits[v]=true end
            if v.Name=="FullDoorAnimated" then M.Doors[v]=true end
        end
        if v:IsA("Model") or v:IsA("BasePart") then
            local name=v.Name:lower()
            if M.Map and v:IsDescendantOf(M.Map) then
                if name:find("stair",1,true) then M.Stairs[v]=true end
                if name:find("spike",1,true) then M.Spikes[v]=true end
            end
            local keyName=name:find("key",1,true) and not name:find("hole",1,true) and not name:find("holder",1,true)
                and not name:find("needed",1,true) and not name:find("prompt",1,true)
            if keyName and not inDoor(v) and not v:FindFirstAncestor("Live") then
                local parent=v.Parent
                if not (parent and parent.Name:lower():find("key",1,true)) then M.Keys[v]=true end
            end
        elseif v:IsA("ProximityPrompt") and not inDoor(v) then
            if (v.ObjectText.." "..v.ActionText):lower():find("key",1,true) then
                local object=v:FindFirstAncestorOfClass("Model") or v.Parent
                if object==M.Map then object=v.Parent end
                if object and objectPart(object) then M.Keys[object]=true end
            end
        end
    end
    local function watch(root)
        if not root then return end
        local generation=M.Generation
        M.Connections[#M.Connections+1]=root.DescendantAdded:Connect(index)
        task.spawn(function()
            for i,v in ipairs(root:GetDescendants())do
                if M.Destroyed or M.Generation~=generation then return end
                index(v);if i%256==0 then task.wait()end
            end
        end)
    end
    local function mark(mode,objects,color)
        local c=M.Controllers[mode];if not c then return end
        if not c.Enabled then clearMarks(c);return end
        local seen,n={},0
        for object in pairs(objects)do
            if object:IsDescendantOf(workspace) and objectPart(object) and n<180 then
                n+=1;seen[object]=true
                local h=c.Marks[object]
                if not h then
                    h=Instance.new("Highlight");h.Name="AllenHNSHighlight";h.Adornee=object
                    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.FillTransparency=.75;h.OutlineTransparency=0
                    h.Parent=M.Folder;c.Marks[object]=h
                end
                local value=type(color)=="function" and color(object) or color
                h.FillColor=value;h.OutlineColor=value
            elseif not object.Parent then objects[object]=nil end
        end
        for object,h in pairs(c.Marks)do if not seen[object]then h:Destroy();c.Marks[object]=nil end end
        c.Status=n.." highlighted"
    end
    local function safeDirection(point,from)
        local direction=Vector3.new(point.X-from.X,0,point.Z-from.Z)
        if direction.Magnitude<.1 then return nil end
        direction=direction.Unit
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={workspace:FindFirstChild("Live") or LP.Character};params.IgnoreWater=true
        local floor=workspace:Raycast(from+direction*4,Vector3.new(0,-12,0),params)
        local wall=workspace:Raycast(from,direction*4,params)
        if not floor or wall or floor.Instance.Name:lower():find("spike",1,true) then return nil end
        return direction
    end
    local function route(owner,target,point)
        local _,_,r=live(LP);if not r or M.RoutePending then return end
        if os.clock()-(M.RouteClock or 0)<1.5 and M.Motion and M.Motion.Target==target then return end
        M.RouteClock=os.clock();M.RoutePending=true
        local generation=M.Generation;local origin=r.Position
        task.spawn(function()
            local path=Pathfinding:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=5})
            local ok=pcall(path.ComputeAsync,path,origin,point)
            if generation~=M.Generation then return end
            M.RoutePending=false
            if not enabled(owner)then return end
            if ok and path.Status==Enum.PathStatus.Success then
                M.Motion={Owner=owner,Target=target,Waypoints=path:GetWaypoints(),Index=2}
            else M.Motion=nil;M.Controllers[owner].Status="No walkable route found" end
        end)
    end
    local function knifeAttacker(p)
        if not p or p==LP then return false end
        local c=live(p)
        return c and c:FindFirstChild("Knife") and (not active() or hunter(p))
    end
    local function aimedKnifeThreat(attacker)
        local threat=M.Threats[attacker]
        if type(threat)~="table" or threat.Expires<=os.clock() or not threat.Track.IsPlaying
            or threat.Character~=attacker.Character or not knifeAttacker(attacker)then return false end
        local c,_,other=live(attacker);local _,_,r=live(LP)
        if not c or not r or not c:FindFirstChild("Knife")then return false end
        local offset=r.Position-other.Position
        -- Geometry gate: estimated oriented attack volume versus actual local body parts.
        -- HB caller dimensions are unavailable; these are explicitly estimated, not server hitboxes.
        local box=other.CFrame*CFrame.new(0,0,-threat.Range/2)
        local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include
        overlap.FilterDescendantsInstances={LP.Character}
        local intersecting=false
        local body={HumanoidRootPart=true,Head=true,Torso=true,UpperTorso=true,LowerTorso=true,
            ["Right Arm"]=true,["Left Arm"]=true,["Right Leg"]=true,["Left Leg"]=true}
        for _,part in ipairs(workspace:GetPartBoundsInBox(box,Vector3.new(7,10,threat.Range),overlap))do
            if body[part.Name]then intersecting=true;break end
        end
        if not intersecting then return false end
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={workspace:FindFirstChild("Live") or c,LP.Character}
        params.IgnoreWater=true;params.RespectCanCollide=true
        return workspace:Raycast(other.Position,offset,params)==nil
    end
    local function onCooldown(c,tool)
        for _,child in ipairs(c:GetChildren())do
            if not child:IsA("Tool")then
                local id=child:GetAttribute("CD")
                if id and (id==tool.Name or id==tool:GetAttribute("Require"))then return true end
            end
        end
        return false
    end
    local function evade(attacker)
        if not enabled("dodge") or os.clock()-M.LastDodge<.55 then return end
        if not aimedKnifeThreat(attacker)then return end
        local threat=M.Threats[attacker]
        if not threat or threat.Attempted then return end
        local c,h,r=live(LP);local _,_,other=live(attacker)
        if not r or not other or c:FindFirstChild("Ragdoll") or c:FindFirstChild("DisableMovement")then return end
        local bag=LP:FindFirstChildOfClass("Backpack")
        local tool=c:FindFirstChild("DODGE!") or bag and bag:FindFirstChild("DODGE!")
        if not tool or not tool:IsA("Tool")then M.Controllers.dodge.Status="DODGE! item required";return end
        if onCooldown(c,tool)then M.Controllers.dodge.Status="DODGE! cooldown";return end
        -- Consume the swing before scheduling input: failures never retry this attack.
        threat.Attempted=true
        M.LastDodge=os.clock()
        M.Controllers.dodge.Status="Attempting DODGE! hotbar input"
        local generation=M.Generation
        task.defer(function()
            if generation~=M.Generation or not enabled("dodge")then return end
            if M.Threats[attacker]~=threat or not aimedKnifeThreat(attacker)then
                M.EvadeUntil=nil;restoreEquipment();M.Controllers.dodge.Status="Knife threat no longer aimed at you";return
            end
            if c~=LP.Character then return end
            if onCooldown(c,tool)then M.Controllers.dodge.Status="DODGE! cooldown";return end
            local ok,err=pcall(function()
                local input=game:GetService("UserInputService")
                assert(not input:GetFocusedTextBox(),"Close the text box before dodging")
                local gui=LP:FindFirstChildOfClass("PlayerGui")
                local hotbar=gui and gui:FindFirstChild("Hotbar")
                hotbar=hotbar and hotbar:FindFirstChild("Backpack")
                hotbar=hotbar and hotbar:FindFirstChild("Hotbar")
                local slot
                if hotbar then for _,button in ipairs(hotbar:GetChildren())do
                    local label=button:FindFirstChild("ToolName")
                    if button:IsA("GuiButton") and button.Visible and label and label.Text==tool.Name then
                        slot=button;break
                    end
                end end
                assert(slot,"DODGE! must be visible in the hotbar")
                local vim=game:GetService("VirtualInputManager")
                local number=slot:FindFirstChild("Number")
                local names={['1']='One',['2']='Two',['3']='Three',['4']='Four',['5']='Five',
                    ['6']='Six',['7']='Seven',['8']='Eight',['9']='Nine',['0']='Zero',['E']='E',['T']='T',['Y']='Y'}
                local key=number and names[number.Text]
                if input.KeyboardEnabled and key then
                    local code=Enum.KeyCode[key]
                    vim:SendKeyEvent(true,code,false,game)
                    task.delay(.03,function()pcall(function()vim:SendKeyEvent(false,code,false,game)end)end)
                else
                    local center=slot.AbsolutePosition+slot.AbsoluteSize/2
                    local top=gui:GetGuiObjectsAtPosition(center.X,center.Y)[1]
                    assert(top and (top==slot or top:IsDescendantOf(slot)),"DODGE! hotbar button is covered")
                    vim:SendMouseButtonEvent(center.X,center.Y,0,true,game,0)
                    task.delay(.03,function()pcall(function()
                        vim:SendMouseButtonEvent(center.X,center.Y,0,false,game,0)
                    end)end)
                end
                local state=M.Controllers.dodge
                state.Status="Input sent · checking dodge cooldown"
                task.delay(.45,function()
                    if generation~=M.Generation or not enabled("dodge") or c~=LP.Character then return end
                    if onCooldown(c,tool)then
                        state.Actions+=1;state.Status="DODGE! cooldown observed"
                    else state.Status="Input unconfirmed · no dodge cooldown observed"end
                    M.DodgeStatusUntil=os.clock()+3
                end)
            end)
            if not ok then M.Controllers.dodge.Status="DODGE! unavailable: "..tostring(err):sub(1,110);M.DodgeStatusUntil=os.clock()+5;warn("[DODGE INPUT ERROR] "..tostring(err))end
        end)
    end
    local function peers()
        local objects={}
        for _,p in ipairs(Players:GetPlayers())do
            local c,_,r=live(p)
            if p~=LP and c then
                objects[c]=true
                if enabled("dodge") and knifeAttacker(p)then
                    local animator=c:FindFirstChildOfClass("Humanoid") and c:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
                    if animator and not M.Animators[animator]then
                        M.Animators[animator]=animator.AnimationPlayed:Connect(function(track)
                            local id=track.Animation and track.Animation.AnimationId:match("%d+")
                            local profile=M.AttackIds and M.AttackIds[id]
                            if enabled("dodge") and profile then
                                M.Threats[p]={Track=track,Character=c,Range=profile.Range,
                                    Expires=os.clock()+math.clamp(.6/math.max(.2,track.Speed),.2,.9)}
                                -- Animation identifies a swing; the geometry poll decides whether to press.
                            end
                        end)
                    end
                end
            end
        end
        for animator,connection in pairs(M.Animators)do
            if not animator:IsDescendantOf(workspace) or not enabled("dodge")then connection:Disconnect();M.Animators[animator]=nil end
        end
        if not active()then return end
        mark("players",objects,function(c)
            local p=Players:GetPlayerFromCharacter(c)
            return p and hider(p) and colors.Blue or p and hunter(p) and colors.Red or colors.White
        end)
    end
    local function loadAttacks()
        M.AttackIds={}
        local a=RS:FindFirstChild("Animations");a=a and a:FindFirstChild("Abilities")
        local knife=a and a:FindFirstChild("Knife")
        if knife then for _,v in ipairs(knife:GetDescendants())do
            if v:IsA("Animation") and not v.Name:lower():find("victim",1,true) and (v.Name:lower():find("swing") or v.Name:lower():find("stab") or v.Name:lower():find("slash"))then
                local id=v.AnimationId:match("%d+")
                if id then M.AttackIds[id]={Range=v.Name:lower():find("lunge",1,true) and 14 or 8}end
            end
        end end
    end
    local function spikes()
        if not enabled("disablespikes")then
            restore("disablespikes");for object,cover in pairs(M.Covers)do cover:Destroy();M.Covers[object]=nil end;return
        end
        local n=0
        for object in pairs(M.Spikes)do if object:IsDescendantOf(M.Map) then
            local parent=object.Parent;local nested=false
            while parent and parent~=M.Map do if M.Spikes[parent]then nested=true;break end;parent=parent.Parent end
            if not nested then
                n+=1
                local parts=object:IsA("BasePart") and {object} or object:GetDescendants()
                for _,part in ipairs(parts)do if part:IsA("BasePart")then
                    set("disablespikes",part,"CanTouch",false);set("disablespikes",part,"CanCollide",false)
                    set("disablespikes",part,"LocalTransparencyModifier",1)
                end end
                if not M.Covers[object]then
                    local cf,size
                    if object:IsA("Model")then cf,size=object:GetBoundingBox()else cf,size=object.CFrame,object.Size end
                    if size.X<120 and size.Z<120 and size.Y<30 then
                        local cover=Instance.new("Part");cover.Name="LocalSpikeCover";cover.Anchored=true;cover.CanCollide=true
                        cover.CanTouch=false;cover.Transparency=1;cover.CastShadow=false
                        cover.Size=Vector3.new(size.X+.5,.4,size.Z+.5);cover.CFrame=cf*CFrame.new(0,size.Y*.5+.5,0)
                        cover.Parent=M.Folder;M.Covers[object]=cover
                    end
                end
            end
        end end
        M.Controllers.disablespikes.Status=n.." local spike groups disabled · server hazards may apply"
    end
    local function hitboxes()
        if not enabled("hitboxes")then restore("hitboxes");return end
        local keep,n={},0
        for _,p in ipairs(Players:GetPlayers())do
            local _,_,r=live(p)
            if p~=LP and r and (hunter(LP) and hider(p) or hider(LP) and hunter(p))then
                keep[r]=true;n+=1
                set("hitboxes",r,"Size",Vector3.new(6,6,6));set("hitboxes",r,"CanCollide",false)
                set("hitboxes",r,"Transparency",.7);set("hitboxes",r,"Color",colors.Red)
            end
        end
        local records=M.Originals.hitboxes
        if records then for object,values in pairs(records)do if not keep[object]then
            for property,record in pairs(values)do pcall(function()if object[property]==record.Value then object[property]=record.Original end end)end
            records[object]=nil
        end end end
        M.Controllers.hitboxes.Status=n.." local hitboxes · server range applies"
    end
    local function finishCollection()
        local trip=M.KeyTrip;M.KeyTrip=nil
        if not trip then return end
        if trip.Prompt then pcall(function()trip.Prompt:InputHoldEnd()end)end
        local c,_,r=live(LP)
        if c==trip.Character and r then
            c:PivotTo(trip.Origin)
            r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
        end
        M.NextKeyAt=os.clock()+.4
    end
    M.FinishCollection=finishCollection
    local function collect()
        if not enabled("collect")then finishCollection();return false end
        local c,h,r=live(LP);if not r then finishCollection();return false end
        local s=M.Controllers.collect
        local trip=M.KeyTrip
        if trip then
            M.Motion=nil
            if c~=trip.Character or not active() or not trip.Key.Parent or os.clock()>=trip.ReturnAt then
                finishCollection();s.Status="Returned from key pickup";return true
            end
            if not trip.Attempted and os.clock()>=trip.PickupAt then
                trip.Attempted=true
                local prompt=trip.Key:FindFirstChildWhichIsA("ProximityPrompt",true)
                local distance=(trip.Part.Position-r.Position).Magnitude
                if prompt and prompt.Enabled and distance<=prompt.MaxActivationDistance then
                    -- Hold through the native prompt interface without replaying its remote.
                    trip.Prompt=prompt;prompt:InputHoldBegin()
                    trip.ReturnAt=os.clock()+math.clamp(prompt.HoldDuration,0,5)+.25
                    s.Actions+=1;s.Status="Attempting dropped-key pickup"
                elseif distance<=5 and type(firetouchinterest)=="function" and trip.Part:FindFirstChildOfClass("TouchTransmitter")then
                    firetouchinterest(r,trip.Part,0);firetouchinterest(r,trip.Part,1)
                    trip.ReturnAt=os.clock()+.3;s.Actions+=1;s.Status="Attempting key touch pickup"
                else trip.ReturnAt=os.clock()+.3;s.Status="Waiting for native key pickup" end
            end
            return true
        end
        if os.clock()<(M.NextKeyAt or 0)then return true end
        if c:FindFirstChild("Ragdoll") or c:FindFirstChild("DisableMovement")then
            s.Status="Waiting for movement recovery";return true
        end
        M.KeyVisited=M.KeyVisited or setmetatable({},{__mode="k"})
        local best,part,distance=nil,nil,math.huge
        for object in pairs(M.Keys)do
            local p=object.Parent and objectPart(object)
            if p and not M.KeyVisited[object] and object:IsDescendantOf(workspace)then
                local d=(p.Position-r.Position).Magnitude
                if d<distance then best=object;part=p;distance=d end
            end
        end
        if not best then s.Status="Waiting for new dropped keys";return false end
        M.Motion=nil;M.KeyVisited[best]=true
        local now=os.clock()
        M.KeyTrip={Character=c,Origin=c:GetPivot(),Key=best,Part=part,PickupAt=now+.2,ReturnAt=now+1}
        c:PivotTo(CFrame.new(part.Position+Vector3.new(0,2.5,0))*r.CFrame.Rotation)
        r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
        s.Status="Teleported to dropped key · will return"
        return true
    end
    function M:Step()
        local any=false;for _,c in pairs(self.Controllers)do if c.Enabled then any=true;break end end
        local map=workspace:FindFirstChild("HideAndSeekMap")
        -- DODGE! is also usable in private-server lobby tests. Other HNS modes stay gated.
        if any and enabled("dodge") and (not active() or not map)then
            if self.Map then self:Reset()end
            if not self.AttackIds then loadAttacks()end
            local c=live(LP);local bag=LP:FindFirstChildOfClass("Backpack")
            local tool=c and (c:FindFirstChild("DODGE!") or bag and bag:FindFirstChild("DODGE!"))
            if tool then
                peers()
                for attacker,threat in pairs(self.Threats)do
                    if threat.Expires<=os.clock() or not threat.Track.IsPlaying then self.Threats[attacker]=nil
                    elseif aimedKnifeThreat(attacker)then evade(attacker)end
                end
                if os.clock()-(self.LastDodge or 0)>.6 and os.clock()>(self.DodgeStatusUntil or 0)then self.Controllers.dodge.Status="Watching attack-box overlap · outside Hide & Seek"end
            else self.Controllers.dodge.Status="DODGE! item required"end
            for mode,state in pairs(self.Controllers)do if mode~="dodge"and state.Enabled then state.Status="Waiting for Hide & Seek"end end
            return
        end
        if not any or not active() or not map then
            if self.Map then self:Reset()end
            for _,c in pairs(self.Controllers)do if c.Enabled then c.Status="Waiting for Hide & Seek"end end
            return
        end
        if self.Map~=map then
            self:Reset();self.Map=map;self.Folder=Instance.new("Folder");self.Folder.Name="AllenHideAndSeek";self.Folder.Parent=workspace
            watch(map);watch(workspace:FindFirstChild("Effects"));loadAttacks()
        end
        local c,h,r=live(LP)
        if enabled("stamina")then
            local value=c and c:FindFirstChild("StaminaVal")
            if value and value:IsA("NumberValue")then if value.Value<100 then value.Value=100 end;self.Controllers.stamina.Status="Client stamina kept at 100"
            else self.Controllers.stamina.Status="Waiting for native sprint stamina value"end
        end
        mark("exits",self.Exits,colors.Green);mark("doors",self.Doors,colors.Yellow)
        mark("keys",self.Keys,colors.Yellow);mark("stairs",self.Stairs,colors.White);mark("spikes",self.Spikes,colors.Red)
        peers();spikes();hitboxes()
        if not r then return end
        if enabled("dodge")then
            for attacker,threat in pairs(self.Threats)do
                if threat.Expires<=os.clock() or not threat.Track.IsPlaying then self.Threats[attacker]=nil
                elseif aimedKnifeThreat(attacker)then evade(attacker)end
            end
            if os.clock()-(self.LastDodge or 0)>.6 and os.clock()>(self.DodgeStatusUntil or 0)then self.Controllers.dodge.Status="Watching attack-box overlap · one press per swing"end
        end
        local collecting=collect()
        if not collecting and enabled("follow")then
            local target=nearest(hider,180)
            if target then local _,_,other=live(target);route("follow",target,other.Position);self.Controllers.follow.Status="Following "..target.DisplayName
            else self.Controllers.follow.Status="Waiting for nearby blue-team hider"end
        end
        if not collecting and enabled("teleport")then
            local s=self.Controllers.teleport
            if self.Teleported==c then s.Status="Teleported to hider"
            else
                local target=nearest(hider,math.huge)
                local _,_,other=target and live(target)
                -- Unpack explicitly: Lua's boolean expression only preserves the first return.
                if target then local _,_,root=live(target);other=root end
                if other then
                    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={workspace:FindFirstChild("Live") or c}
                    for _,offset in ipairs({other.CFrame.RightVector*4,-other.CFrame.RightVector*4,-other.CFrame.LookVector*4})do
                        local p=other.Position+offset
                        local hit=workspace:Raycast(p+Vector3.new(0,4,0),Vector3.new(0,-14,0),params)
                        if hit and hit.Normal.Y>.7 and not hit.Instance.Name:lower():find("spike",1,true)
                            and not workspace:Raycast(other.Position,offset,params)then
                            local point=hit.Position+Vector3.new(0,math.max(3,h.HipHeight+r.Size.Y*.5)+.2,0)
                            c:PivotTo(CFrame.lookAt(point,Vector3.new(other.Position.X,point.Y,other.Position.Z)))
                            r.AssemblyLinearVelocity=Vector3.zero;self.Teleported=c;s.Actions+=1;s.Status="Teleported near "..target.DisplayName;break
                        end
                    end
                    if self.Teleported~=c then s.Status="No safe landing beside hider"end
                else s.Status="Waiting for living hider"end
            end
        end
    end
    local renderName="AllenHNS_"..game:GetService("HttpService"):GenerateGUID(false)
    RunService:BindToRenderStep(renderName,Enum.RenderPriority.Input.Value+2,function()
        if M.Destroyed then return end
        if (not M.Map or not active()) and not enabled("dodge")then return end
        local c,h,r=live(LP);if not r then return end
        if c:FindFirstChild("Ragdoll") or c:FindFirstChild("Stun") or c:FindFirstChild("DisableMovement")then
            if M.Moving then h:Move(Vector3.zero,false);M.Moving=false end;return
        end
        if enabled("dodge") and M.EvadeUntil and os.clock()<M.EvadeUntil then h:Move(M.EvadeDirection,false);M.Moving=true;return end
        local motion=M.Motion
        if motion and enabled(motion.Owner)then
            local waypoint=motion.Waypoints[motion.Index]
            while waypoint and (r.Position-waypoint.Position).Magnitude<3 do motion.Index+=1;waypoint=motion.Waypoints[motion.Index]end
            if waypoint then
                local direction=safeDirection(waypoint.Position,r.Position)
                if direction then h:Move(direction,false);if waypoint.Action==Enum.PathWaypointAction.Jump then h.Jump=true end;M.Moving=true;return end
                M.Controllers[motion.Owner].Status="Route blocked · stopped"
            end
            M.Motion=nil
        end
        if M.Moving then h:Move(Vector3.zero,false);M.Moving=false end
    end)
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        M.Elapsed+=dt;if M.Elapsed<.1 then return end;M.Elapsed=0
        local ok,err=pcall(M.Step,M)
        if not ok then for _,c in pairs(M.Controllers)do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,110)end;M:Reset();warn("[Allen HNS] "..tostring(err))end
    end)
    function M:Create(mode)
        local key="__ALLEN_HNS_"..mode
        local previous=self.Controllers[mode];if previous then previous:SetEnabled(false);previous.Destroyed=true end
        local s={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Marks={},Actions=0}
        function s:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if mode=="collect"then
                if not self.Enabled then finishCollection()else M.KeyVisited=nil end
            end
            if mode=="teleport"then M.Teleported=nil end
            if not self.Enabled then
                clearMarks(self);restore(mode)
                if M.Motion and M.Motion.Owner==mode then M.Motion=nil end
                if mode=="dodge"then M.EvadeUntil=nil;restoreEquipment()end
            end
            local ok,err=pcall(M.Step,M)
            if not ok then self.Enabled=false;M:Reset();self.Status="Stopped: "..tostring(err):sub(1,110);error(err,0)end
            if not self.Enabled then self.Status="Off"end
        end
        function s:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Actions=self.Actions}end
        function s:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers)then M:Reset();M.Destroyed=true;M.Connection:Disconnect();RunService:UnbindFromRenderStep(renderName)
                if env.__ALLEN_HNS_MANAGER==M then env.__ALLEN_HNS_MANAGER=nil end
            end
        end
        self.Controllers[mode]=s;env[key]=s;return s
    end
end
return M:Create(MODE)

end

]====],
}
-- Allen Scripts general hub. Feature sources are bundled by the build script.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer
local env=getgenv()
if env.__ALLEN_GENERAL_HUB then env.__ALLEN_GENERAL_HUB:Destroy() end
if env.__ALLEN_SCRIPTS_HUB then env.__ALLEN_SCRIPTS_HUB:Destroy() end
local hub={Version="2026-11-03-r14",Destroyed=false,Connections={},Controllers={},Busy={},Rows={}}
local INK,FF,ROSU,DUELS,MMM,SHINDO,BFNF,FNP,BLADE,UBG=7008097940,2404080894,3405992067,10766630653,2802559498,1511883870,2443177453,10258128048,4777817887,4730278139
local gameName=game.GameId==INK and "Ink Game" or game.GameId==FF and "Funky Friday" or game.GameId==ROSU and "rosu!mania" or game.GameId==DUELS and "Funky Duels" or game.GameId==MMM and "Monday Morning Misery" or game.GameId==SHINDO and "Shindo Life" or game.GameId==BFNF and "Basically FNF: Remix" or game.GameId==FNP and "Friday Night Partying" or game.GameId==BLADE and "Blade Ball" or game.GameId==UBG and "Untitled Boxing Game" or "Other experience"
local note="Build r13 · improved boxing defense and footwork · all features OFF."
local ffFolder,ffActor
local factories={}
local function execute(name,mode)
    if mode then
        if not factories[name]then local fn,err=loadstring(SOURCES[name]);assert(fn,err);factories[name]=fn()end
        return factories[name](mode)
    end
    local fn,err=loadstring(SOURCES[name]);assert(fn,err);return fn()
end
local function localController(id,key)
    local current=hub.Controllers[id]
    if not current or current.Destroyed then current=env[key] end
    if current and not current.Destroyed and current.HubOnly and type(current.SetEnabled)=="function" then hub.Controllers[id]=current;return current end
end
local function prepareFF()
    if ffFolder and ffFolder.Parent then
        if not ffFolder:GetAttribute("Error") then return end
        ffFolder:Destroy();ffFolder=nil
    end
    assert(type(run_on_actor)=="function","This executor does not support Actor execution")
    ffActor=LP:WaitForChild("PlayerScripts"):FindFirstChild("ClientActor")
    assert(ffActor,"Funky Friday client is not ready")
    ffFolder=Instance.new("Folder");ffFolder.Name="AllenHubFFStatus";ffFolder.Parent=LP:WaitForChild("PlayerGui")
    ffFolder:SetAttribute("Ready",false)
    ffFolder:SetAttribute("DesiredEnabled",false)
    run_on_actor(ffActor,SOURCES.FFBridge)
end
local features={
    {Id="candyesp",Section="Ink Game",Category="Alerts",Name="Candy ESP",Subtitle="Orange pickup highlights and distance labels",Badge="Halloween",Game=INK,Key="__ALLEN_CANDY_ESP",Source="CandyESP"},
    {Id="halloweenshoot",Section="Ink Game",Category="Combat",Name="Halloween Auto Shoot + Ammo",Subtitle="Zombie NPCs and nearby ammo stations",Badge="Halloween",Game=INK,Key="__ALLEN_HALLOWEEN_SHOOT",Source="HalloweenShoot"},
    {Id="pa",Section="Project: Afternight",Category="Rhythm",Name="Auto Play",Subtitle="Native botplay · taps and holds · game scoring rules",Badge="New",Game=4557322431,Key="__ALLEN_PA_AUTOPLAY",Source="PA"},
    {Id="ubgcombat",Section="Untitled Boxing Game",Category="Combat",Name="Auto Combat",Subtitle="Timed counters · stamina-aware defense · safe footwork",Badge="New",Game=UBG,Key="__ALLEN_UBG_COMBAT",Source="UBGCombat"},
    {Id="remotespy",Section="Universal",Category="Alerts",Name="Remote Spy (Cobalt)",Subtitle="Cobalt inspector GUI · ON loads / OFF unloads",Badge="Developer",Key="__ALLEN_REMOTE_SPY",Source="RemoteSpy"},
    {Id="bladeparry",Section="Blade Ball",Category="Combat",Name="Auto Parry",Subtitle="Disabled after BAC anti-cheat kick",Badge="Testing",Unavailable=true,Game=BLADE,Key="__BLADE_AUTO_PARRY",Source="BladeParry"},
    {Id="bladebeep",Section="Blade Ball",Category="Alerts",Name="Red Ball Beep",Subtitle="Short sound when the ball turns red · manual parry",Badge="Blade Ball",Game=BLADE,Key="__BLADE_BALL_BEEP",Source="BladeBeep"},
    {Id="fnp",Section="Friday Night Partying",Category="Rhythm",Name="Auto Play",Subtitle="Native taps, sustains and chords · skips harmful notes",Badge="Friday Night Partying",Game=FNP,Key="__FNP_AUTOPLAY",Source="FNP"},
    {Id="bfnf",Section="Basically FNF: Remix",Category="Rhythm",Name="Auto Play",Subtitle="Native taps, holds and chords · local lanes",Badge="Basically FNF: Remix",Game=BFNF,Key="__BFNF_AUTOPLAY",Source="BFNF"},
    {Id="shindo",Section="Shindo Life",Category="Movement",Name="Auto Dodge + Auto Block",Subtitle="Native movement · automatic power guard",Badge="Shindo Life",Game=SHINDO,Key="__SHINDO_AUTO_DODGE",Source="Shindo"},
    {Id="camera",Section="Universal",Category="Aim",Name="Soft Camera Lock",Subtitle="PC only · C to lock/unlock · red highlight",Badge="PC only",PCOnly=true,Key="__INK_SOFT_CAMERA_MOBILE",Source="Camera"},
    {Id="dodge",Section="Ink Game",Category="Movement",Name="Auto Dodge",Subtitle="Disabled while investigating timeout / crash reports",Badge="Disabled",Unavailable=true,Game=INK,Key="__INK_GAME_AUTO_DODGE",Source="Dodge"},
    {Id="inkrlgl",Section="Ink Game",Category="Movement",Name="Red Light, Green Light Auto Stop",Subtitle="Manual movement · stops on red until finish",Badge="Ink Game",Game=INK,Key="__ALLEN_INK_RLGL",Source="RLGL"},
    {Id="dalgonaauto",Section="Ink Game",Category="Minigames",Name="Auto-complete Dalgona",Subtitle="Triggers native cookie completion · one attempt per cookie",Badge="Ink Game",Game=INK,Key="__ALLEN_DALGONA_auto",Source="DalgonaAuto"},
    {Id="dalgonalighter",Section="Ink Game",Category="Minigames",Name="Dalgona Lighter",Subtitle="Temporary client-side native lighter · hold to use",Badge="Ink Game",Game=INK,Key="__ALLEN_DALGONA_lighter",Source="DalgonaLighter"},
    {Id="dalgonaanticrack",Section="Ink Game",Category="Minigames",Name="Dalgona Anti-crack",Subtitle="Wrong-click protection and fear control · timer still applies",Badge="Ink Game",Game=INK,Key="__ALLEN_DALGONA_anticrack",Source="DalgonaAntiCrack"},
    {Id="glassfinish",Section="Ink Game",Category="Minigames",Name="Finish Teleport",Subtitle="Glass Bridge · finds a solid landing on the End platform",Badge="Ink Game",Game=INK,Key="__ALLEN_GLASS_finish",Source="GlassFinish"},
    {Id="glassreveal",Section="Ink Game",Category="Minigames",Name="Reveal Safe / Fake Glass",Subtitle="Glass Bridge · green: safe · red: fake",Badge="Ink Game",Game=INK,Key="__ALLEN_GLASS_reveal",Source="GlassReveal"},
    {Id="glassantifall",Section="Ink Game",Category="Minigames",Name="Anti Fall",Subtitle="Glass Bridge · local catch floor and fall recovery",Badge="Ink Game",Game=INK,Key="__ALLEN_GLASS_antifall",Source="GlassAntiFall"},
    {Id="glasswalkfake",Section="Ink Game",Category="Minigames",Name="Walk on Fake Glass",Subtitle="Glass Bridge · temporary local supports above fake panes",Badge="Ink Game",Game=INK,Key="__ALLEN_GLASS_walkfake",Source="GlassWalkFake"},
    {Id="ff",Section="Funky Friday",Category="Rhythm",Name="Auto Play",Subtitle="Taps, holds and chords · native lane timing",Badge="Funky Friday",Game=FF},
    {Id="duels",Section="Funky Duels",Category="Rhythm",Name="Auto Play",Subtitle="Native taps, holds and chords · skips hurt notes",Badge="Funky Duels",Game=DUELS,Key="__FUNKY_DUELS_AUTOPLAY",Source="Duels"},
    {Id="mmm",Section="Monday Morning Misery",Category="Rhythm",Name="Auto Play",Subtitle="Native taps and holds · local lanes",Badge="Monday Morning Misery",Game=MMM,Key="__MMM_AUTOPLAY",Source="MMM"},
    {Id="rosu",Section="rosu!mania",Category="Rhythm",Name="Auto Play",Subtitle="Native taps, holds and releases · local charts",Badge="rosu!mania",Game=ROSU,Key="__ROSU_AUTOPLAY",Source="Rosu"},
}
features[#features+1]={Id="inktug",Section="Ink Game",Category="Minigames",Name="Auto Pull",Subtitle="Tug of War · native hit-window timing",Badge="Ink Game",Game=INK,Key="__INK_TUG_AUTO_PULL",Source="Tug"}
features[#features+1]={Id="inkrope",Section="Ink Game",Category="Minigames",Name="Auto Jump",Subtitle="Jump Rope · learns first pass · manual movement",Badge="Ink Game",Game=INK,Key="__ALLEN_JUMP_ROPE",Source="JumpRope"}
for _,item in ipairs({
 {"balance","Auto Balance","Normal A/D input · executor input support required"},
 {"bridge","Bridge","Local support · requires verified Start / End platforms"},
 {"antifall","Anti Fall","Returns to last solid ground · local recovery"},
 {"fake","Fake Balance","Cosmetic indicator only · balance still applies"},
 {"cutscene","Cutscene Fall Protection","Local recovery only · cannot prevent server death"},
 {"disable","Disable Rope Locally","Hides rope / local collision · timing hazard still applies"},
 {"finish","Instant Finish Teleport","Verified landing required · server decides completion"}
})do features[#features+1]={Id="rope_"..item[1],Section="Ink Game",Category="Minigames",Name=item[2],Subtitle=item[3],Badge="Jump Rope",Game=INK,Key="__ALLEN_ROPE_"..item[1],Source="RopeUtils",Mode=item[1]}end
features[#features+1]={Id="inkqte",Section="Ink Game",Category="Minigames",Name="Auto QTE",Subtitle="Times native combat / struggle ring prompts",Badge="Ink Game",Game=INK,Key="__ALLEN_INK_AUTO_QTE",Source="AutoQTE"}
local hnsFeatures={
    {"exits","Exit ESP","Highlights Hide & Seek exits"},
    {"doors","Door ESP","Highlights key doors"},
    {"players","Player ESP","Blue: hiders · red: seekers"},
    {"keys","Dropped Key ESP","Highlights recognized dropped keys"},
    {"stairs","Stair ESP","Highlights named staircase objects"},
    {"spikes","Spike ESP","Highlights named spike hazards"},
    {"collect","Collect Dropped Keys","Teleports to each key · returns after pickup"},
    {"dodge","Auto Dodge (DODGE!)","Estimated knife-box overlap · one press per swing"},
    {"stamina","Infinite Stamina","Keeps the native client stamina value full"},
    {"follow","Follow Blue Team","Finds walkable routes to nearby hiders"},
    {"hitboxes","Expanded Hitboxes","Local enemy hitboxes · server range still applies"},
    {"teleport","Teleport to Hider","One teleport to a checked landing beside a hider"},
    {"disablespikes","Disable Spikes","Local spike changes and covers · server hazards may apply"},
}
for _,item in ipairs(hnsFeatures)do
    features[#features+1]={Id="hns_"..item[1],Section="Ink Game",Category="Minigames",Name=item[2],Subtitle=item[1]=="dodge" and "Knife + weak fists · dash prediction · one activation per swing" or item[3],Badge="Hide & Seek",Game=INK,Key="__ALLEN_HNS_"..item[1],Source=item[1]=="dodge" and "IsolatedDodge" or "HNS",Mode=item[1]~="dodge" and item[1] or nil}
end
local gameCategories={"All"}
local knownCategories={}
for _,feature in ipairs(features)do
    if not knownCategories[feature.Section]then
        knownCategories[feature.Section]=true;gameCategories[#gameCategories+1]=feature.Section
    end
end
local function snapshot(feature)
    if feature.MobileUnsupported and UIS.TouchEnabled then return {Enabled=false,Status="Disabled on mobile after crash report"}end
    if feature.PCOnly and not UIS.KeyboardEnabled then return {Enabled=false,Status="PC only"} end
    if feature.Unavailable then return {Enabled=false,Status="Unavailable"} end
    if feature.Game and feature.Game~=game.GameId then return {Enabled=false,Status="Open "..feature.Section} end
    if feature.Id=="ff" then
        if not ffFolder or not ffFolder.Parent then return {Enabled=false,Status="Not loaded"} end
        return {Enabled=ffFolder:GetAttribute("Enabled")==true,Status=ffFolder:GetAttribute("Status") or "Loading engine",
            Hits=ffFolder:GetAttribute("Hits"),Ready=ffFolder:GetAttribute("Ready")}
    end
    local current=localController(feature.Id,feature.Key)
    if not current then return {Enabled=false,Status="Not loaded"} end
    if type(current.GetSnapshot)=="function" then
        local ok,value=pcall(current.GetSnapshot,current)
        if ok then value.Status=value.Status or value.LastReason or (value.Enabled and "On" or "Off");value.Hits=value.Hits or value.Presses;return value end
    end
    return {Enabled=current.Enabled==true,Status=current.Enabled and "On" or "Off"}
end
local function change(feature)
    if hub.Destroyed or hub.Busy[feature.Id] then return end
    if feature.PCOnly and not UIS.KeyboardEnabled then note="This aimlock is PC only.";return end
    if feature.MobileUnsupported and UIS.TouchEnabled then note="This feature is disabled on mobile after crash reports.";return end
    if feature.Unavailable then note="This script has not been completed.";return end
    if feature.Game and feature.Game~=game.GameId then note="Open "..feature.Section.." to use this feature.";return end
    hub.Busy[feature.Id]=true
    task.spawn(function()
        local ok,err=pcall(function()
            if feature.Id=="ff" then
                prepareFF()
                local deadline=os.clock()+12
                while not hub.Destroyed and ffFolder.Parent and not ffFolder:GetAttribute("Ready") and not ffFolder:GetAttribute("Error") and os.clock()<deadline do task.wait(.1) end
                if hub.Destroyed then return end
                assert(ffFolder:GetAttribute("Ready"),ffFolder:GetAttribute("Error") or "Autoplay engine did not initialize")
                ffFolder:SetAttribute("DesiredEnabled",not ffFolder:GetAttribute("DesiredEnabled"))
            else
                local current=localController(feature.Id,feature.Key)
                if not current then
                    local loaded=execute(feature.Source,feature.Mode)
                    if type(loaded)=="table" and type(loaded.SetEnabled)=="function" and loaded.HubOnly then
                        hub.Controllers[feature.Id]=loaded
                    end
                    current=localController(feature.Id,feature.Key)
                end
                assert(current,"Feature did not initialize")
                if hub.Destroyed then current:Destroy();return end
                if current.Gui then current.Gui.Enabled=false end
                current:SetEnabled(not snapshot(feature).Enabled)
            end
            note=feature.Name.." updated."
        end)
        if not ok then note=tostring(err):sub(1,140);warn("[Allen Scripts] "..tostring(err)) end
        hub.Busy[feature.Id]=nil
    end)
end
-- Black tabbed library, inspired by the visible Ringta window layout.
local C={BG=Color3.fromRGB(7,7,8),Panel=Color3.fromRGB(13,13,15),Card=Color3.fromRGB(23,23,26),
    Selected=Color3.fromRGB(31,31,35),Line=Color3.fromRGB(39,39,43),Text=Color3.fromRGB(242,242,245),
    Muted=Color3.fromRGB(145,145,155),Accent=Color3.fromRGB(230,230,235)}
local function create(class,props,parent)
    local o=Instance.new(class);for k,v in pairs(props)do o[k]=v end;o.Parent=parent;return o
end
local function rounded(o,r)create("UICorner",{CornerRadius=UDim.new(0,r)},o);return o end
local function label(parent,value,size)
    return create("TextLabel",{Text=value,Font=Enum.Font.Gotham,TextSize=size or 13,TextColor3=C.Text,
        TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1,BorderSizePixel=0},parent)
end
local function button(parent,value)
    return rounded(create("TextButton",{Text=value,Font=Enum.Font.Gotham,TextSize=14,TextColor3=C.Text,
        BackgroundColor3=C.Card,AutoButtonColor=false,BorderSizePixel=0},parent),8)
end
local function place(o,x,y,w,h)o.Position=UDim2.fromOffset(x,y);o.Size=UDim2.fromOffset(w,h)end
local function connect(signal,fn)local c=signal:Connect(fn);hub.Connections[#hub.Connections+1]=c;return c end
local gui=create("ScreenGui",{Name="AllenScriptsGeneralHub",ResetOnSpawn=false,IgnoreGuiInset=false,DisplayOrder=1000010},nil)
pcall(function()gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets end)
local mounted=false
if type(gethui)=="function" then mounted=pcall(function()gui.Parent=gethui();assert(gui.Parent)end)end
if not mounted then gui.Parent=LP:WaitForChild("PlayerGui")end
hub.Gui=gui
local root=create("Frame",{Name="SafeArea",BackgroundTransparency=1,Size=UDim2.fromScale(1,1)},gui)
local window=rounded(create("Frame",{Name="Window",BackgroundColor3=C.BG,BorderSizePixel=0,Size=UDim2.fromOffset(720,520)},root),16)
create("UIStroke",{Color=C.Line,Thickness=1},window)
local header=create("Frame",{Name="DragHandle",BackgroundTransparency=1,Active=true},window)
local logo=label(window,"◇",30)
local title=label(window,"ALLEN SCRIPTS",15);title.Font=Enum.Font.GothamBold
local subtitle=label(window,"SCRIPT LIBRARY · BUILD R13",10);subtitle.TextColor3=C.Muted
local minimize=button(window,"—");minimize.Name="Minimize"
local maximize=button(window,"□");maximize.Name="Maximize"
local close=button(window,"×");close.Name="Close"
for _,b in ipairs({minimize,maximize,close})do b.BackgroundTransparency=1;b.TextSize=19 end
local launcher=button(root,"AS");launcher.Name="OpenHub";launcher.Font=Enum.Font.GothamBold
place(launcher,18,220,46,46)
create("UIStroke",{Color=C.Line,Thickness=1},launcher)
local gameSelect=button(window,gameName.."  v");gameSelect.Name="ChooseGame";gameSelect.TextSize=12
launcher.Visible=false
connect(window:GetPropertyChangedSignal("Visible"),function()launcher.Visible=not window.Visible end)
local tabsButton=button(window,"Tabs");tabsButton.Name="OpenTabs"
local sidebar=create("ScrollingFrame",{Name="Tabs",BackgroundTransparency=1,BorderSizePixel=0,
    ScrollBarThickness=3,ScrollBarImageColor3=C.Muted,Active=true,ScrollingEnabled=true,
    ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.new()},window)
local navCaption=label(sidebar,"FEATURES",10);navCaption.TextColor3=C.Muted
local panel=rounded(create("Frame",{Name="ContentPanel",BackgroundColor3=C.Panel,BorderSizePixel=0},window),12)
local pageIcon=label(panel,"◇",19)
local pageTitle=label(panel,"Home",15);pageTitle.Font=Enum.Font.GothamMedium
local pageLine=create("Frame",{BackgroundColor3=C.Line,BorderSizePixel=0},panel)
local search=rounded(create("TextBox",{Name="Search",Text="",PlaceholderText="Search games or scripts…",ClearTextOnFocus=false,
    BackgroundColor3=C.BG,BorderSizePixel=0,TextColor3=C.Text,PlaceholderColor3=C.Muted,TextSize=12,
    TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Gotham},panel),8)
create("UIPadding",{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,36)},search)
local clearSearch=button(panel,"×");clearSearch.BackgroundTransparency=1
local results=label(panel,"Main Features",12);results.TextColor3=C.Muted
local scroll=create("ScrollingFrame",{Name="Features",BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,
    ScrollBarImageColor3=C.Muted,Active=true,ScrollingEnabled=true,ScrollingDirection=Enum.ScrollingDirection.Y,
    AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()},panel)
create("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},scroll)
create("UIPadding",{PaddingBottom=UDim.new(0,10)},scroll)
local empty=label(panel,"No matching scripts",13);empty.TextColor3=C.Muted;empty.TextXAlignment=Enum.TextXAlignment.Center
local footer=label(window,"All features start OFF",10);footer.TextColor3=C.Muted;footer.TextTruncate=Enum.TextTruncate.AtEnd
local dismiss=create("TextButton",{Name="DismissMenu",Text="",BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.25,
    Size=UDim2.fromScale(1,1),Visible=false,BorderSizePixel=0,ZIndex=20},window)
local gameMenu=rounded(create("ScrollingFrame",{Name="Games",BackgroundColor3=C.Panel,BorderSizePixel=0,
    ScrollBarThickness=4,Active=true,ScrollingEnabled=true,ScrollingDirection=Enum.ScrollingDirection.Y,
    Visible=false,ZIndex=30,CanvasSize=UDim2.fromOffset(0,#gameCategories*44+12)},window),10)
create("UIStroke",{Color=C.Line,Thickness=1},gameMenu)
local categoryButtons,sectionButtons,navButtons={},{},{}
local selectedGame=knownCategories[gameName] and gameName or "All"
local selectedTab="Home"
local compact,drawerOpen,gamesOpen,expanded=false,false,false,false
local panelWidth,panelHeight=720,520
local panelPosition,availableSize,previewSize,previewTouch
local render,layout,buildNavigation
local function matches(feature,query,onlyCurrent,universe)
    if onlyCurrent and feature.Game and feature.Game~=universe then return false end
    local hay=(feature.Section.." "..feature.Name.." "..feature.Subtitle.." "..feature.Category):lower():gsub("[^%w]","")
    for term in query:lower():gmatch("%w+")do if not hay:find(term,1,true)then return false end end
    return true
end
local function inTab(f)
    if selectedTab=="Home" then return true end
    if selectedTab=="Red Light" then return f.Id=="inkrlgl" end
    if selectedTab=="Dalgona" then return f.Id:sub(1,7)=="dalgona" end
    if selectedTab=="Glass Bridge" then return f.Id:sub(1,5)=="glass" end
    if selectedTab=="Hide & Seek" then return f.Id:sub(1,4)=="hns_" or f.Id=="inkqte" end
    if selectedTab=="Auto QTE" then return f.Id=="inkqte" end
    if selectedTab=="Jump Rope" then return f.Id=="inkrope" or f.Id:sub(1,5)=="rope_" end
    if selectedTab=="Tug of War" then return f.Id=="inktug" end
    return f.Category==selectedTab
end
local function chooseGame(name)
    if name~="All" and not knownCategories[name] then return end
    selectedGame=name;selectedTab="Home";gamesOpen=false;drawerOpen=false
    search.Text="";scroll.CanvasPosition=Vector2.zero
    buildNavigation();layout();render()
end
for index,name in ipairs(gameCategories)do
    local b=button(gameMenu,name=="All" and "All games" or name)
    place(b,6,6+(index-1)*44,218,40);b.ZIndex=31;b.TextXAlignment=Enum.TextXAlignment.Left
    create("UIPadding",{PaddingLeft=UDim.new(0,12)},b)
    categoryButtons[name]=b
    connect(b.Activated,function()chooseGame(name)end)
end
buildNavigation=function()
    for _,b in ipairs(navButtons)do b:Destroy()end
    table.clear(navButtons);table.clear(sectionButtons)
    local tabs={{"Home","◇"}}
    if selectedGame=="Ink Game" then
        tabs[#tabs+1]={"Red Light","◉"};tabs[#tabs+1]={"Dalgona","◇"};tabs[#tabs+1]={"Glass Bridge","◇"};tabs[#tabs+1]={"Hide & Seek","◇"};tabs[#tabs+1]={"Tug of War","◇"};tabs[#tabs+1]={"Jump Rope","◇"};tabs[#tabs+1]={"Auto QTE","◇"};tabs[#tabs+1]={"Movement","↗"}
    else
        for _,name in ipairs({"Aim","Movement","Rhythm","Alerts","Combat","Minigames"})do
            local found=false
            for _,f in ipairs(features)do if f.Category==name and (selectedGame=="All" or f.Section==selectedGame)then found=true;break end end
            if found then tabs[#tabs+1]={name,"◇"} end
        end
    end
    for index,item in ipairs(tabs)do
        local name=item[1]
        local b=button(sidebar,item[2].."   "..name)
        b.TextXAlignment=Enum.TextXAlignment.Left;b.BackgroundTransparency=1
        create("UIPadding",{PaddingLeft=UDim.new(0,12)},b)
        b.Name="Tab_"..name;navButtons[#navButtons+1]=b;sectionButtons[name]=b
        connect(b.Activated,function()
            selectedTab=name;drawerOpen=false;search.Text="";scroll.CanvasPosition=Vector2.zero;render()
        end)
    end
    sidebar.CanvasSize=UDim2.fromOffset(0,36+#navButtons*44)
end
for index,feature in ipairs(features)do
    local card=rounded(create("Frame",{Name=feature.Id,BackgroundColor3=C.Card,BorderSizePixel=0,
        LayoutOrder=index,Size=UDim2.new(1,-6,0,96)},scroll),10)
    local name=label(card,feature.Name,14);name.Font=Enum.Font.GothamMedium;name.TextWrapped=true
    local desc=label(card,feature.Subtitle,11);desc.TextColor3=C.Muted;desc.TextWrapped=true
    local state=label(card,"Off",11);state.TextColor3=C.Muted;state.TextTruncate=Enum.TextTruncate.AtEnd
    local toggle=rounded(create("TextButton",{Name="Switch",Text="",AutoButtonColor=false,BackgroundColor3=C.Line,BorderSizePixel=0},card),16)
    local knob=rounded(create("Frame",{Name="Thumb",BackgroundColor3=C.Text,BorderSizePixel=0},toggle),12)
    toggle:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(1,0)
    knob:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(1,0)
    local caption=label(card,"OFF",9);caption.TextXAlignment=Enum.TextXAlignment.Center;caption.TextColor3=C.Muted
    hub.Rows[#hub.Rows+1]={Feature=feature,Card=card,Title=name,Description=desc,State=state,Toggle=toggle,Knob=knob,Label=caption}
    connect(toggle.Activated,function()change(feature);render()end)
end
render=function()
    gameSelect.Text=(selectedGame=="All" and "All games" or selectedGame).."  v"
    local query=search.Text
    pageTitle.Text=query~="" and "Search results" or selectedTab=="Home" and (selectedGame=="All" and "Home" or selectedGame) or selectedTab
    local n=0
    for _,row in ipairs(hub.Rows)do
        local f=row.Feature
        row.Card.Visible=matches(f,query,false,game.GameId) and (query~="" or ((selectedGame=="All" or f.Section==selectedGame) and inTab(f)))
        if row.Card.Visible then n+=1 end
        local q=snapshot(f);local busy=hub.Busy[f.Id]
        local unavailable=f.Unavailable or f.MobileUnsupported and UIS.TouchEnabled or f.PCOnly and not UIS.KeyboardEnabled or f.Game and f.Game~=game.GameId
        row.Toggle.BackgroundColor3=q.Enabled and C.Accent or C.Line
        row.Knob.BackgroundColor3=q.Enabled and C.BG or unavailable and C.Muted or C.Text
        row.Knob.Position=UDim2.fromOffset(q.Enabled and row.OnX or 4,4)
        row.Label.Text=busy and "…" or unavailable and "N/A" or q.Enabled and "ON" or "OFF"
        row.Toggle.Active=not unavailable and not busy
        row.State.Text=busy and "Loading…" or (q.Status or "Off")..(q.Hits and " · "..q.Hits.." hits" or "")
    end
    for name,b in pairs(sectionButtons)do
        b.BackgroundTransparency=selectedTab==name and 0 or 1
        b.BackgroundColor3=C.Selected;b.TextColor3=selectedTab==name and C.Text or C.Muted
    end
    for name,b in pairs(categoryButtons)do b.BackgroundColor3=selectedGame==name and C.Selected or C.Panel end
    results.Text=(query=="" and "Main Features" or "Search Results").."  ·  "..n
    empty.Visible=n==0;clearSearch.Visible=query~=""
    gameMenu.Visible=gamesOpen
    sidebar.Visible=not compact or drawerOpen
    sidebar.BackgroundColor3=compact and C.Panel or C.BG
    sidebar.BackgroundTransparency=compact and 0 or 1
    sidebar.ZIndex=compact and 30 or 1
    for _,o in ipairs(sidebar:GetDescendants())do if o:IsA("GuiObject")then o.ZIndex=compact and 31 or 2 end end
    dismiss.Visible=gamesOpen or compact and drawerOpen
    footer.Text=note
end
local function positionPanel(position)
    local size=availableSize or root.AbsoluteSize
    panelPosition=Vector2.new(math.clamp(position.X,8,math.max(8,size.X-panelWidth-8)),math.clamp(position.Y,8,math.max(8,size.Y-panelHeight-8)))
    window.Position=UDim2.fromOffset(panelPosition.X,panelPosition.Y)
end
layout=function()
    local size=previewSize or root.AbsoluteSize
    if size.X<200 or size.Y<200 then return end
    if not previewSize and UIS.OnScreenKeyboardVisible and UIS.OnScreenKeyboardPosition.Y>root.AbsolutePosition.Y+200 then
        size=Vector2.new(size.X,math.min(size.Y,UIS.OnScreenKeyboardPosition.Y-root.AbsolutePosition.Y))
    end
    availableSize=size
    compact=previewSize and previewTouch or UIS.TouchEnabled or size.X<760 or size.Y<600
    local w,h
    if compact then w=math.min(430,size.X-20);h=math.min(430,size.Y-28,math.floor(size.Y*.9))
    else w=expanded and math.min(940,size.X-32) or 720;h=expanded and math.min(700,size.Y-32) or 520 end
    panelWidth,panelHeight=w,h;window.Size=UDim2.fromOffset(w,h)
    place(header,0,0,w-142,58);place(logo,18,14,30,32)
    place(title,55,14,w-205,20);place(subtitle,55,34,w-205,16)
    local control=compact and 38 or 32
    place(minimize,w-control*3-12,12,control,control);place(maximize,w-control*2-8,12,control,control);place(close,w-control-4,12,control,control)
    tabsButton.Visible=compact
    local px,py,pw,ph
    if compact then
        place(gameSelect,12,64,w-116,38);place(tabsButton,w-96,64,84,38)
        place(sidebar,12,112,190,h-150);place(navCaption,12,8,160,20)
        px,py,pw,ph=10,112,w-20,h-126
        place(gameMenu,12,106,230,math.min(300,h-122))
    else
        place(gameSelect,14,76,186,36);place(sidebar,10,126,194,h-164);place(navCaption,12,4,165,20)
        px,py,pw,ph=214,70,w-228,h-106
        place(gameMenu,14,116,230,math.min(330,h-132))
    end
    for index,b in ipairs(navButtons)do place(b,4,32+(index-1)*44,compact and 180 or 186,38)end
    place(panel,px,py,pw,ph)
    place(pageIcon,16,11,22,26);place(pageTitle,44,11,pw-60,26);place(pageLine,0,47,pw,1)
    place(search,14,60,pw-28,36);place(clearSearch,pw-46,62,30,32)
    place(results,16,105,pw-32,20)
    place(scroll,14,135,pw-24,math.max(12,ph-145));place(empty,20,135,pw-40,50)
    place(footer,16,h-28,w-32,18)
    results.Visible=not compact
    if compact then
        place(pageIcon,12,7,22,24);place(pageTitle,38,7,pw-50,24);place(pageLine,0,37,pw,1)
        place(search,12,46,pw-24,32);place(clearSearch,pw-44,46,30,32)
        place(scroll,12,90,pw-22,math.max(12,ph-98));place(empty,18,90,pw-36,40)
        place(footer,16,h-13,w-32,12);footer.TextSize=9
    else footer.TextSize=10 end
    local cw=pw-30
    for _,row in ipairs(hub.Rows)do
        local rh=compact and 110 or 104
        row.Card.Size=UDim2.new(1,-6,0,rh)
        place(row.Title,14,9,cw-88,compact and 34 or 34);row.Title.TextSize=compact and 14 or 16
        place(row.Description,14,compact and 45 or 44,cw-90,compact and 30 or 30);row.Description.TextSize=compact and 11 or 12
        place(row.State,14,rh-23,cw-28,16)
        local sw,sh=compact and 56 or 48,compact and 44 or 28
        place(row.Toggle,cw-sw-12,compact and 43 or 40,sw,sh);place(row.Label,cw-sw-12,17,sw,15)
        row.Knob.Size=UDim2.fromOffset(sh-8,sh-8);row.OnX=sw-sh+4
    end
    positionPanel(panelPosition or Vector2.new((size.X-w)/2,(size.Y-h)/2))
    render()
end
connect(search:GetPropertyChangedSignal("Text"),function()scroll.CanvasPosition=Vector2.zero;render()end)
connect(clearSearch.Activated,function()search.Text="";search:ReleaseFocus()end)
connect(gameSelect.Activated,function()gamesOpen=not gamesOpen;drawerOpen=false;render()end)
connect(tabsButton.Activated,function()drawerOpen=not drawerOpen;gamesOpen=false;render()end)
connect(dismiss.Activated,function()drawerOpen=false;gamesOpen=false;render()end)
connect(minimize.Activated,function()window.Visible=false end)
connect(maximize.Activated,function()expanded=not expanded;panelPosition=nil;layout()end)
connect(close.Activated,function()hub:Destroy()end)
connect(launcher.Activated,function()window.Visible=not window.Visible end)
local drag
connect(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        drag={Input=input,Start=input.Position,Position=panelPosition or Vector2.zero}
    end
end)
connect(UIS.InputChanged,function(input)
    if drag and (input==drag.Input or drag.Input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)then
        local d=input.Position-drag.Start;positionPanel(drag.Position+Vector2.new(d.X,d.Y))
    end
end)
connect(UIS.InputEnded,function(input)
    if drag and (input==drag.Input or input.UserInputType==Enum.UserInputType.MouseButton1 and drag.Input.UserInputType==Enum.UserInputType.MouseButton1)then drag=nil end
end)
connect(UIS.WindowFocusReleased,function()drag=nil end)
connect(UIS.InputBegan,function(input,processed)
    if processed or UIS:GetFocusedTextBox()then return end
    if input.KeyCode==Enum.KeyCode.RightShift then window.Visible=not window.Visible
    elseif input.KeyCode==Enum.KeyCode.C and UIS.KeyboardEnabled then
        for _,f in ipairs(features)do if f.Id=="camera" then change(f);break end end
    end
end)
function hub:Destroy()
    if self.Destroyed then return end
    self.Destroyed=true
    for _,c in ipairs(self.Connections)do c:Disconnect()end
    for _,c in pairs(self.Controllers)do if not c.Destroyed then pcall(c.Destroy,c)end end
    if ffFolder then ffFolder:Destroy();ffFolder=nil end
    gui:Destroy()
    if env.__ALLEN_GENERAL_HUB==self then env.__ALLEN_GENERAL_HUB=nil end
end
for _,f in ipairs(features)do
    local c=f.Key and env[f.Key]
    if c and type(c.Destroy)=="function" then pcall(c.Destroy,c)end
end
if game.GameId==FF and type(run_on_actor)=="function" then
    local actor=LP:WaitForChild("PlayerScripts"):FindFirstChild("ClientActor")
    if actor then run_on_actor(actor,[[local s=getgenv().__FF_AUTOPLAY;if s and not s.Destroyed then s:Destroy()end]])end
end
env.__ALLEN_GENERAL_HUB=hub
hub.Features=features;hub.Search=search;hub.Matches=matches;hub.CategoryButtons=categoryButtons;hub.SectionButtons=sectionButtons
hub.SelectGame=function(_,name)chooseGame(name)end
hub.SelectTab=function(_,name)if sectionButtons[name]then selectedTab=name;search.Text="";scroll.CanvasPosition=Vector2.zero;render()end end
hub.PreviewLayout=function(_,width,height)previewSize=Vector2.new(width,height);previewTouch=true;panelPosition=nil;layout()end
hub.RestoreLayout=function()previewSize=nil;previewTouch=nil;panelPosition=nil;layout()end
hub.GetFeatureSnapshot=function(_,id)for _,f in ipairs(features)do if f.Id==id then return snapshot(f)end end end
buildNavigation();layout()
task.defer(layout)
task.spawn(function()
    local size,keyboard
    while not hub.Destroyed do
        if window.Visible then render()end
        if root.AbsoluteSize~=size or keyboard~=UIS.OnScreenKeyboardVisible then size=root.AbsoluteSize;keyboard=UIS.OnScreenKeyboardVisible;layout()end
        task.wait(.25)
    end
end)
print("[Allen Scripts] Black tabbed hub loaded; features OFF.")

