-- ============================================================
-- REMOTE MODULE
-- Rednet listener para control remoto desde otra computer.
--
-- Protocolo: "turtle_miner"
-- Hostname : "miner-" + os.getComputerID()
--
-- Mensajes cliente -> turtle:
--   { action = "status" }      -- responde con snapshot
--   { action = "pause"  }
--   { action = "resume" }
--   { action = "home"   }      -- aborta y vuelve al origen
--   { action = "stop"   }      -- aborta y guarda checkpoint
--   { action = "ping"   }
--
-- Mensajes turtle -> cliente (broadcast cada 5s y on-demand):
--   { kind = "status", data = {...} }
--   { kind = "ack",    action = "pause" }
--   { kind = "event",  type = "ore",  name = "...", y = ... }
-- ============================================================

PROTOCOL = "turtle_miner"
local BROADCAST_INTERVAL = 5 -- segundos entre pushes automaticos

local modemSide = nil

-- ============================================================
-- INIT
-- Busca un modem (upgrade o peripheral externo), abre rednet,
-- se registra con host() para discovery via rednet.lookup.
-- ============================================================

function init()
    for _, side in ipairs({ "left", "right", "top", "bottom", "front", "back" }) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            modemSide = side
            state.hasRemote = true
            state.hostname = "miner-" .. os.getComputerID()
            pcall(rednet.host, PROTOCOL, state.hostname)
            return true
        end
    end
    state.hasRemote = false
    return false
end

function shutdown()
    if not state.hasRemote then return end
    pcall(rednet.unhost, PROTOCOL)
    if modemSide then
        pcall(rednet.close, modemSide)
    end
end

-- ============================================================
-- SNAPSHOT
-- Empaqueta campos seguros de _G.state para enviar al cliente.
-- Excluye userdata (peripherals) que no se puede serializar.
-- ============================================================

function snapshot()
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then fuel = -1 end
    local used = 0
    pcall(function() used = inventory.slotsUsed() end)
    local abs = nil
    if swarm and swarm.currentAbs then
        pcall(function() abs = swarm.currentAbs() end)
    end
    local mapSize = 0
    if swarm and swarm.mapSize then
        pcall(function() mapSize = swarm.mapSize() end)
    end
    return {
        hostname      = state.hostname,
        mode          = state.mode or "mining",
        x             = state.x,
        y             = state.y,
        z             = state.z,
        facing        = state.facing,
        abs           = abs,                   -- coords absolutas si hay GPS
        origin        = state.origin,
        hasGPS        = state.hasGPS == true,
        fuel          = fuel,
        -- mining
        pattern       = state.pattern,
        currentStep   = state.currentStep or 0,
        shaftLength   = state.shaftLength,
        branchLength  = state.branchLength,
        branchSpacing = state.branchSpacing,
        tunnelWidth   = state.tunnelWidth,
        blocksMined   = state.blocksMined,
        oresFound     = state.oresFound,
        chestsPlaced  = state.chestsPlaced,
        sliceLane     = state.sliceLane or 0,
        oreMapSize    = mapSize,
        -- lumber
        lumberMode    = state.lumberMode,
        lumberCount   = state.lumberCount,
        lumberSpacing = state.lumberSpacing,
        useBonemeal   = state.useBonemeal,
        logsHarvested = state.logsHarvested or 0,
        -- farmer
        farmWidth      = state.farmWidth,
        farmLength     = state.farmLength,
        farmCycle      = state.farmCycle or 0,
        farmRow        = state.farmRow or 0,
        cropsHarvested = state.cropsHarvested or 0,
        -- scout
        scoutPatrol    = state.scoutPatrol,
        scansDone      = state.scansDone or 0,
        scanRadius     = state.scoutScanRadius,
        -- loader
        followTarget   = state.followTarget,
        liveTargetId   = state.liveTargetId,
        cruiseAltY     = state.cruiseAltY,
        chunkPadding   = state.chunkPadding,
        lastTargetAt   = state.lastTargetAt,
        lastTargetAbs  = state.lastTargetAbs,
        -- quarry
        quarryMode     = state.quarryMode,
        quarryWidth    = state.quarryWidth,
        quarryLength   = state.quarryLength,
        quarryMaxDepth = state.quarryMaxDepth,
        quarryLayer    = state.quarryLayer or 0,
        quarryRow      = state.quarryRow or 0,
        quarryCol      = state.quarryCol or 0,
        quarryDone     = state.quarryDone == true,
        unloadCycles   = state.unloadCycles or 0,
        unloadStuck    = state.unloadStuck == true,
        storageSide    = state.storageSide,
        -- swarm P2P health
        tombstones    = (swarm and swarm.tombstoneCount) and swarm.tombstoneCount() or 0,
        peers         = (swarm and swarm.peerCount) and swarm.peerCount() or 0,
        lastSyncAt    = state.lastSyncAt,
        syncPhase     = state.syncInFlight and state.syncInFlight.phase or nil,
        -- comunes
        slotsUsed     = used,
        remoteCmd     = state.remoteCmd,
        startEpoch    = state.startEpoch,
    }
