local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WORLD3_PLACE_ID = 93411036959889
local UINT32_RANGE = 4294967296
local MOTION_TICK = 1 / 30
local POLL_TICK = 0.05
local player = Players.LocalPlayer

_G.CelestialFarmGeneration = (_G.CelestialFarmGeneration or 0) + 1
_G.World3AutoRouteSession = (_G.World3AutoRouteSession or 0) + 1
_G.World3AutoRouteRun = (_G.World3AutoRouteRun or 0) + 1

local generation = _G.CelestialFarmGeneration

pcall(function()
    if _G.CelestialFarmUI then
        _G.CelestialFarmUI:Destroy()
    end
end)

pcall(function()
    UI.RemoveTab("World 3")
    UI.RemoveTab("BBNO$ World")
    UI.RemoveTab("BBNO$")
    UI.RemoveTab("Summer Coins")
    UI.RemoveTab("Events")
end)

local INS_UI_URL = "https://raw.githubusercontent.com/mrketa/celestial-autofarm/main/celestial_ui.lua"
local fetched, librarySource = pcall(function()
    if isfile("celestial_ui.lua") then
        return readfile("celestial_ui.lua")
    end

    return game:HttpGet(INS_UI_URL)
end)

if not fetched or type(librarySource) ~= "string" then
    warn("[Celestial] INS-ui download failed")
    return
end

local Lib = loadstring(librarySource)() or INSui

if not Lib then
    warn("[Celestial] INS-ui could not be loaded")
    return
end

local function getRoot()
    local character = player.Character

    return character
        and character:FindFirstChild("HumanoidRootPart")
end

local function getWorld3Wins()
    local leaderstats = player:FindFirstChild("leaderstats")
    return leaderstats and leaderstats:FindFirstChild("Wins")
end

local function stopPart(root)
    if root and root.AssemblyLinearVelocity.Magnitude > 0.05 then
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

local function stopRoot()
    stopPart(getRoot())
end

local function formatNumber(value)
    local formatted = tostring(math.floor(value or 0))

    while true do
        local replacements

        formatted, replacements = string.gsub(
            formatted,
            "^(-?%d+)(%d%d%d)",
            "%1.%2"
        )

        if replacements == 0 then
            return formatted
        end
    end
end

local function cashDelta(currentValue, previousValue)
    return (currentValue - previousValue) % UINT32_RANGE
end

local function cleanError(value)
    local text = tostring(value or "Unknown error")
    local message = string.match(text, "^[^:]+:%d+:%s*(.+)$")

    return message or text
end

local world3 = {
    auto = false,
    running = false,
    route = "Stage 1",
    speed = 300,
    status = "Ready",
    point = "Spawn",
    cycles = 0,
    earned = 0,
    lastReward = 0,
    lastRewardAt = nil,
    runToken = 0,
    spawnPosition = nil,
    eventsActive = false,
    autoVoidRecovery = true,
    voidRecoveryPending = false,
    voidRecoveries = 0
}

local returnToWorld3Spawn

local WORLD3_STAGE5_MINIMUM_TIME = 12.5
local WORLD3_STAGE5_WIN_PLATE = Vector3.new(
    -1431.3326,
    536.1462,
    759.6248
)
local WORLD3_STAGE6_MINIMUM_TIME = 15.5
local WORLD3_STAGE6_WIN_PLATE = Vector3.new(
    -1431.4525,
    533.6140,
    1329.8270
)
local WORLD3_STAGE7_MINIMUM_TIME = 18.5
local WORLD3_STAGE7_WIN_PLATE = Vector3.new(
    -2062.3730,
    443.6126,
    1459.3718
)
local WORLD3_STAGE1_REWARD_INTERVAL = 3
local WORLD3_ROUTE = {
    {
        name = "Safe Start",
        position = Vector3.new(
            -1473.716797,
            -158.274429,
            -956.626160
        ),
        physics = true,
        dwell = 0.15
    },
    {
        name = "Stage 1",
        position = Vector3.new(
            -1490.1263427734375,
            -68.3874282836914,
            -533.1188354492188
        )
    },
    {
        name = "Stage 2",
        position = Vector3.new(
            -1476.367431640625,
            -56.145263671875,
            -36.770565032958984
        )
    },
    {
        name = "Stage 3 Rise",
        position = Vector3.new(
            -1453.0216064453125,
            258.1046447753906,
            12.547174453735352
        )
    },
    {
        name = "Stage 3 Gate",
        position = Vector3.new(
            -1454.333984375,
            215.8647003173828,
            328.38763427734375
        )
    },
    {
        name = "Stage 4 Ladder",
        position = Vector3.new(
            -1453.474365234375,
            215.8647003173828,
            623.4430541992188
        )
    },
    {
        name = "Stage 4 Top",
        position = Vector3.new(
            -1403.07275390625,
            589.49755859375,
            723.4365234375
        )
    },
    {
        name = "Win staging",
        position = Vector3.new(
            -1403.2591552734375,
            533.8761596679688,
            768.9608764648438
        )
    }
}
local WORLD3_STAGE6_ROUTE = {}

for index = 1, #WORLD3_ROUTE - 1 do
    table.insert(WORLD3_STAGE6_ROUTE, WORLD3_ROUTE[index])
end

