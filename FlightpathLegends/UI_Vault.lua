-- Flightpath Legends - Vault Breaker view: your vault (your code and their guesses) and theirs
-- (your guesses and the pins they gave), the gem palette, player strips, the turn banner,
-- the side panel and the result banner.
local _, ns = ...

local VV = {}
ns.VaultView = VV

local VB, G, P, C, A, W, L = ns.Vault, ns.Game, ns.Profile, ns.Comm, ns.Assets, ns.W, ns.Ledger
local floor, max, min = math.floor, math.max, math.min

VV.CELL = 36 -- the vaults are built at 36px per gem and scaled to fit
VV.LABEL = 24 -- round numbers
VV.PINS = 36
VV.CODE = 50 -- the code row at the top of each vault
VV.PANEL_W = VV.LABEL + VB.PEGS * VV.CELL + VV.PINS + 10
VV.PANEL_H = VV.CODE + 8 + VB.ROUNDS * VV.CELL + 8
VV.STRIP = 58
VV.TURN = 42
VV.TITLE = 20
VV.PALETTE = 58
VV.GAP = 6
VV.HANDLE = 30
VV.SIDE = 300
VV.SETUP_H = 420

local view = { draft = {} }
VV.view = view

local GOLD, SILVER = { 1, 0.8, 0.2 }, { 0.85, 0.88, 0.95 }

------------------------------------------------------------------------
-- Gems and pins
------------------------------------------------------------------------
local function MakeGem(parent, size)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(size, size)
    f.socket = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.socket:SetTexture(W.TEX .. "dot")
    f.socket:SetPoint("CENTER")
    f.socket:SetSize(size * 0.86, size * 0.86)
    f.socket:SetVertexColor(0.05, 0.04, 0.035, 0.95)
    f.icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.icon:SetPoint("CENTER")
    f.icon:SetSize(size * 0.78, size * 0.78)
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
    f.ring:SetPoint("CENTER")
    f.ring:SetSize(size * 0.95, size * 0.95)
    f.ring:SetVertexColor(0.45, 0.36, 0.18)
    f.mark = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.mark:SetPoint("CENTER")
    f.mark:Hide()
    function f:SetGem(n, hidden)
        self.gem = n
        if hidden then
            self.icon:Hide()
            self.mark:SetText("?")
            self.mark:Show()
            self.ring:SetVertexColor(0.55, 0.45, 0.2)
        elseif n then
            local icon = A.GemIcon(n)
            local c = A.GEMS[n].color
            if icon then
                self.icon:SetTexture(icon)
                self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                self.icon:SetVertexColor(1, 1, 1)
            else
                self.icon:SetTexture(W.TEX .. "dot")
                self.icon:SetTexCoord(0, 1, 0, 1)
                self.icon:SetVertexColor(c[1], c[2], c[3])
            end
            self.icon:Show()
            self.mark:Hide()
            self.ring:SetVertexColor(c[1], c[2], c[3])
        else
            self.icon:Hide()
            self.mark:Hide()
            self.ring:SetVertexColor(0.45, 0.36, 0.18)
        end
    end
    f:SetGem(nil)
    return f
end

