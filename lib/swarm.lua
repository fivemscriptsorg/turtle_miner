-- ============================================================
-- SWARM MODULE
-- Infraestructura P2P para cooperacion entre multiples turtles:
--  - GPS wrapper (coords absolutas)
--  - ore map compartido con version por entrada (seenAt)
--  - tombstones (10 min TTL) para evitar re-introducir ores minados
--  - sync inteligente: digest -> offer -> ack -> chunked dump
--  - anti-entropy gossip cada 120s para auto-healing
--  - compat con protocolo viejo (sync_dump)
--
-- NO hace pathfinding ni claims activos. Aqui vive la data layer
-- y el protocolo de sync.
-- ============================================================

-- Constantes
local ORE_TTL_SECONDS    = 300      -- stale sin ver
local ORE_MAP_MAX        = 500      -- cap de entradas
local TOMBSTONE_TTL      = 600      -- 10 min
local GOSSIP_INTERVAL    = 120      -- 2 min
local SYNC_OFFER_WAIT    = 3        -- ventana para recoger offers
local SYNC_DUMP_TIMEOUT  = 15       -- chunks deben llegar en <=15s
local CHUNK_SIZE         = 100      -- entradas por chunk

-- ============================================================
-- GPS
-- ============================================================

function tryLocate()
    if not gps or not gps.locate then return nil end
    local ok, x, y, z = pcall(gps.locate, 2, false)
    if not ok or not x then return nil end
    return { x = x, y = y, z = z }
end

function initGPS()
    local here = tryLocate()
    if not here then
        state.hasGPS = false
        state.origin = nil
        return false
    end
    state.hasGPS = true
    state.origin = {
        x = here.x - (state.x or 0),
        y = here.y - (state.y or 0),
        z = here.z - (state.z or 0),
    }
    return true
end

function toAbs(lx, ly, lz)
    if not state.origin then return nil end
    return { x = state.origin.x + lx, y = state.origin.y + ly, z = state.origin.z + lz }
end

function toLocal(ax, ay, az)
    if not state.origin then return nil end
    return { x = ax - state.origin.x, y = ay - state.origin.y, z = az - state.origin.z }
end

function currentAbs()
    return toAbs(state.x, state.y, state.z)
end

-- ============================================================
-- KEY + HELPERS
-- ============================================================

local function keyFor(x, y, z)
    return x .. "_" .. y .. "_" .. z
end

local function now()
    return os.epoch("utc") / 1000
end

local function pruneStale()
    if not state.oreMap then return 0 end
    local t = now()
    local count = 0
    for k, v in pairs(state.oreMap) do
        count = count + 1
        if v.seenAt and (t - v.seenAt) > ORE_TTL_SECONDS then
            state.oreMap[k] = nil
            count = count - 1
        elseif v.claimUntil and t > v.claimUntil then
            v.claimedBy = nil
            v.claimUntil = nil
        end
    end
    return count
end

local function pruneTombstones()
    if not state.oreTombstones then return end
    local t = now()
    for k, tomb in pairs(state.oreTombstones) do
        if (t - (tomb.removedAt or 0)) > TOMBSTONE_TTL then
            state.oreTombstones[k] = nil
        end
    end
end

local function enforceCap()
    if not state.oreMap then return end
    local count = 0
    for _ in pairs(state.oreMap) do count = count + 1 end
    if count <= ORE_MAP_MAX then return end

    local entries = {}
    for k, v in pairs(state.oreMap) do
        table.insert(entries, { key = k, seenAt = v.seenAt or 0 })
    end
    table.sort(entries, function(a, b) return a.seenAt < b.seenAt end)
    for i = 1, count - ORE_MAP_MAX do
        state.oreMap[entries[i].key] = nil
    end
end

function mapSize()
    if not state.oreMap then return 0 end
    local n = 0
    for _ in pairs(state.oreMap) do n = n + 1 end
    return n
end

function tombstoneCount()
    if not state.oreTombstones then return 0 end
    pruneTombstones()
    local n = 0
    for _ in pairs(state.oreTombstones) do n = n + 1 end
    return n
end

-- ============================================================
-- TOMBSTONES
-- Marcan ores ya minados para que sync/broadcast no los
-- re-introduzcan. TTL = 10 min. Si llega un ore con seenAt
-- posterior al tombstone (raro respawn), se acepta.
-- ============================================================

local function recordTombstone(absPos, byId)
    if not absPos then return end
    state.oreTombstones = state.oreTombstones or {}
    state.oreTombstones[keyFor(absPos.x, absPos.y, absPos.z)] = {
        x = absPos.x, y = absPos.y, z = absPos.z,
        removedAt = now(),
        by = byId,
    }
end

