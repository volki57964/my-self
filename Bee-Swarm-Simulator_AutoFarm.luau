local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local TS = game:GetService("TweenService")
local lp = Players.LocalPlayer
local cs = lp:WaitForChild("CoreStats")
local pv = cs:WaitForChild("Pollen")
local cv = cs:WaitForChild("Capacity")
local hv = cs:WaitForChild("Honey")
local ev = game.ReplicatedStorage:WaitForChild("Events")
local tc = ev:WaitForChild("ToolCollect")
local phc = ev:WaitForChild("PlayerHiveCommand")
local F = {
    {"Sunflower Field", Vector3.new(-208.95, 3, 176.58)},
    {"Dandelion Field", Vector3.new(-30.72, 3, 220.62)},
    {"Mushroom Field", Vector3.new(-89.70, 3, 111.73)},
    {"Blue Flower Field", Vector3.new(146.87, 3, 99.31)},
    {"Clover Field", Vector3.new(157.55, 33, 196.35)},
    {"Strawberry Field", Vector3.new(-178.17, 20, -9.85)},
    {"Spider Field", Vector3.new(-43.47, 20, -13.59)},
    {"Bamboo Field", Vector3.new(132.96, 20, -25.6)},
    {"Pineapple Patch", Vector3.new(256.5, 68, -207.48)},
    {"Stump Field", Vector3.new(424.48, 96, -174.81)},
    {"Cactus Field", Vector3.new(-188.5, 67, -101.6)},
    {"Pumpkin Patch", Vector3.new(-188.5, 67, -183.85)},
    {"Pine Tree Forest", Vector3.new(-328.67, 67, -187.35)},
    {"Rose Field", Vector3.new(-327.46, 19, 129.5)},
    {"Mountain Top Field", Vector3.new(77.68, 175, -165.43)},
    {"Ant Field", Vector3.new(95.88, 31, 594.62)},
    {"Pepper Patch", Vector3.new(-488.76, 122, 535.68)},
    {"Coconut Field", Vector3.new(-254.48, 70, 469.46)},
}
local function getNegateCircle()
    local hc = lp:FindFirstChild("Honeycomb")
    if hc and hc.Value then
        local num = hc.Value.Name:match("Hive(%d+)")
        if num then
            local canvas = workspace.HiveDeco.StickerCanvases:FindFirstChild("StickerCanvas"..num)
            if canvas then
                local ps = canvas:FindFirstChild("PlaceableSurfaces")
                if ps then
                    local nc = ps:FindFirstChild("NegateCircle")
                    if nc then return nc.Position end
                end
            end
        end
    end
    return Vector3.new(-77, 3, 330)
end
local CONVERT = getNegateCircle()
local farming = false
local sel = 1
local conn = nil
local function nf(n)
    local s = tostring(math.floor(math.abs(n)))
    local r = ""
    for i = #s, 1, -1 do
        r = s:sub(i,i)..r
        if (#s-i+1)%3==0 and i>1 then r=","..r end
    end
    return if n<0 then "-"..r else r
end
local function moveTo(tgt)
    local char = lp.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if (root.Position-tgt).Magnitude > 250 then
        TS:Create(root, TweenInfo.new((root.Position-tgt).Magnitude/300, Enum.EasingStyle.Linear), {CFrame=CFrame.new(tgt)}):Play()
    else
        hum:MoveTo(tgt)
    end
end
local function rndPos(idx)
    local c = F[idx][2]
    return Vector3.new(c.X+math.random(-35,35), c.Y, c.Z+math.random(-35,35))
end
-- Always collect nearest token, returns true if token found
local function collectTokens()
    local collectibles = workspace:FindFirstChild("Collectibles")
    if not collectibles then return false end
    local char = lp.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local pos = root.Position
    local closest, closestDist = nil, 40
    for _, c in ipairs(collectibles:GetChildren()) do
        if c:IsA("BasePart") then
            local d = (c.Position - pos).Magnitude
            if d < closestDist then closestDist=d; closest=c.Position end
        end
    end
    if closest then
        hum:MoveTo(closest)
        return true
    end
    return false
end
local sg = Instance.new("ScreenGui")
sg.Name = "AutoFarmGui"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.DisplayOrder = 99999
local fr = Instance.new("Frame")
fr.Size = UDim2.new(0,200,0,340)
fr.Position = UDim2.new(0,15,0,80)
fr.BackgroundColor3 = Color3.fromRGB(20,20,30)
fr.BackgroundTransparency = 0.05
fr.BorderSizePixel = 0
fr.Active = true
Instance.new("UICorner",fr).CornerRadius = UDim.new(0,8)
local dr = Instance.new("Frame",fr)
dr.Size = UDim2.new(1,0,0,26)
dr.BackgroundColor3 = Color3.fromRGB(35,35,50)
dr.BorderSizePixel = 0
dr.Active = true
Instance.new("UICorner",dr).CornerRadius = UDim.new(0,8)
local ti = Instance.new("TextLabel",dr)
ti.Size = UDim2.new(1,0,1,0)
ti.BackgroundTransparency = 1
ti.Text = "AutoFarm"
ti.TextColor3 = Color3.fromRGB(255,245,220)
ti.Font = Enum.Font.GothamBold
ti.TextSize = 13
local dragging, dragStart, frameStart
dr.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=inp.Position; frameStart=fr.Position
        inp.Changed:Connect(function() if inp.UserInputState==Enum.UserInputState.End then dragging=false end end)
    end
end)
UIS.InputChanged:Connect(function(inp)
    if dragging and (inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch) then
        local d = inp.Position-dragStart
        fr.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset+d.X, frameStart.Y.Scale, frameStart.Y.Offset+d.Y)
    end
