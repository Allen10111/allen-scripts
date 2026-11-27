-- Red Light injury relief: native injury markers only; no health/death changes.
assert(game.GameId==7008097940,"Open Ink Game first")
local player=game:GetService("Players").LocalPlayer
local state={Version=2,HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Removed=0}
local connections={}
local childConnection
local generation=0
local function disconnect(c) if c then c:Disconnect() end end
local function active()
    local values=workspace:FindFirstChild("Values")
    local current=values and values:FindFirstChild("CurrentGame")
    return state.Enabled and not state.Destroyed and current and current.Value=="RedLightGreenLight"
end
local function remove(marker,character)
    if active() and player.Character==character and marker.Parent==character
        and (marker.Name=="InjuredWalking" or marker.Name=="Crawling"
            or marker.Name=="Stun" and (marker:GetAttribute("InjuredWalking") or marker:GetAttribute("Crawling"))) then
        marker:Destroy()
        state.Removed+=1
    end
end
local function refresh()
    state.Status=not state.Enabled and "Off" or active() and "Red Light injury relief (local)" or "Waiting for Red Light"
    if not active() then return end
    local character=player.Character
    if character then
        for _,marker in ipairs(character:GetChildren())do remove(marker,character)end
    end
end
local function bind(character)
    disconnect(childConnection);childConnection=nil
    if character then
        childConnection=character.ChildAdded:Connect(function(marker)
            task.defer(function()remove(marker,character)end)
        end)
    end
    refresh()
end
function state:SetEnabled(enabled)
    enabled=enabled==true
    if self.Destroyed or self.Enabled==enabled then return end
    self.Enabled=enabled
    generation+=1
    if enabled then
        connections[#connections+1]=player.CharacterAdded:Connect(bind)
        bind(player.Character)
        local token=generation
        task.spawn(function()
            while state.Enabled and not state.Destroyed and generation==token do
                task.wait(.15)
                if state.Enabled and not state.Destroyed and generation==token then refresh()end
            end
        end)
    else
        disconnect(childConnection);childConnection=nil
        for _,c in ipairs(connections)do c:Disconnect()end
        table.clear(connections);self.Status="Off"
    end
end
function state:GetSnapshot()return {Version=self.Version,Enabled=self.Enabled,Status=self.Status,Removed=self.Removed}end
function state:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true
end
return state