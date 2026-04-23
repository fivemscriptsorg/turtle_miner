-- ============================================================
-- CONFIGURE
-- Comando para re-abrir el wizard de configuracion y cambiar el
-- rol del dispositivo o los parametros del programa actual.
-- Uso: `configure` en el shell.
-- ============================================================

os.loadAPI("lib/ui.lua")
os.loadAPI("lib/roleconfig.lua")
os.loadAPI("lib/config.lua")

local function main()
    local current = roleconfig.load()
    if not current then
        print("No hay config previa. Iniciando wizard de primer boot...")
        sleep(1)
        current = config.wizardFromScratch()
    else
        current = config.reconfigure(current)
        if not current then
            term.clear(); term.setCursorPos(1, 1)
            print("Config sin cambios.")
            return
        end
    end

    term.clear(); term.setCursorPos(1, 1)
    print("Guardado en /role.cfg")
    print("Rol activo: " .. tostring(current.role))
    print("")
    print("Reinicia el dispositivo para aplicar (reboot).")
end

local ok, err = pcall(main)
if not ok and err ~= "User cancel" then
    print("ERROR: " .. tostring(err))
end