end)
local st = Instance.new("TextLabel",fr)
st.Size = UDim2.new(1,-16,0,18)
st.Position = UDim2.new(0,8,0,30)
st.BackgroundTransparency = 1
st.Text = "Status: Idle"
st.TextColor3 = Color3.fromRGB(160,160,160)
st.Font = Enum.Font.Gotham
st.TextSize = 11
st.TextXAlignment = Enum.TextXAlignment.Left
local st2 = Instance.new("TextLabel",fr)
st2.Size = UDim2.new(1,-16,0,14)
st2.Position = UDim2.new(0,8,0,48)
st2.BackgroundTransparency = 1
st2.Text = "Pollen: 0 / 0"
st2.TextColor3 = Color3.fromRGB(130,200,130)
st2.Font = Enum.Font.Gotham
st2.TextSize = 10
st2.TextXAlignment = Enum.TextXAlignment.Left
local hLab = Instance.new("TextLabel",fr)
hLab.Size = UDim2.new(1,-16,0,14)
hLab.Position = UDim2.new(0,8,0,62)
hLab.BackgroundTransparency = 1
hLab.Text = "Honey: 0"
hLab.TextColor3 = Color3.fromRGB(255,200,80)
hLab.Font = Enum.Font.Gotham
hLab.TextSize = 10
hLab.TextXAlignment = Enum.TextXAlignment.Left
local list = Instance.new("ScrollingFrame",fr)
list.Size = UDim2.new(1,-16,0,156)
list.Position = UDim2.new(0,8,0,80)
list.BackgroundColor3 = Color3.fromRGB(25,25,38)
list.BackgroundTransparency = 0.3
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.new(0,0,0,#F*22)
Instance.new("UICorner",list).CornerRadius = UDim.new(0,4)
local HIGHLIGHT = Color3.fromRGB(60,90,170)
local NORMAL_BG = Color3.fromRGB(40,40,55)
local btns = {}
local function hl(idx)
    for j,b in ipairs(btns) do
        b.BackgroundColor3 = j==idx and HIGHLIGHT or NORMAL_BG
        b.TextColor3 = j==idx and Color3.new(1,1,1) or Color3.fromRGB(190,190,200)
    end
end
for i,f in ipairs(F) do
    local b = Instance.new("TextButton",list)
    b.Size = UDim2.new(1,-4,0,20)
    b.Position = UDim2.new(0,2,0,(i-1)*22+1)
    b.BackgroundColor3 = NORMAL_BG
    b.BackgroundTransparency = 0.3
    b.BorderSizePixel = 0
    b.Text = f[1]
    b.TextColor3 = Color3.fromRGB(190,190,200)
    b.Font = Enum.Font.Gotham
    b.TextSize = 10
    b.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,3)
    b.MouseButton1Click:Connect(function()
        if farming then return end
        sel = i; hl(i)
        st.Text = "Status: Ready - "..f[1]
        st.TextColor3 = Color3.fromRGB(160,200,255)
    end)
    table.insert(btns,b)
