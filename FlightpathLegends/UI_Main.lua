-- Flightpath Legends - the main window - frame, tabs, resizing and responsive layout, folding the
-- side panel during battles, challenge popup, toasts, launcher and event wiring.
local _, ns = ...

local UI = {}
ns.UI = UI

local G, P, C, D, A, W, Board, PV, T = ns.Game, ns.Profile, ns.Comm, ns.Data, ns.Assets, ns.W, ns.Board, ns.PlayView, ns.Tabs
local BV, BS = ns.BattleView, ns.Battleship
local floor, max, min = math.floor, math.max, math.min

local PAD = 12
local HEAD = 56 -- title row with the character card
local TABBAR = 30 -- tab buttons
local MIN_BOARD, MAX_BOARD = 300, 1000

local main
local built = false
local currentTab = "play"
local collapsed = false
local size = { w = 0, h = 0 } -- current window size (tracked here, not read back from frames)

-- game: tab only shown for that game ("chess" / "bs"); shared tabs have none.
local TABS = {
    { id = "play", game = "chess", text = "Battle", build = PV.Build, refresh = PV.Refresh },
    { id = "bsplay", game = "bs", text = "Battle", build = BV.Build, refresh = BV.Refresh },
    { id = "lobby", text = "Lobby", build = T.BuildLobby, refresh = T.RefreshLobby, layout = T.LayoutLobby },
    { id = "live", text = "Live Battles", build = T.BuildLive, refresh = T.RefreshLive, layout = T.LayoutLive },
    { id = "ladder", game = "chess", text = "Ladder", build = T.BuildLadder, refresh = T.RefreshLadder, layout = T.LayoutLadder },
    { id = "admirals", game = "bs", text = "Admirals", build = T.BuildAdmirals, refresh = T.RefreshAdmirals, layout = T.LayoutAdmirals },
    { id = "collection", text = "Collection", build = T.BuildCollection, refresh = T.RefreshCollection, layout = T.LayoutCollection },
    { id = "settings", text = "Settings", build = T.BuildSettings, refresh = T.RefreshSettings, layout = T.LayoutSettings },
}
-- The same tab in the other game.
local SWAP = { play = "bsplay", bsplay = "play", ladder = "admirals", admirals = "ladder" }

local function Game()
    return (ns.db and ns.db.settings.game == "bs") and "bs" or "chess"
end
UI.Game = Game

local function IsPlayTab(id) return id == "play" or id == "bsplay" end

local function TabVisible(tab)
    return tab.game == nil or tab.game == Game()
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
local function TabsVisible()
    return not (IsPlayTab(currentTab) and collapsed)
end

local function ContentTop()
    return HEAD + (TabsVisible() and TABBAR or 0)
end

local function ShowSide()
    return not collapsed
end

-- Window size that exactly fits a board of boardPx in the play tab.
local function PlaySizeFor(boardPx)
    local w = PAD + boardPx + PV.GAP + PV.HANDLE + PAD
    if ShowSide() then w = w + PV.GAP + PV.SIDE end
    local h = ContentTop() + PV.STRIP * 2 + PV.GAP * 2 + boardPx + PAD
    if ShowSide() then
        -- The setup panel needs a minimum height.
        h = max(h, ContentTop() + PV.SETUP_H + PAD)
    end
    return w, h
end

-- Largest board that fits the window size.
local function BoardFor(w, h)
    local availW = w - PAD * 2 - PV.GAP - PV.HANDLE - (ShowSide() and (PV.GAP + PV.SIDE) or 0)
    local availH = h - ContentTop() - PV.STRIP * 2 - PV.GAP * 2 - PAD
    return max(MIN_BOARD, min(MAX_BOARD, floor(min(availW, availH))))
end

-- Battleship page: window size for a square size, and the square size that fits.
local function BsSizeFor(cellPx)
    local w, h = BV.SizeFor(cellPx, ShowSide())
    return w + PAD * 2, h + ContentTop() + PAD
end
local function BsCellFor(w, h)
    return BV.CellFor(w - PAD * 2, h - ContentTop() - PAD, ShowSide())
end

