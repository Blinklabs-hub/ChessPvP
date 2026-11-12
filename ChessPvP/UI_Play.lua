-- ChessPvP: the Play tab - board with player strips, a slim action column, and a side
-- panel (game setup or move list) that folds away during games.
local _, ns = ...

local PV = {}
ns.PlayView = PV

local E, G, P, C, D, AI, A, W, Board = ns.Engine, ns.Game, ns.Profile, ns.Comm, ns.Data, ns.AI, ns.Assets, ns.W, ns.Board
local floor, max, min = math.floor, math.max, math.min

PV.BASE = 56 * 8 -- the board is built at 448px and scaled to fit
PV.STRIP = 46
PV.GAP = 6
PV.HANDLE = 30
PV.SIDE = 300
PV.SETUP_H = 420 -- height the setup panel needs

local play = {}
PV.play = play
local PIECE_VALUE = { 1, 3, 3, 5, 9, 0 }

local function TimeControlName(base, inc)
    if base == 0 then return "No clock" end
    return string.format("%d+%d", floor(base / 60), inc)
end
PV.TimeControlName = TimeControlName

------------------------------------------------------------------------
-- Player strips
------------------------------------------------------------------------
local function KnownGames(name)
    if ns.SameName(name, ns.me) then return P.RatedGames() end
    local v = ns.Ledger.Get(name)
    return v and v.games or 0
end

local function BuildStrip(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(PV.STRIP)
    s.bg = W.Background(s, 0.1, 0.08, 0.06, 0.92, { 0.55, 0.45, 0.2, 0.9 })
    s.glow = s:CreateTexture(nil, "BORDER")
    s.glow:SetAllPoints()
    s.glow:SetTexture(W.TEX .. "burst")
    s.glow:SetBlendMode("ADD")
    s.glow:SetVertexColor(1, 0.8, 0.3, 0.22)
    s.glow:Hide()
    s.crest = s:CreateTexture(nil, "ARTWORK")
    s.crest:SetSize(38, 38)
    s.crest:SetPoint("LEFT", 2, 1)
    s.name = W.Title(s, 15)
    s.name:SetPoint("TOPLEFT", 42, -5)
    s.name:SetWordWrap(false)
    s.sub = W.Label(s, "GameFontHighlightSmall")
    s.sub:SetPoint("LEFT", s.name, "RIGHT", 8, -1)
    s.sub:SetWordWrap(false)
    s.clock = W.Title(s, 22)
    s.clock:SetPoint("RIGHT", -8, 0)
    s.clock:SetJustifyH("RIGHT")
    s.tray = {}
    for k = 1, 15 do
        local v = Board.CreatePieceView(s, 17)
        v:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 42 + (k - 1) * 12, 3)
        v:SetFrameLevel(s:GetFrameLevel() + 2 + k)
        s.tray[k] = v
    end
    s.lead = W.Label(s, "GameFontNormalSmall")
    s.lead:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 42, 6)
    function s:SetStripWidth(w)
        self:SetWidth(w)
        local nameW = max(60, min(w * 0.45, w - 160))
        self.name:SetWidth(nameW)
        self.sub:SetWidth(max(40, w - 42 - nameW - 90))
    end
    return s
end

