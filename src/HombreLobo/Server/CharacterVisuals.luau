-- Apariencia original nativa: conserva rig, colisiones y escala del avatar.
local CharacterVisuals = {}
local appearances = setmetatable({}, { __mode = "k" })
local fur = Color3.fromRGB(71, 76, 81)
local pale = Color3.fromRGB(119, 117, 108)
local dark = Color3.fromRGB(32, 36, 41)
local silver = Color3.fromRGB(221, 232, 241)
local brass = Color3.fromRGB(164, 132, 72)
local ivory = Color3.fromRGB(218, 211, 193)
local V, C = Vector3.new, CFrame.new

local function weldedPart(parent, host, name, size, offset, color, className, shape)
    local part = Instance.new(className or "Part")
    part.Name, part.Size, part.Color = name, size, color
    part.Material, part.CastShadow = Enum.Material.SmoothPlastic, true
    part.Anchored, part.Massless = false, true
    part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
    if shape then part.Shape = shape end
    part.CFrame, part.Parent = host.CFrame * offset, parent
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1, weld.Parent = host, part, part
    return part
end
local function roundPart(parent, host, name, size, offset, color)
    return weldedPart(parent, host, name, size, offset, color or fur, nil, Enum.PartType.Ball)
end

function CharacterVisuals.restore(character)
    if not character then return end
    local saved = appearances[character]
    if saved then
        if saved.added then saved.added:Disconnect() end
        if saved.destroying then saved.destroying:Disconnect() end
        for object, value in pairs(saved.transparencies) do
            if object.Parent then object.Transparency = value end
        end
        if saved.model.Parent then saved.model:Destroy() end
        appearances[character] = nil
    end
    character:SetAttribute("Transformed", false)
end

function CharacterVisuals.setTransformationProgress(character, progress)
    local saved = appearances[character]
    if not saved then return false end
    progress = math.clamp(progress, 0, 1)
    saved.progress = progress
    for object, value in pairs(saved.transparencies) do
        if object.Parent then object.Transparency = value + (1 - value) * progress end
    end
    for _, object in ipairs(saved.model:GetDescendants()) do
        if object:IsA("BasePart") then object.Transparency = 1 - progress end
    end
    character:SetAttribute("Transformed", progress == 1)
    return true
end

