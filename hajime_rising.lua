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
        AutoFood = false, AutoBuyFood = false, FoodLow = 35, FoodTarget = 80,
        FoodItem = "Auto", FoodBudget = 5000,
        AutoWeave = false, AutoDodge = false, AutoBlock = false,
        CombatPlayers = true, CombatNPCs = true, CombatReactionDelay = 0.08,
        CombatThreatRange = 12, CombatStaminaFloor = 20,
        AutoClaim = false, AntiAFK = false, SpeedEnabled = false, WalkSpeed = 16,
        JumpEnabled = false, JumpPower = 50, FOVEnabled = false, FOV = 70,
        Accent = "#6366F1", ToggleKey = "RightShift", Visible = true, Minimized = false,
        WindowX = 0.5, WindowY = 0.5, ActiveTab = "Dashboard", ProfileName = "default",
        WorldDestination = "Gym · main floor",
    }
    App.State = { Config = table.clone(App.Defaults), Status = "Ready", LastNotice = "",
        Started = os.clock(), Reps = 0, Baseline = {}, Recovering = false, NextStart = 0, CombatStatus = "Off" }
    local ranges = { StartDelay = {0.5,10}, Jitter = {0,0.05}, StaminaLow = {5,80},
        StaminaResume = {20,100}, EnergyFloor = {0,30}, WalkSpeed = {8,40},
        JumpPower = {20,100}, FOV = {40,100}, WindowX = {0,1}, WindowY = {0,1}, BagPunchInterval = {0.3,2},
        CombatReactionDelay = {0,0.35}, CombatThreatRange = {6,24}, CombatStaminaFloor = {5,70},
        FoodLow = {5,80}, FoodTarget = {20,100}, FoodBudget = {0,50000} }
    local tabs = { Dashboard=true, Training=true, Combat=true, ["World & Quests"]=true,
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
                if key=="FoodBudget" then value=math.floor(value) end
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
        if result.FoodLow >= result.FoodTarget then return nil, "Food target must exceed the hunger threshold" end
        if result.FoodItem~="Auto" then
            local food=App.GameConfig.Foods and App.GameConfig.Foods[result.FoodItem]
            if type(food)~="table" or not ((tonumber(food.Hunger) or 0)>0 or (tonumber(food.Energy) or 0)>0) then
                return nil,"Unknown food item"
            end
        end
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
        if App.Food then App.Food.Stop("Manual travel") end
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
        if App.Food and App.Food.IsBusy() then return false end
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
        if App.ReconcileCombat then App.ReconcileCombat(changed) end
        if App.Food then App.Food.Reconcile(changed) end
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
            ProfileMode=App.ConfigStore.Mode,LastNotice=state.LastNotice,CombatStatus=state.CombatStatus,
            Combat=App.GetCombatSnapshot and App.GetCombatSnapshot() or nil,
            Food=App.Food and App.Food.Snapshot() or nil }
    end
    function App.Unload()
        if not App.Alive then return end
        App.Alive=false
        if App.Food then App.Food.Destroy() end
        if App.StopCombat then App.StopCombat() end
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


