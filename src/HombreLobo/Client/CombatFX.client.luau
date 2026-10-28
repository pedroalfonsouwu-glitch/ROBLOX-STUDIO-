-- Local visuals for attacks accepted by the server; damage and input remain on the server.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local localPlayer = Players.LocalPlayer
local shared = game.ReplicatedStorage:WaitForChild("HombreLobo")
local Config = require(shared:WaitForChild("Config"))
local ExperienceSettings = require(script.Parent:WaitForChild("ExperienceSettings"))
local screen = localPlayer:WaitForChild("PlayerGui"):WaitForChild("HombreLoboHUD")
local feedback = shared:WaitForChild("Network"):WaitForChild("Feedback")
local state = shared:WaitForChild("State")
local folder = Instance.new("Folder")
folder.Name, folder.Parent = "HombreLoboClientFX", Workspace
local random = Random.new()
local stopped = false
local connections = {}
local poses = setmetatable({}, { __mode = "k" })
local rigs = setmetatable({}, { __mode = "k" })
local bookGrips = setmetatable({}, { __mode = "k" })
local victoryDances = setmetatable({}, { __mode = "k" })
local pendingVictory, lastVictoryStartedAt
local locomotion, locomotionEntries = {}, {}
local clearBookGrip, clearVictoryDance
local poseAnimationConnection, poseSimulationConnection
local poseCount = 0
local ownCharacter, ownRoot, ownHumanoid
local ownConnections, healthConnection = {}, nil
local previewConnection, attackConnection
-- Bounded retention holds one simultaneous four-player wave (248 pieces).
local POOL_LIMIT, FAR_DISTANCE = 256, 256
local PREVIEW_INTERVAL, GROUND_INTERVAL = 1 / 30, 1 / 4
local MOVE_EPSILON_SQUARED = 0.01 * 0.01
local previewColor = Color3.fromRGB(162, 212, 202)
local wolfColor, bladeColor = Color3.fromRGB(240, 127, 99), Color3.fromRGB(183, 228, 255)
local fadeInfo = { ring = TweenInfo.new(0.38), arc = TweenInfo.new(0.3) }
local sparkInfo = TweenInfo.new(0.45)
local groundParams, groundCharacter = RaycastParams.new(), nil
local groundDirection = Vector3.new(0, -30, 0)
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function track(connection)
    table.insert(connections, connection)
    return connection
end
local function disconnectAll(list)
    for _, connection in ipairs(list) do connection:Disconnect() end
    table.clear(list)
end
local function forgetGroundCharacter(character)
    if groundCharacter == character then
        groundCharacter = nil
        groundParams.FilterDescendantsInstances = { folder }
    end
end
local function ground(center, character)
    if groundCharacter ~= character then
        groundCharacter = character
        groundParams.FilterDescendantsInstances = { character, folder }
    end
    local hit = Workspace:Raycast(center, groundDirection, groundParams)
    return hit and hit.Position.Y + 0.08 or center.Y - 3
end
local function newPart(name)
    local part = Instance.new("Part")
    part.Name, part.Anchored = name, true
    part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
    part.Material = Enum.Material.Neon
    return part
end
local function configureSegment(part, a, b, color, thickness)
    part.Color, part.Transparency = color, 0
    part.Size = Vector3.new(thickness, thickness, math.max((b - a).Magnitude, 0.01))
    part.CFrame = CFrame.lookAt((a + b) / 2, b)
end

-- The retained pool is bounded; overflow still renders and is destroyed after its lease.
local free = { ring = {}, arc = {}, spark = {} }
local entries, retained = {}, 0
local function release(entry, generation)
    if stopped or not entry.active or entry.generation ~= generation then return end
    entry.active, entry.releaseTask = false, nil
    if entry.kind == "spark" or not entry.pooled then
        if entry.completed then entry.completed:Disconnect(); entry.completed = nil end
        if entry.tween then entry.tween:Cancel(); entry.tween:Destroy(); entry.tween = nil end
    elseif entry.tween then
        entry.tween:Cancel()
    end
    entry.part.Parent = nil
    if entry.pooled then
        table.insert(free[entry.kind], entry)
    else
        entries[entry] = nil
        entry.part:Destroy()
    end
end
local function scheduleRelease(entry, generation)
    entry.releaseTask = task.delay(0.05, function() release(entry, generation) end)
end
local function lease(kind, a, b, color, thickness)
    local entry = table.remove(free[kind])
    if not entry then
        local pooled = retained < POOL_LIMIT
        entry = { part = newPart("Brisa"), kind = kind, pooled = pooled, generation = 0, active = false }
        entries[entry] = true
        if pooled then retained = retained + 1 end
        if kind ~= "spark" then
            entry.tween = TweenService:Create(entry.part, fadeInfo[kind], { Transparency = 1 })
            entry.completed = entry.tween.Completed:Connect(function(playbackState)
                if not stopped and entry.active and playbackState == Enum.PlaybackState.Completed then
                    scheduleRelease(entry, entry.generation)
                end
            end)
        end
    end
    entry.generation = entry.generation + 1
    entry.active = true
    if entry.tween then entry.tween:Cancel() end
    configureSegment(entry.part, a, b, color, thickness)
    entry.part.Parent = folder
    return entry
end
local function fade(kind, a, b, color, thickness)
    local entry = lease(kind, a, b, color, thickness)
    entry.tween:Play()
end
local function spark(a, b, destination, color)
    local entry = lease("spark", a, b, color, 0.08)
    local generation = entry.generation
    entry.tween = TweenService:Create(entry.part, sparkInfo, { Position = destination, Transparency = 1 })
    entry.completed = entry.tween.Completed:Connect(function(playbackState)
        if not stopped and entry.active and entry.generation == generation and playbackState == Enum.PlaybackState.Completed then
            scheduleRelease(entry, generation)
        end
    end)
    entry.tween:Play()
end

local function stopPoseFrames()
    if poseAnimationConnection then poseAnimationConnection:Disconnect(); poseAnimationConnection = nil end
    if poseSimulationConnection then poseSimulationConnection:Disconnect(); poseSimulationConnection = nil end
