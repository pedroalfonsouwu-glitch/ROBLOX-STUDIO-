local ReplicatedStorage = game:GetService("ReplicatedStorage")

local toggleBallControl = require(ReplicatedStorage.toggleBallControl)
local respawnBallAsync = require(ReplicatedStorage.respawnBallAsync)
local getPlayerFromSeat = require(ReplicatedStorage.getPlayerFromSeat)

local targetHitRemoteEvent = ReplicatedStorage.Instances.Events.TargetHitRemoteEvent

-- Coefficients used in the calculation of the maximum distance allowed between the ball and the target.
-- These values were fine-tuned through experimentation with various ball velocities.
local MAX_DISTANCE_CHECK_COEFFICIENT = 0.15
local MAX_DISTANCE_CHECK_CONSTANT = 30

local TARGET_TAG = "Target"

local function processHitAsync(ball: Model, _target: Model, _player: Player)
	-- TODO: process target based on future direction of T3 (ex: award points?)
	-- print(`Server processed player {player.Name} hit target {target:GetFullName()}`)

	-- Reset the ball position and state
	respawnBallAsync(ball)
end

local function validateTarget(target: Model)
	return table.find(target:GetTags(), TARGET_TAG) ~= nil
end

local function onTargetHit(player: Player, target: Model, ball: Model)
	-- Validate that the player who fired the remote is the player sitting in the ball
	local seat = ball:FindFirstChildWhichIsA("Seat")
	if not seat then
		warn(`Ball {ball.Name} does not have a seat`)
		return
	end

	local playerInBall = getPlayerFromSeat(seat)
	if player ~= playerInBall then
		warn(`Player ({player.Name}) does not match player in the ball ({playerInBall.Name})`)
		return
	end

	-- Validate that the target is actually a target (make sure it has the target tag)
	local validTarget = validateTarget(target)
	if not validTarget then
		warn(`Target model {target:GetFullName()} does not have {TARGET_TAG} tag`)
		return
	end

	-- Calculate the server distance between the ball and target
	local hitBox = target.PrimaryPart
	local distanceFromBallToTarget = (hitBox:GetPivot().Position - ball:GetPivot().Position).Magnitude

	-- Calculates the maximum allowable distance for a valid hit. This distance is a function
	-- of the ball's velocity, scaling with the velocity to allow for more leniency at higher speeds.
	local ballPrimaryPart = ball.PrimaryPart
	if not ballPrimaryPart then
		warn(`Ball {ball.Name} does not have a primary part`)
		return
	end
	local ballVelocity = ballPrimaryPart.AssemblyLinearVelocity.Magnitude
	local maxDistanceCheck = (MAX_DISTANCE_CHECK_COEFFICIENT * ballVelocity) + MAX_DISTANCE_CHECK_CONSTANT

	-- Ensure the server distance is within the maximum distance allowed to ensure the hit is valid
	if distanceFromBallToTarget > maxDistanceCheck then
		warn(`Player {player.Name} failed target distance hit sanity check`)
		return
	end

	toggleBallControl(ball, false)

	-- Process the hit on the server
	processHitAsync(ball, target, player)

	-- Re-enable the player's input
	toggleBallControl(ball, true)
end

targetHitRemoteEvent.OnServerEvent:Connect(onTargetHit)
