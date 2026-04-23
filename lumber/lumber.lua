-- ============================================================
-- LUMBER MODULE
-- Tala de arboles con patron "side-row": la turtle camina por
-- un carril central y los arboles estan a UN LADO (o ambos).
-- Nunca pisa donde planta. Idea tomada del patron standard de
-- la comunidad CC (asciiAvenger/cc-tree-farm, FTB docs).
--
-- Dos modos:
--   - "grid":    N paradas en linea. En cada parada procesa
--                1 o 2 arboles a los lados (config rows=1 o 2).
--   - "single":  un solo arbol delante. Estacionario. Ideal
--                con bonemeal para acelerar crecimiento.
--
-- GEOMETRIA (grid, rows=2 ejemplo):
--     Z=+1:    T . T . T . T         <- row derecho (tree spots)
--     Z= 0:    @ . . . . . .         <- carril turtle (empieza en @)
--     Z=-1:    T . T . T . T         <- row izquierdo (si rows=2)
--              X=0 1 2 3 4 5 6
--     Cofre: (-1, 0, 0)
--
-- El turtle nunca camina sobre las posiciones de arbol (Z=+-1).
-- En cada parada: turnRight -> processTree -> turnLeft (volver a +X).
-- Si rows=2, despues: turnLeft -> processTree -> turnRight.
--
-- GEOMETRIA (single):
--   Turtle en (0,0,0) mirando el sapling en (1,0,0).
--   Cofre atras (-1,0,0). Bonemeal en slot si useBonemeal=true.
--
-- Requisitos de inventario:
--   - Saplings (spruce = mejor: tronco 1x1 sin ramas)
--   - Coal o charcoal para auto-refuel
--   - Bonemeal (opcional)
-- ============================================================

-- ============================================================
-- REMOTE COMMAND CHECK
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

local function notifyLog(name)
    if not state.hasRemote then return end
    pcall(remote.notifyEvent, "log", {
        name = name,
        count = state.logsHarvested or 0,
    })
end

-- ============================================================
-- TALADO DE TRONCO (1x1, spruce-friendly)
-- La turtle esta mirando un bloque de log. Cava, entra en la
-- columna, sube cavando mientras haya log encima, vuelve al
-- suelo y sale de la columna hacia atras. Queda en la posicion
-- de partida con el mismo facing.
-- ============================================================

local function chopTrunkInFront()
    ui.setStatus("Talando arbol")

    local ok, data = turtle.inspect()
    if not (ok and data and data.name and inventory.isLog(data.name)) then
        return false
    end

    local species = data.name
    turtle.dig()
    state.blocksMined = (state.blocksMined or 0) + 1
    state.logsHarvested = (state.logsHarvested or 0) + 1

    local entered = movement.safeForward()
    if not entered then return false end

    local climbed = 0
    while true do
        local okU, dU = turtle.inspectUp()
        if okU and dU and dU.name and inventory.isLog(dU.name) then
            turtle.digUp()
            state.blocksMined = state.blocksMined + 1
            state.logsHarvested = state.logsHarvested + 1
            if not movement.safeUp() then break end
            climbed = climbed + 1
        else
            break
        end
    end

    for _ = 1, climbed do
        if not movement.safeDown() then break end
    end

    -- Salir de la columna: dar la vuelta, avanzar 1, dar la vuelta
    movement.turnAround()
    movement.safeForward()
    movement.turnAround()

    notifyLog(species)
    return true
end

-- ============================================================
-- PLANTAR / BONEMEAL
-- ============================================================

local function plantSaplingInFront()
    local slot = inventory.selectSlotWith(inventory.isSapling)
    if not slot then return false end
    return turtle.place()
end

local function applyBonemealInFront()
    if not state.useBonemeal then return false end
    local slot = inventory.selectSlotWith(inventory.isBonemeal)
    if not slot then return false end
    local applied = false
    for _ = 1, 3 do
        if turtle.place() then applied = true else break end
    end
    return applied
end

