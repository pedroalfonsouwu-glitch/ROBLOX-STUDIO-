-- Oro de cuenta solamente; los objetos y roles de ronda no se guardan.
-- Las dependencias inyectables permiten UNIT_STUB sin fingir acceso a Roblox.
local Persistence = {}
Persistence.__index = Persistence
local MAX_GOLD = 2147483647
Persistence.MaxGold = MAX_GOLD

local function integer(value, maximum)
    return type(value) == "number" and value == value and value >= 0
        and value <= maximum and value % 1 == 0
end
local function valid(data)
    return type(data) == "table" and data.Version == 1 and integer(data.Gold, MAX_GOLD)
        and (data.LockId == nil or (type(data.LockId) == "string"
            and integer(data.LockExpiresAt, 9007199254740991)))
        and (data.WriteId == nil or type(data.WriteId) == "string")
end
local function metadata(info, userId)
    local ids = info and table.clone(info:GetUserIds()) or {}
    if not table.find(ids, userId) then table.insert(ids, userId) end
    return ids, info and info:GetMetadata() or {}
end
local function status(profile, mode, ready, saveError)
    profile.mode, profile.ready = mode, ready
    profile.player:SetAttribute("ProfileMode", mode)
    profile.player:SetAttribute("ProfileReady", ready and not profile.closing)
    profile.player:SetAttribute("ProfileSaveError", saveError == true)
end

function Persistence.new(options)
    options = options or {}
    local self = setmetatable({}, Persistence)
    self.store = options.Store
    self.initError = options.InitError
    self.startingGold = options.StartingGold or 80
    assert(integer(self.startingGold, MAX_GOLD), "StartingGold invalido")
    self.now = options.Now or os.time
    self.clock = options.Clock or os.clock
    self.wait = options.Wait or task.wait
    self.spawn = options.Spawn or task.spawn
    self.guid = assert(options.Guid, "Guid requerido")
    self.log = options.Warn or warn
    self.jitter = options.Jitter or function() return math.random(0, 10) end
    self.interval = options.SaveInterval or 30
    self.lease = options.LeaseSeconds or 120
    self.attempts = options.Attempts or 3
    assert(self.interval > 0 and self.lease > self.interval + 10, "Lease demasiado corto")
    self.profiles = {}
    self.closing = false
    return self
end

function Persistence:IsReady(player)
    local p = self.profiles[player]
    return p ~= nil and p.ready and not p.closing
        and (not p.saveable or not p.leaseExpires or self.now() < p.leaseExpires)
end

function Persistence:_load(p)
    local reason = "DataStoreError"
    for attempt = 1, self.attempts do
        if self.closing or p.closing then return false, "Closing" end
        local decision = "DataStoreError"
        local ok, result = pcall(function()
            return self.store:UpdateAsync(p.key, function(old, info)
                local data = old
                if data == nil then data = {Version = 1, Gold = self.startingGold} end
                if not valid(data) then decision = "InvalidData"; return nil end
                if data.LockId and data.LockId ~= p.token and data.LockExpiresAt > self.now() then
                    decision = "SessionLocked"; return nil
                end
                local nextData = table.clone(data)
                nextData.LockId, nextData.LockExpiresAt = p.token, self.now() + self.lease
                -- A transport failure can hide a committed lock from this caller.
                p.loadClaimPending = true
                decision = "Ready"
                local ids, meta = metadata(info, p.player.UserId)
                return nextData, ids, meta
            end)
        end)
        if ok and valid(result) and result.LockId == p.token then return true, result end
        reason = ok and decision or "DataStoreError"
        if reason == "InvalidData" then break end
        if attempt < self.attempts then self.wait(2 ^ (attempt - 1)) end
    end
    return false, reason
end

