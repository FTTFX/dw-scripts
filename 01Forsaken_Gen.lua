-- 01Forsaken_Gen v1.1
-- Generator autofarm + floating mini button

local PREFIX = "F01GEN"
if _G[PREFIX.."_CONNS"] then
    for _, c in ipairs(_G[PREFIX.."_CONNS"]) do pcall(function() c:Disconnect() end) end
end
_G[PREFIX.."_CONNS"] = {}
_G[PREFIX.."_STOP"] = false

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local PathfindingSv = game:GetService("PathfindingService")
local LP = Players.LocalPlayer

local GEN_TIME      = 2.5  -- วินาทีต่อ fire (ห้าม < 2.5 → kick)
local FIRE_PER_GEN  = 6    -- จำนวน RE:FireServer per gen
local SAFE_DIST     = 25   -- studs — มี survivor อื่นใกล้กว่านี้ ข้าม
local MAX_REACH_T   = 5    -- timeout ต่อ waypoint
local SPEED_MULT    = 2.15 -- SpeedMultipliers.Sprinting

--------------------------------------------------
-- helpers
--------------------------------------------------
local function getMap()
    local m = workspace:FindFirstChild("Map")
    m = m and m:FindFirstChild("Ingame")
    return m and m:FindFirstChild("Map")
end

local function charOK()
    local ch = LP.Character
    return ch
        and ch:FindFirstChild("HumanoidRootPart")
        and ch:FindFirstChildOfClass("Humanoid")
        and ch:FindFirstChildOfClass("Humanoid").Health > 0
end

local function killerPos()
    local kf = workspace:FindFirstChild("Players")
    kf = kf and kf:FindFirstChild("Killers")
    local k = kf and kf:GetChildren()[1]
    local hrp = k and k:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position
end

--------------------------------------------------
-- find generators (sort: ไกล killer ก่อน)
--------------------------------------------------
local function findGens()
    local map = getMap(); if not map then return {} end
    local list = {}
    for _, g in ipairs(map:GetChildren()) do
        if g.Name == "Generator"
           and g:FindFirstChild("Progress") and g.Progress.Value < 100 then
            local nearby = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Character
                   and p:DistanceFromCharacter(g:GetPivot().Position) <= SAFE_DIST then
                    nearby = true; break
                end
            end
            if not nearby then table.insert(list, g) end
        end
    end
    local kp = killerPos()
    if kp then
        table.sort(list, function(a, b)
            return (a:GetPivot().Position - kp).Magnitude
                 > (b:GetPivot().Position - kp).Magnitude
        end)
    end
    return list
end

--------------------------------------------------
-- sprint patch (ไม่หมด stamina + เร็วขึ้น)
--------------------------------------------------
local function patchSprint()
    pcall(function()
        local mod = require(game.ReplicatedStorage.Systems.Character.Game.Sprinting)
        mod.StaminaLossDisabled = true
        mod.IsSprinting = true
    end)
    pcall(function()
        LP.Character.SpeedMultipliers.Sprinting.Value = SPEED_MULT
    end)
end

--------------------------------------------------
-- walk to generator
--------------------------------------------------
local function walkTo(gen)
    if not charOK() then return false end
    local hrp  = LP.Character.HumanoidRootPart
    local hum  = LP.Character:FindFirstChildOfClass("Humanoid")
    local target = gen:GetPivot().Position + gen:GetPivot().LookVector * 3

    local path = PathfindingSv:CreatePath({
        AgentRadius = 2.5, AgentHeight = 1, AgentCanJump = false,
    })
    local ok = pcall(function() path:ComputeAsync(hrp.Position, target) end)
    if not ok or path.Status ~= Enum.PathStatus.Success then return false end

    patchSprint()
    for _, wp in ipairs(path:GetWaypoints()) do
        if _G[PREFIX.."_STOP"] or not charOK() then return false end
        hum:MoveTo(wp.Position)
        local t = tick()
        while tick() - t < MAX_REACH_T do
            if (hrp.Position - wp.Position).Magnitude < 5 then break end
            RunService.Heartbeat:Wait()
        end
    end
    return true
end

