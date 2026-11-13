-- Flightpath Legends - the game window: just the game being played (board, players, turn banner,
-- a side panel that folds away), resizing and responsive layout. Everything else (finding a game,
-- browsing players, leaderboards, settings) lives in the finder (UI_Finder.lua).
-- Also: the How to play window, challenge popup, toasts, launcher and event wiring.
local _, ns = ...

local UI = {}
ns.UI = UI

local G, P, C, D, A, W, Board, PV, T = ns.Game, ns.Profile, ns.Comm, ns.Data, ns.Assets, ns.W, ns.Board, ns.PlayView, ns.Tabs
local BV, BS = ns.BattleView, ns.Battleship
local FV, FR = ns.FourView, ns.FourRow
local VV, VB = ns.VaultView, ns.Vault
local HV, HA = ns.ArmyView, ns.Army
local FD = ns.Finder
local floor, max, min = math.floor, math.max, math.min

local PAD = 12
local HEAD = 40 -- the game window's title bar
local MIN_BOARD, MAX_BOARD = 300, 1000

local main
local built = false
local currentTab = "play"
local collapsed = false
local size = { w = 0, h = 0 } -- current window size (tracked here, not read back from frames)

-- The game pages: the game window shows one of them.
local TABS = {
    { id = "play", game = "chess", text = "Battle", build = PV.Build, refresh = PV.Refresh },
    { id = "bsplay", game = "bs", text = "Battle", build = BV.Build, refresh = BV.Refresh },
    { id = "c4play", game = "c4", text = "Game", build = FV.Build, refresh = FV.Refresh },
    { id = "vbplay", game = "vb", text = "Game", build = VV.Build, refresh = VV.Refresh },
    { id = "haplay", game = "ha", text = "Battle", build = HV.Build, refresh = HV.Refresh },
}
-- Every page of every game: play pages are in the game window, the rest in the finder.
local KIND = {
    play = "play", bsplay = "play", c4play = "play", vbplay = "play", haplay = "play",
    lobby = "lobby", bslobby = "lobby", c4lobby = "lobby", vblobby = "lobby", halobby = "lobby",
    live = "live", bslive = "live", c4live = "live", vblive = "live", halive = "live",
    ladder = "board", admirals = "board", c4board = "board", vbboard = "board", haboard = "board",
    collection = "coll", bscollection = "coll", c4collection = "coll", vbcollection = "coll", hacollection = "coll",
    chesshub = "hub", bshub = "hub", c4hub = "hub", vbhub = "hub", hahub = "hub",
}
local TAB_FOR = {
    chess = { play = "play", lobby = "lobby", live = "live", board = "ladder", coll = "collection" },
    bs = { play = "bsplay", lobby = "bslobby", live = "bslive", board = "admirals", coll = "bscollection" },
    c4 = { play = "c4play", lobby = "c4lobby", live = "c4live", board = "c4board", coll = "c4collection" },
    vb = { play = "vbplay", lobby = "vblobby", live = "vblive", board = "vbboard", coll = "vbcollection" },
    ha = { play = "haplay", lobby = "halobby", live = "halive", board = "haboard", coll = "hacollection" },
}
for key, t in pairs(TAB_FOR) do t.hub = key .. "hub" end
UI.KIND, UI.TAB_FOR = KIND, TAB_FOR
local TAB_BY_ID = {}
for _, t in ipairs(TABS) do TAB_BY_ID[t.id] = t end

local function Game()
    local g = ns.db and ns.db.settings.game
    if g and D.GAMES[g] then return g end
    return "chess"
end
UI.Game = Game

local function IsPlayTab(id) return KIND[id] == "play" end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
local function PanelsShown()
    return not collapsed
end

local function ContentTop()
    return HEAD + 4
end

local function ShowSide()
    return not collapsed
end

-- Window size that exactly fits a board of boardPx in the chess page.
local function PlaySizeFor(boardPx)
    local w = PAD + boardPx + PV.GAP + PV.HANDLE + PAD
    if ShowSide() then w = w + PV.GAP + PV.SIDE end
    local h = ContentTop() + PV.STRIP * 2 + PV.GAP * 2 + boardPx + PAD
    if ShowSide() then
        -- The side panel needs a minimum height.
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