end
local function locomotionFor(joint)
    local record = locomotion[joint]
    if record and record.base.Parent and record.owner.Parent then return record end
end
local function claimLocomotion(joint, pose)
    local record = locomotionFor(joint)
    if record then
        record.owner.Value = true
        pose.locomotionApplied = true
    end
end
local function locomotionBase(joint, pose)
    local record = locomotionFor(joint)
    if record then
        pose.locomotionApplied = true
        return record.base.Value
    end
    if pose.locomotionApplied then return CFrame.identity end
    return joint.Transform
end
local function restorePoseTransform(joint, pose)
    if pose.appliedBase then
        -- Leave an external transform change intact; remove only our previous overlay.
        if joint.Parent and joint.Transform == pose.appliedTransform then
            joint.Transform = pose.locomotionApplied and locomotionBase(joint, pose) or pose.appliedBase
        end
        pose.appliedBase, pose.appliedTransform = nil, nil
    end
end
-- Hand-authored from the user's video, 10.75--15.75 s at quarter-second
-- intervals. Each arm stores shoulder pitch/inward yaw/inward roll, elbow
-- flexion and palm turn (degrees). These are observed poses, not a walk cycle.
local VICTORY_REFERENCE_BPM = 171.43
local victoryKeys = {
    {0.00, {52, 28, 32, 94,  0}, { 2,  0,  1,  5,  0}, -0.8, -1.0, -1},
    {0.25, { 4,  0,  2,  8,  0}, {30, 16, 34, 61,  0}, -0.3, -0.5, -1},
    {0.50, { 2,  0,  1,  5,  0}, {55, 30, 34, 96,  0},  0.7,  0.8,  1},
    {0.75, {42, 26, 42, 43, 35}, { 3,  0,  1,  6,  0},  0.4,  0.4,  1},
    {1.00, {17, 12, 22, 48, 20}, { 2,  0,  0,  5,  0}, -0.1, -0.2,  0},
    {1.25, {54, 30, 34, 97,  0}, { 2,  0,  1,  5,  0}, -0.8, -1.1, -1},
    {1.50, {34, 22, 38, 62, 15}, { 3,  0,  2,  7,  0}, -0.4, -0.5, -1},
    {1.75, { 3,  0,  2,  6,  0}, {36, 20, 38, 57,  0},  0.2,  0.3,  0},
    {2.00, { 2,  0,  1,  5,  0}, {56, 32, 35, 96,  0},  0.9,  1.1,  1},
    {2.25, {35, 18, 30, 63, 10}, { 4,  0,  2,  8,  0},  0.3,  0.4,  1},
    {2.50, {16, 10, 16, 72, 70}, { 2,  0,  1,  5,  0}, -0.2, -0.2,  0},
    {2.75, { 2,  0,  1,  5,  0}, {53, 30, 32, 95,  0},  0.9,  1.0,  1},
    {3.00, { 3,  0,  2,  6,  0}, {22, 12, 24, 50, 20},  0.4,  0.5,  1},
    {3.25, {56, 32, 35, 98,  0}, { 2,  0,  1,  5,  0}, -1.0, -1.2, -1},
    {3.50, {43, 24, 44, 42, 60}, { 3,  0,  1,  6,  0}, -0.4, -0.4, -1},
    {3.75, { 4,  0,  2,  8,  0}, {21, 10, 23, 48, 15},  0.1,  0.2,  0},
    {4.00, { 2,  0,  1,  5,  0}, {54, 30, 34, 97,  0},  0.8,  1.0,  1},
    {4.25, { 3,  0,  1,  6,  0}, {37, 20, 35, 69,  0},  0.4,  0.5,  1},
    {4.50, {35, 20, 38, 61, 10}, { 3,  0,  2,  7,  0}, -0.2, -0.3,  0},
    {4.75, {53, 30, 34, 96,  0}, { 2,  0,  1,  5,  0}, -0.8, -1.0, -1},
    {5.00, { 4,  0,  2,  8,  0}, {23, 12, 25, 52, 15}, -0.2, -0.3,  0},
}
local function degrees(x, y, z)
    return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end
local victoryFrames = {}
for _, key in ipairs(victoryKeys) do
    local lean, yaw, support = key[4], key[5], key[6]
    local frame = {
        beat = key[1] * VICTORY_REFERENCE_BPM / 60,
        Root = degrees(0, yaw, lean), Waist = degrees(0, -yaw * 0.4, lean * 0.25),
        Neck = degrees(0, -yaw * 0.7, -lean * 0.4), Tail = degrees(0, yaw * 2, 0),
    }
    for index, side in ipairs({1, -1}) do
        local arm, prefix = key[index + 1], side > 0 and "Right" or "Left"
        frame[prefix .. "Shoulder"] = degrees(arm[1], side * arm[2], -side * arm[3])
        frame[prefix .. "Elbow"] = degrees(arm[4], 0, 0)
        frame[prefix .. "Wrist"] = degrees(0, -side * arm[5], 0)
        -- R6 has one rigid arm instead of an upper arm and forearm. Retarget
        -- the hand-to-chest reach with its shoulder rather than inventing bones.
        frame[prefix .. "ShoulderR6"] = degrees(arm[1] * 0.35 + arm[4] * 0.08,
            -side * (arm[2] * 0.8 + arm[4] * 0.08), -side * math.min(82, arm[3] + arm[4] * 0.45))
        -- Counter the small pelvis lean so feet stay near their contact point.
        -- There is no forward/back hip swing, root translation or walking step.
        frame[prefix .. "Hip"] = degrees(0, 0, -lean + side * support * 0.2)
        frame[prefix .. "Knee"] = degrees(-0.4 - math.max(0, side * support) * 0.4, 0, 0)
    end
    table.insert(victoryFrames, frame)
