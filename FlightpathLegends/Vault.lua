-- Flightpath Legends - Vault Breaker: rules, sealed vault codes, computer safecrackers and online play.
--
-- Each player locks a gnomish vault with a secret code of four gems (six kinds, repeats
-- allowed). Every round both players guess the other's code at the same time and get pins
-- back: a gold pin for each right gem in the right slot, a silver pin for each right gem in
-- the wrong slot. Cracking the other vault first wins; cracking in the same round is a draw,
-- and so is nobody cracking it in ten rounds.
-- Fair play: each code is sealed with SHA-256 before the first guess and revealed at the end,
-- so every pin a player gave can be checked.
local _, ns = ...

local VB = {}
ns.Vault = VB

local C, P = ns.Comm, ns.Profile
local floor, max, min = math.floor, math.max, math.min

VB.PEGS = 4
VB.GEMS = 6
VB.ROUNDS = 10
VB.ROUND_TIME = 60 -- seconds per guess
VB.SET_TIME = 90 -- seconds to choose your code
VB.GRACE = 30
VB.MAX_MISSED = 3
VB.LEVELS = { "Novice", "Adept", "Master" }

------------------------------------------------------------------------
-- Rules. A code is a string of four digits 1-6, e.g. "3415".
------------------------------------------------------------------------
function VB.Valid(code)
    return type(code) == "string" and string.match(code, "^[1-6][1-6][1-6][1-6]$") ~= nil
end

function VB.RandomCode()
    local t = {}
    for i = 1, VB.PEGS do t[i] = math.random(1, VB.GEMS) end
    return table.concat(t)
end

-- Pins for a guess against a code: gold (right gem, right slot), silver (right gem, wrong slot).
function VB.Pins(code, guess)
    local gold = 0
    local cc, gc = {}, {}
    for i = 1, VB.PEGS do
        local a, b = string.byte(code, i), string.byte(guess, i)
        if a == b then
            gold = gold + 1
        else
            cc[a] = (cc[a] or 0) + 1
            gc[b] = (gc[b] or 0) + 1
        end
    end
    local silver = 0
    for k, n in pairs(gc) do silver = silver + min(n, cc[k] or 0) end
    return gold, silver
end

function VB.Seal(code, salt)
    return ns.Hash.SHA256("FPL-VB1:" .. code .. ":" .. salt)
end

-- Checks a revealed code against its seal and every pin that player gave.
-- answers = { [round] = { guess = , gold = , silver = } } (our guesses and their pins)
function VB.Verify(seal, code, salt, answers)
    if not VB.Valid(code) then return false, "their vault code was not valid" end
    if type(salt) ~= "string" or VB.Seal(code, salt) ~= seal then
        return false, "their vault code does not match the seal they sent before the game"
    end
    for r, e in pairs(answers) do
        if e.gold then
            local g, sv = VB.Pins(code, e.guess)
            if g ~= e.gold or sv ~= e.silver then
                return false, "they gave false pins for guess " .. r
            end
        end
    end
    return true
end