local function SetMinSize()
    local minW, minH
    if currentTab == "bsplay" then
        minW, minH = BsSizeFor(20)
    elseif currentTab == "play" then
        minW, minH = PlaySizeFor(MIN_BOARD)
    else
        minW, minH = 620, 460
    end
    if main.SetResizeBounds then
        pcall(main.SetResizeBounds, main, minW, minH, 2400, 1600)
    elseif main.SetMinResize then
        pcall(main.SetMinResize, main, minW, minH)
    end
    return minW, minH
end

function UI.Layout()
    if not built then return end
    local w, h = size.w, size.h
    local top = ContentTop()
    -- The player line beside the title only when there is room for it.
    -- The character card shrinks with the window and hides when there is no room.
    local cardW = min(360, w - 290)
    if cardW >= 180 then
        main.me:SetWidth(cardW)
        main.me.name:SetWidth(cardW - 52 - 70)
        main.me.line:SetWidth(cardW - 52 - 50)
        main.me:Show()
    else
        main.me:Hide()
    end
    local x = PAD
    for i = 1, #TABS do
        local tab = TABS[i]
        local page = main.pages[tab.id]
        page:ClearAllPoints()
        page:SetPoint("TOPLEFT", main, "TOPLEFT", PAD, -top)
        page:SetSize(max(10, w - PAD * 2), max(10, h - top - PAD))
        local b = main.tabs[tab.id]
        if TabsVisible() and TabVisible(tab) then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", main, "TOPLEFT", x, -HEAD)
            x = x + 101
            b:Show()
        else
            b:Hide()
        end
    end
    if currentTab == "bsplay" then
        BV.Layout(BsCellFor(w, h), ShowSide())
    elseif currentTab == "play" then
        PV.Layout(BoardFor(w, h), ShowSide())
    else
        local tab
        for i = 1, #TABS do if TABS[i].id == currentTab then tab = TABS[i] end end
        if tab and tab.layout then tab.layout(max(10, w - PAD * 2), max(10, h - top - PAD)) end
    end
end

-- Sets the window size (keeps the top-left corner in place) and lays out.
local function ApplySize(w, h)
    local minW, minH = SetMinSize()
    w, h = max(w, minW), max(h, minH)
    size.w, size.h = floor(w + 0.5), floor(h + 0.5)
    main:SetSize(size.w, size.h)
    UI.Layout()
end

-- In the play tab the window hugs the board exactly.
local function SnapToBoard()
    if currentTab == "bsplay" then
        local w, h = BsSizeFor(BsCellFor(size.w, size.h))
        ApplySize(w, h)
        return
    end
    if currentTab ~= "play" then return end
    local w, h = PlaySizeFor(BoardFor(size.w, size.h))
    ApplySize(w, h)
end

local function SaveGeometry()
    local s = ns.db.settings
    local left, top = main:GetLeft(), main:GetTop()
    if left and top then s.pos = { "TOPLEFT", "BOTTOMLEFT", left, top } end
    if currentTab == "bsplay" then
        s.bsCell = BsCellFor(size.w, size.h)
    elseif currentTab == "play" then
        s.boardPx = BoardFor(size.w, size.h)
    else
        s.tabSize = { size.w, size.h }
    end
end

-- Resizes the window for the current tab and mode.
local function FitForTab()
    local s = ns.db.settings
    if currentTab == "bsplay" then
        local w, h = BsSizeFor(s.bsCell or 34)
        ApplySize(w, h)
    elseif currentTab == "play" then
        local w, h = PlaySizeFor(s.boardPx or 448)
        ApplySize(w, h)
    else
        local ts = s.tabSize or { 760, 560 }
        ApplySize(ts[1], ts[2])
    end
end

function UI.IsCollapsed()
    return collapsed
end