local function MakePins(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.dots = {}
    local d = size * 0.34
    for k = 1, 4 do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetTexture(W.TEX .. "dot")
        t:SetSize(d, d)
        local cx = (k - 1) % 2 == 0 and -size * 0.2 or size * 0.2
        local cy = k <= 2 and size * 0.2 or -size * 0.2
        t:SetPoint("CENTER", f, "CENTER", cx, cy)
        f.dots[k] = t
    end
    function f:SetPins(gold, silver)
        self.gold, self.silver = gold, silver
        for k = 1, 4 do
            local t = self.dots[k]
            if gold and k <= gold then t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
            elseif gold and k <= gold + silver then t:SetVertexColor(SILVER[1], SILVER[2], SILVER[3], 1)
            else t:SetVertexColor(0.12, 0.1, 0.08, 0.9) end
        end
    end
    f:SetPins(nil)
    return f
end

------------------------------------------------------------------------
-- A vault panel: the code on top, then ten rounds of guesses
------------------------------------------------------------------------
local function RowY(r) return -(VV.CODE + 8 + (r - 1) * VV.CELL) end

local function BuildPanel(parent, kind)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(VV.PANEL_W, VV.PANEL_H)
    p.kind = kind
    local bg = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    if A.HasFile(A.ART.rock) then
        bg:SetTexture(A.ART.rock, "REPEAT", "REPEAT")
        bg:SetVertexColor(0.32, 0.29, 0.26)
    else
        bg:SetColorTexture(0.12, 0.11, 0.1, 1)
    end
    W.Background(p, 0, 0, 0, 0, { 0.62, 0.5, 0.2, 1 })
    -- the vault door plate behind the code
    local plate = p:CreateTexture(nil, "BACKGROUND", nil, 2)
    plate:SetPoint("TOPLEFT", 4, -4)
    plate:SetPoint("TOPRIGHT", -4, -4)
    plate:SetHeight(VV.CODE - 4)
    plate:SetColorTexture(0.18, 0.14, 0.08, 0.9)
    p.lock = p:CreateTexture(nil, "ARTWORK")
    p.lock:SetSize(32, 32)
    p.lock:SetPoint("LEFT", plate, "LEFT", 4, 0)
    W.SetIcon(p.lock, "Interface\\Icons\\inv_misc_lockbox_1")
    p.code = {}
    for k = 1, VB.PEGS do
        local g = MakeGem(p, VV.CELL + 4)
        g:SetPoint("CENTER", p, "TOPLEFT", VV.LABEL + (k - 1) * VV.CELL + VV.CELL / 2 + 8, -(VV.CODE / 2 + 2))
        g:SetScript("OnClick", function() VV.OnSlotClick("code", k) end)
        p.code[k] = g
    end
    p.rows = {}
    for r = 1, VB.ROUNDS do
        local row = {}
        local y = RowY(r)
        row.hl = p:CreateTexture(nil, "BORDER")
        row.hl:SetPoint("TOPLEFT", 4, y)
        row.hl:SetSize(VV.PANEL_W - 8, VV.CELL)
        row.hl:SetColorTexture(0.3, 1, 0.3, 0.14)
        row.hl:Hide()
        row.stripe = p:CreateTexture(nil, "BACKGROUND", nil, 3)
        row.stripe:SetPoint("TOPLEFT", 4, y)
        row.stripe:SetSize(VV.PANEL_W - 8, VV.CELL)
        row.stripe:SetColorTexture(0, 0, 0, r % 2 == 0 and 0.22 or 0.1)
        row.num = W.Label(p, "GameFontNormalSmall", tostring(r))
        row.num:SetPoint("CENTER", p, "TOPLEFT", VV.LABEL / 2 + 2, y - VV.CELL / 2)
        row.gems = {}
        for k = 1, VB.PEGS do
            local g = MakeGem(p, VV.CELL)
            g:SetPoint("TOPLEFT", VV.LABEL + (k - 1) * VV.CELL, y)
            g:SetScript("OnClick", function() VV.OnSlotClick(kind, k, r) end)
            row.gems[k] = g
        end
        row.pins = MakePins(p, VV.PINS)
        row.pins:SetPoint("TOPLEFT", VV.LABEL + VB.PEGS * VV.CELL + 4, y)
        p.rows[r] = row
    end
    p.fx = CreateFrame("Frame", nil, p)
    p.fx:SetAllPoints()
    p.fx:SetFrameLevel(p:GetFrameLevel() + 10)
    p.fx:EnableMouse(false)
    return p
end

------------------------------------------------------------------------
-- Strips (as in the other games)
------------------------------------------------------------------------
local function BuildStrip(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(VV.STRIP)
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

function VV.RecordLine(name)
    local rec = L.Record(name, "vb")
    if not rec then return "|cffaaaaaaNo games yet|r" end
    return string.format("|cff40ff40%d|r won  |cffff5040%d|r lost  |cffd0d0d0%d|r drawn", rec.w, rec.l, rec.d)
end

local function UpdateStrip(s, name, isComputer, active, state, timeLeft)
    local info = (not isComputer) and W.CharInfo(name) or nil
    local e = P.players[name]
    local faction = ns.SameName(name, ns.me) and A.MyFaction() or (e and e.f) or nil
    s.portrait:SetPlayer(name, info, faction or (isComputer and "Horde" or nil))
    local title = ""
    if not isComputer then title = "  " .. P.GameTitleText(P.TitleOf(name, "vb"), "vb") end
    s.name:SetText(W.ClassName(name, info, faction and A.ARMIES[faction] and A.ARMIES[faction].color) .. title)
    s.sub:SetText(isComputer and "|cffaaaaaaComputer safecracker|r" or (VV.RecordLine(name) .. "  |cffaaaaaa" .. A.CharLine(info) .. "|r"))
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
    local s = ns.db.settings
    local W2 = VV.SIDE - 8
    local h1 = W.Title(sp, 20, "Vault Breaker")
    h1:SetPoint("TOPLEFT", 4, -2)
    local rules = W.Label(sp, "GameFontHighlightSmall",
        "Lock your vault with four gems, then race to crack theirs. Each round you both guess at once: "
        .. "a |cffffcc33gold pin|r is a right gem in the right slot, a |cffd8e0f0silver pin|r a right gem in the wrong slot. "
        .. "Ten guesses, a minute each. Not rated: wins, losses and draws.")
    rules:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -6)
    rules:SetWidth(W2)
    rules:SetSpacing(2)

    view.findButton = W.Button(sp, "Find Random Opponent", W2, 34, function()
        if G.seek then G.StopSeek() else G.StartSeek(0, 0, false, true, "vb") end
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
        G.Invite(name, { game = "vb", color = "r" })
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
        s.vbLevel = ((s.vbLevel or 2) % #VB.LEVELS) + 1
        ns.UI.Refresh()
    end)
    view.aiButton:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -6)
    local aiStart = W.Button(sp, "Play vs Computer", W2 - 126, 24, function()
        VB.StartAI(s.vbLevel or 2)
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
    view.status:SetWidth(VV.SIDE - 12)
    view.status:SetJustifyV("TOP")
    view.status:SetSpacing(3)

    local logBox = W.Card(gp)
    logBox:SetPoint("TOPLEFT", 0, -110)
    logBox:SetPoint("TOPRIGHT", 0, -110)
    view.logBox = logBox
    local lh = W.Label(logBox, "GameFontNormalSmall", "Rounds")
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
        local s = VB.current
        if not s or s.phase == "over" then return end
        if s.mode == "spectate" or view.resignArmed then
            view.resignArmed = false
            VB.Resign()
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
function VV.Build(page)
    view.page = page
    view.leftHolder = CreateFrame("Frame", nil, page)
    view.rightHolder = CreateFrame("Frame", nil, page)
    view.left = BuildPanel(view.leftHolder, "mine")
    view.left:SetPoint("TOPLEFT")
    view.right = BuildPanel(view.rightHolder, "theirs")
    view.right:SetPoint("TOPLEFT")
    view.leftTitle = W.Title(page, 15, "Your Vault")
    view.rightTitle = W.Title(page, 15, "Their Vault")
    view.strips = { BuildStrip(page), BuildStrip(page) }

    local turn = CreateFrame("Frame", nil, page)
    turn.bg = turn:CreateTexture(nil, "BACKGROUND")
    turn.bg:SetAllPoints()
    turn.shine = turn:CreateTexture(nil, "BORDER")
    turn.shine:SetAllPoints()
    turn.shine:SetTexture(W.TEX .. "burst")
    turn.shine:SetBlendMode("ADD")
    W.Background(turn, 0, 0, 0, 0, { 0.9, 0.75, 0.3, 0.9 })
    turn.text = W.Title(turn, 20)
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
        for _, panel in ipairs({ view.left, view.right }) do
            for _, row in ipairs(panel.rows) do
                if row.hl:IsShown() then row.hl:SetAlpha(0.5 + 0.5 * p) end
            end
        end
    end)
    turn:Hide()
    view.turn = turn

    -- the gem palette
    local pal = CreateFrame("Frame", nil, page)
    pal:SetHeight(VV.PALETTE)
    W.Background(pal, 0.1, 0.08, 0.06, 0.92, { 0.55, 0.45, 0.2, 0.9 })
    view.palette = pal
    view.gemButtons = {}
    for n = 1, VB.GEMS do
        local b = MakeGem(pal, 44)
        b:SetGem(n)
        b:SetScript("OnClick", function() VV.PickGem(n) end)
        W.Tooltip(b, function(_, tip)
            tip:SetText(A.GEMS[n].name, 1, 0.82, 0)
            tip:AddLine("Click to put it in the next empty slot.", 1, 1, 1, true)
        end)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture(W.TEX .. "burst")
        hl:SetBlendMode("ADD")
        hl:SetAllPoints()
        hl:SetVertexColor(1, 0.9, 0.5, 0.4)
        view.gemButtons[n] = b
    end
    view.clear = W.Button(pal, "Clear", 64, 24, function() VV.ClearDraft() end)
    view.random = W.Button(pal, "Random", 74, 24, function()
        local code = VB.RandomCode()
        VB.SetCode(code)
        VV.LoadDraft(code)
        A.Play("vbClick")
        VV.Refresh()
    end)
    view.lockIn = W.Button(pal, "Lock In", 104, 30, function() VV.LockIn() end)

    view.banner = BuildBanner(page)

    local h = CreateFrame("Frame", nil, page)
    h:SetWidth(VV.HANDLE)
    view.handle = h
    view.toggle = W.IconButton(h, VV.HANDLE - 2, nil, ">", function()
        return ns.UI.IsCollapsed() and "Show the side panel" or "Hide the side panel"
    end, function() ns.UI.SetCollapsed(not ns.UI.IsCollapsed()) end)
    view.toggle:SetPoint("TOP")

    local side = CreateFrame("Frame", nil, page)
    side:SetWidth(VV.SIDE)
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

function VV.SizeFor(cellPx, showSide)
    local scale = cellPx / VV.CELL
    local w = VV.PANEL_W * scale * 2 + VV.GAP * 2 + VV.HANDLE + (showSide and (VV.GAP + VV.SIDE) or 0)
    local h = VV.STRIP + VV.GAP + VV.TURN + VV.TITLE + VV.PANEL_H * scale + VV.GAP + VV.PALETTE
    if showSide then h = max(h, VV.SETUP_H) end
    return w, h
end

function VV.CellFor(w, h, showSide)
    local availW = (w - VV.GAP * 2 - VV.HANDLE - (showSide and (VV.GAP + VV.SIDE) or 0)) / 2
    local availH = h - VV.STRIP - VV.GAP - VV.TURN - VV.TITLE - VV.GAP - VV.PALETTE
    local scale = min(availW / VV.PANEL_W, availH / VV.PANEL_H)
    return max(24, min(64, floor(scale * VV.CELL)))
end

function VV.Layout(cellPx, showSide)
    local scale = cellPx / VV.CELL
    local pw, ph = VV.PANEL_W * scale, VV.PANEL_H * scale
    local S, GAP = VV.STRIP, VV.GAP
    local page = view.page
    local top = S + GAP + VV.TURN + VV.TITLE
    for k, holder in ipairs({ view.leftHolder, view.rightHolder }) do
        local x = (k - 1) * (pw + GAP)
        view.strips[k]:ClearAllPoints()
        view.strips[k]:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
        view.strips[k]:SetStripWidth(pw)
        local title = k == 1 and view.leftTitle or view.rightTitle
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, -(S + GAP + VV.TURN + 2))
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", page, "TOPLEFT", x, -top)
        holder:SetSize(pw, ph)
        local panel = k == 1 and view.left or view.right
        panel:SetScale(scale)
    end
    local both = pw * 2 + GAP
    view.turn:ClearAllPoints()
    view.turn:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(S + GAP))
    view.turn:SetSize(both, VV.TURN - 6)
    view.palette:ClearAllPoints()
    view.palette:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(top + ph + GAP))
    view.palette:SetWidth(both)
    -- gems on the left, buttons on the right
    local gemStep = min(50, max(30, (both - 260) / VB.GEMS))
    for n, b in ipairs(view.gemButtons) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", view.palette, "LEFT", 8 + (n - 1) * gemStep, 0)
        b:SetScale(min(1, gemStep / 48))
    end
    view.lockIn:ClearAllPoints()
    view.lockIn:SetPoint("RIGHT", view.palette, "RIGHT", -8, 0)
    view.clear:ClearAllPoints()
    view.clear:SetPoint("RIGHT", view.lockIn, "LEFT", -6, 0)
    view.random:ClearAllPoints()
    view.random:SetPoint("RIGHT", view.clear, "LEFT", -6, 0)
    local total = top + ph + GAP + VV.PALETTE
    view.handle:ClearAllPoints()
    view.handle:SetPoint("TOPLEFT", page, "TOPLEFT", both + GAP, -(S + GAP))
    view.handle:SetHeight(ph)
    view.side:ClearAllPoints()
    view.side:SetPoint("TOPLEFT", page, "TOPLEFT", both + GAP * 2 + VV.HANDLE, 0)
    view.side:SetHeight(max(total, VV.SETUP_H))
    if showSide then view.side:Show() else view.side:Hide() end
    view.toggle:SetIcon(nil, showSide and ">" or "<")
    view.banner:ClearAllPoints()
    view.banner:SetPoint("CENTER", page, "TOPLEFT", both / 2, -(top + ph / 2))
    local logH = max(60, max(total, VV.SETUP_H) - 110 - 40)
    view.logBox:SetHeight(logH)
    view.log:Resize(VV.SIDE - 8, logH - 26)
