local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("HombreLobo")
local Config = require(shared:WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local ExperienceSettings = require(script.Parent:WaitForChild("ExperienceSettings"))
local network = shared:WaitForChild("Network")
local state = shared:WaitForChild("State")
local action = network:WaitForChild("Action")
local purchase = network:WaitForChild("Purchase")
local feedback = network:WaitForChild("Feedback")
local palette = {
    panel = Color3.fromRGB(22, 29, 32), text = Color3.fromRGB(235, 231, 213),
    muted = Color3.fromRGB(165, 176, 176), gold = Color3.fromRGB(212, 179, 109),
    green = Color3.fromRGB(63, 97, 81), red = Color3.fromRGB(121, 65, 61),
}
local screen = Instance.new("ScreenGui")
screen.Name, screen.ResetOnSpawn, screen.ZIndexBehavior = "HombreLoboHUD", false, Enum.ZIndexBehavior.Sibling
screen:SetAttribute("ShowAttackRange", false)
screen.Parent = player:WaitForChild("PlayerGui")
local safeRoot = Instance.new("Frame")
safeRoot.Name, safeRoot.Size = "SafeArea", UDim2.fromScale(1, 1)
safeRoot.BackgroundTransparency, safeRoot.BorderSizePixel = 1, 0
safeRoot.Parent = screen
local connections, stopped, cleaned = {}, false, false
local compactLayout = false
local touchLayout = UserInputService.TouchEnabled
local menuOpen = false
local syncMenu
local closeDialog, beginDialog
local activeDialog
local dialogue
local renderDirty, renderQueued, renderHUD = true, false, nil
local characterConnections, humanoidConnections, statsConnections, goldConnections = {}, {}, {}, {}
local currentCharacter, currentHumanoid, currentStats, currentGold
local settingsController
local resultCamera, closedResultId, resultPhaseSeenId = nil, 0, 0
local syncResultPresentation, stopResultCamera
local function settingsOpen()
    return settingsController ~= nil and settingsController:IsOpen()
end
local function disconnectAll(list)
    for _, connection in ipairs(list) do connection:Disconnect() end
    table.clear(list)
end
local function requestRender()
    if stopped then return end
    renderDirty = true
    if renderQueued or not renderHUD then return end
    renderQueued = true
    task.defer(function()
        renderQueued = false
        if stopped or not screen.Parent or not renderDirty then return end
        renderDirty = false
        renderHUD()
    end)
end
local function track(connection)
    table.insert(connections, connection)
    return connection
end

local function canAct()
    local character = player.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    local phase = state:GetAttribute("Phase")
    return player:GetAttribute("Alive") == true and hum ~= nil and hum.Health > 0
        and (phase == "Día" or phase == "Noche")
end
local function requestAction(kind)
    if not settingsOpen() and canAct() then action:FireServer(kind) end
end

local function roundCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 10)
    corner.Parent = parent
end
local function panel(name, size, position, anchor)
    local frame = Instance.new("Frame")
    frame.Name, frame.Size, frame.Position = name, size, position
    frame.AnchorPoint = anchor or Vector2.zero
    frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = palette.panel, 0.12, 0
    frame.Parent = safeRoot
    roundCorner(frame)
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Transparency, stroke.Parent = palette.gold, 0.65, frame
    return frame
end
local function label(parent, name, text, pos, size, fontSize, color)
    local l = Instance.new("TextLabel")
    l.Name, l.Text, l.Position, l.Size = name, text, pos, size
    l.BackgroundTransparency, l.BorderSizePixel = 1, 0
    l.TextColor3, l.TextSize, l.Font = color or palette.text, fontSize or 15, Enum.Font.Gotham
    l.TextXAlignment, l.TextYAlignment, l.TextWrapped = Enum.TextXAlignment.Left, Enum.TextYAlignment.Center, true
    l.Parent = parent
    return l
end
local function button(parent, text, position, size, color, callback)
    local b = Instance.new("TextButton")
    b.Text, b.Position, b.Size = text, position, size
    b.BackgroundColor3, b.TextColor3, b.TextSize = color or palette.green, palette.text, 15
    b.Font, b.BorderSizePixel, b.AutoButtonColor = Enum.Font.GothamBold, 0, true
    b.Parent = parent
    roundCorner(b, 8)
    b.TextWrapped = true
    local minimum = Instance.new("UISizeConstraint")
    minimum.MinSize, minimum.Parent = Vector2.new(44, 44), b
    track(b.Activated:Connect(callback))
    return b
end
local function setText(object, text)
    if object.Text ~= text then object.Text = text end
end
local function setVisible(object, visible)
    if object.Visible ~= visible then object.Visible = visible end
end
local function setEnabled(b, enabled)
    local transparency = enabled and 0 or 0.45
    if b.Active ~= enabled then b.Active = enabled end
    if b.AutoButtonColor ~= enabled then b.AutoButtonColor = enabled end
    if b.TextTransparency ~= transparency then b.TextTransparency = transparency end
    if b.BackgroundTransparency ~= transparency then b.BackgroundTransparency = transparency end
end

local top = panel("Estado", UDim2.new(0.92, 0, 0, 150), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0))
local constraint = Instance.new("UISizeConstraint")
constraint.MaxSize, constraint.Parent = Vector2.new(690, 150), top
label(top, "Titulo", "HOMBRE LOBO  /  BOSQUE DE LA LUNA", UDim2.fromOffset(16, 8), UDim2.new(1, -32, 0, 24), 17, palette.gold).Font = Enum.Font.GothamBold
local summary = label(top, "Resumen", "", UDim2.fromOffset(16, 36), UDim2.new(1, -32, 0, 25), 15)
local objectives = label(top, "Objetivos", "", UDim2.fromOffset(16, 63), UDim2.new(1, -32, 0, 24), 14, palette.muted)
local message = label(top, "Mensaje", "", UDim2.fromOffset(16, 91), UDim2.new(1, -32, 0, 50), 14)
-- A separate, persistent layer stays readable over a dead or respawned avatar.
local resultScreen = Instance.new("ScreenGui")
resultScreen.Name, resultScreen.ResetOnSpawn, resultScreen.DisplayOrder = "HombreLoboResultado", false, 20
resultScreen.ZIndexBehavior, resultScreen.ScreenInsets = Enum.ZIndexBehavior.Sibling, screen.ScreenInsets
resultScreen.Parent = player.PlayerGui
local resultRoot = Instance.new("Frame")
resultRoot.Name, resultRoot.Size = "SafeArea", UDim2.fromScale(1, 1)
resultRoot.BackgroundTransparency, resultRoot.BorderSizePixel, resultRoot.Parent = 1, 0, resultScreen
local resultPanel = panel("Resultado", UDim2.fromOffset(690, 154), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
resultPanel.Parent, resultPanel.Visible = resultRoot, false
local resultOutcome = label(resultPanel, "ResultadoPersonal", "", UDim2.fromOffset(16, 8), UDim2.new(1, -32, 0, 40), 32, palette.gold)
resultOutcome.Font = Enum.Font.GothamBold
local resultFaction = label(resultPanel, "BandoGanador", "", UDim2.fromOffset(16, 50), UDim2.new(1, -32, 0, 30), 20)
resultFaction.Font = Enum.Font.GothamBold
local resultNames = label(resultPanel, "Ganadores", "", UDim2.fromOffset(16, 82), UDim2.new(1, -32, 0, 58), 17, palette.muted)
for _, textLabel in ipairs({resultOutcome, resultFaction, resultNames}) do textLabel.TextXAlignment = Enum.TextXAlignment.Center end
local startPanel = panel("InicioPartida", UDim2.fromOffset(380, 174), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5))
startPanel.ZIndex, startPanel.Visible = 5, false
local startTitle = label(startPanel, "Titulo", "PRUEBA CON IA · TEMPORAL", UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 28), 18, palette.gold)
startTitle.Font, startTitle.ZIndex = Enum.Font.GothamBold, 6
local startDescription = label(startPanel, "Descripcion", "Una IA ocupa el segundo lugar. Explorá, combatí y probá una ronda completa.", UDim2.fromOffset(16, 43), UDim2.new(1, -32, 0, 55), 14)
startDescription.ZIndex = 6
local playAIButton = button(startPanel, "Jugar con IA", UDim2.fromOffset(16, 113), UDim2.new(1, -32, 0, 46), palette.green, function()
    local phase = state:GetAttribute("Phase")
    if state:GetAttribute("AIAvailable") and not state:GetAttribute("AIRequested")
        and (phase == "Esperando" or phase == "Lobby") then action:FireServer("PlayWithAI") end
end)
playAIButton.Name, playAIButton.ZIndex = "PlayWithAI", 6
setEnabled(playAIButton, false)

