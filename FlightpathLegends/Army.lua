-- Flightpath Legends - Hidden Army: rules, sealed setups, the computer general and online play.
--
-- An 8x8 battlefield with two lakes. Each side hides 16 ranked units in its three back rows;
-- the opponent sees where they stand but not what they are. Units move one square (Scouts any
-- distance in a line); moving onto an enemy starts a fight that reveals both ranks. Capturing
-- the enemy Banner wins, and so does leaving the enemy with no unit that can move.
-- Fair play: each setup is sealed with SHA-256 before the first move and revealed at the end;
-- every move and fight is then replayed against both real setups.
local _, ns = ...

local HA = {}
ns.Army = HA

local C, P = ns.Comm, ns.Profile
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

HA.SIZE = 8
HA.TURN_TIME = 60
HA.SETUP_TIME = 120
HA.GRACE = 30
HA.MAX_MISSED = 3
HA.MAX_MOVES = 300
HA.LEVELS = { "Novice", "Adept", "Master" }

-- Unit letters, in rank order. B and N never move.
HA.ORDER = { "W", "C", "K", "F", "S", "X", "R", "B", "N" }
HA.COUNT = { W = 1, C = 1, K = 2, F = 3, S = 2, X = 2, R = 1, B = 3, N = 1 }
HA.RANK = { W = 10, C = 8, K = 6, F = 4, S = 3, X = 2, R = 1 }
HA.NAME = { W = "Warlord", C = "Champion", K = "Knight", F = "Footman", S = "Sapper", X = "Scout", R = "Assassin", B = "Bomb", N = "Banner" }
HA.UNITS = 16

------------------------------------------------------------------------
-- The battlefield
------------------------------------------------------------------------
function HA.Index(col, row) return (row - 1) * 8 + col end
function HA.ColRow(idx) return (idx - 1) % 8 + 1, floor((idx - 1) / 8) + 1 end

HA.LAKE = {}
for _, cr in ipairs({ { 3, 4 }, { 3, 5 }, { 6, 4 }, { 6, 5 } }) do HA.LAKE[HA.Index(cr[1], cr[2])] = true end

-- The 24 setup squares of each side, in a fixed order (rows up, columns across).
HA.ZONE = { w = {}, b = {} }
for row = 1, 8 do
    for col = 1, 8 do
        if row <= 3 then table.insert(HA.ZONE.w, HA.Index(col, row)) end
        if row >= 6 then table.insert(HA.ZONE.b, HA.Index(col, row)) end
    end
end
HA.IN_ZONE = { w = {}, b = {} }
for side, list in pairs(HA.ZONE) do for k, idx in ipairs(list) do HA.IN_ZONE[side][idx] = k end end

function HA.Other(side) return side == "w" and "b" or "w" end
function HA.Movable(rank) return rank ~= nil and rank ~= "B" and rank ~= "N" end

function HA.SquareName(idx)
    local col, row = HA.ColRow(idx)
    return string.sub("abcdefgh", col, col) .. row
end

------------------------------------------------------------------------
-- Setups: 24 characters, one per setup square ("." for empty)
------------------------------------------------------------------------
function HA.ValidLayout(str)
    if type(str) ~= "string" or #str ~= 24 then return false end
    local n = {}
    for i = 1, 24 do
        local ch = string.sub(str, i, i)
        if ch ~= "." then
            if not HA.COUNT[ch] then return false end
            n[ch] = (n[ch] or 0) + 1
        end
    end
    for k, want in pairs(HA.COUNT) do if n[k] ~= want then return false end end
    return true
end

function HA.Occupancy(str)
    return (string.gsub(str, "[^%.]", "1"):gsub("%.", "0"))
end

