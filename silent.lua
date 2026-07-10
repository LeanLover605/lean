-- ===== LINORIA LIBRARY LOADING (zic1 fork) =====
local Library = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/Library.lua'))()
local ThemeManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/addons/SaveManager.lua'))()

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

-- ===== CHANT PACKAGE LIST (FIXED: ScottishRSG not ScottishRSC) =====
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
    toggleKey = "Delete",
    smoothing = 0.3,
    wallCheck = false,
    prediction = 0.15,
    bulletVelocity = WEAPON_SETTINGS.Velocity,
    bulletDrop = 5,
    autoPrediction = true,
    gravityCompensation = 1.0,
    autoCalibration = true,
    adaptiveCalibration = true,
    calibrationRate = 0.05,
    hitboxEnabled = false,
    hitboxSize = 1.5,
    hitboxColor = Color3.fromRGB(255, 0, 0),
    hitboxTransparency = 0.5,
    hitboxTeamCheck = false,
    hitboxPart = "Head",
    chantPackage = "English",
    velocityDeviation = WEAPON_SETTINGS.VelocityDeviation,
}

-- ===== STATE =====
local fovCircle = nil
local lastTargetPos = {}
local targetVelocities = {}
local hitRemote = nil
local remoteConnection = nil
local fastCastHooked = false
local playerHitboxes = {}
local originalFireServer = nil
local isUILoaded = false

-- ===== CONNECTIONS =====
local connections = {
    renderStepped = nil,
    velocityLoop = nil,
    characterAdded = nil,
    hitboxUpdate = nil,
    toggleKeybind = nil,
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
    calibrationTarget = "prediction",
    calibrationValues = {
        prediction = { min = 0.05, max = 0.5, current = config.prediction },
        bulletDrop = { min = 0, max = 30, current = config.bulletDrop },
        bulletVelocity = { min = 100, max = 2000, current = config.bulletVelocity },
        gravityCompensation = { min = 0.5, max = 1.5, current = config.gravityCompensation }
    },
    remoteFound = false,
    remoteName = nil,
}

-- ===== CHANT CHANGER (FIXED: Uses ObjectValue) =====
local function setChantPackage(packageName)
    if not plr or not packageName then return end
    
    -- Get the ChantPackage ObjectValue
    local chantValue = plr:FindFirstChild("ChantPackage")
    if not chantValue and plr.Character then
        chantValue = plr.Character:FindFirstChild("ChantPackage")
    end
    
    if chantValue then
        -- Find the chant object in ReplicatedStorage.Chants
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
        -- Create the ObjectValue if it doesn't exist
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
        -- Get the name from the ObjectValue
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
    return player.Character:FindFirstChild(config.aimPart) or player.Character:FindFirstChild("Head")
end

local function shouldExtendHitbox(player)
    if not player or player == plr then return false end
    if not player.Character then return false end
    if config.hitboxTeamCheck and player.Team == plr.Team then return false end
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    return true
end

local function getPlayerFromPart(part)
    if not part then return nil end
    for player, data in pairs(playerHitboxes) do
        if data.hitbox == part then return player end
    end
    local character = part.Parent
    while character do
        if character:IsA("Model") and character:FindFirstChildOfClass("Humanoid") then
            return Players:GetPlayerFromCharacter(character)
        end
        character = character.Parent
    end
    return nil
end

-- ===== FIRE HIT REMOTE =====
local function fireHitRemote(targetPlayer, hitVelocity)
    if not hitRemote then return end
    if not targetPlayer or not targetPlayer.Character then return end
    local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    pcall(function()
        hitRemote:FireServer(plr, hitVelocity, humanoid)
    end)
end

