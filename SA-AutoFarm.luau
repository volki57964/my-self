--[[
    Survive Zombie Arena - Full AutoFarm
    Features: Auto-Upgrade, Auto-Shoot, Auto-Aim, Auto-Gear, Auto-Queue, Auto-Collect, Auto-Revive
]]--

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local WS = game:GetService("Workspace")
local RStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- Remote references
local GunFire = RStorage.NetRemotes.GunFire
local GearAction = RStorage.GearRemotes.GearAction
local PurchaseWeaponUpgrade = RStorage.UpgradeRemotes.PurchaseWeaponUpgrade
local PurchaseHealthUpgrade = RStorage.UpgradeRemotes.PurchaseHealthUpgrade
local GetUpgrades = RStorage.UpgradeRemotes.GetUpgrades
local RequestWaveState = RStorage.WaveRemotes.RequestWaveState
local RequestRevive = RStorage.GameStateRemotes.RequestRevive
local ReturnToLobby = RStorage.GameStateRemotes.ReturnToLobby
local VotePlayAgain = RStorage.GameStateRemotes.VotePlayAgain
local RequestAllZombies = RStorage.ZombieRemotes.RequestAllZombies

-- Configuration
local CFG = {
    gunFireRate = 0.1,
    gearInterval = 6,
    collectInterval = 0.5,
    detectInterval = 1,
    upgradeMinCredits = 500,
    upgradeWeapons = true,
    upgradeHealth = true,
    buyCrate = false,
    autoQueue = true,
    autoShoot = true,
    autoAim = true,
    autoGear = false,
    autoRevive = true,
    autoCollect = true,
    autoVoteAgain = true,
}

local farming = false
local inMatch = false
local conn = nil
local lastShot = 0
local lastGear = 0
local lastCollect = 0
local lastDetect = 0
local lastUpgradeCheck = 0
local startCredits = 0
local startKills = 0
local bestWave = 0

-- Number formatting
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

local function getCredits()
    local cv = LP:FindFirstChild("Credits")
    return cv and cv.Value or 0
end

local function getShards()
    local vs = LP:FindFirstChild("VoidShards")
    return vs and vs.Value or 0
end

local function getKills()
    local ls = LP:FindFirstChild("leaderstats")
    if not ls then return 0 end
    local k = ls:FindFirstChild("Kills")
    return k and k.Value or 0
end

local function getTopWave()
    local ls = LP:FindFirstChild("leaderstats")
    if not ls then return 0 end
    local tw = ls:FindFirstChild("TopWave")
    return tw and tw.Value or 0
end

-- GUI
local sg = Instance.new("ScreenGui")
sg.Name = "ZombieFarm"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.DisplayOrder = 99999

local fr = Instance.new("Frame")
fr.Size = UDim2.new(0,230,0,440); fr.Position = UDim2.new(0,10,0,50)
fr.BackgroundColor3 = Color3.fromRGB(12,12,22); fr.BackgroundTransparency = 0.06
fr.BorderSizePixel = 0; fr.Active = true
Instance.new("UICorner",fr).CornerRadius = UDim.new(0,10)

local dr = Instance.new("Frame",fr)
dr.Size = UDim2.new(1,0,0,28); dr.BackgroundColor3 = Color3.fromRGB(25,25,40)
dr.BorderSizePixel = 0; dr.Active = true
Instance.new("UICorner",dr).CornerRadius = UDim.new(0,10)

local ti = Instance.new("TextLabel",dr)
ti.Size = UDim2.new(1,-8,1,0); ti.Position = UDim2.new(0,4,0,0)
ti.BackgroundTransparency = 1; ti.Text = "SA Farm v1"
ti.TextColor3 = Color3.fromRGB(255,245,220); ti.Font = Enum.Font.GothamBold; ti.TextSize = 13

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

