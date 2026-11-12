-- Checkmate: Azeroth - witnessed ratings.
--
-- Nobody's rating is taken from what they say about themselves. Instead every rated game
-- produces statements broadcast by each player ("game X between W and B has started" and
-- "... ended 1-0"). The game server stamps every addon message with the real sender, so
-- a player can only ever make statements for themselves. Every client collects the
-- statements it hears and computes everyone's rating from them in the same way:
--
--   * A game only exists if BOTH players stated that it started (no invented games).
--   * Both players agree on the result: it counts.
--   * The players disagree: it does not count, and both get a "disputed" mark.
--   * Only one result was stated and the other player stayed silent for 30 minutes
--     (left, rage-quit): the stated result counts.
--   * Only the first 2 rated games per pair of players per day count (no farming).
--   * Wins against provisional players (fewer than 5 counted games) are worth half.
--
-- Players re-share their own recent statements, so clients that were offline catch up.
local _, ns = ...

local L = {}
ns.Ledger = L

local floor = math.floor
local START = 1200
local PROVISIONAL = 5
local SILENCE = 1800 -- seconds before a one-sided result counts
local PAIR_PER_DAY = 2
local MAX_GAMES = 3000
local MAX_PER_PLAYER = 300

L.players = {} -- computed: [name] = { r, w, l, d, games, peak, beaten, disputed, opps }
local db -- ledger table in saved variables: { games = { [id] = game } }

local VALID_RES = { ["1-0"] = true, ["0-1"] = true, ["1/2"] = true }

------------------------------------------------------------------------
-- Storage
------------------------------------------------------------------------
local function CountStatements(name)
    local n = 0
    for _, g in pairs(db.games) do
        if g.st[name] then n = n + 1 end
    end
    return n
end

-- Records a statement by `sender` about game `id`. res is a result or nil (started).
-- Returns true when something changed.
function L.AddStatement(sender, id, white, black, ts, res, casual)
    if not db then return false end
    if type(id) ~= "string" or not string.match(id, "^%w+$") or #id > 12 then return false end
    if type(white) ~= "string" or type(black) ~= "string" or white == black then return false end
    if sender ~= white and sender ~= black then return false end -- only about your own games
    ts = tonumber(ts)
    if not ts or ts < 1600000000 or ts > ns.ServerTime() + 3600 then return false end
    if res ~= nil and not VALID_RES[res] then return false end

    local g = db.games[id]
    if not g then
        if CountStatements(sender) >= MAX_PER_PLAYER then return false end
        g = { w = white, b = black, st = {}, casual = casual and true or nil }
        db.games[id] = g
    elseif g.w ~= white or g.b ~= black or (g.casual or false) ~= (casual and true or false) then
        return false -- the first description of a game id wins
    end
    local st = g.st[sender]
    local changed = false
    if not st then
        st = { ts = ts }
        g.st[sender] = st
        changed = true
    elseif ts < st.ts then
        st.ts = ts
        changed = true
    end
    if res then
        if st.res and st.res ~= res then
            return changed -- a result, once stated, cannot be changed
        end
        if not st.res then
            st.res = res
            st.at = ns.ServerTime()
            changed = true
        end
    end
    if changed then L.Dirty() end
    return changed
end

------------------------------------------------------------------------
-- Rating computation (identical on every client)
------------------------------------------------------------------------
local function Get(players, name)
    local p = players[name]
    if not p then
        p = { r = START, w = 0, l = 0, d = 0, games = 0, peak = START, beaten = 0, opps = {}, disputed = 0,
            cw = 0, cl = 0, cd = 0, recent = {} }
        players[name] = p
    end
    return p
end

local function K(p)
    if p.games < 20 then return 40 end
    if p.r >= 2000 then return 16 end
    return 24
end

-- Rating change for `p` scoring `score` against `o`.
local function Delta(p, o, score)
    local expected = 1 / (1 + 10 ^ ((o.r - p.r) / 400))
    local d = K(p) * (score - expected)
    -- Beating a provisional player is worth half (cheap wins over fresh characters).
    if o.games < PROVISIONAL and p.games >= PROVISIONAL then d = d * 0.5 end
    return d
end

-- Decides the result of a game, or nil if it does not count (yet).
local function Outcome(g, now)
    local sw, sb = g.st[g.w], g.st[g.b]
    if not (sw and sb) then return nil end -- both must have started it
    local rw, rb = sw.res, sb.res
    if rw and rb then
        if rw ~= rb then return nil, true end
        return rw
    end
    local one = rw and sw or (rb and sb)
    if one and now - (one.at or 0) >= SILENCE then return one.res end
    return nil
end

