-- Untitled Boxing Game native-action auto combat. Starts OFF; one hub switch.
-- No simulated keyboard/mouse input, raw remote replay, stat edits or teleports.
assert(game.GameId==4730278139,"Open Untitled Boxing Game")
local Policy=(function()
local P={}
function P.Decide(s)
    if not s.Match then return "wait"end
    if s.Disabled then return "recover"end
    if s.Threat then
        -- Ordinary lights are cheaper to guard; reserve a fresh dodge for heavier danger.
        if s.ThreatKind=="Light"and s.CanBlock and s.Block>.35 then return "block"end
        if s.CanDash and s.CanAffordDash~=false and s.Stamina>.25 and s.FreshThreat then return "dodge"end
        if s.CanBlock and s.Block>.12 then return "block"end
        return "retreat"
    end
    local restingDistance=s.RestDistance or s.Reach+3
    if s.RecoveringStamina or s.Stamina<.22 or s.Health<.3 and s.Stamina<.55 then
        return s.Distance>=restingDistance and "rest"or"retreat"
    end
    -- A recognized approaching contact should not be met with a fresh attack startup.
    if s.Windup then
        if s.CanBlock and s.Block>.12 then return "block"end
        return s.Distance<s.Reach+2 and "retreat"or"circle"
    end
    if s.Distance>s.Reach then return "approach"end
    if s.Distance<2.1 then return "space"end
    if not s.CanPunch or s.OpponentDashing then return "circle"end
    local opening=s.Opening or 0
    local heavyStartup=s.HeavyStartup or .45
    local ultimateStartup=s.UltimateStartup or .65
    if s.Ultimate>=100 and s.CanAffordUltimate~=false and s.Stamina>.5
        and opening>=ultimateStartup+.1 and s.Distance<s.Reach-.3 then return "ultimate"end
    if s.CanAffordHeavy~=false and s.Stamina>.58 and(opening>=heavyStartup+.1
        or s.OpponentBlocking and s.OpponentBlock<.25)then return "heavy"end
    if s.CanAffordLight~=false and s.Stamina>.3 then return "light"end
    return "circle"
end
return P

end)()
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer
local env=getgenv()
if env.__ALLEN_UBG_COMBAT then env.__ALLEN_UBG_COMBAT:Destroy()end
local S={Version="1.1",HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Attacks=0,Dodges=0,Blocks=0,
    ConfirmedAttacks=0,ConfirmedDodges=0,ConfirmedGuards=0,BlockedRoutes=0,RejectedGuards=0,
    MaxStepMs=0,Generation=0,Desired=Vector3.zero,Threats={},LastAttack=-math.huge,LastDash=-math.huge,
    LastUltimate=-math.huge,LastEquip=-math.huge,Decision="wait"}
local connection,enemyConnection,ownConnection,native,styles,phases,broadcast,controls,originalMove,rawMove,moveShim
local currentTarget,currentCharacter,currentStyle,profileMap,blockCommand
local lockLease,ownProfileMap,ownBoundCharacter,ownStyle=nil,nil,nil,nil
local nextGuardAt,guardRequestedAt=0,nil
local function value(folder,name,default)
    local v=folder and folder:FindFirstChild(name)
    return v and v.Value or default
end
local function flag(folder,name)
    local v=folder and folder:FindFirstChild(name);return v and v.Value==true or false
end
local function stateFor(name)
    local states=workspace:FindFirstChild("States");local s=states and states:FindFirstChild(name)
    return s,s and s:FindFirstChild("CharacterData"),s and s:FindFirstChild("Occupied"),s and s:FindFirstChild("PlayerData")
end
local function live(c)
    local h=c and c:FindFirstChildOfClass("Humanoid");local r=c and c:FindFirstChild("HumanoidRootPart")
    if c and c.Parent and h and h.Health>0 and r then return h,r end
end
local function resolveOpponent(v)
    if typeof(v)=="Instance"then if v:IsA("Player")then return v.Character elseif v:IsA("Model")then return v end end
    local liveFolder=workspace:FindFirstChild("Live")
    return type(v)=="string"and liveFolder and liveFolder:FindFirstChild(v)or nil
