local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local WORLD3_PLACE_ID = 93411036959889
local UINT32_RANGE = 4294967296
local MOTION_TICK = 0.1
local STAGE7_HAZARD = {
    bossSpeed = 400,
    tsunamiSpeed = 300,
    tsunamiMinRemaining = 0.35,
    tsunamiMaxRemaining = 0.60,
    fallbackMinX = -1925,
    fallbackMaxX = -1875
}
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
    eventsActive = false
}

local TP_DIAGNOSTIC_PATH = "celestial_tp_flags.txt"
local lastTpCommand

local function vectorRecord(value)
    if typeof(value) ~= "Vector3" then
        return nil
    end
    return { x = value.X, y = value.Y, z = value.Z }
end

local function writeTpDiagnostic(kind, data)
    local record = {
        type = kind,
        timestamp = os.time(),
        clock = tick(),
        status = world3.status,
        point = world3.point,
        data = data or {}
    }
    local encoded
    pcall(function()
        encoded = HttpService:JSONEncode(record)
    end)
    if type(encoded) ~= "string" then
        return
    end
    if type(appendfile) == "function" then
        pcall(appendfile, TP_DIAGNOSTIC_PATH, encoded .. "\n")
    end
end

local function rememberTpCommand(target, commanded, speed)
    if not lastTpCommand then
        lastTpCommand = {}
    end

    lastTpCommand.at = tick()
    lastTpCommand.point = world3.point
    lastTpCommand.status = world3.status
    lastTpCommand.target = target
    lastTpCommand.commanded = commanded
    lastTpCommand.speed = speed
end

local function reportTpCorrection(phase, actual, expected, target, speed)
    local deviation = typeof(actual) == "Vector3"
        and typeof(expected) == "Vector3"
        and (actual - expected).Magnitude
        or -1
    writeTpDiagnostic("position_correction", {
        phase = phase,
        actual = vectorRecord(actual),
        expected = vectorRecord(expected),
        target = vectorRecord(target),
        deviation = deviation,
        speed = speed
    })
    warn(string.format(
        "[Celestial TP] correction at %s (%s), deviation %.2f",
        tostring(world3.point),
        tostring(phase),
        deviation
    ))
end

pcall(function()
    if type(writefile) == "function" then
        writefile(TP_DIAGNOSTIC_PATH, "")
    end
end)

local function watchCharacterDeath(character)
    local humanoid = character
        and character:FindFirstChildOfClass("Humanoid")
    local died = humanoid and humanoid.Died
    local connect = died and died.Connect

    if type(connect) ~= "function" then
        return
    end

    pcall(connect, died, function()
        if lastTpCommand and tick() - lastTpCommand.at <= 3 then
            writeTpDiagnostic("death_after_tp", {
                age = tick() - lastTpCommand.at,
                commandPoint = lastTpCommand.point,
                commandStatus = lastTpCommand.status,
                target = vectorRecord(lastTpCommand.target),
                commanded = vectorRecord(lastTpCommand.commanded),
                speed = lastTpCommand.speed
            })
            warn(
                "[Celestial TP] death after movement at "
                    .. tostring(lastTpCommand.point)
            )
        end
    end)
end

watchCharacterDeath(player.Character)
pcall(function()
    player.CharacterAdded:Connect(watchCharacterDeath)
end)

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
        name = "Rolling Candy Bypass Start",
        position = Vector3.new(
            -1510,
            -158.274429,
            -956.626160
        )
    },
    {
        name = "Rolling Candy Bypass End",
        position = Vector3.new(
            -1510,
            -68.3874282836914,
            -533.1188354492188
        )
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
            280,
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
        position = Vector3.new(-1400.3630, 620, 772.5512)
    },
    {
        name = "Stage 5 Curve 2",
        position = Vector3.new(-1362.1042, 620, 840.0916)
    },
    {
        name = "Stage 5 Curve 3",
        position = Vector3.new(-1303.8162, 620, 915.6722)
    },
    {
        name = "Stage 5 Curve 4",
        position = Vector3.new(-1260.5690, 620, 1030.5386)
    },
    {
        name = "Stage 5 Curve 5",
        position = Vector3.new(-1280.7828, 620, 1100.2794)
    },
    {
        name = "Stage 5 Curve 6",
        position = Vector3.new(-1337.5544, 620, 1205.0078)
    },
    {
        name = "Stage 5 Curve 7",
        position = Vector3.new(-1397.1460, 620, 1344.5568)
    },
    {
        name = "Stage 5 Boss Bypass Drop",
        position = Vector3.new(-1397.1460, 533.8660, 1344.5568)
    },
    {
        name = "WinBlock36 staging",
        position = Vector3.new(-1422.8318, 533.8660, 1335.9071)
    }
}) do
    table.insert(WORLD3_STAGE6_ROUTE, point)
end

