local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BALL_RESET_HEIGHT = 10
local RESPAWN_TIME = 3
local ENABLE_WOBBLE_TIME = 0.5
local BALL_SPAWN = Workspace.Ball_Spawn_Target.circleHollowa.BallSpawnAttachment

local function respawnBallAsync(ball: Model)
	if RunService:IsClient() then
		warn("Ball cannot be reset from the Client")
		return
	end

	-- Wait respawn time before resetting
	task.wait(RESPAWN_TIME)

	-- Drop down from above the spawn position when reset
	local resetCFrame = BALL_SPAWN.WorldCFrame + BALL_RESET_HEIGHT * Vector3.yAxis
	ball:PivotTo(resetCFrame)

	-- Without wait, player is still wobbling upon respawn
	task.wait(ENABLE_WOBBLE_TIME)
end

return respawnBallAsync