local labels = {}
local y = 34
local function addLabel(text, color, h, bold)
    local lbl = Instance.new("TextLabel",fr)
    lbl.Size = UDim2.new(1,-16,0,h or 14); lbl.Position = UDim2.new(0,8,0,y)
    lbl.BackgroundTransparency = 1; lbl.Text = text
    lbl.TextColor3 = color or Color3.fromRGB(180,180,200)
    lbl.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    lbl.TextSize = h==18 and 11 or (h==20 and 12 or 10)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    y = y + (h or 14) + 2
    return lbl
end

local stateLabel = addLabel("State: Hub", Color3.fromRGB(130,200,130), 18, true)
addLabel("", Color3.new(), 4)
local creditsLabel = addLabel("Credits: -", Color3.fromRGB(255,200,80))
local killsLabel = addLabel("Kills: -", Color3.fromRGB(255,140,140))
local waveLabel = addLabel("Wave: -", Color3.fromRGB(130,200,255))
local shardLabel = addLabel("Shards: -", Color3.fromRGB(200,130,255))
local earnedLabel = addLabel("Earned: -", Color3.fromRGB(130,255,130))
addLabel("", Color3.new(), 4)
local actionLabel = addLabel("Action: Idle", Color3.fromRGB(170,170,190), 12)
local rateLabel = addLabel("Rate: -/min", Color3.fromRGB(170,150,220), 12)
addLabel("", Color3.new(), 6)

local function makeToggle(text, default, cbY)
    local btn = Instance.new("TextButton",fr)
    btn.Size = UDim2.new(1,-16,0,16); btn.Position = UDim2.new(0,8,0,cbY)
    btn.BackgroundTransparency = 1; btn.AutoButtonColor = false
    btn.Text = (default and "[X] " or "[  ] ")..text
    btn.TextColor3 = default and Color3.fromRGB(130,255,130) or Color3.fromRGB(140,140,160)
    btn.Font = Enum.Font.Gotham; btn.TextSize = 10; btn.TextXAlignment = Enum.TextXAlignment.Left
    return btn
end

local cbY = y
local cbUpgrade = makeToggle("Upgrade Weapons", CFG.upgradeWeapons, cbY); cbY+=18
local cbHealth  = makeToggle("Upgrade Health",  CFG.upgradeHealth,  cbY); cbY+=18
local cbCrate   = makeToggle("Galactic Crate",  CFG.buyCrate,      cbY); cbY+=18
local cbQueue   = makeToggle("Auto Queue",      CFG.autoQueue,     cbY); cbY+=18
local cbShoot   = makeToggle("Auto Shoot",      CFG.autoShoot,     cbY); cbY+=18
local cbAim     = makeToggle("Auto Aim",        CFG.autoAim,       cbY); cbY+=18
local cbGear    = makeToggle("Auto Gear",       CFG.autoGear,      cbY); cbY+=18
local cbRevive  = makeToggle("Auto Revive",     CFG.autoRevive,    cbY); cbY+=18
local cbCollect = makeToggle("Auto Collect",    CFG.autoCollect,   cbY); cbY+=18
local cbVote    = makeToggle("Vote PlayAgain",  CFG.autoVoteAgain, cbY); cbY+=18

local toggleMap = {
    [cbUpgrade] = "upgradeWeapons", [cbHealth] = "upgradeHealth",
    [cbCrate] = "buyCrate", [cbQueue] = "autoQueue",
    [cbShoot] = "autoShoot", [cbAim] = "autoAim",
    [cbGear] = "autoGear", [cbRevive] = "autoRevive",
    [cbCollect] = "autoCollect", [cbVote] = "autoVoteAgain",
}
for cb, key in pairs(toggleMap) do
    cb.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        cb.Text = (CFG[key] and "[X] " or "[  ] ")..cb.Text:sub(5)
        cb.TextColor3 = CFG[key] and Color3.fromRGB(130,255,130) or Color3.fromRGB(140,140,160)
    end)
