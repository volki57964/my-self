--[[
    Mommy | +1 Speed Keyboard Escape (WORLD 2)
    Self-contained Instance-based UI (no Drawing API, no external deps).
    Tailored to this game's remotes & config (studied via Cobalt MCP).

    Usage:
      loadstring(...)()  or  paste into your executor
      RightShift   = toggle GUI visibility
      RightControl = full destroy (also getgenv().DestroyMommy())
]]

-- [State / Config] --------------------------------------------------------------------------------------------------------------------------------------------------
local Mommy = {
    Farm = {
        AutoTreadmill = false,
        TreadmillName = "Treadmill",
        AutoStep = false,
        StepRadius = 200,
        AutoRebirth = false,
        AutoGift = false,
        AutoSpecial = false,
    },
    Player = {
        WalkSpeedEnabled = false,
        WalkSpeed = 100,
        JumpPowerEnabled = false,
        JumpPower = 100,
        InfiniteJump = false,
        Noclip = false,
        Bhop = false,
        AntiAFK = false,
    },
    Teleport = {
        Return = false,
        ReturnDelay = 0.2,
    },
    Bypass = {
        BlockPunish = false,
        SuppressAFK = false,
        ClampSpeed = true,
    },
    Visuals = {
        FOV = { Enable = false, Amount = 90 },
        ESP = {
            Players = false,
            Treadmills = false,
            Winblocks = false,
            Checkpoints = false,
            ShowNames = true,
            ShowDistance = true,
            MaxDist = 1500,
        },
        World = {
            IndoorAmbience = false,
            IndoorColor = Color3.fromRGB(124, 97, 196),
            OutdoorAmbience = false,
            OutdoorColor = Color3.fromRGB(124, 97, 196),
            Fog = false,
            FogColor = Color3.fromRGB(124, 97, 196),
            Saturation = false,
            SatAmount = 0,
        },
    },
}

-- [Variables] -------------------------------------------------------------------------------------------------------------------------------------------------------
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser
pcall(function() VirtualUser = game:GetService("VirtualUser") end)

local Clock = os.clock()
local Connections = {}
local ActiveThreads = {}
local ESPObjects = {}
local Highlights = {}
local MommyAlive = true

-- Safe global access (works whether or not getgenv/_G exist in the executor)
local function setGlobal(key, value)
    if getgenv then pcall(function() getgenv()[key] = value end) end
    if _G then pcall(function() _G[key] = value end) end
end
local function getGlobal(key)
    if getgenv then
        local ok, v = pcall(function() return getgenv()[key] end)
        if ok and v ~= nil then return v end
    end
    if _G then
        local ok, v = pcall(function() return _G[key] end)
        if ok and v ~= nil then return v end
    end
    return nil
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClientState
pcall(function() ClientState = require(ReplicatedStorage:WaitForChild("ClientState")) end)
local GameConfig
pcall(function() GameConfig = require(ReplicatedStorage:WaitForChild("Config")) end)

-- Safely fetch a remote by name
local function Remote(name)
    local r = Remotes:FindFirstChild(name)
    return r
end
local function fireRemote(name, ...)
    local r = Remote(name)
    if r and r:IsA("RemoteEvent") then pcall(function(...) r:FireServer(...) end, ...) end
end
local function invokeRemote(name, ...)
    local r = Remote(name)
    if r and r:IsA("RemoteFunction") then
        local args = {...}
        local ok, res = pcall(function() return r:InvokeServer(unpack(args)) end)
        return ok, res
    end
    return false
end

-- leaderstats helpers (server-authoritative)
local function statValue(name)
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if not ls then return nil end
    local v = ls:FindFirstChild(name)
    return v and v.Value or nil
end

-- [Dynamic game data] -----------------------------------------------------------------------------------------------------------------------------------------------
local function getPartFrom(child)
    if not child then return nil end
    if child:IsA("BasePart") then return child end
    return child:FindFirstChildWhichIsA("BasePart") or child:FindFirstChild("HumanoidRootPart")
end

local function collectTreadmills()
    local t = {}
    local folder = Workspace:FindFirstChild("Treadmill")
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            local p = getPartFrom(m)
            if p then table.insert(t, { name = m.Name, part = p }) end
        end
    end
    return t
end

local function collectCheckpoints()
    local t = {}
    local folder = Workspace:FindFirstChild("Checkpoints")
    if folder then
        local spawns = folder:FindFirstChild("Spawns") or folder
        for i, c in ipairs(spawns:GetChildren()) do
            local p = getPartFrom(c)
            if p then table.insert(t, { name = tostring(i) .. ". " .. c.Name, part = p }) end
        end
    end
    return t
end

local function collectWinblocks()
    local t = {}
    local folder = Workspace:FindFirstChild("Winblocks")
    if folder then
        for _, c in ipairs(folder:GetChildren()) do
            local p = getPartFrom(c)
            if p then table.insert(t, { name = c.Name, part = p }) end
        end
    end
    return t
end

local function getPortalPart()
    local portal = Workspace:FindFirstChild("Portal")
    if portal then return getPartFrom(portal) or getPartFrom(portal:GetChildren()[1]) end
    return nil
end

local Treadmills = collectTreadmills()
local Checkpoints = collectCheckpoints()
local Winblocks = collectWinblocks()

local TreadmillNames = {}
for _, t in ipairs(Treadmills) do table.insert(TreadmillNames, t.name) end
local CheckpointNames = {}
for _, c in ipairs(Checkpoints) do table.insert(CheckpointNames, c.name) end
local WinblockNames = {}
for _, w in ipairs(Winblocks) do table.insert(WinblockNames, w.name) end

