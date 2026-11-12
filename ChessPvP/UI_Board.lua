-- ChessPvP: the board widget (squares, pieces, highlights, click-to-move, promotion picker).
local _, ns = ...

local B = {}
ns.Board = B

local E, G, P = ns.Engine, ns.Game, ns.Profile
local TEX = "Interface\\AddOns\\ChessPvP\\Textures\\"
local PIECE_NAME = { "P", "N", "B", "R", "Q", "K" }
local PROMO_ORDER = { 5, 4, 3, 2 } -- queen, rook, bishop, knight
local PROMO_CHAR = { [2] = "n", [3] = "b", [4] = "r", [5] = "q" }
local FILES = "abcdefgh"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local startPos = E.New()

-- Draws one piece (two tinted layers, or a letter) into the given textures.
local function ShowPiece(fill, line, letter, piece, set)
    if piece == 0 then
        fill:Hide(); line:Hide(); letter:Hide()
        return
    end
    local white = piece > 0
    local t = white and piece or -piece
    local fc = white and set.wFill or set.bFill
    local lc = white and set.wLine or set.bLine
    if set.letters then
        fill:Hide(); line:Hide()
        letter:SetText(PIECE_NAME[t])
        if white then
            letter:SetTextColor(1, 1, 1)
        else
            letter:SetTextColor(0.05, 0.05, 0.05)
        end
        letter:Show()
    else
        letter:Hide()
        fill:SetTexture(TEX .. PIECE_NAME[t] .. "_fill")
        fill:SetVertexColor(fc[1], fc[2], fc[3])
        line:SetTexture(TEX .. PIECE_NAME[t] .. "_line")
        line:SetVertexColor(lc[1], lc[2], lc[3])
        fill:Show(); line:Show()
    end
end
B.ShowPiece = ShowPiece

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

local function Refresh(board)
    local g = G.current
    local pos = g and g.pos or startPos
    local theme = P.Theme()
    local set = P.PieceSet()
    local showLegal = ns.db.settings.showLegal
    local checkSq
    if g and E.InCheck(pos) then checkSq = pos.ks[pos.turn] end

    for row = 0, 7 do
        for col = 0, 7 do
            local cell = board.cells[row * 8 + col + 1]
            local sq = SquareAt(board, col, row)
            cell.sq = sq
            local file, rank = E.FileOf(sq), E.RankOf(sq)
            local c = ((file + rank) % 2 == 0) and theme.dark or theme.light
            cell.bg:SetColorTexture(c[1], c[2], c[3], 1)

            if sq == board.sel then
                cell.hl:SetColorTexture(0.25, 0.85, 0.30, 0.55)
                cell.hl:Show()
            elseif sq == checkSq then
                cell.hl:SetColorTexture(0.95, 0.15, 0.10, 0.60)
                cell.hl:Show()
            elseif g and (sq == g.lastFrom or sq == g.lastTo) then
                cell.hl:SetColorTexture(1.00, 0.90, 0.20, 0.40)
                cell.hl:Show()
            else
                cell.hl:Hide()
            end

            local piece = pos.b[sq]
            ShowPiece(cell.fill, cell.line, cell.letter, piece, set)

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

            -- Coordinates along the left and bottom edges.
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
    local set = P.PieceSet()
    local base = string.sub(E.MoveToUCI(moves[1]), 1, 4)
    for i = 1, 4 do
        local btn = promo.buttons[i]
        local t = PROMO_ORDER[i]
        ShowPiece(btn.fill, btn.line, btn.letter, white and t or -t, set)
        btn.uci = base .. PROMO_CHAR[t]
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
        end
    end
    Refresh(board)
end

