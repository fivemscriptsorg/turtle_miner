-- ============================================================
-- CONFIG MODULE
-- Menu inicial: selector de programa (mineria/lumber/farmer) y
-- sub-menus por programa.
-- ============================================================

-- ============================================================
-- MINING MENU
-- ============================================================

local function runMiningMenu()
    local pattern = ui.menu("PATRON DE MINERIA", {
        { label = "Branch Mining 3x3 (recomendado)", value = "branch" },
        { label = "Tunnel Recto 3x3",                value = "tunnel" },
        { label = "Volver",                          value = "back" },
    }, 1)

    if pattern == "back" then return false end

    state.pattern = pattern

    state.shaftLength = ui.promptNumber(
        "LONGITUD DEL TUNEL PRINCIPAL",
        30, 5, 200
    )

    if pattern == "branch" then
        state.branchLength = ui.promptNumber(
            "LONGITUD DE CADA RAMA LATERAL",
            8, 3, 30
        )
        state.branchSpacing = ui.promptNumber(
            "SEPARACION ENTRE RAMAS (bloques)",
            3, 2, 8
        )
    end

    local width = ui.menu("ANCHO DEL TUNEL", {
        { label = "3 bloques (3x3 completo)", value = 3 },
        { label = "1 bloque (1x3 rapido)",    value = 1 },
    }, 1)
    state.tunnelWidth = width

    ui.clear()
    ui.hline(1, "=")
    ui.center(2, "RESUMEN DE CONFIGURACION")
    ui.hline(3, "=")
    term.setCursorPos(2, 5)
    term.write("Patron     : " .. pattern)
    term.setCursorPos(2, 6)
    term.write("Shaft      : " .. state.shaftLength .. " bloques")
    term.setCursorPos(2, 7)
    term.write("Ancho      : " .. state.tunnelWidth .. "x3")
    if pattern == "branch" then
        term.setCursorPos(2, 8)
        term.write("Ramas      : " .. state.branchLength .. " cada " .. state.branchSpacing)
    end

    local fuel = turtle.getFuelLevel()
    term.setCursorPos(2, 9)
    if fuel == "unlimited" then
        term.write("Fuel       : INF (sin limite)")
    else
        term.write("Fuel       : " .. fuel)
        local perSlice = (state.tunnelWidth == 1) and 1 or 3
        local estimate = state.shaftLength * perSlice + 2
        if pattern == "branch" then
            local numBranches = math.floor(state.shaftLength / state.branchSpacing) * 2
            estimate = estimate + numBranches * (state.branchLength * (perSlice + 1) + 1)
        end
        estimate = estimate + state.shaftLength
        estimate = math.floor(estimate * 1.15)
        term.setCursorPos(2, 10)
        term.write("Estimado   : " .. estimate .. " (aprox)")
        if fuel < estimate then
            term.setCursorPos(2, 11)
            term.write("AVISO: fuel bajo, se auto-repostara con coal.")
        end
    end

    term.setCursorPos(2, 13)
    term.write("Pulsa [Enter] para empezar, Q para salir.")

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter then return true end
        if key == keys.q then
            ui.clear()
            error("User exit", 0)
        end
    end
end

-- ============================================================
-- LUMBER MENU
-- ============================================================

local function runLumberMenu()
    local mode = ui.menu("MODO TALA", {
        { label = "Grid - linea de arboles",   value = "grid" },
        { label = "Single - un arbol",         value = "single" },
        { label = "Volver",                    value = "back" },
    }, 1)

    if mode == "back" then return false end
    state.lumberMode = mode

    if mode == "grid" then
        state.lumberCount = ui.promptNumber(
            "NUMERO DE ARBOLES EN LINEA", 4, 1, 20
        )
        state.lumberSpacing = ui.promptNumber(
            "ESPACIADO ENTRE ARBOLES", 2, 2, 6
        )
    else
        state.lumberCount = 1
        state.lumberSpacing = 2
    end

    local bm = ui.menu("BONEMEAL PARA ACELERAR", {
        { label = "Si (requiere bonemeal en inventario)", value = true },
        { label = "No (esperar crecimiento natural)",     value = false },
    }, mode == "single" and 1 or 2)
    state.useBonemeal = bm

    state.lumberSleepSecs = ui.promptNumber(
        "SEGUNDOS ENTRE CICLOS",
        mode == "single" and 30 or 120, 5, 3600
    )

    ui.clear()
    ui.hline(1, "=")
    ui.center(2, "CONFIG LUMBER")
    ui.hline(3, "=")
    term.setCursorPos(2, 5); term.write("Modo       : " .. mode)
    term.setCursorPos(2, 6); term.write("Arboles    : " .. state.lumberCount)
    term.setCursorPos(2, 7); term.write("Spacing    : " .. state.lumberSpacing)
    term.setCursorPos(2, 8); term.write("Bonemeal   : " .. (bm and "si" or "no"))
    term.setCursorPos(2, 9); term.write("Sleep      : " .. state.lumberSleepSecs .. "s")
    term.setCursorPos(2, 11)
    term.write("Recuerda: coal + saplings + (bonemeal)")
    term.setCursorPos(2, 12)
    term.write("Cofre detras de la turtle.")
    term.setCursorPos(2, 13)
    term.write("[Enter] empezar  [Q] salir")

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter then return true end
        if key == keys.q then ui.clear(); error("User exit", 0) end
    end
end

-- ============================================================
-- FARMER MENU
-- ============================================================

local function runFarmerMenu()
    state.farmWidth = ui.promptNumber(
        "ANCHO DEL PLOT (X)", 5, 1, 20
    )
    state.farmLength = ui.promptNumber(
        "LARGO DEL PLOT (Z)", 5, 1, 20
    )
    state.farmSleepSecs = ui.promptNumber(
        "SEGUNDOS ENTRE CICLOS", 600, 30, 3600
    )

    ui.clear()
    ui.hline(1, "=")
    ui.center(2, "CONFIG FARMER")
    ui.hline(3, "=")
    term.setCursorPos(2, 5); term.write("Plot       : " .. state.farmWidth .. "x" .. state.farmLength)
    term.setCursorPos(2, 6); term.write("Sleep      : " .. state.farmSleepSecs .. "s")
    term.setCursorPos(2, 8); term.write("Cultivos   : wheat, carrot,")
    term.setCursorPos(2, 9); term.write("             potato, beetroot")
    term.setCursorPos(2, 11)
    term.write("Turtle 2 bloques encima del farmland.")
    term.setCursorPos(2, 12)
    term.write("Cofre detras de la turtle.")
    term.setCursorPos(2, 13)
    term.write("[Enter] empezar  [Q] salir")

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter then return true end
        if key == keys.q then ui.clear(); error("User exit", 0) end
    end
end

-- ============================================================
-- TOP-LEVEL: selecciona programa y despacha a su menu
-- ============================================================

function runMenu()
    while true do
        local program = ui.menu("PROGRAMA", {
            { label = "Mineria (branch / tunnel)", value = "mining" },
            { label = "Tala de arboles (lumber)",  value = "lumber" },
            { label = "Cultivos (farmer)",         value = "farmer" },
            { label = "Salir",                     value = "exit"   },
        }, 1)

        if program == "exit" then
            ui.clear()
            print("Bye!")
            error("User exit", 0)
        end

        state.mode = program

        local ok
        if program == "mining" then
            ok = runMiningMenu()
        elseif program == "lumber" then
            ok = runLumberMenu()
        elseif program == "farmer" then
            ok = runFarmerMenu()
        end

        if ok then return end
        -- si el sub-menu devolvio false (back), volver al selector
    end
end
