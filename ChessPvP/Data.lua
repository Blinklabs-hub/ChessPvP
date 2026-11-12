-- ChessPvP: static data - rank titles, board themes, piece sets and badges.
local _, ns = ...

local D = {}
ns.Data = D

D.START_RATING = 1200
D.PLACEMENT_GAMES = 5 -- rated games before a rank title is shown

-- Time controls offered in the UI: base seconds, increment seconds.
D.TIME_CONTROLS = {
    { name = "Bullet 1+0", base = 60, inc = 0 },
    { name = "Blitz 3+2", base = 180, inc = 2 },
    { name = "Blitz 5+0", base = 300, inc = 0 },
    { name = "Rapid 10+0", base = 600, inc = 0 },
    { name = "Rapid 15+10", base = 900, inc = 10 },
    { name = "Classical 30+0", base = 1800, inc = 0 },
    { name = "No clock", base = 0, inc = 0 },
}

-- Rank titles, by rating.
D.RANKS = {
    { id = "r1", min = 0, name = "Pawn", color = "ff9d9d9d" },
    { id = "r2", min = 1000, name = "Squire", color = "ffffffff" },
    { id = "r3", min = 1200, name = "Footman", color = "ff1eff00" },
    { id = "r4", min = 1350, name = "Knight", color = "ff1eff00" },
    { id = "r5", min = 1500, name = "Tactician", color = "ff0070dd" },
    { id = "r6", min = 1650, name = "Castellan", color = "ff0070dd" },
    { id = "r7", min = 1800, name = "Master", color = "ffa335ee" },
    { id = "r8", min = 2000, name = "Grandmaster", color = "ffff8000" },
    { id = "r9", min = 2200, name = "Legend", color = "ffe6cc80" },
}

function D.RankFor(rating)
    local best = D.RANKS[1]
    for i = 1, #D.RANKS do
        if rating >= D.RANKS[i].min then best = D.RANKS[i] end
    end
    return best
end

-- Unlock requirements use one of these stats (see Profile.Stat):
--   wins (rated wins), games (games against players), peak (best rating),
--   streak (best rated win streak), points (badge points)
D.STAT_TEXT = {
    wins = "Win %d rated games",
    games = "Play %d games against players",
    peak = "Reach a rating of %d",
    streak = "Win %d rated games in a row",
    points = "Earn %d badge points",
}

-- `texture`: a game texture laid over the squares for a stone/marble grain (optional).
D.THEMES = {
    { id = "warfront", name = "Warfront Stone", light = { 0.80, 0.74, 0.62 }, dark = { 0.42, 0.36, 0.30 }, texture = "rock" },
    { id = "oak", name = "Tavern Oak", light = { 0.93, 0.85, 0.71 }, dark = { 0.62, 0.43, 0.27 } },
    { id = "frost", name = "Froststeel", light = { 0.87, 0.91, 0.95 }, dark = { 0.40, 0.53, 0.66 }, texture = "marble" },
    { id = "grove", name = "Emerald Grove", light = { 0.93, 0.93, 0.82 }, dark = { 0.42, 0.58, 0.32 }, req = { "games", 5 } },
    { id = "dusk", name = "Dusk Marble", light = { 0.80, 0.78, 0.84 }, dark = { 0.38, 0.33, 0.48 }, req = { "wins", 5 } },
    { id = "forge", name = "Molten Forge", light = { 0.96, 0.78, 0.52 }, dark = { 0.55, 0.20, 0.10 }, req = { "peak", 1350 } },
    { id = "tide", name = "Deep Tide", light = { 0.70, 0.90, 0.90 }, dark = { 0.10, 0.38, 0.47 }, req = { "points", 60 } },
    { id = "blood", name = "Bloodstone", light = { 0.85, 0.72, 0.70 }, dark = { 0.45, 0.10, 0.12 }, req = { "streak", 5 } },
    { id = "void", name = "Twilight Void", light = { 0.62, 0.55, 0.80 }, dark = { 0.20, 0.12, 0.33 }, req = { "wins", 25 } },
    { id = "royal", name = "Royal Gold", light = { 1.00, 0.93, 0.65 }, dark = { 0.70, 0.52, 0.12 }, req = { "peak", 1650 } },
    { id = "legend", name = "Legend's Slate", light = { 0.78, 0.78, 0.78 }, dark = { 0.16, 0.16, 0.18 }, req = { "peak", 2000 } },
}