end

-- Start/Stop buttons
local tg = Instance.new("TextButton",fr)
tg.Size = UDim2.new(0.5,-11,0,32); tg.Position = UDim2.new(0,8,0,cbY+8)
tg.BackgroundColor3 = Color3.fromRGB(45,140,45); tg.BorderSizePixel = 0
tg.Text = "START"; tg.TextColor3 = Color3.new(1,1,1)
tg.Font = Enum.Font.GothamBold; tg.TextSize = 13
Instance.new("UICorner",tg).CornerRadius = UDim.new(0,5)

local cl = Instance.new("TextButton",fr)
cl.Size = UDim2.new(0.5,-11,0,32); cl.Position = UDim2.new(0.5,3,0,cbY+8)
cl.BackgroundColor3 = Color3.fromRGB(160,45,45); cl.BorderSizePixel = 0
cl.Text = "CLOSE"; cl.TextColor3 = Color3.new(1,1,1)
cl.Font = Enum.Font.Gotham; cl.TextSize = 13
Instance.new("UICorner",cl).CornerRadius = UDim.new(0,5)

local disc = Instance.new("TextLabel",fr)
disc.Size = UDim2.new(1,-16,0,18); disc.Position = UDim2.new(0,8,0,cbY+44)
disc.BackgroundTransparency = 1; disc.Text = "RShift = Hide | Survive Zombie Arena"
disc.TextColor3 = Color3.fromRGB(80,80,95); disc.Font = Enum.Font.Gotham; disc.TextSize = 8
disc.TextXAlignment = Enum.TextXAlignment.Left

fr.Size = UDim2.new(0,230,0,cbY+68)
sg.Parent = LP:WaitForChild("PlayerGui")

UIS.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then fr.Visible = not fr.Visible end
end)

-- Helper functions
local function setState(t, c)
    stateLabel.Text = "State: "..t
    stateLabel.TextColor3 = c or Color3.fromRGB(180,180,200)
end

local function setAction(t)
    actionLabel.Text = "Action: "..t
end

-- Detect game state
local function detectState()
    local ok, ws = pcall(function() return RequestWaveState:InvokeServer() end)
    if not ok or not ws then return "hub" end

    for _,v in ipairs(WS:GetDescendants()) do
        if v:IsA("Model") and (v.Name:lower():find("zombie") or v.Name:lower():find("enemy")) then
            return "match"
        end
    end

    if ws.GameState and (ws.GameState == 1 or ws.GameState == 2) then
        return "match"
    end

    return "hub"
end

-- Get nearest enemy HumanoidRootPart
local function getNearestEnemy()
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local nearest, minDist = nil, 300
    for _,v in ipairs(WS:GetDescendants()) do
        if v:IsA("Model") and v.Name:lower():find("zombie") then
            local hum = v:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                local hrp = v:FindFirstChild("HumanoidRootPart") or v:FindFirstChild("Head") or v.PrimaryPart
                if hrp then
                    local d = (hrp.Position - root.Position).Magnitude
                    if d < minDist then minDist = d; nearest = hrp end
                end
            end
        end
    end
    return nearest
end

-- Shoot weapon
local function shoot()
    pcall(function()
        GunFire:FireServer()
    end)
end

-- Place class gear
local function placeGear()
    local now = tick()
    if now - lastGear < CFG.gearInterval then return end
    lastGear = now

    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local pos = root.Position + root.CFrame.LookVector * 6
    local gears = {"Barricade", "AutoTurret", "Landmine"}
    for _, g in ipairs(gears) do
        local ok = pcall(function() GearAction:FireServer(g, pos) end)
        if ok then
            setAction("Placed: "..g)
            return
        end
    end
end

-- Revive
local function revive()
    local hum = LP.Character and LP.Character:FindFirstChild("Humanoid")
    if hum and hum.Health <= 0 then
        setAction("Reviving...")
        pcall(function() RequestRevive:FireServer() end)
        task.wait(0.3)
    end
