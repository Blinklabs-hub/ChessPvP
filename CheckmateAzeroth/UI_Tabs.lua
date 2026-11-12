-- Checkmate: Azeroth - Lobby, Ladder, Collection and Settings tabs (cards and tiles, responsive).
local _, ns = ...

local T = {}
ns.Tabs = T

local G, P, C, D, A, W, Board = ns.Game, ns.Profile, ns.Comm, ns.Data, ns.Assets, ns.W, ns.Board
local floor, max, min = math.floor, math.max, math.min
local LOCK = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"

local function RankIndex(rating, games)
    if (games or 0) < D.PLACEMENT_GAMES then return nil end
    local idx = 1
    for i = 1, #D.RANKS do
        if rating >= D.RANKS[i].min then idx = i end
    end
    return idx
end

-- Rank index for a title id (rank titles only).
local function TitleRankIndex(titleId)
    for i = 1, #D.RANKS do
        if D.RANKS[i].id == titleId then return i end
    end
    return nil
end

local function FactionColor(f)
    local army = f and A.ARMIES[f]
    return army and army.color or { 0.9, 0.9, 0.9 }
end

------------------------------------------------------------------------
-- Lobby
------------------------------------------------------------------------
local lobby = { filter = "all" }
T.lobby = lobby

local STATUS_TEXT = {
    i = "|cff40ff40Ready for battle|r",
    r = "|cffffd100In the rated queue|r",
    c = "|cff80c0ffIn the casual queue|r",
    s = "|cffffd100Seeking a match|r",
    d = "|cff808080Do not disturb|r",
}

local FILTERS = {
    { id = "all", text = "Everyone" },
    { id = "r", text = "Rated queue" },
    { id = "c", text = "Casual queue" },
    { id = "g", text = "In battle" },
}

local function RecordText(rec, prefix)
    if not rec then return "" end
    return string.format("%s|cff40ff40%d|r-|cffff5040%d|r-|cffaaaaaa%d|r", prefix, rec.w or rec.cw, rec.l or rec.cl, rec.d or rec.cd)
end

