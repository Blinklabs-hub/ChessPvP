-- Flightpath Legends - Warcraft look and feel - game art lookups (with safe fallbacks), the two armies,
-- sounds, and a small tween engine for animations.
local ADDON, ns = ...

local A = {}
local floor = math.floor
ns.Assets = A

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
A.TEX = TEX

------------------------------------------------------------------------
-- Art lookups. The game client is the source of the Warcraft art; every path is checked
-- at runtime and anything missing falls back to the addon's own textures.
------------------------------------------------------------------------
local fileCache = {}

-- True when the client has this file (or when it cannot tell).
function A.HasFile(path)
    if not path then return false end
    local cached = fileCache[path]
    if cached ~= nil then return cached end
    local ok = true
    if GetFileIDFromPath then
        local success, id = pcall(GetFileIDFromPath, path)
        ok = success and type(id) == "number" and id > 0
    end
    fileCache[path] = ok
    return ok
end

-- First existing path from a list, or nil.
function A.First(list)
    for i = 1, #list do
        if A.HasFile(list[i]) then return list[i] end
    end
    return nil
end

function A.HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

local function Icon(name) return "Interface\\Icons\\" .. name end

-- Window and board art from the game (each with a fallback in the UI code).
A.ART = {
    dialogBg = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    goldBorder = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    dialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
    marble = "Interface\\FrameGeneral\\UI-Background-Marble",
    rock = "Interface\\FrameGeneral\\UI-Background-Rock",
    glow = "Interface\\Buttons\\UI-ActionButton-Border",
    sea = "Interface\\Garrison\\ShipyardNavalMap01",
    sea2 = "Interface\\Garrison\\ShipyardNavalMap02",
    crest = {
        Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
        Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
    },
    banner = {
        Alliance = Icon("inv_bannerpvp_02"),
        Horde = Icon("inv_bannerpvp_01"),
    },
}

-- Battleship: Garrison Shipyard icons per ship (Alliance / Horde versions where they exist).
local SHIP_ICONS = {
    { "inv_garrison_carrier" },
    { "inv_garrison_dreadnaught" },
    { Alliance = "inv_garrison_alliancecargo", Horde = "inv_garrison_hordecargo", "inv_garrison_cargoship" },
    { Alliance = "inv_garrison_alliancesub", Horde = "inv_garrison_hordesub" },
    { Alliance = "inv_garrison_alliancedestroyer", Horde = "inv_garrison_hordedestroyer" },
}
function A.ShipIcon(i, faction)
    local set = SHIP_ICONS[i]
    if not set then return nil end
    local name = (faction and set[faction]) or set.Alliance or set[1]
    local path = Icon(name)
    if A.HasFile(path) then return path end
    if set[1] and A.HasFile(Icon(set[1])) then return Icon(set[1]) end
    return nil
end

-- Four in a Row: the first player's coins are gold, the second player's silver.
A.COINS = {
    { icon = "inv_misc_coin_01", ring = { 1, 0.8, 0.25 }, name = "Gold" },
    { icon = "inv_misc_coin_03", ring = { 0.82, 0.86, 0.92 }, name = "Silver" },
}
-- Vault Breaker: the six gems (each with a colour for its ring, so they stay easy to tell apart).
A.GEMS = {
    { icon = "inv_misc_gem_ruby_01", color = { 1, 0.25, 0.25 }, name = "Ruby" },
    { icon = "inv_misc_gem_sapphire_01", color = { 0.3, 0.55, 1 }, name = "Sapphire" },
    { icon = "inv_misc_gem_topaz_01", color = { 1, 0.85, 0.2 }, name = "Topaz" },
    { icon = "inv_misc_gem_emerald_01", color = { 0.3, 0.95, 0.35 }, name = "Emerald" },
    { icon = "inv_misc_gem_amethyst_01", color = { 0.75, 0.4, 1 }, name = "Amethyst" },
    { icon = "inv_misc_gem_flamespessarite_01", color = { 1, 0.55, 0.15 }, name = "Spessarite" },
}
function A.GemIcon(n)
    local g = A.GEMS[n]
    if not g then return nil end
    local path = Icon(g.icon)
    if A.HasFile(path) then return path end
    return nil
