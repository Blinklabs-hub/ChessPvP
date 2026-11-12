-- ChessPvP: main window (Play, Lobby, Ladder, Collection, Settings), challenge popup, toasts, launcher.
local _, ns = ...

local UI = {}
ns.UI = UI

local E, G, P, C, D, AI, Board = ns.Engine, ns.Game, ns.Profile, ns.Comm, ns.Data, ns.AI, ns.Board
local floor, max, min = math.floor, math.max, math.min

local SQUARE = 56
local BOARD = SQUARE * 8
local SIDE = 290
local PAD = 14
local TOP = 62
local WIDTH = PAD + BOARD + PAD + SIDE + PAD
local HEIGHT = TOP + BOARD + PAD
local CONTENT_W = WIDTH - PAD * 2
local TEX = "Interface\\AddOns\\ChessPvP\\Textures\\"

local main -- created on first use
local built = false

------------------------------------------------------------------------
-- Small widget helpers
------------------------------------------------------------------------
local function AddBackground(frame, r, g, b, a, border)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(r, g, b, a)
    frame.bg = bg
    if border then
        local function Edge(p1, p2, w, h)
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetColorTexture(border[1], border[2], border[3], border[4] or 1)
            t:SetPoint(p1)
            t:SetPoint(p2)
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
        end
        Edge("TOPLEFT", "TOPRIGHT", nil, 1)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
        Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
        Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    end
end

local function Label(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

local function Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    b:SetScript("OnClick", function(self)
        ns.Sound("click")
        onClick(self)
    end)
    return b
end

local function Check(parent, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local fs = Label(parent, "GameFontHighlight", text)
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label = fs
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Sound("click")
    end)
    cb.Sync = function() cb:SetChecked(get() and true or false) end
    return cb
end

local function Tooltip(frame, fn)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if fn(self, GameTooltip) ~= false then GameTooltip:Show() end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A simple paged list scrolled with the mouse wheel.
local function CreateList(parent, width, rows, rowHeight, build, update)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, rows * rowHeight)
    list.rows, list.data, list.offset = {}, {}, 0
    for i = 1, rows do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(width, rowHeight)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0)
        build(row)
        list.rows[i] = row
    end
    function list:Update()
        local maxOffset = max(0, #self.data - rows)
        if self.offset > maxOffset then self.offset = maxOffset end
        for i = 1, rows do
            local row = self.rows[i]
            local item = self.data[i + self.offset]
            if item then
                row.item = item
                update(row, item, i + self.offset)
                row:Show()
            else
                row.item = nil
                row:Hide()
            end
        end
    end
    function list:SetData(data)
        self.data = data
        self:Update()
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = max(0, self.offset - delta * 3)
        self:Update()
    end)
    return list
end

local function PlayerText(name, titleId, rating, ratedGames)
    local s = "|cffffffff" .. ns.ShortName(name) .. "|r"
    if rating then
        s = s .. "  " .. P.TitleText(titleId, rating, ratedGames)
    end
    return s
end

local function TimeControlName(base, inc)
    if base == 0 then return "No clock" end
    return string.format("%d+%d", floor(base / 60), inc)
end

------------------------------------------------------------------------
-- Play tab
------------------------------------------------------------------------
local play = {}

local function KnownGames(name)
    if ns.SameName(name, ns.me) then return P.RatedGames() end
    local e = P.GetPlayer(name)
    return e and (e.w + e.l + e.d) or D.PLACEMENT_GAMES
end

local function UpdatePlate(plate, g, color)
    local name = (color == 1) and g.white or g.black
    local rating = (color == 1) and g.wr or g.br
    local title = (color == 1) and g.wt or g.bt
    local text = "|cffffffff" .. ns.ShortName(name) .. "|r"
    plate.name:SetText(text)
    if rating and rating > 0 then
        plate.sub:SetText(P.TitleText(title, rating, KnownGames(name)) .. "  |cffaaaaaa" .. rating .. "|r")
    else
        plate.sub:SetText((color == 1) and "|cffaaaaaaWhite|r" or "|cffaaaaaaBlack|r")
    end
    plate.color = color
    local toMove = g.state == "active" and g.pos.turn == color
    plate.bg:SetColorTexture(toMove and 0.20 or 0.10, toMove and 0.26 or 0.10, toMove and 0.14 or 0.12, 0.9)
    if g.timed then
        plate.clock:Show()
    else
        plate.clock:Hide()
    end
end

local function UpdateClocks()
    local g = G.current
    if not g or not g.timed then return end
    for i = 1, 2 do
        local plate = play.plates[i]
        if plate.color then
            local left = G.Remaining(g, plate.color)
            plate.clock:SetText(ns.FormatClock(left))
            if left < 20 and g.state == "active" and g.pos.turn == plate.color then
                plate.clock:SetTextColor(1, 0.25, 0.2)
            else
                plate.clock:SetTextColor(1, 1, 1)
            end
        end
    end
end

