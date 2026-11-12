-- Flightpath Legends - Battleship: rules, sealed fleets, computer admiral and online play.
--
-- Classic rules: 10x10 sea, five ships (5, 4, 3, 3, 2), one shot per turn, turns alternate.
-- Fair play: before the first shot each player sends a SHA-256 seal of their fleet
-- (layout + secret salt). At the end both fleets are revealed; each client checks the
-- other's seal, that the fleet was legal and that every hit/miss answer was honest.
local _, ns = ...

local BS = {}
ns.Battleship = BS

local C, P, D = ns.Comm, ns.Profile, ns.Data
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

BS.SIZE = 10
BS.TURN_TIME = 60 -- seconds per shot
BS.PLACE_TIME = 120 -- seconds to place the fleet
BS.GRACE = 30 -- extra seconds before an unresponsive opponent forfeits
BS.MAX_MISSED = 3 -- missed turns in a row that forfeit the game
BS.ROWS = "ABCDEFGHIJ"

-- The fleet: Garrison Shipyard vessels.
BS.FLEET = {
    { name = "Carrier", len = 5, art = "carrier" },
    { name = "Dreadnaught", len = 4, art = "dreadnaught" },
    { name = "Cargo Galleon", len = 3, art = "galleon" },
    { name = "Submarine", len = 3, art = "submarine" },
    { name = "Destroyer", len = 2, art = "destroyer" },
}
BS.TOTAL = 17

------------------------------------------------------------------------
-- Rules
------------------------------------------------------------------------
function BS.Cell(r, c) return r * 10 + c end
function BS.RC(cell) return floor(cell / 10), cell % 10 end
function BS.CellName(cell)
    local r, c = BS.RC(cell)
    return string.sub(BS.ROWS, r + 1, r + 1) .. (c + 1)
end

