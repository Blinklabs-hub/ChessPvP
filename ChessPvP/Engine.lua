-- ChessPvP: chess rules engine (10x12 mailbox board, full legal move generation).
local _, ns = ...

local E = {}
ns.Engine = E

local floor, abs = math.floor, math.abs

-- Piece codes: white 1..6 (P N B R Q K), black negative, 0 empty, 7 off-board.
local OFF = 7
E.OFF = OFF

local N_OFF = { -21, -19, -12, -8, 8, 12, 19, 21 }
local K_OFF = { -11, -10, -9, -1, 1, 9, 10, 11 }
local B_DIR = { -11, -9, 9, 11 }
local R_DIR = { -10, -1, 1, 10 }

local START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
E.START_FEN = START_FEN

local PIECE_FROM_CHAR = { P = 1, N = 2, B = 3, R = 4, Q = 5, K = 6, p = -1, n = -2, b = -3, r = -4, q = -5, k = -6 }
local CHAR_FROM_PIECE = { [0] = ".", "P", "N", "B", "R", "Q", "K", [-1] = "p", [-2] = "n", [-3] = "b", [-4] = "r", [-5] = "q", [-6] = "k" }
local PROMO_CHAR = { [2] = "n", [3] = "b", [4] = "r", [5] = "q" }
local PROMO_FROM_CHAR = { n = 2, b = 3, r = 4, q = 5 }
local SAN_LETTER = { "", "N", "B", "R", "Q", "K" }
local FILES = "abcdefgh"

-- Square helpers. file/rank are 0-based; a1 = 21, h8 = 98.
local function Sq(file, rank) return 21 + file + rank * 10 end
local function FileOf(sq) return (sq % 10) - 1 end
local function RankOf(sq) return floor(sq / 10) - 2 end
E.Sq, E.FileOf, E.RankOf = Sq, FileOf, RankOf

local function SqName(sq)
    local f = FileOf(sq) + 1
    return string.sub(FILES, f, f) .. (RankOf(sq) + 1)
end
E.SqName = SqName

local function SqFromName(s)
    local f = string.find(FILES, string.sub(s, 1, 1), 1, true)
    local r = tonumber(string.sub(s, 2, 2))
    if not f or not r or r < 1 or r > 8 then return nil end
    return Sq(f - 1, r - 1)
end

-- Moves are packed into one number:
--   from + to*128 + promo*16384 + flag*131072
-- flag: 0 normal, 1 en passant, 2 castle kingside, 3 castle queenside, 4 double pawn push
local function MFrom(m) return m % 128 end
local function MTo(m) return floor(m / 128) % 128 end
local function MPromo(m) return floor(m / 16384) % 8 end
local function MFlag(m) return floor(m / 131072) end
E.MFrom, E.MTo, E.MPromo, E.MFlag = MFrom, MTo, MPromo, MFlag

------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------
local function Key(pos)
    local b = pos.b
    local t, n = {}, 0
    for sq = 21, 98 do
        local p = b[sq]
        if p ~= OFF then
            n = n + 1
            t[n] = CHAR_FROM_PIECE[p]
        end
    end
    n = n + 1
    t[n] = pos.turn == 1 and "w" or "b"
    n = n + 1
    t[n] = pos.castle
    -- Only count the en passant square when a capture is actually available.
    local ep = pos.ep
    if ep ~= 0 then
        local c = pos.turn
        if b[ep - 9 * c] == c or b[ep - 11 * c] == c then
            n = n + 1
            t[n] = ep
        end
    end
    return table.concat(t)
end

