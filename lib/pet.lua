-- ============================================================
-- PET MODULE
-- Tamagotchi-style virtual cat that lives on the dashboard of
-- mining / quarry turtles. Eats ores for XP + hunger, decays
-- over time, multi-frame mood animations + random fidgets so
-- the cat is never completely still. Notifies via pushEvent.
--
-- All sprites are exactly 7 chars wide x 3 lines, ASCII only,
-- to fit cols 32-38 rows 5-7 of the 39x13 turtle terminal.
-- The nameplate "Mochi L3" sits at row 8 cols 31-38.
-- ============================================================

local DEFAULT_NAME = "Mochi"

-- XP awarded per ore (also = hunger restored, capped at 100).
-- Keys are stripped of "minecraft:", "deepslate_", and "_ore" suffix.
local XP_TABLE = {
    coal           = 1,
    copper         = 1,
    raw_copper     = 1,
    iron           = 2,
    raw_iron       = 2,
    lapis          = 2,
    redstone       = 2,
    quartz         = 2,
    nether_quartz  = 2,
    gold           = 4,
    raw_gold       = 4,
    nether_gold    = 4,
    diamond        = 8,
    emerald        = 8,
    ancient_debris = 15,
}
local DEFAULT_XP = 2 -- any unrecognized ore
local BIG_FEED   = 8 -- triggers excited mood + ticker notification

-- Animation frames. Each entry: { line1, line2, line3 } all 7 chars.
-- Multiple frames per mood = visible motion (tail twitches, blinks,
-- mouth movement) so the cat is never frozen.
local FRAMES = {
    idle = {
        { " /\\_/\\ ", "(=o.o=)", "  >v<  " },
        { " /\\_/\\ ", "(=o.o=)", "  >v<~ " }, -- tail twitch right
        { " /\\_/\\ ", "(=-.-=)", "  >v<  " }, -- blink
        { " /\\_/\\ ", "(=o.o=)", " ~>v<  " }, -- tail twitch left
    },
    happy = {
        { " /\\_/\\ ", "(=^.^=)", "  >v<  " },
        { " /\\_/\\ ", "(=^o^=)", "  >v<~ " },
        { " /\\_/\\ ", "(=^.^=)", " ~>v<~ " },
        { " /\\_/\\ ", "(=^_^=)", " ~>v<  " },
    },
    eating = {
        { " /\\_/\\ ", "(=>w<=)", "  vmv  " },
        { " /\\_/\\ ", "(=>v<=)", "  >m<  " },
        { " /\\_/\\ ", "(=>w<=)", "  vmv  " },
    },
    excited = {
        { "*/\\_/\\*", "(=*o*=)", " *>0<* " },
        { " /\\_/\\ ", "(=*O*=)", "  >0<  " },
        { "*/\\_/\\ ", "(=*o*=)", "  >0<* " },
        { " /\\_/\\*", "(=*O*=)", " *>0<  " },
    },
    hungry = {
        { " /\\_/\\ ", "(=u.u=)", "  >.<  " },
        { " /\\_/\\ ", "(=T.T=)", "  >.<  " },
        { " /\\_/\\ ", "(=u.u=)", "  >.<  " },
        { " /\\_/\\ ", "(=>.<=)", "  >.<  " }, -- exasperated
    },
    starving = {
        { " /\\_/\\ ", "(=;_;=)", "  >~<  " },
        { " /\\_/\\ ", "(=T_T=)", "  >~<  " },
        { "  /\\_/\\", "(=;_;=)", "  >~<  " }, -- shake right
        { "/\\_/\\  ", "(=T_T=)", "  >~<  " }, -- shake left
    },
    sleepy = {
        { " /\\_/\\ ", "(=-_-=)", " z     " },
        { " /\\_/\\z", "(=-_-=)", "  z    " },
        { " /\\_/\\ ", "(=u_u=)", "   z   " },
        { " /\\_/\\Z", "(=-_-=)", "    z  " },
    },
    -- Fidget moods: short random "alive" actions that play during idle/happy.
    stretch = {
        { " /\\_/\\ ", "(=o.o=)", "  >v<  " },
        { " /=_=\\ ", "( -.-) ", "  >v<  " }, -- prep
        { "_/=_=\\_", "( ^o^ )", " /^v^\\ " }, -- full stretch
        { " /\\_/\\ ", "(=^.^=)", "  >v<  " }, -- relax
    },
    wag = {
        { " /\\_/\\ ", "(=o.o=)", "  >v<~~" },
        { " /\\_/\\ ", "(=o.o=)", "  >v<  " },
        { " /\\_/\\ ", "(=o.o=)", "~~>v<  " },
        { " /\\_/\\ ", "(=o.o=)", "  >v<  " },
    },
    look = {
        { " /\\_/\\ ", "(=o.o=)", "  >v<  " },
        { " /\\_/\\ ", "(=o.o<)", "  >v<  " }, -- looking left
        { " /\\_/\\ ", "(>o.o=)", "  >v<  " }, -- looking right
        { " /\\_/\\ ", "(=o.o=)", "  >v<  " },
    },
    yawn = {
        { " /\\_/\\ ", "(=o.o=)", "  >v<  " },
        { " /\\_/\\ ", "(=o.O=)", "  >O<  " },
        { " /\\_/\\ ", "(=o-O=)", "  vOv  " }, -- big yawn
        { " /\\_/\\ ", "(=u.u=)", "  >v<  " },
    },
}

