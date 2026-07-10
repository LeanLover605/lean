-- ===== WINDUI LOADING =====
local cloneref = (cloneref or clonereference or function(instance)
    return instance
end)

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local RunService = cloneref(game:GetService("RunService"))

local WindUI

do
    local ok, result = pcall(function()
        return require("./src/Init")
    end)

    if ok then
        WindUI = result
    else
        if RunService:IsStudio() or not writefile then
            local windUI = ReplicatedStorage:FindFirstChild("WindUI")
            if windUI then
                WindUI = require(windUI:WaitForChild("Init"))
            else
                WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
            end
        else
            WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
        end
    end
end

if not WindUI then
    WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
end

-- ===== SERVICES =====
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local Stats = game:GetService("Stats")

local plr = Players.LocalPlayer

-- ===== DEFAULT CONFIGURATION =====
local config = {
    enabled = false,
    fovRadius = 150,
    teamCheck = false,
    aimPart = "Head",
    showFOV = true,
    fovColor = Color3.fromRGB(255, 255, 255),
    fovTransparency = 0.7,
    toggleKey = "Delete",
    guikey = "RightShift",
    smoothing = 0.3,
    wallCheck = false,
    prediction = 0.15,
    bulletVelocity = 500,
    bulletDrop = 5,
    autoPrediction = true,
    gravityCompensation = 1.0,
    autoCalibration = true,
    adaptiveCalibration = true,
    calibrationRate = 0.05,
    
    -- Hitbox Extender settings
    hitboxEnabled = false,
    hitboxSize = 1.5,
    hitboxColor = Color3.fromRGB(255, 0, 0),
    hitboxTransparency = 0.5,
    hitboxTeamCheck = false,
    hitboxPart = "Head",
}

-- ===== AUTO-CALCULATION SYSTEM =====
local autoCalc = {
    ping = 0.05,
    pingSamples = {},
    pingSampleCount = 0,
    
    totalShots = 0,
    totalHits = 0,
    hitRate = 0,
    lastShotTime = 0,
    shotCooldown = 0.5,
    
    lastAdjustment = 0,
    adjustmentDirection = 0,
    
    calibrationTarget = "prediction",
    calibrationValues = {
        prediction = { min = 0.05, max = 0.5, current = config.prediction },
        bulletDrop = { min = 0, max = 30, current = config.bulletDrop },
        bulletVelocity = { min = 100, max = 2000, current = config.bulletVelocity },
        gravityCompensation = { min = 0.5, max = 1.5, current = config.gravityCompensation }
    },
    
    remoteFound = false,
    remoteType = nil,
    remotePath = nil,
    remoteName = nil,
}

-- ===== STATE =====
local toggleKeyConnection = nil
local fovCircle = nil
local lastTargetPos = {}
local targetVelocities = {}
local currentTarget = nil
local currentTargetPlayer = nil
local enabledToggleElement = nil
local guiElements = {}
local hitRemote = nil
local remoteConnection = nil
local remoteSearching = false
local isUILoaded = false
local fastCast = nil
local fastCastHooked = false

-- ===== UI SLIDER REFERENCE STORAGE =====
local sliderElements = {}

-- ===== CONNECTIONS FOR CLEANUP =====
local connections = {
    renderStepped = nil,
    velocityLoop = nil,
    characterAdded = nil,
    hitboxUpdate = nil,
    fastCastHook = nil,
}

-- ===== HITBOX EXTENDER STATE =====
local playerHitboxes = {}
local originalHitRemote = nil
local originalFireServer = nil

-- ===== FORWARD DECLARATIONS =====
local performAdaptiveCalibration
local updateUISliders
local cleanup
local createHitboxForPlayer
local removeHitboxForPlayer
local updateAllHitboxes
local getTargetPart
local shouldExtendHitbox
local fireHitRemote
local hookFastCastRedux
local hookHitRemote

-- ===== GET TARGET PART =====
function getTargetPart(player)
    if not player or not player.Character then return nil end
    local partName = config.hitboxPart or "Head"
    return player.Character:FindFirstChild(partName)
end

-- ===== SHOULD EXTEND HITBOX =====
function shouldExtendHitbox(player)
    if not player or player == plr then return false end
    if not player.Character then return false end
    
    if config.hitboxTeamCheck and player.Team == plr.Team then
        return false
    end
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end
    
    return true
end

-- ===== GET PLAYER FROM PART =====
local function getPlayerFromPart(part)
    if not part then return nil end
    
    -- Check if part is a hitbox
    for player, data in pairs(playerHitboxes) do
        if data.hitbox == part then
            return player
        end
    end
    
    -- Check if part is in a character
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
function fireHitRemote(targetPlayer, hitVelocity)
    if not hitRemote then
        setupHitRemoteListener()
        if not hitRemote then return end
    end
    
    if not targetPlayer or not targetPlayer.Character then return end
    
    local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    pcall(function()
        hitRemote:FireServer(
            plr,           -- [1] Shooter
            hitVelocity,   -- [2] Vector3 velocity at impact
            humanoid       -- [3] Target's Humanoid
        )
        print("Fired Hit remote for: " .. targetPlayer.Name .. " with velocity: " .. tostring(hitVelocity))
    end)
end