-- Pages of the other games: each view has SizeFor(cell, side) and CellFor(w, h, side);
-- key is where the chosen square size is saved.
local PAGES = {
    bsplay = { view = BV, key = "bsCell", def = 34, min = 20 },
    c4play = { view = FV, key = "c4Cell", def = 56, min = 30 },
    vbplay = { view = VV, key = "vbCell", def = 36, min = 24 },
    haplay = { view = HV, key = "haCell", def = 52, min = 30 },
}
local function PageSizeFor(pg, cellPx)
    local w, h = pg.view.SizeFor(cellPx, ShowSide())
    return w + PAD * 2, h + ContentTop() + PAD
end
local function PageCellFor(pg, w, h)
    return pg.view.CellFor(w - PAD * 2, h - ContentTop() - PAD, ShowSide())
end

local function SetMinSize()
    local minW, minH
    local pg = PAGES[currentTab]
    if pg then
        minW, minH = PageSizeFor(pg, pg.min)
    else
        minW, minH = PlaySizeFor(MIN_BOARD)
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
    for i = 1, #TABS do
        local page = main.pages[TABS[i].id]
        page:ClearAllPoints()
        page:SetPoint("TOPLEFT", main, "TOPLEFT", PAD, -top)
        page:SetSize(max(10, w - PAD * 2), max(10, h - top - PAD))
    end
    local pg = PAGES[currentTab]
    if pg then
        pg.view.Layout(PageCellFor(pg, w, h), ShowSide())
    else
        PV.Layout(BoardFor(w, h), ShowSide())
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

-- The window hugs the board exactly.
local function SnapToBoard()
    local pg = PAGES[currentTab]
    if pg then
        local w, h = PageSizeFor(pg, PageCellFor(pg, size.w, size.h))
        ApplySize(w, h)
        return
    end
    local w, h = PlaySizeFor(BoardFor(size.w, size.h))
    ApplySize(w, h)
end

local function SaveGeometry()
    local s = ns.db.settings
    local left, top = main:GetLeft(), main:GetTop()
    if left and top then s.pos = { "TOPLEFT", "BOTTOMLEFT", left, top } end
    local pg = PAGES[currentTab]
    if pg then
        s[pg.key] = PageCellFor(pg, size.w, size.h)
    else
        s.boardPx = BoardFor(size.w, size.h)
    end
end

-- Resizes the window for the current game and mode.
local function FitForTab()
    local s = ns.db.settings
    local pg = PAGES[currentTab]
    if pg then
        local w, h = PageSizeFor(pg, s[pg.key] or pg.def)
        ApplySize(w, h)
    else
        local w, h = PlaySizeFor(s.boardPx or 448)
        ApplySize(w, h)
    end
end

function UI.IsCollapsed()
    return collapsed
end

-- Folds the side panel away (or brings it back); the board keeps its size.
function UI.SetCollapsed(v)
    v = v and true or false
    if v == collapsed then return end
    collapsed = v
    if not built then return end
    FitForTab()
    UI.Refresh()
end

------------------------------------------------------------------------
-- The game window
------------------------------------------------------------------------
local function HeaderButton(parent, icon, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    W.SetIcon(b.icon, icon)
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetPoint("CENTER")
    b.ring:SetSize(34, 34)
    b.ring:SetTexture(W.TEX .. "token_ring")
    b.ring:SetVertexColor(0.85, 0.7, 0.3)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.5, 0.2)
    b:SetScript("OnClick", function() ns.Sound("click"); onClick() end)
    W.Tooltip(b, function(_, t) t:SetText(tip, 1, 0.82, 0) end)
    return b