end
local function danceOffset(pose, now)
    local dance = pose.dance
    if dance.sampledAt ~= now then
        local elapsed = math.max(0, now - dance.startedAt)
        local beat = elapsed * dance.bpm / 60
        local index = dance.keyIndex or 1
        while index < #victoryFrames - 1 and victoryFrames[index + 1].beat <= beat do index += 1 end
        dance.keyIndex = index
        dance.a, dance.b = victoryFrames[index], victoryFrames[index + 1]
        dance.alpha = math.clamp((beat - dance.a.beat) / (dance.b.beat - dance.a.beat), 0, 1)
        dance.weight = math.clamp(math.min(elapsed / 0.18, (dance.endsAt - now) / 0.25), 0, 1)
        dance.sampledAt = now
    end
    local rotation = dance.a[pose.danceKey]:Lerp(dance.b[pose.danceKey], dance.alpha)
    -- Transform is expressed in the joint's bind frame. R6 shoulder/root C0
    -- axes differ from R15; conjugating prevents sideways or inverted limbs.
    return CFrame.identity:Lerp(pose.danceBasisInverse * rotation * pose.danceBasis, dance.weight)
end
local function finishPose(joint, pose)
    if poses[joint] ~= pose then return end
    poses[joint] = nil
    poseCount = poseCount - 1
    if pose.delay then task.cancel(pose.delay); pose.delay = nil end
    if pose.tween then pose.tween:Cancel(); pose.tween:Destroy(); pose.tween = nil end
    restorePoseTransform(joint, pose)
    local walk = locomotionFor(joint)
    if walk then walk.owner.Value = false end
    if pose.offset then pose.offset.Value = CFrame.new() end
    if poseCount == 0 then stopPoseFrames() end
end
local function validPose(joint, pose)
    return not stopped and joint.Parent and pose.character.Parent
        and pose.humanoid.Parent and pose.humanoid.Health > 0
        and (not pose.attachment0 or (joint.Attachment0 == pose.attachment0 and pose.attachment0.Parent))
end
local function connectPoseFrames()
    if poseAnimationConnection then return end
    -- Animator writes Transform between these events. Restoring first also handles
    -- throttled animation and rigs without evaluated tracks, without accumulating offsets.
    poseAnimationConnection = RunService.PreAnimation:Connect(function()
        for joint, pose in pairs(poses) do
            if validPose(joint, pose) then restorePoseTransform(joint, pose)
            else finishPose(joint, pose) end
        end
    end)
    poseSimulationConnection = RunService.PreSimulation:Connect(function()
        local danceNow
        for joint, pose in pairs(poses) do
            if validPose(joint, pose) then
                restorePoseTransform(joint, pose)
                -- AI used to animate C0 as C0Base * Walk, with FX in Transform.
                -- Walk * FX preserves that order, with one output owner and no accumulation.
                pose.appliedBase = locomotionBase(joint, pose)
                if pose.dance then
                    danceNow = danceNow or Workspace:GetServerTimeNow()
                    -- Run after Animator without stopping its tracks. The previous
                    -- evaluated pose is restored before its next animation step.
                    joint.Transform = danceOffset(pose, danceNow)
                else
                    joint.Transform = pose.locomotionApplied and pose.appliedBase * pose.offset.Value
                        or pose.offset.Value * pose.appliedBase
                end
                pose.appliedTransform = joint.Transform
            else finishPose(joint, pose) end
        end
    end)
end
local function registerLocomotion(object)
    local entry = object:IsA("Folder") and object or object.Parent
    if not entry or not entry:IsA("Folder") or locomotionEntries[entry] then return end
    local target, base, owner = entry:FindFirstChild("Joint"), entry:FindFirstChild("Base"), entry:FindFirstChild("CombatOwned")
    if not target or not target:IsA("ObjectValue") or not base or not base:IsA("CFrameValue")
        or not owner or not owner:IsA("BoolValue") then return end
    local joint = target.Value
    local character = joint and joint:FindFirstAncestorOfClass("Model")
    if not joint or not joint:IsA("Motor6D") or not character or character:GetAttribute("AIControlled") ~= true then return end
    locomotion[joint], locomotionEntries[entry] = {base = base, owner = owner, entry = entry}, joint
    local pose = poses[joint]
    if pose then claimLocomotion(joint, pose) end
end
local function unregisterLocomotion(object)
    local entry = locomotionEntries[object] and object or object.Parent
    local joint = entry and locomotionEntries[entry]
    if not joint then return end
    locomotionEntries[entry], locomotion[joint] = nil, nil
    local pose = poses[joint]
    if pose then restorePoseTransform(joint, pose)
    elseif joint.Parent then joint.Transform = CFrame.identity end
end
local function bindLocomotion()
    local presentation = script.Parent:WaitForChild("NPCPresentation", 10)
    local bridge = presentation and presentation:WaitForChild("AILocomotion", 10)
    if stopped or not bridge or not bridge:IsA("Folder") then return end
    track(bridge.DescendantAdded:Connect(registerLocomotion))
    track(bridge.DescendantRemoving:Connect(unregisterLocomotion))
    track(bridge.Destroying:Connect(function()
        for entry in pairs(locomotionEntries) do unregisterLocomotion(entry) end
    end))
    for _, object in ipairs(bridge:GetDescendants()) do registerLocomotion(object) end
end
local function clearSwordTrail(record, deferDestroy)
    local trail = record.trail
    if not trail then return end
    record.trail = nil
    trail.generation += 1
    if trail.disableTask then task.cancel(trail.disableTask); trail.disableTask = nil end
    trail.object.Enabled = false
    trail.object:Clear()
    local function destroy()
        trail.object:Destroy()
        trail.a:Destroy(); trail.b:Destroy()
    end
    -- DescendantRemoving runs before Roblox finishes changing ancestry.
    -- Invalidate the lease immediately; destroy after that event completes.
    if deferDestroy then task.defer(destroy) else destroy() end
end
local function clearRig(character)
    if clearVictoryDance then clearVictoryDance(character) end
    if clearBookGrip then clearBookGrip(character) end
    local record = rigs[character]
    if not record then forgetGroundCharacter(character); return end
    rigs[character] = nil
    disconnectAll(record.connections)
    clearSwordTrail(record)
    for _, connection in pairs(record.attachmentConnections) do connection:Disconnect() end
    table.clear(record.attachmentConnections)
    for _, joint in ipairs(record.joints) do
        local pose = poses[joint]
        if pose then finishPose(joint, pose) end
    end
    for _, offset in pairs(record.offsets) do offset:Destroy() end
    table.clear(record.offsets)
    forgetGroundCharacter(character)