for _, point in ipairs({
    {
        name = "Stage 5 Lower",
        position = Vector3.new(-1404.4468, 390.5382, 724.7380)
    },
    {
        name = "Stage 5 Rise",
        position = Vector3.new(-1404.4468, 533.8660, 724.7380)
    },
    {
        name = "Stage 5 Curve 1",
        position = Vector3.new(-1400.3630, 533.8660, 772.5512)
    },
    {
        name = "Stage 5 Curve 2",
        position = Vector3.new(-1362.1042, 533.8660, 840.0916)
    },
    {
        name = "Stage 5 Curve 3",
        position = Vector3.new(-1303.8162, 533.8660, 915.6722)
    },
    {
        name = "Stage 5 Curve 4",
        position = Vector3.new(-1260.5690, 533.8660, 1030.5386)
    },
    {
        name = "Stage 5 Curve 5",
        position = Vector3.new(-1280.7828, 533.8660, 1100.2794)
    },
    {
        name = "Stage 5 Curve 6",
        position = Vector3.new(-1337.5544, 533.8660, 1205.0078)
    },
    {
        name = "Stage 5 Curve 7",
        position = Vector3.new(-1397.1460, 533.8660, 1344.5568)
    },
    {
        name = "WinBlock36 staging",
        position = Vector3.new(-1422.8318, 533.8660, 1335.9071)
    }
}) do
    table.insert(WORLD3_STAGE6_ROUTE, point)
end

local WORLD3_STAGE7_ROUTE = {}

for index = 1, #WORLD3_STAGE6_ROUTE - 1 do
    table.insert(WORLD3_STAGE7_ROUTE, WORLD3_STAGE6_ROUTE[index])
end

for _, point in ipairs({
    {
        name = "Stage 6 Curve 1",
        position = Vector3.new(-1391.9022, 533.8642, 1365.9102)
    },
    {
        name = "Stage 6 Curve 2",
        position = Vector3.new(-1397.8521, 533.8641, 1406.8398)
    },
    {
        name = "Stage 6 Gate",
        position = Vector3.new(-1402.4264, 533.8641, 1427.2498)
    },
    {
        name = "Stage 6 Drop 1",
        position = Vector3.new(-1397.9819, 541.0258, 1448.9692),
        tsunamiWindow = true,
        minimumSpeed = 300
    },
    {
        name = "Stage 6 Drop 2",
        position = Vector3.new(-1433.3904, 502.0983, 1465.3796),
        minimumSpeed = 300
    },
    {
        name = "Stage 6 Floor",
        position = Vector3.new(-1475.4453, 443.2820, 1472.2993),
        minimumSpeed = 300
    },
    {
        name = "Stage 6 Run 1",
        position = Vector3.new(-1582.7493, 443.8641, 1475.2930),
        minimumSpeed = 300
    },
    {
        name = "Stage 6 Run 2",
        position = Vector3.new(-1708.5725, 443.8643, 1477.6670),
        minimumSpeed = 300
    },
    {
        name = "Stage 6 Run 3",
        position = Vector3.new(-1834.3958, 443.8653, 1478.9807),
        minimumSpeed = 300
    },
    {
        name = "Stage 6 Run 4",
        position = Vector3.new(-1951.4202, 446.4776, 1479.5720),
        minimumSpeed = 300
    },
    {
        name = "WinBlock37 safezone",
        position = Vector3.new(-2058.228516, 443.873718, 1484.287231),
        dwell = 0.25,
        minimumSpeed = 300
    }
}) do
    table.insert(WORLD3_STAGE7_ROUTE, point)
end

local function world3MayContinue(forceRun, token)
    return generation == _G.CelestialFarmGeneration
        and token == world3.runToken
        and not world3.eventsActive
        and (forceRun or world3.auto)
end

local function waitForWorld3Spawn(forceRun, token)
    local deadline = tick() + 8
    local stableSince
    local lastPosition

    world3.status = "Syncing spawn"
    world3.point = "Spawn"

    while tick() < deadline do
        if not world3MayContinue(forceRun, token) then
            return false
        end

        local root = getRoot()

        if root then
            local position = root.Position
            local atSpawn = position.Y > -300
                and position.Y < -120
                and position.Z < -900
            local stable = lastPosition
                and (position - lastPosition).Magnitude < 1

            if atSpawn and stable then
                stableSince = stableSince or tick()

                if tick() - stableSince >= 0.35 then
                    stopPart(root)
                    world3.spawnPosition = position
                    return true
                end
            else
                stableSince = nil
            end

            lastPosition = position
        else
            stableSince = nil
            lastPosition = nil
        end

        task.wait(POLL_TICK)
    end

    return false
end

local function tweenWorld3(target, forceRun, token, dwell, speed)
    local root = getRoot()

    if not root then
        return false, "Character unavailable"
    end

    local startPosition = root.Position
    local distance = (target - startPosition).Magnitude
    local duration = distance / math.max(speed or world3.speed, 1)
    local startedAt = tick()

    while tick() - startedAt < duration do
        if not world3MayContinue(forceRun, token) then
            stopPart(root)
            return false, "Stopped"
        end

        root = getRoot()

        if not root then
            return false, "Character was replaced"
        end

        local alpha = math.min((tick() - startedAt) / duration, 1)
        local position = startPosition:Lerp(target, alpha)

        stopPart(root)
        root.CFrame = CFrame.new(position.X, position.Y, position.Z)
        task.wait(MOTION_TICK)
    end

    root = getRoot()

    if not root then
        return false, "Character was replaced"
    end

    stopPart(root)
    root.CFrame = CFrame.new(target.X, target.Y, target.Z)
    task.wait(dwell or 0.2)

    if (root.Position - target).Magnitude > 12 then
        return false, "Movement was corrected"
    end

    return true
end

local function moveWorld3Physics(target, forceRun, token, dwell)
    local deadline = tick() + 2

    while tick() < deadline do
        if not world3MayContinue(forceRun, token) then
            return false, "Stopped"
        end

        local root = getRoot()

        if not root then
            return false, "Character unavailable"
        end

        local offset = Vector3.new(
            target.X - root.Position.X,
            0,
            target.Z - root.Position.Z
        )

        if offset.Magnitude <= 3 then
            stopPart(root)
            task.wait(dwell or 0.05)
            return true
        end

        root.AssemblyLinearVelocity = Vector3.new(
            offset.Unit.X * 100,
            root.AssemblyLinearVelocity.Y,
            offset.Unit.Z * 100
        )
        task.wait(MOTION_TICK)
    end

    stopRoot()
    return false, "Safe Start not reached"
