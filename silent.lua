-- ===== LINORIA LIBRARY LOADING (zic1 fork) =====
local Library = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/Library.lua'))()
local ThemeManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/zic1/LinoriaLib/refs/heads/main/addons/SaveManager.lua'))()

-- ===== ESP LIBRARY LOADING =====
local esplib = loadstring(game:HttpGet("https://raw.githubusercontent.com/tulontop/esp-lib.lua/refs/heads/main/source.lua"))()

-- ===== ESP CONFIGURATION =====
getgenv().esplib = {
    box = {
        enabled = true,
        type = "normal",
        padding = 1.15,
        fill = Color3.new(1, 1, 1),
        outline = Color3.new(0, 0, 0),
    },
    healthbar = {
        enabled = true,
        fill = Color3.new(0, 1, 0),
        outline = Color3.new(0, 0, 0),
    },
    name = {
        enabled = true,
        fill = Color3.new(1, 1, 1),
        size = 13,
    },
    distance = {
        enabled = true,
        fill = Color3.new(1, 1, 1),
        size = 13,
    },
    tracer = {
        enabled = false,
        fill = Color3.new(1, 1, 1),
        outline = Color3.new(0, 0, 0),
        from = "bottom",
    },
}

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
    hitboxSize = 1.5,
    hitboxColor = Color3.fromRGB(255, 0, 0),
    hitboxTransparency = 0.5,
    hitboxTeamCheck = false,
    hitboxPart = "Head",
    chantPackage = "English",
    velocityDeviation = WEAPON_SETTINGS.VelocityDeviation,
    debugMode = false,
    
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

-- ===== ESP STATE =====
local espObjects = {}
local espEnabledPlayers = {}

-- ===== CONNECTIONS (FOR CLEANUP) =====
local connections = {
    renderStepped = nil,
    velocityLoop = nil,
    characterAdded = nil,
    hitboxUpdate = nil,
    toggleKeybind = nil,
    espUpdate = nil,
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
        bulletDrop = { min = 0, max = 250, current = config.bulletDrop },
        bulletVelocity = { min = 100, max = 2000, current = config.bulletVelocity },
        gravityCompensation = { min = 0.5, max = 3.0, current = config.gravityCompensation }
    },
    remoteFound = false,
    remoteName = nil,
}

-- ===== FOV CIRCLE (DRAWING API) =====
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

