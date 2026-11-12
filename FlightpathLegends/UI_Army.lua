-- Flightpath Legends - Hidden Army view: the battlefield (your army at the bottom), setting up
-- by clicking units, moving and attacking, player strips, the turn banner, the side panel with
-- what is left of each army, and the result banner.
local _, ns = ...

local HV = {}
ns.ArmyView = HV

local HA, G, P, C, A, W, L = ns.Army, ns.Game, ns.Profile, ns.Comm, ns.Assets, ns.W, ns.Ledger
local floor, max, min = math.floor, math.max, math.min

HV.CELL = 52 -- built at 52px per square and scaled to fit
HV.LABEL = 16
HV.BASE = HV.LABEL + 8 * HV.CELL
HV.STRIP = 58
HV.TURN = 42
HV.GAP = 6
HV.HANDLE = 30
HV.SIDE = 300
HV.SETUP_H = 440

local view = {}
HV.view = view

------------------------------------------------------------------------
-- Orientation: our own army is always at the bottom.
------------------------------------------------------------------------
local function MySide()
    local s = HA.current
    return s and s.mySide or "w"
end

-- Screen position (column 1-8 left to right, row 1-8 top to bottom) of a square.
local function ScreenPos(idx)
    local col, row = HA.ColRow(idx)
    if MySide() == "w" then return col, 9 - row end
    return 9 - col, row
end

local function SquareOrigin(idx)
    local c, r = ScreenPos(idx)
    return HV.LABEL + (c - 1) * HV.CELL, -((r - 1) * HV.CELL)
end

local function Factions(s)
    local mine = A.MyFaction()
    if s and s.mode == "spectate" then
        local he, ge = P.players[s.host], P.players[s.guest]
        return (he and he.f) or "Alliance", (ge and ge.f) or "Horde"
    end
    local e = s and s.opp and P.players[s.opp]
    local theirs = (e and e.f) or (mine == "Horde" and "Alliance" or "Horde")
    if theirs == mine then theirs = mine == "Horde" and "Alliance" or "Horde" end
    return mine, theirs
end