function CharacterVisuals.transform(character, initialProgress)
    if not character then return false end
    if appearances[character] then return true end
    local head = character:FindFirstChild("Head")
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if not head or not torso or not head:IsA("BasePart") or not torso:IsA("BasePart") then return false end
    local model = Instance.new("Model")
    model.Name, model.Parent = "WolfForm", character
    local saved = { model = model, transparencies = {}, progress = initialProgress == nil and 1 or math.clamp(initialProgress, 0, 1) }
    appearances[character] = saved
    local function hide(object)
        if saved.transparencies[object] == nil then saved.transparencies[object] = object.Transparency end
        object.Transparency = saved.transparencies[object] + (1 - saved.transparencies[object]) * saved.progress
    end
    local function hideAccessory(object)
        if object:IsDescendantOf(model) then return end
        if object:IsA("BasePart") and object:FindFirstAncestorOfClass("Accessory") then hide(object) end
        if object:IsA("Decal") and object.Parent == head then hide(object) end
    end
    for _, object in ipairs(character:GetDescendants()) do hideAccessory(object) end
    -- Todas las piezas originales permanecen intactas debajo de la silueta.
    for _, body in ipairs(character:GetChildren()) do
        if body:IsA("BasePart") and body.Name ~= "HumanoidRootPart" then
            hide(body)
            if body ~= head and body ~= torso then
                local scale = V(1.16, 1.08, 1.24)
                local color = fur
                if body.Name == "LowerTorso" then scale = V(1.13, 1.15, 1.2) end
                if string.find(body.Name, "Hand") then scale = V(1.3, 1.25, 1.45); color = dark end
                if string.find(body.Name, "Foot") then scale = V(1.25, 1.1, 1.55); color = dark end
                roundPart(model, body, "Fur_" .. body.Name, body.Size * scale, C(), color)
                if body.Name == "Right Arm" or body.Name == "Left Arm" then
                    roundPart(model, body, "Forearm", body.Size * V(1.22, 0.63, 1.27), C(0, -body.Size.Y * 0.22, -0.04))
                elseif body.Name == "Right Leg" or body.Name == "Left Leg" then
                    roundPart(model, body, "Paw", V(body.Size.X * 1.22, body.Size.Y * 0.32, body.Size.Z * 1.6),
                        C(0, -body.Size.Y * 0.39, -body.Size.Z * 0.22), dark)
                end
            end
        end
    end
    roundPart(model, torso, "ChestFur", torso.Size * V(1.2, 1.15, 1.3), C(0, 0.04, -0.05))
    -- La silueta del torso es continua: no hay una placa que parezca un babero.
    roundPart(model, torso, "Mane", V(torso.Size.X * 1.18, torso.Size.Y * 0.62, torso.Size.Z * 1.6),
        C(0, torso.Size.Y * 0.4, 0.03), dark)
    local scale = math.clamp(head.Size.Y, 0.75, 1.6)
    local function hp(name, size, x, y, z, color, className, angles)
        local offset = C(x, y, z)
        if angles then offset = offset * angles end
        if className then return weldedPart(model, head, name, size * scale, offset, color, className) end
        return roundPart(model, head, name, size * scale, offset, color)
    end
    roundPart(model, head, "WolfHead", head.Size * V(1.15, 1.24, 1.28), C(), fur)
    hp("Muzzle", V(1.06, 0.65, 0.94), 0, -0.10 * scale, -head.Size.Z * 0.5 - 0.28 * scale, pale)
    hp("Snout", V(0.76, 0.49, 0.62), 0, -0.13 * scale, -head.Size.Z * 0.5 - 0.67 * scale, pale)
    hp("Jaw", V(0.89, 0.33, 0.78), 0, -0.40 * scale, -head.Size.Z * 0.5 - 0.4 * scale, fur)
    hp("Mouth", V(0.77, 0.075, 0.64), 0, -0.29 * scale, -head.Size.Z * 0.5 - 0.5 * scale, dark)
    hp("Nose", V(0.44, 0.27, 0.26), 0, -0.06 * scale, -head.Size.Z * 0.5 - 0.97 * scale, dark)
    for _, side in ipairs({-1, 1}) do
        local eyeX = side * head.Size.X * 0.25
        hp("EyeSocket", V(0.38, 0.27, 0.2), eyeX, head.Size.Y * 0.19, -head.Size.Z * 0.5 - 0.08 * scale, dark)
        local eye = hp("WolfEye", V(0.21, 0.15, 0.11), eyeX, head.Size.Y * 0.19, -head.Size.Z * 0.5 - 0.19 * scale, Color3.fromRGB(255, 184, 72))
        eye.Material = Enum.Material.Neon
        hp("Pupil", V(0.046, 0.12, 0.035), eyeX, head.Size.Y * 0.19, -head.Size.Z * 0.5 - 0.25 * scale, dark)
        hp("Brow", V(0.45, 0.16, 0.26), eyeX, head.Size.Y * 0.32, -head.Size.Z * 0.5 - 0.08 * scale, fur, "WedgePart", CFrame.Angles(0, 0, -side * 0.15))
        local earRotation = CFrame.Angles(0, side * math.pi / 2, -side * 0.18)
        hp("Ear", V(0.56, 0.93, 0.54), side * head.Size.X * 0.32, head.Size.Y * 0.71, 0.04, fur, "WedgePart", earRotation)
        hp("InnerEar", V(0.31, 0.62, 0.37), side * head.Size.X * 0.32, head.Size.Y * 0.72, -0.1 * scale, pale, "WedgePart", earRotation)
        hp("CheekFur", V(0.35, 0.64, 0.6), side * head.Size.X * 0.47, -0.18 * scale, -0.02, fur, "WedgePart", CFrame.Angles(0, side * math.pi / 2, side * 1.85))
        -- Tres secciones estrechas dibujan un colmillo curvo, no un bloque blanco.
        local fangRoot = hp("Fang", V(0.13, 0.24, 0.15), side * 0.30 * scale, -0.34 * scale,
            -head.Size.Z * 0.5 - 0.64 * scale, ivory)
        local fangCurve = hp("FangCurve", V(0.10, 0.19, 0.13), side * 0.30 * scale, -0.49 * scale,
            -head.Size.Z * 0.5 - 0.66 * scale, ivory, nil, CFrame.Angles(-0.35, 0, 0))
        local fangTip = hp("FangTip", V(0.055, 0.18, 0.09), side * 0.30 * scale, -0.60 * scale,
            -head.Size.Z * 0.5 - 0.62 * scale, ivory, "WedgePart", CFrame.Angles(-0.62, 0, 0))
        fangRoot.CastShadow, fangCurve.CastShadow, fangTip.CastShadow = false, false, false
        roundPart(model, torso, "ShoulderFur", V(0.92, torso.Size.Y * 0.65, torso.Size.Z * 1.4),
            C(side * (torso.Size.X / 2 + 0.04), torso.Size.Y * 0.3, 0), fur)
        for tuft = 1, 2 do
            weldedPart(model, torso, "ManeTuft", V(0.45, 0.72, 0.58),
                C(side * (torso.Size.X * 0.47), torso.Size.Y * (0.3 - tuft * 0.18), 0.24)
                    * CFrame.Angles(0, side * math.pi / 2, side * 0.65), dark, "WedgePart")
        end
        local hand = character:FindFirstChild(side == 1 and "RightHand" or "LeftHand")
            or character:FindFirstChild(side == 1 and "Right Arm" or "Left Arm")
        if hand and hand:IsA("BasePart") then
            local palmY = -hand.Size.Y / 2 + 0.2
            roundPart(model, hand, "HandPaw", V(hand.Size.X * 1.3, 0.55, hand.Size.Z * 1.38), C(0, palmY, -0.08), dark)
            for finger = -1, 1 do
                local claw = roundPart(model, hand, "Claw", V(0.12, 0.14, 0.37),
                    C(finger * hand.Size.X * 0.23, palmY - 0.10, -hand.Size.Z / 2 - 0.18)
                        * CFrame.Angles(-0.12, finger * -0.08, 0), ivory)
                local curve = roundPart(model, hand, "ClawCurve", V(0.095, 0.11, 0.30),
                    C(finger * hand.Size.X * 0.25, palmY - 0.16, -hand.Size.Z / 2 - 0.43)
                        * CFrame.Angles(-0.38, finger * -0.08, 0), ivory)
                local tip = weldedPart(model, hand, "ClawTip", V(0.055, 0.085, 0.22),
                    C(finger * hand.Size.X * 0.27, palmY - 0.25, -hand.Size.Z / 2 - 0.62)
                        * CFrame.Angles(-0.68, finger * -0.08, 0), ivory, "WedgePart")
                claw.CastShadow, curve.CastShadow, tip.CastShadow = false, false, false
            end
        end
    end
    local lower = character:FindFirstChild("LowerTorso") or torso
    local tailStart = lower.Size.Z / 2
    local tailBase = roundPart(model, lower, "TailBase", V(0.63, 0.65, 0.96),
        C(0, -0.18, tailStart + 0.38) * CFrame.Angles(0.28, 0, 0))
    tailBase:FindFirstChildOfClass("WeldConstraint"):Destroy()
    local tailJoint = Instance.new("Motor6D")
    local tailPivot = lower.CFrame * C(0, -0.1, tailStart)
    tailJoint.Name, tailJoint.Part0, tailJoint.Part1 = "WolfTail", lower, tailBase
    tailJoint.C0, tailJoint.C1 = lower.CFrame:ToObjectSpace(tailPivot), tailBase.CFrame:ToObjectSpace(tailPivot)
    tailJoint.Parent = tailBase
    local function tailSegment(name, dimensions, offset, color)
        roundPart(model, tailBase, name, dimensions, tailBase.CFrame:ToObjectSpace(lower.CFrame * offset), color)
    end
    tailSegment("Tail", V(0.56, 0.58, 1.08), C(0, -0.44, tailStart + 0.93) * CFrame.Angles(0.46, 0, 0), fur)
    tailSegment("TailCurve", V(0.42, 0.46, 0.88), C(0, -0.80, tailStart + 1.46) * CFrame.Angles(0.66, 0, 0), fur)
    tailSegment("TailTip", V(0.22, 0.28, 0.58), C(0, -1.16, tailStart + 1.80) * CFrame.Angles(0.88, 0, 0), dark)
    saved.added = character.DescendantAdded:Connect(hideAccessory)
    saved.destroying = character.Destroying:Connect(function() CharacterVisuals.restore(character) end)
    CharacterVisuals.setTransformationProgress(character, saved.progress)
    return true
