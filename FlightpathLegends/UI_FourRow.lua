-- Flightpath Legends - Four in a Row view: the tavern board (coins drop behind a wooden
-- plate with round holes), the column hover ghost, player strips, the turn banner,
-- the side panel and the result banner.
local _, ns = ...

local FV = {}
ns.FourView = FV

local FR, G, P, C, A, W, L = ns.FourRow, ns.Game, ns.Profile, ns.Comm, ns.Assets, ns.W, ns.Ledger
local floor, max, min = math.floor, math.max, math.min

FV.CELL = 64 -- the board is built at 64px per hole and scaled to fit
FV.PAD = 12 -- wooden frame around the holes
FV.BOARD_W = FR.COLS * FV.CELL + FV.PAD * 2
FV.BOARD_H = FV.CELL + FR.ROWS * FV.CELL + FV.PAD * 2 -- one row on top for the coin in hand
FV.STRIP = 58
FV.TURN = 42
FV.GAP = 6
FV.HANDLE = 30
FV.SIDE = 300
FV.SETUP_H = 420

local view = {}
FV.view = view

local WOOD = { 0.58, 0.40, 0.23 }
local COIN = 0.84 -- coin size relative to a hole

------------------------------------------------------------------------
-- The board
------------------------------------------------------------------------
-- Centre of a hole (row 1 at the bottom), in board coordinates (y negative down).
local function HoleCentre(col, row)
    local x = FV.PAD + (col - 1) * FV.CELL + FV.CELL / 2
    local y = -(FV.CELL + FV.PAD + (FR.ROWS - row) * FV.CELL + FV.CELL / 2)
    return x, y
end
FV.HoleCentre = HoleCentre

local function HandY() return -(FV.CELL / 2 + 2) end