-- Folds the side panel and tabs away (or brings them back); the board keeps its size.
function UI.SetCollapsed(v)
    v = v and true or false
    if v == collapsed then return end
    collapsed = v
    if not built then return end
    FitForTab()
    UI.Refresh()
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function Build()
    if built then return end
    built = true
    local s = ns.db.settings
    s.scale = 1

    main = CreateFrame("Frame", "FlightpathLegendsFrame", UIParent)
    main:SetFrameStrata("MEDIUM")
    main:SetToplevel(true)
    main:SetClampedToScreen(true)
    main:EnableMouse(true)
    main:SetMovable(true)
    main:SetResizable(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveGeometry()
    end)
    if s.pos and s.pos[1] == "TOPLEFT" then
        main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.pos[3], s.pos[4])
    else
        main:SetPoint("CENTER")
    end
    W.Background(main, 0.05, 0.04, 0.04, 0.97)
    W.Tile(main, "dialogBg", 0.95)
    W.Chrome(main, "goldBorder", 6, 28)
    table.insert(UISpecialFrames, "FlightpathLegendsFrame") -- closes with Escape

    local title = W.Title(main, 24, "Flightpath Legends")
    title:SetPoint("TOPLEFT", PAD, -6)
    -- Game switcher: Chess / Battleship
    main.games = {}
    local games = {
        { id = "chess", text = "Chess", icon = "Interface\\Icons\\achievement_leader_king_varian_wrynn" },
        { id = "bs", text = "Battleship", icon = "Interface\\Icons\\inv_garrison_dreadnaught" },
    }
    for i, gdef in ipairs(games) do
        local b = CreateFrame("Button", nil, main)
        b:SetSize(112, 22)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * 116, -32)
        b.bg = W.Background(b, 0.1, 0.08, 0.05, 0.9, { 0.55, 0.43, 0.18, 0.9 })
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("LEFT", 3, 0)
        W.SetIcon(b.icon, gdef.icon)
        b.text = W.Title(b, 13, gdef.text)
        b.text:SetPoint("LEFT", 25, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.4, 0.12)
        b:SetScript("OnClick", function()
            ns.Sound("click")
            UI.SetGame(gdef.id)
        end)
        b.id = gdef.id
        main.games[gdef.id] = b
    end

    -- Your character card (armory style), top right. Click for your full profile.
    local card = CreateFrame("Button", nil, main)
    card:SetSize(340, 46)
    card:SetPoint("TOPRIGHT", -30, -5)
    main.me = card
    card.portrait = W.Portrait(card, 46)
    card.portrait:SetPoint("LEFT", 0, 0)
    card.statusDot = card:CreateTexture(nil, "OVERLAY")
    card.statusDot:SetSize(12, 12)
    card.statusDot:SetPoint("BOTTOMRIGHT", card.portrait, "BOTTOMRIGHT", 0, 1)
    card.statusDot:SetTexture(W.TEX .. "dot")
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card.name = W.Title(card, 16)
    card.name:SetPoint("TOPLEFT", 52, -5)
    card.name:SetWordWrap(false)
    card.line = W.Label(card, "GameFontHighlightSmall")
    card.line:SetPoint("BOTTOMLEFT", 52, 6)
    card.line:SetWordWrap(false)
    card.rating = W.Title(card, 20)
    card.rating:SetPoint("TOPRIGHT", -2, -4)
    card.rating:SetJustifyH("RIGHT")
    card.league = card:CreateTexture(nil, "ARTWORK")
    card.league:SetSize(20, 20)
    card.league:SetPoint("BOTTOMRIGHT", -2, 3)
    card.rank = card:CreateTexture(nil, "ARTWORK")
    card.rank:SetSize(20, 20)
    card.rank:SetPoint("RIGHT", card.league, "LEFT", -3, 0)
    local hl = card:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.85, 0.4, 0.07)
    card:SetScript("OnClick", function(self, button)
        if button == "RightButton" then UI.ShowStatusMenu(self) else UI.ShowProfile(ns.me) end
    end)
    W.Tooltip(card, function(_, tip)
        tip:SetText("Your profile", 1, 0.82, 0)
        tip:AddLine(UI.StatusText())
        tip:AddLine("Click to see your records, battles and feats.", 1, 1, 1)
        tip:AddLine("Right-click to set your status.", 0.7, 0.7, 0.7)
    end)

    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    main.tabs, main.pages = {}, {}
    local x = PAD
    for i = 1, #TABS do
        local tab = TABS[i]
        local b = W.Button(main, tab.text, 98, 24, function() UI.ShowTab(tab.id) end)
        b:SetPoint("TOPLEFT", x, -HEAD)
        main.tabs[tab.id] = b
        local page = CreateFrame("Frame", nil, main)
        page:Hide()
        main.pages[tab.id] = page
        tab.build(page)
    end

    -- Resize grip (bottom-right corner).
    local grip = CreateFrame("Button", nil, main)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(main:GetFrameLevel() + 50)
    local up = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
    if A.HasFile(up) then
        grip:SetNormalTexture(up)
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    else
        local t = grip:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetColorTexture(0.8, 0.65, 0.2, 0.6)
    end
    grip:SetScript("OnMouseDown", function()
        main.sizing = true
        main:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        main:StopMovingOrSizing()
        main.sizing = false
        SnapToBoard()
        SaveGeometry()
    end)
    W.Tooltip(grip, function(_, tip)
        tip:SetText("Drag to resize", 1, 0.82, 0)
    end)
    main:SetScript("OnSizeChanged", function(_, w, h)
        if not w or not h then return end
        size.w, size.h = w, h
        UI.Layout()
    end)

    local accum, bsAccum = 0, 0
    main:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum >= 0.1 then
            accum = 0
            if currentTab == "play" then PV.UpdateClocks() end
            if currentTab == "bsplay" and BS.current and BS.current.phase ~= "over" then
                bsAccum = (bsAccum or 0) + 1
                if bsAccum >= 3 then bsAccum = 0; BV.Refresh() end
            end
        end
    end)
    main:SetScript("OnShow", function()
        UI.Refresh()
        UI.UpdateAlert()
    end)
    main:SetScript("OnHide", function() UI.UpdateAlert() end)
    main:Hide()
    FitForTab()
