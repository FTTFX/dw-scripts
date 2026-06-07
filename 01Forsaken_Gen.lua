-- 01Forsaken_Gen v2.0
-- โหมดใหม่: คุณเดินไปกด E เอง → สคริปต์ยิง progress ให้
-- ไม่มี pathfinding แล้ว

local PREFIX = "F01GEN"
if _G[PREFIX.."_CONNS"] then
    for _, c in ipairs(_G[PREFIX.."_CONNS"]) do pcall(function() c:Disconnect() end) end
end
_G[PREFIX.."_CONNS"] = {}
_G[PREFIX.."_ON"]    = false
_G[PREFIX.."_BUSY"]  = false

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local GEN_TIME     = 2.5   -- ห้ามต่ำกว่า 2.5 → kick
local FIRE_PER_GEN = 6     -- จำนวน RE:FireServer ต่อ gen

--------------------------------------------------
-- core: ทำ gen 1 ตัว (ยิง progress 6 ครั้ง)
--------------------------------------------------
local function doGen(g)
    if _G[PREFIX.."_BUSY"] then return end
    _G[PREFIX.."_BUSY"] = true

    -- sprint + stamina patch
    pcall(function()
        local mod = require(game.ReplicatedStorage.Systems.Character.Game.Sprinting)
        mod.StaminaLossDisabled = true
    end)

    local RE = g:FindFirstChild("Remotes") and g.Remotes:FindFirstChild("RE")
    if RE then
        for i = 1, FIRE_PER_GEN do
            if not _G[PREFIX.."_ON"] then break end
            if g.Progress and g.Progress.Value >= 100 then break end
            pcall(function() RE:FireServer() end)
            task.wait(GEN_TIME)
        end
    end

    _G[PREFIX.."_BUSY"] = false
end

--------------------------------------------------
-- listener: ดักทุก Generator ที่อยู่บน map
-- เมื่อ ProximityPrompt ถูก trigger → เริ่มยิง progress
--------------------------------------------------
local function hookGen(g)
    if not g or g.Name ~= "Generator" then return end
    local prompt = g:FindFirstChild("Main") and g.Main:FindFirstChild("Prompt")
    if not prompt then return end

    local c = prompt.Triggered:Connect(function(plr)
        if plr ~= LP then return end
        if not _G[PREFIX.."_ON"] then return end
        task.spawn(function() doGen(g) end)
    end)
    table.insert(_G[PREFIX.."_CONNS"], c)
end

local function scanMap()
    local map = workspace:FindFirstChild("Map")
    map = map and map:FindFirstChild("Ingame")
    map = map and map:FindFirstChild("Map")
    if not map then return end

    for _, g in ipairs(map:GetChildren()) do hookGen(g) end
    local c = map.ChildAdded:Connect(function(child)
        task.wait(0.5)
        hookGen(child)
    end)
    table.insert(_G[PREFIX.."_CONNS"], c)
end

scanMap()
-- รอ map โหลด (ถ้ายังไม่มี ingame)
task.spawn(function()
    while not (workspace:FindFirstChild("Map")
           and workspace.Map:FindFirstChild("Ingame")
           and workspace.Map.Ingame:FindFirstChild("Map")) do
        task.wait(1)
    end
    scanMap()
end)

-- respawn → rescan
local c = LP.CharacterAdded:Connect(function()
    task.wait(3)
    scanMap()
end)
table.insert(_G[PREFIX.."_CONNS"], c)

--------------------------------------------------
-- Floating button (ON/OFF toggle)
--------------------------------------------------
local PlayerGui = LP:WaitForChild("PlayerGui", 5)
for _, where in ipairs({PlayerGui, game:GetService("CoreGui")}) do
    pcall(function()
        local old = where:FindFirstChild(PREFIX.."_UI")
        if old then old:Destroy() end
    end)
end

local gui = Instance.new("ScreenGui")
gui.Name = PREFIX.."_UI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local parented = false
if gethui then
    local ok = pcall(function() gui.Parent = gethui() end)
    if ok then parented = true end
end
if not parented and PlayerGui then
    pcall(function() gui.Parent = PlayerGui end)
end

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(0, 80, 0, 80)
btn.Position = UDim2.new(0, 30, 0.5, -40)
btn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
btn.BackgroundTransparency = 0.05
btn.BorderSizePixel = 0
btn.AutoButtonColor = false
btn.Text = "GEN\nOFF"
btn.TextColor3 = Color3.fromRGB(255, 90, 90)
btn.Font = Enum.Font.GothamBold
btn.TextSize = 16
btn.Active = true
btn.Draggable = true
btn.ZIndex = 100
btn.Parent = gui

Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
local stroke = Instance.new("UIStroke", btn)
stroke.Thickness = 3
stroke.Color = Color3.fromRGB(255, 90, 90)

local UIS = game:GetService("UserInputService")
local dragging, dragStart, startPos
btn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = i.Position; startPos = btn.Position
    end
end)
btn.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                  or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                 startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local function setState(on)
    _G[PREFIX.."_ON"] = on
    if on then
        btn.Text = "GEN\nON"
        btn.TextColor3 = Color3.fromRGB(120, 255, 120)
        stroke.Color = Color3.fromRGB(120, 255, 120)
    else
        btn.Text = "GEN\nOFF"
        btn.TextColor3 = Color3.fromRGB(255, 90, 90)
        stroke.Color = Color3.fromRGB(255, 90, 90)
    end
end

local clickStart
btn.MouseButton1Down:Connect(function() clickStart = tick() end)
btn.MouseButton1Click:Connect(function()
    if clickStart and tick() - clickStart < 0.3 then
        setState(not _G[PREFIX.."_ON"])
    end
end)

setState(false)
print("[01Forsaken_Gen v2.0] โหมดมือกดเอง — เปิดปุ่ม → เดินไปกด E ที่ gen → progress ขึ้นเอง")