end
local function isRigObject(object)
    return object:IsA("Motor6D") or object:IsA("AnimationConstraint")
        or (object:IsA("Attachment") and string.find(object.Name, "Shoulder", 1, true) ~= nil)
end
local function shoulders(character)
    local record = rigs[character]
    if not record then
        record = { joints = {}, offsets = {}, dirty = true, connections = {}, attachmentConnections = {} }
        rigs[character] = record
        local function watchAttachment0(object)
            if object:IsA("AnimationConstraint") and not record.attachmentConnections[object] then
                record.attachmentConnections[object] = object:GetPropertyChangedSignal("Attachment0"):Connect(function()
                    record.dirty = true
                    local pose = poses[object]
                    if pose then finishPose(object, pose) end
                end)
            end
        end
        record.watchAttachment0 = watchAttachment0
        table.insert(record.connections, character.DescendantAdded:Connect(function(object)
            watchAttachment0(object)
            if isRigObject(object) then record.dirty = true end
        end))
        table.insert(record.connections, character.DescendantRemoving:Connect(function(object)
            local trail = record.trail
            if trail and (object == trail.tool or object == trail.blade or object == trail.object
                or object == trail.a or object == trail.b) then clearSwordTrail(record, true) end
            local connection = record.attachmentConnections[object]
            if connection then connection:Disconnect(); record.attachmentConnections[object] = nil end
            if isRigObject(object) then record.dirty = true end
            local pose = poses[object]
            if pose then finishPose(object, pose) end
            local offset = record.offsets[object]
            if offset then offset:Destroy(); record.offsets[object] = nil end
            if object:IsA("Attachment") then
                for _, joint in ipairs(record.joints) do
                    local attachedPose = poses[joint]
                    if attachedPose and attachedPose.attachment0 == object then finishPose(joint, attachedPose) end
                end
            end
        end))
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then table.insert(record.connections, humanoid.Died:Connect(function() clearRig(character) end)) end
        table.insert(record.connections, character.Destroying:Connect(function() clearRig(character) end))
        table.insert(record.connections, character.AncestryChanged:Connect(function(_, parent)
            if parent == nil then clearRig(character) end
        end))
    end
    if record.dirty then
        table.clear(record.joints)
        for _, joint in ipairs(character:GetDescendants()) do
            record.watchAttachment0(joint)
            local name
            if joint:IsA("Motor6D") then name = joint.Name
            elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then name = joint.Attachment0.Name end
            if name then
                name = name:gsub(" ", "")
                if string.find(name, "RightShoulder", 1, true) or string.find(name, "LeftShoulder", 1, true)
                    or string.find(name, "Neck", 1, true) or string.find(name, "Hip", 1, true)
                    or string.find(name, "Elbow", 1, true) or string.find(name, "Wrist", 1, true)
                    or string.find(name, "Knee", 1, true) or name == "Waist" or name == "WaistRigAttachment"
                    or name == "WolfTail" or name == "Root" or name == "RootJoint" or name == "RootRigAttachment" then
                    table.insert(record.joints, joint)
                end
            end
        end
        record.dirty = false
    end
    return record.joints
end

clearBookGrip = function(character)
    local record = bookGrips[character]
    if not record then return end
    bookGrips[character] = nil
    if record.expiry then task.cancel(record.expiry) end
    disconnectAll(record.connections)
    for _, object in ipairs(record.objects) do object:Destroy() end
end
local function beginBookGrip(character)
    clearBookGrip(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    local book = character:FindFirstChild("Grimorio")
    if not humanoid or not root or not book then return false end
    local record = {objects = {}, connections = {}}
    for _, side in ipairs({"Right", "Left"}) do
        local arm, hand = character:FindFirstChild(side .. "UpperArm"), character:FindFirstChild(side .. "Hand")
        if not arm or not hand then
            for _, object in ipairs(record.objects) do object:Destroy() end
            return false -- R6 retains its procedural shoulder pose.
        end
        local target = Instance.new("Attachment")
        target.Name, target.Position, target.Parent = "Book" .. side .. "Target", Vector3.new(side == "Right" and 0.6 or -0.6, -0.6, -1.5), root
        table.insert(record.objects, target)
        local control = Instance.new("IKControl")
        control.Name, control.Type = "Book" .. side .. "Grip", Enum.IKControlType.Position
        control.ChainRoot, control.EndEffector, control.Target = arm, hand, target
        control.Weight, control.SmoothTime, control.Priority = 1, 0.08, 20
        control.Parent = humanoid
        table.insert(record.objects, control)
    end
    bookGrips[character] = record
    table.insert(record.connections, book.AncestryChanged:Connect(function() if book.Parent ~= character then clearBookGrip(character) end end))
    table.insert(record.connections, humanoid.Died:Connect(function() clearBookGrip(character) end))
    table.insert(record.connections, character.Destroying:Connect(function() clearBookGrip(character) end))
    record.expiry = task.delay(3, function() record.expiry = nil; clearBookGrip(character) end)
    return true
end

local function bodyPose(character, mode, duration)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    duration = math.clamp(duration or 0.4, 0.25, 5)
    for _, joint in ipairs(shoulders(character)) do
        local attachment0 = joint:IsA("AnimationConstraint") and joint.Attachment0 or nil
        local name = (attachment0 and attachment0.Name or joint.Name):gsub(" ", "")
        local right, left = name:find("Right", 1, true), name:find("Left", 1, true)
        local shoulder, neck, hip = name:find("Shoulder", 1, true), name:find("Neck", 1, true), name:find("Hip", 1, true)
        local root = name == "Root" or name == "RootJoint" or name == "RootRigAttachment"
        local tail = name == "WolfTail"
        local value
        if mode == "Book" and shoulder and not bookGrips[character] then value = CFrame.Angles(0.65, right and -0.5 or 0.5, right and -0.35 or 0.35)
        elseif mode == "Defend" and shoulder then value = CFrame.Angles(1.15, 0, right and -0.5 or 0.5)
        elseif mode == "Dodge" then
            if root then value = CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, 0.3)
            elseif shoulder then value = CFrame.Angles(0.25, 0, right and -0.35 or 0.35)
            elseif hip then value = CFrame.Angles(0.35, 0, 0) end
        elseif mode == "Lunge" then
            if shoulder then value = CFrame.Angles(1.6, 0, right and -0.2 or 0.2)
            elseif hip then value = CFrame.Angles(0.45, 0, 0)
            elseif root then value = CFrame.Angles(-0.22, 0, 0) end
        elseif mode == "Bite" and neck then value = CFrame.new(0, -0.06, -0.12) * CFrame.Angles(-0.42, 0, 0)
        elseif mode == "Transform" then
            if shoulder then value = CFrame.Angles(-0.65, 0, right and -0.75 or 0.75)
            elseif neck then value = CFrame.Angles(-0.2, 0, 0)
            elseif tail then value = CFrame.Angles(0, 0.4, 0) end
        elseif mode == "Tail" and tail then value = CFrame.Angles(0, 0.45, 0) end
        if value then
            local old = poses[joint]
            if old then finishPose(joint, old) end
            local record = rigs[character]
            local offset = record.offsets[joint]
            if not offset then offset = Instance.new("CFrameValue"); record.offsets[joint] = offset end
            offset.Value = CFrame.new()
            local pose = {offset = offset, character = character, humanoid = humanoid, attachment0 = attachment0}
            poses[joint], poseCount = pose, poseCount + 1
            claimLocomotion(joint, pose)
            connectPoseFrames()
            if mode == "Tail" then
                pose.tween = TweenService:Create(offset, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, math.max(0, math.floor(duration / 0.5) - 1), true), {Value = value})
            else
                pose.tween = TweenService:Create(offset, TweenInfo.new(0.1), {Value = value})
            end
            pose.tween:Play()
            pose.delay = task.delay(duration - 0.12, function()
                pose.delay = nil
                if poses[joint] ~= pose then return end
                if not validPose(joint, pose) then finishPose(joint, pose); return end
                pose.tween:Cancel(); pose.tween:Destroy()
                pose.tween = TweenService:Create(offset, TweenInfo.new(0.12), {Value = CFrame.new()})
                pose.tween:Play()
                pose.delay = task.delay(0.13, function() pose.delay = nil; finishPose(joint, pose) end)
            end)
        end
    end
