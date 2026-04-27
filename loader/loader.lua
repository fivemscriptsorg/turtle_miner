-- ============================================================
-- LOADER MODULE  (Chunky Turtle follower)
-- Sigue a otra turtle manteniendose en su mismo chunk, para
-- que el upgrade Chunky de Advanced Peripherals mantenga
-- cargado el area donde trabaja la target.
--
-- Requisitos:
--   - Wireless modem (rednet)
--   - GPS (3+ host computers al alcance) - marco de coords comun
--   - Upgrade "Chunky Turtle" de Advanced Peripherals equipado
--
-- Config (/role.cfg seccion `loader`):
--   followTarget : number (id) | string (hostname) | "auto"
--   cruiseAltY   : altitud absoluta de vuelo (default 120)
--   chunkPadding : 0 = mismo chunk, 1 = 1 chunk de tolerancia, ...
--
-- Protocolo rednet (comandos adicionales, procesados en remote.lua):
--   { action = "follow", targetId = 7 }         -- fijar target
--   { action = "follow", auto = true }          -- modo auto
--   { action = "follow", targetId = nil }       -- borrar target
--
-- IMPORTANTE: la turtle NUNCA cava bloques para moverse. Si hay
-- un obstaculo intenta subir hasta MAX_FLY_RETRIES bloques. Si
-- tampoco pasa, se queda donde este y sigue intentandolo al
-- proximo ciclo (la target posiblemente se mueva y la ruta libere).
-- ============================================================

local CHUNK_SIZE             = 16
local STATUS_REQUEST_EVERY   = 4      -- segs entre pings on-demand
local LOOP_TICK              = 1      -- segs por iteracion del loop
local MAX_FLY_RETRIES        = 6      -- cuanto puede subir para esquivar

-- ============================================================
-- HELPERS
-- ============================================================

local function now() return os.epoch("utc") / 1000 end

local function chunkOf(abs)
    return math.floor(abs.x / CHUNK_SIZE), math.floor(abs.z / CHUNK_SIZE)
end

local function chunkCenter(cx, cz, y)
    return {
        x = cx * CHUNK_SIZE + 8,
        y = y,
        z = cz * CHUNK_SIZE + 8,
    }
end

local function chunkDist(cx1, cz1, cx2, cz2)
    return math.max(math.abs(cx1 - cx2), math.abs(cz1 - cz2))
end

local function applyForwardDelta(sign)
    sign = sign or 1
    if state.facing == 0 then state.x = state.x + sign
    elseif state.facing == 1 then state.z = state.z + sign
    elseif state.facing == 2 then state.x = state.x - sign
    elseif state.facing == 3 then state.z = state.z - sign
    end
end

-- ============================================================
-- REMOTE COMMAND CHECK (mismo patron que el resto de roles)
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
-- VUELO (sin cavar)
-- ============================================================

-- Intenta moverse un bloque hacia adelante. Si choca, sube hasta
-- MAX_FLY_RETRIES bloques intentando librar el obstaculo.
-- Solo actualiza state.x/y/z en movimientos EXITOSOS.
local function flyForward()
    if turtle.forward() then
        applyForwardDelta(1)
        return true
    end
    for _ = 1, MAX_FLY_RETRIES do
        if not turtle.up() then return false end
        state.y = state.y + 1
        if turtle.forward() then
            applyForwardDelta(1)
            return true
        end
    end
    return false
end

-- Sube hasta la altitud absoluta indicada. Falla si hay techo.
local function flyUpTo(absY)
    local here = swarm.currentAbs()
    if not here then return false end
    while here.y < absY do
        if not turtle.up() then return false end
        state.y = state.y + 1
        here = swarm.currentAbs()
    end
    return true
end

-- Vuela horizontal manteniendo la Y actual hasta llegar a (absX, absZ).
-- Movimiento axial: primero X, luego Z. Devuelve true si llego.
local function flyToXZ(targetAbsX, targetAbsZ)
    local localTarget = swarm.toLocal(targetAbsX, state.y + state.origin.y, targetAbsZ)
    if not localTarget then return false end

    -- Eje X
    if state.x ~= localTarget.x then
        movement.faceDirection(localTarget.x > state.x and 0 or 2)
        while state.x ~= localTarget.x do
            if checkRemoteCmd() then return false end
            if not flyForward() then
                ui.setStatus("Ruta X bloqueada")
                return false
            end
        end
    end

    -- Eje Z
    if state.z ~= localTarget.z then
        movement.faceDirection(localTarget.z > state.z and 1 or 3)
        while state.z ~= localTarget.z do
            if checkRemoteCmd() then return false end
            if not flyForward() then
                ui.setStatus("Ruta Z bloqueada")
                return false
            end
        end
    end

    return true
