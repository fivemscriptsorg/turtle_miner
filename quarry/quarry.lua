-- ============================================================
-- QUARRY MODULE
-- Excava un rectangulo top-down y descarga via ender chest.
-- Dos sub-modos:
--   miner    = la turtle excava un W x L rectangulo capa por capa,
--              descendiendo. Cuando se llena coloca un ender chest
--              arriba, dropea, lo recoge, sigue.
--   unloader = estatica al lado de un cofre normal. Saca items del
--              ender chest (encima de ella) y los pasa al cofre.
--
-- Convencion de coordenadas (igual que el resto):
--   Turtle empieza en (0,0,0) mirando +X (facing=0).
--   length L = a lo largo de +X.
--   width  W = a lo largo de +Z (perpendicular, "derecha").
--   layer  = numero de descensos hechos. y = -quarryLayer.
--
-- Ender chest comparte inventario globalmente (vanilla minecraft:
-- ender_chest sin canales). El unloader saca de su ender chest y
-- el miner mete en el suyo: estan conectados.
-- ============================================================

-- ============================================================
-- HELPERS COMPARTIDOS (copia de mining/mining.lua para no acoplar)
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
            if direction == "up" then
                orePos.y = orePos.y + 1
            elseif direction == "down" then
                orePos.y = orePos.y - 1
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

-- Devuelve true si hay que abortar el loop (home/stop). Bloquea en pause.
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
-- BEDROCK / IRROMPIBLES
-- ============================================================

local function isBedrock(name)
    return name == "minecraft:bedrock"
end

-- Mina el bloque debajo. Devuelve:
--   "ok"      = excavado o ya era aire
--   "bedrock" = bedrock detectado, abortar quarry
--   "blocked" = algo irrompible debajo (lava-source, obsidiana sin pico, etc)
local function mineCellDown()
    inspectAndLog("down")
    local ok, data = turtle.inspectDown()
    if ok and data and isBedrock(data.name) then
        return "bedrock"
    end

    if not turtle.detectDown() then return "ok" end

    digCounting(turtle.digDown, turtle.detectDown)
    -- Reintento por si cae arena/grava encima de inmediato
    for _ = 1, 3 do
        if not turtle.detectDown() then return "ok" end
        digCounting(turtle.digDown, turtle.detectDown)
        sleep(0.15)
    end
    if turtle.detectDown() then return "blocked" end
    return "ok"
end

-- ============================================================
-- ENDER CHEST DUMP
-- Coloca el ender chest arriba (encima esta vacio por construccion:
-- la turtle acaba de bajar desde alli). Dropea slots 2..15 menos
-- fuel y ender chests. Recupera el cofre con digUp.
-- ============================================================

local function findEnderSlot()
    -- Preferir el slot reservado, si tiene ender chest.
    local reserved = state.enderSlot or 1
    local d = turtle.getItemDetail(reserved)
    if d and inventory.isEnderChest(d.name) then return reserved end
    -- Fallback: buscar en cualquier slot
    return inventory.findSlot(inventory.isEnderChest)
end

