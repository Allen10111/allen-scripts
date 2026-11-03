-- Isolated DODGE! controller: invokes one validated native hotbar callback per swing.
-- No synthesized keyboard/touch input, direct remotes, map index or movement.
assert(game.GameId==7008097940,"Open Ink Game")
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local Run=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
assert(type(getconnections)=="function"and debug and type(debug.getupvalues)=="function",
    "Native hotbar callback inspection is unavailable on this executor")
local env=getgenv()
if env.__ALLEN_HNS_dodge then env.__ALLEN_HNS_dodge:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Actions=0,Attempts=0,Status="Off",MaxStepMs=0,Generation=0}
local animationIds={}
local abilities=RS:FindFirstChild("Animations");abilities=abilities and abilities:FindFirstChild("Abilities")
local knife=abilities and abilities:FindFirstChild("Knife")
if knife then for _,v in ipairs(knife:GetChildren())do
    local name=v.Name:lower()
    if v:IsA("Animation")and name:find("swing",1,true)and not name:find("victim",1,true)then
        local id=v.AnimationId:match("%d+")
        if id then animationIds[id]={Kind="Knife",Range=name:find("lunge",1,true)and 14 or 8}end
    end
end end
-- SharedFunctions maps Weak Fists to FightBack, which also contains non-punch assets.
-- Explicit whitelist avoids victim, clash, QTE and pole animations in the same folder.
local weakNames={Punch1=true,Punch2=true,Punch3=true,AttemptToPunchBack=true}
local fightBack=abilities and abilities:FindFirstChild("FightBack")
if fightBack then for _,v in ipairs(fightBack:GetChildren())do
    if v:IsA("Animation")and weakNames[v.Name]then
        local id=v.AnimationId:match("%d+")
        if id then animationIds[id]={Kind="Weak Fists",Range=6}end
    end
end end
local function weaponMatches(c,kind)
    -- The exact FightBack punch IDs identify Weak Fists even when it auto-uses from inventory.
    return kind=="Weak Fists" or c:FindFirstChild("Knife")~=nil
end
local watches,threats={},{}
local heartbeat,lastScan,lastAttempt,statusUntil,elapsed=nil,0,-math.huge,0,0
local function log(...)print("[DODGE ISOLATED]",...)end
local function live(p)
    local c=p.Character;local h=c and c:FindFirstChildOfClass("Humanoid");local r=c and c:FindFirstChild("HumanoidRootPart")
    if h and h.Health>0 and r then return c,h,r end
end
local function cooldown(c)
    for _,v in ipairs(c:GetChildren())do if not v:IsA("Tool") and (v:GetAttribute("CD")=="DODGE!"or v:GetAttribute("CD")=="Dodge")then return true end end
    return false
end
local function slotHandler()
    local pg=LP:FindFirstChildOfClass("PlayerGui");local bar=pg and pg:FindFirstChild("Hotbar")
    bar=bar and bar:FindFirstChild("Backpack");bar=bar and bar:FindFirstChild("Hotbar")
    if not bar then return end
    for _,button in ipairs(bar:GetChildren())do
        local label=button:FindFirstChild("ToolName")
        if button:IsA("GuiButton")and button.Visible and label and label.Text=="DODGE!"then
            local handler
            for _,connection in ipairs(getconnections(button.MouseButton1Down))do
                local fn=connection.Function
                if type(fn)=="function"then
                    local ok,u=pcall(debug.getupvalues,fn)
                    -- Native backpack handler: inventory-open flag, drag fn, slot, char, bag, use fn.
                    if ok and type(u)=="table"and type(u[1])=="boolean"and type(u[2])=="function"
                        and u[3]==button and typeof(u[4])=="Instance"and typeof(u[5])=="Instance"and type(u[6])=="function"then
                        if u[1]then return nil,"Close the inventory editor"end
                        if handler then return nil,"Multiple native hotbar handlers; stopped"end
                        handler=fn
                    end
                end
            end
            return handler,handler and nil or "Native hotbar callback schema changed"
        end
    end
    return nil,"DODGE! must be visible in the hotbar"
end
local function scan()
    local present={};local n=0
    for _,p in ipairs(Players:GetPlayers())do
        if p~=LP then
            n+=1;if n>32 then break end
            local c,h=live(p);local a=h and h:FindFirstChildOfClass("Animator")
            if a then
                present[p]=a
                if not watches[p]or watches[p].Animator~=a then
                    if watches[p]then watches[p].Connection:Disconnect()end
                    watches[p]={Animator=a,Connection=a.AnimationPlayed:Connect(function(track)
                        if not S.Enabled then return end
                        local id=track.Animation and track.Animation.AnimationId:match("%d+")
                        local profile=id and animationIds[id]
                        if profile and weaponMatches(c,profile.Kind)then
                            threats[p]={Character=c,Track=track,Range=profile.Range,Kind=profile.Kind,Expires=os.clock()+1.2,Attempted=false}
                            log("swing",p.Name,profile.Kind,id)
                        end
                    end)}
                end
            end
        end
    end
    for p,w in pairs(watches)do if present[p]~=w.Animator then w.Connection:Disconnect();watches[p]=nil;threats[p]=nil end end
