--[[
    Cinema Panel — инструмент для съёмки контента (клиентский, только для вашей камеры)
    Функции:
      * Spectator за NPC/монстрами (3-е и 1-е лицо), переключение между ними
      * Попытка управлять NPC (работает только если у клиента есть network ownership)
      * Freecam, Camera Lock на выбранном NPC
      * Расстановка/сохранение/переключение камер (сохраняются в файл, если executor поддерживает writefile)
      * День <-> Ночь, скрытие игроков
      * Панель с кнопками + горячие клавиши (таблица KEYS ниже)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

local lp = Players.LocalPlayer
local K = Enum.KeyCode
local function getCam() return workspace.CurrentCamera end

---------------------------------------------------------------------
-- НАСТРОЙКА ГОРЯЧИХ КЛАВИШ (меняйте под себя)
---------------------------------------------------------------------
local KEYS = {
    TogglePanel = K.RightShift,
    Freecam     = K.F1,
    Spectate    = K.F2,
    FirstPerson = K.F3,
    CameraLock  = K.F4,
    Control     = K.F5,
    PrevNPC     = K.Comma,
    NextNPC     = K.Period,
    PlaceCam    = K.F6,
    DayNight    = K.F7,
    HidePlayers = K.F8,
    FovDown     = K.LeftBracket,
    FovUp       = K.RightBracket,
    Exit        = K.Backspace,
}

local KEY_LABELS = {
    {"TogglePanel", "Показать/скрыть панель"},
    {"Freecam", "Freecam вкл/выкл"},
    {"Spectate", "Наблюдение за NPC вкл/выкл"},
    {"FirstPerson", "Вид от 1-го / 3-го лица"},
    {"CameraLock", "Camera Lock на NPC"},
    {"Control", "Управление NPC"},
    {"PrevNPC", "Предыдущий NPC"},
    {"NextNPC", "Следующий NPC"},
    {"PlaceCam", "Поставить камеру"},
    {"DayNight", "День / Ночь"},
    {"HidePlayers", "Скрыть игроков"},
    {"FovDown", "FOV меньше"},
    {"FovUp", "FOV больше"},
    {"Exit", "Выйти из всех режимов"},
}

---------------------------------------------------------------------
-- Очистка предыдущего запуска
---------------------------------------------------------------------
local genv = (getgenv and getgenv()) or _G
if genv.__CinePanelCleanup then pcall(genv.__CinePanelCleanup) end

local conns = {}
local function connect(sig, fn)
    local c = sig:Connect(fn)
    table.insert(conns, c)
    return c
end

---------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------
local S = {
    mode = "none",          -- none | free | spec
    target = nil,
    view = "third",         -- third | first
    lock = false,
    control = false,
    controlled = nil,
    yaw = 0, pitch = -0.25, dist = 12,
    lyaw = 0, lpitch = 0,
    fpos = Vector3.zero, fyaw = 0, fpitch = 0,
    speed = 40,
    fov = 70, origFov = 70,
    rmb = false,
    smooth = true,
    markers = false,
    cams = {},
    camId = 0,
    tween = nil,
    hidden = false, hideSelf = false,
    night = false, timeLock = false, origTime = Lighting.ClockTime,
}

local npcs = {}
local seen = setmetatable({}, {__mode = "k"})
local seenCounter = 0

local status = function(_) end
local refreshButtons = function() end
local rebuildNPCList = function() end
local rebuildCamList = function() end

---------------------------------------------------------------------
-- Утилиты
---------------------------------------------------------------------
local function typing() return UIS:GetFocusedTextBox() ~= nil end

local function rootOf(m)
    return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
end
local function headOf(m) return m:FindFirstChild("Head") or rootOf(m) end
local function humOf(m) return m and m:FindFirstChildOfClass("Humanoid") end

local function scanNPCs()
    local camPos = getCam().CFrame.Position
    local out = {}
    for _, h in ipairs(workspace:GetDescendants()) do
        if h:IsA("Humanoid") then
            local m = h.Parent
            if m and m:IsA("Model") and not Players:GetPlayerFromCharacter(m) and h.Health > 0 then
                local r = rootOf(m)
                if r then
                    if not seen[m] then
                        seenCounter = seenCounter + 1
                        seen[m] = seenCounter
                    end
                    table.insert(out, {model = m, root = r, dist = (r.Position - camPos).Magnitude, order = seen[m]})
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    npcs = out
end

local function pickNearest()
    scanNPCs()
    local best
    for _, e in ipairs(npcs) do
        if not best or e.dist < best.dist then best = e end
    end
    if best then S.target = best.model end
    return best ~= nil
end

---------------------------------------------------------------------
-- Блокировка стандартного управления персонажем во время режимов
---------------------------------------------------------------------
local sinkKeys = {K.W, K.A, K.S, K.D, K.Space, K.Q, K.E,
    K.One, K.Two, K.Three, K.Four, K.Five, K.Six, K.Seven, K.Eight, K.Nine}
local function bindSink()
    CAS:BindActionAtPriority("CineSink", function() return Enum.ContextActionResult.Sink end,
        false, Enum.ContextActionPriority.High.Value + 1, table.unpack(sinkKeys))
end
local function unbindSink() pcall(function() CAS:UnbindAction("CineSink") end) end

---------------------------------------------------------------------
-- Скрытие головы NPC в режиме 1-го лица
---------------------------------------------------------------------
local fpHidden = {}
local function setFPHidden(on)
    for p in pairs(fpHidden) do
        if p.Parent then p.LocalTransparencyModifier = 0 end
    end
    fpHidden = {}
    if on and S.target then
        local head = S.target:FindFirstChild("Head")
        for _, d in ipairs(S.target:GetDescendants()) do
            if d:IsA("BasePart") and (d == head or (d.Parent and d.Parent:IsA("Accessory"))) then
                fpHidden[d] = true
            end
        end
    end
end

---------------------------------------------------------------------
-- Управление NPC (клиентская попытка)
---------------------------------------------------------------------
local function syncControl()
    local want = (S.control and S.mode == "spec" and S.target) and humOf(S.target) or nil
    if S.controlled and S.controlled ~= want then
        pcall(function() S.controlled:Move(Vector3.zero, false) end)
    end
    if want and want ~= S.controlled then
        pcall(function() sethiddenproperty(lp, "SimulationRadius", math.huge) end)
    end
    S.controlled = want
end

---------------------------------------------------------------------
-- Режимы камеры
---------------------------------------------------------------------
local function activate()
    local cam = getCam()
    S.origFov = cam.FieldOfView
    S.fov = S.origFov
    bindSink()
end

local function setFree(cf)
    S.fpos = cf.Position
    S.fpitch, S.fyaw = cf:ToOrientation()
end

local function enterFree()
    if S.mode == "none" then activate() end
    if S.mode ~= "free" then setFree(getCam().CFrame) end
    S.mode = "free"
    S.tween = nil
    setFPHidden(false)
    syncControl()
    refreshButtons()
end

local function enterSpec(view)
    if not (S.target and S.target.Parent) then pickNearest() end
    if not S.target then status("NPC не найдены") return end
    local r = rootOf(S.target)
    if not r then status("У NPC нет частей тела") return end
    if S.mode == "none" then activate() end
    S.mode = "spec"
    S.view = view or S.view
    S.lock = false
    S.tween = nil
    local look = r.CFrame.LookVector
    local _, y = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z).Magnitude > 0.01 and Vector3.new(look.X, 0, look.Z) or Vector3.new(0, 0, -1)):ToOrientation()
    S.yaw, S.pitch = y, -0.25
    S.lyaw, S.lpitch = 0, 0
    setFPHidden(S.view == "first")
    syncControl()
    status("Наблюдение: " .. S.target.Name)
    refreshButtons()
    rebuildNPCList()