local function dumpToEnderChest()
    ui.setStatus("Descargando ender chest")
    inventory.compact()
    inventory.dropJunk()
    if inventory.slotsUsed() < (state.dumpThreshold or 13) then
        return true
    end

    -- Limpiar arriba (puede haber arena que cayo)
    if turtle.detectUp() then
        digCounting(turtle.digUp, turtle.detectUp)
        sleep(0.15)
        if turtle.detectUp() then digCounting(turtle.digUp, turtle.detectUp) end
    end

    local slot = findEnderSlot()
    if not slot then
        ui.setStatus("Sin ender chest!")
        sleep(1)
        -- Fallback: cofre normal a la derecha si hay
        return inventory.placeChest()
    end

    local prevSelect = turtle.getSelectedSlot()
    turtle.select(slot)

    local placed = turtle.placeUp()
    if not placed then
        sleep(0.3)
        if turtle.detectUp() then digCounting(turtle.digUp, turtle.detectUp) end
        placed = turtle.placeUp()
    end
    if not placed then
        ui.setStatus("No pude colocar ender")
        turtle.select(prevSelect)
        return false
    end

    -- Dropear todo menos fuel y ender chests
    local enderSlot = state.enderSlot or 1
    local fuelSlot  = state.fuelSlot  or 16
    for i = 1, 16 do
        if i ~= enderSlot and i ~= fuelSlot then
            local d = turtle.getItemDetail(i)
            if d and not inventory.isEnderChest(d.name) and not inventory.isFuel(d.name) then
                turtle.select(i)
                turtle.dropUp()
            end
        end
    end

    -- Recuperar el ender chest. Reintenta 3 veces si arena cae.
    turtle.select(slot)
    local recovered = false
    for _ = 1, 3 do
        if turtle.digUp() then recovered = true; break end
        sleep(0.2)
    end
    if not recovered then
        ui.setStatus("Ender chest perdido!")
        state.enderLost = true
    else
        state.chestsPlaced = (state.chestsPlaced or 0) + 1
    end

    turtle.select(prevSelect)
    return recovered
end

-- ============================================================
-- SAFE FORWARD CON RETORNO
-- safeForward retorna false tras 8 retries; lo elevamos a un
-- helper que registra el evento y decide si bailar.
-- ============================================================

local function tryStepForward()
    inspectAndLog("forward")
    digCounting(turtle.dig, turtle.detect)
    return movement.safeForward()
end

-- ============================================================
-- SNAKE LAYER (lawnmower)
-- Estado:
--   state.quarryRow  ∈ [0, W-1]   fila a lo largo del eje width (+Z)
--   state.quarryCol  ∈ [0, L-1]   col a lo largo del eje length (+X)
--   state.quarryDirection ∈ {+1,-1}  direccion en la fila actual
--   state.quarryRowDir    ∈ {+1,-1}  direccion en el eje rows entre layers
-- ============================================================

local function faceLength(dir)
    -- dir +1 → facing 0 (+X), dir -1 → facing 2 (-X)
    movement.faceDirection(dir > 0 and 0 or 2)
end

local function faceWidth(dir)
    -- dir +1 → facing 1 (+Z), dir -1 → facing 3 (-Z)
    movement.faceDirection(dir > 0 and 1 or 3)
end

local function mineLayer(W, L)
    local rowDir = state.quarryRowDir or 1
    local colDir = state.quarryDirection or 1
    state.quarryRowDir    = rowDir
    state.quarryDirection = colDir

    local row = state.quarryRow or 0
    local col = state.quarryCol or 0

    while row >= 0 and row < W do
        state.quarryRow = row
        state.quarryDirection = colDir

        -- Recorre la fila desde col actual hasta el extremo
        while col >= 0 and col < L do
            if checkRemoteCmd() then return "interrupt" end

            state.quarryCol = col

            local r = mineCellDown()
            if r == "bedrock" then
                state.quarryDone = true
                return "bedrock"
            end
            -- "blocked" (irrompible) → seguimos, registramos, no bloquea quarry

            if inventory.slotsUsed() >= (state.dumpThreshold or 13) then
                dumpToEnderChest()
            end

            -- Refuel preventivo: si el viaje a casa supera lo que tenemos, intenta refuel
            local fuel = turtle.getFuelLevel()
            if fuel ~= "unlimited" then
                local needed = math.abs(state.x) + math.abs(state.z) + math.abs(state.y) + 30
                if fuel < needed then
                    inventory.autoRefuel(needed)
                end
            end

            persist.save()

            -- Avanzar al siguiente col en esta fila
            local nextCol = col + colDir
            local atRowEnd = (colDir > 0 and nextCol >= L) or (colDir < 0 and nextCol < 0)
            if atRowEnd then break end

            faceLength(colDir)
            if not tryStepForward() then
                ui.setStatus("Columna bloqueada, salto fila")
                break
            end
            col = nextCol
        end

        -- Fin de fila. Hay siguiente?
        local nextRow = row + rowDir
        local atLastRow = (rowDir > 0 and nextRow >= W) or (rowDir < 0 and nextRow < 0)
        if atLastRow then break end

        -- Cruzar al siguiente row (1 paso lateral)
        faceWidth(rowDir)
        if not tryStepForward() then
            ui.setStatus("Lateral bloqueado, capa parcial")
            break
        end

        row = nextRow
        colDir = -colDir
        state.quarryRow       = row
        state.quarryDirection = colDir
    end

    state.quarryRow = row
    state.quarryCol = col
    return "done"