-- ===== HOOK FASTCASTREDUX =====
function hookFastCastRedux()
    if fastCastHooked then return true end
    
    print("Attempting to hook FastCastRedux...")
    
    -- Get the FastCastRedux module
    local fastCastModule = ReplicatedStorage:FindFirstChild("Tools")
    if fastCastModule then
        local components = fastCastModule:FindFirstChild("Components")
        if components then
            local muzzle = components:FindFirstChild("Muzzle")
            if muzzle then
                fastCast = muzzle:FindFirstChild("FastCastRedux")
                if fastCast then
                    print("Found FastCastRedux module!")
                    
                    -- Try to get the actual FastCast instance
                    local fastCastInstance = nil
                    
                    -- Method 1: Check if it's already initialized
                    if fastCast.__index and fastCast.__index.RayHit then
                        fastCastInstance = fastCast
                    end
                    
                    -- Method 2: Check for a global FastCast instance
                    if not fastCastInstance and _G.FastCast then
                        fastCastInstance = _G.FastCast
                    end
                    
                    -- Method 3: Search workspace for FastCast objects
                    if not fastCastInstance then
                        for _, obj in ipairs(Workspace:GetDescendants()) do
                            if obj:IsA("ModuleScript") and obj.Name == "FastCastRedux" then
                                local success, result = pcall(function()
                                    return require(obj)
                                end)
                                if success and result and result.RayHit then
                                    fastCastInstance = result
                                    break
                                end
                            end
                        end
                    end
                    
                    if fastCastInstance and fastCastInstance.RayHit then
                        print("Hooking FastCastRedux RayHit event...")
                        
                        -- Hook the RayHit event
                        local oldRayHit = fastCastInstance.RayHit
                        fastCastInstance.RayHit = function(cast, result, velocity, cosmeticBullet)
                            -- Check if the hit part is our extended hitbox
                            local hitPart = result and result.Instance
                            local hitPlayer = getPlayerFromPart(hitPart)
                            
                            if hitPlayer and playerHitboxes[hitPlayer] then
                                print("FastCast hit extended hitbox: " .. hitPlayer.Name)
                                
                                -- Get the real target part
                                local realTargetPart = playerHitboxes[hitPlayer].targetPart
                                if realTargetPart then
                                    -- Fire the Hit remote with the velocity
                                    fireHitRemote(hitPlayer, velocity)
                                end
                            end
                            
                            -- Call the original event
                            if oldRayHit then
                                return oldRayHit(cast, result, velocity, cosmeticBullet)
                            end
                        end
                        
                        fastCastHooked = true
                        print("FastCastRedux hooked successfully!")
                        return true
                    else
                        print("Could not find FastCastRedux instance. Trying alternative method...")
                        
                        -- Alternative: Hook the module's new function
                        local success, result = pcall(function()
                            return require(fastCast)
                        end)
                        
                        if success and result and result.new then
                            local oldNew = result.new
                            result.new = function(...)
                                local instance = oldNew(...)
                                
                                -- Hook the instance's events
                                if instance and instance.RayHit then
                                    local oldInstanceRayHit = instance.RayHit
                                    instance.RayHit = function(cast, result, velocity, cosmeticBullet)
                                        local hitPart = result and result.Instance
                                        local hitPlayer = getPlayerFromPart(hitPart)
                                        
                                        if hitPlayer and playerHitboxes[hitPlayer] then
                                            print("FastCast instance hit extended hitbox: " .. hitPlayer.Name)
                                            fireHitRemote(hitPlayer, velocity)
                                        end
                                        
                                        if oldInstanceRayHit then
                                            return oldInstanceRayHit(cast, result, velocity, cosmeticBullet)
                                        end
                                    end
                                end
                                
                                return instance
                            end
                            
                            fastCastHooked = true
                            print("FastCastRedux new() hooked successfully!")
                            return true
                        end
                    end
                else
                    print("FastCastRedux not found at expected location.")
                end
            end
        end
    end
    
    print("Failed to hook FastCastRedux.")
    return false
end

-- ===== HOOK HIT REMOTE =====
function hookHitRemote()
    if originalHitRemote then return true end
    
    print("Hooking Hit remote...")
    
    if not hitRemote then
        setupHitRemoteListener()
        if not hitRemote then return false end
    end
    
    -- Store original FireServer
    originalFireServer = hitRemote.FireServer
    
    -- Hook the FireServer method
    hitRemote.FireServer = function(self, ...)
        local args = {...}
        local shooter = args[1]
        local velocity = args[2]
        local targetHumanoid = args[3]
        
        -- Check if this is a hit on our extended hitbox
        local targetPlayer = targetHumanoid and targetHumanoid.Parent and Players:GetPlayerFromCharacter(targetHumanoid.Parent)
        
        if targetPlayer and playerHitboxes[targetPlayer] then
            print("Hit remote detected hit on extended hitbox: " .. targetPlayer.Name)
            -- Let the original remote fire normally
        end
        
        -- Call original
        if originalFireServer then
            return originalFireServer(self, ...)
        end
    end
    
    originalHitRemote = true
    print("Hit remote hooked successfully!")
    return true
end