local bottom = panel("Controles", UDim2.new(0.92, 0, 0, 125), UDim2.new(0.5, 0, 1, -12), Vector2.new(0.5, 1))
local bc = Instance.new("UISizeConstraint")
bc.MaxSize, bc.Parent = Vector2.new(690, 160), bottom
local ability = button(bottom, "Habilidad [Q]", UDim2.new(0, 12, 0, 12), UDim2.new(0.5, -18, 0, 42), palette.green, function() requestAction("Ability") end)
local attackButton = button(bottom, "Atacar [F]", UDim2.new(0.5, 6, 0, 12), UDim2.new(0.5, -18, 0, 42), palette.red, function() requestAction("Attack") end)
local stats = label(bottom, "InventarioResumen", "", UDim2.fromOffset(12, 60), UDim2.new(1, -164, 0, 26), 13, palette.gold)
local tip = label(bottom, "Ayuda", "", UDim2.fromOffset(12, 88), UDim2.new(1, -164, 0, 28), 12, palette.muted)

local shop = panel("Mercado", UDim2.new(0.9, 0, 0, 310), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
shop.Visible, shop.ZIndex = false, 5
local sc = Instance.new("UISizeConstraint")
sc.MaxSize, sc.Parent = Vector2.new(10000, 10000), shop
label(shop, "Titulo", "MERCADO DE LA ALDEA", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 28), 18, palette.gold)
local shopStatus = label(shop, "Estado", "Las compras duran esta ronda.", UDim2.fromOffset(16, 44), UDim2.new(1, -32, 0, 40), 13, palette.muted)
local buying = false
local shopButtons = {}
for index, itemId in ipairs({"Potion", "Reroll", "Boots"}) do
    local item = Config.Shop[itemId]
    local b = button(shop, item.Name .. "  ·  " .. item.Price .. " Oro", UDim2.fromOffset(16, 88 + (index - 1) * 51), UDim2.new(1, -32, 0, 43), palette.green, function()
        if buying or not canAct() then return end
        buying = true
        local ok, success, detail = pcall(function() return purchase:InvokeServer(itemId) end)
        shopStatus.Text = ok and tostring(detail or "") or "No se pudo completar la compra."
        shopStatus.TextColor3 = ok and success and palette.gold or palette.text
        buying = false
    end)
    b.Name, b.ZIndex = "Comprar" .. itemId, 6
    table.insert(shopButtons, b)
end
local shopClose = button(shop, "Cerrar", UDim2.new(0, 16, 1, -54), UDim2.new(1, -32, 0, 44), palette.red, function() shop.Visible = false end)
shopClose.ZIndex = 6
for _, child in ipairs(shop:GetChildren()) do if child:IsA("TextLabel") then child.ZIndex = 6 end end

-- Panel lateral; su contenido se desplaza en pantallas pequeñas.
local inventoryPanel = panel("Inventario", UDim2.new(0.9, 0, 0.7, 0), UDim2.new(1, -14, 0.5, 0), Vector2.new(1, 0.5))
inventoryPanel.Visible, inventoryPanel.ZIndex = false, 5
local ic = Instance.new("UISizeConstraint")
ic.MaxSize, ic.MinSize, ic.Parent = Vector2.new(380, 440), Vector2.new(250, 200), inventoryPanel
label(inventoryPanel, "Titulo", "INVENTARIO Y MISIÓN", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 28), 17, palette.gold).ZIndex = 6
local inventoryScroll = Instance.new("ScrollingFrame")
inventoryScroll.Name, inventoryScroll.Position, inventoryScroll.Size = "Contenido", UDim2.fromOffset(12, 44), UDim2.new(1, -24, 1, -88)
inventoryScroll.BackgroundTransparency, inventoryScroll.BorderSizePixel = 1, 0
inventoryScroll.CanvasSize, inventoryScroll.ScrollBarThickness = UDim2.fromOffset(0, 386), 5
inventoryScroll.ScrollBarImageColor3, inventoryScroll.ZIndex = palette.gold, 6
inventoryScroll.Parent = inventoryPanel
local bladeSlot = label(inventoryScroll, "Espada", "", UDim2.fromOffset(2, 0), UDim2.new(1, -12, 0, 38), 14)
local bootsSlot = label(inventoryScroll, "Botas", "", UDim2.fromOffset(2, 42), UDim2.new(1, -12, 0, 36), 14)
local potionSlot = label(inventoryScroll, "Pociones", "", UDim2.fromOffset(2, 84), UDim2.new(1, -12, 0, 36), 14)
local abilitySlot = label(inventoryScroll, "Habilidad", "", UDim2.fromOffset(2, 126), UDim2.new(1, -12, 0, 40), 14)
local potionButton = button(inventoryScroll, "Usar poción [R]", UDim2.fromOffset(2, 174), UDim2.new(1, -12, 0, 36), palette.green, function() requestAction("UsePotion") end)
local missionSlot = label(inventoryScroll, "Mision", "", UDim2.fromOffset(2, 220), UDim2.new(1, -12, 0, 56), 13, palette.gold)
local hintSlot = label(inventoryScroll, "Pista", "", UDim2.fromOffset(2, 284), UDim2.new(1, -12, 0, 68), 13, palette.muted)
local rangeHelp = label(inventoryScroll, "Alcance", tostring(Config.Combat.Range) .. " studs en 3D, en cualquier dirección. Golpea al rival más cercano sin obstáculos.", UDim2.fromOffset(2, 354), UDim2.new(1, -12, 0, 32), 11, palette.muted)
local pistolSlot = label(inventoryScroll, "Pistola", "", UDim2.fromOffset(2, 0), UDim2.new(1, -12, 0, 42), 14)
local bookSlot = label(inventoryScroll, "Grimorio", "", UDim2.fromOffset(2, 0), UDim2.new(1, -12, 0, 42), 14)
for _, child in ipairs(inventoryScroll:GetChildren()) do if child:IsA("GuiObject") then child.ZIndex = 7 end end
local inventoryClose = button(inventoryPanel, "Cerrar [Esc]", UDim2.new(0, 14, 1, -54), UDim2.new(1, -28, 0, 44), palette.red, function() inventoryPanel.Visible = false end)
inventoryClose.ZIndex = 6
local function toggleInventory()
    if settingsController then settingsController:SetOpen(false) end
    if closeDialog then closeDialog() end
    inventoryPanel.Visible = not inventoryPanel.Visible
    if inventoryPanel.Visible then shop.Visible = false end
    menuOpen = false
    if syncMenu then syncMenu() end
end
local function toggleRange()
    screen:SetAttribute("ShowAttackRange", not screen:GetAttribute("ShowAttackRange"))
end
local inventoryToggle = button(bottom, "Inventario [B]", UDim2.new(1, -146, 0, 60), UDim2.fromOffset(134, 26), palette.green, toggleInventory)
inventoryToggle.TextSize = 12
local rangeToggle = button(bottom, "Alcance [V]", UDim2.new(1, -146, 0, 90), UDim2.fromOffset(134, 24), palette.green, toggleRange)
rangeToggle.TextSize = 12
local quickPotion = button(bottom, "Poción [R]", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 44), palette.green, function() requestAction("UsePotion") end)
quickPotion.TextSize = 12
local jumpButton = button(bottom, "Saltar", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 44), palette.green, function()
    local hum = currentHumanoid
    if hum and hum.Health > 0 and hum.FloorMaterial ~= Enum.Material.Air
        and hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)
