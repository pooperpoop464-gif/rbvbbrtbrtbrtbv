--[[
    Cinema Panel — инструмент для съёмки контента (клиентский, только для вашей камеры)
    Функции:
      * Spectator за NPC/монстрами (3-е и 1-е лицо), переключение между ними
      * Визуальное управление NPC (только для вас)
      * Freecam, Camera Lock на выбранном NPC
      * Расстановка/сохранение/переключение камер (сохраняются в файл, если executor поддерживает writefile)
      * День <-> Ночь, скрытие игроков
      * Панель с кнопками + горячие клавиши (таблица KEYS ниже)
      * Функция атаки для NPC
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

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
    God         = K.F10,
    HideNPCs    = K.Delete,
    PlayersAsNPC = K.End,
    CaptureNPC  = K.Home,
    KillFront   = K.X,
    Puppet      = K.P,
    KillNearest = K.Insert,
    KillSelected = K.PageDown,
    ReviveAll   = K.PageUp,
    Exit        = K.Backspace,
    Attack      = K.Z, -- Новая клавиша для атаки
}

local KEY_LABELS = {
    {"TogglePanel", "Показать/скрыть панель"},
    {"Freecam", "Freecam вкл/выкл"},
    {"Spectate", "Наблюдение за NPC вкл/выкл"},
    {"FirstPerson", "Вид от 1-го / 3-го лица"},
    {"CameraLock", "Camera Lock на NPC"},
    {"Control", "Визуальное управление NPC"},
    {"PrevNPC", "Предыдущий NPC"},
    {"NextNPC", "Следующий NPC"},
    {"PlaceCam", "Поставить камеру"},
    {"DayNight", "День / Ночь"},
    {"HidePlayers", "Скрыть игроков"},
    {"FovDown", "FOV меньше"},
    {"FovUp", "FOV больше"},
    {"God", "Бессмертие вкл/выкл"},
    {"HideNPCs", "Скрыть всех NPC (выбранный виден)"},
    {"PlayersAsNPC", "Игроки = модели NPC"},
    {"CaptureNPC", "Скопировать выбранного NPC"},
    {"KillFront", "KILL: убить NPC перед тобой"},
    {"Puppet", "Кукла (неуязвимость от NPC)"},
    {"KillNearest", "Визуально убить ближайшего"},
    {"KillSelected", "Визуально убить выбранного"},
    {"ReviveAll", "Вернуть всех"},
    {"Exit", "Выйти из всех режимов"},
    {"Attack", "Атаковать выбранным NPC"},
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
    god = false,
    hideNPC = false, swap = false, listPlayers = false, basicAnim = false,
    selfEntry = nil, allEntry = nil,
    visualControl = false, -- Новое поле для визуального управления
    visualControlledNPC = nil, -- NPC, которым визуально управляем
    visualControlMoveVector = Vector3.zero,
    visualControlJump = false,
    attackCooldown = 0,
}

local npcs = {}
local puppet = nil          -- «кукла»: локальная копия персонажа (см. togglePuppet)
local function myRootPart()   -- корень того, кем ты сейчас управляешь
    if puppet and puppet.root and puppet.root.Parent then return puppet.root end
    return lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
end
local seen = setmetatable({}, {__mode = "k"})
local seenCounter = 0

local status = function(_) end
local refreshButtons = function() end
local rebuildNPCList = function() end
local rebuildCamList = function() end
local updateNPCHide = function() end
local function isSkinModel(m) return m.Parent ~= nil and (m.Parent.Name == "CineSkins" or m.Parent.Name == "CineFX") end

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
        if h:IsA("Humanoid") or h:IsA("AnimationController") then
            local m = h.Parent
            local plr = m and m:IsA("Model") and Players:GetPlayerFromCharacter(m)
            if m and m:IsA("Model") and not isSkinModel(m) and (not plr or (S.listPlayers and plr ~= lp))
                and (not h:IsA("Humanoid") or h.Health > 0) then
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
-- Визуальное управление NPC (только для клиента)
---------------------------------------------------------------------
local LIB, libSel = {}, nil
local skins = {}
local applySkin, animateActor, getSource
local function updateVisualControl(dt)
    if not S.visualControl or not S.visualControlledNPC or not S.visualControlledNPC.Parent then
        return
    end

    local npcModel = S.visualControlledNPC
    local npcRoot = rootOf(npcModel)
    local npcHum = humOf(npcModel)
    if not npcRoot or not npcHum then return end

    local cam = getCam()
    local camCF = cam.CFrame
    local moveVector = S.visualControlMoveVector

    local moveCFrame = CFrame.new(0, 0, 0)
    if moveVector.Z ~= 0 then
        moveCFrame = moveCFrame * CFrame.new(0, 0, -moveVector.Z)
    end
    if moveVector.X ~= 0 then
        moveCFrame = moveCFrame * CFrame.new(-moveVector.X, 0, 0)
    end

    local currentCF = npcRoot.CFrame
    local targetCF = CFrame.new(currentCF.Position) * (camCF - camCF.Position) * moveCFrame

    -- Применяем движение
    local newPos = currentCF.Position + (targetCF.Position - currentCF.Position) * 0.1
    local _, yaw, _ = targetCF:ToOrientation()
    local newRot = CFrame.fromOrientation(0, yaw, 0)
    npcRoot.CFrame = CFrame.new(newPos) * newRot

    -- Применяем прыжок
    if S.visualControlJump then
        npcHum.Jump = true
        S.visualControlJump = false
    end

    -- Обновляем анимацию (если есть)
    local entry = skins[npcModel]
    if entry then
        local speed = (moveVector.Magnitude > 0.1) and (moveVector.Magnitude * 15) or 0
        animateActor(entry, dt, speed, moveVector.Magnitude > 0.1)
    end
end

local function toggleVisualControl()
    S.visualControl = not S.visualControl
    if S.visualControl then
        if not (S.target and S.target.Parent) then
            if not pickNearest() then status("NPC не найдены для управления") S.visualControl = false return end
        end
        S.visualControlledNPC = S.target
        status("Визуальное управление NPC: " .. S.visualControlledNPC.Name .. " (WASD, Space)")
        -- Применяем скин, если его нет, чтобы иметь возможность анимировать
        if not skins[S.visualControlledNPC] then
            local entry = LIB[libSel]
            if entry then
                local src = getSource(entry)
                if src then
                    applySkin(S.visualControlledNPC, src, entry)
                end
            else
                status("Выберите скин в библиотеке для визуального управления")
                S.visualControl = false
                S.visualControlledNPC = nil
                return
            end
        end
        bindSink()
    else
        S.visualControlledNPC = nil
        S.visualControlMoveVector = Vector3.zero
        S.visualControlJump = false
        unbindSink()
        status("Визуальное управление NPC выключено")
    end
    refreshButtons()
end

---------------------------------------------------------------------
-- Атака NPC (визуальная)
---------------------------------------------------------------------
local function attackNPC()
    if not S.visualControlledNPC or not S.visualControlledNPC.Parent then
        status("Выберите NPC для атаки")
        return
    end
    if S.attackCooldown > os.clock() then
        status("Перезарядка атаки")
        return
    end

    local npcModel = S.visualControlledNPC
    local npcRoot = rootOf(npcModel)
    local npcHum = humOf(npcModel)
    if not npcRoot or not npcHum then return end

    local entry = skins[npcModel]
    if entry and entry.attackTr then
        entry.attackTr:Play()
        status("NPC " .. npcModel.Name .. " атакует!")
    elseif entry then
        -- Базовая анимация атаки, если нет ассет-анимации
        entry.fakeAtk = os.clock()
        entry.punchSide = (entry.punchSide == 1) and -1 or 1 -- Чередуем руки
        status("NPC " .. npcModel.Name .. " атакует (базовая анимация)!")
    else
        status("NPC " .. npcModel.Name .. " не имеет анимации атаки")
        return
    end

    -- Визуальные эффекты атаки (например, ударная волна или частицы)
    local attackEffect = Instance.new("Part")
    attackEffect.Name = "AttackEffect"
    attackEffect.Shape = Enum.PartType.Ball
    attackEffect.Size = Vector3.new(3, 3, 3)
    attackEffect.Transparency = 0.7
    attackEffect.Color = Color3.fromRGB(255, 0, 0)
    attackEffect.CanCollide = false
    attackEffect.Anchored = true
    attackEffect.CFrame = npcRoot.CFrame * CFrame.new(0, 0, -5) -- Перед NPC
    attackEffect.Parent = getSkinFolder() -- Используем папку для скинов, чтобы не засорять workspace
    Debris:AddItem(attackEffect, 0.5)

    -- Звук атаки
    local attackSound = Instance.new("Sound")
    attackSound.SoundId = "rbxassetid://104996894" -- Пример ID звука удара
    attackSound.Volume = 0.8
    attackSound.Parent = npcRoot
    attackSound:Play()
    Debris:AddItem(attackSound, 1)

    S.attackCooldown = os.clock() + 1 -- 1 секунда перезарядки
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
    -- syncControl() -- Убрано, так как теперь есть visualControl
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
    -- syncControl() -- Убрано, так как теперь есть visualControl
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
    S.visualControl = false -- Сброс визуального управления
    S.visualControlledNPC = nil
    S.visualControlMoveVector = Vector3.zero
    S.visualControlJump = false
    -- syncControl() -- Убрано
    setFPHidden(false)
    UIS.MouseBehavior = Enum.MouseBehavior.Default
    unbindSink()
    local cam = getCam()
    cam.CameraType = Enum.CameraType.Custom
    local hum = (puppet and puppet.hum) or (lp.Character and lp.Character:FindFirstChildOfClass("Humanoid"))
    if hum then cam.CameraSubject = hum end
    cam.FieldOfView = S.origFov
    status("Режимы выключены")
    refreshButtons()
end

local function setTarget(m)
    S.target = m
    updateNPCHide()
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

-- toggleControl теперь переключает визуальное управление
local function toggleControl()
    toggleVisualControl()
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
---------------------------------------------------------------------
-- Бессмертие (клиентское: работает, если урон считается на клиенте)
---------------------------------------------------------------------
local godConns = {}
local godCharConn
local godHum, godOrigMax
local godParts = {}

local function godRelease()
    for _, c in ipairs(godConns) do c:Disconnect() end
    godConns = {}
    for _, d in ipairs(godParts) do pcall(function() d.CanTouch = true end) end
    godParts = {}
    if godHum and godHum.Parent then
        pcall(function()
            godHum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
            if godOrigMax then
                godHum.MaxHealth = godOrigMax
                godHum.Health = godOrigMax
            end
        end)
    end
    godHum, godOrigMax = nil, nil
end

local function godApply(char)
    godRelease()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    godHum = hum
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") and d.CanTouch then
            pcall(function() d.CanTouch = false end)
            table.insert(godParts, d)
        end
    end
    if hum.MaxHealth ~= math.huge then godOrigMax = hum.MaxHealth end
    pcall(function()
        hum.MaxHealth = math.huge
        hum.Health = math.huge
        hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    end)
    table.insert(godConns, hum.HealthChanged:Connect(function()
        if S.god and hum.Health < hum.MaxHealth then
            pcall(function() hum.Health = hum.MaxHealth end)
        end
    end))
    table.insert(godConns, hum.StateChanged:Connect(function(_, new)
        if S.god and new == Enum.HumanoidStateType.Dead then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end))
end

local function toggleGod(force)
    local want = (force == nil) and (not S.god) or force
    S.god = want
    if godCharConn then godCharConn:Disconnect() godCharConn = nil end
    if want then
        godApply(lp.Character)
        godCharConn = lp.CharacterAdded:Connect(function(c)
            task.wait(0.2)
            if S.god then godApply(c) end
        end)
        status("Бессмертие включено")
    else
        godRelease()
        status("Бессмертие выключено")
    end
    refreshButtons()
end

local function healSelf()
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum.Health = (hum.MaxHealth == math.huge) and math.huge or hum.MaxHealth end)
        status("Здоровье восстановлено")
    end
