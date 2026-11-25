-- Allens Forsaken Script | standalone bundle v12 / independent feature library
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
    local function stepDelay()
        if ctx.State.SeparatePuzzleTiming then
            local key=({Connect="ConnectPairDelay",Flow="FlowCellDelay",Gear="GearTurnDelay",Lock="LockPressDelay"})[m.Puzzle]
            if key then return math.clamp(tonumber(ctx.State[key]) or .1,.05,3) end
        end
        return math.clamp(tonumber(ctx.State.PuzzleStepDelay) or .2,.1,3)
    end
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
        return ctx.State.AutoFarmGenerators == true or ctx.State.AutoPlay == true or ctx.State.AutoRotateGear == true
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
            if kind~="Gear" and not ctx.State.AutoFarmGenerators and not ctx.State.AutoPlay then continue end
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
                            callbacks.OnTurn(math.clamp(tonumber(ctx.State.GearTurnDegrees) or 90,15,180))
                        end
                        m.Status="Rotating gear clockwise; waiting for native completion"
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
local SUITE_FEATURES=(function()
-- Original Allen Scripts controls. No external script engine is loaded.
local rows={}
local function add(section,key,label,kind,default,extra)
 local r={Section=section,Key=key,Label=label,Kind=kind,Default=default}
 for k,v in pairs(extra or {}) do r[k]=v end
 rows[#rows+1]=r;return r
end
local function toggle(s,k,l,help)return add(s,k,l,"toggle",false,{Help=help or ""})end
local function number(s,k,l,d,lo,hi,step)return add(s,k,l,"number",d,{Min=lo,Max=hi,Step=step or 1})end
local function choice(s,k,l,d,options)return add(s,k,l,"choice",d,{Options=options})end
local function text(s,k,l,d)return add(s,k,l,"text",d or "")end
local function action(s,k,l)return add(s,k,l,"action")end
for _,role in ipairs({"Survivor","Killer"}) do
 for _,field in ipairs({{"MaxStamina",100,20,500},{"StaminaGain",20,0,100},{"StaminaLoss",10,0,50},{"SprintSpeed",26,10,60}}) do
  toggle("Stamina",role..field[1].."On",role.." custom "..field[1],"Local sprint controller setting; server rules still apply.")
  number("Stamina",role..field[1],field[1].." value",field[2],field[3],field[4],1)
 end
 number("Stamina",role.."SpeedBoost",role.." speed boost (%)",0,0,100,1)
end
toggle("Stamina","NoStaminaPenalty","Remove local recovery delay")
toggle("Stamina","ToggleSprint","Toggle sprint with Left Shift")
toggle("Stamina","ManageSprint","Stop sprinting before exhaustion")
number("Stamina","SprintStopPercent","Stop sprinting below (%)",15,0,75)
action("Stamina","RecommendedStamina","Use recommended stamina settings")
action("Stamina","ResetStamina","Reset custom stamina settings")
for _,entry in ipairs({{"KillerESP","Killers"},{"SurvivorESP","Survivors"},{"ItemESP","Items"},{"ProjectileESP","Projectiles"},{"ObjectESP","Traps and deployables"},{"ObjectiveESP","Map objectives"},{"EventESP","Event pickups"}}) do toggle("Visual",entry[1],entry[2].." ESP") end
add("Visual","ESPTags","Names and distance tags","toggle",true)
add("Visual","ESPHealth","Player health in tags","toggle",true)
number("Visual","ESPTextSize","Tag text size",12,8,24)
number("Visual","ESPFill","Highlight transparency",.8,0,1,.05)
number("Visual","ESPRange","ESP range (studs)",2500,50,5000,50)
text("Visual","KillerColor","Killer color (hex)","FF606F")
text("Visual","SurvivorColor","Survivor color (hex)","64E3A0")
text("Visual","ItemColor","Item color (hex)","7B8CFF")
toggle("Visual","ThreatWarning","Attack warnings","Uses nearby killers' native attack animations.")
toggle("Generators","SeparatePuzzleTiming","Separate timing for each puzzle")
number("Generators","ConnectPairDelay","Connect step interval (seconds)",.15,.05,1,.05)
number("Generators","FlowCellDelay","Flow cell interval (seconds)",.1,.05,1,.05)
number("Generators","GearTurnDelay","Gear rotation interval (seconds)",.1,.05,1,.05)
number("Generators","LockPressDelay","Lock press interval (seconds)",.05,.05,1,.05)
number("Generators","GearTurnDegrees","Clockwise degrees per gear step",90,15,180,15)
toggle("Combat","AutoM1","Auto primary attack","Uses the equipped actor's native main ability and cooldown guard.")
number("Combat","AttackRange","Primary attack distance",8,2,20,.5)
number("Combat","AbilityRange","Character ability distance",14,2,100,1)
number("Combat","RequestSpacing","Minimum ability request interval",.2,.1,2,.1)
toggle("Combat","AutoTrapQTE","Auto Azure trap minigame","Presses Space when the native marker enters an unfinished target zone (PC input).")
toggle("Combat","AutoHookQTE","Auto Nosferatu hook minigame","Reads the active native QTE key; does not submit a fabricated result.")
toggle("Combat","InfiniteQTEAttempts","Preserve local Azure QTE attempts","Resets the client's failed-attempt counter; server rules remain authoritative.")
number("Combat","QTEInputInterval","Minimum QTE input interval",.1,.05,.5,.05)
toggle("Combat","AutoDodge","Move away from incoming attacks")
number("Combat","DodgeRadius","Attack warning / dodge radius",14,5,35)
toggle("Combat","AntiBackstab","Face nearby threats behind you")
toggle("Combat","BodyBlock","Move into a selected opponent's path")
number("Combat","BodyBlockPrediction","Body-block lead time",.25,0,1,.05)
text("Combat","AbilityName","Native ability name", "Block")
action("Combat","UseAbility","Request selected native ability")
number("Combat","BackstabRadius","Backstab checking distance",8,3,20)
toggle("Combat","AttackVisualizer","Visualize attack range","Visualization only; does not change server hitboxes.")
number("Combat","VisualWidth","Visualizer width",5,1,20,.5)
number("Combat","VisualHeight","Visualizer height",6,1,20,.5)
number("Combat","VisualLength","Visualizer length",8,1,30,.5)
toggle("Aim","AimBot","Aim assist")
toggle("Aim","SilentAim","Native mouse-position aim","Overrides this game's mouse-position interface; restores on disable.")
choice("Aim","AimMethod","Aim method","Camera",{"Camera","Root","Camera + Root"})
choice("Aim","AimTargetType","Target type","Auto",{"Auto","Killers","Survivors","All"})
choice("Aim","AimPart","Aim part","HumanoidRootPart",{"HumanoidRootPart","Head"})
add("Aim","WallCheck","Wall check","toggle",true)
toggle("Aim","StickyTarget","Keep the same target")
toggle("Aim","LowestHealthTarget","Prefer lowest-health target")
toggle("Aim","AimOnAttack","Aim only during an attack")
add("Aim","AimUseFOV","Use screen FOV","toggle",true)
toggle("Aim","ShowAimFOV","Show FOV circle")
number("Aim","AimFOV","FOV radius (pixels)",150,30,600,10)
number("Aim","AimDistance","Maximum aim distance",300,10,2500,10)
number("Aim","AimPrediction","Prediction (seconds)",.1,0,1,.025)
toggle("Aim","PingPrediction","Add measured ping prediction")
number("Aim","AimSmoothness","Aim smoothing",15,1,40)
number("Aim","AimLockTime","Manual attack lock duration",.6,.1,3,.1)
text("Aim","TargetPlayer","Optional target username")
local abilities={
 {"Survivors","Guest1337","AutoPunch","Automatic punch","Punch"},
 {"Survivors","Guest1337","AutoCharge","Automatic charge","Charge"},
 {"Survivors","Guest1337","GuestAim","Punch / charge aim",false},
 {"Survivors","Shedletsky","AutoSlash","Automatic slash","Slash"},
 {"Survivors","Shedletsky","ShedAim","Slash aim",false},
 {"Survivors","Shedletsky","AutoChicken","Eat chicken when injured","FriedChicken","heal"},
 {"Survivors","Chance","AutoCoinFlip","Automatic coin flip","CoinFlip","utility"},
 {"Survivors","Chance","ChanceAim","Shoot aim",false},
 {"Survivors","Chance","AutoShoot","Automatic shoot","Shoot"},
 {"Survivors","Chance","AutoHatFix","Automatic hat repair","HatFix","utility"},
 {"Survivors","Elliot","PizzaAim","Pizza delivery aim",false,"support"},
 {"Survivors","Elliot","AutoPizza","Throw pizza to injured allies","ThrowPizza","support"},
 {"Survivors","Elliot","AutoRushHour","Rush Hour when threatened","RushHour","threat"},
 {"Survivors","007n7","AutoClone","Clone when threatened","Clone","threat"},
 {"Survivors","Veeronica","AutoSkate","Use Sk8 when available","Sk8","skate"},
 {"Survivors","TwoTime","AutoBackstab","Backstab when behind the killer","Dagger","backstab"},
 {"Survivors","TwoTime","TwoTimeAim","Dagger aim",false},
 {"Survivors","TwoTime","AutoPray","Pray when safe and injured","Pray","safeheal"},
 {"Survivors","Noob","AutoCola","Cola when threatened","BloxyCola","threat"},
 {"Survivors","Noob","AutoGhostburger","Ghostburger when threatened","Ghostburger","threat"},
 {"Survivors","Noob","AutoSlateskin","Slateskin when threatened","SlateskinPotion","threat"},
 {"Survivors","JaneDoe","CrystalAim","Crystal pitch aim",false},
 {"Survivors","JaneDoe","HatchetAim","Hatchet aim",false},
 {"Survivors","Dusekkar","PlasmaAim","Plasma beam aim",false},
 {"Survivors","Dusekkar","AutoProtection","Protect an injured ally","SpawnProtection","support"},
 {"Killers","Noli","NoliAim","Void Rush / Nova aim",false},
 {"Killers","Noli","AutoNova","Use Nova in range","Nova"},
 {"Killers","Noli","AutoVoidRush","Use Void Rush in range","VoidRush"},
 {"Killers","Slasher","SlasherAim","Slasher ability aim",false},
 {"Killers","Slasher","AutoRagingPace","Use Raging Pace","RagingPace","utility"},
 {"Killers","JohnDoe","JohnAim","John Doe projectile aim",false},
 {"Killers","JohnDoe","Auto404","Use 404 Error","404Error","utility"},
 {"Killers","1x1x1x1","OneAim","Mass Infection / Entanglement aim",false},
 {"Killers","Azure","AzureAim","Tentacle ability aim",false},
 {"Killers","Nosferatu","NosferatuAim","Nosferatu ability aim",false},
 {"Killers","c00lkidd","CoolkidAim","Corrupt Nature / dash aim",false},
 {"Killers","Sixer","SixerAim","Demonic Pursuit aim",false},
}
toggle("Survivors","AutoTrick","Veeronica / automatic tricks","Uses the native ready highlight and Space input while skating.")
toggle("Survivors","AutoFarmSk8","Veeronica / skate practice","Starts Sk8 when native requirements permit and steers around your nearest spray zone.")
toggle("Survivors","AntiRebound","Veeronica / disable local phase rebounds")
for _,a in ipairs(abilities) do
 local r=toggle(a[1],a[3],a[2].." / "..a[4],a[5] and "Native ability request; respects the game's cooldown and eligibility guard." or "Predictive aim for this actor.")
 r.Actor=a[2];r.Ability=a[5] or nil;r.AbilityMode=a[6];r.ActorAim=not a[5]
end
local configFields={
 {"Guest1337","ChargingTurnSpeed",2,0,20},{"Guest1337","ChargingSpeed",34,10,80},{"Guest1337","PunchDashForce",40,0,100},
 {"Veeronica","Sk8TurnControl",.65,0,5},{"Veeronica","Sk8Speed",1.15,.1,5},{"Veeronica","Sk8TrickPower",75,0,150},
 {"Veeronica","Sk8BumpPower",12,0,50},{"Veeronica","Sk8TrickStamina",10,0,50},{"Veeronica","Sk8TrickCooldown",1,.1,5},
 {"Veeronica","Sk8StaminaLoss",.85,0,3},{"Veeronica","Sk8StaminaLossOut",1.1,0,3},
 {"Noli","VoidRushDashSpeed",60,10,150},{"Noli","VoidRushTurnSpeed",1,0,10},{"Noli","VoidRushInitialTurnMult",6.6,0,20},
 {"Noli","VoidRushDashLength",3.5,.1,20},{"Noli","VoidRushChargingSpeed",.4,.1,3},
 {"Slasher","EnragedSpeed",20,5,60},{"Slasher","Speed",9,5,40},
 {"Sixer","PursuitHorizontalPenalty",.8,0,2},{"Sixer","PursuitGravity",.6,0,2},{"Sixer","PursuitLength",.8,.1,10},
 {"Sixer","PursuitMaxSpeed",17,5,100},{"Sixer","PursuitBaseSpeed",7,1,60},
 {"Nosferatu","AscentFlight.Speed",6.5,1,40},{"Nosferatu","AscentFlight.Duration",10,1,180},
 {"Nosferatu","AscentBite.Speed",100,20,150},{"Nosferatu","AscentBite.TurnSpeed",4,0,20},
 {"Nosferatu","Spire.TurnControl",10,0,40},{"Nosferatu","Spire.Speed",15,1,60},
 {"JaneDoe","Crystal.MaxChargeTime",2,.1,5},{"JaneDoe","Crystal.MinChargeTime",.25,.1,1},
 {"JaneDoe","Crystal.ChargeSpeedMult",.75,.1,3},{"JaneDoe","Axe.DashSpeed",90,10,150},
 {"Azure","Grab.HookSpeed",270,50,500},{"Azure","GolemFissure.VictimSpeedMult",.3,0,1},
 {"TwoTime","DaggerLungeForce",110,0,150},{"TwoTime","DaggerUncrouchedLungeForce",50,0,150},
}
for _,a in ipairs(configFields) do
 local section=(a[1]=="Guest1337" or a[1]=="Veeronica" or a[1]=="TwoTime" or a[1]=="JaneDoe") and "Survivors" or "Killers"
 local key="Config_"..a[1].."_"..a[2]
 local r=toggle(section,key.."On",a[1].." / override "..a[2],"Local configuration only; this cannot change server-owned damage or duration.")
 r.ConfigActor=a[1];r.ConfigField=a[2];r.ValueKey=key
 number(section,key,a[2].." value",a[3],a[4],a[5],.1)
end
text("Misc","ConfigField","Local actor config field (dot path)","Speed")
number("Misc","ConfigValue","Local config value",12,0,1000,.5)
toggle("Misc","CustomConfig","Apply custom local config field")
for _,name in ipairs({"Slowness","Stunned","Blindness","Confusion","Nausea","Hacked","Glitched","Corrupted","Hallucination","Oblivious","Subspaced","Bleeding"}) do toggle("Antis","Anti_"..name,"Suppress local "..name,"Only client visual/movement effects can be changed; server damage and status remain authoritative.") end
toggle("Antis","AntiInvisible","Reveal locally invisible actor parts")
toggle("Antis","DisableDirectionalSpeed","Disable local directional speed penalty")
toggle("Antis","DisableDirectionalMovement","Use ordinary character movement")
toggle("Antis","NoFootsteps","Mute local footsteps")
toggle("Antis","DisableKillerDoors","Disable local killer door collision")
toggle("Antis","WalkablePuddles","Make local puddles non-collidable")
toggle("Antis","HideFakeGenerators","Hide locally identified fake generators")
toggle("Antis","HideClones","Hide locally identified clone actors")
toggle("Items","AutoPickup","Pick up nearby items and gears")
toggle("Items","PickupReach","Extend local pickup prompt reach","Server pickup-distance checks still apply.")
number("Items","PickupMultiplier","Local prompt distance multiplier",2,1,3,.25)
action("Items","NearestCola","Go to nearest Bloxy Cola")
action("Items","NearestMedkit","Go to nearest Medkit")
action("Items","NearestGear","Go to nearest gear")
toggle("Misc","FullBright","Full bright / no fog")
toggle("Misc","InfiniteZoom","Extended zoom / Invisicam")
toggle("Misc","CustomFOV","Custom field of view")
number("Misc","FOVValue","Field of view",85,40,120)
toggle("Misc","LowEffects","Reduce particles and shadows")
toggle("Misc","EnableJump","Enable local jumping")
number("Misc","JumpPower","Local jump power",50,0,100)
toggle("Misc","AntiAFK","Prevent idle input timeout")
toggle("Misc","EnableChat","Show chat window")
toggle("Misc","HideName","Hide your local nameplate")
toggle("Misc","StatsOverlay","Show local role / health / stamina")
choice("Misc","DeviceOverride","Device override","Default",{"Default","PC","Mobile","Console"})
toggle("Misc","ApplyDeviceOverride","Apply device override")
toggle("Teleport","SpectatePlayer","Spectate selected player")
text("Teleport","TeleportPlayer","Selected player username")
action("Teleport","TeleportPlayerNow","Go to selected player")
action("Teleport","NearestGenerator","Go to nearest incomplete generator")
action("Teleport","ReturnSpawn","Return to saved position")
action("Teleport","SavePosition","Save current position")
action("Teleport","ResetCharacter","Reset character")
action("Teleport","Rejoin","Rejoin current server")
action("Teleport","ServerHop","Find another public server")
text("Animations","AnimationId","Animation asset ID")
number("Animations","AnimationSpeed","Playback speed",1,.1,5,.1)
choice("Animations","AnimationPriority","Priority","Action",{"Idle","Movement","Action","Action2","Action3","Action4"})
action("Animations","PlayAnimation","Play animation")
action("Animations","StopAnimation","Stop your custom animation")
text("Music","MusicId","Audio asset ID")
number("Music","MusicVolume","Volume",.4,0,1,.05)
number("Music","MusicSpeed","Playback speed",1,.25,2,.05)
toggle("Music","MusicLoop","Loop local audio")
action("Music","PlayMusic","Play local audio")
action("Music","StopMusic","Stop local audio")
toggle("Fun","Spin","Spin character locally")
toggle("Fun","Flight","Camera-relative local flight")
number("Fun","FlightSpeed","Flight speed",30,5,100)
toggle("Fun","Noclip","Local character noclip")
number("Fun","SpinSpeed","Spin degrees per second",360,30,1440,30)
action("Fun","Sit","Sit down")
text("UI","BackgroundImage","Background image asset ID")
toggle("UI","ShowBackgroundImage","Show custom background")
number("UI","BackgroundTransparency","Background transparency",.85,0,1,.05)
return rows

end)()
local SUITE_LOOKUP={}
for _,def in ipairs(SUITE_FEATURES) do SUITE_LOOKUP[def.Key]=def end
Factories.Suite=(function()
-- Original Allen Scripts runtime. Uses the game's public client modules;
-- no Cursedsaken code, callbacks, loader, or runtime objects are used.
return function(ctx)
 local Players=game:GetService("Players")
 local Run=game:GetService("RunService")
 local UIS=game:GetService("UserInputService")
 local Lighting=game:GetService("Lighting")
 local Teleport=game:GetService("TeleportService")
 local Http=game:GetService("HttpService")
 local RS=ctx.RS or game:GetService("ReplicatedStorage")
 local player=ctx.Player or Players.LocalPlayer
 local state=ctx.State
 local m={Destroyed=false,Requests=0,Markers={},LastError=nil,Target=nil,Inventory={}}
 local connections,patches={},setmetatable({},{__mode="k"})
 local attributes=setmetatable({},{__mode="k"})
 local epoch,lastScan,lastRequest,lastDodge,lastWarning=0,0,-math.huge,-math.huge,-math.huge
 local mouseModule,actors,sprint,network,statuses,device
 local lastActor,lastCamera,oldSubject,savedPosition,animation,sound
 local originalMouse,originalCamera,mouseWrapper,cameraWrapper
 local visualBox,fovRing,overlay,aimUntil= nil,nil,nil,0
 local worldObjects=setmetatable({},{__mode="k"})
 local lastDevice,desiredAim=nil,nil
 local cameraOriginal,cameraWritten
 local flightRoot,flightAttachment,flightVelocity,bodyOwner
 local controls,skateVector,skateGetter
 local schemas=ctx.Schema or {}
 local clock=ctx.Clock or os.clock
 local azureQTE,azureOriginalNew,azureNewWrapper=ctx.AzureQTE,ctx.AzureQTE and ctx.AzureQTE.new,nil
 local lastQTEInput=-math.huge
 local heldKeys={}
 local function status(key,message)
  if ctx.Status then ctx.Status(key,tostring(message)) end
 end
 local function import(path)
  local node=RS
  for _,key in ipairs(path) do node=node and node:FindFirstChild(key) end
  if not node then return nil end
  local ok,value=pcall(require,node)
  return ok and value or nil
 end
 actors=ctx.Actors or import({"Modules","Gameplay","Actors"})
 sprint=ctx.Sprint or import({"Systems","Character","Game","Sprinting"})
 network=ctx.Network or import({"Modules","Network","Network"})
 statuses=ctx.Statuses or import({"Modules","Gameplay","Statuses"})
 device=ctx.Device or import({"Modules","Utilities","Device"})
 mouseModule=ctx.Mouse or import({"Systems","Player","Miscellaneous","GetPlayerMousePosition"})
 if mouseModule then originalMouse=mouseModule.GetMousePos;originalCamera=mouseModule.GetCameraCFrame end
 local function connect(signal,fn)
  local connection=signal:Connect(fn);connections[#connections+1]=connection;return connection
 end
 local function alive(rig)
  local h=rig and rig:FindFirstChildOfClass("Humanoid")
  local root=rig and (rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart)
  if h and h.Health>0 and root then return h,root end
  return nil,nil
 end
 local function actorFor(rig)
  for _,a in pairs(actors and actors.CurrentActors or {}) do if a.Rig==rig then return a end end
 end
 local function localActor()return actorFor(player.Character)end
 local function patch(object,key,value)
  if not object then return end
  local ok,current=pcall(function()return object[key]end)
  if not ok then return end
  local records=patches[object]
  if not records then records={};patches[object]=records end
  local r=records[key]
  if not r then r={Original=current};records[key]=r
  elseif current~=r.Last then r.Original=current end
  local wrote=pcall(function() object[key]=value end)
  if wrote then r.Last=value;r.Epoch=epoch end
 end
 local function restore(object,key,r)
  pcall(function()if object[key]==r.Last then object[key]=r.Original end end)
 end
 local function prune(all)
  for object,records in pairs(patches) do
   for key,r in pairs(records) do if all or r.Epoch~=epoch then restore(object,key,r);records[key]=nil end end
   if not next(records) then patches[object]=nil end
  end
  for object,records in pairs(attributes) do
   for key,r in pairs(records) do if all or r.Epoch~=epoch then
    pcall(function()if object:GetAttribute(key)==r.Last then object:SetAttribute(key,r.Original) end end)
    records[key]=nil
   end end
   if not next(records) then attributes[object]=nil end
  end
 end
 local function patchAttribute(object,key,value)
  local records=attributes[object]
  if not records then records={};attributes[object]=records end
  local current=object:GetAttribute(key)
  local r=records[key]
  if not r then r={Original=current};records[key]=r elseif current~=r.Last then r.Original=current end
  if current~=value then object:SetAttribute(key,value) end
  r.Last=value;r.Epoch=epoch
 end
 local function hex(value,fallback)
  local s=tostring(value):gsub("#","")
  if s:match("^%x%x%x%x%x%x$") then return Color3.fromRGB(tonumber(s:sub(1,2),16),tonumber(s:sub(3,4),16),tonumber(s:sub(5,6),16)) end
  return fallback
 end
 local function visible(rig,position)
  if not state.WallCheck then return true end
  local _,root=alive(player.Character)
  if not root then return false end
  local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Exclude
  ray.FilterDescendantsInstances={player.Character,rig};ray.RespectCanCollide=true
  return workspace:Raycast(root.Position,position-root.Position,ray)==nil
 end
 local function matchesRole(rig,healing)
  local char=player.Character
  if rig==char or not rig.Parent then return false end
  if healing then return rig.Parent.Name=="Survivors" end
  local mode=state.AimTargetType or "Auto"
  if mode=="All" then return rig.Parent.Name=="Survivors" or rig.Parent.Name=="Killers" end
  if mode=="Auto" then mode=char and char.Parent and char.Parent.Name=="Killers" and "Survivors" or "Killers" end
  return rig.Parent.Name==mode
 end
 function m:ChooseTarget(screenFilter,healing)
  local _,root=alive(player.Character);local camera=workspace.CurrentCamera
  if not root or not camera then return nil end
  local best,bestScore=nil,math.huge
  local selected=tostring(state.TargetPlayer or ""):lower()
  for _,actor in pairs(actors and actors.CurrentActors or {}) do
   local rig=actor.Rig;local h,r=alive(rig)
   if h and matchesRole(rig,healing) then
    local p=Players:GetPlayerFromCharacter(rig)
    local allowed=selected=="" or p and (p.Name:lower():sub(1,#selected)==selected or p.DisplayName:lower():sub(1,#selected)==selected)
    local distance=(r.Position-root.Position).Magnitude
    if allowed and distance<=(state.AimDistance or 300) and visible(rig,r.Position) and (not healing or h.Health<h.MaxHealth) then
     local screen,onScreen=camera:WorldToViewportPoint(r.Position)
     local pixels=(Vector2.new(screen.X,screen.Y)-camera.ViewportSize/2).Magnitude
     if not screenFilter or not state.AimUseFOV or onScreen and pixels<=(state.AimFOV or 150) then
      if state.StickyTarget and m.Target==rig and not healing then return rig end
      local score=state.LowestHealthTarget or healing
      score=score and h.Health/math.max(1,h.MaxHealth)*1000+distance*.01 or distance
      if score<bestScore then best,bestScore=rig,score end
     end
    end
   end
  end
  return best
 end
 local function prediction(rig)
  local _,root=alive(rig);if not root then return end
  local part=rig:FindFirstChild(state.AimPart or "HumanoidRootPart") or root
  local lead=state.AimPrediction or .1
  if state.PingPrediction then local ok,ping=pcall(player.GetNetworkPing,player);if ok then lead+=math.clamp(ping,0,.4) end end
  return part.Position+root.AssemblyLinearVelocity*lead
 end
 local function activeInput()
  return (not ctx.CanAutomate or ctx.CanAutomate()) and not UIS:GetFocusedTextBox()
 end
 local function sendKey(key)
  if clock()-lastQTEInput<(state.QTEInputInterval or .1) or not activeInput() then return false end
  lastQTEInput=clock()
  if ctx.SyntheticInput then ctx.SyntheticInput() end
  if ctx.SendKey then ctx.SendKey(key);return true end
  local input=game:GetService("VirtualInputManager")
  local ok=pcall(input.SendKeyEvent,input,true,key,false,game)
  if not ok then status("Suite","This executor cannot deliver native QTE keyboard input");return false end
  heldKeys[key]=true
  task.delay(.025,function()
   pcall(input.SendKeyEvent,input,false,key,false,game);heldKeys[key]=nil
  end)
  return true
 end
 function m:TickQTE()
  if not activeInput() then return end
  if state.AutoTrapQTE or state.InfiniteQTEAttempts then
   if not azureQTE then
    local folder=RS:FindFirstChild("Assets");folder=folder and folder:FindFirstChild("Killers");folder=folder and folder:FindFirstChild("Azure")
    local module=folder and folder:FindFirstChild("Config")
    if module then
     local ok,config=pcall(require,module)
     local refs=ok and config.Instances and config.Instances.ClientQTEModules
     local source=refs and (type(refs)=="table" and refs.Behavior or refs:FindFirstChild("Behavior"))
     if source then local ready,result=pcall(require,source);if ready then azureQTE=result;azureOriginalNew=result.new end end
    end
   end
   if azureQTE and type(azureOriginalNew)=="function" then
    if not azureNewWrapper then azureNewWrapper=function(...)
     local object=azureOriginalNew(...);if object then m.TrapQTE=object end;return object
    end end
    patch(azureQTE,"new",azureNewWrapper)
    if not m.TrapQTE then
     local inspect=type(getupvalues)=="function" and getupvalues or debug and debug.getupvalues
     if inspect then local ok,values=pcall(inspect,azureOriginalNew)
      if ok then for _,value in pairs(values) do if type(value)=="table" and type(value.QTEBounds)=="table" and type(value.CompletedZones)=="table" then m.TrapQTE=value;break end end end
     end
    end
    local q=m.TrapQTE
    if q and state.InfiniteQTEAttempts and type(q.FailedAttempts)=="number" then patch(q,"FailedAttempts",0) end
    if q and q.UI and q.UI.UI and q.UI.UI.Parent and type(q.Value)=="number" then
     for index,zone in ipairs(q.QTEBounds or {}) do
      if state.AutoTrapQTE and not q.CompletedZones[index] and q.Value>=zone.Min+.01 and q.Value<=zone.Max-.01 then sendKey(Enum.KeyCode.Space);break end
     end
    elseif q then m.TrapQTE=nil end
   end
  end
  if state.AutoHookQTE then
   for _,actor in pairs(actors and actors.CurrentActors or {}) do
    local ui=actor.Meta and actor.Meta.ActiveQTE
    if typeof(ui)=="Instance" and ui.Parent and ui:IsDescendantOf(player.PlayerGui) then
     local active=ui:FindFirstChild("ActiveButton")
     if active and active:IsA("GuiButton") and type(firesignal)=="function" and clock()-lastQTEInput>(state.QTEInputInterval or .1) then
      lastQTEInput=clock();firesignal(active.MouseButton1Down)
     else
      for _,label in ipairs(ui:QueryDescendants("TextLabel")) do
       local parent=label.Parent
       if parent and parent:IsA("ImageLabel") and parent.Visible and parent.Position.X.Scale<.7 and label.TextTransparency<.5 and parent.ImageTransparency<.5 then
        local name=label.Text:upper()
        local aliases={SPACE="Space",["↑"]="Up",["↓"]="Down",["←"]="Left",["→"]="Right",UP="Up",DOWN="Down",LEFT="Left",RIGHT="Right"}
        local ok,key=pcall(function()return Enum.KeyCode[aliases[name] or name]end)
        if ok and key and key~=Enum.KeyCode.Unknown then sendKey(key);break end
       end
      end
     end
    end
   end
  end
 end
 local function actorAiming(actor)
  local enabled=state.AimBot or state.SilentAim
  local support,automatic=false,false
  for _,def in ipairs(schemas) do
   if state[def.Key] and actor and actor.ActorName==def.Actor then
    if def.ActorAim or def.Ability and (not def.AbilityMode or def.AbilityMode=="support" or def.AbilityMode=="backstab") then
     enabled=true;automatic=true;support=support or def.AbilityMode=="support"
    end
   end
  end
  return enabled,support,automatic
 end
 local function sendAbility(actor,name)
  if m.Destroyed or not activeInput() or not network or clock()-lastRequest<(state.RequestSpacing or .2) then return false end
  if m.RequestBusy then return false end
  local ability=actor and actor.Behavior and actor.Behavior.Abilities and actor.Behavior.Abilities[name]
  if type(ability)~="table" or type(actor.CanUseAbility)~="function" then return false end
  local ok,allowed=pcall(actor.CanUseAbility,actor,name)
  if not ok or not allowed then return false end
  local payload
  m.RequestBusy=true
  lastRequest=clock()
  if type(ability.ClientCallback)=="function" then
   local ready,value=pcall(ability.ClientCallback,actor)
   if not ready or value==false then m.RequestBusy=false;return false end
   payload=value
  end
  if m.Destroyed then m.RequestBusy=false;return false end
  local sent,err=pcall(network.FireServerConnection,network,"UseActorAbility","REMOTE_EVENT",name,payload)
  m.RequestBusy=false
  if sent then m.Requests+=1;aimUntil=clock()+(state.AimLockTime or .6);status("Suite","Requested "..name)
  else status("Suite",err) end
  return sent
 end
 function m:RequestAbility(name)return sendAbility(localActor(),name)end
 local function threat(root)
  local nearest,distance=nil,math.huge
  for _,actor in pairs(actors and actors.CurrentActors or {}) do
   local rig=actor.Rig;local _,r=alive(rig)
   if r and rig.Parent.Name=="Killers" and rig~=player.Character then
    local d=(root.Position-r.Position).Magnitude
    if d<distance then nearest,distance=actor,d end
   end
  end
  return nearest,distance
 end
 local function attacking(actor)
  for name,ability in pairs(actor and actor.Behavior and actor.Behavior.Abilities or {}) do
   if type(ability)=="table" and ability.KeybindType=="MainAbility" then
    for _,key in ipairs({name,"Attack","Punch","Slash","Stab","Tag"}) do
     local track=actor.Animations and actor.Animations[key]
     if typeof(track)=="Instance" and track:IsA("AnimationTrack") and track.IsPlaying then return true end
    end
   end
  end
  return false
 end
 local objectNames={
  gear="Item",bloxycola="Item",bloxcola="Item",medkit="Item",fruit="Item",apple="Item",banana="Item",
  sentry="Object",dispenser="Object",ritual="Object",graffiti="Object",trap="Object",tentacle="Object",tripwire="Object",
  projectile="Projectile",pizza="Projectile",corruptnature="Projectile",massinfection="Projectile",entanglement="Projectile",
  pumpkin="Event",candy="Event",ring="Event",folder="Objective",objective="Objective",bloodorb="Object",
 }
 local function classify(object)
  if not object:IsA("Model") and not object:IsA("BasePart") then return end
  local name=object.Name:lower():gsub("[^%w]","")
  local category=objectNames[name]
  if not category then
   if name:find("projectile",1,true) then category="Projectile"
   elseif name:find("pumpkin",1,true) or name:find("candy",1,true) then category="Event"
   elseif name:find("trap",1,true) or name:find("graffiti",1,true) or name:find("ritual",1,true) or name:find("sentry",1,true) then category="Object"
   elseif name:find("door",1,true) or name:find("puddle",1,true) or name:find("fake",1,true) or name:find("clone",1,true) then category="Surface" end
  end
  if category then worldObjects[object]=category end
 end
 for _,rootName in ipairs({"Map","Misc","HalloweenPumpkins"}) do
  local root=workspace:FindFirstChild(rootName)
  if root then
   for _,o in ipairs(root:QueryDescendants("Model")) do classify(o) end
   for _,o in ipairs(root:QueryDescendants("#Gear, #BloxyCola, #Medkit, #BloodOrb")) do classify(o) end
   connect(root.DescendantAdded,classify)
  end
 end
 connect(workspace.ChildAdded,function(root)
  if root.Name=="Map" or root.Name=="Misc" or root.Name=="HalloweenPumpkins" then
   for _,o in ipairs(root:QueryDescendants("Model")) do classify(o) end
   connect(root.DescendantAdded,classify)
  else classify(root) end
 end)
 local markerRoot=Instance.new("Folder");markerRoot.Name="AllensIndependentESP";markerRoot.Parent=workspace.CurrentCamera or workspace
 local visualGui=Instance.new("ScreenGui");visualGui.Name="AllensForsakenOverlay";visualGui.ResetOnSpawn=false;visualGui.IgnoreGuiInset=true
 visualGui.DisplayOrder=1000025;visualGui.Parent=player:WaitForChild("PlayerGui")
 m.Gui=visualGui
 local function makeMarker(object,part,color)
  local highlight=Instance.new("Highlight");highlight.Name="AllenHighlight";highlight.Adornee=object
  highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;highlight.OutlineTransparency=.1;highlight.Parent=markerRoot
  local bill=Instance.new("BillboardGui");bill.Name="AllenTag";bill.Adornee=part
  bill.Size=UDim2.fromOffset(220,52);bill.StudsOffsetWorldSpace=Vector3.new(0,3,0);bill.AlwaysOnTop=true;bill.Parent=visualGui
  local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.TextStrokeTransparency=.3
  label.Font=Enum.Font.GothamBold;label.Parent=bill
  local record={Highlight=highlight,Gui=bill,Label=label};m.Markers[object]=record;return record
 end
 local function updateMarker(object,part,text,color,distance)
  if distance>(state.ESPRange or 2500) then return end
  local marker=m.Markers[object] or makeMarker(object,part,color)
  marker.Epoch=epoch;marker.Highlight.FillColor=color;marker.Highlight.OutlineColor=color
  marker.Highlight.FillTransparency=state.ESPFill or .8
  marker.Gui.Adornee=part;marker.Gui.Enabled=state.ESPTags==true
  marker.Label.Text=text;marker.Label.TextColor3=color;marker.Label.TextSize=state.ESPTextSize or 12
 end
 function m:RefreshESP()
  local _,root=alive(player.Character);local origin=root and root.Position or workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero
  for _,actor in pairs(actors and actors.CurrentActors or {}) do
   local rig=actor.Rig;local h,r=alive(rig)
   if h and rig~=player.Character then
    local killer=rig.Parent.Name=="Killers"
    if killer and state.KillerESP or not killer and state.SurvivorESP then
     local p=Players:GetPlayerFromCharacter(rig)
     local distance=(r.Position-origin).Magnitude
     local title=(p and p.DisplayName or actor.ActorName or rig.Name).."  |  "..math.floor(distance).." studs"
     if state.ESPHealth then title..="\n"..math.floor(h.Health).." / "..math.floor(h.MaxHealth).." HP" end
     updateMarker(rig,r,title,hex(killer and state.KillerColor or state.SurvivorColor,Color3.new(1,1,1)),distance)
    end
   end
  end
  m.Inventory={}
  for object,category in pairs(worldObjects) do
   if object:IsDescendantOf(workspace) then
    local part=object:IsA("BasePart") and object or object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart",true)
    if part then
     local distance=(part.Position-origin).Magnitude
     if category=="Item" then m.Inventory[#m.Inventory+1]={Object=object,Part=part,Distance=distance} end
     if state[category.."ESP"] then updateMarker(object,part,object.Name.."  |  "..math.floor(distance).." studs",hex(state.ItemColor,Color3.fromRGB(123,140,255)),distance) end
    end
   else worldObjects[object]=nil end
  end
  for object,marker in pairs(m.Markers) do
   if marker.Epoch~=epoch then marker.Gui:Destroy();marker.Highlight:Destroy();m.Markers[object]=nil end
  end
 end
 local pickupAt=setmetatable({},{__mode="k"})
 local promptDefaults=setmetatable({},{__mode="k"})
 local function pickup()
  for _,item in ipairs(m.Inventory) do
   local prompt=item.Object:FindFirstChildWhichIsA("ProximityPrompt",true)
   if prompt then
    if not promptDefaults[prompt] then promptDefaults[prompt]=prompt.MaxActivationDistance end
    if state.PickupReach then patch(prompt,"MaxActivationDistance",promptDefaults[prompt]*(state.PickupMultiplier or 2)) end
    if state.AutoPickup and activeInput() and prompt.Enabled and item.Distance<=prompt.MaxActivationDistance and clock()-(pickupAt[prompt] or 0)>1.2 then
     pickupAt[prompt]=clock()
     if type(fireproximityprompt)=="function" then fireproximityprompt(prompt)
     else
      prompt:InputHoldBegin()
      task.delay(prompt.HoldDuration+.05,function()if not m.Destroyed and prompt.Parent then prompt:InputHoldEnd() end end)
     end
    end
   elseif state.AutoPickup and activeInput() and item.Object.Name=="Gear" and item.Distance<=5 and clock()-(pickupAt[item.Object] or 0)>1.2 then
    local _,root=alive(player.Character)
    if root and type(firetouchinterest)=="function" then
     local touch=item.Object:FindFirstChildWhichIsA("TouchTransmitter",true)
     local part=touch and touch.Parent or item.Part
     pickupAt[item.Object]=clock();firetouchinterest(root,part,0);firetouchinterest(root,part,1)
    end
   end
  end
 end
 local function configTarget(config,path)
  local parent=config;local keys=string.split(tostring(path),".")
  for i=1,#keys-1 do
   local key=keys[i];if type(parent)=="table" and parent[key]==nil then key=tonumber(key) or key end
   parent=type(parent)=="table" and parent[key] or nil
  end
  local key=keys[#keys];if type(parent)=="table" and parent[key]==nil then key=tonumber(key) or key end
  return parent,key
 end
 local function applyConfig(actor)
  if not actor then return end
  if actor.ActorName=="Veeronica" and state.AntiRebound and type(actor.Config.Sk8PhaseBounceEnabled)=="boolean" then patch(actor.Config,"Sk8PhaseBounceEnabled",false) end
  for _,def in ipairs(schemas) do
   if def.ConfigField and state[def.Key] and actor.ActorName==def.ConfigActor then
    local parent,key=configTarget(actor.Config,def.ConfigField)
    if parent and type(parent[key])=="number" then patch(parent,key,state[def.ValueKey])
    else status(def.Key,"This actor version has no numeric field "..def.ConfigField) end
   end
  end
  if state.CustomConfig then
   local parent,key=configTarget(actor.Config,state.ConfigField)
   if parent and type(parent[key])=="number" then patch(parent,key,state.ConfigValue)
   else status("CustomConfig","Unknown numeric config field; inspect the current actor first") end
  end
 end
 local function applyStamina(actor,h,root)
  if not sprint or not sprint.DefaultsSet or not actor then return end
  local role=actor.Rig.Parent.Name=="Killers" and "Killer" or "Survivor"
  for _,field in ipairs({"MaxStamina","StaminaGain","StaminaLoss","SprintSpeed"}) do
   if state[role..field.."On"] then
    local value=state[role..field];patch(sprint,field,value)
    if field=="MaxStamina" then patch(sprint,"StaminaCap",value) end
    if field=="SprintSpeed" then patch(sprint,"CurrentSprintSpeed",value) end
   end
  end
  if state.NoStaminaPenalty then patch(sprint,"timeUntilStaminaRecovers",0) end
  local boost=state[role.."SpeedBoost"] or 0
  if boost>0 and typeof(sprint.__speedMultiplier)=="Instance" then patch(sprint.__speedMultiplier,"Value",1+boost/100) end
  if state.ManageSprint and type(sprint.Stamina)=="number" and type(sprint.MaxStamina)=="number" and sprint.IsSprinting then
   if sprint.Stamina/math.max(1,sprint.MaxStamina)*100<=(state.SprintStopPercent or 15) then
    local movement=ctx.GetMovement and ctx.GetMovement()
    if movement then movement:SetSprint(false) end
   end
  end
 end
 local function suppressStatuses()
  local entries=statuses and statuses.CurrentStatuses and statuses.CurrentStatuses[player]
  for name,entry in pairs(entries or {}) do
   if state["Anti_"..name] and entry.Character==player.Character then
    local info=type(entry.Info)=="table" and entry.Info or entry
    for _,key in ipairs({"SpeedMultiplier","FOVMultiplier","JumpMultiplier"}) do
     local object=info[key];if typeof(object)=="Instance" and object:IsA("NumberValue") then patch(object,"Value",1) end
    end
    for key,object in pairs(info) do
     if typeof(object)=="Instance" then
      if object:IsA("PostEffect") then patch(object,"Enabled",false)
      elseif object:IsA("ScreenGui") then patch(object,"Enabled",false)
      elseif object:IsA("GuiObject") and (key=="Overlay" or key=="Frame" or key=="UI") then patch(object,"Visible",false) end
     end
    end
    if name=="Nausea" and type(info.TickTimePast)=="number" then patch(info,"TickTimePast",0) end
   end
  end
 end
 local function applyMisc(actor,h,root)
  if state.FullBright then
   patch(Lighting,"Brightness",3);patch(Lighting,"ClockTime",14);patch(Lighting,"FogEnd",1000000)
   patch(Lighting,"Ambient",Color3.fromRGB(190,190,190));patch(Lighting,"OutdoorAmbient",Color3.fromRGB(190,190,190))
   for _,object in ipairs(Lighting:GetChildren()) do if object:IsA("Atmosphere") then patch(object,"Density",0);patch(object,"Haze",0) end end
  end
  if state.InfiniteZoom then patch(player,"CameraMaxZoomDistance",100000);patch(player,"DevCameraOcclusionMode",Enum.DevCameraOcclusionMode.Invisicam) end
  if state.EnableChat then
   local chat=game:GetService("TextChatService"):FindFirstChildOfClass("ChatWindowConfiguration")
   if chat then patch(chat,"Enabled",true) end
  end
  if state.LowEffects then patch(Lighting,"GlobalShadows",false) end
  if state.EnableJump and h then patch(h,"UseJumpPower",true);patch(h,"JumpPower",state.JumpPower or 50) end
  if state.HideName and h then patch(h,"DisplayDistanceType",Enum.HumanoidDisplayDistanceType.None) end
  if state.Flight and h then patch(h,"PlatformStand",true);patch(h,"AutoRotate",false) end
  if state.Noclip and player.Character then for _,part in ipairs(player.Character:QueryDescendants("BasePart")) do patch(part,"CanCollide",false) end end
  if device and state.ApplyDeviceOverride and state.DeviceOverride~="Default" then
   patch(device,"Value",state.DeviceOverride)
   if lastDevice~=state.DeviceOverride and network then
    pcall(network.FireServerConnection,network,"SetDevice","REMOTE_EVENT",state.DeviceOverride)
    if device.Changed then pcall(function()device.Changed:Fire(state.DeviceOverride)end) end
    lastDevice=state.DeviceOverride
   end
  elseif lastDevice then
   local records=device and patches[device];local r=records and records.Value
   if r and network then pcall(network.FireServerConnection,network,"SetDevice","REMOTE_EVENT",r.Original) end
   lastDevice=nil
  end
  if h and state.SpectatePlayer then
   local name=tostring(state.TeleportPlayer or ""):lower()
   for _,p in ipairs(Players:GetPlayers()) do if name~="" and p.Name:lower():sub(1,#name)==name then
    local hum=alive(p.Character);if hum then patch(workspace.CurrentCamera,"CameraSubject",hum) end
   end end
  end
  if player.Character then
   if state.DisableDirectionalMovement or state.DisableDirectionalSpeed then patchAttribute(player.Character,"DirectionalMovementDisabled",true) end
   if state.NoFootsteps then patchAttribute(player.Character,"FootstepsMuted",true) end
   if state.NoFootsteps then for _,s in ipairs(player.Character:QueryDescendants("Sound")) do if s.Name:lower():find("step",1,true) or s.Name=="Running" then patch(s,"Volume",0) end end end
   if state.AntiInvisible then
    for _,actorEntry in pairs(actors and actors.CurrentActors or {}) do
     if actorEntry.Rig~=player.Character then for _,part in ipairs(actorEntry.Rig:QueryDescendants("BasePart")) do
      if part.Name~="HumanoidRootPart" then patch(part,"LocalTransparencyModifier",0);if part.Transparency>=.95 then patch(part,"Transparency",.35) end end
     end end
    end
   end
   if state.HideClones then
    local worldPlayers=workspace:FindFirstChild("Players")
    if worldPlayers then for _,rig in ipairs(worldPlayers:QueryDescendants("Model")) do
     if rig~=player.Character and (rig:GetAttribute("IsClone") or rig:GetAttribute("Clone") or rig.Name:lower():find("clone",1,true)) then
      for _,part in ipairs(rig:QueryDescendants("BasePart")) do patch(part,"LocalTransparencyModifier",1) end
     end
    end end
   end
  end
  for object,category in pairs(worldObjects) do
   local name=object.Name:lower()
   if object.Parent and ((state.WalkablePuddles and name:find("puddle",1,true)) or (state.DisableKillerDoors and name:find("door",1,true))) then
    if object:IsA("BasePart") then patch(object,"CanCollide",false) else for _,part in ipairs(object:QueryDescendants("BasePart")) do patch(part,"CanCollide",false) end end
   end
   if object.Parent and state.HideFakeGenerators and name:find("fake",1,true) then
    if object:IsA("BasePart") then patch(object,"LocalTransparencyModifier",1) else for _,part in ipairs(object:QueryDescendants("BasePart")) do patch(part,"LocalTransparencyModifier",1) end end
   end
  end
 end
 local effects=setmetatable({},{__mode="k"})
 for _,o in ipairs(workspace:QueryDescendants("ParticleEmitter, Trail, Beam")) do effects[o]=true end
 connect(workspace.DescendantAdded,function(o)if o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Beam") then effects[o]=true end end)
 local function runAbilities(actor,h,root)
  if not actor or not activeInput() then return end
  local target=m:ChooseTarget(false,false);local _,targetRoot=alive(target)
  local distance=targetRoot and (targetRoot.Position-root.Position).Magnitude or math.huge
  if state.AutoM1 and distance<=(state.AttackRange or 8) then
   for name,ability in pairs(actor.Behavior and actor.Behavior.Abilities or {}) do if type(ability)=="table" and ability.KeybindType=="MainAbility" then if sendAbility(actor,name) then break end end end
  end
  local enemy,enemyDistance=threat(root)
  for _,def in ipairs(schemas) do
   if def.Ability and state[def.Key] and actor.ActorName==def.Actor then
    local mode=def.AbilityMode;local permitted=distance<=(state.AbilityRange or 14)
    if mode=="utility" then permitted=true
    elseif mode=="heal" then permitted=h.Health<h.MaxHealth*.8
    elseif mode=="safeheal" then permitted=h.Health<h.MaxHealth*.8 and enemyDistance>45
    elseif mode=="threat" then permitted=enemyDistance<=(state.AbilityRange or 14)
    elseif mode=="support" then
     local friend=m:ChooseTarget(false,true);local _,friendRoot=alive(friend)
     permitted=friendRoot and (friendRoot.Position-root.Position).Magnitude<=(state.AbilityRange or 14)
     if permitted then desiredAim=prediction(friend) end
    elseif mode=="backstab" then
     local delta=targetRoot and root.Position-targetRoot.Position
     permitted=permitted and delta and delta.Magnitude>.01 and targetRoot.CFrame.LookVector:Dot(delta.Unit)<-.5
    elseif mode=="skate" then permitted=not (actor.State and actor.State.isSkating)
    end
    if permitted then sendAbility(actor,def.Ability) end
   end
  end
  if actor.ActorName=="Veeronica" then
   local skating=actor.State and actor.State.isSkating
   if state.AutoFarmSk8 and not skating then sendAbility(actor,"Sk8") end
   local highlight=actor.Instances and actor.Instances.Sk8Highlight
   if (state.AutoTrick or state.AutoFarmSk8) and skating and highlight and highlight.Adornee==actor.Rig then sendKey(Enum.KeyCode.Space) end
   if state.AutoFarmSk8 and skating then
    local spray=actor.State.ClosestSpray
    local center=typeof(spray)=="Instance" and (spray:IsA("BasePart") and spray.Position or spray:IsA("Model") and spray:GetPivot().Position)
    if center then
     local targetPosition=center+Vector3.new(math.cos(clock()*.6)*5,0,math.sin(clock()*.6)*5)
     local delta=Vector3.new(targetPosition.X-root.Position.X,0,targetPosition.Z-root.Position.Z)
     if delta.Magnitude>.1 and workspace.CurrentCamera then skateVector=workspace.CurrentCamera.CFrame:VectorToObjectSpace(delta.Unit) end
     if not controls then
      local ps=player:FindFirstChild("PlayerScripts");local module=ps and ps:FindFirstChild("PlayerModule")
      if module then local ok,result=pcall(require,module);if ok then controls=result:GetControls() end end
     end
     if controls and type(controls.GetMoveVector)=="function" then
      if not skateGetter then skateGetter=function()return skateVector or Vector3.zero end end
      patch(controls,"GetMoveVector",skateGetter)
     end
    end
   end
  end
  if enemy and enemyDistance<=(state.DodgeRadius or 14) and attacking(enemy) then
   local _,enemyRoot=alive(enemy.Rig)
   if enemyRoot then
    local toward=root.Position-enemyRoot.Position
    if toward.Magnitude>.01 and enemyRoot.CFrame.LookVector:Dot(toward.Unit)>.1 and visible(enemy.Rig,enemyRoot.Position) then
     if state.ThreatWarning and clock()-lastWarning>1 then status("Suite","Incoming attack: "..tostring(enemy.ActorName));if ctx.Notify then ctx.Notify("Incoming "..tostring(enemy.ActorName).." attack") end;lastWarning=clock() end
     if state.AutoDodge and not state.AutoPlay and clock()-lastDodge>.8 then
      local flat=Vector3.new(toward.X,0,toward.Z)
      if flat.Magnitude>.01 then h:MoveTo(root.Position+flat.Unit*9);lastDodge=clock() end
     end
    end
   end
  end
  if state.AntiBackstab and enemyDistance<=(state.BackstabRadius or 8) then
   if enemy then
    local _,r=alive(enemy.Rig)
    if r then local delta=r.Position-root.Position;if delta.Magnitude>.01 and root.CFrame.LookVector:Dot(delta.Unit)<0 then root.CFrame=CFrame.lookAt(root.Position,Vector3.new(r.Position.X,root.Position.Y,r.Position.Z)) end end
   end
  end
  if state.BodyBlock and not state.AutoPlay and targetRoot and clock()-lastDodge>1 then
   bodyOwner=h
   h:MoveTo(targetRoot.Position+targetRoot.AssemblyLinearVelocity*(state.BodyBlockPrediction or .25))
  elseif bodyOwner then
   local _,r=alive(player.Character);if r and bodyOwner.Parent then bodyOwner:MoveTo(r.Position) end
   bodyOwner=nil
  end
 end
 function m:Step()
  if self.Destroyed then return end
  epoch+=1
  local h,root=alive(player.Character);local actor=localActor()
  local enabled,support,automaticAim=actorAiming(actor)
  desiredAim=nil
  if enabled and activeInput() then m.Target=self:ChooseTarget(true,support);desiredAim=prediction(m.Target) else m.Target=nil end
  if mouseModule and desiredAim and (state.SilentAim or automaticAim) then
   if not mouseWrapper then mouseWrapper=function(self,...)
    if not m.Destroyed and desiredAim and activeInput() then return desiredAim end
    return originalMouse(self,...)
   end end
   patch(mouseModule,"GetMousePos",mouseWrapper)
  end
  applyConfig(actor)
  applyStamina(actor,h,root)
  suppressStatuses()
  applyMisc(actor,h,root)
  self:TickQTE()
  if sound then sound.Volume=state.MusicVolume or .4;sound.PlaybackSpeed=state.MusicSpeed or 1;sound.Looped=state.MusicLoop==true end
  if animation then animation:AdjustSpeed(state.AnimationSpeed or 1) end
  if state.LowEffects then for object in pairs(effects) do if object.Parent then patch(object,"Enabled",false) else effects[object]=nil end end end
  self:RefreshESP();pickup()
  if h and root then runAbilities(actor,h,root) end
  prune(false)
 end
 local function restoreCamera()
  if lastCamera and cameraOriginal and cameraWritten then pcall(function()if math.abs(lastCamera.FieldOfView-cameraWritten)<.001 then lastCamera.FieldOfView=cameraOriginal end end) end
  lastCamera=nil;cameraOriginal=nil;cameraWritten=nil
 end
 local function render(dt)
  if m.Destroyed then return end
  local camera=workspace.CurrentCamera
  if not camera then return end
  if state.CustomFOV then
   if lastCamera~=camera then restoreCamera();lastCamera=camera;cameraOriginal=camera.FieldOfView end
   camera.FieldOfView=state.FOVValue or 85;cameraWritten=camera.FieldOfView
  else restoreCamera() end
  local actor=localActor();local enabled=actorAiming(actor)
  local h,root=alive(player.Character)
  if state.Flight and root then
   if flightRoot~=root then
    if flightVelocity then flightVelocity:Destroy() end
    if flightAttachment then flightAttachment:Destroy() end
    flightRoot=root
    flightAttachment=Instance.new("Attachment");flightAttachment.Name="AllenFlightAttachment";flightAttachment.Parent=root
    flightVelocity=Instance.new("LinearVelocity");flightVelocity.Name="AllenFlightVelocity";flightVelocity.Attachment0=flightAttachment
    flightVelocity.RelativeTo=Enum.ActuatorRelativeTo.World;flightVelocity.MaxForce=math.max(100000,root.AssemblyMass*10000);flightVelocity.Parent=root
   end
   local movement=Vector3.zero
   if activeInput() then
   if UIS:IsKeyDown(Enum.KeyCode.W) then movement+=camera.CFrame.LookVector end
   if UIS:IsKeyDown(Enum.KeyCode.S) then movement-=camera.CFrame.LookVector end
   if UIS:IsKeyDown(Enum.KeyCode.D) then movement+=camera.CFrame.RightVector end
   if UIS:IsKeyDown(Enum.KeyCode.A) then movement-=camera.CFrame.RightVector end
   if UIS:IsKeyDown(Enum.KeyCode.Space) then movement+=Vector3.yAxis end
   if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then movement-=Vector3.yAxis end
   end
   flightVelocity.VectorVelocity=movement.Magnitude>0 and movement.Unit*(state.FlightSpeed or 30) or Vector3.zero
  elseif flightRoot then
   if flightVelocity then flightVelocity:Destroy();flightVelocity=nil end
   if flightAttachment then flightAttachment:Destroy();flightAttachment=nil end
   flightRoot=nil
  end
  local shouldAim=enabled and desiredAim and activeInput() and (not state.AimOnAttack or clock()<aimUntil)
  if shouldAim and (state.AimBot or enabled and not state.SilentAim) then
   local method=state.AimMethod or "Camera"
   if method:find("Camera",1,true) then
    camera.CFrame=camera.CFrame:Lerp(CFrame.lookAt(camera.CFrame.Position,desiredAim),1-math.exp(-(state.AimSmoothness or 15)*dt))
   end
   if root and method:find("Root",1,true) then
    local target=Vector3.new(desiredAim.X,root.Position.Y,desiredAim.Z)
    if (target-root.Position).Magnitude>.01 then root.CFrame=CFrame.lookAt(root.Position,target) end
   end
  end
  if state.Spin and root and activeInput() then root.CFrame*=CFrame.Angles(0,math.rad(state.SpinSpeed or 360)*dt,0) end
  if not fovRing then
   fovRing=Instance.new("Frame");fovRing.Name="AimFOV";fovRing.AnchorPoint=Vector2.new(.5,.5);fovRing.Position=UDim2.fromScale(.5,.5)
   fovRing.BackgroundTransparency=1;fovRing.Parent=visualGui
   local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(1,0);corner.Parent=fovRing
   local stroke=Instance.new("UIStroke");stroke.Color=Color3.fromRGB(123,140,255);stroke.Transparency=.25;stroke.Parent=fovRing
  end
  fovRing.Visible=state.ShowAimFOV==true;fovRing.Size=UDim2.fromOffset((state.AimFOV or 150)*2,(state.AimFOV or 150)*2)
  if state.AttackVisualizer and root then
   if not visualBox then visualBox=Instance.new("BoxHandleAdornment");visualBox.Name="AllenAttackVisualizer";visualBox.AlwaysOnTop=true;visualBox.ZIndex=2;visualBox.Transparency=.8;visualBox.Color3=Color3.fromRGB(123,140,255);visualBox.Parent=visualGui end
   visualBox.Adornee=root;visualBox.Visible=true
   visualBox.Size=Vector3.new(state.VisualWidth or 5,state.VisualHeight or 6,state.VisualLength or 8)
   visualBox.CFrame=CFrame.new(0,0,-(state.VisualLength or 8)/2)
  elseif visualBox then visualBox.Visible=false end
  if not overlay then
   overlay=Instance.new("TextLabel");overlay.Name="AllenStats";overlay.Position=UDim2.fromOffset(12,80);overlay.Size=UDim2.fromOffset(280,78)
   overlay.BackgroundColor3=Color3.fromRGB(10,12,16);overlay.BackgroundTransparency=.2;overlay.Font=Enum.Font.GothamMedium;overlay.TextSize=12
   overlay.TextColor3=Color3.new(1,1,1);overlay.TextXAlignment=Enum.TextXAlignment.Left;overlay.Parent=visualGui
   local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,8);corner.Parent=overlay
  end
  overlay.Visible=state.StatsOverlay==true
  if overlay.Visible then overlay.Text=string.format("  %s\n  HP %s  |  Stamina %s / %s\n  Native ability requests: %d",actor and actor.ActorName or "Spectating",h and math.floor(h.Health) or "--",sprint and math.floor(sprint.Stamina or 0) or "--",sprint and sprint.MaxStamina or "--",m.Requests) end
 end
 function m:Action(key)
  if self.Destroyed then return end
  local h,root=alive(player.Character)
  if key=="UseAbility" then
   assert(sendAbility(localActor(),tostring(state.AbilityName)),"Ability unavailable, cooling down, or input paused");return
  elseif key=="RecommendedStamina" then
   for _,role in ipairs({"Survivor","Killer"}) do for _,field in ipairs({"MaxStamina","StaminaGain","StaminaLoss","SprintSpeed"}) do ctx.Set(role..field.."On",false) end;ctx.Set(role.."SpeedBoost",0) end
   ctx.Set("ManageSprint",true);ctx.Set("SprintStopPercent",15);return
  elseif key=="ResetStamina" then
   for _,role in ipairs({"Survivor","Killer"}) do for _,field in ipairs({"MaxStamina","StaminaGain","StaminaLoss","SprintSpeed"}) do ctx.Set(role..field.."On",false) end;ctx.Set(role.."SpeedBoost",0) end
   ctx.Set("ManageSprint",false);ctx.Set("NoStaminaPenalty",false);return
  elseif key=="PlayMusic" then
   local id=tostring(state.MusicId):match("%d+");assert(id,"Enter an audio asset ID")
   if sound then sound:Destroy() end
   sound=Instance.new("Sound");sound.Name="AllenLocalMusic";sound.SoundId="rbxassetid://"..id;sound.Volume=state.MusicVolume or .4
   sound.PlaybackSpeed=state.MusicSpeed or 1;sound.Looped=state.MusicLoop==true;sound.Parent=game:GetService("SoundService");sound:Play();return
  elseif key=="StopMusic" then if sound then sound:Destroy();sound=nil end;return
  elseif key=="StopAnimation" then if animation then animation:Stop(.1);animation:Destroy();animation=nil end;return
  elseif key=="Rejoin" then Teleport:TeleportToPlaceInstance(game.PlaceId,game.JobId,player);return
  elseif key=="ServerHop" then
   local data=Http:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
   for _,server in ipairs(data.data or {}) do if server.id~=game.JobId and server.playing<server.maxPlayers then Teleport:TeleportToPlaceInstance(game.PlaceId,server.id,player);return end end
   error("No other available public server was returned")
  end
  assert(h and root,"Wait for a living character")
  if key=="SavePosition" then savedPosition=root.CFrame
  elseif key=="ReturnSpawn" then assert(savedPosition,"Save a position first");root.CFrame=savedPosition
  elseif key=="ResetCharacter" then h.Health=0
  elseif key=="Sit" then h.Sit=true
  elseif key=="PlayAnimation" then
   local id=tostring(state.AnimationId):match("%d+");assert(id,"Enter an animation asset ID")
   local animator=h:FindFirstChildOfClass("Animator");assert(animator,"Animator unavailable")
   if animation then animation:Stop(.1);animation:Destroy() end
   local asset=Instance.new("Animation");asset.AnimationId="rbxassetid://"..id
   animation=animator:LoadAnimation(asset);asset:Destroy();animation.Priority=Enum.AnimationPriority[state.AnimationPriority or "Action"]
   animation.Looped=true;animation:Play(.1);animation:AdjustSpeed(state.AnimationSpeed or 1)
  elseif key=="TeleportPlayerNow" then
   local name=tostring(state.TeleportPlayer or ""):lower();assert(name~="","Enter a username")
   for _,p in ipairs(Players:GetPlayers()) do if p.Name:lower():sub(1,#name)==name then local _,r=alive(p.Character);assert(r,"Target character unavailable");root.CFrame=r.CFrame*CFrame.new(0,0,4);return end end
   error("No matching player")
  elseif key=="NearestGenerator" then
   local adapter=ctx.GetGenerators and ctx.GetGenerators();assert(adapter,"Generator adapter unavailable")
   local best,dist=nil,math.huge
   for _,desc in ipairs(adapter:Scan()) do if not desc.Completed then local d=(desc.Position-root.Position).Magnitude;if d<dist then best,dist=desc,d end end end
   assert(best,"No incomplete generator");root.CFrame=CFrame.new(best.InteractionPosition or best.Position+Vector3.new(0,3,0))
  elseif key=="NearestCola" or key=="NearestMedkit" or key=="NearestGear" then
   local search=key=="NearestGear" and "gear" or key=="NearestMedkit" and "medkit" or "cola"
   local best,distance=nil,math.huge
   for _,item in ipairs(m.Inventory) do if item.Object.Name:lower():find(search,1,true) and item.Distance<distance then best,distance=item,item.Distance end end
   assert(best,"No matching spawned pickup");root.CFrame=CFrame.new(best.Part.Position+Vector3.new(0,3,0))
  end
 end
 connect(player.Idled,function()
  if state.AntiAFK then
   local user=game:GetService("VirtualUser");pcall(function()user:CaptureController();user:ClickButton2(Vector2.zero)end)
  end
 end)
 connect(UIS.InputBegan,function(input,processed)
  if processed or UIS:GetFocusedTextBox() then return end
  if input.UserInputType==Enum.UserInputType.MouseButton1 then aimUntil=clock()+(state.AimLockTime or .6) end
  if input.KeyCode==Enum.KeyCode.LeftShift and state.ToggleSprint and activeInput() then
   local movement=ctx.GetMovement and ctx.GetMovement();if movement and sprint then movement:SetSprint(not sprint.IsSprinting) end
  end
 end)
 local bindName="AllenIndependentSuite_"..tostring({})
 Run:BindToRenderStep(bindName,Enum.RenderPriority.Camera.Value+3,function(dt)
  local ok,err=pcall(render,dt);if not ok then m.LastError=tostring(err);status("Suite",err) end
 end)
 local elapsed=0
 connect(Run.Heartbeat,function(dt)
  elapsed+=dt;if elapsed<.2 then return end;elapsed=0
  local ok,err=pcall(m.Step,m)
  if not ok then m.LastError=tostring(err);status("Suite",err) end
 end)
 function m:Destroy()
  if self.Destroyed then return end
  self.Destroyed=true
  Run:UnbindFromRenderStep(bindName)
  for _,c in ipairs(connections) do c:Disconnect() end
  local input=game:GetService("VirtualInputManager")
  for key in pairs(heldKeys) do pcall(input.SendKeyEvent,input,false,key,false,game) end
  if lastDevice and device then
   local records=patches[device];local r=records and records.Value
   if r and network then pcall(network.FireServerConnection,network,"SetDevice","REMOTE_EVENT",r.Original) end
  end
  prune(true);restoreCamera()
  if animation then pcall(animation.Stop,animation,.1);animation:Destroy() end
  if sound then sound:Destroy() end
  if flightVelocity then flightVelocity:Destroy() end
  if flightAttachment then flightAttachment:Destroy() end
  if bodyOwner and bodyOwner.Parent then local _,root=alive(player.Character);if root then bodyOwner:MoveTo(root.Position) end end
  markerRoot:Destroy();visualGui:Destroy()
  table.clear(self.Markers)
 end
 m:Step()
 return m
end

end)()

local UIFactory=(function()
-- Allen's native UI layer: one control tree, responsive grid and library views.
return function(ctx)
 local app,C=ctx.App,ctx.Palette
 local make,label,button,connect=ctx.Make,ctx.Label,ctx.Button,ctx.Connect
 local function round(object,radius)ctx.Round(object,radius);return object end
 local panel,body,header,rail=ctx.Panel,ctx.Body,ctx.Header,ctx.Rail
 local library=ctx.Pages.Library
 local ui={Destroyed=false,Decorations={},Navigation={},Columns=1}
 local old={};for key,value in pairs(C) do old[key]=value end
 local palette={BG=Color3.fromRGB(12,14,22),Panel=Color3.fromRGB(19,22,33),Hover=Color3.fromRGB(34,38,56),
  Line=Color3.fromRGB(43,49,70),Text=Color3.fromRGB(240,243,252),Muted=Color3.fromRGB(155,166,189),
  Accent=Color3.fromRGB(145,125,255),Green=Color3.fromRGB(83,222,174),Warning=Color3.fromRGB(255,197,113)}
 for key,value in pairs(palette) do C[key]=value end
 for _,object in ipairs(ctx.Gui:QueryDescendants("GuiObject, UIStroke")) do
  for key,value in pairs(old) do
   if palette[key] then
    if object:IsA("GuiObject") and object.BackgroundColor3==value then object.BackgroundColor3=palette[key] end
    if (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) and object.TextColor3==value then object.TextColor3=palette[key] end
    if object:IsA("UIStroke") and object.Color==value then object.Color=palette[key] end
   end
  end
 end
 round(panel,18)
 local shadow=round(make("Frame",{Name="WindowShadow",BackgroundColor3=Color3.new(),BackgroundTransparency=.48,BorderSizePixel=0,ZIndex=0},ctx.Gui),22)
 local function shadowLayout()
  shadow.Position=panel.Position+UDim2.fromOffset(-6,8);shadow.Size=panel.Size+UDim2.fromOffset(12,8);shadow.Visible=panel.Visible
 end
 connect(panel:GetPropertyChangedSignal("Position"),shadowLayout)
 connect(panel:GetPropertyChangedSignal("Size"),shadowLayout)
 connect(panel:GetPropertyChangedSignal("Visible"),shadowLayout)
 shadowLayout()
 local logo=round(make("Frame",{Position=UDim2.fromOffset(16,13),Size=UDim2.fromOffset(34,34),BackgroundColor3=C.Accent,BorderSizePixel=0},header),10)
 local logoText=label(logo,"AS",UDim2.new(),UDim2.fromScale(1,1),14,Color3.new(1,1,1));logoText.Font=Enum.Font.GothamBold;logoText.TextXAlignment=Enum.TextXAlignment.Center
 local accentLine=make("Frame",{Size=UDim2.new(1,-32,0,2),Position=UDim2.fromOffset(16,0),BackgroundColor3=C.Accent,BorderSizePixel=0},header)
 make("UIGradient",{Color=ColorSequence.new(C.Accent,Color3.fromRGB(85,211,205))},accentLine)
 local subtitleLabel
 for _,text in ipairs(header:QueryDescendants("TextLabel")) do
  if text.Text=="Allens Forsaken Script" then text.Position=UDim2.fromOffset(62,11);text.Text="ALLEN / FORSAKEN";text.Font=Enum.Font.GothamBold;text.TextSize=17;text.Size=UDim2.new(1,-230,0,22)
  elseif text.Text:find("SURVIVOR AUTOMATION",1,true) then subtitleLabel=text;text.Position=UDim2.fromOffset(63,34);text.Text="FEATURE LIBRARY";text.TextSize=10;text.TextColor3=C.Muted end
 end
 local ready=round(make("Frame",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-128,0,17),Size=UDim2.fromOffset(88,25),BackgroundColor3=Color3.fromRGB(23,49,43),BorderSizePixel=0},header),12)
 local readyText=label(ready,"● READY",UDim2.new(),UDim2.fromScale(1,1),10,C.Green);readyText.TextXAlignment=Enum.TextXAlignment.Center;readyText.Font=Enum.Font.GothamBold
 ctx.Badge.Visible=false
 rail.BackgroundTransparency=0;rail.BackgroundColor3=C.BG
 for _,child in ipairs(rail:GetChildren()) do if child:IsA("TextLabel") then child.Text="BROWSE LIBRARY";child.TextSize=10;child.Position=UDim2.fromOffset(15,17) end end
 local order={"Library","Favorites","Stamina","Generators","Combat","Survivors","Killers","Aim","Visual","Antis","Items","Teleport","Animations","Music","Fun","Misc","UI","Live","Settings"}
 local categoryRank={};for index,name in ipairs(order)do categoryRank[name]=index end
 local priority={InfiniteStamina=1,ManageSprint=2,NoStaminaPenalty=3,ToggleSprint=4,RecommendedStamina=5,ResetStamina=6,
  AutoFarmGenerators=1,AutoPlay=2,AutoRotateGear=3,GeneratorESP=4,PuzzleStepDelay=5,ThreatRadius=6,FarmDelay=7,
  AutoBlock=1,AutoM1=2,AutoDodge=3,BlockRange=4,AttackRange=5,AbilityRange=6,
  AutoPickup=1,GearESP=2,PickupReach=3,AntiDebuff=1}
 local popular={AutoFarmGenerators=1,InfiniteStamina=2,AutoBlock=3,AutoRotateGear=4,GearESP=5,AutoPlay=6,GeneratorESP=7}
 for index,row in ipairs(app.LibraryRows)do row.DesignOrder=(categoryRank[row.Category] or 99)*1000+(priority[row.Key] or 100+index) end
 local icons={Library="ALL",Favorites="★",Stamina="ST",Generators="GE",Combat="CO",Survivors="SU",Killers="KI",Aim="AI",Visual="VI",Antis="AN",Items="IT",Teleport="TP",Animations="AN",Music="MU",Fun="FX",Misc="MI",UI="UI",Live="LV",Settings="SE"}
 for index,name in ipairs(order) do
  local control=ctx.Tabs[name]
  if control then
   control.Position=UDim2.fromOffset(10,44+(index-1)*44);control.Size=UDim2.fromOffset(170,38)
   control.Text=name;control.TextSize=14;control.TextXAlignment=Enum.TextXAlignment.Left;round(control,9)
   local padding=control:FindFirstChildOfClass("UIPadding") or make("UIPadding",{},control)
   padding.PaddingLeft=UDim.new(0,14);padding.PaddingRight=UDim.new(0,40)
   local icon=label(control,"",UDim2.fromOffset(9,0),UDim2.fromOffset(24,38),10,C.Muted);icon.Visible=false
   local count=label(control,"",UDim2.new(1,-35,0,0),UDim2.fromOffset(28,38),10,C.Muted);count.TextXAlignment=Enum.TextXAlignment.Right
   local line=round(make("Frame",{Position=UDim2.fromOffset(-12,9),Size=UDim2.fromOffset(3,20),BackgroundColor3=C.Accent,BorderSizePixel=0,Visible=false},control),2)
   ui.Navigation[name]={Button=control,Count=count,Icon=icon,Line=line}
  end
 end
 if ctx.Tabs.Automation then ctx.Tabs.Automation.Visible=false end
 rail.CanvasSize=UDim2.fromOffset(0,56+#order*44)
 ctx.Search.TextXAlignment=Enum.TextXAlignment.Left;ctx.Search.TextSize=14
 ctx.Search.PlaceholderText="Search features, characters, or settings"
 round(ctx.Search,11)
 local searchStroke=make("UIStroke",{Color=C.Line,Thickness=1},ctx.Search)
 connect(ctx.Search.Focused,function()searchStroke.Color=C.Accent end)
 connect(ctx.Search.FocusLost,function()searchStroke.Color=C.Line end)
 local shortcut=label(body,"Ctrl K",UDim2.new(),UDim2.fromOffset(50,24),10,C.Muted);shortcut.TextXAlignment=Enum.TextXAlignment.Center
 local clear=button(body,"×",UDim2.new(),UDim2.fromOffset(28,28));clear.BackgroundTransparency=1;clear.TextSize=20
 connect(clear.Activated,function()ctx.Search.Text="";ctx.Search:ReleaseFocus()end)
 local hero=ctx.LibraryHeader;hero.Parent=body;hero.BackgroundTransparency=0;hero.BackgroundColor3=C.Panel;round(hero,13)
 make("UIStroke",{Color=C.Line,Thickness=1},hero)
 ctx.Title.Position=UDim2.fromOffset(18,13);ctx.Title.Size=UDim2.new(1,-36,0,30);ctx.Title.TextSize=24;ctx.Title.Font=Enum.Font.GothamBold
 ctx.Count.Position=UDim2.fromOffset(19,53);ctx.Count.Size=UDim2.new(1,-36,0,20);ctx.Count.TextSize=12;ctx.Count.TextColor3=C.Muted
 local metric=round(make("Frame",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-18,0,18),Size=UDim2.fromOffset(104,25),BackgroundColor3=C.Hover,BorderSizePixel=0},hero),12)
 local metricText=label(metric,"",UDim2.new(),UDim2.fromScale(1,1),10,C.Accent);metricText.TextXAlignment=Enum.TextXAlignment.Center;metricText.Font=Enum.Font.GothamBold
 local filters=make("Frame",{BackgroundTransparency=1},body)
 local chips={}
 app.LibraryFilter="all"
 for index,item in ipairs({{"all","All"},{"enabled","Enabled"},{"favorites","Starred"}}) do
  local key,text=item[1],item[2]
  local control=button(filters,text,UDim2.fromOffset((index-1)*88,0),UDim2.fromOffset(80,30));control.TextSize=12;round(control,9)
  connect(control.Activated,function()app.LibraryFilter=key;ctx.Refresh()end)
  chips[key]=control
 end
 local view=button(filters,"Grid",UDim2.new(1,-72,0,0),UDim2.fromOffset(72,30));view.TextSize=12;round(view,9)
 app.LibraryListView=false
 connect(view.Activated,function()app.LibraryListView=not app.LibraryListView;view.Text=app.LibraryListView and "List" or "Grid";ui:Layout(app.WindowWidth,app.WindowHeight,app.Compact)end)
 for _,layout in ipairs(library:GetChildren()) do if layout:IsA("UIListLayout") then layout:Destroy() end end
 local grid=make("UIGridLayout",{CellPadding=UDim2.fromOffset(12,12),SortOrder=Enum.SortOrder.LayoutOrder,FillDirection=Enum.FillDirection.Horizontal},library)
 library.ScrollBarThickness=4;library.ScrollBarImageColor3=C.Line
 for _,row in ipairs(app.LibraryRows) do
  local aliases={AutoFarmGenerators="auto generator autogen generator farm",AutoPlay="auto generator autoplay navigation pathfinding",InfiniteStamina="infinite stamina inf stamina energy",AutoRotateGear="auto gear rotate",GeneratorESP="generator gen esp",GearESP="gear esp"}
  row.Search=row.Search.." "..(aliases[row.Key] or "")
  if row.Key=="AutoFarmGenerators" or row.Key=="AutoPlay" then
   for _,text in ipairs(row.Card:GetChildren())do
    if text:IsA("TextLabel") and text.Position.Y.Offset<30 and text.Position.X.Scale==0 then text.Text=row.Key=="AutoFarmGenerators" and "Auto Generator" or "Generator Autoplay" end
   end
  end
  round(row.Card,12);row.Card.BackgroundColor3=C.Panel
  for _,text in ipairs(row.Card:QueryDescendants("TextLabel")) do
   if text.TextSize<=11 then text.TextSize=12 end
   if text.TextWrapped and text.Position.Y.Offset>=37 then text.Size=UDim2.new(text.Size.X.Scale,text.Size.X.Offset,0,48);text.TextTruncate=Enum.TextTruncate.AtEnd end
  end
  local footer=label(row.Card,row.Category:upper(),UDim2.fromOffset(40,103),UDim2.new(1,-120,0,15),9,C.Muted)
  local stateLabel=label(row.Card,"",UDim2.new(1,-76,0,103),UDim2.fromOffset(60,15),9,C.Muted);stateLabel.TextXAlignment=Enum.TextXAlignment.Right;stateLabel.Font=Enum.Font.GothamBold
  ui.Decorations[row.Key]={Footer=footer,State=stateLabel}
  local stroke=row.Card:FindFirstChildOfClass("UIStroke")
  if stroke then stroke.Color=C.Line end
  connect(row.Card.MouseEnter,function()if stroke then stroke.Color=Color3.fromRGB(91,84,134)end end)
  connect(row.Card.MouseLeave,function()if stroke then stroke.Color=C.Line end end)
 end
 function ui:Refresh()
  if self.Destroyed then return end
  local count,on,favorites=0,0,0
  local counts={}
  for _,row in ipairs(app.LibraryRows) do
   row.Card.LayoutOrder=app.Tab=="Library" and not ctx.Search.Text:find("%S") and popular[row.Key] or row.DesignOrder
   counts[row.Category]=(counts[row.Category] or 0)+1
   if app.Favorites[row.Key] then favorites+=1 end
   local value=app.State[row.Key]
   if type(value)=="boolean" and value then on+=1 end
   if row.Card.Visible then
    if app.LibraryFilter=="enabled" and not (type(value)=="boolean" and value) then row.Card.Visible=false end
    if app.LibraryFilter=="favorites" and not app.Favorites[row.Key] then row.Card.Visible=false end
   end
   if row.Card.Visible then count+=1 end
   local decoration=self.Decorations[row.Key]
   if decoration then
    local text=type(value)=="boolean" and (value and "ON" or "OFF") or type(value)=="number" and "VALUE" or type(value)=="string" and "SETTING" or "ACTION"
    if decoration.State.Text~=text then decoration.State.Text=text end
    decoration.State.TextColor3=type(value)=="boolean" and value and C.Green or C.Muted
   end
  end
  app.LibraryResultCount=count
  local searching=ctx.Search.Text:find("%S")~=nil
  if subtitleLabel then subtitleLabel.Text=app.Compact and (searching and "SEARCH RESULTS" or (app.Tab or "Library"):upper()) or "FEATURE LIBRARY" end
  ctx.Count.Text=count.." visible  ·  "..#app.LibraryRows.." in your library  ·  "..on.." switches on"
  if count==0 then ctx.Count.Text=app.Tab=="Favorites" and "No favorites yet. Use the star on any control." or "No matches. Try a feature name or a character." end
  if app.Tab=="Live" and not searching then ctx.Count.Text="Your character, automation and adapter diagnostics" end
  metricText.Text=on.." ENABLED"
  clear.Visible=searching;shortcut.Visible=not searching and not app.Compact
  for key,control in pairs(chips) do control.BackgroundColor3=app.LibraryFilter==key and C.Hover or C.Panel;control.TextColor3=app.LibraryFilter==key and C.Accent or C.Muted end
  for name,entry in pairs(self.Navigation) do
   entry.Line.Visible=app.Tab==name
   entry.Icon.TextColor3=app.Tab==name and C.Accent or C.Muted
   local total=name=="Library" and #app.LibraryRows or name=="Favorites" and favorites or counts[name]
   entry.Count.Text=total and tostring(total) or ""
  end
 end
 function ui:Layout(w,h,compact)
  if self.Destroyed then return end
  header.Size=UDim2.new(1,0,0,compact and 44 or 58)
  body.Position=UDim2.fromOffset(0,compact and 44 or 58)
  body.Size=UDim2.new(1,0,1,compact and -44 or -58)
  logo.Visible=not compact
  if subtitleLabel then subtitleLabel.Visible=not compact end
  local side=compact and 0 or 190
  local margin=compact and 12 or 20
  local short=h<490
  rail.Size=UDim2.new(0,190,1,compact and -48 or 0)
  rail.BackgroundTransparency=0;rail.BackgroundColor3=C.BG
  rail.Position=UDim2.fromOffset(0,compact and 60 or 0)
  rail.Size=UDim2.new(0,190,1,compact and -60 or 0)
  local index=0
  for _,name in ipairs(order)do local entry=self.Navigation[name];if entry then
   entry.Button.Position=UDim2.fromOffset(10,44+index*(compact and 48 or 44));entry.Button.Size=UDim2.fromOffset(170,compact and 44 or 38);index+=1
  end end
  rail.CanvasSize=UDim2.fromOffset(0,56+index*(compact and 48 or 44))
  local x=side+margin
  ctx.Search.Position=UDim2.fromOffset(compact and 64 or x,12)
  ctx.Search.Size=UDim2.new(1,-(compact and 78 or side+margin*2),0,40)
  ctx.NavToggle.Position=UDim2.fromOffset(10,12);ctx.NavToggle.Size=UDim2.fromOffset(44,40)
  ctx.Minimize.Size=UDim2.fromOffset(compact and 40 or 30,compact and 40 or 30)
  ctx.Close.Size=ctx.Minimize.Size
  ctx.Minimize.Position=UDim2.new(1,compact and -90 or -84,0,compact and 9 or 13)
  ctx.Close.Position=UDim2.new(1,compact and -46 or -44,0,compact and 9 or 13)
  for _,text in ipairs(header:GetChildren())do if text:IsA("TextLabel") and text.Text=="ALLEN / FORSAKEN" then text.TextSize=compact and (w<340 and 12 or 14) or 17;text.Size=UDim2.new(1,compact and -160 or -230,0,22)end end
  local padding=ctx.Search:FindFirstChildOfClass("UIPadding");if padding then padding.PaddingRight=UDim.new(0,compact and 36 or 66) end
  clear.Size=UDim2.fromOffset(compact and 40 or 28,compact and 40 or 28)
  clear.Position=UDim2.new(1,-margin-(compact and 40 or 32),0,compact and 12 or 18);shortcut.Position=UDim2.new(1,-margin-58,0,20)
  hero.Visible=not compact
  hero.Position=UDim2.fromOffset(x,68);hero.Size=UDim2.new(1,-side-margin*2,0,compact and 72 or 90)
  ctx.Title.TextSize=short and 17 or compact and 21 or 24
  ctx.Title.Position=UDim2.fromOffset(18,short and 7 or 13)
  ctx.Count.Visible=not short
  metric.Visible=not compact and not short
  ready.Visible=w>=650;ctx.Badge.Visible=false
  local filterY=compact and 60 or 170
  filters.Position=UDim2.fromOffset(x,filterY);filters.Size=UDim2.new(1,-side-margin*2,0,compact and 40 or 30)
  local chipWidth=compact and math.min(100,(w-side-margin*2-12)/3) or 80
  for i,key in ipairs({"all","enabled","favorites"})do local control=chips[key];control.Position=UDim2.fromOffset((i-1)*(chipWidth+(compact and 6 or 8)),0);control.Size=UDim2.fromOffset(chipWidth,compact and 40 or 30)end
  view.Visible=not compact
  local top=filterY+(compact and 52 or 44)
  for _,page in pairs(ctx.Pages) do page.Position=UDim2.fromOffset(side,top);page.Size=UDim2.new(1,-side,1,-top-8) end
  local content=w-side-margin*2
  local columns=not app.LibraryListView and content>=650 and 2 or 1
  self.Columns=columns;app.LibraryColumns=columns
  grid.CellSize=UDim2.new(1/columns,columns==2 and -9 or -6,0,compact and 78 or 124)
  for _,row in ipairs(app.LibraryRows)do local d=self.Decorations[row.Key];if d then d.Footer.Position=UDim2.fromOffset(40,compact and 61 or 103);d.State.Position=UDim2.new(1,-76,0,compact and 61 or 103)end end
  local padding=library:FindFirstChildOfClass("UIPadding")
  if padding then padding.PaddingTop=UDim.new(0,compact and 4 or 18);padding.PaddingBottom=UDim.new(0,compact and 10 or 20);padding.PaddingLeft=UDim.new(0,compact and 10 or 20);padding.PaddingRight=UDim.new(0,compact and 10 or 20)end
  for _,row in ipairs(app.LibraryRows)do row.Favorite.Size=UDim2.fromOffset(compact and 40 or 24,compact and 44 or 24);row.Favorite.Position=UDim2.fromOffset(compact and 0 or 7,compact and 0 or 11)end
  if compact then
   ctx.Search.PlaceholderText="Search features..."
   ctx.Minimize.Position=UDim2.new(1,-88,0,2);ctx.Close.Position=UDim2.new(1,-44,0,2)
   for _,text in ipairs(header:GetChildren())do if text:IsA("TextLabel") and text.Text=="ALLEN / FORSAKEN" then text.Position=UDim2.fromOffset(14,11);text.Size=UDim2.new(1,-108,0,22)end end
  else
   ctx.Search.PlaceholderText="Search features, characters, or settings"
   for _,text in ipairs(header:GetChildren())do if text:IsA("TextLabel") and text.Text=="ALLEN / FORSAKEN" then text.Position=UDim2.fromOffset(62,11)end end
  end
  if compact and w>=450 then
   local searchWidth=math.floor(w*.48)
   ctx.Search.Position=UDim2.fromOffset(58,8);ctx.Search.Size=UDim2.fromOffset(searchWidth-64,40)
   ctx.NavToggle.Position=UDim2.fromOffset(8,8)
   filters.Position=UDim2.fromOffset(searchWidth+4,8);filters.Size=UDim2.fromOffset(w-searchWidth-12,40)
   local cw=(w-searchWidth-24)/3
   for i,key in ipairs({"all","enabled","favorites"})do chips[key].Position=UDim2.fromOffset((i-1)*(cw+4),0);chips[key].Size=UDim2.fromOffset(cw,40)end
   for _,page in pairs(ctx.Pages)do page.Position=UDim2.fromOffset(0,56);page.Size=UDim2.new(1,0,1,-64)end
   clear.Visible=false
  end
  for _,row in ipairs(app.LibraryRows)do
   for _,text in ipairs(row.Card:GetChildren())do
    if text:IsA("TextLabel") and text.TextWrapped then
     if not text:GetAttribute("DesktopY") then text:SetAttribute("DesktopY",text.Position.Y.Offset) end
     text.Position=UDim2.new(text.Position.X.Scale,text.Position.X.Offset,0,compact and 34 or text:GetAttribute("DesktopY"))
     text.Size=UDim2.new(text.Size.X.Scale,text.Size.X.Offset,0,compact and 22 or 48)
     text.TextTruncate=Enum.TextTruncate.AtEnd
    end
   end
   local d=self.Decorations[row.Key];if d then d.Footer.Visible=not compact;d.State.Visible=not compact end
  end
  shadowLayout();self:Refresh()
 end
 connect(game:GetService("UserInputService").InputBegan,function(input,processed)
  if input.KeyCode==Enum.KeyCode.K and (game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.LeftControl) or game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.RightControl)) then
   panel.Visible=true;app:SetMinimized(false);ctx.Search:CaptureFocus()
  elseif input.KeyCode==Enum.KeyCode.Escape and ctx.Search:IsFocused() then ctx.Search.Text="";ctx.Search:ReleaseFocus() end
 end)
 function ui:Destroy()self.Destroyed=true;shadow:Destroy()end
 return ui
end

end)()
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
local c = {Version=12,Destroyed=false,Connections={},Tasks={},Tweens={},Bindings={},FeatureStatus={},
    State={AutoFarmGenerators=false,AutoPlay=false,AutoRotateGear=false,AutoBlock=false,InfiniteStamina=false,AntiDebuff=false,
        GeneratorESP=true,GearESP=true,ThreatRadius=45,FarmDelay=0.8,PuzzleStepDelay=0.2,BlockRange=16,FaceThreat=true,Hotkey=Enum.KeyCode.RightShift},
    Generators={},NavStatus="Paused",ManualUntil=0,NavGeneration=0,PathBusy=false,Waypoints=nil,
    NavOwner=nil,WaypointIndex=1,LastPath=0,LastFarm=0,LastScan=0,LastFailure={},LastStuck=0,Ready=false,Focused=true}
for _,def in ipairs(SUITE_FEATURES) do if def.Kind~="action" then c.State[def.Key]=def.Default end end
c.Catalog=SUITE_FEATURES
c.LibraryRows={}
c.Favorites={}
env.AllensForsaken = c
local gui, panel, body, badge, statusLabel, statsLabel, detailsLabel, toast, toastLabel, keyButton
local pages, tabs = {}, {}
local dragging, draggingSlider, captureKey, minimized
local move, combat, generators, suite
local generatorMarkers={}
local gearMarkers={}
c.GearMarkers=gearMarkers
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
    if c.State.AutoPlay and os.clock()>(c.SyntheticInputUntil or 0) then
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
function c:ClearGearESP()
    for model,marker in pairs(gearMarkers) do
        marker.Gui:Destroy();marker.Highlight:Destroy();gearMarkers[model]=nil
    end
end
function c:RefreshGearESP()
    if self.Destroyed or not self.State.GearESP then self:ClearGearESP();return end
    local ch=player.Character
    local root=ch and ch:FindFirstChild("HumanoidRootPart")
    local keep={}
    -- Native gear spawners create pickup Models named Gear. Query only those,
    -- rather than scanning every descendant or touching native highlights.
    for _,model in ipairs(workspace:QueryDescendants("#Gear")) do
        if model:IsA("Model") then
            local part=model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart",true)
            if part then
                keep[model]=true
                local marker=gearMarkers[model]
                if not marker then
                    local billboard=Instance.new("BillboardGui")
                    billboard.Name="AllensGearLabel";billboard.Adornee=part
                    billboard.Size=UDim2.fromOffset(150,40)
                    billboard.StudsOffsetWorldSpace=Vector3.new(0,2.5,0)
                    billboard.AlwaysOnTop=true;billboard.MaxDistance=2500
                    local text=Instance.new("TextLabel")
                    text.Size=UDim2.fromScale(1,1);text.BackgroundColor3=C.BG
                    text.BackgroundTransparency=.2;text.BorderSizePixel=0
                    text.Font=Enum.Font.GothamBold;text.TextSize=12;text.TextColor3=C.Accent
                    text.Parent=billboard
                    local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,6);corner.Parent=text
                    local highlight=Instance.new("Highlight")
                    highlight.Name="AllensGearESP";highlight.Adornee=model
                    highlight.FillColor=C.Accent;highlight.OutlineColor=C.Accent
                    highlight.FillTransparency=.65;highlight.OutlineTransparency=.1
                    highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;highlight.Parent=model
                    billboard.Parent=gui
                    marker={Gui=billboard,Highlight=highlight,Text=text};gearMarkers[model]=marker
                end
                local distance=root and math.floor((part.Position-root.Position).Magnitude)
                marker.Text.Text=distance and ("GEAR  |  "..distance.." studs") or "GEAR"
            end
        end
    end
    for model,marker in pairs(gearMarkers) do
        if not keep[model] then marker.Gui:Destroy();marker.Highlight:Destroy();gearMarkers[model]=nil end
    end
end
function c:Set(key,value)
    if self.Destroyed or self.State[key]==nil then return false end
    local def=SUITE_LOOKUP[key]
    if def then
        if def.Kind=="number" then
            value=tonumber(value)
            if not value or value~=value or math.abs(value)==math.huge then return false end
            value=math.clamp(value,def.Min,def.Max)
        elseif def.Kind=="choice" then
            if not table.find(def.Options,value) then return false end
        elseif def.Kind=="text" then value=tostring(value):sub(1,180)
        elseif def.Kind=="toggle" then value=value==true
        else return false end
    elseif key=="Hotkey" then
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
    if key=="GearESP" then self:RefreshGearESP() end
    if key=="AutoRotateGear" and not value and not self.State.AutoFarmGenerators and not self.State.AutoPlay then safeCall(generators,"Leave") end
    return true
end
function c:Destroy()
    if self.Destroyed then return end
    for key,value in pairs(self.State) do if type(value)=="boolean" then self.State[key]=false end end
    self:StopNavigation()
    self.Destroyed=true
    safeCall(suite,"Destroy");safeCall(generators,"Destroy"); safeCall(combat,"Destroy"); safeCall(move,"Destroy")
    self:ClearGeneratorESP();self:ClearGearESP()
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    for thread in pairs(self.Tasks) do if thread~=coroutine.running() then pcall(task.cancel,thread) end end
    table.clear(self.Tasks)
    for _,t in pairs(self.Tweens) do t:Cancel() end
    table.clear(self.Tweens)
    if self.UI then self.UI:Destroy() end
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
gui.Enabled=false
pcall(function()gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets end)
if type(gethui)=="function" then pcall(function()local mount=gethui();if mount then gui.Parent=mount end end) end
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
local rail=make("ScrollingFrame",{Size=UDim2.new(0,132,1,0),BackgroundTransparency=1,BorderSizePixel=0,
    ScrollBarThickness=3,ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.fromOffset(0,1020)},body)
make("Frame",{Position=UDim2.new(1,-1,0,0),Size=UDim2.new(0,1,1,0),BackgroundColor3=C.Line,BorderSizePixel=0},rail)
label(rail,"WORKSPACE",UDim2.fromOffset(14,22),UDim2.fromOffset(110,16),9,C.Muted)

local refreshLibrary
local function selectTab(name)
    c.Tab=name
    if pages.Library then pages.Library.CanvasPosition=Vector2.zero end
    if c.Search then c.Search.Text="" end
    if refreshLibrary then refreshLibrary();return end
    for n,page in pairs(pages) do page.Visible=n==name end
    for n,b in pairs(tabs) do tween(b,{TextColor3=n==name and C.Accent or C.Muted,
        BackgroundColor3=n==name and C.Hover or C.Panel}) end
end
local allTabs={"Library","Favorites","Automation","Stamina","Visual","Generators","Combat","Survivors","Killers","Aim","Antis","Items","Misc","Teleport","Animations","Music","Fun","UI","Live","Settings"}
rail.CanvasSize=UDim2.fromOffset(0,60+#allTabs*44)
for i,name in ipairs(allTabs) do
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
    round(row,8); stroke(row)
    if page.Name~="Live" then c.LibraryRows[#c.LibraryRows+1]={Card=row,Category=page.Name,Key=name,Order=order} end
    return row
end
local function heading(page,title,subtitle)
    local row=make("Frame",{LayoutOrder=0,Size=UDim2.new(1,0,0,48),BackgroundTransparency=1},page)
    label(row,title,UDim2.new(),UDim2.new(1,0,0,24),20)
    label(row,subtitle,UDim2.fromOffset(0,29),UDim2.new(1,0,0,16),10,C.Muted)
end
local function toggle(page,key,title,description,order)
    local row=card(page,key,72,order)
    local titleLabel=label(row,title,UDim2.fromOffset(14,8),UDim2.new(1,-88,0,28),13)
    titleLabel.TextWrapped=true;titleLabel.TextTruncate=Enum.TextTruncate.None
    local desc=label(row,description,UDim2.fromOffset(14,40),UDim2.new(1,-88,0,26),10,C.Muted)
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
    local titleLabel=label(row,title,UDim2.fromOffset(14,8),UDim2.new(1,-125,0,32),12)
    titleLabel.TextWrapped=true;titleLabel.TextTruncate=Enum.TextTruncate.None
    local readout=label(row,"",UDim2.new(1,-110,0,12),UDim2.fromOffset(96,20),11,C.Accent)
    readout.TextXAlignment=Enum.TextXAlignment.Right
    local bar=make("Frame",{Position=UDim2.new(0,14,0,54),Size=UDim2.new(1,-28,0,4),BackgroundColor3=C.Line,BorderSizePixel=0},row); round(bar,2)
    local fill=make("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=C.Accent,BorderSizePixel=0},bar); round(fill,2)
    local knob=make("Frame",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0,0.5),
        Size=UDim2.fromOffset(12,12),BackgroundColor3=C.Text,BorderSizePixel=0},bar); round(knob,6)
    local hit=make("TextButton",{Size=UDim2.new(1,0,0,28),Position=UDim2.new(0,0,0.5,-14),Text="",BackgroundTransparency=1},bar)
    c.Bindings[key]=function(value)
        local f=(value-lo)/(hi-lo)
        readout.Text=string.format(step<.1 and "%.3f%s" or step<1 and "%.1f%s" or "%.0f%s",value,suffix)
        tween(fill,{Size=UDim2.fromScale(f,1)}); tween(knob,{Position=UDim2.fromScale(f,0.5)})
    end
    local function update(x) c:Set(key,lo+math.floor(math.clamp((x-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1)*(hi-lo)/step+0.5)*step) end
    connect(hit.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            if dragging or draggingSlider then return end
            draggingSlider={Input=input,Update=update}; update(input.Position.X)
        end
    end)
end
local sectionOrder={}
for _,def in ipairs(SUITE_FEATURES) do
    local page=pages[def.Section]
    if not sectionOrder[def.Section] then
        heading(page,def.Section,"Independent Allen Scripts controls; native game rules apply.")
        sectionOrder[def.Section]=0
    end
    sectionOrder[def.Section]+=1
    local order=sectionOrder[def.Section]
    if def.Kind=="toggle" then toggle(page,def.Key,def.Label,def.Help or "",order)
    elseif def.Kind=="number" then slider(page,def.Key,def.Label,def.Min,def.Max,def.Step,"",order)
    elseif def.Kind=="choice" then
        local row=card(page,def.Key,78,order)
        label(row,def.Label,UDim2.fromOffset(14,8),UDim2.new(1,-28,0,22),12)
        local control=button(row,tostring(c.State[def.Key]),UDim2.fromOffset(14,36),UDim2.new(1,-28,0,30))
        c.Bindings[def.Key]=function(value) control.Text=tostring(value) end
        connect(control.Activated,function()
            local i=table.find(def.Options,c.State[def.Key]) or 0
            c:Set(def.Key,def.Options[i%#def.Options+1])
        end)
    elseif def.Kind=="text" then
        local row=card(page,def.Key,84,order)
        label(row,def.Label,UDim2.fromOffset(14,8),UDim2.new(1,-28,0,22),12)
        local control=make("TextBox",{Position=UDim2.fromOffset(14,38),Size=UDim2.new(1,-28,0,30),
            ClearTextOnFocus=false,Text=tostring(c.State[def.Key]),PlaceholderText="Enter value",Font=Enum.Font.Gotham,
            TextSize=12,TextColor3=C.Text,BackgroundColor3=C.BG,BorderSizePixel=0},row)
        round(control,6)
        c.Bindings[def.Key]=function(value) if not control:IsFocused() then control.Text=tostring(value) end end
        connect(control.FocusLost,function() c:Set(def.Key,control.Text) end)
    elseif def.Kind=="action" then
        local actionRow=card(page,def.Key,52,order)
        local control=button(actionRow,def.Label,UDim2.fromOffset(14,9),UDim2.new(1,-28,0,34))
        connect(control.Activated,function()
            if not suite then c:Notify("Feature suite is initializing");return end
            c:Spawn(function()
                local ok,err=pcall(suite.Action,suite,def.Key)
                c:Notify(ok and def.Label.." completed" or tostring(err))
            end)
        end)
    end
    if order%12==0 then task.wait() end
end
local backgroundImage=make("ImageLabel",{Name="CustomBackground",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
    ImageTransparency=.85,ZIndex=0,Visible=false,ScaleType=Enum.ScaleType.Crop},panel)
heading(pages.Automation,"Automation","Automation starts paused. Generator ESP is available below.")
toggle(pages.Automation,"AutoPlay","Survivor autoplay","Walk to generators; retreat from nearby killers.",1)
toggle(pages.Automation,"AutoFarmGenerators","Generator farmer","Work through nearby puzzles one move at a time.",2)
toggle(pages.Automation,"AutoBlock","Guest1337 auto-block","React to supported attack cues; respects cooldown.",3)
toggle(pages.Automation,"InfiniteStamina","Infinite stamina (local)","Remove local drain; preserve ability freeze locks.",4)
toggle(pages.Automation,"AntiDebuff","Local debuff relief","Reduce supported client effects; server effects may persist.",5)
toggle(pages.Automation,"GeneratorESP","Generator ESP","Show progress, completion, distance, and occupancy.",6)
toggle(pages.Automation,"AutoRotateGear","Auto rotate gear","Turn clockwise in an open gear puzzle; requires a gear.",7)
toggle(pages.Automation,"GearESP","Gear ESP","Highlight dropped gears through walls and show distance.",8)
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
            Favorites=c.Favorites,SuiteSettings=(function()local values={} for _,def in ipairs(SUITE_FEATURES) do if def.Kind~="toggle" and def.Kind~="action" then values[def.Key]=c.State[def.Key] end end return values end)(),
            PuzzlePacingVersion=4,PuzzleStepDelay=c.State.PuzzleStepDelay,GeneratorESP=c.State.GeneratorESP,GearESP=c.State.GearESP,BlockRange=c.State.BlockRange,Hotkey=c.State.Hotkey.Name}))
    end)
    c:Notify(ok and "Preferences saved. Automation still starts paused." or tostring(err))
end)
local unload=button(pages.Settings,"Unload and restore",UDim2.new(),UDim2.new(1,0,0,34)); unload.LayoutOrder=7
connect(unload.Activated,function() c:Destroy() end)
for _,item in ipairs({{save,"Save preferences"},{unload,"Unload and restore"}}) do
    local control,key=item[1],item[2]
    local row=card(pages.Settings,key,52,control.LayoutOrder)
    control.Parent=row;control.Position=UDim2.fromOffset(14,9);control.Size=UDim2.new(1,-28,0,34)
end
-- Category, favorites and search reuse the same controls and connections.
local searchBox=make("TextBox",{Name="LibrarySearch",Position=UDim2.fromOffset(146,8),Size=UDim2.new(1,-160,0,34),
    ClearTextOnFocus=false,PlaceholderText="Search all features, characters or settings...",Text="",Font=Enum.Font.Gotham,
    TextSize=13,TextColor3=C.Text,PlaceholderColor3=C.Muted,BackgroundColor3=C.Panel,BorderSizePixel=0},body)
round(searchBox,8)
make("UIPadding",{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)},searchBox)
c.Search=searchBox
function c:SaveFavorites()
    if type(writefile)~="function" or type(readfile)~="function" or type(isfile)~="function" or type(makefolder)~="function" then return false end
    local ok=pcall(function()
        local preferences={}
        if isfile(CONFIG) then preferences=Http:JSONDecode(readfile(CONFIG)) end
        preferences.Favorites=table.clone(self.Favorites)
        if type(isfolder)~="function" or not isfolder("AllensForsaken") then makefolder("AllensForsaken") end
        writefile(CONFIG,Http:JSONEncode(preferences))
    end)
    return ok
