-- Allen Scripts / Ink Game attack-animation dash.
assert(game.GameId == 7008097940, "Open Ink Game first")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local env = getgenv()
local key = "__INK_GAME_ANIMATION_DASH"
if env[key] then env[key]:Destroy() end

-- Animation IDs, forward reach in studs, and facing thresholds.
local attacks = {
    ["116839849594540"] = {10.5, 0.6, 1.75}, -- fists
    ["96924216250322"] = {10.5, 0.6, 1.75},
    ["123072675259257"] = {20, 0.84, 2.15}, -- fists lunge
    ["85793691404836"] = {10.5, 0.6, 1.75}, -- fork swings
    ["86197206792061"] = {10.5, 0.6, 1.75},
    ["85623602463927"] = {10.5, 0.6, 1.75}, -- bottle swings
    ["87978085217719"] = {10.5, 0.6, 1.75},
    ["99157505926076"] = {20, 0.84, 2.15}, -- shared fork/bottle lunge
    ["79649041083405"] = {10.5, 0.6, 1.75}, -- knife swings
    ["73242877658272"] = {10.5, 0.6, 1.75},
    ["130148105259587"] = {20, 0.84, 2.15}, -- knife lunge
    ["121147456137931"] = {20, 0.84, 2.15}, -- knife backstab opener
    ["72557176302052"] = {35, 0.95}, -- fork throw
    ["73150160715773"] = {35, 0.95}, -- bottle throw
    ["94215646393565"] = {35, 0.95}, -- knife throw
}

local animationNames = {
    ["116839849594540"] = "FistsSwing1",
    ["96924216250322"] = "FistsSwing2",
    ["123072675259257"] = "FistsSwing1Lunge",
    ["85793691404836"] = "ForkSwing1",
    ["86197206792061"] = "ForkSwing2",
    ["85623602463927"] = "BottleSwing1",
    ["87978085217719"] = "BottleSwing2",
    ["99157505926076"] = "Fork/Bottle Lunge",
    ["79649041083405"] = "KnifeSwing1",
    ["73242877658272"] = "KnifeSwing2",
    ["130148105259587"] = "KnifeSwing1Lunge",
    ["121147456137931"] = "KnifeSwingBackstab",
    ["72557176302052"] = "Fork Throw",
    ["73150160715773"] = "Bottle Throw",
    ["94215646393565"] = "Knife Throw",
}
local folderAttacks = {}
local dashIds = {
    ["134552572582241"] = "Forward",
    ["98397849734585"] = "Backwards",
    ["88725936982152"] = "Left",
    ["104349024070999"] = "Right",
}
local enemyDashes = setmetatable({}, {__mode = "k"})
local fightBackProfiles = {
    Punch1 = {14, 0.65},
    Punch2 = {14, 0.65},
    Punch3 = {20, 0.65},
    AttemptToPunchBack = {26, 0.65},
    PoleSwing1 = {22, 0.65},
    PoleSwing2 = {22, 0.65},
    PoleThrow = {35, 0.95},
}
local closeRange = {7, 0.75}

local function indexAttackFolders()
    table.clear(folderAttacks)
    local animations = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
    local abilities = animations and animations:FindFirstChild("Abilities")
    local dashing = animations and animations:FindFirstChild("Dashing")
    if dashing then
        for _, name in ipairs({"Forward", "Backwards", "Left", "Right"}) do
            local animation = dashing:FindFirstChild(name)
            local id = animation and animation:IsA("Animation") and animation.AnimationId:match("%d+")
            if id then dashIds[id] = name end
        end
    end
    local count = 0
    for _, name in ipairs({"FightBack", "Fists"}) do
        local folder = abilities and abilities:FindFirstChild(name)
        if folder then
            for _, object in ipairs(folder:GetDescendants()) do
                if object:IsA("Animation") then
                    local id = object.AnimationId:match("%d+")
                    if id then
                        folderAttacks[id] = attacks[id] or fightBackProfiles[object.Name] or closeRange
                        animationNames[id] = object.Name
                        count += 1
                    end
                end
            end
        end
    end
    return count
end

local state = {HubOnly = true, Enabled = false, Destroyed = false, Status = "Off"}
local watchers = {}
local pendingSwings = {}
local approach = setmetatable({}, {__mode = "k"})
local sampledTarget
local nextMotionSample = 0
local recentThreats = setmetatable({}, {__mode = "k"})
local connections = {}

local cachedInfo
local cachedCooldown
local nextProbe = 0

