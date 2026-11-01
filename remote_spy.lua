-- Disabled after a confirmed BAC kick during logging.
error("Remote Spy disabled after BAC detection during testing")
-- Allen Scripts: local outbound remote logger. Starts OFF, no standalone UI.
local env=getgenv()
if env.__ALLEN_REMOTE_SPY then env.__ALLEN_REMOTE_SPY:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Calls=0,Dropped=0,Pending=0,Logs={},Status="Off"}
local bridge=env.__ALLEN_REMOTE_SPY_HOOK
if not bridge then bridge={};env.__ALLEN_REMOTE_SPY_HOOK=bridge end
local function preview(v,depth,seen)
    local kind=typeof(v)
    if kind=="string"then return string.format("%q",v:sub(1,220))..(#v>220 and "…"or"")end
    if kind=="Instance"then local ok,path=pcall(v.GetFullName,v);return ok and path or tostring(v)end
    if kind~="table"then return tostring(v)end
    if seen[v]then return "<cycle>"end
    if depth>=2 then return "<table>"end
    seen[v]=true
    local items={};local n=0
    for k,x in pairs(v)do
        n+=1;if n>8 then items[#items+1]="…";break end
        items[#items+1]="["..preview(k,depth+1,seen).."]="..preview(x,depth+1,seen)
    end
    seen[v]=nil
    return "{"..table.concat(items,", ").."}"
end
local function install()
    if bridge.Installed then return end
    assert(type(hookmetamethod)=="function" and type(getnamecallmethod)=="function" and type(newcclosure)=="function",
        "Remote Spy needs hookmetamethod, getnamecallmethod and newcclosure")
    local original
    original=hookmetamethod(game,"__namecall",newcclosure(function(object,...)
        local state=bridge.State
        if state and state.Enabled and not state.Destroyed then
            local method=getnamecallmethod()
            local ok,isRemote=pcall(function()
                local class=object.ClassName
                return (method=="FireServer"and(class=="RemoteEvent"or class=="UnreliableRemoteEvent"))
                    or(method=="InvokeServer"and class=="RemoteFunction")
            end)
            if ok and isRemote then
                local now=os.clock()
                if now>=(state.WindowEnds or 0)then state.WindowEnds=now+1;state.WindowCount=0 end
                if (state.WindowCount or 0)>=40 or state.Pending>=80 then state.Dropped+=1
                else
                    state.WindowCount=(state.WindowCount or 0)+1;state.Pending+=1
                    local args=table.pack(...)
                    task.defer(function()
                        state.Pending-=1
                        if not state.Enabled or state.Destroyed then return end
                        local rendered={}
                        local success,message=pcall(function()
                            for i=1,math.min(args.n,12)do rendered[i]=preview(args[i],0,{})end
                            if args.n>12 then rendered[#rendered+1]="…"end
                            local path=object:GetFullName()
                            local entry={Time=now,Method=method,Path=path,Arguments=table.concat(rendered,", ")}
                            state.Calls+=1;state.Logs[#state.Logs+1]=entry
                            if #state.Logs>100 then table.remove(state.Logs,1)end
                            state.Status=method.." · "..object.Name
                            print("[Remote Spy] "..method.." "..path.."("..entry.Arguments..")")
                        end)
                        if not success then state.LastError=tostring(message)end
                    end)
                end
            end
        end
        return original(object,...)
    end))
    bridge.Installed=true
end
function S:SetEnabled(value)
    if self.Destroyed then return end
    if value then install()end
    self.Enabled=value==true;self.Status=self.Enabled and "Logging outbound remotes"or"Off"
    bridge.State=self
    if self.Enabled then self:DumpRemotes()end
end
function S:DumpRemotes()
    self.DumpGeneration=(self.DumpGeneration or 0)+1
    local generation=self.DumpGeneration
    task.spawn(function()
        print("[Remote Spy] Remote instances have no script source. Server handlers are not replicated.")
        local ok,descendants=pcall(game.GetDescendants,game)
        if not ok then warn("[Remote Spy] Remote inventory failed: "..tostring(descendants));return end
        local count=0
        for i,object in ipairs(descendants)do
            if self.Destroyed or not self.Enabled or self.DumpGeneration~=generation then return end
            local class=object.ClassName
            if class=="RemoteEvent"or class=="RemoteFunction"or class=="UnreliableRemoteEvent"then
                local success,path=pcall(object.GetFullName,object)
                if success then count+=1;print("[Remote Spy / Inventory] "..class.." | "..path.." | Source: not applicable")end
            end
            if i%250==0 then task.wait()end
        end
        self.RemoteCount=count
        print("[Remote Spy] Inventory complete: "..count.." replicated remotes")
    end)
end
function S:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status.." · "..self.Calls.." calls",Dropped=self.Dropped,LastError=self.LastError}
end
function S:Clear()table.clear(self.Logs);self.Calls=0;self.Dropped=0 end
function S:Destroy()
    self.Enabled=false;self.Destroyed=true;self.Status="Off"
    if bridge.State==self then bridge.State=nil end
    table.clear(self.Logs)
    if env.__ALLEN_REMOTE_SPY==self then env.__ALLEN_REMOTE_SPY=nil end
end
env.__ALLEN_REMOTE_SPY=S
return S