end

-- ============================================================
-- DESCEND ENTRE LAYERS
-- ============================================================

local function descendOne()
    -- Mira primero abajo: si bedrock, abortar
    local ok, data = turtle.inspectDown()
    if ok and data and isBedrock(data.name) then
        state.quarryDone = true
        return false
    end
    if not movement.safeDown() then return false end
    state.quarryLayer = (state.quarryLayer or 0) + 1
    -- Reset row al inicio del nuevo barrido (snake-back: invertimos rowDir)
    state.quarryRowDir = -(state.quarryRowDir or 1)
    -- col y row se mantienen donde acabamos para snake seamless
    return true
end

-- ============================================================
-- RETURN TO START
-- Sube hasta y=0, vuelve a (0,0,0), encara +X.
-- ============================================================

local function returnToStart()
    ui.setStatus("Subiendo...")
    while state.y < 0 do
        if not movement.safeUp() then break end
    end

    ui.setStatus("Volviendo a origen")
    -- Volver a x=0
    if state.x ~= 0 then
        movement.faceDirection(state.x > 0 and 2 or 0)
        while state.x ~= 0 do
            if not movement.safeForward() then break end
        end
    end
    -- Volver a z=0
    if state.z ~= 0 then
        movement.faceDirection(state.z > 0 and 3 or 1)
        while state.z ~= 0 do
            if not movement.safeForward() then break end
        end
    end
    movement.faceDirection(0)

    -- Descarga final
    if inventory.slotsUsed() > 0 then
        ui.setStatus("Descarga final")
        dumpToEnderChest()
    end
end

-- ============================================================
-- RUN MINER
-- ============================================================

local function runMiner()
    local W = state.quarryWidth  or 8
    local L = state.quarryLength or 8
    local maxDepth = state.quarryMaxDepth or 64  -- 0 = bedrock

    -- Init runtime si no estamos resumiendo
    if not state.resuming then
        state.quarryRow       = 0
        state.quarryCol       = 0
        state.quarryDirection = 1
        state.quarryRowDir    = 1
        state.quarryLayer     = 0
        state.quarryDone      = false
    end

    ui.drawDashboard()
    ui.setStatus("Quarry " .. W .. "x" .. L .. " miner")

    while not state.quarryDone do
        if checkRemoteCmd() then break end

        ui.drawDashboard()
        ui.setStatus(string.format("Capa %d  fila %d/%d  col %d/%d",
            state.quarryLayer or 0, (state.quarryRow or 0) + 1, W,
            (state.quarryCol or 0) + 1, L))

        local r = mineLayer(W, L)
        if r == "interrupt" or r == "bedrock" then break end

        -- Limite por profundidad (0 = bajar hasta bedrock)
        if maxDepth > 0 and (state.quarryLayer or 0) + 1 >= maxDepth then
            state.quarryDone = true
            break
        end

        -- Descender al siguiente layer
        if not descendOne() then break end
    end
    state.resuming = false

    -- "stop" remoto: dejar checkpoint y salir sin volver
    if state.remoteCmd == "stop" then
        ui.setStatus("STOP remoto - checkpoint OK")
        persist.save()
        return
    end

    returnToStart()
    persist.clear()
end

-- ============================================================
-- RUN UNLOADER
-- Estatica. La turtle MISMA coloca su ender chest arriba cada
-- ciclo (asi el jugador no necesita perder un eye of ender):
--   1) placeUp ender chest (slot enderSlot)
--   2) suckUp hasta vaciar el ender chest
--   3) digUp para recuperar el cofre
--   4) si trajo items, girar a storageSide y dropear al cofre destino
-- ============================================================

