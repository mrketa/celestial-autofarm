local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local BBNO_PLACE_ID = 75012837977315
local BBNO_LOBBY_PLACE_ID = 95082159892680
local WORLD3_PLACE_ID = 93411036959889
local UINT32_RANGE = 4294967296
local MOTION_TICK = 1 / 30
local POLL_TICK = 0.05
local BBNO_AUTOJOIN_PREF = "celestial_bbno_autojoin.txt"
local player = Players.LocalPlayer
local scriptStartedAt = tick()

_G.CelestialFarmGeneration = (_G.CelestialFarmGeneration or 0) + 1
_G.World3AutoRouteSession = (_G.World3AutoRouteSession or 0) + 1
_G.World3AutoRouteRun = (_G.World3AutoRouteRun or 0) + 1
_G.CashFarmSession = (_G.CashFarmSession or 0) + 1

local generation = _G.CelestialFarmGeneration

pcall(function()
    if _G.CelestialFarmUI then
        _G.CelestialFarmUI:Destroy()
    end
end)

pcall(function()
    UI.RemoveTab("World 3")
    UI.RemoveTab("BBNO$ World")
    UI.RemoveTab("Cash Farm")
end)

local INS_UI_URL = "https://raw.githubusercontent.com/mrketa/celestial-autofarm/main/celestial_ui.lua"
local fetched, librarySource = pcall(function()
    if isfile("celestial_ui.lua") then
        return readfile("celestial_ui.lua")
    end

    return game:HttpGet(INS_UI_URL)
end)

if not fetched or type(librarySource) ~= "string" then
    warn("[Celestial] INS-ui Download fehlgeschlagen")
    return
end

local Lib = loadstring(librarySource)() or INSui

if not Lib then
    warn("[Celestial] INS-ui konnte nicht geladen werden")
    return
end

local function getRoot()
    local character = player.Character

    return character
        and character:FindFirstChild("HumanoidRootPart")
end

local function getCash()
    local leaderstats = player:FindFirstChild("leaderstats")

    if not leaderstats then
        return nil
    end

    local exact = leaderstats:FindFirstChild("$ CASH $")

    if exact then
        return exact
    end

    for _, value in ipairs(leaderstats:GetChildren()) do
        if value:IsA("ValueBase")
            and string.find(
                string.lower(value.Name),
                "cash",
                1,
                true
            )
        then
            return value
        end
    end

    return leaderstats:FindFirstChild("Wins")
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

local function readBbnoAutoJoin(defaultValue)
    if not isfile or not readfile or not isfile(BBNO_AUTOJOIN_PREF) then
        return defaultValue
    end

    local ok, value = pcall(readfile, BBNO_AUTOJOIN_PREF)

    if not ok then
        return defaultValue
    end

    return tostring(value) == "true"
end

local function writeBbnoAutoJoin(enabled)
    if writefile then
        pcall(writefile, BBNO_AUTOJOIN_PREF, enabled and "true" or "false")
    end
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
    local text = tostring(value or "Unbekannter Fehler")
    local message = string.match(text, "^[^:]+:%d+:%s*(.+)$")

    return message or text
end

local world3 = {
    auto = false,
    running = false,
    route = "Stage 1",
    speed = 300,
    status = "Bereit",
    point = "Spawn",
    cycles = 0,
    lastReward = 0,
    lastRewardAt = nil,
    collectSummerCoins = false,
    runToken = 0,
    spawnPosition = nil
}

local collectWorld3SummerCoins

local summerCoins = {
    auto = false,
    running = false,
    status = "Wartet auf Coins",
    collected = 0,
    visited = {},
    returnedToSpawn = false
}