function Persistence:Attach(player, gold)
    if self.profiles[player] then return end
    assert(gold ~= nil, "Oro requerido")
    local p = {player = player, gold = gold, token = self.guid(), key = "User_" .. tostring(player.UserId),
        loading = true, sequence = 0, nextSave = self.clock() + self.interval + self.jitter()}
    self.profiles[player] = p
    gold.Value = self.startingGold
    status(p, "Temporary", false, false)
    self.spawn(function()
        if self.closing then p.closing = true end
        if not self.store or not integer(player.UserId, 9007199254740991) or player.UserId == 0 then
            p.loading, p.saveable = false, false
            status(p, self.initError and "LoadFailed" or "Temporary", true, self.initError ~= nil)
        else
            local ok, result = self:_load(p)
            if ok then
                p.saveable, p.leaseExpires = true, result.LockExpiresAt
                p.loadClaimPending = nil
                gold.Value = result.Gold
                if p.closing then p.finalGold = result.Gold end
                status(p, "Saved", true, false)
            else
                p.saveable = false
                status(p, "LoadFailed", true, true)
                self.log("[Persistence] Carga sin guardado: " .. tostring(player.UserId) .. " " .. tostring(result))
            end
            p.loading = false
        end
        if p.closing then self:Close(player) end
    end)
end

-- Release an unconfirmed load without ever writing the fallback balance.
function Persistence:_releaseLoadClaim(p, deadline)
    p.busy = true
    local success, reason = false, "DataStoreError"
    for attempt = 1, self.attempts do
        if deadline and self.clock() >= deadline then reason = "Deadline"; break end
        local decision = "DataStoreError"
        local ok, result = pcall(function()
            return self.store:UpdateAsync(p.key, function(old, info)
                if old == nil or (type(old) == "table" and old.LockId ~= p.token) then
                    decision = "ClaimGone"
                    return nil
                end
                if not valid(old) then decision = "InvalidData"; return nil end
                local nextData = table.clone(old)
                nextData.LockId, nextData.LockExpiresAt = nil, nil
                decision = "Released"
                local ids, meta = metadata(info, p.player.UserId)
                return nextData, ids, meta
            end)
        end)
        if ok and (decision == "ClaimGone" or (decision == "Released"
            and valid(result) and result.LockId ~= p.token)) then
            success = true
            p.loadClaimPending = nil
            break
        end
        reason = ok and decision or "DataStoreError"
        if reason == "InvalidData" then break end
        if attempt < self.attempts then
            local delay = 2 ^ (attempt - 1)
            if deadline and self.clock() + delay >= deadline then break end
            self.wait(delay)
        end
    end
    p.busy = false
    if not success then
        p.player:SetAttribute("ProfileSaveError", true)
        self.log("[Persistence] Liberacion de carga pendiente: " .. tostring(p.player.UserId) .. " " .. reason)
    end
    return success, reason
end

function Persistence:Save(player, release, deadline)
    local p = self.profiles[player]
    if not p or not p.saveable or p.loading then return false, "NotWritable" end
    if p.busy then return false, "Busy" end
    if p.closing and not release then return false, "Closing" end
    local gold = p.closing and p.finalGold or p.gold.Value
    if not integer(gold, MAX_GOLD) then
        p.player:SetAttribute("ProfileSaveError", true)
        if not p.invalidGold then self.log("[Persistence] Oro invalido sin guardar: " .. tostring(player.UserId)) end
        p.invalidGold = true
        return false, "InvalidGold"
    end
    p.invalidGold = nil
    p.busy = true
    p.sequence += 1
    local writeId = p.token .. ":" .. tostring(p.sequence)
    if release then
        p.releaseWriteId = p.releaseWriteId or writeId
        writeId = p.releaseWriteId
    end
    local success, reason = false, "DataStoreError"
    for attempt = 1, self.attempts do
        if deadline and self.clock() >= deadline then reason = "Deadline"; break end
        local decision = "DataStoreError"
        local ok, result = pcall(function()
            return self.store:UpdateAsync(p.key, function(old, info)
                if not valid(old) then decision = "InvalidData"; return nil end
                -- A release response can be lost after committing. Its retry never writes again.
                if release and old.WriteId == writeId then decision = "AlreadySaved"; return nil end
                if old.LockId ~= p.token then decision = "SessionLost"; return nil end
                local nextData = table.clone(old)
                nextData.Gold, nextData.WriteId = gold, writeId
                nextData.LockId = release and nil or p.token
                nextData.LockExpiresAt = release and nil or (self.now() + self.lease)
                -- Lua's and/or idiom cannot represent nil; explicitly remove the released lock.
                if release then nextData.LockId, nextData.LockExpiresAt = nil, nil end
                decision = "Ready"
                local ids, meta = metadata(info, player.UserId)
                return nextData, ids, meta
            end)
        end)
        if ok and (decision == "AlreadySaved" or (valid(result) and result.WriteId == writeId)) then
            success = true
            p.leaseExpires = result and result.LockExpiresAt or nil
            break
        end
        reason = ok and decision or "DataStoreError"
        if reason == "SessionLost" or reason == "InvalidData" then break end
        if attempt < self.attempts then
            local delay = 2 ^ (attempt - 1)
            if deadline and self.clock() + delay >= deadline then break end
            self.wait(delay)
        end
    end
    p.busy = false
    if success then
        if not release then status(p, "Saved", true, false) end
        p.player:SetAttribute("ProfileSaveError", false)
        return true
    end
    p.player:SetAttribute("ProfileSaveError", true)
    if reason == "SessionLost" or reason == "InvalidData" then
        p.saveable = false
        status(p, "LoadFailed", false, true)
    end
    self.log("[Persistence] Guardado pendiente: " .. tostring(player.UserId) .. " " .. reason)
    return false, reason
