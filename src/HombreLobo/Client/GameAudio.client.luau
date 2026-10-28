-- Short spatial cues from server-accepted actions. No polling or frame callbacks.
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")
local localPlayer = Players.LocalPlayer
local shared = game.ReplicatedStorage:WaitForChild("HombreLobo")
local Config = require(shared:WaitForChild("Config"))
local feedback = shared:WaitForChild("Network"):WaitForChild("Feedback")
local state = shared:WaitForChild("State")
local hud = localPlayer:WaitForChild("PlayerGui"):WaitForChild("HombreLoboHUD")
local cache = Instance.new("Folder")
cache.Name, cache.Parent = "AudioCache", script
local templates, voices, active, connections, playerConnections = {}, {}, {}, {}, {}
-- Idle voices remember their last character without retaining a removed rig.
local affinity = setmetatable({}, {__mode = "v"})
local stopped, activeCount, voiceCount = false, 0, 0
local MAX_VOICES, MAX_ACTOR_VOICES = 16, 3
local LEASE_CONNECTIONS = {"ended", "died", "characterRemoving", "characterDestroying", "emitterRemoving"}
local cueSettings = {
    SwordDraw = {volume = 0.45, duration = 2},
    SwordSwing = {volume = 0.42, duration = 2},
    WolfTransform = {volume = 0.6, duration = 3},
}
for name, settings in pairs(cueSettings) do
    local id = Config.Audio and Config.Audio[name]
    if typeof(id) == "string" and id:match("^rbxassetid://%d+$") then
        local sound = Instance.new("Sound")
        sound.Name, sound.SoundId, sound.Volume = name, id, settings.volume
        sound.RollOffMode = Enum.RollOffMode.InverseTapered
        sound.RollOffMinDistance, sound.RollOffMaxDistance = 8, 80
        sound.Parent = cache
        templates[name] = sound
    end
end
-- One non-spatial music voice serves the whole winning team, avoiding an echo
-- when multiple survivors celebrate. Combat retains its existing bounded pool.
local victorySound, victoryExpiry, victoryLoaded, victoryEnded, victoryAt
local victoryGeneration, victoryWinners, victoryConnections = 0, {}, {}
local pendingVictory, pendingVictoryExpiry, lastVictoryStartedAt
local victoryId = Config.Audio and Config.Audio.VictoryMusic
local victorySpeed = Config.Audio and Config.Audio.VictoryMusicPlaybackSpeed
if typeof(victorySpeed) ~= "number" or victorySpeed ~= victorySpeed or victorySpeed < 0.5 or victorySpeed > 2 then victorySpeed = 1 end
if typeof(victoryId) == "string" and victoryId:match("^rbxassetid://%d+$") then
    victorySound = Instance.new("Sound")
    victorySound.Name, victorySound.SoundId = "HombreLoboVictoryMusic", victoryId
    victorySound.Volume, victorySound.Looped = 0.4, false
    victorySound.PlaybackSpeed = victorySpeed
    -- A Sound outside a BasePart/Attachment is global. Keeping it under the
    -- script also guarantees destruction when Deferred signals skip cleanup.
    victorySound.Parent = cache
end
-- Fetch once, independently of combat and map generation.
local preloadTask = task.spawn(function()
    local list = {}
    for _, sound in pairs(templates) do table.insert(list, sound) end
    if victorySound then table.insert(list, victorySound) end
    local ok, detail = pcall(function() ContentProvider:PreloadAsync(list) end)
    if not ok and not stopped then warn("No se pudo precargar el audio: " .. tostring(detail)) end
end)
local function disconnectLease(record)
    for _, key in ipairs(LEASE_CONNECTIONS) do
        if record[key] then record[key]:Disconnect(); record[key] = nil end
    end
    if record.expiry then task.cancel(record.expiry); record.expiry = nil end
end
local discard
local function release(record, generation)
    local sound = record.sound
    if voices[sound] ~= record or not record.active or (generation and record.generation ~= generation) then return end
    -- With deferred signals, a rig's Destroying/AncestryChanged callback may
    -- run after its descendant Sound has already been destroyed and unparented.
    if sound.Parent == nil then discard(record, false); return end
    record.generation += 1
    record.active = false
    active[sound] = nil
    activeCount -= 1
    disconnectLease(record)
    record.character, record.actor = nil, nil
    sound:Stop()
    sound.TimePosition = 0
    sound.Parent = cache