local function isTombstoned(absPos, candidateSeenAt)
    if not absPos or not state.oreTombstones then return false end
    local k = keyFor(absPos.x, absPos.y, absPos.z)
    local t = state.oreTombstones[k]
    if not t then return false end
    if (now() - t.removedAt) > TOMBSTONE_TTL then
        state.oreTombstones[k] = nil
        return false
    end
    if candidateSeenAt and candidateSeenAt > t.removedAt then
        state.oreTombstones[k] = nil
        return false
    end
    return true
end

-- ============================================================
-- ORE MAP OPERATIONS
-- ============================================================

-- Registra un ore. Respeta tombstones. seenAtHint permite preservar
-- el timestamp original cuando viene de un sync (si no, se usa now()).
-- Devuelve true si la entrada es nueva o mas reciente.
function recordOre(absPos, name, byId, seenAtHint)
    if not absPos then return false end
    local seenAt = seenAtHint or now()
    if isTombstoned(absPos, seenAt) then return false end

    state.oreMap = state.oreMap or {}
    local k = keyFor(absPos.x, absPos.y, absPos.z)
    local existing = state.oreMap[k]
    if existing then
        if (existing.seenAt or 0) < seenAt then
            existing.seenAt = seenAt
            existing.name = name or existing.name
            return true
        end
        return false
    end
    state.oreMap[k] = {
        x = absPos.x, y = absPos.y, z = absPos.z,
        name = name,
        seenAt = seenAt,
        by = byId,
    }
    pruneStale()
    enforceCap()
    return true
end

-- Elimina un ore (porque lo cavamos o alguien lo cavo).
-- Crea un tombstone para que sync no lo vuelva a introducir.
function forgetOre(absPos, byId)
    if not absPos then return end
    if state.oreMap then
        state.oreMap[keyFor(absPos.x, absPos.y, absPos.z)] = nil
    end
    recordTombstone(absPos, byId)
end

function claimOre(absPos, byId, ttl)
    if not absPos or not state.oreMap then return false end
    local k = keyFor(absPos.x, absPos.y, absPos.z)
    local ore = state.oreMap[k]
    if not ore then return false end
    local t = now()
    if ore.claimedBy and ore.claimedBy ~= byId and ore.claimUntil and t < ore.claimUntil then
        return false
    end
    ore.claimedBy = byId
    ore.claimUntil = t + (ttl or 30)
    return true
end

function nearestUnclaimed(fromAbs, maxDist)
    if not fromAbs or not state.oreMap then return nil end
    pruneStale()
    local best, bestDist = nil, math.huge
    local t = now()
    for _, ore in pairs(state.oreMap) do
        local claimed = ore.claimedBy and ore.claimUntil and t < ore.claimUntil
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
-- DIGEST
-- Resumen compacto del oreMap para que otros peers decidan si
-- tienen algo que aportarnos (comparacion count+latest).
-- ============================================================

function computeDigest()
    local count = 0
    local latest = 0
    if state.oreMap then
        for _, ore in pairs(state.oreMap) do
            count = count + 1
            if (ore.seenAt or 0) > latest then latest = ore.seenAt end
        end
    end
    return { count = count, latest = latest }
end

-- ============================================================
-- BROADCAST HELPERS (delta real-time)
-- ============================================================

function broadcastOreSpotted(localPos, name)
    if not state.hasRemote then return end
    local abs = toAbs(localPos.x, localPos.y, localPos.z)
    if not abs then return end
    local seenAt = now()
    pcall(rednet.broadcast, {
        kind = "ore_spotted",
        pos = abs, name = name, seenAt = seenAt,
        by = os.getComputerID(),
    }, remote.PROTOCOL)
    recordOre(abs, name, os.getComputerID(), seenAt)
end

function broadcastOreGone(localPos)
    if not state.hasRemote then return end
    local abs = toAbs(localPos.x, localPos.y, localPos.z)
    if not abs then return end
    pcall(rednet.broadcast, {
        kind = "ore_gone",
        pos = abs, by = os.getComputerID(),
    }, remote.PROTOCOL)
    forgetOre(abs, os.getComputerID())
end

-- ============================================================
-- PEER REGISTRY
-- ============================================================

local function recordPeer(senderId, data)
    if not data then return end
    state.knownPeers = state.knownPeers or {}
    state.knownPeers[senderId] = {
        id = senderId,
        hostname = data.hostname,
        mode = data.mode,
        abs = data.abs,
        fuel = data.fuel,
        lastSeen = now(),
    }
end

function peerCount()
    if not state.knownPeers then return 0 end
    local n, t = 0, now()
    for _, p in pairs(state.knownPeers) do
        if (t - (p.lastSeen or 0)) < 60 then n = n + 1 end
    end
    return n
end