end

------------------------------------------------------------------------
-- Interaction: the draft is the code (while setting) or the guess being built
------------------------------------------------------------------------
function VV.Visible()
    return ns.UI.IsVisibleTab and ns.UI.IsVisibleTab("vbplay")
end

local function Setting(s)
    return s and s.phase == "set" and not s.ready and s.mode ~= "spectate"
end

function VV.LoadDraft(code)
    view.draft = {}
    if code then
        for k = 1, VB.PEGS do view.draft[k] = tonumber(string.sub(code, k, k)) end
    end
end

local function DraftCode()
    for k = 1, VB.PEGS do if not view.draft[k] then return nil end end
    return table.concat(view.draft)
end

function VV.PickGem(n)
    local s = VB.current
    if not (Setting(s) or VB.CanGuess()) then return end
    for k = 1, VB.PEGS do
        if not view.draft[k] then
            view.draft[k] = n
            A.Play("vbGem")
            if Setting(s) and DraftCode() then VB.SetCode(DraftCode()) end
            VV.Refresh()
            return
        end
    end
end

function VV.ClearDraft()
    view.draft = {}
    VV.Refresh()
end

-- Clicking a slot of the code (while setting) or of the current guess row empties it.
function VV.OnSlotClick(kind, k, r)
    local s = VB.current
    if kind == "code" then
        if Setting(s) then
            view.draft[k] = nil
            VV.Refresh()
        end
    elseif kind == "theirs" and VB.CanGuess() and r == s.round then
        view.draft[k] = nil
        VV.Refresh()
    end