end
discard = function(record, destroy)
    local sound = record.sound
    if voices[sound] ~= record then return end
    record.generation += 1
    if record.active then active[sound] = nil; activeCount -= 1 end
    record.active = false
    disconnectLease(record)
    if record.destroying then record.destroying:Disconnect(); record.destroying = nil end
    record.character, record.actor = nil, nil
    voices[sound], affinity[sound] = nil, nil
    voiceCount -= 1
    -- A Destroying callback only forgets the slot; it must not destroy or
    -- reparent the Sound while another caller is already destroying it.
    if destroy then sound:Destroy() end
end
local function isIdle(record)
    return voices[record.sound] == record and not record.active and record.sound.Parent == cache
end
local function acquire(template, cue, character)
    local idle, preferred
    for sound, record in pairs(voices) do
        -- Destroying may still be queued under deferred signals. Never hand
        -- out an unparented Sound or an idle slot removed from our cache.
        if sound.Parent == nil or (not record.active and sound.Parent ~= cache) then
            discard(record, false)
        elseif isIdle(record) then
            if record.cue == cue and affinity[sound] == character then preferred = record end
            idle = idle or record
        end
    end
    idle = preferred or idle
    if idle then
        if isIdle(idle) then return idle end
        discard(idle, false)
    end
    if voiceCount >= MAX_VOICES then
        local oldest
        for _, record in pairs(active) do
            if not oldest or record.at < oldest.at then oldest = record end
        end
        if oldest then
            release(oldest, oldest.generation)
            if isIdle(oldest) then return oldest end
        end
    end
    -- release can discard a Sound destroyed before its deferred callback ran.
    -- Replace it only after the slot count fell, without recursive retries.
    if voiceCount >= MAX_VOICES then return nil end
    local sound = template:Clone()
    local record = {sound = sound, generation = 0, active = false}
    voices[sound], voiceCount = record, voiceCount + 1
    sound.Parent = cache
    record.destroying = sound.Destroying:Connect(function() discard(record, false) end)
    return record
end
local function play(cue, actor, character)
    if stopped or typeof(actor) ~= "Instance" then return end
    local current, actorId
    if actor:IsA("Player") and actor.Parent == Players then current, actorId = actor.Character, actor.UserId
    elseif actor:IsA("Model") and actor:GetAttribute("AIControlled") == true and actor:IsDescendantOf(Workspace) then current, actorId = actor, -1
    else return end
    character = character or current
    if not character or character ~= current then return end
    local root = character:FindFirstChild("HumanoidRootPart")
    local hum = character:FindFirstChildOfClass("Humanoid")
    local template = templates[cue]
    if not template or not root or not hum or hum.Health <= 0 then return end
    local camera = Workspace.CurrentCamera
    if actor ~= localPlayer and camera and (camera.CFrame.Position - root.Position).Magnitude > 84 then return end
    debug.profilebegin("HL/GameAudio.play")
    -- Restart an existing cue before choosing an idle voice. Other cue types
    -- may still overlap, up to the same per-character limit as before.
    for _, record in pairs(active) do
        if record.character == character and record.cue == cue then release(record, record.generation); break end
    end
    local actorCount, oldestActor = 0, nil
    for _, record in pairs(active) do
        if record.character == character then
            actorCount += 1
            if not oldestActor or record.at < oldestActor.at then oldestActor = record end
        end
    end
    if actorCount >= MAX_ACTOR_VOICES and oldestActor then release(oldestActor, oldestActor.generation) end
    local record = acquire(template, cue, character)
    if not record then debug.profileend(); return end
    local sound = record.sound
    sound.Name = "HLAudio_" .. cue
    sound.SoundId, sound.Volume = template.SoundId, template.Volume
    sound.RollOffMode = template.RollOffMode
    sound.RollOffMinDistance, sound.RollOffMaxDistance = template.RollOffMinDistance, template.RollOffMaxDistance
    sound.PlaybackSpeed = cue == "WolfTransform" and 1 or 1 + ((actorId % 5) - 2) * 0.015
    sound.TimePosition = 0
    local tool = character:FindFirstChild("EspadaPlata")
    local handle = tool and tool:FindFirstChild("Handle")
    local emitter = cue ~= "WolfTransform" and handle and handle:IsA("BasePart") and handle or root
    sound.Parent = emitter
    record.generation += 1
    local generation = record.generation
    record.character, record.actor, record.cue, record.at, record.active = character, actor, cue, os.clock(), true
    affinity[sound] = character
    active[sound], activeCount = record, activeCount + 1
    record.ended = sound.Ended:Connect(function() release(record, generation) end)
    record.died = hum.Died:Connect(function() release(record, generation) end)
    record.characterRemoving = character.AncestryChanged:Connect(function()
        if not character:IsDescendantOf(Workspace) then release(record, generation) end
    end)
    record.characterDestroying = character.Destroying:Connect(function() release(record, generation) end)
    record.emitterRemoving = emitter.AncestryChanged:Connect(function()
        if not emitter:IsDescendantOf(character) then release(record, generation) end
    end)
    record.expiry = task.delay(cueSettings[cue].duration, function()
        if record.generation ~= generation or not record.active then return end
        record.expiry = nil
        release(record, generation)
    end)
    sound:Play()
    debug.profileend()