end

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

    -- title bar: the game, and who it is against
    local bar = main:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT", 4, -4)
    bar:SetPoint("TOPRIGHT", -4, -4)
    bar:SetHeight(HEAD - 8)
    bar:SetColorTexture(0.16, 0.11, 0.05, 0.9)
    local rule = main:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.6, 0.48, 0.2, 0.8)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 4, -(HEAD - 4))
    rule:SetPoint("TOPRIGHT", -4, -(HEAD - 4))
    main.gameIcon = main:CreateTexture(nil, "ARTWORK")
    main.gameIcon:SetSize(24, 24)
    main.gameIcon:SetPoint("TOPLEFT", PAD, -8)
    main.title = W.Title(main, 18)
    main.title:SetPoint("LEFT", main.gameIcon, "RIGHT", 8, 0)
    main.title:SetWordWrap(false)
    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    main.finderButton = HeaderButton(main, "Interface\\Icons\\inv_misc_eye_01", "Find a Game, Browse, Legends", function()
        if FD.IsShown() then FD.Hide() else FD.Show() end
    end)
    main.finderButton:SetPoint("TOPRIGHT", -40, -7)
    main.helpButton = HeaderButton(main, "Interface\\Icons\\inv_misc_questionmark", "How to play", function()
        UI.ShowHelp(TAB_BY_ID[currentTab] and TAB_BY_ID[currentTab].game or Game())
    end)
    main.helpButton:SetPoint("RIGHT", main.finderButton, "LEFT", -12, 0)
    -- a long title (game and opponent) stops short of the buttons
    main.title:SetPoint("RIGHT", main.helpButton, "LEFT", -12, 0)

    main.pages = {}
    for i = 1, #TABS do
        local tab = TABS[i]
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
            -- the other games' timers tick every 0.3s
            local pg = PAGES[currentTab]
            local m = pg and G.Module(TAB_BY_ID[currentTab].game)
            if m and m.current and m.current.phase ~= "over" then
                bsAccum = (bsAccum or 0) + 1
                if bsAccum >= 3 then bsAccum = 0; pg.view.Refresh() end
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

-- Who the game on a page is against (for the title bar).
local function Opponent(game)
    if game == "chess" then
        local g = G.current
        if not g then return nil end
        if g.mode == "spectate" then return ns.ShortName(g.white or "?") .. " vs " .. ns.ShortName(g.black or "?") end
        return "vs " .. (g.mode == "ai" and ("Computer (" .. ns.AI.LEVELS[g.aiLevel or 1].name .. ")") or ns.ShortName(g.opp or "?"))
    end
    local m = G.Module(game)
    local s = m and m.current
    if not s then return nil end
    if s.mode == "spectate" then return "watching " .. ns.ShortName(s.host or "?") .. " vs " .. ns.ShortName(s.guest or "?") end
    return "vs " .. (s.mode == "ai" and s.oppName or ns.ShortName(s.opp or "?"))
end

function UI.Refresh()
    if FD.IsShown() then FD.Refresh() end
    if not built or not main:IsShown() or not P.me then return end
    local tabDef = TAB_BY_ID[currentTab]
    local game = tabDef and tabDef.game or Game()
    W.SetIcon(main.gameIcon, D.GameIcon(game))
    local opp = Opponent(game)
    main.title:SetText(D.GAMES[game].name .. (opp and ("   |cffaaaaaa" .. opp .. "|r") or ""))
    for i = 1, #TABS do
        local tab = TABS[i]
        if tab.id == currentTab then
            main.pages[tab.id]:Show()
            tab.refresh()
        else
            main.pages[tab.id]:Hide()
        end
    end
end

-- Chooses the game the finder shows (Browse and Legends switch to the same page of it).
function UI.SetGame(game)
    if not ns.db then return end
    if not (game and D.GAMES[game]) then game = "chess" end
    ns.db.settings.game = game
    if FD.IsShown() then
        local kind = KIND[FD.Current()]
        if kind and kind ~= "play" then FD.Show(TAB_FOR[game][kind]) else FD.Refresh() end
    end
end

-- Opens the finder on a game's Find page (after a game, "New Game" comes here).
function UI.NewGame(game)
    if game then ns.db.settings.game = game end
    FD.Show(TAB_FOR[Game()].hub)
end

function UI.OpenFinder()
    FD.Show()
end

