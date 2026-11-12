-- ChessPvP: Warcraft look and feel - game art lookups (with safe fallbacks), the two armies,
-- sounds, and a small tween engine for animations.
local _, ns = ...

local A = {}
ns.Assets = A

local TEX = "Interface\\AddOns\\ChessPvP\\Textures\\"
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
    crest = {
        Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
        Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
    },
    banner = {
        Alliance = Icon("inv_bannerpvp_02"),
        Horde = Icon("inv_bannerpvp_01"),
    },
}

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
A.ARMIES = {
    Alliance = {
        name = "Alliance",
        color = { 0.25, 0.55, 1.00 },
        ring = { 0.95, 0.80, 0.35 }, -- gold
        ringDark = { 0.12, 0.22, 0.55 },
        units = {
            { name = "Footman", icons = { Icon("achievement_character_human_male") } },
            { name = "Knight", icons = { Icon("ability_mount_charger"), Icon("ability_mount_ridinghorse") } },
            { name = "Prophet Velen", short = "Priest", icons = { Icon("achievement_leader_prophet_velen"), Icon("spell_holy_holybolt") } },
            { name = "Siege Engine", icons = { Icon("ability_vehicle_siegeenginecannon"), Icon("inv_misc_tournaments_banner_human"), Icon("inv_guild_standard_alliance_a") } },
            { name = "Tyrande", icons = { Icon("achievement_leader_tyrande_whisperwind"), Icon("achievement_character_nightelf_female") } },
            { name = "King Varian", icons = { Icon("achievement_leader_king_varian_wrynn"), Icon("inv_misc_head_human_01") } },
        },
    },
    Horde = {
        name = "Horde",
        color = { 0.90, 0.18, 0.15 },
        ring = { 0.70, 0.12, 0.08 }, -- blood red
        ringDark = { 0.25, 0.05, 0.03 },
        units = {
            { name = "Grunt", icons = { Icon("achievement_character_orc_male") } },
            { name = "Wolf Rider", icons = { Icon("ability_mount_blackdirewolf"), Icon("ability_mount_whitedirewolf") } },
            { name = "Cairne", short = "Chieftain", icons = { Icon("achievement_leader_cairne bloodhoof"), Icon("achievement_character_tauren_male") } },
            { name = "Demolisher", icons = { Icon("ability_vehicle_demolisherflamecatapult"), Icon("inv_misc_tournaments_banner_orc"), Icon("inv_guild_standard_horde_a") } },
            { name = "Sylvanas", icons = { Icon("achievement_leader_sylvanas"), Icon("achievement_character_undead_female") } },
            { name = "Warchief Thrall", icons = { Icon("achievement_leader_ thrall"), Icon("achievement_leader_thrall"), Icon("inv_misc_head_orc_01") } },
        },
    },
}

-- Portrait for a piece type of an army, or nil when the client lacks the art.
function A.Portrait(army, t)
    local unit = A.ARMIES[army].units[t]
    if unit.resolved == nil then
        unit.resolved = A.First(unit.icons) or false
    end
    return unit.resolved or nil
end

-- The local player's faction leads their own colour; the opponent gets the other army.
function A.MyFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Horde" then return "Horde" end
    return "Alliance"
end

local function Other(f) return f == "Horde" and "Alliance" or "Horde" end

-- Army for a chess colour (1 white, -1 black) in a game (nil = no game yet).
function A.ArmyFor(color, g)
    local mine = A.MyFaction()
    local myColor = g and g.myColor
    if not myColor then
        -- Pass & play, spectating, idle board: white leads the player's faction.
        return color == 1 and mine or Other(mine)
    end
    return color == myColor and mine or Other(mine)
end

function A.UnitName(army, t)
    return A.ARMIES[army].units[t].name
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
    -- death cries of the fallen piece's army
    deathAlliance = { files = { 540722, 540838 }, random = true },
    deathHorde = { files = { 541234, 541308 }, random = true },
    -- battle cries when a game starts
    cryAlliance = { files = { 540696, 540717 }, random = true },
    cryHorde = { files = { 541389, 541391, 541400 }, random = true },
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
}

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
    if handler then pcall(handler, "ChessPvP animation: " .. tostring(err)) end
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