local function MoveListText(g)
    local lines = {}
    local n = #g.san
    local pairsTotal = floor((n + 1) / 2)
    local first = max(1, pairsTotal - 11)
    for i = first, pairsTotal do
        local w = g.san[i * 2 - 1] or ""
        local b = g.san[i * 2] or ""
        lines[#lines + 1] = string.format("|cff888888%d.|r %s   %s", i, w, b)
    end
    if #lines == 0 then return "|cff888888No moves yet.|r" end
    return table.concat(lines, "\n")
end

local function StatusText(g)
    if g.state == "over" then
        local r = g.result
        local text
        if r == "1-0" then
            text = "White wins by " .. (D.REASON_TEXT[g.reason] or g.reason)
        elseif r == "0-1" then
            text = "Black wins by " .. (D.REASON_TEXT[g.reason] or g.reason)
        elseif r == "1/2" then
            text = "Draw by " .. (D.REASON_TEXT[g.reason] or g.reason)
        else
            text = "No result: " .. (D.REASON_TEXT[g.reason] or "game ended")
        end
        if g.outcome == "win" then
            text = "|cff40ff40Victory!|r " .. text
        elseif g.outcome == "loss" then
            text = "|cffff5040Defeat.|r " .. text
        end
        if g.rated and g.delta and g.outcome then
            text = text .. string.format("\nRating %s%d  (now %d)", g.delta >= 0 and "|cff40ff40+" or "|cffff5040", g.delta, P.me.rating) .. "|r"
        end
        return text
    end
    local side = (g.pos.turn == 1) and "White" or "Black"
    local check = E.InCheck(g.pos) and "  |cffff4030Check!|r" or ""
    if g.mode == "spectate" then
        return "Watching. " .. side .. " to move." .. check
    elseif g.mode == "local" then
        return side .. " to move." .. check
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
        kind = (g.rated and "Rated" or "Casual") .. " game"
    elseif g.mode == "ai" then
        kind = "Practice game"
    elseif g.mode == "local" then
        kind = "Pass & Play"
    else
        kind = "Spectating " .. (g.rated and "rated" or "casual") .. " game"
    end
    return kind .. "  |cffaaaaaa" .. TimeControlName(g.base, g.inc) .. "|r"
end

local function RefreshSetup()
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
    if G.seek then
        play.seekButton:SetText("Searching... (cancel)")
    else
        play.seekButton:SetText("Find Match")
    end
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

local function RefreshPlay()
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

    local showSetup = (not g) or play.showSetup
    if showSetup then
        play.setup:Show()
        play.gamePanel:Hide()
        RefreshSetup()
        return
    end
    play.setup:Hide()
    play.gamePanel:Show()

    local topColor = board.flipped and 1 or -1
    UpdatePlate(play.plates[1], g, topColor)
    UpdatePlate(play.plates[2], g, -topColor)
    UpdateClocks()
    play.header:SetText(GameHeader(g))
    play.moves:SetText(MoveListText(g))
    play.status:SetText(StatusText(g))

    local active = g.state == "active"
    if active and g.mode == "online" and g.drawOffer == -g.myColor then
        play.drawBar:Show()
    else
        play.drawBar:Hide()
    end
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

local function BuildPlay(page)
    local board = Board.Create(page, SQUARE)
    board:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    play.board = board

    local side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPLEFT", board, "TOPRIGHT", PAD, 0)
    side:SetSize(SIDE, BOARD)

    ------------------------------------------------------------ game panel
    local gp = CreateFrame("Frame", nil, side)
    gp:SetAllPoints()
    play.gamePanel = gp

    play.plates = {}
    for i = 1, 2 do
        local plate = CreateFrame("Frame", nil, gp)
        plate:SetSize(SIDE, 46)
        if i == 1 then
            plate:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, 0)
        else
            plate:SetPoint("BOTTOMLEFT", gp, "BOTTOMLEFT", 0, 30)
        end
        AddBackground(plate, 0.10, 0.10, 0.12, 0.9, { 0.3, 0.3, 0.35, 1 })
        plate.name = Label(plate, "GameFontNormal")
        plate.name:SetPoint("TOPLEFT", 8, -7)
        plate.name:SetWidth(SIDE - 100)
        plate.name:SetWordWrap(false)
        plate.sub = Label(plate, "GameFontHighlightSmall")
        plate.sub:SetPoint("BOTTOMLEFT", 8, 7)
        plate.clock = Label(plate, "GameFontHighlightLarge")
        plate.clock:SetPoint("RIGHT", -10, 0)
        plate.clock:SetJustifyH("RIGHT")
        play.plates[i] = plate
    end

    play.header = Label(gp, "GameFontNormal")
    play.header:SetPoint("TOPLEFT", play.plates[1], "BOTTOMLEFT", 2, -10)

    local movesBox = CreateFrame("Frame", nil, gp)
    movesBox:SetPoint("TOPLEFT", play.header, "BOTTOMLEFT", -2, -6)
    movesBox:SetSize(SIDE, 176)
    AddBackground(movesBox, 0, 0, 0, 0.35, { 0.25, 0.25, 0.3, 1 })
    play.moves = Label(movesBox, "GameFontHighlightSmall")
    play.moves:SetPoint("TOPLEFT", 8, -6)
    play.moves:SetPoint("BOTTOMRIGHT", -8, 6)
    play.moves:SetJustifyV("TOP")
    play.moves:SetSpacing(2)

    play.status = Label(gp, "GameFontHighlight")
    play.status:SetPoint("TOPLEFT", movesBox, "BOTTOMLEFT", 2, -8)
    play.status:SetWidth(SIDE - 4)
    play.status:SetJustifyV("TOP")
    play.status:SetSpacing(3)

    local drawBar = CreateFrame("Frame", nil, gp)
    drawBar:SetSize(SIDE, 26)
    drawBar:SetPoint("BOTTOMLEFT", play.plates[2], "TOPLEFT", 0, 6)
    AddBackground(drawBar, 0.25, 0.20, 0.05, 0.9, { 0.8, 0.65, 0.1, 1 })
    local dl = Label(drawBar, "GameFontHighlightSmall", "Your opponent offers a draw")
    dl:SetPoint("LEFT", 8, 0)
    local decline = Button(drawBar, "No", 40, 20, function() G.DeclineDraw() end)
    decline:SetPoint("RIGHT", -4, 0)
    local accept = Button(drawBar, "Accept", 60, 20, function() G.OfferDraw() end)
    accept:SetPoint("RIGHT", decline, "LEFT", -4, 0)
    drawBar:Hide()
    play.drawBar = drawBar

    play.resignButton = Button(gp, "Resign", 92, 24, function(self)
        local g = G.current
        if not g or g.state ~= "active" then return end
        if g.mode == "spectate" or play.resignArmed then
            play.resignArmed = false
            G.Resign()
            return
        end
        -- Ask for a second click so a slip of the mouse does not end the game.
        play.resignArmed = true
        self:SetText("Sure?")
        ns.After(3, function()
            if play.resignArmed then
                play.resignArmed = false
                UI.Refresh()
            end
        end)
    end)
    play.resignButton:SetPoint("BOTTOMLEFT", gp, "BOTTOMLEFT", 0, 0)
    play.drawButton = Button(gp, "Offer Draw", 92, 24, function() G.OfferDraw() end)
    play.drawButton:SetPoint("LEFT", play.resignButton, "RIGHT", 6, 0)
    play.flipButton = Button(gp, "Flip Board", 92, 24, function()
        board.flipped = not board.flipped
        board:ClearSelection()
        UI.Refresh()
    end)
    play.flipButton:SetPoint("BOTTOMRIGHT", gp, "BOTTOMRIGHT", 0, 0)
    play.newButton = Button(gp, "New Game", 120, 24, function()
        play.showSetup = true
        UI.Refresh()
    end)
    play.newButton:SetPoint("BOTTOMLEFT", gp, "BOTTOMLEFT", 0, 0)

    ------------------------------------------------------------ setup panel
    local sp = CreateFrame("Frame", nil, side)
    sp:SetAllPoints()
    play.setup = sp
    local s = ns.db.settings

    local h1 = Label(sp, "GameFontNormalLarge", "Play a player")
    h1:SetPoint("TOPLEFT", 0, -2)

    local tcLabel = Label(sp, "GameFontHighlightSmall", "Time control")
    tcLabel:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -12)
    play.tcButton = Button(sp, "", 150, 22, function()
        s.tc = (s.tc % #D.TIME_CONTROLS) + 1
        if G.seek then G.StopSeek() end
        UI.Refresh()
    end)
    play.tcButton:SetPoint("TOPRIGHT", sp, "TOPRIGHT", 0, -28)

    local colLabel = Label(sp, "GameFontHighlightSmall", "Your colour (challenges)")
    colLabel:SetPoint("TOPLEFT", tcLabel, "BOTTOMLEFT", 0, -16)
    play.colorButton = Button(sp, "", 150, 22, function()
        s.color = (s.color == "r" and "w") or (s.color == "w" and "b") or "r"
        UI.Refresh()
    end)
    play.colorButton:SetPoint("TOPRIGHT", play.tcButton, "BOTTOMRIGHT", 0, -6)

    play.ratedCheck = Check(sp, "Rated", function() return s.rated end, function(v)
        s.rated = v
        if G.seek then G.StopSeek() end
        UI.Refresh()
    end)
    play.ratedCheck:SetPoint("TOPLEFT", colLabel, "BOTTOMLEFT", -4, -12)

    play.seekButton = Button(sp, "Find Match", SIDE, 28, function()
        if G.seek then
            G.StopSeek()
        else
            local tc = D.TIME_CONTROLS[s.tc]
            G.StartSeek(tc.base, tc.inc, s.rated)
        end
        UI.Refresh()
    end)
    play.seekButton:SetPoint("TOPLEFT", play.ratedCheck, "BOTTOMLEFT", 4, -8)

    local nameBox = CreateFrame("EditBox", nil, sp, "InputBoxTemplate")
    nameBox:SetSize(SIDE - 110, 22)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetPoint("TOPLEFT", play.seekButton, "BOTTOMLEFT", 6, -12)
    play.nameBox = nameBox
    local function SendChallenge()
        if G.outgoing and not G.outgoing.q then
            G.CancelInvite()
            UI.Refresh()
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
        UI.Refresh()
    end
    nameBox:SetScript("OnEnterPressed", SendChallenge)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    play.challengeButton = Button(sp, "Challenge", 96, 22, SendChallenge)
    play.challengeButton:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    local hint = Label(sp, "GameFontDisableSmall", "Name of a player, or leave empty to challenge your target.")
    hint:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -4)
    hint:SetWidth(SIDE)

    play.setupNote = Label(sp, "GameFontHighlightSmall", "")
    play.setupNote:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    play.setupNote:SetWidth(SIDE)
    play.setupNote:SetTextColor(1, 0.82, 0)

    local h2 = Label(sp, "GameFontNormalLarge", "Practice")
    h2:SetPoint("TOPLEFT", play.setupNote, "BOTTOMLEFT", 0, -22)
    play.aiButton = Button(sp, "", 170, 24, function()
        s.aiLevel = (s.aiLevel % #AI.LEVELS) + 1
        UI.Refresh()
    end)
    play.aiButton:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -10)
    local aiStart = Button(sp, "Play", SIDE - 176, 24, function()
        local color = (s.color == "w" and 1) or (s.color == "b" and -1) or nil
        G.StartAI(s.aiLevel, color)
    end)
    aiStart:SetPoint("LEFT", play.aiButton, "RIGHT", 6, 0)
    local localButton = Button(sp, "Pass & Play (two players, one screen)", SIDE, 24, function() G.StartLocal() end)
    localButton:SetPoint("TOPLEFT", play.aiButton, "BOTTOMLEFT", 0, -8)

    play.backButton = Button(sp, "Back to game", 120, 24, function()
        play.showSetup = false
        UI.Refresh()
    end)
    play.backButton:SetPoint("BOTTOMLEFT", sp, "BOTTOMLEFT", 0, 0)
