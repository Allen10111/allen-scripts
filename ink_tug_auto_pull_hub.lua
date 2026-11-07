-- Ink Game Tug of War auto-pull, Potassium, v2.0
-- Starts OFF. Controlled only by the Allen Scripts hub switch.
-- Uses the live game's QTE click callback; no direct remote spam.
-- Re-run safely: the preceding instance disconnects itself.
-- Diagnostic snapshot: getgenv().__INK_TUG_AUTO_PULL:GetSnapshot()

if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 7008097940 then
    warn("[Ink Tug] This script is for Ink Game.")
    return
end
if type(getconnections) ~= "function" or not debug
    or type(debug.getupvalues) ~= "function" then
    warn("[Ink Tug] Potassium connection/upvalue inspection is required.")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Environment = getgenv()
local previous = Environment.__INK_TUG_AUTO_PULL
if previous and type(previous.Destroy) == "function" then
    pcall(previous.Destroy, previous)
end

local MAX_WINDOW = 26
local MIN_PRESS_INTERVAL = 0.12
local BIND_RETRY_INTERVAL = 0.25

local State = {
    Version = "2.0",
    Enabled = false,
    Destroyed = false,
    Engine = nil,
    Context = nil,
    NextBindAt = 0,
    LastPressAt = -math.huge,
    Presses = 0,
    LocalAdvances = 0,
    UnconfirmedPulls = 0,
    LocalMisses = 0,
    LockoutSkips = 0,
    Errors = 0,
    LastError = nil,
    LastWindow = nil,
    LastAngleError = nil,
    LastReason = "Off",
    BindingCount = 0,
}

local function angleError(a, b)
    return math.abs((a - b + 180) % 360 - 180)
end

local function visible(instance)
    if not instance or not instance:IsDescendantOf(PlayerGui) then return false end
    local current = instance
    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current = current.Parent
    end
    return current == PlayerGui
end

-- Identify the live onPress closure by its UI instance references, not by
-- guessed function names or by changing any of its captured values.
local function findPressFunction(callback, context, depth, visited)
    if depth > 2 or visited[callback] then return nil end
    visited[callback] = true
    local ok, values = pcall(debug.getupvalues, callback)
    if not ok or type(values) ~= "table" then return nil end
    if values[3] == context.Halftone and values[4] == context.Medium
        and values[5] == context.Arrow and values[16] == context.Button
        and type(values[2]) == "boolean" and type(values[6]) == "number"
        and type(values[18]) == "boolean" then
        return callback
    end
    local checked = 0
    for _, value in pairs(values) do
        if type(value) == "function" then
            checked += 1
            if checked > 12 then break end
            local found = findPressFunction(value, context, depth + 1, visited)
            if found then return found end
        end
    end
end

function State:Bind(root)
    if not root or not root:IsDescendantOf(PlayerGui) then return false end
    local circle = root:FindFirstChild("CircleBase")
    if not circle then return false end
    local context = {
        Root = root,
        Circle = circle,
        Arrow = circle:FindFirstChild("Arrow"),
        Medium = circle:FindFirstChild("Medium"),
        Button = circle:FindFirstChild("TextButton"),
        Halftone = circle:FindFirstChild("HalftoneWhenPressed"),
        Armed = false,
        LastGoal = nil,
        LastReason = "Bound",
    }
    if not (context.Arrow and context.Medium and context.Halftone
        and context.Button and context.Button:IsA("TextButton")) then return false end
    local ok, connections = pcall(getconnections, context.Button.MouseButton1Click)
    if not ok then return false end
    for _, connection in ipairs(connections) do
        local callback = connection.Function
        if type(callback) == "function" and connection.Enabled ~= false then
            local press = findPressFunction(callback, context, 0, {})
            if press then
                context.Press = callback
                context.Read = function()
                    local values = debug.getupvalues(press)
                    if values[4] ~= context.Medium or values[5] ~= context.Arrow
                        or values[16] ~= context.Button
                        or type(values[6]) ~= "number"
                        or type(values[11]) ~= "number"
                        or type(values[18]) ~= "boolean" then
                        error("The native Tug of War handler changed; stopped safely.")
                    end
                    return values[6], values[1] ~= nil and values[1] ~= false,
                        values[18], values[11]
                end
                self.Context = context
                self.BindingCount += 1
                self.LastReason = "Native QTE bound"
                return true
            end
        end
    end
    self.LastReason = "Waiting for native QTE click handler"
    return false
end

