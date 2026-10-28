local Players = game:GetService("Players")
local shared = game.ReplicatedStorage:WaitForChild("HombreLobo")
local network = shared:WaitForChild("Network")
local changed = Instance.new("BindableEvent")
local ClientState = { changed = changed.Event }
local values = { Version = -1 }
local stopped = false

local function accept(snapshot)
    if stopped or typeof(snapshot) ~= "table" or typeof(snapshot.Version) ~= "number"
        or snapshot.Version < values.Version then return end
    values = table.clone(snapshot)
    changed:Fire()
end

function ClientState.get(key, default)
    local value = values[key]
    if value == nil then return default end
    return value
end

function ClientState.snapshot()
    return table.clone(values)
end

local connection = network:WaitForChild("Feedback").OnClientEvent:Connect(function(kind, detail)
    if kind == "PrivateState" then accept(detail) end
end)
task.spawn(function()
    local remote = network:WaitForChild("PrivateSnapshot")
    for _ = 1, 8 do
        if stopped or Players.LocalPlayer.Parent == nil then return end
        local ok, snapshot = pcall(function() return remote:InvokeServer() end)
        if ok and snapshot then accept(snapshot); return end
        task.wait(0.5)
    end
end)

script.Destroying:Connect(function()
    stopped = true
    connection:Disconnect()
    changed:Destroy()
end)

return ClientState