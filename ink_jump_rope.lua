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