local WORLD3_MINIMUM_TIME = 12.5
local WORLD3_WIN_PLATE = Vector3.new(
    -1431.3326,
    536.1462,
    759.6248
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

local function world3MayContinue(forceRun, token)
    return generation == _G.CelestialFarmGeneration
        and token == world3.runToken
        and (forceRun or world3.auto)
end

local function waitForWorld3Spawn(forceRun, token)
    local deadline = tick() + 8
    local stableSince
    local lastPosition

    world3.status = "Spawn wird synchronisiert"
    world3.point = "Spawn"

    while tick() < deadline do
        if not world3MayContinue(forceRun, token) then
            return false
        end

        local root = getRoot()

        if root then
            local position = root.Position
            local atSpawn = position.Y < -120 and position.Z < -900
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

local function tweenWorld3(target, forceRun, token, dwell)
    local root = getRoot()

    if not root then
        return false, "Charakter nicht verfügbar"
    end

    local startPosition = root.Position
    local distance = (target - startPosition).Magnitude
    local duration = distance / math.max(world3.speed, 1)
    local startedAt = tick()

    while tick() - startedAt < duration do
        if not world3MayContinue(forceRun, token) then
            stopPart(root)
            return false, "Gestoppt"
        end

        root = getRoot()

        if not root then
            return false, "Charakter wurde ersetzt"
        end

        local alpha = math.min((tick() - startedAt) / duration, 1)
        local position = startPosition:Lerp(target, alpha)

        stopPart(root)
        root.CFrame = CFrame.new(position.X, position.Y, position.Z)
        task.wait(MOTION_TICK)
    end

    root = getRoot()

    if not root then
        return false, "Charakter wurde ersetzt"
    end

    stopPart(root)
    root.CFrame = CFrame.new(target.X, target.Y, target.Z)
    task.wait(dwell or 0.2)

    if (root.Position - target).Magnitude > 12 then
        return false, "Bewegung wurde korrigiert"
    end

    return true
end

local function moveWorld3Physics(target, forceRun, token, dwell)
    local deadline = tick() + 2

    while tick() < deadline do
        if not world3MayContinue(forceRun, token) then
            return false, "Gestoppt"
        end

        local root = getRoot()

        if not root then
            return false, "Charakter nicht verfügbar"
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
    return false, "Safe Start wurde nicht erreicht"
end

local function enterWorld3WinPlate(cashValue, cashBefore, forceRun, token)
    local deadline = tick() + 5
    local reached = false

    world3.status = "Stage 5 wird betreten"
    world3.point = "Stage 5"

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
            WORLD3_WIN_PLATE.X - root.Position.X,
            0,
            WORLD3_WIN_PLATE.Z - root.Position.Z
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

    world3.status = "Reward wird bestätigt"
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

    world3.status = "Nächster Orbit wird vorbereitet"
    world3.point = "Reset"

    while tick() < deadline do
        if not world3MayContinue(forceRun, token) then
            return false
        end

        local root = getRoot()

        if root and root.Position.Y < -120 and root.Position.Z < -900 then
            task.wait(0.5)
            return true
        end

        task.wait(POLL_TICK)
    end

    return false
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
        assert(world3MayContinue(forceRun, token), "Gestoppt")
        error("Kein stabiler Spawn gefunden")
    end

    local safeStart = WORLD3_ROUTE[1]

    world3.status = "Safe Start wird angelaufen"
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

    assert(cashValue, "Wins-Wert nicht verfügbar")
    assert(winBlock, "WinBlock32 nicht gefunden")

    local root = getRoot()
    assert(root, "Charakter nicht verfügbar")
    local stage1Entry = WORLD3_ROUTE[2].position
    local cashBefore = cashValue.Value

    world3.status = "Direkt zu Stage 1"
    world3.point = "Stage 1 Eingang"
    local reachedStage1 = false

    for attempt = 1, 3 do
        root = getRoot()
        assert(root, "Charakter nicht verfügbar")

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
                "Stage 1 Versuch %d/3",
                attempt + 1
            )
        end
    end

    assert(reachedStage1, "Stage-1-Teleport wurde korrigiert")

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

        world3.status = "Wartet auf Lauf-Fenster"

        while tick() < walkAt do
            assert(world3MayContinue(forceRun, token), "Gestoppt")
            task.wait(math.max(
                0.001,
                math.min(POLL_TICK, walkAt - tick())
            ))
        end
    end

    world3.status = "Läuft auf WinBlock32"
    world3.point = "WinBlock32"
    local rewardDeadline = tick() + 2.5
    local lastDistance = math.huge
    local lastProgressAt = tick()

    while tick() < rewardDeadline do
        if not world3MayContinue(forceRun, token) then
            stopRoot()
            error("Gestoppt")
        end

        if cashValue.Value ~= cashBefore then
            stopRoot()
            local reward = cashDelta(cashValue.Value, cashBefore)

            world3.cycles = world3.cycles + 1
            world3.lastReward = reward
            world3.lastRewardAt = tick()
            world3.status = "Stage-1-Reward bestätigt"

            Lib:Notify(
                "World 3 Stage 1",
                "+" .. formatNumber(reward) .. " Wins",
                2,
                "success"
            )

            if not waitForWorld3Reset(forceRun, token) then
                assert(world3MayContinue(forceRun, token), "Gestoppt")
                error("Spawn-Reset nicht erkannt")
            end

            if world3.collectSummerCoins then
                collectWorld3SummerCoins(forceRun, token)
            end

            return
        end

        root = getRoot()

        if not root then
            error("Charakter nicht verfügbar")
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

    error("WinBlock32-Reward wurde nicht erkannt")
end

