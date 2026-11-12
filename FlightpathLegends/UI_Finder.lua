-- Flightpath Legends - the finder: a Group Finder style window for everything except playing.
-- Side tabs: Find a Game (pick the games you would play, queue, challenge, practise),
-- Browse (each game's players and live games), Legends (leaderboards and collections), Settings.
local _, ns = ...

local FD = {}
ns.Finder = FD

local G, P, C, D, A, W, L, T = ns.Game, ns.Profile, ns.Comm, ns.Data, ns.Assets, ns.W, ns.Ledger, ns.Tabs
local floor, max, min = math.floor, math.max, math.min

local FW, FH = 700, 640 -- default size
local TOP = 40 -- title bar
local PADF = 14

local frame
local built = false
local current = "games" -- the page id being shown
local section = "find" -- find | browse | legends | settings
local pages = {} -- [id] = { frame, refresh, layout, built }
FD.pages = pages

local function UI() return ns.UI end
local function Game() return UI().Game() end

------------------------------------------------------------------------
-- Which page belongs to which side tab
------------------------------------------------------------------------
local function SectionOf(id)
    if id == "games" then return "find" end
    if id == "settings" then return "settings" end
    local kind = UI().KIND[id]
    if kind == "lobby" or kind == "live" then return "browse" end
    if kind == "board" or kind == "coll" then return "legends" end
    return nil
end
FD.SectionOf = SectionOf

local function GameOf(id)
    for key, t in pairs(UI().TAB_FOR) do
        for _, pid in pairs(t) do if pid == id then return key end end
    end
end

-- The builders of every finder page.
local function Defs()
    local defs = {
        games = { build = function(p) FD.BuildFind(p) end, refresh = function() FD.RefreshFind() end, layout = function(w, h) FD.LayoutFind(w, h) end },
        settings = { build = T.BuildSettings, refresh = T.RefreshSettings, layout = T.LayoutSettings },
        ladder = { build = T.BuildLadder, refresh = T.RefreshLadder, layout = T.LayoutLadder },
        admirals = { build = T.BuildAdmirals, refresh = T.RefreshAdmirals, layout = T.LayoutAdmirals },
    }
    for _, key in ipairs(D.GAME_ORDER) do
        local tf = UI().TAB_FOR[key]
        local lo, li, co = T.lobbies[key], T.lives[key], T.collections[key]
        defs[tf.lobby] = { build = lo.Build, refresh = lo.Refresh, layout = lo.Layout }
        defs[tf.live] = { build = li.Build, refresh = li.Refresh, layout = li.Layout }
        defs[tf.coll] = { build = co.Build, refresh = co.Refresh, layout = co.Layout }
        if T.boards[key] then
            local bo = T.boards[key]
            defs[tf.board] = { build = bo.Build, refresh = bo.Refresh, layout = bo.Layout }
        end
    end
    return defs
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------
local function SideTab(parent, icon, tip, onClick)
    local b = CreateFrame("CheckButton", nil, parent)
    b:SetSize(36, 36)
    local tabArt = "Interface\\SpellBook\\SpellBook-SkillLineTab"
    if A.HasFile(tabArt) then
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(tabArt)
        bg:SetSize(64, 64)
        bg:SetPoint("TOPLEFT", -3, 11)
    else
        W.Background(b, 0.1, 0.08, 0.05, 1, { 0.6, 0.48, 0.2, 1 })
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    W.SetIcon(b.icon, icon)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetAllPoints()
    b.check:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.check:SetBlendMode("ADD")
    b.check:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    b:SetScript("OnClick", function() ns.Sound("click"); onClick() end)
    W.Tooltip(b, function(_, t) t:SetText(tip, 1, 0.82, 0) end)
    function b:SetOn(on) if on then self.check:Show() else self.check:Hide() end; self:SetChecked(on) end
    return b
end

local function Build()
    if built then return end
    built = true
    local s = ns.db.settings
    frame = CreateFrame("Frame", "FlightpathLegendsFinder", UIParent)
    FD.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then s.finderPos = { l, t } end
    end)
    local fs = s.finderSize or { FW, FH }
    frame:SetSize(fs[1], fs[2])
    frame.w, frame.h = fs[1], fs[2]
    if s.finderPos then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.finderPos[1], s.finderPos[2])
    else
        frame:SetPoint("CENTER", -60, 20)
    end
    if frame.SetResizeBounds then pcall(frame.SetResizeBounds, frame, 600, 560, 1300, 1000)
    elseif frame.SetMinResize then pcall(frame.SetMinResize, frame, 600, 560) end
    W.Background(frame, 0.05, 0.04, 0.04, 0.97)
    W.Tile(frame, "dialogBg", 0.95)
    W.Chrome(frame, "goldBorder", 6, 28)
    table.insert(UISpecialFrames, "FlightpathLegendsFinder")

    -- title bar
    local bar = frame:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT", 4, -4)
    bar:SetPoint("TOPRIGHT", -4, -4)
    bar:SetHeight(TOP - 10)
    bar:SetColorTexture(0.16, 0.11, 0.05, 0.9)
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.6, 0.48, 0.2, 0.8)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 4, -(TOP - 6))
    rule:SetPoint("TOPRIGHT", -4, -(TOP - 6))
    frame.title = W.Title(frame, 17, "Flightpath Legends")
    frame.title:SetPoint("TOP", 0, -11)
    frame.title:SetJustifyH("CENTER")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- the round emblem over the top-left corner
    local em = CreateFrame("Frame", nil, frame)
    em:SetSize(66, 66)
    em:SetPoint("TOPLEFT", -16, 16)
    em:SetFrameLevel(frame:GetFrameLevel() + 20)
    em.bg = em:CreateTexture(nil, "BACKGROUND")
    em.bg:SetTexture(W.TEX .. "dot")
    em.bg:SetPoint("CENTER")
    em.bg:SetSize(54, 54)
    em.bg:SetVertexColor(0, 0, 0, 1)
    em.logo = em:CreateTexture(nil, "ARTWORK")
    em.logo:SetPoint("CENTER")
    em.logo:SetSize(50, 50)
    em.logo:SetTexture(W.TEX .. "logo")
    if em.CreateMaskTexture and em.logo.AddMaskTexture then
        local m = em:CreateMaskTexture()
        if m then
            m:SetAllPoints(em.logo)
            m:SetTexture(A.PortraitMask(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            em.logo:AddMaskTexture(m)
        end
    end
    em.ring = em:CreateTexture(nil, "OVERLAY")
    em.ring:SetAllPoints()
    if A.HasFile("Interface\\Common\\GoldRing") then
        em.ring:SetTexture("Interface\\Common\\GoldRing")
    else
        em.ring:SetTexture(W.TEX .. "token_ring")
        em.ring:SetVertexColor(1, 0.8, 0.3)
    end

    -- side tabs (outside the right edge)
    frame.tabs = {}
    local defs = {
        { id = "find", icon = "Interface\\Icons\\inv_misc_eye_01", tip = "Find a Game", page = function() return "games" end },
        { id = "browse", icon = "Interface\\Icons\\inv_misc_spyglass_02", tip = "Browse players and live games",
            page = function() return FD.browseKind == "live" and UI().TAB_FOR[Game()].live or UI().TAB_FOR[Game()].lobby end },
        { id = "legends", icon = "Interface\\Icons\\inv_misc_trophy_argent", tip = "Legends: leaderboards, titles and feats",
            page = function() return FD.legendsKind == "coll" and UI().TAB_FOR[Game()].coll or UI().TAB_FOR[Game()].board end },
        { id = "settings", icon = "Interface\\Icons\\trade_engineering", tip = "Settings", page = function() return "settings" end },
    }
    for i, d in ipairs(defs) do
        local tab = SideTab(frame, d.icon, d.tip, function() FD.Show(d.page()) end)
        tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -(36 + (i - 1) * 50))
        frame.tabs[d.id] = tab
    end

    -- the page area and the controls of Browse and Legends
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", PADF, -(TOP + 4))
    body:SetPoint("BOTTOMRIGHT", -PADF, PADF)
    frame.body = body
    local bar2 = CreateFrame("Frame", nil, body)
    bar2:SetHeight(30)
    bar2:SetPoint("TOPLEFT")
    bar2:SetPoint("TOPRIGHT")
    frame.controls = bar2
    local function GameItems()
        local out = {}
        for _, key in ipairs(D.GAME_ORDER) do out[#out + 1] = { value = key, text = D.GAMES[key].name, icon = D.GameIcon(key) } end
        return out
    end
    frame.gameDrop = W.Dropdown(bar2, 190, GameItems, function(key)
        local kind = UI().KIND[current]
        UI().SetGame(key)
        if kind then FD.Show(UI().TAB_FOR[key][kind]) end
    end)
    frame.gameDrop:SetPoint("LEFT", 0, 0)
    frame.kindDrop = W.Dropdown(bar2, 170, function()
        if section == "browse" then
            return { { value = "lobby", text = "Players" }, { value = "live", text = "Live Games" } }
        end
        return { { value = "board", text = "Leaderboard" }, { value = "coll", text = "Titles and Feats" } }
    end, function(kind)
        if section == "browse" then FD.browseKind = kind else FD.legendsKind = kind end
        FD.Show(UI().TAB_FOR[Game()][kind])
    end)
    frame.kindDrop:SetPoint("LEFT", frame.gameDrop, "RIGHT", 8, 0)
    frame.refresh = CreateFrame("Button", nil, bar2)
    frame.refresh:SetSize(26, 26)
    frame.refresh:SetPoint("LEFT", frame.kindDrop, "RIGHT", 8, 0)
    if A.HasFile("Interface\\Buttons\\UI-RefreshButton") then
        frame.refresh:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    else
        W.Background(frame.refresh, 0.4, 0.3, 0.1, 1)
    end
    frame.refresh:SetScript("OnClick", function()
        ns.Sound("click")
        G.Announce(true)
        FD.Refresh()
    end)
    W.Tooltip(frame.refresh, function(_, t) t:SetText("Refresh", 1, 0.82, 0) end)
    frame.profileBtn = W.Button(bar2, "My Profile", 110, 24, function() UI().ShowProfile(ns.me) end)
    frame.profileBtn:SetPoint("RIGHT", 0, 0)

    local host = CreateFrame("Frame", nil, body)
    frame.host = host

    -- every page, built on first use
    local all = Defs()
    for id, d in pairs(all) do
        local p = CreateFrame("Frame", nil, host)
        p:SetAllPoints()
        p:Hide()
        pages[id] = { frame = p, build = d.build, refresh = d.refresh, layout = d.layout }
    end

    -- resize grip
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 30)
    local up = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
    if A.HasFile(up) then
        grip:SetNormalTexture(up)
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    end
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        s.finderSize = { floor(frame.w + 0.5), floor(frame.h + 0.5) }
    end)
    frame:SetScript("OnSizeChanged", function(_, w, h)
        if w and h then frame.w, frame.h = w, h; FD.Layout() end
    end)
    local accum = 0
    frame:SetScript("OnUpdate", function(_, e)
        accum = accum + e
        if accum >= 1 then
            accum = 0
            if section == "find" and G.seek then FD.RefreshListing() end
        end
    end)
    frame:SetScript("OnShow", function() FD.Refresh() end)
    frame:Hide()
