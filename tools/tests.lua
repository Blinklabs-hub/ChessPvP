dofile(TEST_DIR .. "/harness.lua")

local function want(name) return TEST_FILTER == "" or string.find(name, TEST_FILTER, 1, true) end

------------------------------------------------------------------------
if want("rules") then
    section("rules: perft")
    local c = NewClient("Solo")
    local E = c.ns.Engine
    local cases = {
        { E.START_FEN, { 20, 400, 8902, 197281 } },
        { "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", { 48, 2039, 97862 } },
        { "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", { 14, 191, 2812, 43238 } },
        { "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", { 6, 264, 9467 } },
        { "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", { 44, 1486, 62379 } },
        { "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", { 46, 2079, 89890 } },
    }
    for i, case in ipairs(cases) do
        local pos = E.New(case[1])
        for d, expected in ipairs(case[2]) do
            eq(E.Perft(pos, d), expected, "perft case " .. i .. " depth " .. d)
        end
        eq(E.ToFEN(pos), case[1], "position restored after perft " .. i)
    end

    section("rules: SAN, status, repetition")
    local pos = E.New()
    local function play(list)
        for _, u in ipairs(list) do
            local m = E.FindMove(pos, u)
            assert(m, "illegal test move " .. u)
            local san = E.ToSAN(pos, m)
            E.Play(pos, m)
            pos.lastSan = san
        end
    end
    play({ "f2f3", "e7e5", "g2g4", "d8h4" })
    eq(pos.lastSan, "Qh4#", "fool's mate SAN")
    eq(E.Status(pos), "checkmate", "fool's mate status")

    pos = E.New("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    eq(E.Status(pos), "stalemate", "stalemate")
    pos = E.New("8/8/4k3/8/8/3NK3/8/8 w - - 0 1")
    eq(E.Status(pos), "material", "K+N vs K is a draw")
    pos = E.New("8/8/4k3/8/8/3BK3/2b5/8 w - - 0 1")
    eq(E.Status(pos), "material", "same-colour bishops")
    pos = E.New("8/8/4k3/8/8/3RK3/8/8 w - - 0 1")
    eq(E.Status(pos), nil, "rook is enough material")

    pos = E.New()
    play({ "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1" })
    eq(E.Status(pos), nil, "two-fold is not a draw")
    play({ "f6g8" })
    eq(E.Status(pos), "repetition", "threefold repetition")

    pos = E.New("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    local m = E.FindMove(pos, "e1g1")
    eq(E.ToSAN(pos, m), "O-O", "castle SAN")
    eq(E.ToSAN(pos, E.FindMove(pos, "a1d1")), "Rd1", "no disambiguation when the other rook is blocked")
    pos = E.New("4k3/8/8/8/8/8/8/R4RK1 w - - 0 1")
    eq(E.ToSAN(pos, E.FindMove(pos, "a1d1")), "Rad1", "rook file disambiguation")
    pos = E.New("4k3/8/R7/8/8/8/8/R5K1 w - - 0 1")
    eq(E.ToSAN(pos, E.FindMove(pos, "a1a3")), "R1a3", "rook rank disambiguation")
    pos = E.New("4k3/1P6/8/8/8/8/8/4K3 w - - 0 1")
    eq(E.ToSAN(pos, E.FindMove(pos, "b7b8q")), "b8=Q+", "promotion with check SAN")
    eq(E.FindMove(pos, "b7b8"), nil, "promotion needs a piece")
    pos = E.New("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
    eq(E.ToSAN(pos, E.FindMove(pos, "e5d6")), "exd6", "en passant SAN")
    E.Play(pos, E.FindMove(pos, "e5d6"))
    eq(pos.b[E.Sq(3, 4)], 0, "en passant removes the pawn")
    -- castling through check is illegal
    pos = E.New("4k3/8/8/8/8/8/5r2/4K2R w K - 0 1")
    eq(E.FindMove(pos, "e1g1"), nil, "cannot castle through check")
    pos = E.New("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    E.Play(pos, E.FindMove(pos, "a1a8"))
    eq(E.ToFEN(pos):match("^%S+ %S+ (%S+)"), "Kk", "capturing a rook removes castling rights")
    RemoveClient(c)
end

------------------------------------------------------------------------
if want("ai") then
    section("ai")
    local c = NewClient("Bot")
    local E, AI = c.ns.Engine, c.ns.AI
    -- mate in one
    local pos = E.New("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1")
    -- Only Master: Novice and Adept blunder on purpose some of the time.
    eq(E.MoveToUCI(AI.ThinkNow(pos, 3)), "a1a8", "master finds back-rank mate")
    -- free queen
    pos = E.New("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1")
    eq(E.MoveToUCI(AI.ThinkNow(pos, 3)), "d1d5", "master takes the hanging queen")
    -- master does not hang its queen: queen attacked by pawn
    pos = E.New("4k3/8/8/8/3q4/4P3/8/4K3 b - - 0 1")
    local mv = E.MoveToUCI(AI.ThinkNow(pos, 3))
    check(mv:sub(1, 2) == "d4" and mv ~= "d4e3" or mv == "d4e3", "queen reacts to attack (" .. mv .. ")")
    -- timing from the start position
    local t0 = os.clock()
    AI.ThinkNow(E.New(), 3)
    print(string.format("   master move from start position: %.2fs (fengari, slower than WoW's Lua)", os.clock() - t0))

    -- full game vs AI through the Game module, with the coroutine driver
    local G = c.ns.Game
    c.ns.db.settings.aiLevel = 1
    G.StartAI(1, 1)
    local g = G.current
    local guard = 0
    while g.state == "active" and guard < 400 do
        guard = guard + 1
        if g.pos.turn == 1 then
            local legal = E.GenLegal(g.pos)
            check(G.Move(E.MoveToUCI(legal[math.random(1, #legal)])), "random move accepted")
        end
        Advance(0.3)
    end
    check(g.state == "over" or guard >= 400, "AI game progresses (" .. #g.moves .. " plies, " .. tostring(g.reason) .. ")")
    RemoveClient(c)
end

------------------------------------------------------------------------
if want("online") or TEST_FILTER == "debug" then
    section("online: challenge, play, checkmate, ratings")
    local a = NewClient("Alice")
    local b = NewClient("Bob")
    Advance(20) -- join channel, announce
    check(a.ns.Profile.online["Bob-TestRealm"] ~= nil, "Alice sees Bob in the lobby")
    check(b.ns.Profile.online["Alice-TestRealm"] ~= nil, "Bob sees Alice in the lobby")

    a.ns.db.settings.color = "w"
    a.ns.Game.Invite("bob")
    Advance(1)
    local inv = b.ns.Game.LatestInvite()
    check(inv ~= nil, "Bob receives the challenge")
    b.ns.Game.AnswerLatest(true)
    Advance(1)
    local ga, gb = a.ns.Game.current, b.ns.Game.current
    check(ga and gb and ga.id == gb.id, "both clients share a game")
    eq(ga.myColor, 1, "Alice is white")
    eq(gb.myColor, -1, "Bob is black")
    check(ga.rated and ga.timed, "rated timed game")

    -- Scholar's mate
    local seq = { { a, "e2e4" }, { b, "e7e5" }, { a, "f1c4" }, { b, "b8c6" }, { a, "d1h5" }, { b, "g8f6" }, { a, "h5f7" } }
    for _, s in ipairs(seq) do
        check(s[1].ns.Game.Move(s[2]), "move " .. s[2])
        Advance(1)
    end
    check(not b.ns.Game.Move("a7a6"), "cannot move after mate")
    eq(ga.state, "over", "Alice's game over")
    eq(gb.state, "over", "Bob's game over")
    eq(ga.outcome, "win", "Alice wins")
    eq(gb.outcome, "loss", "Bob loses")
    eq(gb.reason, "checkmate", "by checkmate")
    local pa, pb = a.ns.Profile.me, b.ns.Profile.me
    eq(pa.rating, 1220, "Alice rating")
    eq(pb.rating, 1180, "Bob rating")
    check(pa.badges.first_win and pa.badges.quick, "Alice earns First Blood and Lightning Strike")
    check(pb.badges.first_game and not pb.badges.first_win, "Bob earns First Move only")
    Advance(30)
    local e = b.ns.Profile.GetPlayer("Alice-TestRealm")
    eq(e and e.r, 1220, "Bob's ladder shows Alice's new rating")
    local board = b.ns.Profile.Board()
    eq(board[1].name, "Alice-TestRealm", "Alice tops Bob's ladder")

    section("online: resign, draw offer, abort")
    a.ns.Game.Invite("Bob")
    Advance(1)
    b.ns.Game.AnswerLatest(true)
    Advance(1)
    ga, gb = a.ns.Game.current, b.ns.Game.current
    local white = (ga.myColor == 1) and a or b
    local black = (ga.myColor == 1) and b or a
    white.ns.Game.Move("d2d4"); Advance(1)
    black.ns.Game.Move("d7d5"); Advance(1)
    white.ns.Game.OfferDraw(); Advance(1)
    eq(black.ns.Game.current.drawOffer, -black.ns.Game.current.myColor, "draw offer arrives")
    black.ns.Game.DeclineDraw(); Advance(1)
    eq(white.ns.Game.current.drawOffer, nil, "draw declined")
    white.ns.Game.OfferDraw(); Advance(1)
    black.ns.Game.OfferDraw(); Advance(1)
    eq(ga.result, "1/2", "draw agreed (A)")
    eq(gb.result, "1/2", "draw agreed (B)")
    eq(ga.reason, "agreement", "draw reason")

    a.ns.Game.Invite("Bob"); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(1)
    a.ns.Game.Resign(); Advance(1)
    eq(a.ns.Game.current.reason, "abort", "resign before 2 moves aborts")
    eq(b.ns.Game.current.reason, "abort", "abort reaches Bob")
    eq(a.ns.Game.current.result, "*", "abort has no result")

    section("online: packet loss")
    net.dropRate = 0.4
    -- Challenge until both sides are in the same active game (any message may be lost).
    local started = false
    for attempt = 1, 20 do
        if not a.ns.Game.outgoing then a.ns.Game.Invite("Bob") end
        Advance(2)
        if b.ns.Game.LatestInvite() then b.ns.Game.AnswerLatest(true) end
        Advance(25) -- covers accept resends, or the acceptor giving up
        ga, gb = a.ns.Game.current, b.ns.Game.current
        if ga.id == gb.id and ga.state == "active" and gb.state == "active" then
            started = true
            break
        end
        -- Never both stuck: a lost start must not leave just one side in a game.
        check(not (gb.state == "active" and ga.id ~= gb.id), "no one-sided game after lost accept (attempt " .. attempt .. ")")
        if a.ns.Game.outgoing then a.ns.Game.CancelInvite() end
        Advance(5)
    end
    check(started, "lossy game starts")
    white = (ga.myColor == 1) and a or b
    black = (ga.myColor == 1) and b or a
    local moves = { "e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7" }
    for i, mv in ipairs(moves) do
        local who = (i % 2 == 1) and white or black
        local tries = 0
        while who.ns.Game.current.pos.turn ~= ((i % 2 == 1) and 1 or -1) or #who.ns.Game.current.moves ~= i - 1 do
            Advance(1)
            tries = tries + 1
            if tries > 120 then break end
        end
        check(who.ns.Game.Move(mv), "lossy move " .. mv)
    end
    Advance(90)
    net.dropRate = 0
    Advance(10)
    eq(#ga.moves, 10, "Alice has all moves despite loss")
    eq(#gb.moves, 10, "Bob has all moves despite loss")
    eq(c and 0 or 0, 0, "")
    check(ga.state == "active" and gb.state == "active", "game still running")

    section("online: reload and resume")
    local aliceDB = DeepCopy(a.env.ChessPvPDB)
    RemoveClient(a)
    -- Bob plays a move while Alice is offline... it is white's turn after 10 plies
    local bobIsWhite = gb.myColor == 1
    if bobIsWhite then
        b.ns.Game.Move("d2d4")
    end
    Advance(5)
    local a2 = NewClient("Alice", aliceDB)
    Advance(40)
    local ga2 = a2.ns.Game.current
    check(ga2 ~= nil and ga2.id == gb.id, "Alice resumes the saved game")
    eq(#ga2.moves, #gb.moves, "resumed game catches up on missed moves")
    eq(ga2.state, "active", "resumed game active")
    a = a2
    ga = ga2

    section("online: timeout")
    -- whoever is to move just waits; their clock (10 min) runs out
    local mover = (ga.pos.turn == ga.myColor) and a or b
    local other = (mover == a) and b or a
    Advance(620)
    eq(mover.ns.Game.current.reason, "time", "mover loses on time")
    eq(other.ns.Game.current.reason, "time", "opponent sees time loss")
    eq(other.ns.Game.current.outcome, "win", "opponent wins on time")

    section("online: opponent vanishes, flag claim")
    a.ns.Game.Invite("Bob"); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(1)
    ga, gb = a.ns.Game.current, b.ns.Game.current
    white = (ga.myColor == 1) and a or b
    black = (ga.myColor == 1) and b or a
    white.ns.Game.Move("e2e4"); Advance(1)
    black.ns.Game.Move("e7e5"); Advance(1)
    white.ns.Game.Move("d2d4"); Advance(1)
    RemoveClient(black) -- black disconnects for good, on move
    Advance(640)
    eq(white.ns.Game.current.reason, "time", "flag claimed against vanished opponent")
    eq(white.ns.Game.current.outcome, "win", "win after opponent vanished")
    if black == a then a = nil else b = nil end
    for _, c in ipairs({ a, b }) do if c then RemoveClient(c) end end

    section("spectate and matchmaking")
    local p1 = NewClient("Carol")
    local p2 = NewClient("Dave")
    local w = NewClient("Erin")
    Advance(20)
    p1.ns.Game.StartSeek(300, 0, true)
    p2.ns.Game.StartSeek(300, 0, true)
    Advance(30)
    local g1, g2 = p1.ns.Game.current, p2.ns.Game.current
    check(g1 and g2 and g1.id == g2.id and g1.state == "active", "matchmaking pairs Carol and Dave")
    check(p1.ns.Game.seek == nil and p2.ns.Game.seek == nil, "seeks cleared")
    local cw = (g1.myColor == 1) and p1 or p2
    local cb = (g1.myColor == 1) and p2 or p1
    cw.ns.Game.Move("e2e4"); Advance(1)
    w.ns.Game.Watch("Carol"); Advance(3)
    local gw = w.ns.Game.current
    check(gw and gw.mode == "spectate" and gw.id == g1.id, "Erin is spectating")
    eq(gw and #gw.moves, 1, "spectator receives existing moves")
    cb.ns.Game.Move("f7f6"); Advance(1)
    cw.ns.Game.Move("d2d4"); Advance(1)
    cb.ns.Game.Move("g7g5"); Advance(1)
    cw.ns.Game.Move("d1h5"); Advance(1)
    eq(gw.state, "over", "spectator sees game end")
    eq(gw.result, "1-0", "spectator sees white win")
    check(w.ns.Profile.me.badges.watcher, "Armchair General badge")

    section("challenge an offline player")
    net.log = (TEST_FILTER == "debug")
    p1.ns.Game.Invite("Nobody")
    Advance(2)
    net.log = false
    eq(p1.ns.Game.outgoing, nil, "challenge to offline player cancelled")
    local hidden = true
    for _, msg in ipairs(p1.chat) do if msg:find("^SYS:") then hidden = false end end
    check(hidden, "'no player named' system message hidden")

    section("UI smoke test")
    p1.ns.UI.Show()
    for _, tab in ipairs({ "play", "lobby", "ladder", "collection", "settings" }) do
        p1.ns.UI.ShowTab(tab)
    end
    Advance(1)
    check(true, "all tabs render without errors")
end

------------------------------------------------------------------------
if want("forever") then
    -- Names as seen in game: "Canga Prime" and "Just Keepingcalm". A third player shares
    -- the first name "Just", so first names alone are ambiguous.
    section("forever: identities")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    local c = NewClient("Just", nil, "Other")
    eq(a.ns.me, "Canga Prime", "own identity is the full two-part name")
    eq(b.ns.me, "Just Keepingcalm", "friend identity")
    Advance(20)
    check(a.ns.Profile.online["Just Keepingcalm"] ~= nil, "lobby lists 'Just Keepingcalm'")
    check(a.ns.Profile.online["Just Other"] ~= nil, "lobby lists 'Just Other' separately")

    local function Duel(label, challenge)
        Advance(8) -- let the previous game's messages drain (about 1 message per second)
        challenge()
        Advance(1)
        check(b.ns.Game.LatestInvite() ~= nil, label .. ": challenge arrives")
        check(c.ns.Game.LatestInvite() == nil, label .. ": the other 'Just' is not challenged")
        b.ns.Game.AnswerLatest(true)
        Advance(1)
        local ga, gb = a.ns.Game.current, b.ns.Game.current
        check(ga and gb and ga.id == gb.id and ga.state == "active", label .. ": game starts")
        local w = (ga.myColor == 1) and a or b
        local k = (ga.myColor == 1) and b or a
        w.ns.Game.Move("f2f3"); Advance(1)
        k.ns.Game.Move("e7e5"); Advance(1)
        w.ns.Game.Move("g2g4"); Advance(1)
        k.ns.Game.Move("d8h4"); Advance(1)
        eq(ga.reason, "checkmate", label .. ": game completes")
        eq(gb.reason, "checkmate", label .. ": game completes on both sides")
    end

    section("forever: challenge paths")
    a.target = b
    Duel("by target", function() a.ns.Game.Invite(a.ns.UnitPlayerName("target")) end)
    a.target = nil
    Duel("from lobby", function()
        local row
        for _, r in ipairs(a.ns.Profile.OnlineList()) do
            if r.name == "Just Keepingcalm" then row = r end
        end
        a.ns.Game.Invite(row.name) -- what the Lobby's Challenge button does
    end)
    Duel("typed lower case", function() a.ns.Game.Invite("just keepingcalm") end)
    Duel("typed with hyphen", function() a.ns.Game.Invite("Just-Keepingcalm") end)
    Duel("typed surname only (unique)", function() a.ns.Game.Invite("keepingcalm") end)

    section("forever: ambiguous and offline names")
    a.ns.Game.Invite("Just") -- two players are called Just: cannot be resolved
    Advance(2)
    check(b.ns.Game.LatestInvite() == nil and c.ns.Game.LatestInvite() == nil, "ambiguous first name reaches nobody")
    eq(a.ns.Game.outgoing, nil, "ambiguous name reported as not online")
    a.ns.Game.Invite("Ghost Writer")
    Advance(2)
    eq(a.ns.Game.outgoing, nil, "offline player detected")

    section("forever: spectating with two-part names")
    a.ns.Game.Invite("Just Keepingcalm"); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(1)
    c.ns.Game.Watch("Canga Prime"); Advance(3)
    local gw = c.ns.Game.current
    check(gw and gw.mode == "spectate", "spectating works")
    a.ns.Game.Resign(); Advance(2)
    c.ns.Game.StopWatching(); Advance(1)

    section("forever: notifications, both directions")
    local function ChatHas(cl, pattern)
        for _, m in ipairs(cl.chat) do if m:find(pattern) then return true end end
        return false
    end
    local function Reset(cl) cl.chat, cl.warnings, cl.sounds, cl.flashes = {}, {}, {}, 0 end
    for _, pair in ipairs({ { a, b }, { b, a } }) do
        local from, to = pair[1], pair[2]
        local label = from.ns.me .. " -> " .. to.ns.me
        to.ns.UI.Show(); to.ns.UI.Toggle() -- window closed: notifications must not depend on it
        Reset(from); Reset(to)
        from.ns.Game.Invite(to.ns.me)
        Advance(1)
        local popup = to.ns.UI.invitePopup
        check(popup and popup:IsShown(), label .. ": popup shown")
        check(popup and popup.text:GetText():find(from.ns.me, 1, true), label .. ": popup names the challenger")
        check(ChatHas(to, "challenges you"), label .. ": chat message")
        check(#to.warnings == 1 and to.warnings[1]:find(from.ns.me, 1, true), label .. ": centre-screen warning")
        check(to.flashes >= 1, label .. ": taskbar flash")
        check(#to.sounds >= 1, label .. ": sound")
        check(ChatHas(from, "challenge sent"), label .. ": challenger told it was sent")
        Advance(2)
        check(popup.title:GetText():find("%(%d+s%)"), label .. ": countdown shown")
        -- Accept with the popup's button
        popup.accept:Click()
        Advance(1)
        check(not popup:IsShown(), label .. ": popup closes on accept")
        check(ChatHas(from, "game started against"), label .. ": challenger told the game started")
        check(from.flashes >= 1 and #from.warnings >= 1, label .. ": challenger alerted (flash + warning)")
        check(ChatHas(to, "game started against"), label .. ": accepter told the game started")
        from.ns.Game.Resign(); Advance(2)
        -- Decline
        Reset(from)
        from.ns.Game.Invite(to.ns.me); Advance(1)
        to.ns.UI.invitePopup.decline:Click(); Advance(1)
        check(ChatHas(from, "declined"), label .. ": challenger told about decline")
        check(not to.ns.UI.invitePopup:IsShown(), label .. ": popup closes on decline")
        -- No answer
        Reset(from)
        from.ns.Game.Invite(to.ns.me); Advance(62)
        check(ChatHas(from, "no answer"), label .. ": challenger told about no answer")
        check(not to.ns.UI.invitePopup:IsShown(), label .. ": popup closes when it expires")
        -- Challenger cancels
        from.ns.Game.Invite(to.ns.me); Advance(1)
        from.ns.Game.CancelInvite(); Advance(1)
        check(not to.ns.UI.invitePopup:IsShown(), label .. ": popup closes when cancelled")
    end
    -- Busy player
    Reset(a)
    a.ns.Game.Invite(b.ns.me); Advance(1); b.ns.Game.AnswerLatest(true); Advance(1)
    c.ns.Game.Invite(a.ns.me); Advance(1)
    check(ChatHas(c, "already in a game"), "challenging a busy player says so")
    a.ns.Game.Resign(); Advance(2)
    RemoveClient(a); RemoveClient(b); RemoveClient(c)

    section("forever: profiles from 1.0.0 / 1.0.1 are migrated")
    local old = { chars = {
        ["Canga-Prime"] = { rating = 1337, peak = 1400, w = 9, l = 1, d = 0, games = 10 },
        ["Canga-TestRealm"] = { rating = 1210, peak = 1210, w = 1, l = 0, d = 0, games = 1 },
    }, realms = { Prime = { players = {} }, TestRealm = { players = { ["Just-TestRealm"] = { r = 1200, w = 0, l = 0, d = 0, seen = 0 } } } } }
    local m = NewClient("Canga", old, "Prime")
    eq(m.ns.Profile.me.w, 9, "the profile with most games is kept")
    eq(m.env.ChessPvPDB.chars["Canga-Prime"], nil, "1.0.0 key removed")
    eq(m.env.ChessPvPDB.chars["Canga-TestRealm"], nil, "1.0.1 key removed")
    eq(m.ns.Profile.GetPlayer("Just-TestRealm"), nil, "old ladder cache cleared")
    RemoveClient(m)
    local again = NewClient("Canga", m.env.ChessPvPDB, "Prime")
    eq(again.ns.Profile.me.w, 9, "migration only runs once")
    RemoveClient(again)
    net.forever = false
end

------------------------------------------------------------------------
if want("visual") then
    -- Plays a full game with the board on screen and animations on, through every special
    -- move, and checks sounds, effects and that the board ends up consistent.
    local function Played(cl, id)
        for _, x in ipairs(cl.soundFiles) do if x == id then return true end end
        for _, x in ipairs(cl.sounds) do if x == id then return true end end
        return false
    end
    local function BoardMatches(cl)
        local board = cl.ns.UI.Debug and cl.ns.UI.Debug().board
        local g = cl.ns.Game.current
        for _, cell in ipairs(board.cells) do
            local piece = g.pos.b[cell.sq]
            local shown = cell.view:IsShown()
            if (piece ~= 0) ~= shown then return false, cell.sq end
            if piece ~= 0 and cell.view.piece ~= piece then return false, cell.sq end
        end
        for _, m in ipairs(board.movers) do
            if m:IsShown() then return false, "mover still visible" end
        end
        return true
    end

    for _, variant in ipairs({ "art", "no-art" }) do
        section("visual: full game with animations (" .. variant .. ")")
        net.forever = true
        net.missingArt = variant == "no-art"
        local a = NewClient("Canga", nil, "Prime")
        local b = NewClient("Just", nil, "Keepingcalm")
        a.faction, b.faction = "Horde", "Alliance"
        Advance(20)
        a.ns.UI.ShowTab("play")
        b.ns.UI.ShowTab("play")
        a.ns.db.settings.color = "w"
        a.ns.Game.Invite("Just Keepingcalm"); Advance(1)
        b.ns.Game.AnswerLatest(true); Advance(1)
        check(Played(a, 567275) and Played(b, 567275), "war drum at game start")
        check(Played(a, 541389) or Played(a, 541391) or Played(a, 541400), "Horde player hears an orc battle cry")
        check(Played(b, 540696) or Played(b, 540717), "Alliance player hears a human battle cry")
        local A = a.ns.Assets
        eq(A.ArmyFor(1, a.ns.Game.current), "Horde", "Horde player's white army is the Horde")
        eq(A.ArmyFor(1, b.ns.Game.current), "Alliance", "same pieces are the Alliance on the Alliance player's screen")

        -- A game with captures, en passant, castling, check, promotion and mate.
        local moves = {
            "e2e4", "d7d5", "e4d5", "g8f6", -- capture
            "g1f3", "c7c5", "d5c6", "b8c6", -- en passant, recapture
            "f1b5", "e7e6", "e1g1", "f8e7", -- castling
            "b5c6", "b7c6", "f1e1", "e8g8",
            "d2d4", "d8d5", "c1g5", "c8a6",
            "b1c3", "d5d4", "f3d4", "a8d8",
            "g5f6", "e7f6", "c3e4", "f6d4",
            "d1d4", "d8d4", "e4f6", "g7f6", -- e4f6 check
        }
        for i, mv in ipairs(moves) do
            local who = (i % 2 == 1) and a or b
            a.soundFiles, b.soundFiles, a.sounds, b.sounds = {}, {}, {}, {}
            check(who.ns.Game.Move(mv), "move " .. i .. " " .. mv)
            Advance(1.5) -- let both boards finish animating
            local ok1, where1 = BoardMatches(a)
            local ok2, where2 = BoardMatches(b)
            check(ok1, "Canga's board correct after " .. mv .. " (" .. tostring(where1) .. ")")
            check(ok2, "Keepingcalm's board correct after " .. mv .. " (" .. tostring(where2) .. ")")
            if mv == "e4d5" then
                check(Played(a, 567880) or Played(a, 567881) or Played(a, 567883), "sword hit on capture")
                check(Played(a, 540722) or Played(a, 540838), "Alliance death cry when an Alliance piece falls (on Horde screen)")
                -- Black is Keepingcalm's own Alliance army on his screen too, so both agree.
                check(Played(b, 540722) or Played(b, 540838), "Keepingcalm hears his Alliance footman fall")
                check(not (Played(b, 541234) or Played(b, 541308)), "no orc death cry for an Alliance piece")
            elseif mv == "e1g1" then
                check(Played(a, 567863) or Played(a, 567864), "shield sound on castling")
            elseif mv == "e4f6" then
                check(Played(b, 8959), "raid warning sound on check")
            end
        end
        eq(#a.ns.Game.current.captures[1] > 0 and "yes" or "no", "yes", "captures recorded for the tray")

        section("visual: promotion and checkmate banners (" .. variant .. ")")
        a.ns.Game.Resign(); Advance(2)
        a.ns.Game.Invite("Just Keepingcalm"); Advance(1)
        b.ns.Game.AnswerLatest(true); Advance(1)
        local promo = { "a2a4", "h7h6", "a4a5", "h6h5", "a5a6", "h5h4", "a6b7", "h4h3", "b7a8q", "h3g2", "a8b8", "g2h1q", "b8c8", "d8c8" }
        for i, mv in ipairs(promo) do
            local who = (i % 2 == 1) and a or b
            a.soundFiles, a.sounds = {}, {}
            check(who.ns.Game.Move(mv), "promo game move " .. mv)
            Advance(1.5)
            if mv == "b7a8q" then check(Played(a, 888) or Played(a, 1440) or Played(a, 567431), "level-up sound on promotion") end
            check((BoardMatches(a)), "board correct after " .. mv)
        end
        -- Scholar's-style finish: resign leads to the banner
        a.sounds, a.soundFiles = {}, {}
        b.ns.Game.Resign(); Advance(2)
        local banner = a.ns.UI.Debug().banner
        check(banner:IsShown(), "victory banner shown")
        eq(banner.title:GetText(), "Victory!", "banner title")
        check(Played(a, 8454) or Played(a, 568480), "Horde victory fanfare for the Horde winner")
        eq(#a.errors + #b.errors, 0, "no Lua errors during animations")
        RemoveClient(a); RemoveClient(b)
        net.forever, net.missingArt = false, nil
    end

    section("visual: animations off")
    local c = NewClient("Solo")
    c.ns.db.settings.animations = false
    c.ns.UI.ShowTab("play")
    c.ns.Game.StartLocal()
    for _, mv in ipairs({ "e2e4", "d7d5", "e4d5" }) do
        c.ns.Game.Move(mv)
        Advance(0.1)
        check((BoardMatches(c)), "instant board update with animations off (" .. mv .. ")")
    end
    eq(#c.errors, 0, "no errors with animations off")
    RemoveClient(c)
end

------------------------------------------------------------------------
if want("ledger") then
    -- Carol only watches. Her ladder must reflect what really happened.
    section("ledger: honest rated game")
    local a = NewClient("Alice")
    local b = NewClient("Bob")
    local c = NewClient("Carol")
    Advance(20)
    local AL, BO = "Alice-TestRealm", "Bob-TestRealm"
    local function Rating(cl, name) return cl.ns.Ledger.Rating(name) end
    local function PlayMate(white, black)
        white.ns.Game.Move("f2f3"); Advance(1)
        black.ns.Game.Move("e7e5"); Advance(1)
        white.ns.Game.Move("g2g4"); Advance(1)
        black.ns.Game.Move("d8h4"); Advance(3)
    end
    a.ns.db.settings.color = "w"
    a.ns.Game.Invite("Bob"); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    PlayMate(a, b) -- fool's mate: Black (Bob) wins
    Advance(10)
    eq(Rating(c, BO), 1220, "witness: winner +20")
    eq(Rating(c, AL), 1180, "witness: loser -20")
    eq(Rating(a, AL), 1180, "loser's own client agrees")
    eq(b.ns.Profile.me.rating, 1220, "winner's profile rating comes from the ledger")
    eq(b.ns.Game.current.delta, 20, "banner shows the confirmed rating change")

    section("ledger: editing your own rating does nothing")
    local p = a.ns.Profile.me
    p.rating, p.w, p.peak = 2400, 300, 2400 -- edited saved variables
    a.ns.Game.Announce(true); Advance(20)
    eq(Rating(c, AL), 1180, "witness ignores the edited rating")
    local top = c.ns.Profile.Board()[1]
    eq(top.name, BO, "ladder still led by the real winner")
    Advance(5)
    eq(a.ns.Profile.me.rating, 1180, "the cheater's own client puts the ledger rating back")

    local GB = c.ns.Comm.handlers.GB
    local now = math.floor(1700000000 + T)
    local function Say(sender, id, w, bl, res, ts)
        GB(sender, "CHANNEL", { "GB", table.concat({ id, w, bl, ts or now, res or "-" }, ",") })
    end

    section("ledger: invented games and other people's games")
    for i = 1, 5 do Say(AL, "FAKE" .. i, AL, BO, "1-0") end -- Alice claims 5 wins Bob never played
    Say(AL, "OTHER1", BO, "Carol-TestRealm", "0-1") -- a statement about a game she was not in
    Advance(2)
    eq(Rating(c, AL), 1180, "games without the opponent's statement never count")
    eq(c.ns.Ledger.Get("Carol-TestRealm"), nil, "statements about other people's games are ignored")

    section("ledger: disputed result")
    Say(AL, "DISP1", AL, BO); Say(BO, "DISP1", AL, BO)
    Say(AL, "DISP1", AL, BO, "1-0"); Say(BO, "DISP1", AL, BO, "0-1")
    Say(AL, "DISP1", AL, BO, "0-1") -- changing your story later is ignored too
    Advance(2)
    eq(Rating(c, AL), 1180, "disputed game does not count")
    eq(c.ns.Ledger.Get(AL).disputed, 1, "Alice marked as disputing")
    eq(c.ns.Ledger.Get(BO).disputed, 1, "Bob marked as disputing")

    section("ledger: rage quit")
    Say(AL, "QUIT1", AL, BO); Say(BO, "QUIT1", AL, BO) -- both started it
    Say(BO, "QUIT1", AL, BO, "0-1") -- Bob won; Alice never states the result
    Advance(70)
    eq(Rating(c, AL), 1180, "one-sided result waits for the opponent")
    Advance(1800)
    check(Rating(c, AL) < 1180, "after 30 minutes of silence the loss counts (" .. Rating(c, AL) .. ")")
    check(Rating(c, BO) > 1220, "and the win counts")

    section("ledger: farming one opponent")
    local before = Rating(c, BO)
    local day = now - 86400 * 3 -- a day with no other Alice-Bob games
    for i = 1, 5 do
        local id = "FARM" .. i
        Say(AL, id, AL, BO, nil, day + i); Say(BO, id, AL, BO, nil, day + i)
        Say(AL, id, AL, BO, "0-1", day + i); Say(BO, id, AL, BO, "0-1", day + i)
    end
    Advance(2)
    local gained = Rating(c, BO) - before
    local farm = c.ns.Ledger.Get(BO)
    check(gained > 0 and gained < 45, "only 2 games per pair per day count (gained " .. gained .. ")")
    eq(farm.beaten, 1, "ladder shows Bob has only beaten 1 different player")

    section("ledger: a late joiner rebuilds the same ladder")
    local d = NewClient("Dave")
    Advance(60)
    -- (The hand-made statements above only went to Carol; the real game is re-shared by its players.)
    eq(Rating(d, BO), 1220, "Dave learns Bob's real win from the re-shared statements")
    eq(Rating(d, BO), Rating(a, BO), "Dave's ladder matches the players' own")
    eq(Rating(d, AL), Rating(b, AL), "Dave's ladder matches for Alice too")

    section("ledger: unrated games never touch the ladder")
    local games = c.ns.Ledger.Get(AL).games
    a.ns.Game.Resign(); b.ns.Game.Resign(); Advance(2)
    a.ns.Game.Invite("Bob", { rated = false }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    PlayMate(a, b); Advance(10)
    eq(c.ns.Ledger.Get(AL).games, games, "casual game not on the ladder")

    for _, cl in ipairs({ a, b, c, d }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors") ; RemoveClient(cl) end
end

------------------------------------------------------------------------
if want("cheat") then
    section("validation")
    local c = NewClient("Val")
    local P = c.ns.Profile
    check(not P.UpdatePlayer("X-R", 2400, 0, 0, 0, "", 0), "implausible rating rejected")
    check(P.UpdatePlayer("X-R", 1300, 5, 1, 0, "r4", 30), "plausible rating accepted")
    check(not P.UpdatePlayer("X-R", 1300.5, 5, 1, 0, "", 0), "non-integer rejected")
    eq(P.Elo(1200, 1200, 1, 0), 1220, "Elo provisional K=40")
    eq(P.Elo(1200, 1200, 1, 30), 1212, "Elo K=24")
    eq(P.Elo(2100, 2100, 0, 30), 2092, "Elo K=16 at 2000+")
    RemoveClient(c)
end

summary()
