-- ===== LINORIA LIBRARY LOADING (zic1 fork) =====
local Library = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/Library.lua'))()
local ThemeManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/addons/SaveManager.lua'))()
print("skibidi")
-- ===== SERVICES =====
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local Stats = game:GetService("Stats")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer

-- ===== WEAPON SETTINGS (FROM MusketSettings.txt) =====
local WEAPON_SETTINGS = {
    Velocity = 1300,
    VelocityDeviation = 60,
    BaseDamage = 100,
    MinDamage = 80,
    BaseDmgDistance = 250,
    MinDmgDistance = 600,
    Deviation = 1.7,
    RecoilMagnitude = 12,
    ReloadTime = 15,
    AimTime = 0.5,
    SwayFactor = 0.08,
}

-- ===== CHANT PACKAGE LIST =====
local chantPackages = {
    "American", "Danish", "Dutch", "English", "English1FG", "EnglishGuard",
    "French", "FrenchGuard", "FrenchGuard2", "GermanBrunswick", "GermanKaiser",
    "GermanKing", "Irish", "Italian", "ItalianGuard", "Ottoman", "Polish",
    "Polish2", "PolishCongress", "Romanian", "Russian", "Scottish",
    "Scottish42nd", "Scottish71st", "ScottishRSG", "Spanish", "Swedish",
    "Swiss", "Zulu"
}

-- ===== CONFIGURATION =====
local config = {
    enabled = false,
    fovRadius = 150,
    teamCheck = false,
    aimPart = "Head",
    showFOV = true,
    fovColor = Color3.fromRGB(255, 255, 255),
    fovTransparency = 0.7,
    fovThickness = 1,
    toggleKey = "Delete",
    guiToggleKey = "RightShift",
    smoothing = 0.3,
    wallCheck = false,
    prediction = 0.25,
    bulletVelocity = WEAPON_SETTINGS.Velocity,
    bulletDrop = 5,
    autoPrediction = true,
    autoBulletDrop = true,
    gravityCompensation = 1.5,
    longRangeCompensation = 1.5,
    mountedLeadMultiplier = 2.0,
    autoCalibration = true,
    adaptiveCalibration = true,
    calibrationRate = 0.05,
    hitboxEnabled = false,
    hitboxSize = 15,
    hitboxColor = Color3.fromRGB(255, 0, 0),
    hitboxTransparency = 1,
    hitboxTeamCheck = true,
    chantPackage = "English",
    velocityDeviation = WEAPON_SETTINGS.VelocityDeviation,
    debugMode = false,
    
    -- Flag Tech Settings
    flagTechEnabled = true,
    flagHoldDuration = 1,
    flagMaxDistance = 6.7,
    
    -- ESP Settings
    espEnabled = false,
    espTeamCheck = false,
    espWallCheck = false,
    espBoxEnabled = true,
    espHealthbarEnabled = true,
    espNameEnabled = true,
    espDistanceEnabled = true,
    espTracerEnabled = false,
    espBoxColor = Color3.fromRGB(255, 255, 255),
    espHealthColor = Color3.fromRGB(0, 255, 0),
    espNameColor = Color3.fromRGB(255, 255, 255),
    espDistanceColor = Color3.fromRGB(255, 255, 255),
    espTracerColor = Color3.fromRGB(255, 255, 255),
    espWallColor = Color3.fromRGB(128, 0, 255),
    espWallHue = 0.75,
    espVisibleColor = Color3.fromRGB(0, 255, 128),
    espHiddenColor = Color3.fromRGB(255, 50, 50),
    espUseTeamColor = true,
    
    -- Bullet Tracer Settings
    bulletTracerEnabled = false,
    bulletTracerColor = Color3.fromRGB(255, 255, 0),
    bulletTracerDuration = 2,
    bulletTracerThickness = 2,
}

-- ===== STATE =====
local fovCircle = nil
local lastTargetPos = {}
local targetVelocities = {}
local isUILoaded = false
local bulletTraces = {} -- Table to store active bullet tracers

-- ===== HITBOX STATE =====
local Expanded = {}
local DEFAULT_HRP_SIZE = Vector3.new(2, 2, 1)
local DEFAULT_TRANSPARENCY = 1
local DEFAULT_COLOR = BrickColor.new("Medium stone grey")
local DEFAULT_MATERIAL = Enum.Material.Plastic
local DEFAULT_COLLIDE = false

-- ===== ESP STATE =====
local espObjects = {}

-- ===== UI SLIDER REFERENCES =====
local sliderElements = {
    predictionSlider = nil,
    velocitySlider = nil,
    dropSlider = nil,
    compensationSlider = nil,
}

-- ===== UI TOGGLE REFERENCES =====
local Toggles = {}

-- ===== CONNECTIONS =====
local connections = {
    renderStepped = nil,
    velocityLoop = nil,
    characterAdded = nil,
    toggleKeybind = nil,
    espUpdate = nil,
    sizeMonitor = nil,
    flagMonitor = nil,
    autoRefresh = nil,
    fastCastHook = nil,
    bulletTracerUpdate = nil,  -- Add this
}

-- ===== AUTO-CALCULATION =====
local autoCalc = {
    ping = 0.05,
    pingSamples = {},
    pingSampleCount = 0,
    totalShots = 0,
    totalHits = 0,
    hitRate = 0,
    lastShotTime = 0,
    shotCooldown = 0.5,
    calibrationValues = {
        prediction = { min = 0.05, max = 0.5, current = config.prediction },
        bulletDrop = { min = 0, max = 250, current = config.bulletDrop },
        bulletVelocity = { min = 100, max = 2000, current = config.bulletVelocity },
        gravityCompensation = { min = 0.5, max = 3.0, current = config.gravityCompensation }
    },
    remoteFound = false,
    remoteName = nil,
    autoCalcRunning = false,
    lastAutoUpdate = 0,
    autoUpdateInterval = 0.5,
}

-- ===== FOV CIRCLE =====
local function createFOVCircle()
    if fovCircle then
        pcall(function() fovCircle:Remove() end)
        fovCircle = nil
    end
    
    if not Drawing then
        warn("Drawing API not available! FOV circle disabled.")
        return
    end
    
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible = config.showFOV and config.enabled
    fovCircle.Thickness = config.fovThickness or 1
    fovCircle.Color = config.fovColor
    fovCircle.Transparency = config.fovTransparency or 0.7
    fovCircle.Filled = false
    fovCircle.NumSides = 60
    fovCircle.Radius = config.fovRadius
end

local function updateFOVCircle()
    if not fovCircle then return end
    fovCircle.Visible = config.showFOV and config.enabled
    fovCircle.Radius = config.fovRadius
    fovCircle.Color = config.fovColor
    fovCircle.Transparency = config.fovTransparency
    fovCircle.Thickness = config.fovThickness or 1
end

local function updateFOVPosition()
    if not fovCircle or not fovCircle.Visible then return end
    local mousePos = UserInputService:GetMouseLocation()
    fovCircle.Position = Vector2.new(mousePos.X, mousePos.Y)
end

-- ===== UPDATE UI SLIDERS =====
local function updateUISliders()
    if not isUILoaded then return end
    
    if sliderElements.predictionSlider then
        pcall(function()
            sliderElements.predictionSlider:Set(config.prediction)
        end)
    end
    
    if sliderElements.velocitySlider then
        pcall(function()
            sliderElements.velocitySlider:Set(config.bulletVelocity)
        end)
    end
    
    if sliderElements.dropSlider then
        pcall(function()
            sliderElements.dropSlider:Set(config.bulletDrop)
        end)
    end
    
    if sliderElements.compensationSlider then
        pcall(function()
            sliderElements.compensationSlider:Set(config.gravityCompensation)
        end)
    end
end

-- ===== CLEANUP =====
local function cleanup()
    print("Cleaning up VaM Client...")
    
    if fovCircle then
        pcall(function() fovCircle:Remove() end)
        fovCircle = nil
    end
    
    -- Clean up bullet tracers
    for _, trace in pairs(bulletTraces) do
        if trace.line then
            pcall(function() trace.line:Remove() end)
        end
    end
    bulletTraces = {}
    
    -- Clean up ESP
    for player, data in pairs(espObjects) do
        if data.box then pcall(function() data.box:Remove() end) end
        if data.boxOutline then pcall(function() data.boxOutline:Remove() end) end
        if data.healthbar then pcall(function() data.healthbar:Remove() end) end
        if data.healthbg then pcall(function() data.healthbg:Remove() end) end
        if data.nameText then pcall(function() data.nameText:Remove() end) end
        if data.distanceText then pcall(function() data.distanceText:Remove() end) end
        if data.tracer then pcall(function() data.tracer:Remove() end) end
        if data.connection then pcall(function() data.connection:Disconnect() end) end
    end
    espObjects = {}
    
    -- Clean up hitbox expansion
    for player, _ in pairs(Expanded) do
        if player and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    hrp.Size = DEFAULT_HRP_SIZE
                    hrp.Transparency = DEFAULT_TRANSPARENCY
                    hrp.BrickColor = DEFAULT_COLOR
                    hrp.Material = DEFAULT_MATERIAL
                    hrp.CanCollide = DEFAULT_COLLIDE
                    hrp.CanQuery = true
                end)
            end
        end
        Expanded[player] = nil
    end
    
    for _, conn in pairs(connections) do
        if conn then
            pcall(function()
                if type(conn) == "RBXScriptConnection" then
                    conn:Disconnect()
                elseif type(conn) == "thread" then
                    coroutine.close(conn)
                end
            end)
        end
    end
    
    if Window then
        pcall(function()
            Library:Unload()
        end)
        Window = nil
    end
    
    lastTargetPos = {}
    targetVelocities = {}
    config.enabled = false
    config.hitboxEnabled = false
    config.espEnabled = false
    
    print("Cleanup complete!")
end