jumpButton.Name, jumpButton.Visible = "Saltar", false
local defendButton = button(bottom, "Defender [C]", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 44), palette.green, function() requestAction("Defend") end)
local lungeButton = button(bottom, "Lanzarse [Z]", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 44), palette.red, function() requestAction("Lunge") end)
defendButton.Name, lungeButton.Name = "Defender", "Lanzarse"
local dodgeButton = button(bottom, "Esquivar [X]", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 44), palette.green, function() requestAction("Dodge") end)
dodgeButton.Name = "Esquivar"
local swapButton = button(bottom, "Arma [T]", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 44), palette.green, function() requestAction("SwapWeapon") end)
local reloadButton = button(bottom, "Recargar [G]", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 44), palette.green, function() requestAction("Reload") end)
local bookButton = button(bottom, "Grimorio [H]", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 44), palette.green, function() requestAction("ReadBook") end)
swapButton.Name, reloadButton.Name, bookButton.Name = "CambiarArma", "Recargar", "LeerGrimorio"
local menuScroll = Instance.new("ScrollingFrame")
menuScroll.Name, menuScroll.BackgroundTransparency, menuScroll.BorderSizePixel = "OpcionesMenu", 1, 0
menuScroll.CanvasSize, menuScroll.ScrollBarThickness = UDim2.fromOffset(0, 644), 4
menuScroll.ScrollBarImageColor3, menuScroll.ScrollingDirection = palette.gold, Enum.ScrollingDirection.Y
menuScroll.Parent = bottom
local menuToggle = button(safeRoot, "Menú ◀", UDim2.fromOffset(0, 0), UDim2.fromOffset(84, 44), palette.panel, function()
    if settingsController then settingsController:SetOpen(false) end
    if closeDialog then closeDialog() end
    inventoryPanel.Visible, shop.Visible = false, false
    menuOpen = not menuOpen
    syncMenu()
end)
menuToggle.Name, menuToggle.Visible, menuToggle.ZIndex = "AbrirMenu", touchLayout, 4
syncMenu = function()
    setVisible(bottom, not touchLayout or menuOpen)
    setVisible(menuScroll, touchLayout)
    setVisible(menuToggle, touchLayout)
    setVisible(jumpButton, touchLayout)
    setText(menuToggle, menuOpen and "Menú ▶" or "Menú ◀")
    requestRender()
end
syncMenu()
stats.Parent, tip.Parent = safeRoot, safeRoot
local profileStatus = label(safeRoot, "EstadoOro", "", UDim2.fromOffset(0, 0), UDim2.fromOffset(320, 32), 11, palette.muted)
profileStatus.Visible = false
local shopScroll = Instance.new("ScrollingFrame")
shopScroll.Name, shopScroll.BackgroundTransparency, shopScroll.BorderSizePixel = "Articulos", 1, 0
shopScroll.CanvasSize, shopScroll.ScrollBarThickness = UDim2.fromOffset(0, 160), 5
shopScroll.ScrollBarImageColor3, shopScroll.ZIndex, shopScroll.Parent = palette.gold, 6, shop
for _, b in ipairs(shopButtons) do b.Parent, b.ZIndex = shopScroll, 7 end
ability.Name, attackButton.Name = "Habilidad", "Atacar"
inventoryToggle.Name, rangeToggle.Name = "AbrirInventario", "MostrarAlcance"
quickPotion.Name, potionButton.Name = "UsarPocionRapida", "UsarPocion"
shopClose.Name, inventoryClose.Name = "CerrarMercado", "CerrarInventario"
local function place(object, x, y, width, height)
    object.AnchorPoint, object.Position, object.Size = Vector2.zero, UDim2.fromOffset(x, y), UDim2.fromOffset(width, height)
end
-- Keep Roblox's Tool hotbar from covering controls inside either drawer.
local backpackBeforeModal, backpackHidden = nil, false
local function restoreBackpack()
    if backpackBeforeModal == nil then return end
    local ok = pcall(function()
        if StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack) ~= backpackBeforeModal then
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, backpackBeforeModal)
        end
    end)
    if ok then backpackBeforeModal, backpackHidden = nil, false end
end
local function syncBackpack()
    if not (touchLayout or inventoryPanel.Visible or shop.Visible or settingsOpen() or (dialogue and dialogue.Visible)) then restoreBackpack(); return end
    if backpackHidden then return end
    local ok, enabled = pcall(function()
        return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
    end)
    if not ok then return end
    if backpackBeforeModal == nil then backpackBeforeModal = enabled end
    if not enabled then backpackHidden = true; return end
    backpackHidden = pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    end)
end
-- The native player list covers compact action controls; restore its original
-- enabled state when space is available or when this HUD is removed.
local playerListBeforeHud, playerListHidden = nil, false
local function restorePlayerList()
    if playerListBeforeHud == nil then return end
    local ok = pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, playerListBeforeHud) end)
    if ok then playerListBeforeHud, playerListHidden = nil, false end
end
local function syncPlayerList()
    if not (compactLayout or touchLayout or inventoryPanel.Visible or shop.Visible or settingsOpen() or (dialogue and dialogue.Visible)) then restorePlayerList(); return end
    if playerListHidden then return end
    local ok, enabled = pcall(function() return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) end)
    if not ok then return end
    if playerListBeforeHud == nil then playerListBeforeHud = enabled end
    playerListHidden = not enabled or pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
end
local function modalChanged()
    syncBackpack()
    syncPlayerList()
    requestRender()
end
track(inventoryPanel:GetPropertyChangedSignal("Visible"):Connect(modalChanged))
track(shop:GetPropertyChangedSignal("Visible"):Connect(modalChanged))
dialogue = panel("DialogoGuia", UDim2.fromOffset(380, 220), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
dialogue.Visible, dialogue.ZIndex = false, 5
local dialogueTitle = label(dialogue, "Titulo", "ELAR · GUÍA", UDim2.fromOffset(14, 8), UDim2.new(1, -82, 0, 44), 16, palette.gold)
local dialogueText = label(dialogue, "Descripcion", "", UDim2.fromOffset(14, 62), UDim2.new(1, -28, 1, -76), 15)
dialogueTitle.ZIndex, dialogueText.ZIndex = 6, 6
local dialogueClose = button(dialogue, "X", UDim2.new(1, -58, 0, 8), UDim2.fromOffset(44, 44), palette.red, function() closeDialog() end)
dialogueClose.Name, dialogueClose.ZIndex = "CerrarDialogo", 6
closeDialog = function(keepServerHold)
    local previous = activeDialog
    activeDialog = nil
    dialogue.Visible = false
    if previous then
        if previous.tween then previous.tween:Cancel(); previous.tween:Destroy() end
        local camera = previous.camera
        if camera.Parent and camera.CameraType == Enum.CameraType.Scriptable then
            camera.CFrame, camera.FieldOfView, camera.Focus = previous.frame, previous.fov, previous.focus
            local subject = previous.subject
            camera.CameraSubject = subject and subject.Parent and subject or currentHumanoid
            camera.CameraType = previous.kind
        end
        if previous.kindName == "Shop" then shop.Visible = false end
        if not keepServerHold then action:FireServer("DialogClose", previous.token) end
    end
    modalChanged()
end
beginDialog = function(detail, kindName)
    if settingsController then settingsController:SetOpen(false) end
    closeDialog(true)
    if typeof(detail) ~= "table" or typeof(detail.npc) ~= "Instance" then return end
    local npc = detail.npc:IsA("Model") and detail.npc or detail.npc:FindFirstAncestorOfClass("Model")
    local root = npc and npc.PrimaryPart
    local head = npc and npc:FindFirstChild("Head")
    local camera = Workspace.CurrentCamera
    if not root or not head or not camera or not canAct() then return end
    activeDialog = {npc = npc, root = root, camera = camera, frame = camera.CFrame, kind = camera.CameraType,
        subject = camera.CameraSubject, fov = camera.FieldOfView, focus = camera.Focus, kindName = kindName,
        token = detail.dialogToken, expires = os.clock() + 19}
    local focus = head.Position + Vector3.new(0, 0.2, 0)
    local destination = focus + root.CFrame.LookVector * 8 + Vector3.new(0, 1.5, 0)
    local parameters = RaycastParams.new()
    parameters.FilterType, parameters.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, {npc, currentCharacter}
    local hit = Workspace:Raycast(focus, destination - focus, parameters)
    if hit then destination = hit.Position + (focus - destination).Unit * 0.7 end
    camera.CameraType = Enum.CameraType.Scriptable
    camera.Focus = CFrame.new(focus)
    activeDialog.tween = TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {CFrame = CFrame.lookAt(destination, focus), FieldOfView = 58})
    activeDialog.tween:Play()
    if kindName == "Guide" then
        dialogueText.Text = tostring(detail.message or "Abrí dos cofres y volvé a hablar conmigo.")
        dialogue.Visible = true
    end
    modalChanged()
