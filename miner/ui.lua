-- ============================================================
-- UI MODULE
-- Dashboard compatible con turtle normal (sin color, 39x13).
-- ============================================================

local w, h = term.getSize()

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

-- Splash screen inicial con ASCII art
function splash()
    clear()
    local art = {
        "+-------------------------------------+",
        "|                                     |",
        "|   #####  ##   ## ##### ##   ## #### |",
        "|   ## ##  ### ### ##    ###  ## #    |",
        "|   ####   ## # ## #####  ##  ## ###  |",
        "|   ## ##  ##   ## ##      ## ## #    |",
        "|   ## ##  ##   ## ##### ######  #### |",
        "|                                     |",
        "|        T U R T L E  M I N E R       |",
        "|             v 1.0                   |",
        "+-------------------------------------+",
    }
    for i, line in ipairs(art) do
        center(i, line)
    end
    center(h, "Iniciando... (pulsa cualquier tecla)")
    parallel.waitForAny(
        function() sleep(1.5) end,
        function() os.pullEvent("key") end
    )
end

-- Menu generico (usado por config)
-- options = {{label="...", value=...}, ...}
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
        term.write("[Up/Down] mover  [Enter] seleccionar")

        local event, key = os.pullEvent("key")
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

-- Input numerico simple
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

-- Dashboard dibujado durante la mineria
-- Se refresca periodicamente desde mining.lua
function drawDashboard()
    clear()
    hline(1, "=")
    center(2, "TURTLE MINER - ACTIVO")
    hline(3, "=")

    -- Fuel
    local fuel = turtle.getFuelLevel()
    local fuelStr
    if fuel == "unlimited" then
        fuelStr = "INF"
    else
        fuelStr = tostring(fuel)
    end
    term.setCursorPos(2, 4)
    term.write("Fuel : " .. fuelStr)

    -- Barra de fuel
    local fuelMax = turtle.getFuelLimit()
    if fuelMax ~= "unlimited" and fuel ~= "unlimited" then
        local pct = math.min(fuel / fuelMax, 1)
        local barLen = 20
        local filled = math.floor(pct * barLen)
        term.setCursorPos(15, 4)
        term.write("[" .. string.rep("#", filled) .. string.rep("-", barLen - filled) .. "]")
    end

    -- Progreso del shaft
    term.setCursorPos(2, 5)
    term.write("Avance: " .. state.x .. "/" .. state.shaftLength .. " bloques")
    local pct = math.min(state.x / state.shaftLength, 1)
    local barLen = 20
    local filled = math.floor(pct * barLen)
    term.setCursorPos(25, 5)
    term.write("[" .. string.rep("#", filled) .. string.rep("-", barLen - filled) .. "]")

    -- Posicion
    term.setCursorPos(2, 6)
    term.write("Pos  : X="..state.x.." Y="..state.y.." Z="..state.z.." F="..state.facing)

    -- Inventario
    local used, total = inventory.slotsUsed()
    term.setCursorPos(2, 7)
    term.write("Slots: "..used.."/16   Minados: "..state.blocksMined)

    -- Ores y cofres
    term.setCursorPos(2, 8)
    term.write("Ores : "..state.oresFound.."   Cofres: "..state.chestsPlaced)

    -- Peripherals
    term.setCursorPos(2, 9)
    local per = ""
    if state.hasEnvDetector then per = per .. "[EnvD] " end
    if state.hasGeoScanner then per = per .. "[Geo] " end
    if per == "" then per = "(sin peripherals)" end
    term.write("Per  : " .. per)

    -- Tiempo (usa epoch para sobrevivir reinicios)
    local elapsed = (os.epoch("utc") - (state.startEpoch or os.epoch("utc"))) / 1000
    local mins = math.floor(elapsed / 60)
    local secs = math.floor(elapsed % 60)
    term.setCursorPos(2, 10)
    term.write(string.format("Time : %02d:%02d", mins, secs))

    hline(11, "-")
    term.setCursorPos(2, 12)
    term.write("Status: ")
end

function setStatus(text)
    term.setCursorPos(10, 12)
    term.write(string.rep(" ", w - 11))
    term.setCursorPos(10, 12)
    -- truncar a 28 chars por si acaso
    if #text > 28 then text = text:sub(1, 28) end
    term.write(text)
end

local ORES_LOG_MAX = 50

function logOre(name, y)
    local short = name:gsub("minecraft:", ""):gsub("_ore", "")
    short = short:gsub("deepslate_", "")
    table.insert(state.oresLog, { name = short, y = y })
    -- cap al tamano maximo: en runs largos no explota memoria
    while #state.oresLog > ORES_LOG_MAX do
        table.remove(state.oresLog, 1)
    end
end

function finalReport()
    clear()
    hline(1, "=")
    center(2, "MINERIA COMPLETADA")
    hline(3, "=")

    local elapsed = (os.epoch("utc") - (state.startEpoch or os.epoch("utc"))) / 1000
    local mins = math.floor(elapsed / 60)
    local secs = math.floor(elapsed % 60)

    term.setCursorPos(2, 5)
    term.write("Bloques minados : " .. state.blocksMined)
    term.setCursorPos(2, 6)
    term.write("Minerales       : " .. state.oresFound)
    term.setCursorPos(2, 7)
    term.write("Cofres dejados  : " .. state.chestsPlaced)
    term.setCursorPos(2, 8)
    term.write(string.format("Tiempo          : %02d:%02d", mins, secs))
    term.setCursorPos(2, 9)
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then fuel = "INF" end
    term.write("Fuel restante   : " .. fuel)

    term.setCursorPos(2, 11)
    term.write("Ultimos ores detectados:")
    local startIdx = math.max(1, #state.oresLog - 2)
    for i = startIdx, #state.oresLog do
        local ore = state.oresLog[i]
        term.setCursorPos(4, 11 + (i - startIdx + 1))
        term.write("- " .. ore.name .. " @ Y=" .. ore.y)
    end
end