local function runWorld3WinBlock35Cycle(forceRun, token)
    if not waitForWorld3Spawn(forceRun, token) then
        assert(world3MayContinue(forceRun, token), "Gestoppt")
        error("Kein stabiler Spawn gefunden")
    end

    local cashValue = getWorld3Wins()

    assert(cashValue, "Wins-Wert nicht verfügbar")

    local cashBefore = cashValue.Value
    local cycleStartedAt = tick()

    for index, point in ipairs(WORLD3_ROUTE) do
        world3.status = "Route läuft"
        world3.point = string.format(
            "%d/%d  %s",
            index,
            #WORLD3_ROUTE,
            point.name
        )

        local moved
        local moveError

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
                    point.dwell
                )

                if moved or moveError ~= "Bewegung wurde korrigiert" then
                    break
                end

                world3.status = string.format(
                    "%s: Versuch %d/3",
                    point.name,
                    attempt + 1
                )
                task.wait(0.2)
            end
        end

        assert(moved, point.name .. ": " .. tostring(moveError))
    end

    world3.status = "Wartet auf Reward"
    world3.point = "Win staging"
    stopRoot()

    while tick() - cycleStartedAt < WORLD3_MINIMUM_TIME do
        assert(world3MayContinue(forceRun, token), "Gestoppt")
        task.wait(POLL_TICK)
    end

    if not enterWorld3WinPlate(
        cashValue,
        cashBefore,
        forceRun,
        token
    ) then
        assert(world3MayContinue(forceRun, token), "Gestoppt")
        error("Reward wurde nicht erkannt")
    end

    local reward = cashDelta(cashValue.Value, cashBefore)

    world3.cycles = world3.cycles + 1
    world3.lastReward = reward
    world3.lastRewardAt = tick()
    world3.status = "Reward bestätigt"
    world3.point = "Stage 5"

    Lib:Notify(
        "World 3 Stage 5",
        "+" .. formatNumber(reward) .. " Wins",
        2,
        "success"
    )

    if not waitForWorld3Reset(forceRun, token) then
        assert(world3MayContinue(forceRun, token), "Gestoppt")
        error("Spawn-Reset nicht erkannt")
    end

    if world3.collectSummerCoins then
        collectWorld3SummerCoins(forceRun, token)
    end
end

local function runWorld3(forceRun)
    if game.PlaceId ~= WORLD3_PLACE_ID then
        world3.auto = false
        Lib:Notify(
            "World 3",
            "Wechsle zuerst in World 3.",
            3,
            "warning"
        )
        return
    elseif world3.running then
        Lib:Notify("World 3", "Die Route läuft bereits.", 2, "info")
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
            world3.status = world3.auto and "Nächster Orbit" or "Bereit"
            world3.point = world3.auto and "Spawn" or "Abgeschlossen"
        else
            local message = cleanError(failure)

            if not string.find(message, "Gestoppt", 1, true) then
                world3.status = "Fehler: " .. message
                world3.auto = false
                Lib:Notify("World 3", message, 4, "error")
            else
                world3.status = "Gestoppt"
                world3.point = "-"
            end
        end
    end)
end

local function stopWorld3()
    world3.auto = false
    world3.runToken = world3.runToken + 1
    world3.status = "Gestoppt"
    world3.point = "-"
    stopRoot()
end

local queueTeleport = queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)

local bbno = {
    auto = game.PlaceId == BBNO_PLACE_ID
        and game.PrivateServerId ~= "",
    autoJoin = readBbnoAutoJoin(
        game.PlaceId == BBNO_PLACE_ID
            or game.PlaceId == BBNO_LOBBY_PLACE_ID
    ),
    joining = false,
    joinAttemptAt = 0,
    running = false,
    speed = 300,
    status = "Bereit",
    stage = "Spawn",
    cycles = 0,
    earned = 0,
    recoveries = 0,
    lastRewardAt = nil,
    runToken = 0
}

if (game.PlaceId == BBNO_PLACE_ID or game.PlaceId == BBNO_LOBBY_PLACE_ID)
    and (not isfile or not isfile(BBNO_AUTOJOIN_PREF))
then
    writeBbnoAutoJoin(bbno.autoJoin)
end

if game.PlaceId == BBNO_PLACE_ID then
    if type(queueTeleport) == "function" then
        local bootstrap = string.format([=[
if _G.CelestialBbnoRejoinBootstrap then return end
_G.CelestialBbnoRejoinBootstrap = true
repeat task.wait(1) until game:IsLoaded()

local enabled = true
if isfile and readfile and isfile(%q) then
    local ok, value = pcall(readfile, %q)
    enabled = not ok or tostring(value) == "true"
end

if enabled and game.PlaceId == %d then
    task.wait(3)
    local service = game:GetService("TeleportService")
    local player = game:GetService("Players").LocalPlayer

    for _ = 1, 12 do
        pcall(function()
            service:Teleport(%d, player)
        end)
        task.wait(10)
    end
end
]=], BBNO_AUTOJOIN_PREF, BBNO_AUTOJOIN_PREF, BBNO_LOBBY_PLACE_ID, BBNO_PLACE_ID)

        pcall(queueTeleport, bootstrap)
    end