local FIDGET_POOL    = { "stretch", "wag", "look", "yawn" }
local FIDGET_DUR     = 2.0   -- seconds (4 frames at 0.5s)
local FIDGET_MIN_GAP = 8     -- seconds between fidgets (random window)
local FIDGET_MAX_GAP = 22

-- Timing (seconds)
local DECAY_INTERVAL = 30
local SLEEPY_AFTER   = 120
local EATING_DUR     = 1.2
local EXCITED_DUR    = 2.0
local ANIM_INTERVAL  = 0.5   -- animator coroutine sleep period

-- ============================================================
-- Helpers
-- ============================================================

local function nowSecs()
    return os.epoch("utc") / 1000
end

local function stripPrefix(name)
    if not name then return "" end
    local short = name:gsub("^minecraft:", "")
    short = short:gsub("^deepslate_", "")
    short = short:gsub("_ore$", "")
    return short
end

local function xpForOre(name)
    local key = stripPrefix(name)
    local v = XP_TABLE[key]
    if v then return v, key end
    return DEFAULT_XP, key
end

local function xpForLevel(lvl)
    return lvl * lvl * 5
end

local function isFeedingMode()
    local m = state.mode or "mining"
    return m == "mining" or m == "quarry"
end

local function writeAt(x, y, text)
    term.setCursorPos(x, y)
    term.write(text)
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function init()
    if not state then return end
    state.petName          = state.petName          or DEFAULT_NAME
    state.petHunger        = state.petHunger        or 80
    state.petXp            = state.petXp            or 0
    state.petLevel         = state.petLevel         or 1
    state.petLastFedAt     = state.petLastFedAt     or 0
    state.petLastBigFeedAt = state.petLastBigFeedAt or 0
    -- Runtime-only (always reset on init):
    state.petLastTickAt          = 0
    state.petFrameIdx            = 0
    state.petFidgetMood          = nil
    state.petFidgetUntil         = 0
    state.petFidgetCooldownUntil = 0
    if state.petStarvingNotified == nil then
        state.petStarvingNotified = false
    end
end

function feedOre(name)
    if not state then return end
    local xp, key = xpForOre(name)

    local prevHunger = state.petHunger or 0
    state.petHunger = math.min(100, prevHunger + xp)

    if prevHunger < 15 and state.petHunger >= 15 then
        state.petStarvingNotified = false
    end

    state.petXp = (state.petXp or 0) + xp
    while state.petXp >= xpForLevel((state.petLevel or 1) + 1) do
        state.petLevel = (state.petLevel or 1) + 1
        if ui and ui.pushEvent then
            pcall(ui.pushEvent,
                (state.petName or DEFAULT_NAME) .. " sube a Lv" .. state.petLevel .. "!")
        end
        state.petLastBigFeedAt = nowSecs()
    end

    local now = nowSecs()
    state.petLastFedAt = now
    if xp >= BIG_FEED then
        state.petLastBigFeedAt = now
        if ui and ui.pushEvent then
            pcall(ui.pushEvent,
                (state.petName or DEFAULT_NAME) .. ": NOM! +" .. xp .. " XP (" .. key .. ")")
        end
    end

    -- Cancel any active fidget when something more interesting happens.
    state.petFidgetMood = nil
    state.petFidgetUntil = 0
end

