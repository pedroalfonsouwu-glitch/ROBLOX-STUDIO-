local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local toggleBallControl = require(ReplicatedStorage.toggleBallControl)
local respawnBallAsync = require(ReplicatedStorage.respawnBallAsync)

local RESETTING_ATTRIBUTE_NAME = "Resetting"

-- Get any "reset player" parts
local resetPlayerBoundsParts = CollectionService:GetTagged("ResetPlayer")

local function ballHitResetBounds(ball: Model)
	-- Disable control, reset ball, re-enable control upon hitting reset bounds
	toggleBallControl(ball, false)

	respawnBallAsync(ball)

	toggleBallControl(ball, true)

	-- Allow the ball to be reset again
	ball:SetAttribute(RESETTING_ATTRIBUTE_NAME, nil)
end

-- Check if any of these parts contains a Ball
local function onHeartbeat()
	for _, boundPart in resetPlayerBoundsParts do
		local partsInBounds = Workspace:GetPartBoundsInBox(boundPart:GetPivot(), boundPart.Size)
		for _, partIn in partsInBounds do
			if partIn.Name == "CollisionBall" then
				local ball = partIn.Parent.Parent
				-- Ensure the ball is not already being reset
				if not ball:GetAttribute(RESETTING_ATTRIBUTE_NAME) then
					ball:SetAttribute(RESETTING_ATTRIBUTE_NAME, true)
					ballHitResetBounds(ball)
				end
			end
		end
	end
end

RunService.Heartbeat:Connect(onHeartbeat)
