-- Allen Scripts: Blade Ball red-ball sound notice. No automatic input.
assert(game.GameId==4777817887,"Open Blade Ball")
local env=getgenv()
if env.__BLADE_BALL_BEEP then env.__BLADE_BALL_BEEP:Destroy()end
local S={HubOnly=true,Enabled=false,Destroyed=false,Connections={},Roots={},Balls={},Beeps=0,Errors=0,Status="Off"}
local sound=Instance.new("Sound")
sound.Name="AllenRedBallBeep"
sound.SoundId="rbxasset://sounds/electronicpingshort.wav"
sound.Volume=.7;sound.PlaybackSpeed=1.4
sound.Parent=game:GetService("SoundService")
local function disconnect(list)for _,c in ipairs(list)do c:Disconnect()end;table.clear(list)end
function S:IsRed(ball)
    if ball:GetAttribute("realBall")==true then return false end -- the visible clone carries the red flag
    local highlighted=ball:GetAttribute("highlighted")
    if type(highlighted)=="boolean"then return highlighted end
    local color=ball.Color
    return color.R>.6 and color.R>color.G*1.8 and color.R>color.B*1.8
end
function S:Evaluate(ball)
    local record=self.Balls[ball];if not record or not self.Enabled then return end
    local red=ball.Parent~=nil and self:IsRed(ball)
    if red and not record.Red then
        sound:Stop();sound.TimePosition=0;sound:Play()
        self.Beeps+=1
        self.Status="Red ball · beep"
        self.SoundGeneration=(self.SoundGeneration or 0)+1
        local generation=self.SoundGeneration
        task.delay(.16,function()if not self.Destroyed and self.SoundGeneration==generation then sound:Stop()end end)
    end
    record.Red=red
end
function S:Forget(ball)
    local record=self.Balls[ball]
    if record then disconnect(record.Connections);self.Balls[ball]=nil end
end
function S:Watch(ball)
    if not ball:IsA("BasePart")or self.Balls[ball]then return end
    local count=0;for _ in pairs(self.Balls)do count+=1 end
    if count>=64 then return end
    local record={Red=false,Connections={}}
    self.Balls[ball]=record
    local function check()
        local ok,err=pcall(self.Evaluate,self,ball)
        if not ok then self.Errors+=1;self.LastError=tostring(err);self.Status="Alert error"end
    end
    for _,name in ipairs({"highlighted","realBall"})do record.Connections[#record.Connections+1]=ball:GetAttributeChangedSignal(name):Connect(check)end
    record.Connections[#record.Connections+1]=ball:GetPropertyChangedSignal("Color"):Connect(check)
    record.Connections[#record.Connections+1]=ball.AncestryChanged:Connect(function()if not ball.Parent then self:Forget(ball)end end)
    check()
end
function S:Bind(root)
    if self.Roots[root]then return end
    local list={}
    self.Roots[root]=list
    list[#list+1]=root.ChildAdded:Connect(function(ball)self:Watch(ball)end)
    list[#list+1]=root.ChildRemoved:Connect(function(ball)self:Forget(ball)end)
    for _,ball in ipairs(root:GetChildren())do self:Watch(ball)end
end
function S:SetEnabled(on)
    if self.Destroyed then return end
    disconnect(self.Connections)
    for root,list in pairs(self.Roots)do disconnect(list);self.Roots[root]=nil end
    local all={};for ball in pairs(self.Balls)do all[#all+1]=ball end
    for _,ball in ipairs(all)do self:Forget(ball)end
    sound:Stop();self.SoundGeneration=(self.SoundGeneration or 0)+1
    self.Enabled=on==true;self.Status=self.Enabled and "Watching red-ball changes"or"Off"
    if not self.Enabled then return end
    local function add(root)if root.Name=="Balls"or root.Name=="TrainingBalls"then self:Bind(root)end end
    self.Connections[#self.Connections+1]=workspace.ChildAdded:Connect(add)
    self.Connections[#self.Connections+1]=workspace.ChildRemoved:Connect(function(root)
        local list=self.Roots[root];if list then disconnect(list);self.Roots[root]=nil end
        for _,ball in ipairs(root:GetChildren())do self:Forget(ball)end
    end)
    for _,root in ipairs(workspace:GetChildren())do add(root)end
end
function S:GetSnapshot()
    return {Enabled=self.Enabled,Status=self.Status,Beeps=self.Beeps,Errors=self.Errors,SoundLoaded=sound.IsLoaded,LastError=self.LastError}
end
function S:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false);self.Destroyed=true;sound:Destroy()
    if env.__BLADE_BALL_BEEP==self then env.__BLADE_BALL_BEEP=nil end
end
env.__BLADE_BALL_BEEP=S
return S

