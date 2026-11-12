-- Flightpath Legends - Lobby, Ladder, Collection and Settings tabs (cards and tiles, responsive).
local _, ns = ...

local T = {}
ns.Tabs = T

local G, P, C, D, A, W, Board = ns.Game, ns.Profile, ns.Comm, ns.Data, ns.Assets, ns.W, ns.Board
local L = ns.Ledger
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
-- Lobby (one per game)
------------------------------------------------------------------------
local function RecordText(rec, prefix)
    if not rec then return "" end
    return string.format("%s|cff40ff40%d|r-|cffff5040%d|r-|cffaaaaaa%d|r", prefix, rec.w or rec.cw, rec.l or rec.cl, rec.d or rec.cd)
end

-- Joins the random-opponent queue with the Battle tab's time control (0 = any).
function T.JoinQueue(rated)
    local idx = ns.db.settings.tc or 4
    if idx == 0 then
        local tc = D.TIME_CONTROLS[4]
        G.StartSeek(tc.base, tc.inc, rated, true)
    else
        local tc = D.TIME_CONTROLS[idx]
        G.StartSeek(tc.base, tc.inc, rated, false)
    end
end

local PLAY_TAB = {}
for key, g in pairs(D.GAMES) do PLAY_TAB[key] = g.play end
T.PLAY_TAB = PLAY_TAB

local function GameName(game) return game == "chess" and "chess" or D.GAMES[game].name end

-- The record line for a game without ratings ("3 won 1 lost 2 drawn").
function T.GameRecordLine(game, rec, empty)
    if not rec then return "|cffaaaaaa" .. (empty or "No games yet") .. "|r" end
    local text = string.format("|cff40ff40%d|r won  |cffff5040%d|r lost", rec.w, rec.l)
    if D.GAMES[game].draws then text = text .. string.format("  |cffd0d0d0%d|r drawn", rec.d) end
    return text
end

-- What a player is doing, as seen from one game's lobby.
local function StatusLine(item, game)
    local st = item.status
    if st == "g" then
        local bg = item.battle and item.battle.game or "chess"
        return "|cffff9040In a " .. GameName(bg) .. " " .. D.GAMES[bg].word .. " vs " .. (item.opp and ns.ShortName(item.opp) or "?") .. "|r"
    elseif st == "r" or st == "c" then
        local kind = st == "r" and "rated" or "casual"
        return game == "chess" and ("|cffffd100Looking for a " .. kind .. " game|r") or ("|cff9ac8ffLooking for a " .. kind .. " chess game|r")
    elseif st == "d" then
        return "|cff808080Do not disturb|r"
    end
    local sg = D.SEEK_GAME[st]
    if sg then
        local word = D.GAMES[sg].word
        if sg == game then return "|cffffd100Looking for a " .. word .. "|r" end
        return "|cff9ac8ffLooking for a " .. GameName(sg) .. " " .. word .. "|r"
    end
    return "|cff40ff40Ready for battle|r"
end

-- Order: looking for this game first, then ready, then looking for another game, then busy.
local function OrderOf(game, status)
    if status == "i" then return 2 end
    if status == "g" then return 4 end
    if status == "d" then return 5 end
    local sg = D.SEEK_GAME[status] or (status == "s" and "chess")
    if sg == game then return 1 end
    if sg then return 3 end
    return 2
end