end
local function clearPendingVictory()
    if pendingVictoryExpiry then task.cancel(pendingVictoryExpiry); pendingVictoryExpiry = nil end
    pendingVictory = nil
end
local function stopVictory(keepPending)
    if not keepPending then clearPendingVictory() end
    victoryGeneration += 1
    if victoryExpiry then task.cancel(victoryExpiry); victoryExpiry = nil end
    if victoryLoaded then victoryLoaded:Disconnect(); victoryLoaded = nil end
    if victoryEnded then victoryEnded:Disconnect(); victoryEnded = nil end
    for _, connection in ipairs(victoryConnections) do connection:Disconnect() end
    table.clear(victoryConnections); table.clear(victoryWinners)
    victoryAt = nil
    if victorySound and victorySound.Parent then
        victorySound:Stop()
        victorySound.TimePosition = 0
    end
end
local function currentWinner(actor)
    if typeof(actor) ~= "Instance" then return nil end
    if actor:IsA("Player") then return actor.Character end
    if actor:IsA("Model") and actor:GetAttribute("AIControlled") == true and actor:IsDescendantOf(Workspace) then return actor end
end
local function victoryRemaining(data)
    local startedAt, duration = data.startedAt, data.duration
    local now = Workspace:GetServerTimeNow()
    if typeof(startedAt) ~= "number" or startedAt ~= startedAt or math.abs(startedAt) == math.huge
        or typeof(duration) ~= "number" or duration ~= duration or duration <= 0 or duration > 5
        or startedAt > now + 1 then return nil end
    local remaining = duration - math.max(0, now - startedAt)
    return remaining > 0 and remaining or nil
end
local function playVictory(data)
    local startedAt, duration = data.startedAt, data.duration
    if not victorySound or not victorySound.Parent or stopped or state:GetAttribute("Phase") ~= "Resultado"
        or not victoryRemaining(data) then return end
    if victoryAt == startedAt then return end
    stopVictory()
    local elapsed = math.max(0, Workspace:GetServerTimeNow() - startedAt)
    if elapsed >= duration or startedAt > Workspace:GetServerTimeNow() + 1 then return end
    for index, actor in ipairs(typeof(data.players) == "table" and data.players or {}) do
        local character = currentWinner(actor)
        local expected = typeof(data.characters) == "table" and data.characters[index]
        local hum = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if character and character == expected and character:IsDescendantOf(Workspace) and hum and hum.Health > 0 and root then
            table.insert(victoryWinners, {actor = actor, character = character, humanoid = hum})
        end
    end
    -- Result music belongs to the whole match, including distant spectators;
    -- lobby teleports may still be awaiting streaming when this event arrives.
    if #victoryWinners == 0 then return end
    victoryAt = startedAt
    local generation = victoryGeneration
    local function checkWinners()
        for _, winner in ipairs(victoryWinners) do
            if currentWinner(winner.actor) == winner.character and winner.character:IsDescendantOf(Workspace)
                and winner.humanoid.Parent and winner.humanoid.Health > 0 then return end
        end
        stopVictory()
    end
    for _, winner in ipairs(victoryWinners) do
        table.insert(victoryConnections, winner.humanoid.Died:Connect(checkWinners))
        table.insert(victoryConnections, winner.character.AncestryChanged:Connect(checkWinners))
        if winner.actor:IsA("Player") then
            table.insert(victoryConnections, winner.actor:GetPropertyChangedSignal("Character"):Connect(checkWinners))
        end
    end
    local function beginMusic()
        if stopped or generation ~= victoryGeneration or not victorySound.Parent or state:GetAttribute("Phase") ~= "Resultado" then return end
        local offset = math.max(0, Workspace:GetServerTimeNow() - startedAt)
        if offset >= duration then stopVictory(); return end
        local start = Config.Audio.VictoryMusicStart or 0
        if typeof(start) ~= "number" or start ~= start or start < 0 or start == math.huge then start = 0 end
        local position = start + offset * victorySpeed
        if victorySound.TimeLength > 0 and position >= victorySound.TimeLength then stopVictory(); return end
        if victoryLoaded then victoryLoaded:Disconnect(); victoryLoaded = nil end
        victorySound.TimePosition = position
        victorySound:Play()
    end
    victoryEnded = victorySound.Ended:Connect(function() if generation == victoryGeneration then stopVictory() end end)
    victoryExpiry = task.delay(duration - elapsed, function()
        if generation ~= victoryGeneration then return end
        victoryExpiry = nil
        stopVictory()
    end)
    if victorySound.IsLoaded then beginMusic() else victoryLoaded = victorySound.Loaded:Connect(beginMusic) end