-- Cells of ship i at (r, c), vertical or not.
function BS.ShipCells(i, r, c, v)
    local out = {}
    for k = 0, BS.FLEET[i].len - 1 do
        local rr, cc = v and r + k or r, v and c or c + k
        if rr < 0 or rr > 9 or cc < 0 or cc > 9 then return nil end
        out[#out + 1] = BS.Cell(rr, cc)
    end
    return out
end

-- A layout is { [i] = { r = , c = , v = } } for the five ships.
-- Returns occupancy { [cell] = shipIndex } or nil if illegal.
function BS.Occupancy(layout)
    local occ = {}
    for i = 1, #BS.FLEET do
        local s = layout[i]
        if not s then return nil end
        local cells = BS.ShipCells(i, s.r, s.c, s.v)
        if not cells then return nil end
        for _, cell in ipairs(cells) do
            if occ[cell] then return nil end
            occ[cell] = i
        end
    end
    return occ
end

function BS.RandomLayout()
    for _ = 1, 1000 do
        local layout, occ, ok = {}, {}, true
        for i = 1, #BS.FLEET do
            local placed = false
            for _ = 1, 200 do
                local v = math.random(0, 1) == 1
                local r, c = math.random(0, 9), math.random(0, 9)
                local cells = BS.ShipCells(i, r, c, v)
                local free = cells ~= nil
                if cells then for _, cell in ipairs(cells) do if occ[cell] then free = false end end end
                if free then
                    for _, cell in ipairs(cells) do occ[cell] = i end
                    layout[i] = { r = r, c = c, v = v }
                    placed = true
                    break
                end
            end
            if not placed then ok = false break end
        end
        if ok then return layout end
    end
end

-- "rcO" per ship (O = h or v): 15 characters.
function BS.Encode(layout)
    local t = {}
    for i = 1, #BS.FLEET do
        local s = layout[i]
        t[i] = s.r .. s.c .. (s.v and "v" or "h")
    end
    return table.concat(t)
end

function BS.Decode(str)
    if type(str) ~= "string" or #str ~= 3 * #BS.FLEET then return nil end
    local layout = {}
    for i = 1, #BS.FLEET do
        local r, c, o = string.match(string.sub(str, i * 3 - 2, i * 3), "^(%d)(%d)([hv])$")
        if not r then return nil end
        layout[i] = { r = tonumber(r), c = tonumber(c), v = o == "v" }
    end
    if not BS.Occupancy(layout) then return nil end
    return layout
end

function BS.Seal(layout, salt)
    return ns.Hash.SHA256("FPL-BS1:" .. BS.Encode(layout) .. ":" .. salt)
end

-- Result of a shot at cell against a fleet: "m", "h" or "s<i>" (sunk ship i).
-- hits is the set of cells already hit on this fleet (updated).
function BS.Resolve(occ, hits, cell)
    local i = occ[cell]
    if not i then return "m" end
    hits[cell] = true
    for c2, j in pairs(occ) do
        if j == i and not hits[c2] then return "h" end
    end
    return "s" .. i
end

function BS.AllSunk(occ, hits)
    for cell in pairs(occ) do
        if not hits[cell] then return false end
    end
    return true
end

-- Checks a revealed fleet: seal, legality and every answer given during the battle.
-- answers = { [cell] = "m" | "h" | "s<i>" } as reported by that player.
function BS.Verify(seal, layoutStr, salt, answers)
    local layout = BS.Decode(layoutStr)
    if not layout then return false, "their fleet layout was not legal" end
    if type(salt) ~= "string" or BS.Seal(layout, salt) ~= seal then
        return false, "their fleet does not match the seal they sent before the battle"
    end
    local occ = BS.Occupancy(layout)
    -- Replay their answers in order against the real fleet.
    local hits = {}
    for _, e in ipairs(answers) do
        local truth = BS.Resolve(occ, hits, e.cell)
        if truth ~= e.res then
            return false, "they reported " .. BS.CellName(e.cell) .. " wrongly"
        end
    end
    return true
end

------------------------------------------------------------------------
-- Computer admiral
------------------------------------------------------------------------
BS.LEVELS = { "Cadet", "Captain", "Admiral" }

-- known = { [cell] = "m" | "h" | "s" }, sunkLens = list of remaining ship lengths
local function Neighbours(cell)
    local r, c = BS.RC(cell)
    local out = {}
    if r > 0 then out[#out + 1] = cell - 10 end
    if r < 9 then out[#out + 1] = cell + 10 end
    if c > 0 then out[#out + 1] = cell - 1 end
    if c < 9 then out[#out + 1] = cell + 1 end
    return out
end

local function RandomUnknown(known, parity)
    local list = {}
    for cell = 0, 99 do
        if not known[cell] then
            local r, c = BS.RC(cell)
            if not parity or (r + c) % 2 == 0 then list[#list + 1] = cell end
        end
    end
    if #list == 0 and parity then return RandomUnknown(known, false) end
    return list[math.random(1, #list)]
end

-- Probability density: how many ways each unknown cell could hold a remaining ship.
local function Density(known, remaining)
    local score = {}
    local openHits = {}
    for cell, k in pairs(known) do if k == "h" then openHits[cell] = true end end
    for _, len in ipairs(remaining) do
        for r = 0, 9 do
            for c = 0, 9 do
                for _, v in ipairs({ false, true }) do
                    local fits, covers = true, 0
                    local cells = {}
                    for k = 0, len - 1 do
                        local rr, cc = v and r + k or r, v and c or c + k
                        if rr > 9 or cc > 9 then fits = false break end
                        local cell = BS.Cell(rr, cc)
                        local kn = known[cell]
                        if kn == "m" or kn == "s" then fits = false break end
                        if kn == "h" then covers = covers + 1 end
                        cells[#cells + 1] = cell
                    end
                    if fits then
                        local w = 1 + covers * 20 -- placements through open hits matter most
                        for _, cell in ipairs(cells) do
                            if not known[cell] then score[cell] = (score[cell] or 0) + w end
                        end
                    end
                end
            end
        end
    end
    local best, bestScore = nil, -1
    for cell, sc in pairs(score) do
        if sc > bestScore or (sc == bestScore and math.random() < 0.5) then best, bestScore = cell, sc end
    end
    return best
end

-- Target mode: extend a line of open hits, or try around a lone hit.
local function Target(known)
    local hits = {}
    for cell, k in pairs(known) do if k == "h" then hits[#hits + 1] = cell end end
    if #hits == 0 then return nil end
    table.sort(hits)
    for _, h in ipairs(hits) do
        for _, step in ipairs({ 1, 10 }) do
            if known[h + step] == "h" and (step == 10 or floor((h + 1) / 10) == floor(h / 10)) then
                -- a line: walk both ways to the first unknown cell
                for _, dir in ipairs({ step, -step }) do
                    local cell = h
                    while known[cell] == "h" do
                        local nxt = cell + dir
                        if nxt < 0 or nxt > 99 or (step == 1 and floor(nxt / 10) ~= floor(cell / 10)) then break end
                        cell = nxt
                    end
                    if cell ~= h and not known[cell] and cell >= 0 and cell <= 99 then return cell end
                end
            end
        end
    end
    local options = {}
    for _, h in ipairs(hits) do
        for _, n in ipairs(Neighbours(h)) do
            if not known[n] then options[#options + 1] = n end
        end
    end
    if #options > 0 then return options[math.random(1, #options)] end
    return nil
end

function BS.AIShot(level, known, remaining)
    if level <= 1 then return RandomUnknown(known, false) end
    if level == 2 then return Target(known) or RandomUnknown(known, true) end
    return Density(known, remaining) or RandomUnknown(known, false)
end

------------------------------------------------------------------------
-- Session
------------------------------------------------------------------------
BS.current = nil
local unacked = {}

local function Fire(event, ...) ns.Fire(event, ...) end

local function NewSession(o)
    local s = {
        id = o.id or ns.NewId(), mode = o.mode, opp = o.opp, oppName = o.oppName or o.opp,
        iFirst = o.iFirst, level = o.level,
        phase = "place", -- place -> battle -> over
        myShots = {}, theirShots = {}, -- [cell] = result (shots I fired / shots at my fleet)
        myLog = {}, theirLog = {}, -- in order: { cell = , res = }
        sunkMine = {}, sunkTheirs = {}, -- [shipIndex] = true
        revealTheirs = {}, -- [shipIndex] = { r, c, v } (sunk ships revealed by the opponent)
        missed = 0, seq = 0, seen = {},
        placeDeadline = ns.Now() + BS.PLACE_TIME,
    }
    s.myLayout = BS.RandomLayout()
    s.white = s.iFirst and ns.me or s.opp
    s.black = s.iFirst and s.opp or ns.me
    return s
end

function BS.Busy()
    local s = BS.current
    return s ~= nil and s.phase ~= "over" and s.mode == "online"
end

function BS.Active()
    local s = BS.current
    return s ~= nil and s.phase ~= "over"
end

-- Reliable whisper (resent until acknowledged). Returns the message key.
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

-- Accept a reliable message from the opponent: returns the session if it is new.
-- noAck: the reply itself acknowledges it (a shot is acknowledged by its result).
local function Accept(sender, parts, noAck)
    local gid, seq = parts[2], tonumber(parts[3])
    local s = BS.current
    if not (s and s.id == gid and s.mode == "online" and s.opp == sender and seq) then return nil end
    if not noAck then C.Whisper(sender, "BK", gid, seq) end
    if s.seen[seq] then return nil, s end
    s.seen[seq] = true
    return s
end

C.handlers.BK = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local key = (parts[2] or "") .. ":" .. (parts[3] or "")
    local u = unacked[key]
    if u and u.target == sender then unacked[key] = nil end
end

------------------------------------------------------------------------
-- Starting
------------------------------------------------------------------------
local function Begin(s)
    BS.current = s
    s.occ = BS.Occupancy(s.myLayout)
    Fire("BS_STARTED", s)
    Fire("BS_CHANGED", s)
    if s.mode == "online" then ns.Game.Announce(true) end
end

-- Online game, after a challenge was accepted. iFirst: we fire the first shot.
function BS.StartOnline(id, opp, iFirst)
    local s = NewSession({ id = id, mode = "online", opp = opp, iFirst = iFirst })
    Begin(s)
    return s
end

function BS.StartAI(level)
    local s = NewSession({ mode = "ai", opp = "Computer", iFirst = math.random(1, 2) == 1, level = level or 2 })
    s.oppName = "Computer (" .. BS.LEVELS[s.level] .. ")"
    s.white = s.iFirst and ns.me or s.oppName
    s.black = s.iFirst and s.oppName or ns.me
    s.aiLayout = BS.RandomLayout()
    s.aiOcc = BS.Occupancy(s.aiLayout)
    s.aiHits = {}
    Begin(s)
    return s
end

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------
-- Moves ship i (fails if the new position is illegal).
function BS.MoveShip(i, r, c, v)
    local s = BS.current
    if not s or s.phase ~= "place" or s.ready then return false end
    local old = s.myLayout[i]
    s.myLayout[i] = { r = r, c = c, v = v }
    if not BS.Occupancy(s.myLayout) then
        s.myLayout[i] = old
        return false
    end
    s.occ = BS.Occupancy(s.myLayout)
    Fire("BS_CHANGED", s)
    return true
end

function BS.Shuffle()
    local s = BS.current
    if not s or s.phase ~= "place" or s.ready then return end
    s.myLayout = BS.RandomLayout()
    s.occ = BS.Occupancy(s.myLayout)
    Fire("BS_CHANGED", s)
end

local function StartBattle(s)
    s.phase = "battle"
    s.myTurn = s.iFirst
    s.turnStart = ns.Now()
    s.missed = 0
    if s.mode == "online" then
        -- Witnessed record: both players state that this battle started.
        ns.Ledger.StateOwn({ id = s.id, white = s.white, black = s.black, mode = "online", kind = "b" }, nil)
    end
    Fire("BS_BATTLE", s)
    Fire("BS_CHANGED", s)
    if s.mode == "ai" and not s.myTurn then BS.AITurnSoon(s) end
end

-- Seals the fleet and tells the opponent we are ready.
function BS.Ready()
    local s = BS.current
    if not s or s.phase ~= "place" or s.ready then return end
    s.ready = true
    s.salt = ns.Hash.Salt()
    s.seal = BS.Seal(s.myLayout, s.salt)
    if s.mode == "ai" then
        StartBattle(s)
        return
    end
    Send(s, "BC", s.seal)
    if s.theirSeal then StartBattle(s) end
    Fire("BS_CHANGED", s)
end

C.handlers.BC = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "place" then return end
    local seal = parts[4]
    if type(seal) ~= "string" or not string.match(seal, "^%x+$") or #seal ~= 64 then return end
    s.theirSeal = seal
    if s.ready then StartBattle(s) end
    Fire("BS_CHANGED", s)
end

------------------------------------------------------------------------
-- Shooting
------------------------------------------------------------------------
local Finish, ProcessReveal -- forward

local function ShotsFired(s)
    local n = 0
    for _ in pairs(s.myShots) do n = n + 1 end
    return n
end
BS.ShotsFired = ShotsFired

-- Records the answer to one of our shots.
local function OnResult(s, cell, res, reveal)
    s.myShots[cell] = res
    s.myLog[#s.myLog + 1] = { cell = cell, res = res }
    s.awaiting = nil
    local i = tonumber(string.match(res, "^s(%d)$"))
    if i then
        s.sunkTheirs[i] = true
        if reveal then s.revealTheirs[i] = reveal end
    end
    Fire("BS_SHOT", s, true, cell, res)
    Relay(s, "BW", s.id, ns.me, cell, res, reveal and (reveal.r .. reveal.c .. (reveal.v and "v" or "h")) or "")
    local sunkAll = true
    for k = 1, #BS.FLEET do if not s.sunkTheirs[k] then sunkAll = false end end
    if sunkAll then
        Finish(s, "win", "fleet")
        return
    end
    s.myTurn = false
    s.turnStart = ns.Now()
    Fire("BS_CHANGED", s)
    if s.mode == "ai" then BS.AITurnSoon(s) end
end

-- Fires at a cell of the enemy sea (our turn only).
function BS.FireAt(cell, auto)
    local s = BS.current
    if not s or s.phase ~= "battle" or not s.myTurn or s.awaiting then return false end
    if s.myShots[cell] or cell < 0 or cell > 99 then return false end
    if not auto then s.missed = 0 end
    s.awaiting = cell
    Fire("BS_FIRING", s, cell)
    if s.mode == "ai" then
        local res = BS.Resolve(s.aiOcc, s.aiHits, cell)
        local i = tonumber(string.match(res, "^s(%d)$"))
        ns.After(0.5, function()
            if BS.current ~= s or s.phase ~= "battle" then return end
            OnResult(s, cell, res, i and s.aiLayout[i] or nil)
        end)
    else
        s.fireKey = Send(s, "BF", #s.myLog + #s.theirLog + 1, cell)
    end
    return true
end

-- The opponent fires at us.
local function OnIncoming(s, cell)
    s.hitsOnMe = s.hitsOnMe or {}
    local res = BS.Resolve(s.occ, s.hitsOnMe, cell)
    s.theirShots[cell] = res
    s.theirLog[#s.theirLog + 1] = { cell = cell, res = res }
    local i = tonumber(string.match(res, "^s(%d)$"))
    if i then s.sunkMine[i] = true end
    Fire("BS_SHOT", s, false, cell, res)
    return res, i
end

C.handlers.BF = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s, dup = Accept(sender, parts, true)
    if not s then
        -- The same shot again: our answer was lost, send it once more.
        if dup and dup.lastAnswer and dup.lastAnswerFor == tonumber(parts[3]) then
            C.SendRaw("WHISPER", sender, dup.lastAnswer)
        end
        return
    end
    if s.phase ~= "battle" or s.myTurn then return end
    local n, cell = tonumber(parts[4]), tonumber(parts[5])
    if not n or not cell or cell < 0 or cell > 99 or cell ~= floor(cell) then return end
    if n ~= #s.myLog + #s.theirLog + 1 or s.theirShots[cell] then return end
    local res, i = OnIncoming(s, cell)
    local ship = i and s.myLayout[i]
    local _, text = Send(s, "BR", n, cell, res, ship and (ship.r .. ship.c .. (ship.v and "v" or "h")) or "")
    s.lastAnswer, s.lastAnswerFor = text, tonumber(parts[3])
    Relay(s, "BW", s.id, s.opp, cell, res, ship and (ship.r .. ship.c .. (ship.v and "v" or "h")) or "")
    if BS.AllSunk(s.occ, s.hitsOnMe) then
        Finish(s, "loss", "fleet")
        return
    end
    s.myTurn = true
    s.turnStart = ns.Now()
    Fire("BS_CHANGED", s)
end

local function ParseShip(str)
    local r, c, o = string.match(str or "", "^(%d)(%d)([hv])$")
    if not r then return nil end
    return { r = tonumber(r), c = tonumber(c), v = o == "v" }
end

C.handlers.BR = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "battle" or not s.myTurn then return end
    local cell, res = tonumber(parts[5]), parts[6]
    if cell ~= s.awaiting then return end
    if res ~= "m" and res ~= "h" and not string.match(res or "", "^s[1-5]$") then return end
    if s.fireKey then unacked[s.fireKey] = nil; s.fireKey = nil end
    OnResult(s, cell, res, ParseShip(parts[7]))
end

-- Computer's turn.
function BS.AITurnSoon(s)
    ns.After(0.9, function()
        if BS.current ~= s or s.phase ~= "battle" or s.myTurn then return end
        local known, remaining = {}, {}
        for cell, res in pairs(s.theirShots) do known[cell] = (res == "m") and "m" or "h" end
        -- cells of sunk ships are no longer "open hits"
        for i in pairs(s.sunkMine) do
            local sh = s.myLayout[i]
            for _, cell in ipairs(BS.ShipCells(i, sh.r, sh.c, sh.v)) do known[cell] = "s" end
        end
        for i = 1, #BS.FLEET do if not s.sunkMine[i] then remaining[#remaining + 1] = BS.FLEET[i].len end end
        local cell = BS.AIShot(s.level, known, remaining)
        if not cell then return end
        OnIncoming(s, cell)
        if BS.AllSunk(s.occ, s.hitsOnMe) then
            Finish(s, "loss", "fleet")
            return
        end
        s.myTurn = true
        s.turnStart = ns.Now()
        Fire("BS_CHANGED", s)
    end)
end

------------------------------------------------------------------------
-- Ending
------------------------------------------------------------------------
local function Statement(s)
    if s.mode ~= "online" or s.stated or not s.outcome then return end
    s.stated = true
    local iWhite = s.white == ns.me
    local res
    if s.outcome == "win" then res = iWhite and "1-0" or "0-1" else res = iWhite and "0-1" or "1-0" end
    ns.Ledger.StateOwn({ id = s.id, white = s.white, black = s.black, mode = "online", kind = "b" }, res)
end

-- outcome: "win" | "loss" | "abort"; reason: fleet, resign, time, abandoned, cheat, abort
Finish = function(s, outcome, reason)
    if s.phase == "over" then return end
    s.phase = "over"
    s.outcome = outcome
    s.reason = reason
    s.myTurn = false
    s.awaiting = nil
    if s.mode == "online" then
        -- Reveal our fleet so the opponent can check our answers.
        if s.ready and outcome ~= "abort" then
            Send(s, "BV", BS.Encode(s.myLayout), s.salt or "")
        end
        -- A win stands at once; a loss is only confirmed once the winner's fleet checks out.
        if outcome == "win" then
            Statement(s)
        elseif outcome == "loss" and reason ~= "fleet" then
            Statement(s) -- resigned or timed out ourselves
        elseif outcome == "loss" then
            s.verifyDeadline = ns.Now() + 90
        end
        Relay(s, "BE", s.id, outcome == "win" and ns.me or s.opp, reason)
    end
    if outcome ~= "abort" and s.mode ~= "spectate" then
        P.RecordGame({
            mode = "bs", outcome = outcome, vsAI = s.mode == "ai", aiLevel = s.level or 0,
            shots = ShotsFired(s), shipsLeft = (function()
                local n = 0
                for i = 1, #BS.FLEET do if not s.sunkMine[i] then n = n + 1 end end
                return n
            end)(), opp = s.opp,
        })
    end
    Fire("BS_OVER", s)
    Fire("BS_CHANGED", s)
    if s.mode == "online" then ns.Game.Announce(true) end
    if s.earlyReveal then
        local r = s.earlyReveal
        s.earlyReveal = nil
        ProcessReveal(s, r[1], r[2])
    end
end
BS.Finish = function(outcome, reason) if BS.current then Finish(BS.current, outcome, reason) end end

-- Checks the opponent's revealed fleet against their seal and every answer they gave.
ProcessReveal = function(s, layoutStr, salt)
    if s.verified ~= nil then return end
    local ok, why = BS.Verify(s.theirSeal or "", layoutStr, salt, s.myLog)
    s.verified = ok
    s.theirLayout = ok and BS.Decode(layoutStr) or nil
    if not ok then
        s.cheat = why
        ns.Print("|cffff4030Fair-play check failed: " .. why .. ". This battle is disputed and will not count.|r")
        if s.outcome == "loss" then
            -- We do not accept a loss against a fleet that broke the rules.
            s.outcome = "disputed"
            s.stated = true
            local iWhite = s.white == ns.me
            ns.Ledger.StateOwn({ id = s.id, white = s.white, black = s.black, mode = "online", kind = "b" }, iWhite and "1-0" or "0-1")
        end
    else
        Statement(s)
    end
    s.verifyDeadline = nil
    Fire("BS_CHANGED", s)
end

C.handlers.BV = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s then return end
    if s.phase ~= "over" then
        -- Their reveal overtook the last shot result: keep it until our side has finished.
        s.earlyReveal = { parts[4], parts[5] }
        return
    end
    ProcessReveal(s, parts[4], parts[5])
end

function BS.Resign()
    local s = BS.current
    if not s or s.phase == "over" then return end
    if s.mode == "online" then
        if s.phase == "place" then
            Send(s, "BQ", "abort")
            Finish(s, "abort", "abort")
        else
            Send(s, "BQ", "resign")
            Finish(s, "loss", "resign")
        end
    elseif s.mode == "spectate" then
        BS.StopWatching()
    else
        Finish(s, "loss", "resign")
    end
end

C.handlers.BQ = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase == "over" then return end
    if parts[4] == "abort" and s.phase == "place" then
        Finish(s, "abort", "abort")
    else
        Finish(s, "win", parts[4] == "time" and "time" or "resign")
    end
end

------------------------------------------------------------------------
-- Spectating: the player relays every shot (fleets stay hidden until sunk)
------------------------------------------------------------------------
function BS.HandleWatchRequest(sender)
    local s = BS.current
    if not (s and s.mode == "online" and s.phase == "battle" and ns.db.settings.allowSpectators) then return false end
    s.spectators = s.spectators or {}
    local n = 0
    for _ in pairs(s.spectators) do n = n + 1 end
    if not s.spectators[sender] and n >= 5 then return false end
    s.spectators[sender] = true
    -- Snapshot: players, then every shot so far as "who,cell,res".
    C.Whisper(sender, "BX", s.id, ns.me, s.opp, s.white)
    local entries = {}
    for _, e in ipairs(s.myLog) do entries[#entries + 1] = "1" .. e.cell .. "." .. e.res end
    for _, e in ipairs(s.theirLog) do entries[#entries + 1] = "2" .. e.cell .. "." .. e.res end
    local chunk = {}
    for i, e in ipairs(entries) do
        chunk[#chunk + 1] = e
        if #chunk == 30 or i == #entries then
            C.Whisper(sender, "BY", s.id, table.concat(chunk, ","))
            chunk = {}
        end
    end
    return true
end

C.handlers.BX = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    if not (ns.Game.watchPending and ns.SameName(ns.Game.watchPending, sender)) then return end
    ns.Game.watchPending = nil
    local s = NewSession({ id = parts[2], mode = "spectate", opp = parts[4] })
    s.source = sender
    s.host, s.guest = parts[3], parts[4]
    s.white = parts[5]
    s.phase = "battle"
    s.myLayout = nil
    BS.current = s
    Fire("BS_STARTED", s)
    Fire("BS_CHANGED", s)
end

-- Spectator view: myShots = host's shots (at the guest), theirShots = guest's shots (at the host).
local function SpectatorShot(s, who, cell, res, reveal)
    local byHost = ns.SameName(who, s.host)
    local t = byHost and s.myShots or s.theirShots
    t[cell] = res
    local i = tonumber(string.match(res, "^s(%d)$"))
    if i then
        if byHost then s.sunkTheirs[i] = true; s.revealTheirs[i] = reveal
        else s.sunkMine[i] = true; s.revealMine = s.revealMine or {}; s.revealMine[i] = reveal end
    end
end

C.handlers.BY = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = BS.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2]) then return end
    for e in string.gmatch(parts[3] or "", "[^,]+") do
        local who, cell, res = string.match(e, "^([12])(%d+)%.(%w+)$")
        if who then SpectatorShot(s, who == "1" and s.host or s.guest, tonumber(cell), res) end
    end
    Fire("BS_CHANGED", s)
end

C.handlers.BW = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = BS.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2]) then return end
    local cell = tonumber(parts[4])
    if not cell then return end
    SpectatorShot(s, parts[3], cell, parts[5] or "m", ParseShip(parts[6]))
    Fire("BS_SHOT", s, ns.SameName(parts[3], s.host), cell, parts[5])
    Fire("BS_CHANGED", s)
end

C.handlers.BE = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = BS.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2]) then return end
    s.phase = "over"
    s.winner = parts[3]
    s.reason = parts[4]
    P.RecordGame({ mode = "spectate", outcome = "none" })
    Fire("BS_OVER", s)
    Fire("BS_CHANGED", s)
end

function BS.StopWatching()
    local s = BS.current
    if s and s.mode == "spectate" and s.phase ~= "over" then
        C.Whisper(s.source, "SX", s.id)
        s.phase = "over"
        Fire("BS_CHANGED", s)
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
                u.next = now + 2 -- still waiting to go out: no duplicate
            else
                u.tries = u.tries + 1
                if u.tries > 15 then unacked[key] = nil else
                    u.next = now + 5
                    C.SendRaw("WHISPER", u.target, u.text)
                end
            end
        end
    end
    local s = BS.current
    if not s then return end
    if s.phase == "place" and not s.ready and now >= s.placeDeadline then
        BS.Ready() -- the fleet as it stands sails out
    elseif s.phase == "place" and s.ready and s.mode == "online" and now >= s.placeDeadline + BS.PLACE_TIME then
        Send(s, "BQ", "abort")
        Finish(s, "abort", "abandoned")
    elseif s.phase == "battle" and s.mode ~= "spectate" then
        local elapsed = now - (s.turnStart or now)
        if s.myTurn and not s.awaiting and elapsed >= BS.TURN_TIME then
            -- Out of time: a random shot is fired for us.
            s.missed = s.missed + 1
            if s.missed >= BS.MAX_MISSED then
                if s.mode == "online" then Send(s, "BQ", "time") end
                Finish(s, "loss", "time")
                return
            end
            local free = {}
            for cell = 0, 99 do if not s.myShots[cell] then free[#free + 1] = cell end end
            if #free > 0 then
                ns.Print("time's up - a random shot was fired for you (" .. s.missed .. "/" .. BS.MAX_MISSED .. " missed turns).")
                BS.FireAt(free[math.random(1, #free)], true)
            end
        elseif s.mode == "online" and not s.myTurn and elapsed >= BS.TURN_TIME * BS.MAX_MISSED + BS.GRACE then
            -- The opponent has gone silent.
            Finish(s, "win", "abandoned")
        end
    elseif s.phase == "over" and s.verifyDeadline and now >= s.verifyDeadline then
        -- The winner never showed their fleet: we do not accept the loss.
        s.verifyDeadline = nil
        s.outcome = "disputed"
        s.cheat = "they never revealed their fleet"
        s.stated = true
        local iWhite = s.white == ns.me
        ns.Ledger.StateOwn({ id = s.id, white = s.white, black = s.black, mode = "online", kind = "b" }, iWhite and "1-0" or "0-1")
        ns.Print("|cffff4030" .. ns.ShortName(s.opp) .. " never revealed their fleet - this battle is disputed and will not count.|r")
        Fire("BS_CHANGED", s)
    end
end)

function BS.TimeLeft()
    local s = BS.current
    if not s then return 0 end
    if s.phase == "place" then return max(0, s.placeDeadline - ns.Now()) end
    if s.phase == "battle" then return max(0, BS.TURN_TIME - (ns.Now() - (s.turnStart or ns.Now()))) end
    return 0
end
