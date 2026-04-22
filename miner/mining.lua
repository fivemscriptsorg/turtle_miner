-- ============================================================
-- MINING MODULE
-- Logica de branch mining y tunnel mining.
-- Soporta tunnelWidth=1 (rapido 1x3) y tunnelWidth=3 (completo 3x3).
-- ============================================================

-- ============================================================
-- INSPECCION Y TRACKING DE ORES
-- ============================================================

local function inspectAndLog(direction)
    local inspectFn = turtle.inspect
    if direction == "up" then inspectFn = turtle.inspectUp
    elseif direction == "down" then inspectFn = turtle.inspectDown end

    local ok, data = inspectFn()
    if ok and data and inventory.isOre(data.name) then
        state.oresFound = state.oresFound + 1
        ui.logOre(data.name, state.y)
        return true
    end
    return false
end

local function digCounting(fn, detectFn)
    if detectFn() then
        fn()
        state.blocksMined = state.blocksMined + 1
        return true
    end
    return false
end

-- ============================================================
-- CARVE FULL SLICE
-- Mina un slice completo del tunel y avanza la turtle un bloque.
-- Si tunnelWidth=3: carva las 3 columnas (9 bloques por slice).
-- Si tunnelWidth=1: solo la columna central (3 bloques por slice).
--
-- IMPORTANTE: turtle.digUp/digDown/inspectUp son facing-independent,
-- siempre operan sobre el bloque directamente encima/debajo de la
-- turtle. Por eso para cavar las esquinas laterales hay que mover
-- fisicamente la turtle a la columna lateral.
-- ============================================================

local function carveCurrentColumnVertical()
    -- Cava arriba y abajo de la posicion actual (inspecciona y cuenta ores)
    inspectAndLog("up")
    inspectAndLog("down")
    digCounting(turtle.digUp, turtle.detectUp)
    digCounting(turtle.digDown, turtle.detectDown)
end

local function carveSideColumn(turnFn)
    -- Asume turtle en columna central, facing forward.
    -- Gira, avanza al lateral, cava up+down, vuelve al centro, re-alinea.
    local f0 = state.facing
    turnFn()
    inspectAndLog("forward")
    digCounting(turtle.dig, turtle.detect)
    if not movement.safeForward() then
        movement.faceDirection(f0)
        return false
    end
    carveCurrentColumnVertical()
    movement.turnAround()
    if not movement.safeForward() then
        -- algo raro: no podemos volver. re-alineamos de todos modos
        movement.faceDirection(f0)
        return false
    end
    movement.faceDirection(f0)
    return true
end

local function carveFullSlice()
    -- Cava techo+suelo de la columna central actual
    inspectAndLog("forward")
    carveCurrentColumnVertical()
    digCounting(turtle.dig, turtle.detect)

    -- Pausa breve por grava/arena que caiga
    sleep(0.15)
    if turtle.detectUp() then turtle.digUp() end

    -- Avanzar al nuevo slice
    if not movement.safeForward() then return false end

    -- Cavar techo+suelo del nuevo centro
    carveCurrentColumnVertical()

    -- Si el tunel es ancho, cavar laterales
    local width = state.tunnelWidth or 3
    if width >= 3 then
        carveSideColumn(movement.turnLeft)
        carveSideColumn(movement.turnRight)
    end

    return true
end

-- ============================================================
-- GEO SCANNER HINT
-- ============================================================

local function geoHint()
    if not state.hasGeoScanner then return end
    local ore = peripherals.nearestOre(8)
    if ore then
        local short = (ore.name or "?"):gsub("minecraft:", "")
        ui.setStatus("Ore cerca: " .. short)
    end
end

-- ============================================================
-- BRANCH
-- Una rama de `length` bloques y vuelta al origen.
-- Trackea los pasos realmente avanzados para no pasarse al volver.
-- ============================================================