function E.LoadFEN(pos, fen)
    local parts = {}
    for w in string.gmatch(fen, "%S+") do parts[#parts + 1] = w end
    local b = pos.b
    for i = 0, 119 do b[i] = OFF end
    for rank = 0, 7 do
        for file = 0, 7 do b[Sq(file, rank)] = 0 end
    end
    local rank, file = 7, 0
    for ch in string.gmatch(parts[1], ".") do
        if ch == "/" then
            rank = rank - 1
            file = 0
        elseif tonumber(ch) then
            file = file + tonumber(ch)
        else
            local p = PIECE_FROM_CHAR[ch]
            local sq = Sq(file, rank)
            b[sq] = p
            if p == 6 then pos.ks[1] = sq elseif p == -6 then pos.ks[-1] = sq end
            file = file + 1
        end
    end
    pos.turn = (parts[2] == "b") and -1 or 1
    local cas = 0
    local cs = parts[3] or "-"
    if string.find(cs, "K", 1, true) then cas = cas + 1 end
    if string.find(cs, "Q", 1, true) then cas = cas + 2 end
    if string.find(cs, "k", 1, true) then cas = cas + 4 end
    if string.find(cs, "q", 1, true) then cas = cas + 8 end
    pos.castle = cas
    pos.ep = (parts[4] and parts[4] ~= "-") and SqFromName(parts[4]) or 0
    pos.half = tonumber(parts[5] or "") or 0
    pos.full = tonumber(parts[6] or "") or 1
    pos.n = 0
    local key = Key(pos)
    pos.keys = { key }
    pos.keyCount = { [key] = 1 }
end

function E.New(fen)
    local pos = {
        b = {}, turn = 1, castle = 15, ep = 0, half = 0, full = 1,
        ks = { [1] = 25, [-1] = 95 },
        n = 0, hm = {}, hc = {}, hcas = {}, hep = {}, hhalf = {},
        keys = {}, keyCount = {},
    }
    E.LoadFEN(pos, fen or START_FEN)
    return pos
end

-- A copy for searching: same position, no game history.
function E.Clone(src)
    local pos = {
        b = {}, turn = src.turn, castle = src.castle, ep = src.ep, half = src.half, full = src.full,
        ks = { [1] = src.ks[1], [-1] = src.ks[-1] },
        n = 0, hm = {}, hc = {}, hcas = {}, hep = {}, hhalf = {},
        keys = {}, keyCount = {},
    }
    for i = 0, 119 do pos.b[i] = src.b[i] end
    return pos
end

function E.ToFEN(pos)
    local b = pos.b
    local t = {}
    for rank = 7, 0, -1 do
        local empty = 0
        for file = 0, 7 do
            local p = b[Sq(file, rank)]
            if p == 0 then
                empty = empty + 1
            else
                if empty > 0 then t[#t + 1] = empty; empty = 0 end
                t[#t + 1] = CHAR_FROM_PIECE[p]
            end
        end
        if empty > 0 then t[#t + 1] = empty end
        if rank > 0 then t[#t + 1] = "/" end
    end
    local cas = pos.castle
    local cs = (cas % 2 >= 1 and "K" or "") .. (cas % 4 >= 2 and "Q" or "") .. (cas % 8 >= 4 and "k" or "") .. (cas >= 8 and "q" or "")
    if cs == "" then cs = "-" end
    return table.concat(t) .. " " .. (pos.turn == 1 and "w" or "b") .. " " .. cs .. " " ..
        (pos.ep ~= 0 and SqName(pos.ep) or "-") .. " " .. pos.half .. " " .. pos.full
end

------------------------------------------------------------------------
-- Attacks
------------------------------------------------------------------------
local function Attacked(pos, sq, by)
    local b = pos.b
    if by == 1 then
        if b[sq - 9] == 1 or b[sq - 11] == 1 then return true end
    else
        if b[sq + 9] == -1 or b[sq + 11] == -1 then return true end
    end
    local kn, kg = 2 * by, 6 * by
    for i = 1, 8 do
        if b[sq + N_OFF[i]] == kn then return true end
    end
    for i = 1, 8 do
        if b[sq + K_OFF[i]] == kg then return true end
    end
    local bi, ro, qu = 3 * by, 4 * by, 5 * by
    for i = 1, 4 do
        local d = R_DIR[i]
        local t = sq + d
        local p = b[t]
        while p == 0 do
            t = t + d
            p = b[t]
        end
        if p == ro or p == qu then return true end
    end
    for i = 1, 4 do
        local d = B_DIR[i]
        local t = sq + d
        local p = b[t]
        while p == 0 do
            t = t + d
            p = b[t]
        end
        if p == bi or p == qu then return true end
    end
    return false
end
E.Attacked = Attacked

function E.InCheck(pos, color)
    color = color or pos.turn
    return Attacked(pos, pos.ks[color], -color)
end

------------------------------------------------------------------------
-- Move generation (pseudo-legal; legality is checked after making the move)
------------------------------------------------------------------------
function E.GenPseudo(pos, list, capsOnly)
    local b, c = pos.b, pos.turn
    local white = c > 0
    local ep = pos.ep
    local n = 0
    for sq = 21, 98 do
        local p = b[sq]
        if p ~= 0 and p ~= OFF and (p > 0) == white then
            local t = p * c
            if t == 1 then
                local fwd = sq + 10 * c
                local promoting = (white and fwd >= 91) or ((not white) and fwd <= 28)
                if b[fwd] == 0 then
                    if promoting then
                        n = n + 1; list[n] = sq + fwd * 128 + 5 * 16384
                        if not capsOnly then
                            n = n + 1; list[n] = sq + fwd * 128 + 2 * 16384
                            n = n + 1; list[n] = sq + fwd * 128 + 4 * 16384
                            n = n + 1; list[n] = sq + fwd * 128 + 3 * 16384
                        end
                    elseif not capsOnly then
                        n = n + 1; list[n] = sq + fwd * 128
                        local onStart = (white and sq <= 38) or ((not white) and sq >= 81)
                        if onStart and b[fwd + 10 * c] == 0 then
                            n = n + 1; list[n] = sq + (fwd + 10 * c) * 128 + 4 * 131072
                        end
                    end
                end
                for i = 1, 2 do
                    local to = sq + (i == 1 and 9 or 11) * c
                    local q = b[to]
                    if q ~= 0 and q ~= OFF and (q > 0) ~= white then
                        if promoting then
                            n = n + 1; list[n] = sq + to * 128 + 5 * 16384
                            n = n + 1; list[n] = sq + to * 128 + 2 * 16384
                            n = n + 1; list[n] = sq + to * 128 + 4 * 16384
                            n = n + 1; list[n] = sq + to * 128 + 3 * 16384
                        else
                            n = n + 1; list[n] = sq + to * 128
                        end
                    elseif q == 0 and to == ep then
                        n = n + 1; list[n] = sq + to * 128 + 131072
                    end
                end
            elseif t == 2 or t == 6 then
                local offs = (t == 2) and N_OFF or K_OFF
                for i = 1, 8 do
                    local to = sq + offs[i]
                    local q = b[to]
                    if q == 0 then
                        if not capsOnly then n = n + 1; list[n] = sq + to * 128 end
                    elseif q ~= OFF and (q > 0) ~= white then
                        n = n + 1; list[n] = sq + to * 128
                    end
                end
                if t == 6 and not capsOnly then
                    local cas = pos.castle
                    if white and sq == 25 then
                        if cas % 2 >= 1 and b[26] == 0 and b[27] == 0 and b[28] == 4
                            and not Attacked(pos, 25, -1) and not Attacked(pos, 26, -1) and not Attacked(pos, 27, -1) then
                            n = n + 1; list[n] = 25 + 27 * 128 + 2 * 131072
                        end
                        if cas % 4 >= 2 and b[24] == 0 and b[23] == 0 and b[22] == 0 and b[21] == 4
                            and not Attacked(pos, 25, -1) and not Attacked(pos, 24, -1) and not Attacked(pos, 23, -1) then
                            n = n + 1; list[n] = 25 + 23 * 128 + 3 * 131072
                        end
                    elseif (not white) and sq == 95 then
                        if cas % 8 >= 4 and b[96] == 0 and b[97] == 0 and b[98] == -4
                            and not Attacked(pos, 95, 1) and not Attacked(pos, 96, 1) and not Attacked(pos, 97, 1) then
                            n = n + 1; list[n] = 95 + 97 * 128 + 2 * 131072
                        end
                        if cas >= 8 and b[94] == 0 and b[93] == 0 and b[92] == 0 and b[91] == -4
                            and not Attacked(pos, 95, 1) and not Attacked(pos, 94, 1) and not Attacked(pos, 93, 1) then
                            n = n + 1; list[n] = 95 + 93 * 128 + 3 * 131072
                        end
                    end
                end
            else
                if t ~= 4 then
                    for i = 1, 4 do
                        local d = B_DIR[i]
                        local to = sq + d
                        local q = b[to]
                        while q == 0 do
                            if not capsOnly then n = n + 1; list[n] = sq + to * 128 end
                            to = to + d
                            q = b[to]
                        end
                        if q ~= OFF and (q > 0) ~= white then
                            n = n + 1; list[n] = sq + to * 128
                        end
                    end
                end
                if t ~= 3 then
                    for i = 1, 4 do
                        local d = R_DIR[i]
                        local to = sq + d
                        local q = b[to]
                        while q == 0 do
                            if not capsOnly then n = n + 1; list[n] = sq + to * 128 end
                            to = to + d
                            q = b[to]
                        end
                        if q ~= OFF and (q > 0) ~= white then
                            n = n + 1; list[n] = sq + to * 128
                        end
                    end
                end
            end
        end
    end
    return n
end

local function StripCastle(cas, sq)
    if sq == 25 then
        cas = cas - cas % 4
    elseif sq == 28 then
        if cas % 2 >= 1 then cas = cas - 1 end
    elseif sq == 21 then
        if cas % 4 >= 2 then cas = cas - 2 end
    elseif sq == 95 then
        cas = cas % 4
    elseif sq == 98 then
        if cas % 8 >= 4 then cas = cas - 4 end
    elseif sq == 91 then
        if cas >= 8 then cas = cas - 8 end
    end
    return cas
end

function E.Make(pos, m)
    local b, c = pos.b, pos.turn
    local from = m % 128
    local to = floor(m / 128) % 128
    local promo = floor(m / 16384) % 8
    local flag = floor(m / 131072)
    local p = b[from]
    local cap = b[to]
    local n = pos.n + 1
    pos.n = n
    pos.hm[n] = m
    pos.hcas[n] = pos.castle
    pos.hep[n] = pos.ep
    pos.hhalf[n] = pos.half

    b[from] = 0
    if promo ~= 0 then b[to] = promo * c else b[to] = p end
    if flag == 1 then
        local cs = to - 10 * c
        cap = b[cs]
        b[cs] = 0
    elseif flag == 2 then
        b[to - 1] = b[to + 1]
        b[to + 1] = 0
    elseif flag == 3 then
        b[to + 1] = b[to - 2]
        b[to - 2] = 0
    end
    pos.hc[n] = cap

    pos.ep = (flag == 4) and (from + 10 * c) or 0
    local cas = pos.castle
    if cas ~= 0 then
        pos.castle = StripCastle(StripCastle(cas, from), to)
    end
    if p == c or cap ~= 0 then pos.half = 0 else pos.half = pos.half + 1 end
    if p == 6 * c then pos.ks[c] = to end
    if c == -1 then pos.full = pos.full + 1 end
    pos.turn = -c
end

function E.Unmake(pos)
    local n = pos.n
    local m = pos.hm[n]
    local b = pos.b
    local c = -pos.turn -- the side that made the move
    local from = m % 128
    local to = floor(m / 128) % 128
    local promo = floor(m / 16384) % 8
    local flag = floor(m / 131072)
    local p = b[to]
    if promo ~= 0 then p = c end
    b[from] = p
    local cap = pos.hc[n]
    if flag == 1 then
        b[to] = 0
        b[to - 10 * c] = cap
    else
        b[to] = cap
        if flag == 2 then
            b[to + 1] = b[to - 1]
            b[to - 1] = 0
        elseif flag == 3 then
            b[to - 2] = b[to + 1]
            b[to + 1] = 0
        end
    end
    pos.castle = pos.hcas[n]
    pos.ep = pos.hep[n]
    pos.half = pos.hhalf[n]
    if p == 6 * c then pos.ks[c] = from end
    if c == -1 then pos.full = pos.full - 1 end
    pos.turn = c
    pos.n = n - 1
end

-- All fully legal moves for the side to move.
function E.GenLegal(pos)
    local pseudo = {}
    local n = E.GenPseudo(pos, pseudo)
    local c = pos.turn
    local legal, k = {}, 0
    for i = 1, n do
        local m = pseudo[i]
        E.Make(pos, m)
        if not Attacked(pos, pos.ks[c], -c) then
            k = k + 1
            legal[k] = m
        end
        E.Unmake(pos)
    end
    return legal
end

------------------------------------------------------------------------
-- Game-level helpers
------------------------------------------------------------------------
-- Plays a move "for real": also records the position for repetition checks.
function E.Play(pos, m)
    E.Make(pos, m)
    local key = Key(pos)
    pos.keys[#pos.keys + 1] = key
    pos.keyCount[key] = (pos.keyCount[key] or 0) + 1
end

local function Insufficient(pos)
    local b = pos.b
    local knights, light, dark = 0, 0, 0
    for sq = 21, 98 do
        local p = b[sq]
        if p ~= 0 and p ~= OFF then
            local t = abs(p)
            if t == 1 or t == 4 or t == 5 then return false end
            if t == 2 then
                knights = knights + 1
            elseif t == 3 then
                if (FileOf(sq) + RankOf(sq)) % 2 == 0 then dark = dark + 1 else light = light + 1 end
            end
        end
    end
    if knights == 0 and (light == 0 or dark == 0) then return true end
    if knights == 1 and light + dark == 0 then return true end
    return false
end

-- Returns nil while the game continues, otherwise one of:
--   "checkmate", "stalemate", "material", "fifty", "repetition"
-- An optional precomputed legal move list can be passed in.
function E.Status(pos, legal)
    legal = legal or E.GenLegal(pos)
    if #legal == 0 then
        if E.InCheck(pos) then return "checkmate" end
        return "stalemate"
    end
    if Insufficient(pos) then return "material" end
    if pos.half >= 100 then return "fifty" end
    local key = pos.keys[#pos.keys]
    if key and (pos.keyCount[key] or 0) >= 3 then return "repetition" end
    return nil
end

function E.MoveToUCI(m)
    local promo = MPromo(m)
    return SqName(MFrom(m)) .. SqName(MTo(m)) .. (promo ~= 0 and PROMO_CHAR[promo] or "")
end

-- Finds the legal move matching a coordinate string such as "e2e4" or "e7e8q".
function E.FindMove(pos, uci, legal)
    if type(uci) ~= "string" or #uci < 4 or #uci > 5 then return nil end
    local from = SqFromName(string.sub(uci, 1, 2))
    local to = SqFromName(string.sub(uci, 3, 4))
    if not from or not to then return nil end
    local promo = 0
    if #uci == 5 then
        promo = PROMO_FROM_CHAR[string.sub(uci, 5, 5)]
        if not promo then return nil end
    end
    legal = legal or E.GenLegal(pos)
    for i = 1, #legal do
        local m = legal[i]
        if MFrom(m) == from and MTo(m) == to and MPromo(m) == promo then return m end
    end
    return nil
end

-- Standard algebraic notation for a legal move in the current position.
function E.ToSAN(pos, m, legal)
    legal = legal or E.GenLegal(pos)
    local from, to, promo, flag = MFrom(m), MTo(m), MPromo(m), MFlag(m)
    local b = pos.b
    local s
    if flag == 2 then
        s = "O-O"
    elseif flag == 3 then
        s = "O-O-O"
    else
        local t = abs(b[from])
        local capture = (b[to] ~= 0) or flag == 1
        if t == 1 then
            s = capture and (string.sub(SqName(from), 1, 1) .. "x" .. SqName(to)) or SqName(to)
            if promo ~= 0 then s = s .. "=" .. SAN_LETTER[promo] end
        else
            local sameFile, sameRank, other = false, false, false
            for i = 1, #legal do
                local o = legal[i]
                if o ~= m and MTo(o) == to and b[MFrom(o)] == b[from] then
                    other = true
                    if FileOf(MFrom(o)) == FileOf(from) then sameFile = true end
                    if RankOf(MFrom(o)) == RankOf(from) then sameRank = true end
                end
            end
            local dis = ""
            if other then
                local name = SqName(from)
                if not sameFile then
                    dis = string.sub(name, 1, 1)
                elseif not sameRank then
                    dis = string.sub(name, 2, 2)
                else
                    dis = name
                end
            end
            s = SAN_LETTER[t] .. dis .. (capture and "x" or "") .. SqName(to)
        end
    end
    E.Make(pos, m)
    if E.InCheck(pos) then
        s = s .. ((#E.GenLegal(pos) == 0) and "#" or "+")
    end
    E.Unmake(pos)
    return s
end

-- Counts leaf nodes to a given depth; used by the test suite.
function E.Perft(pos, depth)
    if depth == 0 then return 1 end
    local list = {}
    local n = E.GenPseudo(pos, list)
    local c = pos.turn
    local total = 0
    for i = 1, n do
        E.Make(pos, list[i])
        if not Attacked(pos, pos.ks[c], -c) then
            total = total + E.Perft(pos, depth - 1)
        end
        E.Unmake(pos)
    end
    return total
end