------------------------------------------------------------------------
-- Unit tokens
------------------------------------------------------------------------
local function MakeToken(parent, size)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(size, size)
    t:EnableMouse(false)
    t.shadow = t:CreateTexture(nil, "BACKGROUND")
    t.shadow:SetTexture(W.TEX .. "shadow")
    t.shadow:SetPoint("CENTER", 2, -3)
    t.shadow:SetSize(size * 1.05, size * 1.05)
    t.back = t:CreateTexture(nil, "ARTWORK", nil, 0)
    t.back:SetTexture(W.TEX .. "dot")
    t.back:SetPoint("CENTER")
    t.back:SetSize(size * 0.86, size * 0.86)
    t.icon = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.icon:SetPoint("CENTER")
    t.icon:SetSize(size * 0.8, size * 0.8)
    if t.CreateMaskTexture and t.icon.AddMaskTexture then
        local m = t:CreateMaskTexture()
        if m then
            m:SetAllPoints(t.icon)
            m:SetTexture(A.PortraitMask(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            t.icon:AddMaskTexture(m)
        end
    end
    t.ring = t:CreateTexture(nil, "ARTWORK", nil, 3)
    t.ring:SetTexture(W.TEX .. "token_ring")
    t.ring:SetAllPoints()
    t.badge = t:CreateTexture(nil, "OVERLAY", nil, 1)
    t.badge:SetTexture(W.TEX .. "dot")
    t.badge:SetSize(size * 0.38, size * 0.38)
    t.badge:SetPoint("BOTTOMRIGHT", 2, -2)
    t.badge:SetVertexColor(0.08, 0.06, 0.04, 0.95)
    t.rank = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.rank:SetPoint("CENTER", t.badge, "CENTER", 0, 0)
    t.moved = t:CreateTexture(nil, "OVERLAY", nil, 1)
    t.moved:SetTexture(W.TEX .. "dot")
    t.moved:SetSize(size * 0.16, size * 0.16)
    t.moved:SetPoint("TOPLEFT", 3, -3)
    t.moved:SetVertexColor(0.4, 1, 0.4, 0.9)
    t:Hide()
    return t
end

local function RankLabel(rank)
    if rank == "B" then return "B" end
    if rank == "N" then return "F" end
    return tostring(HA.RANK[rank] or "?")
end

-- Shows a unit. rank nil = hidden (their faction crest instead).
local function SetToken(t, rank, faction, mine, unit)
    local army = A.ARMIES[faction]
    local ring = army and army.ring or (mine and { 0.3, 0.6, 1 } or { 1, 0.3, 0.25 })
    t.ring:SetVertexColor(ring[1], ring[2], ring[3])
    t.back:SetVertexColor(ring[1] * 0.35, ring[2] * 0.35, ring[3] * 0.35, 1)
    if rank then
        local icon = A.UnitIcon(rank, faction)
        if icon then
            t.icon:SetTexture(icon)
            t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            t.icon:SetTexture(W.TEX .. "dot")
        end
        t.icon:SetDesaturated(false)
        t.badge:Show()
        t.rank:SetText(RankLabel(rank))
        t.rank:Show()
    else
        W.SetCrest(t.icon, faction)
        t.badge:Hide()
        t.rank:Hide()
    end
    t.unitRank = rank
    if unit and unit.moved and not mine and not rank then t.moved:Show() else t.moved:Hide() end
    t:Show()
end

------------------------------------------------------------------------
-- The battlefield
------------------------------------------------------------------------
local function BuildBoard(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(HV.BASE, 8 * HV.CELL + HV.LABEL)
    local CS = HV.CELL
    local field = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    field:SetPoint("TOPLEFT", HV.LABEL, 0)
    field:SetSize(8 * CS, 8 * CS)
    if A.HasFile(A.ART.rock) then
        field:SetTexture(A.ART.rock, "REPEAT", "REPEAT")
        field:SetVertexColor(0.42, 0.48, 0.3)
    else
        field:SetColorTexture(0.2, 0.26, 0.14, 1)
    end
    b.squares = {}
    for idx = 1, 64 do
        local x, y = 0, 0
        local sq = CreateFrame("Button", nil, b)
        sq:SetSize(CS, CS)
        sq.idx = idx
        sq.tint = sq:CreateTexture(nil, "BACKGROUND", nil, 2)
        sq.tint:SetAllPoints()
        local col, row = HA.ColRow(idx)
        sq.tint:SetColorTexture(0, 0, 0, (col + row) % 2 == 0 and 0.16 or 0.04)
        if HA.LAKE[idx] then
            sq.lake = sq:CreateTexture(nil, "BACKGROUND", nil, 3)
            sq.lake:SetAllPoints()
            if A.HasFile(A.ART.sea) then
                sq.lake:SetTexture(A.ART.sea)
                sq.lake:SetTexCoord(0.3 + col * 0.02, 0.36 + col * 0.02, 0.4, 0.46)
            else
                sq.lake:SetColorTexture(0.1, 0.3, 0.5, 1)
            end
        end
        sq.zone = sq:CreateTexture(nil, "BORDER", nil, 1)
        sq.zone:SetAllPoints()
        sq.zone:SetColorTexture(0.3, 0.6, 1, 0.1)
        sq.zone:Hide()
        sq.hl = sq:CreateTexture(nil, "BORDER", nil, 2)
        sq.hl:SetPoint("TOPLEFT", 2, -2)
        sq.hl:SetPoint("BOTTOMRIGHT", -2, 2)
        sq.hl:Hide()
        sq.dot = sq:CreateTexture(nil, "OVERLAY")
        sq.dot:SetTexture(W.TEX .. "dot")
        sq.dot:SetPoint("CENTER")
        sq.dot:SetSize(CS * 0.28, CS * 0.28)
        sq.dot:Hide()
        sq:SetScript("OnClick", function(self) HV.OnSquareClick(self.idx) end)
        sq:SetScript("OnEnter", function(self)
            view.hover = self.idx
            HV.ShowUnitTip(self)
        end)
        sq:SetScript("OnLeave", function(self)
            if view.hover == self.idx then view.hover = nil end
            if GameTooltip then GameTooltip:Hide() end
        end)
        b.squares[idx] = sq
        local _ = x + y
    end
    -- grid edge
    W.Background(CreateFrame("Frame", nil, b), 0, 0, 0, 0, { 0.55, 0.45, 0.2, 1 })
    -- labels
    b.colLabels, b.rowLabels = {}, {}
    for i = 1, 8 do
        local c = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.colLabels[i] = c
        local r = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.rowLabels[i] = r
    end
    -- units above the squares
    local layer = CreateFrame("Frame", nil, b)
    layer:SetAllPoints()
    layer:SetFrameLevel(b:GetFrameLevel() + 6)
    layer:EnableMouse(false)
    b.layer = layer
    b.tokens = {}
    for i = 1, 32 do b.tokens[i] = MakeToken(layer, CS * 0.9) end
    b.fx = CreateFrame("Frame", nil, b)
    b.fx:SetAllPoints()
    b.fx:SetFrameLevel(b:GetFrameLevel() + 10)
    b.fx:EnableMouse(false)
    return b
end

-- Positions squares and labels for the current orientation.
local function OrientBoard()
    local b = view.board
    for idx, sq in ipairs(b.squares) do
        local x, y = SquareOrigin(idx)
        sq:ClearAllPoints()
        sq:SetPoint("TOPLEFT", b, "TOPLEFT", x, y)
    end
    local white = MySide() == "w"
    for i = 1, 8 do
        local col = white and i or (9 - i)
        b.colLabels[i]:ClearAllPoints()
        b.colLabels[i]:SetPoint("CENTER", b, "TOPLEFT", HV.LABEL + (i - 1) * HV.CELL + HV.CELL / 2, -(8 * HV.CELL + HV.LABEL / 2))
        b.colLabels[i]:SetText(string.sub("abcdefgh", col, col))
        local row = white and (9 - i) or i
        b.rowLabels[i]:ClearAllPoints()
        b.rowLabels[i]:SetPoint("CENTER", b, "TOPLEFT", HV.LABEL / 2, -((i - 1) * HV.CELL + HV.CELL / 2))
        b.rowLabels[i]:SetText(row)
    end
    view.orientedFor = MySide()
end

------------------------------------------------------------------------
-- Strips
------------------------------------------------------------------------
local function BuildStrip(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(HV.STRIP)
    s.bg = W.Background(s, 0.1, 0.08, 0.06, 0.92, { 0.55, 0.45, 0.2, 0.9 })
    s.glow = s:CreateTexture(nil, "BORDER")
    s.glow:SetAllPoints()
    s.glow:SetTexture(W.TEX .. "burst")
    s.glow:SetBlendMode("ADD")
    s.glow:SetVertexColor(1, 0.8, 0.3, 0.22)
    s.glow:Hide()
    s.portrait = W.Portrait(s, 50)
    s.portrait:SetPoint("LEFT", 3, 0)
    s.name = W.Title(s, 16)
    s.name:SetPoint("TOPLEFT", 58, -6)
    s.name:SetWordWrap(false)
    s.sub = W.Label(s, "GameFontHighlightSmall")
    s.sub:SetPoint("TOPLEFT", 58, -26)
    s.sub:SetWordWrap(false)
    s.state = W.Label(s, "GameFontHighlightSmall")
    s.state:SetPoint("BOTTOMLEFT", 58, 5)
    s.state:SetWordWrap(false)
    s.timer = W.Title(s, 22)
    s.timer:SetPoint("RIGHT", -10, 0)
    s.timer:SetJustifyH("RIGHT")
    function s:SetStripWidth(w)
        self:SetWidth(w)
        self.name:SetWidth(max(60, w - 58 - 50))
        self.sub:SetWidth(max(60, w - 58 - 50))
        self.state:SetWidth(max(60, w - 58 - 50))
    end
    return s
end

local function UpdateStrip(s, name, isComputer, active, state, timeLeft)
    local info = (not isComputer) and W.CharInfo(name) or nil
    local e = P.players[name]
    local faction = ns.SameName(name, ns.me) and A.MyFaction() or (e and e.f) or nil
    s.portrait:SetPlayer(name, info, faction or (isComputer and "Horde" or nil))
    local title = ""
    if not isComputer then title = "  " .. P.GameTitleText(P.TitleOf(name, "ha"), "ha") end
    s.name:SetText(W.ClassName(name, info, faction and A.ARMIES[faction] and A.ARMIES[faction].color) .. title)
    s.sub:SetText(isComputer and "|cffaaaaaaComputer general|r" or
        (ns.Tabs.GameRecordLine("ha", L.Record(name, "ha"), "No battles yet") .. "  |cffaaaaaa" .. A.CharLine(info) .. "|r"))
    s.state:SetText(state or "")
    if active then s.glow:Show() else s.glow:Hide() end
    if timeLeft then
        s.timer:SetText(string.format("%d", math.ceil(timeLeft)))
        if timeLeft < 10 then s.timer:SetTextColor(1, 0.25, 0.2) else s.timer:SetTextColor(1, 0.82, 0) end
        s.timer:Show()
    else
        s.timer:Hide()
    end
end

------------------------------------------------------------------------
-- Side panel
------------------------------------------------------------------------
local function BuildSetup(sp)
    local st = ns.db.settings
    local W2 = HV.SIDE - 8
    local h1 = W.Title(sp, 20, "Hidden Army")
    h1:SetPoint("TOPLEFT", 4, -2)
    local rules = W.Label(sp, "GameFontHighlightSmall",
        "Hide the ranks of your 16 units, then march. Moving onto an enemy starts a fight and reveals both ranks: "
        .. "the higher rank wins. Take the enemy Banner to win. Not rated: wins, losses and draws.")
    rules:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -6)
    rules:SetWidth(W2)
    rules:SetSpacing(2)

    view.findButton = W.Button(sp, "Find Random Opponent", W2, 34, function()
        if G.seek then G.StopSeek() else G.StartSeek(0, 0, false, true, "ha") end
        ns.UI.Refresh()
    end)
    view.findButton:SetPoint("TOPLEFT", rules, "BOTTOMLEFT", 0, -12)
    view.queueNote = W.Label(sp, "GameFontHighlightSmall", "")
    view.queueNote:SetPoint("TOPLEFT", view.findButton, "BOTTOMLEFT", 2, -4)
    view.queueNote:SetWidth(W2)

    local h2 = W.Label(sp, "GameFontNormal", "Challenge by name")
    h2:SetPoint("TOPLEFT", view.queueNote, "BOTTOMLEFT", -2, -12)
    local nameBox = CreateFrame("EditBox", nil, sp, "InputBoxTemplate")
    nameBox:SetSize(W2 - 104, 22)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 6, -6)
    view.nameBox = nameBox
    local function SendChallenge()
        if G.outgoing and not G.outgoing.q then
            G.CancelInvite()
            ns.UI.Refresh()
            return
        end
        local name = nameBox:GetText() or ""
        if name == "" and UnitExists("target") and UnitIsPlayer("target") then
            name = ns.UnitPlayerName("target") or ""
        end
        if name == "" then
            ns.Print("type a character name, or target a player first.")
            return
        end
        nameBox:ClearFocus()
        G.Invite(name, { game = "ha", color = "r" })
        ns.UI.Refresh()
    end
    nameBox:SetScript("OnEnterPressed", SendChallenge)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    view.challengeButton = W.Button(sp, "Challenge", 92, 22, SendChallenge)
    view.challengeButton:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    view.setupNote = W.Label(sp, "GameFontDisableSmall", "")
    view.setupNote:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -4)
    view.setupNote:SetWidth(W2)

    local h3 = W.Label(sp, "GameFontNormal", "Practice against the computer")
    h3:SetPoint("TOPLEFT", view.setupNote, "BOTTOMLEFT", 0, -12)
    view.aiButton = W.Button(sp, "", 120, 24, function()
        st.haLevel = ((st.haLevel or 2) % #HA.LEVELS) + 1
        ns.UI.Refresh()
    end)
    view.aiButton:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -6)
    local aiStart = W.Button(sp, "Play vs Computer", W2 - 126, 24, function()
        HA.StartAI(st.haLevel or 2)
    end)
    aiStart:SetPoint("LEFT", view.aiButton, "RIGHT", 6, 0)

    view.backButton = W.Button(sp, "Back to the battle", 150, 24, function()
        view.showSetup = false
        ns.UI.Refresh()
    end)
    view.backButton:SetPoint("BOTTOMLEFT", sp, "BOTTOMLEFT", 4, 4)
end

-- What is left of each army: icon, ours, theirs.
local function BuildRoster(gp)
    local r = W.Card(gp)
    r:SetHeight(9 * 18 + 26)
    view.roster = r
    local head = W.Label(r, "GameFontNormalSmall", "Armies")
    head:SetPoint("TOPLEFT", 8, -5)
    r.youHead = W.Label(r, "GameFontNormalSmall", "You")
    r.themHead = W.Label(r, "GameFontNormalSmall", "Them")
    r.rows = {}
    for i, rank in ipairs(HA.ORDER) do
        local row = CreateFrame("Frame", nil, r)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", 4, -20 - (i - 1) * 18)
        row:SetPoint("TOPRIGHT", -4, -20 - (i - 1) * 18)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)
        row.name = W.Label(row, "GameFontHighlightSmall", HA.NAME[rank] .. (HA.RANK[rank] and ("  |cffaaaaaa" .. HA.RANK[rank] .. "|r") or ""))
        row.name:SetPoint("LEFT", 22, 0)
        row.mine = W.Label(row, "GameFontHighlightSmall")
        row.theirs = W.Label(row, "GameFontHighlightSmall")
        row.rank = rank
        r.rows[i] = row
    end
    function r:Arrange(w)
        self.youHead:ClearAllPoints()
        self.youHead:SetPoint("TOPLEFT", w - 96, -5)
        self.themHead:ClearAllPoints()
        self.themHead:SetPoint("TOPLEFT", w - 48, -5)
        for _, row in ipairs(self.rows) do
            row.mine:ClearAllPoints()
            row.mine:SetPoint("LEFT", row, "LEFT", w - 92, 0)
            row.theirs:ClearAllPoints()
            row.theirs:SetPoint("LEFT", row, "LEFT", w - 44, 0)
        end
    end
    r:Arrange(HV.SIDE)
