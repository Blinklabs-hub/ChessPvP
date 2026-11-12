-- ChessPvP: practice opponent. Alpha-beta search run in small slices so the game never freezes.
local _, ns = ...

local AI = {}
ns.AI = AI

local E = ns.Engine
local floor = math.floor
local OFF = E.OFF
local Make, Unmake, GenPseudo, Attacked = E.Make, E.Unmake, E.GenPseudo, E.Attacked

AI.LEVELS = {
    { name = "Novice", depth = 1, blunder = 0.35, quiesce = false },
    { name = "Adept", depth = 2, blunder = 0.08, quiesce = false },
    { name = "Master", depth = 3, blunder = 0, quiesce = true },
}

local VALUE = { 100, 320, 330, 500, 900, 0 }
local MATE = 100000

-- Piece-square tables, written from White's side with rank 8 on the first row.
local PST_RAW = {
    { -- pawn
        0, 0, 0, 0, 0, 0, 0, 0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
        5, 5, 10, 25, 25, 10, 5, 5,
        0, 0, 0, 20, 20, 0, 0, 0,
        5, -5, -10, 0, 0, -10, -5, 5,
        5, 10, 10, -20, -20, 10, 10, 5,
        0, 0, 0, 0, 0, 0, 0, 0,
    },
    { -- knight
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20, 0, 0, 0, 0, -20, -40,
        -30, 0, 10, 15, 15, 10, 0, -30,
        -30, 5, 15, 20, 20, 15, 5, -30,
        -30, 0, 15, 20, 20, 15, 0, -30,
        -30, 5, 10, 15, 15, 10, 5, -30,
        -40, -20, 0, 5, 5, 0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50,
    },
    { -- bishop
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 10, 10, 5, 0, -10,
        -10, 5, 5, 10, 10, 5, 5, -10,
        -10, 0, 10, 10, 10, 10, 0, -10,
        -10, 10, 10, 10, 10, 10, 10, -10,
        -10, 5, 0, 0, 0, 0, 5, -10,
        -20, -10, -10, -10, -10, -10, -10, -20,
    },
    { -- rook
        0, 0, 0, 0, 0, 0, 0, 0,
        5, 10, 10, 10, 10, 10, 10, 5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        0, 0, 0, 5, 5, 0, 0, 0,
    },
    { -- queen
        -20, -10, -10, -5, -5, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 5, 5, 5, 0, -10,
        -5, 0, 5, 5, 5, 5, 0, -5,
        0, 0, 5, 5, 5, 5, 0, -5,
        -10, 5, 5, 5, 5, 5, 0, -10,
        -10, 0, 5, 0, 0, 0, 0, -10,
        -20, -10, -10, -5, -5, -10, -10, -20,
    },
    { -- king (middlegame)
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -10, -20, -20, -20, -20, -20, -20, -10,
        20, 20, 0, 0, 0, 0, 20, 20,
        20, 30, 10, 0, 0, 10, 30, 20,
    },
}

-- score[piece][square] from White's point of view, material included.
local SCORE = {}
for t = 1, 6 do
    local w, bl = {}, {}
    for rank = 0, 7 do
        for file = 0, 7 do
            local sq = E.Sq(file, rank)
            w[sq] = VALUE[t] + PST_RAW[t][(7 - rank) * 8 + file + 1]
            bl[sq] = -(VALUE[t] + PST_RAW[t][rank * 8 + file + 1])
        end
    end
    SCORE[t] = w
    SCORE[-t] = bl
end

local function Evaluate(pos)
    local b = pos.b
    local s = 0
    for sq = 21, 98 do
        local p = b[sq]
        if p ~= 0 and p ~= OFF then
            s = s + SCORE[p][sq]
        end
    end
    return s * pos.turn
end

------------------------------------------------------------------------
-- Search
------------------------------------------------------------------------
local nodes = 0
local sliceStart = 0
local deadline = 0
local aborted = false
local SLICE_MS = 10
local buffers = {} -- one move list (and score list) per ply

local function Tick()
    nodes = nodes + 1
    if nodes % 128 == 0 then
        local now = debugprofilestop()
        if now > deadline then
            aborted = true
        elseif now - sliceStart > SLICE_MS then
            coroutine.yield()
        end
    end
end

-- Orders captures first (most valuable victim, least valuable attacker).
local function Order(pos, list, n, ply)
    local buf = buffers[ply]
    local sc = buf.scores
    local b = pos.b
    for i = 1, n do
        local m = list[i]
        local victim = b[floor(m / 128) % 128]
        local s = 0
        if victim ~= 0 then
            local attacker = b[m % 128]
            s = VALUE[victim < 0 and -victim or victim] * 10 - VALUE[attacker < 0 and -attacker or attacker]
        end
        if floor(m / 16384) % 8 == 5 then s = s + 8000 end
        sc[i] = s
    end
    for i = 2, n do
        local m, s = list[i], sc[i]
        local j = i - 1
        while j >= 1 and sc[j] < s do
            list[j + 1] = list[j]
            sc[j + 1] = sc[j]
            j = j - 1
        end
        list[j + 1] = m
        sc[j + 1] = s
    end
