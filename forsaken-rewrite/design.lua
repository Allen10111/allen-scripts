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
  row.TextLayout={}
  for _,text in ipairs(row.Card:GetChildren())do
   if text:IsA("TextLabel") and text~=footer and text~=stateLabel then
    row.TextLayout[#row.TextLayout+1]={Object=text,Position=text.Position,Size=text.Size,Wrapped=text.TextWrapped,Alignment=text.TextYAlignment,
     Description=text.Position.Y.Offset>=30 and text.Position.X.Scale==0}
   end
  end
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
   for _,item in ipairs(row.TextLayout)do
    local text=item.Object
    text.Position=item.Position;text.Size=item.Size;text.TextWrapped=item.Wrapped;text.TextYAlignment=item.Alignment
    if compact then
     if item.Description then
      text.Position=UDim2.new(item.Position.X.Scale,item.Position.X.Offset,0,36)
      text.Size=UDim2.new(item.Size.X.Scale,item.Size.X.Offset,0,30)
      text.TextWrapped=true;text.TextYAlignment=Enum.TextYAlignment.Top
     elseif item.Position.X.Scale==0 then
      text.Position=UDim2.new(0,item.Position.X.Offset,0,10)
      text.Size=UDim2.new(item.Size.X.Scale,item.Size.X.Offset,0,22)
      text.TextWrapped=false;text.TextYAlignment=Enum.TextYAlignment.Center
     end
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
