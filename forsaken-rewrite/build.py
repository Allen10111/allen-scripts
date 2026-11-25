from pathlib import Path
import json

root=Path(__file__).resolve().parent
s=(root/'base-v5.lua').read_text(encoding='utf-8-sig')
schema=(root/'catalog.lua').read_text(encoding='utf-8-sig')
suite=(root/'suite.lua').read_text(encoding='utf-8-sig')
def once(a,b):
 global s
 assert s.count(a)==1,('missing or duplicate anchor',a[:100])
 s=s.replace(a,b,1)

once('standalone bundle v5','standalone bundle v6 / independent feature suite')
once('local env = type(getgenv)', 'local SUITE_FEATURES=(function()\n'+schema+'\nend)()\nlocal SUITE_LOOKUP={}\nfor _,def in ipairs(SUITE_FEATURES) do SUITE_LOOKUP[def.Key]=def end\nFactories.Suite=(function()\n'+suite+'\nend)()\n\nlocal env = type(getgenv)')
once('local c = {Version=5,','local c = {Version=6,')
once('env.AllensForsaken = c','for _,def in ipairs(SUITE_FEATURES) do if def.Kind~="action" then c.State[def.Key]=def.Default end end\nc.Catalog=SUITE_FEATURES\nenv.AllensForsaken = c')
once('local move, combat, generators','local move, combat, generators, suite')
once('readout.Text=string.format(step<1 and "%.1f%s" or "%.0f%s",value,suffix)','readout.Text=string.format(step<.1 and "%.3f%s" or step<1 and "%.1f%s" or "%.0f%s",value,suffix)')
once('    label(row,title,UDim2.fromOffset(14,12),UDim2.new(1,-88,0,20),13)','    local titleLabel=label(row,title,UDim2.fromOffset(14,8),UDim2.new(1,-88,0,28),13)\n    titleLabel.TextWrapped=true;titleLabel.TextTruncate=Enum.TextTruncate.None')
once('UDim2.fromOffset(14,37),UDim2.new(1,-88,0,24),10,C.Muted','UDim2.fromOffset(14,40),UDim2.new(1,-88,0,26),10,C.Muted')
once('    label(row,title,UDim2.fromOffset(14,12),UDim2.new(1,-125,0,20),12)','    local titleLabel=label(row,title,UDim2.fromOffset(14,8),UDim2.new(1,-125,0,32),12)\n    titleLabel.TextWrapped=true;titleLabel.TextTruncate=Enum.TextTruncate.None')
once('    if c.State.AutoPlay then\n        for _,key in ipairs({Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Space}) do', '    if c.State.AutoPlay and os.clock()>(c.SyntheticInputUntil or 0) then\n        for _,key in ipairs({Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Space}) do')
once('    if processed or UIS:GetFocusedTextBox() then return end','    if processed or UIS:GetFocusedTextBox() or os.clock()<(c.SyntheticInputUntil or 0) then return end')
once('    local function stepDelay() return math.clamp(tonumber(ctx.State.PuzzleStepDelay) or 0.2, 0.1, 3) end', '''    local function stepDelay()
        if ctx.State.SeparatePuzzleTiming then
            local key=({Connect="ConnectPairDelay",Flow="FlowCellDelay",Gear="GearTurnDelay",Lock="LockPressDelay"})[m.Puzzle]
            if key then return math.clamp(tonumber(ctx.State[key]) or .1,.05,3) end
        end
        return math.clamp(tonumber(ctx.State.PuzzleStepDelay) or .2,.1,3)
    end''')
once('callbacks.OnTurn(90)','callbacks.OnTurn(math.clamp(tonumber(ctx.State.GearTurnDegrees) or 90,15,180))')
once('    if key=="Hotkey" then','''    local def=SUITE_LOOKUP[key]
    if def then
        if def.Kind=="number" then
            value=tonumber(value)
            if not value or value~=value or math.abs(value)==math.huge then return false end
            value=math.clamp(value,def.Min,def.Max)
        elseif def.Kind=="choice" then
            if not table.find(def.Options,value) then return false end
        elseif def.Kind=="text" then value=tostring(value):sub(1,180)
        elseif def.Kind=="toggle" then value=value==true
        else return false end
    elseif key=="Hotkey" then''')
once('    safeCall(generators,"Destroy"); safeCall(combat,"Destroy"); safeCall(move,"Destroy")','    safeCall(suite,"Destroy");safeCall(generators,"Destroy"); safeCall(combat,"Destroy"); safeCall(move,"Destroy")')
once('local rail=make("Frame",{Size=UDim2.new(0,132,1,0),BackgroundTransparency=1},body)', '''local rail=make("ScrollingFrame",{Size=UDim2.new(0,132,1,0),BackgroundTransparency=1,BorderSizePixel=0,
    ScrollBarThickness=3,ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.fromOffset(0,1020)},body)''')