end

local function enterWorld3WinPlate(
    cashValue,
    cashBefore,
    forceRun,
    token,
    target,
    stageLabel
)
    local deadline = tick() + 5
    local reached = false

    world3.status = "Entering " .. stageLabel
    world3.point = stageLabel

    while tick() < deadline do
        if cashValue.Value ~= cashBefore then
            return true
        elseif not world3MayContinue(forceRun, token) then
            return false
        end

        local root = getRoot()

        if not root then
            return false
        end

        local offset = Vector3.new(
            target.X - root.Position.X,
            0,
            target.Z - root.Position.Z
        )

        if offset.Magnitude <= 1.5 then
            stopPart(root)
            reached = true
            break
        end

        root.AssemblyLinearVelocity = Vector3.new(
            offset.Unit.X * 70,
            root.AssemblyLinearVelocity.Y,
            offset.Unit.Z * 70
        )
        task.wait(MOTION_TICK)
    end

    stopRoot()

    if not reached then
        return cashValue.Value ~= cashBefore
    end

    world3.status = "Confirming reward"
    local rewardDeadline = tick() + 5

    while tick() < rewardDeadline do
        if cashValue.Value ~= cashBefore then
            return true
        elseif not world3MayContinue(forceRun, token) then
            return false
        end

        task.wait(POLL_TICK)
    end

    return cashValue.Value ~= cashBefore
end

local function waitForWorld3Reset(forceRun, token)
    local deadline = tick() + 8

    world3.status = "Preparing next run"
    world3.point = "Reset"

    while tick() < deadline do
        if not world3MayContinue(forceRun, token) then
            return false
        end

        local root = getRoot()

        if root
            and root.Position.Y > -300
            and root.Position.Y < -120
            and root.Position.Z < -900
        then
            task.wait(0.5)
            return true
        end

        task.wait(POLL_TICK)
    end

    return false
end

local function waitForWorld3TsunamiWindow(forceRun, token)
    local deadline = tick() + 8

    world3.status = "Waiting for tsunami window"
    world3.point = "Stage 6 Gate"

    while tick() < deadline do
        if not world3MayContinue(forceRun, token) then
            return false, "Stopped"
        end

        local hazards = workspace:FindFirstChild("NPC & Piege")
        local tsunamiModel = hazards
            and hazards:FindFirstChild("Tsunami1")
        local tsunami = tsunamiModel
            and tsunamiModel:FindFirstChild("Tsunami")

        if not tsunami or not tsunami:IsA("BasePart") then
            return false, "Tsunami not found"
        end

        local tsunamiX = tsunami.Position.X

        if tsunamiX < -1625 and tsunamiX > -1725 then
            return true
        end

        task.wait(0.02)
    end

    return false, "No safe tsunami window detected"
end

local function forceWorld3VoidRecovery(forceRun, token)
    assert(world3MayContinue(forceRun, token), "Stopped")

    if world3.voidRecoveryPending or not world3.autoVoidRecovery then
        return false
    end

    local character = player.Character
    local root = getRoot()
    local humanoid = character
        and character:FindFirstChildOfClass("Humanoid")

    if not character or not root then
        return false
    end

    world3.voidRecoveryPending = true
    world3.status = "Forcing character reset"
    world3.point = "Reset"
    world3.spawnPosition = nil

    assert(world3MayContinue(forceRun, token), "Stopped")
    local killed = pcall(function()
        if humanoid then
            humanoid.Health = 0
            humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        end
        character:BreakJoints()
    end)

    if not killed then
        world3.voidRecoveryPending = false
        return false
    end

    local deadline = tick() + 15
    local lastDropAt = tick()

    while tick() < deadline do
        assert(world3MayContinue(forceRun, token), "Stopped")

        local currentRoot = getRoot()
        local currentPosition = currentRoot and currentRoot.Position
        local atSpawn = currentPosition
            and currentPosition.Y > -300
            and currentPosition.Y < -120
            and currentPosition.Z < -900

        if atSpawn then
            world3.status = "Verifying void recovery"
            world3.point = "Spawn"
            task.wait(0.5)
            local recovered = waitForWorld3Spawn(forceRun, token)
            if not recovered then
                world3.voidRecoveryPending = false
            end
            return recovered
        elseif tick() - lastDropAt >= 0.4 then
            pcall(function()
                stopPart(root)
                root.Position = Vector3.new(
                    root.Position.X,
                    -1000,
                    -1000
                )
                root.AssemblyLinearVelocity = Vector3.new(
                    0,
                    -250,
                    0
                )
            end)

            if not currentRoot then
                pcall(function()
                    character:BreakJoints()
                end)
            end

            lastDropAt = tick()
        end

        task.wait(0.1)
    end

    world3.voidRecoveryPending = false
    return false
end

local function confirmWorld3RewardHealth()
    if not world3.voidRecoveryPending then
        return
    end

    world3.voidRecoveryPending = false
    world3.voidRecoveries = world3.voidRecoveries + 1
    Lib:Notify(
        "Void Recovery",
        "Wins collection restored.",
        4,
        "success"
    )
end

local function getWorld3Stage1WinBlock()
    local structure = workspace:FindFirstChild("Structure")
    local stage1 = structure and structure:FindFirstChild("Stage1")
    local sas = stage1 and stage1:FindFirstChild("SAS")
    local winBlock = sas and sas:FindFirstChild("WinBlock32")

    if winBlock and winBlock:IsA("BasePart") then
        return winBlock
    end

    return nil
