-- Original Allen Scripts Remote Inspector. Local-only, no third-party loader.
local Model=(function()
local M={}
function M.Preview(value,depth,seen,budget)
    if budget.Left<=0 then return "<limit>"end
    budget.Left-=1
    local kind=typeof(value)
    if kind=="nil"or kind=="boolean"or kind=="number"then return tostring(value)end
    if kind=="string"then return string.format("%q",value:sub(1,180))..(#value>180 and "…"or"")end
    if kind=="Instance"then local ok,path=pcall(value.GetFullName,value);return ok and path:sub(1,512)or"<destroyed instance>"end
    if kind~="table"then
        if kind=="Vector3"or kind=="Vector2"or kind=="CFrame"or kind=="Color3"or kind=="EnumItem"then return kind.."("..tostring(value):sub(1,200)..")"end
        return "<"..kind..">"
    end
    if seen[value]then return "<cycle>"end
    if depth>=3 then return "<table depth limit>"end
    seen[value]=true;local items={};local count=0
    for k,v in next,value do
        count+=1;if count>10 or budget.Left<=0 then items[#items+1]="…";break end
        items[#items+1]="["..M.Preview(k,depth+1,seen,budget).."]="..M.Preview(v,depth+1,seen,budget)
    end
    seen[value]=nil;return "{"..table.concat(items,", ").."}"
end
function M.Arguments(args)
    local result={};local budget={Left=50}
    for i=1,math.min(args.n or #args,10)do result[#result+1]=M.Preview(args[i],0,{},budget)end
    if (args.n or #args)>10 then result[#result+1]="<additional arguments omitted>"end
    return table.concat(result,", "):sub(1,2400)
end
function M.New()
    return {Queue={},Head=1,Tail=0,Logs={},Counts={},CountKeys=0,Total=0,Dropped=0,Window=0,WindowCount=0,Sequence=0}
end
function M.Enqueue(s,remote,direction,method,args,now)
    if now>=s.Window then s.Window=now+1;s.WindowCount=0 end
    if s.WindowCount>=40 or s.Tail-s.Head+1>=64 then s.Dropped+=1;return false end
    s.WindowCount+=1;s.Tail+=1
    s.Queue[s.Tail]={Remote=remote,Direction=direction,Method=method,Args=args,Time=now}
    return true
end
function M.Pop(s)
    if s.Head>s.Tail then return end
    local item=s.Queue[s.Head];s.Queue[s.Head]=nil;s.Head+=1
    if s.Head>s.Tail then s.Head=1;s.Tail=0 end
    return item
end
function M.Store(s,item,path)
    s.Sequence+=1;s.Total+=1
    local key=item.Direction..":"..path
    if s.Counts[key]or s.CountKeys<256 then
        if not s.Counts[key]then s.CountKeys+=1 end
        s.Counts[key]=(s.Counts[key]or 0)+1
    end
    local entry={Id=s.Sequence,Time=item.Time,Direction=item.Direction,Method=item.Method,
        Path=path:sub(1,512),Arguments=M.Arguments(item.Args),ArgumentCount=item.Args.n or #item.Args,Count=s.Counts[key]or 1}
    s.Logs[#s.Logs+1]=entry
    if #s.Logs>200 then table.remove(s.Logs,1)end
    return entry
end
function M.Matches(entry,query,direction)
    return (direction=="All"or entry.Direction==direction)and
        (query==""or (entry.Path.." "..entry.Method.." "..entry.Arguments):lower():find(query:lower(),1,true)~=nil)
end
return M

end)()
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Http=game:GetService("HttpService")
local LP=Players.LocalPlayer
local env=getgenv()
if env.__ALLEN_REMOTE_SPY then env.__ALLEN_REMOTE_SPY:Destroy()end
local bridge=env.__ALLEN_INSPECTOR_BRIDGE or {};env.__ALLEN_INSPECTOR_BRIDGE=bridge
local S={HubOnly=true,Enabled=false,Destroyed=false,Paused=false,Status="Off",Connections={},UIConnections={},
    Data=Model.New(),Ignored={},Query="",Direction="All",Generation=0,RemoteCount=0,IncomingCount=0}
local function connect(signal,fn,ui)
    local connection=signal:Connect(fn);table.insert(ui and S.UIConnections or S.Connections,connection);return connection
end
local pathRoots={{game:GetService("ReplicatedStorage"),"ReplicatedStorage"},{workspace,"Workspace"},{Players,"Players"}}
local function remotePath(object)
    for _,root in ipairs(pathRoots)do
        if object==root[1]or object:IsDescendantOf(root[1])then
            local parts={};local current=object
            while current and current~=root[1]and #parts<64 do
                table.insert(parts,1,"["..string.format("%q",current.Name).."]");current=current.Parent
            end
            return "game:GetService("..string.format("%q",root[2])..")"..table.concat(parts)
        end
    end
    return object:GetFullName()
end
local function capture(remote,direction,method,...)
    if S.Enabled and not S.Destroyed and not S.Paused then
        Model.Enqueue(S.Data,remote,direction,method,table.pack(...),os.clock())
    end
end
local function install()
    if bridge.Installed then return end
    assert(type(hookmetamethod)=="function"and type(getnamecallmethod)=="function"and type(newcclosure)=="function",
        "Outgoing capture requires hookmetamethod/getnamecallmethod/newcclosure")
    local old
    old=hookmetamethod(game,"__namecall",newcclosure(function(object,...)
        local state=bridge.State
        if state and state.Enabled and not state.Destroyed and not state.Paused then
            local method=getnamecallmethod()
            if method=="FireServer"or method=="InvokeServer"then
                local class=typeof(object)=="Instance"and object.ClassName
                if (method=="FireServer"and(class=="RemoteEvent"or class=="UnreliableRemoteEvent"))
                    or(method=="InvokeServer"and class=="RemoteFunction")then
                    -- Never serialize, yield, replay, block or alter arguments inside the hook.
                    pcall(Model.Enqueue,state.Data,object,"Out",method,table.pack(...),os.clock())
                end
            end
        end
        return old(object,...)
    end))
    bridge.Installed=true
end
local function watchRemotes(generation)
    local seen=setmetatable({},{__mode="k"});local events={};local queue={game:GetService("ReplicatedStorage"),workspace,LP};local head=1
    while head<=#queue and head<=180000 and S.Enabled and generation==S.Generation do
        local object=queue[head];head+=1
        if not seen[object]then
            seen[object]=true
            if object:IsA("RemoteEvent")or object:IsA("UnreliableRemoteEvent")or object:IsA("RemoteFunction")then
                S.RemoteCount+=1
                if not object:IsA("RemoteFunction")and S.IncomingCount<256 then
                    S.IncomingCount+=1
                    events[object]=true
                    connect(object.OnClientEvent,function(...)capture(object,"In","OnClientEvent",...)end)
                end
            end
            for _,child in ipairs(object:GetChildren())do queue[#queue+1]=child end
        end
        if head%200==0 then task.wait()end
    end
    -- Observe newly replicated remotes without replacing OnClientInvoke callbacks.
    if not S.Enabled or generation~=S.Generation then return end
    local function added(object)
        if seen[object]then return end
        if object:IsA("RemoteEvent")or object:IsA("UnreliableRemoteEvent")or object:IsA("RemoteFunction")then
            seen[object]=true;S.RemoteCount+=1
            if not object:IsA("RemoteFunction")and S.IncomingCount<256 then
                S.IncomingCount+=1;connect(object.OnClientEvent,function(...)capture(object,"In","OnClientEvent",...)end)
            end
        end
    end
    for _,root in ipairs({game:GetService("ReplicatedStorage"),workspace,LP})do connect(root.DescendantAdded,added)end
    S.Status="Capturing · incoming events + outgoing calls"
end
function S:Clear()
    self.Data=Model.New();self.Selected=nil;self.Dirty=true
end
function S:Export()
    return Http:JSONEncode({Tool="Allen Remote Inspector",Version=1,GameId=game.GameId,PlaceId=game.PlaceId,
        Captured=self.Data.Total,Dropped=self.Data.Dropped,Entries=self.Data.Logs})
end
local function createUI()
    local gui=Instance.new("ScreenGui");gui.Name="AllenRemoteInspector";gui.ResetOnSpawn=false;gui.DisplayOrder=35
    gui.IgnoreGuiInset=true;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Parent=LP:WaitForChild("PlayerGui")
    S.Gui=gui
    local function make(class,parent,props)
        local item=Instance.new(class);for k,v in pairs(props)do item[k]=v end;item.Parent=parent;return item
    end
    local panel=make("Frame",gui,{BackgroundColor3=Color3.fromRGB(8,8,10),BorderSizePixel=0,Active=true})
    make("UICorner",panel,{CornerRadius=UDim.new(0,12)})
    make("UIStroke",panel,{Color=Color3.fromRGB(48,48,54),Thickness=1})
    local function text(parent,content,size)
        return make("TextLabel",parent,{BackgroundTransparency=1,Text=content,TextColor3=Color3.fromRGB(235,235,240),
            Font=Enum.Font.Gotham,TextSize=size or 12,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
    end
    local function button(content)
        local b=make("TextButton",panel,{Text=content,TextColor3=Color3.fromRGB(225,225,230),TextSize=12,Font=Enum.Font.Gotham,
            BackgroundColor3=Color3.fromRGB(27,27,32),BorderSizePixel=0,AutoButtonColor=true})
        make("UICorner",b,{CornerRadius=UDim.new(0,6)});return b
    end
    local title=text(panel,"ALLEN  /  REMOTE INSPECTOR",14);title.Font=Enum.Font.GothamBold
    local close=button("×");local pause=button("Pause");local clear=button("Clear");local export=button("Export JSON");local direction=button("All directions")
    local query=make("TextBox",panel,{Text="",PlaceholderText="Search remote paths, methods or arguments…",ClearTextOnFocus=false,
        TextColor3=Color3.fromRGB(235,235,240),PlaceholderColor3=Color3.fromRGB(130,130,140),TextSize=12,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,BackgroundColor3=Color3.fromRGB(22,22,27),BorderSizePixel=0})
    make("UICorner",query,{CornerRadius=UDim.new(0,6)});make("UIPadding",query,{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)})
    local summary=text(panel,"",11)
    local list=make("ScrollingFrame",panel,{BackgroundColor3=Color3.fromRGB(14,14,18),BorderSizePixel=0,ScrollBarThickness=5,
        CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.None,ScrollingDirection=Enum.ScrollingDirection.Y})
    local detail=make("ScrollingFrame",panel,{BackgroundColor3=Color3.fromRGB(17,17,21),BorderSizePixel=0,ScrollBarThickness=4,
        CanvasSize=UDim2.new(0,0,0,420),ScrollingDirection=Enum.ScrollingDirection.Y})
    local detailText=make("TextBox",detail,{BackgroundTransparency=1,Text="Select a call to inspect its captured snapshot.",TextEditable=false,
        ClearTextOnFocus=false,MultiLine=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
        Font=Enum.Font.Code,TextSize=12,TextColor3=Color3.fromRGB(210,210,220),Position=UDim2.fromOffset(10,8),Size=UDim2.new(1,-24,0,600)})
    local copy=button("Copy details");local ignore=button("Ignore remote");local foot=text(panel,"Local snapshots · no automatic replay · 200-record limit",10)
    local pool={};local selected
    local function show(entry)
        selected=entry;S.Selected=entry
        detailText.Text=string.format("%s  %s  |  %.3fs  |  observed %dx\n%s\n\nArguments (%d):\n%s",entry.Direction,entry.Method,entry.Time,entry.Count,entry.Path,entry.ArgumentCount,entry.Arguments)
        detail.CanvasPosition=Vector2.zero
        ignore.Text=S.Ignored[entry.Path]and"Unignore remote"or"Ignore remote"
    end
    for i=1,40 do
        local row=make("TextButton",list,{Visible=false,BackgroundColor3=Color3.fromRGB(22,22,27),BorderSizePixel=0,
            TextColor3=Color3.fromRGB(220,220,229),Font=Enum.Font.Code,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,
            TextTruncate=Enum.TextTruncate.AtEnd,Size=UDim2.new(1,-8,0,32),Position=UDim2.fromOffset(4,(i-1)*35)})
        pool[i]=row;connect(row.Activated,function()if row:GetAttribute("EntryId")then
            for _,entry in ipairs(S.Data.Logs)do if entry.Id==row:GetAttribute("EntryId")then show(entry);break end end
        end end,true)
    end
    local function clipboard(value)
        if type(setclipboard)=="function"then setclipboard(value);S.Status="Copied to clipboard"
        else detailText.Text=value;S.Status="Clipboard unavailable · text displayed"end
    end
    connect(copy.Activated,function()if selected then clipboard(detailText.Text)end end,true)
    connect(ignore.Activated,function()if selected then
        if S.Ignored[selected.Path]then S.Ignored[selected.Path]=nil
        else local count=0;for _ in pairs(S.Ignored)do count+=1 end;if count>=256 then S.Status="Ignore list limit reached";return end;S.Ignored[selected.Path]=true end
        ignore.Text=S.Ignored[selected.Path]and"Unignore remote"or"Ignore remote";S.Dirty=true
    end end,true)
    connect(close.Activated,function()S:SetEnabled(false)end,true)
    connect(pause.Activated,function()S.Paused=not S.Paused;pause.Text=S.Paused and"Resume"or"Pause";S.Dirty=true end,true)
    connect(clear.Activated,function()S:Clear();selected=nil;detailText.Text="Log cleared."end,true)
    connect(export.Activated,function()clipboard(S:Export())end,true)
    connect(direction.Activated,function()
        S.Direction=S.Direction=="All"and"Out"or S.Direction=="Out"and"In"or"All"
        direction.Text=S.Direction=="All"and"All directions"or S.Direction=="Out"and"Outgoing"or"Incoming";S.Dirty=true
    end,true)
    connect(query:GetPropertyChangedSignal("Text"),function()S.Query=query.Text;S.Dirty=true;list.CanvasPosition=Vector2.zero end,true)
    local position,drag;local w,h
    local function place(item,x,y,width,height)item.Position=UDim2.fromOffset(x,y);item.Size=UDim2.fromOffset(width,height)end
    local function layout()
        local camera=workspace.CurrentCamera;if not camera then return end
        local v=camera.ViewportSize;w=math.max(240,math.min(760,v.X-20));h=math.max(300,math.min(590,v.Y-20))
        panel.Size=UDim2.fromOffset(w,h)
        local p=position or Vector2.new((v.X-w)/2,(v.Y-h)/2)
        p=Vector2.new(math.clamp(p.X,0,math.max(0,v.X-w)),math.clamp(p.Y,0,math.max(0,v.Y-h)))
        position=p;panel.Position=UDim2.fromOffset(p.X,p.Y)
        place(title,14,10,w-62,28);place(close,w-42,8,30,30)
        place(query,12,46,w-24,36)
        local bw=(w-30)/4
        for i,b in ipairs({pause,clear,export,direction})do place(b,12+(i-1)*(bw+2),90,bw,34)end
        place(summary,14,128,w-28,22)
        local lh=math.max(70,math.floor((h-216)*.53))
        place(list,12,154,w-24,lh);place(detail,12,160+lh,w-24,h-lh-214)
        place(copy,12,h-48,(w-30)/2,30);place(ignore,18+(w-30)/2,h-48,(w-30)/2,30)
        place(foot,14,h-17,w-28,14)
    end
    connect(title.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then drag={Input=input,Start=input.Position,Position=position}end
    end,true)
    connect(UIS.InputChanged,function(input)
        if drag and(input==drag.Input or drag.Input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)then
            local delta=input.Position-drag.Start;position=drag.Position+Vector2.new(delta.X,delta.Y);layout()
        end
    end,true)
    connect(UIS.InputEnded,function(input)if drag and(input==drag.Input or input.UserInputType==Enum.UserInputType.MouseButton1)then drag=nil end end,true)
    local camera=workspace.CurrentCamera;if camera then connect(camera:GetPropertyChangedSignal("ViewportSize"),layout,true)end
    local renderElapsed=0
    connect(Run.Heartbeat,function(dt)
        renderElapsed+=dt;if renderElapsed<.3 then return end;renderElapsed=0
        summary.Text=string.format("%d calls · %d dropped · %d remotes · %s",S.Data.Total,S.Data.Dropped,S.RemoteCount,S.Paused and"PAUSED"or"LIVE")
        if not S.Dirty then return end;S.Dirty=false
        local count=0
        for i=#S.Data.Logs,1,-1 do local entry=S.Data.Logs[i]
            if Model.Matches(entry,S.Query,S.Direction)then
                count+=1;if count>40 then break end
                local row=pool[count];row.Visible=true;row:SetAttribute("EntryId",entry.Id)
                row.Text=string.format(" %s  %-13s  %s  ×%d",entry.Direction,entry.Method,entry.Path,entry.Count)
            end
        end
        count=math.min(count,40)
        for i=count+1,40 do pool[i].Visible=false end
        list.CanvasSize=UDim2.fromOffset(0,count*35)
    end,true)
    S.Dirty=true;layout()
end
function S:SetEnabled(value)
    if self.Destroyed then return end
    if value==true then
        if self.Enabled then return end
        install();self.Enabled=true;self.Paused=false;self.Generation+=1;bridge.State=self
        self.RemoteCount=0;self.IncomingCount=0;self.Status="Indexing replicated remotes"
        local ok,err=pcall(createUI)
        if not ok then self:SetEnabled(false);error(err,0)end
        local elapsed=0
        connect(Run.Heartbeat,function(dt)
            elapsed+=dt;if elapsed<.1 then return end;elapsed=0
            for _=1,8 do local item=Model.Pop(self.Data);if not item then break end
                local ok,path=pcall(remotePath,item.Remote)
                if ok and not self.Ignored[path]then
                    local success=pcall(Model.Store,self.Data,item,path)
                    if success then self.Dirty=true else self.Data.Dropped+=1 end
                end
            end
        end)
        local generation=self.Generation
        task.spawn(function()local ok,err=pcall(watchRemotes,generation);if not ok then self.Status="Inventory error: "..tostring(err):sub(1,100)end end)
    else
        self.Enabled=false;self.Generation+=1;if bridge.State==self then bridge.State=nil end
        for _,connection in ipairs(self.Connections)do connection:Disconnect()end;table.clear(self.Connections)
        for _,connection in ipairs(self.UIConnections)do connection:Disconnect()end;table.clear(self.UIConnections)
        if self.Gui then self.Gui:Destroy();self.Gui=nil end
        table.clear(self.Data.Queue);self.Data.Head=1;self.Data.Tail=0;self.Status="Off"
    end
end
function S:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Calls=self.Data.Total,Dropped=self.Data.Dropped,Paused=self.Paused}end
function S:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true;self.Data=Model.New();table.clear(self.Ignored)
    if env.__ALLEN_REMOTE_SPY==self then env.__ALLEN_REMOTE_SPY=nil end
end
env.__ALLEN_REMOTE_SPY=S
return S