end

---------------------------------------------------------------------
-- Модели: библиотека, скины, скрытие NPC, подмена игроков
-- (всё только визуально и только на вашем клиенте)
---------------------------------------------------------------------
-- Слоты библиотеки: вставьте ID модели в панели (вкладка «Модели»)
local PRESETS = {"Huggy Wuggy", "Kissy Missy", "Mommy Long Legs", "CatNap"}
local CLIP_FPS = 15      -- частота записи поз (кадров/с) для копирования анимаций
local ARM_DOWN = 1.4   -- насколько (рад.) опускать руки R15, если у источника нет позы/анимации
local LIB_FILE = "CinePanel_library.json"
local rebuildLibList = function() end

local VH = {}               -- визуально скрытые модели
-- skins объявлена выше для ранних обработчиков
local skinFolder
local swapTemplates = {}
local swapPrevHide, swapPrevList = false, false

local function visProps(d)
    if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
        return "Transparency", 1
    elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("Highlight")
        or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
        return "Enabled", false
    else
        return nil, nil -- Добавлено для явного возврата nil
    end
end

local function vhHide(model, who)
    local rec = VH[model]
    if not rec then
        rec = {orig = {}, who = {}}
        local function h(d)
            local prop, hid = visProps(d)
            if prop then
                if rec.orig[d] == nil then rec.orig[d] = {prop, hid, d[prop]} end
                d[prop] = hid
            end
        end
        for _, d in ipairs(model:GetDescendants()) do h(d) end
        rec.conn = model.DescendantAdded:Connect(h)
        VH[model] = rec
    end
    rec.who[who] = true
end

local function vhShow(model, who)
    local rec = VH[model]
    if not rec then return end
    rec.who[who] = nil
    if next(rec.who) then return end
    rec.conn:Disconnect()
    for d, info in pairs(rec.orig) do
        if d.Parent then pcall(function() d[info[1]] = info[3] end) end
    end
    VH[model] = nil
end

local function vhClearAll()
    for m, rec in pairs(VH) do
        rec.conn:Disconnect()
        for d, info in pairs(rec.orig) do
            if d.Parent then pcall(function() d[info[1]] = info[3] end) end
        end
        VH[m] = nil
    end
end

