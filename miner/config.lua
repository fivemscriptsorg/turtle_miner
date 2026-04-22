-- ============================================================
-- CONFIG MODULE
-- Menu inicial para configurar la mineria.
-- ============================================================

function runMenu()
    -- 1) Seleccion de patron
    local pattern = ui.menu("PATRON DE MINERIA", {
        { label = "Branch Mining 3x3 (recomendado)", value = "branch" },
        { label = "Tunnel Recto 3x3",                value = "tunnel" },
        { label = "Salir",                           value = "exit" },
    }, 1)

    if pattern == "exit" then
        ui.clear()
        print("Bye!")
        error("User exit", 0)
    end

    state.pattern = pattern

    -- 2) Longitud del shaft principal
    state.shaftLength = ui.promptNumber(
        "LONGITUD DEL TUNEL PRINCIPAL",
        30, 5, 200
    )

    -- 3) Si es branch, preguntar longitud de ramas y spacing
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

    -- 3b) Ancho del tunel (1 = rapido 1x3, 3 = completo 3x3)
    local width = ui.menu("ANCHO DEL TUNEL", {
        { label = "3 bloques (3x3 completo)", value = 3 },
        { label = "1 bloque (1x3 rapido)",    value = 1 },
    }, 1)
    state.tunnelWidth = width

    -- 4) Confirmacion y chequeo de fuel
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
        -- estimacion rapida: costo por slice segun ancho
        local perSlice = (state.tunnelWidth == 1) and 3 or 9
        local estimate = state.shaftLength * perSlice
        if pattern == "branch" then
            local numBranches = math.floor(state.shaftLength / state.branchSpacing) * 2
            estimate = estimate + numBranches * state.branchLength * perSlice
        end
        estimate = estimate + state.shaftLength -- vuelta al inicio
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
        if key == keys.enter then return end
        if key == keys.q then
            ui.clear()
            error("User exit", 0)
        end
    end
end
