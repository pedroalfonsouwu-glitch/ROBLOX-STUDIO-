-- Private round data stays on the server. Each client receives only its own snapshot.
local Players = game:GetService("Players")
local PlayerState = {}
local sessions = {}
local defaults = {
    Role = "Lobby", Ability = "Ninguna", Hint = "", AbilityReadyAt = 0,
    ChestsOpened = 0, HasBlade = false, Potion = 0, Boots = false,
    LungeReadyAt = 0, DefendReadyAt = 0, Transforming = false,
    HasPistol = false, Ammo = 0, Reloading = false, HasBook = false,
    ResultRoundId = 0, ResultOutcome = "", ResultWinnerRole = "", ResultWinnerNames = "",
    ResultWinnerCount = 0, ResultEndsAt = 0, ResultCameraPosition = Vector3.zero,
}
local event

function PlayerState.create(player)
    if sessions[player] then return end
    local values = table.clone(defaults)
    values.Version = 0
    sessions[player] = { values = values, pending = false, lastRequest = -math.huge }
    for key in pairs(defaults) do player:SetAttribute(key, nil) end
end

function PlayerState.get(player, key)
    local session = sessions[player]
    return session and session.values[key]
end

function PlayerState.snapshot(player)
    local session = sessions[player]
    return session and table.clone(session.values)
end

function PlayerState.set(player, key, value)
    local session = sessions[player]
    if not session or defaults[key] == nil or session.values[key] == value then return end
    assert(typeof(value) == typeof(defaults[key]), "Invalid private state value")
    session.values[key] = value
    session.values.Version += 1
    if session.pending then return end
    session.pending = true
    task.defer(function()
        if sessions[player] ~= session then return end
        session.pending = false
        if event and typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players then
            event:FireClient(player, "PrivateState", table.clone(session.values))
        end
    end)
end

function PlayerState.attach(network)
    event = network:WaitForChild("Feedback")
    local remote = Instance.new("RemoteFunction")
    remote.Name = "PrivateSnapshot"
    remote.OnServerInvoke = function(player, ...)
        if select("#", ...) ~= 0 then return nil end
        local session = sessions[player]
        if not session then return nil end
        local now = os.clock()
        if now - session.lastRequest < 0.25 then return nil end
        session.lastRequest = now
        return table.clone(session.values)
    end
    remote.Parent = network
end

function PlayerState.remove(player)
    sessions[player] = nil
end

return PlayerState
