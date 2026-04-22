-- ============================================================
-- TURTLE MINER CLIENT
-- Control remoto y fleet dashboard.
--
-- Uso:
--   client            -- selector: modo single o fleet
--   client <id>       -- conecta directo a una turtle (modo single)
--   client fleet      -- dashboard de TODAS las turtles detectadas
-- ============================================================

local PROTOCOL = "turtle_miner"

-- ============================================================
-- INIT: abrir modem
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
    -- Pocket computer: intentar equipar un modem del inventario
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
        print("ERROR: sin modem. Pon un wireless modem en el slot")
        print("seleccionado del inventario y vuelve a ejecutar.")
    else
        print("ERROR: no hay modem. Conecta un wireless modem.")
    end
    return
end

-- ============================================================
-- DISCOVERY
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
-- SINGLE MODE (dashboard de UNA turtle)
-- ============================================================

local FACING = { [0]="+X", [1]="+Z", [2]="-X", [3]="-Z" }
local messageLog = {}

local function addLog(t)
    table.insert(messageLog, t)
    while #messageLog > 4 do table.remove(messageLog, 1) end
end

local function bar(pct, len)
    len = len or 15
    local f = math.floor(math.max(0, math.min(1, pct)) * len)
    return "[" .. string.rep("#", f) .. string.rep("-", len - f) .. "]"
end

local function singleMode(targetId)
    local lastStatus
    local lastUpdate = 0

    local function render()
        term.clear()
        term.setCursorPos(1, 1)
        local w, h = term.getSize()
        print(string.rep("=", w))
        local name = (lastStatus and lastStatus.hostname) or ("miner-"..targetId)
        print(" " .. name .. "  (#" .. targetId .. ")")
        print(string.rep("=", w))

        if not lastStatus then
            print("")
            print(" (esperando status...)")
        else
            local s = lastStatus
            local fuelStr = s.fuel == -1 and "INF" or tostring(s.fuel)
            local progPct = (s.shaftLength and s.shaftLength > 0) and (s.currentStep / s.shaftLength) or 0

            print(string.format(" Local  : X=%d Y=%d Z=%d %s",
                s.x or 0, s.y or 0, s.z or 0, FACING[s.facing or 0] or "?"))
            if s.abs then
                print(string.format(" World  : X=%d Y=%d Z=%d [GPS]",
                    s.abs.x, s.abs.y, s.abs.z))
            else
                print(" World  : (sin GPS)")
            end
            print(string.format(" Fuel   : %s", fuelStr))
            print(string.format(" Prog   : %d/%d %s",
                s.currentStep or 0, s.shaftLength or 0, bar(progPct)))
            print(string.format(" Config : %s %dx3  ramas %d/cada %d",
                tostring(s.pattern), s.tunnelWidth or 0,
                s.branchLength or 0, s.branchSpacing or 0))
            print(string.format(" Stats  : min=%d ore=%d cof=%d slot=%d",
                s.blocksMined or 0, s.oresFound or 0, s.chestsPlaced or 0, s.slotsUsed or 0))
            print(string.format(" OreMap : %d entradas compartidas", s.oreMapSize or 0))
            local age = os.clock() - lastUpdate
            local cmd = s.remoteCmd and ("  CMD="..s.remoteCmd) or ""
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
        term.write(" [P]ause [R]esume [H]ome [S]top [Space]refresh [Q]uit")
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
                    addLog("<- ack "..tostring(msg.action)); render()
                elseif msg.kind == "event" then
                    local txt = "! " .. tostring(msg.type)
                    if msg.data and msg.data.name then txt = txt .. " " .. msg.data.name end
                    addLog(txt); render()
                end
            elseif type(msg) == "table" and msg.kind == "ore_spotted" then
                local n = msg.name or "ore"
                addLog("#"..senderId.." "..n:gsub("minecraft:",""))
                render()
            end
        end
    end

    local function input()
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.q then return
            elseif key == keys.p then sendCmd("pause"); render()
            elseif key == keys.r then sendCmd("resume"); render()
            elseif key == keys.h then sendCmd("home"); render()
            elseif key == keys.s then sendCmd("stop"); render()
            elseif key == keys.space then sendCmd("status")
            end
        end
    end

    sendCmd("status"); render()
    parallel.waitForAny(listener, input)
end

-- ============================================================
-- FLEET MODE (dashboard multi-turtle + ore map combinado)
-- ============================================================

