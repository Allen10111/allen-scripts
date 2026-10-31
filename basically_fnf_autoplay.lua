-- Allen Scripts: Basically FNF: Remix. Native lane input, hub controls only.
assert(game.GameId==2443177453,"Open Basically FNF: Remix")
assert(type(getfenv)=="function" and debug and type(debug.getupvalues)=="function","Executor requires getfenv and debug.getupvalues")
local env=getgenv()
if env.__BFNF_AUTOPLAY then env.__BFNF_AUTOPLAY:Destroy() end
local LP=game:GetService("Players").LocalPlayer
local main=LP:WaitForChild("PlayerGui"):WaitForChild("Main",10)
assert(main and main:FindFirstChild("FNFMain"),"Note engine not ready")
local module=require(main.FNFMain.Modules.songPlay)
local native=getfenv(module.PlaySong)
assert(type(native.KeyPress)=="function" and type(native.KeyLift)=="function" and type(native.NoteInput)=="function","Native input handlers unavailable")
local function up(fn) return debug.getupvalues(fn) end
-- Validate the inspected native layout before accessing mutable lane data.
local p,n=up(native.KeyPress),up(native.NoteInput)
assert(type(p[3])=="function" and type(p[5])=="table" and typeof(n[3])=="Instance" and type(n[5])=="table" and type(n[6])=="table","Unsupported note engine layout")
local state={HubOnly=true,Enabled=false,Destroyed=false,Held={},Seen=setmetatable({},{__mode="k"}),Hits=0,Holds=0,Errors=0,Status="Off"}
local function call(fn,...)
    local getid=getthreadidentity or getidentity
    local setid=setthreadidentity or setidentity
    local id=getid and getid()
    if setid and id then setid(2) end
    local ok,err=pcall(fn,...)
    if setid and id then setid(id) end
    if not ok then error(err,0) end
end
function state:ReleaseLane(lane)
    local h=self.Held[lane]
    if h then self.Held[lane]=nil;call(native.KeyLift,h.Input,false) end
end
function state:Release()
    for lane=1,4 do local ok,err=pcall(self.ReleaseLane,self,lane);if not ok then self.LastError=tostring(err) end end
end
function state:SetEnabled(value)
    self:Release();self.Enabled=value==true and not self.Destroyed
    self.Status=self.Enabled and "Waiting for song" or "Off"
end
function state:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Hits=self.Hits,Holds=self.Holds,Errors=self.Errors,LastError=self.LastError}
end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if self.Connection then self.Connection:Disconnect() end
    if env.__BFNF_AUTOPLAY==self then env.__BFNF_AUTOPLAY=nil end
end
function state:Step(dt)
    local press=up(native.KeyPress)
    local noteUp=up(native.NoteInput)
    local active,side=press[1],press[8]
    if not active or not main.MatchFrame.Visible or not LP:FindFirstChild("CurrentMatch") then
        self:Release();self.Status="Waiting for song";return
    end
    local lanes=noteUp[5][side]
    local settings=getfenv(native.NoteInput)._G.Settings
    local direction=settings.Direction
    local speed=tonumber(noteUp[4])
    if not lanes or not speed or speed<=0 or (direction~=1 and direction~=-1) then self:Release();self.Status="Waiting for lanes";return end
    local keys=up(press[3])[1]
    local now=os.clock()
    self.Status="Playing · native lanes"
    for lane=1,4 do
        local data=lanes[lane]
        local h=self.Held[lane]
        if h then
            local hold=data and data.holding
            if h.Side~=side or not hold or not hold.Parent then
                if h.Side~=side or now>=h.ReleaseAt then self:ReleaseLane(lane) end
            elseif math.abs(hold.Size.Y.Scale)+hold.Position.Y.Scale*direction<=0.5 then
                self:ReleaseLane(lane)
            end
        end
        if data then
            local idx=data.index
            local note=data.notes[idx]
            -- Mirror the native closest-note choice without modifying its index.
            local nextNote=data.notes[idx+1]
            if nextNote and nextNote.Parent and (not note or not note.Parent or math.abs(nextNote.Position.Y.Scale)<math.abs(note.Position.Y.Scale)) then note=nextNote end
            if note and note.Parent and not self.Seen[note] then
                local timeLeft=note.Position.Y.Scale*direction/(5.5*speed)
                -- Render-step midpoint targeting; late notes outside the native window are skipped.
                if timeLeft<=math.min(dt*0.5,0.012) and timeLeft>=-0.11 then
                    if self.Held[lane] and not data.holding then self:ReleaseLane(lane) end
                    if not self.Held[lane] then
                        local key=keys and Enum.KeyCode[keys[lane]]
                        assert(key,"Lane keybinding unavailable")
                        local input={UserInputType=Enum.UserInputType.Keyboard,KeyCode=key}
                        call(native.KeyPress,input,false)
                        self.Held[lane]={Input=input,Side=side,ReleaseAt=now+0.025}
                        self.Seen[note]=true
                        if not note.Parent then self.Hits+=1;if data.holding then self.Holds+=1 end end
                    end
                end
            end
        end
    end
end
state.Connection=game:GetService("RunService").RenderStepped:Connect(function(dt)
    if not state.Enabled or state.Destroyed then return end
    local ok,err=pcall(state.Step,state,dt)
    if not ok then
        state.Errors+=1;state.LastError=tostring(err);state:Release()
        state.Enabled=false;state.Status="Stopped: "..tostring(err):sub(1,100)
        warn("[BFNF Autoplay] "..tostring(err))
    end
end)
env.__BFNF_AUTOPLAY=state
return state