local function UpdateStrip(s, g, color)
    s.color = color
    local army = A.ArmyFor(color, g)
    local info = A.ARMIES[army]
    local name, rating, title
    if g then
        name = (color == 1) and g.white or g.black
        rating = (color == 1) and g.wr or g.br
        title = (color == 1) and g.wt or g.bt
        local v = ns.Ledger.Get(name)
        if v then rating = v.r end -- witnessed rating beats whatever was sent
    elseif color == 1 then
        name, rating, title = ns.me, P.me.rating, P.MyTitleId()
    else
        name = "Opponent"
    end
    s.name:SetText("|c" .. W.Hex(info.color) .. ns.ShortName(name) .. "|r")
    if rating and rating > 0 then
        s.sub:SetText(P.TitleText(title, rating, KnownGames(name)) .. " |cffaaaaaa" .. rating .. "|r")
    else
        s.sub:SetText("|cff888888" .. army .. "|r")
    end
    W.SetCrest(s.crest, army)
    local toMove = g and g.state == "active" and g.pos.turn == color
    local c, k = info.color, toMove and 0.30 or 0.12
    s.bg:SetColorTexture(c[1] * k + 0.04, c[2] * k + 0.03, c[3] * k + 0.02, 0.94)
    if toMove then s.glow:Show() else s.glow:Hide() end
    if g and g.timed then s.clock:Show() else s.clock:Hide() end

    local caps = g and g.captures and g.captures[color] or {}
    local sorted = {}
    for i = 1, #caps do sorted[i] = caps[i] end
    table.sort(sorted, function(a, b) return a > b end)
    local mine, theirs = 0, 0
    for i = 1, #caps do mine = mine + PIECE_VALUE[caps[i]] end
    local other = g and g.captures and g.captures[-color] or {}
    for i = 1, #other do theirs = theirs + PIECE_VALUE[other[i]] end
    for i = 1, #s.tray do
        if sorted[i] then s.tray[i]:SetPiece(sorted[i] * -color, g) else s.tray[i]:Hide() end
    end
    local lead = mine - theirs
    s.lead:ClearAllPoints()
    s.lead:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 42 + #sorted * 12 + 10, 6)
    s.lead:SetText(lead > 0 and ("|cff40ff40+" .. lead .. "|r") or "")
end

function PV.UpdateClocks()
    local g = G.current
    if not g or not g.timed or not play.strips then return end
    for i = 1, 2 do
        local s = play.strips[i]
        if s.color then
            local left = G.Remaining(g, s.color)
            s.clock:SetText(ns.FormatClock(left))
            if left < 20 and g.state == "active" and g.pos.turn == s.color then
                s.clock:SetTextColor(1, 0.25, 0.2)
            else
                s.clock:SetTextColor(1, 0.82, 0)
            end
        end
    end
end