function B.Create(parent, size)
    local board = CreateFrame("Frame", nil, parent)
    board:SetSize(size * 8, size * 8)
    board.cells = {}
    board.flipped = false
    local inset = math.floor(size * 0.04)

    for row = 0, 7 do
        for col = 0, 7 do
            local cell = CreateFrame("Button", nil, board)
            cell:SetSize(size, size)
            cell:SetPoint("TOPLEFT", board, "TOPLEFT", col * size, -row * size)

            cell.bg = cell:CreateTexture(nil, "BACKGROUND")
            cell.bg:SetAllPoints()
            cell.hl = cell:CreateTexture(nil, "BORDER")
            cell.hl:SetAllPoints()
            cell.hl:Hide()

            cell.fill = cell:CreateTexture(nil, "ARTWORK", nil, 1)
            cell.fill:SetPoint("TOPLEFT", inset, -inset)
            cell.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
            cell.line = cell:CreateTexture(nil, "ARTWORK", nil, 2)
            cell.line:SetPoint("TOPLEFT", inset, -inset)
            cell.line:SetPoint("BOTTOMRIGHT", -inset, inset)

            cell.dot = cell:CreateTexture(nil, "OVERLAY")
            cell.dot:SetTexture(TEX .. "dot")
            cell.dot:SetSize(size * 0.34, size * 0.34)
            cell.dot:SetPoint("CENTER")
            cell.dot:SetVertexColor(0, 0, 0, 0.35)
            cell.dot:Hide()
            cell.ring = cell:CreateTexture(nil, "OVERLAY")
            cell.ring:SetTexture(TEX .. "ring")
            cell.ring:SetAllPoints()
            cell.ring:SetVertexColor(0, 0, 0, 0.40)
            cell.ring:Hide()

            cell.letter = cell:CreateFontString(nil, "OVERLAY")
            cell.letter:SetFont(FONT, math.floor(size * 0.6), "OUTLINE")
            cell.letter:SetPoint("CENTER")
            cell.letter:Hide()

            cell.rankLabel = cell:CreateFontString(nil, "OVERLAY")
            cell.rankLabel:SetFont(FONT, 9, "OUTLINE")
            cell.rankLabel:SetPoint("TOPLEFT", 2, -2)
            cell.rankLabel:SetTextColor(1, 1, 1, 0.8)
            cell.fileLabel = cell:CreateFontString(nil, "OVERLAY")
            cell.fileLabel:SetFont(FONT, 9, "OUTLINE")
            cell.fileLabel:SetPoint("BOTTOMRIGHT", -2, 2)
            cell.fileLabel:SetTextColor(1, 1, 1, 0.8)

            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            cell:SetScript("OnClick", function(_, button) OnCellClick(board, cell, button) end)
            board.cells[row * 8 + col + 1] = cell
        end
    end

    -- Promotion picker
    local promo = CreateFrame("Frame", nil, board)
    promo:SetSize(size * 4 + 16, size + 16)
    promo:SetPoint("CENTER")
    promo:SetFrameLevel(board:GetFrameLevel() + 10)
    promo:EnableMouse(true)
    local bg = promo:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
    promo.buttons = {}
    for i = 1, 4 do
        local btn = CreateFrame("Button", nil, promo)
        btn:SetSize(size, size)
        btn:SetPoint("LEFT", promo, "LEFT", 8 + (i - 1) * size, 0)
        local back = btn:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0.55, 0.55, 0.55, 1)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.25)
        btn.fill = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        btn.fill:SetAllPoints()
        btn.line = btn:CreateTexture(nil, "ARTWORK", nil, 2)
        btn.line:SetAllPoints()
        btn.letter = btn:CreateFontString(nil, "OVERLAY")
        btn.letter:SetFont(FONT, math.floor(size * 0.6), "OUTLINE")
        btn.letter:SetPoint("CENTER")
        btn:SetScript("OnClick", function(self)
            promo:Hide()
            if self.uci then G.Move(self.uci) end
        end)
        promo.buttons[i] = btn
    end
    promo:Hide()
    board.promo = promo

    board.Refresh = Refresh
    board.ClearSelection = ClearSelection
    return board
end
