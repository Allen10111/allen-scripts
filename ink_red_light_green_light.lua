-- Ink Game Red Light, Green Light: automatic stopping on red only.
-- Read-only light events; no outgoing remotes, raw keypresses or map indexing.
local Policy=(function()
local Policy={}
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
local function active()
    if not State.Enabled or State.Light=="over" or LP:GetAttribute("IsGuard") then return false end
    if workspace:GetAttribute("RLGLOVER") then return false end
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
        State.Status=State.Enabled and (State.Light=="over" and "Round ended" or "Waiting for Red Light, Green Light") or "Off"
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
    return {Enabled=self.Enabled,Status=self.Status,Light=self.Light,Stops=self.Stops,Signal=self.Source}
end
function State:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    RunService:UnbindFromRenderStep(renderName)
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
connect(LP.CharacterAdded,function()
    release();State.Light="unknown";image=nil
    if imageConnection then imageConnection:Disconnect();imageConnection=nil end
end)
local values=workspace:FindFirstChild("Values")
local current=values and values:FindFirstChild("CurrentGame")
if current then connect(current.Changed,function()
    release();State.Light="unknown";image=nil
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