-- Queue panel: rated / casual buttons, time control, counts and search timer.
local function BuildQueue(page)
    local q = W.Card(page)
    q:SetHeight(64)
    q:SetPoint("TOPLEFT", 0, 0)
    q:SetPoint("TOPRIGHT", 0, 0)
    lobby.queue = q
    local title = W.Title(q, 18, "Quick Match")
    title:SetPoint("TOPLEFT", 10, -8)
    lobby.queueInfo = W.Label(q, "GameFontHighlightSmall", "")
    lobby.queueInfo:SetPoint("TOPLEFT", 10, -32)
    lobby.queueInfo:SetWidth(260)
    lobby.queueInfo:SetJustifyV("TOP")

    lobby.tcButton = W.Button(q, "", 130, 24, function()
        local s = ns.db.settings
        -- 0 = any time control, then the regular list
        s.queueTc = ((s.queueTc or 0) + 1) % (#D.TIME_CONTROLS) -- the last entry (no clock) is skipped
        if G.seek then G.StopSeek() end
        ns.UI.Refresh()
    end)
    W.Tooltip(lobby.tcButton, function(_, tip)
        tip:SetText("Time control for the queue", 1, 0.82, 0)
        tip:AddLine("\"Any\" matches whatever the other player picked (two \"Any\" players get Rapid 10+0).", 1, 1, 1, true)
    end)
    lobby.casualButton = W.Button(q, "Casual Queue", 130, 28, function()
        if G.seek and not G.seek.rated then G.StopSeek() else T.JoinQueue(false) end
        ns.UI.Refresh()
    end)
    lobby.ratedButton = W.Button(q, "Rated Queue", 130, 28, function()
        if G.seek and G.seek.rated then G.StopSeek() else T.JoinQueue(true) end
        ns.UI.Refresh()
    end)
    lobby.ratedButton:SetPoint("RIGHT", -10, 0)
    lobby.casualButton:SetPoint("RIGHT", lobby.ratedButton, "LEFT", -6, 0)
    lobby.tcButton:SetPoint("RIGHT", lobby.casualButton, "LEFT", -10, 0)
    lobby.league = q:CreateTexture(nil, "ARTWORK")
    lobby.league:SetSize(28, 28)
    lobby.league:SetPoint("RIGHT", lobby.tcButton, "LEFT", -10, 0)
    W.Tooltip(lobby.league, function() return false end)
end

function T.JoinQueue(rated)
    local s = ns.db.settings
    local idx = s.queueTc or 0
    if idx == 0 then
        local tc = D.TIME_CONTROLS[4]
        G.StartSeek(tc.base, tc.inc, rated, true)
    else
        local tc = D.TIME_CONTROLS[idx]
        G.StartSeek(tc.base, tc.inc, rated, false)
    end
end

function T.BuildLobby(page)
    lobby.page = page
    BuildQueue(page)

    lobby.filters = {}
    for i, f in ipairs(FILTERS) do
        local b = W.Button(page, f.text, 112, 22, function()
            lobby.filter = f.id
            lobby.list.offset = 0
            ns.UI.Refresh()
        end)
        b:SetPoint("TOPLEFT", (i - 1) * 116, -72)
        lobby.filters[f.id] = b
    end
    lobby.count = W.Label(page, "GameFontHighlightSmall", "")
    lobby.count:SetPoint("TOPRIGHT", -4, -77)

    lobby.list = W.List(page, 52, function(row)
        W.Gradient(row, { 0.14, 0.11, 0.07, 0.95 }, { 0.07, 0.05, 0.04, 0.95 })
        W.Background(row, 0, 0, 0, 0, { 0.5, 0.4, 0.16, 0.7 })
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.4, 0.07)
        row.crest = row:CreateTexture(nil, "ARTWORK")
        row.crest:SetSize(42, 42)
        row.crest:SetPoint("LEFT", 5, 0)
        row.name = W.Title(row, 16)
        row.name:SetPoint("TOPLEFT", 54, -7)
        row.name:SetWordWrap(false)
        row.rank = row:CreateTexture(nil, "ARTWORK")
        row.rank:SetSize(16, 16)
        row.rank:SetPoint("BOTTOMLEFT", 54, 8)
        row.sub = W.Label(row, "GameFontHighlightSmall")
        row.sub:SetPoint("BOTTOMLEFT", 74, 10)
        row.sub:SetWordWrap(false)
        row.statusIcon = row:CreateTexture(nil, "ARTWORK")
        row.statusIcon:SetSize(14, 14)
        row.status = W.Label(row, "GameFontHighlightSmall")
        row.status:SetWordWrap(false)
        row.challenge = W.Button(row, "Challenge", 90, 24, function()
            if row.item then
                G.Invite(row.item.name)
                ns.UI.ShowTab("play")
            end
        end)
        row.challenge:SetPoint("RIGHT", -8, 0)
        row.watch = W.Button(row, "Watch", 66, 24, function()
            if row.item then
                G.Watch(row.item.name)
                ns.UI.ShowTab("play")
            end
        end)
        row.watch:SetPoint("RIGHT", row.challenge, "LEFT", -4, 0)
        row:SetScript("OnClick", function(self)
            if self.item then ns.UI.ShowProfile(self.item.name) end
        end)
        W.Tooltip(row, function(self, tip)
            local item = self.item
            if not item then return false end
            tip:SetText(ns.ShortName(item.name), 1, 0.82, 0)
            tip:AddLine("Click to see their profile", 0.7, 0.7, 0.7)
        end)
        function row:OnResize(w)
            local statusX = max(250, w * 0.5)
            self.name:SetWidth(max(80, statusX - 64))
            self.sub:SetWidth(max(80, statusX - 84))
            self.statusIcon:ClearAllPoints()
            self.statusIcon:SetPoint("LEFT", self, "LEFT", statusX, 0)
            self.status:ClearAllPoints()
            self.status:SetPoint("LEFT", self.statusIcon, "RIGHT", 4, 0)
            self.status:SetWidth(max(60, w - statusX - 190))
        end
    end, function(row, item)
        local army = item.f
        local info = army and A.ARMIES[army]
        local color = info and info.color or { 0.9, 0.9, 0.9 }
        row.name:SetText("|c" .. W.Hex(color) .. ns.ShortName(item.name) .. "|r")
        W.SetCrest(row.crest, army)
        local idx = RankIndex(item.r, item.g)
        if idx then W.SetRankIcon(row.rank, idx) else row.rank:Hide() end
        local rating = item.verified and ("|cffffffff" .. item.r .. "|r") or ("|cff808080~" .. item.r .. "?|r")
        local casual = item.casual and RecordText(item.casual, "   |cff80c0ffcasual|r ") or ""
        row.sub:SetText(P.TitleText(item.t, item.r, item.g) .. "   " .. rating .. casual)
        W.SetStatusIcon(row.statusIcon, (item.status == "r" or item.status == "c") and "s" or item.status)
        if item.status == "g" then
            row.status:SetText("|cffff9040In battle vs " .. (item.opp and ns.ShortName(item.opp) or "?") .. "|r")
            row.watch:Show()
            row.challenge:Disable()
        else
            row.status:SetText(STATUS_TEXT[item.status] or STATUS_TEXT.i)
            row.watch:Hide()
            if item.status == "d" then row.challenge:Disable() else row.challenge:Enable() end
        end
    end, 4)
    lobby.list:SetPoint("TOPLEFT", 0, -100)

    lobby.empty = CreateFrame("Frame", nil, page)
    lobby.empty:SetSize(400, 140)
    lobby.empty:SetPoint("CENTER", 0, -20)
    local e1 = lobby.empty:CreateTexture(nil, "ARTWORK")
    e1:SetSize(64, 64)
    e1:SetPoint("TOP")
    e1:SetAlpha(0.5)
    lobby.emptyCrest = e1
    lobby.emptyText = W.Label(lobby.empty, "GameFontHighlight", "")
    lobby.emptyText:SetPoint("TOP", e1, "BOTTOM", 0, -10)
    lobby.emptyText:SetWidth(400)
    lobby.emptyText:SetJustifyH("CENTER")
    lobby.emptyText:SetSpacing(4)
end

function T.LayoutLobby(w, h)
    lobby.list:Resize(w, h - 100)
end

