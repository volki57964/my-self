--[[
    GOD WEAPON - Survive Zombie Arena
    Modifies weapon config for 0 spread + max pellets + rapid fire
    Auto-aims at nearest zombie
]]--

local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local LP = game.Players.LocalPlayer
local UIS = game:GetService("UserInputService")

-- ====== WEAPON CONFIG MODS ======
local gc = require(RS.Data.GunConfig)
local mods = {
    Minigun = {Spread = 0, PelletCount = 100, Damage = gc.Guns.Minigun.Damage},
    Pistol = {SpreadAngle = 0, PelletCount = 50, Damage = gc.Guns.Pistol.Damage},
    Rifle = {SpreadAngle = 0, PelletCount = 50, Damage = gc.Guns.Rifle.Damage},
    ShotGun = {SpreadAngle = 0, PelletCount = 50, Damage = gc.Guns.ShotGun.Damage},
    AK47 = {SpreadAngle = 0, PelletCount = 50, Damage = gc.Guns.AK47.Damage},
    SMG = {SpreadAngle = 0, PelletCount = 50, Damage = gc.Guns.SMG.Damage},
    Flamethrower = {Spread = 0, PelletCount = 100},
    ["Scar-H"] = {SpreadAngle = 0, PelletCount = 50},
    HoneyBadger = {SpreadAngle = 0, PelletCount = 50},
    TommyGun = {SpreadAngle = 0, PelletCount = 50},
    Sniper = {SpreadAngle = 0, PelletCount = 30},
    P90 = {SpreadAngle = 0, PelletCount = 50},
    MP5 = {SpreadAngle = 0, PelletCount = 50},
    BurstRifle = {SpreadAngle = 0, PelletCount = 50},
}

for name, mod in pairs(mods) do
    if gc.Guns[name] then
        for k, v in pairs(mod) do
            gc.Guns[name][k] = v
        end
    end
end

print("[GOD] Weapon config modified: "..gc.Guns.Minigun.PelletCount.." pellets, Spread="..tostring(gc.Guns.Minigun.Spread))

-- ====== STATE ======
local running = true
local startKills = LP.leaderstats:FindFirstChild("Kills") and LP.leaderstats.Kills.Value or 0
local lastKills = startKills

-- ====== HELPER ======
local function nf(n)
    if type(n) ~= "number" then return tostring(n) end
    local s = tostring(math.floor(math.abs(n)))
    local r = ""
    for i = #s, 1, -1 do
        r = s:sub(i,i)..r
        if (#s-i+1)%3==0 and i>1 then r=","..r end
    end
    return n<0 and "-"..r or r
end

local function isEnemy(model, playerChar)
    if not model:IsA("Model") then return false end
    if model == playerChar then return false end
    local hum = model:FindFirstChild("Humanoid")
    return hum ~= nil
end

-- ====== GUI ======
local sg = Instance.new("ScreenGui")
sg.Name = "GodWeapon"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true
sg.DisplayOrder = 2147483647; sg.ZIndexBehavior = Enum.ZIndexBehavior.Global

local fr = Instance.new("Frame")
fr.Size = UDim2.new(0,200,0,110); fr.Position = UDim2.new(0.5,-100,0,10)
fr.BackgroundColor3 = Color3.fromRGB(15,5,5); fr.BackgroundTransparency = 0.08
fr.BorderSizePixel = 0; fr.Active = true
Instance.new("UICorner",fr).CornerRadius = UDim.new(0,8)

-- Draggable header
local dr = Instance.new("Frame",fr)
dr.Size = UDim2.new(1,0,0,24); dr.BackgroundColor3 = Color3.fromRGB(40,10,10)
dr.BorderSizePixel = 0; dr.Active = true
Instance.new("UICorner",dr).CornerRadius = UDim.new(0,8)
local ti = Instance.new("TextLabel",dr)
ti.Size = UDim2.new(1,0,1,0); ti.BackgroundTransparency = 1
ti.Text = "GOD WEAPON"; ti.TextColor3 = Color3.fromRGB(255,100,100)
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
        fr.Position = UDim2.new(frameStart.X.Scale,frameStart.X.Offset+d.X,frameStart.Y.Scale,frameStart.Y.Offset+d.Y)
    end
end)