end

clearVictoryDance = function(character)
    local dance = victoryDances[character]
    if not dance then return end
    victoryDances[character] = nil
    if dance.expiry then task.cancel(dance.expiry); dance.expiry = nil end
    for _, joint in ipairs(dance.joints) do
        local pose = poses[joint]
        if pose and pose.dance == dance then finishPose(joint, pose) end
    end
end

local function victoryDance(character, data)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 or state:GetAttribute("Phase") ~= "Resultado" then return end
    clearVictoryDance(character)
    local now = Workspace:GetServerTimeNow()
    -- The event receiver already validates and bounds these values. Keep the
    -- original deadline when a pending result starts late.
    local duration, startedAt = data.duration, data.startedAt
    local remaining = startedAt + duration - now
    if remaining <= 0 then return end
    local bpm = Config.Audio and tonumber(Config.Audio.VictoryBPM) or VICTORY_REFERENCE_BPM
    local dance = {startedAt = startedAt, endsAt = startedAt + duration, bpm = math.clamp(bpm, 60, 180), joints = {}}
    victoryDances[character] = dance
    for _, joint in ipairs(shoulders(character)) do
        local attachment0 = joint:IsA("AnimationConstraint") and joint.Attachment0 or nil
        local name = (attachment0 and attachment0.Name or joint.Name):gsub(" ", "")
        local kind = name:find("Shoulder", 1, true) and "Shoulder" or name:find("Elbow", 1, true) and "Elbow"
            or name:find("Wrist", 1, true) and "Wrist"
            or name:find("Hip", 1, true) and "Hip" or name:find("Knee", 1, true) and "Knee"
            or name:find("Neck", 1, true) and "Neck" or name:find("Waist", 1, true) and "Waist"
            or name == "WolfTail" and "Tail" or "Root"
        local old = poses[joint]
        if old then finishPose(joint, old) end
        local side = name:find("Right", 1, true) and "Right" or "Left"
        local sided = kind == "Shoulder" or kind == "Elbow" or kind == "Wrist" or kind == "Hip" or kind == "Knee"
        local pose = {
            character = character, humanoid = humanoid, attachment0 = attachment0, dance = dance,
            danceKey = sided and side .. kind or kind,
            danceBasis = attachment0 and attachment0.CFrame.Rotation or joint.C0.Rotation,
        }
        if kind == "Shoulder" and humanoid.RigType == Enum.HumanoidRigType.R6 then pose.danceKey ..= "R6" end
        pose.danceBasisInverse = pose.danceBasis:Inverse()
        poses[joint], poseCount = pose, poseCount + 1
        table.insert(dance.joints, joint)
        claimLocomotion(joint, pose)
    end
    if #dance.joints == 0 then victoryDances[character] = nil; return end
    connectPoseFrames()
    -- One finite expiry for the whole rig; no permanent dance polling or tweens.
    dance.expiry = task.delay(remaining, function()
        dance.expiry = nil
        if victoryDances[character] == dance then clearVictoryDance(character) end
    end)
end