end

function UI.Refresh()
    if not built or not main:IsShown() or not P.me then return end
    local p = P.me
    for id, b in pairs(main.games) do
        if id == Game() then
            b.bg:SetColorTexture(0.45, 0.32, 0.08, 0.95)
            b.text:SetTextColor(1, 0.92, 0.6)
        else
            b.bg:SetColorTexture(0.1, 0.08, 0.05, 0.9)
            b.text:SetTextColor(0.75, 0.62, 0.3)
        end
    end
    local card, info = main.me, A.MyCharInfo()
    card.portrait:SetPlayer(ns.me, info, A.MyFaction())
    card.name:SetText(W.ClassName(ns.me, info) .. "  |cffaaaaaa" .. P.TitleText(P.MyTitleId(), p.rating, P.RatedGames()) .. "|r")
    card.line:SetText(A.CharLine(info) .. (info.guild and ("  |cff40ff40<" .. info.guild .. ">|r") or ""))
    card.rating:SetText(p.rating)
    card.statusDot:SetVertexColor(unpack(UI.StatusColor()))
    local li = G.LeagueIndex(ns.me)
    if li > 0 then W.SetLeagueIcon(card.league, li) else card.league:Hide() end
    if P.RatedGames() >= D.PLACEMENT_GAMES then
        local idx = 1
        for i = 1, #D.RANKS do if p.rating >= D.RANKS[i].min then idx = i end end
        W.SetRankIcon(card.rank, idx)
    else
        card.rank:Hide()
    end
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

-- Switches between Chess and Battleship (the tab stays the same kind where possible).
function UI.SetGame(game)
    if not ns.db then return end
    game = game == "bs" and "bs" or "chess"
    local s = ns.db.settings
    if s.game == game and built then
        UI.ShowTab(game == "bs" and "bsplay" or "play")
        return
    end
    s.game = game
    local target = currentTab
    if SWAP[target] and ((game == "bs") == (target == "play" or target == "ladder")) then target = SWAP[target] end
    if built then
        collapsed = false
        UI.ShowTab(target, true)
    end
end

function UI.IsVisibleTab(id)
    return built and main:IsShown() and currentTab == id
end

function UI.ShowTab(id, force)
    -- a game-specific tab switches the game too
    for i = 1, #TABS do
        if TABS[i].id == id and TABS[i].game and TABS[i].game ~= Game() then ns.db.settings.game = TABS[i].game end
    end
    local changed = id ~= currentTab or force
    currentTab = id
    UI.Show()
    if changed then
        if id ~= "play" then collapsed = false end
        FitForTab()
    end
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
    local s = ns.db.settings
    s.pos, s.boardPx, s.tabSize = nil, nil, nil
    main:ClearAllPoints()
    main:SetPoint("CENTER")
    FitForTab()
    main:Show()
end

-- For the test suite.
function UI.Debug()
    return { board = PV.play.board, banner = PV.play.banner, size = size, collapsed = collapsed,
        tabsVisible = TabsVisible(), boardPx = built and BoardFor(size.w, size.h) }
end

