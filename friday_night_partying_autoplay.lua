-- Allen Scripts: Friday Night Partying native note scheduler. Hub only.
assert(game.GameId==10258128048,"Open Friday Night Partying")
assert(debug and type(debug.getupvalues)=="function" and type(getconnections)=="function","Executor needs getconnections and debug.getupvalues")
local env=getgenv()
if env.__FNP_AUTOPLAY then env.__FNP_AUTOPLAY:Destroy()end
local LP=game:GetService("Players").LocalPlayer
local ui=LP:WaitForChild("PlayerGui"):WaitForChild("GameUI",10)
assert(ui and ui:FindFirstChild("GameHandler"),"Game engine not ready")
local handler=require(ui.GameHandler)
local native=getfenv(handler.genSong)
local good=native.Goodhit
local modules=game.ReplicatedStorage.Modules
local conductor=require(modules.Conductor)
local inputs=require(modules.UserInputBindables)
local began,check
for _,c in ipairs(getconnections(inputs.InputEvents.Began))do
    local f=c.Function
    if f and debug.info(f,"s")==ui.GameHandler:GetFullName() then
        local candidate=debug.getupvalues(f)[2]
        if type(candidate)=="function" and debug.info(candidate,"n")=="CheckInput"then began=f;check=candidate;break end
    end
end
assert(type(good)=="function" and check,"Native note handlers unavailable")
local layout=debug.getupvalues(check)
assert(type(layout[4])=="table" and type(layout[5])=="table" and type(layout[7])=="table","Unsupported lane engine layout")
local state={HubOnly=true,Enabled=false,Destroyed=false,Hits=0,Holds=0,Errors=0,Skipped=0,Held={},Status="Off",Seen=setmetatable({},{__mode="k"})}
local function call(fn,...)
    local gi=getthreadidentity or getidentity;local si=setthreadidentity or setidentity
    local identity=gi and gi();if si and identity then si(2)end
    local ok,err=pcall(fn,...)
    if si and identity then si(identity)end
    if not ok then error(err,0)end
end
local function release(receptor)
    receptor.Holding=false
    call(receptor.PlayAnimation,receptor,"static")
end
function state:Release()
    for receptor in pairs(self.Held)do
        pcall(release,receptor)
    end
    table.clear(self.Held)
end
function state:SetEnabled(value)
    self:Release();self.Enabled=value==true and not self.Destroyed
    self.Status=self.Enabled and "Waiting for song"or"Off"
end
function state:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Hits=self.Hits,Holds=self.Holds,Skipped=self.Skipped,Errors=self.Errors,LastError=self.LastError}
end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if self.Connection then self.Connection:Disconnect()end
    if env.__FNP_AUTOPLAY==self then env.__FNP_AUTOPLAY=nil end
end
function state:UpdateHold(note,receptor)
    if note.IsSustain and not note.IsSusEnd then
        self.Held[receptor]=true
        receptor.Holding=true
        self.Holds+=1
        return
    end
    if note.IsSusEnd then
        self.Held[receptor]=nil
        release(receptor)
        return
    end
    if not self.Held[receptor] then
        release(receptor)
    end
    self.Hits+=1
end
function state:Step(dt)
    if not debug.getupvalues(began)[1] or not ui.Enabled then self:Release();self.Status="Waiting for song";return end
    local up=debug.getupvalues(check)
    local heads,receptors,tails=up[4],up[5],up[7]
    local now=conductor.SongPos
    if type(now)~="number"or now~=now then return end
    local due={};local scanned=0
    local lead=math.min(dt*500,8)
    for _,group in ipairs({heads,tails})do
        for lane,notes in pairs(group)do
            local receptor=receptors[lane]
            for _,note in ipairs(notes)do
                scanned+=1;if scanned>2048 then error("Active note limit exceeded")end
                if not note.Destroyed and not note.GoodHit and note.MustPress and not self.Seen[note] then
                    if note.shouldPress==false or (tonumber(note.HealthLoss)or 0)>0 then
                        self.Seen[note]=true;self.Skipped+=1
                    elseif note.CanBeHit and not note.TooLate and receptor and receptor.CanBePressed
                        and type(note.StrumTime)=="number" and note.StrumTime-now<=lead and note.StrumTime-now>=-100 then
                        due[#due+1]={Note=note,Receptor=receptor}
                    end
                end
            end
        end
    end
    table.sort(due,function(a,b)return a.Note.StrumTime<b.Note.StrumTime end)
    for _,entry in ipairs(due)do
        local note=entry.Note
        if not note.GoodHit and not note.Destroyed then
            call(good,note)
            self.Seen[note]=true
            if note.GoodHit then
                self:UpdateHold(note,entry.Receptor)
            end
        end
    end
    self.Status="Playing · native note timing"
end
state.Connection=game:GetService("RunService").RenderStepped:Connect(function(dt)
    if not state.Enabled or state.Destroyed then return end
    local ok,err=pcall(state.Step,state,dt)
    if not ok then state.Errors+=1;state.LastError=tostring(err);state:SetEnabled(false);state.Status="Stopped: "..tostring(err):sub(1,100);warn("[FNP Autoplay] "..tostring(err))end
end)
env.__FNP_AUTOPLAY=state
return state
