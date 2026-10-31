local __cineOk, __cineErr = xpcall(function()
do
local RS = game:GetService("RunService")
for _, n in ipairs({"CinePanel", "CineSkins", "CineShake", "CineJoy"}) do
pcall(function() RS:UnbindFromRenderStep(n) end)
end
pcall(function() game:GetService("ContextActionService"):UnbindAction("CineSink") end)
local roots = {}
pcall(function() if gethui then table.insert(roots, gethui()) end end)
pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
pcall(function() table.insert(roots, game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")) end)
for _, r in ipairs(roots) do
for _, nm in ipairs({"CinePanel", "CineKill", "CineBlood", "CineSprint"}) do
pcall(function()
for _ = 1, 10 do
local o = r:FindFirstChild(nm)
if not o then break end
o:Destroy()
end
end)
end
end
pcall(function()
for _, nm in ipairs({"CineSkins", "CineFX", "CineSkinsDummy"}) do
local o = workspace:FindFirstChild(nm)
if o then o:Destroy() end
end
end)
end
-- ждём загрузку игры (в некоторых играх запуск во время загрузки приводил к сбою)
if not game:IsLoaded() then
local t0 = os.clock()
repeat task.wait(0.1) until game:IsLoaded() or os.clock() - t0 > 15
end
local G = {}   -- сюда вынесены функции (у Luau лимит ~200 локальных переменных на функцию)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer
do
local t0 = os.clock()
while not lp and os.clock() - t0 < 10 do
task.wait(0.1)
lp = Players.LocalPlayer
end
end
local K = Enum.KeyCode
local function getCam()
local c = workspace.CurrentCamera
if c then return c end
if not G.dummyCam then G.dummyCam = Instance.new("Camera") end -- камеры нет (бывает в некоторых играх) — запасная
return G.dummyCam
end
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
CopySounds  = K.Insert,
KillFront   = K.X,
KillNearest = K.N,
KillSelected = K.PageDown,
Attack      = K.Z,
Puppet      = K.P,
SelfView    = K.Backquote,
ReviveAll   = K.PageUp,
Exit        = K.Backspace,
}
local KEY_LABELS = {
{"TogglePanel", "Показать/скрыть панель"},
{"Freecam", "Freecam вкл/выкл"},
{"Spectate", "Наблюдение за NPC вкл/выкл"},
{"FirstPerson", "Вид от 1-го / 3-го лица"},
{"CameraLock", "Camera Lock на NPC"},
{"Control", "Управление NPC (визуальная копия)"},
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
{"CopySounds", "Скопировать звуки выбранного NPC"},
{"KillFront", "KILL: убить NPC перед тобой"},
{"KillNearest", "KILL: убить ближайшего NPC"},
{"KillSelected", "KILL: убить выбранного NPC"},
{"Attack", "Атака (замах + удар перед собой)"},
{"Puppet", "Кукла (неуязвимость от NPC)"},
{"SelfView", "3-е лицо за себя / куклу"},
{"ReviveAll", "Вернуть всех"},
{"Exit", "Выйти из всех режимов"},
}
local genv = (getgenv and getgenv()) or _G
if genv.__CinePanelCleanup then pcall(genv.__CinePanelCleanup) end
local conns = {}
local function connect(sig, fn)
local c = sig:Connect(fn)
table.insert(conns, c)
return c
end
local S = {
mode = "none",          -- none | free | spec | self
target = nil,
view = "third",         -- third | first
lock = false,
control = false,
controlled = nil,
yaw = 0, pitch = -0.25, dist = 12,
lyaw = 0, lpitch = 0,
syaw = 0, spitch = -0.25, sdist = 10,   -- 3-е лицо за себя/куклу
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
sfx = true,
ctlMul = 1,   -- множитель скорости управляемого NPC
}
local npcs = {}
local npcCtl = nil          -- визуальное управление настоящим NPC (копия, оригинал скрыт только у тебя)
local puppet = nil          -- «кукла»: локальная копия персонажа (см. togglePuppet)
local function myRootPart()   -- корень того, кем ты сейчас управляешь
if npcCtl and npcCtl.root and npcCtl.root.Parent then return npcCtl.root end
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
if #out >= 150 then break end
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
local sinkKeys = {K.W, K.A, K.S, K.D, K.Space, K.Q, K.E,
K.One, K.Two, K.Three, K.Four, K.Five, K.Six, K.Seven, K.Eight, K.Nine}
local function bindSink()
CAS:BindActionAtPriority("CineSink", function() return Enum.ContextActionResult.Sink end,
false, Enum.ContextActionPriority.High.Value + 1, table.unpack(sinkKeys))
end
local function unbindSink() pcall(function() CAS:UnbindAction("CineSink") end) end
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
local function activate()
local cam = getCam()
S.origFov = cam.FieldOfView
S.fov = S.origFov
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
bindSink()
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
bindSink()
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
local hum = (npcCtl and npcCtl.hum) or (puppet and puppet.hum) or (lp.Character and lp.Character:FindFirstChildOfClass("Humanoid"))
if hum then cam.CameraSubject = hum end
cam.FieldOfView = S.origFov
status("Режимы выключены")
refreshButtons()
end
-- 3-е лицо за себя (или за куклу, если она включена). NPC не выбираются, управление — обычное (WASD)
function G.enterSelf()
local r = myRootPart()
if not r then status("Нет персонажа") return end
if S.mode == "none" then activate() end
S.mode = "self"
S.control = false
S.lock = false
S.tween = nil
syncControl()
setFPHidden(false)
unbindSink()
local look = r.CFrame.LookVector
local flat = Vector3.new(look.X, 0, look.Z)
if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
local _, y = CFrame.lookAt(Vector3.zero, flat):ToOrientation()
S.syaw, S.spitch = y, -0.25
status((puppet and "3-е лицо: кукла" or "3-е лицо: ты") .. " (ПКМ — поворот, колесо — дистанция)")
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
local function toggleControl() G.toggleNpcCtl() end
function G.camsFile() return "CinePanel_" .. tostring(game.PlaceId) .. ".json" end
local function saveCams()
if not writefile then return end
local t = {}
for _, c in ipairs(S.cams) do
table.insert(t, {n = c.name, c = {c.cf:GetComponents()}, f = c.fov})
end
pcall(function() writefile(G.camsFile(), HttpService:JSONEncode(t)) end)
end
local function loadCams()
if not (isfile and readfile) then return end
local okExists, exists = pcall(isfile, G.camsFile())
if not (okExists and exists) then return end
local ok, t = pcall(function() return HttpService:JSONDecode(readfile(G.camsFile())) end)
if ok and type(t) == "table" then
for _, e in ipairs(t) do
S.camId = S.camId + 1
table.insert(S.cams, {name = e.n, cf = CFrame.new(table.unpack(e.c)), fov = e.f})
end
end
end
local markerFolder
function G.refreshMarkers()
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
G.refreshMarkers()
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
local hiddenData = {}
local hideConns = {}
function G.hideInst(d)
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
function G.hideChar(char)
for _, d in ipairs(char:GetDescendants()) do G.hideInst(d) end
table.insert(hideConns, char.DescendantAdded:Connect(G.hideInst))
end
function G.watchPlayer(p)
if p == lp and not S.hideSelf then return end
if p.Character then G.hideChar(p.Character) end
table.insert(hideConns, p.CharacterAdded:Connect(function(c)
task.wait()
G.hideChar(c)
end))
end
function G.applyHide()
for _, p in ipairs(Players:GetPlayers()) do G.watchPlayer(p) end
table.insert(hideConns, Players.PlayerAdded:Connect(G.watchPlayer))
end
function G.clearHide()
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
G.clearHide()
if want then G.applyHide() end
status(want and "Игроки скрыты" or "Игроки показаны")
refreshButtons()
end
local function toggleDayNight()
if not S.timeLock then S.origTime = Lighting.ClockTime end
S.timeLock = true
S.night = not S.night
Lighting.ClockTime = S.night and 0 or 14
status(S.night and "Ночь" or "День")
refreshButtons()
end
function G.resetTime()
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
local godConns = {}
local godCharConn
local godHum, godOrigMax
local godParts = {}
G.GOD_HP = 1e9   -- конечное число: math.huge давал NaN (inf/inf) в игровых эффектах урона -> чёрный экран
function G.godRelease()
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
function G.godApply(char)
G.godRelease()
local hum = char and char:FindFirstChildOfClass("Humanoid")
if not hum then return end
godHum = hum
for _, d in ipairs(char:GetDescendants()) do
if d:IsA("BasePart") and d.CanTouch then
pcall(function() d.CanTouch = false end)
table.insert(godParts, d)
end
end
if hum.MaxHealth < G.GOD_HP * 0.5 then godOrigMax = hum.MaxHealth end
pcall(function()
hum.MaxHealth = G.GOD_HP
hum.Health = G.GOD_HP
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
G.godApply(lp.Character)
godCharConn = lp.CharacterAdded:Connect(function(c)
task.wait(0.2)
if S.god then G.godApply(c) end
end)
status("Бессмертие включено")
else
G.godRelease()
status("Бессмертие выключено")
end
refreshButtons()
end
local function healSelf()
local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
if hum then
pcall(function() hum.Health = (hum.MaxHealth >= G.GOD_HP) and G.GOD_HP or hum.MaxHealth end)
status("Здоровье восстановлено")
end
end
local PRESETS = {"Huggy Wuggy", "Kissy Missy", "Mommy Long Legs", "CatNap"}
local CLIP_FPS = 15      -- частота записи поз (кадров/с) для копирования анимаций
local ARM_DOWN = 1.4   -- насколько (рад.) опускать руки R15, если у источника нет позы/анимации
local LIB_FILE = "CinePanel_library.json"
local LIB, libSel = {}, nil
local rebuildLibList = function() end
local VH = {}               -- визуально скрытые модели
local skins = {}            -- [персонаж] = данные скина
local skinFolder
local swapTemplates = {}
local swapPrevHide, swapPrevList = false, false
local function visProps(d)
if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
return "Transparency", 1
elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("Highlight")
or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
return "Enabled", false
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
function G.vhClearAll()
for m, rec in pairs(VH) do
rec.conn:Disconnect()
for d, info in pairs(rec.orig) do
if d.Parent then pcall(function() d[info[1]] = info[3] end) end
end
VH[m] = nil
end
end
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
function G.loadAssetModel(id)
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
local function readAnimIds(model)
local out = {}
local an = model:FindFirstChild("Animate")
if an then
for _, key in ipairs({"idle", "walk", "run"}) do
local f = an:FindFirstChild(key)
local a = f and f:FindFirstChildWhichIsA("Animation", true)
if a and a.AnimationId ~= "" then out[key] = a.AnimationId end
end
end
return out
end
function G.livePlayingIds(model)
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
function G.enumByValue(enum, v)
for _, it in ipairs(enum:GetEnumItems()) do
if it.Value == v then return it end
end
end
function G.origVal(model, d, prop)
local rec = VH[model]
local info = rec and rec.orig[d]
if info and info[1] == prop then return info[3] end
return d[prop]
end
function G.v3(v) return {v.X, v.Y, v.Z} end
function G.serialize(model)
local root = rootOf(model)
if not root then return nil end
local rootCF = root.CFrame
local parts, idx = {}, {}
for _, d in ipairs(model:GetDescendants()) do
if d:IsA("BasePart") then
local e = {
n = d.Name, sz = G.v3(d.Size), cf = {rootCF:ToObjectSpace(d.CFrame):GetComponents()},
col = {d.Color.R, d.Color.G, d.Color.B}, mat = d.Material.Value,
tr = G.origVal(model, d, "Transparency"), rf = d.Reflectance,
}
if d:IsA("MeshPart") then
e.mid, e.tid, e.msz = d.MeshId, d.TextureID, G.v3(d.MeshSize)
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
e.sm = {t = c.MeshType.Value, id = c.MeshId, tx = c.TextureId, sc = G.v3(c.Scale), of = G.v3(c.Offset)}
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
tr = G.origVal(model, c, "Transparency")})
elseif c:IsA("Decal") then
e.dc = e.dc or {}
table.insert(e.dc, {t = c.Texture, f = c.Face.Value, tr = G.origVal(model, c, "Transparency")})
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
function G.deserialize(desc)
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
p.Material = G.enumByValue(Enum.Material, e.mat) or Enum.Material.Plastic
p.Transparency = e.tr or 0
p.Reflectance = e.rf or 0
if e.shape and p.ClassName == "Part" then
pcall(function() p.Shape = G.enumByValue(Enum.PartType, e.shape) end)
end
if e.sm then
local sm = Instance.new("SpecialMesh")
sm.MeshType = G.enumByValue(Enum.MeshType, e.sm.t) or Enum.MeshType.FileMesh
if e.sm.id and e.sm.id ~= "" then sm.MeshId = e.sm.id end
sm.TextureId = e.sm.tx or ""
sm.Scale = Vector3.new(table.unpack(e.sm.sc))
sm.Offset = Vector3.new(table.unpack(e.sm.of))
sm.Parent = p
end
for _, dd in ipairs(e.dc or {}) do
local dc = Instance.new("Decal")
dc.Texture = dd.t
dc.Face = G.enumByValue(Enum.NormalId, dd.f) or Enum.NormalId.Front
dc.Transparency = dd.tr or 0
dc.Parent = p
end
for _, tt in ipairs(e.tx or {}) do
local tx = Instance.new("Texture")
tx.Texture = tt.t
tx.Face = G.enumByValue(Enum.NormalId, tt.f) or Enum.NormalId.Front
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
pcall(function() hum.RigType = G.enumByValue(Enum.HumanoidRigType, desc.rig or 1) or Enum.HumanoidRigType.R15 end)
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
cm.BodyPart = G.enumByValue(Enum.BodyPart, m.b)
cm.MeshId, cm.OverlayTextureId, cm.BaseTextureId = m.m, m.o, m.t
cm.Parent = model
end)
end
model:SetAttribute("CineUnsup", unsup)
model:SetAttribute("CineHip", desc.hip or 0)
return model
end
local function saveLib()
if not writefile then return end
local t = {}
for _, e in ipairs(LIB) do
if e.kind == "capture" then
if e.desc then t[#t + 1] = {n = e.name, k = "capture", d = e.desc} end
else
t[#t + 1] = {n = e.name, k = "asset", id = e.id, an = e.anim, cl = e.clips, sn = e.sounds}
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
table.insert(LIB, {name = e.n, kind = e.k, id = e.id, desc = e.d, anim = (e.d and e.d.anim) or e.an,
clips = (e.d and e.d.clips) or e.cl, sounds = (e.d and e.d.snd) or e.sn})
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
-- ===================== ЗВУКИ + ключи суставов =====================
-- ключи суставов: новый (Имя|Part0>Part1#N) и старый (Имя#N, для ранее сохранённых клипов)
function G.motorKeys(model)
local out, cnt, cntOld = {}, {}, {}
for _, d in ipairs(model:GetDescendants()) do
if d:IsA("Motor6D") then
local base = d.Name .. "|" .. (d.Part0 and d.Part0.Name or "?") .. ">" .. (d.Part1 and d.Part1.Name or "?")
cnt[base] = (cnt[base] or 0) + 1
cntOld[d.Name] = (cntOld[d.Name] or 0) + 1
out[#out + 1] = {d, base .. "#" .. cnt[base], d.Name .. "#" .. cntOld[d.Name]}
end
end
return out
end
-- скорость по смещению корня (работает и для NPC, которых двигают твином/CFrame)
function G.speedTracker()
local last, lt
return function(root)
local now, p = os.clock(), root.Position
local sp = 0
if last and now > lt then
local d = p - last
sp = math.min(Vector3.new(d.X, 0, d.Z).Magnitude / (now - lt), 80)
end
last, lt = p, now
local v = root.AssemblyLinearVelocity
return math.max(sp, Vector3.new(v.X, 0, v.Z).Magnitude)
end
end
-- мгновенный снимок позы: копия не стоит в T-позе, пока идёт запись
function G.snapshotPose(model, entry)
if entry.clips then return end
local keys, fr = {}, {}
local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end
for _, it in ipairs(G.motorKeys(model)) do
local cf = it[1].Transform
local ps = cf.Position
local rx, ry, rz = cf:ToEulerAnglesYXZ()
keys[#keys + 1] = it[2]
local n = #fr
fr[n + 1], fr[n + 2], fr[n + 3] = r3(ps.X), r3(ps.Y), r3(ps.Z)
fr[n + 4], fr[n + 5], fr[n + 6] = r3(rx), r3(ry), r3(rz)
end
if #keys == 0 then return end
entry.clips = {keys = keys, idle = {f = {fr, fr}, sp = 0}}
entry._dec = nil
end
function G.classifySound(name)
local n = string.lower(name or "")
local function has(list)
for _, w in ipairs(list) do
if n:find(w, 1, true) then return true end
end
return false
end
if has({"death", "die", "dead"}) then return "death" end
if has({"hit", "hurt", "pain", "punch", "impact", "damage", "ouch", "oof"}) then return "hit" end
if has({"attack", "swing", "slash", "bite", "grab", "kill", "scream", "roar", "screech",
"jumpscare", "growl", "shout", "swipe", "whoosh", "lunge", "chase"}) then return "attack" end
if has({"step", "foot", "walk", "run", "jump", "land"}) then return "step" end
if has({"idle", "ambient", "breath", "music", "loop", "theme", "hum"}) then return "idle" end
return "other"
end
function G.addSound(entry, s, cat)
if not s or s.SoundId == "" then return end
entry.sounds = entry.sounds or {}
for _, x in ipairs(entry.sounds) do
if x.id == s.SoundId then
if cat == "attack" and x.cat == "other" then x.cat = "attack" end
return
end
end
if #entry.sounds >= 40 then return end
table.insert(entry.sounds, {id = s.SoundId, name = s.Name, cat = cat or G.classifySound(s.Name),
vol = s.Volume, spd = s.PlaybackSpeed, loop = s.Looped})
end
function G.readSounds(model, entry)
entry.sounds = entry.sounds or {}
for _, d in ipairs(model:GetDescendants()) do
if d:IsA("Sound") then G.addSound(entry, d) end
end
end
G.SFX_FB = {attack = {"attack"}, hit = {"hit"}, death = {"death", "hit"}}
G.DEFAULT_ATTACK = "rbxasset://sounds/swordslash.wav" -- запасной звук, если у модели нет своих
function G.playSfxAt(entry, cat, pos, vol, useDefault)
if not S.sfx then return false end
local x
if entry and entry.sounds then
for _, c in ipairs(G.SFX_FB[cat] or {cat}) do
local list = {}
for _, s in ipairs(entry.sounds) do
if s.cat == c then list[#list + 1] = s end
end
if #list > 0 then x = list[math.random(#list)] break end
end
end
if not x and useDefault then x = {id = G.DEFAULT_ATTACK, vol = 0.8, spd = 1} end
if not x then return false end
local ok = pcall(function()
local part = Instance.new("Part")
part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
part.Transparency = 1
part.Size = Vector3.new(0.2, 0.2, 0.2)
part.Position = pos
part.Parent = G.getFx()
local snd = Instance.new("Sound")
snd.SoundId = x.id
snd.Volume = math.clamp((x.vol or 1) * (vol or 1), 0, 10)
snd.PlaybackSpeed = (x.spd and x.spd > 0) and x.spd or 1
snd.Looped = false
snd.RollOffMaxDistance = 150
snd.Parent = part
snd:Play()
game:GetService("Debris"):AddItem(part, 10)
end)
return ok
end
function G.isAttacking(model)
for _, t in ipairs(G.livePlayingIds(model)) do
local nm = string.lower(t.name or "")
if (not t.looped) or nm:find("attack") or nm:find("kill") or nm:find("grab")
or nm:find("slash") or nm:find("bite") or nm:find("hit") or nm:find("swing") then
return true
end
end
return false
end
function G.sfxSave(entry)
if entry.desc then entry.desc.snd = entry.sounds end
saveLib()
end
-- слушает звуки NPC (и новые, создаваемые рядом) и раскладывает по категориям
function G.observeSounds(model, entry, duration)
task.spawn(function()
entry.sounds = entry.sounds or {}
local watched, cons = {}, {}
local function cat() return G.isAttacking(model) and "attack" or nil end
local function watch(s)
if watched[s] then return end
watched[s] = true
table.insert(cons, s.Played:Connect(function() G.addSound(entry, s, cat()) end))
end
for _, d in ipairs(model:GetDescendants()) do
if d:IsA("Sound") then watch(d) end
end
table.insert(cons, model.DescendantAdded:Connect(function(d)
if d:IsA("Sound") then
watch(d)
task.defer(function() if d.IsPlaying then G.addSound(entry, d, cat()) end end)
end
end))
table.insert(cons, workspace.DescendantAdded:Connect(function(d)
if d:IsA("Sound") and not isSkinModel(d.Parent or workspace) then
local r = rootOf(model)
local part = d.Parent and d.Parent:IsA("BasePart") and d.Parent
if r and part and (part.Position - r.Position).Magnitude < 60 then
watch(d)
task.defer(function() if d.IsPlaying then G.addSound(entry, d, cat()) end end)
end
end
end))
local t0 = os.clock()
while os.clock() - t0 < duration and model.Parent do
for s in pairs(watched) do
if s.Parent and s.IsPlaying then G.addSound(entry, s, cat()) end
end
task.wait(0.2)
end
for _, c in ipairs(cons) do c:Disconnect() end
G.sfxSave(entry)
local n = {attack = 0, hit = 0, death = 0}
for _, x in ipairs(entry.sounds) do
if n[x.cat] then n[x.cat] = n[x.cat] + 1 end
end
status(string.format("Звуки: всего %d (атака %d, удар %d, смерть %d)", #entry.sounds, n.attack, n.hit, n.death))
end)
end
-- кнопка / Insert: скопировать звуки выбранного NPC в выбранную модель библиотеки
function G.copySounds()
local m = S.target
if not (m and m.Parent) then status("Выбери NPC во вкладке NPC") return end
local e = libSel
if not e then status("Выбери модель в списке (вкладка «Модели»)") return end
G.readSounds(m, e)
G.sfxSave(e)
G.observeSounds(m, e, 25)
status("Копирую звуки с «" .. m.Name .. "» 25 с: пусть NPC атакует/кричит")
end
local function getSource(entry)
if entry.src and entry.src.Parent == nil then return entry.src end
if entry.failT and os.clock() - entry.failT < 5 then return nil end
local src
if entry.kind == "asset" then
if not entry.id then
status("У «" .. entry.name .. "» нет ID — введи ID и нажми «Добавить по ID»")
entry.failT = os.clock()
return nil
end
src = G.loadAssetModel(entry.id)
elseif entry.kind == "capture" and entry.desc then
local ok, m = pcall(G.deserialize, entry.desc)
if ok then src = m end
end
if src then
entry.src = src
entry.failT = nil
if not entry.sounds then pcall(G.readSounds, src, entry) end
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
function G.isIdentity(cf)
return cf.RightVector:Dot(Vector3.xAxis) > 0.999 and cf.UpVector:Dot(Vector3.yAxis) > 0.999
end
function G.setupTracks(skin, entry)
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
function G.patchFailedMeshes(skin, label)
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
function G.checkTextures(skin)
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
function G.syncVisuals(skin, orig)
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
local function isArmJoint(m)
local n = string.lower(m.Name .. " " .. (m.Part1 and m.Part1.Name or ""))
if n:find("fore") or n:find("lower") or n:find("hand") or n:find("elbow") or n:find("wrist")
or n:find("finger") or n:find("armor") then
return false
end
return n:find("shoulder") ~= nil or n:find("arm") ~= nil
end
function G.armToward(m, target)
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
function G.limbSide(m, idx)
local n = string.lower(m.Name .. " " .. (m.Part1 and m.Part1.Name or ""))
if n:find("right") then return 1 end
if n:find("left") then return -1 end
return (idx % 2 == 0) and 1 or -1
end
function G.buildArms(model, root)
local arms, idx = {}, 0
local down = -root.CFrame.UpVector
local fwd = (root.CFrame.LookVector * 0.9 + root.CFrame.UpVector * 0.1).Unit
for _, d in ipairs(model:GetDescendants()) do
if d:IsA("Motor6D") and isArmJoint(d) then
idx = idx + 1
arms[#arms + 1] = {d, G.armToward(d, down), G.armToward(d, fwd), G.limbSide(d, idx)}
end
end
return arms
end
function G.limbKind(m)
if isArmJoint(m) then return "arm" end
local n = string.lower(m.Name .. " " .. (m.Part1 and m.Part1.Name or ""))
if n:find("lower") or n:find("knee") or n:find("foot") or n:find("ankle") or n:find("toe")
or n:find("shin") or n:find("calf") or n:find("armor") then
return nil
end
if n:find("hip") or n:find("thigh") or n:find("leg") then return "leg" end
return nil
end
function G.buildLimbs(model, root)
local list, cnt = {}, {arm = 0, leg = 0}
local axisW = root.CFrame.RightVector
local down = -root.CFrame.UpVector
for _, d in ipairs(model:GetDescendants()) do
if d:IsA("Motor6D") and d.Part0 and d.Part1 then
local kind = G.limbKind(d)
if kind then
cnt[kind] = cnt[kind] + 1
local F = d.Part0.CFrame * d.C0
list[#list + 1] = {m = d, kind = kind, side = G.limbSide(d, cnt[kind]),
axis = F:VectorToObjectSpace(axisW), base = (kind == "arm") and G.armToward(d, down) or nil}
end
end
end
return list
end
function G.decodeClips(raw)
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
function G.entryClips(entry)
if not (entry and entry.clips) then return nil end
if entry._dec == nil then
local ok, r = pcall(G.decodeClips, entry.clips)
entry._dec = (ok and r) or false
end
return entry._dec or nil
end
function G.buildClipMotors(model, dec)
local list = {}
for _, it in ipairs(G.motorKeys(model)) do
local j = dec.keyIndex[it[2]] or dec.keyIndex[it[3]]
if j then list[#list + 1] = {it[1], j} end
end
return list
end
function G.applyClip(e, c, t, loop)
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
local function animateActor(e, dt, sp, hint)
e.sm = (e.sm or sp) * 0.7 + sp * 0.3
if e.moving then
if e.sm < 1.2 and not hint then e.moving = false end   -- гистерезис: без дёрганья стоя
elseif e.sm > 2.5 or hint then
e.moving = true
end
local want = "idle"
if e.moving then want = (e.sm > 18) and "run" or "walk" end
local useRecorded = not (S.basicAnim and e.limbs and #e.limbs > 0)
local lackMove = false -- нет записи ходьбы -> процедурная ходьба вместо скольжения в позе idle
local cl = e.clips
if useRecorded and cl and e.cm and #e.cm > 0 then
if e.atkT0 and cl.attack then
local t = os.clock() - e.atkT0
if t < cl.attack.len then
G.applyClip(e, cl.attack, t, false)
return true
end
e.atkT0 = nil
end
local order = (want == "run" and {"run", "walk"}) or (want == "walk" and {"walk", "run"}) or {"idle"}
local c
for _, k in ipairs(order) do
if cl[k] then c = cl[k] break end
end
if c then
local scale = 1
if want ~= "idle" and c.sp and c.sp > 0.5 then scale = math.clamp(e.sm / c.sp, 0.5, 2) end
e.ct = (e.ct or 0) + dt * scale
G.applyClip(e, c, e.ct, true)
return true
elseif want ~= "idle" then
lackMove = true
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
or (w == "idle" and e.tracks.idle and "idle") or nil
end
if w == nil and want ~= "idle" then lackMove = true end
if not lackMove or w then
lackMove = false
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
end
if e.limbs and #e.limbs > 0 and (e.procedural or S.basicAnim or lackMove) then
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
function G.applyFakeAttack(e)
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
local function applySkin(char, src, entry)
removeSkin(char)
diagInfo.mesh, diagInfo.tex, diagInfo.fixed = "", "", 0
local origRoot = char:FindFirstChild("HumanoidRootPart") or rootOf(char)
if not origRoot then return false end
local skin, root, hip = buildSkin(src)
if not skin then return false end
skin.Name = "CineSkin"
skin.Parent = getSkinFolder()
if entry and entry.orig then diagInfo.fixed = G.syncVisuals(skin, entry.orig) end
if entry and (entry.kind == "capture" or entry.kind == "asset") then
G.patchFailedMeshes(skin, entry.name)
G.checkTextures(skin)
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
local arms = G.buildArms(skin, root)
local armDown = {}
for _, a in ipairs(arms) do armDown[a[1]] = a[2] end
for _, d in ipairs(skin:GetDescendants()) do
if d:IsA("Motor6D") then
local o = origMotors[d.Name]
local sg = armDown[d]
if o or sg then pairsList[#pairsList + 1] = {d, o, sg} end
end
end
local totalMotors = 0
for _, d in ipairs(skin:GetDescendants()) do
if d:IsA("Motor6D") then totalMotors = totalMotors + 1 end
end
local matched = 0
for _, pr in ipairs(pairsList) do
if pr[2] then matched = matched + 1 end
end
local tracks, attackTr = G.setupTracks(skin, entry)
local dec = G.entryClips(entry)
vhHide(char, "skin")
skins[char] = {skin = skin, root = root, origRoot = origRoot, offY = offY,
motors = pairsList, fb = pairsList, tracks = tracks, attack = attackTr, t0 = os.clock(),
clips = dec, cm = dec and G.buildClipMotors(skin, dec) or {}, arms = arms,
limbs = G.buildLimbs(skin, root), procedural = (matched < math.max(1, math.floor(totalMotors * 0.6))),
isPlayer = Players:GetPlayerFromCharacter(char) ~= nil, entry = entry, parked = false}
task.delay(1.5, function()
local cur = skins[char]
if not cur or cur.skin ~= skin then return end
local n, vis, maxd = 0, 0, 0
for _, d in ipairs(skin:GetDescendants()) do
if d:IsA("BasePart") then
n = n + 1
if d.Transparency < 0.95 then vis = vis + 1 end
maxd = math.max(maxd, (d.Position - root.Position).Magnitude)
end
end
diagInfo.skin = string.format("частей %d, видно %d, разброс %.0f, сдвиг %.1f", n, vis, maxd,
(root.Position - origRoot.Position).Magnitude)
pushDiag()
end)
return true
end
local stopPuppet = function() end
RunService:BindToRenderStep("CineSkins", Enum.RenderPriority.Last.Value, function(dt)
for char, e in pairs(skins) do
if not char.Parent or not e.origRoot.Parent then
removeSkin(char)
else
local lunge = 0
if e.fakeAtk then
local u = (os.clock() - e.fakeAtk) / 0.38
if u < 1 then lunge = math.sin(math.pi * u) * 0.8 end
end
-- поворот к цели при атаке делаем ТОЛЬКО у локальной модели (настоящий персонаж не крутим — это видят другие)
local base = e.origRoot.CFrame
if e.faceT and os.clock() < e.faceT and e.faceDir then
local p0 = base.Position
base = CFrame.lookAt(p0, p0 + e.faceDir)
end
pcall(function() e.skin:PivotTo(base * CFrame.new(0, e.offY, -lunge)) end)
local v = e.origRoot.AssemblyLinearVelocity
local sp = Vector3.new(v.X, 0, v.Z).Magnitude
local hum = char:FindFirstChildOfClass("Humanoid")
local hint = char == lp.Character and hum and hum.MoveDirection.Magnitude > 0.05 or false
if not animateActor(e, dt, sp, hint) then
if not (e.attack and e.attack.IsPlaying) then
for _, pr in ipairs(e.motors) do
local m, o, sg = pr[1], pr[2], pr[3]
if m.Parent then
local t = o and o.Parent and o.Transform
if sg and (not t or G.isIdentity(t)) then
m.Transform = sg -- руки вниз
elseif t then
m.Transform = t
end
end
end
end
end
if e.fakeAtk then G.applyFakeAttack(e) end
local park = (e.dead or (S.hidden and e.isPlayer and (char ~= lp.Character or S.hideSelf))) and true or false
if park ~= e.parked then
e.parked = park
if park then e.skin.Parent = nil else e.skin.Parent = getSkinFolder() end
end
end
end
local pp = puppet
if pp then
if not (pp.model.Parent and pp.hum.Parent and pp.root.Parent and lp.Character and pp.realRoot.Parent) then
stopPuppet()
else
if S.mode == "none" then
local cam = getCam()
if cam.CameraSubject ~= pp.hum then cam.CameraSubject = pp.hum end
if cam.CameraType ~= Enum.CameraType.Custom then cam.CameraType = Enum.CameraType.Custom end
end
local v = pp.root.AssemblyLinearVelocity
local sp = Vector3.new(v.X, 0, v.Z).Magnitude
local e = pp.e
if not animateActor(e, dt, sp, pp.hum.MoveDirection.Magnitude > 0.05) then
for _, a in ipairs(e.arms or {}) do
if a[1].Parent and a[2] then a[1].Transform = a[2] end
end
end
if e.fakeAtk then G.applyFakeAttack(e) end
end
end
local nc = npcCtl
if nc then
if not (nc.model.Parent and nc.hum.Parent and nc.root.Parent and nc.orig.Parent) then
G.stopNpcCtl()
else
if S.mode == "none" then
local cam = getCam()
if cam.CameraSubject ~= nc.hum then cam.CameraSubject = nc.hum end
if cam.CameraType ~= Enum.CameraType.Custom then cam.CameraType = Enum.CameraType.Custom end
end
local ne = nc.e
if ne.entry and ne.entry._dec == nil and ne.entry.clips then -- запись анимаций закончилась: подхватываем клипы
local dec = G.entryClips(ne.entry)
if dec then
ne.clips = dec
ne.cm = G.buildClipMotors(ne.skin, dec)
end
end
local nv = nc.root.AssemblyLinearVelocity
local nsp = Vector3.new(nv.X, 0, nv.Z).Magnitude
if not animateActor(ne, dt, nsp, nc.hum.MoveDirection.Magnitude > 0.05) then
for _, a in ipairs(ne.arms or {}) do
if a[1].Parent and a[2] then a[1].Transform = a[2] end
end
end
if ne.fakeAtk then G.applyFakeAttack(ne) end
end
end
end)
local function desiredFor(p)
if p == lp then
if puppet or npcCtl then return nil end
return S.selfEntry
end
if S.allEntry then return S.allEntry end
if S.swap and #swapTemplates > 0 then
return swapTemplates[(p.UserId % #swapTemplates) + 1]
end
end
local function reconcile()
for _, p in ipairs(Players:GetPlayers()) do
local char = p.Character
if char and char.Parent and char:FindFirstChildOfClass("Humanoid") then
local want = desiredFor(p)
local cur = skins[char]
if want then
if not cur or cur.entry ~= want then
local src = getSource(want)
if src and applySkin(char, src, want) and p == lp then
status("Модель применена: " .. want.name)
end
end
elseif cur then
removeSkin(char)
end
end
end
for char in pairs(skins) do
if not char.Parent then removeSkin(char) end
end
end
local reconciling = false
local function reconcileAsync()
if reconciling then return end
reconciling = true
task.spawn(function()
pcall(reconcile)
reconciling = false
end)
end
updateNPCHide = function()
if not S.hideNPC then
for m, rec in pairs(VH) do
if rec.who.npc then vhShow(m, "npc") end
end
return
end
local list = {}
for _, h in ipairs(workspace:GetDescendants()) do
if h:IsA("Humanoid") then
local m = h.Parent
if m and m:IsA("Model") and not isSkinModel(m) and not Players:GetPlayerFromCharacter(m) then
list[m] = true
end
end
end
for m in pairs(list) do
if m == S.target then vhShow(m, "npc") else vhHide(m, "npc") end
end
for m, rec in pairs(VH) do
if rec.who.npc and not list[m] then vhShow(m, "npc") end
end
end
local function toggleHideNPC(force)
if force == nil then force = not S.hideNPC end
S.hideNPC = force
updateNPCHide()
status(S.hideNPC and "NPC скрыты (выбранный виден)" or "NPC показаны")
refreshButtons()
end
function G.buildTemplates()
for _, t in ipairs(swapTemplates) do
if t.src then pcall(function() t.src:Destroy() end) end
end
swapTemplates = {}
local byName = {}
for _, h in ipairs(workspace:GetDescendants()) do
if h:IsA("Humanoid") then
local m = h.Parent
if m and m:IsA("Model") and not isSkinModel(m) and not Players:GetPlayerFromCharacter(m)
and not byName[m.Name] and #swapTemplates < 24 and rootOf(m) then
local c = cloneModel(m)
if c then
byName[m.Name] = true
table.insert(swapTemplates, {name = m.Name, kind = "template", src = c, anim = readAnimIds(m)})
end
end
end
end
end
local function toggleSwap(force)
if force == nil then force = not S.swap end
if force then
G.buildTemplates()
if #swapTemplates == 0 then
status("NPC не найдены — подменять нечем")
return
end
S.swap = true
swapPrevHide, swapPrevList = S.hideNPC, S.listPlayers
S.hideNPC, S.listPlayers = true, true
updateNPCHide()
reconcileAsync()
scanNPCs()
rebuildNPCList()
status("Игроки получили модели NPC (" .. #swapTemplates .. " шт.)")
else
S.swap = false
reconcile()
S.hideNPC, S.listPlayers = swapPrevHide, swapPrevList
updateNPCHide()
for _, t in ipairs(swapTemplates) do
if t.src then pcall(function() t.src:Destroy() end) end
end
swapTemplates = {}
scanNPCs()
rebuildNPCList()
status("Подмена игроков выключена")
end
refreshButtons()
end
function G.needSel()
if not libSel then status("Сначала выбери модель в списке") end
return libSel
end
function G.applySelf()
local e = G.needSel()
if not e then return end
S.selfEntry = e
status("Загружаю модель: " .. e.name)
reconcileAsync()
rebuildLibList()
end
function G.clearSelf()
S.selfEntry = nil
reconcileAsync()
status("Твоя модель возвращена")
rebuildLibList()
end
function G.applyOthers()
local e = G.needSel()
if not e then return end
S.allEntry = e
status("Модель для других игроков: " .. e.name)
reconcileAsync()
rebuildLibList()
end
function G.clearOthers()
S.allEntry = nil
reconcileAsync()
status("Модели других игроков возвращены")
rebuildLibList()
end
function G.deleteSel()
local e = libSel
if not e then return end
for i, x in ipairs(LIB) do
if x == e then table.remove(LIB, i) break end
end
if S.selfEntry == e then S.selfEntry = nil end
if S.allEntry == e then S.allEntry = nil end
libSel = nil
saveLib()
reconcileAsync()
rebuildLibList()
status("Удалено: " .. e.name)
end
function G.observeAnims(model, entry, duration)
G.observeSounds(model, entry, duration)
task.spawn(function()
entry.anim = entry.anim or {}
local motors, keys = {}, {}
for _, it in ipairs(G.motorKeys(model)) do
motors[#motors + 1] = it[1]
keys[#keys + 1] = it[2]
end
local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end
local function sample()
local fr = {}
for _, m in ipairs(motors) do
local cf = m.Transform
local ps = cf.Position
local rx, ry, rz = cf:ToEulerAnglesYXZ()
local n = #fr
fr[n + 1], fr[n + 2], fr[n + 3] = r3(ps.X), r3(ps.Y), r3(ps.Z)
fr[n + 4], fr[n + 5], fr[n + 6] = r3(rx), r3(ry), r3(rz)
end
return fr
end
local LIM = {idle = 3, walk = 2.4, run = 2, attack = 3.5}
local rec, prev, smooth, moving = {}, nil, 0, false
local speedOf = G.speedTracker()
local t0 = os.clock()
while os.clock() - t0 < duration and model.Parent do
local r = rootOf(model)
if r then
local sp = speedOf(r)
smooth = smooth * 0.6 + sp * 0.4
if moving then
if smooth < 1.2 then moving = false end
elseif smooth > 2.5 then
moving = true
end
local isAtk = false
local key = moving and (smooth > 14 and "run" or "walk") or "idle"
for _, t in ipairs(G.livePlayingIds(model)) do
local nm = string.lower(t.name or "")
local atk = (not t.looped) or nm:find("attack") or nm:find("kill") or nm:find("grab")
or nm:find("slash") or nm:find("bite") or nm:find("hit") or nm:find("swing")
if atk then isAtk = true end
local known = false
for _, v2 in pairs(entry.anim) do
if v2 == t.id then known = true end
end
if not known then
if atk then
if not entry.anim.attack then entry.anim.attack = t.id end
elseif not entry.anim[key] then
entry.anim[key] = t.id
end
end
end
if #motors > 0 then
local state = isAtk and "attack" or key
if state ~= prev then
local pc = prev and rec[prev]
if pc and not pc.closed then
if #pc.f >= 8 then
pc.closed = true
else
pc.f, pc.sps, pc.nsp = {}, 0, 0
end
end
prev = state
end
local c = rec[state]
if not c then
c = {f = {}, sps = 0, nsp = 0}
rec[state] = c
end
if not c.closed and #c.f < LIM[state] * CLIP_FPS then
c.f[#c.f + 1] = sample()
c.sps, c.nsp = c.sps + smooth, c.nsp + 1
end
end
end
task.wait(1 / CLIP_FPS)
end
-- объединяем с прошлой записью (если набор суставов тот же), а не стираем её
local clips, got = {keys = keys}, {}
local old = entry.clips
if old and old.keys and #old.keys == #keys then
local same = true
for i, k in ipairs(keys) do
if old.keys[i] ~= k then same = false break end
end
if same then
for _, st in ipairs({"idle", "walk", "run", "attack"}) do clips[st] = old[st] end
end
end
for st, c in pairs(rec) do
if #c.f >= 6 then
clips[st] = {f = c.f, sp = c.nsp > 0 and r3(c.sps / c.nsp) or 0}
got[#got + 1] = st
end
end
if #got > 0 or clips.idle then
entry.clips = clips
entry._dec = nil
if entry.desc then entry.desc.clips = clips end
end
if entry.desc then entry.desc.anim = entry.anim end
saveLib()
for k in pairs(entry.anim) do
local f = false
for _, g in ipairs(got) do
if g == k then f = true end
end
if not f then got[#got + 1] = k .. "(id)" end
end
table.sort(got)
status("Записано: " .. (#got > 0 and table.concat(got, ", ") or "ничего (NPC стоял без анимаций?)"))
if S.selfEntry == entry and lp.Character then
removeSkin(lp.Character)
reconcileAsync()
end
end)
end
function G.recordAttacks()
local m = S.target
if not (m and m.Parent) then status("Выбери NPC во вкладке NPC") return end
local e = libSel
if not e then status("Выбери модель в списке библиотеки") return end
e.anim = e.anim or {}
if e.desc then e.desc.anim = e.anim end
G.observeAnims(m, e, 40)
status("Записываю 40 с: пусть NPC постоит, походит и атакует")
end
function G.setAttackId(idText)
local e = libSel
if not e then status("Выбери модель в списке") return end
local id = tonumber((idText or ""):match("%d+"))
if not id then status("Введи ID анимации в поле «ID модели»") return end
e.anim = e.anim or {}
e.anim.attack = "rbxassetid://" .. id
if e.desc then e.desc.anim = e.anim end
saveLib()
if S.selfEntry == e and lp.Character then
removeSkin(lp.Character)
reconcileAsync()
end
status("Анимация атаки привязана к «" .. e.name .. "»")
end
local function captureNPC()
local m = S.target
if not (m and m.Parent) then
if not pickNearest() then status("NPC не найдены") return end
m = S.target
end
local src = cloneModel(m)
if not src then status("Не удалось скопировать модель") return end
local ok, desc = pcall(G.serialize, m)
local base, name, n = m.Name, m.Name, 1
local function exists(nm)
for _, e in ipairs(LIB) do
if e.name == nm then return true end
end
return false
end
while exists(name) do
n = n + 1
name = base .. " #" .. n
end
local entry = {name = name, kind = "capture", src = src, desc = ok and desc or nil}
entry.orig = m
entry.anim = readAnimIds(m)
entry.sounds = {}
pcall(G.readSounds, m, entry)
pcall(G.snapshotPose, m, entry)
if entry.desc then
entry.desc.anim = entry.anim
entry.desc.snd = entry.sounds
if entry.clips then entry.desc.clips = entry.clips end
end
G.observeAnims(m, entry, 30)
table.insert(LIB, entry)
libSel = entry
saveLib()
rebuildLibList()
status("Скопировано: " .. name .. (entry.desc and (writefile and " (в файл)" or "") or " (только сессия)")
.. ". Запоминаю анимации и звуки 30 с — пусть NPC постоит, пройдётся и атакует")
end
function G.addById(nameText, idText)
local id = tonumber((idText or ""):match("%d+"))
if not id then status("Введи числовой ID модели") return end
local name = (nameText or ""):gsub("^%s+", ""):gsub("%s+$", "")
if name == "" then name = "Model " .. id end
local entry
for _, e in ipairs(LIB) do
if e.name == name then entry = e break end
end
if not entry then
entry = {name = name}
table.insert(LIB, entry)
end
entry.kind, entry.id, entry.src, entry.desc, entry.failT = "asset", id, nil, nil, nil
libSel = entry
saveLib()
rebuildLibList()
status("Добавлено: " .. name .. " (ID " .. id .. ")")
end
-- ===================== KILL (единственный вариант атаки: X / кнопка KILL) =====================
-- Всё делается ТОЛЬКО на твоём клиенте: копия NPC, частицы, кровь, тряска, звуки. Серверу и другим игрокам ничего не отправляется.
local KILL_RESPAWN = 8      -- через сколько секунд NPC «возвращается»
local fxFolder
local deadChars = {}
local function reviveChar(char)
local d = deadChars[char]
if not d then return end
deadChars[char] = nil
pcall(function() d.fake:Destroy() end)
vhShow(char, "dead")
local e = skins[char]
if e then e.dead = false end
end
local function reviveAll()
for ch in pairs(deadChars) do reviveChar(ch) end
status("Все персонажи возвращены")
end
local TweenService = game:GetService("TweenService")
local HITS_TO_KILL = 3
local FIGHT_TIMEOUT = 7
local fights = {}   -- [оригинал NPC] = {fake = замороженная копия, root, hits, last}
local fxGui
function G.getFx()
if not fxFolder or not fxFolder.Parent then
fxFolder = Instance.new("Folder")
fxFolder.Name = "CineFX"
fxFolder.Parent = workspace
end
return fxFolder
end
function G.fxNew(class, props, parent)
local o = Instance.new(class)
for k, v in pairs(props) do o[k] = v end
if parent then o.Parent = parent end
return o
end
function G.ensureFxGui()
if fxGui and fxGui.Parent then return fxGui end
fxGui = G.fxNew("ScreenGui", {Name = "CineBlood", ResetOnSpawn = false, DisplayOrder = 998,
IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local ok = false
if gethui then ok = pcall(function() fxGui.Parent = gethui() end) and fxGui.Parent ~= nil end
if not ok then ok = pcall(function() fxGui.Parent = game:GetService("CoreGui") end) and fxGui.Parent ~= nil end
if not ok then fxGui.Parent = lp:WaitForChild("PlayerGui") end
return fxGui
end
local shake = {t0 = 0, dur = 0, mag = 0, fov = 0, base = nil}
function G.cameraShake(mag, dur, fovKick)
shake.t0, shake.dur, shake.mag, shake.fov = os.clock(), dur, mag, fovKick or 0
end
RunService:BindToRenderStep("CineShake", Enum.RenderPriority.Camera.Value + 3, function()
local cam = workspace.CurrentCamera
if not cam then return end
local t = os.clock() - shake.t0
if t < shake.dur then
local k = (1 - t / shake.dur) ^ 2
local m = shake.mag * k
if not shake.base then shake.base = cam.FieldOfView end
local r = math.random
local ok, ncf = pcall(function()
return cam.CFrame * CFrame.new((r() - 0.5) * m, (r() - 0.5) * m, 0)
* CFrame.Angles((r() - 0.5) * m * 0.04, (r() - 0.5) * m * 0.04, (r() - 0.5) * m * 0.06)
end)
-- защита: NaN-камера = чёрный экран
if ok and ncf.Position == ncf.Position then cam.CFrame = ncf end
cam.FieldOfView = math.clamp(shake.base + shake.fov * k, 1, 120)
elseif shake.base then
cam.FieldOfView = shake.base
shake.base = nil
end
end)
function G.screenFlash(color, transparency, dur)
local g = G.ensureFxGui()
local f = G.fxNew("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = color,
BackgroundTransparency = transparency, BorderSizePixel = 0, ZIndex = 1}, g)
TweenService:Create(f, TweenInfo.new(dur), {BackgroundTransparency = 1}):Play()
task.delay(dur + 0.1, function() f:Destroy() end)
end
function G.bloodScreen()
local g = G.ensureFxGui()
local rnd = math.random
G.screenFlash(Color3.fromRGB(150, 0, 10), 0.6, 0.7)
for _ = 1, 16 do
local w = rnd(12, 44)
local drip = G.fxNew("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(rnd(), 0, 0, -6),
Size = UDim2.new(0, w, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2}, g)
G.fxNew("UICorner", {CornerRadius = UDim.new(0, w / 2)}, drip)
G.fxNew("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(196, 18, 26),
Color3.fromRGB(96, 0, 8))}, drip)
local len = 0.14 + rnd() * 0.42
local dur = 1.4 + rnd() * 1.8
task.delay(rnd() * 0.35, function()
TweenService:Create(drip, TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
{Size = UDim2.new(0, w, len, 0)}):Play()
end)
task.delay(4 + rnd() * 1.5, function()
TweenService:Create(drip, TweenInfo.new(1.2), {BackgroundTransparency = 1}):Play()
task.delay(1.3, function() drip:Destroy() end)
end)
end
for _ = 1, 8 do
local sz = rnd(40, 150)
local b = G.fxNew("Frame", {AnchorPoint = Vector2.new(0.5, 0.5),
Position = UDim2.fromScale(rnd(), rnd() * 0.8), Size = UDim2.fromOffset(sz * 0.4, sz * 0.4),
BackgroundColor3 = Color3.fromRGB(rnd(110, 160), 6, 12), BackgroundTransparency = 0.25,
BorderSizePixel = 0, ZIndex = 2}, g)
G.fxNew("UICorner", {CornerRadius = UDim.new(1, 0)}, b)
TweenService:Create(b, TweenInfo.new(0.12, Enum.EasingStyle.Back), {Size = UDim2.fromOffset(sz, sz)}):Play()
task.delay(3.5 + rnd() * 1.5, function()
TweenService:Create(b, TweenInfo.new(1.2), {BackgroundTransparency = 1}):Play()
task.delay(1.3, function() b:Destroy() end)
end)
end
-- страховка: если какой-то оверлей «завис» — через 8 с всё очищаем
G.fxToken = (G.fxToken or 0) + 1
local tok = G.fxToken
task.delay(8, function()
if tok == G.fxToken and fxGui and fxGui.Parent then
for _, c in ipairs(fxGui:GetChildren()) do c:Destroy() end
end
end)
end
local function deathFX()
G.bloodScreen()
G.cameraShake(2.2, 0.7, 10)
end
G.bits = {}
function G.spawnBit(pos, color, vel, size, life, neon)
-- частицы вплотную к камере закрывали экран (особенно у чёрных NPC) — не создаём их рядом с камерой
local camPos = getCam().CFrame.Position
local toCam = camPos - pos
local dist = toCam.Magnitude
if dist < 4 then return end
if dist < 14 then
local u = toCam.Unit
local into = vel:Dot(u)
if into > 0 then vel = vel - u * into end
end
size = math.min(size, 0.5)
local p = Instance.new("Part")
p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, false, true
p.Size = Vector3.new(size, size, size)
p.Color = color
p.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
p.Parent = G.getFx()
p.AssemblyLinearVelocity = vel
p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14
G.bits[p] = true
TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
{Transparency = 1, Size = Vector3.new(size * 0.25, size * 0.25, size * 0.25)}):Play()
task.delay(life + 0.1, function() G.bits[p] = nil p:Destroy() end)
end
function G.disintegrate(model)
local list, total, n, center = {}, 0, 0, Vector3.zero
for _, d in ipairs(model:GetDescendants()) do
if d:IsA("BasePart") and d.Transparency < 0.9 then
local vol = math.max(d.Size.X * d.Size.Y * d.Size.Z, 0.01)
list[#list + 1] = {d, vol}
total = total + vol
center = center + d.Position
n = n + 1
end
end
if n == 0 then return end
center = center / n
local budget = 160
for _, it in ipairs(list) do
local d, vol = it[1], it[2]
local cnt = math.clamp(math.floor(budget * vol / total + 0.5), 1, 24)
for _ = 1, cnt do
local off = Vector3.new((math.random() - 0.5) * d.Size.X, (math.random() - 0.5) * d.Size.Y,
(math.random() - 0.5) * d.Size.Z)
local pos = (d.CFrame * CFrame.new(off)).Position
local dir = pos - center
dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.yAxis
local vel = dir * math.random(10, 26) + Vector3.new(math.random(-4, 4), math.random(6, 16), math.random(-4, 4))
G.spawnBit(pos, d.Color, vel, 0.25 + math.random() * 0.45, 1.0 + math.random() * 0.9, false)
end
end
end
function G.startFight(orig)
local clone = cloneModel(orig)
if not clone then return nil end
clone.Name = "CineFight"
for _, d in ipairs(clone:GetDescendants()) do
pcall(function()
if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
d:Destroy()
elseif d:IsA("BasePart") then
d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false
end
end)
end
local hum = clone:FindFirstChildOfClass("Humanoid")
if hum then
pcall(function()
hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
hum.PlatformStand = true
hum.EvaluateStateMachine = false
end)
end
clone.Parent = G.getFx()
local root = rootOf(clone)
if not root then clone:Destroy() return nil end
vhHide(orig, "fight")
local f = {fake = clone, root = root, hits = 0, last = os.clock()}
-- звуки самого NPC берём с оригинала (у клона Sound удалены)
f.snd = {sounds = {}}
pcall(G.readSounds, orig, f.snd)
fights[orig] = f
return f
end
function G.endFight(orig)
local f = fights[orig]
if not f then return end
fights[orig] = nil
pcall(function() f.fake:Destroy() end)
vhShow(orig, "fight")
end
connect(RunService.Heartbeat, function()
for orig, f in pairs(fights) do
if not f.fake.Parent or not orig.Parent or os.clock() - f.last > FIGHT_TIMEOUT then
G.endFight(orig)
end
end
-- частицы, подлетевшие к камере, делаем невидимыми (локально)
if next(G.bits) then
local cp = getCam().CFrame.Position
for b in pairs(G.bits) do
if not b.Parent then
G.bits[b] = nil
elseif (b.Position - cp).Magnitude < 3.5 then
pcall(function() b.LocalTransparencyModifier = 1 end)
end
end
end
end)
function G.finishKill(orig, f)
fights[orig] = nil
local clone = f.fake
pcall(function()
local p = f.root.Position
if not G.playSfxAt(f.snd, "death", p, 1) then
local ae = (puppet and puppet.e) or (lp.Character and skins[lp.Character])
G.playSfxAt(ae and ae.entry or nil, "death", p, 1)
end
end)
pcall(G.disintegrate, clone)
pcall(function() clone:Destroy() end)
local dummy = Instance.new("Folder")
dummy.Name = "CineDeathDummy"
dummy.Parent = G.getFx()
deadChars[orig] = {fake = dummy}
vhHide(orig, "dead")
vhShow(orig, "fight")
task.delay(KILL_RESPAWN, function()
if deadChars[orig] and deadChars[orig].fake == dummy then reviveChar(orig) end
end)
pcall(deathFX)
end
local function landHit(orig)
if not orig or deadChars[orig] or Players:GetPlayerFromCharacter(orig) then return end
local f = fights[orig] or G.startFight(orig)
if not f then return end
f.hits = f.hits + 1
f.last = os.clock()
local pos = f.root.Position + Vector3.new(0, 1, 0)
pcall(function()
local ae = (puppet and puppet.e) or (lp.Character and skins[lp.Character])
G.playSfxAt(f.snd, "hit", pos, 1)
G.playSfxAt(ae and ae.entry or nil, "hit", pos, 0.9)
end)
for _ = 1, 10 do -- искры от удара
G.spawnBit(pos, Color3.fromRGB(255, 235, 170), Vector3.new(math.random(-14, 14), math.random(4, 14), math.random(-14, 14)),
0.2 + math.random() * 0.15, 0.4, true)
end
pcall(function()
local h = Instance.new("Highlight")
h.FillColor = Color3.fromRGB(255, 60, 60)
h.FillTransparency = 0.4
h.OutlineTransparency = 1
h.Parent = f.fake
TweenService:Create(h, TweenInfo.new(0.2), {FillTransparency = 1}):Play()
task.delay(0.25, function() h:Destroy() end)
local base = f.fake:GetPivot()
local myR = myRootPart()
local dir = myR and (f.root.Position - myR.Position) or Vector3.new(0, 0, -1)
dir = Vector3.new(dir.X, 0, dir.Z)
dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.new(0, 0, -1)
f.fake:PivotTo(base + dir * 0.9)
task.delay(0.07, function()
if f.fake.Parent then f.fake:PivotTo(base + dir * 0.25) end
end)
end)
if f.hits >= HITS_TO_KILL then
G.finishKill(orig, f)
else
G.cameraShake(0.55, 0.22, 3)
G.screenFlash(Color3.new(1, 1, 1), 0.88, 0.15)
status("Удар " .. f.hits .. " из " .. HITS_TO_KILL)
end
end
local function isCandidate(m, h)
return m and m:IsA("Model") and m ~= lp.Character and not isSkinModel(m) and not deadChars[m]
and not (npcCtl and npcCtl.orig == m)
and not fights[m] and not Players:GetPlayerFromCharacter(m)
and (not h:IsA("Humanoid") or h.Health > 0)
end
local toggleKillUI = function() end
local pressKillFX = function() end
local KILL_FRONT_RANGE = 25   -- дальность «перед тобой» (studs)
local KILL_FRONT_DOT = 0.6    -- ширина конуса (0.6 ≈ ±53°)
local killBusy = false
function G.findFrontTarget(origin, look, range)   -- look == nil: без конуса (ближайший)
local best, bd = nil, range or KILL_FRONT_RANGE
for orig, f in pairs(fights) do
if f.root and f.root.Parent then
local dir = f.root.Position - origin
local dist = dir.Magnitude
if dist > 0.1 and dist < bd and (not look or look:Dot(dir.Unit) > KILL_FRONT_DOT) then best, bd = orig, dist end
end
end
if best then return best end
for _, h in ipairs(workspace:GetDescendants()) do
if h:IsA("Humanoid") or h:IsA("AnimationController") then
local m = h.Parent
if isCandidate(m, h) then
local r = rootOf(m)
if r then
local dir = r.Position - origin
local dist = dir.Magnitude
if dist > 0.1 and dist < bd and (not look or look:Dot(dir.Unit) > KILL_FRONT_DOT) then best, bd = m, dist end
end
end
end
end
return best
end
function G.playAttackAnim(e)
local delay = 0.16
if not e then return delay end
e.punchSide = ((e.punchSide or -1) == 1) and -1 or 1 -- удары чередуем: правая/левая рука
if not S.basicAnim and e.clips and e.clips.attack and e.cm and #e.cm > 0 then
e.atkT0 = os.clock()
delay = math.min(e.clips.attack.len * 0.6, 0.8)
elseif not S.basicAnim and e.attack then
pcall(function() e.attack:Play(0.1) end)
delay = 0.4
else
e.fakeAtk = os.clock()
end
return delay
end
-- тот, кем ты сейчас «играешь»: управляемый NPC > кукла > твоя модель
function G.actor()
return (npcCtl and npcCtl.e) or (puppet and puppet.e) or (lp.Character and skins[lp.Character])
end
function G.doKill(best, cf)
if killBusy then return end
killBusy = true
local myRoot = myRootPart()
if not S.god then pcall(toggleGod, true) end
local e = G.actor()
-- поворот к цели: у управляемого NPC/куклы или у локальной модели. Настоящий персонаж НЕ вращаем (это видно другим)
local flat
local tr = fights[best] and fights[best].root or rootOf(best)
if tr and myRoot then
local d = tr.Position - myRoot.Position
flat = Vector3.new(d.X, 0, d.Z)
flat = flat.Magnitude > 0.05 and flat.Unit or nil
end
if flat then
local ctl = npcCtl or puppet
if ctl and myRoot == ctl.root then
pcall(function()
local p0 = myRoot.Position
myRoot.CFrame = CFrame.lookAt(p0, p0 + flat)
end)
elseif e then
e.faceDir, e.faceT = flat, os.clock() + 0.8
end
end
pcall(function()
G.playSfxAt(e and e.entry or nil, "attack", myRoot and myRoot.Position or cf.Position, 1, true)
end)
local delay = G.playAttackAnim(e)
task.delay(delay, function()
local ok, err = pcall(function()
if best.Parent or fights[best] then landHit(best) end
end)
if not ok then warn("[CinePanel] kill: " .. tostring(err)) end
task.wait(0.28)
killBusy = false
end)
end
local function G_origin()
local myRoot = myRootPart()
local cf = getCam().CFrame
local fromBody = (S.mode == "none" or S.mode == "self") and myRoot
return fromBody and myRoot.Position or cf.Position, cf
end
local function killFront()
if killBusy then return end
local origin, cf = G_origin()
local best = G.findFrontTarget(origin, cf.LookVector)
if not best then status("Перед тобой нет NPC") return end
G.doKill(best, cf)
end
function G.killNearest()
if killBusy then return end
local origin, cf = G_origin()
local best = G.findFrontTarget(origin, nil, 80)
if not best then status("Рядом нет NPC (80 studs)") return end
G.doKill(best, cf)
end
function G.killSelected()
if killBusy then return end
local m = S.target
if not (m and m.Parent) then status("Сначала выбери NPC во вкладке NPC") return end
local h = humOf(m) or m:FindFirstChildOfClass("AnimationController") or m
if not isCandidate(m, h) then status("Этого NPC убить нельзя (игрок/уже убит/ты им управляешь)") return end
local _, cf = G_origin()
G.doKill(m, cf)
end
-- Атака: замах + звук, а если перед тобой (до 7 studs) есть NPC — один удар по нему (3 удара = смерть)
function G.swing()
local e = G.actor()
if not e then status("Нет модели для атаки: включи управление NPC (F5), куклу или модель на себя") return end
if S.attackCd and os.clock() < S.attackCd then return end
S.attackCd = os.clock() + 0.6
local origin, cf = G_origin()
local myRoot = myRootPart()
pcall(function()
G.playSfxAt(e.entry, "attack", myRoot and myRoot.Position or cf.Position, 1, true)
end)
local tgt = G.findFrontTarget(origin, cf.LookVector, 7)
local delay = G.playAttackAnim(e)
if tgt then
task.delay(delay, function()
if tgt.Parent or fights[tgt] then pcall(landHit, tgt) end
end)
end
end
local function startPuppet()
if puppet then return end
if npcCtl then G.stopNpcCtl() end
local char = lp.Character
local realRoot = char and char:FindFirstChild("HumanoidRootPart")
local realHum = char and char:FindFirstChildOfClass("Humanoid")
if not (realRoot and realHum) then status("Нет персонажа") return end
local entry = S.selfEntry
local src = entry and getSource(entry)
local model = cloneModel(src or char)
if not model then status("Не удалось создать куклу") return end
local animIds = (entry and entry.anim and next(entry.anim)) and entry.anim or readAnimIds(char)
for _, d in ipairs(model:GetDescendants()) do
pcall(function()
if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
or d:IsA("ForceField") or d:IsA("Sound") then
d:Destroy()
elseif d:IsA("BasePart") then
d.Anchored, d.CanTouch, d.CanQuery, d.Massless = false, false, false, false
d.CanCollide = (d.Name == "HumanoidRootPart")
end
end)
end
local hum = model:FindFirstChildOfClass("Humanoid")
if not hum then
hum = Instance.new("Humanoid")
hum.Parent = model
end
local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
or model:FindFirstChildWhichIsA("BasePart", true)
if not root then
model:Destroy()
status("У модели нет корневой части")
return
end
model.PrimaryPart = root
pcall(function()
hum.RequiresNeck = false
hum.BreakJointsOnDeath = false
hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
hum.MaxHealth = 1e9
hum.Health = 1e9
hum.WalkSpeed = math.clamp(realHum.WalkSpeed, 8, 40)
hum.PlatformStand = false
hum.EvaluateStateMachine = true
end)
local origCF = realRoot.CFrame
model.Name = "CinePuppet"
model.Parent = getSkinFolder()
pcall(function() model:PivotTo(origCF) end)
local e = {skin = model, root = root, t0 = os.clock(), motors = {}, fb = {}}
e.entry = entry
e.tracks, e.attack = G.setupTracks(model, {anim = animIds})
local dec = G.entryClips(entry)
e.clips = dec
e.cm = dec and G.buildClipMotors(model, dec) or {}
e.arms = G.buildArms(model, root)
e.limbs = G.buildLimbs(model, root)
e.procedural = true
puppet = {model = model, hum = hum, root = root, e = e, realRoot = realRoot, realHum = realHum,
wasAnchored = realRoot.Anchored, origCF = origCF}
removeSkin(char) -- скин с настоящего персонажа снимаем
local up = workspace.StreamingEnabled and 250 or 2500
pcall(function()
realRoot.AssemblyLinearVelocity = Vector3.zero
realRoot.CFrame = origCF + Vector3.new(0, up, 0)
realRoot.Anchored = true
end)
local cam = getCam()
if S.mode == "none" then
cam.CameraType = Enum.CameraType.Custom
cam.CameraSubject = hum
end
status("Кукла включена: управляй копией (WASD/джойстик), настоящий персонаж спрятан")
refreshButtons()
end
stopPuppet = function()
if not puppet then return end
local p = puppet
puppet = nil
local cf = (p.root and p.root.Parent) and p.root.CFrame or p.origCF
pcall(function() p.model:Destroy() end)
local rr = p.realRoot
if rr and rr.Parent then
pcall(function()
rr.CFrame = cf + Vector3.new(0, 3, 0) -- настоящий персонаж возвращается туда, где стоит кукла
rr.AssemblyLinearVelocity = Vector3.zero
rr.Anchored = p.wasAnchored
end)
end
if S.mode == "none" then
local cam = getCam()
cam.CameraType = Enum.CameraType.Custom
if p.realHum and p.realHum.Parent then cam.CameraSubject = p.realHum end
end
status("Кукла выключена")
refreshButtons()
reconcileAsync()
end
local function togglePuppet(force)
if force == nil then force = not puppet end
if force then startPuppet() else stopPuppet() end
end
-- ===================== ВИЗУАЛЬНОЕ УПРАВЛЕНИЕ НАСТОЯЩИМ NPC =====================
-- Настоящий NPC остаётся на месте и не трогается. У тебя на клиенте он скрыт, а вместо него появляется
-- его копия, которой ты управляешь (WASD/Space/джойстик). Сервер и другие игроки ничего не видят.
function G.startNpcCtl()
if npcCtl then return end
local orig = S.target
if not (orig and orig.Parent) then
if not pickNearest() then status("NPC не найдены") return end
orig = S.target
end
if Players:GetPlayerFromCharacter(orig) then status("Это игрок — выбери NPC") return end
local oroot = rootOf(orig)
local char = lp.Character
local realRoot = char and char:FindFirstChild("HumanoidRootPart")
if not (oroot and realRoot) then status("Нет частей тела NPC или твоего персонажа") return end
if puppet then stopPuppet() end
-- если NPC уже копировали в библиотеку — берём оттуда записанные анимации и звуки
local entry
for _, le in ipairs(LIB) do
if le.kind == "capture" and (le.name == orig.Name or le.name:sub(1, #orig.Name + 2) == orig.Name .. " #") then entry = le break end
end
local temp = false
if not entry then
temp = true
entry = {name = orig.Name, kind = "temp", anim = readAnimIds(orig), sounds = {}}
pcall(G.snapshotPose, orig, entry)
for _, t in ipairs(G.livePlayingIds(orig)) do
if t.looped then entry.anim.idle = entry.anim.idle or t.id else entry.anim.attack = entry.anim.attack or t.id end
end
end
if not entry.sounds then entry.sounds = {} end
pcall(G.readSounds, orig, entry)
local model = cloneModel(orig)
if not model then status("Не удалось скопировать NPC") return end
for _, d in ipairs(model:GetDescendants()) do
pcall(function()
if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
or d:IsA("ForceField") or d:IsA("Sound") or d:IsA("BodyMover") or d:IsA("AlignPosition")
or d:IsA("AlignOrientation") or d:IsA("LinearVelocity") or d:IsA("VectorForce") or d:IsA("AngularVelocity") then
d:Destroy()
elseif d:IsA("BasePart") then
d.Anchored, d.CanTouch, d.CanQuery, d.Massless, d.CanCollide = false, false, false, false, false
end
end)
end
local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
or model:FindFirstChildWhichIsA("BasePart", true)
if not root then
model:Destroy()
status("У NPC нет корневой части")
return
end
model.PrimaryPart = root
pcall(function() root.CanCollide = true end)
local ohum = humOf(orig)
local hum = model:FindFirstChildOfClass("Humanoid")
if not hum then -- NPC на AnimationController: создаём Humanoid, высоту подбираем по самой нижней части
local minY = math.huge
for _, d in ipairs(model:GetDescendants()) do
if d:IsA("BasePart") then minY = math.min(minY, d.Position.Y - d.Size.Y / 2) end
end
hum = Instance.new("Humanoid")
hum.HipHeight = math.max((root.Position.Y - minY) - root.Size.Y / 2, 0)
hum.Parent = model
end
pcall(function()
hum.RequiresNeck = false
hum.BreakJointsOnDeath = false
hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
hum.MaxHealth = 1e9
hum.Health = 1e9
hum.WalkSpeed = ohum and math.clamp(ohum.WalkSpeed, 8, 40) or 16
hum.PlatformStand = false
hum.EvaluateStateMachine = true
end)
model.Name = "CineNPCCtl"
model.Parent = getSkinFolder()
pcall(function() model:PivotTo(orig:GetPivot()) end)
vhHide(orig, "ctl") -- оригинал скрыт только у тебя
local e = {skin = model, root = root, t0 = os.clock(), motors = {}, fb = {}, entry = entry}
e.tracks, e.attack = G.setupTracks(model, entry)
local dec = G.entryClips(entry)
e.clips = dec
e.cm = dec and G.buildClipMotors(model, dec) or {}
e.arms = G.buildArms(model, root)
e.limbs = G.buildLimbs(model, root)
e.procedural = true
npcCtl = {orig = orig, model = model, hum = hum, root = root, e = e, realRoot = realRoot,
wasAnchored = realRoot.Anchored, temp = temp, baseSpeed = hum.WalkSpeed}
-- твой настоящий персонаж остаётся стоять на месте (иначе WASD двигал бы и его)
pcall(function()
realRoot.AssemblyLinearVelocity = Vector3.zero
realRoot.Anchored = true
end)
local cam = getCam()
if S.mode == "none" then
cam.CameraType = Enum.CameraType.Custom
cam.CameraSubject = hum
end
G.enterSelf() -- орбитальная камера: ПКМ поворачивает, колесо — дистанция
if temp then G.observeAnims(orig, entry, 25) end
status("Управляешь копией «" .. orig.Name .. "»: WASD/Space, Shift — ускорение, ПКМ — поворот, Z — атака, X — KILL, F5 — стоп"
.. (temp and ". Записываю его анимации 25 с" or ""))
refreshButtons()
end
function G.stopNpcCtl()
if not npcCtl then return end
local c = npcCtl
npcCtl = nil
pcall(function() c.model:Destroy() end)
pcall(vhShow, c.orig, "ctl")
local rr = c.realRoot
if rr and rr.Parent then pcall(function() rr.Anchored = c.wasAnchored end) end
if S.mode == "self" then exitAll() end
if S.mode == "none" then
local cam = getCam()
cam.CameraType = Enum.CameraType.Custom
local rh = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
if rh then cam.CameraSubject = rh end
end
status("Управление NPC выключено")
refreshButtons()
reconcileAsync()
end
function G.toggleNpcCtl()
if npcCtl then G.stopNpcCtl() else G.startNpcCtl() end
refreshButtons()
end
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
-- 3-е лицо за себя / куклу (орбитальная камера вокруг своего персонажа)
function G.updateSelf(dt)
local r = myRootPart()
if not r then
status("Персонаж не найден — режим выключен")
exitAll()
return
end
local cam = getCam()
local focus = r.Position + Vector3.new(0, 2.2, 0)
local rot = CFrame.fromOrientation(S.spitch, S.syaw, 0)
local dir = rot:VectorToWorldSpace(Vector3.new(0, 0, S.sdist))
if not G.selfRay then
G.selfRay = RaycastParams.new()
G.selfRay.FilterType = Enum.RaycastFilterType.Exclude
G.selfRay.RespectCanCollide = true
end
local ex = {}
if lp.Character then ex[#ex + 1] = lp.Character end
if puppet then ex[#ex + 1] = puppet.model end
if npcCtl then ex[#ex + 1] = npcCtl.model ex[#ex + 1] = npcCtl.orig end
if skinFolder then ex[#ex + 1] = skinFolder end
if fxFolder then ex[#ex + 1] = fxFolder end
G.selfRay.FilterDescendantsInstances = ex
local hit = workspace:Raycast(focus, dir, G.selfRay)
local pos = hit and (hit.Position - dir.Unit * 0.5) or (focus + dir)
cam.CFrame = CFrame.lookAt(pos, focus)
end
RunService:BindToRenderStep("CinePanel", Enum.RenderPriority.Camera.Value + 1, function(dt)
if S.mode == "none" then return end
local cam = getCam()
cam.CameraType = Enum.CameraType.Scriptable
if S.mode == "free" then updateFree(dt)
elseif S.mode == "spec" then updateSpec(dt)
else G.updateSelf(dt) end
cam.FieldOfView = S.fov + (S.fovKick or 0)
end)
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
God = function() toggleGod() end,
HideNPCs = function() toggleHideNPC() end,
PlayersAsNPC = function() toggleSwap() end,
CaptureNPC = captureNPC,
CopySounds = function() G.copySounds() end,
KillFront = function() pressKillFX() killFront() end,
KillNearest = function() pressKillFX() G.killNearest() end,
KillSelected = function() pressKillFX() G.killSelected() end,
Attack = function() G.swing() end,
Puppet = function() togglePuppet() end,
SelfView = function() if S.mode == "self" then exitAll() else G.enterSelf() end end,
ReviveAll = reviveAll,
Exit = function() exitAll() G.stopNpcCtl() end,
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
elseif S.mode == "self" then
S.syaw = S.syaw - d.X * sens
S.spitch = math.clamp(S.spitch - d.Y * sens, -1.4, 1.4)
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
elseif S.mode == "self" then
S.sdist = math.clamp(S.sdist - z * 1.5, 2, 40)
elseif S.view == "third" then
S.dist = math.clamp(S.dist - z * 2, 2, 80)
end
refreshButtons()
end
end)
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
local main = new("Frame", {Size = UDim2.fromOffset(320, 580), Position = UDim2.fromOffset(20, 80),
BackgroundColor3 = BG, BorderSizePixel = 0, Active = true}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, main)
local titleBar = new("TextLabel", {Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(16, 16, 22),
BorderSizePixel = 0, Text = "  Cinema Panel", TextColor3 = TXT, Font = Enum.Font.GothamBold,
TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, titleBar)
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
local pages, tabBtns = {}, {}
local tabNames = {"NPC", "Камеры", "Мир", "Модели", "Клавиши"}
local tabBar = new("Frame", {Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 34), BackgroundTransparency = 1}, main)
new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
SortOrder = Enum.SortOrder.LayoutOrder}, tabBar)
local function showTab(name)
for n, p in pairs(pages) do p.Visible = (n == name) end
for n, b in pairs(tabBtns) do b.BackgroundColor3 = (n == name) and Color3.fromRGB(80, 105, 220) or BTN end
end
for i, n in ipairs(tabNames) do
local b = btn(tabBar, n, function() showTab(n) end, {Size = UDim2.new(0.2, -3, 1, 0), LayoutOrder = i, TextSize = 11})
tabBtns[n] = b
pages[n] = new("Frame", {Size = UDim2.new(1, -16, 1, -118), Position = UDim2.fromOffset(8, 66),
BackgroundTransparency = 1, Visible = false}, main)
end
local statusLabel = new("TextLabel", {Size = UDim2.new(1, -16, 0, 46), Position = UDim2.new(0, 8, 1, -52),
BackgroundColor3 = PANEL, BorderSizePixel = 0, Text = "Готово", TextColor3 = Color3.fromRGB(180, 190, 255),
Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true}, main)
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
do
local p = pages["NPC"]
local g = grid(p, 282)
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
B.selfView = gbtn(g, "3-е лицо: я / кукла", function() ACTIONS.SelfView() end)
B.puppet2  = gbtn(g, "", function() togglePuppet() end)
gbtn(g, "KILL ближайшего", function() pressKillFX() G.killNearest() end)
gbtn(g, "KILL выбранного", function() pressKillFX() G.killSelected() end)
gbtn(g, "Атака (Z)", function() G.swing() end)
gbtn(g, "Стоп управление", function() G.stopNpcCtl() end)
gbtn(g, "Скорость NPC -", function() S.ctlMul = math.clamp(S.ctlMul / 1.25, 0.25, 5) status(string.format("Скорость NPC: x%.2f (Shift = бег)", S.ctlMul)) end)
gbtn(g, "Скорость NPC +", function() S.ctlMul = math.clamp(S.ctlMul * 1.25, 0.25, 5) status(string.format("Скорость NPC: x%.2f (Shift = бег)", S.ctlMul)) end)
local list = scroller(p, 290)
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
do
local p = pages["Камеры"]
local g = grid(p, 70)
gbtn(g, "+ Поставить камеру", addCam)
B.smooth = gbtn(g, "", function() S.smooth = not S.smooth refreshButtons() end)
B.markers = gbtn(g, "", function() S.markers = not S.markers G.refreshMarkers() refreshButtons() end)
gbtn(g, "Очистить все", function()
S.cams = {}
saveCams()
G.refreshMarkers()
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
G.refreshMarkers()
rebuildCamList()
end, {Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -26, 0, 0),
BackgroundColor3 = Color3.fromRGB(150, 50, 50)})
end
end
end
do
local p = pages["Мир"]
local g = grid(p, 218)
B.night = gbtn(g, "День <-> Ночь", toggleDayNight)
gbtn(g, "Сбросить время", G.resetTime)
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
B.god = gbtn(g, "Бессмертие", function() toggleGod() end)
gbtn(g, "Вылечить себя", healSelf)
B.puppet = gbtn(g, "", function() togglePuppet() end)
B.basic = gbtn(g, "", function() S.basicAnim = not S.basicAnim refreshButtons() end)
B.sfx = gbtn(g, "", function() S.sfx = not S.sfx refreshButtons() end)
gbtn(g, "Копировать звуки NPC", G.copySounds)
B.info = new("TextLabel", {Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 226),
BackgroundTransparency = 1, TextColor3 = TXT, Font = Enum.Font.Gotham, TextSize = 12,
TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, p)
end
do
local p = pages["Модели"]
local g = grid(p, 218)
gbtn(g, "На себя", G.applySelf)
gbtn(g, "Снять с себя", G.clearSelf)
gbtn(g, "На других игроков", G.applyOthers)
gbtn(g, "Снять с других", G.clearOthers)
gbtn(g, "Скопировать NPC", captureNPC)
gbtn(g, "Удалить из списка", G.deleteSel)
gbtn(g, "Вернуть всех", reviveAll)
B.hideNPC = gbtn(g, "", function() toggleHideNPC() end)
B.swap = gbtn(g, "", function() toggleSwap() end)
B.listPlayers = gbtn(g, "", function()
S.listPlayers = not S.listPlayers
scanNPCs()
rebuildNPCList()
refreshButtons()
end)
gbtn(g, "Записать анимации (40с)", G.recordAttacks)
B.killUI = gbtn(g, "", function() toggleKillUI() end)
local function box(placeholder, pos, size)
local b = new("TextBox", {Size = size, Position = pos, PlaceholderText = placeholder, Text = "",
ClearTextOnFocus = false, BackgroundColor3 = PANEL, TextColor3 = TXT,
PlaceholderColor3 = Color3.fromRGB(140, 140, 150), Font = Enum.Font.Gotham, TextSize = 12,
BorderSizePixel = 0}, p)
new("UICorner", {CornerRadius = UDim.new(0, 5)}, b)
return b
end
local nameBox = box("Имя модели", UDim2.fromOffset(0, 224), UDim2.new(0.5, -3, 0, 24))
local idBox = box("ID модели", UDim2.new(0.5, 3, 0, 224), UDim2.new(0.5, -3, 0, 24))
gbtn(g, "ID атаки -> модель", function() G.setAttackId(idBox.Text) end)
btn(p, "Добавить / привязать ID", function() G.addById(nameBox.Text, idBox.Text) end,
{Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 252)})
local list = scroller(p, 282)
rebuildLibList = function()
for _, c in ipairs(list:GetChildren()) do
if c:IsA("TextButton") then c:Destroy() end
end
for i, e in ipairs(LIB) do
local tag = e.kind == "capture" and " [копия]" or (e.id and (" [ID " .. e.id .. "]") or " [нет ID]")
local marks = (e == S.selfEntry and " • я" or "") .. (e == S.allEntry and " • все" or "")
local row = btn(list, "  " .. e.name .. tag .. marks, function()
libSel = e
if e.kind == "asset" then
nameBox.Text = e.name
idBox.Text = e.id and tostring(e.id) or ""
end
if e.kind == "asset" and not e.id then
status("Введи ID модели справа и нажми «Добавить / привязать ID»")
else
status("Выбрано: " .. e.name)
end
rebuildLibList()
end, {Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = i})
row.BackgroundColor3 = (e == libSel) and Color3.fromRGB(80, 105, 220) or BTN
end
end
end
local killGui = new("ScreenGui", {Name = "CineKill", ResetOnSpawn = false, DisplayOrder = 1000,
ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
do
local ok = false
if gethui then ok = pcall(function() killGui.Parent = gethui() end) and killGui.Parent ~= nil end
if not ok then ok = pcall(function() killGui.Parent = game:GetService("CoreGui") end) and killGui.Parent ~= nil end
if not ok then killGui.Parent = lp:WaitForChild("PlayerGui") end
local TweenService = game:GetService("TweenService")
local holder = new("Frame", {Name = "KillHolder", Size = UDim2.fromOffset(240, 240), AnchorPoint = Vector2.new(1, 0.5),
Position = UDim2.new(1, -30, 0.6, 0), BackgroundTransparency = 1}, killGui)
local scale = new("UIScale", {Scale = 1}, holder)
local shadow = new("Frame", {Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 12),
BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6, BorderSizePixel = 0}, holder)
new("UICorner", {CornerRadius = UDim.new(1, 0)}, shadow)
local ring = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(38, 10, 14),
BorderSizePixel = 0}, holder)
new("UICorner", {CornerRadius = UDim.new(1, 0)}, ring)
new("UIStroke", {Color = Color3.fromRGB(255, 255, 255), Thickness = 3, Transparency = 0.45}, ring)
local kb = new("TextButton", {Name = "KillButton", Text = "", AutoButtonColor = false,
Size = UDim2.new(1, -24, 1, -24), Position = UDim2.fromOffset(12, 12),
BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, ring)
new("UICorner", {CornerRadius = UDim.new(1, 0)}, kb)
new("UIGradient", {Rotation = 90, Color = ColorSequence.new({
ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 96, 84)),
ColorSequenceKeypoint.new(0.55, Color3.fromRGB(214, 36, 44)),
ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 14, 28)),
})}, kb)
new("UIStroke", {Color = Color3.fromRGB(255, 190, 180), Thickness = 2.5, Transparency = 0.5}, kb)
local gloss = new("Frame", {Size = UDim2.fromScale(0.66, 0.34), Position = UDim2.fromScale(0.17, 0.07),
BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false}, kb)
new("UICorner", {CornerRadius = UDim.new(1, 0)}, gloss)
new("UIGradient", {Rotation = 90, Transparency = NumberSequence.new({
NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1)})}, gloss)
local label = new("TextLabel", {Text = "KILL", Size = UDim2.fromScale(0.78, 0.3), AnchorPoint = Vector2.new(0.5, 0.5),
Position = UDim2.fromScale(0.5, 0.48), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1),
Font = Enum.Font.GothamBlack, TextScaled = true, Active = false}, kb)
new("UITextSizeConstraint", {MaxTextSize = 60}, label)
new("UIStroke", {Color = Color3.fromRGB(90, 0, 10), Thickness = 2.5, Transparency = 0.15}, label)
new("TextLabel", {Text = "[ X ]", Size = UDim2.fromScale(0.5, 0.12), AnchorPoint = Vector2.new(0.5, 0.5),
Position = UDim2.fromScale(0.5, 0.74), BackgroundTransparency = 1,
TextColor3 = Color3.fromRGB(255, 220, 215), TextTransparency = 0.25,
Font = Enum.Font.GothamBold, TextScaled = true, Active = false}, kb)
pressKillFX = function()
TweenService:Create(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.86}):Play()
TweenService:Create(kb, TweenInfo.new(0.07), {BackgroundColor3 = Color3.fromRGB(165, 165, 165)}):Play()
TweenService:Create(shadow, TweenInfo.new(0.07), {Position = UDim2.fromOffset(0, 4), BackgroundTransparency = 0.45}):Play()
task.delay(0.1, function()
TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
TweenService:Create(kb, TweenInfo.new(0.2), {BackgroundColor3 = Color3.new(1, 1, 1)}):Play()
TweenService:Create(shadow, TweenInfo.new(0.2), {Position = UDim2.fromOffset(0, 12), BackgroundTransparency = 0.6}):Play()
end)
end
kb.Activated:Connect(function()
pressKillFX()
killFront()
end)
RunService:BindToRenderStep("CineJoy", Enum.RenderPriority.Input.Value + 1, function()
local ctl = npcCtl or puppet
if (S.mode ~= "none" and S.mode ~= "self") or not ctl or typing() then return end
local hum = ctl.hum
-- ускорение: Shift = бег (x2.2), Ctrl = медленно (x0.4), базовый множитель меняется кнопками «Скорость NPC»
if npcCtl then
local mul = S.ctlMul
if UIS:IsKeyDown(K.LeftShift) then mul = mul * 2.2 elseif UIS:IsKeyDown(K.LeftControl) then mul = mul * 0.4 end
pcall(function() hum.WalkSpeed = npcCtl.baseSpeed * mul end)
end
-- поворот: ПКМ зажат -> NPC плавно смотрит туда же, куда камера (можно идти боком); отпущен -> NPC поворачивается по ходу движения
local rr = ctl.root
if S.rmb and S.mode == "self" and rr and rr.Parent then
pcall(function()
hum.AutoRotate = false
local want = CFrame.new(rr.Position) * CFrame.fromOrientation(0, S.syaw, 0)
rr.CFrame = rr.CFrame:Lerp(want, 0.3)
end)
else
pcall(function() hum.AutoRotate = true end)
end
local vec = Vector3.zero
if UIS:IsKeyDown(K.W) then vec = vec + Vector3.new(0, 0, -1) end
if UIS:IsKeyDown(K.S) then vec = vec + Vector3.new(0, 0, 1) end
if UIS:IsKeyDown(K.A) then vec = vec + Vector3.new(-1, 0, 0) end
if UIS:IsKeyDown(K.D) then vec = vec + Vector3.new(1, 0, 0) end
if UIS:IsKeyDown(K.Space) then hum.Jump = true end
if vec.Magnitude > 1 then vec = vec.Unit end
hum:Move(vec, true)
end)
S.killUI = true
toggleKillUI = function(force)
if force == nil then force = (S.killUI == false) end
S.killUI = force
killGui.Enabled = force
refreshButtons()
end
end
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
table.insert(lines, "NPC-копия: Shift - бег, Ctrl - медленно")
table.insert(lines, "NPC-копия: ПКМ - поворот камеры, зажат - NPC смотрит по камере")
new("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = PANEL, BorderSizePixel = 0,
Text = table.concat(lines, "\n"), TextColor3 = TXT, Font = Enum.Font.Code, TextSize = 12,
TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, pages["Клавиши"])
end
refreshButtons = function()
local function mark(b, on) if b then b.BackgroundColor3 = on and ON or BTN end end
mark(B.spec, S.mode == "spec" and S.view == "third")
mark(B.first, S.mode == "spec" and S.view == "first")
mark(B.lock, S.lock)
mark(B.control, npcCtl ~= nil)
B.control.Text = "Управлять NPC: " .. (npcCtl and "ВКЛ" or "ВЫКЛ")
mark(B.free, S.mode == "free")
mark(B.selfView, S.mode == "self")
mark(B.hide, S.hidden)
mark(B.night, S.timeLock and S.night)
mark(B.god, S.god)
mark(B.hideNPC, S.hideNPC)
mark(B.swap, S.swap)
mark(B.listPlayers, S.listPlayers)
B.hideNPC.Text = "Скрыть NPC: " .. (S.hideNPC and "ВКЛ" or "ВЫКЛ")
B.swap.Text = "Игроки = NPC: " .. (S.swap and "ВКЛ" or "ВЫКЛ")
B.listPlayers.Text = "Игроки в списке: " .. (S.listPlayers and "ДА" or "НЕТ")
B.killUI.Text = "KILL UI: " .. (S.killUI ~= false and "ВКЛ" or "ВЫКЛ")
mark(B.basic, S.basicAnim)
B.basic.Text = "Только базовая анимация: " .. (S.basicAnim and "ДА" or "НЕТ")
mark(B.sfx, S.sfx)
B.sfx.Text = "Звуки атаки: " .. (S.sfx and "ВКЛ" or "ВЫКЛ")
mark(B.puppet, puppet ~= nil)
B.puppet.Text = "Кукла (защита): " .. (puppet and "ВКЛ" or "ВЫКЛ")
mark(B.puppet2, puppet ~= nil)
B.puppet2.Text = "Кукла: " .. (puppet and "ВКЛ" or "ВЫКЛ")
B.smooth.Text = "Плавно: " .. (S.smooth and "ВКЛ" or "ВЫКЛ")
B.markers.Text = "Маркеры: " .. (S.markers and "ВКЛ" or "ВЫКЛ")
B.hideSelf.Text = "Скрывать и себя: " .. (S.hideSelf and "ДА" or "НЕТ")
B.info.Text = string.format("FOV: %d   Скорость: %d\nВремя: %s", math.floor(S.fov + 0.5), math.floor(S.speed + 0.5),
S.timeLock and (S.night and "ночь (фикс.)" or "день (фикс.)") or "по игре")
end
local acc, acc2, acc3 = 0, 0, 0
connect(RunService.Heartbeat, function(dt)
acc = acc + dt
acc2 = acc2 + dt
acc3 = acc3 + dt
if acc2 >= 1 then
acc2 = 0
if S.selfEntry or S.allEntry or S.swap or next(skins) then reconcileAsync() end
end
if acc3 >= 2 then
acc3 = 0
if S.hideNPC then updateNPCHide() end
end
for _, rec in pairs(VH) do
for d, info in pairs(rec.orig) do
if d.Parent and d[info[1]] ~= info[2] then d[info[1]] = info[2] end
end
end
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
-- ===================== КРАСНЫЙ ЭФФЕКТ БЕГА (Shift при управлении NPC) =====================
-- всё внутри одной функции, чтобы не упереться в лимит локальных переменных Luau
function G.initSprintFX()
local RED = Color3.fromRGB(255, 25, 35)
local sg = new("ScreenGui", {Name = "CineSprint", ResetOnSpawn = false, DisplayOrder = 997,
IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local ok = false
if gethui then ok = pcall(function() sg.Parent = gethui() end) and sg.Parent ~= nil end
if not ok then ok = pcall(function() sg.Parent = game:GetService("CoreGui") end) and sg.Parent ~= nil end
if not ok then sg.Parent = lp:WaitForChild("PlayerGui") end
G.sprintGui = sg
local root = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false}, sg)
-- красные полосы по краям экрана (мягкий градиент к центру)
local function edge(ax, rot)
local f = new("Frame", {Size = UDim2.fromScale(0.24, 1), Position = UDim2.fromScale(ax, 0),
AnchorPoint = Vector2.new(ax, 0), BackgroundColor3 = RED, BorderSizePixel = 0}, root)
new("UIGradient", {Rotation = rot, Transparency = NumberSequence.new({
NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})}, f)
return f
end
local edgeL, edgeR = edge(0, 0), edge(1, 180)
-- тонкие красные полосы сверху и снизу
local function bar(ay)
return new("Frame", {Size = UDim2.new(1, 0, 0, 5), Position = UDim2.fromScale(0, ay),
AnchorPoint = Vector2.new(0, ay), BackgroundColor3 = RED, BorderSizePixel = 0}, root)
end
local barT, barB = bar(0), bar(1)
-- красные линии скорости, разлетающиеся от центра к краям
local streaks = {}
for i = 1, 18 do
local f = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(100, 2),
BackgroundColor3 = RED, BorderSizePixel = 0, BackgroundTransparency = 1}, root)
streaks[i] = {f = f, t = math.random(), side = (i % 2 == 0) and 1 or -1, y = 0.05 + math.random() * 0.9,
len = math.random(90, 240), spd = 1.4 + math.random() * 1.4}
end
local k = 0
connect(RunService.RenderStepped, function(dt)
local c = npcCtl
local want = 0
if c and c.hum.Parent and not typing() and UIS:IsKeyDown(K.LeftShift) and c.hum.MoveDirection.Magnitude > 0.1 then
want = 1
end
k = k + (want - k) * math.min(dt * (want > k and 6 or 4), 1)
S.fovKick = 12 * k   -- небольшой «рывок» FOV при беге
if k < 0.02 then
root.Visible = false
return
end
root.Visible = true
local pulse = k * (0.85 + 0.15 * math.sin(os.clock() * 14))
edgeL.BackgroundTransparency = 1 - pulse
edgeR.BackgroundTransparency = 1 - pulse
barT.BackgroundTransparency = 1 - 0.9 * pulse
barB.BackgroundTransparency = 1 - 0.9 * pulse
for _, st in ipairs(streaks) do
st.t = st.t + dt * st.spd
if st.t >= 1 then
st.t = 0
st.y = 0.05 + math.random() * 0.9
st.len = math.random(90, 240)
end
st.f.Position = UDim2.fromScale(0.5 + st.side * (0.28 + 0.22 * st.t), st.y)
st.f.Size = UDim2.fromOffset(st.len * (0.4 + st.t), 2)
st.f.BackgroundTransparency = 1 - 0.85 * pulse * (1 - st.t)
end
end)
end
genv.__CinePanelCleanup = function()
exitAll()
unbindSink()
S.timeLock = false
G.clearHide()
toggleGod(false)
stopPuppet()
G.stopNpcCtl()
for orig in pairs(fights) do G.endFight(orig) end
pcall(function() RunService:UnbindFromRenderStep("CineShake") end)
if fxGui then fxGui:Destroy() end
reviveAll()
if fxFolder then fxFolder:Destroy() end
S.selfEntry, S.allEntry, S.swap, S.hideNPC = nil, nil, false, false
for ch in pairs(skins) do removeSkin(ch) end
G.vhClearAll()
for _, t in ipairs(swapTemplates) do
if t.src then pcall(function() t.src:Destroy() end) end
end
pcall(function() RunService:UnbindFromRenderStep("CineSkins") end)
if skinFolder then skinFolder:Destroy() end
if markerFolder then markerFolder:Destroy() end
pcall(function() RunService:UnbindFromRenderStep("CinePanel") end)
pcall(function() RunService:UnbindFromRenderStep("CineJoy") end)
for _, c in ipairs(conns) do c:Disconnect() end
if gui then gui:Destroy() end
if killGui then killGui:Destroy() end
if G.sprintGui then G.sprintGui:Destroy() end
S.fovKick = 0
genv.__CinePanelCleanup = nil
end
-- каждый шаг запуска в своём pcall: сбой одного шага (например, файл камер) больше не ломает весь запуск
function G.step(name, fn)
local ok, err = pcall(fn)
if not ok then
warn("[CinePanel] шаг «" .. name .. "»: " .. tostring(err))
G.initErr = (G.initErr or "") .. name .. "; "
end
end
G.step("камеры", loadCams)
G.step("библиотека", loadLib)
G.step("список моделей", rebuildLibList)
G.step("поиск NPC", scanNPCs)
G.step("список NPC", rebuildNPCList)
G.step("список камер", rebuildCamList)
G.step("вкладка", function() showTab("NPC") end)
G.step("кнопки", refreshButtons)
G.step("эффект бега", G.initSprintFX)
status("Готово. RightShift — скрыть/показать панель" .. (G.initErr and ("\nОшибки шагов: " .. G.initErr .. "см. консоль F9") or ""))
end, function(e) return debug.traceback(tostring(e), 2) end)
if not __cineOk then
warn("[CinePanel] ОШИБКА ЗАПУСКА: " .. tostring(__cineErr))
pcall(function()
game:GetService("StarterGui"):SetCore("SendNotification", {
Title = "CinePanel: ошибка запуска",
Text = string.sub(tostring(__cineErr), 1, 180),
Duration = 20,
})
end)
-- запасной вариант: показать ошибку прямо на экране (уведомления бывают заблокированы игрой)
pcall(function()
local g = Instance.new("ScreenGui")
g.Name = "CinePanel"
g.ResetOnSpawn = false
g.DisplayOrder = 999
local ok = false
if gethui then ok = pcall(function() g.Parent = gethui() end) and g.Parent ~= nil end
if not ok then ok = pcall(function() g.Parent = game:GetService("CoreGui") end) and g.Parent ~= nil end
if not ok then g.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end
local l = Instance.new("TextLabel")
l.Size = UDim2.new(0, 520, 0, 150)
l.Position = UDim2.fromOffset(20, 80)
l.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
l.TextColor3 = Color3.new(1, 1, 1)
l.TextWrapped = true
l.TextXAlignment = Enum.TextXAlignment.Left
l.TextYAlignment = Enum.TextYAlignment.Top
l.TextSize = 12
l.Font = Enum.Font.Code
l.Text = "CinePanel: ошибка запуска\n" .. string.sub(tostring(__cineErr), 1, 500)
l.Parent = g
task.delay(40, function() g:Destroy() end)
end)
end