------------------------------------------------------------------------
-- Side panel text
------------------------------------------------------------------------
local function MoveListText(g, maxLines)
    local lines = {}
    local n = #g.san
    local pairsTotal = floor((n + 1) / 2)
    local first = max(1, pairsTotal - (maxLines or 12) + 1)
    for i = first, pairsTotal do
        local w = g.san[i * 2 - 1] or ""
        local b = g.san[i * 2] or ""
        lines[#lines + 1] = string.format("|cff888888%3d.|r  %-8s  %s", i, w, b)
    end
    if #lines == 0 then return "|cff888888No moves yet.|r" end
    return table.concat(lines, "\n")
end

local function StatusText(g)
    if g.state == "over" then
        local r = g.result
        local reason = D.REASON_TEXT[g.reason] or g.reason or ""
        local text
        if r == "1-0" or r == "0-1" then
            text = A.ArmyFor(r == "1-0" and 1 or -1, g) .. " wins by " .. reason
        elseif r == "1/2" then
            text = "Draw by " .. reason
        else
            text = "No result: " .. (D.REASON_TEXT[g.reason] or "game ended")
        end
        if g.outcome == "win" then
            text = "|cff40ff40Victory!|r " .. text
        elseif g.outcome == "loss" then
            text = "|cffff5040Defeat.|r " .. text
        end
        if g.rated and g.outcome then
            if g.delta then
                text = text .. string.format("\nRating %s%d|r  (now %d)", g.delta >= 0 and "|cff40ff40+" or "|cffff5040", g.delta, P.me.rating)
            else
                text = text .. "\n|cffaaaaaaRating: waiting for your opponent to confirm the result...|r"
            end
        end
        return text
    end
    local side = A.ArmyFor(g.pos.turn, g)
    local check = E.InCheck(g.pos) and "  |cffff4030Check!|r" or ""
    if g.mode == "spectate" then
        return "Watching. The " .. side .. " to move." .. check
    elseif g.mode == "local" then
        return "The " .. side .. " to move." .. check
    elseif g.pos.turn == g.myColor then
        local t = "|cffffd100Your move.|r" .. check
        if g.drawOffer == g.myColor then t = t .. "\nDraw offered." end
        return t
    else
        local who = (g.mode == "ai") and "the computer" or ns.ShortName(g.opp)
        local t = "Waiting for " .. who .. "." .. check
        if g.awaitSync then t = t .. "\n|cffaaaaaaReconnecting...|r" end
        if g.drawOffer == g.myColor then t = t .. "\nDraw offered." end
        return t
    end
end

local function GameHeader(g)
    local kind
    if g.mode == "online" then
        kind = (g.rated and "Rated" or "Casual") .. " battle"
    elseif g.mode == "ai" then
        kind = "Practice battle"
    elseif g.mode == "local" then
        kind = "Pass & Play"
    else
        kind = "Spectating"
    end
    return kind .. "  |cffaaaaaa" .. TimeControlName(g.base, g.inc) .. "|r"
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
local function ArmedResign(button, setText)
    -- A second click within 3 seconds confirms, so a slip of the mouse does not end the game.
    local g = G.current
    if not g or g.state ~= "active" then return end
    if g.mode == "spectate" or play.resignArmed then
        play.resignArmed = false
        G.Resign()
        return
    end
    play.resignArmed = true
    setText("Sure?")
    ns.After(3, function()
        if play.resignArmed then
            play.resignArmed = false
            ns.UI.Refresh()
        end
    end)
end

local function BuildSetup(sp)
    local s = ns.db.settings
    local h1 = W.Title(sp, 18, "Seek a Battle")
    h1:SetPoint("TOPLEFT", 4, -2)

    local tcLabel = W.Label(sp, "GameFontHighlightSmall", "Time control")
    tcLabel:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -14)
    play.tcButton = W.Button(sp, "", 150, 22, function()
        s.tc = (s.tc % #D.TIME_CONTROLS) + 1
        if G.seek then G.StopSeek() end
        ns.UI.Refresh()
    end)
    play.tcButton:SetPoint("TOPRIGHT", sp, "TOPRIGHT", -4, -30)

    local colLabel = W.Label(sp, "GameFontHighlightSmall", "Your colour (challenges)")
    colLabel:SetPoint("TOPLEFT", tcLabel, "BOTTOMLEFT", 0, -16)
    play.colorButton = W.Button(sp, "", 150, 22, function()
        s.color = (s.color == "r" and "w") or (s.color == "w" and "b") or "r"
        ns.UI.Refresh()
    end)
    play.colorButton:SetPoint("TOPRIGHT", play.tcButton, "BOTTOMRIGHT", 0, -6)

    play.ratedCheck = W.Check(sp, "Rated", function() return s.rated end, function(v)
        s.rated = v
        if G.seek then G.StopSeek() end
        ns.UI.Refresh()
    end)
    play.ratedCheck:SetPoint("TOPLEFT", colLabel, "BOTTOMLEFT", -4, -12)

    play.seekButton = W.Button(sp, "Find Match", PV.SIDE - 8, 30, function()
        if G.seek then
            G.StopSeek()
        else
            local tc = D.TIME_CONTROLS[s.tc]
            G.StartSeek(tc.base, tc.inc, s.rated)
        end
        ns.UI.Refresh()
    end)
    play.seekButton:SetPoint("TOPLEFT", play.ratedCheck, "BOTTOMLEFT", 4, -8)

    local nameBox = CreateFrame("EditBox", nil, sp, "InputBoxTemplate")
    nameBox:SetSize(PV.SIDE - 118, 22)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetPoint("TOPLEFT", play.seekButton, "BOTTOMLEFT", 6, -14)
    play.nameBox = nameBox
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
        G.Invite(name)
        ns.UI.Refresh()
    end
    nameBox:SetScript("OnEnterPressed", SendChallenge)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    play.challengeButton = W.Button(sp, "Challenge", 96, 22, SendChallenge)
    play.challengeButton:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    local hint = W.Label(sp, "GameFontDisableSmall", "Name of a player, or leave empty to challenge your target.")
    hint:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -4)
    hint:SetWidth(PV.SIDE - 8)

    play.setupNote = W.Label(sp, "GameFontHighlightSmall", "")
    play.setupNote:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    play.setupNote:SetWidth(PV.SIDE - 8)
    play.setupNote:SetTextColor(1, 0.82, 0)

    local h2 = W.Title(sp, 18, "Practice")
    h2:SetPoint("TOPLEFT", play.setupNote, "BOTTOMLEFT", 0, -20)
    play.aiButton = W.Button(sp, "", 170, 24, function()
        s.aiLevel = (s.aiLevel % #AI.LEVELS) + 1
        ns.UI.Refresh()
    end)
    play.aiButton:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -10)
    local aiStart = W.Button(sp, "Play", PV.SIDE - 184, 24, function()
        local color = (s.color == "w" and 1) or (s.color == "b" and -1) or nil
        G.StartAI(s.aiLevel, color)
    end)
    aiStart:SetPoint("LEFT", play.aiButton, "RIGHT", 6, 0)
    local localButton = W.Button(sp, "Pass & Play (two players, one screen)", PV.SIDE - 8, 24, function() G.StartLocal() end)
    localButton:SetPoint("TOPLEFT", play.aiButton, "BOTTOMLEFT", 0, -8)

    play.backButton = W.Button(sp, "Back to battle", 130, 24, function()
        play.showSetup = false
        ns.UI.Refresh()
    end)
    play.backButton:SetPoint("BOTTOMLEFT", sp, "BOTTOMLEFT", 4, 4)
