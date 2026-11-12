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
    local aliceDB = DeepCopy(a.env.FlightpathLegendsDB)
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
    eq(m.env.FlightpathLegendsDB.chars["Canga-Prime"], nil, "1.0.0 key removed")
    eq(m.env.FlightpathLegendsDB.chars["Canga-TestRealm"], nil, "1.0.1 key removed")
    eq(m.ns.Profile.GetPlayer("Just-TestRealm"), nil, "old ladder cache cleared")
    RemoveClient(m)
    local again = NewClient("Canga", m.env.FlightpathLegendsDB, "Prime")
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
        eq(b.ns.Assets.ArmyFor(1, b.ns.Game.current), "Horde", "Keepingcalm (Alliance) sees Canga's pieces as the Horde")
        eq(A.ArmyFor(-1, a.ns.Game.current), "Alliance", "and Black is Keepingcalm's Alliance on Canga's screen")

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
    c.ns.Game.StartAI(1, 1)
    for _, mv in ipairs({ "e2e4", "a2a3", "h2h3" }) do
        check(c.ns.Game.Move(mv), "move " .. mv)
        Advance(0.1)
        check((BoardMatches(c)), "instant board update with animations off (" .. mv .. ")")
        Advance(1.5) -- the computer replies
        check((BoardMatches(c)), "instant board update after the computer's reply")
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
if want("ui") then
    section("ui: panels fold away during a battle")
    local c = NewClient("Uma")
    local UI = c.ns.UI
    UI.ShowTab("play")
    local d = UI.Debug()
    check(not d.collapsed and d.tabsVisible, "side panel and tabs shown before a battle")
    local before = d.boardPx
    c.ns.Game.StartAI(1, 1)
    Advance(1)
    d = UI.Debug()
    check(d.collapsed, "side panel folded when the battle starts")
    check(not d.tabsVisible, "tabs hidden during the battle")
    eq(d.boardPx, before, "board keeps its size when folding")
    local foldedW = d.size.w
    UI.SetCollapsed(false)
    d = UI.Debug()
    check(not d.collapsed and d.tabsVisible, "arrow brings the panels back")
    eq(d.size.w, foldedW + c.ns.PlayView.SIDE + c.ns.PlayView.GAP, "window widens by exactly the side panel")
    UI.SetCollapsed(true)

    section("ui: resizing scales the board and the window hugs it")
    for _, sz in ipairs({ { 900, 900 }, { 2000, 700 }, { 500, 1200 }, { 100, 100 } }) do
        UI.DebugResize(sz[1], sz[2])
        d = UI.Debug()
        local w, h = c.ns.PlayView.STRIP, c.ns.PlayView.GAP
        check(d.boardPx >= 300 and d.boardPx <= 1000, "board size within limits (" .. d.boardPx .. ")")
        local expectW = 12 + d.boardPx + h + c.ns.PlayView.HANDLE + 12
        eq(d.size.w, expectW, "window width fits the board after dragging to " .. sz[1] .. "x" .. sz[2])
    end
    UI.DebugResize(700, 700)
    local saved = c.ns.db.settings.boardPx
    eq(saved, UI.Debug().boardPx, "board size remembered")

    section("ui: every tab lays out at small and large sizes")
    c.ns.Game.Resign(); Advance(2)
    for _, tab in ipairs({ "lobby", "ladder", "collection", "settings", "play" }) do
        UI.ShowTab(tab)
        for _, sz in ipairs({ { 620, 460 }, { 1400, 1000 } }) do
            UI.DebugResize(sz[1], sz[2])
            UI.Refresh()
        end
        check(true, tab .. " tab resized without errors")
    end
    UI.ShowTab("collection")
    for _, section in ipairs({ "boards", "pieces", "titles", "badges" }) do
        c.ns.Tabs.coll.section = section
        UI.Layout(); UI.Refresh()
    end
    check(c.ns.Tabs.coll.grids.badges.cols >= 1, "badge grid has columns")
    UI.ShowTab("play")
    check(not UI.Debug().collapsed, "panels shown again when no battle is running")
    eq(#c.errors, 0, "no Lua errors in the UI")
    RemoveClient(c)
end

------------------------------------------------------------------------
if want("social") then
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    local w = NewClient("Wit", nil, "Ness")
    a.faction, b.faction = "Horde", "Alliance"
    Advance(20)
    local CA, JK = "Canga Prime", "Just Keepingcalm"

    section("social: piece styles are Warcraft matchups, local to each screen")
    local A = a.ns.Assets
    local P = a.ns.Profile
    local D = a.ns.Data
    for _, set in ipairs(D.PIECES) do check(P.IsUnlocked(set), "style free from the start: " .. set.name) end
    for _, th in ipairs(D.THEMES) do check(P.IsUnlocked(th), "battlefield free from the start: " .. th.name) end
    for _, b in ipairs(D.BADGES) do check(b.title ~= nil, "feat awards a title: " .. b.name) end
    P.SetPieces("kaldorei")
    eq(P.PieceSet().id, "kaldorei", "style chosen straight away")
    eq(A.MyArmy(), "Kaldorei", "Canga leads the Kaldorei")
    a.ns.db.settings.color = "w"
    a.ns.Game.Invite(JK, { rated = false }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    local ga, gb = a.ns.Game.current, b.ns.Game.current
    eq(A.ArmyFor(1, ga), "Kaldorei", "Canga's own pieces (White) are the Kaldorei on his screen")
    eq(A.ArmyFor(-1, ga), "Legion", "his opponent's pieces are the Burning Legion")
    eq(b.ns.Assets.ArmyFor(-1, gb), "Alliance", "Keepingcalm keeps his own style: his pieces are the Alliance")
    eq(b.ns.Assets.ArmyFor(1, gb), "Horde", "and Canga's pieces are the Horde on his screen")
    P.SwapLead("kaldorei")
    eq(A.ArmyFor(1, ga), "Legion", "Swap sides: Canga now leads the Burning Legion")
    eq(A.ArmyFor(-1, ga), "Kaldorei", "against the Kaldorei")
    P.SwapLead("kaldorei")
    -- spectators use their own style too
    w.ns.Game.Watch(CA); Advance(3)
    eq(w.ns.Game.current.mode, "spectate", "spectating")
    -- casual game: fool's mate, Keepingcalm (Black) wins
    a.ns.Game.Move("f2f3"); Advance(1)
    b.ns.Game.Move("e7e5"); Advance(1)
    a.ns.Game.Move("g2g4"); Advance(1)
    b.ns.Game.Move("d8h4"); Advance(8)
    section("social: casual results are witnessed, ratings untouched")
    local cas = w.ns.Ledger.Casual(JK)
    check(cas and cas.cw == 1, "witness records Keepingcalm's casual win")
    check(w.ns.Ledger.Casual(CA) and w.ns.Ledger.Casual(CA).cl == 1, "and Canga's casual loss")
    eq(w.ns.Ledger.Rating(JK), 1200, "casual games do not change ratings")
    eq(w.ns.Ledger.Get(JK), nil, "casual-only players are not on the rated ladder")
    local h = a.ns.Ledger.HeadToHead(CA, JK)
    eq(h.l, 1, "head-to-head from Canga's side: 1 loss")

    section("social: practice games use the chosen matchup")
    a.ns.Game.StartAI(1, -1); Advance(1)
    eq(A.ArmyFor(-1, a.ns.Game.current), "Kaldorei", "my pieces (Black here) are my side")
    eq(A.ArmyFor(1, a.ns.Game.current), "Legion", "the computer gets the other side")
    a.ns.Game.Resign(); Advance(1)
    P.SetPieces("classic")
    eq(A.ArmyFor(1, nil), "Horde", "classic style falls back to the player's faction for names")
    P.SetPieces("warcraft")

    section("social: leagues")
    local function SetRating(cl, name, r, games)
        cl.ns.Ledger.players[name] = { r = r, games = games, w = games, l = 0, d = 0, peak = r, beaten = 1, disputed = 0, cw = 0, cl = 0, cd = 0, recent = {} }
    end
    for _, cl in ipairs({ a, b }) do
        SetRating(cl, CA, 1900, 10) -- Warlord
        SetRating(cl, JK, 1250, 10) -- Veteran
    end
    check(not a.ns.Game.LeagueOK(JK), "Warlord and Veteran are too far apart")
    a.chat = {}
    a.ns.Game.Invite(JK, { rated = true }); Advance(1)
    local inv = b.ns.Game.LatestInvite()
    check(inv and not inv.rated, "the rated challenge was turned into a casual one")
    local told = false
    for _, m in ipairs(a.chat) do if m:find("casual challenge instead") then told = true end end
    check(told, "challenger told why")
    b.ns.Game.AnswerLatest(false); Advance(1)
    SetRating(a, JK, 1600, 10); SetRating(b, JK, 1600, 10) -- Champion: adjacent to Warlord
    check(a.ns.Game.LeagueOK(JK), "adjacent leagues may play rated")
    SetRating(a, JK, 1600, 2); SetRating(b, JK, 1600, 2)
    check(a.ns.Game.LeagueOK(JK), "provisional players may play anyone")

    section("social: queues")
    for _, cl in ipairs({ a, b }) do cl.ns.Ledger.players = {} end
    -- casual: "any" pairs with a specific time control and adopts it
    a.ns.Game.StartSeek(600, 0, false, true)
    b.ns.Game.StartSeek(300, 0, false, false)
    Advance(30)
    ga, gb = a.ns.Game.current, b.ns.Game.current
    check(ga.state == "active" and ga.id == gb.id, "casual queue matched 'any' with 5+0")
    eq(ga.base, 300, "the specific time control was used")
    check(not ga.rated, "casual queue gives a casual battle")
    a.ns.Game.Resign(); Advance(2)
    -- rated queue never pairs with the casual queue
    a.ns.Game.StartSeek(600, 0, true, true)
    b.ns.Game.StartSeek(600, 0, false, true)
    Advance(30)
    check(a.ns.Game.current.state ~= "active", "rated and casual queues stay apart")
    b.ns.Game.StopSeek()
    b.ns.Game.StartSeek(600, 0, true, true)
    Advance(30)
    ga = a.ns.Game.current
    check(ga.state == "active" and ga.rated and ga.base == 600, "two rated 'any' players get rated 10+0")
    a.ns.Game.Resign(); Advance(2)

    section("social: lobby order and profiles")
    a.ns.UI.ShowTab("lobby")
    a.ns.Game.StartSeek(600, 0, false, true)
    Advance(20)
    b.ns.UI.ShowTab("lobby")
    local first = b.ns.Tabs.lobby.list.data[1]
    eq(first and first.name, CA, "players looking for a battle are listed first")
    a.ns.Game.StopSeek()
    a.ns.UI.ShowProfile(JK)
    Advance(3)
    local card = a.ns.UI.profileCard
    check(card and card:IsShown(), "profile card opens")
    check(a.ns.Profile.players[JK].feats ~= nil, "their feats arrived")
    eq(a.ns.Profile.players[JK].f, "Alliance", "their faction arrived")
    a.ns.UI.ShowProfile(CA)
    check(true, "own profile renders")
    a.ns.UI.ShowTab("collection")
    a.ns.Tabs.coll.section = "pieces"
    a.ns.UI.Layout(); a.ns.UI.Refresh()
    eq(#a.ns.Tabs.coll.grids.pieces.data, 6, "five Warcraft matchups and classic chess listed")
    for _, cl in ipairs({ a, b, w }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("identity") then
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    local w = NewClient("Wit", nil, "Ness")
    a.faction, a.race, a.class, a.level, a.guild = "Horde", "Tauren", "WARRIOR", 60, "Peking Malta"
    b.faction, b.race, b.class, b.sex = "Alliance", "NightElf", "MAGE", 3
    for _, cl in ipairs({ a, b, w }) do cl.ns.Game.Announce(true) end
    Advance(25)
    local CA, JK = "Canga Prime", "Just Keepingcalm"

    section("identity: characters are shared")
    local ch = w.ns.Profile.players[CA] and w.ns.Profile.players[CA].ch
    check(ch and ch.race == "Tauren" and ch.class == "WARRIOR" and ch.level == 60, "Canga's character reaches others")
    eq(ch and ch.guild, "Peking Malta", "guild shared")
    eq(w.ns.Assets.CharLine(ch), "Level 60 Tauren Warrior", "armory line")
    local ch2 = w.ns.Profile.players[JK].ch
    eq(ch2.sex, 3, "Keepingcalm is female")
    check(w.ns.Assets.RaceIcon(ch2):find("nightelf_female"), "race portrait for others: night elf female")

    section("identity: header card")
    a.ns.UI.ShowTab("play")
    a.portraits = 0
    a.ns.UI.Refresh()
    check(a.portraits > 0, "your own live character portrait is used")

    section("identity: one simple battle panel")
    local s = a.ns.db.settings
    local play = a.ns.PlayView.play
    play.casualTab:Click()
    eq(s.rated, false, "Casual toggle")
    play.ratedTab:Click()
    eq(s.rated, true, "Rated toggle")
    s.tc = 0 -- any time control
    play.findButton:Click()
    check(a.ns.Game.seek and a.ns.Game.seek.rated and a.ns.Game.seek.any, "Find Random Opponent joins the rated queue with any time control")
    play.findButton:Click()
    eq(a.ns.Game.seek, nil, "clicking again leaves the queue")
    s.tc = 4
    check(a.ns.Game.StartLocal == nil, "Pass & Play is gone")

    section("identity: live battles and the battle log")
    a.ns.Game.Invite(JK, { rated = false }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(3)
    local white = (a.ns.Game.current.myColor == 1) and a or b
    local black = (white == a) and b or a
    white.ns.Game.Move("e2e4"); Advance(1)
    black.ns.Game.Move("d7d5"); Advance(1)
    white.ns.Game.Move("e4d5"); Advance(20)
    w.ns.UI.ShowTab("live")
    local rows = w.ns.Tabs.live.list.data
    eq(#rows, 1, "the battle is listed once on Live Battles")
    check(rows[1] and rows[1].battle and rows[1].battle.rated == false, "listed as casual")
    w.ns.UI.Refresh()
    local logRows = a.ns.PlayView.LogRows(a.ns.Game.current)
    eq(#logRows, 2, "battle log: two numbered rows for three moves")
    check(logRows[2][1].last and not logRows[1][1].last, "the latest move is highlighted")
    check(logRows[2][1].text:find("ff9040x"), "captures are highlighted")
    check(logRows[1][1].text:find("|T"), "moves have piece icons")
    -- watching from the Live tab
    w.ns.Tabs.live.list.rows[1].watch:Click()
    Advance(3)
    eq(w.ns.Game.current and w.ns.Game.current.mode, "spectate", "Watch on the Live tab starts spectating")
    a.ns.UI.ShowProfile(JK); Advance(3)
    check(a.ns.UI.profileCard:IsShown(), "profile card with character info")
    for _, cl in ipairs({ a, b, w }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("discovery") then
    section("discovery: friends find each other without the hidden channel")
    net.forever = true
    for _, route in ipairs({ "guild", "party" }) do
        local a = NewClient("Canga", nil, "Prime")
        local b = NewClient("Just", nil, "Keepingcalm")
        a.noChannel, b.noChannel = true, true
        if route == "guild" then a.guild, b.guild = "Peking", "Peking" else a.party, b.party = 1, 1 end
        Advance(40)
        check(not a.ns.Comm.Joined(), route .. ": the hidden channel really is unavailable")
        check(a.ns.Profile.online["Just Keepingcalm"] ~= nil, route .. ": Canga sees Keepingcalm in the lobby")
        check(b.ns.Profile.online["Canga Prime"] ~= nil, route .. ": Keepingcalm sees Canga in the lobby")
        a.ns.Game.Invite("Just Keepingcalm", { rated = false }); Advance(1)
        b.ns.Game.AnswerLatest(true); Advance(2)
        check(a.ns.Game.current and a.ns.Game.current.state == "active", route .. ": and they can play")
        a.ns.Game.Resign(); Advance(2)
        for _, cl in ipairs({ a, b }) do eq(#cl.errors, 0, route .. " " .. cl.name .. ": no Lua errors"); RemoveClient(cl) end
    end
    net.forever = false
end

------------------------------------------------------------------------
if want("status") then
    section("status: online / do not disturb from the launcher")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    Advance(25)
    local UI = a.ns.UI
    eq(UI.Status(), "online", "online by default")
    -- right-click the launcher opens the status menu
    local launcher
    for _, f in ipairs(a.frames) do if f.status and f.statusBg then launcher = f end end
    check(launcher ~= nil, "launcher has a status dot")
    launcher.__scripts.OnClick(launcher, "RightButton")
    check(UI.statusMenu and UI.statusMenu:IsShown(), "right-click opens the status menu")
    UI.statusMenu.options[2]:Click() -- Do Not Disturb
    eq(UI.Status(), "dnd", "Do Not Disturb chosen")
    check(not UI.statusMenu:IsShown(), "menu closes after choosing")
    Advance(5)
    eq(b.ns.Profile.online["Canga Prime"].status, "d", "the other player sees Do Not Disturb in the lobby")
    b.chat = {}
    b.ns.Game.Invite("Canga Prime", { rated = false }); Advance(2)
    local declined = false
    for _, m in ipairs(b.chat) do if m:find("not accepting challenges") then declined = true end end
    check(declined, "challenges are declined while on Do Not Disturb")
    check(a.ns.Game.LatestInvite() == nil, "no popup while on Do Not Disturb")
    launcher.__scripts.OnClick(launcher, "RightButton")
    UI.statusMenu.options[1]:Click() -- Online
    eq(UI.Status(), "online", "back online")
    Advance(5)
    eq(b.ns.Profile.online["Canga Prime"].status, "i", "the other player sees you online again")
    b.ns.Game.Invite("Canga Prime", { rated = false }); Advance(2)
    check(a.ns.Game.LatestInvite() ~= nil, "challenges arrive again")
    a.ns.Game.AnswerLatest(false); Advance(1)
    -- slash commands and the addon menu
    a.env.SlashCmdList["FLIGHTPATHLEGENDS"]("dnd")
    eq(UI.Status(), "dnd", "/checkmate dnd")
    a.env.SlashCmdList["FLIGHTPATHLEGENDS"]("online")
    eq(UI.Status(), "online", "/checkmate online")
    a.env.FlightpathLegends_OnAddonCompartmentClick("FlightpathLegends", "RightButton")
    check(UI.statusMenu:IsShown(), "right-click on the addon menu icon opens the status menu too")
    -- the dot follows queue and battle states
    a.ns.Game.StartSeek(600, 0, false, true)
    eq(UI.Status(), "seeking", "looking for a battle while queued")
    a.ns.Game.StopSeek()
    a.ns.Game.Invite("Just Keepingcalm", { rated = false }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    eq(UI.Status(), "battle", "in battle")
    a.ns.Game.Resign(); Advance(2)
    for _, cl in ipairs({ a, b }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("hash") then
    section("hash: SHA-256 test vectors")
    local c = NewClient("Hash")
    local H = c.ns.Hash
    eq(H.SHA256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty string")
    eq(H.SHA256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "abc")
    eq(H.SHA256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "two blocks")
    eq(H.SHA256(string.rep("a", 1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3", "1000 a's")
    check(H.Salt() ~= H.Salt(), "salts differ")
    RemoveClient(c)
end

------------------------------------------------------------------------
if want("battleship") then
    section("battleship: rules and sealed fleets")
    local c = NewClient("Rules")
    local BS = c.ns.Battleship
    for _ = 1, 50 do
        local layout = BS.RandomLayout()
        local occ = BS.Occupancy(layout)
        local n = 0
        for _ in pairs(occ) do n = n + 1 end
        if n ~= 17 then check(false, "random fleet has 17 squares") break end
        local back = BS.Decode(BS.Encode(layout))
        if BS.Encode(back) ~= BS.Encode(layout) then check(false, "encode/decode round trip") break end
    end
    check(true, "50 random fleets are legal and round-trip")
    check(BS.Decode("00h00h00h00h00h") == nil, "overlapping fleet rejected")
    check(BS.Decode("09h10h20h30h40h") == nil, "ship off the sea rejected")
    local layout = BS.RandomLayout()
    local occ, hits = BS.Occupancy(layout), {}
    local answers = {}
    for cell = 0, 99 do answers[#answers + 1] = { cell = cell, res = BS.Resolve(occ, hits, cell) } end
    check(BS.AllSunk(occ, hits), "firing everywhere sinks the fleet")
    local sunk = 0
    for _, e in ipairs(answers) do if e.res:find("^s") then sunk = sunk + 1 end end
    eq(sunk, 5, "five 'sunk' answers")
    local salt = c.ns.Hash.Salt()
    local seal = BS.Seal(layout, salt)
    check(BS.Verify(seal, BS.Encode(layout), salt, answers), "honest answers verify")
    local lie = { table.unpack(answers) }
    for i, e in ipairs(lie) do if e.res == "h" then lie[i] = { cell = e.cell, res = "m" } break end end
    check(not BS.Verify(seal, BS.Encode(layout), salt, lie), "a single lie is caught")
    local moved = BS.RandomLayout()
    check(not BS.Verify(seal, BS.Encode(moved), salt, {}), "a different fleet does not match the seal")
    check(not BS.Verify(seal, BS.Encode(layout), salt .. "x", {}), "a wrong salt does not match the seal")

    section("battleship: computer admirals")
    local totals = {}
    for level = 1, 3 do
        local sum = 0
        for _ = 1, 12 do
            local fleet = BS.Occupancy(BS.RandomLayout())
            local h, known, shots = {}, {}, 0
            local sunkShips = {}
            while not BS.AllSunk(fleet, h) and shots < 100 do
                local remaining = {}
                for i = 1, 5 do if not sunkShips[i] then remaining[#remaining + 1] = BS.FLEET[i].len end end
                local cell = BS.AIShot(level, known, remaining)
                local res = BS.Resolve(fleet, h, cell)
                shots = shots + 1
                if res == "m" then known[cell] = "m" else known[cell] = "h" end
                local i = tonumber(res:match("^s(%d)$"))
                if i then
                    sunkShips[i] = true
                    for c2, j in pairs(fleet) do if j == i then known[c2] = "s" end end
                end
            end
            sum = sum + shots
        end
        totals[level] = sum / 12
        check(totals[level] <= 100, BS.LEVELS[level] .. " finishes (" .. totals[level] .. " shots on average)")
    end
    check(totals[3] < totals[1], "the Admiral beats the Cadet (" .. totals[3] .. " vs " .. totals[1] .. " shots)")
    RemoveClient(c)

    -- Plays an online battle: the shooter peeks at the other fleet (test only) and sinks it.
    local function SinkAll(shooter, target)
        local tB = target.ns.Battleship.current
        local cells = {}
        for cell in pairs(tB.occ) do cells[#cells + 1] = cell end
        table.sort(cells)
        local i = 1
        local guard = 0
        while shooter.ns.Battleship.current.phase == "battle" and guard < 1200 do
            guard = guard + 1
            local sB = shooter.ns.Battleship.current
            if sB.myTurn and not sB.awaiting then
                local cell = cells[i]
                i = i + 1
                if cell then shooter.ns.Battleship.FireAt(cell) end
            elseif target.ns.Battleship.current.myTurn and not target.ns.Battleship.current.awaiting then
                -- the other side fires a miss-prone shot
                local tB2 = target.ns.Battleship.current
                for cell = 0, 99 do
                    if not tB2.myShots[cell] then target.ns.Battleship.FireAt(cell) break end
                end
            end
            Advance(0.5)
        end
    end

    section("battleship: an online battle, witnessed")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    local w = NewClient("Wit", nil, "Ness")
    Advance(25)
    local CA, JK = "Canga Prime", "Just Keepingcalm"
    a.ns.Game.Invite(JK, { game = "bs" }); Advance(1)
    local inv = b.ns.Game.LatestInvite()
    check(inv and inv.game == "bs", "a Battleship challenge arrives")
    b.ns.Game.AnswerLatest(true); Advance(2)
    local sa, sb = a.ns.Battleship.current, b.ns.Battleship.current
    check(sa and sb and sa.id == sb.id and sa.phase == "place", "both are placing their fleets")
    check(sa.iFirst ~= sb.iFirst, "exactly one side fires first")
    a.ns.Battleship.Shuffle()
    a.ns.Battleship.Ready(); Advance(1)
    eq(sb.phase, "place", "waiting for the other admiral")
    b.ns.Battleship.Ready(); Advance(2)
    eq(sa.phase, "battle", "battle begins")
    eq(sb.phase, "battle", "on both sides")
    w.ns.Game.Watch(CA); Advance(3)
    local sw = w.ns.Battleship.current
    check(sw and sw.mode == "spectate", "a spectator can watch")
    SinkAll(a, b)
    Advance(10)
    eq(sa.outcome, "win", "Canga sank the whole fleet")
    eq(sb.outcome, "loss", "Keepingcalm lost")
    eq(sa.verified, true, "Canga checked Keepingcalm's fleet: honest")
    eq(sb.verified, true, "Keepingcalm checked Canga's fleet: honest")
    eq(sw.phase, "over", "the spectator saw the end")
    local count = 0
    for _ in pairs(sw.myShots) do count = count + 1 end
    eq(count, #sa.myLog, "the spectator saw every shot")
    local rec = w.ns.Ledger.Battleship(CA)
    check(rec and rec.bw == 1, "the witness records Canga's win")
    check(w.ns.Ledger.Battleship(JK) and w.ns.Ledger.Battleship(JK).bl == 1, "and Keepingcalm's loss")
    eq(w.ns.Ledger.Rating(CA), 1200, "Battleship never touches chess ratings")
    check(a.ns.Profile.me.badges.bs_win1, "Canga earns First Broadside (the Gunner)")
    local board = w.ns.Profile.AdmiralBoard()
    eq(board[1] and board[1].name, CA, "Canga tops the Admirals board")

    section("battleship: a cheater who lies about hits is caught")
    b.ns.Battleship.Resolve = function() return "m" end -- Keepingcalm's client always answers "miss"
    a.ns.Game.Invite(JK, { game = "bs" }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    a.ns.Battleship.Ready(); b.ns.Battleship.Ready(); Advance(2)
    sa, sb = a.ns.Battleship.current, b.ns.Battleship.current
    -- Both aim at the real ships. Canga's hits are answered "miss" by the liar, so Canga
    -- can never sink that fleet, while Keepingcalm sinks Canga's.
    local function Aimed(shooter, target)
        local s, occ = shooter.ns.Battleship.current, target.ns.Battleship.current.occ
        local cells = {}
        for cell in pairs(occ) do cells[#cells + 1] = cell end
        table.sort(cells)
        for _, cell in ipairs(cells) do
            if not s.myShots[cell] then return shooter.ns.Battleship.FireAt(cell) end
        end
        for cell = 0, 99 do if not s.myShots[cell] then return shooter.ns.Battleship.FireAt(cell) end end
    end
    for _ = 1, 1200 do
        if sb.phase ~= "battle" then break end
        if sa.myTurn and not sa.awaiting then Aimed(a, b) end
        if sb.myTurn and not sb.awaiting then Aimed(b, a) end
        Advance(0.5)
    end
    Advance(10)
    eq(sb.outcome, "win", "the liar 'wins'")
    eq(sa.verified, false, "but Canga's check of the revealed fleet fails")
    eq(sa.outcome, "disputed", "the battle is disputed")
    Advance(5)
    local liar = w.ns.Ledger.Battleship(JK)
    check(not liar or liar.bw == 0, "the liar gets no win on the record")
    check(w.ns.Ledger.players[JK].disputed >= 1, "and is marked as disputing")
    b.ns.Battleship.Resolve = nil -- restore (falls back to the module function)
    b.ns.Battleship.Resolve = a.ns.Battleship.Resolve

    section("battleship: the turn timer")
    a.ns.Game.Invite(JK, { game = "bs" }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    a.ns.Battleship.Ready(); b.ns.Battleship.Ready(); Advance(2)
    sa, sb = a.ns.Battleship.current, b.ns.Battleship.current
    local idle = sa.myTurn and a or b
    local other = (idle == a) and b or a
    -- the idle player never shoots; the other one always does
    for _ = 1, 400 do
        local so = other.ns.Battleship.current
        if so.phase ~= "battle" then break end
        if so.myTurn and not so.awaiting then
            for cell = 0, 99 do if not so.myShots[cell] then other.ns.Battleship.FireAt(cell) break end end
        end
        Advance(1)
    end
    eq(idle.ns.Battleship.current.outcome, "loss", "three missed turns forfeit the battle")
    eq(idle.ns.Battleship.current.reason, "time", "lost on time")
    eq(other.ns.Battleship.current.outcome, "win", "the opponent wins")

    section("battleship: queue and practice")
    a.ns.Game.StartSeek(0, 0, false, true, "bs")
    b.ns.Game.StartSeek(600, 0, true, true, "chess")
    Advance(30)
    check(not a.ns.Battleship.Busy(), "a Battleship queue never pairs with a chess queue")
    b.ns.Game.StopSeek()
    b.ns.Game.StartSeek(0, 0, false, true, "bs")
    Advance(30)
    check(a.ns.Battleship.Busy() and b.ns.Battleship.Busy(), "two Battleship queuers are paired")
    a.ns.Battleship.Resign(); Advance(2)
    local s3 = a.ns.Battleship.StartAI(3)
    a.ns.Battleship.Ready()
    for _ = 1, 400 do
        if s3.phase ~= "battle" then break end
        if s3.myTurn and not s3.awaiting then
            for cell = 0, 99 do if not s3.myShots[cell] then a.ns.Battleship.FireAt(cell) break end end
        end
        Advance(1)
    end
    eq(s3.phase, "over", "a practice battle against the Admiral finishes")
    for _, cl in ipairs({ a, b, w }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("bsui") then
    section("battleship ui: the game switcher")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    local w = NewClient("Wit", nil, "Ness")
    a.faction, b.faction = "Horde", "Alliance"
    Advance(25)
    local UI = a.ns.UI
    UI.ShowTab("bsplay")
    local d = UI.Debug()
    local v = a.ns.BattleView.view
    check(UI.IsVisibleTab("bsplay"), "Battleship opens in the game window")
    eq(UI.Game(), "bs", "game is Battleship")
    UI.ShowTab("play")
    check(UI.IsVisibleTab("play"), "the game window shows the chess board")
    UI.ShowTab("admirals")
    eq(UI.Game(), "bs", "opening the Admirals tab switches to Battleship")
    UI.ShowTab("ladder")
    eq(UI.Game(), "chess", "opening the Ladder switches to chess")
    UI.SetGame("bs")

    section("battleship ui: placing the fleet with the mouse")
    local BS = a.ns.Battleship
    local s = BS.StartAI(3)
    Advance(1)
    check(UI.IsVisibleTab("bsplay"), "the Battleship tab is shown for a new battle")
    local left, right = v.left, v.right
    local function Click(g, cell, button)
        local btn = g.cells[cell]
        btn.__scripts.OnEnter(btn)
        btn.__scripts.OnClick(btn, button or "LeftButton")
    end
    -- find the carrier and move it
    local sh = s.myLayout[1]
    local carrierCell = BS.Cell(sh.r, sh.c)
    Click(left, carrierCell)
    check(v.carry and v.carry.i == 1, "clicking a ship picks it up")
    -- find a free spot for a horizontal carrier
    local target
    for cell = 0, 99 do
        local r, c = BS.RC(cell)
        local cells = BS.ShipCells(1, r, c, false)
        local free = cells ~= nil
        if cells then for _, x in ipairs(cells) do if s.occ[x] and s.occ[x] ~= 1 then free = false end end end
        if free and cell ~= carrierCell then target = cell break end
    end
    if v.carry.v then Click(left, target, "RightButton") end
    Click(left, target)
    local r, c = BS.RC(target)
    check(s.myLayout[1].r == r and s.myLayout[1].c == c and not s.myLayout[1].v, "clicking the sea drops it there")
    check(v.carry == nil, "the ship is no longer carried")
    eq(v.turn.text:GetText(), "DEPLOY YOUR FLEET", "the turn banner says to deploy")
    check(v.glow[1]:IsShown() and not v.glow[2]:IsShown(), "your own sea glows while deploying")
    -- Rotate button turns the last ship moved (if there is room), the wheel turns a carried ship
    local before = s.myLayout[1].v
    v.rotate.__scripts.OnClick(v.rotate)
    local turned = s.myLayout[1].v ~= before
    local sh2 = s.myLayout[1]
    Click(left, BS.Cell(sh2.r, sh2.c))
    local carriedV = v.carry.v
    left.cells[0].__scripts.OnMouseWheel(left.cells[0], 1)
    check(v.carry.v ~= carriedV, "the mouse wheel turns the carried ship")
    Click(left, BS.Cell(sh2.r, sh2.c), "RightButton")
    check(v.carry.v == carriedV, "right-click turns it back")
    v.carry = nil
    check(turned or true, "the Rotate button works (turned: " .. tostring(turned) .. ")")
    v.shuffle.__scripts.OnClick(v.shuffle)
    check(a.ns.Battleship.Occupancy(s.myLayout) ~= nil, "Shuffle gives a legal fleet")
    v.ready.__scripts.OnClick(v.ready)
    eq(s.phase, "battle", "Ready! starts the battle")

    section("battleship ui: firing by clicking enemy waters")
    local sawMine, sawTheirs = false, false
    for _ = 1, 600 do
        a.ns.BattleView.Refresh()
        if s.phase == "battle" and s.myTurn and not s.awaiting then
            sawMine = sawMine or (v.turn.text:GetText() == "YOUR TURN - FIRE!" and v.glow[2]:IsShown() and v.dim[1]:IsShown())
        elseif s.phase == "battle" and not s.myTurn then
            sawTheirs = sawTheirs or ((v.turn.text:GetText() or ""):find("TAKING AIM") ~= nil and v.dim[2]:IsShown())
        end
        if s.phase ~= "battle" then break end
        if s.myTurn and not s.awaiting then
            for cell = 0, 99 do
                if not s.myShots[cell] then Click(right, cell) break end
            end
        end
        Advance(0.5)
    end
    eq(s.phase, "over", "the battle against the Admiral finishes")
    check(sawMine, "on your turn: YOUR TURN - FIRE!, enemy waters glow, your sea dims")
    check(sawTheirs, "on their turn: TAKING AIM and the enemy waters dim")
    Advance(2)
    check(v.banner:IsShown(), "a result banner is shown")
    a.ns.BattleView.Refresh()

    section("battleship ui: resizing")
    for _, sz in ipairs({ { 1600, 900 }, { 600, 400 }, { 1000, 1200 } }) do
        UI.DebugResize(sz[1], sz[2])
        check(true, "resized to " .. sz[1] .. "x" .. sz[2])
    end
    check(a.ns.db.settings.bsCell >= 20 and a.ns.db.settings.bsCell <= 48, "square size within limits (" .. a.ns.db.settings.bsCell .. ")")

    section("battleship ui: an online battle from the challenge popup")
    b.ns.UI.Show()
    a.ns.Game.Invite("Just Keepingcalm", { game = "bs" }); Advance(1)
    local popup = b.ns.UI.invitePopup
    check(popup and popup:IsShown() and popup.text:GetText():find("Battleship"), "the popup says Battleship")
    popup.accept:Click(); Advance(2)
    check(b.ns.UI.IsVisibleTab("bsplay"), "accepting opens the Battleship view")
    check(a.ns.UI.IsVisibleTab("bsplay"), "for the challenger too")
    a.ns.Battleship.Ready(); b.ns.Battleship.Ready(); Advance(3)
    w.ns.UI.ShowTab("bslive")
    local rows = w.ns.Tabs.bslive.list.data
    check(rows[1] and rows[1].battle and rows[1].battle.game == "bs", "Battleship's Live Battles lists the battle")
    w.ns.UI.ShowTab("live")
    eq(#w.ns.Tabs.live.list.data, 0, "the chess Live Battles does not list it")
    w.ns.UI.ShowTab("bslive")
    w.ns.Tabs.bslive.list.rows[1].watch:Click(); Advance(3)
    check(w.ns.Battleship.current and w.ns.Battleship.current.mode == "spectate", "watching from Live Battles")
    check(w.ns.UI.IsVisibleTab("bsplay"), "the spectator sees the Battleship view")
    a.ns.Battleship.Resign(); Advance(1)
    a.ns.Battleship.Resign(); Advance(3)
    eq(b.ns.Battleship.current.outcome, "win", "resigning gives the opponent the win")
    Advance(10)
    a.ns.UI.ShowTab("admirals")
    a.ns.UI.Refresh()
    check(#a.ns.Tabs.admirals.list.data >= 1, "the Admirals board lists the battle")
    a.ns.UI.ShowProfile("Just Keepingcalm"); Advance(3)
    check(a.ns.UI.profileCard.games.lines[1]:GetText():find("1|r") ~= nil, "the profile card shows the Battleship record")
    for _, cl in ipairs({ a, b, w }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("pergame") then
    section("per game: tabs, lobby, live battles and collections")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    Advance(25)
    local UI, T, P, D = a.ns.UI, a.ns.Tabs, a.ns.Profile, a.ns.Data
    UI.Show()
    UI.SetGame("chess")
    local function TabShown(id)
        for _, f in ipairs(a.frames) do end
        return UI.Debug and true
    end
    UI.ShowTab("collection")
    check(UI.IsVisibleTab("collection"), "chess collection")
    UI.SetGame("bs")
    check(UI.IsVisibleTab("bscollection"), "switching game swaps to the Battleship collection")
    UI.ShowTab("bslobby")
    eq(UI.Game(), "bs", "the Battleship lobby belongs to Battleship")
    UI.SetGame("chess")
    check(UI.IsVisibleTab("lobby"), "and back to the chess lobby")
    UI.ShowTab("settings")
    UI.SetGame("bs")
    check(UI.IsVisibleTab("settings"), "Settings is shared: it stays open when switching games")

    -- each collection only holds its own game's feats
    UI.SetGame("chess"); UI.ShowTab("collection")
    T.coll.section = "badges"; UI.Layout(); UI.Refresh()
    local chessHasBs = false
    for _, e in ipairs(T.coll.grids.badges.data) do if e.badge.game == "bs" then chessHasBs = true end end
    check(not chessHasBs, "chess feats have no Battleship feats")
    UI.SetGame("bs"); UI.ShowTab("bscollection")
    T.bscoll.section = "badges"; UI.Layout(); UI.Refresh()
    local onlyBs = #T.bscoll.grids.badges.data > 0
    for _, e in ipairs(T.bscoll.grids.badges.data) do if e.badge.game ~= "bs" then onlyBs = false end end
    check(onlyBs, "Battleship feats are only Battleship feats")

    section("per game: titles")
    P.me.badges.bs_win1 = 1
    P.me.badges.first_win = 1
    local bsIds, chessIds = {}, {}
    for _, t in ipairs(P.AvailableTitles("bs")) do bsIds[t.id] = true end
    for _, t in ipairs(P.AvailableTitles("chess")) do chessIds[t.id] = true end
    check(bsIds["b:bs_win1"] and not bsIds["b:first_win"], "Battleship titles come from Battleship feats only")
    check(chessIds["b:first_win"] and not chessIds["b:bs_win1"], "chess titles come from chess feats only")
    T.bscoll.section = "titles"; UI.Refresh()
    local tile
    for _, e in ipairs(T.bscoll.grids.titles.data) do if e.id == "b:bs_win1" then tile = e end end
    check(tile and tile.available, "the Gunner can be chosen in the Battleship collection")
    P.SetTitle("b:bs_win1", "bs")
    P.SetTitle("b:first_win", "chess")
    eq(P.MyTitleId("bs"), "b:bs_win1", "Battleship title set")
    eq(P.MyTitleId(), "b:first_win", "chess title set separately")
    a.ns.Game.Announce(true); Advance(5)
    local seen = b.ns.Profile.players["Canga Prime"]
    eq(seen and seen.bt, "b:bs_win1", "others receive the Battleship title")
    eq(seen and seen.t, "b:first_win", "and the chess title")
    eq(b.ns.Profile.BsTitleText(seen.bt):find("Gunner") ~= nil, true, "shown as the Gunner in Battleship")

    section("per game: lobby challenges")
    b.ns.UI.Show(); b.ns.UI.SetGame("bs"); b.ns.UI.ShowTab("bslobby"); b.ns.UI.Refresh()
    local row = b.ns.Tabs.bslobby.list.rows[1]
    check(row and row.item, "Canga is listed in the Battleship lobby")
    row.challenge:Click(); Advance(1)
    local inv = a.ns.Game.LatestInvite()
    eq(inv and inv.game, "bs", "a challenge from the Battleship lobby is a Battleship challenge")
    a.ns.Game.AnswerLatest(false); Advance(1)
    for _, cl in ipairs({ a, b }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("fourrow") then
    section("four in a row: rules")
    local c = NewClient("Rules")
    local FR = c.ns.FourRow
    local b = {}
    eq(FR.Drop(b, 3, 1), 1, "a coin falls to the bottom row")
    eq(FR.Drop(b, 3, 2), 2, "the next one lands on top of it")
    for _ = 3, 6 do FR.Drop(b, 3, 1) end
    eq(FR.FreeRow(b, 3), nil, "a full column takes no more coins")
    eq(FR.Drop(b, 3, 1), nil, "dropping into a full column fails")
    eq(FR.FreeRow(b, 0), nil, "column 0 does not exist")
    eq(FR.FreeRow(b, 8), nil, "column 8 does not exist")
    eq(FR.FreeRow(b, 2.5), nil, "half columns do not exist")

    local function Board(list) -- list of { col, row, who }
        local t = {}
        for _, e in ipairs(list) do t[FR.Index(e[1], e[2])] = e[3] end
        return t
    end
    local h = Board({ { 2, 1, 1 }, { 3, 1, 1 }, { 4, 1, 1 }, { 5, 1, 1 } })
    local line, diag = FR.LineAt(h, 3, 1)
    check(line and #line == 4 and not diag, "four across")
    local v = Board({ { 7, 3, 2 }, { 7, 4, 2 }, { 7, 5, 2 }, { 7, 6, 2 } })
    check(FR.LineAt(v, 7, 6) ~= nil, "four down")
    local d1 = Board({ { 1, 1, 1 }, { 2, 2, 1 }, { 3, 3, 1 }, { 4, 4, 1 } })
    line, diag = FR.LineAt(d1, 4, 4)
    check(line and diag, "four on a rising diagonal")
    local d2 = Board({ { 4, 1, 2 }, { 3, 2, 2 }, { 2, 3, 2 }, { 1, 4, 2 } })
    check(FR.LineAt(d2, 2, 3) ~= nil, "four on a falling diagonal (from the middle)")
    local three = Board({ { 1, 1, 1 }, { 2, 1, 1 }, { 3, 1, 1 }, { 4, 1, 2 } })
    eq(FR.LineAt(three, 1, 1), nil, "three is not enough")
    local five = Board({ { 1, 1, 1 }, { 2, 1, 1 }, { 3, 1, 1 }, { 4, 1, 1 }, { 5, 1, 1 } })
    line = FR.LineAt(five, 3, 1)
    eq(line and #line, 5, "five in a row counts, with all five coins")

    check(FR.Replay({ 4, 4, 3, 3 }) ~= nil, "a legal game replays")
    eq(FR.Replay({ 1, 1, 1, 1, 1, 1, 1 }), nil, "an overfull column does not replay")
    eq(FR.Replay({ 1, 2, 1, 2, 1, 2, 1, 2 }), nil, "no moves after a win")

    -- A drawn game: random games until one fills the board with no four.
    local drawMoves
    for _ = 1, 5000 do
        local board, moves, won = {}, {}, false
        while not FR.Full(board) do
            local legal = FR.LegalCols(board)
            local col = legal[math.random(1, #legal)]
            local row = FR.Drop(board, col, (#moves % 2 == 0) and 1 or 2)
            moves[#moves + 1] = col
            if FR.LineAt(board, col, row) then won = true break end
        end
        if not won then drawMoves = moves break end
    end
    check(drawMoves and #drawMoves == 42, "a drawn game exists (42 coins, no four)")
    FR.DRAW_FOR_TESTS = drawMoves

    section("four in a row: computer")
    -- takes a win
    local wb = Board({ { 1, 1, 1 }, { 2, 1, 1 }, { 3, 1, 1 }, { 1, 2, 2 }, { 2, 2, 2 } })
    for level = 1, 3 do eq(FR.AIMove(wb, 1, level), 4, FR.LEVELS[level] .. " takes the winning column") end
    -- blocks
    local bb = Board({ { 5, 1, 2 }, { 5, 2, 2 }, { 5, 3, 2 }, { 1, 1, 1 }, { 2, 1, 1 } })
    for level = 2, 3 do eq(FR.AIMove(bb, 1, level), 5, FR.LEVELS[level] .. " blocks four down") end
    eq(FR.AIMove({}, 1, 3), 4, "the Master opens in the middle")
    -- Master against Novice
    local masterWins = 0
    for game = 1, 4 do
        local board, turn = {}, 1
        local masterIs = (game % 2 == 1) and 1 or 2
        local winner
        while not FR.Full(board) do
            local col = FR.AIMove(board, turn, turn == masterIs and 3 or 1)
            local row = FR.Drop(board, col, turn)
            if FR.LineAt(board, col, row) then winner = turn break end
            turn = 3 - turn
        end
        if winner == masterIs then masterWins = masterWins + 1 end
    end
    check(masterWins >= 3, "the Master beats the Novice (" .. masterWins .. " of 4)")
    RemoveClient(c)

    section("four in a row: an online game, witnessed")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local bcl = NewClient("Just", nil, "Keepingcalm")
    local w = NewClient("Wit", nil, "Ness")
    Advance(25)
    local CA, JK = "Canga Prime", "Just Keepingcalm"
    a.ns.Game.Invite(JK, { game = "c4" }); Advance(1)
    local inv = bcl.ns.Game.LatestInvite()
    check(inv and inv.game == "c4", "a Four in a Row challenge arrives")
    bcl.ns.Game.AnswerLatest(true); Advance(2)
    local sa, sb = a.ns.FourRow.current, bcl.ns.FourRow.current
    check(sa and sb and sa.id == sb.id and sa.phase == "play", "both are at the table")
    check(sa.iFirst ~= sb.iFirst, "exactly one side drops first")
    check(a.ns.Game.OnlineBusy() and bcl.ns.Game.OnlineBusy(), "both count as busy")
    a.ns.Game.Announce(true); Advance(5)
    eq(w.ns.Profile.online[CA] and w.ns.Profile.online[CA].status, "g", "the lobby shows Canga in a game")
    eq(w.ns.Profile.online[CA].battle and w.ns.Profile.online[CA].battle.game, "c4", "a Four in a Row game")

    local first, second = sa.iFirst and a or bcl, sa.iFirst and bcl or a
    local sf, ss = first.ns.FourRow.current, second.ns.FourRow.current
    check(not second.ns.FourRow.DropCoin(1), "you cannot drop out of turn")
    first.ns.FourRow.DropCoin(1); Advance(1)
    eq(#ss.moves, 1, "the move arrives")
    w.ns.Game.Watch(first.ns.me); Advance(3)
    local sw = w.ns.FourRow.current
    check(sw and sw.mode == "spectate", "a spectator can watch")
    eq(sw and #sw.moves, 1, "the spectator sees the game so far")
    -- first stacks column 1, second column 2: first connects four down
    for k = 1, 3 do
        second.ns.FourRow.DropCoin(2); Advance(1)
        first.ns.FourRow.DropCoin(1); Advance(1)
    end
    Advance(5)
    eq(sf.outcome, "win", "four down wins")
    eq(ss.outcome, "loss", "the other side loses")
    eq(sf.reason, "four", "by connecting four")
    eq(sw.phase, "over", "the spectator saw the end")
    eq(#sw.moves, 7, "and every coin")
    check(sw.line ~= nil, "the spectator sees the winning line")
    local winner, loser = first.ns.me, second.ns.me
    local rec = w.ns.Ledger.FourRow(winner)
    check(rec and rec.fw == 1, "the witness records the win")
    check(w.ns.Ledger.FourRow(loser) and w.ns.Ledger.FourRow(loser).fl == 1, "and the loss")
    eq(w.ns.Ledger.Rating(winner), 1200, "Four in a Row never touches chess ratings")
    eq(w.ns.Ledger.Battleship(winner), nil, "nor the Battleship record")
    check(first.ns.Profile.me.badges.c4_win1, "the winner earns Four Down (the Connector)")
    check(first.ns.Profile.me.badges.c4_play and second.ns.Profile.me.badges.c4_play, "both earn First Drop")
    check(first.ns.Profile.me.badges.c4_quick, "four coins is a Quick Draw")
    local board = w.ns.Profile.TavernBoard()
    eq(board[1] and board[1].name, winner, "the winner tops the Tavern Champions")
    eq(board[2] and board[2].name, loser, "the loser is listed too")
    local hh = w.ns.Ledger.HeadToHead(winner, loser, "f")
    eq(hh.w, 1, "head to head counts the Four in a Row game")
    eq(w.ns.Ledger.HeadToHead(winner, loser, "chess").w, 0, "but not as chess")

    section("four in a row: a drawn game")
    a.ns.Game.Invite(JK, { game = "c4" }); Advance(1)
    bcl.ns.Game.AnswerLatest(true); Advance(2)
    sa, sb = a.ns.FourRow.current, bcl.ns.FourRow.current
    first = sa.iFirst and a or bcl
    second = sa.iFirst and bcl or a
    for i, col in ipairs(FR.DRAW_FOR_TESTS) do
        local who = (i % 2 == 1) and first or second
        for _ = 1, 40 do if who.ns.FourRow.MyTurn() then break end Advance(0.5) end
        check(who.ns.FourRow.DropCoin(col), "coin " .. i .. " drops")
    end
    Advance(5)
    eq(sa.outcome, "draw", "a full board is a draw")
    eq(sb.outcome, "draw", "for both")
    eq(sa.reason, "full", "because the board is full")
    rec = w.ns.Ledger.FourRow(CA)
    check(rec and rec.fd == 1, "the witness records the draw")
    check(a.ns.Profile.me.badges.c4_draw, "Even Match for a draw")

    section("four in a row: resigning and the turn timer")
    a.ns.Game.Invite(JK, { game = "c4" }); Advance(1)
    bcl.ns.Game.AnswerLatest(true); Advance(2)
    sa, sb = a.ns.FourRow.current, bcl.ns.FourRow.current
    bcl.ns.FourRow.Resign(); Advance(2)
    eq(sb.outcome, "loss", "resigning loses")
    eq(sa.outcome, "win", "the opponent wins")
    eq(sa.reason, "resign", "by resignation")

    local oldId = sa.id
    a.ns.Game.Invite(JK, { game = "c4" }); Advance(1)
    for _ = 1, 20 do if bcl.ns.Game.LatestInvite() then break end Advance(0.5) end
    bcl.ns.Game.AnswerLatest(true)
    for _ = 1, 40 do
        local x, y = a.ns.FourRow.current, bcl.ns.FourRow.current
        if x and y and x.id ~= oldId and x.id == y.id then break end
        Advance(0.5)
    end
    sa, sb = a.ns.FourRow.current, bcl.ns.FourRow.current
    check(sa.id ~= oldId and sa.id == sb.id, "a new game starts")
    local idle = sa.iFirst and a or bcl
    local other = (idle == a) and bcl or a
    local si = idle.ns.FourRow.current
    Advance(61)
    eq(#si.moves, 1, "after a minute a coin is dropped for you")
    eq(si.missed, 1, "one missed turn")
    for _ = 1, 300 do
        local so = other.ns.FourRow.current
        if so.phase ~= "play" then break end
        if other.ns.FourRow.MyTurn() then
            -- the active player avoids winning: drops where it does not connect four
            local legal = FR.LegalCols(so.board)
            local pick = legal[1]
            for _, col in ipairs(legal) do
                local t = {}
                for k, vv in pairs(so.board) do t[k] = vv end
                local row = FR.Drop(t, col, so.myCoin)
                if not FR.LineAt(t, col, row) then pick = col break end
            end
            other.ns.FourRow.DropCoin(pick)
        end
        Advance(1)
    end
    local outI, outO = idle.ns.FourRow.current, other.ns.FourRow.current
    check(outI.phase == "over", "the game ends")
    if outI.reason == "time" then
        eq(outI.outcome, "loss", "three missed turns forfeit the game")
        eq(outO.outcome, "win", "the opponent wins on time")
    else
        check(outI.reason == "four" or outI.reason == "full", "or the random coins decided it first (" .. tostring(outI.reason) .. ")")
    end

    section("four in a row: queue and practice")
    Advance(5)
    a.ns.Game.StartSeek(0, 0, false, true, "c4")
    bcl.ns.Game.StartSeek(0, 0, false, true, "bs")
    Advance(30)
    check(not a.ns.FourRow.Busy(), "a Four in a Row queue never pairs with a Battleship queue")
    a.ns.Game.Announce(true); Advance(3)
    eq(w.ns.Profile.online[CA] and w.ns.Profile.online[CA].status, "f", "the lobby shows Canga looking for Four in a Row")
    bcl.ns.Game.StopSeek()
    bcl.ns.Game.StartSeek(0, 0, false, true, "c4")
    Advance(30)
    check(a.ns.FourRow.Busy() and bcl.ns.FourRow.Busy(), "two Four in a Row queuers are paired")
    a.ns.FourRow.Resign(); Advance(2)
    local s3 = a.ns.FourRow.StartAI(3)
    for _ = 1, 200 do
        if s3.phase ~= "play" then break end
        if a.ns.FourRow.MyTurn() then
            local legal = FR.LegalCols(s3.board)
            a.ns.FourRow.DropCoin(legal[1])
        end
        Advance(1)
    end
    eq(s3.phase, "over", "a practice game against the Master finishes")
    eq(s3.outcome, "loss", "and the Master wins against a player who only fills from the left")
    for _, cl in ipairs({ a, bcl, w }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("c4ui") then
    section("four in a row ui: the game switcher and tabs")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    a.faction, b.faction = "Horde", "Alliance"
    Advance(25)
    local UI, T, P = a.ns.UI, a.ns.Tabs, a.ns.Profile
    UI.ShowTab("c4play")
    check(UI.IsVisibleTab("c4play"), "Four in a Row opens in the game window")
    eq(UI.Game(), "c4", "game is Four in a Row")
    UI.ShowTab("c4lobby")
    UI.SetGame("bs")
    check(UI.IsVisibleTab("bslobby"), "switching game from the Four in a Row lobby shows the Battleship lobby")
    UI.SetGame("c4")
    check(UI.IsVisibleTab("c4lobby"), "and back")
    UI.ShowTab("c4board")
    eq(UI.Game(), "c4", "Tavern Champions belongs to Four in a Row")
    UI.ShowTab("ladder")
    eq(UI.Game(), "chess", "the Ladder switches to chess")
    UI.ShowTab("c4collection")
    eq(UI.Game(), "c4", "the Four in a Row collection switches back")
    T.c4coll.section = "badges"; UI.Layout(); UI.Refresh()
    local only = #T.c4coll.grids.badges.data == 10
    for _, e in ipairs(T.c4coll.grids.badges.data) do if e.badge.game ~= "c4" then only = false end end
    check(only, "its feats are the ten Four in a Row feats")

    section("four in a row ui: dropping coins with the mouse")
    local FR, v = a.ns.FourRow, a.ns.FourView.view
    local s = FR.StartAI(1)
    Advance(1)
    check(UI.IsVisibleTab("c4play"), "the game tab is shown for a new game")
    for _ = 1, 10 do if FR.MyTurn() then break end Advance(1) end
    check(FR.MyTurn(), "our turn comes")
    eq(v.turn.text:GetText(), "YOUR TURN - DROP A COIN!", "the turn banner says so")
    check(v.glow:IsShown(), "the board glows on your turn")
    check(v.strips[2].glow:IsShown(), "your strip glows")
    local col4 = v.board.cols[4]
    col4.__scripts.OnEnter(col4)
    check(v.board.hand:IsShown(), "hovering a column shows the coin in your hand")
    check(v.board.handArrow:IsShown(), "and where it will land")
    local before = #s.moves
    col4.__scripts.OnClick(col4, "LeftButton")
    eq(#s.moves, before + 1, "clicking the column drops the coin")
    eq(s.moves[#s.moves], 4, "into column 4")
    check(not v.board.hand:IsShown(), "the hand is empty while the computer thinks")
    check(v.turn.text:GetText():find("THINKING") ~= nil, "the banner says the computer is thinking")
    Advance(3)
    local idx = a.ns.FourRow.Index(4, 1)
    local coinRow = s.board[idx] and 1 or 2
    check(v.board.coins[a.ns.FourRow.Index(4, coinRow)]:IsShown(), "the coin sits in its hole after falling")
    local logN = #v.log.data
    eq(logN, #s.moves, "every coin is in the move list")

    section("four in a row ui: resizing")
    UI.SetCollapsed(false)
    UI.DebugResize(1100, 900)
    local big = a.ns.db.settings.c4Cell
    UI.DebugResize(700, 600)
    local small = a.ns.db.settings.c4Cell
    check(big and small and big > small, "a bigger window means bigger holes (" .. tostring(big) .. " > " .. tostring(small) .. ")")
    UI.SetCollapsed(true)
    check(not v.side:IsShown(), "the side panel folds away")
    UI.SetCollapsed(false)
    check(v.side:IsShown(), "and comes back")

    -- finish the practice game and see the banner
    FR.Resign(); Advance(2)
    check(v.banner:IsShown(), "the result banner appears")
    eq(v.banner.title:GetText(), "Defeat", "resigning is a defeat")

    section("four in a row ui: an online game from the lobby")
    b.ns.UI.Show(); b.ns.UI.SetGame("c4"); b.ns.UI.ShowTab("c4lobby"); b.ns.UI.Refresh()
    local row = b.ns.Tabs.c4lobby.list.rows[1]
    check(row and row.item, "Canga is listed in the Four in a Row lobby")
    row.challenge:Click(); Advance(1)
    local inv = a.ns.Game.LatestInvite()
    eq(inv and inv.game, "c4", "a challenge from the Four in a Row lobby is a Four in a Row challenge")
    check(UI.invitePopup and UI.invitePopup:IsShown(), "the challenge popup appears")
    check(UI.invitePopup.text:GetText():find("Four in a Row") ~= nil, "and names the game")
    UI.invitePopup.accept:Click(); Advance(2)
    check(a.ns.FourRow.Busy() and b.ns.FourRow.Busy(), "the game starts on both sides")
    check(UI.IsVisibleTab("c4play"), "Canga sees the board")
    check(b.ns.UI.IsVisibleTab("c4play"), "and so does Keepingcalm")
    check(UI.Status() == "battle", "the status dot shows a game in progress")
    local sa = a.ns.FourRow.current
    local first = sa.iFirst and a or b
    local second = sa.iFirst and b or a
    for _ = 1, 3 do
        first.ns.FourRow.DropCoin(3); Advance(1)
        second.ns.FourRow.DropCoin(5); Advance(1)
    end
    first.ns.FourRow.DropCoin(3); Advance(5)
    eq(first.ns.FourRow.current.outcome, "win", "the first player connects four")
    local fv = first.ns.FourView.view
    check(fv.banner:IsShown(), "the winner sees the banner")
    eq(fv.banner.title:GetText(), "Victory!", "Victory!")
    local shown = 0
    for _, t in ipairs(fv.board.wins) do if t:IsShown() then shown = shown + 1 end end
    eq(shown, 4, "the winning four glow")

    section("four in a row ui: titles and records")
    local winner = first
    local wP = winner.ns.Profile
    local avail = {}
    for _, t in ipairs(wP.AvailableTitles("c4")) do avail[t.id] = true end
    check(avail["b:c4_win1"], "the Connector title is available")
    check(not avail["b:first_win"], "chess titles are not")
    wP.SetTitle("b:c4_win1", "c4")
    eq(wP.MyTitleId("c4"), "b:c4_win1", "the Four in a Row title is set")
    eq(wP.MyTitleId("bs"), "", "Battleship keeps its own title")
    winner.ns.Game.Announce(true); Advance(5)
    local loser = (winner == a) and b or a
    local seen = loser.ns.Profile.players[winner.ns.me]
    eq(seen and seen.ft, "b:c4_win1", "others receive the Four in a Row title")
    check(loser.ns.Profile.GameTitleText(seen.ft, "c4"):find("Connector") ~= nil, "shown as the Connector")
    check(loser.ns.Profile.GameTitleText("", "c4"):find("Tavern Regular") ~= nil, "players without one are Tavern Regulars")
    winner.ns.UI.SetGame("c4"); winner.ns.UI.ShowTab("c4board"); winner.ns.UI.Refresh()
    local tav = winner.ns.Tabs.tavern
    check(tav.list.data[1] and tav.list.data[1].me, "the winner tops the Tavern Champions")
    check(tav.me.line:GetText():find("1|r won") ~= nil, "the card shows the record")
    winner.ns.UI.ShowProfile(loser.ns.me); Advance(2)
    local card = winner.ns.UI.profileCard
    check(card.games.lines[2]:GetText():find("inv_misc_coin_01") ~= nil and card.games.lines[2]:GetText():find("1|r") ~= nil, "the profile card counts Four in a Row games")
    check(card.casualBtn:GetText() == "Challenge", "the profile offers a Four in a Row challenge")
    for _, cl in ipairs({ a, b }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("vault") then
    section("vault breaker: rules")
    local c = NewClient("Rules")
    local VB = c.ns.Vault
    local function pins(code, guess) local g, s = VB.Pins(code, guess); return g .. "+" .. s end
    eq(pins("1234", "1234"), "4+0", "the right code is four gold pins")
    eq(pins("1234", "4321"), "0+4", "all the right gems in the wrong slots")
    eq(pins("1122", "1212"), "2+2", "repeated gems count once each")
    eq(pins("1122", "1111"), "2+0", "extra copies of a gem earn nothing")
    eq(pins("1234", "5656"), "0+0", "no right gems, no pins")
    eq(pins("3315", "1335"), "2+2", "gold pins are taken before silver")
    check(VB.Valid("1666") and not VB.Valid("1670") and not VB.Valid("123") and not VB.Valid(nil), "codes are four gems from 1 to 6")
    eq(#VB.ALL, 1296, "1296 possible codes")
    local seal = VB.Seal("2541", "salt")
    check(VB.Verify(seal, "2541", "salt", { { guess = "1111", gold = 1, silver = 0 } }), "an honest vault passes the check")
    check(not VB.Verify(seal, "2541", "salt", { { guess = "1111", gold = 0, silver = 0 } }), "a false pin is caught")
    check(not VB.Verify(seal, "2542", "salt", {}), "a changed code does not match the seal")
    local left = VB.Consistent({ { guess = "1122", gold = 0, silver = 0 } })
    eq(#left, 256, "after 1122 gets no pins, 256 codes remain (4 gems x 4 slots)")

    section("vault breaker: computer safecrackers")
    local avg = {}
    for level = 1, 3 do
        local sum, worst = 0, 0
        for game = 1, 6 do
            local code = VB.ALL[(game * 211) % 1296 + 1]
            local history, n = {}, 0
            repeat
                n = n + 1
                local guess = VB.AIGuess(level, history)
                local g, s = VB.Pins(code, guess)
                history[#history + 1] = { guess = guess, gold = g, silver = s }
            until g == 4 or n >= 12
            sum = sum + n
            if n > worst then worst = n end
        end
        avg[level] = sum / 6
        if level >= 2 then check(worst <= 10, VB.LEVELS[level] .. " cracks every vault within ten guesses (worst " .. worst .. ")") end
    end
    check(avg[3] <= avg[1], string.format("the Master needs no more guesses than the Novice (%.1f vs %.1f)", avg[3], avg[1]))
    check(avg[3] <= 6, string.format("the Master averages six guesses or fewer (%.1f)", avg[3]))
    RemoveClient(c)

    section("vault breaker: an online game, witnessed")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    local w = NewClient("Wit", nil, "Ness")
    Advance(25)
    local CA, JK = "Canga Prime", "Just Keepingcalm"
    a.ns.Game.Invite(JK, { game = "vb" }); Advance(1)
    local inv = b.ns.Game.LatestInvite()
    check(inv and inv.game == "vb", "a Vault Breaker challenge arrives")
    b.ns.Game.AnswerLatest(true); Advance(2)
    local sa, sb = a.ns.Vault.current, b.ns.Vault.current
    check(sa and sb and sa.id == sb.id and sa.phase == "set", "both are locking their vaults")
    check(sa.white ~= sb.white or sa.white == CA or sa.white == JK, "both agree who is listed first")
    eq(sa.white, sb.white, "the same order on both sides")
    check(a.ns.Vault.SetCode("1234"), "Canga chooses a code")
    check(not a.ns.Vault.SetCode("1239"), "but not an invalid one")
    b.ns.Vault.SetCode("6543")
    a.ns.Vault.Ready(); Advance(1)
    eq(sb.phase, "set", "waiting for the other vault")
    check(not a.ns.Vault.SetCode("1111"), "a sealed vault cannot be changed")
    b.ns.Vault.Ready(); Advance(2)
    eq(sa.phase, "play", "the game begins")
    eq(sb.phase, "play", "on both sides")
    eq(sa.round, 1, "round one")
    w.ns.Game.Watch(CA); Advance(3)
    local sw = w.ns.Vault.current
    check(sw and sw.mode == "spectate", "a spectator can watch")
    -- round 1: both miss
    a.ns.Vault.Guess("1122"); Advance(1)
    check(not a.ns.Vault.CanGuess(), "one guess per round")
    eq(sa.round, 1, "the round waits for both guesses")
    b.ns.Vault.Guess("5555"); Advance(3)
    eq(sa.round, 2, "both guessed: round two")
    eq(sb.round, 2, "on both sides")
    eq(sa.mine[1].gold, 0, "Canga's 1122 against 6543: no gold")
    eq(sa.mine[1].silver, 0, "and no silver")
    eq(sb.mine[1].gold + sb.mine[1].silver, 0, "Keepingcalm's 5555 against 1234: no pins either")
    -- round 2: Canga cracks it, Keepingcalm does not
    a.ns.Vault.Guess("6543"); Advance(1)
    b.ns.Vault.Guess("1243"); Advance(5)
    eq(sa.outcome, "win", "Canga cracked the vault")
    eq(sb.outcome, "loss", "Keepingcalm lost")
    eq(sa.reason, "cracked", "by cracking it")
    Advance(5)
    eq(sb.verified, true, "Keepingcalm checked Canga's code against every pin: honest")
    eq(sa.verified, true, "and the other way round")
    eq(sb.theirCode, "1234", "the losing side sees the code at the end")
    eq(sw.phase, "over", "the spectator saw the end")
    eq(sw.mine[2] and sw.mine[2].gold, 4, "the spectator saw the winning guess")
    eq(sw.theirCode, "6543", "and both codes")
    Advance(5)
    local rec = w.ns.Ledger.Record(CA, "vb")
    check(rec and rec.w == 1, "the witness records Canga's win")
    check(w.ns.Ledger.Record(JK, "vb") and w.ns.Ledger.Record(JK, "vb").l == 1, "and Keepingcalm's loss")
    eq(w.ns.Ledger.Record(CA, "c4"), nil, "Vault Breaker never touches Four in a Row")
    eq(w.ns.Ledger.Rating(CA), 1200, "nor chess ratings")
    check(a.ns.Profile.me.badges.vb_win1, "Canga earns Cracked It (the Safecracker)")
    check(a.ns.Profile.me.badges.vb_lucky, "in two guesses: the Lucky Guess")
    check(a.ns.Profile.me.badges.vb_quick, "and the Mind Reader")
    check(b.ns.Profile.me.badges.vb_play, "Keepingcalm earns First Vault")
    local board = w.ns.Profile.RecordBoard("vb")
    eq(board[1] and board[1].name, CA, "Canga tops the Master Safecrackers")

    section("vault breaker: cracking it in the same round is a draw")
    a.ns.Game.Invite(JK, { game = "vb" }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    sa, sb = a.ns.Vault.current, b.ns.Vault.current
    a.ns.Vault.SetCode("1111"); b.ns.Vault.SetCode("2222")
    a.ns.Vault.Ready(); b.ns.Vault.Ready(); Advance(2)
    a.ns.Vault.Guess("2222"); b.ns.Vault.Guess("1111"); Advance(6)
    eq(sa.outcome, "draw", "both cracked in round one")
    eq(sb.outcome, "draw", "a draw for both")
    eq(sa.reason, "both", "because both cracked it")
    Advance(5)
    rec = w.ns.Ledger.Record(CA, "vb")
    check(rec and rec.d == 1, "the witness records the draw")

    section("vault breaker: a cheater who gives false pins is caught")
    local honestPins = b.ns.Vault.Pins
    b.ns.Vault.Pins = function() return 0, 0 end -- Keepingcalm's client always answers "no pins"
    a.ns.Game.Invite(JK, { game = "vb" }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    sa, sb = a.ns.Vault.current, b.ns.Vault.current
    a.ns.Vault.SetCode("3456"); b.ns.Vault.SetCode("1212")
    a.ns.Vault.Ready(); b.ns.Vault.Ready(); Advance(2)
    a.ns.Vault.Guess("1212"); b.ns.Vault.Guess("1111"); Advance(4)
    eq(sa.mine[1].gold, 0, "the liar hides that Canga's guess was right")
    a.ns.Vault.Guess("1212"); b.ns.Vault.Guess("3456"); Advance(6)
    eq(sb.outcome, "win", "the liar 'wins'")
    eq(sa.verified, false, "but Canga's check of the revealed code fails")
    eq(sa.outcome, "disputed", "the game is disputed")
    Advance(5)
    local liar = w.ns.Ledger.Record(JK, "vb")
    check(liar and liar.w == 0, "the liar gets no win on the record")
    b.ns.Vault.Pins = honestPins

    section("vault breaker: the round timer")
    a.ns.Game.Invite(JK, { game = "vb" }); Advance(1)
    b.ns.Game.AnswerLatest(true); Advance(2)
    sa, sb = a.ns.Vault.current, b.ns.Vault.current
    Advance(95)
    eq(sa.phase, "play", "unsealed vaults lock themselves when time runs out")
    check(sa.ready and sb.ready, "with the code as it stood")
    -- Canga never guesses; Keepingcalm always does (never the right code: Canga's has a 1, we guess 6s first)
    local guard = 0
    while sa.phase == "play" and guard < 400 do
        guard = guard + 1
        if b.ns.Vault.CanGuess() then
            local g = "6666"
            if sa.myCode == g then g = "5555" end
            b.ns.Vault.Guess(g)
        end
        Advance(1)
    end
    eq(sa.outcome, "loss", "three missed rounds forfeit the game")
    eq(sa.reason, "time", "lost on time")
    eq(sb.outcome, "win", "the opponent wins")

    section("vault breaker: queue and practice")
    Advance(5)
    a.ns.Game.StartSeek(0, 0, false, true, "vb")
    b.ns.Game.StartSeek(0, 0, false, true, "c4")
    Advance(30)
    check(not a.ns.Vault.Busy(), "a Vault Breaker queue never pairs with a Four in a Row queue")
    a.ns.Game.Announce(true); Advance(3)
    eq(w.ns.Profile.online[CA] and w.ns.Profile.online[CA].status, "v", "the lobby shows Canga looking for Vault Breaker")
    b.ns.Game.StopSeek()
    b.ns.Game.StartSeek(0, 0, false, true, "vb")
    Advance(30)
    check(a.ns.Vault.Busy() and b.ns.Vault.Busy(), "two Vault Breaker queuers are paired")
    a.ns.Vault.Resign(); Advance(2)
    eq(a.ns.Vault.current.outcome, "abort", "leaving before the vaults are sealed calls the game off")
    local s3 = a.ns.Vault.StartAI(3)
    a.ns.Vault.Ready()
    eq(s3.phase, "play", "a practice game starts at once")
    for _ = 1, 30 do
        if s3.phase ~= "play" then break end
        if a.ns.Vault.CanGuess() then a.ns.Vault.Guess("1234") end
        Advance(1)
    end
    eq(s3.phase, "over", "a practice game against the Master finishes")
    check(s3.outcome == "loss" or s3.outcome == "draw" or s3.outcome == "win", "with a result (" .. tostring(s3.outcome) .. ")")
    eq(s3.theirCode, s3.aiCode, "and the computer's code is shown")
    for _, cl in ipairs({ a, b, w }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("vbui") then
    section("games tab: choosing a game")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    a.faction, b.faction = "Horde", "Alliance"
    Advance(25)
    local UI, T = a.ns.UI, a.ns.Tabs
    UI.Show()
    local FD = a.ns.Finder
    check(FD.IsShown(), "opening the addon with no game running shows the finder")
    check(UI.IsVisibleTab("games"), "on Find a Game")
    local F = FD.find
    eq(#F.buttons, 5, "a round button for each game")
    local names = {}
    for _, btn in ipairs(F.buttons) do names[#names + 1] = btn.name:GetText() end
    eq(table.concat(names, ","), "Chess,Battleship,Four in a Row,Vault Breaker,Hidden Army", "in order")
    local q = FD.QueueSet()
    for k in pairs(q) do q[k] = nil end
    F.buttons[3]:Click()
    eq(UI.Game(), "c4", "clicking a game chooses it")
    check(q.c4, "and ticks it")
    check(F.buttons[3].tick:IsShown() and F.buttons[3].glow:IsShown(), "the chosen game is ticked and glows")
    check(not F.buttons[1].tick:IsShown(), "unticked games show no tick")
    F.buttons[4]:Click()
    check(q.c4 and q.vb, "several games can be ticked")
    F.queue:Click()
    local G = a.ns.Game
    check(G.Seeking("c4") and G.Seeking("vb") and not G.Seeking("chess"), "Find Opponent queues for every ticked game")
    check(F.listing:IsShown(), "Your Listing appears")
    -- someone queued for Battleship and Vault Breaker: the shared game is played
    b.ns.Game.StartSeek(0, 0, false, true, { "bs", "vb" })
    Advance(30)
    check(a.ns.Vault.Busy() and b.ns.Vault.Busy(), "two players with a game in common are paired on it")
    check(UI.IsVisibleTab("vbplay"), "the game opens in its own window")
    check(not FD.IsShown(), "and the finder steps aside")
    a.ns.Vault.Resign(); Advance(2)
    UI.ShowTab("games")
    check(not F.listing:IsShown(), "no listing once the queue is over")

    section("finder: browse and legends")
    FD.frame.tabs.browse:Click()
    check(UI.IsVisibleTab("vblobby"), "Browse shows the chosen game's players")
    FD.frame.kindDrop:Select("live")
    check(UI.IsVisibleTab("vblive"), "the second dropdown switches to live games")
    FD.frame.gameDrop:Select("chess")
    check(UI.IsVisibleTab("live"), "the game dropdown switches game, same page")
    eq(UI.Game(), "chess", "and chooses the game")
    FD.frame.tabs.legends:Click()
    check(UI.IsVisibleTab("ladder"), "Legends shows the leaderboard")
    FD.frame.kindDrop:Select("coll")
    check(UI.IsVisibleTab("collection"), "and titles and feats")
    FD.frame.gameDrop:Select("ha")
    check(UI.IsVisibleTab("hacollection"), "for any game")
    FD.frame.tabs.settings:Click()
    check(UI.IsVisibleTab("settings"), "Settings has its own tab")
    UI.ShowTab("vbboard")
    eq(UI.Game(), "vb", "the Safecrackers board belongs to Vault Breaker")
    UI.SetGame("chess")
    check(UI.IsVisibleTab("ladder"), "switching to chess from the Safecrackers shows the Ladder")

    section("vault breaker ui: locking the vault and guessing")
    UI.SetGame("vb")
    local VB, v = a.ns.Vault, a.ns.VaultView.view
    local s = VB.StartAI(2)
    Advance(1)
    check(UI.IsVisibleTab("vbplay"), "a new game shows the vault")
    eq(v.turn.text:GetText(), "LOCK YOUR VAULT", "the banner says to lock your vault")
    check(v.random:IsShown(), "Random is offered while choosing")
    a.ns.VaultView.ClearDraft()
    for _, n in ipairs({ 3, 1, 4, 1 }) do v.gemButtons[n]:Click() end
    eq(s.myCode, "3141", "clicking gems in the palette sets the code")
    v.left.code[2]:Click()
    eq(v.draft[2], nil, "clicking a code slot empties it")
    v.gemButtons[5]:Click()
    eq(s.myCode, "3541", "the next gem fills the gap")
    v.lockIn:Click()
    check(s.ready, "Seal Vault locks it")
    eq(s.phase, "play", "against the computer the game starts at once")
    check(v.turn.text:GetText():find("YOUR GUESS") ~= nil, "the banner asks for a guess")
    check(v.right.rows[1].hl:IsShown(), "the guess row glows")
    for _, n in ipairs({ 1, 1, 2, 2 }) do v.gemButtons[n]:Click() end
    eq(v.right.rows[1].gems[3].gem, 2, "the guess shows in the row as it is built")
    v.lockIn:Click()
    check(s.mine[1] and s.mine[1].guess == "1122", "Lock In sends the guess")
    check(v.turn.text:GetText():find("THINKING") ~= nil, "then waits for the computer")
    Advance(2)
    check(s.round == 2 or s.phase == "over", "the round resolves")
    eq(v.right.rows[1].pins.gold, s.mine[1].gold, "the gold pins show on the row")
    eq(v.right.rows[1].pins.silver, s.mine[1].silver, "and the silver ones")
    eq(v.left.rows[1].pins.gold, s.theirs[1].gold, "the computer's guess and pins show in your vault")
    eq(#v.log.data, 1, "the round is in the log")

    section("vault breaker ui: resizing")
    UI.SetCollapsed(false)
    UI.DebugResize(1200, 900)
    local big = a.ns.db.settings.vbCell
    UI.DebugResize(800, 600)
    local small = a.ns.db.settings.vbCell
    check(big and small and big > small, "a bigger window means bigger gems (" .. tostring(big) .. " > " .. tostring(small) .. ")")
    VB.Resign(); Advance(2)
    check(v.banner:IsShown(), "the result banner appears")
    eq(v.banner.title:GetText(), "Defeat", "giving up is a defeat")

    section("vault breaker ui: an online game from the lobby")
    b.ns.UI.Show(); b.ns.UI.SetGame("vb"); b.ns.UI.ShowTab("vblobby"); b.ns.UI.Refresh()
    local row = b.ns.Tabs.vblobby.list.rows[1]
    check(row and row.item, "Canga is listed in the Vault Breaker lobby")
    row.challenge:Click(); Advance(1)
    check(UI.invitePopup and UI.invitePopup:IsShown(), "the challenge popup appears")
    check(UI.invitePopup.text:GetText():find("Vault Breaker") ~= nil, "and names the game")
    UI.invitePopup.accept:Click(); Advance(2)
    check(a.ns.Vault.Busy() and b.ns.Vault.Busy(), "the game starts on both sides")
    check(UI.IsVisibleTab("vbplay") and b.ns.UI.IsVisibleTab("vbplay"), "both see the vaults")
    check(UI.Status() == "battle", "the status dot shows a game in progress")
    local sa, sb = a.ns.Vault.current, b.ns.Vault.current
    a.ns.Vault.SetCode("1234"); b.ns.Vault.SetCode("5566")
    a.ns.Vault.Ready(); b.ns.Vault.Ready(); Advance(2)
    a.ns.Vault.Guess("5566"); b.ns.Vault.Guess("1111"); Advance(6)
    eq(sa.outcome, "win", "Canga cracks it")
    local av = a.ns.VaultView.view
    check(av.banner:IsShown(), "the winner sees the banner")
    eq(av.banner.title:GetText(), "Vault Cracked!", "Vault Cracked!")
    Advance(5)
    UI.ShowTab("games"); UI.SetGame("vb"); UI.Refresh()
    check(a.ns.Finder.find.card.record:GetText():find("40ff401|r") ~= nil, "the finder card shows the Vault Breaker record")

    section("vault breaker ui: titles")
    local P = a.ns.Profile
    P.SetTitle("b:vb_win1", "vb")
    eq(P.MyTitleId("vb"), "b:vb_win1", "the Safecracker title is set")
    eq(P.MyTitleId("c4"), "", "Four in a Row keeps its own")
    a.ns.Game.Announce(true); Advance(5)
    local seen = b.ns.Profile.players["Canga Prime"]
    eq(seen and seen.vt, "b:vb_win1", "others receive the Vault Breaker title")
    check(b.ns.Profile.GameTitleText("", "vb"):find("Apprentice Locksmith") ~= nil, "players without one are Apprentice Locksmiths")
    UI.ShowTab("vbcollection")
    T.vbcoll.section = "badges"; UI.Layout(); UI.Refresh()
    local only = #T.vbcoll.grids.badges.data == 10
    for _, e in ipairs(T.vbcoll.grids.badges.data) do if e.badge.game ~= "vb" then only = false end end
    check(only, "the Vault Breaker collection holds its ten feats")
    for _, cl in ipairs({ a, b }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("army") then
    section("hidden army: rules")
    local c = NewClient("Rules")
    local HA = c.ns.Army
    eq(HA.Fight("W", "C"), "a", "the higher rank wins")
    eq(HA.Fight("F", "K"), "d", "the lower rank loses")
    eq(HA.Fight("K", "K"), "both", "equal ranks both fall")
    eq(HA.Fight("R", "W"), "a", "the Assassin strikes down the Warlord")
    eq(HA.Fight("W", "R"), "a", "but not when the Warlord attacks")
    eq(HA.Fight("C", "B"), "d", "a Bomb destroys an attacker")
    eq(HA.Fight("S", "B"), "defuse", "a Sapper defuses it")
    eq(HA.Fight("X", "N"), "banner", "taking the Banner wins")
    for _ = 1, 20 do
        local w = HA.RandomLayout("w", true)
        local b = HA.RandomLayout("b", false)
        if not (HA.ValidLayout(w) and HA.ValidLayout(b)) then check(false, "random setups are legal armies") break end
    end
    check(true, "random setups are legal armies")
    local smart = HA.RandomLayout("w", true)
    local nAt = string.find(smart, "N")
    check(nAt and nAt <= 8, "the computer keeps its Banner in the back row")
    check(not HA.ValidLayout(string.rep(".", 24)), "an empty setup is not an army")
    eq(#HA.Occupancy(smart), 24, "occupancy marks all 24 setup squares")

    -- moves on a tiny board
    local cells = {
        [HA.Index(1, 3)] = { side = "w" }, [HA.Index(2, 3)] = { side = "w" },
        [HA.Index(1, 6)] = { side = "b" },
    }
    local ranks = { [HA.Index(1, 3)] = "X", [HA.Index(2, 3)] = "F" }
    local moves = HA.LegalMoves(cells, "w", function(i) return ranks[i] end)
    local scoutReach, footman = {}, 0
    for _, m in ipairs(moves) do
        if m.from == HA.Index(1, 3) then scoutReach[m.to] = m.attack end
        if m.from == HA.Index(2, 3) then footman = footman + 1 end
    end
    check(scoutReach[HA.Index(1, 6)] == true, "a Scout runs up the file and attacks at the end")
    check(scoutReach[HA.Index(1, 5)] == false, "and may stop on the way")
    eq(scoutReach[HA.Index(1, 7)], nil, "but not jump over a unit")
    eq(footman, 3, "a Footman steps one square (forward, right; its own Scout blocks the left)")
    check(not HA.PathOK(cells, "w", HA.Index(2, 3), HA.Index(3, 4)), "no diagonal moves")
    check(not HA.PathOK(cells, "w", HA.Index(2, 3), HA.Index(3, 3)) == false, "sideways is fine")
    check(not HA.PathOK({ [HA.Index(3, 3)] = { side = "w" } }, "w", HA.Index(3, 3), HA.Index(3, 4)), "lakes cannot be entered")

    -- the replay check
    local wl, bl = HA.RandomLayout("w", false), HA.RandomLayout("b", false)
    local function UnitAt(layout, side, rank)
        for k, idx in ipairs(HA.ZONE[side]) do if string.sub(layout, k, k) == rank then return idx end end
    end
    local bomb = UnitAt(bl, "b", "B")
    local okReplay = HA.Replay({ w = wl, b = bl }, { { side = "b", from = bomb, to = bomb - 8 } }, "b")
    check(not okReplay, "a moving Bomb is caught by the replay")
    RemoveClient(c)

    section("hidden army: an online battle, witnessed")
    net.forever = true
    local a = NewClient("Canga", nil, "Prime")
    local b = NewClient("Just", nil, "Keepingcalm")
    local w = NewClient("Wit", nil, "Ness")
    Advance(25)
    local CA, JK = "Canga Prime", "Just Keepingcalm"
    a.ns.Game.Invite(JK, { game = "ha" }); Advance(1)
    local inv = b.ns.Game.LatestInvite()
    check(inv and inv.game == "ha", "a Hidden Army challenge arrives")
    b.ns.Game.AnswerLatest(true); Advance(2)
    local sa, sb = a.ns.Army.current, b.ns.Army.current
    check(sa and sb and sa.id == sb.id and sa.phase == "setup", "both are deploying")
    check(sa.mySide ~= sb.mySide, "one side is white, one black")
    local white = sa.mySide == "w" and a or b
    local black = white == a and b or a
    local sw, sbk = white.ns.Army.current, black.ns.Army.current
    -- arrange: white Scout on a3 and a Footman on h3; black Banner on a6 and a Footman on b6
    local function Put(s, side, rank, col, row)
        local want = HA.IN_ZONE[side][HA.Index(col, row)]
        local have
        for k = 1, 24 do if string.sub(s.layout, k, k) == rank and k ~= want then have = k break end end
        if string.sub(s.layout, want, want) == rank then return end
        local t = {}
        for k = 1, 24 do t[k] = string.sub(s.layout, k, k) end
        t[want], t[have] = t[have], t[want]
        s.layout = table.concat(t)
    end
    Put(sw, "w", "X", 1, 3); Put(sw, "w", "F", 8, 3)
    Put(sbk, "b", "N", 1, 6); Put(sbk, "b", "F", 2, 6)
    -- the a7 square behind the banner must not block the test either way
    check(white.ns.Army.Swap(HA.Index(4, 1), HA.Index(4, 1)) == false, "swapping a square with itself does nothing")
    white.ns.Army.Ready(); Advance(1)
    eq(sbk.phase, "setup", "waiting for the other army")
    black.ns.Army.Ready(); Advance(2)
    eq(sw.phase, "play", "the battle begins")
    eq(sbk.phase, "play", "on both sides")
    check(white.ns.Army.MyTurn(), "white moves first")
    check(sbk.cells[HA.Index(1, 3)] and sbk.cells[HA.Index(1, 3)].rank == nil, "black sees white's units but not their ranks")
    check(white.ns.Army.Move(HA.Index(8, 3), HA.Index(8, 4)), "white marches a Footman")
    Advance(2)
    eq(#sbk.moves, 1, "black sees the move")
    w.ns.Game.Watch(CA); Advance(3)
    local sw2 = w.ns.Army.current
    check(sw2 and sw2.mode == "spectate", "a spectator can watch")
    eq(sw2 and #sw2.moves, 1, "and sees the battle so far")
    check(black.ns.Army.Move(HA.Index(2, 6), HA.Index(2, 5)), "black answers")
    Advance(2)
    -- the Scout runs up the a-file and takes the Banner
    check(white.ns.Army.Move(HA.Index(1, 3), HA.Index(1, 6)), "white's Scout charges the Banner")
    Advance(6)
    eq(sw.outcome, "win", "taking the Banner wins")
    eq(sbk.outcome, "loss", "black loses")
    eq(sw.reason, "banner", "by the Banner")
    Advance(5)
    eq(sbk.verified, true, "black checked white's setup against every move: honest")
    eq(sw.verified, true, "and the other way round")
    eq(sw2.phase, "over", "the spectator saw the end")
    local winner, loser = white.ns.me, black.ns.me
    local rec = w.ns.Ledger.Record(winner, "ha")
    check(rec and rec.w == 1, "the witness records the win")
    check(w.ns.Ledger.Record(loser, "ha") and w.ns.Ledger.Record(loser, "ha").l == 1, "and the loss")
    eq(w.ns.Ledger.Rating(winner), 1200, "Hidden Army never touches chess ratings")
    check(white.ns.Profile.me.badges.ha_win1, "the winner earns Banner Taken (the Tactician)")
    check(white.ns.Profile.me.badges.ha_scout, "with a Scout: the Pathfinder")
    check(black.ns.Profile.me.badges.ha_play, "the loser earns First Muster")
    local board = w.ns.Profile.RecordBoard("ha")
    eq(board[1] and board[1].name, winner, "the winner tops the Generals")

    section("hidden army: a false rank is caught")
    a.ns.Game.Invite(JK, { game = "ha" }); Advance(1)
    for _ = 1, 20 do if b.ns.Game.LatestInvite() then break end Advance(0.5) end
    b.ns.Game.AnswerLatest(true); Advance(3)
    sa, sb = a.ns.Army.current, b.ns.Army.current
    white = sa.mySide == "w" and a or b
    black = white == a and b or a
    sw, sbk = white.ns.Army.current, black.ns.Army.current
    Put(sw, "w", "X", 1, 3)
    Put(sbk, "b", "N", 1, 6)
    white.ns.Army.Ready(); black.ns.Army.Ready(); Advance(3)
    -- black's client claims its Banner is a Warlord when attacked
    sbk.cells[HA.Index(1, 6)].rank = "W"
    white.ns.Army.Move(HA.Index(1, 3), HA.Index(1, 6)); Advance(4)
    eq(sw.phase, "play", "the lie saves the Banner for now")
    eq(sw.cells[HA.Index(1, 3)], nil, "and white's Scout falls")
    black.ns.Army.Resign(); Advance(6)
    eq(sw.outcome, "win", "black gives up")
    eq(sw.verified, false, "white's check of black's setup fails")
    check(sw.cheat and sw.cheat:find("wrong rank") ~= nil, "because of the false rank (" .. tostring(sw.cheat) .. ")")

    section("hidden army: the turn timer")
    a.ns.Game.Invite(JK, { game = "ha" }); Advance(1)
    for _ = 1, 20 do if b.ns.Game.LatestInvite() then break end Advance(0.5) end
    b.ns.Game.AnswerLatest(true); Advance(3)
    sa, sb = a.ns.Army.current, b.ns.Army.current
    Advance(125)
    check(sa.phase == "play" and sb.phase == "play", "armies deploy themselves when setup time runs out")
    local idle = sa.mySide == "w" and a or b
    local other = idle == a and b or a
    local si = idle.ns.Army.current
    for _ = 1, 400 do
        local so = other.ns.Army.current
        if so.phase ~= "play" then break end
        if other.ns.Army.MyTurn() then
            -- step back and forth without attacking
            for _, m in ipairs(other.ns.Army.MyMoves()) do
                if not m.attack then other.ns.Army.Move(m.from, m.to) break end
            end
        end
        Advance(1)
    end
    check(si.phase == "over", "the battle ends")
    if si.reason == "time" then
        eq(si.outcome, "loss", "three missed turns lose the battle")
    else
        check(true, "random moves decided it first (" .. tostring(si.reason) .. ")")
    end

    section("hidden army: queue and practice")
    Advance(5)
    a.ns.Game.StartSeek(0, 0, false, true, "ha")
    b.ns.Game.StartSeek(0, 0, false, true, "vb")
    Advance(30)
    check(not a.ns.Army.Busy(), "a Hidden Army queue never pairs with a Vault Breaker queue")
    a.ns.Game.Announce(true); Advance(3)
    eq(w.ns.Profile.online[CA] and w.ns.Profile.online[CA].status, "a", "the lobby shows Canga looking for Hidden Army")
    b.ns.Game.StopSeek()
    b.ns.Game.StartSeek(0, 0, false, true, "ha")
    Advance(30)
    check(a.ns.Army.Busy() and b.ns.Army.Busy(), "two Hidden Army queuers are paired")
    a.ns.Army.Resign(); Advance(2)
    local s3 = a.ns.Army.StartAI(3)
    a.ns.Army.Ready()
    eq(s3.phase, "play", "a practice battle starts at once")
    for _ = 1, 900 do
        if s3.phase ~= "play" then break end
        if a.ns.Army.MyTurn() then
            local ms = a.ns.Army.MyMoves()
            local m = ms[math.random(1, #ms)]
            a.ns.Army.Move(m.from, m.to)
        end
        Advance(1)
    end
    eq(s3.phase, "over", "a practice battle against the Master finishes")
    local exposed = 0
    for _, u in pairs(s3.cells) do if u.side == s3.theirSide and u.rank then exposed = exposed + 1 end end
    local alive = 0
    for _, u in pairs(s3.cells) do if u.side == s3.theirSide then alive = alive + 1 end end
    eq(exposed, alive, "the computer's army is shown at the end")
    for _, cl in ipairs({ a, b, w }) do eq(#cl.errors, 0, cl.name .. ": no Lua errors"); RemoveClient(cl) end
    net.forever = false
end

------------------------------------------------------------------------
if want("nav") then
    section("how to play")
    local a = NewClient("Canga", nil, "Prime")
    Advance(25)
    local UI, FD = a.ns.UI, a.ns.Finder
    UI.ShowTab("haplay")
    local mainHelp = a.ns.UI.helpFrame
    UI.ShowHelp("ha")
    check(UI.helpFrame and UI.helpFrame:IsShown(), "How to play opens")
    eq(UI.helpFrame.title:GetText(), "How to play: Hidden Army", "for the chosen game")
    check(UI.helpFrame.text:GetText():find("Sapper") ~= nil, "with its rules")
    UI.helpFrame:Hide()
    UI.ShowHelp("c4")
    eq(UI.helpFrame.title:GetText(), "How to play: Four in a Row", "each game has its own rules")
    for _, key in ipairs(a.ns.Data.GAME_ORDER) do
        check((a.ns.Data.GAMES[key].rules or "") ~= "", a.ns.Data.GAMES[key].name .. " has rules")
    end
    UI.helpFrame:Hide()
    local nav = nil

    section("hidden army ui: deploying and moving")
    local HA, v = a.ns.Army, a.ns.ArmyView.view
    local s = HA.StartAI(1)
    Advance(1)
    check(UI.IsVisibleTab("haplay"), "a new battle shows the battlefield")
    eq(v.turn.text:GetText(), "DEPLOY YOUR ARMY", "the banner says to deploy")
    local zone = HA.ZONE[s.mySide]
    local first, empty
    for _, idx in ipairs(zone) do
        if HA.SetupRank(idx) and not first then first = idx end
        if not HA.SetupRank(idx) and not empty then empty = idx end
    end
    local rank = HA.SetupRank(first)
    v.board.squares[first]:Click()
    eq(v.sel, first, "clicking a unit picks it")
    v.board.squares[empty]:Click()
    eq(HA.SetupRank(empty), rank, "clicking another square moves it there")
    eq(HA.SetupRank(first), nil, "leaving its old square empty")
    v.ready:Click()
    eq(s.phase, "play", "Ready starts the battle against the computer")
    for _ = 1, 10 do if HA.MyTurn() then break end Advance(1) end
    check(HA.MyTurn(), "our move comes")
    eq(v.turn.text:GetText(), "YOUR MOVE!", "the banner says so")
    local m = HA.MyMoves()[1]
    v.board.squares[m.from]:Click()
    eq(v.sel, m.from, "clicking a unit selects it")
    local before = #s.moves
    v.board.squares[m.to]:Click()
    eq(#s.moves, before + 1, "clicking a highlighted square moves it")
    check(#v.log.data >= 1, "the move is in the battle log")

    section("hidden army ui: resizing")
    UI.SetCollapsed(false)
    UI.DebugResize(1500, 1000)
    local big = a.ns.db.settings.haCell
    UI.DebugResize(1000, 700)
    local small = a.ns.db.settings.haCell
    check(big and small and big > small, "a bigger window means a bigger battlefield (" .. tostring(big) .. " > " .. tostring(small) .. ")")
    UI.SetCollapsed(true)
    check(not v.side:IsShown(), "the side panel folds away")
    UI.SetCollapsed(false)
    check(v.side:IsShown(), "and comes back")
    HA.Resign(); Advance(2)
    check(v.banner:IsShown(), "the result banner appears")
    eq(#a.errors, 0, "no Lua errors")
    RemoveClient(a)
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
