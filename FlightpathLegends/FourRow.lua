-- Flightpath Legends - Four in a Row: rules, computer opponent and online play.
--
-- Seven columns, six rows. Players take turns dropping a coin into a column; it falls to
-- the lowest free hole. Four of your coins in a line (across, down or diagonal) wins;
-- a full board is a draw. The first player drops gold coins, the second silver.
-- Every move is public, so both clients check each other's moves as they arrive.
local _, ns = ...

local FR = {}
ns.FourRow = FR

local C, P = ns.Comm, ns.Profile
local floor, max, min = math.floor, math.max, math.min

FR.COLS, FR.ROWS = 7, 6
FR.CELLS = FR.COLS * FR.ROWS
FR.TURN_TIME = 60 -- seconds per move
FR.GRACE = 30 -- extra seconds before a silent opponent forfeits
FR.MAX_MISSED = 3 -- missed turns in a row that forfeit the game
FR.LEVELS = { "Novice", "Adept", "Master" }
FR.COIN_NAMES = { "gold", "silver" }

------------------------------------------------------------------------
-- Rules. A board is a flat array: index (row - 1) * 7 + col, row 1 at the bottom;
-- values 1 (first player) or 2 (second player), nil = empty.
------------------------------------------------------------------------
function FR.Index(col, row) return (row - 1) * FR.COLS + col end

function FR.NewBoard() return {} end

-- Lowest free row in a column, or nil if it is full.
function FR.FreeRow(board, col)
    if type(col) ~= "number" or col < 1 or col > FR.COLS or col ~= floor(col) then return nil end
    for row = 1, FR.ROWS do
        if not board[FR.Index(col, row)] then return row end
    end
    return nil
end

function FR.Drop(board, col, who)
    local row = FR.FreeRow(board, col)
    if not row then return nil end
    board[FR.Index(col, row)] = who
    return row
end

function FR.Full(board)
    for col = 1, FR.COLS do
        if not board[FR.Index(col, FR.ROWS)] then return false end
    end
    return true
end

local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

