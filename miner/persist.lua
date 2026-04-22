-- ============================================================
-- PERSIST MODULE
-- Guarda/carga el state a disco para poder reanudar tras un
-- apagado, crash o chunk unload.
-- Usa textutils.serialize (format Lua) por simplicidad y
-- tolerancia a tipos como tablas anidadas.
-- ============================================================

local PATH = "/miner/state.dat"

-- Campos que SI se guardan. Los peripherals (userdata) no se serializan.
local PERSIST_FIELDS = {
    "x", "y", "z", "facing",
    "pattern",
    "shaftLength", "branchLength", "branchSpacing",
    "tunnelWidth", "tunnelHeight",
    "blocksMined", "oresFound", "chestsPlaced",
    "currentStep",
    "oresLog",
    "startEpoch",
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