end

local BBNO_FINAL_DEFAULT = Vector3.new(
    112.16692352294922,
    811.8273315429688,
    960.5953369140625
)
local BBNO_WALK_DEFAULT = Vector3.new(93.43, 812.03, 937.55)
local BBNO_STAGE2 = Vector3.new(142.8027, 59.5576, -235.4966)
local BBNO_CONFIG_PATH = "cash_farm_routes.json"
local BBNO_REWARD_INTERVAL_MS = 3050
local BBNO_READY_DELAY_MS = 450
local BBNO_SPRINT_TIME = 0.25
local BBNO_SPRINT_LEAD = 0.08
local bbnoFinal = BBNO_FINAL_DEFAULT
local bbnoWalk = BBNO_WALK_DEFAULT
local bbnoDirection = Vector3.zAxis
local bbnoRemote

local function tableToVector(value, fallback)
    if type(value) ~= "table"
        or type(value.x) ~= "number"
        or type(value.y) ~= "number"
        or type(value.z) ~= "number"
    then
        return fallback
    end

    return Vector3.new(value.x, value.y, value.z)
end

local function loadBbnoRoute()
    local ok, decoded = pcall(function()
        if not isfile(BBNO_CONFIG_PATH) then
            return nil
        end

        return HttpService:JSONDecode(readfile(BBNO_CONFIG_PATH))
    end)

    if ok and type(decoded) == "table"
        and type(decoded.worlds) == "table"
    then
        local route = decoded.worlds[tostring(BBNO_PLACE_ID)]

        if type(route) == "table" then
            bbnoFinal = tableToVector(
                route.teleportPoint,
                BBNO_FINAL_DEFAULT
            )
            bbnoWalk = tableToVector(route.walkPoint, BBNO_WALK_DEFAULT)
        end
    end

    local offset = bbnoWalk - bbnoFinal
    local horizontal = Vector3.new(offset.X, 0, offset.Z)

    bbnoDirection = horizontal.Magnitude > 0
        and horizontal.Unit
        or Vector3.zAxis
end

loadBbnoRoute()

local function getBbnoRemote()
    if bbnoRemote and bbnoRemote.Parent then
        return bbnoRemote
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    bbnoRemote = remotes
        and remotes:FindFirstChild("RequestCheckpointTp")

    return bbnoRemote
end

local function bbnoMayContinue(forceRun, token)
    return generation == _G.CelestialFarmGeneration
        and token == bbno.runToken
        and (forceRun or bbno.auto)
end

local function waitForBbnoStage2(root, forceRun, token, remote)
    local startedAt = tick()
    local initialPosition = root.Position
    local lastPosition = root.Position
    local lastMovementAt = startedAt
    local lastRequestAt = startedAt

    while tick() - startedAt < 6 do
        local currentRoot = getRoot()

        if currentRoot and (currentRoot ~= root or not root.Parent) then
            root = currentRoot
            lastPosition = root.Position
            lastMovementAt = tick()
            bbno.status = "Stage 2 wird geladen"
        elseif not currentRoot then
            task.wait(POLL_TICK)
        end

        if currentRoot then
            stopPart(root)

            if not bbnoMayContinue(forceRun, token) then
                return false
            end

            local currentPosition = root.Position

            if (currentPosition - lastPosition).Magnitude > 1 then
                lastPosition = currentPosition
                lastMovementAt = tick()
            end

            local atKnownStage = (
                currentPosition - BBNO_STAGE2
            ).Magnitude < 150
            local serverMovedFar = (
                currentPosition - initialPosition
            ).Magnitude >= 250
            local atStage2 = atKnownStage or serverMovedFar

            if not atStage2 and tick() - lastRequestAt >= 1.2 then
                bbno.status = "Stage 2 wird erneut angefragt"
                remote:FireServer(1, "wins")
                lastRequestAt = tick()
            end

            if tick() - startedAt >= 0.8
                and tick() - lastMovementAt >= 0.25
                and atStage2
            then
                stopPart(root)
                return true, root
            end
        end

        task.wait(POLL_TICK)
    end

    return false, nil, "Stage 2 wurde nicht bestätigt"
end

local function moveBbnoFinal(root, forceRun, token)
    for attempt = 1, 3 do
        if not bbnoMayContinue(forceRun, token) then
            return false
        elseif root ~= getRoot() or not root.Parent then
            return false, "Reset beim Final-Transfer"
        end

        bbno.status = attempt == 1
            and "Direkt zur Final Stage"
            or string.format("Final Stage: Versuch %d/3", attempt)
        stopPart(root)
        root.Position = bbnoFinal
        task.wait(0.12)

        local currentRoot = getRoot()

        if currentRoot ~= root or not root.Parent then
            return false, "Reset beim Final-Transfer"
        elseif (root.Position - bbnoFinal).Magnitude <= 20 then
            task.wait(0.08)

            if root == getRoot()
                and root.Parent
                and (root.Position - bbnoFinal).Magnitude <= 20
            then
                return true
            end
        end
    end

    stopRoot()
    return false, "Final Stage wurde nicht bestätigt"
