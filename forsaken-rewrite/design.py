from pathlib import Path

def add_design(s):
 def once(a,b):
  nonlocal s
  assert s.count(a)==1,('design anchor',a[:100])
  s=s.replace(a,b,1)
 s=s.replace('"Generators+"','"Generators"').replace('"Combat+"','"Combat"')
 once('standalone bundle v6 / independent feature suite','standalone bundle v9 / independent feature library')
 once('local c = {Version=6,','local c = {Version=9,')
 once('c.Gui=gui','c.Gui=gui\ngui.Enabled=false\npcall(function()gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets end)\nif type(gethui)=="function" then pcall(function()local mount=gethui();if mount then gui.Parent=mount end end) end')
 once('    c.Tab=name\n    if c.Search then','    c.Tab=name\n    if pages.Library then pages.Library.CanvasPosition=Vector2.zero end\n    if c.Search then')
 once('c.Ready=true','c.Ready=true\nfit();gui.Enabled=true')
 module=(Path(__file__).parent/'design.lua').read_text(encoding='utf-8-sig')
 once('local env = type(getgenv)','local UIFactory=(function()\n'+module+'\nend)()\nlocal env = type(getgenv)')
 once('for i,row in ipairs(c.LibraryRows) do','''local organized={AutoPlay="Generators",AutoFarmGenerators="Generators",AutoRotateGear="Generators",GeneratorESP="Generators",
    ThreatRadius="Generators",FarmDelay="Generators",PuzzleStepDelay="Generators",InfiniteStamina="Stamina",
    AutoBlock="Combat",BlockRange="Combat",AntiDebuff="Antis",GearESP="Items"}
for _,row in ipairs(c.LibraryRows) do row.Category=organized[row.Key] or row.Category end
for i,row in ipairs(c.LibraryRows) do''')
 once('local w=math.min(860,','local w=math.min(1040,')
 once('local h=math.min(720,','local h=math.min(780,')
 once('    local v=c.PreviewViewport or camera.ViewportSize','''    local available=gui.AbsoluteSize
    local v=c.PreviewViewport or (available.X>200 and available.Y>200 and available or camera.ViewportSize)
    local keyboardOpen=false
    if not c.PreviewViewport and UIS.OnScreenKeyboardVisible and UIS.OnScreenKeyboardPosition.Y>260 then
        keyboardOpen=true
        v=Vector2.new(v.X,math.min(v.Y,UIS.OnScreenKeyboardPosition.Y-12))
    end''')
 once('    c.WindowWidth=w;c.WindowHeight=h','''    if v.X<700 then
        w=math.min(330,math.floor(v.X*.86),v.X-24);h=math.min(460,math.floor(v.Y*.60),v.Y-80)
    elseif v.Y<550 then
        w=math.min(520,math.floor(v.X*.66));h=math.min(330,math.floor(v.Y*.80),v.Y-60)
    elseif UIS.TouchEnabled and not UIS.KeyboardEnabled then
        w=math.min(740,math.floor(v.X*.78));h=math.min(560,math.floor(v.Y*.70))
    end
    if keyboardOpen then h=math.min(h+180,v.Y-16) end
    c.WindowWidth=w;c.WindowHeight=h''')
 once('function c:SetMinimized(value)','''pcall(function()
    connect(UIS:GetPropertyChangedSignal("OnScreenKeyboardVisible"),fit)
    connect(UIS:GetPropertyChangedSignal("OnScreenKeyboardPosition"),fit)
    connect(gui:GetPropertyChangedSignal("AbsoluteSize"),fit)
end)
function c:SetMinimized(value)''')
 once('    local x,y=panel.AbsolutePosition.X,panel.AbsolutePosition.Y','    if c.UI then c.UI:Layout(w,h,c.Compact) end\n    local x,y=panel.AbsolutePosition.X,panel.AbsolutePosition.Y')
 once('    local x,y=panel.AbsolutePosition.X,panel.AbsolutePosition.Y','    local x,y=panel.Position.X.Offset,panel.Position.Y.Offset\n    if c.DragNormalized and c.WindowFitted and not dragging then x=8+c.DragNormalized.X*math.max(0,v.X-w-16);y=8+c.DragNormalized.Y*math.max(0,v.Y-(minimized and 58 or h)-16) end')
 a=s.index('connect(header.InputBegan,function(input)')
 b=s.index('connect(UIS.InputBegan,function(input,processed)',a)
 s=s[:a]+'''-- One pointer owns a drag. A second finger cannot cancel or hijack it.
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
''' + s[b:]
 once('            draggingSlider={Input=input,Update=update}; update(input.Position.X)','            if dragging or draggingSlider then return end\n            draggingSlider={Input=input,Update=update}; update(input.Position.X)')
 once('c.Adapters={Movement=move,Combat=combat,Generators=generators,Suite=suite}', '''c.Adapters={Movement=move,Combat=combat,Generators=generators,Suite=suite}
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
end''')
 once('    if gui then gui:Destroy() end','    if self.UI then self.UI:Destroy() end\n    if gui then gui:Destroy() end')
 return s
