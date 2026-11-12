# ChessPvP

A chess addon for WoW Forever (interface 16001). You can play other players who have the addon, and there is a realm ladder, rank titles, badges, and board and piece unlocks.

## Install
1. Download `ChessPvP-1.0.0.zip` from the [latest release](https://github.com/Blinklabs-hub/ChessPvP/releases/latest).
2. Unzip it and copy the `ChessPvP` folder (the one with `ChessPvP.toc` inside) to `World of Warcraft\_forever_\Interface\AddOns\`.
3. Start the game and type `/chess`, or click the knight button.

You can only play people who also have the addon installed.

## Layout
| File | Purpose |
|---|---|
| `Core.lua` | Namespace, event bus, saved variables, slash commands |
| `Engine.lua` | Chess rules: legal moves, check, mate, draws, SAN |
| `AI.lua` | Practice computer at 3 levels. It thinks in short slices so the game doesn't freeze |
| `Data.lua` | Rank titles, badges, board themes, piece sets, time controls |
| `Profile.lua` | Elo rating, stats, badge and unlock checks, ladder cache |
| `Comm.lua` | Addon-message transport with throttling, plus the hidden `ChessPvPNet` channel |
| `Game.lua` | Sessions, clocks, challenges, matchmaking, resume after /reload, spectating |
| `UI_Board.lua`, `UI_Main.lua` | Board widget and the main window |

## Tools
These need Node.js. Run them from `tools/` after `npm install`.
- Tests: `node run.js ../ChessPvP tests.lua` runs the rules perft suite, the AI checks, and simulated multi-client online games.
- Textures: `node gen_textures.js ../ChessPvP/Textures` rebuilds the piece art.
