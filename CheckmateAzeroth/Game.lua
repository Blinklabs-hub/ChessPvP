-- Checkmate: Azeroth - game sessions - online play, computer and pass-and-play games, clocks,
-- challenges, matchmaking, spectating and the lobby/ladder announcements.
local _, ns = ...

local G = {}
ns.Game = G

local E, AI, P, C, D = ns.Engine, ns.AI, ns.Profile, ns.Comm, ns.Data
local floor, max, abs = math.floor, math.max, math.abs

G.current = nil -- the game shown on the board (may be finished)
G.incoming = {} -- [gameId] = challenge received
G.outgoing = nil -- challenge we sent
G.seek = nil -- matchmaking request
G.watchPending = nil -- player we asked to spectate

local FLAG_GRACE = 12 -- seconds past zero before claiming a win on time (covers lag)
local INVITE_TIMEOUT = 60
local MAX_SPECTATORS = 5
local VALID_RESULT = { ["1-0"] = true, ["0-1"] = true, ["1/2"] = true, ["*"] = true }

local unacked = {} -- [gameId:seq] = { target, text, next, tries }

------------------------------------------------------------------------
-- Game object
------------------------------------------------------------------------
local function NewGame(o)
    local g = {
        id = o.id or ns.NewId(),
        mode = o.mode, -- "online" | "ai" | "local" | "spectate"
        white = o.white, black = o.black, -- display / full names
        wr = o.wr, br = o.br, wt = o.wt, bt = o.bt, -- ratings and title ids
        myColor = o.myColor, -- 1 white, -1 black, nil when not a participant
        opp = o.opp, -- opponent's full name (online)
        source = o.source, -- who relays the game to us (spectate)
        rated = o.rated and true or false,
        base = o.base or 0, inc = o.inc or 0,
        aiLevel = o.aiLevel,
        pos = E.New(),
        moves = {}, san = {},
        state = "active",
        seq = o.seq or 0, seen = {},
        spectators = {}, spectatorCount = 0,
        lastPiece = {}, knightPromo = {},
    }
    g.timed = g.base > 0
    g.clock = { [1] = g.base, [-1] = g.base }
    g.turnT = ns.Now()
    g.turnS = ns.ServerTime()
    return g
end

local function StartTurn(g)
    g.turnT = ns.Now()
    g.turnS = ns.ServerTime()
end

-- Seconds left for a colour, counting down live for the side to move.
function G.Remaining(g, color)
    if not g.timed then return 0 end
    if g.state == "active" and g.pos.turn == color then
        return g.clock[color] - (ns.Now() - g.turnT)
    end
    return g.clock[color]
end

local function Persist(g)
    local p = P.me
    if not p then return end
    if g.state ~= "active" or g.mode == "spectate" then
        if p.active and p.active.id == g.id then p.active = nil end
        return
    end
    local moves = {}
    for i = 1, #g.moves do moves[i] = g.moves[i] end
    p.active = {
        id = g.id, mode = g.mode, white = g.white, black = g.black,
        wr = g.wr, br = g.br, wt = g.wt, bt = g.bt,
        myColor = g.myColor, opp = g.opp, rated = g.rated, base = g.base, inc = g.inc,
        aiLevel = g.aiLevel, moves = moves, seq = g.seq,
        clockW = g.clock[1], clockB = g.clock[-1], turnS = g.turnS,
    }
end