end

local function runWorld3Stage1Attempt(forceRun, token)
    if not waitForWorld3Spawn(forceRun, token) then
        assert(world3MayContinue(forceRun, token), "Stopped")
        error("No stable spawn found")
    end

    local safeStart = WORLD3_ROUTE[1]

    world3.status = "Moving to Safe Start"
    world3.point = "Stage1SafeStart"

    local safe, safeError = moveWorld3Physics(
        safeStart.position,
        forceRun,
        token,
        safeStart.dwell
    )

    assert(safe, "Safe Start: " .. tostring(safeError))

    local cashValue = getWorld3Wins()
    local winBlock = getWorld3Stage1WinBlock()

    assert(cashValue, "Wins value unavailable")
    assert(winBlock, "WinBlock32 not found")

    local root = getRoot()
    assert(root, "Character unavailable")
    local stage1Entry = WORLD3_ROUTE[2].position
    local cashBefore = cashValue.Value

    world3.status = "Going directly to Stage 1"
    world3.point = "Stage 1 Entrance"
    local reachedStage1 = false

    for attempt = 1, 3 do
        assert(world3MayContinue(forceRun, token), "Stopped")
        root = getRoot()
        assert(root, "Character unavailable")

        root.CFrame = CFrame.new(
            stage1Entry.X,
            stage1Entry.Y,
            stage1Entry.Z
        )
        stopPart(root)
        task.wait(0.08)

        root = getRoot()

        if root and (root.Position - stage1Entry).Magnitude <= 15 then
            reachedStage1 = true
            break
        end

        if attempt < 3 then
            world3.status = string.format(
                "Stage 1 attempt %d/3",
                attempt + 1
            )
        end
    end

    if not reachedStage1 then
        stopRoot()
        world3.status = "Correcting Stage 1 teleport"
        world3.point = "Recovery"

        if world3.autoVoidRecovery then
            if world3.voidRecoveryPending then
                error("Position correction remained after void recovery")
            end

            if forceWorld3VoidRecovery(forceRun, token) then
                return false
            end

            error("Void recovery failed")
        end

        repeat
            assert(world3MayContinue(forceRun, token), "Stopped")
            world3.status = "Returning to spawn"
            task.wait(0.5)
        until returnToWorld3Spawn()

        return false
    end

    local walkTarget = winBlock.Position
    local walkSpeed = 60

    if world3.lastRewardAt then
        local estimatedWalkTime = (
            Vector3.new(
                walkTarget.X - root.Position.X,
                0,
                walkTarget.Z - root.Position.Z
            ).Magnitude
        ) / walkSpeed
        local walkAt = world3.lastRewardAt
            + WORLD3_STAGE1_REWARD_INTERVAL
            - estimatedWalkTime

        world3.status = "Waiting for movement window"

        while tick() < walkAt do
            assert(world3MayContinue(forceRun, token), "Stopped")
            task.wait(math.max(
                0.001,
                math.min(POLL_TICK, walkAt - tick())
            ))
        end
    end

    world3.status = "Moving to WinBlock32"
    world3.point = "WinBlock32"
    local rewardDeadline = tick() + 2.5
    local lastDistance = math.huge
    local lastProgressAt = tick()

    while tick() < rewardDeadline do
        if not world3MayContinue(forceRun, token) then
            stopRoot()
            error("Stopped")
        end

        if cashValue.Value ~= cashBefore then
            stopRoot()
            local reward = cashDelta(cashValue.Value, cashBefore)

            world3.cycles = world3.cycles + 1
            world3.earned = world3.earned + reward
            world3.lastReward = reward
            world3.lastRewardAt = tick()
            world3.status = "Stage 1 reward confirmed"
            confirmWorld3RewardHealth()

            Lib:Notify(
                "World 3 Stage 1",
                "+" .. formatNumber(reward) .. " Wins",
                2,
                "success"
            )

            if not waitForWorld3Reset(forceRun, token) then
                assert(world3MayContinue(forceRun, token), "Stopped")
                error("Spawn reset not detected")
            end

            return true
        end

        root = getRoot()

        if not root then
            error("Character unavailable")
        end

        local offset = Vector3.new(
            walkTarget.X - root.Position.X,
            0,
            walkTarget.Z - root.Position.Z
        )

        if offset.Magnitude > 0.5 then
            local liveDirection = offset.Unit
            local vertical = root.AssemblyLinearVelocity.Y

            if offset.Magnitude < lastDistance - 0.25 then
                lastDistance = offset.Magnitude
                lastProgressAt = tick()
            elseif tick() - lastProgressAt > 0.35 then
                vertical = 32
                lastProgressAt = tick()
            end

            root.AssemblyLinearVelocity = Vector3.new(
                liveDirection.X * walkSpeed,
                vertical,
                liveDirection.Z * walkSpeed
            )
        else
            stopPart(root)
        end

        task.wait(MOTION_TICK)
    end

    stopRoot()

    if world3.autoVoidRecovery then
        if world3.voidRecoveryPending then
            error("Wins still unavailable after void recovery")
        end

        if forceWorld3VoidRecovery(forceRun, token) then
            return false
        end

        error("Void recovery failed")
    end

    error("WinBlock32 reward not detected")
end

local function runWorld3Stage1Cycle(forceRun, token)
    local recoveries = 0

    while world3MayContinue(forceRun, token) do
        if runWorld3Stage1Attempt(forceRun, token) then
            return
        end

        recoveries = recoveries + 1
        world3.status = string.format(
            "Stage 1 Recovery %d",
            recoveries
        )
        world3.point = "Spawn"
        task.wait(math.min(0.5 + recoveries * 0.15, 2))
    end

    error("Stopped")