end

local function sprintBbnoReward(
    root,
    cashValue,
    cashBefore,
    forceRun,
    token
)
    local startedAt = tick()

    while tick() - startedAt < BBNO_SPRINT_TIME do
        if cashValue.Value ~= cashBefore then
            stopRoot()
            return cashDelta(cashValue.Value, cashBefore), tick()
        elseif not bbnoMayContinue(forceRun, token) then
            stopRoot()
            return nil, nil
        elseif (root.Position - bbnoFinal).Magnitude > 150 then
            stopRoot()
            return nil, nil
        end

        root.AssemblyLinearVelocity = Vector3.new(
            bbnoDirection.X * bbno.speed,
            0,
            bbnoDirection.Z * bbno.speed
        )
        task.wait(MOTION_TICK)
    end

    stopRoot()
    return nil, nil
end

local function waitForBbnoReward(
    cashValue,
    cashBefore,
    forceRun,
    token,
    timeout
)
    local startedAt = tick()
    stopRoot()

    while tick() - startedAt < timeout do
        if cashValue.Value ~= cashBefore then
            return cashDelta(cashValue.Value, cashBefore)
        elseif not bbnoMayContinue(forceRun, token) then
            return nil
        end

        task.wait(POLL_TICK)
    end

    return nil
end

local function runBbnoCycle(forceRun, token)
    local root = getRoot()
    local cashValue = getCash()
    local remote = getBbnoRemote()

    assert(root, "Charakter nicht verfügbar")
    assert(cashValue, "Cash-Wert nicht verfügbar")
    assert(remote, "Checkpoint-Remote nicht verfügbar")

    local cashBefore = cashValue.Value

    bbno.status = "Stage 2"
    bbno.stage = "1/3  Checkpoint"
    remote:FireServer(1, "wins")

    local stageReady, stageRoot, stageError = waitForBbnoStage2(
        root,
        forceRun,
        token,
        remote
    )

    if not stageReady then
        assert(bbnoMayContinue(forceRun, token), "Gestoppt")
        error(stageError or "Stage 2 wurde nicht bestätigt")
    end

    root = stageRoot

    task.wait(0.15)
    assert(bbnoMayContinue(forceRun, token), "Gestoppt")

    bbno.status = "Final Stage"
    bbno.stage = "2/3  Final"

    local finalReady, finalError = moveBbnoFinal(
        root,
        forceRun,
        token
    )

    if not finalReady then
        assert(bbnoMayContinue(forceRun, token), "Gestoppt")
        error(finalError or "Final Stage wurde nicht bestätigt")
    end

    local sprintDeadline = bbno.lastRewardAt
        and bbno.lastRewardAt
            + BBNO_REWARD_INTERVAL_MS / 1000
            - BBNO_SPRINT_LEAD
        or nil
    local readyAt = tick() + BBNO_READY_DELAY_MS / 1000

    if sprintDeadline then
        readyAt = math.min(readyAt, sprintDeadline)
    end

    bbno.status = "Bereit für Reward"
    stopRoot()

    while tick() < readyAt do
        assert(bbnoMayContinue(forceRun, token), "Gestoppt")
        task.wait(POLL_TICK)
    end

    if sprintDeadline and tick() < sprintDeadline then
        bbno.status = "Reward Cooldown"
        stopRoot()

        while tick() < sprintDeadline do
            assert(bbnoMayContinue(forceRun, token), "Gestoppt")
            task.wait(POLL_TICK)
        end
    end

    bbno.status = "Reward Sprint"
    bbno.stage = "3/3  Reward"

    local difference, rewardAt = sprintBbnoReward(
        root,
        cashValue,
        cashBefore,
        forceRun,
        token
    )

    if not difference then
        difference = waitForBbnoReward(
            cashValue,
            cashBefore,
            forceRun,
            token,
            0.8
        )

        if difference then
            rewardAt = tick()
        end
    end

    if not difference and bbnoMayContinue(forceRun, token) then
        bbno.status = "Reward wird erneut versucht"

        local recovered, recoveryError = moveBbnoFinal(
            root,
            forceRun,
            token
        )

        if recovered then
            task.wait(0.25)
            difference, rewardAt = sprintBbnoReward(
                root,
                cashValue,
                cashBefore,
                forceRun,
                token
            )

            if not difference then
                difference = waitForBbnoReward(
                    cashValue,
                    cashBefore,
                    forceRun,
                    token,
                    1.2
                )

                if difference then
                    rewardAt = tick()
                end
            end
        elseif recoveryError == "Reset beim Final-Transfer" then
            error(recoveryError)
        end
    end

    if not difference then
        assert(bbnoMayContinue(forceRun, token), "Gestoppt")
        error("Reward wurde nicht erkannt")
    end

    bbno.lastRewardAt = rewardAt or tick()
    bbno.cycles = bbno.cycles + 1
    bbno.earned = bbno.earned + difference
    bbno.recoveries = 0
    bbno.status = "Reward bestätigt"
    bbno.stage = "Abgeschlossen"

    Lib:Notify(
        "BBNO$",
        "+" .. formatNumber(difference) .. " Cash",
        2,
        "success"
    )
