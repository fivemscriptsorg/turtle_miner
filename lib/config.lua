-- ============================================================
-- CONFIG MODULE
-- Wizard interactivo para elegir rol + configurar parametros.
-- La config se guarda en /role.cfg via roleconfig.
-- Cada invocacion puede:
--   - wizardFromScratch(): primer boot, elige rol + configura
--   - reconfigure(currentCfg): re-abre menu para cambiar rol o params
-- ============================================================

-- ============================================================
-- ROLE PICKER
-- ============================================================

function pickRole(deviceType)
    deviceType = deviceType or roleconfig.detectDeviceType()
    local roles = roleconfig.rolesFor(deviceType)

    -- Si solo hay una opcion (pocket/computer -> client), auto.
    if #roles == 1 then return roles[1] end

    local labels = {
        mining = "Mineria (branch / tunnel)",
        lumber = "Tala de arboles (lumber)",
        farmer = "Cultivos (farmer)",
        scout  = "Scout (mapea con geoscanner)",
        loader = "Loader (chunky, sigue a otra)",
        quarry = "Quarry (rectangulo top-down)",
        client = "Cliente de control remoto",
    }

    local options = {}
    for _, r in ipairs(roles) do
        table.insert(options, { label = labels[r] or r, value = r })
    end

    return ui.menu("ROL DEL DISPOSITIVO", options, 1)
end

-- ============================================================
-- MINING CONFIG
-- ============================================================

local function configureMining(cfg)
    local pattern = ui.menu("PATRON DE MINERIA", {
        { label = "Branch Mining 3x3 (recomendado)", value = "branch" },
        { label = "Tunnel Recto 3x3",                value = "tunnel" },
    }, cfg.pattern == "tunnel" and 2 or 1)
    cfg.pattern = pattern

    cfg.shaftLength = ui.promptNumber("LONGITUD DEL TUNEL", cfg.shaftLength or 30, 5, 200)

    if pattern == "branch" then
        cfg.branchLength  = ui.promptNumber("LONGITUD DE RAMAS",   cfg.branchLength  or 8, 3, 30)
        cfg.branchSpacing = ui.promptNumber("SEPARACION DE RAMAS", cfg.branchSpacing or 3, 2, 8)
    end

    cfg.tunnelWidth = ui.menu("ANCHO DEL TUNEL", {
        { label = "3 bloques (3x3 completo)", value = 3 },
        { label = "1 bloque (1x3 rapido)",    value = 1 },
    }, cfg.tunnelWidth == 1 and 2 or 1)
    return cfg
end

-- ============================================================
-- LUMBER CONFIG
-- ============================================================

local function configureLumber(cfg)
    cfg.mode = ui.menu("MODO TALA", {
        { label = "Grid - linea de arboles", value = "grid" },
        { label = "Single - un arbol",       value = "single" },
    }, cfg.mode == "single" and 2 or 1)

    if cfg.mode == "grid" then
        cfg.count   = ui.promptNumber("PARADAS EN LINEA",  cfg.count or 4, 1, 20)
        cfg.spacing = ui.promptNumber("ESPACIADO X",       cfg.spacing or 2, 2, 6)
        cfg.rows    = ui.menu("ROWS DE ARBOLES", {
            { label = "1 - solo lado derecho (+Z)", value = 1 },
            { label = "2 - ambos lados (recomendado)", value = 2 },
        }, cfg.rows == 1 and 1 or 2)
    end

    cfg.bonemeal = ui.menu("USAR BONEMEAL", {
        { label = "Si", value = true },
        { label = "No", value = false },
    }, cfg.bonemeal and 1 or 2)

    cfg.sleepSecs = ui.promptNumber("SEGUNDOS ENTRE CICLOS", cfg.sleepSecs or 120, 5, 3600)
    return cfg
end

-- ============================================================
-- FARMER CONFIG
-- ============================================================

local function configureFarmer(cfg)
    cfg.width     = ui.promptNumber("ANCHO DEL PLOT (X)",    cfg.width or 5, 1, 20)
    cfg.length    = ui.promptNumber("LARGO DEL PLOT (Z)",    cfg.length or 5, 1, 20)
    cfg.sleepSecs = ui.promptNumber("SEGUNDOS ENTRE CICLOS", cfg.sleepSecs or 600, 30, 3600)
    return cfg
end

-- ============================================================
-- SCOUT CONFIG
-- ============================================================