local WORLD3_STAGE7_ROUTE = {
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
        name = "Stage 5 Lower",
        position = Vector3.new(-1404.4468, 390.5382, 724.7380)
    },
    {
        name = "Stage 5 Rise",
        position = Vector3.new(-1404.4468, 533.8660, 724.7380)
    },
    {
        name = "Stage 5 Curve 1",
        position = Vector3.new(-1400.3630, 533.8660, 772.5512),
        hazardSpeed = STAGE7_HAZARD.bossSpeed
    },
    {
        name = "Stage 5 Curve 2",
        position = Vector3.new(-1362.1042, 533.8660, 840.0916),
        hazardSpeed = STAGE7_HAZARD.bossSpeed
    },
    {
        name = "Stage 5 Curve 3",
        position = Vector3.new(-1303.8162, 533.8660, 915.6722),
        hazardSpeed = STAGE7_HAZARD.bossSpeed
    },
    {
        name = "Stage 5 Curve 4",
        position = Vector3.new(-1260.5690, 533.8660, 1030.5386),
        hazardSpeed = STAGE7_HAZARD.bossSpeed
    },
    {
        name = "Stage 5 Curve 5",
        position = Vector3.new(-1280.7828, 533.8660, 1100.2794),
        hazardSpeed = STAGE7_HAZARD.bossSpeed
    },
    {
        name = "Stage 5 Curve 6",
        position = Vector3.new(-1337.5544, 533.8660, 1205.0078),
        hazardSpeed = STAGE7_HAZARD.bossSpeed
    },
    {
        name = "Stage 5 Curve 7",
        position = Vector3.new(-1397.1460, 533.8660, 1344.5568),
        hazardSpeed = STAGE7_HAZARD.bossSpeed
    }
}

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
        dwell = 0.02,
        hazardSpeed = STAGE7_HAZARD.tsunamiSpeed
    },
    {
        name = "Stage 6 Drop 2",
        position = Vector3.new(-1433.3904, 502.0983, 1465.3796),
        dwell = 0.02,
        hazardSpeed = STAGE7_HAZARD.tsunamiSpeed
    },
    {
        name = "Stage 6 Floor",
        position = Vector3.new(-1475.4453, 443.2820, 1472.2993),
        dwell = 0.02,
        hazardSpeed = STAGE7_HAZARD.tsunamiSpeed
    },
    {
        name = "Stage 6 Run 1",
        position = Vector3.new(-1582.7493, 443.8641, 1475.2930),
        hazardPosition = Vector3.new(-1582.7493, 520, 1475.2930),
        dwell = 0.02,
        hazardSpeed = STAGE7_HAZARD.tsunamiSpeed
    },
    {
        name = "Stage 6 Run 2",
        position = Vector3.new(-1708.5725, 443.8643, 1477.6670),
        hazardPosition = Vector3.new(-1708.5725, 520, 1477.6670),
        dwell = 0.02,
        hazardSpeed = STAGE7_HAZARD.tsunamiSpeed
    },
    {
        name = "Stage 6 Run 3",
        position = Vector3.new(-1834.3958, 443.8653, 1478.9807),
        hazardPosition = Vector3.new(-1834.3958, 520, 1478.9807),
        dwell = 0.02,
        hazardSpeed = STAGE7_HAZARD.tsunamiSpeed
    },
    {
        name = "Stage 6 Run 4",
        position = Vector3.new(-1951.4202, 446.4776, 1479.5720),
        hazardPosition = Vector3.new(-1951.4202, 520, 1479.5720),
        dwell = 0.02,
        hazardSpeed = STAGE7_HAZARD.tsunamiSpeed
    },
    {
        name = "WinBlock37 safezone",
        position = Vector3.new(-2058.228516, 443.873718, 1484.287231),
        dwell = 0.25,
        hazardSpeed = STAGE7_HAZARD.tsunamiSpeed
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
    local movementSpeed = speed or world3.speed
    local duration = distance / math.max(movementSpeed, 1)
    local startedAt = tick()
    local lastCommanded = startPosition
    while tick() - startedAt < duration do
        if not world3MayContinue(forceRun, token) then
            stopPart(root)
            return false, "Stopped"
        end

        root = getRoot()

        if not root then
            return false, "Character was replaced"
        end

        local actual = root.Position
        if (actual - lastCommanded).Magnitude > 12 then
            reportTpCorrection(
                "during_tween",
                actual,
                lastCommanded,
                target,
                movementSpeed
            )
            stopPart(root)
            return false, "Movement was corrected"
        end

        local alpha = math.min((tick() - startedAt) / duration, 1)
        local position = startPosition:Lerp(target, alpha)

        stopPart(root)
        root.CFrame = CFrame.new(position.X, position.Y, position.Z)
        rememberTpCommand(target, position, movementSpeed)
        lastCommanded = position
        task.wait(MOTION_TICK)
    end

    root = getRoot()

    if not root then
        return false, "Character was replaced"
    end

    stopPart(root)
    root.CFrame = CFrame.new(target.X, target.Y, target.Z)
    rememberTpCommand(target, target, movementSpeed)
    task.wait(dwell or 0.2)

    if (root.Position - target).Magnitude > 12 then
        reportTpCorrection(
            "after_tween",
            root.Position,
            target,
            target,
            movementSpeed
        )
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

        local rootPosition = root.Position
        local velocity = root.AssemblyLinearVelocity
        local offset = Vector3.new(
            target.X - rootPosition.X,
            0,
            target.Z - rootPosition.Z
        )

        if offset.Magnitude <= 3 then
            stopPart(root)
            task.wait(dwell or 0.05)
            return true
        end

        local direction = offset.Unit
        root.AssemblyLinearVelocity = Vector3.new(
            direction.X * 100,
            velocity.Y,
            direction.Z * 100
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

        local rootPosition = root.Position
        local velocity = root.AssemblyLinearVelocity
        local offset = Vector3.new(
            target.X - rootPosition.X,
            0,
            target.Z - rootPosition.Z
        )

        if offset.Magnitude <= 1.5 then
            stopPart(root)
            reached = true
            break
        end

        local direction = offset.Unit
        root.AssemblyLinearVelocity = Vector3.new(
            direction.X * 70,
            velocity.Y,
            direction.Z * 70
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

local function isStage7TsunamiLaunchReady(tsunamiModel, tsunami)
    local spawn = tsunamiModel:FindFirstChild("TsunamiSpawn")
    local finish = tsunamiModel:FindFirstChild("TsunamiEnd")
    local travelTime = tsunamiModel:GetAttribute("TravelTime")

    if spawn
        and spawn:IsA("BasePart")
        and finish
        and finish:IsA("BasePart")
        and type(travelTime) == "number"
        and travelTime > 0
    then
        local travelDistance = (finish.Position - spawn.Position).Magnitude

        if travelDistance > 0 then
            local tsunamiSpeed = travelDistance / travelTime
            local remainingTime = (finish.Position - tsunami.Position).Magnitude
                / tsunamiSpeed

            return remainingTime >= STAGE7_HAZARD.tsunamiMinRemaining
                and remainingTime <= STAGE7_HAZARD.tsunamiMaxRemaining
        end
    end

    local tsunamiX = tsunami.Position.X
    return tsunamiX > STAGE7_HAZARD.fallbackMinX
        and tsunamiX < STAGE7_HAZARD.fallbackMaxX
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

        if isStage7TsunamiLaunchReady(tsunamiModel, tsunami) then
            return true
        end

        task.wait(0.02)
    end

    return false, "No safe tsunami window detected"
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


local function runWorld3Stage1Cycle(forceRun, token)
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

    local stage1Entry = WORLD3_ROUTE[4].position
    local reachedStage1 = false

    for attempt = 1, 3 do
        assert(world3MayContinue(forceRun, token), "Stopped")
        local root = getRoot()
        assert(root, "Character unavailable")
        stopPart(root)
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
    end

    assert(reachedStage1, "Stage 1 entrance was corrected")

    local holdPosition = winBlock.Position + Vector3.new(0, 1.5, 0)
    local holdCFrame = CFrame.new(
        holdPosition.X,
        holdPosition.Y,
        holdPosition.Z
    )
    local cashBefore = cashValue.Value
    local RunService = game:GetService("RunService")
    local root = getRoot()
    assert(root, "Character unavailable")
    stopPart(root)
    root.CFrame = holdCFrame
    stopPart(root)

    world3.status = "Holding inside WinBlock32"
    world3.point = "WinBlock32 Hold"
    local nextHoldCorrectionAt = 0

    local holdConnection = RunService.RenderStepped:Connect(function()
        if not world3MayContinue(forceRun, token) then
            return
        end

        local liveRoot = getRoot()
        local now = tick()
        if liveRoot
            and now >= nextHoldCorrectionAt
            and (liveRoot.Position - holdPosition).Magnitude > 2
        then
            nextHoldCorrectionAt = now + 0.1
            stopPart(liveRoot)
            liveRoot.CFrame = holdCFrame
            stopPart(liveRoot)
        end
    end)

    while world3MayContinue(forceRun, token) do
        if cashValue.Value ~= cashBefore then
            local reward = cashDelta(cashValue.Value, cashBefore)
            cashBefore = cashValue.Value
            world3.cycles = world3.cycles + 1
            world3.earned = world3.earned + reward
            world3.lastReward = reward
            world3.lastRewardAt = tick()
            world3.status = "Stage 1 hold reward confirmed"
            Lib:Notify(
                "World 3 Stage 1",
                "+" .. formatNumber(reward) .. " Wins",
                2,
                "success"
            )

            if forceRun then
                holdConnection:Disconnect()
                task.wait(0.2)
                stopRoot()
                returnToWorld3Spawn()
                return
            end

            world3.status = "Holding inside WinBlock32"
        end

        task.wait(0.05)
    end

    holdConnection:Disconnect()
    stopRoot()
    returnToWorld3Spawn()
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
            local targetPosition = point.hazardPosition or point.position
            local movementSpeed = point.hazardSpeed
                or (
                    point.minimumSpeed
                        and math.max(world3.speed, point.minimumSpeed)
                    or world3.speed
                )
            local retryStartedAt = tick()
            local retryRoot = getRoot()
            local nominalDuration = retryRoot
                    and (targetPosition - retryRoot.Position).Magnitude
                        / math.max(movementSpeed, 1)
                or 0
            local retryDeadline = retryStartedAt
                + math.max(12, nominalDuration * 6)
            local attempt = 0

            while true do
                attempt = attempt + 1
                moved, moveError = tweenWorld3(
                    targetPosition,
                    forceRun,
                    token,
                    point.dwell,
                    movementSpeed
                )

                if moved or moveError ~= "Movement was corrected" then
                    break
                end

                if tick() >= retryDeadline then
                    moveError = string.format(
                        "Movement remained corrected for %.1fs after %d attempts",
                        tick() - retryStartedAt,
                        attempt
                    )
                    break
                end

                world3.status = string.format(
                    "%s: retry %d",
                    point.name,
                    attempt + 1
                )
                task.wait(point.hazardSpeed and 0.05 or 0.2)
            end
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
        error("Reward not detected")
    end

    local reward = cashDelta(cashValue.Value, cashBefore)

    world3.cycles = world3.cycles + 1
    world3.earned = world3.earned + reward
    world3.lastReward = reward
    world3.lastRewardAt = tick()
    world3.status = "Reward confirmed"
    world3.point = stageLabel

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
    world3.status = "Stopped"
    world3.point = "-"
    stopRoot()
end

local events = {
    enabled = {
        summer = false,
        battle = false,
        disco = false,
        soccer = false,
        rings = false,
        masked = false,
        overdrive = false,
    },
    retry = {
        summer = 2,
        battle = 2,
        disco = 2,
        soccer = 2,
        rings = 2,
        masked = 2,
        overdrive = 2,
    },
    retryAt = {},
    maskedRetryAt = {},
    counts = {
        summer = 0,
        battle = 0,
        disco = 0,
        soccer = 0,
        rings = 0,
        masked = 0,
        overdrive = 0,
        total = 0
    },
    status = "Ready",
    current = "-",
    running = false,
    runToken = 0,
    homePosition = nil,
    atHome = true,
    tpHistory = {},
    lastTpAt = nil,
    rewardLockSignal = nil,
    summerOnlyStorm = false,
    summerStormUntil = 0,
    summerStormNoticeScanAt = 0,
    summerStormAnnouncement = nil,
    nextTargetScanAt = 0,
    minTeleportInterval = 10,
    travelRoute = {},
    teleportDistanceBudget10s = 1000,
    maxTeleportDistance = 1000,
    maskedActive = false,
    maskedMapAddress = nil,
    maskedScanAt = 0,
    maskedPadScanAt = 0,
    maskedPadLabel = nil,
    maskedPadPart = nil,
    maskedScanPending = false
}
function events.retryKey(kind, model)
    return kind
        .. ":"
        .. tostring((model and model.Address) or (model and model.Name))
end

function events.ringMultiplier(model)
    local root = model and model:FindFirstChild("Root")
    local billboard = root and root:FindFirstChild("BillboardGui")
    local top = billboard and billboard:FindFirstChild("Top")
    local label = top and top:FindFirstChild("TextLabel")
    local text = label and label.Text
    if type(text) ~= "string" then
        return 0
    end

    text = string.upper(string.gsub(text, "%s+", " "))
    if text == "WINS" then
        return 1
    end

    return tonumber(string.match(text, "^X(%d+) WINS$")) or 0
end


for _, point in ipairs(WORLD3_STAGE7_ROUTE) do
    table.insert(events.travelRoute, point)
end

for _, point in ipairs({
    {
        name = "Stage 7 Ramp 1",
        position = Vector3.new(-2130.1968, 443.0, 1486.1375)
    },
    {
        name = "Stage 7 Ramp 2",
        position = Vector3.new(-2302.0222, 443.0, 1486.1375)
    },
    {
        name = "Stage 7 Ramp 3",
        position = Vector3.new(-2441.5222, 443.0, 1486.1375)
    },
    {
        name = "Stage 8 Floor",
        position = Vector3.new(-3059.9753, 675.6495, 1503.9557)
    },
    {
        name = "Stage 9 Floor",
        position = Vector3.new(-4049.3909, 620.9781, 1483.2378)
    }
}) do
    table.insert(events.travelRoute, point)
end

local function anyEventEnabled()
    return events.enabled.summer
        or events.enabled.battle
        or events.enabled.disco
        or events.enabled.soccer
        or events.enabled.rings
        or events.enabled.masked
        or events.enabled.overdrive
end

local function recordEventTeleport(kind, origin, destination)
    local now = tick()
    local history = events.tpHistory

    while history[1] and now - history[1].at > 10 do
        table.remove(history, 1)
    end

    local distance = (destination - origin).Magnitude
    local interval = events.lastTpAt and now - events.lastTpAt or nil
    local entry = { at = now, distance = distance }
    table.insert(history, entry)
    events.lastTpAt = now

    local count1 = 0
    local count3 = 0
    local distance10 = 0
    for _, item in ipairs(history) do
        local age = now - item.at
        if age <= 1 then
            count1 = count1 + 1
        end
        if age <= 3 then
            count3 = count3 + 1
        end
        distance10 = distance10 + item.distance
    end

    local snapshot = {
        kind = kind,
        origin = vectorRecord(origin),
        destination = vectorRecord(destination),
        distance = distance,
        interval = interval,
        count1s = count1,
        count3s = count3,
        count10s = #history,
        distance10s = distance10
    }
    writeTpDiagnostic("event_teleport", snapshot)
    rememberTpCommand(destination, destination, nil)
    return snapshot
end

local function stopEventsForRewardRisk(message)
    events.enabled.summer = false
    events.enabled.battle = false
    events.enabled.disco = false
    events.enabled.soccer = false
    events.enabled.rings = false
    events.enabled.masked = false
    events.enabled.overdrive = false
    events.runToken = events.runToken + 1
    events.running = false
    events.status = message
    world3.eventsActive = false
    stopRoot()
    Lib:Notify("TP Safety", message, 5, "warning")
end

local function detectEventRubberband(origin, destination, snapshot)
    for _ = 1, 6 do
        task.wait(0.05)
        local root = getRoot()
        if not root then
            return false
        end

        local actual = root.Position
        local targetDistance = (actual - destination).Magnitude
        local originDistance = (actual - origin).Magnitude
        if targetDistance > 30 and originDistance < targetDistance then
            snapshot.actual = vectorRecord(actual)
            snapshot.targetDistance = targetDistance
            snapshot.originDistance = originDistance
            writeTpDiagnostic("event_rubberband", snapshot)
            warn(string.format(
                "[Celestial TP] event rubberband: %d TP/1s, %d TP/3s",
                snapshot.count1s,
                snapshot.count3s
            ))
            stopEventsForRewardRisk(
                "Rubberband detected; collectors stopped to protect WinPlates."
            )
            return true
        end
    end

    return false
end

local function moveEventSafely(
    kind,
    origin,
    destination,
    token,
    allowStopped,
    targetPart,
    targetOffset
)
    local offset = targetOffset or Vector3.new(0, 0, 0)
    local distance

    while true do
        if generation ~= _G.CelestialFarmGeneration
            or token ~= events.runToken
            or (not allowStopped and not events.enabled[kind])
            or (targetPart and not targetPart.Parent)
        then
            return false
        end
        if targetPart then
            destination = targetPart.Position + offset
        end

        distance = (destination - origin).Magnitude
        if distance > events.maxTeleportDistance then
            return false
        end


        local now = tick()
        local history = events.tpHistory
        while history[1] and now - history[1].at > 10 do
            table.remove(history, 1)
        end

        local distance10 = 0
        for _, entry in ipairs(history) do
            distance10 = distance10 + entry.distance
        end

        local intervalReady = not events.lastTpAt
            or now - events.lastTpAt >= events.minTeleportInterval
        local budgetReady = distance10 + distance
            <= events.teleportDistanceBudget10s

        if intervalReady and budgetReady then
            break
        elseif kind == "masked" and targetPart then
            events.status = "Waiting for direct TP safety window"
            return false
        end

        events.status = "Waiting for direct TP safety window"
        task.wait(0.1)
    end

    local root = getRoot()
    if not root then
        return false
    end

    local snapshot = recordEventTeleport(kind, origin, destination)
    stopPart(root)
    root.Position = destination
    stopPart(root)

    return not detectEventRubberband(origin, destination, snapshot)
end

local function waitForEventTsunamiWindow(kind, token, allowStopped)
    local deadline = tick() + 8

    while tick() < deadline do
        if generation ~= _G.CelestialFarmGeneration
            or token ~= events.runToken
            or (not allowStopped and not events.enabled[kind])
        then
            return false
        end

        local hazards = workspace:FindFirstChild("NPC & Piege")
        local tsunamiModel = hazards and hazards:FindFirstChild("Tsunami1")
        local tsunami = tsunamiModel and tsunamiModel:FindFirstChild("Tsunami")

        if tsunami
            and tsunami:IsA("BasePart")
            and isStage7TsunamiLaunchReady(tsunamiModel, tsunami)
        then
            return true
        end

        task.wait(0.02)
    end

    return false
end

local function moveEventRoutePoint(kind, point, token, allowStopped)
    local root = getRoot()
    if not root then
        return false
    end

    local startPosition = root.Position
    local target = point.hazardPosition or point.position
    local distance = (target - startPosition).Magnitude
    local movementSpeed = point.hazardSpeed
        or (
            point.minimumSpeed
                and math.max(world3.speed, point.minimumSpeed)
            or world3.speed
        )
    local duration = distance / math.max(movementSpeed, 1)
    local startedAt = tick()
    local lastCommanded = startPosition

    while tick() - startedAt < duration do
        if generation ~= _G.CelestialFarmGeneration
            or token ~= events.runToken
            or (not allowStopped and not events.enabled[kind])
        then
            stopPart(root)
            return false
        end

        root = getRoot()
        if not root then
            return false
        end

        local actual = root.Position
        if (actual - lastCommanded).Magnitude > 12 then
            writeTpDiagnostic("position_correction", {
                kind = kind,
                phase = "event_route",
                actual = vectorRecord(actual),
                commanded = vectorRecord(lastCommanded),
                target = vectorRecord(target),
                speed = movementSpeed
            })
            stopPart(root)
            stopEventsForRewardRisk(
                "Route correction detected; collectors stopped"
            )
            return false
        end

        local alpha = math.min((tick() - startedAt) / duration, 1)
        local position = startPosition:Lerp(target, alpha)
        stopPart(root)
        root.CFrame = CFrame.new(position.X, position.Y, position.Z)
        lastCommanded = position
        task.wait(MOTION_TICK)
    end

    root = getRoot()
    if not root then
        return false
    end

    stopPart(root)
    root.CFrame = CFrame.new(target.X, target.Y, target.Z)
    task.wait(point.dwell or 0.2)

    if (root.Position - target).Magnitude > 12 then
        writeTpDiagnostic("position_correction", {
            kind = kind,
            phase = "event_route_final",
            actual = vectorRecord(root.Position),
            commanded = vectorRecord(target),
            target = vectorRecord(target),
            speed = movementSpeed
        })
        stopEventsForRewardRisk(
            "Route correction detected; collectors stopped"
        )
        return false
    end

    return true
end

local function stageEventTravel(kind, destination, token, allowStopped)
    local root = getRoot()
    if not root then
        return false
    end

    local origin = root.Position
    local route = events.travelRoute
    local currentIndex = 1
    local targetIndex = 1
    local currentDistance = math.huge
    local targetDistance = math.huge

    for index, point in ipairs(route) do
        local fromCurrent = (point.position - origin).Magnitude
        local fromTarget = (point.position - destination).Magnitude

        if fromCurrent < currentDistance then
            currentDistance = fromCurrent
            currentIndex = index
        end
        if fromTarget < targetDistance then
            targetDistance = fromTarget
            targetIndex = index
        end
    end

    local nextIndex
    if targetIndex > currentIndex then
        nextIndex = currentIndex + 1
    elseif targetIndex < currentIndex then
        nextIndex = currentIndex - 1
    elseif destination.X < origin.X and currentIndex < #route then
        nextIndex = currentIndex + 1
    elseif currentIndex > 1 then
        nextIndex = currentIndex - 1
    else
        return false
    end

    local point = route[nextIndex]
    if not point
        or (point.position - origin).Magnitude > events.maxTeleportDistance
    then
        return false
    end

    if point.tsunamiWindow
        and not waitForEventTsunamiWindow(
            kind,
            token,
            allowStopped == true
        )
    then
        events.status = "Waiting for safe tsunami route"
        return false
    end

    events.atHome = false
    events.current = point.name
    events.status = "Traveling across map"
    writeTpDiagnostic("event_route_stage", {
        kind = kind,
        routeIndex = nextIndex,
        routePoint = point.name,
        destination = vectorRecord(destination)
    })

    return moveEventRoutePoint(
        kind,
        point,
        token,
        allowStopped == true
    )
end


local function summerCoinCount()
    local folder = workspace:FindFirstChild("SummerCoinsLocal")
    local count = 0

    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model")
                and model.Name == "SummerCoin"
                and model:FindFirstChild("Coin", true)
            then
                count = count + 1
            end
        end
    end

    return count
end

local function monitorSummerStormNotice()
    local now = tick()
    if now < events.summerStormNoticeScanAt then
        return
    end

    events.summerStormNoticeScanAt = now + 1

    local playerGui = player:FindFirstChild("PlayerGui")
    local announcement

    if playerGui then
        for _, item in ipairs(playerGui:GetDescendants()) do
            if item:IsA("TextLabel")
                and item.Name == "CenterMessage"
                and type(item.Text) == "string"
            then
                local text = string.lower(item.Text)
                if string.find(text, "coin", 1, true)
                    and string.find(text, "storm", 1, true)
                then
                    announcement = item.Text
                    if string.find(text, "stop", 1, true)
                        or string.find(text, "end", 1, true)
                        or string.find(text, "over", 1, true)
                        or string.find(text, "finish", 1, true)
                    then
                        events.summerStormUntil = 0
                    else
                        events.summerStormUntil = now + 90
                    end
                    break
                end
            end
        end
    end

    if announcement ~= events.summerStormAnnouncement then
        events.summerStormAnnouncement = announcement
        if announcement then
            writeTpDiagnostic("summer_storm_notice", {
                active = now < events.summerStormUntil,
                announcement = announcement
            })
        end
    end
end

local function summerStormActive()
    monitorSummerStormNotice()
    return tick() < events.summerStormUntil, summerCoinCount()
end

local function isEventBasePart(value)
    local className = value and value.ClassName
    return className == "Part"
        or className == "MeshPart"
        or className == "UnionOperation"
        or className == "WedgePart"
        or className == "CornerWedgePart"
        or className == "TrussPart"
        or className == "Seat"
        or className == "VehicleSeat"
end

local MASKED_SUFFIX_MULTIPLIERS = {
    K = 1e3,
    M = 1e6,
    B = 1e9,
    T = 1e12,
    QA = 1e15,
    QI = 1e18,
    SX = 1e21,
    SP = 1e24,
    OC = 1e27,
    NO = 1e30,
    DC = 1e33,
    UD = 1e36,
    DD = 1e39,
    TD = 1e42,
    QAD = 1e45,
    QID = 1e48,
    SXD = 1e51,
    SPD = 1e54,
    OD = 1e57,
    ND = 1e60,
    VG = 1e63
}

local function maskedPayoutFromText(text)
    if type(text) ~= "string" then
        return 0
    end

    local compact = string.upper(string.gsub(text, "%s+", ""))
    local amount, suffix = string.match(
        compact,
        "^([%d%.]+)([%a]*)WINS$"
    )
    amount = tonumber(amount)
    if not amount then
        return 0
    end

    if suffix == "" then
        return amount
    end

    local multiplier = MASKED_SUFFIX_MULTIPLIERS[suffix]
    return multiplier and amount * multiplier or 0
end

local function findMaskedWinPad(primaryRoot, presentationRoot)
    for rootIndex = 1, 2 do
        local root = rootIndex == 1 and primaryRoot or presentationRoot
        if root then
            for _, item in ipairs(root:GetDescendants()) do
                if item.ClassName == "TextLabel" then
                    local payout = maskedPayoutFromText(item.Text)
                    if payout > 0 then
                        local gui = item.Parent
                        while gui
                            and gui ~= root
                            and gui.ClassName ~= "BillboardGui"
                            and gui.ClassName ~= "SurfaceGui"
                        do
                            gui = gui.Parent
                        end

                        local ancestor = (
                            gui
                            and (gui.ClassName == "BillboardGui"
                                or gui.ClassName == "SurfaceGui")
                        ) and gui.Parent or item.Parent
                        while ancestor and ancestor ~= root.Parent do
                            if isEventBasePart(ancestor) then
                                return item, ancestor
                            end
                            ancestor = ancestor.Parent
                        end
                    end
                end
            end
        end
    end

    return nil, nil
end


local function eventConfirmed(model, kind, target)
    if kind == "masked"
        and target
        and target.id
        and target.id.type == "pad"
    then
        local cashValue = getWorld3Wins()
        local wins = cashValue and cashValue.Value
        return wins ~= nil
            and target.winsBefore ~= nil
            and wins ~= target.winsBefore
    end

    if kind == "overdrive" then
        local cashValue = getWorld3Wins()
        local wins = cashValue and cashValue.Value
        return wins ~= nil
            and target
            and target.winsBefore ~= nil
            and wins ~= target.winsBefore
    end

    if kind == "rings" then
        local cashValue = getWorld3Wins()
        local wins = cashValue and cashValue.Value
        return wins ~= nil
            and target
            and target.winsBefore ~= nil
            and wins ~= target.winsBefore
    end

    if kind == "soccer" then
        if not model.Parent then
            return true
        end

        local part = target and target.part
        local ok, transparency = pcall(function()
            return part and part.Transparency
        end)
        return ok and transparency ~= nil and transparency >= 1
    end

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

    local rootPosition = root.Position
    local nearestKind
    local nearestModel
    local nearestPart
    local nearestId
    local nearestRetryKey
    local nearestDistance = math.huge
    local now = tick()
    events.maskedScanPending = false
    local summerStormIsActive
    local function consider(kind, model, part, id)
        local retryKey = kind ~= "masked"
                and events.retryKey(kind, model)
            or nil
        local retryAt = kind == "masked"
                and id
                and events.maskedRetryAt[id.key]
            or (retryKey and events.retryAt[retryKey])

        if retryKey and retryAt and retryAt <= now then
            events.retryAt[retryKey] = nil
        end

        if isEventBasePart(part)
            and model.Parent
            and (retryAt or 0) <= now
        then
            local distance = (part.Position - rootPosition).Magnitude

            if distance < nearestDistance then
                nearestKind = kind
                nearestModel = model
                nearestPart = part
                nearestId = id
                nearestRetryKey = retryKey
                nearestDistance = distance
            end
        end
    end

    if events.enabled.summer then
        local folder = workspace:FindFirstChild("SummerCoinsLocal")

        if events.summerOnlyStorm then
            local scanned = 0
            local visible = 0
            local summerModel
            local summerPart
            local summerDistance = math.huge

            if folder then
                for _, model in ipairs(folder:GetChildren()) do
                    if model:IsA("Model") and model.Name == "SummerCoin" then
                        scanned = scanned + 1
                        local coin = model:FindFirstChild("Coin", true)
                        if coin then
                            visible = visible + 1
                            if coin:IsA("BasePart")
                                and model.Parent
                                and (
                                    events.retryAt[
                                        events.retryKey("summer", model)
                                    ] or 0
                                ) <= now
                            then
                                local distance = (
                                    coin.Position - rootPosition
                                ).Magnitude
                                if distance < summerDistance then
                                    summerModel = model
                                    summerPart = coin
                                    summerDistance = distance
                                end
                            end
                        end
                        if scanned >= 64 then
                            break
                        end
                    end
                end
            end

            monitorSummerStormNotice()
            if visible >= 10 then
                events.summerStormUntil = math.max(
                    events.summerStormUntil,
                    tick() + 5
                )
            end

            summerStormIsActive = tick() < events.summerStormUntil

            if summerStormIsActive and summerModel then
                consider("summer", summerModel, summerPart)
            end
        elseif folder then
            local scanned = 0
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") and model.Name == "SummerCoin" then
                    scanned = scanned + 1
                    local coin = model:FindFirstChild("Coin", true)
                    if coin and coin:IsA("BasePart") then
                        consider("summer", model, coin)
                    end
                    if scanned >= 64 then
                        break
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

    if events.enabled.soccer then
        for _, object in ipairs(workspace:GetChildren()) do
            if object.Name == "SoccerBall" and isEventBasePart(object) then
                consider("soccer", object, object)
            end
        end
    end

    if events.enabled.overdrive then
        for _, object in ipairs(workspace:GetChildren()) do
            if object.Name == "TixCollectibleOrb"
                and object.ClassName == "Model"
            then
                local part = object.PrimaryPart
                    or object:FindFirstChild("CollectibleOrb")

                consider("overdrive", object, part)
            end
        end
    end

    if events.enabled.rings then
        local bestModel
        local bestPart
        local bestMultiplier = 0
        local bestRadius = 0
        local bestDistance = math.huge

        for _, object in ipairs(workspace:GetChildren()) do
            if object.Name == "WinRing"
                and object.ClassName == "Model"
            then
                local part = object:FindFirstChild("Root")
                    or object:FindFirstChild("Cylinder")
                local multiplier = events.ringMultiplier(object)
                local retryKey = events.retryKey("rings", object)
                local retryAt = events.retryAt[retryKey]

                if retryAt and retryAt <= now then
                    events.retryAt[retryKey] = nil
                    retryAt = nil
                end

                if multiplier > 0
                    and isEventBasePart(part)
                    and (retryAt or 0) <= now
                then
                    local distance = (part.Position - rootPosition).Magnitude
                    if multiplier > bestMultiplier
                        or (
                            multiplier == bestMultiplier
                            and distance < bestDistance
                        )
                    then
                        local cylinder = object:FindFirstChild("Cylinder")
                        bestModel = object
                        bestPart = part
                        bestMultiplier = multiplier
                        bestRadius = isEventBasePart(cylinder)
                                and math.max(
                                    cylinder.Size.X,
                                    cylinder.Size.Z
                                ) / 2
                            or 10
                        bestDistance = distance
                    end
                end
            end
        end

        if bestModel then
            consider("rings", bestModel, bestPart, {
                type = "ring",
                key = tostring(bestModel.Address),
                multiplier = bestMultiplier,
                radius = bestRadius
            })
        end
    end

    if events.enabled.masked then
        local adminAbuse = workspace:FindFirstChild("AdminAbuse")
        local mapFolder = adminAbuse and adminAbuse:FindFirstChild("Map")
        local liveMap = mapFolder
            and mapFolder:FindFirstChild("MaskedManColorMania_Live")
        local mapAddress = liveMap and liveMap.Address or nil

        if mapAddress ~= events.maskedMapAddress then
            events.maskedMapAddress = mapAddress
            events.maskedRetryAt = {}
            events.maskedPadLabel = nil
            events.maskedPadPart = nil
            events.maskedScanAt = 0
            events.maskedPadScanAt = 0
        end

        events.maskedActive = liveMap ~= nil
        if liveMap and now >= events.maskedScanAt then
            events.maskedScanAt = now + 0.25

            local maps = workspace:FindFirstChild("AdminAbuseMaps")
            local presentation = maps
                and maps:FindFirstChild("MaskedManColorMania")
            local debris = presentation
                and presentation:FindFirstChild("Debris")

            if debris then
                for _, object in ipairs(debris:GetChildren()) do
                    if (object.Name == "CollectibleOrb"
                            or object.Name == "BigCollectibleOrb")
                        and isEventBasePart(object)
                    then
                        consider("masked", object, object, {
                            type = "orb",
                            key = tostring(object.Address)
                        })
                    end
                end
            else
                for _, orbName in ipairs({
                    "CollectibleOrb",
                    "BigCollectibleOrb"
                }) do
                    local object = workspace:FindFirstChild(orbName)
                    if isEventBasePart(object) then
                        consider("masked", object, object, {
                            type = "orb",
                            key = tostring(object.Address)
                        })
                    end
                end
            end

            local label = events.maskedPadLabel
            local pad = events.maskedPadPart
            if not label
                or not label.Parent
                or not pad
                or not pad.Parent
                or not isEventBasePart(pad)
            then
                events.maskedPadLabel = nil
                events.maskedPadPart = nil
                label = nil
                pad = nil
            end

            if not label and now >= events.maskedPadScanAt then
                events.maskedPadScanAt = now + 2
                label, pad = findMaskedWinPad(liveMap, presentation)
                events.maskedPadLabel = label
                events.maskedPadPart = pad
            end

            if label
                and pad
                and maskedPayoutFromText(label.Text) > 0
            then
                consider("masked", pad, pad, {
                    type = "pad",
                    key = tostring(pad.Address)
                })
            end
        elseif liveMap then
            events.maskedScanPending = true
        end
    else
        events.maskedActive = false
    end

    if not nearestModel then
        return nil, summerStormIsActive
    end

    return {
        kind = nearestKind,
        model = nearestModel,
        part = nearestPart,
        id = nearestId,
        retryKey = nearestRetryKey
    }, summerStormIsActive
end

local function returnFromEvents(token, allowStopped)
    local root = getRoot()

    if not root or not events.homePosition then
        return false
    end

    events.status = "Waiting to return safely"
    local origin = root.Position
    local destination = events.homePosition
    local kind = events.travelKind or "summer"
    local travelDistance = (destination - origin).Magnitude
    local staged = travelDistance > events.maxTeleportDistance
    local moved

    if staged then
        moved = stageEventTravel(
            kind,
            destination,
            token or events.runToken,
            allowStopped == true
        )
    else
        moved = moveEventSafely(
            kind,
            origin,
            destination,
            token or events.runToken,
            allowStopped == true
        )
    end

    if moved and not staged then
        events.atHome = true
        events.current = "-"
        events.travelKind = nil
    elseif moved and staged and allowStopped == true then
        events.returnPending = true
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

    events.current = target.kind == "summer" and "Summer Coin"
        or target.kind == "battle" and "Coin Battle"
        or target.kind == "disco" and "Disco Keycap"
        or target.kind == "soccer" and "World Cup Soccer Ball"
        or target.kind == "overdrive" and "Overdrive Tix Orb"
        or target.kind == "rings"
            and string.format(
                "Summer Boss x%d Win Ring",
                target.id.multiplier
            )
        or target.id and target.id.type == "pad"
            and "Masked Man Win Pad"
        or "Masked Man Orb"
    local origin = root.Position
    local targetOffset = target.kind == "masked"
            and Vector3.new(0, 1.5, 0)
        or target.kind == "overdrive" and Vector3.zero
        or Vector3.new(0, 3, 0)
    local destination = target.part.Position + targetOffset
    local travelDistance = (destination - origin).Magnitude

    if travelDistance > events.maxTeleportDistance then
        events.atHome = false
        events.travelKind = target.kind
        events.status = string.format(
            "Routing to distant %s (%.0f studs)",
            events.current,
            travelDistance
        )
        writeTpDiagnostic("event_route_requested", {
            kind = target.kind,
            distance = travelDistance,
            destination = vectorRecord(destination)
        })
        return stageEventTravel(
            target.kind,
            destination,
            token,
            false
        )
    end

    events.atHome = false
    events.travelKind = target.kind
    events.status = "Collecting " .. events.current
    if target.kind == "rings"
        or target.kind == "overdrive"
        or (
            target.kind == "masked"
            and target.id
            and target.id.type == "pad"
        )
    then
        local cashValue = getWorld3Wins()
        target.winsBefore = cashValue and cashValue.Value
    end

    local moved
    if target.kind == "overdrive" then
        moved = true
    elseif target.kind == "rings" then
        local delta = target.part.Position - root.Position
        local horizontalDistance = Vector3.new(
            delta.X,
            0,
            delta.Z
        ).Magnitude
        moved = horizontalDistance
            <= math.max(target.id.radius * 0.8, 4)
    end

    if not moved then
        moved = moveEventSafely(
            target.kind,
            origin,
            destination,
            token,
            false,
            target.part,
            targetOffset
        )
    end

    if not moved then
        return false
    end

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


    local deadline = tick()
        + (
            target.kind == "rings" and 12
            or target.kind == "overdrive"
                and math.min(
                    math.max(travelDistance / 12 + 4, 8),
                    55
                )
            or target.kind == "soccer" and 3
            or 1
        )

    while tick() < deadline
        and generation == _G.CelestialFarmGeneration
        and token == events.runToken
        and events.enabled[target.kind]
    do
        if eventConfirmed(target.model, target.kind, target) then
            events.counts[target.kind] = events.counts[target.kind] + 1
            events.counts.total = events.counts.total + 1
            if target.retryKey then
                events.retryAt[target.retryKey] = nil
            end
            if target.kind == "masked" and target.id then
                events.maskedRetryAt[target.id.key] = nil
            end
            events.status = events.current
                .. (target.kind == "masked"
                        and target.id
                        and target.id.type == "orb"
                        and " touched"
                    or " confirmed")
            events.maskedScanAt = 0
            if target.kind == "rings"
                or target.kind == "overdrive"
            then
                stopRoot()
            end
            return true
        end

        if target.kind == "rings"
            and tick() >= (target.nextChaseAt or 0)
        then
            target.nextChaseAt = tick() + 0.2
            root = getRoot()
            local part = target.part
            if root and part and part.Parent then
                local delta = part.Position - root.Position
                local horizontal = Vector3.new(delta.X, 0, delta.Z)
                local velocity = root.AssemblyLinearVelocity
                local desiredX = 0
                local desiredZ = 0
                if horizontal.Magnitude
                    > math.max(target.id.radius * 0.45, 4)
                then
                    local speed = math.min(
                        math.max(horizontal.Magnitude * 2, 20),
                        70
                    )
                    local direction = horizontal.Unit
                    desiredX = direction.X * speed
                    desiredZ = direction.Z * speed
                end

                local velocityDelta = Vector3.new(
                    velocity.X - desiredX,
                    0,
                    velocity.Z - desiredZ
                ).Magnitude
                if velocityDelta > 5 then
                    root.AssemblyLinearVelocity = Vector3.new(
                        desiredX,
                        velocity.Y,
                        desiredZ
                    )
                end
            end
        end

        if target.kind == "overdrive"
            and tick() >= (target.nextMoveAt or 0)
        then
            target.nextMoveAt = tick() + 0.2
            root = getRoot()
            local part = target.part
            if root and part and part.Parent then
                local delta = part.Position - root.Position
                local horizontal = Vector3.new(delta.X, 0, delta.Z)
                if horizontal.Magnitude > 2 then
                    local step = math.min(horizontal.Magnitude, 3.2)
                    local nextPosition = root.Position
                        + horizontal.Unit * step
                    root.CFrame = CFrame.lookAt(
                        nextPosition,
                        nextPosition + root.CFrame.LookVector
                    )
                end
            end
        end

        task.wait(POLL_TICK)
    end

    if generation == _G.CelestialFarmGeneration
        and token == events.runToken
        and events.enabled[target.kind]
        and eventConfirmed(target.model, target.kind, target)
    then
        events.counts[target.kind] = events.counts[target.kind] + 1
        events.counts.total = events.counts.total + 1
        if target.retryKey then
            events.retryAt[target.retryKey] = nil
        end
        if target.kind == "masked" and target.id then
            events.maskedRetryAt[target.id.key] = nil
        end
        events.status = events.current
            .. (target.kind == "masked"
                    and target.id
                    and target.id.type == "orb"
                    and " touched"
                or " confirmed")
        events.maskedScanAt = 0
        if target.kind == "rings"
            or target.kind == "overdrive"
        then
            stopRoot()
        end
        return true
    end

    if target.kind == "rings" then
        stopRoot()
    end

    if target.kind == "overdrive" then
        stopRoot()
        if not target.model.Parent then
            events.status = "Overdrive Tix reward not confirmed"
        end
    end

    if target.model.Parent
        and events.enabled[target.kind]
    then
        local retryAt = tick() + events.retry[target.kind]
        if target.kind == "masked" and target.id then
            events.maskedRetryAt[target.id.key] = retryAt
            events.maskedScanAt = 0
        else
            events.retryAt[target.retryKey] = retryAt
        end
        events.status = string.format(
            "%s not confirmed, retrying in %.1fs",
            events.current,
            events.retry[target.kind]
        )
    end

    return false
end

local function runEventStep()
    local now = tick()
    if now < events.nextTargetScanAt then
        return
    end
    events.nextTargetScanAt = now + 0.25

    if events.busy or not anyEventEnabled() then
        return
    end

    events.busy = true
    events.running = true
    local token = events.runToken
    local ok, failure = pcall(function()
        events.status = "Scanning event targets"
        local target, summerStormIsActive = findNearestEventTarget()

        if target then
            collectEventTarget(target, token)
        elseif events.maskedScanPending then
            events.status = "Scanning Masked Man targets"
        elseif not events.atHome then
            events.status = "No targets, returning"
            returnFromEvents()
        elseif events.enabled.summer
            and events.summerOnlyStorm
            and not events.enabled.battle
            and not events.enabled.disco
            and not events.enabled.rings
            and not events.enabled.masked
            and not events.enabled.soccer
            and not events.enabled.overdrive
        then
            if summerStormIsActive == nil then
                summerStormIsActive = summerStormActive()
            end
            events.status = summerStormIsActive
                and "Waiting for event targets"
                or "Waiting for Coin Storm"
        elseif events.enabled.rings then
            events.status = "Waiting for Summer Boss Win Rings"
        elseif events.enabled.masked and not events.maskedActive then
            events.status = "Waiting for Masked Man event"
        elseif events.enabled.masked then
            events.status = "Waiting for Masked Man targets"
        else
            events.status = "Waiting for event targets"
        end
    end)
    events.busy = false

    if not ok and token == events.runToken then
        events.enabled.summer = false
        events.enabled.battle = false
        events.enabled.disco = false
        events.enabled.soccer = false
        events.enabled.rings = false
        events.enabled.masked = false
        events.enabled.overdrive = false
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
        events.nextTargetScanAt = 0
    end

    if enabled then
        stopWorld3()
        world3.eventsActive = true

        if not wasActive then
            events.runToken = events.runToken + 1
            events.homePosition = nil
            events.atHome = true
            events.tpHistory = {}
            events.lastTpAt = nil
            events.rewardLockSignal = nil
            events.retryAt = {}
            events.maskedRetryAt = {}
            events.maskedScanAt = 0
            events.maskedPadScanAt = 0
            events.status = "Event search started"
            events.running = true
            writeTpDiagnostic("event_session_started", { kind = kind })
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
    events.enabled.soccer = false
    events.enabled.rings = false
    events.enabled.masked = false
    events.enabled.overdrive = false
    world3.eventsActive = false
    events.runToken = events.runToken + 1
    events.running = false
    events.status = "Stopped"
    events.returnPending = true
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
        world3.point = "Return"

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
    world3.point = "Return"
    return false
end

local window = Lib:CreateWindow({
    title = "CELESTIAL",
    subtitle = "WORLD 3",
    size = Vector2.new(620, 420),
    menuKey = "delete",
    configName = "orbit",
    configFolder = "celestial_farm",
    accentA = Color3.fromRGB(112, 114, 255),
    accentB = Color3.fromRGB(86, 192, 255),
    theme = {
        bg = Color3.fromRGB(10, 12, 18),
        sidebar = Color3.fromRGB(13, 15, 23),
        text = Color3.fromRGB(236, 239, 247),
        sub = Color3.fromRGB(143, 151, 174),
        surface = Color3.fromRGB(14, 17, 25),
        surface2 = Color3.fromRGB(18, 22, 32),
        surface3 = Color3.fromRGB(24, 29, 42),
        border = Color3.fromRGB(43, 51, 71),
        trackOff = Color3.fromRGB(46, 53, 70),
        sliderTrack = Color3.fromRGB(38, 45, 62)
    },
    font = "Default",
    backgroundEffect = "Off",
    opacity = 0.99,
    rounding = 0.9,
    rowLines = false,
    checkboxStyle = false,
    railOnly = false,
    skeetMode = false,
    compactSkeet = false,
    neverloseMode = true,
    searchStyle = "icon",
    lockChrome = true,
    smartFps = true,
    gameInput = true,
    autoSave = true,
    startOpen = true,
    keybindOverlay = false
})
Lib:SetPerformance(false)
_G.CelestialFarmUI = window

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
        choices = {
            "Stage 1",
            "Stage 5",
            "Stage 6",
            "Stage 7"
        },
        legacyOptionKeys = {
            "World 3.World 3 Orbit.Auto Farm.settings.Route",
            "World 3.World 3 Orbit.Auto Farm.settings.Stage 5 Route"
        },
        legacyKey = "World 3.World 3 Orbit.Route",
        deserialize = function(value)
            if type(value) == "table" then
                value = value[1]
            elseif type(value) == "boolean" then
                value = value and "Stage 5" or "Stage 1"
            end

            if value == "Stage 1 Hold" then
                return "Stage 1"
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
        visibleWhen = function()
            return world3.route == "Stage 5"
                or world3.route == "Stage 6"
                or world3.route == "Stage 7"
        end,
        legacyOptionKeys = {
            "World 3.World 3 Orbit.Auto Farm.settings.Geschwindigkeit"
        },
        legacyKey = "World 3.World 3 Orbit.Speed",
        callback = function(value)
            world3.speed = value
        end
    },
})

