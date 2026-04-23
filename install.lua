-- ============================================================
-- INSTALLER
-- Descarga todos los archivos del programa desde el repo de GitHub.
-- Auto-actualizable: primero se actualiza a si mismo para traer la
-- lista de archivos nueva, luego descarga el resto.
--
-- Uso desde la turtle:
--   pastebin get <TU_PASTEBIN_ID> install
--   install
-- ============================================================

local BASE_URL = "https://raw.githubusercontent.com/fivemscriptsorg/turtle_miner/main"

-- Nota: install.lua NO esta en esta lista. Se descarga aparte al inicio
-- para poder detectar cambios y reiniciar con la lista nueva.
local FILES = {
    "startup.lua",
    "client.lua",
    "configure.lua",
    "lib/ui.lua",
    "lib/persist.lua",
    "lib/config.lua",
    "lib/roleconfig.lua",
    "lib/peripherals.lua",
    "lib/inventory.lua",
    "lib/movement.lua",
    "lib/remote.lua",
    "lib/swarm.lua",
    "mining/mining.lua",
    "lumber/lumber.lua",
    "farmer/farmer.lua",
    "scout/scout.lua",
}

local DIRS = { "lib", "mining", "lumber", "farmer", "scout" }

local args = { ... }
local skipSelfUpdate = (args[1] == "--post-update")

print("Turtle Miner Installer")
print("======================")

if not BASE_URL then
    print("No hay BASE_URL configurada.")
    return
end

if not http then
    print("ERROR: HTTP no esta habilitado")
    return
end

local function download(path)
    local h, err = http.get(BASE_URL .. "/" .. path)
    if not h then return nil, err end
    local content = h.readAll()
    h.close()
    return content
end

local function writeFile(path, content)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local c = f.readAll()
    f.close()
    return c
end

-- ============================================================
-- SELF-UPDATE
-- Descarga la ultima version del propio installer. Si cambio,
-- se reescribe y se re-ejecuta (con --post-update para no volver
-- a auto-actualizar y evitar loops).
-- ============================================================

if not skipSelfUpdate then
    write("Comprobando installer... ")
    local newInstaller, err = download("install.lua")
    if not newInstaller then
        print("sin red (" .. tostring(err) .. ")")
    else
        local current = readFile("install.lua") or ""
        if newInstaller ~= current then
            writeFile("install.lua", newInstaller)
            print("actualizado")
            print("Reiniciando installer...")
            print("")
            shell.run("install", "--post-update")
            return
        else
            print("al dia")
        end
    end
end

-- ============================================================
-- CREAR DIRECTORIOS Y DESCARGAR RESTO DE ARCHIVOS
-- ============================================================

-- Limpieza de la estructura antigua (miner/). Los archivos estan
-- ahora en lib/ + mining/ + lumber/ + farmer/.
if fs.exists("miner") and not fs.exists("lib") then
    print("Estructura antigua detectada. Eliminando /miner...")
    fs.delete("miner")
end

for _, d in ipairs(DIRS) do
    if not fs.exists(d) then fs.makeDir(d) end
end

local okCount, failCount = 0, 0
for _, path in ipairs(FILES) do
    write("Descargando " .. path .. "... ")
    local content, err = download(path)
    if not content then
        print("ERROR: " .. tostring(err))
        failCount = failCount + 1
    else
        writeFile(path, content)
        print("OK")
        okCount = okCount + 1
    end
end

print("")
print("Descargados: " .. okCount .. "  Fallados: " .. failCount)
if failCount == 0 then
    print("Instalacion completa. Reinicia la turtle.")
else
    print("Algunos archivos fallaron. Revisa la red.")
end
