-- Flightpath Legends - the finder: a Group Finder style window for everything except playing.
-- Side tabs: one per game (its Play page - find an opponent, challenge, practise, How to play -
-- then Lobby, Live Games, Leaderboard, Titles & Feats) and Settings.
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
local current = "chesshub" -- the page id being shown
local section = "game" -- game | settings
local SUBS = {
    { kind = "hub", text = "Play" },
    { kind = "lobby", text = "Lobby" },
    { kind = "live", text = "Live Games" },
    { kind = "board", text = "Leaderboard" },
    { kind = "coll", text = "Titles & Feats" },
}
local pages = {} -- [id] = { frame, refresh, layout, built }
FD.pages = pages

local function UI() return ns.UI end
local function Game() return UI().Game() end

------------------------------------------------------------------------
-- Which page belongs to which side tab
------------------------------------------------------------------------
local function SectionOf(id)
    if id == "settings" then return "settings" end
    local kind = UI().KIND[id]
    if kind and kind ~= "play" then return "game" end
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
        settings = { build = T.BuildSettings, refresh = T.RefreshSettings, layout = T.LayoutSettings },
        ladder = { build = T.BuildLadder, refresh = T.RefreshLadder, layout = T.LayoutLadder },
        admirals = { build = T.BuildAdmirals, refresh = T.RefreshAdmirals, layout = T.LayoutAdmirals },
    }
    for id, d in pairs(FD.HubDefs()) do defs[id] = d end
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
    local mug = CreateFrame("Button", nil, frame)
    mug:SetSize(20, 20)
    mug:SetPoint("CENTER", frame, "TOPRIGHT", -44, -(TOP - 6) / 2 - 4)
    mug.icon = mug:CreateTexture(nil, "ARTWORK")
    mug.icon:SetAllPoints()
    W.SetIcon(mug.icon, "Interface\\Icons\\inv_drink_04")
    local mhl = mug:CreateTexture(nil, "HIGHLIGHT")
    mhl:SetAllPoints()
    mhl:SetColorTexture(1, 0.9, 0.5, 0.25)
    mug:SetScript("OnClick", function() ns.Sound("click"); UI().ShowDonate() end)
    W.Tooltip(mug, function(_, t)
        t:SetText("The Tavern Tip Jar", 1, 0.82, 0)
        t:AddLine("Enjoying the games? Buy the developer a coffee.", 1, 1, 1, true)
    end)
    frame.mug = mug

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
    W.SetIcon(em.logo, "Interface\\Icons\\ability_mount_gryphon_01")
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

    -- side tabs (outside the right edge): Find a Game, each game, Settings
    frame.tabs = {}
    local defs = {}
    for _, key in ipairs(D.GAME_ORDER) do
        defs[#defs + 1] = { id = key, icon = D.GameIcon(key), tip = D.GAMES[key].name,
            page = function() return UI().TAB_FOR[key][FD.gameKind or "hub"] end }
    end
    defs[#defs + 1] = { id = "settings", icon = "Interface\\Icons\\trade_engineering", tip = "Settings", page = function() return "settings" end }
    for i, d in ipairs(defs) do
        local tab = SideTab(frame, d.icon, d.tip, function() FD.Show(d.page()) end)
        -- a little gap after Find a Game and before Settings
        local gap = (i == #defs and 12 or 0)
        tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -(36 + (i - 1) * 46 + gap))
        frame.tabs[d.id] = tab
    end

    -- the page area, and a game's page buttons along the top
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", PADF, -(TOP + 4))
    body:SetPoint("BOTTOMRIGHT", -PADF, PADF)
    frame.body = body
    local bar2 = CreateFrame("Frame", nil, body)
    bar2:SetHeight(30)
    bar2:SetPoint("TOPLEFT")
    bar2:SetPoint("TOPRIGHT")
    frame.controls = bar2
    frame.sub = {}
    local prev
    for _, sd in ipairs(SUBS) do
        local b = W.Button(bar2, sd.text, 96, 26, function()
            FD.gameKind = sd.kind
            FD.Show(UI().TAB_FOR[Game()][sd.kind])
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", 0, 0) end
        prev = b
        frame.sub[sd.kind] = b
    end
    frame.refresh = CreateFrame("Button", nil, bar2)
    frame.refresh:SetSize(26, 26)
    frame.refresh:SetPoint("LEFT", prev, "RIGHT", 10, 0)
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
    frame.profileBtn = W.Button(bar2, "My Profile", 100, 24, function() UI().ShowProfile(ns.me) end)
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
            if section == "game" and G.seek then FD.RefreshListing(); local p = pages[current]; if p and p.built and UI().KIND[current] == "hub" then p.refresh() end end
        end
    end)
    frame:SetScript("OnShow", function() FD.Refresh() end)
    frame:Hide()
end

function FD.Layout()
    if not built then return end
    local w, h = frame.w - PADF * 2, frame.h - TOP - 4 - PADF
    local withControls = section == "game"
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
    if not pages[id] then id = UI().TAB_FOR[Game()].hub end
    local game = GameOf(id)
    if game then ns.db.settings.game = game end
    current = id
    section = SectionOf(id) or "find"
    if section == "game" then FD.gameKind = UI().KIND[id] end
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
    local game = Game()
    for id, tab in pairs(frame.tabs) do
        tab:SetOn(id == section or (section == "game" and id == game))
    end
    frame.title:SetText(section == "game" and D.GAMES[game].name or "Settings")
    if section == "game" then
        for kind, b in pairs(frame.sub) do W.SetSelected(b, kind == FD.gameKind) end
        if game == "chess" then frame.sub.board:SetText("Ladder") else frame.sub.board:SetText("Leaderboard") end
    end
    for id, p in pairs(pages) do
        if id == current then p.frame:Show() else p.frame:Hide() end
    end
    local p = pages[current]
    if p and p.built then p.refresh() end
end

------------------------------------------------------------------------
-- A game's Play page: the game, your record, How to play; find an opponent (the queue can
-- hold several games: each game's page adds or removes itself); challenge by name; practice.
------------------------------------------------------------------------
local hubs = {}
FD.hubs = hubs

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
    return G.Module(key).LEVELS, key .. "Level"
end

-- Whether we have an unfinished game of this kind (playing or watching).
local function InProgress(key)
    if key == "chess" then
        local g = G.current
        return g and g.state == "active"
    end
    local m = G.Module(key)
    return m and m.Active()
end

-- Adds this game to the queue, or takes it out (the queue may hold several games).
function FD.ToggleQueue(key)
    local list = {}
    local s = G.seek
    if s then for _, k in ipairs(s.list or { s.game }) do if k ~= key then list[#list + 1] = k end end end
    local adding = not G.Seeking(key)
    if adding then list[#list + 1] = key end
    if s then G.StopSeek() end
    if #list == 0 then return end
    local st = ns.db.settings
    local idx = st.tc or 4
    local tc = D.TIME_CONTROLS[idx == 0 and 4 or idx]
    G.StartSeek(tc.base, tc.inc, st.rated ~= false, idx == 0, list)
end

local function Section(page, title, height)
    local c = W.Card(page)
    c:SetHeight(height)
    c.h = height
    c.title = W.Title(c, 15, title)
    c.title:SetPoint("TOPLEFT", 10, -8)
    return c
end

local function BuildHub(key, page)
    local h = { key = key, page = page }
    hubs[key] = h
    local g = D.GAMES[key]
    local st = ns.db.settings

    -- the game
    local head = CreateFrame("Frame", nil, page)
    head:SetHeight(84)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    W.Gradient(head, { 0.16, 0.12, 0.07, 0.95 }, { 0.07, 0.05, 0.04, 0.95 })
    W.Background(head, 0, 0, 0, 0, { 0.55, 0.43, 0.18, 0.9 })
    h.icon = head:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(56, 56)
    h.icon:SetPoint("LEFT", 14, 0)
    W.SetIcon(h.icon, D.GameIcon(key))
    if head.CreateMaskTexture and h.icon.AddMaskTexture then
        local m = head:CreateMaskTexture()
        if m then
            m:SetAllPoints(h.icon)
            m:SetTexture(A.PortraitMask(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            h.icon:AddMaskTexture(m)
        end
    end
    local ring = head:CreateTexture(nil, "OVERLAY")
    ring:SetSize(72, 72)
    ring:SetPoint("CENTER", h.icon)
    if A.HasFile("Interface\\Common\\GoldRing") then ring:SetTexture("Interface\\Common\\GoldRing")
    else ring:SetTexture(W.TEX .. "token_ring"); ring:SetVertexColor(1, 0.8, 0.3) end
    h.name = W.Title(head, 20, g.name)
    h.name:SetPoint("TOPLEFT", 84, -10)
    h.blurb = W.Label(head, "GameFontHighlightSmall", g.blurb)
    h.blurb:SetPoint("TOPLEFT", 84, -36)
    h.blurb:SetJustifyV("TOP")
    h.record = W.Label(head, "GameFontHighlightSmall")
    h.record:SetPoint("BOTTOMLEFT", 84, 8)
    h.record:SetWordWrap(false)
    h.help = W.Button(head, "How to play", 110, 22, function() UI().ShowHelp(key) end)
    h.help:SetPoint("TOPRIGHT", -8, -8)
    h.resume = W.Button(head, "Resume game", 110, 22, function() UI().ShowTab(UI().TAB_FOR[key].play) end)
    h.resume:SetPoint("TOPRIGHT", h.help, "BOTTOMRIGHT", 0, -4)
    h.head = head

    -- your listing (while queued for anything)
    local li = CreateFrame("Frame", nil, page)
    li:SetHeight(40)
    W.Gradient(li, { 0.04, 0.32, 0.36, 0.95 }, { 0.02, 0.12, 0.15, 0.95 })
    W.Background(li, 0, 0, 0, 0, { 0.3, 0.7, 0.75, 0.8 })
    li.name = W.Title(li, 15)
    li.name:SetPoint("LEFT", 10, 0)
    li.icons = {}
    for i = 1, #D.GAME_ORDER do
        local t = li:CreateTexture(nil, "ARTWORK")
        t:SetSize(22, 22)
        li.icons[i] = t
    end
    li.cancel = CreateFrame("Button", nil, li, "UIPanelCloseButton")
    li.cancel:SetPoint("RIGHT", -2, 0)
    li.cancel:SetScript("OnClick", function() G.StopSeek(); FD.Refresh() end)
    W.Tooltip(li.cancel, function(_, t) t:SetText("Leave the queue", 1, 0.82, 0) end)
    li.timer = W.Title(li, 15, nil, { 1, 1, 1 })
    li.timer:SetPoint("RIGHT", li.cancel, "LEFT", -4, 0)
    li:Hide()
    h.listing = li

    -- find an opponent
    local q = Section(page, "Find an opponent", 96)
    q.activity = W.Label(q, "GameFontHighlightSmall")
    q.activity:SetPoint("TOPLEFT", 10, -30)
    q.button = W.Button(q, "Find Opponent", 160, 30, function()
        FD.ToggleQueue(key)
        FD.Refresh()
    end)
    q.button:SetPoint("BOTTOMRIGHT", -10, 10)
    q.note = W.Label(q, "GameFontDisableSmall", "")
    q.note:SetPoint("BOTTOMLEFT", 10, 14)
    q.note:SetPoint("RIGHT", q.button, "LEFT", -8, 0)
    if key == "chess" then
        q.rated = W.Button(q, "Rated", 76, 22, function()
            st.rated = not (st.rated ~= false)
            if G.Seeking("chess") then FD.ToggleQueue("chess") end
            FD.Refresh()
        end)
        q.rated:SetPoint("TOPRIGHT", -10, -8)
        q.nextB = W.Button(q, ">", 24, 22, function()
            st.tc = ((st.tc or 4) + 1) % (#D.TIME_CONTROLS + 1)
            if G.Seeking("chess") then FD.ToggleQueue("chess") end
            FD.Refresh()
        end)
        q.nextB:SetPoint("RIGHT", q.rated, "LEFT", -10, 0)
        q.tc = W.Label(q, "GameFontHighlight")
        q.tc:SetPoint("RIGHT", q.nextB, "LEFT", -4, 0)
        q.tc:SetWidth(96)
        q.tc:SetJustifyH("CENTER")
        q.prev = W.Button(q, "<", 24, 22, function()
            st.tc = ((st.tc or 4) - 1) % (#D.TIME_CONTROLS + 1)
            if G.Seeking("chess") then FD.ToggleQueue("chess") end
            FD.Refresh()
        end)
        q.prev:SetPoint("RIGHT", q.tc, "LEFT", -4, 0)
    end
    h.queue = q

    -- challenge a player
    local c = Section(page, "Challenge a player", 66)
    local nameBox = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
    nameBox:SetSize(200, 22)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetPoint("BOTTOMLEFT", 16, 10)
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
        if key == "chess" then G.Invite(name, { rated = st.rated ~= false }) else G.Invite(name, { game = key }) end
        FD.Refresh()
    end
    nameBox:SetScript("OnEnterPressed", SendChallenge)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    c.box = nameBox
    c.button = W.Button(c, "Challenge", 110, 24, SendChallenge)
    c.button:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    c.note = W.Label(c, "GameFontDisableSmall", "")
    c.note:SetPoint("LEFT", c.button, "RIGHT", 10, 0)
    c.note:SetPoint("RIGHT", -10, 0)
    h.challenge = c

    -- practice
    local pr = Section(page, "Practice against the computer", 66)
    pr.level = W.Button(pr, "", 110, 24, function()
        local levels, lk = AILevels(key)
        st[lk] = ((st[lk] or 2) % #levels) + 1
        FD.Refresh()
    end)
    pr.level:SetPoint("BOTTOMLEFT", 10, 10)
    W.Tooltip(pr.level, function(_, t)
        t:SetText("Computer strength", 1, 0.82, 0)
        t:AddLine("Click to change. Practice games never count.", 1, 1, 1, true)
    end)
    pr.start = W.Button(pr, "Play vs Computer", 150, 24, function()
        local _, lk = AILevels(key)
        local level = st[lk] or 2
        if key == "chess" then G.StartAI(level, nil) else G.Module(key).StartAI(level) end
    end)
    pr.start:SetPoint("LEFT", pr.level, "RIGHT", 8, 0)
    h.practice = pr
    return h
end

local function LayoutHub(key, w, hgt)
    local h = hubs[key]
    if not h then return end
    h.w = w
    h.blurb:SetWidth(max(120, w - 40 - 84 - 130))
    local y = -90
    h.listing:ClearAllPoints()
    if G.seek then
        h.listing:SetPoint("TOPLEFT", h.page, "TOPLEFT", 0, y)
        h.listing:SetPoint("TOPRIGHT", h.page, "TOPRIGHT", 0, y)
        y = y - 46
    end
    for _, sec in ipairs({ h.queue, h.challenge, h.practice }) do
        sec:ClearAllPoints()
        sec:SetPoint("TOPLEFT", h.page, "TOPLEFT", 0, y)
        sec:SetPoint("TOPRIGHT", h.page, "TOPRIGHT", 0, y)
        y = y - sec.h - 8
    end
end

local function RefreshListing(h)
    local li = h.listing
    local seek = G.seek
    if not seek then li:Hide() return end
    li:Show()
    li.name:SetText(W.ClassName(ns.me, W.CharInfo(ns.me)) .. "  |cff40ff40Your Listing|r")
    local n = 0
    for _, k in ipairs(seek.list or { seek.game }) do
        n = n + 1
        local t = li.icons[n]
        W.SetIcon(t, D.GameIcon(k))
        t:ClearAllPoints()
        t:SetPoint("RIGHT", li.timer, "LEFT", -12 - (#(seek.list or { seek.game }) - n) * 26, 0)
        t:Show()
    end
    for i = n + 1, #li.icons do li.icons[i]:Hide() end
    local secs = floor(ns.Now() - (seek.since or ns.Now()))
    li.timer:SetText(string.format("%d:%02d", floor(secs / 60), secs % 60))
end

function FD.RefreshListing()
    for _, h in pairs(hubs) do
        if h.page:IsShown() then RefreshListing(h) end
    end
end

local function RefreshHub(key)
    local h = hubs[key]
    if not h then return end
    local st = ns.db.settings
    -- your record and title in this game
    if key == "chess" then
        local v = L.Get(ns.me)
        local text = P.TitleText(P.MyTitleId(), P.me.rating, P.RatedGames()) .. string.format("   Rating |cffffffff%d|r", P.me.rating)
        if v then text = text .. string.format("   rated |cff40ff40%d|r-|cffff5040%d|r-|cffaaaaaa%d|r", v.w, v.l, v.d) end
        h.record:SetText(text)
    else
        h.record:SetText(P.GameTitleText(P.MyTitleId(key), key) .. "   " ..
            T.GameRecordLine(key, L.Record(ns.me, key), key == "bs" and "No battles yet" or nil))
    end
    if InProgress(key) then h.resume:Show() else h.resume:Hide() end
    RefreshListing(h)
    LayoutHub(key, h.w or 600)
    -- queue
    local q = h.queue
    local looking, playing = Activity(key)
    q.activity:SetText(string.format("|cffffd100%d|r looking for a %s  ·  |cffff9040%d|r playing now", looking, D.GAMES[key].word, playing))
    if G.Seeking(key) then
        q.button:SetText("Leave Queue")
        local secs = floor(ns.Now() - (G.seek.since or ns.Now()))
        q.note:SetText(string.format("|cffffd100Searching...|r  %d:%02d", floor(secs / 60), secs % 60))
    else
        q.button:SetText(G.seek and "Also Queue Here" or "Find Opponent")
        q.note:SetText(G.seek and "You can be queued for several games at once." or
            ((not C.Joined() and #C.GroupDists() == 0) and "Connecting to the network..." or ""))
    end
    if key == "chess" then
        q.rated:SetText(st.rated ~= false and "Rated" or "Casual")
        local idx = st.tc or 4
        q.tc:SetText(idx == 0 and "Any clock" or ns.PlayView.TimeControlName(D.TIME_CONTROLS[idx].base, D.TIME_CONTROLS[idx].inc))
    end
    -- challenge
    local c = h.challenge
    if G.outgoing and not G.outgoing.q then
        c.button:SetText("Cancel")
        c.note:SetText("|cffffd100Waiting for " .. ns.ShortName(G.outgoing.to) .. "...|r")
    else
        c.button:SetText("Challenge")
        c.note:SetText("Type a name, or leave it empty to challenge your target.")
    end
    -- practice
    local levels, lk = AILevels(key)
    h.practice.level:SetText(levels[st[lk] or 2] or "")
end

function FD.HubDefs()
    local out = {}
    for _, key in ipairs(D.GAME_ORDER) do
        out[key .. "hub"] = {
            build = function(p) BuildHub(key, p) end,
            refresh = function() RefreshHub(key) end,
            layout = function(w, hgt) LayoutHub(key, w, hgt) end,
        }
    end
    return out
end
