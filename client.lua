-- ============================================================
-- TURTLE MULTIPROGRAM CLIENT
-- Control remoto para turtles mining / lumber / farmer.
--
-- Navegacion:
--   Menu principal -> [1] Selector single, [2] Fleet, [Q] salir
--   Single view    -> [B] back  [Q] quit
--   Fleet view     -> [1-9] drill, [B] back, [Q] quit
--
-- Uso:
--   client            -- menu principal
--   client <id>       -- conecta directo a turtle (single)
--   client fleet      -- directo a fleet dashboard
-- ============================================================

local PROTOCOL = "turtle_miner"

-- ============================================================
-- MODEM INIT
-- ============================================================

local function findModem()
    for _, side in ipairs({ "left", "right", "top", "bottom", "front", "back" }) do
        if peripheral.getType(side) == "modem" then
            return side
        end
    end
    return nil
end

local function openModem()
    local side = findModem()
    if side then
        rednet.open(side)
        return side
    end
    if pocket and pocket.equipBack then
        local ok, err = pocket.equipBack()
        if ok then
            side = findModem()
            if side then
                rednet.open(side)
                return side
            end
        else
            print("pocket.equipBack fallo: " .. tostring(err))
        end
    end
    return nil
end

local side = openModem()
if not side then
    if pocket then
        print("ERROR: sin modem. Pon un wireless modem")
        print("en el slot seleccionado del pocket.")
    else
        print("ERROR: no hay modem. Conecta uno.")
    end
    return
end

-- ============================================================
-- UTILS
-- ============================================================

local FACING = { [0] = "+X", [1] = "+Z", [2] = "-X", [3] = "-Z" }

local MODE_BADGE = {
    mining = "M",
    lumber = "L",
    farmer = "F",
    scout  = "S",
    client = "C",
}

local MODE_FULL = {
    mining = "MINING",
    lumber = "LUMBER",
    farmer = "FARMER",
    scout  = "SCOUT",
    client = "CLIENT",
}

local function modeOf(s)
    return (s and s.mode) or "mining"
end

local function bar(pct, len)
    len = len or 15
    local f = math.floor(math.max(0, math.min(1, pct)) * len)
    return "[" .. string.rep("#", f) .. string.rep("-", len - f) .. "]"
end

local function short(name)
    if not name then return "?" end
    return (name:gsub("minecraft:", ""))
end

local function statusStr(s, age)
    if age > 15 then return "DEAD" end
    if s.remoteCmd == "pause" then return "PAU" end
    if s.remoteCmd == "home" then return "HOM" end
    if s.remoteCmd == "stop" then return "STP" end
    return "RUN"
end

local function fuelStr(f)
    if f == -1 or f == "unlimited" then return "INF" end
    return tostring(f or 0)
end

-- Progreso resumido por modo (texto corto)
local function progressOf(s)
    local m = modeOf(s)
    if m == "lumber" then
        return "logs:" .. (s.logsHarvested or 0)
    elseif m == "farmer" then
        return "cyc:" .. (s.farmCycle or 0)
    elseif m == "scout" then
        return "scn:" .. (s.scansDone or 0)
    end
    if s.shaftLength and s.shaftLength > 0 then
        return (s.currentStep or 0) .. "/" .. s.shaftLength
    end
    return "-"
end

local function locationOf(s)
    if s.abs then
        return string.format("(%d,%d,%d)", s.abs.x, s.abs.y, s.abs.z)
    end
    return string.format("L(%d,%d,%d)", s.x or 0, s.y or 0, s.z or 0)
end

-- ============================================================
-- SCAN
-- ============================================================

local function scan(timeout)
    timeout = timeout or 1.5
    local ids = { rednet.lookup(PROTOCOL) }
    if #ids == 0 then return {}, {} end

    local info = {}
    for _, id in ipairs(ids) do
        rednet.send(id, { action = "status" }, PROTOCOL)
    end
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        local senderId, msg = rednet.receive(PROTOCOL, math.max(0.1, deadline - os.clock()))
        if senderId and type(msg) == "table" and msg.kind == "status" and msg.data then
            info[senderId] = msg.data
        end
    end
    return ids, info
end

