local MODE="lighter"
-- Headless Dalgona controls. MODE is supplied by the hub build.
-- Uses the validated native Dalgona frame; no remote hooks or input injection.
assert(game.GameId==7008097940,"Open Ink Game to use Dalgona")
assert(type(getconnections)=="function" and debug and type(debug.getupvalues)=="function"
    and type(debug.setupvalue)=="function" and type(debug.info)=="function",
    "Dalgona requires connection and upvalue APIs supported by this executor")
local env=getgenv()
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local RunService=game:GetService("RunService")
local M=env.__ALLEN_DALGONA_MANAGER
if not M or M.Destroyed then
    M={Controllers={},Context=nil,NextScan=0,Destroyed=false}
    env.__ALLEN_DALGONA_MANAGER=M
    local I={Cookie=3,Outline=6,Player=9,LighterReady=11,LighterModel=12,LighterViewport=13,
        LighterCamera=14,OpenTrack=20,CloseTrack=22,Flame=23,LighterGeneration=24,
        LighterOpen=25,Character=27,Progress=35,Total=36,Allowance=37,Finishing=39,
        Cracks=40,CrackFunction=41,Completed=42,Remote=45,CloseLighter=65,Guard=79}
    local function is(value,class)
        return typeof(value)=="Instance" and value:IsA(class)
    end
    local function enabled(mode)
        local c=M.Controllers[mode];return c and c.Enabled and not c.Destroyed
    end
    local function active()
        local c=LP.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local values=workspace:FindFirstChild("Values")
        local current=values and values:FindFirstChild("CurrentGame")
        return current and current.Value=="Dalgona" and h and h.Health>0 and not c:FindFirstChild("Dead")
    end
    local function write(context,index,value)
        debug.setupvalue(context.Function,index,value)
    end
    local function valid(context)
        return context and context.Connection.Connected~=false and context.Cookie.Parent and context.Outline.Parent
            and context.Character==LP.Character
    end
    local function releaseGuard(context)
        if context and context.GuardOwned then
            local ok,u=pcall(debug.getupvalues,context.Function)
            if ok and u[I.Guard]==true then pcall(write,context,I.Guard,context.OriginalGuard) end
            context.GuardOwned=false
        end
    end
    local function releaseLighter(context)
        if M.LighterSet then
            if LP:GetAttribute("HasLighter")==true then LP:SetAttribute("HasLighter",M.OriginalLighter) end
            M.LighterSet=false;M.OriginalLighter=nil
        end
        if not context or not context.LighterOwned then return end
        context.LighterOwned=false
        -- Invalidate native animation timers before clearing our temporary lighter.
        local u=debug.getupvalues(context.Function)
        write(context,I.LighterGeneration,(u[I.LighterGeneration] or 0)+2)
        write(context,I.LighterOpen,nil)
        local close=u[I.CloseLighter]
        if type(close)=="function" then
            local values=debug.getupvalues(close)
            local sound=values[8] -- u62, validated against the native close-lighter closure.
            if is(sound,"Sound") then sound:Stop();sound:Destroy();debug.setupvalue(close,8,nil) end
        end
        for _,index in ipairs({I.OpenTrack,I.CloseTrack}) do
            local track=u[index]
            if is(track,"AnimationTrack") then track:Stop(0);track:Destroy() end
            write(context,index,nil)
        end
        for _,index in ipairs({I.LighterModel,I.LighterViewport,I.LighterCamera,I.Flame}) do
            local object=u[index]
            if typeof(object)=="Instance" then object:Destroy() end
            write(context,index,nil)
        end
        write(context,I.LighterReady,nil)
    end
    function M:DropContext()
        local context=self.Context
        pcall(releaseGuard,context);pcall(releaseLighter,context)
        self.Context=nil
    end
    local function scan()
        for _,connection in ipairs(getconnections(RunService.RenderStepped)) do
            local f=connection.Function
            if type(f)=="function" and connection.Connected~=false then
                local ok,source=pcall(debug.info,f,"s")
                if ok and tostring(source):find("DalgonaClient",1,true) then
                    local success,u=pcall(debug.getupvalues,f)
                    if success and is(u[I.Cookie],"Model") and is(u[I.Outline],"Model")
                        and u[I.Outline].Name==u[I.Cookie].Name.."Outline" and u[I.Player]==LP
                        and u[I.Character]==LP.Character and is(u[I.Remote],"RemoteEvent")
                        and type(u[I.Progress])=="number" and type(u[I.Total])=="number"
                        and u[I.Total]>0 and u[I.Progress]>=0 and u[I.Progress]<=u[I.Total]
                        and type(u[I.Allowance])=="number" and type(u[I.CrackFunction])=="function"
                        and type(u[I.CloseLighter])=="function" and type(u[I.LighterGeneration])=="number" then
                        local crack=debug.getupvalues(u[I.CrackFunction])
                        -- A second closure validates the same outline, cookie, crack counter and remote.
                        if crack[15]==u[I.Cookie] and crack[18]==u[I.Outline] and crack[10]==u[I.Remote]
                            and crack[4]==u[I.Cracks] then
                            return {Function=f,Connection=connection,Cookie=u[I.Cookie],Outline=u[I.Outline],
                                Character=u[I.Character],Shape=u[I.Cookie].Name,BoundAt=os.clock(),
                                Fear=is(crack[5],"NumberValue") and crack[5] or nil,AutoSubmitted=false}
                        end
                    end
                end
            end
        end
    end
    function M:Step()
        if not (enabled("auto") or enabled("lighter") or enabled("anticrack")) or not active() then
            if self.Context or self.LighterSet then self:DropContext() end
            for _,c in pairs(self.Controllers) do if c.Enabled then c.Status="Waiting for Dalgona" end end
            return
        end
        if not valid(self.Context) then
            self:DropContext()
            if os.clock()<self.NextScan then return end
            self.NextScan=os.clock()+.5;self.Context=scan()
        end
        local context=self.Context
        if not context then
            for _,c in pairs(self.Controllers) do if c.Enabled then c.Status="Waiting for native cookie controller" end end
            return
        end
        local u=debug.getupvalues(context.Function)
        if enabled("anticrack") then
            if not context.GuardOwned then context.OriginalGuard=u[I.Guard];context.GuardOwned=true end
            write(context,I.Guard,true)
            if context.Fear and context.Fear.Value~=0 then context.Fear.Value=0 end
            self.Controllers.anticrack.Status="Wrong-click protection · "..context.Shape
        else releaseGuard(context) end
        if enabled("lighter") then
            if not self.LighterSet then
                self.OriginalLighter=LP:GetAttribute("HasLighter");self.LighterSet=true
                context.LighterOwned=not u[I.LighterReady] and self.OriginalLighter~=true
                LP:SetAttribute("HasLighter",true)
            end
            self.Controllers.lighter.Status=u[I.LighterReady] and "Native lighter ready · hold to use" or "Enabling native lighter"
        elseif self.LighterSet then releaseLighter(context) end
        if enabled("auto") then
            local c=self.Controllers.auto
            local remaining=workspace:GetAttribute("CurrentGameTime")
            if u[I.Finishing] or u[I.Completed] then
                c.Status=context.AutoSubmitted and "Native completion triggered · awaiting server result" or "Cookie already finished"
            elseif type(remaining)=="number" and remaining<=0 then
                c.Status="Dalgona timer ended"
            elseif not context.AutoSubmitted and os.clock()-context.BoundAt>=.35 then
                -- The game's next frame performs its own Completed request, visuals and cleanup.
                write(context,I.Progress,u[I.Total])
                context.AutoSubmitted=true;c.Requests+=1
                c.Status="Completing "..context.Shape
            end
        end
    end
    local elapsed=0
    M.Connection=RunService.Heartbeat:Connect(function(dt)
        if M.Destroyed then return end
        elapsed+=dt;if elapsed<.05 then return end;elapsed=0
        local ok,err=pcall(M.Step,M)
        if not ok then
            for _,c in pairs(M.Controllers) do c.Enabled=false;c.Status="Stopped: "..tostring(err):sub(1,120) end
            M:DropContext();warn("[Allen Dalgona] "..tostring(err))
        end
    end)
    function M:Create(mode)
        local key="__ALLEN_DALGONA_"..mode
        if self.Controllers[mode] then
            self.Controllers[mode]:SetEnabled(false)
            self.Controllers[mode].Destroyed=true
        end
        local c={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Requests=0}
        function c:SetEnabled(value)
            if self.Destroyed then return end
            self.Enabled=value==true
            if not self.Enabled then
                if mode=="anticrack" then releaseGuard(M.Context) end
                if mode=="lighter" then releaseLighter(M.Context) end
                self.Status="Off"
            else self.Status="Waiting for Dalgona";M.NextScan=0;M:Step() end
        end
        function c:GetSnapshot() return {Enabled=self.Enabled,Status=self.Status,Requests=self.Requests} end
        function c:Destroy()
            if self.Destroyed then return end
            self:SetEnabled(false);self.Destroyed=true
            if M.Controllers[mode]==self then M.Controllers[mode]=nil end
            if env[key]==self then env[key]=nil end
            if not next(M.Controllers) then
                M:DropContext();M.Destroyed=true;M.Connection:Disconnect()
                if env.__ALLEN_DALGONA_MANAGER==M then env.__ALLEN_DALGONA_MANAGER=nil end
            end
        end
        self.Controllers[mode]=c;env[key]=c
        return c
    end
end
return M:Create(MODE)

