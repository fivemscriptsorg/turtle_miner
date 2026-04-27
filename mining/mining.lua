-- ============================================================
-- MINING MODULE
-- Logica de branch mining y tunnel mining.
-- Soporta tunnelWidth=1 (rapido 1x3) y tunnelWidth=3 (completo 3x3).
--
-- OPTIMIZACION: patron alternante. Tras cavar un lateral la turtle
-- NO vuelve al centro; cruza al lado opuesto y termina el slice en
-- ese lado. El slice siguiente arranca desde ese lado y vuelve al
-- opuesto. Solo se vuelve al centro al final del pass. Ahorra ~2
-- forwards por slice vs el patron centrado.
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
        if pet then pcall(pet.feedOre, data.name) end
        if state.hasRemote then
            pcall(remote.notifyEvent, "ore", { name = data.name, y = state.y })
            -- Coord del bloque del ore (relativa a posicion actual segun direccion)
            local orePos = { x = state.x, y = state.y, z = state.z }
            if direction == "up" then
                orePos.y = orePos.y + 1
            elseif direction == "down" then
                orePos.y = orePos.y - 1
            else
                -- frente: depende del facing
                if state.facing == 0 then orePos.x = orePos.x + 1
                elseif state.facing == 1 then orePos.z = orePos.z + 1
                elseif state.facing == 2 then orePos.x = orePos.x - 1
                elseif state.facing == 3 then orePos.z = orePos.z - 1
                end
            end
            pcall(swarm.broadcastOreSpotted, orePos, data.name)
            -- Lo vamos a cavar ahora mismo, asi que tambien lo anunciamos como gone
            pcall(swarm.broadcastOreGone, orePos)
        end
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
-- LANE TRACKING
-- sliceLane: offset lateral respecto a la centerline del pass actual.
--   0 = centro, -1 = izquierda, +1 = derecha (relativo a passFacing)
-- passFacing: direccion "adelante" del pass actual.
-- ============================================================

local function moveLaterally(diff)
    if diff == 0 then return true end
    local passF = state.passFacing
    local dirFacing = (diff > 0) and ((passF + 1) % 4) or ((passF + 3) % 4)
    movement.faceDirection(dirFacing)
    for _ = 1, math.abs(diff) do
        inspectAndLog("forward")
        digCounting(turtle.dig, turtle.detect)
        if not movement.safeForward() then
            return false
        end
    end
    state.sliceLane = (state.sliceLane or 0) + diff
    return true
end

local function returnToPassCenter()
    local lane = state.sliceLane or 0
    if lane ~= 0 then
        moveLaterally(-lane)
    end
    movement.faceDirection(state.passFacing)
    state.sliceLane = 0
end

-- ============================================================
-- CARVE FULL SLICE (alternante)
-- ============================================================

local function carveVerticalHere()
    inspectAndLog("up"); inspectAndLog("down")
    digCounting(turtle.digUp, turtle.detectUp)
    digCounting(turtle.digDown, turtle.detectDown)
end

local function carveFullSlice()
    local passF = state.passFacing

    -- Asegurarse de mirar hacia adelante antes de avanzar
    movement.faceDirection(passF)

    -- Avanzar en el lane actual: cavar f+u+d, mover, cavar u+d en la nueva pos
    inspectAndLog("forward")
    digCounting(turtle.dig, turtle.detect)
    digCounting(turtle.digUp, turtle.detectUp)
    digCounting(turtle.digDown, turtle.detectDown)
    sleep(0.15) -- grava/arena que caiga
    if turtle.detectUp() then turtle.digUp() end

    if not movement.safeForward() then return false end

    carveVerticalHere()

    if (state.tunnelWidth or 3) < 3 then return true end

    -- Visitar los otros 2 lanes en orden que termine alejado del de inicio
    local lane = state.sliceLane or 0
    local visits
    if lane == 0 then
        visits = { -1, 1 }      -- centro -> izq -> der (termina en der)
    elseif lane > 0 then
        visits = { 0, -1 }      -- der -> centro -> izq (termina en izq)
    else
        visits = { 0, 1 }       -- izq -> centro -> der (termina en der)
    end

    for _, targetLane in ipairs(visits) do
        local diff = targetLane - (state.sliceLane or 0)
        if not moveLaterally(diff) then
            return true -- lateral bloqueado; el avance del slice si se hizo
        end
        carveVerticalHere()
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
-- REMOTE COMMAND CHECK
-- Se llama en puntos seguros (entre slices / antes de ramas).
-- Devuelve true si hay que abortar el loop actual (home/stop).
-- Bloquea en pause hasta que cambie a resume/home/stop.
-- ============================================================