-- Piece sets are two tints (fill and outline) per side applied to the same artwork.
D.PIECES = {
    { id = "warcraft", name = "Horde vs Alliance", warcraft = true,
        wFill = { 0.97, 0.95, 0.90 }, wLine = { 0.08, 0.07, 0.06 }, bFill = { 0.20, 0.19, 0.18 }, bLine = { 0.92, 0.90, 0.85 } },
    { id = "classic", name = "Ivory & Ebony",
        wFill = { 0.97, 0.95, 0.90 }, wLine = { 0.08, 0.07, 0.06 }, bFill = { 0.20, 0.19, 0.18 }, bLine = { 0.92, 0.90, 0.85 } },
    { id = "letters", name = "Letters", letters = true,
        wFill = { 1, 1, 1 }, wLine = { 0, 0, 0 }, bFill = { 0.1, 0.1, 0.1 }, bLine = { 1, 1, 1 } },
    { id = "faction", name = "Crimson & Azure", req = { "games", 10 },
        wFill = { 0.36, 0.62, 1.00 }, wLine = { 0.03, 0.08, 0.25 }, bFill = { 0.78, 0.14, 0.12 }, bLine = { 1.00, 0.85, 0.80 } },
    { id = "nature", name = "Sun & Moss", req = { "wins", 10 },
        wFill = { 1.00, 0.88, 0.45 }, wLine = { 0.25, 0.15, 0.02 }, bFill = { 0.16, 0.36, 0.18 }, bLine = { 0.85, 1.00, 0.80 } },
    { id = "arcane", name = "Fel & Arcane", req = { "points", 100 },
        wFill = { 0.60, 1.00, 0.35 }, wLine = { 0.05, 0.20, 0.02 }, bFill = { 0.45, 0.18, 0.70 }, bLine = { 0.95, 0.80, 1.00 } },
    { id = "gold", name = "Gold & Obsidian", req = { "peak", 1500 },
        wFill = { 1.00, 0.80, 0.20 }, wLine = { 0.30, 0.16, 0.00 }, bFill = { 0.08, 0.08, 0.10 }, bLine = { 1.00, 0.80, 0.20 } },
    { id = "spirit", name = "Spirit & Shadow", req = { "wins", 50 },
        wFill = { 0.75, 0.97, 1.00 }, wLine = { 0.05, 0.25, 0.35 }, bFill = { 0.22, 0.10, 0.30 }, bLine = { 0.75, 0.97, 1.00 } },
}