end
local function setBlock(on)
    if blockCommand==on then return end
    blockCommand=on
    if native then native.SetBlock:Fire(on)end
    if on then S.Blocks+=1;guardRequestedAt=os.clock();S.GuardObserved=false
    else
        if guardRequestedAt then nextGuardAt=os.clock()+(S.BlockDebounce or .3)end
        guardRequestedAt=nil;S.GuardObserved=false
    end
end
local function releasePunch()
    if native then
        native.TryPunch:Fire({StopHoldingDownHeavy=true,InputType="Heavy"})
        native.TryPunch:Fire({StopHoldingDownHeavy=true,InputType="Light"})
    end
end
local function releaseTarget()
    if enemyConnection then enemyConnection:Disconnect();enemyConnection=nil end
    table.clear(S.Threats);currentTarget=nil;profileMap=nil;currentStyle=nil
    if lockLease then
        local slot=lockLease.Slot
        if slot.Parent and slot.Value==lockLease.Target then slot.Value=lockLease.Original end
        lockLease=nil
    end
    S.Desired=Vector3.zero;S.RecoveringStamina=false;S.PendingAttack=nil;S.PendingDash=nil;S.WasRecovering=false;S.WakeupGuardUntil=nil
end
local function profileStyle(style)
    local info=styles[style];local map={};if type(info)~="table"then return map end
    local defaultReach=math.clamp(((info.HitboxInfo and info.HitboxInfo.Size and info.HitboxInfo.Size.Z)or 2.9)+2.5,4,9)
    local visited=0
    local function walk(t,defaults,kind,depth,seen)
        if type(t)~="table"or depth>4 or seen[t]or visited>=500 then return end;seen[t]=true;visited+=1
        if t.AnimId then
            local id=tostring(t.AnimId):match("%d+")
            if id then map[id]={Kind=kind,Contact=tonumber(t.LandedFrame)or tonumber(t.Startup)or tonumber(defaults.Startup)or .25,
                Reach=defaultReach,Recovery=tonumber(t.MaxTime)or tonumber(defaults.MaxTime)or .75}end
        end
        local n=0;for _,v in pairs(t)do n+=1;if n>100 then break end;if type(v)=="table"then walk(v,defaults,kind,depth+1,seen)end end
    end
    walk(info.Combos,info.DefaultPunchInfo or {},"Light",0,{})
    walk(info.HeavyAttacks,info.HeavyAttacks and info.HeavyAttacks.DefaultPunchInfo or {},"Heavy",0,{})
    walk(info.UltimateInfo,info.UltimateInfo and info.UltimateInfo.DefaultPunchInfo or {},"Ultimate",0,{})
    return map
