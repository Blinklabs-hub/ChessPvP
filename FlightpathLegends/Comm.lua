-- Flightpath Legends - network transport. Addon messages over whispers (games) and a hidden channel (ladder, lobby).
local _, ns = ...

local C = {}
ns.Comm = C

local PREFIX = "FPLegends"
local CHANNEL = "FPLegendsNet"
C.PREFIX, C.CHANNEL = PREFIX, CHANNEL

C.handlers = {} -- [command] = function(sender, dist, parts)
C.recentSenders = {} -- { rawName, normalizedName } pairs, for /chess debug

local queue = {}
local tokens = 8
local lastFill = 0
local BURST, RATE = 8, 0.9 -- stay under the client's 10-message burst / 1 per second limit
local recentWhispers = {} -- [name] = time, for hiding "player not found" replies

local function InLockdown()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if f then
        local ok, locked = pcall(f)
        return ok and locked and true or false
    end
    return false
end

function C.ChannelId()
    local id = GetChannelName(CHANNEL)
    if type(id) ~= "number" then return 0 end
    return id
end

-- Returns "sent", "retry" or "drop".
local function TrySend(q)
    local target = q.target
    if q.dist == "CHANNEL" then
        target = C.ChannelId()
        if target == 0 then return "drop" end
    elseif q.dist ~= "WHISPER" then
        target = nil -- GUILD / PARTY / RAID need no target
    else
        -- Retail: plain name for our realm, Name-Realm otherwise. Forever: "First Surname".
        target = ns.WhisperTarget(q.target)
        -- Recorded before sending: the "player not found" reply can arrive at any moment.
        recentWhispers[string.lower(target)] = ns.Now()
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, q.text, q.dist, target)
    if not ok then return "drop" end
    if result == nil or result == true or result == 0 then
        return "sent"
    end
    -- Throttled (3) and channel-throttled (8) sends can be retried.
    if result == 3 or result == 8 then return "retry" end
    q.tries = (q.tries or 0) + 1
    if q.tries >= 3 then return "drop" end
    return "retry"
end

local function Pump()
    local now = ns.Now()
    tokens = math.min(BURST, tokens + (now - lastFill) * RATE)
    lastFill = now
    if #queue == 0 or InLockdown() then return end
    while #queue > 0 and tokens >= 1 do
        local q = queue[1]
        local outcome = TrySend(q)
        if outcome == "retry" then
            tokens = 0 -- back off until the bucket refills
            return
        end
        table.remove(queue, 1)
        if outcome == "sent" then tokens = tokens - 1 end
    end
end

