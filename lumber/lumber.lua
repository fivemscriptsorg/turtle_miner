-- ============================================================
-- LUMBER MODULE
-- Tala de arboles. Dos modos:
--   - "grid": linea de N arboles espaciados. La turtle recorre,
--     tala los maduros, replanta saplings y vuelve a casa a
--     volcar logs. Duerme X segundos y repite.
--   - "single": un solo arbol delante. Opcionalmente aplica
--     bonemeal para acelerar el crecimiento.
--
-- GEOMETRIA ASUMIDA (grid):
--   Posicion casa = (0,0,0) mirando +X.
--   Tree spot i en x = (i-1)*spacing + 1  (i=1..count).
--   La turtle descansa en x=(i-1)*spacing entre arboles.
--   Cofre de descarga atras, en (-1, 0, 0).
--
-- GEOMETRIA ASUMIDA (single):
--   Turtle en (0,0,0) mirando el sapling en (1,0,0).
--   Cofre atras en (-1,0,0). Bonemeal en slot si useBonemeal=true.
--
-- Requisitos de inventario:
--   - Saplings (cualquier tipo; spruce = mejor por tronco 1x1)
--   - Coal o charcoal para auto-refuel
--   - Bonemeal (opcional)
-- ============================================================

-- ============================================================
-- INSPECCION
-- ============================================================

local function inspectIsLog(inspectFn)
    local ok, data = inspectFn()
    if ok and data and data.name and inventory.isLog(data.name) then
        return true, data
    end
    return false, data
end

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
-- TALADO DE TRONCO
-- La turtle esta mirando un log (x+1). Cavar log base, entrar en
-- su columna, subir cavando mientras haya log encima, volver al
-- suelo y salir de la columna hacia atras. Funciona para arboles
-- de tronco 1x1 (spruce es el ideal); si el arbol ramifica, para
-- al primer bloque no-log y las hojas se dejan que despawneen.
-- ============================================================

local function chopTrunkInFront()
    ui.setStatus("Talando arbol")

    local isLog, data = inspectIsLog(turtle.inspect)
    if not isLog then return false end

    local species = data and data.name or "unknown"
    turtle.dig()
    state.blocksMined = (state.blocksMined or 0) + 1
    state.logsHarvested = (state.logsHarvested or 0) + 1
    if not movement.safeForward() then
        -- no pudimos entrar; intentar un step atras para no dejar la turtle atorada
        return false
    end

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

    -- Volver al suelo
    for _ = 1, climbed do
        if not movement.safeDown() then break end
    end

    -- Salir del hueco hacia atras (respecto al arbol)
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

-- Procesa el tree spot que hay delante. Devuelve true si talo.
local function processTreeFront()
    local ok, data = turtle.inspect()

    if ok and data and data.name and inventory.isLog(data.name) then
        chopTrunkInFront()
        sleep(0.3) -- que se caigan las leaves
        plantSaplingInFront()
        applyBonemealInFront()
        return true
    end

    if not ok then
        -- Aire: intentar plantar
        plantSaplingInFront()
        applyBonemealInFront()
        return false
    end

    -- Hay un bloque (probablemente sapling creciendo). Solo bonemeal.
    if data and data.name and data.name:find("sapling") then
        applyBonemealInFront()
    end
    return false
end

-- ============================================================
-- NAVEGACION (GRID)
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
-- PASADA GRID / SINGLE
-- ============================================================

local function gridPass()
    local count = state.lumberCount or 4
    local spacing = state.lumberSpacing or 2
    ui.drawDashboard()

    for i = 1, count do
        if checkRemoteCmd() then
            returnHomeFromPos()
            dumpAtHome()
            return false
        end
        ui.setStatus("Arbol "..i.."/"..count)

        processTreeFront()

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

local function singlePass()
    ui.drawDashboard()
    ui.setStatus("Single tree")
    processTreeFront()
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
        ui.setStatus("Esperando "..sleepSecs.."s")
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
