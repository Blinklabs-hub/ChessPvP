-- Flightpath Legends - player profile (rating, stats, badges, unlocks) and the realm leaderboard cache.
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
    theme = "warfront", pieces = "warcraft",
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
    -- 1.1: switch existing players to the new Warcraft look once (they can switch back).
    if (p.style or 0) < 1 then
        p.style = 1
        if p.pieces == "classic" then p.pieces = "warcraft" end
        if p.theme == "oak" then p.theme = "warfront" end
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

-- Counted rated games: from the ledger for ourselves, else what was announced.
function P.RatedGames(p)
    if p == nil or p == P.me then
        local e = ns.Ledger.Get(ns.me)
        return e and e.games or 0
    end
    return p.w + p.l + p.d
end

-- Which game a feat belongs to ("chess" or "bs").
function P.BadgeGame(b)
    return b.game or "chess"
end

-- Feat points for one game (chess when no game is given).
function P.Points(p, game)
    p = p or P.me
    game = game or "chess"
    local total = 0
    for id in pairs(p.badges) do
        local b = D.BADGE_BY_ID[id]
        if b and P.BadgeGame(b) == game then total = total + b.points end
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
-- Titles the player may show in one game: chess ranks and chess feats, or Battleship feats.
function P.AvailableTitles(game)
    game = game or "chess"
    local p = P.me
    local out = {}
    if game == "chess" and P.RatedGames(p) >= D.PLACEMENT_GAMES then
        local top = D.RankFor(p.peak)
        for i = 1, #D.RANKS do
            local r = D.RANKS[i]
            if r.min <= top.min then out[#out + 1] = { id = r.id, name = r.name, color = r.color } end
        end
    end
    for i = 1, #D.BADGES do
        local b = D.BADGES[i]
        if b.title and p.badges[b.id] and P.BadgeGame(b) == game then
            out[#out + 1] = { id = "b:" .. b.id, name = b.title, color = "ffffd100" }
        end
    end
    return out
end

-- The title id broadcast to others: the chosen one, or the current rank.
-- The title shown to others in a game ("chess" by default).
local function TitleGame(id)
    local badgeId = id and string.match(id, "^b:(.+)$")
    local b = badgeId and D.BADGE_BY_ID[badgeId]
    return b and P.BadgeGame(b) or "chess"
end

function P.MyTitleId(game)
    local p = P.me
    if game and game ~= "chess" then
        local id = (game == "bs") and p.bsTitle or (p.gameTitles and p.gameTitles[game])
        if id and D.TitleName(id) and TitleGame(id) == game then return id end
        return ""
    end
    if p.title and D.TitleName(p.title) and TitleGame(p.title) == "chess" then return p.title end
    if P.RatedGames(p) < D.PLACEMENT_GAMES then return "" end
    return D.RankFor(p.rating).id
end

-- Battleship title text (players without one are still landlubbers).
-- Title text in a game other than chess (players without one get the game's default name).
function P.GameTitleText(id, game)
    local name, color = D.TitleName(id)
    if name then return "|c" .. color .. name .. "|r" end
    local g = D.GAMES[game or "bs"]
    return "|cff808080" .. ((g and g.noTitle) or "No title") .. "|r"
end

function P.BsTitleText(id)
    return P.GameTitleText(id, "bs")
end

-- A player's title id in a game, from what they announced (or our own).
local TITLE_FIELD = { bs = "bt", c4 = "ft" }
function P.TitleOf(name, game)
    if ns.SameName(name, ns.me) then return P.MyTitleId(game) end
    local e = P.players[name]
    if not e then return "" end
    if game == "chess" or not game then return e.t or "" end
    return e[TITLE_FIELD[game]] or ""
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

function P.SetTitle(id, game)
    if game == "bs" then
        P.me.bsTitle = id
    elseif game and game ~= "chess" then
        P.me.gameTitles = P.me.gameTitles or {}
        P.me.gameTitles[game] = id
    else
        P.me.title = id
    end
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

-- Which side of a matchup style the player leads (1 or 2).
function P.LeadIndex(set)
    local lead = P.me and P.me.lead and P.me.lead[set.id]
    if lead == 2 then return 2 end
    return 1
end

function P.SwapLead(id)
    local set = D.PIECES_BY_ID[id]
    if not set or not set.armies or set.faction then return end
    P.me.lead = P.me.lead or {}
    P.me.lead[id] = (P.LeadIndex(set) == 1) and 2 or 1
    ns.Fire("PROFILE_CHANGED")
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
        if P.IsUnlocked(D.PIECES[i]) then set["Style: " .. D.PIECES[i].name] = true end
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

    if s.mode == "c4" and not s.vsAI then
        -- local Four in a Row counters (only for feats; the record itself is witnessed)
        if s.outcome == "win" then
            p.c4w = (p.c4w or 0) + 1
            p.c4Streak = (p.c4Streak or 0) + 1
            if p.c4Streak > (p.c4Best or 0) then p.c4Best = p.c4Streak end
        elseif s.outcome == "loss" or s.outcome == "draw" then
            p.c4Streak = 0
        end
    end
    if s.mode == "bs" and not s.vsAI then
        -- local Battleship counters (only for feats; the record itself is witnessed)
        if s.outcome == "win" then
            p.bsw = (p.bsw or 0) + 1
            p.bsStreak = (p.bsStreak or 0) + 1
            if p.bsStreak > (p.bsBest or 0) then p.bsBest = p.bsStreak end
        elseif s.outcome == "loss" then
            p.bsl = (p.bsl or 0) + 1
            p.bsStreak = 0
        end
    end
    if s.mode == "online" then
        p.games = p.games + 1
        if s.opp and not p.rivals[s.opp] then
            p.rivals[s.opp] = true
            p.rivalCount = p.rivalCount + 1
        end
        if s.rated then
            -- The rating itself comes from the witnessed ledger (Ledger.lua); these local
            -- counts only drive badges and unlocks.
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
                ns.Fire("TOAST", "Badge earned", b.name .. "  |cffffd100+" .. b.points .. "|r", D.BadgeIcon(b.id, ns.Assets.MyFaction()))
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

-- Ladder rows from the witnessed ledger, best first.
--   name, r, w, l, d, games, beaten, disputed, peak, t (title id), f (faction), me
function P.Board()
    local rows = {}
    for name, e in pairs(ns.Ledger.players) do
        if e.games > 0 then
            local known = P.players[name]
            local t = name == ns.me and P.MyTitleId() or (known and known.t) or ""
            rows[#rows + 1] = {
                name = name, r = e.r, w = e.w, l = e.l, d = e.d, games = e.games, beaten = e.beaten,
                disputed = e.disputed, peak = e.peak, t = t, me = name == ns.me,
                f = name == ns.me and ns.Assets.MyFaction() or (known and known.f),
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.r ~= b.r then return a.r > b.r end
        return a.name < b.name
    end)
    return rows
end

-- Battleship leaderboard: witnessed wins and losses, best win ratio first.
function P.AdmiralBoard()
    local rows = {}
    for name, e in pairs(ns.Ledger.players) do
        local n = (e.bw or 0) + (e.bl or 0)
        if n > 0 then
            local known = P.players[name]
            rows[#rows + 1] = {
                name = name, w = e.bw, l = e.bl, games = n, ratio = e.bw / n, best = e.bbest, streak = e.bstreak,
                me = name == ns.me, t = name == ns.me and P.MyTitleId("bs") or (known and known.bt) or "",
                f = name == ns.me and ns.Assets.MyFaction() or (known and known.f), ch = known and known.ch,
            }
        end
    end
    -- Ratio first, but a few battles are needed before a perfect record counts as best.
    local function Score(r) return (r.w + 1) / (r.games + 2) end
    table.sort(rows, function(a, b)
        local sa, sb = Score(a), Score(b)
        if sa ~= sb then return sa > sb end
        if a.w ~= b.w then return a.w > b.w end
        return a.name < b.name
    end)
    return rows
end

-- Four in a Row leaderboard: witnessed wins, losses and draws, best record first.
function P.TavernBoard()
    local rows = {}
    for name, e in pairs(ns.Ledger.players) do
        local n = (e.fw or 0) + (e.fl or 0) + (e.fd or 0)
        if n > 0 then
            local known = P.players[name]
            rows[#rows + 1] = {
                name = name, w = e.fw, l = e.fl, d = e.fd, games = n, ratio = (e.fw + e.fd * 0.5) / n,
                best = e.fbest, streak = e.fstreak, me = name == ns.me, t = P.TitleOf(name, "c4"),
                f = name == ns.me and ns.Assets.MyFaction() or (known and known.f), ch = known and known.ch,
            }
        end
    end
    local function Score(r) return (r.w + r.d * 0.5 + 1) / (r.games + 2) end
    table.sort(rows, function(a, b)
        local sa, sb = Score(a), Score(b)
        if sa ~= sb then return sa > sb end
        if a.w ~= b.w then return a.w > b.w end
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
            local v = ns.Ledger.Get(name)
            rows[#rows + 1] = {
                name = name, status = o.status, opp = o.opp,
                -- Witnessed rating when known; otherwise what they claim, marked unverified.
                r = v and v.r or (e and e.r) or D.START_RATING, verified = v ~= nil,
                t = e and e.t or "", bt = e and e.bt, ft = e and e.ft, f = e and e.f, ch = e and e.ch, battle = o.battle,
                bs = ns.Ledger.Battleship(name), c4 = ns.Ledger.FourRow(name),
                g = v and v.games or 0, casual = ns.Ledger.Casual(name),
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.r ~= b.r then return a.r > b.r end
        return a.name < b.name
    end)
    return rows
end

-- On Forever a typed single word ("Keepingcalm") may be either half of a two-part name.
-- If exactly one known player matches, that player is meant.
ns.ResolveSingleName = function(word)
    word = string.lower(word)
    local found
    local function Consider(name)
        if found == name then return true end
        for part in string.gmatch(name, "%S+") do
            if string.lower(part) == word then
                if found then return false end -- ambiguous
                found = name
                return true
            end
        end
        return true
    end
    for name in pairs(P.online) do
        if not Consider(name) then return nil end
    end
    if P.players then
        for name in pairs(P.players) do
            if not Consider(name) then return nil end
        end
    end
    return found
end

ns.On("CHESS_READY", InitProfile)

-- Our rating is whatever the ledger says.
ns.On("CHESS_LEDGER_CHANGED", function()
    if not P.me then return end
    local e = ns.Ledger.Get(ns.me)
    P.me.rating = e and e.r or D.START_RATING
    P.me.peak = e and e.peak or D.START_RATING
    ns.Fire("PROFILE_CHANGED")
end)