-- ===== CREATE HITBOX FOR PLAYER =====
function createHitboxForPlayer(player)
    if not player or not player.Character then return end
    
    removeHitboxForPlayer(player)
    
    local targetPart = getTargetPart(player)
    if not targetPart then return end
    
    local hitbox = Instance.new("Part")
    hitbox.Name = "ExtendedHitbox"
    hitbox.Anchored = false
    hitbox.CanCollide = true
    hitbox.Massless = true
    hitbox.Transparency = config.hitboxTransparency or 0.5
    hitbox.Color = config.hitboxColor or Color3.fromRGB(255, 0, 0)
    hitbox.Material = Enum.Material.Neon
    hitbox.Size = targetPart.Size * config.hitboxSize
    
    -- Weld to target part
    local weld = Instance.new("Weld")
    weld.Part0 = targetPart
    weld.Part1 = hitbox
    weld.C0 = CFrame.new(0, 0, 0)
    weld.Parent = hitbox
    
    hitbox.Parent = player.Character
    
    playerHitboxes[player] = {
        hitbox = hitbox,
        weld = weld,
        targetPart = targetPart,
        connection = nil
    }
    
    -- Touch detection (for visual feedback only, since raycasts don't trigger Touched)
    playerHitboxes[player].connection = hitbox.Touched:Connect(function(hit)
        if hit and hit.Parent then
            -- Check if a physical bullet hit (unlikely with FastCastRedux)
            local isBullet = hit.Name:match("Bullet") or hit.Name:match("Projectile")
            if isBullet then
                print("Physical bullet touched extended hitbox: " .. player.Name)
                -- Try to get velocity from bullet
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
    
    print("Created hitbox for: " .. player.Name)
end

-- ===== REMOVE HITBOX FOR PLAYER =====
function removeHitboxForPlayer(player)
    if playerHitboxes[player] then
        if playerHitboxes[player].hitbox then
            pcall(function()
                playerHitboxes[player].hitbox:Destroy()
            end)
        end
        if playerHitboxes[player].connection then
            pcall(function()
                playerHitboxes[player].connection:Disconnect()
            end)
        end
        playerHitboxes[player] = nil
        print("Removed hitbox for: " .. player.Name)
    end
end

-- ===== UPDATE ALL HITBOXES =====
function updateAllHitboxes()
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
    else
        for player, _ in pairs(playerHitboxes) do
            removeHitboxForPlayer(player)
        end
    end
end

-- ===== CLEANUP FUNCTION =====
cleanup = function()
    print("Cleaning up Silent Aim script...")
    
    -- Restore original Hit remote
    if originalFireServer and hitRemote then
        pcall(function()
            hitRemote.FireServer = originalFireServer
        end)
        originalFireServer = nil
        originalHitRemote = nil
    end
    
    if remoteConnection then
        pcall(function()
            remoteConnection:Disconnect()
        end)
        remoteConnection = nil
    end
    
    if toggleKeyConnection then
        pcall(function()
            toggleKeyConnection:Disconnect()
        end)
        toggleKeyConnection = nil
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
    
    if connections.fastCastHook then
        pcall(function()
            connections.fastCastHook:Disconnect()
        end)
        connections.fastCastHook = nil
    end
    
    for player, data in pairs(playerHitboxes) do
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
    
    if fovCircle then
        pcall(function()
            fovCircle:Destroy()
        end)
        fovCircle = nil
    end
    
    if Window then
        pcall(function()
            Window:Destroy()
        end)
        Window = nil
    end
    
    guiElements = {}
    sliderElements = {}
    lastTargetPos = {}
    targetVelocities = {}
    currentTarget = nil
    currentTargetPlayer = nil
    enabledToggleElement = nil
    hitRemote = nil
    fastCast = nil
    fastCastHooked = false
    isUILoaded = false
    
    config.enabled = false
    config.hitboxEnabled = false
    
    print("Cleanup complete!")
end

-- ===== INTERCEPT HIT REMOTE =====
local function setupHitRemoteListener()
    if remoteSearching then return false end
    remoteSearching = true
    
    print("Looking for Hit remote at: ReplicatedStorage.Tools.Components.Muzzle.Hit")
    
    local tools = ReplicatedStorage:FindFirstChild("Tools")
    if tools then
        local components = tools:FindFirstChild("Components")
        if components then
            local muzzle = components:FindFirstChild("Muzzle")
            if muzzle then
                hitRemote = muzzle:FindFirstChild("Hit")
                if hitRemote then
                    print("Found Hit remote at the expected location!")
                    autoCalc.remoteFound = true
                    autoCalc.remoteName = hitRemote.Name
                    autoCalc.remotePath = "ReplicatedStorage.Tools.Components.Muzzle.Hit"
                    autoCalc.remoteType = hitRemote:IsA("RemoteEvent") and "RemoteEvent" or "RemoteFunction"
                    
                    if hitRemote:IsA("RemoteEvent") then
                        if remoteConnection then
                            remoteConnection:Disconnect()
                        end
                        remoteConnection = hitRemote.OnClientEvent:Connect(function(...)
                            onHitDetected(...)
                        end)
                        print("Connected to Hit RemoteEvent!")
                        remoteSearching = false
                        return true
                    elseif hitRemote:IsA("RemoteFunction") then
                        local oldInvoke = hitRemote.OnClientInvoke
                        hitRemote.OnClientInvoke = function(...)
                            onHitDetected(...)
                            if oldInvoke then
                                return oldInvoke(...)
                            end
                        end
                        print("Connected to Hit RemoteFunction!")
                        remoteSearching = false
                        return true
                    end
                else
                    print("Hit remote not found in Muzzle.")
                end
            else
                print("Muzzle folder not found.")
            end
        else
            print("Components folder not found.")
        end
    else
        print("Tools folder not found.")
    end
    
    remoteSearching = false
    return false
end

-- ===== UPDATE UI SLIDERS =====
updateUISliders = function()
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
    
    if sliderElements.hitboxSizeSlider then
        pcall(function()
            sliderElements.hitboxSizeSlider:Set(config.hitboxSize)
        end)
    end
    
    if sliderElements.hitboxTransparencySlider then
        pcall(function()
            sliderElements.hitboxTransparencySlider:Set(config.hitboxTransparency)
        end)
    end
    
    if guiElements.calibrationTargetText then
        pcall(function()
            guiElements.calibrationTargetText:SetDesc("Currently calibrating: " .. autoCalc.calibrationTarget)
        end)
    end
end

-- ===== ADAPTIVE CALIBRATION =====
performAdaptiveCalibration = function(force)
    if not config.adaptiveCalibration and not force then return end
    
    local hitRate = autoCalc.hitRate
    
    if autoCalc.totalShots < 10 and not force then return end
    
    local idealHitRate = 0.7
    local error = hitRate - idealHitRate
    
    if math.abs(error) < 0.05 and not force then
        autoCalc.adjustmentDirection = 0
        return
    end
    
    local adjustment = config.calibrationRate * math.clamp(error * 2, -0.1, 0.1)
    
    if force then
        adjustment = (math.random() - 0.5) * 0.1
    end
    
    local targets = {"prediction", "bulletDrop", "gravityCompensation", "bulletVelocity"}
    local targetIndex = 1
    
    for i, t in ipairs(targets) do
        if t == autoCalc.calibrationTarget then
            targetIndex = i
            break
        end
    end
    
    targetIndex = targetIndex % #targets + 1
    autoCalc.calibrationTarget = targets[targetIndex]
    
    local targetConfig = autoCalc.calibrationValues[autoCalc.calibrationTarget]
    
    if targetConfig then
        local newValue = targetConfig.current + adjustment * 2
        newValue = math.clamp(newValue, targetConfig.min, targetConfig.max)
        targetConfig.current = newValue
        
        if autoCalc.calibrationTarget == "prediction" then
            config.prediction = newValue
        elseif autoCalc.calibrationTarget == "bulletDrop" then
            config.bulletDrop = newValue
        elseif autoCalc.calibrationTarget == "bulletVelocity" then
            config.bulletVelocity = newValue
        elseif autoCalc.calibrationTarget == "gravityCompensation" then
            config.gravityCompensation = newValue
        end
        
        print("Adaptive calibration: " .. autoCalc.calibrationTarget .. " -> " .. string.format("%.3f", newValue))
        print("Current hit rate: " .. math.floor(hitRate * 100) .. "%")
        
        updateUISliders()
    end
end

-- ===== ON HIT DETECTED =====
local function onHitDetected(...)
    autoCalc.totalShots = autoCalc.totalShots + 1
    autoCalc.totalHits = autoCalc.totalHits + 1
    autoCalc.hitRate = autoCalc.totalHits / autoCalc.totalShots
    
    print("HIT DETECTED! Hit rate: " .. math.floor(autoCalc.hitRate * 100) .. "% (" .. autoCalc.totalHits .. "/" .. autoCalc.totalShots .. ")")
    
    if isUILoaded and guiElements and guiElements.hitRateText then
        pcall(function()
            guiElements.hitRateText:SetDesc("Current hit rate: " .. math.floor(autoCalc.hitRate * 100) .. "% (" .. autoCalc.totalHits .. "/" .. autoCalc.totalShots .. ")")
        end)
    end
    
    if config.adaptiveCalibration and autoCalc.totalShots >= 5 then
        performAdaptiveCalibration()
    end
end

-- ===== TRACK SHOT ATTEMPTS =====
local function trackShotAttempt()
    local currentTime = tick()
    if currentTime - autoCalc.lastShotTime > autoCalc.shotCooldown then
        autoCalc.totalShots = autoCalc.totalShots + 1
        autoCalc.lastShotTime = currentTime
        
        if isUILoaded and guiElements and guiElements.hitRateText then
            pcall(function()
                guiElements.hitRateText:SetDesc("Current hit rate: " .. math.floor(autoCalc.hitRate * 100) .. "% (" .. autoCalc.totalHits .. "/" .. autoCalc.totalShots .. ")")
            end)
        end
        
        if autoCalc.totalShots - autoCalc.totalHits > 10 then
            performAdaptiveCalibration(true)
        end
    end
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
                autoCalc.ping = total / (autoCalc.pingSampleCount)
                table.remove(autoCalc.pingSamples, 1)
            end
        end
    end
    
    local networkStats = Stats:FindFirstChild("Network")
    if networkStats then
        local ping = networkStats:FindFirstChild("Ping")
        if ping and type(ping.Value) == "number" then
            autoCalc.ping = ping.Value / 1000
        end
    end
    
    return autoCalc.ping
end

-- ===== BULLET VELOCITY DETECTION =====
local function detectBulletVelocity()
    if plr.Character then
        local tools = plr.Character:GetChildren()
        for _, tool in ipairs(tools) do
            if tool:IsA("Tool") then
                local projectile = tool:FindFirstChild("Projectile")
                if projectile then
                    local speed = projectile:FindFirstChild("Speed")
                    if speed and type(speed.Value) == "number" then
                        return speed.Value
                    end
                end
                
                local handle = tool:FindFirstChild("Handle")
                if handle then
                    local velocity = handle:FindFirstChild("Velocity")
                    if velocity and type(velocity.Value) == "number" then
                        return velocity.Value
                    end
                end
            end
        end
    end
    
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name:match("Projectile") or obj.Name:match("Bullet") then
            local velocity = obj:FindFirstChild("Velocity")
            if velocity and type(velocity.Value) == "number" then
                return velocity.Value
            end
        end
    end
    
    return nil
end

-- ===== BULLET DROP DETECTION =====
local function detectBulletDrop()
    local gravity = Workspace:FindFirstChild("Gravity")
    if gravity and type(gravity.Value) == "number" then
        return gravity.Value * 0.5
    end
    
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name:match("Projectile") or obj.Name:match("Bullet") then
            local drop = obj:FindFirstChild("Drop")
            if drop and type(drop.Value) == "number" then
                return drop.Value
            end
        end
    end
    
    return nil
end

-- ===== PERFORMANCE TESTING =====
local function performAutoCalibration()
    print("Starting auto-calibration...")
    
    detectPing()
    print("Detected ping: " .. math.floor(autoCalc.ping * 1000) .. "ms")
    
    local velocity = detectBulletVelocity()
    if velocity then
        config.bulletVelocity = velocity
        autoCalc.calibrationValues.bulletVelocity.current = velocity
        print("Detected bullet velocity: " .. velocity .. " studs/s")
    else
        print("Could not auto-detect bullet velocity. Using manual setting.")
    end
    
    local drop = detectBulletDrop()
    if drop then
        config.bulletDrop = drop
        autoCalc.calibrationValues.bulletDrop.current = drop
        print("Detected bullet drop: " .. drop .. " studs/s²")
    else
        print("Could not auto-detect bullet drop. Using manual setting.")
    end
    
    if autoCalc.ping and autoCalc.ping > 0 then
        config.prediction = math.clamp(autoCalc.ping * 2, 0.05, 0.3)
        autoCalc.calibrationValues.prediction.current = config.prediction
        print("Auto-adjusted prediction to: " .. config.prediction)
    end
    
    updateUISliders()
end

-- ===== CREATE FOV CIRCLE =====
local function createFOVCircle()
    if fovCircle then 
        pcall(function() fovCircle:Destroy() end) 
    end
    
    fovCircle = Instance.new("ScreenGui")
    fovCircle.Name = "FOVCircle"
    fovCircle.Parent = game:GetService("CoreGui")
    fovCircle.Enabled = config.showFOV and config.enabled
    fovCircle.ResetOnSpawn = false
    fovCircle.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
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

local function updateFOVCircle()
    if not fovCircle then return end
    
    local outline = fovCircle:FindFirstChild("CircleOutline")
    if outline then
        outline.Size = UDim2.new(0, config.fovRadius * 2, 0, config.fovRadius * 2)
        outline.ImageColor3 = config.fovColor
        outline.ImageTransparency = config.fovTransparency
    end
end

local function updateFOVPosition()
    if not fovCircle or not fovCircle.Enabled then return end
    
    local mousePos = UserInputService:GetMouseLocation()
    
    local outline = fovCircle:FindFirstChild("CircleOutline")
    local centerDot = fovCircle:FindFirstChild("CenterDot")
    
    if outline then
        outline.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
    end
    
    if centerDot then
        centerDot.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
    end
end

createFOVCircle()

-- ===== TRACK TARGET VELOCITIES =====
local function updateTargetVelocities()
    local dt = 0.05
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr and player.Character and player.Character.Parent then
            local targetPart = player.Character:FindFirstChild(config.aimPart) 
                or player.Character:FindFirstChild("Head")
            
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

-- ===== PREDICT TARGET POSITION =====
local function predictPosition(targetPart, player)
    if not targetPart or not targetPart.Parent then 
        return targetPart and targetPart.Position or Vector3.new(0, 0, 0)
    end
    
    local basePosition = targetPart.Position
    local cameraPos = Camera.CFrame.Position
    
    local pingCompensation = autoCalc.ping or 0.05
    
    local distance = (basePosition - cameraPos).Magnitude
    local bulletTravelTime = math.clamp(distance / config.bulletVelocity, 0.01, 3)
    
    if config.autoPrediction and targetVelocities[player] then
        local velocity = targetVelocities[player]
        local velocityMagnitude = velocity.Magnitude
        
        if velocityMagnitude > 1 then
            local leadTime = bulletTravelTime * config.prediction + pingCompensation
            
            local speedMultiplier = math.min(velocityMagnitude / 30, 2)
            leadTime = leadTime * (1 + speedMultiplier * 0.3)
            
            basePosition = basePosition + (velocity * leadTime)
        end
    end
    
    if config.bulletDrop > 0 then
        local predictedDistance = (basePosition - cameraPos).Magnitude
        local travelTime = math.clamp(predictedDistance / config.bulletVelocity, 0.01, 3)
        
        local drop = 0.5 * config.bulletDrop * travelTime * travelTime
        drop = drop * config.gravityCompensation
        drop = drop * (1 + pingCompensation * 0.5)
        
        basePosition = basePosition + Vector3.new(0, drop, 0)
    end
    
    return basePosition
end

-- ===== GET CLOSEST TARGET IN FOV =====
local function getClosestTarget()
    if not plr.Character or not plr.Character.Parent then return nil, nil end
    
    local mousePos = UserInputService:GetMouseLocation()
    local fovRadius = config.fovRadius
    local closestTarget = nil
    local closestDistance = fovRadius
    local closestPlayer = nil
    local cameraPos = Camera.CFrame.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= plr and player.Character and player.Character.Parent then
            if not config.teamCheck or (player.Team ~= plr.Team) then
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local targetPart = player.Character:FindFirstChild(config.aimPart)
                    if not targetPart then
                        targetPart = player.Character:FindFirstChild("Head")
                    end
                    
                    if targetPart and targetPart.Parent then
                        local predictedPos = predictPosition(targetPart, player)
                        
                        local toTarget = predictedPos - cameraPos
                        local forward = Camera.CFrame.LookVector
                        if toTarget:Dot(forward) < 0 then
                            continue
                        end
                        
                        local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)
                        
                        if onScreen then
                            local screenPoint = Vector2.new(screenPos.X, screenPos.Y)
                            local mousePoint = Vector2.new(mousePos.X, mousePos.Y)
                            local distance = (screenPoint - mousePoint).Magnitude
                            
                            if distance < closestDistance then
                                local wallPassed = false
                                if config.wallCheck then
                                    local rayParams = RaycastParams.new()
                                    rayParams.FilterDescendantsInstances = {plr.Character}
                                    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                                    rayParams.IgnoreWater = true
                                    
                                    local direction = (predictedPos - cameraPos)
                                    local distanceToTarget = direction.Magnitude
                                    direction = direction.Unit * distanceToTarget
                                    
                                    local rayResult = Workspace:Raycast(cameraPos, direction, rayParams)
                                    
                                    if not rayResult then
                                        wallPassed = true
                                    elseif rayResult.Instance:IsDescendantOf(player.Character) then
                                        wallPassed = true
                                    end
                                else
                                    wallPassed = true
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
    
    if config.autoCalibration and tick() % 5 < 0.1 then
        detectPing()
    end
    
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        trackShotAttempt()
    end
    
    local target, player = getClosestTarget()
    
    if target and player then
        local predictedPos = predictPosition(target, player)
        local cameraPos = Camera.CFrame.Position
        local direction = (predictedPos - cameraPos).Unit
        
        if config.smoothing < 0.95 then
            local currentLook = Camera.CFrame.LookVector
            local lerpFactor = 1 - math.pow(config.smoothing, 2)
            local newDirection = currentLook:Lerp(direction, math.clamp(lerpFactor, 0, 1))
            
            local newCFrame = CFrame.new(
                cameraPos,
                cameraPos + newDirection
            )
            
            local adjustedCFrame = Camera.CFrame:Lerp(newCFrame, math.clamp(lerpFactor * 0.1, 0, 0.1))
            
            pcall(function()
                Camera.CFrame = adjustedCFrame
            end)
        else
            local targetCFrame = CFrame.new(cameraPos, predictedPos)
            pcall(function()
                Camera.CFrame = targetCFrame
            end)
        end
        
        currentTarget = target
        currentTargetPlayer = player
    else
        currentTarget = nil
        currentTargetPlayer = nil
    end
end

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
        elseif config.hitboxEnabled == false and next(playerHitboxes) then
            for player, _ in pairs(playerHitboxes) do
                pcall(function() removeHitboxForPlayer(player) end)
            end
        end
    end
end)

