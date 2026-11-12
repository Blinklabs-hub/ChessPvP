-- Flightpath Legends - Battleship view: your fleet and the enemy waters side by side,
-- fleet placement (click a ship to pick it up, click to drop, right-click to rotate),
-- firing, effects, player strips, side panel and the result banner.
local _, ns = ...

local BV = {}
ns.BattleView = BV

local BS, G, P, C, D, A, W, L = ns.Battleship, ns.Game, ns.Profile, ns.Comm, ns.Data, ns.Assets, ns.W, ns.Ledger
local floor, max, min = math.floor, math.max, math.min

BV.CELL = 32 -- grids are built at 32px per square and scaled to fit
BV.LABEL = 18 -- room for A-J / 1-10
BV.BASE = BV.LABEL + BV.CELL * 10
BV.STRIP = 58
BV.TITLE = 20
BV.TURN = 42 -- the "whose turn" banner across both seas
BV.ROSTER = 38
BV.GAP = 6
BV.HANDLE = 30
BV.SIDE = 300
BV.SETUP_H = 420

local view = {}
BV.view = view

local WOOD = { 0.74, 0.55, 0.36 }
local SUNK = { 0.35, 0.12, 0.10 }

------------------------------------------------------------------------
-- A grid
------------------------------------------------------------------------
local function CellOrigin(grid, cell)
    local r, c = BS.RC(cell)
    return BV.LABEL + c * BV.CELL, -(BV.LABEL + r * BV.CELL)
end