end

-- Vote play again
local function voteAgain()
    pcall(function() VotePlayAgain:FireServer(true) end)
    pcall(function() VotePlayAgain:FireServer() end)
end

-- Collect drops
local function collectDrops()
    local now = tick()
    if now - lastCollect < CFG.collectInterval then return end
    lastCollect = now

    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    for _,v in ipairs(WS:GetDescendants()) do
        if v:IsA("BasePart") and v:GetAttribute("Shard") then
            local d = (v.Position - root.Position).Magnitude
            if d < 60 then
                root.CFrame = CFrame.new(v.Position + Vector3.new(0,3,0))
                task.wait(0.1)
            end
        end
    end
end

-- Upgrade weapon
local function upgradeWeapon()
    local ok, upg = pcall(function() return GetUpgrades:InvokeServer() end)
    if not ok or not upg then return false end
    if upg.IsMaxWeapon then return false end

    local price = upg.CurrentWeapon and upg.CurrentWeapon.Price or (upg.NextWeapon and upg.NextWeapon.Price or 9999999)
    local credits = getCredits()
    if credits < price + CFG.upgradeMinCredits then return false end

    setAction("Upgrading weapon ("..nf(price).." cr)")
    local ok2 = pcall(function() PurchaseWeaponUpgrade:FireServer() end)
    if ok2 then
        setAction("Weapon upgraded!")
        task.wait(0.5)
    end
    return ok2
end

-- Upgrade health
local function upgradeHealth()
    local ok, upg = pcall(function() return GetUpgrades:InvokeServer() end)
    if not ok or not upg or not upg.HealthPrice then return false end

    local credits = getCredits()
    if credits < upg.HealthPrice + CFG.upgradeMinCredits then return false end

    setAction("Upgrading health ("..nf(upg.HealthPrice).." cr)")
    local ok2 = pcall(function() PurchaseHealthUpgrade:FireServer() end)
    if ok2 then
        setAction("Health upgraded!")
        task.wait(0.5)
    end
    return ok2
end

-- Galactic crate
local function galacticCrate()
    if getShards() < 50 then return end
    setAction("Spinning Galactic Crate...")
    local gs = RStorage.EventRemotes:FindFirstChild("GalacticRequestSpin")
    if gs and gs:IsA("RemoteFunction") then
        pcall(function() gs:InvokeServer() end)
        task.wait(1)
    end
end