end

function VV.LockIn()
    local s = VB.current
    local code = DraftCode()
    if Setting(s) then
        if not code then
            ns.Print("put four gems in your vault first (or press Random).")
            return
        end
        VB.SetCode(code)
        A.Play("vbLock")
        VB.Ready()
        view.draft = {}
    elseif VB.CanGuess() then
        if not code then
            ns.Print("choose four gems for your guess first.")
            return
        end
        A.Play("vbLock")
        VB.Guess(code)
        view.draft = {}
    end
    VV.Refresh()
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function Digits(code)
    local t = {}
    for k = 1, VB.PEGS do t[k] = code and tonumber(string.sub(code, k, k)) or nil end
    return t
end

local function Resolved(s, r)
    return r < s.round or s.phase == "over"
end

local function PaintRows(panel, entries, s, isMineSide)
    for r = 1, VB.ROUNDS do
        local row = panel.rows[r]
        local e = entries[r]
        local resolved = Resolved(s, r)
        -- our own locked-in guess shows at once; theirs only when the round is over
        local showGuess = e and (resolved or (not isMineSide and s.mode ~= "spectate"))
        local d = showGuess and Digits(e.guess) or {}
        local draftRow = (not isMineSide) and VB.CanGuess() and r == s.round
        for k = 1, VB.PEGS do
            row.gems[k]:SetGem(draftRow and view.draft[k] or d[k])
        end
        if resolved and e and e.gold then row.pins:SetPins(e.gold, e.silver) else row.pins:SetPins(nil) end
        if draftRow then row.hl:Show() else row.hl:Hide() end
        local current = s.phase == "play" and r == s.round
        row.num:SetTextColor(current and 1 or 0.8, current and 0.82 or 0.65, current and 0 or 0.3)
    end
