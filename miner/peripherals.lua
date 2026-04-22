-- ============================================================
-- PERIPHERALS MODULE
-- Detecta Environment Detector y Geo Scanner (Advanced Peripherals).
-- Funciona tanto si son peripherals externos conectados como
-- upgrades de la turtle.
-- ============================================================

-- Busca un peripheral por multiples nombres posibles
local function findAny(names)
    for _, n in ipairs(names) do
        local p = peripheral.find(n)
        if p then return p, n end
    end
    -- busqueda por lado (por si es un upgrade de la turtle)
    for _, side in ipairs({"left", "right", "front", "back", "top", "bottom"}) do
        local pType = peripheral.getType(side)
        if pType then
            for _, n in ipairs(names) do
                if pType == n or pType:lower():find(n:lower()) then
                    return peripheral.wrap(side), pType
                end
            end
        end
    end
    return nil
end

function detect()
    -- Environment Detector
    local env = findAny({ "environmentDetector", "environment_detector" })
    if env then
        state.hasEnvDetector = true
        state.envDetector = env
    end

    -- Geo Scanner (compat: puede no existir todavia, el codigo tiene que aguantar)
    local geo = findAny({ "geoScanner", "geo_scanner" })
    if geo then
        state.hasGeoScanner = true
        state.geoScanner = geo
    end
end

-- ============================================================
-- ENVIRONMENT DETECTOR HELPERS
-- ============================================================

function getBiome()
    if not state.hasEnvDetector then return nil end
    local ok, biome = pcall(state.envDetector.getBiome)
    if ok then return biome end
    return nil
end

function isDangerousBiome()
    local biome = getBiome()
    if not biome then return false end
    -- biomas con lava/peligro donde deberiamos ir con cuidado
    local danger = {
        ["minecraft:nether_wastes"] = true,
        ["minecraft:basalt_deltas"] = true,
        ["minecraft:soul_sand_valley"] = true,
        ["minecraft:warped_forest"] = true,
        ["minecraft:crimson_forest"] = true,
    }
    return danger[biome] == true
end

-- Escanea entidades cercanas para detectar mobs hostiles
function scanForMobs(range)
    if not state.hasEnvDetector then return {} end
    range = range or 4
    local ok, entities = pcall(state.envDetector.scanEntities, range)
    if not ok or not entities then return {} end

    local hostile = {}
    local hostileNames = {
        "zombie", "skeleton", "creeper", "spider", "enderman",
        "witch", "pillager", "vindicator", "warden", "piglin"
    }
    for _, ent in ipairs(entities) do
        local name = (ent.name or ""):lower()
        for _, h in ipairs(hostileNames) do
            if name:find(h) then
                table.insert(hostile, ent)
                break
            end
        end
    end
    return hostile
end

-- ============================================================
-- GEO SCANNER HELPERS
-- ============================================================

-- Lista de nombres de ores (vanilla + deepslate) que nos interesan
local ORE_NAMES = {
    "minecraft:coal_ore",             "minecraft:deepslate_coal_ore",
    "minecraft:iron_ore",             "minecraft:deepslate_iron_ore",
    "minecraft:copper_ore",           "minecraft:deepslate_copper_ore",
    "minecraft:gold_ore",             "minecraft:deepslate_gold_ore",
    "minecraft:redstone_ore",         "minecraft:deepslate_redstone_ore",
    "minecraft:lapis_ore",            "minecraft:deepslate_lapis_ore",
    "minecraft:diamond_ore",          "minecraft:deepslate_diamond_ore",
    "minecraft:emerald_ore",          "minecraft:deepslate_emerald_ore",
    "minecraft:nether_quartz_ore",    "minecraft:nether_gold_ore",
    "minecraft:ancient_debris",
}

local ORE_SET = {}
for _, n in ipairs(ORE_NAMES) do ORE_SET[n] = true end

function isOreName(name)
    if not name then return false end
    return ORE_SET[name] == true or name:find("_ore$") ~= nil or name == "minecraft:ancient_debris"
end

-- Escanea ores en un radio. Devuelve lista de {name, x, y, z} relativos al geo scanner.
-- Si no hay geo scanner devuelve nil. Maneja cooldown silenciosamente.
function scanOres(radius)
    if not state.hasGeoScanner then return nil end
    radius = radius or 8

    -- respetar cooldown
    local ok, cd = pcall(state.geoScanner.getScanCooldown)
    if ok and cd and cd > 0 then
        return nil -- no es error, solo saltamos este scan
    end

    -- verificar fuel del geo scanner
    local okFuel, fuel = pcall(state.geoScanner.getFuelLevel)
    if okFuel and fuel then
        local okCost, cost = pcall(state.geoScanner.cost, radius)
        if okCost and cost and fuel < cost then
            return nil -- no hay energia suficiente
        end
    end

    local ok2, blocks = pcall(state.geoScanner.scan, radius)
    if not ok2 or not blocks then return nil end

    local ores = {}
    for _, b in ipairs(blocks) do
        if isOreName(b.name) then
            table.insert(ores, b)
        end
    end
    return ores
end

-- Devuelve el ore mas cercano al origen del scan, si hay alguno
function nearestOre(radius)
    local ores = scanOres(radius)
    if not ores or #ores == 0 then return nil end
    local best, bestDist = nil, math.huge
    for _, o in ipairs(ores) do
        local d = math.abs(o.x) + math.abs(o.y) + math.abs(o.z)
        if d < bestDist then
            bestDist = d
            best = o
        end
    end
    return best, bestDist
end