end

local function BuildGamePanel(gp)
    view.header = W.Title(gp, 18)
    view.header:SetPoint("TOPLEFT", 6, -4)
    view.status = W.Label(gp, "GameFontHighlight")
    view.status:SetPoint("TOPLEFT", 6, -30)
    view.status:SetWidth(HV.SIDE - 12)
    view.status:SetJustifyV("TOP")
    view.status:SetSpacing(3)

    view.shuffle = W.Button(gp, "Shuffle", 92, 26, function()
        HA.Shuffle()
        view.sel = nil
        A.Play("haStep")
    end)
    view.shuffle:SetPoint("TOPLEFT", 4, -96)
    view.ready = W.Button(gp, "Ready!", 92, 26, function()
        view.sel = nil
        HA.Ready()
    end)
    view.ready:SetPoint("LEFT", view.shuffle, "RIGHT", 4, 0)

    BuildRoster(gp)
    view.roster:SetPoint("TOPLEFT", 0, -128)
    view.roster:SetPoint("TOPRIGHT", 0, -128)

    local logBox = W.Card(gp)
    logBox:SetPoint("TOPLEFT", view.roster, "BOTTOMLEFT", 0, -6)
    logBox:SetPoint("TOPRIGHT", view.roster, "BOTTOMRIGHT", 0, -6)
    view.logBox = logBox
    local lh = W.Label(logBox, "GameFontNormalSmall", "Battle log")
    lh:SetPoint("TOPLEFT", 8, -5)
    view.log = W.List(logBox, 17, function(row)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.text = W.Label(row, "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 6, 0)
        function row:OnResize(w) self.text:SetWidth(w - 10) end
    end, function(row, item, idx)
        row.stripe:SetColorTexture(1, 1, 1, idx % 2 == 0 and 0.05 or 0)
        row.text:SetText(item)
    end, 0)
    view.log:SetPoint("TOPLEFT", 4, -22)

    view.resign = W.Button(gp, "Resign", 100, 26, function(self)
        local s = HA.current
        if not s or s.phase == "over" then return end
        if s.mode == "spectate" or view.resignArmed then
            view.resignArmed = false
            HA.Resign()
            return
        end
        view.resignArmed = true
        self:SetText("Sure?")
        ns.After(3, function()
            if view.resignArmed then view.resignArmed = false; ns.UI.Refresh() end
        end)
    end)
    view.resign:SetPoint("BOTTOMLEFT", 0, 0)
    view.newButton = W.Button(gp, "New Battle", 130, 26, function()
        ns.UI.NewGame("ha")
    end)
    view.newButton:SetPoint("BOTTOMLEFT", 0, 0)
end

local function BuildBanner(parent)
    local banner = CreateFrame("Button", nil, parent)
    banner:SetSize(380, 150)
    banner:SetFrameLevel(parent:GetFrameLevel() + 60)
    W.Background(banner, 0.04, 0.03, 0.02, 0.95)
    W.Tile(banner, "dialogBg", 0.9)
    W.Chrome(banner, "goldBorder", 4, 24)
    banner.icon = banner:CreateTexture(nil, "ARTWORK")
    banner.icon:SetSize(64, 64)
    banner.icon:SetPoint("LEFT", 16, 8)
    banner.title = W.Title(banner, 34)
    banner.title:SetPoint("TOP", 36, -16)
    banner.title:SetJustifyH("CENTER")
    banner.sub = W.Label(banner, "GameFontHighlight")
    banner.sub:SetPoint("TOP", banner.title, "BOTTOM", 0, -8)
    banner.sub:SetWidth(250)
    banner.sub:SetJustifyH("CENTER")
    banner.sub:SetSpacing(3)
    banner.again = W.Button(banner, "New Battle", 110, 22, function()
        banner:Hide()
        ns.UI.NewGame("ha")
    end)
    banner.again:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", -4, 10)
    banner.close = W.Button(banner, "Close", 110, 22, function() banner:Hide() end)
    banner.close:SetPoint("BOTTOMLEFT", banner, "BOTTOM", 4, 10)
    banner:SetScript("OnClick", function(self) self:Hide() end)
    banner:Hide()
    return banner
end

------------------------------------------------------------------------
-- Build and layout
------------------------------------------------------------------------
function HV.Build(page)
    view.page = page
    view.holder = CreateFrame("Frame", nil, page)
    view.board = BuildBoard(view.holder)
    view.board:SetPoint("TOPLEFT")
    OrientBoard()
    view.strips = { BuildStrip(page), BuildStrip(page) } -- 1: enemy (top), 2: you (bottom)

    local turn = CreateFrame("Frame", nil, page)
    turn.bg = turn:CreateTexture(nil, "BACKGROUND")
    turn.bg:SetAllPoints()
    turn.shine = turn:CreateTexture(nil, "BORDER")
    turn.shine:SetAllPoints()
    turn.shine:SetTexture(W.TEX .. "burst")
    turn.shine:SetBlendMode("ADD")
    W.Background(turn, 0, 0, 0, 0, { 0.9, 0.75, 0.3, 0.9 })
    turn.text = W.Title(turn, 22)
    turn.text:SetPoint("CENTER", 0, 1)
    turn.text:SetJustifyH("CENTER")
    turn.sub = W.Title(turn, 18, nil, { 1, 1, 1 })
    turn.sub:SetPoint("RIGHT", -12, 0)
    turn.sub:SetJustifyH("RIGHT")
    turn.hint = W.Label(turn, "GameFontHighlightSmall")
    turn.hint:SetPoint("LEFT", 12, 0)
    turn.hint:SetJustifyH("LEFT")
    turn.t = 0
    turn:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        local p = 0.5 + 0.5 * math.sin(self.t * 4)
        self.shine:SetAlpha(self.urgent and (0.15 + 0.35 * p) or 0.12)
        self.text:SetAlpha(self.urgent and (0.75 + 0.25 * p) or 1)
    end)
    turn:Hide()
    view.turn = turn
    view.banner = BuildBanner(page)

    local h = CreateFrame("Frame", nil, page)
    h:SetWidth(HV.HANDLE)
    view.handle = h
    view.toggle = W.IconButton(h, HV.HANDLE - 2, nil, ">", function()
        return ns.UI.IsCollapsed() and "Show the side panel" or "Hide the side panel"
    end, function() ns.UI.SetCollapsed(not ns.UI.IsCollapsed()) end)
    view.toggle:SetPoint("TOP")

    local side = CreateFrame("Frame", nil, page)
    side:SetWidth(HV.SIDE)
    view.side = side
    local sp = CreateFrame("Frame", nil, side)
    sp:SetAllPoints()
    view.setup = sp
    BuildSetup(sp)
    local gp = CreateFrame("Frame", nil, side)
    gp:SetAllPoints()
    view.gamePanel = gp
    BuildGamePanel(gp)
