-- Allens Forsaken Script | standalone bundle v4
-- RightShift: show/hide. End: unload. Automation starts paused.
-- Puzzle steps are serialized; default pause is 0.2 seconds per native action.
local Factories = {}

Factories.Generators = (function()
-- Generator and minigame adapter for Allens Forsaken Script.
-- Factory context: Player, RS, State, Alive(), Spawn(fn), CanAutomate().
-- State.PuzzleStepDelay controls native puzzle actions (default 0.2s, range 0.1-3s).
-- Optional test dependencies: Definitions, GeneratorClass, Gears, RunService,
-- Clock(), ServerClock(), IsSurvivor().
-- Scan returns {Model, Binder, Prompt, Position, InteractionPosition, InteractionPositions,
--   Progress, MaxProgress, Completed, Occupants, OccupantCount, IsInteracting}.
-- Methods: Scan(), Interact(descriptor), SolveActive(), IsInteracting(), Leave(), Destroy().
-- No bypassed completion: valid boards are applied through the game's native input callbacks.
return function(ctx)
    local player = assert(ctx.Player, "Generator adapter requires Player")
    local rs = ctx.RS or game:GetService("ReplicatedStorage")
    local runService = ctx.RunService or game:GetService("RunService")
    local clock = ctx.Clock or os.clock
    local serverClock = ctx.ServerClock or function() return workspace:GetServerTimeNow() end
    local gameModules
    if not ctx.GeneratorClass or not ctx.Definitions or not ctx.Gears then gameModules = rs.Systems.Player.Game end
    local generatorClass = ctx.GeneratorClass or require(gameModules.Generators.GeneratorClientBinder)
    local minigames = gameModules and gameModules.Minigames
    local definitions = ctx.Definitions or {
        Connect = require(minigames.ConnectClientMinigame),
        Flow = require(minigames.FlowClientMinigame),
        Lock = require(minigames.LockClientMinigame),
        Gear = require(minigames.GearClientMinigame),
    }
    local gears = ctx.Gears or require(gameModules.Spawners.GearsClientHandler)
    local m = {Destroyed = false, Current = nil, Status = "Idle", Puzzle = nil, Submitted = 0}
    local records = setmetatable({}, {__mode = "k"})
    local runningCache = {}
    local workerThread
    local suppressUntil = 0
    local generation = 0
    local advancing = false
    local nextActionAt = 0
    local function stepDelay() return math.clamp(tonumber(ctx.State.PuzzleStepDelay) or 0.2, 0.1, 3) end
    local function takeAction(r)
        local now = clock()
        if now < nextActionAt or now < r.NextAction then return false end
        r.LastAction = now
        r.NextAction = now + stepDelay()
        nextActionAt = r.NextAction
        return true
    end
    local elapsed, lastScan, lastEnter, lastLeave = 0, -math.huge, -math.huge, -math.huge

    local function enabled()
        if m.Destroyed or clock()<suppressUntil or (ctx.Alive and not ctx.Alive()) then return false end
        if ctx.CanAutomate and not ctx.CanAutomate() then return false end
        return ctx.State.AutoFarmGenerators == true or ctx.State.AutoPlay == true
    end
    local function survivor()
        if ctx.IsSurvivor then return ctx.IsSurvivor() end
        local ch = player.Character
        local h = ch and ch:FindFirstChildOfClass("Humanoid")
        return ch and ch.Parent and ch.Parent.Name == "Survivors" and h and h.Health > 0
    end
    local function getProperties(object)
        local ok, result = pcall(function() return object.Network.Properties end)
        return ok and result or nil
    end
    local function getProperty(properties, key, fallback)
        if not properties then return fallback end
        local ok, value = pcall(properties.Get, properties, key)
        if ok and value ~= nil then return value end
        return fallback
    end
    local function sessions(kind)
        if runningCache[kind] then return runningCache[kind] end
        -- Minigame_Client deliberately labels its private keys through __tostring.
        -- Only the four known game definitions are examined, never the global heap.
        for key, value in pairs(definitions[kind]) do
            if type(key) == "table" and type(value) == "table" then
                local ok, name = pcall(tostring, key)
                if ok and name == "MinigameKey(Running)" then
                    runningCache[kind] = value
                    return value
                end
            end
        end
        return {}
    end
    local function owns(session)
        return getProperty(getProperties(session), "FixerUserId", 0) == player.UserId
    end
    local function inputCallbacks(session)
        local input = session.__input
        return input and not input.Ended and input.Callbacks or nil
    end
    local function active(kind, session)
        if not enabled() or not survivor() or not owns(session) then return false end
        return sessions(kind)[session.SessionId] == session
            and session.__renderer ~= nil and inputCallbacks(session) ~= nil
    end
    local function record(session)
        local r = records[session]
        local board = session.__renderer and session.__renderer.Board
        if r and r.Board ~= board then
            generation += 1
            if workerThread then pcall(task.cancel,workerThread); workerThread=nil end
            r=nil
            nextActionAt=clock()+stepDelay()
        end
        if not r then
            r = {Started = clock(), LastAction = -math.huge,
                NextAction = clock() + stepDelay(), Board = board}
            records[session] = r
        end
        return r
    end
    local function callbacksSolved(session, r)
        if r.Submitted or not inputCallbacks(session) then return false end
        local fn = inputCallbacks(session).OnSolved
        if type(fn) ~= "function" then return false end
        -- Reserve submission before calling native input: callbacks can yield, error,
        -- or synchronously re-enter SolveActive through game/UI signals.
        r.Submitted = true
        local ok, err = pcall(fn)
        if ok then
            m.Submitted += 1
            m.Status = "Solution submitted; waiting for server"
        else
            r.Failed = true
            m.Status = "Submission callback failed; re-enter puzzle to retry"
            m.LastError = tostring(err)
        end
        return ok
    end

    function m:Scan()
        if self.Destroyed then return {} end
        local list = {}
        local ch = player.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        local ok, bound = pcall(generatorClass.GetAll, generatorClass)
        if not ok then self.Status = "Generator binder unavailable"; return list end
        self.Current = nil
        for model, binder in pairs(bound) do
            if typeof(model) == "Instance" and model:IsA("Model") and model:IsDescendantOf(workspace) then
                local main = model:FindFirstChild("Main")
                local prompt = main and main:FindFirstChildOfClass("ProximityPrompt")
                if main and main:IsA("BasePart") and prompt then
                    local properties = getProperties(binder)
                    local occupants = getProperty(properties, "Occupants", {})
                    local count = 0
                    for _, uid in pairs(occupants) do if uid and uid ~= 0 then count += 1 end end
                    local positions,positionNames = {},{}
                    local seats=model:FindFirstChild("Positions")
                    if seats then
                        local children=seats:GetChildren()
                        table.sort(children,function(a,b) return a.Name<b.Name end)
                        for _,seat in ipairs(children) do
                            local occupant=occupants[seat.Name]
                            local free=not occupant or occupant==0 or occupant==player.UserId
                            local position=seat:IsA("BasePart") and seat.Position
                                or seat:IsA("Attachment") and seat.WorldPosition
                            if free and position then
                                positions[#positions+1]=position
                                positionNames[#positionNames+1]=seat.Name
                            end
                        end
                    else
                        local offset=math.clamp(prompt.MaxActivationDistance*.55,2,4.5)
                        for _,v in ipairs({Vector3.new(0,0,-offset),Vector3.new(-offset,0,0),Vector3.new(offset,0,0),Vector3.new(0,0,offset)}) do
                            positions[#positions+1]=main.CFrame:PointToWorldSpace(v)
                            positionNames[#positionNames+1]=tostring(#positions)
                        end
                    end
                    local descriptor = {
                        Model = model, Binder = binder, Prompt = prompt, Position = main.Position,
                        InteractionPositions = positions, InteractionPosition = positions[1],
                        PositionNames=positionNames, HasFreePosition=#positions>0,
                        Progress = getProperty(properties, "Counter", 0),
                        MaxProgress = getProperty(properties, "MaxCounter", 0),
                        Completed = getProperty(properties, "Completed", false),
                        Occupants = occupants, OccupantCount = count,
                        IsInteracting = binder.__sitting ~= nil,
                    }
                    list[#list+1] = descriptor
                    if descriptor.IsInteracting then self.Current = descriptor end
                end
            end
        end
        if root then
            table.sort(list, function(a,b) return (a.Position-root.Position).Magnitude < (b.Position-root.Position).Magnitude end)
        end
        return list
    end

    function m:IsInteracting()
        self:Scan()
        return self.Current ~= nil
    end
    function m:Interact(descriptor)
        if not enabled() or not survivor() then return false, "Not an active survivor" end
        if self:IsInteracting() then return true, "Already repairing" end
        local model = descriptor and descriptor.Model
        local binder = model and generatorClass:FromInstance(model)
        local main = model and model:FindFirstChild("Main")
        local prompt = main and main:FindFirstChildOfClass("ProximityPrompt")
        local ch = player.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        if not binder or not root or not prompt or not main then return false, "Generator unavailable" end
        if getProperty(getProperties(binder), "Completed", false) then return false, "Generator complete" end
        if (root.Position-main.Position).Magnitude > prompt.MaxActivationDistance then return false, "Move closer" end
        if prompt.RequiresLineOfSight then
            local ray = RaycastParams.new()
            ray.FilterType = Enum.RaycastFilterType.Exclude
            ray.FilterDescendantsInstances = {ch}
            local origin = root.Position + Vector3.new(0,1.5,0)
            local hit = workspace:Raycast(origin, main.Position-origin, ray)
            if hit and not hit.Instance:IsDescendantOf(model) then return false, "Generator obstructed" end
        end
        if clock()-lastEnter < 1.5 then return false, "Waiting for entry response" end
        lastEnter = clock()
        local ok, err = pcall(function() binder.Network:FireServer("Enter") end)
        if ok then self.RequestedBinder = binder; self.Managed = true end
        self.Status = ok and "Requested generator entry" or "Entry failed"
        return ok, ok and self.Status or tostring(err)
    end

    -- Non-overlapping paths matching FlowBoard.Validate. Search is bounded by both
    -- expanded nodes and wall time and yields so it never monopolizes the client.
    local function solveFlow(size, pairsList, cancelled)
        if size < 2 or size > 9 or #pairsList > 12 then return nil, "Unsupported board size" end
        local total = size*size
        local endpoints, occupied, routes = {}, {}, {}
        for color, pair in ipairs(pairsList) do
            if type(pair) ~= "table" or type(pair[1]) ~= "number" or type(pair[2]) ~= "number" then return nil, "Invalid endpoints" end
            endpoints[pair[1]], endpoints[pair[2]] = color, color
        end
        local neighbors = {}
        for cell = 1,total do
            local row, col = math.floor((cell-1)/size), (cell-1)%size
            local n = {}
            if row>0 then n[#n+1]=cell-size end
            if row<size-1 then n[#n+1]=cell+size end
            if col>0 then n[#n+1]=cell-1 end
            if col<size-1 then n[#n+1]=cell+1 end
            neighbors[cell]=n
        end
        local function distance(a,b)
            return math.abs(math.floor((a-1)/size)-math.floor((b-1)/size)) + math.abs((a-1)%size-(b-1)%size)
        end
        local deadline = clock()+12
        local nodes, slice = 0, clock()
        local aborted
        local function checkpoint()
            nodes+=1
            if nodes>220000 or clock()>deadline or cancelled() then aborted=true; return false end
            if clock()-slice>0.004 then task.wait(); slice=clock() end
            return true
        end
        local function reachable(a,b,color)
            local queue, seen, index = {a}, {[a]=true}, 1
            while index<=#queue do
                local x=queue[index];index+=1
                if x==b then return true end
                for _,v in ipairs(neighbors[x]) do
                    if not seen[v] and not occupied[v] and (not endpoints[v] or endpoints[v]==color) then
                        seen[v]=true;queue[#queue+1]=v
                    end
                end
            end
            return false
        end
        local order = {}
        for i,pair in ipairs(pairsList) do order[i]=i end
        table.sort(order,function(a,b) return distance(pairsList[a][1],pairsList[a][2]) < distance(pairsList[b][1],pairsList[b][2]) end)
        local solvePair
        solvePair=function(index)
            if index>#order then return true end
            if not checkpoint() then return false end
            local color=order[index]
            local start,goal=pairsList[color][1],pairsList[color][2]
            if not reachable(start,goal,color) then return false end
            local path={start};occupied[start]=color
            local function walk(cell)
                if not checkpoint() then return false end
                if cell==goal then
                    routes[color]=table.clone(path)
                    local viable=true
                    for later=index+1,#order do
                        local c=order[later];local p=pairsList[c]
                        if not reachable(p[1],p[2],c) then viable=false;break end
                    end
                    if viable and solvePair(index+1) then return true end
                    routes[color]=nil
                    return false
                end
                local ns=table.clone(neighbors[cell])
                table.sort(ns,function(a,b)return distance(a,goal)<distance(b,goal) end)
                for _,nextCell in ipairs(ns) do
                    if not occupied[nextCell] and (not endpoints[nextCell] or endpoints[nextCell]==color) then
                        occupied[nextCell]=color;path[#path+1]=nextCell
                        if walk(nextCell) then return true end
                        path[#path]=nil;occupied[nextCell]=nil
                        if aborted then return false end
                    end
                end
                return false
            end
            if walk(start) then return true end
            occupied[start]=nil
            return false
        end
        if solvePair(1) then return routes end
        return nil, aborted and "Flow search budget reached; solve manually or re-enter" or "No valid Flow solution found"
    end

    local function render(session)
        local renderer = session.__renderer
        if renderer and type(renderer.Render) == "function" then renderer:Render() end
    end
    local function fail(r, message)
        r.Failed = true
        m.Status = message
    end
    local function advanceFlow(session, board, r)
        -- The worker only computes routes. All actual board mutations below are
        -- serialized one native operation per configured interval.
        local transitions = 0
        while transitions < 32 do
            transitions += 1
            local color = r.Color or 1
            if r.Stage == "ClearBegin" then
                if color > #board.Pairs then
                    r.Color=1; r.Stage="Begin"
                elseif not board.Paths[color] or #board.Paths[color]==0 then
                    r.Color=color+1
                else
                    if not takeAction(r) then return end
                    board:Begin(board.Pairs[color][1])
                    r.Stage="ClearRelease"; render(session); return
                end
            elseif r.Stage == "ClearRelease" then
                if not takeAction(r) then return end
                board:Release(color,false)
                r.Color=color+1; r.Stage="ClearBegin"; render(session); return
            elseif r.Stage == "Begin" then
                if not takeAction(r) then return end
                local path=r.Routes[color]
                if not path or #path<2 or board:Begin(path[1])~=color then
                    fail(r,"Flow board changed; re-enter to retry"); return
                end
                r.Cell=2; r.Stage="Step"; render(session); return
            elseif r.Stage == "Step" then
                if not takeAction(r) then return end
                local path=r.Routes[color]
                local result=board:Step(color,path[r.Cell],0)
                if not result then fail(r,"Flow path interrupted; re-enter to retry");return end
                r.Cell+=1
                if r.Cell>#path then r.Stage="Release" end
                render(session); return
            elseif r.Stage == "Release" then
                if not takeAction(r) then return end
                if not board:Release(color,false) then
                    fail(r,"Flow path did not connect; re-enter to retry");return
                end
                r.Color=color+1
                r.Stage=r.Color>#r.Routes and "Submit" or "Begin"
                render(session); return
            elseif r.Stage == "Submit" then
                if not board:IsSolved() then fail(r,"Flow solution changed; re-enter to retry"); return end
                if takeAction(r) then callbacksSolved(session,r) end
                return
            else return end
        end
    end
    local function solveActive()
        if not enabled() or not survivor() then return false end
        for kind in pairs(definitions) do
            for _, session in pairs(sessions(kind)) do
                if active(kind,session) then
                    m.Puzzle=kind
                    m.Managed=true
                    local r=record(session)
                    local board=session.__renderer.Board
                    local callbacks=inputCallbacks(session)
                    if r.Submitted or r.Failed then return true end
                    if kind=="Connect" and board then
                        if board:IsSolved() then
                            if takeAction(r) then callbacksSolved(session,r) end
                            return true
                        end
                        local index,mate
                        for candidate in ipairs(board.Blobs) do
                            if not board:GetLink(candidate) then
                                local found=board:GetMate(candidate)
                                if found and not board:GetLink(found) then index,mate=candidate,found; break end
                            end
                        end
                        if not index then fail(r,"Connect board has unmatched blobs");return true end
                        if takeAction(r) then
                            if not board:Connect(index,mate) then fail(r,"Connect board changed; re-enter to retry")
                            else render(session);m.Status="Connected one pair" end
                        end
                        return true
                    elseif kind=="Flow" and board then
                        if r.Routes then
                            advanceFlow(session,board,r)
                        elseif not r.Working then
                            r.Working=true
                            local token=generation
                            local function work()
                                local ok, routes, reason=pcall(solveFlow,board.Size,board.Pairs,function()
                                    return token~=generation or not active("Flow",session) or session.__renderer.Board~=board
                                end)
                                if token~=generation or not active("Flow",session) or session.__renderer.Board~=board then r.Working=false;return end
                                if not ok then reason=tostring(routes);routes=nil end
                                if routes then
                                    r.Routes=routes; r.Color=1; r.Stage="ClearBegin"
                                    r.NextAction=math.max(r.NextAction,clock()+stepDelay())
                                    m.Status="Flow solution ready; drawing one cell per interval"
                                else fail(r,reason or "Flow solver failed") end
                                r.Working=false
                            end
                            workerThread=(ctx.Spawn or task.spawn)(work)
                            m.Status="Computing Flow solution"
                        end
                        return true
                    elseif kind=="Lock" and board then
                        if board:IsBroken() then return true end
                        local now=serverClock()
                        local angle=board:AngleAt(now)
                        local delta=(angle-board.State.Target)%360
                        local gap=math.min(delta,360-delta)
                        if now>=board.Config.StartTime and gap<=math.max(1,board.Config.TargetSize*0.30)
                            and type(callbacks.OnPress)=="function" and takeAction(r) then
                            callbacks.OnPress()
                        end
                        m.Status="Waiting for the next valid lock press"
                        return true
                    elseif kind=="Gear" then
                        local ok,count=pcall(gears.Get,gears)
                        if not ok or count<1 then m.Status="Find a gear before repairing";return true end
                        if type(callbacks.OnTurn)=="function" and takeAction(r) then
                            callbacks.OnTurn(45)
                        end
                        m.Status="Turning one gear step per interval"
                        return true
                    end
                    return true
                end
            end
        end
        m.Puzzle=nil
        return false
    end
    function m:SolveActive()
        if advancing or self.Destroyed then return false end
        advancing=true
        local ok,result=pcall(solveActive)
        advancing=false
        if not ok then
            self.Status="Puzzle adapter error: "..tostring(result)
            self.LastError=tostring(result)
            return false
        end
        return result
    end

    function m:Leave()
        if clock()-lastLeave < 0.5 then return end
        lastLeave=clock();generation+=1;suppressUntil=clock()+0.75
        if workerThread then pcall(task.cancel,workerThread);workerThread=nil end
        -- Preserve once-per-session submission/error tombstones until that exact
        -- session is released by the game's Running table (weak keys then expire).
        for _,r in pairs(records) do
            r.Working=false; r.Routes=nil; r.Stage=nil; r.Color=nil; r.Cell=nil
            r.NextAction=clock()+stepDelay()
        end
        nextActionAt = clock()+stepDelay()
        self:Scan()
        local current=self.Current
        if not self.Managed and not self.RequestedBinder then
            self.Puzzle=nil;self.Status="Idle";return
        end
        if current and current.Binder.__sitting then
            pcall(current.Binder.__leave,current.Binder)
        else
            for kind in pairs(definitions) do
                for _,session in pairs(sessions(kind)) do
                    if owns(session) then local cb=inputCallbacks(session)
                        if cb and type(cb.OnLeave)=="function" then pcall(cb.OnLeave) end
                    end
                end
            end
        end
        self.Current=nil;self.Puzzle=nil;self.Managed=false;self.RequestedBinder=nil;self.Status="Paused generator work"
    end
    local connection=runService.Heartbeat:Connect(function(dt)
        elapsed+=dt
        if elapsed<0.04 then return end
        elapsed=0
        if enabled() then
            if clock()-lastScan>0.5 then lastScan=clock();m:Scan() end
            local ok,err=pcall(m.SolveActive,m)
            if not ok then m.Status="Puzzle adapter error: "..tostring(err) end
        elseif m.Puzzle then
            m:Leave()
        end
    end)
    function m:Destroy()
        if self.Destroyed then return end
        self:Leave()
        self.Destroyed=true
        connection:Disconnect()
        table.clear(records);table.clear(runningCache)
    end
    return m
end
end)()

Factories.Movement = (function()
-- Allens Forsaken Script: local movement/effect adapter.
-- Factory context: Player, RS, State, Alive(), Status(feature, text).
-- No server status, damage, ability lock, or speed-cap removal is attempted.
return function(ctx)
    local player = ctx.Player
    local rs = ctx.RS or game:GetService("ReplicatedStorage")
    local runService = game:GetService("RunService")
    local state = ctx.State
    local adapter = {Destroyed = false, Ready = false}
    local sprint, statuses, controls
    local character, generation
    local infiniteSaved, sprintSaved
    local localPatches = {}
    local nauseaInfo, confusionInfo, confusionOriginal
    local liveEffects = {}
    local connections = {}
    local previousReport = {}

    local function report(feature, message)
        if previousReport[feature] ~= message then
            previousReport[feature] = message
            if ctx.Status then ctx.Status(feature, message) end
        end
    end

    local function resolve(path)
        local object = rs
        for _, name in ipairs(path) do
            object = object and object:FindFirstChild(name)
        end
        if object and object:IsA("ModuleScript") then
            local ok, result = pcall(require, object)
            if ok and type(result) == "table" then return result end
        end
        return nil
    end

    sprint = resolve({"Systems", "Character", "Game", "Sprinting"})
    statuses = resolve({"Modules", "Gameplay", "Statuses"})

    local function activeCharacter()
        if ctx.Alive and not ctx.Alive() then return nil end
        local ch = player.Character
        local humanoid = ch and ch:FindFirstChildOfClass("Humanoid")
        local role = ch and ch.Parent and ch.Parent.Name
        if not humanoid or humanoid.Health <= 0 or (role ~= "Survivors" and role ~= "Killers") then
            return nil
        end
        return ch
    end

    local function initialized(ch)
        local multiplier = sprint and sprint.__speedMultiplier
        return ch and sprint and sprint.DefaultsSet == true
            and typeof(multiplier) == "Instance" and multiplier:IsDescendantOf(ch)
            and type(sprint.Stamina) == "number" and type(sprint.MaxStamina) == "number"
    end

    local function isCurrent(entry)
        if not entry or not statuses then return false end
        local entries = statuses.CurrentStatuses and statuses.CurrentStatuses[player]
        if not entries then return false end
        for _, current in pairs(entries) do
            if current == entry and current.Character == character then return true end
        end
        return false
    end

    local function nativeSprint(value)
        if not initialized(character) or sprint.__speedMultiplier ~= generation then return false end
        local old = sprint.IsSprinting
        sprint.IsSprinting = value
        local event = sprint.__sprintedEvent
        local ok = pcall(function()
            if typeof(event) == "Instance" and event:IsA("BindableEvent") then
                event:Fire(value)
            else
                sprint:Toggle(value)
            end
        end)
        if not ok then sprint.IsSprinting = old end
        return ok
    end

    function adapter:ReleaseSprint()
        if sprintSaved then
            local saved = sprintSaved
            sprintSaved = nil
            if saved.Generation == generation and sprint.__speedMultiplier == saved.Generation and initialized(character) then
                nativeSprint(saved.Value)
            end
        end
    end

    function adapter:SetSprint(value)
        if self.Destroyed or not self.Ready then return false end
        value = value == true
        if value and (not sprint.CanSprint or sprint.isSpeedLocked or sprint:IsStaminaFrozen()) then
            return false
        end
        if value and sprint.Stamina <= (sprint.MinStamina or 0) then return false end
        if not sprintSaved then
            sprintSaved = {Generation = generation, Value = sprint.IsSprinting == true}
        end
        if sprint.IsSprinting == value then return true end
        return nativeSprint(value)
    end

    local function restoreInfinite()
        if not infiniteSaved then return end
        local saved = infiniteSaved
        infiniteSaved = nil
        if saved.Generation ~= generation or sprint.__speedMultiplier ~= saved.Generation or not initialized(character) then return end
        if sprint.StaminaLossDisabled == true then
            sprint.StaminaLossDisabled = saved.Disabled
        end
        -- Restore only our most recent write, never a newer game-produced value.
        if saved.LastStamina ~= nil and sprint.Stamina == saved.LastStamina then
            local before = sprint.Stamina
            sprint.Stamina = math.clamp(saved.Stamina, sprint.MinStamina or 0,
                sprint.StaminaCap or sprint.MaxStamina)
            local event = sprint.__staminaChangedEvent
            if typeof(event) == "Instance" and event:IsA("BindableEvent") then
                event:Fire(sprint.Stamina, sprint.Stamina - before)
            end
        end
    end

    local function patchInstance(object, property, desired, entry, restore)
        if typeof(object) ~= "Instance" or not object.Parent then return end
        local record = localPatches[object]
        if not record then
            record = {Property = property, Original = object[property], Entry = entry}
            localPatches[object] = record
        end
        record.Entry, record.Restore, record.Desired = entry, restore, desired
        object[property] = desired
    end

    local function restoreDebuffs()
        for object, record in pairs(localPatches) do
            if object.Parent and isCurrent(record.Entry) then
                pcall(function()
                    if object[record.Property] == record.Desired then
                        object[record.Property] = record.Restore ~= nil and record.Restore or record.Original
                    end
                end)
            end
        end
        table.clear(localPatches)
        if nauseaInfo and isCurrent(nauseaInfo.Entry) then
            local entry = nauseaInfo.Entry
            local elapsed = entry.TimePast or 0
            local duration = entry.TimeRequired or 0
            nauseaInfo.Info.TickTimePast = math.max(0, math.min(elapsed, duration - elapsed))
        end
        nauseaInfo = nil
        if confusionInfo and controls and isCurrent(confusionInfo) then
            if controls.moveFunction == player.Move and confusionOriginal then
                controls.moveFunction = confusionOriginal
            end
        end
        confusionInfo, confusionOriginal = nil, nil
        table.clear(liveEffects)
    end

    local function applyDebuffs()
        if not state.AntiDebuff or not adapter.Ready then return end
        for name, entry in pairs(liveEffects) do
            if isCurrent(entry) and entry.Info then
                local info = entry.Info
                if name == "Slowness" then
                    local level = tonumber(info.Level) or tonumber(entry.Level) or 1
                    local data = info.Data or entry.Data or {}
                    patchInstance(info.SpeedMultiplier, "Value", 1, entry, 1 - level / 10)
                    patchInstance(info.FOVMultiplier, "Value", 1, entry, data.Hidden and 1 or 1 - level / 20)
                elseif name == "Blindness" then
                    patchInstance(info.Blur, "Enabled", false, entry, nil)
                elseif name == "Nausea" then
                    nauseaInfo = {Entry = entry, Info = info}
                    -- The native distortion callback multiplies its effect by TickTimePast.
                    info.TickTimePast = 0
                elseif name == "Confusion" and controls then
                    if confusionInfo ~= entry then
                        confusionInfo = entry
                        confusionOriginal = controls.moveFunction
                    elseif controls.moveFunction ~= player.Move then
                        -- Preserve a fresh inversion installed by a native status refresh.
                        confusionOriginal = controls.moveFunction
                    end
                    controls.moveFunction = player.Move
                end
            end
        end
    end

    function adapter:GetStamina()
        if not self.Ready then return nil, nil end
        return sprint.Stamina, math.min(sprint.StaminaCap or sprint.MaxStamina, sprint.MaxStamina)
    end

    function adapter:Snapshot()
        local stamina, maximum = self:GetStamina()
        local count = 0
        for _, entry in pairs(liveEffects) do if isCurrent(entry) then count += 1 end end
        return {
            Ready = self.Ready,
            Stamina = stamina,
            MaxStamina = maximum,
            MinStamina = self.Ready and sprint.MinStamina or 0,
            RegenDelay = self.Ready and sprint.timeUntilStaminaRecovers or nil,
            IsSprinting = self.Ready and sprint.IsSprinting == true,
            StaminaFrozen = self.Ready and sprint:IsStaminaFrozen() or false,
            DebuffsMitigated = count,
            Status = previousReport.Movement or "Waiting for a living actor",
            Limitation = "Local Slowness, Blindness, Nausea and Confusion effects only; server caps/damage remain authoritative.",
        }
    end

    function adapter:Tick()
        if self.Destroyed then return end
        local ch = activeCharacter()
        local nextGeneration = ch and sprint and sprint.__speedMultiplier
        if ch ~= character or nextGeneration ~= generation then
            self:ReleaseSprint()
            restoreInfinite()
            restoreDebuffs()
            character, generation = ch, nextGeneration
        end
        self.Ready = initialized(character) == true
        if not self.Ready then
            restoreInfinite()
            restoreDebuffs()
            report("Movement", sprint and "Waiting for a living actor" or "Native sprint module unavailable")
            return
        end

        if state.InfiniteStamina then
            if not infiniteSaved then
                infiniteSaved = {
                    Generation = generation,
                    Disabled = sprint.StaminaLossDisabled,
                    Stamina = sprint.Stamina,
                }
            end
            sprint.StaminaLossDisabled = true
            -- Respect native freeze/ability overrides; do not remove locks.
            if not sprint:IsStaminaFrozen() and not character:GetAttribute("AbilityStaminaOverride") then
                local before = sprint.Stamina
                local cap = math.min(sprint.StaminaCap or sprint.MaxStamina, sprint.MaxStamina)
                sprint.Stamina = cap
                infiniteSaved.LastStamina = cap
                local event = sprint.__staminaChangedEvent
                if before ~= cap and typeof(event) == "Instance" and event:IsA("BindableEvent") then
                    event:Fire(cap, cap - before)
                end
            end
        else
            restoreInfinite()
        end

        if state.AntiDebuff and statuses then
            local entries = statuses.CurrentStatuses and statuses.CurrentStatuses[player]
            for name, entry in pairs(liveEffects) do
                if not entries or entries[name] ~= entry then
                    if name == "Nausea" then nauseaInfo = nil end
                    if name == "Confusion" then confusionInfo, confusionOriginal = nil, nil end
                    liveEffects[name] = nil
                end
            end
            for _, name in ipairs({"Slowness", "Blindness", "Nausea", "Confusion"}) do
                local entry = entries and entries[name]
                if entry and entry.Character == character then liveEffects[name] = entry end
            end
            if liveEffects.Confusion and not controls then
                local ps = player:FindFirstChildOfClass("PlayerScripts")
                local module = ps and ps:FindFirstChild("PlayerModule")
                if module then
                    local ok, result = pcall(function() return require(module):GetControls() end)
                    if ok then controls = result end
                end
            end
            for object, record in pairs(localPatches) do
                if not object.Parent or not isCurrent(record.Entry) then localPatches[object] = nil end
            end
            applyDebuffs()
        else
            restoreDebuffs()
        end
        local applied = self:Snapshot().DebuffsMitigated
        report("Movement", string.format("Stamina %.0f / %.0f%s", sprint.Stamina,
            math.min(sprint.StaminaCap or sprint.MaxStamina, sprint.MaxStamina),
            state.InfiniteStamina and " · local drain disabled" or ""))
        report("AntiDebuff", state.AntiDebuff and string.format("%d local effects suppressed", applied) or "Off")
    end

    -- Nausea's camera callback runs at Camera+1; neutralize its scale immediately before it.
    local bindName = "AllensForsakenAntiDebuff_" .. tostring({})
    runService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value, function()
        if not adapter.Destroyed then applyDebuffs() end
    end)

    function adapter:Destroy()
        if self.Destroyed then return end
        self:ReleaseSprint()
        restoreInfinite()
        restoreDebuffs()
        self.Destroyed = true
        runService:UnbindFromRenderStep(bindName)
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
    end

    adapter:Tick()
    return adapter
end
end)()

Factories.Combat = (function()
-- Guest1337 defensive adapter. Uses native ability requests, normal cooldowns,
-- and replicated MainAbility animation cues. No proximity-only block spam.
return function(ctx)
    local RS = ctx.RS or game:GetService("ReplicatedStorage")
    local Player = ctx.Player or game:GetService("Players").LocalPlayer
    local Clock = ctx.Clock or os.clock
    local module = {
        Available = false, Reason = "Waiting for character", Requests = 0,
        DefendUntil = 0, LastRequest = -math.huge, LastThreat = nil,
        Destroyed = false, Watches = {}, Seen = setmetatable({}, {__mode = "k"}),
    }
    local Actors = ctx.Actors
    local Network = ctx.Network
    if not Actors then
        local ok, result = pcall(require, RS.Modules.Gameplay.Actors)
        if ok then Actors = result else module.Reason = "Actor module unavailable" end
    end
    if not Network then
        local ok, result = pcall(require, RS.Modules.Network.Network)
        if ok then Network = result else module.Reason = "Ability network unavailable" end
    end
    local facedHumanoid, oldAutoRotate, faceTarget
    local lastScan = -math.huge
    local lastStatus
    local baseReach = {Slasher=7.5, JohnDoe=7.5, c00lkidd=5, Noli=8}
    local function status(message)
        module.Reason = message
        if message ~= lastStatus and ctx.Status then
            lastStatus = message
            ctx.Status("AutoBlock", message)
        end
    end
    local function disconnect(watch)
        if watch.Connection then watch.Connection:Disconnect() end
    end
    local function releaseFacing()
        if facedHumanoid and facedHumanoid.Parent then
            facedHumanoid.AutoRotate = oldAutoRotate
        end
        facedHumanoid, oldAutoRotate, faceTarget = nil, nil, nil
    end
    local function rootOf(rig)
        if not rig then return nil end
        return rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
    end
    local function alive(rig)
        local h = rig and rig:FindFirstChildOfClass("Humanoid")
        return h and h.Health > 0 and rootOf(rig) ~= nil
    end
    local function localActor()
        if not Actors or type(Actors.CurrentActors) ~= "table" then return nil end
        local actor = Actors.CurrentActors[Player] or Actors.CurrentActors[Player.Character]
        if actor and actor.Rig == Player.Character then return actor end
        for _, candidate in pairs(Actors.CurrentActors) do
            if type(candidate) == "table" and candidate.Rig == Player.Character then
                return candidate
            end
        end
    end
    local function abilities(actor)
        return actor and actor.Behavior and actor.Behavior.Abilities
    end
    local function canBlock(actor)
        if not actor or not alive(actor.Rig) then return false, "Waiting for character" end
        if not actor.Rig.Parent or actor.Rig.Parent.Name ~= "Survivors" then
            return false, "Survivors only"
        end
        local list = abilities(actor)
        -- Other characters' attack abilities are not mislabeled as blocks.
        if not list or type(list.Block) ~= "table" then
            return false, "Equip Guest1337 for Block"
        end
        if actor.ActorName and actor.ActorName ~= "Guest1337" then
            return false, "This actor has no supported Block"
        end
        if type(actor.CanUseAbility) ~= "function" then
            return false, "Native ability guard unavailable"
        end
        local ok, permitted = pcall(actor.CanUseAbility, actor, "Block")
        if not ok then return false, "Native ability guard failed" end
        if not permitted then return false, "Block cooling down or locked" end
        return true
    end
    local function idOf(animation)
        if typeof(animation) == "Instance" and animation:IsA("Animation") then
            animation = animation.AnimationId
        end
        if type(animation) == "number" then return tostring(animation) end
        if type(animation) == "string" then return animation:match("%d+") end
    end
    local function descriptors(actor)
        local result = {}
        local config = actor.Config or {}
        local animations = config.Animations or {}
        for name, ability in pairs(abilities(actor) or {}) do
            if type(ability) == "table" and ability.KeybindType == "MainAbility"
                and not ability.IsProjectile then
                local nested = type(config[name]) == "table" and config[name] or {}
                local windup = config[name.."Windup"] or config[name.."WindupTime"] or nested.Windup
                if name == "Punch" or name == "Attack" then
                    windup = windup or config.PunchWindup
                end
                local linger = config[name.."Linger"] or nested.Linger or 0.25
                local keys = {name, "Enraged"..name}
                if name == "Punch" or name == "Attack" then keys[#keys+1] = "Attack" end
                local ids = {}
                for _, key in ipairs(keys) do
                    local id = idOf(animations[key])
                    if id then ids[id] = true end
                end
                result[#result+1] = {
                    Name = name, Keys = keys, Ids = ids,
                    Windup = math.clamp(tonumber(windup) or 0.25, 0.05, 1.5),
                    Linger = math.clamp(tonumber(linger) or 0.25, 0.05, 0.6),
                    Reach = tonumber(config[name.."Range"]) or baseReach[actor.ActorName] or 8,
                }
            end
        end
        return result
    end
    local function descriptorFor(watch, track)
        for _, d in ipairs(watch.Descriptors) do
            for _, key in ipairs(d.Keys) do
                if watch.Actor.Animations and watch.Actor.Animations[key] == track then
                    return d
                end
            end
            local ok, animation = pcall(function() return track.Animation end)
            local id = ok and idOf(animation)
            if id and d.Ids[id] then return d end
        end
    end
    local function lineOfSight(rig, enemyRig, startPosition, endPosition)
        local delta = endPosition - startPosition
        if delta.Magnitude < 0.01 then return true end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {rig, enemyRig}
        params.RespectCanCollide = true
        local hit = workspace:Raycast(startPosition, delta, params)
        return hit == nil
    end
    function module:Consider(watch, track, fromEvent)
        if self.Destroyed or not ctx.State.AutoBlock or not Network then return end
        if ctx.Alive and not ctx.Alive() then return end
        if ctx.CanAutomate and not ctx.CanAutomate() then return end
        local actor = localActor()
        local permitted = canBlock(actor)
        if not permitted then return end
        if Clock() - self.LastRequest < 1.1 then return end
        local enemy = watch.Actor
        if not alive(enemy.Rig) or not enemy.Rig.Parent
            or enemy.Rig.Parent.Name ~= "Killers" then return end
        local d = descriptorFor(watch, track)
        if not d or not track.IsPlaying then return end
        local speed = math.abs(tonumber(track.Speed) or 1)
        if speed < 0.01 then return end
        local position = math.max(0, tonumber(track.TimePosition) or 0)
        local seen = self.Seen[track]
        if fromEvent or not seen or position + 0.04 < seen.Position then
            seen = {Position = position, Fired = false}
            self.Seen[track] = seen
        end
        seen.Position = position
        if seen.Fired then return end
        local elapsed = position / speed
        if elapsed > d.Windup + d.Linger then return end
        local untilImpact = math.max(0, d.Windup - elapsed)
        local blockDuration = tonumber(actor.Config and actor.Config.BlockDuration) or 1
        if untilImpact > math.max(0.1, blockDuration - 0.15) then return end
        local root, enemyRoot = rootOf(actor.Rig), rootOf(enemy.Rig)
        if not root or not enemyRoot then return end
        local delta = root.Position - enemyRoot.Position
        local flat = Vector3.new(delta.X, 0, delta.Z)
        local distance = delta.Magnitude
        local maxRange = math.clamp(tonumber(ctx.State.BlockRange) or 12, 4, 18)
        if distance > maxRange or flat.Magnitude < 0.05 or math.abs(delta.Y) > 7 then return end
        local forward = enemyRoot.CFrame.LookVector
        local facing = Vector3.new(forward.X, 0, forward.Z)
        if facing.Magnitude < 0.01 or facing.Unit:Dot(flat.Unit) < 0.35 then return end
        local relativeVelocity = root.AssemblyLinearVelocity - enemyRoot.AssemblyLinearVelocity
        local approach = math.max(0, -relativeVelocity:Dot(delta.Unit))
        local predictedDistance = distance - math.min(6, approach * untilImpact)
        if predictedDistance > math.min(maxRange, d.Reach + 1.5) then return end
        if not lineOfSight(actor.Rig, enemy.Rig, enemyRoot.Position, root.Position) then return end
        if ctx.State.FaceThreat ~= false then
            local toEnemy = enemyRoot.Position - root.Position
            local direction = Vector3.new(toEnemy.X, 0, toEnemy.Z)
            if direction.Magnitude > 0.01 and not root.Anchored then
                releaseFacing()
                facedHumanoid = actor.Rig:FindFirstChildOfClass("Humanoid")
                oldAutoRotate = facedHumanoid.AutoRotate
                facedHumanoid.AutoRotate = false
                faceTarget = enemyRoot
                root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
            end
        end
        local ability = abilities(actor).Block
        local payload
        if ability.ClientCallback then
            local ok, value = pcall(ability.ClientCallback, actor)
            if not ok or value == false then releaseFacing(); return end
            payload = value
        end
        seen.Fired = true
        self.LastRequest = Clock()
        self.LastThreat = enemy.ActorName or enemy.Rig.Name
        local ok, err = pcall(Network.FireServerConnection, Network,
            "UseActorAbility", "REMOTE_EVENT", "Block", payload)
        if not ok then
            self.LastError = tostring(err)
            status("Block request failed")
            releaseFacing()
            return
        end
        self.Requests += 1
        self.DefendUntil = Clock() + blockDuration
        status("Reacted to "..self.LastThreat.." "..d.Name)
    end
    function module:RefreshWatches()
        local keep = {}
        for _, actor in pairs(Actors and Actors.CurrentActors or {}) do
            if type(actor) == "table" and actor.Rig and actor.Rig.Parent
                and actor.Rig.Parent.Name == "Killers" and not keep[actor.Rig] then
                keep[actor.Rig] = true
                local old = self.Watches[actor.Rig]
                if not old or old.Actor ~= actor then
                    if old then disconnect(old) end
                    local h = actor.Rig:FindFirstChildOfClass("Humanoid")
                    local animator = h and h:FindFirstChildOfClass("Animator")
                    local watch = {Actor = actor, Animator = animator, Descriptors = descriptors(actor)}
                    self.Watches[actor.Rig] = watch
                    if animator then
                        watch.Connection = animator.AnimationPlayed:Connect(function(track)
                            self.Seen[track] = nil
                            local ok, err = pcall(self.Consider, self, watch, track, true)
                            if not ok then self.LastError = tostring(err) end
                        end)
                    end
                end
            end
        end
        for rig, watch in pairs(self.Watches) do
            if not keep[rig] then disconnect(watch); self.Watches[rig] = nil end
        end
    end
    function module:IsDefending()
        return not self.Destroyed and ctx.State.AutoBlock
            and Clock() < self.DefendUntil
    end
    function module:Tick()
        if self.Destroyed then return end
        local actor = localActor()
        local list = abilities(actor)
        self.Available = actor ~= nil and list ~= nil and type(list.Block) == "table"
            and (not actor.ActorName or actor.ActorName == "Guest1337")
        local inputPaused = ctx.CanAutomate and not ctx.CanAutomate()
        if not ctx.State.AutoBlock or not Actors or not Network or inputPaused then
            releaseFacing()
            self.DefendUntil = 0
            for rig, watch in pairs(self.Watches) do disconnect(watch); self.Watches[rig] = nil end
            status(inputPaused and "Paused for manual control" or
                (ctx.State.AutoBlock and "Ability modules unavailable" or "Off"))
            return
        end
        if not alive(Player.Character) then
            releaseFacing()
            self.DefendUntil = 0
            status("Waiting for character")
            return
        end
        if facedHumanoid and facedHumanoid.Parent ~= Player.Character then releaseFacing() end
        if not self.Available then
            releaseFacing()
            self.DefendUntil = 0
            status("Equip Guest1337 for Block")
            return
        end
        if Clock() >= self.DefendUntil then releaseFacing() end
        if self:IsDefending() then
            local root = rootOf(Player.Character)
            if root and faceTarget and faceTarget.Parent and ctx.State.FaceThreat ~= false then
                local delta = faceTarget.Position - root.Position
                local flat = Vector3.new(delta.X, 0, delta.Z)
                if flat.Magnitude > 0.01 and not root.Anchored then
                    root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
                end
            end
        end
        if Clock() - lastScan >= 0.4 then
            lastScan = Clock()
            self:RefreshWatches()
        end
        for _, watch in pairs(self.Watches) do
            if watch.Animator and watch.Animator.Parent then
                for _, track in ipairs(watch.Animator:GetPlayingAnimationTracks()) do
                    local ok, err = pcall(self.Consider, self, watch, track, false)
                    if not ok then self.LastError = tostring(err) end
                end
            end
        end
        local permitted, reason = canBlock(actor)
        if not self:IsDefending() then status(permitted and "Watching melee windups" or reason) end
    end
    function module:Snapshot()
        local actor = localActor()
        local remaining = 0
        if actor and type(actor.IsOnCooldown) == "function" then
            local ok, value = pcall(actor.IsOnCooldown, actor, "Block")
            if ok and type(value) == "number" then remaining = math.max(0, value) end
        end
        return {
            Available = self.Available, Reason = self.Reason, Requests = self.Requests,
            LastThreat = self.LastThreat, LastError = self.LastError,
            Defending = self:IsDefending(), Cooldown = remaining,
        }
    end
    function module:Destroy()
        if self.Destroyed then return end
        self.Destroyed = true
        releaseFacing()
        for rig, watch in pairs(self.Watches) do disconnect(watch); self.Watches[rig] = nil end
        table.clear(self.Seen)
        self.DefendUntil = 0
    end
    return module
end
end)()

-- Main runtime. The distributable bundles the three adapters before this block.
local env = type(getgenv) == "function" and getgenv() or _G
if env.AllensForsaken then env.AllensForsaken:Destroy() end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Pathfinding = game:GetService("PathfindingService")
local Http = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player and RS:FindFirstChild("Systems") and RS:FindFirstChild("Modules"), "Load Forsaken before running this script")
local C = {BG=Color3.fromRGB(10,12,16),Panel=Color3.fromRGB(18,22,31),Hover=Color3.fromRGB(24,30,42),
    Line=Color3.fromRGB(37,46,62),Text=Color3.fromRGB(235,240,250),Muted=Color3.fromRGB(144,156,178),
    Accent=Color3.fromRGB(123,140,255),Green=Color3.fromRGB(83,222,176),Warning=Color3.fromRGB(246,190,106)}
local c = {Version=4,Destroyed=false,Connections={},Tasks={},Tweens={},Bindings={},FeatureStatus={},
    State={AutoFarmGenerators=false,AutoPlay=false,AutoBlock=false,InfiniteStamina=false,AntiDebuff=false,
        GeneratorESP=true,ThreatRadius=45,FarmDelay=0.8,PuzzleStepDelay=0.2,BlockRange=16,FaceThreat=true,Hotkey=Enum.KeyCode.RightShift},
    Generators={},NavStatus="Paused",ManualUntil=0,NavGeneration=0,PathBusy=false,Waypoints=nil,
    NavOwner=nil,WaypointIndex=1,LastPath=0,LastFarm=0,LastScan=0,LastFailure={},LastStuck=0,Ready=false,Focused=true}
env.AllensForsaken = c
local gui, panel, body, badge, statusLabel, statsLabel, detailsLabel, toast, toastLabel, keyButton
local pages, tabs = {}, {}
local dragging, draggingSlider, captureKey, minimized
local move, combat, generators
local generatorMarkers={}
local CONFIG = "AllensForsaken/preferences.json"
local function connect(signal,callback)
    local connection=signal:Connect(callback)
    table.insert(c.Connections,connection)
    return connection
end
function c:Spawn(callback)
    local thread
    thread=task.defer(function()
        if not self.Destroyed then
            local ok,err=xpcall(callback,debug.traceback)
            if not ok and not self.Destroyed then
                self.FeatureStatus.Error=tostring(err)
                warn("Allens Forsaken: "..tostring(err))
            end
        end
        self.Tasks[coroutine.running()]=nil
    end)
    self.Tasks[thread]=true
    return thread
end
local function character()
    local ch=player.Character
    local h=ch and ch:FindFirstChildOfClass("Humanoid")
    local root=ch and ch:FindFirstChild("HumanoidRootPart")
    if h and root and h.Health>0 then return ch,h,root end
end
local function survivor()
    local ch=character()
    return ch~=nil and ch.Parent~=nil and ch.Parent.Name=="Survivors"
end
local function canAutomate()
    return not c.Destroyed and c.Focused and not UIS:GetFocusedTextBox() and os.clock()>=c.ManualUntil
end
local function tween(object,properties,duration)
    if c.Tweens[object] then c.Tweens[object]:Cancel() end
    local t=TweenService:Create(object,TweenInfo.new(duration or 0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),properties)
    c.Tweens[object]=t; t:Play()
end
local toastDeadline=0
function c:Notify(message)
    if self.Destroyed then return end
    if toast then
        toastLabel.Text=tostring(message)
        toast.Visible=true; toastDeadline=os.clock()+4
        tween(toast,{Position=UDim2.new(1,-22,1,-24)},0.25)
    end
end
local function status(feature,message) c.FeatureStatus[feature]=tostring(message) end
local function safeCall(adapter,method,...)
    if not adapter or type(adapter[method])~="function" then return nil end
    local ok,a,b,d=pcall(adapter[method],adapter,...)
    if not ok then
        local key=tostring(method)..tostring(a)
        if os.clock()-(c.LastFailure[key] or -math.huge)>10 then
            c.LastFailure[key]=os.clock()
            status("Error",a)
            warn("Allens Forsaken: "..tostring(a))
        end
        return nil
    end
    return a,b,d
end
local function releaseSprint() safeCall(move,"ReleaseSprint") end
function c:StopNavigation()
    self.NavGeneration+=1
    self.Waypoints=nil; self.NavGoal=nil
    if self.PathThread then
        pcall(task.cancel,self.PathThread); self.Tasks[self.PathThread]=nil
        self.PathThread=nil
    end
    self.PathBusy=false
    if self.PathBlocked then self.PathBlocked:Disconnect(); self.PathBlocked=nil end
    if self.NavOwner and self.NavOwner.Parent then
        local root=self.NavOwner.Parent:FindFirstChild("HumanoidRootPart")
        if root then self.NavOwner:MoveTo(root.Position) end
    end
    self.NavOwner=nil
    releaseSprint()
end
local function nearestThreat(position)
    local actors=workspace:FindFirstChild("Players")
    local killers=actors and actors:FindFirstChild("Killers")
    local nearest,distance=nil,math.huge
    if killers then
        for _,model in ipairs(killers:GetChildren()) do
            local root=model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            local h=model:FindFirstChildOfClass("Humanoid")
            if root and root:IsA("BasePart") and (not h or h.Health>0) then
                local d=(root.Position-position).Magnitude
                if d<distance then nearest,distance=root,d end
            end
        end
    end
    return nearest,distance
end
function c:Navigate(goal,mode)
    local ch,h,root=character()
    if not ch or root.Anchored then return false end
    if (root.Position-goal).Magnitude<2.5 then
        if self.NavOwner or self.PathBusy or self.Waypoints then self:StopNavigation() end
        return true
    end
    if self.NavGoal and (self.NavGoal-goal).Magnitude>2 then self:StopNavigation() end
    if self.PathBusy and os.clock()-(self.PathStarted or 0)>5 then
        self:StopNavigation();self.NavFailureAt=os.clock()
    end
    if not self.PathBusy and not self.Waypoints and os.clock()-self.LastPath>.6 then
        self.NavGeneration+=1
        local generation=self.NavGeneration
        self.NavGoal=goal;self.LastPath=os.clock();self.PathStarted=os.clock();self.PathBusy=true
        self.PathThread=self:Spawn(function()
            local path=Pathfinding:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=3})
            local ok=pcall(function() path:ComputeAsync(root.Position,goal) end)
            if self.Destroyed or generation~=self.NavGeneration or player.Character~=ch then return end
            self.PathBusy=false;self.PathThread=nil
            if self.PathBlocked then self.PathBlocked:Disconnect();self.PathBlocked=nil end
            if ok and path.Status==Enum.PathStatus.Success then
                self.Waypoints=path:GetWaypoints();self.WaypointIndex=math.min(2,#self.Waypoints)
                self.LastProgress=os.clock();self.LastPosition=root.Position
                self.PathBlocked=path.Blocked:Connect(function(index)
                    if generation==self.NavGeneration and index>=self.WaypointIndex then
                        self.Waypoints=nil;self.NavStatus="Route blocked; recalculating"
                    end
                end)
            else
                self.Waypoints=nil;self.NavFailureAt=os.clock()
                self.NavStatus="No walkable route; trying another approach"
            end
        end)
    end
    local waypoints=self.Waypoints
    if waypoints and #waypoints>0 then
        local point=waypoints[self.WaypointIndex]
        while point and (root.Position-point.Position).Magnitude<2.5 do
            self.WaypointIndex+=1;point=waypoints[self.WaypointIndex]
        end
        if point then
            self.NavOwner=h
            if point.Action==Enum.PathWaypointAction.Jump then h.Jump=true end
            h:MoveTo(point.Position)
            if not self.LastPosition or (root.Position-self.LastPosition).Magnitude>1 then
                self.LastPosition=root.Position;self.LastProgress=os.clock()
            elseif os.clock()-(self.LastProgress or os.clock())>2 then
                h.Jump=true;self:StopNavigation();self.NavFailureAt=os.clock()
            end
        else self.Waypoints=nil end
    end
    local stamina=safeCall(move,"Snapshot")
    local canSprint=stamina and type(stamina.Stamina)=="number" and stamina.Stamina>15
    safeCall(move,"SetSprint",canSprint==true)
    return false
end
local fleeGoal,fleeTime,evading=nil,0,false
local function fleePoint(root,threat)
    local away=Vector3.new(root.Position.X-threat.Position.X,0,root.Position.Z-threat.Position.Z)
    if away.Magnitude<0.1 then away=Vector3.new(1,0,0) end
    away=away.Unit
    local ray=RaycastParams.new()
    ray.FilterType=Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances={player.Character,workspace:FindFirstChild("Players") or player.Character}
    local best,score=nil,-math.huge
    for _,angle in ipairs({0,math.rad(55),math.rad(-55),math.rad(100),math.rad(-100)}) do
        local direction=CFrame.Angles(0,angle,0):VectorToWorldSpace(away)
        local target=root.Position+direction*32
        local ground=workspace:Raycast(target+Vector3.new(0,12,0),Vector3.new(0,-60,0),ray)
        if ground then
            local point=ground.Position+Vector3.new(0,2,0)
            local s=(point-threat.Position).Magnitude
            if not workspace:Raycast(root.Position,direction*10,ray) then s+=10 end
            if s>score then best,score=point,s end
        end
    end
    return best
end
local farmRecords=setmetatable({},{__mode="k"})
local function farmRecord(desc)
    local r=farmRecords[desc.Model]
    if not r then r={Blocked={},RetryAt=0};farmRecords[desc.Model]=r end
    return r
end
local function generatorPosition(desc,root,r)
    local positions=desc.InteractionPositions or {}
    if r.GoalName then
        for i,name in ipairs(desc.PositionNames or {}) do
            if name==r.GoalName and (r.Blocked[name] or 0)<=os.clock() then return positions[i] end
        end
    end
    local best,distance,name=nil,math.huge,nil
    for i,position in ipairs(positions) do
        local key=desc.PositionNames and desc.PositionNames[i] or tostring(i)
        if (r.Blocked[key] or 0)<=os.clock() then
            local d=(root.Position-position).Magnitude
            if d<distance then best,distance,name=position,d,key end
        end
    end
    r.GoalName=name
    return best
end
local function rejectApproach(desc,r)
    if r.GoalName then r.Blocked[r.GoalName]=os.clock()+12 end
    r.GoalName=nil;r.PendingUntil=nil;r.ApproachStarted=nil
    c:StopNavigation()
    local _,_,root=character()
    if not root or not generatorPosition(desc,root,r) then r.RetryAt=os.clock()+12;c.TargetGenerator=nil end
end
local function farmTick()
    if not c.State.AutoFarmGenerators and not c.State.AutoPlay then
        if c.NavOwner or c.PathBusy then c:StopNavigation() end
        c.NavStatus="Paused";return
    end
    local ch,h,root=character()
    if not ch or not survivor() then
        if c.NavOwner or c.PathBusy then c:StopNavigation() end
        safeCall(generators,"Leave")
        c.TargetGenerator=nil
        c.NavStatus="Waiting for a survivor round";return
    end
    if c.State.AutoPlay then
        for _,key in ipairs({Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Space}) do
            if UIS:IsKeyDown(key) then c.ManualUntil=os.clock()+2;break end
        end
    end
    if not canAutomate() or safeCall(combat,"IsDefending") then
        if c.NavOwner or c.PathBusy then c:StopNavigation() end
        c.NavStatus="Manual control or defense; farming paused";return
    end
    local threat,distance=nearestThreat(root.Position)
    if distance<c.State.ThreatRadius then evading=true end
    if not threat or distance>c.State.ThreatRadius+15 then evading=false end
    if evading then
        safeCall(generators,"Leave")
        if c.State.AutoPlay then
            if not fleeGoal or os.clock()-fleeTime>2 then fleeGoal=fleePoint(root,threat);fleeTime=os.clock() end
            c.NavStatus="Evading killer ("..math.floor(distance).." studs)"
            if fleeGoal then c:Navigate(fleeGoal,"Evading") else c:StopNavigation();c.NavStatus="Threat nearby; no safe route" end
        else
            if c.NavOwner or c.PathBusy then c:StopNavigation() end
            c.NavStatus="Generator farming paused: killer nearby"
        end
        return
    end
    if fleeGoal then c:StopNavigation();fleeGoal=nil end
    -- Continue the active puzzle before looking for another generator.
    if safeCall(generators,"IsInteracting") then
        if c.NavOwner or c.PathBusy then c:StopNavigation() end
        if c.TargetGenerator then local r=farmRecord(c.TargetGenerator);r.PendingUntil=nil;r.ApproachStarted=nil end
        c.NavStatus="Working on generator puzzle"
        if os.clock()-c.LastFarm>=c.State.FarmDelay then c.LastFarm=os.clock();safeCall(generators,"SolveActive") end
        return
    end
    if os.clock()-c.LastScan>.6 then c.LastScan=os.clock();c.Generators=safeCall(generators,"Scan") or {} end
    local best,score=nil,math.huge
    local previous=c.TargetGenerator and c.TargetGenerator.Model
    for _,desc in ipairs(c.Generators) do
        local r=farmRecord(desc)
        if not desc.Completed and desc.HasFreePosition~=false and (not desc.Prompt or desc.Prompt.Enabled)
            and typeof(desc.Position)=="Vector3" and r.RetryAt<=os.clock() then
            local d=(desc.Position-root.Position).Magnitude
            local range=desc.Prompt and desc.Prompt.MaxActivationDistance or 8
            local _,danger=nearestThreat(desc.Position)
            if danger>=c.State.ThreatRadius and (c.State.AutoPlay or d<=range) then
                local maximum=tonumber(desc.MaxProgress) or 0
                local progress=maximum>0 and math.clamp((tonumber(desc.Progress) or 0)/maximum,0,1) or 0
                local candidate=d-progress*8+(tonumber(desc.OccupantCount) or 0)*3
                -- Keep an eligible target instead of changing routes every scan.
                if desc.Model==previous then best=desc;break end
                if candidate<score then best,score=desc,candidate end
            end
        end
    end
    if not best then
        c.TargetGenerator=nil
        if c.NavOwner or c.PathBusy then c:StopNavigation() end
        c.NavStatus=c.State.AutoPlay and "Waiting for a safe, free generator" or "Move near a free generator, or enable AutoPlay"
        return
    end
    local r=farmRecord(best)
    if best.Model~=previous then
        c:StopNavigation();r.GoalName=nil;r.PendingUntil=nil;r.ApproachStarted=nil
        r.LastFailure=c.NavFailureAt
    end
    c.TargetGenerator=best
    local goal=generatorPosition(best,root,r)
    if not goal then r.RetryAt=os.clock()+12;c.TargetGenerator=nil;c:StopNavigation();return end
    if r.PendingUntil then
        if os.clock()<r.PendingUntil then c.NavStatus="Waiting for generator entry confirmation";return end
        rejectApproach(best,r);c.NavStatus="Entry not confirmed; trying another free side";return
    end
    if c.State.AutoPlay then
        r.ApproachStarted=r.ApproachStarted or os.clock()
        if c.NavFailureAt and c.NavFailureAt~=(r.LastFailure or 0) then
            r.LastFailure=c.NavFailureAt;rejectApproach(best,r);c.NavStatus="Trying another generator approach";return
        end
        if os.clock()-r.ApproachStarted>25 then rejectApproach(best,r);c.NavStatus="Approach timed out; trying another side";return end
        if not c:Navigate(goal,"Generator") then c.NavStatus="Walking to a free repair position";return end
    end
    local range=best.Prompt and best.Prompt.MaxActivationDistance or 8
    if (root.Position-best.Position).Magnitude>range then
        if c.State.AutoPlay then rejectApproach(best,r) end
        c.NavStatus="Move closer to the generator";return
    end
    if os.clock()-c.LastFarm>=math.max(c.State.FarmDelay,1.5) then
        c.LastFarm=os.clock()
        local accepted,reason=safeCall(generators,"Interact",best)
        if accepted then
            c:StopNavigation();r.PendingUntil=os.clock()+2.5
            c.NavStatus="Entering generator; awaiting confirmation"
        elseif reason=="Waiting for entry response" then c.NavStatus=reason
        else rejectApproach(best,r);c.NavStatus=tostring(reason or "Entry unavailable; trying another side") end
    end
end
function c:ClearGeneratorESP()
    for model,marker in pairs(generatorMarkers) do
        marker.Gui:Destroy(); marker.Highlight:Destroy(); generatorMarkers[model]=nil
    end
end
function c:RefreshGeneratorESP()
    if self.Destroyed or not self.State.GeneratorESP then self:ClearGeneratorESP(); return end
    local list=safeCall(generators,"Scan") or {}
    local ch=player.Character
    local root=ch and ch:FindFirstChild("HumanoidRootPart")
    local keep={}
    for _,desc in ipairs(list) do
        local model=desc.Model
        local main=model and model:FindFirstChild("Main")
        if model and model:IsDescendantOf(workspace) and main and main:IsA("BasePart") then
            keep[model]=true
            local marker=generatorMarkers[model]
            if not marker then
                local billboard=Instance.new("BillboardGui")
                billboard.Name="AllensGeneratorLabel"; billboard.Adornee=main
                billboard.Size=UDim2.fromOffset(180,50); billboard.StudsOffsetWorldSpace=Vector3.new(0,4,0)
                billboard.AlwaysOnTop=true; billboard.MaxDistance=2500
                local frame=Instance.new("Frame")
                frame.Size=UDim2.fromScale(1,1); frame.BackgroundColor3=C.BG
                frame.BackgroundTransparency=0.12; frame.BorderSizePixel=0; frame.Parent=billboard
                local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,6); corner.Parent=frame
                local outline=Instance.new("UIStroke"); outline.Color=C.Line; outline.Thickness=1; outline.Parent=frame
                local title=Instance.new("TextLabel")
                title.Size=UDim2.new(1,-12,0,20); title.Position=UDim2.fromOffset(6,4)
                title.BackgroundTransparency=1; title.Font=Enum.Font.GothamBold; title.TextSize=11
                title.TextColor3=C.Warning; title.TextTruncate=Enum.TextTruncate.AtEnd; title.Parent=frame
                local info=Instance.new("TextLabel")
                info.Size=UDim2.new(1,-12,0,18); info.Position=UDim2.fromOffset(6,27)
                info.BackgroundTransparency=1; info.Font=Enum.Font.GothamMedium; info.TextSize=10
                info.TextColor3=C.Text; info.TextTruncate=Enum.TextTruncate.AtEnd; info.Parent=frame
                billboard.Parent=gui
                local highlight=Instance.new("Highlight")
                highlight.Name="AllensGeneratorHighlight"; highlight.Adornee=model
                highlight.FillTransparency=0.85; highlight.OutlineTransparency=0.15
                highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; highlight.Parent=model
                marker={Gui=billboard,Highlight=highlight,Title=title,Info=info}
                generatorMarkers[model]=marker
            end
            local color=desc.Completed and C.Green or C.Warning
            marker.Title.TextColor3=color; marker.Highlight.FillColor=color; marker.Highlight.OutlineColor=color
            local progress=tonumber(desc.Progress) or 0
            local maximum=tonumber(desc.MaxProgress) or 0
            marker.Title.Text=desc.Completed and "GENERATOR  /  COMPLETE"
                or string.format("GENERATOR  /  %g/%g",progress,maximum)
            local distance=root and math.floor((main.Position-root.Position).Magnitude) or nil
            marker.Info.Text=string.format("%s  |  %d repairing",distance and distance.." studs" or "Distance unavailable",tonumber(desc.OccupantCount) or 0)
        end
    end
    for model,marker in pairs(generatorMarkers) do
        if not keep[model] then marker.Gui:Destroy(); marker.Highlight:Destroy(); generatorMarkers[model]=nil end
    end
end
function c:Set(key,value)
    if self.Destroyed or self.State[key]==nil then return false end
    if key=="Hotkey" then
        if typeof(value)~="EnumItem" or value.EnumType~=Enum.KeyCode or value==Enum.KeyCode.Unknown
            or value==Enum.KeyCode.Escape or value==Enum.KeyCode.End then return false end
    elseif key=="ThreatRadius" then value=math.clamp(tonumber(value) or 45,20,90)
    elseif key=="FarmDelay" then value=math.clamp(tonumber(value) or 0.8,0.4,2.5)
    elseif key=="PuzzleStepDelay" then value=math.clamp(tonumber(value) or 0.2,0.1,3)
    elseif key=="BlockRange" then value=math.clamp(tonumber(value) or 16,8,18)
    else value=value==true end
    self.State[key]=value
    if self.Bindings[key] then self.Bindings[key](value) end
    if key=="AutoPlay" and not value then
        self:StopNavigation(); evading=false
        if not self.State.AutoFarmGenerators then safeCall(generators,"Leave") end
    end
    if key=="AutoFarmGenerators" and not value and not self.State.AutoPlay then safeCall(generators,"Leave") end
    if key=="InfiniteStamina" or key=="AntiDebuff" then safeCall(move,"Tick",0) end
    if key=="GeneratorESP" then self:RefreshGeneratorESP() end
    return true
end
function c:Destroy()
    if self.Destroyed then return end
    for key,value in pairs(self.State) do if type(value)=="boolean" then self.State[key]=false end end
    self:StopNavigation()
    self.Destroyed=true
    safeCall(generators,"Destroy"); safeCall(combat,"Destroy"); safeCall(move,"Destroy")
    self:ClearGeneratorESP()
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    for thread in pairs(self.Tasks) do if thread~=coroutine.running() then pcall(task.cancel,thread) end end
    table.clear(self.Tasks)
    for _,t in pairs(self.Tweens) do t:Cancel() end
    table.clear(self.Tweens)
    if gui then gui:Destroy() end
    if env.AllensForsaken==self then env.AllensForsaken=nil end
end
local function make(class,properties,parent)
    local object=Instance.new(class)
    for key,value in pairs(properties) do object[key]=value end
    object.Parent=parent; return object
end
local function round(object,radius) make("UICorner",{CornerRadius=UDim.new(0,radius or 6)},object) end
local function stroke(object) make("UIStroke",{Color=C.Line,Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},object) end
local function label(parent,title,position,size,textSize,color)
    return make("TextLabel",{Position=position,Size=size,BackgroundTransparency=1,Text=title,
        Font=Enum.Font.GothamMedium,TextSize=textSize or 12,TextColor3=color or C.Text,
        TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},parent)
end
local function button(parent,title,position,size)
    local b=make("TextButton",{Position=position,Size=size,Text=title,TextSize=12,
        Font=Enum.Font.GothamMedium,TextColor3=C.Muted,BackgroundColor3=C.Panel,
        BorderSizePixel=0,AutoButtonColor=false},parent)
    round(b)
    connect(b.MouseEnter,function() tween(b,{BackgroundColor3=C.Hover,TextColor3=C.Text}) end)
    connect(b.MouseLeave,function() tween(b,{BackgroundColor3=C.Panel,TextColor3=C.Muted}) end)
    connect(b.MouseButton1Down,function() tween(b,{BackgroundColor3=C.Line}) end)
    connect(b.MouseButton1Up,function() tween(b,{BackgroundColor3=C.Hover}) end)
    return b
end
gui=make("ScreenGui",{Name="Allens Forsaken Script",ResetOnSpawn=false,DisplayOrder=95,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling},player:WaitForChild("PlayerGui"))
c.Gui=gui
connect(gui.Destroying,function() if not c.Destroyed then c:Destroy() end end)
panel=make("Frame",{Name="Panel",Size=UDim2.fromOffset(620,530),Position=UDim2.new(0.5,-310,0.5,-265),
    BackgroundColor3=C.BG,BorderSizePixel=0,ClipsDescendants=true},gui)
round(panel,8); stroke(panel)
local scale=make("UIScale",{Scale=1},panel)
local header=make("Frame",{Name="Header",Size=UDim2.new(1,0,0,58),BackgroundColor3=C.Panel,BorderSizePixel=0,Active=true},panel)
label(header,"Allens Forsaken Script",UDim2.fromOffset(20,10),UDim2.fromOffset(320,24),17)
label(header,"SURVIVOR AUTOMATION  /  CHARACTER TOOLS",UDim2.fromOffset(20,35),UDim2.fromOffset(320,12),9,C.Muted)
badge=label(header,"PAUSED",UDim2.fromOffset(412,20),UDim2.fromOffset(78,18),10,C.Muted)
local minimize=button(header,"-",UDim2.fromOffset(522,13),UDim2.fromOffset(30,30))
local close=button(header,"X",UDim2.fromOffset(570,13),UDim2.fromOffset(30,30))
connect(close.Activated,function() c:Destroy() end)
body=make("Frame",{Name="Body",Position=UDim2.fromOffset(0,58),Size=UDim2.new(1,0,1,-58),BackgroundTransparency=1},panel)
local rail=make("Frame",{Size=UDim2.new(0,132,1,0),BackgroundTransparency=1},body)
make("Frame",{Position=UDim2.new(1,-1,0,0),Size=UDim2.new(0,1,1,0),BackgroundColor3=C.Line,BorderSizePixel=0},rail)
label(rail,"WORKSPACE",UDim2.fromOffset(14,22),UDim2.fromOffset(110,16),9,C.Muted)
label(rail,"End / unload",UDim2.new(0,14,1,-37),UDim2.fromOffset(110,16),10,C.Muted)
local function selectTab(name)
    c.Tab=name
    for n,page in pairs(pages) do page.Visible=n==name end
    for n,b in pairs(tabs) do tween(b,{TextColor3=n==name and C.Accent or C.Muted,
        BackgroundColor3=n==name and C.Hover or C.Panel}) end
end
for i,name in ipairs({"Automation","Live","Settings"}) do
    local tab=button(rail,name,UDim2.fromOffset(10,51+(i-1)*44),UDim2.fromOffset(112,34))
    tabs[name]=tab; connect(tab.Activated,function() selectTab(name) end)
    local page=make("ScrollingFrame",{Name=name,Position=UDim2.fromOffset(132,0),Size=UDim2.new(1,-132,1,0),
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=C.Line,
        CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,Visible=false},body)
    make("UIPadding",{PaddingTop=UDim.new(0,18),PaddingBottom=UDim.new(0,20),
        PaddingLeft=UDim.new(0,20),PaddingRight=UDim.new(0,20)},page)
    make("UIListLayout",{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder},page)
    pages[name]=page
end
function c:SelectTab(name) if pages[name] then selectTab(name) end end
local function card(page,name,height,order)
    local row=make("Frame",{Name=name,LayoutOrder=order,Size=UDim2.new(1,0,0,height),BackgroundColor3=C.Panel,BorderSizePixel=0},page)
    round(row,8); stroke(row); return row
end
local function heading(page,title,subtitle)
    local row=make("Frame",{LayoutOrder=0,Size=UDim2.new(1,0,0,48),BackgroundTransparency=1},page)
    label(row,title,UDim2.new(),UDim2.new(1,0,0,24),20)
    label(row,subtitle,UDim2.fromOffset(0,29),UDim2.new(1,0,0,16),10,C.Muted)
end
local function toggle(page,key,title,description,order)
    local row=card(page,key,72,order)
    label(row,title,UDim2.fromOffset(14,12),UDim2.new(1,-88,0,20),13)
    local desc=label(row,description,UDim2.fromOffset(14,37),UDim2.new(1,-88,0,24),10,C.Muted)
    desc.TextWrapped=true; desc.TextTruncate=Enum.TextTruncate.None; desc.TextYAlignment=Enum.TextYAlignment.Top
    local hit=make("TextButton",{Size=UDim2.fromScale(1,1),Text="",AutoButtonColor=false,BackgroundTransparency=1},row)
    local track=make("Frame",{AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-14,0.5,0),
        Size=UDim2.fromOffset(44,24),BackgroundColor3=C.Line,BorderSizePixel=0},hit); round(track,12)
    local knob=make("Frame",{Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(18,18),
        BackgroundColor3=C.Text,BorderSizePixel=0},track); round(knob,9)
    c.Bindings[key]=function(value)
        tween(track,{BackgroundColor3=value and C.Accent or C.Line})
        tween(knob,{Position=UDim2.fromOffset(value and 23 or 3,3)})
    end
    connect(hit.Activated,function() c:Set(key,not c.State[key]) end)
    connect(hit.MouseEnter,function() tween(row,{BackgroundColor3=C.Hover}) end)
    connect(hit.MouseLeave,function() tween(row,{BackgroundColor3=C.Panel}) end)
end
local function slider(page,key,title,lo,hi,step,suffix,order)
    local row=card(page,key,78,order)
    label(row,title,UDim2.fromOffset(14,12),UDim2.new(1,-125,0,20),12)
    local readout=label(row,"",UDim2.new(1,-110,0,12),UDim2.fromOffset(96,20),11,C.Accent)
    readout.TextXAlignment=Enum.TextXAlignment.Right
    local bar=make("Frame",{Position=UDim2.new(0,14,0,54),Size=UDim2.new(1,-28,0,4),BackgroundColor3=C.Line,BorderSizePixel=0},row); round(bar,2)
    local fill=make("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=C.Accent,BorderSizePixel=0},bar); round(fill,2)
    local knob=make("Frame",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0,0.5),
        Size=UDim2.fromOffset(12,12),BackgroundColor3=C.Text,BorderSizePixel=0},bar); round(knob,6)
    local hit=make("TextButton",{Size=UDim2.new(1,0,0,28),Position=UDim2.new(0,0,0.5,-14),Text="",BackgroundTransparency=1},bar)
    c.Bindings[key]=function(value)
        local f=(value-lo)/(hi-lo)
        readout.Text=string.format(step<1 and "%.1f%s" or "%.0f%s",value,suffix)
        tween(fill,{Size=UDim2.fromScale(f,1)}); tween(knob,{Position=UDim2.fromScale(f,0.5)})
    end
    local function update(x) c:Set(key,lo+math.floor(math.clamp((x-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1)*(hi-lo)/step+0.5)*step) end
    connect(hit.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            draggingSlider={Input=input,Update=update}; update(input.Position.X)
        end
    end)
end
heading(pages.Automation,"Automation","Automation starts paused. Generator ESP is available below.")
toggle(pages.Automation,"AutoPlay","Survivor autoplay","Walk to generators; retreat from nearby killers.",1)
toggle(pages.Automation,"AutoFarmGenerators","Generator farmer","Work through nearby puzzles one move at a time.",2)
toggle(pages.Automation,"AutoBlock","Guest1337 auto-block","React to supported attack cues; respects cooldown.",3)
toggle(pages.Automation,"InfiniteStamina","Infinite stamina (local)","Remove local drain; preserve ability freeze locks.",4)
toggle(pages.Automation,"AntiDebuff","Local debuff relief","Reduce supported client effects; server effects may persist.",5)
toggle(pages.Automation,"GeneratorESP","Generator ESP","Show progress, completion, distance, and occupancy.",6)
heading(pages.Live,"Live status","Role, movement, puzzle, and adapter diagnostics.")
local live=card(pages.Live,"Status",96,1)
statusLabel=label(live,"Starting",UDim2.fromOffset(14,14),UDim2.new(1,-28,0,24),13)
statsLabel=label(live,"",UDim2.fromOffset(14,44),UDim2.new(1,-28,0,36),11,C.Muted)
statsLabel.TextWrapped=true; statsLabel.TextTruncate=Enum.TextTruncate.None
local diagnostics=card(pages.Live,"Diagnostics",244,2)
detailsLabel=label(diagnostics,"",UDim2.fromOffset(14,12),UDim2.new(1,-28,1,-24),11,C.Muted)
detailsLabel.TextWrapped=true; detailsLabel.TextTruncate=Enum.TextTruncate.None; detailsLabel.TextYAlignment=Enum.TextYAlignment.Top
heading(pages.Settings,"Settings","Movement keys pause autoplay. End unloads everything.")
slider(pages.Settings,"ThreatRadius","Killer avoidance distance",20,90,1," studs",1)
slider(pages.Settings,"FarmDelay","Interaction retry interval",0.4,2.5,0.1," s",2)
slider(pages.Settings,"PuzzleStepDelay","Pause between puzzle moves",0.1,3,0.1," s",3)
slider(pages.Settings,"BlockRange","Maximum block detection",8,18,1," studs",4)
local keyRow=card(pages.Settings,"Hotkey",66,5)
label(keyRow,"Show / hide hotkey",UDim2.fromOffset(14,12),UDim2.new(1,-150,0,20),12)
label(keyRow,"Click to rebind; Escape cancels.",UDim2.fromOffset(14,36),UDim2.new(1,-150,0,16),9,C.Muted)
keyButton=button(keyRow,"RightShift",UDim2.new(1,-136,0,14),UDim2.fromOffset(122,36))
c.Bindings.Hotkey=function(value) keyButton.Text=value.Name end
connect(keyButton.Activated,function() captureKey=true; keyButton.Text="PRESS KEY" end)
local save=button(pages.Settings,"Save preferences",UDim2.new(),UDim2.new(1,0,0,34)); save.LayoutOrder=6
connect(save.Activated,function()
    if type(writefile)~="function" or type(makefolder)~="function" then c:Notify("This executor has no configuration file support."); return end
    local ok,err=pcall(function()
        if type(isfolder)~="function" or not isfolder("AllensForsaken") then makefolder("AllensForsaken") end
        writefile(CONFIG,Http:JSONEncode({ThreatRadius=c.State.ThreatRadius,FarmDelay=c.State.FarmDelay,
            PuzzlePacingVersion=4,PuzzleStepDelay=c.State.PuzzleStepDelay,GeneratorESP=c.State.GeneratorESP,BlockRange=c.State.BlockRange,Hotkey=c.State.Hotkey.Name}))
    end)
    c:Notify(ok and "Preferences saved. Automation still starts paused." or tostring(err))
end)
local unload=button(pages.Settings,"Unload and restore",UDim2.new(),UDim2.new(1,0,0,34)); unload.LayoutOrder=7
connect(unload.Activated,function() c:Destroy() end)
toast=make("Frame",{Name="Toast",AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,400,1,-24),
    Size=UDim2.fromOffset(360,66),BackgroundColor3=C.Panel,BorderSizePixel=0,ZIndex=10,Visible=false},gui)
round(toast,8); stroke(toast)
toastLabel=label(toast,"",UDim2.fromOffset(14,12),UDim2.new(1,-28,1,-24),11)
toastLabel.TextWrapped=true; toastLabel.TextTruncate=Enum.TextTruncate.None
local function fit()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local v=camera.ViewportSize
    scale.Scale=math.max(0.15,math.min(1,(v.X-32)/620,(v.Y-80)/530))
    panel.Position=UDim2.fromOffset(math.clamp(panel.AbsolutePosition.X,8,math.max(8,v.X-panel.AbsoluteSize.X-8)),
        math.clamp(panel.AbsolutePosition.Y,8,math.max(8,v.Y-panel.AbsoluteSize.Y-48)))
end
connect(minimize.Activated,function()
    minimized=not minimized; body.Visible=not minimized; minimize.Text=minimized and "+" or "-"
    tween(panel,{Size=UDim2.fromOffset(620,minimized and 58 or 530)},0.25)
end)
connect(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging={Input=input,Origin=input.Position,Position=panel.AbsolutePosition}
    end
end)
connect(UIS.InputChanged,function(input)
    if draggingSlider and (input.UserInputType==Enum.UserInputType.MouseMovement or input==draggingSlider.Input) then
        draggingSlider.Update(input.Position.X)
    elseif dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input==dragging.Input) then
        local v=workspace.CurrentCamera.ViewportSize
        local delta=input.Position-dragging.Origin
        panel.Position=UDim2.fromOffset(math.clamp(dragging.Position.X+delta.X,8,math.max(8,v.X-panel.AbsoluteSize.X-8)),
            math.clamp(dragging.Position.Y+delta.Y,8,math.max(8,v.Y-panel.AbsoluteSize.Y-48)))
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=nil; draggingSlider=nil end
end)
connect(UIS.InputBegan,function(input,processed)
    if captureKey and input.UserInputType==Enum.UserInputType.Keyboard then
        if input.KeyCode==Enum.KeyCode.Escape then captureKey=false; c.Bindings.Hotkey(c.State.Hotkey)
        elseif c:Set("Hotkey",input.KeyCode) then captureKey=false end
        return
    end
    if processed or UIS:GetFocusedTextBox() then return end
    if input.KeyCode==Enum.KeyCode.End then c:Destroy(); return end
    if input.KeyCode==c.State.Hotkey then panel.Visible=not panel.Visible; return end
    if input.KeyCode==Enum.KeyCode.W or input.KeyCode==Enum.KeyCode.A or input.KeyCode==Enum.KeyCode.S or input.KeyCode==Enum.KeyCode.D or input.KeyCode==Enum.KeyCode.Space then
        if c.State.AutoPlay then
            c.ManualUntil=os.clock()+2
            c:StopNavigation(); safeCall(generators,"Leave")
        end
    end
end)
connect(UIS.WindowFocusReleased,function()
    c.Focused=false; dragging=nil; draggingSlider=nil; captureKey=false
    c.Bindings.Hotkey(c.State.Hotkey)
    c:StopNavigation(); safeCall(generators,"Leave")
end)
connect(UIS.WindowFocused,function() c.Focused=true end)
connect(player.CharacterRemoving,function() c:StopNavigation(); safeCall(generators,"Leave"); c.TargetGenerator=nil; c.Generators={} end)
local ctx={Player=player,RS=RS,State=c.State,Alive=function() return not c.Destroyed end,
    CanAutomate=canAutomate,
    Connect=connect,Spawn=function(fn) return c:Spawn(fn) end,
    Notify=function(message) c:Notify(message) end,Status=status}
for name,factory in pairs(Factories) do
    local ok,adapter=pcall(factory,ctx)
    if ok then
        if name=="Movement" then move=adapter elseif name=="Combat" then combat=adapter elseif name=="Generators" then generators=adapter end
    else status(name,"Unavailable: "..tostring(adapter)); warn("Allens Forsaken "..name..": "..tostring(adapter)) end
end
c.Adapters={Movement=move,Combat=combat,Generators=generators}
if type(isfile)=="function" and type(readfile)=="function" then
    pcall(function()
        if isfile(CONFIG) then
            local preferences=Http:JSONDecode(readfile(CONFIG))
            if preferences.PuzzlePacingVersion~=4 then preferences.PuzzleStepDelay=math.min(tonumber(preferences.PuzzleStepDelay) or 0.2,0.2) end
            for _,key in ipairs({"ThreatRadius","FarmDelay","PuzzleStepDelay","BlockRange"}) do if preferences[key]~=nil then c:Set(key,preferences[key]) end end
            if type(preferences.GeneratorESP)=="boolean" then c:Set("GeneratorESP",preferences.GeneratorESP) end
            if type(preferences.Hotkey)=="string" then local ok,key=pcall(function() return Enum.KeyCode[preferences.Hotkey] end); if ok then c:Set("Hotkey",key) end end
        end
    end)
end
for key,value in pairs(c.State) do if c.Bindings[key] then c.Bindings[key](value) end end
selectTab("Automation")
local elapsed,displayElapsed,viewport=0,0,nil
connect(RunService.Heartbeat,function(dt)
    if c.Destroyed then return end
    local camera=workspace.CurrentCamera
    if camera and camera.ViewportSize~=viewport then viewport=camera.ViewportSize; fit() end
    if toast.Visible and os.clock()>toastDeadline then toast.Visible=false end
    elapsed+=dt; displayElapsed+=dt
    if elapsed>=0.1 then
        local step=elapsed; elapsed=0
        safeCall(move,"Tick",step); safeCall(combat,"Tick",step)
        local ok,err=pcall(farmTick)
        if not ok then status("Autoplay",err); c:StopNavigation() end
    end
    if displayElapsed>=0.4 then
        displayElapsed=0
        c:RefreshGeneratorESP()
        local active=false
        for _,key in ipairs({"AutoPlay","AutoFarmGenerators","AutoBlock","InfiniteStamina","AntiDebuff"}) do active=active or c.State[key] end
        local badgeText=active and "ACTIVE" or "PAUSED"
        if badge.Text~=badgeText then badge.Text=badgeText; tween(badge,{TextColor3=active and C.Green or C.Muted}) end
        statusLabel.Text=c.NavStatus
        local ch,h=character()
        local stamina=safeCall(move,"Snapshot") or {}
        local role=ch and ch.Parent and ch.Parent.Name or "Loading"
        local health=h and math.floor(h.Health) or 0
        statsLabel.Text=string.format("%s  /  %d health\nStamina: %s / %s",role,health,
            type(stamina.Stamina)=="number" and tostring(math.floor(stamina.Stamina)) or "--",
            type(stamina.MaxStamina)=="number" and tostring(math.floor(stamina.MaxStamina)) or "--")
        local combatInfo=safeCall(combat,"Snapshot") or {}
        detailsLabel.Text=table.concat({"Movement: "..tostring(stamina.Status or c.FeatureStatus.Movement or "Paused"),
            "\nDefense: "..tostring(combatInfo.Reason or c.FeatureStatus.AutoBlock or "Paused"),
            "\nPuzzles: "..tostring(generators and (generators.Status or generators.Puzzle) or c.FeatureStatus.Generators or "Paused"),
            "\nLast diagnostic: "..tostring(c.FeatureStatus.Error or "None"),
            "\nLocal recovery does not remove server damage or stuns."},"\n")
    end
end)
c.Ready=true
c:Notify("Ready. All automation is paused. RightShift opens the hub.")
print("ALLENS_FORSAKEN_READY",c.Version,"movement",move~=nil,"combat",combat~=nil,"generators",generators~=nil)