-- Runs only after the round, phase, character and GUI checks in Step.
-- Context.Read returns the actual native window and its input lock state.
function State:TryPull(context, now)
    local goal = context.Medium.Rotation
    local errorDegrees = angleError(goal, context.Arrow.Rotation)
    local window, blocked, ended, progressBefore = context.Read()
    self.LastAngleError = errorDegrees
    if ended then
        self.LastReason = "QTE ended"
        return
    end
    if blocked then
        context.Armed = false
        self.LockoutSkips += 1
        self.LastReason = "Native miss lockout"
        return
    end
    if not (window > 0 and window <= MAX_WINDOW) then
        error("Unexpected native hit window: " .. tostring(window))
    end
    self.LastWindow = window
    -- Wait for a new goal or a full exit before accepting another pass.
    -- This also handles Rhythmical, which can keep the same goal angle.
    if context.LastGoal ~= nil and angleError(goal, context.LastGoal) > 0.01
        or errorDegrees > window + 2 then
        context.Armed = true
    end
    context.LastGoal = goal
    if not context.Armed or now - self.LastPressAt < MIN_PRESS_INTERVAL then
        self.LastReason = "Waiting for next alignment"
        return
    end
    if errorDegrees > window * 0.55 then
        self.LastReason = "Waiting for center of hit window"
        return
    end

    context.Armed = false
    self.LastPressAt = now
    self.Presses += 1
    context.Press()
    local _, missed, _, progressAfter = context.Read()
    if missed then
        self.LocalMisses += 1
        self:SetEnabled(false)
        self.LastReason = "Stopped after native miss"
    elseif progressAfter > progressBefore or angleError(goal, context.Medium.Rotation) > 0.01 then
        self.LocalAdvances += 1
        self.LastReason = "Native QTE advanced locally"
    else
        self.UnconfirmedPulls += 1
        self.LastReason = "Pull result unconfirmed"
    end
end

function State:ActiveRound()
    local values = workspace:FindFirstChild("Values")
    local currentGame = values and values:FindFirstChild("CurrentGame")
    if not currentGame or currentGame.Value ~= "TugOfWar" then
        return false, "Waiting for Tug of War"
    end
    if LocalPlayer:GetAttribute("TugOfWarPhase") ~= "QTE" then
        return false, "Waiting for QTE phase"
    end
    if LocalPlayer:FindFirstChild("QTEOver") then return false, "QTE finished" end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 or character:FindFirstChild("Dead") then
        return false, "Character unavailable"
    end
    return true
end

function State:Step(now)
    if not self.Enabled or self.Destroyed then return end
    local active, reason = self:ActiveRound()
    if not active then
        self.Context = nil
        self.LastReason = reason
        return
    end
    local context = self.Context
    if context and not context.Root:IsDescendantOf(PlayerGui) then
        self.Context = nil
        context = nil
    end
    if not context then
        if now >= self.NextBindAt then
            self.NextBindAt = now + BIND_RETRY_INTERVAL
            local screen = PlayerGui:FindFirstChild("TugOfWarUIV2")
            self:Bind(screen and screen:FindFirstChild("TugofWarRemake"))
        end
        if not self.Context then self.LastReason = "Waiting for verified QTE handler" end
        return
    end
    if not visible(context.Circle) then self.LastReason = "QTE hidden"; return end
    self:TryPull(context, now)
end

function State:SetEnabled(enabled)
    if self.Destroyed then return end
    self.Enabled = enabled == true
    if self.Engine then self.Engine:Disconnect(); self.Engine = nil end
    self.LastPressAt = -math.huge
    self.Context = nil
    self.NextBindAt = 0
    if self.Enabled then
        self.Engine = RunService.RenderStepped:Connect(function()
            local ok, message = pcall(self.Step, self, os.clock())
            if not ok then
                self.Errors += 1
                self.LastError = tostring(message)
                self:SetEnabled(false)
                self.LastReason = "Stopped: " .. self.LastError
                warn("[Ink Tug] " .. self.LastError)
            end
        end)
    else
        self.LastReason = "Off"
    end
end

function State:GetSnapshot()
    return {
        Version = self.Version, Enabled = self.Enabled,
        BindingCount = self.BindingCount, Bound = self.Context ~= nil,
        Phase = LocalPlayer:GetAttribute("TugOfWarPhase"),
        Presses = self.Presses, LocalAdvances = self.LocalAdvances,
        UnconfirmedPulls = self.UnconfirmedPulls, LocalMisses = self.LocalMisses,
        LockoutSkips = self.LockoutSkips, Status = self.LastReason,
        LastWindow = self.LastWindow, LastAngleError = self.LastAngleError,
        LastReason = self.LastReason, Errors = self.Errors, LastError = self.LastError,
        Note = "QTE advances are measured on the client.",
    }
end

function State:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false)
    self.Destroyed = true
    self.Context = nil
    if Environment.__INK_TUG_AUTO_PULL == self then
        Environment.__INK_TUG_AUTO_PULL = nil
    end
end

Environment.__INK_TUG_AUTO_PULL = State
State:SetEnabled(false)

State.HubOnly=true
return State