end

local function LogLines(s)
    local lines = {}
    local spect = s.mode == "spectate"
    local me = spect and ns.ShortName(s.host) or "You"
    local them = spect and ns.ShortName(s.guest) or (s.mode == "ai" and "Computer" or ns.ShortName(s.opp))
    for r = 1, VB.ROUNDS do
        local m, t = s.mine[r], s.theirs[r]
        if Resolved(s, r) and m and t and m.gold and t.gold then
            lines[#lines + 1] = string.format("|cffaaaaaa%d.|r %s |cffffcc33%d|r|cffd8e0f0+%d|r   %s |cffffcc33%d|r|cffd8e0f0+%d|r",
                r, me, m.gold, m.silver, them, t.gold, t.silver)
        end
    end
    return lines
end

local GREEN, RED, GOLDC, GREY = { 0.1, 0.45, 0.12 }, { 0.5, 0.08, 0.06 }, { 0.5, 0.36, 0.05 }, { 0.2, 0.2, 0.22 }

function VV.RefreshTurn(s)
    local turn = view.turn
    if not s or s.phase == "over" then
        turn:Hide()
        return
    end
    local left = VB.TimeLeft()
    local secs = string.format("%d", math.ceil(left))
    local who = s.mode == "ai" and "the computer" or ns.ShortName((s.mode == "spectate" and s.guest) or s.opp or "?")
    local bg, text, hint, urgent = GREY, "", "", false
    if s.mode == "spectate" then
        text = s.phase == "set" and "THE VAULTS ARE BEING LOCKED..." or string.format("ROUND %d OF %d", s.round, VB.ROUNDS)
        secs = ""
    elseif s.phase == "set" and not s.ready then
        bg, text, urgent = GOLDC, "LOCK YOUR VAULT", true
        hint = "Pick four gems (or Random), then Seal Vault"
    elseif s.phase == "set" then
        text = "VAULT SEALED - WAITING FOR " .. string.upper(who)
        secs = ""
    elseif VB.CanGuess() then
        bg, text, urgent = GREEN, string.format("ROUND %d OF %d - MAKE YOUR GUESS!", s.round, VB.ROUNDS), true
        hint = "Pick four gems, then Lock In"
        if s.missed > 0 then hint = hint .. string.format("   |cffff8040missed %d/%d|r", s.missed, VB.MAX_MISSED) end
    else
        bg, text = RED, "GUESS LOCKED - " .. string.upper(who) .. " IS THINKING..."
        hint = string.format("Round %d of %d", s.round, VB.ROUNDS)
    end
    turn.bg:SetColorTexture(bg[1], bg[2], bg[3], 0.92)
    turn.shine:SetVertexColor(bg[1] * 2, bg[2] * 2, bg[3] * 2)
    turn.text:SetText(text)
    turn.hint:SetText(hint)
    turn.sub:SetText(secs ~= "" and (secs .. "s") or "")
    if urgent and left < 10 then turn.sub:SetTextColor(1, 0.3, 0.2) else turn.sub:SetTextColor(1, 1, 1) end
    turn.urgent = urgent
    turn:Show()
