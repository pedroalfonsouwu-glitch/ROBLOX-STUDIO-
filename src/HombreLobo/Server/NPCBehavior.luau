-- Two short, terrain-flat village patrols. No Humanoid AI or pathfinding loop.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local NPCBehavior = {}
local CHECK_INTERVAL, NEAR_DISTANCE, DIALOG_DISTANCE = 0.25, 96, 20
local DIALOG_TTL, WALK_SPEED = 30, 2.5
local dialogSerial = 0 -- Monotonic across generated worlds in this server.

local function playerRoot(player)
    local character = player.Parent == Players and player.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return hum and hum.Health > 0 and root and root:IsA("BasePart") and root or nil
end
local function cancelWalk(actor)
    if actor.completed then actor.completed:Disconnect(); actor.completed = nil end
    if actor.tween then actor.tween:Cancel(); actor.tween:Destroy(); actor.tween = nil end
end
local function face(actor, position)
    local direction = Vector3.new(position.X - actor.root.Position.X, 0, position.Z - actor.root.Position.Z)
    if direction.Magnitude < 0.05 then return end
    local target = CFrame.lookAt(actor.root.Position, actor.root.Position + direction)
    if actor.root.CFrame.LookVector:Dot(target.LookVector) < 0.999 then actor.root.CFrame = target end
end
local function markIdle(actor, now)
    if actor.model:GetAttribute("NPCState") ~= "Idle" then actor.model:SetAttribute("NPCState", "Idle") end
    if actor.model:GetAttribute("InteractingUserId") ~= 0 then actor.model:SetAttribute("InteractingUserId", 0) end
    actor.focus, actor.nextMoveAt = nil, now + 2.5
end

function NPCBehavior.start(world)
    assert(world and world.root, "NPCBehavior requires a generated world")
    local controller = { actors = {}, byPart = {}, stopped = false, nextDialogId = dialogSerial }
    for index, target in ipairs({ world.guide, world.shop }) do
        local rig = target and target.Parent
        local root = rig and rig.PrimaryPart
        if root then
            local home = rig:GetAttribute("HomeCFrame") or root.CFrame
            local actor = { model = rig, root = root, part = target, home = home,
                patrolPoint = home.Position + home.LookVector * 4,
                holds = {}, routeIndex = 0, nextMoveAt = os.clock() + 3 + index }
            table.insert(controller.actors, actor)
            controller.byPart[target] = actor
        end
    end

    function controller:release(player, token)
        if self.stopped then return end
        local now = os.clock()
        for _, actor in ipairs(self.actors) do
            local hold = actor.holds[player]
            if hold and (token == nil or hold.token == token) then
                actor.holds[player] = nil
                if actor.focus == player then actor.focus = nil end
                if next(actor.holds) == nil and not actor.tween then markIdle(actor, now) end
            end
        end
    end

    function controller:interact(target, player)
        if self.stopped then return false end
        local actor, root = self.byPart[target], playerRoot(player)
        if not actor or not root or not actor.model:IsDescendantOf(world.root)
            or (root.Position - target.Position).Magnitude > DIALOG_DISTANCE then return false end
        self:release(player)
        cancelWalk(actor)
        dialogSerial += 1
        self.nextDialogId = dialogSerial
        actor.holds[player] = { expires = os.clock() + DIALOG_TTL, token = dialogSerial }
        actor.focus = player
        face(actor, root.Position)
        actor.model:SetAttribute("NPCState", "Greeting")
        actor.model:SetAttribute("GreetingAt", Workspace:GetServerTimeNow())
        actor.model:SetAttribute("InteractingUserId", player.UserId)
        return true, dialogSerial
    end

    function controller:destroy()
        if self.stopped then return end
        self.stopped = true
        if self.checkTask then task.cancel(self.checkTask); self.checkTask = nil end
        if self.destroying then self.destroying:Disconnect(); self.destroying = nil end
        for _, actor in ipairs(self.actors) do cancelWalk(actor); table.clear(actor.holds) end
        table.clear(self.byPart)
        table.clear(self.actors)
    end

    local function beginWalk(actor, now)
        actor.routeIndex = actor.routeIndex == 1 and 2 or 1
        local destination = actor.routeIndex == 1 and actor.patrolPoint or actor.home.Position
        local delta = destination - actor.root.Position
        if delta.Magnitude < 0.1 then
            actor.root.CFrame = actor.home
            actor.nextMoveAt = now + 3.5
            return
        end
        face(actor, destination)
        local orientation = actor.root.CFrame.Rotation
        local target = CFrame.new(destination) * orientation
        actor.model:SetAttribute("NPCState", "Walking")
        actor.model:SetAttribute("WalkStartedAt", Workspace:GetServerTimeNow())
        local tween = TweenService:Create(actor.root, TweenInfo.new(delta.Magnitude / WALK_SPEED,
            Enum.EasingStyle.Linear), { CFrame = target })
        actor.tween = tween
        actor.completed = tween.Completed:Connect(function(state)
            if controller.stopped or actor.tween ~= tween then return end
            actor.completed:Disconnect(); actor.completed = nil
            actor.tween = nil
            tween:Destroy()
            if state == Enum.PlaybackState.Completed then
                if actor.routeIndex == 2 then actor.root.CFrame = actor.home end
                actor.model:SetAttribute("NPCState", "Idle")
                actor.nextMoveAt = os.clock() + 3.5
            end
        end)
        tween:Play()
    end

    local function check()
        controller.checkTask = nil
        if controller.stopped then return end
        if not world.root.Parent then controller:destroy(); return end
        local now, roots = os.clock(), {}
        for _, player in ipairs(Players:GetPlayers()) do
            local root = playerRoot(player)
            if root then roots[player] = root end
        end
        for _, actor in ipairs(controller.actors) do
            if not actor.root.Parent then continue end
            for player, hold in pairs(actor.holds) do
                local root = roots[player]
                if not root or now >= hold.expires or (root.Position - actor.part.Position).Magnitude > DIALOG_DISTANCE then
                    actor.holds[player] = nil
                    if actor.focus == player then actor.focus = nil end
                end
            end
            local focus = actor.focus or next(actor.holds)
            if focus then
                actor.focus = focus
                face(actor, roots[focus].Position)
                if actor.model:GetAttribute("InteractingUserId") ~= focus.UserId then
                    actor.model:SetAttribute("InteractingUserId", focus.UserId)
                end
                if Workspace:GetServerTimeNow() - (actor.model:GetAttribute("GreetingAt") or 0) > 1.4 then
                    if actor.model:GetAttribute("NPCState") ~= "Talking" then actor.model:SetAttribute("NPCState", "Talking") end
                end
            else
                if actor.model:GetAttribute("InteractingUserId") ~= 0 then markIdle(actor, now) end
                local nearby = false
                for _, root in pairs(roots) do
                    if (root.Position - actor.root.Position).Magnitude <= NEAR_DISTANCE then nearby = true; break end
                end
                if not nearby then
                    if actor.tween then cancelWalk(actor); markIdle(actor, now) end
                elseif not actor.tween and now >= actor.nextMoveAt then
                    beginWalk(actor, now)
                end
            end
        end
        controller.checkTask = task.delay(CHECK_INTERVAL, check)
    end
    controller.destroying = world.root.Destroying:Connect(function() controller:destroy() end)
    controller.checkTask = task.delay(CHECK_INTERVAL, check)
    return controller
end

return NPCBehavior
