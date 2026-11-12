-- Flightpath Legends - player profile card (click a player in the Lobby or Ladder).
local _, ns = ...

local UI = ns.UI
local G, P, D, A, W, L = ns.Game, ns.Profile, ns.Data, ns.Assets, ns.W, ns.Ledger
local floor, max, min = math.floor, math.max, math.min

local card
local FEAT_ICONS = 16

local function Record(w, l, d)
    return string.format("|cff40ff40%d|r  -  |cffff5040%d|r  -  |cffaaaaaa%d|r", w, l, d)
end

local function WinRate(w, l, d)
    local n = w + l + d
    if n == 0 then return "" end
    return string.format("|cffaaaaaa%d%% won|r", floor(w / n * 100 + 0.5))
end

local function StatBox(parent, title)
    local b = W.Card(parent)
    b:SetSize(94, 78)
    b.title = W.Label(b, "GameFontNormalSmall", title)
    b.title:SetPoint("TOP", 0, -6)
    b.big = W.Title(b, 20, nil, { 1, 1, 1 })
    b.big:SetPoint("TOP", 0, -22)
    b.big:SetJustifyH("CENTER")
    b.line1 = W.Label(b, "GameFontHighlightSmall")
    b.line1:SetPoint("TOP", b.big, "BOTTOM", 0, -3)
    b.line1:SetJustifyH("CENTER")
    b.line2 = W.Label(b, "GameFontHighlightSmall")
    b.line2:SetPoint("TOP", b.line1, "BOTTOM", 0, -2)
    b.line2:SetJustifyH("CENTER")
    return b
end