end

function VV.ResultText(s)
    if s.mode == "spectate" then
        if s.winner then return ns.ShortName(s.winner) .. " cracked the vault first." end
        return "Neither vault was cracked first - a draw."
    end
    local text
    if s.outcome == "win" then
        text = "|cff40ff40Victory!|r " .. ((s.reason == "cracked" and string.format("You cracked their vault in %d guesses.", s.crackRound or s.round)) or
            (s.reason == "resign" and "They gave up.") or (s.reason == "time" and "They ran out of time.") or "They left the game.")
    elseif s.outcome == "loss" then
        text = "|cffff5040Defeat.|r " .. ((s.reason == "cracked" and "They cracked your vault first.") or
            (s.reason == "resign" and "You gave up.") or (s.reason == "time" and "You missed too many turns.") or "")
    elseif s.outcome == "draw" then
        text = "|cffd0d0d0Draw.|r " .. (s.reason == "both" and "You both cracked it in the same round." or "Neither vault was cracked in ten rounds.")
    elseif s.outcome == "disputed" then
        text = "|cffff8040Disputed.|r This game does not count."
    else
        text = "Game called off."
    end
    if s.mode == "online" and s.outcome ~= "abort" then
        if s.verified == true then
            text = text .. "\n|cff40ff40Fair-play check passed:|r their code matched every pin."
        elseif s.verified == false then
            text = text .. "\n|cffff4030Fair-play check failed:|r " .. (s.cheat or "") .. "."
        elseif s.cheat then
            text = text .. "\n|cffff4030" .. s.cheat .. ".|r"
        else
            text = text .. "\n|cffaaaaaaChecking their vault code...|r"
        end
    end
    return text
end

function VV.RefreshSetup()
    if VB.current and VB.current.phase ~= "over" then view.backButton:Show() else view.backButton:Hide() end
    local seek = G.seek
    if seek and seek.game == "vb" then
        local secs = floor(ns.Now() - (seek.since or ns.Now()))
        view.findButton:SetText(string.format("Searching... %d:%02d  (cancel)", floor(secs / 60), secs % 60))
    else
        view.findButton:SetText("Find Random Opponent")
    end
    if not C.Joined() and #C.GroupDists() == 0 then
        view.queueNote:SetText("|cffaaaaaaConnecting to the network...|r")
    else
        local n = 0
        for _, o in pairs(P.online) do if o.status == "v" then n = n + 1 end end
        view.queueNote:SetText(string.format("|cffaaaaaa%d looking for a game of Vault Breaker|r", n))
    end
    view.aiButton:SetText(VB.LEVELS[ns.db.settings.vbLevel or 2])
    if G.outgoing and not G.outgoing.q and G.outgoing.game == "vb" then
        view.challengeButton:SetText("Cancel")
        view.setupNote:SetText("|cffffd100Waiting for " .. ns.ShortName(G.outgoing.to) .. " to answer...|r")
    else
        view.challengeButton:SetText("Challenge")
        view.setupNote:SetText("Type a name, or leave it empty to challenge your target.")
    end
end