end

local function runWorld3WinBlock35Cycle(forceRun, token)
    if not waitForWorld3Spawn(forceRun, token) then
        assert(world3MayContinue(forceRun, token), "Stopped")
        error("No stable spawn found")
    end

    local cashValue = getWorld3Wins()

    assert(cashValue, "Wins value unavailable")

    local cashBefore = cashValue.Value
    local cycleStartedAt = tick()
    local route = WORLD3_ROUTE
    local minimumTime = WORLD3_STAGE5_MINIMUM_TIME
    local winPlate = WORLD3_STAGE5_WIN_PLATE
    local stageLabel = "Stage 5"

    if world3.route == "Stage 7" then
        route = WORLD3_STAGE7_ROUTE
        minimumTime = WORLD3_STAGE7_MINIMUM_TIME
        winPlate = WORLD3_STAGE7_WIN_PLATE
        stageLabel = "Stage 7"
    elseif world3.route == "Stage 6" then
        route = WORLD3_STAGE6_ROUTE
        minimumTime = WORLD3_STAGE6_MINIMUM_TIME
        winPlate = WORLD3_STAGE6_WIN_PLATE
        stageLabel = "Stage 6"
    end

    for index, point in ipairs(route) do
        world3.status = "Running route"
        world3.point = string.format(
            "%d/%d  %s",
            index,
            #route,
            point.name
        )

        local moved
        local moveError

        if point.tsunamiWindow then
            local safeWindow, windowError = waitForWorld3TsunamiWindow(
                forceRun,
                token
            )
            assert(safeWindow, windowError)
            world3.status = "Running tsunami window"
            world3.point = point.name
        end

        if point.physics then
            moved, moveError = moveWorld3Physics(
                point.position,
                forceRun,
                token,
                point.dwell
            )
        else
            for attempt = 1, 3 do
                moved, moveError = tweenWorld3(
                    point.position,
                    forceRun,
                    token,
                    point.dwell,
                    point.minimumSpeed
                        and math.max(world3.speed, point.minimumSpeed)
                        or nil
                )

                if moved or moveError ~= "Movement was corrected" then
                    break
                end

                if world3.autoVoidRecovery then
                    break
                end

                world3.status = string.format(
                    "%s: attempt %d/3",
                    point.name,
                    attempt + 1
                )
                task.wait(0.2)
            end
        end

        if not moved
            and moveError == "Movement was corrected"
            and world3.autoVoidRecovery
        then
            if world3.voidRecoveryPending then
                error("Position correction remained after void recovery")
            end

            assert(
                forceWorld3VoidRecovery(forceRun, token),
                "Void recovery failed"
            )
            return runWorld3WinBlock35Cycle(forceRun, token)
        end

        assert(moved, point.name .. ": " .. tostring(moveError))
    end

    world3.status = "Waiting for reward"
    world3.point = "Win staging"
    stopRoot()

    while tick() - cycleStartedAt < minimumTime do
        assert(world3MayContinue(forceRun, token), "Stopped")
        task.wait(POLL_TICK)
    end

    if not enterWorld3WinPlate(
        cashValue,
        cashBefore,
        forceRun,
        token,
        winPlate,
        stageLabel
    ) then
        assert(world3MayContinue(forceRun, token), "Stopped")

        if world3.autoVoidRecovery then
            if world3.voidRecoveryPending then
                error("Wins still unavailable after void recovery")
            end

            assert(
                forceWorld3VoidRecovery(forceRun, token),
                "Void recovery failed"
            )
            return runWorld3WinBlock35Cycle(forceRun, token)
        end

        error("Reward not detected")
    end

    local reward = cashDelta(cashValue.Value, cashBefore)

    world3.cycles = world3.cycles + 1
    world3.earned = world3.earned + reward
    world3.lastReward = reward
    world3.lastRewardAt = tick()
    world3.status = "Reward confirmed"
    world3.point = stageLabel
    confirmWorld3RewardHealth()

    Lib:Notify(
        "World 3 " .. stageLabel,
        "+" .. formatNumber(reward) .. " Wins",
        2,
        "success"
    )

    if not waitForWorld3Reset(forceRun, token) then
        assert(world3MayContinue(forceRun, token), "Stopped")
        error("Spawn reset not detected")
    end

end

local function runWorld3(forceRun)
    if world3.eventsActive then
        world3.auto = false
        Lib:Notify(
            "World 3",
            "Stop the event collectors first.",
            3,
            "warning"
        )
        return
    elseif game.PlaceId ~= WORLD3_PLACE_ID then
        world3.auto = false
        Lib:Notify(
            "World 3",
            "Switch to World 3 first.",
            3,
            "warning"
        )
        return
    elseif world3.running then
        Lib:Notify("World 3", "The route is already running.", 2, "info")
        return
    end

    world3.running = true
    world3.runToken = world3.runToken + 1
    local token = world3.runToken

    task.spawn(function()
        local ok, failure = pcall(function()
            repeat
                if world3.route == "Stage 1" then
                    runWorld3Stage1Cycle(forceRun, token)
                else
                    runWorld3WinBlock35Cycle(forceRun, token)
                end
            until forceRun or not world3MayContinue(false, token)
        end)

        if generation == _G.CelestialFarmGeneration
            and token == world3.runToken
        then
            stopRoot()
        end
        world3.running = false

        if ok then
            world3.status = world3.auto and "Next run" or "Ready"
            world3.point = world3.auto and "Spawn" or "Complete"
        else
            local message = cleanError(failure)
            world3.voidRecoveryPending = false

            if not string.find(message, "Stopped", 1, true) then
                world3.status = "Error: " .. message
                world3.auto = false
                Lib:Notify("World 3", message, 4, "error")
            else
                world3.status = "Stopped"
                world3.point = "-"
            end
        end
    end)