local function fleetMode()
    local fleet = {}     -- computerId -> lastStatus
    local lastSeen = {}  -- computerId -> os.clock()
    local fleetOres = {} -- clave "x_y_z" -> ore entry
    local log = {}

    local function addFleetLog(t)
        table.insert(log, 1, t)
        while #log > 5 do table.remove(log) end
    end

    local function fleetRender()
        term.clear()
        term.setCursorPos(1, 1)
        local w, h = term.getSize()
        print(string.rep("=", w))
        print(" FLEET DASHBOARD                     [F]leet launch [Q]uit")
        print(string.rep("=", w))

        local ids = {}
        for id in pairs(fleet) do table.insert(ids, id) end
        table.sort(ids)

        if #ids == 0 then
            print("")
            print(" (esperando turtles... asegurate que tienen modem)")
        else
            print(string.format(" %-12s %-18s %-8s %-4s %-7s %s",
                "name","world/local","fuel","st","prog","ore"))
            for _, id in ipairs(ids) do
                local s = fleet[id]
                local age = os.clock() - (lastSeen[id] or 0)
                local dead = age > 15
                local name = (s.hostname or ("#"..id)):sub(1, 12)
                local loc
                if s.abs then
                    loc = string.format("(%d,%d,%d)", s.abs.x, s.abs.y, s.abs.z)
                else
                    loc = string.format("L(%d,%d,%d)", s.x or 0, s.y or 0, s.z or 0)
                end
                local fuel = s.fuel == -1 and "INF" or tostring(s.fuel or 0)
                local st
                if dead then st = "DEAD"
                elseif s.remoteCmd == "pause" then st = "PAU"
                elseif s.remoteCmd == "home" then st = "HOM"
                elseif s.remoteCmd == "stop" then st = "STP"
                else st = "RUN" end
                local prog
                if s.shaftLength and s.shaftLength > 0 then
                    prog = (s.currentStep or 0) .. "/" .. s.shaftLength
                else
                    prog = "-"
                end
                print(string.format(" %-12s %-18s %-8s %-4s %-7s %d",
                    name, loc:sub(1,18), fuel:sub(1,8), st, prog:sub(1,7), s.oresFound or 0))
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
                    fleetRender()
                elseif msg.kind == "ore_spotted" and msg.pos then
                    local k = msg.pos.x .. "_" .. msg.pos.y .. "_" .. msg.pos.z
                    fleetOres[k] = { x=msg.pos.x, y=msg.pos.y, z=msg.pos.z,
                                     name = msg.name, by = msg.by or senderId,
                                     seenAt = os.clock() }
                    local short = (msg.name or "ore"):gsub("minecraft:", "")
                    addFleetLog(string.format("! #%d %s @ (%d,%d,%d)",
                        msg.by or senderId, short, msg.pos.x, msg.pos.y, msg.pos.z))
                    fleetRender()
                elseif msg.kind == "ore_gone" and msg.pos then
                    local k = msg.pos.x .. "_" .. msg.pos.y .. "_" .. msg.pos.z
                    fleetOres[k] = nil
                elseif msg.kind == "event" then
                    local txt = "# "..senderId.." "..tostring(msg.type)
                    addFleetLog(txt)
                    fleetRender()
                end
            end
        end
    end

    local function launchFleet()
        -- lanza un "start" con offsets de Z a todas las turtles en idle
        term.clear(); term.setCursorPos(1,1)
        print("Fleet launch: lanzar N turtles en paralelo con offset Z")
        print("Cada turtle debe estar ya en su posicion inicial.")
        print("Este comando solo envia CONFIG. Cada turtle arranca sola.")
        print("")
        write("Longitud del shaft: ")
        local L = tonumber(read()) or 30
        write("Separacion Z entre turtles (bloques): ")
        local dz = tonumber(read()) or 5
        local ids = {}
        for id in pairs(fleet) do table.insert(ids, id) end
        table.sort(ids)
        print("Turtles a lanzar: " .. #ids)
        for i, id in ipairs(ids) do
            local payload = {
                action = "configure",
                pattern = "branch",
                shaftLength = L,
                branchLength = 8,
                branchSpacing = 3,
                tunnelWidth = 3,
                zOffset = (i - 1) * dz, -- informativo, la turtle no lo aplica sola
            }
            rednet.send(id, payload, PROTOCOL)
            addFleetLog("-> launch #" .. id .. " offset z=" .. ((i - 1) * dz))
        end
        print("")
        print("OJO: este build aun no aplica configure automaticamente.")
        print("Cada turtle debe tener menu resuelto manualmente. Roadmap.")
        print("")
        print("Pulsa cualquier tecla para volver...")
        os.pullEvent("key")
    end

    local function input()
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.q then return
            elseif key == keys.f then
                launchFleet()
                fleetRender()
            end
        end
    end

    -- arranque: pedir status a cualquier turtle en la red
    rednet.broadcast({ action = "status" }, PROTOCOL)
    fleetRender()

    local function ticker()
        while true do
            sleep(2)
            fleetRender()
        end
    end

    parallel.waitForAny(listener, input, ticker)
end

-- ============================================================
-- ROUTER
-- ============================================================

local function mainMenu()
    term.clear(); term.setCursorPos(1, 1)
    print("TURTLE MINER CLIENT")
    print("===================")
    print("")
    print(" [1] Single turtle (control detallado)")
    print(" [2] Fleet dashboard (ver todas)")
    print(" [Q] Salir")
    print("")
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.one then return "single" end
        if key == keys.two then return "fleet" end
        if key == keys.q then return nil end
    end
end

local targetId
local mode = nil

if arg and arg[1] then
    if arg[1] == "fleet" then
        mode = "fleet"
    else
        targetId = tonumber(arg[1])
        mode = "single"
    end
end

if not mode then
    mode = mainMenu()
    if not mode then
        term.clear(); term.setCursorPos(1,1)
        print("Bye!")
        return
    end
end

if mode == "single" then
    if not targetId then
        local ids, info = scan()
        if #ids == 0 then
            print("No se encontro ninguna turtle.")
            return
        end
        term.clear(); term.setCursorPos(1,1)
        print("Turtles detectadas:")
        for i, id in ipairs(ids) do
            local name = (info[id] and info[id].hostname) or ("miner-" .. id)
            print("  " .. i .. ". " .. name .. " (#" .. id .. ")")
        end
        write("Elige (Enter=1): ")
        targetId = ids[tonumber(read()) or 1]
    end
    if targetId then singleMode(targetId) end
elseif mode == "fleet" then
    fleetMode()
end

term.clear(); term.setCursorPos(1, 1)
print("Desconectado.")
rednet.close(side)