end

function FD.Layout()
    if not built then return end
    local w, h = frame.w - PADF * 2, frame.h - TOP - 4 - PADF
    local withControls = section == "browse" or section == "legends"
    frame.host:ClearAllPoints()
    frame.host:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 0, withControls and -36 or 0)
    frame.host:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", 0, 0)
    if withControls then frame.controls:Show() else frame.controls:Hide() end
    local p = pages[current]
    if p and p.layout then p.layout(max(10, w), max(10, h - (withControls and 36 or 0))) end
end

-- Shows a page of the finder (and the finder).
function FD.Show(id)
    if not ns.db or not P.me then return end
    Build()
    id = id or current
    if not pages[id] then id = "games" end
    local game = GameOf(id)
    if game then ns.db.settings.game = game end
    current = id
    section = SectionOf(id) or "find"
    local kind = UI().KIND[id]
    if section == "browse" then FD.browseKind = kind end
    if section == "legends" then FD.legendsKind = kind end
    local p = pages[id]
    if not p.built then
        p.built = true
        p.build(p.frame)
    end
    frame:Show()
    FD.Layout()
    FD.Refresh()
end

function FD.Hide() if built then frame:Hide() end end
function FD.IsShown() return built and frame:IsShown() end
function FD.Current() return current end
function FD.IsVisible(id) return built and frame:IsShown() and current == id end