-- Number formatter (mirrors the game's suffix table)
local Suffixes = {
    { 1e63, "Vg" }, { 1e60, "Nd" }, { 1e57, "Od" }, { 1e54, "Spd" }, { 1e51, "Sxd" },
    { 1e48, "Qid" }, { 1e45, "Qad" }, { 1e42, "Td" }, { 1e39, "Dd" }, { 1e36, "Ud" },
    { 1e33, "Dc" }, { 1e30, "No" }, { 1e27, "Oc" }, { 1e24, "Sp" }, { 1e21, "Sx" },
    { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" },
}
local function fmtNum(n)
    n = tonumber(n) or 0
    if n < 1000 then return tostring(math.floor(n)) end
    for _, s in ipairs(Suffixes) do
        if s[1] <= n then
            return string.format("%.2f", n / s[1]):gsub("%.?0+$", "") .. s[2]
        end
    end
    return tostring(n)
end

-- [Theme] ----------------------------------------------------------------------------------------------------------------------------------------------------------
local Theme = {
    Background = Color3.fromRGB(20, 20, 28),
    TabBar = Color3.fromRGB(28, 28, 38),
    TabActive = Color3.fromRGB(124, 97, 196),
    TabInactive = Color3.fromRGB(45, 45, 58),
    Section = Color3.fromRGB(32, 32, 44),
    Text = Color3.fromRGB(235, 235, 245),
    TextDim = Color3.fromRGB(150, 150, 165),
    Accent = Color3.fromRGB(124, 97, 196),
    AccentDim = Color3.fromRGB(80, 60, 140),
    ToggleOff = Color3.fromRGB(50, 50, 65),
    ToggleOn = Color3.fromRGB(124, 97, 196),
    Slider = Color3.fromRGB(50, 50, 65),
    Button = Color3.fromRGB(45, 45, 58),
    ButtonHover = Color3.fromRGB(60, 60, 78),
    Stroke = Color3.fromRGB(50, 50, 65),
    Success = Color3.fromRGB(80, 200, 120),
    Font = Enum.Font.Gotham,
    FontBold = Enum.Font.GothamBold,
}

-- [UI Library - Instance based] ------------------------------------------------------------------------------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MommyUI_" .. tostring(math.random(100000, 999999))
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999999
local function ParentGui(gui)
    -- Priority: CoreGui (visible) -> PlayerGui (fallback). Avoid gethui() which
    -- returns a hidden container on some executors and makes the GUI invisible.
    local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not ok then
        pcall(function() gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end)
    end
end
ParentGui(ScreenGui)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 560, 0, 400)
MainFrame.Position = UDim2.new(0.5, -280, 0.5, -200)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local Stroke = Instance.new("UIStroke", MainFrame)
Stroke.Color = Theme.Stroke
Stroke.Thickness = 1
Stroke.Transparency = 0.3

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Theme.TabBar
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 8)

local TitleFrame = Instance.new("Frame")
TitleFrame.Size = UDim2.new(1, 0, 0, 18)
TitleFrame.Position = UDim2.new(0, 0, 1, -18)
TitleFrame.BackgroundColor3 = Theme.TabBar
TitleFrame.BorderSizePixel = 0
TitleFrame.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -40, 1, 0)
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Mommy | +1 Speed Keyboard Escape"
TitleLabel.TextColor3 = Theme.Text
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Font = Theme.FontBold
TitleLabel.TextSize = 14
TitleLabel.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
CloseBtn.Text = "X"
CloseBtn.Font = Theme.FontBold
CloseBtn.TextSize = 13
CloseBtn.TextColor3 = Theme.Text
CloseBtn.Parent = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(0, 130, 1, -42)
TabBar.Position = UDim2.new(0, 0, 0, 40)
TabBar.BackgroundColor3 = Theme.TabBar
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame

local TabList = Instance.new("UIListLayout", TabBar)
TabList.Padding = UDim.new(0, 2)
TabList.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabList.SortOrder = Enum.SortOrder.LayoutOrder

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -140, 1, -42)
ContentArea.Position = UDim2.new(0, 134, 0, 40)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

local Tabs = {}
local function AddTab(name)
    local tabBtn = Instance.new("TextButton")
    tabBtn.Size = UDim2.new(1, -8, 0, 30)
    tabBtn.BackgroundColor3 = Theme.TabInactive
    tabBtn.Text = name
    tabBtn.Font = Theme.Font
    tabBtn.TextSize = 12
    tabBtn.TextColor3 = Theme.TextDim
    tabBtn.Parent = TabBar
    Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 5)

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Theme.Accent
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = ContentArea

    local pageList = Instance.new("UIListLayout", page)
    pageList.Padding = UDim.new(0, 6)
    pageList.SortOrder = Enum.SortOrder.LayoutOrder

    local tab = { Page = page, Button = tabBtn }
    table.insert(Tabs, tab)

    tabBtn.MouseButton1Click:Connect(function()
        for _, t in ipairs(Tabs) do
            t.Page.Visible = false
            t.Button.BackgroundColor3 = Theme.TabInactive
            t.Button.TextColor3 = Theme.TextDim
        end
        page.Visible = true
        tabBtn.BackgroundColor3 = Theme.TabActive
        tabBtn.TextColor3 = Theme.Text
    end)

    return tab
end

local function AddSection(parent, title)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -8, 0, 0)
    holder.BackgroundColor3 = Theme.Section
    holder.BorderSizePixel = 0
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.Parent = parent.Page or parent
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 6)

    local stroke = Instance.new("UIStroke", holder)
    stroke.Color = Theme.Stroke
    stroke.Thickness = 1
    stroke.Transparency = 0.5

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 0, 24)
    lbl.Position = UDim2.new(0, 8, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Text = title
    lbl.TextColor3 = Theme.Accent
    lbl.Font = Theme.FontBold
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = holder

    local list = Instance.new("UIListLayout", holder)
    list.Padding = UDim.new(0, 4)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local pad = Instance.new("UIPadding", holder)
    pad.PaddingTop = UDim.new(0, 28)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.PaddingLeft = UDim.new(0, 6)
    pad.PaddingRight = UDim.new(0, 6)

    return { Holder = holder }
end

local function AddToggle(parent, text, default, callback)
    local state = default or false
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 28)
    row.BackgroundColor3 = Theme.Button
    row.Text = ""
    row.Parent = parent.Holder
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 36, 0, 16)
    knob.Position = UDim2.new(1, -44, 0.5, -8)
    knob.BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff
    knob.Parent = row
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 12, 0, 12)
    dot.Position = state and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    dot.BackgroundColor3 = Theme.Text
    dot.Parent = knob
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -50, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Theme.Text
    label.Font = Theme.Font
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local updating = false
    row.MouseButton1Click:Connect(function()
        state = not state
        knob.BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff
        TweenService:Create(dot, TweenInfo.new(0.15), {
            Position = state and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
        }):Play()
        if callback then callback(state) end
    end)

    return {
        Get = function() return state end,
        Set = function(v)
            if v == state then return end
            state = v
            updating = true
            knob.BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff
            TweenService:Create(dot, TweenInfo.new(0.15), {
                Position = state and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
            }):Play()
            updating = false
            if callback then callback(state) end
        end,
    }
