-- Flightpath Legends - static data - rank titles, board themes, piece sets and badges.
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

-- Leagues: rated battles are only possible within one league of each other.
-- badge: PvP rank insignia number used as the league emblem.
D.LEAGUES = {
    { name = "Recruit", min = 0, badge = 2, desc = "Below 1200" },
    { name = "Veteran", min = 1200, badge = 6, desc = "1200 - 1499" },
    { name = "Champion", min = 1500, badge = 10, desc = "1500 - 1799" },
    { name = "Warlord", min = 1800, badge = 14, desc = "1800 and above" },
}

function D.LeagueFor(rating)
    local idx = 1
    for i = 1, #D.LEAGUES do
        if rating >= D.LEAGUES[i].min then idx = i end
    end
    return idx
end

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
    { id = "grove", name = "Emerald Grove", light = { 0.93, 0.93, 0.82 }, dark = { 0.42, 0.58, 0.32 } },
    { id = "dusk", name = "Dusk Marble", light = { 0.80, 0.78, 0.84 }, dark = { 0.38, 0.33, 0.48 } },
    { id = "forge", name = "Molten Forge", light = { 0.96, 0.78, 0.52 }, dark = { 0.55, 0.20, 0.10 } },
    { id = "tide", name = "Deep Tide", light = { 0.70, 0.90, 0.90 }, dark = { 0.10, 0.38, 0.47 } },
    { id = "blood", name = "Bloodstone", light = { 0.85, 0.72, 0.70 }, dark = { 0.45, 0.10, 0.12 } },
    { id = "void", name = "Twilight Void", light = { 0.62, 0.55, 0.80 }, dark = { 0.20, 0.12, 0.33 } },
    { id = "royal", name = "Royal Gold", light = { 1.00, 0.93, 0.65 }, dark = { 0.70, 0.52, 0.12 } },
    { id = "legend", name = "Legend's Slate", light = { 0.78, 0.78, 0.78 }, dark = { 0.16, 0.16, 0.18 } },
}

-- Piece sets are two tints (fill and outline) per side applied to the same artwork.
-- Piece styles. Matchups use Warcraft portraits (Assets.ARMIES): you lead one side and
-- your opponent's pieces are the other (only on your own screen). "faction" means you lead
-- your character's own faction. Colours are for the classic style and as a fallback.
local IVORY = { wFill = { 0.97, 0.95, 0.90 }, wLine = { 0.08, 0.07, 0.06 }, bFill = { 0.20, 0.19, 0.18 }, bLine = { 0.92, 0.90, 0.85 } }
local function Style(t)
    for k, v in pairs(IVORY) do t[k] = t[k] or v end
    return t
end
D.PIECES = {
    Style({ id = "warcraft", name = "Horde vs Alliance", warcraft = true, armies = { "Alliance", "Horde" }, faction = true }),
    Style({ id = "kaldorei", name = "Kaldorei vs Burning Legion", warcraft = true, armies = { "Kaldorei", "Legion" } }),
    Style({ id = "ironforge", name = "Ironforge vs Blackrock", warcraft = true, armies = { "Ironforge", "Blackrock" } }),
    Style({ id = "lordaeron", name = "Alliance vs the Scourge", warcraft = true, armies = { "Alliance", "Scourge" } }),
    Style({ id = "ulduar", name = "Titan Keepers vs Old Gods", warcraft = true, armies = { "Keepers", "OldGods" } }),
    Style({ id = "classic", name = "Classic Chess" }),
}

