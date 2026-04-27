-- ============================================================
-- TURTLE MULTIPROGRAM v1.3
-- Dispatcher unico. Detecta el tipo de dispositivo (turtle /
-- pocket / computer), lee /role.cfg y arranca directamente el
-- programa asignado. Si no hay config, abre el wizard.
--
-- Roles soportados:
--   turtle    : mining | lumber | farmer | scout
--   pocket    : client
--   computer  : client
--
-- Resume: si /state.dat existe (ejecucion previa sin cierre
-- limpio) el programa ofrece reanudar.
-- ============================================================

os.loadAPI("lib/ui.lua")
os.loadAPI("lib/roleconfig.lua")
os.loadAPI("lib/persist.lua")
os.loadAPI("lib/inventory.lua")
os.loadAPI("lib/movement.lua")
os.loadAPI("lib/peripherals.lua")
os.loadAPI("lib/remote.lua")
os.loadAPI("lib/swarm.lua")
os.loadAPI("lib/localctrl.lua")
os.loadAPI("lib/config.lua")
if turtle then
    os.loadAPI("mining/mining.lua")
    os.loadAPI("lumber/lumber.lua")
    os.loadAPI("farmer/farmer.lua")
    os.loadAPI("scout/scout.lua")
    os.loadAPI("loader/loader.lua")
    os.loadAPI("quarry/quarry.lua")
end

-- ============================================================
-- STATE
-- ============================================================

local function defaultState()
    return {
        -- posicion relativa al inicio
        x = 0, y = 0, z = 0, facing = 0,

        -- stats comunes
        blocksMined = 0, oresFound = 0, chestsPlaced = 0,
        startEpoch = os.epoch("utc"),

        -- rol (se sobrescribe desde /role.cfg)
        mode = "mining",

        -- stats especificas (se incrementan en runtime)
        currentStep = 0,
        oresLog = {},
        logsHarvested = 0,
        farmRow = 0, farmCol = 0, farmCycle = 0,
        cropsHarvested = 0,
        scansDone = 0,

        -- runtime flags
        resuming = false,

        -- peripherals (no persisten)
        hasEnvDetector = false, hasGeoScanner = false,
        envDetector = nil, geoScanner = nil,

        -- remote (no persiste)
        hasRemote = false, hostname = nil, remoteCmd = nil,

        -- swarm (no persiste)
        hasGPS = false, origin = nil, oreMap = {},
    }
end

_G.state = defaultState()

-- ============================================================
-- RESUME PROMPT
-- ============================================================

local function modeLabel(m)
    local labels = { mining = "MINING", lumber = "LUMBER", farmer = "FARMER",
        scout = "SCOUT", loader = "LOADER", quarry = "QUARRY", client = "CLIENT" }
    return labels[m] or "?"
end

