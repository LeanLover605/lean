-- ===== FIRE HIT REMOTE (UPDATED) =====
local function fireHitRemote(targetPlayer, hitPosition)
    if not hitRemote then
        -- Try to find the remote again
        setupHitRemoteListener()
        if not hitRemote then return end
    end
    
    if not targetPlayer or not targetPlayer.Character then return end
    
    -- Find the humanoid
    local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Get the hit position (use the provided position or fallback to target position)
    local hitPos = hitPosition
    if not hitPos then
        -- Fallback to the target part position
        local targetPart = getTargetPart(targetPlayer)
        if targetPart then
            hitPos = targetPart.Position
        else
            hitPos = targetPlayer.Character.PrimaryPart and targetPlayer.Character.PrimaryPart.Position or targetPlayer.Character.Position
        end
    end
    
    -- Fire the Hit remote with the correct arguments
    -- [1] = The player who fired (shooter)
    -- [2] = Vector3 position of the hit
    -- [3] = The target's Humanoid
    pcall(function()
        hitRemote:FireServer(
            plr,           -- [1] Shooter
            hitPos,        -- [2] Vector3 position
            humanoid       -- [3] Target's Humanoid
        )
        print("Fired Hit remote for: " .. targetPlayer.Name .. " at position: " .. tostring(hitPos))
    end)
end

-- ===== HITBOX TOUCH DETECTION (UPDATED) =====
-- Inside createHitboxForPlayer function, the touch connection:
playerHitboxes[player].connection = hitbox.Touched:Connect(function(hit)
    -- Check if the hit was caused by a bullet/projectile
    if hit and hit.Parent then
        -- Check if it's a bullet or projectile
        local isBullet = hit.Name:match("Bullet") or hit.Name:match("Projectile") or hit.Name:match("Ray") or hit:IsA("Part")
        
        if isBullet then
            -- Get the hit position (where the bullet hit the hitbox)
            local hitPos = hit.Position
            
            -- Fire the Hit remote with the position
            fireHitRemote(player, hitPos)
        end
    end
end)
