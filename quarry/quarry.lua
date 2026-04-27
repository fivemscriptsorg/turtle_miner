-- ============================================================
-- QUARRY MODULE
-- Excava un rectangulo W x L top-down. Cuando el inventario se
-- llena, coloca un cofre normal arriba (placeUp), dropea, y deja
-- el cofre flotando ahi (no recovery). Anota la posicion en
-- state.dropChests y sigue minando.
--
-- Al terminar el quarry: fase LIFT. Visita cada cofre subterraneo
-- (de arriba abajo), succiona su contenido, recupera el cofre con
-- digUp (vanilla chest se dropea entero, sin silk touch).
--
-- Si el inventario se llena durante el lift: fase CONSOLIDATE.
-- Sube a superficie, coloca filas de 2 cofres dobles apilados
-- (4 cofres por fila) en linea -X desde el origen, con 1 bloque
-- de gap entre filas. El jugador encuentra el botin en superficie.
--
-- Sin slots reservados. Cofres y fuel se buscan dinamicamente
-- (isChest cubre chest+trapped_chest, isFuel cubre coal+charcoal+
-- coal_block).
--
-- Si la turtle se queda sin cofres o sin fuel: fase RESUPPLY.
-- Vuelve a (0,0,0), espera a que el jugador rellene y pulse R.
-- Al reanudar, refuel al maximo posible y vuelve a su posicion.
-- ============================================================

-- ============================================================
-- ORE TRACKING (copia de mining/mining.lua para no acoplar)
-- ============================================================

local function inspectAndLog(direction)
    local inspectFn = turtle.inspect
    if direction == "up" then inspectFn = turtle.inspectUp
    elseif direction == "down" then inspectFn = turtle.inspectDown end

    local ok, data = inspectFn()
    if ok and data and inventory.isOre(data.name) then
        state.oresFound = state.oresFound + 1
        ui.logOre(data.name, state.y)
        if state.hasRemote then
            pcall(remote.notifyEvent, "ore", { name = data.name, y = state.y })
            local orePos = { x = state.x, y = state.y, z = state.z }
            if direction == "up" then orePos.y = orePos.y + 1
            elseif direction == "down" then orePos.y = orePos.y - 1
            else
                if state.facing == 0 then orePos.x = orePos.x + 1
                elseif state.facing == 1 then orePos.z = orePos.z + 1
                elseif state.facing == 2 then orePos.x = orePos.x - 1
                elseif state.facing == 3 then orePos.z = orePos.z - 1 end
            end
            pcall(swarm.broadcastOreSpotted, orePos, data.name)
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
-- REMOTE / RESUME CONTROL
-- ============================================================

local function checkRemoteCmd()
    local cmd = state.remoteCmd
    if cmd == "pause" then
        ui.setStatus("PAUSADO - pulsa R para seguir")
        while state.remoteCmd == "pause" do sleep(0.3) end
        ui.setStatus("Reanudando")
        if state.remoteCmd == "resume" then state.remoteCmd = nil end
    end
    if state.remoteCmd == "home" or state.remoteCmd == "stop" then return true end
    return false
end

local function waitForResume()
    while state.remoteCmd ~= "resume"
        and state.remoteCmd ~= "home"
        and state.remoteCmd ~= "stop" do
        sleep(0.3)
    end
    if state.remoteCmd == "resume" then state.remoteCmd = nil end
end

-- ============================================================
-- BEDROCK / MINE CELL
-- ============================================================

local function isBedrock(name) return name == "minecraft:bedrock" end

local function mineCellDown()
    inspectAndLog("down")
    local ok, data = turtle.inspectDown()
    if ok and data and isBedrock(data.name) then return "bedrock" end
    if not turtle.detectDown() then return "ok" end
    digCounting(turtle.digDown, turtle.detectDown)
    for _ = 1, 3 do
        if not turtle.detectDown() then return "ok" end
        digCounting(turtle.digDown, turtle.detectDown)
        sleep(0.15)
    end
    if turtle.detectDown() then return "blocked" end
    return "ok"
end

-- ============================================================
-- NAVIGATION
-- Manhattan: Y first, then X, then Z. Funciona dentro del volumen
-- minado (todo aire), y por encima del quarry (aire o terreno
-- que safe* digiere automaticamente).
-- ============================================================

local function ascendToY(targetY)
    while state.y < targetY do
        if not movement.safeUp() then return false end
    end
    return true
end

local function descendToY(targetY)
    while state.y > targetY do
        if not movement.safeDown() then return false end
    end
    return true
end

local function moveToX(targetX)
    if state.x == targetX then return true end
    movement.faceDirection(state.x < targetX and 0 or 2)
    while state.x ~= targetX do
        if not movement.safeForward() then return false end
    end
    return true
end

