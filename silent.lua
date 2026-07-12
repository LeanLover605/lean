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

-- ===== HITBOX EXPANSION STATE =====
local Expanded = {}  -- Track which players have expanded hitboxes
local DEFAULT_HRP_SIZE = Vector3.new(2, 2, 1)
local DEFAULT_TRANSPARENCY = 0
local DEFAULT_COLOR = BrickColor.new("Bright blue")
local DEFAULT_MATERIAL = Enum.Material.Plastic
local DEFAULT_COLLIDE = true

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
local Toggles = {}  -- Store toggle references for keybind updates

-- ===== CONNECTIONS (FOR CLEANUP) =====
local connections = {
    renderStepped = nil,
    velocityLoop = nil,
    characterAdded = nil,
    hitboxUpdate = nil,
    toggleKeybind = nil,
    espUpdate = nil,
    mountedCheck = nil,
    autoRefresh = nil,
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
    autoCalcRunning = false,
    lastAutoUpdate = 0,
    autoUpdateInterval = 0.5,
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

-- ===== CLEANUP FUNCTION =====
local function cleanup()
    print("Cleaning up VaM Client...")
    
    if fovCircle then
        pcall(function() fovCircle:Remove() end)
        fovCircle = nil
    end
    
    -- Clean up ESP drawing objects
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
    
    -- Clean up old hitbox system
    for player, _ in pairs(playerHitboxes) do
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
    
    if connections.mountedCheck then
        pcall(function()
            connections.mountedCheck:Disconnect()
        end)
        connections.mountedCheck = nil
    end
    
    if connections.autoRefresh then
        pcall(function()
            connections.autoRefresh:Disconnect()
        end)
        connections.autoRefresh = nil
    end
    
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
    
    return player.Character:FindFirstChild("HumanoidRootPart")
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

-- ===== HITBOX EXPANSION CORE FUNCTIONS =====
local function resetHRP(hrp)
    if not hrp then return end
    pcall(function()
        hrp.Size = DEFAULT_HRP_SIZE
        hrp.Transparency = DEFAULT_TRANSPARENCY
        hrp.BrickColor = DEFAULT_COLOR
        hrp.Material = DEFAULT_MATERIAL
        hrp.CanCollide = DEFAULT_COLLIDE
        hrp.CanQuery = true
    end)
end

local function isMounted(player)
    if not player then return false end
    
    local model = Workspace:FindFirstChild(player.Name)
    if not model then return false end
    
    -- Check for horse mount
    local horse = model:FindFirstChild("Horse")
    if horse and horse:IsA("Model") then
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                resetHRP(hrp)
            end
        end
        return true
    end
    
    -- Check for vehicle seat
    local seat = model:FindFirstChild("Seat")
    if seat and seat:IsA("VehicleSeat") then
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                resetHRP(hrp)
            end
        end
        return true
    end
    
    return false
end

local function applyHitboxExpansion(player)
    if not config.hitboxEnabled then return end
    if not player or not player.Character then return end
    
    -- Team check
    if config.hitboxTeamCheck and player.Team ~= nil and plr.Team ~= nil then
        if player.Team == plr.Team then
            if Expanded[player] then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    resetHRP(hrp)
                end
                Expanded[player] = nil
            end
            return
        end
    end
    
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Check if mounted
    if isMounted(player) then
        Expanded[player] = nil
        return
    end
    
    -- Update size if already expanded
    if Expanded[player] then
        pcall(function()
            hrp.Size = Vector3.new(config.hitboxSize, config.hitboxSize, config.hitboxSize)
        end)
        return
    end
    
    -- Apply hitbox expansion
    pcall(function()
        hrp.Size = Vector3.new(config.hitboxSize, config.hitboxSize, config.hitboxSize)
        hrp.Transparency = config.hitboxTransparency
        hrp.BrickColor = BrickColor.new(config.hitboxColor)
        hrp.Material = Enum.Material.Neon
        hrp.CanCollide = false
        hrp.CanQuery = true
    end)
    
    Expanded[player] = true
    -- print("Expanded hitbox for: " .. player.Name)
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
            applyHitboxExpansion(player)
        end
    end
end

local function onCharacterAddedWithExpansion(player, char)
    Expanded[player] = nil
    
    task.spawn(function()
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            hrp = char:WaitForChild("HumanoidRootPart", 5)
        end
        if hrp then
            applyHitboxExpansion(player)
        end
    end)
    
    -- Monitor workspace folder for mount changes
    task.spawn(function()
        local model = Workspace:FindFirstChild(player.Name)
        if not model then
            model = Workspace:WaitForChild(player.Name, 5)
        end
        if not model then return end
        
        model.ChildAdded:Connect(function(child)
            if child.Name == "Horse" or child.Name == "Seat" then
                if isMounted(player) then
                    Expanded[player] = nil
                end
            end
        end)
        
        model.ChildRemoved:Connect(function(child)
            if child.Name == "Horse" or child.Name == "Seat" then
                task.wait(0.1)
                applyHitboxExpansion(player)
            end
        end)
    end)
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

-- ===== HITBOX EXTENDER (LEGACY - KEPT FOR COMPATIBILITY BUT NOT TRIGGERED) =====
-- [[ LEGACY HITBOX CODE - KEPT BUT DISABLED ]]
local function createHitboxForPlayer(player)
    -- DISABLED - This function is not called anywhere
    -- if not player or not player.Character then return end
    -- removeHitboxForPlayer(player)
    -- local targetPart = getTargetPart(player)
    -- if not targetPart then return end
    -- 
    -- local hitbox = Instance.new("Part")
    -- hitbox.Name = "ExtendedHitbox"
    -- hitbox.Anchored = false
    -- hitbox.CanCollide = false
    -- hitbox.CanQuery = true
    -- hitbox.Massless = true
    -- hitbox.Transparency = config.hitboxTransparency or 0.5
    -- hitbox.Color = config.hitboxColor or Color3.fromRGB(255, 0, 0)
    -- hitbox.Material = Enum.Material.Neon
    -- hitbox.Size = targetPart.Size * (config.hitboxSize or 1.5)
    -- 
    -- local weld = Instance.new("Weld")
    -- weld.Part0 = targetPart
    -- weld.Part1 = hitbox
    -- weld.C0 = CFrame.new(0, 0, 0)
    -- weld.Parent = hitbox
    -- hitbox.Parent = player.Character
    -- 
    -- local connection = hitbox.Touched:Connect(function(hit)
    --     if hit and hit.Parent then
    --         local isBullet = hit.Name:match("Bullet") or hit.Name:match("Projectile")
    --         if isBullet then
    --             local velocity = Vector3.new(0, 0, 0)
    --             local velProp = hit:FindFirstChild("Velocity")
    --             if velProp then
    --                 if type(velProp.Value) == "Vector3" then
    --                     velocity = velProp.Value
    --                 elseif type(velProp.Value) == "number" then
    --                     local dir = (hit.Position - hit.Parent.Position).Unit
    --                     velocity = dir * velProp.Value
    --                 end
    --             end
    --             fireHitRemote(player, velocity)
    --         end
    --     end
    -- end)
    -- 
    -- playerHitboxes[player] = { hitbox = hitbox, weld = weld, targetPart = targetPart, connection = connection }
    -- print("Created hitbox for: " .. player.Name)
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
    -- DISABLED - Legacy hitbox system is disabled
    -- for player, _ in pairs(playerHitboxes) do
    --     if not player or not player.Parent or not shouldExtendHitbox(player) then
    --         removeHitboxForPlayer(player)
    --     end
    -- end
    -- if config.hitboxEnabled then
    --     for _, player in ipairs(Players:GetPlayers()) do
    --         if shouldExtendHitbox(player) and not playerHitboxes[player] then
    --             createHitboxForPlayer(player)
    --         end
    --     end
    -- end
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

-- ===== AUTO-CALCULATE PREDICTION VALUES =====
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
    
    -- ===== AUTO LEAD CALCULATION =====
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
    
    -- ===== AUTO BULLET DROP CALCULATION =====
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
    
    -- ===== MOVEMENT PREDICTION =====
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
    
    -- ===== BULLET DROP COMPENSATION =====
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

-- ===== ESP FUNCTIONS (SMOOTH UPDATES ON RENDERSTEPPED) =====
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

-- ===== GET BOUNDING BOX =====
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

-- ===== CREATE ESP OBJECTS FOR A PLAYER =====
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

-- ===== UPDATE ESP FOR A PLAYER =====
local function updateESPForPlayer(player)
    local espData = espObjects[player]
    if not espData then
        return
    end
    
    if not player or not player.Character then
        -- Hide all ESP elements
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
        -- Hide all ESP elements when off-screen
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

-- ===== UPDATE ALL ESP (CALLED EVERY RENDER STEP) =====
local function updateAllESP()
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
end

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
            if shouldExtendHitbox(player) then
                -- Legacy hitbox is disabled - only use HRP expansion
                -- createHitboxForPlayer(player)
            end
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

-- ===== CREATE TABS =====
local SilentAimTab = Window:AddTab("Silent Aim")
local PredictionTab = Window:AddTab("Prediction")
local ESPTab = Window:AddTab("ESP")
local HitboxTab = Window:AddTab("Hitbox")
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
    Desc = "Automatically calculate bullet drop compensation based on distance, velocity, and gravity",
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

local predictionSlider = PredictionGroup:AddSlider("PredictionMultiplier", {
    Text = "Prediction Multiplier",
    Desc = "How much to lead moving targets (higher = more lead)",
    Default = config.prediction,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(v)
        config.prediction = v
        autoCalc.calibrationValues.prediction.current = v
    end
})
sliderElements.predictionSlider = predictionSlider

local velocitySlider = PredictionGroup:AddSlider("BulletVelocity", {
    Text = "Bullet Velocity (Musket: 1300)",
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
sliderElements.velocitySlider = velocitySlider

local dropSlider = PredictionGroup:AddSlider("BulletDrop", {
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
sliderElements.dropSlider = dropSlider

local compensationSlider = PredictionGroup:AddSlider("DropCompensation", {
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
sliderElements.compensationSlider = compensationSlider

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

ESPGroup:AddToggle("ESPTeamCheck", {
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

ESPGroup:AddToggle("ESPWallCheck", {
    Text = "Wall Check",
    Desc = "Change ESP colors when players are behind walls",
    Default = config.espWallCheck,
    Callback = function(v)
        config.espWallCheck = v
    end
})

ESPGroup:AddDivider()
ESPGroup:AddLabel("ESP Elements")

ESPGroup:AddToggle("ESPBoxEnabled", {
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

ESPGroup:AddToggle("ESPHealthbarEnabled", {
    Text = "Health Bar",
    Default = config.espHealthbarEnabled,
    Callback = function(v)
        config.espHealthbarEnabled = v
    end
})

ESPGroup:AddToggle("ESPNameEnabled", {
    Text = "Player Names",
    Default = config.espNameEnabled,
    Callback = function(v)
        config.espNameEnabled = v
    end
})

ESPGroup:AddToggle("ESPDistanceEnabled", {
    Text = "Distance",
    Default = config.espDistanceEnabled,
    Callback = function(v)
        config.espDistanceEnabled = v
    end
})

ESPGroup:AddToggle("ESPTracerEnabled", {
    Text = "Tracer",
    Default = config.espTracerEnabled,
    Callback = function(v)
        config.espTracerEnabled = v
        -- Force refresh ESP when tracer is toggled
        if config.espEnabled then
            for player, espData in pairs(espObjects) do
                if espData.tracer then
                    if v then
                        -- Tracer enabled, will be shown in update loop
                    else
                        espData.tracer.Visible = false
                    end
                end
            end
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
    end
})

local hiddenColorLabel = ESPGroup:AddLabel("Hidden/Wall Color")
hiddenColorLabel:AddColorPicker("ESPHiddenColor", {
    Default = config.espHiddenColor,
    Callback = function(v)
        config.espHiddenColor = v
    end
})

ESPGroup:AddToggle("ESPUseTeamColor", {
    Text = "Use Team Color",
    Default = config.espUseTeamColor,
    Callback = function(v)
        config.espUseTeamColor = v
    end
})

ESPGroup:AddButton({
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

-- ===== HITBOX TAB =====
local HitboxGroup = HitboxTab:AddLeftGroupbox("Hitbox Extender")

HitboxGroup:AddToggle("HitboxEnabled", {
    Text = "Hitbox Extender",
    Default = config.hitboxEnabled,
    Callback = function(v)
        config.hitboxEnabled = v
        if v then
            -- Apply hitbox expansion to all players
            applyHitboxToAllPlayers()
            -- Legacy hitbox system is DISABLED
            -- updateAllHitboxes()
            -- hookFastCastRedux()
            -- hookHitRemote()
        else
            -- Reset all expanded hitboxes
            resetAllExpanded()
            -- Clean up legacy hitboxes
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
            -- Update all expanded hitboxes
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

local colorLabel = HitboxGroup:AddLabel("Hitbox Color")
colorLabel:AddColorPicker("HitboxColor", {
    Default = config.hitboxColor,
    Callback = function(v)
        config.hitboxColor = v
        -- Update expanded hitbox colors (they use BrickColor)
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

HitboxGroup:AddSlider("HitboxTransparency", {
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

HitboxGroup:AddToggle("HitboxTeamCheck", {
    Text = "Team Check",
    Default = config.hitboxTeamCheck,
    Callback = function(v)
        config.hitboxTeamCheck = v
        if config.hitboxEnabled then
            resetAllExpanded()
            applyHitboxToAllPlayers()
        end
    end
})

HitboxGroup:AddButton({
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
            resetAllExpanded()
            applyHitboxToAllPlayers()
            print("Hitboxes refreshed!")
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
    applyHitboxToAllPlayers()
    -- Legacy hitbox system is DISABLED
    -- updateAllHitboxes()
    -- hookFastCastRedux()
    -- hookHitRemote()
end

-- Setup ESP update loop on RenderStepped (smooth, every frame)
connections.espUpdate = RunService.RenderStepped:Connect(function()
    if config.espEnabled then
        pcall(updateAllESP)
    end
end)

-- Setup player respawn handlers
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
        if shouldExtendHitbox(player) then
            applyHitboxExpansion(player)
            -- Legacy hitbox is DISABLED
            -- createHitboxForPlayer(player)
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if playerHitboxes[player] then
        removeHitboxForPlayer(player)
    end
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

-- Monitor for hitbox size changes
connections.mountedCheck = task.spawn(function()
    local lastHitboxSize = config.hitboxSize
    while task.wait(0.15) do
        if config.hitboxEnabled and config.hitboxSize ~= lastHitboxSize then
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

-- ===== AUTO REFRESH HITBOXES ON RENDERSTEPPED (HRP ONLY) =====
connections.autoRefresh = RunService.RenderStepped:Connect(function()
    if config.hitboxEnabled then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= plr and player.Character then
                resetAllExpanded()
                applyHitboxToAllPlayers()
            end
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
