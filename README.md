# EasyTexMod

One double-click to launch any game with all your TexMod texture packs loaded.

[TexMod](https://www.moddb.com/downloads/texmod4) is the classic tool for loading `.tpf` texture packages into DirectX 9 games — but it has no command line, no config file, and no memory: every single time you play you have to open it, browse to the game exe, browse to each `.tpf`, and click Run. **EasyTexMod automates all of that.**

```
[18:34:24] Launching TexMod: ...\TexMod.exe
[18:34:26] Target game set: window title is now 'TexMod - SPEED.EXE'
[18:34:29] Loading mod 1/1: DefiniteveTextures.tpf
[18:34:29] Clicking Run...
[18:35:47] Game window appeared after 78s.
[18:35:49] Game brought to the foreground. Have fun!
```

## Why another TexMod automator?

Existing tools drive TexMod's GUI with blind coordinate clicks and fixed timings, which breaks with different DPI scaling, resolutions, Windows languages, or TexMod builds. EasyTexMod instead talks **directly to TexMod's window controls through Win32 messages** (`BM_CLICK`, `WM_SETTEXT`), addressed by control ID — and it *verifies* every step actually happened (window title changed, package appeared in the list, game process spawned, game window visible) before moving on.

It's a single PowerShell script. No dependencies, nothing to install.

## Features

- Launches TexMod, selects the game, loads every `.tpf` from the `Mod` folder, clicks Run
- Optional explicit **load order** via the ini (some mods care about priority)
- Waits for the game window and **brings it to the foreground** (big packs can take minutes to inject — go ahead and alt-tab, the game will jump to the front when it's ready)
- Closes TexMod automatically when you quit the game (optional)
- Clear progress output + `EasyTexMod.log` for troubleshooting

## Setup

1. Download this repository (Code → Download ZIP) and copy these files **into your game's folder** (next to the game's `.exe`):
   - `EasyTexMod.ps1`
   - `EasyTexMod.bat`
   - `EasyTexMod.ini`
   - `TexMod.exe` (included here for convenience; any TexMod 0.9b works)
   - the `Mod` folder
2. Drop your `.tpf` texture packages inside the `Mod` folder.
3. Open `EasyTexMod.ini` in Notepad and set your game's executable:
   ```ini
   Game=YourGame.exe
   ```
4. Double-click **`EasyTexMod.bat`**. That's it.

> You don't have to install it in the game folder — every path in the ini also accepts absolute paths (e.g. `Game=C:\Games\MyGame\game.exe`), so you can keep EasyTexMod anywhere.

## Configuration (`EasyTexMod.ini`)

| Key | Default | What it does |
|---|---|---|
| `TexMod` | `TexMod.exe` | Path to TexMod |
| `Game` | — | Game executable TexMod will launch |
| `ModFolder` | `Mod` | Folder containing your `.tpf` files |
| `Delay` | `300` | Pause (ms) between UI actions — raise it on slow PCs |
| `AutoRun` | `1` | `1` = click Run automatically; `0` = leave TexMod open, you click Run |
| `CloseTexModOnExit` | `1` | Close TexMod when the game exits |

### Load order

Leave `[LoadOrder]` empty to load every `.tpf` in `ModFolder` alphabetically, or list files one per line to control priority (first line loads first):

```ini
[LoadOrder]
MainTexturePack.tpf
SmallFixesOnTop.tpf
```

### Command-line switches

- `EasyTexMod.bat -NoRun` — load everything but don't click Run (inspect TexMod first)
- `EasyTexMod.bat -TestMode` — full run, then automatically kill the game and TexMod (for testing a new setup)

## Good to know

- **Big texture packs take a while.** TexMod decompresses the whole package *inside* the game process at startup — a 300 MB pack means roughly a minute of black screen / no window. EasyTexMod prints progress and warns you; don't click Run again, and don't worry: the game jumps to the foreground when it's ready.
- **The game window never shows up?** Check `EasyTexMod.log`. If the game process died, open TexMod yourself and click Run to see TexMod's own error message.
- **Automation fails on a slow PC?** Raise `Delay` in the ini (e.g. `600`).
- **Game/TexMod needs administrator rights?** Then run `EasyTexMod.bat` as administrator too — Windows blocks automation messages from a normal process to an elevated one.
- **TexMod.exe gets flagged by your antivirus?** That's a well-known false positive with TexMod (it injects into the game — that's literally its job). Add an exception, or download TexMod yourself from a source you trust and point the ini at it.

## Credits

- **TexMod** was created by RS — all credit for the actual texture magic goes to them. It's included in this repo unmodified, purely for convenience; if you prefer, grab your own copy (e.g. from [ModDB](https://www.moddb.com/downloads/texmod4)) and replace it.
- EasyTexMod script written with Claude.
