-- ============================================================
-- TURTLE MULTIPROGRAM v1.2
-- Tres programas sobre la misma base:
--   - mining  : branch / tunnel mining con auto-fuel, cofres y
--               resume tras crash.
--   - lumber  : tala de arboles (grid o single con bonemeal).
--   - farmer  : cultivo automatizado de trigo/zanahoria/patata/
--               remolacha sobre un plot NxM.
-- Target: non-advanced mining turtle (term 39x13, no color).
-- ============================================================

os.loadAPI("lib/ui.lua")
os.loadAPI("lib/persist.lua")
os.loadAPI("lib/config.lua")
os.loadAPI("lib/inventory.lua")
os.loadAPI("lib/movement.lua")
os.loadAPI("lib/peripherals.lua")
os.loadAPI("lib/remote.lua")
os.loadAPI("lib/swarm.lua")
os.loadAPI("mining/mining.lua")
os.loadAPI("lumber/lumber.lua")
os.loadAPI("farmer/farmer.lua")

-- State global accesible por todos los modulos
local function defaultState()
    return {
        -- posicion relativa al inicio (turtle empieza en 0,0,0 mirando +X)
        x = 0, y = 0, z = 0,
        facing = 0, -- 0=+X, 1=+Z, 2=-X, 3=-Z

        -- stats comunes
        blocksMined = 0,
        oresFound = 0,
        chestsPlaced = 0,
        startEpoch = os.epoch("utc"),

        -- que programa correr
        mode = "mining",    -- "mining" | "lumber" | "farmer"

        -- config mining
        pattern = "branch",
        shaftLength = 30,
        branchLength = 8,
        branchSpacing = 3,
        tunnelWidth = 3,
        currentStep = 0,
        oresLog = {},

        -- config lumber
        lumberMode = "grid",        -- "grid" | "single"
        lumberCount = 4,
        lumberSpacing = 2,
        useBonemeal = false,
        lumberSleepSecs = 120,
        logsHarvested = 0,

        -- config farmer
        farmWidth = 5,
        farmLength = 5,
        farmSleepSecs = 600,
        farmRow = 0,
        farmCol = 0,
        farmCycle = 0,
        cropsHarvested = 0,

        -- flags runtime
        resuming = false,

        -- peripherals (no persisten)
        hasEnvDetector = false,
        hasGeoScanner = false,
        envDetector = nil,
        geoScanner = nil,

        -- remote control (no persiste)
        hasRemote = false,
        hostname = nil,
        remoteCmd = nil,

        -- swarm (no persiste)
        hasGPS = false,
        origin = nil,
        oreMap = {},
    }
end

_G.state = defaultState()

local function modeLabel(m)
    if m == "lumber" then return "LUMBER" end
    if m == "farmer" then return "FARMER" end
    return "MINING"
end

local function askResume(saved)
    ui.clear()
    ui.hline(1, "=")
    ui.center(2, "SESION ANTERIOR DETECTADA")
    ui.hline(3, "=")

    local mode = saved.mode or "mining"
    term.setCursorPos(2, 5)
    term.write("Programa: " .. modeLabel(mode))

    term.setCursorPos(2, 6)
    if mode == "lumber" then
        term.write("Config  : "..tostring(saved.lumberMode).." x"..tostring(saved.lumberCount))
    elseif mode == "farmer" then
        term.write("Plot    : "..tostring(saved.farmWidth).."x"..tostring(saved.farmLength)
            .."  ciclo "..tostring(saved.farmCycle or 0))
    else
        term.write("Patron  : "..tostring(saved.pattern)
            .."  "..tostring(saved.currentStep).."/"..tostring(saved.shaftLength))
    end

    term.setCursorPos(2, 7)
    term.write("Pos     : X="..tostring(saved.x).." Y="..tostring(saved.y).." Z="..tostring(saved.z))

    term.setCursorPos(2, 9)
    term.write("IMPORTANTE: la turtle debe estar EN esa")
    term.setCursorPos(2, 10)
    term.write("posicion. Si la moviste, empieza nueva.")
    term.setCursorPos(2, 12)
    term.write("[R] Reanudar  [N] Nueva  [D] Borrar")

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.r then return "resume" end
        if key == keys.n then return "new" end
        if key == keys.d then return "delete" end
    end
end

local function dispatchProgram()
    if state.mode == "lumber" then
        lumber.run()
    elseif state.mode == "farmer" then
        farmer.run()
    else
        mining.run()
    end
end

local function main()
    ui.clear()
    ui.splash()

    -- Detectar sesion anterior
    local saved = persist.load()
    if saved then
        local choice = askResume(saved)
        if choice == "resume" then
            for k, v in pairs(saved) do
                state[k] = v
            end
            state.resuming = true
        else
            persist.clear()
        end
    end

    peripherals.detect()
    remote.init()

    if state.hasRemote then
        swarm.initGPS()
        swarm.requestSync()
    end

    if not state.resuming then
        config.runMenu()
    end

    -- Programa + listener rednet en paralelo.
    if state.hasRemote then
        parallel.waitForAny(
            function() dispatchProgram() end,
            function() remote.listener() end
        )
        remote.shutdown()
    else
        dispatchProgram()
    end

    ui.finalReport()
end

local ok, err = pcall(main)
if not ok then
    ui.clear()
    print("ERROR FATAL:")
    print(err)
    print("")
    print("Posicion estimada: x="..state.x.." y="..state.y.." z="..state.z)
    print("El checkpoint se conserva para reanudar.")
    print("")
    print("Pulsa cualquier tecla para salir.")
    os.pullEvent("key")
end
