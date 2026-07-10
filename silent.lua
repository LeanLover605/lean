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
    toggleKey = "F",
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

-- ===== ON HIT DETECTED =====
local function onHitDetected(...)
    -- Track the hit
    autoCalc.totalShots = autoCalc.totalShots + 1
    autoCalc.totalHits = autoCalc.totalHits + 1
    autoCalc.hitRate = autoCalc.totalHits / autoCalc.totalShots
    
    print("HIT DETECTED! Hit rate: " .. math.floor(autoCalc.hitRate * 100) .. "% (" .. autoCalc.totalHits .. "/" .. autoCalc.totalShots .. ")")
    
    -- Update UI if it exists
    if guiElements and guiElements.hitRateText then
        pcall(function()
            guiElements.hitRateText:SetDesc("Current hit rate: " .. math.floor(autoCalc.hitRate * 100) .. "% (" .. autoCalc.totalHits .. "/" .. autoCalc.totalShots .. ")")
        end)
    end
    
    if config.adaptiveCalibration and autoCalc.totalShots >= 5 then
        performAdaptiveCalibration()
    end
end

-- ===== ADAPTIVE CALIBRATION =====
local function performAdaptiveCalibration(force)
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
        
        -- Update UI
        if guiElements and guiElements.calibrationTargetText then
            pcall(function()
                guiElements.calibrationTargetText:SetDesc("Currently calibrating: " .. autoCalc.calibrationTarget)
            end)
        end
    end
end

-- ===== INTERCEPT HIT REMOTE =====
local function setupHitRemoteListener()
    if remoteSearching then return false end
    remoteSearching = true
    
    print("Looking for Hit remote at: ReplicatedStorage.Tools.Components.Muzzle.Hit")
    
    -- Try the specific path first
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
                    
                    -- Setup listener based on remote type
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

-- ===== TRACK SHOT ATTEMPTS =====
local function trackShotAttempt()
    local currentTime = tick()
    if currentTime - autoCalc.lastShotTime > autoCalc.shotCooldown then
        autoCalc.totalShots = autoCalc.totalShots + 1
        autoCalc.lastShotTime = currentTime
        
        -- Update UI
        if guiElements and guiElements.hitRateText then
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
    
    -- Track mouse clicks for shot attempts
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

RunService.RenderStepped:Connect(function()
    pcall(onRenderStepped)
end)

task.spawn(function()
    while task.wait(0.05) do
        pcall(updateTargetVelocities)
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
    
    Size = UDim2.fromOffset(600, 550),
    MinSize = Vector2.new(560, 400),
    MaxSize = Vector2.new(850, 600),
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

local MainTab = Window:Tab({
    Title = "Main",
    Icon = "crosshair"
})

local PredictionTab = Window:Tab({
    Title = "Prediction",
    Icon = "target"
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

PredictionTab:Slider({
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

PredictionTab:Slider({
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

PredictionTab:Slider({
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

PredictionTab:Slider({
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
        if guiElements.hitRateText then
            pcall(function()
                guiElements.hitRateText:SetDesc("Current hit rate: 0% (0/0)")
            end)
        end
    end
})

-- Hit rate display
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
            if guiElements.remoteStatusText then
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
    Default = config.toggleKey,
    Callback = function(key)
        config.toggleKey = key
        updateToggleKeybind()
    end
})

SettingsTab:Keybind({
    Title = "GUI Toggle Key",
    Desc = "Key to open/close the GUI",
    Default = config.guikey,
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

-- ===== INITIAL SETUP =====
updateToggleKeybind()

-- Setup hit remote listener with specific path
task.wait(1)
local remoteFound = setupHitRemoteListener()

if not remoteFound then
    -- Keep trying to find the remote
    task.spawn(function()
        while true do
            task.wait(10)
            if setupHitRemoteListener() then
                break
            end
        end
    end)
end

-- Run initial calibration AFTER UI is created
task.wait(1)
performAutoCalibration()

plr.CharacterAdded:Connect(function(character)
    character:WaitForChild("HumanoidRootPart", 5)
    lastTargetPos = {}
    targetVelocities = {}
    currentTarget = nil
    currentTargetPlayer = nil
    if config.autoCalibration then
        performAutoCalibration()
    end
end)

print("Silent Aim script loaded successfully!")