local function checkRemoteCmd()
    local cmd = state.remoteCmd
    if cmd == "pause" then
        ui.setStatus("PAUSADO - pulsa R para seguir")
        while state.remoteCmd == "pause" do
            sleep(0.3)
        end
        ui.setStatus("Reanudando")
        if state.remoteCmd == "resume" then
            state.remoteCmd = nil
        end
    end
    if state.remoteCmd == "home" or state.remoteCmd == "stop" then
        return true
    end
    return false
end

-- ============================================================
-- BRANCH
-- ============================================================

local function mineBranch(length)
    state.sliceLane = 0
    state.passFacing = state.facing

    local advanced = 0
    for i = 1, length do
        if checkRemoteCmd() then break end

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

    -- Centrar antes de volver para que el backtrack sea recto
    returnToPassCenter()

    ui.setStatus("Volviendo del ramal")
    movement.turnAround()
    for _ = 1, advanced do
        if not movement.safeForward() then break end
    end
    movement.turnAround()
end

-- ============================================================
-- BRANCH MINING
-- ============================================================

local function runBranchMining()
    -- En resume: respetar passFacing/sliceLane guardados. state.facing
    -- puede estar en lane lateral, asi que no sirve como facingStart.
    local facingStart
    if state.resuming and state.passFacing ~= nil then
        facingStart = state.passFacing
        state.sliceLane = state.sliceLane or 0
    else
        facingStart = state.facing
        state.sliceLane = 0
        state.passFacing = facingStart
    end

    local startStep = (state.currentStep or 0) + 1

    for step = startStep, state.shaftLength do
        if checkRemoteCmd() then break end
        state.currentStep = step

        ui.drawDashboard()
        ui.setStatus("Shaft "..step.."/"..state.shaftLength)
        geoHint()

        if step > 1 and (step % state.branchSpacing == 0) then
            -- Asegurarse de estar en el centro del shaft antes de ramificar
            returnToPassCenter()

            movement.turnLeft()
            ui.setStatus("Rama izquierda")
            mineBranch(state.branchLength)

            movement.turnAround()
            ui.setStatus("Rama derecha")
            mineBranch(state.branchLength)

            movement.turnLeft()
            movement.faceDirection(facingStart)

            -- Restaurar contexto del shaft
            state.passFacing = facingStart
            state.sliceLane = 0
        end

        if not carveFullSlice() then
            ui.setStatus("Shaft bloqueado")
            break
        end

        if inventory.isAlmostFull() then
            inventory.handleFullInventory()
        end

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

    returnToPassCenter()
end

-- ============================================================
-- TUNNEL SIMPLE
-- ============================================================

local function runTunnelMining()
    if state.resuming and state.passFacing ~= nil then
        state.sliceLane = state.sliceLane or 0
    else
        state.sliceLane = 0
        state.passFacing = state.facing
    end

    local startStep = (state.currentStep or 0) + 1

    for step = startStep, state.shaftLength do
        if checkRemoteCmd() then break end
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

    returnToPassCenter()
end

-- ============================================================
-- RETURN TO START
-- ============================================================

local function returnToStart()
    ui.setStatus("Volviendo al inicio")
    movement.faceDirection(2)
    while state.x > 0 do
        if not movement.safeForward() then break end
    end
    while state.z ~= 0 do
        if state.z > 0 then
            movement.faceDirection(3)
        else
            movement.faceDirection(1)
        end
        if not movement.safeForward() then break end
    end
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
    state.resuming = false

    -- Comando "stop" remoto: guarda checkpoint y termina sin volver
    if state.remoteCmd == "stop" then
        ui.setStatus("STOP remoto - checkpoint OK")
        persist.save()
        return
    end

    returnToStart()
    persist.clear()
end