-- ============================================================
-- SINGLE VIEW (mode-aware)
-- Devuelve "back" o "quit"
-- ============================================================

local function renderSingle(targetId, lastStatus, lastUpdate, messageLog)
    term.clear()
    term.setCursorPos(1, 1)
    local w, h = term.getSize()

    local m = modeOf(lastStatus)
    local badge = MODE_FULL[m] or "?"
    local name = (lastStatus and lastStatus.hostname) or ("miner-" .. targetId)

    print(string.rep("=", w))
    print(" " .. name .. " [" .. badge .. "]   (#" .. targetId .. ")")
    print(string.rep("=", w))

    if not lastStatus then
        print("")
        print(" (esperando status...)")
    else
        local s = lastStatus

        print(string.format(" Local  : X=%d Y=%d Z=%d %s",
            s.x or 0, s.y or 0, s.z or 0, FACING[s.facing or 0] or "?"))
        if s.abs then
            print(string.format(" World  : X=%d Y=%d Z=%d [GPS]",
                s.abs.x, s.abs.y, s.abs.z))
        else
            print(" World  : (sin GPS)")
        end
        print(string.format(" Fuel   : %s", fuelStr(s.fuel)))

        -- Cuerpo mode-specific
        if m == "lumber" then
            print(string.format(" Config : %s  arboles=%d  spacing=%d  bm=%s",
                tostring(s.lumberMode or "?"),
                s.lumberCount or 0,
                s.lumberSpacing or 0,
                s.useBonemeal and "si" or "no"))
            print(string.format(" Stats  : logs=%d  slot=%d",
                s.logsHarvested or 0, s.slotsUsed or 0))
        elseif m == "farmer" then
            print(string.format(" Config : plot %dx%d",
                s.farmWidth or 0, s.farmLength or 0))
            print(string.format(" Stats  : crops=%d  slot=%d",
                s.cropsHarvested or 0, s.slotsUsed or 0))
            print(string.format(" Cycle  : %d  (fila %d)",
                s.farmCycle or 0, s.farmRow or 0))
        elseif m == "scout" then
            print(string.format(" Patrol : %s  radius=%d",
                tostring(s.scoutPatrol or "?"), s.scanRadius or 0))
            print(string.format(" Stats  : scans=%d  ores=%d",
                s.scansDone or 0, s.oresFound or 0))
            print(string.format(" OreMap : %d entradas compartidas",
                s.oreMapSize or 0))
        else
            local progPct = (s.shaftLength and s.shaftLength > 0)
                and (s.currentStep / s.shaftLength) or 0
            print(string.format(" Prog   : %d/%d %s",
                s.currentStep or 0, s.shaftLength or 0, bar(progPct)))
            print(string.format(" Config : %s %dx3  ramas %d/cada %d",
                tostring(s.pattern or "?"),
                s.tunnelWidth or 0,
                s.branchLength or 0,
                s.branchSpacing or 0))
            print(string.format(" Stats  : min=%d ore=%d cof=%d slot=%d",
                s.blocksMined or 0, s.oresFound or 0,
                s.chestsPlaced or 0, s.slotsUsed or 0))
            print(string.format(" OreMap : %d entradas compartidas",
                s.oreMapSize or 0))
        end

        local age = os.clock() - (lastUpdate or 0)
        local cmd = s.remoteCmd and ("  CMD=" .. s.remoteCmd) or ""
        print(string.format(" Upd    : hace %ds%s", math.floor(age), cmd))
    end

    local logY = h - 6
    term.setCursorPos(1, logY)
    print(string.rep("-", w))
    print(" Eventos:")
    for i, line in ipairs(messageLog) do
        term.setCursorPos(1, logY + 1 + i)
        term.write(" - " .. line:sub(1, w - 3))
    end

    term.setCursorPos(1, h - 1)
    print(string.rep("-", w))
    term.setCursorPos(1, h)
    term.write(" [P]ause [R]esume [H]ome [S]top [Space] [B]ack [Q]uit")
end

