-- Ink Game Red Light, Green Light: native walking and automatic stopping.
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
function Policy.Action(active,light,hasCharacter,hasTarget,distance)
    if not active or not hasCharacter then return "idle" end
    if light~="green" then return "stop" end
    if not hasTarget then return "stop" end
    if distance<=6 then return "arrived" end
    return "run"
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
local controls,controlsWereEnabled,managing=false,nil,false
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
        if controls and controlsWereEnabled then pcall(function() controls:Enable() end) end
    end
    managing=false;controlsWereEnabled=nil
end
local function takeControls()
    if managing then return true end
    assert(controls and type(controls.Disable)=="function","Native player controls are unavailable")
    -- The default ControlModule exposes enabled; do not enable controls another system disabled.
    if controls.enabled==false then State.Status="Waiting for native movement controls";return false end
    controlsWereEnabled=true
    controls:Disable();managing=true
    return true
end
local function setLight(value,source)
    if not value then return end
    local changed=State.Light~=value
    State.Light=value;State.Source=source
    if value~="green" and active() then
        local _,h,r=character()
        if takeControls() then stop(h,r) end
        if value=="red" and changed then State.Stops+=1 end
    elseif value=="over" then release() end
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
local function destination(r)
    local doll=workspace:FindFirstChild("SQUIDDOLL123")
    if not doll then return end
    local point
    if doll:IsA("Model") then point=doll:GetPivot().Position
    elseif doll:IsA("BasePart") then point=doll.Position end
    if not point or math.abs(point.Y-r.Position.Y)>150 then return end
    point=Vector3.new(point.X,r.Position.Y,point.Z)
    local distance=(point-r.Position).Magnitude
    -- Prevent movement toward an unrelated distant map or a lobby prop.
    if distance>2500 then return end
    return point,distance
end
local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true
local function step()
    if not active() then
        release()
        State.Status=State.Enabled and (State.Light=="over" and "Round ended" or "Waiting for Red Light, Green Light") or "Off"
        return
    end
    local c,h,r=character()
    if not c then release();State.Status="Waiting for character";return end
    if not takeControls() then return end
    if c:FindFirstChild("Ragdoll") or c:FindFirstChild("Stun") or c:FindFirstChild("DisableMovement") then
        stop(h,r);State.Status="Waiting for movement recovery";return
    end
    local point,distance=destination(r)
    local action=Policy.Action(true,State.Light,true,point~=nil,distance or math.huge)
    if action~="run" then
        stop(h,r)
        State.Status=action=="arrived" and "Doll area reached · waiting for round result"
            or State.Light=="red" and "Red light · stopped"
            or State.Light=="unknown" and "Waiting for a confirmed green light"
            or "Waiting for the native doll target"
        return
    end
    local direction=(point-r.Position).Unit
    rayParams.FilterDescendantsInstances={workspace:FindFirstChild("Live") or c,workspace:FindFirstChild("Effects") or c}
    local floor=workspace:Raycast(r.Position+direction*5,Vector3.new(0,-12,0),rayParams)
    local wall=workspace:Raycast(r.Position,direction*4,rayParams)
    if not floor or wall then stop(h,r);State.Status="Route blocked · stopped";return end
    h:Move(direction,false)
    State.Status="Green light · walking toward finish"
end
function State:SetEnabled(value)
    if self.Destroyed then return end
    value=value==true
    if self.Enabled==value then return end
    if value then
        local ps=LP:FindFirstChild("PlayerScripts")
        local module=ps and ps:FindFirstChild("PlayerModule")
        assert(module,"Native PlayerModule is not ready")
        controls=require(module):GetControls()
        assert(controls and type(controls.Disable)=="function" and type(controls.Enable)=="function","Native movement control is unavailable")
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

