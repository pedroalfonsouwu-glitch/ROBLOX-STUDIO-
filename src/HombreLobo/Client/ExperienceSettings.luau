-- Personal preferences live only on this client, for this game session.
-- No engine quality override, collision change, server request or frame loop.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ExperienceSettings = {}
local changed = Instance.new("BindableEvent")
ExperienceSettings.changed = changed.Event

local defaults = {
    Quality = "Normal", DecorDensity = 50, Grass = true, TreeDetail = "Completo",
    SignDistance = 160, Shadows = true, FXDensity = 100, PanelOpacity = 88,
    Brightness = 0, ControlSide = "Auto", OffsetX = 0, OffsetY = 0,
    ActionOrder = "Normal", PanelWidth = 440,
}
local choices = {
    Quality = {"Baja", "Normal", "Alta", "Personalizada"},
    DecorDensity = {0, 25, 50, 75, 100}, Grass = {false, true},
    TreeDetail = {"Reducido", "Completo"}, SignDistance = {0, 80, 160, 240},
    Shadows = {false, true}, FXDensity = {0, 50, 100},
    PanelOpacity = {40, 60, 75, 88, 100}, Brightness = {-0.2, -0.1, 0, 0.1, 0.2, 0.3},
    ControlSide = {"Auto", "Izquierda", "Derecha"}, OffsetX = {-120, -80, -40, 0, 40, 80, 120},
    OffsetY = {-80, -40, 0, 40, 80}, ActionOrder = {"Normal", "Combate primero"},
    PanelWidth = {360, 440, 520},
}
local presets = {
    Baja = {DecorDensity = 25, Grass = true, TreeDetail = "Reducido", SignDistance = 80, Shadows = false, FXDensity = 50},
    Normal = {DecorDensity = 50, Grass = true, TreeDetail = "Completo", SignDistance = 160, Shadows = true, FXDensity = 100},
    Alta = {DecorDensity = 100, Grass = true, TreeDetail = "Completo", SignDistance = 240, Shadows = true, FXDensity = 100},
}
local visualKeys = {DecorDensity = true, Grass = true, TreeDetail = true, SignDistance = true, Shadows = true, FXDensity = true}
local values = table.clone(defaults)
local mounted

function ExperienceSettings.get(key)
    return values[key]
end
function ExperienceSettings.snapshot()
    return table.clone(values)
end
function ExperienceSettings.effectsScale()
    return values.FXDensity / 100
end
function ExperienceSettings.set(key, value)
    local allowed = choices[key]
    if not allowed or not table.find(allowed, value) then return false end
    if values[key] == value then return true end
    values[key] = value
    if key == "Quality" and presets[value] then
        for presetKey, presetValue in pairs(presets[value]) do values[presetKey] = presetValue end
    elseif visualKeys[key] then
        values.Quality = "Personalizada"
    end
    changed:Fire(ExperienceSettings.snapshot())
    return true
end
function ExperienceSettings.reset()
    values = table.clone(defaults)
    changed:Fire(ExperienceSettings.snapshot())
end

local function disconnectAll(list)
    for _, connection in ipairs(list) do connection:Disconnect() end
    table.clear(list)
end
local function purelyVisual(part)
    return part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch
end
local function protectedAncestor(object, world)
    local cursor = object.Parent
    while cursor and cursor ~= world do
        local kind = cursor:GetAttribute("AssetTemplateKey")
        if kind == "Chest" or kind == "WolfStatue" or cursor:GetAttribute("NPCType")
            or cursor:GetAttribute("AIControlled") or (cursor:IsA("Model") and cursor:FindFirstChildOfClass("Humanoid")) then return true end
        cursor = cursor.Parent
    end
    return false