local function Build()
    local f = CreateFrame("Frame", "FlightpathLegendsProfile", UIParent)
    f:SetSize(420, 540)
    f:SetPoint("CENTER", 220, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.Background(f, 0.05, 0.04, 0.04, 0.97)
    W.Tile(f, "dialogBg", 0.95)
    W.Chrome(f, "goldBorder", 6, 28)
    table.insert(UISpecialFrames, "FlightpathLegendsProfile")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- Header
    f.portrait = W.Portrait(f, 80)
    f.portrait:SetPoint("TOPLEFT", 14, -12)
    f.name = W.Title(f, 22)
    f.name:SetPoint("TOPLEFT", 104, -18)
    f.name:SetWidth(290)
    f.name:SetWordWrap(false)
    f.rank = f:CreateTexture(nil, "ARTWORK")
    f.rank:SetSize(18, 18)
    f.rank:SetPoint("TOPLEFT", 104, -46)
    f.titleText = W.Label(f, "GameFontHighlight")
    f.titleText:SetPoint("LEFT", f.rank, "RIGHT", 4, 0)
    f.league = f:CreateTexture(nil, "ARTWORK")
    f.league:SetSize(18, 18)
    f.league:SetPoint("TOPLEFT", 104, -68)
    f.leagueText = W.Label(f, "GameFontHighlightSmall")
    f.leagueText:SetPoint("LEFT", f.league, "RIGHT", 4, 0)
    f.army = W.Label(f, "GameFontHighlightSmall")
    f.army:SetPoint("TOPLEFT", 104, -88)

    -- Stats
    f.rated = StatBox(f, "Rated")
    f.rated:SetPoint("TOPLEFT", 14, -114)
    f.casual = StatBox(f, "Casual")
    f.casual:SetPoint("LEFT", f.rated, "RIGHT", 6, 0)
    f.bs = StatBox(f, "Battleship")
    f.bs:SetPoint("LEFT", f.casual, "RIGHT", 6, 0)
    f.h2h = StatBox(f, "Against you")
    f.h2h:SetPoint("LEFT", f.bs, "RIGHT", 6, 0)
    f.warn = W.Label(f, "GameFontHighlightSmall")
    f.warn:SetPoint("TOPLEFT", 16, -198)
    f.warn:SetWidth(390)
    f.warn:SetTextColor(1, 0.45, 0.3)

    -- Recent battles
    local rh = W.Title(f, 16, "Recent battles")
    rh:SetPoint("TOPLEFT", 16, -216)
    f.recent = {}
    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(388, 18)
        row:SetPoint("TOPLEFT", 16, -238 - (i - 1) * 19)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
        row.result = W.Label(row, "GameFontHighlightSmall")
        row.result:SetPoint("LEFT", 4, 0)
        row.result:SetWidth(60)
        row.opp = W.Label(row, "GameFontHighlightSmall")
        row.opp:SetPoint("LEFT", 68, 0)
        row.opp:SetWidth(180)
        row.opp:SetWordWrap(false)
        row.kind = W.Label(row, "GameFontHighlightSmall")
        row.kind:SetPoint("LEFT", 254, 0)
        row.when = W.Label(row, "GameFontDisableSmall")
        row.when:SetPoint("RIGHT", -4, 0)
        f.recent[i] = row
    end
    f.noRecent = W.Label(f, "GameFontDisableSmall", "No witnessed battles yet.")
    f.noRecent:SetPoint("TOPLEFT", 20, -240)

    -- Feats
    f.featTitle = W.Title(f, 16, "Feats")
    f.featTitle:SetPoint("TOPLEFT", 16, -358)
    f.feats = {}
    for i = 1, FEAT_ICONS do
        local b = CreateFrame("Frame", nil, f)
        b:SetSize(36, 36)
        b:SetPoint("TOPLEFT", 16 + ((i - 1) % 8) * 48, -382 - floor((i - 1) / 8) * 42)
        b.border = b:CreateTexture(nil, "ARTWORK", nil, 1)
        b.border:SetAllPoints()
        b.border:SetColorTexture(0.85, 0.68, 0.2, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK", nil, 2)
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b:EnableMouse(true)
        W.Tooltip(b, function(self, tip)
            local badge = self.badge
            if not badge then return false end
            tip:SetText(badge.name, 1, 0.82, 0)
            tip:AddLine(badge.desc, 1, 1, 1, true)
        end)
        f.feats[i] = b
    end
    f.featNote = W.Label(f, "GameFontDisableSmall", "")
    f.featNote:SetPoint("TOPLEFT", 20, -384)

    -- Actions
    f.ratedBtn = W.Button(f, "Rated Battle", 120, 26, function()
        G.Invite(f.target, { rated = true })
        UI.ShowTab("play")
    end)
    f.ratedBtn:SetPoint("BOTTOMLEFT", 14, 14)
    W.Tooltip(f.ratedBtn, function(_, tip)
        if G.LeagueOK(f.target or "") then
            tip:SetText("Challenge to a rated battle", 1, 1, 1)
        else
            tip:SetText("Too far from your league for a rated battle", 1, 0.4, 0.3)
            tip:AddLine("Rated battles are only possible within one league of yours.", 1, 1, 1, true)
        end
    end)
    f.casualBtn = W.Button(f, "Casual Battle", 120, 26, function()
        G.Invite(f.target, { rated = false })
        UI.ShowTab("play")
    end)
    f.casualBtn:SetPoint("LEFT", f.ratedBtn, "RIGHT", 6, 0)
    f.watchBtn = W.Button(f, "Watch", 70, 26, function()
        G.Watch(f.target)
        UI.ShowTab("play")
    end)
    f.watchBtn:SetPoint("LEFT", f.casualBtn, "RIGHT", 6, 0)
    f.whisperBtn = W.Button(f, "Whisper", 70, 26, function()
        local name = ns.WhisperTarget(f.target)
        local send = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if send then pcall(send, name) end
    end)
    f.whisperBtn:SetPoint("LEFT", f.watchBtn, "RIGHT", 6, 0)
    f:Hide()
    card = f
    UI.profileCard = f
end

local function Refresh()
    if not card or not card:IsShown() then return end
    local f, name = card, card.target
    local me = ns.SameName(name, ns.me)
    local known = P.players[name]
    local v = L.Any(name)
    local rated = L.Get(name)
    local army = me and A.MyFaction() or (known and known.f)
    local info = army and A.ARMIES[army]

    -- Header
    local ch = W.CharInfo(name)
    f.portrait:SetPlayer(name, ch, army)
    f.name:SetText(W.ClassName(name, ch, info and info.color))
    local rating = rated and rated.r or (me and P.me.rating) or (known and known.r) or D.START_RATING
    local games = rated and rated.games or 0
    local titleId = me and P.MyTitleId() or (known and known.t) or ""
    local bsMode = ns.UI.Game() == "bs"
    if bsMode then
        f.titleText:SetText(P.BsTitleText(me and P.MyTitleId("bs") or (known and known.bt)))
    else
        f.titleText:SetText(P.TitleText(titleId, rating, games))
    end
    if games >= D.PLACEMENT_GAMES then
        local idx = 1
        for i = 1, #D.RANKS do if rating >= D.RANKS[i].min then idx = i end end
        W.SetRankIcon(f.rank, idx)
    else
        f.rank:Hide()
    end
    local li = G.LeagueIndex(name)
    if li > 0 then
        W.SetLeagueIcon(f.league, li)
        f.leagueText:SetText("|cffffd100" .. D.LEAGUES[li].name .. " league|r  |cffaaaaaa" .. D.LEAGUES[li].desc .. "|r")
    else
        f.league:Hide()
        f.leagueText:SetText("|cffaaaaaaUnranked - plays any league until " .. D.PLACEMENT_GAMES .. " rated battles|r")
    end
    local line = A.CharLine(ch)
    if line == "" then line = info and ("|c" .. W.Hex(info.color) .. info.title .. "|r") or "|cffaaaaaaCharacter unknown|r" end
    if ch and ch.guild then line = line .. "  |cff40ff40<" .. ch.guild .. ">|r" end
    f.army:SetText(line)

    -- Stats
    if rated then
        f.rated.big:SetText(rated.r)
        f.rated.line1:SetText(Record(rated.w, rated.l, rated.d))
        f.rated.line2:SetText("|cffaaaaaaBest " .. rated.peak .. " · " .. rated.beaten .. " foes|r")
    else
        f.rated.big:SetText("|cff808080" .. rating .. "|r")
        f.rated.line1:SetText("|cffaaaaaaNo rated battles|r")
        f.rated.line2:SetText("")
    end
    if v and (v.cw + v.cl + v.cd) > 0 then
        f.casual.big:SetText(v.cw + v.cl + v.cd)
        f.casual.line1:SetText(Record(v.cw, v.cl, v.cd))
        f.casual.line2:SetText(WinRate(v.cw, v.cl, v.cd))
    else
        f.casual.big:SetText("|cff808080-|r")
        f.casual.line1:SetText("|cffaaaaaaNo casual battles|r")
        f.casual.line2:SetText("")
    end
    local bs = L.Battleship(name)
    if bs then
        f.bs.big:SetText(bs.bw + bs.bl)
        f.bs.line1:SetText(string.format("|cff40ff40%d|r - |cffff5040%d|r", bs.bw, bs.bl))
        f.bs.line2:SetText(WinRate(bs.bw, bs.bl, 0))
    else
        f.bs.big:SetText("|cff808080-|r")
        f.bs.line1:SetText("|cffaaaaaaNo battles|r")
        f.bs.line2:SetText("")
    end
    if me then
        f.h2h:Hide()
    else
        local h = L.HeadToHead(ns.me, name, "chess")
        f.h2h:Show()
        f.h2h.big:SetText(h.w + h.l + h.d)
        f.h2h.line1:SetText(Record(h.w, h.l, h.d))
        local hb = L.HeadToHead(ns.me, name, "b")
        f.h2h.line2:SetText(string.format("|cffaaaaaachess · ships %d-%d|r", hb.w, hb.l))
    end
    if v and v.disputed > 0 then
        f.warn:SetText(v.disputed .. " disputed result(s): the players reported different outcomes.")
    else
        f.warn:SetText("")
    end

    -- Recent battles
    local recent = v and v.recent or {}
    for i, row in ipairs(f.recent) do
        local e = recent[i]
        if e then
            local res = (e.s == 1 and "|cff40ff40Victory|r") or (e.s == 0 and "|cffff5040Defeat|r") or "|cffaaaaaaDraw|r"
            row.result:SetText(res)
            row.opp:SetText("vs " .. ns.ShortName(e.opp))
            if e.game == "b" then
                row.kind:SetText("|cff9ac8ffBattleship|r")
            elseif e.rated then
                local d = e.d or 0
                row.kind:SetText(string.format("rated %s%d|r", d >= 0 and "|cff40ff40+" or "|cffff5040", d))
            else
                row.kind:SetText("|cff80c0ffcasual|r")
            end
            row.when:SetText(date and date("%d %b", e.ts) or "")
            row:Show()
        else
            row:Hide()
        end
    end
    if #recent == 0 then f.noRecent:Show() else f.noRecent:Hide() end

    -- Feats
    local feats
    if me then
        feats = {}
        for i = 1, #D.BADGES do
            if P.me.badges[D.BADGES[i].id] then feats[#feats + 1] = D.BADGES[i].id end
        end
    else
        feats = known and known.feats
    end
    -- only this game's feats
    if feats then
        local game = bsMode and "bs" or "chess"
        local only = {}
        for _, id in ipairs(feats) do
            local b = D.BADGE_BY_ID[id]
            if b and P.BadgeGame(b) == game then only[#only + 1] = id end
        end
        feats = only
    end
    local faction = (info and info.side) or "Alliance"
    for i, b in ipairs(f.feats) do
        local id = feats and feats[i]
        local badge = id and D.BADGE_BY_ID[id]
        if badge then
            W.SetIcon(b.icon, D.BadgeIcon(id, faction))
            b.badge = badge
            b:Show()
        else
            b.badge = nil
            b:Hide()
        end
    end
    if not feats then
        f.featTitle:SetText("Feats")
        f.featNote:SetText("Asking " .. ns.ShortName(name) .. " for their feats...")
    elseif #feats == 0 then
        f.featTitle:SetText("Feats")
        f.featNote:SetText("No feats earned yet.")
    else
        local total = 0
        for _, b in ipairs(D.BADGES) do if P.BadgeGame(b) == (bsMode and "bs" or "chess") then total = total + 1 end end
        f.featTitle:SetText(string.format("%s feats  |cffaaaaaa%d / %d|r", bsMode and "Battleship" or "Chess", #feats, total))
        f.featNote:SetText("")
    end

    -- Actions
    if me then
        f.ratedBtn:Hide(); f.casualBtn:Hide(); f.watchBtn:Hide(); f.whisperBtn:Hide()
    else
        f.ratedBtn:Show(); f.casualBtn:Show(); f.whisperBtn:Show()
        if G.LeagueOK(name) then f.ratedBtn:Enable() else f.ratedBtn:Disable() end
        local o = P.online[name]
        if o and o.status == "g" then f.watchBtn:Show() else f.watchBtn:Hide() end
    end
end

function UI.ShowProfile(name)
    if not name then return end
    if not card then Build() end
    card.target = name
    card:Show()
    ns.Sound("select")
    -- Ask them for their feats and army (only they know those).
    local known = P.players[name]
    if not ns.SameName(name, ns.me) and (not known or not known.profileAt or ns.ServerTime() - known.profileAt > 60) then
        if known then known.feats = nil end
        G.RequestProfile(name)
    end
    Refresh()
end

function UI.HideProfile()
    if card then card:Hide() end
end

ns.On("CHESS_PROFILE_INFO", function(name)
    if card and card:IsShown() and card.target == name then Refresh() end
end)
ns.On("CHESS_LEDGER_CHANGED", Refresh)
ns.On("CHESS_LOBBY_CHANGED", Refresh)