local function MakeCoin(parent)
    local f = CreateFrame("Frame", nil, parent)
    local size = FV.CELL * COIN
    f:SetSize(size, size)
    f:EnableMouse(false)
    f.icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.icon:SetPoint("CENTER")
    f.icon:SetSize(size * 0.9, size * 0.9)
    f.fill = f:CreateTexture(nil, "ARTWORK", nil, 0)
    f.fill:SetTexture(W.TEX .. "dot")
    f.fill:SetPoint("CENTER")
    f.fill:SetSize(size * 0.92, size * 0.92)
    if f.CreateMaskTexture and f.icon.AddMaskTexture then
        local m = f:CreateMaskTexture()
        if m then
            m:SetAllPoints(f.icon)
            m:SetTexture(A.PortraitMask(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            f.icon:AddMaskTexture(m)
        end
    end
    f.ring = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.ring:SetTexture(W.TEX .. "token_ring")
    f.ring:SetAllPoints()
    f.shine = f:CreateTexture(nil, "ARTWORK", nil, 4)
    f.shine:SetTexture(W.TEX .. "token_shine")
    f.shine:SetAllPoints()
    f.shine:SetAlpha(0.6)
    function f:SetWho(who)
        local c = A.COINS[who]
        self.who = who
        local icon = A.CoinIcon(who)
        if icon then
            self.icon:SetTexture(icon)
            self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            self.icon:Show()
        else
            self.icon:Hide()
        end
        self.fill:SetVertexColor(c.ring[1] * 0.8, c.ring[2] * 0.8, c.ring[3] * 0.8)
        self.ring:SetVertexColor(c.ring[1], c.ring[2], c.ring[3])
    end
    f:Hide()
    return f
end

local function BuildBoard(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(FV.BOARD_W, FV.BOARD_H)
    local CS = FV.CELL
    local top = CS -- the plate starts below the coin-in-hand row
    local plateH = FR.ROWS * CS + FV.PAD * 2

    -- Behind the holes: the dark tavern wall.
    local back = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    back:SetPoint("TOPLEFT", 0, -top)
    back:SetSize(FV.BOARD_W, plateH)
    if A.HasFile(A.ART.rock) then
        back:SetTexture(A.ART.rock, "REPEAT", "REPEAT")
        back:SetVertexColor(0.22, 0.17, 0.13)
    else
        back:SetColorTexture(0.08, 0.06, 0.05, 1)
    end

    -- Coins (behind the plate, so the holes frame them as they fall).
    local coinLayer = CreateFrame("Frame", nil, b)
    coinLayer:SetAllPoints()
    coinLayer:SetFrameLevel(b:GetFrameLevel() + 2)
    coinLayer:EnableMouse(false)
    b.coins = {}
    for idx = 1, FR.CELLS do b.coins[idx] = MakeCoin(coinLayer) end

    -- The wooden plate with its holes.
    local plate = CreateFrame("Frame", nil, b)
    plate:SetAllPoints()
    plate:SetFrameLevel(b:GetFrameLevel() + 4)
    plate:EnableMouse(false)
    local function Wood(x, y, w, h)
        local t = plate:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetPoint("TOPLEFT", x, y)
        t:SetSize(w, h)
        t:SetColorTexture(WOOD[1] * 0.74, WOOD[2] * 0.74, WOOD[3] * 0.74, 1)
        return t
    end
    Wood(0, -top, FV.BOARD_W, FV.PAD) -- top rail
    Wood(0, -(top + plateH - FV.PAD), FV.BOARD_W, FV.PAD) -- bottom rail
    Wood(0, -(top + FV.PAD), FV.PAD, FR.ROWS * CS) -- left rail
    Wood(FV.BOARD_W - FV.PAD, -(top + FV.PAD), FV.PAD, FR.ROWS * CS) -- right rail
    b.slots = {}
    for col = 1, FR.COLS do
        for row = 1, FR.ROWS do
            local x, y = HoleCentre(col, row)
            local t = plate:CreateTexture(nil, "ARTWORK", nil, 2)
            t:SetTexture(W.TEX .. "c4_slot")
            t:SetSize(CS, CS)
            t:SetPoint("CENTER", plate, "TOPLEFT", x, y)
            t:SetVertexColor(WOOD[1], WOOD[2], WOOD[3])
            b.slots[FR.Index(col, row)] = t
        end
    end
    local edge = CreateFrame("Frame", nil, plate)
    edge:SetPoint("TOPLEFT", 0, -top)
    edge:SetSize(FV.BOARD_W, plateH)
    edge:EnableMouse(false)
    W.Background(edge, 0, 0, 0, 0, { 0.25, 0.16, 0.08, 1 })

    -- Winning line and last-move markers (above the plate).
    local marks = CreateFrame("Frame", nil, b)
    marks:SetAllPoints()
    marks:SetFrameLevel(b:GetFrameLevel() + 6)
    marks:EnableMouse(false)
    b.marks = marks
    b.wins = {}
    for k = 1, 7 do
        local t = marks:CreateTexture(nil, "OVERLAY")
        t:SetTexture(W.TEX .. "burst")
        t:SetBlendMode("ADD")
        t:SetSize(CS * 1.25, CS * 1.25)
        t:Hide()
        b.wins[k] = t
    end
    b.last = marks:CreateTexture(nil, "OVERLAY")
    b.last:SetTexture(W.TEX .. "ring")
    b.last:SetSize(CS * 0.95, CS * 0.95)
    b.last:SetVertexColor(1, 0.95, 0.6, 0.9)
    b.last:Hide()

    -- The coin in hand, above the column the mouse is over.
    b.hand = MakeCoin(marks)
    -- where the coin would land
    b.handArrow = marks:CreateTexture(nil, "OVERLAY")
    b.handArrow:SetSize(CS * 0.8, CS * 0.8)
    b.handArrow:SetTexture(W.TEX .. "ring")
    b.handArrow:SetVertexColor(0.5, 1, 0.5, 0.8)
    b.handArrow:Hide()
    -- A soft column highlight down the plate.
    b.colHL = plate:CreateTexture(nil, "ARTWORK", nil, 3)
    b.colHL:SetColorTexture(1, 0.9, 0.5, 0.12)
    b.colHL:SetSize(CS, FR.ROWS * CS)
    b.colHL:Hide()

    -- Effects
    local fx = CreateFrame("Frame", nil, b)
    fx:SetAllPoints()
    fx:SetFrameLevel(b:GetFrameLevel() + 10)
    fx:EnableMouse(false)
    b.fx = fx

    -- Column buttons (the whole column, including the hand row).
    b.cols = {}
    for col = 1, FR.COLS do
        local btn = CreateFrame("Button", nil, b)
        btn:SetSize(CS, FV.BOARD_H)
        btn:SetPoint("TOPLEFT", FV.PAD + (col - 1) * CS, 0)
        btn:SetFrameLevel(b:GetFrameLevel() + 12)
        btn.col = col
        btn:SetScript("OnEnter", function(self)
            view.hover = self.col
            FV.RefreshHand()
        end)
        btn:SetScript("OnLeave", function(self)
            if view.hover == self.col then view.hover = nil end
            FV.RefreshHand()
        end)
        btn:SetScript("OnClick", function(self) FV.OnColumnClick(self.col) end)
        b.cols[col] = btn
    end
    return b
end

------------------------------------------------------------------------
-- Strips
------------------------------------------------------------------------
local function BuildStrip(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(FV.STRIP)
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
    s.coinText = W.Label(s, "GameFontHighlightSmall")
    s.coinText:SetPoint("BOTTOMLEFT", 58, 5)
    s.coin = MakeCoin(s)
    s.coin:SetScale(0.5)
    s.timer = W.Title(s, 22)
    s.timer:SetPoint("RIGHT", -10, 0)
    s.timer:SetJustifyH("RIGHT")
    function s:SetStripWidth(w)
        self:SetWidth(w)
        self.name:SetWidth(max(60, w - 58 - 70))
        self.sub:SetWidth(max(60, w - 58 - 70))
        self.coin:ClearAllPoints()
        self.coin:SetPoint("RIGHT", self, "RIGHT", -110, 0)
    end
    return s
end

-- A player's W-L-D line in Four in a Row.
function FV.RecordLine(name)
    local rec = L.FourRow(name)
    if not rec then return "|cffaaaaaaNo games yet|r" end
    return string.format("|cff40ff40%d|r won  |cffff5040%d|r lost  |cffd0d0d0%d|r drawn", rec.fw, rec.fl, rec.fd)
end

local function UpdateStrip(s, name, isComputer, who, toMove, timeLeft, coinsLeft)
    local info = (not isComputer) and W.CharInfo(name) or nil
    local e = P.players[name]
    local faction = ns.SameName(name, ns.me) and A.MyFaction() or (e and e.f) or nil
    s.portrait:SetPlayer(name, info, faction or (isComputer and "Horde" or nil))
    local title = ""
    if not isComputer then title = "  " .. P.GameTitleText(P.TitleOf(name, "c4"), "c4") end
    s.name:SetText(W.ClassName(name, info, faction and A.ARMIES[faction] and A.ARMIES[faction].color) .. title)
    local line
    if isComputer then
        line = "|cffaaaaaaComputer opponent|r"
    else
        line = FV.RecordLine(name) .. "  |cffaaaaaa" .. A.CharLine(info) .. "|r"
    end
    s.sub:SetText(line)
    if who then
        s.coin:SetWho(who)
        s.coin:Show()
        s.coinText:SetText(string.format("%s coins  |cffaaaaaa%d left|r", A.COINS[who].name, coinsLeft or 21))
    else
        s.coin:Hide()
        s.coinText:SetText("")
    end
    if toMove then s.glow:Show() else s.glow:Hide() end
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
    local s = ns.db.settings
    local W2 = FV.SIDE - 8
    local h1 = W.Title(sp, 20, "Four in a Row")
    h1:SetPoint("TOPLEFT", 4, -2)
    local rules = W.Label(sp, "GameFontHighlightSmall",
        "Take turns dropping coins into the board. Four of yours in a line - across, down or diagonally - wins. "
        .. "A full board is a draw. A minute per move. Not rated: every game counts as a win, a loss or a draw.")
    rules:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -6)
    rules:SetWidth(W2)
    rules:SetSpacing(2)

    view.findButton = W.Button(sp, "Find Random Opponent", W2, 34, function()
        if G.seek then G.StopSeek() else G.StartSeek(0, 0, false, true, "c4") end
        ns.UI.Refresh()
    end)
    view.findButton:SetPoint("TOPLEFT", rules, "BOTTOMLEFT", 0, -14)
    view.queueNote = W.Label(sp, "GameFontHighlightSmall", "")
    view.queueNote:SetPoint("TOPLEFT", view.findButton, "BOTTOMLEFT", 2, -4)
    view.queueNote:SetWidth(W2)

    local h2 = W.Label(sp, "GameFontNormal", "Challenge by name")
    h2:SetPoint("TOPLEFT", view.queueNote, "BOTTOMLEFT", -2, -14)
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
        G.Invite(name, { game = "c4", color = "r" })
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
    h3:SetPoint("TOPLEFT", view.setupNote, "BOTTOMLEFT", 0, -14)
    view.aiButton = W.Button(sp, "", 120, 24, function()
        s.c4Level = ((s.c4Level or 2) % #FR.LEVELS) + 1
        ns.UI.Refresh()
    end)
    view.aiButton:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -6)
    local aiStart = W.Button(sp, "Play vs Computer", W2 - 126, 24, function()
        FR.StartAI(s.c4Level or 2)
    end)
    aiStart:SetPoint("LEFT", view.aiButton, "RIGHT", 6, 0)

    view.backButton = W.Button(sp, "Back to the game", 140, 24, function()
        view.showSetup = false
        ns.UI.Refresh()
    end)
    view.backButton:SetPoint("BOTTOMLEFT", sp, "BOTTOMLEFT", 4, 4)
end

local function BuildGamePanel(gp)
    view.header = W.Title(gp, 18)
    view.header:SetPoint("TOPLEFT", 6, -4)
    view.status = W.Label(gp, "GameFontHighlight")
    view.status:SetPoint("TOPLEFT", 6, -30)
    view.status:SetWidth(FV.SIDE - 12)
    view.status:SetJustifyV("TOP")
    view.status:SetSpacing(3)

    local logBox = W.Card(gp)
    logBox:SetPoint("TOPLEFT", 0, -110)
    logBox:SetPoint("TOPRIGHT", 0, -110)
    view.logBox = logBox
    local lh = W.Label(logBox, "GameFontNormalSmall", "Moves")
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
        local s = FR.current
        if not s or s.phase == "over" then return end
        if s.mode == "spectate" or view.resignArmed then
            view.resignArmed = false
            FR.Resign()
            return
        end
        view.resignArmed = true
        self:SetText("Sure?")
        ns.After(3, function()
            if view.resignArmed then view.resignArmed = false; ns.UI.Refresh() end
        end)
    end)
    view.resign:SetPoint("BOTTOMLEFT", 0, 0)
    view.newButton = W.Button(gp, "New Game", 130, 26, function()
        view.showSetup = true
        ns.UI.Refresh()
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
    banner.coin = MakeCoin(banner)
    banner.coin:SetScale(1.05)
    banner.coin:SetPoint("LEFT", 14, 8)
    banner.title = W.Title(banner, 34)
    banner.title:SetPoint("TOP", 36, -16)
    banner.title:SetJustifyH("CENTER")
    banner.sub = W.Label(banner, "GameFontHighlight")
    banner.sub:SetPoint("TOP", banner.title, "BOTTOM", 0, -8)
    banner.sub:SetWidth(250)
    banner.sub:SetJustifyH("CENTER")
    banner.sub:SetSpacing(3)
    banner.again = W.Button(banner, "New Game", 110, 22, function()
        banner:Hide()
        view.showSetup = true
        ns.UI.Refresh()
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
function FV.Build(page)
    view.page = page
    view.holder = CreateFrame("Frame", nil, page)
    view.board = BuildBoard(view.holder)
    view.board:SetPoint("TOPLEFT")
    view.strips = { BuildStrip(page), BuildStrip(page) } -- 1: opponent (top), 2: you (bottom)

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
        if view.glow:IsShown() then view.glow:SetAlpha(0.45 + 0.55 * p) end
        for _, t in ipairs(view.board.wins) do
            if t:IsShown() then t:SetAlpha(0.45 + 0.5 * p) end
        end
    end)
    turn:Hide()
    view.turn = turn

    -- A glowing frame around the board while it is your move.
    local g = CreateFrame("Frame", nil, page)
    g:SetFrameLevel(page:GetFrameLevel() + 40)
    g:EnableMouse(false)
    g.edges = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 4 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 4 },
        { "TOPLEFT", "BOTTOMLEFT", 4, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 4, nil } }) do
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) end
        if e[4] then t:SetHeight(e[4]) end
        g.edges[#g.edges + 1] = t
    end
    function g:SetColor(r, gg, b)
        for _, t in ipairs(self.edges) do t:SetColorTexture(r, gg, b, 1) end
    end
    g:Hide()
    view.glow = g
    view.banner = BuildBanner(page)

    local h = CreateFrame("Frame", nil, page)
    h:SetWidth(FV.HANDLE)
    view.handle = h
    view.toggle = W.IconButton(h, FV.HANDLE - 2, nil, ">", function()
        return ns.UI.IsCollapsed() and "Show the side panel" or "Hide the side panel"
    end, function() ns.UI.SetCollapsed(not ns.UI.IsCollapsed()) end)
    view.toggle:SetPoint("TOP")

    local side = CreateFrame("Frame", nil, page)
    side:SetWidth(FV.SIDE)
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

-- Page size for a given hole size.
function FV.SizeFor(cellPx, showSide)
    local scale = cellPx / FV.CELL
    local w = FV.BOARD_W * scale + FV.GAP + FV.HANDLE + (showSide and (FV.GAP + FV.SIDE) or 0)
    local h = FV.STRIP * 2 + FV.TURN + FV.GAP * 3 + FV.BOARD_H * scale
    if showSide then h = max(h, FV.SETUP_H) end
    return w, h
end

function FV.CellFor(w, h, showSide)
    local availW = w - FV.GAP - FV.HANDLE - (showSide and (FV.GAP + FV.SIDE) or 0)
    local availH = h - FV.STRIP * 2 - FV.TURN - FV.GAP * 3
    local scale = min(availW / FV.BOARD_W, availH / FV.BOARD_H)
    return max(30, min(96, floor(scale * FV.CELL)))
end

function FV.Layout(cellPx, showSide)
    local scale = cellPx / FV.CELL
    local bw, bh = FV.BOARD_W * scale, FV.BOARD_H * scale
    local S, GAP = FV.STRIP, FV.GAP
    local page = view.page
    view.strips[1]:ClearAllPoints()
    view.strips[1]:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    view.strips[1]:SetStripWidth(bw)
    view.turn:ClearAllPoints()
    view.turn:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(S + GAP))
    view.turn:SetSize(bw, FV.TURN - 6)
    view.turn.width = bw
    local boardY = -(S + GAP + FV.TURN)
    view.holder:ClearAllPoints()
    view.holder:SetPoint("TOPLEFT", page, "TOPLEFT", 0, boardY)
    view.holder:SetSize(bw, bh)
    view.board:SetScale(scale)
    -- glow around the plate (not the coin-in-hand row)
    view.glow:ClearAllPoints()
    view.glow:SetPoint("TOPLEFT", page, "TOPLEFT", -3, boardY - FV.CELL * scale + 3)
    view.glow:SetSize(bw + 6, bh - FV.CELL * scale + 6)
    view.strips[2]:ClearAllPoints()
    view.strips[2]:SetPoint("TOPLEFT", page, "TOPLEFT", 0, boardY - bh - GAP)
    view.strips[2]:SetStripWidth(bw)
    local total = S * 2 + FV.TURN + GAP * 3 + bh
    view.handle:ClearAllPoints()
    view.handle:SetPoint("TOPLEFT", page, "TOPLEFT", bw + GAP, boardY)
    view.handle:SetHeight(bh)
    view.side:ClearAllPoints()
    view.side:SetPoint("TOPLEFT", page, "TOPLEFT", bw + GAP * 2 + FV.HANDLE, 0)
    view.side:SetHeight(max(total, FV.SETUP_H))
    if showSide then view.side:Show() else view.side:Hide() end
    view.toggle:SetIcon(nil, showSide and ">" or "<")
    view.banner:ClearAllPoints()
    view.banner:SetPoint("CENTER", page, "TOPLEFT", bw / 2, boardY - bh / 2)
    local logH = max(60, max(total, FV.SETUP_H) - 110 - 40)
    view.logBox:SetHeight(logH)
    view.log:Resize(FV.SIDE - 8, logH - 26)
