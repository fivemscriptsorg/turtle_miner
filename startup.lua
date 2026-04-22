-- ============================================================
-- TURTLE MINER v1.1
-- Branch mining 3x3 con auto-fuel, cofres inteligentes,
-- Environment Detector, Geo Scanner opcional, y resume tras crash.
-- Target: non-advanced mining turtle (term 39x13, no color).
-- ============================================================

os.loadAPI("miner/ui.lua")
os.loadAPI("miner/persist.lua")
os.loadAPI("miner/config.lua")
os.loadAPI("miner/inventory.lua")
os.loadAPI("miner/movement.lua")
os.loadAPI("miner/peripherals.lua")
os.loadAPI("miner/remote.lua")
os.loadAPI("miner/mining.lua")

-- State global accesible por todos los modulos
local function defaultState()
    return {
        -- posicion relativa al inicio (turtle empieza en 0,0,0 mirando +X)
        x = 0, y = 0, z = 0,
        facing = 0, -- 0=+X, 1=+Z, 2=-X, 3=-Z

        -- stats
        blocksMined = 0,
        oresFound = 0,
        chestsPlaced = 0,
        startEpoch = os.epoch("utc"),

        -- config (se llena desde el menu o desde state.dat)
        pattern = "branch",
        shaftLength = 30,
        branchLength = 8,
        branchSpacing = 3,
        tunnelWidth = 3,

        -- progreso (para resume)
        currentStep = 0,

        -- registros
        oresLog = {},

        -- flags runtime
        resuming = false,

        -- peripherals (se rellenan en peripherals.detect, no persisten)
        hasEnvDetector = false,
        hasGeoScanner = false,
        envDetector = nil,
        geoScanner = nil,

        -- remote control (se rellena en remote.init, no persiste)
        hasRemote = false,
        hostname = nil,
        remoteCmd = nil,
    }
end

_G.state = defaultState()

local function askResume(saved)
    ui.clear()
    ui.hline(1, "=")
    ui.center(2, "SESION ANTERIOR DETECTADA")
    ui.hline(3, "=")
    term.setCursorPos(2, 5)
    term.write("Patron : " .. tostring(saved.pattern))
    term.setCursorPos(2, 6)
    term.write("Paso   : " .. tostring(saved.currentStep) .. "/" .. tostring(saved.shaftLength))
    term.setCursorPos(2, 7)
    term.write("Pos    : X="..tostring(saved.x).." Y="..tostring(saved.y).." Z="..tostring(saved.z))
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

    if not state.resuming then
        config.runMenu()
    end

    -- Mineria + listener rednet en paralelo.
    -- waitForAny termina en cuanto mining.run vuelve (listener es un loop
    -- infinito y solo muere cuando el parallel lo mata).
    if state.hasRemote then
        parallel.waitForAny(
            function() mining.run() end,
            function() remote.listener() end
        )
        remote.shutdown()
    else
        mining.run()
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
