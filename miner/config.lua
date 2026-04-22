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

    -- 4) Confirmacion y chequeo de fuel
    ui.clear()
    ui.hline(1, "=")
    ui.center(2, "RESUMEN DE CONFIGURACION")
    ui.hline(3, "=")
    term.setCursorPos(2, 5)
    term.write("Patron     : " .. pattern)
    term.setCursorPos(2, 6)
    term.write("Shaft      : " .. state.shaftLength .. " bloques")
    if pattern == "branch" then
        term.setCursorPos(2, 7)
        term.write("Ramas      : " .. state.branchLength .. " cada " .. state.branchSpacing .. " bloques")
    end

    local fuel = turtle.getFuelLevel()
    term.setCursorPos(2, 9)
    if fuel == "unlimited" then
        term.write("Fuel       : INF (sin limite)")
    else
        term.write("Fuel       : " .. fuel)
        -- estimacion rapida
        local estimate = state.shaftLength * 6
        if pattern == "branch" then
            local numBranches = math.floor(state.shaftLength / state.branchSpacing) * 2
            estimate = estimate + numBranches * state.branchLength * 6
        end
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
