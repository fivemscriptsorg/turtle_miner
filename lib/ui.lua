-- ============================================================
-- UI MODULE
-- Dashboard compatible con turtle normal (sin color, 39x13).
--
-- Layout del dashboard (13 filas):
--   1  ======================================
--   2  header: nombre, modo, tiempo, spinner
--   3  ======================================
--   4  Fuel  [####----------]  xx%
--   5  Prog  [######--------]  n/N    (mode-aware)
--   6  Pos   (x,y,z) FACING
--   7  Lane  L  [C]  R        (solo mining)
--   8  Stats ...
--   9  Per   [EnvD][Geo][Rem][GPS]
--  10  --------------------------------------
--  11  >> Status text
--  12  ~ last event
--  13  [P]ause [R]esume [H]ome [S]top [Spc]
-- ============================================================

local w, h = term.getSize()

-- Ring buffer para eventos recientes (ores encontrados, comandos, etc).
-- Se dibuja en la fila 12 del dashboard.
local EVENT_LOG_MAX = 6
local eventLog = {}

-- Spinner. Avanza con cada drawDashboard para dar sensacion de vida.
local SPIN = { "|", "/", "-", "\\" }
local spinIdx = 1

-- ============================================================
-- PRIMITIVES
-- ============================================================

function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

function center(y, text)
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, y)
    term.write(text)
end

function hline(y, char)
    char = char or "-"
    term.setCursorPos(1, y)
    term.write(string.rep(char, w))
end

local function writeAt(x, y, text)
    term.setCursorPos(x, y)
    term.write(text)
end

local function clearLine(y)
    term.setCursorPos(1, y)
    term.write(string.rep(" ", w))
end

-- ============================================================
-- SPLASH
-- ============================================================

function splash()
    clear()
    local art = {
        "+-----------------------------------+",
        "|                                   |",
        "|   ##### ##  ## ##### ##### #####  |",
        "|   ##    ### ## ##    ##    ##  #  |",
        "|   ##### ## ### ####  ##### #####  |",
        "|      ## ##  ## ##    ##    ## ##  |",
        "|   ##### ##  ## ##### ##### ##  #  |",
        "|                                   |",
        "|       T U R T L E   M I N E R     |",
        "|             v 1.1                 |",
        "+-----------------------------------+",
    }
    for i, line in ipairs(art) do
        center(i, line)
    end
    center(h, "Iniciando... (pulsa tecla)")
    parallel.waitForAny(
        function() sleep(1.2) end,
        function() os.pullEvent("key") end
    )
end

-- ============================================================
-- MENUS / INPUT
-- ============================================================

function menu(title, options, defaultIdx)
    local selected = defaultIdx or 1
    while true do
        clear()
        hline(1, "=")
        center(2, title)
        hline(3, "=")

        for i, opt in ipairs(options) do
            term.setCursorPos(3, 3 + i)
            if i == selected then
                term.write("> " .. opt.label)
            else
                term.write("  " .. opt.label)
            end
        end

        term.setCursorPos(2, h - 1)
        term.write("[Up/Down] mover  [Enter] selec")

        local _, key = os.pullEvent("key")
        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = #options end
        elseif key == keys.down then
            selected = selected + 1
            if selected > #options then selected = 1 end
        elseif key == keys.enter then
            return options[selected].value, selected
        end
    end
end

function promptNumber(title, default, min, max)
    clear()
    hline(1, "=")
    center(2, title)
    hline(3, "=")
    term.setCursorPos(2, 5)
    term.write("Valor (min="..min..", max="..max..")")
    term.setCursorPos(2, 6)
    term.write("Default: "..default.." (Enter = default)")
    term.setCursorPos(2, 8)
    term.write("> ")

    local input = read()
    if input == "" then return default end
    local n = tonumber(input)
    if not n or n < min or n > max then
        term.setCursorPos(2, 10)
        term.write("Valor invalido, usando default.")
        sleep(1)
        return default
    end
    return math.floor(n)
end

-- ============================================================
-- EVENT TICKER
-- ============================================================

function pushEvent(text)
    if type(text) ~= "string" or text == "" then return end
    local maxLen = w - 3
    if #text > maxLen then text = text:sub(1, maxLen) end
    table.insert(eventLog, text)
    while #eventLog > EVENT_LOG_MAX do
        table.remove(eventLog, 1)
    end
    -- refresco de la fila de ultimo evento sin redraw completo
    clearLine(12)
    writeAt(1, 12, " ~ " .. text)
end

-- Flash: banner prominente + status breve.
-- No bloquea: el siguiente setStatus o drawDashboard lo reemplaza.
function flash(text, _secs)
    if not text then return end
    clearLine(11)
    writeAt(1, 11, " >> " .. text:sub(1, w - 4))
end

-- ============================================================
-- DASHBOARD HELPERS
-- ============================================================

local MODE_LABEL = {
    mining = "MINING", lumber = "LUMBER",
    farmer = "FARMER", scout  = "SCOUT",
}

local FACING_LABEL = { [0] = "+X", [1] = "+Z", [2] = "-X", [3] = "-Z" }

local function barStr(pct, len)
    len = len or 10
    pct = math.max(0, math.min(1, pct or 0))
    local f = math.floor(pct * len + 0.5)
    return "[" .. string.rep("#", f) .. string.rep("-", len - f) .. "]"
end

local function laneGlyph(lane)
    lane = lane or 0
    if lane < 0 then return "[L]  C   R " end
    if lane > 0 then return " L   C  [R]" end
    return           " L  [C]  R "
end

local function spinTick()
    spinIdx = (spinIdx % #SPIN) + 1
    return SPIN[spinIdx]
end

local function fmtTime(startEpoch)
    local elapsed = (os.epoch("utc") - (startEpoch or os.epoch("utc"))) / 1000
    local mins = math.floor(elapsed / 60)
    local secs = math.floor(elapsed % 60)
    return string.format("%02d:%02d", mins, secs)
end

local function slotsUsedSafe()
    local ok, used = pcall(function() return inventory.slotsUsed() end)
    if ok and type(used) == "number" then return used end
    return 0
end

-- ============================================================
-- DASHBOARD
-- ============================================================

function drawDashboard()
    clear()
    hline(1, "=")

    -- Header (fila 2)
    local name = state.hostname or ("miner-" .. os.getComputerID())
    if #name > 14 then name = name:sub(1, 14) end
    local mode = MODE_LABEL[state.mode or "mining"] or "?"
    local header = string.format(" %s [%s]", name, mode)
    writeAt(1, 2, header)
    local right = fmtTime(state.startEpoch) .. " " .. spinTick()
    writeAt(w - #right, 2, right)

    hline(3, "=")

    -- Fuel (fila 4)
    local fuel = turtle and turtle.getFuelLevel() or "unlimited"
    local fuelPct, fuelTxt
    if fuel == "unlimited" then
        fuelPct, fuelTxt = 1, " INF"
    else
        local fmax = turtle.getFuelLimit()
        fuelPct = (fmax ~= "unlimited" and fmax > 0) and (fuel / fmax) or 1
        fuelTxt = string.format("%3d%%", math.floor(fuelPct * 100))
    end
    writeAt(2, 4, "Fuel  " .. barStr(fuelPct, 14) .. " " .. fuelTxt)

    -- Progreso mode-aware (fila 5)
    local mo = state.mode or "mining"
    if mo == "mining" and state.shaftLength and state.shaftLength > 0 then
        local pct = (state.currentStep or 0) / state.shaftLength
        writeAt(2, 5, string.format("Prog  %s %d/%d",
            barStr(pct, 14), state.currentStep or 0, state.shaftLength))
    elseif mo == "lumber" then
        writeAt(2, 5, string.format("Logs  %d    ciclo %d",
            state.logsHarvested or 0, state.farmCycle or 0))
    elseif mo == "farmer" then
        local total = (state.farmWidth or 0) * (state.farmLength or 0)
        writeAt(2, 5, string.format("Plot  %dx%d   ciclo %d",
            state.farmWidth or 0, state.farmLength or 0, state.farmCycle or 0))
    elseif mo == "scout" then
        writeAt(2, 5, string.format("Scans %d", state.scansDone or 0))
    end

    -- Posicion + facing (fila 6)
    writeAt(2, 6, string.format("Pos   (%d,%d,%d) %s",
        state.x or 0, state.y or 0, state.z or 0,
        FACING_LABEL[state.facing or 0] or "?"))

    -- Lane (fila 7) - mining only; otros modos muestran slots
    if mo == "mining" then
        writeAt(2, 7, "Lane  " .. laneGlyph(state.sliceLane))
    else
        writeAt(2, 7, string.format("Slots %d/16", slotsUsedSafe()))
    end

    -- Stats (fila 8)
    if mo == "mining" then
        writeAt(2, 8, string.format("Stats %dm %do %dc s=%d",
            state.blocksMined or 0, state.oresFound or 0,
            state.chestsPlaced or 0, slotsUsedSafe()))
    elseif mo == "lumber" then
        writeAt(2, 8, string.format("Stats logs=%d slot=%d",
            state.logsHarvested or 0, slotsUsedSafe()))
    elseif mo == "farmer" then
        writeAt(2, 8, string.format("Stats crops=%d slot=%d",
            state.cropsHarvested or 0, slotsUsedSafe()))
    else
        writeAt(2, 8, string.format("Stats ores=%d scan=%d",
            state.oresFound or 0, state.scansDone or 0))
    end

    -- Peripherals + oreMap (fila 9)
    local per = ""
    if state.hasEnvDetector then per = per .. "[EnvD]" end
    if state.hasGeoScanner  then per = per .. "[Geo]"  end
    if state.hasRemote      then per = per .. "[Rem]"  end
    if state.hasGPS         then per = per .. "[GPS]"  end
    if per == "" then per = "(sin peripherals)" end
    writeAt(2, 9, "Per   " .. per)
    if state.oreMap then
        local n = 0
        for _ in pairs(state.oreMap) do n = n + 1 end
        if n > 0 then
            local tag = "om:" .. n
            writeAt(w - #tag, 9, tag)
        end
    end

    hline(10, "-")

    -- Status placeholder (fila 11) - setStatus lo rellena
    writeAt(1, 11, " >>")

    -- Ultimo evento (fila 12)
    if #eventLog > 0 then
        writeAt(1, 12, " ~ " .. eventLog[#eventLog])
    end

    -- Key hints (fila 13)
    writeAt(1, h, " [P]aus [R]es [H]om [S]top [Spc]")
end

function setStatus(text)
    text = tostring(text or "")
    clearLine(11)
    local maxLen = w - 5
    if #text > maxLen then text = text:sub(1, maxLen) end
    writeAt(1, 11, " >> " .. text)
end

-- ============================================================
-- ORE LOG (se usa en el finalReport)
-- ============================================================

local ORES_LOG_MAX = 50

function logOre(name, y)
    local short = name:gsub("minecraft:", ""):gsub("_ore", "")
    short = short:gsub("deepslate_", "")
    state.oresLog = state.oresLog or {}
    table.insert(state.oresLog, { name = short, y = y })
    while #state.oresLog > ORES_LOG_MAX do
        table.remove(state.oresLog, 1)
    end
    -- tambien al ticker para feedback visual inmediato
    pushEvent(string.format("%s Y=%d", short, y))
end

-- ============================================================
-- FINAL REPORT
-- ============================================================

function finalReport()
    clear()
    hline(1, "=")
    center(2, "MINERIA COMPLETADA")
    hline(3, "=")

    local mins = math.floor(((os.epoch("utc") - (state.startEpoch or os.epoch("utc"))) / 1000) / 60)
    local secs = math.floor(((os.epoch("utc") - (state.startEpoch or os.epoch("utc"))) / 1000) % 60)

    writeAt(2, 5, "Bloques minados : " .. (state.blocksMined or 0))
    writeAt(2, 6, "Minerales       : " .. (state.oresFound or 0))
    writeAt(2, 7, "Cofres dejados  : " .. (state.chestsPlaced or 0))
    writeAt(2, 8, string.format("Tiempo          : %02d:%02d", mins, secs))
    local fuel = turtle and turtle.getFuelLevel() or "?"
    if fuel == "unlimited" then fuel = "INF" end
    writeAt(2, 9, "Fuel restante   : " .. tostring(fuel))

    writeAt(2, 11, "Ultimos ores:")
    local log = state.oresLog or {}
    local startIdx = math.max(1, #log - 1)
    for i = startIdx, #log do
        local ore = log[i]
        writeAt(4, 11 + (i - startIdx + 1), "- " .. ore.name .. " @ Y=" .. ore.y)
    end
end
