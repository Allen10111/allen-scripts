-- Allen Scripts: Blade Ball native parry controller, hub only.
error("Auto Parry disabled after a reported Roblox crash; do not run this experimental build")
assert(game.GameId==4777817887,"Open Blade Ball")
assert(type(getconnections)=="function"and debug and type(debug.getupvalues)=="function","Executor needs getconnections and debug.getupvalues")
local LP=game:GetService("Players").LocalPlayer
local env=getgenv()
if env.__BLADE_AUTO_PARRY then env.__BLADE_AUTO_PARRY:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Connections={},Balls={},Requests=0,Successes=0,Errors=0,NextRequest=0,Status="Off"}
local function native()
    local gui=LP:FindFirstChild("PlayerGui")
    local hotbar=gui and gui:FindFirstChild("Hotbar")
    if not hotbar then return end
    for _,name in ipairs({"Block","NewBlockButton"})do
        local button=hotbar:FindFirstChild(name)
        if button then
            for _,signal in ipairs({button.Activated,button.MouseButton1Up})do
                for _,c in ipairs(getconnections(signal))do
                    local f=c.Function
                    if f and debug.info(f,"s"):find("SwordsController",1,true)then
                        local fn=debug.getupvalues(f)[1]
                        if type(fn)=="function"then return fn end
                    end
                end
            end
        end
    end
end
local function invoke(fn)
    local gi=getthreadidentity or getidentity;local si=setthreadidentity or setidentity
    local identity=gi and gi();if si and identity then si(2)end
    local ok,result=pcall(fn)
    if si and identity then si(identity)end
    if not ok then error(result,0)end
    return result
end
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
        self.NextRequest=now+.10
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