-- ===== HOOK FASTCASTREDUX =====
local function hookFastCastRedux()
    if fastCastHooked then return true end
    local fastCastModule = ReplicatedStorage:FindFirstChild("Tools")
    if fastCastModule then
        local components = fastCastModule:FindFirstChild("Components")
        if components then
            local muzzle = components:FindFirstChild("Muzzle")
            if muzzle then
                local fastCast = muzzle:FindFirstChild("FastCastRedux")
                if fastCast then
                    local fastCastInstance = nil
                    if fastCast.__index and fastCast.__index.RayHit then
                        fastCastInstance = fastCast
                    end
                    if not fastCastInstance and _G.FastCast then
                        fastCastInstance = _G.FastCast
                    end
                    if fastCastInstance and fastCastInstance.RayHit then
                        local oldRayHit = fastCastInstance.RayHit
                        fastCastInstance.RayHit = function(cast, result, velocity, cosmeticBullet)
                            local hitPart = result and result.Instance
                            local hitPlayer = getPlayerFromPart(hitPart)
                            if hitPlayer and playerHitboxes[hitPlayer] then
                                fireHitRemote(hitPlayer, velocity)
                            end
                            if oldRayHit then
                                return oldRayHit(cast, result, velocity, cosmeticBullet)
                            end
                        end
                        fastCastHooked = true
                        print("FastCastRedux hooked successfully!")
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- ===== HOOK HIT REMOTE =====
local function hookHitRemote()
    if originalFireServer then return true end
    if not hitRemote then return false end
    originalFireServer = hitRemote.FireServer
    hitRemote.FireServer = function(self, ...)
        local args = {...}
        local targetHumanoid = args[3]
        local targetPlayer = targetHumanoid and targetHumanoid.Parent and Players:GetPlayerFromCharacter(targetHumanoid.Parent)
        if targetPlayer and playerHitboxes[targetPlayer] then
            print("Hit on extended hitbox: " .. targetPlayer.Name)
        end
        if originalFireServer then
            return originalFireServer(self, ...)
        end
    end
    print("Hit remote hooked!")
    return true
end

-- ===== HITBOX EXTENDER =====
local function createHitboxForPlayer(player)
    if not player or not player.Character then return end
    removeHitboxForPlayer(player)
    local targetPart = getTargetPart(player)
    if not targetPart then return end
    
    local hitbox = Instance.new("Part")
    hitbox.Name = "ExtendedHitbox"
    hitbox.Anchored = false
    hitbox.CanCollide = true
    hitbox.Massless = true
    hitbox.Transparency = config.hitboxTransparency
    hitbox.Color = config.hitboxColor
    hitbox.Material = Enum.Material.Neon
    hitbox.Size = targetPart.Size * config.hitboxSize
    
    local weld = Instance.new("Weld")
    weld.Part0 = targetPart
    weld.Part1 = hitbox
    weld.C0 = CFrame.new(0, 0, 0)
    weld.Parent = hitbox
    hitbox.Parent = player.Character
    
    local connection = hitbox.Touched:Connect(function(hit)
        if hit and hit.Parent then
            local isBullet = hit.Name:match("Bullet") or hit.Name:match("Projectile")
            if isBullet then
                local velocity = Vector3.new(0, 0, 0)
                local velProp = hit:FindFirstChild("Velocity")
                if velProp then
                    if type(velProp.Value) == "Vector3" then
                        velocity = velProp.Value
                    elseif type(velProp.Value) == "number" then
                        local dir = (hit.Position - hit.Parent.Position).Unit
                        velocity = dir * velProp.Value
                    end
                end
                fireHitRemote(player, velocity)
            end
        end
    end)
    
    playerHitboxes[player] = { hitbox = hitbox, weld = weld, targetPart = targetPart, connection = connection }
end

local function removeHitboxForPlayer(player)
    if playerHitboxes[player] then
        if playerHitboxes[player].hitbox then
            pcall(function() playerHitboxes[player].hitbox:Destroy() end)
        end
        if playerHitboxes[player].connection then
            pcall(function() playerHitboxes[player].connection:Disconnect() end)
        end
        playerHitboxes[player] = nil
    end
end

local function updateAllHitboxes()
    for player, _ in pairs(playerHitboxes) do
        if not player or not player.Parent or not shouldExtendHitbox(player) then
            removeHitboxForPlayer(player)
        end
    end
    if config.hitboxEnabled then
        for _, player in ipairs(Players:GetPlayers()) do
            if shouldExtendHitbox(player) and not playerHitboxes[player] then
                createHitboxForPlayer(player)
            end
        end
    end
end

-- ===== FIND HIT REMOTE =====
local function findHitRemote()
    local tools = ReplicatedStorage:FindFirstChild("Tools")
    if tools then
        local components = tools:FindFirstChild("Components")
        if components then
            local muzzle = components:FindFirstChild("Muzzle")
            if muzzle then
                hitRemote = muzzle:FindFirstChild("Hit")
                if hitRemote then
                    autoCalc.remoteFound = true
                    autoCalc.remoteName = hitRemote.Name
                    print("Found Hit remote!")
                    return true
                end
            end
        end
    end
    return false
end

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

-- ===== TRACK TARGET VELOCITIES =====
local function updateTargetVelocities()
    local dt = 0.05
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr and player.Character and player.Character.Parent then
            local targetPart = getTargetPart(player)
            if targetPart and targetPart.Parent then
                local currentPos = targetPart.Position
                if lastTargetPos[player] then
                    local delta = currentPos - lastTargetPos[player]
                    if targetVelocities[player] then
                        targetVelocities[player] = targetVelocities[player] * 0.7 + (delta / dt) * 0.3
                    else
                        targetVelocities[player] = delta / dt
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