end
track(shop:GetPropertyChangedSignal("Visible"):Connect(function()
    if not shop.Visible and activeDialog and activeDialog.kindName == "Shop" then closeDialog() end
end))
track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() if activeDialog then closeDialog() end end))
track(dialogue:GetPropertyChangedSignal("Visible"):Connect(modalChanged))
-- Per-observer visibility: the lobby is a mirador from above and hidden below.
-- Reuse the HUD's low-frequency maintenance instead of another frame callback.
local lobby = Workspace:WaitForChild("Lobby")
local lobbyParts, lobbyGuis, lobbyHidden = {}, {}, nil
local function watchLobbyObject(object)
    if object:IsA("BasePart") then
        lobbyParts[object] = object.LocalTransparencyModifier
        if lobbyHidden then object.LocalTransparencyModifier = 1 end
    elseif object:IsA("SurfaceGui") or object:IsA("BillboardGui") then
        lobbyGuis[object] = object.Enabled
        if lobbyHidden then object.Enabled = false end
    end
end
for _, object in ipairs(lobby:GetDescendants()) do watchLobbyObject(object) end
track(lobby.DescendantAdded:Connect(watchLobbyObject))
track(lobby.DescendantRemoving:Connect(function(object)
    if lobbyParts[object] ~= nil then object.LocalTransparencyModifier = lobbyParts[object] end
    if lobbyGuis[object] ~= nil then object.Enabled = lobbyGuis[object] end
    lobbyParts[object], lobbyGuis[object] = nil, nil
end))
local function updateLobbyVisibility()
    local camera = Workspace.CurrentCamera
    local platform = lobby:FindFirstChild("Plataforma")
    if not camera or not platform then return end
    local hidden = camera.CFrame.Position.Y < (platform:GetAttribute("TopY") or platform.Position.Y)
    if lobbyHidden == hidden then return end
    lobbyHidden = hidden
    for object, original in pairs(lobbyParts) do if object.Parent then object.LocalTransparencyModifier = hidden and 1 or original end end
    for object, original in pairs(lobbyGuis) do if object.Parent then object.Enabled = not hidden and original end end
end
-- Keep the native finger joystick; hide its separate jump button on touch devices.
-- The menu provides jump without adding a movement/render loop or disabling controls.
local nativeJumpRecords = {}
local function hideNativeJump(object)
    if not touchLayout or not object:IsA("GuiButton") or object.Name ~= "JumpButton" then return end
    local touchGui = object:FindFirstAncestor("TouchGui")
    if not touchGui or touchGui.Parent ~= player.PlayerGui or nativeJumpRecords[object] then return end
    local record = {visible = object.Visible, connections = {}}
    nativeJumpRecords[object] = record
    local function hide()
        if not stopped and object.Visible then record.visible = true; object.Visible = false end
    end
    table.insert(record.connections, object:GetPropertyChangedSignal("Visible"):Connect(hide))
    table.insert(record.connections, object.Destroying:Connect(function()
        disconnectAll(record.connections)
        nativeJumpRecords[object] = nil
    end))
    hide()