end

local BOARD_H = 8 * HV.CELL + HV.LABEL

function HV.SizeFor(cellPx, showSide)
    local scale = cellPx / HV.CELL
    local w = HV.BASE * scale + HV.GAP + HV.HANDLE + (showSide and (HV.GAP + HV.SIDE) or 0)
    local h = HV.STRIP * 2 + HV.TURN + HV.GAP * 3 + BOARD_H * scale
    if showSide then h = max(h, HV.SETUP_H) end
    return w, h
end

function HV.CellFor(w, h, showSide)
    local availW = w - HV.GAP - HV.HANDLE - (showSide and (HV.GAP + HV.SIDE) or 0)
    local availH = h - HV.STRIP * 2 - HV.TURN - HV.GAP * 3
    local scale = min(availW / HV.BASE, availH / BOARD_H)
    return max(30, min(90, floor(scale * HV.CELL)))
end

function HV.Layout(cellPx, showSide)
    local scale = cellPx / HV.CELL
    local bw, bh = HV.BASE * scale, BOARD_H * scale
    local S, GAP = HV.STRIP, HV.GAP
    local page = view.page
    view.strips[1]:ClearAllPoints()
    view.strips[1]:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    view.strips[1]:SetStripWidth(bw)
    view.turn:ClearAllPoints()
    view.turn:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(S + GAP))
    view.turn:SetSize(bw, HV.TURN - 6)
    view.turn.width = bw
    local boardY = -(S + GAP + HV.TURN)
    view.holder:ClearAllPoints()
    view.holder:SetPoint("TOPLEFT", page, "TOPLEFT", 0, boardY)
    view.holder:SetSize(bw, bh)
    view.board:SetScale(scale)
    view.strips[2]:ClearAllPoints()
    view.strips[2]:SetPoint("TOPLEFT", page, "TOPLEFT", 0, boardY - bh - GAP)
    view.strips[2]:SetStripWidth(bw)
    local total = S * 2 + HV.TURN + GAP * 3 + bh
    view.handle:ClearAllPoints()
    view.handle:SetPoint("TOPLEFT", page, "TOPLEFT", bw + GAP, boardY)
    view.handle:SetHeight(bh)
    view.side:ClearAllPoints()
    view.side:SetPoint("TOPLEFT", page, "TOPLEFT", bw + GAP * 2 + HV.HANDLE, 0)
    view.side:SetHeight(max(total, HV.SETUP_H))
    if showSide then view.side:Show() else view.side:Hide() end
    view.toggle:SetIcon(nil, showSide and ">" or "<")
    view.banner:ClearAllPoints()
    view.banner:SetPoint("CENTER", page, "TOPLEFT", bw / 2, boardY - bh / 2)
    local logH = max(50, max(total, HV.SETUP_H) - 128 - (9 * 18 + 26) - 6 - 34)
    view.logBox:SetHeight(logH)
    view.log:Resize(HV.SIDE - 8, logH - 26)