end

local function BuildGamePanel(gp)
    play.header = W.Title(gp, 16)
    play.header:SetPoint("TOPLEFT", 6, -4)

    local movesBox = W.Card(gp)
    movesBox:SetPoint("TOPLEFT", 0, -26)
    movesBox:SetPoint("TOPRIGHT", 0, -26)
    play.movesBox = movesBox
    local mh = W.Label(movesBox, "GameFontNormalSmall", "Battle log")
    mh:SetPoint("TOPLEFT", 8, -6)
    play.moves = W.Label(movesBox, "GameFontHighlightSmall")
    play.moves:SetPoint("TOPLEFT", 8, -22)
    play.moves:SetPoint("BOTTOMRIGHT", -8, 6)
    play.moves:SetJustifyV("TOP")
    play.moves:SetSpacing(3)
    if STANDARD_TEXT_FONT then play.moves:SetFont(STANDARD_TEXT_FONT, 11, "") end

    play.status = W.Label(gp, "GameFontHighlight")
    play.status:SetPoint("TOPLEFT", movesBox, "BOTTOMLEFT", 4, -8)
    play.status:SetWidth(PV.SIDE - 8)
    play.status:SetJustifyV("TOP")
    play.status:SetSpacing(3)

    local drawBar = W.Card(gp)
    drawBar:SetSize(PV.SIDE, 30)
    drawBar:SetPoint("BOTTOMLEFT", gp, "BOTTOMLEFT", 0, 36)
    local dl = W.Label(drawBar, "GameFontHighlightSmall", "Your opponent offers a draw")
    dl:SetPoint("LEFT", 8, 0)
    local decline = W.Button(drawBar, "No", 40, 20, function() G.DeclineDraw() end)
    decline:SetPoint("RIGHT", -5, 0)
    local accept = W.Button(drawBar, "Accept", 60, 20, function() G.OfferDraw() end)
    accept:SetPoint("RIGHT", decline, "LEFT", -4, 0)
    drawBar:Hide()
    play.drawBar = drawBar

    play.resignButton = W.Button(gp, "Resign", 94, 26, function(self)
        ArmedResign(self, function(t) self:SetText(t) end)
    end)
    play.resignButton:SetPoint("BOTTOMLEFT", gp, "BOTTOMLEFT", 0, 0)
    play.drawButton = W.Button(gp, "Offer Draw", 94, 26, function() G.OfferDraw() end)
    play.drawButton:SetPoint("LEFT", play.resignButton, "RIGHT", 6, 0)
    play.newButton = W.Button(gp, "New Battle", 130, 26, function()
        play.showSetup = true
        ns.UI.SetCollapsed(false)
        ns.UI.Refresh()
    end)
    play.newButton:SetPoint("BOTTOMLEFT", gp, "BOTTOMLEFT", 0, 0)
