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
        cfg.count   = ui.promptNumber("ARBOLES EN LINEA", cfg.count or 4, 1, 20)
        cfg.spacing = ui.promptNumber("ESPACIADO",        cfg.spacing or 2, 2, 6)
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
-- DISPATCH POR ROL
-- ============================================================

local CONFIGURATORS = {
    mining = configureMining,
    lumber = configureLumber,
    farmer = configureFarmer,
    scout  = configureScout,
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
        term.setCursorPos(2, y+1); term.write("N      : " .. tostring(l.count) .. " spacing " .. tostring(l.spacing))
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
