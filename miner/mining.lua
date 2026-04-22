-- ============================================================
-- MINING MODULE
-- Logica de branch mining y tunnel mining 3x3.
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

-- ============================================================
-- DIG 3x3
-- La turtle se mueve en la fila central (y=0 relativo al suelo del tunel).
-- Para cada bloque de avance: cava adelante, arriba y abajo.
-- Luego sube una vez y cava arriba otra vez para hacerlo 3 de alto.
-- Para hacerlo 3 de ancho, en cada paso cavamos la pared izquierda y derecha tambien.
-- ============================================================

-- Minar el cubo 3x3 ALREDEDOR de la posicion actual (sin avanzar).
-- Asume que la turtle esta en la columna central, fila del medio.
local function mine3x3Slice()
    -- Inspeccionar antes de cavar (para loguear ores)
    inspectAndLog("forward")
    inspectAndLog("up")
    inspectAndLog("down")

    -- cavar frente, arriba, abajo
    if turtle.detect() then
        turtle.dig()
        state.blocksMined = state.blocksMined + 1
    end
    if turtle.detectUp() then
        turtle.digUp()
        state.blocksMined = state.blocksMined + 1
    end
    if turtle.detectDown() then
        turtle.digDown()
        state.blocksMined = state.blocksMined + 1
    end

    -- pequena pausa para grava/arena que cae
    sleep(0.1)
    if turtle.detectUp() then turtle.digUp() end
end

-- Mina un paso del tunel 3x3 y avanza.
-- Patron optimizado: la turtle va en el medio-inferior, sube una vez para cubrir
-- el medio-superior, vuelve a bajar. Izquierda y derecha se cubren al costado.
local function tunnelStep()
    -- Nivel central: minar frente + arriba + abajo
    mine3x3Slice()

    -- Avanzar
    if not movement.safeForward() then
        return false
    end

    -- Despues de avanzar, la siguiente slice se mina en el proximo tunnelStep().
    -- Para cubrir el 3x3 completo, chequear paredes laterales:
    -- giramos, cavamos, volvemos. Esto extiende el tunel a 3 de ancho.
    movement.turnLeft()
    inspectAndLog("forward")
    if turtle.detect() then
        turtle.dig()
        state.blocksMined = state.blocksMined + 1
    end
    inspectAndLog("up")
    if turtle.detectUp() then
        turtle.digUp()
        state.blocksMined = state.blocksMined + 1
    end
    movement.turnRight() -- volver al frente

    movement.turnRight()
    inspectAndLog("forward")
    if turtle.detect() then
        turtle.dig()
        state.blocksMined = state.blocksMined + 1
    end
    inspectAndLog("up")
    if turtle.detectUp() then
        turtle.digUp()
        state.blocksMined = state.blocksMined + 1
    end
    movement.turnLeft() -- volver al frente

    return true
end

-- ============================================================
-- GEO SCANNER HINT
-- Usa el geo scanner (si esta) para decidir si vale la pena seguir.
-- Si detecta un ore muy cerca, muestra un hint en el status.
-- ============================================================

local function geoHint()
    if not state.hasGeoScanner then return end
    local ore, dist = peripherals.nearestOre(8)
    if ore then
        ui.setStatus("Ore cerca: " .. (ore.name or "?"):gsub("minecraft:", ""))
    end
end

-- ============================================================
-- BRANCH MINING
-- Patron: tunel principal largo, y cada `branchSpacing` bloques
-- salen dos ramas (izquierda y derecha) de `branchLength` bloques.
-- ============================================================

-- Mina una rama de X bloques en la direccion actual y vuelve al origen.
local function mineBranch(length)
    for i = 1, length do
        ui.drawDashboard()
        ui.setStatus("Rama "..i.."/"..length)
        geoHint()

        if not tunnelStep() then
            ui.setStatus("Bloqueado en rama")
            break
        end

        if inventory.isAlmostFull() then
            inventory.handleFullInventory()
        end
    end

    -- Volver al origen de la rama
    ui.setStatus("Volviendo del ramal")
    movement.turnAround()
    for i = 1, length do
        movement.safeForward()
    end
    movement.turnAround()
end

local function runBranchMining()
    local facingStart = state.facing

    for step = 1, state.shaftLength do
        ui.drawDashboard()
        ui.setStatus("Shaft "..step.."/"..state.shaftLength)
        geoHint()

        -- cada branchSpacing bloques, hacer ramas
        if step > 1 and (step % state.branchSpacing == 0) then
            -- rama izquierda
            movement.turnLeft()
            ui.setStatus("Rama izquierda")
            mineBranch(state.branchLength)
            -- rama derecha
            movement.turnAround() -- ahora miramos derecha relativo al shaft
            ui.setStatus("Rama derecha")
            mineBranch(state.branchLength)
            -- volver a mirar hacia adelante del shaft
            movement.turnLeft()
            movement.faceDirection(facingStart)
        end

        -- avanzar por el shaft
        if not tunnelStep() then
            ui.setStatus("Shaft bloqueado")
            break
        end

        if inventory.isAlmostFull() then
            inventory.handleFullInventory()
        end

        -- chequeo de fuel proactivo para volver
        local fuel = turtle.getFuelLevel()
        if fuel ~= "unlimited" then
            local needed = state.x + 10
            if fuel < needed and not inventory.autoRefuel(needed) then
                ui.setStatus("Fuel critico, volviendo")
                break
            end
        end
    end
end

-- ============================================================
-- TUNNEL SIMPLE (sin ramas)
-- ============================================================

local function runTunnelMining()
    for step = 1, state.shaftLength do
        ui.drawDashboard()
        ui.setStatus("Tunel "..step.."/"..state.shaftLength)
        geoHint()

        if not tunnelStep() then
            ui.setStatus("Bloqueado")
            break
        end

        if inventory.isAlmostFull() then
            inventory.handleFullInventory()
        end
    end
end

-- ============================================================
-- RETURN TO START
-- ============================================================

local function returnToStart()
    ui.setStatus("Volviendo al inicio")
    -- girar hacia -X
    movement.faceDirection(2)
    while state.x > 0 do
        if not movement.safeForward() then break end
    end
    -- alinear X si quedo descentrado
    while state.z ~= 0 do
        if state.z > 0 then
            movement.faceDirection(3)
        else
            movement.faceDirection(1)
        end
        if not movement.safeForward() then break end
    end
    -- dejar mirando el tunel
    movement.faceDirection(0)

    -- dejar cofre final con todo lo recolectado
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
    ui.setStatus("Empezando mineria")

    -- Aviso temprano si estamos en bioma peligroso
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
end