local function mineBranch(length)
    local advanced = 0
    for i = 1, length do
        ui.drawDashboard()
        ui.setStatus("Rama "..i.."/"..length)
        geoHint()

        if not carveFullSlice() then
            ui.setStatus("Rama bloqueada")
            break
        end
        advanced = advanced + 1

        if inventory.isAlmostFull() then
            inventory.handleFullInventory()
        end
    end

    -- Volver exactamente los pasos avanzados
    ui.setStatus("Volviendo del ramal")
    movement.turnAround()
    for _ = 1, advanced do
        if not movement.safeForward() then break end
    end
    movement.turnAround()
end

-- ============================================================
-- BRANCH MINING (shaft principal + ramas)
-- ============================================================

local function runBranchMining()
    local facingStart = state.facing
    local startStep = (state.currentStep or 0) + 1

    for step = startStep, state.shaftLength do
        state.currentStep = step

        ui.drawDashboard()
        ui.setStatus("Shaft "..step.."/"..state.shaftLength)
        geoHint()

        -- cada branchSpacing bloques, hacer ramas (step>1 para no cavar en la entrada)
        if step > 1 and (step % state.branchSpacing == 0) then
            movement.turnLeft()
            ui.setStatus("Rama izquierda")
            mineBranch(state.branchLength)
            movement.turnAround()
            ui.setStatus("Rama derecha")
            mineBranch(state.branchLength)
            movement.turnLeft()
            movement.faceDirection(facingStart)
        end

        if not carveFullSlice() then
            ui.setStatus("Shaft bloqueado")
            break
        end

        if inventory.isAlmostFull() then
            inventory.handleFullInventory()
        end

        -- fuel proactivo: necesitamos poder volver
        local fuel = turtle.getFuelLevel()
        if fuel ~= "unlimited" then
            local needed = math.abs(state.x) + 10
            if fuel < needed and not inventory.autoRefuel(needed) then
                ui.setStatus("Fuel critico, volviendo")
                break
            end
        end

        persist.save()
    end
end

-- ============================================================
-- TUNNEL SIMPLE (sin ramas)
-- ============================================================

local function runTunnelMining()
    local startStep = (state.currentStep or 0) + 1

    for step = startStep, state.shaftLength do
        state.currentStep = step

        ui.drawDashboard()
        ui.setStatus("Tunel "..step.."/"..state.shaftLength)
        geoHint()

        if not carveFullSlice() then
            ui.setStatus("Bloqueado")
            break
        end

        if inventory.isAlmostFull() then
            inventory.handleFullInventory()
        end

        persist.save()
    end
end

-- ============================================================
-- RETURN TO START
-- ============================================================

local function returnToStart()
    ui.setStatus("Volviendo al inicio")
    -- girar hacia -X para volver
    movement.faceDirection(2)
    while state.x > 0 do
        if not movement.safeForward() then break end
    end
    -- alinear Z si quedo descentrado
    while state.z ~= 0 do
        if state.z > 0 then
            movement.faceDirection(3)
        else
            movement.faceDirection(1)
        end
        if not movement.safeForward() then break end
    end
    -- dejar mirando hacia el tunel
    movement.faceDirection(0)

    if inventory.slotsUsed() > 0 then
        ui.setStatus("Cofre final")
        inventory.placeChest()
    end
end

-- ============================================================
-- ENTRY POINT
-- ============================================================

function run()
    ui.drawDashboard()

    if state.resuming then
        ui.setStatus("Reanudando sesion...")
        sleep(1)
    else
        ui.setStatus("Empezando mineria")
    end

    if state.hasEnvDetector and peripherals.isDangerousBiome() then
        ui.setStatus("AVISO: bioma peligroso")
        sleep(1.5)
    end

    if state.pattern == "branch" then
        runBranchMining()
    else
        runTunnelMining()
    end

    returnToStart()

    -- limpiar checkpoint al terminar limpiamente
    persist.clear()
end