end
local function trackAttack(track)
    local id=track.Animation and track.Animation.AnimationId:match("%d+")
    local profile=id and profileMap and profileMap[id]
    if profile then
        if #S.Threats>=12 then table.remove(S.Threats,1)end
        S.Threats[#S.Threats+1]={Track=track,Profile=profile,Expires=os.clock()+4,Defended=false}
    end
end
local function bindTarget(target,style)
    local changed=currentTarget~=target
    if changed then
        releaseTarget();currentTarget=target
        local h=target:FindFirstChildOfClass("Humanoid");local a=h and h:FindFirstChildOfClass("Animator")
        if a then enemyConnection=a.AnimationPlayed:Connect(trackAttack)end
    end
    if currentStyle~=style then currentStyle=style;profileMap=profileStyle(style)end
    if changed then local h=target:FindFirstChildOfClass("Humanoid");local a=h and h:FindFirstChildOfClass("Animator");if a then
        for i,tr in ipairs(a:GetPlayingAnimationTracks())do if i>16 then break end;trackAttack(tr)end
    end end
end
local function safeMove(worldDirection,root,target)
    local flat=Vector3.new(worldDirection.X,0,worldDirection.Z)
    local amount=math.min(1,flat.Magnitude)
    if amount<.05 then return Vector3.zero end
    flat=flat.Unit
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={workspace:FindFirstChild("Live")or LP.Character,target};params.RespectCanCollide=true
    local point=root.Position+flat*3
    if workspace:Raycast(root.Position,flat*3,params)then return Vector3.zero end
    local floor=workspace:Raycast(point+Vector3.new(0,2,0),Vector3.new(0,-9,0),params)
    if not floor or floor.Normal.Y<.6 then return Vector3.zero end
    local localDirection=CFrame.lookAt(root.Position,Vector3.new(target.PrimaryPart.Position.X,root.Position.Y,target.PrimaryPart.Position.Z)):VectorToObjectSpace(flat)
    return Vector3.new(localDirection.X,0,localDirection.Z)*amount
end
local function chooseMove(candidates,root,target)
    for i,candidate in ipairs(candidates)do
        local direction=safeMove(candidate,root,target)
        if direction.Magnitude>.05 then return direction,i end
    end
    S.BlockedRoutes+=1;return Vector3.zero,0
end
local function bindOwn(c,style)
    if ownBoundCharacter==c and ownStyle==style then return end
    if ownConnection then ownConnection:Disconnect();ownConnection=nil end
    ownBoundCharacter=c;ownStyle=style;ownProfileMap=profileStyle(style)
    local h=c:FindFirstChildOfClass("Humanoid");local a=h and h:FindFirstChildOfClass("Animator")
    if a then ownConnection=a.AnimationPlayed:Connect(function(track)
        local id=track.Animation and track.Animation.AnimationId:match("%d+")
        local pending=S.PendingAttack
        if id and ownProfileMap[id]and pending and not pending.Observed and os.clock()-pending.Time<.65 then
            pending.Observed=true;S.ConfirmedAttacks+=1
        end
    end)end
end
local function requestPunch(kind,now)
    if now-S.LastAttack<.36 then return end
    if kind=="ultimate"and now-S.LastUltimate<2 then return end
    setBlock(false);S.LastAttack=now
    S.PendingAttack={Time=now,Kind=kind,Observed=false}
    if kind=="ultimate"then native.TryPunch:Fire({IsUltimate=true});S.LastUltimate=now
    elseif kind=="heavy"then native.TryPunch:Fire({IsHeavy=true})
    else native.TryPunch:Fire()end
    S.Attacks+=1
    local generation=S.Generation
    task.delay(.1,function()if generation==S.Generation then releasePunch()end end)
end
local function step()
    local now=os.clock();S.Desired=Vector3.zero
    local c=LP.Character;local h,r=live(c)
    local _,cd,occupied,pd=stateFor(LP.Name)
    if not h or not cd or not occupied then setBlock(false);releaseTarget();S.Status="Waiting for character combat state";return end
    if currentCharacter~=c then releaseTarget();currentCharacter=c;releasePunch();blockCommand=nil end
    local actualGuard=flag(cd,"Blocking")or flag(occupied,"Blocking")
    if blockCommand and actualGuard and not S.GuardObserved then S.GuardObserved=true;S.ConfirmedGuards+=1 end
    if blockCommand and not actualGuard and guardRequestedAt and now-guardRequestedAt>.3 then
        S.RejectedGuards+=1;setBlock(false)
    end
    if S.PendingDash then
        local pending=S.PendingDash
        if pending.Character~=c or now-pending.Time>.5 then S.PendingDash=nil
        elseif flag(cd,"Dashing")or flag(occupied,"Dashing")or c:GetAttribute("LocalDashTime")~=pending.Before then
            S.ConfirmedDodges+=1;S.PendingDash=nil
        end
    end
    if UIS:GetFocusedTextBox()then setBlock(false);S.Status="Paused while typing";return end
    local menu=workspace:FindFirstChild("CurrentMenu")
    if menu and menu.Value~=""then setBlock(false);releaseTarget();S.Status="Paused while menu is open";return end
    local target=resolveOpponent(value(cd,"Opponent"))
    local oh,other=live(target)
    if not target or target==c or not oh or not other or not target.PrimaryPart then
        setBlock(false);releaseTarget();S.Status="Waiting for active match opponent";return
    end
    local _,ocd,ooccupied,opd=stateFor(target.Name)
    if not ocd then setBlock(false);S.Status="Opponent state unavailable";return end
    local styleName=value(pd,"Style","Basic");local opponentStyle=value(opd,"Style","Basic")
    bindTarget(target,opponentStyle);bindOwn(c,styleName)
    local forced=flag(occupied,"ForceMove")or c:GetAttribute("Rooted")or c:GetAttribute("SpecialHoldRooted")
    local blocked=forced or flag(cd,"Cutscene")or flag(cd,"Stunned")or flag(occupied,"Stunned")or flag(occupied,"Spectating")
        or flag(pd,"Disable")or flag(cd,"Toxic")or value(cd,"Health",100)<=0 or c:GetAttribute("StaminaBroken")
    if blocked then S.WasRecovering=true;setBlock(false);S.Decision="recover";S.Status="Waiting for stun / knockdown / cutscene recovery";return end
    if S.WasRecovering then S.WakeupGuardUntil=now+.18;S.WasRecovering=false end
    if flag(ocd,"Cutscene")or value(ocd,"Health",100)<=0 then setBlock(false);S.Status="Waiting for opponent recovery";return end
    if not flag(cd,"Equipped")then
        if now-S.LastEquip>1 then native.TrySwitchEquip:Fire();S.LastEquip=now end
        S.Status="Waiting for native combat equip";return
    end
    local locked=occupied:FindFirstChild("LockedOn")
    if locked and locked.Value~=target then
        if not lockLease then lockLease={Slot=locked,Original=locked.Value,Target=target}end
        locked.Value=target
    end
    local delta=other.Position-r.Position;local flat=Vector3.new(delta.X,0,delta.Z)
    local distance=flat.Magnitude
    if distance<.01 or distance>80 then setBlock(false);S.Status="Opponent outside controlled range";return end
    local toward=flat.Unit;local side=toward:Cross(Vector3.yAxis)
    local facing=other.CFrame.LookVector:Dot(-toward)>.35 and math.abs(delta.Y)<5
    local threatening,fresh,selected=false,false,nil
    local opponentRecovering,opening,windup=false,0,false
    local ownInfo=styles[styleName]or styles.Basic
    local lightInfo=ownInfo.DefaultPunchInfo or {}
    local heavyInfo=ownInfo.HeavyAttacks and ownInfo.HeavyAttacks.DefaultPunchInfo or {}
    local ultimateInfo=ownInfo.UltimateInfo and ownInfo.UltimateInfo.DefaultPunchInfo or {}
    local dashInfo=ownInfo.DashInfo and ownInfo.DashInfo.DefaultInfo or {}
    local coreInfo=ownInfo.CoreInfo or {}
    local lightStartup=tonumber(lightInfo.Startup)or .2
    local heavyStartup=tonumber(heavyInfo.Startup)or .5
    local ultimateStartup=tonumber(ultimateInfo.Startup)or .65
    S.BlockDebounce=tonumber(coreInfo.BlockDebounce)or .3
    local dashInterval=math.clamp((tonumber(dashInfo.DashDelay)or .65)+(tonumber(dashInfo.DashStartup)or .05),.35,1.5)
    for i=#S.Threats,1,-1 do
        local t=S.Threats[i];local tr=t.Track
        if not tr.IsPlaying or now>t.Expires then table.remove(S.Threats,i)
        else
            local eta=(t.Profile.Contact-tr.TimePosition)/math.max(.1,tr.Speed)
            local recovering=phases.IsInRecovery(tr)==true
            if recovering then
                opponentRecovering=true
                opening=math.max(opening,math.max(0,((tonumber(tr.Length)or t.Profile.Recovery)-tr.TimePosition)/math.max(.1,tr.Speed)))
            end
            if not recovering and facing and distance<=t.Profile.Reach+1.5 and eta>0 and eta<=lightStartup+.15 then windup=true end
            if not recovering and facing and distance<=t.Profile.Reach+1.5 and eta<=.24 and eta>=-.15 then
                threatening=true
                if not selected or eta<selected.Eta then selected={Threat=t,Eta=eta};fresh=not t.Defended end
            end
        end
    end
    if not threatening and target:GetAttribute("Punching")and facing and distance<5.5 and #S.Threats==0 then threatening=true end
    local stamina=value(cd,"Stamina",0)/math.max(1,value(cd,"MaxStamina",100))
    local healthRatio=value(cd,"Health",100)/math.max(1,value(cd,"MaxHealth",100))
    local reserve=healthRatio<.3 and .8 or .65
    if stamina<.3 or healthRatio<.3 and stamina<.55 then S.RecoveringStamina=true
    elseif stamina>=reserve then S.RecoveringStamina=false end
    local ownBlock=value(cd,"BlockEnergy",0)/math.max(1,value(cd,"MaxBlockEnergy",50))
    local reach=math.clamp(((ownInfo.HitboxInfo and ownInfo.HitboxInfo.Size and ownInfo.HitboxInfo.Size.Z)or 2.9)+2.2,3.8,8)
    local ownPunch=flag(occupied,"Punching")
    local movementLocked=phases.IsMovementLocked(c)
    local staminaPoints=value(cd,"Stamina",0)
    local dashCost=tonumber(dashInfo.Stamina)or 10
    local reserveCost=dashCost+3
    local threatKind=selected and selected.Threat.Profile.Kind or "Unknown"
    local snapshot={Match=true,Disabled=false,Threat=threatening,FreshThreat=fresh,
        CanDash=not flag(occupied,"Dashing")and not ownPunch and not movementLocked and now-S.LastDash>dashInterval
            and not c:HasTag("DashDisabled")and not c:GetAttribute("NoDash"),
        CanBlock=flag(occupied,"CanBlock")and not ownPunch and not movementLocked and now>=nextGuardAt
            and not c:HasTag("BlockDisabled")and not coreInfo.NoBlock and not c:GetAttribute("NoBlock")
            and not c:GetAttribute("BlockBroken")and not c:GetAttribute("DempseyRolling")and not c:GetAttribute("SlowMo"),
        ThreatKind=threatKind,Windup=windup or(now<(S.WakeupGuardUntil or 0)and facing and distance<=reach+2),Opening=opening,HeavyStartup=heavyStartup,UltimateStartup=ultimateStartup,
        CanAffordDash=staminaPoints>=dashCost+5,
        CanAffordLight=staminaPoints>=(tonumber(lightInfo.Stamina)or 10)+reserveCost,
        CanAffordHeavy=staminaPoints>=(tonumber(heavyInfo.Stamina)or 20)+reserveCost,
        CanAffordUltimate=staminaPoints>=(tonumber(ultimateInfo.Stamina)or 20)+reserveCost,
        RestDistance=reach+3,
        Stamina=stamina,RecoveringStamina=S.RecoveringStamina,Block=ownBlock,Health=value(cd,"Health",100)/math.max(1,value(cd,"MaxHealth",100)),
        Distance=distance,Reach=reach,CanPunch=flag(occupied,"CanPunch")and not flag(occupied,"Dashing")and not ownPunch,
        OpponentVulnerable=flag(ocd,"Stunned")or opponentRecovering,
        OpponentBlocking=flag(ocd,"Blocking")or flag(ooccupied,"Blocking"),
        OpponentBlock=value(ocd,"BlockEnergy",50)/math.max(1,value(ocd,"MaxBlockEnergy",50)),
        OpponentDashing=flag(ocd,"Dashing")or flag(ooccupied,"Dashing"),Ultimate=value(cd,"UltimateEnergy",0)}
    local decision=Policy.Decide(snapshot);S.Decision=decision
    local direction=Vector3.zero
    local sign=math.floor(now/1.2)%2==0 and 1 or -1
    if decision=="approach"then direction=toward
    elseif decision=="retreat"or decision=="space"then direction=-toward+side*.25*sign
    elseif decision=="circle"then direction=side*sign*.35
    elseif decision=="dodge"then direction=side*sign end
    local candidates={direction}
    if decision=="dodge"then candidates={direction,-direction,-toward}
    elseif decision=="approach"or decision=="retreat"or decision=="space"then
        candidates={direction,direction+side*.7,direction-side*.7}
    elseif decision=="circle"then candidates={direction,-direction}end
    S.Desired=direction.Magnitude>.05 and chooseMove(candidates,r,target)or Vector3.zero
    if decision=="block"then setBlock(true)
    elseif decision=="dodge"then
        setBlock(false)
        if S.Desired.Magnitude>.1 then
            if selected then selected.Threat.Defended=true end
            S.LastDash=now;S.Dodges+=1;S.PendingDash={Character=c,Time=now,Before=c:GetAttribute("LocalDashTime")};native.TryDash:Fire()
        elseif snapshot.CanBlock then setBlock(true)end
    else
        setBlock(false)
        if decision=="light"or decision=="heavy"or decision=="ultimate"then
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={workspace:FindFirstChild("Live")or c};params.RespectCanCollide=true
            if not workspace:Raycast(r.Position,delta,params)then requestPunch(decision,now)end
        end
    end
    S.Status=decision.." · "..target.Name..string.format(" · %.1f studs · %d%% stamina",distance,stamina*100)
end
local function setupNative()
    local folder=RS:FindFirstChild("MobileEvents");assert(folder,"Native action interfaces unavailable")
    local actions={}
    for _,name in ipairs({"TryPunch","TryDash","SetBlock","TrySwitchEquip"})do
        local event=folder:FindFirstChild(name);assert(event and event:IsA("BindableEvent"),"Native action changed: "..name);actions[name]=event
    end
    native=actions
    local modules=RS:FindFirstChild("Modules");assert(modules,"Combat modules unavailable")
    styles=require(modules:FindFirstChild("Styles"));phases=require(modules.Combat:FindFirstChild("AttackAnimationPhases"))
    broadcast=require(modules:FindFirstChild("BroadcastCamera"))
    local playerModule=LP.PlayerScripts:FindFirstChild("PlayerModule");assert(playerModule,"Native movement module unavailable")
    controls=require(playerModule):GetControls();originalMove=controls.GetMoveVector;rawMove=rawget(controls,"GetMoveVector")
    assert(type(originalMove)=="function","Native movement interface changed")
    moveShim=function(self,...)
        if not S.Enabled or not currentTarget or UIS:GetFocusedTextBox()then return originalMove(self,...)end
        local _,_,forcedOccupied=stateFor(LP.Name)
        local c=LP.Character
        if flag(forcedOccupied,"ForceMove")or c and(c:GetAttribute("Rooted")or c:GetAttribute("SpecialHoldRooted"))then return originalMove(self,...)end
        local desired=S.Desired
        local _,_,occupied=stateFor(LP.Name)
        local locked=value(occupied,"LockedOn")
        local x=broadcast.GetCombatMoveVector(Vector3.xAxis,locked)
        local z=broadcast.GetCombatMoveVector(Vector3.zAxis,locked)
        local det=x.X*z.Z-z.X*x.Z
        if math.abs(det)<.01 then return Vector3.zero end
        local vector=Vector3.new((desired.X*z.Z-desired.Z*z.X)/det,0,(x.X*desired.Z-x.Z*desired.X)/det)
        if flag(occupied,"ReverseInputs")then vector=-vector end
        return vector.Magnitude>1 and vector.Unit or vector
    end
    controls.GetMoveVector=moveShim
end
function S:SetEnabled(valueOn)
    if self.Destroyed then return end
    if valueOn~=true then
        self.Enabled=false;self.Generation+=1
        if connection then connection:Disconnect();connection=nil end
        pcall(setBlock,false);pcall(releasePunch);releaseTarget()
        if ownConnection then ownConnection:Disconnect();ownConnection=nil end
        ownBoundCharacter=nil;ownStyle=nil
        if controls and controls.GetMoveVector==moveShim then controls.GetMoveVector=rawMove end
        controls=nil;originalMove=nil;moveShim=nil;self.Status="Off";self.Desired=Vector3.zero
        return
    end
    if self.Enabled then return end
    local ok,err=pcall(setupNative)
    if not ok then self:SetEnabled(false);error(err,0)end
    self.Enabled=true;self.Generation+=1;blockCommand=nil;self.Status="Waiting for active match"
    local elapsed=0
    connection=Run.Heartbeat:Connect(function(dt)
        elapsed+=dt;if elapsed<.05 then return end;elapsed=0
        local started=os.clock();local ok,message=pcall(step)
        local ms=(os.clock()-started)*1000;self.MaxStepMs=math.max(self.MaxStepMs,ms)
        if not ok or ms>50 then
            self:SetEnabled(false);self.Status=not ok and("Stopped: "..tostring(message):sub(1,120))or"Stopped: timing guard"
            warn("[UBG Auto Combat] "..self.Status)
        end
    end)
end
function S:GetSnapshot()return {Version=self.Version,Enabled=self.Enabled,Status=self.Status,Attacks=self.Attacks,Dodges=self.Dodges,Blocks=self.Blocks,Decision=self.Decision,MaxStepMs=self.MaxStepMs,ConfirmedAttacks=self.ConfirmedAttacks,ConfirmedDodges=self.ConfirmedDodges,ConfirmedGuards=self.ConfirmedGuards,RejectedGuards=self.RejectedGuards,BlockedRoutes=self.BlockedRoutes}end
function S:Destroy()
    if self.Destroyed then return end;self:SetEnabled(false);self.Destroyed=true
    if env.__ALLEN_UBG_COMBAT==self then env.__ALLEN_UBG_COMBAT=nil end
end
env.__ALLEN_UBG_COMBAT=S
return S

