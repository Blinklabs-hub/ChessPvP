-- ChessPvP: core namespace, utilities, saved variables and slash commands.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = "1.0.1"
ns.PROTO = 1 -- network protocol version; bump when messages change incompatibly
ChessPvP = ns -- exposed for debugging and the addon compartment

------------------------------------------------------------------------
-- Internal event bus (used both for WoW events and addon events)
------------------------------------------------------------------------
local callbacks = {}

function ns.On(event, fn)
    local list = callbacks[event]
    if not list then
        list = {}
        callbacks[event] = list
    end
    list[#list + 1] = fn
end

function ns.Fire(event, ...)
    local list = callbacks[event]
    if list then
        for i = 1, #list do
            list[i](...)
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    ns.Fire(event, ...)
end)

function ns.RegisterEvent(event, fn)
    -- Unknown events raise an error on modern clients, so guard the call.
    pcall(eventFrame.RegisterEvent, eventFrame, event)
    ns.On(event, fn)
end

------------------------------------------------------------------------
-- Utilities
------------------------------------------------------------------------
function ns.Print(msg)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage("|cffffd100ChessPvP:|r " .. tostring(msg))
    end
end

function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

function ns.Split(str, sep)
    local out, n = {}, 0
    local start = 1
    while true do
        local i = string.find(str, sep, start, true)
        n = n + 1
        if not i then
            out[n] = string.sub(str, start)
            break
        end
        out[n] = string.sub(str, start, i - 1)
        start = i + 1
    end
    return out
end

