-- ============================================================
-- SWARM MODULE
-- Infraestructura para cooperacion entre multiples turtles:
--  - GPS wrapper (coords absolutas)
--  - conversiones local <-> absoluto
--  - ore map compartido (broadcast + merge)
--  - helpers de mensajeria peer-to-peer
--
-- NO hace pathfinding ni claims activos todavia - esas son
-- capas encima de esta. Aqui vive la DATA LAYER del swarm.
-- ============================================================

-- Tiempo tras el que una entrada del oreMap se considera stale
local ORE_TTL_SECONDS = 300
-- Cap del oreMap para no explotar memoria
local ORE_MAP_MAX = 500

-- ============================================================
-- GPS
-- ============================================================

function tryLocate()
    if not gps or not gps.locate then return nil end
    -- gps.locate necesita que el modem este abierto y que haya
    -- al menos 3 hosts de GPS en rango. Timeout 2s por defecto.
    local ok, x, y, z = pcall(gps.locate, 2, false)
    if not ok or not x then return nil end
    return { x = x, y = y, z = z }
end

-- Configura state.origin = coords ABS de la posicion actual de
-- la turtle (que ella considera su 0,0,0 local). Se llama una
-- vez al boot, despues de que peripherals.detect haya abierto
-- un modem (gps necesita modem).
function initGPS()
    local here = tryLocate()
    if not here then
        state.hasGPS = false
        state.origin = nil
        return false
    end
    -- origin ABS = here - (x,y,z) local. Como state x/y/z=0 al boot,
    -- origin = here directamente.
    state.hasGPS = true
    state.origin = {
        x = here.x - (state.x or 0),
        y = here.y - (state.y or 0),
        z = here.z - (state.z or 0),
    }
    return true
end

-- Convierte coords locales (relativas al inicio de la turtle)
-- a absolutas. Devuelve nil si no hay GPS.
function toAbs(lx, ly, lz)
    if not state.origin then return nil end
    return {
        x = state.origin.x + lx,
        y = state.origin.y + ly,
        z = state.origin.z + lz,
    }
end

-- Convierte coords absolutas a locales. Devuelve nil si no hay GPS.
function toLocal(ax, ay, az)
    if not state.origin then return nil end
    return {
        x = ax - state.origin.x,
        y = ay - state.origin.y,
        z = az - state.origin.z,
    }
end

-- Posicion absoluta actual de la turtle. Nil si no hay GPS.
function currentAbs()
    return toAbs(state.x, state.y, state.z)
end

-- ============================================================
-- ORE MAP
-- Clave "x_y_z" (absolutas). Valor: { x, y, z, name, seenAt, by, claimedBy, claimUntil }
-- Solo se almacenan ores con posicion absoluta (necesita GPS).
-- ============================================================

local function keyFor(x, y, z)
    return x .. "_" .. y .. "_" .. z
end

local function pruneStale()
    local now = os.epoch("utc") / 1000
    local removed = 0
    local count = 0
    for k, v in pairs(state.oreMap) do
        count = count + 1
        if v.seenAt and (now - v.seenAt) > ORE_TTL_SECONDS then
            state.oreMap[k] = nil
            removed = removed + 1
        elseif v.claimUntil and now > v.claimUntil then
            v.claimedBy = nil
            v.claimUntil = nil
        end
    end
    return count - removed
end

local function enforceCap()
    -- Si superamos el cap, tiramos las entradas mas viejas
    local count = 0
    for _ in pairs(state.oreMap) do count = count + 1 end
    if count <= ORE_MAP_MAX then return end

    local entries = {}
    for k, v in pairs(state.oreMap) do
        table.insert(entries, { key = k, seenAt = v.seenAt or 0 })
    end
    table.sort(entries, function(a, b) return a.seenAt < b.seenAt end)
    local toDrop = count - ORE_MAP_MAX
    for i = 1, toDrop do
        state.oreMap[entries[i].key] = nil
    end
end

function mapSize()
    if not state.oreMap then return 0 end
    local n = 0
    for _ in pairs(state.oreMap) do n = n + 1 end
    return n
end

-- Registra un ore detectado (en coords absolutas).
-- by = id de la turtle que lo vio. Devuelve true si es nuevo.
function recordOre(absPos, name, byId)
    if not absPos then return false end
    if not state.oreMap then state.oreMap = {} end
    local k = keyFor(absPos.x, absPos.y, absPos.z)
    local existing = state.oreMap[k]
    local now = os.epoch("utc") / 1000
    if existing then
        existing.seenAt = now
        return false
    end
    state.oreMap[k] = {
        x = absPos.x, y = absPos.y, z = absPos.z,
        name = name,
        seenAt = now,
        by = byId,
    }
    pruneStale()
    enforceCap()
    return true
end

-- Elimina un ore del mapa (porque alguien lo cavo).
function forgetOre(absPos)
    if not absPos or not state.oreMap then return end
    state.oreMap[keyFor(absPos.x, absPos.y, absPos.z)] = nil
end