function VV.Refresh()
    if not view.page then return end
    local s = VB.current
    local spect = s and s.mode == "spectate"

    -- Left vault: our code and their guesses (for spectators: the host's)
    local left, right = view.left, view.right
    if s then
        local setting = Setting(s)
        local myCode = Digits(s.myCode)
        for k = 1, VB.PEGS do
            if setting then left.code[k]:SetGem(view.draft[k])
            elseif spect and not s.myCode then left.code[k]:SetGem(nil, true)
            else left.code[k]:SetGem(myCode[k]) end
        end
        local theirCode = Digits(s.theirCode)
        for k = 1, VB.PEGS do
            if s.theirCode then right.code[k]:SetGem(theirCode[k]) else right.code[k]:SetGem(nil, true) end
        end
        PaintRows(left, s.theirs, s, true)
        PaintRows(right, s.mine, s, false)
    else
        for k = 1, VB.PEGS do left.code[k]:SetGem(nil); right.code[k]:SetGem(nil, true) end
        for r = 1, VB.ROUNDS do
            for k = 1, VB.PEGS do left.rows[r].gems[k]:SetGem(nil); right.rows[r].gems[k]:SetGem(nil) end
            left.rows[r].pins:SetPins(nil); right.rows[r].pins:SetPins(nil)
            left.rows[r].hl:Hide(); right.rows[r].hl:Hide()
        end
    end
    VV.RefreshTurn(s)

    -- Titles and strips
    if spect then
        view.leftTitle:SetText(ns.ShortName(s.host) .. "'s Vault")
        view.rightTitle:SetText(ns.ShortName(s.guest) .. "'s Vault")
    else
        view.leftTitle:SetText("Your Vault")
        view.rightTitle:SetText("Their Vault")
    end
    local timeLeft = s and VB.TimeLeft() or nil
    if s then
        local leftName = spect and s.host or ns.me
        local rightName = spect and s.guest or (s.mode == "ai" and s.oppName or s.opp)
        local mineLocked = s.mine[s.round] ~= nil
        local myState, theirState = "", ""
        if s.phase == "set" then
            myState = s.ready and "|cff40ff40Vault sealed|r" or "|cffffd100Choosing a code...|r"
            theirState = s.theirSeal and "|cff40ff40Vault sealed|r" or (s.mode == "ai" and "|cff40ff40Vault sealed|r" or "|cffffd100Choosing a code...|r")
        elseif s.phase == "play" and not spect then
            myState = mineLocked and "|cff40ff40Guess locked in|r" or "|cffffd100Guessing...|r"
            theirState = (s.theirs[s.round] and "|cff40ff40Guess locked in|r") or "|cffffd100Guessing...|r"
        end
        local myTurn = (Setting(s) or VB.CanGuess())
        UpdateStrip(view.strips[1], leftName, false, myTurn, myState, myTurn and timeLeft or nil)
        UpdateStrip(view.strips[2], rightName, s.mode == "ai", false, theirState, nil)
    else
        UpdateStrip(view.strips[1], ns.me, false, false, "", nil)
        UpdateStrip(view.strips[2], "Opponent", true, false, "", nil)
    end

    -- Palette
    local canEdit = s and (Setting(s) or VB.CanGuess())
    for _, b in ipairs(view.gemButtons) do b:SetAlpha(canEdit and 1 or 0.35) end
    if canEdit then
        view.lockIn:Enable(); view.clear:Enable()
        view.lockIn:SetText(Setting(s) and "Seal Vault" or "Lock In")
    else
        view.lockIn:Disable(); view.clear:Disable()
        view.lockIn:SetText((s and s.phase == "set") and "Seal Vault" or "Lock In")
    end
    if s and Setting(s) then view.random:Show() else view.random:Hide() end

    -- Side panel
    if (not s) or view.showSetup then
        view.setup:Show()
        view.gamePanel:Hide()
        VV.RefreshSetup()
        return
    end
    view.setup:Hide()
    view.gamePanel:Show()
    view.header:SetText(spect and "Watching a game" or (s.mode == "ai" and ("Practice vs " .. s.oppName) or ("Game vs " .. ns.ShortName(s.opp))))
    local status
    local who = s.mode == "ai" and "The computer" or ns.ShortName((spect and s.guest) or s.opp or "?")
    if s.phase == "set" then
        if spect then status = "The vaults are being locked."
        elseif s.ready then status = "|cff40ff40Vault sealed.|r\nWaiting for " .. who .. " to lock theirs..."
        else status = "|cffffd100Lock your vault.|r\nPick four gems from the palette (or Random), then press Seal Vault." end
    elseif s.phase == "play" then
        if spect then status = "Watching " .. ns.ShortName(s.host) .. " vs " .. ns.ShortName(s.guest) .. "."
        elseif VB.CanGuess() then
            status = string.format("|cff40ff40Round %d of %d: make your guess.|r\nPick four gems, then Lock In.", s.round, VB.ROUNDS) ..
                (s.missed > 0 and ("\n|cffff8040Missed turns: " .. s.missed .. "/" .. VB.MAX_MISSED .. "|r") or "")
        else
            status = "|cffffd100Guess locked in.|r\n" .. who .. " is still guessing..."
        end
    else
        status = VV.ResultText(s)
    end
    view.status:SetText(status)
    view.log:SetData(LogLines(s))
    view.log.offset = max(0, #view.log.data - (view.log.visible or 1))
    view.log:Update()
    if s.phase ~= "over" then
        view.newButton:Hide()
        view.resign:Show()
        if not view.resignArmed then
            view.resign:SetText(spect and "Stop Watching" or (s.phase == "set" and s.mode == "online") and "Abort" or "Resign")
        end
    else
        view.resign:Hide()
        view.newButton:Show()
    end
end

------------------------------------------------------------------------
-- Effects and sounds
------------------------------------------------------------------------
local function PopRow(panel, r)
    local row = panel.rows[r]
    A.Tween(0.35, function(p)
        local sc = 1 + 0.5 * math.sin(p * math.pi)
        row.pins:SetScale(sc)
    end, function() row.pins:SetScale(1) end)
end

local function Burst(panel, x, y, size, r, g, b)
    local t = panel.fx:CreateTexture(nil, "OVERLAY")
    t:SetTexture(W.TEX .. "burst")
    t:SetBlendMode("ADD")
    t:SetVertexColor(r, g, b)
    t:SetPoint("CENTER", panel.fx, "TOPLEFT", x, y)
    A.Tween(0.7, function(p)
        local sz = size * (0.4 + 1.4 * p)
        t:SetSize(sz, sz)
        t:SetAlpha(1 - p)
    end, function() t:Hide() end, A.Ease.outCubic)
end

ns.On("VB_STARTED", function(s)
    view.showSetup = false
    view.wasMyTurn = nil
    if view.banner then view.banner:Hide() end
    VV.LoadDraft(s.mode ~= "spectate" and s.myCode or nil)
    if s.mode ~= "spectate" then
        A.Play("vbClick")
        ns.After(0.5, function() A.Play("vbGears") end)
    end
end)

ns.On("VB_PLAY", function(s)
    view.draft = {}
    A.Play("vbLock")
    ns.After(0.6, function() A.Play("vbTurn") end)
end)

ns.On("VB_ROUND", function(s, r)
    A.Play("vbGears")
    if VV.Visible() and view.left then
        PopRow(view.left, r)
        PopRow(view.right, r)
    end
end)

function VV.ShowBanner(s)
    local banner = view.banner
    local title, color, icon
    if s.mode == "spectate" then
        title, color = s.winner and (ns.ShortName(s.winner) .. " wins!") or "Draw", { 1, 0.82, 0 }
        icon = "Interface\\Icons\\inv_misc_lockbox_1"
    elseif s.outcome == "win" then
        title, color, icon = "Vault Cracked!", { 1, 0.82, 0 }, "Interface\\Icons\\inv_box_04"
    elseif s.outcome == "loss" then
        title, color, icon = "Defeat", { 0.9, 0.2, 0.15 }, "Interface\\Icons\\inv_misc_key_03"
    elseif s.outcome == "draw" then
        title, color, icon = "Draw", { 0.85, 0.85, 0.9 }, "Interface\\Icons\\inv_misc_gem_pearl_05"
    elseif s.outcome == "disputed" then
        title, color, icon = "Disputed", { 1, 0.5, 0.2 }, "Interface\\Icons\\inv_misc_lockbox_1"
    else
        return
    end
    banner.title:SetText(title)
    banner.title:SetTextColor(color[1], color[2], color[3])
    banner.sub:SetText(VV.ResultText(s))
    W.SetIcon(banner.icon, icon)
    banner:Show()
    banner:SetAlpha(0)
    A.Tween(0.45, function(p)
        banner:SetAlpha(min(1, p * 1.5))
        banner:SetScale(0.7 + 0.3 * p)
    end, nil, A.Ease.outBack)
end

ns.On("VB_OVER", function(s)
    if s.outcome == "win" then
        A.Play("vbOpen")
        ns.After(0.7, function() A.Play("vbChest") end)
        ns.After(1.4, function() ns.Sound("win" .. A.MyFaction()) end)
        if VV.Visible() and view.right then
            Burst(view.right, VV.PANEL_W / 2, -VV.CODE / 2, 160, 1, 0.8, 0.3)
        end
    elseif s.outcome == "loss" then
        A.Play("vbShut")
        ns.After(0.9, function() ns.Sound("lose") end)
    elseif s.outcome == "draw" then
        A.Play("vbOpen")
        ns.After(0.6, function() A.Play("c4Applause") end)
    end
    ns.After(1.0, function()
        if VB.current == s and VV.Visible() then
            VV.Refresh()
            VV.ShowBanner(s)
        end
    end)
end)

-- A chime when a new round starts for us (and a taskbar flash when the window is closed).
ns.On("VB_CHANGED", function(s)
    local mine = VB.CanGuess()
    if mine and not view.wasMyTurn and s.round > 1 then
        A.Play("vbTurn")
        if not VV.Visible() and FlashClientIcon then pcall(FlashClientIcon) end
    end
    view.wasMyTurn = mine
    if view.banner and view.banner:IsShown() and s.phase == "over" then
        view.banner.sub:SetText(VV.ResultText(s))
    end
end)