end

local function stopWorld3()
    world3.auto = false
    world3.runToken = world3.runToken + 1
    world3.voidRecoveryPending = false
    world3.status = "Stopped"
    world3.point = "-"
    stopRoot()
end

local events = {
    enabled = { summer = false, battle = false, disco = false },
    retry = { summer = 2, battle = 2, disco = 2 },
    retryAt = setmetatable({}, { __mode = "k" }),
    counts = { summer = 0, battle = 0, disco = 0, total = 0 },
    status = "Ready",
    current = "-",
    running = false,
    runToken = 0,
    homePosition = nil,
    atHome = true
}

local function anyEventEnabled()
    return events.enabled.summer
        or events.enabled.battle
        or events.enabled.disco
end

local function eventConfirmed(model, kind)
    if not model.Parent then
        return true
    end

    if kind == "disco" then
        local ok, collected = pcall(function()
            return model:GetAttribute("Collected")
        end)

        return ok and collected == true
    end

    return false
end

local function findNearestEventTarget()
    local root = getRoot()

    if not root then
        return nil
    end

    local nearest
    local nearestDistance = math.huge
    local now = tick()
    local function consider(kind, model, part, id)
        if part and part:IsA("BasePart")
            and model.Parent
            and (events.retryAt[model] or 0) <= now
        then
            local distance = (part.Position - root.Position).Magnitude

            if distance < nearestDistance then
                nearest = {
                    kind = kind,
                    model = model,
                    part = part,
                    id = id
                }
                nearestDistance = distance
            end
        end
    end

    if events.enabled.summer then
        local folder = workspace:FindFirstChild("SummerCoinsLocal")

        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") and model.Name == "SummerCoin" then
                    local coin = model:FindFirstChild("Coin", true)
                    if coin and coin:IsA("BasePart") then
                        consider("summer", model, coin)
                    end
                end
            end
        end
    end

    if events.enabled.battle then
        local folder = workspace:FindFirstChild("CoinBattleCoinsLocal")

        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") then
                    local rawId = string.match(model.Name, "^CoinBattleCoin_(.+)$")
                        or string.match(model.Name, "^Coin_(.+)$")

                    if rawId then
                        local part = model:FindFirstChild("CoinPart", true)
                            or model:FindFirstChild("Coin", true)
                            or model.PrimaryPart
                            or model:FindFirstChildWhichIsA("BasePart", true)

                        consider("battle", model, part, rawId)
                    end
                end
            end
        end
    end

    if events.enabled.disco then
        local folder = workspace:FindFirstChild("SpecialKeys")

        if folder then
            for _, object in ipairs(folder:GetChildren()) do
                local ok, isDisco = pcall(function()
                    return object:GetAttribute("IsDiscoKey")
                end)

                if ok and isDisco == true then
                    local part = object:IsA("BasePart") and object
                        or object:FindFirstChildWhichIsA("BasePart", true)

                    consider("disco", object, part)
                end
            end
        end
    end

    return nearest
end

local function returnFromEvents()
    if game.PlaceId == WORLD3_PLACE_ID then
        local moved = returnToWorld3Spawn()

        if moved then
            events.atHome = true
            events.current = "-"
        end

        return moved
    end

    local root = getRoot()

    if not root or not events.homePosition then
        return false
    end

    local moved = pcall(function()
        stopPart(root)
        root.Position = events.homePosition
        stopPart(root)
    end)

    if moved then
        events.atHome = true
        events.current = "-"
    end

    return moved
end

local function collectEventTarget(target, token)
    local root = getRoot()

    if not root or not target.part.Parent then
        return false
    end

    if not events.homePosition then
        events.homePosition = root.Position
    end

    events.atHome = false
    events.current = target.kind == "summer" and "Summer Coin"
        or target.kind == "battle" and "Coin Battle"
        or "Disco Keycap"
    events.status = "Collecting " .. events.current

    pcall(function()
        stopPart(root)
        root.Position = target.part.Position + Vector3.new(0, 3, 0)
    end)

    if target.kind == "battle" and target.id ~= nil then
        pcall(function()
            local admin = ReplicatedStorage:FindFirstChild("AdminAbuse")
            local remotes = admin and admin:FindFirstChild("Remotes")
            local remote = remotes and remotes:FindFirstChild(
                "CoinBattleCollect"
            )

            if remote and remote:IsA("RemoteEvent") then
                remote:FireServer(target.id)
            end
        end)
    end

    local deadline = tick() + 1

    while tick() < deadline
        and generation == _G.CelestialFarmGeneration
        and token == events.runToken
        and events.enabled[target.kind]
    do
        if eventConfirmed(target.model, target.kind) then
            events.counts[target.kind] = events.counts[target.kind] + 1
            events.counts.total = events.counts.total + 1
            events.retryAt[target.model] = nil
            events.status = events.current .. " confirmed"
            return true
        end

        task.wait(POLL_TICK)
    end

    if generation == _G.CelestialFarmGeneration
        and token == events.runToken
        and events.enabled[target.kind]
        and eventConfirmed(target.model, target.kind)
    then
        events.counts[target.kind] = events.counts[target.kind] + 1
        events.counts.total = events.counts.total + 1
        events.retryAt[target.model] = nil
        events.status = events.current .. " confirmed"
        return true
    end

    if target.model.Parent
        and events.enabled[target.kind]
    then
        events.retryAt[target.model] = tick() + events.retry[target.kind]
        events.status = string.format(
            "%s not confirmed, retrying in %.1fs",
            events.current,
            events.retry[target.kind]
        )
    end

    return false
end