end

function CharacterVisuals.createBlade()
    local tool = Instance.new("Tool")
    tool.Name, tool.ToolTip = "EspadaPlata", "Espada de plata: F o botón Atacar"
    tool.RequiresHandle, tool.CanBeDropped, tool.Enabled = true, false, false
    tool:SetAttribute("HombreLoboItem", "SilverBlade")
    local handle = Instance.new("Part")
    handle.Name, handle.Size, handle.Color = "Handle", V(0.29, 1.1, 0.29), Color3.fromRGB(61, 42, 32)
    handle.Material, handle.Anchored, handle.Massless = Enum.Material.Wood, false, true
    handle.CanCollide, handle.CanTouch, handle.CanQuery = false, false, false
    handle.Parent = tool
    local function metal(name, size, offset, color, className)
        local part = weldedPart(tool, handle, name, size, offset, color or silver, className)
        part.Material = Enum.Material.Metal
        return part
    end
    local guard = metal("Guard", V(1.38, 0.17, 0.34), C(0, 0.65, 0), brass)
    roundPart(tool, handle, "GuardCenter", V(0.48, 0.32, 0.44), C(0, 0.65, 0), brass).Material = Enum.Material.Metal
    for _, side in ipairs({-1, 1}) do
        roundPart(tool, handle, "GuardEnd", V(0.25, 0.27, 0.29), C(side * 0.73, 0.57, 0), brass).Material = Enum.Material.Metal
    end
    for band = -2, 2 do
        local wrap = weldedPart(tool, handle, "GripWrap", V(0.085, 0.33, 0.33),
            C(0, band * 0.18, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(102, 74, 45), nil, Enum.PartType.Cylinder)
        wrap.Material = Enum.Material.Wood
    end
    roundPart(tool, handle, "Pommel", V(0.38, 0.4, 0.38), C(0, -0.69, 0), brass).Material = Enum.Material.Metal
    local blade = metal("Blade", V(0.43, 2.85, 0.12), C(0, 2.12, 0))
    metal("BladeRidge", V(0.09, 2.85, 0.05), C(0, 2.12, -0.077), Color3.fromRGB(245, 249, 253))
    metal("Fuller", V(0.034, 2.37, 0.013), C(0, 2.02, -0.109), Color3.fromRGB(102, 127, 147))
    for _, side in ipairs({-1, 1}) do
        metal(side == -1 and "BladeTip" or "BladeTipOther", V(0.12, 0.6, 0.215),
            C(side * 0.1075, 3.84, 0) * CFrame.Angles(0, -side * math.pi / 2, 0), silver, "WedgePart")
    end
    roundPart(tool, handle, "MoonStone", V(0.12, 0.15, 0.045), C(0, 0.65, -0.24), Color3.fromRGB(102, 181, 207)).Material = Enum.Material.Neon
    tool.Grip = C(0, -0.1, 0)
    return tool
end

local function heldTool(name, itemId, tip, dimensions, color, material)
    local tool = Instance.new("Tool")
    tool.Name, tool.ToolTip = name, tip
    tool.RequiresHandle, tool.CanBeDropped, tool.Enabled = true, false, false
    tool:SetAttribute("HombreLoboItem", itemId)
    local handle = Instance.new("Part")
    handle.Name, handle.Size, handle.Color = "Handle", dimensions, color
    handle.Material, handle.Anchored, handle.Massless = material, false, true
    handle.CanCollide, handle.CanTouch, handle.CanQuery = false, false, false
    handle.Parent = tool
    return tool, handle
end

function CharacterVisuals.createPistol()
    local tool, handle = heldTool("Pistola", "Pistol", "Pistola: disparo validado por el servidor",
        V(0.45, 1.05, 0.55), Color3.fromRGB(40, 39, 37), Enum.Material.SmoothPlastic)
    local metal = Color3.fromRGB(76, 80, 85)
    local function piece(name, dimensions, offset, color)
        local p = weldedPart(tool, handle, name, dimensions, offset, color or metal)
        p.Material = Enum.Material.Metal
        return p
    end
    piece("Slide", V(0.47, 0.37, 1.55), C(0, 0.59, -0.45))
    piece("Muzzle", V(0.31, 0.26, 0.16), C(0, 0.59, -1.30), dark)
    piece("TriggerGuard", V(0.16, 0.11, 0.75), C(0, -0.04, -0.52))
    piece("Trigger", V(0.1, 0.31, 0.12), C(0, 0.15, -0.57) * CFrame.Angles(-0.18, 0, 0), dark)
    piece("Sight", V(0.13, 0.09, 0.15), C(0, 0.82, -1.05), dark)
    tool.Grip = C(0, -0.12, 0)
    return tool
end

function CharacterVisuals.createBook()
    local cover = Color3.fromRGB(61, 43, 37)
    local tool, handle = heldTool("Grimorio", "Grimoire", "Grimorio: leer la pista de Elar",
        V(1.3, 1.8, 0.14), cover, Enum.Material.Wood)
    local function page(name, dimensions, offset, color, material)
        local p = weldedPart(tool, handle, name, dimensions, offset, color)
        p.Material = material or Enum.Material.SmoothPlastic
        return p
    end
    page("Paginas", V(1.15, 1.64, 0.32), C(0, 0, 0.23), Color3.fromRGB(205, 192, 156))
    page("Contratapa", V(1.3, 1.8, 0.14), C(0, 0, 0.46), cover, Enum.Material.Wood)
    page("Lomo", V(0.16, 1.8, 0.58), C(-0.62, 0, 0.23), cover, Enum.Material.Wood)
    page("EmblemaLunar", V(0.37, 0.37, 0.045), C(0, 0.2, -0.10), brass, Enum.Material.Metal)
    page("Cierre", V(0.22, 0.13, 0.08), C(0.53, 0, -0.12), brass, Enum.Material.Metal)
    tool.Grip = C(0, -0.1, 0) * CFrame.Angles(0, 0.25, 0)
    return tool
end
return CharacterVisuals