local killsLabel = Instance.new("TextLabel",fr)
killsLabel.Size = UDim2.new(1,-16,0,16); killsLabel.Position = UDim2.new(0,8,0,30)
killsLabel.BackgroundTransparency = 1; killsLabel.Text = "Kills: "..nf(startKills)
killsLabel.TextColor3 = Color3.fromRGB(255,180,80); killsLabel.Font = Enum.Font.GothamBold; killsLabel.TextSize = 11
killsLabel.TextXAlignment = Enum.TextXAlignment.Left

local earnedLabel = Instance.new("TextLabel",fr)
earnedLabel.Size = UDim2.new(1,-16,0,14); earnedLabel.Position = UDim2.new(0,8,0,48)
earnedLabel.BackgroundTransparency = 1; earnedLabel.Text = "Earned: 0"
earnedLabel.TextColor3 = Color3.fromRGB(130,255,130); earnedLabel.Font = Enum.Font.Gotham; earnedLabel.TextSize = 10
earnedLabel.TextXAlignment = Enum.TextXAlignment.Left

local rateLabel = Instance.new("TextLabel",fr)
rateLabel.Size = UDim2.new(1,-16,0,14); rateLabel.Position = UDim2.new(0,8,0,64)
rateLabel.BackgroundTransparency = 1; rateLabel.Text = "Rate: -/min"
rateLabel.TextColor3 = Color3.fromRGB(180,160,255); rateLabel.Font = Enum.Font.Gotham; earnedLabel.TextSize = 10
rateLabel.TextXAlignment = Enum.TextXAlignment.Left

local stopBtn = Instance.new("TextButton",fr)
stopBtn.Size = UDim2.new(1,-16,0,26); stopBtn.Position = UDim2.new(0,8,0,80)
stopBtn.BackgroundColor3 = Color3.fromRGB(120,20,20); stopBtn.BorderSizePixel = 0
stopBtn.Text = "STOP"; stopBtn.TextColor3 = Color3.new(1,1,1)
stopBtn.Font = Enum.Font.GothamBold; stopBtn.TextSize = 12
Instance.new("UICorner",stopBtn).CornerRadius = UDim.new(0,5)

fr.Parent = sg; sg.Parent = LP:WaitForChild("PlayerGui")

stopBtn.MouseButton1Click:Connect(function()
    running = false; sg:Destroy()
end)

-- ====== MAIN LOOP ======
local rateCheck = tick()
local rateCheckKills = startKills

task.spawn(function()
    while running do
        local char = LP.Character
        if not char then task.wait(0.1); continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then task.wait(0.1); continue end

        -- Find nearest enemy
        local bestZombie, bestDist = nil, 9999
        for _,v in ipairs(WS:GetDescendants()) do
            if isEnemy(v, char) then
                local hum = v.Humanoid
                if hum.Health > 0 then
                    local hrp = v:FindFirstChild("HumanoidRootPart") or v:FindFirstChild("Head") or v.PrimaryPart
                    if hrp then
                        local d = (hrp.Position - root.Position).Magnitude
                        if d < bestDist then bestDist = d; bestZombie = hrp end
                    end
                end
            end
        end

        if bestZombie then
            -- Aim
            pcall(function()
                local lookAt = Vector3.new(bestZombie.Position.X, root.Position.Y, bestZombie.Position.Z)
                root.CFrame = CFrame.lookAt(root.Position, lookAt)
            end)

            -- FIRE: spam shots at zombie
            for i = 1, 5 do
                pcall(function()
                    RS.NetRemotes.GunFire:FireServer(bestZombie.Position)
                end)
            end
        end

        -- Update UI every 1s
        local now = tick()
        if now - rateCheck > 1 then
            local kills = LP.leaderstats:FindFirstChild("Kills")
            local currentKills = kills and kills.Value or 0
            killsLabel.Text = "Kills: "..nf(currentKills)
            earnedLabel.Text = "Earned: "..nf(currentKills - startKills)
            if now - rateCheck > 5 then
                rateLabel.Text = "Rate: "..nf(math.floor((currentKills - rateCheckKills)/(now - rateCheck)*60)).."/min"
                rateCheck = now
                rateCheckKills = currentKills
            end
        end

        task.wait(0.02)
    end
end)

warn("[GOD] God Weapon injected — auto-aim + 0 spread + 100 pellets")
print("[GOD] Active! Kills: "..nf(startKills))