-- ===== CLEANUP FUNCTION =====
local function cleanup()
    print("Cleaning up VaM Client...")
    
    if fovCircle then
        pcall(function() fovCircle:Remove() end)
        fovCircle = nil
    end
    
    for player, _ in pairs(espEnabledPlayers) do
        espEnabledPlayers[player] = nil
    end
    espObjects = {}
    
    if originalFireServer and hitRemote then
        pcall(function()
            hitRemote.FireServer = originalFireServer
        end)
        originalFireServer = nil
    end
    
    if remoteConnection then
        pcall(function()
            remoteConnection:Disconnect()
        end)
        remoteConnection = nil
    end
    
    if connections.toggleKeybind then
        pcall(function()
            connections.toggleKeybind:Disconnect()
        end)
        connections.toggleKeybind = nil
    end
    
    if connections.renderStepped then
        pcall(function()
            connections.renderStepped:Disconnect()
        end)
        connections.renderStepped = nil
    end
    
    if connections.velocityLoop then
        pcall(function()
            connections.velocityLoop:Disconnect()
        end)
        connections.velocityLoop = nil
    end
    
    if connections.characterAdded then
        pcall(function()
            connections.characterAdded:Disconnect()
        end)
        connections.characterAdded = nil
    end
    
    if connections.hitboxUpdate then
        pcall(function()
            connections.hitboxUpdate:Disconnect()
        end)
        connections.hitboxUpdate = nil
    end
    
    if connections.espUpdate then
        pcall(function()
            connections.espUpdate:Disconnect()
        end)
        connections.espUpdate = nil
    end
    
    for _, data in pairs(playerHitboxes) do
        if data.hitbox then
            pcall(function()
                data.hitbox:Destroy()
            end)
        end
        if data.connection then
            pcall(function()
                data.connection:Disconnect()
            end)
        end
    end
    playerHitboxes = {}
    
    if Window then
        pcall(function()
            Library:Unload()
        end)
        Window = nil
    end
    
    lastTargetPos = {}
    targetVelocities = {}
    fastCastHooked = false
    config.enabled = false
    config.hitboxEnabled = false
    config.espEnabled = false
    
    print("Cleanup complete! VaM Client fully unloaded.")
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
    
    print("Attempting to hook FastCastRedux...")
    
    local fastCastModule = ReplicatedStorage:FindFirstChild("Tools")
    if fastCastModule then
        local components = fastCastModule:FindFirstChild("Components")
        if components then
            local muzzle = components:FindFirstChild("Muzzle")
            if muzzle then
                local fastCastScript = muzzle:FindFirstChild("FastCastRedux")
                if fastCastScript then
                    print("Found FastCastRedux module script!")
                    
                    local success, fastCast = pcall(function()
                        return require(fastCastScript)
                    end)
                    
                    if success and fastCast then
                        print("FastCastRedux module required successfully!")
                        
                        local fastCastInstance = nil
                        
                        if fastCast.RayHit then
                            fastCastInstance = fastCast
                            print("Method 1: Using required module directly")
                        end
                        
                        if not fastCastInstance and _G.FastCast and _G.FastCast.RayHit then
                            fastCastInstance = _G.FastCast
                            print("Method 2: Found global FastCast instance")
                        end
                        
                        if not fastCastInstance then
                            for _, obj in ipairs(Workspace:GetDescendants()) do
                                if obj:IsA("ModuleScript") and obj.Name == "FastCastRedux" then
                                    local s, r = pcall(function()
                                        return require(obj)
                                    end)
                                    if s and r and r.RayHit then
                                        fastCastInstance = r
                                        print("Method 3: Found FastCast instance via workspace search")
                                        break
                                    end
                                end
                            end
                        end
                        
                        if not fastCastInstance and fastCast.new then
                            local oldNew = fastCast.new
                            fastCast.new = function(...)
                                local instance = oldNew(...)
                                if instance and instance.RayHit then
                                    local oldRayHit = instance.RayHit
                                    instance.RayHit = function(cast, result, velocity, cosmeticBullet)
                                        local hitPart = result and result.Instance
                                        local hitPlayer = getPlayerFromPart(hitPart)
                                        if hitPlayer and playerHitboxes[hitPlayer] then
                                            print("FastCast hit extended hitbox: " .. hitPlayer.Name)
                                            fireHitRemote(hitPlayer, velocity)
                                        end
                                        if oldRayHit then
                                            return oldRayHit(cast, result, velocity, cosmeticBullet)
                                        end
                                    end
                                end
                                return instance
                            end
                            fastCastHooked = true
                            print("FastCastRedux .new() hooked successfully!")
                            return true
                        end
                        
                        if fastCastInstance and fastCastInstance.RayHit then
                            print("Hooking FastCastRedux RayHit event...")
                            
                            local oldRayHit = fastCastInstance.RayHit
                            fastCastInstance.RayHit = function(cast, result, velocity, cosmeticBullet)
                                local hitPart = result and result.Instance
                                local hitPlayer = getPlayerFromPart(hitPart)
                                if hitPlayer and playerHitboxes[hitPlayer] then
                                    print("FastCast hit extended hitbox: " .. hitPlayer.Name)
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
                    else
                        print("Failed to require FastCastRedux module.")
                    end
                end
            end
        end
    end
    
    print("Failed to hook FastCastRedux.")
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
    if not targetPart then 
        print("No target part found for: " .. player.Name)
        return 
    end
    
    local hitbox = Instance.new("Part")
    hitbox.Name = "ExtendedHitbox"
    hitbox.Anchored = false
    hitbox.CanCollide = true
    hitbox.Massless = true
    hitbox.Transparency = config.hitboxTransparency or 0.5
    hitbox.Color = config.hitboxColor or Color3.fromRGB(255, 0, 0)
    hitbox.Material = Enum.Material.Neon
    hitbox.Size = targetPart.Size * (config.hitboxSize or 1.5)
    
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
    print("Created hitbox for: " .. player.Name)
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
        print("Removed hitbox for: " .. player.Name)
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

