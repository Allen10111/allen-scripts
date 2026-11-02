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