-- ===== CHANT CHANGER =====
local function setChantPackage(packageName)
    if not plr or not packageName then return end
    
    local chantValue = plr:FindFirstChild("ChantPackage")
    if not chantValue and plr.Character then
        chantValue = plr.Character:FindFirstChild("ChantPackage")
    end
    
    if chantValue then
        local chantsFolder = ReplicatedStorage:FindFirstChild("Chants")
        if chantsFolder then
            local chantObject = chantsFolder:FindFirstChild(packageName)
            if chantObject then
                pcall(function()
                    chantValue.Value = chantObject
                    config.chantPackage = packageName
                    print("Chant package changed to: " .. packageName)
                end)
            else
                warn("Chant object not found: " .. packageName)
            end
        else
            warn("Chants folder not found in ReplicatedStorage")
        end
    else
        local chantsFolder = ReplicatedStorage:FindFirstChild("Chants")
        if chantsFolder then
            local chantObject = chantsFolder:FindFirstChild(packageName)
            if chantObject then
                local newChantValue = Instance.new("ObjectValue")
                newChantValue.Name = "ChantPackage"
                newChantValue.Value = chantObject
                newChantValue.Parent = plr.Character or plr
                config.chantPackage = packageName
                print("Created and set Chant package to: " .. packageName)
            end
        end
    end
end

-- ===== INITIALIZE CURRENT CHANT =====
local function initChantPackage()
    if not plr then return end
    
    local chantValue = plr:FindFirstChild("ChantPackage")
    if not chantValue and plr.Character then
        chantValue = plr.Character:FindFirstChild("ChantPackage")
    end
    
    if chantValue and chantValue.Value then
        local chantName = chantValue.Value.Name
        if chantName then
            config.chantPackage = chantName
            print("Current chant package: " .. chantName)
        end
    else
        print("No ChantPackage found. Use the Chant Changer to set one.")
    end
end

-- ===== HELPER FUNCTIONS =====
local function getTargetPart(player)
    if not player or not player.Character then return nil end
    
    local mount = player.Character:FindFirstChild("Horse") or 
                  player.Character:FindFirstChild("Vehicle") or 
                  player.Character:FindFirstChild("Mount")
    
    if mount then
        local mountPart = mount:FindFirstChild("Head") or 
                         mount:FindFirstChild("Torso") or 
                         mount:FindFirstChild("HumanoidRootPart")
        if mountPart then
            return mountPart
        end
    end
    
    return player.Character:FindFirstChild("HumanoidRootPart")
end

-- ===== HITBOX EXPANSION =====
local function resetHRP(hrp)
    if not hrp then return end
    pcall(function()
        hrp.Size = DEFAULT_HRP_SIZE
        hrp.Transparency = DEFAULT_TRANSPARENCY
        hrp.BrickColor = DEFAULT_COLOR
        hrp.Material = DEFAULT_MATERIAL
        hrp.CanCollide = DEFAULT_COLLIDE
    end)
end

local function isMounted(player)
    local model = Workspace:FindFirstChild(player.Name)
    if not model then return false end

    local horse = model:FindFirstChild("Horse")
    if horse and horse:IsA("Model") then
        local char = player.Character
        if not char then return true end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            resetHRP(hrp)
        end
        return true
    end

    return false
end

local function applyHitbox(player)
    if not config.hitboxEnabled then return end
    if not player or not player.Character then return end

    -- Team check
    if config.hitboxTeamCheck and player.Team ~= nil and plr.Team ~= nil then
        if player.Team == plr.Team then
            return
        end
    end

    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- Mounted? skip & reset
    if isMounted(player) then
        Expanded[player] = nil
        return
    end

    -- Already expanded?
    if Expanded[player] then
        pcall(function()
            hrp.Size = Vector3.new(config.hitboxSize, config.hitboxSize, config.hitboxSize)
        end)
        return
    end

    -- Apply hitbox
    pcall(function()
        hrp.Size = Vector3.new(config.hitboxSize, config.hitboxSize, config.hitboxSize)
        hrp.Transparency = config.hitboxTransparency
        hrp.BrickColor = BrickColor.new(config.hitboxColor)
        hrp.Material = Enum.Material.Neon
        hrp.CanCollide = false
        hrp.CanQuery = true
    end)

    Expanded[player] = true
end

local function resetAllExpanded()
    for player, _ in pairs(Expanded) do
        if player and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                resetHRP(hrp)
            end
        end
        Expanded[player] = nil
    end
end

local function applyHitboxToAllPlayers()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr then
            applyHitbox(player)
        end
    end
end

-- ===== FLAG TECH =====
local HOLD_DURATION = config.flagHoldDuration
local MAX_DISTANCE = config.flagMaxDistance