-- ===== IMPROVED VELOCITY TRACKING =====
local function updateTargetVelocities()
    local dt = 0.05
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr and player.Character and player.Character.Parent then
            local isMounted = false
            if player.Character:FindFirstChild("Horse") or 
               player.Character:FindFirstChild("Vehicle") or
               player.Character:FindFirstChild("Mount") then
                isMounted = true
            end
            
            local targetPart = getTargetPart(player)
            if targetPart and targetPart.Parent then
                local currentPos = targetPart.Position
                if lastTargetPos[player] then
                    local delta = currentPos - lastTargetPos[player]
                    local rawVelocity = delta / dt
                    
                    if targetVelocities[player] then
                        local smoothingFactor = isMounted and 0.5 or 0.7
                        targetVelocities[player] = targetVelocities[player] * smoothingFactor + rawVelocity * (1 - smoothingFactor)
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

-- ===== ESP FUNCTIONS (Using esp-lib.lua) =====
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
        local hitPlayer = getPlayerFromPart(result.Instance)
        if hitPlayer == player then
            return false
        end
        
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

local function updateESPColors()
    local espSettings = getgenv().esplib
    if not espSettings then return end
    
    espSettings.box.fill = config.espBoxColor
    espSettings.healthbar.fill = config.espHealthColor
    espSettings.name.fill = config.espNameColor
    espSettings.distance.fill = config.espDistanceColor
    espSettings.tracer.fill = config.espTracerColor
end

local function getESPColorForPlayer(player)
    if not player then return config.espBoxColor
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
        return config.espBoxColor
    end
end
local function refreshESPForPlayer(player)
    if not player or player == plr then return end
    if espEnabledPlayers[player] then
        removeESPForPlayer(player)
    end
    if config.espEnabled then
        setupESPForPlayer(player)
    end
end

local function setupESPForPlayer(player)
    if player == plr then return end
    if espEnabledPlayers[player] then return end
    
    local function shouldShowESP()
        if not player or not player.Character then return false end
        if config.espTeamCheck and player.Team == plr.Team then return false end
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return false end
        return true
    end
    
    if not shouldShowESP() then
        return
    end
    
    local character = player.Character
    if not character then return end
    
    updateESPColors()
    
    local playerColor = getESPColorForPlayer(player)
    local espSettings = getgenv().esplib
    local originalBoxColor = espSettings.box.fill
    local originalNameColor = espSettings.name.fill
    local originalDistColor = espSettings.distance.fill
    
    espSettings.box.fill = playerColor
    espSettings.name.fill = playerColor
    espSettings.distance.fill = playerColor
    
    if config.espBoxEnabled then
        esplib.add_box(character)
    end
    if config.espHealthbarEnabled then
        esplib.add_healthbar(character)
    end
    if config.espNameEnabled then
        esplib.add_name(character)
    end
    if config.espDistanceEnabled then
        esplib.add_distance(character)
    end
    if config.espTracerEnabled then
        esplib.add_tracer(character)
    end
    
    espSettings.box.fill = originalBoxColor
    espSettings.name.fill = originalNameColor
    espSettings.distance.fill = originalDistColor
    
    espEnabledPlayers[player] = true
    
    if not espObjects[player] then
        espObjects[player] = {}
    end
    
    if not espObjects[player].connection then
        espObjects[player].connection = player.CharacterAdded:Connect(function(newCharacter)
            task.wait(0.5)
            if shouldShowESP() then
                updateESPColors()
                local newColor = getESPColorForPlayer(player)
                espSettings.box.fill = newColor
                espSettings.name.fill = newColor
                espSettings.distance.fill = newColor
                
                if config.espBoxEnabled then
                    esplib.add_box(newCharacter)
                end
                if config.espHealthbarEnabled then
                    esplib.add_healthbar(newCharacter)
                end
                if config.espNameEnabled then
                    esplib.add_name(newCharacter)
                end
                if config.espDistanceEnabled then
                    esplib.add_distance(newCharacter)
                end
                if config.espTracerEnabled then
                    esplib.add_tracer(newCharacter)
                end
                
                espSettings.box.fill = originalBoxColor
                espSettings.name.fill = originalNameColor
                espSettings.distance.fill = originalDistColor
            end
        end)
    end