--------------------------------------------------
-- fire prompt + ยิง progress
--------------------------------------------------
local function doGen(g)
    if not g:FindFirstChild("Main") or not g.Main:FindFirstChild("Prompt") then return end
    local prompt = g.Main.Prompt
    fireproximityprompt(prompt)
    task.wait(0.4)

    -- ถ้า prompt ไม่ติด → ลองด้านข้าง
    if not (g:FindFirstChild("Remotes") and g.Remotes:FindFirstChild("RE")) then return end
    for _, off in ipairs({
        g:GetPivot().Position - g:GetPivot().RightVector * 3,
        g:GetPivot().Position + g:GetPivot().RightVector * 3,
    }) do
        if g.Progress.Value > 0 then break end
        if charOK() then
            LP.Character.HumanoidRootPart.CFrame = CFrame.new(off)
            task.wait(0.25); fireproximityprompt(prompt)
        end
    end

    local RE = g.Remotes.RE
    for i = 1, FIRE_PER_GEN do
        if _G[PREFIX.."_STOP"] or g.Progress.Value >= 100 then break end
        RE:FireServer()
        task.wait(GEN_TIME)
    end
end

--------------------------------------------------
-- main loop (เรียกใหม่ทุกครั้งที่ respawn)
--------------------------------------------------
local function run()
    if _G[PREFIX.."_STOP"] then return end
    if LP.Character.Parent ~= workspace.Players.Survivors then return end

    for _, g in ipairs(findGens()) do
        if _G[PREFIX.."_STOP"] or not charOK() then break end
        if (LP.Character:GetPivot().Position - g:GetPivot().Position).Magnitude <= 500 then
            local reached = false
            for _ = 1, 3 do
                if walkTo(g) then reached = true; break end
                task.wait(1)
            end
            if reached then doGen(g) end
        end
    end
end

--------------------------------------------------
-- hook respawn
--------------------------------------------------
local conn = LP.CharacterAdded:Connect(function()
    task.wait(4)
    if not _G[PREFIX.."_STOP"] then run() end
end)
table.insert(_G[PREFIX.."_CONNS"], conn)

--------------------------------------------------
-- Floating Mini Button (draggable, ON/OFF)
--------------------------------------------------
-- ลอง parent หลายที่ — executor บางตัว block CoreGui
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

-- parent priority: gethui > PlayerGui > CoreGui (PlayerGui เวิร์คสุดบน mobile exec)
local parented = false
if gethui then
    local ok = pcall(function() gui.Parent = gethui() end)
    if ok then parented = true end
end
if not parented and PlayerGui then
    local ok = pcall(function() gui.Parent = PlayerGui end)
    if ok then parented = true end
end
if not parented then
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
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

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = btn

local stroke = Instance.new("UIStroke")
stroke.Thickness = 3
stroke.Color = Color3.fromRGB(255, 90, 90)
stroke.Parent = btn

-- manual drag fallback (สำหรับ exec ที่ Draggable เสีย)
local UIS = game:GetService("UserInputService")
local dragging, dragStart, startPos
btn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = i.Position
        startPos = btn.Position
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
        btn.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local function setState(on)
    _G[PREFIX.."_ON"] = on
    _G[PREFIX.."_STOP"] = not on
    if on then
        btn.Text = "GEN\nON"
        btn.TextColor3 = Color3.fromRGB(120, 255, 120)
        stroke.Color = Color3.fromRGB(120, 255, 120)
        if LP.Character then task.spawn(run) end
    else
        btn.Text = "GEN\nOFF"
        btn.TextColor3 = Color3.fromRGB(255, 90, 90)
        stroke.Color = Color3.fromRGB(255, 90, 90)
    end
end

-- กันโดน drag แล้วเข้าใจผิดว่าเป็นคลิก
local clickStart
btn.MouseButton1Down:Connect(function() clickStart = tick() end)
btn.MouseButton1Click:Connect(function()
    if clickStart and tick() - clickStart < 0.3 then
        setState(not _G[PREFIX.."_ON"])
    end
end)

setState(false)  -- เริ่มต้น OFF (กดเอง)

print("[01Forsaken_Gen v1.1] loaded — กดปุ่ม GEN ลอยซ้ายจอ")
