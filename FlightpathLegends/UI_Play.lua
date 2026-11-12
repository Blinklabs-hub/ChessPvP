-- Flightpath Legends - the Play tab - board with player strips, a slim action column, and a side
-- panel (game setup or move list) that folds away during games.
local _, ns = ...

local PV = {}
ns.PlayView = PV

local E, G, P, C, D, AI, A, W, Board = ns.Engine, ns.Game, ns.Profile, ns.Comm, ns.Data, ns.AI, ns.Assets, ns.W, ns.Board
local floor, max, min = math.floor, math.max, math.min

PV.BASE = 56 * 8 -- the board is built at 448px and scaled to fit
PV.STRIP = 58
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

-- Player strip: character portrait, name and title, rating/league/character line, captured
-- pieces and clock.
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
    s.portrait = W.Portrait(s, 50)
    s.portrait:SetPoint("LEFT", 3, 0)
    s.name = W.Title(s, 16)
    s.name:SetPoint("TOPLEFT", 58, -5)
    s.name:SetWordWrap(false)
    s.league = s:CreateTexture(nil, "ARTWORK")
    s.league:SetSize(14, 14)
    s.league:SetPoint("TOPLEFT", 58, -24)
    s.sub = W.Label(s, "GameFontHighlightSmall")
    s.sub:SetPoint("TOPLEFT", 76, -25)
    s.sub:SetWordWrap(false)
    s.clock = W.Title(s, 24)
    s.clock:SetPoint("RIGHT", -10, 0)
    s.clock:SetJustifyH("RIGHT")
    -- "YOUR MOVE" / "THINKING..." tag, pulsing
    s.tag = W.Title(s, 15)
    s.tag:SetPoint("TOPRIGHT", -10, -5)
    s.tag:SetJustifyH("RIGHT")
    s.t = 0
    s:SetScript("OnUpdate", function(self, elapsed)
        if not self.pulse then return end
        self.t = self.t + elapsed
        local a = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(self.t * 5))
        self.tag:SetAlpha(a)
        self.glow:SetAlpha(0.4 + 0.6 * a)
    end)
    s.tray = {}
    for k = 1, 15 do
        local v = Board.CreatePieceView(s, 15)
        v:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 58 + (k - 1) * 11, 2)
        v:SetFrameLevel(s:GetFrameLevel() + 2 + k)
        s.tray[k] = v
    end
    s.lead = W.Label(s, "GameFontNormalSmall")
    s.lead:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 58, 4)
    function s:SetStripWidth(w)
        self:SetWidth(w)
        self.name:SetWidth(max(80, w - 58 - 90))
        self.sub:SetWidth(max(60, w - 76 - 90))
    end
    return s
end

local function UpdateStrip(s, g, color)
    s.color = color
    local army = A.ArmyFor(color, g)
    local armyInfo = A.ARMIES[army]
    local name, rating, title
    local isComputer = g and g.mode == "ai" and color ~= g.myColor
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
    local info = (not isComputer) and W.CharInfo(name) or nil
    local e = P.players[name]
    s.portrait:SetPlayer(name, info, isComputer and army or (e and e.f) or (ns.SameName(name, ns.me) and A.MyFaction()) or army)
    local titleText = ""
    if rating and rating > 0 and not isComputer then
        titleText = "  " .. P.TitleText(title, rating, KnownGames(name))
    end
    s.name:SetText(W.ClassName(name, info, armyInfo.color) .. titleText)
    local line
    if isComputer then
        line = "|cffaaaaaaLeads " .. armyInfo.title .. "|r"
        s.league:Hide()
    else
        local li = G.LeagueIndex(name)
        if li > 0 then W.SetLeagueIcon(s.league, li) else s.league:Hide() end
        line = (rating and rating > 0) and ("|cffffffff" .. rating .. "|r  ") or ""
        line = line .. "|cffaaaaaa" .. A.CharLine(info) .. "|r"
        if info and info.guild then line = line .. "  |cff40ff40<" .. info.guild .. ">|r" end
    end
    s.sub:ClearAllPoints()
    s.sub:SetPoint("TOPLEFT", s.league:IsShown() and 76 or 58, -25)
    s.sub:SetText(line)

    local toMove = g and g.state == "active" and g.pos.turn == color
    local c, k = armyInfo.color, toMove and 0.30 or 0.12
    s.bg:SetColorTexture(c[1] * k + 0.04, c[2] * k + 0.03, c[3] * k + 0.02, 0.94)
    if toMove then s.glow:Show() else s.glow:Hide() end
    if g and g.timed then s.clock:Show() else s.clock:Hide() end
    -- Whose move: a clear tag on the strip (the clock moves down when shown)
    local mine = g and g.myColor and color == g.myColor
    s.tag:ClearAllPoints()
    if g and g.timed then s.tag:SetPoint("BOTTOMRIGHT", -10, 5) else s.tag:SetPoint("RIGHT", -10, 0) end
    s.clock:ClearAllPoints()
    s.clock:SetPoint("TOPRIGHT", -10, -4)
    if toMove and g.mode ~= "spectate" and mine then
        s.tag:SetText("YOUR MOVE")
        s.tag:SetTextColor(0.3, 1, 0.3)
        s.pulse = true
    elseif toMove and g.mode ~= "spectate" then
        s.tag:SetText(isComputer and "THINKING..." or "THEIR MOVE")
        s.tag:SetTextColor(1, 0.55, 0.3)
        s.pulse = false
        s.tag:SetAlpha(1)
    elseif toMove then
        s.tag:SetText("TO MOVE")
        s.tag:SetTextColor(1, 0.82, 0)
        s.pulse = false
        s.tag:SetAlpha(1)
    else
        s.tag:SetText("")
        s.pulse = false
        s.glow:SetAlpha(1)
    end

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
    s.lead:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 58 + #sorted * 11 + 8, 4)
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
local PIECE_LETTER = { N = 2, B = 3, R = 4, Q = 5, K = 6 }
local PIECE_FILE = { "P", "N", "B", "R", "Q", "K" }