end

local function removeESPForPlayer(player)
    if not espEnabledPlayers[player] then return end
    espEnabledPlayers[player] = nil
    
    if espObjects[player] then
        if espObjects[player].connection then
            pcall(function()
                espObjects[player].connection:Disconnect()
            end)
        end
        espObjects[player] = nil
    end
end

local function updateAllESP()
    updateESPColors()
    
    for player, _ in pairs(espEnabledPlayers) do
        if not player or not player.Parent or player == plr then
            removeESPForPlayer(player)
            continue
        end
        
        if not player.Character then
            removeESPForPlayer(player)
            continue
        end
        
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            removeESPForPlayer(player)
            continue
        end
        
        if config.espTeamCheck and player.Team == plr.Team then
            removeESPForPlayer(player)
            continue
        end
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr and player.Character and player.Character.Parent then
            if config.espTeamCheck and player.Team == plr.Team then
                if espEnabledPlayers[player] then
                    removeESPForPlayer(player)
                end
                continue
            end
            
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                if not espEnabledPlayers[player] then
                    setupESPForPlayer(player)
                end
            else
                if espEnabledPlayers[player] then
                    removeESPForPlayer(player)
                end
            end
        end
    end
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

-- ===== CREATE TABS =====
local SilentAimTab = Window:AddTab("Silent Aim")
local PredictionTab = Window:AddTab("Prediction")
local ESPTab = Window:AddTab("ESP")
local HitboxTab = Window:AddTab("Hitbox")
local ChantTab = Window:AddTab("Chant")
local SettingsTab = Window:AddTab("Settings")

-- ===== SILENT AIM TAB =====
local SilentAimGroup = SilentAimTab:AddLeftGroupbox("Silent Aim")

SilentAimGroup:AddToggle("Enabled", {
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
    Text = "Auto Prediction",
    Default = config.autoPrediction,
    Callback = function(v) config.autoPrediction = v end
})

PredictionGroup:AddToggle("AutoBulletDrop", {
    Text = "Auto Bullet Drop",
    Desc = "Automatically calculate bullet drop compensation based on distance, velocity, and gravity",
    Default = config.autoBulletDrop,
    Callback = function(v)
        config.autoBulletDrop = v
        print("Auto bullet drop: " .. (v and "ON" or "OFF"))
    end
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
    Desc = "Gravitational acceleration in studs/s². Normal Roblox gravity is 196.2",
    Default = config.bulletDrop,
    Min = 0,
    Max = 250,
    Rounding = 1,
    Callback = function(v)
        config.bulletDrop = v
        autoCalc.calibrationValues.bulletDrop.current = v
    end
})

