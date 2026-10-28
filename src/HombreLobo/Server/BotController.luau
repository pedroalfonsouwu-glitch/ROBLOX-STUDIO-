-- One original, server-controlled actor fills the second seat in an opted-in AI round.
-- Roles, rewards and accepted game actions remain in Main / PlayerState.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("HombreLobo"):WaitForChild("Config"))

local BotController = {}
local function bounded(value, fallback, minimum, maximum)
    if typeof(value) ~= "number" or value ~= value then value = fallback end
    return math.clamp(value, minimum, maximum)
end
local settings = Config.AI or {}
local THINK_INTERVAL = bounded(settings.ThinkInterval, 0.25, 0.2, 1)
local SELECT_INTERVAL = bounded(settings.TargetInterval, 1, 1, 5)
local PATH_INTERVAL = bounded(settings.PathInterval, 2, 2, 10)
local MAX_WAYPOINTS = math.floor(bounded(settings.MaxWaypoints, 48, 8, 48))
local INTERACT_DISTANCE, MELEE_DISTANCE = 12, 8.5
local controllers = setmetatable({}, { __mode = "k" })
local V, C = Vector3.new, CFrame.new

local function bodyPart(model, name, size, position, color, collide)
    local part = Instance.new("Part")
    part.Name, part.Size, part.CFrame = name, size, C(position)
    part.Color, part.Material = color, Enum.Material.SmoothPlastic
    part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    part.CanCollide, part.CanTouch, part.CanQuery = collide, false, true
    part.Massless = not collide
    part.Parent = model
    return part
end

local function motor(name, parent, first, second, c0, c1)
    local joint = Instance.new("Motor6D")
    joint.Name, joint.Part0, joint.Part1 = name, first, second
    joint.C0, joint.C1, joint.Parent = c0, c1, parent
    return joint
end

