-- ============================================================
-- TURTLE MINER CLIENT
-- Control remoto de una turtle corriendo el miner v1.1+.
-- Se ejecuta en OTRA computer (no la turtle) que tenga un
-- wireless modem. Hace discovery, muestra dashboard en vivo,
-- y envia comandos.
--
-- Uso:
--   client           -- scan y selecciona una turtle
--   client <id>      -- conecta directo al computer ID dado
-- ============================================================

local PROTOCOL = "turtle_miner"

-- ============================================================
-- INIT: abrir modem
-- ============================================================

local function openModem()
    local sides = { "left", "right", "top", "bottom", "front", "back" }
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            return side
        end
    end
    return nil
end

local side = openModem()
if not side then
    print("ERROR: no hay modem conectado.")
    print("Conecta un wireless modem y reinicia.")
    return
end

-- ============================================================
-- DISCOVERY
-- ============================================================

local function selectTurtle()
    term.clear()
    term.setCursorPos(1, 1)
    print("Escaneando turtles en rednet...")

    local ids = { rednet.lookup(PROTOCOL) }
    if #ids == 0 then
        print("No se encontro ninguna turtle.")
        print("Asegurate de que la turtle tiene modem y esta corriendo.")
        return nil
    end

    -- Pedir un status ping a cada una para obtener hostname
    local info = {}
    for _, id in ipairs(ids) do
        rednet.send(id, { action = "status" }, PROTOCOL)
    end
    local deadline = os.clock() + 1.0
    while os.clock() < deadline do
        local senderId, msg = rednet.receive(PROTOCOL, deadline - os.clock())
        if senderId and type(msg) == "table" and msg.kind == "status" then
            info[senderId] = msg.data
        end
    end

    print("Turtles encontradas:")
    for i, id in ipairs(ids) do
        local name = (info[id] and info[id].hostname) or ("miner-" .. id)
        print(string.format("  %d. #%d  %s", i, id, name))
    end
    write("Elige (numero, Enter=1): ")
    local input = read()
    local idx = tonumber(input) or 1
    return ids[idx]
end

local targetId
if arg and arg[1] then
    targetId = tonumber(arg[1])
end
if not targetId then
    targetId = selectTurtle()
end
if not targetId then return end

-- ============================================================
-- STATE
-- ============================================================

local lastStatus = nil
local lastUpdate = 0
local messageLog = {}

local function addLog(text)
    table.insert(messageLog, text)
    while #messageLog > 4 do table.remove(messageLog, 1) end
end

-- ============================================================
-- RENDER
-- ============================================================

local FACING_NAMES = { [0] = "+X", [1] = "+Z", [2] = "-X", [3] = "-Z" }

local function bar(pct, len)
    len = len or 20
    local filled = math.floor(math.max(0, math.min(1, pct)) * len)
    return "[" .. string.rep("#", filled) .. string.rep("-", len - filled) .. "]"
end

local function render()
    term.clear()
    term.setCursorPos(1, 1)
    local w, h = term.getSize()

    -- header
    print(string.rep("=", w))
    local name = (lastStatus and lastStatus.hostname) or ("miner-" .. targetId)
    print(" " .. name .. "  (computer #" .. targetId .. ")")
    print(string.rep("=", w))

    if not lastStatus then
        print("")
        print(" (esperando status del turtle...)")
        print("")
    else
        local s = lastStatus
        local fuelStr = s.fuel == -1 and "INF" or tostring(s.fuel)
        local progPct = (s.shaftLength and s.shaftLength > 0)
            and (s.currentStep / s.shaftLength) or 0

        print(string.format(" Pos     : X=%d  Y=%d  Z=%d  face=%s",
            s.x or 0, s.y or 0, s.z or 0, FACING_NAMES[s.facing or 0] or "?"))
        print(string.format(" Fuel    : %s", fuelStr))
        print(string.format(" Progreso: %d/%d  %s",
            s.currentStep or 0, s.shaftLength or 0, bar(progPct, 15)))
        print(string.format(" Patron  : %s  %dx3  ramas %d (cada %d)",
            tostring(s.pattern), s.tunnelWidth or 0,
            s.branchLength or 0, s.branchSpacing or 0))
        print(string.format(" Minados : %d   Ores: %d   Cofres: %d",
            s.blocksMined or 0, s.oresFound or 0, s.chestsPlaced or 0))
        print(string.format(" Slots   : %d/16   Lane: %d",
            s.slotsUsed or 0, s.sliceLane or 0))

        local age = os.clock() - lastUpdate
        print(string.format(" Update  : hace %ds%s", math.floor(age),
            s.remoteCmd and ("  CMD=" .. s.remoteCmd) or ""))
    end

    -- log de eventos
    local logY = h - 6
    term.setCursorPos(1, logY)
    print(string.rep("-", w))
    print(" Eventos:")
    for i, line in ipairs(messageLog) do
        term.setCursorPos(1, logY + 1 + i)
        term.write(" - " .. line:sub(1, w - 3))
    end

    -- footer con teclas
    term.setCursorPos(1, h - 1)
    print(string.rep("-", w))
    term.setCursorPos(1, h)
    term.write(" [P]ausa [R]esume [H]ome [S]top [Space]refresh [Q]uit")
end

-- ============================================================
-- COMMAND SEND
-- ============================================================

local function sendCmd(action)
    rednet.send(targetId, { action = action }, PROTOCOL)
    addLog("-> " .. action)
end

-- ============================================================
-- COROUTINES PARA parallel.waitForAny
-- ============================================================

local function listener()
    while true do
        local senderId, msg, protocol = rednet.receive(PROTOCOL)
        if senderId == targetId and type(msg) == "table" then
            if msg.kind == "status" then
                lastStatus = msg.data
                lastUpdate = os.clock()
                render()
            elseif msg.kind == "ack" then
                addLog("<- ack " .. tostring(msg.action))
                render()
            elseif msg.kind == "event" then
                local txt = "! evt " .. tostring(msg.type)
                if msg.data and msg.data.name then
                    txt = txt .. " " .. msg.data.name
                end
                addLog(txt)
                render()
            end
        end
    end
end

local function input()
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.q then
            return
        elseif key == keys.p then
            sendCmd("pause"); render()
        elseif key == keys.r then
            sendCmd("resume"); render()
        elseif key == keys.h then
            sendCmd("home"); render()
        elseif key == keys.s then
            sendCmd("stop"); render()
        elseif key == keys.space then
            sendCmd("status")
        end
    end
end

-- ============================================================
-- GO
-- ============================================================

sendCmd("status")
render()
parallel.waitForAny(listener, input)

term.clear()
term.setCursorPos(1, 1)
print("Desconectado. Cerrando modem.")
rednet.close(side)