PredictionGroup:AddSlider("DropCompensation", {
    Text = "Drop Compensation",
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
PredictionGroup:AddLabel("Velocity Deviation: ±60 (speed variation)")
PredictionGroup:AddLabel("Deviation: 1.7 (accuracy/spread)")
PredictionGroup:AddLabel("Base Damage: 100 | Min: 80")
PredictionGroup:AddLabel("Effective Range: 250-600 studs")

-- ===== ESP TAB =====
local ESPGroup = ESPTab:AddLeftGroupbox("ESP Settings")

ESPGroup:AddToggle("ESPEnabled", {
    Text = "ESP Enabled",
    Default = config.espEnabled,
    Callback = function(v)
        config.espEnabled = v
        if v then
            updateAllESP()
        else
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
        end
    end
})

ESPGroup:AddToggle("ESPTeamCheck", {
    Text = "Team Check",
    Default = config.espTeamCheck,
    Callback = function(v)
        config.espTeamCheck = v
        if config.espEnabled then
            updateAllESP()
        end
    end
})

ESPGroup:AddToggle("ESPWallCheck", {
    Text = "Wall Check",
    Desc = "Change ESP colors when players are behind walls",
    Default = config.espWallCheck,
    Callback = function(v)
        config.espWallCheck = v
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
        end
    end
})

ESPGroup:AddDivider()
ESPGroup:AddLabel("ESP Elements")

ESPGroup:AddToggle("ESPBoxEnabled", {
    Text = "Bounding Box",
    Default = config.espBoxEnabled,
    Callback = function(v)
        config.espBoxEnabled = v
        getgenv().esplib.box.enabled = v
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
        end
    end
})

ESPGroup:AddToggle("ESPHealthbarEnabled", {
    Text = "Health Bar",
    Default = config.espHealthbarEnabled,
    Callback = function(v)
        config.espHealthbarEnabled = v
        getgenv().esplib.healthbar.enabled = v
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
        end
    end
})

ESPGroup:AddToggle("ESPNameEnabled", {
    Text = "Player Names",
    Default = config.espNameEnabled,
    Callback = function(v)
        config.espNameEnabled = v
        getgenv().esplib.name.enabled = v
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
        end
    end
})

ESPGroup:AddToggle("ESPDistanceEnabled", {
    Text = "Distance",
    Default = config.espDistanceEnabled,
    Callback = function(v)
        config.espDistanceEnabled = v
        getgenv().esplib.distance.enabled = v
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
        end
    end
})

ESPGroup:AddToggle("ESPTracerEnabled", {
    Text = "Tracer",
    Default = config.espTracerEnabled,
    Callback = function(v)
        config.espTracerEnabled = v
        getgenv().esplib.tracer.enabled = v
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
        end
    end
})

ESPGroup:AddDivider()
ESPGroup:AddLabel("Colors")

local visibleColorLabel = ESPGroup:AddLabel("Visible Color")
visibleColorLabel:AddColorPicker("ESPVisibleColor", {
    Default = config.espVisibleColor,
    Callback = function(v)
        config.espVisibleColor = v
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
        end
    end
})

local hiddenColorLabel = ESPGroup:AddLabel("Hidden/Wall Color")
hiddenColorLabel:AddColorPicker("ESPHiddenColor", {
    Default = config.espHiddenColor,
    Callback = function(v)
        config.espHiddenColor = v
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
        end
    end
})

ESPGroup:AddDivider()
ESPGroup:AddLabel("Individual Element Colors (Override)")

local boxColorLabel = ESPGroup:AddLabel("Box Color")
boxColorLabel:AddColorPicker("ESPBoxColor", {
    Default = config.espBoxColor,
    Callback = function(v)
        config.espBoxColor = v
        updateESPColors()
    end
})

local healthColorLabel = ESPGroup:AddLabel("Health Bar Color")
healthColorLabel:AddColorPicker("ESPHealthColor", {
    Default = config.espHealthColor,
    Callback = function(v)
        config.espHealthColor = v
        updateESPColors()
    end
})

local nameColorLabel = ESPGroup:AddLabel("Name Color")
nameColorLabel:AddColorPicker("ESPNameColor", {
    Default = config.espNameColor,
    Callback = function(v)
        config.espNameColor = v
        updateESPColors()
    end
})

local distColorLabel = ESPGroup:AddLabel("Distance Color")
distColorLabel:AddColorPicker("ESPDistanceColor", {
    Default = config.espDistanceColor,
    Callback = function(v)
        config.espDistanceColor = v
        updateESPColors()
    end
})

local tracerColorLabel = ESPGroup:AddLabel("Tracer Color")
tracerColorLabel:AddColorPicker("ESPTracerColor", {
    Default = config.espTracerColor,
    Callback = function(v)
        config.espTracerColor = v
        updateESPColors()
    end
})

ESPGroup:AddButton({
    Text = "Refresh ESP",
    Func = function()
        if config.espEnabled then
            for player, _ in pairs(espEnabledPlayers) do
                removeESPForPlayer(player)
            end
            espEnabledPlayers = {}
            updateAllESP()
            print("ESP refreshed!")
        else
            print("ESP is disabled. Enable it first.")
        end
    end
})

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
        connections.toggleKeybind = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == Enum.KeyCode[keyString] then
                config.enabled = not config.enabled
                if Toggles and Toggles.Enabled then
                    Toggles.Enabled:SetValue(config.enabled)
                end
                if fovCircle then fovCircle.Visible = config.showFOV and config.enabled end
            end
        end)
    end
})