-- The winning line through (col, row), or nil. Returns the cells { {col,row}, ... }
-- and whether the line is diagonal.
function FR.LineAt(board, col, row)
    local who = board[FR.Index(col, row)]
    if not who then return nil end
    for d = 1, #DIRS do
        local dc, dr = DIRS[d][1], DIRS[d][2]
        local cells = { { col, row } }
        for _, sign in ipairs({ 1, -1 }) do
            local c, r = col + dc * sign, row + dr * sign
            while c >= 1 and c <= FR.COLS and r >= 1 and r <= FR.ROWS and board[FR.Index(c, r)] == who do
                if sign == 1 then cells[#cells + 1] = { c, r } else table.insert(cells, 1, { c, r }) end
                c, r = c + dc * sign, r + dr * sign
            end
        end
        if #cells >= 4 then return cells, dr ~= 0 and dc ~= 0 end
    end
    return nil
end

-- Plays a list of columns from an empty board. Returns the board, or nil if a move is illegal
-- or comes after the game was already decided.
function FR.Replay(cols)
    local board = {}
    for i = 1, #cols do
        local row = FR.Drop(board, cols[i], (i % 2 == 1) and 1 or 2)
        if not row then return nil end
        if i < #cols and (FR.LineAt(board, cols[i], row) or FR.Full(board)) then return nil end
    end
    return board
end

function FR.ColName(col) return tostring(col) end

------------------------------------------------------------------------
-- Computer opponent: negamax with alpha-beta pruning, centre columns first.
------------------------------------------------------------------------
local ORDER = { 4, 3, 5, 2, 6, 1, 7 }
local WIN = 100000
local COLS, ROWS = FR.COLS, FR.ROWS

-- Every line of four on the board (69 of them) as four board indexes, and for each hole
-- the lines that pass through it. Precomputed so the search stays fast.
local LINES, LINES_AT = {}, {}
for idx = 1, FR.CELLS do LINES_AT[idx] = {} end
for d = 1, #DIRS do
    local dc, dr = DIRS[d][1], DIRS[d][2]
    for col = 1, COLS do
        for row = 1, ROWS do
            local ec, er = col + dc * 3, row + dr * 3
            if ec >= 1 and ec <= COLS and er >= 1 and er <= ROWS then
                local line = {}
                for k = 0, 3 do line[k + 1] = FR.Index(col + dc * k, row + dr * k) end
                LINES[#LINES + 1] = line
                for k = 1, 4 do table.insert(LINES_AT[line[k]], line) end
            end
        end
    end
end

-- Did the coin just placed at idx make four?
local function MadeFour(board, idx, who)
    local lines = LINES_AT[idx]
    for i = 1, #lines do
        local l = lines[i]
        if board[l[1]] == who and board[l[2]] == who and board[l[3]] == who and board[l[4]] == who then return true end
    end
    return false
end

-- Scores every line of four for `who` (positive is good for who).
local CENTRE = {}
for row = 1, ROWS do CENTRE[row] = FR.Index(4, row) end
local function Evaluate(board, who)
    local opp = 3 - who
    local score = 0
    for i = 1, ROWS do -- the centre column is worth holding
        local v = board[CENTRE[i]]
        if v == who then score = score + 3 elseif v == opp then score = score - 3 end
    end
    for i = 1, #LINES do
        local l = LINES[i]
        local mine, theirs = 0, 0
        for k = 1, 4 do
            local v = board[l[k]]
            if v == who then mine = mine + 1 elseif v == opp then theirs = theirs + 1 end
        end
        if theirs == 0 then
            if mine == 3 then score = score + 50 elseif mine == 2 then score = score + 8 end
        elseif mine == 0 then
            if theirs == 3 then score = score - 60 elseif theirs == 2 then score = score - 8 end
        end
    end
    return score
end

-- heights[col] = coins in that column (kept in step with the board during the search)
local function Negamax(board, heights, who, depth, alpha, beta, filled)
    if filled >= FR.CELLS then return 0 end
    -- an immediate win ends the search
    for i = 1, 7 do
        local col = ORDER[i]
        local h = heights[col]
        if h < ROWS then
            local idx = h * COLS + col
            board[idx] = who
            local won = MadeFour(board, idx, who)
            board[idx] = nil
            if won then return WIN + depth end
        end
    end
    if depth <= 0 then return Evaluate(board, who) end
    local best = -math.huge
    for i = 1, 7 do
        local col = ORDER[i]
        local h = heights[col]
        if h < ROWS then
            local idx = h * COLS + col
            board[idx] = who
            heights[col] = h + 1
            local v = -Negamax(board, heights, 3 - who, depth - 1, -beta, -alpha, filled + 1)
            heights[col] = h
            board[idx] = nil
            if v > best then best = v end
            if v > alpha then alpha = v end
            if alpha >= beta then break end
        end
    end
    return best
end

local function Filled(board)
    local n = 0
    for _ in pairs(board) do n = n + 1 end
    return n
end

local function LegalCols(board)
    local list = {}
    for col = 1, FR.COLS do if FR.FreeRow(board, col) then list[#list + 1] = col end end
    return list
end
FR.LegalCols = LegalCols

-- A column that wins at once for who, or nil.
local function WinningCol(board, who)
    for i = 1, #ORDER do
        local col = ORDER[i]
        local row = FR.FreeRow(board, col)
        if row then
            local idx = FR.Index(col, row)
            board[idx] = who
            local won = FR.LineAt(board, col, row)
            board[idx] = nil
            if won then return col end
        end
    end
end

local DEPTH = { 1, 4, 6 }

-- Picks a column for `who` at the given level (1 Novice, 2 Adept, 3 Master).
function FR.AIMove(board, who, level)
    local legal = LegalCols(board)
    if #legal == 0 then return nil end
    local win = WinningCol(board, who)
    if win then return win end
    local block = WinningCol(board, 3 - who)
    if level <= 1 then
        -- Novice: takes wins, blocks most of the time, otherwise leans to the middle.
        if block and math.random() < 0.8 then return block end
        local weighted = {}
        for _, col in ipairs(legal) do
            for _ = 1, 4 - math.abs(col - 4) do weighted[#weighted + 1] = col end
        end
        return weighted[math.random(1, #weighted)]
    end
    if block then return block end
    local depth = DEPTH[min(level, #DEPTH)]
    local filled = Filled(board)
    local heights = {}
    for col = 1, COLS do heights[col] = (FR.FreeRow(board, col) or (ROWS + 1)) - 1 end
    local bestScore, bestCols = -math.huge, {}
    for i = 1, #ORDER do
        local col = ORDER[i]
        local row = FR.FreeRow(board, col)
        if row then
            local idx = FR.Index(col, row)
            board[idx] = who
            heights[col] = row
            local v = -Negamax(board, heights, 3 - who, depth - 1, -math.huge, math.huge, filled + 1)
            heights[col] = row - 1
            board[idx] = nil
            if v > bestScore then bestScore, bestCols = v, { col }
            elseif v == bestScore then bestCols[#bestCols + 1] = col end
        end
    end
    -- Adept sometimes picks among equally good moves at random; Master keeps the most central.
    if level == 2 then return bestCols[math.random(1, #bestCols)] end
    return bestCols[1]
end

------------------------------------------------------------------------
-- Session
------------------------------------------------------------------------
FR.current = nil
local unacked = {}

local function Fire(event, ...) ns.Fire(event, ...) end

local function NewSession(o)
    local s = {
        id = o.id or ns.NewId(), mode = o.mode, opp = o.opp, oppName = o.oppName or o.opp,
        iFirst = o.iFirst, level = o.level,
        phase = "play", -- play -> over
        board = {}, moves = {}, -- moves: list of columns
        turn = 1, -- whose coin drops next: 1 (first player) or 2
        missed = 0, seq = 0, seen = {},
        turnStart = ns.Now(),
    }
    s.myCoin = s.iFirst and 1 or 2
    s.white = s.iFirst and ns.me or s.opp
    s.black = s.iFirst and s.opp or ns.me
    return s
end

function FR.Busy()
    local s = FR.current
    return s ~= nil and s.phase ~= "over" and s.mode == "online"
end

-- Moves so far (for the Live Games list).
function FR.MoveCount(s) return #s.moves end

function FR.Active()
    local s = FR.current
    return s ~= nil and s.phase ~= "over"
end

function FR.MyTurn()
    local s = FR.current
    return s ~= nil and s.phase == "play" and s.mode ~= "spectate" and s.turn == s.myCoin
end

-- Reliable whisper (resent until acknowledged).
local function Send(s, cmd, ...)
    s.seq = s.seq + 1
    local text = ns.Join(cmd, s.id, s.seq, ...)
    local key = s.id .. ":" .. s.seq
    unacked[key] = { target = s.opp, text = text, next = ns.Now() + 4, tries = 0 }
    C.SendRaw("WHISPER", s.opp, text)
    return key, text
end

local function Relay(s, ...)
    if not s.spectators then return end
    local text = ns.Join(...)
    for name in pairs(s.spectators) do C.SendRaw("WHISPER", name, text) end
end

-- Accepts a reliable message from the opponent: returns the session if it is new.
local function Accept(sender, parts)
    local gid, seq = parts[2], tonumber(parts[3])
    local s = FR.current
    if not (s and s.id == gid and s.mode == "online" and s.opp == sender and seq) then return nil end
    C.Whisper(sender, "FK", gid, seq)
    if s.seen[seq] then return nil end
    s.seen[seq] = true
    return s
end

C.handlers.FK = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local key = (parts[2] or "") .. ":" .. (parts[3] or "")
    local u = unacked[key]
    if u and u.target == sender then unacked[key] = nil end
end

local function Statement(s, res)
    if s.mode ~= "online" then return end
    ns.Ledger.StateOwn({ id = s.id, white = s.white, black = s.black, mode = "online", kind = "f" }, res)
end

local function Begin(s)
    FR.current = s
    Fire("FR_STARTED", s)
    Fire("FR_CHANGED", s)
    if s.mode == "online" then
        Statement(s, nil) -- witnessed record: both players state that this game started
        ns.Game.Announce(true)
    end
    if s.mode == "ai" and not s.iFirst then FR.AITurnSoon(s) end
end

-- Online game, after a challenge was accepted. iFirst: we drop the first coin.
function FR.StartOnline(id, opp, iFirst)
    local s = NewSession({ id = id, mode = "online", opp = opp, iFirst = iFirst })
    Begin(s)
    return s
end

function FR.StartAI(level)
    level = level or 2
    local s = NewSession({ mode = "ai", opp = "Computer", iFirst = math.random(1, 2) == 1, level = level })
    s.oppName = "Computer (" .. FR.LEVELS[level] .. ")"
    s.white = s.iFirst and ns.me or s.oppName
    s.black = s.iFirst and s.oppName or ns.me
    Begin(s)
    return s
end

------------------------------------------------------------------------
-- Moves
------------------------------------------------------------------------
local Finish -- forward

-- Applies the next move (by whoever's turn it is). Returns the row, or nil if illegal.
local function Apply(s, col)
    local who = s.turn
    local row = FR.Drop(s.board, col, who)
    if not row then return nil end
    s.moves[#s.moves + 1] = col
    s.last = { col = col, row = row }
    Fire("FR_MOVE", s, #s.moves, col, row, who)
    if s.mode ~= "spectate" then Relay(s, "FW", s.id, #s.moves, col) end
    local line, diagonal = FR.LineAt(s.board, col, row)
    if line then
        s.line, s.diagonal = line, diagonal
        if s.mode == "spectate" then return row end
        Finish(s, who == s.myCoin and "win" or "loss", "four")
        return row
    end
    if FR.Full(s.board) then
        if s.mode == "spectate" then return row end
        Finish(s, "draw", "full")
        return row
    end
    s.turn = 3 - who
    s.turnStart = ns.Now()
    Fire("FR_CHANGED", s)
    if s.mode == "ai" and s.turn ~= s.myCoin then FR.AITurnSoon(s) end
    return row
end

-- Drops our coin into a column (our turn only).
function FR.DropCoin(col, auto)
    local s = FR.current
    if not FR.MyTurn() then return false end
    if not FR.FreeRow(s.board, col) then return false end
    if not auto then s.missed = 0 end
    if s.mode == "online" then Send(s, "FM", #s.moves + 1, col) end
    Apply(s, col)
    return true
end

C.handlers.FM = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "play" or s.turn == s.myCoin then return end
    local n, col = tonumber(parts[4]), tonumber(parts[5])
    if n ~= #s.moves + 1 or not FR.FreeRow(s.board, col) then return end
    Apply(s, col)
end

function FR.AITurnSoon(s)
    ns.After(0.7 + math.random() * 0.5, function()
        if FR.current ~= s or s.phase ~= "play" or s.turn == s.myCoin then return end
        local col = FR.AIMove(s.board, s.turn, s.level)
        if col then Apply(s, col) end
    end)
end

------------------------------------------------------------------------
-- Ending
------------------------------------------------------------------------
-- outcome: "win" | "loss" | "draw"; reason: four, full, resign, time, abandoned
Finish = function(s, outcome, reason)
    if s.phase == "over" then return end
    s.phase = "over"
    s.outcome, s.reason = outcome, reason
    if s.mode == "online" then
        local iWhite = s.white == ns.me
        local res = "1/2"
        if outcome == "win" then res = iWhite and "1-0" or "0-1"
        elseif outcome == "loss" then res = iWhite and "0-1" or "1-0" end
        Statement(s, res)
        local winner = (outcome == "win" and ns.me) or (outcome == "loss" and s.opp) or ""
        Relay(s, "FE", s.id, winner, reason)
    end
    if s.mode ~= "spectate" then
        local mine = 0
        for i = 1, #s.moves do
            if ((i % 2 == 1) and 1 or 2) == s.myCoin then mine = mine + 1 end
        end
        P.RecordGame({
            mode = "c4", outcome = outcome, vsAI = s.mode == "ai", aiLevel = s.level or 0, opp = s.opp,
            myCoins = mine, diagonal = (reason == "four" and s.diagonal) or false,
            lastHole = reason == "four" and #s.moves == FR.CELLS,
        })
    end
    Fire("FR_OVER", s)
    Fire("FR_CHANGED", s)
    if s.mode == "online" then ns.Game.Announce(true) end
end

function FR.Resign()
    local s = FR.current
    if not s or s.phase == "over" then return end
    if s.mode == "spectate" then
        FR.StopWatching()
        return
    end
    if s.mode == "online" then Send(s, "FQ", "resign") end
    Finish(s, "loss", "resign")
end

C.handlers.FQ = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase == "over" then return end
    Finish(s, "win", parts[4] == "time" and "time" or "resign")
end

------------------------------------------------------------------------
-- Spectating: the player relays every move.
--   FX;id;host;guest;white;moves   FW;id;n;col   FE;id;winner;reason
------------------------------------------------------------------------
function FR.HandleWatchRequest(sender)
    local s = FR.current
    if not (s and s.mode == "online" and s.phase == "play" and ns.db.settings.allowSpectators) then return false end
    s.spectators = s.spectators or {}
    local n = 0
    for _ in pairs(s.spectators) do n = n + 1 end
    if not s.spectators[sender] and n >= 5 then return false end
    s.spectators[sender] = true
    C.Whisper(sender, "FX", s.id, ns.me, s.opp, s.white, table.concat(s.moves))
    return true
end

function FR.DropSpectator(sender, id)
    local s = FR.current
    if s and s.id == id and s.spectators then s.spectators[sender] = nil end
end

C.handlers.FX = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    if not (ns.Game.watchPending and ns.SameName(ns.Game.watchPending, sender)) then return end
    local cols = {}
    for d in string.gmatch(parts[6] or "", "%d") do cols[#cols + 1] = tonumber(d) end
    local board = FR.Replay(cols)
    if not board then return end
    ns.Game.watchPending = nil
    local s = NewSession({ id = parts[2], mode = "spectate", opp = parts[4] })
    s.source = sender
    s.host, s.guest = parts[3], parts[4]
    s.white = parts[5]
    s.black = ns.SameName(s.white, s.host) and s.guest or s.host
    s.myCoin = 0 -- neither side
    s.board, s.moves = board, cols
    s.turn = (#cols % 2 == 0) and 1 or 2
    FR.current = s
    Fire("FR_STARTED", s)
    Fire("FR_CHANGED", s)
end

C.handlers.FW = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = FR.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2] and s.phase == "play") then return end
    local n, col = tonumber(parts[3]), tonumber(parts[4])
    if n ~= #s.moves + 1 or not FR.FreeRow(s.board, col) then return end
    Apply(s, col) -- if this decided the game, FE follows with how it ended
end

C.handlers.FE = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = FR.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2]) then return end
    s.phase = "over"
    s.winner = parts[3] ~= "" and parts[3] or nil
    s.reason = parts[4]
    P.RecordGame({ mode = "spectate", outcome = "none" })
    Fire("FR_OVER", s)
    Fire("FR_CHANGED", s)
end

function FR.StopWatching()
    local s = FR.current
    if s and s.mode == "spectate" and s.phase ~= "over" then
        C.Whisper(s.source, "SX", s.id)
        s.phase = "over"
        Fire("FR_CHANGED", s)
    end
end

------------------------------------------------------------------------
-- Timers and resends
------------------------------------------------------------------------
ns.On("CHESS_TICK", function()
    local now = ns.Now()
    for key, u in pairs(unacked) do
        if now >= u.next then
            if C.IsQueued(u.text) then
                u.next = now + 2
            else
                u.tries = u.tries + 1
                if u.tries > 15 then unacked[key] = nil else
                    u.next = now + 5
                    C.SendRaw("WHISPER", u.target, u.text)
                end
            end
        end
    end
    local s = FR.current
    if not s or s.phase ~= "play" or s.mode == "spectate" then return end
    local elapsed = now - (s.turnStart or now)
    if s.turn == s.myCoin and elapsed >= FR.TURN_TIME then
        -- Out of time: a coin is dropped for us.
        s.missed = s.missed + 1
        if s.missed >= FR.MAX_MISSED then
            if s.mode == "online" then Send(s, "FQ", "time") end
            Finish(s, "loss", "time")
            return
        end
        local legal = LegalCols(s.board)
        if #legal > 0 then
            ns.Print("time's up - a coin was dropped for you (" .. s.missed .. "/" .. FR.MAX_MISSED .. " missed turns).")
            FR.DropCoin(legal[math.random(1, #legal)], true)
        end
    elseif s.mode == "online" and s.turn ~= s.myCoin and elapsed >= FR.TURN_TIME * FR.MAX_MISSED + FR.GRACE then
        Finish(s, "win", "abandoned") -- the opponent has gone silent
    end
end)

function FR.TimeLeft()
    local s = FR.current
    if not s or s.phase ~= "play" then return 0 end
    return max(0, FR.TURN_TIME - (ns.Now() - (s.turnStart or ns.Now())))
end