-- ===== TOGGLE FUNCTION =====
local function setEnabled(value)
    config.enabled = value
    
    if enabledToggleElement then
        pcall(function()
            enabledToggleElement:Set(value)
        end)
    end
    
    if fovCircle then
        fovCircle.Enabled = config.showFOV and value
    end
    
    if not value then
        currentTarget = nil
        currentTargetPlayer = nil
    end
end

-- ===== UPDATE TOGGLE KEYBIND =====
local function updateToggleKeybind()
    if toggleKeyConnection then
        toggleKeyConnection:Disconnect()
        toggleKeyConnection = nil
    end
    
    toggleKeyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode[config.toggleKey] then
            config.enabled = not config.enabled
            
            if enabledToggleElement then
                pcall(function()
                    enabledToggleElement:Set(config.enabled)
                end)
            end
            
            if fovCircle then
                fovCircle.Enabled = config.showFOV and config.enabled
            end
            
            if not config.enabled then
                currentTarget = nil
                currentTargetPlayer = nil
            end
        end
    end)
end

-- ===== CREATE GUI =====
local Window = WindUI:CreateWindow({
    Title = "Silent Aim",
    Icon = "crosshair",
    Author = "by Prayut",
    Folder = "SilentAim",
    
    Size = UDim2.fromOffset(650, 600),
    MinSize = Vector2.new(560, 400),
    MaxSize = Vector2.new(850, 650),
    ToggleKey = Enum.KeyCode.RightShift,
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 200,
    BackgroundImageTransparency = 0.42,
    HideSearchBar = true,
    ScrollBarEnabled = false,
    
    User = {
        Enabled = true,
        Anonymous = false,
        Callback = function()
            print("User profile clicked")
        end,
    },
})