end

------------------------------------------------------------------------
-- Interaction and animation
------------------------------------------------------------------------
function FV.Visible()
    return ns.UI.IsVisibleTab and ns.UI.IsVisibleTab("c4play")
end

function FV.OnColumnClick(col)
    local s = FR.current
    if not FR.MyTurn() or view.dropping then return end
    if not FR.FreeRow(s.board, col) then
        ns.Sound("click")
        return
    end
    FR.DropCoin(col)
end

-- Bounce on landing.
local function OutBounce(p)
    if p < 1 / 2.75 then return 7.5625 * p * p
    elseif p < 2 / 2.75 then p = p - 1.5 / 2.75; return 7.5625 * p * p + 0.75
    elseif p < 2.5 / 2.75 then p = p - 2.25 / 2.75; return 7.5625 * p * p + 0.9375
    else p = p - 2.625 / 2.75; return 7.5625 * p * p + 0.984375 end
end

local function Burst(b, x, y, r, g, bb, size)
    local t = b.fx:CreateTexture(nil, "OVERLAY")
    t:SetTexture(W.TEX .. "burst")
    t:SetBlendMode("ADD")
    t:SetVertexColor(r, g, bb)
    t:SetPoint("CENTER", b.fx, "TOPLEFT", x, y)
    A.Tween(0.5, function(p)
        local sz = FV.CELL * (0.5 + (size or 1.2) * p)
        t:SetSize(sz, sz)
        t:SetAlpha(1 - p)
    end, function() t:Hide() end, A.Ease.outCubic)