-- Test hook: simulates the user dragging the resize grip to (w, h).
function UI.DebugResize(w, h)
    Build()
    size.w, size.h = w, h
    UI.Layout()
    SnapToBoard()
    SaveGeometry()
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
        local f = CreateFrame("Frame", "FlightpathLegendsInvite", UIParent)
        f:SetSize(400, 112)
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        W.Background(f, 0.05, 0.04, 0.04, 0.97)
        W.Tile(f, "dialogBg", 0.95)
        W.Chrome(f, "goldBorder", 5, 24)
        f.crest = f:CreateTexture(nil, "ARTWORK")
        f.crest:SetSize(52, 52)
        f.crest:SetPoint("LEFT", 12, 8)
        f.title = W.Title(f, 18, "Challenge")
        f.title:SetPoint("TOP", 26, -10)
        f.text = W.Label(f, "GameFontHighlight", "")
        f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.text:SetWidth(300)
        f.text:SetJustifyH("CENTER")
        f.accept = W.Button(f, "Accept", 110, 24, function()
            local inv = f.id and G.incoming[f.id]
            if f.id then G.AnswerInvite(f.id, true) end
            if not (inv and inv.game == "bs") then UI.ShowTab("play") end
        end)
        f.accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 20, 10)
        f.decline = W.Button(f, "Decline", 110, 24, function()
            if f.id then G.AnswerInvite(f.id, false) end
        end)
        f.decline:SetPoint("BOTTOMLEFT", f, "BOTTOM", 32, 10)
        local accum = 0
        f:SetScript("OnUpdate", function(self, elapsed)
            accum = accum + elapsed
            if accum < 0.25 then return end
            accum = 0
            local cur = self.id and G.incoming[self.id]
            if cur then
                self.title:SetText(string.format("%s challenge  |cffaaaaaa(%ds)|r", cur.game == "bs" and "Battleship" or "Chess",
                    max(0, math.ceil(cur.expires - ns.Now()))))
            end
        end)
        invitePopup = f
        UI.invitePopup = f
    end
    invitePopup.id = inv.id
    local e = P.players[inv.from]
    local faction = e and e.f
    W.SetCrest(invitePopup.crest, faction)
    local v = ns.Ledger.Get(inv.from)
    local games = v and v.games or 0
    local rating = v and v.r or inv.rating
    local color = faction and W.Hex(A.ARMIES[faction].color) or "ffffffff"
    invitePopup.text:SetText(string.format("|c%s%s|r  %s |cffaaaaaa%d%s|r\n%s, %s - %s",
        color, ns.ShortName(inv.from), P.TitleText(inv.title, rating, games), rating, v and "" or "?",
        inv.game == "bs" and "Battleship" or PV.TimeControlName(inv.base, inv.inc),
        inv.game == "bs" and "win/loss" or (inv.rated and "|cffffd100rated|r" or "casual"),
        inv.game == "bs" and ((inv.theirColor == "w") and "you fire second" or "you fire first")
            or ((inv.theirColor == "w") and "you play Black" or "you play White")))
    invitePopup:Show()
end

------------------------------------------------------------------------
-- Toasts (achievement style)
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
    W.SetIcon(toastFrame.icon, t[3] or "Interface\\Icons\\achievement_pvp_a_04")
    toastFrame.age = 0
    toastFrame:SetAlpha(0)
    toastFrame:Show()
    ns.Sound("unlock")
end