local function BuildGrid(parent, kind)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(BV.BASE, BV.BASE)
    g.kind = kind
    local CS = BV.CELL

    -- The sea: the Garrison Shipyard naval map, a different part for each side.
    local sea = g:CreateTexture(nil, "BACKGROUND", nil, 1)
    sea:SetPoint("TOPLEFT", BV.LABEL, -BV.LABEL)
    sea:SetSize(CS * 10, CS * 10)
    local art = A.ART[kind == "mine" and "sea" or "sea2"]
    if A.HasFile(art) then
        sea:SetTexture(art)
        if kind == "mine" then sea:SetTexCoord(0.05, 0.55, 0.15, 0.75) else sea:SetTexCoord(0.45, 0.95, 0.2, 0.8) end
    else
        sea:SetColorTexture(0.06, 0.20, 0.32, 1)
    end
    local shade = g:CreateTexture(nil, "BACKGROUND", nil, 2)
    shade:SetAllPoints(sea)
    shade:SetColorTexture(0.02, 0.07, 0.12, 0.35)
    -- grid lines
    for i = 0, 10 do
        local v = g:CreateTexture(nil, "BORDER")
        v:SetColorTexture(1, 0.9, 0.6, (i == 0 or i == 10) and 0.6 or 0.18)
        v:SetSize(1, CS * 10)
        v:SetPoint("TOPLEFT", BV.LABEL + i * CS, -BV.LABEL)
        local h = g:CreateTexture(nil, "BORDER")
        h:SetColorTexture(1, 0.9, 0.6, (i == 0 or i == 10) and 0.6 or 0.18)
        h:SetSize(CS * 10, 1)
        h:SetPoint("TOPLEFT", BV.LABEL, -(BV.LABEL + i * CS))
    end
    -- coordinates
    for i = 0, 9 do
        local col = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        col:SetPoint("CENTER", g, "TOPLEFT", BV.LABEL + i * CS + CS / 2, -BV.LABEL / 2)
        col:SetText(i + 1)
        local row = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("CENTER", g, "TOPLEFT", BV.LABEL / 2, -(BV.LABEL + i * CS + CS / 2))
        row:SetText(string.sub(BS.ROWS, i + 1, i + 1))
    end

    -- Ships (above the sea)
    g.ships = {}
    for i = 1, #BS.FLEET do
        local s = CreateFrame("Frame", nil, g)
        s:SetFrameLevel(g:GetFrameLevel() + 2)
        s:EnableMouse(false)
        s.hull = s:CreateTexture(nil, "ARTWORK", nil, 1)
        s.hull:SetAllPoints()
        s.icon = s:CreateTexture(nil, "ARTWORK", nil, 3)
        s.icon:SetSize(CS * 0.78, CS * 0.78)
        s.icon:SetPoint("CENTER")
        s.iconRing = s:CreateTexture(nil, "ARTWORK", nil, 4)
        s.iconRing:SetTexture(W.TEX .. "token_ring")
        s.iconRing:SetPoint("CENTER")
        s.iconRing:SetSize(CS * 0.92, CS * 0.92)
        if s.CreateMaskTexture and s.icon.AddMaskTexture then
            local m = s:CreateMaskTexture()
            if m then
                m:SetAllPoints(s.icon)
                m:SetTexture(A.PortraitMask(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                s.icon:AddMaskTexture(m)
            end
        end
        s:Hide()
        g.ships[i] = s
    end

    -- Markers and highlights (above the ships)
    local top = CreateFrame("Frame", nil, g)
    top:SetAllPoints()
    top:SetFrameLevel(g:GetFrameLevel() + 6)
    top:EnableMouse(false)
    g.top = top
    g.cells = {}
    for cell = 0, 99 do
        local x, y = CellOrigin(g, cell)
        local b = CreateFrame("Button", nil, g)
        b:SetSize(CS, CS)
        b:SetPoint("TOPLEFT", x, y)
        b:SetFrameLevel(g:GetFrameLevel() + 8)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.cell = cell
        b.mark = top:CreateTexture(nil, "OVERLAY", nil, 2)
        b.mark:SetPoint("CENTER", top, "TOPLEFT", x + CS / 2, y - CS / 2)
        b.mark:Hide()
        b.fire = top:CreateTexture(nil, "OVERLAY", nil, 3)
        b.fire:SetTexture(W.TEX .. "burst")
        b.fire:SetBlendMode("ADD")
        b.fire:SetPoint("CENTER", top, "TOPLEFT", x + CS / 2, y - CS / 2)
        b.fire:SetSize(CS * 1.1, CS * 1.1)
        b.fire:Hide()
        b.ember = top:CreateTexture(nil, "OVERLAY", nil, 4)
        b.ember:SetTexture(W.TEX .. "dot")
        b.ember:SetPoint("CENTER", top, "TOPLEFT", x + CS / 2, y - CS / 2)
        b.ember:SetSize(CS * 0.32, CS * 0.32)
        b.ember:SetVertexColor(0.15, 0.03, 0.01, 0.9)
        b.ember:Hide()
        b.hl = top:CreateTexture(nil, "OVERLAY", nil, 1)
        b.hl:SetPoint("TOPLEFT", top, "TOPLEFT", x + 1, y - 1)
        b.hl:SetSize(CS - 1, CS - 1)
        b.hl:Hide()
        b:SetScript("OnEnter", function(self)
            g.hover = self.cell
            BV.Refresh()
        end)
        b:SetScript("OnLeave", function(self)
            if g.hover == self.cell then g.hover = nil end
            BV.Refresh()
        end)
        b:SetScript("OnClick", function(self, button) BV.OnCellClick(g, self.cell, button) end)
        if kind == "mine" then
            b:EnableMouseWheel(true)
            b:SetScript("OnMouseWheel", function() BV.Rotate() end)
        end
        g.cells[cell] = b
    end
    -- effects layer
    local fx = CreateFrame("Frame", nil, g)
    fx:SetAllPoints()
    fx:SetFrameLevel(g:GetFrameLevel() + 12)
    fx:EnableMouse(false)
    g.fx = fx
    return g
end

-- Draws ship i of a fleet on a grid.
local function PlaceShip(g, i, ship, tint, faction, alpha)
    local f = g.ships[i]
    if not ship then f:Hide() return end
    local CS, len = BV.CELL, BS.FLEET[i].len
    local x, y = CellOrigin(g, BS.Cell(ship.r, ship.c))
    f:ClearAllPoints()
    if ship.v then
        f:SetSize(CS - 6, CS * len - 6)
        f.hull:SetTexture(W.TEX .. "hull_v")
    else
        f:SetSize(CS * len - 6, CS - 6)
        f.hull:SetTexture(W.TEX .. "hull_h")
    end
    f:SetPoint("TOPLEFT", g, "TOPLEFT", x + 3, y - 3)
    f.hull:SetVertexColor(tint[1], tint[2], tint[3])
    local icon = A.ShipIcon(i, faction)
    if icon then
        f.icon:SetTexture(icon)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.icon:Show(); f.iconRing:Show()
        local c = faction and A.ARMIES[faction] and A.ARMIES[faction].ring or { 0.85, 0.7, 0.3 }
        f.iconRing:SetVertexColor(c[1], c[2], c[3])
    else
        f.icon:Hide(); f.iconRing:Hide()
    end
    if f.icon.SetDesaturated then f.icon:SetDesaturated(tint == SUNK) end
    f:SetAlpha(alpha or 1)
    f:Show()
end

-- Shot markers: splash for a miss, fire for a hit.
local function SetMarks(g, shots)
    for cell = 0, 99 do
        local b = g.cells[cell]
        local res = shots[cell]
        if res == "m" then
            b.mark:SetTexture(W.TEX .. "splash")
            b.mark:SetSize(BV.CELL * 0.7, BV.CELL * 0.7)
            b.mark:SetVertexColor(0.85, 0.95, 1, 0.85)
            b.mark:Show()
            b.fire:Hide(); b.ember:Hide()
        elseif res then
            b.mark:Hide()
            b.fire:SetVertexColor(1, 0.45, 0.1, 0.95)
            b.fire:Show(); b.ember:Show()
        else
            b.mark:Hide(); b.fire:Hide(); b.ember:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Strips (who is playing)
------------------------------------------------------------------------
local function BuildStrip(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(BV.STRIP)
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
    s.timer = W.Title(s, 22)
    s.timer:SetPoint("RIGHT", -10, 0)
    s.timer:SetJustifyH("RIGHT")
    s.ships = W.Label(s, "GameFontHighlightSmall")
    s.ships:SetPoint("BOTTOMLEFT", 58, 5)
    function s:SetStripWidth(w)
        self:SetWidth(w)
        self.name:SetWidth(max(60, w - 58 - 70))
        self.sub:SetWidth(max(60, w - 58 - 70))
    end
    return s
end

local function UpdateStrip(s, name, isComputer, toMove, shipsAfloat, timeLeft)
    local info = (not isComputer) and W.CharInfo(name) or nil
    local e = P.players[name]
    local faction = ns.SameName(name, ns.me) and A.MyFaction() or (e and e.f) or nil
    s.portrait:SetPlayer(name, info, faction or (isComputer and "Horde" or nil))
    local title = ""
    if not isComputer then
        title = "  " .. P.BsTitleText(ns.SameName(name, ns.me) and P.MyTitleId("bs") or (e and e.bt) or "")
    end
    s.name:SetText(W.ClassName(name, info, faction and A.ARMIES[faction].color) .. title)
    local rec = L.Battleship(name)
    local line
    if isComputer then
        line = "|cffaaaaaaComputer admiral|r"
    else
        line = rec and string.format("|cff40ff40%d|r won  |cffff5040%d|r lost", rec.bw, rec.bl) or "|cffaaaaaaNo battles yet|r"
        line = line .. "  |cffaaaaaa" .. A.CharLine(info) .. "|r"
    end
    s.sub:SetText(line)
    s.ships:SetText(shipsAfloat and ("Ships afloat: |cffffffff" .. shipsAfloat .. "/5|r") or "")
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
-- Roster (the five ships under each sea)
------------------------------------------------------------------------
local function BuildRoster(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(BV.ROSTER)
    r.items = {}
    for i = 1, #BS.FLEET do
        local b = CreateFrame("Frame", nil, r)
        b:SetSize(34, 34)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.x = b:CreateFontString(nil, "OVERLAY", "GameFontRedLarge")
        b.x:SetPoint("CENTER")
        b.x:SetText("X")
        b.pips = W.Label(b, "GameFontHighlightSmall")
        b.pips:SetPoint("BOTTOM", 0, -12)
        b:EnableMouse(true)
        W.Tooltip(b, function(self, tip)
            local f = BS.FLEET[self.i]
            tip:SetText(f.name, 1, 0.82, 0)
            tip:AddLine(f.len .. " squares", 1, 1, 1)
            if self.sunk then tip:AddLine("Sunk", 1, 0.3, 0.2) end
        end)
        b.i = i
        r.items[i] = b
    end
    function r:Arrange(w)
        local step = min(48, (w - 10) / #BS.FLEET)
        for i, b in ipairs(self.items) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * step + (step - 34) / 2, -2)
        end
    end
    return r
end

local function UpdateRoster(r, faction, sunk)
    for i, b in ipairs(r.items) do
        W.SetIcon(b.icon, A.ShipIcon(i, faction))
        b.sunk = sunk[i]
        if b.icon.SetDesaturated then b.icon:SetDesaturated(sunk[i] and true or false) end
        b.icon:SetAlpha(sunk[i] and 0.45 or 1)
        if sunk[i] then b.x:Show() else b.x:Hide() end
        b.pips:SetText(string.rep("|cffffd100o|r", BS.FLEET[i].len))
    end
end

------------------------------------------------------------------------
-- Side panel
------------------------------------------------------------------------
local function BuildSetup(sp)
    local s = ns.db.settings
    local W2 = BV.SIDE - 8
    local h1 = W.Title(sp, 20, "Battleship")
    h1:SetPoint("TOPLEFT", 4, -2)
    local rules = W.Label(sp, "GameFontHighlightSmall",
        "Sink the enemy fleet before they sink yours. Ten by ten waters, five ships, one shot per turn and a minute to fire it. Not rated: every battle counts as a win or a loss.")
    rules:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -6)
    rules:SetWidth(W2)
    rules:SetSpacing(2)

    view.findButton = W.Button(sp, "Find Random Opponent", W2, 34, function()
        if G.seek then G.StopSeek() else G.StartSeek(0, 0, false, true, "bs") end
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
        G.Invite(name, { game = "bs", color = "r" })
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
        s.bsLevel = ((s.bsLevel or 2) % #BS.LEVELS) + 1
        ns.UI.Refresh()
    end)
    view.aiButton:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -6)
    local aiStart = W.Button(sp, "Play vs Computer", W2 - 126, 24, function()
        BS.StartAI(s.bsLevel or 2)
    end)
    aiStart:SetPoint("LEFT", view.aiButton, "RIGHT", 6, 0)

    view.backButton = W.Button(sp, "Back to battle", 130, 24, function()
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
    view.status:SetWidth(BV.SIDE - 12)
    view.status:SetJustifyV("TOP")
    view.status:SetSpacing(3)

    view.shuffle = W.Button(gp, "Shuffle", 92, 26, function()
        BS.Shuffle()
        view.carry = nil
        A.Play("bsCreak")
    end)
    view.shuffle:SetPoint("TOPLEFT", 4, -110)
    view.rotate = W.Button(gp, "Rotate", 92, 26, function() BV.Rotate() end)
    view.rotate:SetPoint("LEFT", view.shuffle, "RIGHT", 4, 0)
    W.Tooltip(view.rotate, function(_, tip)
        tip:SetText("Turn a ship", 1, 0.82, 0)
        tip:AddLine("Turns the ship you are carrying, or the last ship you moved.", 1, 1, 1, true)
        tip:AddLine("You can also right-click a ship or use the mouse wheel.", 0.8, 0.8, 0.8, true)
    end)
    view.ready = W.Button(gp, "Ready!", 92, 26, function()
        view.carry = nil
        BS.Ready()
    end)
    view.ready:SetPoint("LEFT", view.rotate, "RIGHT", 4, 0)

    local logBox = W.Card(gp)
    logBox:SetPoint("TOPLEFT", 0, -144)
    logBox:SetPoint("TOPRIGHT", 0, -144)
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
        local s = BS.current
        if not s or s.phase == "over" then return end
        if s.mode == "spectate" or view.resignArmed then
            view.resignArmed = false
            BS.Resign()
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
    banner.icon = banner:CreateTexture(nil, "ARTWORK")
    banner.icon:SetSize(68, 68)
    banner.icon:SetPoint("LEFT", 16, 6)
    banner.title = W.Title(banner, 34)
    banner.title:SetPoint("TOP", 36, -16)
    banner.title:SetJustifyH("CENTER")
    banner.sub = W.Label(banner, "GameFontHighlight")
    banner.sub:SetPoint("TOP", banner.title, "BOTTOM", 36 - 36, -8)
    banner.sub:SetWidth(250)
    banner.sub:SetJustifyH("CENTER")
    banner.sub:SetSpacing(3)
    banner.again = W.Button(banner, "New Battle", 110, 22, function()
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
function BV.Build(page)
    view.page = page
    view.leftHolder = CreateFrame("Frame", nil, page)
    view.rightHolder = CreateFrame("Frame", nil, page)
    view.left = BuildGrid(view.leftHolder, "mine")
    view.left:SetPoint("TOPLEFT")
    view.right = BuildGrid(view.rightHolder, "enemy")
    view.right:SetPoint("TOPLEFT")
    view.leftTitle = W.Title(page, 15, "Your Fleet")
    view.rightTitle = W.Title(page, 15, "Enemy Waters")
    view.strips = { BuildStrip(page), BuildStrip(page) }

    -- Whose turn: a banner across both seas, pulsing.
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
        for k = 1, 2 do
            local g = view.glow[k]
            if g:IsShown() then g:SetAlpha(0.45 + 0.55 * p) end
        end
    end)
    turn:Hide()
    view.turn = turn

    -- A glowing frame around the sea to look at, and a dimmer for the other one.
    view.glow, view.dim = {}, {}
    for k = 1, 2 do
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
        view.glow[k] = g
        local d = CreateFrame("Frame", nil, page)
        d:SetFrameLevel(page:GetFrameLevel() + 39)
        d:EnableMouse(false)
        d.tex = d:CreateTexture(nil, "OVERLAY")
        d.tex:SetAllPoints()
        d.tex:SetColorTexture(0, 0, 0, 0.42)
        d:Hide()
        view.dim[k] = d
    end
    view.rosters = { BuildRoster(page), BuildRoster(page) }
    view.banner = BuildBanner(page)

    local h = CreateFrame("Frame", nil, page)
    h:SetWidth(BV.HANDLE)
    view.handle = h
    view.toggle = W.IconButton(h, BV.HANDLE - 2, nil, ">", function()
        return ns.UI.IsCollapsed() and "Show the side panel" or "Hide the side panel"
    end, function() ns.UI.SetCollapsed(not ns.UI.IsCollapsed()) end)
    view.toggle:SetPoint("TOP")

    local side = CreateFrame("Frame", nil, page)
    side:SetWidth(BV.SIDE)
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

-- Page size for a given square size.
function BV.SizeFor(cellPx, showSide)
    local gridPx = BV.BASE * cellPx / BV.CELL
    local w = gridPx * 2 + BV.GAP * 2 + BV.HANDLE + (showSide and (BV.GAP + BV.SIDE) or 0)
    local h = BV.STRIP + BV.GAP + BV.TURN + BV.TITLE + gridPx + BV.GAP + BV.ROSTER + 12
    if showSide then h = max(h, BV.SETUP_H) end
    return w, h
end

function BV.CellFor(w, h, showSide)
    local availW = (w - BV.GAP * 2 - BV.HANDLE - (showSide and (BV.GAP + BV.SIDE) or 0)) / 2
    local availH = h - BV.STRIP - BV.GAP - BV.TURN - BV.TITLE - BV.GAP - BV.ROSTER - 12
    local gridPx = min(availW, availH)
    return max(20, min(48, floor(gridPx / BV.BASE * BV.CELL)))
end

function BV.Layout(cellPx, showSide)
    local scale = cellPx / BV.CELL
    local gridPx = BV.BASE * scale
    local S, GAP = BV.STRIP, BV.GAP
    for k, holder in ipairs({ view.leftHolder, view.rightHolder }) do
        local x = (k - 1) * (gridPx + GAP)
        view.strips[k]:ClearAllPoints()
        view.strips[k]:SetPoint("TOPLEFT", view.page, "TOPLEFT", x, 0)
        view.strips[k]:SetStripWidth(gridPx)
        local title = k == 1 and view.leftTitle or view.rightTitle
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", view.page, "TOPLEFT", x + BV.LABEL * scale, -(S + GAP + BV.TURN + 2))
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", view.page, "TOPLEFT", x, -(S + GAP + BV.TURN + BV.TITLE))
        holder:SetSize(gridPx, gridPx)
        -- glow frame and dimmer over the sea itself (not the coordinate labels)
        local seaX, seaY = x + BV.LABEL * scale, -(S + GAP + BV.TURN + BV.TITLE + BV.LABEL * scale)
        local seaPx = gridPx - BV.LABEL * scale
        view.glow[k]:ClearAllPoints()
        view.glow[k]:SetPoint("TOPLEFT", view.page, "TOPLEFT", seaX - 4, seaY + 4)
        view.glow[k]:SetSize(seaPx + 8, seaPx + 8)
        view.dim[k]:ClearAllPoints()
        view.dim[k]:SetPoint("TOPLEFT", view.page, "TOPLEFT", seaX, seaY)
        view.dim[k]:SetSize(seaPx, seaPx)
        local grid = k == 1 and view.left or view.right
        grid:SetScale(scale)
        view.rosters[k]:ClearAllPoints()
        view.rosters[k]:SetPoint("TOPLEFT", view.page, "TOPLEFT", x + BV.LABEL * scale, -(S + GAP + BV.TURN + BV.TITLE + gridPx + GAP))
        view.rosters[k]:SetWidth(gridPx - BV.LABEL * scale)
        view.rosters[k]:Arrange(gridPx - BV.LABEL * scale)
    end
    local total = S + GAP + BV.TURN + BV.TITLE + gridPx + GAP + BV.ROSTER + 12
    view.turn:ClearAllPoints()
    view.turn:SetPoint("TOPLEFT", view.page, "TOPLEFT", 0, -(S + GAP))
    view.turn:SetSize(gridPx * 2 + GAP, BV.TURN - 6)
    view.turn.width = gridPx * 2 + GAP
    view.handle:ClearAllPoints()
    view.handle:SetPoint("TOPLEFT", view.page, "TOPLEFT", gridPx * 2 + GAP * 2, -(S + GAP))
    view.handle:SetHeight(gridPx)
    view.side:ClearAllPoints()
    view.side:SetPoint("TOPLEFT", view.page, "TOPLEFT", gridPx * 2 + GAP * 3 + BV.HANDLE, 0)
    view.side:SetHeight(max(total, BV.SETUP_H))
    if showSide then view.side:Show() else view.side:Hide() end
    view.toggle:SetIcon(nil, showSide and ">" or "<")
    view.banner:ClearAllPoints()
    view.banner:SetPoint("CENTER", view.page, "TOPLEFT", gridPx + GAP / 2, -(S + GAP + BV.TURN + BV.TITLE + gridPx / 2))
    local logH = max(60, max(total, BV.SETUP_H) - 144 - 40)
    view.logBox:SetHeight(logH)
    view.log:Resize(BV.SIDE - 8, logH - 26)
end

------------------------------------------------------------------------
-- Interaction
------------------------------------------------------------------------
-- Cells a carried ship would cover from the hovered cell, and whether it fits.
local function Ghost(s)
    local carry, hover = view.carry, view.left.hover
    if not (carry and hover) then return nil end
    local r, c = BS.RC(hover)
    local cells = BS.ShipCells(carry.i, r, c, carry.v)
    if not cells then
        -- show what fits inside the sea, in red
        cells = {}
        for k = 0, BS.FLEET[carry.i].len - 1 do
            local rr, cc = carry.v and r + k or r, carry.v and c or c + k
            if rr <= 9 and cc <= 9 then cells[#cells + 1] = BS.Cell(rr, cc) end
        end
        return cells, false
    end
    for _, cell in ipairs(cells) do
        local owner = s.occ[cell]
        if owner and owner ~= carry.i then return cells, false end
    end
    return cells, true
end

-- Turns the carried ship, or the last ship moved.
function BV.Rotate()
    local s = BS.current
    if not s or s.phase ~= "place" or s.ready or s.mode == "spectate" then return end
    if view.carry then
        view.carry.v = not view.carry.v
        A.Play("bsCreak")
    elseif view.lastShip then
        local i = view.lastShip
        local sh = s.myLayout[i]
        if BS.MoveShip(i, sh.r, sh.c, not sh.v) then
            A.Play("bsCreak")
        else
            ns.Print("no room to turn the " .. BS.FLEET[i].name .. " there - move it first.")
        end
    else
        ns.Print("click a ship first, then turn it.")
    end
    BV.Refresh()
end

function BV.OnCellClick(g, cell, button)
    local s = BS.current
    if not s then return end
    if g.kind == "mine" and s.phase == "place" and not s.ready and s.mode ~= "spectate" then
        if button == "RightButton" then
            if view.carry then
                view.carry.v = not view.carry.v
            else
                local i = s.occ[cell]
                if i then
                    view.lastShip = i
                    local sh = s.myLayout[i]
                    if not BS.MoveShip(i, sh.r, sh.c, not sh.v) then ns.Print("no room to turn the " .. BS.FLEET[i].name .. " there.") end
                end
            end
            A.Play("bsCreak")
            BV.Refresh()
            return
        end
        if view.carry then
            local r, c = BS.RC(cell)
            if BS.MoveShip(view.carry.i, r, c, view.carry.v) then
                A.Play("bsCreak")
                view.lastShip = view.carry.i
                view.carry = nil
            else
                ns.Sound("click")
            end
        else
            local i = s.occ[cell]
            if i then
                view.carry = { i = i, v = s.myLayout[i].v }
                view.lastShip = i
                ns.Sound("select")
            end
        end
        BV.Refresh()
        return
    end
    if g.kind == "enemy" and button == "LeftButton" and s.phase == "battle" and s.myTurn and not s.awaiting then
        BS.FireAt(cell)
    end
end

------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------
local function FloatText(g, cell, text, r, gg, b)
    local x, y = CellOrigin(g, cell)
    local fs = g.fx:CreateFontString(nil, "OVERLAY")
    fs:SetFont(A.TitleFont(), 16, "OUTLINE")
    fs:SetTextColor(r, gg, b)
    fs:SetText(text)
    fs:SetPoint("CENTER", g.fx, "TOPLEFT", x + BV.CELL / 2, y)
    A.Tween(1.3, function(p)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", g.fx, "TOPLEFT", x + BV.CELL / 2, y + 30 * p)
        fs:SetAlpha(p < 0.7 and 1 or (1 - (p - 0.7) / 0.3))
    end, function() fs:Hide() end)
end

local function Burst(g, cell, tex, r, gg, b, size, add)
    local x, y = CellOrigin(g, cell)
    local t = g.fx:CreateTexture(nil, "OVERLAY")
    t:SetTexture(W.TEX .. tex)
    if add then t:SetBlendMode("ADD") end
    t:SetVertexColor(r, gg, b)
    t:SetPoint("CENTER", g.fx, "TOPLEFT", x + BV.CELL / 2, y - BV.CELL / 2)
    A.Tween(0.55, function(p)
        local sz = BV.CELL * (0.4 + (size or 1.6) * p)
        t:SetSize(sz, sz)
        t:SetAlpha(1 - p)
    end, function() t:Hide() end, A.Ease.outCubic)
end

-- A shot landed: mine = we fired it (enemy waters), else it hit our fleet.
local function ShotEffect(s, mine, cell, res)
    local g = mine and view.right or view.left
    if s.mode == "spectate" then g = mine and view.right or view.left end
    local i = tonumber(string.match(res or "", "^s(%d)$"))
    if res == "m" then
        A.Play("bsSplash")
        if math.random() < 0.35 then ns.After(0.4, function() A.Play("bsParrot") end) end
        Burst(g, cell, "splash", 0.8, 0.95, 1, 1.4)
        FloatText(g, cell, "Miss", 0.7, 0.85, 1)
    elseif i then
        A.Play("bsBoom")
        A.Play("bsSunk")
        ns.After(0.6, function() A.Play(mine and "bsArr" or "bsDying") end)
        if i == 4 then ns.After(1.2, function() A.Play("bsSonar") end) end
        Burst(g, cell, "burst", 1, 0.4, 0.1, 3, true)
        Burst(g, cell, "splash", 0.9, 0.95, 1, 2.4)
        local name = BS.FLEET[i].name
        FloatText(g, cell, (mine and "Sunk their " or "Your ") .. name .. (mine and "!" or " sank!"), 1, 0.35, 0.2)
    else
        A.Play("bsHit")
        Burst(g, cell, "burst", 1, 0.5, 0.1, 1.8, true)
        FloatText(g, cell, "Hit!", 1, 0.6, 0.2)
    end
end

ns.On("BS_FIRING", function(s, cell)
    A.Play("bsFire")
end)

ns.On("BS_SHOT", function(s, mine, cell, res)
    if not mine then A.Play("bsFire") end
    if BV.Visible() then
        ns.After(mine and 0 or 0.35, function() ShotEffect(s, mine, cell, res) end)
    else
        A.Play(res == "m" and "bsSplash" or "bsHit")
    end
end)

ns.On("BS_STARTED", function(s)
    view.carry = nil
    view.showSetup = false
    if view.banner then view.banner:Hide() end
    view.wasMyTurn = nil
    if s.mode ~= "spectate" then
        A.Play("bsBell")
        ns.After(0.8, function() A.Play("bsGulls") end)
    end
end)

ns.On("BS_BATTLE", function(s)
    A.Play("bsHorn")
    A.Play("bsWaves")
    ns.After(1.2, function() A.Play("cry" .. A.MyFaction()) end)
end)

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function LogLines(s)
    local lines = {}
    -- merge both logs in firing order (shots alternate, the first shooter starts)
    local mineFirst = s.iFirst
    local a, b = s.myLog, s.theirLog
    local ia, ib = 1, 1
    local turnMine = mineFirst
    while ia <= #a or ib <= #b do
        local e, who
        if turnMine and ia <= #a then e, who = a[ia], "You"; ia = ia + 1
        elseif not turnMine and ib <= #b then e, who = b[ib], (s.mode == "ai" and "Computer" or ns.ShortName(s.opp)); ib = ib + 1
        elseif ia <= #a then e, who = a[ia], "You"; ia = ia + 1
        else e, who = b[ib], (s.mode == "ai" and "Computer" or ns.ShortName(s.opp)); ib = ib + 1 end
        turnMine = not turnMine
        local i = tonumber(string.match(e.res, "^s(%d)$"))
        local res = (e.res == "m" and "|cff9ac8ffmiss|r") or (i and ("|cffff5030SUNK " .. BS.FLEET[i].name .. "|r")) or "|cffff9040hit|r"
        lines[#lines + 1] = string.format("|cffaaaaaa%d.|r %s fired at |cffffffff%s|r: %s", #lines + 1, who, BS.CellName(e.cell), res)
    end
    return lines
end

function BV.Visible()
    return ns.UI.IsVisibleTab and ns.UI.IsVisibleTab("bsplay")
end

local function Afloat(sunk)
    local n = 0
    for i = 1, #BS.FLEET do if not sunk[i] then n = n + 1 end end
    return n
end

function BV.Refresh()
    if not view.page then return end
    local s = BS.current
    local myFaction = A.MyFaction()
    local spect = s and s.mode == "spectate"
    -- Opponent's faction (for ship icons)
    local oppName = s and (spect and s.guest or s.opp) or nil
    local oppE = oppName and P.players[oppName]
    local oppFaction = (oppE and oppE.f) or (myFaction == "Horde" and "Alliance" or "Horde")
    local leftName = s and (spect and s.host or ns.me) or ns.me
    local leftE = P.players[leftName]
    local leftFaction = spect and ((leftE and leftE.f) or "Alliance") or myFaction

    -- Left sea: my fleet (or the host's) and the shots fired at it.
    local left, right = view.left, view.right
    local ghostCells, ghostOk = nil, nil
    if s and not spect then
        for i = 1, #BS.FLEET do
            local carried = view.carry and view.carry.i == i
            PlaceShip(left, i, s.myLayout and s.myLayout[i], s.sunkMine[i] and SUNK or WOOD, leftFaction, carried and 0.35 or 1)
        end
        SetMarks(left, s.theirShots)
        ghostCells, ghostOk = Ghost(s)
    elseif s and spect then
        for i = 1, #BS.FLEET do
            PlaceShip(left, i, s.revealMine and s.revealMine[i], SUNK, leftFaction, 1)
        end
        SetMarks(left, s.theirShots)
    else
        for i = 1, #BS.FLEET do left.ships[i]:Hide() end
        SetMarks(left, {})
    end
    -- Right sea: the enemy (ships only once sunk, or all at the end when revealed)
    if s then
        for i = 1, #BS.FLEET do
            local ship = s.revealTheirs[i] or (s.theirLayout and s.theirLayout[i])
            PlaceShip(right, i, ship, s.sunkTheirs[i] and SUNK or { 0.5, 0.5, 0.55 }, oppFaction, s.sunkTheirs[i] and 1 or 0.55)
        end
        SetMarks(right, s.myShots)
    else
        for i = 1, #BS.FLEET do right.ships[i]:Hide() end
        SetMarks(right, {})
    end
    -- Highlights: placement ghost on the left, aiming crosshair on the right
    local ghostSet = {}
    if ghostCells then for _, cell in ipairs(ghostCells) do ghostSet[cell] = true end end
    local canFire = s and s.phase == "battle" and s.myTurn and not s.awaiting and not spect
    for cell = 0, 99 do
        local lb, rb = left.cells[cell], right.cells[cell]
        if ghostSet[cell] then
            lb.hl:SetColorTexture(ghostOk and 0.3 or 1, ghostOk and 1 or 0.25, 0.3, 0.35)
            lb.hl:Show()
        elseif left.hover == cell and s and s.phase == "place" and not s.ready and s.occ and s.occ[cell] and not view.carry then
            lb.hl:SetColorTexture(1, 0.85, 0.3, 0.25)
            lb.hl:Show()
        else
            lb.hl:Hide()
        end
        if canFire and right.hover == cell and not s.myShots[cell] then
            rb.hl:SetColorTexture(1, 0.3, 0.2, 0.35)
            rb.hl:Show()
        else
            rb.hl:Hide()
        end
    end

    -- Whose turn: banner, glowing sea and dimmed sea
    BV.RefreshTurn(s)

    -- Titles, strips and rosters
    if spect then
        view.leftTitle:SetText(ns.ShortName(s.host) .. "'s Fleet")
        view.rightTitle:SetText(ns.ShortName(s.guest) .. "'s Fleet")
    else
        view.leftTitle:SetText("Your Fleet")
        view.rightTitle:SetText("Enemy Waters")
    end
    local timeLeft = s and BS.TimeLeft() or nil
    if s then
        local inBattle = s.phase == "battle"
        local myMove = inBattle and s.myTurn
        UpdateStrip(view.strips[1], leftName, false, myMove and not spect, Afloat(s.sunkMine),
            (inBattle and s.myTurn and not spect) and timeLeft or (s.phase == "place" and not s.ready) and timeLeft or nil)
        UpdateStrip(view.strips[2], oppName or "Opponent", s.mode == "ai", inBattle and not s.myTurn and not spect, Afloat(s.sunkTheirs),
            (inBattle and not s.myTurn and not spect) and timeLeft or nil)
        UpdateRoster(view.rosters[1], leftFaction, s.sunkMine)
        UpdateRoster(view.rosters[2], oppFaction, s.sunkTheirs)
    else
        UpdateStrip(view.strips[1], ns.me, false, false, nil, nil)
        UpdateStrip(view.strips[2], "Opponent", true, false, nil, nil)
        UpdateRoster(view.rosters[1], myFaction, {})
        UpdateRoster(view.rosters[2], oppFaction, {})
    end

    -- Side panel
    if (not s) or view.showSetup then
        view.setup:Show()
        view.gamePanel:Hide()
        BV.RefreshSetup()
        return
    end
    view.setup:Hide()
    view.gamePanel:Show()
    local who = s.mode == "ai" and "the computer" or ns.ShortName(oppName or "?")
    view.header:SetText(spect and "Watching a battle" or (s.mode == "ai" and ("Practice vs " .. s.oppName) or ("Battle vs " .. ns.ShortName(s.opp))))
    local status
    if s.phase == "place" then
        if s.ready then
            status = "|cffffd100Fleet sealed and ready.|r\nWaiting for " .. who .. " to deploy..."
        else
            status = "|cffffd100Deploy your fleet.|r\nClick a ship to pick it up, click to drop it, right-click to rotate.\n" ..
                string.format("Time left: |cffffffff%d|r s", math.ceil(timeLeft or 0))
        end
    elseif s.phase == "battle" then
        if spect then
            status = "Watching " .. ns.ShortName(s.host) .. " vs " .. ns.ShortName(s.guest) .. "."
        elseif s.awaiting then
            status = "|cffffd100Cannonball away...|r"
        elseif s.myTurn then
            status = "|cff40ff40Your turn - fire!|r\nClick a square in Enemy Waters." ..
                (s.missed > 0 and ("\n|cffff8040Missed turns: " .. s.missed .. "/" .. BS.MAX_MISSED .. "|r") or "")
        else
            status = "|cffffd100" .. who .. " is taking aim...|r"
        end
    else
        status = BV.ResultText(s)
    end
    view.status:SetText(status)
    local placing = s.phase == "place" and not s.ready and not spect
    if placing then view.shuffle:Show(); view.rotate:Show(); view.ready:Show() else view.shuffle:Hide(); view.rotate:Hide(); view.ready:Hide() end
    view.log:SetData(LogLines(s))
    view.log.offset = max(0, #view.log.data - (view.log.visible or 1))
    view.log:Update()
    if s.phase ~= "over" then
        view.newButton:Hide()
        view.resign:Show()
        if not view.resignArmed then
            view.resign:SetText(spect and "Stop Watching" or (s.phase == "place" and s.mode == "online") and "Abort" or "Resign")
        end
    else
        view.resign:Hide()
        view.newButton:Show()
    end
end

local GREEN, RED, GOLD, GREY = { 0.1, 0.45, 0.12 }, { 0.5, 0.08, 0.06 }, { 0.5, 0.36, 0.05 }, { 0.2, 0.2, 0.22 }

function BV.RefreshTurn(s)
    local turn = view.turn
    local function Glow(k, color)
        if color then
            view.glow[k]:SetColor(color[1], color[2], color[3])
            view.glow[k]:Show()
        else
            view.glow[k]:Hide()
        end
    end
    local function Dim(k, on) if on then view.dim[k]:Show() else view.dim[k]:Hide() end end
    if not s or s.phase == "over" then
        turn:Hide(); Glow(1); Glow(2); Dim(1, false); Dim(2, false)
        return
    end
    local left = BS.TimeLeft()
    local secs = string.format("%d", math.ceil(left))
    local who = s.mode == "ai" and "The computer" or ns.ShortName((s.mode == "spectate" and s.guest) or s.opp or "?")
    local bg, text, hint, urgent = GREY, "", "", false
    if s.mode == "spectate" then
        bg, text = GREY, (s.phase == "place" and "The fleets are deploying..." or "Battle in progress")
        Glow(1); Glow(2); Dim(1, false); Dim(2, false)
        secs = ""
    elseif s.phase == "place" and not s.ready then
        bg, text, urgent = GOLD, "DEPLOY YOUR FLEET", true
        hint = "Click a ship to move it - right-click, mouse wheel or Rotate to turn it"
        Glow(1, { 1, 0.82, 0.2 }); Glow(2); Dim(1, false); Dim(2, true)
    elseif s.phase == "place" then
        bg, text = GREY, "Fleet sealed - waiting for " .. who
        Glow(1); Glow(2); Dim(1, false); Dim(2, true)
        secs = ""
    elseif s.myTurn then
        bg, text, urgent = GREEN, s.awaiting and "CANNONBALL AWAY..." or "YOUR TURN - FIRE!", not s.awaiting
        hint = s.awaiting and "" or "Click a square in Enemy Waters"
        if s.missed > 0 then hint = hint .. string.format("   |cffff8040missed %d/%d|r", s.missed, BS.MAX_MISSED) end
        Glow(1); Glow(2, { 0.3, 1, 0.3 }); Dim(1, true); Dim(2, false)
    else
        bg, text = RED, string.upper(who) .. " IS TAKING AIM..."
        hint = "Your fleet is under fire"
        Glow(1, { 1, 0.3, 0.2 }); Glow(2); Dim(1, false); Dim(2, true)
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

function BV.ResultText(s)
    if s.mode == "spectate" then
        return "Battle over: " .. ns.ShortName(s.winner or "?") .. " wins."
    end
    local text
    if s.outcome == "win" then
        text = "|cff40ff40Victory!|r " .. ((s.reason == "fleet") and "You sank the enemy fleet." or
            (s.reason == "resign" and "They struck their colours.") or (s.reason == "time" and "They ran out of time.") or "They left the battle.")
    elseif s.outcome == "loss" then
        text = "|cffff5040Defeat.|r " .. ((s.reason == "fleet") and "Your fleet was sunk." or
            (s.reason == "resign" and "You resigned.") or (s.reason == "time" and "You missed too many turns.") or "")
    elseif s.outcome == "disputed" then
        text = "|cffff8040Disputed.|r This battle does not count."
    else
        text = "Battle called off."
    end
    if s.mode == "online" and s.outcome ~= "abort" then
        if s.verified == true then
            text = text .. "\n|cff40ff40Fair-play check passed:|r their fleet matched every answer."
        elseif s.verified == false then
            text = text .. "\n|cffff4030Fair-play check failed:|r " .. (s.cheat or "") .. "."
        elseif s.cheat then
            text = text .. "\n|cffff4030" .. s.cheat .. ".|r"
        else
            text = text .. "\n|cffaaaaaaChecking their fleet...|r"
        end
    end
    text = text .. string.format("\nShots fired: %d", BS.ShotsFired(s))
    return text
end

function BV.RefreshSetup()
    if BS.current and BS.current.phase ~= "over" then view.backButton:Show() else view.backButton:Hide() end
    local seek = G.seek
    if seek and seek.game == "bs" then
        local secs = floor(ns.Now() - (seek.since or ns.Now()))
        view.findButton:SetText(string.format("Searching... %d:%02d  (cancel)", floor(secs / 60), secs % 60))
    else
        view.findButton:SetText("Find Random Opponent")
    end
    if not C.Joined() and #C.GroupDists() == 0 then
        view.queueNote:SetText("|cffaaaaaaConnecting to the network...|r")
    else
        local n = 0
        for _, o in pairs(P.online) do if o.status == "b" then n = n + 1 end end
        view.queueNote:SetText(string.format("|cffaaaaaa%d looking for a Battleship battle|r", n))
    end
    view.aiButton:SetText(BS.LEVELS[ns.db.settings.bsLevel or 2])
    if G.outgoing and not G.outgoing.q and G.outgoing.game == "bs" then
        view.challengeButton:SetText("Cancel")
        view.setupNote:SetText("|cffffd100Waiting for " .. ns.ShortName(G.outgoing.to) .. " to answer...|r")
    else
        view.challengeButton:SetText("Challenge")
        view.setupNote:SetText("Type a name, or leave it empty to challenge your target.")
    end
end

function BV.ShowBanner(s)
    local banner = view.banner
    local title, color
    if s.mode == "spectate" then
        title, color = ns.ShortName(s.winner or "?") .. " wins!", { 1, 0.82, 0 }
    elseif s.outcome == "win" then
        title, color = "Victory!", { 1, 0.82, 0 }
    elseif s.outcome == "loss" then
        title, color = "Defeat", { 0.9, 0.2, 0.15 }
    elseif s.outcome == "disputed" then
        title, color = "Disputed", { 1, 0.5, 0.2 }
    else
        return
    end
    banner.title:SetText(title)
    banner.title:SetTextColor(color[1], color[2], color[3])
    banner.sub:SetText(BV.ResultText(s))
    W.SetIcon(banner.icon, A.ShipIcon(s.outcome == "loss" and 2 or 1, A.MyFaction()))
    banner:Show()
    banner:SetAlpha(0)
    A.Tween(0.45, function(p)
        banner:SetAlpha(min(1, p * 1.5))
        banner:SetScale(0.7 + 0.3 * p)
    end, nil, A.Ease.outBack)
end

ns.On("BS_OVER", function(s)
    if s.outcome == "win" then
        A.Play("bsCheer")
        ns.After(0.9, function() ns.Sound("win" .. A.MyFaction()) end)
    elseif s.outcome == "loss" then
        A.Play("bsDying")
        ns.After(0.9, function() ns.Sound("lose") end)
    end
    ns.After(0.8, function()
        if BS.current == s and BV.Visible() then BV.ShowBanner(s) end
    end)
end)

-- A bell when our turn starts (and a taskbar flash when the window is closed).
ns.On("BS_CHANGED", function(s)
    local mine = s.phase == "battle" and s.myTurn and not s.awaiting and s.mode ~= "spectate"
    if mine and not view.wasMyTurn then
        A.Play("bsTurn")
        if not BV.Visible() and FlashClientIcon then pcall(FlashClientIcon) end
    end
    view.wasMyTurn = mine
end)

-- Keep the banner text current while the fair-play check completes.
ns.On("BS_CHANGED", function(s)
    if view.banner and view.banner:IsShown() and s.phase == "over" then
        view.banner.sub:SetText(BV.ResultText(s))
    end
end)