end

-- ============================================================
-- HANDLERS
-- ============================================================

local function reply(id, payload)
    pcall(rednet.send, id, payload, PROTOCOL)
end

function handleMessage(senderId, msg)
    if type(msg) ~= "table" then return end

    -- Primero: mensajes swarm (peer-to-peer entre turtles)
    if swarm and swarm.handleSwarmMessage then
        local handled = false
        pcall(function() handled = swarm.handleSwarmMessage(senderId, msg) end)
        if handled then return end
    end

    local action = msg.action
    if action == "status" or action == "ping" then
        reply(senderId, { kind = "status", data = snapshot() })
    elseif action == "pause" then
        state.remoteCmd = "pause"
        reply(senderId, { kind = "ack", action = "pause" })
    elseif action == "resume" then
        state.remoteCmd = "resume"
        reply(senderId, { kind = "ack", action = "resume" })
    elseif action == "home" then
        state.remoteCmd = "home"
        reply(senderId, { kind = "ack", action = "home" })
    elseif action == "stop" then
        state.remoteCmd = "stop"
        reply(senderId, { kind = "ack", action = "stop" })
    elseif action == "follow" then
        -- Cambio de target para el rol loader. Persiste en /role.cfg
        -- para que sobreviva reinicios.
        if msg.auto then
            state.followTarget = "auto"
        elseif msg.targetId == nil then
            state.followTarget = nil
        else
            state.followTarget = msg.targetId
        end
        state.liveTargetId = nil
        pcall(function()
            local cfg = roleconfig.load()
            if cfg then
                cfg.loader = cfg.loader or {}
                cfg.loader.followTarget = state.followTarget or "auto"
                roleconfig.save(cfg)
            end
        end)
        reply(senderId, { kind = "ack", action = "follow", target = state.followTarget })
    end
end

-- ============================================================
-- EVENT HELPERS (la turtle puede notificar eventos puntuales)
-- ============================================================

function notifyEvent(evType, payload)
    if not state.hasRemote then return end
    local msg = { kind = "event", type = evType, data = payload }
    pcall(rednet.broadcast, msg, PROTOCOL)
end

-- ============================================================
-- LISTENER LOOP
-- Se ejecuta en paralelo con la mineria (parallel.waitForAny).
-- Usa timeout corto en rednet.receive para poder hacer
-- broadcasts periodicos incluso cuando no hay comandos.
-- ============================================================

function listener()
    if not state.hasRemote then return end

    local lastBroadcast = os.epoch("utc") / 1000

    while true do
        local id, msg, protocol = rednet.receive(PROTOCOL, 2)
        if id then
            handleMessage(id, msg)
        end

        local now = os.epoch("utc") / 1000
        if now - lastBroadcast >= BROADCAST_INTERVAL then
            pcall(rednet.broadcast, { kind = "status", data = snapshot() }, PROTOCOL)
            lastBroadcast = now
        end

        -- Tick del swarm (avanza sync state machine + gossip periodico)
        if swarm and swarm.tick then
            pcall(swarm.tick)
        end
    end
end
