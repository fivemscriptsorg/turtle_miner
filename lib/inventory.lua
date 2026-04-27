-- ============================================================
-- INVENTORY MODULE
-- Gestion de slots, filtrado de items, auto-refuel con coal,
-- coloca cofres cuando el inventario se llena.
-- ============================================================

-- Items que consideramos "basura" (se descartan si hay que hacer sitio)
local JUNK_ITEMS = {
    ["minecraft:cobblestone"] = true,
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:stone"] = true,
    ["minecraft:deepslate"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:granite"] = true,
    ["minecraft:diorite"] = true,
    ["minecraft:andesite"] = true,
    ["minecraft:tuff"] = true,
    ["minecraft:netherrack"] = true,
    ["minecraft:basalt"] = true,
    ["minecraft:blackstone"] = true,
    ["minecraft:end_stone"] = true,
    ["minecraft:sand"] = true,
    ["minecraft:sandstone"] = true,
}

-- Items que la turtle necesita conservar (combustible, cofres)
local KEEP_ITEMS = {
    ["minecraft:coal"] = true,
    ["minecraft:charcoal"] = true,
    ["minecraft:coal_block"] = true,
    ["minecraft:chest"] = true,
}

-- Saplings (lumber)
local SAPLINGS = {
    ["minecraft:oak_sapling"] = true,
    ["minecraft:spruce_sapling"] = true,
    ["minecraft:birch_sapling"] = true,
    ["minecraft:jungle_sapling"] = true,
    ["minecraft:acacia_sapling"] = true,
    ["minecraft:dark_oak_sapling"] = true,
    ["minecraft:cherry_sapling"] = true,
    ["minecraft:mangrove_propagule"] = true,
}

-- Semillas y tuberculos que tambien replantan (farmer)
local SEEDS = {
    ["minecraft:wheat_seeds"] = true,
    ["minecraft:beetroot_seeds"] = true,
    ["minecraft:carrot"] = true,
    ["minecraft:potato"] = true,
}

function isJunk(name)
    return JUNK_ITEMS[name] == true
end

function isFuel(name)
    return name == "minecraft:coal" or name == "minecraft:charcoal"
        or name == "minecraft:coal_block"
end

function isChest(name)
    return name == "minecraft:chest" or name == "minecraft:trapped_chest"
end

function isEnderChest(name)
    return name == "minecraft:ender_chest"
end

function isOre(name)
    if not name then return false end
    return name:find("_ore$") ~= nil
        or name == "minecraft:ancient_debris"
        or name == "minecraft:raw_iron"
        or name == "minecraft:raw_copper"
        or name == "minecraft:raw_gold"
end

function isSapling(name)
    return SAPLINGS[name] == true
end

function isSeed(name)
    return SEEDS[name] == true
end

function isBonemeal(name)
    return name == "minecraft:bone_meal"
end

function isLog(name)
    if not name then return false end
    return name:find("_log$") ~= nil
        or name:find("_wood$") ~= nil
        or name == "minecraft:mangrove_roots"
end

-- Items que se conservan al volcar en un cofre.
-- Combustible, cofres, saplings, semillas y bonemeal.
function isKeepWhenDumping(name)
    if not name then return false end
    if KEEP_ITEMS[name] then return true end
    if isSapling(name) or isSeed(name) or isBonemeal(name) then return true end
    return false
end

-- Numero de slots ocupados
function slotsUsed()
    local used = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then used = used + 1 end
    end
    return used, 16
end

function isFull()
    return slotsUsed() >= 16
end

function isAlmostFull()
    return slotsUsed() >= 14
end

-- Busca el primer slot con un item cuyo nombre coincida con el filtro (func)
function findSlot(filter)
    for i = 1, 16 do
        local detail = turtle.getItemDetail(i)
        if detail and filter(detail.name) then
            return i, detail
        end
    end
    return nil
end

-- ============================================================
-- REFUEL
-- ============================================================

-- Rellena con coal si el nivel cae por debajo del minimo
function autoRefuel(minLevel)
    minLevel = minLevel or 200
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then return true end
    if fuel >= minLevel then return true end

    ui.setStatus("Repostando...")
    local currentSlot = turtle.getSelectedSlot()
    local refueled = false

    for i = 1, 16 do
        local detail = turtle.getItemDetail(i)
        if detail and isFuel(detail.name) then
            turtle.select(i)
            -- dejamos 1 stack minimo de coal para mas tarde si hay de sobra
            local count = turtle.getItemCount(i)
            local toBurn = count
            if count > 32 then toBurn = count - 16 end
            if turtle.refuel(toBurn) then
                refueled = true
                if turtle.getFuelLevel() >= minLevel then break end
            end
        end
    end

    turtle.select(currentSlot)
    return refueled or turtle.getFuelLevel() >= minLevel
end

-- ============================================================
-- DROP JUNK
-- ============================================================

-- Tira items basura para hacer sitio. No tira ores, coal ni cofres.
function dropJunk()
    local currentSlot = turtle.getSelectedSlot()
    local dropped = 0
    for i = 1, 16 do
        local detail = turtle.getItemDetail(i)
        if detail and isJunk(detail.name) then
            turtle.select(i)
            turtle.drop()
            dropped = dropped + 1
        end
    end
    turtle.select(currentSlot)
    return dropped
end

-- Compacta items iguales entre slots.
-- Cachea los details una sola vez (16 llamadas en vez de O(n^2)).
function compact()
    local names = {}
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        names[i] = d and d.name or nil
    end

    for i = 1, 16 do
        if names[i] and turtle.getItemCount(i) > 0 then
            for j = i + 1, 16 do
                if names[j] == names[i] and turtle.getItemCount(j) > 0 then
                    turtle.select(j)
                    turtle.transferTo(i)
                    if turtle.getItemCount(j) == 0 then
                        names[j] = nil
                    end
                end
            end
        end
    end
    turtle.select(1)
end

-- ============================================================
-- CHEST PLACEMENT
-- Coloca un cofre a la derecha de la turtle (sin bloquear el paso).
-- La turtle esta mirando en la direccion del tunel; giramos a la
-- derecha, cavamos un hueco en la pared, metemos el cofre, volvemos.
-- Luego vaciamos inventario (menos coal y cofres).
-- ============================================================

function placeChest()
    ui.setStatus("Colocando cofre...")

    -- buscar un cofre en el inventario
    local slot = findSlot(isChest)
    if not slot then
        ui.setStatus("Sin cofres!")
        sleep(1)
        return false
    end

    local currentSlot = turtle.getSelectedSlot()

    -- girar a la derecha, cavar hueco en la pared, colocar cofre
    movement.turnRight()
    if turtle.detect() then turtle.dig() end
    turtle.select(slot)
    local ok = turtle.place()
    if not ok then
        -- fallback: intentar de nuevo tras limpiar
        sleep(0.3)
        if turtle.detect() then turtle.dig() end
        ok = turtle.place()
    end

    if ok then
        state.chestsPlaced = state.chestsPlaced + 1
        -- vaciar inventario (todo menos coal y cofres)
        for i = 1, 16 do
            local detail = turtle.getItemDetail(i)
            if detail and not isFuel(detail.name) and not isChest(detail.name) then
                turtle.select(i)
                turtle.drop()
            end
        end
    end

    turtle.select(currentSlot)
    movement.turnLeft() -- volver a la direccion original
    return ok
end

-- Si el inventario esta casi lleno:
-- 1) compactar
-- 2) tirar basura
-- 3) si sigue lleno, colocar cofre
function handleFullInventory()
    compact()
    if not isAlmostFull() then return true end

    dropJunk()
    if not isAlmostFull() then return true end

    return placeChest()
end

-- ============================================================
-- DUMP INTO CHEST
-- Para lumber/farmer: vuelca todo menos items a conservar
-- (fuel, cofres, saplings, semillas, bonemeal) en el cofre que
-- haya en la direccion indicada. direction: "forward"|"up"|"down".
-- ============================================================

function dumpInto(direction)
    local dropFn = turtle.drop
    if direction == "up" then dropFn = turtle.dropUp
    elseif direction == "down" then dropFn = turtle.dropDown
    end
    local currentSlot = turtle.getSelectedSlot()
    local dumped = 0
    for i = 1, 16 do
        local detail = turtle.getItemDetail(i)
        if detail and not isKeepWhenDumping(detail.name) then
            turtle.select(i)
            if dropFn() then dumped = dumped + 1 end
        end
    end
    turtle.select(currentSlot)
    return dumped
end

-- Busca y selecciona el primer slot cuyo item pase el filtro.
-- Devuelve el indice del slot o nil.
function selectSlotWith(filterFn)
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and filterFn(d.name) then
            turtle.select(i)
            return i
        end
    end
    return nil
end