local function configureScout(cfg)
    local patrolIdx = ({ box = 1, stationary = 2, follow = 3 })[cfg.patrol or "box"] or 1
    cfg.patrol = ui.menu("PATRON DE PATRULLA", {
        { label = "Box  - rectangulo fijo",  value = "box" },
        { label = "Stationary - un punto",   value = "stationary" },
        { label = "Follow - sigue mineros",  value = "follow" },
    }, patrolIdx)

    if cfg.patrol == "box" then
        cfg.boxX = ui.promptNumber("CORNER X (local)",  cfg.boxX or 0, -200, 200)
        cfg.boxZ = ui.promptNumber("CORNER Z (local)",  cfg.boxZ or 0, -200, 200)
        cfg.boxW = ui.promptNumber("ANCHO (X)",         cfg.boxW or 32, 4, 200)
        cfg.boxL = ui.promptNumber("LARGO (Z)",         cfg.boxL or 32, 4, 200)
        cfg.stepSpacing = ui.promptNumber("SPACING ENTRE SCANS", cfg.stepSpacing or 12, 4, 32)
    end

    cfg.scanAltY   = ui.promptNumber("ALTURA DE SCAN (Y)",   cfg.scanAltY or 0, -50, 100)
    cfg.safeAltY   = ui.promptNumber("ALTURA SEGURA (Y)",    cfg.safeAltY or 20, 0, 200)
    cfg.scanRadius = ui.promptNumber("RADIO GEOSCANNER",     cfg.scanRadius or 8, 4, 32)
    cfg.sleepSecs  = ui.promptNumber("SEGUNDOS ENTRE CICLOS", cfg.sleepSecs or 30, 5, 3600)
    return cfg
end

-- ============================================================
-- LOADER CONFIG  (chunky turtle follower)
-- ============================================================

local function configureLoader(cfg)
    -- Target: escanea la red ahora mismo y deja elegir, o "auto".
    local opts = { { label = "AUTO (sigue a la primera visible)", value = "auto" } }
    pcall(function()
        -- Intentar abrir modem aqui es prematuro; si no hay modem
        -- disponible rednet.lookup devuelve nada y solo queda AUTO.
        local ids = { rednet.lookup("turtle_miner") }
        for _, id in ipairs(ids) do
            if id ~= os.getComputerID() then
                table.insert(opts, { label = "Turtle #" .. id, value = id })
            end
        end
    end)
    table.insert(opts, { label = "Introducir ID manualmente", value = "manual" })

    local pick = ui.menu("TARGET A SEGUIR", opts, 1)
    if pick == "manual" then
        cfg.followTarget = ui.promptNumber("ID DE LA TURTLE", cfg.followTarget and tonumber(cfg.followTarget) or 1, 1, 99999)
    else
        cfg.followTarget = pick
    end

    cfg.cruiseAltY   = ui.promptNumber("ALTITUD DE VUELO (Y abs)", cfg.cruiseAltY or 120, -64, 320)
    cfg.chunkPadding = ui.promptNumber("TOLERANCIA (chunks)",      cfg.chunkPadding or 0, 0, 4)
    return cfg
end

-- ============================================================
-- QUARRY CONFIG
-- Una sola turtle excava un rectangulo top-down. Cuando se llena
-- coloca cofres flotando. Al terminar levanta los cofres y los
-- consolida en superficie en filas de 2 cofres dobles apilados.
-- ============================================================

local function configureQuarry(cfg)
    cfg.width    = ui.promptNumber("ANCHO (X)",                cfg.width or 8, 2, 32)
    cfg.length   = ui.promptNumber("LARGO (Z)",                cfg.length or 8, 2, 32)
    cfg.maxDepth = ui.promptNumber("PROFUNDIDAD (0=bedrock)", cfg.maxDepth or 64, 0, 320)
    cfg.dumpThreshold = ui.promptNumber("SLOTS ANTES DE COLOCAR COFRE",
        cfg.dumpThreshold or 13, 4, 15)
    return cfg
end

-- ============================================================
-- DISPATCH POR ROL
-- ============================================================

local CONFIGURATORS = {
    mining = configureMining,
    lumber = configureLumber,
    farmer = configureFarmer,
    scout  = configureScout,
    loader = configureLoader,
    quarry = configureQuarry,
    client = function(cfg) return cfg end,
}

function configureRole(role, cfg)
    cfg = cfg or {}
    local fn = CONFIGURATORS[role]
    if fn then return fn(cfg) end
    return cfg
end

-- ============================================================
-- CONFIRMACION
-- ============================================================

