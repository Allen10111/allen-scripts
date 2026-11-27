def add_library(s):
 def once(a,b):
  nonlocal s
  assert s.count(a)==1,('library anchor',a[:90])
  s=s.replace(a,b,1)
 once('c.Catalog=SUITE_FEATURES','c.Catalog=SUITE_FEATURES\nc.LibraryRows={}\nc.Favorites={}')
 once('local function selectTab(name)\n    c.Tab=name','local refreshLibrary\nlocal function selectTab(name)\n    c.Tab=name\n    if c.Search then c.Search.Text="" end\n    if refreshLibrary then refreshLibrary();return end')
 once('local allTabs={"Automation",','local allTabs={"Library","Favorites","Automation",')
 once('    round(row,8); stroke(row); return row','''    round(row,8); stroke(row)
    if page.Name~="Live" then c.LibraryRows[#c.LibraryRows+1]={Card=row,Category=page.Name,Key=name,Order=order} end
    return row''')
 once('connect(unload.Activated,function() c:Destroy() end)', '''connect(unload.Activated,function() c:Destroy() end)
for _,item in ipairs({{save,"Save preferences"},{unload,"Unload and restore"}}) do
    local control,key=item[1],item[2]
    local row=card(pages.Settings,key,52,control.LayoutOrder)
    control.Parent=row;control.Position=UDim2.fromOffset(14,9);control.Size=UDim2.new(1,-28,0,34)
end
-- Category, favorites and search reuse the same controls and connections.
local searchBox=make("TextBox",{Name="LibrarySearch",Position=UDim2.fromOffset(146,8),Size=UDim2.new(1,-160,0,34),
    ClearTextOnFocus=false,PlaceholderText="Search all features, characters or settings...",Text="",Font=Enum.Font.Gotham,
    TextSize=13,TextColor3=C.Text,PlaceholderColor3=C.Muted,BackgroundColor3=C.Panel,BorderSizePixel=0},body)
round(searchBox,8)
make("UIPadding",{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)},searchBox)
c.Search=searchBox
function c:SaveFavorites()
    if type(writefile)~="function" or type(readfile)~="function" or type(isfile)~="function" or type(makefolder)~="function" then return false end
    local ok=pcall(function()
        local preferences={}
        if isfile(CONFIG) then preferences=Http:JSONDecode(readfile(CONFIG)) end
        preferences.Favorites=table.clone(self.Favorites)
        if type(isfolder)~="function" or not isfolder("AllensForsaken") then makefolder("AllensForsaken") end
        writefile(CONFIG,Http:JSONEncode(preferences))
    end)
    return ok
end
for _,page in pairs(pages) do page.Position=UDim2.fromOffset(132,48);page.Size=UDim2.new(1,-132,1,-48) end
local libraryHeader=make("Frame",{Size=UDim2.new(1,0,0,58),BackgroundTransparency=1,LayoutOrder=-1000},pages.Library)
local libraryTitle=label(libraryHeader,"Feature Library",UDim2.new(),UDim2.new(1,0,0,26),20)
local libraryCount=label(libraryHeader,"",UDim2.fromOffset(0,32),UDim2.new(1,0,0,20),11,C.Muted)
local function searchable(text) return tostring(text):lower():gsub("[^%w]"," ") end
for i,row in ipairs(c.LibraryRows) do
    local terms={row.Category,row.Key}
    local def=SUITE_LOOKUP[row.Key]
    if def then
        local actor=def.Actor or def.ConfigActor
        local aliases={Veeronica="veronica skateboard skating sk8",TwoTime="two time dagger",c00lkidd="coolkid cool kid",JohnDoe="john doe",["1x1x1x1"]="1x4",["007n7"]="007 clone teleport"}
        if actor then terms[#terms+1]=actor;terms[#terms+1]=aliases[actor] or "" end
        for name,alias in pairs(aliases) do if def.Label:find(name,1,true) then terms[#terms+1]=alias end end
    end
    for _,item in ipairs(row.Card:QueryDescendants("TextLabel, TextButton")) do
        if item.Text~="" then terms[#terms+1]=item.Text end
    end
    row.Search=searchable(table.concat(terms," "))
    row.Card.Parent=pages.Library;row.Card.LayoutOrder=i
    for _,child in ipairs(row.Card:GetChildren()) do
        if child:IsA("GuiObject") and child.Position.X.Scale==0 then
            child.Position=UDim2.new(0,child.Position.X.Offset+26,child.Position.Y.Scale,child.Position.Y.Offset)
            if child.Size.X.Scale==1 then child.Size=UDim2.new(1,child.Size.X.Offset-26,child.Size.Y.Scale,child.Size.Y.Offset) end
        end
    end
    local star=button(row.Card,"☆",UDim2.fromOffset(7,11),UDim2.fromOffset(24,24))
    star.BackgroundTransparency=1;star.TextSize=19
    row.Favorite=star
    connect(star.Activated,function()
        c.Favorites[row.Key]=not c.Favorites[row.Key] or nil
        c:SaveFavorites()
        refreshLibrary()
    end)
end
refreshLibrary=function()
    local query=searchable(searchBox.Text)
    local searching=query:find("%S")~=nil
    local selected=c.Tab or "Library"
    pages.Library.Visible=selected~="Live" or searching
    for name,page in pairs(pages) do if name~="Library" then page.Visible=name=="Live" and selected=="Live" and not searching end end
    local count=0
    for _,row in ipairs(c.LibraryRows) do
        local show=searching or selected=="Library" or selected=="Favorites" and c.Favorites[row.Key] or selected==row.Category
        if searching then for word in query:gmatch("%S+") do if not row.Search:find(word,1,true) then show=false;break end end end
        row.Card.Visible=show==true
        if row.Card.Visible then count+=1 end
        row.Favorite.Text=c.Favorites[row.Key] and "★" or "☆"
        row.Favorite.TextColor3=c.Favorites[row.Key] and C.Warning or C.Muted
    end
    libraryTitle.Text=searching and "Search results" or selected=="Library" and "Feature Library" or selected
    libraryCount.Text=count.." controls  /  "..#c.LibraryRows.." total  ·  ☆ to save favorites"
    c.LibraryResultCount=count
    for name,control in pairs(tabs) do
        control.BackgroundColor3=name==selected and C.Hover or C.Panel
        control.TextColor3=name==selected and C.Accent or C.Muted
    end
end
connect(searchBox:GetPropertyChangedSignal("Text"),function()pages.Library.CanvasPosition=Vector2.zero;refreshLibrary()end)
c.RefreshLibrary=refreshLibrary
refreshLibrary()''')
 once('c.RefreshLibrary=refreshLibrary','''local navToggle=button(body,"≡",UDim2.fromOffset(8,8),UDim2.fromOffset(38,34))
navToggle.Name="LibraryCategories";navToggle.TextSize=22;navToggle.Visible=false
connect(navToggle.Activated,function()c.NavigationOpen=not c.NavigationOpen;rail.Visible=c.NavigationOpen end)
c.Rail=rail
c.RefreshLibrary=refreshLibrary''')
 once('    local selected=c.Tab or "Library"','    local selected=c.Tab or "Library"\n    if c.Compact then c.NavigationOpen=false;rail.Visible=false end')
 start=s.index('local function fit()')
 end=s.index('connect(minimize.Activated',start)
 s=s[:start]+'''local function fit()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local v=c.PreviewViewport or camera.ViewportSize
    local w=math.min(860,math.max(280,v.X-24))
    local h=math.min(720,math.max(230,v.Y-80))
    c.WindowWidth=w;c.WindowHeight=h
    c.Compact=v.X<700 or v.Y<550
    scale.Scale=1
    panel.Size=UDim2.fromOffset(w,minimized and 58 or h)
    minimize.Position=UDim2.new(1,-84,0,13)
    close.Position=UDim2.new(1,-44,0,13)
    badge.Position=UDim2.new(1,-180,0,20);badge.Visible=w>=600
    navToggle.Visible=c.Compact
    rail.Visible=not c.Compact or c.NavigationOpen==true
    rail.ZIndex=c.Compact and 30 or 1
    rail.Position=UDim2.fromOffset(0,c.Compact and 48 or 0)
    rail.Size=UDim2.new(0,132,1,c.Compact and -48 or 0)
    rail.BackgroundTransparency=c.Compact and 0 or 1;rail.BackgroundColor3=C.BG
    searchBox.Position=UDim2.fromOffset(c.Compact and 54 or 146,8)
    searchBox.Size=UDim2.new(1,c.Compact and -68 or -160,0,34)
    for _,page in pairs(pages) do
        page.Position=UDim2.fromOffset(c.Compact and 0 or 132,48)
        page.Size=UDim2.new(1,c.Compact and 0 or -132,1,-48)
    end
    local x,y=panel.AbsolutePosition.X,panel.AbsolutePosition.Y
    if not c.WindowFitted then x=(v.X-w)/2;y=(v.Y-h)/2;c.WindowFitted=true end
    panel.Position=UDim2.fromOffset(math.clamp(x,8,math.max(8,v.X-w-8)),math.clamp(y,8,math.max(8,v.Y-(minimized and 58 or h)-8)))
end
function c:SetMinimized(value)
    minimized=value==true;body.Visible=not minimized;minimize.Text=minimized and "+" or "-";fit()
end
function c:PreviewLayout(width,height)
    c.PreviewViewport=Vector2.new(width,height);c.WindowFitted=false;fit()
end
function c:RestoreLayout()
    c.PreviewViewport=nil;c.WindowFitted=false;fit()
end
''' + s[end:]
 a=s.index('connect(minimize.Activated,function()')
 b=s.index('connect(header.InputBegan',a)
 s=s[:a]+'''connect(minimize.Activated,function()c:SetMinimized(not minimized)end)
'''+s[b:]
 once('SuiteSettings=(function()', 'Favorites=c.Favorites,SuiteSettings=(function()')
 once('            if type(preferences.SuiteSettings)=="table" then','''            if type(preferences.Favorites)=="table" then
                for _,row in ipairs(c.LibraryRows) do if preferences.Favorites[row.Key]==true then c.Favorites[row.Key]=true end end
            end
            if type(preferences.SuiteSettings)=="table" then''')
 once('selectTab("Automation")\nlocal elapsed,displayElapsed','selectTab("Library")\nlocal elapsed,displayElapsed')
 return s