end

-- ============================================================
-- TARGET RESOLUTION
-- Usa state.knownPeers (llenado por swarm vi status broadcasts).
-- ============================================================

local function isFreshPeer(peer)
    if not peer or not peer.abs then return false end
    return (now() - (peer.lastSeen or 0)) < 30
end

local function resolveTarget()
    local ft = state.followTarget

    -- Modo auto: primer peer no-yo con abs fresca
    if ft == nil or ft == "" or ft == "auto" then
        if state.knownPeers then
            for id, peer in pairs(state.knownPeers) do
                if id ~= os.getComputerID() and isFreshPeer(peer) then
                    return id, peer
                end
            end
        end
        return nil, nil
    end

    -- Numero: id directo
    local asNum = tonumber(ft)
    if asNum then
        local peer = state.knownPeers and state.knownPeers[asNum]
        return asNum, peer
    end

    -- String: hostname lookup (primero en cache, luego rednet.lookup)
    if type(ft) == "string" and state.knownPeers then
        for id, peer in pairs(state.knownPeers) do
            if peer.hostname == ft then return id, peer end
        end
    end
    if type(ft) == "string" then
        local id = rednet.lookup(remote.PROTOCOL, ft)
        if id then return id, state.knownPeers and state.knownPeers[id] end
    end

    return nil, nil
end

-- ============================================================
-- ENTRY POINT
-- ============================================================

function run()
    ui.drawDashboard()
    ui.setStatus("Loader iniciando...")

    -- Requisitos
    if not state.hasRemote then
        ui.setStatus("ERROR: sin modem / rednet")
        sleep(3); return
    end
    if not state.hasGPS or not state.origin then
        ui.setStatus("ERROR: sin GPS")
        sleep(3); return
    end

    -- Altitud de crucero
    local cruiseY = state.cruiseAltY or 120
    local here = swarm.currentAbs()
    if here.y < cruiseY then
        ui.setStatus("Ascendiendo a Y=" .. cruiseY)
        if not flyUpTo(cruiseY) then
            ui.setStatus("Bloqueado subiendo - mueveme")
            sleep(3); return
        end
    end

    -- Pedir status a toda la red al inicio para popular knownPeers rapido
    pcall(rednet.broadcast, { action = "status" }, remote.PROTOCOL)

    local lastStatusReq = 0

    while true do
        if checkRemoteCmd() then break end

        local t = now()
        local targetId, peer = resolveTarget()

        -- Poll activo: si llevamos demasiado sin ver al target, pedir status
        if targetId and (t - lastStatusReq) > STATUS_REQUEST_EVERY then
            pcall(rednet.send, targetId, { action = "status" }, remote.PROTOCOL)
            lastStatusReq = t
        end

        if peer and peer.abs then
            local myAbs = swarm.currentAbs()
            local myCX, myCZ = chunkOf(myAbs)
            local tgCX, tgCZ = chunkOf(peer.abs)
            local dist = chunkDist(myCX, myCZ, tgCX, tgCZ)
            local padding = state.chunkPadding or 0

            state.lastTargetAbs = peer.abs
            state.lastTargetAt  = peer.lastSeen or t
            state.liveTargetId  = targetId

            if dist > padding then
                ui.setStatus(string.format(
                    "Chunk target (%d,%d) d=%d", tgCX, tgCZ, dist))
                local c = chunkCenter(tgCX, tgCZ, myAbs.y)
                flyToXZ(c.x, c.z)
            else
                ui.setStatus(string.format(
                    "En chunk #%s  d=0", tostring(targetId)))
            end
        else
            if state.followTarget == nil or state.followTarget == "auto" or state.followTarget == "" then
                ui.setStatus("Modo AUTO - sin peers")
            else
                ui.setStatus("Sin update de target " .. tostring(state.followTarget))
            end
        end

        ui.drawDashboard()
        sleep(LOOP_TICK)
    end

    if state.remoteCmd == "stop" then
        ui.setStatus("STOP - detenida")
    end
end