local function Toast(title, text, icon)
    if not toastFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(320, 64)
        f:SetPoint("TOP", UIParent, "TOP", 0, -240)
        f:SetFrameStrata("DIALOG")
        W.Background(f, 0.05, 0.04, 0.04, 0.96)
        W.Tile(f, "dialogBg", 0.95)
        W.Chrome(f, "goldBorder", 4, 22)
        f.iconBorder = f:CreateTexture(nil, "ARTWORK", nil, 1)
        f.iconBorder:SetSize(46, 46)
        f.iconBorder:SetPoint("LEFT", 9, 0)
        f.iconBorder:SetColorTexture(0.85, 0.68, 0.2, 1)
        f.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
        f.icon:SetSize(42, 42)
        f.icon:SetPoint("CENTER", f.iconBorder)
        f.title = W.Title(f, 13)
        f.title:SetPoint("TOPLEFT", 64, -10)
        f.text = W.Title(f, 17, nil, { 1, 1, 1 })
        f.text:SetPoint("BOTTOMLEFT", 64, 12)
        f:SetScript("OnUpdate", function(self, elapsed)
            self.age = (self.age or 0) + elapsed
            if self.age < 0.3 then
                self:SetAlpha(self.age / 0.3)
            elseif self.age > 4.5 then
                NextToast()
            elseif self.age > 3.7 then
                self:SetAlpha(max(0, (4.5 - self.age) / 0.8))
            else
                self:SetAlpha(1)
            end
        end)
        f:Hide()
        toastFrame = f
    end
    toastQueue[#toastQueue + 1] = { title, text, icon }
    if not toastFrame:IsShown() then NextToast() end
end

------------------------------------------------------------------------
-- Launcher button
------------------------------------------------------------------------
local launcher

------------------------------------------------------------------------
-- Your status: online (accepting challenges), do not disturb, looking for a battle, in battle
------------------------------------------------------------------------
local STATUS = {
    online = { text = "Online - accepting challenges", color = { 0.25, 1.00, 0.25 } },
    dnd = { text = "Do Not Disturb - challenges are declined", color = { 1.00, 0.20, 0.15 } },
    seeking = { text = "Looking for a battle", color = { 1.00, 0.82, 0.00 } },
    battle = { text = "In battle", color = { 1.00, 0.55, 0.15 } },
}

function UI.Status()
    local g = G.current
    if g and g.state == "active" and g.mode == "online" then return "battle" end
    if BS.Busy() then return "battle" end
    if G.seek then return "seeking" end
    if ns.db and ns.db.settings.dnd then return "dnd" end
    return "online"
end

function UI.StatusColor()
    return STATUS[UI.Status()].color
end

function UI.StatusText()
    local st = STATUS[UI.Status()]
    return "|c" .. W.Hex(st.color) .. st.text .. "|r"
end

-- Online / Do Not Disturb (other players see it in the Lobby within seconds).
function UI.SetDND(on)
    ns.db.settings.dnd = on and true or false
    ns.Print(on and "Do Not Disturb: challenges are declined automatically." or "Online: you are accepting challenges again.")
    G.Announce(true)
    UI.UpdateStatus()
    UI.Refresh()
end

local menu
local function BuildMenu()
    local f = CreateFrame("Frame", "FlightpathLegendsStatusMenu", UIParent)
    f:SetSize(240, 96)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    W.Background(f, 0.05, 0.04, 0.04, 0.97)
    W.Tile(f, "dialogBg", 0.95)
    W.Chrome(f, "goldBorder", 4, 20)
    table.insert(UISpecialFrames, "FlightpathLegendsStatusMenu")
    local title = W.Title(f, 15, "Your status")
    title:SetPoint("TOPLEFT", 10, -8)
    f.options = {}
    local function Option(i, key, onClick)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(224, 24)
        b:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 26)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.4, 0.12)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.15)
        b.dot = b:CreateTexture(nil, "ARTWORK")
        b.dot:SetSize(12, 12)
        b.dot:SetPoint("LEFT", 4, 0)
        b.dot:SetTexture(W.TEX .. "dot")
        local c = STATUS[key].color
        b.dot:SetVertexColor(c[1], c[2], c[3])
        b.text = W.Label(b, "GameFontHighlight", key == "online" and "Online (accept challenges)" or "Do Not Disturb")
        b.text:SetPoint("LEFT", 22, 0)
        b:SetScript("OnClick", function()
            ns.Sound("click")
            onClick()
            f:Hide()
        end)
        b.key = key
        f.options[i] = b
    end
    Option(1, "online", function() UI.SetDND(false) end)
    Option(2, "dnd", function() UI.SetDND(true) end)
    f.open = W.Button(f, "Open Checkmate", 110, 20, function()
        f:Hide()
        UI.Show()
    end)
    f.open:SetPoint("BOTTOMRIGHT", -8, 6)
    f:SetHeight(112)
    -- Close when the mouse leaves for a moment.
    local away = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() or (launcher and launcher:IsMouseOver()) then
            away = 0
        else
            away = away + elapsed
            if away > 1.5 then self:Hide() end
        end
    end)
    f:Hide()
    return f
end