local function moveToZ(targetZ)
    if state.z == targetZ then return true end
    movement.faceDirection(state.z < targetZ and 1 or 3)
    while state.z ~= targetZ do
        if not movement.safeForward() then return false end
    end
    return true
end

local function navigateTo(tx, ty, tz)
    if state.y < ty then ascendToY(ty)
    elseif state.y > ty then descendToY(ty) end
    moveToX(tx)
    moveToZ(tz)
end

-- ============================================================
-- INVENTORY: BUSCAR COFRE / FUEL DINAMICAMENTE
-- ============================================================

local function findAnyChestSlot()
    return inventory.findSlot(inventory.isChest)
end

-- Dropea slots con items que no sean cofres ni fuel
local function dropAllNonReserved(dropFn)
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and not inventory.isChest(d.name) and not inventory.isFuel(d.name) then
            turtle.select(i)
            dropFn()
        end
    end
end

local function hasNonReservedItems()
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and not inventory.isChest(d.name) and not inventory.isFuel(d.name) then
            return true
        end
    end
    return false
end

-- ============================================================
-- DUMP DURING MINING
-- placeUp un cofre vanilla, dropea slots no reservados, deja el
-- cofre flotando arriba. Anota la pos en state.dropChests.
-- Devuelve true | "no_chest" | false
-- ============================================================

local function placeWallChest()
    inventory.compact()
    inventory.dropJunk()
    if inventory.slotsUsed() < (state.dumpThreshold or 13) then return true end

    local slot = findAnyChestSlot()
    if not slot then return "no_chest" end

    if turtle.detectUp() then
        digCounting(turtle.digUp, turtle.detectUp)
        sleep(0.15)
        if turtle.detectUp() then digCounting(turtle.digUp, turtle.detectUp) end
    end

    local prev = turtle.getSelectedSlot()
    turtle.select(slot)
    local placed = turtle.placeUp()
    if not placed then
        sleep(0.3)
        if turtle.detectUp() then digCounting(turtle.digUp, turtle.detectUp) end
        placed = turtle.placeUp()
    end
    if not placed then
        turtle.select(prev)
        return false
    end

    state.dropChests = state.dropChests or {}
    table.insert(state.dropChests, { x = state.x, y = state.y + 1, z = state.z })
    state.chestsPlaced = (state.chestsPlaced or 0) + 1

    dropAllNonReserved(turtle.dropUp)
    turtle.select(prev)
    return true
end

-- ============================================================
-- RESUPPLY (fallback C)
-- Vuelve a (0,0,0), espera, recarga al maximo, vuelve.
-- ============================================================

local function navigateHome()
    while state.y < 0 do
        if not movement.safeUp() then break end
    end
    if state.x ~= 0 then
        movement.faceDirection(state.x > 0 and 2 or 0)
        while state.x ~= 0 do
            if not movement.safeForward() then break end
        end
    end
    if state.z ~= 0 then
        movement.faceDirection(state.z > 0 and 3 or 1)
        while state.z ~= 0 do
            if not movement.safeForward() then break end
        end
    end
    movement.faceDirection(0)
end

local function awaitResupply(why)
    state.resupplyReturn = {
        x = state.x, y = state.y, z = state.z, facing = state.facing,
    }
    persist.save()

    ui.setStatus("Vuelvo: " .. (why or "sin recursos"))
    navigateHome()

    state.awaitingResupply = true
    persist.save()

    ui.setStatus("Sin recursos - rellena y pulsa R")
    waitForResume()
    state.awaitingResupply = false

    -- Refuel al maximo posible
    local fuelLimit = turtle.getFuelLimit()
    if fuelLimit ~= "unlimited" and fuelLimit and fuelLimit > 0 then
        inventory.autoRefuel(fuelLimit)
    end

    if state.resupplyReturn then
        local r = state.resupplyReturn
        navigateTo(r.x, r.y, r.z)
        movement.faceDirection(r.facing)
        state.resupplyReturn = nil
    end
    persist.save()
end

local function dumpOrResupply()
    while true do
        local r = placeWallChest()
        if r == true then return true end
        if r == "no_chest" then
            awaitResupply("sin cofres")
        else
            return false
        end
    end
end

-- ============================================================
-- SNAKE LAYER
-- ============================================================

local function faceLength(dir) movement.faceDirection(dir > 0 and 0 or 2) end
local function faceWidth(dir)  movement.faceDirection(dir > 0 and 1 or 3) end

local function tryStepForward()
    inspectAndLog("forward")
    digCounting(turtle.dig, turtle.detect)
    return movement.safeForward()
end