local function modifyPrompt(player, prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    if not config.flagTechEnabled then return end

    if config.hitboxTeamCheck and player.Team ~= nil and plr.Team ~= nil then
        if player.Team == plr.Team then
            return
        end
    end

    pcall(function()
        prompt.HoldDuration = HOLD_DURATION
        prompt.MaxActivationDistance = MAX_DISTANCE
    end)
end

local function handleGrip(player, grip)
    if not grip then return end

    for _, obj in ipairs(grip:GetChildren()) do
        if obj:IsA("ProximityPrompt") then
            modifyPrompt(player, obj)
        end
    end

    grip.ChildAdded:Connect(function(child)
        if child:IsA("ProximityPrompt") then
            modifyPrompt(player, child)
        end
    end)
end

local function handleColoursTool(player, tool)
    if not tool then return end
    local model = tool:FindFirstChild("Model")
    if not model then return end

    local grip = model:FindFirstChild("Grip")
    if grip and grip:IsA("BasePart") then
        handleGrip(player, grip)
    end

    model.ChildAdded:Connect(function(child)
        if child.Name == "Grip" and child:IsA("BasePart") then
            handleGrip(player, child)
        end
    end)
end

local function monitorPlayerFlags(player)
    if not player then return end

    local success, playerFolder = pcall(function() return Workspace:WaitForChild(player.Name, 5) end)
    if not success or not playerFolder then return end

    for _, obj in ipairs(playerFolder:GetChildren()) do
        if obj.Name == "Colours" and obj:IsA("Tool") then
            handleColoursTool(player, obj)
        end
    end

    playerFolder.ChildAdded:Connect(function(child)
        if child.Name == "Colours" and child:IsA("Tool") then
            handleColoursTool(player, child)
        end
    end)
end

local function reapplyPromptsForPlayer(player)
    if not player then return end
    local folder = Workspace:FindFirstChild(player.Name)
    if not folder then return end

    for _, child in ipairs(folder:GetChildren()) do
        if child.Name == "Colours" and child:IsA("Tool") then
            local model = child:FindFirstChild("Model")
            if model then
                local grip = model:FindFirstChild("Grip")
                if grip and grip:IsA("BasePart") then
                    for _, obj in ipairs(grip:GetChildren()) do
                        if obj:IsA("ProximityPrompt") then
                            modifyPrompt(player, obj)
                        end
                    end
                end
            end
        end
    end
end

local function reapplyPromptsForAll()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr then
            reapplyPromptsForPlayer(player)
        end
    end
end

-- ===== PLAYER CONNECTIONS (Modified with 5 second auto-refresh) =====
local function onCharacterAdded(player, char)
    Expanded[player] = nil

    task.spawn(function()
        local hrp = char:WaitForChild("HumanoidRootPart", 5)
        if hrp then
            applyHitbox(player)
        end
    end)

    task.spawn(function()
        local ok, model = pcall(function() return Workspace:WaitForChild(player.Name, 5) end)
        if not ok or not model then return end

        model.ChildAdded:Connect(function()
            if isMounted(player) then
                Expanded[player] = nil
            end
        end)

        model.ChildRemoved:Connect(function()
            task.wait(0.1)
            applyHitbox(player)
        end)
    end)
end

local function onPlayerAdded(player)
    -- Character handling
    player.CharacterAdded:Connect(function(char)
        onCharacterAdded(player, char)
    end)

    if player.Character then
        onCharacterAdded(player, player.Character)
    end

    -- Flag monitoring
    monitorPlayerFlags(player)
end

-- Connect existing players
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= plr then
        onPlayerAdded(player)
    end
end

-- Future players
Players.PlayerAdded:Connect(function(player)
    if player ~= plr then
        onPlayerAdded(player)
    end
end)

-- ===== AUTO REFRESH HITBOXES EVERY 5 SECONDS =====
connections.autoRefresh = task.spawn(function()
    while task.wait(5) do
        if config.hitboxEnabled then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= plr then
                    applyHitbox(player)
                end
            end
        end
    end
end)

-- ===== Monitor _G.HeadSize changes (now using config.hitboxSize) =====
do
    local lastHitboxSize = config.hitboxSize
    task.spawn(function()
        while true do
            task.wait(0.15)
            if config.hitboxSize ~= lastHitboxSize then
                lastHitboxSize = config.hitboxSize
                for player, _ in pairs(Expanded) do
                    if player and player.Character then
                        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            pcall(function()
                                hrp.Size = Vector3.new(config.hitboxSize, config.hitboxSize, config.hitboxSize)
                            end)
                        end
                    end
                end
            end
        end
    end)
end

-- ===== FASTCAST BULLET TRACER (Using ActiveCast detection) =====
local TracerColor = Color3.fromRGB(0, 255, 128)  -- Lime Green
local TracerThickness = 0.1
local FadeTime = 0.2

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local tracerHooked = false
local activeTracers = {}
local hookedCasters = {}

-- ===== CREATE BULLET SEGMENT =====
local function CreateBulletSegment(startPoint, endPoint)
    if not startPoint or not endPoint then return end
    
    local distance = (startPoint - endPoint).Magnitude
    if distance < 0.1 or distance > 1000 then return end

    local segment = Instance.new("Part")
    segment.Name = "FastCastTracer"
    segment.Anchored = true
    segment.CanCollide = false
    segment.CanTouch = false
    segment.CanQuery = false
    segment.Material = Enum.Material.Neon
    segment.Color = TracerColor
    segment.Transparency = 0.2
    segment.Size = Vector3.new(TracerThickness, TracerThickness, distance)
    
    segment.CFrame = CFrame.lookAt(startPoint, endPoint) * CFrame.new(0, 0, -distance / 2)
    segment.Parent = workspace

    local fadeTween = TweenService:Create(segment, TweenInfo.new(FadeTime, Enum.EasingStyle.Linear), {
        Transparency = 1,
        Size = Vector3.new(0, 0, distance)
    })
    
    fadeTween:Play()
    Debris:AddItem(segment, FadeTime + 0.05)
    
    table.insert(activeTracers, segment)
end

-- ===== CHECK IF OBJECT IS AN ACTIVECAST =====
local function IsActiveCast(obj)
    if typeof(obj) ~= "table" then return false end
    local mt = getmetatable(obj)
    if mt and mt.__type == "ActiveCast" then
        return true
    end
    return false
end

-- ===== CHECK IF OBJECT IS A FASTCAST CASTER =====
local function IsFastCastCaster(obj)
    if typeof(obj) ~= "table" then return false end
    
    -- Check for FastCast caster signature
    local hasLengthChanged = obj.LengthChanged ~= nil
    local hasFire = obj.Fire ~= nil
    local hasConnect = obj.LengthChanged and typeof(obj.LengthChanged) == "table" and obj.LengthChanged.Connect ~= nil
    
    return (hasLengthChanged and hasFire and hasConnect)
end

-- ===== HOOK A CASTER'S LENGTHCHANGED EVENT =====
local function HookCaster(caster)
    if not caster or typeof(caster) ~= "table" then return false end
    
    -- Check if already hooked
    if hookedCasters[caster] then return false end
    
    -- Verify it's a FastCast caster
    if not IsFastCastCaster(caster) then return false end
    
    -- Check if LengthChanged exists and is connectable
    if caster.LengthChanged and typeof(caster.LengthChanged) == "table" and caster.LengthChanged.Connect then
        -- Mark as hooked
        hookedCasters[caster] = true
        
        -- Hook the LengthChanged event
        caster.LengthChanged:Connect(function(cast, lastPoint, rayDir, displacement, velocity, bulletPart)
            if lastPoint and rayDir and displacement then
                local tipPoint = lastPoint + (rayDir * displacement)
                task.spawn(CreateBulletSegment, lastPoint, tipPoint)
            end
        end)
        
        print("[FastCast Tracer] Hooked FastCast caster!")
        return true
    end
    
    return false
end

-- ===== METHOD 1: SCAN GC FOR ACTIVECAST INSTANCES =====
local function ScanGCForActiveCasts()
    print("[FastCast Tracer] Scanning GC for ActiveCast instances...")
    
    local gcObjects = getgc(true)
    local hookedCount = 0
    local totalTables = 0
    
    for _, obj in ipairs(gcObjects) do
        if typeof(obj) == "table" then
            totalTables = totalTables + 1
            
            -- Check if it's an ActiveCast
            if IsActiveCast(obj) then
                print("[FastCast Tracer] Found ActiveCast!")
                -- ActiveCast has a Caster property
                if obj.Caster and IsFastCastCaster(obj.Caster) then
                    if HookCaster(obj.Caster) then
                        hookedCount = hookedCount + 1
                    end
                end
            -- Check if it's a FastCast caster directly
            elseif IsFastCastCaster(obj) then
                if HookCaster(obj) then
                    hookedCount = hookedCount + 1
                end
            end
        end
    end
    
    if hookedCount > 0 then
        tracerHooked = true
        print("[FastCast Tracer] Successfully hooked " .. hookedCount .. " FastCast caster(s)! (Scanned " .. totalTables .. " tables)")
    else
        print("[FastCast Tracer] No FastCast casters found in GC. (Scanned " .. totalTables .. " tables)")
    end
    
    return hookedCount
end

-- ===== METHOD 2: SCAN GC FOR FASTCAST CASTERS (Legacy) =====
local function ScanGCForFastCast()
    print("[FastCast Tracer] Scanning GC for FastCast casters...")
    
    local gcObjects = getgc(true)
    local hookedCount = 0
    local totalTables = 0
    
    for _, obj in ipairs(gcObjects) do
        if typeof(obj) == "table" then
            totalTables = totalTables + 1
            
            -- Check if it has FastCast caster signature
            if IsFastCastCaster(obj) then
                if HookCaster(obj) then
                    hookedCount = hookedCount + 1
                end
            end
        end
    end
    
    if hookedCount > 0 then
        tracerHooked = true
        print("[FastCast Tracer] Successfully hooked " .. hookedCount .. " FastCast caster(s)! (Scanned " .. totalTables .. " tables)")
    else
        print("[FastCast Tracer] No FastCast casters found in GC. (Scanned " .. totalTables .. " tables)")
    end
    
    return hookedCount
end

-- ===== METHOD 3: HOOK FASTCAST.NEW() CONSTRUCTOR =====
local function HookFastCastNew()
    print("[FastCast Tracer] Attempting to hook FastCast.new()...")
    
    local fastCastModule = ReplicatedStorage:FindFirstChild("Tools")
    if fastCastModule then
        local components = fastCastModule:FindFirstChild("Components")
        if components then
            local muzzle = components:FindFirstChild("Muzzle")
            if muzzle then
                local fastCastScript = muzzle:FindFirstChild("FastCastRedux")
                if fastCastScript and fastCastScript:IsA("ModuleScript") then
                    local success, fastCast = pcall(function()
                        return require(fastCastScript)
                    end)
                    
                    if success and fastCast and fastCast.new then
                        print("[FastCast Tracer] Found FastCast module, hooking .new()...")
                        
                        local oldNew = fastCast.new
                        fastCast.new = function(...)
                            local caster = oldNew(...)
                            
                            -- Hook the new caster
                            if caster and typeof(caster) == "table" then
                                task.wait(0.1) -- Wait for caster to initialize
                                if IsFastCastCaster(caster) then
                                    HookCaster(caster)
                                end
                            end
                            
                            return caster
                        end
                        
                        print("[FastCast Tracer] FastCast.new() hooked successfully!")
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

-- ===== METHOD 4: HOOK GLOBAL FASTCAST =====
local function HookGlobalFastCast()
    if _G.FastCast and typeof(_G.FastCast) == "table" then
        if IsFastCastCaster(_G.FastCast) then
            print("[FastCast Tracer] Found global FastCast!")
            return HookCaster(_G.FastCast)
        end
    end
    return false
end

-- ===== CONTINUOUS SCAN FOR NEW CASTERS =====
local function StartContinuousScan()
    task.spawn(function()
        local attempts = 0
        while attempts < 15 and not tracerHooked do
            attempts = attempts + 1
            task.wait(3)
            
            -- Try scanning for ActiveCasts first (more reliable)
            local hooked = ScanGCForActiveCasts()
            if hooked > 0 then
                print("[FastCast Tracer] Found and hooked " .. hooked .. " ActiveCast(s) on attempt " .. attempts)
                break
            end
            
            -- Fallback to regular FastCast scan
            hooked = ScanGCForFastCast()
            if hooked > 0 then
                print("[FastCast Tracer] Found and hooked " .. hooked .. " FastCast caster(s) on attempt " .. attempts)
                break
            end
            
            print("[FastCast Tracer] Scan attempt " .. attempts .. " - no casters found.")
        end
        
        if tracerHooked then
            print("[FastCast Tracer] Tracers are now active!")
        else
            print("[FastCast Tracer] No FastCast casters found after 15 attempts. Make sure you have a weapon equipped and try firing once.")
        end
    end)
end

-- ===== MAIN HOOK FUNCTION =====
local function HookFastCastForTracers()
    if tracerHooked then return true end
    
    print("[FastCast Tracer] Attempting to hook FastCast...")
    
    -- Try different methods
    local methods = {
        HookGlobalFastCast,
        HookFastCastNew,
    }
    
    for _, method in ipairs(methods) do
        if method() then
            print("[FastCast Tracer] Hook successful!")
            tracerHooked = true
            return true
        end
    end
    
    -- If direct methods fail, scan GC for ActiveCasts
    local hooked = ScanGCForActiveCasts()
    if hooked > 0 then
        tracerHooked = true
        return true
    end
    
    -- Last resort: scan GC for FastCast casters
    hooked = ScanGCForFastCast()
    if hooked > 0 then
        tracerHooked = true
        return true
    end
    
    print("[FastCast Tracer] All hooking methods failed.")
    return false
end

-- ===== CLEANUP =====
local function ClearTracers()
    for _, tracer in ipairs(activeTracers) do
        pcall(function() tracer:Destroy() end)
    end
    activeTracers = {}
    hookedCasters = {}
    print("[FastCast Tracer] Cleared all tracers and reset hooks.")
end

-- ===== UPDATE LOOP =====
local function UpdateTracers()
    -- Debris handles cleanup, but we can clean any orphaned tracers
    for i, tracer in ipairs(activeTracers) do
        if not tracer or not tracer.Parent then
            table.remove(activeTracers, i)
        end
    end
end

-- ===== EXPOSE FUNCTIONS FOR UI =====
_G.FastCastTracer = {
    Enable = function()
        if not tracerHooked then
            HookFastCastForTracers()
            StartContinuousScan()
        else
            print("[FastCast Tracer] Already active.")
        end
    end,
    Disable = function()
        ClearTracers()
        tracerHooked = false
        print("[FastCast Tracer] Disabled.")
    end,
    SetColor = function(color)
        TracerColor = color
        for _, tracer in ipairs(activeTracers) do
            pcall(function() tracer.Color = color end)
        end
    end,
    SetThickness = function(thickness)
        TracerThickness = thickness
    end,
    SetFadeTime = function(time)
        FadeTime = time
    end,
    Clear = ClearTracers,
    Status = function()
        return tracerHooked
    end,
    Scan = function()
        return ScanGCForActiveCasts()
    end
}

-- ===== TRACER UPDATE LOOP =====
task.spawn(function()
    while task.wait(0.1) do
        pcall(UpdateTracers)
    end
end)

print("[FastCast Tracer] Script loaded. Tracers will appear when you fire a FastCast weapon.")
print("[FastCast Tracer] Use _G.FastCastTracer.Scan() to manually scan for casters.")
-- ===== PING DETECTION =====
local function detectPing()
    local statsData = Stats:FindFirstChild("Data")
    if statsData then
        local ping = statsData:FindFirstChild("Ping")
        if ping and type(ping.Value) == "number" then
            autoCalc.pingSamples[#autoCalc.pingSamples + 1] = ping.Value / 1000
            autoCalc.pingSampleCount = autoCalc.pingSampleCount + 1
            if autoCalc.pingSampleCount >= 5 then
                local total = 0
                local startIndex = math.max(1, #autoCalc.pingSamples - 4)
                for i = startIndex, #autoCalc.pingSamples do
                    total = total + autoCalc.pingSamples[i]
                end
                autoCalc.ping = total / autoCalc.pingSampleCount
                table.remove(autoCalc.pingSamples, 1)
            end
        end
    end
    return autoCalc.ping
end

-- ===== VELOCITY TRACKING =====
local function updateTargetVelocities()
    local dt = 0.05
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr and player.Character and player.Character.Parent then
            local targetPart = getTargetPart(player)
            if targetPart and targetPart.Parent then
                local currentPos = targetPart.Position
                if lastTargetPos[player] then
                    local delta = currentPos - lastTargetPos[player]
                    local rawVelocity = delta / dt
                    
                    if targetVelocities[player] then
                        targetVelocities[player] = targetVelocities[player] * 0.7 + rawVelocity * 0.3
                    else
                        targetVelocities[player] = rawVelocity
                    end
                else
                    targetVelocities[player] = Vector3.new(0, 0, 0)
                end
                lastTargetPos[player] = currentPos
            else
                lastTargetPos[player] = nil
                targetVelocities[player] = nil
            end
        end
    end
end

-- ===== AUTO-CALCULATE PREDICTION =====
local function autoCalculateValues(targetPart, player, distance, bulletTravelTime)
    if not config.autoPrediction and not config.autoBulletDrop then
        return
    end
    
    local currentTime = tick()
    if currentTime - autoCalc.lastAutoUpdate < autoCalc.autoUpdateInterval then
        return
    end
    autoCalc.lastAutoUpdate = currentTime
    
    if not targetPart or not player then
        return
    end
    
    local targetVelocity = targetVelocities[player]
    if not targetVelocity then
        return
    end
    
    local targetSpeed = targetVelocity.Magnitude
    if targetSpeed < 1 then
        return
    end
    
    if config.autoPrediction then
        local toTarget = (targetPart.Position - Camera.CFrame.Position).Unit
        local angle = math.acos(math.clamp(toTarget:Dot(targetVelocity.Unit), -1, 1))
        local perpendicularFactor = math.abs(math.sin(angle))
        
        local targetVelocityAlongShot = targetSpeed * math.cos(angle)
        local relativeVelocity = config.bulletVelocity - targetVelocityAlongShot
        if relativeVelocity < 1 then relativeVelocity = 1 end
        
        local optimalLeadTime = distance / relativeVelocity
        optimalLeadTime = math.clamp(optimalLeadTime, 0.01, 1)
        
        if perpendicularFactor > 0.3 then
            optimalLeadTime = optimalLeadTime * (1 + perpendicularFactor * 0.5)
        end
        
        optimalLeadTime = optimalLeadTime + autoCalc.ping
        
        local speedMultiplier = math.min(targetSpeed / 20, 3)
        optimalLeadTime = optimalLeadTime * (1 + speedMultiplier * 0.3)
        
        local newPrediction = optimalLeadTime / bulletTravelTime * 0.5
        newPrediction = math.clamp(newPrediction, 0.05, 0.5)
        
        config.prediction = config.prediction * 0.7 + newPrediction * 0.3
        config.prediction = math.clamp(config.prediction, 0.05, 0.5)
        
        autoCalc.calibrationValues.prediction.current = config.prediction
        
        if config.debugMode then
            print(string.format("Auto Lead: Speed=%.1f, Lead=%.3f, Angle=%.1f°", 
                targetSpeed, config.prediction, math.deg(angle)))
        end
    end
    
    if config.autoBulletDrop then
        local travelTime = distance / config.bulletVelocity
        if travelTime < 0.01 then travelTime = 0.01 end
        
        local heightDiff = targetPart.Position.Y - Camera.CFrame.Position.Y
        
        local optimalGravity = 0
        if travelTime > 0 then
            optimalGravity = (2 * math.abs(heightDiff)) / (travelTime * travelTime)
            
            if math.abs(heightDiff) < 1 then
                local dropFactor = 1 + (distance / 500) * 2
                optimalGravity = 20 * dropFactor
            end
        end
        
        optimalGravity = math.clamp(optimalGravity, 1, 250)
        optimalGravity = optimalGravity * config.gravityCompensation
        
        local newBulletDrop = config.bulletDrop * 0.6 + optimalGravity * 0.4
        newBulletDrop = math.clamp(newBulletDrop, 0, 250)
        
        config.bulletDrop = newBulletDrop
        
        autoCalc.calibrationValues.bulletDrop.current = config.bulletDrop
        
        if config.debugMode then
            print(string.format("Auto Drop: Dist=%.1f, Drop=%.1f, HeightDiff=%.1f", 
                distance, config.bulletDrop, heightDiff))
        end
    end
    
    updateUISliders()
end

-- ===== PREDICT POSITION =====
local function predictPosition(targetPart, player)
    if not targetPart or not targetPart.Parent then
        return targetPart and targetPart.Position or Vector3.new(0, 0, 0)
    end
    
    local basePosition = targetPart.Position
    local cameraPos = Camera.CFrame.Position
    local distance = (basePosition - cameraPos).Magnitude
    local bulletVelocity = config.bulletVelocity or WEAPON_SETTINGS.Velocity
    local pingComp = autoCalc.ping or 0.05
    
    local bulletTravelTime = math.clamp(distance / bulletVelocity, 0.01, 5)
    
    if (config.autoPrediction or config.autoBulletDrop) and player then
        autoCalculateValues(targetPart, player, distance, bulletTravelTime)
    end
    
    if config.autoPrediction and targetVelocities[player] then
        local velocity = targetVelocities[player]
        if velocity and velocity.Magnitude > 1 then
            local targetSpeed = velocity.Magnitude
            local toTarget = (basePosition - cameraPos).Unit
            local angle = math.acos(math.clamp(toTarget:Dot(velocity.Unit), -1, 1))
            local perpendicularFactor = math.abs(math.sin(angle))
            local leadTime = bulletTravelTime * config.prediction + pingComp
            
            local speedMultiplier = math.min(targetSpeed / 20, 5)
            leadTime = leadTime * (1 + speedMultiplier * 0.5)
            
            if perpendicularFactor > 0.5 then
                leadTime = leadTime * (1 + perpendicularFactor * 0.3)
            end
            
            basePosition = basePosition + (velocity * leadTime)
            
            if config.debugMode then
                print(string.format("Target: %s | Speed: %.1f | Lead: %.3f | Angle: %.1f°", 
                    player.Name, targetSpeed, leadTime, math.deg(angle)))
            end
        end
    end
    
    local drop = 0
    if config.bulletDrop > 0 then
        local predDist = (basePosition - cameraPos).Magnitude
        local travelTime = math.clamp(predDist / bulletVelocity, 0.01, 5)
        
        drop = 0.5 * config.bulletDrop * travelTime * travelTime
        drop = drop * config.gravityCompensation
        
        if config.autoBulletDrop then
            local heightDiff = basePosition.Y - cameraPos.Y
            if heightDiff > 0 then
                drop = drop * (1 + math.min(heightDiff / 50, 2))
            elseif heightDiff < -20 then
                drop = drop * (1 + math.max(heightDiff / 100, -0.5))
            end
            
            if predDist > 300 then
                local longRangeMultiplier = 1 + (predDist - 300) / 500
                drop = drop * math.min(longRangeMultiplier, 3)
            end
        end
    end
    
    basePosition = basePosition + Vector3.new(0, drop, 0)
    
    return basePosition
end

-- ===== GET CLOSEST TARGET =====
local function getClosestTarget()
    if not plr.Character or not plr.Character.Parent then return nil, nil end
    
    local mousePos = UserInputService:GetMouseLocation()
    local fovRadius = config.fovRadius
    local closestTarget = nil
    local closestPlayer = nil
    local closestDistance = fovRadius
    local cameraPos = Camera.CFrame.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr and player.Character and player.Character.Parent then
            if not config.teamCheck or (player.Team ~= plr.Team) then
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local targetPart = getTargetPart(player)
                    if targetPart and targetPart.Parent then
                        local predictedPos = predictPosition(targetPart, player)
                        local toTarget = predictedPos - cameraPos
                        if toTarget:Dot(Camera.CFrame.LookVector) < 0 then
                            continue
                        end
                        
                        local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)
                        if onScreen then
                            local distance = (Vector2.new(screenPos.X, screenPos.Y) - Vector2.new(mousePos.X, mousePos.Y)).Magnitude
                            if distance < closestDistance then
                                local wallPassed = true
                                if config.wallCheck then
                                    local rayParams = RaycastParams.new()
                                    rayParams.FilterDescendantsInstances = {plr.Character}
                                    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                                    rayParams.IgnoreWater = true
                                    local rayResult = Workspace:Raycast(cameraPos, (predictedPos - cameraPos).Unit * (predictedPos - cameraPos).Magnitude, rayParams)
                                    if rayResult and not rayResult.Instance:IsDescendantOf(player.Character) then
                                        wallPassed = false
                                    end
                                end
                                if wallPassed then
                                    closestDistance = distance
                                    closestTarget = targetPart
                                    closestPlayer = player
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return closestTarget, closestPlayer
end

-- ===== SILENT AIM =====
local function onRenderStepped()
    updateFOVPosition()
    
    if not config.enabled then return end
    if config.autoCalibration and tick() % 5 < 0.1 then detectPing() end
    
    local target, player = getClosestTarget()
    if target and player then
        local predictedPos = predictPosition(target, player)
        local cameraPos = Camera.CFrame.Position
        local direction = (predictedPos - cameraPos).Unit
        
        if config.smoothing < 0.95 then
            local currentLook = Camera.CFrame.LookVector
            local lerpFactor = 1 - math.pow(config.smoothing, 2)
            local newDirection = currentLook:Lerp(direction, math.clamp(lerpFactor, 0, 1))
            local newCFrame = CFrame.new(cameraPos, cameraPos + newDirection)
            local adjustedCFrame = Camera.CFrame:Lerp(newCFrame, math.clamp(lerpFactor * 0.1, 0, 0.1))
            pcall(function() Camera.CFrame = adjustedCFrame end)
        else
            pcall(function() Camera.CFrame = CFrame.new(cameraPos, predictedPos) end)
        end
    end
end

-- ===== ESP FUNCTIONS =====
local function isPlayerBehindWall(player)
    if not player or not player.Character then return false end
    
    local targetPart = getTargetPart(player)
    if not targetPart then return false end
    
    local origin = Camera.CFrame.Position
    local direction = (targetPart.Position - origin).Unit
    local distance = (targetPart.Position - origin).Magnitude
    
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {plr.Character}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.IgnoreWater = true
    
    local result = Workspace:Raycast(origin, direction * distance, rayParams)
    
    if result and result.Instance then
        local character = result.Instance.Parent
        while character do
            if character == player.Character then
                return false
            end
            character = character.Parent
        end
        return true
    end
    
    return false
end

local function getTeamColor(player)
    if player.Team then
        return player.Team.TeamColor.Color
    end
    return Color3.fromRGB(255, 255, 255)
end

local function getESPColorForPlayer(player)
    if not player then
        return config.espBoxColor
    end
    
    local isBehindWall = false
    if config.espWallCheck then
        isBehindWall = isPlayerBehindWall(player)
    end

    if config.espWallCheck and isBehindWall then
        if config.espUseTeamColor then
            local teamColor = getTeamColor(player)
            local h, s, v = Color3.toHSV(teamColor)
            return Color3.fromHSV(config.espWallHue or 0.75, s, v)
        else
            return config.espWallColor
        end
    else
        if config.espUseTeamColor then
            return getTeamColor(player)
        else
            return config.espBoxColor
        end
    end
end

local function getBoundingBox(character)
    local min = Vector2.new(math.huge, math.huge)
    local max = Vector2.new(-math.huge, -math.huge)
    local onscreen = false
    local padding = 1.15
    
    local parts = {}
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(parts, child)
        elseif child:IsA("Accessory") then
            local handle = child:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                table.insert(parts, handle)
            end
        end
    end
    
    if #parts == 0 then
        return min, max, false
    end
    
    for _, part in ipairs(parts) do
        local size = part.Size / 2 * padding
        local cf = part.CFrame
        local corners = {
            Vector3.new( size.X,  size.Y,  size.Z),
            Vector3.new(-size.X,  size.Y,  size.Z),
            Vector3.new( size.X, -size.Y,  size.Z),
            Vector3.new(-size.X, -size.Y,  size.Z),
            Vector3.new( size.X,  size.Y, -size.Z),
            Vector3.new(-size.X,  size.Y, -size.Z),
            Vector3.new( size.X, -size.Y, -size.Z),
            Vector3.new(-size.X, -size.Y, -size.Z),
        }
        
        for _, offset in ipairs(corners) do
            local pos, visible = Camera:WorldToViewportPoint(cf:PointToWorldSpace(offset))
            if visible then
                local v2 = Vector2.new(pos.X, pos.Y)
                min = Vector2.new(math.min(min.X, v2.X), math.min(min.Y, v2.Y))
                max = Vector2.new(math.max(max.X, v2.X), math.max(max.Y, v2.Y))
                onscreen = true
            end
        end
    end
    
    return min, max, onscreen
end

local function createESPForPlayer(player)
    if not player or player == plr then
        return
    end
    if espObjects[player] then
        return
    end
    if not player.Character then
        return
    end
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return
    end
    
    if config.espTeamCheck and player.Team == plr.Team then
        return
    end
    
    local espData = {
        box = nil,
        boxOutline = nil,
        healthbar = nil,
        healthbg = nil,
        nameText = nil,
        distanceText = nil,
        tracer = nil,
        visible = true,
    }
    
    if config.espBoxEnabled then
        local box = Drawing.new("Square")
        box.Thickness = 2
        box.Filled = false
        box.Transparency = 1
        box.Visible = false
        espData.box = box
        
        local boxOutline = Drawing.new("Square")
        boxOutline.Thickness = 3
        boxOutline.Filled = false
        boxOutline.Transparency = 0.8
        boxOutline.Color = Color3.new(0, 0, 0)
        boxOutline.Visible = false
        espData.boxOutline = boxOutline
    end
    
    if config.espHealthbarEnabled then
        local healthbar = Drawing.new("Square")
        healthbar.Thickness = 1
        healthbar.Filled = true
        healthbar.Transparency = 1
        healthbar.Visible = false
        espData.healthbar = healthbar
        
        local healthbg = Drawing.new("Square")
        healthbg.Thickness = 1
        healthbg.Filled = true
        healthbg.Transparency = 0.6
        healthbg.Color = Color3.new(0, 0, 0)
        healthbg.Visible = false
        espData.healthbg = healthbg
    end
    
    if config.espNameEnabled then
        local nameText = Drawing.new("Text")
        nameText.Center = true
        nameText.Outline = true
        nameText.Font = 1
        nameText.Size = 14
        nameText.Transparency = 1
        nameText.Visible = false
        espData.nameText = nameText
    end
    
    if config.espDistanceEnabled then
        local distanceText = Drawing.new("Text")
        distanceText.Center = true
        distanceText.Outline = true
        distanceText.Font = 1
        distanceText.Size = 12
        distanceText.Transparency = 1
        distanceText.Visible = false
        espData.distanceText = distanceText
    end
    
    if config.espTracerEnabled then
        local tracer = Drawing.new("Line")
        tracer.Thickness = 2
        tracer.Transparency = 0.7
        tracer.Visible = false
        espData.tracer = tracer
    end
    
    espObjects[player] = espData
    return espData
end

local function updateESPForPlayer(player)
    local espData = espObjects[player]
    if not espData then
        return
    end
    
    if not player or not player.Character then
        if espData.box then espData.box.Visible = false end
        if espData.boxOutline then espData.boxOutline.Visible = false end
        if espData.healthbar then espData.healthbar.Visible = false end
        if espData.healthbg then espData.healthbg.Visible = false end
        if espData.nameText then espData.nameText.Visible = false end
        if espData.distanceText then espData.distanceText.Visible = false end
        if espData.tracer then espData.tracer.Visible = false end
        espData.visible = false
        return
    end
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        if espData.box then espData.box.Visible = false end
        if espData.boxOutline then espData.boxOutline.Visible = false end
        if espData.healthbar then espData.healthbar.Visible = false end
        if espData.healthbg then espData.healthbg.Visible = false end
        if espData.nameText then espData.nameText.Visible = false end
        if espData.distanceText then espData.distanceText.Visible = false end
        if espData.tracer then espData.tracer.Visible = false end
        espData.visible = false
        return
    end
    
    if config.espTeamCheck and player.Team == plr.Team then
        if espData.box then espData.box.Visible = false end
        if espData.boxOutline then espData.boxOutline.Visible = false end
        if espData.healthbar then espData.healthbar.Visible = false end
        if espData.healthbg then espData.healthbg.Visible = false end
        if espData.nameText then espData.nameText.Visible = false end
        if espData.distanceText then espData.distanceText.Visible = false end
        if espData.tracer then espData.tracer.Visible = false end
        espData.visible = false
        return
    end
    
    local targetPart = getTargetPart(player)
    if not targetPart then
        if espData.box then espData.box.Visible = false end
        if espData.boxOutline then espData.boxOutline.Visible = false end
        if espData.healthbar then espData.healthbar.Visible = false end
        if espData.healthbg then espData.healthbg.Visible = false end
        if espData.nameText then espData.nameText.Visible = false end
        if espData.distanceText then espData.distanceText.Visible = false end
        if espData.tracer then espData.tracer.Visible = false end
        espData.visible = false
        return
    end
    
    local min, max, onscreen = getBoundingBox(player.Character)
    if not onscreen then
        if espData.box then espData.box.Visible = false end
        if espData.boxOutline then espData.boxOutline.Visible = false end
        if espData.healthbar then espData.healthbar.Visible = false end
        if espData.healthbg then espData.healthbg.Visible = false end
        if espData.nameText then espData.nameText.Visible = false end
        if espData.distanceText then espData.distanceText.Visible = false end
        if espData.tracer then espData.tracer.Visible = false end
        espData.visible = false
        return
    end
    
    espData.visible = true
    
    local mainColor = getESPColorForPlayer(player)
    
    local boxPos = min
    local boxSize = max - min
    local center = (min + max) / 2
    
    if espData.box and config.espBoxEnabled then
        espData.box.Position = boxPos
        espData.box.Size = boxSize
        espData.box.Color = mainColor
        espData.box.Visible = true
        
        if espData.boxOutline then
            espData.boxOutline.Position = boxPos - Vector2.new(1, 1)
            espData.boxOutline.Size = boxSize + Vector2.new(2, 2)
            espData.boxOutline.Visible = true
        end
    end
    
    if espData.healthbar and config.espHealthbarEnabled then
        local health = humanoid.Health / humanoid.MaxHealth
        local barWidth = 3
        local barHeight = boxSize.Y
        
        espData.healthbg.Position = Vector2.new(boxPos.X - barWidth - 2, boxPos.Y)
        espData.healthbg.Size = Vector2.new(barWidth, barHeight)
        espData.healthbg.Visible = true
        
        local fillHeight = barHeight * health
        espData.healthbar.Position = Vector2.new(boxPos.X - barWidth - 2, boxPos.Y + barHeight - fillHeight)
        espData.healthbar.Size = Vector2.new(barWidth, fillHeight)
        espData.healthbar.Color = Color3.new(1 - health, health, 0)
        espData.healthbar.Visible = true
    end
    
    if espData.nameText and config.espNameEnabled then
        espData.nameText.Text = player.Name
        espData.nameText.Position = Vector2.new(center.X, min.Y - 18)
        espData.nameText.Color = mainColor
        espData.nameText.Visible = true
    end
    
    if espData.distanceText and config.espDistanceEnabled then
        local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
        espData.distanceText.Text = math.floor(distance) .. "m"
        espData.distanceText.Position = Vector2.new(center.X, max.Y + 16)
        espData.distanceText.Color = mainColor
        espData.distanceText.Visible = true
    end
    
    if espData.tracer and config.espTracerEnabled then
        local mousePos = UserInputService:GetMouseLocation()
        espData.tracer.From = Vector2.new(mousePos.X, mousePos.Y)
        espData.tracer.To = center
        espData.tracer.Color = mainColor
        espData.tracer.Visible = true
    end
end

-- ===== ESP UPDATE LOOP =====
connections.espUpdate = task.spawn(function()
    while task.wait(1) do
        -- Update bullet tracers
        pcall(updateBulletTracers)
        
        if config.espEnabled then
            pcall(function()
                -- Remove ESP for players that no longer exist
                for player, espData in pairs(espObjects) do
                    if not player or not player.Parent or player == plr then
                        if espData.box then pcall(function() espData.box:Remove() end) end
                        if espData.boxOutline then pcall(function() espData.boxOutline:Remove() end) end
                        if espData.healthbar then pcall(function() espData.healthbar:Remove() end) end
                        if espData.healthbg then pcall(function() espData.healthbg:Remove() end) end
                        if espData.nameText then pcall(function() espData.nameText:Remove() end) end
                        if espData.distanceText then pcall(function() espData.distanceText:Remove() end) end
                        if espData.tracer then pcall(function() espData.tracer:Remove() end) end
                        espObjects[player] = nil
                    end
                end
                
                -- Create ESP for new players
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= plr and not espObjects[player] then
                        if config.espEnabled then
                            if player.Character then
                                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                                if humanoid and humanoid.Health > 0 then
                                    createESPForPlayer(player)
                                end
                            end
                        end
                    end
                end
                
                -- Update ESP for all players
                for player, _ in pairs(espObjects) do
                    if config.espEnabled then
                        updateESPForPlayer(player)
                    else
                        local espData = espObjects[player]
                        if espData.box then espData.box.Visible = false end
                        if espData.boxOutline then espData.boxOutline.Visible = false end
                        if espData.healthbar then espData.healthbar.Visible = false end
                        if espData.healthbg then espData.healthbg.Visible = false end
                        if espData.nameText then espData.nameText.Visible = false end
                        if espData.distanceText then espData.distanceText.Visible = false end
                        if espData.tracer then espData.tracer.Visible = false end
                    end
                end
            end)
        end
    end
end)

-- ===== HANDLE PLAYER RESPAWN =====
local function setupPlayerRespawnHandler(player)
    if player == plr then
        return
    end
    
    local charRemovingConn
    charRemovingConn = player.CharacterRemoving:Connect(function()
        if espObjects[player] then
            local espData = espObjects[player]
            if espData.box then pcall(function() espData.box:Remove() end) end
            if espData.boxOutline then pcall(function() espData.boxOutline:Remove() end) end
            if espData.healthbar then pcall(function() espData.healthbar:Remove() end) end
            if espData.healthbg then pcall(function() espData.healthbg:Remove() end) end
            if espData.nameText then pcall(function() espData.nameText:Remove() end) end
            if espData.distanceText then pcall(function() espData.distanceText:Remove() end) end
            if espData.tracer then pcall(function() espData.tracer:Remove() end) end
            espObjects[player] = nil
        end
        if charRemovingConn then
            charRemovingConn:Disconnect()
        end
    end)
    
    local charAddedConn
    charAddedConn = player.CharacterAdded:Connect(function(character)
        task.wait(0.5)
        if config.espEnabled then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                createESPForPlayer(player)
            end
        end
        if config.hitboxEnabled then
            task.wait(0.5)
            applyHitbox(player)
        end
        if charAddedConn then
            charAddedConn:Disconnect()
        end
    end)
end

-- ===== CREATE UI =====
local Window = Library:CreateWindow({
    Title = "VaM Client",
    Center = true,
    AutoShow = true,
    Resizable = true,
    ShowCustomCursor = true,
    ToggleKey = Enum.KeyCode[config.guiToggleKey] or Enum.KeyCode.RightShift,
})

-- ===== TABS =====
local SilentAimTab = Window:AddTab("Silent Aim")
local PredictionTab = Window:AddTab("Prediction")
local VisualsTab = Window:AddTab("Visuals")  -- Renamed from ESP
local RageTab = Window:AddTab("Rage")
local ChantTab = Window:AddTab("Chant")
local SettingsTab = Window:AddTab("Settings")

-- ===== SILENT AIM TAB =====
local SilentAimGroup = SilentAimTab:AddLeftGroupbox("Silent Aim")

Toggles.Enabled = SilentAimGroup:AddToggle("Enabled", {
    Text = "Enabled",
    Default = config.enabled,
    Callback = function(v)
        config.enabled = v
        if fovCircle then fovCircle.Visible = config.showFOV and v end
    end
})

SilentAimGroup:AddSlider("FOVRadius", {
    Text = "FOV Radius",
    Default = config.fovRadius,
    Min = 30,
    Max = 500,
    Rounding = 0,
    Callback = function(v)
        config.fovRadius = v
        updateFOVCircle()
    end
})

SilentAimGroup:AddToggle("TeamCheck", {
    Text = "Team Check",
    Default = config.teamCheck,
    Callback = function(v) config.teamCheck = v end
})

SilentAimGroup:AddDropdown("AimPart", {
    Text = "Aim Part",
    Values = {"Head", "Torso", "HumanoidRootPart"},
    Default = 1,
    Callback = function(v) config.aimPart = v end
})

SilentAimGroup:AddToggle("WallCheck", {
    Text = "Wall Check",
    Default = config.wallCheck,
    Callback = function(v) config.wallCheck = v end
})

SilentAimGroup:AddSlider("Smoothing", {
    Text = "Smoothing",
    Default = config.smoothing,
    Min = 0.05,
    Max = 0.95,
    Rounding = 2,
    Callback = function(v) config.smoothing = v end
})

-- ===== PREDICTION TAB =====
local PredictionGroup = PredictionTab:AddLeftGroupbox("Prediction")

PredictionGroup:AddToggle("AutoPrediction", {
    Text = "Auto Lead",
    Desc = "Automatically calculate lead based on target speed and distance",
    Default = config.autoPrediction,
    Callback = function(v)
        config.autoPrediction = v
        print("Auto lead: " .. (v and "ON" or "OFF"))
        if not v then
            config.prediction = 0.25
            autoCalc.calibrationValues.prediction.current = config.prediction
            updateUISliders()
        end
    end
})

PredictionGroup:AddToggle("AutoBulletDrop", {
    Text = "Auto Bullet Drop",
    Desc = "Automatically calculate bullet drop compensation",
    Default = config.autoBulletDrop,
    Callback = function(v)
        config.autoBulletDrop = v
        print("Auto bullet drop: " .. (v and "ON" or "OFF"))
        if not v then
            config.bulletDrop = 5
            autoCalc.calibrationValues.bulletDrop.current = config.bulletDrop
            updateUISliders()
        end
    end
})

sliderElements.predictionSlider = PredictionGroup:AddSlider("PredictionMultiplier", {
    Text = "Prediction Multiplier",
    Desc = "How much to lead moving targets",
    Default = config.prediction,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(v)
        config.prediction = v
        autoCalc.calibrationValues.prediction.current = v
    end
})

sliderElements.velocitySlider = PredictionGroup:AddSlider("BulletVelocity", {
    Text = "Bullet Velocity",
    Desc = "Bullet speed in studs/second",
    Default = config.bulletVelocity,
    Min = 100,
    Max = 2000,
    Rounding = 0,
    Callback = function(v)
        config.bulletVelocity = v
        autoCalc.calibrationValues.bulletVelocity.current = v
    end
})

sliderElements.dropSlider = PredictionGroup:AddSlider("BulletDrop", {
    Text = "Bullet Drop (Gravity)",
    Desc = "Gravitational acceleration in studs/s²",
    Default = config.bulletDrop,
    Min = 0,
    Max = 250,
    Rounding = 1,
    Callback = function(v)
        config.bulletDrop = v
        autoCalc.calibrationValues.bulletDrop.current = v
    end
})

sliderElements.compensationSlider = PredictionGroup:AddSlider("DropCompensation", {
    Text = "Drop Compensation",
    Desc = "Multiplier for bullet drop compensation",
    Default = config.gravityCompensation,
    Min = 0.5,
    Max = 3.0,
    Rounding = 2,
    Callback = function(v)
        config.gravityCompensation = v
        autoCalc.calibrationValues.gravityCompensation.current = v
    end
})

PredictionGroup:AddSlider("LongRangeCompensation", {
    Text = "Long Range Drop Bonus",
    Default = config.longRangeCompensation,
    Min = 0.5,
    Max = 3.0,
    Rounding = 2,
    Callback = function(v)
        config.longRangeCompensation = v
    end
})

PredictionGroup:AddSlider("MountedLeadMultiplier", {
    Text = "Mounted Lead Multiplier",
    Default = config.mountedLeadMultiplier,
    Min = 0.5,
    Max = 4.0,
    Rounding = 2,
    Callback = function(v)
        config.mountedLeadMultiplier = v
    end
})

PredictionGroup:AddToggle("DebugMode", {
    Text = "Debug Mode",
    Default = config.debugMode,
    Callback = function(v)
        config.debugMode = v
        print("Debug mode: " .. (v and "ON" or "OFF"))
    end
})

PredictionGroup:AddLabel("Weapon Info")
PredictionGroup:AddLabel("Musket Velocity: 1300 studs/s")
PredictionGroup:AddLabel("Velocity Deviation: ±60")
PredictionGroup:AddLabel("Deviation: 1.7 (accuracy/spread)")
PredictionGroup:AddLabel("Base Damage: 100 | Min: 80")
PredictionGroup:AddLabel("Effective Range: 250-600 studs")

-- ===== VISUALS TAB (Formerly ESP) =====
local VisualsLeftGroup = VisualsTab:AddLeftGroupbox("ESP Settings")

VisualsLeftGroup:AddToggle("ESPEnabled", {
    Text = "ESP Enabled",
    Default = config.espEnabled,
    Callback = function(v)
        config.espEnabled = v
        if v then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= plr then
                    task.wait(0.1)
                    createESPForPlayer(player)
                end
            end
        else
            for player, espData in pairs(espObjects) do
                if espData.box then pcall(function() espData.box:Remove() end) end
                if espData.boxOutline then pcall(function() espData.boxOutline:Remove() end) end
                if espData.healthbar then pcall(function() espData.healthbar:Remove() end) end
                if espData.healthbg then pcall(function() espData.healthbg:Remove() end) end
                if espData.nameText then pcall(function() espData.nameText:Remove() end) end
                if espData.distanceText then pcall(function() espData.distanceText:Remove() end) end
                if espData.tracer then pcall(function() espData.tracer:Remove() end) end
            end
            espObjects = {}
        end
    end
})

VisualsLeftGroup:AddToggle("ESPTeamCheck", {
    Text = "Team Check",
    Default = config.espTeamCheck,
    Callback = function(v)
        config.espTeamCheck = v
        if config.espEnabled then
            for player, espData in pairs(espObjects) do
                if espData.box then pcall(function() espData.box:Remove() end) end
                if espData.boxOutline then pcall(function() espData.boxOutline:Remove() end) end
                if espData.healthbar then pcall(function() espData.healthbar:Remove() end) end
                if espData.healthbg then pcall(function() espData.healthbg:Remove() end) end
                if espData.nameText then pcall(function() espData.nameText:Remove() end) end
                if espData.distanceText then pcall(function() espData.distanceText:Remove() end) end
                if espData.tracer then pcall(function() espData.tracer:Remove() end) end
            end
            espObjects = {}
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= plr then
                    task.wait(0.1)
                    createESPForPlayer(player)
                end
            end
        end
    end
})

VisualsLeftGroup:AddToggle("ESPWallCheck", {
    Text = "Wall Check",
    Desc = "Change ESP colors when players are behind walls",
    Default = config.espWallCheck,
    Callback = function(v)
        config.espWallCheck = v
    end
})

VisualsLeftGroup:AddDivider()
VisualsLeftGroup:AddLabel("ESP Elements")

VisualsLeftGroup:AddToggle("ESPBoxEnabled", {
    Text = "Bounding Box",
    Default = config.espBoxEnabled,
    Callback = function(v)
        config.espBoxEnabled = v
        if config.espEnabled then
            for player, espData in pairs(espObjects) do
                if espData.box then pcall(function() espData.box:Remove() end) end
                if espData.boxOutline then pcall(function() espData.boxOutline:Remove() end) end
                if espData.healthbar then pcall(function() espData.healthbar:Remove() end) end
                if espData.healthbg then pcall(function() espData.healthbg:Remove() end) end
                if espData.nameText then pcall(function() espData.nameText:Remove() end) end
                if espData.distanceText then pcall(function() espData.distanceText:Remove() end) end
                if espData.tracer then pcall(function() espData.tracer:Remove() end) end
            end
            espObjects = {}
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= plr then
                    task.wait(0.1)
                    createESPForPlayer(player)
                end
            end
        end
    end
})

VisualsLeftGroup:AddToggle("ESPHealthbarEnabled", {
    Text = "Health Bar",
    Default = config.espHealthbarEnabled,
    Callback = function(v)
        config.espHealthbarEnabled = v
    end
})

VisualsLeftGroup:AddToggle("ESPNameEnabled", {
    Text = "Player Names",
    Default = config.espNameEnabled,
    Callback = function(v)
        config.espNameEnabled = v
    end
})

VisualsLeftGroup:AddToggle("ESPDistanceEnabled", {
    Text = "Distance",
    Default = config.espDistanceEnabled,
    Callback = function(v)
        config.espDistanceEnabled = v
    end
})

VisualsLeftGroup:AddToggle("ESPTracerEnabled", {
    Text = "ESP Tracers",
    Default = config.espTracerEnabled,
    Callback = function(v)
        config.espTracerEnabled = v
    end
})

VisualsLeftGroup:AddDivider()
VisualsLeftGroup:AddLabel("Colors")

local visibleColorLabel = VisualsLeftGroup:AddLabel("Visible Color")
visibleColorLabel:AddColorPicker("ESPVisibleColor", {
    Default = config.espVisibleColor,
    Callback = function(v)
        config.espVisibleColor = v
    end
})

local hiddenColorLabel = VisualsLeftGroup:AddLabel("Hidden/Wall Color")
hiddenColorLabel:AddColorPicker("ESPHiddenColor", {
    Default = config.espHiddenColor,
    Callback = function(v)
        config.espHiddenColor = v
    end
})

VisualsLeftGroup:AddToggle("ESPUseTeamColor", {
    Text = "Use Team Color",
    Default = config.espUseTeamColor,
    Callback = function(v)
        config.espUseTeamColor = v
    end
})

VisualsLeftGroup:AddButton({
    Text = "Refresh ESP",
    Func = function()
        if config.espEnabled then
            for player, espData in pairs(espObjects) do
                if espData.box then pcall(function() espData.box:Remove() end) end
                if espData.boxOutline then pcall(function() espData.boxOutline:Remove() end) end
                if espData.healthbar then pcall(function() espData.healthbar:Remove() end) end
                if espData.healthbg then pcall(function() espData.healthbg:Remove() end) end
                if espData.nameText then pcall(function() espData.nameText:Remove() end) end
                if espData.distanceText then pcall(function() espData.distanceText:Remove() end) end
                if espData.tracer then pcall(function() espData.tracer:Remove() end) end
            end
            espObjects = {}
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= plr then
                    task.wait(0.1)
                    createESPForPlayer(player)
                end
            end
            print("ESP refreshed!")
        else
            print("ESP is disabled. Enable it first.")
        end
    end
})

-- ===== TRACERS (Right Groupbox) =====
local TracersGroup = VisualsTab:AddRightGroupbox("Bullet Tracers")

TracersGroup:AddToggle("BulletTracerEnabled", {
    Text = "Bullet Tracers",
    Desc = "Show trajectory beams using FastCast LengthChanged",
    Default = config.bulletTracerEnabled,
    Callback = function(v)
        config.bulletTracerEnabled = v
        if v then
            if _G.FastCastTracer then
                _G.FastCastTracer.Enable()
            else
                -- Try to initialize
                InitializeGCScan()
                StartContinuousScan()
            end
            print("Bullet tracers enabled!")
        else
            if _G.FastCastTracer then
                _G.FastCastTracer.Disable()
            end
            print("Bullet tracers disabled!")
        end
    end
})

local tracerColorLabel = TracersGroup:AddLabel("Tracer Color")
tracerColorLabel:AddColorPicker("BulletTracerColor", {
    Default = config.bulletTracerColor,
    Callback = function(v)
        config.bulletTracerColor = v
        if _G.FastCastTracer then
            _G.FastCastTracer.SetColor(v)
        end
    end
})

TracersGroup:AddSlider("BulletTracerDuration", {
    Text = "Tracer Fade Time (Seconds)",
    Default = config.bulletTracerDuration,
    Min = 0.05,
    Max = 5,
    Rounding = 1,
    Callback = function(v)
        config.bulletTracerDuration = v
        if _G.FastCastTracer then
            _G.FastCastTracer.SetFadeTime(v)
        end
    end
})

TracersGroup:AddSlider("BulletTracerThickness", {
    Text = "Tracer Thickness",
    Default = config.bulletTracerThickness,
    Min = 0.05,
    Max = 5,
    Rounding = 1,
    Callback = function(v)
        config.bulletTracerThickness = v
        if _G.FastCastTracer then
            _G.FastCastTracer.SetThickness(v)
        end
    end
})

TracersGroup:AddButton({
    Text = "Clear Tracers",
    Func = function()
        if _G.FastCastTracer then
            _G.FastCastTracer.Clear()
        else
            ClearTracers()
        end
    end
})

TracersGroup:AddButton({
    Text = "Force Scan FastCast",
    Func = function()
        print("Force scanning for FastCast casters...")
        InitializeGCScan()
        StartContinuousScan()
    end
})

-- ===== RAGE TAB =====
local RageGroup = RageTab:AddLeftGroupbox("Hitbox Extender")

RageGroup:AddToggle("HitboxEnabled", {
    Text = "Hitbox Extender",
    Default = config.hitboxEnabled,
    Callback = function(v)
        config.hitboxEnabled = v
        if v then
            applyHitboxToAllPlayers()
            print("Hitbox extender enabled!")
        else
            resetAllExpanded()
            print("Hitbox extender disabled!")
        end
    end
})

RageGroup:AddSlider("HitboxSize", {
    Text = "Hitbox Size",
    Default = config.hitboxSize,
    Min = 0.5,
    Max = 15,  -- Changed from 50 to 15
    Rounding = 0,
    Callback = function(v)
        config.hitboxSize = v
        if config.hitboxEnabled then
            for player, _ in pairs(Expanded) do
                if player and player.Character then
                    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        pcall(function()
                            hrp.Size = Vector3.new(v, v, v)
                        end)
                    end
                end
            end
        end
    end
})

local colorLabel = RageGroup:AddLabel("Hitbox Color")
colorLabel:AddColorPicker("HitboxColor", {
    Default = config.hitboxColor,
    Callback = function(v)
        config.hitboxColor = v
        for player, _ in pairs(Expanded) do
            if player and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function()
                        hrp.BrickColor = BrickColor.new(v)
                    end)
                end
            end
        end
    end
})

RageGroup:AddSlider("HitboxTransparency", {
    Text = "Hitbox Transparency",
    Default = config.hitboxTransparency,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(v)
        config.hitboxTransparency = v
        for player, _ in pairs(Expanded) do
            if player and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function()
                        hrp.Transparency = v
                    end)
                end
            end
        end
    end
})

