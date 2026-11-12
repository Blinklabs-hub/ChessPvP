-- ChessPvP: core namespace, utilities, saved variables and slash commands.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = "1.1.0"
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
-- Player identity:
--   Retail/Classic: "Name-Realm".
--   WoW Forever:    "First Surname". Forever is one server without realms, and only the
--                   first name + surname combination is unique (either part alone can be
--                   shared). Name APIs return the surname where retail returns the realm.
-- The identity is also the whisper target (see ns.WhisperTarget).

-- Optional resolver for a single word typed on Forever ("Keepingcalm" -> "Just Keepingcalm"),
-- set by Profile.lua once it knows which players have been seen.
ns.ResolveSingleName = nil

local function Trim(s)
    return string.match(s, "^%s*(.-)%s*$")
end

-- Normalises any form of a player name into the identity, or nil when empty.
function ns.FullName(name)
    if type(name) ~= "string" or ns.IsSecret(name) then return nil end
    name = Trim(name)
    if name == "" then return nil end
    if ns.isForever then
        -- No realms here: a hyphen can only be a "First-Surname" join.
        name = string.gsub(name, "%-", " ")
        name = Trim(string.gsub(name, "%s+", " "))
        if name == "" then return nil end
        if not string.find(name, " ", 1, true) and ns.ResolveSingleName then
            name = ns.ResolveSingleName(name) or name
        end
        return name
    end
    local base, realm = string.match(name, "^([^%-]+)%-(.+)$")
    if not base then base = name end
    base = string.gsub(base, "%s+", "")
    if base == "" then return nil end
    if realm then realm = string.gsub(realm, "%s+", "") end
    if not realm or realm == "" then realm = ns.realm or "" end
    return base .. "-" .. realm
end

-- Name for display: drops our own realm on retail; Forever names are shown in full.
function ns.ShortName(full)
    if not full then return "?" end
    if ns.isForever then return full end
    local name, realm = string.match(full, "^([^-]+)-(.+)$")
    if name and (realm == ns.realm or realm == "") then return name end
    return full
end

-- What SendAddonMessage needs as a whisper target.
function ns.WhisperTarget(full)
    return ns.ShortName(full)
end

function ns.SameName(a, b)
    return a ~= nil and b ~= nil and string.lower(a) == string.lower(b)
end

-- Identity of the player behind a unit ("player", "target", ...), or nil.
function ns.UnitPlayerName(unit)
    local n, r = UnitName(unit)
    if type(n) ~= "string" or ns.IsSecret(n) or n == "" then return nil end
    if ns.IsSecret(r) or type(r) ~= "string" then r = nil end
    if ns.isForever then
        if r and r ~= "" then return ns.FullName(n .. " " .. r) end
        local full = GetUnitName and GetUnitName(unit, true)
        if type(full) == "string" and not ns.IsSecret(full) and full ~= "" then return ns.FullName(full) end
        return ns.FullName(n)
    end
    if r and r ~= "" then return ns.FullName(n .. "-" .. r) end
    return ns.FullName(n)
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

-- Sounds live in Assets.lua (loaded later); this is just a shortcut.
function ns.Sound(key)
    if ns.Assets then ns.Assets.Play(key) end
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
    animations = true,
    autoCollapse = true,
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

-- Versions 1.0.0 and 1.0.1 used wrong identities on Forever ("First-Surname" and
-- "First-Realm"). Move the profile to the correct key, keeping whichever has played most,
-- and drop ladder caches whose names were keyed the old way (they refill by themselves).
local NAME_FORMAT = 2

local function MigrateLegacyKeys(db)
    if not ns.isForever or (db.nameFormat or 0) >= NAME_FORMAT then return end
    db.nameFormat = NAME_FORMAT
    local first, second = UnitName("player")
    if type(first) ~= "string" or ns.IsSecret(first) then return end
    local candidates = { first .. "-" .. ns.realm }
    if type(second) == "string" and not ns.IsSecret(second) and second ~= "" then
        table.insert(candidates, 1, first .. "-" .. second)
    end
    local function Played(p)
        return (p.games or 0) + (p.w or 0) + (p.l or 0) + (p.d or 0)
    end
    local best = db.chars[ns.me]
    for _, key in ipairs(candidates) do
        local p = db.chars[key]
        if key ~= ns.me and type(p) == "table" then
            if not best or Played(p) > Played(best) then best = p end
            db.chars[key] = nil
        end
    end
    if best then
        best.active = nil -- an unfinished game from the old version cannot be resumed
        best.recent = {}
        db.chars[ns.me] = best
    end
    db.realms = {}
end

ns.RegisterEvent("PLAYER_LOGIN", function()
    ns.isForever = DetectForever()
    ns.realm = RealmName()
    ns.me = ns.UnitPlayerName("player")
    if not ns.me then
        -- Should not happen; fall back to the plain name.
        ns.me = ns.FullName(UnitName("player")) or "Unknown"
    end
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
            target = ns.UnitPlayerName("target") or ""
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
            ns.Print("target UnitName: " .. S(UnitName("target")) .. " -> " .. tostring(ns.UnitPlayerName("target")))
        end
        local A = ns.Assets
        for _, army in ipairs({ "Alliance", "Horde" }) do
            local found = {}
            for t = 1, 6 do
                found[t] = A.ARMIES[army].units[t].name .. (A.Portrait(army, t) and "" or " (missing)")
            end
            ns.Print(army .. " art: " .. table.concat(found, ", "))
        end
        ns.Print("faction: " .. A.MyFaction() .. ", title font: " .. tostring(A.HasFile(A.FONT_TITLE)))
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