end

local function AddSlider(parent, text, min, max, default, increment, callback)
    local val = default or min
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 40)
    row.BackgroundColor3 = Theme.Button
    row.Parent = parent.Holder
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 0, 18)
    lbl.Position = UDim2.new(0, 8, 0, 3)
    lbl.BackgroundTransparency = 1
    lbl.Text = text .. ": " .. tostring(val)
    lbl.TextColor3 = Theme.Text
    lbl.Font = Theme.Font
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -16, 0, 6)
    track.Position = UDim2.new(0, 8, 0, 26)
    track.BackgroundColor3 = Theme.Slider
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local function update(inputX)
        local rel = math.clamp((inputX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local stepped = math.floor((min + rel * (max - min)) / increment + 0.5) * increment
        stepped = math.clamp(stepped, min, max)
        if stepped ~= val then
            val = stepped
            fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
            lbl.Text = text .. ": " .. tostring(val)
            if callback then callback(val) end
        end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            update(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            update(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)

    return { Get = function() return val end }
end

local function AddButton(parent, text, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 28)
    btn.BackgroundColor3 = Theme.Button
    btn.Text = text
    btn.Font = Theme.Font
    btn.TextSize = 12
    btn.TextColor3 = Theme.Text
    btn.Parent = parent.Holder
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Theme.ButtonHover end)
    btn.MouseLeave:Connect(function() btn.BackgroundColor3 = Theme.Button end)
    btn.MouseButton1Click:Connect(function() if callback then callback() end end)
    return btn
end

local function AddDropdown(parent, text, values, default, callback)
    local selected = default or (values[1] or "")
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 28)
    row.BackgroundColor3 = Theme.Button
    row.Text = ""
    row.Parent = parent.Holder
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -24, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text .. ": " .. selected
    lbl.TextColor3 = Theme.Text
    lbl.Font = Theme.Font
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 16, 1, 0)
    arrow.Position = UDim2.new(1, -20, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "v"
    arrow.TextColor3 = Theme.TextDim
    arrow.Font = Theme.FontBold
    arrow.TextSize = 11
    arrow.Parent = row

    local list = Instance.new("Frame")
    list.Size = UDim2.new(1, 0, 0, 0)
    list.Position = UDim2.new(0, 0, 1, 2)
    list.BackgroundColor3 = Theme.Section
    list.Visible = false
    list.ZIndex = 10
    list.Parent = row
    Instance.new("UICorner", list).CornerRadius = UDim.new(0, 4)
    local listLayout = Instance.new("UIListLayout", list)
    listLayout.Padding = UDim.new(0, 1)

    local expanded = false
    local currentValues = values
    local function refresh()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for _, v in ipairs(currentValues) do
            local item = Instance.new("TextButton")
            item.Size = UDim2.new(1, 0, 0, 22)
            item.BackgroundColor3 = v == selected and Theme.AccentDim or Theme.Button
            item.Text = v
            item.Font = Theme.Font
            item.TextSize = 11
            item.TextColor3 = Theme.Text
            item.ZIndex = 11
            item.Parent = list
            item.MouseButton1Click:Connect(function()
                selected = v
                lbl.Text = text .. ": " .. selected
                list.Visible = false
                expanded = false
                arrow.Text = "v"
                if callback then callback(selected) end
            end)
        end
        list.Size = UDim2.new(1, 0, 0, #currentValues * 23)
    end

    row.MouseButton1Click:Connect(function()
        expanded = not expanded
        list.Visible = expanded
        arrow.Text = expanded and "^" or "v"
        if expanded then refresh() end
    end)

    return {
        Get = function() return selected end,
        SetValues = function(newVals) currentValues = newVals end,
    }
end

local function AddLabel(parent, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Theme.TextDim
    lbl.Font = Theme.FontBold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent.Holder
    return lbl
end

-- [Drag] ----------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local dragging, dragStart, startPos
    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

-- [Notifications] -------------------------------------------------------------------------------------------------------------------------------------------------
local function Notify(text, duration)
    duration = duration or 3
    local notif = Instance.new("TextLabel")
    notif.Size = UDim2.new(0, 280, 0, 30)
    notif.Position = UDim2.new(0.5, -140, 0, 10)
    notif.BackgroundColor3 = Theme.Section
    notif.Text = text
    notif.Font = Theme.Font
    notif.TextSize = 12
    notif.TextColor3 = Theme.Text
    notif.Parent = ScreenGui
    Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 6)
    local s = Instance.new("UIStroke", notif)
    s.Color = Theme.Accent
    s.Thickness = 1
    task.delay(duration, function()
        if notif then notif:Destroy() end
    end)
end

-- [Helpers] --------------------------------------------------------------------------------------------------------------------------------------------------------
-- Anti-cheat limits (from Config.SECURITY, WORLD 2)
local MAX_SPEED_ALLOWED = 295        -- server kicks if WalkSpeed > 300; keep a safety margin
local DISTANCE_MARGIN = 1.8         -- server flags teleport if moved > 2 studs between checks
local TELEPORT_COOLDOWN = 0.55      -- server flags teleports faster than 0.5s apart

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- Safe teleport: move in small steps (<= DISTANCE_MARGIN) to avoid anti-cheat distance check.
-- `instant` bypasses stepping (use only for short hops where the game already tolerates it).
local function safeTP(cframe, instant)
    local root = getRoot()
    if not root then return end
    local startPos = root.CFrame
    local distance = (startPos.Position - cframe.Position).Magnitude
    if instant or distance < DISTANCE_MARGIN then
        root.CFrame = cframe
        return
    end
    -- step towards target in <= DISTANCE_MARGIN increments
    local steps = math.ceil(distance / DISTANCE_MARGIN)
    for i = 1, steps do
        local alpha = i / steps
        if not getRoot() then return end
        root.CFrame = startPos:Lerp(cframe, alpha)
        RunService.RenderStepped:Wait()
    end
end

-- Track last teleport time to respect TELEPORT_COOLDOWN
local lastTeleport = 0
local function tpWithCooldown(cframe)
    local now = os.clock()
    if now - lastTeleport < TELEPORT_COOLDOWN then
        task.wait(TELEPORT_COOLDOWN - (now - lastTeleport))
    end
    lastTeleport = os.clock()
    safeTP(cframe)
end

-- [Anti-Cheat Bypass] ----------------------------------------------------------------------------------------------------------------------------------------------
-- The server uses CheatWarningEvent / ToggleCheatAlert / SlapEvent to punish the
-- client (kick UI, slap physics). We neutralise their OnClientEvent so the client
-- never reacts to them. PlayerAfkStatus is an outgoing "I'm AFK" signal that the
-- server uses to stop granting treadmill speed; we block it during AFK-farm.
-- Executor functions may live in getgenv() rather than the global scope, so probe both.
local function execFn(name)
    local v = _G and _G[name]
    if type(v) == "function" then return v end
    if getgenv then
        local ok, gv = pcall(function() return getgenv()[name] end)
        if ok and type(gv) == "function" then return gv end
    end
    return nil
end
local hookfunction = execFn("hookfunction")
local setreadonly = execFn("setreadonly")
local getconnectionsFn = getconnections or execFn("getconnections")

local BlockedRemotes = {}
local function disableAllConns(signal)
    if not getconnectionsFn then return end
    pcall(function()
        for _, c in ipairs(getconnectionsFn(signal)) do
            pcall(function() c:Disable() end)
        end
    end)
end

local bypassInitialized = false
local function initBypass()
    if bypassInitialized then return end
    bypassInitialized = true
    -- incoming punishment remotes (server -> client): disable every OnClientEvent handler
    disableAllConns(ReplicatedStorage.CheatWarningEvent.OnClientEvent)
    disableAllConns(ReplicatedStorage.ToggleCheatAlert.OnClientEvent)
    disableAllConns(ReplicatedStorage.SlapEvent.OnClientEvent)
    BlockedRemotes["CheatWarningEvent"] = true
    BlockedRemotes["ToggleCheatAlert"] = true
    BlockedRemotes["SlapEvent"] = true
end

-- PlayerAfkStatus: hook FireServer so we can swallow the "I'm AFK" report at will.
local afkRemote = ReplicatedStorage:FindFirstChild("PlayerAfkStatus")
local originalFireServer
if afkRemote then
    originalFireServer = afkRemote.FireServer
    if hookfunction then
        pcall(function()
            local old = afkRemote.FireServer
            hookfunction(afkRemote.FireServer, function(self, ...)
                if Mommy.Bypass.SuppressAFK then return end
                return old(self, ...)
            end)
        end)
    end
end
-- Fallback: also disable the game's Idled connections when SuppressAFK is on, so the
-- AfkDetector script (which fires PlayerAfkStatus) can't run.
local suppressAFKConns = {}
local function toggleSuppressAFK(on)
    if on then
        if getconnectionsFn then
            pcall(function()
                for _, c in ipairs(getconnectionsFn(LocalPlayer.Idled)) do
                    table.insert(suppressAFKConns, c)
                    pcall(function() c:Disable() end)
                end
            end)
        end
    else
        for _, c in ipairs(suppressAFKConns) do
            pcall(function() c:Enable() end)
        end
        suppressAFKConns = {}
    end
end

-- [Build UI - Farm] -------------------------------------------------------------------------------------------------------------------------------------------------
local farmTab = AddTab("Farm")
local farmSec = AddSection(farmTab, "Auto Farm Speed")
local tmDD = AddDropdown(farmSec, "Treadmill", TreadmillNames, TreadmillNames[1], function(v) Mommy.Farm.TreadmillName = v end)
AddToggle(farmSec, "Auto Treadmill (AFK speed)", false, function(v)
    Mommy.Farm.AutoTreadmill = v
    if not v then
        local root = getRoot()
        if root then root.Anchored = false end
    end
end)
AddToggle(farmSec, "Auto Step Keycaps (XP)", false, function(v) Mommy.Farm.AutoStep = v end)
AddSlider(farmSec, "Step Radius", 50, 1000, 200, 25, function(v) Mommy.Farm.StepRadius = v end)
AddLabel(farmSec, "Note: Treadmill & Step are mutually exclusive; pick one.")

local rbSec = AddSection(farmTab, "Rebirth & Rewards")
AddToggle(rbSec, "Auto Rebirth (when level met)", false, function(v) Mommy.Farm.AutoRebirth = v end)
AddToggle(rbSec, "Auto Claim Gift", false, function(v) Mommy.Farm.AutoGift = v end)
AddToggle(rbSec, "Auto Collect Special Keys", false, function(v) Mommy.Farm.AutoSpecial = v end)
AddButton(rbSec, "Rebirth Now", function()
    fireRemote("Rebirth")
    Notify("Rebirth requested", 2)
end)
AddButton(rbSec, "Claim Gift Now", function() fireRemote("ClaimGift") end)

-- [Build UI - Player] ----------------------------------------------------------------------------------------------------------------------------------------------
local playerTab = AddTab("Player")
local moveSec = AddSection(playerTab, "Movement")
AddToggle(moveSec, "WalkSpeed Override", false, function(v)
    Mommy.Player.WalkSpeedEnabled = v
    if not v then
        local hum = getHum()
        if hum then pcall(function() end) end
    end
end)
AddSlider(moveSec, "WalkSpeed (cap 295)", 16, 295, 100, 1, function(v) Mommy.Player.WalkSpeed = v end)
AddToggle(moveSec, "JumpPower Override", false, function(v)
    Mommy.Player.JumpPowerEnabled = v
    local hum = getHum()
    if hum and not v then pcall(function() hum.UseJumpPower = true; hum.JumpPower = 50 end) end
end)
AddSlider(moveSec, "JumpPower", 50, 350, 100, 1, function(v) Mommy.Player.JumpPower = v end)
AddToggle(moveSec, "Infinite Jump", false, function(v) Mommy.Player.InfiniteJump = v end)
AddToggle(moveSec, "Bhop (auto-jump)", false, function(v) Mommy.Player.Bhop = v end)
AddToggle(moveSec, "Noclip", false, function(v)
    Mommy.Player.Noclip = v
    if v then
        local c = RunService.Stepped:Connect(function()
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetChildren()) do
                    if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
                end
            end
        end)
        table.insert(Connections, c)
    end
end)
AddToggle(moveSec, "Anti AFK", false, function(v)
    Mommy.Player.AntiAFK = v
end)

local acSec = AddSection(playerTab, "Anti-Cheat Bypass")
AddToggle(acSec, "Block Punishments (slap/kick)", false, function(v) Mommy.Bypass.BlockPunish = v end)
AddToggle(acSec, "Suppress AFK Report", false, function(v)
    Mommy.Bypass.SuppressAFK = v
    toggleSuppressAFK(v)
end)
AddToggle(acSec, "God WalkSpeed (auto-clamp 295)", true, function(v) Mommy.Bypass.ClampSpeed = v end)
AddLabel(acSec, "Auto-clamp keeps WalkSpeed under the 300 server limit.")
AddLabel(acSec, "Teleports move in safe steps to dodge distance checks.")

-- [Build UI - Teleport] ---------------------------------------------------------------------------------------------------------------------------------------------
local tpTab = AddTab("Teleport")

local tpTmSec = AddSection(tpTab, "Treadmills")
local tpTmDD = AddDropdown(tpTmSec, "Treadmill", TreadmillNames, TreadmillNames[1], function(v) _G.Mommy_TmTarget = v end)
AddButton(tpTmSec, "Teleport to Treadmill", function()
    local t = Treadmills[table.find(TreadmillNames, _G.Mommy_TmTarget) or 1]
    if t and t.part then tpWithCooldown(t.part.CFrame + Vector3.new(0, 4, 0)) end
end)

local tpCpSec = AddSection(tpTab, "Checkpoints")
local tpCpDD = AddDropdown(tpCpSec, "Checkpoint", CheckpointNames, CheckpointNames[1], function(v) _G.Mommy_CpTarget = v end)
AddButton(tpCpSec, "Teleport to Checkpoint", function()
    local c = Checkpoints[table.find(CheckpointNames, _G.Mommy_CpTarget) or 1]
    if c and c.part then tpWithCooldown(c.part.CFrame + Vector3.new(0, 4, 0)) end
end)
AddButton(tpCpSec, "Request Server TP (if available)", function()
    local idx = table.find(CheckpointNames, _G.Mommy_CpTarget)
    fireRemote("RequestCheckpointTp", idx)
end)

local tpWbSec = AddSection(tpTab, "Winblocks")
local tpWbDD = AddDropdown(tpWbSec, "Winblock", WinblockNames, WinblockNames[1], function(v) _G.Mommy_WbTarget = v end)
AddButton(tpWbSec, "Teleport to Winblock", function()
    local w = Winblocks[table.find(WinblockNames, _G.Mommy_WbTarget) or 1]
    if w and w.part then tpWithCooldown(w.part.CFrame + Vector3.new(0, 4, 0)) end
end)

local tpQSec = AddSection(tpTab, "Quick & Players")
AddButton(tpQSec, "Teleport to Portal", function()
    local p = getPortalPart()
    if p then tpWithCooldown(p.CFrame + Vector3.new(0, 4, 0)) end
end)
AddButton(tpQSec, "Teleport to Nearest Keycap", function()
    local folder = Workspace:FindFirstChild("Keycaps")
    local root = getRoot()
    if not (folder and root) then return end
    local best, bestD = nil, math.huge
    for _, m in ipairs(folder:GetChildren()) do
        local part = getPartFrom(m)
        if part then
            local d = (part.Position - root.Position).Magnitude
            if d < bestD then bestD = d; best = part end
        end
    end
    if best then tpWithCooldown(best.CFrame + Vector3.new(0, 5, 0)) end
end)

local playerListValues = {}
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then table.insert(playerListValues, p.Name) end
end
local tpPlDD = AddDropdown(tpQSec, "Player", playerListValues, playerListValues[1] or "", function(v) _G.Mommy_PlTarget = v end)
AddButton(tpQSec, "Teleport to Player", function()
    local target = Players:FindFirstChild(_G.Mommy_PlTarget or "")
    if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
        tpWithCooldown(target.Character.HumanoidRootPart.CFrame + Vector3.new(0, 3, 0))
    end
end)
AddButton(tpQSec, "View Player", function()
    local target = Players:FindFirstChild(_G.Mommy_PlTarget or "")
    if target and target.Character and target.Character:FindFirstChild("Humanoid") then
        Workspace.Camera.CameraSubject = target.Character.Humanoid
    end
end)
AddButton(tpQSec, "Unview", function()
    local hum = getHum()
    if hum then Workspace.Camera.CameraSubject = hum end
end)

-- [Build UI - Visuals] ---------------------------------------------------------------------------------------------------------------------------------------------
local visTab = AddTab("Visuals")
local fovSec = AddSection(visTab, "FOV")
AddToggle(fovSec, "Enable FOV", false, function(v)
    Mommy.Visuals.FOV.Enable = v
    Workspace.Camera.FieldOfView = v and Mommy.Visuals.FOV.Amount or 70
end)
AddSlider(fovSec, "FOV Amount", 70, 120, 90, 1, function(v)
    Mommy.Visuals.FOV.Amount = v
    if Mommy.Visuals.FOV.Enable then Workspace.Camera.FieldOfView = v end
end)

local espSec = AddSection(visTab, "ESP")
AddToggle(espSec, "Player ESP", false, function(v) Mommy.Visuals.ESP.Players = v end)
AddToggle(espSec, "Treadmill ESP", false, function(v) Mommy.Visuals.ESP.Treadmills = v end)
AddToggle(espSec, "Winblock ESP", false, function(v) Mommy.Visuals.ESP.Winblocks = v end)
AddToggle(espSec, "Checkpoint ESP", false, function(v) Mommy.Visuals.ESP.Checkpoints = v end)
AddToggle(espSec, "Show Names", true, function(v) Mommy.Visuals.ESP.ShowNames = v end)
AddToggle(espSec, "Show Distance", true, function(v) Mommy.Visuals.ESP.ShowDistance = v end)
AddSlider(espSec, "Max Distance", 100, 5000, 1500, 50, function(v) Mommy.Visuals.ESP.MaxDist = v end)

local worldSec = AddSection(visTab, "World")
AddToggle(worldSec, "Indoor Ambience", false, function(v)
    Mommy.Visuals.World.IndoorAmbience = v
    Lighting.Ambient = v and Mommy.Visuals.World.IndoorColor or Color3.fromRGB(0, 0, 0)
end)
AddToggle(worldSec, "Outdoor Ambience", false, function(v)
    Mommy.Visuals.World.OutdoorAmbience = v
    Lighting.OutdoorAmbient = v and Mommy.Visuals.World.OutdoorColor or Color3.fromRGB(152, 152, 146)
end)
AddToggle(worldSec, "Fog Color", false, function(v)
    Mommy.Visuals.World.Fog = v
    Lighting.FogColor = v and Mommy.Visuals.World.FogColor or Color3.fromRGB(100, 87, 72)
end)
AddToggle(worldSec, "Saturation", false, function(v)
    Mommy.Visuals.World.Saturation = v
    local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if not cc then cc = Instance.new("ColorCorrectionEffect"); cc.Parent = Lighting end
    cc.Saturation = v and Mommy.Visuals.World.SatAmount or 0
end)
AddSlider(worldSec, "Saturation Amount", 0, 5, 0, 0.1, function(v)
    Mommy.Visuals.World.SatAmount = v
    if Mommy.Visuals.World.Saturation then
        local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
        if cc then cc.Saturation = v end
    end
end)

-- [Build UI - Stats] -----------------------------------------------------------------------------------------------------------------------------------------------
local statsTab = AddTab("Stats")
local statSec = AddSection(statsTab, "Live Stats")
local statLabels = {}
local function newStatLine(key, title)
    local lbl = AddLabel(statSec, title .. ": ...")
    statLabels[key] = lbl
end
newStatLine("speed", "Speed (currency)")
newStatLine("wins", "Wins")
newStatLine("rebirths", "Rebirths")
newStatLine("level", "Level")
newStatLine("xp", "XP")
newStatLine("mult", "Speed Multiplier")
newStatLine("walkspeed", "WalkSpeed")
newStatLine("rebirthprog", "Rebirth Progress")
AddLabel(statSec, "RightShift = toggle UI | RightControl = destroy")

-- Close button handler (hide)
CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui.Enabled = false
end)