end

-- A coin falls from the hand row into its hole.
local function AnimateDrop(col, row, who)
    local b = view.board
    local idx = FR.Index(col, row)
    local coin = b.coins[idx]
    local x, y = HoleCentre(col, row)
    local y0 = HandY()
    coin:SetWho(who)
    coin:ClearAllPoints()
    coin:SetPoint("CENTER", b, "TOPLEFT", x, y0)
    coin:Show()
    view.anim = view.anim or {}
    view.anim[idx] = true
    local fall = 0.25 + 0.06 * (FR.ROWS - row)
    A.Play("c4Drop")
    A.Tween(fall + 0.25, function(p)
        coin:ClearAllPoints()
        coin:SetPoint("CENTER", b, "TOPLEFT", x, y0 + (y - y0) * OutBounce(p))
    end, function()
        view.anim[idx] = nil
        coin:ClearAllPoints()
        coin:SetPoint("CENTER", b, "TOPLEFT", x, y)
        A.Play("c4Land")
        FV.Refresh()
    end)
    ns.After(fall, function() Burst(b, x, y, 1, 0.85, 0.4, 0.8) end)
end

ns.On("FR_MOVE", function(s, n, col, row, who)
    if FR.current ~= s then return end
    if FV.Visible() and view.board then
        AnimateDrop(col, row, who)
    else
        A.Play("c4Land")
    end
end)