end

local function exitAll()
    if S.mode == "none" then return end
    S.mode = "none"
    S.control = false
    S.lock = false
    S.tween = nil
    S.rmb = false
    syncControl()
    setFPHidden(false)
    UIS.MouseBehavior = Enum.MouseBehavior.Default
    unbindSink()
    local cam = getCam()
    cam.CameraType = Enum.CameraType.Custom
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if hum then cam.CameraSubject = hum end
    cam.FieldOfView = S.origFov
    status("Режимы выключены")
    refreshButtons()
end

local function setTarget(m)
    S.target = m
    if S.mode == "spec" then
        enterSpec(S.view)
    else
        status("Выбран: " .. m.Name)
        refreshButtons()
        rebuildNPCList()
    end
end

local function cycle(d)
    if #npcs == 0 then scanNPCs() end
    if #npcs == 0 then status("NPC не найдены") return end
    local idx = 0
    for i, e in ipairs(npcs) do
        if e.model == S.target then idx = i break end
    end
    idx = ((idx - 1 + d) % #npcs) + 1
    setTarget(npcs[idx].model)
end

local function toggleLock()
    if not (S.target and S.target.Parent) then
        if not pickNearest() then status("NPC не найдены") return end
    end
    if S.lock then
        S.lock = false
        status("Camera Lock выключен")
    else
        enterFree()
        S.lock = true
        status("Camera Lock: " .. S.target.Name)
    end
    refreshButtons()
end

local function toggleControl()
    S.control = not S.control
    if S.control then
        if S.mode ~= "spec" then enterSpec(S.view) end
        if S.mode == "spec" then
            status("Управление: WASD + Space (нужен network ownership)")
        else
            S.control = false
        end
    else
        syncControl()
        status("Управление NPC выключено")
    end
    refreshButtons()
end

---------------------------------------------------------------------
-- Камеры (сохранение/переключение)
---------------------------------------------------------------------
local function camsFile() return "CinePanel_" .. tostring(game.PlaceId) .. ".json" end

local function saveCams()
    if not writefile then return end
    local t = {}
    for _, c in ipairs(S.cams) do
        table.insert(t, {n = c.name, c = {c.cf:GetComponents()}, f = c.fov})
    end
    pcall(function() writefile(camsFile(), HttpService:JSONEncode(t)) end)
end

local function loadCams()
    if not (isfile and readfile) then return end
    local okExists, exists = pcall(isfile, camsFile())
    if not (okExists and exists) then return end
    local ok, t = pcall(function() return HttpService:JSONDecode(readfile(camsFile())) end)
    if ok and type(t) == "table" then
        for _, e in ipairs(t) do
            S.camId = S.camId + 1
            table.insert(S.cams, {name = e.n, cf = CFrame.new(table.unpack(e.c)), fov = e.f})
        end
    end
end

local markerFolder
local function refreshMarkers()
    if markerFolder then markerFolder:Destroy() markerFolder = nil end
    if not S.markers then return end
    markerFolder = Instance.new("Folder")
    markerFolder.Name = "CinePanelMarkers"
    for _, c in ipairs(S.cams) do
        local p = Instance.new("Part")
        p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
        p.Size = Vector3.new(1, 1, 2)
        p.Color = Color3.fromRGB(255, 70, 70)
        p.Transparency = 0.3
        p.CFrame = c.cf
        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.fromOffset(80, 20)
        bb.AlwaysOnTop = true
        bb.StudsOffset = Vector3.new(0, 2, 0)
        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.fromScale(1, 1)
        tl.BackgroundTransparency = 1
        tl.Text = c.name
        tl.TextColor3 = Color3.new(1, 1, 1)
        tl.TextStrokeTransparency = 0
        tl.Parent = bb
        bb.Parent = p
        p.Parent = markerFolder
    end
    markerFolder.Parent = workspace
end

local function addCam()
    local cam = getCam()
    S.camId = S.camId + 1
    table.insert(S.cams, {name = "Cam " .. S.camId, cf = cam.CFrame, fov = (S.mode ~= "none") and S.fov or cam.FieldOfView})
    saveCams()
    refreshMarkers()
    rebuildCamList()
    status("Камера сохранена: Cam " .. S.camId .. " (клавиша " .. #S.cams .. ")")
end

local function gotoCam(i)
    local c = S.cams[i]
    if not c then return end
    if S.mode ~= "free" then enterFree() end
    S.lock = false
    if S.smooth then
        S.tween = {from = getCam().CFrame, to = c.cf, t = 0, dur = 0.8, fov0 = S.fov, fov1 = c.fov or S.fov}
    else
        setFree(c.cf)
        S.fov = c.fov or S.fov
    end
    status("Камера: " .. c.name)
    refreshButtons()
end

---------------------------------------------------------------------
-- Скрытие игроков
---------------------------------------------------------------------
local hiddenData = {}
local hideConns = {}

local function hideInst(d)
    local prop, hid
    if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
        prop, hid = "Transparency", 1
    elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("Highlight")
        or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
        prop, hid = "Enabled", false
    else
        return
    end
    if not hiddenData[d] then
        hiddenData[d] = {prop = prop, hid = hid, orig = d[prop]}
    end
    d[prop] = hid
end

local function hideChar(char)
    for _, d in ipairs(char:GetDescendants()) do hideInst(d) end
    table.insert(hideConns, char.DescendantAdded:Connect(hideInst))
end

local function watchPlayer(p)
    if p == lp and not S.hideSelf then return end
    if p.Character then hideChar(p.Character) end
    table.insert(hideConns, p.CharacterAdded:Connect(function(c)
        task.wait()
        hideChar(c)
    end))
end

local function applyHide()
    for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
    table.insert(hideConns, Players.PlayerAdded:Connect(watchPlayer))
end

local function clearHide()
    for _, c in ipairs(hideConns) do c:Disconnect() end
    hideConns = {}
    for d, info in pairs(hiddenData) do
        if d.Parent then pcall(function() d[info.prop] = info.orig end) end
    end
    hiddenData = {}
end

local function toggleHide(force)
    local want = (force == nil) and (not S.hidden) or force
    S.hidden = want
    clearHide()
    if want then applyHide() end
    status(want and "Игроки скрыты" or "Игроки показаны")
    refreshButtons()
end

---------------------------------------------------------------------
-- День / Ночь
---------------------------------------------------------------------
local function toggleDayNight()
    if not S.timeLock then S.origTime = Lighting.ClockTime end
    S.timeLock = true
    S.night = not S.night
    Lighting.ClockTime = S.night and 0 or 14
    status(S.night and "Ночь" or "День")
    refreshButtons()
end

local function resetTime()
    S.timeLock = false
    Lighting.ClockTime = S.origTime
    status("Время сброшено")
    refreshButtons()
end

connect(Lighting:GetPropertyChangedSignal("ClockTime"), function()
    if S.timeLock then
        local want = S.night and 0 or 14
        if math.abs(Lighting.ClockTime - want) > 0.01 then Lighting.ClockTime = want end
    end
end)

---------------------------------------------------------------------
-- Обновление камеры каждый кадр
---------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateFree(dt)
    local cam = getCam()

    if S.tween then
        local t = S.tween
        t.t = t.t + dt
        local a = math.min(t.t / t.dur, 1)
        local e = a * a * (3 - 2 * a)
        cam.CFrame = t.from:Lerp(t.to, e)
        S.fov = t.fov0 + (t.fov1 - t.fov0) * e
        if a >= 1 then
            setFree(t.to)
            S.tween = nil
        end
        return
    end

    if S.lock then
        local r = S.target and S.target.Parent and rootOf(S.target)
        if r then
            local p, y = CFrame.lookAt(S.fpos, r.Position + Vector3.new(0, 1.5, 0)):ToOrientation()
            S.fpitch, S.fyaw = p, y
        else
            S.lock = false
            status("Цель пропала — Lock выключен")
            refreshButtons()
        end
    end

    local move = Vector3.zero
    if not typing() then
        if UIS:IsKeyDown(K.W) then move = move + Vector3.new(0, 0, -1) end
        if UIS:IsKeyDown(K.S) then move = move + Vector3.new(0, 0, 1) end
        if UIS:IsKeyDown(K.A) then move = move + Vector3.new(-1, 0, 0) end
        if UIS:IsKeyDown(K.D) then move = move + Vector3.new(1, 0, 0) end
    end
    local vert = 0
    if not typing() then
        if UIS:IsKeyDown(K.E) then vert = vert + 1 end
        if UIS:IsKeyDown(K.Q) then vert = vert - 1 end
    end
    local spd = S.speed
    if UIS:IsKeyDown(K.LeftShift) then spd = spd * 3 end
    if UIS:IsKeyDown(K.LeftControl) then spd = spd / 4 end

    local rot = CFrame.fromOrientation(S.fpitch, S.fyaw, 0)
    local delta = rot:VectorToWorldSpace(move) + Vector3.new(0, vert, 0)
    S.fpos = S.fpos + delta * spd * dt
    cam.CFrame = CFrame.new(S.fpos) * rot
end

local function updateSpec(dt)
    local m = S.target
    local r = m and m.Parent and rootOf(m)
    if not r then
        status("Цель пропала — Freecam")
        enterFree()
        return
    end
    local cam = getCam()

    if S.view == "third" then
        local focus = r.Position + Vector3.new(0, 2, 0)
        local cf = CFrame.new(focus) * CFrame.fromOrientation(S.pitch, S.yaw, 0) * CFrame.new(0, 0, S.dist)
        rayParams.FilterDescendantsInstances = {m, lp.Character}
        local dir = cf.Position - focus
        local hit = workspace:Raycast(focus, dir, rayParams)
        local pos = hit and (hit.Position - dir.Unit * 0.5) or cf.Position
        cam.CFrame = CFrame.lookAt(pos, focus)
    else
        local h = headOf(m)
        cam.CFrame = h.CFrame * CFrame.new(0, 0, -0.5) * CFrame.fromOrientation(S.lpitch, S.lyaw, 0)
        for p in pairs(fpHidden) do
            if p.Parent then p.LocalTransparencyModifier = 1 end
        end
    end

    syncControl()
    local hum = S.controlled
    if hum and not typing() then
        local cf = cam.CFrame
        local f = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
        local rt = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
        f = f.Magnitude > 0.01 and f.Unit or Vector3.zero
        rt = rt.Magnitude > 0.01 and rt.Unit or Vector3.zero
        local d = Vector3.zero
        if UIS:IsKeyDown(K.W) then d = d + f end
        if UIS:IsKeyDown(K.S) then d = d - f end
        if UIS:IsKeyDown(K.D) then d = d + rt end
        if UIS:IsKeyDown(K.A) then d = d - rt end
        pcall(function()
            hum:Move(d, false)
            if UIS:IsKeyDown(K.Space) then hum.Jump = true end
        end)
    end
end

RunService:BindToRenderStep("CinePanel", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if S.mode == "none" then return end
    local cam = getCam()
    cam.CameraType = Enum.CameraType.Scriptable
    if S.mode == "free" then updateFree(dt) else updateSpec(dt) end
    cam.FieldOfView = S.fov
end)

---------------------------------------------------------------------
-- Ввод
---------------------------------------------------------------------
local gui -- объявлено заранее для TogglePanel

local ACTIONS = {
    Freecam = function() if S.mode == "free" then exitAll() else enterFree() end end,
    Spectate = function() if S.mode == "spec" then exitAll() else enterSpec(S.view) end end,
    FirstPerson = function()
        if S.mode == "spec" then
            enterSpec(S.view == "first" and "third" or "first")
        else
            enterSpec("first")
        end
    end,
    CameraLock = toggleLock,
    Control = toggleControl,
    PrevNPC = function() cycle(-1) end,
    NextNPC = function() cycle(1) end,
    PlaceCam = addCam,
    DayNight = toggleDayNight,
    HidePlayers = function() toggleHide() end,
    FovDown = function()
        S.fov = math.clamp(S.fov - 5, 10, 120)
        if S.mode == "none" then getCam().FieldOfView = S.fov end
        refreshButtons()
    end,
    FovUp = function()
        S.fov = math.clamp(S.fov + 5, 10, 120)
        if S.mode == "none" then getCam().FieldOfView = S.fov end
        refreshButtons()
    end,
    Exit = exitAll,
    TogglePanel = function() if gui then gui.Enabled = not gui.Enabled end end,
}

connect(UIS.InputBegan, function(input, gp)
    if typing() then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        if not gp and S.mode ~= "none" then
            S.rmb = true
            UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        end
        return
    end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local kc = input.KeyCode
    for name, key in pairs(KEYS) do
        if key == kc and ACTIONS[name] then
            ACTIONS[name]()
            return
        end
    end
    if S.mode ~= "none" and kc.Value >= 49 and kc.Value <= 57 then
        gotoCam(kc.Value - 48)
    end
end)

connect(UIS.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        S.rmb = false
        if S.mode ~= "none" then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    end
end)

connect(UIS.InputChanged, function(input, gp)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if not S.rmb then return end
        local d = input.Delta
        local sens = 0.0035
        if S.mode == "free" then
            if not S.lock then
                S.fyaw = S.fyaw - d.X * sens
                S.fpitch = math.clamp(S.fpitch - d.Y * sens, -1.5, 1.5)
            end
        elseif S.mode == "spec" then
            if S.view == "third" then
                S.yaw = S.yaw - d.X * sens
                S.pitch = math.clamp(S.pitch - d.Y * sens, -1.4, 1.4)
            else
                S.lyaw = S.lyaw - d.X * sens
                S.lpitch = math.clamp(S.lpitch - d.Y * sens, -1.4, 1.4)
            end
        end
    elseif input.UserInputType == Enum.UserInputType.MouseWheel then
        if gp or S.mode == "none" then return end
        local z = input.Position.Z
        if S.mode == "free" then
            S.speed = math.clamp(S.speed * (1.15 ^ z), 2, 500)
        elseif S.view == "third" then
            S.dist = math.clamp(S.dist - z * 2, 2, 80)
        end
        refreshButtons()
    end
end)

---------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------
local BG, PANEL, BTN = Color3.fromRGB(24, 24, 30), Color3.fromRGB(34, 34, 42), Color3.fromRGB(52, 52, 64)
local ON, TXT = Color3.fromRGB(60, 150, 95), Color3.fromRGB(235, 235, 240)

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

gui = new("ScreenGui", {Name = "CinePanel", ResetOnSpawn = false, DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
do
    local ok = false
    if gethui then ok = pcall(function() gui.Parent = gethui() end) and gui.Parent ~= nil end
    if not ok then ok = pcall(function() gui.Parent = game:GetService("CoreGui") end) and gui.Parent ~= nil end
    if not ok then gui.Parent = lp:WaitForChild("PlayerGui") end
end

local main = new("Frame", {Size = UDim2.fromOffset(320, 470), Position = UDim2.fromOffset(20, 80),
    BackgroundColor3 = BG, BorderSizePixel = 0, Active = true}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, main)

local titleBar = new("TextLabel", {Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(16, 16, 22),
    BorderSizePixel = 0, Text = "  Cinema Panel", TextColor3 = TXT, Font = Enum.Font.GothamBold,
    TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, titleBar)

-- перетаскивание
do
    local dragging, startPos, startMouse
    titleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPos = main.Position
            startMouse = i.Position
        end
    end)
    connect(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startMouse
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    connect(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local function styleBtn(b)
    new("UICorner", {CornerRadius = UDim.new(0, 5)}, b)
    return b
end

local function btn(parent, text, cb, props)
    local b = new("TextButton", {Text = text, BackgroundColor3 = BTN, TextColor3 = TXT, Font = Enum.Font.Gotham,
        TextSize = 12, BorderSizePixel = 0}, parent)
    if props then for k, v in pairs(props) do b[k] = v end end
    styleBtn(b)
    b.MouseButton1Click:Connect(cb)
    return b
end

local closeBtn = btn(titleBar, "X", function()
    if genv.__CinePanelCleanup then genv.__CinePanelCleanup() end
end, {Size = UDim2.fromOffset(24, 20), Position = UDim2.new(1, -28, 0, 5), BackgroundColor3 = Color3.fromRGB(150, 50, 50)})

-- вкладки
local pages, tabBtns = {}, {}
local tabNames = {"NPC", "Камеры", "Мир", "Клавиши"}
local tabBar = new("Frame", {Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 34), BackgroundTransparency = 1}, main)
new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder}, tabBar)

local function showTab(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(tabBtns) do b.BackgroundColor3 = (n == name) and Color3.fromRGB(80, 105, 220) or BTN end
end

for i, n in ipairs(tabNames) do
    local b = btn(tabBar, n, function() showTab(n) end, {Size = UDim2.new(0.25, -3, 1, 0), LayoutOrder = i})
    tabBtns[n] = b
    pages[n] = new("Frame", {Size = UDim2.new(1, -16, 1, -96), Position = UDim2.fromOffset(8, 66),
        BackgroundTransparency = 1, Visible = false}, main)
end

local statusLabel = new("TextLabel", {Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 1, -26),
    BackgroundColor3 = PANEL, BorderSizePixel = 0, Text = "Готово", TextColor3 = Color3.fromRGB(180, 190, 255),
    Font = Enum.Font.Gotham, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd}, main)
new("UICorner", {CornerRadius = UDim.new(0, 5)}, statusLabel)
status = function(t) statusLabel.Text = t end

local function grid(parent, height)
    local g = new("Frame", {Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1}, parent)
    new("UIGridLayout", {CellSize = UDim2.new(0.5, -3, 0, 26), CellPadding = UDim2.fromOffset(6, 6),
        SortOrder = Enum.SortOrder.LayoutOrder}, g)
    return g
end
local function gbtn(g, text, cb)
    local b = btn(g, text, cb)
    b.LayoutOrder = #g:GetChildren()
    return b
end
local function scroller(parent, y)
    local s = new("ScrollingFrame", {Size = UDim2.new(1, 0, 1, -y), Position = UDim2.fromOffset(0, y),
        BackgroundColor3 = PANEL, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y}, parent)
    new("UICorner", {CornerRadius = UDim.new(0, 5)}, s)
    new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, s)
    new("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8)}, s)
    return s
end

local B = {}

-- Вкладка NPC
do
    local p = pages["NPC"]
    local g = grid(p, 158)
    B.spec    = gbtn(g, "Наблюдать (3-е лицо)", function() enterSpec("third") end)
    B.first   = gbtn(g, "Вид от 1-го лица", function() enterSpec("first") end)
    B.lock    = gbtn(g, "Camera Lock", toggleLock)
    B.control = gbtn(g, "Управлять NPC", toggleControl)
    gbtn(g, "< Пред. NPC", function() cycle(-1) end)
    gbtn(g, "След. NPC >", function() cycle(1) end)
    B.free    = gbtn(g, "Freecam", function() ACTIONS.Freecam() end)
    gbtn(g, "Выйти из режимов", exitAll)
    gbtn(g, "Ближайший NPC", function()
        if pickNearest() then setTarget(S.target) else status("NPC не найдены") end
    end)
    gbtn(g, "Обновить список", function() scanNPCs() rebuildNPCList() end)

    local list = scroller(p, 166)
    local rows = {}
    rebuildNPCList = function()
        local alive = {}
        for _, e in ipairs(npcs) do
            alive[e.model] = true
            local row = rows[e.model]
            if not row then
                row = btn(list, "", function() setTarget(e.model) end,
                    {Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left})
                rows[e.model] = row
            end
            row.LayoutOrder = e.order
            row.Text = "  " .. e.model.Name .. "  [" .. math.floor(e.dist) .. " м]"
            row.BackgroundColor3 = (e.model == S.target) and Color3.fromRGB(80, 105, 220) or BTN
        end
        for m, row in pairs(rows) do
            if not alive[m] then row:Destroy() rows[m] = nil end
        end
    end
end

-- Вкладка Камеры
do
    local p = pages["Камеры"]
    local g = grid(p, 70)
    gbtn(g, "+ Поставить камеру", addCam)
    B.smooth = gbtn(g, "", function() S.smooth = not S.smooth refreshButtons() end)
    B.markers = gbtn(g, "", function() S.markers = not S.markers refreshMarkers() refreshButtons() end)
    gbtn(g, "Очистить все", function()
        S.cams = {}
        saveCams()
        refreshMarkers()
        rebuildCamList()
    end)

    local list = scroller(p, 78)
    rebuildCamList = function()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        for i, c in ipairs(S.cams) do
            local row = new("Frame", {Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = i}, list)
            btn(row, "  [" .. i .. "] " .. c.name, function() gotoCam(i) end,
                {Size = UDim2.new(1, -30, 1, 0), TextXAlignment = Enum.TextXAlignment.Left})
            btn(row, "X", function()
                table.remove(S.cams, i)
                saveCams()
                refreshMarkers()
                rebuildCamList()
            end, {Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -26, 0, 0),
                BackgroundColor3 = Color3.fromRGB(150, 50, 50)})
        end
    end
end

-- Вкладка Мир
do
    local p = pages["Мир"]
    local g = grid(p, 140)
    B.night = gbtn(g, "День <-> Ночь", toggleDayNight)
    gbtn(g, "Сбросить время", resetTime)
    B.hide = gbtn(g, "Скрыть игроков", function() toggleHide() end)
    B.hideSelf = gbtn(g, "", function()
        S.hideSelf = not S.hideSelf
        if S.hidden then toggleHide(true) end
        refreshButtons()
    end)
    gbtn(g, "FOV -", ACTIONS.FovDown)
    gbtn(g, "FOV +", ACTIONS.FovUp)
    gbtn(g, "Скорость камеры -", function() S.speed = math.clamp(S.speed / 1.3, 2, 500) refreshButtons() end)
    gbtn(g, "Скорость камеры +", function() S.speed = math.clamp(S.speed * 1.3, 2, 500) refreshButtons() end)
    B.info = new("TextLabel", {Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 150),
        BackgroundTransparency = 1, TextColor3 = TXT, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, p)
end

-- Вкладка Клавиши
do
    local lines = {}
    for _, e in ipairs(KEY_LABELS) do
        table.insert(lines, string.format("%-12s - %s", KEYS[e[1]].Name, e[2]))
    end
    table.insert(lines, "")
    table.insert(lines, "1-9          - перейти к камере №")
    table.insert(lines, "ПКМ (зажать) - поворот камеры")
    table.insert(lines, "WASD, Q/E    - полёт (Freecam)")
    table.insert(lines, "Shift/Ctrl  - быстрее / медленнее")
    table.insert(lines, "Колесо      - скорость / дистанция")
    new("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = PANEL, BorderSizePixel = 0,
        Text = table.concat(lines, "\n"), TextColor3 = TXT, Font = Enum.Font.Code, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, pages["Клавиши"])
end

refreshButtons = function()
    local function mark(b, on) if b then b.BackgroundColor3 = on and ON or BTN end end
    mark(B.spec, S.mode == "spec" and S.view == "third")
    mark(B.first, S.mode == "spec" and S.view == "first")
    mark(B.lock, S.lock)
    mark(B.control, S.control)
    mark(B.free, S.mode == "free")
    mark(B.hide, S.hidden)
    mark(B.night, S.timeLock and S.night)
    B.smooth.Text = "Плавно: " .. (S.smooth and "ВКЛ" or "ВЫКЛ")
    B.markers.Text = "Маркеры: " .. (S.markers and "ВКЛ" or "ВЫКЛ")
    B.hideSelf.Text = "Скрывать и себя: " .. (S.hideSelf and "ДА" or "НЕТ")
    B.info.Text = string.format("FOV: %d   Скорость: %d\nВремя: %s", math.floor(S.fov + 0.5), math.floor(S.speed + 0.5),
        S.timeLock and (S.night and "ночь (фикс.)" or "день (фикс.)") or "по игре")
end

---------------------------------------------------------------------
-- Фоновые задачи
---------------------------------------------------------------------
local acc = 0
connect(RunService.Heartbeat, function(dt)
    acc = acc + dt
    if acc >= 3 then
        acc = 0
        if gui.Enabled and pages["NPC"].Visible then
            scanNPCs()
            rebuildNPCList()
        end
    end
    if S.hidden then
        for d, info in pairs(hiddenData) do
            if d.Parent and d[info.prop] ~= info.hid then d[info.prop] = info.hid end
        end
    end
end)

genv.__CinePanelCleanup = function()
    exitAll()
    unbindSink()
    S.timeLock = false
    clearHide()
    if markerFolder then markerFolder:Destroy() end
    pcall(function() RunService:UnbindFromRenderStep("CinePanel") end)
    for _, c in ipairs(conns) do c:Disconnect() end
    if gui then gui:Destroy() end
    genv.__CinePanelCleanup = nil
end

loadCams()
scanNPCs()
rebuildNPCList()
rebuildCamList()
showTab("NPC")
refreshButtons()
status("Готово. RightShift — скрыть/показать панель")
