-- Checkmate: Azeroth - shared UI building blocks with a Warcraft look (game art where available,
-- flat fallbacks otherwise).
local _, ns = ...

local W = {}
ns.W = W

local A = ns.Assets
local floor, max, min = math.floor, math.max, math.min
W.TEX = A.TEX

W.GOLD = { 1, 0.82, 0 }
W.MEDAL = {
    { 1.00, 0.82, 0.20 }, -- gold
    { 0.80, 0.82, 0.88 }, -- silver
    { 0.80, 0.50, 0.25 }, -- bronze
}

function W.Hex(c)
    return string.format("ff%02x%02x%02x", floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255))
end

-- Flat background (and optional 1px border) behind a frame.
function W.Background(frame, r, g, b, a, border)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(r, g, b, a)
    frame.bg = bg
    if border then
        frame.edges = {}
        local function Edge(p1, p2, w, h)
            local t = frame:CreateTexture(nil, "BORDER", nil, -1)
            t:SetColorTexture(border[1], border[2], border[3], border[4] or 1)
            t:SetPoint(p1)
            t:SetPoint(p2)
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
            frame.edges[#frame.edges + 1] = t
        end
        Edge("TOPLEFT", "TOPRIGHT", nil, 1)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
        Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
        Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    end
    return bg
end

-- Vertical gradient (top colour -> bottom colour), used for cards.
function W.Gradient(frame, top, bottom, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, -7)
    t:SetAllPoints()
    t:SetColorTexture(1, 1, 1, 1)
    if t.SetGradient and CreateColor then
        pcall(t.SetGradient, t, "VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1),
            CreateColor(top[1], top[2], top[3], top[4] or 1))
    else
        t:SetColorTexture(top[1], top[2], top[3], top[4] or 1)
    end
    return t
end

-- Game border art just outside `frame`. Returns the border frame or nil.
function W.Chrome(frame, art, pad, edgeSize)
    local file = A.ART[art]
    if not A.HasFile(file) then return nil end
    local ok, border = pcall(CreateFrame, "Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if not ok or not border or not border.SetBackdrop then return nil end
    pad = pad or 6
    border:SetPoint("TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", pad, -pad)
    border:SetFrameLevel(frame:GetFrameLevel() + 1)
    border:EnableMouse(false)
    border:SetBackdrop({ edgeFile = file, edgeSize = edgeSize or 24, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    return border
end

-- Tiled game texture (e.g. dark dialog stone) as a background layer.
function W.Tile(frame, art, alpha)
    local file = A.ART[art]
    if not A.HasFile(file) then return nil end
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    t:SetAllPoints()
    t:SetTexture(file, "REPEAT", "REPEAT")
    if t.SetHorizTile then t:SetHorizTile(true); t:SetVertTile(true) end
    t:SetAlpha(alpha or 1)
    return t
end

-- A dark card with a faint gold edge.
function W.Card(parent)
    local f = CreateFrame("Frame", nil, parent)
    W.Gradient(f, { 0.13, 0.10, 0.07, 0.95 }, { 0.06, 0.05, 0.04, 0.95 })
    W.Background(f, 0, 0, 0, 0, { 0.55, 0.43, 0.18, 0.75 })
    return f
end

function W.Label(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

-- Morpheus (quest title) font in gold.
function W.Title(parent, size, text, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(A.TitleFont(), size, "")
    local c = color or W.GOLD
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

function W.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    b:SetScript("OnClick", function(self, ...)
        ns.Sound("click")
        onClick(self, ...)
    end)
    return b
end

-- Small square button showing a game icon (or a text glyph when the icon is missing).
function W.IconButton(parent, size, icon, glyph, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    W.Background(b, 0.08, 0.06, 0.04, 0.95, { 0.6, 0.48, 0.2, 1 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.glyph = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.glyph:SetPoint("CENTER")
    function b:SetIcon(path, text)
        if path and A.HasFile(path) then
            self.icon:SetTexture(path)
            self.icon:Show()
            self.glyph:Hide()
        else
            self.icon:Hide()
            self.glyph:SetText(text or "?")
            self.glyph:Show()
        end
    end
    b:SetIcon(icon, glyph)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.85, 0.4, 0.25)
    b:SetScript("OnClick", function(self, ...)
        ns.Sound("click")
        onClick(self, ...)
    end)
    if tooltip then
        W.Tooltip(b, function(_, tip)
            tip:SetText(type(tooltip) == "function" and tooltip() or tooltip, 1, 1, 1)
        end)
    end
    return b
end

function W.Check(parent, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local fs = W.Label(parent, "GameFontHighlight", text)
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label = fs
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Sound("click")
    end)
    cb.Sync = function() cb:SetChecked(get() and true or false) end
    return cb
end

function W.Tooltip(frame, fn)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if fn(self, GameTooltip) ~= false then GameTooltip:Show() end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Sets a texture to a game icon, falling back to the question mark icon.
local QUESTION = "Interface\\Icons\\inv_misc_questionmark"
function W.SetIcon(tex, path)
    if path and A.HasFile(path) then
        tex:SetTexture(path)
    else
        tex:SetTexture(QUESTION)
    end
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

-- Army crest into a texture: the PvP emblem for Alliance/Horde, otherwise the army
-- leader's portrait. Hides the texture when nothing is known.
function W.SetCrest(tex, army)
    local file, isPortrait = nil, false
    if army then file, isPortrait = A.Crest(army) end
    if file then
        tex:SetTexture(file)
        if isPortrait then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 0.62, 0, 0.62) end
        tex:Show()
    else
        tex:Hide()
    end
end

-- League emblem (PvP rank insignia) into a texture.
function W.SetLeagueIcon(tex, leagueIndex)
    local L = ns.Data.LEAGUES[leagueIndex or 0]
    if not L then tex:Hide(); return false end
    local file = string.format("Interface\\PvPRankBadges\\PvPRank%02d", L.badge)
    if A.HasFile(file) then
        tex:SetTexture(file)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
        return true
    end
    tex:Hide()
    return false
end

-- PvP rank insignia for a rank index (1..9) of Data.RANKS.
local RANK_BADGE = { 1, 2, 4, 6, 8, 10, 12, 13, 14 }
function W.SetRankIcon(tex, rankIndex)
    local n = RANK_BADGE[rankIndex or 1] or 1
    local file = string.format("Interface\\PvPRankBadges\\PvPRank%02d", n)
    if A.HasFile(file) then
        tex:SetTexture(file)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
        return true
    end
    tex:Hide()
    return false
end

-- Status dot icons used by the friends list.
local STATUS_ICON = {
    i = "Interface\\FriendsFrame\\StatusIcon-Online",
    s = "Interface\\FriendsFrame\\StatusIcon-Away",
    d = "Interface\\FriendsFrame\\StatusIcon-DnD",
    g = "Interface\\FriendsFrame\\StatusIcon-Away",
}
function W.SetStatusIcon(tex, status)
    local file = STATUS_ICON[status] or STATUS_ICON.i
    if A.HasFile(file) then
        tex:SetTexture(file)
        tex:Show()
    else
        tex:Hide()
    end
end

------------------------------------------------------------------------
-- Responsive scroll list: rows are created as needed for the available height.
--   build(row) creates widgets; update(row, item, index) fills them.
------------------------------------------------------------------------
function W.List(parent, rowHeight, build, update, gap)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.data, list.offset = {}, {}, 0
    list.rowHeight, list.gap = rowHeight, gap or 2
    list.visible = 0
    function list:Resize(width, height)
        self.width = width
        self:SetSize(width, height)
        local fit = max(1, floor((height + self.gap) / (self.rowHeight + self.gap)))
        for i = #self.rows + 1, fit do
            local row = CreateFrame("Button", nil, self)
            row:SetHeight(self.rowHeight)
            build(row)
            self.rows[i] = row
        end
        self.visible = fit
        for i = 1, #self.rows do
            local row = self.rows[i]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * (self.rowHeight + self.gap))
            row:SetWidth(width)
            if row.OnResize then row:OnResize(width) end
        end
        self:Update()
    end
    function list:Update()
        local maxOffset = max(0, #self.data - self.visible)
        if self.offset > maxOffset then self.offset = maxOffset end
        for i = 1, #self.rows do
            local row = self.rows[i]
            local item = i <= self.visible and self.data[i + self.offset]
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
        self.offset = max(0, self.offset - delta * 2)
        self:Update()
    end)
    return list
end

------------------------------------------------------------------------
-- Responsive tile grid: as many columns as fit, scrolls by rows.
------------------------------------------------------------------------
function W.Grid(parent, tileW, tileH, build, update, gap)
    local grid = CreateFrame("Frame", nil, parent)
    grid.tiles, grid.data, grid.offset = {}, {}, 0
    gap = gap or 8
    function grid:Resize(width, height)
        self:SetSize(width, height)
        self.cols = max(1, floor((width + gap) / (tileW + gap)))
        self.rowsFit = max(1, floor((height + gap) / (tileH + gap)))
        local need = self.cols * self.rowsFit
        for i = #self.tiles + 1, need do
            local tile = CreateFrame("Button", nil, self)
            tile:SetSize(tileW, tileH)
            build(tile)
            self.tiles[i] = tile
        end
        -- Spread the columns over the full width.
        local spare = width - self.cols * tileW
        local g = self.cols > 1 and min(gap * 3, spare / (self.cols - 1)) or 0
        for i = 1, #self.tiles do
            local tile = self.tiles[i]
            local c, r = (i - 1) % self.cols, floor((i - 1) / self.cols)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", self, "TOPLEFT", c * (tileW + g), -r * (tileH + gap))
        end
        self:Update()
    end
    function grid:Update()
        local cols = self.cols or 1
        local totalRows = math.ceil(#self.data / cols)
        local maxOffset = max(0, totalRows - (self.rowsFit or 1))
        if self.offset > maxOffset then self.offset = maxOffset end
        local first = self.offset * cols
        local shown = cols * (self.rowsFit or 1)
        for i = 1, #self.tiles do
            local tile = self.tiles[i]
            local item = i <= shown and self.data[first + i]
            if item then
                tile.item = item
                update(tile, item)
                tile:Show()
            else
                tile.item = nil
                tile:Hide()
            end
        end
    end
    function grid:SetData(data)
        self.data = data
        self:Update()
    end
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(self, delta)
        self.offset = max(0, self.offset - delta)
        self:Update()
    end)
    return grid
end

-- Thin progress bar.
function W.Bar(parent, width, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    W.Background(f, 0, 0, 0, 0.6, { 0.4, 0.32, 0.12, 1 })
    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetPoint("TOPLEFT", 1, -1)
    f.fill:SetPoint("BOTTOMLEFT", 1, 1)
    f.fill:SetColorTexture(0.85, 0.65, 0.1, 1)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("CENTER")
    function f:SetProgress(value, total)
        local p = total > 0 and min(1, value / total) or 0
        self.fill:SetWidth(max(1, (self.width or width) * p - 2))
        self.text:SetText(string.format("%d / %d", min(value, total), total))
    end
    function f:SetBarWidth(w)
        self.width = w
        self:SetWidth(w)
    end
    return f
end
