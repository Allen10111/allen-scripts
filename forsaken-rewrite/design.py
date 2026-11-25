from pathlib import Path

def add_design(s):
 def once(a,b):
  nonlocal s
  assert s.count(a)==1,('design anchor',a[:100])
  s=s.replace(a,b,1)
 s=s.replace('"Generators+"','"Generators"').replace('"Combat+"','"Combat"')
 once('standalone bundle v6 / independent feature suite','standalone bundle v7 / independent feature library')
 once('local c = {Version=6,','local c = {Version=7,')
 once('c.Gui=gui','c.Gui=gui\ngui.Enabled=false\nif type(gethui)=="function" then pcall(function()local mount=gethui();if mount then gui.Parent=mount end end) end')
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
 once('    local x,y=panel.AbsolutePosition.X,panel.AbsolutePosition.Y','    if c.UI then c.UI:Layout(w,h,c.Compact) end\n    local x,y=panel.AbsolutePosition.X,panel.AbsolutePosition.Y')
 once('c.Adapters={Movement=move,Combat=combat,Generators=generators,Suite=suite}', '''c.Adapters={Movement=move,Combat=combat,Generators=generators,Suite=suite}
c.UI=UIFactory({App=c,Palette=C,Gui=gui,Panel=panel,Body=body,Header=header,Rail=rail,Tabs=tabs,Pages=pages,
    Search=searchBox,LibraryHeader=libraryHeader,Title=libraryTitle,Count=libraryCount,Badge=badge,
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