RageGroup:AddToggle("HitboxTeamCheck", {
    Text = "Team Check",
    Default = config.hitboxTeamCheck,
    Callback = function(v)
        config.hitboxTeamCheck = v
        if config.hitboxEnabled then
            resetAllExpanded()
            applyHitboxToAllPlayers()
            reapplyPromptsForAll()
        end
    end
})

RageGroup:AddButton({
    Text = "Refresh Hitboxes",
    Func = function()
        if config.hitboxEnabled then
            resetAllExpanded()
            applyHitboxToAllPlayers()
            print("Hitboxes refreshed!")
        else
            print("Hitbox extender is disabled. Enable it first.")
        end
    end
})

-- ===== FLAG TECH =====
local FlagGroup = RageTab:AddRightGroupbox("Flag Tech")

FlagGroup:AddToggle("FlagTechEnabled", {
    Text = "Flag Tech Enabled",
    Default = config.flagTechEnabled,
    Callback = function(v)
        config.flagTechEnabled = v
        if v then
            reapplyPromptsForAll()
            print("Flag Tech enabled!")
        else
            reapplyPromptsForAll()
            print("Flag Tech disabled!")
        end
    end
})

FlagGroup:AddSlider("HoldDuration", {
    Text = "Pickup Time (Seconds)",
    Default = config.flagHoldDuration,
    Min = 0.5,
    Max = 3,
    Rounding = 1,
    Callback = function(v)
        config.flagHoldDuration = v
        HOLD_DURATION = v
        if config.flagTechEnabled then
            reapplyPromptsForAll()
        end
    end
})