Window._cleanup = cleanup

-- ===== CREATE TABS =====
local MainTab = Window:Tab({
    Title = "Main",
    Icon = "crosshair"
})

local PredictionTab = Window:Tab({
    Title = "Prediction",
    Icon = "target"
})

local HitboxTab = Window:Tab({
    Title = "Hitbox Extender",
    Icon = "expand"
})

local CalibrationTab = Window:Tab({
    Title = "Calibration",
    Icon = "sliders"
})

local FOVTab = Window:Tab({
    Title = "FOV",
    Icon = "eye"
})

local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "settings"
})

-- ===== MAIN TAB =====
local enabledToggle = MainTab:Toggle({
    Title = "Enabled",
    Desc = "Toggle silent aim on/off",
    Default = config.enabled,
    Callback = function(value) 
        if config.enabled ~= value then
            config.enabled = value
            
            if fovCircle then
                fovCircle.Enabled = config.showFOV and value
            end
            
            if not value then
                currentTarget = nil
                currentTargetPlayer = nil
            end
        end
    end
})
enabledToggleElement = enabledToggle

MainTab:Slider({
    Title = "FOV Radius",
    Desc = "Aim assist radius in pixels",
    Step = 5,
    Value = {
        Min = 30,
        Max = 500,
        Default = config.fovRadius
    },
    Callback = function(value)
        config.fovRadius = value
        updateFOVCircle()
    end
})

