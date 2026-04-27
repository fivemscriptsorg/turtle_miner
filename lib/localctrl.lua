-- ============================================================
-- LOCAL CONTROL MODULE
-- Escucha eventos "key" en la terminal de la propia turtle y
-- emite los mismos comandos que el cliente remoto (pause /
-- resume / home / stop) escribiendo state.remoteCmd.
-- Esto permite operar la turtle pegado a ella sin necesidad de
-- modem ni red. Se ejecuta en paralelo con el programa via
-- parallel.waitForAny (cada coroutine tiene su propia cola de
-- eventos, asi que no compite con mining/rednet).
--
-- Teclas:
--   P = pause    R = resume    H = home    S = stop
--   Q = stop (alias)           space = redraw dashboard
-- ============================================================

-- Intensidad del "flash" en el dashboard al recibir un comando local.
local FLASH_SECS = 0.8

local function issue(cmd, label)
    state.remoteCmd = cmd
    if ui and ui.flash then
        pcall(ui.flash, label, FLASH_SECS)
    elseif ui and ui.setStatus then
        pcall(ui.setStatus, label)
    end
end

function listener()
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.p then
            issue("pause",  "PAUSA (local)")
        elseif key == keys.r then
            issue("resume", "RESUME (local)")
        elseif key == keys.h then
            issue("home",   "HOME (local)")
        elseif key == keys.s or key == keys.q then
            issue("stop",   "STOP (local)")
        elseif key == keys.space then
            if ui and ui.drawDashboard then pcall(ui.drawDashboard) end
        end
    end
end