end

local function joinBbno(forceJoin)
    if game.PlaceId == BBNO_PLACE_ID then
        return true
    elseif game.PlaceId ~= BBNO_LOBBY_PLACE_ID then
        if forceJoin then
            Lib:Notify(
                "BBNO$",
                "Auto Rejoin ist nur aus der World-1-Lobby verfügbar.",
                3,
                "warning"
            )
        end

        return false
    elseif not forceJoin and not bbno.autoJoin then
        return false
    elseif bbno.joining and tick() - bbno.joinAttemptAt < 10 then
        return false
    end

    bbno.joining = true
    bbno.joinAttemptAt = tick()
    bbno.status = "Verbinde mit BBNO$ World"
    bbno.stage = "Auto Rejoin"

    local ok, failure = pcall(function()
        TeleportService:Teleport(BBNO_PLACE_ID, player)
    end)

    if not ok then
        bbno.joining = false
        bbno.status = "Rejoin fehlgeschlagen"

        if forceJoin then
            Lib:Notify("BBNO$", cleanError(failure), 4, "error")
        end
    end

    return ok
end

local teleportInitFailed
pcall(function()
    teleportInitFailed = TeleportService.TeleportInitFailed
end)

if teleportInitFailed then
    pcall(function()
        teleportInitFailed:Connect(function(
            failedPlayer,
            _,
            errorMessage,
            placeId
        )
            if generation ~= _G.CelestialFarmGeneration
                or failedPlayer ~= player
                or placeId ~= BBNO_PLACE_ID
            then
                return
            end

            bbno.joining = false
            bbno.status = "Rejoin fehlgeschlagen"
            Lib:Notify(
                "BBNO$ Auto Rejoin",
                tostring(errorMessage or "Teleport nicht verfügbar"),
                4,
                "error"
            )
        end)
    end)
end

local function runBbno(forceRun)
    if game.PlaceId ~= BBNO_PLACE_ID then
        joinBbno(forceRun)
        return
    elseif bbno.running then
        Lib:Notify("BBNO$", "Die Farm läuft bereits.", 2, "info")
        return
    end

    bbno.running = true
    bbno.runToken = bbno.runToken + 1
    local token = bbno.runToken

    task.spawn(function()
        local ok, failure = pcall(function()
            repeat
                runBbnoCycle(forceRun, token)
            until forceRun or not bbnoMayContinue(false, token)
        end)

        if generation == _G.CelestialFarmGeneration
            and token == bbno.runToken
        then
            stopRoot()
        end
        bbno.running = false

        if ok then
            bbno.status = bbno.auto and "Nächster Orbit" or "Bereit"
            bbno.stage = bbno.auto and "Spawn" or "Abgeschlossen"
        else
            local message = cleanError(failure)
            local recoverable = string.find(
                message,
                "Reset beim Final-Transfer",
                1,
                true
            ) or string.find(
                message,
                "Stage 2 wurde nicht bestätigt",
                1,
                true
            ) or string.find(
                message,
                "Final Stage wurde nicht bestätigt",
                1,
                true
            )

            if recoverable and bbno.auto then
                bbno.recoveries = bbno.recoveries + 1

                if bbno.recoveries >= 3 then
                    bbno.auto = false
                    bbno.status = "Server blockiert Final-Transfer"
                    bbno.stage = "Sicherheitsstopp"
                    Lib:Notify(
                        "BBNO$",
                        "Final-Transfer wurde dreimal blockiert.",
                        5,
                        "error"
                    )
                else
                    bbno.running = true
                    bbno.status = "Respawn erkannt, neuer Versuch"
                    bbno.stage = "Recovery"
                    task.wait(1.5)
                    bbno.running = false
                end
            elseif not string.find(message, "Gestoppt", 1, true) then
                bbno.status = "Fehler: " .. message
                bbno.auto = false
                Lib:Notify("BBNO$", message, 4, "error")
            else
                bbno.status = "Gestoppt"
                bbno.stage = "-"
            end
        end
    end)
end

local function stopBbno()
    bbno.auto = false
    bbno.runToken = bbno.runToken + 1
    bbno.status = "Gestoppt"
    bbno.stage = "-"
    stopRoot()
