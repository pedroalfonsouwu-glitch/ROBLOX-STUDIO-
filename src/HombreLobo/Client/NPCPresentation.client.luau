-- Prepared client locomotion variant: one existing 20 Hz pose loop, NPCs and opted-in AI.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local records, active, activeAI, connections = {}, {}, {}, {}
local animationConnection, scanTask
local stopped, accumulator = false, 0
local DISTANCE_SQUARED, SCAN_INTERVAL, POSE_INTERVAL = 96 * 96, 0.35, 1 / 20
local MOTION_MEMORY, MIN_SPEED_SQUARED = 0.12, 0.5 * 0.5
local identity = CFrame.identity
-- The local composition bridge stays outside the avatar hierarchy and never replicates.
local bridge = Instance.new("Folder")
bridge.Name, bridge.Parent = "AILocomotion", script
local walkNames = {"RightShoulder", "LeftShoulder", "RightHip", "LeftHip"}

local function reset(record)
    if record.ai then
        record.walkPhase, record.lastPoseAt, record.lastPosition, record.lastMotionAt = 0, nil, nil, nil
        for _, entry in ipairs(record.walkEntries) do
            if entry.base.Parent then entry.base.Value = identity end
            if entry.joint.Parent and entry.owner.Parent and not entry.owner.Value then entry.joint.Transform = identity end
        end
    else
        for _, joint in pairs(record.joints) do if joint.Parent then joint.Transform = identity end end
    end
end
local function remove(model)
    local record = records[model]
    if not record then return end
    reset(record)
    active[record], activeAI[record], records[model] = nil, nil, nil
    for _, connection in ipairs(record.connections) do connection:Disconnect() end
    table.clear(record.connections)
    if record.bridge then record.bridge:Destroy() end
    if not next(active) and animationConnection then animationConnection:Disconnect(); animationConnection = nil end
end
local function add(model, ai)
    if stopped or not model:IsA("Model") or records[model] then return end
    local root = model.PrimaryPart
    if not root then return end -- Atomic rigs arrive with complete joints and PrimaryPart.
    local joints = {}
    for _, child in ipairs(model:GetDescendants()) do
        if child:IsA("Motor6D") then joints[child.Name:gsub(" ", "")] = child end
    end
    if not joints.RootJoint or not joints.Neck or not joints.LeftShoulder or not joints.RightShoulder
        or not joints.LeftHip or not joints.RightHip then return end
    local record = {model = model, root = root, joints = joints, ai = ai == true, connections = {}}
    if record.ai then
        if model:GetAttribute("AIControlled") ~= true then return end
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        record.humanoid, record.walkEntries, record.walkPhase = humanoid, {}, 0
        local floorParams = RaycastParams.new()
        floorParams.FilterType, floorParams.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, {model}
        floorParams.IgnoreWater, floorParams.RespectCanCollide = true, true
        floorParams.CollisionGroup = root.CollisionGroup
        record.floorParams = floorParams
        local leg = model:FindFirstChild("Left Leg")
        local legHeight = leg and leg:IsA("BasePart") and leg.Size.Y or 0
        -- R6 root height is half the root plus one leg and HipHeight. This short
        -- local query also works when a server-owned Humanoid reports Air here.
        local floorReach = math.clamp(root.Size.Y / 2 + legHeight + humanoid.HipHeight + 0.6, 1, 6)
        record.floorDirection = Vector3.new(0, -floorReach, 0)
        local group = Instance.new("Folder")
        group.Name = model.Name
        for index, name in ipairs(walkNames) do
            local entry = Instance.new("Folder")
            entry.Name = name
            local target, base, owner = Instance.new("ObjectValue"), Instance.new("CFrameValue"), Instance.new("BoolValue")
            target.Name, target.Value, target.Parent = "Joint", joints[name], entry
            base.Name, base.Value, base.Parent = "Base", identity, entry
            owner.Name, owner.Value, owner.Parent = "CombatOwned", false, entry
            table.insert(record.walkEntries, {joint = joints[name], base = base, owner = owner, sign = index <= 2 and 1 or -1})
            entry.Parent = group
        end
        record.bridge = group
        table.insert(record.connections, humanoid.Died:Connect(function() remove(model) end))
        table.insert(record.connections, model:GetAttributeChangedSignal("AILocomotionActive"):Connect(function()
            if model:GetAttribute("AILocomotionActive") ~= true then reset(record); active[record], activeAI[record] = nil, nil end
        end))
        table.insert(record.connections, root:GetPropertyChangedSignal("Anchored"):Connect(function()
            if root.Anchored then reset(record) end
        end))
        group.Parent = bridge -- Publish each complete local bridge atomically.
    end
    records[model] = record
    table.insert(record.connections, model.Destroying:Connect(function() remove(model) end))
    table.insert(record.connections, model.AncestryChanged:Connect(function()
        if not model:IsDescendantOf(Workspace) then remove(model) end
    end))