end

function A.CoinIcon(who)
    local c = A.COINS[who]
    if not c then return nil end
    local path = Icon(c.icon)
    if A.HasFile(path) then return path end
    return nil
end

-- Circular mask used by the game's own unit portraits.
function A.PortraitMask()
    local blizzard = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    if A.HasFile(blizzard) then return blizzard end
    return TEX .. "mask"
end

A.FONT_TITLE = "Fonts\\MORPHEUS.TTF"
A.FONT_BODY = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

function A.TitleFont()
    if A.HasFile(A.FONT_TITLE) then return A.FONT_TITLE end
    return A.FONT_BODY
end

------------------------------------------------------------------------
-- Armies. Index = piece type (1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king).
-- icons: candidate portraits, first existing one is used.
------------------------------------------------------------------------
A.ARMY_ORDER = { "Alliance", "Horde", "Kaldorei", "Ironforge", "Scourge", "Legion", "Blackrock", "OldGods", "Keepers" }

-- Every icon name below was checked against the game's file list (exact spelling:
-- "achievement_leader_ thrall" and "achievement_boss_archimonde " really contain spaces).
-- side: which PvP victory fanfare plays when this army wins. rival: the army the other
-- player gets if both chose the same one.
A.ARMIES = {
    Alliance = {
        name = "Alliance", title = "The Alliance", side = "Alliance", rival = "Horde",
        color = { 0.25, 0.55, 1.00 }, ring = { 0.95, 0.80, 0.35 }, ringDark = { 0.12, 0.22, 0.55 },
        units = {
            { name = "Footman", icons = { Icon("achievement_character_human_male") } },
            { name = "Knight", icons = { Icon("ability_mount_charger"), Icon("ability_mount_ridinghorse") } },
            { name = "Prophet Velen", icons = { Icon("achievement_leader_prophet_velen"), Icon("spell_holy_holybolt") } },
            { name = "Siege Engine", icons = { Icon("ability_vehicle_siegeenginecannon"), Icon("inv_misc_tournaments_banner_human") } },
            { name = "Tyrande", icons = { Icon("achievement_leader_tyrande_whisperwind"), Icon("achievement_character_nightelf_female") } },
            { name = "King Varian", icons = { Icon("achievement_leader_king_varian_wrynn"), Icon("inv_misc_head_human_01") } },
        },
        death = { 540722, 540838 }, cry = { 540696, 540717 },
    },
    Horde = {
        name = "Horde", title = "The Horde", side = "Horde", rival = "Alliance",
        color = { 0.90, 0.18, 0.15 }, ring = { 0.70, 0.12, 0.08 }, ringDark = { 0.25, 0.05, 0.03 },
        units = {
            { name = "Grunt", icons = { Icon("achievement_character_orc_male") } },
            { name = "Wolf Rider", icons = { Icon("ability_mount_blackdirewolf"), Icon("ability_mount_whitedirewolf") } },
            { name = "Cairne", icons = { Icon("achievement_leader_cairne bloodhoof"), Icon("achievement_character_tauren_male") } },
            { name = "Demolisher", icons = { Icon("ability_vehicle_demolisherflamecatapult"), Icon("inv_misc_tournaments_banner_orc") } },
            { name = "Sylvanas", icons = { Icon("achievement_leader_sylvanas"), Icon("achievement_character_undead_female") } },
            { name = "Warchief Thrall", icons = { Icon("achievement_leader_ thrall"), Icon("inv_misc_head_orc_01") } },
        },
        death = { 541234, 541308 }, cry = { 541389, 541391, 541400 },
    },
    Kaldorei = {
        name = "Kaldorei", title = "The Kaldorei", side = "Alliance", rival = "Legion",
        color = { 0.70, 0.50, 1.00 }, ring = { 0.62, 0.48, 0.92 }, ringDark = { 0.12, 0.06, 0.22 },
        units = {
            { name = "Sentinel", icons = { Icon("achievement_character_nightelf_female") } },
            { name = "Nightsaber Rider", icons = { Icon("ability_mount_whitetiger") } },
            { name = "Druid of the Grove", icons = { Icon("spell_nature_forceofnature"), Icon("ability_druid_forceofnature") } },
            { name = "Ancient Guardian", icons = { Icon("achievement_reputation_guardiansofcenarius") } },
            { name = "Illidan", icons = { Icon("achievement_boss_illidan") } },
            { name = "Tyrande", icons = { Icon("achievement_leader_tyrande_whisperwind") } },
        },
        death = { 540868, 540954 }, cry = { 541023, 541025, 541026 },
    },
    Ironforge = {
        name = "Ironforge", title = "Ironforge", side = "Alliance", rival = "Blackrock",
        color = { 0.95, 0.68, 0.35 }, ring = { 0.78, 0.56, 0.30 }, ringDark = { 0.20, 0.12, 0.05 },
        units = {
            { name = "Mountaineer", icons = { Icon("achievement_character_dwarf_male") } },
            { name = "Ram Rider", icons = { Icon("ability_mount_mountainram") } },
            { name = "Gnome Tinker", icons = { Icon("achievement_character_gnome_male") } },
            { name = "Clockwork Golem", icons = { Icon("inv_misc_head_clockworkgnome_01") } },
            { name = "Queen Moira", icons = { Icon("achievement_character_dwarf_female") } },
            { name = "King Magni", icons = { Icon("achievement_leader_king_magni_bronzebeard") } },
        },
        death = { 539885, 539958 }, cry = { 540085, 540088, 540491 },
    },
    Scourge = {
        name = "Scourge", title = "The Scourge", side = "Horde", rival = "Keepers",
        color = { 0.45, 0.90, 0.85 }, ring = { 0.40, 0.78, 0.90 }, ringDark = { 0.03, 0.12, 0.16 },
        units = {
            { name = "Ghoul", icons = { Icon("inv_misc_head_scourge_01"), Icon("ability_ghoulfrenzy") } },
            { name = "Death Knight", icons = { Icon("spell_deathknight_summondeathcharger") } },
            { name = "Kel'Thuzad", icons = { Icon("achievement_boss_kelthuzad_01") } },
            { name = "Abomination", icons = { Icon("achievement_boss_patchwerk") } },
            { name = "Sindragosa", icons = { Icon("achievement_boss_sindragosa") } },
            { name = "The Lich King", icons = { Icon("achievement_boss_lichking") } },
        },
        death = { 549806, 542603, 542596 }, cry = { 542738, 542762 },
    },
    Legion = {
        name = "Burning Legion", title = "The Burning Legion", side = "Horde", rival = "Kaldorei",
        color = { 0.50, 1.00, 0.25 }, ring = { 0.38, 0.82, 0.12 }, ringDark = { 0.05, 0.16, 0.02 },
        units = {
            { name = "Imp", icons = { Icon("spell_shadow_summonimp") } },
            { name = "Felhunter", icons = { Icon("spell_shadow_summonfelhunter") } },
            { name = "Prince Malchezaar", icons = { Icon("achievement_boss_prince_malchezaar") } },
            { name = "Infernal", icons = { Icon("spell_shadow_summoninfernal") } },
            { name = "Kil'jaeden", icons = { Icon("achievement_boss_kiljaedan") } },
            { name = "Archimonde", icons = { Icon("achievement_boss_archimonde "), Icon("achievement_boss_hellfire_archimonde") } },
        },
        death = { 552535, 544141 }, cry = { 552542, 544138 },
    },
    Blackrock = {
        name = "Blackrock", title = "Blackrock Mountain", side = "Horde", rival = "Ironforge",
        color = { 1.00, 0.45, 0.12 }, ring = { 0.30, 0.28, 0.30 }, ringDark = { 0.35, 0.08, 0.02 },
        units = {
            { name = "Blackrock Orc", icons = { Icon("inv_misc_head_orc2_brn"), Icon("inv_misc_head_orc1_brn") } },
            { name = "Black Drake", icons = { Icon("inv_misc_head_dragon_black") } },
            { name = "General Drakkisath", icons = { Icon("achievement_boss_generaldrakkisath") } },
            { name = "Emperor Thaurissan", icons = { Icon("achievement_boss_emperordagranthaurissan") } },
            { name = "Onyxia", icons = { Icon("achievement_boss_onyxia") } },
            { name = "Nefarian", icons = { Icon("achievement_boss_nefarion") } },
        },
        death = { 547392, 547380, 547387 }, cry = { 547393, 547431 },
    },
    OldGods = {
        name = "Old Gods", title = "The Old Gods", side = "Horde", rival = "Keepers",
        color = { 0.72, 0.30, 0.90 }, ring = { 0.45, 0.12, 0.55 }, ringDark = { 0.08, 0.00, 0.12 },
        units = {
            { name = "Faceless One", icons = { Icon("achievement_boss_heraldvolazj") } },
            { name = "Hakkar", icons = { Icon("achievement_boss_hakkar") } },
            { name = "General Vezax", icons = { Icon("achievement_boss_generalvezax_01") } },
            { name = "Ragnaros", icons = { Icon("achievement_boss_ragnaros") } },
            { name = "C'Thun", icons = { Icon("achievement_boss_cthun") } },
            { name = "Yogg-Saron", icons = { Icon("achievement_boss_yoggsaron_01") } },
        },
        death = { 546622, 564846, 558802 }, cry = { 546633, 564829 },
    },
    Keepers = {
        name = "Titan Keepers", title = "The Keepers of Ulduar", side = "Alliance", rival = "OldGods",
        color = { 0.65, 0.88, 1.00 }, ring = { 0.82, 0.86, 0.95 }, ringDark = { 0.10, 0.16, 0.28 },
        units = {
            { name = "Iron Construct", icons = { Icon("achievement_boss_xt002deconstructor_01") } },
            { name = "Mimiron", icons = { Icon("achievement_boss_mimiron_01") } },
            { name = "Hodir", icons = { Icon("achievement_boss_hodir_01") } },
            { name = "Flame Leviathan", icons = { Icon("achievement_boss_theflameleviathan_01"), Icon("achievement_boss_kologarn_01") } },
            { name = "Freya", icons = { Icon("achievement_boss_freya_01") } },
            { name = "Thorim", icons = { Icon("achievement_boss_thorim"), Icon("achievement_boss_algalon_01") } },
        },
        death = { 552626, 552630, 1446824 }, cry = { 552642 },
    },
}

