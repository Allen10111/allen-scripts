-- Hajime Rising | Allen Scripts integration.
-- Hajime Rising | client adapter verified against place 123177480308580, version 160.
-- Single-file release: no HTTP loaders, metamethod hooks, or external UI dependencies.
local App = { Alive = true, S = {}, NotificationQueue = {}, Widgets = {}, Tweens = {} }

do
    local ok, env = false, nil
    if type(getgenv) == "function" then ok, env = pcall(getgenv) end
    App.Environment = ok and type(env) == "table" and env or _G
    local previous = App.Environment.HajimeRisingHub
    if type(previous) == "table" and type(previous.Unload) == "function" then
        pcall(previous.Unload)
    end
    if game.PlaceId ~= 123177480308580 then
        error("Hajime Rising Hub: this place has no verified adapter.", 0)
    end
    for _, name in { "Players", "ReplicatedStorage", "RunService", "TweenService",
        "UserInputService", "HttpService", "CollectionService", "VirtualUser",
        "GuiService", "PathfindingService" } do
        local success, service = pcall(game.GetService, game, name)
        if success then
            if type(cloneref) == "function" then
                local wrapped, reference = pcall(cloneref, service)
                if wrapped then service = reference end
            end
            App.S[name] = service
        end
    end
    App.Player = App.S.Players.LocalPlayer
    if not App.Player then error("Hajime Rising Hub: local player is not ready.", 0) end
    App.Boxing = App.S.ReplicatedStorage:WaitForChild("Boxing", 10)
    if not App.Boxing then error("Hajime Rising Hub: Boxing has not replicated.", 0) end
    App.Remote = App.Boxing:FindFirstChild("BoxingRemote")
    App.QuestRemote = App.Boxing:FindFirstChild("QuestRemote")
    local configModule = App.Boxing:FindFirstChild("BoxingConfig")
    local success, config = pcall(function() return require(configModule) end)
    if not success or type(config) ~= "table" or type(config.Training) ~= "table"
        or type(config.Training.Stations) ~= "table" or not App.Remote
        or not App.Remote:IsA("RemoteEvent") then
        error("Hajime Rising Hub: verified training contract is unavailable.", 0)
    end
    App.GameConfig = config
    local header = App.Boxing:FindFirstChild("StatHeader")
    if header then
        local loaded, result = pcall(require, header)
        if loaded and type(result) == "table" then App.StatHeader = result end
    end
    local menu = App.Boxing:FindFirstChild("MenuState")
    if menu then
        local loaded, result = pcall(require, menu)
        if loaded and type(result) == "table" then App.MenuState = result end
    end
    App.Executor = "Unknown executor"
    if type(identifyexecutor) == "function" then
        local named, name, version = pcall(identifyexecutor)
        if named then App.Executor = tostring(name) .. (version and " " .. tostring(version) or "") end
    end
end