end

function Persistence:Close(player, deadline)
    local p = self.profiles[player]
    if not p then return true end
    deadline = deadline or (self.clock() + 25)
    p.closing = true
    p.player:SetAttribute("ProfileReady", false)
    if not p.loading and p.finalGold == nil then p.finalGold = p.gold.Value end
    if p.closeBusy then
        while self.profiles[player] == p and p.closeBusy and self.clock() < deadline do self.wait(0.05) end
        return self.profiles[player] ~= p
    end
    p.closeBusy = true
    while (p.loading or p.busy) and self.clock() < deadline do self.wait(0.05) end
    local done = not p.loading and not p.saveable and not p.loadClaimPending
    while not done and not p.loading and not p.busy and self.clock() < deadline do
        local reason
        if p.saveable then done, reason = self:Save(player, true, deadline)
        else done, reason = self:_releaseLoadClaim(p, deadline) end
        if not p.saveable and not p.loadClaimPending then done = true end
        if not done and (reason == "InvalidGold" or reason == "InvalidData") then break end
        if not done then self.wait(0.5) end
    end
    p.closeBusy = false
    if done then self.profiles[player] = nil end
    return done
end

function Persistence:Step()
    for player, p in pairs(self.profiles) do
        if p.ready and not p.closing then p.player:SetAttribute("ProfileReady", self:IsReady(player)) end
        if not p.scheduled and not p.loading and not p.busy and self.clock() >= p.nextSave then
            p.nextSave = self.clock() + self.interval + self.jitter()
            if p.closing or p.saveable then
                p.scheduled = true
                self.spawn(function()
                    if p.closing then self:Close(player) else self:Save(player, false) end
                    p.scheduled = false
                end)
            end
        end
    end
end

function Persistence:CloseAll(timeout)
    self.closing = true
    local deadline, pending, completed = self.clock() + (timeout or 25), 0, true
    for player in pairs(self.profiles) do
        pending += 1
        self.spawn(function()
            if not self:Close(player, deadline) then completed = false end
            pending -= 1
        end)
    end
    while pending > 0 and self.clock() < deadline do self.wait(0.05) end
    return pending == 0 and completed
end

function Persistence.start(players, options)
    options = options or {}
    local run = game:GetService("RunService")
    assert(run:IsServer(), "Persistence requiere servidor")
    local store, initError
    -- Studio never accesses production data. An isolated test universe can opt in explicitly.
    local enabled = game.GameId > 0 and (not run:IsStudio() or options.AllowStudio == true)
    if enabled then
        local ok, result = pcall(function()
            return game:GetService("DataStoreService"):GetDataStore(options.StoreName or "HombreLobo_Account_v1")
        end)
        if ok then store = result else initError = tostring(result) end
    end
    local dependencies = table.clone(options)
    dependencies.Store, dependencies.InitError = store, initError
    dependencies.Guid = function() return game:GetService("HttpService"):GenerateGUID(false) end
    local self = Persistence.new(dependencies)
    players.PlayerRemoving:Connect(function(player) self:Close(player) end)
    game:BindToClose(function()
        if not self:CloseAll(25) then warn("[Persistence] Cierre con perfiles pendientes de guardado.") end
    end)
    task.spawn(function()
        while not self.closing do task.wait(1); self:Step() end
    end)
    return self
end
return Persistence