world3Control:Button("Run", function()
    runWorld3(true)
end):SetStyle("primary"):AddButton("Stop", function()
    stopWorld3()

    if world3AutoHandle:Get() then
        world3AutoHandle:Set(false)
    end
end, "danger")

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
        type = "toggle",
        label = "Only during Coin Storm",
        value = false,
        callback = function(value)
            events.summerOnlyStorm = value == true
            if events.summerOnlyStorm then
                local active = summerStormActive()
                events.status = active
                    and "Coin Storm active"
                    or "Waiting for Coin Storm"
            end
        end
    },
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

eventHandles.soccer = eventsControl:Toggle(
    "World Cup Soccer Balls",
    false,
    function(enabled)
        setEventEnabled("soccer", enabled)
    end
)
eventHandles.soccer:AddSettings({
    {
        type = "slider",
        label = "Retry after",
        value = 2,
        min = 0.5,
        max = 10,
        step = 0.5,
        suffix = "s",
        callback = function(value)
            events.retry.soccer = value
        end
    }
})

eventHandles.rings = eventsControl:Toggle(
    "Summer Boss Win Rings",
    false,
    function(enabled)
        setEventEnabled("rings", enabled)
    end
)
eventHandles.rings:AddSettings({
    {
        type = "slider",
        label = "Retry after",
        value = 2,
        min = 0.5,
        max = 10,
        step = 0.5,
        suffix = "s",
        callback = function(value)
            events.retry.rings = value
        end
    }
})

