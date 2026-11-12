-- ChessPvP: player profile (rating, stats, badges, unlocks) and the realm leaderboard cache.
local _, ns = ...

local P = {}
ns.Profile = P

local D = ns.Data
local floor = math.floor

P.online = {} -- [fullName] = { last = GetTime(), status = "i|g|s|d", opp = fullName or nil }

------------------------------------------------------------------------
-- My profile
------------------------------------------------------------------------
local PROFILE_DEFAULTS = {
    rating = D.START_RATING, peak = D.START_RATING,
    w = 0, l = 0, d = 0, -- rated results
    cw = 0, cl = 0, cd = 0, -- casual results against players
    games = 0, -- all finished games against players
    streak = 0, bestStreak = 0,
    rivalCount = 0,
    theme = "oak", pieces = "classic",
}

function P.Get()
    return P.me
end

local function InitProfile()
    local chars = ns.db.chars
    local p = chars[ns.me]
    if type(p) ~= "table" then
        p = {}
        chars[ns.me] = p
    end
    for k, v in pairs(PROFILE_DEFAULTS) do
        if p[k] == nil then p[k] = v end
    end
    p.badges = p.badges or {}
    p.rivals = p.rivals or {}
    p.history = p.history or {}
    p.recent = p.recent or {}
    P.me = p

    local realms = ns.db.realms
    realms[ns.realm] = realms[ns.realm] or {}
    realms[ns.realm].players = realms[ns.realm].players or {}
    P.players = realms[ns.realm].players

    -- Forget players that have not been seen for 90 days.
    local cutoff = ns.ServerTime() - 90 * 86400
    for name, e in pairs(P.players) do
        if type(e) ~= "table" or (e.seen or 0) < cutoff then P.players[name] = nil end
    end
end

function P.RatedGames(p)
    p = p or P.me
    return p.w + p.l + p.d
end

function P.Points(p)
    p = p or P.me
    local total = 0
    for id in pairs(p.badges) do
        local b = D.BADGE_BY_ID[id]
        if b then total = total + b.points end
    end
    return total
end

function P.Stat(stat)
    local p = P.me
    if stat == "wins" then return p.w end
    if stat == "games" then return p.games end
    if stat == "peak" then return p.peak end
    if stat == "streak" then return p.bestStreak end
    if stat == "points" then return P.Points(p) end
    return 0
end

-- item is a theme or piece set from Data. Returns unlocked, requirementText.
function P.IsUnlocked(item)
    local req = item.req
    if not req then return true end
    local text = string.format(D.STAT_TEXT[req[1]], req[2])
    return P.Stat(req[1]) >= req[2], text
end