FlagGroup:AddSlider("MaxDistance", {
    Text = "Max Distance",
    Default = config.flagMaxDistance,
    Min = 3,
    Max = 15,
    Rounding = 1,
    Callback = function(v)
        config.flagMaxDistance = v
        MAX_DISTANCE = v
        if config.flagTechEnabled then
            reapplyPromptsForAll()
        end
    end
})

FlagGroup:AddButton({
    Text = "Refresh Flag Tech",
    Func = function()
        if config.flagTechEnabled then
            reapplyPromptsForAll()
            print("Flag Tech refreshed!")
        else
            print("Flag Tech is disabled. Enable it first.")
        end
    end
})

-- ===== CHANT TAB =====
local ChantGroup = ChantTab:AddLeftGroupbox("Chant Changer")

ChantGroup:AddDropdown("ChantPackage", {
    Text = "Chant Package",
    Values = chantPackages,
    Default = 1,
    Callback = function(v)
        setChantPackage(v)
    end
})

ChantGroup:AddButton({
    Text = "Refresh Chant",
    Func = function()
        setChantPackage(config.chantPackage)
        print("Refreshed chant: " .. config.chantPackage)
    end
})

ChantGroup:AddButton({
    Text = "Random Chant",
    Func = function()
        local randomIndex = math.random(1, #chantPackages)
        local randomChant = chantPackages[randomIndex]
        setChantPackage(randomChant)
        print("Random chant: " .. randomChant)
    end
})

-- ===== SETTINGS TAB =====
local SettingsGroup = SettingsTab:AddLeftGroupbox("Keybinds")

local toggleKeyLabel = SettingsGroup:AddLabel("Toggle Silent Aim")
toggleKeyLabel:AddKeyPicker("ToggleKey", {
    Text = "Toggle Silent Aim",
    Default = config.toggleKey,
    Mode = "Toggle",
    ChangedCallback = function(v)
        local keyString = type(v) == "string" and v or tostring(v)
        config.toggleKey = keyString
        if connections.toggleKeybind then
            connections.toggleKeybind:Disconnect()
        end
        
        -- Try to get the Enum.KeyCode safely
        local success, keyCode = pcall(function()
            return Enum.KeyCode[keyString]
        end)
        
        if success and keyCode then
            connections.toggleKeybind = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if gameProcessed then return end
                if input.KeyCode == keyCode then
                    config.enabled = not config.enabled
                    if Toggles and Toggles.Enabled then
                        Toggles.Enabled:SetValue(config.enabled)
                    end
                    if fovCircle then fovCircle.Visible = config.showFOV and config.enabled end
                end
            end)
        else
            warn("Invalid key for Silent Aim toggle: " .. keyString)
            -- Fallback to Delete key
            connections.toggleKeybind = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if gameProcessed then return end
                if input.KeyCode == Enum.KeyCode.Delete then
                    config.enabled = not config.enabled
                    if Toggles and Toggles.Enabled then
                        Toggles.Enabled:SetValue(config.enabled)
                    end
                    if fovCircle then fovCircle.Visible = config.showFOV and config.enabled end
                end
            end)
        end
    end
})

