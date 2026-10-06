local function stopBallMovement(ball: Model)
	local primaryPart = ball.PrimaryPart
	if not primaryPart then
		return
	end

	local constraints = ball:FindFirstChild("Constraints")
	if not constraints then
		return
	end

	-- Zero out velocity applied to the ball
	local controlAngularVelocity = constraints:FindFirstChild("ControlAngularVelocity")
	if not controlAngularVelocity then
		return
	end

	controlAngularVelocity.AngularVelocity = Vector3.zero
	primaryPart.AssemblyLinearVelocity = Vector3.zero
	primaryPart.AssemblyAngularVelocity = Vector3.zero
end

return stopBallMovement