-- Badges. `title` (optional) is a title the player can display once earned.
-- `check(p, s)` receives the profile (after the game was recorded) and the game summary.
D.BADGES = {
    { id = "first_game", name = "First Move", points = 5, desc = "Finish a game against another player.",
        check = function(p, s) return s.mode == "online" end },
    { id = "first_win", name = "First Blood", points = 10, desc = "Win a game against another player.",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" end },
    { id = "wins10", name = "Seasoned", points = 10, desc = "Win 10 rated games.",
        check = function(p) return p.w >= 10 end, progress = function(p) return p.w, 10 end },
    { id = "wins50", name = "Veteran", points = 25, desc = "Win 50 rated games.", title = "Veteran",
        check = function(p) return p.w >= 50 end, progress = function(p) return p.w, 50 end },
    { id = "wins100", name = "Warlord of the Board", points = 50, desc = "Win 100 rated games.", title = "Warlord of the Board",
        check = function(p) return p.w >= 100 end, progress = function(p) return p.w, 100 end },
    { id = "streak3", name = "On a Roll", points = 10, desc = "Win 3 rated games in a row.",
        check = function(p) return p.bestStreak >= 3 end, progress = function(p) return p.bestStreak, 3 end },
    { id = "streak5", name = "Unstoppable", points = 20, desc = "Win 5 rated games in a row.", title = "the Unstoppable",
        check = function(p) return p.bestStreak >= 5 end, progress = function(p) return p.bestStreak, 5 end },
    { id = "streak10", name = "The Unbroken", points = 50, desc = "Win 10 rated games in a row.", title = "the Unbroken",
        check = function(p) return p.bestStreak >= 10 end, progress = function(p) return p.bestStreak, 10 end },
    { id = "giant", name = "Giant Slayer", points = 25, desc = "Win a rated game against someone rated 200 or more above you.", title = "Giant Slayer",
        check = function(p, s) return s.rated and s.outcome == "win" and (s.oppRating - s.ratingBefore) >= 200 end },
    { id = "quick", name = "Lightning Strike", points = 15, desc = "Checkmate another player within your first 15 moves.",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" and s.reason == "checkmate" and s.myMoves <= 15 end },
    { id = "pawnmate", name = "Peasant Uprising", points = 25, desc = "Deliver checkmate to another player with a pawn.", title = "Peasant King",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" and s.reason == "checkmate" and s.matePiece == 1 end },
    { id = "underpromo", name = "Dark Horse", points = 15, desc = "Promote a pawn to a knight and win against another player.",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" and s.knightPromo end },
    { id = "clutch", name = "By a Thread", points = 15, desc = "Win a timed game with under 10 seconds left on your clock.",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" and s.timed and s.myClock < 10 end },
    { id = "rivals10", name = "Well Travelled", points = 15, desc = "Play 10 different opponents.",
        check = function(p) return p.rivalCount >= 10 end, progress = function(p) return p.rivalCount, 10 end },
    { id = "marathon", name = "War of Attrition", points = 15, desc = "Finish a game against a player that lasts 60 moves or more.",
        check = function(p, s) return s.mode == "online" and s.myMoves >= 60 end },
    { id = "peace", name = "Honourable Peace", points = 5, desc = "Draw a rated game.",
        check = function(p, s) return s.rated and s.outcome == "draw" end },
    { id = "bot1", name = "Sparring Partner", points = 5, desc = "Beat the Novice computer.",
        check = function(p, s) return s.mode == "ai" and s.outcome == "win" and s.aiLevel >= 1 end },
    { id = "bot2", name = "Quick Study", points = 10, desc = "Beat the Adept computer.",
        check = function(p, s) return s.mode == "ai" and s.outcome == "win" and s.aiLevel >= 2 end },
    { id = "bot3", name = "Machine Breaker", points = 20, desc = "Beat the Master computer.",
        check = function(p, s) return s.mode == "ai" and s.outcome == "win" and s.aiLevel >= 3 end },
    { id = "watcher", name = "Armchair General", points = 5, desc = "Watch another game through to the end.",
        check = function(p, s) return s.mode == "spectate" end },
    { id = "r1350", name = "Knighted", points = 10, desc = "Reach a rating of 1350.",
        check = function(p) return p.peak >= 1350 end },
    { id = "r1500", name = "Strategist", points = 20, desc = "Reach a rating of 1500.",
        check = function(p) return p.peak >= 1500 end },
    { id = "r1800", name = "Mastermind", points = 40, desc = "Reach a rating of 1800.",
        check = function(p) return p.peak >= 1800 end },
    { id = "r2000", name = "Grand Design", points = 75, desc = "Reach a rating of 2000.",
        check = function(p) return p.peak >= 2000 end },
}

D.BADGE_BY_ID = {}
for i = 1, #D.BADGES do D.BADGE_BY_ID[D.BADGES[i].id] = D.BADGES[i] end

D.THEME_BY_ID = {}
for i = 1, #D.THEMES do D.THEME_BY_ID[D.THEMES[i].id] = D.THEMES[i] end

D.PIECES_BY_ID = {}
for i = 1, #D.PIECES do D.PIECES_BY_ID[D.PIECES[i].id] = D.PIECES[i] end

D.RANK_BY_ID = {}
for i = 1, #D.RANKS do D.RANK_BY_ID[D.RANKS[i].id] = D.RANKS[i] end

-- Resolves a title id ("r4" or "b:giant") to its text, or nil if unknown.
function D.TitleName(id)
    if not id or id == "" then return nil end
    local rank = D.RANK_BY_ID[id]
    if rank then return rank.name, rank.color end
    local badgeId = string.match(id, "^b:(.+)$")
    local badge = badgeId and D.BADGE_BY_ID[badgeId]
    if badge and badge.title then return badge.title, "ffffd100" end
    return nil
end

D.REASON_TEXT = {
    checkmate = "checkmate",
    stalemate = "stalemate",
    material = "insufficient material",
    fifty = "the fifty-move rule",
    repetition = "threefold repetition",
    resign = "resignation",
    time = "time",
    agreement = "agreement",
    abort = "the game was aborted",
    abandoned = "the opponent could not be reached",
}