-- ===== PREDICT POSITION =====
local function predictPosition(targetPart, player)
    if not targetPart or not targetPart.Parent then
        return targetPart and targetPart.Position or Vector3.new(0, 0, 0)
    end
    
    local basePosition = targetPart.Position
    local cameraPos = Camera.CFrame.Position
    local distance = (basePosition - cameraPos).Magnitude
    local bulletVelocity = config.bulletVelocity or WEAPON_SETTINGS.Velocity
    local bulletTravelTime = math.clamp(distance / bulletVelocity, 0.01, 3)
    local pingComp = autoCalc.ping or 0.05
    
    if config.autoPrediction and targetVelocities[player] then
        local velocity = targetVelocities[player]
        if velocity and velocity.Magnitude > 1 then
            local leadTime = bulletTravelTime * config.prediction + pingComp
            local speedMult = math.min(velocity.Magnitude / 30, 2)
            leadTime = leadTime * (1 + speedMult * 0.3)
            basePosition = basePosition + (velocity * leadTime)
        end
    end
    
    if config.bulletDrop > 0 then
        local predDist = (basePosition - cameraPos).Magnitude
        local travelTime = math.clamp(predDist / bulletVelocity, 0.01, 3)
        local drop = 0.5 * config.bulletDrop * travelTime * travelTime
        drop = drop * config.gravityCompensation
        basePosition = basePosition + Vector3.new(0, drop, 0)
    end
    
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
                        if toTarget:Dot(Camera.CFrame.LookVector) < 0 then continue end
                        
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

-- ===== FOV CIRCLE =====
local function createFOVCircle()
    if fovCircle then pcall(function() fovCircle:Destroy() end) end
    fovCircle = Instance.new("ScreenGui")
    fovCircle.Name = "FOVCircle"
    fovCircle.Parent = game:GetService("CoreGui")
    fovCircle.Enabled = config.showFOV and config.enabled
    fovCircle.ResetOnSpawn = false
    
    local outline = Instance.new("ImageLabel")
    outline.Name = "CircleOutline"
    outline.Size = UDim2.new(0, config.fovRadius * 2, 0, config.fovRadius * 2)
    outline.AnchorPoint = Vector2.new(0.5, 0.5)
    outline.BackgroundTransparency = 1
    outline.BorderSizePixel = 0
    outline.Image = "rbxassetid://10891594364"
    outline.ImageColor3 = config.fovColor
    outline.ImageTransparency = config.fovTransparency
    outline.ScaleType = Enum.ScaleType.Fit
    outline.Parent = fovCircle
    
    local centerDot = Instance.new("ImageLabel")
    centerDot.Name = "CenterDot"
    centerDot.Size = UDim2.new(0, 4, 0, 4)
    centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
    centerDot.BackgroundTransparency = 1
    centerDot.BorderSizePixel = 0
    centerDot.Image = "rbxassetid://10891594364"
    centerDot.ImageColor3 = config.fovColor
    centerDot.ImageTransparency = 0
    centerDot.ScaleType = Enum.ScaleType.Fit
    centerDot.Parent = fovCircle
end

local function updateFOVPosition()
    if not fovCircle or not fovCircle.Enabled then return end
    local mousePos = UserInputService:GetMouseLocation()
    local outline = fovCircle:FindFirstChild("CircleOutline")
    local centerDot = fovCircle:FindFirstChild("CenterDot")
    if outline then outline.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y) end
    if centerDot then centerDot.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y) end
end

-- ===== CLEANUP =====
local function cleanup()
    print("Cleaning up...")
    if originalFireServer and hitRemote then
        pcall(function() hitRemote.FireServer = originalFireServer end)
        originalFireServer = nil
    end
    if remoteConnection then pcall(function() remoteConnection:Disconnect() end) remoteConnection = nil end
    if connections.toggleKeybind then pcall(function() connections.toggleKeybind:Disconnect() end) end
    if connections.renderStepped then pcall(function() connections.renderStepped:Disconnect() end) end
    if connections.velocityLoop then pcall(function() connections.velocityLoop:Disconnect() end) end
    if connections.characterAdded then pcall(function() connections.characterAdded:Disconnect() end) end
    if connections.hitboxUpdate then pcall(function() connections.hitboxUpdate:Disconnect() end) end
    
    for _, data in pairs(playerHitboxes) do
        if data.hitbox then pcall(function() data.hitbox:Destroy() end) end
        if data.connection then pcall(function() data.connection:Disconnect() end) end
    end
    playerHitboxes = {}
    
    if fovCircle then pcall(function() fovCircle:Destroy() end) fovCircle = nil end
    if Window then pcall(function() Library:Unload() end) end
    
    lastTargetPos = {}
    targetVelocities = {}
    fastCastHooked = false
    config.enabled = false
    config.hitboxEnabled = false
    print("Cleanup complete!")
