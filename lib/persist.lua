-- ============================================================
-- PERSIST MODULE
-- Guarda/carga el state a disco para poder reanudar tras un
-- apagado, crash o chunk unload.
-- Usa textutils.serialize (format Lua) por simplicidad y
-- tolerancia a tipos como tablas anidadas.
-- ============================================================

local PATH = "/state.dat"

-- Campos que SI se guardan. Los peripherals (userdata) no se serializan.
-- /state.dat = runtime progress (para resume tras crash).
-- La config de cada rol vive en /role.cfg (ver lib/roleconfig.lua)
-- y se carga antes que esto; aqui solo guardamos lo que cambia
-- durante la ejecucion y hace falta para reanudar en el mismo punto.
local PERSIST_FIELDS = {
    -- posicion / orientacion
    "x", "y", "z", "facing",
    "mode",
    -- stats comunes
    "blocksMined", "oresFound", "chestsPlaced",
    "startEpoch",
    -- mining runtime
    "currentStep",
    "sliceLane", "passFacing",
    "oresLog",
    -- lumber runtime
    "logsHarvested",
    -- farmer runtime
    "farmRow", "farmCol", "farmCycle", "cropsHarvested",
    -- scout runtime
    "scansDone",
    -- quarry runtime
    "quarryMode",
    "quarryRow", "quarryCol", "quarryLayer",
    "quarryDirection", "quarryRowDir", "quarryDone",
    "unloadCycles", "unloadStuck",
}

function save()
    if not state then return false end
    local snapshot = {}
    for _, k in ipairs(PERSIST_FIELDS) do
        snapshot[k] = state[k]
    end
    local ok, serialized = pcall(textutils.serialize, snapshot)
    if not ok then return false end
    local f = fs.open(PATH, "w")
    if not f then return false end
    f.write(serialized)
    f.close()
    return true
end

function load()
    if not fs.exists(PATH) then return nil end
    local f = fs.open(PATH, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    local ok, data = pcall(textutils.unserialize, content)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

function clear()
    if fs.exists(PATH) then
        fs.delete(PATH)
    end
end

function exists()
    return fs.exists(PATH)
end