local function nativeCooldown(info)
    if cachedInfo ~= info then
        cachedInfo, cachedCooldown, nextProbe = info, nil, 0
    end
    if cachedCooldown then return cachedCooldown end
    if os.clock() < nextProbe or type(getconnections) ~= "function"
        or type(debug.getupvalues) ~= "function" then return nil end
    nextProbe = os.clock() + 1
    local ok, listeners = pcall(getconnections, info.Event)
    if not ok or type(listeners) ~= "table" then return nil end
    for i = 1, math.min(#listeners, 12) do
        local found, upvalues = pcall(function()
            return debug.getupvalues(listeners[i].Function)
        end)
        if found and type(upvalues) == "table" then
            for _, value in pairs(upvalues) do
                if type(value) == "table" and type(rawget(value, "CDDASHSTACKS")) == "number" then
                    cachedCooldown = value
                    return value
                end
            end
        end
    end
end

local function dashReady(character, info)
    local cooldown = nativeCooldown(info)
    if not cooldown then return false, "Native cooldown unavailable" end
    if cooldown.DidEffect or cooldown.DashZoomIn then return false, "Manual dash charging" end

    local values = workspace:FindFirstChild("Values")
    local disabled = values and values:FindFirstChild("PowersDisabled")
    local override = character:FindFirstChild("PowerOverwrite")
    local power = override and override:IsA("StringValue") and override.Value
        or player:GetAttribute("_EquippedPower")
    if power == "PHANTOM STEP" and not player:GetAttribute("IsGuard") and not (disabled and disabled.Value) then
        return cooldown.CDDASHSTACKS < 2, "Native dash charges recovering"
    end
    return not cooldown.DashCD, "Native dash cooldown"
end
local nextDispatch = 0
local frameTime = 1 / 60
local ping = 0
local nextPingSample = 0

local function sampleTiming(dt)
    frameTime += (math.clamp(dt, 1 / 300, 0.1) - frameTime) * 0.15
    local now = os.clock()
    if now < nextPingSample then return end
    nextPingSample = now + 0.5
    local ok, sample = pcall(player.GetNetworkPing, player)
    if ok and type(sample) == "number" and sample >= 0 then
        ping = math.clamp(sample, 0, 0.12)
    end
end

local function flat(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function sampleApproach()
    local now = os.clock()
    if now < nextMotionSample then return end
    nextMotionSample = now + 0.033
    local target = player.Character
    if sampledTarget ~= target then
        table.clear(approach)
        table.clear(enemyDashes)
        sampledTarget = target
    end
    local root = target and target:FindFirstChild("HumanoidRootPart")
    if not root then return end

    for opponent in pairs(watchers) do
        local character = opponent.Character
        local enemy = character and character:FindFirstChild("HumanoidRootPart")
        if enemy then
            local offset = flat(root.Position - enemy.Position)
            if offset.Magnitude > 0.1 and offset.Magnitude <= 38 then
                local enemyVelocity = flat(enemy.AssemblyLinearVelocity)
                local velocity = enemyVelocity - flat(root.AssemblyLinearVelocity)
                local closing = velocity:Dot(offset.Unit)
                if closing >= 24 and enemyVelocity:Dot(offset.Unit) >= 24 then
                    approach[enemy] = {Velocity = velocity, At = now}
                elseif closing < -4 then
                    approach[enemy] = nil
                end
            else
                approach[enemy] = nil
            end
        end
    end
end

local function dashAway(enemyRoot, character, humanoid, root, track, animationId)
    if os.clock() < nextDispatch then return end
    local boosts = player:FindFirstChild("Boosts")
    local sprint = boosts and boosts:FindFirstChild("Faster Sprint")
    if not sprint or not (sprint:IsA("IntValue") or sprint:IsA("NumberValue")) or sprint.Value < 5 then
        state.Status = "Requires Faster Sprint level 5"
        return
    end

    local camera = workspace.CurrentCamera
    local controller = character:FindFirstChild("DashRequest") or character:FindFirstChild("Main")
    local info = controller and controller:FindFirstChild("Info")
    if not camera or not info or not info:IsA("BindableEvent") or character:FindFirstChild("DisableDash") then return end

    local look = flat(camera.CFrame.LookVector)
    if look.Magnitude < 0.01 then return end
    local forward = look.Unit
    local right = forward:Cross(Vector3.yAxis)
    local away = flat(root.Position - enemyRoot.Position)
    if away.Magnitude < 0.1 then return end
    away = away.Unit

    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances = {character, enemyRoot.Parent}
    ray.RespectCanCollide = true
    local direction, bestScore = nil, -math.huge
    local now = os.clock()
    for _, candidate in ipairs({forward, -forward, right, -right}) do
        local dot = away:Dot(candidate)
        if dot >= -0.01 and not workspace:Raycast(root.Position, candidate * 20, ray) then
            local landing = root.Position + candidate * 20
            local nearest = 30
            for threat, seenAt in pairs(recentThreats) do
                if now - seenAt <= 0.55 and threat:IsDescendantOf(workspace) then
                    nearest = math.min(nearest, flat(landing - threat.Position).Magnitude)
                end
            end
            local score = nearest + dot * 4
            if score > bestScore then direction, bestScore = candidate, score end
        end
    end
    if not direction then return end


    local ready, reason = dashReady(character, info)
    if not ready then
        state.Status = reason
        return
    end

    -- Keep a level-5 request interval even when the controller rejects a dash.
    nextDispatch = os.clock() + 1.5
    local previous = shared.controllerpressed
    local before = character:GetAttribute("RecentDash")
    local phase, health = track.TimePosition, humanoid.Health
    shared.controllerpressed = true
    local ok, message = pcall(function()
        humanoid:Move(direction, false)
        info:Fire({DashingReleased = true})
    end)
    state.Status = "Dash requested"
    task.spawn(function()
        -- Let the native listener sample the chosen direction before restoring input mode.
        task.wait()
        shared.controllerpressed = previous
        task.wait(0.4)
        if not state.Enabled or player.Character ~= character then return end
        if not ok then
            state.Status = "Dash dispatch error"
            warn("[Weapon Auto Dodge]", message)
            return
        end
        local registered = character:GetAttribute("RecentDash") ~= before
        state.Status = registered and "Dash registered" or "Native dash did not register"
        print("[Weapon Auto Dodge]", state.Status, "animation", animationNames[animationId] or track.Name, animationId, "phase", phase, "health", health, humanoid.Health, "direction", direction)
    end)
end

local function dashBlockedByRecovery(character)
    if character:FindFirstChild("Ragdoll") or character:FindFirstChild("Dead") then return true end
    for _, child in ipairs(character:GetChildren()) do
        if child.Name == "Stun" and not (child:GetAttribute("GettingShot") or child:GetAttribute("CanFireGun")
            or child:GetAttribute("FakeStun") or child:GetAttribute("CanDash")) then
            return true
        end
    end
    return false
end

local function rememberDash(character, direction)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local frame = root.CFrame
    local vector = direction == "Backwards" and -frame.LookVector
        or direction == "Left" and -frame.RightVector
        or direction == "Right" and frame.RightVector
        or frame.LookVector
    vector = flat(vector)
    if vector.Magnitude > 0.01 then
        enemyDashes[character] = {Direction = vector.Unit, Expires = os.clock() + 0.12}
    end
end

local function observe(character, track, deadline)
    local animation = track.Animation
    local animationId = animation and animation.AnimationId:match("%d+")
    local dashDirection = animationId and dashIds[animationId]
    if dashDirection and not deadline and state.Enabled then
        rememberDash(character, dashDirection)
        for pendingTrack, swing in pairs(pendingSwings) do
            if swing.Character == character and not observe(character, pendingTrack, swing.Deadline) then
                pendingSwings[pendingTrack] = nil
            end
        end
        return
    end
    local attack = animationId and (folderAttacks[animationId] or attacks[animationId])
    if not deadline then pendingSwings[track] = nil end
    if not attack then return end
    if deadline and (os.clock() >= deadline or not track.IsPlaying) then return end
    local target = player.Character
    if not state.Enabled or not target then return end
    local live = workspace:FindFirstChild("Live")
    if not live or character.Parent ~= live or target.Parent ~= live then return end
    local humanoid = target:FindFirstChildOfClass("Humanoid")
    local root = target:FindFirstChild("HumanoidRootPart")
    local enemyRoot = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root or not enemyRoot then return end

    local function keepWatching()
        if deadline then return true end
        -- A swing can start out of range and close during its windup.
        if attack[3] and (root.Position - enemyRoot.Position).Magnitude <= attack[1] + 14 then
            pendingSwings[track] = {Character = character, Deadline = os.clock() + 0.15}
        end
    end

    local delta = root.Position - enemyRoot.Position
    local horizontal = flat(delta)
    local facing = flat(enemyRoot.CFrame.LookVector)
    local distance = horizontal.Magnitude
    if math.abs(delta.Y) > 5 or distance < 0.1 or facing.Magnitude < 0.01
        or facing.Unit:Dot(horizontal.Unit) < attack[2] then return keepWatching() end

    local windupLead = attack[3] and math.max(0, 0.1 - track.TimePosition) or 0
    local lead = math.clamp(ping + frameTime + windupLead, 0, 0.18)
    local relativeVelocity = flat(enemyRoot.AssemblyLinearVelocity - root.AssemblyLinearVelocity)
    local recent = approach[enemyRoot]
    if attack[3] and recent and sampledTarget == target and os.clock() - recent.At <= 0.16 then
        local axis = horizontal.Unit
        local closing = relativeVelocity:Dot(axis)
        local recentClosing = recent.Velocity:Dot(axis)
        if closing >= -4 and recentClosing > closing then
            -- Carry only the closing component, so old sideways motion cannot aim the prediction.
            relativeVelocity += axis * ((recentClosing - closing) * 0.65)
        end
    end
    local dash = enemyDashes[character]
    if attack[3] and dash and os.clock() < dash.Expires then
        local axis = horizontal.Unit
        local closing = relativeVelocity:Dot(axis)
        local dashClosing = dash.Direction:Dot(axis)
        if dashClosing >= 0.75 and closing >= -4 then
            relativeVelocity += axis * math.max(0, 48 * dashClosing - closing)
        end
    end
    local motion = relativeVelocity * lead
    if motion.Magnitude > 6 then motion = motion.Unit * 6 end

    if attack[3] then
        -- HB uses an attacker-relative box. These dimensions estimate its footprint.
        local values = workspace:FindFirstChild("Values")
        local scale = values and values:FindFirstChild("HitboxMultiplier")
        local multiplier = scale and (scale:IsA("NumberValue") or scale:IsA("IntValue"))
            and math.max(0, scale.Value) or 1
        local forward = facing.Unit
        local right = forward:Cross(Vector3.yAxis)
        local bodyRadius = math.max(root.Size.X, root.Size.Z) * 0.5
        local length = attack[1] * multiplier + bodyRadius
        local halfWidth = attack[3] * multiplier + bodyRadius

        local function overlaps(point)
            local depth = point:Dot(forward)
            return depth >= -bodyRadius and depth <= length and math.abs(point:Dot(right)) <= halfWidth
        end

        if not overlaps(horizontal) and not overlaps(horizontal - motion) then return keepWatching() end
    elseif distance > attack[1] then
        if relativeVelocity:Dot(horizontal.Unit) <= 0
            or (horizontal - motion).Magnitude > attack[1] then return end
    end
    recentThreats[enemyRoot] = os.clock()
    if dashBlockedByRecovery(target) then
        state.Status = "Waiting for ragdoll or stun to clear"
        return keepWatching()
    end
    dashAway(enemyRoot, target, humanoid, root, track, animationId)
end

local function unwatch(other)
    local watcher = watchers[other]
    if not watcher then return end
    for _, connection in pairs(watcher) do connection:Disconnect() end
    watchers[other] = nil
end

local function watch(other)
    if other == player or watchers[other] then return end
    local watcher = {}
    watchers[other] = watcher

    local function bind(character)
        if watcher.animation then watcher.animation:Disconnect(); watcher.animation = nil end
        if watcher.descendant then watcher.descendant:Disconnect() end
        if watcher.removing then watcher.removing:Disconnect() end

        local currentAnimator
        local function attach(animator)
            if not animator:IsA("Animator") or not animator.Parent or not animator.Parent:IsA("Humanoid")
                or animator == currentAnimator then return end
            if watcher.animation then watcher.animation:Disconnect() end
            currentAnimator = animator
            watcher.animation = animator.AnimationPlayed:Connect(function(track)
                observe(character, track)
            end)
        end

        watcher.descendant = character.DescendantAdded:Connect(attach)
        watcher.removing = character.DescendantRemoving:Connect(function(object)
            if object ~= currentAnimator then return end
            watcher.animation:Disconnect()
            watcher.animation = nil
            currentAnimator = nil
        end)
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if animator then attach(animator) end
    end

    watcher.character = other.CharacterAdded:Connect(bind)
    if other.Character then bind(other.Character) end
end

function state:SetEnabled(value)
    if self.Destroyed or self.Enabled == value then return end
    self.Enabled = value
    self.Status = value and "Watching Fists and weapon attacks" or "Off"
    if value then
        self.IndexedAnimations = indexAttackFolders()
        nextPingSample = 0
        connections.timing = RunService.Heartbeat:Connect(function(dt)
            sampleTiming(dt)
            sampleApproach()
            for track, swing in pairs(pendingSwings) do
                if not observe(swing.Character, track, swing.Deadline) then pendingSwings[track] = nil end
            end
        end)
        connections.added = Players.PlayerAdded:Connect(watch)
        connections.removing = Players.PlayerRemoving:Connect(unwatch)
        for _, other in ipairs(Players:GetPlayers()) do watch(other) end
    else
        for _, connection in pairs(connections) do connection:Disconnect() end
        table.clear(connections)
        table.clear(recentThreats)
        table.clear(pendingSwings)
        table.clear(approach)
        table.clear(enemyDashes)
        for other in pairs(watchers) do unwatch(other) end
    end
end

function state:Destroy()
    self:SetEnabled(false)
    self.Destroyed = true
    if env[key] == self then env[key] = nil end
end

env[key] = state
return state