-- Feats. Each one awards a title the player can display once earned (the rewards).
-- `check(p, s)` receives the profile (after the game was recorded) and the game summary.
D.BADGES = {
    { id = "first_game", title = "the Initiate", name = "First Move", points = 5, desc = "Finish a game against another player.",
        check = function(p, s) return s.mode == "online" end },
    { id = "first_win", title = "the Victorious", name = "First Blood", points = 10, desc = "Win a game against another player.",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" end },
    { id = "wins10", title = "the Seasoned", name = "Seasoned", points = 10, desc = "Win 10 rated games.",
        check = function(p) return p.w >= 10 end, progress = function(p) return p.w, 10 end },
    { id = "wins50", name = "Veteran", points = 25, desc = "Win 50 rated games.", title = "Veteran",
        check = function(p) return p.w >= 50 end, progress = function(p) return p.w, 50 end },
    { id = "wins100", name = "Warlord of the Board", points = 50, desc = "Win 100 rated games.", title = "Warlord of the Board",
        check = function(p) return p.w >= 100 end, progress = function(p) return p.w, 100 end },
    { id = "streak3", title = "the Relentless", name = "On a Roll", points = 10, desc = "Win 3 rated games in a row.",
        check = function(p) return p.bestStreak >= 3 end, progress = function(p) return p.bestStreak, 3 end },
    { id = "streak5", name = "Unstoppable", points = 20, desc = "Win 5 rated games in a row.", title = "the Unstoppable",
        check = function(p) return p.bestStreak >= 5 end, progress = function(p) return p.bestStreak, 5 end },
    { id = "streak10", name = "The Unbroken", points = 50, desc = "Win 10 rated games in a row.", title = "the Unbroken",
        check = function(p) return p.bestStreak >= 10 end, progress = function(p) return p.bestStreak, 10 end },
    { id = "giant", name = "Giant Slayer", points = 25, desc = "Win a rated game against someone rated 200 or more above you.", title = "Giant Slayer",
        check = function(p, s) return s.rated and s.outcome == "win" and (s.oppRating - s.ratingBefore) >= 200 end },
    { id = "quick", title = "the Swift", name = "Lightning Strike", points = 15, desc = "Checkmate another player within your first 15 moves.",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" and s.reason == "checkmate" and s.myMoves <= 15 end },
    { id = "pawnmate", name = "Peasant Uprising", points = 25, desc = "Deliver checkmate to another player with a pawn.", title = "Peasant King",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" and s.reason == "checkmate" and s.matePiece == 1 end },
    { id = "underpromo", title = "the Dark Horse", name = "Dark Horse", points = 15, desc = "Promote a pawn to a knight and win against another player.",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" and s.knightPromo end },
    { id = "clutch", title = "Hand of Fate", name = "By a Thread", points = 15, desc = "Win a timed game with under 10 seconds left on your clock.",
        check = function(p, s) return s.mode == "online" and s.outcome == "win" and s.timed and s.myClock < 10 end },
    { id = "rivals10", title = "the Well-Travelled", name = "Well Travelled", points = 15, desc = "Play 10 different opponents.",
        check = function(p) return p.rivalCount >= 10 end, progress = function(p) return p.rivalCount, 10 end },
    { id = "marathon", title = "the Enduring", name = "War of Attrition", points = 15, desc = "Finish a game against a player that lasts 60 moves or more.",
        check = function(p, s) return s.mode == "online" and s.myMoves >= 60 end },
    { id = "peace", title = "the Peacekeeper", name = "Honourable Peace", points = 5, desc = "Draw a rated game.",
        check = function(p, s) return s.rated and s.outcome == "draw" end },
    { id = "bot1", title = "Sparring Partner", name = "Sparring Partner", points = 5, desc = "Beat the Novice computer.",
        check = function(p, s) return s.mode == "ai" and s.outcome == "win" and s.aiLevel >= 1 end },
    { id = "bot2", title = "Quick Study", name = "Quick Study", points = 10, desc = "Beat the Adept computer.",
        check = function(p, s) return s.mode == "ai" and s.outcome == "win" and s.aiLevel >= 2 end },
    { id = "bot3", title = "Machine Breaker", name = "Machine Breaker", points = 20, desc = "Beat the Master computer.",
        check = function(p, s) return s.mode == "ai" and s.outcome == "win" and s.aiLevel >= 3 end },
    { id = "watcher", title = "Armchair General", name = "Armchair General", points = 5, desc = "Watch another game through to the end.",
        check = function(p, s) return s.mode == "spectate" end },
    { id = "r1350", title = "Knighted", name = "Knighted", points = 10, desc = "Reach a rating of 1350.",
        check = function(p) return p.peak >= 1350 end },
    { id = "r1500", title = "Strategist", name = "Strategist", points = 20, desc = "Reach a rating of 1500.",
        check = function(p) return p.peak >= 1500 end },
    { id = "r1800", title = "Mastermind", name = "Mastermind", points = 40, desc = "Reach a rating of 1800.",
        check = function(p) return p.peak >= 1800 end },
    { id = "r2000", title = "Grand Designer", name = "Grand Design", points = 75, desc = "Reach a rating of 2000.",
        check = function(p) return p.peak >= 2000 end },

    -- Battleship (game = "bs")
    { id = "bs_sail", game = "bs", title = "the Deckhand", name = "Set Sail", points = 5, desc = "Finish a Battleship battle against another player.",
        check = function(p, s) return s.mode == "bs" and not s.vsAI end },
    { id = "bs_win1", game = "bs", title = "the Gunner", name = "First Broadside", points = 10, desc = "Win a Battleship battle against another player.",
        check = function(p, s) return s.mode == "bs" and not s.vsAI and s.outcome == "win" end },
    { id = "bs_win10", game = "bs", title = "Fleet Captain", name = "Fleet Captain", points = 15, desc = "Win 10 Battleship battles.",
        check = function(p) return (p.bsw or 0) >= 10 end, progress = function(p) return p.bsw or 0, 10 end },
    { id = "bs_win50", game = "bs", title = "Grand Admiral", name = "Grand Admiral", points = 50, desc = "Win 50 Battleship battles.",
        check = function(p) return (p.bsw or 0) >= 50 end, progress = function(p) return p.bsw or 0, 50 end },
    { id = "bs_streak5", game = "bs", title = "Terror of the Seas", name = "Terror of the Seas", points = 25, desc = "Win 5 Battleship battles in a row.",
        check = function(p) return (p.bsBest or 0) >= 5 end, progress = function(p) return p.bsBest or 0, 5 end },
    { id = "bs_flawless", game = "bs", title = "the Untouchable", name = "Untouchable", points = 25, desc = "Win a Battleship battle without losing a single ship.",
        check = function(p, s) return s.mode == "bs" and not s.vsAI and s.outcome == "win" and s.shipsLeft == 5 end },
    { id = "bs_sharp", game = "bs", title = "the Sharpshooter", name = "Sharpshooter", points = 20, desc = "Win a Battleship battle in 45 shots or fewer.",
        check = function(p, s) return s.mode == "bs" and not s.vsAI and s.outcome == "win" and s.shots <= 45 end },
    { id = "bs_last", game = "bs", title = "Last Ship Standing", name = "Last Ship Standing", points = 15, desc = "Win a Battleship battle with only one ship left afloat.",
        check = function(p, s) return s.mode == "bs" and not s.vsAI and s.outcome == "win" and s.shipsLeft == 1 end },
    { id = "bs_ai", game = "bs", title = "the Sea Dog", name = "Sea Dog", points = 10, desc = "Beat the Admiral (the hardest computer) at Battleship.",
        check = function(p, s) return s.mode == "bs" and s.vsAI and s.outcome == "win" and s.aiLevel >= 3 end },

    -- Four in a Row (game = "c4")
    { id = "c4_play", game = "c4", title = "the Coin Dropper", name = "First Drop", points = 5, desc = "Finish a game of Four in a Row against another player.",
        check = function(p, s) return s.mode == "c4" and not s.vsAI end },
    { id = "c4_win1", game = "c4", title = "the Connector", name = "Four Down", points = 10, desc = "Win a game of Four in a Row against another player.",
        check = function(p, s) return s.mode == "c4" and not s.vsAI and s.outcome == "win" end },
    { id = "c4_win10", game = "c4", title = "Tavern Champion", name = "Tavern Champion", points = 15, desc = "Win 10 games of Four in a Row.",
        check = function(p) return (p.c4w or 0) >= 10 end, progress = function(p) return p.c4w or 0, 10 end },
    { id = "c4_win50", game = "c4", title = "Grandmaster of the Tavern", name = "Grandmaster of the Tavern", points = 50, desc = "Win 50 games of Four in a Row.",
        check = function(p) return (p.c4w or 0) >= 50 end, progress = function(p) return p.c4w or 0, 50 end },
    { id = "c4_streak5", game = "c4", title = "the Unbeatable", name = "Unbeatable", points = 25, desc = "Win 5 games of Four in a Row in a row.",
        check = function(p) return (p.c4Best or 0) >= 5 end, progress = function(p) return p.c4Best or 0, 5 end },
    { id = "c4_quick", game = "c4", title = "the Quick Draw", name = "Quick Draw", points = 15, desc = "Win with no more than 6 coins of your own.",
        check = function(p, s) return s.mode == "c4" and not s.vsAI and s.outcome == "win" and s.myCoins <= 6 end },
    { id = "c4_diag", game = "c4", title = "the Sharp Angle", name = "Sharp Angle", points = 10, desc = "Win with a diagonal line.",
        check = function(p, s) return s.mode == "c4" and not s.vsAI and s.outcome == "win" and s.diagonal end },
    { id = "c4_last", game = "c4", title = "the Last Coin", name = "The Last Coin", points = 20, desc = "Win by filling the very last empty hole.",
        check = function(p, s) return s.mode == "c4" and not s.vsAI and s.outcome == "win" and s.lastHole end },
    { id = "c4_draw", game = "c4", title = "the Even-Handed", name = "Even Match", points = 5, desc = "Draw a game of Four in a Row against another player.",
        check = function(p, s) return s.mode == "c4" and not s.vsAI and s.outcome == "draw" end },
    { id = "c4_ai", game = "c4", title = "the Machinist", name = "Machinist", points = 10, desc = "Beat the Master computer at Four in a Row.",
        check = function(p, s) return s.mode == "c4" and s.vsAI and s.outcome == "win" and s.aiLevel >= 3 end },
}

-- The games of Flightpath Legends. kind: witnessed-record kind, seek: lobby status while queued,
-- noTitle: what players without a title are called in that game.
D.GAMES = {
    chess = { name = "Chess", kind = "r", seek = "r" },
    bs = { name = "Battleship", kind = "b", seek = "b", noTitle = "Landlubber" },
    c4 = { name = "Four in a Row", kind = "f", seek = "f", noTitle = "Tavern Regular" },
}
D.GAME_ORDER = { "chess", "bs", "c4" }

-- Badge icons (game icons). A table picks the icon by the player's faction.
local function PvP(n) return { Alliance = string.format("achievement_pvp_a_%02d", n), Horde = string.format("achievement_pvp_h_%02d", n) } end
D.BADGE_ICONS = {
    first_game = "inv_misc_book_09",
    first_win = "inv_sword_04",
    wins10 = PvP(4),
    wins50 = PvP(8),
    wins100 = PvP(14),
    streak3 = "ability_warrior_charge",
    streak5 = "ability_warrior_battleshout",
    streak10 = "inv_shield_06",
    giant = "inv_misc_head_dragon_01",
    quick = "ability_rogue_sprint",
    pawnmate = { Alliance = "achievement_character_human_male", Horde = "achievement_character_orc_male" },
    underpromo = { Alliance = "ability_mount_charger", Horde = "ability_mount_blackdirewolf" },
    clutch = "inv_misc_pocketwatch_01",
    rivals10 = "inv_misc_map_01",
    marathon = "spell_nature_timestop",
    peace = "spell_holy_layonhands",
    bot1 = "inv_misc_gear_01",
    bot2 = "inv_misc_gear_02",
    bot3 = "inv_misc_gear_08",
    watcher = "inv_misc_spyglass_01",
    r1350 = PvP(5),
    r1500 = PvP(7),
    r1800 = PvP(10),
    r2000 = PvP(12),
    bs_sail = { Alliance = "inv_garrison_alliancedestroyer", Horde = "inv_garrison_hordedestroyer" },
    bs_win1 = "ability_rogue_cannonballbarrage",
    bs_win10 = "inv_garrison_dreadnaught",
    bs_win50 = "inv_garrison_carrier",
    bs_streak5 = { Alliance = "inv_garrison_alliancesub", Horde = "inv_garrison_hordesub" },
    bs_flawless = "inv_misc_anchor",
    bs_sharp = "ability_marksmanship",
    bs_last = "inv_garrison_cargoship",
    bs_ai = "ships_ability_depthcharges",
    c4_play = "inv_misc_coin_05",
    c4_win1 = "inv_misc_coin_03",
    c4_win10 = "inv_misc_coin_01",
    c4_win50 = "inv_misc_coin_02",
    c4_streak5 = "inv_misc_coin_04",
    c4_quick = "inv_drink_05",
    c4_diag = "inv_drink_03",
    c4_last = "inv_misc_bag_10",
    c4_draw = "inv_drink_01",
    c4_ai = "inv_misc_gear_08",
}

function D.BadgeIcon(id, faction)
    local icon = D.BADGE_ICONS[id]
    if type(icon) == "table" then icon = icon[faction or "Alliance"] end
    return icon and ("Interface\\Icons\\" .. icon) or nil
end

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
