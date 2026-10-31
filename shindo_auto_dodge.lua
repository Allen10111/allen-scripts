-- Allen Scripts: Shindo Life native local movement evasions. Hub controlled, starts OFF.
-- Combat values and projectile motion are replicated evidence; range envelopes
-- are defensive heuristics, not a copy of server hitboxes or invulnerability.
if game.GameId ~= 1511883870 then return end
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local LP=Players.LocalPlayer
local env=getgenv()
if env.__SHINDO_AUTO_DODGE then env.__SHINDO_AUTO_DODGE:Destroy() end
local S={Enabled=false,HubOnly=true,Destroyed=false,Connections={},Watchers={},Projectiles={},Powers={},
    Threats={},Replay={},Requests=0,Acknowledged=0,Errors=0,Detected=0,NextRequest=0,
    Status="Off",Generation=0,NextScan=0,NextTick=0,LastHit="None",Version=5}
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
    if not direction then self.Status=self.RouteReason or "No verified ground route";return end
    self:Request(direction,dangers[1].Source)
end
function S:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Requests=self.Requests,Acknowledged=self.Acknowledged,
        Errors=self.Errors,Threats=self.ActiveThreats or 0,RouteThreats=self.RouteThreatCount or 0,
        RoutesChecked=self.RouteChecked or 0,RouteClearance=self.LastRouteClearance,
        RouteReason=self.RouteReason,PowerEvents=self.PowerEvents or 0}
end
function S:SetEnabled(on)
    if self.Destroyed then return end
    on=on==true;if self.Enabled==on then return end
    self.Enabled=on;self.Generation+=1
    if not on then
        disconnect(self.Connections)
        for _,w in pairs(self.Watchers)do disconnect(w.Connections)end
        disconnect(self.HazardConnections or {});self.HazardConnections={};self.HazardRoots={};self.EffectsFolder=nil
        if self.ReleaseRemote and self.ReleaseRemote.Parent then self.ReleaseRemote:FireServer("key","xend")end
        self.ReleaseRemote=nil;self.ProjectileFolder=nil;self.PendingAck=nil;self.NativeCallback=nil;self.NativeCharacter=nil
        table.clear(self.Watchers);table.clear(self.Projectiles);table.clear(self.Threats);table.clear(self.Powers)
        self.PowerOverflowUntil=nil
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
