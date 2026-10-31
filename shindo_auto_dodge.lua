-- Allen Scripts: Shindo Life native local movement evasions. Hub controlled, starts OFF.
-- Combat values and projectile motion are replicated evidence; range envelopes
-- are defensive heuristics, not a copy of server hitboxes or invulnerability.
if game.GameId ~= 1511883870 then return end
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local LP=Players.LocalPlayer
local env=getgenv()
if env.__SHINDO_AUTO_DODGE then env.__SHINDO_AUTO_DODGE:Destroy() end
local S={Enabled=false,HubOnly=true,Destroyed=false,Connections={},Watchers={},Projectiles={},
    Threats={},Replay={},Requests=0,Acknowledged=0,Errors=0,Detected=0,NextRequest=0,
    Status="Off",Generation=0,NextScan=0,NextTick=0,LastHit="None",Version=1}
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
    local folder=workspace:FindFirstChild("projectileparent")
    if not folder or not part:IsA("BasePart") or part.Name:lower():find("mouse",1,true)
        or ownProjectile(part,folder) or self.Projectiles[part] then return end
    if not ownerOf(part,folder) and not part:FindFirstChildOfClass("TouchTransmitter")then return end
    local count=0;for _ in pairs(self.Projectiles)do count+=1 end
    if count>=160 then return end
    self.Projectiles[part]={Position=part.Position,At=os.clock()}
end
local function addThreat(w,kind)
    if not S.Enabled or w.Character==LP.Character then return end
    local _,_,root=localParts();local r=w.Root
    if not root or not r or not r.Parent then return end
    local distance=(root.Position-r.Position).Magnitude
    if distance>(kind=="Jutsu" and 36 or 24)then return end
    -- A cast signals possible danger, not a verified target or server hitbox.
    -- Only nearby forward-facing casts are considered without a projectile.
    if distance>5 and flat(r.CFrame.LookVector):Dot(flat(root.Position-r.Position))<0.25 then return end
    S.Threats[w.Character]={Root=r,Kind=kind,Until=os.clock()+(kind=="Jutsu" and .65 or .4),
        Range=kind=="Jutsu" and 24 or 12,Created=os.clock()}
    S.Detected+=1;log("attack",{Name=w.Character.Name,Source=kind,Distance=distance})
    S.NextTick=0
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
            end)
        end
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
    local folder=workspace:FindFirstChild("projectileparent")
    if folder~=self.ProjectileFolder then
        if self.ProjectileConnection then self.ProjectileConnection:Disconnect()end
        self.ProjectileFolder=folder;table.clear(self.Projectiles)
        if folder then
            self.ProjectileConnection=folder.DescendantAdded:Connect(function(x)self:RememberProjectile(x)end)
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
    for c,t in pairs(self.Threats)do
        if now>t.Until or not t.Root.Parent then self.Threats[c]=nil
        else
            local relative=t.Root.Position-root.Position
            local velocity=t.Root.AssemblyLinearVelocity-root.AssemblyLinearVelocity
            local gap,eta=self:ClosestApproach(relative,velocity,.25,t.Range+2)
            local forward=flat(t.Root.CFrame.LookVector):Dot(flat(-relative))
            if gap<=0 and (relative.Magnitude<5 or forward>.15)then
                dangers[#dangers+1]={Position=t.Root.Position,Velocity=t.Root.AssemblyLinearVelocity,
                    Radius=t.Range,Source=t.Kind,ETA=eta}
            end
        end
    end
    for part,sample in pairs(self.Projectiles)do
        if not part.Parent or not part:IsDescendantOf(self.ProjectileFolder)then self.Projectiles[part]=nil
        else
            local position=part.Position;local dt=now-sample.At
            local measured=dt>.008 and (position-sample.Position)/dt or sample.Velocity or ZERO
            local velocity=part.AssemblyLinearVelocity
            if part.Anchored or velocity.Magnitude<2 then velocity=measured end
            sample.Position=position;sample.At=now;sample.Velocity=velocity
            local relative=position-root.Position
            if relative.Magnitude<140 and not ownProjectile(part,self.ProjectileFolder)then
                local radius=math.clamp(part.Size.Magnitude*.5,1,30)+2.5
                local relativeVelocity=velocity-root.AssemblyLinearVelocity
                local gap,eta=self:ClosestApproach(relative,relativeVelocity,.3,radius)
                if gap<=0 and (relative.Magnitude<=radius or relative:Dot(relativeVelocity)<-1)then
                    dangers[#dangers+1]={Position=position,Velocity=velocity,Radius=radius,
                        Source="Projectile",ETA=eta}
                end
            end
        end
    end
    table.sort(dangers,function(a,b)return a.ETA<b.ETA end)
    return dangers
