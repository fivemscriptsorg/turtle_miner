-- ============================================================
-- FARMER MODULE
-- Cultivo automatizado de trigo, zanahoria, patata y remolacha.
--
-- GEOMETRIA:
--   La turtle se mueve POR ENCIMA del farmland. Es decir:
--     - Farmland a Y=0 (el suelo arado)
--     - Cultivos creciendo a Y=1 (estan plantados en el farmland)
--     - Turtle a Y=2 (un bloque encima del cultivo)
--   turtle.inspectDown() devuelve el cultivo a Y=1.
--   turtle.digDown() / turtle.placeDown() operan sobre Y=1.
--
--   Casa = (0,0,0) mirando +X.
--   El plot se extiende hacia +X (ancho W) y +Z (largo L).
--   Cofre atras en (-1,0,0) para volcar cosecha.
--
-- REQUISITOS:
--   - El plot ya tiene que estar preparado (farmland regado).
--   - Semillas en inventario para los cultivos que se cultiven.
--   - Agua cada 9x9 bloques de farmland.
--
-- Patron: serpentina. Recorre fila +X, avanza 1 en Z, vuelve -X,
-- avanza 1 en Z, y asi. Al final vuelve a casa, vuelca, duerme.
-- ============================================================

-- Nombre del bloque -> { seed = item usado para replantar, maxAge = N }
local CROPS = {
    ["minecraft:wheat"]     = { seed = "minecraft:wheat_seeds",    maxAge = 7 },
    ["minecraft:carrots"]   = { seed = "minecraft:carrot",         maxAge = 7 },
    ["minecraft:potatoes"]  = { seed = "minecraft:potato",         maxAge = 7 },
    ["minecraft:beetroots"] = { seed = "minecraft:beetroot_seeds", maxAge = 3 },
}

-- ============================================================
-- REMOTE COMMAND
-- ============================================================

local function checkRemoteCmd()
    if not state.hasRemote then return false end
    if state.remoteCmd == "pause" then
        ui.setStatus("PAUSADO (remoto)")
        while state.remoteCmd == "pause" do sleep(0.3) end
        ui.setStatus("Reanudando")
        if state.remoteCmd == "resume" then state.remoteCmd = nil end
    end
    return state.remoteCmd == "home" or state.remoteCmd == "stop"
end

-- ============================================================
-- BROADCAST
-- ============================================================

local function notifyCrop(name)
    if not state.hasRemote then return end
    pcall(remote.notifyEvent, "crop", {
        name = name,
        count = state.cropsHarvested or 0,
    })
end

-- ============================================================
-- CELL PROCESSING
-- Inspecciona el bloque debajo. Si es un cultivo maduro, lo
-- cosecha y replanta con la semilla correspondiente.
-- ============================================================

local function selectSeed(seedName)
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and d.name == seedName then
            turtle.select(i)
            return i
        end
    end
    return nil
end

local function processCell()
    local ok, block = turtle.inspectDown()
    if not ok or not block or not block.name then return false end

    local crop = CROPS[block.name]
    if not crop then return false end

    local age = (block.state and block.state.age) or 0
    if age < crop.maxAge then return false end

    turtle.digDown()
    state.cropsHarvested = (state.cropsHarvested or 0) + 1
    notifyCrop(block.name)

    -- Replantar si hay semilla. Si no, queda farmland vacia.
    if selectSeed(crop.seed) then
        turtle.placeDown()
    end
    return true
end

-- ============================================================
-- SERPENTINA
-- Recorre plot W x L empezando en (0,0,0) mirando +X.
-- ============================================================

local function walkPlot()
    local W = math.max(1, state.farmWidth or 5)
    local L = math.max(1, state.farmLength or 5)

    -- Primera celda: bajo la turtle
    processCell()
    if inventory.isAlmostFull() then
        inventory.compact()
    end

    local dir = 0 -- 0 = +X, 2 = -X
    for row = 1, L do
        -- Recorrer el resto de la fila
        for c = 2, W do
            if checkRemoteCmd() then return false end
            if not movement.safeForward() then return false end
            processCell()
            if inventory.isAlmostFull() then
                inventory.compact()
                if inventory.isAlmostFull() then return false end
            end
        end

        state.farmRow = row
        persist.save()

        if row == L then break end

        -- Avanzar a la fila siguiente cambiando direccion
        if dir == 0 then
            movement.turnRight()
            if not movement.safeForward() then return false end
            processCell()
            movement.turnRight()
            dir = 2
        else
            movement.turnLeft()
            if not movement.safeForward() then return false end
            processCell()
            movement.turnLeft()
            dir = 0
        end

        if inventory.isAlmostFull() then
            inventory.compact()
            if inventory.isAlmostFull() then return false end
        end
    end

    return true
end

-- ============================================================
-- NAVEGACION HOME
-- Vuelve a (0,0,0) mirando +X desde cualquier punto del plot.
-- ============================================================

local function returnHome()
    ui.setStatus("Volviendo a casa")
    if state.x > 0 then
        movement.faceDirection(2)
        while state.x > 0 do
            if not movement.safeForward() then break end
        end
    elseif state.x < 0 then
        movement.faceDirection(0)
        while state.x < 0 do
            if not movement.safeForward() then break end
        end
    end
    if state.z > 0 then
        movement.faceDirection(3)
        while state.z > 0 do
            if not movement.safeForward() then break end
        end
    elseif state.z < 0 then
        movement.faceDirection(1)
        while state.z < 0 do
            if not movement.safeForward() then break end
        end
    end
    movement.faceDirection(0)
end

local function dumpAtHome()
    ui.setStatus("Volcando cultivos")
    movement.faceDirection(2)
    inventory.dumpInto("forward")
    movement.faceDirection(0)
end

-- ============================================================
-- ENTRY POINT
-- ============================================================

local function sleepInterruptible(secs)
    for _ = 1, secs do
        if checkRemoteCmd() then return end
        sleep(1)
    end
end

function run()
    ui.drawDashboard()
    if state.resuming then
        ui.setStatus("Reanudando farmer")
        sleep(0.8)
    else
        ui.setStatus("Empezando farmer")
    end

    local sleepSecs = state.farmSleepSecs or 600

    while true do
        if checkRemoteCmd() then break end

        state.farmCycle = (state.farmCycle or 0) + 1
        ui.drawDashboard()
        ui.setStatus("Ciclo "..state.farmCycle)

        walkPlot()
        returnHome()
        dumpAtHome()
        persist.save()

        if checkRemoteCmd() then break end
        ui.setStatus("Esperando "..sleepSecs.."s")
        sleepInterruptible(sleepSecs)
    end

    if state.remoteCmd == "stop" then
        ui.setStatus("STOP farmer - checkpoint OK")
        persist.save()
        return
    end

    returnHome()
    dumpAtHome()
    persist.clear()
end