local function runEventStep()
    if events.busy or not anyEventEnabled() then
        return
    end

    events.busy = true
    events.running = true
    local token = events.runToken
    local ok, failure = pcall(function()
        events.status = "Scanning event targets"
        local target = findNearestEventTarget()

        if target then
            collectEventTarget(target, token)
        elseif not events.atHome then
            events.status = "No targets, returning"
            returnFromEvents()
        else
            events.status = "Waiting for event targets"
        end
    end)
    events.busy = false

    if not ok and token == events.runToken then
        events.enabled.summer = false
        events.enabled.battle = false
        events.enabled.disco = false
        world3.eventsActive = false
        events.running = false
        events.status = "Error: " .. cleanError(failure)
        Lib:Notify("Events", cleanError(failure), 4, "error")
    end
end

local function setEventEnabled(kind, enabled)
    local wasActive = anyEventEnabled()
    events.enabled[kind] = enabled == true

    if enabled then
        stopWorld3()
        world3.eventsActive = true

        if not wasActive then
            events.runToken = events.runToken + 1
            events.homePosition = nil
            events.atHome = true
            events.status = "Event search started"
            events.running = true
        end
    elseif not anyEventEnabled() then
        world3.eventsActive = false
        events.runToken = events.runToken + 1
        events.running = false
        events.status = "Stopped"
        events.returnPending = true
    end
end

local function stopEvents()
    events.enabled.summer = false
    events.enabled.battle = false
    events.enabled.disco = false
    world3.eventsActive = false
    events.runToken = events.runToken + 1
    events.running = false
    events.status = "Stopped"
    returnFromEvents()
    stopRoot()
end

returnToWorld3Spawn = function()
    if game.PlaceId ~= WORLD3_PLACE_ID then
        return false
    end

    local target = world3.spawnPosition or WORLD3_ROUTE[1].position

    if not target then
        return false
    end

    for attempt = 1, 6 do
        local root = getRoot()

        world3.status = string.format(
            "World-3-Spawn TP %d/6",
            attempt
        )
        world3.point = "Recovery"

        if root then
            stopPart(root)

            if attempt % 2 == 0 then
                root.Position = target
            else
                root.CFrame = CFrame.new(target.X, target.Y, target.Z)
            end

            task.wait(0.25)
            root = getRoot()

            if root then
                local position = root.Position
                local atSpawn = (position - target).Magnitude <= 20
                    or (position.Y < -120 and position.Z < -900)

                if atSpawn then
                    stopPart(root)
                    world3.spawnPosition = position
                    world3.status = "Back at World 3 spawn"
                    world3.point = "Spawn"
                    return true
                end
            end
        end

        task.wait(0.2)
    end

    stopRoot()
    world3.status = "World 3 spawn teleport corrected"
    world3.point = "Recovery"
    return false
end

local window = Lib:CreateWindow({
    title = "CELESTIAL",
    subtitle = "",
    size = Vector2.new(500, 350),
    menuKey = "delete",
    configName = "orbit",
    configFolder = "celestial_farm",
    accentA = Color3.fromRGB(91, 145, 220),
    accentB = Color3.fromRGB(91, 145, 220),
    theme = {
        bg = Color3.fromRGB(17, 17, 17),
        sidebar = Color3.fromRGB(12, 12, 12),
        text = Color3.fromRGB(238, 238, 238),
        sub = Color3.fromRGB(170, 170, 174),
        surface = Color3.fromRGB(17, 17, 17),
        surface2 = Color3.fromRGB(24, 25, 27),
        surface3 = Color3.fromRGB(31, 33, 36),
        border = Color3.fromRGB(61, 65, 76),
        trackOff = Color3.fromRGB(71, 71, 71),
        sliderTrack = Color3.fromRGB(71, 71, 71)
    },
    font = "Pixel",
    backgroundEffect = "Off",
    opacity = 1,
    rounding = 0,
    rowLines = false,
    checkboxStyle = true,
    railOnly = false,
    skeetMode = true,
    compactSkeet = true,
    searchStyle = "off",
    lockChrome = true,
    smartFps = true,
    gameInput = true,
    autoSave = true,
    startOpen = true,
    keybindOverlay = false
})

_G.CelestialFarmUI = window
Lib:SetLayout("side")

Lib:Category("FARM")
local world3Tab = window:Tab("World 3", "target")
local world3Control = world3Tab:Section(
    "World 3 Farm",
    "Left"
)
local world3Live = world3Tab:Section(
    "Live",
    "Right"
)

local world3AutoHandle

world3AutoHandle = world3Control:Toggle(
    "Auto Farm",
    false,
    function(enabled)
        world3.auto = enabled == true

        if not world3.auto then
            stopWorld3()
        end
    end
)
world3AutoHandle:AddSettings({
    {
        type = "dropdown",
        label = "Route",
        value = "Stage 1",
        choices = { "Stage 1", "Stage 5", "Stage 6", "Stage 7" },
        legacyOptionKeys = {
            "World 3.World 3 Orbit.Auto Farm.settings.Route",
            "World 3.World 3 Orbit.Auto Farm.settings.Stage 5 Route"
        },
        legacyKey = "World 3.World 3 Orbit.Route",
        deserialize = function(value)
            if type(value) == "table" then
                return value[1]
            elseif type(value) == "boolean" then
                return value and "Stage 5" or "Stage 1"
            end

            return value
        end,
        callback = function(value)
            world3.route = value
        end
    },
    {
        type = "slider",
        label = "Speed",
        value = 300,
        min = 50,
        max = 1000,
        step = 10,
        suffix = " studs/s",
        legacyOptionKeys = {
            "World 3.World 3 Orbit.Auto Farm.settings.Geschwindigkeit"
        },
        legacyKey = "World 3.World 3 Orbit.Speed",
        callback = function(value)
            world3.speed = value
        end
    },
    {
        type = "toggle",
        label = "Void recovery",
        value = true,
        callback = function(enabled)
            world3.autoVoidRecovery = enabled == true
        end
    }
})