-- Defensive inputs follow server-announced punches and the game's contact geometry.
do
    local D = { Threats={}, Owned={}, Native=nil, NextWeave=0, NextDash=0, Errors=0,
        Weaves=0, Dodges=0, Blocks=0, AcceptedWeaves=0, AcceptedDodges=0, AcceptedBlocks=0,
        ConfirmedDodges=0, ConfirmedBlocks=0, RejectedDodges=0, Status="Off", Serial=0 }
    App.Defense = D
    local Policy = {}
    App.CombatPolicy = Policy
    local renderName = "AllenHajimeDefense_" .. App.S.HttpService:GenerateGUID(false)
    local intentBound = false
    local lastScan = 0

    function Policy.Enabled(config)
        return config.AutoWeave == true or config.AutoDodge == true or config.AutoBlock == true
    end
    function Policy.Entity(isPlayer,isNpc,config)
        return isPlayer and config.CombatPlayers == true or not isPlayer and isNpc and config.CombatNPCs == true
    end
    function Policy.Timing(received,hitTime,scale,reaction)
        if not App.Finite(received) or not App.Finite(hitTime) or hitTime<=0 then return end
        scale=App.Finite(scale) and math.clamp(scale,0.4,6) or 1
        reaction=App.Finite(reaction) and math.clamp(reaction,0,0.4) or 0.08
        local impact=received+math.clamp(hitTime*scale,0.035,3)
        local desired=math.max(received+reaction,impact-0.11)
        local latest=math.max(received,impact-0.065)
        return impact,math.max(received,math.min(desired,latest)),impact+0.18
    end
    function Policy.Window(threat,now)
        if now>threat.Expires then return "expired" end
        if now<threat.ReactAt then return "waiting" end
        return "ready"
    end
    function Policy.CanWeave(punch,zone,weave)
        return zone=="Head" and type(weave)=="table" and type(weave.SlipAnims)=="table"
            and weave.SlipAnims[punch.Anim]==true
    end
    function Policy.SafeDashDirection(direction,toAttacker)
        if typeof(direction)~="Vector3" or typeof(toAttacker)~="Vector3" then return false end
        local a=direction*Vector3.new(1,0,1)
        local b=toAttacker*Vector3.new(1,0,1)
        return a.Magnitude>0.1 and b.Magnitude>0.1 and a.Unit:Dot(b.Unit)<0.25
    end
    function Policy.DashDirections(movement,toAttacker,facing)
        local toward=toAttacker*Vector3.new(1,0,1)
        local away=toward.Magnitude>.1 and -toward.Unit or -facing*Vector3.new(1,0,1)
        if away.Magnitude<.1 then away=Vector3.new(0,0,1) end
        away=away.Unit
        local manual=movement*Vector3.new(1,0,1)
        local preferred=Policy.SafeDashDirection(manual,toward) and manual.Unit or away
        local side=Vector3.new(-away.Z,0,away.X)
        local result={}
        for _,direction in {preferred,away,side,-side} do
            local duplicate=false
            for _,old in result do if old:Dot(direction)>.99 then duplicate=true;break end end
            if not duplicate then result[#result+1]=direction end
        end
        return result
    end
    local function status(value)
        D.Status=value
        App.State.CombatStatus=value
    end
    local function physical(key)
        if typeof(key)~="EnumItem" then return false end
        local ok,down=pcall(App.S.UserInputService.IsKeyDown,App.S.UserInputService,key)
        return ok and down==true
    end
    local function finiteAttribute(object,key,now)
        local value=object:GetAttribute(key)
        return App.Finite(value) and value>now
    end
    local function nativeModules()
        if D.Native then return true end
        if D.ModuleFailure then return false end
        local ok,native=pcall(function()
            local input=require(App.Boxing:FindFirstChild("BoxingVirtualInput"))
            local geometry=require(App.Boxing:FindFirstChild("BoxingHitDetection"))
            local skills=require(App.Boxing:FindFirstChild("BoxingSkills"))
            assert(type(input)=="table" and type(input.Set)=="function" and type(input.Tap)=="function"
                and type(input.IsDown)=="function" and type(input.SetIntent)=="function","Input contract unavailable")
            assert(type(geometry)=="table" and type(geometry.PathFor)=="function"
                and type(geometry.Contact)=="function","Contact geometry unavailable")
            assert(type(skills)=="table" and type(skills.Has)=="function","Skill contract unavailable")
            return {Input=input,Geometry=geometry,Skills=skills}
        end)
        if not ok then D.ModuleFailure=tostring(native);status("Native defensive controls unavailable");return false end
        D.Native=native
        return true
    end
    local function setOwned(key,down)
        local input=D.Native and D.Native.Input
        if not input then return false end
        if down then
            if input.IsDown(key) then return false end
            D.Owned[key]=true
            local ok=pcall(input.Set,key,true)
            if not ok then D.Owned[key]=nil;return false end
            return true
        end
        if D.Owned[key] then
            D.Owned[key]=nil
            pcall(input.Set,key,false)
        end
        return true
    end
    local function releaseIntent()
        local input=D.Native and D.Native.Input
        if D.Intent and input then
            local _,humanoid=App.Character()
            local manual=humanoid and humanoid.MoveDirection or Vector3.zero
            if D.DriveCharacter==App.Player.Character and humanoid then
                if (manual-D.Intent).Magnitude<.05 then
                    manual=D.ManualMove or Vector3.zero
                    pcall(humanoid.Move,humanoid,manual,false)
                end
            end
            pcall(input.SetIntent,manual)
        end
        D.Intent=nil;D.DriveCharacter=nil;D.ManualMove=nil;D.DashHandoff=nil
        if intentBound then pcall(App.S.RunService.UnbindFromRenderStep,App.S.RunService,renderName);intentBound=false end
    end
    local function releaseHeld()
        -- Release only keys this runtime changed; the game's physical-key path
        -- remains active and may continue a manually held guard independently.
        setOwned("HeadBlock",false)
        setOwned("Block",false)
        setOwned("Weave",false)
        releaseIntent()
        D.Held=nil
    end
    local function ownIntent(direction,character,drive)
        if drive then
            local _,humanoid=App.Character()
            if not humanoid then return false end
            D.ManualMove=humanoid.MoveDirection
            D.DriveCharacter=character
            humanoid:Move(direction,false)
        end
        D.Intent=direction
        if intentBound then return true end
        intentBound=true
        App.S.RunService:BindToRenderStep(renderName,Enum.RenderPriority.Last.Value+3,function()
            if not App.Alive or not D.Intent or App.Player.Character~=character or not Policy.Enabled(App.State.Config) then return end
            local input=D.Native and D.Native.Input
            if D.DriveCharacter==character then
                local _,humanoid=App.Character()
                if humanoid then
                    if (humanoid.MoveDirection-D.Intent).Magnitude>.05 then D.ManualMove=humanoid.MoveDirection end
                    humanoid:Move(D.Intent,false)
                end
            end
            if input then pcall(input.SetIntent,D.Intent) end
        end)
        return true
    end
    App.Maid:Give(function() releaseHeld() end)

    local function blocked(character,humanoid)
        if not App.Alive or not Policy.Enabled(App.State.Config) then return "Off" end
        if App.Food and App.Food.IsBusy() then return "Eating" end
        if App.Session or App.PendingStart or App.Moving or App.State.Config.TrainingEnabled
            or (App.Player:GetAttribute("TrainingUI") or "")~="" or character:GetAttribute("Training")~=nil then
            return "Paused during training or travel"
        end
        if humanoid.Health<=0 or humanoid.Sit or humanoid.PlatformStand or character:GetAttribute("Downed")
            or character:GetAttribute("RingBreak") or character:GetAttribute("ClinchState")
            or character:GetAttribute("ClinchedBy") then return "Waiting for character recovery" end
        local now=workspace:GetServerTimeNow()
        for _,key in {"StunnedUntil","GuardBrokenUntil","FrozenUntil","CounterMissUntil"} do
            if finiteAttribute(character,key,now) then return "Waiting for character recovery" end
        end
        local localNow=os.clock()
        if finiteAttribute(App.Player,"TechniqueUntil",localNow) then return "Waiting for technique recovery" end
        local tool=character:FindFirstChildOfClass("Tool")
        if not tool or tool:GetAttribute("BoxingTool")~=true then return "Equip Boxing gloves" end
        if App.S.UserInputService:GetFocusedTextBox() then return "Paused while typing" end
        if App.MenuState then
            for _,key in {"IsOpen","Blocked"} do
                if type(App.MenuState[key])=="function" then
                    local ok,value=pcall(App.MenuState[key])
                    if not ok or value then return "Paused in game menu" end
                end
            end
        end
        local percent=App.Stamina()
        if not percent or percent<App.State.Config.CombatStaminaFloor then return "Saving stamina" end
    end
    local function allowedAttacker(attacker)
        if typeof(attacker)~="Instance" or not attacker:IsA("Model") or not attacker.Parent
            or attacker==App.Player.Character or attacker:GetAttribute("PunchingBag")==true then return false end
        local root=attacker:FindFirstChild("HumanoidRootPart")
        local humanoid=attacker:FindFirstChildOfClass("Humanoid")
        if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health<=0 then return false end
        local player=App.S.Players:GetPlayerFromCharacter(attacker)
        local tags=App.S.CollectionService
        local npc=tags:HasTag(attacker,"BoxingNPC") or tags:HasTag(attacker,"AIFighter") or tags:HasTag(attacker,"RankedBot")
        return Policy.Entity(player~=nil,npc,App.State.Config),root
    end
    local function contact(threat,character,root,now)
        local allowed,attackerRoot=allowedAttacker(threat.Attacker)
        if not allowed then return end
        local range=App.State.Config.CombatThreatRange
        if (attackerRoot.Position-root.Position).Magnitude>range then return end
        local lead=math.clamp(threat.ImpactAt-now,0,0.18)
        local attackerVelocity=attackerRoot.AssemblyLinearVelocity*Vector3.new(1,0,1)
        local ownVelocity=root.AssemblyLinearVelocity*Vector3.new(1,0,1)
        if attackerVelocity.Magnitude>60 then attackerVelocity=Vector3.zero end
        if ownVelocity.Magnitude>60 then ownVelocity=Vector3.zero end
        local attackerPose={Root=attackerRoot,CFrame=attackerRoot.CFrame+attackerVelocity*lead}
        local ownShift=CFrame.new(ownVelocity*lead)
        local ok,result=pcall(D.Native.Geometry.Contact,attackerPose,threat.Path,character,threat.Zone,false,
            -0.08,threat.Punch,nil,ownShift)
        return ok and result or nil,attackerRoot
    end
    local function manualGuard(character)
        local input=D.Native.Input
        local config=App.GameConfig
        return physical(config.BlockKey) or physical(config.HeadBlockKey)
            or input.IsDown("Block") and not D.Owned.Block
            or input.IsDown("HeadBlock") and not D.Owned.HeadBlock
            or character:GetAttribute("Blocking")==true and not D.Owned.Block and not D.Owned.HeadBlock
    end
    local function checkAcceptance(character,now)
        local pending=D.PendingAcceptance
        if not pending then return end
        if pending.Character~=character then
            D.PendingAcceptance=nil
            if pending.Kind=="Dash" then
                D.RejectedDodges+=1
                if pending.Threat then pending.Threat.Handled=false;pending.Threat.DashTried=true end
                releaseIntent()
            end
            return
        end
        local dashAt=App.Player:GetAttribute("HitMoveDashAt")
        local accepted=pending.Kind=="Weave" and (App.Player:GetAttribute("WeaveMode")==true or character:GetAttribute("Weaving")~=nil)
            or pending.Kind=="Dash" and (finiteAttribute(App.Player,"DashingUntil",now)
                or App.Finite(dashAt) and dashAt>=(pending.RequestedAt or math.huge))
            or pending.Kind=="Block" and character:GetAttribute("Blocking")==true
        if accepted then
            local key=pending.Kind=="Weave" and "AcceptedWeaves" or pending.Kind=="Dash" and "AcceptedDodges" or "AcceptedBlocks"
            D[key]+=1;D.PendingAcceptance=nil
            if pending.Kind=="Dash" and D.DashHandoff then
                D.DashHandoff.ReleaseAt=math.max(now,math.min(now+.8,tonumber(App.Player:GetAttribute("DashingUntil")) or now))
            end
        elseif now>pending.Expires then
            D.PendingAcceptance=nil
            if pending.Kind=="Dash" then
                D.RejectedDodges+=1
                if pending.Threat then pending.Threat.Handled=false;pending.Threat.DashTried=true end
                releaseIntent()
            end
        end
    end
    local function acted(kind,character,threat,releaseAt)
        threat.Handled=true
        D.PendingAcceptance={Kind=kind,Character=character,Threat=threat,Expires=os.clock()+(kind=="Dash" and .16 or .25),
            RequestedAt=kind=="Dash" and D.DashHandoff and D.DashHandoff.RequestedAt or nil}
        if kind~="Dash" then D.Held={Kind=kind,Character=character,ReleaseAt=releaseAt,Zone=threat.Zone} end
    end
    local function tryWeave(threat,character,humanoid,root,now)
        if not App.State.Config.AutoWeave or now<D.NextWeave or not Policy.CanWeave(threat.Punch,threat.Zone,App.GameConfig.Weave)
            or manualGuard(character) or physical(App.GameConfig.Weave.Key) or D.Native.Input.IsDown("Weave") then return false end
        local ok,hasSkill=pcall(D.Native.Skills.Has,App.Player,"Weaving")
        if not ok or not hasSkill then return false end
        if finiteAttribute(App.Player,"DashingUntil",now) or finiteAttribute(App.Player,"PunchLockedUntil",now) then return false end
        ownIntent(-root.CFrame.LookVector*Vector3.new(1,0,1),character)
        D.Native.Input.SetIntent(D.Intent)
        if not setOwned("Weave",true) then releaseIntent();return false end
        D.NextWeave=now+math.max(0.6,tonumber(App.GameConfig.Weave.IframeCooldown) or 1)
        D.Weaves+=1
        acted("Weave",character,threat,math.clamp(threat.ImpactAt+0.09,now+0.12,now+0.35))
        status("Auto Weave input · head attack")
        return true
    end
    local function tryDash(threat,character,humanoid,root,attackerRoot,now)
        if not App.State.Config.AutoDodge or threat.DashTried or now<D.NextDash or manualGuard(character)
            or D.Native.Input.IsDown("Weave") or physical(App.GameConfig.Weave.Key)
            or App.Player:GetAttribute("WeaveMode")==true then return false end
        local loadout=App.Player:GetAttribute("Loadout")
        local ok,value=pcall(App.S.HttpService.JSONDecode,App.S.HttpService,type(loadout)=="string" and loadout or "{}")
        if not ok or type(value)~="table" or type(value.Dash)~="string" then return false end
        local settings=App.GameConfig.DashSettings(value.Dash)
        if type(settings)~="table" or (character:GetAttribute("Stamina") or 0)<(settings.StaminaCost or 12) then return false end
        local lastDash=App.Player:GetAttribute("HitMoveDashAt")
        if App.Finite(lastDash) and now-lastDash<(tonumber(settings.Cooldown) or .8) then return false end
        local parameters=RaycastParams.new()
        parameters.FilterType=Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances={character,attackerRoot.Parent}
        parameters.RespectCanCollide=true
        local movement
        for _,direction in Policy.DashDirections(humanoid.MoveDirection,attackerRoot.Position-root.Position,root.CFrame.LookVector) do
            if not workspace:Blockcast(root.CFrame,Vector3.new(1.8,2.8,0.8),direction*4,parameters) then
                movement=direction;break
            end
        end
        if not movement then return false end
        -- Dash reads MoveDirection before virtual intent. Own both briefly so
        -- deferred native input cannot see a cleared or forward-chasing vector.
        if not ownIntent(movement,character,true) then return false end
        D.Native.Input.SetIntent(movement)
        D.DashHandoff={Character=character,RequestedAt=os.clock(),ReleaseAt=now+.2}
        local tapped=pcall(D.Native.Input.Tap,"Dash")
        if not tapped then releaseIntent();return false end
        D.LastDashDirection=movement
        D.NextDash=now+math.max(0.3,tonumber(settings.Cooldown) or 0.8)
        D.Dodges+=1;acted("Dash",character,threat)
        status("Auto Dodge input · native dash")
        return true
    end
    local function tryBlock(threat,character,now)
        if not App.State.Config.AutoBlock or manualGuard(character) or D.Native.Input.IsDown("Weave")
            or App.Player:GetAttribute("WeaveMode")==true or (character:GetAttribute("BlockStamina") or 0)<=0 then return false end
        if finiteAttribute(App.Player,"DashingUntil",now) then return false end
        if not setOwned("Block",true) then return false end
        if threat.Zone=="Head" then setOwned("HeadBlock",true) end
        D.Blocks+=1
        acted("Block",character,threat,math.clamp(threat.ImpactAt+0.15,now+0.15,now+0.5))
        status("Auto Block input · "..threat.Zone)
        return true
    end
    function App.OnCombatEvent(action,attacker,punchName,scale,zone,jammed,special)
        if not App.Alive or not Policy.Enabled(App.State.Config) then return end
        local character=App.Player.Character
        if action=="WeaveDodge" or action=="Dodge" or action=="PerfectDodge" then
            if attacker==character then D.ConfirmedDodges+=1 end
            return
        end
        if action=="Hit" then
            if attacker==character and scale==true then D.ConfirmedBlocks+=1 end
            return
        end
        if action~="Punch" or not nativeModules() then return end
        local allowed,root=allowedAttacker(attacker)
        local _,_,ownRoot=App.Character()
        if not allowed or not ownRoot or (root.Position-ownRoot.Position).Magnitude>App.State.Config.CombatThreatRange then return end
        local punch=type(punchName)=="string" and App.GameConfig.Punches[punchName]
        if type(punch)~="table" or jammed==true then return end
        zone=type(special)=="table" and special.Zone or zone
        zone=App.GameConfig.PunchZone(punchName,zone)
        if zone~="Head" and zone~="Body" then return end
        local hitTime=punch.HitTime
        if type(App.GameConfig.PunchAnimation)=="function" then
            local ok,_,time=pcall(App.GameConfig.PunchAnimation,punchName,zone,attacker)
            if ok and App.Finite(time) and time>0 then hitTime=time end
        end
        local options
        if type(special)=="table" then
            if App.Finite(special.HitTime) and special.HitTime>0 then hitTime=special.HitTime end
            options={AnimId=special.AnimId,Time=special.HitTime,Reach=special.Reach,Points=special.Points}
        end
        local received=os.clock()
        local impact,react,expires=Policy.Timing(received,hitTime,scale,App.State.Config.CombatReactionDelay)
        if not impact then return end
        local ok,path=pcall(D.Native.Geometry.PathFor,attacker,punchName,zone,punch,options)
        if not ok or type(path)~="table" or #path==0 or #path>600 then return end
        -- Coalesce repeated copies of the same announcement, not distinct combos.
        for _,previous in D.Threats do
            if previous.Attacker==attacker and previous.Name==punchName and received-previous.Received<0.04 then return end
        end
        D.Serial+=1
        D.Threats[#D.Threats+1]={Id=D.Serial,Attacker=attacker,Name=punchName,Punch=punch,Path=path,
            Options=options,Zone=zone,Received=received,ImpactAt=impact,ReactAt=react,Expires=expires}
        while #D.Threats>24 do table.remove(D.Threats,1) end
    end
    function App.StopCombat(reason)
        releaseHeld()
        table.clear(D.Threats)
        D.PendingAcceptance=nil
        status(reason or "Off")
    end
    function App.ReconcileCombat(changed)
        local relevant=false
        for _,key in {"AutoWeave","AutoDodge","AutoBlock","CombatPlayers","CombatNPCs","CombatStaminaFloor"} do
            if changed[key] then relevant=true;break end
        end
        if relevant then
            App.StopCombat(Policy.Enabled(App.State.Config) and "Waiting for incoming punches" or "Off")
            D.ModuleFailure=nil
        end
    end
    local function step()
        if not App.Alive then return end
        local character,humanoid,root=App.Character()
        local reason=not character and "Waiting for character" or blocked(character,humanoid)
        if reason then
            releaseHeld();table.clear(D.Threats);D.PendingAcceptance=nil;status(reason);return
        end
        if not nativeModules() then return end
        local now=os.clock()
        checkAcceptance(character,now)
        local handoff=D.DashHandoff
        if handoff and (handoff.Character~=character or now>=handoff.ReleaseAt) then releaseIntent() end
        local held=D.Held
        if held then
            local enabled=held.Kind=="Weave" and App.State.Config.AutoWeave or held.Kind=="Block" and App.State.Config.AutoBlock
            if held.Character~=character or not enabled or now>=held.ReleaseAt then releaseHeld() end
        end
        for index=#D.Threats,1,-1 do
            if Policy.Window(D.Threats[index],now)=="expired" then table.remove(D.Threats,index) end
        end
        if D.Held or D.PendingAcceptance or finiteAttribute(App.Player,"DashingUntil",now) then return end
        if now-lastScan<0.025 then return end
        lastScan=now
        local best,attackerRoot
        for _,threat in D.Threats do
            if not threat.Handled and Policy.Window(threat,now)=="ready" and (not best or threat.ImpactAt<best.ImpactAt) then
                local hit,attackingRoot=contact(threat,character,root,now)
                if hit then best,attackerRoot=threat,attackingRoot end
            end
        end
        if not best then status("Waiting for incoming punches");return end
        if tryWeave(best,character,humanoid,root,now) then return end
        if tryDash(best,character,humanoid,root,attackerRoot,now) then return end
        tryBlock(best,character,now)
    end
    function App.StepCombat()
        local ok,message=xpcall(step,debug.traceback)
        if not ok then
            D.Errors+=1;D.LastError=tostring(message)
            App.StopCombat("Defense stopped · input error")
            App.Set("AutoWeave",false);App.Set("AutoDodge",false);App.Set("AutoBlock",false)
            status("Defense stopped · input error")
        end
    end
    function App.GetCombatSnapshot()
        return {Status=D.Status,Weaves=D.Weaves,Dodges=D.Dodges,Blocks=D.Blocks,
            AcceptedWeaves=D.AcceptedWeaves,AcceptedDodges=D.AcceptedDodges,AcceptedBlocks=D.AcceptedBlocks,
            ConfirmedDodges=D.ConfirmedDodges,ConfirmedBlocks=D.ConfirmedBlocks,Errors=D.Errors,
            RejectedDodges=D.RejectedDodges,LastDashDirection=D.LastDashDirection,
            LastError=D.LastError,Threats=#D.Threats,Inputs=D.Weaves+D.Dodges+D.Blocks}
    end
end

-- Food identity, nutrition and shop requests come from the native Boxing config.
-- The verified consume path is Humanoid:EquipTool(food), then food:Activate().
do
    local Food={}
    App.Food=Food
    local foods=App.GameConfig.Foods or {}
    local shops=App.GameConfig.Shops or {}
    local remote=App.Boxing:FindFirstChild("SurvivalRemote")
    local active,cycle
    local generation,cooldown=0,0
    local destroyed=false
    local status,item,eaten,spent="Off","--",0,0
    local connections={}
    local function live() return App.Alive and not destroyed end
    local function foodInfo(name)
        local info=type(name)=="string" and foods[name]
        if type(info)=="table" and ((tonumber(info.Hunger) or 0)>0 or (tonumber(info.Energy) or 0)>0) then return info end
    end
    function Food.Options()
        local result={}
        for name in foods do if foodInfo(name) then result[#result+1]=name end end
        table.sort(result);table.insert(result,1,"Auto")
        return result
    end
    local function inventory(name)
        local selected,total
        total=0
        for _,container in {App.Player.Character,App.Player:FindFirstChildOfClass("Backpack")} do
            if container then for _,tool in container:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("FoodItem")==name and foodInfo(name) then
                    local count=tonumber(tool:GetAttribute("Count"))
                    if count and count>0 then total+=count;selected=selected or tool end
                end
            end end
        end
        return selected,total
    end
    local function owned(tool)
        local backpack=App.Player:FindFirstChildOfClass("Backpack")
        local character=App.Player.Character
        return tool and (character and tool.Parent==character or backpack and tool.Parent==backpack)
    end
    local function resource(name)
        local value=App.Player:GetAttribute(name)
        return App.Finite(value) and value or nil
    end
    local function needs()
        local config=App.State.Config
        local hunger,energy=resource("Hunger"),resource("Energy")
        return hunger and hunger<=config.FoodLow or false,
            config.EnergyFloor>0 and energy and energy<config.EnergyFloor or false
    end
    local function pendingNeeds()
        if not cycle then return false,false end
        local hunger,energy=resource("Hunger"),resource("Energy")
        return cycle.Hunger and (not hunger or hunger<App.State.Config.FoodTarget) or false,
            cycle.Energy and App.State.Config.EnergyFloor>0 and (not energy or energy<cycle.EnergyGoal) or false
    end
    local function nativeBusy(character)
        local activity=App.Player:GetAttribute("TrainingUI")
        local training=character and character:GetAttribute("Training")
        return type(activity)=="string" and activity~="" or training~=nil and training~=false
    end
    local function restoreEquipment(record)
        if not record or not record.Equipped or App.Player.Character~=record.Character then return end
        local character,humanoid=App.Character()
        if not character then return end
        local current=character:FindFirstChildOfClass("Tool")
        -- A manually selected replacement tool belongs to the player.
        if current and current~=record.Tool then return end
        pcall(function()
            if current==record.Tool then humanoid:UnequipTools() end
            local backpack=App.Player:FindFirstChildOfClass("Backpack")
            for _,tool in record.Previous or {} do
                if backpack and tool.Parent==backpack then humanoid:EquipTool(tool) end
            end
        end)
        record.Equipped=false
    end
    local function release(reason,delay)
        local old=active
        generation+=1;active=nil
        if old then
            if old.Move and App.Moving==old.Move then App.CancelMove() end
            restoreEquipment(old)
            App.State.NextStart=math.max(App.State.NextStart or 0,os.clock()+.5)
            App.State.Status=App.State.Config.TrainingEnabled and "Resuming training" or (reason or "Ready")
        end
        if delay then cooldown=math.max(cooldown,os.clock()+delay) end
        status=reason or "Ready"
    end
    function Food.Stop(reason)
        reason=reason or (App.State.Config.AutoFood and "Waiting for character" or "Off")
        release(reason,reason=="Manual travel" and 20 or nil)
    end
    function Food.IsBusy() return live() and active~=nil end
    local function current(record)
        local character=App.Character()
        return live() and App.State.Config.AutoFood and active==record and record.Generation==generation
            and character==record.Character
    end
    local function useful(name,hungerNeed,energyNeed)
        local info=foodInfo(name)
        if not info then return false end
        if hungerNeed and (tonumber(info.Hunger) or 0)<=0 then return false end
        if not hungerNeed and energyNeed and (tonumber(info.Energy) or 0)<=0 then return false end
        return true
    end
    local function choices(hungerNeed,energyNeed)
        local selected=App.State.Config.FoodItem
        if selected~="Auto" then return useful(selected,hungerNeed,energyNeed) and {selected} or {} end
        local result={}
        local preferred=hungerNeed and "Tomato" or "Energy Drink"
        if useful(preferred,hungerNeed,energyNeed) then result[#result+1]=preferred end
        if preferred~="Tomato" and useful("Tomato",hungerNeed,energyNeed) then result[#result+1]="Tomato" end
        for _,name in Food.Options() do
            local info=foodInfo(name)
            if name~=preferred and name~="Tomato" and info and (tonumber(info.Stamina) or 0)>=0
                and useful(name,hungerNeed,energyNeed) then result[#result+1]=name end
        end
        return result
    end
    local function promptPosition(prompt)
        local parent=prompt.Parent
        if parent and parent:IsA("Attachment") then return parent.WorldPosition end
        if parent and parent:IsA("BasePart") then return parent.Position end
    end
    local function shopFor(name,root)
        local counters=workspace:FindFirstChild("ShopCounters")
        if not counters then return end
        local best,distance
        for _,prompt in counters:QueryDescendants("ProximityPrompt[$ShopId]") do
            if not prompt.Enabled then continue end
            local id=prompt:GetAttribute("ShopId")
            local config=type(id)=="string" and type(shops.List)=="table" and shops.List[id]
            local position=promptPosition(prompt)
            if type(config)=="table" and type(config.Items)=="table" and position then
                for _,entry in config.Items do
                    if type(entry)=="table" and entry[1]==name and App.Finite(entry[2]) and entry[2]>=0 then
                        local delta=(root.Position-position).Magnitude
                        if not distance or delta<distance then
                            best={Id=id,Name=name,Price=entry[2],Prompt=prompt,Position=position,
                                Range=math.min(tonumber(shops.InteractDistance) or 8,prompt.MaxActivationDistance)}
                            distance=delta
                        end
                    end
                end
            end
        end
        return best,distance
    end
    local function pick(hungerNeed,energyNeed,root)
        local available=choices(hungerNeed,energyNeed)
        for _,name in available do
            local tool=inventory(name)
            if tool then return {Name=name,Tool=tool} end
        end
        if #available==0 then return nil,"Selected food does not restore the needed resource" end
        if not App.State.Config.AutoBuyFood then return nil,"Out of food · Auto Buy is off" end
        local cash=resource("Cash")
        if not cash then return nil,"Waiting for cash data" end
        local budget=(cycle and cycle.Spent or 0)
        local failed="No matching food shop is loaded"
        for _,name in available do
            local shop,distance=shopFor(name,root)
            if shop then
                if shop.Price+budget>App.State.Config.FoodBudget then failed="Refill budget reached · buy food manually or raise the budget"
                elseif shop.Price>cash then failed="Not enough cash for "..name
                elseif not App.State.Config.AutoMove and distance>shop.Range then failed="Move closer to a food shop or enable Auto Move"
                else return {Name=name,Shop=shop} end
            end
        end
        return nil,failed
    end
    local function acknowledge(pending)
        if pending.Counted then return end
        pending.Counted=true;spent+=pending.Price
    end
    local function pollPurchase(now)
        local pending=cycle and cycle.Pending
        if not pending then return end
        if pending.Result==false then
            if not pending.Refunded then cycle.Spent=math.max(0,cycle.Spent-pending.Price);pending.Refunded=true end
            cycle.Pending=nil
            return "rejected",pending.Message or "Food purchase rejected"
        end
        local _,count=inventory(pending.Name)
        if count>pending.BeforeCount then
            local cash=resource("Cash")
            if pending.Result==true or cash and pending.BeforeCash-cash>=pending.Price then acknowledge(pending) end
            cycle.Pending=nil
            return "delivered"
        end
        if pending.Result==true then acknowledge(pending) end
        if now-pending.Sent>8 then return "unknown","Waiting for purchased "..pending.Name.." · no duplicate request sent" end
        return "waiting"
    end
    if remote and remote:IsA("RemoteEvent") then
        connections[#connections+1]=remote.OnClientEvent:Connect(function(action,ok,message,name)
            local pending=cycle and cycle.Pending
            if destroyed or action~="BuyResult" or not pending or name~=pending.Name or type(ok)~="boolean" then return end
            pending.Result=ok;pending.Message=tostring(message or "")
            if ok then acknowledge(pending) end
        end)
    end
    local function begin(plan,character,now)
        -- Preserve the toggle while releasing only this hub's training/input work.
        App.StopTraining("Preparing food")
        if App.StopCombat then App.StopCombat() end
        generation+=1
        local previous={}
        for _,tool in character:GetChildren() do if tool:IsA("Tool") then previous[#previous+1]=tool end end
        active={Generation=generation,Character=character,Stage="WaitTraining",Deadline=now+9,
            Plan=plan,Previous=previous,NextEat=now}
        item=plan.Name;status="Pausing training for food"
    end
    function Food.Step(now)
        if not live() then return false end
        now=now or os.clock()
        local config=App.State.Config
        local hungerNeed,energyNeed=pendingNeeds()
        if cycle and not hungerNeed and not energyNeed and not (active and active.Stage=="Eating") then
            release("Food target reached");cycle=nil
        end
        if not config.AutoFood then
            if active then release("Off") end
            status="Off";return false
        end
        local character,humanoid,root=App.Character()
        if not character or App.Player:GetAttribute("GameLoaded")~=true then
            if active then release("Waiting for character") end
            status="Waiting for character";return false
        end
        local purchase,message=pollPurchase(now)
        if purchase=="rejected" then release(message,10);return false end
        if purchase=="unknown" then release(message,10);return false end
        if not cycle then
            local lowHunger,lowEnergy=needs()
            if not lowHunger and not lowEnergy then status="Monitoring hunger and energy";return false end
            if not resource("Hunger") or not resource("Energy") then status="Waiting for survival data";return false end
            cycle={Hunger=lowHunger,Energy=lowEnergy,EnergyGoal=math.min(100,math.max(config.EnergyFloor+5,20)),Spent=0}
        end
        hungerNeed,energyNeed=pendingNeeds()
        if active and not current(active) then release("Food interrupted",3);return false end
        if now<cooldown and not active then return false end
        if not active then
            if cycle.Pending then status="Waiting for purchased "..cycle.Pending.Name;return false end
            local training=App.Session and App.Session.Owned or App.PendingStart and not App.PendingStart.Canceled
            if App.Moving and not training then status="Waiting for current travel";return false end
            if nativeBusy(character) and not training then status="Finish the manual activity before Auto Food";return false end
            local plan,reason=pick(hungerNeed,energyNeed,root)
            if not plan then status=reason;cooldown=now+1;return false end
            begin(plan,character,now)
            return true
        end
        local record=active
        App.State.Status=status
        if record.Stage=="WaitTraining" then
            if nativeBusy(character) or App.AwaitingEnd and now<App.AwaitingEnd then
                if now>=record.Deadline then release("Waiting for the training session to end",5);return false end
                return true
            end
            record.Stage="Choose"
        end
        if record.Stage=="Choose" then
            if now<record.NextEat then return true end
            local plan,reason=pick(hungerNeed,energyNeed,root)
            if not plan then release(reason,3);return false end
            record.Plan=plan;item=plan.Name
            if plan.Tool then
                record.Tool=plan.Tool
                if not owned(record.Tool) then release("Food no longer in inventory",3);return false end
                local equipped=pcall(humanoid.EquipTool,humanoid,record.Tool)
                if not equipped then release("Unable to equip food",5);return false end
                record.Equipped=true;record.Stage="Equip";record.ReadyAt=now+.25
                status="Preparing "..plan.Name
            else
                record.Shop=plan.Shop
                local distance=(root.Position-plan.Shop.Position).Magnitude
                if distance<=plan.Shop.Range then record.Stage="Buy"
                else
                    record.Stage="Travel";status="Travelling to buy "..plan.Name
                    local started=App.Move({Position=plan.Shop.Position},function(arrived)
                        if not current(record) then return end
                        record.Arrived=arrived;record.Stage=arrived and "Buy" or "RouteFailed"
                    end)
                    record.Move=App.Moving
                    if not started then release("Unable to reach the food shop",10);return false end
                end
            end
            return true
        end
        if record.Stage=="RouteFailed" then release("Food shop route failed",10);return false end
        if record.Stage=="Travel" then
            if not record.Move or App.Moving~=record.Move then release("Food route interrupted · retrying later",3);return false end
            return true
        end
        if record.Stage=="Buy" then
            if not config.AutoBuyFood then release("Auto Buy is off");return false end
            local shop=record.Shop
            if not shop.Prompt.Parent or (root.Position-shop.Position).Magnitude>shop.Range then release("Move closer to the food shop",10);return false end
            if not remote or not remote:IsA("RemoteEvent") then release("Food shop remote unavailable",10);return false end
            local cash=resource("Cash")
            if not cash or cash<shop.Price or cycle.Spent+shop.Price>config.FoodBudget then release("Food cash or refill budget limit reached",5);return false end
            local _,count=inventory(shop.Name)
            local pending={Name=shop.Name,Price=shop.Price,BeforeCount=count,BeforeCash=cash,Sent=now}
            cycle.Spent+=shop.Price;cycle.Pending=pending
            local sent=App.Send(remote,"Buy",shop.Id,shop.Name)
            if not sent then
                cycle.Spent=math.max(0,cycle.Spent-shop.Price);cycle.Pending=nil
                release("Food purchase request unavailable",10);return false
            end
            record.Stage="Purchase";status="Buying "..shop.Name
            return true
        end
        if record.Stage=="Purchase" then
            if not cycle.Pending then record.Stage="Choose";record.NextEat=now+.1 end
            return true
        end
        if record.Stage=="Equip" then
            if now<record.ReadyAt then return true end
            if record.Tool.Parent~=character then release("Food equipment changed",5);return false end
            if nativeBusy(character) then release("Finish the current activity before eating",5);return false end
            record.Before={Hunger=resource("Hunger"),Energy=resource("Energy"),Count=tonumber(record.Tool:GetAttribute("Count")) or 1}
            record.Stage="Eating";record.EatDeadline=now+3
            local activated=pcall(record.Tool.Activate,record.Tool)
            if not activated then release("Food activation unavailable",10);return false end
            status="Eating "..record.Plan.Name
            return true
        end
        if record.Stage=="Eating" then
            local before=record.Before
            local hunger,energy=resource("Hunger"),resource("Energy")
            local used=not owned(record.Tool) or (tonumber(record.Tool:GetAttribute("Count")) or 0)<before.Count
            local restored=hunger and before.Hunger and hunger>before.Hunger or energy and before.Energy and energy>before.Energy
            if used and restored then
                eaten+=1;record.Stage="Choose"
                record.NextEat=now+math.max(tonumber(App.GameConfig.Survival.EatCooldown) or 1,1)+.2
                status="Ate "..record.Plan.Name
                return true
            end
            if now>=record.EatDeadline then release("Food use was not confirmed · retrying later",15);return false end
            return true
        end
        return true
    end
    function Food.Reconcile(changed)
        if destroyed then return end
        if changed.AutoFood or changed.AutoBuyFood or changed.FoodLow or changed.FoodTarget
            or changed.FoodItem or changed.FoodBudget or changed.EnergyFloor or changed.MoveMode or changed.AutoMove then
            Food.Stop(App.State.Config.AutoFood and "Monitoring hunger and energy" or "Off")
            if cycle then cycle.EnergyGoal=math.min(100,math.max(App.State.Config.EnergyFloor+5,20)) end
        end
    end
    function Food.Snapshot()
        return {Status=status,Item=item,Eaten=eaten,Spent=spent,CycleSpent=cycle and cycle.Spent or 0}
    end
    function Food.Destroy()
        if destroyed then return end
        Food.Stop("Off");destroyed=true
        for _,connection in connections do connection:Disconnect() end
        table.clear(connections)
    end
    App.Maid:Give(Food.Destroy)
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
        local pageNames = {"Dashboard", "Training", "World & Quests", "Combat", "Player & QoL", "Configs & Settings"}
        local shortNames = {Dashboard="Home",Training="Train",["World & Quests"]="World",["Player & QoL"]="Player",["Configs & Settings"]="Config",Combat="Fight"}
        local responsiveCallbacks = {}
        local compact, touchMode, preview, layoutWidth, layoutHeight = false, S.UserInputService.TouchEnabled, nil, 800, 590
        local refreshLayout, updateVisibility, scrollFocused, navLayout
        local function responsive(callback)
            table.insert(responsiveCallbacks,callback)
            callback()
        end

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
            local object = create("TextLabel", {
                BackgroundTransparency = 1, BorderSizePixel = 0, Text = value or "", TextColor3 = color or P.Text,
                Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize = size or 13,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
                Size = UDim2.new(1, 0, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd,
            }, parent)
            object:SetAttribute("BaseTextSize",size or 13)
            object:SetAttribute("MutedText",color==P.Muted)
            return object
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
            local button = create("TextButton", {Text = caption, TextSize = 14, Font = Enum.Font.GothamMedium,
                TextColor3 = P.Text, BackgroundColor3 = P.Control, BorderSizePixel = 0,
                TextWrapped=true, Size = UDim2.new(1, 0, 0, 46)}, parent)
            button:SetAttribute("ControlType","Action")
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
            text(frame, title, 16, P.Text, true)
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
                TextColor3 = P.Text, TextSize = 14, Font = Enum.Font.Gotham,
                ClearTextOnFocus = false, Size = UDim2.new(1, 0, 0, 44)}, parent)
            box:SetAttribute("ControlType","TextInput")
            corners(box, 8)
            outline(box)
            watch(box.Focused,function()
                if refreshLayout then refreshLayout() end
                App.Maid:Delay(0.22,function() if scrollFocused then scrollFocused(box) end end)
            end)
            return box
        end
        local function set(key, value)
            local ok, message = App.Set(key, value)
            if ok == false and message then App.Notify(message, "error") end
        end
        local function toggle(parent, caption, key, detail)
            local frame=create("TextButton",{Name="Toggle_"..key,Text="",AutoButtonColor=false,
                BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,0,0,56)},parent)
            frame:SetAttribute("ControlType","Toggle")
            frame:SetAttribute("ControlKey",key)
            local label=text(frame,caption,14)
            label.Size=UDim2.new(1,-74,0,24)
            label.TextWrapped=true
            label.TextTruncate=Enum.TextTruncate.None
            label.AutomaticSize=Enum.AutomaticSize.Y
            local sub
            if detail then
                sub=text(frame,detail,12,P.Muted)
                sub.Size=UDim2.new(1,-74,0,18)
                sub.TextWrapped=true
                sub.TextTruncate=Enum.TextTruncate.None
                sub.AutomaticSize=Enum.AutomaticSize.Y
            end
            local pill=create("Frame",{BackgroundColor3=P.Control,BorderSizePixel=0,
                AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,0,0.5,0),Size=UDim2.fromOffset(54,32)},frame)
            corners(pill,16)
            local knob=create("Frame",{BackgroundColor3=P.Muted,BorderSizePixel=0,
                Position=UDim2.fromOffset(4,4),Size=UDim2.fromOffset(24,24)},pill)
            corners(knob,12)
            local function fit()
                local labelHeight=math.max(24,label.TextBounds.Y)
                if sub then
                    sub.Position=UDim2.fromOffset(0,labelHeight+4)
                    frame.Size=UDim2.new(1,0,0,math.max(64,labelHeight+math.max(18,sub.TextBounds.Y)+12))
                else frame.Size=UDim2.new(1,0,0,math.max(52,labelHeight+12)) end
            end
            local function update(value)
                App.Tween(pill,{BackgroundColor3=value and P.Accent or P.Control},0.15)
                App.Tween(knob,{Position=UDim2.fromOffset(value and 26 or 4,4),
                    BackgroundColor3=value and P.Text or P.Muted},0.15)
            end
            interactive(frame,function()set(key,not C[key])end,nil,true)
            watch(label:GetPropertyChangedSignal("TextBounds"),fit)
            if sub then watch(sub:GetPropertyChangedSignal("TextBounds"),fit) end
            App.Bind(key,update)
            themed(function()update(C[key])end)
            responsive(fit)
        end
        local function slider(parent, caption, key, minimum, maximum, step, suffix)
            local frame=row(parent,100)
            frame.Name="Slider_"..key
            frame:SetAttribute("ControlType","Slider")
            frame:SetAttribute("ControlKey",key)
            local label=text(frame,caption,14)
            label.Size=UDim2.new(1,-104,0,44)
            label.TextWrapped=true
            label.TextTruncate=Enum.TextTruncate.None
            local numeric=input(frame,"","")
            numeric.Name="Value"
            numeric.AnchorPoint=Vector2.new(1,0)
            numeric.Position=UDim2.fromScale(1,0)
            numeric.Size=UDim2.fromOffset(96,44)
            numeric:SetAttribute("ControlKey",key)
            local track=create("TextButton",{Name="TouchRail",Text="",BackgroundTransparency=1,BorderSizePixel=0,
                Size=UDim2.new(1,0,0,44),Position=UDim2.fromOffset(0,50),AutoButtonColor=false},frame)
            track:SetAttribute("ControlType","SliderTouchRail")
            track:SetAttribute("ControlKey",key)
            local rail=create("Frame",{BackgroundColor3=P.Control,BorderSizePixel=0,
                AnchorPoint=Vector2.new(0,0.5),Position=UDim2.fromScale(0,0.5),Size=UDim2.new(1,0,0,6)},track)
            corners(rail,3)
            local fill=create("Frame",{BackgroundColor3=P.Accent,BorderSizePixel=0,Size=UDim2.new(0,0,1,0)},rail)
            corners(fill,3)
            local glow=create("Frame",{BackgroundColor3=P.Accent,BackgroundTransparency=0.8,BorderSizePixel=0,
                AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0,0.5),Size=UDim2.fromOffset(30,30)},track)
            corners(glow,15)
            local handle=create("Frame",{BackgroundColor3=P.Text,BorderSizePixel=0,
                AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0,0.5),Size=UDim2.fromOffset(20,20)},track)
            corners(handle,10)
            local dragging,dragInput,startPosition,vertical,lockedScroll,lockedWasEnabled=false,nil,nil,false,nil,true
            local function format(value)
                if step>=1 then return string.format("%.0f",value) end
                if step>=0.1 then return string.format("%.1f",value) end
                if step>=0.01 then return string.format("%.2f",value) end
                return string.format("%.3f",value)
            end
            local function update(value)
                local ratio=math.clamp(((tonumber(value) or minimum)-minimum)/(maximum-minimum),0,1)
                App.Tween(fill,{Size=UDim2.new(ratio,0,1,0)},0.15)
                App.Tween(handle,{Position=UDim2.fromScale(ratio,0.5)},0.15)
                App.Tween(glow,{Position=UDim2.fromScale(ratio,0.5)},0.15)
                if not numeric:IsFocused() then numeric.Text=format(value)..(suffix or "") end
            end
            local function fromPosition(position)
                if track.AbsoluteSize.X<=0 then return end
                local ratio=math.clamp((position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
                local value=minimum+ratio*(maximum-minimum)
                set(key,math.clamp(math.floor(value/step+0.5)*step,minimum,maximum))
            end
            local function finish()
                if lockedScroll and lockedScroll.Parent then lockedScroll.ScrollingEnabled=lockedWasEnabled end
                lockedScroll=nil;dragging=false;dragInput=nil;startPosition=nil;vertical=false
                App.Tween(glow,{BackgroundTransparency=0.8},0.15)
            end
            App.Maid:Give(finish)
            local function beginDrag()
                dragging=true
                lockedScroll=frame:FindFirstAncestorWhichIsA("ScrollingFrame")
                if lockedScroll then lockedWasEnabled=lockedScroll.ScrollingEnabled;lockedScroll.ScrollingEnabled=false end
                App.Tween(glow,{BackgroundTransparency=0.55},0.15)
            end
            watch(track.InputBegan,function(event)
                if event.UserInputType~=Enum.UserInputType.MouseButton1 and event.UserInputType~=Enum.UserInputType.Touch then return end
                finish();dragInput=event;startPosition=event.Position
                if event.UserInputType==Enum.UserInputType.MouseButton1 then beginDrag();fromPosition(event.Position) end
            end)
            watch(S.UserInputService.InputChanged,function(event)
                if not dragInput or (event~=dragInput and event.UserInputType~=Enum.UserInputType.MouseMovement) then return end
                if event.UserInputState==Enum.UserInputState.Cancel then finish();return end
                if not dragging and not vertical then
                    local delta=event.Position-startPosition
                    if math.abs(delta.Y)>8 and math.abs(delta.Y)>math.abs(delta.X) then vertical=true
                    elseif math.abs(delta.X)>8 and math.abs(delta.X)>math.abs(delta.Y) then beginDrag() end
                end
                if dragging then fromPosition(event.Position) end
            end)
            watch(S.UserInputService.InputEnded,function(event)
                if not dragInput then return end
                if event==dragInput or event.UserInputType==Enum.UserInputType.MouseButton1 then
                    if not dragging and not vertical and startPosition and (event.Position-startPosition).Magnitude<8 then fromPosition(event.Position) end
                    finish()
                end
            end)
            watch(S.UserInputService.WindowFocusReleased,finish)
            watch(numeric.Focused,function()numeric.Text=format(C[key])end)
            watch(numeric.FocusLost,function()
                local value=tonumber(numeric.Text)
                if value then set(key,math.clamp(math.floor(value/step+0.5)*step,minimum,maximum)) end
                numeric.Text=format(C[key])..(suffix or "")
            end)
            App.Bind(key,update)
            themed(function()fill.BackgroundColor3=P.Accent;glow.BackgroundColor3=P.Accent end)
        end
        local function dropdown(parent, caption, key, options)
            local frame = row(parent, 80)
            frame.Name="Dropdown_"..key
            frame:SetAttribute("ControlType","Dropdown")
            frame:SetAttribute("ControlKey",key)
            text(frame, caption, 12, P.Muted).Size = UDim2.new(1, 0, 0, 22)
            local header = create("TextButton", {Text = "", BackgroundColor3 = P.Control, BorderSizePixel = 0,
                Name="Open", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 44)}, frame)
            corners(header, 8)
            outline(header)
            header:SetAttribute("ControlType","DropdownButton")
            header:SetAttribute("ControlKey",key)
            local valueText = text(header, "", 14)
            valueText.Position = UDim2.fromOffset(12, 0)
            valueText.Size = UDim2.new(1, -42, 1, 0)
            local chevron = text(header, "+", 17, P.Muted)
            chevron.AnchorPoint = Vector2.new(1, 0)
            chevron.Position = UDim2.new(1, -10, 0, 0)
            chevron.Size = UDim2.new(0, 18, 1, 0)
            chevron.TextXAlignment = Enum.TextXAlignment.Center
            local panel = create("Frame", {BackgroundColor3 = P.Sidebar, BorderSizePixel = 0, ClipsDescendants = true,
                Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 0), Visible = false}, frame)
            corners(panel, 8)
            local search = input(panel, "Search...", "")
            search.Position = UDim2.fromOffset(7, 7)
            search.Size = UDim2.new(1, -14, 0, 44)
            local list = create("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0,
                Position = UDim2.fromOffset(7, 58), Size = UDim2.new(1, -14, 1, -66),
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 3, ScrollBarImageColor3 = P.Border}, panel)
            layout(list, 4)
            local connections, selectedButtons, opened, revision = {}, {}, false, 0
            local function panelHeight() return math.clamp(layoutHeight-100,110,220) end
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
                App.Tween(frame, {Size = UDim2.new(1, 0, 0, 80)}, 0.22)
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
                            TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham, TextSize = 14, TextWrapped=true, TextTruncate=Enum.TextTruncate.AtEnd,
                            BackgroundColor3 = name == tostring(C[key]) and P.Accent or P.Control, BorderSizePixel = 0,
                            Size = UDim2.new(1, -4, 0, 44)}, list)
                        choice:SetAttribute("ControlType","DropdownOption")
                        choice:SetAttribute("ControlKey",key)
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
                App.Tween(frame, {Size = UDim2.new(1, 0, 0, 80+panelHeight())}, 0.22)
                App.Tween(panel, {Size = UDim2.new(1, 0, 0, panelHeight())}, 0.22)
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
            responsive(function()
                frame.Size=UDim2.new(1,0,0,opened and 80+panelHeight() or 80)
                panel.Size=UDim2.new(1,0,0,opened and panelHeight() or 0)
            end)
            return {Refresh = function() update(C[key]); if opened then rebuild() end end, Close = close}
        end
        local function result(ok, message)
            App.Notify(tostring(message or (ok and "Done" or "Action failed")), ok and "success" or "error")
        end

        gui = create("ScreenGui", {Name = "HajimeRisingHub", ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 99999, IgnoreGuiInset = false})
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
                    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=99999,IgnoreGuiInset=false})
            end
        end
        if not parented then gui:Destroy(); error("No writable UI container is available") end
        pcall(function() if type(syn) == "table" and type(syn.protect_gui) == "function" then syn.protect_gui(gui) end end)
        pcall(function() gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets end)
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
        local minimize = create("TextButton", {Name="Minimize",Text = "-", TextSize = 23, TextColor3 = P.Muted,
            Font = Enum.Font.GothamMedium, BorderSizePixel = 0, BackgroundColor3 = P.Control,
            Position = UDim2.new(1, -86, 0, 17), Size = UDim2.fromOffset(28, 28)}, top)
        corners(minimize, 7)
        local close = create("TextButton", {Name="Close",Text = "x", TextSize = 15, TextColor3 = P.Muted,
            Font = Enum.Font.GothamMedium, BorderSizePixel = 0, BackgroundColor3 = P.Control,
            Position = UDim2.new(1, -48, 0, 17), Size = UDim2.fromOffset(28, 28)}, top)
        corners(close, 7)
        local keyboardDismiss=create("TextButton",{Name="KeyboardDone",Text="Done",TextSize=14,
            TextColor3=P.Text,Font=Enum.Font.GothamMedium,BorderSizePixel=0,BackgroundColor3=P.Control,
            Position=UDim2.new(1,-106,0,6),Size=UDim2.fromOffset(50,44),Visible=false},top)
        corners(keyboardDismiss,7)
        keyboardDismiss:SetAttribute("ControlType","HeaderButton")
        interactive(keyboardDismiss,function()
            local focused=S.UserInputService:GetFocusedTextBox()
            if focused then focused:ReleaseFocus() end
            if preview then preview.KeyboardHeight=0 end
            if refreshLayout then refreshLayout(true) end
        end)
        local sidebar = create("Frame", {Name="Navigation",BackgroundColor3 = P.Sidebar, BorderSizePixel = 0,
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
            local button = create("TextButton", {Name="Tab_"..name,Text = "", BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, (index - 1) * 49), ZIndex = 2}, nav)
            local number = text(button, string.format("%02d", index), 10, P.Muted, true)
            number.Position = UDim2.fromOffset(12, 0)
            number.Size = UDim2.new(0, 25, 1, 0)
            local title = text(button, name, 11, P.Muted)
            title.Position = UDim2.fromOffset(40, 0)
            title.Size = UDim2.new(1, -45, 1, 0)
            button:SetAttribute("ControlType","Navigation")
            title:SetAttribute("NavigationText",true)
            tabButtons[name] = {Button = button, Label = title, Number = number, Index = index}
            interactive(button, function() set("ActiveTab", name) end, nil, true)
            watch(button.MouseEnter, function() if C.ActiveTab ~= name then App.Tween(title, {TextColor3 = P.Text}, 0.15) end end)
            watch(button.MouseLeave, function() if C.ActiveTab ~= name then App.Tween(title, {TextColor3 = P.Muted}, 0.15) end end)
        end
        local sideTip = text(sidebar, "CONSISTENCY\nBUILDS CHAMPIONS.", 10, P.Muted, true)
        sideTip.Position = UDim2.new(0, 24, 1, -74)
        sideTip.Size = UDim2.new(1, -40, 0, 50)
        sideTip.TextWrapped = true
        local content = create("Frame", {Name="Pages",BackgroundTransparency = 1, BorderSizePixel = 0,
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
                    offset = offset + 89
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
                AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 370, 1, 0), Size = UDim2.new(1,0,0,80), ClipsDescendants = true})
            corners(frame, 10)
            outline(frame)
            local strip = create("Frame", {BackgroundColor3 = color, BorderSizePixel = 0,
                Size = UDim2.new(0, 3, 1, 0)}, frame)
            local label = text(frame, tostring(message), 14, P.Text)
            label.Position = UDim2.fromOffset(17, 9)
            label.Size = UDim2.new(1, -31, 1, -21)
            label.TextWrapped = true
            label.TextTruncate = Enum.TextTruncate.None
            local progress = create("Frame", {BackgroundColor3 = color, BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2)}, frame)
            local item = {Frame = frame}
            table.insert(toasts, item)
            while #toasts > (compact and 2 or 4) do dismissToast(toasts[1]) end
            arrangeToasts()
            App.Tween(progress, {Size = UDim2.new(0, 0, 0, 2)}, lifespan, Enum.EasingStyle.Linear)
            App.Maid:Delay(lifespan, function() dismissToast(item) end)
        end

        local dashboardLabels, statLabels, ledgerRows = {}, {}, {}
        local combatStatusLabel
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
                ledgerRows[#ledgerRows+1]={Row=line,Label=label,Values=values}
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
            local page=pages.Combat.Scroll
            local defense=card(page,"Automatic defense","Choose which defensive actions to use. All actions start off.")
            toggle(defense,"Auto Weave","AutoWeave")
            toggle(defense,"Auto Dodge","AutoDodge","Equip Boxing gloves. Retreats or moves sideways from incoming punches; pauses during training and eating.")
            toggle(defense,"Auto Block","AutoBlock")
            combatStatusLabel=text(defense,"Defense is off",12,P.Muted)
            combatStatusLabel.TextWrapped=true
            combatStatusLabel.AutomaticSize=Enum.AutomaticSize.Y
            local threats=card(page,"Threat detection","Defense starts earlier against fast punches.")
            toggle(threats,"React to players","CombatPlayers")
            toggle(threats,"React to NPCs","CombatNPCs")
            slider(threats,"Reaction delay","CombatReactionDelay",0,0.35,0.01,"s")
            slider(threats,"Threat detection range","CombatThreatRange",6,24,1," studs")
            slider(threats,"Minimum stamina","CombatStaminaFloor",5,70,1,"%")
        end
        local foodStatusLabel,foodLedgerLabel
        do
            local page = pages["Player & QoL"].Scroll
            local food = card(page,"Auto Food","Pauses your workout to eat, then resumes it. Also refills energy below the training floor.")
            toggle(food,"Auto Food","AutoFood","Uses food in your inventory when hunger or energy runs low.")
            toggle(food,"Auto-buy food","AutoBuyFood","Visits a food counter and spends in-game cash within your refill budget.")
            dropdown(food,"Food item","FoodItem",function()return App.Food and App.Food.Options() or {"Auto"}end)
            slider(food,"Eat below hunger","FoodLow",5,80,1,"%")
            slider(food,"Refill hunger to","FoodTarget",20,100,1,"%")
            slider(food,"Budget per refill (¥)","FoodBudget",0,50000,500)
            foodStatusLabel=text(food,"Auto Food off",13,P.Muted)
            foodLedgerLabel=text(food,"Eaten: 0 · Spent: ¥0",13,P.Muted)
            for _,label in {foodStatusLabel,foodLedgerLabel} do
                label.TextWrapped=true;label.TextTruncate=Enum.TextTruncate.None
                label.AutomaticSize=Enum.AutomaticSize.Y;label.Size=UDim2.new(1,0,0,24)
            end
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

        pill = create("TextButton", {Name = "Minimized", Text = "H  /  RISING    +", TextSize = 14,
            TextColor3 = P.Text, Font = Enum.Font.GothamBold, BackgroundColor3 = P.Sidebar,
            BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(C.WindowX, C.WindowY),
            Size = UDim2.fromOffset(176, 48), Visible = false}, root)
        corners(pill, 21)
        local pillBorder = outline(pill, P.Accent)
        themed(function() pillBorder.Color = P.Accent end)
        local layoutSignature, fontsCompact, keyboardOpen, currentAvailableHeight
        local layoutBusy=false
        local function fittedScale() return 1 end
        navLayout=function()
            local index=(tabButtons[C.ActiveTab] or tabButtons.Dashboard).Index
            if compact then
                local cell=layoutWidth/#pageNames
                activeIndicator.Size=UDim2.new(1/#pageNames,-4,1,-8)
                App.Tween(activeIndicator,{Position=UDim2.fromOffset((index-1)*cell+2,4)},0.22)
                indicatorLine.Position=UDim2.new(0.5,-10,1,-3)
                indicatorLine.Size=UDim2.fromOffset(20,3)
            else
                activeIndicator.Size=UDim2.new(1,0,0,44)
                App.Tween(activeIndicator,{Position=UDim2.fromOffset(0,(index-1)*49)},0.22)
                indicatorLine.Position=UDim2.fromOffset(0,12)
                indicatorLine.Size=UDim2.fromOffset(3,19)
            end
        end
        scrollFocused=function(box)
            box=box or S.UserInputService:GetFocusedTextBox()
            if not box or not box:IsDescendantOf(gui) then return end
            local scrolling=box:FindFirstAncestorWhichIsA("ScrollingFrame")
            if not scrolling then return end
            local topY=scrolling.AbsolutePosition.Y+8
            local bottomY=scrolling.AbsolutePosition.Y+scrolling.AbsoluteSize.Y-12
            local boxTop,boxBottom=box.AbsolutePosition.Y,box.AbsolutePosition.Y+box.AbsoluteSize.Y
            local adjustment=boxTop<topY and boxTop-topY or boxBottom>bottomY and boxBottom-bottomY or 0
            if adjustment~=0 then
                scrolling.CanvasPosition=Vector2.new(scrolling.CanvasPosition.X,math.max(0,scrolling.CanvasPosition.Y+adjustment))
            end
        end
        refreshLayout=function(force)
            if layoutBusy or not root.Parent then return end
            local available=preview and Vector2.new(preview.Width,preview.Height) or root.AbsoluteSize
            local availableHeight=available.Y
            local keyboard=false
            if preview then
                keyboard=(preview.KeyboardHeight or 0)>0
                availableHeight=availableHeight-(preview.KeyboardHeight or 0)
            else
                pcall(function()
                    if S.UserInputService.OnScreenKeyboardVisible then
                        local keyboardY=S.UserInputService.OnScreenKeyboardPosition.Y-root.AbsolutePosition.Y
                        if keyboardY>0 and keyboardY<availableHeight then keyboard=true;availableHeight=keyboardY end
                    end
                end)
            end
            local touch=S.UserInputService.TouchEnabled
            if preview then touch=preview.Touch end
            local signature=string.format("%.1f:%.1f:%.1f:%s:%s",available.X,available.Y,availableHeight,tostring(touch),tostring(keyboard))
            if not force and signature==layoutSignature then return end
            layoutBusy=true;layoutSignature=signature
            viewport=available;touchMode=touch;keyboardOpen=keyboard;currentAvailableHeight=availableHeight
            compact=touch or available.X<720 or available.Y<520
            local usableWidth=math.max(240,available.X)
            local usableHeight=math.max(112,availableHeight)
            layoutWidth=math.min(800,usableWidth-16)
            local portrait=available.Y>available.X
            local desiredHeight=compact and portrait and 760 or 590
            layoutHeight=math.min(desiredHeight,usableHeight-16)
            main.Size=UDim2.fromOffset(layoutWidth,layoutHeight)
            local halfX,halfY=layoutWidth/2,layoutHeight/2
            local x=math.clamp(C.WindowX*usableWidth,halfX+8,math.max(halfX+8,usableWidth-halfX-8))
            local y=math.clamp(C.WindowY*usableHeight,halfY+8,math.max(halfY+8,usableHeight-halfY-8))
            App.Tween(main,{Position=UDim2.fromOffset(x,y)},0.15)
            if main.Visible then App.Tween(mainScale,{Scale=1},0.15) end
            local headerHeight=compact and 56 or 62
            top.Size=UDim2.new(1,0,0,headerHeight)
            logo.Position=UDim2.fromOffset(compact and 12 or 19,compact and 13 or 16)
            brand.Position=UDim2.fromOffset(compact and 52 or 61,compact and 15 or 13)
            brand.Size=UDim2.new(1,compact and -156 or -180,0,24)
            brandSub.Visible=not compact
            minimize.Position=UDim2.new(1,-100,0,6)
            close.Position=UDim2.new(1,-50,0,6)
            minimize.Size=UDim2.fromOffset(44,44);close.Size=UDim2.fromOffset(44,44)
            minimize.Visible=not keyboard;keyboardDismiss.Visible=keyboard
            minimize:SetAttribute("ControlType","HeaderButton");close:SetAttribute("ControlType","HeaderButton")
            sideTip.Visible=not compact
            footer.Visible=not keyboard
            if compact then
                local bottom=keyboard and 0 or 80
                sidebar.Visible=not keyboard
                sidebar.Position=UDim2.new(0,0,1,-80)
                sidebar.Size=UDim2.new(1,0,0,52)
                nav.Position=UDim2.fromOffset(0,0);nav.Size=UDim2.fromScale(1,1)
                content.Position=UDim2.fromOffset(8,headerHeight+8)
                content.Size=UDim2.new(1,-16,1,-headerHeight-bottom-16)
                footer.Position=UDim2.new(0,0,1,-28);footer.Size=UDim2.new(1,0,0,28)
                statusDot.Position=UDim2.fromOffset(14,11)
                footerStatus.Position=UDim2.fromOffset(30,0);footerStatus.Size=UDim2.new(1,-42,1,0)
            else
                sidebar.Visible=true
                sidebar.Position=UDim2.fromOffset(0,62);sidebar.Size=UDim2.new(0,179,1,-105)
                nav.Position=UDim2.fromOffset(12,18);nav.Size=UDim2.new(1,-24,0,#pageNames*49)
                content.Position=UDim2.fromOffset(198,76);content.Size=UDim2.new(1,-218,1,-133)
                footer.Position=UDim2.new(0,0,1,-42);footer.Size=UDim2.new(1,0,0,42)
                statusDot.Position=UDim2.new(1,-179,0,17)
                footerStatus.Position=UDim2.new(1,-160,0,0);footerStatus.Size=UDim2.new(0,140,1,0)
            end
            for name,tab in pairs(tabButtons) do
                if compact then
                    tab.Button.Position=UDim2.new((tab.Index-1)/#pageNames,0,0,0)
                    tab.Button.Size=UDim2.new(1/#pageNames,0,1,0)
                    tab.Number.Visible=false
                    tab.Label.Text=shortNames[name] or name
                    tab.Label.Position=UDim2.fromOffset(1,0);tab.Label.Size=UDim2.new(1,-2,1,0)
                    tab.Label.TextXAlignment=Enum.TextXAlignment.Center
                else
                    tab.Button.Position=UDim2.fromOffset(0,(tab.Index-1)*49)
                    tab.Button.Size=UDim2.new(1,0,0,44)
                    tab.Number.Visible=true
                    tab.Label.Text=name
                    tab.Label.Position=UDim2.fromOffset(40,0);tab.Label.Size=UDim2.new(1,-45,1,0)
                    tab.Label.TextXAlignment=Enum.TextXAlignment.Left
                end
            end
            if fontsCompact~=compact then
                fontsCompact=compact
                for _,object in ipairs(main:GetDescendants()) do
                    if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                        local base=object:GetAttribute("BaseTextSize") or object.TextSize
                        if object:GetAttribute("BaseTextSize")==nil then object:SetAttribute("BaseTextSize",base) end
                        object.TextSize=compact and math.max(base,object:GetAttribute("MutedText") and 12 or 14) or base
                        if object:GetAttribute("NavigationText") then object.TextSize=compact and 12 or base end
                    end
                end
            end
            brand.TextSize=compact and 16 or 14
            for _,entry in ledgerRows do
                if compact then
                    entry.Row.Size=UDim2.new(1,0,0,52)
                    entry.Label.Position=UDim2.fromOffset(0,0);entry.Label.Size=UDim2.new(1,0,0,24)
                    entry.Values.Position=UDim2.fromOffset(0,25);entry.Values.Size=UDim2.new(1,0,0,24)
                    entry.Values.TextXAlignment=Enum.TextXAlignment.Left
                else
                    entry.Row.Size=UDim2.new(1,0,0,29)
                    entry.Label.Position=UDim2.fromOffset(0,0);entry.Label.Size=UDim2.new(.35,0,1,0)
                    entry.Values.Position=UDim2.fromScale(.35,0);entry.Values.Size=UDim2.new(.65,0,1,0)
                    entry.Values.TextXAlignment=Enum.TextXAlignment.Right
                end
            end
            toastLayer.Position=UDim2.new(1,-12,1,-12)
            toastLayer.Size=UDim2.new(0,math.min(340,usableWidth-24),1,-24)
            for _,item in toasts do item.Frame.Size=UDim2.new(1,0,0,80) end
            pill.Size=UDim2.fromOffset(176,48)
            pill.Position=UDim2.fromOffset(math.clamp(x,96,math.max(96,usableWidth-96)),math.clamp(y,32,math.max(32,usableHeight-32)))
            pill.Visible=(touchMode or compact or C.Visible==true) and (C.Visible~=true or C.Minimized==true)
            navLayout()
            for _,callback in ipairs(responsiveCallbacks) do callback() end
            layoutBusy=false
            if keyboard then App.Maid:Delay(.05,function()scrollFocused()end) end
        end
        local function positionWindow()refreshLayout(true)end
        updateVisibility=function()
            visibilityVersion=visibilityVersion+1
            local version=visibilityVersion
            local visible=C.Visible==true
            pill.Visible=(touchMode or compact or visible) and (not visible or C.Minimized==true)
            if visible and C.Minimized~=true then
                main.Visible=true;positionWindow()
                App.Tween(mainScale,{Scale=fittedScale()},0.22);opacity(main,0,0.22)
            else
                opacity(main,1,0.18);App.Tween(mainScale,{Scale=.98},0.18)
                App.Maid:Delay(.2,function()if version==visibilityVersion then main.Visible=false end end)
            end
        end
        App.PreviewLayout=function(width,height,touch,keyboardHeight)
            preview={Width=math.max(240,tonumber(width) or 390),Height=math.max(160,tonumber(height) or 844),
                Touch=touch~=false,KeyboardHeight=math.max(0,tonumber(keyboardHeight) or 0)}
            root.AnchorPoint=Vector2.new(.5,.5);root.Position=UDim2.fromScale(.5,.5)
            root.Size=UDim2.fromOffset(preview.Width,preview.Height)
            refreshLayout(true);updateVisibility()
        end
        App.RestoreLayout=function()
            preview=nil
            root.AnchorPoint=Vector2.zero;root.Position=UDim2.fromOffset(0,0);root.Size=UDim2.fromScale(1,1)
            refreshLayout(true);updateVisibility()
            App.Maid:Delay(.05,function()refreshLayout(true)end)
        end
        App.LayoutSnapshot=function()
            return {Compact=compact,Touch=touchMode,Width=layoutWidth,Height=layoutHeight,Scale=mainScale.Scale,
                ViewportX=viewport.X,ViewportY=viewport.Y,Keyboard=keyboardOpen==true,Navigation=sidebar.Visible,
                ContentWidth=content.AbsoluteSize.X,ContentHeight=content.AbsoluteSize.Y,
                Visible=main.Visible,ReopenVisible=pill.Visible,Preview=preview~=nil,
                NavigationX=sidebar.AbsolutePosition.X,NavigationY=sidebar.AbsolutePosition.Y,
                NavigationWidth=sidebar.AbsoluteSize.X,NavigationHeight=sidebar.AbsoluteSize.Y,
                AvailableHeight=currentAvailableHeight,KeyboardDone=keyboardDismiss.Visible}
        end
        local function releaseKeyboard()
            local focused=S.UserInputService:GetFocusedTextBox()
            if focused and focused:IsDescendantOf(gui) then focused:ReleaseFocus() end
        end
        interactive(minimize,function()releaseKeyboard();set("Minimized",true)end)
        interactive(close,function()releaseKeyboard();set("Visible",false)end)
        interactive(pill,function()set("Visible",true);set("Minimized",false)end,nil,true)
        watch(pill.MouseEnter,function()App.Tween(pill,{BackgroundColor3=P.Control},.15)end)
        watch(pill.MouseLeave,function()App.Tween(pill,{BackgroundColor3=P.Sidebar},.15)end)
        local dragStart, dragCenter, dragInput
        watch(top.InputBegan, function(event)
            if event.UserInputType ~= Enum.UserInputType.MouseButton1 and event.UserInputType ~= Enum.UserInputType.Touch then return end
            if S.UserInputService:GetFocusedTextBox() then return end
            local position = event.Position
            if position.X >= main.AbsolutePosition.X+main.AbsoluteSize.X-110 then return end
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
            navLayout()
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
            refreshLayout(false)
            local ok, data = pcall(App.GetDashboard)
            if not ok or type(data) ~= "table" then return end
            if combatStatusLabel then combatStatusLabel.Text=tostring(data.CombatStatus or "Defense is off") end
            local food=data.Food or {}
            foodStatusLabel.Text=tostring(food.Status or "Auto Food off")
            foodLedgerLabel.Text=string.format("Eaten: %s · Spent: ¥%s · This refill: ¥%s",number(food.Eaten or 0,0),
                number(food.Spent or 0,0),number(food.CycleSpent or 0,0))
            dashboardLabels.Status.Text = tostring(data.Status or "Standing by")
            dashboardLabels.Character.Text = string.format("%s  ·  %s  ·  Mastery %s  ·  ¥ %s", tostring(data.Style or "--"), tostring(data.Rank or "--"), number(data.Mastery, 1), number(data.Cash, 0))
            dashboardLabels.Resources.Text = string.format("Stamina %s / %s (%s%%)  ·  Energy %s  ·  Hunger %s  ·  Thirst %s", number(data.Stamina, 0), number(data.StaminaMax, 0), number(data.StaminaPercent, 0), number(data.Energy, 0), number(data.Hunger, 0), number(data.Thirst, 0))
            local seconds = math.max(0, tonumber(data.Elapsed) or 0)
            dashboardLabels.Session.Text = string.format("Session %02d:%02d  ·  %s reps  ·  %s", math.floor(seconds / 60), math.floor(seconds % 60), number(data.Reps, 0), tostring(data.Executor or "Executor"))
            dashboardLabels.Notice.Text = tostring(data.LastNotice or "")
            App.Tween(dashboardLabels.StaminaFill, {Size = UDim2.new(math.clamp((tonumber(data.StaminaPercent) or 0) / 100, 0, 1), 0, 1, 0)}, 0.22)
            for _, stat in ipairs(data.Stats or {}) do
                local label = statLabels[stat.Name]
                if label then
                    local digits=compact and 2 or 3
                    local gain=tonumber(stat.Gain) or 0
                    label.Text=string.format("%s   %s%s   %s/min",number(stat.Value,digits),gain>=0 and "+" or "",number(gain,digits),number(stat.PerMinute,digits))
                end
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
        if App.OnCombatEvent then App.Maid:Give(App.Remote.OnClientEvent:Connect(App.OnCombatEvent)) end
        App.Maid:Give(App.Player.CharacterRemoving:Connect(function()
            if App.Food then App.Food.Stop("Waiting for respawn") end
            if App.StopCombat then App.StopCombat() end
            App.StopTraining("Waiting for respawn")
            App.RestoreAll()
        end))
        App.Maid:Give(App.Player.CharacterAdded:Connect(function()
            if App.Food then App.Food.Stop("Waiting for character") end
            if App.StopCombat then App.StopCombat() end
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
                local foodOwns=App.Food and App.Food.Step(os.clock())
                if not foodOwns then
                    App.StepTraining()
                    if App.StepCombat then App.StepCombat() end
                end
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
                local stopped=table.clone(App.State.Config)
                stopped.TrainingEnabled=false
                stopped.AutoFood=false
                stopped.AutoWeave=false;stopped.AutoDodge=false;stopped.AutoBlock=false
                App.Apply(stopped)
                if App.StopCombat then App.StopCombat() end
                if App.Food then App.Food.Stop("Stopped after an error") end
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