local function swing(character, wolf)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    for _, joint in ipairs(shoulders(character)) do
        local name, attachment0
        if joint:IsA("Motor6D") then name = joint.Name
        elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
            attachment0, name = joint.Attachment0, joint.Attachment0.Name
        end
        local right = name and string.find(name:gsub(" ", ""), "RightShoulder", 1, true)
        local left = name and string.find(name:gsub(" ", ""), "LeftShoulder", 1, true)
        if joint.Parent and (right or (wolf and left)) then
            local old = poses[joint]
            if old then finishPose(joint, old) end
            local record = rigs[character]
            local offset = record.offsets[joint]
            if not offset then
                offset = Instance.new("CFrameValue")
                record.offsets[joint] = offset
            end
            offset.Value = CFrame.new()
            local pose = { offset = offset, character = character, humanoid = humanoid, attachment0 = attachment0 }
            poses[joint] = pose
            poseCount = poseCount + 1
            claimLocomotion(joint, pose)
            connectPoseFrames()
            local function tween(value, seconds)
                if pose.tween then pose.tween:Cancel(); pose.tween:Destroy() end
                pose.tween = TweenService:Create(offset, TweenInfo.new(seconds), { Value = value })
                pose.tween:Play()
            end
            local function valid()
                if stopped or poses[joint] ~= pose then return false end
                if not validPose(joint, pose) then finishPose(joint, pose); return false end
                return true
            end
            local function after(seconds, callback)
                pose.delay = task.delay(seconds, function()
                    pose.delay = nil
                    if valid() then callback() end
                end)
            end
            tween(CFrame.Angles(-1.05, 0, -0.4), 0.08)
            after(0.08, function()
                tween(CFrame.Angles(0.7, 0, 0.5), 0.15)
                after(0.15, function()
                    tween(CFrame.new(), 0.18)
                    after(0.19, function() finishPose(joint, pose) end)
                end)
            end)
        end
    end
    local tool = character:FindFirstChild("EspadaPlata")
    local blade = tool and tool:FindFirstChild("Blade")
    local record = rigs[character]
    if not record then return end
    if record.trail and (record.trail.tool ~= tool or record.trail.blade ~= blade) then clearSwordTrail(record) end
    if blade and blade:IsA("BasePart") then
        local cached = record.trail
        if not cached then
            local a, b = Instance.new("Attachment"), Instance.new("Attachment")
            a.Name, b.Name = "HLSwordTrailA", "HLSwordTrailB"
            a.Position, b.Position = Vector3.new(0, -1.3, 0), Vector3.new(0, 1.3, 0)
            a.Parent, b.Parent = blade, blade
            local trail = Instance.new("Trail")
            trail.Name, trail.Enabled = "HLSwordTrail", false
            trail.Attachment0, trail.Attachment1 = a, b
            trail.Color = ColorSequence.new(Color3.fromRGB(214, 236, 255))
            trail.Lifetime, trail.FaceCamera, trail.LightEmission = 0.16, true, 0.8
            trail.Parent = blade
            cached = {object = trail, a = a, b = b, tool = tool, blade = blade, generation = 0}
            record.trail = cached
        end
        -- The server's melee cooldown exceeds this lease. Retain the same three
        -- objects between swings, without allowing an old expiry to end a new one.
        cached.generation += 1
        local generation = cached.generation
        if cached.disableTask then task.cancel(cached.disableTask) end
        cached.object:Clear()
        cached.object.Enabled = true
        cached.disableTask = task.delay(0.55, function()
            if record.trail ~= cached or cached.generation ~= generation then return end
            cached.disableTask = nil
            cached.object.Enabled = false
            cached.object:Clear()
        end)
    end
end

-- Cache each of the three local detail levels. Their radii still describe the
-- same server-owned attack range; minimum detail keeps essential feedback.
local effectsScale = ExperienceSettings.effectsScale()
local function segmentCount(scale) return scale >= 1 and 32 or (scale > 0 and 16 or 8) end
local detailSegments = segmentCount(effectsScale)
local geometryCache, arc = {}, {}
local function geometry(a, b)
    local frame = CFrame.lookAt((a + b) / 2, b)
    return { position = frame.Position, rotation = frame.Rotation, length = (b - a).Magnitude }
end
local function detailGeometry(segments)
    local cached = geometryCache[segments]
    if cached then return cached end
    cached = {circle = {}, ground = {}, xy = {}, yz = {}}
    for i = 1, segments do
        local angle = (i - 1) * math.pi * 2 / segments
        cached.circle[i] = Vector3.new(math.cos(angle), 0, math.sin(angle))
    end
    for i = 1, segments do
        local a, b = cached.circle[i], cached.circle[i % segments + 1]
        cached.ground[i] = geometry(a, b)
        cached.xy[i] = geometry(Vector3.new(a.X, a.Z, 0), Vector3.new(b.X, b.Z, 0))
        cached.yz[i] = geometry(Vector3.new(0, a.Z, a.X), Vector3.new(0, b.Z, b.X))
    end
    geometryCache[segments] = cached
    return cached
end
for i = 1, 17 do
    local angle = -1.05 + (i - 1) * 2.1 / 16
    arc[i] = Vector3.new(math.sin(angle) * 0.68, 0, -math.cos(angle) * 0.68)
end
local function tooFar(player, center, range)
    if player == localPlayer then return false end
    local camera = Workspace.CurrentCamera
    if not camera or not ownRoot or not ownRoot.Parent then return false end
    local limit = (FAR_DISTANCE + range) ^ 2
    local cameraDelta, playerDelta = center - camera.CFrame.Position, center - ownRoot.Position
    return cameraDelta:Dot(cameraDelta) > limit and playerDelta:Dot(playerDelta) > limit
end
local function actorCharacter(actor)
    if typeof(actor) ~= "Instance" then return nil end
    if actor:IsA("Player") then return actor.Character end
    if actor:IsA("Model") and actor:GetAttribute("AIControlled") == true and actor:IsDescendantOf(Workspace) then return actor end
end
local function clearPendingVictory()
    local pending = pendingVictory
    if not pending then return end
    pendingVictory = nil
    if pending.expiry then task.cancel(pending.expiry); pending.expiry = nil end
end
local function playVictory(data)
    for index, actor in ipairs(typeof(data.players) == "table" and data.players or {}) do
        local character = actorCharacter(actor)
        local expected = typeof(data.characters) == "table" and data.characters[index]
        local root = character and character:FindFirstChild("HumanoidRootPart")
        -- Results can arrive before the asynchronous lobby teleport. The short
        -- celebration follows an already replicated winner into the lobby.
        if root and (not expected or character == expected) then victoryDance(character, data) end
    end
