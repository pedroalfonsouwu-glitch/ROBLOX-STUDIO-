-- The bounds of DisableExitingBallBounds caused the wedge to be inserted above it which creates a confusing UX when placing the wedge
-- To fix this, the bounds part is inserted at runtime

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local addedAtRuntime = ServerStorage.AddedAtRuntime
addedAtRuntime.Parent = Workspace
