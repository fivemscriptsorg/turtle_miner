-- ============================================================
-- MOVEMENT MODULE
-- Movimiento seguro con tracking de posicion y reintentos.
-- ============================================================

-- Actualiza la posicion segun el facing actual
local function updatePosForward(sign)
    sign = sign or 1
    if state.facing == 0 then state.x = state.x + sign
    elseif state.facing == 1 then state.z = state.z + sign
    elseif state.facing == 2 then state.x = state.x - sign
    elseif state.facing == 3 then state.z = state.z - sign
    end
end

-- ============================================================
-- GIROS
-- ============================================================

function turnRight()
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4
end

function turnLeft()
    turtle.turnLeft()
    state.facing = (state.facing - 1) % 4
    if state.facing < 0 then state.facing = state.facing + 4 end
end

function turnAround()
    turnRight()
    turnRight()
end

function faceDirection(target)
    while state.facing ~= target do
        local diff = (target - state.facing) % 4
        if diff == 1 then turnRight()
        elseif diff == 3 then turnLeft()
        else turnRight() end
    end
end

-- ============================================================
-- MOVIMIENTO SEGURO
-- Maneja grava que cae, mobs, y bloques que aparecen.
-- Intenta hasta maxTries veces antes de rendirse.
-- ============================================================

local MAX_TRIES = 8

function safeForward()
    inventory.autoRefuel(100)

    for attempt = 1, MAX_TRIES do
        if turtle.forward() then
            updatePosForward(1)
            return true
        end
        -- algo bloquea: cavar o atacar
        if turtle.detect() then
            turtle.dig()
        else
            turtle.attack() -- probablemente un mob
        end
        sleep(0.2)
    end
    return false
end

function safeUp()
    inventory.autoRefuel(100)

    for attempt = 1, MAX_TRIES do
        if turtle.up() then
            state.y = state.y + 1
            return true
        end
        if turtle.detectUp() then
            turtle.digUp()
        else
            turtle.attackUp()
        end
        sleep(0.2)
    end
    return false
end

function safeDown()
    inventory.autoRefuel(100)

    for attempt = 1, MAX_TRIES do
        if turtle.down() then
            state.y = state.y - 1
            return true
        end
        if turtle.detectDown() then
            turtle.digDown()
        else
            turtle.attackDown()
        end
        sleep(0.2)
    end
    return false
end

function safeBack()
    inventory.autoRefuel(100)

    if turtle.back() then
        updatePosForward(-1)
        return true
    end
    -- no hay dig atras, asi que giramos
    turnAround()
    local ok = safeForward()
    turnAround()
    return ok
end