function FD.Toggle()
    if built and frame:IsShown() then frame:Hide() else FD.Show(current) end
end

function FD.Refresh()
    if not built or not frame:IsShown() or not P.me then return end
    for id, tab in pairs(frame.tabs) do tab:SetOn(id == section) end
    frame.title:SetText(section == "find" and "Find a Game" or section == "browse" and "Browse" or section == "legends" and "Legends" or "Settings")
    local game = Game()
    frame.gameDrop:SetValue(D.GAMES[game].name, D.GameIcon(game))
    if section == "browse" then
        frame.kindDrop:SetValue(FD.browseKind == "live" and "Live Games" or "Players")
        frame.profileBtn:Hide()
    elseif section == "legends" then
        frame.kindDrop:SetValue(FD.legendsKind == "coll" and "Titles and Feats" or "Leaderboard")
        frame.profileBtn:Show()
    end
    for id, p in pairs(pages) do
        if id == current then p.frame:Show() else p.frame:Hide() end
    end
    local p = pages[current]
    if p and p.built then p.refresh() end
end

------------------------------------------------------------------------
-- Find a Game: the games you would play (round buttons with ticks), your listing,
-- the chosen games with how many are looking, challenge by name, practice and queue
------------------------------------------------------------------------
local find = {}
FD.find = find

