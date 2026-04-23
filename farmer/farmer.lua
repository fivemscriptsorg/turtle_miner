-- ============================================================
-- FARMER MODULE
-- Cultivo automatizado de trigo, zanahoria, patata y remolacha.
--
-- GEOMETRIA:
--   La turtle VUELA por encima del plot para no pisar farmland.
--   Al arrancar cada ciclo, sube FLY_HEIGHT (1) bloque sobre su
--   posicion de partida. Tras caminar el plot, baja para volcar.
--
--   Setup fisico:
--     [C][T][.][.][.]...       <- turtle sobre grass/path, adyacente
--     [ ][ ][C][C][C]...          cultivos (C) crecen a la misma Y
--     [ ][ ][F][F][F]...          farmland (F) 1 abajo
--
--   Cuando colocas la turtle sobre un bloque, ya esta en el slot
--   encima = MISMO Y que un cultivo creciendo en el farmland
--   adyacente. Subiendo SOLO 1 bloque, la turtle queda a
--   crop_Y + 1: inspectDown ve el cultivo y avanzar pasa por aire.
--
-- REQUISITOS:
--   - El plot ya tiene que estar preparado (farmland regado).
--   - Turtle adyacente al plot, AL MISMO NIVEL que el farmland.
--   - Chest directamente atras (tambien al mismo nivel).
--   - Semillas en inventario para los cultivos que se cultiven.
--   - Agua cada 9x9 bloques de farmland.
--
-- Patron: serpentina. Recorre fila +X, avanza 1 en Z, vuelve -X,
-- y asi. Al final vuelve, baja, vuelca, duerme, vuelve a subir.
-- ============================================================

-- Al colocar la turtle sobre un bloque (grass/dirt/path) ya ocupa el
-- slot encima (mismo Y que crece un cultivo). Con 1 sola subida
-- queda 1 bloque sobre el cultivo -> inspectDown lo ve.
local FLY_HEIGHT = 1

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

-- Si hay farmland vacia debajo, planta la PRIMERA semilla conocida
-- que tengamos en inventario. Sirve para sembrar un plot recien
-- arado sin tener que esperar a un primer ciclo de cultivos maduros.
local function plantAnySeed()
    for _, crop in pairs(CROPS) do
        if selectSeed(crop.seed) then
            if turtle.placeDown() then
                state.cropsPlanted = (state.cropsPlanted or 0) + 1
                return true
            end
        end
    end
    return false
end

local function processCell()
    local ok, block = turtle.inspectDown()
    local name = (ok and block and block.name) or "minecraft:air"

    -- Caso 1: aire o farmland debajo -> plantar si tenemos semilla.
    -- IMPORTANTE: la turtle vuela a crop_Y+1. Si no hay cultivo,
    -- inspectDown ve AIRE (el slot del cultivo vacio), no farmland
    -- (que esta 2 abajo). placeDown con seed igual planta: MC busca
    -- farmland un bloque mas abajo al usar la semilla.
    if name == "minecraft:air" or name == "minecraft:farmland" then
        if plantAnySeed() then
            ui.setStatus("plantado")
            return true
        end
        ui.setStatus(name == "minecraft:air" and "aire, sin semilla" or "farmland, sin semilla")
        return false
    end

    -- Caso 2: bloque desconocido (dirt/stone/...) -> setup raro
    local crop = CROPS[name]
    if not crop then
        ui.setStatus("cell: " .. name:gsub("minecraft:", ""))
        return false
    end

    -- Caso 3: cultivo joven -> esperar
    local age = (block.state and block.state.age) or 0
    if age < crop.maxAge then
        ui.setStatus("joven age="..age.."/"..crop.maxAge)
        return false
    end

    -- Caso 4: cultivo maduro -> cosechar y replantar
    if not turtle.digDown() then
        ui.setStatus("digDown fallo")
        return false
    end
    state.cropsHarvested = (state.cropsHarvested or 0) + 1
    notifyCrop(name)

    if selectSeed(crop.seed) then
        if turtle.placeDown() then
            state.cropsPlanted = (state.cropsPlanted or 0) + 1
            ui.setStatus("harvested+replanted")
        else
            ui.setStatus("placeDown fallo")
        end
    else
        ui.setStatus("harvested, sin semilla")
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

    -- APPROACH: la turtle empieza FUERA del plot (sobre grass/path
    -- adyacente). El primer paso la mete en la primera celda del
    -- plot para que processCell vea el cultivo/farmland.
    if not movement.safeForward() then
        ui.setStatus("No puedo entrar al plot")
        return false
    end
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
-- ALTITUDE
-- Sube FLY_HEIGHT=1 bloque desde la posicion de inicio.
--
-- Clave: la turtle al colocarse sobre un bloque ya ocupa el slot
-- encima (= mismo Y que crece un cultivo en farmland adyacente).
-- Subiendo 1 mas, la turtle queda en crop_Y + 1 -> inspectDown
-- ve el cultivo debajo y puede avanzar por aire.
--
-- Early-return si inspectDown ya ve un cultivo: estamos justo
-- donde queremos.
-- ============================================================

local function ascendToFly()
    local target = FLY_HEIGHT
    for _ = 1, target do
        local ok, block = turtle.inspectDown()
        if ok and block and block.name and CROPS[block.name] then
            -- Ya estamos sobre un cultivo (1 por encima). Stop.
            return true
        end
        if not movement.safeUp() then
            ui.setStatus("No puedo subir!")
            return false
        end
    end
    return true
end

local function descendToGround()
    while state.y > 0 do
        if not movement.safeDown() then
            ui.setStatus("No puedo bajar!")
            return false
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

    -- Subir a altitud de trabajo antes del primer ciclo
    ui.setStatus("Subiendo a altitud")
    if not ascendToFly() then
        ui.setStatus("ERROR: no hay espacio arriba")
        sleep(2)
        return
    end

    while true do
        if checkRemoteCmd() then break end

        state.farmCycle = (state.farmCycle or 0) + 1
        ui.drawDashboard()
        ui.setStatus("Ciclo "..state.farmCycle)

        walkPlot()
        returnHome()
        descendToGround()     -- bajar para alcanzar el cofre
        dumpAtHome()
        persist.save()

        if checkRemoteCmd() then break end
        ui.setStatus("Esperando "..sleepSecs.."s")
        sleepInterruptible(sleepSecs)

        if checkRemoteCmd() then break end
        -- volver a subir para el siguiente ciclo
        ascendToFly()
    end

    -- Al terminar (stop / home remoto): asegurarnos de estar en el suelo
    descendToGround()

    if state.remoteCmd == "stop" then
        ui.setStatus("STOP farmer - checkpoint OK")
        persist.save()
        return
    end

    returnHome()
    dumpAtHome()
    persist.clear()
end