-- Applies a coordinate move to the game. Returns ok, wasCapture.
local function Apply(g, uci)
    local pos = g.pos
    local legal = E.GenLegal(pos)
    local m = E.FindMove(pos, uci, legal)
    if not m then return false end
    local mover = pos.turn
    local from, to, promo = E.MFrom(m), E.MTo(m), E.MPromo(m)
    local piece = abs(pos.b[from])
    local flag = E.MFlag(m)
    local victim = (flag == 1) and -mover or pos.b[to] -- en passant takes a pawn
    local capture = victim ~= 0
    local san = E.ToSAN(pos, m, legal)
    E.Play(pos, m)
    -- What happened, for animations and the captured-pieces tray.
    g.last = {
        from = from, to = to, mover = mover, piece = piece * mover,
        victim = capture and victim or 0,
        victimSq = (flag == 1) and (to - 10 * mover) or to,
        castle = (flag == 2 or flag == 3) and flag or nil,
        promo = promo ~= 0 and promo or nil,
    }
    if capture then
        g.captures = g.captures or { [1] = {}, [-1] = {} }
        table.insert(g.captures[mover], abs(victim))
    end
    g.moves[#g.moves + 1] = uci
    g.san[#g.san + 1] = san
    g.lastFrom, g.lastTo = from, to
    g.lastPiece[mover] = (promo ~= 0) and promo or piece
    if promo == 2 then g.knightPromo[mover] = true end
    g.drawOffer = nil
    g.status = E.Status(pos)
    return true, capture
end

------------------------------------------------------------------------
-- Reliable whispers (acknowledged, resent until confirmed)
------------------------------------------------------------------------
local function Reliable(g, cmd, ...)
    g.seq = g.seq + 1
    local text = ns.Join(cmd, g.id, g.seq, ...)
    unacked[g.id .. ":" .. g.seq] = { target = g.opp, text = text, next = ns.Now() + 4, tries = 0 }
    C.SendRaw("WHISPER", g.opp, text)
    Persist(g) -- keeps the sequence number unique across a UI reload
end

-- Acknowledges a reliable message and returns the game if it should be processed.
local function Accept(sender, parts)
    local gid, seq = parts[2], tonumber(parts[3])
    if not gid or not seq then return nil end
    local g = G.current
    if g and g.id == gid and g.mode == "online" and g.opp == sender then
        g.acPending = nil -- any game message proves the game started on their side
        C.Whisper(sender, "AK", gid, seq)
        if g.state ~= "active" then
            -- They still think the game is running (messages crossed): tell them how it ended.
            C.Whisper(sender, "EN", gid, g.result or "*", g.reason or "abort")
            return nil
        end
        if g.seen[seq] then return nil end
        g.seen[seq] = true
        return g
    end
    local rec = P.me.recent[gid]
    if rec and rec.opp == sender then C.Whisper(sender, "AK", gid, seq) end
    return nil
end

C.handlers.AK = function(sender, dist, parts)
    if dist ~= "WHISPER" or not parts[2] or not parts[3] then return end
    local key = parts[2] .. ":" .. parts[3]
    local u = unacked[key]
    if u and u.target == sender then unacked[key] = nil end
end

------------------------------------------------------------------------
-- Lobby / ladder announcements
------------------------------------------------------------------------
local lastAnnounce = -100
local nextAnnounce = 0
local announceQueued = false

local function MyStatus()
    local g = G.current
    if g and g.state == "active" and g.mode == "online" then return "g", g.opp end
    if G.seek then return G.seek.rated and "r" or "c", "" end
    if ns.db.settings.dnd then return "d", "" end
    return "i", ""
end

function G.Announce(force)
    if not C.Joined() or not P.me then return end
    local now = ns.Now()
    if not force and now - lastAnnounce < 15 then
        if not announceQueued then
            announceQueued = true
            ns.After(15 - (now - lastAnnounce) + 0.5, function()
                announceQueued = false
                G.Announce(true)
            end)
        end
        return
    end
    lastAnnounce = now
    nextAnnounce = now + 240 + math.random(0, 60)
    local p = P.me
    local status, opp = MyStatus()
    local char, guild = ns.Assets.PackChar(ns.Assets.MyCharInfo())
    -- While in a battle, what kind it is (for the Live Battles tab).
    local cur, battle = G.current, ""
    if status == "g" and cur then battle = table.concat({ cur.rated and "r" or "c", cur.base, cur.inc, #cur.moves }, ",") end
    C.Broadcast("PF", ns.PROTO, p.rating, p.w, p.l, p.d, P.MyTitleId(), P.Points(p), status, opp or "", ns.Assets.MyFaction(),
        char, guild, battle)
end

C.handlers.PF = function(sender, dist, parts)
    if dist ~= "CHANNEL" then return end
    local rating, w, l, d = tonumber(parts[3]), tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6])
    local title, points, status, opp = parts[7] or "", tonumber(parts[8]) or 0, parts[9] or "i", parts[10]
    if not P.UpdatePlayer(sender, rating, w, l, d, title, points) then return end
    local faction = parts[11]
    if faction == "Horde" or faction == "Alliance" then P.players[sender].f = faction end
    local ch = ns.Assets.UnpackChar(parts[12], parts[13])
    if ch then P.players[sender].ch = ch end
    if opp == "" then opp = nil end
    P.SetOnline(sender, status, opp)
    local rated, base, inc, moves = string.match(parts[14] or "", "^([rc]),(%d+),(%d+),(%d+)$")
    if rated and opp then
        P.online[sender].battle = { rated = rated == "r", base = tonumber(base), inc = tonumber(inc), moves = tonumber(moves) }
    end
    ns.Fire("CHESS_LOBBY_CHANGED")
end

-- A newcomer asks everyone to announce themselves; replies are spread out over time.
C.handlers.HI = function(sender, dist)
    if dist ~= "CHANNEL" then return end
    local count = 0
    for _ in pairs(P.online) do count = count + 1 end
    local delay = 1 + math.random() * max(20, count / 5)
    ns.After(delay, function()
        if ns.Now() - lastAnnounce > 30 then G.Announce(true) end
    end)
end

C.handlers.BY = function(sender, dist)
    if dist ~= "CHANNEL" then return end
    P.SetOffline(sender)
    ns.Fire("CHESS_LOBBY_CHANGED")
end

ns.On("CHESS_CHANNEL_READY", function()
    ns.After(2, function()
        C.Broadcast("HI")
        G.Announce(true)
    end)
end)

ns.RegisterEvent("PLAYER_LOGOUT", function()
    if C.Joined() then C.Broadcast("BY") end
end)

------------------------------------------------------------------------
-- Finishing a game
------------------------------------------------------------------------
local function Relay(g, ...)
    if g.spectatorCount == 0 then return end
    local text = ns.Join(...)
    for name in pairs(g.spectators) do
        C.SendRaw("WHISPER", name, text)
    end
end

-- result: "1-0", "0-1", "1/2" or "*" (no result).
local function Finish(g, result, reason)
    if g.state ~= "active" then return end
    if g.timed then
        local c = g.pos.turn
        g.clock[c] = max(0, G.Remaining(g, c))
    end
    g.state = "over"
    g.result = result
    g.reason = reason
    g.drawOffer = nil
    g.awaitSync = nil
    g.rejoinDeadline = nil
    if g.mode == "ai" then AI.Cancel() end

    local outcome
    if result ~= "*" and g.myColor then
        if result == "1/2" then
            outcome = "draw"
        elseif (result == "1-0") == (g.myColor == 1) then
            outcome = "win"
        else
            outcome = "loss"
        end
    end
    g.outcome = outcome

    -- Rated result statement for the witnessed ladder (see Ledger.lua).
    if g.mode == "online" and result ~= "*" then
        if g.rated then g.ratingBefore = ns.Ledger.Rating(ns.me) end
        ns.Ledger.StateOwn(g, result)
    end

    if outcome and (g.mode == "online" or g.mode == "ai") then
        local n = #g.moves
        local myMoves = (g.myColor == 1) and floor((n + 1) / 2) or floor(n / 2)
        P.RecordGame({
            mode = g.mode, outcome = outcome, reason = reason, rated = g.rated,
            opp = g.opp, oppRating = (g.myColor == 1) and g.br or g.wr,
            myMoves = myMoves, matePiece = g.lastPiece[g.myColor], knightPromo = g.knightPromo[g.myColor],
            timed = g.timed, myClock = g.clock[g.myColor], aiLevel = g.aiLevel or 0,
        })
    elseif g.mode == "spectate" and result ~= "*" then
        P.RecordGame({ mode = "spectate", outcome = "none" })
    end

    if g.mode == "online" then
        Relay(g, "SE", g.id, result, reason)
        P.me.recent[g.id] = { opp = g.opp, result = result, reason = reason, at = ns.ServerTime() }
    end
    Persist(g)
    ns.Fire("CHESS_GAME_OVER", g)
    ns.Fire("CHESS_GAME_CHANGED", g)
    G.Announce()
end

local function FinishByStatus(g)
    local status = g.status
    if not status then return false end
    if status == "checkmate" then
        Finish(g, (g.pos.turn == -1) and "1-0" or "0-1", "checkmate")
    else
        Finish(g, "1/2", status)
    end
    return true
end

local AfterMove -- forward declaration

local function AIThink(g)
    AI.Start(g.pos, g.aiLevel, function(move)
        if G.current ~= g or g.state ~= "active" or not move then return end
        local ok, capture = Apply(g, E.MoveToUCI(move))
        if ok then
            StartTurn(g)
            AfterMove(g, capture)
        end
    end)
end

AfterMove = function(g, capture)
    Persist(g)
    ns.Fire("CHESS_GAME_MOVED", g, capture, E.InCheck(g.pos))
    if not FinishByStatus(g) then
        if g.mode == "ai" and g.pos.turn ~= g.myColor then AIThink(g) end
    end
    ns.Fire("CHESS_GAME_CHANGED", g)
end

local function Begin(g)
    local old = G.current
    if old and old.state == "active" then
        if old.mode == "ai" then AI.Cancel() end
        local sameWatch = g.mode == "spectate" and g.source == old.source and g.id == old.id
        if old.mode == "spectate" and old.source and not sameWatch then C.Whisper(old.source, "SX", old.id) end
        old.state = "over"
        old.result, old.reason = "*", "abort"
        Persist(old)
    end
    G.current = g
    G.watchPending = nil
    Persist(g)
    if g.mode == "online" then ns.Ledger.StateOwn(g, nil) end
    ns.Fire("CHESS_GAME_STARTED", g)
    ns.Fire("CHESS_GAME_CHANGED", g)
    if g.mode == "ai" and g.pos.turn ~= g.myColor then AIThink(g) end
    G.Announce(true)
end

local function OnlineBusy()
    local g = G.current
    return g and g.state == "active" and g.mode == "online"
end

------------------------------------------------------------------------
-- Local actions
------------------------------------------------------------------------
-- Plays a move for the local player. uci is e.g. "e2e4" or "e7e8q".
function G.Move(uci)
    local g = G.current
    if not g or g.state ~= "active" or g.mode == "spectate" then return false end
    local mover = g.pos.turn
    if g.mode ~= "local" and mover ~= g.myColor then return false end
    local rem = 0
    if g.timed then rem = max(0, G.Remaining(g, mover)) + g.inc end
    local ok, capture = Apply(g, uci)
    if not ok then return false end
    if g.timed then g.clock[mover] = rem end
    StartTurn(g)
    if g.mode == "online" then
        Reliable(g, "MV", #g.moves, uci, floor(rem * 10))
        Relay(g, "SM", g.id, #g.moves, uci, floor(g.clock[1] * 10), floor(g.clock[-1] * 10))
    end
    AfterMove(g, capture)
    return true
end

function G.CanMove()
    local g = G.current
    if not g or g.state ~= "active" or g.mode == "spectate" then return false end
    return g.mode == "local" or g.pos.turn == g.myColor
end

function G.StartAI(level, color)
    if OnlineBusy() then
        ns.Print("finish your current game first.")
        return
    end
    if color ~= 1 and color ~= -1 then color = (math.random(1, 2) == 1) and 1 or -1 end
    local botName = "Computer (" .. AI.LEVELS[level].name .. ")"
    local me = ns.me
    Begin(NewGame({
        mode = "ai", aiLevel = level, myColor = color,
        white = (color == 1) and me or botName, black = (color == 1) and botName or me,
    }))
end


function G.Resign()
    local g = G.current
    if not g or g.state ~= "active" then return end
    if g.mode == "spectate" then
        G.StopWatching()
    elseif g.mode == "online" then
        if #g.moves < 2 then
            Reliable(g, "AB")
            Finish(g, "*", "abort")
        else
            Reliable(g, "RS")
            Finish(g, (g.myColor == 1) and "0-1" or "1-0", "resign")
        end
    elseif g.mode == "ai" then
        Finish(g, (g.myColor == 1) and "0-1" or "1-0", "resign")
    else
        Finish(g, (g.pos.turn == 1) and "0-1" or "1-0", "resign")
    end
end

-- Offers a draw, or accepts the opponent's pending offer.
function G.OfferDraw()
    local g = G.current
    if not g or g.state ~= "active" then return end
    if g.mode == "online" then
        if g.drawOffer == -g.myColor then
            Reliable(g, "DA")
            Finish(g, "1/2", "agreement")
        elseif g.drawOffer ~= g.myColor then
            g.drawOffer = g.myColor
            g.myOfferPly = #g.moves
            Reliable(g, "DO")
            ns.Fire("CHESS_GAME_CHANGED", g)
        end
    elseif g.mode == "ai" then
        ns.Print("the computer declines your draw offer.")
    elseif g.mode == "local" then
        Finish(g, "1/2", "agreement")
    end
end

function G.DeclineDraw()
    local g = G.current
    if g and g.state == "active" and g.mode == "online" and g.drawOffer == -g.myColor then
        g.drawOffer = nil
        Reliable(g, "DD")
        ns.Fire("CHESS_GAME_CHANGED", g)
    end
end

------------------------------------------------------------------------
-- Challenges
------------------------------------------------------------------------
local function Capitalise(word)
    if string.match(word, "^%a+$") then -- plain ASCII only; leave accented names alone
        return string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2))
    end
    return word
end

-- Turns whatever the player typed into an identity:
--   retail  "bob" / "Bob-Realm"                    -> "Bob-Realm"
--   Forever "just keepingcalm" / "Just-Keepingcalm" -> "Just Keepingcalm"
local function NormalizeName(name)
    local full = ns.FullName(name)
    if not full then return nil end
    if ns.isForever then
        return (string.gsub(full, "%S+", Capitalise))
    end
    local n, r = string.match(full, "^([^-]+)-(.*)$")
    return Capitalise(n) .. "-" .. r
end

local SameName = ns.SameName

-- opts: base, inc, rated, color ("w", "b" or "r" for random), q (matchmaking)
function G.Invite(name, opts)
    opts = opts or {}
    name = NormalizeName(name or "")
    if not name then return end
    if SameName(name, ns.me) then
        ns.Print("you cannot challenge yourself. Try Pass & Play instead.")
        return
    end
    if OnlineBusy() then
        ns.Print("finish your current game first.")
        return
    end
    if G.outgoing then G.CancelInvite() end
    local s = ns.db.settings
    local tc = D.TIME_CONTROLS[s.tc or 4] or D.TIME_CONTROLS[4]
    local base = opts.base or tc.base
    local inc = opts.inc or tc.inc
    local rated = opts.rated
    if rated == nil then rated = s.rated ~= false end
    if base == 0 then rated = false end -- rated games always use a clock
    if rated and not opts.q and not G.LeagueOK(name) then
        ns.Print(string.format("%s plays in the %s league - rated battles are only possible within one league of yours. Sending a casual challenge instead.",
            ns.ShortName(name), G.LeagueName(name)))
        rated = false
    end
    local color = opts.color or s.color or "r"
    local myColor = (color == "w") and 1 or (color == "b") and -1 or ((math.random(1, 2) == 1) and 1 or -1)
    local id = ns.NewId()
    G.outgoing = {
        id = id, to = name, base = base, inc = inc, rated = rated, myColor = myColor,
        expires = ns.Now() + INVITE_TIMEOUT, q = opts.q,
    }
    C.Whisper(name, "IV", id, base, inc, rated and 1 or 0, (myColor == 1) and "w" or "b",
        P.me.rating, ns.PROTO, opts.q and 1 or 0, P.MyTitleId())
    if not opts.q then
        ns.Print("challenge sent to " .. ns.ShortName(name) .. ".")
    end
    ns.Fire("CHESS_INVITE_CHANGED")
end

function G.CancelInvite()
    local o = G.outgoing
    if not o then return end
    G.outgoing = nil
    C.Whisper(o.to, "CX", o.id)
    ns.Fire("CHESS_INVITE_CHANGED")
end

local function Decline(inv, reason)
    G.incoming[inv.id] = nil
    C.Whisper(inv.from, "DC", inv.id, reason or "declined")
    ns.Fire("CHESS_INVITE_CHANGED")
end

local function AcceptInvite(inv)
    G.incoming[inv.id] = nil
    if OnlineBusy() then
        C.Whisper(inv.from, "DC", inv.id, "busy")
        return
    end
    if G.outgoing then G.CancelInvite() end
    G.seek = nil
    local myColor = (inv.theirColor == "w") and -1 or 1
    local p = P.me
    local g = NewGame({
        id = inv.id, mode = "online", opp = inv.from, myColor = myColor,
        rated = inv.rated, base = inv.base, inc = inv.inc,
        white = (myColor == 1) and ns.me or inv.from, black = (myColor == 1) and inv.from or ns.me,
        wr = (myColor == 1) and p.rating or inv.rating, br = (myColor == 1) and inv.rating or p.rating,
        wt = (myColor == 1) and P.MyTitleId() or inv.title, bt = (myColor == 1) and inv.title or P.MyTitleId(),
    })
    C.Whisper(inv.from, "AC", inv.id, p.rating, P.MyTitleId())
    -- Resent until the challenger confirms (GA), in case the message is lost.
    g.acPending = { next = ns.Now() + 3, tries = 0, text = ns.Join("AC", inv.id, p.rating, P.MyTitleId()) }
    -- Any other pending challenges are declined.
    for _, other in pairs(G.incoming) do
        C.Whisper(other.from, "DC", other.id, "busy")
    end
    G.incoming = {}
    Begin(g)
    ns.Fire("CHESS_INVITE_CHANGED")
end

function G.AnswerInvite(id, accept)
    local inv = G.incoming[id]
    if not inv then return end
    if accept then AcceptInvite(inv) else Decline(inv) end
end

function G.LatestInvite()
    local best
    for _, inv in pairs(G.incoming) do
        if not best or inv.expires > best.expires then best = inv end
    end
    return best
end

function G.AnswerLatest(accept)
    local inv = G.LatestInvite()
    if not inv then
        ns.Print("there is no pending challenge.")
        return
    end
    G.AnswerInvite(inv.id, accept)
end

C.handlers.IV = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local gid = parts[2]
    local base, inc = tonumber(parts[3]), tonumber(parts[4])
    local rated = parts[5] == "1"
    local color = parts[6]
    local rating = tonumber(parts[7])
    local proto = tonumber(parts[8])
    local q = parts[9] == "1"
    if not gid or not string.match(gid, "^%w+$") or #gid > 12 then return end
    if not base or base < 0 or base > 7200 or not inc or inc < 0 or inc > 60 then return end
    if not rating or rating < 100 or rating > 3500 then return end
    if color ~= "w" and color ~= "b" then return end
    if proto ~= ns.PROTO then
        C.Whisper(sender, "DC", gid, "version")
        return
    end
    if OnlineBusy() then
        C.Whisper(sender, "DC", gid, "busy")
        return
    end
    if base == 0 then rated = false end
    local inv = {
        id = gid, from = sender, base = base, inc = inc, rated = rated,
        theirColor = color, rating = floor(rating), title = parts[10] or "",
        expires = ns.Now() + INVITE_TIMEOUT,
    }
    if q then
        local s = G.seek
        if s and G.SeekCompatible(s, sender, base, inc, rated, false) then
            AcceptInvite(inv)
        else
            C.Whisper(sender, "DC", gid, "noseek")
        end
        return
    end
    if rated and not G.LeagueOK(sender) then
        C.Whisper(sender, "DC", gid, "league")
        return
    end
    if ns.db.settings.dnd then
        C.Whisper(sender, "DC", gid, "dnd")
        return
    end
    G.incoming[gid] = inv
    ns.Sound("invite")
    ns.Fire("CHESS_INVITE", inv)
    ns.Fire("CHESS_INVITE_CHANGED")
end

C.handlers.AC = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local o = G.outgoing
    local gid = parts[2]
    local cur = G.current
    if cur and cur.id == gid and cur.mode == "online" and cur.opp == sender then
        C.Whisper(sender, "GA", gid) -- a repeated accept: confirm again
        return
    end
    if not o or o.id ~= gid or not SameName(o.to, sender) or OnlineBusy() then
        -- We are no longer waiting for this answer: tell them the game is off.
        if gid then C.Whisper(sender, "NG", gid) end
        return
    end
    local rating = tonumber(parts[3]) or D.START_RATING
    if rating < 100 or rating > 3500 then rating = D.START_RATING end
    rating = floor(rating)
    local title = parts[4] or ""
    G.outgoing = nil
    G.seek = nil
    local p = P.me
    local myColor = o.myColor
    local g = NewGame({
        id = o.id, mode = "online", opp = sender, myColor = myColor,
        rated = o.rated, base = o.base, inc = o.inc,
        white = (myColor == 1) and ns.me or sender, black = (myColor == 1) and sender or ns.me,
        wr = (myColor == 1) and p.rating or rating, br = (myColor == 1) and rating or p.rating,
        wt = (myColor == 1) and P.MyTitleId() or title, bt = (myColor == 1) and title or P.MyTitleId(),
    })
    for _, other in pairs(G.incoming) do
        C.Whisper(other.from, "DC", other.id, "busy")
    end
    G.incoming = {}
    C.Whisper(sender, "GA", gid)
    Begin(g)
    ns.Fire("CHESS_INVITE_CHANGED")
end

-- The challenger confirms that the game has started on their side.
C.handlers.GA = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if g and g.id == parts[2] and g.opp == sender then g.acPending = nil end
end

local DECLINE_TEXT = {
    declined = "declined your challenge.",
    busy = "is already in a game.",
    dnd = "is not accepting challenges right now.",
    version = "is using a different version of Checkmate: Azeroth.",
    league = "is too far from your league for a rated battle. Try a casual one.",
}

C.handlers.DC = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local o = G.outgoing
    if not o or o.id ~= parts[2] or not SameName(o.to, sender) then return end
    G.outgoing = nil
    if not o.q then
        ns.Print(ns.ShortName(sender) .. " " .. (DECLINE_TEXT[parts[3] or ""] or DECLINE_TEXT.declined))
    end
    ns.Fire("CHESS_INVITE_CHANGED")
end

C.handlers.CX = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local inv = G.incoming[parts[2] or ""]
    if inv and inv.from == sender then
        G.incoming[inv.id] = nil
        ns.Fire("CHESS_INVITE_CHANGED")
    end
end

ns.On("CHESS_PEER_OFFLINE", function(name)
    local o = G.outgoing
    if o and SameName(o.to, name) then
        G.outgoing = nil
        if not o.q then ns.Print(ns.ShortName(o.to) .. " is not online.") end
        ns.Fire("CHESS_INVITE_CHANGED")
    end
    if G.watchPending and SameName(G.watchPending, name) then G.watchPending = nil end
end)

------------------------------------------------------------------------
-- Matchmaking
------------------------------------------------------------------------
-- Joins the rated or casual queue. any = true accepts any time control.
function G.StartSeek(base, inc, rated, any)
    if OnlineBusy() then
        ns.Print("finish your current game first.")
        return
    end
    if not C.Joined() then
        ns.Print("still connecting to the chess network - try again in a few seconds.")
        return
    end
    if base == 0 and not any then rated = false end
    G.seek = { base = base, inc = inc, rated = rated and true or false, any = any and true or false, next = 0, since = ns.Now() }
    G.Announce()
    ns.Fire("CHESS_INVITE_CHANGED")
end

function G.StopSeek()
    if not G.seek then return end
    G.seek = nil
    G.Announce()
    ns.Fire("CHESS_INVITE_CHANGED")
end

------------------------------------------------------------------------
-- Leagues (rated battles only within one league; provisional players play anyone)
------------------------------------------------------------------------
-- League index of a player from the witnessed ledger, or 0 while provisional.
function G.LeagueIndex(name)
    local v = ns.Ledger.Get(name)
    if not v or v.games < D.PLACEMENT_GAMES then return 0 end
    return D.LeagueFor(v.r)
end

function G.LeagueName(name)
    local i = G.LeagueIndex(name)
    return i == 0 and "Unranked" or D.LEAGUES[i].name
end

function G.LeagueOK(name)
    local a, b = G.LeagueIndex(ns.me), G.LeagueIndex(name)
    return a == 0 or b == 0 or math.abs(a - b) <= 1
end

-- Can my queue entry s be paired with an opponent's (base, inc, rated, any)?
-- Returns ok, base, inc (the time control to use).
function G.SeekCompatible(s, sender, base, inc, rated, theirAny)
    if s.rated ~= rated then return false end
    if rated and not G.LeagueOK(sender) then return false end
    if not s.any and not theirAny then
        if s.base ~= base or s.inc ~= inc then return false end
        return true, base, inc
    end
    if not s.any then return true, s.base, s.inc end
    if not theirAny then return true, base, inc end
    local tc = D.TIME_CONTROLS[4] -- both said "any": Rapid 10+0
    return true, tc.base, tc.inc
end

C.handlers.SK = function(sender, dist, parts)
    if dist ~= "CHANNEL" then return end
    local s = G.seek
    if not s or G.outgoing or OnlineBusy() then return end
    local base, inc, rated, any = tonumber(parts[2]), tonumber(parts[3]), parts[4] == "1", parts[5] == "1"
    if not base or not inc then return end
    local ok, b, i = G.SeekCompatible(s, sender, base, inc, rated, any)
    if not ok then return end
    -- Both sides see each other's request; the alphabetically first name sends the challenge.
    if ns.me < sender then
        G.Invite(sender, { base = b, inc = i, rated = s.rated, color = "r", q = true })
    end
end

------------------------------------------------------------------------
-- Profiles: ask a player for the things only they know (faction, feats, title).
--   PQ                         -> PR;faction;title;feat indexes (comma separated)
------------------------------------------------------------------------
function G.RequestProfile(name)
    if ns.SameName(name, ns.me) then return end
    C.Whisper(name, "PQ")
end

C.handlers.PQ = function(sender, dist)
    if dist ~= "WHISPER" then return end
    local list = {}
    for i = 1, #D.BADGES do
        if P.me.badges[D.BADGES[i].id] then list[#list + 1] = i end
    end
    local char, guild = ns.Assets.PackChar(ns.Assets.MyCharInfo())
    C.Whisper(sender, "PR", ns.Assets.MyFaction(), P.MyTitleId(), table.concat(list, ","), char, guild)
end

C.handlers.PR = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local e = P.players[sender]
    if not e then
        e = { r = D.START_RATING, w = 0, l = 0, d = 0, t = "", seen = ns.ServerTime() }
        P.players[sender] = e
    end
    if parts[2] == "Horde" or parts[2] == "Alliance" then e.f = parts[2] end
    if parts[3] and #parts[3] <= 24 then e.t = parts[3] end
    local feats = {}
    for idx in string.gmatch(parts[4] or "", "%d+") do
        local b = D.BADGES[tonumber(idx)]
        if b then feats[#feats + 1] = b.id end
    end
    e.feats = feats
    local ch = ns.Assets.UnpackChar(parts[5], parts[6])
    if ch then e.ch = ch end
    e.profileAt = ns.ServerTime()
    ns.Fire("CHESS_PROFILE_INFO", sender)
end

------------------------------------------------------------------------
-- Online game messages
------------------------------------------------------------------------
local function RequestSync(g)
    local now = ns.Now()
    if g.lastSyncRequest and now - g.lastSyncRequest < 5 then return end
    g.lastSyncRequest = now
    g.awaitSync = true
    C.Whisper(g.opp, "RJ", g.id, #g.moves)
end

C.handlers.MV = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = Accept(sender, parts)
    if not g or g.state ~= "active" then return end
    local ply, uci, rem = tonumber(parts[4]), parts[5], tonumber(parts[6])
    if not ply or not uci then return end
    local mover = -g.myColor
    if ply == #g.moves + 1 and g.pos.turn == mover then
        local allowance = g.clock[mover] + g.inc
        local ok, capture = Apply(g, uci)
        if not ok then
            RequestSync(g)
            return
        end
        if g.timed then
            local left = (rem or 0) / 10
            if left > allowance then left = allowance end
            if left < 0 then left = 0 end
            g.clock[mover] = left
        end
        StartTurn(g)
        Relay(g, "SM", g.id, #g.moves, uci, floor(g.clock[1] * 10), floor(g.clock[-1] * 10))
        AfterMove(g, capture)
    elseif ply > #g.moves + 1 then
        g.seen[tonumber(parts[3])] = nil -- let it be delivered again after the resync
        RequestSync(g)
    end
end

C.handlers.RS = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = Accept(sender, parts)
    if g then Finish(g, (g.myColor == 1) and "1-0" or "0-1", "resign") end
end

C.handlers.AB = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = Accept(sender, parts)
    if not g then return end
    if #g.moves < 2 then
        Finish(g, "*", "abort")
    else
        Finish(g, (g.myColor == 1) and "1-0" or "0-1", "resign")
    end
end

C.handlers.DO = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = Accept(sender, parts)
    if not g or g.state ~= "active" then return end
    g.drawOffer = -g.myColor
    ns.Print(ns.ShortName(sender) .. " offers a draw.")
    ns.Fire("CHESS_GAME_CHANGED", g)
end

C.handlers.DA = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = Accept(sender, parts)
    if g and g.state == "active" and g.drawOffer == g.myColor then
        Finish(g, "1/2", "agreement")
    end
end

C.handlers.DD = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = Accept(sender, parts)
    if g and g.state == "active" and g.drawOffer == g.myColor then
        g.drawOffer = nil
        ns.Print(ns.ShortName(sender) .. " declined the draw.")
        ns.Fire("CHESS_GAME_CHANGED", g)
    end
end

-- The opponent reports running out of time.
C.handlers.TO = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = Accept(sender, parts)
    if g and g.timed then Finish(g, (g.myColor == 1) and "1-0" or "0-1", "time") end
end

-- The opponent claims that our clock ran out.
C.handlers.FL = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = Accept(sender, parts)
    if g and g.timed and (g.pos.turn == g.myColor or G.Remaining(g, g.myColor) < 30) then
        Finish(g, (g.myColor == 1) and "0-1" or "1-0", "time")
    end
end

------------------------------------------------------------------------
-- Rejoining after a reload or disconnect
------------------------------------------------------------------------
local function SendMoveList(target, g, fromPly)
    local i = fromPly
    local n = #g.moves
    while i <= n do
        local last = math.min(n, i + 34)
        local chunk = {}
        for k = i, last do chunk[#chunk + 1] = g.moves[k] end
        C.Whisper(target, "ML", g.id, i, table.concat(chunk, ","))
        i = last + 1
    end
end

C.handlers.RJ = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local gid = parts[2]
    local theirPly = tonumber(parts[3]) or 0
    if not gid then return end
    local g = G.current
    if g and g.id == gid and g.mode == "online" and g.opp == sender then
        if g.state == "active" then
            C.Whisper(sender, "ST", gid, floor(max(0, G.Remaining(g, 1)) * 10), floor(max(0, G.Remaining(g, -1)) * 10), #g.moves)
            if theirPly < #g.moves then SendMoveList(sender, g, theirPly + 1) end
        else
            C.Whisper(sender, "EN", gid, g.result or "*", g.reason or "abort")
        end
        return
    end
    local rec = P.me.recent[gid]
    if rec and rec.opp == sender then
        C.Whisper(sender, "EN", gid, rec.result, rec.reason)
    else
        C.Whisper(sender, "NG", gid)
    end
end

C.handlers.ST = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if not g or g.id ~= parts[2] or g.mode ~= "online" or g.opp ~= sender or g.state ~= "active" then return end
    if not g.awaitSync then return end
    local wc, bc, ply = tonumber(parts[3]), tonumber(parts[4]), tonumber(parts[5])
    if not wc or not bc or not ply then return end
    g.awaitSync = nil
    g.rejoinDeadline = nil
    if g.timed then
        local theirs = -g.myColor
        local mine = g.myColor
        local reported = { [1] = wc / 10, [-1] = bc / 10 }
        -- Never accept more time for the opponent than we already knew about.
        if reported[theirs] < g.clock[theirs] then g.clock[theirs] = reported[theirs] end
        if ply >= #g.moves and reported[mine] < g.clock[mine] then g.clock[mine] = reported[mine] end
        StartTurn(g)
    end
    -- They are missing our latest move(s): send again.
    for i = ply + 1, #g.moves do
        Reliable(g, "MV", i, g.moves[i], floor(g.clock[g.myColor] * 10))
    end
    ns.Fire("CHESS_GAME_CHANGED", g)
end

C.handlers.ML = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if not g or g.id ~= parts[2] or g.state ~= "active" then return end
    local trusted = (g.mode == "online" and g.opp == sender) or (g.mode == "spectate" and g.source == sender)
    if not trusted then return end
    local ply = tonumber(parts[3])
    if not ply or not parts[4] then return end
    local list = ns.Split(parts[4], ",")
    local applied = false
    for i = 1, #list do
        if ply == #g.moves + 1 then
            -- In our own game only the opponent's moves can be missing.
            if g.mode == "online" and g.pos.turn == g.myColor then break end
            if not Apply(g, list[i]) then break end
            applied = true
        end
        ply = ply + 1
    end
    if applied then
        StartTurn(g)
        AfterMove(g, false)
    end
end

C.handlers.EN = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if not g or g.id ~= parts[2] or g.mode ~= "online" or g.opp ~= sender or g.state ~= "active" then return end
    local result, reason = parts[3], parts[4] or "abort"
    if not VALID_RESULT[result] or not D.REASON_TEXT[reason] then return end
    if not g.awaitSync then
        -- Unrequested: only believe results we can check or that do not hurt us.
        local iWin = (result == "1-0") == (g.myColor == 1) and result ~= "1/2" and result ~= "*"
        local agreedDraw = result == "1/2" and reason == "agreement" and g.myOfferPly and (#g.moves - g.myOfferPly) <= 1
        local flagged = reason == "time" and g.timed and G.Remaining(g, g.myColor) < 30
        if not (iWin or agreedDraw or flagged) then return end
    end
    Finish(g, result, reason)
end

C.handlers.NG = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if not g or g.id ~= parts[2] or g.mode ~= "online" or g.opp ~= sender or g.state ~= "active" then return end
    if g.awaitSync or #g.moves == 0 then
        Finish(g, "*", "abort")
    end
end

local function Restore()
    local s = P.me.active
    if type(s) ~= "table" or type(s.moves) ~= "table" then
        P.me.active = nil
        return
    end
    local g = NewGame(s)
    for i = 1, #s.moves do
        if not Apply(g, s.moves[i]) then
            P.me.active = nil
            return
        end
    end
    if g.status then -- should not happen: finished games are never saved as active
        P.me.active = nil
        return
    end
    g.clock[1] = s.clockW or g.base
    g.clock[-1] = s.clockB or g.base
    local elapsed = max(0, ns.ServerTime() - (s.turnS or ns.ServerTime()))
    if g.timed then
        local c = g.pos.turn
        g.clock[c] = g.clock[c] - elapsed
    end
    g.turnT = ns.Now()
    g.turnS = ns.ServerTime()
    G.current = g
    if g.mode == "online" then
        if g.timed and g.pos.turn == g.myColor and g.clock[g.myColor] <= 0 then
            Reliable(g, "TO")
            Finish(g, (g.myColor == 1) and "0-1" or "1-0", "time")
            return
        end
        g.awaitSync = true
        g.rejoinDeadline = ns.Now() + 25
        C.Whisper(g.opp, "RJ", g.id, #g.moves)
        ns.Print("resuming your game against " .. ns.ShortName(g.opp) .. ".")
    elseif g.mode == "ai" and g.pos.turn ~= g.myColor then
        AIThink(g)
    end
    ns.Fire("CHESS_GAME_CHANGED", g)
end

------------------------------------------------------------------------
-- Spectating
------------------------------------------------------------------------
function G.Watch(name)
    name = ns.FullName(name)
    if not name or SameName(name, ns.me) then return end
    local g = G.current
    if g and g.state == "active" and g.mode ~= "spectate" then
        ns.Print("finish your current game before watching another.")
        return
    end
    G.watchPending = name
    C.Whisper(name, "SP")
end

function G.StopWatching()
    local g = G.current
    if g and g.mode == "spectate" and g.state == "active" then
        C.Whisper(g.source, "SX", g.id)
        g.state = "over"
        g.result, g.reason = "*", "abort"
        ns.Fire("CHESS_GAME_CHANGED", g)
    end
end

C.handlers.SP = function(sender, dist)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if not g or g.mode ~= "online" or g.state ~= "active" or not ns.db.settings.allowSpectators then
        C.Whisper(sender, "SN")
        return
    end
    if not g.spectators[sender] then
        if g.spectatorCount >= MAX_SPECTATORS then
            C.Whisper(sender, "SN")
            return
        end
        g.spectators[sender] = true
        g.spectatorCount = g.spectatorCount + 1
    end
    C.Whisper(sender, "SS", g.id, g.white, g.black, g.wr or 0, g.br or 0, g.base, g.inc, g.rated and 1 or 0,
        floor(max(0, G.Remaining(g, 1)) * 10), floor(max(0, G.Remaining(g, -1)) * 10), g.wt or "", g.bt or "")
    SendMoveList(sender, g, 1)
end

C.handlers.SX = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if g and g.id == parts[2] and g.spectators[sender] then
        g.spectators[sender] = nil
        g.spectatorCount = g.spectatorCount - 1
    end
end

C.handlers.SN = function(sender, dist)
    if dist ~= "WHISPER" then return end
    if G.watchPending and SameName(G.watchPending, sender) then
        G.watchPending = nil
        ns.Print(ns.ShortName(sender) .. " has no game you can watch right now.")
    end
end

C.handlers.SS = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local cur = G.current
    local resync = cur and cur.mode == "spectate" and cur.state == "active" and cur.source == sender and cur.id == parts[2]
    if not resync and not (G.watchPending and SameName(G.watchPending, sender)) then return end
    if cur and cur.state == "active" and cur.mode ~= "spectate" then return end
    local gid, white, black = parts[2], parts[3], parts[4]
    local base, inc = tonumber(parts[7]), tonumber(parts[8])
    if not gid or not white or not black or not base or not inc then return end
    local g = NewGame({
        id = gid, mode = "spectate", source = sender, white = white, black = black,
        wr = tonumber(parts[5]), br = tonumber(parts[6]), base = base, inc = inc, rated = parts[9] == "1",
        wt = parts[12], bt = parts[13],
    })
    g.clock[1] = (tonumber(parts[10]) or 0) / 10
    g.clock[-1] = (tonumber(parts[11]) or 0) / 10
    Begin(g)
end

C.handlers.SM = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if not g or g.mode ~= "spectate" or g.source ~= sender or g.id ~= parts[2] or g.state ~= "active" then return end
    local ply, uci = tonumber(parts[3]), parts[4]
    if not ply or not uci then return end
    if ply == #g.moves + 1 then
        local ok, capture = Apply(g, uci)
        if ok then
            g.clock[1] = (tonumber(parts[5]) or 0) / 10
            g.clock[-1] = (tonumber(parts[6]) or 0) / 10
            StartTurn(g)
            AfterMove(g, capture)
        end
    elseif ply > #g.moves + 1 then
        local now = ns.Now()
        if not g.lastSyncRequest or now - g.lastSyncRequest > 5 then
            g.lastSyncRequest = now
            C.Whisper(sender, "SP")
        end
    end
end

C.handlers.SE = function(sender, dist, parts)
    if dist ~= "WHISPER" then return end
    local g = G.current
    if not g or g.mode ~= "spectate" or g.source ~= sender or g.id ~= parts[2] then return end
    local result, reason = parts[3], parts[4] or "abort"
    if not VALID_RESULT[result] or not D.REASON_TEXT[reason] then return end
    Finish(g, result, reason)
end

------------------------------------------------------------------------
-- Periodic work: clocks, resends, timeouts, announcements
------------------------------------------------------------------------
ns.On("CHESS_TICK", function()
    if not P.me then return end
    local now = ns.Now()

    for key, u in pairs(unacked) do
        if now >= u.next then
            u.tries = u.tries + 1
            if u.tries > 15 then
                unacked[key] = nil
            else
                u.next = now + 4
                C.SendRaw("WHISPER", u.target, u.text)
            end
        end
    end

    local g = G.current
    local ac = g and g.state == "active" and g.mode == "online" and g.acPending
    if ac and now >= ac.next then
        ac.tries = ac.tries + 1
        if ac.tries > 6 then
            -- The challenger never confirmed: the game did not start on their side.
            g.acPending = nil
            Finish(g, "*", "abandoned")
        else
            ac.next = now + 3
            C.SendRaw("WHISPER", g.opp, ac.text)
        end
    end
    if g and g.state == "active" and g.mode == "online" then
        if g.rejoinDeadline and now > g.rejoinDeadline then
            g.rejoinDeadline = nil
            g.awaitSync = nil
            if g.timed and g.pos.turn ~= g.myColor and G.Remaining(g, -g.myColor) <= 0 then
                -- Their clock ran out while we were away and they cannot confirm it.
                Finish(g, "*", "abandoned")
            end
        end
        if g.state == "active" and g.timed and not g.rejoinDeadline then
            if g.pos.turn == g.myColor then
                if G.Remaining(g, g.myColor) <= 0 then
                    Reliable(g, "TO")
                    Finish(g, (g.myColor == 1) and "0-1" or "1-0", "time")
                end
            elseif G.Remaining(g, -g.myColor) <= -FLAG_GRACE then
                Reliable(g, "FL")
                Finish(g, (g.myColor == 1) and "1-0" or "0-1", "time")
            end
        end
    end

    local o = G.outgoing
    if o and now > o.expires then
        G.outgoing = nil
        if not o.q then
            ns.Print("no answer from " .. ns.ShortName(o.to) .. " (they may not have Checkmate: Azeroth installed).")
        end
        ns.Fire("CHESS_INVITE_CHANGED")
    end
    local expired = false
    for id, inv in pairs(G.incoming) do
        if now > inv.expires then
            G.incoming[id] = nil
            expired = true
        end
    end
    if expired then ns.Fire("CHESS_INVITE_CHANGED") end

    local s = G.seek
    if s and now >= s.next and C.Joined() then
        s.next = now + 12
        C.Broadcast("SK", s.base, s.inc, s.rated and 1 or 0, s.any and 1 or 0)
    end

    if C.Joined() and now >= nextAnnounce and nextAnnounce > 0 then
        G.Announce(true)
    end
end)

ns.On("CHESS_LEDGER_CHANGED", function()
    local g = G.current
    if g and g.state == "over" and g.rated and g.ratingBefore and not g.delta and ns.Ledger.Counted(g.id) then
        g.delta = ns.Ledger.Rating(ns.me) - g.ratingBefore
        ns.Fire("CHESS_GAME_CHANGED", g)
    end
end)

ns.On("CHESS_READY", function()
    -- Drop old finished-game records.
    local cutoff = ns.ServerTime() - 2 * 86400
    for id, rec in pairs(P.me.recent) do
        if type(rec) ~= "table" or (rec.at or 0) < cutoff then P.me.recent[id] = nil end
    end
    ns.After(5, Restore)
end)