end
for _,page in pairs(pages) do page.Position=UDim2.fromOffset(132,48);page.Size=UDim2.new(1,-132,1,-48) end
local libraryHeader=make("Frame",{Size=UDim2.new(1,0,0,58),BackgroundTransparency=1,LayoutOrder=-1000},pages.Library)
local libraryTitle=label(libraryHeader,"Feature Library",UDim2.new(),UDim2.new(1,0,0,26),20)
local libraryCount=label(libraryHeader,"",UDim2.fromOffset(0,32),UDim2.new(1,0,0,20),11,C.Muted)
local function searchable(text) return tostring(text):lower():gsub("[^%w]"," ") end
local organized={AutoPlay="Generators",AutoFarmGenerators="Generators",AutoRotateGear="Generators",GeneratorESP="Generators",
    ThreatRadius="Generators",FarmDelay="Generators",PuzzleStepDelay="Generators",InfiniteStamina="Stamina",
    AutoBlock="Combat",BlockRange="Combat",AntiDebuff="Antis",GearESP="Items"}
for _,row in ipairs(c.LibraryRows) do row.Category=organized[row.Key] or row.Category end
for i,row in ipairs(c.LibraryRows) do
    local terms={row.Category,row.Key}
    local def=SUITE_LOOKUP[row.Key]
    if def then
        local actor=def.Actor or def.ConfigActor
        local aliases={Veeronica="veronica skateboard skating sk8",TwoTime="two time dagger",c00lkidd="coolkid cool kid",JohnDoe="john doe",["1x1x1x1"]="1x4",["007n7"]="007 clone teleport"}
        if actor then terms[#terms+1]=actor;terms[#terms+1]=aliases[actor] or "" end
        for name,alias in pairs(aliases) do if def.Label:find(name,1,true) then terms[#terms+1]=alias end end
    end
    for _,item in ipairs(row.Card:QueryDescendants("TextLabel, TextButton")) do
        if item.Text~="" then terms[#terms+1]=item.Text end
    end
    row.Search=searchable(table.concat(terms," "))
    row.Card.Parent=pages.Library;row.Card.LayoutOrder=i
    for _,child in ipairs(row.Card:GetChildren()) do
        if child:IsA("GuiObject") and child.Position.X.Scale==0 then
            child.Position=UDim2.new(0,child.Position.X.Offset+26,child.Position.Y.Scale,child.Position.Y.Offset)
            if child.Size.X.Scale==1 then child.Size=UDim2.new(1,child.Size.X.Offset-26,child.Size.Y.Scale,child.Size.Y.Offset) end
        end
    end
    local star=button(row.Card,"☆",UDim2.fromOffset(7,11),UDim2.fromOffset(24,24))
    star.BackgroundTransparency=1;star.TextSize=19
    row.Favorite=star
    connect(star.Activated,function()
        c.Favorites[row.Key]=not c.Favorites[row.Key] or nil
        c:SaveFavorites()
        refreshLibrary()
    end)
end
refreshLibrary=function()
    local query=searchable(searchBox.Text)
    local searching=query:find("%S")~=nil
    local selected=c.Tab or "Library"
    if c.Compact then c.NavigationOpen=false;rail.Visible=false end
    pages.Library.Visible=selected~="Live" or searching
    for name,page in pairs(pages) do if name~="Library" then page.Visible=name=="Live" and selected=="Live" and not searching end end
    local count=0
    for _,row in ipairs(c.LibraryRows) do
        local show=searching or selected=="Library" or selected=="Favorites" and c.Favorites[row.Key] or selected==row.Category
        if searching then for word in query:gmatch("%S+") do if not row.Search:find(word,1,true) then show=false;break end end end
        row.Card.Visible=show==true
        if row.Card.Visible then count+=1 end
        row.Favorite.Text=c.Favorites[row.Key] and "★" or "☆"
        row.Favorite.TextColor3=c.Favorites[row.Key] and C.Warning or C.Muted
    end
    libraryTitle.Text=searching and "Search results" or selected=="Library" and "Feature Library" or selected
    libraryCount.Text=count.." controls  /  "..#c.LibraryRows.." total  ·  ☆ to save favorites"
    c.LibraryResultCount=count
    for name,control in pairs(tabs) do
        control.BackgroundColor3=name==selected and C.Hover or C.Panel
        control.TextColor3=name==selected and C.Accent or C.Muted
    end
end
connect(searchBox:GetPropertyChangedSignal("Text"),function()pages.Library.CanvasPosition=Vector2.zero;refreshLibrary()end)
local navToggle=button(body,"≡",UDim2.fromOffset(8,8),UDim2.fromOffset(38,34))
navToggle.Name="LibraryCategories";navToggle.TextSize=22;navToggle.Visible=false
connect(navToggle.Activated,function()c.NavigationOpen=not c.NavigationOpen;rail.Visible=c.NavigationOpen end)
c.Rail=rail
c.RefreshLibrary=refreshLibrary
refreshLibrary()
toast=make("Frame",{Name="Toast",AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,400,1,-24),
    Size=UDim2.fromOffset(360,66),BackgroundColor3=C.Panel,BorderSizePixel=0,ZIndex=10,Visible=false},gui)
round(toast,8); stroke(toast)
toastLabel=label(toast,"",UDim2.fromOffset(14,12),UDim2.new(1,-28,1,-24),11)
toastLabel.TextWrapped=true; toastLabel.TextTruncate=Enum.TextTruncate.None
local function fit()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local available=gui.AbsoluteSize
    local v=c.PreviewViewport or (available.X>200 and available.Y>200 and available or camera.ViewportSize)
    local keyboardOpen=false
    if not c.PreviewViewport and UIS.OnScreenKeyboardVisible and UIS.OnScreenKeyboardPosition.Y>260 then
        keyboardOpen=true
        v=Vector2.new(v.X,math.min(v.Y,UIS.OnScreenKeyboardPosition.Y-12))
    end
    local w=math.min(1040,math.max(280,v.X-24))
    local h=math.min(780,math.max(230,v.Y-80))
    local mobile=c.PreviewViewport~=nil or UIS.TouchEnabled
    if mobile then
        if v.X>v.Y then
            -- Safe GUI dimensions are logical pixels, independent of device resolution.
            w=math.min(1040,math.max(360,math.floor(v.X*.59)),v.X-24)
            h=math.min(780,math.max(280,math.floor(v.Y*.79)),v.Y-24)
        else
            w=math.min(480,math.max(280,math.floor(v.X*.86)),v.X-24)
            h=math.min(720,math.max(360,math.floor(v.Y*.79)),v.Y-24)
        end
    end
    if keyboardOpen then h=math.min(h+180,v.Y-16) end
    c.Compact=w<700 or v.Y<550
    c.WindowWidth=w;c.WindowHeight=h
    c.Compact=v.X<700 or v.Y<550
    scale.Scale=1
    panel.Size=UDim2.fromOffset(w,minimized and 58 or h)
    minimize.Position=UDim2.new(1,-84,0,13)
    close.Position=UDim2.new(1,-44,0,13)
    badge.Position=UDim2.new(1,-180,0,20);badge.Visible=w>=600
    navToggle.Visible=c.Compact
    rail.Visible=not c.Compact or c.NavigationOpen==true
    rail.ZIndex=c.Compact and 30 or 1
    rail.Position=UDim2.fromOffset(0,c.Compact and 48 or 0)
    rail.Size=UDim2.new(0,132,1,c.Compact and -48 or 0)
    rail.BackgroundTransparency=c.Compact and 0 or 1;rail.BackgroundColor3=C.BG
    searchBox.Position=UDim2.fromOffset(c.Compact and 54 or 146,8)
    searchBox.Size=UDim2.new(1,c.Compact and -68 or -160,0,34)
    for _,page in pairs(pages) do
        page.Position=UDim2.fromOffset(c.Compact and 0 or 132,48)
        page.Size=UDim2.new(1,c.Compact and 0 or -132,1,-48)
    end
    if c.UI then c.UI:Layout(w,h,c.Compact) end
    local x,y=panel.Position.X.Offset,panel.Position.Y.Offset
    if c.DragNormalized and c.WindowFitted and not dragging then x=8+c.DragNormalized.X*math.max(0,v.X-w-16);y=8+c.DragNormalized.Y*math.max(0,v.Y-(minimized and 58 or h)-16) end
    if not c.WindowFitted then x=(v.X-w)/2;y=(v.Y-h)/2;c.WindowFitted=true end
    panel.Position=UDim2.fromOffset(math.clamp(x,8,math.max(8,v.X-w-8)),math.clamp(y,8,math.max(8,v.Y-(minimized and 58 or h)-8)))
end
pcall(function()
    connect(UIS:GetPropertyChangedSignal("OnScreenKeyboardVisible"),fit)
    connect(UIS:GetPropertyChangedSignal("OnScreenKeyboardPosition"),fit)
    connect(gui:GetPropertyChangedSignal("AbsoluteSize"),fit)
end)
function c:SetMinimized(value)
    minimized=value==true;body.Visible=not minimized;minimize.Text=minimized and "+" or "-";fit()
end
function c:PreviewLayout(width,height)
    c.PreviewViewport=Vector2.new(width,height);c.WindowFitted=false;fit()
end
function c:RestoreLayout()
    c.PreviewViewport=nil;c.WindowFitted=false;fit()
end
connect(minimize.Activated,function()c:SetMinimized(not minimized)end)
-- One pointer owns a drag. A second finger cannot cancel or hijack it.
local dragSurface=make("TextButton",{Name="WindowDragSurface",Text="",BackgroundTransparency=1,AutoButtonColor=false,
    Position=UDim2.new(),Size=UDim2.new(1,-100,1,0),Active=true,Selectable=false,ZIndex=20},header)
function c:MoveWindowTo(position)
    local camera=workspace.CurrentCamera
    local v=self.PreviewViewport or gui.AbsoluteSize
    if v.X<100 or v.Y<100 then v=camera and camera.ViewportSize or Vector2.new(390,844) end
    local width,height=panel.Size.X.Offset,panel.Size.Y.Offset
    local dx,dy=math.max(0,v.X-width-16),math.max(0,v.Y-height-16)
    local x=math.clamp(position.X,8,8+dx)
    local y=math.clamp(position.Y,8,8+dy)
    panel.Position=UDim2.fromOffset(x,y)
    self.DragNormalized=Vector2.new(dx>0 and (x-8)/dx or 0,dy>0 and (y-8)/dy or 0)
end
function c:BeginWindowDrag(pointer,position,isMouse)
    if dragging or draggingSlider then return false end
    dragging={Pointer=pointer,Mouse=isMouse==true,Origin=position,Position=Vector2.new(panel.Position.X.Offset,panel.Position.Y.Offset)}
    return true
end
function c:UpdateWindowDrag(pointer,position)
    if not dragging or dragging.Pointer~=pointer then return false end
    self:MoveWindowTo(dragging.Position+position-dragging.Origin)
    return true
end
function c:EndWindowDrag(pointer)
    if dragging and dragging.Pointer==pointer then dragging=nil;return true end
    return false
end
connect(dragSurface.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        c:BeginWindowDrag(input,Vector2.new(input.Position.X,input.Position.Y),input.UserInputType==Enum.UserInputType.MouseButton1)
    end
end)
connect(UIS.InputChanged,function(input)
    if draggingSlider then
        local owner=draggingSlider.Input
        if input==owner or owner.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement then draggingSlider.Update(input.Position.X) end
    elseif dragging and (input==dragging.Pointer or dragging.Mouse and input.UserInputType==Enum.UserInputType.MouseMovement) then
        c:UpdateWindowDrag(dragging.Pointer,Vector2.new(input.Position.X,input.Position.Y))
    end
end)
connect(UIS.InputEnded,function(input)
    if dragging and (input==dragging.Pointer or dragging.Mouse and input.UserInputType==Enum.UserInputType.MouseButton1) then c:EndWindowDrag(dragging.Pointer) end
    if draggingSlider and (input==draggingSlider.Input or draggingSlider.Input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1) then draggingSlider=nil end
end)
connect(UIS.InputBegan,function(input,processed)
    if captureKey and input.UserInputType==Enum.UserInputType.Keyboard then
        if input.KeyCode==Enum.KeyCode.Escape then captureKey=false; c.Bindings.Hotkey(c.State.Hotkey)
        elseif c:Set("Hotkey",input.KeyCode) then captureKey=false end
        return
    end
    if processed or UIS:GetFocusedTextBox() or os.clock()<(c.SyntheticInputUntil or 0) then return end
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
    Notify=function(message) c:Notify(message) end,Status=status,
    Schema=SUITE_FEATURES,Set=function(key,value)return c:Set(key,value)end,
    GetMovement=function()return move end,GetGenerators=function()return generators end,
    SyntheticInput=function()c.SyntheticInputUntil=os.clock()+.15 end}
for name,factory in pairs(Factories) do
    local ok,adapter=pcall(factory,ctx)
    if ok then
        if name=="Movement" then move=adapter elseif name=="Combat" then combat=adapter elseif name=="Generators" then generators=adapter elseif name=="Suite" then suite=adapter end
    else status(name,"Unavailable: "..tostring(adapter)); warn("Allens Forsaken "..name..": "..tostring(adapter)) end
end
c.Adapters={Movement=move,Combat=combat,Generators=generators,Suite=suite}
c.UI=UIFactory({App=c,Palette=C,Gui=gui,Panel=panel,Body=body,Header=header,Rail=rail,Tabs=tabs,Pages=pages,
    Search=searchBox,LibraryHeader=libraryHeader,Title=libraryTitle,Count=libraryCount,Badge=badge,NavToggle=navToggle,Minimize=minimize,Close=close,
    Make=make,Label=label,Button=button,Round=round,Connect=connect,Refresh=function()refreshLibrary()end})
local plainRefresh=refreshLibrary
refreshLibrary=function()plainRefresh();if c.UI then c.UI:Refresh()end end
c.RefreshLibrary=refreshLibrary
local originalSet=c.Set
c.Set=function(self,key,value)
    local result=originalSet(self,key,value)
    if result and self.Ready and self.UI then refreshLibrary() end
    return result
end
if type(isfile)=="function" and type(readfile)=="function" then
    pcall(function()
        if isfile(CONFIG) then
            local preferences=Http:JSONDecode(readfile(CONFIG))
            if type(preferences.Favorites)=="table" then
                for _,row in ipairs(c.LibraryRows) do if preferences.Favorites[row.Key]==true then c.Favorites[row.Key]=true end end
            end
            if type(preferences.SuiteSettings)=="table" then
                for key,value in pairs(preferences.SuiteSettings) do
                    local def=SUITE_LOOKUP[key]
                    if def and def.Kind~="toggle" and def.Kind~="action" then c:Set(key,value) end
                end
            end
            if preferences.PuzzlePacingVersion~=4 then preferences.PuzzleStepDelay=math.min(tonumber(preferences.PuzzleStepDelay) or 0.2,0.2) end
            for _,key in ipairs({"ThreatRadius","FarmDelay","PuzzleStepDelay","BlockRange"}) do if preferences[key]~=nil then c:Set(key,preferences[key]) end end
            if type(preferences.GeneratorESP)=="boolean" then c:Set("GeneratorESP",preferences.GeneratorESP) end
            if type(preferences.GearESP)=="boolean" then c:Set("GearESP",preferences.GearESP) end
            if type(preferences.Hotkey)=="string" then local ok,key=pcall(function() return Enum.KeyCode[preferences.Hotkey] end); if ok then c:Set("Hotkey",key) end end
        end
    end)
end
for key,value in pairs(c.State) do if c.Bindings[key] then c.Bindings[key](value) end end
selectTab("Library")
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
        c:RefreshGeneratorESP();c:RefreshGearESP()
        backgroundImage.Visible=c.State.ShowBackgroundImage==true
        local backgroundId=tostring(c.State.BackgroundImage):match("%d+")
        backgroundImage.Image=backgroundId and "rbxassetid://"..backgroundId or ""
        backgroundImage.ImageTransparency=c.State.BackgroundTransparency or .85
        local active=false
        for _,key in ipairs({"AutoPlay","AutoFarmGenerators","AutoRotateGear","AutoBlock","InfiniteStamina","AntiDebuff"}) do active=active or c.State[key] end
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
            "\nSuite: "..tostring(c.FeatureStatus.Suite or "Ready"),
            "\nLast diagnostic: "..tostring(c.FeatureStatus.Error or "None"),
            "\nLocal recovery does not remove server damage or stuns."},"\n")
    end
end)
c.Ready=true
fit();gui.Enabled=true
c:Notify("Ready. All automation is paused. RightShift opens the hub.")
print("ALLENS_FORSAKEN_READY",c.Version,"movement",move~=nil,"combat",combat~=nil,"generators",generators~=nil)