MainTab:Toggle({
    Title = "Team Check",
    Desc = "Only aim at enemies",
    Default = config.teamCheck,
    Callback = function(value) 
        config.teamCheck = value 
    end
})

MainTab:Dropdown({
    Title = "Aim Part",
    Desc = "Which body part to aim at",
    Values = {"Head", "Torso", "HumanoidRootPart"},
    Default = config.aimPart,
    Callback = function(value)
        config.aimPart = value
    end
})

MainTab:Toggle({
    Title = "Wall Check",
    Desc = "Don't aim through walls",
    Default = config.wallCheck,
    Callback = function(value) 
        config.wallCheck = value 
    end
})

MainTab:Slider({
    Title = "Smoothing",
    Desc = "Aim smoothness (0 = instant, 1 = very smooth)",
    Step = 0.05,
    Value = {
        Min = 0.05,
        Max = 0.95,
        Default = config.smoothing
    },
    Callback = function(value) 
        config.smoothing = value 
    end
})

-- ===== PREDICTION TAB =====
PredictionTab:Toggle({
    Title = "Auto Prediction",
    Desc = "Automatically predict target movement",
    Default = config.autoPrediction,
    Callback = function(value) 
        config.autoPrediction = value 
    end
})

local predictionSlider = PredictionTab:Slider({
    Title = "Prediction Multiplier",
    Desc = "How much to lead moving targets (higher = more lead)",
    Step = 0.05,
    Value = {
        Min = 0,
        Max = 1,
        Default = config.prediction
    },
    Callback = function(value) 
        config.prediction = value
        autoCalc.calibrationValues.prediction.current = value
    end
})
sliderElements.predictionSlider = predictionSlider