-- ============================================================
-- SYNC PROTOCOL
-- Flujo:
--   A) Turtle nueva broadcast sync_request + su digest
--   B) Peers con mas/nuevo: envian sync_offer con su digest
--   C) Tras SYNC_OFFER_WAIT segs, turtle nueva elige el mejor
--      y envia sync_ack al elegido
--   D) Elegido envia sync_chunk pages con entradas > requesterLatest
--   E) Ultimo chunk lleva tombstones recientes
-- ============================================================

function startSyncProtocol()
    if not state.hasRemote then return end
    state.syncInFlight = {
        phase = "awaiting_offers",
        startedAt = now(),
        offers = {},
        myDigest = computeDigest(),
    }
    pcall(rednet.broadcast, {
        kind = "sync_request",
        by = os.getComputerID(),
        digest = state.syncInFlight.myDigest,
    }, remote.PROTOCOL)
end

-- Compat: API vieja mantiene el nombre
function requestSync() return startSyncProtocol() end

local function handleSyncRequest(senderId, msg)
    local my = computeDigest()
    local their = msg.digest or { count = 0, latest = 0 }
    -- Solo ofrecemos si tenemos algo que aporta (mas entradas O mas reciente)
    if my.count == 0 then return end
    if my.count <= their.count and my.latest <= their.latest then return end
    pcall(rednet.send, senderId, {
        kind = "sync_offer",
        by = os.getComputerID(),
        to = senderId,
        digest = my,
    }, remote.PROTOCOL)
end

local function handleSyncOffer(senderId, msg)
    local s = state.syncInFlight
    if not s or s.phase ~= "awaiting_offers" then return end
    if msg.to ~= os.getComputerID() then return end
    s.offers[senderId] = msg.digest or { count = 0, latest = 0 }
end

local function pickBestOffer(offers)
    local bestId, bestScore = nil, -1
    for id, d in pairs(offers) do
        -- Score ponderado: count pesa mas que latest
        local score = (d.count or 0) * 1e3 + (d.latest or 0)
        if score > bestScore then
            bestId, bestScore = id, score
        end
    end
    return bestId
end