end
local function templateAncestor(object, world, template)
    local cursor = object.Parent
    while cursor and cursor ~= world do
        if cursor:GetAttribute("NPCType") or cursor:GetAttribute("AIControlled") or cursor:IsA("Humanoid") then return nil end
        local kind = cursor:GetAttribute("AssetTemplateKey")
        if kind == "Chest" or kind == "WolfStatue" then return nil end
        if kind == template then return cursor end
        cursor = cursor.Parent
    end
    return nil
end

function ExperienceSettings.mount(options)
    if mounted then mounted:Destroy() end
    local root, palette = options.root, options.palette
    local controller = {}
    mounted = controller
    local connections, worldConnections = {}, {}
    local records, trees, dirty = {}, {}, {}
    local world, pending, stopped, applyingAll = nil, nil, false, false
    local baseExposure, baseShadows = Lighting.ExposureCompensation, Lighting.GlobalShadows
    local appliedExposure, appliedShadows = baseExposure, baseShadows
    local rows, viewport = {}, Vector2.zero
    local visualSummary = {GrassLoaded = 0, GrassVisible = 0, TreeLeavesLoaded = 0, TreeLeavesVisible = 0}
    local refreshVisualSummary
    local function track(connection)
        table.insert(connections, connection)
        return connection
    end
    local function restore(record)
        local object = record.object
        if not object.Parent then return end
        if record.kind == "Sign" then
            object.Enabled, object.MaxDistance = record.enabled, record.distance
        else object.LocalTransparencyModifier = record.transparency end
    end
    local function treeExtents(group)
        local widest, highest = 0, -math.huge
        for part in pairs(group) do
            if part.Parent then
                widest = math.max(widest, part.Size.X * part.Size.Z)
                highest = math.max(highest, part.Position.Y + part.Size.Y / 2)
            end
        end
        return widest, highest
    end
    local function applyRecord(record, extents)
        local object = record.object
        if not object.Parent then return end
        if record.kind == "Sign" then
            object.Enabled = record.enabled and values.SignDistance > 0
            object.MaxDistance = values.SignDistance > 0 and values.SignDistance or record.distance
        else
            -- A change to collision/query flags immediately disqualifies this decoration.
            if not purelyVisual(object) then object.LocalTransparencyModifier = record.transparency; return end
            local hidden = false
            if record.kind == "Grass" then
                hidden = not values.Grass or record.rank >= values.DecorDensity
            elseif values.TreeDetail == "Reducido" then
                local bounds = extents[record.tree]
                if not bounds then
                    local widest, highest = treeExtents(trees[record.tree])
                    bounds = {widest, highest}
                    extents[record.tree] = bounds
                end
                -- Keep both halves of the broadest and highest crowns, plus every trunk.
                hidden = object.Size.X * object.Size.Z < bounds[1] - 0.01
                    and object.Position.Y + object.Size.Y / 2 < bounds[2] - 0.01
            end
            object.LocalTransparencyModifier = hidden and 1 or record.transparency
        end
    end
    local function flush()
        pending = nil
        if stopped then return end
        local extents = {}
        if applyingAll then
            for _, record in pairs(records) do applyRecord(record, extents) end
        else
            for object in pairs(dirty) do
                local record = records[object]
                if record then applyRecord(record, extents) end
            end
        end
        applyingAll = false
        table.clear(dirty)
        if refreshVisualSummary then refreshVisualSummary() end
    end
    local function queue(all)
        applyingAll = applyingAll or all == true
        if not pending and not stopped then pending = task.delay(0.05, flush) end
    end
    local function addObject(object)
        if records[object] or protectedAncestor(object, world) then return end
        local record
        if object:IsA("BasePart") and purelyVisual(object) then
            if object.Name == "Hierba" then
                -- Only procedural grass is optional clutter; walls, doors, ramps and lamps stay.
                record = {object = object, kind = "Grass", transparency = object.LocalTransparencyModifier,
                    rank = (math.floor(object.Position.X * 10) * 73856093 + math.floor(object.Position.Z * 10) * 19349663) % 100}
            elseif object.Name == "leafsDark" or object.Name == "Copa" then
                local tree = templateAncestor(object, world, "Tree")
                if tree then
                    record = {object = object, kind = "Tree", tree = tree, transparency = object.LocalTransparencyModifier}
                    trees[tree] = trees[tree] or {}
                    trees[tree][object] = true
                    for leaf in pairs(trees[tree]) do dirty[leaf] = true end
                end
            end
        elseif object:IsA("SurfaceGui") and templateAncestor(object, world, "Sign") then
            record = {object = object, kind = "Sign", enabled = object.Enabled, distance = object.MaxDistance}
        end
        if record then records[object], dirty[object] = record, true; queue(false) end
    end
    local function removeObject(object)
        local record = records[object]
        if not record then return end
        restore(record)
        records[object], dirty[object] = nil, nil
        queue(false)
        if record.tree and trees[record.tree] then
            local group = trees[record.tree]
            group[object] = nil
            if next(group) == nil then trees[record.tree] = nil
            else for leaf in pairs(group) do dirty[leaf] = true end; queue(false) end
        end
    end
    local function bindWorld(nextWorld)
        if nextWorld == world then return end
        disconnectAll(worldConnections)
        for _, record in pairs(records) do restore(record) end
        table.clear(records); table.clear(trees); table.clear(dirty)
        world = nextWorld
        if not world then queue(false); return end
        table.insert(worldConnections, world.DescendantAdded:Connect(addObject))
        table.insert(worldConnections, world.DescendantRemoving:Connect(removeObject))
        -- One scan per replacement/stream-in; subsequent work is cached and debounced.
        for _, object in ipairs(world:GetDescendants()) do addObject(object) end
    end
    local function applyLighting()
        appliedExposure = math.clamp(baseExposure + values.Brightness, -2, 2)
        appliedShadows = baseShadows and values.Shadows
        -- Lighting stores a float32; Lua preferences use doubles. A rounded own
        -- write must never become a new baseline and receive the offset again.
        if math.abs(Lighting.ExposureCompensation - appliedExposure) > 0.00001 then
            Lighting.ExposureCompensation = appliedExposure
        end
        appliedExposure = Lighting.ExposureCompensation
        if Lighting.GlobalShadows ~= appliedShadows then Lighting.GlobalShadows = appliedShadows end
    end
    track(Lighting:GetPropertyChangedSignal("ExposureCompensation"):Connect(function()
        if stopped or math.abs(Lighting.ExposureCompensation - appliedExposure) <= 0.00001 then return end
        baseExposure = Lighting.ExposureCompensation
        applyLighting()
    end))
    track(Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(function()
        if stopped or Lighting.GlobalShadows == appliedShadows then return end
        baseShadows = Lighting.GlobalShadows
        applyLighting()
    end))
    track(Workspace.ChildAdded:Connect(function(child) if child.Name == "GeneratedWorld" then bindWorld(child) end end))
    track(Workspace.ChildRemoved:Connect(function(child) if child == world then bindWorld(nil) end end))
    bindWorld(Workspace:FindFirstChild("GeneratedWorld"))

    local function corner(object, radius)
        local rounded = Instance.new("UICorner")
        rounded.CornerRadius, rounded.Parent = UDim.new(0, radius or 8), object
    end
    local function text(parent, name, caption, size, bold)
        local label = Instance.new("TextLabel")
        label.Name, label.Text, label.BackgroundTransparency = name, caption, 1
        label.TextColor3, label.TextSize, label.Font = palette.text, size, bold and Enum.Font.GothamBold or Enum.Font.Gotham
        label.TextXAlignment, label.TextYAlignment, label.TextWrapped = Enum.TextXAlignment.Left, Enum.TextYAlignment.Center, true
        label.ZIndex, label.Parent = 42, parent
        return label
    end
    local function button(parent, name, caption, callback)
        local object = Instance.new("TextButton")
        object.Name, object.Text, object.Font, object.TextSize = name, caption, Enum.Font.GothamBold, 17
        object.BackgroundColor3, object.TextColor3, object.BorderSizePixel = palette.green, palette.text, 0
        object.AutoButtonColor, object.TextWrapped, object.ZIndex, object.Parent = true, true, 43, parent
        local constraint = Instance.new("UISizeConstraint")
        constraint.MinSize, constraint.Parent = Vector2.new(44, 44), object
        corner(object)
        track(object.Activated:Connect(callback))
        return object
    end
    local gear = button(root, "AbrirAjustes", "⚙", function() controller:SetOpen(not controller:IsOpen()) end)
    gear.Font, gear.TextSize, gear.ZIndex = Enum.Font.ArialBold, 31, 30
    gear.TextYAlignment = Enum.TextYAlignment.Top
    gear:SetAttribute("AccessibleName", "Ajustes de la experiencia")
    local gearHint = text(gear, "Descripcion", "Ajustes", 10, false)
    gearHint.TextXAlignment, gearHint.ZIndex = Enum.TextXAlignment.Center, 31
    gearHint.Position, gearHint.Size = UDim2.fromOffset(0, 32), UDim2.new(1, 0, 0, 14)
    local panel = Instance.new("Frame")
    panel.Name, panel.Visible, panel.Active = "AjustesExperiencia", false, true
    panel.BackgroundColor3, panel.BackgroundTransparency, panel.BorderSizePixel = palette.panel, 0.08, 0
    panel.ZIndex, panel.Parent = 40, root
    corner(panel, 10)
    local title = text(panel, "Titulo", "TU EXPERIENCIA", 18, true)
    title.TextColor3 = palette.gold
    local subtitle = text(panel, "AvisoSesion", "Se mantiene al reaparecer durante esta sesión.", 12, false)
    subtitle.TextColor3 = palette.muted
    local close = button(panel, "CerrarAjustes", "X", function() controller:SetOpen(false) end)
    close.BackgroundColor3 = palette.red
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name, scroll.BackgroundTransparency, scroll.BorderSizePixel = "Opciones", 1, 0
    scroll.ScrollBarThickness, scroll.ScrollBarImageColor3 = 5, palette.gold
    scroll.ScrollingDirection, scroll.ZIndex, scroll.Parent = Enum.ScrollingDirection.Y, 41, panel
    local definitions = {
        {"Quality", "Calidad visual", "Baja: 25% de pasto. Normal: 50%. Alta: 100%."},
        {"DecorDensity", "Densidad del pasto", "Controla las hojas que sobresalen del suelo."},
        {"Grass", "Mostrar pasto decorativo", "Oculta las hojas altas; el suelo verde se conserva."},
        {"TreeDetail", "Detalle de árboles", "Reducido conserva troncos y las copas principales."},
        {"SignDistance", "Carteles del mapa", "Distancia de sus textos; las señales físicas permanecen."},
        {"Shadows", "Sombras del mapa", "Desactivarlas puede aliviar el trabajo de la GPU."},
        {"FXDensity", "Detalle de efectos", "Reduce chispas y segmentos del alcance; conserva la señal de ataque."},
        {"PanelOpacity", "Opacidad de paneles", "Los textos y las señales de combate siguen visibles."},
        {"Brightness", "Brillo personal", "Ajuste suave de exposición; conserva el ciclo día/noche."},
        {"ControlSide", "Ubicación de controles", "Mueve el panel de acciones y el menú lateral."},
        {"OffsetX", "Mover controles: horizontal", "Desplazamiento en píxeles, dentro de la pantalla."},
        {"OffsetY", "Mover controles: vertical", "El joystick nativo mantiene su ubicación."},
        {"ActionOrder", "Orden del menú táctil", "Podés dejar el ataque y la defensa al principio."},
        {"PanelWidth", "Ancho de este menú", "Se adapta al espacio disponible de tu pantalla."},
    }
    local function valueText(key)
        local value = values[key]
        if typeof(value) == "boolean" then return value and "Sí" or "No" end
        if key == "FXDensity" then return value == 0 and "Mínimos" or (value == 50 and "Reducidos" or "Completos") end
        if key == "SignDistance" then return value == 0 and "Ocultar textos" or (tostring(value) .. " studs") end
        if key == "DecorDensity" or key == "PanelOpacity" then return tostring(value) .. "%" end
        if key == "Brightness" then return string.format("%+.1f EV", value) end
        if key == "OffsetX" or key == "OffsetY" then return string.format("%+d px", value) end
        if key == "PanelWidth" then return tostring(value) .. " px" end
        return tostring(value)
    end
    local function cycle(key, direction)
        local allowed = choices[key]
        local index = table.find(allowed, values[key]) or 1
        ExperienceSettings.set(key, allowed[(index - 1 + direction) % #allowed + 1])
    end
    for _, definition in ipairs(definitions) do
        local key = definition[1]
        local row = Instance.new("Frame")
        row.Name, row.BackgroundTransparency, row.Size, row.ZIndex, row.Parent = key, 1, UDim2.new(1, -8, 0, 100), 41, scroll
        local heading = text(row, "Nombre", definition[2], 14, true)
        local detail = text(row, "Ayuda", definition[3], 11, false)
        detail.TextColor3 = palette.muted
        local value = text(row, "Valor", valueText(key), 14, true)
        value.TextXAlignment, value.TextColor3 = Enum.TextXAlignment.Center, palette.gold
        local previous = button(row, "Anterior", "‹", function() cycle(key, -1) end)
        local nextButton = button(row, "Siguiente", "›", function() cycle(key, 1) end)
        rows[#rows + 1] = {frame = row, title = heading, detail = detail, value = value, previous = previous, next = nextButton, key = key, help = definition[3]}
    end
    local function refreshDescriptions()
        for _, row in ipairs(rows) do
            local caption = row.help
            if row.key == "DecorDensity" then
                caption = visualSummary.GrassLoaded > 0
                    and string.format("Se ven %d de %d hojas cargadas. Probá 0%% y 100%%.", visualSummary.GrassVisible, visualSummary.GrassLoaded)
                    or "No hay hojas cargadas cerca. Acercate a un parche de hierba."
            elseif row.key == "TreeDetail" and visualSummary.TreeLeavesLoaded > 0 then
                caption = string.format("Copas visibles: %d de %d. Los troncos se conservan.", visualSummary.TreeLeavesVisible, visualSummary.TreeLeavesLoaded)
            end
            if caption and row.detail.Text ~= caption then row.detail.Text = caption end
        end
    end
    refreshVisualSummary = function()
        for key in pairs(visualSummary) do visualSummary[key] = 0 end
        -- Recount only after a debounced preference/world change, never per frame.
        -- These are loaded decorations, not the server's whole map or camera visibility.
        for object, record in pairs(records) do
            if object.Parent and (record.kind == "Grass" or record.kind == "Tree") then
                local prefix = record.kind == "Grass" and "Grass" or "TreeLeaves"
                visualSummary[prefix .. "Loaded"] += 1
                if object.Transparency < 0.99 and object.LocalTransparencyModifier < 0.99 then
                    visualSummary[prefix .. "Visible"] += 1
                end
            end
        end
        for key, value in pairs(visualSummary) do
            if panel:GetAttribute(key) ~= value then panel:SetAttribute(key, value) end
        end
        refreshDescriptions()
    end
    refreshVisualSummary()
    local reset = button(panel, "RestablecerAjustes", "Restablecer valores", ExperienceSettings.reset)
    function controller:IsOpen() return panel.Visible end
    function controller:SetOpen(open)
        if stopped or panel.Visible == open then return end
        if open and options.onOpen then options.onOpen() end
        panel.Visible = open
        if options.onVisibilityChanged then options.onVisibilityChanged() end
    end
    function controller:Layout(size)
        if stopped then return end
        viewport = size
        local width, height = math.floor(size.X), math.floor(size.Y)
        if width < 1 or height < 1 then return end
        gear.Position, gear.Size = UDim2.fromOffset(math.max(0, width - 58), math.max(0, height - 58)), UDim2.fromOffset(48, 48)
        local panelWidth, panelHeight = math.min(values.PanelWidth, width - 20), math.min(650, height - 20)
        panel.Position, panel.Size = UDim2.fromOffset((width - panelWidth) / 2, (height - panelHeight) / 2), UDim2.fromOffset(panelWidth, panelHeight)
        title.Position, title.Size = UDim2.fromOffset(14, 8), UDim2.fromOffset(panelWidth - 82, 30)
        close.Position, close.Size = UDim2.fromOffset(panelWidth - 58, 8), UDim2.fromOffset(44, 44)
        subtitle.Position, subtitle.Size = UDim2.fromOffset(14, 42), UDim2.fromOffset(panelWidth - 28, 32)
        scroll.Position, scroll.Size = UDim2.fromOffset(12, 80), UDim2.fromOffset(panelWidth - 24, math.max(0, panelHeight - 146))
        for index, row in ipairs(rows) do
            row.frame.Position = UDim2.fromOffset(0, (index - 1) * 110)
            row.title.Position, row.title.Size = UDim2.fromOffset(2, 0), UDim2.new(1, -4, 0, 21)
            row.detail.Position, row.detail.Size = UDim2.fromOffset(2, 23), UDim2.new(1, -4, 0, 30)
            row.previous.Position, row.previous.Size = UDim2.fromOffset(2, 56), UDim2.fromOffset(44, 44)
            row.next.Position, row.next.Size = UDim2.new(1, -46, 0, 56), UDim2.fromOffset(44, 44)
            row.value.Position, row.value.Size = UDim2.fromOffset(50, 56), UDim2.new(1, -100, 0, 44)
        end
        scroll.CanvasSize = UDim2.fromOffset(0, #rows * 110)
        reset.Position, reset.Size = UDim2.new(0, 14, 1, -56), UDim2.new(1, -28, 0, 44)
        panel.BackgroundTransparency = math.clamp(1 - values.PanelOpacity / 100, 0, 0.6)
    end
    function controller:Destroy()
        if stopped then return end
        stopped = true
        if pending then task.cancel(pending); pending = nil end
        disconnectAll(connections); disconnectAll(worldConnections)
        for _, record in pairs(records) do restore(record) end
        table.clear(records); table.clear(trees); table.clear(dirty)
        Lighting.ExposureCompensation, Lighting.GlobalShadows = baseExposure, baseShadows
        panel:Destroy(); gear:Destroy()
        if mounted == controller then mounted = nil end
    end
    controller.panel, controller.gear = panel, gear
    local lastValues = ExperienceSettings.snapshot()
    track(ExperienceSettings.changed:Connect(function(snapshot)
        if stopped then return end
        for _, row in ipairs(rows) do
            local caption = valueText(row.key)
            if row.value.Text ~= caption then row.value.Text = caption end
        end
        refreshDescriptions()
        if snapshot.Brightness ~= lastValues.Brightness or snapshot.Shadows ~= lastValues.Shadows then applyLighting() end
        if snapshot.DecorDensity ~= lastValues.DecorDensity or snapshot.Grass ~= lastValues.Grass
            or snapshot.TreeDetail ~= lastValues.TreeDetail or snapshot.SignDistance ~= lastValues.SignDistance then queue(true) end
        lastValues = snapshot
        controller:Layout(viewport)
        if options.onChanged then options.onChanged() end
    end))
    applyLighting()
    return controller
end
return ExperienceSettings