local guiKeyLabel = SettingsGroup:AddLabel("Toggle GUI")
guiKeyLabel:AddKeyPicker("GUIToggleKey", {
    Text = "Toggle GUI",
    Default = config.guiToggleKey,
    Mode = "Toggle",
    ChangedCallback = function(v)
        local keyString = type(v) == "string" and v or tostring(v)
        config.guiToggleKey = keyString
        Window:SetToggleKey(Enum.KeyCode[keyString])
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
        if Toggles and Toggles.Enabled then
            Toggles.Enabled:SetValue(config.enabled)
        end
        if fovCircle then fovCircle.Visible = config.showFOV and config.enabled end
    end
end)

task.wait(1)
findHitRemote()

if config.hitboxEnabled then
    task.wait(0.5)
    hookFastCastRedux()
    hookHitRemote()
end

connections.espUpdate = RunService.RenderStepped:Connect(function()
    if config.espEnabled then
        pcall(updateAllESP)
    end
end)

Players.PlayerAdded:Connect(function(player)
    if config.espEnabled then
        task.wait(0.5)
        pcall(function() setupESPForPlayer(player) end)
    end
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
    if espEnabledPlayers[player] then
        removeESPForPlayer(player)
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
        pcall(updateAllESP)
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

connections.hitboxUpdate = task.spawn(function()
    while task.wait(1) do
        if config.hitboxEnabled then
            pcall(updateAllHitboxes)
        end
    end
end)

task.wait(0.5)
initChantPackage()

print("VaM Client loaded successfully!")
print("Musket Settings Applied:")
print("  Velocity: " .. WEAPON_SETTINGS.Velocity .. " studs/s")
print("  Velocity Deviation: ±" .. WEAPON_SETTINGS.VelocityDeviation .. " (speed variation)")
print("  Deviation: " .. WEAPON_SETTINGS.Deviation .. " (accuracy/spread)")
print("  Damage: " .. WEAPON_SETTINGS.BaseDamage .. "-" .. WEAPON_SETTINGS.MinDamage)
print("  Range: " .. WEAPON_SETTINGS.BaseDmgDistance .. "-" .. WEAPON_SETTINGS.MinDmgDistance .. " studs")
print("Press " .. config.toggleKey .. " to toggle silent aim")
print("Press " .. config.guiToggleKey .. " to toggle GUI")
print("Click 'Unload Script' in the Settings tab to fully unload")