end
track(player.PlayerGui.DescendantAdded:Connect(hideNativeJump))
for _, object in ipairs(player.PlayerGui:GetDescendants()) do hideNativeJump(object) end
local lastViewport = Vector2.zero
local function layout(viewport)
    local width, height = math.floor(viewport.X), math.floor(viewport.Y)
    if width < 1 or height < 1 then return end
    lastViewport = viewport
    local landscape = height < 520 and width > height
    compactLayout = width < 650 or height < 520 or UserInputService.TouchEnabled
    bc.MaxSize = Vector2.new(690, touchLayout and 328 or 160)
    local topWidth = compactLayout and (landscape and math.min(440, width - 20) or width - 20) or math.min(690, width - 20)
    local headerCompact = compactLayout and height < 700
    local topHeight = headerCompact and 72 or (compactLayout and 118 or 150)
    local topX = compactLayout and 10 or (width - topWidth) / 2
    local headerWidth = topWidth - 24
    local controlSide = ExperienceSettings.get("ControlSide")
    local offsetX, offsetY = ExperienceSettings.get("OffsetX"), ExperienceSettings.get("OffsetY")
    place(top, topX, 8, topWidth, topHeight)
    local title = top:FindFirstChild("Titulo")
    title.Visible = not headerCompact
    title.TextSize = compactLayout and 14 or 17
    place(title, 12, 5, headerWidth, 24)
    place(summary, 12, headerCompact and 4 or 30, headerWidth, compactLayout and 28 or 26)
    place(objectives, 12, headerCompact and 30 or 62, headerWidth, 20)
    place(message, 12, headerCompact and 50 or (compactLayout and 85 or 90), headerWidth, headerCompact and 18 or (compactLayout and 30 or 50))
    local resultWidth = math.min(690, width - 20)
    local resultHeight = landscape and 112 or (compactLayout and 150 or 164)
    place(resultPanel, (width - resultWidth) / 2, 8, resultWidth, resultHeight)
    place(resultOutcome, 12, 5, resultWidth - 24, landscape and 30 or 42)
    place(resultFaction, 12, landscape and 36 or 50, resultWidth - 24, landscape and 24 or 32)
    place(resultNames, 12, landscape and 61 or 85, resultWidth - 24, landscape and 44 or (resultHeight - 92))
    resultOutcome.TextSize, resultFaction.TextSize, resultNames.TextSize = landscape and 24 or 32, compactLayout and 17 or 20, compactLayout and 14 or 17
    local startWidth = math.min(430, width - 20)
    place(startPanel, (width - startWidth) / 2, math.max(8, math.min(math.max(topHeight + 20, height * 0.45 - 87), height - 186)), startWidth, 174)
    message.TextSize = headerCompact and 12 or 14
    message.TextTruncate = headerCompact and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None
    local controlsY, drawerX, drawerY, drawerWidth, drawerHeight
    if touchLayout then
        local menuWidth = math.min(176, math.floor(width * 0.46))
        -- Leave the lower-right settings gear its own space, including on short
        -- touch viewports and when the user moves the action menu downwards.
        local menuY = math.clamp(topHeight + 20 + offsetY, 8, math.max(8, height - 184))
        local dropdownY = menuY + 50
        local menuHeight = math.min(328, math.max(56, height - dropdownY - 78))
        controlsY = menuY
        local left = controlSide == "Izquierda"
        local menuX = math.clamp((left and 10 or width - 94) + offsetX, 10, math.max(10, width - 94))
        local dropdownX = math.clamp((left and 10 or width - menuWidth - 10) + offsetX, 10, math.max(10, width - menuWidth - 10))
        place(menuToggle, menuX, menuY, 84, 44)
        place(bottom, dropdownX, dropdownY, menuWidth, menuHeight)
        bottom.BackgroundTransparency = 0.08
        bottom:FindFirstChildOfClass("UIStroke").Enabled = true
        bottom.ZIndex, menuScroll.ZIndex = 3, 3
        place(menuScroll, 6, 6, menuWidth - 12, menuHeight - 12)
        local rows = ExperienceSettings.get("ActionOrder") == "Combate primero"
            and {attackButton, defendButton, dodgeButton, lungeButton, ability, inventoryToggle, quickPotion, swapButton, reloadButton, bookButton, rangeToggle, jumpButton}
            or {inventoryToggle, ability, attackButton, defendButton, dodgeButton, lungeButton, swapButton, reloadButton, bookButton, rangeToggle, quickPotion, jumpButton}
        for index, b in ipairs(rows) do
            b.Parent, b.ZIndex, b.TextSize = menuScroll, 4, 13
            place(b, 0, (index - 1) * 54, menuWidth - 20, 48)
        end
        menuScroll.CanvasSize = UDim2.fromOffset(0, #rows * 54 - 4)
        inventoryToggle.Text = "Inventario"
        place(stats, topX, topHeight + 20, math.max(0, width - 114), 22)
        place(profileStatus, topX, topHeight + 44, math.max(0, width - 114), 32)
        place(tip, topX, topHeight + 79, math.max(0, width - 114), 34)
        drawerWidth, drawerHeight = math.min(380, width - 20), math.min(440, height - 20)
        drawerX, drawerY = (width - drawerWidth) / 2, (height - drawerHeight) / 2
    elseif compactLayout then
        controlsY = math.min(math.max(84, height - (landscape and 244 or 254)), math.max(8, height - 160))
        bc.MaxSize = Vector2.new(690, 266)
        local controlsX = math.clamp((controlSide == "Izquierda" and 10 or width - 154) + offsetX, 10, math.max(10, width - 154))
        local compactY = math.clamp(controlsY - 98 + offsetY, 8, math.max(8, height - 324))
        place(bottom, controlsX, compactY, 144, 256)
        bottom.BackgroundTransparency = 1
        bottom:FindFirstChildOfClass("UIStroke").Enabled = false
        place(ability, 0, 0, 70, 48)
        place(attackButton, 74, 0, 70, 48)
        place(inventoryToggle, 0, 52, 70, 44)
        place(rangeToggle, 74, 52, 70, 44)
        place(quickPotion, 0, 100, 144, 44)
        place(defendButton, 0, 152, 70, 44)
        place(lungeButton, 74, 152, 70, 44)
        place(dodgeButton, 0, 204, 144, 44)
        swapButton.Visible, reloadButton.Visible, bookButton.Visible = false, false, false
        ability.TextSize, attackButton.TextSize = 12, 12
        inventoryToggle.TextSize, rangeToggle.TextSize = 11, 11
        inventoryToggle.Text = "Inventario"
        place(stats, topX, topHeight + 20, topWidth, 22)
        place(profileStatus, topX, topHeight + 44, topWidth, 32)
        place(tip, topX, topHeight + 79, topWidth, 34)
        drawerWidth = math.min(380, width - 20)
        if landscape then
            drawerHeight = math.min(440, height - 20)
            drawerX, drawerY = (width - drawerWidth) / 2, (height - drawerHeight) / 2
        else
            drawerX, drawerY = (width - drawerWidth) / 2, topHeight + 86
            drawerHeight = math.min(440, controlsY - 12 - drawerY)
            if drawerHeight < 200 then
                drawerY = math.max(8, controlsY - 12 - 200)
                drawerHeight = math.min(200, math.max(0, controlsY - 12 - drawerY))
            end
        end
    else
        local controlsWidth = math.min(690, width - 88)
        local baseX = controlSide == "Izquierda" and 10 or (controlSide == "Derecha" and width - controlsWidth - 78 or (width - controlsWidth) / 2)
        local controlsX = math.clamp(baseX + offsetX, 10, math.max(10, width - controlsWidth - 78))
        controlsY = math.clamp(height - 204 + offsetY, 8, math.max(8, height - 202))
        bc.MaxSize = Vector2.new(690, 196)
        place(bottom, controlsX, controlsY, controlsWidth, 192)
        bottom.BackgroundTransparency = 0.12
        bottom:FindFirstChildOfClass("UIStroke").Enabled = true
        local actionWidth = (controlsWidth - 42) / 4
        for index, b in ipairs({ability, attackButton, defendButton, lungeButton}) do place(b, 12 + (index - 1) * (actionWidth + 6), 10, actionWidth, 48) end
        place(inventoryToggle, controlsWidth - 342, 64, 110, 44)
        place(rangeToggle, controlsWidth - 228, 64, 110, 44)
        place(quickPotion, controlsWidth - 114, 64, 102, 44)
        for index, b in ipairs({dodgeButton, swapButton, reloadButton, bookButton}) do place(b, 12 + (index - 1) * ((controlsWidth - 24) / 4), 112, (controlsWidth - 42) / 4, 44) end
        swapButton.Visible, reloadButton.Visible, bookButton.Visible = true, true, true
        ability.TextSize, attackButton.TextSize = 15, 15
        inventoryToggle.TextSize, rangeToggle.TextSize = 12, 12
        inventoryToggle.Text = "Inventario [B]"
        place(stats, controlsX + 12, controlsY + 64, controlsWidth - 368, 44)
        place(tip, controlsX + 12, controlsY + 160, controlsWidth - 24, 24)
        place(profileStatus, topX, topHeight + 20, topWidth, 32)
        drawerWidth, drawerHeight = 380, math.min(440, height - 24)
        drawerX, drawerY = width - drawerWidth - 14, (height - drawerHeight) / 2
    end
    if not touchLayout then
        for _, b in ipairs({ability, attackButton, defendButton, dodgeButton, lungeButton, swapButton, reloadButton, bookButton, inventoryToggle, rangeToggle, quickPotion}) do b.Parent = bottom end
    else
        swapButton.Visible, reloadButton.Visible, bookButton.Visible = true, true, true
    end
    syncMenu()
    drawerHeight = math.max(0, drawerHeight)
    ic.MinSize = Vector2.new(math.min(250, drawerWidth), math.min(200, drawerHeight))
    place(inventoryPanel, drawerX, drawerY, drawerWidth, drawerHeight)
    place(shop, drawerX, drawerY, drawerWidth, drawerHeight)
    local dialogueWidth, dialogueHeight = math.min(380, width - 20), math.min(220, height - 20)
    place(dialogue, (width - dialogueWidth) / 2, (height - dialogueHeight) / 2, dialogueWidth, dialogueHeight)
    local inventoryTitle = inventoryPanel:FindFirstChild("Titulo")
    local shopTitle = shop:FindFirstChild("Titulo")
    inventoryTitle.Visible, shopTitle.Visible = drawerHeight >= 60, drawerHeight >= 60
    inventoryTitle.TextSize, shopTitle.TextSize = compactLayout and 14 or 16, compactLayout and 14 or 16
    inventoryClose.Visible, shopClose.Visible = drawerHeight >= 44, drawerHeight >= 44
    inventoryScroll.Visible, shopScroll.Visible = drawerHeight >= 116, drawerHeight >= 168
    shopStatus.Visible = drawerHeight >= 112
    place(inventoryTitle, 14, 8, drawerWidth - 82, 44)
    place(shopTitle, 14, 8, drawerWidth - 82, 44)
    place(inventoryScroll, 12, 60, drawerWidth - 24, math.max(0, drawerHeight - 72))
    inventoryScroll.CanvasSize = UDim2.fromOffset(0, 600)
    place(bladeSlot, 2, 0, drawerWidth - 38, 42)
    place(pistolSlot, 2, 48, drawerWidth - 38, 42)
    place(bookSlot, 2, 96, drawerWidth - 38, 42)
    place(bootsSlot, 2, 144, drawerWidth - 38, 42)
    place(potionSlot, 2, 192, drawerWidth - 38, 42)
    place(abilitySlot, 2, 240, drawerWidth - 38, 44)
    place(potionButton, 2, 292, drawerWidth - 38, 44)
    place(missionSlot, 2, 346, drawerWidth - 38, 56)
    place(hintSlot, 2, 412, drawerWidth - 38, 72)
    place(rangeHelp, 2, 492, drawerWidth - 38, 100)
    local closeY = math.min(8, math.max(0, drawerHeight - 44))
    inventoryClose.Text, shopClose.Text = "X", "X"
    inventoryClose.TextSize, shopClose.TextSize = 20, 20
    place(inventoryClose, drawerWidth - 58, closeY, 44, 44)
    place(shopClose, drawerWidth - 58, closeY, 44, 44)
    place(shopStatus, 14, 60, drawerWidth - 28, 40)
    place(shopScroll, 14, 108, drawerWidth - 28, math.max(0, drawerHeight - 120))
    for index, b in ipairs(shopButtons) do place(b, 0, (index - 1) * 54, drawerWidth - 36, 48) end
    local opacityOffset = 0.88 - ExperienceSettings.get("PanelOpacity") / 100
    for _, frame in ipairs({top, startPanel, shop, inventoryPanel, dialogue}) do
        frame.BackgroundTransparency = math.clamp(0.12 + opacityOffset, 0, 0.6)
    end
    bottom.BackgroundTransparency = not touchLayout and compactLayout and 1
        or math.clamp((touchLayout and 0.08 or 0.12) + opacityOffset, 0, 0.6)
    if settingsController then settingsController:Layout(viewport) end
    syncPlayerList()
end

settingsController = ExperienceSettings.mount({
    root = safeRoot, palette = palette,
    onOpen = function()
        closeDialog()
        inventoryPanel.Visible, shop.Visible, menuOpen = false, false, false
        syncMenu()
    end,
    onVisibilityChanged = modalChanged,
    onChanged = function()
        lastViewport = Vector2.zero
        requestRender()
    end,
})

local toastUntil, toastText = 0, ""
track(feedback.OnClientEvent:Connect(function(kind, detail)
    if kind == "Shop" and canAct() then
        menuOpen = false
        syncMenu()
        inventoryPanel.Visible = false
        beginDialog(detail, "Shop")
        shop.Visible, shopStatus.Text = true, "Las pociones se guardan en tu inventario."
    elseif kind == "Guide" and canAct() then
        menuOpen = false
        syncMenu()
        beginDialog(detail, "Guide")
        inventoryPanel.Visible, shop.Visible = false, false
    elseif kind == "Message" and typeof(detail) == "string" then
        toastText, toastUntil = detail, os.clock() + 5
        requestRender()
    end
end))
-- Toda entrada de acciones se centraliza aquí; el servidor decide si es válida.
local function bind(name, callback, ...)
    ContextActionService:BindAction(name, function(_, inputState)
        if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
        if inputState == Enum.UserInputState.Begin then callback() end
        return Enum.ContextActionResult.Sink
    end, false, ...)
end
bind("HLAbility", function() requestAction("Ability") end, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
bind("HLAttack", function() requestAction("Attack") end, Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
bind("HLInventory", toggleInventory, Enum.KeyCode.B)
bind("HLPotion", function() requestAction("UsePotion") end, Enum.KeyCode.R)
bind("HLRange", toggleRange, Enum.KeyCode.V)
bind("HLDefend", function() requestAction("Defend") end, Enum.KeyCode.C, Enum.KeyCode.ButtonL2)
bind("HLDodge", function() requestAction("Dodge") end, Enum.KeyCode.X, Enum.KeyCode.ButtonB)
bind("HLLunge", function() requestAction("Lunge") end, Enum.KeyCode.Z, Enum.KeyCode.ButtonX)
bind("HLSwapWeapon", function() requestAction("SwapWeapon") end, Enum.KeyCode.T)
bind("HLReload", function() requestAction("Reload") end, Enum.KeyCode.G)
bind("HLReadBook", function() requestAction("ReadBook") end, Enum.KeyCode.H)
ContextActionService:BindAction("HLClosePanels", function(_, inputState)
    if inputState == Enum.UserInputState.Begin and (inventoryPanel.Visible or shop.Visible or menuOpen or activeDialog or settingsOpen()) then
        if settingsController then settingsController:SetOpen(false) end
        closeDialog()
        inventoryPanel.Visible, shop.Visible = false, false
        menuOpen = false
        syncMenu()
        return Enum.ContextActionResult.Sink
    end
    return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Escape)

local roleNames = { HombreLobo = "Hombre Lobo", Ejecutor = "Ejecutor", Lobby = "Lobby", Espectador = "Espectador" }
local RESULT_CAMERA_BINDING = "HLResultCamera"
local function restoreResultView(record)
    local camera = record.camera
    if camera and camera.Parent and camera.CameraType == Enum.CameraType.Scriptable and camera.CFrame == record.lastFrame then
        camera.CFrame, camera.Focus, camera.FieldOfView = record.frame, record.focus, record.fov
        camera.CameraSubject = currentHumanoid and currentHumanoid.Parent and currentHumanoid
            or (record.subject and record.subject.Parent and record.subject or nil)
        camera.CameraType = record.kind
    end
end
stopResultCamera = function(closeRound)
    local record = resultCamera
    resultCamera = nil
    RunService:UnbindFromRenderStep(RESULT_CAMERA_BINDING)
    if record then
        if closeRound then closedResultId = math.max(closedResultId, record.roundId) end
        restoreResultView(record)
    end
    resultPanel:SetAttribute("CameraActive", false)
end
local function applyResultView()
    local record = resultCamera
    if not record then return end
    if stopped or Workspace:GetServerTimeNow() >= record.endsAt then stopResultCamera(true); requestRender(); return end
    local camera = Workspace.CurrentCamera
    if not camera then return end
    if camera ~= record.camera then
        restoreResultView(record)
        record.camera, record.frame, record.focus, record.fov = camera, camera.CFrame, camera.Focus, camera.FieldOfView
        record.subject, record.kind = camera.CameraSubject, camera.CameraType
    end
    local aspect = math.max(0.25, camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y))
    local distance = math.max(18, record.width / (2 * math.tan(math.rad(29)) * aspect))
    local focus = record.position + Vector3.new(0, 1.5, 0)
    local frame = CFrame.lookAt(focus + Vector3.new(0, 4, -distance), focus)
    camera.CameraType, camera.FieldOfView = Enum.CameraType.Scriptable, 58
    camera.CFrame, camera.Focus = frame, CFrame.new(focus)
    record.lastFrame = frame
    resultPanel:SetAttribute("CameraActive", true)
end
syncResultPresentation = function(serverNow)
    local resultId = ClientState.get("ResultRoundId", 0)
    local endsAt = ClientState.get("ResultEndsAt", 0)
    local phase = state:GetAttribute("Phase")
    if phase == "Resultado" then resultPhaseSeenId = math.max(resultPhaseSeenId, resultId)
    elseif resultId > 0 and resultId <= resultPhaseSeenId then closedResultId = math.max(closedResultId, resultId) end
    local visible = resultId > closedResultId and endsAt > serverNow
    setVisible(resultPanel, visible)
    setVisible(top, not visible)
    resultPanel:SetAttribute("ResultRoundId", resultId)
    resultPanel:SetAttribute("ResultEndsAt", endsAt)
    if not visible then stopResultCamera(false); return end
    local outcome = ClientState.get("ResultOutcome", "Resultado")
    local winnerRole = ClientState.get("ResultWinnerRole", "")
    local names, count = ClientState.get("ResultWinnerNames", ""), ClientState.get("ResultWinnerCount", 0)
    setText(resultOutcome, string.upper(outcome))
    resultOutcome.TextColor3 = outcome == "Victoria" and palette.gold or (outcome == "Derrota" and Color3.fromRGB(239, 149, 136) or palette.text)
    setText(resultFaction, winnerRole == "HombreLobo" and "GANÓ EL LOBO" or (winnerRole == "Ejecutor" and "GANARON LOS EJECUTORES" or "RONDA TERMINADA"))
    setText(resultNames, names ~= "" and ((count == 1 and "Ganó " or "Ganaron ") .. names) or "Esperando la próxima ronda")
    resultPanel:SetAttribute("ResultOutcome", outcome)
    local position = ClientState.get("ResultCameraPosition", Vector3.zero)
    if typeof(position) ~= "Vector3" or position == Vector3.zero then stopResultCamera(false); return end
    if resultCamera and resultCamera.roundId == resultId then resultCamera.endsAt = endsAt; return end
    stopResultCamera(false)
    closeDialog()
    if settingsController then settingsController:SetOpen(false) end
    inventoryPanel.Visible, shop.Visible = false, false
    menuOpen = false
    if syncMenu then syncMenu() end
    resultCamera = {roundId = resultId, endsAt = endsAt, position = position, width = math.max(8, count * 6)}
    applyResultView()
    -- The sole camera callback exists only during this finite ceremony; it
    -- runs after Roblox's camera so automatic respawn cannot steal the view.
    RunService:BindToRenderStep(RESULT_CAMERA_BINDING, Enum.RenderPriority.Camera.Value + 1, applyResultView)
end
local boundNames = {"HLAbility", "HLAttack", "HLInventory", "HLPotion", "HLRange", "HLDefend", "HLDodge", "HLLunge", "HLSwapWeapon", "HLReload", "HLReadBook", "HLClosePanels"}
local function cleanup()
    if cleaned then return end
    cleaned, stopped = true, true
    stopResultCamera(false)
    resultScreen:Destroy()
    if settingsController then settingsController:Destroy(); settingsController = nil end
    closeDialog()
    for object, original in pairs(lobbyParts) do if object.Parent then object.LocalTransparencyModifier = original end end
    for object, original in pairs(lobbyGuis) do if object.Parent then object.Enabled = original end end
    table.clear(lobbyParts); table.clear(lobbyGuis)
    restoreBackpack()
    restorePlayerList()
    local hum = currentHumanoid
    local canJump = hum ~= nil and hum.Health > 0 and hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
        and ((hum.UseJumpPower and hum.JumpPower > 0) or (not hum.UseJumpPower and hum.JumpHeight > 0))
    for object, record in pairs(nativeJumpRecords) do
        disconnectAll(record.connections)
        if object.Parent then object.Visible = record.visible and canJump end
    end
    table.clear(nativeJumpRecords)
    for _, name in ipairs(boundNames) do ContextActionService:UnbindAction(name) end
    disconnectAll(connections)
    disconnectAll(characterConnections)
    disconnectAll(humanoidConnections)
    disconnectAll(statsConnections)
    disconnectAll(goldConnections)
    currentCharacter, currentHumanoid, currentStats, currentGold = nil, nil, nil, nil
end
track(screen.Destroying:Connect(cleanup))
track(script.Destroying:Connect(function() cleanup(); screen:Destroy() end))
-- Replaceable-instance connections are released before each rebind.
local function bindHumanoid(humanoid)
    if humanoid == currentHumanoid then return end
    disconnectAll(humanoidConnections)
    currentHumanoid = humanoid
    if humanoid then
        table.insert(humanoidConnections, humanoid.HealthChanged:Connect(requestRender))
        table.insert(humanoidConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(requestRender))
        table.insert(humanoidConnections, humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(requestRender))
    end
    requestRender()
end
local function bindCharacter(character)
    if character == currentCharacter then return end
    disconnectAll(characterConnections)
    bindHumanoid(nil)
    currentCharacter = character
    if character then
        local function childChanged(child)
            if child:IsA("Humanoid") then bindHumanoid(character:FindFirstChildOfClass("Humanoid")) end
            if child:IsA("Humanoid") or child:IsA("Tool") then requestRender() end
        end
        table.insert(characterConnections, character.ChildAdded:Connect(childChanged))
        table.insert(characterConnections, character.ChildRemoved:Connect(childChanged))
        bindHumanoid(character:FindFirstChildOfClass("Humanoid"))
        -- Respawn can reset CoreGui; retry only while a modal needs to hide it.
        if touchLayout or inventoryPanel.Visible or shop.Visible or settingsOpen() then backpackHidden = false end
        if compactLayout or touchLayout or inventoryPanel.Visible or shop.Visible or settingsOpen() then playerListHidden = false end
    end
    requestRender()
end
local function bindGold(gold)
    if gold == currentGold then return end
    disconnectAll(goldConnections)
    currentGold = gold
    if gold then table.insert(goldConnections, gold.Changed:Connect(requestRender)) end
    requestRender()
end
local function bindStats(leaderstats)
    if leaderstats == currentStats then return end
    disconnectAll(statsConnections)
    bindGold(nil)
    currentStats = leaderstats
    if leaderstats then
        local function childChanged(child)
            if child.Name == "Oro" then bindGold(leaderstats:FindFirstChild("Oro")); requestRender() end
        end
        table.insert(statsConnections, leaderstats.ChildAdded:Connect(childChanged))
        table.insert(statsConnections, leaderstats.ChildRemoved:Connect(childChanged))
        bindGold(leaderstats:FindFirstChild("Oro"))
    end
    requestRender()
end
track(ClientState.changed:Connect(requestRender))
track(state.AttributeChanged:Connect(requestRender))
track(player.AttributeChanged:Connect(function(name)
    if name == "Alive" or name == "ProfileMode" or name == "ProfileSaveError" then requestRender() end
end))
track(player.CharacterAdded:Connect(bindCharacter))
track(player.CharacterRemoving:Connect(function(character)
    if character == currentCharacter then bindCharacter(nil) end
end))
track(player:GetPropertyChangedSignal("Character"):Connect(function() bindCharacter(player.Character) end))
local function playerChildChanged(child)
    if child.Name == "leaderstats" then bindStats(player:FindFirstChild("leaderstats")) end
end
track(player.ChildAdded:Connect(playerChildChanged))
track(player.ChildRemoved:Connect(playerChildChanged))
track(safeRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(requestRender))
track(screen:GetAttributeChangedSignal("ShowAttackRange"):Connect(requestRender))
bindCharacter(player.Character)
bindStats(player:FindFirstChild("leaderstats"))

local displayedCooldown, displayedDefendCooldown, displayedLungeCooldown = 0, 0, 0
local displayedNightCountdown, displayedWolfCountdown = 0, 0
local function secondsTo(attribute, serverNow)
    return math.max(0, math.ceil((tonumber(state:GetAttribute(attribute)) or 0) - serverNow))
end
renderHUD = function()
    if safeRoot.AbsoluteSize ~= lastViewport then layout(safeRoot.AbsoluteSize) end
    local seconds = state:GetAttribute("Seconds") or 0
    local role = ClientState.get("Role", "Lobby")
    local practice = state:GetAttribute("AIActive") and " · con IA" or (state:GetAttribute("Practice") and " · Práctica" or "")
    local phase = state:GetAttribute("Phase")
    local winningRole = phase == "Resultado" and state:GetAttribute("WinnerRole") or ""
    local resultTitle = winningRole == "HombreLobo" and "GANÓ EL LOBO"
        or (winningRole == "Ejecutor" and "GANARON LOS EJECUTORES" or nil)
    setText(summary, resultTitle or string.format("%s%s  ·  %02d:%02d  ·  %s", phase or "Cargando", practice, math.floor(seconds / 60), seconds % 60, roleNames[role] or role))
    setText(objectives, string.format("Estatuas restantes: %d  ·  Bosque: %s", state:GetAttribute("StatuesRemaining") or 0, tostring(state:GetAttribute("Seed") or "-")))
    local serverNow = Workspace:GetServerTimeNow()
    syncResultPresentation(serverNow)
    local nightCountdown = secondsTo("NightTransitionEndsAt", serverNow)
    local wolfCountdown = secondsTo("WolfAttackReadyAt", serverNow)
    displayedNightCountdown, displayedWolfCountdown = nightCountdown, wolfCountdown
    if phase == "Resultado" then
        setText(message, state:GetAttribute("Message") or "")
    elseif phase == "Día" and nightCountdown > 0 then
        setText(message, string.format("El lobo se transforma en %d s · El sol se oculta…", nightCountdown))
    elseif phase == "Noche" and wolfCountdown > 0 then
        setText(message, string.format("Transformación… El lobo ataca en %d s", wolfCountdown))
    else
        setText(message, os.clock() < toastUntil and toastText or (state:GetAttribute("Message") or ""))
    end
    local choosingAI = state:GetAttribute("AIAvailable") == true and (phase == "Esperando" or phase == "Lobby")
        and (state:GetAttribute("HumanCount") or 0) < Config.Round.MinimumPlayers
    setVisible(startPanel, choosingAI)
    local aiRequested = state:GetAttribute("AIRequested") == true
    setEnabled(playAIButton, choosingAI and not aiRequested and state:GetAttribute("HumanCount") == 1)
    setText(playAIButton, aiRequested and "Preparando partida…" or "Jugar con IA")
    setText(startDescription, aiRequested and "La IA completa los dos participantes. Esperá la cuenta regresiva del lobby."
        or "Una IA ocupa el segundo lugar. Si entra otra persona antes de empezar, jugás con ella.")
    local readyAt = ClientState.get("AbilityReadyAt", 0)
    local cooldown = math.max(0, math.ceil(readyAt - serverNow))
    displayedCooldown = cooldown
    setText(ability, cooldown > 0 and ("Recarga: " .. cooldown .. " s") or (compactLayout and "Habilidad" or "Habilidad [Q]"))
    local claws = role == "HombreLobo" and state:GetAttribute("FullMoon") == true
    local transforming = ClientState.get("Transforming", false)
    setText(attackButton, transforming and "Transformando…" or (claws and (compactLayout and "Garras" or "Garras [F]") or (compactLayout and "Espada" or "Espada [F]")))
    local defendCooldown = math.max(0, math.ceil(ClientState.get("DefendReadyAt", 0) - serverNow))
    local lungeCooldown = math.max(0, math.ceil(ClientState.get("LungeReadyAt", 0) - serverNow))
    displayedDefendCooldown, displayedLungeCooldown = defendCooldown, lungeCooldown
    setText(defendButton, defendCooldown > 0 and ("Defensa · " .. defendCooldown .. " s") or (compactLayout and "Defender" or "Defender [C]"))
    setText(dodgeButton, defendCooldown > 0 and ("Esquiva · " .. defendCooldown .. " s") or (compactLayout and "Esquivar" or "Esquivar [X]"))
    setText(lungeButton, lungeCooldown > 0 and ("Salto · " .. lungeCooldown .. " s") or (compactLayout and "Lanzarse" or "Lanzarse [Z]"))
    local gold = currentGold
    local blade = ClientState.get("HasBlade", false)
    local pistol = ClientState.get("HasPistol", false)
    local hasBook = ClientState.get("HasBook", false)
    local ammo = ClientState.get("Ammo", 0)
    local reloading = ClientState.get("Reloading", false)
    local boots = ClientState.get("Boots", false)
    local potions = ClientState.get("Potion", 0)
    local currentAbility = ClientState.get("Ability", "Ninguna")
    setText(stats, compactLayout and string.format("%d Oro  ·  %d pociones", gold and gold.Value or 0, potions)
        or string.format("%d Oro  ·  %s\n%d pociones", gold and gold.Value or 0, currentAbility, potions))
    local profileMode = player:GetAttribute("ProfileMode")
    local savePending = player:GetAttribute("ProfileSaveError") == true
    setVisible(profileStatus, profileMode == "Temporary" or profileMode == "LoadFailed" or savePending)
    if profileMode == "Temporary" then
        setText(profileStatus, RunService:IsStudio() and "Oro temporal (Studio)" or "Oro temporal: sólo esta sesión.")
    elseif profileMode == "LoadFailed" then
        setText(profileStatus, "No se pudo cargar tu oro. En esta sesión no se guarda.")
    elseif savePending then
        setText(profileStatus, "Guardado de oro pendiente: reintentando.")
    end
    local hint = ClientState.get("Hint", "")
    setText(tip, hint and hint ~= "" and hint or (compactLayout and "Tocá los objetos para interactuar." or "E: interactuar · Q: habilidad · F: atacar"))
    local character = currentCharacter
    local equipped = character and character:FindFirstChild("EspadaPlata")
    local gunEquipped = character and character:FindFirstChild("Pistola")
    if gunEquipped and not claws then setText(attackButton, compactLayout and ("Disparar · " .. ammo) or ("Disparar [F] · " .. ammo)) end
    setText(pistolSlot, "PISTOLA\n" .. (pistol and ((gunEquipped and "Equipada" or "En tu mochila") .. " · " .. ammo .. "/6 · T cambia arma") or "Recompensa al abrir dos cofres"))
    setText(bookSlot, "GRIMORIO\n" .. (hasBook and "H: sostener y leer tu pista" or "Abrí dos cofres y hablá con Elar"))
    setText(reloadButton, reloading and "Recargando…" or (compactLayout and "Recargar" or "Recargar [G]"))
    setText(bladeSlot, "ESPADA DE PLATA\n" .. (blade and (equipped and "Equipada" or "En tu mochila") or "Buscala en un cofre"))
    setText(bootsSlot, "BOTAS\n" .. (boots and "Equipadas" or "Disponibles en el mercado"))
    setText(potionSlot, "POCIONES\n" .. tostring(potions) .. " guardadas · recuperan 55 de vida")
    setText(abilitySlot, "HABILIDAD\n" .. currentAbility .. (cooldown > 0 and (" · recarga " .. cooldown .. " s") or ""))
    local chests = tonumber(ClientState.get("ChestsOpened", 0)) or 0
    setText(missionSlot, string.format("MISIÓN DEL GUÍA  %d/2 cofres\n%s", math.min(chests, 2), chests >= 2 and "Volvé a hablar con el guía." or "Abrí dos cofres y volvé a la aldea."))
    setText(hintSlot, hint and hint ~= "" and ("PISTA\n" .. hint) or "PISTA\nEl guía te mostrará una estatua después de la misión.")
    local hum = currentHumanoid
    setEnabled(jumpButton, hum ~= nil and hum.Health > 0 and hum:GetStateEnabled(Enum.HumanoidStateType.Jumping))
    local alive = canAct()
    setEnabled(ability, alive and cooldown == 0)
    setEnabled(attackButton, alive and not transforming and not reloading and (claws or (gunEquipped and pistol and ammo > 0) or (not gunEquipped and blade)))
    setEnabled(swapButton, alive and not claws and not transforming and not reloading and pistol)
    setEnabled(reloadButton, alive and not claws and not transforming and not reloading and gunEquipped ~= nil and pistol and ammo < 6)
    setEnabled(bookButton, alive and not claws and not transforming and not reloading and hasBook)
    setText(rangeHelp, "Espada/garras: " .. Config.Combat.Range .. " studs en 3D.\nPistola: 60 studs, apunta hacia donde mira tu personaje; G recarga.\nC: bloqueo. X: esquiva. Comparten recarga; un golpe recibido durante la ventana causa daño ×0,2. Z: salto del lobo nocturno.")
    setEnabled(defendButton, alive and not transforming and defendCooldown == 0)
    setEnabled(dodgeButton, alive and not transforming and defendCooldown == 0 and hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air)
    setEnabled(lungeButton, alive and claws and not transforming and lungeCooldown == 0)
    local potionReady = alive and potions > 0 and hum ~= nil and hum.Health < hum.MaxHealth
    setEnabled(potionButton, potionReady)
    setEnabled(quickPotion, potionReady)
    setText(quickPotion, compactLayout and ("Poción · " .. potions) or "Poción [R]")
    setVisible(tip, not shop.Visible and not inventoryPanel.Visible and not menuOpen and not dialogue.Visible and not settingsOpen())
    setText(rangeToggle, screen:GetAttribute("ShowAttackRange") and (compactLayout and "Alcance: sí" or "Alcance: sí [V]") or (compactLayout and "Alcance" or "Alcance [V]"))
    if not alive and shop.Visible then shop.Visible = false end
end
requestRender()
local nextTimeCheck = 0
while not stopped and screen.Parent do
    -- Retry CoreGui only until the requested modal state is reached.
    local modal = touchLayout or inventoryPanel.Visible or shop.Visible or dialogue.Visible or settingsOpen()
    if (modal and not backpackHidden) or (not modal and backpackBeforeModal ~= nil) then syncBackpack() end
    local hideList = compactLayout or modal
    if (hideList and not playerListHidden) or (not hideList and playerListBeforeHud ~= nil) then syncPlayerList() end
    local now = os.clock()
    if resultPanel.Visible and Workspace:GetServerTimeNow() >= ClientState.get("ResultEndsAt", 0) then requestRender() end
    updateLobbyVisibility()
    if now >= nextTimeCheck then
        nextTimeCheck = now + 1
        if toastUntil > 0 and now >= toastUntil then toastUntil = 0; requestRender() end
        local serverNow = Workspace:GetServerTimeNow()
        local cooldown = math.max(0, math.ceil(ClientState.get("AbilityReadyAt", 0) - serverNow))
        local defendCooldown = math.max(0, math.ceil(ClientState.get("DefendReadyAt", 0) - serverNow))
        local lungeCooldown = math.max(0, math.ceil(ClientState.get("LungeReadyAt", 0) - serverNow))
        local nightCountdown, wolfCountdown = secondsTo("NightTransitionEndsAt", serverNow), secondsTo("WolfAttackReadyAt", serverNow)
        if cooldown ~= displayedCooldown or defendCooldown ~= displayedDefendCooldown or lungeCooldown ~= displayedLungeCooldown
            or nightCountdown ~= displayedNightCountdown or wolfCountdown ~= displayedWolfCountdown then requestRender() end
    end
    if activeDialog then
        local root = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
        if not canAct() or not root or not activeDialog.root.Parent or not activeDialog.npc:IsDescendantOf(Workspace)
            or (root.Position - activeDialog.root.Position).Magnitude > 20 or now >= activeDialog.expires then closeDialog() end
    end
    if renderDirty then requestRender() end
    task.wait(0.2)
end
cleanup()