------------------------------------------------------------------------
-- Computer safecracker
------------------------------------------------------------------------
local ALL = {}
for a = 1, 6 do for b = 1, 6 do for c = 1, 6 do for d = 1, 6 do
    ALL[#ALL + 1] = a .. b .. c .. d
end end end end
VB.ALL = ALL

-- Codes that would have given every pin seen so far. history = list of { guess, gold, silver }.
local function Consistent(history)
    local out = {}
    for i = 1, #ALL do
        local code, ok = ALL[i], true
        for j = 1, #history do
            local h = history[j]
            local g, s = VB.Pins(code, h.guess)
            if g ~= h.gold or s ~= h.silver then ok = false break end
        end
        if ok then out[#out + 1] = code end
    end
    return out
end
VB.Consistent = Consistent

local function Sample(list, n)
    if #list <= n then return list end
    local out, step = {}, #list / n
    for i = 0, n - 1 do out[#out + 1] = list[floor(i * step) + 1] end
    return out
end

-- The guess whose worst-case answer leaves the fewest possible codes (Knuth's idea, sampled).
local function Minimax(cands)
    local pool = Sample(cands, 120)
    local against = Sample(cands, 240)
    local best, bestWorst = pool[1], math.huge
    for i = 1, #pool do
        local guess, parts, worst = pool[i], {}, 0
        for j = 1, #against do
            local g, s = VB.Pins(against[j], guess)
            local k = g * 5 + s
            local n = (parts[k] or 0) + 1
            parts[k] = n
            if n > worst then worst = n end
            if worst >= bestWorst then break end
        end
        if worst < bestWorst then best, bestWorst = guess, worst end
    end
    return best
end

-- Next guess for the computer at a level, given its history of guesses and pins.
function VB.AIGuess(level, history)
    if #history == 0 then
        if level >= 3 then return "1122" end
        return VB.RandomCode()
    end
    if level <= 1 and math.random() < 0.45 then return VB.RandomCode() end
    local cands = Consistent(history)
    if #cands == 0 then return VB.RandomCode() end
    if level <= 2 or #cands <= 2 then return cands[math.random(1, #cands)] end
    return Minimax(cands)
end

------------------------------------------------------------------------
-- Session
------------------------------------------------------------------------
VB.current = nil
local unacked = {}

local function Fire(event, ...) ns.Fire(event, ...) end

local function NewSession(o)
    local s = {
        id = o.id or ns.NewId(), mode = o.mode, opp = o.opp, oppName = o.oppName or o.opp,
        iFirst = o.iFirst, level = o.level,
        phase = "set", -- set -> play -> over
        myCode = VB.RandomCode(),
        round = 1,
        mine = {}, -- [round] = { guess, gold, silver }: our guesses at their vault
        theirs = {}, -- [round] = { guess, gold, silver }: their guesses at our vault
        missed = 0, seq = 0, seen = {},
        setDeadline = ns.Now() + VB.SET_TIME,
    }
    s.white = s.iFirst and ns.me or s.opp
    s.black = s.iFirst and s.opp or ns.me
    return s
end

function VB.Busy()
    local s = VB.current
    return s ~= nil and s.phase ~= "over" and s.mode == "online"
end

function VB.Active()
    local s = VB.current
    return s ~= nil and s.phase ~= "over"
end

-- Rounds finished so far (for the Live Games list).
function VB.MoveCount(s) return max(0, (s.round or 1) - 1) end

-- Whether we can lock in a guess right now.
function VB.CanGuess()
    local s = VB.current
    return s ~= nil and s.phase == "play" and s.mode ~= "spectate" and not s.mine[s.round]
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
    local s = VB.current
    if not (s and s.id == gid and s.mode == "online" and s.opp == sender and seq) then return nil end
    C.Whisper(sender, "KK", gid, seq)
    if s.seen[seq] then return nil end
    s.seen[seq] = true
    return s
end

C.handlers.KK = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local key = (parts[2] or "") .. ":" .. (parts[3] or "")
    local u = unacked[key]
    if u and u.target == sender then unacked[key] = nil end
end

local function Statement(s, res)
    if s.mode ~= "online" then return end
    ns.Ledger.StateOwn({ id = s.id, white = s.white, black = s.black, mode = "online", kind = "v" }, res)
end

local function Begin(s)
    VB.current = s
    Fire("VB_STARTED", s)
    Fire("VB_CHANGED", s)
    if s.mode == "online" then ns.Game.Announce(true) end
end

function VB.StartOnline(id, opp, iFirst)
    local s = NewSession({ id = id, mode = "online", opp = opp, iFirst = iFirst })
    Begin(s)
    return s
end

function VB.StartAI(level)
    level = level or 2
    local s = NewSession({ mode = "ai", opp = "Computer", iFirst = true, level = level })
    s.oppName = "Computer (" .. VB.LEVELS[level] .. ")"
    s.black = s.oppName
    s.aiCode = VB.RandomCode()
    Begin(s)
    return s
end

------------------------------------------------------------------------
-- Choosing the code
------------------------------------------------------------------------
function VB.SetCode(code)
    local s = VB.current
    if not s or s.phase ~= "set" or s.ready or not VB.Valid(code) then return false end
    s.myCode = code
    Fire("VB_CHANGED", s)
    return true
end

local function StartPlay(s)
    s.phase = "play"
    s.round = 1
    s.roundStart = ns.Now()
    s.missed = 0
    Statement(s, nil) -- witnessed record: both players state that this game started
    Fire("VB_PLAY", s)
    Fire("VB_CHANGED", s)
end

-- Seals our vault and tells the opponent we are ready.
function VB.Ready()
    local s = VB.current
    if not s or s.phase ~= "set" or s.ready then return end
    s.ready = true
    s.salt = ns.Hash.Salt()
    s.seal = VB.Seal(s.myCode, s.salt)
    if s.mode == "ai" then
        StartPlay(s)
        return
    end
    Send(s, "KC", s.seal)
    if s.theirSeal then StartPlay(s) end
    Fire("VB_CHANGED", s)
end

C.handlers.KC = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "set" then return end
    local seal = parts[4]
    if type(seal) ~= "string" or not string.match(seal, "^%x+$") or #seal ~= 64 then return end
    s.theirSeal = seal
    if s.ready then StartPlay(s) end
    Fire("VB_CHANGED", s)
end

------------------------------------------------------------------------
-- Rounds
------------------------------------------------------------------------
local Finish -- forward

local function Encode(e) return e.guess .. "." .. e.gold .. "." .. e.silver end

-- Ends rounds for which both guesses have their pins.
local function TryResolve(s)
    while s.phase == "play" do
        local r = s.round
        local m, t = s.mine[r], s.theirs[r]
        if not (m and m.gold and t and t.gold) then return end
        local iCracked, theyCracked = m.gold == VB.PEGS, t.gold == VB.PEGS
        Fire("VB_ROUND", s, r)
        if s.mode == "online" then
            Relay(s, "KW", s.id, r, Encode(m), Encode(t))
        end
        if iCracked then s.crackRound = r end
        if iCracked and theyCracked then
            Finish(s, "draw", "both")
        elseif iCracked then
            Finish(s, "win", "cracked")
        elseif theyCracked then
            Finish(s, "loss", "cracked")
        elseif r >= VB.ROUNDS then
            Finish(s, "draw", "rounds")
        else
            s.round = r + 1
            s.roundStart = ns.Now()
            Fire("VB_CHANGED", s)
        end
    end
end

-- Locks in our guess for this round.
function VB.Guess(code, auto)
    local s = VB.current
    if not VB.CanGuess() or not VB.Valid(code) then return false end
    if not auto then s.missed = 0 end
    local r = s.round
    s.mine[r] = { guess = code }
    Fire("VB_GUESSED", s, r)
    Fire("VB_CHANGED", s)
    if s.mode == "online" then
        Send(s, "KG", r, code)
    elseif s.mode == "ai" then
        ns.After(0.9, function()
            if VB.current ~= s or s.phase ~= "play" or s.round ~= r then return end
            local g, sv = VB.Pins(s.aiCode, code)
            s.mine[r].gold, s.mine[r].silver = g, sv
            local history = {}
            for k = 1, r - 1 do history[#history + 1] = s.theirs[k] end
            local ag = VB.AIGuess(s.level, history)
            local tg, ts = VB.Pins(s.myCode, ag)
            s.theirs[r] = { guess = ag, gold = tg, silver = ts }
            TryResolve(s)
        end)
    end
    return true
end

-- Their guess at our vault: we answer with pins.
C.handlers.KG = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "play" then return end
    local r, guess = tonumber(parts[4]), parts[5]
    if not r or (r ~= s.round and r ~= s.round + 1) or s.theirs[r] or not VB.Valid(guess) then return end
    local g, sv = VB.Pins(s.myCode, guess)
    s.theirs[r] = { guess = guess, gold = g, silver = sv }
    Send(s, "KF", r, g, sv)
    Fire("VB_THEY_GUESSED", s, r)
    TryResolve(s)
    Fire("VB_CHANGED", s)
end

-- Pins for our guess.
C.handlers.KF = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase ~= "play" then return end
    local r, g, sv = tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6])
    local m = r and s.mine[r]
    if not m or m.gold or not g or not sv or g < 0 or sv < 0 or g + sv > VB.PEGS or g ~= floor(g) or sv ~= floor(sv) then return end
    m.gold, m.silver = g, sv
    TryResolve(s)
    Fire("VB_CHANGED", s)
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

local function Announced(s)
    -- host's code, and the guest's once known (spectators see both at the end)
    return s.myCode or "", s.theirCode or ""
end

-- outcome: "win" | "loss" | "draw" | "abort"; reason: cracked, both, rounds, resign, time, abandoned, abort
Finish = function(s, outcome, reason)
    if s.phase == "over" then return end
    local wasSet = s.phase == "set"
    s.phase = "over"
    s.outcome, s.reason = outcome, reason
    if s.mode == "online" then
        if s.ready and outcome ~= "abort" then Send(s, "KV", s.myCode, s.salt or "") end
        if outcome == "win" or (outcome == "loss" and reason ~= "cracked") then
            -- a win stands at once, and so does losing by our own resignation or time
            s.stated = true
            Statement(s, Result(s, outcome))
        elseif outcome ~= "abort" then
            -- a loss or a draw is only confirmed once their pins check out against their code
            s.verifyDeadline = ns.Now() + 90
        end
        local winner = (outcome == "win" and ns.me) or (outcome == "loss" and s.opp) or ""
        local hc, gc = Announced(s)
        Relay(s, "KE", s.id, winner, reason, hc, gc)
    end
    if outcome ~= "abort" and s.mode ~= "spectate" and not wasSet then
        P.RecordGame({
            mode = "vb", outcome = outcome, vsAI = s.mode == "ai", aiLevel = s.level or 0, opp = s.opp,
            cracked = s.crackRound ~= nil, rounds = s.crackRound or 0,
        })
    end
    if s.mode == "ai" then s.theirCode = s.aiCode end
    Fire("VB_OVER", s)
    Fire("VB_CHANGED", s)
    if s.mode == "online" then ns.Game.Announce(true) end
    if s.earlyReveal then
        local r = s.earlyReveal
        s.earlyReveal = nil
        ProcessReveal(s, r[1], r[2])
    end
end
VB.Finish = function(outcome, reason) if VB.current then Finish(VB.current, outcome, reason) end end

ProcessReveal = function(s, code, salt)
    if s.verified ~= nil then return end
    local ok, why = VB.Verify(s.theirSeal or "", code, salt, s.mine)
    s.verified = ok
    if ok then
        s.theirCode = code
        if not s.stated then
            s.stated = true
            Statement(s, Result(s, s.outcome))
        end
        Relay(s, "KE", s.id, (s.outcome == "win" and ns.me) or (s.outcome == "loss" and s.opp) or "", s.reason, s.myCode, code)
    else
        s.cheat = why
        ns.Print("|cffff4030Fair-play check failed: " .. why .. ". This game is disputed and will not count.|r")
        if not s.stated then
            -- We do not accept a loss or a draw against a vault that broke the rules.
            s.outcome = "disputed"
            s.stated = true
            Statement(s, Result(s, "win"))
        end
    end
    s.verifyDeadline = nil
    Fire("VB_CHANGED", s)
end

C.handlers.KV = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s then return end
    if s.phase ~= "over" then
        s.earlyReveal = { parts[4], parts[5] }
        return
    end
    ProcessReveal(s, parts[4], parts[5])
end

function VB.Resign()
    local s = VB.current
    if not s or s.phase == "over" then return end
    if s.mode == "spectate" then
        VB.StopWatching()
        return
    end
    if s.mode == "online" then
        if s.phase == "set" then
            Send(s, "KQ", "abort")
            Finish(s, "abort", "abort")
            return
        end
        Send(s, "KQ", "resign")
    end
    Finish(s, "loss", "resign")
end

C.handlers.KQ = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = Accept(sender, parts)
    if not s or s.phase == "over" then return end
    if parts[4] == "abort" and s.phase == "set" then
        Finish(s, "abort", "abort")
    else
        Finish(s, "win", parts[4] == "time" and "time" or "resign")
    end
end

------------------------------------------------------------------------
-- Spectating: the host relays every finished round; codes are shown at the end.
--   KX;id;host;guest;white;round;history   KW;id;round;hostGuess;guestGuess   KE;id;winner;reason;hostCode;guestCode
------------------------------------------------------------------------
local function Decode(str)
    local guess, g, sv = string.match(str or "", "^([1-6][1-6][1-6][1-6])%.([0-4])%.([0-4])$")
    if not guess then return nil end
    return { guess = guess, gold = tonumber(g), silver = tonumber(sv) }
end

function VB.HandleWatchRequest(sender)
    local s = VB.current
    if not (s and s.mode == "online" and s.phase == "play" and ns.db.settings.allowSpectators) then return false end
    s.spectators = s.spectators or {}
    local n = 0
    for _ in pairs(s.spectators) do n = n + 1 end
    if not s.spectators[sender] and n >= 5 then return false end
    s.spectators[sender] = true
    local hist = {}
    for r = 1, s.round - 1 do
        if s.mine[r] and s.theirs[r] then hist[#hist + 1] = Encode(s.mine[r]) .. ":" .. Encode(s.theirs[r]) end
    end
    C.Whisper(sender, "KX", s.id, ns.me, s.opp, s.white, s.round, table.concat(hist, ","))
    return true
end

function VB.DropSpectator(sender, id)
    local s = VB.current
    if s and s.id == id and s.spectators then s.spectators[sender] = nil end
end

C.handlers.KX = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    if not (ns.Game.watchPending and ns.SameName(ns.Game.watchPending, sender)) then return end
    ns.Game.watchPending = nil
    local s = NewSession({ id = parts[2], mode = "spectate", opp = parts[4] })
    s.source = sender
    s.host, s.guest = parts[3], parts[4]
    s.white = parts[5]
    s.phase = "play"
    s.myCode = nil
    local r = 1
    for entry in string.gmatch(parts[7] or "", "[^,]+") do
        local a, b = string.match(entry, "^([^:]+):([^:]+)$")
        local m, t = Decode(a), Decode(b)
        if m and t then
            s.mine[r], s.theirs[r] = m, t
            r = r + 1
        end
    end
    s.round = r
    s.roundStart = ns.Now()
    VB.current = s
    Fire("VB_STARTED", s)
    Fire("VB_CHANGED", s)
end

C.handlers.KW = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = VB.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2] and s.phase == "play") then return end
    local r = tonumber(parts[3])
    local m, t = Decode(parts[4]), Decode(parts[5])
    if r ~= s.round or not m or not t then return end
    s.mine[r], s.theirs[r] = m, t
    s.round = r + 1
    s.roundStart = ns.Now()
    Fire("VB_ROUND", s, r)
    Fire("VB_CHANGED", s)
end

C.handlers.KE = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local s = VB.current
    if not (s and s.mode == "spectate" and s.source == sender and s.id == parts[2]) then return end
    if VB.Valid(parts[5]) then s.myCode = parts[5] end
    if VB.Valid(parts[6]) then s.theirCode = parts[6] end
    if s.phase ~= "over" then
        s.phase = "over"
        s.round = max(1, s.round - 1)
        s.winner = parts[3] ~= "" and parts[3] or nil
        s.reason = parts[4]
        P.RecordGame({ mode = "spectate", outcome = "none" })
        Fire("VB_OVER", s)
    end
    Fire("VB_CHANGED", s)
end

function VB.StopWatching()
    local s = VB.current
    if s and s.mode == "spectate" and s.phase ~= "over" then
        C.Whisper(s.source, "SX", s.id)
        s.phase = "over"
        Fire("VB_CHANGED", s)
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
    local s = VB.current
    if not s or s.mode == "spectate" then return end
    if s.phase == "set" then
        if not s.ready and now >= s.setDeadline then
            VB.Ready() -- the code as it stands locks the vault
        elseif s.ready and s.mode == "online" and not s.theirSeal and now >= s.setDeadline + VB.SET_TIME then
            Send(s, "KQ", "abort")
            Finish(s, "abort", "abandoned")
        end
    elseif s.phase == "play" then
        local elapsed = now - (s.roundStart or now)
        if not s.mine[s.round] and elapsed >= VB.ROUND_TIME then
            s.missed = s.missed + 1
            if s.missed >= VB.MAX_MISSED then
                if s.mode == "online" then Send(s, "KQ", "time") end
                Finish(s, "loss", "time")
                return
            end
            ns.Print("time's up - a random guess was made for you (" .. s.missed .. "/" .. VB.MAX_MISSED .. " missed turns).")
            VB.Guess(VB.RandomCode(), true)
        elseif s.mode == "online" and s.mine[s.round] and elapsed >= VB.ROUND_TIME * VB.MAX_MISSED + VB.GRACE then
            Finish(s, "win", "abandoned") -- the opponent has gone silent
        end
    elseif s.phase == "over" and s.verifyDeadline and now >= s.verifyDeadline then
        s.verifyDeadline = nil
        if not s.stated then
            s.outcome = "disputed"
            s.cheat = "they never revealed their vault code"
            s.stated = true
            Statement(s, Result(s, "win"))
            ns.Print("|cffff4030" .. ns.ShortName(s.opp) .. " never revealed their vault code - this game is disputed and will not count.|r")
        end
        Fire("VB_CHANGED", s)
    end
end)

function VB.TimeLeft()
    local s = VB.current
    if not s then return 0 end
    if s.phase == "set" then return max(0, s.setDeadline - ns.Now()) end
    if s.phase == "play" then return max(0, VB.ROUND_TIME - (ns.Now() - (s.roundStart or ns.Now()))) end
    return 0
end