local velocitySlider = PredictionTab:Slider({
    Title = "Bullet Velocity",
    Desc = "Bullet speed in studs/second",
    Step = 10,
    Value = {
        Min = 100,
        Max = 2000,
        Default = config.bulletVelocity
    },
    Callback = function(value) 
        config.bulletVelocity = value
        autoCalc.calibrationValues.bulletVelocity.current = value
    end
})
sliderElements.velocitySlider = velocitySlider

local dropSlider = PredictionTab:Slider({
    Title = "Bullet Drop",
    Desc = "Bullet drop (gravity) in studs/s²",
    Step = 1,
    Value = {
        Min = 0,
        Max = 50,
        Default = config.bulletDrop
    },
    Callback = function(value) 
        config.bulletDrop = value
        autoCalc.calibrationValues.bulletDrop.current = value
    end
})
sliderElements.dropSlider = dropSlider

local compensationSlider = PredictionTab:Slider({
    Title = "Drop Compensation",
    Desc = "Multiplier for bullet drop compensation",
    Step = 0.05,
    Value = {
        Min = 0.5,
        Max = 1.5,
        Default = config.gravityCompensation
    },
    Callback = function(value) 
        config.gravityCompensation = value
        autoCalc.calibrationValues.gravityCompensation.current = value
    end
})
sliderElements.compensationSlider = compensationSlider

-- ===== HITBOX EXTENDER TAB =====
local hitboxEnabled = HitboxTab:Toggle({
    Title = "Hitbox Extender",
    Desc = "Toggle hitbox expansion on enemies",
    Default = config.hitboxEnabled,
    Callback = function(value)
        config.hitboxEnabled = value
        if value then
            updateAllHitboxes()
            -- Hook FastCastRedux when enabling
            hookFastCastRedux()
            hookHitRemote()
        else
            for player, _ in pairs(playerHitboxes) do
                pcall(function() removeHitboxForPlayer(player) end)
            end
        end
    end
})

local hitboxSizeSlider = HitboxTab:Slider({
    Title = "Hitbox Size",
    Desc = "Multiplier for hitbox size (1 = normal, 2 = double)",
    Step = 0.1,
    Value = {
        Min = 0.5,
        Max = 3,
        Default = config.hitboxSize
    },
    Callback = function(value)
        config.hitboxSize = value
        if config.hitboxEnabled then
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
            updateAllHitboxes()
        end
    end
})
sliderElements.hitboxSizeSlider = hitboxSizeSlider

HitboxTab:Colorpicker({
    Title = "Hitbox Color",
    Desc = "Choose the color of the hitbox",
    Default = config.hitboxColor,
    Callback = function(color)
        config.hitboxColor = color
        for player, data in pairs(playerHitboxes) do
            if data.hitbox then
                pcall(function()
                    data.hitbox.Color = color
                end)
            end
        end
    end
})

local hitboxTransparencySlider = HitboxTab:Slider({
    Title = "Hitbox Transparency",
    Desc = "Transparency of the hitbox (0 = solid, 1 = invisible)",
    Step = 0.05,
    Value = {
        Min = 0,
        Max = 1,
        Default = config.hitboxTransparency
    },
    Callback = function(value)
        config.hitboxTransparency = value
        for player, data in pairs(playerHitboxes) do
            if data.hitbox then
                pcall(function()
                    data.hitbox.Transparency = value
                end)
            end
        end
    end
})
sliderElements.hitboxTransparencySlider = hitboxTransparencySlider

HitboxTab:Toggle({
    Title = "Team Check",
    Desc = "Only extend hitboxes on enemies",
    Default = config.hitboxTeamCheck,
    Callback = function(value)
        config.hitboxTeamCheck = value
        if config.hitboxEnabled then
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
            updateAllHitboxes()
        end
    end
})

HitboxTab:Dropdown({
    Title = "Target Part",
    Desc = "Which body part to extend",
    Values = {"Head", "Torso", "HumanoidRootPart"},
    Default = config.hitboxPart,
    Callback = function(value)
        config.hitboxPart = value
        if config.hitboxEnabled then
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
            updateAllHitboxes()
        end
    end
})

HitboxTab:Button({
    Title = "Refresh Hitboxes",
    Desc = "Manually refresh all hitboxes",
    Callback = function()
        if config.hitboxEnabled then
            for player, _ in pairs(playerHitboxes) do
                removeHitboxForPlayer(player)
            end
            updateAllHitboxes()
            hookFastCastRedux()
            hookHitRemote()
            print("Hitboxes refreshed and hooks re-established!")
        else
            print("Hitbox extender is disabled. Enable it first.")
        end
    end
})

HitboxTab:Button({
    Title = "Force Hook FastCast",
    Desc = "Manually hook FastCastRedux if it wasn't detected",
    Callback = function()
        local success = hookFastCastRedux()
        if success then
            print("FastCastRedux hooked successfully!")
        else
            print("Failed to hook FastCastRedux. Check console for details.")
        end
    end
})

HitboxTab:Paragraph({
    Title = "FastCast Status",
    Desc = fastCastHooked and "FastCastRedux is hooked!" or "FastCastRedux not hooked yet."
})

HitboxTab:Paragraph({
    Title = "Hitbox Info",
    Desc = "Hitboxes are created on enemy players. With FastCastRedux hooks, shots that hit the extended hitbox will register as hits on the actual player."
})

-- ===== CALIBRATION TAB =====
CalibrationTab:Toggle({
    Title = "Auto Calibration",
    Desc = "Automatically detect bullet velocity, drop, and ping",
    Default = config.autoCalibration,
    Callback = function(value)
        config.autoCalibration = value
        if value then
            performAutoCalibration()
        end
    end
})

