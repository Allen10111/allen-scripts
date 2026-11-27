-- Allen Scripts / Ink Game local movement recovery.
assert(game.GameId==7008097940,"Open Ink Game first")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local state={HubOnly=true,Enabled=false,Destroyed=false,Status="Off",Corrections=0}
local connections={}
local character,humanoid,speedConnection,addedConnection,removedConnection
local baseline,nativeSpeed,forcedSpeed
local writing=false
local function disconnect(c)if c then c:Disconnect()end end
local function restore()
 if humanoid and humanoid.Parent and forcedSpeed and nativeSpeed~=nil and humanoid.WalkSpeed==forcedSpeed then
  writing=true;humanoid.WalkSpeed=nativeSpeed;writing=false
 end
 nativeSpeed=nil;forcedSpeed=nil
end
local function blocked()
 return not humanoid or humanoid.Health<=0 or not character or not character.Parent
  or character:FindFirstChild("Dead") or character:FindFirstChild("Ragdoll")
  or character:FindFirstChild("InCutscene") or character:FindFirstChild("Anchor")
end
local function refresh()
 if not state.Enabled or state.Destroyed or writing then return end
 if blocked()then restore();state.Status="Waiting for movable character";return end
 local speed=humanoid.WalkSpeed
 if not character:FindFirstChild("Stun")then
  -- The native controller resumes its own speed when the stun ends.
  -- Do not restore a stale zero-speed request over that recovery.
  forcedSpeed=nil;nativeSpeed=nil
  if speed>0 then baseline=speed end
  state.Status="Ready";return
 end
 if speed~=forcedSpeed then nativeSpeed=speed end
 local target=baseline and baseline>0 and baseline or 14
 if speed<target then
  forcedSpeed=target;writing=true;humanoid.WalkSpeed=target;writing=false
  state.Corrections+=1
 end
 state.Status="Preserving local movement during stun"
end
local function bind(nextCharacter)
 disconnect(speedConnection);disconnect(addedConnection);disconnect(removedConnection)
 restore()
 character=nextCharacter
 humanoid=character and character:FindFirstChildOfClass("Humanoid")
 baseline=humanoid and humanoid.WalkSpeed>0 and humanoid.WalkSpeed or 14
 if not character then return end
 addedConnection=character.ChildAdded:Connect(function(child)
  if child:IsA("Humanoid")and not humanoid then bind(character)else refresh()end
 end)
 removedConnection=character.ChildRemoved:Connect(refresh)
 if humanoid then speedConnection=humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(refresh)end
 refresh()
end
function state:SetEnabled(enabled)
 enabled=enabled==true
 if self.Destroyed or self.Enabled==enabled then return end
 self.Enabled=enabled
 if enabled then
  bind(player.Character)
  connections[#connections+1]=player.CharacterAdded:Connect(bind)
  connections[#connections+1]=player.CharacterRemoving:Connect(function()bind(nil)end)
  local elapsed=0
  connections[#connections+1]=RunService.Heartbeat:Connect(function(dt)
   elapsed+=dt
   if elapsed>=.1 then elapsed=0;refresh()end
  end)
 else
  disconnect(speedConnection);disconnect(addedConnection);disconnect(removedConnection)
  speedConnection=nil;addedConnection=nil;removedConnection=nil
  for _,c in ipairs(connections)do c:Disconnect()end
  table.clear(connections);restore();character=nil;humanoid=nil;self.Status="Off"
 end
end
function state:GetSnapshot()return {Enabled=self.Enabled,Status=self.Status,Corrections=self.Corrections}end
function state:Destroy()
 if self.Destroyed then return end
 self:SetEnabled(false);self.Destroyed=true
end
return state
