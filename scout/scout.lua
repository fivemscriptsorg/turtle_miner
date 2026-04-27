-- ============================================================
-- SCOUT MODULE
-- Mapea una zona con el geoscanner y publica los ores via rednet.
-- NO mina. Upgrades tipicos: geoscanner + wireless modem.
--
-- Requisitos:
--   - Wireless modem + GPS (minimo 3 hosts) para posicionamiento.
--   - Geoscanner (Advanced Peripherals) como upgrade o peripheral.
--   - Coal/charcoal para auto-refuel.
--
-- La navegacion asume que el aire sobre la zona esta LIBRE: el
-- scout no tiene pico y `turtle.dig()` falla. Si encuentra un
-- obstaculo, intenta subir por encima y continuar.
--
-- Tres patrones (state.scoutPatrol):
--   box        - rectangulo W x L desde corner (boxX, boxZ), recorrido
--                en serpentina a scanAltY, con scans cada stepSpacing.
--   stationary - se queda en el punto inicial, scanea en loop.
--   follow     - va a la posicion del miner activo mas reciente,
--                scanea y vuelve a safeAltY.
-- ============================================================

-- ============================================================
-- NAVEGACION
-- ============================================================

local MAX_VERTICAL_AVOID = 5

local function ensureYAt(targetY)
    while state.y < targetY do
        if not movement.safeUp() then return false end
    end
    while state.y > targetY do
        if not movement.safeDown() then return false end
    end
    return true
end

-- Sube hasta safeAltY antes de moverse en XZ
local function riseToSafe()
    local safe = state.scoutSafeAltY or 20
    return ensureYAt(safe)
end

-- Mueve hasta el target local (tx, tz) a la Y actual. Gira y avanza.
-- Si algo bloquea en XZ, intenta subir un par de bloques para saltarlo.
local function moveXZ(tx, tz)
    -- Eje X primero
    if state.x ~= tx then
        local dir = (tx > state.x) and 0 or 2
        movement.faceDirection(dir)
        local tries = 0
        while state.x ~= tx and tries < 500 do
            if not movement.safeForward() then
                -- Intentar saltar por encima
                local jumped = 0
                for _ = 1, MAX_VERTICAL_AVOID do
                    if movement.safeUp() then jumped = jumped + 1 else break end
                end
                if not movement.safeForward() then
                    for _ = 1, jumped do movement.safeDown() end
                    return false
                end
            end
            tries = tries + 1
        end
    end
    -- Eje Z
    if state.z ~= tz then
        local dir = (tz > state.z) and 1 or 3
        movement.faceDirection(dir)
        local tries = 0
        while state.z ~= tz and tries < 500 do
            if not movement.safeForward() then
                local jumped = 0
                for _ = 1, MAX_VERTICAL_AVOID do
                    if movement.safeUp() then jumped = jumped + 1 else break end
                end
                if not movement.safeForward() then
                    for _ = 1, jumped do movement.safeDown() end
                    return false
                end
            end
            tries = tries + 1
        end
    end
    return true
end

-- Navega a (tx, ty, tz) local subiendo primero a altura segura.
local function goToLocal(tx, ty, tz)
    if not riseToSafe() then return false end
    if not moveXZ(tx, tz) then return false end
    return ensureYAt(ty)
end

-- ============================================================
-- REMOTE COMMAND CHECK
-- ============================================================

local function checkRemoteCmd()
    if state.remoteCmd == "pause" then
        ui.setStatus("PAUSADO - pulsa R para seguir")
        while state.remoteCmd == "pause" do sleep(0.3) end
        ui.setStatus("Reanudando")
        if state.remoteCmd == "resume" then state.remoteCmd = nil end
    end
    return state.remoteCmd == "home" or state.remoteCmd == "stop"
end

-- ============================================================
-- SCAN + BROADCAST
-- ============================================================

-- Hace un scan y broadcast en batch. Devuelve numero de ores.
local function scanHere()
    if not state.hasGeoScanner then
        ui.setStatus("Sin geoscanner")
        return 0
    end
    local radius = state.scoutScanRadius or 8
    local ores = peripherals.scanOres(radius)
    if not ores then return 0 end

    state.scansDone = (state.scansDone or 0) + 1

    -- Coords absolutas de cada ore
    local batch = {}
    for _, o in ipairs(ores) do
        -- o.x/y/z son offsets relativos al scanner (que esta en la turtle)
        local localPos = { x = state.x + o.x, y = state.y + o.y, z = state.z + o.z }
        local abs = swarm.toAbs(localPos.x, localPos.y, localPos.z)
        if abs then
            table.insert(batch, { x = abs.x, y = abs.y, z = abs.z, name = o.name })
            -- Registrar en nuestro propio mapa
            swarm.recordOre(abs, o.name, os.getComputerID())
        end
    end

    -- Broadcast batch. Los listeners lo ingieren como si fueran ore_spotted
    -- individuales (ver swarm.handleSwarmMessage).
    if #batch > 0 and state.hasRemote then
        local scanAbs = swarm.currentAbs()
        pcall(rednet.broadcast, {
            kind = "scan_report",
            by = os.getComputerID(),
            at = scanAbs,
            radius = radius,
            ores = batch,
        }, remote.PROTOCOL)
    end

    state.oresFound = (state.oresFound or 0) + #batch
    return #batch
