# Flightpath Legends

Board games to play with other players while you're on a flight path or auto-running in WoW Forever (interface 16001). Everything uses Warcraft artwork and sounds from the game itself.

- **Chess:** Horde vs Alliance pieces with character portraits, rated (Elo and leagues) or casual, plus a computer opponent.
- **Battleship:** the Garrison Shipyard fleet on a naval-map sea. Results are wins and losses, there's a computer admiral, and fleets are sealed so nobody can cheat.
- **Shared:** a lobby, Live Battles to watch, player profiles, titles for every feat, and witnessed results that nobody can fake.

## Install
1. Download `FlightpathLegends-2.0.0.zip` from the [latest release](https://github.com/Blinklabs-hub/FlightpathLegends/releases/latest).
2. Unzip it and copy the `FlightpathLegends` folder (the one with `FlightpathLegends.toc` inside) to `World of Warcraft\_forever_\Interface\AddOns\`.
3. Delete any old `CheckmateAzeroth` or `ChessPvP` folder from that AddOns folder. Your saved data carries over.
4. Restart WoW completely and type `/fpl`, or click the knight button. `/chess` and `/battleship` open a game directly.

You can only play people who also have this addon installed.

## Layout
| File | Purpose |
|---|---|
| `Core.lua` | Namespace, event bus, saved variables, slash commands |
| `Hash.lua` | SHA-256 in plain Lua, used to seal Battleship fleets |
| `Data.lua` | Ranks, leagues, feats and titles, board themes, piece styles, time controls |
| `Assets.lua` | Warcraft art and sounds from the game client (checked at runtime, with fallbacks), armies, character identity, animation engine |
| `Engine.lua`, `AI.lua` | Chess rules and the chess computer |
| `Profile.lua` | Your profile, feats, leaderboards |
| `Comm.lua` | Addon messages over whispers, the hidden `FPLegendsNet` channel, and guild or party |
| `Ledger.lua` | Witnessed results: chess ratings and records, and the Battleship win/loss record |
| `Game.lua` | Chess sessions, challenges and queues for both games, spectating, lobby announcements |
| `Battleship.lua` | Battleship rules, sealed fleets, computer admirals, online play |
| `UI_*.lua` | Main window and game hub, chess board, Battleship view, tabs, profile card |

## Tools
These need Node.js. Run them from `tools/` after `npm install`.
- Tests: `node run.js ../FlightpathLegends tests.lua` covers both games' rules, the computer opponents, simulated multi-player online games including cheating attempts, and the interface.
- Textures: `node gen_textures.js ../FlightpathLegends/Textures` rebuilds the generated art.