end

------------------------------------------------------------------------
-- Lobby tab
------------------------------------------------------------------------
local lobby = {}

local STATUS_TEXT = {
    i = "|cff40ff40Available|r",
    s = "|cffffd100Looking for a match|r",
    d = "|cff808080Do not disturb|r",
}

local function RefreshLobby()
    local rows = P.OnlineList()
    lobby.list:SetData(rows)
    if #rows == 0 then
        if C.Joined() then
            lobby.empty:SetText("Nobody else with ChessPvP is online right now.\nChallenge a friend by name from the Play tab, or practise against the computer.")
        else
            lobby.empty:SetText("Connecting to the chess network...")
        end
        lobby.empty:Show()
    else
        lobby.empty:Hide()
    end
    lobby.count:SetText(#rows .. " player" .. (#rows == 1 and "" or "s") .. " online")
end

local function BuildLobby(page)
    lobby.count = Label(page, "GameFontNormal", "")
    lobby.count:SetPoint("TOPLEFT", 4, -2)
    local note = Label(page, "GameFontDisableSmall", "Challenges use the time control and rated setting chosen on the Play tab.")
    note:SetPoint("TOPRIGHT", -4, -4)

    lobby.list = CreateList(page, CONTENT_W, 17, 24, function(row)
        row.name = Label(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(330)
        row.name:SetWordWrap(false)
        row.rating = Label(row, "GameFontHighlight")
        row.rating:SetPoint("LEFT", 345, 0)
        row.status = Label(row, "GameFontHighlightSmall")
        row.status:SetPoint("LEFT", 410, 0)
        row.status:SetWidth(200)
        row.status:SetWordWrap(false)
        row.challenge = Button(row, "Challenge", 84, 20, function()
            if row.item then
                G.Invite(row.item.name)
                UI.ShowTab("play")
            end
        end)
        row.challenge:SetPoint("RIGHT", -4, 0)
        row.watch = Button(row, "Watch", 60, 20, function()
            if row.item then
                G.Watch(row.item.name)
                UI.ShowTab("play")
            end
        end)
        row.watch:SetPoint("RIGHT", row.challenge, "LEFT", -4, 0)
    end, function(row, item)
        row.name:SetText(PlayerText(item.name, item.t, item.r, item.g))
        row.rating:SetText(item.g > 0 and item.r or "|cff808080-|r")
        if item.status == "g" then
            row.status:SetText("|cffff9040Playing " .. (item.opp and ns.ShortName(item.opp) or "") .. "|r")
            row.watch:Show()
            row.challenge:Disable()
        else
            row.status:SetText(STATUS_TEXT[item.status] or STATUS_TEXT.i)
            row.watch:Hide()
            if item.status == "d" then row.challenge:Disable() else row.challenge:Enable() end
        end
    end)
    lobby.list:SetPoint("TOPLEFT", 0, -26)

    lobby.empty = Label(page, "GameFontHighlight", "")
    lobby.empty:SetPoint("CENTER", 0, 20)
    lobby.empty:SetJustifyH("CENTER")
    lobby.empty:SetSpacing(4)
end

------------------------------------------------------------------------
-- Ladder tab
------------------------------------------------------------------------
local ladder = {}

local function RefreshLadder()
    local rows = P.Board()
    local myRank
    for i = 1, #rows do
        rows[i].rank = i
        if rows[i].me then myRank = i end
    end
    ladder.list:SetData(rows)
    local p = P.me
    local line = string.format("Your rating: |cffffffff%d|r   %s   Record: |cff40ff40%d|r / |cffff5040%d|r / |cffaaaaaa%d|r",
        p.rating, P.TitleText(P.MyTitleId(), p.rating, P.RatedGames()), p.w, p.l, p.d)
    if myRank then
        line = line .. string.format("   Rank |cffffd100#%d|r of %d", myRank, #rows)
    else
        line = line .. "   |cffaaaaaaPlay a rated game to join the ladder.|r"
    end
    ladder.summary:SetText(line)
    if #rows == 0 then ladder.empty:Show() else ladder.empty:Hide() end
end

local function BuildLadder(page)
    ladder.summary = Label(page, "GameFontHighlight", "")
    ladder.summary:SetPoint("TOPLEFT", 4, -2)

    local head = CreateFrame("Frame", nil, page)
    head:SetSize(CONTENT_W, 20)
    head:SetPoint("TOPLEFT", 0, -24)
    AddBackground(head, 1, 1, 1, 0.08)
    local function Head(text, x)
        local fs = Label(head, "GameFontNormalSmall", text)
        fs:SetPoint("LEFT", x, 0)
    end
    Head("#", 8)
    Head("Player", 50)
    Head("Title", 300)
    Head("Rating", 470)
    Head("Won", 550)
    Head("Lost", 610)
    Head("Drawn", 670)

    ladder.list = CreateList(page, CONTENT_W, 18, 22, function(row)
        row.rank = Label(row, "GameFontHighlight")
        row.rank:SetPoint("LEFT", 8, 0)
        row.name = Label(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", 50, 0)
        row.name:SetWidth(240)
        row.name:SetWordWrap(false)
        row.title = Label(row, "GameFontHighlight")
        row.title:SetPoint("LEFT", 300, 0)
        row.rating = Label(row, "GameFontNormal")
        row.rating:SetPoint("LEFT", 470, 0)
        row.w = Label(row, "GameFontHighlight")
        row.w:SetPoint("LEFT", 550, 0)
        row.l = Label(row, "GameFontHighlight")
        row.l:SetPoint("LEFT", 610, 0)
        row.d = Label(row, "GameFontHighlight")
        row.d:SetPoint("LEFT", 670, 0)
        row.mine = row:CreateTexture(nil, "BORDER")
        row.mine:SetAllPoints()
        row.mine:SetColorTexture(1, 0.82, 0, 0.15)
    end, function(row, item)
        row.rank:SetText(item.rank)
        row.name:SetText(ns.ShortName(item.name))
        row.title:SetText(P.TitleText(item.t, item.r, item.w + item.l + item.d))
        row.rating:SetText(item.r)
        row.w:SetText(item.w)
        row.l:SetText(item.l)
        row.d:SetText(item.d)
        if item.me then row.mine:Show() else row.mine:Hide() end
    end)
    ladder.list:SetPoint("TOPLEFT", 0, -46)

    ladder.empty = Label(page, "GameFontHighlight",
        "The ladder is empty so far.\nIt fills in as you meet other ChessPvP players on this realm.")
    ladder.empty:SetPoint("CENTER", 0, 0)
    ladder.empty:SetJustifyH("CENTER")
    ladder.empty:SetSpacing(4)
end

------------------------------------------------------------------------
-- Collection tab
------------------------------------------------------------------------
local coll = {}

local function RefreshCollection()
    local p = P.me
    coll.points:SetText(string.format("Badge points: |cffffd100%d|r", P.Points(p)))

    local themes = {}
    for i = 1, #D.THEMES do
        local t = D.THEMES[i]
        local ok, req = P.IsUnlocked(t)
        themes[i] = { item = t, unlocked = ok, req = req, selected = (P.Theme() == t) }
    end
    coll.themes:SetData(themes)

    local sets = {}
    for i = 1, #D.PIECES do
        local t = D.PIECES[i]
        local ok, req = P.IsUnlocked(t)
        sets[i] = { item = t, unlocked = ok, req = req, selected = (P.PieceSet() == t) }
    end
    coll.pieces:SetData(sets)

    local titles = { { id = nil, name = "Current rank (automatic)", color = "ffffffff", selected = (p.title == nil) } }
    local avail = P.AvailableTitles()
    for i = 1, #avail do
        local t = avail[i]
        titles[#titles + 1] = { id = t.id, name = t.name, color = t.color, selected = (p.title == t.id) }
    end
    coll.titles:SetData(titles)

    local badges = {}
    for i = 1, #D.BADGES do
        local b = D.BADGES[i]
        badges[i] = { badge = b, earned = p.badges[b.id] }
    end
    table.sort(badges, function(a, b)
        if (a.earned ~= nil) ~= (b.earned ~= nil) then return a.earned ~= nil end
        return a.badge.points < b.badge.points
    end)
    coll.badges:SetData(badges)
end

local function BuildUnlockList(page, onPick, swatch)
    return CreateList(page, 330, swatch and 10 or 7, 20, function(row)
        -- Two colour swatches: light/dark squares, or white/black piece colours.
        row.sw1 = row:CreateTexture(nil, "ARTWORK")
        row.sw1:SetSize(12, 12)
        row.sw1:SetPoint("LEFT", 6, 0)
        row.sw2 = row:CreateTexture(nil, "ARTWORK")
        row.sw2:SetSize(12, 12)
        row.sw2:SetPoint("LEFT", row.sw1, "RIGHT", 0, 0)
        row.text = Label(row, "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 38, 0)
        row.text:SetWidth(286)
        row.text:SetWordWrap(false)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
        row:SetScript("OnClick", function(self)
            if self.item and self.item.unlocked then
                ns.Sound("click")
                onPick(self.item.item.id)
            end
        end)
    end, function(row, entry)
        local item = entry.item
        local a = swatch and item.light or item.wFill
        local b = swatch and item.dark or item.bFill
        row.sw1:SetColorTexture(a[1], a[2], a[3], 1)
        row.sw2:SetColorTexture(b[1], b[2], b[3], 1)
        if entry.selected then
            row.text:SetText("|cff40ff40" .. item.name .. "  (in use)|r")
        elseif entry.unlocked then
            row.text:SetText(item.name)
        else
            row.text:SetText("|cff808080" .. item.name .. "  -  " .. entry.req .. "|r")
        end
    end)
end

local function BuildCollection(page)
    local h1 = Label(page, "GameFontNormal", "Board themes")
    h1:SetPoint("TOPLEFT", 4, -2)
    coll.themes = BuildUnlockList(page, function(id) P.SetTheme(id) end, true)
    coll.themes:SetPoint("TOPLEFT", 0, -20)

    local h2 = Label(page, "GameFontNormal", "Piece sets")
    h2:SetPoint("TOPLEFT", 4, -230)
    coll.pieces = BuildUnlockList(page, function(id) P.SetPieces(id) end, false)
    coll.pieces:SetPoint("TOPLEFT", 0, -248)

    local h3 = Label(page, "GameFontNormal", "Title shown to other players")
    h3:SetPoint("TOPLEFT", 4, -398)
    coll.titles = CreateList(page, 330, 2, 20, function(row)
        row.text = Label(row, "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 8, 0)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
        row:SetScript("OnClick", function(self)
            if self.item then
                ns.Sound("click")
                P.SetTitle(self.item.id)
                G.Announce()
            end
        end)
    end, function(row, item)
        row.text:SetText("|c" .. item.color .. item.name .. "|r" .. (item.selected and "  |cff40ff40(in use)|r" or ""))
    end)
    coll.titles:SetPoint("TOPLEFT", 0, -416)
    local scrollHint = Label(page, "GameFontDisableSmall", "Scroll for more")
    scrollHint:SetPoint("LEFT", h3, "RIGHT", 8, 0)

    coll.points = Label(page, "GameFontNormal", "")
    coll.points:SetPoint("TOPLEFT", 350, -2)
    coll.badges = CreateList(page, CONTENT_W - 346, 18, 24, function(row)
        row.name = Label(row, "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", 6, -1)
        row.desc = Label(row, "GameFontDisableSmall")
        row.desc:SetPoint("BOTTOMLEFT", 6, 1)
        row.desc:SetWidth(CONTENT_W - 346 - 60)
        row.desc:SetWordWrap(false)
        row.pts = Label(row, "GameFontNormal")
        row.pts:SetPoint("RIGHT", -8, 0)
        Tooltip(row, function(self, tip)
            local entry = self.item
            if not entry then return false end
            local b = entry.badge
            tip:SetText(b.name, 1, 0.82, 0)
            tip:AddLine(b.desc, 1, 1, 1, true)
            if b.title then tip:AddLine("Unlocks the title: " .. b.title, 0.4, 1, 0.4) end
            if not entry.earned and b.progress then
                local have, need = b.progress(P.me)
                tip:AddLine(string.format("Progress: %d / %d", min(have, need), need), 0.8, 0.8, 0.8)
            end
        end)
    end, function(row, entry)
        local b = entry.badge
        if entry.earned then
            row.name:SetText("|cffffd100" .. b.name .. "|r")
            row.pts:SetText(b.points)
        else
            row.name:SetText("|cff808080" .. b.name .. "|r")
            row.pts:SetText("|cff606060" .. b.points .. "|r")
        end
        row.desc:SetText(b.desc)
    end)
    coll.badges:SetPoint("TOPLEFT", 346, -20)
end

------------------------------------------------------------------------
-- Settings tab
------------------------------------------------------------------------
local settings = {}

local function RefreshSettings()
    for i = 1, #settings.checks do settings.checks[i].Sync() end
    settings.scaleButton:SetText(string.format("Window size: %d%%", floor(ns.db.settings.scale * 100 + 0.5)))
end

local function BuildSettings(page)
    local s = ns.db.settings
    settings.checks = {}
    local y = -6
    local function Add(text, key, onChange)
        local cb = Check(page, text, function() return s[key] end, function(v)
            s[key] = v
            if onChange then onChange(v) end
            UI.Refresh()
        end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 30
        settings.checks[#settings.checks + 1] = cb
    end
    Add("Play sounds", "sound")
    Add("Show legal moves when a piece is selected", "showLegal")
    Add("Let other players watch my games", "allowSpectators")
    Add("Do not disturb (automatically decline challenges)", "dnd", function() G.Announce() end)
    Add("Show the launcher button on screen", "showLauncher", function() UI.UpdateLauncher() end)

    settings.scaleButton = Button(page, "", 170, 24, function()
        local steps = { 0.8, 0.9, 1, 1.1, 1.2, 1.3 }
        local nextScale = steps[1]
        for i = 1, #steps do
            if steps[i] > s.scale + 0.01 then
                nextScale = steps[i]
                break
            end
        end
        s.scale = nextScale
        main:SetScale(nextScale)
        UI.Refresh()
    end)
    settings.scaleButton:SetPoint("TOPLEFT", 8, y - 6)

    local about = Label(page, "GameFontDisableSmall",
        "ChessPvP " .. ns.VERSION .. "\n\n" ..
        "Ratings use the Elo system and start at " .. D.START_RATING .. ". Rated games always use a clock.\n" ..
        "The ladder is shared directly between players on this realm who use the addon, so it shows everyone your client has met.\n\n" ..
        "Commands: /chess, /chess challenge <name>, /chess accept, /chess decline, /chess resign, /chess reset")
    about:SetPoint("BOTTOMLEFT", 6, 6)
    about:SetWidth(CONTENT_W - 12)
    about:SetSpacing(3)
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
local TABS = {
    { id = "play", text = "Play", build = BuildPlay, refresh = RefreshPlay },
    { id = "lobby", text = "Lobby", build = BuildLobby, refresh = RefreshLobby },
    { id = "ladder", text = "Ladder", build = BuildLadder, refresh = RefreshLadder },
    { id = "collection", text = "Collection", build = BuildCollection, refresh = RefreshCollection },
    { id = "settings", text = "Settings", build = BuildSettings, refresh = RefreshSettings },
}
local currentTab = "play"

local function Build()
    if built then return end
    built = true
    local s = ns.db.settings

    main = CreateFrame("Frame", "ChessPvPFrame", UIParent)
    main:SetSize(WIDTH, HEIGHT)
    main:SetFrameStrata("MEDIUM")
    main:SetToplevel(true)
    main:SetClampedToScreen(true)
    main:EnableMouse(true)
    main:SetMovable(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        s.pos = { point, relPoint, x, y }
    end)
    main:SetScale(s.scale or 1)
    if s.pos then
        main:SetPoint(s.pos[1], UIParent, s.pos[2], s.pos[3], s.pos[4])
    else
        main:SetPoint("CENTER")
    end
    AddBackground(main, 0.05, 0.05, 0.07, 0.96, { 0.45, 0.38, 0.20, 1 })
    table.insert(UISpecialFrames, "ChessPvPFrame") -- closes with Escape

    local title = Label(main, "GameFontNormalLarge", "|cffffd100Chess|r|cffffffffPvP|r")
    title:SetPoint("TOPLEFT", PAD, -10)
    main.me = Label(main, "GameFontHighlightSmall", "")
    main.me:SetPoint("LEFT", title, "RIGHT", 14, -1)

    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    main.tabs, main.pages = {}, {}
    local x = PAD
    for i = 1, #TABS do
        local tab = TABS[i]
        local b = Button(main, tab.text, 96, 22, function() UI.ShowTab(tab.id) end)
        b:SetPoint("TOPLEFT", x, -34)
        x = x + 100
        main.tabs[tab.id] = b
        local page = CreateFrame("Frame", nil, main)
        page:SetPoint("TOPLEFT", PAD, -TOP)
        page:SetSize(CONTENT_W, BOARD)
        page:Hide()
        main.pages[tab.id] = page
        tab.build(page)
    end

    local accum = 0
    main:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum >= 0.1 then
            accum = 0
            if currentTab == "play" then UpdateClocks() end
        end
    end)
    main:SetScript("OnShow", function()
        UI.Refresh()
        UI.UpdateAlert()
    end)
    main:SetScript("OnHide", function() UI.UpdateAlert() end)
    main:Hide()
end

function UI.Refresh()
    if not built or not main:IsShown() or not P.me then return end
    local p = P.me
    main.me:SetText(string.format("%s  %s  |cffaaaaaa%d|r", ns.ShortName(ns.me), P.TitleText(P.MyTitleId(), p.rating, P.RatedGames()), p.rating))
    for i = 1, #TABS do
        local tab = TABS[i]
        if tab.id == currentTab then
            main.pages[tab.id]:Show()
            main.tabs[tab.id]:Disable()
            tab.refresh()
        else
            main.pages[tab.id]:Hide()
            main.tabs[tab.id]:Enable()
        end
    end
end

function UI.ShowTab(id)
    currentTab = id
    UI.Show()
    UI.Refresh()
end

function UI.Show()
    if not ns.db or not P.me then return end
    Build()
    if not main:IsShown() then main:Show() end
end

function UI.Toggle()
    if not ns.db or not P.me then return end
    Build()
    if main:IsShown() then main:Hide() else main:Show() end
end

function UI.ResetPosition()
    if not ns.db then return end
    Build()
    ns.db.settings.pos = nil
    main:ClearAllPoints()
    main:SetPoint("CENTER")
    main:Show()
end

------------------------------------------------------------------------
-- Challenge popup
------------------------------------------------------------------------
local invitePopup

local function RefreshInvite()
    local inv = G.LatestInvite()
    if not inv then
        if invitePopup then invitePopup:Hide() end
        return
    end
    if not invitePopup then
        local f = CreateFrame("Frame", "ChessPvPInvite", UIParent)
        f:SetSize(380, 96)
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        AddBackground(f, 0.05, 0.05, 0.07, 0.96, { 0.9, 0.75, 0.2, 1 })
        f.title = Label(f, "GameFontNormalLarge", "Chess challenge")
        f.title:SetPoint("TOP", 0, -8)
        f.text = Label(f, "GameFontHighlight", "")
        f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.text:SetWidth(360)
        f.text:SetJustifyH("CENTER")
        f.accept = Button(f, "Accept", 110, 24, function()
            if f.id then G.AnswerInvite(f.id, true) end
            UI.ShowTab("play")
        end)
        f.accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 8)
        f.decline = Button(f, "Decline", 110, 24, function()
            if f.id then G.AnswerInvite(f.id, false) end
        end)
        f.decline:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 8)
        invitePopup = f
    end
    invitePopup.id = inv.id
    local e = P.GetPlayer(inv.from)
    local games = e and (e.w + e.l + e.d) or D.PLACEMENT_GAMES
    invitePopup.text:SetText(string.format("%s |cffaaaaaa(%d)|r\n%s, %s - you play %s",
        PlayerText(inv.from, inv.title, inv.rating, games), inv.rating,
        TimeControlName(inv.base, inv.inc), inv.rated and "|cffffd100rated|r" or "casual",
        (inv.theirColor == "w") and "Black" or "White"))
    invitePopup:Show()
end

------------------------------------------------------------------------
-- Toasts (badges and unlocks)
------------------------------------------------------------------------
local toastFrame
local toastQueue = {}

local function NextToast()
    if #toastQueue == 0 then
        toastFrame:Hide()
        return
    end
    local t = table.remove(toastQueue, 1)
    toastFrame.title:SetText(t[1])
    toastFrame.text:SetText(t[2])
    toastFrame.age = 0
    toastFrame:SetAlpha(1)
    toastFrame:Show()
    ns.Sound("unlock")
end

local function Toast(title, text)
    if not toastFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(300, 54)
        f:SetPoint("TOP", UIParent, "TOP", 0, -250)
        f:SetFrameStrata("DIALOG")
        AddBackground(f, 0.05, 0.05, 0.07, 0.95, { 1, 0.82, 0, 1 })
        f.title = Label(f, "GameFontNormal", "")
        f.title:SetPoint("TOP", 0, -9)
        f.text = Label(f, "GameFontHighlight", "")
        f.text:SetPoint("BOTTOM", 0, 10)
        f:SetScript("OnUpdate", function(self, elapsed)
            self.age = (self.age or 0) + elapsed
            if self.age > 4 then
                NextToast()
            elseif self.age > 3.2 then
                self:SetAlpha(max(0, (4 - self.age) / 0.8))
            end
        end)
        f:Hide()
        toastFrame = f
    end
    toastQueue[#toastQueue + 1] = { title, text }
    if not toastFrame:IsShown() then NextToast() end
end

------------------------------------------------------------------------
-- Launcher button
------------------------------------------------------------------------
local launcher

function UI.UpdateLauncher()
    if not ns.db then return end
    local s = ns.db.settings
    if not s.showLauncher then
        if launcher then launcher:Hide() end
        return
    end
    if not launcher then
        local b = CreateFrame("Button", "ChessPvPLauncher", UIParent)
        b:SetSize(34, 34)
        b:SetFrameStrata("MEDIUM")
        b:SetClampedToScreen(true)
        b:SetMovable(true)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", b.StartMoving)
        b:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint(1)
            s.launcherPos = { point, relPoint, x, y }
        end)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(TEX .. "logo")
        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.2)
        b.alert = b:CreateTexture(nil, "OVERLAY")
        b.alert:SetSize(12, 12)
        b.alert:SetPoint("TOPRIGHT", 2, 2)
        b.alert:SetTexture(TEX .. "dot")
        b.alert:SetVertexColor(1, 0.2, 0.1, 1)
        b.alert:Hide()
        b:SetScript("OnClick", function() UI.Toggle() end)
        Tooltip(b, function(_, tip)
            tip:SetText("ChessPvP", 1, 0.82, 0)
            tip:AddLine("Click to open. Drag to move.", 1, 1, 1)
        end)
        if s.launcherPos then
            b:SetPoint(s.launcherPos[1], UIParent, s.launcherPos[2], s.launcherPos[3], s.launcherPos[4])
        else
            b:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
        end
        launcher = b
    end
    launcher:Show()
end

-- Shows a red dot on the launcher when it is our move and the window is closed.
function UI.UpdateAlert()
    if not launcher then return end
    local g = G.current
    local myTurn = g and g.state == "active" and g.myColor and g.pos.turn == g.myColor
    if myTurn and not (built and main:IsShown()) then launcher.alert:Show() else launcher.alert:Hide() end
end

------------------------------------------------------------------------
-- Event wiring
------------------------------------------------------------------------
ns.On("CHESS_READY", function()
    local s = ns.db.settings
    s.tc = s.tc or 4
    if s.rated == nil then s.rated = true end
    s.color = s.color or "r"
    s.aiLevel = s.aiLevel or 2
    UI.UpdateLauncher()
end)

ns.On("CHESS_GAME_CHANGED", function()
    UI.Refresh()
    UI.UpdateAlert()
end)

ns.On("CHESS_GAME_STARTED", function(g)
    if g.mode == "online" then
        ns.Print("game started against " .. ns.ShortName(g.opp) .. ". You play " .. ((g.myColor == 1) and "White." or "Black."))
        UI.ShowTab("play")
    end
end)

ns.On("CHESS_GAME_MOVED", function(g, capture, check)
    if check then
        ns.Sound("check")
    elseif capture then
        ns.Sound("capture")
    else
        ns.Sound("move")
    end
end)

ns.On("CHESS_GAME_OVER", function(g)
    if g.outcome == "win" then
        ns.Sound("win")
    elseif g.outcome == "loss" then
        ns.Sound("lose")
    end
    if g.mode == "online" and g.outcome then
        local text = (g.outcome == "win" and "you won") or (g.outcome == "loss" and "you lost") or "the game was drawn"
        local msg = text .. " against " .. ns.ShortName(g.opp) .. " (" .. (D.REASON_TEXT[g.reason] or g.reason) .. ")."
        if g.rated and g.delta then
            msg = msg .. string.format(" Rating %s%d, now %d.", g.delta >= 0 and "+" or "", g.delta, P.me.rating)
        end
        ns.Print(msg)
    elseif g.mode == "online" then
        ns.Print("game ended without a result (" .. (D.REASON_TEXT[g.reason] or "aborted") .. ").")
    end
end)

ns.On("CHESS_INVITE_CHANGED", function()
    RefreshInvite()
    UI.Refresh()
end)

ns.On("CHESS_PROFILE_CHANGED", function() UI.Refresh() end)
ns.On("PROFILE_CHANGED", function() UI.Refresh() end)
ns.On("TOAST", Toast)

local lobbyDirty = false
ns.On("CHESS_LOBBY_CHANGED", function()
    if lobbyDirty then return end
    lobbyDirty = true
    ns.After(1, function()
        lobbyDirty = false
        if built and main:IsShown() and (currentTab == "lobby" or currentTab == "ladder") then UI.Refresh() end
    end)
end)
