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
    autoPrediction = true
}

-- ===== STATE =====
local toggleKeyConnection = nil
local fovCircle = nil
local lastTargetPos = {}
local targetVelocities = {}
local currentTarget = nil
local currentTargetPlayer = nil
local enabledToggleElement = nil -- Store reference to toggle element

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
    outline.Image = "rbxassetid://8789695013"
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
    centerDot.Image = "rbxassetid://8789695013"
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
                    targetVelocities[player] = delta / dt
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
    
    if config.autoPrediction and targetVelocities[player] then
        local velocity = targetVelocities[player]
        local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
        local bulletTravelTime = math.clamp(distance / config.bulletVelocity, 0, 1)
        local leadTime = math.max(config.prediction, bulletTravelTime * 0.5)
        
        basePosition = basePosition + (velocity * leadTime)
    end
    
    if config.bulletDrop > 0 then
        local distance = (basePosition - Camera.CFrame.Position).Magnitude
        local bulletTravelTime = math.clamp(distance / config.bulletVelocity, 0, 2)
        local drop = 0.5 * config.bulletDrop * bulletTravelTime * bulletTravelTime
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
    
    -- Update the toggle element without calling its Set method
    if enabledToggleElement then
        -- Use pcall to handle any internal errors
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
            -- Toggle the config value directly
            config.enabled = not config.enabled
            
            -- Update UI elements without creating loops
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
    Icon = "lucide:crosshair", -- lucide icon
    Author = "by Prayut",
    Folder = "SilentAim",
    
    -- Window settings
    Size = UDim2.fromOffset(600, 500),
    MinSize = Vector2.new(560, 350),
    MaxSize = Vector2.new(850, 560),
    ToggleKey = Enum.KeyCode.RightShift,
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 200,
    BackgroundImageTransparency = 0.42,
    HideSearchBar = true,
    ScrollBarEnabled = false,
    
    -- User profile (non-anonymous)
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
        -- Only update if the value actually changed
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
    Title = "Prediction Time",
    Desc = "Seconds to predict ahead",
    Step = 0.01,
    Value = {
        Min = 0,
        Max = 1,
        Default = config.prediction
    },
    Callback = function(value) 
        config.prediction = value 
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

-- ===== INITIAL SETUP =====
updateToggleKeybind()

plr.CharacterAdded:Connect(function(character)
    character:WaitForChild("HumanoidRootPart", 5)
    lastTargetPos = {}
    targetVelocities = {}
    currentTarget = nil
    currentTargetPlayer = nil
end)

print("Silent Aim script loaded successfully!")