end
local function receiveVictory(data)
    local now = Workspace:GetServerTimeNow()
    local duration, receivedAt = data.duration, data.startedAt
    if typeof(duration) ~= "number" or duration ~= duration or duration <= 0 or duration > 5
        or typeof(receivedAt) ~= "number" or receivedAt ~= receivedAt or math.abs(receivedAt) == math.huge
        or receivedAt > now + 1 or receivedAt + duration <= now
        or (lastVictoryStartedAt and receivedAt <= lastVictoryStartedAt) then return end
    local phase = state:GetAttribute("Phase")
    if phase ~= "Resultado" and phase ~= "Día" and phase ~= "Noche" then return end
    lastVictoryStartedAt = receivedAt
    clearPendingVictory()
    local payload = {
        players = data.players, characters = data.characters,
        duration = duration, startedAt = math.min(receivedAt, now),
    }
    if phase == "Resultado" then playVictory(payload); return end
    -- Attributes and RemoteEvents may replicate in either order. Retain only
    -- this result until Phase catches up, bounded by its original five seconds.
    local pending = {data = payload}
    pendingVictory = pending
    pending.expiry = task.delay(payload.startedAt + duration - now, function()
        pending.expiry = nil
        if pendingVictory == pending then pendingVictory = nil end
    end)
end
attackConnection = feedback.OnClientEvent:Connect(function(kind, data)
    if stopped or typeof(data) ~= "table" then return end
    if kind == "VictoryFX" then
        receiveVictory(data)
        return
    end
    local current = actorCharacter(data.player)
    if not current then return end
    local character = data.character or current
    if character ~= current then return end
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local range = typeof(data.range) == "number" and math.clamp(data.range, 1, 30) or Config.Combat.Range
    local center = root.Position
    if tooFar(data.player, center, range) then return end
    if kind == "TransformFX" then bodyPose(character, "Transform", data.duration); return
    elseif kind == "LungeFX" then bodyPose(character, "Lunge", 0.55); return
    elseif kind == "DefendFX" then bodyPose(character, "Defend", Config.Combat.DefendWindow or 0.35); return
    elseif kind == "DodgeFX" then bodyPose(character, "Dodge", 0.3); return
    elseif kind == "BookFX" then beginBookGrip(character); bodyPose(character, "Book", 3); return
    elseif kind == "GunFX" then
        if typeof(data.origin) == "Vector3" and typeof(data.position) == "Vector3" then fade("arc", data.origin, data.position, Color3.fromRGB(255, 221, 151), 0.045) end
        return
    elseif kind ~= "AttackFX" then return end
    local color = data.wolf and wolfColor or bladeColor
    swing(character, data.wolf)
    if data.wolf then bodyPose(character, "Bite", 0.3); bodyPose(character, "Tail", 0.5) end
    local y = ground(center, character)
    local radius = math.sqrt(math.max(0, range * range - (center.Y - y) ^ 2))
    local circle = detailGeometry(detailSegments).circle
    -- When the sphere does not intersect the ground, there is no horizontal circle to draw.
    if radius > 0.001 then
        for i = 1, detailSegments do
            local a, b = circle[i], circle[i % detailSegments + 1]
            fade("ring", Vector3.new(center.X + a.X * radius, y, center.Z + a.Z * radius),
                Vector3.new(center.X + b.X * radius, y, center.Z + b.Z * radius), color, 0.075)
        end
    end
    local frame = root.CFrame
    local arcStep = 32 / detailSegments
    for claw = 1, (data.wolf and 3 or 1) do
        local offset = Vector3.new(0, (claw - 2) * 0.3, 0)
        for i = 1, 16, arcStep do
            fade("arc", frame:PointToWorldSpace(arc[i] * range + offset),
                frame:PointToWorldSpace(arc[i + arcStep] * range + offset), color, data.wolf and 0.11 or 0.08)
        end
    end
    for _ = 1, math.floor(6 * effectsScale + 0.5) do
        local start = center + frame.LookVector * 4 + Vector3.new(0, random:NextNumber(-0.4, 0.7), 0)
        local destination = start + Vector3.new(random:NextNumber(-3, 3), random:NextNumber(0.5, 2), random:NextNumber(-3, 3))
        spark(start, start + Vector3.new(0, 0.22, 0), destination, color)
    end
end)

local preview, frames, verticalFrames = {}, {}, {}
local lastCenter, lastGround, lastRadius, lastRange
local accumulator, groundElapsed, sampledGround = 0, 0, nil
local function clearPreview()
    for _, part in ipairs(preview) do part:Destroy() end
    table.clear(preview); table.clear(frames); table.clear(verticalFrames)
    lastCenter, lastGround, lastRadius, lastRange, sampledGround = nil, nil, nil, nil, nil
end
local function preparePreview(range)
    local newRange = lastRange ~= range
    for i = 1, detailSegments * 3 do
        if not preview[i] then
            local part = newPart("Alcance")
            part.Color, part.Transparency = previewColor, 0.4
            preview[i] = part
        end
    end
    if newRange then
        local detail = detailGeometry(detailSegments)
        for i = 1, detailSegments do
            local xy, yz = detail.xy[i], detail.yz[i]
            verticalFrames[i] = CFrame.new(xy.position * range) * xy.rotation
            verticalFrames[detailSegments + i] = CFrame.new(yz.position * range) * yz.rotation
            preview[detailSegments + i].Size = Vector3.new(0.055, 0.055, xy.length * range)
            preview[detailSegments * 2 + i].Size = Vector3.new(0.055, 0.055, yz.length * range)
        end
        lastRange, lastRadius = range, nil
    end
end
local function updatePreview(center, y, range)
    preparePreview(range)
    local detail = detailGeometry(detailSegments)
    local radius = math.sqrt(math.max(0, range * range - (center.Y - y) ^ 2))
    if radius ~= lastRadius then
        for i = 1, detailSegments do
            preview[i].Size = Vector3.new(0.055, 0.055, math.max(detail.ground[i].length * radius, 0.01))
            preview[i].Transparency = radius > 0.001 and 0.4 or 1
        end
        lastRadius = radius
    end
    local centerFrame = CFrame.new(center)
    for i = 1, detailSegments do
        local g = detail.ground[i]
        frames[i] = CFrame.new(center.X + g.position.X * radius, y, center.Z + g.position.Z * radius) * g.rotation
        frames[detailSegments + i] = centerFrame * verticalFrames[i]
        frames[detailSegments * 2 + i] = centerFrame * verticalFrames[detailSegments + i]
    end
    for _, part in ipairs(preview) do if not part.Parent then part.Parent = folder end end
    Workspace:BulkMoveTo(preview, frames, Enum.BulkMoveMode.FireCFrameChanged)
    lastCenter, lastGround = center, y
