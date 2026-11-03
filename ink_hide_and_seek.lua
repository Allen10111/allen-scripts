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
local env=getgenv()
local KnifePolicy=(function()
local Policy={}
function Policy.InAttackArc(distance,forward,lateral,height,range)
    return distance>.05 and distance<=range and forward>0 and forward/distance>=.8
        and math.abs(lateral)<=3.5 and math.abs(height)<=5
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
    local function aimedKnifeThreat(attacker)
        local threat=M.Threats[attacker]
        if type(threat)~="table" or threat.Expires<=os.clock() or not threat.Track.IsPlaying
            or threat.Character~=attacker.Character or not hunter(attacker)then return false end
        local c,_,other=live(attacker);local _,_,r=live(LP)
        if not c or not r or not c:FindFirstChild("Knife")then return false end
        local offset=r.Position-other.Position
        local flat=Vector3.new(offset.X,0,offset.Z)
        local look=Vector3.new(other.CFrame.LookVector.X,0,other.CFrame.LookVector.Z)
        if look.Magnitude<.1 then return false end;look=look.Unit
        local right=look:Cross(Vector3.yAxis)
        if not KnifePolicy.InAttackArc(flat.Magnitude,flat:Dot(look),flat:Dot(right),offset.Y,threat.Range)then return false end
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
        local c,h,r=live(LP);local _,_,other=live(attacker)
        if not r or not other or c:FindFirstChild("Ragdoll") or c:FindFirstChild("DisableMovement")then return end
        local bag=LP:FindFirstChildOfClass("Backpack")
        local tool=c:FindFirstChild("DODGE!") or bag and bag:FindFirstChild("DODGE!")
        if not tool or not tool:IsA("Tool")then M.Controllers.dodge.Status="DODGE! item required";return end
        if onCooldown(c,tool)then M.Controllers.dodge.Status="DODGE! cooldown";return end
        local away=Vector3.new(r.Position.X-other.Position.X,0,r.Position.Z-other.Position.Z)
        if away.Magnitude<.1 then away=-other.CFrame.LookVector end
        away=away.Unit
        local side=away:Cross(Vector3.yAxis)
        local direction
        for _,v in ipairs({away,side,-side})do direction=safeDirection(r.Position+v*8,r.Position);if direction then break end end
        if not direction then M.Controllers.dodge.Status="No clear dodge route";return end
        M.LastDodge=os.clock();M.EvadeDirection=direction;M.EvadeUntil=os.clock()+.18
        M.DodgeItemUntil=os.clock()+.45
        M.Controllers.dodge.Status="Evading knife threat"
        local previous=c:FindFirstChildOfClass("Tool")
        if tool.Parent~=c then
            restoreEquipment()
            local lease={Character=c,Tool=tool,Previous=previous,Backpack=bag};M.DodgeEquipment=lease
            h:EquipTool(tool)
            task.delay(.35,function()if M.DodgeEquipment==lease then restoreEquipment()end end)
        end
        local generation=M.Generation
        task.delay(.04,function()
            if generation~=M.Generation or not enabled("dodge") or not active()then return end
            if not aimedKnifeThreat(attacker)then
                M.EvadeUntil=nil;restoreEquipment();M.Controllers.dodge.Status="Knife threat no longer aimed at you";return
            end
            if c~=LP.Character then return end
            if tool.Parent~=c then M.Controllers.dodge.Status="Waiting for DODGE! equip";return end
            if onCooldown(c,tool)then M.Controllers.dodge.Status="DODGE! cooldown";return end
            local ok,err=pcall(function()
                local input=game:GetService("UserInputService")
                assert(not input:GetFocusedTextBox(),"Close the text box before dodging")
                assert(type(mouse1press)=="function" and type(mouse1release)=="function",
                    "Executor mouse input is unavailable; no remote fallback")
                -- The game's equipped-tool action is MouseButton1, not the ordinary Q dash.
                -- Release is unconditional, including when the controller is switched OFF.
                mouse1press()
                task.delay(.03,function()pcall(mouse1release)end)
                M.Controllers.dodge.Actions+=1;M.Controllers.dodge.Status="DODGE! input sent"
            end)
            if not ok then M.Controllers.dodge.Status="DODGE! unavailable: "..tostring(err):sub(1,75)end
        end)
    end
    local function peers()
        local objects={}
        for _,p in ipairs(Players:GetPlayers())do
            local c,_,r=live(p)
            if p~=LP and c then
                objects[c]=true
                if enabled("dodge") and hunter(p)then
                    local animator=c:FindFirstChildOfClass("Humanoid") and c:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
                    if animator and not M.Animators[animator]then
                        M.Animators[animator]=animator.AnimationPlayed:Connect(function(track)
                            local id=track.Animation and track.Animation.AnimationId:match("%d+")
                            local profile=M.AttackIds and M.AttackIds[id]
                            if enabled("dodge") and profile then
                                M.Threats[p]={Track=track,Character=c,Range=profile.Range,
                                    Expires=os.clock()+math.clamp(.6/math.max(.2,track.Speed),.2,.9)}
                                evade(p)
                            end
                        end)
                    end
                end
            end
        end
        for animator,connection in pairs(M.Animators)do
            if not animator:IsDescendantOf(workspace) or not enabled("dodge")then connection:Disconnect();M.Animators[animator]=nil end
        end
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
            if v:IsA("Animation") and (v.Name:lower():find("swing") or v.Name:lower():find("stab") or v.Name:lower():find("slash"))then
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
    local function collect()
        if not enabled("collect")then return false end
        local c,h,r=live(LP);if not r then return false end
        local best,part,distance=nil,nil,70
        for object in pairs(M.Keys)do
            local p=object.Parent and objectPart(object)
            if p and object:IsDescendantOf(workspace)then
                local d=(p.Position-r.Position).Magnitude;if d<distance then best=object;part=p;distance=d end
            end
        end
        local s=M.Controllers.collect
        if not best then s.Status="Waiting for nearby dropped key";return false end
        if distance>4 then route("collect",best,part.Position);s.Status="Walking to dropped key";return true end
        M.Motion=nil
        if os.clock()-(M.LastPickup or 0)>=1 then
            M.LastPickup=os.clock()
            local prompt=best:FindFirstChildWhichIsA("ProximityPrompt",true)
            if prompt and prompt.Enabled and distance<=prompt.MaxActivationDistance then
                if type(fireproximityprompt)=="function" then fireproximityprompt(prompt)
                else prompt:InputHoldBegin();local generation=M.Generation;task.delay(prompt.HoldDuration+.05,function()if generation==M.Generation and prompt.Parent then prompt:InputHoldEnd()end end)end
                s.Actions+=1;s.Status="Native key pickup attempted"
            elseif type(firetouchinterest)=="function" and part:FindFirstChildOfClass("TouchTransmitter")then
                firetouchinterest(r,part,0);firetouchinterest(r,part,1);s.Actions+=1;s.Status="Nearby key touch attempted"
            else s.Status="At dropped key · waiting for native pickup" end
        end
        return true
    end
    function M:Step()
        local any=false;for _,c in pairs(self.Controllers)do if c.Enabled then any=true;break end end
        local map=workspace:FindFirstChild("HideAndSeekMap")
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
            if not self.EvadeUntil or self.EvadeUntil<os.clock()then self.Controllers.dodge.Status="Watching knife animations aimed at you"end
        end
        local collecting=collect()
        if not collecting and enabled("follow")then
            local target=nearest(hider,180)
            if target then local _,_,other=live(target);route("follow",target,other.Position);self.Controllers.follow.Status="Following "..target.DisplayName
            else self.Controllers.follow.Status="Waiting for nearby blue-team hider"end
        end
        if enabled("teleport")then
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
        if M.Destroyed or not M.Map or not active()then return end
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