------------------------------------------------------------------------
-- The tavern tip jar: a thank-you note and the donation link (addons cannot open web pages,
-- so the link is shown selected, ready to copy).
------------------------------------------------------------------------
UI.DONATE_URL = "https://buymeacoffee.com/zeppil"
local donateFrame
function UI.ShowDonate()
    if not donateFrame then
        local f = CreateFrame("Frame", "FlightpathLegendsDonate", UIParent)
        f:SetSize(440, 360)
        f:SetPoint("CENTER", 0, 40)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        W.Background(f, 0.05, 0.04, 0.04, 0.97)
        W.Tile(f, "dialogBg", 0.95)
        W.Chrome(f, "goldBorder", 5, 24)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(44, 44)
        f.icon:SetPoint("TOPLEFT", 18, -16)
        W.SetIcon(f.icon, "Interface\\Icons\\inv_drink_04")
        f.title = W.Title(f, 22, "The Tavern Tip Jar")
        f.title:SetPoint("LEFT", f.icon, "RIGHT", 12, 4)
        f.sub = W.Label(f, "GameFontDisableSmall", "From one Azeroth nerd to another")
        f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
        f.text = W.Label(f, "GameFontHighlight",
            "Well met, traveller!\n\n"
            .. "I built Flightpath Legends one gryphon ride at a time - somewhere between corpse runs, "
            .. "waiting for a tank, and staring at the same patch of Barrens for the hundredth time.\n\n"
            .. "It is free and it will stay free. Every title and feat is earned, never bought.\n\n"
            .. "But if it has saved you from one more boring flight, you can toss a coin in the jar. "
            .. "It keeps the coffee brewing and the next game coming.\n\n"
            .. "|cffffd100No gold sellers were harmed in the making of this addon.|r")
        f.text:SetPoint("TOPLEFT", 20, -74)
        f.text:SetWidth(400)
        f.text:SetJustifyV("TOP")
        f.text:SetSpacing(2)
        local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        box:SetSize(300, 24)
        box:SetPoint("BOTTOMLEFT", 26, 54)
        box:SetAutoFocus(false)
        box:SetText(UI.DONATE_URL)
        -- the link cannot be edited: typing puts it back
        box:SetScript("OnTextChanged", function(self, user)
            if user then self:SetText(UI.DONATE_URL); self:HighlightText() end
        end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.box = box
        f.hint = W.Label(f, "GameFontDisableSmall", "Press Ctrl+C to copy, then paste it into your browser.")
        f.hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -4)
        local copy = W.Button(f, "Select", 80, 24, function() box:SetFocus(); box:HighlightText() end)
        copy:SetPoint("LEFT", box, "RIGHT", 8, 0)
        f.thanks = W.Label(f, "GameFontNormal", "For the Horde! For the Alliance! For the coffee!")
        f.thanks:SetPoint("BOTTOM", 0, 14)
        table.insert(UISpecialFrames, "FlightpathLegendsDonate")
        donateFrame = f
        UI.donateFrame = f
    end
    donateFrame:Show()
    donateFrame.box:SetText(UI.DONATE_URL)
    donateFrame.box:SetFocus()
    donateFrame.box:HighlightText()
end

function UI.IsVisibleTab(id)
    if IsPlayTab(id) then return built and main:IsShown() and currentTab == id end
    return FD.IsVisible(id)
end

-- Whether a game of any kind is in progress (for us: playing or watching).
local function AnyGameActive()
    local g = G.current
    if g and g.state == "active" then return "play" end
    for _, key in ipairs(D.GAME_ORDER) do
        local m = G.Module(key)
        if m and m.Active() then return TAB_FOR[key].play end
    end
    return nil
end

-- Shows a page: a game page opens the game window, anything else the finder.
function UI.ShowTab(id, force)
    if not ns.db or not P.me then return end
    if not IsPlayTab(id) then
        FD.Show(id)
        return
    end
    local tab = TAB_BY_ID[id]
    if tab and tab.game then ns.db.settings.game = tab.game end
    Build()
    local changed = id ~= currentTab or force
    currentTab = id
    if not main:IsShown() then main:Show() end
    -- no game running: the side panel comes back
    if collapsed and not AnyGameActive() then collapsed = false; changed = true end
    if changed then FitForTab() end
    UI.Refresh()