end
local syncPreview
local function onPreviewFrame(delta)
    accumulator, groundElapsed = accumulator + delta, groundElapsed + delta
    if accumulator < PREVIEW_INTERVAL then return end
    accumulator = accumulator % PREVIEW_INTERVAL
    if stopped or not screen.Parent or not ownRoot or not ownRoot.Parent or not ownHumanoid or ownHumanoid.Health <= 0
        or not localPlayer:GetAttribute("Alive") or not screen:GetAttribute("ShowAttackRange") then
        syncPreview(); return
    end
    local center, range = ownRoot.Position, Config.Combat.Range
    local moved = lastCenter == nil
    if lastCenter then local offset = center - lastCenter; moved = offset:Dot(offset) > MOVE_EPSILON_SQUARED end
    if moved or sampledGround == nil or groundElapsed >= GROUND_INTERVAL then
        sampledGround, groundElapsed = ground(center, ownCharacter), 0
    end
    if moved or sampledGround ~= lastGround or range ~= lastRange then updatePreview(center, sampledGround, range) end
end
syncPreview = function()
    if stopped then return end
    local allowed = screen.Parent and screen:GetAttribute("ShowAttackRange") and localPlayer:GetAttribute("Alive")
        and ownRoot and ownRoot.Parent and ownHumanoid and ownHumanoid.Health > 0
    if not allowed then
        if previewConnection then previewConnection:Disconnect(); previewConnection = nil end
        clearPreview()
    elseif not previewConnection then
        accumulator, groundElapsed = PREVIEW_INTERVAL, GROUND_INTERVAL
        previewConnection = RunService.RenderStepped:Connect(onPreviewFrame)
    end
end
local function refreshOwnCharacter()
    local humanoid = ownCharacter and ownCharacter:FindFirstChildOfClass("Humanoid")
    ownRoot = ownCharacter and ownCharacter:FindFirstChild("HumanoidRootPart")
    if humanoid ~= ownHumanoid then
        if healthConnection then healthConnection:Disconnect(); healthConnection = nil end
        ownHumanoid = humanoid
        if humanoid then healthConnection = humanoid.HealthChanged:Connect(syncPreview) end
    end
    syncPreview()
end
local function bindOwnCharacter(character)
    disconnectAll(ownConnections)
    if healthConnection then healthConnection:Disconnect(); healthConnection = nil end
    ownCharacter, ownRoot, ownHumanoid = character, nil, nil
    if character then
        table.insert(ownConnections, character.DescendantAdded:Connect(function(object)
            if object.Parent == character and (object.Name == "HumanoidRootPart" or object:IsA("Humanoid")) then
                refreshOwnCharacter()
            end
        end))
        table.insert(ownConnections, character.DescendantRemoving:Connect(function(object)
            if object == ownRoot or object == ownHumanoid then
                if object == ownRoot then ownRoot = nil end
                if object == ownHumanoid then
                    ownHumanoid = nil
                    if healthConnection then healthConnection:Disconnect(); healthConnection = nil end
                end
                syncPreview()
                task.defer(function() if not stopped and ownCharacter == character then refreshOwnCharacter() end end)
            end
        end))
    end
    refreshOwnCharacter()
end
local function cleanup()
    if stopped then return end
    stopped = true
    clearPendingVictory()
    if previewConnection then previewConnection:Disconnect(); previewConnection = nil end
    if attackConnection then attackConnection:Disconnect(); attackConnection = nil end
    disconnectAll(connections); disconnectAll(ownConnections)
    if healthConnection then healthConnection:Disconnect(); healthConnection = nil end
    for character in pairs(rigs) do clearRig(character) end
    for character in pairs(bookGrips) do clearBookGrip(character) end
    for joint, pose in pairs(poses) do finishPose(joint, pose) end
    stopPoseFrames()
    table.clear(poses)
    table.clear(locomotion); table.clear(locomotionEntries)
    clearPreview()
    for entry in pairs(entries) do
        entry.active = false
        if entry.releaseTask then task.cancel(entry.releaseTask); entry.releaseTask = nil end
        if entry.completed then entry.completed:Disconnect(); entry.completed = nil end
        if entry.tween then entry.tween:Cancel(); entry.tween:Destroy(); entry.tween = nil end
        entry.part:Destroy()
    end
    table.clear(entries); table.clear(free.ring); table.clear(free.arc); table.clear(free.spark)
    retained = 0
    groundCharacter, ownCharacter, ownRoot, ownHumanoid = nil, nil, nil, nil
    groundParams.FilterDescendantsInstances = {}
    folder:Destroy()
end
track(localPlayer.CharacterAdded:Connect(bindOwnCharacter))
track(state:GetAttributeChangedSignal("Phase"):Connect(function()
    local phase = state:GetAttribute("Phase")
    if phase == "Resultado" then
        local pending = pendingVictory
        if pending then
            clearPendingVictory()
            playVictory(pending.data)
        end
    else
        for character in pairs(victoryDances) do clearVictoryDance(character) end
        if phase ~= "Día" and phase ~= "Noche" then clearPendingVictory() end
    end
end))
track(localPlayer.CharacterRemoving:Connect(function(character)
    clearRig(character)
    if ownCharacter == character then bindOwnCharacter(nil) end
end))
track(Players.PlayerRemoving:Connect(function(player) if player.Character then clearRig(player.Character) end end))
track(localPlayer:GetAttributeChangedSignal("Alive"):Connect(syncPreview))
track(screen:GetAttributeChangedSignal("ShowAttackRange"):Connect(syncPreview))
track(ExperienceSettings.changed:Connect(function()
    local nextScale = ExperienceSettings.effectsScale()
    if stopped or nextScale == effectsScale then return end
    effectsScale, detailSegments = nextScale, segmentCount(nextScale)
    clearPreview()
    syncPreview()
end))
track(screen.Destroying:Connect(cleanup))
track(script.Destroying:Connect(cleanup))
bindLocomotion()
bindOwnCharacter(localPlayer.Character)