-- Sound entries for every army (death cries and battle cries).
function A.RegisterArmySounds()
    for id, army in pairs(A.ARMIES) do
        A.SOUNDS["death" .. id] = { files = army.death, random = true }
        A.SOUNDS["cry" .. id] = { files = army.cry, random = true }
    end
end

-- Portrait for a piece type of an army, or nil when the client lacks the art.
function A.Portrait(army, t)
    local unit = A.ARMIES[army].units[t]
    if unit.resolved == nil then
        unit.resolved = A.First(unit.icons) or false
    end
    return unit.resolved or nil
end

------------------------------------------------------------------------
-- Character identity (race, sex, class, level, guild) - like the armory.
------------------------------------------------------------------------
local function Safe(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

-- Our own character: { race = "Tauren", sex = 2, class = "WARRIOR", level = 60, guild = "..." }
function A.MyCharInfo()
    local info = {}
    if UnitRace then
        local _, raceFile = UnitRace("player")
        info.race = Safe(raceFile)
    end
    if UnitSex then info.sex = Safe(UnitSex("player")) end
    if UnitClass then
        local _, classFile = UnitClass("player")
        info.class = Safe(classFile)
    end
    if UnitLevel then info.level = Safe(UnitLevel("player")) end
    if GetGuildInfo then
        local guild = Safe(GetGuildInfo("player"))
        if type(guild) == "string" and guild ~= "" then info.guild = guild end
    end
    return info
end

-- Packs identity for a message: "race,sex,class,level" and the guild separately.
function A.PackChar(info)
    return table.concat({ info.race or "", info.sex or "", info.class or "", info.level or "" }, ","),
        (info.guild or ""):gsub("[;,|]", "")
end

local VALID_RACE = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Orc = true, Scourge = true,
    Tauren = true, Troll = true, BloodElf = true, Draenei = true, Goblin = true, Worgen = true, Pandaren = true }
