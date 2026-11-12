-- ChessPvP: core namespace, utilities, saved variables and slash commands.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = "1.0.0"
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

-- "Name" -> "Name-Realm" (using our own realm when none is given).
function ns.FullName(name)
    if not name or name == "" then return nil end
    if string.find(name, "-", 1, true) then return name end
    return name .. "-" .. (ns.realm or "")
end

-- "Name-Realm" -> "Name" when the realm is ours, otherwise unchanged.
function ns.ShortName(full)
    if not full then return "?" end
    local name, realm = string.match(full, "^([^-]+)-(.+)$")
    if name and realm == ns.realm then return name end
    return full
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

ns.RegisterEvent("PLAYER_LOGIN", function()
    local name, realm = UnitFullName("player")
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    ns.realm = realm
    ns.me = name .. "-" .. realm
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
            local n, r = UnitName("target")
            if n and not ns.IsSecret(n) then
                target = (r and r ~= "") and (n .. "-" .. r) or n
            end
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
    else
        Help()
    end
end

function ChessPvP_OnAddonCompartmentClick()
    ns.UI.Toggle()
end
