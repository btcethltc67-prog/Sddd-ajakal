-- ==========================================
-- SERVICES
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ==========================================
-- STATE
-- ==========================================
local isMoving = false
local autoRunning = false
local character, rootPart, humanoid
local farmToggle = nil
local Rayfield = nil

-- ==========================================
-- STATUS LABEL
-- ==========================================
local statusGui = Instance.new("ScreenGui")
statusGui.Name = "FarmStatusGui"
statusGui.ResetOnSpawn = false
statusGui.Parent = CoreGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 50)
statusLabel.Position = UDim2.new(0, 0, 0, 10)
statusLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
statusLabel.BackgroundTransparency = 0.3
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 28
statusLabel.Text = ""
statusLabel.TextScaled = true
statusLabel.Visible = false
statusLabel.Parent = statusGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = statusLabel

local function setStatus(text)
    statusLabel.Text = text
    statusLabel.Visible = (text ~= "")
end

-- ==========================================
-- DEBUG PLATFORM
-- ==========================================
local platform = Instance.new("Part")
platform.Name = "DebugPathfindPlatform"
platform.Anchored = true
platform.CanCollide = true
platform.Size = Vector3.new(6, 0.5, 6)
platform.Transparency = 0.75
platform.Color = Color3.fromRGB(0, 255, 150)
platform.Material = Enum.Material.ForceField
platform.Parent = workspace
platform.CFrame = CFrame.new(0, -1000, 0)

-- ==========================================
-- PATHFINDING & MOVEMENT
-- ==========================================
local function computePath(startPos, targetPos)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2.0,
        AgentHeight = 3.0,
        AgentCanJump = true,
        WaypointSpacing = 8,
        CostLimit = 100000
    })

    local success = pcall(function()
        path:ComputeAsync(startPos, targetPos)
    end)

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        local cleanPath = {}
        for i, wp in ipairs(waypoints) do
            local pos = wp.Position + Vector3.new(0, 1, 0)
            table.insert(cleanPath, pos)
        end
        return cleanPath
    end
    return nil
end

local function safeSetCFrame(pos)
    if not rootPart or not rootPart.Parent then return false end
    
    local yRot = 0
    local success = pcall(function()
        _, yRot, _ = rootPart.CFrame:ToEulerAnglesYXZ()
    end)
    if not success or yRot ~= yRot then yRot = 0 end
    
    rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, yRot, 0)
    return true
end