local function eventLine(msg, senderId)
    local t = msg.type or "?"
    if t == "ore" and msg.data and msg.data.name then
        return "! ore " .. short(msg.data.name)
    elseif t == "log" and msg.data then
        return "! log " .. short(msg.data.name or "") .. " total=" .. (msg.data.count or 0)
    elseif t == "crop" and msg.data then
        return "! crop " .. short(msg.data.name or "") .. " total=" .. (msg.data.count or 0)
    end
    return "! " .. t
end

local function singleView(targetId)
    local lastStatus = nil
    local lastUpdate = 0
    local messageLog = {}
    local result = nil

    local function addLog(t)
        table.insert(messageLog, t)
        while #messageLog > 4 do table.remove(messageLog, 1) end
    end

    local function render()
        renderSingle(targetId, lastStatus, lastUpdate, messageLog)
    end

    local function sendCmd(action)
        rednet.send(targetId, { action = action }, PROTOCOL)
        addLog("-> " .. action)
    end

    local function listener()
        while true do
            local senderId, msg = rednet.receive(PROTOCOL)
            if senderId == targetId and type(msg) == "table" then
                if msg.kind == "status" then
                    lastStatus = msg.data
                    lastUpdate = os.clock()
                    render()
                elseif msg.kind == "ack" then
                    addLog("<- ack " .. tostring(msg.action))
                    render()
                elseif msg.kind == "event" then
                    addLog(eventLine(msg, senderId))
                    render()
                end
            elseif type(msg) == "table" and msg.kind == "ore_spotted" then
                addLog("#" .. senderId .. " " .. short(msg.name))
                render()
            elseif type(msg) == "table" and msg.kind == "scan_report" then
                addLog("#" .. senderId .. " scan +" .. tostring(#(msg.ores or {})))
                render()
            end
        end
    end

    local function input()
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.q then
                result = "quit"; return
            elseif key == keys.b or key == keys.backspace then
                result = "back"; return
            elseif key == keys.p then sendCmd("pause"); render()
            elseif key == keys.r then sendCmd("resume"); render()
            elseif key == keys.h then sendCmd("home"); render()
            elseif key == keys.s then sendCmd("stop"); render()
            elseif key == keys.space then sendCmd("status")
            end
        end
    end

    -- Kickoff
    sendCmd("status")
    render()
    parallel.waitForAny(listener, input)

    return result or "back"
end

-- ============================================================
-- SELECTOR (lista interactiva con flechas)
-- Devuelve targetId o nil(back)
-- ============================================================

local function selectorView()
    local ids, info

    local function refresh()
        term.clear(); term.setCursorPos(1, 1)
        print("Escaneando turtles en la red...")
        ids, info = scan(1.5)
    end

    refresh()

    if #ids == 0 then
        print("")
        print("No se encontro ninguna turtle.")
        print("[R] Refrescar  [B/Q] Volver")
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.r then refresh(); return selectorView() end
            if key == keys.b or key == keys.q or key == keys.backspace then
                return nil
            end
        end
    end

    local selected = 1

    local function render()
        term.clear(); term.setCursorPos(1, 1)
        local w, h = term.getSize()
        print(string.rep("=", w))
        print(" TURTLES DISPONIBLES   ([Enter] entrar  [R] refresh  [B] back)")
        print(string.rep("=", w))

        for i, id in ipairs(ids) do
            local s = info[id] or {}
            local badge = MODE_BADGE[modeOf(s)] or "?"
            local name = (s.hostname or ("miner-" .. id)):sub(1, 16)
            local fuel = fuelStr(s.fuel)
            local st = statusStr(s, 0)
            local cursor = (i == selected) and ">" or " "
            local line = string.format("%s %d. %-16s [%s] %-3s  fuel=%s  %s",
                cursor, i, name, badge, st, fuel, progressOf(s))
            print(line:sub(1, w))
        end

        term.setCursorPos(1, h)
        term.write(" Flechas mover | Enter seleccionar | Q salir")
    end

    render()

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = #ids end
            render()
        elseif key == keys.down then
            selected = selected + 1
            if selected > #ids then selected = 1 end
            render()
        elseif key == keys.enter then
            return ids[selected]
        elseif key == keys.r then
            refresh()
            selected = 1
            if #ids == 0 then return selectorView() end
            render()
        elseif key == keys.b or key == keys.backspace then
            return nil
        elseif key == keys.q then
            return "QUIT"
        end
    end
end

-- ============================================================
-- FLEET VIEW (mixed mining/lumber/farmer)
-- Navegacion: 1..9 = drill, B = back, Q = quit
-- ============================================================

local function fleetView()
    local fleet = {}       -- computerId -> snapshot
    local lastSeen = {}    -- computerId -> clock
    local fleetOres = {}   -- "x_y_z" -> ore entry
    local log = {}
    local result = nil

    local function addFleetLog(t)
        table.insert(log, 1, t)
        while #log > 5 do table.remove(log) end
    end

    local function sortedIds()
        local ids = {}
        for id in pairs(fleet) do table.insert(ids, id) end
        table.sort(ids)
        return ids
    end

    local function render()
        term.clear()
        term.setCursorPos(1, 1)
        local w, h = term.getSize()
        print(string.rep("=", w))
        print(" FLEET DASHBOARD          [1-9]drill [R]efresh [B]ack [Q]uit")
        print(string.rep("=", w))

        local ids = sortedIds()
        if #ids == 0 then
            print("")
            print(" (esperando turtles... asegurate que tienen modem)")
        else
            print(string.format(" %-2s %-12s %-4s %-16s %-5s %-4s %-9s %s",
                "#", "name", "mode", "pos", "fuel", "st", "prog", "n"))
            for i, id in ipairs(ids) do
                local s = fleet[id]
                local age = os.clock() - (lastSeen[id] or 0)
                local badge = MODE_BADGE[modeOf(s)] or "?"
                local name = (s.hostname or ("#" .. id)):sub(1, 12)
                local pos = locationOf(s):sub(1, 16)
                local fuel = fuelStr(s.fuel):sub(1, 5)
                local st = statusStr(s, age):sub(1, 4)
                local prog = progressOf(s):sub(1, 9)

                -- "n" columna: ores para mining, logs para lumber, crops para farmer
                local n = 0
                local m = modeOf(s)
                if m == "lumber" then n = s.logsHarvested or 0
                elseif m == "farmer" then n = s.cropsHarvested or 0
                else n = s.oresFound or 0
                end

                local line = string.format(" %-2d %-12s %-4s %-16s %-5s %-4s %-9s %d",
                    i, name, badge, pos, fuel, st, prog, n)
                print(line:sub(1, w))
                if i >= 9 then break end
            end
        end

        local oreCount = 0
        for _ in pairs(fleetOres) do oreCount = oreCount + 1 end

        local logY = h - 7
        term.setCursorPos(1, logY)
        print(string.rep("-", w))
        print(string.format(" Ores descubiertos: %d (compartidos)", oreCount))
        for i, line in ipairs(log) do
            term.setCursorPos(1, logY + 1 + i)
            term.write(" " .. line:sub(1, w - 2))
        end
    end

    local function listener()
        while true do
            local senderId, msg = rednet.receive(PROTOCOL)
            if type(msg) == "table" then
                if msg.kind == "status" and msg.data then
                    fleet[senderId] = msg.data
                    lastSeen[senderId] = os.clock()
                    render()
                elseif msg.kind == "ore_spotted" and msg.pos then
                    local k = msg.pos.x .. "_" .. msg.pos.y .. "_" .. msg.pos.z
                    fleetOres[k] = {
                        x = msg.pos.x, y = msg.pos.y, z = msg.pos.z,
                        name = msg.name, by = msg.by or senderId,
                        seenAt = os.clock(),
                    }
                    addFleetLog(string.format("! #%d %s @ (%d,%d,%d)",
                        msg.by or senderId, short(msg.name),
                        msg.pos.x, msg.pos.y, msg.pos.z))
                    render()
                elseif msg.kind == "ore_gone" and msg.pos then
                    local k = msg.pos.x .. "_" .. msg.pos.y .. "_" .. msg.pos.z
                    fleetOres[k] = nil
                elseif msg.kind == "scan_report" and type(msg.ores) == "table" then
                    for _, ore in ipairs(msg.ores) do
                        local k = ore.x .. "_" .. ore.y .. "_" .. ore.z
                        fleetOres[k] = {
                            x = ore.x, y = ore.y, z = ore.z,
                            name = ore.name, by = msg.by or senderId,
                            seenAt = os.clock(),
                        }
                    end
                    addFleetLog(string.format("# %d scan_report %d ores",
                        msg.by or senderId, #msg.ores))
                    render()
                elseif msg.kind == "event" then
                    addFleetLog("# " .. senderId .. " " .. eventLine(msg, senderId))
                    render()
                end
            end
        end
    end

    local function input()
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.q then result = "quit"; return end
            if key == keys.b or key == keys.backspace then result = "back"; return end
            if key == keys.r then
                rednet.broadcast({ action = "status" }, PROTOCOL)
                addFleetLog("-> broadcast status")
                render()
            else
                -- Numeros 1-9 para drill into
                local numKey = {
                    [keys.one] = 1, [keys.two] = 2, [keys.three] = 3,
                    [keys.four] = 4, [keys.five] = 5, [keys.six] = 6,
                    [keys.seven] = 7, [keys.eight] = 8, [keys.nine] = 9,
                }
                local idx = numKey[key]
                if idx then
                    local ids = sortedIds()
                    local target = ids[idx]
                    if target then
                        result = { drill = target }
                        return
                    end
                end
            end
        end
    end

    local function ticker()
        while true do
            sleep(2)
            render()
        end
    end

    -- Kickoff: pide status a cualquier turtle en la red
    rednet.broadcast({ action = "status" }, PROTOCOL)
    render()

    parallel.waitForAny(listener, input, ticker)

    return result or "back"
end

-- ============================================================
-- MAIN MENU
-- ============================================================

local function mainMenu()
    term.clear(); term.setCursorPos(1, 1)
    local options = {
        { k = "1", label = "Lista de turtles (selector)", value = "single" },
        { k = "2", label = "Fleet dashboard (ver todas)", value = "fleet" },
        { k = "Q", label = "Salir",                        value = "quit" },
    }
    local selected = 1
    local function render()
        term.clear(); term.setCursorPos(1, 1)
        local w, _ = term.getSize()
        print(string.rep("=", w))
        print(" TURTLE CLIENT")
        print(string.rep("=", w))
        print("")
        for i, o in ipairs(options) do
            local cursor = (i == selected) and ">" or " "
            print(" " .. cursor .. " [" .. o.k .. "] " .. o.label)
        end
        print("")
        print(" Flechas mover | Enter seleccionar")
    end
    render()
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = #options end
            render()
        elseif key == keys.down then
            selected = selected + 1
            if selected > #options then selected = 1 end
            render()
        elseif key == keys.enter then
            return options[selected].value
        elseif key == keys.one then return "single"
        elseif key == keys.two then return "fleet"
        elseif key == keys.q then return "quit"
        end
    end
end

-- ============================================================
-- ROUTER
-- ============================================================

local function runSingleLoop()
    while true do
        local id = selectorView()
        if id == "QUIT" then return "quit" end
        if not id then return "back" end
        local r = singleView(id)
        if r == "quit" then return "quit" end
        -- r == "back" -> loop to selector
    end
end

local function runFleetLoop()
    while true do
        local r = fleetView()
        if r == "quit" then return "quit" end
        if r == "back" then return "back" end
        if type(r) == "table" and r.drill then
            local sr = singleView(r.drill)
            if sr == "quit" then return "quit" end
            -- sr == "back" -> loop back into fleet
        end
    end
end

local function main()
    -- Args (shortcut): client <id> | client fleet
    if arg and arg[1] then
        if arg[1] == "fleet" then
            runFleetLoop()
            return
        end
        local id = tonumber(arg[1])
        if id then
            singleView(id)
            return
        end
    end

    while true do
        local choice = mainMenu()
        if choice == "quit" or not choice then return end
        if choice == "single" then
            local r = runSingleLoop()
            if r == "quit" then return end
        elseif choice == "fleet" then
            local r = runFleetLoop()
            if r == "quit" then return end
        end
    end
end

local ok, err = pcall(main)
term.clear(); term.setCursorPos(1, 1)
if not ok then
    print("ERROR: " .. tostring(err))
end
print("Desconectado.")
rednet.close(side)