local function askResume(saved)
    ui.clear()
    ui.hline(1, "=")
    ui.center(2, "SESION ANTERIOR DETECTADA")
    ui.hline(3, "=")

    local m = saved.mode or "mining"
    term.setCursorPos(2, 5); term.write("Programa: " .. modeLabel(m))

    term.setCursorPos(2, 6)
    if m == "lumber" then
        term.write("Config  : " .. tostring(saved.lumberMode) .. " x" .. tostring(saved.lumberCount))
    elseif m == "farmer" then
        term.write("Plot    : " .. tostring(saved.farmWidth) .. "x" .. tostring(saved.farmLength)
            .. "  ciclo " .. tostring(saved.farmCycle or 0))
    elseif m == "scout" then
        term.write("Scout   : " .. tostring(saved.scoutPatrol or "?")
            .. "  scans=" .. tostring(saved.scansDone or 0))
    elseif m == "quarry" then
        local ph = saved.quarryPhase or "mine"
        if ph == "mine" then
            term.write("Layer " .. tostring(saved.quarryLayer or 0)
                .. "  fila " .. tostring(saved.quarryRow or 0)
                .. " col " .. tostring(saved.quarryCol or 0))
        elseif ph == "lift" then
            term.write("Lift: quedan " .. tostring(saved.dropChests and #saved.dropChests or 0) .. " cofres")
        elseif ph == "consolidate" then
            term.write("Consolidate: fila " .. tostring(saved.surfaceFila or 0))
        else
            term.write("Phase: " .. tostring(ph))
        end
    else
        term.write("Patron  : " .. tostring(saved.pattern)
            .. "  " .. tostring(saved.currentStep) .. "/" .. tostring(saved.shaftLength))
    end

    term.setCursorPos(2, 7)
    term.write("Pos     : X=" .. tostring(saved.x) .. " Y=" .. tostring(saved.y) .. " Z=" .. tostring(saved.z))

    term.setCursorPos(2, 9);  term.write("IMPORTANTE: la turtle debe estar EN esa")
    term.setCursorPos(2, 10); term.write("posicion. Si la moviste, empieza nueva.")
    term.setCursorPos(2, 12); term.write("[R] Reanudar  [N] Nueva  [D] Borrar")

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.r then return "resume" end
        if key == keys.n then return "new" end
        if key == keys.d then return "delete" end
    end
end

-- ============================================================
-- DISPATCH POR ROL
-- ============================================================

local function dispatchRole(role)
    if role == "lumber" then
        lumber.run()
    elseif role == "farmer" then
        farmer.run()
    elseif role == "scout" then
        scout.run()
    elseif role == "loader" then
        loader.run()
    elseif role == "quarry" then
        quarry.run()
    elseif role == "client" then
        -- Cargar y ejecutar client.lua directamente
        shell.run("/client.lua")
    else
        mining.run()
    end
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
    local deviceType = roleconfig.detectDeviceType()

    ui.clear()
    ui.splash()

    -- 1. Cargar config persistente (rol + params)
    local cfg = roleconfig.load()

    -- Primer boot: wizard. Pocket/computer default = client.
    if not cfg or not cfg.role then
        if deviceType ~= "turtle" then
            -- Para pocket/computer, auto-asignamos client sin preguntar
            cfg = roleconfig.blankConfig("client", deviceType)
            cfg.role = "client"
            roleconfig.save(cfg)
        else
            cfg = config.wizardFromScratch()
        end
    end

    roleconfig.applyToState(cfg)

    -- 2. Client: no tiene runtime state, despachar directo
    if cfg.role == "client" then
        dispatchRole("client")
        return
    end

    -- 3. Turtle roles: revisar resume mid-run
    local saved = persist.load()
    if saved and saved.mode and saved.mode ~= cfg.role then
        -- El rol cambio desde la ultima sesion. El state.dat es de otro
        -- programa y no tiene sentido reanudar.
        persist.clear()
        saved = nil
    end
    if saved then
        local choice = askResume(saved)
        if choice == "resume" then
            -- El state runtime (x/y/z/counters/currentStep) se sobreescribe
            for k, v in pairs(saved) do
                state[k] = v
            end
            state.resuming = true
        elseif choice == "delete" then
            -- Borrar checkpoint Y config, volver a preguntar todo
            persist.clear()
            roleconfig.clear()
            _G.state = defaultState()
            cfg = config.wizardFromScratch()
            roleconfig.applyToState(cfg)
        else
            -- "new": limpia checkpoint pero conserva la config
            persist.clear()
        end
    end

    -- 4. Peripherals + remote + swarm
    peripherals.detect()
    remote.init()
    if state.hasRemote then
        swarm.initGPS()
        swarm.requestSync()
    end

    -- 5. Ejecutar programa + listeners en paralelo
    -- localctrl corre siempre (control por teclado pegado a la turtle),
    -- remote.listener solo si hay modem. Cada coroutine tiene su propia
    -- cola de eventos (ver docs de parallel) asi que no compiten.
    if state.hasRemote then
        parallel.waitForAny(
            function() dispatchRole(cfg.role) end,
            function() remote.listener() end,
            function() localctrl.listener() end
        )
        remote.shutdown()
    else
        parallel.waitForAny(
            function() dispatchRole(cfg.role) end,
            function() localctrl.listener() end
        )
    end

    ui.finalReport()
end

local ok, err = pcall(main)
if not ok then
    ui.clear()
    print("ERROR FATAL:")
    print(err)
    print("")
    if state then
        print("Posicion estimada: x="..state.x.." y="..state.y.." z="..state.z)
        print("El checkpoint se conserva para reanudar.")
    end
    print("")
    print("Pulsa cualquier tecla para salir.")
    os.pullEvent("key")
end
