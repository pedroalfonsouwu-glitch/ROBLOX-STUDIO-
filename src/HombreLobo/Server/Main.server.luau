-- El servidor decide roles, daño, objetivos, compras y recompensas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("HombreLobo")
local Config = require(Shared:WaitForChild("Config"))
local WorldGenerator = require(script.Parent:WaitForChild("WorldGenerator"))
local CharacterVisuals = require(script.Parent:WaitForChild("CharacterVisuals"))
local NPCBehavior = require(script.Parent:WaitForChild("NPCBehavior"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local Persistence = require(script.Parent:WaitForChild("Persistence"))
local BotController = require(script.Parent:WaitForChild("BotController"))

local network = Instance.new("Folder")
network.Name = "Network"
network.Parent = Shared
local state = Instance.new("Folder")
state.Name = "State"
state.Parent = Shared
local action = Instance.new("RemoteEvent")
action.Name = "Action"
action.Parent = network
local feedback = Instance.new("RemoteEvent")
feedback.Name = "Feedback"
feedback.Parent = network
local purchase = Instance.new("RemoteFunction")
purchase.Name = "Purchase"
purchase.Parent = network
PlayerState.attach(network)
local persistence = Persistence.start(Players, { StartingGold = Config.Economy.StartingGold })
local privateInventories = Instance.new("Folder")
privateInventories.Name, privateInventories.Parent = "HombreLoboInventories", game:GetService("ServerStorage")
local function setPrivate(player, key, value) PlayerState.set(player, key, value) end

local rng = Random.new()
local roster, records = {}, {}
local world, winner, npcController
local roundId = 0
local running, practice, deploying = false, false, false
local aiRequester, aiActor, aiController
local botHolds, objectiveCallbacks = {}, {}
local lobbyPosition = Vector3.new(0, 124, 0)
local stageLeases, stageLeaseExpiry = {}, nil

local function releaseStageLeases(expected)
    if expected and stageLeases ~= expected then return end
    local releasing = stageLeases
    stageLeases = {}
    if stageLeaseExpiry then task.cancel(stageLeaseExpiry); stageLeaseExpiry = nil end
    for root, lease in pairs(releasing) do
        -- A respawn or replaced root belongs to a new character; leave it alone.
        if root.Parent and lease.actor.Character == lease.character and root:IsDescendantOf(lease.character) then
            root.Anchored = lease.wasAnchored
        end
    end
end
local function holdStageActor(actor, character)
    local root = character:FindFirstChild("HumanoidRootPart")
    local hum = character:FindFirstChildOfClass("Humanoid")
    if actor.Character ~= character or not root or not hum or hum.Health <= 0 or stageLeases[root] then return end
    stageLeases[root] = {actor = actor, character = character, wasAnchored = root.Anchored}
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    root.Anchored = true
    if not stageLeaseExpiry then
        local leased = stageLeases
        -- A finite fallback releases roots even if round teardown fails.
        stageLeaseExpiry = task.delay(10.5, function()
            if stageLeases ~= leased then return end
            stageLeaseExpiry = nil
            releaseStageLeases(leased)
        end)
    end
end

local function clearPrivateResult(actor)
    setPrivate(actor, "ResultRoundId", 0)
    setPrivate(actor, "ResultOutcome", "")
    setPrivate(actor, "ResultWinnerRole", "")
    setPrivate(actor, "ResultWinnerNames", "")
    setPrivate(actor, "ResultWinnerCount", 0)
    setPrivate(actor, "ResultEndsAt", 0)
    setPrivate(actor, "ResultCameraPosition", Vector3.zero)
end
local function setState(key, value)
    -- A faction result is public only after the round has ended.
    if key == "Phase" and value ~= "Resultado" then
        releaseStageLeases()
        if state:GetAttribute("Phase") == "Resultado" then
            for actor in pairs(records) do clearPrivateResult(actor) end
        end
        state:SetAttribute("WinnerRole", "")
        state:SetAttribute("WinnerNames", "")
        state:SetAttribute("ResultRoundId", 0)
        state:SetAttribute("ResultEndsAt", 0)
    end
    state:SetAttribute(key, value)
end
setState("Phase", "Esperando")
setState("Seconds", 0)
setState("StatuesRemaining", 0)
setState("Seed", 0)
setState("Message", "Esperando jugadores")
setState("Practice", false)
setState("FullMoon", false)
setState("NightTransitionEndsAt", 0)
setState("WolfAttackReadyAt", 0)
setState("WinnerRole", "")
setState("AIAvailable", Config.Round.AllowAI == true)
setState("AIRequested", false)
setState("AIActive", false)

-- Two finite native tweens animate the sunset; there is no permanent update loop.
-- Reuse the place's atmosphere and Roblox's built-in sun/moon textures.
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
    atmosphere = Instance.new("Atmosphere")
    atmosphere.Name, atmosphere.Density, atmosphere.Offset = "Atmosphere", 0.28, 0.15
    atmosphere.Color, atmosphere.Decay = Color3.new(0.57, 0.66, 0.7), Color3.new(0.22, 0.28, 0.35)
    atmosphere.Parent = Lighting
end
local sky = Lighting:FindFirstChildOfClass("Sky")
if not sky then
    sky = Instance.new("Sky")
    sky.Name, sky.CelestialBodiesShown = "HombreLoboSky", true
    sky.Parent = Lighting
end
local dayAtmosphere = {
    Density = atmosphere.Density, Haze = atmosphere.Haze,
    Color = atmosphere.Color, Decay = atmosphere.Decay,
}
local nightAtmosphere = {
    Density = 0.4, Haze = 1.8,
    Color = Color3.fromRGB(125, 143, 176), Decay = Color3.fromRGB(43, 54, 82),
}
local environmentTweens = {}
local function cancelNightTransition()
    for _, tween in ipairs(environmentTweens) do tween:Cancel(); tween:Destroy() end
    table.clear(environmentTweens)
    setState("NightTransitionEndsAt", 0)
    setState("WolfAttackReadyAt", 0)
end
local function setDayEnvironment()
    cancelNightTransition()
    Lighting.ClockTime, Lighting.Brightness = 16, 2.3
    Lighting.Ambient = Color3.fromRGB(105, 108, 106)
    for property, value in pairs(dayAtmosphere) do atmosphere[property] = value end
end
local function beginNightTransition(seconds)
    cancelNightTransition()
    if seconds <= 0 then return end
    setState("NightTransitionEndsAt", Workspace:GetServerTimeNow() + seconds)
    setState("Message", "El sol se oculta y la niebla anuncia la luna llena.")
    local info = TweenInfo.new(seconds, Enum.EasingStyle.Linear)
    -- Advance through sunset instead of tweening 16 backwards to midnight.
    -- ClockTime 24 wraps to 0, the existing night endpoint.
    environmentTweens[1] = TweenService:Create(Lighting, info, {
        ClockTime = 24, Brightness = 1.6, Ambient = Color3.fromRGB(63, 72, 97),
    })
    environmentTweens[2] = TweenService:Create(atmosphere, info, nightAtmosphere)
    for _, tween in ipairs(environmentTweens) do tween:Play() end
end

local function isBot(actor)
    return typeof(actor) == "table" and actor.IsBot == true
end
local function actorReady(actor)
    return isBot(actor) or persistence:IsReady(actor)
end
local function publicActor(actor)
    return isBot(actor) and actor.Character or actor
end
local function sendPrivate(actor, kind, data)
    if typeof(actor) == "Instance" and actor:IsA("Player") and actor.Parent == Players then
        feedback:FireClient(actor, kind, data)
    end
end

local function lobbyPart(name, size, position, color)
    local p = Instance.new("Part")
    p.Name, p.Anchored, p.Size, p.Position, p.Color = name, true, size, position, color
    p.CastShadow = false
    p.Material = Enum.Material.WoodPlanks
    p.Parent = Workspace:WaitForChild("Lobby")
    return p
end
local lobbyPlatform = lobbyPart("Plataforma", Vector3.new(84, 2, 64), Vector3.new(0, 119, 0), Color3.fromRGB(61, 55, 47))
lobbyPlatform:SetAttribute("TopY", 120)
lobbyPlatform.Material, lobbyPlatform.Transparency = Enum.Material.Glass, 0.35
for _, edge in ipairs({
    {Vector3.new(84, 6, 2), Vector3.new(0, 123, -31)},
    {Vector3.new(84, 6, 2), Vector3.new(0, 123, 31)},
    {Vector3.new(2, 6, 64), Vector3.new(-41, 123, 0)},
    {Vector3.new(2, 6, 64), Vector3.new(41, 123, 0)},
}) do
    lobbyPart("Baranda", edge[1], edge[2], Color3.fromRGB(87, 76, 60))
end
local sign = lobbyPart("Cartel", Vector3.new(26, 10, 1), Vector3.new(0, 130, 24), Color3.fromRGB(30, 41, 39))
local board = Instance.new("SurfaceGui")
board.Face = Enum.NormalId.Front
board.Parent = sign
local text = Instance.new("TextLabel")
text.Size = UDim2.fromScale(1, 1)
text.BackgroundTransparency = 1
text.Text = "HOMBRE LOBO\nBosque de la luna"
text.TextColor3 = Color3.fromRGB(226, 216, 180)
text.TextScaled, text.Font = true, Enum.Font.GothamBold
text.Parent = board

local function tell(player, message)
    sendPrivate(player, "Message", message)
end
local function awardGold(player, amount)
    local gold = records[player].gold
    local before = gold.Value
    gold.Value = math.min(Persistence.MaxGold, before + amount)
    return gold.Value - before
end
local function humanoidOf(player)
    local character = player.Character
    if not character then return nil, nil end
    return character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end
local function eligible(player)
    local hum, root = humanoidOf(player)
    return running and not deploying and not winner and roster[player] and actorReady(player) and player:GetAttribute("Alive") == true
        and hum ~= nil and hum.Health > 0 and root ~= nil
end
local function near(player, part, distance)
    local _, root = humanoidOf(player)
    return root and part and (root.Position - part.Position).Magnitude <= distance
end
local function refreshSpeed(player)
    local record = records[player]
    local hum = humanoidOf(player)
    if not hum or not record then return end
    local wolfNight = PlayerState.get(player, "Role") == "HombreLobo" and state:GetAttribute("FullMoon")
        and player.Character and player.Character:GetAttribute("Transformed") == true
    hum.WalkSpeed = (record.transforming and 8 or (wolfNight and Config.Player.WolfSpeed or Config.Player.WalkSpeed))
        + (record.boots and 3 or 0) + (record.sprinting and 10 or 0)
end
local function releaseLunge(record)
    local root = record.lungeRoot
    record.lungeRoot = nil
    if record.lungeVelocity then record.lungeVelocity:Destroy(); record.lungeVelocity = nil end
    if record.lungeAttachment then record.lungeAttachment:Destroy(); record.lungeAttachment = nil end
    if root and root.Parent then
        if not root.Anchored then
            local hum = root.Parent:FindFirstChildOfClass("Humanoid")
            local velocity = root.AssemblyLinearVelocity
            local horizontal = hum and hum.MoveDirection * hum.WalkSpeed or Vector3.zero
            root.AssemblyLinearVelocity = horizontal + Vector3.new(0, velocity.Y, 0)
        end
        pcall(function()
            if root.Parent:GetAttribute("AIControlled") == true then root:SetNetworkOwner(nil) else root:SetNetworkOwnershipAuto() end
        end)
    end
end
local function releaseDodge(record)
    local root = record.dodgeRoot
    record.dodgeRoot = nil
    if record.dodgeVelocity then record.dodgeVelocity:Destroy(); record.dodgeVelocity = nil end
    if record.dodgeAttachment then record.dodgeAttachment:Destroy(); record.dodgeAttachment = nil end
    if root and root.Parent then
        if not root.Anchored then
            local hum = root.Parent:FindFirstChildOfClass("Humanoid")
            local velocity = root.AssemblyLinearVelocity
            local horizontal = hum and hum.MoveDirection * hum.WalkSpeed or Vector3.zero
            root.AssemblyLinearVelocity = horizontal + Vector3.new(0, velocity.Y, 0)
        end
        pcall(function()
            if root.Parent:GetAttribute("AIControlled") == true then root:SetNetworkOwner(nil) else root:SetNetworkOwnershipAuto() end
        end)
    end
end
local function resetCombat(player)
    local record = records[player]
    if not record then return end
    record.combatGeneration = (record.combatGeneration or 0) + 1
    for worker in pairs(record.combatTasks) do task.cancel(worker) end
    table.clear(record.combatTasks)
    releaseLunge(record)
    releaseDodge(record)
    record.transforming, record.reloading, record.defendUntil, record.defendReady, record.lungeReady = false, false, 0, 0, 0
    record.attackReady, record.bookReady = 0, 0
    setPrivate(player, "Transforming", false)
    setPrivate(player, "DefendReadyAt", 0)
    setPrivate(player, "LungeReadyAt", 0)
    setPrivate(player, "Reloading", false)
end
local function combatLater(player, seconds, callback, motionCleanup)
    local record = records[player]
    if not record then return end
    local token, character, generation = roundId, player.Character, record.combatGeneration
    local worker
    worker = task.delay(seconds, function()
        record.combatTasks[worker] = nil
        if records[player] == record and roundId == token and record.combatGeneration == generation
            and player.Character == character and (motionCleanup or eligible(player)) then callback(record, character) end
    end)
    record.combatTasks[worker] = true
end
local function assignAbilities(player)
    local record = records[player]
    if not record then return end
    local first = Config.Abilities[rng:NextInteger(1, #Config.Abilities)]
    record.abilities = {first}
    if first == "Fortuna" then
        -- Variante del ejemplo: Fortuna conserva una segunda habilidad garantizada.
        table.insert(record.abilities, Config.Abilities[rng:NextInteger(1, #Config.Abilities - 1)])
    end
    record.abilityReady = 0
    setPrivate(player, "Ability", table.concat(record.abilities, " + "))
    setPrivate(player, "AbilityReadyAt", 0)
end
local function clearEffects(player, preserveWolfAura)
    local record = records[player]
    if record then
        record.sprinting = false
        record.effectId = (record.effectId or 0) + 1
    end
    local character = player.Character
    if character then
        for _, item in ipairs(character:GetDescendants()) do
            if item.Name == "AbilityShield" or item.Name == "AbilityLight"
                or (item.Name == "WolfAura" and not preserveWolfAura) then
                item:Destroy()
            end
        end
    end
    if not preserveWolfAura then
        resetCombat(player)
        if character then CharacterVisuals.restore(character) end
        local hum = humanoidOf(player)
        if hum then hum.MaxHealth = Config.Player.Health; hum.Health = math.min(hum.Health, hum.MaxHealth) end
    end
    refreshSpeed(player)
end
local function removeBlade(player)
    local record = records[player]
    if not record then return end
    record.inventory.SilverBlade.Value = false
    record.inventory.Pistol.Value = false
    record.inventory.Grimoire.Value = false
    record.inventory.Ammo.Value = 0
    setPrivate(player, "HasBlade", false)
    setPrivate(player, "HasPistol", false)
    setPrivate(player, "HasBook", false)
    for _, container in pairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") then
                    local id = item:GetAttribute("HombreLoboItem")
                    if id == "SilverBlade" or id == "Pistol" or id == "Grimoire" then item:Destroy() end
                end
            end
        end
    end
end
local function resetInventory(player)
    local record = records[player]
    if not record then return end
    record.boots = false
    record.inventory.Boots.Value = false
    record.inventory.Potion.Value = 0
    removeBlade(player)
end
local function clawsActive(player)
    local record = records[player]
    return record and not record.transforming and PlayerState.get(player, "Role") == "HombreLobo"
        and state:GetAttribute("FullMoon") == true and player.Character
        and player.Character:GetAttribute("Transformed") == true
end
local function bladeAllowed(player)
    return not (PlayerState.get(player, "Role") == "HombreLobo" and state:GetAttribute("FullMoon") == true)
end
local function watchBlade(player, blade)
    local record = records[player]
    if not record or record.bladeConnections[blade] then return end
    local hooks = {}
    record.bladeConnections[blade] = hooks
    hooks[1] = blade.Equipped:Connect(function()
        local handle = blade:FindFirstChild("Handle")
        if records[player] ~= record or not eligible(player) or not bladeAllowed(player)
            or blade.Parent ~= player.Character or not handle or not handle:IsA("BasePart") then return end
        local now = os.clock()
        if now - record.lastDrawAt < 0.25 then return end
        record.lastDrawAt = now
        feedback:FireAllClients("BladeDrawFX", { player = publicActor(player), character = player.Character })
    end)
    hooks[2] = blade.Destroying:Connect(function()
        for _, hook in ipairs(hooks) do hook:Disconnect() end
        record.bladeConnections[blade] = nil
    end)
end
local function giveBlade(player)
    local record = records[player]
    if not record or not bladeAllowed(player) then return false end
    record.inventory.SilverBlade.Value = true
    setPrivate(player, "HasBlade", true)
    local backpack = player:FindFirstChildOfClass("Backpack")
    local hum = humanoidOf(player)
    if backpack and hum then
        local existing = backpack:FindFirstChild("EspadaPlata")
            or (player.Character and player.Character:FindFirstChild("EspadaPlata"))
        if not existing then
            existing = CharacterVisuals.createBlade()
            watchBlade(player, existing)
            existing.Parent = backpack
        else
            watchBlade(player, existing)
        end
        if existing.Parent == backpack then hum:EquipTool(existing) end
    end
    return true
end
local function ownedTool(player, name, id)
    local character, backpack = player.Character, player:FindFirstChildOfClass("Backpack")
    local tool = character and character:FindFirstChild(name) or (backpack and backpack:FindFirstChild(name))
    local handle = tool and tool:FindFirstChild("Handle")
    if tool and tool:IsA("Tool") and tool:GetAttribute("HombreLoboItem") == id
        and handle and handle:IsA("BasePart") then return tool, backpack end
end
local function givePistol(player)
    local record = records[player]
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not record or not backpack or not bladeAllowed(player) or record.inventory.Pistol.Value then return false end
    local pistol = CharacterVisuals.createPistol()
    pistol.Parent = backpack
    record.inventory.Pistol.Value = true
    record.inventory.Ammo.Value = Config.Combat.PistolCapacity
    setPrivate(player, "HasPistol", true)
    return true
end
local function giveBook(player)
    local record = records[player]
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not record or not backpack or not bladeAllowed(player) or record.inventory.Grimoire.Value then return false end
    local book = CharacterVisuals.createBook()
    book.Parent = backpack
    record.inventory.Grimoire.Value = true
    setPrivate(player, "HasBook", true)
    return true
end
-- One bounded monitor serves active held interactions; no worker exists while idle.
local activeHolds, activeHoldCount = {}, 0
local holdMonitor, holdMonitorGeneration = nil, 0
local HOLD_CHECK_INTERVAL, HOLD_NETWORK_GRACE, HOLD_ENDED_GRACE = 0.05, 2, 0.15
local function stopIdleHoldMonitor()
    if activeHoldCount ~= 0 or not holdMonitor then return end
    local previous = holdMonitor
    holdMonitor = nil
    holdMonitorGeneration += 1
    if previous ~= coroutine.running() then task.cancel(previous) end
end
local function clearHeldPrompt(player, expected)
    local hold = activeHolds[player]
    if not hold or (expected and hold ~= expected) then return end
    activeHolds[player] = nil
    activeHoldCount -= 1
    stopIdleHoldMonitor()
end
local function clearAllHeldPrompts()
    table.clear(activeHolds)
    activeHoldCount = 0
    stopIdleHoldMonitor()
end
local function startHoldMonitor()
    if holdMonitor or activeHoldCount == 0 then return end
    holdMonitorGeneration += 1
    local generation = holdMonitorGeneration
    holdMonitor = task.spawn(function()
        while activeHoldCount > 0 and holdMonitorGeneration == generation do
            task.wait(HOLD_CHECK_INTERVAL)
            if holdMonitorGeneration ~= generation then return end
            local now = os.clock()
            for player, hold in pairs(activeHolds) do
                if now > hold.expires or (hold.ended and now >= hold.ended + HOLD_ENDED_GRACE)
                    or not hold.valid(player, hold) then clearHeldPrompt(player, hold) end
            end
        end
        if holdMonitorGeneration == generation then holdMonitor = nil end
    end)
end
local function connectHeldPrompt(prompt, target, requiredRole, callback)
    local function valid(player, hold)
        return prompt.Parent and prompt.Enabled and eligible(player) and near(player, target, 14)
            and (not requiredRole or PlayerState.get(player, "Role") == requiredRole)
            and (not hold or (hold.character == player.Character and hold.round == roundId))
    end
    objectiveCallbacks[target] = { prompt = prompt, valid = valid, complete = callback }
    prompt.PromptButtonHoldBegan:Connect(function(player)
        if not valid(player) then return end
        local previous = activeHolds[player]
        if previous and previous.prompt == prompt then return end
        clearHeldPrompt(player, previous)
        local now = os.clock()
        local hold = { started = now, expires = now + prompt.HoldDuration + HOLD_NETWORK_GRACE,
            character = player.Character, round = roundId, prompt = prompt, valid = valid }
        activeHolds[player] = hold
        activeHoldCount += 1
        startHoldMonitor()
    end)
    prompt.PromptButtonHoldEnded:Connect(function(player)
        local hold = activeHolds[player]
        if hold and hold.prompt == prompt then hold.ended = hold.ended or os.clock() end
    end)
    prompt.Triggered:Connect(function(player)
        local hold = activeHolds[player]
        if not hold or hold.prompt ~= prompt then return end
        clearHeldPrompt(player, hold)
        if not valid(player, hold) or os.clock() > hold.expires
            or (hold.ended and os.clock() >= hold.ended + HOLD_ENDED_GRACE) then return end
        local elapsed = (hold.ended or os.clock()) - hold.started
        -- Small scheduling tolerance; zero-duration client edits still cannot complete a hold.
        if elapsed < math.max(0, prompt.HoldDuration - 0.08) then return end
        callback(player)
    end)
    prompt.Destroying:Connect(function()
        objectiveCallbacks[target] = nil
        for player, hold in pairs(activeHolds) do
            if hold.prompt == prompt then clearHeldPrompt(player, hold) end
        end
    end)
end
local function checkWinner()
    if not running or deploying or winner then return end
    if state:GetAttribute("StatuesRemaining") == 0 then
        winner = "Ejecutores: destruyeron todas las estatuas."
        return
    end
    local executors, wolves = 0, 0
    for player in pairs(roster) do
        if player.Parent == Players and player:GetAttribute("Alive") then
            if PlayerState.get(player, "Role") == "HombreLobo" then wolves += 1 else executors += 1 end
        end
    end
    if executors == 0 then
        winner = practice and "Práctica terminada." or "Hombre Lobo: no quedan ejecutores."
    elseif not practice and wolves == 0 then
        winner = "Ejecutores: el Hombre Lobo fue eliminado o abandonó."
    end
end

local function teleportCharacter(player, character, position, token, alreadyStreamed)
    local hum = character:FindFirstChildOfClass("Humanoid")
    if player.Parent ~= Players or player.Character ~= character or roundId ~= token
        or not character:IsDescendantOf(Workspace) or not hum or hum.Health <= 0
        or not character:FindFirstChild("HumanoidRootPart") then return false end
    -- La precarga evita caer en un terreno todavía no recibido por el cliente.
    if not alreadyStreamed then pcall(function() player:RequestStreamAroundAsync(position, 3) end) end
    if player.Parent ~= Players or player.Character ~= character or roundId ~= token
        or not character:IsDescendantOf(Workspace) or hum.Parent ~= character or hum.Health <= 0
        or not character:FindFirstChild("HumanoidRootPart") then return false end
    character:PivotTo(CFrame.new(position))
    return true
end
local function makeSpectator(player)
    local record = records[player]
    if not record then return end
    if npcController then npcController:release(player) end
    player:SetAttribute("Alive", false)
    setPrivate(player, "Role", "Espectador")
    resetInventory(player)
    record.abilities, record.abilityReady = {}, 0
    record.chests, record.hintStatue, record.boots, record.spawn = 0, nil, false, lobbyPosition
    setPrivate(player, "Hint", "")
    setPrivate(player, "ChestsOpened", 0)
    setPrivate(player, "Ability", "Ninguna")
    setPrivate(player, "AbilityReadyAt", 0)
    clearEffects(player)
    checkWinner()
end
local function clearCharacterConnections(record)
    resetCombat(record.player)
    record.characterGeneration = (record.characterGeneration or 0) + 1
    if record.deathConnection then record.deathConnection:Disconnect(); record.deathConnection = nil end
    for _, connection in ipairs(record.characterConnections or {}) do connection:Disconnect() end
    record.characterConnections = {}
    record.character, record.humanoid = nil, nil
end
local function clearPlayerConnections(record)
    clearCharacterConnections(record)
    for _, connection in ipairs(record.playerConnections or {}) do connection:Disconnect() end
    table.clear(record.playerConnections)
    for _, hooks in pairs(record.bladeConnections) do for _, hook in ipairs(hooks) do hook:Disconnect() end end
    table.clear(record.bladeConnections)
end
local function destroyAI()
    if aiController then aiController:destroy(); aiController = nil end
    local actor = aiActor
    aiActor = nil
    if actor then
        botHolds[actor] = nil
        local record = records[actor]
        if record then clearPlayerConnections(record); record.inventoryFolder:Destroy() end
        records[actor], roster[actor] = nil, nil
        PlayerState.remove(actor)
        actor:Destroy()
    end
    setState("AIActive", false)
end
local function performBotHold(actor, model)
    if actor ~= aiActor or not eligible(actor) or not model or not model.Parent then botHolds[actor] = nil; return false end
    local target = model.PrimaryPart
    local entry = target and objectiveCallbacks[target]
    if not entry or not entry.valid(actor) then botHolds[actor] = nil; return false end
    local _, root = humanoidOf(actor)
    local params = RaycastParams.new()
    params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { actor.Character }
    local hit = Workspace:Raycast(root.Position, target.Position - root.Position, params)
    if hit and not hit.Instance:IsDescendantOf(model) then botHolds[actor] = nil; return false end
    local now = os.clock()
    local hold = botHolds[actor]
    if not hold or hold.target ~= target or hold.character ~= actor.Character or hold.round ~= roundId
        or now - hold.checked > 0.6 then
        hold = { target = target, character = actor.Character, round = roundId, started = now, checked = now }
        botHolds[actor] = hold
    end
    hold.checked = now
    if now - hold.started < entry.prompt.HoldDuration then return false end
    botHolds[actor] = nil
    if not entry.valid(actor, hold) then return false end
    entry.complete(actor)
    return true
end
local function onCharacter(player, character)
    local record = records[player]
    if not record or player.Parent ~= Players or player.Character ~= character then return end
    if record.character == character then return end
    clearCharacterConnections(record)
    record.character = character
    local generation = record.characterGeneration
    local function current()
        return records[player] == record and player.Parent == Players and player.Character == character
            and record.character == character and record.characterGeneration == generation
    end
    local function refreshHumanoid()
        if not current() then return end
        local hum = character:FindFirstChildOfClass("Humanoid")
        if record.humanoid == hum then return end
        if record.deathConnection then record.deathConnection:Disconnect(); record.deathConnection = nil end
        record.humanoid = nil
        if not hum or not character:FindFirstChild("HumanoidRootPart") then return end
        record.humanoid = hum
        hum.MaxHealth, hum.Health = Config.Player.Health, Config.Player.Health
        record.deathConnection = hum.Died:Connect(function()
            if not current() or record.humanoid ~= hum then return end
            if running and roster[player] and player:GetAttribute("Alive") then
                makeSpectator(player)
                tell(player, "Fuiste eliminado. Esperá la próxima ronda en el lobby.")
                checkWinner()
            end
        end)
        refreshSpeed(player)
    end
    local function childChanged(child)
        if child:IsA("Humanoid") or child.Name == "HumanoidRootPart" then refreshHumanoid() end
    end
    table.insert(record.characterConnections, character.ChildAdded:Connect(childChanged))
    table.insert(record.characterConnections, character.ChildRemoved:Connect(childChanged))
    local hum = character:WaitForChild("Humanoid", 10)
    local root = character:WaitForChild("HumanoidRootPart", 10)
    if not hum or not root or not current() then return end
    refreshHumanoid()
    -- El spawn automático está en el lobby. El despliegue de ronda se realiza
    -- después del retorno de LoadCharacterAsync, para que no lo sobrescriba Roblox.
end
local function onPlayer(player)
    if player.Parent ~= Players or records[player] then return end
    PlayerState.create(player)
    local stats = Instance.new("Folder")
    stats.Name, stats.Parent = "leaderstats", isBot(player) and player.Character or player
    local gold = Instance.new("IntValue")
    gold.Name, gold.Value, gold.Parent = "Oro", Config.Economy.StartingGold, stats
    local inventory = Instance.new("Folder")
    inventory.Name, inventory.Parent = tostring(player.UserId), privateInventories
    local items = {}
    for _, name in ipairs({ "SilverBlade", "Pistol", "Grimoire", "Ammo", "Boots", "Potion" }) do
        local item = Instance.new((name == "Potion" or name == "Ammo") and "IntValue" or "BoolValue")
        item.Name, item.Parent = name, inventory
        items[name] = item
    end
    setPrivate(player, "ChestsOpened", 0)
    local record = { player = player, inventory = items, gold = gold, abilities = {}, lastAction = 0, lastAttack = 0,
        abilityReady = 0, chests = 0, hintGiven = false, boots = false, sprinting = false,
        spawn = lobbyPosition, inventoryFolder = inventory, playerConnections = {}, characterConnections = {},
        combatTasks = {}, combatGeneration = 0, bladeConnections = {}, lastDrawAt = -math.huge,
        defendUntil = 0, defendReady = 0, lungeReady = 0, transforming = false, reloading = false, attackReady = 0, bookReady = 0 }
    records[player] = record
    for name, item in pairs(items) do
        if name == "Potion" or name == "Boots" or name == "Ammo" then
            table.insert(record.playerConnections, item.Changed:Connect(function(value)
                if records[player] == record and player.Parent == Players then setPrivate(player, name, value) end
            end))
        end
    end
    if not isBot(player) then persistence:Attach(player, gold) end
    setPrivate(player, "Role", "Lobby")
    player:SetAttribute("Alive", false)
    setPrivate(player, "Ability", "Ninguna")
    setPrivate(player, "HasBlade", false)
    setPrivate(player, "AbilityReadyAt", 0)
    if isBot(player) then
        onCharacter(player, player.Character)
        return
    end
    table.insert(record.playerConnections, player:GetAttributeChangedSignal("ProfileReady"):Connect(function()
        if records[player] ~= record or player.Parent ~= Players or not roster[player]
            or not player:GetAttribute("Alive") or persistence:IsReady(player) then return end
        -- A profile that loses its session must not remain an immune combatant.
        local hum = humanoidOf(player)
        if hum and hum.Health > 0 then hum.Health = 0 end
        makeSpectator(player)
        tell(player, "No se pudo mantener el guardado de tu cuenta. Volvé a entrar para recuperarlo.")
    end))
    table.insert(record.playerConnections, player.CharacterAdded:Connect(function(character)
        if records[player] == record then onCharacter(player, character) end
    end))
    table.insert(record.playerConnections, player.CharacterRemoving:Connect(function(character)
        if records[player] == record and record.character == character then clearCharacterConnections(record) end
    end))
    if player.Character then task.spawn(onCharacter, player, player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end
Players.PlayerRemoving:Connect(function(player)
    if aiRequester == player then aiRequester = nil; setState("AIRequested", false) end
    clearHeldPrompt(player)
    local record = records[player]
    if npcController then npcController:release(player) end
    if record then resetCombat(player) end
    roster[player], records[player] = nil, nil
    if record then clearPlayerConnections(record); record.inventoryFolder:Destroy() end
    PlayerState.remove(player)
    local anotherHuman = false
    for _, other in ipairs(Players:GetPlayers()) do if other ~= player then anotherHuman = true; break end end
    if not anotherHuman then destroyAI() end
    checkWinner()
end)

local function attachObjectives(map)
    for _, statue in ipairs(map.statues) do
        local prompt = statue.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
        connectHeldPrompt(prompt, statue.PrimaryPart, "Ejecutor", function(player)
            if not eligible(player) or PlayerState.get(player, "Role") ~= "Ejecutor"
                or not near(player, statue.PrimaryPart, 14) or statue:GetAttribute("Destroyed") then return end
            statue:SetAttribute("Destroyed", true)
            for other, record in pairs(records) do
                if record.hintStatue == statue then
                    record.hintStatue = nil
                    setPrivate(other, "Hint", "")
                    tell(other, "La estatua de tu pista fue purificada. Volvé con Elar por otra ubicación.")
                end
            end
            prompt.Enabled = false
            for _, p in ipairs(statue:GetDescendants()) do
                if p:IsA("BasePart") then p.Transparency, p.CanCollide = 1, false end
                if p:IsA("Light") then p.Enabled = false end
            end
            local earned = awardGold(player, Config.Economy.StatueGold)
            setState("StatuesRemaining", state:GetAttribute("StatuesRemaining") - 1)
            tell(player, "Estatua destruida. +" .. earned .. " Oro.")
            checkWinner()
        end)
    end
    for _, chest in ipairs(map.chests) do
        local prompt = chest.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
        connectHeldPrompt(prompt, chest.PrimaryPart, nil, function(player)
            if not eligible(player) or not near(player, chest.PrimaryPart, 14)
                or chest:GetAttribute("Looted") then return end
            chest:SetAttribute("Looted", true)
            prompt.Enabled = false
            chest.PrimaryPart.Color = Color3.fromRGB(72, 66, 57)
            local record = records[player]
            local earned = awardGold(player, Config.Economy.ChestGold)
            record.chests += 1
            setPrivate(player, "ChestsOpened", record.chests)
            local bladeGiven = giveBlade(player)
            local pistolGiven = record.chests >= 2 and givePistol(player)
            tell(player, bladeGiven and ("Encontraste una espada de plata y " .. earned .. " Oro.")
                or ("Encontraste " .. earned .. " Oro. En forma de lobo combatís con tus garras."))
            if pistolGiven then tell(player, "Segundo cofre: pistola de 6 disparos. T cambia de arma; G recarga.") end
        end)
    end
    map.guide:FindFirstChildOfClass("ProximityPrompt").Triggered:Connect(function(player)
        if not eligible(player) or not near(player, map.guide, 14) then return end
        local dialogToken
        if npcController then local _, token = npcController:interact(map.guide, player); dialogToken = token end
        local record = records[player]
        -- Both secret factions can carry the same visible book in their human form.
        if record.chests >= 2 then giveBook(player) end
        local function dialog(message)
            sendPrivate(player, "Guide", { npc = map.guide.Parent, message = message, dialogToken = dialogToken })
            tell(player, message)
        end
        if PlayerState.get(player, "Role") ~= "Ejecutor" then dialog("El guía ayuda a los ejecutores."); return end
        if record.chests < 2 then
            dialog("Misión del guía: abrí dos cofres y volvé. Progreso: " .. record.chests .. "/2.")
            return
        end
        local _, root = humanoidOf(player)
        local closest, distance
        for _, statue in ipairs(map.statues) do
            if not statue:GetAttribute("Destroyed") then
                local d = (root.Position - statue.PrimaryPart.Position).Magnitude
                if not distance or d < distance then closest, distance = statue, d end
            end
        end
        if closest then
            local pos = closest.PrimaryPart.Position
            local hint = string.format("El guía señala %s, cerca de X=%d Z=%d.", closest:GetAttribute("SiteName"), pos.X, pos.Z)
            record.hintStatue = closest
            setPrivate(player, "Hint", hint)
            dialog(hint)
        else
            dialog("Todas las estatuas ya fueron purificadas.")
        end
    end)
    map.shop:FindFirstChildOfClass("ProximityPrompt").Triggered:Connect(function(player)
        if eligible(player) and near(player, map.shop, 16) then
            local dialogToken
            if npcController then local _, token = npcController:interact(map.shop, player); dialogToken = token end
            sendPrivate(player, "Shop", { npc = map.shop.Parent, dialogToken = dialogToken })
        end
    end)
end

-- Todas las compras se validan sin aceptar precios ni saldos del cliente.
purchase.OnServerInvoke = function(player, itemId)
    if typeof(itemId) ~= "string" or not Config.Shop[itemId] then return false, "Artículo inválido." end
    if not eligible(player) or not world or not near(player, world.shop, 18) then
        return false, "Acercate al mercado durante la ronda."
    end
    local record = records[player]
    local now = os.clock()
    if now - (record.lastPurchase or 0) < 0.35 then return false, "Esperá un momento." end
    record.lastPurchase = now
    local item = Config.Shop[itemId]
    local hum = humanoidOf(player)
    if itemId == "Boots" and record.boots then return false, "Ya tenés las botas." end
    if itemId == "Potion" and record.inventory.Potion.Value >= 20 then return false, "Tu inventario de pociones está lleno." end
    if record.gold.Value < item.Price then return false, "No tenés suficiente Oro." end
    record.gold.Value -= item.Price
    if itemId == "Potion" then
        record.inventory.Potion.Value += 1
    elseif itemId == "Boots" then
        record.boots = true
        record.inventory.Boots.Value = true
        refreshSpeed(player)
    elseif itemId == "Reroll" then
        clearEffects(player, true)
        assignAbilities(player)
    end
    return true, item.Name .. ": compra realizada."
end

local function pistolAttack(player, pistol, now)
    local record = records[player]
    if not bladeAllowed(player) or not PlayerState.get(player, "HasPistol")
        or pistol.Parent ~= player.Character then return end
    local muzzle = pistol:FindFirstChild("Muzzle")
    if not muzzle or not muzzle:IsA("BasePart") then return end
    if record.inventory.Ammo.Value <= 0 then tell(player, "Sin munición: recargá con G."); return end
    local _, root = humanoidOf(player)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character }
    local origin = muzzle.Position
    local reach = origin - root.Position
    local cover = reach.Magnitude > 0.01 and Workspace:Raycast(root.Position, reach, params) or nil
    if cover then tell(player, "El arma está contra un obstáculo."); return end
    record.lastAttack, record.attackReady = now, now + Config.Combat.PistolCooldown
    record.inventory.Ammo.Value -= 1
    local direction = root.CFrame.LookVector * Config.Combat.PistolRange
    local hit = Workspace:Raycast(origin, direction, params)
    local position = hit and hit.Position or origin + direction
    local target
    local isWolf = PlayerState.get(player, "Role") == "HombreLobo"
    if hit then
        for other in pairs(roster) do
            if other ~= player and eligible(other) and hit.Instance:IsDescendantOf(other.Character)
                and (PlayerState.get(other, "Role") == "HombreLobo") ~= isWolf then target = other; break end
        end
    end
    feedback:FireAllClients("GunFX", { player = publicActor(player), character = player.Character, origin = origin, position = position, hit = target ~= nil })
    if target then
        local hum = humanoidOf(target)
        local defense = records[target]
        local multiplier = Workspace:GetServerTimeNow() <= defense.defendUntil and Config.Combat.DefendDamageMultiplier or 1
        hum:TakeDamage(Config.Combat.PistolDamage * multiplier)
        tell(player, multiplier < 1 and "Disparo bloqueado a tiempo." or "Disparo conectado.")
    end
end
local function swapWeapon(player)
    local record = records[player]
    if record.reloading or not bladeAllowed(player) then return end
    local blade = PlayerState.get(player, "HasBlade") and ownedTool(player, "EspadaPlata", "SilverBlade") or nil
    local pistol = PlayerState.get(player, "HasPistol") and ownedTool(player, "Pistola", "Pistol") or nil
    local character = player.Character
    local wanted = pistol and (pistol.Parent ~= character or not blade) and pistol or blade
    if not wanted then tell(player, "Buscá armas en los cofres."); return end
    local hum = humanoidOf(player)
    if wanted.Parent ~= character then hum:EquipTool(wanted) end
end
local function reload(player)
    local record = records[player]
    if record.reloading or not bladeAllowed(player) or not PlayerState.get(player, "HasPistol") then return end
    local pistol = ownedTool(player, "Pistola", "Pistol")
    if not pistol or pistol.Parent ~= player.Character or record.inventory.Ammo.Value >= Config.Combat.PistolCapacity then return end
    record.reloading = true
    setPrivate(player, "Reloading", true)
    combatLater(player, Config.Combat.ReloadSeconds, function(current)
        current.reloading = false
        setPrivate(player, "Reloading", false)
        if bladeAllowed(player) and ownedTool(player, "Pistola", "Pistol") == pistol then
            current.inventory.Ammo.Value = Config.Combat.PistolCapacity
            tell(player, "Pistola recargada: 6 disparos.")
        end
    end)
end
local function readBook(player)
    local record = records[player]
    if record.reloading or not bladeAllowed(player) or not PlayerState.get(player, "HasBook") then return end
    local now = os.clock()
    if now < record.bookReady then return end
    local book = ownedTool(player, "Grimorio", "Grimoire")
    if not book then return end
    local hum = humanoidOf(player)
    if book.Parent ~= player.Character then hum:EquipTool(book) end
    if book.Parent ~= player.Character then return end
    record.bookReady = now + 3
    feedback:FireAllClients("BookFX", { player = publicActor(player), character = player.Character, duration = 3 })
    local hint = PlayerState.get(player, "Hint")
    tell(player, hint ~= "" and hint or "El grimorio espera una pista del guía. Volvé a hablar con Elar.")
end

local function attack(player)
    local record = records[player]
    local now = os.clock()
    if now < record.attackReady then return end
    if record.transforming then tell(player, "La transformación está en curso."); return end
    if record.reloading then tell(player, "Terminá de recargar antes de atacar."); return end
    local isWolf = PlayerState.get(player, "Role") == "HombreLobo"
    local claws = clawsActive(player) == true
    if isWolf and state:GetAttribute("FullMoon") == true and not claws then return end
    local pistol = not claws and ownedTool(player, "Pistola", "Pistol") or nil
    if pistol and pistol.Parent == player.Character then pistolAttack(player, pistol, now); return end
    if not claws and not PlayerState.get(player, "HasBlade") then tell(player, "Buscá una espada de plata en un cofre."); return end
    local equippedBlade
    if not claws then
        -- Ownership alone is insufficient: the visual weapon must be equipped before a strike.
        local character = player.Character
        local backpack = player:FindFirstChildOfClass("Backpack")
        local blade = character and character:FindFirstChild("EspadaPlata")
            or (backpack and backpack:FindFirstChild("EspadaPlata"))
        local handle = blade and blade:FindFirstChild("Handle")
        if not blade or not blade:IsA("Tool") or blade:GetAttribute("HombreLoboItem") ~= "SilverBlade"
            or not handle or not handle:IsA("BasePart") then
            tell(player, "No tenés una espada lista para atacar.")
            return
        end
        local hum = humanoidOf(player)
        if blade.Parent == backpack and hum then hum:EquipTool(blade) end
        if blade.Parent ~= character then tell(player, "No se pudo equipar la espada."); return end
        equippedBlade = blade
    end
    record.lastAttack, record.attackReady = now, now + Config.Combat.Cooldown
    local _, root = humanoidOf(player)
    local target, nearest = nil, Config.Combat.Range
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character }
    for other in pairs(roster) do
        if other ~= player and eligible(other) and (PlayerState.get(other, "Role") == "HombreLobo") ~= isWolf then
            local _, otherRoot = humanoidOf(other)
            local d = (root.Position - otherRoot.Position).Magnitude
            if d <= nearest then
                local delta = otherRoot.Position - root.Position
                local hit = d > 0.01 and Workspace:Raycast(root.Position, delta, params) or nil
                if not hit or hit.Instance:IsDescendantOf(other.Character) then
                    target, nearest = other, d
                end
            end
        end
    end
    -- Only the visible fighting style is public; a daytime wolf sounds/looks like every sword user.
    feedback:FireAllClients("AttackFX", { player = publicActor(player), character = player.Character, wolf = claws, range = Config.Combat.Range, hit = target ~= nil })
    if not target then tell(player, "No hay un rival a alcance."); return end
    local targetCharacter = target.Character
    combatLater(player, Config.Combat.Windup, function()
        if not eligible(target) or target.Character ~= targetCharacter
            or (PlayerState.get(target, "Role") == "HombreLobo") == isWolf
            or records[player].transforming or (clawsActive(player) == true) ~= claws then return end
        if not claws then
            local handle = equippedBlade and equippedBlade:FindFirstChild("Handle")
            if not equippedBlade or equippedBlade.Parent ~= player.Character or not handle or not handle:IsA("BasePart") then return end
        end
        local _, currentRoot = humanoidOf(player)
        local hum, otherRoot = humanoidOf(target)
        local delta = otherRoot.Position - currentRoot.Position
        if delta.Magnitude > Config.Combat.Range then return end
        local obstruction = delta.Magnitude > 0.01 and Workspace:Raycast(currentRoot.Position, delta, params) or nil
        if obstruction and not obstruction.Instance:IsDescendantOf(targetCharacter) then return end
        local defense = records[target]
        local blocked = defense and Workspace:GetServerTimeNow() <= defense.defendUntil
        local damage = claws and Config.Combat.WolfDamage or Config.Combat.BladeDamage
        hum:TakeDamage(blocked and damage * Config.Combat.DefendDamageMultiplier or damage)
        tell(player, blocked and "El rival bloqueó a tiempo: recibió el 20 % del daño." or "Golpe conectado.")
        if blocked then tell(target, "¡Defensa a tiempo! Recibiste el 20 % del daño.") end
    end)
end

local function defend(player)
    local record = records[player]
    local now = Workspace:GetServerTimeNow()
    if record.transforming or now < record.defendReady then return end
    record.defendReady = now + Config.Combat.DefendCooldown
    record.defendUntil = now + Config.Combat.DefendWindow
    setPrivate(player, "DefendReadyAt", record.defendReady)
    feedback:FireAllClients("DefendFX", { player = publicActor(player), character = player.Character, duration = Config.Combat.DefendWindow })
end

local function dodge(player)
    local record = records[player]
    local now = Workspace:GetServerTimeNow()
    if record.transforming or record.lungeRoot or record.dodgeRoot or now < record.defendReady then return end
    local hum, root = humanoidOf(player)
    if root.Anchored or hum.FloorMaterial == Enum.Material.Air then return end
    local direction = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
    if direction.Magnitude < 0.05 then
        direction = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
    end
    if direction.Magnitude < 0.01 then return end
    direction = direction.Unit
    local params = RaycastParams.new()
    params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, {player.Character}
    params.RespectCanCollide = true
    local size = root.Size + Vector3.new(0.75, 0, 0.75)
    local overlaps = OverlapParams.new()
    overlaps.FilterType, overlaps.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, {player.Character}
    overlaps.RespectCanCollide, overlaps.MaxParts = true, 1
    if #Workspace:GetPartBoundsInBox(root.CFrame, size, overlaps) > 0 then
        tell(player, "Alejate del obstáculo antes de esquivar.")
        return
    end
    local hit = Workspace:Blockcast(root.CFrame, size, direction * Config.Combat.DodgeDistance, params)
    local distance = hit and math.max(0, hit.Distance - 0.5) or Config.Combat.DodgeDistance
    if distance < 0.5 then tell(player, "Necesitás espacio para esquivar."); return end
    if not pcall(function() root:SetNetworkOwner(nil) end) then return end
    record.dodgeRoot = root
    local attachment = Instance.new("Attachment")
    attachment.Name, attachment.Parent = "DodgeAttachment", root
    local velocity = Instance.new("LinearVelocity")
    velocity.Name, velocity.Attachment0 = "DodgeVelocity", attachment
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
    velocity.PrimaryTangentAxis, velocity.SecondaryTangentAxis = Vector3.xAxis, Vector3.zAxis
    local speed = distance / Config.Combat.DodgeSeconds
    velocity.PlaneVelocity = Vector2.new(direction.X * speed, direction.Z * speed)
    velocity.ForceLimitsEnabled, velocity.MaxForce = true, math.max(1, root.AssemblyMass) * 2000
    velocity.Parent = root
    record.dodgeVelocity, record.dodgeAttachment = velocity, attachment
    record.defendReady, record.defendUntil = now + Config.Combat.DefendCooldown, now + Config.Combat.DefendWindow
    setPrivate(player, "DefendReadyAt", record.defendReady)
    root.AssemblyLinearVelocity = direction * speed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
    feedback:FireAllClients("DodgeFX", {player = publicActor(player), character = player.Character, duration = Config.Combat.DodgeSeconds})
    combatLater(player, Config.Combat.DodgeSeconds, function(current)
        if current.dodgeRoot == root then releaseDodge(current) end
    end, true)
end

local function lunge(player)
    local record = records[player]
    local now = Workspace:GetServerTimeNow()
    if not clawsActive(player) or record.dodgeRoot or record.lungeRoot or now < record.lungeReady then return end
    local hum, root = humanoidOf(player)
    if root.Anchored or hum.FloorMaterial == Enum.Material.Air then return end
    local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
    if forward.Magnitude < 0.01 then return end
    forward = forward.Unit
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character }
    params.RespectCanCollide = true
    local size = root.Size + Vector3.new(0.75, 0, 0.75)
    local overlaps = OverlapParams.new()
    overlaps.FilterType = Enum.RaycastFilterType.Exclude
    overlaps.FilterDescendantsInstances = { player.Character }
    overlaps.RespectCanCollide, overlaps.MaxParts = true, 1
    -- Blockcast omits parts already intersecting its starting box; reject those separately.
    if #Workspace:GetPartBoundsInBox(root.CFrame, size, overlaps) > 0 then
        tell(player, "Alejate del obstáculo antes de lanzarte.")
        return
    end
    local hit = Workspace:Blockcast(root.CFrame, size, forward * Config.Combat.LungeDistance, params)
    local distance = hit and math.max(0, hit.Distance - 1) or Config.Combat.LungeDistance
    if distance < 2 then tell(player, "Necesitás espacio delante para lanzarte."); return end
    local owned = pcall(function() root:SetNetworkOwner(nil) end)
    if not owned then return end
    record.lungeRoot = root
    local attachment = Instance.new("Attachment")
    attachment.Name, attachment.Parent = "LungeAttachment", root
    local velocity = Instance.new("LinearVelocity")
    velocity.Name, velocity.Attachment0 = "LungeVelocity", attachment
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
    velocity.PrimaryTangentAxis, velocity.SecondaryTangentAxis = Vector3.xAxis, Vector3.zAxis
    local speed = distance / Config.Combat.LungeSeconds
    velocity.PlaneVelocity = Vector2.new(forward.X * speed, forward.Z * speed)
    velocity.ForceLimitsEnabled, velocity.MaxForce = true, math.max(1, root.AssemblyMass) * 2000
    velocity.Parent = root
    record.lungeVelocity, record.lungeAttachment = velocity, attachment
    record.lungeReady = now + Config.Combat.LungeCooldown
    setPrivate(player, "LungeReadyAt", record.lungeReady)
    hum:ChangeState(Enum.HumanoidStateType.Jumping)
    root.AssemblyLinearVelocity = forward * speed + Vector3.new(0, 36, 0)
    feedback:FireAllClients("LungeFX", { player = publicActor(player), character = player.Character, duration = Config.Combat.LungeSeconds })
    combatLater(player, Config.Combat.LungeSeconds, function(current)
        if current.lungeRoot ~= root then return end
        releaseLunge(current)
    end, true)
end

local function useAbility(player)
    local record = records[player]
    local now = Workspace:GetServerTimeNow()
    if now < record.abilityReady then tell(player, "Tu habilidad se está recargando."); return end
    local chosen = record.abilities[#record.abilities]
    if not chosen then return end
    record.abilityReady = now + Config.Ability.Cooldown
    setPrivate(player, "AbilityReadyAt", record.abilityReady)
    local character = player.Character
    local token = roundId
    record.effectId = (record.effectId or 0) + 1
    local effectId = record.effectId
    if chosen == "Carrera" then
        record.sprinting = true
        refreshSpeed(player)
        task.delay(Config.Ability.Duration, function()
            if records[player] == record and roundId == token and record.effectId == effectId
                and player.Character == character then
                record.sprinting = false
                refreshSpeed(player)
            end
        end)
    elseif chosen == "Escudo" then
        local shield = Instance.new("ForceField")
        shield.Name, shield.Parent = "AbilityShield", character
        Debris:AddItem(shield, Config.Ability.Duration)
    elseif chosen == "Luz" then
        local light = Instance.new("PointLight")
        light.Name, light.Brightness, light.Range = "AbilityLight", 3, 38
        light.Color = Color3.fromRGB(255, 237, 179)
        light.Parent = character:FindFirstChild("HumanoidRootPart")
        Debris:AddItem(light, Config.Ability.Duration)
    end
    tell(player, chosen .. " activa por " .. Config.Ability.Duration .. " segundos.")
end
action.OnServerEvent:Connect(function(player, kind, dialogToken)
    if typeof(kind) ~= "string" then return end
    if kind == "PlayWithAI" then
        if dialogToken ~= nil or Config.Round.AllowAI ~= true or running or deploying
            or not records[player] or not persistence:IsReady(player) then return end
        local phase, now = state:GetAttribute("Phase"), os.clock()
        if phase ~= "Esperando" and phase ~= "Lobby" then return end
        local readyCount, soleHuman = 0, nil
        for _, human in ipairs(Players:GetPlayers()) do
            if persistence:IsReady(human) then readyCount += 1; soleHuman = human end
        end
        if readyCount ~= 1 or soleHuman ~= player then return end
        local record = records[player]
        if now - (record.lastAIRequest or -math.huge) < 0.75 then return end
        record.lastAIRequest = now
        aiRequester = player
        setState("AIRequested", true)
        tell(player, "Partida con IA solicitada. La ronda empieza después de la cuenta regresiva.")
        return
    end
    if kind == "DialogClose" then
        if npcController and typeof(dialogToken) == "number" and dialogToken > 0
            and dialogToken < math.huge and dialogToken % 1 == 0 then npcController:release(player, dialogToken) end
        return
    end
    if not eligible(player) then return end
    local record = records[player]
    local now = os.clock()
    if kind == "Defend" or kind == "Dodge" then
        -- A reaction must still work immediately after attacking; its own cooldown bounds requests.
        if kind == "Defend" then defend(player) else dodge(player) end
        return
    end
    if record.transforming then return end
    if now - record.lastAction < 0.15 then return end
    record.lastAction = now
    if kind == "Attack" then attack(player)
    elseif kind == "Lunge" then lunge(player)
    elseif kind == "SwapWeapon" then swapWeapon(player)
    elseif kind == "Reload" then reload(player)
    elseif kind == "ReadBook" then readBook(player)
    elseif kind == "Ability" then useAbility(player)
    elseif kind == "UsePotion" then
        local hum = humanoidOf(player)
        if record.inventory.Potion.Value <= 0 then tell(player, "No tenés pociones."); return end
        if hum.Health >= hum.MaxHealth then tell(player, "Tu vida ya está completa."); return end
        record.inventory.Potion.Value -= 1
        hum.Health = math.min(hum.MaxHealth, hum.Health + 55)
        tell(player, "Usaste una poción. +55 de vida.")
    end
end)

local function setNight()
    cancelNightTransition()
    setState("WolfAttackReadyAt", Workspace:GetServerTimeNow() + Config.Combat.TransformSeconds)
    setState("Phase", "Noche")
    setState("FullMoon", true)
    setState("Message", "Luna llena: comienza la transformación del Hombre Lobo.")
    Lighting.ClockTime, Lighting.Brightness = 0, 1.6
    Lighting.Ambient = Color3.fromRGB(63, 72, 97)
    for property, value in pairs(nightAtmosphere) do atmosphere[property] = value end
    for player in pairs(roster) do
        refreshSpeed(player)
        if eligible(player) and PlayerState.get(player, "Role") == "HombreLobo" and player.Character then
            resetCombat(player)
            removeBlade(player)
            local record, character = records[player], player.Character
            record.transforming = true
            setPrivate(player, "Transforming", true)
            refreshSpeed(player)
            if not CharacterVisuals.transform(character, 0) then
                makeSpectator(player)
                tell(player, "No se pudo completar la transformación de tu personaje.")
                continue
            end
            local aura = Instance.new("Highlight")
            aura.Name, aura.FillColor, aura.OutlineColor = "WolfAura", Color3.fromRGB(188, 28, 32), Color3.fromRGB(255, 70, 48)
            aura.FillTransparency, aura.OutlineTransparency = 0.8, 0.1
            aura.DepthMode = Enum.HighlightDepthMode.Occluded
            aura.Parent = character
            feedback:FireAllClients("TransformFX", { player = publicActor(player), character = character, duration = Config.Combat.TransformSeconds })
            tell(player, "La espada desaparece: te estás transformando bajo la luna llena.")
            for stage = 1, 3 do
                local progress = stage / 3
                combatLater(player, Config.Combat.TransformSeconds * progress, function(current)
                    if state:GetAttribute("FullMoon") ~= true or PlayerState.get(player, "Role") ~= "HombreLobo" then return end
                    CharacterVisuals.setTransformationProgress(character, progress)
                    if aura.Parent then aura.FillTransparency = 0.8 - progress * 0.45 end
                    if progress == 1 then
                        current.transforming = false
                        setPrivate(player, "Transforming", false)
                        local hum = humanoidOf(player)
                        local fraction = hum.Health / hum.MaxHealth
                        hum.MaxHealth = Config.Player.WolfHealth
                        hum.Health = math.clamp(fraction * hum.MaxHealth, 0, hum.MaxHealth)
                        refreshSpeed(player)
                        setState("Message", "Luna llena: el Hombre Lobo ya puede atacar.")
                        tell(player, "Garras activas. Lanzate con Z y defendete con C al ver el golpe.")
                    end
                end)
            end
        end
    end
end

local function loadPlayer(player, token)
    local record = records[player]
    local ok, err = pcall(function() player:LoadCharacterAsync() end)
    if token ~= roundId or records[player] ~= record or not record or not roster[player] then return end
    local character = player.Character
    local hum, root = humanoidOf(player)
    if not ok or not character or not hum or not root or hum.Health <= 0 then
        warn("No se pudo cargar a " .. player.Name .. ": " .. tostring(err or "personaje incompleto"))
        makeSpectator(player)
        tell(player, "No se pudo cargar tu personaje. Esperá la próxima ronda.")
        return
    end
    if not running or not player:GetAttribute("Alive") then return end
    if not teleportCharacter(player, character, record.spawn, token) then return end
    -- La precarga también cede ejecución: comprobar de nuevo muerte/timeout/ronda.
    if token ~= roundId or records[player] ~= record or not running or not roster[player]
        or not player:GetAttribute("Alive") or hum.Health <= 0 then
        if player.Character == character then character:PivotTo(CFrame.new(lobbyPosition)) end
        return
    end
    refreshSpeed(player)
    record.deployed = true
end
local function runRound()
    roundId += 1
    cancelNightTransition()
    destroyAI()
    table.clear(objectiveCallbacks)
    table.clear(botHolds)
    clearAllHeldPrompts()
    local seed = Config.Round.FixedSeed
    if seed == 0 then seed = rng:NextInteger(1, 100000000) end
    setState("Phase", "Generando")
    setState("Message", "Creando un nuevo bosque...")
    setState("Seed", seed)
    if npcController then npcController:destroy(); npcController = nil end
    world = WorldGenerator.generate(seed, Config)
    -- La generación cede tiempo al motor: la lista debe capturarse después.
    local participants = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if records[player] and persistence:IsReady(player) then table.insert(participants, player) end
    end
    local useAI = #participants == 1 and aiRequester == participants[1] and Config.Round.AllowAI == true
    aiRequester = nil
    setState("AIRequested", false)
    if useAI then
        aiActor = BotController.create(world.spawnPoints[2] or world.spawnPoints[1])
        onPlayer(aiActor)
        table.insert(participants, aiActor)
        setState("AIActive", true)
    end
    practice = #participants == 1 and RunService:IsStudio() and Config.Round.StudioSoloPractice
    if #participants < Config.Round.MinimumPlayers and not practice then return end
    npcController = NPCBehavior.start(world)
    setState("Practice", practice)
    setState("StatuesRemaining", #world.statues)
    attachObjectives(world)
    roster, winner = {}, nil
    local wolfIndex = not practice and rng:NextInteger(1, #participants) or 0
    setDayEnvironment()
    setState("FullMoon", false)
    setState("Phase", "Día")
    setState("Message", practice and "Práctica en Studio: explorá y destruí las estatuas." or "Explorá y preparate antes de la luna llena.")
    running, deploying = true, true
    setState("Phase", "Preparando")
    setState("Message", "Cargando los personajes y el bosque...")
    for index, player in ipairs(participants) do
        local record = records[player]
        if player.Parent == Players and record then
            local wolf = index == wolfIndex
            roster[player] = true
            -- Preserve the participant's faction through elimination and lobby reset.
            -- This record is server-only; clients receive only their own final outcome.
            record.roundRole = wolf and "HombreLobo" or "Ejecutor"
            clearPrivateResult(player)
            record.spawn = world.spawnPoints[((index - 1) % #world.spawnPoints) + 1]
            resetInventory(player)
            record.boots, record.sprinting, record.chests = false, false, 0
            setPrivate(player, "ChestsOpened", 0)
            record.lastAttack, record.lastAction, record.deployed = 0, 0, false
            resetCombat(player)
            player:SetAttribute("Alive", true)
            setPrivate(player, "Role", record.roundRole)
            setPrivate(player, "HasBlade", false)
            setPrivate(player, "Hint", "")
            record.hintStatue = nil
            assignAbilities(player)
            task.spawn(loadPlayer, player, roundId)
        end
    end
    local deadline = os.clock() + 15
    while os.clock() < deadline do
        local pending = false
        for player in pairs(roster) do
            if player.Parent == Players and player:GetAttribute("Alive") and not records[player].deployed then pending = true; break end
        end
        if not pending then break end
        task.wait(0.1)
    end
    for player in pairs(roster) do
        if player.Parent == Players and player:GetAttribute("Alive") and not records[player].deployed then
            makeSpectator(player)
            tell(player, "Tu personaje tardó demasiado en cargar. Esperá la próxima ronda.")
            if player.Character then task.spawn(teleportCharacter, player, player.Character, lobbyPosition, roundId) end
        end
    end
    deploying = false
    if aiActor and aiActor:GetAttribute("Alive") then
        aiController = BotController.start(aiActor, {
            eligible = eligible, getRole = function(actor) return PlayerState.get(actor, "Role") end,
            isNight = function() return state:GetAttribute("FullMoon") == true end,
            getWorld = function() return world end,
            getHumanActors = function() return Players:GetPlayers() end,
            getChestsOpened = function(actor) return records[actor] and records[actor].chests or 0 end,
            attack = function(actor) if eligible(actor) and not records[actor].transforming then attack(actor) end end,
            defend = function(actor) if eligible(actor) then defend(actor) end end,
            lunge = function(actor) if eligible(actor) then lunge(actor) end end,
            lootChest = performBotHold, purifyStatue = performBotHold,
            cancelHold = function(actor) botHolds[actor] = nil end,
            isAttackIncoming = function(actor, other)
                local record, root = records[other], select(2, humanoidOf(actor))
                local _, attackerRoot = humanoidOf(other)
                return record and root and attackerRoot and record.attackReady > os.clock()
                    and record.lastAttack + Config.Combat.Windup > os.clock()
                    and (root.Position - attackerRoot.Position).Magnitude <= Config.Combat.Range
            end,
        })
    end
    local deployedCount = 0
    for player in pairs(roster) do
        if player.Parent == Players and player:GetAttribute("Alive") then deployedCount += 1 end
    end
    if deployedCount == 0 then winner = "Ronda cancelada: no se pudieron cargar los jugadores." end
    setState("Phase", "Día")
    setState("Message", practice and "Práctica en Studio: explorá y destruí las estatuas." or "Explorá y preparate antes de la luna llena.")
    checkWinner()
    local sunsetSeconds = math.clamp(Config.Round.NightTransitionSeconds or 10, 0, Config.Round.DaySeconds)
    for remaining = Config.Round.DurationSeconds, 1, -1 do
        if winner then break end
        setState("Seconds", remaining)
        local elapsed = Config.Round.DurationSeconds - remaining
        if elapsed == Config.Round.DaySeconds - sunsetSeconds then beginNightTransition(sunsetSeconds) end
        if elapsed == Config.Round.DaySeconds then setNight() end
        checkWinner()
        task.wait(1)
    end
    if not winner then winner = practice and "Práctica: se agotó el tiempo." or "Hombre Lobo: los ejecutores no destruyeron las estatuas a tiempo." end
    running = false
    cancelNightTransition()
    setDayEnvironment()
    if aiController then aiController:destroy(); aiController = nil end
    table.clear(botHolds)
    clearAllHeldPrompts()
    local winningRole = not practice and (string.find(winner, "Ejecutores:", 1, true) == 1 and "Ejecutor"
        or (string.find(winner, "Hombre Lobo:", 1, true) == 1 and "HombreLobo" or nil)) or nil
    local resultStartedAt = Workspace:GetServerTimeNow()
    local resultSeconds = math.clamp(Config.Round.ResultsSeconds, 8, 10)
    local resultEndsAt = resultStartedAt + resultSeconds
    local resultStage = lobbyPosition
    local winnerNames = {}
    for actor in pairs(roster) do
        if actor.Parent == Players and records[actor] and records[actor].roundRole == winningRole then
            table.insert(winnerNames, {id = actor.UserId, name = isBot(actor) and "Luna (IA)" or actor.DisplayName})
        end
    end
    table.sort(winnerNames, function(a, b) return a.id < b.id end)
    local displayNames = {}
    for _, entry in ipairs(winnerNames) do table.insert(displayNames, entry.name) end
    local winnerNamesText = table.concat(displayNames, ", ")
    setState("Phase", "Resultado")
    setState("WinnerRole", winningRole or "")
    setState("WinnerNames", winnerNamesText)
    setState("ResultRoundId", roundId)
    setState("ResultEndsAt", resultEndsAt)
    setState("Message", winner)
    setState("Seconds", 0)
    setState("FullMoon", false)
    local victorious, victoriousCharacters, victoriousActors, victoriousAI = {}, {}, {}, false
    for player in pairs(roster) do
        local hum, root = humanoidOf(player)
        if player.Parent == Players and player:GetAttribute("Alive") and hum and hum.Health > 0 and root
            and (practice or PlayerState.get(player, "Role") == winningRole) then
            table.insert(victorious, publicActor(player))
            table.insert(victoriousCharacters, player.Character)
            table.insert(victoriousActors, player)
            if player == aiActor then victoriousAI = true end
        end
    end
    -- A defeated AI has no lobby avatar to respawn. Remove its body before the
    -- lobby reset instead of relocating an intact dead rig beside the winner.
    if aiActor and not victoriousAI then destroyAI() end
    if npcController then npcController:destroy(); npcController = nil end
    for actor, record in pairs(records) do
        local outcome = "Resultado"
        if winningRole and roster[actor] and record.roundRole then
            outcome = record.roundRole == winningRole and "Victoria" or "Derrota"
        end
        setPrivate(actor, "ResultRoundId", roundId)
        setPrivate(actor, "ResultOutcome", outcome)
        setPrivate(actor, "ResultWinnerRole", winningRole or "")
        setPrivate(actor, "ResultWinnerNames", winnerNamesText)
        setPrivate(actor, "ResultWinnerCount", #displayNames)
        setPrivate(actor, "ResultEndsAt", resultEndsAt)
        setPrivate(actor, "ResultCameraPosition", #victorious > 0 and resultStage or Vector3.zero)
    end
    -- Stream the ceremony for every remaining participant, including a dead
    -- observer whose camera is still near the map. No character reload or healing.
    local pendingStreams = 0
    for actor in pairs(roster) do
        if not isBot(actor) and actor.Parent == Players then
            pendingStreams += 1
            task.spawn(function()
                pcall(function() actor:RequestStreamAroundAsync(resultStage, 2) end)
                pendingStreams -= 1
            end)
        end
    end
    local streamDeadline = os.clock() + 2.1
    while pendingStreams > 0 and os.clock() < streamDeadline do task.wait(0.05) end
    local stagePositions = {}
    for index, actor in ipairs(victoriousActors) do
        stagePositions[actor] = resultStage + Vector3.new((index - (#victoriousActors + 1) / 2) * 6, 0, 0)
    end
    for player in pairs(records) do
        player:SetAttribute("Alive", false)
        setPrivate(player, "Role", "Lobby")
        setPrivate(player, "Ability", "Ninguna")
        setPrivate(player, "HasBlade", false)
        setPrivate(player, "Hint", "")
        setPrivate(player, "AbilityReadyAt", 0)
        setPrivate(player, "ChestsOpened", 0)
        resetInventory(player)
        local record = records[player]
        if record then
            record.spawn, record.boots = lobbyPosition, false
            record.abilities, record.abilityReady, record.hintStatue = {}, 0, nil
        end
        clearEffects(player)
        if player.Character then
            player.Character:SetAttribute("Transformed", false)
            local position = stagePositions[player] or (lobbyPosition + Vector3.new(0, 0, 12))
            if stagePositions[player] then holdStageActor(player, player.Character) end
            if isBot(player) then
                -- A surviving AI winner keeps its real rig for the finite dance,
                -- with its own spot and no physical contact with lobby players.
                for _, item in ipairs(player.Character:GetDescendants()) do
                    if item:IsA("BasePart") then item.CanCollide = false end
                end
            end
            teleportCharacter(player, player.Character, position, roundId, true)
        end
    end
    roster = {}
    -- Give the entire cue five seconds after streaming. Extensions are bounded
    -- by two seconds; publish the same authoritative deadline to every observer.
    resultEndsAt = math.min(resultStartedAt + resultSeconds + 2, math.max(resultEndsAt, Workspace:GetServerTimeNow() + 5))
    setState("ResultEndsAt", resultEndsAt)
    for actor in pairs(records) do setPrivate(actor, "ResultEndsAt", resultEndsAt) end
    if #victorious > 0 then
        feedback:FireAllClients("VictoryFX", {
            players = victorious, characters = victoriousCharacters,
            duration = 5, startedAt = Workspace:GetServerTimeNow(),
        })
    end
    task.wait(math.max(0, resultEndsAt - Workspace:GetServerTimeNow()))
    releaseStageLeases()
    destroyAI()
end

while true do
    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do if persistence:IsReady(player) then count += 1 end end
    setState("HumanCount", count)
    local withAI = count == 1 and aiRequester and aiRequester.Parent == Players and persistence:IsReady(aiRequester)
    local canStart = count >= Config.Round.MinimumPlayers
        or withAI
        or (count == 1 and RunService:IsStudio() and Config.Round.StudioSoloPractice)
    if not canStart then
        setState("Phase", "Esperando")
        setState("Message", "Esperando otro jugador. Podés elegir Jugar con IA para empezar solo.")
        setState("Seconds", 0)
        task.wait(1)
    else
        local cancelled = false
        setState("Phase", "Lobby")
        setState("Message", "La próxima ronda comienza pronto.")
        for seconds = Config.Round.IntermissionSeconds, 1, -1 do
            setState("Seconds", seconds)
            task.wait(1)
            local n = 0
            for _, player in ipairs(Players:GetPlayers()) do if persistence:IsReady(player) then n += 1 end end
            setState("HumanCount", n)
            local pendingAI = n == 1 and aiRequester and aiRequester.Parent == Players and persistence:IsReady(aiRequester)
            if n < Config.Round.MinimumPlayers and not pendingAI and not (n == 1 and RunService:IsStudio() and Config.Round.StudioSoloPractice) then
                cancelled = true
                break
            end
        end
        if not cancelled then
            local ok, err = xpcall(runRound, debug.traceback)
            if not ok then
                destroyAI()
                warn("Error de ronda: " .. tostring(err))
                running, deploying, roster = false, false, {}
                if npcController then npcController:destroy(); npcController = nil end
                clearAllHeldPrompts()
                setState("FullMoon", false)
                setState("Seconds", 0)
                setDayEnvironment()
                setState("Phase", "Error")
                setState("Message", "No se pudo crear la ronda. Revisá Output en Studio.")
                for _, player in ipairs(Players:GetPlayers()) do
                    player:SetAttribute("Alive", false)
                    setPrivate(player, "Role", "Lobby")
                    resetInventory(player)
                    setPrivate(player, "Ability", "Ninguna")
                    setPrivate(player, "AbilityReadyAt", 0)
                    setPrivate(player, "ChestsOpened", 0)
                    setPrivate(player, "Hint", "")
                    if records[player] then
                        local record = records[player]
                        record.abilities, record.abilityReady = {}, 0
                        record.chests, record.hintStatue, record.boots, record.spawn = 0, nil, false, lobbyPosition
                    end
                    
                    clearEffects(player)
                    if player.Character then task.spawn(teleportCharacter, player, player.Character, lobbyPosition, roundId) end
                end
                task.wait(5)
            end
        end
    end
end