-- [ESP helpers] ----------------------------------------------------------------------------------------------------------------------------------------------------
local function clearESP(key)
    if ESPObjects[key] then
        pcall(function() ESPObjects[key]:Destroy() end)
        ESPObjects[key] = nil
    end
    if Highlights[key] then
        pcall(function() Highlights[key]:Destroy() end)
        Highlights[key] = nil
    end
end

local function highlightObjects(key, parts, color)
    if not Mommy.Visuals.ESP[key] then clearESP(key) return end
    local hl = Highlights[key]
    if not hl then
        hl = Instance.new("Highlight")
        hl.FillTransparency = 0.7
        hl.OutlineColor = color or Theme.Accent
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ScreenGui
        Highlights[key] = hl
    end
    hl.FillColor = color or Theme.Accent
    -- attach by setting highlight on a model parent; use first part as adornee fallback via parent
    -- Highlight applies to a single instance subtree; we adornee each via individual highlights is heavy,
    -- so we keep one highlight adornee per refresh cycle on the folder/model.
    return hl
end

-- Simpler per-object ESP using BillboardGui for parts + Highlight for players
local function ensureHighlight(name, instance, color)
    local hl = Highlights[name .. "_" .. tostring(instance)]
    if not hl then
        hl = Instance.new("Highlight")
        hl.FillTransparency = 0.75
        hl.OutlineTransparency = 0
        hl.OutlineColor = color or Theme.Accent
        hl.FillColor = color or Theme.Accent
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ScreenGui
        Highlights[name .. "_" .. tostring(instance)] = hl
    end
    hl.Adornee = instance
    return hl