end
local tg = Instance.new("TextButton",fr)
tg.Size = UDim2.new(0.5,-11,0,28)
tg.Position = UDim2.new(0,8,0,244)
tg.BackgroundColor3 = Color3.fromRGB(55,130,55)
tg.BorderSizePixel = 0
tg.Text = "Start"
tg.TextColor3 = Color3.new(1,1,1)
tg.Font = Enum.Font.GothamBold
tg.TextSize = 12
Instance.new("UICorner",tg).CornerRadius = UDim.new(0,5)
local cl = Instance.new("TextButton",fr)
cl.Size = UDim2.new(0.5,-11,0,28)
cl.Position = UDim2.new(0.5,3,0,244)
cl.BackgroundColor3 = Color3.fromRGB(160,55,55)
cl.BorderSizePixel = 0
cl.Text = "Close"
cl.TextColor3 = Color3.new(1,1,1)
cl.Font = Enum.Font.Gotham
cl.TextSize = 12
Instance.new("UICorner",cl).CornerRadius = UDim.new(0,5)
local disc = Instance.new("TextLabel",fr)
disc.Size = UDim2.new(1,-16,0,14)
disc.Position = UDim2.new(0,8,0,280)
disc.BackgroundTransparency = 1
disc.Text = "RightShift to hide"
disc.TextColor3 = Color3.fromRGB(100,100,110)
disc.Font = Enum.Font.Gotham
disc.TextSize = 9
disc.TextXAlignment = Enum.TextXAlignment.Left
fr.Parent = sg
sg.Parent = lp:WaitForChild("PlayerGui")
task.defer(function() hl(1); st.Text = "Status: Ready - "..F[1][1]; st.TextColor3 = Color3.fromRGB(160,200,255) end)
local function setStatus(t, c) st.Text = "Status: "..t; st.TextColor3 = c or Color3.fromRGB(160,160,160) end
local function farmLoop()
    while farming do
        local fn = F[sel][1]
        setStatus("Moving to "..fn, Color3.fromRGB(130,170,255))
        moveTo(F[sel][2])
        task.wait(0.3)
        setStatus("Farming "..fn, Color3.fromRGB(130,255,130))
        local fc = 0; local rc = 0
        while farming do
            -- Always check for tokens first
            collectTokens()
            task.wait(0.15)
            pcall(function() tc:FireServer() end)
            task.wait(0.2)
            rc = rc+1
            if rc>=4 then
                rc=0
                local char = lp.Character
                if char and char:FindFirstChildOfClass("Humanoid") then
                    collectTokens()
                    task.wait(0.2)
                    char:FindFirstChildOfClass("Humanoid"):MoveTo(rndPos(sel))
                end
                task.wait(0.3)
                pcall(function() tc:FireServer() end)
            end
            if pv.Value>=cv.Value then fc=fc+1; if fc>=2 then break end else fc=0 end
            task.wait(0.15)
        end
        if not farming then break end
        setStatus("Converting at hive", Color3.fromRGB(255,200,80))
        moveTo(CONVERT)
        task.wait(1)
        pcall(function() phc:FireServer() end)
        local maxT = 120; local t = 0; local last = pv.Value; local sc = 0
        while t<maxT and farming do
            if pv.Value<=0 then task.wait(1); if pv.Value<=0 then break end end
            task.wait(1)
            t=t+1
            if pv.Value==last then sc=sc+1; if sc>=10 then break end else sc=0; last=pv.Value end
        end
    end
end
tg.MouseButton1Click:Connect(function()
    farming = not farming
    if farming then
        tg.Text = "Stop"
        tg.BackgroundColor3 = Color3.fromRGB(180,55,55)
        setStatus("Starting...", Color3.fromRGB(255,200,100))
        CONVERT = getNegateCircle()
        conn = RS.Heartbeat:Connect(function()
            st2.Text = string.format("Pollen: %s / %s", nf(pv.Value), nf(cv.Value))
            hLab.Text = string.format("Honey: %s", nf(hv.Value))
        end)
        task.spawn(farmLoop)
    else
        tg.Text = "Start"
        tg.BackgroundColor3 = Color3.fromRGB(55,130,55)
        setStatus("Stopped")
        if conn then conn:Disconnect(); conn=nil end
    end
end)
cl.MouseButton1Click:Connect(function()
    if farming then farming=false; if conn then conn:Disconnect(); conn=nil end end
    sg:Destroy()
end)
UIS.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.RightShift then fr.Visible = not fr.Visible end
end)
print("AutoFarm v4 ready")