-- Titles the player may display: every rank up to their best, plus badge titles.
function P.AvailableTitles()
    local p = P.me
    local out = {}
    if P.RatedGames(p) >= D.PLACEMENT_GAMES then
        local top = D.RankFor(p.peak)
        for i = 1, #D.RANKS do
            local r = D.RANKS[i]
            if r.min <= top.min then out[#out + 1] = { id = r.id, name = r.name, color = r.color } end
        end
    end
    for i = 1, #D.BADGES do
        local b = D.BADGES[i]
        if b.title and p.badges[b.id] then
            out[#out + 1] = { id = "b:" .. b.id, name = b.title, color = "ffffd100" }
        end
    end
    return out
end

-- The title id broadcast to others: the chosen one, or the current rank.
function P.MyTitleId()
    local p = P.me
    if p.title and D.TitleName(p.title) then return p.title end
    if P.RatedGames(p) < D.PLACEMENT_GAMES then return "" end
    return D.RankFor(p.rating).id
end

-- Coloured title text for any player record ({ t = titleId, r = rating, g = ratedGames }).
function P.TitleText(titleId, rating, ratedGames)
    local name, color = D.TitleName(titleId)
    if not name then
        if (ratedGames or 0) < D.PLACEMENT_GAMES then return "|cff808080Unranked|r" end
        local rank = D.RankFor(rating or D.START_RATING)
        name, color = rank.name, rank.color
    end
    return "|c" .. color .. name .. "|r"
end

function P.SetTitle(id)
    P.me.title = id
    ns.Fire("PROFILE_CHANGED")
end

function P.SetTheme(id)
    local item = D.THEME_BY_ID[id]
    if item and P.IsUnlocked(item) then
        P.me.theme = id
        ns.Fire("PROFILE_CHANGED")
    end
end

function P.SetPieces(id)
    local item = D.PIECES_BY_ID[id]
    if item and P.IsUnlocked(item) then
        P.me.pieces = id
        ns.Fire("PROFILE_CHANGED")
    end
end

function P.Theme()
    local item = D.THEME_BY_ID[P.me and P.me.theme or "oak"]
    if not item or not P.IsUnlocked(item) then item = D.THEMES[1] end
    return item
end

function P.PieceSet()
    local item = D.PIECES_BY_ID[P.me and P.me.pieces or "classic"]
    if not item or not P.IsUnlocked(item) then item = D.PIECES[1] end
    return item
end

------------------------------------------------------------------------
-- Rating
------------------------------------------------------------------------
-- score: 1 win, 0.5 draw, 0 loss. Returns the new rating.
function P.Elo(rating, oppRating, score, ratedGames)
    local expected = 1 / (1 + 10 ^ ((oppRating - rating) / 400))
    local k = 24
    if ratedGames < 20 then k = 40 elseif rating >= 2000 then k = 16 end
    local new = floor(rating + k * (score - expected) + 0.5)
    if new < 100 then new = 100 end
    return new
end

local function UnlockedSet()
    local set = {}
    for i = 1, #D.THEMES do
        if P.IsUnlocked(D.THEMES[i]) then set["Board: " .. D.THEMES[i].name] = true end
    end
    for i = 1, #D.PIECES do
        if P.IsUnlocked(D.PIECES[i]) then set["Pieces: " .. D.PIECES[i].name] = true end
    end
    -- Only the highest rank counts here, so finishing placement announces one title.
    local titles = P.AvailableTitles()
    local topRank
    for i = 1, #titles do
        if D.RANK_BY_ID[titles[i].id] then
            topRank = titles[i].name
        else
            set["Title: " .. titles[i].name] = true
        end
    end
    if topRank then set["Title: " .. topRank] = true end
    return set
end

-- Records a finished game. The summary has:
--   mode ("online" | "ai" | "spectate"), outcome ("win" | "loss" | "draw"), reason,
--   rated, opp, oppRating, myMoves, matePiece, knightPromo, timed, myClock, aiLevel
-- Returns the rating change (0 for unrated games).
function P.RecordGame(s)
    local p = P.me
    local before = UnlockedSet()
    s.ratingBefore = p.rating
    local delta = 0

    if s.mode == "online" then
        p.games = p.games + 1
        if s.opp and not p.rivals[s.opp] then
            p.rivals[s.opp] = true
            p.rivalCount = p.rivalCount + 1
        end
        if s.rated then
            local score = (s.outcome == "win" and 1) or (s.outcome == "draw" and 0.5) or 0
            local new = P.Elo(p.rating, s.oppRating or D.START_RATING, score, P.RatedGames(p))
            delta = new - p.rating
            p.rating = new
            if new > p.peak then p.peak = new end
            if s.outcome == "win" then
                p.w = p.w + 1
                p.streak = p.streak + 1
                if p.streak > p.bestStreak then p.bestStreak = p.streak end
            elseif s.outcome == "loss" then
                p.l = p.l + 1
                p.streak = 0
            else
                p.d = p.d + 1
                p.streak = 0
            end
        else
            if s.outcome == "win" then p.cw = p.cw + 1
            elseif s.outcome == "loss" then p.cl = p.cl + 1
            else p.cd = p.cd + 1 end
        end
        table.insert(p.history, 1, {
            opp = s.opp, outcome = s.outcome, reason = s.reason, rated = s.rated and true or false,
            delta = delta, at = ns.ServerTime(), moves = s.myMoves,
        })
        while #p.history > 30 do table.remove(p.history) end
    end

    -- Badges
    for i = 1, #D.BADGES do
        local b = D.BADGES[i]
        if not p.badges[b.id] then
            local ok, earned = pcall(b.check, p, s)
            if ok and earned then
                p.badges[b.id] = ns.ServerTime()
                ns.Fire("TOAST", "Badge earned", b.name .. "  |cffffd100+" .. b.points .. "|r")
            end
        end
    end

    -- Anything newly unlocked by this game?
    local after = UnlockedSet()
    for label in pairs(after) do
        if not before[label] then
            ns.Fire("TOAST", "Unlocked", label)
        end
    end

    ns.Fire("PROFILE_CHANGED")
    return delta
end

------------------------------------------------------------------------
-- Leaderboard cache (what other players have announced about themselves)
------------------------------------------------------------------------
local function ValidInt(v, lo, hi)
    return type(v) == "number" and v == floor(v) and v >= lo and v <= hi
end

-- Stores a profile announced by `name`. Returns false if it looks implausible.
function P.UpdatePlayer(name, rating, w, l, d, titleId, points)
    if not (ValidInt(rating, 100, 3500) and ValidInt(w, 0, 99999) and ValidInt(l, 0, 99999) and ValidInt(d, 0, 99999)) then
        return false
    end
    -- A rating cannot be higher than the best possible run of results allows.
    if rating > D.START_RATING + 40 * w + 20 * d then return false end
    if not ValidInt(points, 0, 9999) then points = 0 end
    local e = P.players[name]
    if not e then
        e = {}
        P.players[name] = e
    end
    e.r, e.w, e.l, e.d = rating, w, l, d
    e.t = titleId or ""
    e.pts = points
    e.seen = ns.ServerTime()
    return true
end

function P.GetPlayer(name)
    return P.players and P.players[name]
end

-- Sorted leaderboard rows, including the local player.
function P.Board()
    local rows = {}
    local me = P.me
    if P.RatedGames(me) > 0 then
        rows[#rows + 1] = { name = ns.me, r = me.rating, w = me.w, l = me.l, d = me.d, t = P.MyTitleId(), pts = P.Points(me), me = true }
    end
    for name, e in pairs(P.players) do
        if name ~= ns.me and (e.w + e.l + e.d) > 0 then
            rows[#rows + 1] = { name = name, r = e.r, w = e.w, l = e.l, d = e.d, t = e.t, pts = e.pts or 0 }
        end
    end
    table.sort(rows, function(a, b)
        if a.r ~= b.r then return a.r > b.r end
        return a.name < b.name
    end)
    return rows
end

function P.SetOnline(name, status, opp)
    P.online[name] = { last = ns.Now(), status = status, opp = opp }
end

function P.SetOffline(name)
    P.online[name] = nil
end

-- Players heard from in the last few minutes, highest rated first.
function P.OnlineList()
    local now = ns.Now()
    local rows = {}
    for name, o in pairs(P.online) do
        if now - o.last > 420 then
            P.online[name] = nil
        else
            local e = P.players[name]
            rows[#rows + 1] = {
                name = name, status = o.status, opp = o.opp,
                r = e and e.r or D.START_RATING, t = e and e.t or "",
                g = e and (e.w + e.l + e.d) or 0,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.r ~= b.r then return a.r > b.r end
        return a.name < b.name
    end)
    return rows
end

ns.On("CHESS_READY", InitProfile)
