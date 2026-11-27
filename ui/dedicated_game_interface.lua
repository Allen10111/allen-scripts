-- Allen Scripts interface adapter for dedicated game backends.
return function(app,gameName,providedLibrary)
 local hajime=gameName=="Hajime Rising"
 local legacy=app.Gui
 if legacy then legacy.Enabled=false end
 local library=providedLibrary
 if not library then
  local source=game:HttpGet("https://raw.githubusercontent.com/Allen10111/allen-scripts/main/ui/moroelite_allen.lua?build=r60&t="..tostring(os.time()))
  library=assert(loadstring(source,"AllenScripts/Interface"))()
 end
 library.Folder="AllenScriptsUI"
 local ui=library:CreateWindow({Title="Allen Scripts Hub",Subtitle="Allen10111 · "..gameName,
  Logo=false,Art=false,MenuArt=false,OpenControl="Button",TopButtons={"bell","settings"},
  LoaderSound=false,NotifySound=false,Blur=false,
  TeleportUrl="https://raw.githubusercontent.com/Allen10111/allen-scripts/main/allen_scripts_hub.lua"})
 app.AllenUI=ui;app.AllenUILibrary=library;app.Gui=ui.Gui
 ui.Gui.Name="AllenScripts_"..gameName:gsub("%W","")
 ui.Gui.DisplayOrder=1000020
 local state=hajime and app.State.Config or app.State
 local controls,tabs,sections={},{},{}
 local stopped=false
 local originalDestroy=hajime and app.Unload or app.Destroy
 local function unload()
  if stopped then return end
  stopped=true
  if hajime then originalDestroy()else originalDestroy(app)end
  if legacy and legacy.Parent then legacy:Destroy()end
  library:Unload()
 end
 if hajime then app.Unload=unload else app.Destroy=unload end
 library:OnUnload(function()
  if stopped then return end
  stopped=true
  if hajime then originalDestroy()else originalDestroy(app)end
  if legacy and legacy.Parent then legacy:Destroy()end
 end)
 if hajime then
  app.Notify=function(text,kind,duration)ui:Notify({Title="Allen Scripts · "..gameName,Text=tostring(text),Type=kind or "info",Duration=duration,Sound=false})end
  app.UIUpdate=nil
 else
  app.Notify=function(_,text)ui:Notify({Title="Allen Scripts · "..gameName,Text=tostring(text),Sound=false})end
 end
 local function set(key,value)
  local ok,err
  if hajime then ok,err=app.Set(key,value)else ok,err=app:Set(key,value)end
  if ok==false then ui:Notify({Title="Setting not applied",Text=tostring(err or key),Type="warning",Sound=false})end
 end
 local function section(tabName,name)
  tabName=tabName=="Settings" and "Game Settings" or tabName
  local tab=tabs[tabName]
  if not tab then
   tab=ui:CreateTab({Name=tabName,Icon="sliders-horizontal"});tabs[tabName]=tab
   tab.RightCol.Frame.Visible=false;tab.LeftCol.Frame.Size=UDim2.new(1,0,0,0)
  end
  local id=tabName.."/"..name
  if not sections[id]then sections[id]=tab:Column("left"):CreateSection({Name=name})end
  return sections[id]
 end
 local specs={}
 if hajime then
  for _,spec in ipairs(app.UIControls or {})do
   local parent=spec.Parent
   local card=app.UICards and app.UICards[parent]
   specs[#specs+1]={Kind=spec.Kind,Label=spec.Label,Key=spec.Key,Description=spec.Description,
    Min=spec.Min,Max=spec.Max,Step=spec.Step,Suffix=spec.Suffix,Options=spec.Options,Callback=spec.Callback,
    Tab=card and card.Tab or "Training",Section=card and card.Title or "Controls"}
   if spec.Label=="Unload script"then specs[#specs].Callback=unload end
  end
 else
  local defs={}
  for _,def in ipairs(app.Catalog or {})do defs[def.Key]=def end
  local ranges={ThreatRadius={20,90,1},FarmDelay={.4,2.5,.1},PuzzleStepDelay={.1,3,.1},BlockRange={8,18,1}}
  for _,row in ipairs(app.LibraryRows or {})do
   local def=defs[row.Key]
   local label=def and def.Label or row.Key
   if row.Card then
    local title=row.Card:FindFirstChild("FeatureTitle")
    if title then label=title.Text end
   end
   local value=state[row.Key]
   local kind=def and def.Kind or type(value)=="boolean"and"toggle"or type(value)=="number"and"number"or"action"
   if row.Key=="Hotkey"then kind="key"end
   local range=ranges[row.Key]or{0,100,1}
   local callback
   if kind=="action"then
    local key=row.Key
    if key=="Save preferences"then callback=app.SavePreferences
    elseif key=="Unload and restore"then callback=unload
    else callback=function()assert(app.Adapters and app.Adapters.Suite,"Feature suite is not ready");return app.Adapters.Suite:Action(key)end end
   end
   specs[#specs+1]={Kind=kind,Label=label,Key=row.Key,Tab=row.Category or "Features",Section=row.Category or "Features",
    Min=def and def.Min or range[1],Max=def and def.Max or range[2],Step=def and def.Step or range[3],
    Options=def and def.Options,Callback=callback}
  end
 end
 local function options(spec)
  if type(spec.Options)=="function"then local ok,list=pcall(spec.Options);return ok and list or {}end
  return spec.Options or {}
 end
 for _,spec in ipairs(specs)do
  local target=section(spec.Tab,spec.Section)
  local cfg={Name=spec.Label,Description=spec.Description,NoConfig=true,NoFastMenu=true}
  cfg.Callback=function(value)set(spec.Key,value)end
  local control
  if spec.Kind=="toggle"then
   cfg.Default=false;control=target:AddToggle(cfg);control:Set(state[spec.Key]==true,true)
  elseif spec.Kind=="number"then
   cfg.Min=spec.Min or 0;cfg.Max=spec.Max or 100;cfg.Default=state[spec.Key]or cfg.Min
   cfg.Decimals=(spec.Step or 1)<.1 and 3 or (spec.Step or 1)<1 and 2 or 0;cfg.Suffix=spec.Suffix
   control=target:AddSlider(cfg)
  elseif spec.Kind=="key"then
   cfg.Options={"RightShift","LeftShift","RightControl","LeftControl","Insert","Home","F4","F6","F8","F10"}
   cfg.Default=state[spec.Key].Name;cfg.Callback=function(v)set(spec.Key,Enum.KeyCode[v]);ui:SetToggleKey(Enum.KeyCode[v])end
   control=target:AddDropdown(cfg)
  elseif spec.Kind=="choice"then
   cfg.Options=options(spec);cfg.Default=state[spec.Key];control=target:AddDropdown(cfg)
  elseif spec.Kind=="text"then
   cfg.Default=tostring(state[spec.Key]or"");control=target:AddTextbox(cfg)
  elseif spec.Callback then
   cfg.Callback=function()
    task.spawn(function()if stopped then return end;local ok,err=pcall(spec.Callback);if not ok then ui:Notify({Title=spec.Label,Text=tostring(err),Type="error",Sound=false})end end)
   end
   target:AddButton(cfg)
  end
  if control then controls[#controls+1]={Control=control,Spec=spec}end
 end
 if hajime then
  app.Bind("Visible",function(v)ui:Toggle(v)end)
  app.Bind("ToggleKey",function(v)ui:SetToggleKey(Enum.KeyCode[v])end)
  app.Bind("Accent",function(v)pcall(library.SetAccent,library,Color3.fromHex(v))end)
  local stats=section("Dashboard","Session")
  local cached,at={},0
  local function dashboard()if os.clock()-at>.5 then at=os.clock();cached=app.GetDashboard()end;return cached end
  for _,key in ipairs({"Status","Reps","Cash","CombatStatus"})do stats:AddStat({Name=key,Get=function()return tostring(dashboard()[key]or"--")end})end
 else
  section("Live","Diagnostics"):AddStat({Name="Status",Get=function()return tostring(app.FeatureStatus.Error or app.NavStatus or "Ready")end})
 end
 ui:AddSettingsTab();ui.Watermark.Visible=true
 app.AllenControlCount=#specs
 local first=tabs.Dashboard or tabs.Generators or tabs.Training
 if first then ui:SelectTab(first)end
 task.spawn(function()
  while not stopped and (hajime and app.Alive or not hajime and not app.Destroyed)do
   for _,entry in ipairs(controls)do
    local spec=entry.Spec
    if spec.Kind=="choice"and type(spec.Options)=="function"then
     local list=options(spec);local signature=table.concat(list,"\0")
     if signature~=entry.OptionsSignature then entry.OptionsSignature=signature;entry.Control:Refresh(list,true)end
    end
    local value=state[spec.Key]
    if spec.Kind=="key"then value=value.Name end
    if value~=nil and entry.Control:Get()~=value then entry.Control:Set(value,true)end
   end
   task.wait(.5)
  end
 end)
 return ui
end