end

local function findNearestSummerCoin()
    local folder = workspace:FindFirstChild("SummerCoinsLocal")
    local root = getRoot()

    if not folder or not root then
        return nil, nil
    end

    local nearestModel
    local nearestPart
    local nearestDistance = math.huge

    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model")
            and model.Name == "SummerCoin"
            and not summerCoins.visited[model]
        then
            local coin = model:FindFirstChild("Coin", true)

            if coin and coin:IsA("BasePart") then
                local distance = (coin.Position - root.Position).Magnitude

                if distance < nearestDistance then
                    nearestModel = model
                    nearestPart = coin
                    nearestDistance = distance
                end
            end
        end
    end

    return nearestModel, nearestPart
end

local function hasActiveSummerCoins()
    local folder = workspace:FindFirstChild("SummerCoinsLocal")

    if not folder then
        return false
    end

    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model")
            and model.Name == "SummerCoin"
            and model:FindFirstChild("Coin", true)
        then
            return true
        end
    end

    return false
end

local function collectNearestSummerCoin()
    local model, coin = findNearestSummerCoin()

    if not model or not coin then
        return false
    end

    local root = getRoot()

    if not root then
        summerCoins.status = "Charakter nicht verfügbar"
        return false
    end

    summerCoins.visited[model] = true
    summerCoins.returnedToSpawn = false
    summerCoins.status = "Sammelt Summer Coin"
    stopPart(root)
    root.Position = coin.Position + Vector3.new(0, 3, 0)
    task.wait(0.5)

    if not model.Parent then
        summerCoins.collected = summerCoins.collected + 1
        summerCoins.status = "Coin eingesammelt"
    else
        summerCoins.status = "Coin nicht bestätigt"
        task.spawn(function()
            task.wait(1.5)
            if model.Parent then
                summerCoins.visited[model] = nil
            end
        end)
    end

    return true
end

local function returnToWorld3Spawn()
    if game.PlaceId ~= WORLD3_PLACE_ID then
        return false
    end

    local target = world3.spawnPosition or WORLD3_ROUTE[1].position

    if not target then
        return false
    end

    for attempt = 1, 6 do
        local root = getRoot()

        summerCoins.status = string.format(
            "Spawn TP %d/6",
            attempt
        )

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
                    summerCoins.returnedToSpawn = true
                    summerCoins.status = "Zurück am Spawn"
                    return true
                end
            end
        end

        task.wait(0.2)
    end

    stopRoot()
    summerCoins.returnedToSpawn = false
    summerCoins.status = "Spawn TP wurde korrigiert"
    return false
end

collectWorld3SummerCoins = function(forceRun, token)
    summerCoins.status = "Scannt Summer Coins"
    world3.status = "Scannt Summer Coins"
    world3.point = "Summer Coins"
    local deadline = tick() + 20

    while world3MayContinue(forceRun, token)
        and world3.collectSummerCoins
        and tick() < deadline
    do
        if not collectNearestSummerCoin() then
            if not hasActiveSummerCoins() then
                break
            end

            task.wait(0.1)
        end
    end

    assert(world3MayContinue(forceRun, token), "Gestoppt")
    assert(returnToWorld3Spawn(), "Spawn-Teleport wurde korrigiert")
    world3.status = "Summer Coins abgeschlossen"
    world3.point = "Spawn"
end

local function startSummerCoins()
    if summerCoins.running then
        return
    end

    stopWorld3()
    stopBbno()
    summerCoins.auto = true
    summerCoins.running = true

    task.spawn(function()
        while generation == _G.CelestialFarmGeneration
            and summerCoins.auto
        do
            if not collectNearestSummerCoin() then
                if hasActiveSummerCoins() then
                    summerCoins.status = "Wartet auf Coin-Bestätigung"
                else
                    if not summerCoins.returnedToSpawn then
                        if not returnToWorld3Spawn() then
                            summerCoins.status = "Spawn TP wurde korrigiert"
                        end
                    end

                    if summerCoins.returnedToSpawn then
                        summerCoins.status = "Wartet am Spawn"
                    end
                end
                task.wait(0.1)
            end
        end

        summerCoins.running = false
    end)
end

local function stopSummerCoins()
    summerCoins.auto = false
    summerCoins.status = "Gestoppt"
    stopRoot()
end