-- One log entry: a coloured piece icon plus the move without its piece letter.
local function LogEntry(g, ply, san)
    local color = (ply % 2 == 1) and 1 or -1
    local first = string.sub(san, 1, 1)
    local t = PIECE_LETTER[first] or 1
    local text = PIECE_LETTER[first] and string.sub(san, 2) or san
    if string.sub(san, 1, 3) == "O-O" then t, text = 6, san end
    local c = A.ARMIES[A.ArmyFor(color, g)].color
    local icon = string.format("|T%s%s_fill:14:14:0:0:128:128:0:128:0:128:%d:%d:%d|t", W.TEX, PIECE_FILE[t],
        floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255))
    -- captures in orange, checks in red
    text = string.gsub(text, "x", "|cffff9040x|r")
    text = string.gsub(text, "([+#])$", "|cffff4030%1|r")
    return { text = icon .. " " .. text, last = ply == #g.san }
end

function PV.LogRows(g)
    local rows = {}
    for ply = 1, #g.san do
        local n = floor((ply + 1) / 2)
        local row = rows[n]
        if not row then
            row = { n = n }
            rows[n] = row
        end
        row[(ply % 2 == 1) and 1 or 2] = LogEntry(g, ply, g.san[ply])
    end
    return rows
end

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

-- Time control choices: 0 = any (random opponents only), then Data.TIME_CONTROLS.
local function TcText(idx)
    if idx == 0 then return "Any time control" end
    return D.TIME_CONTROLS[idx].name
end
local function QueueTcText()
    return TcText(ns.db.settings.tc or 4)
end
PV.QueueTcText = QueueTcText

-- One panel: rated/casual, time control, then one of three ways to start a battle.
local function BuildSetup(sp)
    local s = ns.db.settings
    local W2 = PV.SIDE - 8

    local h1 = W.Title(sp, 20, "New Battle")
    h1:SetPoint("TOPLEFT", 4, -2)

    -- Rated / Casual toggle
    play.ratedTab = W.Button(sp, "Rated", W2 / 2 - 2, 26, function()
        s.rated = true
        if G.seek then G.StopSeek() end
        ns.UI.Refresh()
    end)
    play.ratedTab:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -10)
    play.casualTab = W.Button(sp, "Casual", W2 / 2 - 2, 26, function()
        s.rated = false
        if G.seek then G.StopSeek() end
        ns.UI.Refresh()
    end)
    play.casualTab:SetPoint("LEFT", play.ratedTab, "RIGHT", 4, 0)
    play.modeNote = W.Label(sp, "GameFontDisableSmall", "")
    play.modeNote:SetPoint("TOPLEFT", play.ratedTab, "BOTTOMLEFT", 2, -4)
    play.modeNote:SetWidth(W2)

    -- Time control: < Rapid 10+0 >
    local prev = W.Button(sp, "<", 28, 24, function()
        s.tc = ((s.tc or 4) - 1) % (#D.TIME_CONTROLS + 1)
        if G.seek then G.StopSeek() end
        ns.UI.Refresh()
    end)
    prev:SetPoint("TOPLEFT", play.modeNote, "BOTTOMLEFT", -2, -8)
    play.tcText = W.Title(sp, 16)
    play.tcText:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    play.tcText:SetWidth(W2 - 64)
    play.tcText:SetJustifyH("CENTER")
    local nextB = W.Button(sp, ">", 28, 24, function()
        s.tc = ((s.tc or 4) + 1) % (#D.TIME_CONTROLS + 1)
        if G.seek then G.StopSeek() end
        ns.UI.Refresh()
    end)
    nextB:SetPoint("LEFT", prev, "RIGHT", W2 - 28, 0)

    -- 1) A random opponent from the queue
    play.findButton = W.Button(sp, "Find Random Opponent", W2, 34, function()
        if G.seek then G.StopSeek() else ns.Tabs.JoinQueue(s.rated ~= false) end
        ns.UI.Refresh()
    end)
    play.findButton:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 2, -14)
    play.queueNote = W.Label(sp, "GameFontHighlightSmall", "")
    play.queueNote:SetPoint("TOPLEFT", play.findButton, "BOTTOMLEFT", 2, -4)
    play.queueNote:SetWidth(W2)

    -- 2) A player by name
    local h2 = W.Label(sp, "GameFontNormal", "Challenge by name")
    h2:SetPoint("TOPLEFT", play.queueNote, "BOTTOMLEFT", -2, -14)
    local nameBox = CreateFrame("EditBox", nil, sp, "InputBoxTemplate")
    nameBox:SetSize(W2 - 104, 22)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 6, -6)
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
        G.Invite(name, { color = "r" })
        ns.UI.Refresh()
    end
    nameBox:SetScript("OnEnterPressed", SendChallenge)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    play.challengeButton = W.Button(sp, "Challenge", 92, 22, SendChallenge)
    play.challengeButton:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    play.setupNote = W.Label(sp, "GameFontDisableSmall", "")
    play.setupNote:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -4)
    play.setupNote:SetWidth(W2)

    -- 3) The computer
    local h3 = W.Label(sp, "GameFontNormal", "Practice against the computer")
    h3:SetPoint("TOPLEFT", play.setupNote, "BOTTOMLEFT", 0, -14)
    play.aiButton = W.Button(sp, "", 120, 24, function()
        s.aiLevel = (s.aiLevel % #AI.LEVELS) + 1
        ns.UI.Refresh()
    end)
    play.aiButton:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -6)
    W.Tooltip(play.aiButton, function(_, tip)
        tip:SetText("Click to change the difficulty", 1, 1, 1)
    end)
    local aiStart = W.Button(sp, "Play vs Computer", W2 - 126, 24, function()
        G.StartAI(s.aiLevel, nil)
    end)
    aiStart:SetPoint("LEFT", play.aiButton, "RIGHT", 6, 0)

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
    -- Battle log: # | White | Black, with piece icons and the latest move lit up.
    local head = CreateFrame("Frame", nil, movesBox)
    head:SetHeight(20)
    head:SetPoint("TOPLEFT", 4, -4)
    head:SetPoint("TOPRIGHT", -4, -4)
    W.Background(head, 1, 0.82, 0, 0.10)
    play.logHead = head
    head.num = W.Label(head, "GameFontNormalSmall", "#")
    head.num:SetPoint("LEFT", 6, 0)
    head.white = W.Label(head, "GameFontNormalSmall", "White")
    head.white:SetPoint("LEFT", 36, 0)
    head.white:SetWordWrap(false)
    head.black = W.Label(head, "GameFontNormalSmall", "Black")
    head.black:SetWordWrap(false)
    play.log = W.List(movesBox, 18, function(row)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.num = W.Label(row, "GameFontDisableSmall")
        row.num:SetPoint("LEFT", 6, 0)
        row.cells = {}
        for i = 1, 2 do
            local c = CreateFrame("Frame", nil, row)
            c:SetHeight(18)
            c.hl = c:CreateTexture(nil, "BORDER")
            c.hl:SetAllPoints()
            c.hl:SetColorTexture(1, 0.82, 0, 0.22)
            c.text = W.Label(c, "GameFontHighlight")
            c.text:SetPoint("LEFT", 2, 0)
            if STANDARD_TEXT_FONT then c.text:SetFont(STANDARD_TEXT_FONT, 12, "") end
            row.cells[i] = c
        end
        function row:OnResize(w)
            local colW = (w - 36) / 2
            self.cells[1]:SetPoint("LEFT", 32, 0)
            self.cells[1]:SetWidth(colW)
            self.cells[2]:SetPoint("LEFT", 32 + colW, 0)
            self.cells[2]:SetWidth(colW)
        end
    end, function(row, item)
        row.stripe:SetColorTexture(1, 1, 1, item.n % 2 == 0 and 0.05 or 0)
        row.num:SetText(item.n .. ".")
        for i = 1, 2 do
            local c, mv = row.cells[i], item[i]
            if mv then
                c.text:SetText(mv.text)
                if mv.last then c.hl:Show() else c.hl:Hide() end
                c:Show()
            else
                c:Hide()
            end
        end
    end, 0)
    play.log:SetPoint("TOPLEFT", 4, -26)
    play.logEmpty = W.Label(movesBox, "GameFontDisableSmall", "No moves yet.")
    play.logEmpty:SetPoint("TOPLEFT", 12, -32)

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
        ns.UI.NewGame("chess")
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
        ns.UI.NewGame("chess")
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
    play.log:Resize(PV.SIDE - 8, movesH - 30)
    local colW = (PV.SIDE - 8 - 36) / 2
    play.logHead.white:SetWidth(colW - 4)
    play.logHead.black:ClearAllPoints()
    play.logHead.black:SetPoint("LEFT", play.logHead, "LEFT", 36 + colW, 0)
    play.logHead.black:SetWidth(colW - 4)
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
    local rows = PV.LogRows(g)
    local log = play.log
    -- Follow the game: jump to the newest move when one is played.
    if #g.san ~= play.logCount or g ~= play.logGame then
        play.logCount, play.logGame = #g.san, g
        log.offset = math.max(0, #rows - (log.visible or 1))
    end
    log:SetData(rows)
    if #rows == 0 then play.logEmpty:Show() else play.logEmpty:Hide() end
    local wName, bName = ns.ShortName(g.white), ns.ShortName(g.black)
    local wc, bc = A.ARMIES[A.ArmyFor(1, g)].color, A.ARMIES[A.ArmyFor(-1, g)].color
    play.logHead.white:SetText("|c" .. W.Hex(wc) .. wName .. "|r")
    play.logHead.black:SetText("|c" .. W.Hex(bc) .. bName .. "|r")
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
    if G.current and G.current.state == "active" then play.backButton:Show() else play.backButton:Hide() end
    local tcIdx = s.tc or 4
    local tc = D.TIME_CONTROLS[tcIdx]
    local rated = s.rated ~= false
    -- Rated battles need a clock.
    if rated and tc and tc.base == 0 then rated = false end
    if rated then play.ratedTab:Disable(); play.casualTab:Enable() else play.casualTab:Disable(); play.ratedTab:Enable() end
    local li = G.LeagueIndex(ns.me)
    if rated then
        play.modeNote:SetText("Counts for the ladder. " .. (li == 0 and "Unranked: you can face any league."
            or ("You play in the " .. D.LEAGUES[li].name .. " league.")))
    else
        play.modeNote:SetText(tc and tc.base == 0 and s.rated ~= false and "|cffff8040Rated battles need a clock - this one is casual.|r"
            or "Just for fun - your rating is not affected.")
    end
    play.tcText:SetText(TcText(tcIdx))

    local seek = G.seek
    if seek then
        local secs = floor(ns.Now() - (seek.since or ns.Now()))
        play.findButton:SetText(string.format("Searching... %d:%02d  (cancel)", floor(secs / 60), secs % 60))
    else
        play.findButton:SetText(rated and "Find Random Opponent (rated)" or "Find Random Opponent (casual)")
    end
    if not C.Joined() then
        play.queueNote:SetText("|cffaaaaaaConnecting to the chess network...|r")
    else
        local r, c = 0, 0
        for _, o in pairs(P.online) do
            if o.status == "r" then r = r + 1 elseif o.status == "c" then c = c + 1 end
        end
        play.queueNote:SetText(string.format("|cffaaaaaa%d looking for a rated battle  ·  %d for a casual one|r", r, c))
    end
    play.aiButton:SetText(AI.LEVELS[s.aiLevel].name)
    if G.outgoing and not G.outgoing.q then
        play.challengeButton:SetText("Cancel")
        play.setupNote:SetText("|cffffd100Waiting for " .. ns.ShortName(G.outgoing.to) .. " to answer...|r")
    else
        play.challengeButton:SetText("Challenge")
        play.setupNote:SetText("Type a name, or leave it empty to challenge your target." ..
            (tcIdx == 0 and "  (Any time control: Rapid 10+0 is used.)" or ""))
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