function UI.ShowStatusMenu(anchor)
    menu = menu or BuildMenu()
    UI.statusMenu = menu
    local dnd = ns.db.settings.dnd
    for _, b in ipairs(menu.options) do
        if (b.key == "dnd") == (dnd and true or false) then b.sel:Show() else b.sel:Hide() end
    end
    menu:ClearAllPoints()
    if anchor then
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPRIGHT", 0, 0)
    else
        menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    menu:Show()
end

-- The coloured status dot on the launcher.
function UI.UpdateStatus()
    if not launcher then return end
    local c = STATUS[UI.Status()].color
    launcher.status:SetVertexColor(c[1], c[2], c[3])
end

function UI.UpdateLauncher()
    if not ns.db then return end
    local s = ns.db.settings
    if not s.showLauncher then
        if launcher then launcher:Hide() end
        return
    end
    if not launcher then
        local b = CreateFrame("Button", "FlightpathLegendsLauncher", UIParent)
        b:SetSize(36, 36)
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
        icon:SetTexture(W.TEX .. "logo")
        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.2)
        b.alert = b:CreateTexture(nil, "OVERLAY")
        b.alert:SetSize(12, 12)
        b.alert:SetPoint("TOPRIGHT", 2, 2)
        b.alert:SetTexture(W.TEX .. "dot")
        b.alert:SetVertexColor(1, 0.2, 0.1, 1)
        b.alert:Hide()
        -- Status dot (bottom right): online / do not disturb / looking / in battle.
        b.statusBg = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.statusBg:SetSize(15, 15)
        b.statusBg:SetPoint("BOTTOMRIGHT", 3, -3)
        b.statusBg:SetTexture(W.TEX .. "dot")
        b.statusBg:SetVertexColor(0, 0, 0, 1)
        b.status = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.status:SetSize(11, 11)
        b.status:SetPoint("CENTER", b.statusBg)
        b.status:SetTexture(W.TEX .. "dot")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                ns.Sound("click")
                UI.ShowStatusMenu(self)
            else
                UI.Toggle()
            end
        end)
        W.Tooltip(b, function(_, tip)
            tip:SetText("Flightpath Legends", 1, 0.82, 0)
            tip:AddLine(UI.StatusText())
            tip:AddLine(" ")
            tip:AddLine("Left-click to open. Right-click to set your status.", 1, 1, 1)
            tip:AddLine("Drag to move.", 0.7, 0.7, 0.7)
        end)
        if s.launcherPos then
            b:SetPoint(s.launcherPos[1], UIParent, s.launcherPos[2], s.launcherPos[3], s.launcherPos[4])
        else
            b:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
        end
        launcher = b
    end
    launcher:Show()
    UI.UpdateStatus()
end

-- Red dot on the launcher when it is our move and the window is closed.
function UI.UpdateAlert()
    if not launcher then return end
    local g = G.current
    local myTurn = g and g.state == "active" and g.myColor and g.pos.turn == g.myColor
    local s = BS.current
    if s and s.mode ~= "spectate" and ((s.phase == "battle" and s.myTurn) or (s.phase == "place" and not s.ready)) then myTurn = true end
    if myTurn and not (built and main:IsShown()) then launcher.alert:Show() else launcher.alert:Hide() end
end

------------------------------------------------------------------------
-- Event wiring
------------------------------------------------------------------------
local function BoardVisible()
    return built and main:IsShown() and currentTab == "play"
end

ns.On("CHESS_READY", function()
    local s = ns.db.settings
    s.tc = s.tc or 4
    if s.rated == nil then s.rated = true end
    s.color = s.color or "r"
    s.aiLevel = s.aiLevel or 2
    if s.autoCollapse == nil then s.autoCollapse = true end
    UI.UpdateLauncher()
end)

ns.On("CHESS_GAME_CHANGED", function()
    UI.Refresh()
    UI.UpdateAlert()
    UI.UpdateStatus()
end)

ns.On("BS_STARTED", function(s)
    if s.mode == "online" then
        ns.Print("Battleship battle started against " .. ns.ShortName(s.opp) .. ". Deploy your fleet!")
        if RaidNotice_AddMessage and RaidWarningFrame then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, "Battleship vs " .. ns.ShortName(s.opp) .. ": deploy your fleet!", { r = 1, g = 0.82, b = 0 })
        end
        if FlashClientIcon then pcall(FlashClientIcon) end
    end
    collapsed = false
    UI.SetGame("bs")
    UI.ShowTab("bsplay")
end)