function L.Recompute()
    if not db then return end
    local now = ns.ServerTime()
    local list = {}
    for id, g in pairs(db.games) do
        local sw, sb = g.st[g.w], g.st[g.b]
        local ts = math.min(sw and sw.ts or math.huge, sb and sb.ts or math.huge)
        if ts < math.huge then list[#list + 1] = { id = id, g = g, ts = ts } end
    end
    table.sort(list, function(a, b)
        if a.ts ~= b.ts then return a.ts < b.ts end
        return a.id < b.id
    end)

    local players = {}
    local pairDay = {}
    for i = 1, #list do
        local e = list[i]
        local g = e.g
        local res, disputed = Outcome(g, now)
        if disputed then
            Get(players, g.w).disputed = Get(players, g.w).disputed + 1
            Get(players, g.b).disputed = Get(players, g.b).disputed + 1
        elseif res and g.casual then
            -- Casual: witnessed win/loss/draw record, no rating, no daily cap.
            local pw, pb = Get(players, g.w), Get(players, g.b)
            local sw = (res == "1-0" and 1) or (res == "1/2" and 0.5) or 0
            if sw == 1 then pw.cw, pb.cl = pw.cw + 1, pb.cl + 1
            elseif sw == 0 then pb.cw, pw.cl = pb.cw + 1, pw.cl + 1
            else pw.cd, pb.cd = pw.cd + 1, pb.cd + 1 end
            table.insert(pw.recent, { opp = g.b, s = sw, rated = false, ts = e.ts })
            table.insert(pb.recent, { opp = g.w, s = 1 - sw, rated = false, ts = e.ts })
        elseif res then
            local a, b = g.w, g.b
            if b < a then a, b = b, a end
            local key = a .. "|" .. b .. "|" .. floor(e.ts / 86400)
            local n = (pairDay[key] or 0) + 1
            pairDay[key] = n
            if n <= PAIR_PER_DAY then
                local pw, pb = Get(players, g.w), Get(players, g.b)
                local sw = (res == "1-0" and 1) or (res == "1/2" and 0.5) or 0
                local dw = Delta(pw, pb, sw)
                local db_ = Delta(pb, pw, 1 - sw)
                pw.r = math.max(100, pw.r + dw)
                pb.r = math.max(100, pb.r + db_)
                pw.games, pb.games = pw.games + 1, pb.games + 1
                if sw == 1 then
                    pw.w, pb.l = pw.w + 1, pb.l + 1
                    if not pw.opps[g.b] then pw.opps[g.b] = true; pw.beaten = pw.beaten + 1 end
                elseif sw == 0 then
                    pb.w, pw.l = pb.w + 1, pw.l + 1
                    if not pb.opps[g.w] then pb.opps[g.w] = true; pb.beaten = pb.beaten + 1 end
                else
                    pw.d, pb.d = pw.d + 1, pb.d + 1
                end
                table.insert(pw.recent, { opp = g.b, s = sw, rated = true, ts = e.ts, d = floor(dw + 0.5) })
                table.insert(pb.recent, { opp = g.w, s = 1 - sw, rated = true, ts = e.ts, d = floor(db_ + 0.5) })
                pw.peak = math.max(pw.peak, floor(pw.r + 0.5))
                pb.peak = math.max(pb.peak, floor(pb.r + 0.5))
            end
        end
    end
    for _, p in pairs(players) do
        p.r = floor(p.r + 0.5)
        p.opps = nil
        -- Newest first, last 10 only.
        local recent = {}
        for i = #p.recent, math.max(1, #p.recent - 9), -1 do recent[#recent + 1] = p.recent[i] end
        p.recent = recent
    end
    L.players = players
    ns.Fire("CHESS_LEDGER_CHANGED")
end

-- Batches recomputation: many statements often arrive together.
local pending = false
function L.Dirty()
    if pending then return end
    pending = true
    ns.After(0.5, function()
        pending = false
        L.Recompute()
    end)
end

-- True when game id counts on the ladder (both players agree on its result).
function L.Counted(id)
    local g = db and db.games[id]
    if not g then return false end
    local res = Outcome(g, ns.ServerTime())
    return res ~= nil
end

-- Rating info for a player, or nil if they have no counted games.
function L.Get(name)
    local p = L.players[name]
    if p and (p.games > 0 or p.disputed > 0) then return p end
    return nil
end

-- Casual record, or nil if no witnessed casual games.
function L.Casual(name)
    local p = L.players[name]
    if p and (p.cw + p.cl + p.cd) > 0 then return p end
    return nil
end

-- Any witnessed record (rated or casual).
function L.Any(name)
    return L.players[name]
end

-- Head-to-head between a and b, from a's point of view: { w, l, d }.
function L.HeadToHead(a, b)
    local r = { w = 0, l = 0, d = 0 }
    if not db then return r end
    local now = ns.ServerTime()
    for _, g in pairs(db.games) do
        if (g.w == a and g.b == b) or (g.w == b and g.b == a) then
            local res = Outcome(g, now)
            if res then
                local aWhite = g.w == a
                if res == "1/2" then r.d = r.d + 1
                elseif (res == "1-0") == aWhite then r.w = r.w + 1
                else r.l = r.l + 1 end
            end
        end
    end
    return r
end

function L.Rating(name)
    local p = L.players[name]
    return p and p.r or START
end

------------------------------------------------------------------------
-- Network: statements are "GB" messages, each carrying up to three records
--   GB;id,white,black,ts,res;id,white,black,ts,res;...   (res "-" = started only)
------------------------------------------------------------------------
local function Record(id, g, name)
    local st = g.st[name]
    if not st then return nil end
    return table.concat({ id, g.w, g.b, st.ts, st.res or "-", g.casual and "c" or "r" }, ",")
end

-- Broadcasts our own statements for the given game ids (packed, 255-byte limit).
local function Share(ids)
    if not ns.Comm.Joined() then return end
    local parts, len = {}, 3
    local function Flush()
        if #parts > 0 then ns.Comm.SendRaw("CHANNEL", nil, "GB;" .. table.concat(parts, ";"), true) end
        parts, len = {}, 3
    end
    for i = 1, #ids do
        local g = db.games[ids[i]]
        local rec = g and Record(ids[i], g, ns.me)
        if rec then
            if len + #rec + 1 > 250 then Flush() end
            parts[#parts + 1] = rec
            len = len + #rec + 1
        end
    end
    Flush()
end

-- Our own recent rated games, newest first.
local function OwnRecent(n)
    local own = {}
    for id, g in pairs(db.games) do
        local st = g.st[ns.me]
        if st then own[#own + 1] = { id = id, ts = st.ts } end
    end
    table.sort(own, function(a, b) return a.ts > b.ts end)
    local ids = {}
    for i = 1, math.min(n, #own) do ids[i] = own[i].id end
    return ids
end

-- Called by Game when a rated online game starts or ends.
function L.StateOwn(g, res)
    if not db or g.mode ~= "online" then return end
    g.ledgerTs = g.ledgerTs or ns.ServerTime()
    L.AddStatement(ns.me, g.id, g.white, g.black, g.ledgerTs, res, not g.rated)
    Share({ g.id })
end

ns.Comm.handlers.GB = function(sender, dist, parts)
    for i = 2, #parts do
        local f = ns.Split(parts[i], ",")
        if #f == 5 or #f == 6 then
            local res = f[5] ~= "-" and f[5] or nil
            L.AddStatement(sender, f[1], f[2], f[3], f[4], res, f[6] == "c")
        end
    end
end

-- Newcomers ask everyone to re-share; replies are spread out and rate limited.
local lastShare = -1000
-- minGap: seconds since our last share below which we stay quiet (avoids storms when
-- several newcomers ask at once).
local function ShareRecent(minGap)
    local now = ns.Now()
    if now - lastShare < (minGap or 60) then return end
    lastShare = now
    Share(OwnRecent(12))
end

-- A newcomer's request is always answered (after a random delay so replies spread out);
-- requests arriving while a reply is already pending share that one reply.
local replyPending = false
ns.Comm.handlers.LQ = function(sender, dist)
    if dist ~= "CHANNEL" or replyPending then return end
    replyPending = true
    ns.After(2 + math.random() * 20, function()
        replyPending = false
        lastShare = -1000
        ShareRecent()
    end)
end

ns.On("CHESS_CHANNEL_READY", function()
    ns.After(4, function()
        ns.Comm.Broadcast("LQ")
        ShareRecent()
    end)
end)

-- Periodic re-share and re-evaluation (one-sided results mature after 30 minutes).
local nextShare, nextEval = 0, 0
ns.On("CHESS_TICK", function()
    if not db then return end
    local now = ns.Now()
    if now >= nextEval then
        nextEval = now + 60
        L.Recompute()
    end
    if now >= nextShare and ns.Comm.Joined() then
        nextShare = now + 600 + math.random(0, 120)
        lastShare = -1000
        ShareRecent()
    end
end)

------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------
local function Prune()
    local cutoff = ns.ServerTime() - 120 * 86400
    local list = {}
    for id, g in pairs(db.games) do
        local ts = math.huge
        for _, st in pairs(g.st) do ts = math.min(ts, st.ts) end
        if ts < cutoff then
            db.games[id] = nil
        else
            list[#list + 1] = { id = id, ts = ts }
        end
    end
    if #list > MAX_GAMES then
        table.sort(list, function(a, b) return a.ts < b.ts end)
        for i = 1, #list - MAX_GAMES do db.games[list[i].id] = nil end
    end
end

ns.On("CHESS_READY", function()
    local realm = ns.db.realms[ns.realm] or {}
    ns.db.realms[ns.realm] = realm
    realm.ledger = realm.ledger or { games = {} }
    db = realm.ledger
    Prune()
    L.Recompute()
end)