end

-- [Logic Loops] ----------------------------------------------------------------------------------------------------------------------------------------------------

-- Movement: WalkSpeed / JumpPower / Bhop / Noclip already on Stepped for noclip; heartbeat for the rest
local mvConn
mvConn = RunService.Heartbeat:Connect(function()
    local hum = getHum()
    if not hum then return end
    -- Init bypass once a character exists
    if Mommy.Bypass.BlockPunish then initBypass() end
    -- WalkSpeed with anti-cheat clamp
    if Mommy.Player.WalkSpeedEnabled then
        local target = Mommy.Player.WalkSpeed
        if Mommy.Bypass.ClampSpeed and target > MAX_SPEED_ALLOWED then
            target = MAX_SPEED_ALLOWED
        end
        pcall(function() hum.WalkSpeed = target end)
    end
    if Mommy.Player.JumpPowerEnabled then
        pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = Mommy.Player.JumpPower
        end)
    end
    if Mommy.Player.Bhop then
        if hum.MoveDirection.Magnitude > 0 and hum:GetState() ~= Enum.HumanoidStateType.Freefall then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        end
    end
end)
table.insert(Connections, mvConn)

-- Infinite Jump
local ijConn
ijConn = UserInputService.JumpRequest:Connect(function()
    if Mommy.Player.InfiniteJump then
        local hum = getHum()
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end
end)
table.insert(Connections, ijConn)