-- клонирование (даже если Archivable = false); возвращает модель с nil-родителем
local function cloneModel(m)
    local touched = {}
    for _, d in ipairs(m:GetDescendants()) do
        if not d.Archivable then
            d.Archivable = true
            touched[#touched + 1] = d
        end
    end
    local wasArch = m.Archivable
    m.Archivable = true
    local ok, c = pcall(function() return m:Clone() end)
    for _, d in ipairs(touched) do pcall(function() d.Archivable = false end) end
    m.Archivable = wasArch
    if not ok or not c then return nil end
    local rec = VH[m]
    if rec then -- вернуть настоящие значения, если оригинал сейчас скрыт нами
        local a, b = m:GetDescendants(), c:GetDescendants()
        if #a == #b then
            for i, d in ipairs(a) do
                local info = rec.orig[d]
                if info then pcall(function() b[i][info[1]] = info[3] end) end
            end
        end
    end
    return c
end

local function loadAssetModel(id)
    local obj
    local ok, res = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
    if ok and type(res) == "table" and res[1] then obj = res[1] end
    if not obj then
        ok, res = pcall(function() return game:GetService("InsertService"):LoadAsset(id) end)
        if ok and res then obj = res end
    end
    if not obj then return nil end
    local rig
    if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
        rig = obj
    else
        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then rig = d break end
        end
        rig = rig or (obj:IsA("Model") and obj) or obj:FindFirstChildWhichIsA("Model", true)
    end
    if rig then rig.Parent = nil end
    return rig
end

-- анимации модели: из скрипта Animate (idle/walk/run)
local function readAnimIds(model)
    local out = {}
    local an = model:FindFirstChild("Animate")
    if an then
        for _, key in ipairs({"idle", "walk", "run", "attack"}) do -- Добавлена "attack"
            local f = an:FindFirstChild(key)
            local a = f and f:FindFirstChildWhichIsA("Animation", true)
            if a and a.AnimationId ~= "" then out[key] = a.AnimationId end
        end
    end
    return out
end

-- какие анимации сейчас реально играют у модели (для NPC без Animate)
local function livePlayingIds(model)
    local host = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
    local animator = host and host:FindFirstChildOfClass("Animator")
    local ids = {}
    if animator then
        for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
            if tr.Animation and tr.Animation.AnimationId ~= "" and tr.WeightCurrent > 0.3 then
                table.insert(ids, {id = tr.Animation.AnimationId, looped = tr.Looped, name = tr.Animation.Name})
            end
        end
    end
    return ids
end

local function enumByValue(enum, v)
    for _, it in ipairs(enum:GetEnumItems()) do
        if it.Value == v then return it end
    end
end

local function origVal(model, d, prop)
    local rec = VH[model]
    local info = rec and rec.orig[d]
    if info and info[1] == prop then return info[3] end
    return d[prop]
end

local function v3(v) return {v.X, v.Y, v.Z} end

-- описание модели в виде таблицы (для сохранения в файл и переноса в другие игры)
local function serialize(model)
    local root = rootOf(model)
    if not root then return nil end
    local rootCF = root.CFrame
    local parts, idx = {}, {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            local e = {
                n = d.Name, sz = v3(d.Size), cf = {rootCF:ToObjectSpace(d.CFrame):GetComponents()},
                col = {d.Color.R, d.Color.G, d.Color.B}, mat = d.Material.Value,
                tr = origVal(model, d, "Transparency"), rf = d.Reflectance,
            }
            if d:IsA("MeshPart") then
                e.mid, e.tid, e.msz = d.MeshId, d.TextureID, v3(d.MeshSize)
                if e.tid == "" then
                    pcall(function() e.tid = d.TextureContent.Uri or "" end)
                end
                if e.mid == "" then
                    pcall(function() e.mid = d.MeshContent.Uri or "" end)
                end
            else
                e.cls = d.ClassName
                if d:IsA("Part") then e.shape = d.Shape.Value end
            end
            for _, c in ipairs(d:GetChildren()) do
                if c:IsA("SpecialMesh") then
                    e.sm = {t = c.MeshType.Value, id = c.MeshId, tx = c.TextureId, sc = v3(c.Scale), of = v3(c.Offset)}
                elseif c:IsA("SurfaceAppearance") then
                    e.sa = {c = c.ColorMap, n = c.NormalMap, m = c.MetalnessMap, r = c.RoughnessMap}
                    pcall(function()
                        if e.sa.c == "" then e.sa.c = c.ColorMapContent.Uri or "" end
                        if e.sa.n == "" then e.sa.n = c.NormalMapContent.Uri or "" end
                        if e.sa.m == "" then e.sa.m = c.MetalnessMapContent.Uri or "" end
                        if e.sa.r == "" then e.sa.r = c.RoughnessMapContent.Uri or "" end
                    end)
                elseif c:IsA("Texture") then
                    e.tx = e.tx or {}
                    table.insert(e.tx, {t = c.Texture, f = c.Face.Value, u = c.StudsPerTileU, v = c.StudsPerTileV,
                        tr = origVal(model, c, "Transparency")})
                elseif c:IsA("Decal") then
                    e.dc = e.dc or {}
                    table.insert(e.dc, {t = c.Texture, f = c.Face.Value, tr = origVal(model, c, "Transparency")})
                end
            end
            parts[#parts + 1] = e
            idx[d] = #parts
        end
    end
    local joints = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("JointInstance") and d.Part0 and d.Part1 and idx[d.Part0] and idx[d.Part1] then
            joints[#joints + 1] = {k = d.ClassName, n = d.Name, a = idx[d.Part0], b = idx[d.Part1],
                c0 = {d.C0:GetComponents()}, c1 = {d.C1:GetComponents()}}
        elseif d:IsA("WeldConstraint") and d.Part0 and d.Part1 and idx[d.Part0] and idx[d.Part1] then
            joints[#joints + 1] = {k = "WeldConstraint", n = d.Name, a = idx[d.Part0], b = idx[d.Part1]}
        end
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local clo = {}
    local function col(x) return {x.R, x.G, x.B} end
    for _, c in ipairs(model:GetChildren()) do
        if c:IsA("Shirt") then clo.shirt = c.ShirtTemplate
        elseif c:IsA("Pants") then clo.pants = c.PantsTemplate
        elseif c:IsA("ShirtGraphic") then clo.gr = c.Graphic
        elseif c:IsA("BodyColors") then
            clo.bc = {col(c.HeadColor3), col(c.TorsoColor3), col(c.LeftArmColor3), col(c.RightArmColor3),
                col(c.LeftLegColor3), col(c.RightLegColor3)}
        elseif c:IsA("CharacterMesh") then
            clo.cm = clo.cm or {}
            table.insert(clo.cm, {b = c.BodyPart.Value, m = c.MeshId, o = c.OverlayTextureId, t = c.BaseTextureId})
        end
    end
    return {name = model.Name, root = idx[root], parts = parts, joints = joints, hip = hum and hum.HipHeight or 0,
        rig = hum and hum.RigType.Value or 1, clo = clo, anim = readAnimIds(model)}
end

-- сборка модели из описания (работает в другой игре, если ассеты доступны)
local function deserialize(desc)
    local model = Instance.new("Model")
    model.Name = desc.name or "Captured"
    local parts, connected = {}, {}
    local unsup = 0
    for i, e in ipairs(desc.parts) do
        local p
        if e.mid and e.mid ~= "" then
            local ok, mp = pcall(Instance.new, "MeshPart")
            if ok and mp then
                local ok2 = pcall(function() mp.MeshId = e.mid end)
                if ok2 and mp.MeshId ~= "" then p = mp else mp:Destroy() end
            end
        end
        if not p then
            local cls = (e.cls == "WedgePart" or e.cls == "CornerWedgePart") and e.cls or "Part"
            if e.cls and e.cls ~= "Part" and e.cls ~= "WedgePart" and e.cls ~= "CornerWedgePart"
                and not (e.mid and e.mid ~= "") then
                unsup = unsup + 1 -- Union/Truss и т.п.: форму скопировать нельзя, будет блок
            end
            p = Instance.new(cls)
            if e.mid and e.mid ~= "" then
                local sm = Instance.new("SpecialMesh")
                sm.MeshType = Enum.MeshType.FileMesh
                sm.MeshId = e.mid
                sm.TextureId = e.tid or ""
                local ms = e.msz or {1, 1, 1}
                local function sc(a, b) return (b and b > 0.001) and (a / b) or 1 end
                sm.Scale = Vector3.new(sc(e.sz[1], ms[1]), sc(e.sz[2], ms[2]), sc(e.sz[3], ms[3]))
                sm.Parent = p
            end
        end
        if p:IsA("MeshPart") and e.tid and e.tid ~= "" then pcall(function() p.TextureID = e.tid end) end
        p.Name = e.n
        p.Anchored, p.CanCollide, p.Massless = false, false, true
        p.Size = Vector3.new(e.sz[1], e.sz[2], e.sz[3])
        p.Color = Color3.new(e.col[1], e.col[2], e.col[3])
        p.Material = enumByValue(Enum.Material, e.mat) or Enum.Material.Plastic
        p.Transparency = e.tr or 0
        p.Reflectance = e.rf or 0
        if e.shape and p.ClassName == "Part" then
            pcall(function() p.Shape = enumByValue(Enum.PartType, e.shape) end)
        end
        if e.sm then
            local sm = Instance.new("SpecialMesh")
            sm.MeshType = enumByValue(Enum.MeshType, e.sm.t) or Enum.MeshType.FileMesh
            if e.sm.id and e.sm.id ~= "" then sm.MeshId = e.sm.id end
            sm.TextureId = e.sm.tx or ""
            sm.Scale = Vector3.new(table.unpack(e.sm.sc))
            sm.Offset = Vector3.new(table.unpack(e.sm.of))
            sm.Parent = p
        end
        for _, dd in ipairs(e.dc or {}) do
            local dc = Instance.new("Decal")
            dc.Texture = dd.t
            dc.Face = enumByValue(Enum.NormalId, dd.f) or Enum.NormalId.Front
            dc.Transparency = dd.tr or 0
            dc.Parent = p
        end
        for _, tt in ipairs(e.tx or {}) do
            local tx = Instance.new("Texture")
            tx.Texture = tt.t
            tx.Face = enumByValue(Enum.NormalId, tt.f) or Enum.NormalId.Front
            tx.StudsPerTileU, tx.StudsPerTileV = tt.u or 2, tt.v or 2
            tx.Transparency = tt.tr or 0
            tx.Parent = p
        end
        if e.sa and p:IsA("MeshPart") then
            pcall(function()
                local sa = Instance.new("SurfaceAppearance")
                sa.ColorMap, sa.NormalMap, sa.MetalnessMap, sa.RoughnessMap = e.sa.c, e.sa.n, e.sa.m, e.sa.r
                sa.Parent = p
            end)
        end
        p.CFrame = CFrame.new(table.unpack(e.cf))
        p.Parent = model
        parts[i] = p
    end
    for _, j in ipairs(desc.joints or {}) do
        local a, b = parts[j.a], parts[j.b]
        if a and b then
            connected[j.a], connected[j.b] = true, true
            local ok, o = pcall(Instance.new, j.k)
            if ok and o then
                if j.k == "WeldConstraint" then
                    o.Part0, o.Part1 = a, b
                else
                    o.Name = j.n
                    o.C0 = CFrame.new(table.unpack(j.c0))
                    o.C1 = CFrame.new(table.unpack(j.c1))
                    o.Part0, o.Part1 = a, b
                end
                o.Parent = b
            end
        end
    end
    local root = parts[desc.root]
    if not root then model:Destroy() return nil end
    model.PrimaryPart = root
    for i, p in ipairs(parts) do
        if p ~= root and not connected[i] then
            local w = Instance.new("WeldConstraint")
            w.Part0, w.Part1 = root, p
            w.Parent = p
        end
    end
    local hum = Instance.new("Humanoid")
    pcall(function() hum.RigType = enumByValue(Enum.HumanoidRigType, desc.rig or 1) or Enum.HumanoidRigType.R15 end)
    hum.HipHeight = desc.hip or 0
    hum.Parent = model
    Instance.new("Animator", hum)
    local clo = desc.clo or {}
    if clo.shirt then local sh = Instance.new("Shirt") sh.ShirtTemplate = clo.shirt sh.Parent = model end
    if clo.pants then local pa = Instance.new("Pants") pa.PantsTemplate = clo.pants pa.Parent = model end
    if clo.gr then local g = Instance.new("ShirtGraphic") g.Graphic = clo.gr g.Parent = model end
    if clo.bc then
        local function c3(t) return Color3.new(t[1], t[2], t[3]) end
        local b = Instance.new("BodyColors")
        b.HeadColor3, b.TorsoColor3 = c3(clo.bc[1]), c3(clo.bc[2])
        b.LeftArmColor3, b.RightArmColor3 = c3(clo.bc[3]), c3(clo.bc[4])
        b.LeftLegColor3, b.RightLegColor3 = c3(clo.bc[5]), c3(clo.bc[6])
        b.Parent = model
    end
    for _, m in ipairs(clo.cm or {}) do
        pcall(function()
            local cm = Instance.new("CharacterMesh")
            cm.BodyPart = enumByValue(Enum.BodyPart, m.b)
            cm.MeshId, cm.OverlayTextureId, cm.BaseTextureId = m.m, m.o, m.t
            cm.Parent = model
        end)
    end
    model:SetAttribute("CineUnsup", unsup)
    model:SetAttribute("CineHip", desc.hip or 0)
    return model
end

-- библиотека: сохранение/загрузка (общий файл для всех игр)
local function saveLib()
    if not writefile then return end
    local t = {}
    for _, e in ipairs(LIB) do
        if e.kind == "capture" then
            if e.desc then t[#t + 1] = {n = e.name, k = "capture", d = e.desc} end
        else
            t[#t + 1] = {n = e.name, k = "asset", id = e.id, an = e.anim, cl = e.clips}
        end
    end
    pcall(function() writefile(LIB_FILE, HttpService:JSONEncode(t)) end)
end

local function loadLib()
    LIB = {}
    if isfile and readfile then
        local okE, ex = pcall(isfile, LIB_FILE)
        if okE and ex then
            local ok, t = pcall(function() return HttpService:JSONDecode(readfile(LIB_FILE)) end)
            if ok and type(t) == "table" then
                for _, e in ipairs(t) do
                    table.insert(LIB, {name = e.n, kind = e.k, id = e.id, desc = e.d, anim = (e.d and e.d.anim) or e.an, clips = (e.d and e.d.clips) or e.cl})
                end
            end
        end
    end
    for _, nm in ipairs(PRESETS) do
        local found = false
        for _, e in ipairs(LIB) do
            if e.name == nm then found = true break end
        end
        if not found then table.insert(LIB, {name = nm, kind = "asset"}) end
    end
end

getSource = function(entry)
    if entry.src and entry.src.Parent == nil then return entry.src end
    if entry.failT and os.clock() - entry.failT < 5 then return nil end
    local src
    if entry.kind == "asset" then
        if not entry.id then
            status("У «" .. entry.name .. "» нет ID — введи ID и нажми «Добавить по ID»")
            entry.failT = os.clock()
            return nil
        end
        src = loadAssetModel(entry.id)
    elseif entry.kind == "capture" and entry.desc then
        local ok, m = pcall(deserialize, entry.desc)
        if ok then src = m end
    end
    if src then
        entry.src = src
        entry.failT = nil
        if not entry.anim or next(entry.anim) == nil then
            local a = readAnimIds(src)
            if next(a) then entry.anim = a end
        end
    else
        entry.failT = os.clock()
        status("Не удалось загрузить: " .. entry.name)
    end
    return src
end

-- скины
local function getSkinFolder()
    if not skinFolder or not skinFolder.Parent then
        skinFolder = Instance.new("Folder")
        skinFolder.Name = "CineSkins"
        skinFolder.Parent = workspace
    end
    return skinFolder
end

local function removeSkin(char)
    local e = skins[char]
    if not e then return end
    skins[char] = nil
    pcall(function() e.skin:Destroy() end)
    vhShow(char, "skin")
end

local function buildSkin(src)
    local skin = cloneModel(src)
    if not skin then return nil end
    local hum = skin:FindFirstChildOfClass("Humanoid")
    local hip = (hum and hum.HipHeight) or skin:GetAttribute("CineHip") or 0
    for _, d in ipairs(skin:GetDescendants()) do
        pcall(function()
            if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
                or d:IsA("ForceField") or d:IsA("Sound") then
                d:Destroy()
            elseif d:IsA("BasePart") then
                d.CanCollide, d.CanQuery, d.CanTouch, d.Massless, d.Anchored = false, false, false, true, false
            end
        end)
    end
    if hum then
        local clothes = skin:FindFirstChildOfClass("Shirt") or skin:FindFirstChildOfClass("Pants")
            or skin:FindFirstChildOfClass("ShirtGraphic") or skin:FindFirstChildOfClass("BodyColors")
            or skin:FindFirstChildOfClass("CharacterMesh")
        if clothes then -- humanoid нужен только для одежды: делаем его инертным
            pcall(function()
                hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
                hum.BreakJointsOnDeath = false
                hum.PlatformStand = true
                hum.EvaluateStateMachine = false
            end)
        else
            hum:Destroy()
        end
    end
    local root = skin:FindFirstChild("HumanoidRootPart") or skin.PrimaryPart or skin:FindFirstChildWhichIsA("BasePart", true)
    if not root then skin:Destroy() return nil end
    root.Anchored = true
    return skin, root, hip
end

local function isIdentity(cf)
    return cf.RightVector:Dot(Vector3.xAxis) > 0.999 and cf.UpVector:Dot(Vector3.yAxis) > 0.999
end

-- проигрывание сохранённых анимаций (idle/walk/run/attack) на скине
local function setupTracks(skin, entry)
    local anim = entry and entry.anim
    if not anim or next(anim) == nil then return nil, nil end
    local host = skin:FindFirstChildOfClass("Humanoid") or skin:FindFirstChildOfClass("AnimationController")
    if not host then
        host = Instance.new("AnimationController")
        host.Parent = skin
    end
    local animator = host:FindFirstChildOfClass("Animator") or Instance.new("Animator", host)
    local tracks, any, attackTr = {}, false, nil
    for _, key in ipairs({"idle", "walk", "run", "attack"}) do
        local id = anim[key]
        if id then
            local a = Instance.new("Animation")
            a.AnimationId = id
            local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
            if ok and tr then
                if key == "attack" then
                    tr.Looped = false
                    pcall(function() tr.Priority = Enum.AnimationPriority.Action end)
                    attackTr = tr
                else
                    tr.Looped = true
                    tracks[key] = tr
                    any = true
                end
            end
        end
    end
    return (any and tracks or nil), attackTr
end

local diagInfo = {skin = "", mesh = "", tex = "", fixed = 0}
local function pushDiag()
    local txt = diagInfo.skin .. (diagInfo.mesh ~= "" and (" | " .. diagInfo.mesh) or "")
        .. (diagInfo.tex ~= "" and (" | " .. diagInfo.tex) or "")
    status(txt)
    print("[CinePanel] " .. txt)
end

local ContentProvider = game:GetService("ContentProvider")
local function digits(x) return tostring(x):match("%d+") end

-- если меш закрыт для этой игры, показываем блок того же размера и цвета
local function patchFailedMeshes(skin, label)
    task.spawn(function()
        local total, failed, pending = 0, 0, 0
        for _, d in ipairs(skin:GetDescendants()) do
            if (d:IsA("MeshPart") or d:IsA("SpecialMesh")) and d.MeshId ~= "" then
                total = total + 1
                pending = pending + 1
                task.spawn(function()
                    local bad = false
                    local want = digits(d.MeshId)
                    pcall(function()
                        ContentProvider:PreloadAsync({d}, function(id, st)
                            if digits(id) == want and (st == Enum.AssetFetchStatus.Failure
                                or st == Enum.AssetFetchStatus.TimedOut) then
                                bad = true
                            end
                        end)
                    end)
                    local part = d:IsA("MeshPart") and d or d.Parent
                    if bad and part and part.Parent and not part:FindFirstChild("CinePlaceholder") then
                        failed = failed + 1
                        local box = Instance.new("BoxHandleAdornment")
                        box.Name = "CinePlaceholder"
                        box.Adornee = part
                        box.Size = part.Size
                        box.Color3 = part.Color
                        box.ZIndex = 0
                        box.AlwaysOnTop = false
                        box.Transparency = 0
                        box.Parent = part
                    end
                    pending = pending - 1
                end)
            end
        end
        local t0 = os.clock()
        while pending > 0 and os.clock() - t0 < 15 do task.wait(0.2) end
        if total > 0 then
            diagInfo.mesh = "меши " .. total .. "/сбой " .. failed
            pushDiag()
        end
    end)
end

-- проверка и учёт текстур (TextureID / SurfaceAppearance / декали)
local function checkTextures(skin)
    task.spawn(function()
        local tid, sa, deco, empty, failed, pending = 0, 0, 0, 0, 0, 0
        local function probe(inst)
            pending = pending + 1
            task.spawn(function()
                local bad = false
                pcall(function()
                    ContentProvider:PreloadAsync({inst}, function(_, st)
                        if st == Enum.AssetFetchStatus.Failure or st == Enum.AssetFetchStatus.TimedOut then bad = true end
                    end)
                end)
                if bad then failed = failed + 1 end
                pending = pending - 1
            end)
        end
        for _, d in ipairs(skin:GetDescendants()) do
            if d:IsA("MeshPart") then
                local s1 = d:FindFirstChildOfClass("SurfaceAppearance")
                if d.TextureID ~= "" then tid = tid + 1 probe(d) end
                if s1 then sa = sa + 1 probe(s1) end
                if d.TextureID == "" and not s1 then empty = empty + 1 end
            elseif d:IsA("Decal") then
                deco = deco + 1
                probe(d)
            end
        end
        local t0 = os.clock()
        while pending > 0 and os.clock() - t0 < 15 do task.wait(0.2) end
        diagInfo.tex = string.format("текстуры: TID %d, SA %d, декали %d, без текстуры %d, сбой %d, восст. %d, заглушек %d",
            tid, sa, deco, empty, failed, diagInfo.fixed, skin:GetAttribute("CineUnsup") or 0)
        pushDiag()
    end)
end

-- если в копии потерялись текстуры/цвета, берём их с живого оригинала (пока он есть в мире)
local function syncVisuals(skin, orig)
    if not (orig and orig.Parent) then return 0 end
    local function key(counter, p)
        counter[p.Name] = (counter[p.Name] or 0) + 1
        return p.Name .. "#" .. counter[p.Name]
    end
    local map, cnt = {}, {}
    for _, d in ipairs(orig:GetDescendants()) do
        if d:IsA("BasePart") then map[key(cnt, d)] = d end
    end
    local fixed = 0
    cnt = {}
    local function cloneOf(inst)
        local was = inst.Archivable
        inst.Archivable = true
        local ok, c = pcall(function() return inst:Clone() end)
        inst.Archivable = was
        return ok and c or nil
    end
    for _, d in ipairs(skin:GetDescendants()) do
        if d:IsA("BasePart") then
            local o = map[key(cnt, d)]
            if o then
                pcall(function()
                    if d:IsA("MeshPart") and o:IsA("MeshPart") and d.TextureID == "" and o.TextureID ~= "" then
                        d.TextureID = o.TextureID
                        fixed = fixed + 1
                    end
                    if not d:FindFirstChildOfClass("SurfaceAppearance") then
                        local sa = o:FindFirstChildOfClass("SurfaceAppearance")
                        local c = sa and cloneOf(sa)
                        if c then c.Parent = d fixed = fixed + 1 end
                    end
                    local nd, no = 0, 0
                    for _, c in ipairs(d:GetChildren()) do if c:IsA("Decal") then nd = nd + 1 end end
                    for _, c in ipairs(o:GetChildren()) do if c:IsA("Decal") then no = no + 1 end end
                    if no > nd then
                        for _, c in ipairs(d:GetChildren()) do if c:IsA("Decal") then c:Destroy() end end
                        for _, c in ipairs(o:GetChildren()) do
                            if c:IsA("Decal") then
                                local cc = cloneOf(c)
                                if cc then cc.Parent = d fixed = fixed + 1 end
                            end
                        end
                    end
                    d.Color, d.Material, d.Reflectance = o.Color, o.Material, o.Reflectance
                    pcall(function() d.MaterialVariant = o.MaterialVariant end)
                end)
            end
        end
    end
    return fixed
end

-- руки вниз для любого рига: считаем поворот в суставе по геометрии
local function isArmJoint(m)
    local n = string.lower(m.Name .. " " .. (m.Part1 and m.Part1.Name or ""))
    if n:find("fore") or n:find("lower") or n:find("hand") or n:find("elbow") or n:find("wrist")
        or n:find("finger") or n:find("armor") then
        return false
    end
    return n:find("shoulder") ~= nil or n:find("arm") ~= nil
end

local function armToward(m, target)
    local p0, p1 = m.Part0, m.Part1
    if not (p0 and p1) then return nil end
    local F = p0.CFrame * m.C0
    local J = F.Position
    local v = (F * m.C1:Inverse()).Position - J
    if v.Magnitude < 0.05 then return nil end
    local vu = v.Unit
    local d = vu:Dot(target)
    if d > 0.9 then return CFrame.new() end -- уже направлена туда
    local axis = vu:Cross(target)
    if axis.Magnitude < 1e-4 then return nil end
    local ang = math.acos(math.clamp(d, -1, 1)) * 0.95
    local Tj = CFrame.new(J) * CFrame.fromAxisAngle(axis.Unit, ang) * CFrame.new(-J)
    return F:Inverse() * Tj * F
end

local function limbSide(m, idx)
    local n = string.lower(m.Name .. " " .. (m.Part1 and m.Part1.Name or ""))
    if n:find("right") then return 1 end
    if n:find("left") then return -1 end
    return (idx % 2 == 0) and 1 or -1
end

-- руки: {сустав, поза «вниз», поза «вперёд (удар)», сторона}
local function buildArms(model, root)
    local arms, idx = {}, 0
    local down = -root.CFrame.UpVector
    local fwd = (root.CFrame.LookVector * 0.9 + root.CFrame.UpVector * 0.1).Unit
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Motor6D") and isArmJoint(d) then
            idx = idx + 1
            arms[#arms + 1] = {d, armToward(d, down), armToward(d, fwd), limbSide(d, idx)}
        end
    end
    return arms
end

local function limbKind(m)
    if isArmJoint(m) then return "arm" end
    local n = string.lower(m.Name .. " " .. (m.Part1 and m.Part1.Name or ""))
    if n:find("lower") or n:find("knee") or n:find("foot") or n:find("ankle") or n:find("toe")
        or n:find("shin") or n:find("calf") or n:find("armor") then
        return nil
    end
    if n:find("hip") or n:find("thigh") or n:find("leg") then return "leg" end
    return nil
end

-- конечности для базовой (процедурной) анимации ходьбы
local function buildLimbs(model, root)
    local list, cnt = {}, {arm = 0, leg = 0}
    local axisW = root.CFrame.RightVector
    local down = -root.CFrame.UpVector
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Motor6D") and d.Part0 and d.Part1 then
            local kind = limbKind(d)
            if kind then
                cnt[kind] = cnt[kind] + 1
                local F = d.Part0.CFrame * d.C0
                list[#list + 1] = {m = d, kind = kind, side = limbSide(d, cnt[kind]),
                    axis = F:VectorToObjectSpace(axisW), base = (kind == "arm") and armToward(d, down) or nil}
            end
        end
    end
    return list
end

-- записанные «клипы» движения суставов (работают в любой игре, не зависят от прав на анимации)
local function decodeClips(raw)
    if not raw or not raw.keys then return nil end
    local out = {keys = raw.keys, keyIndex = {}}
    for j, k in ipairs(raw.keys) do out.keyIndex[k] = j end
    local any = false
    for _, st in ipairs({"idle", "walk", "run", "attack"}) do
        local c = raw[st]
        if c and c.f and #c.f > 1 then
            local frames = {}
            for fi, fr in ipairs(c.f) do
                local row = {}
                for j = 1, #raw.keys do
                    local b = (j - 1) * 6
                    row[j] = CFrame.new(fr[b + 1], fr[b + 2], fr[b + 3])
                        * CFrame.fromEulerAnglesYXZ(fr[b + 4], fr[b + 5], fr[b + 6])
                end
                frames[fi] = row
            end
            out[st] = {n = #frames, len = #frames / CLIP_FPS, sp = c.sp, frames = frames}
            any = true
        end
    end
    return any and out or nil
end

local function entryClips(entry)
    if not (entry and entry.clips) then return nil end
    if entry._dec == nil then
        local ok, r = pcall(decodeClips, entry.clips)
        entry._dec = (ok and r) or false
    end
    return entry._dec or nil
end

local function buildClipMotors(model, dec)
    local list, cnt = {}, {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Motor6D") then
            cnt[d.Name] = (cnt[d.Name] or 0) + 1
            local j = dec.keyIndex[d.Name .. "#" .. cnt[d.Name]]
            if j then list[#list + 1] = {d, j} end
        end
    end
    return list
end

local function applyClip(e, c, t, loop)
    local n = c.n
    local pos = t * CLIP_FPS
    local i = math.floor(pos)
    local a = pos - i
    local ia, ib
    if loop then
        ia, ib = i % n + 1, (i + 1) % n + 1
    else
        ia, ib = math.min(i + 1, n), math.min(i + 2, n)
    end
    local fa, fb = c.frames[ia], c.frames[ib]
    for _, pr in ipairs(e.cm) do
        local m, j = pr[1], pr[2]
        local x, y = fa[j], fb[j]
        if x and y and m.Parent then m.Transform = x:Lerp(y, a) end
    end
end

-- единая логика анимации: клипы -> анимации-ассеты; true, если что-то проиграно
animateActor = function(e, dt, sp, hint)
    e.sm = (e.sm or sp) * 0.7 + sp * 0.3
    if e.moving then
        if e.sm < 1.2 and not hint then e.moving = false end   -- гистерезис: без дёрганья стоя
    elseif e.sm > 2.5 or hint then
        e.moving = true
    end
    local want = "idle"
    if e.moving then want = (e.sm > 18) and "run" or "walk" end
    local useRecorded = not (S.basicAnim and e.limbs and #e.limbs > 0)

    local cl = e.clips
    if useRecorded and cl and e.cm and #e.cm > 0 then
        if e.atkT0 and cl.attack then
            local t = os.clock() - e.atkT0
            if t < cl.attack.len then
                applyClip(e, cl.attack, t, false)
                return true
            end
            e.atkT0 = nil
        end
        local order = (want == "run" and {"run", "walk", "idle"}) or (want == "walk" and {"walk", "run", "idle"}) or {"idle"}
        local c
        for _, k in ipairs(order) do
            if cl[k] then c = cl[k] break end
        end
        if c then
            local scale = 1
            if want ~= "idle" and c.sp and c.sp > 0.5 then scale = math.clamp(e.sm / c.sp, 0.5, 2) end
            e.ct = (e.ct or 0) + dt * scale
            applyClip(e, c, e.ct, true)
            return true
        end
    end

    if e.tracks then
        if os.clock() - e.t0 > 3 then -- ассеты анимаций не загрузились -> запасной вариант
            local ok = false
            for _, tr in pairs(e.tracks) do
                if tr.Length > 0 then ok = true end
            end
            if not ok then e.tracks, e.motors = nil, (e.fb or {}) end
        end
    end
    if useRecorded and e.tracks then
        local w = want
        if not e.tracks[w] then
            w = (w == "run" and e.tracks.walk and "walk") or (w == "walk" and e.tracks.run and "run")
                or (e.tracks.idle and "idle") or nil
        end
        if w ~= e.state then
            for k, tr in pairs(e.tracks) do
                if k ~= w and tr.IsPlaying then tr:Stop(0.2) end
            end
            if w then e.tracks[w]:Play(0.2) end
            e.state = w
        end
        if w and w ~= "idle" then
            pcall(function() e.tracks[w]:AdjustSpeed(math.clamp(e.sm / 14, 0.4, 2.5)) end)
        end
        return true
    end
    -- базовая анимация ходьбы: машем ногами и руками (работает для любой модели)
    if e.limbs and #e.limbs > 0 and (e.procedural or S.basicAnim) then
        if e.tracks then
            for _, tr in pairs(e.tracks) do
                if tr.IsPlaying then tr:Stop(0.1) end
            end
            e.state = nil
        end
        local target = e.moving and math.clamp(e.sm / 16, 0.35, 1) or 0
        e.amp = (e.amp or 0) + (target - (e.amp or 0)) * math.min(dt * 8, 1)
        e.wp = (e.wp or 0) + dt * (4 + 8 * e.amp)
        local sn = math.sin(e.wp)
        for _, l in ipairs(e.limbs) do
            if l.m.Parent then
                local sign = l.side * (l.kind == "leg" and 1 or -1)
                local amp = (l.kind == "leg" and 0.75 or 0.55) * e.amp
                local rot = CFrame.fromAxisAngle(l.axis, sign * amp * sn)
                l.m.Transform = l.base and (rot * l.base) or rot
            end
        end
        return true
    end
    return false
end

-- удар руками (базовая анимация атаки): бьёт рука стороны e.punchSide, тело подаётся вперёд
local function applyFakeAttack(e)
    local u = (os.clock() - e.fakeAtk) / 0.38
    if u >= 1 then e.fakeAtk = nil return end
    local s = math.sin(math.pi * u)
    for _, a in ipairs(e.arms or {}) do
        local m, down, fwd, side = a[1], a[2], a[3], a[4]
        if m.Parent and fwd and (not side or side == (e.punchSide or 1)) then
            m.Transform = (down or CFrame.new()):Lerp(fwd, s)
        end
    end
end

applySkin = function(char, src, entry)
    removeSkin(char)
    diagInfo.mesh, diagInfo.tex, diagInfo.fixed = "", "", 0
    local origRoot = char:FindFirstChild("HumanoidRootPart") or rootOf(char)
    if not origRoot then return false end
    local skin, root, hip = buildSkin(src)
    if not skin then return false end
    skin.Name = "CineSkin"
    skin.Parent = getSkinFolder()
    if entry and entry.orig then diagInfo.fixed = syncVisuals(skin, entry.orig) end
    if entry and (entry.kind == "capture" or entry.kind == "asset") then
        patchFailedMeshes(skin, entry.name)
        checkTextures(skin)
    end
    for _, d in ipairs(skin:GetDescendants()) do
        pcall(function()
            if d:IsA("BasePart") and d ~= root and d.AssemblyRootPart ~= root.AssemblyRootPart then
                local w = Instance.new("WeldConstraint")
                w.Part0, w.Part1 = root, d
                w.Parent = d
            end
        end)
    end
    local origHum = char:FindFirstChildOfClass("Humanoid")
    local origHip = origHum and origHum.HipHeight or 0
    local offY = (hip + root.Size.Y / 2) - (origHip + origRoot.Size.Y / 2)
    pcall(function()
        skin.PrimaryPart = root
        skin:PivotTo(origRoot.CFrame * CFrame.new(0, offY, 0))
    end)
    local origMotors, pairsList = {}, {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Motor6D") then origMotors[d.Name] = d end
    end
    local arms = buildArms(skin, root)
    local armDown = {}
    for _, a in ipairs(arms) do armDown[a[1]] = a[2] end
    for _, d in ipairs(skin:GetDescendants()) do
        if d:IsA("Motor6D") then
            local o = origMotors[d.Name]
            local sg = armDown[d]
            if o or sg then pairsList[#pairsList + 1] = {d, o, sg} end
        end
    end
    local matched = 0
    for _, pr in ipairs(pairsList) do
        if pr[2] then matched = matched + 1 end
    end

    -- Новая логика для визуального управления NPC
    local newEntry = {
        skin = skin,
        root = root,
        orig = char,
        origRoot = origRoot,
        origHum = origHum,
        pairs = pairsList,
        arms = arms,
        limbs = buildLimbs(skin, root),
        sm = 0, ct = 0, amp = 0, wp = 0,
        clips = entryClips(entry),
        cm = buildClipMotors(skin, entryClips(entry)),
        t0 = os.clock(),
    }
    newEntry.tracks, newEntry.attackTr = setupTracks(skin, entry)
    skins[char] = newEntry
    vhHide(char, "skin")
    diagInfo.skin = "Скин: " .. entry.name .. " (" .. matched .. " суставов)"
    pushDiag()
    return true
end

-- Обновление скинов и визуального управления
local function updateSkins(dt)
    for char, e in pairs(skins) do
        if not char.Parent or not e.skin.Parent then
            removeSkin(char)
            continue
        end
        local origRoot = e.origRoot
        if not origRoot or not origRoot.Parent then
            removeSkin(char)
            continue
        end

        -- Обновление позиции скина
        local origHum = e.origHum
        local origHip = origHum and origHum.HipHeight or 0
        local skinHum = e.skin:FindFirstChildOfClass("Humanoid")
        local skinHip = (skinHum and skinHum.HipHeight) or e.skin:GetAttribute("CineHip") or 0
        local offY = (skinHip + e.root.Size.Y / 2) - (origHip + origRoot.Size.Y / 2)
        e.skin:PivotTo(origRoot.CFrame * CFrame.new(0, offY, 0))

        -- Анимация скина
        local speed = origHum and origHum.WalkSpeed or 0
        local hint = false
        if char == S.visualControlledNPC and S.visualControl then
            speed = S.visualControlMoveVector.Magnitude * 15 -- Скорость для визуального управления
            hint = S.visualControlMoveVector.Magnitude > 0.1
        end
        animateActor(e, dt, speed, hint)

        -- Базовая анимация атаки
        if e.fakeAtk then applyFakeAttack(e) end

        -- Синхронизация суставов
        for _, pr in ipairs(e.pairs) do
            local d, o, sg = pr[1], pr[2], pr[3]
            if d.Parent then
                if o and o.Parent then
                    d.Transform = o.Transform
                elseif sg then
                    d.Transform = sg
                end
            end
        end
    end
end

---------------------------------------------------------------------
-- RenderStep
---------------------------------------------------------------------
local function update(dt)
    local cam = getCam()
    local myChar = lp.Character
    local myRoot = myRootPart()

    -- Обновление визуального управления NPC
    updateVisualControl(dt)

    -- Обновление скинов
    updateSkins(dt)

    -- Freecam
    if S.mode == "free" then
        cam.CameraType = Enum.CameraType.Scriptable
        local move = Vector3.zero
        local speed = S.speed
        if UIS:IsKeyDown(K.LeftShift) then speed = speed * 2.5 end
        if UIS:IsKeyDown(K.LeftControl) then speed = speed * 0.4 end
        if UIS:IsKeyDown(K.W) then move = move + Vector3.new(0, 0, -1) end
        if UIS:IsKeyDown(K.S) then move = move + Vector3.new(0, 0, 1) end
        if UIS:IsKeyDown(K.A) then move = move + Vector3.new(-1, 0, 0) end
        if UIS:IsKeyDown(K.D) then move = move + Vector3.new(1, 0, 0) end
        if UIS:IsKeyDown(K.Q) then move = move + Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(K.E) then move = move + Vector3.new(0, -1, 0) end
        if move.Magnitude > 0.01 then move = move.Unit end
        local cf = CFrame.fromOrientation(S.fpitch, S.fyaw, 0)
        S.fpos = S.fpos + cf:VectorToWorldSpace(move) * speed * dt
        if S.lock and S.target and S.target.Parent then
            local r = rootOf(S.target)
            if r then
                cam.CFrame = CFrame.lookAt(S.fpos, r.Position)
                S.fpitch, S.fyaw = cam.CFrame:ToOrientation()
            end
        else
            cam.CFrame = CFrame.new(S.fpos) * CFrame.fromOrientation(S.fpitch, S.fyaw, 0)
        end
    end

    -- Spectate
    if S.mode == "spec" and S.target and S.target.Parent then
        cam.CameraType = Enum.CameraType.Scriptable
        local r = rootOf(S.target)
        if not r then exitAll() return end
        if S.view == "first" then
            local head = headOf(S.target)
            cam.CFrame = head.CFrame
        else
            local targetPos = r.CFrame.Position
            local look = CFrame.fromOrientation(S.pitch, S.yaw, 0)
            local rayOrigin = targetPos + look.LookVector * S.dist
            local rayDir = (targetPos - rayOrigin).Unit
            local ray = Ray.new(rayOrigin, rayDir * S.dist)
            local hit, pos = workspace:FindPartOnRayWithIgnoreList(ray, {S.target, lp.Character, getSkinFolder()}, false, true)
            if hit then
                S.dist = (pos - targetPos).Magnitude - 1
                if S.dist < 1 then S.dist = 1 end
            end
            cam.CFrame = CFrame.new(targetPos) * look:Inverse() * CFrame.new(0, 0, S.dist)
        end
    end

    -- FOV
    if cam.FieldOfView ~= S.fov then
        cam.FieldOfView = S.fov
    end

    -- Tweening
    if S.tween then
        S.tween.t = S.tween.t + dt
        local alpha = math.min(S.tween.t / S.tween.dur, 1)
        cam.CFrame = S.tween.from:Lerp(S.tween.to, alpha)
        S.fov = S.tween.fov0 + (S.tween.fov1 - S.tween.fov0) * alpha
        if alpha >= 1 then
            S.tween = nil
            setFree(cam.CFrame)
        end
    end
end

local function onInput(input, gp)
    if gp or typing() then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if S.rmb then
            if S.mode == "free" then
                S.fyaw = S.fyaw - input.Delta.X * 0.005
                S.fpitch = math.clamp(S.fpitch - input.Delta.Y * 0.005, -math.pi/2, math.pi/2)
            elseif S.mode == "spec" then
                S.yaw = S.yaw - input.Delta.X * 0.005
                S.pitch = math.clamp(S.pitch - input.Delta.Y * 0.005, -math.pi/2, math.pi/2)
            end
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        S.rmb = (input.UserInputState == Enum.UserInputState.Begin)
        UIS.MouseBehavior = S.rmb and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
    elseif input.UserInputType == Enum.UserInputType.MouseWheel then
        if S.mode == "spec" then
            S.dist = math.clamp(S.dist - input.Position.Z * 2, 1, 100)
        elseif S.mode == "free" then
            S.speed = math.clamp(S.speed + input.Position.Z * 5, 1, 500)
            status("Скорость Freecam: " .. math.floor(S.speed))
        end
    elseif input.UserInputType == Enum.UserInputType.Keyboard then
        if input.UserInputState == Enum.UserInputState.Begin then
            if S.visualControl and S.visualControlledNPC then
                if input.KeyCode == K.W then S.visualControlMoveVector = S.visualControlMoveVector + Vector3.new(0, 0, 1)
                elseif input.KeyCode == K.S then S.visualControlMoveVector = S.visualControlMoveVector + Vector3.new(0, 0, -1)
                elseif input.KeyCode == K.A then S.visualControlMoveVector = S.visualControlMoveVector + Vector3.new(1, 0, 0)
                elseif input.KeyCode == K.D then S.visualControlMoveVector = S.visualControlMoveVector + Vector3.new(-1, 0, 0)
                elseif input.KeyCode == K.Space then S.visualControlJump = true
                end
            end
        elseif input.UserInputState == Enum.UserInputState.End then
            if S.visualControl and S.visualControlledNPC then
                if input.KeyCode == K.W then S.visualControlMoveVector = S.visualControlMoveVector - Vector3.new(0, 0, 1)
                elseif input.KeyCode == K.S then S.visualControlMoveVector = S.visualControlMoveVector - Vector3.new(0, 0, -1)
                elseif input.KeyCode == K.A then S.visualControlMoveVector = S.visualControlMoveVector - Vector3.new(1, 0, 0)
                elseif input.KeyCode == K.D then S.visualControlMoveVector = S.visualControlMoveVector - Vector3.new(-1, 0, 0)
                end
            end
        end
    end
end

local function onKey(actionName, inputState, inputObject)
    if inputState == Enum.UserInputState.Begin then
        if actionName == "FovDown" then
            S.fov = math.max(10, S.fov - 5)
            status("FOV: " .. S.fov)
        elseif actionName == "FovUp" then
            S.fov = math.min(120, S.fov + 5)
            status("FOV: " .. S.fov)
        elseif actionName == "Freecam" then enterFree()
        elseif actionName == "Spectate" then enterSpec()
        elseif actionName == "FirstPerson" then
            if S.mode == "spec" then
                S.view = (S.view == "first") and "third" or "first"
                setFPHidden(S.view == "first")
                status("Вид: " .. S.view)
            end
        elseif actionName == "CameraLock" then toggleLock()
        elseif actionName == "Control" then toggleControl()
        elseif actionName == "PrevNPC" then cycle(-1)
        elseif actionName == "NextNPC" then cycle(1)
        elseif actionName == "PlaceCam" then addCam()
        elseif actionName == "DayNight" then toggleDayNight()
        elseif actionName == "HidePlayers" then toggleHide()
        elseif actionName == "God" then toggleGod()
        elseif actionName == "Exit" then exitAll()
        elseif actionName == "Attack" then attackNPC() -- Обработка новой клавиши атаки
        end
        refreshButtons()
    end
    return Enum.ContextActionResult.Pass
end

local function bindKeys()
    for name, key in pairs(KEYS) do
        CAS:BindAction(name, onKey, false, key)
    end
end

local function unbindKeys()
    for name, _ in pairs(KEYS) do
        CAS:UnbindAction(name)
    end
end

---------------------------------------------------------------------
-- Инициализация
---------------------------------------------------------------------
local function init()
    loadCams()
    loadLib()
    refreshMarkers()
    bindKeys()
    connect(UIS.InputBegan, onInput)
    connect(UIS.InputEnded, onInput)
    connect(RunService.RenderStepped, update)

    genv.__CinePanelCleanup = function()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        unbindKeys()
        clearHide()
        godRelease()
        vhClearAll()
        for _, e in pairs(skins) do pcall(function() e.skin:Destroy() end) end
        skins = {}
        if skinFolder then pcall(function() skinFolder:Destroy() end) end
        if markerFolder then pcall(function() markerFolder:Destroy() end) end
        if S.timeLock then resetTime() end
        exitAll()
        pcall(function() sethiddenproperty(lp, "SimulationRadius", 0) end)
        genv.__CinePanelCleanup = nil
    end

    status("CinePanel загружен. F1 для Freecam, F2 для Spectate.")
end

xpcall(init, function(err)
    warn("CinePanel: " .. err)
    status("Ошибка загрузки CinePanel: " .. err)
end)