ns.On("FR_STARTED", function(s)
    view.showSetup = false
    view.wasMyTurn = nil
    view.anim = {}
    if view.banner then view.banner:Hide() end
    if s.mode ~= "spectate" then A.Play("c4Start") end
end)

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function WhoName(s, who)
    if s.mode == "spectate" then
        return ns.ShortName(who == 1 and s.white or s.black)
    end
    if who == s.myCoin then return "You" end
    return s.mode == "ai" and "Computer" or ns.ShortName(s.opp)
end

local function LogLines(s)
    local lines = {}
    for i, col in ipairs(s.moves) do
        local who = (i % 2 == 1) and 1 or 2
        local c = A.COINS[who]
        lines[#lines + 1] = string.format("|cffaaaaaa%d.|r %s |cff%s%s|r into column |cffffffff%d|r", i, WhoName(s, who),
            who == 1 and "ffd040" or "d0d8e8", string.lower(c.name), col)
    end
    return lines
end

local function CoinsLeft(s, who)
    local n = 0
    for i = 1, #s.moves do if ((i % 2 == 1) and 1 or 2) == who then n = n + 1 end end
    return 21 - n
end

-- The coin in hand follows the mouse over the columns during your turn.
function FV.RefreshHand()
    local b = view.board
    if not b then return end
    local s = FR.current
    local col = view.hover
    if col and FR.MyTurn() and FR.FreeRow(s.board, col) then
        local x = HoleCentre(col, 1)
        b.hand:SetWho(s.myCoin)
        b.hand:ClearAllPoints()
        b.hand:SetPoint("CENTER", b, "TOPLEFT", x, HandY())
        b.hand:SetAlpha(0.95)
        b.hand:Show()
        b.colHL:ClearAllPoints()
        b.colHL:SetPoint("TOPLEFT", b, "TOPLEFT", FV.PAD + (col - 1) * FV.CELL, -(FV.CELL + FV.PAD))
        b.colHL:Show()
        -- where it would land
        local row = FR.FreeRow(s.board, col)
        local hx, hy = HoleCentre(col, row)
        b.handArrow:ClearAllPoints()
        b.handArrow:SetPoint("CENTER", b, "TOPLEFT", hx, hy)
        b.handArrow:Show()
    else
        b.hand:Hide()
        b.colHL:Hide()
        b.handArrow:Hide()
    end