local VALID_CLASS = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
    MAGE = true, WARLOCK = true, DRUID = true, DEATHKNIGHT = true, MONK = true, DEMONHUNTER = true, EVOKER = true }

function A.UnpackChar(packed, guild)
    if type(packed) ~= "string" then return nil end
    local race, sex, class, level = string.match(packed, "^([^,]*),([^,]*),([^,]*),([^,]*)$")
    if not race then return nil end
    local info = {}
    if VALID_RACE[race] then info.race = race end
    sex = tonumber(sex)
    if sex == 2 or sex == 3 then info.sex = sex end
    if VALID_CLASS[class] then info.class = class end
    level = tonumber(level)
    if level and level >= 1 and level <= 100 then info.level = floor(level) end
    if type(guild) == "string" and guild ~= "" and #guild <= 40 then info.guild = guild end
    return info
end

local RACE_ICON = { Human = "human", Dwarf = "dwarf", NightElf = "nightelf", Gnome = "gnome", Orc = "orc",
    Scourge = "undead", Tauren = "tauren", Troll = "troll", BloodElf = "bloodelf", Draenei = "draenei" }
local RACE_NAME = { NightElf = "Night Elf", Scourge = "Undead", BloodElf = "Blood Elf" }

-- Race portrait icon for a character (used when no live portrait is available).
function A.RaceIcon(info)
    local r = info and RACE_ICON[info.race]
    if not r then return nil end
    local file = Icon("achievement_character_" .. r .. "_" .. ((info.sex == 3) and "female" or "male"))
    if A.HasFile(file) then return file end
    return nil