end

local function BuildHandle(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetWidth(PV.HANDLE)
    play.handle = h
    local size = PV.HANDLE - 2
    play.toggleButton = W.IconButton(h, size, nil, ">", function()
        return ns.UI.IsCollapsed() and "Show the side panel" or "Hide the side panel"
    end, function()
        ns.UI.SetCollapsed(not ns.UI.IsCollapsed())
    end)
    play.toggleButton:SetPoint("TOP", 0, 0)
    play.flipButton = W.IconButton(h, size, "Interface\\Buttons\\UI-RotationRight-Button-Up", "F", "Flip the board", function()
        play.board.flipped = not play.board.flipped
        play.board:ClearSelection()
        ns.UI.Refresh()
    end)
    play.flipButton:SetPoint("TOP", play.toggleButton, "BOTTOM", 0, -6)
    play.drawIcon = W.IconButton(h, size, "Interface\\Icons\\spell_holy_layonhands", "=", "Offer a draw", function()
        G.OfferDraw()
    end)
    play.drawIcon:SetPoint("TOP", play.flipButton, "BOTTOM", 0, -6)
    play.resignIcon = W.IconButton(h, size, "Interface\\Icons\\inv_misc_flag_01", "X", function()
        return play.resignArmed and "Click again to resign" or "Resign (click twice)"
    end, function(self)
        ArmedResign(self, function() end)
        if play.resignArmed then
            self.glyph:SetText("?")
            ns.Print("click the flag again within 3 seconds to resign.")
        end
    end)
    play.resignIcon:SetPoint("TOP", play.drawIcon, "BOTTOM", 0, -6)
end

local function BuildBanner(holder)
    local banner = CreateFrame("Button", nil, holder)
    banner:SetSize(360, 140)
    banner:SetPoint("CENTER")
    banner:SetFrameLevel(holder:GetFrameLevel() + 60)
    W.Background(banner, 0.04, 0.03, 0.02, 0.94)
    W.Tile(banner, "dialogBg", 0.9)
    W.Chrome(banner, "goldBorder", 4, 24)
    banner.crest = banner:CreateTexture(nil, "ARTWORK")
    banner.crest:SetSize(72, 72)
    banner.crest:SetPoint("LEFT", 16, 4)
    banner.title = W.Title(banner, 36)
    banner.title:SetPoint("TOP", 36, -18)
    banner.title:SetJustifyH("CENTER")
    banner.sub = W.Label(banner, "GameFontHighlight")
    banner.sub:SetPoint("TOP", banner.title, "BOTTOM", 0, -8)
    banner.sub:SetJustifyH("CENTER")
    banner.sub:SetWidth(240)
    banner.again = W.Button(banner, "New Battle", 110, 22, function()
        banner:Hide()
        play.showSetup = true
        ns.UI.SetCollapsed(false)
        ns.UI.Refresh()
    end)
    banner.again:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", -4, 10)
    banner.close = W.Button(banner, "Close", 110, 22, function()
        banner:Hide()
        ns.UI.SetCollapsed(false)
    end)
    banner.close:SetPoint("BOTTOMLEFT", banner, "BOTTOM", 4, 10)
    banner:SetScript("OnClick", function(self) self:Hide() end)
    banner:Hide()
    play.banner = banner
end

function PV.Build(page)
    play.page = page
    play.holder = CreateFrame("Frame", nil, page)
    play.board = Board.Create(play.holder, 56)
    play.board:SetPoint("CENTER")
    -- Dark wood surround with a gold edge.
    local surround = play.holder:CreateTexture(nil, "BACKGROUND", nil, -8)
    surround:SetPoint("TOPLEFT", -4, 4)
    surround:SetPoint("BOTTOMRIGHT", 4, -4)
    surround:SetColorTexture(0.16, 0.10, 0.05, 1)
    W.Chrome(play.holder, "goldBorder", 8, 24)
    BuildBanner(play.holder)

    play.strips = { BuildStrip(page), BuildStrip(page) }
    BuildHandle(page)

    local side = CreateFrame("Frame", nil, page)
    side:SetWidth(PV.SIDE)
    play.side = side
    local sp = CreateFrame("Frame", nil, side)
    sp:SetAllPoints()
    play.setup = sp
    BuildSetup(sp)
    local gp = CreateFrame("Frame", nil, side)
    gp:SetAllPoints()
    play.gamePanel = gp
    BuildGamePanel(gp)
end

-- Places everything for a board of boardPx pixels; side panel shown or not.
function PV.Layout(boardPx, showSide)
    local S, GAP = PV.STRIP, PV.GAP
    local total = S * 2 + GAP * 2 + boardPx
    play.strips[1]:ClearAllPoints()
    play.strips[1]:SetPoint("TOPLEFT", play.page, "TOPLEFT", 0, 0)
    play.strips[1]:SetStripWidth(boardPx)
    play.holder:ClearAllPoints()
    play.holder:SetPoint("TOPLEFT", play.page, "TOPLEFT", 0, -(S + GAP))
    play.holder:SetSize(boardPx, boardPx)
    play.board:SetScale(boardPx / PV.BASE)
    play.strips[2]:ClearAllPoints()
    play.strips[2]:SetPoint("TOPLEFT", play.page, "TOPLEFT", 0, -(S + GAP * 2 + boardPx))
    play.strips[2]:SetStripWidth(boardPx)
    play.handle:ClearAllPoints()
    play.handle:SetPoint("TOPLEFT", play.page, "TOPLEFT", boardPx + GAP, -(S + GAP))
    play.handle:SetHeight(boardPx)
    play.side:ClearAllPoints()
    play.side:SetPoint("TOPLEFT", play.page, "TOPLEFT", boardPx + GAP + PV.HANDLE + GAP, 0)
    play.side:SetHeight(total)
    if showSide then play.side:Show() else play.side:Hide() end
    -- The move list takes whatever height is left.
    local movesH = max(80, total - 26 - 110 - 70)
    play.movesBox:SetHeight(movesH)
    play.moveLines = max(4, floor((movesH - 28) / 14))
    play.toggleButton:SetIcon(nil, showSide and ">" or "<")
    return total
end

function PV.Refresh()
    local g = G.current
    local board = play.board
    if g and g ~= play.lastGame then
        play.lastGame = g
        play.showSetup = false
        board.flipped = (g.myColor == -1)
        board:ClearSelection()
    end
    if g and g.state ~= "active" then board:ClearSelection() end
    board:Refresh()

    local topColor = board.flipped and 1 or -1
    UpdateStrip(play.strips[1], g, topColor)
    UpdateStrip(play.strips[2], g, -topColor)
    PV.UpdateClocks()

    local active = g and g.state == "active"
    local canAct = active and g.mode ~= "spectate"
    if canAct then play.resignIcon:Show() else play.resignIcon:Hide() end
    if canAct and g.mode ~= "ai" then play.drawIcon:Show() else play.drawIcon:Hide() end
    if not play.resignArmed then play.resignIcon:SetIcon("Interface\\Icons\\inv_misc_flag_01", "X") end

    if (not g) or play.showSetup then
        play.setup:Show()
        play.gamePanel:Hide()
        PV.RefreshSetup()
        return
    end
    play.setup:Hide()
    play.gamePanel:Show()
    play.header:SetText(GameHeader(g))
    play.moves:SetText(MoveListText(g, play.moveLines))
    play.status:SetText(StatusText(g))
    if active and g.mode == "online" and g.drawOffer == -g.myColor then play.drawBar:Show() else play.drawBar:Hide() end
    if active then
        play.newButton:Hide()
        play.resignButton:Show()
        if g.mode == "spectate" then
            play.resignButton:SetText("Stop Watching")
            play.drawButton:Hide()
        else
            if not play.resignArmed then
                play.resignButton:SetText((g.mode == "online" and #g.moves < 2) and "Abort" or "Resign")
            end
            if g.mode == "ai" then play.drawButton:Hide() else play.drawButton:Show() end
        end
    else
        play.resignButton:Hide()
        play.drawButton:Hide()
        play.newButton:Show()
    end
end

function PV.RefreshSetup()
    local s = ns.db.settings
    if G.current then play.backButton:Show() else play.backButton:Hide() end
    local tc = D.TIME_CONTROLS[s.tc] or D.TIME_CONTROLS[4]
    play.tcButton:SetText(tc.name)
    local ratedPossible = tc.base > 0
    play.ratedCheck:SetChecked(ratedPossible and s.rated)
    if ratedPossible then
        play.ratedCheck:Enable()
        play.ratedCheck.label:SetText("Rated (counts for the ladder)")
    else
        play.ratedCheck:Disable()
        play.ratedCheck.label:SetText("|cff808080Rated games need a clock|r")
    end
    play.colorButton:SetText((s.color == "w" and "Play as White") or (s.color == "b" and "Play as Black") or "Random colour")
    play.aiButton:SetText("Computer: " .. AI.LEVELS[s.aiLevel].name)
    play.seekButton:SetText(G.seek and "Searching... (cancel)" or "Find Match")
    if G.outgoing and not G.outgoing.q then
        play.challengeButton:SetText("Cancel")
        play.setupNote:SetText("Waiting for " .. ns.ShortName(G.outgoing.to) .. " to answer...")
    else
        play.challengeButton:SetText("Challenge")
        if G.seek then
            play.setupNote:SetText("Looking for an opponent who wants the same game.")
        elseif not C.Joined() then
            play.setupNote:SetText("|cffaaaaaaConnecting to the chess network...|r")
        else
            play.setupNote:SetText("")
        end
    end
end

function PV.ShowBanner(g)
    local banner = play.banner
    local reason = D.REASON_TEXT[g.reason] or g.reason or ""
    local title, sub, army
    if g.result == "*" then
        title, sub = "Battle Abandoned", reason
    elseif g.result == "1/2" then
        title, sub = "Stalemate", "Draw by " .. reason
    elseif g.outcome then
        title = g.outcome == "win" and "Victory!" or "Defeat"
        sub = (g.outcome == "win" and "You won by " or "You lost by ") .. reason
    else
        army = A.ArmyFor(g.result == "1-0" and 1 or -1, g)
        title, sub = "The " .. army .. " Triumphs!", "Won by " .. reason
    end
    if not army then
        local winner = (g.result == "1-0" and 1) or (g.result == "0-1" and -1) or (g.myColor or 1)
        army = A.ArmyFor(winner, g)
    end
    if g.rated and g.outcome then
        if g.delta then
            sub = sub .. string.format("\nRating %s%d (now %d)", g.delta >= 0 and "+" or "", g.delta, P.me.rating)
        else
            sub = sub .. "\n|cffaaaaaaRating updates when your opponent confirms|r"
        end
    end
    banner.title:SetText(title)
    if g.outcome == "loss" then banner.title:SetTextColor(0.9, 0.2, 0.15) else banner.title:SetTextColor(1, 0.82, 0) end
    banner.sub:SetText(sub)
    W.SetCrest(banner.crest, army)
    banner:Show()
    banner:SetAlpha(0)
    A.Tween(0.45, function(p)
        banner:SetAlpha(min(1, p * 1.5))
        banner:SetScale(0.7 + 0.3 * p)
    end, nil, A.Ease.outBack)
end
