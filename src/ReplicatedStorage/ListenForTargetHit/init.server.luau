local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local getPlayerFromSeat = require(ReplicatedStorage.getPlayerFromSeat)
local playTargetHitEffects = require(script.playTargetHitEffects)

local targetHitRemoteEvent = ReplicatedStorage.Instances.Events.TargetHitRemoteEvent

local PLAYER_HIT_REFRESH_TIME = 5
local TARGET_TAG = "Target"
local recentlyHitTarget = false
local localPlayer = Players.LocalPlayer
local hitConnections = {}

local function onTargetHit(target: Model, otherPart: BasePart)
	if not otherPart or not otherPart.Parent then
		return
	end

	-- Only process hit if otherPart was the CollisionBall of the Ball model
	if otherPart.Name ~= "CollisionBall" then
		return
	end

	-- Only process hit if the target was not hit recently (debounce)
	if recentlyHitTarget then
		return
	end
	recentlyHitTarget = true

	-- Only process hit if player in the ball is the local player
	local ball = otherPart.Parent.Parent
	local seat = ball.DriverSeat
	local playerInBall = getPlayerFromSeat(seat)
	if playerInBall ~= localPlayer then
		return
	end

	playTargetHitEffects(target)
	targetHitRemoteEvent:FireServer(target, ball)

	task.delay(PLAYER_HIT_REFRESH_TIME, function()
		recentlyHitTarget = false
	end)
end

local function onTargetAdded(target: Model)
	local primaryPart = target.PrimaryPart
	if not primaryPart then
		return
	end

	hitConnections[target] = primaryPart.Touched:Connect(function(otherPart: BasePart)
		onTargetHit(target, otherPart)
	end)
end

-- Add any currently existing "target" models
local targetModels = CollectionService:GetTagged(TARGET_TAG)
for _, model in targetModels do
	onTargetAdded(model)
end

local function onTargetRemoved(target: Model)
	if hitConnections[target] then
		hitConnections[target]:Disconnect()
		hitConnections[target] = nil
	end
end

-- Add any "target" models as they stream in
CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(function(object: Instance)
	if object:IsA("Model") then
		onTargetAdded(object)
	end
end)

-- Remove any "target" models as they stream out
CollectionService:GetInstanceRemovedSignal(TARGET_TAG):Connect(function(object: Instance)
	if object:IsA("Model") then
		onTargetRemoved(object)
	end
end)
