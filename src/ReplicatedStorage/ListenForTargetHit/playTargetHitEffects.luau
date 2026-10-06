local Workspace = game:GetService("Workspace")
local confettiFolder = Workspace.VFX.Confetti

local confettiFolderPathMap = {
	["bottomCircleTarget"] = confettiFolder.LowYellowConfetti,
	["middleCircleTarget"] = confettiFolder.MidBlueConfetti,
	["topCircleTarget"] = confettiFolder.HighRedConfetti,
}

local CONFETTI_TIME = 3

local function playTargetHitEffects(target: Instance)
	-- Enable the correct confetti particle emitters for CONFETTI_TIME
	local targetParent = target.Parent
	if not targetParent then
		return
	end

	confettiFolder = confettiFolderPathMap[targetParent.Name]
	for _, desc in confettiFolder:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = true
			task.delay(CONFETTI_TIME, function()
				desc.Enabled = false
			end)
		end
	end
end

return playTargetHitEffects
