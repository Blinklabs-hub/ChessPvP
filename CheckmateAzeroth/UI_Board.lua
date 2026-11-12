-- Checkmate: Azeroth - the board widget - squares, Warcraft piece tokens, highlights, click-to-move,
-- promotion picker, and move/capture/check animations.
local _, ns = ...

local B = {}
ns.Board = B

local E, G, P, A = ns.Engine, ns.Game, ns.Profile, ns.Assets
local TEX = A.TEX
local PIECE_NAME = { "P", "N", "B", "R", "Q", "K" }
local PROMO_ORDER = { 5, 4, 3, 2 } -- queen, rook, bishop, knight
local PROMO_CHAR = { [2] = "n", [3] = "b", [4] = "r", [5] = "q" }
local FILES = "abcdefgh"
local FONT = A.FONT_BODY
local abs, floor, sin = math.abs, math.floor, math.sin

-- Token size relative to the square, per piece type: pawns smaller, royals larger.
local TOKEN_SCALE = { 0.78, 0.86, 0.86, 0.86, 0.94, 0.98 }

local startPos = E.New()

------------------------------------------------------------------------
-- Piece view: one piece drawn as a Warcraft token (portrait in a faction ring with a
-- chess-symbol badge) or as a classic chess piece.
------------------------------------------------------------------------
local function ClassicColors(set, white)
    return white and set.wFill or set.bFill, white and set.wLine or set.bLine
end

-- Draws a piece silhouette into a fill/line texture pair.
local function DrawSilhouette(fill, line, t, fc, lc)
    fill:SetTexture(TEX .. PIECE_NAME[t] .. "_fill")
    fill:SetVertexColor(fc[1], fc[2], fc[3])
    line:SetTexture(TEX .. PIECE_NAME[t] .. "_line")
    line:SetVertexColor(lc[1], lc[2], lc[3])
    fill:Show(); line:Show()
end

local function SetPiece(view, piece, g, setOverride)
    view.piece = piece
    if not piece or piece == 0 then
        view:Hide()
        return
    end
    local white = piece > 0
    local t = white and piece or -piece
    local set = setOverride or P.PieceSet()
    local size = view.size
    local portrait, army
    if set.warcraft then
        army = A.ArmyFor(white and 1 or -1, g, set)
        portrait = A.Portrait(army, t)
    end

    if portrait then
        local info = A.ARMIES[army]
        local s = size * TOKEN_SCALE[t]
        view.token:SetSize(s, s)
        view.portrait:SetTexture(portrait)
        view.ring:SetVertexColor(info.ring[1], info.ring[2], info.ring[3])
        view.rim:SetVertexColor(info.ringDark[1], info.ringDark[2], info.ringDark[3])
        view.badgeBg:SetVertexColor(info.ringDark[1], info.ringDark[2], info.ringDark[3], 0.95)
        if size >= 24 then
            DrawSilhouette(view.badgeFill, view.badgeLine, t, { 1, 1, 1 }, { 0, 0, 0 })
            view.badgeBg:Show()
        else
            -- Too small for a readable badge (captured-pieces tray).
            view.badgeBg:Hide(); view.badgeFill:Hide(); view.badgeLine:Hide()
        end
        view.token:Show()
        view.shadow:Show()
        view.fill:Hide(); view.line:Hide(); view.letter:Hide()
    else
        view.token:Hide()
        view.shadow:Hide()
        local fc, lc
        if set.warcraft then
            -- Art missing on this client: classic pieces in faction colours.
            local info = A.ARMIES[army]
            fc, lc = info.color, white and { 0.05, 0.05, 0.08 } or { 1, 0.9, 0.8 }
        else
            fc, lc = ClassicColors(set, white)
        end
        if set.letters then
            view.fill:Hide(); view.line:Hide()
            view.letter:SetText(PIECE_NAME[t])
            view.letter:SetTextColor(white and 1 or 0.05, white and 1 or 0.05, white and 1 or 0.05)
            view.letter:Show()
        else
            view.letter:Hide()
            DrawSilhouette(view.fill, view.line, t, fc, lc)
        end
    end
    view:Show()
end