local ActionsGroup = SettingsTab:AddRightGroupbox("Actions")

ActionsGroup:AddButton({
    Text = "Refresh Hitboxes",
    Func = function()
        if config.hitboxEnabled then
            resetAllExpanded()
            applyHitboxToAllPlayers()
            print("Hitboxes refreshed!")
        end
    end
})

ActionsGroup:AddButton({
    Text = "Refresh Flag Tech",
    Func = function()
        if config.flagTechEnabled then
            reapplyPromptsForAll()
            print("Flag Tech refreshed!")
        end
    end
})

ActionsGroup:AddButton({
    Text = "Unload Script",
    Func = function()
        cleanup()
    end
})

-- ===== THEME MANAGER =====
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:ApplyToTab(SettingsTab)

-- ===== INITIALIZATION =====
createFOVCircle()

task.spawn(function()
    task.wait(2) -- Wait for game to load
    HookFastCastForTracers()
    StartContinuousScan()
end)

print("[FastCast Tracer] Script loaded. Tracers will appear when you fire a FastCast weapon.")
print("[FastCast Tracer] Use _G.FastCastTracer.Scan() to manually scan for casters.")

connections.toggleKeybind = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode[config.toggleKey] then
        config.enabled = not config.enabled
        if Toggles and Toggles.Enabled then
            Toggles.Enabled:SetValue(config.enabled)
        end
        if fovCircle then fovCircle.Visible = config.showFOV and config.enabled end
    end