-- Anti AFK
if VirtualUser and LocalPlayer.Idled then
    local afkConn = LocalPlayer.Idled:Connect(function()
        if Mommy.Player.AntiAFK then
            pcall(function() VirtualUser:CaptureController() end)
            pcall(function() VirtualUser:ClickButton2(Vector2.new()) end)
        end
    end)
    table.insert(Connections, afkConn)
end

-- Auto Treadmill: stand on the chosen treadmill (server grants speed by proximity every 0.15s).
-- On the treadmill the anti-cheat allows STATION_MARGIN (20 studs) of slack, so holding
-- position there is safe. We move onto it with safe steps first, then anchor in place.
local tmThread
tmThread = task.spawn(function()
    table.insert(ActiveThreads, tmThread)
    while MommyAlive do
        task.wait(0.15)
        if not Mommy.Farm.AutoTreadmill then continue end
        local root = getRoot()
        if not root then continue end
        local idx = table.find(TreadmillNames, Mommy.Farm.TreadmillName) or 1
        local t = Treadmills[idx]
        if t and t.part then
            local target = t.part.CFrame + Vector3.new(0, 3, 0)
            if (root.Position - t.part.Position).Magnitude > 4 then
                -- move onto the treadmill in safe steps (within STATION_MARGIN once close)
                safeTP(target)
            end
            root.Anchored = true
        end
    end
end)