local function confirmAndShow(cfg)
    local _, h = term.getSize()
    ui.clear()
    ui.hline(1, "=")
    ui.center(2, "CONFIGURACION")
    ui.hline(3, "=")

    term.setCursorPos(2, 5); term.write("Rol    : " .. (cfg.role or "?"))
    term.setCursorPos(2, 6); term.write("Device : " .. (cfg.deviceType or "?"))

    local y = 8
    if cfg.role == "mining" and cfg.mining then
        local m = cfg.mining
        term.setCursorPos(2, y);   term.write("Patron : " .. tostring(m.pattern))
        term.setCursorPos(2, y+1); term.write("Shaft  : " .. tostring(m.shaftLength) .. " ancho " .. tostring(m.tunnelWidth))
        if m.pattern == "branch" then
            term.setCursorPos(2, y+2); term.write("Ramas  : " .. tostring(m.branchLength) .. " cada " .. tostring(m.branchSpacing))
        end
    elseif cfg.role == "lumber" and cfg.lumber then
        local l = cfg.lumber
        term.setCursorPos(2, y);   term.write("Modo   : " .. tostring(l.mode))
        term.setCursorPos(2, y+1); term.write("Paradas: " .. tostring(l.count) .. " x " .. tostring(l.rows or 2) .. " rows  sp=" .. tostring(l.spacing))
        term.setCursorPos(2, y+2); term.write("Bm " .. (l.bonemeal and "si" or "no") .. "  sleep " .. tostring(l.sleepSecs) .. "s")
    elseif cfg.role == "farmer" and cfg.farmer then
        local f = cfg.farmer
        term.setCursorPos(2, y);   term.write("Plot   : " .. tostring(f.width) .. "x" .. tostring(f.length))
        term.setCursorPos(2, y+1); term.write("Sleep  : " .. tostring(f.sleepSecs) .. "s")
    elseif cfg.role == "scout" and cfg.scout then
        local s = cfg.scout
        term.setCursorPos(2, y); term.write("Patron : " .. tostring(s.patrol))
        if s.patrol == "box" then
            term.setCursorPos(2, y+1)
            term.write("Box    : " .. tostring(s.boxW) .. "x" .. tostring(s.boxL) .. " step " .. tostring(s.stepSpacing))
        end
        term.setCursorPos(2, y+2); term.write("Y scan=" .. tostring(s.scanAltY) .. " safe=" .. tostring(s.safeAltY))
    elseif cfg.role == "loader" and cfg.loader then
        local ld = cfg.loader
        term.setCursorPos(2, y);   term.write("Target : " .. tostring(ld.followTarget))
        term.setCursorPos(2, y+1); term.write("Cruise : Y=" .. tostring(ld.cruiseAltY) .. " abs")
        term.setCursorPos(2, y+2); term.write("Pad    : " .. tostring(ld.chunkPadding) .. " chunks")
    elseif cfg.role == "quarry" and cfg.quarry then
        local q = cfg.quarry
        term.setCursorPos(2, y);   term.write("Box   : " .. tostring(q.width) .. "x" .. tostring(q.length))
        term.setCursorPos(2, y+1); term.write("Depth : " .. (q.maxDepth == 0 and "bedrock" or tostring(q.maxDepth)))
        term.setCursorPos(2, y+2); term.write("Dump  : " .. tostring(q.dumpThreshold) .. " slots")
    end

    term.setCursorPos(2, h - 1)
    term.write("[Enter] guardar  [Q] cancelar")
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter then return true end
        if key == keys.q then return false end
    end
end

-- ============================================================
-- PUBLIC ENTRY POINTS
-- ============================================================

-- Primer boot: elige rol + configura + confirma + guarda.
function wizardFromScratch()
    local deviceType = roleconfig.detectDeviceType()
    local role = pickRole(deviceType)
    local cfg = roleconfig.blankConfig(role, deviceType)
    cfg.role = role
    cfg[role] = configureRole(role, cfg[role] or {})
    if not confirmAndShow(cfg) then
        error("User cancel", 0)
    end
    roleconfig.save(cfg)
    return cfg
end

-- Reconfiguracion: permite cambiar rol o solo params de un rol.
function reconfigure(currentCfg)
    currentCfg = currentCfg or roleconfig.load() or roleconfig.blankConfig("mining")

    while true do
        local options = {
            { label = "Cambiar rol (actual: " .. tostring(currentCfg.role) .. ")", value = "role" },
        }
        if currentCfg.role and CONFIGURATORS[currentCfg.role] then
            table.insert(options, { label = "Configurar " .. currentCfg.role, value = "params" })
        end
        table.insert(options, { label = "Guardar y salir", value = "save" })
        table.insert(options, { label = "Cancelar",        value = "cancel" })

        local choice = ui.menu("CONFIGURACION", options, 1)
        if choice == "cancel" then return nil end
        if choice == "save" then
            if confirmAndShow(currentCfg) then
                roleconfig.save(currentCfg)
                return currentCfg
            end
        elseif choice == "role" then
            local newRole = pickRole(currentCfg.deviceType)
            if newRole and newRole ~= currentCfg.role then
                currentCfg.role = newRole
                currentCfg[newRole] = currentCfg[newRole] or {}
                currentCfg[newRole] = configureRole(newRole, currentCfg[newRole])
            end
        elseif choice == "params" then
            currentCfg[currentCfg.role] = configureRole(currentCfg.role, currentCfg[currentCfg.role] or {})
        end
    end
end