end)

-- Connect existing players for hitbox and flag tech
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= plr then
        onPlayerAdded(player)
    end
end

-- Future players
Players.PlayerAdded:Connect(function(player)
    if player ~= plr then
        onPlayerAdded(player)
    end
end)

-- Initial apply if enabled
if config.hitboxEnabled then
    task.wait(0.5)
    applyHitboxToAllPlayers()
end

if config.flagTechEnabled then
    task.wait(0.5)
    reapplyPromptsForAll()
end

-- Setup player respawn handlers for ESP
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayerRespawnHandler(player)
end

Players.PlayerAdded:Connect(function(player)
    setupPlayerRespawnHandler(player)
    if config.espEnabled then
        task.wait(0.5)
        createESPForPlayer(player)
    end
    if config.hitboxEnabled then
        task.wait(0.5)
        applyHitbox(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if Expanded[player] then
        Expanded[player] = nil
    end
    if espObjects[player] then
        local espData = espObjects[player]
        if espData.box then pcall(function() espData.box:Remove() end) end
        if espData.boxOutline then pcall(function() espData.boxOutline:Remove() end) end
        if espData.healthbar then pcall(function() espData.healthbar:Remove() end) end
        if espData.healthbg then pcall(function() espData.healthbg:Remove() end) end
        if espData.nameText then pcall(function() espData.nameText:Remove() end) end
        if espData.distanceText then pcall(function() espData.distanceText:Remove() end) end
        if espData.tracer then pcall(function() espData.tracer:Remove() end) end
        espObjects[player] = nil
    end
end)

connections.characterAdded = plr.CharacterAdded:Connect(function(character)
    character:WaitForChild("HumanoidRootPart", 5)
    lastTargetPos = {}
    targetVelocities = {}
    
    task.wait(0.5)
    local chantValue = character:FindFirstChild("ChantPackage")
    if chantValue and chantValue.Value then
        config.chantPackage = chantValue.Value.Name
    end
    
    if config.espEnabled then
        task.wait(0.5)
        -- ESP will update on its own loop
    end
end)

connections.renderStepped = RunService.RenderStepped:Connect(function()
    pcall(onRenderStepped)
end)

connections.velocityLoop = task.spawn(function()
    while task.wait(0.05) do
        pcall(updateTargetVelocities)
    end
end)

task.wait(0.5)
initChantPackage()

print("VaM Client loaded successfully!")
print("Musket Settings Applied:")
print("  Velocity: " .. WEAPON_SETTINGS.Velocity .. " studs/s")
print("  Velocity Deviation: ±" .. WEAPON_SETTINGS.VelocityDeviation)
print("  Deviation: " .. WEAPON_SETTINGS.Deviation)
print("  Damage: " .. WEAPON_SETTINGS.BaseDamage .. "-" .. WEAPON_SETTINGS.MinDamage)
print("  Range: " .. WEAPON_SETTINGS.BaseDmgDistance .. "-" .. WEAPON_SETTINGS.MinDmgDistance .. " studs")
print("Press " .. config.toggleKey .. " to toggle silent aim")
print("Press " .. config.guiToggleKey .. " to toggle GUI")
print("Click 'Unload Script' in the Settings tab to fully unload")