-- Queues a raw message. dist is "WHISPER" (target = full player name) or "CHANNEL".
-- Game whispers go first; channel chatter and bulk messages (bulk = true) wait behind them.
function C.SendRaw(dist, target, text, bulk)
    if #text > 255 then
        ns.Print("internal error: message too long (" .. #text .. ")")
        return
    end
    local item = { dist = dist, target = target, text = text, bulk = bulk }
    if dist ~= "WHISPER" or bulk then
        if #queue > 40 then return end -- never let ladder chatter pile up
        queue[#queue + 1] = item
    else
        -- Game whispers go ahead of any queued channel (lobby/ladder) messages.
        local at = #queue + 1
        for i = 1, #queue do
            if queue[i].dist == "CHANNEL" or queue[i].bulk then
                at = i
                break
            end
        end
        table.insert(queue, at, item)
    end
    Pump()
end

function C.Whisper(target, ...)
    C.SendRaw("WHISPER", target, ns.Join(...))
end

function C.Broadcast(...)
    C.SendRaw("CHANNEL", nil, ns.Join(...))
end

-- Guild and group routes (addon messages only, nothing visible in chat).
function C.GroupDists()
    local list = {}
    if IsInGuild and IsInGuild() then list[#list + 1] = "GUILD" end
    if IsInRaid and IsInRaid() then
        list[#list + 1] = "RAID"
    elseif IsInGroup and IsInGroup() then
        list[#list + 1] = "PARTY"
    end
    return list
end

-- Presence (hello / profile / goodbye) goes out on the hidden channel AND to the guild and
-- group, so friends find each other even if the channel cannot be joined.
function C.Presence(...)
    local text = ns.Join(...)
    if C.Joined() then C.SendRaw("CHANNEL", nil, text) end
    for _, dist in ipairs(C.GroupDists()) do C.SendRaw(dist, nil, text) end
end

function C.CanAnnounce()
    return C.Joined() or #C.GroupDists() > 0
end

-- Messages that reach many players at once (not a whisper).
local BROADCAST = { CHANNEL = true, GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
function C.IsBroadcast(dist)
    return BROADCAST[dist] == true
end

function C.Joined()
    return C.ChannelId() ~= 0
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
-- The addon's old name used another prefix: tell the player when an old version reaches us.
local OLD_PREFIXES = { ChessPvP = "ChessPvP", CheckmateAz = "Checkmate: Azeroth" }
local warnedOld = {}
local function OldVersion(sender, prefix)
    if ns.IsSecret(sender) or type(sender) ~= "string" then return end
    local name = ns.FullName(sender)
    if not name or warnedOld[name] then return end
    warnedOld[name] = prefix
    ns.Print("|cffff8040" .. ns.ShortName(name) .. " is using an old version (" .. tostring(OLD_PREFIXES[warnedOld[name]] or "old") .. "). They need to install Flightpath Legends " ..
        ns.VERSION .. " to play you:|r github.com/Blinklabs-hub/FlightpathLegends/releases")
end

ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, text, dist, sender)
    if ns.IsSecret(prefix) then return end
    if OLD_PREFIXES[prefix] then
        OldVersion(sender, prefix)
        return
    end
    if prefix ~= PREFIX then return end
    if ns.IsSecret(text) or ns.IsSecret(sender) or ns.IsSecret(dist) then return end
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    if dist ~= "WHISPER" and not C.IsBroadcast(dist) then return end
    local raw = sender
    sender = ns.FullName(sender)
    if not sender or ns.SameName(sender, ns.me) then return end
    -- Keep the last few distinct raw sender names for /chess debug.
    local list = C.recentSenders
    local known = false
    for i = 1, #list do
        if list[i][1] == raw then known = true end
    end
    if not known then
        table.insert(list, 1, { raw, sender })
        if #list > 5 then table.remove(list) end
    end
    local parts = ns.Split(text, ";")
    local handler = C.handlers[parts[1]]
    if handler then handler(sender, dist, parts) end
end)

------------------------------------------------------------------------
-- Channel management
------------------------------------------------------------------------
local function HideChannelFromChat()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then
            if ChatFrame_RemoveChannel then
                pcall(ChatFrame_RemoveChannel, frame, CHANNEL)
            elseif frame.RemoveChannel then
                pcall(frame.RemoveChannel, frame, CHANNEL)
            end
        end
    end
end

local joinAllowedAt
local announcedJoin = false

local function EnsureChannel()
    if not joinAllowedAt or ns.Now() < joinAllowedAt then return end
    if C.Joined() then
        if not announcedJoin then
            announcedJoin = true
            HideChannelFromChat()
            ns.Fire("CHESS_CHANNEL_READY")
        end
        return
    end
    announcedJoin = false
    local join = JoinTemporaryChannel or JoinChannelByName
    if join then pcall(join, CHANNEL) end
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    -- Wait so the default channels (General, Trade...) keep their usual numbers.
    if not joinAllowedAt then joinAllowedAt = ns.Now() + 8 end
end)

------------------------------------------------------------------------
-- Hide "No player named X is currently playing" caused by our own whispers
------------------------------------------------------------------------
local notFoundPattern
if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" then
    notFoundPattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
end

local function SystemFilter(_, _, msg)
    if not notFoundPattern or ns.IsSecret(msg) or type(msg) ~= "string" then return false end
    local name = string.match(msg, notFoundPattern)
    if name then
        -- The client may show the name as "Name", "Name-Realm" or "Name Surname".
        local full = ns.FullName(name)
        local at = recentWhispers[string.lower(name)] or (full and recentWhispers[string.lower(ns.ShortName(full))])
        if at and ns.Now() - at < 6 then
            ns.Fire("CHESS_PEER_OFFLINE", full)
            return true
        end
    end
    return false
end

do
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then pcall(add, "CHAT_MSG_SYSTEM", SystemFilter) end
end

------------------------------------------------------------------------
-- Ticker
------------------------------------------------------------------------
local ticker = CreateFrame("Frame")
local accum, slow = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    accum = accum + elapsed
    if accum < 0.2 then return end
    slow = slow + accum
    accum = 0
    Pump()
    ns.Fire("CHESS_TICK")
    if slow >= 5 then
        slow = 0
        EnsureChannel()
    end
end)

ns.On("CHESS_READY", function()
    local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if register then
        pcall(register, PREFIX)
        for old in pairs(OLD_PREFIXES) do pcall(register, old) end
    end
end)