end

-- ===== CREATE UI =====
local Window = Library:CreateWindow({
    Title = "Silent Aim",
    Center = true,
    AutoShow = true,
    Resizable = true,
    ShowCustomCursor = true,
    ToggleKey = Enum.KeyCode.RightShift,
})

local MainTab = Window:AddTab("Main")
local PredictionTab = Window:AddTab("Prediction")
local HitboxTab = Window:AddTab("Hitbox")
local ChantTab = Window:AddTab("Chant")
local SettingsTab = Window:AddTab("Settings")

-- ===== MAIN TAB =====
local MainGroup = MainTab:AddLeftGroupbox("Silent Aim")

MainGroup:AddToggle("Enabled", {
    Text = "Enabled",
    Default = config.enabled,
    Callback = function(v)
        config.enabled = v
        if fovCircle then fovCircle.Enabled = config.showFOV and v end
    end
})

MainGroup:AddSlider("FOVRadius", {
    Text = "FOV Radius",
    Default = config.fovRadius,
    Min = 30,
    Max = 500,
    Rounding = 0,
    Callback = function(v)
        config.fovRadius = v
        local outline = fovCircle and fovCircle:FindFirstChild("CircleOutline")
        if outline then outline.Size = UDim2.new(0, v * 2, 0, v * 2) end
    end
})

MainGroup:AddToggle("TeamCheck", {
    Text = "Team Check",
    Default = config.teamCheck,
    Callback = function(v) config.teamCheck = v end
})

MainGroup:AddDropdown("AimPart", {
    Text = "Aim Part",
    Values = {"Head", "Torso", "HumanoidRootPart"},
    Default = 1,
    Callback = function(v) config.aimPart = v end
})

MainGroup:AddToggle("WallCheck", {
    Text = "Wall Check",
    Default = config.wallCheck,
    Callback = function(v) config.wallCheck = v end
})

MainGroup:AddSlider("Smoothing", {
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
    Text = "Auto Prediction",
    Default = config.autoPrediction,
    Callback = function(v) config.autoPrediction = v end
})

PredictionGroup:AddSlider("PredictionMultiplier", {
    Text = "Prediction Multiplier",
    Default = config.prediction,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(v)
        config.prediction = v
        autoCalc.calibrationValues.prediction.current = v
    end
})

PredictionGroup:AddSlider("BulletVelocity", {
    Text = "Bullet Velocity (Musket: 1300)",
    Default = config.bulletVelocity,
    Min = 100,
    Max = 2000,
    Rounding = 0,
    Callback = function(v)
        config.bulletVelocity = v
        autoCalc.calibrationValues.bulletVelocity.current = v
    end
})

PredictionGroup:AddSlider("BulletDrop", {
    Text = "Bullet Drop (Gravity)",
    Default = config.bulletDrop,
    Min = 0,
    Max = 50,
    Rounding = 0,
    Callback = function(v)
        config.bulletDrop = v
        autoCalc.calibrationValues.bulletDrop.current = v
    end
})

PredictionGroup:AddSlider("DropCompensation", {
    Text = "Drop Compensation",
    Default = config.gravityCompensation,
    Min = 0.5,
    Max = 1.5,
    Rounding = 2,
    Callback = function(v)
        config.gravityCompensation = v
        autoCalc.calibrationValues.gravityCompensation.current = v
    end
})

PredictionGroup:AddLabel("Weapon Info")
PredictionGroup:AddLabel("Musket Velocity: 1300 studs/s")
PredictionGroup:AddLabel("Velocity Deviation: ±60")
PredictionGroup:AddLabel("Base Damage: 100 | Min: 80")
PredictionGroup:AddLabel("Effective Range: 250-600 studs")

-- ===== HITBOX TAB =====
local HitboxGroup = HitboxTab:AddLeftGroupbox("Hitbox Extender")

HitboxGroup:AddToggle("HitboxEnabled", {
    Text = "Hitbox Extender",
    Default = config.hitboxEnabled,
    Callback = function(v)
        config.hitboxEnabled = v
        if v then
            updateAllHitboxes()
            hookFastCastRedux()
            hookHitRemote()
        else
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
        end
    end
})