once('label(rail,"End / unload",UDim2.new(0,14,1,-37),UDim2.fromOffset(110,16),10,C.Muted)','')
once('for i,name in ipairs({"Automation","Live","Settings"}) do','''local allTabs={"Automation","Stamina","Visual","Generators+","Combat+","Survivors","Killers","Aim","Antis","Items","Misc","Teleport","Animations","Music","Fun","UI","Live","Settings"}
rail.CanvasSize=UDim2.fromOffset(0,60+#allTabs*44)
for i,name in ipairs(allTabs) do''')
once('heading(pages.Automation,"Automation",','''local sectionOrder={}
for _,def in ipairs(SUITE_FEATURES) do
    local page=pages[def.Section]
    if not sectionOrder[def.Section] then
        heading(page,def.Section,"Independent Allen Scripts controls; native game rules apply.")
        sectionOrder[def.Section]=0
    end
    sectionOrder[def.Section]+=1
    local order=sectionOrder[def.Section]
    if def.Kind=="toggle" then toggle(page,def.Key,def.Label,def.Help or "",order)
    elseif def.Kind=="number" then slider(page,def.Key,def.Label,def.Min,def.Max,def.Step,"",order)
    elseif def.Kind=="choice" then
        local row=card(page,def.Key,78,order)
        label(row,def.Label,UDim2.fromOffset(14,8),UDim2.new(1,-28,0,22),12)
        local control=button(row,tostring(c.State[def.Key]),UDim2.fromOffset(14,36),UDim2.new(1,-28,0,30))
        c.Bindings[def.Key]=function(value) control.Text=tostring(value) end
        connect(control.Activated,function()
            local i=table.find(def.Options,c.State[def.Key]) or 0
            c:Set(def.Key,def.Options[i%#def.Options+1])
        end)
    elseif def.Kind=="text" then
        local row=card(page,def.Key,84,order)
        label(row,def.Label,UDim2.fromOffset(14,8),UDim2.new(1,-28,0,22),12)
        local control=make("TextBox",{Position=UDim2.fromOffset(14,38),Size=UDim2.new(1,-28,0,30),
            ClearTextOnFocus=false,Text=tostring(c.State[def.Key]),PlaceholderText="Enter value",Font=Enum.Font.Gotham,
            TextSize=12,TextColor3=C.Text,BackgroundColor3=C.BG,BorderSizePixel=0},row)
        round(control,6)
        c.Bindings[def.Key]=function(value) if not control:IsFocused() then control.Text=tostring(value) end end
        connect(control.FocusLost,function() c:Set(def.Key,control.Text) end)
    elseif def.Kind=="action" then
        local actionRow=card(page,def.Key,52,order)
        local control=button(actionRow,def.Label,UDim2.fromOffset(14,9),UDim2.new(1,-28,0,34))
        connect(control.Activated,function()
            if not suite then c:Notify("Feature suite is initializing");return end
            c:Spawn(function()
                local ok,err=pcall(suite.Action,suite,def.Key)
                c:Notify(ok and def.Label.." completed" or tostring(err))
            end)
        end)
    end
    if order%12==0 then task.wait() end
end
local backgroundImage=make("ImageLabel",{Name="CustomBackground",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
    ImageTransparency=.85,ZIndex=0,Visible=false,ScaleType=Enum.ScaleType.Crop},panel)
heading(pages.Automation,"Automation",''')
once('            PuzzlePacingVersion=4,PuzzleStepDelay=', '            SuiteSettings=(function()local values={} for _,def in ipairs(SUITE_FEATURES) do if def.Kind~="toggle" and def.Kind~="action" then values[def.Key]=c.State[def.Key] end end return values end)(),\n            PuzzlePacingVersion=4,PuzzleStepDelay=')
once('    Notify=function(message) c:Notify(message) end,Status=status}', '''    Notify=function(message) c:Notify(message) end,Status=status,
    Schema=SUITE_FEATURES,Set=function(key,value)return c:Set(key,value)end,
    GetMovement=function()return move end,GetGenerators=function()return generators end,
    SyntheticInput=function()c.SyntheticInputUntil=os.clock()+.15 end}''')
once('elseif name=="Generators" then generators=adapter end','elseif name=="Generators" then generators=adapter elseif name=="Suite" then suite=adapter end')
once('c.Adapters={Movement=move,Combat=combat,Generators=generators}','c.Adapters={Movement=move,Combat=combat,Generators=generators,Suite=suite}')
once('            local preferences=Http:JSONDecode(readfile(CONFIG))','''            local preferences=Http:JSONDecode(readfile(CONFIG))
            if type(preferences.SuiteSettings)=="table" then
                for key,value in pairs(preferences.SuiteSettings) do
                    local def=SUITE_LOOKUP[key]
                    if def and def.Kind~="toggle" and def.Kind~="action" then c:Set(key,value) end
                end
            end''')
once('        c:RefreshGeneratorESP();c:RefreshGearESP()','''        c:RefreshGeneratorESP();c:RefreshGearESP()
        backgroundImage.Visible=c.State.ShowBackgroundImage==true
        local backgroundId=tostring(c.State.BackgroundImage):match("%d+")
        backgroundImage.Image=backgroundId and "rbxassetid://"..backgroundId or ""
        backgroundImage.ImageTransparency=c.State.BackgroundTransparency or .85''')
once('            "\\nLast diagnostic: "..tostring(c.FeatureStatus.Error or "None"),','            "\\nSuite: "..tostring(c.FeatureStatus.Suite or "Ready"),\n            "\\nLast diagnostic: "..tostring(c.FeatureStatus.Error or "None"),')
# The catalogue is part of the actual source, rather than a downloaded engine.
from library import add_library
s=add_library(s)
output=root.parent/'allens_forsaken.lua'
output.write_text(s,encoding='utf-8',newline='\n')
print(json.dumps({'output':str(output),'characters':len(s),'thirdPartyLoader':False}))
