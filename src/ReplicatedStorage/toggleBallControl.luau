local ReplicatedStorage = game:GetService("ReplicatedStorage")

local stopBallMovement = require(ReplicatedStorage.stopBallMovement)
local getPlayerFromSeat = require(ReplicatedStorage.getPlayerFromSeat)

local function toggleBallControl(ball: Model, isEnabled: boolean)
	local seat = ball:FindFirstChildWhichIsA("Seat")
	if not seat then
		return
	end

	local player = getPlayerFromSeat(seat)

	local events = ball:FindFirstChild("Events")
	if not events then
		return
	end

	local toggleInputControlsRemoteEvent = events:FindFirstChild("ToggleInputControlsRemoteEvent")
	if not toggleInputControlsRemoteEvent then
		return
	end

	if not isEnabled then
		-- Zero out velocity applied to the ball
		stopBallMovement(ball)

		-- Disable the player's input
		if player then
			toggleInputControlsRemoteEvent:FireClient(player, false)
		end
	else
		-- Enable the player's input
		if player then
			toggleInputControlsRemoteEvent:FireClient(player, true)
		end
	end
end

return toggleBallControl