HitboxGroup:AddSlider("HitboxSize", {
    Text = "Hitbox Size",
    Default = config.hitboxSize,
    Min = 0.5,
    Max = 50,
    Rounding = 1,
    Callback = function(v)
        config.hitboxSize = v
        if config.hitboxEnabled then
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
            updateAllHitboxes()
        end
    end
})

local colorLabel = HitboxGroup:AddLabel("Hitbox Color")
colorLabel:AddColorPicker("HitboxColor", {
    Default = config.hitboxColor,
    Callback = function(v)
        config.hitboxColor = v
        for _, data in pairs(playerHitboxes) do
            if data.hitbox then pcall(function() data.hitbox.Color = v end) end
        end
    end
})

HitboxGroup:AddSlider("HitboxTransparency", {
    Text = "Hitbox Transparency",
    Default = config.hitboxTransparency,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(v)
        config.hitboxTransparency = v
        for _, data in pairs(playerHitboxes) do
            if data.hitbox then pcall(function() data.hitbox.Transparency = v end) end
        end
    end
})

HitboxGroup:AddToggle("HitboxTeamCheck", {
    Text = "Team Check",
    Default = config.hitboxTeamCheck,
    Callback = function(v)
        config.hitboxTeamCheck = v
        if config.hitboxEnabled then
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
            updateAllHitboxes()
        end
    end
})

HitboxGroup:AddDropdown("HitboxPart", {
    Text = "Target Part",
    Values = {"Head", "Torso", "HumanoidRootPart"},
    Default = 1,
    Callback = function(v)
        config.hitboxPart = v
        if config.hitboxEnabled then
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
            updateAllHitboxes()
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

local keyLabel = SettingsGroup:AddLabel("Toggle Key")
keyLabel:AddKeyPicker("ToggleKey", {
    Text = "Toggle Key",
    Default = "Delete",
    Mode = "Toggle",
    ChangedCallback = function(v)
        config.toggleKey = v
        if connections.toggleKeybind then
            connections.toggleKeybind:Disconnect()
        end
        connections.toggleKeybind = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == Enum.KeyCode[v] then
                config.enabled = not config.enabled
                if fovCircle then fovCircle.Enabled = config.showFOV and config.enabled end
            end
        end)
    end
})

local ActionsGroup = SettingsTab:AddRightGroupbox("Actions")

ActionsGroup:AddButton({
    Text = "Refresh Hitboxes",
    Func = function()
        if config.hitboxEnabled then
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
            updateAllHitboxes()
            hookFastCastRedux()
            hookHitRemote()
            print("Hitboxes refreshed!")
        end
    end
})

ActionsGroup:AddButton({
    Text = "Force Hook FastCast",
    Func = function()
        local success = hookFastCastRedux()
        print(success and "FastCast hooked!" or "Failed to hook FastCast")
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

connections.toggleKeybind = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode[config.toggleKey] then
        config.enabled = not config.enabled
        if fovCircle then fovCircle.Enabled = config.showFOV and config.enabled end
    end
end)

task.wait(1)
findHitRemote()

if config.hitboxEnabled then
    task.wait(0.5)
    hookFastCastRedux()
    hookHitRemote()
end

connections.renderStepped = RunService.RenderStepped:Connect(function()
    pcall(onRenderStepped)
    pcall(updateFOVPosition)
end)

connections.velocityLoop = task.spawn(function()
    while task.wait(0.05) do
        pcall(updateTargetVelocities)
    end
end)

connections.hitboxUpdate = task.spawn(function()
    while task.wait(1) do
        if config.hitboxEnabled then
            pcall(updateAllHitboxes)
        end
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
end)

Players.PlayerAdded:Connect(function(player)
    if config.hitboxEnabled then
        task.wait(0.5)
        if shouldExtendHitbox(player) then
            createHitboxForPlayer(player)
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if playerHitboxes[player] then
        removeHitboxForPlayer(player)
    end
end)

-- Initialize chant
task.wait(0.5)
initChantPackage()

print("Silent Aim loaded successfully!")
print("Musket Settings Applied:")
print("  Velocity: " .. WEAPON_SETTINGS.Velocity .. " studs/s")
print("  Deviation: ±" .. WEAPON_SETTINGS.VelocityDeviation)
print("  Damage: " .. WEAPON_SETTINGS.BaseDamage .. "-" .. WEAPON_SETTINGS.MinDamage)
print("  Range: " .. WEAPON_SETTINGS.BaseDmgDistance .. "-" .. WEAPON_SETTINGS.MinDmgDistance .. " studs")
print("Press " .. config.toggleKey .. " to toggle")
print("Press RightShift to toggle menu")