ns.On("BS_CHANGED", function()
    if built and main:IsShown() and currentTab == "bsplay" then BV.Refresh() end
    UI.UpdateStatus()
    UI.UpdateAlert()
end)

ns.On("CHESS_GAME_STARTED", function(g)
    if g.mode == "online" then
        ns.Print("game started against " .. ns.ShortName(g.opp) .. ". You play " .. ((g.myColor == 1) and "White." or "Black."))
        if RaidNotice_AddMessage and RaidWarningFrame then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, "Chess game vs " .. ns.ShortName(g.opp) .. " has started!", { r = 1, g = 0.82, b = 0 })
        end
        if FlashClientIcon then pcall(FlashClientIcon) end
        UI.ShowTab("play")
    end
    local play = PV.play
    if play.banner then play.banner:Hide() end
    if play.board then play.board:ClearFx() end
    -- Fold the panels away so the board has the stage (not when just watching).
    if ns.db.settings.autoCollapse and g.mode ~= "spectate" and built then
        if currentTab == "play" then UI.SetCollapsed(true) else collapsed = true end
    end
    ns.Sound("start")
    ns.Sound("cry" .. A.ArmyFor(g.myColor or 1, g))
    if BoardVisible() and play.board then
        local mine = A.ARMIES[A.ArmyFor(g.myColor or 1, g)].name
        local foe = A.ARMIES[A.ArmyFor(-(g.myColor or 1), g)].name
        play.board:FloatText(nil, mine .. " vs " .. foe, 1, 0.82, 0, true)
    end
end)

ns.On("CHESS_GAME_MOVED", function(g, capture, check)
    if BoardVisible() and PV.play.board then
        PV.play.board:AnimateLast(g, check)
    else
        Board.MoveSounds(g, check)
    end
end)

ns.On("CHESS_GAME_OVER", function(g)
    if g.outcome == "win" then
        ns.Sound("win" .. A.ARMIES[A.ArmyFor(g.myColor or 1, g)].side)
    elseif g.outcome == "loss" then
        ns.Sound("lose")
    elseif g.result == "1/2" then
        ns.Sound("draw")
    elseif g.result == "1-0" or g.result == "0-1" then
        ns.Sound("win" .. A.ARMIES[A.ArmyFor(g.result == "1-0" and 1 or -1, g)].side)
    end
    if g.mode == "online" and g.outcome then
        local text = (g.outcome == "win" and "you won") or (g.outcome == "loss" and "you lost") or "the game was drawn"
        ns.Print(text .. " against " .. ns.ShortName(g.opp) .. " (" .. (D.REASON_TEXT[g.reason] or g.reason) .. ").")
    elseif g.mode == "online" then
        ns.Print("game ended without a result (" .. (D.REASON_TEXT[g.reason] or "aborted") .. ").")
    end
    -- Let the final move's animation land before the banner.
    ns.After(ns.db.settings.animations and 0.6 or 0, function()
        if G.current == g and BoardVisible() then PV.ShowBanner(g) end
    end)
end)

ns.On("CHESS_INVITE", function(inv)
    local who = ns.ShortName(inv.from)
    ns.Print(string.format("|cffffd100%s challenges you|r to %s (%s). Click Accept on the popup or type /fpl accept.",
        who, inv.game == "bs" and "Battleship" or ("chess, " .. PV.TimeControlName(inv.base, inv.inc)),
        inv.game == "bs" and "win/loss" or (inv.rated and "rated" or "casual")))
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, (inv.game == "bs" and "Battleship" or "Chess") .. " challenge from " .. who .. "!", { r = 1, g = 0.82, b = 0 })
    end
    if FlashClientIcon then pcall(FlashClientIcon) end
end)

ns.On("CHESS_INVITE_CHANGED", function()
    RefreshInvite()
    UI.Refresh()
    UI.UpdateStatus()
end)

ns.On("PROFILE_CHANGED", function() UI.Refresh() end)
ns.On("TOAST", Toast)

local dirty = false
local function RefreshSoon()
    if dirty then return end
    dirty = true
    ns.After(1, function()
        dirty = false
        if built and main:IsShown() and currentTab ~= "play" then UI.Refresh() end
    end)
end
ns.On("CHESS_LOBBY_CHANGED", RefreshSoon)
ns.On("CHESS_LEDGER_CHANGED", RefreshSoon)