-- Lifecycle ownership: completed timers remove themselves; no persistent polling threads.
do
    local maid = { Items = {}, Threads = {} }
    function maid:Give(item)
        self.Items[#self.Items + 1] = item
        return item
    end
    function maid:Delay(seconds, callback)
        if not App.Alive then return end
        local thread = task.delay(seconds, function()
            self.Threads[coroutine.running()] = nil
            if App.Alive then
                local ok, message = xpcall(callback, debug.traceback)
                if not ok then App.LastError = tostring(message) end
            end
        end)
        self.Threads[thread] = true
        return thread
    end
    function maid:Spawn(callback)
        if not App.Alive then return end
        local thread = coroutine.create(function()
            local ok, message = xpcall(callback, debug.traceback)
            self.Threads[coroutine.running()] = nil
            if not ok and App.Alive then App.LastError = tostring(message) end
        end)
        self.Threads[thread] = true
        task.spawn(thread)
        return thread
    end
    function maid:Cleanup()
        for thread in self.Threads do
            if thread ~= coroutine.running() then pcall(task.cancel, thread) end
        end
        table.clear(self.Threads)
        for i = #self.Items, 1, -1 do
            local item = self.Items[i]
            pcall(function()
                if typeof(item) == "RBXScriptConnection" then item:Disconnect()
                elseif typeof(item) == "Instance" then item:Destroy()
                elseif type(item) == "function" then item()
                elseif type(item) == "thread" then task.cancel(item)
                elseif type(item) == "table" and type(item.Destroy) == "function" then item:Destroy()
                elseif type(item) == "table" and type(item.Disconnect) == "function" then item:Disconnect() end
            end)
        end
        table.clear(self.Items)
    end
    App.Maid = maid
    function App.Tween(object, properties, duration, easingStyle)
        if not App.Alive or not object then return end
        local entries = App.Tweens[object] or {}
        App.Tweens[object] = entries
        local first
        for property, value in properties do
            local old = entries[property]
            if old then old.Connection:Disconnect();old.Tween:Cancel();entries[property]=nil end
            if duration and duration<=0 then pcall(function() object[property]=value end);continue end
            local ok, tween = pcall(App.S.TweenService.Create,App.S.TweenService,object,
                TweenInfo.new(duration or 0.22,easingStyle or Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{[property]=value})
            if not ok then continue end
            local record={Tween=tween}
            record.Connection=tween.Completed:Connect(function()
                record.Connection:Disconnect()
                if entries[property]==record then entries[property]=nil end
                if next(entries)==nil and App.Tweens[object]==entries then App.Tweens[object]=nil end
            end)
            entries[property]=record
            first=first or tween
            tween:Play()
        end
        if next(entries)==nil then App.Tweens[object]=nil end
        return first
    end
    function App.Notify(text, kind, duration)
        App.NotificationQueue[#App.NotificationQueue + 1] = { tostring(text), kind, duration }
    end
    function App.Finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    function App.Send(remote, ...)
        if typeof(remote) ~= "Instance" or not remote.Parent or not remote:IsA("RemoteEvent") then
            return false, "Remote unavailable"
        end
        return pcall(remote.FireServer, remote, ...)
    end
end

-- Flat, versioned configuration. All writes pass through the same atomic binding path.
do
    App.Defaults = {
        TrainingEnabled = false, TrainingMethod = "Bicep Curls", TargetStation = "Nearest free",
        AutoMove = true, MoveMode = "Teleport", AutoEquip = true, QTEAssist = true,
        StartDelay = 1.2, Jitter = 0.01, AutoRest = true, StaminaLow = 25,
        StaminaResume = 85, EnergyFloor = 10, StopAtGoal = true,
        BagPunchInterval = 0.65, BagAlternate = true,
        AutoClaim = false, AntiAFK = false, SpeedEnabled = false, WalkSpeed = 16,
        JumpEnabled = false, JumpPower = 50, FOVEnabled = false, FOV = 70,
        Accent = "#6366F1", ToggleKey = "RightShift", Visible = true, Minimized = false,
        WindowX = 0.5, WindowY = 0.5, ActiveTab = "Dashboard", ProfileName = "default",
        WorldDestination = "Gym · main floor",
    }
    App.State = { Config = table.clone(App.Defaults), Status = "Ready", LastNotice = "",
        Started = os.clock(), Reps = 0, Baseline = {}, Recovering = false, NextStart = 0 }
    local ranges = { StartDelay = {0.5,10}, Jitter = {0,0.05}, StaminaLow = {5,80},
        StaminaResume = {20,100}, EnergyFloor = {0,30}, WalkSpeed = {8,40},
        JumpPower = {20,100}, FOV = {40,100}, WindowX = {0,1}, WindowY = {0,1}, BagPunchInterval = {0.3,2} }
    local tabs = { Dashboard=true, Training=true, ["World & Quests"]=true,
        ["Player & QoL"]=true, ["Configs & Settings"]=true }
    function App.Normalize(raw)
        if type(raw) ~= "table" then return nil, "Configuration must be an object" end
        local result = table.clone(App.Defaults)
        for key, default in App.Defaults do
            local value = raw[key]
            if value == nil then continue end
            if type(value) ~= type(default) then return nil, "Invalid type: " .. key end
            if type(value) == "number" then
                if not App.Finite(value) then return nil, "Invalid number: " .. key end
                local range = ranges[key]
                value = math.clamp(value, range[1], range[2])
            elseif type(value) == "string" and #value > 180 then
                return nil, "Value too long: " .. key
            end
            result[key] = value
        end
        if result.TrainingMethod ~= "Punching bags" and not App.GameConfig.Training.Stations[result.TrainingMethod] then
            return nil, "Unknown training method"
        end
        if result.MoveMode ~= "Teleport" and result.MoveMode ~= "Walk" then return nil, "Unknown movement mode" end
        if not tabs[result.ActiveTab] then return nil, "Unknown tab" end
        if not result.Accent:match("^#%x%x%x%x%x%x$") then return nil, "Use a six-digit accent hex color" end
        result.Accent = string.upper(result.Accent)
        local validKey, keyCode = pcall(function() return Enum.KeyCode[result.ToggleKey] end)
        if not validKey or not keyCode or keyCode == Enum.KeyCode.Unknown then return nil, "Unknown toggle key" end
        if result.StaminaLow >= result.StaminaResume then return nil, "Recovery threshold must exceed pause threshold" end
        return result
    end
    function App.Bind(key, callback)
        App.Widgets[key] = App.Widgets[key] or {}
        table.insert(App.Widgets[key], callback)
        local ok, message = pcall(callback, App.State.Config[key])
        if not ok then App.LastError = tostring(message) end
    end
    function App.TrainingInfo(method)
        if method == "Punching bags" then return App.GameConfig.PunchingBag end
        return App.GameConfig.Training.Stations[method]
    end
    function App.Apply(raw)
        if not App.Alive then return false, "Hub unloaded" end
        local result, message = App.Normalize(raw)
        if not result then return false, message end
        local old = table.clone(App.State.Config)
        local changed = {}
        for key, value in result do if value ~= old[key] then changed[key] = true end end
        for key, value in result do App.State.Config[key] = value end
        for key in changed do
            for _, update in App.Widgets[key] or {} do
                local ok, err = pcall(update, result[key])
                if not ok then App.LastError = tostring(err) end
            end
        end
        if App.Reconcile then App.Reconcile(changed, old) end
        return true
    end
    function App.Set(key, value)
        if App.Defaults[key] == nil then return false, "Unknown setting" end
        local nextConfig = table.clone(App.State.Config)
        nextConfig[key] = value
        if key == "TrainingMethod" then nextConfig.TargetStation = "Nearest free" end
        return App.Apply(nextConfig)
    end
end

-- Profiles remain usable in memory if any executor filesystem capability is absent.
do
    local Store = { Memory = {}, Version = 1, Directory = "HajimeRising/configs", Mode = "Memory" }
    App.ConfigStore = Store
    local fs = type(isfolder)=="function" and type(makefolder)=="function"
        and type(isfile)=="function" and type(readfile)=="function"
        and type(writefile)=="function" and type(listfiles)=="function" and type(delfile)=="function"
    if fs then
        local ok = pcall(function()
            if not isfolder("HajimeRising") then makefolder("HajimeRising") end
            if not isfolder(Store.Directory) then makefolder(Store.Directory) end
        end)
        if ok then Store.Mode = "Disk" end
    end
    local function nameOf(name)
        if type(name) ~= "string" then return nil end
        name = name:match("^%s*(.-)%s*$")
        if #name < 1 or #name > 48 or not name:match("^[%w_%- ]+$") then return nil end
        return name
    end
    local function pathOf(name) return Store.Directory .. "/" .. name .. ".json" end
    local function diskRead(path)
        if Store.Mode ~= "Disk" then return nil end
        local ok, result = pcall(function() if isfile(path) then return readfile(path) end end)
        return ok and type(result) == "string" and result or nil
    end
    local function exists(name)
        if Store.Memory[name] then return true end
        if Store.Mode ~= "Disk" then return false end
        local ok, result = pcall(isfile, pathOf(name))
        return ok and result == true
    end
    local function decode(text)
        if type(text) ~= "string" or #text > 65536 then return nil, "Profile is empty or too large" end
        local ok, data = pcall(App.S.HttpService.JSONDecode, App.S.HttpService, text)
        if not ok or type(data) ~= "table" then return nil, "Invalid profile JSON" end
        local version = data.SchemaVersion or data.Version or 0
        if not App.Finite(version) or version < 0 or version > Store.Version then return nil, "Unsupported profile schema" end
        local config, err = App.Normalize(data.Config or (version == 0 and data))
        return config, err
    end
    function Store.List()
        local names = {}
        for name in Store.Memory do names[name] = true end
        if Store.Mode == "Disk" then
            local ok, paths = pcall(listfiles, Store.Directory)
            if ok and type(paths) == "table" then
                for i, path in paths do
                    if i > 500 then break end
                    if type(path) == "string" then
                        local stem = path:gsub("\\", "/"):match("([^/]+)%.json$")
                        if stem and nameOf(stem) then names[stem] = true end
                    end
                end
            end
        end
        local result = {}
        for name in names do result[#result + 1] = name end
        table.sort(result)
        return result
    end
    function Store.Save(rawName, overwrite)
        local name = nameOf(rawName)
        if not name then return false, "Profile name: 1–48 letters, digits, spaces, _ or -" end
        if exists(name) and not overwrite then return false, "Profile exists; use Overwrite" end
        local ok, text = pcall(App.S.HttpService.JSONEncode, App.S.HttpService,
            { SchemaVersion=Store.Version, PlaceId=game.PlaceId, Config=App.State.Config })
        if not ok then return false, "Profile encoding failed" end
        Store.Memory[name] = text
        if Store.Mode == "Disk" then
            local written = pcall(writefile, pathOf(name), text)
            if not written then return true, "Saved in memory; disk write failed" end
        end
        return true, "Saved " .. name .. (Store.Mode == "Memory" and " in memory" or "")
    end
    function Store.Load(rawName)
        local name = nameOf(rawName)
        if not name then return false, "Invalid profile name" end
        local text = Store.Memory[name] or diskRead(pathOf(name))
        if not text then return false, "Profile not found" end
        local config, err = decode(text)
        if not config then return false, err end
        local ok, message = App.Apply(config)
        if ok then Store.Memory[name] = text end
        return ok, ok and "Loaded " .. name or message
    end
    function Store.GetAutoload()
        if Store.AutoloadLoaded then return Store.Autoload end
        Store.AutoloadLoaded = true
        local text = diskRead("HajimeRising/meta.json")
        if text and #text <= 4096 then
            local ok, data = pcall(App.S.HttpService.JSONDecode, App.S.HttpService, text)
            if ok and type(data) == "table" then Store.Autoload = nameOf(data.Autoload) end
        end
        return Store.Autoload
    end
    function Store.SetAutoload(rawName)
        local name = rawName ~= nil and nameOf(rawName) or nil
        if rawName ~= nil and not name then return false, "Invalid profile name" end
        if name and not exists(name) then return false, "Save this profile first" end
        Store.Autoload, Store.AutoloadLoaded = name, true
        if Store.Mode == "Disk" then
            local ok = pcall(function()
                writefile("HajimeRising/meta.json", App.S.HttpService:JSONEncode({ SchemaVersion=1, Autoload=name or "" }))
            end)
            if not ok then return true, "Auto-load set in memory; disk write failed" end
        end
        return true, name and "Auto-load: " .. name or "Auto-load cleared"
    end
    function Store.Delete(rawName)
        local name = nameOf(rawName)
        if not name or not exists(name) then return false, "Profile not found" end
        if Store.Mode == "Disk" then
            local ok, deleted = pcall(function()
                if isfile(pathOf(name)) then delfile(pathOf(name)) end
                return not isfile(pathOf(name))
            end)
            if not ok or not deleted then return false, "Disk deletion failed" end
        end
        Store.Memory[name] = nil
        if Store.GetAutoload() == name then Store.SetAutoload(nil) end
        return true, "Deleted " .. name
    end
    function Store.Reset()
        local ok, message = App.Apply(table.clone(App.Defaults))
        return ok, ok and "Defaults restored" or message
    end
end

-- The adapter caches real prompt instances. Names alone are ambiguous in this place.
do
    local Adapter = { Stations = {}, World = {}, Dirty = true }
    App.Adapter = Adapter
    local methods = { "Bicep Curls", "Benches", "Squat Racks", "AbCrunches", "JumpRope", "Speed bag" }
    local labels = { ["Bicep Curls"]="Arm strength", Benches="Arm strength",
        ["Squat Racks"]="Leg strength", AbCrunches="Torso endurance", JumpRope="Footwork", ["Speed bag"]="Punch speed" }
    local function coordinates(position)
        return string.format("%.1f, %.1f, %.1f", position.X, position.Y, position.Z)
    end
    function Adapter.Position(prompt)
        local parent = prompt and prompt.Parent
        if parent and parent:IsA("Attachment") then return parent.WorldPosition end
        if parent and parent:IsA("BasePart") then return parent.Position end
        if parent and parent:IsA("Model") then return parent:GetPivot().Position end
    end
    function Adapter.MethodOptions() return table.clone(methods) end
    function Adapter.Refresh()
        local stations, worldTargets = {}, {}
        for _, object in workspace:GetChildren() do
            if not table.find(methods, object.Name) then continue end
            local cf = object:FindFirstChild("CF")
            local att = cf and cf:FindFirstChild("Att")
            local prompt = att and att:FindFirstChild("Prox")
            if not cf or not cf:IsA("BasePart") or not prompt or not prompt:IsA("ProximityPrompt") then continue end
            local position = Adapter.Position(prompt)
            if not position then continue end
            local key = object.Name .. " · " .. coordinates(position)
            stations[#stations + 1] = { Key=key, Method=object.Name, Station=object,
                Anchor=cf, Prompt=prompt, Position=position, Label=labels[object.Name] }
        end
        table.sort(stations, function(a,b) return a.Key < b.Key end)
        local ok, prompts = pcall(workspace.QueryDescendants, workspace, "ProximityPrompt")
        if ok then
            for i, prompt in prompts do
                if i > 1000 then break end
                local position = Adapter.Position(prompt)
                if not position or position.Y < -50 then continue end
                local title = prompt.ObjectText ~= "" and prompt.ObjectText or prompt.ActionText
                if title == "" then title = prompt.Name end
                -- The old origin trainer is a staging template, not a city destination.
                if position.X > -500 and position.X < 500 and position.Z > -500 and position.Z < 500 then continue end
                local key = title .. " · " .. coordinates(position)
                worldTargets[key] = { Key=key, Prompt=prompt, Position=position }
            end
        end
        for _, station in stations do
            if station.Method == "Bicep Curls" then
                worldTargets["Gym · main floor"] = station
                break
            end
        end
        Adapter.Stations, Adapter.World, Adapter.Dirty = stations, worldTargets, false
    end
    function Adapter.StationOptions(method)
        local result = { "Nearest free" }
        for _, target in Adapter.Stations do
            if target.Method == method then result[#result + 1] = target.Key end
        end
        return result
    end
    function Adapter.WorldOptions()
        local result = {}
        for key in Adapter.World do result[#result + 1] = key end
        table.sort(result)
        return result
    end
    function Adapter.ChooseStation()
        local config = App.State.Config
        local character = App.Player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local best, distance
        for _, target in Adapter.Stations do
            if target.Method ~= config.TrainingMethod or not target.Prompt.Parent
                or not target.Prompt.Enabled or not target.Anchor.Parent then continue end
            if config.TargetStation ~= "Nearest free" and config.TargetStation ~= target.Key then continue end
            local current = (target.Position - root.Position).Magnitude
            if not distance or current < distance then best, distance = target, current end
        end
        return best, distance
    end
    Adapter.Refresh()
end

-- Runtime state and property restoration are separate from configuration.
do
    App.MotionGeneration, App.TrainingGeneration = 0, 0
    App.Restore = setmetatable({}, { __mode="k" })
    App.QuestAttempts = {}
    function App.Character()
        local character = App.Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not character or not humanoid or not root or humanoid.Health <= 0 then return end
        return character, humanoid, root
    end
    function App.Stamina()
        local character = App.Player.Character
        local value = character and character:GetAttribute("Stamina")
        local maximum = character and character:GetAttribute("StaminaMax")
        if App.Finite(value) and App.Finite(maximum) and maximum > 0 then
            return math.clamp(value/maximum*100,0,100), value, maximum
        end
    end
    function App.Override(object, property, value)
        local entries = App.Restore[object]
        if not entries then entries={}; App.Restore[object]=entries end
        local entry = entries[property]
        if not entry then entry={ Original=object[property] }; entries[property]=entry end
        object[property] = value
        entry.Last = object[property]
    end
    function App.RestoreProperty(object, property)
        local entries = App.Restore[object]
        local entry = entries and entries[property]
        if not entry then return end
        pcall(function() if object[property] == entry.Last then object[property] = entry.Original end end)
        entries[property] = nil
        if next(entries) == nil then App.Restore[object] = nil end
    end
    function App.RestoreAll()
        local targets = {}
        for object, entries in App.Restore do
            for property in entries do targets[#targets+1]={object,property} end
        end
        for _, target in targets do App.RestoreProperty(target[1], target[2]) end
    end
    function App.CancelMove()
        App.MotionGeneration += 1
        local moving = App.Moving
        App.Moving = nil
        if moving and moving.Character == App.Player.Character and moving.Root.Parent then
            pcall(moving.Humanoid.MoveTo, moving.Humanoid, moving.Root.Position)
        end
        if moving and moving.Thread and moving.Thread ~= coroutine.running() then
            App.Maid.Threads[moving.Thread] = nil
            pcall(task.cancel, moving.Thread)
        end
    end
    function App.Move(target, onArrival)
        App.CancelMove()
        local character, humanoid, root = App.Character()
        if not character then return false end
        local generation = App.MotionGeneration
        local movement = { Character=character, Humanoid=humanoid, Root=root }
        App.Moving = movement
        App.Maid:Delay(24,function()
            if App.Moving==movement then
                App.CancelMove();App.State.Status="Route timed out"
                if onArrival then onArrival(false) end
            end
        end)
        movement.Thread = App.Maid:Spawn(function()
            local function current()
                return App.Alive and App.MotionGeneration == generation and App.Player.Character == character
                    and root.Parent and humanoid.Parent and humanoid.Health > 0
            end
            local position = target.Anchor and (target.Anchor.CFrame*CFrame.new(0,3,1)).Position
                or target.Position + Vector3.new(0,3,0)
            local arrived = false
            if App.State.Config.MoveMode == "Teleport" then
                if current() then character:PivotTo(CFrame.new(position, position + root.CFrame.LookVector)) end
                task.wait(0.45)
                arrived = current() and (root.Position-position).Magnitude < 10
            else
                local waypoints
                local computed = pcall(function()
                    local path = App.S.PathfindingService:CreatePath({AgentCanJump=true,WaypointSpacing=5})
                    path:ComputeAsync(root.Position, position)
                    if path.Status == Enum.PathStatus.Success then waypoints = path:GetWaypoints() end
                    path:Destroy()
                end)
                if not current() then return end
                if not computed or not waypoints or #waypoints > 80 then waypoints = {{Position=position}} end
                local deadline = os.clock()+18
                for _, point in waypoints do
                    if not current() or os.clock() > deadline then break end
                    if point.Action == Enum.PathWaypointAction.Jump then humanoid.Jump=true end
                    humanoid:MoveTo(point.Position)
                    local stepDeadline = math.min(deadline,os.clock()+4)
                    repeat task.wait(0.05)
                    until not current() or os.clock()>=stepDeadline or (root.Position-point.Position).Magnitude<4
                end
                arrived = current() and (root.Position-position).Magnitude < 8
            end
            if not current() then return end
            App.Moving = nil
            if onArrival then onArrival(arrived) end
        end)
        return true
    end
    function App.StopTraining(reason)
        App.TrainingGeneration += 1
        local session = App.Session
        App.Session = nil
        if App.StopBagTraining then App.StopBagTraining(session) end
        local pending = App.PendingStart
        local stopPending = pending and pending.Issued and not pending.Canceled
        if pending and pending.Issued then
            pending.Canceled = true
        else App.PendingStart = nil end
        App.CancelMove()
        if session and session.Owned and session.Kind ~= "Bag" or stopPending then
            if session and session.Held then App.Send(App.Remote,"TrainRelease",session.Held,workspace:GetServerTimeNow()) end
            App.Send(App.Remote,"TrainStop")
            App.AwaitingEnd = os.clock()+4
        end
        App.State.NextStart = os.clock()+App.State.Config.StartDelay
        local equipped=App.EquippedByHub
        App.EquippedByHub=nil
        if equipped and equipped.Character==App.Player.Character and equipped.Tool.Parent==equipped.Character then
            pcall(function()
                local humanoid=equipped.Character:FindFirstChildOfClass("Humanoid")
                if not humanoid then return end
                humanoid:UnequipTools()
                for _,tool in equipped.Previous do
                    if tool.Parent and tool.Parent:IsA("Backpack") then humanoid:EquipTool(tool) end
                end
            end)
        end
        if reason then App.State.Status=reason end
    end
    function App.Travel()
        local target = App.Adapter.World[App.State.Config.WorldDestination]
        if not target then return false, "Destination is not streamed; refresh destinations" end
        if App.State.Config.TrainingEnabled then App.Set("TrainingEnabled",false) end
        if (App.Player:GetAttribute("TrainingUI") or "") ~= "" then
            return false,"Stop the current activity before travelling"
        end
        App.State.Status="Travelling"
        local moving=App.Move(target,function(arrived)
            App.State.Status=arrived and "Destination reached" or "Route blocked"
            App.Notify(App.State.Status,arrived and "success" or "error")
        end)
        if not moving then App.State.Status="Character unavailable" end
        return moving,moving and ("Travelling to " .. App.State.Config.WorldDestination) or "Character unavailable"
    end
    function App.StartTraining(target)
        local character, humanoid, root = App.Character()
        if not character or App.PendingStart then return end
        local generation = App.TrainingGeneration
        local pending = { Target=target, Generation=generation, Deadline=os.clock()+24, Character=character }
        App.PendingStart = pending
        local function current()
            return App.Alive and App.State.Config.TrainingEnabled and App.State.Config.QTEAssist
                and App.TrainingGeneration==generation and App.PendingStart==pending
                and App.Player.Character==character and humanoid.Health>0 and not pending.Canceled
        end
        local function trigger(arrived)
            if not current() then return end
            if not App.CanTrain() or not current() then return end
            if (App.Player:GetAttribute("TrainingUI") or "")~="" then
                App.PendingStart=nil;App.State.Status="Manual activity is already running";return
            end
            if not arrived or not target.Prompt.Parent or not target.Prompt.Enabled then
                App.PendingStart=nil;App.State.Status="Station unavailable";App.State.NextStart=os.clock()+3;return
            end
            local position=App.Adapter.Position(target.Prompt)
            if not position or (root.Position-position).Magnitude>target.Prompt.MaxActivationDistance then
                App.PendingStart=nil;App.State.Status="Move closer to the station";App.State.NextStart=os.clock()+3;return
            end
            pending.Issued=true;pending.Deadline=os.clock()+6
            local ok = pcall(function()
                if type(fireproximityprompt)=="function" then fireproximityprompt(target.Prompt)
                else target.Prompt:InputHoldBegin();target.Prompt:InputHoldEnd() end
            end)
            if not ok then App.PendingStart=nil;App.State.Status="Prompt activation unavailable" end
        end
        App.Maid:Spawn(function()
            if not current() then return end
            local stationConfig=App.GameConfig.Training.Stations[target.Method]
            if stationConfig.NeedsGloves and not character:FindFirstChild("Boxing") then
                if not App.State.Config.AutoEquip then
                    App.PendingStart=nil;App.State.Status="Equip Boxing gloves to train here";return
                end
                local backpack=App.Player:FindFirstChildOfClass("Backpack")
                local tool=backpack and backpack:FindFirstChild("Boxing")
                if not tool or not tool:IsA("Tool") then
                    App.PendingStart=nil;App.State.Status="Boxing tool unavailable";return
                end
                local previous={}
                for _,item in character:GetChildren() do if item:IsA("Tool") then previous[#previous+1]=item end end
                App.EquippedByHub={Tool=tool,Character=character,Previous=previous}
                humanoid:EquipTool(tool)
                task.wait(0.25)
                if not current() then return end
            end
            if not current() then return end
            local position=App.Adapter.Position(target.Prompt)
            if not position then App.PendingStart=nil;return end
            if (root.Position-position).Magnitude <= math.max(1,target.Prompt.MaxActivationDistance-0.5) then
                trigger(true)
            elseif App.State.Config.AutoMove then
                App.State.Status="Moving to " .. target.Method
                App.Move(target,trigger)
            else
                App.PendingStart=nil;App.State.Status="Move closer, or enable Auto Move"
            end
        end)
    end
end

-- Only server-issued sweep IDs are sent back, at observed server-time positions.
do
    function App.OnTrainingEvent(action, data)
        if not App.Alive then return end
        if action == "TrainStart" and type(data)=="table" then
            local pending=App.PendingStart
            if not pending or not pending.Issued or data.Station~=pending.Target.Method then return end
            App.PendingStart=nil
            if pending.Canceled or not App.State.Config.TrainingEnabled
                or pending.Generation~=App.TrainingGeneration then
                App.Send(App.Remote,"TrainStop");App.AwaitingEnd=os.clock()+4;return
            end
            if pending.Character~=App.Player.Character then return end
            App.Session={Owned=true,Generation=App.TrainingGeneration,Character=pending.Character,
                Method=data.Station,Stat=data.Stat,Sub=data.Sub,Sweeps={}}
            App.State.Status="Training · " .. tostring(data.SubName or data.Station)
        elseif action=="TrainSweep" and type(data)=="table" then
            local session=App.Session
            if not session or not session.Owned or session.Kind == "Bag" then return end
            if not App.Finite(data.Id) or data.Id<1 or data.Id%1~=0
                or not App.Finite(data.Start) or not App.Finite(data.Duration)
                or data.Duration<=0 or data.Duration>60 or (data.Dir~=1 and data.Dir~=-1) then return end
            if data.Hold and (not App.Finite(data.ZoneStart) or not App.Finite(data.ZoneEnd)
                or data.ZoneStart<0 or data.ZoneEnd>1 or data.ZoneStart>=data.ZoneEnd) then return end
            if session.Sweeps[data.Id] then return end
            local sweep={Id=data.Id,Start=data.Start,Duration=data.Duration,Hold=data.Hold==true}
            local entry,exit=0.5,nil
            if sweep.Hold then
                entry=data.Dir==-1 and 1-data.ZoneEnd or data.ZoneStart
                exit=data.Dir==-1 and 1-data.ZoneStart or data.ZoneEnd
            end
            local jitter=(math.random()*2-1)*App.State.Config.Jitter
            local limit=sweep.Hold and (exit-entry)*sweep.Duration*0.15 or sweep.Duration*0.015
            jitter=math.clamp(jitter,-limit,limit)
            sweep.PressAt=sweep.Start+sweep.Duration*entry+jitter
            sweep.ReleaseAt=exit and sweep.Start+sweep.Duration*exit+jitter or nil
            session.Sweeps[sweep.Id]=sweep
            for id, previous in session.Sweeps do
                if id < sweep.Id-5 and not (previous.Pressed and not previous.Released and previous.Hold) then
                    session.Sweeps[id]=nil
                end
            end
        elseif action=="TrainResult" and App.Session and App.Session.Kind~="Bag" and type(data)=="table" then
            if data.Missed~=true and App.Finite(data.Gain) then App.State.Reps+=1 end
        elseif action=="TrainEnd" then
            if App.Session and App.Session.Kind=="Bag" then App.AwaitingEnd=nil;return end
            App.Session=nil;App.AwaitingEnd=nil
            if App.PendingStart and App.PendingStart.Canceled then App.PendingStart=nil end
            App.State.NextStart=os.clock()+App.State.Config.StartDelay+math.random()*App.State.Config.Jitter
            App.State.Status=App.State.Recovering and "Recovering stamina" or tostring(data or "Training ended")
        elseif action=="TrainNotice" and type(data)=="string" then
            App.State.LastNotice=data
            if App.PendingStart or App.Session then
                App.State.Status=data;App.Notify(data,"info",4)
            end
        end
    end
    function App.StepSweeps()
        local session=App.Session
        if not session or not session.Owned or not App.State.Config.TrainingEnabled
            or not App.State.Config.QTEAssist or session.Generation~=App.TrainingGeneration
            or session.Character~=App.Player.Character then return end
        local now=workspace:GetServerTimeNow()
        for id,sweep in session.Sweeps do
            if not App.Alive or App.Session~=session then return end
            if not sweep.Pressed and not sweep.Skipped and now>=sweep.PressAt then
                if now>sweep.PressAt+math.min(0.12,sweep.Duration*0.08) or now>sweep.Start+sweep.Duration then
                    sweep.Skipped=true
                else
                    sweep.Pressed=true
                    local sent=App.Send(App.Remote,"TrainPress",id,now)
                    if sent and sweep.Hold then session.Held=id end
                end
            end
            if sweep.Hold and sweep.Pressed and not sweep.Released and now>=sweep.ReleaseAt then
                sweep.Released=true
                App.Send(App.Remote,"TrainRelease",id,now)
                if session.Held==id then session.Held=nil end
            end
        end
    end
    function App.CanTrain()
        local config,state=App.State.Config,App.State
        if not config.TrainingEnabled then return false end
        if not config.QTEAssist and config.TrainingMethod~="Punching bags" then state.Status="QTE assistance disabled";return false end
        local character=App.Character()
        if not character then state.Status="Waiting for character";return false end
        if App.Player:GetAttribute("GameLoaded")~=true then state.Status="Waiting for game loading";return false end
        local percent=App.Stamina()
        if not percent then
            if App.Session then App.StopTraining("Waiting for stamina data") end
            state.Status="Waiting for stamina data";return false
        end
        if percent<=config.StaminaLow and not (App.Session and App.Session.Held) then
            if App.Session or App.PendingStart then App.StopTraining("Recovering stamina") end
            if not config.AutoRest then App.Set("TrainingEnabled",false);state.Status="Paused at stamina threshold";return false end
            state.Recovering=true
        end
        if state.Recovering then
            if percent<config.StaminaResume then state.Status="Recovering stamina";return false end
            state.Recovering=false
        end
        local energy=App.Player:GetAttribute("Energy")
        if config.EnergyFloor>0 and (not App.Finite(energy) or energy<config.EnergyFloor) then
            if App.PendingStart or App.Session and not App.Session.Held then App.StopTraining("Energy low · use food") end
            state.Status="Energy low · use food";return App.Session and App.Session.Held~=nil or false
        end
        if config.StopAtGoal and App.StatHeader and type(App.StatHeader.NoGainReason)=="function" then
            local station=App.TrainingInfo(config.TrainingMethod)
            if type(station)~="table" then state.Status="Training configuration unavailable";return false end
            local ok,reason,title=pcall(App.StatHeader.NoGainReason,station.Stat,station.Sub)
            if ok and reason then
                App.StopTraining(tostring(title or reason));App.Set("TrainingEnabled",false);return false
            end
        end
        return true
    end
    function App.StepTraining()
        if App.State.Config.TrainingMethod=="Punching bags" then
            if App.StepBagTraining then App.StepBagTraining() end
            return
        end
        local now=os.clock()
        local pending=App.PendingStart
        if pending and now>pending.Deadline then
            App.CancelMove();App.PendingStart=nil;App.State.NextStart=now+3
            App.State.Status=pending.Canceled and "Ready" or "Station did not start · retrying"
        end
        if not App.CanTrain() then return end
        if App.Session then App.StepSweeps();return end
        if App.PendingStart or App.Moving or now<App.State.NextStart then return end
        if App.AwaitingEnd then
            if now<App.AwaitingEnd then return end
            App.AwaitingEnd=nil
        end
        local activity=App.Player:GetAttribute("TrainingUI")
        if type(activity)=="string" and activity~="" then App.State.Status="Manual activity · " .. activity;return end
        local character=App.Player.Character
        if character and character:GetAttribute("Training")~=nil then App.State.Status="Waiting for previous session";return end
        local target=App.Adapter.ChooseStation()
        if not target then App.State.Status="No free station · refresh or choose another";App.State.NextStart=now+2;return end
        App.State.NextStart=now+App.State.Config.StartDelay
        App.StartTraining(target)
    end
end

do
    function App.StepQuests()
        if not App.Alive or not App.State.Config.AutoClaim or not App.QuestRemote then return end
        local raw=App.Player:GetAttribute("Quests")
        if type(raw)~="string" or #raw>65536 then return end
        local ok,data=pcall(App.S.HttpService.JSONDecode,App.S.HttpService,raw)
        if not ok or type(data)~="table" then return end
        local resetKey=tostring(data.DailyEnds)..":"..tostring(data.WeeklyEnds)
        if App.QuestResetKey~=resetKey then App.QuestResetKey=resetKey;table.clear(App.QuestAttempts) end
        for _,category in {"Daily","Weekly"} do
            local quests=data[category]
            if type(quests)~="table" then continue end
            for i,quest in quests do
                if type(i)~="number" or i>30 then break end
                if type(quest)~="table" or type(quest.Id)~="string" or #quest.Id>80
                    or quest.Claimed~=false or not App.Finite(quest.P) or not App.Finite(quest.Goal)
                    or quest.Goal<=0 or quest.P<quest.Goal then continue end
                local key=category..":"..quest.Id
                local attempt=App.QuestAttempts[key]
                if attempt and (attempt.Count>=3 or os.clock()-attempt.Time<30) then continue end
                if not App.Alive or not App.State.Config.AutoClaim then return end
                App.QuestAttempts[key]={Count=attempt and attempt.Count+1 or 1,Time=os.clock()}
                App.Send(App.QuestRemote,"Claim",category,quest.Id)
                return
            end
        end
    end
    function App.StepProperties()
        local config=App.State.Config
        local character,humanoid=App.Character()
        local busy=(App.Player:GetAttribute("TrainingUI") or "")~=""
        if App.MenuState and type(App.MenuState.Blocked)=="function" then
            local ok,blocked=pcall(App.MenuState.Blocked)
            busy=busy or ok and blocked==true
        end
        if App.MenuState and type(App.MenuState.IsOpen)=="function" then
            local ok,opened=pcall(App.MenuState.IsOpen)
            busy=busy or ok and opened==true
        end
        -- Controllers may own the camera or character during menus and activities.
        if App.LastHumanoid and App.LastHumanoid~=humanoid then
            for _,prop in {"WalkSpeed","JumpPower","JumpHeight"} do App.RestoreProperty(App.LastHumanoid,prop) end
        end
        App.LastHumanoid=humanoid
        if humanoid then
            if config.SpeedEnabled and not busy and not humanoid.Sit and humanoid.WalkSpeed>0 then
                App.Override(humanoid,"WalkSpeed",config.WalkSpeed)
            else App.RestoreProperty(humanoid,"WalkSpeed") end
            if config.JumpEnabled and not busy and not humanoid.Sit then
                if humanoid.UseJumpPower then
                    App.RestoreProperty(humanoid,"JumpHeight")
                    App.Override(humanoid,"JumpPower",config.JumpPower)
                elseif workspace.Gravity>0 then
                    App.RestoreProperty(humanoid,"JumpPower")
                    App.Override(humanoid,"JumpHeight",config.JumpPower^2/(2*workspace.Gravity))
                end
            else
                App.RestoreProperty(humanoid,"JumpPower");App.RestoreProperty(humanoid,"JumpHeight")
            end
        end
        local camera=workspace.CurrentCamera
        if App.LastCamera and App.LastCamera~=camera then App.RestoreProperty(App.LastCamera,"FieldOfView") end
        App.LastCamera=camera
        if camera then
            if config.FOVEnabled and not busy and camera.CameraType==Enum.CameraType.Custom then App.Override(camera,"FieldOfView",config.FOV)
            else App.RestoreProperty(camera,"FieldOfView") end
        end
    end
    function App.Reconcile(changed)
        if changed.TrainingEnabled or changed.TrainingMethod or changed.TargetStation
            or changed.QTEAssist or changed.MoveMode or changed.AutoMove then
            App.StopTraining(App.State.Config.TrainingEnabled and "Preparing training" or "Ready")
            App.State.Recovering=false
        end
        if changed.AutoRest and not App.State.Config.AutoRest and App.State.Recovering then
            App.State.Recovering=false;App.Set("TrainingEnabled",false)
            App.State.Status="Recovery disabled · training paused"
        end
        if changed.AutoClaim then table.clear(App.QuestAttempts) end
        if changed.SpeedEnabled or changed.JumpEnabled or changed.FOVEnabled then App.StepProperties() end
    end
    function App.GetDashboard()
        local state=App.State
        local percent,stamina,maximum=App.Stamina()
        local elapsed=math.max(os.clock()-state.Started,1)
        local stats={}
        for _,name in {"Power","Speed","Technique","Willpower","Endurance","Stamina"} do
            local value=App.Player:GetAttribute("Stat_"..name)
            if App.Finite(value) and state.Baseline[name]==nil then state.Baseline[name]=value end
            local gain=App.Finite(value) and value-(state.Baseline[name] or value) or 0
            stats[#stats+1]={Name=name,Value=App.Finite(value) and value or nil,Gain=gain,PerMinute=gain*60/elapsed}
        end
        return { Stats=stats,Cash=App.Player:GetAttribute("Cash"),StaminaPercent=percent,Stamina=stamina,
            StaminaMax=maximum,Energy=App.Player:GetAttribute("Energy"),Hunger=App.Player:GetAttribute("Hunger"),
            Thirst=App.Player:GetAttribute("Thirst"),Style=App.Player:GetAttribute("BoxingStyle") or "--",
            Mastery=App.Player:GetAttribute("Stat_Technique_B"),Status=state.Status,Reps=state.Reps,
            Elapsed=elapsed,Rank=App.Player:GetAttribute("RankWillpower"),Executor=App.Executor,
            ProfileMode=App.ConfigStore.Mode,LastNotice=state.LastNotice }
    end
    function App.Unload()
        if not App.Alive then return end
        App.Alive=false
        App.StopTraining()
        App.Maid:Cleanup()
        for object,entries in App.Tweens do
            for _,record in entries do record.Connection:Disconnect();pcall(record.Tween.Cancel,record.Tween) end
            App.Tweens[object]=nil
        end
        App.RestoreAll()
        if App.Gui then pcall(App.Gui.Destroy,App.Gui) end
        table.clear(App.Widgets)
        if App.Environment.HajimeRisingHub==App then App.Environment.HajimeRisingHub=nil end
    end
end


-- Heavy bags use the game's normal punch controller, not the sweep-training protocol.
do
    App.BagMethod = "Punching bags"
    local Adapter = App.Adapter
    local originalRefresh, originalMethods, originalStations = Adapter.Refresh, Adapter.MethodOptions, Adapter.StationOptions
    local inputBus
    local function bagPart(target)
        if not target or not target.Model.Parent or target.Model:GetAttribute("PunchingBag") ~= true then return end
        local part = target.Model:FindFirstChild("PhysicsPart")
        local humanoid = target.Model:FindFirstChildOfClass("Humanoid")
        if part and part:IsA("BasePart") and humanoid and humanoid.Health > 0 then return part end
    end
    local function restOf(part)
        local rest = part:GetAttribute("BagRest")
        return typeof(rest) == "CFrame" and rest or part.CFrame
    end
    local function occupied(target, character)
        local part = bagPart(target)
        if not part then return true end
        for _, player in App.S.Players:GetPlayers() do
            local other = player.Character
            local root = other and other:FindFirstChild("HumanoidRootPart")
            if other ~= character and root and (root.Position - part.Position).Magnitude < 7 then return true end
        end
        return false
    end
    local function blocked(character, humanoid)
        if humanoid.Sit then return "Stand up to punch bags" end
        if (App.Player:GetAttribute("TrainingUI") or "") ~= "" or character:GetAttribute("Training") ~= nil then
            return "Finish the current activity first"
        end
        if character:GetAttribute("Sparring") ~= nil or character:GetAttribute("InRing") == true
            or character:GetAttribute("MittsRole") ~= nil then return "Bag training paused during this activity" end
        if character:GetAttribute("Downed") or character:GetAttribute("RingBreak")
            or character:GetAttribute("Blocking") or character:GetAttribute("Weaving") then return "Waiting for combat stance" end
        local now = workspace:GetServerTimeNow()
        for _, key in {"StunnedUntil", "ExposedUntil", "FrozenUntil"} do
            local expiry = character:GetAttribute(key)
            if App.Finite(expiry) and expiry > now then return "Waiting for recovery" end
        end
        for _, key in {"TechniqueUntil", "DashingUntil"} do
            local expiry = App.Player:GetAttribute(key)
            if App.Finite(expiry) and expiry > os.clock() then return "Waiting for action recovery" end
        end
        if App.MenuState then
            for _, key in {"IsOpen", "Blocked"} do
                if type(App.MenuState[key]) == "function" then
                    local ok, value = pcall(App.MenuState[key])
                    if not ok or value then return "Close the game menu to train" end
                end
            end
        end
    end
    local function current(session)
        return App.Alive and App.Session == session and session.Kind == "Bag" and session.Owned
            and App.State.Config.TrainingEnabled and App.State.Config.TrainingMethod == App.BagMethod
            and session.Generation == App.TrainingGeneration and App.Player.Character == session.Character
    end
    local function standPosition(target, character, humanoid, root)
        local part = bagPart(target)
        if not part then return end
        local center = restOf(part).Position
        local delta = (root.Position - center) * Vector3.new(1,0,1)
        local outward = delta.Magnitude > 0.1 and delta.Unit or -root.CFrame.LookVector * Vector3.new(1,0,1)
        if outward.Magnitude < 0.1 then outward = Vector3.new(0,0,1) else outward = outward.Unit end
        local radius = math.max(part.Size.X,part.Size.Z) / 2
        local distance = radius + 3
        local point = center + outward * distance
        local parameters = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances = {character,target.Model}
        local ground = workspace:Raycast(Vector3.new(point.X,center.Y+2,point.Z),Vector3.new(0,-24,0),parameters)
        if not ground or ground.Normal.Y < 0.45 then return end
        local clearance = humanoid.HipHeight + root.Size.Y/2
        if humanoid.RigType == Enum.HumanoidRigType.R6 then
            local leg = character:FindFirstChild("Left Leg")
            if leg and leg:IsA("BasePart") then clearance += leg.Size.Y end
        end
        return Vector3.new(point.X,ground.Position.Y+clearance+0.05,point.Z)
    end
    function Adapter.Refresh()
        originalRefresh()
        local bags = {}
        local ok, models = pcall(workspace.QueryDescendants,workspace,"Model[$PunchingBag]")
        if ok then
            for index, model in models do
                if index > 100 then break end
                local target = {Model=model,Method=App.BagMethod}
                local part = bagPart(target)
                if part then
                    local position = restOf(part).Position
                    target.Part,target.Position = part,position
                    target.Key = App.BagMethod .. " · " .. model.Name .. string.format(" · %.1f, %.1f, %.1f",position.X,position.Y,position.Z)
                    bags[#bags+1] = target
                end
            end
        end
        table.sort(bags,function(a,b) return a.Key < b.Key end)
        Adapter.Bags = bags
    end
    function Adapter.MethodOptions()
        local values = originalMethods()
        if not table.find(values,App.BagMethod) then values[#values+1] = App.BagMethod end
        return values
    end
    function Adapter.StationOptions(method)
        if method ~= App.BagMethod then return originalStations(method) end
        local values = {"Nearest free"}
        for _, target in Adapter.Bags or {} do values[#values+1] = target.Key end
        return values
    end
    function Adapter.ChooseBag()
        local character,_,root = App.Character()
        if not character then return end
        local selected = App.State.Config.TargetStation
        local best,distance
        for _, target in Adapter.Bags or {} do
            local part = bagPart(target)
            if not part or occupied(target,character) then continue end
            if selected ~= "Nearest free" and selected ~= target.Key then continue end
            local gap = (root.Position-restOf(part).Position).Magnitude
            if not distance or gap < distance then best,distance = target,gap end
        end
        return best,distance
    end
    local function face(root, part)
        local point = Vector3.new(part.Position.X,root.Position.Y,part.Position.Z)
        if (point-root.Position).Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position,point) end
    end
    local function prepare(session, character, humanoid, root)
        session.PrepareVersion = (session.PrepareVersion or 0)+1
        local version = session.PrepareVersion
        session.Preparing = true
        App.Maid:Spawn(function()
            local function valid()
                return current(session) and session.PrepareVersion == version and humanoid.Parent
                    and humanoid.Health > 0 and root.Parent and not blocked(character,humanoid)
            end
            if not valid() then session.Preparing=false;return end
            local tool = character:FindFirstChild("Boxing")
            if not tool or not tool:IsA("Tool") then
                if not App.State.Config.AutoEquip then
                    session.Preparing=false;App.State.Status="Equip Boxing gloves to punch bags";return
                end
                local backpack = App.Player:FindFirstChildOfClass("Backpack")
                tool = backpack and backpack:FindFirstChild("Boxing")
                if not tool or not tool:IsA("Tool") then
                    session.Preparing=false;App.State.Status="Boxing tool unavailable";return
                end
                local previous = {}
                for _, item in character:GetChildren() do if item:IsA("Tool") then previous[#previous+1]=item end end
                App.EquippedByHub={Tool=tool,Character=character,Previous=previous}
                humanoid:EquipTool(tool)
                task.wait(0.25)
                if not valid() then session.Preparing=false;return end
            end
            if not App.CanTrain() or not valid() then session.Preparing=false;return end
            local part = bagPart(session.Target)
            if not part or occupied(session.Target,character) then session.Preparing=false;return end
            local surface = (part:GetClosestPointOnSurface(root.Position)-root.Position).Magnitude
            if surface < 4.2 and surface > 1 then
                face(root,part);session.Preparing=false;session.NextPunch=os.clock()+0.15;return
            end
            if not App.State.Config.AutoMove then
                session.Preparing=false;App.State.Status="Move within punching range, or enable Auto Move";return
            end
            local point = standPosition(session.Target,character,humanoid,root)
            if not point then
                session.Preparing=false;App.State.Status="Bag floor is not streamed";return
            end
            App.State.Status="Moving to punching bag"
            session.NextMove=os.clock()+2
            local moved = App.Move({Position=point-Vector3.new(0,3,0)},function(arrived)
                if not valid() then session.Preparing=false;return end
                session.Preparing=false
                local livePart = bagPart(session.Target)
                if arrived and livePart then
                    face(root,livePart);session.NextPunch=os.clock()+0.15
                else App.State.Status="Bag route blocked" end
            end)
            if not moved then session.Preparing=false end
        end)
    end
    function App.StepBagTraining()
        if not App.CanTrain() then return end
        local character,humanoid,root = App.Character()
        if not character then return end
        local reason = blocked(character,humanoid)
        local session = App.Session
        if reason then
            if session and session.Kind=="Bag" and session.Preparing then
                session.PrepareVersion=(session.PrepareVersion or 0)+1
                session.Preparing=false;App.CancelMove()
            end
            App.State.Status=reason;return
        end
        if not inputBus then
            local module=App.Boxing:FindFirstChild("BoxingVirtualInput")
            local ok,bus=pcall(function() return module and require(module) end)
            if not ok or type(bus)~="table" or type(bus.Tap)~="function" then
                App.State.Status="Native boxing input is unavailable";return
            end
            inputBus=bus
        end
        if not App.Alive or App.Player.Character~=character or not App.CanTrain() then return end
        if not session then
            if App.Moving or App.PendingStart or os.clock()<App.State.NextStart then return end
            local target=Adapter.ChooseBag()
            if not target then App.State.Status="No unoccupied punching bag · refresh targets";return end
            session={Kind="Bag",Owned=true,Generation=App.TrainingGeneration,Character=character,
                Target=target,NextPunch=os.clock(),Side="PunchLeft",Sweeps={}}
            App.Session=session
        end
        if not current(session) then return end
        local part=bagPart(session.Target)
        if not part or occupied(session.Target,character) then
            App.StopTraining("Punching bag unavailable or occupied");return
        end
        if session.Preparing or App.Moving then return end
        local tool=character:FindFirstChild("Boxing")
        local surface=(part:GetClosestPointOnSurface(root.Position)-root.Position).Magnitude
        if not tool or not tool:IsA("Tool") or surface>4.2 or surface<1 then
            if os.clock()>=(session.NextMove or 0) then
                session.NextMove=os.clock()+1.5
                prepare(session,character,humanoid,root)
            end
            return
        end
        if os.clock()<session.NextPunch then return end
        if not App.CanTrain() or not current(session) or blocked(character,humanoid) then return end
        face(root,part)
        local action=App.State.Config.BagAlternate and session.Side or "PunchLeft"
        session.NextPunch=os.clock()+App.State.Config.BagPunchInterval
        local ok=pcall(inputBus.Tap,action)
        if not ok then App.StopTraining("Native boxing input failed");return end
        session.Side=action=="PunchLeft" and "PunchRight" or "PunchLeft"
        App.State.Status="Punching bags · Punch Sharpness"
    end
    function App.StopBagTraining(session)
        if session and session.Kind=="Bag" then
            session.PrepareVersion=(session.PrepareVersion or 0)+1
            session.Preparing=false
        end
    end
    function App.OnBagEvent(action,bag,attacker)
        local session=App.Session
        if action~="BagHit" or not session or not current(session) then return end
        if attacker~=session.Character or bag~=session.Target.Model then return end
        if typeof(bag)~="Instance" or bag:GetAttribute("PunchingBag")~=true then return end
        App.State.Reps+=1
        session.LastHit=os.clock()
    end
    Adapter.Refresh()
end

do
    function App.BuildUI()
        local S, Player = App.S, App.Player
        local Adapter, ConfigStore = App.Adapter, App.ConfigStore
        local C = App.State.Config
        local P = {
            Main = Color3.fromRGB(13, 15, 20), Sidebar = Color3.fromRGB(17, 20, 28),
            Card = Color3.fromRGB(22, 26, 36), Control = Color3.fromRGB(30, 35, 48),
            Border = Color3.fromRGB(38, 44, 61), Text = Color3.fromRGB(241, 245, 249),
            Muted = Color3.fromRGB(139, 149, 167), Good = Color3.fromRGB(74, 222, 160),
            Bad = Color3.fromRGB(251, 113, 133), Accent = Color3.fromRGB(99, 102, 241),
        }
        local themeCallbacks, tabButtons, pages, fades = {}, {}, {}, setmetatable({}, {__mode = "k"})
        local viewport, gui, main, mainScale, pill, activeIndicator
        local visibilityVersion, pageVersion = 0, 0
        local pageNames = {"Dashboard", "Training", "World & Quests", "Player & QoL", "Configs & Settings"}

        local function watch(signal, callback, bucket)
            local connection = signal:Connect(callback)
            if bucket then table.insert(bucket, connection) else App.Maid:Give(connection) end
            return connection
        end
        local function create(class, properties, parent)
            local object = Instance.new(class)
            for key, value in pairs(properties or {}) do object[key] = value end
            object.Parent = parent
            return object
        end
        local function corners(object, radius)
            create("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, object)
        end
        local function outline(object, color)
            return create("UIStroke", {Color = color or P.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, object)
        end
        local function text(parent, value, size, color, bold)
            return create("TextLabel", {
                BackgroundTransparency = 1, BorderSizePixel = 0, Text = value or "", TextColor3 = color or P.Text,
                Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize = size or 13,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
                Size = UDim2.new(1, 0, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd,
            }, parent)
        end
        local function layout(parent, gap)
            return create("UIListLayout", {Padding = UDim.new(0, gap or 8), SortOrder = Enum.SortOrder.LayoutOrder}, parent)
        end
        local function pad(parent, amount)
            create("UIPadding", {PaddingTop = UDim.new(0, amount), PaddingBottom = UDim.new(0, amount),
                PaddingLeft = UDim.new(0, amount), PaddingRight = UDim.new(0, amount)}, parent)
        end
        local function themed(callback)
            table.insert(themeCallbacks, callback)
            callback()
        end
        local function group(parent, properties)
            local ok, object = pcall(Instance.new, "CanvasGroup")
            if not ok then object = Instance.new("Frame") end
            object.BorderSizePixel = 0
            for key, value in pairs(properties or {}) do object[key] = value end
            object.Parent = parent
            return object
        end
        local function opacity(object, alpha, duration)
            if object:IsA("CanvasGroup") then
                App.Tween(object, {GroupTransparency = alpha}, duration)
                return
            end
            local objects = object:GetDescendants()
            table.insert(objects, object)
            for _, child in ipairs(objects) do
                local properties = {}
                if child:IsA("GuiObject") then properties.BackgroundTransparency = true end
                if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
                    properties.TextTransparency = true
                    properties.TextStrokeTransparency = true
                end
                if child:IsA("ImageLabel") or child:IsA("ImageButton") then properties.ImageTransparency = true end
                if child:IsA("UIStroke") then properties.Transparency = true end
                local original = fades[child] or {}
                fades[child] = original
                local target = {}
                for property in pairs(properties) do
                    if original[property] == nil then original[property] = child[property] end
                    target[property] = original[property] + (1 - original[property]) * alpha
                end
                if next(target) then App.Tween(child, target, duration) end
            end
        end
        local function interactive(button, callback, bucket, quiet)
            button.AutoButtonColor = false
            local pressScale = create("UIScale", {Scale = 1}, button)
            watch(button.InputBegan, function(event)
                if event.UserInputType == Enum.UserInputType.MouseButton1 or event.UserInputType == Enum.UserInputType.Touch then
                    App.Tween(pressScale, {Scale = 0.98}, 0.1)
                end
            end, bucket)
            watch(button.InputEnded, function(event)
                if event.UserInputType == Enum.UserInputType.MouseButton1 or event.UserInputType == Enum.UserInputType.Touch then
                    App.Tween(pressScale, {Scale = 1}, 0.15)
                end
            end, bucket)
            if not quiet then
                watch(button.MouseEnter, function()
                    if App.Alive then App.Tween(button, {BackgroundColor3 = P.Control:Lerp(P.Text, 0.055)}, 0.15) end
                end, bucket)
                watch(button.MouseLeave, function()
                    if App.Alive then App.Tween(button, {BackgroundColor3 = P.Control}, 0.15) end
                end, bucket)
            end
            if callback then watch(button.Activated, function() if App.Alive then callback() end end, bucket) end
        end
        local function action(parent, caption, callback, accent)
            local button = create("TextButton", {Text = caption, TextSize = 12, Font = Enum.Font.GothamMedium,
                TextColor3 = P.Text, BackgroundColor3 = P.Control, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 36)}, parent)
            corners(button, 8)
            outline(button)
            interactive(button, callback, nil, accent)
            if accent then
                themed(function() button.BackgroundColor3 = P.Accent end)
                watch(button.MouseEnter, function() App.Tween(button, {BackgroundColor3 = P.Accent:Lerp(P.Text, 0.1)}, 0.15) end)
                watch(button.MouseLeave, function() App.Tween(button, {BackgroundColor3 = P.Accent}, 0.15) end)
            end
            return button
        end
        local function row(parent, height)
            return create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, height or 46)}, parent)
        end
        local function card(parent, title, subtitle)
            local frame = create("Frame", {BackgroundColor3 = P.Card, BorderSizePixel = 0,
                Size = UDim2.new(1, -2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, parent)
            corners(frame, 12)
            local border = outline(frame)
            pad(frame, 16)
            layout(frame, 9)
            text(frame, title, 14, P.Text, true)
            if subtitle then
                local description = text(frame, subtitle, 11, P.Muted)
                description.TextWrapped = true
                description.TextTruncate = Enum.TextTruncate.None
                description.AutomaticSize = Enum.AutomaticSize.Y
                description.Size = UDim2.new(1, 0, 0, 16)
            end
            watch(frame.MouseEnter, function() App.Tween(border, {Color = P.Border:Lerp(P.Accent, 0.25)}, 0.15) end)
            watch(frame.MouseLeave, function() App.Tween(border, {Color = P.Border}, 0.15) end)
            return frame
        end
        local function input(parent, placeholder, default)
            local box = create("TextBox", {BackgroundColor3 = P.Control, BorderSizePixel = 0,
                Text = default or "", PlaceholderText = placeholder or "", PlaceholderColor3 = P.Muted,
                TextColor3 = P.Text, TextSize = 12, Font = Enum.Font.Gotham,
                ClearTextOnFocus = false, Size = UDim2.new(1, 0, 0, 36)}, parent)
            corners(box, 8)
            outline(box)
            return box
        end
        local function set(key, value)
            local ok, message = App.Set(key, value)
            if ok == false and message then App.Notify(message, "error") end
        end
        local function toggle(parent, caption, key, detail)
            local frame = row(parent, detail and 51 or 40)
            local label = text(frame, caption, 12)
            label.Size = UDim2.new(1, -68, 0, 24)
            if detail then
                local sub = text(frame, detail, 10, P.Muted)
                sub.Position = UDim2.fromOffset(0, 25)
                sub.Size = UDim2.new(1, -62, 0, 20)
            end
            local button = create("TextButton", {Text = "", BackgroundColor3 = P.Control, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0, 20), Size = UDim2.fromOffset(42, 24)}, frame)
            corners(button, 12)
            local knob = create("Frame", {BackgroundColor3 = P.Muted, BorderSizePixel = 0,
                Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(18, 18)}, button)
            corners(knob, 9)
            local function update(value)
                App.Tween(button, {BackgroundColor3 = value and P.Accent or P.Control}, 0.15)
                App.Tween(knob, {Position = UDim2.fromOffset(value and 21 or 3, 3),
                    BackgroundColor3 = value and P.Text or P.Muted}, 0.15)
            end
            interactive(button, function() set(key, not C[key]) end, nil, true)
            watch(button.MouseEnter, function() App.Tween(knob, {BackgroundColor3 = P.Text}, 0.15) end)
            watch(button.MouseLeave, function() update(C[key]) end)
            App.Bind(key, update)
            themed(function() update(C[key]) end)
        end
        local function slider(parent, caption, key, minimum, maximum, step, suffix)
            local frame = row(parent, 66)
            local label = text(frame, caption, 12)
            label.Size = UDim2.new(1, -90, 0, 25)
            local numeric = input(frame, "", "")
            numeric.AnchorPoint = Vector2.new(1, 0)
            numeric.Position = UDim2.fromScale(1, 0)
            numeric.Size = UDim2.fromOffset(76, 25)
            local track = create("TextButton", {Text = "", BackgroundColor3 = P.Control, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 37), BackgroundTransparency = 1}, frame)
            track.AutoButtonColor = false
            local rail = create("Frame", {BackgroundColor3 = P.Control, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 5)}, track)
            corners(rail, 3)
            local fill = create("Frame", {BackgroundColor3 = P.Accent, BorderSizePixel = 0,
                Size = UDim2.new(0, 0, 1, 0)}, rail)
            corners(fill, 3)
            local glow = create("Frame", {BackgroundColor3 = P.Accent, BackgroundTransparency = 0.8, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(24, 24)}, track)
            corners(glow, 12)
            local handle = create("Frame", {BackgroundColor3 = P.Text, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(12, 12)}, track)
            corners(handle, 6)
            local dragging, dragInput = false, nil
            local function format(value)
                if step >= 1 then return string.format("%.0f", value) end
                if step >= 0.1 then return string.format("%.1f", value) end
                if step >= 0.01 then return string.format("%.2f", value) end
                return string.format("%.3f", value)
            end
            local function update(value)
                local ratio = math.clamp(((tonumber(value) or minimum) - minimum) / (maximum - minimum), 0, 1)
                App.Tween(fill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.15)
                App.Tween(handle, {Position = UDim2.fromScale(ratio, 0.5)}, 0.15)
                App.Tween(glow, {Position = UDim2.fromScale(ratio, 0.5)}, 0.15)
                if not numeric:IsFocused() then numeric.Text = format(value) .. (suffix or "") end
            end
            local function fromPosition(position)
                if track.AbsoluteSize.X <= 0 then return end
                local ratio = math.clamp((position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                local value = minimum + ratio * (maximum - minimum)
                value = math.clamp(math.floor(value / step + 0.5) * step, minimum, maximum)
                set(key, value)
            end
            watch(track.InputBegan, function(event)
                if event.UserInputType == Enum.UserInputType.MouseButton1 or event.UserInputType == Enum.UserInputType.Touch then
                    dragging, dragInput = true, event
                    App.Tween(glow, {BackgroundTransparency = 0.55}, 0.15)
                    fromPosition(event.Position)
                end
            end)
            watch(S.UserInputService.InputChanged, function(event)
                if dragging and (event == dragInput or event.UserInputType == Enum.UserInputType.MouseMovement) then fromPosition(event.Position) end
            end)
            watch(S.UserInputService.InputEnded, function(event)
                if dragging and (event == dragInput or event.UserInputType == Enum.UserInputType.MouseButton1) then
                    dragging, dragInput = false, nil
                    App.Tween(glow, {BackgroundTransparency = 0.8}, 0.15)
                end
            end)
            watch(numeric.Focused, function() numeric.Text = format(C[key]) end)
            watch(numeric.FocusLost, function()
                local value = tonumber(numeric.Text)
                if value then set(key, math.clamp(math.floor(value / step + 0.5) * step, minimum, maximum)) end
                numeric.Text = format(C[key]) .. (suffix or "")
            end)
            App.Bind(key, update)
            themed(function() fill.BackgroundColor3 = P.Accent; glow.BackgroundColor3 = P.Accent end)
        end
        local function dropdown(parent, caption, key, options)
            local frame = row(parent, 64)
            text(frame, caption, 11, P.Muted).Size = UDim2.new(1, 0, 0, 18)
            local header = create("TextButton", {Text = "", BackgroundColor3 = P.Control, BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, 23), Size = UDim2.new(1, 0, 0, 34)}, frame)
            corners(header, 8)
            outline(header)
            local valueText = text(header, "", 12)
            valueText.Position = UDim2.fromOffset(12, 0)
            valueText.Size = UDim2.new(1, -42, 1, 0)
            local chevron = text(header, "+", 17, P.Muted)
            chevron.AnchorPoint = Vector2.new(1, 0)
            chevron.Position = UDim2.new(1, -10, 0, 0)
            chevron.Size = UDim2.new(0, 18, 1, 0)
            chevron.TextXAlignment = Enum.TextXAlignment.Center
            local panel = create("Frame", {BackgroundColor3 = P.Sidebar, BorderSizePixel = 0, ClipsDescendants = true,
                Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 0), Visible = false}, frame)
            corners(panel, 8)
            local search = input(panel, "Search...", "")
            search.Position = UDim2.fromOffset(7, 7)
            search.Size = UDim2.new(1, -14, 0, 28)
            local list = create("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0,
                Position = UDim2.fromOffset(7, 41), Size = UDim2.new(1, -14, 1, -48),
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 3, ScrollBarImageColor3 = P.Border}, panel)
            layout(list, 4)
            local connections, selectedButtons, opened, revision = {}, {}, false, 0
            local function clear()
                for _, connection in ipairs(connections) do connection:Disconnect() end
                table.clear(connections)
                table.clear(selectedButtons)
                for _, child in ipairs(list:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
            end
            App.Maid:Give(clear)
            local function getOptions()
                if type(options) == "function" then
                    local ok, values = pcall(options)
                    return ok and type(values) == "table" and values or {}
                end
                return options or {}
            end
            local function close()
                opened, revision = false, revision + 1
                local version = revision
                chevron.Text = "+"
                App.Tween(frame, {Size = UDim2.new(1, 0, 0, 64)}, 0.22)
                App.Tween(panel, {Size = UDim2.new(1, 0, 0, 0)}, 0.22)
                App.Maid:Delay(0.23, function() if revision == version and panel.Parent then panel.Visible = false end end)
            end
            local function rebuild()
                clear()
                local query = string.lower(search.Text)
                local count = 0
                for _, value in ipairs(getOptions()) do
                    local name = tostring(value)
                    if query == "" or string.find(string.lower(name), query, 1, true) then
                        count = count + 1
                        local choice = create("TextButton", {Text = "  " .. name, TextColor3 = P.Text,
                            TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham, TextSize = 11,
                            BackgroundColor3 = name == tostring(C[key]) and P.Accent or P.Control, BorderSizePixel = 0,
                            Size = UDim2.new(1, -4, 0, 29)}, list)
                        corners(choice, 6)
                        selectedButtons[choice] = name
                        interactive(choice, function() set(key, name); close() end, connections, true)
                        watch(choice.MouseEnter, function()
                            App.Tween(choice, {BackgroundColor3 = name == tostring(C[key]) and P.Accent or P.Control:Lerp(P.Text, 0.08)}, 0.15)
                        end, connections)
                        watch(choice.MouseLeave, function()
                            App.Tween(choice, {BackgroundColor3 = name == tostring(C[key]) and P.Accent or P.Control}, 0.15)
                        end, connections)
                    end
                end
                if count == 0 then
                    text(list, "No matching options", 11, P.Muted).Size = UDim2.new(1, 0, 0, 30)
                end
                list.CanvasPosition = Vector2.zero
            end
            interactive(header, function()
                if opened then close(); return end
                opened, revision = true, revision + 1
                search.Text = ""
                rebuild()
                panel.Visible = true
                chevron.Text = "-"
                App.Tween(frame, {Size = UDim2.new(1, 0, 0, 260)}, 0.22)
                App.Tween(panel, {Size = UDim2.new(1, 0, 0, 190)}, 0.22)
            end)
            watch(search:GetPropertyChangedSignal("Text"), function() if opened then rebuild() end end)
            local function update(value)
                valueText.Text = tostring(value or "Select")
                for button, name in pairs(selectedButtons) do
                    App.Tween(button, {BackgroundColor3 = name == tostring(value) and P.Accent or P.Control}, 0.15)
                end
            end
            App.Bind(key, update)
            themed(function() update(C[key]) end)
            return {Refresh = function() update(C[key]); if opened then rebuild() end end, Close = close}
        end
        local function result(ok, message)
            App.Notify(tostring(message or (ok and "Done" or "Action failed")), ok and "success" or "error")
        end

        gui = create("ScreenGui", {Name = "HajimeRisingHub", ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 99999, IgnoreGuiInset = true})
        local parents = {}
        if type(gethui) == "function" then local ok, value = pcall(gethui); if ok and value then table.insert(parents, value) end end
        local okCore, core = pcall(function() return game:GetService("CoreGui") end)
        if okCore then
            if type(cloneref) == "function" then local ok, value = pcall(cloneref, core); if ok then core = value end end
            table.insert(parents, core)
        end
        local playerGui = Player:FindFirstChildOfClass("PlayerGui") or Player:WaitForChild("PlayerGui", 10)
        if playerGui then table.insert(parents, playerGui) end
        local parented = false
        for _, parent in ipairs(parents) do
            local mounted = pcall(function() gui.Parent = parent end) and gui.Parent ~= nil
            if mounted then
                -- Some executors run signal callbacks at game identity. Probe that
                -- identity before choosing a protected container for the whole UI.
                local getter = type(getthreadidentity)=="function" and getthreadidentity
                    or type(getidentity)=="function" and getidentity
                local setter = type(setthreadidentity)=="function" and setthreadidentity
                    or type(setidentity)=="function" and setidentity
                local gotIdentity, identity = false, nil
                if getter and setter then gotIdentity,identity=pcall(getter) end
                local writable = true
                if gotIdentity and type(identity)=="number" then
                    local probe = Instance.new("TextLabel")
                    probe.Visible=false
                    local prepared=pcall(function() probe.Parent=gui end)
                    if prepared then
                        local lowered=pcall(setter,2)
                        if lowered then writable=pcall(function() probe.Text="" end) end
                        pcall(setter,identity)
                    end
                    pcall(probe.Destroy,probe)
                end
                if writable then parented=true;break end
                -- CoreGui protection can survive reparenting. Use a fresh root
                -- for the next candidate rather than carrying that protection.
                pcall(gui.Destroy,gui)
                gui=create("ScreenGui",{Name="HajimeRisingHub",ResetOnSpawn=false,
                    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=99999,IgnoreGuiInset=true})
            end
        end
        if not parented then gui:Destroy(); error("No writable UI container is available") end
        pcall(function() if type(syn) == "table" and type(syn.protect_gui) == "function" then syn.protect_gui(gui) end end)
        App.Maid:Give(gui)
        App.Gui = gui
        local root = create("Frame", {Name = "Viewport", BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1)}, gui)
        viewport = root.AbsoluteSize
        main = group(root, {Name = "Window", BackgroundColor3 = P.Main, Size = UDim2.fromOffset(800, 590),
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(C.WindowX, C.WindowY), ClipsDescendants = true})
        corners(main, 16)
        outline(main)
        mainScale = create("UIScale", {Scale = 0.96}, main)
        local top = create("Frame", {Name = "DragBar", BackgroundColor3 = P.Sidebar, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 61), Active = true}, main)
        local logo = create("Frame", {BackgroundColor3 = P.Accent, BorderSizePixel = 0,
            Position = UDim2.fromOffset(19, 16), Size = UDim2.fromOffset(30, 30)}, top)
        corners(logo, 8)
        local mark = text(logo, "H", 17, P.Text, true)
        mark.Size = UDim2.fromScale(1, 1)
        mark.TextXAlignment = Enum.TextXAlignment.Center
        themed(function() logo.BackgroundColor3 = P.Accent end)
        local brand = text(top, "HAJIME  /  RISING", 14, P.Text, true)
        brand.Position = UDim2.fromOffset(61, 13)
        brand.Size = UDim2.fromOffset(260, 22)
        local brandSub = text(top, "TRAINING CONSOLE", 9, P.Muted)
        brandSub.Position = UDim2.fromOffset(62, 34)
        brandSub.Size = UDim2.fromOffset(260, 15)
        local minimize = create("TextButton", {Text = "-", TextSize = 23, TextColor3 = P.Muted,
            Font = Enum.Font.GothamMedium, BorderSizePixel = 0, BackgroundColor3 = P.Control,
            Position = UDim2.new(1, -86, 0, 17), Size = UDim2.fromOffset(28, 28)}, top)
        corners(minimize, 7)
        local close = create("TextButton", {Text = "x", TextSize = 15, TextColor3 = P.Muted,
            Font = Enum.Font.GothamMedium, BorderSizePixel = 0, BackgroundColor3 = P.Control,
            Position = UDim2.new(1, -48, 0, 17), Size = UDim2.fromOffset(28, 28)}, top)
        corners(close, 7)
        local sidebar = create("Frame", {BackgroundColor3 = P.Sidebar, BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 62), Size = UDim2.new(0, 179, 1, -105)}, main)
        local nav = create("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 18),
            Size = UDim2.new(1, -24, 0, 260)}, sidebar)
        activeIndicator = create("Frame", {BackgroundColor3 = P.Accent, BackgroundTransparency = 0.86,
            BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 43), ZIndex = 1}, nav)
        corners(activeIndicator, 9)
        local indicatorLine = create("Frame", {BackgroundColor3 = P.Accent, BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 12), Size = UDim2.fromOffset(3, 19)}, activeIndicator)
        corners(indicatorLine, 2)
        themed(function() activeIndicator.BackgroundColor3 = P.Accent; indicatorLine.BackgroundColor3 = P.Accent end)
        for index, name in ipairs(pageNames) do
            local button = create("TextButton", {Text = "", BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 43), Position = UDim2.fromOffset(0, (index - 1) * 49), ZIndex = 2}, nav)
            local number = text(button, string.format("%02d", index), 10, P.Muted, true)
            number.Position = UDim2.fromOffset(12, 0)
            number.Size = UDim2.new(0, 25, 1, 0)
            local title = text(button, name, 11, P.Muted)
            title.Position = UDim2.fromOffset(40, 0)
            title.Size = UDim2.new(1, -45, 1, 0)
            tabButtons[name] = {Button = button, Label = title, Number = number, Index = index}
            interactive(button, function() set("ActiveTab", name) end, nil, true)
            watch(button.MouseEnter, function() if C.ActiveTab ~= name then App.Tween(title, {TextColor3 = P.Text}, 0.15) end end)
            watch(button.MouseLeave, function() if C.ActiveTab ~= name then App.Tween(title, {TextColor3 = P.Muted}, 0.15) end end)
        end
        local sideTip = text(sidebar, "CONSISTENCY\nBUILDS CHAMPIONS.", 10, P.Muted, true)
        sideTip.Position = UDim2.new(0, 24, 1, -74)
        sideTip.Size = UDim2.new(1, -40, 0, 50)
        sideTip.TextWrapped = true
        local content = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0,
            Position = UDim2.fromOffset(198, 76), Size = UDim2.new(1, -218, 1, -133), ClipsDescendants = true}, main)
        for _, name in ipairs(pageNames) do
            local page = group(content, {Name = name, BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1), Visible = false})
            local scroll = create("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 3, ScrollBarImageColor3 = P.Border, ScrollingDirection = Enum.ScrollingDirection.Y}, page)
            create("UIPadding", {PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 7), PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2)}, scroll)
            layout(scroll, 13)
            local heading = text(scroll, name, 23, P.Text, true)
            heading.Size = UDim2.new(1, 0, 0, 34)
            pages[name] = {Root = page, Scroll = scroll}
        end
        local footer = create("Frame", {BackgroundColor3 = P.Sidebar, BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 1, -42), Size = UDim2.new(1, 0, 0, 42)}, main)
        local statusDot = create("Frame", {BackgroundColor3 = P.Good, BorderSizePixel = 0,
            Position = UDim2.new(1, -179, 0, 17), Size = UDim2.fromOffset(7, 7)}, footer)
        corners(statusDot, 4)
        local footerStatus = text(footer, "CONNECTED", 9, P.Muted, true)
        footerStatus.Position = UDim2.new(1, -160, 0, 0)
        footerStatus.Size = UDim2.new(0, 140, 1, 0)

        local toastLayer = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -22, 1, -22), Size = UDim2.new(0, 340, 1, -44)}, root)
        local toasts, toastSequence = {}, 0
        local function arrangeToasts()
            local offset = 0
            for index = #toasts, 1, -1 do
                local item = toasts[index]
                if item.Frame.Parent then
                    App.Tween(item.Frame, {Position = UDim2.new(1, 0, 1, -offset)}, 0.22)
                    offset = offset + 81
                end
            end
        end
        local function dismissToast(item)
            if item.Removing then return end
            item.Removing = true
            for index, value in ipairs(toasts) do if value == item then table.remove(toasts, index); break end end
            if item.Frame.Parent then
                App.Tween(item.Frame, {Position = UDim2.new(1, 370, 1, item.Frame.Position.Y.Offset)}, 0.22)
                opacity(item.Frame, 1, 0.2)
                App.Maid:Delay(0.24, function() if item.Frame.Parent then item.Frame:Destroy() end end)
            end
            arrangeToasts()
        end
        App.Notify = function(message, kind, duration)
            if not App.Alive then return end
            toastSequence = toastSequence + 1
            local lifespan = math.clamp(tonumber(duration) or 4, 1, 20)
            local color = kind == "error" and P.Bad or kind == "success" and P.Good or P.Accent
            local frame = group(toastLayer, {Name = "Toast" .. toastSequence, BackgroundColor3 = P.Card,
                AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 370, 1, 0), Size = UDim2.fromOffset(340, 72), ClipsDescendants = true})
            corners(frame, 10)
            outline(frame)
            local strip = create("Frame", {BackgroundColor3 = color, BorderSizePixel = 0,
                Size = UDim2.new(0, 3, 1, 0)}, frame)
            local label = text(frame, tostring(message), 11, P.Text)
            label.Position = UDim2.fromOffset(17, 9)
            label.Size = UDim2.new(1, -31, 1, -21)
            label.TextWrapped = true
            label.TextTruncate = Enum.TextTruncate.None
            local progress = create("Frame", {BackgroundColor3 = color, BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2)}, frame)
            local item = {Frame = frame}
            table.insert(toasts, item)
            while #toasts > 4 do dismissToast(toasts[1]) end
            arrangeToasts()
            App.Tween(progress, {Size = UDim2.new(0, 0, 0, 2)}, lifespan, Enum.EasingStyle.Linear)
            App.Maid:Delay(lifespan, function() dismissToast(item) end)
        end

        local dashboardLabels, statLabels = {}, {}
        do
            local page = pages.Dashboard.Scroll
            local overview = card(page, "Live session", "Training signals and character resources update in real time.")
            local status = text(overview, "Standing by", 17, P.Text, true)
            status.Size = UDim2.new(1, 0, 0, 29)
            dashboardLabels.Status = status
            for _, field in ipairs({"Character", "Resources", "Session", "Notice"}) do
                local line = text(overview, "", field == "Notice" and 10 or 11, P.Muted)
                line.TextWrapped = true
                line.AutomaticSize = Enum.AutomaticSize.Y
                line.Size = UDim2.new(1, 0, 0, 19)
                line.TextTruncate = Enum.TextTruncate.None
                dashboardLabels[field] = line
            end
            local staminaRow = row(overview, 12)
            local rail = create("Frame", {BackgroundColor3 = P.Control, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 6)}, staminaRow)
            corners(rail, 3)
            local staminaFill = create("Frame", {BackgroundColor3 = P.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1)}, rail)
            corners(staminaFill, 3)
            dashboardLabels.StaminaFill = staminaFill
            themed(function() staminaFill.BackgroundColor3 = P.Accent end)
            local stats = card(page, "Training ledger", "Current values · session gain · gain per minute")
            for _, name in ipairs({"Power", "Speed", "Technique", "Willpower", "Endurance", "Stamina"}) do
                local line = row(stats, 29)
                local label = text(line, name, 12)
                label.Size = UDim2.new(0.35, 0, 1, 0)
                local values = text(line, "--", 11, P.Muted)
                values.Position = UDim2.fromScale(0.35, 0)
                values.Size = UDim2.new(0.65, 0, 1, 0)
                values.TextXAlignment = Enum.TextXAlignment.Right
                statLabels[name] = values
            end
            local controls = card(page, "Quick control")
            toggle(controls, "Auto Train", "TrainingEnabled", "Uses the selected station and training method.")
            toggle(controls, "QTE assist", "QTEAssist", "Completes verified training sweeps while enabled.")
        end
        do
            local page = pages.Training.Scroll
            local session = card(page, "Training engine", "Select a method, then let the station drive the session.")
            toggle(session, "Auto Train", "TrainingEnabled")
            dropdown(session, "Method / trained stat", "TrainingMethod", Adapter.MethodOptions)
            local methodDetail = text(session, "", 11, P.Muted)
            methodDetail.TextWrapped = true
            methodDetail.TextTruncate = Enum.TextTruncate.None
            methodDetail.AutomaticSize = Enum.AutomaticSize.Y
            App.Bind("TrainingMethod", function(method)
                local config = App.GameConfig
                local station = App.TrainingInfo(method)
                local subs = station and config.Stats and config.Stats.Subs and config.Stats.Subs[station.Stat]
                methodDetail.Text = station and string.format("%s · %s · %s", tostring(station.Stat or "--"),
                    tostring(subs and subs[station.Sub] or "--"), method=="Punching bags" and "Native boxing punches" or tostring(station.Mode or "--")) or "--"
            end)
            local stations = dropdown(session, "Target station", "TargetStation", function() return Adapter.StationOptions(C.TrainingMethod) end)
            App.Bind("TrainingMethod", function() stations.Refresh() end)
            toggle(session, "Complete timing sweeps", "QTEAssist")
            toggle(session, "Stop when the training goal is reached", "StopAtGoal")
            local approach = card(page, "Station approach")
            toggle(approach, "Move to selected station", "AutoMove")
            dropdown(approach, "Movement", "MoveMode", {"Teleport", "Walk"})
            toggle(approach, "Equip required boxing gloves", "AutoEquip")
            slider(approach, "Start / retry delay", "StartDelay", 0.5, 10, 0.1, "s")
            slider(approach, "Timing jitter", "Jitter", 0, 0.05, 0.001, "s")
            local bags = card(page, "Punching bags", "Select Punching bags above, then enable Auto Train. Hits train Punch Sharpness.")
            toggle(bags, "Alternate left / right punches", "BagAlternate")
            slider(bags, "Punch interval", "BagPunchInterval", 0.3, 2, 0.05, "s")
            local recovery = card(page, "Resource management", "Rest pauses training until the recovery target is met.")
            toggle(recovery, "Smart stamina recovery", "AutoRest")
            slider(recovery, "Pause below stamina", "StaminaLow", 5, 80, 1, "%")
            slider(recovery, "Resume at stamina", "StaminaResume", 20, 100, 1, "%")
            slider(recovery, "Energy floor", "EnergyFloor", 0, 30, 1, "%")
        end
        do
            local page = pages["World & Quests"].Scroll
            local world = card(page, "World destinations", "Destinations come from verified live world markers.")
            local destinations = dropdown(world, "Destination", "WorldDestination", Adapter.WorldOptions)
            action(world, "Travel to destination", function()
                local ok, message = App.Travel()
                if ok ~= nil then result(ok, message) end
            end, true)
            action(world, "Refresh stations and destinations", function()
                Adapter.Refresh()
                destinations.Refresh()
                App.Notify("World markers refreshed", "success")
            end)
            local quests = card(page, "Quest rewards", "Claims only rewards whose replicated progress is complete.")
            toggle(quests, "Claim completed quests", "AutoClaim")
        end
        do
            local page = pages["Player & QoL"].Scroll
            local movement = card(page, "Character controls", "Overrides are restored when disabled or unloaded.")
            toggle(movement, "WalkSpeed override", "SpeedEnabled")
            slider(movement, "WalkSpeed", "WalkSpeed", 8, 40, 1)
            toggle(movement, "JumpPower override", "JumpEnabled")
            slider(movement, "JumpPower", "JumpPower", 20, 100, 1)
            local camera = card(page, "Camera & idle")
            toggle(camera, "Field of view override", "FOVEnabled")
            slider(camera, "Field of view", "FOV", 40, 100, 1, "°")
            toggle(camera, "Anti-AFK", "AntiAFK")
        end
        local profileModeLabel, autoloadLabel, profileDropdown
        do
            local page = pages["Configs & Settings"].Scroll
            local profiles = card(page, "Configuration profiles", "Save every control, selected destination and window preference.")
            profileModeLabel = text(profiles, "", 10, P.Muted)
            profileDropdown = dropdown(profiles, "Profile", "ProfileName", ConfigStore.List)
            local nameBox = input(profiles, "Profile name", C.ProfileName)
            App.Bind("ProfileName", function(value) if not nameBox:IsFocused() then nameBox.Text = tostring(value) end end)
            watch(nameBox.FocusLost, function() set("ProfileName", nameBox.Text); nameBox.Text = C.ProfileName end)
            local function refreshProfiles() profileDropdown.Refresh(); autoloadLabel.Text = "Auto-load: " .. tostring(ConfigStore.GetAutoload() or "off") end
            action(profiles, "Create profile", function() result(ConfigStore.Save(C.ProfileName, false)); refreshProfiles() end, true)
            action(profiles, "Overwrite selected profile", function() result(ConfigStore.Save(C.ProfileName, true)); refreshProfiles() end)
            action(profiles, "Load selected profile", function() result(ConfigStore.Load(C.ProfileName)); refreshProfiles() end)
            action(profiles, "Delete selected profile", function() result(ConfigStore.Delete(C.ProfileName)); refreshProfiles() end)
            action(profiles, "Refresh profile list", function() refreshProfiles(); App.Notify("Profile list refreshed", "success") end)
            autoloadLabel = text(profiles, "Auto-load: " .. tostring(ConfigStore.GetAutoload() or "off"), 10, P.Muted)
            action(profiles, "Set selected profile as auto-load", function() result(ConfigStore.SetAutoload(C.ProfileName)); refreshProfiles() end)
            action(profiles, "Disable auto-load", function() result(ConfigStore.SetAutoload(nil)); refreshProfiles() end)
            action(profiles, "Reset all controls to defaults", function() result(ConfigStore.Reset()); refreshProfiles() end)
            local appearance = card(page, "Appearance & input")
            text(appearance, "Accent color · hex", 11, P.Muted)
            local accent = input(appearance, "#6366F1", C.Accent)
            App.Bind("Accent", function(value) if not accent:IsFocused() then accent.Text = value end end)
            watch(accent.FocusLost, function() set("Accent", accent.Text); accent.Text = C.Accent end)
            dropdown(appearance, "Window toggle key", "ToggleKey", {"RightShift", "LeftShift", "RightControl", "LeftControl", "Insert", "Home", "F4", "F6", "F8", "F10"})
            local capture = action(appearance, "Capture a different toggle key", nil)
            local capturing = false
            watch(capture.Activated, function() capturing = true; App.CapturingKey = true; capture.Text = "Press a key · Esc cancels" end)
            watch(S.UserInputService.InputBegan, function(event)
                if not capturing or event.KeyCode == Enum.KeyCode.Unknown then return end
                capturing = false
                App.CapturingKey = false
                App.KeyCapturedAt = os.clock()
                if event.KeyCode ~= Enum.KeyCode.Escape then set("ToggleKey", event.KeyCode.Name) end
                capture.Text = "Capture a different toggle key"
            end)
            toggle(appearance, "Window visible", "Visible")
            action(appearance, "Center window", function() set("WindowX", 0.5); set("WindowY", 0.5) end)
            local teardown = card(page, "Session cleanup", "Stops owned automation, disconnects signals and restores overrides.")
            action(teardown, "Unload script", App.Unload)
        end

        pill = create("TextButton", {Name = "Minimized", Text = "H  /  RISING    +", TextSize = 12,
            TextColor3 = P.Text, Font = Enum.Font.GothamBold, BackgroundColor3 = P.Sidebar,
            BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(C.WindowX, C.WindowY),
            Size = UDim2.fromOffset(174, 42), Visible = false}, root)
        corners(pill, 21)
        local pillBorder = outline(pill, P.Accent)
        themed(function() pillBorder.Color = P.Accent end)
        local function fittedScale()
            viewport = root.AbsoluteSize
            return math.min(1, math.max(0.12, (viewport.X - 28) / 800), math.max(0.12, (viewport.Y - 28) / 590))
        end
        local function positionWindow()
            local scale = fittedScale()
            local halfX, halfY = 400 * scale, 295 * scale
            local width, height = math.max(viewport.X, 1), math.max(viewport.Y, 1)
            local x = math.clamp(C.WindowX * width, math.min(halfX + 8, width / 2), math.max(width - halfX - 8, width / 2))
            local y = math.clamp(C.WindowY * height, math.min(halfY + 8, height / 2), math.max(height - halfY - 8, height / 2))
            App.Tween(main, {Position = UDim2.fromOffset(x, y)}, 0.15)
            pill.Position = UDim2.fromOffset(math.clamp(x, 95, math.max(95, width - 95)), math.clamp(y, 30, math.max(30, height - 30)))
            if main.Visible then App.Tween(mainScale, {Scale = scale}, 0.15) end
        end
        local function updateVisibility()
            visibilityVersion = visibilityVersion + 1
            local version = visibilityVersion
            local visible = C.Visible == true
            pill.Visible = visible and C.Minimized == true
            if visible and C.Minimized ~= true then
                main.Visible = true
                positionWindow()
                App.Tween(mainScale, {Scale = fittedScale()}, 0.22)
                opacity(main, 0, 0.22)
            else
                opacity(main, 1, 0.18)
                App.Tween(mainScale, {Scale = fittedScale() * 0.96}, 0.18)
                App.Maid:Delay(0.2, function() if version == visibilityVersion then main.Visible = false end end)
            end
        end
        interactive(minimize, function() set("Minimized", true) end)
        interactive(close, function() set("Visible", false) end)
        interactive(pill, function() set("Minimized", false) end, nil, true)
        watch(pill.MouseEnter, function() App.Tween(pill, {BackgroundColor3 = P.Control}, 0.15) end)
        watch(pill.MouseLeave, function() App.Tween(pill, {BackgroundColor3 = P.Sidebar}, 0.15) end)
        local dragStart, dragCenter, dragInput
        watch(top.InputBegan, function(event)
            if event.UserInputType ~= Enum.UserInputType.MouseButton1 and event.UserInputType ~= Enum.UserInputType.Touch then return end
            if S.UserInputService:GetFocusedTextBox() then return end
            local position = event.Position
            if position.X >= minimize.AbsolutePosition.X - 5 then return end
            dragStart, dragCenter, dragInput = position, main.AbsolutePosition + main.AbsoluteSize / 2, event
        end)
        watch(S.UserInputService.InputChanged, function(event)
            if not dragInput then return end
            if event ~= dragInput and event.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            local delta = event.Position - dragStart
            local target = dragCenter + Vector2.new(delta.X, delta.Y)
            if viewport.X > 0 and viewport.Y > 0 then
                set("WindowX", math.clamp(target.X / viewport.X, 0, 1))
                set("WindowY", math.clamp(target.Y / viewport.Y, 0, 1))
            end
        end)
        watch(S.UserInputService.InputEnded, function(event)
            if event == dragInput or event.UserInputType == Enum.UserInputType.MouseButton1 then dragInput = nil end
        end)
        watch(root:GetPropertyChangedSignal("AbsoluteSize"), positionWindow)
        App.Bind("WindowX", positionWindow)
        App.Bind("WindowY", positionWindow)
        App.Bind("Visible", updateVisibility)
        App.Bind("Minimized", updateVisibility)
        App.Bind("Accent", function(value)
            local hex = string.match(tostring(value), "^#?(%x%x%x%x%x%x)$")
            if hex then
                P.Accent = Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
                for _, callback in ipairs(themeCallbacks) do callback() end
            end
        end)
        App.Bind("ActiveTab", function(name)
            local selected = pages[name]
            if not selected then return end
            pageVersion = pageVersion + 1
            local version = pageVersion
            local index = tabButtons[name].Index
            App.Tween(activeIndicator, {Position = UDim2.fromOffset(0, (index - 1) * 49)}, 0.22)
            for tabName, value in pairs(tabButtons) do
                App.Tween(value.Label, {TextColor3 = tabName == name and P.Text or P.Muted}, 0.15)
                App.Tween(value.Number, {TextColor3 = tabName == name and P.Accent or P.Muted}, 0.15)
            end
            for tabName, value in pairs(pages) do
                value.Root.ZIndex = tabName == name and 2 or 1
                if tabName ~= name then
                    opacity(value.Root, 1, 0.12)
                    App.Maid:Delay(0.13, function() if version == pageVersion and C.ActiveTab ~= tabName then value.Root.Visible = false end end)
                end
            end
            selected.Root.Visible = true
            selected.Root.Position = UDim2.fromOffset(9, 0)
            opacity(selected.Root, 1, 0)
            App.Tween(selected.Root, {Position = UDim2.fromOffset(0, 0)}, 0.22)
            opacity(selected.Root, 0, 0.22)
        end)
        themed(function()
            for name, tab in pairs(tabButtons) do tab.Number.TextColor3 = C.ActiveTab == name and P.Accent or P.Muted end
        end)
        local function number(value, decimals)
            if type(value) ~= "number" then return "--" end
            return string.format("%." .. (decimals or 1) .. "f", value)
        end
        App.UIUpdate = function()
            if not App.Alive or not gui.Parent then return end
            local ok, data = pcall(App.GetDashboard)
            if not ok or type(data) ~= "table" then return end
            dashboardLabels.Status.Text = tostring(data.Status or "Standing by")
            dashboardLabels.Character.Text = string.format("%s  ·  %s  ·  Mastery %s  ·  ¥ %s", tostring(data.Style or "--"), tostring(data.Rank or "--"), number(data.Mastery, 1), number(data.Cash, 0))
            dashboardLabels.Resources.Text = string.format("Stamina %s / %s (%s%%)  ·  Energy %s  ·  Hunger %s  ·  Thirst %s", number(data.Stamina, 0), number(data.StaminaMax, 0), number(data.StaminaPercent, 0), number(data.Energy, 0), number(data.Hunger, 0), number(data.Thirst, 0))
            local seconds = math.max(0, tonumber(data.Elapsed) or 0)
            dashboardLabels.Session.Text = string.format("Session %02d:%02d  ·  %s reps  ·  %s", math.floor(seconds / 60), math.floor(seconds % 60), number(data.Reps, 0), tostring(data.Executor or "Executor"))
            dashboardLabels.Notice.Text = tostring(data.LastNotice or "")
            App.Tween(dashboardLabels.StaminaFill, {Size = UDim2.new(math.clamp((tonumber(data.StaminaPercent) or 0) / 100, 0, 1), 0, 1, 0)}, 0.22)
            for _, stat in ipairs(data.Stats or {}) do
                local label = statLabels[stat.Name]
                if label then label.Text = string.format("%s     +%s     %s/min", number(stat.Value, 3), number(stat.Gain, 3), number(stat.PerMinute, 3)) end
            end
            footerStatus.Text = tostring(data.Status or "CONNECTED"):upper()
            profileModeLabel.Text = tostring(data.ProfileMode or "Profiles ready")
        end
        positionWindow()
        App.UIUpdate()
        updateVisibility()
        for _, notification in ipairs(App.NotificationQueue or {}) do
            App.Notify(notification.text or notification[1], notification.kind or notification[2], notification.duration or notification[3])
        end
        App.NotificationQueue = {}
        return gui
    end