-- Heavier tick: hunger decay + threshold notifications. Called from
-- drawDashboard. Also advances frame index (so drawDashboard alone
-- still animates if the animator coroutine isn't running).
function tick()
    if not state then return end
    local now = nowSecs()
    state.petFrameIdx = (state.petFrameIdx or 0) + 1

    if isFeedingMode() then
        if (state.petLastTickAt or 0) == 0 then
            state.petLastTickAt = now
        else
            local dt = now - state.petLastTickAt
            if dt >= DECAY_INTERVAL then
                local prevHunger = state.petHunger or 0
                local steps = math.floor(dt / DECAY_INTERVAL)
                state.petHunger = math.max(0, prevHunger - steps)
                state.petLastTickAt = state.petLastTickAt + steps * DECAY_INTERVAL

                if prevHunger >= 15 and state.petHunger < 15
                        and not state.petStarvingNotified then
                    if ui and ui.pushEvent then
                        pcall(ui.pushEvent,
                            (state.petName or DEFAULT_NAME) .. " tiene HAMBRE!")
                    end
                    state.petStarvingNotified = true
                end
            end
        end
    else
        state.petLastTickAt = now
    end
end

-- Light tick: only advances the frame index, no decay. Used by the
-- animator coroutine running every ANIM_INTERVAL seconds so the cat
-- moves continuously even between drawDashboard calls.
function animateFrame()
    if not state then return end
    state.petFrameIdx = (state.petFrameIdx or 0) + 1
end

function mood()
    if not state then return "idle" end
    local now = nowSecs()
    local hunger = state.petHunger or 80

    -- Highest priority: temporary feed-driven moods.
    if (state.petLastBigFeedAt or 0) > 0
            and (now - state.petLastBigFeedAt) < EXCITED_DUR then
        return "excited"
    end
    if (state.petLastFedAt or 0) > 0
            and (now - state.petLastFedAt) < EATING_DUR then
        return "eating"
    end

    -- Base mood from hunger / inactivity.
    local base
    if hunger < 15 then
        base = "starving"
    elseif hunger < 40 then
        base = "hungry"
    elseif (state.petLastFedAt or 0) > 0
            and (now - state.petLastFedAt) > SLEEPY_AFTER
            and hunger >= 30 then
        base = "sleepy"
    elseif hunger >= 70 then
        base = "happy"
    else
        base = "idle"
    end

    -- Fidgets only override calm moods (idle / happy). Never interrupt
    -- starving / hungry / sleepy / etc — those have their own animation.
    if base == "idle" or base == "happy" then
        if state.petFidgetMood and now < (state.petFidgetUntil or 0) then
            return state.petFidgetMood
        end
        if now >= (state.petFidgetCooldownUntil or 0) then
            state.petFidgetMood = FIDGET_POOL[math.random(#FIDGET_POOL)]
            state.petFidgetUntil = now + FIDGET_DUR
            state.petFidgetCooldownUntil = now + FIDGET_DUR
                + math.random(FIDGET_MIN_GAP, FIDGET_MAX_GAP)
            return state.petFidgetMood
        end
    else
        -- Mood became serious — drop any in-flight fidget.
        state.petFidgetMood = nil
        state.petFidgetUntil = 0
    end

    return base
end

function frame()
    local m = mood()
    local set = FRAMES[m] or FRAMES.idle
    local idx = ((state.petFrameIdx or 0) % #set) + 1
    return set[idx]
end

function snapshotFields()
    if not state then return nil end
    return {
        name   = state.petName or DEFAULT_NAME,
        hunger = state.petHunger or 0,
        level  = state.petLevel or 1,
        xp     = state.petXp or 0,
        mood   = mood(),
    }
end

function draw(x, y)
    local f = frame()
    if not f then return end
    for i = 1, 3 do
        writeAt(x, y + i - 1, f[i] or "       ")
    end
    local name = state.petName or DEFAULT_NAME
    local lvl  = state.petLevel or 1
    local plate = name .. " L" .. lvl
    if #plate > 8 then plate = plate:sub(1, 8) end
    plate = plate .. string.rep(" ", 8 - #plate)
    writeAt(x - 1, y + 3, plate)
end

-- Animator coroutine: loops forever, advances frame + redraws the cat
-- region every ANIM_INTERVAL seconds. Spawned in parallel with the
-- mining/quarry pipeline (see startup.lua). Skips drawing in modes
-- that don't show the pet so it doesn't corrupt other dashboards.
function animator()
    while true do
        sleep(ANIM_INTERVAL)
        if state and (state.mode == "mining" or state.mode == "quarry") then
            animateFrame()
            pcall(draw, 32, 5)
        end
    end
end