local window = Lib:CreateWindow({
    title = "CELESTIAL",
    subtitle = "",
    size = Vector2.new(660, 545),
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

Lib:Category("ORBITS")
local world3Tab = window:Tab("World 3", "target")
local world3Control = world3Tab:Section(
    "World 3 Orbit",
    "Left"
)
local world3Live = world3Tab:Section(
    "Live Orbit",
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

world3Control:Toggle(
    "Collect Summer Coins",
    false,
    function(enabled)
        world3.collectSummerCoins = enabled == true
    end
)

world3Control:Dropdown(
    "Route",
    "Stage 1",
    { "Stage 1", "Stage 5" },
    false,
    function(value)
        local selected = type(value) == "table" and value[1] or value

        if selected == "Stage 1 Event" then
            selected = "Stage 1"
        elseif selected == "WinBlock35" then
            selected = "Stage 5"
        end

        if type(value) == "table" then
            value[1] = selected
        end

        world3.route = selected
    end
)

world3Control:Slider(
    "Speed",
    300,
    10,
    50,
    1000,
    " studs/s",
    function(value)
        world3.speed = value
    end
)

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
    return "Orbits: " .. tostring(world3.cycles)
end)
world3Live:Label(function()
    return "Letzte Wins: " .. formatNumber(world3.lastReward)
end)

local bbnoTab = window:Tab("BBNO$", "rocket")
local bbnoControl = bbnoTab:Section(
    "BBNO$ Orbit",
    "Left"
)
local bbnoLive = bbnoTab:Section(
    "Live Orbit",
    "Right"
)

local bbnoAutoHandle

bbnoAutoHandle = bbnoControl:Toggle(
    "Auto Farm",
    bbno.auto,
    function(enabled)
        bbno.auto = enabled == true

        if not bbno.auto then
            stopBbno()
        end
    end
)

bbnoControl:Slider(
    "Speed",
    300,
    10,
    100,
    400,
    " studs/s",
    function(value)
        bbno.speed = value
    end
)

bbnoControl:Toggle(
    "Auto Rejoin",
    bbno.autoJoin,
    function(enabled)
        bbno.autoJoin = enabled == true
        writeBbnoAutoJoin(bbno.autoJoin)
    end
)

bbnoControl:Button("Run", function()
    runBbno(true)
end):AddButton("Join", function()
    joinBbno(true)
end):AddButton("Stop", function()
    stopBbno()

    if bbnoAutoHandle:Get() then
        bbnoAutoHandle:Set(false)
    end
end)

bbnoLive:Label(function()
    return "Status: " .. bbno.status
end)
bbnoLive:Label(function()
    return "Phase: " .. bbno.stage
end)
bbnoLive:Label(function()
    return bbno.autoJoin and "Rejoin: On" or "Rejoin: Off"
end)
bbnoLive:Label(function()
    return "Orbits: " .. tostring(bbno.cycles)
end)
bbnoLive:Label(function()
    return "Verdient: " .. formatNumber(bbno.earned)
end)

local summerTab = window:Tab("Summer Coins", "star")
local summerControl = summerTab:Section(
    "Summer Coin Collector",
    "Left"
)
local summerLive = summerTab:Section(
    "Live",
    "Right"
)

local summerAutoHandle

summerAutoHandle = summerControl:Toggle(
    "Auto Collect",
    false,
    function(enabled)
        if enabled then
            startSummerCoins()
        else
            stopSummerCoins()
        end
    end
)

summerControl:Button("Collect", function()
    if not collectNearestSummerCoin() then
        Lib:Notify(
            "Summer Coins",
            "Keine aktive Coin gefunden.",
            3,
            "info"
        )
    end
end):AddButton("Stop", function()
    stopSummerCoins()

    if summerAutoHandle:Get() then
        summerAutoHandle:Set(false)
    end
end)

summerLive:Label(function()
    return "Status: " .. summerCoins.status
end)
summerLive:Label(function()
    local folder = workspace:FindFirstChild("SummerCoinsLocal")
    local count = 0

    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model.Name == "SummerCoin" then
                count = count + 1
            end
        end
    end

    return "Aktive Coins: " .. tostring(count)
end)
summerLive:Label(function()
    return "Eingesammelt: " .. tostring(summerCoins.collected)
end)

task.spawn(function()
    while generation == _G.CelestialFarmGeneration do
        if world3AutoHandle:Get() ~= world3.auto then
            world3AutoHandle:Set(world3.auto)
        end

        if bbnoAutoHandle:Get() ~= bbno.auto then
            bbnoAutoHandle:Set(bbno.auto)
        end

        if summerAutoHandle:Get() ~= summerCoins.auto then
            summerAutoHandle:Set(summerCoins.auto)
        end

        if world3.auto and not world3.running then
            runWorld3(false)
        end

        if bbno.auto and not bbno.running then
            runBbno(false)
        end

        if game.PlaceId == BBNO_LOBBY_PLACE_ID
            and bbno.autoJoin
            and tick() - scriptStartedAt >= 3
        then
            joinBbno(false)
        end

        task.wait(0.1)
    end
end)

Lib:Notify(
    "Celestial",
    "Orbit Farm bereit · ENTF öffnet das Menü",
    4,
    "success"
)
