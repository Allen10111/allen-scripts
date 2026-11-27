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