-- Marca un ore como claimed por una turtle durante ttl segundos.
function claimOre(absPos, byId, ttl)
    if not absPos or not state.oreMap then return false end
    local k = keyFor(absPos.x, absPos.y, absPos.z)
    local ore = state.oreMap[k]
    if not ore then return false end
    local now = os.epoch("utc") / 1000
    if ore.claimedBy and ore.claimedBy ~= byId and ore.claimUntil and now < ore.claimUntil then
        return false -- ya reclamado por otro
    end
    ore.claimedBy = byId
    ore.claimUntil = now + (ttl or 30)
    return true
end

-- Busca el ore sin claim mas cercano a una posicion absoluta.
-- Devuelve ore_entry y distancia manhattan, o nil.
function nearestUnclaimed(fromAbs, maxDist)
    if not fromAbs or not state.oreMap then return nil end
    pruneStale()
    local best, bestDist = nil, math.huge
    local now = os.epoch("utc") / 1000
    for _, ore in pairs(state.oreMap) do
        local claimed = ore.claimedBy and ore.claimUntil and now < ore.claimUntil
        if not claimed then
            local d = math.abs(ore.x - fromAbs.x)
                + math.abs(ore.y - fromAbs.y)
                + math.abs(ore.z - fromAbs.z)
            if d < bestDist and (not maxDist or d <= maxDist) then
                best, bestDist = ore, d
            end
        end
    end
    return best, bestDist
end

-- ============================================================
-- BROADCAST HELPERS
-- Se llaman desde mining cuando ocurre algo. Si no hay remote
-- activo, son no-ops silenciosos.
-- ============================================================

function broadcastOreSpotted(localPos, name)
    if not state.hasRemote then return end
    local abs = toAbs(localPos.x, localPos.y, localPos.z)
    if not abs then return end -- sin GPS no tiene sentido (otros no pueden localizarlo)
    local msg = {
        kind = "ore_spotted",
        pos = abs,
        name = name,
        by = os.getComputerID(),
    }
    pcall(rednet.broadcast, msg, remote.PROTOCOL)
    -- y lo registramos en nuestro propio mapa
    recordOre(abs, name, os.getComputerID())
end

function broadcastOreGone(localPos)
    if not state.hasRemote then return end
    local abs = toAbs(localPos.x, localPos.y, localPos.z)
    if not abs then return end
    local msg = {
        kind = "ore_gone",
        pos = abs,
        by = os.getComputerID(),
    }
    pcall(rednet.broadcast, msg, remote.PROTOCOL)
    forgetOre(abs)
end

-- ============================================================
-- MESSAGE HANDLING (llamado desde remote.listener)
-- Procesa mensajes swarm que no son comandos cliente<->turtle.
-- Devuelve true si manejo el mensaje.
-- ============================================================

-- Registro de peers (miners/scouts/etc.) para follow mode del scout
-- y para el dashboard local. Se actualiza con cada status broadcast.
local function recordPeer(senderId, data)
    if not data then return end
    state.knownPeers = state.knownPeers or {}
    state.knownPeers[senderId] = {
        id       = senderId,
        hostname = data.hostname,
        mode     = data.mode,
        abs      = data.abs,
        fuel     = data.fuel,
        lastSeen = os.epoch("utc") / 1000,
    }
end

function handleSwarmMessage(senderId, msg)
    if type(msg) ~= "table" then return false end
    if msg.kind == "ore_spotted" and msg.pos then
        recordOre(msg.pos, msg.name, msg.by or senderId)
        return true
    elseif msg.kind == "ore_gone" and msg.pos then
        forgetOre(msg.pos)
        return true
    elseif msg.kind == "ore_claim" and msg.pos then
        claimOre(msg.pos, msg.by or senderId, msg.ttl or 30)
        return true
    elseif msg.kind == "scan_report" and type(msg.ores) == "table" then
        -- Batch de un scout: cada entrada es una ore en ABS coords.
        for _, ore in ipairs(msg.ores) do
            if ore.x and ore.y and ore.z and ore.name then
                recordOre(ore, ore.name, msg.by or senderId)
            end
        end
        return true
    elseif msg.kind == "sync_request" then
        pcall(rednet.send, senderId,
            { kind = "sync_dump", oreMap = state.oreMap or {} },
            remote.PROTOCOL)
        return true
    elseif msg.kind == "sync_dump" and type(msg.oreMap) == "table" then
        for _, ore in pairs(msg.oreMap) do
            if ore.x and ore.y and ore.z and ore.name then
                recordOre(ore, ore.name, ore.by)
            end
        end
        return true
    elseif msg.kind == "status" and msg.data then
        -- Aprovechamos los status broadcasts para poblar knownPeers.
        -- Devolvemos false para que el flujo normal de remote.handleMessage
        -- tambien los procese si hace falta.
        recordPeer(senderId, msg.data)
        return false
    end
    return false
end

-- Al arrancar una turtle nueva: pide un sync a las demas
function requestSync()
    if not state.hasRemote then return end
    pcall(rednet.broadcast, { kind = "sync_request" }, remote.PROTOCOL)
end