end
function S:Plan(root,humanoid,dangers,character)
    local away=flat(root.Position-dangers[1].Position)
    local side=Vector3.new(-away.Z,0,away.X)
    local dirs={away,side,-side,flat(away+side),flat(away-side),flat(humanoid.MoveDirection)}
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    local exclude={character,self.ProjectileFolder,workspace:FindFirstChild("ClientEffects")}
    for c in pairs(self.Watchers)do exclude[#exclude+1]=c end
    params.FilterDescendantsInstances=exclude;params.RespectCanCollide=true
    local best,bestScore
    for _,dir in ipairs(dirs)do
        local clear=workspace:Raycast(root.Position,dir*60,params)==nil
        for _,step in ipairs({10,20,30,40,50,60})do
            local ground=workspace:Raycast(root.Position+dir*step+Vector3.new(0,3,0),Vector3.new(0,-13,0),params)
            if not ground or ground.Normal.Y<.45 then clear=false;break end
        end
        if clear then
            local score=math.huge
            for i=1,math.min(#dangers,12)do
                local t=dangers[i]
                -- The local native dash travelled 43 studs in the current-client test.
                -- Check a 60-stud route and score intermediate positions.
                local separation=math.huge
                for _,time in ipairs({.08,.16,.28})do
                    local p=root.Position+dir*math.min(50,time*150)
                    separation=math.min(separation,(p-(t.Position+t.Velocity*time)).Magnitude-t.Radius)
                end
                score=math.min(score,separation)
            end
            if not bestScore or score>bestScore then best,bestScore=dir,score end
        end
    end
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
function S:Tick()
    local now=os.clock();if now<self.NextTick then return end;self.NextTick=now+1/30
    local c,h,r,combat=localParts()
    if not c or not h or not r or h.Health<=0 then self.Status="Waiting for character";return end
    local health=value(c,"fakehealth",h.Health)
    if self.LastCharacter~=c then
        self.LastCharacter=c;self.LastHealth=health;self.NextScan=0;self.PendingAck=nil
    elseif health<self.LastHealth then
        self.LastHit=self.Status;log("health_loss",{Amount=self.LastHealth-health,Decision=self.Status})
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
    if #dangers==0 then if now>=self.NextRequest then self.Status="Watching attacks"end;return end
    local direction=self:Plan(r,h,dangers,c)
    if not direction then self.Status="No verified ground route";return end
    self:Request(direction,dangers[1].Source)
end
function S:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Requests=self.Requests,Acknowledged=self.Acknowledged,
        Errors=self.Errors,Threats=self.ActiveThreats or 0}
end
function S:SetEnabled(on)
    if self.Destroyed then return end
    on=on==true;if self.Enabled==on then return end
    self.Enabled=on;self.Generation+=1
    if not on then
        disconnect(self.Connections)
        for _,w in pairs(self.Watchers)do disconnect(w.Connections)end
        if self.ProjectileConnection then self.ProjectileConnection:Disconnect();self.ProjectileConnection=nil end
        if self.ReleaseRemote and self.ReleaseRemote.Parent then self.ReleaseRemote:FireServer("key","xend")end
        self.ReleaseRemote=nil;self.ProjectileFolder=nil;self.PendingAck=nil;self.NativeCallback=nil;self.NativeCharacter=nil
        table.clear(self.Watchers);table.clear(self.Projectiles);table.clear(self.Threats)
        self.Status="Off";return
    end
    self.Status="Watching attacks";self.NextScan=0;self.NextTick=0
    self.Connections[1]=Run.Heartbeat:Connect(function()
        local ok,err=pcall(self.Tick,self)
        if not ok then
            self.Errors+=1;warn("[Shindo Auto Dodge] "..tostring(err))
            if self.Errors>=3 then self:SetEnabled(false);self.Status="Stopped after errors"end
        end
    end)
end
function S:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if env.__SHINDO_AUTO_DODGE==self then env.__SHINDO_AUTO_DODGE=nil end
end
return S