function ns.Join(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do
        t[i] = tostring((select(i, ...)))
    end
    return table.concat(t, ";")
end

function ns.Now()
    return GetTime()
end

function ns.ServerTime()
    return GetServerTime()
end

function ns.After(seconds, fn)
    C_Timer.After(seconds, fn)
end

-- Players are identified internally as "Firstname-Realm".
--
-- WoW Forever characters also have a surname ("Muke Spiteri"). Name APIs return it where
-- retail returns the realm, and some strings contain it after a space. Surnames are never
-- part of a player's identity here: only the first word of a name is kept.
--
-- Accepts "Name", "Name-Realm", "Name Surname", "Name Surname-Realm" (any capitalisation of
-- the realm part is kept as given) and returns "Name-Realm", or nil when empty.
function ns.FullName(name)
    if type(name) ~= "string" or ns.IsSecret(name) then return nil end
    name = string.match(name, "^%s*(.-)%s*$")
    if name == "" then return nil end
    local base, realm = string.match(name, "^([^%-]+)%-(.+)$")
    if not base then base = name end
    base = string.match(base, "^(%S+)") -- drop a surname
    if not base then return nil end
    if realm then realm = string.gsub(realm, "%s+", "") end
    if not realm or realm == "" then realm = ns.realm or "" end
    return base .. "-" .. realm
end

-- "Name-Realm" -> "Name" when the realm is ours, otherwise unchanged.
-- This is also the form used as a whisper target.
function ns.ShortName(full)
    if not full then return "?" end
    local name, realm = string.match(full, "^([^-]+)-(.+)$")
    if name and (realm == ns.realm or realm == "") then return name end
    return full
end

function ns.SameName(a, b)
    return a ~= nil and b ~= nil and string.lower(a) == string.lower(b)
end

-- First name of a unit, without surname (Forever) or realm.
function ns.UnitFirstName(unit)
    local n, r = UnitName(unit)
    if type(n) ~= "string" or ns.IsSecret(n) then return nil end
    n = string.match(n, "^(%S+)")
    if not n then return nil end
    -- On retail the second value is a realm for players from other realms. On Forever it is
    -- a surname, so it is only used when the game is not Forever.
    if not ns.isForever and type(r) == "string" and not ns.IsSecret(r) and r ~= "" then
        return n .. "-" .. string.gsub(r, "%s+", "")
    end
    return n
end

function ns.FormatClock(seconds)
    if seconds < 0 then seconds = 0 end
    if seconds < 20 then
        local tenths = math.floor(seconds * 10)
        return string.format("%d:%02d.%d", math.floor(tenths / 600), math.floor(tenths / 10) % 60, tenths % 10)
    end
    local s = math.floor(seconds + 0.999)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function ns.NewId()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local t = {}
    for i = 1, 8 do
        local k = math.random(1, #chars)
        t[i] = string.sub(chars, k, k)
    end
    return table.concat(t)
end

local SOUNDS = {
    move = { "IG_ABILITY_ICON_DROP", "IG_CHARACTER_INFO_TAB" },
    capture = { "IG_BACKPACK_CLOSE", "IG_ABILITY_ICON_DROP" },
    check = { "ALARM_CLOCK_WARNING_3", "RAID_WARNING" },
    invite = { "READY_CHECK", "IG_PLAYER_INVITE" },
    win = { "UI_GARRISON_MISSION_COMPLETE_MISSION_SUCCESS", "IG_QUEST_LIST_COMPLETE" },
    lose = { "IG_QUEST_FAILED", "IG_MAINMENU_CLOSE" },
    unlock = { "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
    click = { "IG_MAINMENU_OPTION_CHECKBOX_ON" },
}

function ns.Sound(key)
    if not (ns.db and ns.db.settings.sound) then return end
    local names = SOUNDS[key]
    if not names or not SOUNDKIT or not PlaySound then return end
    for i = 1, #names do
        local id = SOUNDKIT[names[i]]
        if id then
            pcall(PlaySound, id, "SFX")
            return
        end
    end
end

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------
local SETTING_DEFAULTS = {
    sound = true,
    allowSpectators = true,
    dnd = false, -- auto-decline challenges
    showLauncher = true,
    showLegal = true,
    scale = 1,
}

ns.RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    if type(ChessPvPDB) ~= "table" then ChessPvPDB = {} end
    local db = ChessPvPDB
    db.settings = db.settings or {}
    for k, v in pairs(SETTING_DEFAULTS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    db.chars = db.chars or {}
    db.realms = db.realms or {}
    ns.db = db
end)

local function DetectForever()
    if WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then return true end
    if WOW_PROJECT_ID == 18 then return true end
    local _, _, _, toc = GetBuildInfo()
    if toc and toc >= 16000 and toc < 17000 then return true end
    local full = GetUnitName and GetUnitName("player")
    return type(full) == "string" and not ns.IsSecret(full) and string.find(full, " ", 1, true) ~= nil
end

local function RealmName()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(realm) ~= "string" or realm == "" then
        realm = string.gsub(GetRealmName() or "", "[%s%-]", "")
    end
    return realm
end

-- Earlier versions keyed the profile by "Firstname-Surname" on Forever (the surname was
-- mistaken for the realm). Move that data to the correct key.
local function MigrateLegacyKeys(db)
    local first, second = UnitFullName("player")
    if type(second) ~= "string" or second == "" or second == ns.realm then return end
    local legacy = first .. "-" .. second
    if legacy == ns.me then return end
    if db.chars[legacy] and not db.chars[ns.me] then
        db.chars[ns.me] = db.chars[legacy]
    end
    db.chars[legacy] = nil
    -- The ladder cache under the fake realm has wrongly keyed names: drop it, it refills.
    db.realms[second] = nil
end

ns.RegisterEvent("PLAYER_LOGIN", function()
    ns.isForever = DetectForever()
    ns.realm = RealmName()
    local first = ns.UnitFirstName("player") or UnitName("player")
    first = string.match(first, "^([^%-]+)") -- never a realm part for ourselves
    ns.myName = first
    ns.me = first .. "-" .. ns.realm
    MigrateLegacyKeys(ns.db)
    ns.Fire("CHESS_READY")
end)

------------------------------------------------------------------------
-- Slash commands and addon compartment
------------------------------------------------------------------------
local function Help()
    ns.Print("commands:")
    ns.Print("  /chess - open or close the chess window")
    ns.Print("  /chess challenge <name> - challenge a player (or your target)")
    ns.Print("  /chess accept | decline - answer the latest challenge")
    ns.Print("  /chess resign - resign the current game")
    ns.Print("  /chess reset - move the window back to the middle of the screen")
    ns.Print("  /chess debug - show name and connection details (for bug reports)")
end

SLASH_CHESSPVP1 = "/chess"
SLASH_CHESSPVP2 = "/chesspvp"
SlashCmdList["CHESSPVP"] = function(msg)
    msg = msg or ""
    local cmd, rest = string.match(msg, "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "challenge" or cmd == "c" then
        local target = rest
        if target == "" and UnitExists("target") and UnitIsPlayer("target") then
            target = ns.UnitFirstName("target") or ""
        end
        if not target or target == "" then
            ns.Print("usage: /chess challenge <name>")
        else
            ns.Game.Invite(target)
        end
    elseif cmd == "accept" then
        ns.Game.AnswerLatest(true)
    elseif cmd == "decline" then
        ns.Game.AnswerLatest(false)
    elseif cmd == "resign" then
        ns.Game.Resign()
    elseif cmd == "reset" then
        ns.UI.ResetPosition()
    elseif cmd == "debug" then
        local function S(...)
            local t = {}
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                t[i] = ns.IsSecret(v) and "<secret>" or ("'" .. tostring(v) .. "'")
            end
            return table.concat(t, ", ")
        end
        ns.Print("version " .. ns.VERSION .. ", forever=" .. tostring(ns.isForever) .. ", project=" .. tostring(WOW_PROJECT_ID))
        ns.Print("UnitName: " .. S(UnitName("player")))
        ns.Print("UnitFullName: " .. S(UnitFullName("player")))
        ns.Print("GetUnitName: " .. S(GetUnitName and GetUnitName("player", true)))
        ns.Print("realm: " .. S(GetRealmName(), GetNormalizedRealmName and GetNormalizedRealmName()))
        ns.Print("me: " .. tostring(ns.me) .. ", channel: " .. tostring(ns.Comm.ChannelId()))
        if UnitExists("target") then
            ns.Print("target UnitName: " .. S(UnitName("target")) .. " -> " .. tostring(ns.UnitFirstName("target")))
        end
        local senders = ns.Comm.recentSenders
        for i = 1, #senders do
            ns.Print("heard from: '" .. senders[i][1] .. "' -> " .. senders[i][2])
        end
    else
        Help()
    end
end

function ChessPvP_OnAddonCompartmentClick()
    ns.UI.Toggle()
end