-- Auto Step Keycaps: move onto keycap parts within radius to gain XP.
-- Uses safe step-wise movement (not instant teleport) to dodge anti-cheat distance checks.
local stepThread
local keycapCache = nil
local stepIndex = 1
local function getKeycaps()
    if keycapCache then return keycapCache end
    local folder = Workspace:FindFirstChild("Keycaps")
    if not folder then return {} end
    local parts = {}
    for _, m in ipairs(folder:GetChildren()) do
        for _, p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then table.insert(parts, p) end
        end
    end
    keycapCache = parts
    return parts
end
stepThread = task.spawn(function()
    table.insert(ActiveThreads, stepThread)
    while MommyAlive do
        task.wait(0.1)
        if not Mommy.Farm.AutoStep then continue end
        local root = getRoot()
        if not root then continue end
        root.Anchored = false
        local parts = getKeycaps()
        if #parts == 0 then continue end
        -- find next keycap within radius
        local found = nil
        local limit = math.min(stepIndex + 40, #parts)
        for i = stepIndex, limit do
            local p = parts[i]
            if p and p.Parent and (p.Position - root.Position).Magnitude <= Mommy.Farm.StepRadius then
                found = p
                stepIndex = i + 1
                break
            end
        end
        if not found then
            -- advance index / wrap
            stepIndex = stepIndex + 40
            if stepIndex > #parts then stepIndex = 1 end
        else
            -- safe step-wise move onto the keycap (respects DISTANCE_MARGIN)
            safeTP(found.CFrame + Vector3.new(0, 3, 0))
        end
    end
end)

-- Auto Rebirth: fire Rebirth when Level meets the next tier requirement
local rbThread
rbThread = task.spawn(function()
    table.insert(ActiveThreads, rbThread)
    local lastFire = 0
    while MommyAlive do
        task.wait(2)
        if not Mommy.Farm.AutoRebirth then continue end
        local rebirths = statValue("Rebirths") or 0
        local tiers = GameConfig and GameConfig.REBIRTH_TIERS
        if not tiers then continue end
        local nextTier = tiers[rebirths + 1]
        if not nextTier then continue end
        local level = 0
        if ClientState then
            local ok, d = pcall(function() return ClientState:Get() end)
            if ok and d then level = d.Level or 0 end
        end
        if level >= (nextTier.level or math.huge) and (os.clock() - lastFire) > 5 then
            lastFire = os.clock()
            fireRemote("Rebirth")
        end
    end
end)

-- Auto Gift & Auto Special
local rewardThread
rewardThread = task.spawn(function()
    table.insert(ActiveThreads, rewardThread)
    while MommyAlive do
        task.wait(5)
        if Mommy.Farm.AutoGift then fireRemote("ClaimGift") end
        if Mommy.Farm.AutoSpecial then fireRemote("SpecialKeyEvent") end
    end
end)

-- Player ESP + part ESP (Treadmills/Winblocks/Checkpoints)
local espThread
espThread = task.spawn(function()
    table.insert(ActiveThreads, espThread)
    while MommyAlive do
        task.wait(0.3)
        local root = getRoot()
        local myPos = root and root.Position or Vector3.new()

        -- Player ESP
        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local key = "player_" .. player.Name
            if not Mommy.Visuals.ESP.Players or not hrp or not hum or hum.Health <= 0 then
                clearESP(key)
                continue
            end
            local dist = (hrp.Position - myPos).Magnitude
            if dist > Mommy.Visuals.ESP.MaxDist then
                clearESP(key)
                continue
            end
            local bb = ESPObjects[key]
            if not bb then
                bb = Instance.new("BillboardGui")
                bb.Name = "MommyESP"
                bb.Size = UDim2.new(0, 200, 0, 30)
                bb.StudsOffset = Vector3.new(0, 3, 0)
                bb.AlwaysOnTop = true
                local lbl = Instance.new("TextLabel", bb)
                lbl.BackgroundTransparency = 1
                lbl.Size = UDim2.new(1, 0, 1, 0)
                lbl.Font = Enum.Font.GothamBold
                lbl.TextSize = 13
                lbl.TextColor3 = Theme.Accent
                lbl.TextStrokeTransparency = 0.5
                bb.Parent = hrp
                ESPObjects[key] = bb
            end
            bb.Adornee = hrp
            local parts = {}
            if Mommy.Visuals.ESP.ShowNames then table.insert(parts, player.Name) end
            if Mommy.Visuals.ESP.ShowDistance then table.insert(parts, string.format("%dm", math.floor(dist))) end
            bb.TextLabel.Text = table.concat(parts, " | ")
        end

        -- Part ESP: Treadmills / Winblocks / Checkpoints
        local function espSet(key, list, color)
            if not Mommy.Visuals.ESP[key] then
                for n, _ in pairs(Highlights) do
                    if n:sub(1, #key + 1) == key .. "_" then clearESP(n) end
                end
                return
            end
            for _, item in ipairs(list) do
                local part = item.part or item
                if part and part.Parent then
                    local dist = (part.Position - myPos).Magnitude
                    if dist <= Mommy.Visuals.ESP.MaxDist then
                        ensureHighlight(key, part, color)
                    else
                        clearESP(key .. "_" .. tostring(part))
                    end
                end
            end
        end
        espSet("Treadmills", Treadmills, Color3.fromRGB(124, 200, 120))
        espSet("Winblocks", Winblocks, Color3.fromRGB(255, 215, 0))
        espSet("Checkpoints", Checkpoints, Color3.fromRGB(100, 180, 255))
    end
end)

-- Stats updater
local statThread
statThread = task.spawn(function()
    table.insert(ActiveThreads, statThread)
    while MommyAlive do
        task.wait(0.5)
        if not statLabels.speed then continue end
        local speedVal = statValue("Speed")
        statLabels.speed.Text = "Speed (currency): " .. (type(speedVal) == "string" and speedVal or fmtNum(speedVal or 0))
        local wins = statValue("Wins")
        statLabels.wins.Text = "Wins: " .. fmtNum(wins or 0)
        local rebirths = statValue("Rebirths") or 0
        statLabels.rebirths.Text = "Rebirths: " .. tostring(rebirths)

        local level, xp, xpReq, mult = 0, 0, 100, 1
        if ClientState then
            local ok, d = pcall(function() return ClientState:Get() end)
            if ok and d then
                level = d.Level or 0
                xp = d.XP or 0
                xpReq = d.XPRequired or 100
                mult = d.Multiplier or 1
            end
        end
        statLabels.level.Text = "Level: " .. tostring(level)
        statLabels.xp.Text = "XP: " .. fmtNum(xp) .. " / " .. fmtNum(xpReq)
        statLabels.mult.Text = "Speed Multiplier: x" .. fmtNum(mult)
        local hum = getHum()
        statLabels.walkspeed.Text = "WalkSpeed: " .. (hum and tostring(hum.WalkSpeed) or "n/a")

        local tiers = GameConfig and GameConfig.REBIRTH_TIERS
        local nextTier = tiers and tiers[rebirths + 1]
        if nextTier then
            local prog = math.clamp(level / (nextTier.level or 1), 0, 1)
            statLabels.rebirthprog.Text = string.format(
                "Rebirth: L%d / %d (%.0f%%) -> x%s",
                level, nextTier.level, prog * 100, fmtNum(nextTier.multiplier)
            )
        else
            statLabels.rebirthprog.Text = "Rebirth: MAX"
        end
    end
end)

-- Player list live update
local padConn
padConn = Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then
        table.insert(playerListValues, p.Name)
        tpPlDD.SetValues(playerListValues)
    end
end)
table.insert(Connections, padConn)
local prmConn
prmConn = Players.PlayerRemoving:Connect(function(p)
    for i, v in ipairs(playerListValues) do
        if v == p.Name then table.remove(playerListValues, i) break end
    end
    tpPlDD.SetValues(playerListValues)
    clearESP("player_" .. p.Name)
end)
table.insert(Connections, prmConn)

-- Character respawn: re-grant WalkSpeed/JumpPower on new character
local charAddedConn
charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    local hum = getHum()
    if hum and Mommy.Player.WalkSpeedEnabled then
        local ws = Mommy.Player.WalkSpeed
        if Mommy.Bypass.ClampSpeed and ws > MAX_SPEED_ALLOWED then ws = MAX_SPEED_ALLOWED end
        pcall(function() hum.WalkSpeed = ws end)
    end
    if hum and Mommy.Player.JumpPowerEnabled then
        pcall(function() hum.UseJumpPower = true; hum.JumpPower = Mommy.Player.JumpPower end)
    end
end)
table.insert(Connections, charAddedConn)

