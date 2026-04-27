-- ============================================================
-- ROLE CONFIG
-- Persiste el rol del dispositivo y los parametros de cada
-- programa en /role.cfg. Es distinto de /state.dat:
--   /role.cfg  = configuracion estable (se guarda una vez, se
--                sobrescribe solo cuando el usuario re-configura).
--   /state.dat = estado de ejecucion (progreso mid-run para
--                resume, se borra al acabar limpiamente).
--
-- Formato de /role.cfg (textutils.serialize de esta tabla):
-- {
--   role = "mining"|"lumber"|"farmer"|"scout"|"client",
--   deviceType = "turtle"|"pocket"|"computer",
--   mining = { pattern=..., shaftLength=..., ... },
--   lumber = { mode=..., count=..., ... },
--   farmer = { width=..., length=..., ... },
--   scout  = { patrol=..., boxX=..., ... },
-- }
-- ============================================================

local PATH = "/role.cfg"

-- Defaults por programa. Cualquier campo omitido hereda de aqui.
DEFAULTS = {
    mining = {
        pattern       = "branch",
        shaftLength   = 30,
        branchLength  = 8,
        branchSpacing = 3,
        tunnelWidth   = 3,
    },
    lumber = {
        mode      = "grid",
        count     = 4,
        spacing   = 2,
        rows      = 2,          -- 1 = solo derecha, 2 = ambos lados
        bonemeal  = false,
        sleepSecs = 120,
    },
    farmer = {
        width     = 5,
        length    = 5,
        sleepSecs = 600,
    },
    scout = {
        patrol      = "box",      -- "box"|"stationary"|"follow"
        boxX        = 0,
        boxZ        = 0,
        boxW        = 32,
        boxL        = 32,
        scanAltY    = 0,          -- relativo al inicio del scout
        safeAltY    = 20,         -- altura segura de traslado
        scanRadius  = 8,
        stepSpacing = 12,         -- separacion entre scans en box mode
        sleepSecs   = 30,         -- espera entre ciclos completos
    },
    loader = {
        followTarget = "auto",    -- number (id) | string (hostname) | "auto"
        cruiseAltY   = 120,       -- altitud absoluta de vuelo
        chunkPadding = 0,         -- chunks de tolerancia (0 = mismo chunk)
    },
    quarry = {
        mode          = "miner",     -- "miner" | "unloader"
        width         = 8,            -- W: a lo ancho (eje +Z respecto al inicio)
        length        = 8,            -- L: a lo largo (eje +X)
        maxDepth      = 64,           -- 0 = bajar hasta bedrock
        enderSlot     = 1,            -- slot reservado para minecraft:ender_chest
        fuelSlot      = 16,           -- slot reservado para combustible
        dumpThreshold = 13,           -- slots ocupados antes de descargar
        -- unloader-only
        storageSide   = "front",     -- "front"|"back"|"left"|"right"
        sleepSecs     = 5,            -- nap cuando el ender chest viene vacio
    },
    client = {},
}

-- ============================================================
-- DEVICE DETECTION
-- ============================================================

function detectDeviceType()
    if turtle then return "turtle" end
    if pocket then return "pocket" end
    return "computer"
end

-- Roles validos por tipo de dispositivo
function rolesFor(deviceType)
    if deviceType == "turtle" then
        return { "mining", "lumber", "farmer", "scout", "loader", "quarry" }
    end
    return { "client" }
end

-- ============================================================
-- LOAD / SAVE
-- ============================================================

local function mergeDefaults(cfg)
    for key, defaults in pairs(DEFAULTS) do
        cfg[key] = cfg[key] or {}
        for k, v in pairs(defaults) do
            if cfg[key][k] == nil then
                cfg[key][k] = v
            end
        end
    end
    return cfg
end

function load()
    if not fs.exists(PATH) then return nil end
    local f = fs.open(PATH, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    local ok, data = pcall(textutils.unserialize, content)
    if not ok or type(data) ~= "table" then return nil end
    return mergeDefaults(data)
end

function save(cfg)
    if type(cfg) ~= "table" then return false end
    cfg.deviceType = cfg.deviceType or detectDeviceType()
    local ok, serialized = pcall(textutils.serialize, cfg)
    if not ok then return false end
    local f = fs.open(PATH, "w")
    if not f then return false end
    f.write(serialized)
    f.close()
    return true
end

function clear()
    if fs.exists(PATH) then fs.delete(PATH) end
end

function exists()
    return fs.exists(PATH)
end

-- Tabla vacia con defaults para un role nuevo
function blankConfig(role, deviceType)
    local cfg = { role = role, deviceType = deviceType or detectDeviceType() }
    return mergeDefaults(cfg)
end

-- ============================================================
-- APPLY TO _G.state
-- Vuelca la config del rol al state global, de forma que los
-- programas puedan seguir leyendo state.shaftLength etc. como antes.
-- ============================================================

function applyToState(cfg)
    if not cfg or not state then return end
    state.mode = cfg.role

    -- Mining
    local m = cfg.mining or DEFAULTS.mining
    state.pattern       = m.pattern
    state.shaftLength   = m.shaftLength
    state.branchLength  = m.branchLength
    state.branchSpacing = m.branchSpacing
    state.tunnelWidth   = m.tunnelWidth

    -- Lumber
    local l = cfg.lumber or DEFAULTS.lumber
    state.lumberMode      = l.mode
    state.lumberCount     = l.count
    state.lumberSpacing   = l.spacing
    state.lumberRows      = l.rows
    state.useBonemeal     = l.bonemeal
    state.lumberSleepSecs = l.sleepSecs

    -- Farmer
    local f = cfg.farmer or DEFAULTS.farmer
    state.farmWidth     = f.width
    state.farmLength    = f.length
    state.farmSleepSecs = f.sleepSecs

    -- Scout
    local s = cfg.scout or DEFAULTS.scout
    state.scoutPatrol      = s.patrol
    state.scoutBoxX        = s.boxX
    state.scoutBoxZ        = s.boxZ
    state.scoutBoxW        = s.boxW
    state.scoutBoxL        = s.boxL
    state.scoutScanAltY    = s.scanAltY
    state.scoutSafeAltY    = s.safeAltY
    state.scoutScanRadius  = s.scanRadius
    state.scoutStepSpacing = s.stepSpacing
    state.scoutSleepSecs   = s.sleepSecs

    -- Loader (chunky follower)
    local ld = cfg.loader or DEFAULTS.loader
    state.followTarget = ld.followTarget
    state.cruiseAltY   = ld.cruiseAltY
    state.chunkPadding = ld.chunkPadding

    -- Quarry
    local q = cfg.quarry or DEFAULTS.quarry
    state.quarryMode      = q.mode
    state.quarryWidth     = q.width
    state.quarryLength    = q.length
    state.quarryMaxDepth  = q.maxDepth
    state.enderSlot       = q.enderSlot
    state.fuelSlot        = q.fuelSlot
    state.dumpThreshold   = q.dumpThreshold
    state.storageSide     = q.storageSide
    state.unloadSleepSecs = q.sleepSecs
end