function B.CreatePieceView(parent, size)
    local v = CreateFrame("Frame", nil, parent)
    v:SetSize(size, size)
    v.size = size
    v:EnableMouse(false)

    v.shadow = v:CreateTexture(nil, "BACKGROUND")
    v.shadow:SetTexture(TEX .. "shadow")
    v.shadow:SetSize(size * 0.86, size * 0.30)
    v.shadow:SetPoint("BOTTOM", 0, size * 0.02)
    v.shadow:SetVertexColor(0, 0, 0, 0.55)

    local token = CreateFrame("Frame", nil, v)
    token:SetPoint("CENTER", 0, size * 0.02)
    token:SetSize(size, size)
    v.token = token
    v.portrait = token:CreateTexture(nil, "ARTWORK", nil, 1)
    v.portrait:SetPoint("TOPLEFT", token, "TOPLEFT", 0, 0)
    v.portrait:SetPoint("BOTTOMRIGHT", token, "BOTTOMRIGHT", 0, 0)
    v.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's built-in border
    -- Round portrait. Texture:SetMask garbles textures on the modern client, so a mask
    -- texture object is used, with the game's own round portrait mask.
    if token.CreateMaskTexture and v.portrait.AddMaskTexture then
        local mask = token:CreateMaskTexture()
        if mask then
            mask:SetAllPoints(v.portrait)
            mask:SetTexture(A.PortraitMask(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            v.portrait:AddMaskTexture(mask)
        end
    end
    v.rim = token:CreateTexture(nil, "ARTWORK", nil, 3)
    v.rim:SetAllPoints()
    v.rim:SetTexture(TEX .. "token_rim")
    v.ring = token:CreateTexture(nil, "ARTWORK", nil, 4)
    v.ring:SetAllPoints()
    v.ring:SetTexture(TEX .. "token_ring")
    v.shine = token:CreateTexture(nil, "ARTWORK", nil, 5)
    v.shine:SetAllPoints()
    v.shine:SetTexture(TEX .. "token_shine")
    v.shine:SetBlendMode("ADD")
    v.shine:SetAlpha(0.35)
    -- Chess-symbol badge, so the piece type is always readable.
    local bs = size * 0.36
    v.badgeBg = token:CreateTexture(nil, "OVERLAY", nil, 1)
    v.badgeBg:SetTexture(TEX .. "dot")
    v.badgeBg:SetSize(bs, bs)
    v.badgeBg:SetPoint("BOTTOMRIGHT", token, "BOTTOMRIGHT", bs * 0.05, -bs * 0.05)
    v.badgeFill = token:CreateTexture(nil, "OVERLAY", nil, 2)
    v.badgeFill:SetPoint("TOPLEFT", v.badgeBg, "TOPLEFT", bs * 0.12, -bs * 0.10)
    v.badgeFill:SetPoint("BOTTOMRIGHT", v.badgeBg, "BOTTOMRIGHT", -bs * 0.12, bs * 0.14)
    v.badgeLine = token:CreateTexture(nil, "OVERLAY", nil, 3)
    v.badgeLine:SetAllPoints(v.badgeFill)

    local inset = floor(size * 0.04)
    v.fill = v:CreateTexture(nil, "ARTWORK", nil, 1)
    v.fill:SetPoint("TOPLEFT", inset, -inset)
    v.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
    v.line = v:CreateTexture(nil, "ARTWORK", nil, 2)
    v.line:SetAllPoints(v.fill)
    v.letter = v:CreateFontString(nil, "OVERLAY")
    v.letter:SetFont(FONT, floor(size * 0.6), "OUTLINE")
    v.letter:SetPoint("CENTER")

    v.SetPiece = SetPiece
    v:Hide()
    return v
end

------------------------------------------------------------------------
-- Board helpers
------------------------------------------------------------------------
local function ClearSelection(board)
    board.sel = nil
    board.targets = nil
    if board.promo then board.promo:Hide() end
end

local function SquareAt(board, col, row)
    if board.flipped then
        return E.Sq(7 - col, row)
    end
    return E.Sq(col, 7 - row)
end

-- Top-left offset of a square inside the board.
local function SquareOffset(board, sq)
    local file, rank = E.FileOf(sq), E.RankOf(sq)
    local col, row
    if board.flipped then
        col, row = 7 - file, rank
    else
        col, row = file, 7 - rank
    end
    return col * board.size, -row * board.size
end

local function Refresh(board)
    local g = G.current
    local pos = g and g.pos or startPos
    local theme = P.Theme()
    local showLegal = ns.db.settings.showLegal
    local grain = theme.texture and A.ART[theme.texture]
    if grain and not A.HasFile(grain) then grain = nil end
    board.checkSq = nil
    if g and E.InCheck(pos) and g.state == "active" then board.checkSq = pos.ks[pos.turn] end
    local hidden = board.hidden or {}

    for row = 0, 7 do
        for col = 0, 7 do
            local cell = board.cells[row * 8 + col + 1]
            local sq = SquareAt(board, col, row)
            cell.sq = sq
            board.cellAt[sq] = cell
            local file, rank = E.FileOf(sq), E.RankOf(sq)
            local dark = (file + rank) % 2 == 0
            local c = dark and theme.dark or theme.light
            cell.bg:SetColorTexture(c[1], c[2], c[3], 1)
            if grain then
                cell.grain:SetTexture(grain)
                -- Different texture regions per square so the grain does not repeat.
                local u, v = (file % 4) * 0.25, (rank % 4) * 0.25
                cell.grain:SetTexCoord(u, u + 0.25, v, v + 0.25)
                cell.grain:SetAlpha(dark and 0.18 or 0.12)
                cell.grain:Show()
            else
                cell.grain:Hide()
            end

            if sq == board.sel then
                cell.hl:SetColorTexture(0.30, 0.85, 0.30, 0.45)
                cell.hl:Show()
                cell.glow:Show()
            elseif sq == board.checkSq then
                cell.hl:SetColorTexture(0.95, 0.12, 0.08, 0.60)
                cell.hl:Show()
                cell.glow:Hide()
            elseif g and (sq == g.lastFrom or sq == g.lastTo) then
                cell.hl:SetColorTexture(1.00, 0.85, 0.25, 0.32)
                cell.hl:Show()
                cell.glow:Hide()
            else
                cell.hl:Hide()
                cell.glow:Hide()
            end

            local piece = pos.b[sq]
            if hidden[sq] then
                cell.view:Hide()
            else
                cell.view:SetPiece(piece, g)
            end

            local target = showLegal and board.targets and board.targets[sq]
            if target then
                if piece ~= 0 then
                    cell.ring:Show(); cell.dot:Hide()
                else
                    cell.dot:Show(); cell.ring:Hide()
                end
            else
                cell.dot:Hide(); cell.ring:Hide()
            end

            if col == 0 then
                cell.rankLabel:SetText(rank + 1)
                cell.rankLabel:Show()
            else
                cell.rankLabel:Hide()
            end
            if row == 7 then
                cell.fileLabel:SetText(string.sub(FILES, file + 1, file + 1))
                cell.fileLabel:Show()
            else
                cell.fileLabel:Hide()
            end
        end
    end
end

local function ShowPromotion(board, moves)
    local promo = board.promo
    local g = G.current
    local white = g.pos.turn == 1
    local base = string.sub(E.MoveToUCI(moves[1]), 1, 4)
    for i = 1, 4 do
        local btn = promo.buttons[i]
        local t = PROMO_ORDER[i]
        btn.view:SetPiece(white and t or -t, g)
        btn.uci = base .. PROMO_CHAR[t]
        local army = A.ArmyFor(white and 1 or -1, g)
        btn.label:SetText(A.UnitName(army, t))
    end
    promo:Show()
end

local function OnCellClick(board, cell, button)
    local g = G.current
    if button == "RightButton" or not g or not G.CanMove() then
        ClearSelection(board)
        Refresh(board)
        return
    end
    local sq = cell.sq
    if board.sel and board.targets and board.targets[sq] then
        local moves = board.targets[sq]
        if #moves > 1 then
            board.sel = nil
            board.targets = nil
            ShowPromotion(board, moves)
            Refresh(board)
        else
            ClearSelection(board)
            G.Move(E.MoveToUCI(moves[1]))
        end
        return
    end
    ClearSelection(board)
    local piece = g.pos.b[sq]
    if piece ~= 0 and (piece > 0) == (g.pos.turn > 0) then
        local legal = E.GenLegal(g.pos)
        local targets, any = {}, false
        for i = 1, #legal do
            local m = legal[i]
            if E.MFrom(m) == sq then
                local to = E.MTo(m)
                targets[to] = targets[to] or {}
                table.insert(targets[to], m)
                any = true
            end
        end
        if any then
            board.sel = sq
            board.targets = targets
            A.Play("select")
            -- A little lift on the selected token.
            local view = cell.view
            A.Tween(0.12, function(p) view:SetScale(1 + 0.08 * p) end, nil, A.Ease.outCubic)
        end
    end
    for i = 1, #board.cells do board.cells[i].view:SetScale(1) end
    if board.sel then
        for i = 1, #board.cells do
            if board.cells[i].sq == board.sel then board.cells[i].view:SetScale(1.08) end
        end
    end
    Refresh(board)
end

------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------
-- Floating combat-text style message over a square (or the board centre when sq is nil).
local function FloatText(board, sq, text, r, g, b, big)
    local fx = board.fx
    local fs = fx:CreateFontString(nil, "OVERLAY")
    fs:SetFont(A.TitleFont(), big and 30 or 15, "OUTLINE")
    fs:SetTextColor(r, g, b)
    fs:SetShadowOffset(2, -2)
    fs:SetText(text)
    local x, y
    if sq then
        x, y = SquareOffset(board, sq)
        x, y = x + board.size / 2, y - board.size * 0.2
    else
        x, y = board.size * 4, -board.size * 3.6
    end
    fs:SetPoint("CENTER", fx, "TOPLEFT", x, y)
    local rise = big and 0 or 34
    local dur = big and 1.4 or 1.3
    A.Tween(dur, function(p)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", fx, "TOPLEFT", x, y + rise * p)
        if big then
            local s = p < 0.2 and (0.5 + 2.5 * p * (1 - p) * 2) or 1
            fs:SetTextHeight(floor(30 * math.min(1.25, s)))
        end
        fs:SetAlpha(p < 0.7 and 1 or (1 - (p - 0.7) / 0.3))
    end, function()
        fs:Hide()
    end)
end
B.FloatText = FloatText

-- A burst of light on a square (additive), optionally tinted.
local function Burst(board, sq, r, g, b, scale)
    local fx = board.fx
    local x, y = SquareOffset(board, sq)
    local tex = fx:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(TEX .. "burst")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(r, g, b)
    local size = board.size
    tex:SetPoint("CENTER", fx, "TOPLEFT", x + size / 2, y - size / 2)
    A.Tween(0.45, function(p)
        local s = size * (0.6 + (scale or 1.4) * p)
        tex:SetSize(s, s)
        tex:SetAlpha(1 - p)
    end, function() tex:Hide() end, A.Ease.outCubic)
end

-- A sword-slash streak across a square.
local function Slash(board, sq)
    local fx = board.fx
    local x, y = SquareOffset(board, sq)
    local tex = fx:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(TEX .. "slash")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(1, 0.85, 0.7)
    local size = board.size
    tex:SetPoint("CENTER", fx, "TOPLEFT", x + size / 2, y - size / 2)
    A.Tween(0.35, function(p)
        local s = size * (0.8 + 0.6 * p)
        tex:SetSize(s, s)
        tex:SetAlpha(p < 0.5 and 1 or (1 - (p - 0.5) / 0.5))
    end, function() tex:Hide() end, A.Ease.outCubic)
end

local function ClearFx(board)
    for _, tw in ipairs(board.anims or {}) do tw:Cancel() end
    board.anims = {}
    board.hidden = nil
    for _, m in ipairs(board.movers) do m:Hide(); m:SetScale(1); m:SetAlpha(1) end
end

local function Mover(board, i)
    local m = board.movers[i]
    m:SetScale(1)
    m:SetAlpha(1)
    return m
end

-- Puts a view's centre over the square whose top-left is (x, y), at the given scale.
-- Anchor offsets are in the view's own (scaled) units, hence the division.
local function PlaceAt(board, view, x, y, scale)
    scale = scale or 1
    local half = board.size / 2
    view:SetScale(scale)
    view:ClearAllPoints()
    view:SetPoint("CENTER", board.fx, "TOPLEFT", (x + half) / scale, (y - half) / scale)
end

-- Sounds for a move, used whether or not the board is visible.
function B.MoveSounds(g, check)
    local last = g.last
    if not last then return end
    if last.victim ~= 0 then
        A.Play("capture")
        local army = A.ArmyFor(last.victim > 0 and 1 or -1, g)
        A.Play("death" .. army)
    elseif last.castle then
        A.Play("castle")
    else
        A.Play("move")
    end
    if last.promo then A.Play("promote") end
    if check then A.Play("check") end
end

-- Animates the last move of game g: slide, capture, promotion, check.
local function AnimateLast(board, g, check)
    ClearFx(board)
    local last = g.last
    if not last then
        B.MoveSounds(g, check)
        return
    end
    local size = board.size
    local hidden = { [last.to] = true }
    local slides = { { from = last.from, to = last.to, piece = (last.promo and last.mover or last.piece) } }
    if last.castle then
        local rf = (last.castle == 2) and (last.to + 1) or (last.to - 2)
        local rt = (last.castle == 2) and (last.to - 1) or (last.to + 1)
        hidden[rt] = true
        slides[2] = { from = rf, to = rt, piece = 4 * last.mover }
    end
    board.hidden = hidden
    Refresh(board)

    -- The victim stays visible where it stood until the attacker arrives.
    local victimView
    if last.victim ~= 0 then
        victimView = Mover(board, 3)
        victimView:SetPiece(last.victim, g)
        PlaceAt(board, victimView, SquareOffset(board, last.victimSq))
    end

    for i, s in ipairs(slides) do
        local m = Mover(board, i)
        m:SetPiece(s.piece, g)
        local x1, y1 = SquareOffset(board, s.from)
        local x2, y2 = SquareOffset(board, s.to)
        PlaceAt(board, m, x1, y1)
        local final = i == 1
        local tw = A.Tween(0.24, function(p)
            -- Slides across with a lift in the middle, as if picked up and set down.
            PlaceAt(board, m, x1 + (x2 - x1) * p, y1 + (y2 - y1) * p, 1 + 0.15 * sin(p * math.pi))
        end, function()
            m:Hide()
            hidden[s.to] = nil
            if not final then
                Refresh(board)
                return
            end
            Refresh(board)
            B.MoveSounds(g, check)
            if last.victim ~= 0 and victimView then
                local army = A.ArmyFor(last.victim > 0 and 1 or -1, g)
                local info = A.ARMIES[army]
                Slash(board, last.victimSq)
                Burst(board, last.victimSq, 1, 0.25, 0.1, 1.2)
                FloatText(board, last.victimSq, A.UnitName(army, abs(last.victim)) .. " slain!", info.color[1], info.color[2], info.color[3])
                local vx, vy = SquareOffset(board, last.victimSq)
                -- The fallen piece swells, flashes red and fades away.
                victimView.portrait:SetVertexColor(1, 0.35, 0.3)
                table.insert(board.anims, A.Tween(0.5, function(p)
                    PlaceAt(board, victimView, vx, vy, 1 + 0.6 * p)
                    victimView:SetAlpha(1 - p)
                end, function()
                    victimView:Hide()
                    victimView.portrait:SetVertexColor(1, 1, 1)
                end, A.Ease.outCubic))
            end
            if last.promo then
                local army = A.ArmyFor(last.mover, g)
                Burst(board, last.to, 1, 0.8, 0.2, 1.8)
                FloatText(board, last.to, "Promoted: " .. A.UnitName(army, last.promo) .. "!", 1, 0.82, 0)
            end
            if check and g.state == "active" then
                FloatText(board, nil, "CHECK!", 1, 0.2, 0.1, true)
            end
            -- The landing piece settles with a small bounce.
            local cell = board.cellAt[last.to]
            if cell then
                table.insert(board.anims, A.Tween(0.18, function(p)
                    cell.view:SetScale(1 + 0.10 * (1 - p))
                end, nil, A.Ease.outCubic))
            end
        end, A.Ease.outCubic)
        table.insert(board.anims, tw)
    end
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------
function B.Create(parent, size)
    local board = CreateFrame("Frame", nil, parent)
    board:SetSize(size * 8, size * 8)
    board.size = size
    board.cells = {}
    board.cellAt = {}
    board.flipped = false
    board.anims = {}

    for row = 0, 7 do
        for col = 0, 7 do
            local cell = CreateFrame("Button", nil, board)
            cell:SetSize(size, size)
            cell:SetPoint("TOPLEFT", board, "TOPLEFT", col * size, -row * size)

            cell.bg = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
            cell.bg:SetAllPoints()
            cell.grain = cell:CreateTexture(nil, "BACKGROUND", nil, 2)
            cell.grain:SetAllPoints()
            -- A light, desaturated overlay: adds stone grain without darkening the colours.
            cell.grain:SetBlendMode("BLEND")
            if cell.grain.SetDesaturated then cell.grain:SetDesaturated(true) end
            cell.hl = cell:CreateTexture(nil, "BORDER")
            cell.hl:SetAllPoints()
            cell.hl:Hide()
            cell.glow = cell:CreateTexture(nil, "BORDER", nil, 2)
            cell.glow:SetTexture(TEX .. "burst")
            cell.glow:SetBlendMode("ADD")
            cell.glow:SetVertexColor(0.4, 1, 0.4, 0.8)
            cell.glow:SetAllPoints()
            cell.glow:Hide()
            local hover = cell:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.10)

            cell.view = B.CreatePieceView(cell, size)
            cell.view:SetPoint("CENTER")

            -- Markers and labels above the piece.
            local top = CreateFrame("Frame", nil, cell)
            top:SetAllPoints()
            top:SetFrameLevel(cell:GetFrameLevel() + 5)
            cell.dot = top:CreateTexture(nil, "OVERLAY")
            cell.dot:SetTexture(TEX .. "dot")
            cell.dot:SetSize(size * 0.30, size * 0.30)
            cell.dot:SetPoint("CENTER")
            cell.dot:SetVertexColor(0.1, 0.06, 0.02, 0.45)
            cell.dot:Hide()
            cell.ring = top:CreateTexture(nil, "OVERLAY")
            cell.ring:SetTexture(TEX .. "ring")
            cell.ring:SetAllPoints()
            cell.ring:SetVertexColor(1, 0.25, 0.1, 0.65)
            cell.ring:Hide()
            cell.rankLabel = top:CreateFontString(nil, "OVERLAY")
            cell.rankLabel:SetFont(FONT, 9, "OUTLINE")
            cell.rankLabel:SetPoint("TOPLEFT", 2, -2)
            cell.rankLabel:SetTextColor(1, 0.9, 0.7, 0.8)
            cell.fileLabel = top:CreateFontString(nil, "OVERLAY")
            cell.fileLabel:SetFont(FONT, 9, "OUTLINE")
            cell.fileLabel:SetPoint("BOTTOMRIGHT", -2, 2)
            cell.fileLabel:SetTextColor(1, 0.9, 0.7, 0.8)

            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            cell:SetScript("OnClick", function(_, button) OnCellClick(board, cell, button) end)
            board.cells[row * 8 + col + 1] = cell
        end
    end

    -- Effects layer above everything, ignoring the mouse.
    local fx = CreateFrame("Frame", nil, board)
    fx:SetAllPoints()
    fx:SetFrameLevel(board:GetFrameLevel() + 20)
    fx:EnableMouse(false)
    board.fx = fx
    board.movers = {}
    for i = 1, 3 do
        local m = B.CreatePieceView(fx, size)
        m:SetFrameLevel(fx:GetFrameLevel() + (i == 3 and 1 or 2))
        board.movers[i] = m
    end

    -- Promotion picker
    local promo = CreateFrame("Frame", nil, board)
    promo:SetSize(size * 4 + 40, size + 44)
    promo:SetPoint("CENTER")
    promo:SetFrameLevel(board:GetFrameLevel() + 30)
    promo:EnableMouse(true)
    local bg = promo:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.04, 0.02, 0.95)
    local ptitle = promo:CreateFontString(nil, "OVERLAY")
    ptitle:SetFont(A.TitleFont(), 15, "OUTLINE")
    ptitle:SetTextColor(1, 0.82, 0)
    ptitle:SetPoint("TOP", 0, -6)
    ptitle:SetText("Promote your pawn")
    promo.buttons = {}
    for i = 1, 4 do
        local btn = CreateFrame("Button", nil, promo)
        btn:SetSize(size, size)
        btn:SetPoint("BOTTOMLEFT", promo, "BOTTOMLEFT", 8 + (i - 1) * (size + 8), 8)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetTexture(TEX .. "burst")
        hover:SetBlendMode("ADD")
        hover:SetVertexColor(1, 0.8, 0.3, 0.8)
        btn.view = B.CreatePieceView(btn, size)
        btn.view:SetPoint("CENTER")
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("TOP", btn, "BOTTOM", 0, 14)
        btn:SetScript("OnClick", function(self)
            promo:Hide()
            if self.uci then G.Move(self.uci) end
        end)
        promo.buttons[i] = btn
    end
    promo:Hide()
    board.promo = promo

    -- Pulse the king's square while in check.
    local t = 0
    board:SetScript("OnUpdate", function(self, elapsed)
        if not self.checkSq then return end
        t = t + elapsed
        local cell = self.cellAt[self.checkSq]
        if cell then cell.hl:SetAlpha(0.45 + 0.35 * sin(t * 6)) end
    end)

    board.Refresh = Refresh
    board.ClearSelection = ClearSelection
    board.AnimateLast = function(self, g, check)
        AnimateLast(self, g, check)
    end
    board.ClearFx = ClearFx
    board.FloatText = FloatText
    return board
end