end

local function GetBuffer(ply)
    local buf = buffers[ply]
    if not buf then
        buf = { moves = {}, scores = {} }
        buffers[ply] = buf
    end
    return buf
end

local function Quiesce(pos, alpha, beta, ply, depthLeft)
    Tick()
    if aborted then return alpha end
    local stand = Evaluate(pos)
    if stand >= beta then return beta end
    if stand > alpha then alpha = stand end
    if depthLeft <= 0 then return alpha end
    local buf = GetBuffer(ply)
    local list = buf.moves
    local n = GenPseudo(pos, list, true)
    Order(pos, list, n, ply)
    local c = pos.turn
    for i = 1, n do
        Make(pos, list[i])
        if Attacked(pos, pos.ks[c], -c) then
            Unmake(pos)
        else
            local score = -Quiesce(pos, -beta, -alpha, ply + 1, depthLeft - 1)
            Unmake(pos)
            if aborted then return alpha end
            if score >= beta then return beta end
            if score > alpha then alpha = score end
        end
    end
    return alpha
end

local function Search(pos, depth, alpha, beta, ply, quiesce)
    if depth <= 0 then
        if quiesce then return Quiesce(pos, alpha, beta, ply, 4) end
        Tick()
        return Evaluate(pos)
    end
    Tick()
    if aborted then return alpha end
    local buf = GetBuffer(ply)
    local list = buf.moves
    local n = GenPseudo(pos, list)
    Order(pos, list, n, ply)
    local c = pos.turn
    local legal = 0
    for i = 1, n do
        Make(pos, list[i])
        if Attacked(pos, pos.ks[c], -c) then
            Unmake(pos)
        else
            legal = legal + 1
            local score = -Search(pos, depth - 1, -beta, -alpha, ply + 1, quiesce)
            Unmake(pos)
            if aborted then return alpha end
            if score >= beta then return beta end
            if score > alpha then alpha = score end
        end
    end
    if legal == 0 then
        if Attacked(pos, pos.ks[c], -c) then return -MATE + ply end
        return 0
    end
    return alpha
end

-- Picks a move for the side to move. Runs inside a coroutine.
local function Think(pos, level)
    local cfg = AI.LEVELS[level] or AI.LEVELS[1]
    local legal = E.GenLegal(pos)
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1] end

    -- Shuffle so equal moves vary from game to game.
    for i = #legal, 2, -1 do
        local j = math.random(1, i)
        legal[i], legal[j] = legal[j], legal[i]
    end
    if cfg.blunder > 0 and math.random() < cfg.blunder then
        return legal[1]
    end

    local best = legal[1]
    for depth = 1, cfg.depth do
        local alpha, beta = -MATE * 2, MATE * 2
        local iterBest = nil
        for i = 1, #legal do
            Make(pos, legal[i])
            local score = -Search(pos, depth - 1, -beta, -alpha, 1, cfg.quiesce)
            Unmake(pos)
            if aborted then break end
            if score > alpha then
                alpha = score
                iterBest = legal[i]
            end
        end
        if aborted then
            break
        end
        if iterBest then
            best = iterBest
            -- Search the best move first on the next, deeper pass.
            for i = 1, #legal do
                if legal[i] == best then
                    legal[i] = legal[1]
                    legal[1] = best
                    break
                end
            end
        end
    end
    return best
end

------------------------------------------------------------------------
-- Driver: resumes the search a few milliseconds per frame
------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local job

local function Step()
    if not job then
        driver:SetScript("OnUpdate", nil)
        return
    end
    local now = GetTime()
    if job.co then
        sliceStart = debugprofilestop()
        local ok, result = coroutine.resume(job.co)
        if not ok then
            job = nil
            driver:SetScript("OnUpdate", nil)
            error("ChessPvP AI: " .. tostring(result), 0)
        end
        if coroutine.status(job.co) == "dead" then
            job.move = result
            job.co = nil
        end
    elseif now >= job.readyAt then
        local j = job
        job = nil
        driver:SetScript("OnUpdate", nil)
        j.callback(j.move)
    end
end

-- Starts thinking about `pos` (which is copied). callback(move) fires when done.
function AI.Start(pos, level, callback)
    AI.Cancel()
    local copy = E.Clone(pos)
    nodes = 0
    aborted = false
    deadline = debugprofilestop() + 6000
    job = {
        co = coroutine.create(function() return Think(copy, level) end),
        callback = callback,
        readyAt = GetTime() + 0.6, -- a short pause so replies do not feel instant
    }
    driver:SetScript("OnUpdate", Step)
end

function AI.Cancel()
    job = nil
    driver:SetScript("OnUpdate", nil)
end

function AI.IsThinking()
    return job ~= nil
end

-- Synchronous variant used by the test suite.
function AI.ThinkNow(pos, level)
    nodes = 0
    aborted = false
    deadline = debugprofilestop() + 60000
    sliceStart = debugprofilestop() + 1e12
    return Think(E.Clone(pos), level)
end