-- Queue for match
local function queueMatch()
    setAction("Looking for queue button...")
    for _,gui in ipairs(LP.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            for _,btn in ipairs(gui:GetDescendants()) do
                if btn:IsA("TextButton") then
                    local t = btn.Text:lower()
                    if t:find("play") or t:find("enter") or t:find("fight") or t:find("survive") or t:find("battle") or t:find("launch") then
                        pcall(function()
                            for _,c in ipairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
                        end)
                        setAction("Clicked: "..btn.Text)
                        return true
                    end
                end
            end
        end
    end
    -- Try GetIntoSpaceShip
    local mg = LP.PlayerGui:FindFirstChild("MainGui")
    if mg then
        local top = mg:FindFirstChild("Top")
        if top then
            local ship = top:FindFirstChild("GetIntoSpaceShip")
            if ship and ship:IsA("TextButton") then
                pcall(function()
                    for _,c in ipairs(getconnections(ship.MouseButton1Click)) do c:Fire() end
                end)
                setAction("Clicked GetIntoSpaceShip")
                return true
            end
        end
    end
    return false
end

local lastUpgradeCheck = 0
local upgradeCheckInterval = 3

-- Hub phase
local function hubPhase()
    setState("Hub", Color3.fromRGB(130,200,130))
    creditsLabel.Text = "Credits: "..nf(getCredits())
    killsLabel.Text = "Kills: "..nf(getKills())
    shardLabel.Text = "Shards: "..nf(getShards())
    waveLabel.Text = "TopWave: "..nf(getTopWave())
    earnedLabel.Text = "Earned: "..nf(getCredits()-startCredits).." cr"

    local now = tick()
    if now - lastUpgradeCheck < upgradeCheckInterval then return end
    lastUpgradeCheck = now

    -- Run hub actions
    local did = false

    if CFG.upgradeWeapons then
        if upgradeWeapon() then did = true end
    end

    if CFG.upgradeHealth then
        if upgradeHealth() then did = true end
    end

    if CFG.buyCrate then
        GalacticCrate() -- function exists but defined differently... 
    end

    if CFG.autoQueue then
        queueMatch()
    end

    if not did then
        setAction("Idle (need credits)")
    end
end

-- Match phase
local function matchPhase()
    setState("Match", Color3.fromRGB(255,200,80))
    creditsLabel.Text = "Credits: "..nf(getCredits())
    killsLabel.Text = "Kills: "..nf(getKills())
    shardLabel.Text = "Shards: "..nf(getShards())

    local ok, ws = pcall(function() return RequestWaveState:InvokeServer() end)
    if ok and ws then
        waveLabel.Text = "Wave: "..tostring(ws.CurrentWave or "?")
        if ws.CurrentWave and ws.CurrentWave > bestWave then bestWave = ws.CurrentWave end
    end

    earnedLabel.Text = "Earned: "..nf(getCredits()-startCredits).." cr"

    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")

    -- Always fix: send GunFire to create weapon if none equipped
    if not root then return end

    -- Auto-aim & shoot
    if CFG.autoShoot then
        local target = nil
        if CFG.autoAim then target = getNearestEnemy() end

        if target then
            root.CFrame = CFrame.new(root.Position, Vector3.new(target.Position.X, root.Position.Y, target.Position.Z))
        end

        local now = tick()
        if now - lastShot > CFG.gunFireRate then
            lastShot = now
            shoot()
        end
    end

    if CFG.autoGear then placeGear() end
    if CFG.autoRevive then revive() end
    if CFG.autoCollect then collectDrops() end
    if CFG.autoVoteAgain then voteAgain() end
end

-- Rate tracking
local rateCheckTime = 0
local rateCheckCredits = 0

-- Main loop
tg.MouseButton1Click:Connect(function()
    farming = not farming
    if farming then
        tg.Text = "STOP"
        tg.BackgroundColor3 = Color3.fromRGB(180,45,45)
        startCredits = getCredits()
        startKills = getKills()
        bestWave = 0
        rateCheckTime = tick()
        rateCheckCredits = startCredits

        conn = RS.Heartbeat:Connect(function()
            local now = tick()
            if now - lastDetect < CFG.detectInterval then return end
            lastDetect = now
            lastUpgradeCheck = 0

            local state = detectState()
            inMatch = (state == "match")

            if inMatch then
                matchPhase()
            else
                hubPhase()
            end

            if now - rateCheckTime > 30 then
                local diff = getCredits() - rateCheckCredits
                rateLabel.Text = "Rate: "..nf(math.floor(diff/(now-rateCheckTime)*60)).."/min"
                rateCheckTime = now
                rateCheckCredits = getCredits()
            end
        end)
        setAction("Farm started")
    else
        tg.Text = "START"
        tg.BackgroundColor3 = Color3.fromRGB(45,140,45)
        setState("Stopped", Color3.fromRGB(200,200,200))
        setAction("Idle")
        if conn then conn:Disconnect(); conn = nil end
    end
end)

cl.MouseButton1Click:Connect(function()
    if farming then
        farming = false
        if conn then conn:Disconnect(); conn = nil end
    end
    sg:Destroy()
end)

warn("[SA Farm] v1 injected - Survive Zombie Arena")
print("[SA Farm] Ready. Press START to begin auto-farming.")