local SIDE_TURNS = {
    front = 0,
    right = 1,
    back  = 2,
    left  = 3,
}

local function turnTo(side)
    local n = SIDE_TURNS[side or "front"] or 0
    for _ = 1, n do movement.turnRight() end
end

local function turnBack(side)
    local n = SIDE_TURNS[side or "front"] or 0
    for _ = 1, n do movement.turnLeft() end
end

-- Coloca el ender chest arriba. Devuelve el slot donde estaba o nil.
local function placeEnderChestUp()
    local slot = findEnderSlot()
    if not slot then return nil end

    -- Limpiar arriba (puede haber arena/grava o un cofre fantasma)
    if turtle.detectUp() then
        digCounting(turtle.digUp, turtle.detectUp)
        sleep(0.15)
        if turtle.detectUp() then digCounting(turtle.digUp, turtle.detectUp) end
    end

    local prevSelect = turtle.getSelectedSlot()
    turtle.select(slot)
    local ok = turtle.placeUp()
    if not ok then
        sleep(0.3)
        if turtle.detectUp() then digCounting(turtle.digUp, turtle.detectUp) end
        ok = turtle.placeUp()
    end
    turtle.select(prevSelect)
    return ok and slot or nil
end

-- Recoge el ender chest de arriba con 3 reintentos.
local function recoverEnderChestUp(slot)
    if slot then turtle.select(slot) end
    for _ = 1, 3 do
        if turtle.digUp() then return true end
        sleep(0.2)
    end
    return false
end

local function unloaderTick()
    -- 1) Colocar el ender chest arriba
    local slot = placeEnderChestUp()
    if not slot then
        state.unloadStuck = true
        ui.setStatus("Sin ender chest!")
        return false
    end

    -- 2) Vaciar el ender chest hacia el inventario propio
    local pulled = false
    for _ = 1, 64 do
        if not turtle.suckUp() then break end
        pulled = true
    end

    -- 3) Recoger el cofre antes de mover items (asi el slot queda libre por si acaso)
    if not recoverEnderChestUp(slot) then
        ui.setStatus("Ender chest perdido!")
        state.enderLost = true
        -- seguimos: aun podemos dropear lo que tengamos
    end

    if not pulled then return false end

    -- 4) Girar al cofre destino y dropear todo lo que NO sea ender chest ni fuel
    turnTo(state.storageSide)
    local stuck = false
    local enderSlot = state.enderSlot or 1
    local fuelSlot  = state.fuelSlot  or 16
    for i = 1, 16 do
        if i ~= enderSlot and i ~= fuelSlot and turtle.getItemCount(i) > 0 then
            local d = turtle.getItemDetail(i)
            if d and not inventory.isEnderChest(d.name) and not inventory.isFuel(d.name) then
                turtle.select(i)
                if not turtle.drop() then stuck = true end
            end
        end
    end
    state.unloadStuck = stuck
    turnBack(state.storageSide)
    turtle.select(1)

    state.unloadCycles = (state.unloadCycles or 0) + 1
    return true
end

local function runUnloader()
    state.unloadCycles = state.unloadCycles or 0
    state.unloadStuck  = false

    ui.drawDashboard()
    ui.setStatus("Unloader " .. tostring(state.storageSide or "front"))

    while true do
        if checkRemoteCmd() then break end

        ui.drawDashboard()
        if state.unloadStuck then
            ui.setStatus("Cofre destino LLENO!")
        else
            ui.setStatus(string.format("Ciclos %d  side=%s",
                state.unloadCycles or 0, tostring(state.storageSide or "front")))
        end

        local moved = unloaderTick()
        if not moved then
            sleep(state.unloadSleepSecs or 5)
        else
            -- breve pausa para no saturar
            sleep(0.2)
        end
    end

    if state.remoteCmd == "stop" then
        persist.save()
    else
        persist.clear()
    end
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

    local mode = state.quarryMode or "miner"
    if mode == "unloader" then
        runUnloader()
    else
        runMiner()
    end
end