local function checkFuelOrResupply()
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then return end
    -- Reserva: poder volver a (0,0,0) + colchon
    local needed = math.abs(state.x) + math.abs(state.z) + math.abs(state.y) + 30
    if fuel >= needed then return end
    inventory.autoRefuel(needed)
    if turtle.getFuelLevel() < needed then
        awaitResupply("fuel critico")
    end
end

local function mineLayer(W, L)
    local rowDir = state.quarryRowDir or 1
    local colDir = state.quarryDirection or 1
    state.quarryRowDir = rowDir
    state.quarryDirection = colDir

    local row = state.quarryRow or 0
    local col = state.quarryCol or 0

    while row >= 0 and row < W do
        state.quarryRow = row
        state.quarryDirection = colDir

        while col >= 0 and col < L do
            if checkRemoteCmd() then return "interrupt" end
            state.quarryCol = col

            local r = mineCellDown()
            if r == "bedrock" then
                state.quarryDone = true
                return "bedrock"
            end

            if inventory.slotsUsed() >= (state.dumpThreshold or 13) then
                dumpOrResupply()
            end

            checkFuelOrResupply()
            persist.save()

            local nextCol = col + colDir
            local atRowEnd = (colDir > 0 and nextCol >= L) or (colDir < 0 and nextCol < 0)
            if atRowEnd then break end

            faceLength(colDir)
            if not tryStepForward() then
                ui.setStatus("Columna bloqueada")
                break
            end
            col = nextCol
        end

        local nextRow = row + rowDir
        local atLastRow = (rowDir > 0 and nextRow >= W) or (rowDir < 0 and nextRow < 0)
        if atLastRow then break end

        faceWidth(rowDir)
        if not tryStepForward() then
            ui.setStatus("Lateral bloqueado")
            break
        end

        row = nextRow
        colDir = -colDir
        state.quarryRow = row
        state.quarryDirection = colDir
    end

    state.quarryRow = row
    state.quarryCol = col
    return "done"
end

local function descendOne()
    local ok, data = turtle.inspectDown()
    if ok and data and isBedrock(data.name) then
        state.quarryDone = true
        return false
    end
    if not movement.safeDown() then return false end
    state.quarryLayer = (state.quarryLayer or 0) + 1
    -- La capa anterior termino en una esquina con colDir y rowDir
    -- apuntando "hacia afuera" del rectangulo. Al snake-back-ear
    -- la siguiente capa hay que flipear AMBAS direcciones, no solo
    -- rowDir, sino la primera fila de la nueva capa solo mina UNA
    -- celda antes de detectar rowEnd y saltar a la siguiente fila.
    state.quarryRowDir    = -(state.quarryRowDir or 1)
    state.quarryDirection = -(state.quarryDirection or 1)
    return true
end

-- ============================================================
-- MINING PHASE
-- ============================================================

local function runMine()
    local W = state.quarryWidth or 8
    local L = state.quarryLength or 8
    local maxDepth = state.quarryMaxDepth or 64

    if not state.resuming then
        state.quarryRow = 0
        state.quarryCol = 0
        state.quarryDirection = 1
        state.quarryRowDir = 1
        state.quarryLayer = 0
        state.quarryDone = false
        state.dropChests = {}
        state.surfaceFila = 0
        state.surfaceTargetIdx = 1
    end
    state.quarryPhase = "mine"

    while not state.quarryDone do
        if checkRemoteCmd() then return "interrupt" end

        ui.drawDashboard()
        ui.setStatus(string.format("Capa %d  fila %d/%d  col %d/%d",
            state.quarryLayer or 0, (state.quarryRow or 0) + 1, W,
            (state.quarryCol or 0) + 1, L))

        local r = mineLayer(W, L)
        if r == "interrupt" then return "interrupt" end
        if r == "bedrock" then break end

        if maxDepth > 0 and (state.quarryLayer or 0) + 1 >= maxDepth then
            state.quarryDone = true
            break
        end
        if not descendOne() then break end
    end

    state.quarryPhase = "lift"
    persist.save()
    return "done"
end

-- ============================================================
-- SURFACE CONSOLIDATION
-- 4 targets per fila, 1-block lateral gap entre filas.
-- ============================================================

-- forward decl para que liftProtocol pueda llamar
local consolidateOnSurface

local function surfaceTarget(filaIdx, targetIdx)
    local baseZ = filaIdx * 3
    if     targetIdx == 1 then return { x = 0, y = 0, z = baseZ,     face = 2 }
    elseif targetIdx == 2 then return { x = 0, y = 0, z = baseZ + 1, face = 2 }
    elseif targetIdx == 3 then return { x = 0, y = 1, z = baseZ + 1, face = 2 }
    elseif targetIdx == 4 then return { x = 0, y = 1, z = baseZ,     face = 2 }
    end
    return nil
end