end

------------------------------------------------------------------------
-- Interaction
------------------------------------------------------------------------
function HV.Visible()
    return ns.UI.IsVisibleTab and ns.UI.IsVisibleTab("haplay")
end

local function Setting(s)
    return s and s.phase == "setup" and not s.ready and s.mode ~= "spectate"
end

-- Moves from the selected unit: { [to] = "move" | "attack" }.
local function Targets()
    local out = {}
    if not view.sel or not HA.MyTurn() then return out end
    for _, m in ipairs(HA.MyMoves()) do
        if m.from == view.sel then out[m.to] = m.attack and "attack" or "move" end
    end
    return out
end

function HV.OnSquareClick(idx)
    local s = HA.current
    if not s then return end
    if Setting(s) then
        if not HA.IN_ZONE[s.mySide][idx] then view.sel = nil; HV.Refresh() return end
        if view.sel then
            if view.sel ~= idx then HA.Swap(view.sel, idx); A.Play("haStep") end
            view.sel = nil
        elseif HA.SetupRank(idx) then
            view.sel = idx
            ns.Sound("select")
        end
        HV.Refresh()
        return
    end
    if not HA.MyTurn() then return end
    local u = s.cells[idx]
    if view.sel then
        local t = Targets()
        if t[idx] then
            local from = view.sel
            view.sel = nil
            HA.Move(from, idx)
            HV.Refresh()
            return
        end
    end
    if u and u.side == s.mySide and HA.Movable(u.rank) then
        view.sel = (view.sel ~= idx) and idx or nil
        ns.Sound("select")
    else
        view.sel = nil
    end
    HV.Refresh()
end