local function followPath(path)
    if not path or #path < 2 or not rootPart or not rootPart.Parent then 
        return false 
    end

    local totalDist = 0
    local segmentDists = {}
    
    for i = 2, #path do
        local d = math.max((path[i] - path[i - 1]).Magnitude, 0.001)
        table.insert(segmentDists, d)
        totalDist = totalDist + d
    end

    if totalDist <= 0 then return false end

    local speed = 19.25
    local totalTime = totalDist / speed
    local t = 0
    local lastPos = rootPart.Position
    local lastTime = os.clock()

    while t < 1 and isMoving do
        if not rootPart or not rootPart.Parent then return false end
        
        local rpPos = rootPart.Position
        local dt = os.clock() - lastTime
        lastTime = os.clock()

        if (rpPos - lastPos).Magnitude > 20 then
            return false
        end
        lastPos = rpPos

        t = math.clamp(t + (dt / totalTime), 0, 1)

        local targetDist = t * totalDist
        local accumulated = 0
        local currentPos = path[1]

        for i = 1, #segmentDists do
            if accumulated + segmentDists[i] >= targetDist then
                local segT = (targetDist - accumulated) / segmentDists[i]
                currentPos = path[i]:Lerp(path[i + 1], segT)
                break
            end
            accumulated = accumulated + segmentDists[i]
        end

        if not safeSetCFrame(currentPos) then return false end
        platform.CFrame = CFrame.new(rootPart.Position.X, rootPart.Position.Y - 3.5, rootPart.Position.Z)
        
        RunService.Heartbeat:Wait()
    end

    if isMoving and rootPart and rootPart.Parent then
        safeSetCFrame(path[#path])
    end
    return true
end

local function tweenDirectlyTo(targetPos)
    if not rootPart or not rootPart.Parent then return false end
    
    local startCF = rootPart.CFrame
    local dist = (startCF.Position - targetPos).Magnitude
    if dist < 0.5 then return true end

    local duration = math.max(dist / 19.25, 0.01)
    local t = 0
    local lastPos = rootPart.Position
    local lastTime = os.clock()

    while t < 1 and isMoving do
        if not rootPart or not rootPart.Parent then return false end
        
        local rpPos = rootPart.Position
        local dt = os.clock() - lastTime
        lastTime = os.clock()

        if (rpPos - lastPos).Magnitude > 20 then
            return false
        end
        lastPos = rpPos

        t = math.clamp(t + (dt / duration), 0, 1)
        local newPos = startCF.Position:Lerp(targetPos, t)
        
        if not safeSetCFrame(newPos) then return false end
        platform.CFrame = CFrame.new(rootPart.Position.X, rootPart.Position.Y - 3.5, rootPart.Position.Z)
        
        RunService.Heartbeat:Wait()
    end

    if isMoving and rootPart and rootPart.Parent then
        safeSetCFrame(targetPos)
    end
    return true
end

-- ==========================================
-- MOVEMENT WITH RETRIES
-- ==========================================
local function moveToTarget(targetPos, usePathfindingFirst)
    if not rootPart or not rootPart.Parent then return false end

    local maxRetries = 3
    local attempts = 0

    while autoRunning and attempts < maxRetries do
        if usePathfindingFirst then
            local path = computePath(rootPart.Position, targetPos)
            if path and #path >= 2 then
                if followPath(path) then
                    return true
                end
            else
                if tweenDirectlyTo(targetPos) then
                    return true
                end
            end
        else
            if tweenDirectlyTo(targetPos) then
                return true
            end
            usePathfindingFirst = true
        end
        
        attempts = attempts + 1
        if autoRunning and attempts < maxRetries then
            task.wait(1)
        end
    end

    return false
end

-- ==========================================
-- REMOTE FIRE HELPERS
-- ==========================================
local function fireBushRemote(entityID)
    local b1 = entityID % 256
    local b2 = math.floor(entityID / 256) % 256
    local b3 = math.floor(entityID / 65536) % 256
    local bufferData = string.format(
        "\000\019\001\000%c%c%c\000\000\210\003]\196\001\000@\192\199>NCH\194L\188H\194!#1\205\165\148\218A",
        b1, b2, b3
    )
    pcall(function()
        ReplicatedStorage:WaitForChild("ByteNetReliable"):FireServer(buffer.fromstring(bufferData))
    end)
end

local function fireEssenceRemote(entityID)
    local b1 = entityID % 256
    local b2 = math.floor(entityID / 256) % 256
    local b3 = math.floor(entityID / 65536) % 256
    local bufferData = string.char(0, 0xEA, b1, b2, b3, 0)
    pcall(function()
        ReplicatedStorage:WaitForChild("ByteNetReliable"):FireServer(buffer.fromstring(bufferData))
    end)
end

-- ==========================================
-- FIND FUNCTIONS
-- ==========================================
local function findClosestFeatherBush()
    local resources = workspace:FindFirstChild("Resources")
    if not resources or not rootPart then return nil end

    local charPos = rootPart.Position
    local closest = nil
    local minDist = math.huge

    for _, model in ipairs(resources:GetChildren()) do
        if model:IsA("Model") and model.Name == "Feather Bush" and model.PrimaryPart then
            local dist = (model.PrimaryPart.Position - charPos).Magnitude
            if dist < minDist then
                minDist = dist
                closest = model
            end
        end
    end
    return closest
end

local function findAllEssence()
    local itemsFolder = workspace:FindFirstChild("Items")
    if not itemsFolder then return {} end

    local results = {}
    local function scan(obj)
        if obj.Name == "Essence" then
            local id = obj:GetAttribute("EntityID")
            if id then
                local pos = nil
                if obj:IsA("BasePart") then
                    pos = obj.Position
                elseif obj:IsA("Model") and obj.PrimaryPart then
                    pos = obj.PrimaryPart.Position
                else
                    for _, child in ipairs(obj:GetDescendants()) do
                        if child:IsA("BasePart") then
                            pos = child.Position
                            break
                        end
                    end
                end
                if pos then
                    table.insert(results, { object = obj, entityID = id, position = pos })
                end
            end
        end
        for _, child in ipairs(obj:GetChildren()) do
            scan(child)
        end
    end

    scan(itemsFolder)
    return results
end

-- ==========================================
-- CHARACTER TRACKING
-- ==========================================
local function cleanupMovement()
    isMoving = false
    autoRunning = false
    pcall(function()
        if humanoid then humanoid.PlatformStand = false end
    end)
    platform.CFrame = CFrame.new(0, -1000, 0)
    setStatus("")
end

local function onCharacterAdded(char)
    character = char
    rootPart = char:WaitForChild("HumanoidRootPart")
    humanoid = char:WaitForChild("Humanoid")
    cleanupMovement()
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

-- ==========================================
-- FARMING LOGIC
-- ==========================================
local function startFarming()
    if autoRunning then return end

    if not rootPart or not humanoid then
        if Rayfield then
            Rayfield:Notify({
                Title = "Error",
                Content = "No character found!",
                Duration = 3
            })
        end
        if farmToggle then farmToggle:Set(false) end
        return
    end

    autoRunning = true
    isMoving = true
    pcall(function() humanoid.PlatformStand = true end)

    task.spawn(function()
        local success, err = pcall(function()
            local currentY = rootPart.Position.Y

            if currentY <= 120 then
                setStatus("Tweening to waterfall...")
                if not moveToTarget(Vector3.new(-170, -3, -704), true) then return end

                if not moveToTarget(Vector3.new(-119, -6, -693), false) then return end

                if not moveToTarget(Vector3.new(-119, 149, -693), false) then return end

                if not moveToTarget(Vector3.new(-208, 149, -675), false) then return end
            end

            -- ==========================================
            -- FEATHER BUSH HARVEST LOOP
            -- ==========================================
            while autoRunning do
                local bush = findClosestFeatherBush()
                while not bush and autoRunning do
                    setStatus("Waiting for bush to spawn...")
                    task.wait(1)
                    bush = findClosestFeatherBush()
                end
                if not autoRunning then break end

                local entityID = bush:GetAttribute("EntityID")
                if not entityID then
                    setStatus("Bush has no ID, skipping...")
                    task.wait(1)
                    goto bush_skip
                end

                local bushPos = bush.PrimaryPart.Position
                local bushAlive = true

                -- Early harvest in parallel
                task.spawn(function()
                    while autoRunning and bushAlive do
                        if not rootPart then break end
                        local dist = (rootPart.Position - bushPos).Magnitude
                        if dist <= 15 then
                            setStatus("Harvesting feather bush...")
                            while autoRunning and bushAlive do
                                if not bush.Parent or not bush.PrimaryPart then
                                    bushAlive = false
                                    break
                                end
                                fireBushRemote(entityID)
                                task.wait(0.05)
                            end
                            break
                        end
                        task.wait(0.1)
                    end
                end)

                setStatus("Moving to feather bush...")
                if not moveToTarget(bushPos, true) then break end

                while autoRunning and bushAlive do
                    if not bush.Parent or not bush.PrimaryPart then
                        bushAlive = false
                        break
                    end
                    fireBushRemote(entityID)
                    task.wait(0.05)
                end

                if not autoRunning then break end
                setStatus("Bush destroyed, searching for essence...")
                task.wait(0.5)

                -- ==========================================
                -- ESSENCE PICKUP
                -- ==========================================
                local pickedEssence = false
                local essenceAttempts = 0
                local maxEssenceAttempts = 30

                while autoRunning and not pickedEssence and essenceAttempts < maxEssenceAttempts do
                    local essences = findAllEssence()
                    if #essences > 0 then
                        local nearest = essences[1]
                        local minDist = (nearest.position - rootPart.Position).Magnitude
                        
                        for i = 2, #essences do
                            local d = (essences[i].position - rootPart.Position).Magnitude
                            if d < minDist then
                                minDist = d
                                nearest = essences[i]
                            end
                        end

                        if nearest then
                            local essPos = nearest.position
                            local essID = nearest.entityID
                            local essencePicked = false

                            task.spawn(function()
                                while autoRunning and not essencePicked do
                                    if not rootPart then break end
                                    local dist = (rootPart.Position - essPos).Magnitude
                                    if dist <= 20 then
                                        setStatus("Picking up essence...")
                                        for _ = 1, 10 do
                                            if not autoRunning then break end
                                            fireEssenceRemote(essID)
                                            task.wait(0.1)
                                        end
                                        essencePicked = true
                                        break
                                    end
                                    task.wait(0.1)
                                end
                            end)

                            if moveToTarget(essPos, true) then
                                for i = 1, 5 do
                                    if not autoRunning then break end
                                    fireEssenceRemote(essID)
                                    task.wait(0.1)
                                end
                                pickedEssence = true
                            else
                                break
                            end
                        end
                    else
                        essenceAttempts = essenceAttempts + 1
                        task.wait(0.1)
                    end
                end

                if not pickedEssence and autoRunning then
                    setStatus("No essence found, moving to next bush...")
                    task.wait(1)
                end

                ::bush_skip::
            end
        end)

        if not success then
            if Rayfield then
                Rayfield:Notify({
                    Title = "Error",
                    Content = tostring(err),
                    Duration = 5
                })
            end
            setStatus("Error: " .. tostring(err))
        end

        cleanupMovement()
        if farmToggle then farmToggle:Set(false) end
    end)
end

local function stopFarming()
    autoRunning = false
    isMoving = false
    cleanupMovement()
    setStatus("")
end

-- ==========================================
-- LOAD RAYFIELD AND CREATE UI
-- ==========================================
local function initializeUI()
    local loadSuccess, result = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)

    if not loadSuccess or not result then
        warn("Failed to load Rayfield")
        setStatus("Rayfield failed to load")
        return false
    end

    Rayfield = result

    local Window = Rayfield:CreateWindow({
        Name = "Auto Route Tool",
        LoadingTitle = "Auto Route Tool",
        LoadingSubtitle = "by YourName",
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "AutoRouteTool",
            FileName = "Settings"
        },
        Discord = {
            Enabled = false,
            Invite = "noinvitelink",
            RememberJoins = true
        },
        KeySystem = false
    })

    local MainTab = Window:CreateTab("Main", 0)

    farmToggle = MainTab:CreateToggle({
        Name = "Farm exp (Feather bush)",
        CurrentValue = false,
        Flag = "FarmExpToggle",
        Callback = function(Value)
            if Value then
                startFarming()
            else
                stopFarming()
            end
        end
    })

    return true
end

-- Initialize on script load
print("Loading farming bot...")
if initializeUI() then
    print("UI loaded successfully!")
else
    print("Failed to initialize UI")
end