world3Control:Button("Run", function()
    runWorld3(true)
end):AddButton("Stop", function()
    stopWorld3()

    if world3AutoHandle:Get() then
        world3AutoHandle:Set(false)
    end
end)

world3Live:Label(function()
    return "Status: " .. world3.status
end)
world3Live:Label(function()
    return "Position: " .. world3.point
end)
world3Live:Label(function()
    return "Runs: " .. tostring(world3.cycles)
end)
world3Live:Label(function()
    return "Last Wins: " .. formatNumber(world3.lastReward)
end)
world3Live:Label(function()
    return "Void recoveries: " .. tostring(world3.voidRecoveries)
end)

local eventsTab = window:Tab("Events", "star")
local eventsControl = eventsTab:Section(
    "Event Collectors",
    "Left"
)
local eventsLive = eventsTab:Section(
    "Live",
    "Right"
)
local eventHandles = {}

eventHandles.summer = eventsControl:Toggle(
    "Summer Coins",
    false,
    function(enabled)
        setEventEnabled("summer", enabled)
    end
)
eventHandles.summer:AddSettings({
    {
        type = "slider",
        label = "Retry after",
        value = 2,
        min = 0.5,
        max = 10,
        step = 0.5,
        suffix = "s",
        callback = function(value)
            events.retry.summer = value
        end
    }
})

eventHandles.battle = eventsControl:Toggle(
    "Coin Battle",
    false,
    function(enabled)
        setEventEnabled("battle", enabled)
    end
)
eventHandles.battle:AddSettings({
    {
        type = "slider",
        label = "Retry after",
        value = 2,
        min = 0.5,
        max = 10,
        step = 0.5,
        suffix = "s",
        callback = function(value)
            events.retry.battle = value
        end
    }
})

eventHandles.disco = eventsControl:Toggle(
    "Disco Keycaps",
    false,
    function(enabled)
        setEventEnabled("disco", enabled)
    end
)
eventHandles.disco:AddSettings({
    {
        type = "slider",
        label = "Retry after",
        value = 2,
        min = 0.5,
        max = 10,
        step = 0.5,
        suffix = "s",
        callback = function(value)
            events.retry.disco = value
        end
    }
})

eventsControl:Button("Stop All", function()
    stopEvents()
end)

eventsLive:Label(function()
    return "Status: " .. events.status
end)
eventsLive:Label(function()
    return "Target: " .. events.current
end)
eventsLive:Label(function()
    return "Summer Coins: " .. tostring(events.counts.summer)
end)
eventsLive:Label(function()
    return "Coin Battle: " .. tostring(events.counts.battle)
end)
eventsLive:Label(function()
    return "Disco Keycaps: " .. tostring(events.counts.disco)
end)
eventsLive:Label(function()
    return "Total: " .. tostring(events.counts.total)
end)

local hudBox = Lib:CreateBox({
    title = "CELESTIAL HUD",
    visible = false,
    x = 18,
    y = 90,
    width = 238,
    statValueX = 92
})

hudBox:Stat(function()
    if world3.eventsActive or anyEventEnabled() then
        return "Mode | Events"
    elseif world3.running or world3.auto then
        return "Mode | World 3"
    end

    return "Mode | Idle"
end)

hudBox:Stat(function()
    local status = "Ready"

    if world3.eventsActive or anyEventEnabled() then
        status = events.status
    elseif world3.running or world3.auto then
        status = world3.status
    end

    if string.find(status, "Waiting for event", 1, true) then
        status = "Waiting"
    elseif string.find(status, "Scanning event", 1, true) then
        status = "Scanning"
    elseif string.find(status, "Collecting ", 1, true) == 1 then
        status = "Collecting"
    elseif string.find(status, "not confirmed", 1, true) then
        status = "Retrying"
    elseif string.find(status, "No targets", 1, true) then
        status = "Returning"
    elseif status == "Event search started" then
        status = "Starting"
    elseif #status > 18 then
        status = string.sub(status, 1, 15) .. "..."
    end

    return "Status | " .. status
end)

hudBox:Stat(function()
    if world3.eventsActive or anyEventEnabled() then
        return "Collected | " .. tostring(events.counts.total) .. " items"
    elseif world3.running or world3.auto then
        return "Earned | " .. formatNumber(world3.earned) .. " Wins"
    end

    return string.format(
        "Session | %s Wins / %d items",
        formatNumber(world3.earned),
        events.counts.total
    )
end)

Lib:Category("SYSTEM")
local settingsTab = window:Tab("Settings", "cog")
local hudSettings = settingsTab:Section("HUD", "Full")

hudSettings:Toggle("Activity HUD", false, function(enabled)
    hudBox:SetVisible(enabled == true)
end)

hudSettings:Label(
    "Shows live status and confirmed session earnings."
)

window:autoloadConfig("orbit")

task.spawn(function()
    while generation == _G.CelestialFarmGeneration do
        if world3AutoHandle:Get() ~= world3.auto then
            world3AutoHandle:Set(world3.auto)
        end

        for kind, handle in pairs(eventHandles) do
            if handle:Get() ~= events.enabled[kind] then
                handle:Set(events.enabled[kind])
            end
        end

        if world3.auto
            and not world3.running
            and not world3.eventsActive
        then
            runWorld3(false)
        elseif anyEventEnabled() then
            runEventStep()
        elseif events.returnPending then
            events.returnPending = false
            returnFromEvents()
        end

        task.wait(0.1)
    end
end)

Lib:Notify(
    "Celestial",
    "World 3 and event farm ready · DELETE opens the menu",
    4,
    "success"
)