local function QueueSet()
    local s = ns.db.settings
    if type(s.queueGames) ~= "table" then s.queueGames = { [Game()] = true } end
    return s.queueGames
end
FD.QueueSet = QueueSet

local function Activity(key)
    local looking, playing = 0, 0
    for _, o in pairs(P.online) do
        if o.status == "g" and (o.battle and o.battle.game or "chess") == key then
            playing = playing + 1
        elseif o.seeking then
            for _, k in ipairs(o.seeking) do if k == key then looking = looking + 1 end end
        end
    end
    return looking, playing
end
FD.Activity = Activity

local function AILevels(key)
    if key == "chess" then
        local out = {}
        for i, l in ipairs(ns.AI.LEVELS) do out[i] = l.name end
        return out, "aiLevel"
    end
    local m = G.Module(key)
    return m.LEVELS, key .. "Level"
end

local function RoundGame(parent, key)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(74, 92)
    b.key = key
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(W.TEX .. "burst")
    b.glow:SetBlendMode("ADD")
    b.glow:SetSize(96, 96)
    b.glow:SetPoint("CENTER", b, "TOP", 0, -34)
    b.glow:SetVertexColor(1, 0.8, 0.3, 0.45)
    b.glow:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(52, 52)
    b.icon:SetPoint("CENTER", b, "TOP", 0, -34)
    W.SetIcon(b.icon, D.GameIcon(key))
    if b.CreateMaskTexture and b.icon.AddMaskTexture then
        local m = b:CreateMaskTexture()
        if m then
            m:SetAllPoints(b.icon)
            m:SetTexture(A.PortraitMask(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            b.icon:AddMaskTexture(m)
        end
    end
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetSize(68, 68)
    b.ring:SetPoint("CENTER", b.icon)
    if A.HasFile("Interface\\Common\\GoldRing") then b.ring:SetTexture("Interface\\Common\\GoldRing")
    else b.ring:SetTexture(W.TEX .. "token_ring"); b.ring:SetVertexColor(1, 0.8, 0.3) end
    b.box = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.box:SetSize(22, 22)
    b.box:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMLEFT", -10, -8)
    b.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    b.tick = b:CreateTexture(nil, "OVERLAY", nil, 3)
    b.tick:SetAllPoints(b.box)
    b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.name = W.Label(b, "GameFontNormalSmall", D.GAMES[key].name)
    b.name:SetPoint("TOP", b, "TOP", 0, -72)
    b.name:SetWidth(84)
    b.name:SetJustifyH("CENTER")
    b:SetScript("OnClick", function() FD.ToggleGame(key) end)
    W.Tooltip(b, function(_, t)
        t:SetText(D.GAMES[key].name, 1, 0.82, 0)
        t:AddLine(D.GAMES[key].blurb, 1, 1, 1, true)
        local looking, playing = Activity(key)
        t:AddLine(string.format("%d looking, %d playing", looking, playing), 0.6, 1, 0.6)
        t:AddLine("Click to tick or untick it for Find Opponent.", 0.7, 0.7, 0.7, true)
    end)
    return b
end

-- Ticks or unticks a game (and makes it the chosen one).
function FD.ToggleGame(key)
    local q = QueueSet()
    q[key] = not q[key] or nil
    ns.db.settings.game = key
    if G.seek then G.StopSeek() end
    ns.Sound("click")
    FD.Refresh()
    UI().Refresh()
end

function FD.BuildFind(page)
    find.page = page
    -- your card
    local card = CreateFrame("Button", nil, page)
    card:SetHeight(52)
    card:SetPoint("TOPLEFT", 40, 0)
    card:SetPoint("TOPRIGHT", 0, 0)
    W.Gradient(card, { 0.14, 0.11, 0.07, 0.9 }, { 0.07, 0.05, 0.04, 0.9 })
    W.Background(card, 0, 0, 0, 0, { 0.5, 0.4, 0.16, 0.8 })
    card.portrait = W.Portrait(card, 46)
    card.portrait:SetPoint("LEFT", 3, 0)
    card.statusDot = card:CreateTexture(nil, "OVERLAY")
    card.statusDot:SetSize(12, 12)
    card.statusDot:SetPoint("BOTTOMRIGHT", card.portrait, "BOTTOMRIGHT", 0, 1)
    card.statusDot:SetTexture(W.TEX .. "dot")
    card.name = W.Title(card, 16)
    card.name:SetPoint("TOPLEFT", 56, -7)
    card.name:SetWordWrap(false)
    card.line = W.Label(card, "GameFontHighlightSmall")
    card.line:SetPoint("BOTTOMLEFT", 56, 8)
    card.line:SetWordWrap(false)
    card.record = W.Title(card, 18)
    card.record:SetPoint("RIGHT", -10, 0)
    card.record:SetJustifyH("RIGHT")
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:SetScript("OnClick", function(self, button)
        if button == "RightButton" then UI().ShowStatusMenu(self) else UI().ShowProfile(ns.me) end
    end)
    W.Tooltip(card, function(_, t)
        t:SetText("Your profile", 1, 0.82, 0)
        t:AddLine(UI().StatusText())
        t:AddLine("Click to see your records and feats. Right-click to set your status.", 1, 1, 1, true)
    end)
    find.card = card

    -- the games, as round buttons with ticks
    find.buttons = {}
    for i, key in ipairs(D.GAME_ORDER) do find.buttons[i] = RoundGame(page, key) end

    -- your listing (while queued)
    local li = CreateFrame("Frame", nil, page)
    li:SetHeight(44)
    W.Gradient(li, { 0.04, 0.32, 0.36, 0.95 }, { 0.02, 0.12, 0.15, 0.95 })
    W.Background(li, 0, 0, 0, 0, { 0.3, 0.7, 0.75, 0.8 })
    li.name = W.Title(li, 16)
    li.name:SetPoint("TOPLEFT", 10, -5)
    li.sub = W.Label(li, "GameFontHighlightSmall")
    li.sub:SetPoint("BOTTOMLEFT", 10, 6)
    li.icons = {}
    for i = 1, #D.GAME_ORDER do
        local t = li:CreateTexture(nil, "ARTWORK")
        t:SetSize(22, 22)
        li.icons[i] = t
    end
    li.timer = W.Title(li, 16, nil, { 1, 1, 1 })
    li.cancel = CreateFrame("Button", nil, li, "UIPanelCloseButton")
    li.cancel:SetPoint("RIGHT", -2, 0)
    li.cancel:SetScript("OnClick", function() G.StopSeek(); FD.Refresh() end)
    li.timer:SetPoint("RIGHT", li.cancel, "LEFT", -6, 0)
    li:Hide()
    find.listing = li

    -- the chosen games
    local box = CreateFrame("Frame", nil, page)
    W.Background(box, 0.03, 0.02, 0.02, 0.9, { 0.5, 0.4, 0.16, 0.8 })
    local art = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-DungeonWall"
    if A.HasFile(art) then
        local bg = box:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetAllPoints()
        bg:SetTexture(art)
        bg:SetTexCoord(0, 0.65, 0, 0.8)
        bg:SetVertexColor(0.45, 0.4, 0.35)
    end
    box.head = W.Label(box, "GameFontNormal", "Your games")
    box.head:SetPoint("TOPLEFT", 10, -8)
    box.help = W.Button(box, "How to play", 150, 20, function() UI().ShowHelp(Game()) end)
    box.help:SetPoint("TOPRIGHT", -6, -5)
    box.rows = {}
    for i, key in ipairs(D.GAME_ORDER) do
        local r = CreateFrame("Button", nil, box)
        r:SetHeight(24)
        r.key = key
        r.box = r:CreateTexture(nil, "ARTWORK")
        r.box:SetSize(22, 22)
        r.box:SetPoint("LEFT", 6, 0)
        r.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        r.tick = r:CreateTexture(nil, "OVERLAY")
        r.tick:SetAllPoints(r.box)
        r.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 32, 0)
        W.SetIcon(r.icon, D.GameIcon(key))
        r.name = W.Label(r, "GameFontNormal", D.GAMES[key].name)
        r.name:SetPoint("LEFT", 56, 0)
        r.count = W.Label(r, "GameFontHighlightSmall")
        r.count:SetPoint("RIGHT", -8, 0)
        r.count:SetJustifyH("RIGHT")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.4, 0.08)
        r:SetScript("OnClick", function() FD.ToggleGame(key) end)
        box.rows[i] = r
    end
    -- chess options: rated or casual, and the clock
    local opt = CreateFrame("Frame", nil, box)
    opt:SetHeight(26)
    local st = ns.db.settings
    opt.rated = W.Button(opt, "Rated", 70, 22, function()
        st.rated = not (st.rated ~= false)
        if G.seek then G.StopSeek() end
        FD.Refresh()
    end)
    opt.rated:SetPoint("LEFT", 56, 0)
    opt.prev = W.Button(opt, "<", 24, 22, function()
        st.tc = ((st.tc or 4) - 1) % (#D.TIME_CONTROLS + 1)
        if G.seek then G.StopSeek() end
        FD.Refresh()
    end)
    opt.prev:SetPoint("LEFT", opt.rated, "RIGHT", 10, 0)
    opt.tc = W.Label(opt, "GameFontHighlight")
    opt.tc:SetPoint("LEFT", opt.prev, "RIGHT", 6, 0)
    opt.tc:SetWidth(110)
    opt.tc:SetJustifyH("CENTER")
    opt.nextB = W.Button(opt, ">", 24, 22, function()
        st.tc = ((st.tc or 4) + 1) % (#D.TIME_CONTROLS + 1)
        if G.seek then G.StopSeek() end
        FD.Refresh()
    end)
    opt.nextB:SetPoint("LEFT", opt.tc, "RIGHT", 6, 0)
    box.opt = opt
    box.empty = W.Label(box, "GameFontDisableSmall", "Tick the games above that you would like to play.")
    find.box = box

    -- challenge by name
    local ch = CreateFrame("Frame", nil, page)
    ch:SetHeight(28)
    ch.label = W.Label(ch, "GameFontNormal", "Challenge a player:")
    ch.label:SetPoint("LEFT", 0, 0)
    local nameBox = CreateFrame("EditBox", nil, ch, "InputBoxTemplate")
    nameBox:SetSize(170, 22)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetPoint("LEFT", ch.label, "RIGHT", 12, 0)
    find.nameBox = nameBox
    local function SendChallenge()
        if G.outgoing and not G.outgoing.q then
            G.CancelInvite()
            FD.Refresh()
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
        local game = Game()
        if game == "chess" then G.Invite(name, { rated = st.rated ~= false }) else G.Invite(name, { game = game }) end
        FD.Refresh()
    end
    nameBox:SetScript("OnEnterPressed", SendChallenge)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ch.button = W.Button(ch, "Challenge", 150, 24, SendChallenge)
    ch.button:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    ch.note = W.Label(page, "GameFontDisableSmall", "")
    find.challenge = ch

    -- bottom: practice and queue
    find.practice = W.Button(page, "Practice", 110, 26, function()
        local game = Game()
        local levels, key = AILevels(game)
        local level = ns.db.settings[key] or 2
        if game == "chess" then G.StartAI(level, nil) else G.Module(game).StartAI(level) end
    end)
    find.level = W.Button(page, "", 96, 26, function()
        local levels, key = AILevels(Game())
        ns.db.settings[key] = ((ns.db.settings[key] or 2) % #levels) + 1
        FD.Refresh()
    end)
    W.Tooltip(find.level, function(_, t)
        t:SetText("Computer strength", 1, 0.82, 0)
        t:AddLine("Click to change. Practice games never count.", 1, 1, 1, true)
    end)
    find.queue = W.Button(page, "Find Opponent", 150, 30, function()
        if G.seek then G.StopSeek() else FD.Queue() end
        FD.Refresh()
    end)
    find.queueNote = W.Label(page, "GameFontDisableSmall", "")
end

-- Joins the queue for every ticked game.
function FD.Queue()
    local list = {}
    local q = QueueSet()
    for _, key in ipairs(D.GAME_ORDER) do if q[key] then list[#list + 1] = key end end
    if #list == 0 then
        ns.Print("tick at least one game first.")
        return
    end
    local st = ns.db.settings
    local idx = st.tc or 4
    local tc = D.TIME_CONTROLS[idx == 0 and 4 or idx]
    G.StartSeek(tc.base, tc.inc, st.rated ~= false, idx == 0, list)
end

function FD.LayoutFind(w, h)
    if not find.page then return end
    local n = #find.buttons
    local step = (w - 40) / n
    for i, b in ipairs(find.buttons) do
        b:ClearAllPoints()
        b:SetPoint("TOP", find.page, "TOPLEFT", 20 + step * (i - 0.5), -60)
    end
    local y = -60 - 96
    find.listing:ClearAllPoints()
    find.listing:SetPoint("TOPLEFT", 0, y)
    find.listing:SetPoint("TOPRIGHT", 0, y)
    find.listTop = y
    find.w, find.h = w, h
    local boxTop = y - (G.seek and 50 or 0)
    find.box:ClearAllPoints()
    find.box:SetPoint("TOPLEFT", 0, boxTop)
    find.box:SetPoint("BOTTOMRIGHT", find.page, "BOTTOMRIGHT", 0, 82)
    find.challenge:ClearAllPoints()
    find.challenge:SetPoint("BOTTOMLEFT", find.page, "BOTTOMLEFT", 4, 44)
    find.challenge:SetPoint("BOTTOMRIGHT", find.page, "BOTTOMRIGHT", 0, 44)
    find.practice:ClearAllPoints()
    find.practice:SetPoint("BOTTOMLEFT", find.page, "BOTTOMLEFT", 0, 4)
    find.level:ClearAllPoints()
    find.level:SetPoint("LEFT", find.practice, "RIGHT", 6, 0)
    find.queue:ClearAllPoints()
    find.queue:SetPoint("BOTTOMRIGHT", find.page, "BOTTOMRIGHT", 0, 2)
    find.queueNote:ClearAllPoints()
    find.queueNote:SetPoint("RIGHT", find.queue, "LEFT", -10, 0)
end

function FD.RefreshListing()
    local li = find.listing
    if not li then return end
    local seek = G.seek
    if not seek then li:Hide() return end
    li:Show()
    local info = W.CharInfo(ns.me)
    li.name:SetText(W.ClassName(ns.me, info) .. "  |cff40ff40Your Listing|r")
    li.sub:SetText("Looking for:")
    local n = 0
    for _, key in ipairs(seek.list or { seek.game }) do
        n = n + 1
        local t = li.icons[n]
        W.SetIcon(t, D.GameIcon(key))
        t:ClearAllPoints()
        t:SetPoint("LEFT", li, "LEFT", 82 + (n - 1) * 26, -10)
        t:Show()
    end
    for i = n + 1, #li.icons do li.icons[i]:Hide() end
    local secs = floor(ns.Now() - (seek.since or ns.Now()))
    li.timer:SetText(string.format("%d:%02d", floor(secs / 60), secs % 60))
end

function FD.RefreshFind()
    if not find.page then return end
    local q = QueueSet()
    local focus = Game()
    local st = ns.db.settings
    -- card
    local card, info = find.card, A.MyCharInfo()
    card.portrait:SetPlayer(ns.me, info, A.MyFaction())
    if focus == "chess" then
        card.name:SetText(W.ClassName(ns.me, info) .. "  |cffaaaaaa" .. P.TitleText(P.MyTitleId(), P.me.rating, P.RatedGames()) .. "|r")
        card.record:SetText(P.me.rating)
    else
        card.name:SetText(W.ClassName(ns.me, info) .. "  " .. P.GameTitleText(P.MyTitleId(focus), focus))
        local rec = L.Record(ns.me, focus)
        local draws = D.GAMES[focus].draws
        if rec then
            card.record:SetText(string.format("|cff40ff40%d|r-|cffff5040%d|r", rec.w, rec.l) .. (draws and string.format("-|cffd0d0d0%d|r", rec.d) or ""))
        else
            card.record:SetText(draws and "|cffaaaaaa0-0-0|r" or "|cffaaaaaa0-0|r")
        end
    end
    card.line:SetText(A.CharLine(info) .. (info.guild and ("  |cff40ff40<" .. info.guild .. ">|r") or ""))
    card.statusDot:SetVertexColor(unpack(UI().StatusColor()))
    card:SetWidth(max(200, (find.w or 600) - 40))
    -- round buttons
    for _, b in ipairs(find.buttons) do
        if q[b.key] then b.tick:Show(); b.icon:SetDesaturated(false); b.icon:SetAlpha(1) else b.tick:Hide(); b.icon:SetDesaturated(true); b.icon:SetAlpha(0.7) end
        if b.key == focus then b.glow:Show(); b.name:SetTextColor(1, 0.85, 0.3) else b.glow:Hide(); b.name:SetTextColor(0.8, 0.7, 0.5) end
    end
    FD.RefreshListing()
    FD.LayoutFind(find.w or 600, find.h or 500)
    -- the chosen games
    local box = find.box
    local y = -28
    local shown = 0
    for _, r in ipairs(box.rows) do
        if q[r.key] then
            shown = shown + 1
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", box, "TOPLEFT", 4, y)
            r:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, y)
            r:Show()
            r.tick:Show()
            local looking, playing = Activity(r.key)
            r.count:SetText(string.format("|cffffd100%d|r looking  ·  |cffff9040%d|r playing", looking, playing))
            r.name:SetTextColor(r.key == focus and 1 or 0.9, r.key == focus and 0.85 or 0.8, r.key == focus and 0.3 or 0.6)
            y = y - 26
            if r.key == "chess" then
                box.opt:ClearAllPoints()
                box.opt:SetPoint("TOPLEFT", box, "TOPLEFT", 4, y)
                box.opt:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, y)
                box.opt:Show()
                box.opt.rated:SetText(st.rated ~= false and "Rated" or "Casual")
                local idx = st.tc or 4
                box.opt.tc:SetText(idx == 0 and "Any clock" or ns.PlayView.TimeControlName(D.TIME_CONTROLS[idx].base, D.TIME_CONTROLS[idx].inc))
                y = y - 28
            end
        else
            r:Hide()
            if r.key == "chess" then box.opt:Hide() end
        end
    end
    box.help:SetText("How to play: " .. (focus == "chess" and "Chess" or D.GAMES[focus].name))
    box.empty:ClearAllPoints()
    box.empty:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y - 4)
    if shown == 0 then box.empty:Show() else box.empty:Hide() end
    -- challenge
    local ch = find.challenge
    if G.outgoing and not G.outgoing.q then
        ch.button:SetText("Cancel")
        ch.label:SetText("|cffffd100Waiting for " .. ns.ShortName(G.outgoing.to) .. "...|r")
    else
        ch.button:SetText("Challenge: " .. (focus == "chess" and "Chess" or D.GAMES[focus].name))
        ch.label:SetText("Challenge a player:")
    end
    -- practice and queue
    local levels, key = AILevels(focus)
    find.level:SetText(levels[st[key] or 2] or "")
    find.practice:SetText("Practice")
    if G.seek then
        find.queue:SetText("Leave Queue")
        find.queueNote:SetText("")
    else
        find.queue:SetText("Find Opponent")
        local n = 0
        for _ in pairs(q) do n = n + 1 end
        find.queueNote:SetText(n == 0 and "Tick a game first" or (n == 1 and "Queue for 1 game" or ("Queue for " .. n .. " games")))
    end
    if not C.Joined() and #C.GroupDists() == 0 then find.queueNote:SetText("|cffaaaaaaConnecting...|r") end
end
