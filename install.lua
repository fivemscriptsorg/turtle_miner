-- ============================================================
-- INSTALLER
-- Descarga todos los archivos del programa desde un pastebin
-- o desde un disquete. Edita BASE_URL si los subes a tu propio sitio.
--
-- Uso desde la turtle:
--   pastebin get <TU_PASTEBIN_ID> install
--   install
-- ============================================================

local BASE_URL = "https://raw.githubusercontent.com/fivemscriptsorg/turtle_miner/main"

local FILES = {
    "startup.lua",
    "miner/ui.lua",
    "miner/config.lua",
    "miner/peripherals.lua",
    "miner/inventory.lua",
    "miner/movement.lua",
    "miner/mining.lua",
}

print("Turtle Miner Installer")
print("======================")

if not BASE_URL then
    print("")
    print("No hay BASE_URL configurada.")
    print("Opciones:")
    print(" 1) Edita install.lua y pon tu URL")
    print(" 2) Copia los archivos desde un disquete:")
    print("    cp disk/startup.lua startup.lua")
    print("    cp -r disk/miner miner")
    return
end

if not http then
    print("ERROR: HTTP no esta habilitado")
    return
end

-- crear carpeta miner si no existe
if not fs.exists("miner") then
    fs.makeDir("miner")
end

for _, path in ipairs(FILES) do
    local url = BASE_URL .. "/" .. path
    write("Descargando " .. path .. "... ")
    local h, err = http.get(url)
    if not h then
        print("ERROR: " .. tostring(err))
    else
        local content = h.readAll()
        h.close()
        local f = fs.open(path, "w")
        f.write(content)
        f.close()
        print("OK")
    end
end

print("")
print("Instalacion completa. Reinicia la turtle.")