end


-- Bootstrap is last so every dependency exists before bindings or auto-load reconcile.
do
    App.Environment.HajimeRisingHub=App
    local ok,message=xpcall(function()
        App.Maid:Give(App.Remote.OnClientEvent:Connect(function(action,data)
            local success,err=xpcall(function() App.OnTrainingEvent(action,data) end,debug.traceback)
            if not success then
                App.LastError=tostring(err)
                App.Set("TrainingEnabled",false)
                App.Notify("Training callback stopped: "..tostring(err):sub(1,150),"error",6)
            end
        end))
        if App.OnBagEvent then App.Maid:Give(App.Remote.OnClientEvent:Connect(App.OnBagEvent)) end
        App.Maid:Give(App.Player.CharacterRemoving:Connect(function()
            App.StopTraining("Waiting for respawn")
            App.RestoreAll()
        end))
        App.Maid:Give(App.Player.CharacterAdded:Connect(function()
            App.StopTraining("Waiting for character")
            App.State.Recovering=false
            App.Adapter.Dirty=true
        end))
        App.Maid:Give(workspace.DescendantAdded:Connect(function(instance)
            if instance:IsA("ProximityPrompt") then App.Adapter.Dirty=true end
        end))
        App.Maid:Give(workspace.DescendantRemoving:Connect(function(instance)
            if instance:IsA("ProximityPrompt") then App.Adapter.Dirty=true end
        end))
        App.Maid:Give(App.Player.Idled:Connect(function()
            if not App.Alive or not App.State.Config.AntiAFK then return end
            local success=pcall(function()
                App.S.VirtualUser:CaptureController()
                App.S.VirtualUser:ClickButton2(Vector2.new())
            end)
            if not success then
                App.Set("AntiAFK",false)
                App.Notify("Anti-AFK input is unavailable in this executor","error")
            end
        end))
        App.Maid:Give(App.S.UserInputService.InputBegan:Connect(function(input,processed)
            if not App.Alive or processed or App.CapturingKey or App.S.UserInputService:GetFocusedTextBox()
                or (App.KeyCapturedAt and os.clock()-App.KeyCapturedAt<0.2) then return end
            if input.KeyCode.Name==App.State.Config.ToggleKey then
                App.Set("Visible",not App.State.Config.Visible)
            end
        end))
        App.BuildUI()
        App.GetDashboard()
        local profile=App.ConfigStore.GetAutoload()
        if profile then
            local loaded,reason=App.ConfigStore.Load(profile)
            App.Notify(loaded and ("Auto-loaded "..profile) or ("Auto-load failed: "..tostring(reason)),loaded and "success" or "error")
        end
        if App.ConfigStore.Mode=="Memory" then
            App.Notify("Filesystem unavailable · profiles stay in memory for this run","info",7)
        end
        App.Notify("Ready · "..App.State.Config.ToggleKey.." toggles the window","success",4)
        local uiTime,questTime,worldTime,errorTime=0,0,0,0
        App.Maid:Give(App.S.RunService.Heartbeat:Connect(function()
            if not App.Alive then return end
            local success,err=xpcall(function()
                App.StepTraining()
                App.StepProperties()
                local now=os.clock()
                if now-questTime>=2 then questTime=now;App.StepQuests() end
                if now-worldTime>=5 and (App.Adapter.Dirty or now-worldTime>=15) then
                    worldTime=now;App.Adapter.Refresh()
                end
                if now-uiTime>=0.25 then
                    uiTime=now
                    if App.UIUpdate then App.UIUpdate() end
                end
            end,debug.traceback)
            if not success then
                App.LastError=tostring(err)
                App.Set("TrainingEnabled",false)
                if os.clock()-errorTime>5 then
                    errorTime=os.clock()
                    App.Notify("Runtime stopped training: "..tostring(err):sub(1,150),"error",6)
                end
            end
        end))
    end,debug.traceback)
    if not ok then App.Unload();error("Hajime Rising Hub: "..tostring(message),0) end
end

return App