end

-- ============================================================
-- PATRON: BOX (serpentina sobre rectangulo)
-- ============================================================

local function boxPass()
    local cx = state.scoutBoxX or 0
    local cz = state.scoutBoxZ or 0
    local w  = state.scoutBoxW or 32
    local l  = state.scoutBoxL or 32
    local step = state.scoutStepSpacing or 12
    local scanY = state.scoutScanAltY or 0

    -- Numero de waypoints en cada eje
    local nx = math.max(1, math.floor(w / step))
    local nz = math.max(1, math.floor(l / step))

    for iz = 0, nz do
        if checkRemoteCmd() then return false end
        local z = cz + iz * step
        -- Alternar direccion de x segun parity de z
        local xRange
        if iz % 2 == 0 then
            xRange = {}; for i = 0, nx do table.insert(xRange, cx + i * step) end
        else
            xRange = {}; for i = nx, 0, -1 do table.insert(xRange, cx + i * step) end
        end
        for _, x in ipairs(xRange) do
            if checkRemoteCmd() then return false end
            ui.setStatus("Scan (" .. x .. "," .. z .. ")")
            if not goToLocal(x, scanY, z) then
                ui.setStatus("Bloqueado, salto")
            else
                scanHere()
                sleep(0.2) -- respetar cooldown
            end
            persist.save()
        end
    end
    return true
end

-- ============================================================
-- PATRON: STATIONARY
-- ============================================================

local function stationaryPass()
    ui.setStatus("Scan stationary")
    scanHere()
    return true
end

-- ============================================================
-- PATRON: FOLLOW
-- Escucha los status broadcasts de miners y se situa sobre el
-- mas reciente. Depende de que ya haya miners hablando por rednet.
-- ============================================================

local function pickTargetMiner()
    -- Buscar en nuestra memoria de peers (estadistica simple:
    -- el ultimo miner que vimos). Para eso extraemos info de
    -- state.knownPeers si swarm lo rellena, si no, no podemos.
    if not state.knownPeers then return nil end
    local best, bestAge = nil, math.huge
    local now = os.epoch("utc") / 1000
    for _, p in pairs(state.knownPeers) do
        local age = now - (p.lastSeen or 0)
        if p.mode == "mining" and p.abs and age < 30 and age < bestAge then
            best, bestAge = p, age
        end
    end
    return best
end

local function followPass()
    local target = pickTargetMiner()
    if not target or not target.abs then
        ui.setStatus("Sin miners visibles")
        sleep(2)
        return true
    end
    local localPos = swarm.toLocal(target.abs.x, target.abs.y, target.abs.z)
    if not localPos then return true end
    ui.setStatus("Siguiendo miner")
    if goToLocal(localPos.x, state.scoutScanAltY or 0, localPos.z) then
        scanHere()
    end
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

local function runPass()
    local p = state.scoutPatrol or "box"
    if p == "stationary" then return stationaryPass() end
    if p == "follow" then return followPass() end
    return boxPass()
end

function run()
    ui.drawDashboard()
    if state.resuming then
        ui.setStatus("Reanudando scout")
        sleep(0.8)
    else
        ui.setStatus("Empezando scout")
    end

    if not state.hasGPS then
        ui.setStatus("AVISO: sin GPS")
        sleep(2)
    end
    if not state.hasGeoScanner then
        ui.setStatus("ERROR: sin geoscanner")
        sleep(3)
        return
    end

    local sleepSecs = state.scoutSleepSecs or 30

    while true do
        if checkRemoteCmd() then break end

        ui.drawDashboard()
        runPass()
        persist.save()

        if checkRemoteCmd() then break end
        ui.setStatus("Esperando " .. sleepSecs .. "s")
        sleepInterruptible(sleepSecs)
    end

    if state.remoteCmd == "stop" then
        ui.setStatus("STOP scout - checkpoint OK")
        persist.save()
        return
    end

    -- Volver al inicio (0,0,0) a altura segura
    ui.setStatus("Volviendo")
    goToLocal(0, state.scoutSafeAltY or 20, 0)
    ensureYAt(0)
    persist.clear()
end
