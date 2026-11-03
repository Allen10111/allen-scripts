-- Allen Scripts adapter for the Cobalt loader used by Infinite Yield's remotespy command.
-- Upstream Cobalt: https://gitlab.com/upio/cobalt/ (deivid / upio).
-- No interception hooks are installed by this adapter itself. Starts OFF.
local URL="https://gitlab.com/upio/cobalt/-/releases/permalink/latest/downloads/Cobalt.luau"
local applyProfile=(function()
-- Reduce optional interception; this does not establish anti-cheat invisibility.
local function replaceOnce(source,needle,replacement)
    local first,last=source:find(needle,1,true)
    assert(first,"Cobalt source changed; reduced-interception profile needs review")
    assert(not source:find(needle,last+1,true),"Ambiguous Cobalt profile anchor; load aborted")
    return source:sub(1,first-1)..replacement..source:sub(last+1)
end
return function(source)
    source=source:gsub("\r\n","\n")
    local needle=[[local OptionsTemplate: Options = {
	IncomingConnections = true,
	IncomingCallbacks = true,
	HookIncomingConnections = true,
	Outgoing = true,
	Actors = true,
}]]
    local replacement=[[local OptionsTemplate: Options = {
	IncomingConnections = true,
	IncomingCallbacks = false,
	HookIncomingConnections = false,
	Outgoing = true,
	Actors = false,
}]]
    source=replaceOnce(source,needle,replacement)
    source=replaceOnce(source,"SaveManager.State = State",[[SaveManager.State = State
    -- Allen hub session profile, applied before interception initializes.
    State.EnableLogging = false
    State.ExecuteOnTeleport = false
    State.LogActors = false
    State.LogRobloxInternalEvents = false
    State.LogBlockedRemotes = false
    State.IgnorePlayerModule = true
    State.AutoIgnoreSpammyEvents = true
    State.DisableNonEssentialChecks = false
    State.RakNetHooks = false]])
    return source
end

end)()
local env=getgenv()
if env.__ALLEN_REMOTE_SPY then env.__ALLEN_REMOTE_SPY:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Loading=false,Status="Off",Generation=0}
local owned
local function sharedOf(value)
    return type(value)=="table"and type(value.shared)=="table"and value.shared or nil
end
local function unload()
    local current=owned;owned=nil
    local shared=sharedOf(current)
    if shared and not shared.Unloaded then
        assert(type(shared.Unload)=="function","Cobalt unload API changed; use Cobalt's own unload control")
        shared.Unload()
    end
end
function S:SetEnabled(value)
    if self.Destroyed then return end
    if value~=true then
        self.Generation+=1;self.Enabled=false
        local ok,err=pcall(unload)
        self.Status=ok and (self.Loading and "Cancelling Cobalt load"or"Off")or("Unload failed: "..tostring(err):sub(1,110))
        return
    end
    if self.Enabled then return end
    assert(not self.Loading,"Wait for the previous Cobalt load to finish")
    assert(not env.Cobalt and not env.CobaltInitialized,"Cobalt is already running or initializing; unload it first")
    self.Generation+=1;local generation=self.Generation
    self.Enabled=true;self.Loading=true;self.Status="Loading Cobalt · reduced interception profile"
    task.spawn(function()
        local startedHere=false
        local ok,err=pcall(function()
            local source=game:HttpGet(URL)
            assert(type(source)=="string"and #source>0,"Cobalt download was empty")
            if generation~=self.Generation or self.Destroyed then return end
            assert(not env.Cobalt and not env.CobaltInitialized,"Another Cobalt instance started during download")
            source=applyProfile(source)
            local fn,compileError=loadstring(source,"AllenCobaltUpstream")
            assert(fn,compileError)
            startedHere=true;fn()
            -- Official bundle starts its entrypoint asynchronously.
            local deadline=os.clock()+60
            while not env.Cobalt and os.clock()<deadline do task.wait(.1)end
            local current=env.Cobalt;local shared=sharedOf(current)
            assert(shared and type(shared.Unload)=="function","Cobalt did not expose its unload API; restart before retrying")
            owned=current
            if generation~=self.Generation or self.Destroyed or not self.Enabled then unload();return end
            self.Status="Cobalt open · reduced interception"
        end)
        self.Loading=false
        if not ok then
            self.Enabled=false;self.Status="Cobalt failed: "..tostring(err):sub(1,150)
            if startedHere then pcall(unload)end
            warn("[Allen Remote Spy] "..tostring(err))
        elseif not self.Enabled then self.Status="Off"end
    end)
end
function S:GetSnapshot()
    local shared=sharedOf(owned)
    if owned and (env.Cobalt~=owned or shared and shared.Unloaded)then
        owned=nil;self.Enabled=false;self.Status="Cobalt closed"
    end
    return {Enabled=self.Enabled,Status=self.Status,Loading=self.Loading}
end
function S:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
    if env.__ALLEN_REMOTE_SPY==self then env.__ALLEN_REMOTE_SPY=nil end
end
env.__ALLEN_REMOTE_SPY=S
return S