-- [Keybinds] ------------------------------------------------------------------------------------------------------------------------------------------------------
local keyConn
keyConn = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        ScreenGui.Enabled = not ScreenGui.Enabled
    elseif input.KeyCode == Enum.KeyCode.RightControl then
        local fn = getGlobal("DestroyMommy")
        if fn then fn() end
    end
end)
table.insert(Connections, keyConn)

-- [Cleanup] -------------------------------------------------------------------------------------------------------------------------------------------------------
local function DestroyMommy()
    MommyAlive = false
    -- Stop all features
    Mommy.Farm.AutoTreadmill = false
    Mommy.Farm.AutoStep = false
    Mommy.Farm.AutoRebirth = false
    Mommy.Farm.AutoGift = false
    Mommy.Farm.AutoSpecial = false
    Mommy.Player.WalkSpeedEnabled = false
    Mommy.Player.JumpPowerEnabled = false
    Mommy.Player.InfiniteJump = false
    Mommy.Player.Noclip = false
    Mommy.Player.Bhop = false
    Mommy.Player.AntiAFK = false
    Mommy.Bypass.BlockPunish = false
    Mommy.Bypass.SuppressAFK = false
    Mommy.Bypass.ClampSpeed = false
    Mommy.Visuals.FOV.Enable = false
    Mommy.Visuals.ESP.Players = false
    Mommy.Visuals.ESP.Treadmills = false
    Mommy.Visuals.ESP.Winblocks = false
    Mommy.Visuals.ESP.Checkpoints = false
    Mommy.Visuals.World.IndoorAmbience = false
    Mommy.Visuals.World.OutdoorAmbience = false
    Mommy.Visuals.World.Fog = false
    Mommy.Visuals.World.Saturation = false

    -- Disconnect connections
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    Connections = {}

    -- Destroy ESP / highlights
    for _, bb in pairs(ESPObjects) do pcall(function() bb:Destroy() end) end
    ESPObjects = {}
    for _, hl in pairs(Highlights) do pcall(function() hl:Destroy() end) end
    Highlights = {}

    -- Restore character
    local root = getRoot()
    if root then root.Anchored = false end
    local hum = getHum()
    if hum then
        pcall(function() hum.WalkSpeed = (GameConfig and GameConfig.DEFAULT_WALKSPEED) or 40 end)
        pcall(function() hum.UseJumpPower = true; hum.JumpPower = 50 end)
    end

    -- Restore Lighting
    pcall(function()
        Lighting.Ambient = Color3.fromRGB(0, 0, 0)
        Lighting.OutdoorAmbient = Color3.fromRGB(152, 152, 146)
        Lighting.FogColor = Color3.fromRGB(100, 87, 72)
        local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
        if cc then cc.Saturation = 0 end
        Workspace.Camera.FieldOfView = 70
    end)

    pcall(function() ScreenGui:Destroy() end)
    setGlobal("DestroyMommy", nil)
    print("[Mommy] GUI destroyed and all loops stopped.")
end
setGlobal("DestroyMommy", DestroyMommy)

-- [Init] ----------------------------------------------------------------------------------------------------------------------------------------------------------
Tabs[1].Page.Visible = true
Tabs[1].Button.BackgroundColor3 = Theme.TabActive
Tabs[1].Button.TextColor3 = Theme.Text

local Time = string.format("%.4f", os.clock() - Clock)
Notify("Mommy loaded in " .. Time .. "s | RightShift = toggle", 4)
print("[Mommy] +1 Speed Keyboard Escape loaded in " .. Time .. "s. Destroy: getgenv().DestroyMommy()")