function BotController.create(spawnPosition)
    assert(typeof(spawnPosition) == "Vector3", "AI spawn must be a Vector3")
    local folder = Workspace:FindFirstChild("HombreLoboBots")
    if not folder then folder = Instance.new("Folder"); folder.Name, folder.Parent = "HombreLoboBots", Workspace end
    assert(folder:IsA("Folder"), "Unexpected AI actor container")
    assert(not folder:FindFirstChild("LunaIA"), "Only one replacement actor can be active")
    local character = Instance.new("Model")
    character.Name, character.ModelStreamingMode = "LunaIA", Enum.ModelStreamingMode.Atomic
    character:SetAttribute("AIControlled", true)
    character:SetAttribute("AILocomotionActive", false)
    local skin, shirt, trousers = Color3.fromRGB(196, 158, 129), Color3.fromRGB(57, 100, 104), Color3.fromRGB(53, 65, 80)
    local root = bodyPart(character, "HumanoidRootPart", V(2, 2, 1), spawnPosition, shirt, false)
    root.Transparency, root.Massless = 1, false
    local torso = bodyPart(character, "Torso", V(2, 2, 1), spawnPosition, shirt, true)
    local head = bodyPart(character, "Head", V(2, 1, 1), spawnPosition + V(0, 1.5, 0), skin, true)
    local rightArm = bodyPart(character, "Right Arm", V(1, 2, 1), spawnPosition + V(1.5, 0, 0), skin, false)
    local leftArm = bodyPart(character, "Left Arm", V(1, 2, 1), spawnPosition + V(-1.5, 0, 0), skin, false)
    local rightLeg = bodyPart(character, "Right Leg", V(1, 2, 1), spawnPosition + V(0.5, -2, 0), trousers, false)
    local leftLeg = bodyPart(character, "Left Leg", V(1, 2, 1), spawnPosition + V(-0.5, -2, 0), trousers, false)
    local r6Axis = CFrame.Angles(-math.pi / 2, 0, math.pi)
    motor("RootJoint", root, root, torso, r6Axis, r6Axis)
    motor("Neck", torso, torso, head, C(0, 1, 0) * r6Axis, C(0, -0.5, 0) * r6Axis)
    local joints = {
        motor("Right Shoulder", torso, torso, rightArm, C(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0), C(-0.5, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0)),
        motor("Left Shoulder", torso, torso, leftArm, C(-1, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0), C(0.5, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0)),
        motor("Right Hip", torso, torso, rightLeg, C(1, -1, 0) * CFrame.Angles(0, math.pi / 2, 0), C(0.5, 1, 0) * CFrame.Angles(0, math.pi / 2, 0)),
        motor("Left Hip", torso, torso, leftLeg, C(-1, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0), C(-0.5, 1, 0) * CFrame.Angles(0, -math.pi / 2, 0)),
    }
    local bases = {}
    for index, joint in ipairs(joints) do bases[index] = joint.C0 end
    for _, side in ipairs({ -1, 1 }) do
        local eye = bodyPart(character, "Ojo", V(0.12, 0.16, 0.06), head.Position + V(side * 0.32, 0.03, -0.51), Color3.fromRGB(29, 28, 30), false)
        eye.CanQuery, eye.CastShadow = false, false
        local weld = Instance.new("WeldConstraint")
        weld.Part0, weld.Part1, weld.Parent = head, eye, eye
    end
    local hair = bodyPart(character, "Cabello", V(2.04, 0.3, 1.05), head.Position + V(0, 0.43, 0.01), Color3.fromRGB(60, 47, 42), false)
    hair.CanQuery = false
    local hairWeld = Instance.new("WeldConstraint")
    hairWeld.Part0, hairWeld.Part1, hairWeld.Parent = head, hair, hair
    local grip = Instance.new("Attachment")
    grip.Name, grip.Position, grip.Parent = "RightGripAttachment", V(0, -1, 0), rightArm
    local hum = Instance.new("Humanoid")
    hum.DisplayName, hum.WalkSpeed, hum.MaxHealth, hum.Health = "Luna (IA)", 16, 100, 100
    hum.UseJumpPower, hum.JumpHeight, hum.HipHeight = false, 7.2, 0
    hum.BreakJointsOnDeath, hum.RequiresNeck = false, true
    hum.NameDisplayDistance, hum.HealthDisplayDistance = 70, 40
    hum.Parent = character
    local animator = Instance.new("Animator")
    animator.Parent = hum
    local backpack = Instance.new("Backpack")
    backpack.Name, backpack.Parent = "Backpack", character
    character.PrimaryPart, character.Parent = root, folder
    CollectionService:AddTag(character, "HombreLoboAI")
    pcall(function() root:SetNetworkOwner(nil) end)
    local added, removing = Instance.new("BindableEvent"), Instance.new("BindableEvent")
    local actor = {
        Name = "Luna (IA)", DisplayName = "Luna (IA)", UserId = -1, IsBot = true,
        Parent = Players, Character = character, Backpack = backpack,
        CharacterAdded = added.Event, CharacterRemoving = removing.Event,
        _walkJoints = joints, _walkBases = bases,
    }
    function actor:SetAttribute(key, value) if self.Character then self.Character:SetAttribute(key, value) end end
    function actor:GetAttribute(key) return self.Character and self.Character:GetAttribute(key) end
    function actor:GetAttributes() return self.Character and self.Character:GetAttributes() or {} end
    function actor:GetAttributeChangedSignal(key) return character:GetAttributeChangedSignal(key) end
    function actor:FindFirstChildOfClass(className)
        if className == "Backpack" and backpack.Parent then return backpack end
        return character:FindFirstChildOfClass(className)
    end
    function actor:FindFirstChild(name) return character:FindFirstChild(name) end
    function actor:RequestStreamAroundAsync() end -- The server already owns the complete map.
    function actor:LoadCharacterAsync() return self.Character end
    function actor:Destroy()
        if self.Parent == nil then return end
        local controller = controllers[self]
        if controller then controller:destroy() end
        removing:Fire(character)
        self.Parent, self.Character = nil, nil
        character:Destroy()
        added:Destroy(); removing:Destroy()
        table.clear(self._walkJoints); table.clear(self._walkBases)
        if folder.Parent and #folder:GetChildren() == 0 then folder:Destroy() end
    end
    return actor
end