end
local function receiveVictory(data)
    if stopped or not victorySound or not victorySound.Parent then return end
    local remaining = victoryRemaining(data)
    if not remaining then return end
    local phase = state:GetAttribute("Phase")
    if phase ~= "Resultado" and phase ~= "Día" and phase ~= "Noche" then return end
    if lastVictoryStartedAt and data.startedAt <= lastVictoryStartedAt then return end
    lastVictoryStartedAt = data.startedAt
    if phase == "Resultado" then playVictory(data); return end
    clearPendingVictory()
    pendingVictory = data
    pendingVictoryExpiry = task.delay(remaining, function()
        pendingVictoryExpiry = nil
        pendingVictory = nil
    end)
end
table.insert(connections, feedback.OnClientEvent:Connect(function(kind, data)
    if kind == "VictoryFX" and typeof(data) == "table" then receiveVictory(data); return end
    if typeof(data) ~= "table" or typeof(data.player) ~= "Instance" then return end
    if kind == "BladeDrawFX" then play("SwordDraw", data.player, data.character)
    elseif kind == "AttackFX" and data.wolf == false then play("SwordSwing", data.player, data.character)
    elseif kind == "TransformFX" then play("WolfTransform", data.player, data.character) end
end))
table.insert(connections, state:GetAttributeChangedSignal("Phase"):Connect(function()
    local phase = state:GetAttribute("Phase")
    if phase == "Resultado" then
        local pending = pendingVictory
        clearPendingVictory()
        if pending then playVictory(pending) end
    else
        -- The event can overtake a final Day -> Night attribute before Result.
        stopVictory(phase == "Noche")
    end
end))
local function bindPlayer(actor)
    playerConnections[actor] = actor.CharacterRemoving:Connect(function(character)
        for _, record in pairs(active) do if record.character == character then release(record, record.generation) end end
    end)
end
for _, actor in ipairs(Players:GetPlayers()) do bindPlayer(actor) end
table.insert(connections, Players.PlayerAdded:Connect(bindPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(function(actor)
    if playerConnections[actor] then playerConnections[actor]:Disconnect(); playerConnections[actor] = nil end
    for _, record in pairs(active) do if record.actor == actor then release(record, record.generation) end end
end))
local function cleanup()
    if stopped then return end
    stopped = true
    stopVictory()
    if victorySound then victorySound:Destroy(); victorySound = nil end
    if coroutine.status(preloadTask) ~= "dead" then task.cancel(preloadTask) end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    for _, connection in pairs(playerConnections) do connection:Disconnect() end
    table.clear(playerConnections)
    while next(voices) do
        local _, record = next(voices)
        discard(record, true)
    end
    cache:Destroy()
    table.clear(templates)
end
table.insert(connections, hud.Destroying:Connect(cleanup))
table.insert(connections, script.Destroying:Connect(cleanup))