-- Coloca un cofre en target si no hay ya uno, y dropea slots no reservados.
local function consolidateAtTarget(target)
    navigateTo(target.x, target.y, target.z)
    movement.faceDirection(target.face)

    if turtle.detect() then
        local ok, data = turtle.inspect()
        if ok and data and not inventory.isChest(data.name) then
            -- Terreno (tierra/hierba/etc): cavar y colocar
            digCounting(turtle.dig, turtle.detect)
            sleep(0.15)
            local cs = findAnyChestSlot()
            if not cs then return "no_chest" end
            local prev = turtle.getSelectedSlot()
            turtle.select(cs)
            if not turtle.place() then
                turtle.select(prev)
                return "place_failed"
            end
            turtle.select(prev)
        end
        -- si ya es un cofre, perfecto, dropeamos directo
    else
        -- aire: colocar cofre nuevo
        local cs = findAnyChestSlot()
        if not cs then return "no_chest" end
        local prev = turtle.getSelectedSlot()
        turtle.select(cs)
        if not turtle.place() then
            turtle.select(prev)
            return "place_failed"
        end
        turtle.select(prev)
    end

    dropAllNonReserved(turtle.drop)
    return "ok"
end

consolidateOnSurface = function()
    state.surfaceFila      = state.surfaceFila or 0
    state.surfaceTargetIdx = state.surfaceTargetIdx or 1

    while hasNonReservedItems() do
        if checkRemoteCmd() then return "interrupt" end

        local target = surfaceTarget(state.surfaceFila, state.surfaceTargetIdx)
        if not target then break end

        ui.drawDashboard()
        ui.setStatus(string.format("Conso fila %d t%d  slots %d",
            state.surfaceFila, state.surfaceTargetIdx, inventory.slotsUsed()))

        local r = consolidateAtTarget(target)
        if r == "no_chest" then
            awaitResupply("sin cofres en superficie")
            -- no avanzamos targetIdx; reintentamos
        elseif r == "place_failed" then
            -- avanzamos para no atascarnos
            state.surfaceTargetIdx = state.surfaceTargetIdx + 1
        else
            state.surfaceTargetIdx = state.surfaceTargetIdx + 1
        end

        if state.surfaceTargetIdx > 4 then
            state.surfaceFila      = state.surfaceFila + 1
            state.surfaceTargetIdx = 1
        end

        persist.save()
    end

    return "done"
end

-- ============================================================
-- LIFT PROTOCOL
-- Visita cada cofre subterraneo, succiona, recupera el cofre.
-- ============================================================

local function liftProtocol()
    state.dropChests = state.dropChests or {}
    -- Mas superficiales primero (Y mayor)
    table.sort(state.dropChests, function(a, b) return a.y > b.y end)

    local total = #state.dropChests

    while #state.dropChests > 0 do
        if checkRemoteCmd() then return "interrupt" end

        local target = state.dropChests[1]
        local doneCount = total - #state.dropChests + 1

        ui.drawDashboard()
        ui.setStatus(string.format("Lift %d/%d  (%d,%d,%d)",
            doneCount, total, target.x, target.y, target.z))

        -- Posicion de succion: directamente DEBAJO del cofre
        navigateTo(target.x, target.y - 1, target.z)

        for _ = 1, 64 do
            if not turtle.suckUp() then break end
        end

        -- Recuperar el cofre vanilla (digUp lo dropea como item)
        for _ = 1, 3 do
            if turtle.digUp() then break end
            sleep(0.2)
        end

        table.remove(state.dropChests, 1)
        persist.save()

        if inventory.slotsUsed() >= 14 then
            consolidateOnSurface()
        end
    end

    return "done"
end

-- ============================================================
-- ENTRY POINT
-- ============================================================

function run()
    ui.drawDashboard()
    if state.resuming then
        ui.setStatus("Reanudando quarry...")
        sleep(0.8)
    end

    local phase = state.quarryPhase or "mine"

    if phase == "mine" then
        local r = runMine()
        if r == "interrupt" then
            state.resuming = false
            return
        end
        phase = state.quarryPhase or "lift"
    end

    if phase == "lift" then
        local r = liftProtocol()
        if r == "interrupt" then
            state.resuming = false
            return
        end
        state.quarryPhase = "consolidate"
        persist.save()
        phase = "consolidate"
    end

    if phase == "consolidate" then
        local r = consolidateOnSurface()
        if r == "interrupt" then
            state.resuming = false
            return
        end
        state.quarryPhase = "done"
        persist.save()
    end

    state.resuming = false

    if state.remoteCmd == "stop" then
        ui.setStatus("STOP - checkpoint OK")
        return
    end

    -- Volver al origen, encarar +X
    ui.setStatus("Volviendo al origen")
    navigateTo(0, 0, 0)
    movement.faceDirection(0)

    persist.clear()
    ui.setStatus("Quarry completado!")
end