end
local DashPolicy=(function()
local P={}
local function finite(v)return v==v and math.abs(v)<math.huge end
function P.Entry(x,y,z,vx,vy,vz,range)
    if not(finite(x)and finite(y)and finite(z)and finite(vx)and finite(vy)and finite(vz))then return end
    local near,far=0,.14
    local speed=math.sqrt(vx*vx+vz*vz)
    local inside=math.abs(x)<=4.25 and math.abs(y)<=5.75 and z>=-range-.75 and z<=.75
    if inside then return 0 end
    -- Only predict a fast approach, not ordinary distant swings or movement away.
    if speed<15 or speed>250 or x*vx+z*vz>=0 then return end
    far=math.min(far,10/speed)
    local function slab(position,velocity,low,high)
        if math.abs(velocity)<.001 then return position>=low and position<=high end
        local a,b=(low-position)/velocity,(high-position)/velocity
        if a>b then a,b=b,a end
        near=math.max(near,a);far=math.min(far,b)
        return near<=far
    end
    if slab(x,vx,-4.25,4.25)and slab(y,vy,-5.75,5.75)and slab(z,vz,-range-.75,.75)then return near end
end
return P

end)()
local function hitboxEntry(root,target,range)
    local point=root.CFrame:PointToObjectSpace(target.Position)
    local relative=root.CFrame:VectorToObjectSpace(target.AssemblyLinearVelocity-root.AssemblyLinearVelocity)
    return DashPolicy.Entry(point.X,point.Y,point.Z,relative.X,relative.Y,relative.Z,range)
end
local function step()
    local now=os.clock()
    if now-lastScan>=.5 then lastScan=now;scan()end
    local c,h,r=live(LP);if not c then return end
    local bag=LP:FindFirstChildOfClass("Backpack")
    if not(c:FindFirstChild("DODGE!")or bag and bag:FindFirstChild("DODGE!"))then S.Status="DODGE! item required";return end
    if cooldown(c)then if S.PendingInput then S.PendingInput.Observed=true end;S.Status="Native DODGE! cooldown · waiting";return end
    if c:FindFirstChild("Ragdoll")or c:FindFirstChild("Stun")or c:FindFirstChild("DisableTools")then S.Status="Waiting for recovery";return end
    if now>statusUntil then S.Status="Watching knife / weak fists + dash approach · one activation per swing"end
    for p,t in pairs(threats)do
        if now>t.Expires or not t.Track.IsPlaying or p.Character~=t.Character then threats[p]=nil
        elseif not t.Attempted and now-lastAttempt>=.55 then
            local attacker,_,root=live(p)
            local entry=attacker and weaponMatches(attacker,t.Kind)and hitboxEntry(root,r,t.Range)
            if type(entry)=="number"then
                if UIS:GetFocusedTextBox()then S.Status="Close text input to dodge";return end
                local handler,reason=slotHandler()
                if not handler then S.Status=reason or "Native hotbar handler unavailable";return end
                -- Consume before spawning: each animation record gets at most one input pair.
                t.Attempted=true;lastAttempt=now;S.Attempts+=1;statusUntil=now+2
                local generation=S.Generation
                local attempt={Observed=false};S.PendingInput=attempt
                log(entry>0 and "dash attack predicted; native button attempt"or"box overlap; native button attempt",S.Attempts,"ETA",entry)
                task.spawn(function()
                    if not S.Enabled or generation~=S.Generation or LP.Character~=c then return end
                    local ok,err=pcall(handler)
                    if not ok then
                        log("native button error",tostring(err));S:SetEnabled(false);S.Status="Native hotbar handler failed";return
                    end
                    task.wait(.4)
                    if generation~=S.Generation then return end
                    if S.PendingInput==attempt then S.PendingInput=nil end
                    if attempt.Observed or cooldown(c)then S.Actions+=1;S.Status="DODGE! cooldown observed";log("activation cooldown confirmed")
                    else S.Status="Native button called; no cooldown confirmed";log("no activation cooldown")end
                end)
                return
            end
        end
    end
end
function S:SetEnabled(value)
    if self.Destroyed then return end
    self.Enabled=value==true;self.Generation+=1
    if heartbeat then heartbeat:Disconnect();heartbeat=nil end
    for _,w in pairs(watches)do w.Connection:Disconnect()end;table.clear(watches);table.clear(threats)
    if not self.Enabled then self.Status="Off";log("OFF");return end
    lastScan=0;elapsed=0
    heartbeat=Run.Heartbeat:Connect(function(dt)
        elapsed+=dt;if elapsed<1/30 then return end;elapsed=0
        local started=os.clock();local ok,err=pcall(step)
        local duration=(os.clock()-started)*1000;self.MaxStepMs=math.max(self.MaxStepMs,duration)
        if not ok or duration>50 then self:SetEnabled(false);self.Status="Stopped by error / timing guard";log("GUARD STOP",tostring(err),duration)end
    end)
    self.Status="Watching knife / weak-fist threats";log("ON")
end
function S:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Actions=self.Actions,Attempts=self.Attempts,MaxStepMs=self.MaxStepMs}end
function S:Destroy()if self.Destroyed then return end;self:SetEnabled(false);self.Destroyed=true;if env.__ALLEN_HNS_dodge==self then env.__ALLEN_HNS_dodge=nil end end
env.__ALLEN_HNS_dodge=S
return S