end

function A.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return nil
end

-- "Level 60 Tauren Warrior"
function A.CharLine(info)
    if not info then return "" end
    local parts = {}
    if info.level then parts[#parts + 1] = "Level " .. info.level end
    if info.race then parts[#parts + 1] = RACE_NAME[info.race] or info.race end
    if info.class then
        local name = info.class:sub(1, 1) .. info.class:sub(2):lower()
        if info.class == "DEATHKNIGHT" then name = "Death Knight" elseif info.class == "DEMONHUNTER" then name = "Demon Hunter" end
        parts[#parts + 1] = name
    end
    return table.concat(parts, " ")
end

function A.MyFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Horde" then return "Horde" end
    return "Alliance"
end

function A.IsArmy(id)
    return type(id) == "string" and A.ARMIES[id] ~= nil
end

-- The two sides of a piece style from the local player's point of view: mine, theirs.
-- Classic chess and other non-matchup styles fall back to the player's faction.
function A.Sides(set)
    set = set or (ns.Profile and ns.Profile.me and ns.Profile.PieceSet())
    if set and set.armies and not set.faction then
        local lead = ns.Profile.LeadIndex(set)
        return set.armies[lead], set.armies[3 - lead]
    end
    local mine = A.MyFaction()
    return mine, mine == "Horde" and "Alliance" or "Horde"
end

-- The army the local player leads with the current style.
function A.MyArmy()
    return (A.Sides())
end

function A.Rival(id)
    return id == "Horde" and "Alliance" or "Horde"
end

-- Army for a chess colour (1 white, -1 black) in a game (nil = no game yet), as drawn on
-- this player's screen: their own pieces are their side of the chosen style.
function A.ArmyFor(color, g, set)
    local mine, theirs = A.Sides(set)
    local myColor = (g and g.myColor) or 1
    return color == myColor and mine or theirs
end

function A.UnitName(army, t)
    return A.ARMIES[army].units[t].name
end

-- Crest for an army: the faction emblem for Alliance/Horde, else the leader's portrait.
-- Returns path, isPortrait.
function A.Crest(army)
    if army == "Alliance" or army == "Horde" then
        local file = A.ART.crest[army]
        if A.HasFile(file) then return file, false end
    end
    if A.IsArmy(army) then
        local p = A.Portrait(army, 6)
        if p then return p, true end
    end
    return nil
end

------------------------------------------------------------------------
-- Sounds. Each event lists sound kits (by SOUNDKIT key) and sound files (by file id),
-- tried in order until one plays.
------------------------------------------------------------------------
-- kits: SOUNDKIT key names or numeric sound kit ids. files: FileDataIDs (game sound files).
-- random = true picks a random file first, for variety.
-- Ids from the game data (verified against the community listfile and SoundKitEntry table).
A.SOUNDS = {
    move = { kits = { 838, "IG_ABILITY_ICON_DROP" } },
    select = { kits = { 836, "IG_ABILITY_PAGE_TURN" } },
    -- one-handed sword hitting flesh
    capture = { files = { 567880, 567881, 567883 }, random = true, kits = { "IG_ABILITY_ICON_DROP" } },
    check = { kits = { 8959, "RAID_WARNING" } },
    promote = { kits = { 888, 1440 }, files = { 567431 } },
    castle = { files = { 567863, 567864 }, random = true, kits = { 838 } }, -- shield block
    start = { files = { 567275 }, kits = { 8459, "PVP_THROUGH_QUEUE" } }, -- war drum
    invite = { kits = { 8960, "READY_CHECK" } },
    winAlliance = { kits = { 8455 }, files = { 569678 } },
    winHorde = { kits = { 8454 }, files = { 568480 } },
    lose = { kits = { 847 }, files = { 567459 } },
    draw = { kits = { 878, "IG_QUEST_LIST_COMPLETE" } },
    unlock = { kits = { 31578, "UI_EPICLOOT_TOAST" } },
    click = { kits = { 856, "IG_MAINMENU_OPTION_CHECKBOX_ON" } },
    -- Battleship
    bsFire = { files = { 566101, 566317 }, random = true, kits = { 838 } }, -- cannon blast
    bsSplash = { files = { 540233, 540231 }, random = true }, -- shot lands in the water
    bsHit = { files = { 565499, 565642 }, random = true }, -- barrel explosion
    bsBoom = { files = { 565570 } }, -- large explosion (ship sunk)
    bsSunk = { files = { 540232 } }, -- giant splash (ship goes down)
    bsBell = { files = { 537384 }, kits = { 8960 } }, -- ship's bell: battle stations
    bsTurn = { files = { 1129273, 1129274, 1129275 }, random = true, kits = { 8960 } }, -- ship bell chime: your turn
    bsHorn = { files = { 567094 } }, -- lighthouse foghorn: the battle begins
    bsWaves = { files = { 839242 } }, -- ocean wave
    bsGulls = { files = { 559721, 559716 }, random = true }, -- seagulls
    bsCreak = { files = { 895858, 895860, 895862, 895864, 895866, 895868 }, random = true, kits = { 838 } }, -- ship timbers
    bsParrot = { files = { 558085, 558086, 558087 }, random = true }, -- the parrot mocks a miss
    bsArr = { files = { 540807, 540810, 540813 }, random = true }, -- pirate shout: enemy ship sunk
    bsCheer = { files = { 540808, 540806 }, random = true }, -- pirate cheer: victory
    bsDying = { files = { 540809 } }, -- pirate death: one of yours goes down
    bsSonar = { files = { 569006, 568683 }, random = true }, -- sonar ping: a submarine sinks
    -- Four in a Row
    c4Drop = { files = { 942678, 942680, 942682, 942684, 942686, 942688 }, random = true, kits = { 856 } }, -- goblin coin toss
    c4Land = { files = { 567428, 567413 }, random = true, kits = { 856 } }, -- coins clink into place
    c4Turn = { files = { 567413 }, kits = { 8960 } }, -- a heavy coin: your turn
    c4Start = { kits = { 25478, 8459 } }, -- the match begins
    c4Cheer = { files = { 567388, 567385, 567383 }, random = true }, -- the tavern crowd cheers
    c4Applause = { files = { 544894 } }, -- polite applause (a draw)
    -- Vault Breaker
    vbGem = { files = { 565450 }, kits = { 856 } }, -- a gem clicks into its socket
    vbLock = { files = { 565409 }, kits = { 838 } }, -- the gearbox closes: vault sealed / guess locked in
    vbGears = { files = { 565319, 565401 }, random = true, kits = { 856 } }, -- tumblers turn: pins come back
    vbClick = { files = { 546260, 546262, 546264, 546266, 546268 }, random = true, kits = { 856 } }, -- clockwork clicks
    vbOpen = { files = { 537918, 565313 }, kits = { 31578 } }, -- a vault unlocks
    vbChest = { files = { 565749, 565636 }, random = true }, -- treasure: you cracked it
    vbShut = { files = { 565478 }, kits = { 847 } }, -- an iron door slams: your vault was cracked
    vbTurn = { files = { 565752 }, kits = { 8960 } }, -- a new round
}

A.RegisterArmySounds()

local function Played(ok, willPlay)
    -- Older clients return nothing; treat that as success.
    return ok and willPlay ~= false
end

function A.Play(key)
    if not (ns.db and ns.db.settings.sound) then return end
    local s = A.SOUNDS[key]
    if not s then return end
    if s.files and PlaySoundFile and #s.files > 0 then
        local n = #s.files
        local first = s.random and math.random(1, n) or 1
        for k = 0, n - 1 do
            local id = s.files[(first - 1 + k) % n + 1]
            if Played(pcall(PlaySoundFile, id, "SFX")) then return end
        end
    end
    if s.kits and PlaySound then
        for i = 1, #s.kits do
            local id = s.kits[i]
            if type(id) == "string" then id = SOUNDKIT and SOUNDKIT[id] end
            if id and Played(pcall(PlaySound, id, "SFX")) then return end
        end
    end
end

------------------------------------------------------------------------
-- Tweens: tiny animation engine driven by one OnUpdate.
------------------------------------------------------------------------
local tweens = {}
local driver = CreateFrame("Frame")

-- An animation error should never break the game, but should still be visible.
function A.ReportError(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, "Flightpath Legends animation: " .. tostring(err)) end
end

local function Step(_, elapsed)
    local i = 1
    while i <= #tweens do
        local tw = tweens[i]
        tw.t = tw.t + elapsed
        local p = tw.duration > 0 and math.min(1, tw.t / tw.duration) or 1
        local ok, err = pcall(tw.step, tw.ease and tw.ease(p) or p)
        if not ok then A.ReportError(err) end
        if p >= 1 or not ok or tw.cancelled then
            table.remove(tweens, i)
            if tw.done and not tw.cancelled then
                local ok2, err2 = pcall(tw.done)
                if not ok2 then A.ReportError(err2) end
            end
        else
            i = i + 1
        end
    end
    if #tweens == 0 then driver:SetScript("OnUpdate", nil) end
end

A.Ease = {
    outCubic = function(p) return 1 - (1 - p) ^ 3 end,
    inQuad = function(p) return p * p end,
    outBack = function(p)
        local c1, c3 = 1.70158, 2.70158
        return 1 + c3 * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
    end,
}

-- step(progress 0..1) is called every frame; done() once at the end. Returns a handle
-- whose :Cancel() stops it. With animations off, it jumps straight to the end.
function A.Tween(duration, step, done, ease)
    local tw = { t = 0, duration = duration, step = step, done = done, ease = ease }
    function tw:Cancel() self.cancelled = true end
    if ns.db and ns.db.settings.animations == false then
        pcall(step, 1)
        if done then pcall(done) end
        return tw
    end
    tweens[#tweens + 1] = tw
    driver:SetScript("OnUpdate", Step)
    return tw
end

function A.Animating()
    return #tweens > 0
end