end
local function poseNPC(record, now)
    local joints, model = record.joints, record.model
    local state = model:GetAttribute("NPCState")
    local walking = state == "Walking"
    local phase = (now - (model:GetAttribute("WalkStartedAt") or now)) * 7
    local swing = walking and math.sin(phase) * 0.32 or math.sin(now * 1.5) * 0.035
    local breath = math.sin(now * 1.7) * 0.025
    joints.RootJoint.Transform = CFrame.new(0, walking and math.abs(math.sin(phase)) * 0.045 or breath, 0)
    joints.Neck.Transform = CFrame.Angles(walking and 0 or math.sin(now * 0.8) * 0.035, 0, 0)
    joints.LeftShoulder.Transform = CFrame.Angles(swing, 0, -0.025)
    joints.RightShoulder.Transform = CFrame.Angles(-swing, 0, 0.025)
    joints.LeftHip.Transform = CFrame.Angles(-swing, 0, 0)
    joints.RightHip.Transform = CFrame.Angles(swing, 0, 0)
    local greeting = now - (model:GetAttribute("GreetingAt") or -100)
    if greeting >= 0 and greeting < 1.4 then
        local envelope = math.min(greeting / 0.2, 1, (1.4 - greeting) / 0.2)
        joints.RightShoulder.Transform = CFrame.Angles(-0.3 * envelope, 0,
            (2.2 + math.sin(greeting * 14) * 0.18) * envelope)
    end
end
local function poseAI(record, now)
    local root, hum = record.root, record.humanoid
    local sampleElapsed = now - (record.lastPoseAt or now)
    local elapsed = math.clamp(sampleElapsed, 0, 0.2)
    local position, previousPosition = root.Position, record.lastPosition
    record.lastPoseAt, record.lastPosition = now, position
    local velocity = root.AssemblyLinearVelocity
    local localSpeedSquared = velocity.X * velocity.X + velocity.Z * velocity.Z
    local observedSpeedSquared = 0
    if previousPosition and sampleElapsed > 0 and sampleElapsed <= 0.25 then
        local displacement = position - previousPosition
        observedSpeedSquared = (displacement.X * displacement.X + displacement.Z * displacement.Z) / (sampleElapsed * sampleElapsed)
    end
    local maxSpeed = math.max(hum.WalkSpeed * 4, 64)
    -- Remote assemblies can have no useful local velocity. Observe replicated
    -- positions too, while rejecting relocation and bridging sparse updates.
    local validObservedMotion = observedSpeedSquared > MIN_SPEED_SQUARED and observedSpeedSquared <= maxSpeed * maxSpeed
    local validLocalMotion = localSpeedSquared > MIN_SPEED_SQUARED and localSpeedSquared <= maxSpeed * maxSpeed
    if validObservedMotion or validLocalMotion then record.lastMotionAt = now end
    local allowed = hum.Health > 0 and not root.Anchored and record.model:GetAttribute("AILocomotionActive") == true
    local recentMotion = record.lastMotionAt ~= nil and now - record.lastMotionAt <= MOTION_MEMORY
    -- FloorMaterial is not replicated either. Cast only for a nearby moving AI,
    -- at the existing 20 Hz cadence, using collidable local geometry as ground.
    local floor = allowed and recentMotion and Workspace:Raycast(position, record.floorDirection, record.floorParams)
    local moving = floor and floor.Normal.Y > 0.35 or false
    if moving then record.walkPhase += elapsed * 9 end
    local swing = moving and math.sin(record.walkPhase) * 0.38 or 0
    for _, entry in ipairs(record.walkEntries) do
        if entry.joint.Parent and entry.base.Parent and entry.owner.Parent then
            local value = CFrame.Angles(0, 0, swing * entry.sign)
            if entry.base.Value ~= value then entry.base.Value = value end
        end
    end