-- ============================================================
-- PROCESSEAR UN TREE SPOT EN LA DIRECCION DADA
-- targetFacing: 0..3, direccion en la que hay un sapling/arbol
-- La turtle retorna al facing original.
-- ============================================================

local function processTreeAtSide(targetFacing, originalFacing)
    movement.faceDirection(targetFacing)

    local ok, data = turtle.inspect()
    if ok and data and data.name and inventory.isLog(data.name) then
        chopTrunkInFront()
        sleep(0.2)
        plantSaplingInFront()
        applyBonemealInFront()
    elseif not ok then
        -- Aire: plantar sapling
        plantSaplingInFront()
        applyBonemealInFront()
    else
        -- Hay un sapling joven u otra cosa
        if data and data.name and data.name:find("sapling") then
            applyBonemealInFront()
        end
    end

    movement.faceDirection(originalFacing)
end

-- ============================================================
-- NAVEGACION HOME
-- Suponemos que el turtle esta siempre en Z=0 (carril).
-- Volvemos en -X hasta x=0. Luego orientamos a +X.
-- ============================================================

local function returnHomeFromPos()
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
    movement.faceDirection(0)
end

local function dumpAtHome()
    ui.setStatus("Volcando logs")
    movement.faceDirection(2)
    inventory.dumpInto("forward")
    movement.faceDirection(0)
end

-- ============================================================
-- GRID PASS (side-row pattern)
-- ============================================================

local function gridPass()
    local count   = state.lumberCount or 4
    local spacing = state.lumberSpacing or 2
    local rows    = state.lumberRows or 2   -- 1 = solo derecha, 2 = ambos
    ui.drawDashboard()

    for i = 1, count do
        if checkRemoteCmd() then
            returnHomeFromPos()
            dumpAtHome()
            return false
        end
        ui.setStatus("Parada " .. i .. "/" .. count)

        -- Row derecho (+Z, facing 1)
        processTreeAtSide(1, 0)

        -- Row izquierdo (-Z, facing 3) si rows=2
        if rows >= 2 then
            processTreeAtSide(3, 0)
        end

        if inventory.isAlmostFull() then
            inventory.compact()
            if inventory.isAlmostFull() then
                ui.setStatus("Inventario lleno")
                break
            end
        end

        if i < count then
            for _ = 1, spacing do
                if not movement.safeForward() then
                    ui.setStatus("Camino bloqueado")
                    returnHomeFromPos()
                    dumpAtHome()
                    return false
                end
            end
        end

        persist.save()
    end

    returnHomeFromPos()
    dumpAtHome()
    return true
end

-- ============================================================
-- SINGLE PASS (estacionario, delante)
-- ============================================================

local function singlePass()
    ui.drawDashboard()
    ui.setStatus("Single tree")

    local ok, data = turtle.inspect()
    if ok and data and data.name and inventory.isLog(data.name) then
        chopTrunkInFront()
        sleep(0.2)
        plantSaplingInFront()
        applyBonemealInFront()
    elseif not ok then
        plantSaplingInFront()
        applyBonemealInFront()
    else
        if data and data.name and data.name:find("sapling") then
            applyBonemealInFront()
        end
    end

    if inventory.isAlmostFull() then
        dumpAtHome()
    end
    persist.save()
    return true
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
        ui.setStatus("Reanudando lumber")
        sleep(0.8)
    else
        ui.setStatus("Empezando lumber")
    end

    local sleepSecs = state.lumberSleepSecs or 120

    while true do
        if checkRemoteCmd() then break end

        if state.lumberMode == "single" then
            singlePass()
        else
            gridPass()
        end

        if checkRemoteCmd() then break end
        ui.setStatus("Esperando " .. sleepSecs .. "s")
        sleepInterruptible(sleepSecs)
    end

    if state.remoteCmd == "stop" then
        ui.setStatus("STOP lumber - checkpoint OK")
        persist.save()
        return
    end

    returnHomeFromPos()
    dumpAtHome()
    persist.clear()
end
