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

