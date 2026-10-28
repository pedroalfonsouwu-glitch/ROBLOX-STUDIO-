-- Mapa reproducible por semilla; sólo modifica su propia región.
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local WorldGenerator = {}
local V, C = Vector3.new, CFrame.new
local palette = {
    wood = Color3.fromRGB(102, 72, 48), trim = Color3.fromRGB(54, 43, 35),
    stone = Color3.fromRGB(88, 99, 109), leaf = Color3.fromRGB(48, 88, 63),
    gold = Color3.fromRGB(216, 165, 81), iron = Color3.fromRGB(56, 65, 72),
    moon = Color3.fromRGB(150, 186, 210), paper = Color3.fromRGB(238, 229, 202),
}
local landmarkColors = {
    Cabin = Color3.fromRGB(163, 121, 72), Treehouse = Color3.fromRGB(86, 135, 88),
    Cave = Color3.fromRGB(99, 174, 170), Ruins = palette.moon,
}
-- Prepared A/B variant: only small-object shadow flags; geometry, materials and RNG remain unchanged.
local smallShadowParts = {
    SoporteLuz = true, BaseLuz = true, TechoLuz = true, LuzInterior = true,
    MarcoVentana = true, Ventana = true, Escalon = true, Hierba = true, Cerradura = true,
}
local function part(name, size, frame, color, material, parent, className)
    local p = Instance.new(className or "Part")
    p.Name, p.Size, p.CFrame = name, size, frame
    p.Color, p.Material = color, material or Enum.Material.SmoothPlastic
    p.Anchored = true
    local template = parent and parent:GetAttribute("AssetTemplateKey")
    if smallShadowParts[name]
        or (template == "Lantern" and name ~= "Poste" and name ~= "Brazo")
        or (template == "WolfStatue" and name == "Ojo") then
        p.CastShadow = false
    end
    p.CanTouch = false -- La geometría estática no usa eventos Touched.
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end
local function model(name, parent, templateKey)
    local m = Instance.new("Model")
    m.Name = name
    m:SetAttribute("AssetTemplateKey", templateKey or name)
    m.Parent = parent
    return m
end
local function prompt(parent, action, object, duration)
    local p = Instance.new("ProximityPrompt")
    p.ActionText, p.ObjectText = action, object
    p.HoldDuration, p.MaxActivationDistance = duration or 0, 10
    p.RequiresLineOfSight = false
    p.KeyboardKeyCode = Enum.KeyCode.E
    p.Parent = parent
    return p
end
local function light(parent, color, range)
    local l = Instance.new("PointLight")
    l.Color, l.Range, l.Brightness = color, range or 20, 1.4
    l.Shadows, l.Parent = false, parent
end
local function billboard(adornee, title, caption)
    local gui = Instance.new("BillboardGui")
    gui.Name, gui.Adornee = "NombreYMision", adornee
    gui.Size = UDim2.fromOffset(246, 116)
    gui.StudsOffsetWorldSpace = V(0, 3.1, 0)
    gui.MaxDistance, gui.AlwaysOnTop, gui.LightInfluence = 85, false, 0
    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromScale(1, 1)
    panel.BackgroundColor3, panel.BackgroundTransparency = Color3.fromRGB(25, 39, 36), 0.16
    panel.BorderSizePixel, panel.Parent = 0, gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius, corner.Parent = UDim.new(0, 9), panel
    local name = Instance.new("TextLabel")
    name.Size, name.Position = UDim2.new(1, -12, 0, 28), UDim2.fromOffset(6, 3)
    name.BackgroundTransparency, name.Text = 1, title
    name.TextColor3, name.Font, name.TextSize = palette.gold, Enum.Font.GothamBold, 17
    name.Parent = panel
    local mission = Instance.new("TextLabel")
    mission.Size, mission.Position = UDim2.new(1, -18, 0, 78), UDim2.fromOffset(9, 32)
    mission.BackgroundTransparency, mission.Text = 1, caption
    mission.TextColor3, mission.Font, mission.TextSize = Color3.fromRGB(237, 235, 218), Enum.Font.Gotham, 14
    mission.TextWrapped, mission.Parent = true, panel
    gui.Parent = adornee
