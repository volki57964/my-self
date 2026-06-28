local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local lp = Players.LocalPlayer
local ls = lp:WaitForChild("leaderstats")
local spd = ls:WaitForChild("Speed")
local wins = ls:WaitForChild("Wins")
local rb = ls:FindFirstChild("Rebirths")

local farming = false
local conn = nil
local startWins = wins.Value
local lastWins = wins.Value
local lastCheck = tick()

local function nf(n)
    if type(n)=="number" then
        local s = tostring(math.floor(math.abs(n)))
        local r = ""
        for i = #s, 1, -1 do
            r = s:sub(i,i)..r
            if (#s-i+1)%3==0 and i>1 then r=","..r end
        end
        return if n<0 then "-"..r else r
    end
    return tostring(n)
end

local sg = Instance.new("ScreenGui")
sg.Name = "AutoFarmGui"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.DisplayOrder = 99999
local fr = Instance.new("Frame")
fr.Size = UDim2.new(0,200,0,280); fr.Position = UDim2.new(0,15,0,80)
fr.BackgroundColor3 = Color3.fromRGB(20,20,30); fr.BackgroundTransparency = 0.05
fr.BorderSizePixel = 0; fr.Active = true
Instance.new("UICorner",fr).CornerRadius = UDim.new(0,8)
local dr = Instance.new("Frame",fr)
dr.Size = UDim2.new(1,0,0,26); dr.BackgroundColor3 = Color3.fromRGB(35,35,50)
dr.BorderSizePixel = 0; dr.Active = true
Instance.new("UICorner",dr).CornerRadius = UDim.new(0,8)
local ti = Instance.new("TextLabel",dr)
ti.Size = UDim2.new(1,0,1,0); ti.BackgroundTransparency = 1
ti.Text = "AutoKeys"; ti.TextColor3 = Color3.fromRGB(255,245,220)
ti.Font = Enum.Font.GothamBold; ti.TextSize = 13
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
local spLabel = Instance.new("TextLabel",fr)
spLabel.Size = UDim2.new(1,-16,0,14); spLabel.Position = UDim2.new(0,8,0,32)
spLabel.BackgroundTransparency = 1; spLabel.TextColor3 = Color3.fromRGB(130,200,130)
spLabel.Font = Enum.Font.Gotham; spLabel.TextSize = 10; spLabel.TextXAlignment = Enum.TextXAlignment.Left
local winLabel = Instance.new("TextLabel",fr)
winLabel.Size = UDim2.new(1,-16,0,14); winLabel.Position = UDim2.new(0,8,0,46)
winLabel.BackgroundTransparency = 1; winLabel.TextColor3 = Color3.fromRGB(255,200,80)
winLabel.Font = Enum.Font.Gotham; winLabel.TextSize = 10; winLabel.TextXAlignment = Enum.TextXAlignment.Left
local earnedLabel = Instance.new("TextLabel",fr)
earnedLabel.Size = UDim2.new(1,-16,0,14); earnedLabel.Position = UDim2.new(0,8,0,60)
earnedLabel.BackgroundTransparency = 1; earnedLabel.TextColor3 = Color3.fromRGB(130,200,255)
earnedLabel.Font = Enum.Font.Gotham; earnedLabel.TextSize = 10; earnedLabel.TextXAlignment = Enum.TextXAlignment.Left
local rateLabel = Instance.new("TextLabel",fr)
rateLabel.Size = UDim2.new(1,-16,0,14); rateLabel.Position = UDim2.new(0,8,0,74)
rateLabel.BackgroundTransparency = 1; rateLabel.TextColor3 = Color3.fromRGB(200,160,255)
rateLabel.Font = Enum.Font.Gotham; rateLabel.TextSize = 10; rateLabel.TextXAlignment = Enum.TextXAlignment.Left
local keysLabel = Instance.new("TextLabel",fr)
keysLabel.Size = UDim2.new(1,-16,0,14); keysLabel.Position = UDim2.new(0,8,0,88)
keysLabel.BackgroundTransparency = 1; keysLabel.TextColor3 = Color3.fromRGB(255,200,130)
keysLabel.Font = Enum.Font.Gotham; keysLabel.TextSize = 10; keysLabel.TextXAlignment = Enum.TextXAlignment.Left
keysLabel.Text = "Keys: none"
local stLabel = Instance.new("TextLabel",fr)
stLabel.Size = UDim2.new(1,-16,0,18); stLabel.Position = UDim2.new(0,8,0,106)
stLabel.BackgroundTransparency = 1; stLabel.TextColor3 = Color3.fromRGB(160,160,160)
stLabel.Font = Enum.Font.Gotham; stLabel.TextSize = 11; stLabel.TextXAlignment = Enum.TextXAlignment.Left
stLabel.Text = "Status: Idle"
local tg = Instance.new("TextButton",fr)
tg.Size = UDim2.new(0.5,-11,0,28); tg.Position = UDim2.new(0,8,0,128)
tg.BackgroundColor3 = Color3.fromRGB(55,130,55); tg.BorderSizePixel = 0
tg.Text = "Start"; tg.TextColor3 = Color3.new(1,1,1)
tg.Font = Enum.Font.GothamBold; tg.TextSize = 12
Instance.new("UICorner",tg).CornerRadius = UDim.new(0,5)
local cl = Instance.new("TextButton",fr)
cl.Size = UDim2.new(0.5,-11,0,28); cl.Position = UDim2.new(0.5,3,0,128)
cl.BackgroundColor3 = Color3.fromRGB(160,55,55); cl.BorderSizePixel = 0
cl.Text = "Close"; cl.TextColor3 = Color3.new(1,1,1)
cl.Font = Enum.Font.Gotham; cl.TextSize = 12
Instance.new("UICorner",cl).CornerRadius = UDim.new(0,5)
local disc = Instance.new("TextLabel",fr)
disc.Size = UDim2.new(1,-16,0,14); disc.Position = UDim2.new(0,8,0,162)
disc.BackgroundTransparency = 1; disc.Text = "RightShift to hide"
disc.TextColor3 = Color3.fromRGB(100,100,110); disc.Font = Enum.Font.Gotham; disc.TextSize = 9
disc.TextXAlignment = Enum.TextXAlignment.Left
fr.Parent = sg; sg.Parent = lp:WaitForChild("PlayerGui")

tg.MouseButton1Click:Connect(function()
    farming = not farming
    if farming then
        tg.Text = "Stop"; tg.BackgroundColor3 = Color3.fromRGB(180,55,55)
        startWins = wins.Value; lastWins = wins.Value; lastCheck = tick()
        VIM:SendKeyEvent(true, Enum.KeyCode.W, false, nil)
        conn = RS.Heartbeat:Connect(function()
            spLabel.Text = "Speed: "..spd.Value
            winLabel.Text = "Wins: "..nf(wins.Value)
            earnedLabel.Text = "Earned: "..nf(wins.Value - startWins)
            local now = tick(); local elapsed = now - lastCheck
            if elapsed >= 3 then
                local diff = wins.Value - lastWins
                rateLabel.Text = "Rate: "..nf(math.floor(diff / elapsed * 60)).."/min"
                lastCheck = now; lastWins = wins.Value
            end
        end)
        task.spawn(function()
            while farming do
                local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local pos = root.Position
                    local near = {}
                    for _, c in ipairs(workspace:GetDescendants()) do
                        if c.Name:lower():find("keycap_") and c:IsA("BasePart") then
                            local d = (c.Position - pos).Magnitude
                            if d < 10 then
                                local letter = c.Name:match("keycap_(.)")
                                if letter and not near[letter] then near[letter] = true end
                            end
                        end
                    end
                    local letters = {}
                    for l in pairs(near) do table.insert(letters, l) end
                    if #letters > 0 then
                        keysLabel.Text = "Keys: "..table.concat(letters, ", ")
                        for _, l in ipairs(letters) do
                            local kc = Enum.KeyCode[l]
                            if kc then
                                VIM:SendKeyEvent(true, kc, false, nil)
                                task.wait(0.03)
                                VIM:SendKeyEvent(false, kc, false, nil)
                            end
                        end
                    else
                        keysLabel.Text = "Keys: none"
                    end
                end
                task.wait(0.5)
            end
        end)
    else
        tg.Text = "Start"; tg.BackgroundColor3 = Color3.fromRGB(55,130,55)
        VIM:SendKeyEvent(false, Enum.KeyCode.W, false, nil)
        if conn then conn:Disconnect(); conn=nil end
    end
end)

cl.MouseButton1Click:Connect(function()
    if farming then farming=false
        VIM:SendKeyEvent(false, Enum.KeyCode.W, false, nil)
        if conn then conn:Disconnect(); conn=nil end end
    sg:Destroy()
end)

UIS.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.RightShift then fr.Visible = not fr.Visible end
end)