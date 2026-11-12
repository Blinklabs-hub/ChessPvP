-- ChessPvP: the main window - frame, tabs, resizing and responsive layout, folding the
-- side panel during battles, challenge popup, toasts, launcher and event wiring.
local _, ns = ...

local UI = {}
ns.UI = UI

local G, P, C, D, A, W, Board, PV, T = ns.Game, ns.Profile, ns.Comm, ns.Data, ns.Assets, ns.W, ns.Board, ns.PlayView, ns.Tabs
local floor, max, min = math.floor, math.max, math.min

local PAD = 12
local HEAD = 34 -- title row
local TABBAR = 30 -- tab buttons
local MIN_BOARD, MAX_BOARD = 300, 1000

local main
local built = false
local currentTab = "play"
local collapsed = false
local size = { w = 0, h = 0 } -- current window size (tracked here, not read back from frames)

local TABS = {
    { id = "play", text = "Battle", build = PV.Build, refresh = PV.Refresh },
    { id = "lobby", text = "Lobby", build = T.BuildLobby, refresh = T.RefreshLobby, layout = T.LayoutLobby },
    { id = "ladder", text = "Ladder", build = T.BuildLadder, refresh = T.RefreshLadder, layout = T.LayoutLadder },
    { id = "collection", text = "Collection", build = T.BuildCollection, refresh = T.RefreshCollection, layout = T.LayoutCollection },
    { id = "settings", text = "Settings", build = T.BuildSettings, refresh = T.RefreshSettings, layout = T.LayoutSettings },
}

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
local function TabsVisible()
    return not (currentTab == "play" and collapsed)
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

local function SetMinSize()
    local minW, minH
    if currentTab == "play" then
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
    for i = 1, #TABS do
        local tab = TABS[i]
        local page = main.pages[tab.id]
        page:ClearAllPoints()
        page:SetPoint("TOPLEFT", main, "TOPLEFT", PAD, -top)
        page:SetSize(max(10, w - PAD * 2), max(10, h - top - PAD))
        if TabsVisible() then main.tabs[tab.id]:Show() else main.tabs[tab.id]:Hide() end
    end
    if currentTab == "play" then
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
    if currentTab ~= "play" then return end
    local w, h = PlaySizeFor(BoardFor(size.w, size.h))
    ApplySize(w, h)
end

local function SaveGeometry()
    local s = ns.db.settings
    local left, top = main:GetLeft(), main:GetTop()
    if left and top then s.pos = { "TOPLEFT", "BOTTOMLEFT", left, top } end
    if currentTab == "play" then
        s.boardPx = BoardFor(size.w, size.h)
    else
        s.tabSize = { size.w, size.h }
    end
end

-- Resizes the window for the current tab and mode.
local function FitForTab()
    local s = ns.db.settings
    if currentTab == "play" then
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

    main = CreateFrame("Frame", "ChessPvPFrame", UIParent)
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
    table.insert(UISpecialFrames, "ChessPvPFrame") -- closes with Escape

    -- Title: Alliance crest - ChessPvP - Horde crest
    local crestL = main:CreateTexture(nil, "ARTWORK")
    crestL:SetSize(30, 30)
    crestL:SetPoint("TOPLEFT", PAD - 4, -3)
    W.SetCrest(crestL, "Alliance")
    local title = W.Title(main, 22, "ChessPvP")
    title:SetPoint("TOPLEFT", PAD + 28, -8)
    local crestR = main:CreateTexture(nil, "ARTWORK")
    crestR:SetSize(30, 30)
    crestR:SetPoint("LEFT", title, "RIGHT", 2, 3)
    W.SetCrest(crestR, "Horde")
    main.me = W.Label(main, "GameFontHighlightSmall", "")
    main.me:SetPoint("LEFT", crestR, "RIGHT", 10, -2)

    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    main.tabs, main.pages = {}, {}
    local x = PAD
    for i = 1, #TABS do
        local tab = TABS[i]
        local b = W.Button(main, tab.text, 104, 24, function() UI.ShowTab(tab.id) end)
        b:SetPoint("TOPLEFT", x, -HEAD)
        x = x + 108
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

    local accum = 0
    main:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum >= 0.1 then
            accum = 0
            if currentTab == "play" then PV.UpdateClocks() end
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
    main.me:SetText(string.format("%s   %s  |cffaaaaaa%d|r", ns.ShortName(ns.me),
        P.TitleText(P.MyTitleId(), p.rating, P.RatedGames()), p.rating))
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
    local changed = id ~= currentTab
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
        local f = CreateFrame("Frame", "ChessPvPInvite", UIParent)
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
        f.title = W.Title(f, 18, "Chess challenge")
        f.title:SetPoint("TOP", 26, -10)
        f.text = W.Label(f, "GameFontHighlight", "")
        f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.text:SetWidth(300)
        f.text:SetJustifyH("CENTER")
        f.accept = W.Button(f, "Accept", 110, 24, function()
            if f.id then G.AnswerInvite(f.id, true) end
            UI.ShowTab("play")
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
                self.title:SetText(string.format("Chess challenge  |cffaaaaaa(%ds)|r", max(0, math.ceil(cur.expires - ns.Now()))))
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
    invitePopup.text:SetText(string.format("|c%s%s|r  %s |cffaaaaaa%d%s|r\n%s, %s - you play %s",
        color, ns.ShortName(inv.from), P.TitleText(inv.title, rating, games), rating, v and "" or "?",
        PV.TimeControlName(inv.base, inv.inc), inv.rated and "|cffffd100rated|r" or "casual",
        (inv.theirColor == "w") and "Black" or "White"))
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

function UI.UpdateLauncher()
    if not ns.db then return end
    local s = ns.db.settings
    if not s.showLauncher then
        if launcher then launcher:Hide() end
        return
    end
    if not launcher then
        local b = CreateFrame("Button", "ChessPvPLauncher", UIParent)
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
        b:SetScript("OnClick", function() UI.Toggle() end)
        W.Tooltip(b, function(_, tip)
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

-- Red dot on the launcher when it is our move and the window is closed.
function UI.UpdateAlert()
    if not launcher then return end
    local g = G.current
    local myTurn = g and g.state == "active" and g.myColor and g.pos.turn == g.myColor
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
    ns.Sound("cry" .. A.MyFaction())
    if BoardVisible() and play.board then
        local army = A.ArmyFor(g.myColor or 1, g)
        local foe = army == "Horde" and "Alliance" or "Horde"
        play.board:FloatText(nil, army .. " vs " .. foe, 1, 0.82, 0, true)
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
        ns.Sound("win" .. A.MyFaction())
    elseif g.outcome == "loss" then
        ns.Sound("lose")
    elseif g.result == "1/2" then
        ns.Sound("draw")
    elseif g.result == "1-0" or g.result == "0-1" then
        ns.Sound("win" .. A.ArmyFor(g.result == "1-0" and 1 or -1, g))
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
    ns.Print(string.format("|cffffd100%s challenges you|r to %s (%s). Click Accept on the popup or type /chess accept.",
        who, PV.TimeControlName(inv.base, inv.inc), inv.rated and "rated" or "casual"))
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, "Chess challenge from " .. who .. "!", { r = 1, g = 0.82, b = 0 })
    end
    if FlashClientIcon then pcall(FlashClientIcon) end
end)

ns.On("CHESS_INVITE_CHANGED", function()
    RefreshInvite()
    UI.Refresh()
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
