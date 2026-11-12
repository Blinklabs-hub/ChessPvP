-- Test harness: loads the addon into mocked WoW environments and simulates several clients.
local FILES = { "Core.lua", "Hash.lua", "Data.lua", "Assets.lua", "Engine.lua", "AI.lua", "Profile.lua", "Comm.lua", "Ledger.lua", "Game.lua", "Battleship.lua", "UI_Widgets.lua", "UI_Board.lua", "UI_Play.lua", "UI_Tabs.lua", "UI_Main.lua", "UI_Profile.lua" }
local REALM = "TestRealm"

-- Like WoW's LuaBitOp "bit" library: 32-bit operations returning signed numbers.
-- Arithmetic only (the test VM's integers are 32-bit, so native operators cannot be used).
local TWO32 = 4294967296.0
local function U32(x) x = math.floor(x) % TWO32; if x < 0 then x = x + TWO32 end; return x end
local function S32(x) if x >= 2147483648 then return x - TWO32 end; return x end
local NIB = {} -- NIB[op][a][b] for 4-bit values
for _, op in ipairs({ "and", "or", "xor" }) do
    NIB[op] = {}
    for x = 0, 15 do
        NIB[op][x] = {}
        for y = 0, 15 do
            local r, bitv = 0, 1
            for _ = 1, 4 do
                local xb, yb = math.floor(x / bitv) % 2, math.floor(y / bitv) % 2
                local v = (op == "and" and xb * yb) or (op == "or" and math.max(xb, yb)) or ((xb + yb) % 2)
                r = r + v * bitv
                bitv = bitv * 2
            end
            NIB[op][x][y] = r
        end
    end
end
local function Op2(op, x, y)
    x, y = U32(x), U32(y)
    local r, mul = 0, 1
    for _ = 1, 8 do
        r = r + NIB[op][x % 16][y % 16] * mul
        x, y, mul = math.floor(x / 16), math.floor(y / 16), mul * 16
    end
    return r
end
local function Fold(op, init, ...)
    local r = init
    for _, v in ipairs({ ... }) do r = Op2(op, r, v) end
    return S32(r)
end
BitLib = {
    band = function(...) return Fold("and", TWO32 - 1, ...) end,
    bor = function(...) return Fold("or", 0, ...) end,
    bxor = function(...) return Fold("xor", 0, ...) end,
    bnot = function(a) return S32(TWO32 - 1 - U32(a)) end,
    lshift = function(a, n) return S32((U32(a) * 2 ^ (n % 32)) % TWO32) end,
    rshift = function(a, n) return S32(math.floor(U32(a) / 2 ^ (n % 32))) end,
}

T = 1000 -- virtual clock (seconds)
local timers = {}
local netQueue = {}
clients = {}
-- forever = true simulates WoW Forever as observed in game (/chess debug):
--   UnitName/UnitFullName("player") -> "First", "Surname"; GetUnitName -> "First Surname";
--   CHAT_MSG_ADDON senders arrive as "First Surname" (no realm);
--   only the full "First Surname" works as a whisper target (either half can be shared).
-- Otherwise retail: senders "Name-Realm", whispers to "Name" or "Name-Realm".
net = { dropRate = 0, log = false, sent = 0, forever = false }

local function SenderName(c)
    if net.forever then return c.name .. " " .. c.surname end
    return c.full
end

local function MatchesTarget(c, target)
    target = tostring(target):lower()
    if net.forever then return target == (c.name .. " " .. c.surname):lower() end
    return target == c.name:lower() or target == c.full:lower()
end

local function readFile(path)
    return assert(SOURCES[path:match("[^/]+$")], "missing " .. path)
end
os.clock = function() return NOW_MS() / 1000 end
os.exit = os.exit or function() error("tests failed") end

-- Universal mock UI object ---------------------------------------------------
local function NewObj(client, kind)
    local o = { __scripts = {}, __shown = true, __kind = kind, __client = client }
    local mt = {}
    mt.__index = function(t, k)
        if k == "SetScript" then
            return function(self, name, fn) self.__scripts[name] = fn end
        elseif k == "GetScript" then
            return function(self, name) return self.__scripts[name] end
        elseif k == "RegisterEvent" then
            return function(self, ev)
                client.events[ev] = client.events[ev] or {}
                table.insert(client.events[ev], self)
            end
        elseif k == "Show" then
            return function(self)
                local was = self.__shown
                self.__shown = true
                if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
            end
        elseif k == "Hide" then
            return function(self)
                local was = self.__shown
                self.__shown = false
                if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
            end
        elseif k == "IsShown" then
            return function(self) return self.__shown end
        elseif k == "CreateTexture" or k == "CreateFontString" then
            return function() return NewObj(client, k) end
        elseif k == "SetText" then
            return function(self, v) self.__text = v end
        elseif k == "GetText" then
            return function(self) return self.__text end
        elseif k == "SetChecked" then
            return function(self, v) self.__checked = v end
        elseif k == "GetChecked" then
            return function(self) return self.__checked end
        elseif k == "GetFrameLevel" then
            return function() return 1 end
        elseif k == "GetPoint" then
            return function() return "CENTER", nil, "CENTER", 0, 0 end
        elseif k == "Click" then
            return function(self, button) if self.__scripts.OnClick then self.__scripts.OnClick(self, button or "LeftButton") end end
        end
        if type(k) == "string" and k:match("^[A-Z]") then
            return function() return nil end
        end
        return nil
    end
    setmetatable(o, mt)
    if kind == "Frame" or kind == "Button" or kind == "CheckButton" or kind == "EditBox" then
        table.insert(client.frames, o)
    end
    return o
end

local function deliver(client, ...)
    local list = client.events["CHAT_MSG_ADDON"]
    if list and not client.offline then
        for _, f in ipairs(list) do f.__scripts.OnEvent(f, "CHAT_MSG_ADDON", ...) end
    end
end

function NewClient(name, savedDB, surname)
    local client = { name = name, surname = surname or (name .. "son"), full = name .. "-" .. REALM, events = {}, frames = {}, joined = false, chat = {}, filters = {} }
    local env = {}
    client.env = env
    setmetatable(env, { __index = _G })
    env._G = env
    env.unpack = table.unpack
    env.FlightpathLegendsDB = savedDB
    env.UIParent = NewObj(client, "UIParent")
    env.GameTooltip = NewObj(client, "Tooltip")
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.NUM_CHAT_WINDOWS = 2
    env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
    env.SOUNDKIT = { IG_ABILITY_ICON_DROP = 1, READY_CHECK = 2 }
    env.bit = BitLib
    client.sounds, client.warnings, client.flashes = {}, {}, 0
    env.PlaySound = function(id) table.insert(client.sounds, id) end
    env.RaidWarningFrame = {}
    env.RaidNotice_AddMessage = function(_, text) table.insert(client.warnings, text) end
    env.FlashClientIcon = function() client.flashes = client.flashes + 1 end
    -- Sound files played (by FileDataID); net.missingSounds makes them fail to play.
    client.soundFiles = {}
    env.PlaySoundFile = function(id)
        if net.missingSounds then return false end
        table.insert(client.soundFiles, id)
        return true, 1
    end
    -- Game art lookups: net.missingArt simulates a client without the Warcraft art.
    env.GetFileIDFromPath = function(path)
        if net.missingArt and not path:find("AddOns", 1, true) then return nil end
        return 100000 + #path
    end
    env.UnitFactionGroup = function() return client.faction or "Alliance" end
    -- Character identity (only the player's own character can be read)
    env.UnitRace = function(unit)
        if unit ~= "player" then return nil end
        local r = client.race or ((client.faction == "Horde") and "Tauren" or "Human")
        return r, r
    end
    env.UnitClass = function(unit)
        if unit ~= "player" then return nil end
        return "Warrior", client.class or "WARRIOR"
    end
    env.UnitSex = function(unit) return unit == "player" and (client.sex or 2) or nil end
    env.UnitLevel = function(unit) return unit == "player" and (client.level or 60) or nil end
    env.GetGuildInfo = function(unit) return unit == "player" and client.guild or nil end
    env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    env.SetPortraitTexture = function(tex, unit) client.portraits = (client.portraits or 0) + 1 end
    -- Lua errors (including ones reported by the animation engine) fail the test run.
    client.errors = {}
    env.geterrorhandler = function() return function(msg) table.insert(client.errors, msg); print("LUA ERROR (" .. name .. "): " .. tostring(msg)) end end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(client.chat, msg); if net.log then print("[" .. name .. "] " .. msg) end end }
    env.CreateFrame = function(kind) return NewObj(client, kind) end
    env.GetTime = function() return T end
    env.GetServerTime = function() return math.floor(1700000000 + T) end
    env.debugprofilestop = function() return os.clock() * 1000 end
    if net.forever then
        env.WOW_PROJECT_ID = 18
        env.WOW_PROJECT_CAMELOT = 18
    end
    env.GetBuildInfo = function() return "1.60.1", "70338", "", net.forever and 16001 or 120105 end
    env.GetRealmName = function() return REALM end
    env.UnitFullName = function() return name, net.forever and client.surname or REALM end
    env.GetUnitName = function(unit)
        if unit == "player" then return net.forever and (name .. " " .. client.surname) or name end
        local t = client.target
        if unit == "target" and t then return net.forever and (t.name .. " " .. t.surname) or t.name end
    end
    env.UnitName = function(unit)
        if unit == "player" then
            if net.forever then return name, client.surname end
            return name
        end
        local t = client.target
        if unit == "target" and t then
            if net.forever then return t.name, t.surname end
            return t.name
        end
    end
    env.UnitExists = function(unit) return unit == "player" or (unit == "target" and client.target ~= nil) end
    env.UnitIsPlayer = function(unit) return env.UnitExists(unit) end
    env.GetNormalizedRealmName = function() return REALM end
    env.GetChannelName = function() return client.joined and 5 or 0 end
    -- client.noChannel simulates a client that cannot join the hidden channel.
    env.JoinTemporaryChannel = function() if not client.noChannel then client.joined = true end end
    env.IsInGuild = function() return client.guild ~= nil end
    env.IsInGroup = function() return client.party ~= nil end
    env.IsInRaid = function() return false end
    env.ChatFrame_AddMessageEventFilter = function(ev, fn) client.filters[ev] = fn end
    env.C_Timer = { After = function(sec, fn) table.insert(timers, { at = T + sec, fn = fn, client = client }) end }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        InChatMessagingLockdown = function() return client.lockdown or false end,
        SendAddonMessage = function(prefix, text, dist, target)
            assert(#text <= 255, "message too long")
            if client.offline then return 9 end
            net.sent = net.sent + 1
            if net.log then print(string.format("  %.1f %s -> %s [%s] %s", T, name, tostring(target), dist, text)) end
            if dist == "WHISPER" then
                local found
                for _, c in ipairs(clients) do
                    if not c.offline and MatchesTarget(c, target) then found = c end
                end
                if not found then
                    local f = client.filters["CHAT_MSG_SYSTEM"]
                    local msg = string.format(env.ERR_CHAT_PLAYER_NOT_FOUND_S, target)
                    if not (f and f(nil, "CHAT_MSG_SYSTEM", msg)) then table.insert(client.chat, "SYS:" .. msg) end
                elseif math.random() >= net.dropRate then
                    table.insert(netQueue, { at = T + 0.05, to = found, args = { prefix, text, "WHISPER", SenderName(client) } })
                end
            elseif dist == "GUILD" or dist == "PARTY" then
                for _, c in ipairs(clients) do
                    local same = (dist == "GUILD" and client.guild and c.guild == client.guild)
                        or (dist == "PARTY" and client.party and c.party == client.party)
                    if same and not c.offline then
                        table.insert(netQueue, { at = T + 0.05, to = c, args = { prefix, text, dist, SenderName(client) } })
                    end
                end
            else
                if not client.joined then return 9 end
                for _, c in ipairs(clients) do
                    if c.joined and not c.offline then
                        table.insert(netQueue, { at = T + 0.05, to = c, args = { prefix, text, "CHANNEL", SenderName(client) } })
                    end
                end
            end
            return 0
        end,
    }
    local ns = {}
    client.ns = ns
    for _, file in ipairs(FILES) do
        local chunk, err = load(readFile(ADDON_DIR .. "/" .. file), "@" .. file, "t", env)
        if not chunk then error(err) end
        chunk("FlightpathLegends", ns)
    end
    table.insert(clients, client)
    client.fire = function(ev, ...)
        local list = client.events[ev]
        if list then for _, f in ipairs(list) do f.__scripts.OnEvent(f, ev, ...) end end
    end
    client.fire("ADDON_LOADED", "FlightpathLegends")
    client.fire("PLAYER_LOGIN")
    client.fire("PLAYER_ENTERING_WORLD")
    return client
end

function RemoveClient(client)
    client.offline = true
    for i, c in ipairs(clients) do if c == client then table.remove(clients, i) break end end
end

function Advance(seconds)
    local steps = math.floor(seconds / 0.1 + 0.5)
    for _ = 1, steps do
        T = T + 0.1
        local i = 1
        while i <= #timers do
            local t = timers[i]
            if t.at <= T then
                table.remove(timers, i)
                if not t.client.offline then t.fn() end
            else
                i = i + 1
            end
        end
        i = 1
        while i <= #netQueue do
            local m = netQueue[i]
            if m.at <= T then
                table.remove(netQueue, i)
                deliver(m.to, table.unpack(m.args))
            else
                i = i + 1
            end
        end
        for _, c in ipairs(clients) do
            if not c.offline then
                local n = #c.frames
                for k = 1, n do
                    local f = c.frames[k]
                    local fn = f.__scripts.OnUpdate
                    if fn and f.__shown then fn(f, 0.1) end
                end
            end
        end
    end
end

function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[DeepCopy(k)] = DeepCopy(x) end
    return t
end

local passed, failed = 0, 0
function check(cond, label)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. label)
    end
end
function eq(a, b, label)
    check(a == b, label .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")")
end
function section(name) print("== " .. name) end
function summary()
    print(string.format("%d passed, %d failed", passed, failed))
    if failed > 0 then os.exit(1) end
end