CalibrationTab:Toggle({
    Title = "Adaptive Calibration",
    Desc = "Adjust prediction values based on hit/miss ratio",
    Default = config.adaptiveCalibration,
    Callback = function(value)
        config.adaptiveCalibration = value
    end
})

CalibrationTab:Button({
    Title = "Calibrate Now",
    Desc = "Manually run auto-calibration",
    Callback = function()
        performAutoCalibration()
        print("Calibration complete! Detected values:")
        print("Ping: " .. math.floor(autoCalc.ping * 1000) .. "ms")
        print("Bullet Velocity: " .. config.bulletVelocity .. " studs/s")
        print("Bullet Drop: " .. config.bulletDrop .. " studs/s²")
        print("Prediction: " .. config.prediction)
    end
})

CalibrationTab:Button({
    Title = "Reset Statistics",
    Desc = "Reset hit/miss tracking statistics",
    Callback = function()
        autoCalc.totalShots = 0
        autoCalc.totalHits = 0
        autoCalc.hitRate = 0
        print("Statistics reset!")
        if isUILoaded and guiElements.hitRateText then
            pcall(function()
                guiElements.hitRateText:SetDesc("Current hit rate: 0% (0/0)")
            end)
        end
    end
})

CalibrationTab:Button({
    Title = "Unload Script",
    Desc = "Completely unload the script and clean up all connections",
    Callback = function()
        cleanup()
    end
})

local hitRateText = CalibrationTab:Paragraph({
    Title = "Hit Statistics",
    Desc = "Current hit rate: 0% (0/0)",
})
guiElements.hitRateText = hitRateText

local calibrationTargetText = CalibrationTab:Paragraph({
    Title = "Active Calibration Target",
    Desc = "Currently calibrating: " .. autoCalc.calibrationTarget,
})
guiElements.calibrationTargetText = calibrationTargetText

local remoteStatusText = CalibrationTab:Paragraph({
    Title = "Remote Status",
    Desc = autoCalc.remoteFound and "Remote found: " .. autoCalc.remoteName .. " at " .. (autoCalc.remotePath or "unknown path") or "Remote not found",
})
guiElements.remoteStatusText = remoteStatusText

CalibrationTab:Button({
    Title = "Find Hit Remote",
    Desc = "Manually search for the Hit remote",
    Callback = function()
        print("Manual remote search...")
        local found = setupHitRemoteListener()
        if found then
            print("Found remote: " .. autoCalc.remoteName)
            if isUILoaded and guiElements.remoteStatusText then
                pcall(function()
                    guiElements.remoteStatusText:SetDesc("Remote found: " .. autoCalc.remoteName .. " at " .. (autoCalc.remotePath or "unknown path"))
                end)
            end
        else
            print("No remote found.")
        end
    end
})

-- ===== FOV TAB =====
FOVTab:Toggle({
    Title = "Show FOV Circle",
    Desc = "Toggle FOV circle visibility",
    Default = config.showFOV,
    Callback = function(value)
        config.showFOV = value
        if fovCircle then
            fovCircle.Enabled = value and config.enabled
        end
    end
})

FOVTab:Colorpicker({
    Title = "FOV Color",
    Desc = "Choose FOV circle color",
    Default = config.fovColor,
    Callback = function(color)
        config.fovColor = color
        updateFOVCircle()
    end
})

FOVTab:Slider({
    Title = "FOV Transparency",
    Desc = "FOV circle transparency",
    Step = 0.05,
    Value = {
        Min = 0,
        Max = 1,
        Default = config.fovTransparency
    },
    Callback = function(value)
        config.fovTransparency = value
        updateFOVCircle()
    end
})

-- ===== SETTINGS TAB =====
SettingsTab:Keybind({
    Title = "Toggle Key",
    Desc = "Key to enable/disable silent aim",
    Value = config.toggleKey,
    Callback = function(key)
        config.toggleKey = key
        updateToggleKeybind()
    end
})

SettingsTab:Keybind({
    Title = "GUI Toggle Key",
    Desc = "Key to open/close the GUI",
    Value = config.guikey,
    Callback = function(key)
        config.guikey = key
        Window:SetToggleKey(Enum.KeyCode[key])
    end
})

SettingsTab:Slider({
    Title = "Calibration Rate",
    Desc = "How aggressively to adjust values (higher = faster adjustment)",
    Step = 0.01,
    Value = {
        Min = 0.01,
        Max = 0.2,
        Default = config.calibrationRate
    },
    Callback = function(value)
        config.calibrationRate = value
    end
})

-- ===== UI IS NOW FULLY LOADED =====
isUILoaded = true
print("UI fully loaded!")

-- ===== INITIAL SETUP =====
updateToggleKeybind()

task.wait(1)
local remoteFound = setupHitRemoteListener()

if not remoteFound then
    task.spawn(function()
        while true do
            task.wait(10)
            if setupHitRemoteListener() then
                break
            end
        end
    end)
end

task.wait(1)
performAutoCalibration()

-- Hook FastCastRedux if hitbox extender is enabled
if config.hitboxEnabled then
    task.wait(0.5)
    hookFastCastRedux()
    hookHitRemote()
end

connections.characterAdded = plr.CharacterAdded:Connect(function(character)
    character:WaitForChild("HumanoidRootPart", 5)
    lastTargetPos = {}
    targetVelocities = {}
    currentTarget = nil
    currentTargetPlayer = nil
    if config.autoCalibration then
        performAutoCalibration()
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

print("Silent Aim script loaded successfully!")
print("Press Delete to toggle silent aim on/off")
print("Press RightShift to toggle GUI")
print("Click 'Unload Script' in the Calibration tab to fully unload")
print("Hitbox Extender: " .. (config.hitboxEnabled and "ENABLED" or "DISABLED"))
print("FastCastRedux Hook: " .. (fastCastHooked and "ACTIVE" or "INACTIVE"))