function BotController.start(actor, context)
    assert(actor.IsBot and actor.Parent == Players and actor.Character, "AI actor is not active")
    assert(not controllers[actor], "AI actor already has a controller")
    for _, key in ipairs({ "eligible", "getRole", "isNight", "getWorld", "getHumanActors", "attack", "defend", "lunge", "lootChest", "purifyStatue" }) do
        assert(typeof(context[key]) == "function", "Missing AI callback: " .. key)
    end
    local character = actor.Character
    local hum, root = character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
    assert(hum and root, "AI character requires a Humanoid and root")
    local controller = {}
    controllers[actor] = controller
    local destroyed, heartbeat, died, healthChanged, destroying, blocked = false, nil, nil, nil, nil, nil
    local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 6, Costs = { Water = 20 } })
    local generation, pathTask, pathBusy, pathReady, waypoints, waypointIndex = 0, nil, false, false, {}, 1
    local target, kind, goal, targetHuman, heldTarget
    local selectAt, pathAt, attackAt, defendAt, lungeAt = 0, 0, 0, 0, 0
    local thoughtTime, reactionTime = 0, 0
    local lastHealth, retaliateUntil = hum.Health, 0
    local stuckPosition, stuckAt = root.Position, os.clock()
    local failures, avoided = {}, {}
    local diagnostics = { thinks = 0, selections = 0, pathRequests = 0, pathFailures = 0, pathsDiscarded = 0,
        holdAttempts = 0, holdCalls = 0, looted = 0, purified = 0, attacks = 0, defenses = 0, lunges = 0,
        currentTask = "Idle", lastTarget = "", maxWaypoints = MAX_WAYPOINTS, thinkInterval = THINK_INTERVAL, pathInterval = PATH_INTERVAL }
    local rayParams = RaycastParams.new()
    rayParams.FilterType, rayParams.FilterDescendantsInstances, rayParams.RespectCanCollide = Enum.RaycastFilterType.Exclude, { character }, true

    local function cancelHold()
        if heldTarget and context.cancelHold then context.cancelHold(actor) end
        heldTarget = nil
    end
    local function clearNavigation()
        generation += 1
        table.clear(waypoints)
        waypointIndex, pathReady = 1, false
    end
    local function setTarget(nextTarget, nextKind, nextGoal, human)
        if nextTarget ~= target or nextKind ~= kind then
            cancelHold()
            clearNavigation()
            stuckPosition, stuckAt = root.Position, os.clock()
        elseif goal and nextGoal and (goal - nextGoal).Magnitude > 7 then
            clearNavigation()
        end
        target, kind, goal, targetHuman = nextTarget, nextKind, nextGoal, human
        diagnostics.currentTask, diagnostics.lastTarget = nextKind or "Idle", nextTarget and nextTarget.Name or ""
    end
    local function actorRoot(other)
        local model = other.Character
        local otherHum = model and model:FindFirstChildOfClass("Humanoid")
        local otherRoot = model and model:FindFirstChild("HumanoidRootPart")
        if otherRoot and otherHum and otherHum.Health > 0 and context.eligible(other) then return otherRoot end
    end
    local function visible(position, model)
        local delta = position - root.Position
        local hit = delta.Magnitude > 0.01 and Workspace:Raycast(root.Position, delta, rayParams) or nil
        return not hit or (model and hit.Instance:IsDescendantOf(model))
    end
    local function approach(object, world)
        -- The central entrance is inside the usable floor, clear of the side table,
        -- and within the ordinary interaction distance of either objective.
        for _, site in ipairs(world.sites or {}) do
            if site.name == object:GetAttribute("SiteName") and site.frame then
                return site.frame:PointToWorldSpace(V(0, (site.elevation or 0) + 4, -7))
            end
        end
        local position = object.PrimaryPart.Position
        local direction = V(root.Position.X - position.X, 0, root.Position.Z - position.Z)
        direction = direction.Magnitude > 0.1 and direction.Unit or V(0, 0, 1)
        local point = position + direction * 8
        local params = RaycastParams.new()
        params.FilterType, params.FilterDescendantsInstances, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, { character, object }, true
        local floor = Workspace:Raycast(point + V(0, 4, 0), V(0, -10, 0), params)
        if floor then return V(point.X, floor.Position.Y + 3, point.Z) end
        return V(point.X, position.Y + 2, point.Z)
    end
    local function nearestObject(objects, consumed, now)
        local selected, best = nil, math.huge
        for _, object in ipairs(objects or {}) do
            if object.Parent and object.PrimaryPart and not object:GetAttribute(consumed) and (avoided[object] or 0) <= now then
                local distance = (root.Position - object.PrimaryPart.Position).Magnitude
                if object == target then distance *= 0.85 end
                if distance < best then selected, best = object, distance end
            end
        end
        return selected
    end
    local function chooseTarget(now)
        diagnostics.selections += 1
        local ownWolf = context.getRole(actor) == "HombreLobo"
        local wolfForm = ownWolf and context.isNight() and character:GetAttribute("Transformed") == true
        local opponent, opponentRoot, nearest = nil, nil, math.huge
        local companion, companionRoot, companionDistance = nil, nil, math.huge
        for _, other in ipairs(context.getHumanActors()) do
            if other ~= actor then
                local otherRoot = actorRoot(other)
                if otherRoot then
                    local distance = (root.Position - otherRoot.Position).Magnitude
                    if distance < companionDistance then companion, companionRoot, companionDistance = other, otherRoot, distance end
                    local hostile = wolfForm or (not ownWolf and other.Character:GetAttribute("Transformed") == true)
                        or (now < retaliateUntil and distance < 24)
                    if hostile and distance < nearest then opponent, opponentRoot, nearest = other, otherRoot, distance end
                end
            end
        end
        if opponent and (wolfForm or nearest < 48 or now < retaliateUntil) then
            setTarget(opponent.Character, "Combat", opponentRoot.Position, opponent)
            return
        end
        local world = context.getWorld()
        local chests = 0
        if context.getChestsOpened then chests = context.getChestsOpened(actor) end
        -- The two accepted chest completions are counted locally if Main does not provide a snapshot callback.
        chests = math.max(chests or 0, diagnostics.looted)
        if world and chests < 2 then
            local chest = nearestObject(world.chests, "Looted", now)
            if chest then setTarget(chest, "Chest", approach(chest, world)); return end
        end
        if world and not ownWolf then
            local statue = nearestObject(world.statues, "Destroyed", now)
            if statue then setTarget(statue, "Statue", approach(statue, world)); return end
        end
        if companion and companionDistance > 15 then
            local delta = root.Position - companionRoot.Position
            local horizontal = V(delta.X, 0, delta.Z)
            local offset = horizontal.Magnitude > 0.1 and horizontal.Unit * 14 or V(14, 0, 0)
            setTarget(companion.Character, "Follow", companionRoot.Position + offset, companion)
        else setTarget(nil, nil, nil) end
    end
    local function requestPath(now)
        if pathBusy or not goal or now < pathAt or hum.FloorMaterial == Enum.Material.Air then return end
        pathBusy, pathAt = true, now + PATH_INTERVAL
        diagnostics.pathRequests += 1
        local token, destination, destinationTarget = generation, goal, target
        pathTask = task.defer(function()
            local ok = pcall(function() path:ComputeAsync(root.Position, destination) end)
            pathTask, pathBusy = nil, false
            if destroyed then return end
            if generation ~= token then diagnostics.pathsDiscarded += 1; return end
            table.clear(waypoints)
            waypointIndex, pathReady = 1, false
            if ok and path.Status == Enum.PathStatus.Success then
                local calculated = path:GetWaypoints()
                for index = 1, math.min(#calculated, MAX_WAYPOINTS) do waypoints[index] = calculated[index] end
                pathReady = #waypoints > 0
                failures[destinationTarget] = nil
            else
                diagnostics.pathFailures += 1
                local count = (failures[destinationTarget] or 0) + 1
                failures[destinationTarget] = count
                if count >= 3 then
                    avoided[destinationTarget], failures[destinationTarget], selectAt = os.clock() + 8, nil, 0
                    if kind ~= "Combat" then setTarget(nil, nil, nil) end
                end
            end
        end)
    end
    local routeOverlap = OverlapParams.new()
    routeOverlap.FilterType, routeOverlap.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
    routeOverlap.RespectCanCollide, routeOverlap.MaxParts = true, 1
    local function standingHeight()
        local leg = character:FindFirstChild("Left Leg") or character:FindFirstChild("Right Leg")
        -- R6 includes leg length; HipHeight describes the remaining ground clearance.
        return root.Size.Y * 0.5 + hum.HipHeight + (leg and leg.Size.Y or 0)
    end
    local function waypointReached(waypoint)
        if hum.FloorMaterial == Enum.Material.Air then return false end
        local delta = root.Position - waypoint.Position
        local horizontal = V(delta.X, 0, delta.Z)
        local groundGap = delta.Y - standingHeight()
        -- Navigation points are near the floor, not at HumanoidRootPart height.
        -- Keep a vertical bound so a nearby point on another level is not skipped.
        local verticalTolerance = math.max(1, root.Size.Y)
        return horizontal:Dot(horizontal) <= 4 and math.abs(groundGap) <= verticalTolerance
    end
    local function directRoute(destination)
        local delta = destination - root.Position
        if math.abs(delta.Y) > 4 then return false end
        local horizontal = V(delta.X, 0, delta.Z)
        if horizontal.Magnitude < 0.05 then return true end
        local clearance, groundHeight = 0.25, standingHeight()
        local head = character:FindFirstChild("Head")
        local fullHeight = groundHeight + root.Size.Y * 0.5 + (head and head.Size.Y or 1)
        local boxSize = V(root.Size.X + 0.1, fullHeight - clearance, root.Size.Z + 0.1)
        local center = root.Position + V(0, -groundHeight + clearance + boxSize.Y * 0.5, 0)
        local frame = CFrame.lookAt(center, center + horizontal)
        -- A torso-height ray can pass over a table or low wall that blocks the feet.
        -- Blockcast omits initial overlaps; reject those before sweeping the body.
        if #Workspace:GetPartBoundsInBox(frame, boxSize, routeOverlap) > 0 then return false end
        return Workspace:Blockcast(frame, boxSize, delta, rayParams) == nil
    end
    local function walk(now)
        if not goal then hum:Move(Vector3.zero); return end
        if directRoute(goal) then
            hum:MoveTo(goal)
        else
            if pathReady then
                local waypoint = waypoints[waypointIndex]
                while waypoint and waypointReached(waypoint) do
                    waypointIndex += 1
                    waypoint = waypoints[waypointIndex]
                end
                if waypoint then
                    if waypoint.Action == Enum.PathWaypointAction.Jump and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
                    hum:MoveTo(waypoint.Position)
                else pathReady = false end
            end
            if not pathReady then hum:Move(Vector3.zero); requestPath(now) end
        end
        if now - stuckAt >= 2 then
            local progress, remaining = root.Position - stuckPosition, goal - root.Position
            local unresolvedObjective = kind == "Chest" or kind == "Statue"
            if V(progress.X, 0, progress.Z).Magnitude < 1
                and (unresolvedObjective or V(remaining.X, 0, remaining.Z).Magnitude > 1 or math.abs(remaining.Y) > 1) then
                clearNavigation()
                requestPath(now)
                if hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
            end
            stuckPosition, stuckAt = root.Position, now
        end
    end
    local function face(position)
        local horizontal = V(position.X - root.Position.X, 0, position.Z - root.Position.Z)
        if horizontal.Magnitude > 0.2 then root.CFrame = CFrame.lookAt(root.Position, root.Position + horizontal) end
    end
    local function defendIncoming(now)
        if kind ~= "Combat" or not targetHuman or now < defendAt or not context.isAttackIncoming then return end
        local otherRoot = actorRoot(targetHuman)
        if otherRoot and (root.Position - otherRoot.Position).Magnitude <= 12 and context.isAttackIncoming(actor, targetHuman) then
            defendAt = now + 3.1
            diagnostics.defenses += 1
            context.defend(actor)
        end
    end
    local function think(now)
        diagnostics.thinks += 1
        local canWalk = context.eligible(actor) and #context.getHumanActors() > 0
        if character:GetAttribute("AILocomotionActive") ~= canWalk then character:SetAttribute("AILocomotionActive", canWalk) end
        if not canWalk then hum:Move(Vector3.zero); cancelHold(); return end
        if now >= selectAt then selectAt = now + SELECT_INTERVAL; chooseTarget(now) end
        if not target or not target.Parent then setTarget(nil, nil, nil); hum:Move(Vector3.zero); return end
        if kind == "Combat" then
            local otherRoot = targetHuman and actorRoot(targetHuman)
            if not otherRoot then selectAt = 0; setTarget(nil, nil, nil); return end
            local distance = (root.Position - otherRoot.Position).Magnitude
            goal = otherRoot.Position
            if distance <= MELEE_DISTANCE and visible(otherRoot.Position, targetHuman.Character) then
                hum:Move(Vector3.zero)
                face(otherRoot.Position)
                defendIncoming(now)
                if not context.isAttackIncoming and now >= defendAt then defendAt = now + 4; diagnostics.defenses += 1; context.defend(actor) end
                if now >= attackAt then attackAt = now + 1.2; diagnostics.attacks += 1; context.attack(actor) end
            else
                cancelHold()
                if character:GetAttribute("Transformed") == true and distance >= 11 and distance <= 22 and now >= lungeAt
                    and visible(otherRoot.Position, targetHuman.Character) then
                    face(otherRoot.Position)
                    lungeAt = now + 8.2
                    diagnostics.lunges += 1
                    context.lunge(actor)
                end
                walk(now)
            end
        elseif kind == "Chest" or kind == "Statue" then
            local primary = target.PrimaryPart
            local consumed = kind == "Chest" and "Looted" or "Destroyed"
            if not primary or target:GetAttribute(consumed) then selectAt = 0; setTarget(nil, nil, nil); return end
            if (root.Position - primary.Position).Magnitude <= INTERACT_DISTANCE and visible(primary.Position, target) then
                hum:Move(Vector3.zero)
                face(primary.Position)
                if heldTarget ~= target then cancelHold(); heldTarget = target; diagnostics.holdAttempts += 1 end
                diagnostics.holdCalls += 1
                local succeeded = kind == "Chest" and context.lootChest(actor, target) or nil
                if kind == "Statue" then succeeded = context.purifyStatue(actor, target) end
                if succeeded == true then
                    if kind == "Chest" then diagnostics.looted += 1 else diagnostics.purified += 1 end
                    selectAt = 0
                    setTarget(nil, nil, nil)
                end
            else cancelHold(); walk(now) end
        else cancelHold(); walk(now) end
    end
    blocked = path.Blocked:Connect(function(index)
        if destroyed or not pathReady or index < waypointIndex then return end
        clearNavigation()
    end)
    function controller:getDiagnostics()
        local snapshot = table.clone(diagnostics)
        snapshot.pathBusy, snapshot.waypoints, snapshot.waypointIndex = pathBusy, #waypoints, waypointIndex
        snapshot.destroyed, snapshot.activeConnections = destroyed, destroyed and 0 or 5
        return snapshot
    end
    function controller:destroy()
        if destroyed then return end
        destroyed = true
        if character.Parent then character:SetAttribute("AILocomotionActive", false) end
        generation += 1
        for _, connection in ipairs({ heartbeat, died, healthChanged, destroying, blocked }) do if connection then connection:Disconnect() end end
        heartbeat, died, healthChanged, destroying, blocked = nil, nil, nil, nil, nil
        if pathTask then task.cancel(pathTask); pathTask = nil end
        pathBusy = false
        cancelHold()
        table.clear(waypoints); table.clear(failures); table.clear(avoided)
        if character.Parent and hum.Parent then
            hum:Move(Vector3.zero)
            hum:MoveTo(root.Position)
        end
        path:Destroy()
        controllers[actor] = nil
        target, targetHuman, goal = nil, nil, nil
        diagnostics.currentTask = "Stopped"
    end
    died = hum.Died:Connect(function() controller:destroy() end)
    healthChanged = hum.HealthChanged:Connect(function(health)
        if health < lastHealth then retaliateUntil, selectAt = os.clock() + 8, 0 end
        lastHealth = health
    end)
    destroying = character.Destroying:Connect(function() controller:destroy() end)
    character:SetAttribute("AILocomotionActive", true)
    heartbeat = RunService.Heartbeat:Connect(function(delta)
        if destroyed then return end
        thoughtTime, reactionTime = thoughtTime + delta, reactionTime + delta
        local now = os.clock()
        if thoughtTime >= THINK_INTERVAL then thoughtTime %= THINK_INTERVAL; think(now) end
        if destroyed then return end
        if reactionTime >= 0.1 then
            reactionTime %= 0.1
            if context.eligible(actor) then defendIncoming(now) end
        end
    end)
    return controller
end

function BotController.destroy(actor)
    if actor and actor.IsBot then actor:Destroy() end
end

return BotController
