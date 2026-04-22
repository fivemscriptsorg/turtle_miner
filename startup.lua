-- ============================================================
-- TURTLE MINER v1.0
-- Branch mining 3x3 with auto-fuel, smart chest placement,
-- Environment Detector support and optional Geo Scanner.
-- Target: non-advanced mining turtle (term 39x13, no color).
-- ============================================================

os.loadAPI("miner/config.lua")
os.loadAPI("miner/ui.lua")
os.loadAPI("miner/inventory.lua")
os.loadAPI("miner/movement.lua")
os.loadAPI("miner/peripherals.lua")
os.loadAPI("miner/mining.lua")

-- State global accesible por todos los modulos
_G.state = {
    -- posicion relativa al punto de inicio (la turtle empieza en 0,0,0 mirando +X)
    x = 0, y = 0, z = 0,
    facing = 0, -- 0=+X (frente), 1=+Z (derecha), 2=-X (atras), 3=-Z (izquierda)

    -- stats
    blocksMined = 0,
    oresFound = 0,
    chestsPlaced = 0,
    startTime = os.clock(),

    -- config (se llena desde el menu)
    shaftLength = 30,      -- longitud del tunel principal
    branchLength = 8,      -- longitud de cada rama lateral
    branchSpacing = 3,     -- cada cuantos bloques sale una rama
    tunnelHeight = 3,      -- 3 = 3x3, 2 = 2x3
    tunnelWidth = 3,

    -- registros detectados
    oresLog = {},

    -- peripherals
    hasEnvDetector = false,
    hasGeoScanner = false,
    envDetector = nil,
    geoScanner = nil,
}

local function main()
    ui.clear()
    ui.splash()
    peripherals.detect()
    config.runMenu()
    mining.run()
    ui.finalReport()
end

local ok, err = pcall(main)
if not ok then
    ui.clear()
    print("ERROR FATAL:")
    print(err)
    print("")
    print("Posicion estimada: x="..state.x.." y="..state.y.." z="..state.z)
    print("Pulsa cualquier tecla para salir.")
    os.pullEvent("key")
end