function T.RefreshLobby()
    local all = P.OnlineList()
    local rows, counts = {}, { r = 0, c = 0, g = 0 }
    for _, row in ipairs(all) do
        if counts[row.status] then counts[row.status] = counts[row.status] + 1 end
        if lobby.filter == "all" or row.status == lobby.filter then rows[#rows + 1] = row end
    end
    lobby.list:SetData(rows)
    for id, b in pairs(lobby.filters) do
        if id == lobby.filter then b:Disable() else b:Enable() end
    end
    W.SetCrest(lobby.emptyCrest, A.MyFaction())
    if #rows == 0 then
        local text
        if not C.Joined() then
            text = "Connecting to the chess network..."
        elseif lobby.filter == "r" or lobby.filter == "c" then
            text = "Nobody is waiting in this queue right now.\nJoin it above and you will be matched as soon as someone else joins."
        elseif lobby.filter == "g" then
            text = "No battles are being fought right now."
        else
            text = "No other Checkmate: Azeroth players are online right now.\nChallenge a friend by name from the Battle tab, or practise against the computer."
        end
        lobby.emptyText:SetText(text)
        lobby.empty:Show()
    else
        lobby.empty:Hide()
    end
    lobby.count:SetText(#all .. " online")

    -- Queue panel
    local s = ns.db.settings
    local idx = s.queueTc or 0
    lobby.tcButton:SetText(ns.PlayView.QueueTcText())
    local seek = G.seek
    lobby.ratedButton:SetText(seek and seek.rated and "Leave queue" or "Rated Queue")
    lobby.casualButton:SetText(seek and not seek.rated and "Leave queue" or "Casual Queue")
    local league = G.LeagueIndex(ns.me)
    W.SetLeagueIcon(lobby.league, league)
    local leagueText = league == 0 and "|cffaaaaaaUnranked (plays any league)|r"
        or ("|cffffd100" .. D.LEAGUES[league].name .. " league|r")
    if seek then
        local secs = floor(ns.Now() - (seek.since or ns.Now()))
        lobby.queueInfo:SetText(string.format("Searching the %s queue...  |cffffffff%d:%02d|r\n%s",
            seek.rated and "rated" or "casual", floor(secs / 60), secs % 60, leagueText))
    else
        lobby.queueInfo:SetText(string.format("|cffffd100%d|r waiting rated  ·  |cff80c0ff%d|r waiting casual\n%s",
            counts.r, counts.c, leagueText))
    end
end

------------------------------------------------------------------------
-- Ladder
------------------------------------------------------------------------
local ladder = {}
T.ladder = ladder

local function BuildPodium(parent, place)
    local f = W.Card(parent)
    f.place = place
    local mc = W.MEDAL[place]
    f.ring = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.ring:SetTexture(W.TEX .. "token_ring")
    f.ring:SetVertexColor(mc[1], mc[2], mc[3])
    f.ring:SetSize(54, 54)
    f.ring:SetPoint("TOP", 0, -10)
    f.inner = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.inner:SetTexture(W.TEX .. "dot")
    f.inner:SetVertexColor(0.08, 0.06, 0.04, 1)
    f.inner:SetSize(46, 46)
    f.inner:SetPoint("CENTER", f.ring)
    f.rank = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.rank:SetSize(30, 30)
    f.rank:SetPoint("CENTER", f.ring)
    f.placeText = W.Title(f, 22, place == 1 and "1st" or place == 2 and "2nd" or "3rd", mc)
    f.placeText:SetPoint("TOPLEFT", 8, -6)
    f.crest = f:CreateTexture(nil, "ARTWORK")
    f.crest:SetSize(28, 28)
    f.crest:SetPoint("TOPRIGHT", -4, -4)
    f.name = W.Title(f, 15)
    f.name:SetPoint("TOP", f.ring, "BOTTOM", 0, -4)
    f.name:SetJustifyH("CENTER")
    f.name:SetWordWrap(false)
    f.sub = W.Label(f, "GameFontHighlightSmall")
    f.sub:SetPoint("TOP", f.name, "BOTTOM", 0, -2)
    f.sub:SetJustifyH("CENTER")
    f.rating = W.Title(f, 18, nil, mc)
    f.rating:SetPoint("BOTTOM", 0, 8)
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(self)
        if self.name_ then ns.UI.ShowProfile(self.name_) end
    end)
    return f
end

function T.BuildLadder(page)
    ladder.page = page
    local card = W.Card(page)
    card:SetHeight(48)
    card:SetPoint("TOPLEFT", 0, 0)
    card:SetPoint("TOPRIGHT", 0, 0)
    ladder.me = card
    card.rank = card:CreateTexture(nil, "ARTWORK")
    card.rank:SetSize(34, 34)
    card.rank:SetPoint("LEFT", 8, 0)
    card.title = W.Title(card, 17)
    card.title:SetPoint("TOPLEFT", 50, -7)
    card.line = W.Label(card, "GameFontHighlightSmall")
    card.line:SetPoint("BOTTOMLEFT", 50, 8)
    card.info = W.IconButton(card, 22, "Interface\\FriendsFrame\\InformationIcon", "i", nil, function() end)
    card.info:SetPoint("RIGHT", -10, 0)
    W.Tooltip(card.info, function(_, tip)
        tip:SetText("Witnessed ratings", 1, 0.82, 0)
        tip:AddLine("Every rated game must be confirmed by both players. Nobody can raise their own rating: "
            .. "each player's addon recalculates everyone from the confirmations it has heard.", 1, 1, 1, true)
        tip:AddLine(" ")
        tip:AddLine("Disagreements are not counted and are shown with a warning sign.", 0.8, 0.8, 0.8, true)
        tip:AddLine("Only 2 rated games per pair of players per day count.", 0.8, 0.8, 0.8, true)
    end)

    ladder.podium = { BuildPodium(page, 1), BuildPodium(page, 2), BuildPodium(page, 3) }

    ladder.head = CreateFrame("Frame", nil, page)
    ladder.head:SetHeight(18)
    W.Background(ladder.head, 1, 1, 1, 0.06)
    ladder.cols = {}
    for _, key in ipairs({ "#", "Player", "Title", "Rating", "W / L / D", "Foes beaten" }) do
        ladder.cols[#ladder.cols + 1] = W.Label(ladder.head, "GameFontNormalSmall", key)
    end

    ladder.list = W.List(page, 26, function(row)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.mine = row:CreateTexture(nil, "BORDER")
        row.mine:SetAllPoints()
        row.mine:SetColorTexture(1, 0.82, 0, 0.14)
        row.num = W.Label(row, "GameFontHighlight")
        row.rank = row:CreateTexture(nil, "ARTWORK")
        row.rank:SetSize(18, 18)
        row.crest = row:CreateTexture(nil, "ARTWORK")
        row.crest:SetSize(20, 20)
        row.name = W.Label(row, "GameFontHighlight")
        row.name:SetWordWrap(false)
        row.title = W.Label(row, "GameFontHighlightSmall")
        row.rating = W.Title(row, 15)
        row.record = W.Label(row, "GameFontHighlightSmall")
        row.beaten = W.Label(row, "GameFontHighlightSmall")
        row.warn = row:CreateTexture(nil, "OVERLAY")
        row.warn:SetSize(16, 16)
        row.warn:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        row:SetScript("OnClick", function(self)
            if self.item then ns.UI.ShowProfile(self.item.name) end
        end)
        W.Tooltip(row, function(self, tip)
            local it = self.item
            if not it then return false end
            tip:SetText(ns.ShortName(it.name), 1, 0.82, 0)
            tip:AddLine("Click to see their profile", 0.7, 0.7, 0.7)
            tip:AddLine(string.format("Rating %d (best %d)", it.r, it.peak), 1, 1, 1)
            tip:AddLine(string.format("%d won, %d lost, %d drawn", it.w, it.l, it.d), 1, 1, 1)
            tip:AddLine("Different opponents beaten: " .. it.beaten, 0.8, 0.8, 0.8)
            if it.disputed > 0 then
                tip:AddLine(it.disputed .. " disputed result(s): the players reported different results.", 1, 0.4, 0.3, true)
            end
        end)
        function row:OnResize(w)
            local x = { 6, 34, 78, w * 0.40, w * 0.62, w * 0.74, w * 0.88 }
            self.num:SetPoint("LEFT", x[1], 0)
            self.rank:SetPoint("LEFT", x[2], 0)
            self.crest:SetPoint("LEFT", x[2] + 20, 0)
            self.name:SetPoint("LEFT", x[3], 0)
            self.name:SetWidth(x[4] - x[3] - 6)
            self.title:SetPoint("LEFT", x[4], 0)
            self.rating:SetPoint("LEFT", x[5], 0)
            self.record:SetPoint("LEFT", x[6], 0)
            self.beaten:SetPoint("LEFT", x[7], 0)
            self.warn:SetPoint("RIGHT", -6, 0)
        end
    end, function(row, it, index)
        row.stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
        if it.me then row.mine:Show() else row.mine:Hide() end
        local mc = W.MEDAL[index]
        row.num:SetText(mc and ("|c" .. W.Hex(mc) .. index .. "|r") or index)
        local idx = RankIndex(it.r, it.games)
        if idx then W.SetRankIcon(row.rank, idx) else row.rank:Hide() end
        W.SetCrest(row.crest, it.f)
        row.name:SetText("|c" .. W.Hex(FactionColor(it.f)) .. ns.ShortName(it.name) .. "|r")
        row.title:SetText(P.TitleText(it.t, it.r, it.games))
        row.rating:SetText(it.r)
        row.record:SetText(string.format("|cff40ff40%d|r / |cffff5040%d|r / |cffaaaaaa%d|r", it.w, it.l, it.d))
        row.beaten:SetText(it.beaten)
        if it.disputed > 0 then row.warn:Show() else row.warn:Hide() end
    end, 0)

    ladder.empty = W.Label(page, "GameFontHighlight",
        "The ladder is empty so far.\nIt fills in as rated battles are confirmed by both players.")
    ladder.empty:SetPoint("CENTER", 0, -20)
    ladder.empty:SetJustifyH("CENTER")
    ladder.empty:SetSpacing(4)
end

function T.LayoutLadder(w, h)
    ladder.width, ladder.height = w, h
    local podiumH = (h >= 360) and 130 or 0
    local pw = min(200, floor((w - 24) / 3))
    local cx = w / 2
    local pos = { { cx - pw / 2, 0 }, { cx - pw * 1.5 - 10, -14 }, { cx + pw / 2 + 10, -14 } }
    for i = 1, 3 do
        local f = ladder.podium[i]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", ladder.page, "TOPLEFT", pos[i][1], -56 + pos[i][2])
        f:SetSize(pw, podiumH - math.abs(pos[i][2]))
        f.name:SetWidth(pw - 12)
        if podiumH == 0 then f:Hide() end
    end
    ladder.podiumH = podiumH
    local top = 56 + (podiumH > 0 and podiumH + 8 or 0)
    ladder.head:ClearAllPoints()
    ladder.head:SetPoint("TOPLEFT", 0, -top)
    ladder.head:SetWidth(w)
    local x = { 6, 34, 78, w * 0.40, w * 0.62, w * 0.74, w * 0.88 }
    local colX = { x[1], x[3], x[4], x[5], x[6], x[7] }
    for i, fs in ipairs(ladder.cols) do
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", ladder.head, "LEFT", colX[i], 0)
    end
    ladder.list:ClearAllPoints()
    ladder.list:SetPoint("TOPLEFT", 0, -(top + 20))
    ladder.list:Resize(w, h - top - 20)
end

function T.RefreshLadder()
    local rows = P.Board()
    local myRank
    for i = 1, #rows do
        if rows[i].me then myRank = i end
    end
    ladder.list:SetData(rows)
    local p = P.me
    local games = P.RatedGames()
    local idx = RankIndex(p.rating, games)
    local card = ladder.me
    if idx then W.SetRankIcon(card.rank, idx) else W.SetCrest(card.rank, A.MyFaction()) end
    card.title:SetText(ns.ShortName(ns.me) .. "  " .. P.TitleText(P.MyTitleId(), p.rating, games))
    local v = ns.Ledger.Get(ns.me)
    local line = string.format("Rating |cffffffff%d|r", p.rating)
    if v then
        line = line .. string.format("    |cff40ff40%d|r won  |cffff5040%d|r lost  |cffaaaaaa%d|r drawn    %d foes beaten", v.w, v.l, v.d, v.beaten)
    end
    local li = G.LeagueIndex(ns.me)
    line = line .. "    " .. (li == 0 and "|cffaaaaaaUnranked|r" or ("|cffffd100" .. D.LEAGUES[li].name .. " league|r"))
    if myRank then
        line = line .. string.format("    Rank |cffffd100#%d|r of %d", myRank, #rows)
    else
        line = line .. "    |cffaaaaaaWin a confirmed rated battle to join the ladder.|r"
    end
    card.line:SetText(line)

    for i = 1, 3 do
        local f, it = ladder.podium[i], rows[i]
        if it and ladder.podiumH > 0 then
            f.name_ = it.name
            f.name:SetText("|c" .. W.Hex(FactionColor(it.f)) .. ns.ShortName(it.name) .. "|r")
            f.sub:SetText(P.TitleText(it.t, it.r, it.games))
            f.rating:SetText(it.r)
            W.SetCrest(f.crest, it.f)
            local ri = RankIndex(it.r, it.games)
            if not (ri and W.SetRankIcon(f.rank, ri)) then W.SetCrest(f.rank, it.f) end
            f:Show()
        else
            f:Hide()
        end
    end
    if #rows == 0 then ladder.empty:Show() else ladder.empty:Hide() end
end

------------------------------------------------------------------------
-- Collection
------------------------------------------------------------------------
local coll = { section = "pieces" }
T.coll = coll

local SECTIONS = {
    { id = "boards", name = "Battlefields", icon = "Interface\\Icons\\inv_misc_map_01" },
    { id = "pieces", name = "Styles", icon = "Interface\\Icons\\inv_bannerpvp_02" },
    { id = "titles", name = "Titles", icon = "Interface\\PvPRankBadges\\PvPRank06" },
    { id = "badges", name = "Feats", icon = "Interface\\Icons\\achievement_pvp_a_04" },
}

local function TileFrame(tile, w, h)
    tile:SetSize(w, h)
    W.Gradient(tile, { 0.15, 0.12, 0.08, 0.96 }, { 0.06, 0.05, 0.04, 0.96 })
    tile.edge = W.Background(tile, 0, 0, 0, 0, { 0.5, 0.4, 0.16, 0.8 })
    tile.sel = tile:CreateTexture(nil, "BORDER", nil, 2)
    tile.sel:SetAllPoints()
    tile.sel:SetTexture(W.TEX .. "burst")
    tile.sel:SetBlendMode("ADD")
    tile.sel:SetVertexColor(0.3, 1, 0.3, 0.35)
    tile.sel:Hide()
    local hl = tile:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.85, 0.4, 0.08)
    tile.lock = tile:CreateTexture(nil, "OVERLAY", nil, 5)
    tile.lock:SetSize(24, 24)
    tile.lock:SetPoint("TOPRIGHT", -4, -4)
    if A.HasFile(LOCK) then tile.lock:SetTexture(LOCK) else tile.lock:SetTexture(W.TEX .. "dot"); tile.lock:SetVertexColor(0.5, 0.1, 0.1) end
    tile.lock:Hide()
end

local function BuildBoardTile(tile)
    TileFrame(tile, 140, 150)
    tile.squares = {}
    local sq = 22
    for r = 0, 3 do
        for c = 0, 3 do
            local t = tile:CreateTexture(nil, "ARTWORK", nil, 1)
            t:SetSize(sq, sq)
            t:SetPoint("TOPLEFT", tile, "TOPLEFT", 26 + c * sq, -10 - r * sq)
            local g = tile:CreateTexture(nil, "ARTWORK", nil, 2)
            g:SetAllPoints(t)
            tile.squares[#tile.squares + 1] = { t = t, g = g, dark = (r + c) % 2 == 1 }
        end
    end
    tile.name = W.Title(tile, 14)
    tile.name:SetPoint("TOP", 0, -102)
    tile.name:SetJustifyH("CENTER")
    tile.name:SetWidth(132)
    tile.state = W.Label(tile, "GameFontHighlightSmall")
    tile.state:SetPoint("TOP", tile.name, "BOTTOM", 0, -3)
    tile.state:SetWidth(132)
    tile.state:SetJustifyH("CENTER")
    tile:SetScript("OnClick", function(self)
        if self.item and self.item.unlocked then
            ns.Sound("click")
            P.SetTheme(self.item.item.id)
        end
    end)
end

local function UpdateBoardTile(tile, e)
    local t = e.item
    local grain = t.texture and A.ART[t.texture]
    if grain and not A.HasFile(grain) then grain = nil end
    for i, s in ipairs(tile.squares) do
        local c = s.dark and t.dark or t.light
        s.t:SetColorTexture(c[1], c[2], c[3], 1)
        if grain then
            s.g:SetTexture(grain)
            s.g:SetAlpha(0.15)
            if s.g.SetDesaturated then s.g:SetDesaturated(true) end
            s.g:Show()
        else
            s.g:Hide()
        end
        if s.t.SetDesaturated then s.t:SetDesaturated(not e.unlocked) end
    end
    tile.name:SetText(e.unlocked and t.name or ("|cff808080" .. t.name .. "|r"))
    if e.selected then
        tile.state:SetText("|cff40ff40In use|r")
        tile.sel:Show()
    else
        tile.sel:Hide()
        tile.state:SetText(e.unlocked and "|cffaaaaaaClick to use|r" or ("|cffff6040" .. e.req .. "|r"))
    end
    if e.unlocked then tile.lock:Hide() else tile.lock:Show() end
end

local function BuildPieceTile(tile)
    TileFrame(tile, 220, 176)
    tile.views = {}
    for i, x in ipairs({ -52, 52 }) do
        local v = Board.CreatePieceView(tile, 66)
        v:SetPoint("CENTER", tile, "TOP", x, -48)
        tile.views[i] = v
    end
    tile.vs = W.Title(tile, 18, "vs")
    tile.vs:SetPoint("CENTER", tile, "TOP", 0, -48)
    tile.mine = W.Label(tile, "GameFontHighlightSmall")
    tile.mine:SetPoint("TOP", tile, "TOP", -52, -84)
    tile.mine:SetWidth(100)
    tile.mine:SetJustifyH("CENTER")
    tile.theirs = W.Label(tile, "GameFontHighlightSmall")
    tile.theirs:SetPoint("TOP", tile, "TOP", 52, -84)
    tile.theirs:SetWidth(100)
    tile.theirs:SetJustifyH("CENTER")
    tile.name = W.Title(tile, 14)
    tile.name:SetPoint("TOP", 0, -112)
    tile.name:SetJustifyH("CENTER")
    tile.name:SetWidth(212)
    tile.state = W.Label(tile, "GameFontHighlightSmall")
    tile.state:SetPoint("TOP", tile.name, "BOTTOM", 0, -3)
    tile.state:SetWidth(212)
    tile.state:SetJustifyH("CENTER")
    tile.swap = W.Button(tile, "Swap sides", 96, 20, function()
        if tile.item then
            P.SwapLead(tile.item.item.id)
            if not tile.item.selected then P.SetPieces(tile.item.item.id) end
        end
    end)
    tile.swap:SetPoint("BOTTOM", 0, 6)
    tile:SetScript("OnClick", function(self)
        if self.item and self.item.unlocked then
            ns.Sound("click")
            P.SetPieces(self.item.item.id)
            local mine = A.Sides(self.item.item)
            ns.Sound("cry" .. mine)
        end
    end)
    W.Tooltip(tile, function(self, tip)
        local e = self.item
        if not e then return false end
        local set = e.item
        tip:SetText(set.name, 1, 0.82, 0)
        if set.armies then
            local mine, theirs = A.Sides(set)
            local names = { "Pawn", "Knight", "Bishop", "Rook", "Queen", "King" }
            tip:AddDoubleLine("You lead", "Opponent", 0.6, 1, 0.6, 1, 0.5, 0.4)
            for k = 6, 1, -1 do
                tip:AddDoubleLine(A.ARMIES[mine].units[k].name, A.ARMIES[theirs].units[k].name, 1, 1, 1, 1, 1, 1)
            end
            tip:AddLine(" ")
            tip:AddLine(set.faction and "You always lead your character's faction." or "Use Swap sides to lead the other army.", 0.8, 0.8, 0.8, true)
            tip:AddLine("Only changes how the board looks on your screen.", 0.6, 0.6, 0.6, true)
        end
    end)
end

local function UpdatePieceTile(tile, e)
    local set = e.item
    tile.views[1]:SetPiece(6, nil, set)
    tile.views[2]:SetPiece(-6, nil, set)
    for _, v in ipairs(tile.views) do v:SetAlpha(e.unlocked and 1 or 0.45) end
    if set.armies then
        local mine, theirs = A.Sides(set)
        local a, b = A.ARMIES[mine], A.ARMIES[theirs]
        tile.mine:SetText("|c" .. W.Hex(a.color) .. a.name .. "|r")
        tile.theirs:SetText("|c" .. W.Hex(b.color) .. b.name .. "|r")
        tile.vs:Show()
    else
        tile.mine:SetText("White")
        tile.theirs:SetText("Black")
        tile.vs:Show()
    end
    tile.name:SetText(e.unlocked and set.name or ("|cff808080" .. set.name .. "|r"))
    if e.selected then
        tile.state:SetText("|cff40ff40In use|r")
        tile.sel:Show()
    else
        tile.sel:Hide()
        tile.state:SetText(e.unlocked and "|cffaaaaaaClick to use|r" or ("|cffff6040" .. e.req .. "|r"))
    end
    if e.unlocked then tile.lock:Hide() else tile.lock:Show() end
    if e.unlocked and set.armies and not set.faction then tile.swap:Show() else tile.swap:Hide() end
end

local function BuildTitleTile(tile)
    TileFrame(tile, 220, 48)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetSize(34, 34)
    tile.icon:SetPoint("LEFT", 8, 0)
    tile.name = W.Title(tile, 15)
    tile.name:SetPoint("TOPLEFT", 50, -8)
    tile.state = W.Label(tile, "GameFontHighlightSmall")
    tile.state:SetPoint("BOTTOMLEFT", 50, 8)
    tile:SetScript("OnClick", function(self)
        if self.item and self.item.available then
            ns.Sound("click")
            P.SetTitle(self.item.id)
            G.Announce()
        end
    end)
end

local function UpdateTitleTile(tile, e)
    local ri = e.id and TitleRankIndex(e.id)
    if ri then
        if not W.SetRankIcon(tile.icon, ri) then W.SetIcon(tile.icon, nil) end
    elseif e.badge then
        W.SetIcon(tile.icon, D.BadgeIcon(e.badge, A.MyFaction()))
        tile.icon:Show()
    else
        W.SetCrest(tile.icon, A.MyFaction())
    end
    tile.name:SetText("|c" .. (e.available and e.color or "ff707070") .. e.name .. "|r")
    if e.selected then
        tile.state:SetText("|cff40ff40Shown to other players|r")
        tile.sel:Show()
    else
        tile.sel:Hide()
        tile.state:SetText(e.available and "|cffaaaaaaClick to show|r" or ("|cffff6040" .. (e.req or "Locked") .. "|r"))
    end
    if tile.icon.SetDesaturated then tile.icon:SetDesaturated(not e.available) end
    if e.available then tile.lock:Hide() else tile.lock:Show() end
end

local function BuildBadgeTile(tile)
    TileFrame(tile, 300, 66)
    tile.iconBorder = tile:CreateTexture(nil, "ARTWORK", nil, 1)
    tile.iconBorder:SetSize(48, 48)
    tile.iconBorder:SetPoint("LEFT", 8, 0)
    tile.iconBorder:SetColorTexture(0.55, 0.43, 0.18, 1)
    tile.icon = tile:CreateTexture(nil, "ARTWORK", nil, 2)
    tile.icon:SetSize(44, 44)
    tile.icon:SetPoint("CENTER", tile.iconBorder)
    tile.name = W.Title(tile, 15)
    tile.name:SetPoint("TOPLEFT", 64, -7)
    tile.desc = W.Label(tile, "GameFontHighlightSmall")
    tile.desc:SetPoint("TOPLEFT", tile.name, "BOTTOMLEFT", 0, -3)
    tile.desc:SetWidth(186)
    tile.desc:SetJustifyV("TOP")
    tile.desc:SetSpacing(1)
    tile.shield = tile:CreateTexture(nil, "ARTWORK")
    tile.shield:SetTexture(W.TEX .. "token_ring")
    tile.shield:SetSize(36, 36)
    tile.shield:SetPoint("RIGHT", -8, 0)
    tile.pts = W.Title(tile, 14)
    tile.pts:SetPoint("CENTER", tile.shield)
    tile.bar = W.Bar(tile, 150, 10)
    tile.bar:SetPoint("BOTTOMLEFT", 64, 6)
    W.Tooltip(tile, function(self, tip)
        local e = self.item
        if not e then return false end
        tip:SetText(e.badge.name, 1, 0.82, 0)
        tip:AddLine(e.badge.desc, 1, 1, 1, true)
        if e.badge.title then tip:AddLine("Rewards the title: " .. e.badge.title, 0.4, 1, 0.4) end
        if e.earned then tip:AddLine("Earned " .. date("%d %b %Y", e.earned), 0.7, 0.7, 0.7) end
    end)
end

local function UpdateBadgeTile(tile, e)
    local b = e.badge
    W.SetIcon(tile.icon, D.BadgeIcon(b.id, A.MyFaction()))
    if tile.icon.SetDesaturated then tile.icon:SetDesaturated(not e.earned) end
    tile.icon:SetAlpha(e.earned and 1 or 0.55)
    tile.iconBorder:SetColorTexture(e.earned and 0.85 or 0.3, e.earned and 0.68 or 0.27, e.earned and 0.2 or 0.22, 1)
    tile.name:SetText(e.earned and b.name or ("|cff909090" .. b.name .. "|r"))
    tile.desc:SetText(b.desc)
    tile.pts:SetText(e.earned and b.points or ("|cff707070" .. b.points .. "|r"))
    tile.shield:SetVertexColor(e.earned and 1 or 0.4, e.earned and 0.8 or 0.4, e.earned and 0.25 or 0.4)
    if not e.earned and b.progress then
        local have, need = b.progress(P.me)
        tile.bar:SetProgress(have, need)
        tile.bar:Show()
    else
        tile.bar:Hide()
    end
end

local GRID_SPEC = {
    boards = { 140, 150, BuildBoardTile, UpdateBoardTile },
    pieces = { 220, 176, BuildPieceTile, UpdatePieceTile },
    titles = { 220, 48, BuildTitleTile, UpdateTitleTile },
    badges = { 300, 66, BuildBadgeTile, UpdateBadgeTile },
}

function T.BuildCollection(page)
    coll.page = page
    coll.nav = {}
    for i, s in ipairs(SECTIONS) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(150, 40)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 46)
        W.Gradient(b, { 0.16, 0.12, 0.08, 0.95 }, { 0.07, 0.05, 0.04, 0.95 })
        W.Background(b, 0, 0, 0, 0, { 0.5, 0.4, 0.16, 0.8 })
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(30, 30)
        b.icon:SetPoint("LEFT", 6, 0)
        W.SetIcon(b.icon, s.icon)
        b.text = W.Title(b, 15, s.name)
        b.text:SetPoint("LEFT", 44, 0)
        b.sel = b:CreateTexture(nil, "BORDER")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.18)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.4, 0.08)
        b:SetScript("OnClick", function()
            ns.Sound("click")
            coll.section = s.id
            ns.UI.Layout()
            ns.UI.Refresh()
        end)
        coll.nav[s.id] = b
    end
    coll.points = W.Title(page, 15)
    coll.points:SetPoint("TOPLEFT", 4, -(#SECTIONS * 46 + 10))
    coll.pointsSub = W.Label(page, "GameFontDisableSmall", "Every feat awards a title.\nBattlefields and styles\nare all free to use.")
    coll.pointsSub:SetPoint("TOPLEFT", coll.points, "BOTTOMLEFT", 0, -4)
    coll.pointsSub:SetWidth(150)

    coll.header = W.Title(page, 20)
    coll.header:SetPoint("TOPLEFT", 166, -2)
    coll.grids = {}
    for id, spec in pairs(GRID_SPEC) do
        local grid = W.Grid(page, spec[1], spec[2], spec[3], spec[4], 10)
        grid:SetPoint("TOPLEFT", 166, -32)
        grid:Hide()
        coll.grids[id] = grid
    end
end

function T.LayoutCollection(w, h)
    for id, grid in pairs(coll.grids) do
        grid:Resize(max(150, w - 166), max(100, h - 32))
    end
end

function T.RefreshCollection()
    local p = P.me
    for id, b in pairs(coll.nav) do
        if id == coll.section then b.sel:Show() else b.sel:Hide() end
    end
    for id, grid in pairs(coll.grids) do
        if id == coll.section then grid:Show() else grid:Hide() end
    end
    local earned = 0
    for _ in pairs(p.badges) do earned = earned + 1 end
    coll.points:SetText(string.format("Feat points: |cffffffff%d|r", P.Points(p)))
    local data = {}
    local section = coll.section
    if section == "boards" then
        coll.header:SetText("Battlefields")
        for i = 1, #D.THEMES do
            local t = D.THEMES[i]
            local ok, req = P.IsUnlocked(t)
            data[i] = { item = t, unlocked = ok, req = req, selected = (P.Theme() == t) }
        end
    elseif section == "pieces" then
        coll.header:SetText("Piece styles  |cffaaaaaaWarcraft matchups|r")
        for i = 1, #D.PIECES do
            local t = D.PIECES[i]
            local ok, req = P.IsUnlocked(t)
            data[i] = { item = t, unlocked = ok, req = req, selected = (P.PieceSet() == t) }
        end
    elseif section == "titles" then
        coll.header:SetText("Titles")
        data[1] = { id = nil, name = "Current rank (automatic)", color = "ffffffff", available = true, selected = p.title == nil }
        local avail = {}
        for _, t in ipairs(P.AvailableTitles()) do avail[t.id] = true end
        for i = 1, #D.RANKS do
            local r = D.RANKS[i]
            data[#data + 1] = {
                id = r.id, name = r.name, color = r.color, available = avail[r.id], selected = p.title == r.id,
                req = "Reach " .. r.min .. " (after " .. D.PLACEMENT_GAMES .. " rated games)",
            }
        end
        for i = 1, #D.BADGES do
            local b = D.BADGES[i]
            if b.title then
                local id = "b:" .. b.id
                data[#data + 1] = {
                    id = id, badge = b.id, name = b.title, color = "ffffd100", available = avail[id],
                    selected = p.title == id, req = "Feat: " .. b.name,
                }
            end
        end
    else
        coll.header:SetText(string.format("Feats  |cffaaaaaa%d / %d|r", earned, #D.BADGES))
        for i = 1, #D.BADGES do
            local b = D.BADGES[i]
            data[i] = { badge = b, earned = p.badges[b.id] }
        end
        table.sort(data, function(a, b)
            if (a.earned ~= nil) ~= (b.earned ~= nil) then return a.earned ~= nil end
            return a.badge.points < b.badge.points
        end)
    end
    coll.grids[section]:SetData(data)
end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local settings = {}

local function Section(page, title, x, y, w, h)
    local card = W.Card(page)
    card:SetPoint("TOPLEFT", x, y)
    card:SetSize(w, h)
    local t = W.Title(card, 16, title)
    t:SetPoint("TOPLEFT", 10, -8)
    return card
end

function T.BuildSettings(page)
    local s = ns.db.settings
    settings.checks = {}
    settings.page = page
    local function Add(card, y, text, key, onChange)
        local cb = W.Check(card, text, function() return s[key] end, function(v)
            s[key] = v
            if onChange then onChange(v) end
            ns.UI.Refresh()
        end)
        cb:SetPoint("TOPLEFT", 10, y)
        settings.checks[#settings.checks + 1] = cb
    end
    local game = Section(page, "Battle", 0, 0, 380, 132)
    Add(game, -30, "Show legal moves when a piece is selected", "showLegal")
    Add(game, -56, "Animations (moving pieces, captures, banners)", "animations")
    Add(game, -82, "Fold the side panel away during battles", "autoCollapse")
    Add(game, -108, "Play sounds", "sound")
    settings.game = game

    local social = Section(page, "Social", 0, -142, 380, 80)
    Add(social, -30, "Let other players watch my battles", "allowSpectators")
    Add(social, -54, "Do not disturb (decline challenges automatically)", "dnd", function() G.Announce() end)

    local ui = Section(page, "Interface", 0, -232, 380, 100)
    Add(ui, -30, "Show the launcher button on screen", "showLauncher", function() ns.UI.UpdateLauncher() end)
    local reset = W.Button(ui, "Reset window size and position", 240, 24, function() ns.UI.ResetPosition() end)
    reset:SetPoint("TOPLEFT", 14, -62)

    local about = Section(page, "About Checkmate: Azeroth " .. ns.VERSION, 392, 0, 300, 332)
    settings.about = about
    local text = W.Label(about, "GameFontHighlightSmall",
        "Ratings use the Elo system and start at " .. D.START_RATING .. ". Rated battles always use a clock.\n\n"
        .. "|cffffd100Witnessed ladder:|r every rated battle is confirmed by both players, and each player's addon "
        .. "recalculates the ladder from those confirmations. Nobody can raise their own rating, results that the "
        .. "players disagree on do not count, and only 2 rated battles per pair of players per day count.\n\n"
        .. "|cffffd100Commands|r\n/chess  -  open or close\n/chess challenge <name>\n/chess accept  /  decline\n/chess resign\n/chess reset\n/chess debug")
    text:SetPoint("TOPLEFT", 12, -32)
    text:SetPoint("BOTTOMRIGHT", -12, 10)
    text:SetJustifyV("TOP")
    text:SetSpacing(2)
end

function T.LayoutSettings(w, h)
    -- Two columns when there is room, otherwise the About card goes underneath.
    local about = settings.about
    about:ClearAllPoints()
    if w >= 700 then
        about:SetPoint("TOPLEFT", 392, 0)
        about:SetSize(min(400, w - 392), min(332, h))
    else
        about:SetPoint("TOPLEFT", 0, -342)
        about:SetSize(min(380, w), max(120, h - 342))
    end
end

function T.RefreshSettings()
    for i = 1, #settings.checks do settings.checks[i].Sync() end
end