end
function WorldGenerator.generate(seed, config)
    local cfg = config.Map or {}
    local size, cell = cfg.Size or 384, cfg.CellSize or 12
    local base, amplitude = cfg.BaseHeight or 8, cfg.HeightAmplitude or 16
    assert(size >= 320 and size % 8 == 0, "Map.Size debe ser >= 320 y múltiplo de 8")
    assert(cell >= 4 and cell % 4 == 0, "Map.CellSize debe ser múltiplo de 4")
    seed = math.floor(tonumber(seed) or 1) % 2147483647
    local rng, half = Random.new(seed), size / 2
    local detailRng = Random.new((seed + 104729) % 2147483647)
    local detailParts = 0
    local old = Workspace:FindFirstChild("GeneratedWorld")
    if old then old:Destroy() end
    local terrain = Workspace.Terrain
    local bottom, ceiling = -32, math.max(128, base + amplitude + 70)
    terrain:FillBlock(C(0, (bottom + ceiling) / 2, 0), V(size, ceiling - bottom, size), Enum.Material.Air)
    local root = model("GeneratedWorld", Workspace, "ProceduralWorld")
    root:SetAttribute("Seed", seed)
    root:SetAttribute("ArtStyle", "Bosque lunar · geometría original")
    local world = { root = root, spawnPoints = {}, statues = {}, chests = {}, sites = {} }
    local catalog = {
        { "Cabaña del guardabosques", "Cabin" }, { "Cueva del eco", "Cave" },
        { "Casa del árbol", "Treehouse" }, { "Ruinas de la luna", "Ruins" },
        { "Refugio olvidado", "Cabin" }, { "Gruta de las sombras", "Cave" },
        { "Santuario del bosque", "Ruins" }, { "Cabaña de los viajeros", "Cabin" },
    }
    for i = #catalog, 2, -1 do
        local j = rng:NextInteger(1, i)
        catalog[i], catalog[j] = catalog[j], catalog[i]
    end
    local count = math.clamp(math.floor(cfg.SiteCount or 8), 4, 8)
    local rotation = rng:NextNumber(0, math.pi * 2)
    for i = 1, count do
        local angle = rotation + (i - 1 + rng:NextNumber(-0.1, 0.1)) * math.pi * 2 / count
        local radius = rng:NextNumber(size * 0.30, size * 0.34)
        local x, z = math.cos(angle) * radius, math.sin(angle) * radius
        table.insert(world.sites, {
            name = catalog[i][1], kind = catalog[i][2], x = x, z = z,
            elevation = catalog[i][2] == "Treehouse" and 12 or 0,
        })
    end
    local function pathDistance(x, z, site)
        local lengthSquared = site.x * site.x + site.z * site.z
        local t = math.clamp((x * site.x + z * site.z) / lengthSquared, 0, 1)
        return math.sqrt((x - site.x * t) ^ 2 + (z - site.z * t) ^ 2), t
    end
    local function distances(x, z)
        local reserve = math.sqrt(x * x + z * z) - 46
        local nearestPath = math.huge
        for _, site in ipairs(world.sites) do
            local distance = pathDistance(x, z, site)
            nearestPath = math.min(nearestPath, distance)
            local siteDistance = math.sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2)
            reserve = math.min(reserve, distance - 12 - cell * 0.65, siteDistance - 25)
        end
        return reserve, nearestPath
    end
    local noiseOffset = (seed % 100000) / 971
    for ix = 0, math.ceil(size / cell) - 1 do
        local width = math.min(cell, size - ix * cell)
        local x = -half + ix * cell + width / 2
        for iz = 0, math.ceil(size / cell) - 1 do
            local depth = math.min(cell, size - iz * cell)
            local z = -half + iz * cell + depth / 2
            local reserve, route = distances(x, z)
            local raw = base + math.max(0, math.noise(x / 85, z / 85, noiseOffset) + 0.3) * amplitude
            local blend = math.clamp(reserve / 14, 0, 1)
            local height = base + (raw - base) * blend
            local material = route < 10 + cell * 0.35 and Enum.Material.Ground or Enum.Material.Grass
            terrain:FillBlock(C(x, (bottom + height) / 2, z), V(width, height - bottom, depth), material)
        end
        task.wait()
    end
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Include
    rayParams.FilterDescendantsInstances = { terrain }
    local function groundY(x, z)
        local hit = Workspace:Raycast(V(x, ceiling - 1, z), V(0, bottom - ceiling, 0), rayParams)
        return hit and hit.Position.Y or base
    end
    local function detailPart(name, dimensions, frame, color, material, parent, className)
        detailParts += 1
        return part(name, dimensions, frame, color, material, parent, className)
    end
    local function decoration(p)
        p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
        return p
    end
    local function sign(frame, parent, title, caption, accent, routeMarker)
        local m = model("Cartel", nil, "Sign")
        local post = detailPart("PosteCartel", V(0.6, 3.8, 0.6), frame * C(0, 1.9, 0.5), palette.trim, Enum.Material.Wood, m)
        local board = detailPart("Tablero", V(7.2, 2.3, 0.4), frame * C(0, 3.7, 0), palette.trim, Enum.Material.WoodPlanks, m)
        if routeMarker then
            decoration(post); decoration(board)
            post.CastShadow, board.CastShadow = false, false
            m:SetAttribute("RouteMarker", true)
        end
        local gui = Instance.new("SurfaceGui")
        gui.Face, gui.CanvasSize, gui.LightInfluence = Enum.NormalId.Front, Vector2.new(480, 180), 0
        gui.MaxDistance = 160
        local panel = Instance.new("Frame")
        panel.Size, panel.BackgroundColor3 = UDim2.fromScale(1, 1), Color3.fromRGB(27, 37, 33)
        panel.BackgroundTransparency, panel.BorderSizePixel, panel.Parent = 0.12, 0, gui
        local stripe = Instance.new("Frame")
        stripe.Size, stripe.Position = UDim2.new(1, -24, 0, 4), UDim2.fromOffset(12, 10)
        stripe.BackgroundColor3, stripe.BorderSizePixel, stripe.Parent = accent or palette.gold, 0, panel
        local text = Instance.new("TextLabel")
        text.Size, text.Position, text.BackgroundTransparency = UDim2.new(1, -28, 0, 76), UDim2.fromOffset(14, 17), 1
        text.Text, text.TextWrapped = title, true
        text.TextColor3, text.Font, text.TextSize = accent or palette.gold, Enum.Font.GothamBold, 27
        text.Parent = panel
        local description = Instance.new("TextLabel")
        description.Size, description.Position, description.BackgroundTransparency = UDim2.new(1, -28, 0, 66), UDim2.fromOffset(14, 99), 1
        description.Text, description.TextWrapped = caption, true
        description.TextColor3, description.Font, description.TextSize = palette.paper, Enum.Font.Gotham, 24
        description.Parent, gui.Parent = panel, board
        m.PrimaryPart = board
        m.Parent = parent
        return m
    end
    local function grass(frame, parent, count, random, scale)
        random, scale = random or detailRng, scale or 1
        for i = 1, count do
            local height = random:NextNumber(0.8, 1.8) * scale
            local offset = C(random:NextNumber(-1.2, 1.2) * scale, height / 2, random:NextNumber(-1.2, 1.2) * scale)
                * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), random:NextNumber(-0.15, 0.15))
            decoration(detailPart("Hierba", V(0.35 * scale, height, 0.6 * scale), frame * offset,
                Color3.fromRGB(73, 120, 66), Enum.Material.Grass, parent, "WedgePart"))
        end
    end
    local function npc(interactionName, title, caption, frame, coat)
        local m = model(interactionName == "Guia" and "NPC_GuardianElfico" or "NPC_Mercader", nil, "ElfNPC")
        m:SetAttribute("NPCType", interactionName == "Guia" and "Guide" or "Shop")
        m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
        local skin = Color3.fromRGB(214, 170, 127)
        local attachments = {}
        local function body(name, dimensions, offset, color, material, className, host)
            local p = decoration(detailPart(name, dimensions, frame * offset, color, material, m, className))
            p.Anchored, p.Massless = false, true
            if host then table.insert(attachments, { part = p, host = host }) end
            return p
        end
        local rootPart = body("HumanoidRootPart", V(2, 2, 1), C(0, 3.4, 0), coat)
        rootPart.Anchored = true
        rootPart.Transparency, rootPart.CastShadow, m.PrimaryPart = 1, false, rootPart
        local torso = body("Torso", V(2, 2.2, 1), C(0, 3.4, 0), coat, Enum.Material.Fabric)
        local head = body("Head", V(1.6, 1.6, 1.4), C(0, 5.3, 0), skin)
        local function motor(name, host, member, pivot)
            local joint = Instance.new("Motor6D")
            joint.Name, joint.Part0, joint.Part1 = name, host, member
            joint.C0, joint.C1 = host.CFrame:ToObjectSpace(pivot), member.CFrame:ToObjectSpace(pivot)
            joint.Parent = host
        end
        motor("RootJoint", rootPart, torso, rootPart.CFrame)
        motor("Neck", torso, head, frame * C(0, 4.5, 0))
        for _, side in ipairs({ -1, 1 }) do
            local sideName = side == -1 and "Left" or "Right"
            local arm = body(sideName .. " Arm", V(0.65, 2.1, 0.85), C(side * 1.3, 3.5, 0), coat, Enum.Material.Fabric)
            local leg = body(sideName .. " Leg", V(0.8, 2.3, 0.85), C(side * 0.55, 1.15, 0), Color3.fromRGB(68, 65, 58), Enum.Material.Fabric)
            motor(sideName .. "Shoulder", torso, arm, frame * C(side * 1.3, 4.3, 0))
            motor(sideName .. "Hip", torso, leg, frame * C(side * 0.55, 2.3, 0))
            body("Mano", V(0.65, 0.45, 0.75), C(side * 1.3, 2.35, 0), skin, nil, nil, arm)
            body("Bota", V(0.9, 0.45, 1.2), C(side * 0.55, 0.225, -0.15), palette.wood, nil, nil, leg)
            body("OrejaElfica", V(0.55, 0.7, 0.35), C(side * 1, 5.35, 0)
                * CFrame.Angles(0, 0, side * 0.25), skin, nil, "WedgePart", head)
            body("Ojo", V(0.16, 0.16, 0.08), C(side * 0.35, 5.5, -0.715), Color3.fromRGB(27, 37, 32), nil, nil, head)
        end
        body("Cabello", V(1.8, 0.3, 1.55), C(0, 6.08, 0.04), Color3.fromRGB(193, 190, 164), nil, nil, head)
        body("Cinturon", V(2.08, 0.25, 1.1), C(0, 2.85, 0), palette.wood, nil, nil, torso)
        body("Hebilla", V(0.4, 0.3, 0.1), C(0, 2.85, -0.6), palette.gold, Enum.Material.Metal, nil, torso)
        body("Capa", V(2.2, 2.4, 0.2), C(0, 3.35, 0.56), coat, Enum.Material.Fabric, nil, torso)
        body("Sombrero", V(2, 0.5, 1.8), C(0, 6.35, 0), coat, Enum.Material.Fabric, nil, head)
        if interactionName == "Guia" then
            body("Capucha", V(1.5, 0.9, 1.4), C(0, 6.85, 0), coat, Enum.Material.Fabric, "WedgePart", head)
            m:SetAttribute("QuestTarget", 2)
        else
            body("Bolso", V(0.9, 1.1, 0.6), C(1.2, 2.95, 0.65), palette.wood, Enum.Material.Fabric, nil, torso)
            body("Barba", V(1.1, 0.65, 0.45), C(0, 4.9, -0.73), Color3.fromRGB(221, 217, 196), nil, nil, head)
        end
        for _, attachment in ipairs(attachments) do
            local weld = Instance.new("WeldConstraint")
            weld.Part0, weld.Part1, weld.Parent = attachment.host, attachment.part, attachment.part
        end
        local hum = Instance.new("Humanoid")
        hum.DisplayName, hum.DisplayDistanceType = title, Enum.HumanoidDisplayDistanceType.None
        hum.RequiresNeck, hum.AutoRotate, hum.BreakJointsOnDeath = false, false, false
        hum.WalkSpeed, hum.JumpPower, hum.EvaluateStateMachine = 0, 0, false
        hum.Parent = m
        local interaction = detailPart(interactionName, V(2.2, 5.8, 1.6), frame * C(0, 2.9, 0), coat, nil, m)
        decoration(interaction)
        interaction.Anchored, interaction.Massless = false, true
        interaction.Transparency, interaction.CastShadow = 1, false
        local interactionWeld = Instance.new("WeldConstraint")
        interactionWeld.Part0, interactionWeld.Part1, interactionWeld.Parent = rootPart, interaction, interaction
        m:SetAttribute("HomeCFrame", rootPart.CFrame)
        m:SetAttribute("NPCState", "Idle")
        m:SetAttribute("InteractingUserId", 0)
        CollectionService:AddTag(m, "HombreLoboNPC")
        billboard(head, title, caption)
        m.Parent = root
        return interaction
    end
    local function lantern(x, z, orientation)
        local y = groundY(x, z)
        local frame = C(x, y, z) * (orientation or CFrame.new())
        local m = model("Farol", nil, "Lantern")
        local post = detailPart("Poste", V(0.8, 7, 0.8), frame * C(0, 3.5, 0), palette.wood, Enum.Material.Wood, m)
        m.PrimaryPart = post
        m:SetAttribute("BaseY", y)
        detailPart("Brazo", V(2.5, 0.35, 0.35), frame * C(-1.2, 6.5, 0), palette.wood, Enum.Material.Wood, m)
        decoration(detailPart("BaseLinterna", V(1.5, 0.25, 1.5), frame * C(-2.2, 5.1, 0), palette.stone, Enum.Material.Metal, m))
        decoration(detailPart("TechoLinterna", V(1.6, 0.3, 1.6), frame * C(-2.2, 6.45, 0), palette.stone, Enum.Material.Metal, m))
        for _, xSide in ipairs({ -1, 1 }) do
            for _, zSide in ipairs({ -1, 1 }) do
                decoration(detailPart("MarcoLinterna", V(0.12, 1.25, 0.12),
                    frame * C(-2.2 + xSide * 0.6, 5.8, zSide * 0.6), palette.stone, Enum.Material.Metal, m))
            end
        end
        local glass = decoration(detailPart("Cristal", V(1.12, 1.2, 1.12), frame * C(-2.2, 5.8, 0),
            Color3.fromRGB(255, 216, 131), Enum.Material.Glass, m))
        glass.Transparency = 0.45
        local bulb = decoration(detailPart("Luz", V(0.35, 0.8, 0.35), frame * C(-2.2, 5.8, 0),
            palette.gold, Enum.Material.Neon, m))
        light(bulb, palette.gold, 23)
        m.Parent = root
    end
    local function buildSite(site)
        local y = groundY(site.x, site.z)
        site.position = V(site.x, y, site.z)
        site.frame = CFrame.lookAt(site.position, V(0, y, 0))
        local m = model(site.name, nil, site.kind)
        site.model = m
        local accent = landmarkColors[site.kind] or palette.gold
        m:SetAttribute("LandmarkKind", site.kind)
        m:SetAttribute("LandmarkColor", accent)
        local frame = site.frame * C(0, site.elevation, 0)
        local function p(name, dimensions, offset, color, material)
            return part(name, dimensions, frame * offset, color, material, m)
        end
        local timberFloor = site.kind == "Cabin" or site.kind == "Treehouse"
        p("Suelo", V(20, 1, 18), C(0, 0.5, 0), timberFloor and palette.wood or palette.stone,
            timberFloor and Enum.Material.WoodPlanks or Enum.Material.Slate)
        if site.kind == "Cave" then
            p("RocaIzquierda", V(6, 12, 22), C(-11, 6, 0), palette.stone, Enum.Material.Rock)
            p("RocaDerecha", V(6, 12, 22), C(11, 6, 0), palette.stone, Enum.Material.Rock)
            p("FondoCueva", V(28, 12, 5), C(0, 6, 10), palette.stone, Enum.Material.Rock)
            p("TechoCueva", V(28, 4, 25), C(0, 13, 0), palette.stone, Enum.Material.Rock)
            p("EntradaIzquierda", V(6, 12, 4), C(-9, 6, -10), palette.stone, Enum.Material.Rock)
            p("EntradaDerecha", V(6, 12, 4), C(9, 6, -10), palette.stone, Enum.Material.Rock)
        elseif site.kind == "Ruins" then
            for _, x in ipairs({ -8, 8 }) do
                for _, z in ipairs({ -7, 7 }) do
                    local height = rng:NextNumber(5, 8)
                    if z == 7 then height = math.max(height, 6) end
                    p("Columna", V(2.5, height, 2.5), C(x, 1 + height / 2, z), palette.stone, Enum.Material.Slate)
                end
            end
            p("Arco", V(19, 2, 2.5), C(0, 8, 7), palette.stone, Enum.Material.Slate)
        else
            p("ParedIzquierda", V(1, 10, 18), C(-10, 6, 0), palette.wood, Enum.Material.WoodPlanks)
            p("ParedDerecha", V(1, 10, 18), C(10, 6, 0), palette.wood, Enum.Material.WoodPlanks)
            p("ParedTrasera", V(20, 10, 1), C(0, 6, 9), palette.wood, Enum.Material.WoodPlanks)
            for _, x in ipairs({ -7, 7 }) do
                p("Frente", V(6, 10, 1), C(x, 6, -9), palette.wood, Enum.Material.WoodPlanks)
            end
            p("Dintel", V(20, 2, 1), C(0, 10, -9), palette.wood, Enum.Material.WoodPlanks)
            for _, side in ipairs({ -1, 1 }) do
                local roof = site.kind == "Treehouse" and Color3.fromRGB(55, 91, 64) or Color3.fromRGB(55, 73, 72)
                p("Tejado", V(12.8, 1, 22), C(side * 6, 12, 0) * CFrame.Angles(0, 0, -side * 0.35), roof, Enum.Material.Slate)
            end
        end
        local accessFrame, accessLength
        if site.kind == "Treehouse" then
            part("TroncoSoporte", V(4, 12, 4), site.frame * C(-6, 6, 2), palette.wood, Enum.Material.Wood, m)
            -- Una superficie continua permite navegar hasta la plataforma sin saltar peldaños.
            local foot = site.frame:PointToWorldSpace(V(0, 0, -44))
            local start = V(foot.X, groundY(foot.X, foot.Z) + 0.12, foot.Z)
            local finish = site.frame:PointToWorldSpace(V(0, 13, -8.75))
            accessLength = (finish - start).Magnitude
            accessFrame = CFrame.lookAt((start + finish) / 2, finish)
            part("Pasarela", V(10, 0.45, accessLength), accessFrame * C(0, -0.225, 0),
                palette.wood, Enum.Material.WoodPlanks, m)
            for i = 1, 18 do
                local offset = accessLength / 2 - (i - 0.5) * accessLength / 18
                decoration(part("Escalon", V(9.8, 0.025, accessLength / 18 - 0.015),
                    accessFrame * C(0, 0.0125, offset), i % 2 == 0 and palette.wood or Color3.fromRGB(119, 82, 51),
                    Enum.Material.WoodPlanks, m))
            end
            m:SetAttribute("AccessStart", start)
            m:SetAttribute("AccessEnd", finish)
            m:SetAttribute("AccessWidth", 10)
            m:SetAttribute("AccessKind", "Ramp")
        end
        local lampOffset = site.kind == "Ruins" and C(-8, 5, 5.3) or C(0, 8, 7)
        decoration(detailPart("SoporteLuz", V(0.25, 0.25, 2), frame * lampOffset * C(0, -0.39, 0.9),
            palette.stone, Enum.Material.Metal, m))
        decoration(detailPart("BaseLuz", V(0.9, 0.18, 0.9), frame * lampOffset * C(0, -0.39, 0),
            palette.stone, Enum.Material.Metal, m))
        decoration(detailPart("TechoLuz", V(0.9, 0.16, 0.9), frame * lampOffset * C(0, 0.38, 0),
            palette.stone, Enum.Material.Metal, m))
        local lamp = decoration(p("LuzInterior", V(0.6, 0.6, 0.6), lampOffset, palette.gold, Enum.Material.Neon))
        light(lamp, palette.gold, 20)
        sign(site.frame * C(14, 0, -15), m, site.name,
            site.kind == "Treehouse" and "Subí por la pasarela · buscá el cofre" or "Cofres y misterios del bosque", accent)
        if site.kind == "Cabin" or site.kind == "Treehouse" then
            for _, side in ipairs({ -1, 1 }) do
                local window = p("Ventana", V(0.12, 3.1, 4.2), C(side * 10.56, 6, -1), Color3.fromRGB(94, 157, 167), Enum.Material.Glass)
                window.Transparency = 0.3
                window.CanCollide, window.CanTouch, window.CanQuery = false, false, false
                p("MarcoVentana", V(0.2, 0.25, 4.7), C(side * 10.65, 7.7, -1), palette.trim, Enum.Material.Wood)
                p("MarcoVentana", V(0.2, 0.25, 4.7), C(side * 10.65, 4.3, -1), palette.trim, Enum.Material.Wood)
                p("MarcoVentana", V(0.2, 3.5, 0.2), C(side * 10.65, 6, -1), palette.trim, Enum.Material.Wood)
            end
            p("Chimenea", V(2.3, 7, 2.3), C(6, 12, 5), palette.stone, Enum.Material.Brick)
            p("Mesa", V(3.2, 0.6, 2), C(5.5, 3, -4), palette.wood, Enum.Material.WoodPlanks)
            p("PataMesa", V(0.5, 2.5, 0.5), C(5.5, 1.75, -4), palette.wood, Enum.Material.Wood)
            local banner = p("Estandarte", V(0.2, 4.5, 2), C(-10.6, 8, 5), accent, Enum.Material.Fabric)
            banner.CanCollide, banner.CanTouch, banner.CanQuery = false, false, false
        elseif site.kind == "Cave" then
            for i = 1, 6 do
                local side = i % 2 == 0 and 1 or -1
                p("RocaIrregular", V(3.5, 4 + (i % 3), 3), C(side * 12, 2, -8 + i * 2.8) * CFrame.Angles(0.2, i, side * 0.18), palette.stone, Enum.Material.Rock)
            end
            for _, side in ipairs({ -1, 1 }) do
                local crystal = p("Cristal", V(0.7, 2.4, 0.7), C(side * 6.7, 2.2, 6.3) * CFrame.Angles(0, 0, side * 0.25), accent, Enum.Material.Neon)
                crystal.CanCollide, crystal.CanTouch, crystal.CanQuery = false, false, false
            end
        else
            for _, side in ipairs({ -1, 1 }) do grass(site.frame * C(side * 9, 1, -6), m, 5) end
        end
        if accessFrame then
            for _, side in ipairs({ -1, 1 }) do
                for i = 3, 18, 3 do
                    local offset = accessLength / 2 - (i - 0.5) * accessLength / 18
                    part("BarandaEscalera", V(0.3, 2.5, 0.3), accessFrame * C(side * 4.75, 1.20, offset),
                        palette.wood, Enum.Material.Wood, m)
                end
                part("Pasamanos", V(0.25, 0.25, accessLength), accessFrame * C(side * 4.75, 2.45, 0),
                    palette.wood, Enum.Material.Wood, m)
            end
        end
        for t = 0.4, 0.8, 0.4 do
            local position = site.frame:PointToWorldSpace(V(12, 0, math.sqrt(site.x ^ 2 + site.z ^ 2) * (t - 1)))
            lantern(position.X, position.Z, site.frame.Rotation)
        end
        m.Parent = root
    end
    local function statue(site)
        local m = model("EstatuaLobo", nil, "WolfStatue")
        m:SetAttribute("Destroyed", false)
        m:SetAttribute("SiteName", site.name)
        -- Deja un pasillo de 4.35 studs entre el cofre y el pedestal (AgentRadius = 2).
        local frame = site.frame * C(5, site.elevation + 1, 1)
        local function p(name, dimensions, offset, material, color, className)
            return part(name, dimensions, frame * offset, color or palette.stone, material or Enum.Material.Slate, m, className)
        end
        local function carved(name, dimensions, offset)
            local sculpture = p(name, dimensions, offset)
            -- SpecialMesh redondea sólo la presentación: la caja física original no cambia.
            local mesh = Instance.new("SpecialMesh")
            mesh.MeshType, mesh.Parent = Enum.MeshType.Sphere, sculpture
            return sculpture
        end
        m.PrimaryPart = p("Pedestal", V(6, 1, 6), C(0, 0.5, 0))
        carved("Cuerpo", V(4.5, 2, 2), C(0, 3.6, 0))
        carved("Cabeza", V(2.2, 2, 2), C(0, 4.7, -1.8))
        carved("Hocico", V(1.5, 0.8, 1.5), C(0, 4.2, -3))
        for _, side in ipairs({ -1, 1 }) do
            p("Oreja", V(0.8, 1.5, 1.2), C(side * 0.7, 6, -1.6), nil, nil, "WedgePart")
            local eye = p("Ojo", V(0.35, 0.35, 0.2), C(side * 0.65, 4.9, -2.83), Enum.Material.Neon, Color3.fromRGB(255, 74, 93))
            eye.CanCollide = false
            for _, z in ipairs({ -0.7, 0.7 }) do carved("Pata", V(0.7, 2.5, 0.7), C(side * 1.3, 2, z)) end
        end
        carved("Cola", V(0.7, 0.7, 2), C(0, 3.8, 1.7) * CFrame.Angles(-0.4, 0, 0))
        prompt(m.PrimaryPart, "Purificar", "Estatua del lobo", 1.5)
        m.Parent = root
        table.insert(world.statues, m)
    end
    local function chest(site)
        local m = model("Cofre", nil, "Chest")
        m:SetAttribute("Looted", false)
        m:SetAttribute("SiteName", site.name)
        local frame = site.frame * C(-4, site.elevation + 1, 1)
        m.PrimaryPart = part("Caja", V(3, 2, 2.4), frame * C(0, 1, 0), palette.wood, Enum.Material.WoodPlanks, m)
        part("Tapa", V(3.3, 0.5, 2.7), frame * C(0, 2.2, 0), palette.wood, Enum.Material.WoodPlanks, m)
        part("Cerradura", V(0.5, 0.7, 0.2), frame * C(0, 1.5, -1.3), palette.gold, Enum.Material.Metal, m)
        for _, side in ipairs({ -1, 1 }) do
            local band = decoration(detailPart("AroCofre", V(0.18, 2.54, 2.80),
                frame * C(side * 0.95, 1.20, 0), palette.iron, Enum.Material.Metal, m))
            band.CastShadow = false
        end
        prompt(m.PrimaryPart, "Buscar suministros", "Cofre", 0.7)
        m.Parent = root
        table.insert(world.chests, m)
    end
    for _, site in ipairs(world.sites) do buildSite(site); chest(site); task.wait() end
    -- Orientación estática; no agrega física, luces ni mantenimiento por frame.
    local plaza = model("PlazaDeLaLuna", nil, "Wayfinding")
    local plazaY = groundY(0, 0)
    local disk = decoration(detailPart("SueloPlaza", V(0.08, 24, 24),
        C(0, plazaY - 0.01, 0) * CFrame.Angles(0, 0, math.pi / 2),
        Color3.fromRGB(115, 114, 103), Enum.Material.Cobblestone, plaza))
    disk.Shape, disk.CastShadow = Enum.PartType.Cylinder, false
    for _, site in ipairs(world.sites) do
        local direction = V(site.x, 0, site.z).Unit
        local spoke = decoration(detailPart("RutaPlaza", V(0.85, 0.06, 7.5),
            CFrame.lookAt(direction * 7.8 + V(0, plazaY + 0.04, 0), direction * 14 + V(0, plazaY + 0.04, 0)),
            landmarkColors[site.kind], Enum.Material.Slate, plaza))
        spoke.CastShadow = false
        local length = math.sqrt(site.x ^ 2 + site.z ^ 2)
        local routePosition = site.frame:PointToWorldSpace(V(11, 0, 36 - length))
        local routeFrame = C(routePosition.X, groundY(routePosition.X, routePosition.Z), routePosition.Z) * site.frame.Rotation
        local marker = sign(routeFrame, root, site.name, "Seguí este sendero desde la aldea", landmarkColors[site.kind], true)
        marker:SetAttribute("Destination", site.name)
    end
    plaza.Parent = root
    local order = table.clone(world.sites)
    for i = #order, 2, -1 do local j = rng:NextInteger(1, i); order[i], order[j] = order[j], order[i] end
    for i = 1, math.clamp(math.floor(cfg.StatueCount or 5), 1, #order) do statue(order[i]) end
    local templates = ServerStorage:FindFirstChild("AssetTemplates")
    local treeTemplate = templates and templates:FindFirstChild("Tree")
    local treeDetail = cfg.TreeDetail or "Simple"
    assert(treeDetail == "Simple" or treeDetail == "Detailed", "Map.TreeDetail debe ser Simple o Detailed")
    root:SetAttribute("TreeDetail", treeDetail)
    local treeSource, sourceScale, sourceBounds, simpleTemplate
    if treeTemplate and treeTemplate:IsA("Model") then
        -- El OBJ tiene su base en (0,0,0). Medir una vez conserva el mismo escalado en ambos modos.
        treeTemplate.WorldPivot = CFrame.new()
        local boundsFrame, bounds = treeTemplate:GetBoundingBox()
        sourceBounds = bounds
        if treeDetail == "Simple" then
            simpleTemplate = model("ArbolCC0", nil, "Tree")
            simpleTemplate.WorldPivot = CFrame.new()
            local lowerY = boundsFrame.Position.Y - bounds.Y / 2
            local stemHeight = bounds.Y * 0.5 - lowerY
            local stem = decoration(part("woodBarkDark", V(2, stemHeight, 2),
                C(0, lowerY + stemHeight / 2, 0), palette.wood, Enum.Material.Wood, simpleTemplate))
            stem.CastShadow = false
            local tiers = {
                { width = 1, height = 0.38, top = 0.70 },
                { width = 0.78, height = 0.34, top = 0.86 },
                { width = 0.55, height = 0.30, top = 1 },
            }
            for _, tier in ipairs(tiers) do
                local width, depth, height = bounds.X * tier.width, bounds.Z * tier.width, bounds.Y * tier.height
                local y = lowerY + bounds.Y * tier.top - height / 2
                for _, side in ipairs({ -1, 1 }) do
                    local leaves = decoration(part("leafsDark", V(width, height, depth / 2),
                        C(boundsFrame.Position.X, y, boundsFrame.Position.Z + side * depth / 4)
                            * CFrame.Angles(0, side == 1 and 0 or math.pi, 0),
                        palette.leaf, Enum.Material.SmoothPlastic, simpleTemplate, "WedgePart"))
                    leaves.CastShadow = false
                end
            end
            treeSource = simpleTemplate
        else
            treeSource = treeTemplate
        end
        sourceScale = treeSource:GetScale()
    end
    local treePositions, treeTarget = {}, math.max(0, math.floor(cfg.TreeCount or 110))
    local function tree(x, z)
        local y, yaw = groundY(x, z), rng:NextNumber(0, math.pi * 2)
        if treeSource then
            -- El mismo valor aleatorio fija tamaño y colisión; el detalle visual no cambia el mapa.
            local relativeScale = rng:NextNumber(16, 24) / math.max(sourceBounds.Y, 0.1)
            local m = treeSource:Clone()
            m.Name = "ArbolCC0"
            m:SetAttribute("AssetTemplateKey", "Tree")
            m:SetAttribute("TreeDetail", treeDetail)
            if treeDetail == "Detailed" then
                for _, child in ipairs(m:GetDescendants()) do
                    if child:IsA("BasePart") then
                        child.Anchored, child.CanCollide, child.CanTouch, child.CanQuery = true, false, false, false
                        if child.Name == "leafsDark" then child.CastShadow = false end
                    elseif child:IsA("LuaSourceContainer") then child:Destroy() end
                end
            end
            m:ScaleTo(sourceScale * relativeScale)
            m:PivotTo(C(x, y, z) * CFrame.Angles(0, yaw, 0))
            local height = sourceBounds.Y * relativeScale
            local trunk = part("ColisionTronco", V(2, height * 0.5, 2), C(x, y + height * 0.25, z), palette.wood, Enum.Material.Wood, m)
            trunk.Transparency, trunk.CastShadow = 1, false
            -- Publicar cada árbol completo evita replicar el escalado y movimiento de sus piezas.
            m.Parent = root
        else
            local m = model("ArbolOriginal", nil, "Tree")
            local height = rng:NextNumber(10, 15)
            local frame = C(x, y, z) * CFrame.Angles(0, yaw, 0)
            part("Tronco", V(2.5, height, 2.5), frame * C(0, height / 2, 0), palette.wood, Enum.Material.Wood, m)
            for level = 1, 3 do
                local width = 13 - level * 2
                for _, side in ipairs({ -1, 1 }) do
                    local leaves = decoration(part("Copa", V(width, 5, width / 2), frame * C(0, height - 4 + level * 3, side * width / 4) * CFrame.Angles(0, side == 1 and 0 or math.pi, 0), palette.leaf, Enum.Material.SmoothPlastic, m, "WedgePart"))
                    leaves.CastShadow = false
                end
            end
            m.Parent = root
        end
    end
    for attempt = 1, treeTarget * 35 do
        if #treePositions >= treeTarget then break end
        local x, z = rng:NextNumber(-half + 16, half - 16), rng:NextNumber(-half + 16, half - 16)
        local reserve, route = distances(x, z)
        local free = reserve > 10 and route > 25 and x * x + z * z > 48 ^ 2
        for _, site in ipairs(world.sites) do if (x - site.x) ^ 2 + (z - site.z) ^ 2 < 38 ^ 2 then free = false; break end end
        for _, position in ipairs(treePositions) do if (V(x, 0, z) - position).Magnitude < 13 then free = false; break end end
        if free then table.insert(treePositions, V(x, 0, z)); tree(x, z); if #treePositions % 5 == 0 then task.wait() end end
        if attempt % 80 == 0 then task.wait() end
    end
    if simpleTemplate then simpleTemplate:Destroy() end
    for _ = 1, 35 do
        local x, z = rng:NextNumber(-half + 12, half - 12), rng:NextNumber(-half + 12, half - 12)
        local reserve = distances(x, z)
        if reserve > 12 then
            local h = rng:NextNumber(2, 5)
            part("Roca", V(h * 1.7, h, h), C(x, groundY(x, z) + h / 2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), palette.stone, Enum.Material.Rock, root, "WedgePart")
        end
    end
    for _, side in ipairs({ -1, 1 }) do
        buildSite({ name = side == -1 and "Casa del guardián" or "Casa del mercader", kind = "Cabin", x = side * 24, z = -20, elevation = 0 })
    end
    local guideY = groundY(-14, -12)
    world.guide = npc("Guia", "Elar · Guardián del bosque", "MISIÓN: abrí 2 cofres y volvé.\nRecompensa: ubicación de una estatua.", CFrame.lookAt(V(-14, guideY, -12), V(0, guideY, 0)), palette.leaf)
    prompt(world.guide, "Consultar misión", "Elar · Guardián")
    local shopY = groundY(14, -12)
    world.shop = npc("Tienda", "Borin · Mercader", "Pociones, botas y habilidades\nLas compras duran esta ronda.", CFrame.lookAt(V(14, shopY, -12), V(0, shopY, 0)), Color3.fromRGB(120, 79, 63))
    prompt(world.shop, "Ver suministros", "Borin · Mercader")
    sign(C(0, groundY(0, -27), -27), root, "ALDEA DE LOS ELFOS", "Elar: misiones  ·  Borin: mercado")
    for _, side in ipairs({ -1, 1 }) do lantern(side * 38, -8, CFrame.Angles(0, side * math.pi / 2, 0)) end
    -- Small, visible clumps around the plaza make the personal grass setting
    -- useful before visiting distant ruins. Independent RNG preserves every
    -- gameplay placement, objective, tree and spawn for an existing seed.
    local villageGrassRng = Random.new((seed + 15485863) % 2147483647)
    local villageGrass = model("PastoDeLaAldea", nil, "VillageGrass")
    for index = 1, 8 do
        local angle = (index - 1) * math.pi / 4
        local x, z = math.cos(angle) * 19, math.sin(angle) * 19
        grass(C(x, groundY(x, z), z), villageGrass, 10, villageGrassRng, 1.6)
    end
    villageGrass.Parent = root
    root:SetAttribute("VillageGrassBlades", 80)
    root:SetAttribute("DecorativeParts", detailParts)
    for i = 1, 12 do
        local angle = i * math.pi * 2 / 12
        local x, z = math.cos(angle) * 10, math.sin(angle) * 10
        table.insert(world.spawnPoints, V(x, groundY(x, z) + 4, z))
    end
    local wolf = world.sites[1].frame:PointToWorldSpace(V(-12, 0, -22))
    world.wolfSpawn = V(wolf.X, groundY(wolf.X, wolf.Z) + 4, wolf.Z)
    for _, side in ipairs({ -1, 1 }) do
        local wallX = part("Limite", V(2, 90, size), C(side * (half - 1), 30, 0), palette.stone, nil, nil)
        local wallZ = part("Limite", V(size, 90, 2), C(0, 30, side * (half - 1)), palette.stone, nil, nil)
        wallX.Transparency, wallZ.Transparency = 1, 1
        wallX.CastShadow, wallZ.CastShadow = false, false
        wallX.Parent, wallZ.Parent = root, root
    end
    return world
end
return WorldGenerator