local function sendDumpChunked(to, requesterLatest, includeTombstones)
    requesterLatest = requesterLatest or 0
    local entries = {}
    if state.oreMap then
        for _, ore in pairs(state.oreMap) do
            if (ore.seenAt or 0) > requesterLatest then
                table.insert(entries, ore)
            end
        end
    end

    local tombs = {}
    if includeTombstones and state.oreTombstones then
        pruneTombstones()
        for k, t in pairs(state.oreTombstones) do
            if (t.removedAt or 0) > requesterLatest then
                tombs[k] = { x = t.x, y = t.y, z = t.z, removedAt = t.removedAt, by = t.by }
            end
        end
    end

    local totalPages = math.max(1, math.ceil(#entries / CHUNK_SIZE))
    for page = 1, totalPages do
        local startIdx = (page - 1) * CHUNK_SIZE + 1
        local endIdx = math.min(page * CHUNK_SIZE, #entries)
        local chunk = {}
        for i = startIdx, endIdx do table.insert(chunk, entries[i]) end
        local msg = {
            kind = "sync_chunk",
            by = os.getComputerID(),
            to = to,
            page = page,
            totalPages = totalPages,
            entries = chunk,
        }
        if page == totalPages and includeTombstones then
            msg.tombstones = tombs
        end
        pcall(rednet.send, to, msg, remote.PROTOCOL)
    end

    if #entries == 0 and includeTombstones then
        -- Mandar aunque sea una pagina vacia con los tombstones
        pcall(rednet.send, to, {
            kind = "sync_chunk",
            by = os.getComputerID(),
            to = to,
            page = 1, totalPages = 1,
            entries = {},
            tombstones = tombs,
        }, remote.PROTOCOL)
    end
end

local function handleSyncAck(senderId, msg)
    if msg.chosen ~= os.getComputerID() then return end
    local requesterLatest = (msg.digest and msg.digest.latest) or 0
    sendDumpChunked(msg.by or senderId, requesterLatest, true)
end

local function handleSyncChunk(senderId, msg)
    if msg.to ~= os.getComputerID() then return end
    -- Merge entradas preservando seenAt original
    for _, ore in ipairs(msg.entries or {}) do
        if ore.x and ore.y and ore.z and ore.name then
            recordOre(ore, ore.name, ore.by, ore.seenAt)
        end
    end
    -- Merge tombstones (last writer wins)
    if msg.tombstones then
        state.oreTombstones = state.oreTombstones or {}
        for k, t in pairs(msg.tombstones) do
            local existing = state.oreTombstones[k]
            if not existing or (existing.removedAt or 0) < (t.removedAt or 0) then
                state.oreTombstones[k] = {
                    x = t.x, y = t.y, z = t.z,
                    removedAt = t.removedAt, by = t.by,
                }
            end
        end
    end
    -- Si es el ultimo chunk de un sync en curso, cerrarlo
    local s = state.syncInFlight
    if s and s.phase == "awaiting_chunks" and msg.by == s.chosen and msg.page == msg.totalPages then
        state.syncInFlight = nil
        state.lastSyncAt = now()
    end
end

-- Compat con protocolo viejo
local function handleLegacySyncDump(senderId, msg)
    if type(msg.oreMap) ~= "table" then return end
    for _, ore in pairs(msg.oreMap) do
        if ore.x and ore.y and ore.z and ore.name then
            recordOre(ore, ore.name, ore.by, ore.seenAt)
        end
    end
end

-- ============================================================
-- GOSSIP
-- Cada GOSSIP_INTERVAL, pick a random peer, mandarle nuestro
-- digest. Si tenemos mas, le mandamos chunks delta.
-- ============================================================

local function sendGossipPing()
    if not state.hasRemote or not state.knownPeers then return end
    local t = now()
    local candidates = {}
    for id, peer in pairs(state.knownPeers) do
        if id ~= os.getComputerID() and (t - (peer.lastSeen or 0)) < 60 then
            table.insert(candidates, id)
        end
    end
    if #candidates == 0 then return end
    local target = candidates[math.random(1, #candidates)]
    pcall(rednet.send, target, {
        kind = "gossip_ping",
        by = os.getComputerID(),
        to = target,
        digest = computeDigest(),
    }, remote.PROTOCOL)
end

local function handleGossipPing(senderId, msg)
    if msg.to and msg.to ~= os.getComputerID() then return end
    local my = computeDigest()
    local their = msg.digest or { count = 0, latest = 0 }
    -- Solo respondemos si tenemos entradas nuevas para ellos
    if my.latest <= their.latest and my.count <= their.count then return end
    sendDumpChunked(senderId, their.latest or 0, true)
end

-- ============================================================
-- TICK
-- Llamado por remote.listener cada ~2s. Avanza el state machine
-- de sync y dispara gossip periodico.
-- ============================================================

function tick()
    local t = now()
    -- Sync state machine
    local s = state.syncInFlight
    if s then
        if s.phase == "awaiting_offers" and (t - s.startedAt) > SYNC_OFFER_WAIT then
            local bestId = pickBestOffer(s.offers)
            if bestId then
                pcall(rednet.send, bestId, {
                    kind = "sync_ack",
                    by = os.getComputerID(),
                    chosen = bestId,
                    digest = s.myDigest,
                }, remote.PROTOCOL)
                s.phase = "awaiting_chunks"
                s.chosen = bestId
                s.ackAt = t
            else
                state.syncInFlight = nil
            end
        elseif s.phase == "awaiting_chunks" and (t - s.ackAt) > SYNC_DUMP_TIMEOUT then
            state.syncInFlight = nil
        end
    end
    -- Gossip tick
    if (t - (state.lastGossip or 0)) > GOSSIP_INTERVAL then
        sendGossipPing()
        state.lastGossip = t
    end
    -- Housekeeping
    pruneTombstones()
end

-- ============================================================
-- MESSAGE ROUTER (llamado desde remote.listener)
-- Devuelve true si consumimos el mensaje (remote no lo procesa mas).
-- ============================================================

function handleSwarmMessage(senderId, msg)
    if type(msg) ~= "table" then return false end
    local k = msg.kind

    if k == "ore_spotted" and msg.pos then
        recordOre(msg.pos, msg.name, msg.by or senderId, msg.seenAt)
        return true
    elseif k == "ore_gone" and msg.pos then
        forgetOre(msg.pos, msg.by or senderId)
        return true
    elseif k == "ore_claim" and msg.pos then
        claimOre(msg.pos, msg.by or senderId, msg.ttl or 30)
        return true
    elseif k == "scan_report" and type(msg.ores) == "table" then
        for _, ore in ipairs(msg.ores) do
            if ore.x and ore.y and ore.z and ore.name then
                recordOre(ore, ore.name, msg.by or senderId, ore.seenAt)
            end
        end
        return true
    elseif k == "sync_request" then
        handleSyncRequest(senderId, msg)
        return true
    elseif k == "sync_offer" then
        handleSyncOffer(senderId, msg)
        return true
    elseif k == "sync_ack" then
        handleSyncAck(senderId, msg)
        return true
    elseif k == "sync_chunk" then
        handleSyncChunk(senderId, msg)
        return true
    elseif k == "sync_dump" then
        -- Compat con protocolo viejo
        handleLegacySyncDump(senderId, msg)
        return true
    elseif k == "gossip_ping" then
        handleGossipPing(senderId, msg)
        return true
    elseif k == "status" and msg.data then
        recordPeer(senderId, msg.data)
        return false -- que el flujo normal de remote tambien lo procese
    end
    return false
end