function HV.ShowUnitTip(sq)
    local s = HA.current
    if not s or not GameTooltip then return end
    local rank, mine
    if Setting(s) or s.phase == "setup" then
        rank, mine = HA.SetupRank(sq.idx), true
    else
        local u = s.cells[sq.idx]
        if not u then return end
        rank, mine = u.rank, u.side == s.mySide
        if not rank then
            GameTooltip:SetOwner(sq, "ANCHOR_RIGHT")
            GameTooltip:SetText("Unknown enemy unit", 1, 0.3, 0.25)
            GameTooltip:AddLine(u.moved and "It has moved, so it is not a Bomb or the Banner." or "It has not moved yet.", 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
    end
    if not rank then return end
    GameTooltip:SetOwner(sq, "ANCHOR_RIGHT")
    GameTooltip:SetText((mine and "Your " or "Enemy ") .. HA.NAME[rank], 1, 0.82, 0)
    if HA.RANK[rank] then GameTooltip:AddLine("Rank " .. HA.RANK[rank], 1, 1, 1) end
    local notes = {
        W = "The strongest unit - but the Assassin can strike it down.",
        X = "Moves any distance in a straight line.",
        S = "The only unit that can defuse a Bomb.",
        R = "Defeats the Warlord when it attacks first.",
        B = "Never moves. Destroys any attacker except a Sapper.",
        N = "Never moves. If it is taken, the battle is lost.",
    }
    if notes[rank] then GameTooltip:AddLine(notes[rank], 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function Fallen(s)
    local out = { [s.mySide] = {}, [s.theirSide] = {} }
    for _, m in ipairs(s.moves) do
        if m.res then
            local other = HA.Other(m.side)
            if m.res == "a" or m.res == "defuse" or m.res == "banner" then out[other][m.dr] = (out[other][m.dr] or 0) + 1
            elseif m.res == "d" then out[m.side][m.ar] = (out[m.side][m.ar] or 0) + 1
            else
                out[m.side][m.ar] = (out[m.side][m.ar] or 0) + 1
                out[other][m.dr] = (out[other][m.dr] or 0) + 1
            end
        end
    end
    return out
end
HV.Fallen = Fallen

local RES_TEXT = { a = "won", d = "lost", both = "both fell", defuse = "defused it", banner = "TOOK THE BANNER" }

local function LogLines(s)
    local lines = {}
    local spect = s.mode == "spectate"
    for i, m in ipairs(s.moves) do
        local mine = m.side == s.mySide
        local who = spect and ns.ShortName(mine and s.host or s.guest) or (mine and "You" or (s.mode == "ai" and "Computer" or ns.ShortName(s.opp)))
        local text
        if m.res then
            local color = (m.res == "a" or m.res == "defuse" or m.res == "banner") == mine and "40ff40" or "ff5040"
            if m.res == "both" then color = "d0d0d0" end
            text = string.format("%s: %s attacked %s - |cff%s%s|r", who, HA.NAME[m.ar], HA.NAME[m.dr], color, RES_TEXT[m.res])
        else
            text = string.format("%s: %s to %s", who, HA.SquareName(m.from), HA.SquareName(m.to))
        end
        lines[#lines + 1] = "|cffaaaaaa" .. i .. ".|r " .. text
    end
    return lines
end

local GREEN, RED, GOLD, GREY = { 0.1, 0.45, 0.12 }, { 0.5, 0.08, 0.06 }, { 0.5, 0.36, 0.05 }, { 0.2, 0.2, 0.22 }

function HV.RefreshTurn(s)
    local turn = view.turn
    if not s or s.phase == "over" then turn:Hide() return end
    local left = HA.TimeLeft()
    local secs = string.format("%d", math.ceil(left))
    local who = s.mode == "ai" and "THE COMPUTER" or string.upper(ns.ShortName((s.mode == "spectate" and s.guest) or s.opp or "?"))
    local bg, text, hint, urgent = GREY, "", "", false
    if s.mode == "spectate" then
        text = s.phase == "setup" and "THE ARMIES ARE DEPLOYING..." or "BATTLE IN PROGRESS"
        secs = ""
    elseif s.phase == "setup" and not s.ready then
        bg, text, urgent = GOLD, "DEPLOY YOUR ARMY", true
        hint = "Click a unit, then a square to move it"
    elseif s.phase == "setup" then
        text = "READY - WAITING FOR " .. who
        secs = ""
    elseif s.awaiting then
        bg, text = GREEN, "CHARGE!"
    elseif s.turn == s.mySide then
        bg, text, urgent = GREEN, "YOUR MOVE!", true
        hint = "Click a unit, then where to go"
        if s.missed > 0 then hint = hint .. string.format("   |cffff8040missed %d/%d|r", s.missed, HA.MAX_MISSED) end
    else
        bg, text = RED, who .. " IS MOVING..."
    end
    turn.bg:SetColorTexture(bg[1], bg[2], bg[3], 0.92)
    turn.shine:SetVertexColor(bg[1] * 2, bg[2] * 2, bg[3] * 2)
    turn.text:SetText(text)
    turn.hint:SetText(hint)
    turn.sub:SetText(secs ~= "" and (secs .. "s") or "")
    if urgent and left < 10 then turn.sub:SetTextColor(1, 0.3, 0.2) else turn.sub:SetTextColor(1, 1, 1) end
    turn.urgent = urgent
    turn:Show()
    W.FitBanner(turn, turn.width, 22)
end

function HV.ResultText(s)
    if s.mode == "spectate" then
        if s.winner then return ns.ShortName(s.winner) .. " wins the battle." end
        return "The battle ended in a draw."
    end
    local text
    local R = {
        win = { banner = "You took their Banner.", stuck = "They had no unit left that could move.", resign = "They surrendered.",
            time = "They ran out of time.", abandoned = "They left the battle." },
        loss = { banner = "They took your Banner.", stuck = "You had no unit left that could move.", resign = "You surrendered.",
            time = "You missed too many turns." },
    }
    if s.outcome == "win" then text = "|cff40ff40Victory!|r " .. (R.win[s.reason] or "")
    elseif s.outcome == "loss" then text = "|cffff5040Defeat.|r " .. (R.loss[s.reason] or "")
    elseif s.outcome == "draw" then text = "|cffd0d0d0Draw.|r " .. HA.MAX_MOVES .. " moves without a winner."
    elseif s.outcome == "disputed" then text = "|cffff8040Disputed.|r This battle does not count."
    else text = "Battle called off." end
    if s.mode == "online" and s.outcome ~= "abort" then
        if s.verified == true then
            text = text .. "\n|cff40ff40Fair-play check passed:|r every move matched their setup."
        elseif s.verified == false then
            text = text .. "\n|cffff4030Fair-play check failed:|r " .. (s.cheat or "") .. "."
        elseif s.cheat then
            text = text .. "\n|cffff4030" .. s.cheat .. ".|r"
        else
            text = text .. "\n|cffaaaaaaChecking their setup...|r"
        end
    end
    return text
end

function HV.RefreshSetup()
    if HA.current and HA.current.phase ~= "over" then view.backButton:Show() else view.backButton:Hide() end
    local seek = G.seek
    if seek and G.Seeking("ha") then
        local secs = floor(ns.Now() - (seek.since or ns.Now()))
        view.findButton:SetText(string.format("Searching... %d:%02d  (cancel)", floor(secs / 60), secs % 60))
    else
        view.findButton:SetText("Find Random Opponent")
    end
    if not C.Joined() and #C.GroupDists() == 0 then
        view.queueNote:SetText("|cffaaaaaaConnecting to the network...|r")
    else
        local n = 0
        for _, o in pairs(P.online) do if o.status == "a" then n = n + 1 end end
        view.queueNote:SetText(string.format("|cffaaaaaa%d looking for a Hidden Army battle|r", n))
    end
    view.aiButton:SetText(HA.LEVELS[ns.db.settings.haLevel or 2])
    if G.outgoing and not G.outgoing.q and G.outgoing.game == "ha" then
        view.challengeButton:SetText("Cancel")
        view.setupNote:SetText("|cffffd100Waiting for " .. ns.ShortName(G.outgoing.to) .. " to answer...|r")
    else
        view.challengeButton:SetText("Challenge")
        view.setupNote:SetText("Type a name, or leave it empty to challenge your target.")
    end
end

function HV.Refresh()
    if not view.page then return end
    local s = HA.current
    if view.orientedFor ~= MySide() then OrientBoard() end
    local b = view.board
    local myF, theirF = Factions(s)

    -- Units
    local used = 0
    local function Place(idx, rank, faction, mine, unit)
        used = used + 1
        local t = b.tokens[used]
        if not t then return end
        local x, y = SquareOrigin(idx)
        t:ClearAllPoints()
        t:SetPoint("CENTER", b, "TOPLEFT", x + HV.CELL / 2, y - HV.CELL / 2)
        SetToken(t, rank, faction, mine, unit)
        t.idx = idx
        t:SetAlpha((view.sel == idx) and 0.6 or 1)
        if unit and unit.exposed and not unit.revealed then t:SetAlpha(0.75) end
    end
    if s and s.phase == "setup" then
        for k, idx in ipairs(HA.ZONE[s.mySide]) do
            local ch = string.sub(s.layout, k, k)
            if ch ~= "." and s.mode ~= "spectate" then Place(idx, ch, myF, true) end
        end
    elseif s then
        for idx = 1, 64 do
            local u = s.cells[idx]
            if u then
                local mine = u.side == s.mySide
                local show = (mine and s.mode ~= "spectate") or u.revealed or u.exposed
                Place(idx, show and u.rank or nil, mine and myF or theirF, mine, u)
            end
        end
    end
    for i = used + 1, #b.tokens do b.tokens[i]:Hide() end

    -- Squares: setup zone, selection, targets, last move
    local targets = Targets()
    local setting = Setting(s)
    for idx, sq in ipairs(b.squares) do
        if setting and HA.IN_ZONE[s.mySide][idx] then sq.zone:Show() else sq.zone:Hide() end
        local t = targets[idx]
        if view.sel == idx then
            sq.hl:SetColorTexture(1, 0.85, 0.2, 0.45); sq.hl:Show()
        elseif t == "attack" then
            sq.hl:SetColorTexture(1, 0.25, 0.2, 0.45); sq.hl:Show()
        elseif s and s.last and s.phase ~= "setup" and (s.last.from == idx or s.last.to == idx) then
            sq.hl:SetColorTexture(1, 0.9, 0.5, 0.18); sq.hl:Show()
        else
            sq.hl:Hide()
        end
        if t == "move" then sq.dot:SetVertexColor(0.4, 1, 0.4, 0.8); sq.dot:Show() else sq.dot:Hide() end
    end
    HV.RefreshTurn(s)

    -- Strips
    local timeLeft = s and HA.TimeLeft() or nil
    if s then
        local spect = s.mode == "spectate"
        local bottom = spect and s.host or ns.me
        local top = spect and s.guest or (s.mode == "ai" and s.oppName or s.opp)
        local myMove = s.phase == "play" and s.turn == s.mySide
        local mineState, theirState = "", ""
        if s.phase == "setup" then
            mineState = s.ready and "|cff40ff40Ready|r" or "|cffffd100Deploying...|r"
            theirState = (s.theirSeal or s.mode == "ai") and "|cff40ff40Ready|r" or "|cffffd100Deploying...|r"
        end
        local f = Fallen(s)
        local function Left(side) local n = 0 for _, c in pairs(f[side]) do n = n + c end return HA.UNITS - n end
        if s.phase ~= "setup" then
            mineState = string.format("Units left: |cffffffff%d|r", Left(s.mySide))
            theirState = string.format("Units left: |cffffffff%d|r", Left(s.theirSide))
        end
        UpdateStrip(view.strips[1], top, s.mode == "ai", s.phase == "play" and not myMove, theirState,
            (s.phase == "play" and not myMove and not spect) and timeLeft or nil)
        UpdateStrip(view.strips[2], bottom, false, myMove or Setting(s), mineState,
            ((myMove and not spect) or Setting(s)) and timeLeft or nil)
    else
        UpdateStrip(view.strips[1], "Opponent", true, false, "", nil)
        UpdateStrip(view.strips[2], ns.me, false, false, "", nil)
    end

    -- Side panel
    if (not s) or view.showSetup then
        view.setup:Show()
        view.gamePanel:Hide()
        HV.RefreshSetup()
        return
    end
    view.setup:Hide()
    view.gamePanel:Show()
    local spect = s.mode == "spectate"
    view.header:SetText(spect and "Watching a battle" or (s.mode == "ai" and ("Practice vs " .. s.oppName) or ("Battle vs " .. ns.ShortName(s.opp))))
    local who = s.mode == "ai" and "The computer" or ns.ShortName((spect and s.guest) or s.opp or "?")
    local status
    if s.phase == "setup" then
        if spect then status = "The armies are deploying."
        elseif s.ready then status = "|cff40ff40Army ready and sealed.|r\nWaiting for " .. who .. "..."
        else status = "|cffffd100Deploy your army.|r\nClick a unit, then another square in your rows to move or swap it." end
    elseif s.phase == "play" then
        if spect then status = "Watching " .. ns.ShortName(s.host) .. " vs " .. ns.ShortName(s.guest) .. "."
        elseif s.awaiting then status = "|cffffd100The fight is on...|r"
        elseif s.turn == s.mySide then
            status = "|cff40ff40Your move.|r\nClick one of your units, then a green dot to move or a red square to attack." ..
                (s.missed > 0 and ("\n|cffff8040Missed turns: " .. s.missed .. "/" .. HA.MAX_MISSED .. "|r") or "")
        else
            status = "|cffffd100" .. who .. " is moving...|r"
        end
    else
        status = HV.ResultText(s)
    end
    view.status:SetText(status)
    if setting then view.shuffle:Show(); view.ready:Show() else view.shuffle:Hide(); view.ready:Hide() end
    -- the armies
    local f = Fallen(s)
    for _, row in ipairs(view.roster.rows) do
        W.SetIcon(row.icon, A.UnitIcon(row.rank, myF))
        local total = HA.COUNT[row.rank]
        local mine = total - (f[s.mySide][row.rank] or 0)
        local theirs = total - (f[s.theirSide][row.rank] or 0)
        row.mine:SetText((mine == 0 and "|cff808080" or "|cffffffff") .. mine .. "|r")
        row.theirs:SetText((theirs == 0 and "|cff808080" or "|cffff9080") .. theirs .. "|r")
    end
    view.log:SetData(LogLines(s))
    view.log.offset = max(0, #view.log.data - (view.log.visible or 1))
    view.log:Update()
    if s.phase ~= "over" then
        view.newButton:Hide()
        view.resign:Show()
        if not view.resignArmed then
            view.resign:SetText(spect and "Stop Watching" or (s.phase == "setup" and s.mode == "online") and "Abort" or "Resign")
        end
    else
        view.resign:Hide()
        view.newButton:Show()
    end
end

------------------------------------------------------------------------
-- Effects and sounds
------------------------------------------------------------------------
local function Burst(idx, r, g, bb, size)
    local b = view.board
    local x, y = SquareOrigin(idx)
    local t = b.fx:CreateTexture(nil, "OVERLAY")
    t:SetTexture(W.TEX .. "burst")
    t:SetBlendMode("ADD")
    t:SetVertexColor(r, g, bb)
    t:SetPoint("CENTER", b.fx, "TOPLEFT", x + HV.CELL / 2, y - HV.CELL / 2)
    A.Tween(0.6, function(p)
        local sz = HV.CELL * (0.5 + (size or 1.6) * p)
        t:SetSize(sz, sz)
        t:SetAlpha(1 - p)
    end, function() t:Hide() end, A.Ease.outCubic)
end

local function FloatText(idx, text, r, g, bb)
    local b = view.board
    local x, y = SquareOrigin(idx)
    local fs = b.fx:CreateFontString(nil, "OVERLAY")
    fs:SetFont(A.TitleFont(), 16, "OUTLINE")
    fs:SetTextColor(r, g, bb)
    fs:SetText(text)
    fs:SetPoint("CENTER", b.fx, "TOPLEFT", x + HV.CELL / 2, y)
    A.Tween(1.4, function(p)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", b.fx, "TOPLEFT", x + HV.CELL / 2, y + 30 * p)
        fs:SetAlpha(p < 0.7 and 1 or (1 - (p - 0.7) / 0.3))
    end, function() fs:Hide() end)
end

ns.On("HA_STARTED", function(s)
    view.sel = nil
    view.showSetup = false
    view.wasMyTurn = nil
    if view.banner then view.banner:Hide() end
    if s.mode ~= "spectate" then A.Play("haMarch") end
end)

ns.On("HA_PLAY", function(s)
    A.Play("haMarch")
    ns.After(1.0, function() ns.Sound("cry" .. A.MyFaction()) end)
end)

ns.On("HA_MOVE", function(s, m)
    A.Play("haStep")
end)

ns.On("HA_FIGHT", function(s, m)
    if m.res == "banner" then
        A.Play("haFlag")
    elseif m.dr == "B" and m.res == "d" then
        A.Play("haBoom")
    elseif m.res == "defuse" then
        A.Play("vbClick")
    else
        A.Play("haClash")
    end
    if HV.Visible() and view.board then
        local mine = m.side == s.mySide
        local good = (m.res == "a" or m.res == "defuse" or m.res == "banner") == mine
        if m.res == "both" then good = nil end
        local text = HA.NAME[m.ar] .. " vs " .. HA.NAME[m.dr]
        if m.dr == "B" and m.res == "d" then
            Burst(m.to, 1, 0.45, 0.1, 2.4)
        else
            Burst(m.to, 1, 0.85, 0.4, 1.4)
        end
        if good == true then FloatText(m.to, text, 0.3, 1, 0.3)
        elseif good == false then FloatText(m.to, text, 1, 0.35, 0.25)
        else FloatText(m.to, text, 0.9, 0.9, 0.9) end
    end
end)

function HV.ShowBanner(s)
    local banner = view.banner
    local myF, theirF = Factions(s)
    local title, color, icon
    if s.mode == "spectate" then
        title, color, icon = s.winner and (ns.ShortName(s.winner) .. " wins!") or "Draw", { 1, 0.82, 0 }, A.UnitIcon("N", myF)
    elseif s.outcome == "win" then
        title, color, icon = "Victory!", { 1, 0.82, 0 }, A.UnitIcon("N", theirF)
    elseif s.outcome == "loss" then
        title, color, icon = "Defeat", { 0.9, 0.2, 0.15 }, A.UnitIcon("N", myF)
    elseif s.outcome == "draw" then
        title, color, icon = "Draw", { 0.85, 0.85, 0.9 }, A.UnitIcon("W", myF)
    elseif s.outcome == "disputed" then
        title, color, icon = "Disputed", { 1, 0.5, 0.2 }, A.UnitIcon("B", myF)
    else
        return
    end
    banner.title:SetText(title)
    banner.title:SetTextColor(color[1], color[2], color[3])
    banner.sub:SetText(HV.ResultText(s))
    W.SetIcon(banner.icon, icon)
    banner:Show()
    banner:SetAlpha(0)
    A.Tween(0.45, function(p)
        banner:SetAlpha(min(1, p * 1.5))
        banner:SetScale(0.7 + 0.3 * p)
    end, nil, A.Ease.outBack)
end

ns.On("HA_OVER", function(s)
    view.sel = nil
    if s.outcome == "win" then
        ns.After(0.6, function() ns.Sound("win" .. A.MyFaction()) end)
    elseif s.outcome == "loss" then
        ns.After(0.6, function() ns.Sound("lose") end)
    end
    ns.After(1.0, function()
        if HA.current == s and HV.Visible() then
            HV.Refresh()
            HV.ShowBanner(s)
        end
    end)
end)

ns.On("HA_CHANGED", function(s)
    local mine = HA.MyTurn()
    if mine and not view.wasMyTurn and #s.moves > 0 then
        ns.After(0.4, function() A.Play("bsTurn") end)
        if not HV.Visible() and FlashClientIcon then pcall(FlashClientIcon) end
    end
    view.wasMyTurn = mine
    if view.banner and view.banner:IsShown() and s.phase == "over" then
        view.banner.sub:SetText(HV.ResultText(s))
    end
end)
