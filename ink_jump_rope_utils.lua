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
