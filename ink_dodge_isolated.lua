-- Isolated DODGE! controller: no map index, pathfinding, movement, remotes or module hooks.
assert(game.GameId==7008097940,"Open Ink Game")
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local Run=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
assert(UIS.KeyboardEnabled and not UIS.TouchEnabled,"DODGE! is PC-only; disabled on mobile after Roblox closure reports")
local env=getgenv()
if env.__ALLEN_HNS_dodge then env.__ALLEN_HNS_dodge:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Actions=0,Attempts=0,Status="Off",MaxStepMs=0,Generation=0}
local animationIds={}
local animations=RS:FindFirstChild("Animations");animations=animations and animations:FindFirstChild("Abilities")
animations=animations and animations:FindFirstChild("Knife")
if animations then for _,v in ipairs(animations:GetChildren())do
    local name=v.Name:lower()
    if v:IsA("Animation") and name:find("swing",1,true) and not name:find("victim",1,true)then
        local id=v.AnimationId:match("%d+");if id then animationIds[id]=name:find("lunge",1,true)and 14 or 8 end
    end
end end
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
local function slotKey()
    local pg=LP:FindFirstChildOfClass("PlayerGui");local bar=pg and pg:FindFirstChild("Hotbar")
    bar=bar and bar:FindFirstChild("Backpack");bar=bar and bar:FindFirstChild("Hotbar")
    if not bar then return end
    for _,button in ipairs(bar:GetChildren())do
        local label=button:FindFirstChild("ToolName");local number=button:FindFirstChild("Number")
        if button:IsA("GuiButton")and button.Visible and label and label.Text=="DODGE!"and number then
            local text=number.Text:gsub("%s+",""):upper()
            local n=tonumber(text)
            if n and n>=0 and n<=9 then return 48+n end
            if text=="E"or text=="T"or text=="Y"then return string.byte(text)end
        end
    end
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
                        if not S.Enabled or not c:FindFirstChild("Knife")then return end
                        local id=track.Animation and track.Animation.AnimationId:match("%d+")
                        local range=id and animationIds[id]
                        if range then
                            threats[p]={Character=c,Track=track,Range=range,Expires=os.clock()+1.2,Attempted=false}
                            log("swing",p.Name,id)
                        end
                    end)}
                end
            end
        end
    end
    for p,w in pairs(watches)do if present[p]~=w.Animator then w.Connection:Disconnect();watches[p]=nil;threats[p]=nil end end
end
local function overlaps(root,target,range)
    -- OBB estimate; no exact server HitboxSize is available. Body radius is included.
    local point=root.CFrame:PointToObjectSpace(target.Position)
    return -point.Z>=-.75 and -point.Z<=range+.75 and math.abs(point.X)<=4.25 and math.abs(point.Y)<=5.75
end
local function step()
    local now=os.clock()
    if now-lastScan>=.5 then lastScan=now;scan()end
    local c,h,r=live(LP);if not c then return end
    local bag=LP:FindFirstChildOfClass("Backpack")
    if not(c:FindFirstChild("DODGE!")or bag and bag:FindFirstChild("DODGE!"))then S.Status="DODGE! item required";return end
    if cooldown(c)then if S.PendingInput then S.PendingInput.Observed=true end;S.Status="Native DODGE! cooldown · waiting";return end
    if c:FindFirstChild("Ragdoll")or c:FindFirstChild("Stun")or c:FindFirstChild("DisableTools")then S.Status="Waiting for recovery";return end
    if now>statusUntil then S.Status="Watching estimated knife box · one press per swing"end
    for p,t in pairs(threats)do
        if now>t.Expires or not t.Track.IsPlaying or p.Character~=t.Character then threats[p]=nil
        elseif not t.Attempted and now-lastAttempt>=.55 then
            local attacker,_,root=live(p)
            if attacker and attacker:FindFirstChild("Knife")and overlaps(root,r,t.Range)then
                if UIS:GetFocusedTextBox()then S.Status="Close text input to dodge";return end
                local key=slotKey()
                if not key then S.Status="DODGE! hotbar key unavailable";return end
                -- Consume before spawning: each animation record gets at most one input pair.
                t.Attempted=true;lastAttempt=now;S.Attempts+=1;statusUntil=now+2
                local generation=S.Generation
                local attempt={Observed=false};S.PendingInput=attempt
                log("box overlap; key attempt",key,S.Attempts)
                task.spawn(function()
                    if not S.Enabled or generation~=S.Generation or LP.Character~=c then return end
                    local ok,err=pcall(function()
                        assert(type(keypress)=="function"and type(keyrelease)=="function","Executor keypress/keyrelease required")
                        keypress(key)
                    end)
                    task.wait(.04)
                    local released,releaseError=pcall(function()keyrelease(key)end)
                    if not ok or not released then
                        log("input error",tostring(err or releaseError));S:SetEnabled(false);S.Status="Input API failed";return
                    end
                    task.wait(.4)
                    if generation~=S.Generation then return end
                    if S.PendingInput==attempt then S.PendingInput=nil end
                    if attempt.Observed or cooldown(c)then S.Actions+=1;S.Status="DODGE! cooldown observed";log("activation cooldown confirmed")
                    else S.Status="Key sent; no cooldown confirmed";log("no activation cooldown")end
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
    self.Status="Watching knife threats";log("ON")
end
function S:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Actions=self.Actions,Attempts=self.Attempts,MaxStepMs=self.MaxStepMs}end
function S:Destroy()if self.Destroyed then return end;self:SetEnabled(false);self.Destroyed=true;if env.__ALLEN_HNS_dodge==self then env.__ALLEN_HNS_dodge=nil end end
env.__ALLEN_HNS_dodge=S
return S