local function Shuffled(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- A random setup. smart: the Banner in the back row with Bombs around it.
function HA.RandomLayout(side, smart)
    local slots = {}
    for i = 1, 24 do slots[i] = "." end
    local pool = {}
    for _, k in ipairs(HA.ORDER) do for _ = 1, HA.COUNT[k] do pool[#pool + 1] = k end end
    local backRow = side == "w" and 1 or 8
    local frontRow = side == "w" and 3 or 6
    local function Slot(col, row) return HA.IN_ZONE[side][HA.Index(col, row)] end
    if smart then
        local col = math.random(1, 8)
        slots[Slot(col, backRow)] = "N"
        local guards = {}
        if col > 1 then guards[#guards + 1] = Slot(col - 1, backRow) end
        if col < 8 then guards[#guards + 1] = Slot(col + 1, backRow) end
        guards[#guards + 1] = Slot(col, side == "w" and 2 or 7)
        local bombs = 0
        for _, g in ipairs(Shuffled(guards)) do
            if bombs < 3 then slots[g] = "B"; bombs = bombs + 1 end
        end
        -- remove what was placed from the pool
        local left = {}
        local placedB = bombs
        local placedN = false
        for _, k in ipairs(pool) do
            if k == "N" and not placedN then placedN = true
            elseif k == "B" and placedB > 0 then placedB = placedB - 1
            else left[#left + 1] = k end
        end
        pool = left
    end
    -- scouts and footmen like the front, the rest anywhere
    local free = {}
    for i = 1, 24 do if slots[i] == "." then free[#free + 1] = i end end
    Shuffled(free)
    Shuffled(pool)
    local used = 0
    for i = 1, #pool do
        used = used + 1
        slots[free[used]] = pool[i]
    end
    local out = table.concat(slots)
    if not HA.ValidLayout(out) then return HA.RandomLayout(side, false) end
    -- keep the front row from being all bombs: fine as is (random); return
    local _ = frontRow
    return out
end

function HA.Seal(layout, salt)
    return ns.Hash.SHA256("FPL-HA1:" .. layout .. ":" .. salt)
end

-- Outcome of a fight: "a" attacker wins, "d" defender wins, "both", "banner", "defuse".
function HA.Fight(a, d)
    if d == "N" then return "banner" end
    if d == "B" then return a == "S" and "defuse" or "d" end
    if a == "R" and d == "W" then return "a" end
    local va, vd = HA.RANK[a] or 0, HA.RANK[d] or 0
    if va > vd then return "a" end
    if va < vd then return "d" end
    return "both"
end

-- Legal moves for one side. cells[idx] = { side = }, rankAt(idx) gives that side's rank.
function HA.LegalMoves(cells, side, rankAt)
    local out = {}
    for idx = 1, 64 do
        local u = cells[idx]
        if u and u.side == side then
            local rank = rankAt(idx)
            if HA.Movable(rank) then
                local col, row = HA.ColRow(idx)
                for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                    local c, r = col + d[1], row + d[2]
                    while c >= 1 and c <= 8 and r >= 1 and r <= 8 do
                        local t = HA.Index(c, r)
                        if HA.LAKE[t] then break end
                        local v = cells[t]
                        if v and v.side == side then break end
                        out[#out + 1] = { from = idx, to = t, attack = v ~= nil }
                        if v or rank ~= "X" then break end
                        c, r = c + d[1], r + d[2]
                    end
                end
            end
        end
    end
    return out
end

-- Whether a move could be legal for some unit (the mover's rank unknown): a straight line
-- through empty squares. Returns ok, distance.
function HA.PathOK(cells, side, from, to)
    if type(from) ~= "number" or type(to) ~= "number" or from < 1 or from > 64 or to < 1 or to > 64 then return false end
    if from == to or HA.LAKE[to] then return false end
    local u = cells[from]
    if not u or u.side ~= side then return false end
    local v = cells[to]
    if v and v.side == side then return false end
    local c1, r1 = HA.ColRow(from)
    local c2, r2 = HA.ColRow(to)
    if c1 ~= c2 and r1 ~= r2 then return false end
    local dc, dr = (c2 > c1 and 1) or (c2 < c1 and -1) or 0, (r2 > r1 and 1) or (r2 < r1 and -1) or 0
    local dist = abs(c2 - c1) + abs(r2 - r1)
    local c, r = c1 + dc, r1 + dr
    while c ~= c2 or r ~= r2 do
        local t = HA.Index(c, r)
        if cells[t] or HA.LAKE[t] then return false end
        c, r = c + dc, r + dr
    end
    return true, dist
end

-- Replays a whole game against both real setups. moves: list of { side, from, to, ar, dr }.
-- Checks every claim made by `side`. Returns ok, why, finalTruth ({ [idx] = { side, rank } }).
function HA.Replay(layouts, moves, side)
    local truth = {}
    for s, str in pairs(layouts) do
        for k, idx in ipairs(HA.ZONE[s]) do
            local ch = string.sub(str, k, k)
            if ch ~= "." then truth[idx] = { side = s, rank = ch } end
        end
    end
    for i, m in ipairs(moves) do
        local u = truth[m.from]
        if not u or u.side ~= m.side then return false, "move " .. i .. " did not match their setup" end
        if m.side == side and not HA.Movable(u.rank) then return false, "they moved a " .. HA.NAME[u.rank] end
        local c1, r1 = HA.ColRow(m.from)
        local c2, r2 = HA.ColRow(m.to)
        if m.side == side and abs(c2 - c1) + abs(r2 - r1) > 1 and u.rank ~= "X" then
            return false, "their " .. HA.NAME[u.rank] .. " moved like a Scout"
        end
        local d = truth[m.to]
        if d then
            if m.side == side and m.ar ~= u.rank then return false, "they named the wrong rank when attacking (move " .. i .. ")" end
            if d.side == side and m.dr ~= d.rank then return false, "they named the wrong rank when defending (move " .. i .. ")" end
            local res = HA.Fight(u.rank, d.rank)
            if res == "a" or res == "defuse" or res == "banner" then truth[m.to] = u; truth[m.from] = nil
            elseif res == "d" then truth[m.from] = nil
            else truth[m.from] = nil; truth[m.to] = nil end
        else
            truth[m.to] = u
            truth[m.from] = nil
        end
    end
    return true, nil, truth
end

------------------------------------------------------------------------
-- Session
------------------------------------------------------------------------
HA.current = nil
local unacked = {}

local function Fire(event, ...) ns.Fire(event, ...) end

local function NewSession(o)
    local s = {
        id = o.id or ns.NewId(), mode = o.mode, opp = o.opp, oppName = o.oppName or o.opp,
        iFirst = o.iFirst, level = o.level,
        phase = "setup", -- setup -> play -> over
        moves = {}, cells = {}, turn = "w",
        missed = 0, seq = 0, seen = {}, defused = 0,
        setupDeadline = ns.Now() + HA.SETUP_TIME,
    }
    s.mySide = s.iFirst and "w" or "b"
    s.theirSide = HA.Other(s.mySide)
    s.layout = HA.RandomLayout(s.mySide, true)
    s.white = s.iFirst and ns.me or s.opp
    s.black = s.iFirst and s.opp or ns.me
    return s
end

function HA.Busy()
    local s = HA.current
    return s ~= nil and s.phase ~= "over" and s.mode == "online"
end

function HA.Active()
    local s = HA.current
    return s ~= nil and s.phase ~= "over"
end

function HA.MoveCount(s) return #s.moves end

function HA.MyTurn()
    local s = HA.current
    return s ~= nil and s.phase == "play" and s.mode ~= "spectate" and s.turn == s.mySide and not s.awaiting
end

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

local function Accept(sender, parts)
    local gid, seq = parts[2], tonumber(parts[3])
    local s = HA.current
    if not (s and s.id == gid and s.mode == "online" and s.opp == sender and seq) then return nil end
    C.Whisper(sender, "UK", gid, seq)
    if s.seen[seq] then return nil end
    s.seen[seq] = true
    return s
end

C.handlers.UK = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local key = (parts[2] or "") .. ":" .. (parts[3] or "")
    local u = unacked[key]
    if u and u.target == sender then unacked[key] = nil end
end

local function Statement(s, res)
    if s.mode ~= "online" then return end
    ns.Ledger.StateOwn({ id = s.id, white = s.white, black = s.black, mode = "online", kind = "a" }, res)
end

local function Begin(s)
    HA.current = s
    Fire("HA_STARTED", s)
    Fire("HA_CHANGED", s)
    if s.mode == "online" then ns.Game.Announce(true) end
end

function HA.StartOnline(id, opp, iFirst)
    local s = NewSession({ id = id, mode = "online", opp = opp, iFirst = iFirst })
    Begin(s)
    return s
end

function HA.StartAI(level)
    level = level or 2
    local s = NewSession({ mode = "ai", opp = "Computer", iFirst = math.random(1, 2) == 1, level = level })
    s.oppName = "Computer (" .. HA.LEVELS[level] .. ")"
    s.white = s.iFirst and ns.me or s.oppName
    s.black = s.iFirst and s.oppName or ns.me
    s.aiLayout = HA.RandomLayout(s.theirSide, level >= 2)
    Begin(s)
    return s
end

------------------------------------------------------------------------
-- Setting up
------------------------------------------------------------------------
-- The rank on one of our setup squares (during setup).
function HA.SetupRank(idx)
    local s = HA.current
    if not s then return nil end
    local k = HA.IN_ZONE[s.mySide][idx]
    if not k then return nil end
    local ch = string.sub(s.layout, k, k)
    return ch ~= "." and ch or nil
end

-- Moves or swaps the contents of two of our setup squares.
function HA.Swap(a, b)
    local s = HA.current
    if not s or s.phase ~= "setup" or s.ready then return false end
    local ka, kb = HA.IN_ZONE[s.mySide][a], HA.IN_ZONE[s.mySide][b]
    if not ka or not kb or ka == kb then return false end
    local t = {}
    for i = 1, 24 do t[i] = string.sub(s.layout, i, i) end
    t[ka], t[kb] = t[kb], t[ka]
    s.layout = table.concat(t)
    Fire("HA_CHANGED", s)
    return true
end

function HA.Shuffle()
    local s = HA.current
    if not s or s.phase ~= "setup" or s.ready then return end
    s.layout = HA.RandomLayout(s.mySide, true)
    Fire("HA_CHANGED", s)
end

local function PlaceArmies(s)
    s.cells = {}
    for k, idx in ipairs(HA.ZONE[s.mySide]) do
        local ch = string.sub(s.layout, k, k)
        if ch ~= "." then s.cells[idx] = { side = s.mySide, rank = ch } end
    end
    local theirs = s.mode == "ai" and HA.Occupancy(s.aiLayout) or s.theirOcc
    for k, idx in ipairs(HA.ZONE[s.theirSide]) do
        if string.sub(theirs, k, k) == "1" then s.cells[idx] = { side = s.theirSide } end
    end
    if s.mode == "ai" then
        s.aiRank = {}
        for k, idx in ipairs(HA.ZONE[s.theirSide]) do
            local ch = string.sub(s.aiLayout, k, k)
            if ch ~= "." then s.aiRank[idx] = ch end
        end
    end
end

local function StartPlay(s)
    PlaceArmies(s)
    s.phase = "play"
    s.turn = "w"
    s.turnStart = ns.Now()
    s.missed = 0
    Statement(s, nil)
    Fire("HA_PLAY", s)
    Fire("HA_CHANGED", s)
    if s.mode == "ai" and s.turn ~= s.mySide then HA.AITurnSoon(s) end
end

function HA.Ready()
    local s = HA.current
    if not s or s.phase ~= "setup" or s.ready then return end
    s.ready = true
    s.salt = ns.Hash.Salt()
    s.seal = HA.Seal(s.layout, s.salt)
    if s.mode == "ai" then
        StartPlay(s)
        return
    end
    Send(s, "UC", s.seal, HA.Occupancy(s.layout))
    if s.theirSeal then StartPlay(s) end
    Fire("HA_CHANGED", s)
end

C.handlers.UC = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "setup" then return end
    local seal, occ = parts[4], parts[5]
    if type(seal) ~= "string" or not string.match(seal, "^%x+$") or #seal ~= 64 then return end
    if type(occ) ~= "string" or not string.match(occ, "^[01]+$") or #occ ~= 24 then return end
    local n = 0
    for _ in string.gmatch(occ, "1") do n = n + 1 end
    if n ~= HA.UNITS then return end
    s.theirSeal, s.theirOcc = seal, occ
    if s.ready then StartPlay(s) end
    Fire("HA_CHANGED", s)
end

------------------------------------------------------------------------
-- Moving and fighting
------------------------------------------------------------------------
local Finish -- forward

-- Our legal moves (we know our own ranks).
function HA.MyMoves()
    local s = HA.current
    if not s or s.phase ~= "play" then return {} end
    return HA.LegalMoves(s.cells, s.mySide, function(idx) return s.cells[idx].rank end)
end

local function EndTurn(s)
    s.awaiting = nil
    s.turn = HA.Other(s.turn)
    s.turnStart = ns.Now()
    if #s.moves >= HA.MAX_MOVES then
        Finish(s, "draw", "limit")
        return
    end
    if s.mode ~= "spectate" and s.turn == s.mySide and #HA.MyMoves() == 0 then
        if s.mode == "online" then Send(s, "UQ", "stuck") end
        Finish(s, "loss", "stuck")
        return
    end
    if s.mode == "ai" and s.turn ~= s.mySide then
        local aiMoves = HA.LegalMoves(s.cells, s.theirSide, function(idx) return s.aiRank[idx] end)
        if #aiMoves == 0 then
            Finish(s, "win", "stuck")
            return
        end
    end
    Fire("HA_CHANGED", s)
    if s.mode == "ai" and s.turn ~= s.mySide then HA.AITurnSoon(s) end
end

local function Code(v) return v or "-" end

-- A plain move (no fight).
local function ApplyMove(s, side, from, to)
    local u = s.cells[from]
    s.cells[to], s.cells[from] = u, nil
    u.moved = true
    local _, dist = HA.PathOK({ [from] = u }, side, from, to)
    if dist and dist > 1 then u.rank = u.rank or "X"; u.revealed = true end -- only Scouts run
    if s.aiRank and s.aiRank[from] then s.aiRank[to], s.aiRank[from] = s.aiRank[from], nil end
    local m = { side = side, from = from, to = to }
    s.moves[#s.moves + 1] = m
    s.last = m
    Fire("HA_MOVE", s, m)
    if s.mode == "online" then Relay(s, "UW", s.id, #s.moves, from, to, "-", "-") end
    EndTurn(s)
end

-- A fight: both ranks are known now.
local function Resolve(s, side, from, to, ar, dr)
    local A, D = s.cells[from], s.cells[to]
    A.rank, D.rank = ar, dr
    A.revealed, D.revealed, A.moved = true, true, true
    local res = HA.Fight(ar, dr)
    if res == "a" or res == "defuse" or res == "banner" then
        s.cells[to], s.cells[from] = A, nil
    elseif res == "d" then
        s.cells[from] = nil
    else
        s.cells[from], s.cells[to] = nil, nil
    end
    if s.aiRank then
        local aiA, aiD = s.aiRank[from], s.aiRank[to]
        if res == "a" or res == "defuse" or res == "banner" then s.aiRank[to], s.aiRank[from] = aiA, nil
        elseif res == "d" then s.aiRank[from] = nil
        else s.aiRank[from], s.aiRank[to] = nil, nil end
        if aiD and (res == "a" or res == "defuse" or res == "banner") and side == s.mySide then s.aiRank[to] = nil end
    end
    local m = { side = side, from = from, to = to, ar = ar, dr = dr, res = res }
    s.moves[#s.moves + 1] = m
    s.last = m
    if side == s.mySide then
        if res == "defuse" then s.defused = s.defused + 1 end
        if ar == "R" and dr == "W" then s.kingslayer = true end
    end
    Fire("HA_FIGHT", s, m)
    if s.mode == "online" then Relay(s, "UW", s.id, #s.moves, from, to, ar, dr) end
    if res == "banner" then
        if side == s.mySide then s.bannerBy = ar end
        Finish(s, side == s.mySide and "win" or "loss", "banner")
        return
    end
    EndTurn(s)
end

-- Our move.
function HA.Move(from, to, auto)
    local s = HA.current
    if not HA.MyTurn() then return false end
    local legal = false
    for _, m in ipairs(HA.MyMoves()) do
        if m.from == from and m.to == to then legal = true break end
    end
    if not legal then return false end
    if not auto then s.missed = 0 end
    local target = s.cells[to]
    local ar = s.cells[from].rank
    if target then
        if s.mode == "ai" then
            Resolve(s, s.mySide, from, to, ar, s.aiRank[to])
        else
            s.awaiting = { from = from, to = to, n = #s.moves + 1 }
            Send(s, "UM", #s.moves + 1, from, to, ar)
            Fire("HA_CHANGED", s)
        end
    else
        if s.mode == "online" then Send(s, "UM", #s.moves + 1, from, to, "-") end
        ApplyMove(s, s.mySide, from, to)
    end
    return true
end

-- Their move.
C.handlers.UM = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "play" or s.turn ~= s.theirSide or s.awaiting then return end
    local n, from, to, ar = tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6]), parts[7]
    if n ~= #s.moves + 1 or not HA.PathOK(s.cells, s.theirSide, from, to) then return end
    local target = s.cells[to]
    if target then
        if not HA.Movable(ar) then return end
        local dr = target.rank
        Send(s, "UR", n, dr)
        Resolve(s, s.theirSide, from, to, ar, dr)
    else
        ApplyMove(s, s.theirSide, from, to)
    end
end

-- Their answer to our attack: the defender's rank.
C.handlers.UR = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "play" or not s.awaiting then return end
    local n, dr = tonumber(parts[4]), parts[5]
    if n ~= s.awaiting.n or not HA.COUNT[dr or ""] then return end
    local a = s.awaiting
    Resolve(s, s.mySide, a.from, a.to, s.cells[a.from].rank, dr)
end

------------------------------------------------------------------------
-- The computer general (it only knows what a player would: our revealed ranks)
------------------------------------------------------------------------
local VALUE = { W = 10, C = 8, K = 6, F = 4, S = 5, X = 2, R = 5, B = 3, N = 100 }

function HA.AIMove(s)
    local side = s.theirSide
    local moves = HA.LegalMoves(s.cells, side, function(idx) return s.aiRank[idx] end)
    if #moves == 0 then return nil end
    local level = s.level or 2
    local forward = side == "w" and 1 or -1
    local best, bestScore = nil, -math.huge
    for _, m in ipairs(moves) do
        local mine = s.aiRank[m.from]
        local score = math.random() * (level <= 1 and 30 or 6)
        local target = s.cells[m.to]
        if target then
            local known = target.revealed and target.rank
            if known then
                local res = HA.Fight(mine, known)
                if res == "banner" then score = score + 1000
                elseif res == "a" or res == "defuse" then score = score + 60 + VALUE[known] * 5
                elseif res == "both" then score = score + (VALUE[known] - VALUE[mine]) * 5
                else score = score - 80 - VALUE[mine] * 5 end
            else
                -- an unknown unit: probe with cheap units, keep the big ones back
                if level >= 2 then
                    if mine == "X" then score = score + 18
                    elseif mine == "W" or mine == "C" then score = score - 35
                    else score = score + 4 - VALUE[mine] end
                    -- a Sapper is sent at units that never moved (they may be Bombs or the Banner)
                    if level >= 3 and mine == "S" and not target.moved then score = score + 25 end
                    if level >= 3 and not target.moved and mine ~= "S" and mine ~= "X" then score = score - 15 end
                else
                    score = score + 10
                end
            end
        else
            local _, r1 = HA.ColRow(m.from)
            local _, r2 = HA.ColRow(m.to)
            score = score + (r2 - r1) * forward * (mine == "X" and 2 or 3)
            if mine == "W" then score = score - 6 end
            if level >= 3 then
                -- do not step next to a revealed enemy that would beat us
                local c2, rr = HA.ColRow(m.to)
                for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                    local c, r = c2 + d[1], rr + d[2]
                    if c >= 1 and c <= 8 and r >= 1 and r <= 8 then
                        local e = s.cells[HA.Index(c, r)]
                        if e and e.side ~= side and e.revealed and HA.Movable(e.rank) and HA.Fight(e.rank, mine) == "a" then
                            score = score - 20 - VALUE[mine] * 2
                        end
                    end
                end
            end
        end
        if score > bestScore then best, bestScore = m, score end
    end
    return best
end

function HA.AITurnSoon(s)
    ns.After(0.8 + math.random() * 0.4, function()
        if HA.current ~= s or s.phase ~= "play" or s.turn == s.mySide then return end
        local m = HA.AIMove(s)
        if not m then return end
        local target = s.cells[m.to]
        if target then
            Resolve(s, s.theirSide, m.from, m.to, s.aiRank[m.from], target.rank)
        else
            ApplyMove(s, s.theirSide, m.from, m.to)
        end
    end)
end

------------------------------------------------------------------------
-- Ending
------------------------------------------------------------------------
local ProcessReveal -- forward

local function Result(s, outcome)
    local iWhite = s.white == ns.me
    if outcome == "win" then return iWhite and "1-0" or "0-1" end
    if outcome == "loss" then return iWhite and "0-1" or "1-0" end
    return "1/2"
end

-- Shows the whole enemy army once it is known.
local function Expose(s, truth)
    for idx, u in pairs(s.cells) do
        local t = truth[idx]
        if u.side == s.theirSide and t then u.rank = t.rank; u.exposed = true end
    end
end

-- outcome: "win" | "loss" | "draw" | "abort"; reason: banner, stuck, limit, resign, time, abandoned, abort
Finish = function(s, outcome, reason)
    if s.phase == "over" then return end
    local wasSetup = s.phase == "setup"
    s.phase = "over"
    s.outcome, s.reason = outcome, reason
    s.awaiting = nil
    if s.mode == "online" then
        if s.ready and outcome ~= "abort" then Send(s, "UV", s.layout, s.salt or "") end
        if outcome == "win" or (outcome == "loss" and (reason == "resign" or reason == "time" or reason == "stuck")) then
            s.stated = true
            Statement(s, Result(s, outcome))
        elseif outcome ~= "abort" then
            s.verifyDeadline = ns.Now() + 90
        end
        local winner = (outcome == "win" and ns.me) or (outcome == "loss" and s.opp) or ""
        Relay(s, "UE", s.id, winner, reason)
    end
    if s.mode == "ai" then
        local truth = {}
        for idx, r in pairs(s.aiRank or {}) do truth[idx] = { side = s.theirSide, rank = r } end
        Expose(s, truth)
    end
    if outcome ~= "abort" and s.mode ~= "spectate" and not wasSetup then
        P.RecordGame({
            mode = "ha", outcome = outcome, vsAI = s.mode == "ai", aiLevel = s.level or 0, opp = s.opp,
            kingslayer = s.kingslayer, defused = s.defused, bannerBy = s.bannerBy,
        })
    end
    Fire("HA_OVER", s)
    Fire("HA_CHANGED", s)
    if s.mode == "online" then ns.Game.Announce(true) end
    if s.earlyReveal then
        local r = s.earlyReveal
        s.earlyReveal = nil
        ProcessReveal(s, r[1], r[2])
    end
end
HA.Finish = function(outcome, reason) if HA.current then Finish(HA.current, outcome, reason) end end

-- Checks the opponent's revealed setup: seal, what they showed us, and every move and fight.
function HA.Verify(s, layoutStr, salt)
    if not HA.ValidLayout(layoutStr) then return false, "their setup was not a legal army" end
    if type(salt) ~= "string" or HA.Seal(layoutStr, salt) ~= s.theirSeal then
        return false, "their setup does not match the seal they sent before the battle"
    end
    if HA.Occupancy(layoutStr) ~= s.theirOcc then return false, "their units did not stand where they said" end
    local layouts = { [s.mySide] = s.layout, [s.theirSide] = layoutStr }
    return HA.Replay(layouts, s.moves, s.theirSide)
end

ProcessReveal = function(s, layoutStr, salt)
    if s.verified ~= nil then return end
    local ok, why, truth = HA.Verify(s, layoutStr, salt)
    s.verified = ok
    if ok then
        Expose(s, truth)
        if not s.stated then
            s.stated = true
            Statement(s, Result(s, s.outcome))
        end
    else
        s.cheat = why
        ns.Print("|cffff4030Fair-play check failed: " .. why .. ". This battle is disputed and will not count.|r")
        if not s.stated then
            s.outcome = "disputed"
            s.stated = true
            Statement(s, Result(s, "win"))
        end
    end
    s.verifyDeadline = nil
    Fire("HA_CHANGED", s)
end

C.handlers.UV = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s then return end
    if s.phase ~= "over" then
        s.earlyReveal = { parts[4], parts[5] }
        return
    end
    ProcessReveal(s, parts[4], parts[5])
end

function HA.Resign()
    local s = HA.current
    if not s or s.phase == "over" then return end
    if s.mode == "spectate" then
        HA.StopWatching()
        return
    end
    if s.mode == "online" then
        if s.phase == "setup" then
            Send(s, "UQ", "abort")
            Finish(s, "abort", "abort")
            return
        end
        Send(s, "UQ", "resign")
    end
    Finish(s, "loss", "resign")
end

C.handlers.UQ = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase == "over" then return end
    if parts[4] == "abort" and s.phase == "setup" then
        Finish(s, "abort", "abort")
    else
        local why = parts[4]
        Finish(s, "win", (why == "time" or why == "stuck") and why or "resign")
    end
end

------------------------------------------------------------------------
-- Spectating: positions are public, ranks only once revealed in a fight.
--   UX;id;host;guest;white;occW;occB   UY;id;moves   UW;id;n;from;to;ar;dr   UE;id;winner;reason
------------------------------------------------------------------------
local function MoveText(m) return m.from .. "." .. m.to .. "." .. Code(m.ar) .. "." .. Code(m.dr) end

function HA.HandleWatchRequest(sender)
    local s = HA.current
    if not (s and s.mode == "online" and s.phase == "play" and ns.db.settings.allowSpectators) then return false end
    s.spectators = s.spectators or {}
    local n = 0
    for _ in pairs(s.spectators) do n = n + 1 end
    if not s.spectators[sender] and n >= 5 then return false end
    s.spectators[sender] = true
    local occ = { [s.mySide] = HA.Occupancy(s.layout), [s.theirSide] = s.theirOcc }
    C.Whisper(sender, "UX", s.id, ns.me, s.opp, s.white, occ.w, occ.b)
    local chunk = {}
    for i, m in ipairs(s.moves) do
        chunk[#chunk + 1] = MoveText(m)
        if #chunk == 16 or i == #s.moves then
            C.Whisper(sender, "UY", s.id, table.concat(chunk, ","))
            chunk = {}
        end
    end
    return true
end

function HA.DropSpectator(sender, id)
    local s = HA.current
    if s and s.id == id and s.spectators then s.spectators[sender] = nil end
end

-- Spectator: apply one move (ranks given for fights only).
local function SpectatorMove(s, from, to, ar, dr)
    local u = s.cells[from]
    if not u then return end
    local side = u.side
    if ar and dr and s.cells[to] then
        local m = { side = side, from = from, to = to, ar = ar, dr = dr }
        local A, D = u, s.cells[to]
        A.rank, D.rank, A.revealed, D.revealed, A.moved = ar, dr, true, true, true
        local res = HA.Fight(ar, dr)
        m.res = res
        if res == "a" or res == "defuse" or res == "banner" then s.cells[to], s.cells[from] = A, nil
        elseif res == "d" then s.cells[from] = nil
        else s.cells[from], s.cells[to] = nil, nil end
        s.moves[#s.moves + 1] = m
        s.last = m
        return m, true
    end
    s.cells[to], s.cells[from] = u, nil
    u.moved = true
    local m = { side = side, from = from, to = to }
    s.moves[#s.moves + 1] = m
    s.last = m
    return m, false
end

C.handlers.UX = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    if not (ns.Game.watchPending and ns.SameName(ns.Game.watchPending, sender)) then return end
    local occW, occB = parts[6], parts[7]
    if not (occW and occB and #occW == 24 and #occB == 24) then return end
    ns.Game.watchPending = nil
    local s = NewSession({ id = parts[2], mode = "spectate", opp = parts[4] })
    s.source = sender
    s.host, s.guest = parts[3], parts[4]
    s.white = parts[5]
    s.mySide = ns.SameName(s.white, s.host) and "w" or "b"
    s.theirSide = HA.Other(s.mySide)
    s.phase = "play"
    s.cells = {}
    for side, occ in pairs({ w = occW, b = occB }) do
        for k, idx in ipairs(HA.ZONE[side]) do
            if string.sub(occ, k, k) == "1" then s.cells[idx] = { side = side } end
        end
    end
    s.turnStart = ns.Now()
    HA.current = s
    Fire("HA_STARTED", s)
    Fire("HA_CHANGED", s)
end

C.handlers.UY = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = HA.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2]) then return end
    for e in string.gmatch(parts[3] or "", "[^,]+") do
        local from, to, ar, dr = string.match(e, "^(%d+)%.(%d+)%.(%a+)%.(%a+)$")
        if not from then from, to, ar, dr = string.match(e, "^(%d+)%.(%d+)%.(%-)%.(%-)$") end
        if from then
            SpectatorMove(s, tonumber(from), tonumber(to), ar ~= "-" and ar or nil, dr ~= "-" and dr or nil)
        end
    end
    s.turn = (#s.moves % 2 == 0) and "w" or "b"
    Fire("HA_CHANGED", s)
end

C.handlers.UW = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = HA.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2] and s.phase == "play") then return end
    local n, from, to = tonumber(parts[3]), tonumber(parts[4]), tonumber(parts[5])
    if n ~= #s.moves + 1 or not from or not to then return end
    local ar, dr = parts[6], parts[7]
    local m, fight = SpectatorMove(s, from, to, (ar and ar ~= "-") and ar or nil, (dr and dr ~= "-") and dr or nil)
    if not m then return end
    s.turn = (#s.moves % 2 == 0) and "w" or "b"
    s.turnStart = ns.Now()
    Fire(fight and "HA_FIGHT" or "HA_MOVE", s, m)
    Fire("HA_CHANGED", s)
end

C.handlers.UE = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = HA.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2]) then return end
    if s.phase == "over" then return end
    s.phase = "over"
    s.winner = parts[3] ~= "" and parts[3] or nil
    s.reason = parts[4]
    P.RecordGame({ mode = "spectate", outcome = "none" })
    Fire("HA_OVER", s)
    Fire("HA_CHANGED", s)
end

function HA.StopWatching()
    local s = HA.current
    if s and s.mode == "spectate" and s.phase ~= "over" then
        C.Whisper(s.source, "SX", s.id)
        s.phase = "over"
        Fire("HA_CHANGED", s)
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
    local s = HA.current
    if not s or s.mode == "spectate" then return end
    if s.phase == "setup" then
        if not s.ready and now >= s.setupDeadline then
            HA.Ready()
        elseif s.ready and s.mode == "online" and not s.theirSeal and now >= s.setupDeadline + HA.SETUP_TIME then
            Send(s, "UQ", "abort")
            Finish(s, "abort", "abandoned")
        end
    elseif s.phase == "play" then
        local elapsed = now - (s.turnStart or now)
        if s.turn == s.mySide and not s.awaiting and elapsed >= HA.TURN_TIME then
            s.missed = s.missed + 1
            if s.missed >= HA.MAX_MISSED then
                if s.mode == "online" then Send(s, "UQ", "time") end
                Finish(s, "loss", "time")
                return
            end
            local moves = HA.MyMoves()
            if #moves > 0 then
                ns.Print("time's up - a random move was made for you (" .. s.missed .. "/" .. HA.MAX_MISSED .. " missed turns).")
                local m = moves[math.random(1, #moves)]
                HA.Move(m.from, m.to, true)
            end
        elseif s.mode == "online" and s.turn ~= s.mySide and elapsed >= HA.TURN_TIME * HA.MAX_MISSED + HA.GRACE then
            Finish(s, "win", "abandoned")
        end
    elseif s.phase == "over" and s.verifyDeadline and now >= s.verifyDeadline then
        s.verifyDeadline = nil
        if not s.stated then
            s.outcome = "disputed"
            s.cheat = "they never revealed their setup"
            s.stated = true
            Statement(s, Result(s, "win"))
            ns.Print("|cffff4030" .. ns.ShortName(s.opp) .. " never revealed their setup - this battle is disputed and will not count.|r")
        end
        Fire("HA_CHANGED", s)
    end
end)

function HA.TimeLeft()
    local s = HA.current
    if not s then return 0 end
    if s.phase == "setup" then return max(0, s.setupDeadline - ns.Now()) end
    if s.phase == "play" then return max(0, HA.TURN_TIME - (ns.Now() - (s.turnStart or ns.Now()))) end
    return 0
end