end

local GREEN, RED, GOLD, GREY = { 0.1, 0.45, 0.12 }, { 0.5, 0.08, 0.06 }, { 0.5, 0.36, 0.05 }, { 0.2, 0.2, 0.22 }

function FV.RefreshTurn(s)
    local turn = view.turn
    if not s or s.phase == "over" then
        turn:Hide()
        view.glow:Hide()
        return
    end
    local left = FR.TimeLeft()
    local secs = string.format("%d", math.ceil(left))
    local bg, text, hint, urgent = GREY, "", "", false
    if s.mode == "spectate" then
        text = string.upper(WhoName(s, s.turn)) .. " TO DROP"
        hint = A.COINS[s.turn].name .. " coin"
        secs = ""
        view.glow:Hide()
    elseif s.turn == s.myCoin then
        bg, text, urgent = GREEN, "YOUR TURN - DROP A COIN!", true
        hint = "Click a column"
        if s.missed > 0 then hint = hint .. string.format("   |cffff8040missed %d/%d|r", s.missed, FR.MAX_MISSED) end
        view.glow:SetColor(0.3, 1, 0.3)
        view.glow:Show()
    else
        local who = s.mode == "ai" and "The computer" or ns.ShortName(s.opp or "?")
        bg, text = RED, string.upper(who) .. " IS THINKING..."
        hint = "Plan your next move"
        view.glow:Hide()
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