end
local function applyAI(record)
    local allowed = record.humanoid.Health > 0 and not record.root.Anchored
        and record.model:GetAttribute("AILocomotionActive") == true
    for _, entry in ipairs(record.walkEntries) do
        if entry.joint.Parent and entry.base.Parent and entry.owner.Parent and not entry.owner.Value then
            local value = allowed and entry.base.Value or identity
            if entry.joint.Transform ~= value then entry.joint.Transform = value end
        end
    end
end
local function animate(dt)
    accumulator += dt
    if accumulator >= POSE_INTERVAL then
        accumulator %= POSE_INTERVAL
        local now = Workspace:GetServerTimeNow()
        for record in pairs(active) do
            if records[record.model] == record and record.model:IsDescendantOf(Workspace) then
                if record.ai then poseAI(record, now) else poseNPC(record, now) end
            end
        end
    end
    -- Compute gait at 20 Hz, then reapply cached AI transforms after Animator on
    -- this same existing callback. During poses FX owns output and composes Walk * FX.
    for record in pairs(activeAI) do
        if records[record.model] == record and record.model:IsDescendantOf(Workspace) then applyAI(record) end
    end
end
local function scan()
    scanTask = nil
    if stopped then return end
    local root = player.Parent == Players and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local count = 0
    for model, record in pairs(records) do
        local offset = root and record.root.Position - root.Position
        local near = offset ~= nil and offset:Dot(offset) <= DISTANCE_SQUARED and model:IsDescendantOf(Workspace)
        if record.ai then near = near and record.humanoid.Health > 0 and model:GetAttribute("AILocomotionActive") == true end
        if near then active[record] = true; if record.ai then activeAI[record] = true end; count += 1
        elseif active[record] then active[record], activeAI[record] = nil, nil; reset(record) end
    end
    if count > 0 and not animationConnection then
        accumulator = 0
        animationConnection = RunService.PreSimulation:Connect(animate)
    elseif count == 0 and animationConnection then
        animationConnection:Disconnect(); animationConnection = nil
    end
    scanTask = task.delay(SCAN_INTERVAL, scan)
end
local function cleanup()
    if stopped then return end
    stopped = true
    if scanTask then task.cancel(scanTask); scanTask = nil end
    if animationConnection then animationConnection:Disconnect(); animationConnection = nil end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for model in pairs(records) do remove(model) end
    table.clear(active); table.clear(activeAI); table.clear(connections)
    bridge:Destroy()
end
table.insert(connections, CollectionService:GetInstanceAddedSignal("HombreLoboNPC"):Connect(function(model) add(model, false) end))
table.insert(connections, CollectionService:GetInstanceRemovedSignal("HombreLoboNPC"):Connect(remove))
table.insert(connections, CollectionService:GetInstanceAddedSignal("HombreLoboAI"):Connect(function(model) add(model, true) end))
table.insert(connections, CollectionService:GetInstanceRemovedSignal("HombreLoboAI"):Connect(remove))
table.insert(connections, script.Destroying:Connect(cleanup))
local playerGui = player:WaitForChild("PlayerGui")
local function bindHUD(screen)
    if screen.Name == "HombreLoboHUD" then table.insert(connections, screen.Destroying:Connect(cleanup)) end
end
table.insert(connections, playerGui.ChildAdded:Connect(bindHUD))
local hud = playerGui:FindFirstChild("HombreLoboHUD")
if hud then bindHUD(hud) end
for _, model in ipairs(CollectionService:GetTagged("HombreLoboNPC")) do add(model, false) end
for _, model in ipairs(CollectionService:GetTagged("HombreLoboAI")) do add(model, true) end
scanTask = task.delay(SCAN_INTERVAL, scan)