eventHandles.overdrive = eventsControl:Toggle(
    "Overdrive Tix Orbs",
    false,
    function(enabled)
        setEventEnabled("overdrive", enabled)
    end
)
eventHandles.overdrive:AddSettings({
    {
        type = "slider",
        label = "Retry after",
        value = 2,
        min = 0.5,
        max = 10,
        step = 0.5,
        suffix = "s",
        callback = function(value)
            events.retry.overdrive = value
        end
    }
})

eventHandles.masked = eventsControl:Toggle(
    "Masked Man Color Mania",
    false,
    function(enabled)
        setEventEnabled("masked", enabled)
    end
)
eventHandles.masked:AddSettings({
    {
        type = "slider",
        label = "Retry after",
        value = 2,
        min = 0.5,
        max = 10,
        step = 0.5,
        suffix = "s",
        callback = function(value)
            events.retry.masked = value
        end
    }
})

eventsControl:Button("Stop All", function()
    stopEvents()
end):SetStyle("danger")

eventsLive:Label(function()
    local status = events.status
    local line = (anyEventEnabled() and "Active" or "Idle")
        .. " · "
        .. status
    if events.current ~= "-"
        and not string.find(status, events.current, 1, true)
    then
        line = line .. " · " .. events.current
    end
    return line
end)
eventsLive:Label(function()
    local active = {}
    if events.enabled.summer then active[#active + 1] = "Summer" end
    if events.enabled.battle then active[#active + 1] = "Battle" end
    if events.enabled.disco then active[#active + 1] = "Disco" end
    if events.enabled.soccer then active[#active + 1] = "Soccer" end
    if events.enabled.rings then active[#active + 1] = "Rings" end
    if events.enabled.overdrive then active[#active + 1] = "Overdrive" end
    if events.enabled.masked then active[#active + 1] = "Masked" end
    return "Active: " .. (#active > 0 and table.concat(active, " · ") or "None")
end)
eventsLive:Label(function()
    local collected = {}
    local counts = events.counts
    if counts.summer > 0 then collected[#collected + 1] = "Summer " .. counts.summer end
    if counts.battle > 0 then collected[#collected + 1] = "Battle " .. counts.battle end
    if counts.disco > 0 then collected[#collected + 1] = "Disco " .. counts.disco end
    if counts.soccer > 0 then collected[#collected + 1] = "Soccer " .. counts.soccer end
    if counts.rings > 0 then collected[#collected + 1] = "Rings " .. counts.rings end
    if counts.overdrive > 0 then collected[#collected + 1] = "Overdrive " .. counts.overdrive end
    if counts.masked > 0 then collected[#collected + 1] = "Masked " .. counts.masked end
    local detail = #collected > 0 and table.concat(collected, " · ") or "None yet"
    return "Collected: " .. detail .. " · Total " .. counts.total
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

if world3AutoHandle:Get() then
    world3AutoHandle:Set(false)
else
    world3.auto = false
end

for kind, handle in pairs(eventHandles) do
    if handle:Get() then
        handle:Set(false)
    else
        events.enabled[kind] = false
    end
end

world3.eventsActive = false
events.running = false
events.returnPending = false
events.status = "Ready"
Lib:SetPerformance(false)
local uiPerformanceMode = false

task.spawn(function()
    while generation == _G.CelestialFarmGeneration do
        local shouldUsePerformance = world3.running
            or world3.auto
            or world3.eventsActive
            or anyEventEnabled()
        if shouldUsePerformance ~= uiPerformanceMode then
            uiPerformanceMode = shouldUsePerformance
            Lib:SetPerformance(uiPerformanceMode)
        end

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
            returnFromEvents(events.runToken, true)
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