function FV.ResultText(s)
    if s.mode == "spectate" then
        if s.winner then return ns.ShortName(s.winner) .. " wins." end
        return s.reason == "full" and "The board is full - a draw." or "The game is over."
    end
    local text
    if s.outcome == "win" then
        text = "|cff40ff40Victory!|r " .. ((s.reason == "four" and (s.diagonal and "Four in a diagonal line." or "Four in a row.")) or
            (s.reason == "resign" and "They resigned.") or (s.reason == "time" and "They ran out of time.") or "They left the game.")
    elseif s.outcome == "loss" then
        text = "|cffff5040Defeat.|r " .. ((s.reason == "four" and "They connected four.") or
            (s.reason == "resign" and "You resigned.") or (s.reason == "time" and "You missed too many turns.") or "")
    else
        text = "|cffd0d0d0Draw.|r The board is full."
    end
    return text .. string.format("\nCoins dropped: %d", #s.moves)
end

function FV.RefreshSetup()
    if FR.current and FR.current.phase ~= "over" then view.backButton:Show() else view.backButton:Hide() end
    local seek = G.seek
    if seek and seek.game == "c4" then
        local secs = floor(ns.Now() - (seek.since or ns.Now()))
        view.findButton:SetText(string.format("Searching... %d:%02d  (cancel)", floor(secs / 60), secs % 60))
    else
        view.findButton:SetText("Find Random Opponent")
    end
    if not C.Joined() and #C.GroupDists() == 0 then
        view.queueNote:SetText("|cffaaaaaaConnecting to the network...|r")
    else
        local n = 0
        for _, o in pairs(P.online) do if o.status == "f" then n = n + 1 end end
        view.queueNote:SetText(string.format("|cffaaaaaa%d looking for a game of Four in a Row|r", n))
    end
    view.aiButton:SetText(FR.LEVELS[ns.db.settings.c4Level or 2])
    if G.outgoing and not G.outgoing.q and G.outgoing.game == "c4" then
        view.challengeButton:SetText("Cancel")
        view.setupNote:SetText("|cffffd100Waiting for " .. ns.ShortName(G.outgoing.to) .. " to answer...|r")
    else
        view.challengeButton:SetText("Challenge")
        view.setupNote:SetText("Type a name, or leave it empty to challenge your target.")
    end
end

function FV.Refresh()
    if not view.page then return end
    local s = FR.current
    local b = view.board
    local board = s and s.board or {}
    view.anim = view.anim or {}

    -- Coins
    for idx = 1, FR.CELLS do
        local coin = b.coins[idx]
        local who = board[idx]
        if who and not view.anim[idx] then
            local col, row = (idx - 1) % FR.COLS + 1, floor((idx - 1) / FR.COLS) + 1
            local x, y = HoleCentre(col, row)
            coin:SetWho(who)
            coin:ClearAllPoints()
            coin:SetPoint("CENTER", b, "TOPLEFT", x, y)
            coin:Show()
        elseif not who then
            coin:Hide()
        end
    end
    -- Last move and winning line
    if s and s.last and not view.anim[FR.Index(s.last.col, s.last.row)] and not s.line then
        local x, y = HoleCentre(s.last.col, s.last.row)
        b.last:ClearAllPoints()
        b.last:SetPoint("CENTER", b, "TOPLEFT", x, y)
        b.last:Show()
    else
        b.last:Hide()
    end
    local line = s and s.line
    local animating = false
    for _ in pairs(view.anim) do animating = true end
    for k, t in ipairs(b.wins) do
        local cell = line and line[k]
        if cell and not animating then
            local x, y = HoleCentre(cell[1], cell[2])
            t:ClearAllPoints()
            t:SetPoint("CENTER", b, "TOPLEFT", x, y)
            local c = A.COINS[board[FR.Index(cell[1], cell[2])] or 1].ring
            t:SetVertexColor(c[1], c[2], c[3])
            t:Show()
        else
            t:Hide()
        end
    end
    FV.RefreshHand()
    FV.RefreshTurn(s)

    -- Strips: opponent on top, you (or the host) at the bottom
    local timeLeft = s and FR.TimeLeft() or nil
    if s then
        local spect = s.mode == "spectate"
        local playing = s.phase == "play"
        if spect then
            local hostCoin = ns.SameName(s.white, s.host) and 1 or 2
            UpdateStrip(view.strips[1], s.guest, false, 3 - hostCoin, playing and s.turn ~= hostCoin, nil, CoinsLeft(s, 3 - hostCoin))
            UpdateStrip(view.strips[2], s.host, false, hostCoin, playing and s.turn == hostCoin, nil, CoinsLeft(s, hostCoin))
        else
            local mine = s.turn == s.myCoin
            UpdateStrip(view.strips[1], s.mode == "ai" and s.oppName or s.opp, s.mode == "ai", 3 - s.myCoin,
                playing and not mine, (playing and not mine) and timeLeft or nil, CoinsLeft(s, 3 - s.myCoin))
            UpdateStrip(view.strips[2], ns.me, false, s.myCoin, playing and mine, (playing and mine) and timeLeft or nil, CoinsLeft(s, s.myCoin))
        end
    else
        UpdateStrip(view.strips[1], "Opponent", true, nil, false, nil)
        UpdateStrip(view.strips[2], ns.me, false, nil, false, nil)
    end

    -- Side panel
    if (not s) or view.showSetup then
        view.setup:Show()
        view.gamePanel:Hide()
        FV.RefreshSetup()
        return
    end
    view.setup:Hide()
    view.gamePanel:Show()
    local spect = s.mode == "spectate"
    view.header:SetText(spect and "Watching a game" or (s.mode == "ai" and ("Practice vs " .. s.oppName) or ("Game vs " .. ns.ShortName(s.opp))))
    local status
    if s.phase == "play" then
        if spect then
            status = "Watching " .. ns.ShortName(s.host) .. " vs " .. ns.ShortName(s.guest) .. "."
        elseif s.turn == s.myCoin then
            status = "|cff40ff40Your turn!|r\nClick a column to drop a " .. string.lower(A.COINS[s.myCoin].name) .. " coin." ..
                (s.missed > 0 and ("\n|cffff8040Missed turns: " .. s.missed .. "/" .. FR.MAX_MISSED .. "|r") or "")
        else
            status = "|cffffd100" .. (s.mode == "ai" and "The computer" or ns.ShortName(s.opp)) .. " is thinking...|r"
        end
    else
        status = FV.ResultText(s)
    end
    view.status:SetText(status)
    view.log:SetData(LogLines(s))
    view.log.offset = max(0, #view.log.data - (view.log.visible or 1))
    view.log:Update()
    if s.phase ~= "over" then
        view.newButton:Hide()
        view.resign:Show()
        if not view.resignArmed then view.resign:SetText(spect and "Stop Watching" or "Resign") end
    else
        view.resign:Hide()
        view.newButton:Show()
    end
end

function FV.ShowBanner(s)
    local banner = view.banner
    local title, color, who
    if s.mode == "spectate" then
        if s.winner then title = ns.ShortName(s.winner) .. " wins!" else title = "Draw" end
        color, who = { 1, 0.82, 0 }, 1
    elseif s.outcome == "win" then
        title, color, who = "Victory!", { 1, 0.82, 0 }, s.myCoin
    elseif s.outcome == "loss" then
        title, color, who = "Defeat", { 0.9, 0.2, 0.15 }, 3 - s.myCoin
    elseif s.outcome == "draw" then
        title, color, who = "Draw", { 0.85, 0.85, 0.9 }, s.myCoin
    else
        return
    end
    banner.title:SetText(title)
    banner.title:SetTextColor(color[1], color[2], color[3])
    banner.sub:SetText(FV.ResultText(s))
    banner.coin:SetWho(who)
    banner.coin:Show()
    banner:Show()
    banner:SetAlpha(0)
    A.Tween(0.45, function(p)
        banner:SetAlpha(min(1, p * 1.5))
        banner:SetScale(0.7 + 0.3 * p)
    end, nil, A.Ease.outBack)
end

ns.On("FR_OVER", function(s)
    if s.outcome == "win" then
        ns.After(0.6, function() A.Play("c4Cheer") end)
        ns.After(1.4, function() ns.Sound("win" .. A.MyFaction()) end)
    elseif s.outcome == "loss" then
        ns.After(0.8, function() ns.Sound("lose") end)
    elseif s.outcome == "draw" then
        ns.After(0.6, function() A.Play("c4Applause") end)
    end
    ns.After(1.2, function()
        if FR.current == s and FV.Visible() then
            FV.Refresh()
            FV.ShowBanner(s)
        end
    end)
end)

-- A coin clink when our turn starts (and a taskbar flash when the window is closed).
ns.On("FR_CHANGED", function(s)
    local mine = FR.MyTurn()
    if mine and not view.wasMyTurn and #s.moves > 0 then
        ns.After(0.6, function() A.Play("c4Turn") end)
        if not FV.Visible() and FlashClientIcon then pcall(FlashClientIcon) end
    end
    view.wasMyTurn = mine
end)