local function MakeLobby(game)
    local lobby = { game = game }
    local self = { state = lobby }

    function self.Build(page)
        lobby.page = page
        lobby.title = W.Title(page, 20, D.GAMES[game].name .. " Lobby")
        lobby.title:SetPoint("TOPLEFT", 4, -4)
        lobby.count = W.Label(page, "GameFontHighlightSmall", "")
        lobby.count:SetPoint("LEFT", lobby.title, "RIGHT", 10, -2)

        lobby.list = W.List(page, 52, function(row)
            W.Gradient(row, { 0.14, 0.11, 0.07, 0.95 }, { 0.07, 0.05, 0.04, 0.95 })
            W.Background(row, 0, 0, 0, 0, { 0.5, 0.4, 0.16, 0.7 })
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.85, 0.4, 0.07)
            row.portrait = W.Portrait(row, 44)
            row.portrait:SetPoint("LEFT", 4, 0)
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
                    G.Invite(row.item.name, { game = game })
                    ns.UI.ShowTab(PLAY_TAB[game])
                end
            end)
            row.challenge:SetPoint("RIGHT", -8, 0)
            row.watch = W.Button(row, "Watch", 66, 24, function()
                if row.item then
                    G.Watch(row.item.name)
                    local bg = row.item.battle and row.item.battle.game or "chess"
                    if bg == "chess" then ns.UI.ShowTab("play") end
                end
            end)
            row.watch:SetPoint("RIGHT", row.challenge, "LEFT", -4, 0)
            row:SetScript("OnClick", function(r) if r.item then ns.UI.ShowProfile(r.item.name) end end)
            W.Tooltip(row, function(r, tip)
                if not r.item then return false end
                tip:SetText(ns.ShortName(r.item.name), 1, 0.82, 0)
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
            local faction = item.f and A.ARMIES[item.f]
            row.portrait:SetPlayer(item.name, item.ch, item.f)
            row.name:SetText(W.ClassName(item.name, item.ch, faction and faction.color) .. "  |cffaaaaaa" .. A.CharLine(item.ch) .. "|r")
            if game ~= "chess" then
                row.rank:Hide()
                row.sub:ClearAllPoints()
                row.sub:SetPoint("BOTTOMLEFT", 54, 10)
                row.sub:SetText(P.GameTitleText(P.TitleOf(item.name, game), game) .. "   " ..
                    T.GameRecordLine(game, L.Record(item.name, game), game == "bs" and "No battles yet" or nil))
            else
                local idx = RankIndex(item.r, item.g)
                row.sub:ClearAllPoints()
                if idx then W.SetRankIcon(row.rank, idx); row.sub:SetPoint("BOTTOMLEFT", 74, 10)
                else row.rank:Hide(); row.sub:SetPoint("BOTTOMLEFT", 54, 10) end
                local rating = item.verified and ("|cffffffff" .. item.r .. "|r") or ("|cff808080~" .. item.r .. "?|r")
                local casual = item.casual and RecordText(item.casual, "   |cff80c0ffcasual|r ") or ""
                row.sub:SetText(P.TitleText(item.t, item.r, item.g) .. "   " .. rating .. casual)
            end
            local seeking = D.SEEK_GAME[item.status] ~= nil
            W.SetStatusIcon(row.statusIcon, seeking and "s" or item.status)
            row.status:SetText(StatusLine(item, game))
            if item.status == "g" then
                row.watch:Show()
                row.challenge:Disable()
            else
                row.watch:Hide()
                if item.status == "d" then row.challenge:Disable() else row.challenge:Enable() end
            end
        end, 4)
        lobby.list:SetPoint("TOPLEFT", 0, -34)

        lobby.empty = CreateFrame("Frame", nil, page)
        lobby.empty:SetSize(400, 140)
        lobby.empty:SetPoint("CENTER", 0, -20)
        local e1 = lobby.empty:CreateTexture(nil, "ARTWORK")
        e1:SetSize(64, 64)
        e1:SetPoint("TOP")
        e1:SetAlpha(0.5)
        lobby.emptyIcon = e1
        lobby.emptyText = W.Label(lobby.empty, "GameFontHighlight", "")
        lobby.emptyText:SetPoint("TOP", e1, "BOTTOM", 0, -10)
        lobby.emptyText:SetWidth(400)
        lobby.emptyText:SetJustifyH("CENTER")
        lobby.emptyText:SetSpacing(4)
    end

    function self.Layout(w, h)
        lobby.list:Resize(w, h - 34)
    end

    function self.Refresh()
        local all = P.OnlineList()
        local rows = {}
        for _, row in ipairs(all) do rows[#rows + 1] = row end
        local wins = {}
        if game ~= "chess" then
            for _, r in ipairs(rows) do
                local rec = L.Record(r.name, game)
                wins[r.name] = rec and rec.w or 0
            end
        end
        table.sort(rows, function(a, b)
            local oa, ob = OrderOf(game, a.status), OrderOf(game, b.status)
            if oa ~= ob then return oa < ob end
            if game ~= "chess" then
                if wins[a.name] ~= wins[b.name] then return wins[a.name] > wins[b.name] end
            elseif a.r ~= b.r then
                return a.r > b.r
            end
            return a.name < b.name
        end)
        lobby.list:SetData(rows)
        if game == "bs" then W.SetIcon(lobby.emptyIcon, A.ShipIcon(2, A.MyFaction()))
        elseif game == "chess" then W.SetCrest(lobby.emptyIcon, A.MyFaction())
        else W.SetIcon(lobby.emptyIcon, D.GameIcon(game)) end
        if #rows == 0 then
            lobby.emptyText:SetText((not C.Joined() and #C.GroupDists() == 0) and "Connecting to the network..."
                or ("No other Flightpath Legends players are online right now.\nChallenge a friend by name from the " ..
                    (game == "chess" and "Battle" or "Game") .. " tab, or play the computer."))
            lobby.empty:Show()
        else
            lobby.empty:Hide()
        end
        lobby.count:SetText(#all .. " online")
    end
    return self
end

T.lobbies = {}
for _, key in ipairs(D.GAME_ORDER) do T.lobbies[key] = MakeLobby(key) end
T.lobby = T.lobbies.chess.state
T.bslobby = T.lobbies.bs.state
T.c4lobby = T.lobbies.c4.state
T.vblobby = T.lobbies.vb.state

------------------------------------------------------------------------
-- Live Battles (one per game)
------------------------------------------------------------------------
local LIVE_TITLE = { chess = "Live Chess Battles", bs = "Live Sea Battles", c4 = "Live Tavern Games", vb = "Live Vault Heists" }
local MOVE_WORD = { bs = "shot", c4 = "coin", vb = "round" }

local function PlayerSide(row, side, align)
    local p = {}
    p.portrait = W.Portrait(row, 50)
    p.name = W.Title(row, 16)
    p.name:SetWordWrap(false)
    p.title = W.Label(row, "GameFontHighlightSmall")
    p.title:SetWordWrap(false)
    p.rating = W.Title(row, 15, nil, { 1, 1, 1 })
    if align == "LEFT" then
        p.portrait:SetPoint("LEFT", 8, 0)
        p.name:SetPoint("TOPLEFT", 64, -12)
        p.title:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -3)
        p.rating:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)
    else
        p.portrait:SetPoint("RIGHT", -8, 0)
        p.name:SetPoint("TOPRIGHT", -64, -12)
        p.name:SetJustifyH("RIGHT")
        p.title:SetPoint("TOPRIGHT", p.name, "BOTTOMRIGHT", 0, -3)
        p.title:SetJustifyH("RIGHT")
        p.rating:SetPoint("TOPRIGHT", p.title, "BOTTOMRIGHT", 0, -3)
        p.rating:SetJustifyH("RIGHT")
    end
    row[side] = p
end

local function FillSide(p, name, game)
    local e = P.players[name]
    local info = W.CharInfo(name)
    local faction = ns.SameName(name, ns.me) and A.MyFaction() or (e and e.f)
    local army = faction and A.ARMIES[faction]
    p.portrait:SetPlayer(name, info, faction)
    p.name:SetText(W.ClassName(name, info, army and army.color))
    if game ~= "chess" then
        local rec = L.Record(name, game)
        p.title:SetText(P.GameTitleText(P.TitleOf(name, game), game) .. "  |cffaaaaaa" .. A.CharLine(info) .. "|r")
        if rec then
            local text = string.format("|cff40ff40%d|r - |cffff5040%d|r", rec.w, rec.l)
            if D.GAMES[game].draws then text = text .. string.format(" - |cffd0d0d0%d|r", rec.d) end
            p.rating:SetText(text)
        else
            p.rating:SetText(game == "bs" and "|cff808080new captain|r" or "|cff808080newcomer|r")
        end
    else
        local v = ns.Ledger.Get(name)
        local rating = v and v.r or (e and e.r) or D.START_RATING
        p.title:SetText(P.TitleText(e and e.t or "", rating, v and v.games or 0) .. "  |cffaaaaaa" .. A.CharLine(info) .. "|r")
        p.rating:SetText(v and rating or ("|cff808080" .. rating .. "?|r"))
    end
end

local function MakeLive(game)
    local live = { game = game }
    local self = { state = live }

    function self.Build(page)
        live.page = page
        local title = W.Title(page, 20, LIVE_TITLE[game] or ("Live " .. D.GAMES[game].name))
        title:SetPoint("TOPLEFT", 4, -4)
        live.count = W.Label(page, "GameFontHighlightSmall", "")
        live.count:SetPoint("LEFT", title, "RIGHT", 10, -2)
        local hint = W.Label(page, "GameFontDisableSmall", "Watch any " .. D.GAMES[game].word .. " in progress (up to 5 spectators each).")
        hint:SetPoint("TOPRIGHT", -4, -8)

        live.list = W.List(page, 78, function(row)
            W.Gradient(row, { 0.15, 0.11, 0.07, 0.95 }, { 0.07, 0.05, 0.04, 0.95 })
            W.Background(row, 0, 0, 0, 0, { 0.55, 0.43, 0.18, 0.8 })
            PlayerSide(row, "a", "LEFT")
            PlayerSide(row, "b", "RIGHT")
            row.vs = W.Title(row, 26, "VS")
            row.vs:SetPoint("TOP", 0, -8)
            row.vs:SetJustifyH("CENTER")
            row.kind = W.Label(row, "GameFontHighlightSmall")
            row.kind:SetPoint("TOP", row.vs, "BOTTOM", 0, -1)
            row.kind:SetJustifyH("CENTER")
            row.watch = W.Button(row, "Watch", 80, 22, function()
                if row.item then
                    G.Watch(row.item.host)
                    if game == "chess" then ns.UI.ShowTab("play") end
                end
            end)
            row.watch:SetPoint("BOTTOM", 0, 6)
            function row:OnResize(w)
                local half = w / 2 - 110
                for _, p in ipairs({ self.a, self.b }) do
                    p.name:SetWidth(max(60, half))
                    p.title:SetWidth(max(60, half))
                end
            end
        end, function(row, item)
            FillSide(row.a, item.a, game)
            FillSide(row.b, item.b, game)
            local bt = item.battle
            if game ~= "chess" then
                row.kind:SetText(string.format("%s %d", MOVE_WORD[game] or "move", ((bt and bt.moves) or 0) + 1))
            elseif bt then
                row.kind:SetText(string.format("%s  ·  %s  ·  move %d", bt.rated and "|cffffd100Rated|r" or "|cff80c0ffCasual|r",
                    ns.PlayView.TimeControlName(bt.base, bt.inc), math.floor((bt.moves or 0) / 2) + 1))
            else
                row.kind:SetText("")
            end
            if ns.SameName(item.a, ns.me) or ns.SameName(item.b, ns.me) then row.watch:Disable() else row.watch:Enable() end
        end, 6)
        live.list:SetPoint("TOPLEFT", 0, -34)

        live.empty = W.Label(page, "GameFontHighlight", "")
        live.empty:SetPoint("CENTER", 0, -10)
        live.empty:SetJustifyH("CENTER")
        live.empty:SetSpacing(4)
    end

    function self.Layout(w, h)
        live.list:Resize(w, h - 34)
    end

    function self.Refresh()
        local seen, rows = {}, {}
        for name, o in pairs(P.online) do
            local bg = o.battle and o.battle.game or "chess"
            if o.status == "g" and o.opp and bg == game then
                local a, b = name, o.opp
                if b < a then a, b = b, a end
                local key = a .. "|" .. b
                local r = seen[key]
                if not r then
                    r = { a = a, b = b, host = name }
                    seen[key] = r
                    rows[#rows + 1] = r
                end
                r.battle = r.battle or o.battle
            end
        end
        -- Our own battle is listed too (it cannot be watched by ourselves).
        local mine
        if game == "chess" then
            local g = G.current
            if g and g.state == "active" and g.mode == "online" then
                mine = { opp = g.opp, battle = { rated = g.rated, base = g.base, inc = g.inc, moves = #g.moves, game = "chess" } }
            end
        else
            local m = G.Module(game)
            if m and m.Busy() then
                mine = { opp = m.current.opp, battle = { game = game, moves = m.MoveCount(m.current) } }
            end
        end
        if mine then
            local a, b = ns.me, mine.opp
            if b < a then a, b = b, a end
            if not seen[a .. "|" .. b] then rows[#rows + 1] = { a = a, b = b, host = ns.me, battle = mine.battle } end
        end
        table.sort(rows, function(x, y) return x.a < y.a end)
        live.list:SetData(rows)
        local word = D.GAMES[game].word
        live.count:SetText(#rows .. " " .. word .. (#rows == 1 and "" or "s"))
        if #rows == 0 then
            live.empty:SetText("No " .. GameName(game) .. " " .. word .. "s are being played right now.\nWhen players start one, it appears here.")
            live.empty:Show()
        else
            live.empty:Hide()
        end
    end
    return self
end

T.lives = {}
for _, key in ipairs(D.GAME_ORDER) do T.lives[key] = MakeLive(key) end
T.live = T.lives.chess.state
T.bslive = T.lives.bs.state
T.c4live = T.lives.c4.state
T.vblive = T.lives.vb.state

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
-- Admirals: the Battleship leaderboard (wins and losses, best ratio first)
------------------------------------------------------------------------
local adm = {}
T.admirals = adm

function T.BuildAdmirals(page)
    adm.page = page
    local card = W.Card(page)
    card:SetHeight(52)
    card:SetPoint("TOPLEFT", 0, 0)
    card:SetPoint("TOPRIGHT", 0, 0)
    adm.me = card
    card.portrait = W.Portrait(card, 44)
    card.portrait:SetPoint("LEFT", 4, 0)
    card.title = W.Title(card, 17)
    card.title:SetPoint("TOPLEFT", 54, -7)
    card.line = W.Label(card, "GameFontHighlightSmall")
    card.line:SetPoint("BOTTOMLEFT", 54, 9)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(40, 40)
    card.icon:SetPoint("RIGHT", -8, 0)
    W.SetIcon(card.icon, A.ShipIcon(2, A.MyFaction()))

    adm.head = CreateFrame("Frame", nil, page)
    adm.head:SetHeight(18)
    adm.head:SetPoint("TOPLEFT", 0, -60)
    W.Background(adm.head, 1, 1, 1, 0.06)
    adm.cols = {}
    for _, key in ipairs({ "#", "Admiral", "Won", "Lost", "Win %", "Best streak" }) do
        adm.cols[#adm.cols + 1] = W.Label(adm.head, "GameFontNormalSmall", key)
    end

    adm.list = W.List(page, 34, function(row)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.mine = row:CreateTexture(nil, "BORDER")
        row.mine:SetAllPoints()
        row.mine:SetColorTexture(1, 0.82, 0, 0.14)
        row.num = W.Title(row, 15)
        row.portrait = W.Portrait(row, 30)
        row.name = W.Label(row, "GameFontHighlight")
        row.name:SetWordWrap(false)
        row.title = W.Label(row, "GameFontHighlightSmall")
        row.title:SetWordWrap(false)
        row.w = W.Title(row, 15, nil, { 0.25, 1, 0.25 })
        row.l = W.Title(row, 15, nil, { 1, 0.35, 0.3 })
        row.ratio = W.Title(row, 15)
        row.best = W.Label(row, "GameFontHighlight")
        row:SetScript("OnClick", function(self) if self.item then ns.UI.ShowProfile(self.item.name) end end)
        W.Tooltip(row, function(self, tip)
            if not self.item then return false end
            tip:SetText(ns.ShortName(self.item.name), 1, 0.82, 0)
            tip:AddLine("Click to see their profile", 0.7, 0.7, 0.7)
        end)
        function row:OnResize(w)
            local x = { 8, 36, 72, w * 0.48, w * 0.58, w * 0.68, w * 0.82 }
            self.num:SetPoint("LEFT", x[1], 0)
            self.portrait:SetPoint("LEFT", x[2], 0)
            self.name:SetPoint("TOPLEFT", x[3], -3)
            self.name:SetWidth(x[4] - x[3] - 6)
            self.title:SetPoint("BOTTOMLEFT", x[3], 3)
            self.title:SetWidth(x[4] - x[3] - 6)
            self.w:SetPoint("LEFT", x[4], 0)
            self.l:SetPoint("LEFT", x[5], 0)
            self.ratio:SetPoint("LEFT", x[6], 0)
            self.best:SetPoint("LEFT", x[7], 0)
        end
    end, function(row, it, index)
        row.stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
        if it.me then row.mine:Show() else row.mine:Hide() end
        local mc = W.MEDAL[index]
        row.num:SetText(mc and ("|c" .. W.Hex(mc) .. index .. "|r") or index)
        local info = W.CharInfo(it.name)
        row.portrait:SetPlayer(it.name, info, it.f)
        local fc = it.f and A.ARMIES[it.f] and A.ARMIES[it.f].color
        row.name:SetText(W.ClassName(it.name, info, fc))
        row.title:SetText(P.BsTitleText(it.t) .. "  |cffaaaaaa" .. A.CharLine(info) .. "|r")
        row.w:SetText(it.w)
        row.l:SetText(it.l)
        row.ratio:SetText(string.format("%d%%", floor(it.ratio * 100 + 0.5)))
        row.best:SetText(it.best .. (it.streak > 1 and ("  |cffaaaaaa(now " .. it.streak .. ")|r") or ""))
    end, 0)
    adm.list:SetPoint("TOPLEFT", 0, -80)

    adm.empty = W.Label(page, "GameFontHighlight",
        "No Battleship battles have been fought yet.\nWin or lose a battle against another player and it appears here.")
    adm.empty:SetPoint("CENTER", 0, -20)
    adm.empty:SetJustifyH("CENTER")
    adm.empty:SetSpacing(4)
end

function T.LayoutAdmirals(w, h)
    adm.head:SetWidth(w)
    local x = { 8, 72, w * 0.48, w * 0.58, w * 0.68, w * 0.82 }
    for i, fs in ipairs(adm.cols) do
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", adm.head, "LEFT", x[i], 0)
    end
    adm.list:Resize(w, h - 80)
end

function T.RefreshAdmirals()
    local rows = P.AdmiralBoard()
    adm.list:SetData(rows)
    local myRank
    for i, r in ipairs(rows) do if r.me then myRank = i end end
    local card, info = adm.me, A.MyCharInfo()
    card.portrait:SetPlayer(ns.me, info, A.MyFaction())
    card.title:SetText(W.ClassName(ns.me, info) .. "  " .. P.BsTitleText(P.MyTitleId("bs")))
    local rec = L.Battleship(ns.me)
    local line
    if rec then
        local n = rec.bw + rec.bl
        line = string.format("|cff40ff40%d|r won  |cffff5040%d|r lost  ·  %d%% won  ·  best streak %d", rec.bw, rec.bl,
            floor(rec.bw / n * 100 + 0.5), rec.bbest)
        if myRank then line = line .. string.format("  ·  |cffffd100#%d|r of %d", myRank, #rows) end
    else
        line = "|cffaaaaaaFight a Battleship battle against another player to join the Admirals.|r"
    end
    card.line:SetText(line)
    if #rows == 0 then adm.empty:Show() else adm.empty:Hide() end
end

------------------------------------------------------------------------
-- Record leaderboards for games without ratings (wins, losses, draws):
-- Tavern Champions (Four in a Row) and Master Safecrackers (Vault Breaker)
------------------------------------------------------------------------
local function MakeRecordBoard(game, o)
    local tav = { game = game }
    local self = { state = tav }

    function self.Build(page)
        tav.page = page
        local card = W.Card(page)
        card:SetHeight(52)
        card:SetPoint("TOPLEFT", 0, 0)
        card:SetPoint("TOPRIGHT", 0, 0)
        tav.me = card
        card.portrait = W.Portrait(card, 44)
        card.portrait:SetPoint("LEFT", 4, 0)
        card.title = W.Title(card, 17)
        card.title:SetPoint("TOPLEFT", 54, -7)
        card.line = W.Label(card, "GameFontHighlightSmall")
        card.line:SetPoint("BOTTOMLEFT", 54, 9)
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(40, 40)
        card.icon:SetPoint("RIGHT", -8, 0)
        W.SetIcon(card.icon, o.icon())

        tav.head = CreateFrame("Frame", nil, page)
        tav.head:SetHeight(18)
        tav.head:SetPoint("TOPLEFT", 0, -60)
        W.Background(tav.head, 1, 1, 1, 0.06)
        tav.cols = {}
        for _, key in ipairs({ "#", o.who, "Won", "Lost", "Drawn", "Score", "Best streak" }) do
            tav.cols[#tav.cols + 1] = W.Label(tav.head, "GameFontNormalSmall", key)
        end

        tav.list = W.List(page, 34, function(row)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()
            row.mine = row:CreateTexture(nil, "BORDER")
            row.mine:SetAllPoints()
            row.mine:SetColorTexture(1, 0.82, 0, 0.14)
            row.num = W.Title(row, 15)
            row.portrait = W.Portrait(row, 30)
            row.name = W.Label(row, "GameFontHighlight")
            row.name:SetWordWrap(false)
            row.title = W.Label(row, "GameFontHighlightSmall")
            row.title:SetWordWrap(false)
            row.w = W.Title(row, 15, nil, { 0.25, 1, 0.25 })
            row.l = W.Title(row, 15, nil, { 1, 0.35, 0.3 })
            row.d = W.Title(row, 15, nil, { 0.82, 0.82, 0.82 })
            row.ratio = W.Title(row, 15)
            row.best = W.Label(row, "GameFontHighlight")
            row:SetScript("OnClick", function(r) if r.item then ns.UI.ShowProfile(r.item.name) end end)
            W.Tooltip(row, function(r, tip)
                if not r.item then return false end
                tip:SetText(ns.ShortName(r.item.name), 1, 0.82, 0)
                tip:AddLine("Click to see their profile", 0.7, 0.7, 0.7)
            end)
            function row:OnResize(w)
                local x = { 8, 36, 72, w * 0.44, w * 0.53, w * 0.62, w * 0.71, w * 0.83 }
                self.num:SetPoint("LEFT", x[1], 0)
                self.portrait:SetPoint("LEFT", x[2], 0)
                self.name:SetPoint("TOPLEFT", x[3], -3)
                self.name:SetWidth(x[4] - x[3] - 6)
                self.title:SetPoint("BOTTOMLEFT", x[3], 3)
                self.title:SetWidth(x[4] - x[3] - 6)
                self.w:SetPoint("LEFT", x[4], 0)
                self.l:SetPoint("LEFT", x[5], 0)
                self.d:SetPoint("LEFT", x[6], 0)
                self.ratio:SetPoint("LEFT", x[7], 0)
                self.best:SetPoint("LEFT", x[8], 0)
            end
        end, function(row, it, index)
            row.stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
            if it.me then row.mine:Show() else row.mine:Hide() end
            local mc = W.MEDAL[index]
            row.num:SetText(mc and ("|c" .. W.Hex(mc) .. index .. "|r") or index)
            local info = W.CharInfo(it.name)
            row.portrait:SetPlayer(it.name, info, it.f)
            local fc = it.f and A.ARMIES[it.f] and A.ARMIES[it.f].color
            row.name:SetText(W.ClassName(it.name, info, fc))
            row.title:SetText(P.GameTitleText(it.t, game) .. "  |cffaaaaaa" .. A.CharLine(info) .. "|r")
            row.w:SetText(it.w)
            row.l:SetText(it.l)
            row.d:SetText(it.d)
            row.ratio:SetText(string.format("%d%%", floor(it.ratio * 100 + 0.5)))
            row.best:SetText(it.best .. (it.streak > 1 and ("  |cffaaaaaa(now " .. it.streak .. ")|r") or ""))
        end, 0)
        tav.list:SetPoint("TOPLEFT", 0, -80)

        tav.empty = W.Label(page, "GameFontHighlight",
            "No games of " .. D.GAMES[game].name .. " have been played yet.\nFinish a game against another player and it appears here.")
        tav.empty:SetPoint("CENTER", 0, -20)
        tav.empty:SetJustifyH("CENTER")
        tav.empty:SetSpacing(4)
    end

    function self.Layout(w, h)
        tav.head:SetWidth(w)
        local x = { 8, 72, w * 0.44, w * 0.53, w * 0.62, w * 0.71, w * 0.83 }
        for i, fs in ipairs(tav.cols) do
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", tav.head, "LEFT", x[i], 0)
        end
        tav.list:Resize(w, h - 80)
    end

    function self.Refresh()
        local rows = P.RecordBoard(game)
        tav.list:SetData(rows)
        local myRank
        for i, r in ipairs(rows) do if r.me then myRank = i end end
        local card, info = tav.me, A.MyCharInfo()
        card.portrait:SetPlayer(ns.me, info, A.MyFaction())
        card.title:SetText(W.ClassName(ns.me, info) .. "  " .. P.GameTitleText(P.MyTitleId(game), game))
        local rec = L.Record(ns.me, game)
        local line
        if rec then
            line = string.format("|cff40ff40%d|r won  |cffff5040%d|r lost  |cffd0d0d0%d|r drawn  ·  %d%% score  ·  best streak %d",
                rec.w, rec.l, rec.d, floor((rec.w + rec.d * 0.5) / rec.games * 100 + 0.5), rec.best)
            if myRank then line = line .. string.format("  ·  |cffffd100#%d|r of %d", myRank, #rows) end
        else
            line = "|cffaaaaaaPlay a game of " .. D.GAMES[game].name .. " against another player to join the " .. o.title .. ".|r"
        end
        card.line:SetText(line)
        if #rows == 0 then tav.empty:Show() else tav.empty:Hide() end
    end
    return self
end

T.boards = {
    c4 = MakeRecordBoard("c4", { title = "Tavern Champions", who = "Champion", icon = function() return A.CoinIcon(1) end }),
    vb = MakeRecordBoard("vb", { title = "Master Safecrackers", who = "Safecracker", icon = function() return D.GameIcon("vb") end }),
}
T.tavern = T.boards.c4.state
T.BuildTavern, T.LayoutTavern, T.RefreshTavern = T.boards.c4.Build, T.boards.c4.Layout, T.boards.c4.Refresh
T.vaultboard = T.boards.vb.state

------------------------------------------------------------------------
-- Games: pick which game to play (a card per game)
------------------------------------------------------------------------
local games = { cards = {} }
T.games = games

-- Players looking for / playing a game right now.
local function Activity(key)
    local looking, playing = 0, 0
    local seek = D.GAMES[key].seek
    for _, o in pairs(P.online) do
        if o.status == "g" and (o.battle and o.battle.game or "chess") == key then
            playing = playing + 1
        elseif o.status == seek or (key == "chess" and o.status == "c") then
            looking = looking + 1
        end
    end
    return looking, playing
end

-- Whether we have an unfinished game of this kind.
local function InProgress(key)
    if key == "chess" then
        local g = G.current
        return g and g.state == "active" and g.mode ~= "spectate"
    end
    local m = G.Module(key)
    return m and m.Active() and m.current.mode ~= "spectate"
end

function T.BuildGames(page)
    games.page = page
    games.title = W.Title(page, 20, "Choose a game")
    games.title:SetPoint("TOPLEFT", 4, -4)
    games.hint = W.Label(page, "GameFontDisableSmall", "Each game has its own lobby, leaderboard, titles and feats.")
    games.hint:SetPoint("LEFT", games.title, "RIGHT", 12, -2)
    for i, key in ipairs(D.GAME_ORDER) do
        local g = D.GAMES[key]
        local card = CreateFrame("Button", nil, page)
        card.key = key
        W.Gradient(card, { 0.16, 0.12, 0.08, 0.96 }, { 0.07, 0.05, 0.04, 0.96 })
        card.edge = W.Background(card, 0, 0, 0, 0, { 0.55, 0.43, 0.18, 0.9 })
        card.glow = card:CreateTexture(nil, "BORDER", nil, 2)
        card.glow:SetAllPoints()
        card.glow:SetTexture(W.TEX .. "burst")
        card.glow:SetBlendMode("ADD")
        card.glow:SetVertexColor(1, 0.8, 0.3, 0.25)
        card.glow:Hide()
        local hl = card:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.4, 0.07)
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(64, 64)
        card.icon:SetPoint("TOPLEFT", 12, -12)
        W.SetIcon(card.icon, D.GameIcon(key))
        card.iconRing = card:CreateTexture(nil, "OVERLAY")
        card.iconRing:SetPoint("CENTER", card.icon)
        card.iconRing:SetSize(76, 76)
        card.iconRing:SetTexture(W.TEX .. "token_ring")
        card.iconRing:SetVertexColor(0.85, 0.7, 0.3)
        card.name = W.Title(card, 20, g.name)
        card.name:SetPoint("TOPLEFT", 88, -12)
        card.blurb = W.Label(card, "GameFontHighlightSmall", g.blurb)
        card.blurb:SetPoint("TOPLEFT", 88, -38)
        card.blurb:SetJustifyV("TOP")
        card.blurb:SetSpacing(2)
        card.record = W.Label(card, "GameFontHighlightSmall")
        card.record:SetPoint("BOTTOMLEFT", 12, 34)
        card.record:SetWordWrap(false)
        card.activity = W.Label(card, "GameFontHighlightSmall")
        card.activity:SetPoint("BOTTOMLEFT", 12, 14)
        card.activity:SetWordWrap(false)
        card.play = W.Button(card, "Play", 96, 26, function() T.OpenGame(key) end)
        card.play:SetPoint("BOTTOMRIGHT", -10, 10)
        card:SetScript("OnClick", function() T.OpenGame(key) end)
        games.cards[i] = card
    end
end

function T.OpenGame(key)
    ns.Sound("click")
    ns.UI.SetGame(key)
    ns.UI.ShowTab(D.GAMES[key].play)
end

function T.LayoutGames(w, h)
    local cols = w >= 560 and 2 or 1
    local rows = math.ceil(#games.cards / cols)
    local gap = 10
    local top = 34
    local cw = floor((w - gap * (cols - 1)) / cols)
    local ch = max(120, min(170, floor((h - top - gap * (rows - 1)) / rows)))
    for i, card in ipairs(games.cards) do
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", games.page, "TOPLEFT", c * (cw + gap), -(top + r * (ch + gap)))
        card:SetSize(cw, ch)
        card.blurb:SetWidth(max(80, cw - 100))
        card.record:SetWidth(max(80, cw - 130))
        card.activity:SetWidth(max(80, cw - 130))
    end
end

function T.RefreshGames()
    local current = ns.UI.Game()
    for _, card in ipairs(games.cards) do
        local key = card.key
        if key == "chess" then
            local v = L.Get(ns.me)
            local casual = L.Casual(ns.me)
            local text = string.format("Rating |cffffffff%d|r", P.me.rating)
            if v then text = text .. string.format("   rated |cff40ff40%d|r-|cffff5040%d|r-|cffaaaaaa%d|r", v.w, v.l, v.d) end
            if casual then text = text .. string.format("   casual |cff40ff40%d|r-|cffff5040%d|r-|cffaaaaaa%d|r", casual.cw, casual.cl, casual.cd) end
            card.record:SetText(text)
        else
            card.record:SetText(T.GameRecordLine(key, L.Record(ns.me, key), key == "bs" and "No battles yet" or nil))
        end
        local looking, playing = Activity(key)
        local word = D.GAMES[key].word
        card.activity:SetText(string.format("|cffffd100%d|r looking for a %s  ·  |cffff9040%d|r playing", looking, word, playing))
        local mine = InProgress(key)
        if key == current then
            card.glow:Show()
        else
            card.glow:Hide()
        end
        card.play:SetText(mine and "Resume" or "Play")
    end
end

------------------------------------------------------------------------
-- Collection
------------------------------------------------------------------------
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
            P.SetTitle(self.item.id, self.item.game)
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

-- One Collection per game: chess has battlefields, piece styles, titles and feats;
-- Battleship has its own titles and feats.
local SECTIONS_BY_GAME = {
    chess = {
        { id = "boards", name = "Battlefields", icon = "Interface\\Icons\\inv_misc_map_01" },
        { id = "pieces", name = "Styles", icon = "Interface\\Icons\\inv_bannerpvp_02" },
        { id = "titles", name = "Titles", icon = "Interface\\PvPRankBadges\\PvPRank06" },
        { id = "badges", name = "Feats", icon = "Interface\\Icons\\achievement_pvp_a_04" },
    },
    bs = {
        { id = "titles", name = "Titles", icon = "Interface\\Icons\\inv_misc_anchor" },
        { id = "badges", name = "Feats", icon = "Interface\\Icons\\inv_garrison_carrier" },
    },
    c4 = {
        { id = "titles", name = "Titles", icon = "Interface\\Icons\\inv_misc_coin_01" },
        { id = "badges", name = "Feats", icon = "Interface\\Icons\\inv_drink_05" },
    },
    vb = {
        { id = "titles", name = "Titles", icon = "Interface\\Icons\\inv_misc_key_03" },
        { id = "badges", name = "Feats", icon = "Interface\\Icons\\inv_misc_lockbox_1" },
    },
}

local function MakeCollection(game)
    local coll = { game = game, section = game == "chess" and "pieces" or "titles" }
    local self = { state = coll }
    local SECTIONS = SECTIONS_BY_GAME[game]

    function self.Build(page)
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
        coll.pointsSub = W.Label(page, "GameFontDisableSmall", (game == "bs"
            and "Every Battleship feat\nawards a title you can\nshow in Battleship.")
            or (game == "c4" and "Every Four in a Row feat\nawards a title you can\nshow at the tavern table.")
            or (game == "vb" and "Every Vault Breaker feat\nawards a title you can\nshow at the vaults.")
            or "Every chess feat awards\na title. Battlefields and\nstyles are free to use.")
        coll.pointsSub:SetPoint("TOPLEFT", coll.points, "BOTTOMLEFT", 0, -4)
        coll.pointsSub:SetWidth(150)

        coll.header = W.Title(page, 20)
        coll.header:SetPoint("TOPLEFT", 166, -2)
        coll.grids = {}
        for _, s in ipairs(SECTIONS) do
            local spec = GRID_SPEC[s.id]
            local grid = W.Grid(page, spec[1], spec[2], spec[3], spec[4], 10)
            grid:SetPoint("TOPLEFT", 166, -32)
            grid:Hide()
            coll.grids[s.id] = grid
        end
    end

    function self.Layout(w, h)
        for _, grid in pairs(coll.grids) do
            grid:Resize(max(150, w - 166), max(100, h - 32))
        end
    end

    function self.Refresh()
        local p = P.me
        for id, b in pairs(coll.nav) do
            if id == coll.section then b.sel:Show() else b.sel:Hide() end
        end
        for id, grid in pairs(coll.grids) do
            if id == coll.section then grid:Show() else grid:Hide() end
        end
        -- this game's feats only
        local feats, earned = {}, 0
        for i = 1, #D.BADGES do
            local b = D.BADGES[i]
            if P.BadgeGame(b) == game then
                feats[#feats + 1] = b
                if p.badges[b.id] then earned = earned + 1 end
            end
        end
        coll.points:SetText(string.format("Feat points: |cffffffff%d|r", P.Points(p, game)))
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
            local current
            if game == "chess" then current = p.title
            elseif game == "bs" then current = p.bsTitle
            else current = p.gameTitles and p.gameTitles[game] end
            local gname = ns.Data.GAMES[game].name
            coll.header:SetText(gname .. " titles")
            local avail = {}
            for _, t in ipairs(P.AvailableTitles(game)) do avail[t.id] = true end
            if game ~= "chess" then
                data[1] = { id = nil, game = game, name = "No title (" .. ns.Data.GAMES[game].noTitle .. ")", color = "ff909090", available = true, selected = current == nil }
            else
                data[1] = { id = nil, game = game, name = "Current rank (automatic)", color = "ffffffff", available = true, selected = current == nil }
                for i = 1, #D.RANKS do
                    local r = D.RANKS[i]
                    data[#data + 1] = {
                        id = r.id, game = game, name = r.name, color = r.color, available = avail[r.id], selected = current == r.id,
                        req = "Reach " .. r.min .. " (after " .. D.PLACEMENT_GAMES .. " rated games)",
                    }
                end
            end
            for _, b in ipairs(feats) do
                if b.title then
                    local id = "b:" .. b.id
                    data[#data + 1] = {
                        id = id, game = game, badge = b.id, name = b.title, color = "ffffd100", available = avail[id],
                        selected = current == id, req = "Feat: " .. b.name,
                    }
                end
            end
        else
            coll.header:SetText(string.format("%s feats  |cffaaaaaa%d / %d|r", ns.Data.GAMES[game].name, earned, #feats))
            for _, b in ipairs(feats) do
                data[#data + 1] = { badge = b, earned = p.badges[b.id] }
            end
            table.sort(data, function(a, b)
                if (a.earned ~= nil) ~= (b.earned ~= nil) then return a.earned ~= nil end
                return a.badge.points < b.badge.points
            end)
        end
        coll.grids[section]:SetData(data)
    end
    return self
end

T.collections = {}
for _, key in ipairs(D.GAME_ORDER) do T.collections[key] = MakeCollection(key) end
T.vbcoll = T.collections.vb.state
T.coll = T.collections.chess.state
T.bscoll = T.collections.bs.state
T.c4coll = T.collections.c4.state

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

    local about = Section(page, "About Flightpath Legends " .. ns.VERSION, 392, 0, 300, 332)
    settings.about = about
    local text = W.Label(about, "GameFontHighlightSmall",
        "Board games with other players while you fly.\n\n"
        .. "|cffffd100Chess:|r rated (Elo, starting at " .. D.START_RATING .. ", leagues) or casual.\n"
        .. "|cffffd100Battleship:|r wins and losses. Fleets are sealed before the battle and checked afterwards, "
        .. "so nobody can move ships or lie about hits.\n\n"
        .. "|cffffd100Four in a Row:|r wins, losses and draws. Every move is checked by both players as it is made.\n\n"
        .. "|cffffd100Vault Breaker:|r wins, losses and draws. Vault codes are sealed before the first guess and checked "
        .. "afterwards, so nobody can give false pins.\n\n"
        .. "|cffffd100Witnessed results:|r every battle is confirmed by both players and each player's addon "
        .. "rebuilds the records from those confirmations. Disagreements do not count.\n\n"
        .. "|cffffd100Commands|r\n/fpl  -  open or close\n/chess  /  /battleship\n/fpl accept  /  decline\n/fpl dnd  /  online\n/fpl reset  /  debug")
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