end

-- Opens the addon: the game in progress if there is one, otherwise the finder.
function UI.Show()
    if not ns.db or not P.me then return end
    local active = AnyGameActive()
    if active then UI.ShowTab(active) else FD.Show() end
end

function UI.Toggle()
    if not ns.db or not P.me then return end
    local active = AnyGameActive()
    if active then
        Build()
        if main:IsShown() then main:Hide() else UI.ShowTab(active) end
    else
        FD.Toggle()
    end
end

function UI.ResetPosition()
    if not ns.db then return end
    Build()
    local s = ns.db.settings
    s.pos, s.boardPx, s.tabSize, s.finderPos, s.finderSize = nil, nil, nil, nil, nil
    main:ClearAllPoints()
    main:SetPoint("CENTER")
    FitForTab()
    if FD.frame then
        FD.frame:ClearAllPoints()
        FD.frame:SetPoint("CENTER", -60, 20)
    end
    UI.Show()
end

-- For the test suite.
function UI.Debug()
    return { board = PV.play.board, banner = PV.play.banner, size = size, collapsed = collapsed,
        tabsVisible = PanelsShown(), boardPx = built and BoardFor(size.w, size.h) }
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
-- How to play
------------------------------------------------------------------------
-- The How to play window (one per screen, shows the chosen game's rules).
local helpFrame
function UI.ShowHelp(game)
    game = (game and D.GAMES[game]) and game or Game()
    if not helpFrame then
        local f = CreateFrame("Frame", "FlightpathLegendsHelp", UIParent)
        f:SetSize(470, 520)
        f:SetPoint("CENTER", 0, 20)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        W.Background(f, 0.05, 0.04, 0.04, 0.97)
        W.Tile(f, "dialogBg", 0.95)
        W.Chrome(f, "goldBorder", 5, 24)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(36, 36)
        f.icon:SetPoint("TOPLEFT", 16, -14)
        f.title = W.Title(f, 22)
        f.title:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local sf = CreateFrame("ScrollFrame", "FlightpathLegendsHelpScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 18, -62)
        sf:SetPoint("BOTTOMRIGHT", -34, 16)
        local child = CreateFrame("Frame", nil, sf)
        child:SetSize(410, 10)
        sf:SetScrollChild(child)
        f.text = W.Label(child, "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 0, 0)
        f.text:SetWidth(408)
        f.text:SetJustifyV("TOP")
        f.text:SetSpacing(3)
        f.child = child
        table.insert(UISpecialFrames, "FlightpathLegendsHelp")
        helpFrame = f
        UI.helpFrame = f
    end
    W.SetIcon(helpFrame.icon, D.GameIcon(game))
    helpFrame.title:SetText("How to play: " .. D.GAMES[game].name)
    helpFrame.text:SetText(D.GAMES[game].rules or "")
    helpFrame.game = game
    local h = helpFrame.text.GetStringHeight and helpFrame.text:GetStringHeight()
    helpFrame.child:SetHeight(max(10, (h or 400) + 10))
    helpFrame:Show()
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
            if not (inv and inv.game ~= "chess") then UI.ShowTab("play") end
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
                self.title:SetText(string.format("%s challenge  |cffaaaaaa(%ds)|r", D.GAMES[cur.game or "chess"].name,
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
        inv.game ~= "chess" and D.GAMES[inv.game].name or PV.TimeControlName(inv.base, inv.inc),
        (inv.game ~= "chess" and (D.GAMES[inv.game].draws and "win/loss/draw" or "win/loss")) or (inv.rated and "|cffffd100rated|r" or "casual"),
        (inv.game == "bs" and ((inv.theirColor == "w") and "you fire second" or "you fire first"))
            or (inv.game == "c4" and ((inv.theirColor == "w") and "you drop second (silver)" or "you drop first (gold)"))
            or (inv.game == "vb" and "you both guess at once")
            or (inv.game == "ha" and ((inv.theirColor == "w") and "you move second" or "you move first"))
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
    if G.BusyModule() then return "battle" end
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
    f.open = W.Button(f, "Open Flightpath Legends", 170, 20, function()
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
        b:SetSize(31, 31)
        b:SetScale(1.3)
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
        -- the same layout as the game's own minimap buttons
        local back = b:CreateTexture(nil, "BACKGROUND")
        back:SetSize(20, 20)
        back:SetPoint("TOPLEFT", 7, -5)
        back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", 7, -6)
        W.SetIcon(icon, "Interface\\Icons\\ability_mount_gryphon_01")
        if b.CreateMaskTexture and icon.AddMaskTexture then
            local m = b:CreateMaskTexture()
            if m then
                m:SetAllPoints(icon)
                m:SetTexture(A.PortraitMask(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                icon:AddMaskTexture(m)
            end
        end
        local border = b:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        b.alert = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.alert:SetSize(9, 9)
        b.alert:SetPoint("TOPRIGHT", 1, 1)
        b.alert:SetTexture(W.TEX .. "dot")
        b.alert:SetVertexColor(1, 0.2, 0.1, 1)
        b.alert:Hide()
        -- Status dot (bottom right): online / do not disturb / looking / in battle.
        b.statusBg = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.statusBg:SetSize(10, 10)
        b.statusBg:SetPoint("BOTTOMRIGHT", 0, 1)
        b.statusBg:SetTexture(W.TEX .. "dot")
        b.statusBg:SetVertexColor(0, 0, 0, 1)
        b.status = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.status:SetSize(7, 7)
        b.status:SetPoint("CENTER", b.statusBg)
        b.status:SetTexture(W.TEX .. "dot")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
            if GameTooltip then GameTooltip:Hide() end
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
        end, "ANCHOR_LEFT")
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
    if FR.MyTurn() then myTurn = true end
    local v = VB.current
    if VB.CanGuess() or (v and v.phase == "set" and not v.ready and v.mode ~= "spectate") then myTurn = true end
    local h = HA.current
    if HA.MyTurn() or (h and h.phase == "setup" and not h.ready and h.mode ~= "spectate") then myTurn = true end
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
    ns.db.settings.game = "bs"
    UI.ShowTab("bsplay")
    FD.Hide()
end)

ns.On("BS_CHANGED", function()
    if built and main:IsShown() and currentTab == "bsplay" then BV.Refresh() end
    UI.UpdateStatus()
    UI.UpdateAlert()
end)

ns.On("FR_STARTED", function(s)
    if s.mode == "online" then
        ns.Print("Four in a Row game started against " .. ns.ShortName(s.opp) .. ". You drop " .. (s.iFirst and "first (gold)." or "second (silver)."))
        if RaidNotice_AddMessage and RaidWarningFrame then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, "Four in a Row vs " .. ns.ShortName(s.opp) .. " has started!", { r = 1, g = 0.82, b = 0 })
        end
        if FlashClientIcon then pcall(FlashClientIcon) end
    end
    collapsed = false
    ns.db.settings.game = "c4"
    UI.ShowTab("c4play")
    FD.Hide()
    if ns.db.settings.autoCollapse and s.mode ~= "spectate" and built then UI.SetCollapsed(true) end
end)

ns.On("FR_CHANGED", function()
    if built and main:IsShown() and currentTab == "c4play" then FV.Refresh() end
    UI.UpdateStatus()
    UI.UpdateAlert()
end)

ns.On("VB_STARTED", function(s)
    if s.mode == "online" then
        ns.Print("Vault Breaker game started against " .. ns.ShortName(s.opp) .. ". Lock your vault!")
        if RaidNotice_AddMessage and RaidWarningFrame then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, "Vault Breaker vs " .. ns.ShortName(s.opp) .. ": lock your vault!", { r = 1, g = 0.82, b = 0 })
        end
        if FlashClientIcon then pcall(FlashClientIcon) end
    end
    collapsed = false
    ns.db.settings.game = "vb"
    UI.ShowTab("vbplay")
    FD.Hide()
end)

ns.On("VB_CHANGED", function()
    if built and main:IsShown() and currentTab == "vbplay" then VV.Refresh() end
    UI.UpdateStatus()
    UI.UpdateAlert()
end)

ns.On("HA_STARTED", function(s)
    if s.mode == "online" then
        ns.Print("Hidden Army battle started against " .. ns.ShortName(s.opp) .. ". Deploy your army!")
        if RaidNotice_AddMessage and RaidWarningFrame then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, "Hidden Army vs " .. ns.ShortName(s.opp) .. ": deploy your army!", { r = 1, g = 0.82, b = 0 })
        end
        if FlashClientIcon then pcall(FlashClientIcon) end
    end
    collapsed = false
    ns.db.settings.game = "ha"
    UI.ShowTab("haplay")
    FD.Hide()
end)

ns.On("HA_CHANGED", function()
    if built and main:IsShown() and currentTab == "haplay" then HV.Refresh() end
    UI.UpdateStatus()
    UI.UpdateAlert()
end)

ns.On("HA_OVER", function(s)
    if s.mode == "online" and s.outcome and s.outcome ~= "abort" then
        local text = (s.outcome == "win" and "you won") or (s.outcome == "loss" and "you lost") or
            (s.outcome == "draw" and "the battle was drawn") or "the battle is disputed"
        ns.Print(text .. " at Hidden Army against " .. ns.ShortName(s.opp) .. ".")
    end
end)

ns.On("VB_OVER", function(s)
    if s.mode == "online" and s.outcome and s.outcome ~= "abort" then
        local text = (s.outcome == "win" and "you won") or (s.outcome == "loss" and "you lost") or
            (s.outcome == "draw" and "the game was drawn") or "the game is disputed"
        ns.Print(text .. " at Vault Breaker against " .. ns.ShortName(s.opp) .. ".")
    end
end)

ns.On("FR_OVER", function(s)
    if s.mode == "online" and s.outcome then
        local text = (s.outcome == "win" and "you won") or (s.outcome == "loss" and "you lost") or "the game was drawn"
        ns.Print(text .. " at Four in a Row against " .. ns.ShortName(s.opp) .. ".")
    end
    if built and collapsed and currentTab == "c4play" then UI.SetCollapsed(false) end
end)

ns.On("CHESS_GAME_STARTED", function(g)
    if g.mode == "online" then
        ns.Print("game started against " .. ns.ShortName(g.opp) .. ". You play " .. ((g.myColor == 1) and "White." or "Black."))
        if RaidNotice_AddMessage and RaidWarningFrame then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, "Chess game vs " .. ns.ShortName(g.opp) .. " has started!", { r = 1, g = 0.82, b = 0 })
        end
        if FlashClientIcon then pcall(FlashClientIcon) end
    end
    UI.ShowTab("play")
    FD.Hide()
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

-- A bell when it becomes our move in an online game (and a flash when the window is closed).
ns.On("CHESS_GAME_MOVED", function(g)
    if g.mode == "online" and g.state == "active" and g.pos.turn == g.myColor then
        ns.After(0.5, function()
            if G.current == g and g.state == "active" and g.pos.turn == g.myColor then
                A.Play("bsTurn")
                if not (built and main:IsShown()) and FlashClientIcon then pcall(FlashClientIcon) end
            end
        end)
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
        who, inv.game ~= "chess" and D.GAMES[inv.game].name or ("chess, " .. PV.TimeControlName(inv.base, inv.inc)),
        (inv.game ~= "chess" and (D.GAMES[inv.game].draws and "win/loss/draw" or "win/loss")) or (inv.rated and "rated" or "casual")))
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, D.GAMES[inv.game or "chess"].name .. " challenge from " .. who .. "!", { r = 1, g = 0.82, b = 0 })
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
        if FD.IsShown() then FD.Refresh() end
    end)
end
ns.On("CHESS_LOBBY_CHANGED", RefreshSoon)
ns.On("CHESS_LEDGER_CHANGED", RefreshSoon)
